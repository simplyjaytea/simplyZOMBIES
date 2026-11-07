extends SceneTree
# The first-person encounter gate: one zombie against the first-person player, from first sight or
# sound to the grab, the wound, the player's death, and what the player can do back. It boots the
# seeded district the first-person scene boots (SimBoot.playable with the scene's own seed and size)
# and reads and steps the sim only. No module is changed. Every lane's numbers are printed; a lane
# that cannot pass prints FAIL and the gate exits non-zero.
#
#   SIGHT    a shambler 12 m away on open ground, with line of sight, acquires the player within
#            ACQUIRE_TICKS (the module's own target, _seen_target, must be the player) and closes.
#   NOISE    a shambler 30 m away behind one wall tile, with no line of sight (checked first), hears
#            a shot published as noise.emitted at the player, turns toward it and closes.
#   CONTACT  the shambler reaches the player and a grab forms (the hold is set on both bodies, with
#            SimShambler._clear_contact true at that tick); a bite then lands as a wound.
#   DEATH    the CONTACT run continues until the player dies: world.player moves to an heir, or
#            world.runOver is set. Those are the end states the first-person scene reads.
#   BREAK    a second CONTACT run in which the player presses F (a swing) while held: the grab
#            breaks, or the zombie takes a hit.
#
# Setup is placement only: the district's own zombies are removed, other survivors are parked 40 m
# from the player, and the player is put on a standing spot. The shot is a noise.emitted event, the
# event ranged.gd publishes for a shot, because the fixture has no firearm to fire; the magnitude is
# ranged.gd's default for a weapon that names no noise. Nothing is loosened: a lane whose mechanic is
# missing fails with the reason. A lane that depends on an earlier lane's contact does not run and
# says so.

const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimAptitudesRes = preload("res://sim/modules/aptitudes.gd")

const SEED: int = SimBoot.DISTRICT_SEED
# The district size the first-person scene boots its gates on: small on purpose, as in
# check_fp_expedition, so every lane walks the sim and not the map.
const DISTRICT_TILES: int = 64
const SIGHT_METRES: int = 12
# CONTACT and BREAK start the shambler inside its own sight reach (about 3.8 m, see SIGHT), so the
# acquisition is the sim's and only the contact is under test.
const CONTACT_METRES: int = 3
const NOISE_METRES: int = 30
const WALL_AT_METRES: int = 15
# ranged.gd's default noise for a weapon that names none (`weapon.get("noise", 4)`).
const SHOT_MAGNITUDE: float = 4.0
const PARK_METRES: float = 40.0
const ACQUIRE_TICKS: int = 60
const CLOSE_TICKS: int = 40
const CLOSE_METRES: float = 1.0
const REACT_TICKS: int = 200
const NOISE_CLOSE_TICKS: int = 80
const GRAB_TICKS: int = 400
const BITE_TICKS: int = 200
const DEATH_TICKS: int = 3000
const BREAK_TICKS: int = 300
const SWING_EVERY_TICKS: int = 12
const STRUGGLE_TICKS: int = 16
# Open lines tried for the encounter before the gate says the district has none in sight.
const ENCOUNTER_CANDIDATES: int = 200
const MOVED_METRES: float = 0.05
const TIME_BUDGET_SECONDS: float = 60.0

var _failures: Array[String] = []
var _started_ms: int = 0
# Subscription ids are unique per gate run, because the event bus refuses a duplicate id.
var _sub_serial: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_started_ms = Time.get_ticks_msec()
	var sight_ok: bool = _sight_lane()
	var noise_ok: bool = _noise_lane()
	var contact_ok: bool = _contact_and_death_lanes()
	var break_ok: bool = _break_lane()
	var seconds: float = float(Time.get_ticks_msec() - _started_ms) / 1000.0
	var ok: bool = sight_ok and noise_ok and contact_ok and break_ok
	if seconds > TIME_BUDGET_SECONDS:
		_fail("TIME", "the gate took %.1f s, over its %.0f s budget" % [seconds, TIME_BUDGET_SECONDS])
		ok = false
	if ok:
		print("FP_ENCOUNTER_OK all five lanes (SIGHT, NOISE, CONTACT, DEATH, BREAK) in %.1f s" % seconds)
		quit(0)
		return
	print("FP_ENCOUNTER_RESULT not every lane passed, in %.1f s" % seconds)
	quit(1)


