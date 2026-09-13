extends SceneTree
# NPC combat from assigned posts -- docs/09's "NPCs fight autonomously from their post and Focus
# ... they break off when critically injured, per traits".
#
# Every assertion here carries a true positive AND a true negative, the convention
# check_ban_health_bar.gd set after a field that was always false passed a "no leak" test. An
# NPC that never swings would satisfy "does not swing across the district" perfectly.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimAttachments = preload("res://sim/modules/attachments.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimNpcCombat = preload("res://sim/modules/npc_combat.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const Clock = preload("res://sim/time/clock.gd")

const ARENA_SEED: int = 4242
const ARENA_TICKS: int = 900

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _armed_npc_kills_what_walks_into_reach() and ok
	ok = _ranged_npc_spends_its_ammunition() and ok
	ok = _critically_injured_breaks_off() and ok
	ok = _distance_and_silence_are_both_negative_controls() and ok
	ok = _a_guard_engages_without_leaving_its_post() and ok
	ok = _a_shambler_with_someone_in_its_hands_is_shot_first() and ok
	ok = _hands_before_weapons_when_somebody_is_being_held() and ok
	ok = _an_unattended_survivor_answers_the_claw() and ok
	ok = _a_dropped_weapon_is_picked_back_up() and ok
	ok = _nobody_closes_on_a_gun_that_cannot_fire() and ok
	ok = _armour_that_is_found_gets_worn() and ok
	ok = _nobody_swaps_down_to_worse_armour() and ok
	ok = _two_colonists_do_not_walk_to_one_vest() and ok
	if ok:
		print("M2_NPC_COMBAT_OK melee ranged breakoff quiet post holder rescue instinct blocked dress selective claim")
		quit(0)
	else:
		push_error("M2_NPC_COMBAT_FAIL")
		quit(1)


