class_name SimNpcCombat
extends RefCounted

# NPC survivors fight from where they are standing.
#
# docs/09: "NPCs fight autonomously from their post and Focus, using their loadout and web. They
# break off when critically injured, per traits."
#
# This is an *intake*, not a second combat model. `melee.resolve` and `ranged.resolve` already
# query on position/facing and know nothing about who is acting -- only the two command intakes
# were gated on `controlled`. So the whole of NPC combat is: pick a threat, turn to face it, and
# start the same swing or shot a key press would have started, through
# `SimMelee.try_begin_swing` / `SimRanged.try_begin_fire`. Every precondition -- stamina, ammo,
# posture, grabs, reload-when-empty -- is inherited rather than restated.
#
# It never sets a velocity. Engaging is something a guard does *from* the gate; a post that
# chases is not a post, and `jobs.gd` stays the only thing that decides where a survivor stands.

const SimAllegiance = preload("res://sim/modules/allegiance.gd")
const SimAimRes = preload("res://sim/aim.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimCombat = preload("res://sim/combat.gd")
const SimShamblerRes = preload("res://sim/modules/shambler.gd")
const SimSightingsRes = preload("res://sim/modules/sightings.gd")
const SimSpaceRes = preload("res://sim/space/space.gd")

# How close a threat comes before an NPC decides to spend a shot on it, capped again by the
# weapon's own `rangeMetres`. This is a *pacing* constant -- "close enough to be worth the noise"
# -- and deliberately not a sightline rule. The sightline rule has since landed where this note
# said it would: `SimRanged.can_target` refuses the player and the colony with one test, and
# `_nearest_threat` below asks it rather than carrying a second answer.
const ENGAGE_METRES: float = 20.0

# Colonists come to the held player's aid (2026-11-07). A colonist that can see a zombie holding a controlled body,
# or Pursuing one within AID_PURSUE_METRES of it, and that is within AID_METRES of the zombie, is given an attack order
# on it through the order seam (orders.gd `issue`): the walk and the rescue are then the existing ones. One aider per
# zombie, and at most one issue per colonist per AID_RETRY_TICKS, so a colonist is not re-ordered every tick. Owner
# card: default 24 m and 4 m. The raiders and the settlers do not aid.
const AID_METRES: float = 24.0
const AID_PURSUE_METRES: float = 4.0
const AID_RETRY_TICKS: int = 60

# How long the controlled survivor goes without a single command before instinct answers a claw
# for them -- SimShambler.STRUGGLE_INSTINCT_TICKS' number and its exact reasoning: two seconds is
# long enough that an attentive player's own key is always the thing that answers an attack, and
# short enough that nobody stands still being clawed because there is nobody at the keyboard --
# which is the balance harness's permanent condition, and became a wipe the day zombies got an
# attack. The diagnosis driver measured the chain: the passive player dies, succession promotes a
# colonist into the same passivity, and one shambler eats the successor over 41 unanswered
# swipes. ANY command resets the clock -- a move, an aim, a wait -- so a player who is present is
# never overridden: not aiming past a zombie, not holding still on purpose, not fleeing.
const DEFEND_INSTINCT_TICKS: int = 40

# Critically injured, per docs/09 -- and expressed in `SimHealth.part_state`'s words rather than
# in integrity numbers. Each part has its own maximum (a head is 15, a hand 10, a torso 40), so an
# absolute threshold would mean something different on every part; `part_state` is the one place
# that normalises, and reusing it means this module carries no second scale and no raw integrity.
#
# A trait moves the threshold by one rung rather than changing the decision. `squeamish` and
# `iron_stomach` are the two the generator already rolls that mean "how much of this can you
# stand", and are the two `needs.gd` already reads for the same reason.
const BREAK_OFF_STATE: int = SimHealth.PartState.BadlyHurt
const BREAK_OFF_SQUEAMISH: int = SimHealth.PartState.Hurt
const BREAK_OFF_IRON_STOMACH: int = SimHealth.PartState.Unusable

# combat.gd's list, not a second copy of it -- the same rule condition.gd states.
const PARTS: Array[String] = SimCombat.SURVIVOR_BODY_PARTS


static func register_module(world: Variant) -> void:
	# combat/-5: after `movement.integrate` has set facing from velocity (or this tick's turn to
	# face a threat would be overwritten by the walk), and before `melee.resolve` at 0 and
	# `ranged.resolve` at 1 read that facing. Same tick, same order the player's key press gets.
	world.systems.register("npc.combat", "combat", -5, func(w: Variant) -> void:
		if bool(w.runOver) if "runOver" in w else false:
			return
		# Asked once per tick rather than once per NPC, and asked of `count` rather than `query`,
		# which sorts: this runs every tick of every campaign and answers "no" on almost all of
		# them. It is what widens the engagement envelope below, and only while somebody is held.
		var anyone_held: bool = w.components.count("grabbed") > 0
		for ent in _combatants(w):
			if not _engages(w, int(ent)):
				continue
			_engage(w, int(ent), anyone_held)
	)

	# Instinct defense: the controlled survivor, unattended, answers a claw already in melee
	# reach with the swing a key press would have started. The struggle instinct's twin (see
	# DEFEND_INSTINCT_TICKS above), and melee only -- instinct is flailing at the thing on you,
	# not marksmanship. Restricted to a *Pursuing* threat so it can never open a fight: a
	# shambler that has not noticed anybody draws no swing and no noise from it.
	# Aid runs before the combat intake, so an order given this tick is what the walk and the swing read.
	world.systems.register("npc.aid", "combat", -6, func(w: Variant) -> void:
		_aid_colonists(w)
	)

	world.systems.register("npc.instinct-defense", "combat", -4, func(w: Variant) -> void:
		var any_command: bool = not (w.commands.current as Array).is_empty()
		for ent in w.components.query(["controlled", "position", "facing"]):
			var attended: Variant = w.components.get_component(int(ent), "attended")
			if not (attended is Dictionary):
				attended = {"idleTicks": 0}
				w.components.set_component(int(ent), "attended", attended)
			var a: Dictionary = attended as Dictionary
			a["idleTicks"] = 0 if any_command else int(a.get("idleTicks", 0)) + 1
			if int(a["idleTicks"]) < DEFEND_INSTINCT_TICKS:
				continue
			var reach: float = _melee_reach(w, int(ent))
			if reach <= 0.0:
				continue
			var threat: int = _nearest_threat(w, int(ent), reach)
			if threat < 0:
				continue
			var sd: Variant = w.components.get_component(threat, "shambler")
			if not (sd is Dictionary) or int((sd as Dictionary)["state"]) != SimShamblerRes.ShamblerState["Pursue"]:
				continue
			# A claw through a wall, or a window the blow cannot cross, is not a claw on you: no
			# swing that `_resolve_strike` would only refuse (#282).
			if not _in_reach(w, int(ent), threat, reach):
				continue
			_face(w, int(ent), threat)
			SimMelee.try_begin_swing(w, int(ent))
	)


# Everybody this module is an intake for: the colony (`needs`), the band at the gate (`raider`),
# and the camp out in the district (the settlers faction). Three queries rather than one on
# `allegiance`, deliberately -- the colony's own gate fixtures build an NPC out of `needs` + a body
# and nothing else, and re-rooting the roster on a component they do not carry would have silently
# stopped them fighting. Sorted, because `components.query` sorts and an engagement order that
# depended on table iteration would not survive a save/load.
#
# **The third query is the settlers slice's one honest option, and the two it is not are worth
# naming.** A settler has no `needs` and no `jobPriorities`, and that is not an oversight: those
# two components are what the colony's books are keyed on -- `check_m2_balance.gd`'s
# `_survivors_alive` counts `needs` + `body`, and `jobs.gd` queries `jobPriorities` + `identity`.
# So *giving* a settler `needs` to get them in here would put a camp on the colony's ledger and
# its work panel, which the camp slice went out of its way to prevent; and *widening* the first
# query to something every body carries would change which bodies this module schedules for
# everybody, colonists included. Asking for the third faction **by name** changes the roster by
# exactly the bodies it names and nothing else, which is how the raiders were added to this same
# function and is the only one of the three that can be read at a glance.
# The order seam is loaded at run time: orders.gd preloads jobs.gd, which preloads this file, so a preload here
# would be a ring.
static func _orders() -> GDScript:
	return load("res://sim/modules/orders.gd") as GDScript


static func _aid_colonists(world: Variant) -> void:
	var holders: Array[int] = []
	for c in world.components.query(["controlled", "position"]):
		holders.append(int(c))
	if holders.is_empty():
		return
	var orders: GDScript = _orders()
	for ent in _combatants(world):
		var e: int = int(ent)
		if SimAllegiance.faction_of(world, e) != SimAllegiance.COLONY:
			continue
		if not _engages(world, e) or not bool(orders.call("takes_orders", world, e)):
			continue
		if bool(orders.call("holds", world, e)):
			continue
		var body: Variant = world.components.get_component(e, "body")
		if body is Dictionary and _critically_injured(world, e, body as Dictionary):
			continue
		var issued: Variant = world.components.get_component(e, "aidIssued")
		if issued is Dictionary and int(world.tick) - int((issued as Dictionary).get("tick", -100000)) < AID_RETRY_TICKS:
			continue
		var target: int = _aid_target(world, e, holders)
		if target < 0:
			continue
		if bool(orders.call("issue", world, {"type": "colonist.order", "entity": e, "kind": "attack", "target": target})):
			world.components.set_component(e, "aidIssued", {"tick": int(world.tick)})


# The zombie this colonist goes to: the nearest that it can see, that holds a holder or is Pursuing one within reach
# of it, and that no other colonist already has an order on.
static func _aid_target(world: Variant, ent: int, holders: Array[int]) -> int:
	var best: int = -1
	var best_d: float = INF
	for z in world.components.query(["shambler", "position"]):
		var zed: int = int(z)
		if not world.entities.is_alive(zed) or world.components.has_component(zed, "corpse"):
			continue
		var zp: Dictionary = world.components.get_component(zed, "position") as Dictionary
		var zv := Vector2(float(zp["x"]), float(zp["y"]))
		var holds_one: bool = false
		var hold: Variant = world.components.get_component(zed, "grabState")
		if hold is Dictionary and holders.has(int((hold as Dictionary)["victim"])):
			holds_one = true
		var pursuing: bool = false
		if not holds_one and int((world.components.get_component(zed, "shambler") as Dictionary).get("state", -1)) == SimShamblerRes.ShamblerState["Pursue"]:
			for h in holders:
				var hp: Dictionary = world.components.get_component(h, "position") as Dictionary
				if zv.distance_to(Vector2(float(hp["x"]), float(hp["y"]))) <= AID_PURSUE_METRES:
					pursuing = true
					break
		if not holds_one and not pursuing:
			continue
		var d: float = _distance(world, ent, zed)
		if d > AID_METRES:
			continue
		if not SimRanged.can_target(world, ent, zv.x, zv.y):
			continue
		if _aided(world, zed):
			continue
		if d < best_d:
			best_d = d
			best = zed
	return best


# Another colonist already has an attack order on this zombie.
static func _aided(world: Variant, zed: int) -> bool:
	for c in world.components.query(["colonistOrder"]):
		var order: Dictionary = world.components.get_component(int(c), "colonistOrder") as Dictionary
		if String(order.get("kind", "")) == "attack" and int(order.get("target", -1)) == zed:
			return true
	return false


static func _combatants(world: Variant) -> Array[int]:
	var out: Array[int] = world.components.query(["needs", "position", "facing"])
	for ent in world.components.query(["raider", "position", "facing"]):
		if not out.has(int(ent)):
			out.append(int(ent))
	for ent in world.components.query(["allegiance", "position", "facing"]):
		if SimAllegiance.faction_of(world, int(ent)) != SimAllegiance.SETTLERS:
			continue
		if not out.has(int(ent)):
			out.append(int(ent))
	out.sort()
	return out


# The roster of people this module is allowed to act for: survivors who are not the one the
# player is driving, and not otherwise out of play. Mirrors `jobs.gd:_tick`'s exclusions --
# a corpse, a leaver and an unrecruited stranger are all still `needs` carriers.
static func _engages(world: Variant, ent: int) -> bool:
	if world.components.has_component(ent, "controlled"):
		return false
	if int(ent) == int(world.player):
		return false
	for out_of_play in ["recruit", "leaving", "corpse", "grabbed", "sleeping"]:
		if world.components.has_component(ent, out_of_play):
			return false
	if String(SimNeeds.of(world, ent).get("crisis", "none")) == "passed_out":
		return false
	var body: Variant = world.components.get_component(ent, "body")
	if not body is Dictionary or not SimHealth.is_alive(body as Dictionary):
		return false
	return true


static func break_off_state(world: Variant, ent: int) -> int:
	if SimNeeds.has_trait(world, ent, "squeamish"):
		return BREAK_OFF_SQUEAMISH
	if SimNeeds.has_trait(world, ent, "iron_stomach"):
		return BREAK_OFF_IRON_STOMACH
	return BREAK_OFF_STATE


static func _critically_injured(world: Variant, ent: int, body: Dictionary) -> bool:
	var threshold: int = break_off_state(world, ent)
	for part in PARTS:
		var state: Variant = SimHealth.part_state(body, part)
		if state != null and int(state) >= threshold:
			return true
	return false


static func _engage(world: Variant, ent: int, anyone_held: bool = false) -> void:
	var reach: float = _melee_reach(world, ent)
	# Breaking off is disengagement, not surrender. Until the swipe landed, "critically injured
	# NPCs do not engage" cost nothing -- a zombie could not touch anyone, so standing down and
	# standing there were the same thing. The diagnosis driver measured what that equivalence
	# became the day zombies could claw: a colonist crossed BadlyHurt after three or four swipes,
	# fell out of this module entirely, and was then ground down over 2,460 ticks by the one
	# shambler standing at arm's length -- 41 swipes taken, one swing answered. So the break-off
	# now narrows the envelope instead of closing it: a critically injured survivor spends no
	# shot, seeks no rescue and starts nothing at range, but a claw already inside melee reach is
	# fought, because a person with a knife and a monster on top of them does not stand down.
	# docs/09's clause reads exactly this way -- you break *off*, you do not lie down.
	var defending: bool = false
	var body: Variant = world.components.get_component(ent, "body")
	if body is Dictionary:
		defending = _critically_injured(world, ent, body as Dictionary)
	var range_metres: float = 0.0 if defending else _ranged_range(world, ent)
	var furthest: float = maxf(reach, range_metres)
	# While somebody is being held, the envelope opens to the length of a rescue: the rescuer
	# stands within RESCUE_METRES of the *victim*, and the victim is inside GRAB_METRES of the
	# holder, so a holder worth acting on can be that much further off than a knife reaches. Two
	# consequences, both wanted. Below `furthest <= 0.0`, so somebody with empty hands can still
	# pull -- hands are enough for this and for nothing else. And exactly nothing when nobody is
	# held, which is why every existing target-selection assertion is untouched by it.
	if anyone_held and not defending:
		furthest = maxf(furthest, SimShamblerRes.RESCUE_METRES + SimShamblerRes.GRAB_METRES)
	if furthest <= 0.0:
		return
	var threat: int = _nearest_threat(world, ent, furthest)
	if threat < 0:
		if not defending:
			_shoot_where_it_was(world, ent, range_metres)
		return
	_face(world, ent, threat)
	if defending:
		# Defense is the melee branch alone, and only for a claw already in reach.
		if _in_reach(world, ent, threat, reach):
			SimMelee.try_begin_swing(world, ent)
		return
	# Rescue first, because _nearest_threat has already preferred a shambler with somebody in its
	# hands: if the thing this NPC just turned to face is holding a colonist and that colonist is
	# within arm's length, hauling them out is worth more than a swing at the holder. An archer
	# standing off keeps shooting -- the reach check is on the *victim*, not on the threat -- and a
	# guard who cannot reach the victim falls straight through to the weapon it is carrying.
	var hold: Variant = world.components.get_component(threat, "grabState")
	if hold is Dictionary:
		var victim: int = int((hold as Dictionary)["victim"])
		if _distance(world, ent, victim) <= SimShamblerRes.RESCUE_METRES:
			if SimShamblerRes.try_begin_rescue(world, ent, victim):
				return
	# Reach first: a shambler at arm's length is a melee problem even for someone holding a bow,
	# and a survivor carrying both should not be raising a weapon while being grabbed. At arm's
	# length means the blow arrives (`_in_reach`, the question `can_strike` asks): a shambler on the
	# far side of a wall or a window the swing cannot cross is no melee problem, and falls through to
	# the shot, exactly as `can_strike` falls through for the attack walk (#282).
	if _in_reach(world, ent, threat, reach):
		if SimMelee.try_begin_swing(world, ent):
			return
	if range_metres > 0.0 and _distance(world, ent, threat) <= range_metres:
		SimRanged.try_begin_fire(world, ent)


# The same reach the swing will resolve against, so an NPC starts a wind-up exactly when a blow
# would land rather than against a second number that could drift from `_resolve_strike`'s.
static func _melee_reach(world: Variant, ent: int) -> float:
	var weapon: Variant = world.components.get_component(ent, "meleeWeapon")
	if not weapon is Dictionary:
		return 0.0
	if not world.components.has_component(ent, "swing"):
		return 0.0
	return float((weapon as Dictionary).get("reachMetres", 1.4)) + SimMelee.MELEE_REACH_FUDGE


static func _ranged_range(world: Variant, ent: int) -> float:
	var weapon: Variant = world.components.get_component(ent, "rangedWeapon")
	if not weapon is Dictionary:
		return 0.0
	# A weapon missing a part it cannot work without has no envelope at all. Without this an NPC
	# holding a barrel-less rifle would walk to sixty metres and stand there for the rest of the
	# campaign taking shots that `try_begin_fire` refuses -- an open circuit of exactly the shape
	# this milestone keeps finding, and the reader that is easiest to forget because nothing
	# crashes.
	if not SimRanged.can_fire(world, ent):
		return 0.0
	return minf(float((weapon as Dictionary).get("rangeMetres", 0.0)), ENGAGE_METRES)


# Nearest, except that a shambler with someone in its hands is dealt with first.
#
# Preference, not a new behaviour: this picks which threat the existing engage does its existing
# thing to. It is safe to be strict about it because `metres` is already the weapon's own
# envelope -- `_engage` passes max(reach, range) -- so every candidate here is one this NPC can
# act on this tick, and preferring a holder can never mean facing something out of range while
# something in range is ignored.
#
# It matters because a held survivor cannot help themselves quickly: melee.gd refuses a grabbed
# body its swing, and the escape is a contest they can lose several times over. The colony's
# answer to a grab is somebody else's weapon, and before this the holder was simply one more
# shambler in the queue -- usually not the closest, because it had stopped moving.
#
# The candidate list used to be `query(["shambler", "position", "body"])` -- "a threat is a
# zombie", which was true right up until an armed human walked in. It is `SimAllegiance.enemies_of`
# now, and that one substitution is the whole of hostility on this side: a colonist fights a
# raider, a raider fights a colonist, and both of them still fight the shambler that arrives while
# they are busy. Every line below it -- the range envelope, the sightline refusal, the holder
# preference -- is untouched and now applies to all three.
static func _nearest_threat(world: Variant, ent: int, metres: float) -> int:
	var ordered: int = _ordered_target(world, ent, metres)
	if ordered >= 0:
		return ordered
	var here: Variant = world.components.get_component(ent, "position")
	if not here is Dictionary:
		return -1
	var hx: float = float((here as Dictionary)["x"])
	var hy: float = float((here as Dictionary)["y"])
	var limit_sq: float = metres * metres
	var best: int = -1
	var best_sq: float = 1e12
	var best_holds: bool = false
	for other in SimAllegiance.enemies_within(world, ent, metres):
		var body: Variant = world.components.get_component(int(other), "body")
		if not body is Dictionary or not SimHealth.is_alive(body as Dictionary):
			continue
		var there: Variant = world.components.get_component(int(other), "position")
		if not there is Dictionary:
			continue
		var dx: float = float((there as Dictionary)["x"]) - hx
		var dy: float = float((there as Dictionary)["y"]) - hy
		var d_sq: float = dx * dx + dy * dy
		if d_sq > limit_sq:
			continue
		# The same refusal the shot itself will make, asked before the NPC turns to face: a
		# colonist who spun towards a shambler through a wall and then declined to fire would
		# look broken in exactly the way the shot's own check would have hidden.
		if not SimRanged.can_target(world, ent, float((there as Dictionary)["x"]), float((there as Dictionary)["y"])):
			continue
		var holds: bool = world.components.has_component(int(other), "grabState")
		# Holding outranks distance; between two of the same kind, distance decides.
		if best >= 0:
			if best_holds and not holds:
				continue
			if best_holds == holds and d_sq >= best_sq:
				continue
		best_sq = d_sq
		best_holds = holds
		best = int(other)
	return best


# The target a colonist was ordered to attack (plan A2), if this colonist can act on it inside
# `metres` right now: alive, hostile, seen, and in the sightline the shot itself would take. The
# player pointed at it, so it outranks every other threat in the envelope. The order's record
# lives in jobs.gd (`ORDER_COMPONENT`, "colonistOrder"); this file cannot preload jobs.gd, because
# jobs.gd preloads this one, so the component name is written out here.
static func _ordered_target(world: Variant, ent: int, metres: float) -> int:
	var order: Variant = world.components.get_component(ent, "colonistOrder")
	if not (order is Dictionary) or String((order as Dictionary).get("kind", "")) != "attack":
		return -1
	var target: int = int((order as Dictionary).get("target", -1))
	if target < 0 or not world.entities.is_alive(target) or world.components.has_component(target, "corpse"):
		return -1
	var body: Variant = world.components.get_component(target, "body")
	if not (body is Dictionary) or not SimHealth.is_alive(body as Dictionary):
		return -1
	if not SimAllegiance.hostile(world, ent, target):
		return -1
	if _distance(world, ent, target) > metres:
		return -1
	var there: Dictionary = world.components.get_component(target, "position") as Dictionary
	if not SimRanged.can_target(world, ent, float(there["x"]), float(there["y"])):
		return -1
	return target


# Whether `target` is inside the blow or the shot this colonist would land right now: the melee reach
# `_engage` swings with, with nothing in the way of the blow (`SimSpace.reach_clear`, the question
# `_resolve_strike` asks), or the ranged envelope with a sightline. Asked by the attack walk, so the
# colonist stops exactly where the fight begins -- and not with a wall between them and it.
static func can_strike(world: Variant, ent: int, target: int) -> bool:
	if _in_reach(world, ent, target, _melee_reach(world, ent)):
		return true
	var d: float = _distance(world, ent, target)
	var range_metres: float = _ranged_range(world, ent)
	if range_metres <= 0.0 or d > range_metres:
		return false
	var there: Dictionary = world.components.get_component(target, "position") as Dictionary
	return SimRanged.can_target(world, ent, float(there["x"]), float(there["y"]))


# Whether a swing `ent` starts now at `target` would arrive: inside `reach` (`_melee_reach`, the
# number `_resolve_strike` measures against) with nothing in the way of the blow
# (`SimSpace.reach_clear`, the question `_resolve_strike` asks). The one melee answer for the attack
# walk (`can_strike`), the engage (`_engage`) and instinct (`npc.instinct-defense`): before #282's
# record the last two asked distance alone, so a colonist at a window wound up swing after swing that
# the resolve refused.
static func _in_reach(world: Variant, ent: int, target: int, reach: float) -> bool:
	if reach <= 0.0 or _distance(world, ent, target) > reach:
		return false
	var here: Variant = world.components.get_component(ent, "position")
	var at: Variant = world.components.get_component(target, "position")
	return here is Dictionary and at is Dictionary and SimSpaceRes.reach_clear(world, here as Dictionary, at as Dictionary, ent, target)


static func _distance(world: Variant, a: int, b: int) -> float:
	var pa: Variant = world.components.get_component(a, "position")
	var pb: Variant = world.components.get_component(b, "position")
	if not pa is Dictionary or not pb is Dictionary:
		return 1e12
	var dx: float = float((pb as Dictionary)["x"]) - float((pa as Dictionary)["x"])
	var dy: float = float((pb as Dictionary)["y"]) - float((pa as Dictionary)["y"])
	return sqrt(dx * dx + dy * dy)


static func _face(world: Variant, ent: int, target: int) -> void:
	var there: Variant = world.components.get_component(target, "position")
	if not there is Dictionary:
		return
	_face_at(world, ent, float((there as Dictionary)["x"]), float((there as Dictionary)["y"]), SimSpaceRes.chest_of(world, target))


# Turning to face a place rather than a body -- what a remembered position is. `_face` is this
# with a lookup in front of it, so a body and the memory of one turn a survivor the same way.
# The head tilts with the turn (docs/40, "Aim: yaw and pitch"): from this body's eye
# (`SimSpace.eye_of`) to `height_mm` at the place, which is the target's chest when `_face` names a
# body and a standing survivor's chest (`SimSpace.chest_of` of no body) when only a place is known.
static func _face_at(world: Variant, ent: int, x: float, y: float, height_mm: int = -1) -> void:
	var here: Variant = world.components.get_component(ent, "position")
	var facing: Variant = world.components.get_component(ent, "facing")
	if not here is Dictionary or not facing is Dictionary:
		return
	var dx: float = x - float((here as Dictionary)["x"])
	var dy: float = y - float((here as Dictionary)["y"])
	if dx == 0.0 and dy == 0.0:
		return
	var radians: float = atan2(dy, dx)
	if radians == 0.0:
		# atan2 reaches negative zero due east, which `canonicalize` means to refuse and cannot see
		# (docs/37). -0.0 == 0.0, so this assignment is the collapse `headingOf` does.
		radians = 0.0
	(facing as Dictionary)["radians"] = radians
	# The aim turns with the body (sim/aim.gd): a proposal the player left behind never points the
	# swing this turn is for.
	SimAimRes.follow_facing(world.components, ent)
	var to_mm: int = height_mm if height_mm >= 0 else SimSpaceRes.chest_of(world, -1)
	SimAimRes.set_pitch(world.components, ent, SimAimRes.pitch_toward(to_mm - SimSpaceRes.eye_of(world, ent), sqrt(dx * dx + dy * dy)))


# Firing at a body you remember rather than one you can see. docs/09: "allowed, and it is a
# decision with a cost -- the shot is 180 noise and 60 of muzzle flash whether or not anything was
# still standing there."
#
# Nothing here pays that cost specially, and that is the point: the noise and the flash are
# published by `_fire_shot` before the hit test, and the round is spent before it, so a shot at an
# empty patch of street already costs everything a hit costs except the hit. The only thing this
# adds is the *decision* -- a colonist who has lost sight of the thing coming for them can put a
# round where it was, which is the option the player has always had by pointing and pressing F.
#
# Only reached when `_nearest_threat` found nothing, so a visible target always outranks a
# remembered one, and only for a survivor holding something that shoots -- there is no melee
# equivalent of swinging at a place.
static func _shoot_where_it_was(world: Variant, ent: int, range_metres: float) -> void:
	if range_metres <= 0.0:
		return
	var row: Variant = SimSightingsRes.freshest_within(world, ent, range_metres)
	if not row is Dictionary:
		return
	# Stale is stale: a memory the survivor would describe as "a while ago" is not a firing
	# solution, and spending a round and 180 of noise on one would be the colony wasting the
	# ammunition the player has to go out and find.
	if int(SimSightingsRes.freshness(int((row as Dictionary)["age"]))) > SimSightingsRes.Freshness.Recent:
		return
	_face_at(world, ent, float((row as Dictionary)["x"]), float((row as Dictionary)["y"]))
	SimRanged.try_begin_fire(world, ent)