func _ok(lane: String, message: String) -> bool:
	print("FP_ENCOUNTER_OK %s %s" % [lane, message])
	return true


func _fail(lane: String, message: String) -> bool:
	var line: String = "FP_ENCOUNTER_FAIL %s %s" % [lane, message]
	_failures.append(line)
	push_error(line)
	return false


# --- SETUP -----------------------------------------------------------------------------------------

# A fresh seeded district, with the district's own zombies removed and the other survivors parked.
func _boot() -> Dictionary:
	var boot: Dictionary = SimBoot.playable(SEED, DISTRICT_TILES)
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	_clear_the_district(world, map)
	return {"world": world, "map": map}


func _clear_the_district(world: Variant, map: Variant) -> void:
	var doomed: Array = []
	for ent in world.components.query(["zombieType"]):
		doomed.append(int(ent))
	for ent in world.components.query(["shambler"]):
		if not doomed.has(int(ent)):
			doomed.append(int(ent))
	for ent in doomed:
		world.despawn(int(ent))
	var player: int = int(world.player)
	var here: Vector2 = _entity_pos(world, player)
	var far: Vector2i = _far_open_tile(map, here, PARK_METRES)
	for ent in world.components.query(["identity", "position"]):
		if int(ent) == player:
			continue
		_place(world, int(ent), _centre(far))


# Open lines of `metres + 1` tiles, in a fixed scan order, from the first `limit` that exist.
func _open_lines(map: Variant, metres: int, limit: int) -> Array:
	var out: Array = []
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
	for y in range(1, int(map.h) - 1):
		for x in range(1, int(map.w) - 1):
			for d in dirs:
				var clear: bool = true
				for k in range(0, metres + 1):
					var t: Vector2i = Vector2i(x, y) + d * k
					if not _open_ground(map, t.x, t.y):
						clear = false
						break
				if clear:
					out.append({"from": Vector2i(x, y), "dir": d})
					if out.size() >= limit:
						return out
	return out


func _open_line(map: Variant, metres: int) -> Dictionary:
	var lines: Array = _open_lines(map, metres, 1)
	return {} if lines.is_empty() else (lines[0] as Dictionary)


func _far_open_tile(map: Variant, here: Vector2, min_metres: float) -> Vector2i:
	for y in range(1, int(map.h) - 1):
		for x in range(1, int(map.w) - 1):
			if not _open_ground(map, x, y):
				continue
			if _centre(Vector2i(x, y)).distance_to(here) >= min_metres:
				return Vector2i(x, y)
	return Vector2i(1, 1)


