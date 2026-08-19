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
const SimSurvivors = preload("res://sim/modules/survivors.gd")
const SimVisibility = preload("res://sim/vision/visibility.gd")
const Clock = preload("res://sim/time/clock.gd")

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
	if ok:
		print("M2_SIGHT_OK sight memory prose recall")
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
