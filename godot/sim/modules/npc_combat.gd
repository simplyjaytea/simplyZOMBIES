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

const SimMelee = preload("res://sim/modules/melee.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimCombat = preload("res://sim/combat.gd")
const SimShamblerRes = preload("res://sim/modules/shambler.gd")
const SimSightingsRes = preload("res://sim/modules/sightings.gd")

# How close a threat comes before an NPC decides to spend a shot on it, capped again by the
# weapon's own `rangeMetres`. This is a *pacing* constant -- "close enough to be worth the noise"
# -- and deliberately not a sightline rule. The sightline rule has since landed where this note
# said it would: `SimRanged.can_target` refuses the player and the colony with one test, and
# `_nearest_threat` below asks it rather than carrying a second answer.
const ENGAGE_METRES: float = 20.0

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
		for ent in w.components.query(["needs", "position", "facing"]):
			if not _engages(w, int(ent)):
				continue
			_engage(w, int(ent), anyone_held)
	)

	# Instinct defense: the controlled survivor, unattended, answers a claw already in melee
	# reach with the swing a key press would have started. The struggle instinct's twin (see
	# DEFEND_INSTINCT_TICKS above), and melee only -- instinct is flailing at the thing on you,
	# not marksmanship. Restricted to a *Pursuing* threat so it can never open a fight: a
	# shambler that has not noticed anybody draws no swing and no noise from it.
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
			_face(w, int(ent), threat)
			SimMelee.try_begin_swing(w, int(ent))
	)


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
		if reach > 0.0 and _distance(world, ent, threat) <= reach:
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
	# and a survivor carrying both should not be raising a weapon while being grabbed.
	if reach > 0.0 and _distance(world, ent, threat) <= reach:
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
static func _nearest_threat(world: Variant, ent: int, metres: float) -> int:
	var here: Variant = world.components.get_component(ent, "position")
	if not here is Dictionary:
		return -1
	var hx: float = float((here as Dictionary)["x"])
	var hy: float = float((here as Dictionary)["y"])
	var limit_sq: float = metres * metres
	var best: int = -1
	var best_sq: float = 1e12
	var best_holds: bool = false
	for other in world.components.query(["shambler", "position", "body"]):
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
	_face_at(world, ent, float((there as Dictionary)["x"]), float((there as Dictionary)["y"]))


# Turning to face a place rather than a body -- what a remembered position is. `_face` is this
# with a lookup in front of it, so a body and the memory of one turn a survivor the same way.
static func _face_at(world: Variant, ent: int, x: float, y: float) -> void:
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
		# atan2 reaches negative zero due east, which `canonicalize` rejects outright. -0.0 == 0.0,
		# so this assignment is the collapse `headingOf` does.
		radians = 0.0
	(facing as Dictionary)["radians"] = radians


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