func _open_ground(map: Variant, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= int(map.w) or y >= int(map.h):
		return false
	if SimTileMap.tile_at(map, x, y) != SimTileMap.Tile.Floor:
		return false
	if SimTileMap.is_solid(map, x, y):
		return false
	return not SimTileMap.is_indoors(map, x, y)


# The shared setup of SIGHT, CONTACT and BREAK: the player on one end of an open line, a shambler
# `metres` away on the other, the vision settled. Returns {} when the district has no such line.
# The first open line on which the sim's own sight holds (the shambler's detail on the player is
# above zero once the vision has settled). A line the zombie cannot see down is not "in the open with
# line of sight", so it is passed over, not measured. The lit-target rule (docs/40) decides which.
func _encounter(world: Variant, map: Variant, metres: int) -> Dictionary:
	var player: int = int(world.player)
	SimMelee.make_melee_armed(world, player)
	SimHealth.make_stamina(world, player, 100)
	for line in _open_lines(map, metres, ENCOUNTER_CANDIDATES):
		var from: Vector2i = (line as Dictionary)["from"]
		var d: Vector2i = (line as Dictionary)["dir"]
		_place(world, player, _centre(from))
		var zed: int = _spawn(world, _centre(from + d * metres))
		_settle(world, 6)
		if _detail(world, zed, player) > 0:
			return {"player": player, "zed": zed, "from": from, "dir": d}
		world.despawn(zed)
	return {}


func _spawn(world: Variant, at: Vector2) -> int:
	var rng: Variant = world.rng.stream("shambler")
	return int(SimRoster.spawn_zombie(world, at.x, at.y, SimRoster.TYPE_SHAMBLER, rng))


func _place(world: Variant, ent: int, at: Vector2) -> void:
	world.components.set_component(ent, "position", {"x": at.x, "y": at.y})
	var vel: Variant = world.components.get_component(ent, "velocity")
	if vel is Dictionary:
		(vel as Dictionary)["dx"] = 0.0
		(vel as Dictionary)["dy"] = 0.0


func _settle(world: Variant, ticks: int) -> void:
	for _i in ticks:
		world.step()


func _centre(tile: Vector2i) -> Vector2:
	return Vector2(float(tile.x) + 0.5, float(tile.y) + 0.5)


# --- READS -----------------------------------------------------------------------------------------

func _entity_pos(world: Variant, ent: int) -> Vector2:
	var pos: Variant = world.components.get_component(ent, "position")
	if not (pos is Dictionary):
		return Vector2.ZERO
	return Vector2(float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]))


func _velocity(world: Variant, ent: int) -> Vector2:
	var vel: Variant = world.components.get_component(ent, "velocity")
	if not (vel is Dictionary):
		return Vector2.ZERO
	return Vector2(float((vel as Dictionary).get("dx", 0.0)), float((vel as Dictionary).get("dy", 0.0)))


func _state(world: Variant, zed: int) -> int:
	var sd: Variant = world.components.get_component(zed, "shambler")
	if not (sd is Dictionary):
		return -1
	return int((sd as Dictionary).get("state", -1))


func _state_name(state: int) -> String:
	for key in SimShambler.ShamblerState.keys():
		if int(SimShambler.ShamblerState[key]) == state:
			return String(key)
	return "none"


func _hunting(world: Variant, zed: int) -> bool:
	var s: int = _state(world, zed)
	return s == int(SimShambler.ShamblerState["Seek"]) or s == int(SimShambler.ShamblerState["Pursue"])


func _investigating_or_hunting(world: Variant, zed: int) -> bool:
	var s: int = _state(world, zed)
	return s == int(SimShambler.ShamblerState["Investigate"]) or _hunting(world, zed)


# The sim's own sight answer: detail above zero means the observer sees some of the target.
func _detail(world: Variant, observer: int, target: int) -> int:
	var at: Vector2 = _entity_pos(world, target)
	return int(world.vision.call("detail", observer, at.x, at.y, -1, target))


# The target the shambler module would pick now, through its own _seen_target.
func _module_target(world: Variant, zed: int) -> Variant:
	var sd: Dictionary = world.components.get_component(zed, "shambler") as Dictionary
	return SimShambler._seen_target(world, zed, SimShambler._gather_survivors(world), sd)


func _dist(world: Variant, a: int, b: int) -> float:
	return _entity_pos(world, a).distance_to(_entity_pos(world, b))


func _wound_count(world: Variant, ent: int) -> int:
	var inj: Variant = world.components.get_component(ent, "injuries")
	if not (inj is Dictionary):
		return 0
	return ((inj as Dictionary).get("wounds", []) as Array).size()


func _last_wound(world: Variant, ent: int) -> Dictionary:
	var inj: Variant = world.components.get_component(ent, "injuries")
	if not (inj is Dictionary):
		return {}
	var wounds: Array = (inj as Dictionary).get("wounds", []) as Array
	if wounds.is_empty():
		return {}
	return wounds[wounds.size() - 1] as Dictionary


func _held(world: Variant, zed: int, player: int) -> bool:
	return world.components.has_component(zed, "grabState") and world.components.has_component(player, "grabbed")


# --- SIGHT -----------------------------------------------------------------------------------------