# A bare arena with the combat modules and no shambler AI: the target stands still so the thing
# under test is the intake deciding to act, not a chase. The post test below uses the real
# district, where everything moves.
func _arena() -> Variant:
	var fixture: Dictionary = {
		"seed": ARENA_SEED,
		"tick_hz": 20,
		"map": {"width": 32, "height": 32, "walls": []},
		"player": {"id": 0, "x": 2.0, "y": 2.0, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	}
	var w: Variant = World.new(fixture)
	w.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	var map: Variant = SimTileMap.blank_map(32, 32)
	SimBoot.attach_kernel(w, map)
	SimHealth.register_module(w)
	SimMelee.register_module(w)
	SimRanged.register_module(w)
	SimInventory.register_module(w)
	SimItems.register_module(w)
	SimNpcCombat.register_module(w)
	return w


# A survivor who is not the one the player is driving: needs, a body, a facing, and no
# `controlled` component. That absence is the whole point of the module.
func _npc(w: Variant, x: float, y: float, traits: Array = []) -> int:
	var ent: int = int(w.entities.spawn())
	w.components.set_component(ent, "position", {"x": x, "y": y})
	w.components.set_component(ent, "velocity", {"dx": 0.0, "dy": 0.0})
	w.components.set_component(ent, "facing", {"radians": 0.0})
	w.components.set_component(ent, "identity", {"id": "survivor.test", "name": "Test", "traits": traits})
	SimHealth.make_survivor_body(w, ent)
	SimHealth.make_stamina(w, ent)
	SimInventory.make_inventory(w, ent)
	SimNeeds.attach(w, ent)
	return ent


func _zombie(w: Variant, x: float, y: float) -> int:
	return SimRoster.spawn_zombie(w, x, y, SimRoster.TYPE_SHAMBLER, w.rng.stream("shambler"))


func _alive(w: Variant, ent: int) -> bool:
	var body: Variant = w.components.get_component(ent, "body")
	return body is Dictionary and SimHealth.is_alive(body as Dictionary)


func _swings(w: Variant, ent: int, ticks: int) -> int:
	var connected: int = 0
	for _t in ticks:
		w.step()
		for e in w.events.drained:
			var ev: Dictionary = e as Dictionary
			if String(ev.get("type", "")) == "attack.connected" and int(ev.get("attacker", -1)) == ent:
				connected += 1
	return connected


func _arrows(w: Variant, ent: int) -> int:
	var n: int = 0
	for item in SimInventory.carried_items(w, ent) as Array:
		var base: Variant = SimItems.item_base_of(w, int(item))
		if not (base is Dictionary and String((base as Dictionary).get("id", "")) == "item.ammo.arrow"):
			continue
		var stack: Variant = w.components.get_component(int(item), "stack")
		n += int((stack as Dictionary).get("count", 1)) if stack is Dictionary else 1
	return n


func _armed_npc_kills_what_walks_into_reach() -> bool:
	var w: Variant = _arena()
	var npc: int = _npc(w, 10.0, 10.0)
	SimInventory.equip(w, npc, SimItems.spawn_item(w, "item.knife.kitchen", {"tier": "scavenged"}))
	var z: int = _zombie(w, 10.9, 10.0)
	var connected: int = _swings(w, npc, ARENA_TICKS)
	if connected < 1:
		push_error("armed NPC never connected in %d ticks" % ARENA_TICKS)
		return false
	if _alive(w, z):
		push_error("armed NPC connected %d times and the shambler lived" % connected)
		return false

	# Negative: the same NPC with empty hands. Not "swung less" -- did not swing.
	var w2: Variant = _arena()
	var bare: int = _npc(w2, 10.0, 10.0)
	var z2: int = _zombie(w2, 10.9, 10.0)
	var idle: int = _swings(w2, bare, ARENA_TICKS)
	if idle != 0:
		push_error("unarmed NPC connected %d times" % idle)
		return false
	if not _alive(w2, z2):
		push_error("unarmed NPC killed a shambler")
		return false
	print("MELEE OK connected=%d unarmed=%d" % [connected, idle])
	return true


func _ranged_npc_spends_its_ammunition() -> bool:
	var w: Variant = _arena()
	var archer: int = _npc(w, 10.0, 10.0)
	SimInventory.equip(w, archer, SimItems.spawn_item(w, "item.bow.hunting", {"tier": "scavenged"}))
	SimInventory.stow(w, archer, SimItems.spawn_item(w, "item.ammo.arrow", {"tier": "scavenged", "count": 12}))
	var before: int = _arrows(w, archer)
	_zombie(w, 18.0, 10.0)
	for _t in ARENA_TICKS:
		w.step()
	var after: int = _arrows(w, archer)
	if after >= before:
		push_error("bow NPC fired nothing: arrows %d -> %d" % [before, after])
		return false

	# Negative: the same archer with no arrows never leaves Idle. An empty quiver is a refusal,
	# not a silent dry fire.
	var w2: Variant = _arena()
	var dry: int = _npc(w2, 10.0, 10.0)
	SimInventory.equip(w2, dry, SimItems.spawn_item(w2, "item.bow.hunting", {"tier": "scavenged"}))
	_zombie(w2, 18.0, 10.0)
	var raised: int = 0
	for _t in 200:
		w2.step()
		var rw: Variant = w2.components.get_component(dry, "rangedWeapon")
		if rw is Dictionary and int((rw as Dictionary)["state"]) != SimRanged.FireState.Idle:
			raised += 1
	if raised != 0:
		push_error("bow NPC with no arrows left Idle on %d ticks" % raised)
		return false

	# A pistol runs its magazine down and reloads itself -- the reload-when-empty branch is
	# inherited from try_begin_fire rather than restated here.
	var w3: Variant = _arena()
	var shooter: int = _npc(w3, 10.0, 10.0)
	SimInventory.equip(w3, shooter, SimItems.spawn_item(w3, "item.pistol.service", {"tier": "scavenged"}))
	SimInventory.stow(w3, shooter, SimItems.spawn_item(w3, "item.ammo.9mm", {"tier": "scavenged", "count": 20}))
	_zombie(w3, 18.0, 10.0)
	var reloads: int = 0
	var was: int = -1
	for _t in ARENA_TICKS:
		w3.step()
		var rw: Variant = w3.components.get_component(shooter, "rangedWeapon")
		if rw is Dictionary:
			var state: int = int((rw as Dictionary)["state"])
			if state == SimRanged.FireState.Reload and was != SimRanged.FireState.Reload:
				reloads += 1
			was = state
	if reloads < 1:
		push_error("pistol NPC never reloaded in %d ticks" % ARENA_TICKS)
		return false
	print("RANGED OK arrows %d->%d dry=%d reloads=%d" % [before, after, raised, reloads])
	return true


func _critically_injured_breaks_off() -> bool:
	# Break-off is disengagement, not surrender -- the swipe slice split this claim in two.
	# While zombies had no offense, "stand down" and "stand there" were the same thing; the
	# moment they could claw, an NPC that crossed BadlyHurt fell out of npc.combat entirely and
	# was ground down at arm's length, one swing answered in 2,460 ticks of contact. So the
	# break-off now narrows the envelope rather than closing it, and this gate holds both
	# halves: at range the critically injured spend nothing, and cornered they still fight.
	#
	# At range first, with its own positive control: a whole archer spends arrows on an
	# approaching threat, a critically injured one holds them.
	var whole_fired: int = _fires_at([], -1)
	if whole_fired < 1:
		push_error("whole archer did not fire, so the break-off test proves nothing")
		return false
	var broken_fired: int = _fires_at([], SimNpcCombat.BREAK_OFF_STATE)
	if broken_fired != 0:
		push_error("critically injured archer spent %d arrows -- break-off must refuse engagement at range" % broken_fired)
		return false

	# Cornered: the same critical wound with a claw already inside knife reach still swings.
	var w2: Variant = _arena()
	var hurt: int = _npc(w2, 10.0, 10.0)
	SimInventory.equip(w2, hurt, SimItems.spawn_item(w2, "item.knife.kitchen", {"tier": "scavenged"}))
	_wound_to(w2, hurt, "arm_right", SimNpcCombat.BREAK_OFF_STATE)
	_zombie(w2, 10.9, 10.0)
	var cornered: int = _swings(w2, hurt, 300)
	if cornered < 1:
		push_error("cornered critically injured NPC stood down -- surrender is not what break-off means")
		return false

	# And traits move the threshold by a rung rather than changing the decision: at a merely
	# Hurt arm the squeamish survivor holds fire and the ordinary one looses.
	var squeamish_fired: int = _fires_at(["squeamish"], SimHealth.PartState.Hurt)
	var ordinary_fired: int = _fires_at([], SimHealth.PartState.Hurt)
	if squeamish_fired != 0 or ordinary_fired < 1:
		push_error("trait threshold wrong: squeamish=%d ordinary=%d at Hurt" % [squeamish_fired, ordinary_fired])
		return false
	print("BREAKOFF OK whole=%d broken=%d cornered=%d squeamish=%d ordinary=%d" % [whole_fired, broken_fired, cornered, squeamish_fired, ordinary_fired])
	return true


# Instinct defense: the controlled survivor, unattended, answers a Pursuing claw in melee reach
# with the swing a key press would have started -- npc.instinct-defense, the struggle instinct's
# twin. Three claims: it fires, it does not fire early, and two silences -- any command at all,
# and a shambler that has not noticed anybody (which is what keeps instinct from ever *opening* a
# fight, or costing a hidden player their silence).
func _an_unattended_survivor_answers_the_claw() -> bool:
	var w: Variant = _arena()
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	SimInventory.make_inventory(w, w.player)
	SimInventory.equip(w, w.player, SimItems.spawn_item(w, "item.knife.kitchen", {"tier": "scavenged"}))
	var z: int = _zombie(w, 2.9, 2.0)
	(w.components.get_component(z, "shambler") as Dictionary)["state"] = SimShambler.ShamblerState["Pursue"]
	var connected: int = 0
	var first_at: int = -1
	for t in range(1, 201):
		w.step()
		for e in w.events.drained:
			if String((e as Dictionary).get("type", "")) == "attack.connected" and int((e as Dictionary).get("attacker", -1)) == int(w.player):
				connected += 1
				if first_at < 0:
					first_at = t
	if connected < 1:
		push_error("INSTINCT: an unattended armed survivor never answered the claw on them")
		return false
	if first_at < SimNpcCombat.DEFEND_INSTINCT_TICKS:
		push_error("INSTINCT: the first swing connected on tick %d, before DEFEND_INSTINCT_TICKS %d -- instinct must wait for the player's own answer" % [first_at, SimNpcCombat.DEFEND_INSTINCT_TICKS])
		return false

	# A player who is present -- any command, even a wait -- is never overridden.
	var w2: Variant = _arena()
	w2.components.set_component(w2.player, "facing", {"radians": 0.0})
	SimInventory.make_inventory(w2, w2.player)
	SimInventory.equip(w2, w2.player, SimItems.spawn_item(w2, "item.knife.kitchen", {"tier": "scavenged"}))
	var z2: int = _zombie(w2, 2.9, 2.0)
	(w2.components.get_component(z2, "shambler") as Dictionary)["state"] = SimShambler.ShamblerState["Pursue"]
	var attended: int = 0
	for _t in 200:
		w2.commands.push({"type": "wait"})
		w2.step()
		for e2 in w2.events.drained:
			if String((e2 as Dictionary).get("type", "")) == "attack.connected" and int((e2 as Dictionary).get("attacker", -1)) == int(w2.player):
				attended += 1
	if attended != 0:
		push_error("INSTINCT: instinct swung %d times over a player who was issuing commands" % attended)
		return false

	# And a claw that has not noticed anybody draws nothing: instinct defends a fight that is
	# already on, it never starts one.
	var w3: Variant = _arena()
	w3.components.set_component(w3.player, "facing", {"radians": 0.0})
	SimInventory.make_inventory(w3, w3.player)
	SimInventory.equip(w3, w3.player, SimItems.spawn_item(w3, "item.knife.kitchen", {"tier": "scavenged"}))
	_zombie(w3, 2.9, 2.0)
	var oblivious: int = 0
	for _t in 200:
		w3.step()
		for e3 in w3.events.drained:
			if String((e3 as Dictionary).get("type", "")) == "attack.connected" and int((e3 as Dictionary).get("attacker", -1)) == int(w3.player):
				oblivious += 1
	if oblivious != 0:
		push_error("INSTINCT: instinct opened a fight with a Wandering shambler %d times" % oblivious)
		return false
	print("INSTINCT OK first at %d (>= %d), %d connects; attended=%d oblivious=%d" % [first_at, SimNpcCombat.DEFEND_INSTINCT_TICKS, connected, attended, oblivious])
	return true


# Damage one part down to exactly the state named, using part_state's own scale rather than a
# second guess at what each part's maximum is.
func _wound_to(w: Variant, ent: int, part: String, state: int) -> void:
	var body: Dictionary = w.components.get_component(ent, "body") as Dictionary
	var maxv: Variant = SimHealth.max_of(body, part)
	var top: float = float(int(maxv)) if maxv != null else 40.0
	for step in range(int(top), -1, -1):
		body[part] = float(step)
		if int(SimHealth.part_state(body, part)) >= state:
			return


# Arrows spent by an archer with `traits`, wounded to `state` on one arm (-1 leaves them whole),
# against a threat approaching from well outside melee reach -- the engagement half of break-off.
func _fires_at(traits: Array, state: int) -> int:
	var w: Variant = _arena()
	var ent: int = _npc(w, 10.0, 10.0, traits)
	SimInventory.equip(w, ent, SimItems.spawn_item(w, "item.bow.hunting", {"tier": "scavenged"}))
	SimInventory.stow(w, ent, SimItems.spawn_item(w, "item.ammo.arrow", {"tier": "scavenged", "count": 12}))
	if state >= 0:
		_wound_to(w, ent, "arm_right", state)
	var before: int = _arrows(w, ent)
	_zombie(w, 18.0, 10.0)
	for _t in 300:
		w.step()
	return before - _arrows(w, ent)


func _distance_and_silence_are_both_negative_controls() -> bool:
	# Nothing to fight: an armed NPC alone in a district stays Idle. Milestone 1's exit criterion
	# reads "a quiet district has nobody pursuing"; NPC combat must not make one loud.
	var w: Variant = _arena()
	var alone: int = _npc(w, 10.0, 10.0)
	SimInventory.equip(w, alone, SimItems.spawn_item(w, "item.knife.kitchen", {"tier": "scavenged"}))
	var noise: int = 0
	for _t in 400:
		w.step()
		for e in w.events.drained:
			if String((e as Dictionary).get("type", "")) == "noise.emitted":
				noise += 1
		var swing: Variant = w.components.get_component(alone, "swing")
		if swing is Dictionary and int((swing as Dictionary)["state"]) != SimMelee.SwingState.Idle:
			push_error("NPC swung at nothing")
			return false
	if noise != 0:
		push_error("empty district emitted %d noise events" % noise)
		return false

	# And a threat further off than ENGAGE_METRES is not a threat yet -- a bow reaches 40 m and a
	# guard does not spend an arrow on everything inside it.
	var w2: Variant = _arena()
	var archer: int = _npc(w2, 4.0, 10.0)
	SimInventory.equip(w2, archer, SimItems.spawn_item(w2, "item.bow.hunting", {"tier": "scavenged"}))
	SimInventory.stow(w2, archer, SimItems.spawn_item(w2, "item.ammo.arrow", {"tier": "scavenged", "count": 12}))
	var quiver: int = _arrows(w2, archer)
	_zombie(w2, 4.0 + SimNpcCombat.ENGAGE_METRES + 4.0, 10.0)
	for _t in 400:
		w2.step()
	if _arrows(w2, archer) != quiver:
		push_error("NPC fired at a threat beyond ENGAGE_METRES")
		return false
	print("QUIET OK noise=%d quiver held at %d beyond %.0fm" % [noise, quiver, SimNpcCombat.ENGAGE_METRES])
	return true


# Whoever has hold of a colonist is the one that gets shot, even though something nearer is
# standing there. A held survivor cannot swing (melee.gd refuses a grabbed body) and buys their
# own way out only by winning a contest they can lose repeatedly, so the colony's answer to a
# grab is somebody else's weapon; before this the holder was just one more shambler in the
# queue, and usually not the closest, because it had stopped walking.
#
# Both halves, in the same arena: with a hold open the far holder is chosen and the near
# wanderer is not touched, and with no hold open at all the identical placement picks the near
# one. Without that second half this assertion would pass on a module that always shot whatever
# was furthest away.
func _a_shambler_with_someone_in_its_hands_is_shot_first() -> bool:
	var quiet: Dictionary = _priority_arena(false)
	var busy: Dictionary = _priority_arena(true)
	if int(quiet["chosen"]) != int(quiet["near"]):
		push_error("negative control failed: with nobody held, the archer did not pick the nearer shambler")
		return false
	if int(quiet["hits_far"]) != 0 or int(quiet["hits_near"]) < 1:
		push_error("negative control failed: with nobody held, hits went near=%d far=%d" % [int(quiet["hits_near"]), int(quiet["hits_far"])])
		return false
	if int(busy["chosen"]) != int(busy["far"]):
		push_error("a shambler holding a colonist was not selected over a nearer one")
		return false
	if int(busy["hits_far"]) < 1:
		push_error("the holder was selected but never actually shot")
		return false
	if int(busy["hits_near"]) != 0:
		push_error("%d shots went to the nearer wanderer while a colonist was being held" % int(busy["hits_near"]))
		return false
	print("HOLDER OK held: far=%d near=%d hits | quiet: far=%d near=%d hits" % [
		int(busy["hits_far"]), int(busy["hits_near"]), int(quiet["hits_far"]), int(quiet["hits_near"]),
	])
	return true


# One archer, one shambler at 3 m and one at 7 m, and -- when `hold` -- a second colonist in the
# far one's hands. The hold is opened through `SimShambler._start_grab`, the same call the think
# loop makes, so this measures the module's reading of a real hold rather than of a hand-placed
# component. Shambler AI is not registered here: nothing walks, nothing re-grabs, and the only
# thing that varies between the two arenas is whether somebody is being held.
#
# The two shamblers stand at right angles to each other on purpose. `ranged._fire_shot` resolves
# against the nearest body inside the *cone*, not against the entity the intake picked, so a near
# shambler standing on the line to a far one would be hit by an arrow aimed past it and the
# counters would read as if the selection had gone the other way.
func _priority_arena(hold: bool) -> Dictionary:
	var w: Variant = _arena()
	var archer: int = _npc(w, 10.0, 10.0)
	SimInventory.equip(w, archer, SimItems.spawn_item(w, "item.bow.hunting", {"tier": "scavenged"}))
	SimInventory.stow(w, archer, SimItems.spawn_item(w, "item.ammo.arrow", {"tier": "scavenged", "count": 40}))
	var near: int = _zombie(w, 10.0, 13.0)
	var far: int = _zombie(w, 17.0, 10.0)
	if hold:
		var victim: int = _npc(w, 17.9, 10.0)
		SimShambler._start_grab(w, far, victim)
	w.events.drain()
	var chosen: int = SimNpcCombat._nearest_threat(w, archer, SimNpcCombat.ENGAGE_METRES)
	var hits_near: int = 0
	var hits_far: int = 0
	for _t in ARENA_TICKS:
		w.step()
		for e in w.events.drained:
			var ev: Dictionary = e as Dictionary
			if String(ev.get("type", "")) != "attack.connected":
				continue
			if int(ev.get("target", -1)) == near:
				hits_near += 1
			elif int(ev.get("target", -1)) == far:
				hits_far += 1
		# Counting stops the moment the preferred target is gone: after that the archer picking
		# the other shambler is correct, and letting it run would fold that into the numbers.
		if not _alive(w, far) or not _alive(w, near):
			break
	return {"chosen": chosen, "near": near, "far": far, "hits_near": hits_near, "hits_far": hits_far}


# An NPC standing next to somebody in a shambler's hands pulls, rather than swinging at the
# shambler. Both are legitimate answers and the module keeps both -- what this pins is which one
# wins when the NPC can do either, and that the choice is made on the *victim's* distance rather
# than on the threat's, so an archer standing off keeps shooting.
#
# The contest is taken out of the picture on purpose: the holder's grip is 0.0, so the roll
# succeeds, and what is being measured is the decision rather than the odds. Whether a rescue can
# fail at all is check_m2_contact.gd's RESCUE claim, over sixteen seeds at the real grip.
func _hands_before_weapons_when_somebody_is_being_held() -> bool:
	# Positive: knife NPC at 10, victim at 11.2 (inside RESCUE_METRES), holder at 12.0 (outside
	# the knife's 1.25 m reach, so the widened envelope is what puts it in view at all).
	var w: Variant = _rescue_arena()
	var rescuer: int = _npc(w, 10.0, 10.0)
	SimInventory.equip(w, rescuer, SimItems.spawn_item(w, "item.knife.kitchen", {"tier": "scavenged"}))
	var victim: int = _npc(w, 11.2, 10.0)
	var holder: int = _zombie(w, 12.0, 10.0)
	(w.components.get_component(holder, "shambler") as Dictionary)["grabStrength"] = 0.0
	SimShambler._start_grab(w, holder, victim)
	w.events.drain()
	var freed_at: int = -1
	var swung: int = 0
	var event: Dictionary = {}
	for t in (SimShambler.RESCUE_TICKS + 5):
		w.step()
		for e in w.events.drained:
			var ev: Dictionary = e as Dictionary
			match String(ev.get("type", "")):
				"attack.connected":
					if int(ev.get("attacker", -1)) == rescuer:
						swung += 1
				"grab.broken":
					if int(ev.get("victim", -1)) == victim and freed_at < 0:
						freed_at = t + 1
						event = ev
		if freed_at >= 0:
			break
	if freed_at < 0:
		push_error("nobody pulled the victim out in %d ticks" % (SimShambler.RESCUE_TICKS + 5))
		return false
	if String(event.get("cause", "")) != "rescue" or int(event.get("by", -1)) != rescuer:
		push_error("the hold ended as %s, expected cause=rescue by=%d" % [str(event), rescuer])
		return false
	if swung != 0:
		push_error("the rescuer connected %d swings before pulling -- the branch order is wrong" % swung)
		return false
	if not _alive(w, holder):
		push_error("the holder died, so the release was not a rescue whatever the event said")
		return false

	# Negative: the same three bodies, collinear, with the victim moved to 2.2 m -- past
	# RESCUE_METRES, while the holder is at 1.0 m and well inside the knife's reach. Nothing about
	# this NPC has changed; only the geometry has, and it swings.
	var w2: Variant = _rescue_arena()
	var fighter: int = _npc(w2, 10.0, 10.0)
	SimInventory.equip(w2, fighter, SimItems.spawn_item(w2, "item.knife.kitchen", {"tier": "scavenged"}))
	var far_victim: int = _npc(w2, 12.2, 10.0)
	var near_holder: int = _zombie(w2, 11.0, 10.0)
	(w2.components.get_component(near_holder, "shambler") as Dictionary)["grabStrength"] = 0.0
	SimShambler._start_grab(w2, near_holder, far_victim)
	w2.events.drain()
	var hits: int = 0
	var rescues: int = 0
	for _t in (SimShambler.RESCUE_TICKS + 5):
		w2.step()
		for e in w2.events.drained:
			var ev2: Dictionary = e as Dictionary
			if String(ev2.get("type", "")) == "attack.connected" and int(ev2.get("attacker", -1)) == fighter:
				hits += 1
			if String(ev2.get("type", "")) == "grab.broken" and String(ev2.get("cause", "")) == "rescue":
				rescues += 1
	if hits < 1:
		push_error("negative control failed: with the victim out of reach the NPC did not swing either, so this measures nothing")
		return false
	if rescues != 0:
		push_error("%d rescues were attempted against a victim past RESCUE_METRES" % rescues)
		return false

	# Spam control: an unwinnable grip. Attempts must be spaced by the commitment plus the
	# cooldown, or a held colonist is a per-tick re-roll that drains the rescuer in seconds.
	var w3: Variant = _rescue_arena()
	var trier: int = _npc(w3, 10.0, 10.0)
	SimInventory.equip(w3, trier, SimItems.spawn_item(w3, "item.knife.kitchen", {"tier": "scavenged"}))
	var stuck: int = _npc(w3, 11.2, 10.0)
	var iron: int = _zombie(w3, 12.0, 10.0)
	(w3.components.get_component(iron, "shambler") as Dictionary)["grabStrength"] = 999.0
	SimShambler._start_grab(w3, iron, stuck)
	w3.events.drain()
	var attempts: Array[int] = []
	for t3 in 200:
		w3.step()
		for e in w3.events.drained:
			var ev3: Dictionary = e as Dictionary
			if String(ev3.get("type", "")) != "stamina.spent" or int(ev3.get("entity", -1)) != trier:
				continue
			if absf(float(ev3.get("amount", 0.0)) - SimShambler.RESCUE_STAMINA) < 0.001:
				attempts.append(t3 + 1)
	var spacing: int = SimShambler.RESCUE_TICKS + SimShambler.RESCUE_RETRY_TICKS
	if attempts.size() < 2:
		push_error("SKIP-WORTHY: only %d rescue attempts in 200 ticks, so the spacing was never judged" % attempts.size())
		return false
	for i in range(1, attempts.size()):
		if attempts[i] - attempts[i - 1] < spacing:
			push_error("rescue attempts %d ticks apart, floor is %d: %s" % [attempts[i] - attempts[i - 1], spacing, str(attempts)])
			return false
	print("RESCUE-FIRST OK freed on tick %d with %d swings; out-of-reach victim drew %d swings and 0 rescues; %d attempts spaced >= %d" % [
		freed_at, swung, hits, attempts.size(), spacing,
	])
	return true


# The combat arena plus the hold lifecycle, and without the struggle intake: an NPC struggles on
# its own every tick it is held (shambler.gd's third intake), which would free this victim before
# anybody could reach them and leave the assertion measuring nothing. `shambler.rescue-intake` is
# deliberately a different system and stays registered -- that separation is the point.
func _rescue_arena() -> Variant:
	var w: Variant = _arena()
	SimShambler.register_module(w, null)
	if not w.systems.unregister("shambler.struggle-intake"):
		push_error("shambler.struggle-intake was not registered -- this arena is silencing nothing")
	return w


func _a_guard_engages_without_leaving_its_post() -> bool:
	# This lane measures engaging-from-a-post against chasing, and its zombie stands 0.9 m off --
	# inside GRAB_METRES. With GRABS_ENABLED shipping true (docs/23's flag record) the zombie
	# takes hold and every escape is a 2.1 m/s break-away flight, so "drift" reads the grab
	# loop's own shove-offs rather than a chase (measured: 8.3 m of accumulated flight). Pinned
	# off for the lane, previous value restored -- the flag is a static shared by every world
	# this gate process boots; the grab loop has its own gate (check_m2_contact.gd).
	var flag_was: bool = SimShambler.GRABS_ENABLED
	SimShambler.GRABS_ENABLED = false
	var ok: bool = _guard_post_lane()
	SimShambler.GRABS_ENABLED = flag_was
	return ok


func _guard_post_lane() -> bool:
	# The real district this time, with every module the playable boot registers.
	var w: Variant = SimBoot.playable(20260805, 64)["world"]
	var guard: int = -1
	for ent in w.components.query(["needs", "jobPriorities", "position"]):
		if w.components.has_component(int(ent), "controlled") or int(ent) == int(w.player):
			continue
		guard = int(ent)
		break
	if guard < 0:
		push_error("no NPC survivor in the playable boot")
		return false
	SimJobs.set_focus(w, guard, "Manual")
	SimJobs.set_priority(w, guard, "Guard", 1)
	SimInventory.unequip(w, guard, "primary")
	if not SimInventory.equip(w, guard, SimItems.spawn_item(w, "item.bat.aluminium", {"tier": "scavenged"})):
		push_error("could not arm the guard")
		return false

	# Stand them on the post rather than waiting for the job router to walk them there --
	# routing is `M2_JOBS_OK`'s claim, and a need seek can legitimately hold a survivor for
	# hours. What is under test here is what they do once they are standing on it.
	# The post is the district's own gate anchor, read off the world that booted, not a constant.
	var gate: Vector2i = SimTileMap.gate_a(w.tilemap)
	if gate.x < 0 or gate.y < 0:
		push_error("the playable boot names no gate, so there is no post to stand on")
		return false
	var post_x: float = float(gate.x) + 0.5
	var post_y: float = float(gate.y) + 1.5
	w.components.set_component(guard, "position", {"x": post_x, "y": post_y})
	# Guard is a dusk-to-dawn post since 2026-09-06, so the watch has to be stood at dusk: the
	# first Dusk tick, where the ambient is still daylight's and the sightline refusal reads as
	# it did when this lane was written.
	w.tick = Clock.tick_on_day(1, Clock.DAY_ENDS)
	var post_job: Dictionary = SimJobs._work_for(w, guard, "Guard")
	if post_job.is_empty():
		push_error("no Guard job at dusk")
		return false
	w.components.set_component(guard, "job", post_job)
	_zombie(w, post_x + 0.9, post_y)
	var connected: int = _swings(w, guard, 600)
	if connected < 1:
		push_error("guard at its post never connected")
		return false
	var after: Dictionary = w.components.get_component(guard, "position") as Dictionary
	var drift: float = sqrt((float(after["x"]) - post_x) ** 2.0 + (float(after["y"]) - post_y) ** 2.0)
	# Engaging is something you do *from* a post. Some drift is the job system's own business;
	# a chase is not, and 6 m is well inside the gate's own footprint.
	if drift > 6.0:
		push_error("guard chased %.1f m off its post" % drift)
		return false
	print("POST OK connected=%d drift=%.2fm" % [connected, drift])
	return true


# --- The playable state, slice 11: re-arm ------------------------------------------------------

# An unarmed colonist walks to a working weapon on the ground near home and takes it, then
# fights with it; a broken one (condition 0) is left where it lies; an armed colonist keeps the
# weapon in hand. And a weapon that wears out is dropped at the feet, not lost.
func _a_dropped_weapon_is_picked_back_up() -> bool:
	var w: Variant = _arena()
	SimJobs.register_module(w)
	var npc: int = _npc(w, 10.0, 10.0)
	SimJobs.attach(w, npc, "Manual", SimJobs.empty_row())
	var bat: int = SimItems.spawn_item(w, "item.bat.aluminium", {"tier": "scavenged"})
	w.components.set_component(bat, "position", {"x": 14.5, "y": 10.5})
	var armed_at: int = -1
	for i in 400:
		w.step()
		if w.components.has_component(npc, "meleeWeapon"):
			armed_at = i
			break
	if armed_at < 0:
		push_error("REARM: an unarmed colonist never picked up the bat 4.5 m away in 400 ticks")
		return false
	var slots: Dictionary = (w.components.get_component(npc, "equipment") as Dictionary)["slots"] as Dictionary
	if int(slots.get("primary", -1)) != bat:
		push_error("REARM: the colonist is armed but not with the bat (%s)" % str(slots))
		return false
	var z: int = _zombie(w, 10.0, 10.0)
	w.components.set_component(z, "position", (w.components.get_component(npc, "position") as Dictionary).duplicate())
	if _swings(w, npc, ARENA_TICKS) < 1:
		push_error("REARM: the re-armed colonist never swung the bat")
		return false
	# Broken is left where it lies.
	var w2: Variant = _arena()
	SimJobs.register_module(w2)
	var npc2: int = _npc(w2, 10.0, 10.0)
	SimJobs.attach(w2, npc2, "Manual", SimJobs.empty_row())
	var broken: int = SimItems.spawn_item(w2, "item.bat.aluminium", {"tier": "scavenged"})
	w2.components.set_component(broken, "position", {"x": 14.5, "y": 10.5})
	(w2.components.get_component(broken, "condition") as Dictionary)["current"] = 0.0
	for _i in 400:
		w2.step()
	if w2.components.has_component(npc2, "meleeWeapon"):
		push_error("REARM: a colonist picked up a broken bat")
		return false
	# Armed keeps its own.
	var w3: Variant = _arena()
	SimJobs.register_module(w3)
	var npc3: int = _npc(w3, 10.0, 10.0)
	SimJobs.attach(w3, npc3, "Manual", SimJobs.empty_row())
	var knife: int = SimItems.spawn_item(w3, "item.knife.kitchen", {"tier": "scavenged"})
	SimInventory.equip(w3, npc3, knife)
	var spare: int = SimItems.spawn_item(w3, "item.bat.aluminium", {"tier": "scavenged"})
	w3.components.set_component(spare, "position", {"x": 14.5, "y": 10.5})
	for _i in 400:
		w3.step()
	var slots3: Dictionary = (w3.components.get_component(npc3, "equipment") as Dictionary)["slots"] as Dictionary
	if int(slots3.get("primary", -1)) != knife or not w3.components.has_component(spare, "position"):
		push_error("REARM: an armed colonist swapped weapons (%s)" % str(slots3))
		return false
	# Worn out is dropped at the feet, not lost -- and, broken, not picked back up.
	var w4: Variant = _arena()
	SimJobs.register_module(w4)
	var npc4: int = _npc(w4, 10.0, 10.0)
	SimJobs.attach(w4, npc4, "Manual", SimJobs.empty_row())
	var worn: int = SimItems.spawn_item(w4, "item.knife.kitchen", {"tier": "scavenged"})
	SimInventory.equip(w4, npc4, worn)
	(w4.components.get_component(worn, "condition") as Dictionary)["current"] = 0.01
	SimItems.apply_wear(w4, worn, 0.05)
	var where: Variant = w4.components.get_component(worn, "position")
	if not where is Dictionary or absf(float((where as Dictionary)["x"]) - 10.0) > 0.01:
		push_error("REARM: a worn-out knife was not dropped at the feet (%s)" % str(where))
		return false
	for _i in 200:
		w4.step()
	if w4.components.has_component(npc4, "meleeWeapon"):
		push_error("REARM: the colonist picked the broken knife back up")
		return false
	print("REARM OK armed with the bat at tick %d and swung it; a broken bat is left; an armed colonist keeps the knife; a worn-out knife drops at the feet and stays there" % armed_at)
	return true


# --- BLOCKED ----------------------------------------------------------------------------------
#
# The reader that is easiest to forget, and the one whose failure is silent. `try_begin_fire`
# refuses a weapon missing a required part, so an NPC whose rifle has no barrel can never shoot --
# but `_ranged_range` is what decides how close it walks, and if that still returns the rifle's
# sixty metres the NPC closes to sixty metres and stands there for the rest of the campaign taking
# shots that are refused. Nothing crashes and nothing is logged; it is an open circuit of exactly
# the shape this milestone keeps finding.
#
# The true negative is the same NPC with a whole rifle. Without it the lane passes for an NPC that
# never engages anything at all, which is the easiest way to accidentally write this assertion.
func _nobody_closes_on_a_gun_that_cannot_fire() -> bool:
	var lane: String = "BLOCKED"

	# TN first, so "it did not engage" below cannot be the arena's fault.
	var whole: Variant = _arena()
	var armed: int = _npc(whole, 10.0, 10.0)
	SimInventory.equip(whole, armed, SimItems.spawn_item(whole, "item.rifle.hunting", {"tier": "scavenged"}))
	SimInventory.stow(whole, armed, SimItems.spawn_item(whole, "item.ammo.rifle", {"tier": "scavenged", "count": 20}))
	_zombie(whole, 18.0, 10.0)
	var fired: int = 0
	for _t in ARENA_TICKS:
		whole.step()
		for e in whole.events.drained:
			if String((e as Dictionary).get("type", "")) == "weapon.fired" and int((e as Dictionary).get("entity", -1)) == armed:
				fired += 1
	if fired < 1:
		push_error("%s: an NPC with a whole rifle never fired, so the blocked half proves nothing" % lane)
		return false
	if SimNpcCombat._ranged_range(whole, armed) <= 0.0:
		push_error("%s: a whole rifle reports no engagement range at all" % lane)
		return false

	var w: Variant = _arena()
	var broken: int = _npc(w, 10.0, 10.0)
	var rifle: int = SimItems.spawn_item(w, "item.rifle.hunting", {"tier": "scavenged"})
	SimInventory.equip(w, broken, rifle)
	SimInventory.stow(w, broken, SimItems.spawn_item(w, "item.ammo.rifle", {"tier": "scavenged", "count": 20}))
	# `equip` publishes; `ranged.equip-weapon` runs at drain. Without this the NPC has no
	# `rangedWeapon` at all yet, `_ranged_range` returns 0 for that reason instead of for the one
	# under test, and the assertion below is vacuous -- which is exactly what it was until the
	# true negative caught it.
	w.events.drain()
	if not w.components.get_component(broken, "rangedWeapon") is Dictionary:
		push_error("%s: the NPC is not holding a built weapon, so its range proves nothing" % lane)
		return false
	if SimNpcCombat._ranged_range(w, broken) <= 0.0:
		push_error("%s: a whole rifle in this NPC's hands already reports no range" % lane)
		return false
	var barrel: int = SimAttachments.in_slot(w, rifle, "barrel")
	if barrel < 0 or not SimAttachments.detach(w, barrel):
		push_error("%s: could not take the rifle's barrel off" % lane)
		return false
	if SimNpcCombat._ranged_range(w, broken) > 0.0:
		push_error("%s: a rifle with no barrel still claims %.1f metres of engagement range" % [lane, SimNpcCombat._ranged_range(w, broken)])
		return false
	_zombie(w, 18.0, 10.0)
	var shots: int = 0
	for _t in ARENA_TICKS:
		w.step()
		for e in w.events.drained:
			if String((e as Dictionary).get("type", "")) == "weapon.fired" and int((e as Dictionary).get("entity", -1)) == broken:
				shots += 1
	if shots != 0:
		push_error("%s: an NPC holding a barrel-less rifle fired %d times" % [lane, shots])
		return false

	print("  BLOCKED OK a whole rifle fires %d times and engages; one with no barrel has no range and fires none" % fired)
	return true


# --- DRESS ------------------------------------------------------------------------------------
#
# "Colonists wear what they find" -- the acquisition half of armour, and the half without which
# `SimHealth.armor_damage_factor` is a reader nothing ever gives anything to read. No kit in the
# game carries armour, so before this rule every armour slot on every colonist was empty at boot
# and empty ten days later, and the balance harness measured the mechanic as exactly zero.
#
# Both branches of `_dress_job`, because they fire in different halves of ordinary play: a search
# empties a cupboard into the searcher's own pack (`SimContainers.search`), and Haul then carries
# everything it finds back to the stockpile, where it lies on the ground. A rule that only had the
# pack branch would miss every piece the colony ever tidied away.
#
# The true negative is the same two arenas with `WEAR_FOUND_ARMOR` pinned off. Without it "the
# colonist is wearing a vest" is worth exactly as much as the arena's ability to leave one off --
# and the flag is a **static**, shared by every world this one process boots, so the previous
# value goes back before the lane returns whatever happens. CLAUDE.md names that trap; docs/30
# records it twice.
func _armour_that_is_found_gets_worn() -> bool:
	var lane: String = "DRESS"
	var was: bool = SimJobs.WEAR_FOUND_ARMOR

	# 1. Out of the pack, at once, with no job at all.
	SimJobs.WEAR_FOUND_ARMOR = true
	var w: Variant = _arena()
	SimJobs.register_module(w)
	var npc: int = _npc(w, 10.0, 10.0)
	SimJobs.attach(w, npc, "Manual", SimJobs.empty_row())
	# A helmet rather than the vest below, for a dull reason worth writing down: pockets are
	# `POCKET_GRID`, four by two, and a 3x3 vest has never fitted in one. A rule that could only
	# be proved with something nobody can carry would not be a rule about found gear.
	var packed: int = SimItems.spawn_item(w, "item.helmet.bike", {"tier": "scavenged"})
	if not SimInventory.stow(w, npc, packed):
		SimJobs.WEAR_FOUND_ARMOR = was
		push_error("%s: the helmet would not go in the pack, so the pack branch has nothing to find" % lane)
		return false
	var packed_at: int = -1
	for i in 400:
		w.step()
		if _worn_in(w, npc, "head") == packed:
			packed_at = i
			break
	if packed_at < 0:
		SimJobs.WEAR_FOUND_ARMOR = was
		push_error("%s: a colonist carrying a bike helmet in the pack never put it on in 400 ticks" % lane)
		return false

	# 2. Off the ground, as a walk, four and a half metres away.
	var w2: Variant = _arena()
	SimJobs.register_module(w2)
	var npc2: int = _npc(w2, 10.0, 10.0)
	SimJobs.attach(w2, npc2, "Manual", SimJobs.empty_row())
	var loose: int = SimItems.spawn_item(w2, "item.vest.scrap", {"tier": "scavenged"})
	w2.components.set_component(loose, "position", {"x": 14.5, "y": 10.5})
	var ground_at: int = -1
	for i in 400:
		w2.step()
		if _worn_in(w2, npc2, "vest") == loose:
			ground_at = i
			break
	if ground_at < 0:
		SimJobs.WEAR_FOUND_ARMOR = was
		push_error("%s: a colonist never walked the 4.5 m to a scrap vest on the ground in 400 ticks" % lane)
		return false
	if w2.components.has_component(loose, "position"):
		SimJobs.WEAR_FOUND_ARMOR = was
		push_error("%s: the vest is worn and still lying on the ground" % lane)
		return false

	# 3. The true negative: the flag off, and neither branch fires.
	SimJobs.WEAR_FOUND_ARMOR = false
	var w3: Variant = _arena()
	SimJobs.register_module(w3)
	var npc3: int = _npc(w3, 10.0, 10.0)
	SimJobs.attach(w3, npc3, "Manual", SimJobs.empty_row())
	var packed3: int = SimItems.spawn_item(w3, "item.helmet.bike", {"tier": "scavenged"})
	var stowed3: bool = SimInventory.stow(w3, npc3, packed3)
	var loose3: int = SimItems.spawn_item(w3, "item.vest.scrap", {"tier": "scavenged"})
	w3.components.set_component(loose3, "position", {"x": 14.5, "y": 10.5})
	for _i in 400:
		w3.step()
	var dressed_anyway: int = _worn_count(w3, npc3)
	SimJobs.WEAR_FOUND_ARMOR = was
	if not stowed3:
		push_error("%s: the helmet would not go in the third arena's pack, so the true negative proves nothing" % lane)
		return false
	if dressed_anyway != 0:
		push_error("%s: WEAR_FOUND_ARMOR is off and the colonist put on %d piece(s) anyway" % [lane, dressed_anyway])
		return false
	if SimJobs.WEAR_FOUND_ARMOR != was:
		push_error("%s: the lane did not put WEAR_FOUND_ARMOR back" % lane)
		return false

	print("  DRESS OK the pack helmet goes on at tick %d, the vest 4.5 m away at tick %d and leaves the ground; with the rule off neither does" % [packed_at, ground_at])
	return true


# --- SELECTIVE --------------------------------------------------------------------------------
#
# "Beats what they are wearing" is the whole of the rule, and the cheapest way to get it wrong is
# to write a rule that swaps on anything -- a colonist who trades a riot vest for a scrap one every
# time they walk past it is worse off than one who never dresses at all, and no lane that only
# watches somebody get dressed would ever see it.
#
# So: the same arena twice, differing only in which vest is on the body and which is on the floor.
# Up the colonist takes; down they refuse. The upward half is this lane's true positive and it is
# load-bearing -- without it "did not swap" passes for a colonist who cannot reach the vest, cannot
# see it, or is standing in an arena where the rule never runs.
func _nobody_swaps_down_to_worse_armour() -> bool:
	var lane: String = "SELECTIVE"
	var was: bool = SimJobs.WEAR_FOUND_ARMOR
	SimJobs.WEAR_FOUND_ARMOR = true

	# Up: wearing the scrap vest, the riot vest at their feet.
	var up: Variant = _arena()
	SimJobs.register_module(up)
	var a: int = _npc(up, 10.0, 10.0)
	SimJobs.attach(up, a, "Manual", SimJobs.empty_row())
	var scrap: int = SimItems.spawn_item(up, "item.vest.scrap", {"tier": "scavenged"})
	SimInventory.equip(up, a, scrap)
	var riot: int = SimItems.spawn_item(up, "item.vest.riot", {"tier": "scavenged"})
	up.components.set_component(riot, "position", {"x": 11.5, "y": 10.5})
	var swapped: bool = false
	for _i in 400:
		up.step()
		if _worn_in(up, a, "vest") == riot:
			swapped = true
			break
	if not swapped:
		SimJobs.WEAR_FOUND_ARMOR = was
		push_error("%s: a colonist in a scrap vest never traded up to the riot vest at their feet -- the refusal below would prove nothing" % lane)
		return false

	# Down: the same arena with the two vests exchanged, and nothing happens.
	var down: Variant = _arena()
	SimJobs.register_module(down)
	var b: int = _npc(down, 10.0, 10.0)
	SimJobs.attach(down, b, "Manual", SimJobs.empty_row())
	var better: int = SimItems.spawn_item(down, "item.vest.riot", {"tier": "scavenged"})
	SimInventory.equip(down, b, better)
	var worse: int = SimItems.spawn_item(down, "item.vest.scrap", {"tier": "scavenged"})
	down.components.set_component(worse, "position", {"x": 11.5, "y": 10.5})
	for _i in 400:
		down.step()
	var still: int = _worn_in(down, b, "vest")
	SimJobs.WEAR_FOUND_ARMOR = was
	if still != better:
		push_error("%s: a colonist in a riot vest swapped down (slot holds %d, the riot vest is %d)" % [lane, still, better])
		return false
	if not down.components.has_component(worse, "position"):
		push_error("%s: the scrap vest was picked up off the floor by somebody already better dressed" % lane)
		return false

	print("  SELECTIVE OK scrap -> riot is taken; riot -> scrap is refused and the worse vest stays on the floor")
	return true


# What is in one equipment slot, or -1. A helper rather than three copies of the same cast, and
# `equipment` is genuinely absent until somebody equips their first thing.
func _worn_in(w: Variant, ent: int, slot: String) -> int:
	var eq: Variant = w.components.get_component(ent, "equipment")
	if not eq is Dictionary:
		return -1
	var slots: Dictionary = ((eq as Dictionary).get("slots", {})) as Dictionary
	return int(slots.get(slot, -1))


# How many garments carrying any armour at all are on this body. Weapons are in `primary` and
# carry no `armor` block, so they never count here.
func _worn_count(w: Variant, ent: int) -> int:
	var n: int = 0
	for item in SimInventory.equipped_items(w, ent):
		var base: Variant = SimItems.item_base_of(w, int(item))
		if base is Dictionary and (base as Dictionary).has("armor"):
			n += 1
	return n

# --- CLAIM ------------------------------------------------------------------------------------
#
# The owner's call of 2026-09-12, made on the balance harness's own evidence: the shipped rule
# sent seed 404 from three survivors to two, because colonists leave the compound to fetch gear
# and `HOME_RADIUS_TILES` is forty. A claim was the chosen lever -- the Cook's `reserved` seam,
# so two colonists never cross the district for the same vest.
#
# This is the one place the Dress job deliberately departs from `_rearm_job`, which it otherwise
# copies letter for letter. Re-arm fires only for somebody with empty hands and is therefore rare;
# a better garment is lying around constantly, so the collision is the common case rather than the
# edge one.
#
# The lane's true positive is load-bearing and easy to omit: "at most one claimant" passes
# trivially in an arena where the rule never runs at all, so somebody has to actually end up
# wearing the thing.
func _two_colonists_do_not_walk_to_one_vest() -> bool:
	var lane: String = "CLAIM"
	var was: bool = SimJobs.WEAR_FOUND_ARMOR
	SimJobs.WEAR_FOUND_ARMOR = true

	var w: Variant = _arena()
	SimJobs.register_module(w)
	# Two colonists, equidistant from one vest, so neither is the obvious taker.
	# Far enough that the walk takes real ticks. Proved necessary by sabotage: with the vest a
	# stride away the first colonist reached it before the second ever picked a job, so a scan
	# that ignored claims entirely still passed. The collision has to have time to happen.
	var a: int = _npc(w, 8.0, 8.0)
	var b: int = _npc(w, 8.0, 16.0)
	SimJobs.attach(w, a, "Manual", SimJobs.empty_row())
	SimJobs.attach(w, b, "Manual", SimJobs.empty_row())
	var vest: int = SimItems.spawn_item(w, "item.vest.riot", {"tier": "scavenged"})
	w.components.set_component(vest, "position", {"x": 20.5, "y": 12.5})

	var most_claimants: int = 0
	var worn_by: int = -1
	for _i in 400:
		w.step()
		var claiming: int = 0
		for ent in [a, b]:
			var job: Variant = w.components.get_component(int(ent), "job")
			if job is Dictionary and String((job as Dictionary).get("kind", "")) == "Dress" and int((job as Dictionary).get("target", -1)) == vest:
				claiming += 1
		most_claimants = maxi(most_claimants, claiming)
		if _worn_in(w, a, "vest") == vest:
			worn_by = a
			break
		if _worn_in(w, b, "vest") == vest:
			worn_by = b
			break
	SimJobs.WEAR_FOUND_ARMOR = was

	# True positive first: without it, "nobody walked twice" is what an inert arena also says.
	if worn_by < 0:
		push_error("%s: neither colonist ever put the vest on, so the claim assertion has nothing to judge" % lane)
		return false
	if most_claimants > 1:
		push_error("%s: %d colonists held a Dress job on the same vest at once -- the claim is not being taken, and both crossed the district for one garment" % [lane, most_claimants])
		return false
	var other: int = b if worn_by == a else a
	if _worn_in(w, other, "vest") == vest:
		push_error("%s: both colonists are wearing the same vest" % lane)
		return false

	print("  CLAIM OK one vest, two colonists, never more than %d claim on it at once; %s wore it" % [most_claimants, "the first" if worn_by == a else "the second"])
	return true
