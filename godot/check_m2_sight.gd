extends SceneTree
# Sightlines and memory -- docs/09's "what you cannot see, you cannot aim at" and docs/28's
# "memory, not deletion".
#
# Two halves of one rule. A shot is refused by a wall (SIGHT), and a body that walked behind that
# wall is still remembered for a while afterwards (MEMORY), with prose that degrades (PROSE) and
# a colony that can put a round where something was (RECALL-FIRE).
#
# Every assertion here carries its own negative, per the convention check_ban_health_bar.gd set:
# a sightline check that only ever fires at a wall would pass just as happily if `can_target`
# returned false for everything, so each blocked case is paired with the same shot taken through
# open ground.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimNpcCombat = preload("res://sim/modules/npc_combat.gd")
const SimSightings = preload("res://sim/modules/sightings.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimSurvivors = preload("res://sim/modules/survivors.gd")
const SimVisibility = preload("res://sim/vision/visibility.gd")
const SimLight = preload("res://sim/modules/light.gd")
const Clock = preload("res://sim/time/clock.gd")
const SimStancesRes = preload("res://sim/stances.gd")
const SimSave = preload("res://sim/save.gd")

const MAP_TILES: int = 24
const WALL_X: int = 12
const DOOR_Y: int = 12


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _a_wall_refuses_the_shot_and_open_ground_does_not() and ok
	ok = _a_shooter_with_no_eyes_is_not_refused() and ok
	ok = _memory_holds_where_it_was_last_seen() and ok
	ok = _memory_expires_and_a_watched_death_erases_it() and ok
	ok = _the_prose_degrades() and ok
	ok = _an_npc_fires_at_a_remembered_position() and ok
	ok = _a_zombie_sees_what_is_lit_at_night() and ok
	ok = _a_survivor_sees_three_and_a_half_metres_in_the_dark() and ok
	ok = _sight_works_by_height() and ok
	ok = _a_crawler_hides_below_low_cover() and ok
	ok = _the_consumers_read_the_height() and ok
	# The EYE lane's planar rule, run with SIGHT_BY_HEIGHT pinned false (docs/40 replaces it with
	# HEIGHT above; the switch must still give it back).
	ok = _the_switch_gives_back_planar_sight() and ok
	ok = _the_visibility_path_reads_eye_of() and ok
	ok = _a_hostile_behind_the_observer_is_not_recorded() and ok
	ok = _observe_one_reads_detail_not_line_of_sight() and ok
	ok = _kinds_are_recorded_and_only_hostiles_are_a_threat() and ok
	ok = _the_remembered_map_marks_the_cast_and_survives_a_save() and ok
	ok = _a_feigner_lies_among_the_dead_and_rises_on_approach() and ok
	if ok:
		print("M2_SIGHT_OK sight memory prose recall, a zombie sees what is lit at night, sight works by height, a crawler hides below Low cover, and a feigner lies among the dead until it rises")
		quit(0)
	else:
		push_error("M2_SIGHT_FAIL")
		quit(1)


# --- fixture ---------------------------------------------------------------------------------

# `walled` puts a solid column at WALL_X. `door` opens one tile of it, which is what lets the
# same map serve both "cannot see it" and "saw it a moment ago".
func _world(walled: bool, door: bool = false) -> Variant:
	var f: Dictionary = {"seed": 77, "tick_hz": 20, "map": {"width": MAP_TILES, "height": MAP_TILES, "walls": []}, "player": {"id": 0, "x": 8.5, "y": 12.5, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	var w: Variant = World.new(f)
	w.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	var map: Variant = SimTileMap.blank_map(MAP_TILES, MAP_TILES)
	if walled:
		for y in range(0, MAP_TILES):
			if door and y == DOOR_Y:
				continue
			map.tiles[y * MAP_TILES + WALL_X] = SimTileMap.Tile.Wall
	SimBoot.attach_kernel(w, map)
	SimHealth.register_module(w)
	SimRanged.register_module(w)
	SimInventory.register_module(w)
	SimSightings.register_module(w)
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	SimHealth.make_survivor_body(w, w.player)
	SimHealth.make_stamina(w, w.player)
	SimInventory.make_inventory(w, w.player)
	return w


func _arm(w: Variant, ent: int) -> void:
	var pistol: int = SimItems.spawn_item(w, "item.pistol.service", {"tier": "scavenged"})
	SimInventory.equip(w, ent, pistol)
	var ammo: int = SimItems.spawn_item(w, "item.ammo.9mm", {"tier": "scavenged", "count": 40})
	if not SimInventory.stow(w, ent, ammo):
		w.components.set_component(ammo, "stored", {"container": ent})
	SimRanged.load_held(w, ent)


func _zombie(w: Variant, x: float, y: float) -> int:
	var rng: Variant = w.rng.stream("shambler")
	var z: int = SimRoster.spawn_zombie(w, x, y, SimRoster.TYPE_SHAMBLER, rng)
	w.events.drain()
	return z


# Fires once and reports what the shot did. `hits` counts attack.connected, which is the only
# thing that separates a round that found somebody from a round that went into a wall -- the
# noise and the muzzle flash are published either way, which is the cost docs/09 names.
func _fire_once(w: Variant, shooter: int) -> Dictionary:
	var hits: int = 0
	var noises: int = 0
	w.commands.push({"type": "fire"})
	for i in 60:
		w.step()
		for e in w.events.drained:
			var t: String = String((e as Dictionary).get("type", ""))
			if t == "attack.connected" and int((e as Dictionary).get("attacker", -1)) == shooter:
				hits += 1
			elif t == "noise.emitted" and int((e as Dictionary).get("source", -1)) == shooter:
				noises += 1
		var rw: Variant = w.components.get_component(shooter, "rangedWeapon")
		if i > 2 and rw is Dictionary and int((rw as Dictionary)["state"]) == SimRanged.FireState.Idle:
			break
	return {"hits": hits, "noises": noises}


# --- SIGHT -----------------------------------------------------------------------------------

func _a_wall_refuses_the_shot_and_open_ground_does_not() -> bool:
	var blocked: Variant = _world(true)
	SimSurvivors.give_eyes(blocked, blocked.player)
	_arm(blocked, blocked.player)
	_zombie(blocked, 16.5, 12.5)
	var walled: Dictionary = _fire_once(blocked, blocked.player)

	var clear: Variant = _world(false)
	SimSurvivors.give_eyes(clear, clear.player)
	_arm(clear, clear.player)
	_zombie(clear, 16.5, 12.5)
	var open: Dictionary = _fire_once(clear, clear.player)

	if int(open["hits"]) < 1:
		push_error("SIGHT: the same shot over open ground missed -- the control proves nothing (%s)" % str(open))
		return false
	if int(walled["hits"]) != 0:
		push_error("SIGHT: a shot connected through a wall (%s)" % str(walled))
		return false
	if int(walled["noises"]) < 1:
		push_error("SIGHT: the blocked shot was never taken at all, so the refusal is the wrong one (%s)" % str(walled))
		return false
	print("SIGHT OK open_hits=%d walled_hits=%d walled_noise=%d" % [int(open["hits"]), int(walled["hits"]), int(walled["noises"])])
	return true


func _a_shooter_with_no_eyes_is_not_refused() -> bool:
	# Deliberately no `give_eyes`. Every ranged fixture in the suite predates sightlines and
	# spawns a shooter with no observer at all; if the absence of a view read as "sees nothing",
	# each of them would silently stop hitting. `can_target` returns true when `tiles_for` has
	# nothing to say, and this is the assertion that says so out loud.
	var w: Variant = _world(true)
	_arm(w, w.player)
	_zombie(w, 16.5, 12.5)
	var r: Dictionary = _fire_once(w, w.player)
	if int(r["hits"]) < 1:
		push_error("NO-EYES: a shooter without an observer was refused by a wall (%s)" % str(r))
		return false
	print("NO-EYES OK hits=%d" % int(r["hits"]))
	return true


# --- MEMORY ----------------------------------------------------------------------------------

func _memory_holds_where_it_was_last_seen() -> bool:
	var w: Variant = _world(true, true)
	SimSurvivors.give_eyes(w, w.player)
	var z: int = _zombie(w, 16.5, float(DOOR_Y) + 0.5)
	w.step()
	var seen: Variant = SimSightings.recall(w, w.player, z)
	if not seen is Dictionary:
		push_error("MEMORY: nothing was recorded for a body in plain view through the doorway")
		return false
	var was_x: float = float((seen as Dictionary)["x"])
	var was_y: float = float((seen as Dictionary)["y"])

	# Behind the wall. Nothing in the sim moved it there -- a teleport is the cheapest way to
	# express "it walked out of sight" without booting the shambler module and waiting.
	w.components.set_component(z, "position", {"x": 16.5, "y": float(DOOR_Y) + 4.5})
	w.step()
	if bool(w.vision.call("line_of_sight", w.player, 16.5, float(DOOR_Y) + 4.5)):
		push_error("MEMORY: the body is still in line of sight, so the test is not testing anything")
		return false
	var after: Variant = SimSightings.recall(w, w.player, z)
	if not after is Dictionary:
		push_error("MEMORY: the record was deleted the instant a wall intervened -- docs/28 forbids exactly this")
		return false
	if absf(float((after as Dictionary)["x"]) - was_x) > 0.001 or absf(float((after as Dictionary)["y"]) - was_y) > 0.001:
		push_error("MEMORY: the remembered position followed an unseen body (%s -> %s)" % [str([was_x, was_y]), str(after)])
		return false

	# The negative: an observer who never saw it has nothing to remember. Same map, same body,
	# standing on the wrong side of the wall from the start.
	var blind: Variant = _world(true)
	SimSurvivors.give_eyes(blind, blind.player)
	var z2: int = _zombie(blind, 16.5, 12.5)
	blind.step()
	if SimSightings.recall(blind, blind.player, z2) != null:
		push_error("MEMORY: a body that was never in view was remembered anyway")
		return false
	print("MEMORY OK kept=(%.1f, %.1f) after_it_left=%s unseen=none" % [was_x, was_y, str([float((after as Dictionary)["x"]), float((after as Dictionary)["y"])])])
	return true


func _memory_expires_and_a_watched_death_erases_it() -> bool:
	var w: Variant = _world(false)
	SimSurvivors.give_eyes(w, w.player)
	var z: int = _zombie(w, 16.5, 12.5)
	w.step()
	if SimSightings.recall(w, w.player, z) == null:
		push_error("EXPIRY: nothing recorded to expire")
		return false
	# Read-only jump past the horizon. Stepping 2,400 times would prove the same thing and cost
	# two minutes of wall clock; the horizon is enforced in `remembered` against `world.tick`,
	# which is exactly what moving the clock exercises.
	w.tick += SimSightings.MEMORY_TICKS + 1
	if SimSightings.recall(w, w.player, z) != null:
		push_error("EXPIRY: a sighting older than the horizon is still being recalled")
		return false
	if SimSightings.clause(w, w.player) != "":
		push_error("EXPIRY: the prose still speaks for a sighting that has expired")
		return false

	# Watched it fall: a body you saw go down stops being remembered as a threat, and the record
	# goes rather than ageing out. The negative is the case above -- an ordinary sighting that is
	# still there one tick later.
	var seen_die: Variant = _world(false)
	SimSurvivors.give_eyes(seen_die, seen_die.player)
	var z3: int = _zombie(seen_die, 16.5, 12.5)
	seen_die.step()
	if SimSightings.recall(seen_die, seen_die.player, z3) == null:
		push_error("EXPIRY: nothing recorded before the kill")
		return false
	var body: Variant = seen_die.components.get_component(z3, "body")
	(body as Dictionary)["head"] = 0.0
	seen_die.step()
	if SimSightings.recall(seen_die, seen_die.player, z3) != null:
		push_error("EXPIRY: a body watched going down is still remembered as somewhere to be wary of")
		return false
	print("EXPIRY OK horizon=%d watched_death=cleared" % SimSightings.MEMORY_TICKS)
	return true


# --- PROSE -----------------------------------------------------------------------------------

func _the_prose_degrades() -> bool:
	var w: Variant = _world(false)
	SimSurvivors.give_eyes(w, w.player)
	_zombie(w, 16.5, 12.5)
	_zombie(w, 17.5, 12.5)
	w.step()
	var fresh: String = SimSightings.clause(w, w.player)
	w.tick += SimSightings.RECENT_TICKS + 1
	var stale: String = SimSightings.clause(w, w.player)

	if not fresh.contains("two of them") or not fresh.contains("east") or not fresh.contains("a moment ago"):
		push_error("PROSE: a fresh pair due east reads '%s'" % fresh)
		return false
	if not stale.contains("a few of them") or not stale.contains("a while ago"):
		push_error("PROSE: the same pair a minute later reads '%s', which has not degraded" % stale)
		return false
	if fresh == stale:
		push_error("PROSE: the clause says the same thing fresh and stale")
		return false
	for line in [fresh, stale]:
		for ch in line:
			if ch >= "0" and ch <= "9":
				push_error("PROSE: a digit reached a player-facing clause: '%s'" % line)
				return false
	# Bearings, since the clause only ever exercises one of the eight.
	if SimSightings.bearing_word(0.0, -1.0) != "north" or SimSightings.bearing_word(-1.0, -1.0) != "north-west":
		push_error("PROSE: bearing words are wrong (%s, %s)" % [SimSightings.bearing_word(0.0, -1.0), SimSightings.bearing_word(-1.0, -1.0)])
		return false
	print("PROSE OK fresh='%s' stale='%s'" % [fresh, stale])
	return true


# --- RECALL-FIRE -----------------------------------------------------------------------------

# An NPC survivor with a pistol, no player involvement. Built by hand rather than through
# `spawn_unique` so the fixture carries no content survivor and no job board.
func _npc(w: Variant, x: float, y: float) -> int:
	var ent: int = int(w.entities.spawn())
	w.components.set_component(ent, "position", {"x": x, "y": y})
	w.components.set_component(ent, "velocity", {"dx": 0.0, "dy": 0.0})
	w.components.set_component(ent, "facing", {"radians": 0.0})
	SimHealth.make_survivor_body(w, ent)
	SimHealth.make_stamina(w, ent)
	SimInventory.make_inventory(w, ent)
	SimNeeds.attach(w, ent)
	SimSurvivors.give_eyes(w, ent)
	_arm(w, ent)
	return ent


func _npc_world() -> Variant:
	var w: Variant = _world(true, true)
	SimNeeds.register_module(w)
	SimNpcCombat.register_module(w)
	return w


# Puts the weapon back to Idle. The NPC sees the body before it walks off -- that is how the
# memory gets made -- and a shot begun against the visible target would still be in its raise or
# steady window when the body leaves, so a noise counted afterwards would be that shot rather than
# a decision taken about a memory. Resetting is what makes the measurement mean what it says.
func _settle(w: Variant, npc: int) -> void:
	var rw: Variant = w.components.get_component(npc, "rangedWeapon")
	if rw is Dictionary:
		(rw as Dictionary)["state"] = SimRanged.FireState.Idle
		(rw as Dictionary)["ticksLeft"] = 0


# FLOOR. After dark a survivor sees the ground 3.5 m off with no light anywhere (docs/23, "The night's
# reach on screen", JT's 2026-10-24 card), and not 4 m off. A zombie in the same dark does not get it.
# At noon the floor changes nothing: the survivor sees 4 m as they always did.
func _a_survivor_sees_three_and_a_half_metres_in_the_dark() -> bool:
	var night: int = Clock.tick_at_time_of_day(0.95)
	var w: Variant = _world(false)
	w.tick = night
	w.components.set_component(w.player, "position", {"x": 8.5, "y": 12.5})
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	SimSurvivors.give_eyes(w, w.player)
	var zed: int = _zombie(w, 8.5, 12.5)
	w.step()
	var near: int = int(w.vision.call("detail", w.player, 11.5, 12.5))
	var far: int = int(w.vision.call("detail", w.player, 12.5, 12.5))
	if near == SimVisibility.Detail.Unseen:
		push_error("FLOOR: a survivor in the dark does not see the ground 3 m off -- the night-eyes floor is not reaching sight")
		return false
	if far != SimVisibility.Detail.Unseen:
		push_error("FLOOR: a survivor in the dark sees the ground 4 m off, past the 3.5 m floor")
		return false
	var zed_near: int = int(w.vision.call("detail", zed, 11.5, 12.5))
	if zed_near != SimVisibility.Detail.Unseen:
		push_error("FLOOR: a zombie in the dark sees 3 m, and only a survivor should get the floor")
		return false
	w.tick = Clock.tick_at_time_of_day(0.5)
	w.step()
	if int(w.vision.call("detail", w.player, 12.5, 12.5)) == SimVisibility.Detail.Unseen:
		push_error("FLOOR: at noon the survivor does not see 4 m -- the floor changed the day")
		return false
	# A save from before the floor: the survivor's observer has no `night_eyes`, and a restore gives it
	# the floor as give_eyes would have. The zombie's old-shape observer does not get it.
	var old: Variant = _world(false)
	old.tick = night
	old.components.set_component(old.player, "position", {"x": 8.5, "y": 12.5})
	old.components.set_component(old.player, "facing", {"radians": 0.0})
	old.components.set_component(old.player, "observer", SimVisibility.daylight_eyes())
	var old_zed: int = _zombie(old, 8.5, 12.5)
	var snap: Dictionary = old.snapshot()
	var back: Variant = _world(false)
	back.restore(snap)
	back.tick = night
	back.step()
	if int(back.vision.call("detail", back.player, 11.5, 12.5)) == SimVisibility.Detail.Unseen:
		push_error("FLOOR LOAD: a survivor restored from a save with no night_eyes does not see 3 m in the dark")
		return false
	if bool((back.components.get_component(old_zed, "observer") as Dictionary).get("night_eyes", false)):
		push_error("FLOOR LOAD: a zombie restored from an old save got the survivor floor")
		return false
	print("FLOOR LOAD OK an old save's survivor gets the floor on restore; its zombie does not")
	print("FLOOR OK a survivor sees 3 m and not 4 m in the dark; a zombie does not get the floor; noon unchanged")
	return true


func _run_npc(w: Variant, npc: int, ticks: int) -> Dictionary:
	var noises: int = 0
	var hits: int = 0
	for i in ticks:
		w.step()
		for e in w.events.drained:
			var t: String = String((e as Dictionary).get("type", ""))
			if t == "noise.emitted" and int((e as Dictionary).get("source", -1)) == npc:
				noises += 1
			elif t == "attack.connected" and int((e as Dictionary).get("attacker", -1)) == npc:
				hits += 1
	return {"noises": noises, "hits": hits}


func _an_npc_fires_at_a_remembered_position() -> bool:
	var w: Variant = _npc_world()
	var npc: int = _npc(w, 8.5, float(DOOR_Y) + 0.5)
	var z: int = _zombie(w, 16.5, float(DOOR_Y) + 0.5)
	w.step()
	if SimSightings.recall(w, npc, z) == null:
		push_error("RECALL-FIRE: the NPC never saw the body through the doorway")
		return false
	w.components.set_component(z, "position", {"x": 16.5, "y": float(DOOR_Y) + 4.5})
	_settle(w, npc)
	var shot: Dictionary = _run_npc(w, npc, 90)
	if int(shot["noises"]) < 1:
		push_error("RECALL-FIRE: the NPC lost sight of it and did nothing (%s)" % str(shot))
		return false
	if int(shot["hits"]) != 0:
		push_error("RECALL-FIRE: a shot at a remembered position hit something that had left (%s)" % str(shot))
		return false
	var facing: Variant = w.components.get_component(npc, "facing")
	if absf(float((facing as Dictionary)["radians"])) > 0.1:
		push_error("RECALL-FIRE: the NPC fired somewhere other than where it last saw the body (facing %.3f)" % float((facing as Dictionary)["radians"]))
		return false

	# Negative one: nothing seen, nothing remembered, nothing spent. Otherwise this assertion
	# would pass for an NPC that simply fires east every tick.
	var never: Variant = _npc_world()
	var npc2: int = _npc(never, 8.5, float(DOOR_Y) + 0.5)
	_zombie(never, 16.5, float(DOOR_Y) + 4.5)
	var quiet: Dictionary = _run_npc(never, npc2, 90)
	if int(quiet["noises"]) != 0:
		push_error("RECALL-FIRE: an NPC that never saw anything spent ammunition anyway (%s)" % str(quiet))
		return false

	# Negative two: a memory past the point where it is worth a round. Same fixture, same body,
	# and the only difference is the clock.
	var old: Variant = _npc_world()
	var npc3: int = _npc(old, 8.5, float(DOOR_Y) + 0.5)
	var z3: int = _zombie(old, 16.5, float(DOOR_Y) + 0.5)
	old.step()
	if SimSightings.recall(old, npc3, z3) == null:
		push_error("RECALL-FIRE: the stale-memory control never saw the body either")
		return false
	old.components.set_component(z3, "position", {"x": 16.5, "y": float(DOOR_Y) + 4.5})
	_settle(old, npc3)
	old.tick += SimSightings.RECENT_TICKS + 1
	var too_old: Dictionary = _run_npc(old, npc3, 90)
	if int(too_old["noises"]) != 0:
		push_error("RECALL-FIRE: a memory the survivor would call 'a while ago' was still worth a round (%s)" % str(too_old))
		return false
	print("RECALL-FIRE OK shots=%d hits=%d unseen=%d stale=%d" % [int(shot["noises"]), int(shot["hits"]), int(quiet["noises"]), int(too_old["noises"])])
	return true


# --- NIGHT-LIT -------------------------------------------------------------------------------

# A zombie's eyes sample the light at the *target*, not at their own tile. The oracle's rule --
# sight is `min(eyes, max(ambient, lit at the observer))` -- made every zombie blind after dark
# (12 m x 0.04 = 0.48 m) and blind to a survivor standing under a floodlight, which is the
# screamer's whole purpose inverted. `shambler_eyes()` now carries `lit_target`, and `detail`
# for such an observer answers seen inside the ambient reach *or* where the light index says
# the target's tile is lit, out to the eyes' full range and never through a wall.
#
# The player's eyes keep the oracle's rule on purpose: `tiles_for(player)` is what cuts roofs
# out and pools the light wash, and a night-time shadowcast at 48 m would open every roof in
# sight. The fourth case pins that scoping so a later "fix" cannot widen it unnoticed.
func _a_zombie_sees_what_is_lit_at_night() -> bool:
	var night: int = Clock.tick_at_time_of_day(0.95)
	if Clock.ambient_light_at(night) > 0.1:
		push_error("NIGHT-LIT: the fixture tick is not dark")
		return false
	var results: Dictionary = {}
	for case in ["lit", "dark", "lit-behind-wall", "player-eyes-lit"]:
		var walled: bool = case == "lit-behind-wall"
		var w: Variant = _world(walled)
		w.tick = night
		w.components.set_component(w.player, "position", {"x": 18.5, "y": 12.5})
		w.components.set_component(w.player, "facing", {"radians": PI})
		if case != "dark":
			var lamp: int = int(w.entities.spawn())
			w.components.set_component(lamp, "position", {"x": 18.5, "y": 12.5})
			SimLight.make_light_source(w, lamp, 6.0)
		var z: int = _zombie(w, 8.5, 12.5)
		w.components.set_component(z, "facing", {"radians": 0.0})
		w.step()
		if case == "player-eyes-lit":
			SimSurvivors.give_eyes(w, w.player)
			# The survivor is lit; the zombie is not. Can the player see the zombie ten metres
			# off in the dark? The oracle's rule says no, and that rule stands for people.
			var zl: int = int(w.entities.spawn())
			w.components.set_component(zl, "position", {"x": 8.5, "y": 12.5})
			SimLight.make_light_source(w, zl, 6.0)
			w.step()
			results[case] = int(w.vision.call("detail", w.player, 8.5, 12.5))
		else:
			results[case] = int(w.vision.call("detail", z, 18.5, 12.5))
	if int(results["lit"]) == SimVisibility.Detail.Unseen:
		push_error("NIGHT-LIT: a lit survivor 10 m away after dark was unseen")
		return false
	if int(results["dark"]) != SimVisibility.Detail.Unseen:
		push_error("NIGHT-LIT: an unlit survivor 10 m away after dark was seen -- the night is not dark")
		return false
	if int(results["lit-behind-wall"]) != SimVisibility.Detail.Unseen:
		push_error("NIGHT-LIT: a lit survivor behind a wall was seen")
		return false
	if int(results["player-eyes-lit"]) != SimVisibility.Detail.Unseen:
		push_error("NIGHT-LIT: the player's eyes took the lit-target rule -- roofs and the wash key on tiles_for(player), see the comment")
		return false
	print("NIGHT-LIT OK lit=%d dark=%d behind_wall=%d player_eyes=%d" % [int(results["lit"]), int(results["dark"]), int(results["lit-behind-wall"]), int(results["player-eyes-lit"])])
	return true


# --- EYE ---------------------------------------------------------------------------------------
#
# The planar rule docs/40's slice 4 replaced with HEIGHT (below). Run only with
# `SimVisibility.SIGHT_BY_HEIGHT` pinned false, by `_the_switch_gives_back_planar_sight`: what it
# asserts is what the switch's "off" must still be.
#
# `SimStances.eye_of` was one of docs/23's four named-but-unfixed dead sockets: called by
# nothing, with no code writing `observer["eye"]`, so `Opacity.Low` / `Tile.Low` cover blocked
# nobody -- a crouched survivor saw over a low wall exactly as well as a standing one. Fixed by
# folding the write into `SimVisibility.refresh` (the port of src/sim/modules/stance.ts's
# `stance.eyes`), so an observer's eye follows its posture every tick before the shadowcast that
# depends on it runs.

# A 16x16 floor with one `Tile.Low` cell at (8,8), between a player at tile 4 and a target at
# tile 12 -- `test/integration/stances.test.ts`'s `withLowCover` fixture, built by hand for the
# same reason it gives: the shipped district scatters low cover on open ground, and a test that
# hunted for a useful one would be asserting the generator's luck rather than the rule.
func _world_low_cover() -> Variant:
	var f: Dictionary = {"seed": 77, "tick_hz": 20, "map": {"width": 16, "height": 16, "walls": []}, "player": {"id": 0, "x": 4.5, "y": 8.5, "stance": SimStancesRes.Stance.Walk}, "rng_probe": {"stream": "test", "samples": 0}}
	var w: Variant = World.new(f)
	w.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	var map: Variant = SimTileMap.blank_map(16, 16)
	map.tiles[8 * 16 + 8] = SimTileMap.Tile.Low
	SimBoot.attach_kernel(w, map)
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	return w


func _settle_stance(w: Variant, from_stance: int, to_stance: int) -> void:
	w.commands.push({"type": "stance", "stance": to_stance})
	for i in SimStancesRes.stance_change_ticks(from_stance, to_stance) + 1:
		w.step()


func _crouching_lowers_the_eye_over_low_cover() -> bool:
	var w: Variant = _world_low_cover()
	SimSurvivors.give_eyes(w, w.player)
	w.step()

	# True positive's control: standing sees straight over a Low tile, or the rest proves nothing.
	if not bool(w.vision.call("can_see", w.player, 12.5, 8.5)):
		push_error("EYE: a standing survivor could not see across a Low tile -- the control proves nothing")
		return false
	var obs: Dictionary = w.components.get_component(w.player, "observer") as Dictionary
	if int(obs["eye"]) != SimTileMap.Eye.Standing:
		push_error("EYE: a fresh survivor's observer did not start at Eye.Standing (%d)" % int(obs["eye"]))
		return false

	# The positive: crouch, and the same Low tile now blocks the same sightline.
	_settle_stance(w, SimStancesRes.Stance.Walk, SimStancesRes.Stance.Crouch)
	if int(obs["eye"]) != SimTileMap.Eye.Crouched:
		push_error("EYE: crouching never wrote Eye.Crouched onto the observer (%d)" % int(obs["eye"]))
		return false
	if bool(w.vision.call("can_see", w.player, 12.5, 8.5)):
		push_error("EYE: a crouched survivor still saw straight over a Low tile")
		return false

	# The negative: stand back up on the same body, over the same tile, and the sightline returns
	# -- proving the block above came from the eye and not from some other side effect of crouching.
	_settle_stance(w, SimStancesRes.Stance.Crouch, SimStancesRes.Stance.Walk)
	if int(obs["eye"]) != SimTileMap.Eye.Standing:
		push_error("EYE: standing back up did not restore Eye.Standing (%d)" % int(obs["eye"]))
		return false
	if not bool(w.vision.call("can_see", w.player, 12.5, 8.5)):
		push_error("EYE: standing back up did not restore the sightline over the Low tile")
		return false
	print("EYE OK standing=see crouched=blocked restored=see")
	return true


func _code_of(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


# The dead-socket rule (CLAUDE.md): a gate proving `eye_of` returns the right number does not
# prove anything calls it. Isolated to a non-comment line containing the call, so a prose mention
# in a comment (this file has several, on purpose) cannot satisfy it -- `check_m2_teach.gd`'s
# `READ_KEYS` scan is the precedent for reading the source rather than trusting a behavioural
# proxy alone.
func _the_visibility_path_reads_eye_of() -> bool:
	var code: String = _code_of("res://sim/vision/visibility.gd")
	if code.is_empty():
		push_error("EYE-READER: could not read sim/vision/visibility.gd")
		return false
	var calls: int = 0
	for line in code.split("\n"):
		var trimmed: String = String(line).strip_edges()
		if trimmed.begins_with("#"):
			continue
		if trimmed.contains("eye_of("):
			calls += 1
	if calls == 0:
		push_error("EYE-READER: sim/vision/visibility.gd has no live call to eye_of -- the write in the EYE lane above is not reachable from the visibility path")
		return false
	print("EYE-READER OK eye_of called from %d non-comment line(s) of sim/vision/visibility.gd" % calls)
	return true


# --- BEHIND ------------------------------------------------------------------------------------
#
# sightings.gd:147 recorded a sighting off `line_of_sight` -- walls and range, with no facing
# arc -- so a survivor remembered, and the HUD reported, a body standing anywhere in the
# 170-degree blind arc behind them. `_observe_containers` a few lines above already asked
# `detail`, which narrows by the same focal/peripheral cone `SimVisibility.detail` uses for
# ranged targeting; `_observe_one` now asks the same question. Per the hardcore contract's
# clause 4, information stays scarce -- a colonist does not get to know what is behind their
# own back.

func _behind_world() -> Variant:
	var f: Dictionary = {"seed": 77, "tick_hz": 20, "map": {"width": MAP_TILES, "height": MAP_TILES, "walls": []}, "player": {"id": 0, "x": 8.5, "y": 8.5, "stance": SimStancesRes.Stance.Walk}, "rng_probe": {"stream": "test", "samples": 0}}
	var w: Variant = World.new(f)
	w.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	var map: Variant = SimTileMap.blank_map(MAP_TILES, MAP_TILES)
	SimBoot.attach_kernel(w, map)
	SimSightings.register_module(w)
	SimSurvivors.give_eyes(w, w.player)
	SimSightings.attach(w, w.player)
	# Facing east: everything west of the observer is behind them.
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	return w


func _a_hostile_behind_the_observer_is_not_recorded() -> bool:
	var w: Variant = _behind_world()
	# In line-of-sight geometry alone (open ground, no wall) but due west -- squarely in the
	# 170-degree arc `detail`'s peripheral cone leaves uncovered, per daylight_eyes' half-angles.
	var behind: int = _zombie(w, 2.5, 8.5)
	w.step()
	if bool(w.vision.call("line_of_sight", w.player, 2.5, 8.5)) != true:
		push_error("BEHIND: the geometry control failed -- open ground due west is not even in line of sight, so this lane proves nothing")
		return false
	if SimSightings.recall(w, w.player, behind) != null:
		push_error("BEHIND: a hostile standing behind the observer, in geometric line of sight, was recorded as seen")
		return false

	# The negative: the identical hostile, same distance, directly ahead instead. Same fixture,
	# same facing, only the bearing changed -- if this one is not recorded either, the lane above
	# proved nothing about facing at all.
	var w2: Variant = _behind_world()
	var ahead: int = _zombie(w2, 14.5, 8.5)
	w2.step()
	if SimSightings.recall(w2, w2.player, ahead) == null:
		push_error("BEHIND: the same hostile directly ahead of the observer was not recorded -- the control proves nothing")
		return false
	print("BEHIND OK behind=unrecorded ahead=recorded")
	return true


# Isolated to `_observe_one`'s own body, not the file as a whole -- `_observe_containers` calls
# `detail` too, and a scan of the whole file would pass even if `_observe_one` still called
# `line_of_sight`, which is the exact bug this lane exists to catch.
func _observe_one_reads_detail_not_line_of_sight() -> bool:
	var code: String = _code_of("res://sim/modules/sightings.gd")
	if code.is_empty():
		push_error("BEHIND-READER: could not read sim/modules/sightings.gd")
		return false
	var lines: PackedStringArray = code.split("\n")
	var start: int = -1
	var end: int = lines.size()
	for i in lines.size():
		var trimmed: String = String(lines[i]).strip_edges()
		if trimmed.begins_with("static func _observe_one("):
			start = i
			continue
		if start >= 0 and i > start and trimmed.begins_with("static func "):
			end = i
			break
	if start < 0:
		push_error("BEHIND-READER: sim/modules/sightings.gd has no _observe_one -- this lane is reading the wrong file")
		return false
	var body: String = "\n".join(lines.slice(start, end))
	if not body.contains("world.vision.call(\"detail\""):
		push_error("BEHIND-READER: _observe_one no longer calls detail -- the fix in the BEHIND lane is not reachable")
		return false
	if body.contains("world.vision.call(\"line_of_sight\""):
		push_error("BEHIND-READER: _observe_one still calls line_of_sight alongside detail")
		return false
	print("BEHIND-READER OK _observe_one (lines %d-%d) reads detail, not line_of_sight" % [start + 1, end])
	return true


# --- KINDS ---------------------------------------------------------------------------------
#
# Slice 2, sight memory. `_observe_one` used to query `["shambler", "position"]` alone, so a
# colonist glimpsed and then lost behind a building left no trace an NPC or the HUD could read.
# Every body with a `body` and a `position` now qualifies, tagged with a `kind`, and `clause()`
# and `freshest_within` narrow back down to the two hostile kinds -- a remembered colonist must
# never read as a threat, on the HUD or down an NPC's barrel.

func _colonist(w: Variant, x: float, y: float) -> int:
	var ent: int = int(w.entities.spawn())
	w.components.set_component(ent, "position", {"x": x, "y": y})
	SimHealth.make_survivor_body(w, ent)
	return ent


func _kinds_are_recorded_and_only_hostiles_are_a_threat() -> bool:
	var w: Variant = _world(false)
	SimSurvivors.give_eyes(w, w.player)
	var z: int = _zombie(w, 16.5, 12.5)
	# Closer to the player than the shambler is -- if the exemption below fell through, this is
	# the body a naive "closest thing remembered" would pick instead.
	var person: int = _colonist(w, 12.5, 12.5)
	w.step()

	var z_row: Variant = SimSightings.recall(w, w.player, z)
	var p_row: Variant = SimSightings.recall(w, w.player, person)
	if not z_row is Dictionary or String((z_row as Dictionary)["kind"]) != "zombie":
		push_error("KINDS: the shambler's own record does not carry kind zombie (%s)" % str(z_row))
		return false
	if not p_row is Dictionary or String((p_row as Dictionary)["kind"]) != "person":
		push_error("KINDS: the colonist's own record does not carry kind person (%s)" % str(p_row))
		return false

	var clause: String = SimSightings.clause(w, w.player)
	if not clause.contains("one of them"):
		push_error("KINDS: with one hostile and one colonist in view, the clause reads '%s', not 'one of them'" % clause)
		return false
	var closest: Variant = SimSightings.freshest_within(w, w.player, 20.0)
	if not closest is Dictionary or int((closest as Dictionary)["entity"]) != z:
		push_error("KINDS: freshest_within with a colonist standing closer than the shambler returned %s, not the shambler" % str(closest))
		return false

	# The negative: the same colonist, alone -- nothing hostile left to report or fire at. Without
	# this, the exemption above could just as well be "the shambler happened to win," proving
	# nothing about the colonist being filtered rather than merely outranked.
	var w2: Variant = _world(false)
	SimSurvivors.give_eyes(w2, w2.player)
	_colonist(w2, 12.5, 12.5)
	w2.step()
	if SimSightings.clause(w2, w2.player) != "":
		push_error("KINDS: a colonist alone in view produced a clause -- a remembered person read as a threat")
		return false
	if SimSightings.freshest_within(w2, w2.player, 20.0) != null:
		push_error("KINDS: freshest_within returned a colonist -- an NPC would fire at somebody on its own side")
		return false
	print("KINDS OK zombie=zombie person=person clause='%s' (colonist excluded), freshest=shambler despite range, colonist-alone=quiet" % clause)
	return true


# --- EXPLORED --------------------------------------------------------------------------------
#
# The remembered map: a per-observer bitset over every tile the shadowcast has ever reached,
# merged only on the tick the cast actually recomputes (SimVisibility.cast_generation). Walking
# away must not clear a bit -- that is the whole point, `main.gd`'s dimmed street outside the
# current cone -- and a save is a JSON round trip, which is exactly where a PackedByteArray
# component would come back wrong and a base64 String does not (CLAUDE.md's packed-array trap).

func _the_remembered_map_marks_the_cast_and_survives_a_save() -> bool:
	var w: Variant = _world(true, true)
	SimSurvivors.give_eyes(w, w.player)
	w.step()

	# True positive: a tile beside the observer, and one reached only through the open doorway.
	if not SimSightings.knows_tile(w, w.player, 8, DOOR_Y):
		push_error("EXPLORED: a tile well inside the observer's own cast was never marked explored")
		return false
	if not SimSightings.knows_tile(w, w.player, 16, DOOR_Y):
		push_error("EXPLORED: the tile seen through the doorway was never marked explored")
		return false
	# The negative: a tile behind the solid run of wall, off the door row, that the shadowcast
	# never reaches at all.
	if SimSightings.knows_tile(w, w.player, 16, DOOR_Y - 8):
		push_error("EXPLORED: a tile behind a solid wall run reads explored -- the shadowcast never reached it")
		return false

	# Walk away: the bit must stay set once the observer can no longer see the tile.
	w.components.set_component(w.player, "position", {"x": 2.5, "y": 2.5})
	for i in 5:
		w.step()
	if bool(w.vision.call("can_see", w.player, 16.5, float(DOOR_Y) + 0.5)):
		push_error("EXPLORED: the observer can still see the far tile -- the walk-away control proves nothing")
		return false
	if not SimSightings.knows_tile(w, w.player, 16, DOOR_Y):
		push_error("EXPLORED: a tile explored earlier was forgotten once the observer walked away")
		return false

	# The save round trip: real JSON text, not a Dictionary handed back to itself -- the trap a
	# PackedByteArray component falls into and a base64 String does not.
	var text: String = SimSave.encode_save(SimSave.create_save(w))
	var decoded: Dictionary = SimSave.decode_save_or_throw(text)
	w.restore(decoded["snapshot"] as Dictionary)
	if not SimSightings.knows_tile(w, w.player, 16, DOOR_Y):
		push_error("EXPLORED: the remembered map did not survive a save/load round trip")
		return false

	# A second observer's map is its own: sharing the world and the tick is not sharing memory.
	var second: int = int(w.entities.spawn())
	w.components.set_component(second, "position", {"x": 2.5, "y": 2.5})
	w.components.set_component(second, "facing", {"radians": 0.0})
	SimHealth.make_survivor_body(w, second)
	SimSurvivors.give_eyes(w, second)
	SimSightings.attach(w, second)
	w.step()
	if SimSightings.knows_tile(w, second, 16, DOOR_Y):
		push_error("EXPLORED: a second observer who never stood near the doorway already knows the far tile -- the maps are not per-observer")
		return false
	print("EXPLORED OK the cast marks explored tiles, a wall run is never marked, the map survives walking away and a save round trip, and a second observer keeps its own")
	return true


# --- HEIGHT ------------------------------------------------------------------------------------
#
# docs/40's Perception, slice 4: sight works by height. The 2D cast is cast for everyone as a
# standing eye, and a body is seen only if a line from the observer's eye to the body's eye or its
# chest clears every partial-height tile between -- a car (Low, 0-1100 mm), a window's sill
# (0-1000), a stage-3 board (0-1100), an open door's lintel (2200-2550). This lane replaces the EYE
# lane's planar rule (a crouched observer's whole cast blocked by Low, the target's height never
# asked), as docs/40's "What stays green, and what is replaced" names. The EYE lane still runs,
# under `SimVisibility.SIGHT_BY_HEIGHT` pinned false, and proves the switch gives that rule back.
#
# Every pair below is the same fixture twice with one thing changed -- a stance, a board's stage, a
# door's state, a target's height -- so a hit and a miss differ by what the rule is about and by
# nothing else. All on row 12, the observer to the west facing east, so the arcs are never the
# reason for an answer.

const SimSpace = preload("res://sim/space/space.gd")
const SimScreamer = preload("res://sim/modules/screamer.gd")

const ROW: int = 12


# A 24x24 floor with `tiles` ([x, y, Tile]) and `overlays` ([x, y, Dictionary]) written in, and the
# player parked out of every sightline in the far corner, facing away, unless a case moves it.
func _height_world(tiles: Array = [], overlays: Array = []) -> Variant:
	var f: Dictionary = {"seed": 77, "tick_hz": 20, "map": {"width": MAP_TILES, "height": MAP_TILES, "walls": []}, "player": {"id": 0, "x": 1.5, "y": 22.5, "stance": SimStancesRes.Stance.Walk}, "rng_probe": {"stream": "test", "samples": 0}}
	var w: Variant = World.new(f)
	w.tick = Clock.tick_at_time_of_day(0.5)
	var map: Variant = SimTileMap.blank_map(MAP_TILES, MAP_TILES)
	for t in tiles:
		map.tiles[int(t[1]) * MAP_TILES + int(t[0])] = int(t[2])
	for o in overlays:
		map.overlays[int(o[1]) * MAP_TILES + int(o[0])] = (o[2] as Dictionary).duplicate()
	SimBoot.attach_kernel(w, map)
	SimHealth.register_module(w)
	SimSightings.register_module(w)
	w.components.set_component(w.player, "facing", {"radians": PI})
	SimHealth.make_survivor_body(w, w.player)
	return w


# The wall column at WALL_X with one opening at (WALL_X, ROW) of the given tile class.
func _wall_with(opening: int) -> Array:
	var out: Array = []
	for y in MAP_TILES:
		out.append([WALL_X, y, opening if y == ROW else SimTileMap.Tile.Wall])
	return out


# A survivor body at (x, y) in a stance, facing `radians`; with eyes when `eyes`.
func _person(w: Variant, x: float, y: float, stance: int, radians: float = PI, eyes: bool = false) -> int:
	var ent: int = int(w.entities.spawn())
	w.components.set_component(ent, "position", {"x": x, "y": y})
	w.components.set_component(ent, "facing", {"radians": radians})
	w.components.set_component(ent, "posture", SimStancesRes.make_posture(stance))
	SimHealth.make_survivor_body(w, ent)
	if eyes:
		SimSurvivors.give_eyes(w, ent)
	return ent


func _stand(w: Variant, ent: int, stance: int) -> void:
	w.components.set_component(ent, "posture", SimStancesRes.make_posture(stance))


func _zombie_at(w: Variant, x: float, y: float, radians: float = 0.0, type_id: String = SimRoster.TYPE_SHAMBLER) -> int:
	var z: int = SimRoster.spawn_zombie(w, x, y, type_id, w.rng.stream("shambler"))
	w.events.drain()
	w.components.set_component(z, "facing", {"radians": radians})
	return z


func _seen(w: Variant, observer: int, target: int) -> bool:
	return int(w.vision.call("detail_body", observer, target)) != SimVisibility.Detail.Unseen


func _height_fail(msg: String) -> bool:
	push_error("HEIGHT: " + msg)
	return false


func _sight_works_by_height() -> bool:
	if not SimVisibility.SIGHT_BY_HEIGHT:
		return _height_fail("the shipped default is off -- docs/33's recommended answer to the owner's question 3 is yes")
	var crouch: int = SimStancesRes.Stance.Crouch
	var walk: int = SimStancesRes.Stance.Walk
	var lines: Array[String] = []

	# CAR: a standing zombie six metres off loses a crouched survivor half a metre behind a car, and
	# sees the same survivor stood up. The control: the same crouched survivor in open ground is seen,
	# so crouching alone is not what hides you.
	var car: Variant = _height_world([[13, ROW, SimTileMap.Tile.Low]])
	var cz: int = _zombie_at(car, 8.5, 12.5)
	var cp: int = _person(car, 14.5, 12.5, crouch)
	car.step()
	if _seen(car, cz, cp):
		return _height_fail("a standing zombie six metres off saw a crouched survivor behind a car")
	_stand(car, cp, walk)
	if not _seen(car, cz, cp):
		return _height_fail("a standing zombie did not see a standing survivor over a car")
	var open: Variant = _height_world()
	var oz: int = _zombie_at(open, 8.5, 12.5)
	var op: int = _person(open, 14.5, 12.5, crouch)
	open.step()
	if not _seen(open, oz, op):
		return _height_fail("a crouched survivor in open ground was unseen -- the vertical test invented cover")
	lines.append("car: crouched=hidden standing=seen open-ground-crouched=seen")

	# OVER: a crouched survivor sees a standing zombie's head over a car, and does not see a crouched
	# survivor behind the same car. The car is two tiles, (13,12) and (13,13).
	var over: Variant = _height_world([[13, ROW, SimTileMap.Tile.Low], [13, ROW + 1, SimTileMap.Tile.Low]])
	var looker: int = _person(over, 8.5, 12.5, crouch, 0.0, true)
	var head: int = _zombie_at(over, 14.5, 12.5, PI)
	var low: int = _person(over, 14.5, 13.5, crouch)
	over.step()
	if not _seen(over, looker, head):
		return _height_fail("a crouched survivor did not see a standing head over a car")
	if _seen(over, looker, low):
		return _height_fail("a crouched survivor saw a crouched body behind a car")
	# The planar rule this replaces blinded the crouched survivor's whole cast at the car: the ground
	# behind it is now seen, as a place.
	if int(over.vision.call("detail", looker, 14.5, 13.5)) == SimVisibility.Detail.Unseen:
		return _height_fail("a crouched survivor's cast is still blocked by Low -- the 2D layer is not standing")
	if int((over.components.get_component(looker, "observer") as Dictionary)["eye"]) != SimTileMap.Eye.Standing:
		return _height_fail("a crouched survivor's observer was cast from Eye.Crouched")
	lines.append("over: standing-head=seen crouched-body=hidden ground-behind=seen")

	# WINDOW: someone crouched under a sill is unseen from six metres outside, seen stood up, and seen
	# from close outside, where the line comes down over the sill. Symmetric where the heights are
	# equal, by the eye: the crouched survivor does not see the zombie's head or chest either.
	var win: Variant = _height_world(_wall_with(SimTileMap.Tile.Window))
	var wz: int = _zombie_at(win, 7.5, 12.5)
	var inside: int = _person(win, 13.5, 12.5, crouch, PI, true)
	win.step()
	if _seen(win, wz, inside):
		return _height_fail("a zombie six metres outside saw a survivor crouched under the sill")
	if _seen(win, inside, wz):
		return _height_fail("a survivor crouched under the sill saw the zombie six metres outside")
	_stand(win, inside, walk)
	if not _seen(win, wz, inside):
		return _height_fail("a zombie did not see a standing survivor through an open window")
	if not _seen(win, inside, wz):
		return _height_fail("a standing survivor did not see the zombie through an open window")
	_stand(win, inside, crouch)
	var close: Variant = _height_world(_wall_with(SimTileMap.Tile.Window))
	var near_z: int = _zombie_at(close, 11.5, 12.5)
	var under: int = _person(close, 13.5, 12.5, crouch)
	close.step()
	if not _seen(close, near_z, under):
		return _height_fail("a zombie half a metre outside the window did not see down over the sill")
	lines.append("window: crouched-6m=hidden both-ways standing=seen both-ways crouched-from-close=seen")

	# BOARD: a stage-3 board (sill-height boards, 0-1100) hides a crouched body and not a standing one;
	# a stage-2 board is a wall to sight and hides both, by the 2D layer.
	var results: Dictionary = {}
	for stage in [3, 2]:
		var bw: Variant = _height_world(_wall_with(SimTileMap.Tile.Window), [[WALL_X, ROW, {"kind": "board", "stage": stage}]])
		var bz: int = _zombie_at(bw, 7.5, 12.5)
		var bp: int = _person(bw, 13.5, 12.5, crouch)
		bw.step()
		var crouched_seen: bool = _seen(bw, bz, bp)
		_stand(bw, bp, walk)
		results[stage] = [crouched_seen, _seen(bw, bz, bp)]
	if bool((results[3] as Array)[0]):
		return _height_fail("a zombie saw a survivor crouched behind a stage-3 board")
	if not bool((results[3] as Array)[1]):
		return _height_fail("a zombie did not see a standing survivor over a stage-3 board")
	if bool((results[2] as Array)[1]):
		return _height_fail("a zombie saw a standing survivor through a stage-2 board")
	lines.append("board: stage3-crouched=hidden stage3-standing=seen stage2-standing=hidden")

	# DOOR: an open door shows the room and a closed one does not. The lintel (2200-2550) stops a line
	# rising steeply through the doorway, and passes the same line a little lower.
	var door_seen: Dictionary = {}
	for state in ["open", "closed"]:
		var ov: Array = [] if state == "open" else [[WALL_X, ROW, {"kind": "door", "open": false}]]
		var dw: Variant = _height_world(_wall_with(SimTileMap.Tile.Door), ov)
		var dz: int = _zombie_at(dw, 7.5, 12.5)
		var dp: int = _person(dw, 13.5, 12.5, walk)
		dw.step()
		door_seen[state] = _seen(dw, dz, dp)
	if not bool(door_seen["open"]):
		return _height_fail("a zombie did not see a standing survivor through an open door")
	if bool(door_seen["closed"]):
		return _height_fail("a zombie saw a standing survivor through a closed door")
	var lw: Variant = _height_world(_wall_with(SimTileMap.Tile.Door))
	lw.components.set_component(lw.player, "position", {"x": 10.5, "y": 12.5})
	lw.components.set_component(lw.player, "facing", {"radians": 0.0})
	SimSurvivors.give_eyes(lw, lw.player)
	lw.step()
	var under_lintel: int = int(lw.vision.call("detail", lw.player, 13.2, 12.5, 2100))
	var into_lintel: int = int(lw.vision.call("detail", lw.player, 13.2, 12.5, 2500))
	if under_lintel == SimVisibility.Detail.Unseen:
		return _height_fail("a point under the lintel, through an open doorway, was unseen")
	if into_lintel != SimVisibility.Detail.Unseen:
		return _height_fail("a line rising through an open doorway passed the lintel")
	lines.append("door: open=seen closed=hidden under-lintel=seen through-lintel=hidden")

	# SYMMETRY where the heights are equal: two standing survivors across a car see each other, two
	# crouched ones do not.
	var sym: Variant = _height_world([[13, ROW, SimTileMap.Tile.Low]])
	var sa: int = _person(sym, 8.5, 12.5, walk, 0.0, true)
	var sb: int = _person(sym, 14.5, 12.5, walk, PI, true)
	sym.step()
	if not (_seen(sym, sa, sb) and _seen(sym, sb, sa)):
		return _height_fail("two standing survivors across a car did not both see each other")
	_stand(sym, sa, crouch)
	_stand(sym, sb, crouch)
	if _seen(sym, sa, sb) or _seen(sym, sb, sa):
		return _height_fail("two crouched survivors saw each other across a car")
	lines.append("symmetry: standing-pair=both crouched-pair=neither")

	# The table this lane trusts: SIGHT_PARTIAL is what PROFILE says is partial for sight, and the
	# class bytes the walk reads first say the same as each class's own key.
	for key in SimSpace.PROFILE.keys():
		if SimSpace.sight_partial(String(key)) != SimSpace.SIGHT_PARTIAL.has(key):
			return _height_fail("SIGHT_PARTIAL disagrees with PROFILE at '%s'" % String(key))
	var blank: Variant = SimTileMap.blank_map(2, 1)
	for t in SimSpace.SIGHT_PARTIAL_CLASS.size():
		blank.tiles[0] = t
		if SimSpace.SIGHT_PARTIAL_CLASS[t] != SimSpace.SIGHT_PARTIAL.has(SimSpace.profile_key(blank, 0, 0)):
			return _height_fail("SIGHT_PARTIAL_CLASS disagrees with the key of tile class %d" % t)
	if SimSpace.SIGHT_PARTIAL.has("wall") or not SimSpace.SIGHT_PARTIAL.has("low"):
		return _height_fail("SIGHT_PARTIAL holds a wall or misses Low")
	# The standing broadphase's corridor: every partial tile's sight band lies wholly at or below its
	# floor or at or above its ceiling, so a line inside it can meet none of them.
	for key in SimSpace.SIGHT_PARTIAL.keys():
		for band in SimSpace.bands(String(key)):
			var bnd: Array = band as Array
			if int(bnd[2]) & SimSpace.SIGHT == 0:
				continue
			if not (int(bnd[1]) <= SimSpace.SIGHT_OPEN_FROM_MM or int(bnd[0]) >= SimSpace.SIGHT_OPEN_TO_MM):
				return _height_fail("the open corridor %d-%d meets %s's sight band %s" % [SimSpace.SIGHT_OPEN_FROM_MM, SimSpace.SIGHT_OPEN_TO_MM, String(key), str(bnd)])
	# And it is the widest such corridor, or the broadphase is skipping walks for nothing: Low reaches
	# its floor and the window's lintel its ceiling.
	if SimSpace.sight_clear(blank_corridor_map(), {"x": 0.5, "y": 0.5, "h": SimSpace.SIGHT_OPEN_FROM_MM - 1}, {"x": 2.5, "y": 0.5, "h": SimSpace.SIGHT_OPEN_FROM_MM - 1}):
		return _height_fail("a line just under the corridor's floor passed a Low tile")
	if not SimSpace.sight_clear(blank_corridor_map(), {"x": 0.5, "y": 0.5, "h": SimSpace.SIGHT_OPEN_FROM_MM}, {"x": 2.5, "y": 0.5, "h": SimSpace.SIGHT_OPEN_FROM_MM}):
		return _height_fail("a line on the corridor's floor was stopped by a Low tile")
	lines.append("table: SIGHT_PARTIAL = PROFILE's partial keys")

	print("HEIGHT OK " + "; ".join(lines))
	return true


# CRAWLER: a crawler is a zombie whose legs are gone (`SimHealth.is_crawling`), and its body is 450 mm
# tall with its eye at 300 (`SimSpace._volume`). Behind Low cover (top 1100) a standing survivor sees
# a shambler at the same spot and does not see the crawler; a crawling survivor does not see it
# either. The true negative is the same crawler with its legs restored, which must be seen.
func _a_crawler_hides_below_low_cover() -> bool:
	var walk: int = SimStancesRes.Stance.Walk
	var crawl: int = SimStancesRes.Stance.Crawl
	var lines: Array[String] = []

	var standing: Variant = _height_world([[13, ROW, SimTileMap.Tile.Low]])
	var sp: int = _person(standing, 8.5, 12.5, walk, 0.0, true)
	var cr: int = _zombie_at(standing, 14.5, 12.5, PI, "zombie.crawler")
	standing.step()
	if not SimHealth.is_crawling(standing.components.get_component(cr, "body") as Dictionary):
		return _height_fail("a spawned zombie.crawler is not crawling on its first tick -- its legs did not go")
	if _seen(standing, sp, cr):
		return _height_fail("a standing survivor saw a crawler behind a Low tile")
	lines.append("crawler: standing-behind-low=hidden")

	var control: Variant = _height_world([[13, ROW, SimTileMap.Tile.Low]])
	var csp: int = _person(control, 8.5, 12.5, walk, 0.0, true)
	var sham: int = _zombie_at(control, 14.5, 12.5, PI)
	control.step()
	if not _seen(control, csp, sham):
		return _height_fail("a standing survivor did not see a shambler behind a Low tile -- the crawler's hiding proves nothing")
	lines.append("shambler-same-spot=seen")

	var crawling: Variant = _height_world([[13, ROW, SimTileMap.Tile.Low]])
	var kp: int = _person(crawling, 8.5, 12.5, crawl, 0.0, true)
	var kc: int = _zombie_at(crawling, 14.5, 12.5, PI, "zombie.crawler")
	crawling.step()
	if _seen(crawling, kp, kc):
		return _height_fail("a crawling survivor (eye 300 mm) saw a crawler behind a Low tile")
	lines.append("crawling-survivor=hidden")

	# The true negative: restore the legs, and the same crawler stands 1650 mm tall and is seen.
	var restored: Variant = _height_world([[13, ROW, SimTileMap.Tile.Low]])
	var rp: int = _person(restored, 8.5, 12.5, walk, 0.0, true)
	var rc: int = _zombie_at(restored, 14.5, 12.5, PI, "zombie.crawler")
	var body: Dictionary = (restored.components.get_component(rc, "bodyMax") as Dictionary).duplicate()
	restored.components.set_component(rc, "body", body)
	restored.step()
	if SimHealth.is_crawling(body):
		return _height_fail("restoring the crawler's legs did not stop it crawling")
	if not _seen(restored, rp, rc):
		return _height_fail("a standing survivor did not see the crawler once its legs were restored")
	lines.append("legs-restored=seen")

	print("CRAWLER OK " + "; ".join(lines))
	return true


# Three tiles in a row, a Low tile in the middle: the corridor check's fixture.
func blank_corridor_map() -> Variant:
	var m: Variant = SimTileMap.blank_map(3, 1)
	m.tiles[1] = SimTileMap.Tile.Low
	return m


# The dead-socket rule: every consumer docs/40 names reads the height, shown by what it does.
func _the_consumers_read_the_height() -> bool:
	var crouch: int = SimStancesRes.Stance.Crouch
	var walk: int = SimStancesRes.Stance.Walk
	# The dead's eyes: `_seen_target` picks a standing survivor behind a car and not a crouched one.
	# Three metres off, inside a shambler's daylight reach (`sight_reach`, under four metres).
	var w: Variant = _height_world([[13, ROW, SimTileMap.Tile.Low]])
	var z: int = _zombie_at(w, 11.5, 12.5)
	var p: int = _person(w, 14.5, 12.5, crouch)
	w.step()
	var data: Variant = w.components.get_component(z, "shambler")
	var sd: Dictionary = data as Dictionary if data is Dictionary else {}
	var pick_crouched: Variant = SimShambler._seen_target(w, z, [{"entity": p, "x": 14.5, "y": 12.5}], sd)
	_stand(w, p, walk)
	var pick_standing: Variant = SimShambler._seen_target(w, z, [{"entity": p, "x": 14.5, "y": 12.5}], sd)
	if pick_crouched != null:
		return _height_fail("CONSUMERS: a shambler's eyes picked a survivor crouched behind a car")
	if pick_standing == null or int(pick_standing) != p:
		return _height_fail("CONSUMERS: a shambler's eyes did not pick a standing survivor over a car (%s)" % str(pick_standing))

	# The screamer: no alarm over a survivor crouched under a sill, an alarm once they stand.
	var alarms: Dictionary = {}
	for stance in [crouch, walk]:
		var sw: Variant = _height_world(_wall_with(SimTileMap.Tile.Window))
		SimScreamer.register_module(sw)
		var scream: int = _zombie_at(sw, 7.5, 12.5, 0.0, SimRoster.TYPE_SCREAMER)
		sw.components.set_component(sw.player, "position", {"x": 13.5, "y": 12.5})
		_stand(sw, sw.player, stance)
		var raised: int = 0
		for i in 3:
			sw.step()
			for e in sw.events.drained:
				if String((e as Dictionary).get("type", "")) == "noise.emitted" and int((e as Dictionary).get("source", -1)) == scream:
					raised += 1
		alarms[stance] = raised
	if int(alarms[crouch]) != 0:
		return _height_fail("CONSUMERS: a screamer raised the alarm over a survivor crouched under a sill")
	if int(alarms[walk]) < 1:
		return _height_fail("CONSUMERS: a screamer did not raise the alarm over a survivor standing at the window")

	# Sightings: a crouched survivor remembers a standing zombie over a car, and not a crawling one
	# behind it -- the same zombie with its legs gone, eye at 300 mm.
	var mw: Variant = _height_world([[13, ROW, SimTileMap.Tile.Low], [13, ROW + 1, SimTileMap.Tile.Low]])
	var me: int = _person(mw, 8.5, 12.5, crouch, 0.0, true)
	var tall: int = _zombie_at(mw, 14.5, 12.5, PI)
	var crawler: int = _zombie_at(mw, 14.5, 13.5, PI)
	(mw.components.get_component(crawler, "body") as Dictionary)["legs"] = 0
	mw.step()
	if SimSightings.recall(mw, me, tall) == null:
		return _height_fail("CONSUMERS: sightings did not record a standing zombie seen over a car")
	if SimSightings.recall(mw, me, crawler) != null:
		return _height_fail("CONSUMERS: sightings recorded a crawling zombie behind a car")

	# And the source: each consumer docs/40 names asks about the body -- `detail` with the body as its
	# fifth argument where the caller holds the position, `detail_body` where it does not -- and
	# visibility asks SimSpace.
	var reads: Dictionary = {
		"res://sim/modules/shambler.gd": "-1, int(s[\"entity\"]))",
		"res://sim/modules/screamer.gd": "-1, int(sd[\"entity\"]))",
		"res://sim/modules/sightings.gd": "-1, int(other)))",
		"res://sim/modules/jobs.gd": "detail_body(",
		"res://sim/modules/orders.gd": "detail_body(",
		"res://sim/work_read.gd": "\"detail_body\"",
		"res://sim/vision/visibility.gd": "SimSpaceRes.sight_points(",
	}
	for path in reads.keys():
		var calls: int = 0
		for line in _code_of(String(path)).split("\n"):
			var trimmed: String = String(line).strip_edges()
			if not trimmed.begins_with("#") and trimmed.contains(String(reads[path])):
				calls += 1
		if calls == 0:
			return _height_fail("CONSUMERS: %s has no live call to %s" % [String(path), String(reads[path])])
	print("HEIGHT-CONSUMERS OK shambler picks standing not crouched; screamer quiet under a sill, loud at it; sightings keep the head over a car, not the crawler; %d sources read it" % reads.size())
	return true


# The switch: SIGHT_BY_HEIGHT false gives back the planar rule, so the owner's "no" is one line. The
# car and window pairs above, asked again with it off, answer the old way: the target's height is
# never asked, so the crouched survivor behind the car and under the sill is seen. The EYE lane
# below runs in the same off state and holds the rest of the old rule.
func _the_switch_gives_back_planar_sight() -> bool:
	var was: bool = SimVisibility.SIGHT_BY_HEIGHT
	SimVisibility.SIGHT_BY_HEIGHT = false
	var car: Variant = _height_world([[13, ROW, SimTileMap.Tile.Low]])
	var cz: int = _zombie_at(car, 8.5, 12.5)
	var cp: int = _person(car, 14.5, 12.5, SimStancesRes.Stance.Crouch)
	car.step()
	var car_seen: bool = _seen(car, cz, cp)
	var win: Variant = _height_world(_wall_with(SimTileMap.Tile.Window))
	var wz: int = _zombie_at(win, 7.5, 12.5)
	var wp: int = _person(win, 13.5, 12.5, SimStancesRes.Stance.Crouch)
	win.step()
	var win_seen: bool = _seen(win, wz, wp)
	var eye_ok: bool = _crouching_lowers_the_eye_over_low_cover()
	SimVisibility.SIGHT_BY_HEIGHT = was
	if not car_seen or not win_seen:
		return _height_fail("OFF: with SIGHT_BY_HEIGHT false a crouched survivor behind a car or under a sill was still hidden (car=%s window=%s)" % [str(car_seen), str(win_seen)])
	if not eye_ok:
		return _height_fail("OFF: the EYE lane's planar rule did not come back with SIGHT_BY_HEIGHT false")
	print("HEIGHT-OFF OK SIGHT_BY_HEIGHT false: car and sill hide nobody by height, and the EYE lane's planar rule holds")
	return true


# --- FEIGN ------------------------------------------------------------------------------------
#
# A feigner is born lying among the dead (`shambler.gd`'s Feign state): it walks to within
# `lieWithin` of the nearest settled corpse, reads no sight, scent or hearing while it lies there,
# and is remembered as a corpse, the same record a settled corpse gets. It rises to Seek when a
# living body comes within `riseRadius`, or when it is struck, and the record flips to a zombie
# when it does.
#   SEE     a colonist 12 m off remembers three corpses (two settled, one feigning) and nothing hostile.
#   STAYS   a body at 1.5 times `riseRadius` leaves it lying for FEIGN_TICKS.
#   RISES   a body within `riseRadius` rises it to Seek within FEIGN_TICKS, and the record flips.
#   PLANT   a feigner whose `riseRadius` is planted at twice the real one rises to a body at 1.5 times
#           the real radius. STAYS must see that, or it could not see a leak; the lane fails if the
#           planted rise does not happen.
#   STRUCK  a struck feigner rises (the blow's own stagger then applies to it as to any shambler).
const FEIGN_SETTLE_TICKS: int = 60
const FEIGN_TICKS: int = 30
const FEIGN_RISE_SETUP: float = 2.5
const FEIGN_CORPSE_PLAYER_M: float = 12.0


func _feigner_world() -> Dictionary:
	var w: Variant = _height_world([])
	SimShambler.register_module(w, null)
	w.components.set_component(w.player, "position", {"x": 8.5, "y": 12.5})
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	SimSurvivors.give_eyes(w, w.player)
	var c1: int = _corpse(w, 19.5, 12.5)
	var c2: int = _corpse(w, 20.5, 11.5)
	var f: int = _zombie_at(w, 23.5, 12.5, 0.0, "zombie.feigner")
	return {"w": w, "f": f, "corpses": [c1, c2]}


# A dead shambler on the ground: head at zero, the `corpse` component, and nothing left to think.
func _corpse(w: Variant, x: float, y: float) -> int:
	var z: int = _zombie_at(w, x, y)
	(w.components.get_component(z, "body") as Dictionary)["head"] = 0.0
	w.components.set_component(z, "corpse", {"sinceTick": int(w.tick)})
	return z


func _feign_state(w: Variant, f: int) -> Dictionary:
	return w.components.get_component(f, "shambler") as Dictionary


func _at(w: Variant, e: int) -> Vector2:
	var p: Dictionary = w.components.get_component(e, "position") as Dictionary
	return Vector2(float(p["x"]), float(p["y"]))


func _move_player(w: Variant, to: Vector2) -> void:
	w.components.set_component(w.player, "position", {"x": to.x, "y": to.y})


func _settled(w: Variant, f: int) -> bool:
	for i in FEIGN_SETTLE_TICKS:
		w.step()
		if bool(_feign_state(w, f).get("feignLying", false)):
			return true
	return bool(_feign_state(w, f).get("feignLying", false))


func _corpse_rows(w: Variant, observer: int) -> int:
	var n: int = 0
	for row in SimSightings.remembered(w, observer):
		if String((row as Dictionary).get("kind", "")) == SimSightings.CORPSE_KIND:
			n += 1
	return n


func _feign_fail(msg: String) -> bool:
	push_error("FEIGN: " + msg)
	return false


func _a_feigner_lies_among_the_dead_and_rises_on_approach() -> bool:
	var a: Dictionary = _feigner_world()
	var w: Variant = a["w"]
	var f: int = int(a["f"])
	if int(_feign_state(w, f)["state"]) != SimShambler.ShamblerState["Feign"]:
		return _feign_fail("a feigner was not born in the Feign state (%d)" % int(_feign_state(w, f)["state"]))
	if not _settled(w, f):
		var dbg: Dictionary = _feign_state(w, f)
		return _feign_fail("the feigner did not lie down within %d ticks (state %d, target %s, at %s, corpse %s)" % [FEIGN_SETTLE_TICKS, int(dbg["state"]), str(dbg.get("feignTarget")), str(_at(w, f)), str(_at(w, int(a["corpses"][0])))])
	var lie_within: float = float((_feign_state(w, f)["feigns"] as Dictionary)["lieWithin"])
	var nearest: float = INF
	for c in a["corpses"]:
		nearest = minf(nearest, _at(w, f).distance_to(_at(w, int(c))))
	if nearest > lie_within + 0.01:
		return _feign_fail("lying %.2f m from the nearest corpse, want within %.2f" % [nearest, lie_within])

	# SEE: a colonist 12 m off remembers three corpses, and nothing about them is hostile.
	var observer_gap: float = _at(w, w.player).distance_to(_at(w, f))
	if absf(observer_gap - FEIGN_CORPSE_PLAYER_M) > 1.0:
		return _feign_fail("the observer stands %.2f m from the feigner, want about %.1f" % [observer_gap, FEIGN_CORPSE_PLAYER_M])
	w.step()
	var corpses: int = _corpse_rows(w, w.player)
	if corpses != 3:
		return _feign_fail("a colonist at %.1f m remembers %d corpses, want 3 (two settled, one feigning)" % [observer_gap, corpses])
	if SimSightings.clause(w, w.player) != "":
		return _feign_fail("the prose says something hostile about a lying feigner: '%s'" % SimSightings.clause(w, w.player))
	var feign_row: Variant = SimSightings.recall(w, w.player, f)
	if not (feign_row is Dictionary) or String((feign_row as Dictionary).get("kind", "")) != SimSightings.CORPSE_KIND:
		return _feign_fail("the feigner is not remembered as a corpse: %s" % str(feign_row))

	# STAYS: a body at 1.5 times the rise radius leaves it lying.
	var rise: float = float((_feign_state(w, f)["feigns"] as Dictionary)["riseRadius"])
	var b: Dictionary = _feigner_world()
	var bw: Variant = b["w"]
	var bf: int = int(b["f"])
	_settled(bw, bf)
	_move_player(bw, _at(bw, bf) + Vector2(-1.5 * rise, 0.0))
	for i in FEIGN_TICKS:
		bw.step()
	if int(_feign_state(bw, bf)["state"]) != SimShambler.ShamblerState["Feign"]:
		return _feign_fail("a body at %.2f m rose a feigner whose radius is %.2f -- it rose at 1.5 times its radius" % [1.5 * rise, rise])

	# RISES: a body within the radius rises it, and its record flips from corpse to zombie.
	var c: Dictionary = _feigner_world()
	var cw: Variant = c["w"]
	var cf: int = int(c["f"])
	_settled(cw, cf)
	_move_player(cw, _at(cw, cf) + Vector2(-0.5 * rise, 0.0))
	var risen: bool = false
	for i in FEIGN_TICKS:
		cw.step()
		if int(_feign_state(cw, cf)["state"]) == SimShambler.ShamblerState["Seek"]:
			risen = true
			break
	if not risen:
		return _feign_fail("a body at %.2f m, inside the radius %.2f, did not rise the feigner within %d ticks" % [0.5 * rise, rise, FEIGN_TICKS])
	cw.step()
	var after: Variant = SimSightings.recall(cw, cw.player, cf)
	if not (after is Dictionary) or String((after as Dictionary).get("kind", "")) != "zombie":
		return _feign_fail("the feigner's record did not flip to a zombie after it rose: %s" % str(after))

	# PLANT: the real radius is doubled in the component. STAYS must catch the early rise.
	var d: Dictionary = _feigner_world()
	var dw: Variant = d["w"]
	var df: int = int(d["f"])
	_settled(dw, df)
	(_feign_state(dw, df)["feigns"] as Dictionary)["riseRadius"] = 2.0 * rise
	_move_player(dw, _at(dw, df) + Vector2(-1.5 * rise, 0.0))
	var planted_rose: bool = false
	for i in FEIGN_TICKS:
		dw.step()
		if int(_feign_state(dw, df)["state"]) == SimShambler.ShamblerState["Seek"]:
			planted_rose = true
			break
	if not planted_rose:
		return _feign_fail("a feigner planted at twice its radius did not rise to a body at 1.5 times the real one, so STAYS could not see a leak")

	# STRUCK: a blow rises a lying feigner, even with the player far off.
	var e: Dictionary = _feigner_world()
	var ew: Variant = e["w"]
	var ef: int = int(e["f"])
	_settled(ew, ef)
	ew.events.publish({"type": "attack.connected", "attacker": ew.player, "target": ef, "bodyPart": "torso", "damage": 1.0})
	ew.step()
	# Risen, not lying: the blow's own stagger then takes it as it takes any shambler, so the state
	# is Seek or Staggered. It is never still Feign.
	var struck_state: int = int(_feign_state(ew, ef)["state"])
	if struck_state == SimShambler.ShamblerState["Feign"] or bool(_feign_state(ew, ef).get("feignLying", false)):
		return _feign_fail("a struck feigner did not rise (state %d, lying %s)" % [struck_state, str(_feign_state(ew, ef).get("feignLying", false))])

	print("FEIGN OK lay within %.2f m of two corpses; a colonist at %.1f m remembers %d corpses and nothing hostile; a body at %.2f m (1.5 times the %.1f m radius) left it lying; at %.2f m it rose and its record became a zombie; a planted radius of %.1f m rose it at 1.5 times the real one; a struck feigner rose" % [
		lie_within, observer_gap, corpses, 1.5 * rise, rise, 0.5 * rise, 2.0 * rise,
	])
	return true