func _sight_lane() -> bool:
	var lane: String = "SIGHT"
	var boot: Dictionary = _boot()
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	var setup: Dictionary = _encounter(world, map, SIGHT_METRES)
	if setup.is_empty():
		return _fail(lane, "no %d m of open ground in one row of the %d m district" % [SIGHT_METRES, DISTRICT_TILES])
	var player: int = int(setup["player"])
	var zed: int = int(setup["zed"])
	var sight: int = _detail(world, zed, player)
	if sight <= 0:
		return _fail(lane, "no line of sight at %d m on open ground (vision.detail %d); the precondition does not hold" % [SIGHT_METRES, sight])
	var start_gap: float = _dist(world, zed, player)
	var acquired: int = -1
	for t in range(1, ACQUIRE_TICKS + 1):
		world.step()
		if _hunting(world, zed):
			acquired = t
			break
	if acquired < 0:
		var sd: Dictionary = world.components.get_component(zed, "shambler") as Dictionary
		var reach: float = SimShambler.sight_reach(world, zed, sd)
		return _fail(lane, "did not acquire the player within %d ticks (%.1f s): state %s, %.1f m away (started %.1f m). The shambler's sight reach is %.1f m (sight_reach: observer range %.0f m x sqrt(lightSense) x fog), and _seen_target refuses anything beyond it; a %d m acquisition is not in the sim" % [ACQUIRE_TICKS, float(ACQUIRE_TICKS) / 20.0, _state_name(_state(world, zed)), _dist(world, zed, player), start_gap, reach, float((world.components.get_component(zed, "observer") as Dictionary).get("range_metres", 0.0)), SIGHT_METRES])
	var target: Variant = _module_target(world, zed)
	if target == null or int(target) != player:
		return _fail(lane, "the shambler is hunting, but its module target is %s, not the player (%d)" % [str(target), player])
	var at_acquire: float = _dist(world, zed, player)
	_settle(world, CLOSE_TICKS)
	var after: float = _dist(world, zed, player)
	if at_acquire - after < CLOSE_METRES:
		return _fail(lane, "acquired at tick %d but did not close: %.1f m at acquisition, %.1f m after %d ticks" % [acquired, at_acquire, after, CLOSE_TICKS])
	return _ok(lane, "acquired the player at tick %d at %.1f m (%s), %.1f m after %d more ticks; sight %d" % [acquired, at_acquire, _state_name(_state(world, zed)), after, CLOSE_TICKS, sight])


# --- NOISE -----------------------------------------------------------------------------------------

func _noise_lane() -> bool:
	var lane: String = "NOISE"
	var boot: Dictionary = _boot()
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	var line: Dictionary = _open_line(map, NOISE_METRES)
	if line.is_empty():
		return _fail(lane, "no %d m of open ground in one row of the %d m district" % [NOISE_METRES, DISTRICT_TILES])
	var from: Vector2i = line["from"]
	var d: Vector2i = line["dir"]
	var player: int = int(world.player)
	if not world.components.has_component(player, "attention_emitter"):
		return _fail(lane, "the player has no attention_emitter, so walking makes no noise for the shambler to hear")
	_place(world, player, _centre(from))
	SimHealth.make_stamina(world, player, 100)
	var zed: int = _spawn(world, _centre(from + d * NOISE_METRES))
	# One wall tile across the row, halfway. This is the only thing between the two bodies.
	var wall: Vector2i = from + d * WALL_AT_METRES
	map.tiles[wall.y * int(map.w) + wall.x] = SimTileMap.Tile.Wall
	_settle(world, 6)
	var sight: int = _detail(world, zed, player)
	if sight > 0:
		return _fail(lane, "the wall did not stop the sight: vision.detail %d at %d m; the precondition does not hold" % [sight, NOISE_METRES])
	var shot_at: Vector2 = _entity_pos(world, player)
	world.events.publish({"type": "noise.emitted", "x": shot_at.x, "y": shot_at.y, "magnitude": SHOT_MAGNITUDE, "source": player})
	var react: int = -1
	for t in range(1, REACT_TICKS + 1):
		world.step()
		if _investigating_or_hunting(world, zed):
			react = t
			break
	if react < 0:
		var zp: Vector2 = _entity_pos(world, zed)
		var heard_now: float = float(world.field.noise_at(zp.x, zp.y))
		var needs: float = float(world.field.calibration["floor"]) / SimShambler.NOISE_SENSITIVITY
		return _fail(lane, "did not turn toward the shot within %d ticks (%.0f s): state %s, %.1f m from it. Field noise at the shambler %.4f; it hears at or above %.4f (calibration floor / noiseSense), so a %.1f magnitude shot through a wall at %d m is not heard" % [REACT_TICKS, float(REACT_TICKS) / 20.0, _state_name(_state(world, zed)), zp.distance_to(shot_at), heard_now, needs, SHOT_MAGNITUDE, NOISE_METRES])
	var heard: float = float(world.field.noise_at(_entity_pos(world, zed).x, _entity_pos(world, zed).y))
	var gap_at_react: float = _entity_pos(world, zed).distance_to(shot_at)
	var toward: int = 0
	var away: int = 0
	for _i in NOISE_CLOSE_TICKS:
		world.step()
		var v: Vector2 = _velocity(world, zed)
		if v.length() < MOVED_METRES:
			continue
		var to_shot: Vector2 = shot_at - _entity_pos(world, zed)
		if v.dot(to_shot) > 0.0:
			toward += 1
		else:
			away += 1
	var gap_end: float = _entity_pos(world, zed).distance_to(shot_at)
	if toward <= away:
		return _fail(lane, "reacted at tick %d but moved away from the shot (%d ticks toward, %d away)" % [react, toward, away])
	if gap_at_react - gap_end < CLOSE_METRES:
		return _fail(lane, "reacted at tick %d and turned, but did not close: %.1f m from the shot, %.1f m after %d ticks" % [react, gap_at_react, gap_end, NOISE_CLOSE_TICKS])
	return _ok(lane, "reacted to the shot at tick %d; field noise %.2f at the shambler (shot magnitude %.1f), %d ticks toward and %d away, %.1f m to %.1f m from the shot, behind a wall at %d m" % [react, heard, SHOT_MAGNITUDE, toward, away, gap_at_react, gap_end, WALL_AT_METRES])


# --- CONTACT and DEATH -----------------------------------------------------------------------

func _contact_and_death_lanes() -> bool:
	var boot: Dictionary = _boot()
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	var setup: Dictionary = _encounter(world, map, CONTACT_METRES)
	if setup.is_empty():
		_fail("CONTACT", "no %d m of open ground in sight in one row of the %d m district" % [CONTACT_METRES, DISTRICT_TILES])
		_fail("DEATH", "no contact to die from: CONTACT could not be set up")
		return false
	var player: int = int(setup["player"])
	var zed: int = int(setup["zed"])
	var contact_ok: bool = _contact_lane(world, player, zed)
	if not _held(world, zed, player):
		_fail("DEATH", "no contact to die from: the CONTACT lane did not reach a grab")
		return false
	return _death_lane(world, player, zed) and contact_ok


func _contact_lane(world: Variant, player: int, zed: int) -> bool:
	var lane: String = "CONTACT"
	var grab_tick: int = -1
	for t in range(1, GRAB_TICKS + 1):
		world.step()
		if _held(world, zed, player):
			grab_tick = t
			break
	if grab_tick < 0:
		return _fail(lane, "no grab within %d ticks (%.0f s); shambler %s, %.1f m from the player" % [GRAB_TICKS, float(GRAB_TICKS) / 20.0, _state_name(_state(world, zed)), _dist(world, zed, player)])
	var clear: bool = SimShambler._clear_contact(world, _pos_dict(world, zed), _pos_dict(world, player), zed, player)
	if not clear:
		return _fail(lane, "the grab formed at tick %d, but SimShambler._clear_contact says the reach is not clear" % grab_tick)
	var wounds_before: int = _wound_count(world, player)
	var bite_tick: int = -1
	for t in range(1, BITE_TICKS + 1):
		world.step()
		if _wound_count(world, player) > wounds_before:
			bite_tick = t
			break
	if bite_tick < 0:
		return _fail(lane, "held from tick %d for %d ticks and no wound landed on the player (%d wounds before)" % [grab_tick, BITE_TICKS, wounds_before])
	var wound: Dictionary = _last_wound(world, player)
	return _ok(lane, "grab formed at tick %d (%.1f m, _clear_contact true); first wound at tick %d: %s %s, %s (%d wound(s) total)" % [grab_tick, _dist(world, zed, player), bite_tick, str(wound.get("presentation", "?")), str(wound.get("bodyPart", "?")), str(wound.get("kind", "?")), _wound_count(world, player)])


func _death_lane(world: Variant, player: int, zed: int) -> bool:
	var lane: String = "DEATH"
	var contact_tick: int = int(world.tick)
	var ended: int = -1
	# Every hold on the player that ends, with its cause, so a player who lives is explained.
	var breaks: Array = []
	_sub_serial += 1
	world.events.subscribe({"type": "grab.broken", "id": "fp_encounter.death-break.%d" % _sub_serial, "handler": func(ev: Dictionary) -> void:
		if int(ev.get("victim", -1)) == player:
			breaks.append({"cause": str(ev.get("cause", "?")), "by": int(ev.get("by", -1)), "tick": int(world.tick)})
	})
	for t in range(1, DEATH_TICKS + 1):
		world.step()
		if int(world.player) != player or bool(world.runOver):
			ended = t
			break
	if ended < 0:
		var inj: Variant = world.components.get_component(player, "injuries")
		var blood: float = float((inj as Dictionary).get("bloodLoss", 0.0)) if inj is Dictionary else 0.0
		var last: String = "no hold ended"
		if not breaks.is_empty():
			var b: Dictionary = breaks[breaks.size() - 1] as Dictionary
			last = "%d hold(s) ended, last at tick %d (cause %s, by %d)" % [breaks.size(), int(b["tick"]), b["cause"], int(b["by"])]
		return _fail(lane, "the player was still alive after %d ticks (%.0f s) in contact; %d wound(s), bloodLoss %.1f, still held: %s; %s" % [DEATH_TICKS, float(DEATH_TICKS) / 20.0, _wound_count(world, player), blood, str(world.components.has_component(player, "grabbed")), last + "; shambler %s, %.1f m from the player" % [_state_name(_state(world, zed)), _dist(world, zed, player)]])
	var seconds: float = float(ended) / 20.0
	if int(world.player) != player:
		var heir: String = _identity_id(world, int(world.player))
		if not (heir == "survivor.unique.mara" or heir == "survivor.unique.ellis"):
			return _fail(lane, "world.player moved to %d (%s) at %.1f s, which is neither Mara nor Ellis" % [int(world.player), heir, seconds])
		if not world.components.has_component(player, "corpse"):
			return _fail(lane, "world.player moved to %s, but the dead player has no corpse component for the first-person scene to wait on" % heir)
		return _ok(lane, "the player died %d ticks (%.1f s) after first contact; world.player moved to heir %s (succession); the body is a corpse" % [ended, seconds, heir])
	if not bool(world.runOver):
		return _fail(lane, "the player died with world.player unmoved and world.runOver false: no end state for the first-person scene")
	return _ok(lane, "the player died %d ticks (%.1f s) after first contact; no heir left: world.runOver is true (the run is over)" % [ended, seconds])


func _identity_id(world: Variant, ent: int) -> String:
	var ident: Variant = world.components.get_component(ent, "identity")
	if ident is Dictionary:
		return String((ident as Dictionary).get("id", ""))
	return ""


func _pos_dict(world: Variant, ent: int) -> Dictionary:
	var p: Vector2 = _entity_pos(world, ent)
	return {"x": p.x, "y": p.y}


# --- BREAK -----------------------------------------------------------------------------------------

func _break_lane() -> bool:
	var lane: String = "BREAK"
	var boot: Dictionary = _boot()
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	var setup: Dictionary = _encounter(world, map, CONTACT_METRES)
	if setup.is_empty():
		return _fail(lane, "no %d m of open ground in sight in one row of the %d m district" % [CONTACT_METRES, DISTRICT_TILES])
	var player: int = int(setup["player"])
	var zed: int = int(setup["zed"])
	var grab_tick: int = -1
	for t in range(1, GRAB_TICKS + 1):
		world.step()
		if _held(world, zed, player):
			grab_tick = t
			break
	if grab_tick < 0:
		return _fail(lane, "no contact to break: no grab within %d ticks (%.0f s); the CONTACT lane failed for the same reason" % [GRAB_TICKS, float(GRAB_TICKS) / 20.0])
	# One melee attempt while held. The sim refuses it (melee.gd try_begin_swing, grabbed); that is a
	# finding about the mechanic, printed as one, and the lane carries on to the struggle.
	var melee_started: bool = SimMelee.try_begin_swing(world, player)
	if melee_started:
		print("FP_ENCOUNTER_FINDING BREAK melee started while grabbed; the refusal the sim documents did not hold")
	else:
		print("FP_ENCOUNTER_FINDING BREAK melee refused while grabbed (melee.gd try_begin_swing: grabbed); the only answer to a grab is the struggle (F, shambler.gd struggle intake)")
	# Escape odds, read from the sim's own roll: power over power plus the total grip of every holder.
	var total_grip: float = 0.0
	for src in (world.components.get_component(player, "grabbed") as Dictionary)["sources"] as Array:
		var holder: Variant = world.components.get_component(int(src), "shambler")
		if holder is Dictionary:
			total_grip += float((holder as Dictionary)["grabStrength"])
	var odds: float = SimAptitudesRes.escape_chance(world, player, total_grip)
	var stamina: float = float((world.components.get_component(player, "stamina") as Dictionary).get("current", 0.0))
	print("FP_ENCOUNTER_INFO BREAK escape odds %.3f per roll against %d holder(s) (grip %.2f), stamina %.0f, %d ticks to each roll" % [odds, (world.components.get_component(player, "grabbed") as Dictionary)["sources"].size(), total_grip, stamina, STRUGGLE_TICKS])
	var broke: Dictionary = {}
	var hit: Dictionary = {}
	# Only the two outcomes this lane is about: this grab ending on this player, or this zombie
	# being struck by the player.
	_sub_serial += 1
	world.events.subscribe({"type": "grab.broken", "id": "fp_encounter.break.%d" % _sub_serial, "handler": func(ev: Dictionary) -> void:
		if int(ev.get("victim", -1)) == player:
			broke["ev"] = ev
			broke["tick"] = int(world.tick)
	})
	_sub_serial += 1
	world.events.subscribe({"type": "attack.connected", "id": "fp_encounter.hit.%d" % _sub_serial, "handler": func(ev: Dictionary) -> void:
		if int(ev.get("target", -1)) == zed and int(ev.get("attacker", -1)) == player:
			hit["ev"] = ev
	})
	var presses: int = 0
	var grab_abs: int = int(world.tick)
	for t in range(1, BREAK_TICKS + 1):
		if t % SWING_EVERY_TICKS == 0:
			world.commands.push({"type": "swing"})
			presses += 1
		world.step()
		if broke.has("ev") or hit.has("ev"):
			break
	if broke.has("ev"):
		var ev: Dictionary = broke["ev"] as Dictionary
		return _ok(lane, "grab.broken at tick %d, %d ticks after the grab (tick %d), after %d F presses (cause %s, by %d, the victim)" % [int(broke["tick"]), int(broke["tick"]) - grab_abs, grab_abs, presses, str(ev.get("cause", "?")), int(ev.get("by", -1))])
	if hit.has("ev"):
		var hev: Dictionary = hit["ev"] as Dictionary
		return _ok(lane, "the zombie took a hit (%s, %s damage) from the player while the grab held" % [str(hev.get("bodyPart", "?")), str(hev.get("damage", "?"))])
	return _fail(lane, "neither the grab broke nor the zombie took a hit in %d F presses over %d ticks; still held: %s; escape odds %.3f per roll" % [presses, BREAK_TICKS, str(_held(world, zed, player)), odds])
