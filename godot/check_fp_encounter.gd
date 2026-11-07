extends SceneTree
# The first-person encounter gate: one zombie against the first-person player, from first sight or
# sound to the grab, the wound, the player's death, and what the player can do back. It boots the
# seeded district the first-person scene boots (SimBoot.playable with the scene's own seed and size)
# and reads and steps the sim only. No module is changed.
#
# Each lane prints one line:
#   FP_ENCOUNTER_OK <LANE> ...       the sim does what the lane asks; the numbers are printed
#   FP_ENCOUNTER_FAIL <LANE> ...     the sim does not do what the lane asks, or the harness cannot set the
#                                    lane up. The numbers name what is missing. Any FAIL makes the gate red.
#   FP_ENCOUNTER_FINDING <LANE> ...  a fact about the sim that is neither a pass nor a fail (a refused action)
#   FP_ENCOUNTER_INFO <LANE> ...     a reading, not a verdict
#
#   SIGHT-NEAR      a shambler 3 m away on open ground, inside its sight reach, acquires the player (the
#                   module's own _seen_target must be the player) and closes.
#   SIGHT           the spec's 12 m. FAIL while the sight reach is shorter than 12 m (the reach is printed).
#   NOISE           a rifle shot (item.rifle.hunting's ranged.noise from content, published as ranged.gd
#                   publishes a shot) at the player; a shambler 30 m away behind one wall tile, no sight.
#                   FAIL if not heard: the field value at the shambler and the hearing threshold are printed.
#                   Also FAIL unless the player's footsteps publish noise.emitted. INFO: the distance at which
#                   the walking player (magnitude 1.0) first turns a wall-free shambler.
#   CONTACT         the shambler reaches the player from 3 m; a grab forms (SimShambler._clear_contact true
#                   at that tick) and a bite lands as a wound.
#   DEATH-NOESCAPE  the same contact with stamina held at 0 every tick, so the struggle is refused and no
#                   escape is open: the player must die, and world.player must move to Mara or Ellis, or
#                   world.runOver must be set. A second run removes the other survivors (no heir): there
#                   world.runOver must be set.
#   DEATH           the attentive player (normal stamina, struggle open): the lone shambler must kill them
#                   inside DEATH_TICKS. FAIL while it does not; the break cause and the ticks are printed.
#   REPRESS         after a struggle break with no command, the player comes to rest and the shambler
#                   presses again (a re-grab, then a bite).
#   DRIFT           the break-away shove's record expires; the controlled body comes to rest, and its travel is
#                   no more than the shove. A held move command must survive the expiry (the guard).
#   DRIFT-WALL      the shove runs into a wall: the wall zeroes the axis it hits, the other axis keeps its value,
#                   and after expiry both axes are zero and the body does not move.
#   BREAK           a contact in which the player presses F (swing) while held. One melee attempt is made
#                   first: its refusal is a FINDING line. The struggle is the answer; the escape odds are the
#                   sim's own roll (SimAptitudes.escape_chance). OK when the grab breaks or the zombie is hit.
#
# Ticks are printed as "+N", counted from the boot. The boot sets world.tick to
# Clock.tick_at_time_of_day(Clock.DAY_BEGINS), which is 9000, so an absolute tick is 9000 + N.
#
# Placement only: the district's own zombies are removed, the other survivors are parked 40 m away (or
# removed, in DEATH-NOESCAPE's no-heir run). Nothing is loosened.

const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimAptitudes = preload("res://sim/modules/aptitudes.gd")

const SEED: int = SimBoot.DISTRICT_SEED
# The district size the first-person scene boots its gates on: small on purpose, as in
# check_fp_expedition, so every lane walks the sim and not the map.
const DISTRICT_TILES: int = 64
const NEAR_METRES: int = 3
const PROBE_METRES: int = 12
const NOISE_METRES: int = 30
const WALL_AT_METRES: int = 15
const RIFLE_ITEM: String = "item.rifle.hunting"
const RANGED_CONTENT: String = "res://content/items/ranged.json"
const PARK_METRES: float = 40.0
const ACQUIRE_TICKS: int = 60
const CLOSE_TICKS: int = 40
const CLOSE_METRES: float = 1.0
const REACT_TICKS: int = 200
const NOISE_CLOSE_TICKS: int = 80
const FOOTSTEP_TICKS: int = 10
const WALK_SPEED: float = 1.4
const WALK_START_METRES: int = 20
const WALK_LIMIT_TICKS: int = 600
const WALK_STOP_METRES: float = 2.0
const GRAB_TICKS: int = 400
const BITE_TICKS: int = 200
const DEATH_TICKS: int = 3000
const BREAK_TICKS: int = 300
const SWING_EVERY_TICKS: int = 12
const STRUGGLE_TICKS: int = 16
const STAMINA_MAX: int = 100
const ENCOUNTER_CANDIDATES: int = 200
const MOVED_METRES: float = 0.05
const REST_TICKS: int = 60
const REPRESS_TICKS: int = 200
const DRIFT_SETTLE_TICKS: int = 20
const DRIFT_SLACK_METRES: float = 0.1
const WALL_AHEAD_METRES: float = 2.0
const DRIFT_WALL_SHOVE_DY: float = 0.1035
const TIME_BUDGET_SECONDS: float = 60.0

var _fails: int = 0
var _started_ms: int = 0
# Subscription ids are unique per gate run, because the event bus refuses a duplicate id.
var _sub_serial: int = 0
# world.tick at the most recent boot; printed ticks are counted from here.
var _base_tick: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_started_ms = Time.get_ticks_msec()
	_sight_near()
	_sight_twelve()
	_shot_through_wall()
	_footsteps()
	_walking_distance()
	_contact_lane()
	_death_noescape()
	_death_noescape_no_heir()
	_death_attentive()
	_repress_lane()
	_drift_lane()
	_drift_wall()
	_break_lane()
	var seconds: float = float(Time.get_ticks_msec() - _started_ms) / 1000.0
	if seconds > TIME_BUDGET_SECONDS:
		_fail("TIME", "the gate took %.1f s, over its %.0f s budget" % [seconds, TIME_BUDGET_SECONDS])
	if _fails == 0:
		print("FP_ENCOUNTER_OK gate: 0 FAIL, in %.1f s" % seconds)
		quit(0)
		return
	print("FP_ENCOUNTER_RESULT gate red: %d FAIL, in %.1f s" % [_fails, seconds])
	quit(1)


func _ok(lane: String, message: String) -> void:
	print("FP_ENCOUNTER_OK %s %s" % [lane, message])


func _finding(lane: String, message: String) -> void:
	print("FP_ENCOUNTER_FINDING %s %s" % [lane, message])


func _info(lane: String, message: String) -> void:
	print("FP_ENCOUNTER_INFO %s %s" % [lane, message])


func _fail(lane: String, message: String) -> void:
	_fails += 1
	push_error("FP_ENCOUNTER_FAIL %s %s" % [lane, message])


# --- SETUP -----------------------------------------------------------------------------------------

# A fresh seeded district, with the district's own zombies removed and the other survivors parked, or
# removed altogether when `no_heirs`.
func _boot(no_heirs: bool = false) -> Dictionary:
	var boot: Dictionary = SimBoot.playable(SEED, DISTRICT_TILES)
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	_base_tick = int(world.tick)
	_clear_the_district(world, map, no_heirs)
	return {"world": world, "map": map}


func _clear_the_district(world: Variant, map: Variant, no_heirs: bool) -> void:
	var doomed: Array = []
	for ent in world.components.query(["zombieType"]):
		doomed.append(int(ent))
	for ent in world.components.query(["shambler"]):
		if not doomed.has(int(ent)):
			doomed.append(int(ent))
	var player: int = int(world.player)
	if no_heirs:
		for ent in world.components.query(["identity"]):
			if int(ent) != player and not doomed.has(int(ent)):
				doomed.append(int(ent))
	for ent in doomed:
		world.despawn(int(ent))
	if no_heirs:
		return
	var far: Vector2i = _far_open_tile(map, _entity_pos(world, player), PARK_METRES)
	for ent in world.components.query(["identity", "position"]):
		if int(ent) == player:
			continue
		_place(world, int(ent), _centre(far))


# Open lines of `metres + 1` tiles, in a fixed scan order, the first `limit` of them.
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


# The first open line on which the sim's own sight holds (the shambler's detail on the player is above
# zero once the vision has settled). A line the zombie cannot see down is passed over. Returns {} when
# the district has no such line.
func _encounter(world: Variant, map: Variant, metres: int) -> Dictionary:
	var player: int = int(world.player)
	SimMelee.make_melee_armed(world, player)
	SimHealth.make_stamina(world, player, STAMINA_MAX)
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


# The rifle's noise, read from the content file the sim loads (ranged.noise on item.rifle.hunting), so
# the number is not typed into the gate. -1 when the content has no such value.
func _rifle_noise() -> float:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(RANGED_CONTENT))
	if data is Array:
		for item in data as Array:
			if item is Dictionary and String((item as Dictionary).get("id", "")) == RIFLE_ITEM:
				var ranged: Dictionary = (item as Dictionary).get("ranged", {}) as Dictionary
				return float(ranged.get("noise", -1.0))
	return -1.0


# --- READS -----------------------------------------------------------------------------------------

# The tick, counted from the boot.
func _rel(world: Variant) -> int:
	return int(world.tick) - _base_tick


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


func _sight_reach(world: Variant, zed: int) -> float:
	var sd: Dictionary = world.components.get_component(zed, "shambler") as Dictionary
	return SimShambler.sight_reach(world, zed, sd)


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


func _identity_id(world: Variant, ent: int) -> String:
	var ident: Variant = world.components.get_component(ent, "identity")
	if ident is Dictionary:
		return String((ident as Dictionary).get("id", ""))
	return ""


func _force_stamina(world: Variant, ent: int, value: float) -> void:
	var st: Variant = world.components.get_component(ent, "stamina")
	if st is Dictionary:
		(st as Dictionary)["current"] = value


func _blood(world: Variant, ent: int) -> float:
	var inj: Variant = world.components.get_component(ent, "injuries")
	if inj is Dictionary:
		return float((inj as Dictionary).get("bloodLoss", 0.0))
	return 0.0


func _bled_out(world: Variant, ent: int) -> bool:
	var inj: Variant = world.components.get_component(ent, "injuries")
	if inj is Dictionary:
		return bool((inj as Dictionary).get("bledOut", false))
	return false


# Walks the player one tick toward `dir` by setting its velocity, which the movement and the emitter read.
func _walk(world: Variant, player: int, dir: Vector2) -> void:
	var vel: Variant = world.components.get_component(player, "velocity")
	if vel is Dictionary:
		(vel as Dictionary)["dx"] = dir.x * WALK_SPEED
		(vel as Dictionary)["dy"] = dir.y * WALK_SPEED


func _step_until_held(world: Variant, zed: int, player: int) -> bool:
	for _t in range(1, GRAB_TICKS + 1):
		world.step()
		if _held(world, zed, player):
			return true
	return false


func _listen_deaths(world: Variant, player: int, into: Array) -> void:
	_sub_serial += 1
	world.events.subscribe({"type": "entity.killed", "id": "fp_encounter.death-log.%d" % _sub_serial, "handler": func(ev: Dictionary) -> void:
		if int(ev.get("entity", -1)) == player:
			into.append(ev)
	})


func _listen_breaks(world: Variant, player: int, into: Array) -> void:
	_sub_serial += 1
	world.events.subscribe({"type": "grab.broken", "id": "fp_encounter.break-log.%d" % _sub_serial, "handler": func(ev: Dictionary) -> void:
		if int(ev.get("victim", -1)) == player:
			into.append({"cause": str(ev.get("cause", "?")), "by": int(ev.get("by", -1)), "tick": _rel(world)})
	})


func _pos_dict(world: Variant, ent: int) -> Dictionary:
	var p: Vector2 = _entity_pos(world, ent)
	return {"x": p.x, "y": p.y}


# --- SIGHT -----------------------------------------------------------------------------------------

# SIGHT-NEAR: 3 m, inside the reach. Must acquire and close.
func _sight_near() -> void:
	var lane: String = "SIGHT-NEAR"
	var boot: Dictionary = _boot()
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	var setup: Dictionary = _encounter(world, map, NEAR_METRES)
	if setup.is_empty():
		_fail(lane, "no %d m open line with sight in the %d m district; the setup cannot hold" % [NEAR_METRES, DISTRICT_TILES])
		return
	var player: int = int(setup["player"])
	var zed: int = int(setup["zed"])
	var start_gap: float = _dist(world, zed, player)
	var acquired: int = -1
	for t in range(1, ACQUIRE_TICKS + 1):
		world.step()
		if _hunting(world, zed):
			acquired = t
			break
	if acquired < 0:
		_fail(lane, "%d m, inside the sight reach of %.1f m: not acquired in %d ticks (%.1f s); state %s, %.1f m away (started %.1f m)" % [NEAR_METRES, _sight_reach(world, zed), ACQUIRE_TICKS, float(ACQUIRE_TICKS) / 20.0, _state_name(_state(world, zed)), _dist(world, zed, player), start_gap])
		return
	var target: Variant = _module_target(world, zed)
	if target == null or int(target) != player:
		_fail(lane, "the shambler is hunting, but its module target is %s, not the player (%d)" % [str(target), player])
		return
	var at_acquire: float = _dist(world, zed, player)
	_settle(world, CLOSE_TICKS)
	var after: float = _dist(world, zed, player)
	if at_acquire - after < CLOSE_METRES:
		_fail(lane, "acquired %d ticks after setup but did not close: %.1f m at acquisition, %.1f m after %d ticks" % [acquired, at_acquire, after, CLOSE_TICKS])
		return
	_ok(lane, "acquired the player %d ticks after setup, at %.1f m (%s); %.1f m after %d more ticks; sight reach %.1f m" % [acquired, at_acquire, _state_name(_state(world, zed)), after, CLOSE_TICKS, _sight_reach(world, zed)])


# SIGHT: the spec's 12 m. Red while the reach is shorter.
func _sight_twelve() -> void:
	var lane: String = "SIGHT"
	var boot: Dictionary = _boot()
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	var setup: Dictionary = _encounter(world, map, PROBE_METRES)
	if setup.is_empty():
		_fail(lane, "no %d m open line with sight for the probe" % PROBE_METRES)
		return
	var player: int = int(setup["player"])
	var zed: int = int(setup["zed"])
	var acquired: int = -1
	for t in range(1, ACQUIRE_TICKS + 1):
		world.step()
		if _hunting(world, zed):
			acquired = t
			break
	var observer: Dictionary = world.components.get_component(zed, "observer") as Dictionary
	if acquired < 0:
		_fail(lane, "%d m: not acquired in %d ticks (%.1f s); the sight reach is %.1f m (observer range %.0f m x sqrt(lightSense) x fog), and _seen_target refuses anything beyond it; %.1f m away at the end" % [PROBE_METRES, ACQUIRE_TICKS, float(ACQUIRE_TICKS) / 20.0, _sight_reach(world, zed), float(observer.get("range_metres", 0.0)), _dist(world, zed, player)])
	else:
		_ok(lane, "%d m: acquired at tick +%d, %.1f m away; the reach is %.1f m" % [PROBE_METRES, acquired, _dist(world, zed, player), _sight_reach(world, zed)])


# --- NOISE -----------------------------------------------------------------------------------------

# NOISE: the rifle through one wall tile at 30 m, no sight. FAIL when it is not heard.
func _shot_through_wall() -> void:
	var lane: String = "NOISE"
	var boot: Dictionary = _boot()
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	var player: int = int(world.player)
	if not world.components.has_component(player, "attention_emitter"):
		_fail(lane, "the player has no attention_emitter, so walking makes no noise for the shambler to hear")
		return
	var shot: float = _rifle_noise()
	if shot <= 0.0:
		_fail(lane, "%s has no ranged noise in %s" % [RIFLE_ITEM, RANGED_CONTENT])
		return
	var lines: Array = _open_lines(map, NOISE_METRES, 1)
	if lines.is_empty():
		_fail(lane, "no %d m open line in the %d m district" % [NOISE_METRES, DISTRICT_TILES])
		return
	var from: Vector2i = (lines[0] as Dictionary)["from"]
	var d: Vector2i = (lines[0] as Dictionary)["dir"]
	_place(world, player, _centre(from))
	SimHealth.make_stamina(world, player, STAMINA_MAX)
	var zed: int = _spawn(world, _centre(from + d * NOISE_METRES))
	var wall: Vector2i = from + d * WALL_AT_METRES
	map.tiles[wall.y * int(map.w) + wall.x] = SimTileMap.Tile.Wall
	_settle(world, 6)
	var sight: int = _detail(world, zed, player)
	if sight > 0:
		_fail(lane, "the wall did not stop the sight: vision.detail %d at %d m; the setup cannot hold" % [sight, NOISE_METRES])
		return
	var shot_at: Vector2 = _entity_pos(world, player)
	world.events.publish({"type": "noise.emitted", "x": shot_at.x, "y": shot_at.y, "magnitude": shot, "source": player})
	var react: int = -1
	for t in range(1, REACT_TICKS + 1):
		world.step()
		if _investigating_or_hunting(world, zed):
			react = t
			break
	var zp: Vector2 = _entity_pos(world, zed)
	var threshold: float = float(world.field.calibration["floor"]) / SimShambler.NOISE_SENSITIVITY
	var field_here: float = float(world.field.noise_at(zp.x, zp.y))
	if react < 0:
		_fail(lane, "rifle shot (magnitude %.0f, %s) through one wall tile at %d m: no turn in %d ticks (%.0f s); state %s, %.1f m from the shot; field noise at the shambler %.4f, hearing threshold %.4f" % [shot, RIFLE_ITEM, NOISE_METRES, REACT_TICKS, float(REACT_TICKS) / 20.0, _state_name(_state(world, zed)), zp.distance_to(shot_at), field_here, threshold])
		return
	var gap_at_react: float = zp.distance_to(shot_at)
	var toward: int = 0
	var away: int = 0
	for _i in NOISE_CLOSE_TICKS:
		world.step()
		var v: Vector2 = _velocity(world, zed)
		if v.length() < MOVED_METRES:
			continue
		if v.dot(shot_at - _entity_pos(world, zed)) > 0.0:
			toward += 1
		else:
			away += 1
	var gap_end: float = _entity_pos(world, zed).distance_to(shot_at)
	if toward <= away or gap_at_react - gap_end < CLOSE_METRES:
		_fail(lane, "rifle shot (magnitude %.0f) through a wall at %d m: turned %d ticks after the shot but %d ticks toward and %d away, %.1f m to %.1f m from the shot" % [shot, NOISE_METRES, react, toward, away, gap_at_react, gap_end])
		return
	_ok(lane, "rifle shot (magnitude %.0f, %s) through a wall at %d m: turned %d ticks after the shot, field %.4f at the shambler (threshold %.4f); %d ticks toward, %d away; %.1f m to %.1f m from the shot" % [shot, RIFLE_ITEM, NOISE_METRES, react, field_here, threshold, toward, away, gap_at_react, gap_end])


# NOISE: the player's footsteps publish noise.emitted with the player as source.
func _footsteps() -> void:
	var lane: String = "NOISE"
	var boot: Dictionary = _boot()
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	var player: int = int(world.player)
	var lines: Array = _open_lines(map, 6, 1)
	if lines.is_empty():
		_fail(lane, "no 6 m open line for the footsteps check")
		return
	var from: Vector2i = (lines[0] as Dictionary)["from"]
	var d: Vector2i = (lines[0] as Dictionary)["dir"]
	_place(world, player, _centre(from))
	var steps: Dictionary = {"count": 0, "magnitude": 0.0}
	_sub_serial += 1
	world.events.subscribe({"type": "noise.emitted", "id": "fp_encounter.footsteps.%d" % _sub_serial, "handler": func(ev: Dictionary) -> void:
		if int(ev.get("source", -1)) == player:
			steps["count"] = int(steps["count"]) + 1
			steps["magnitude"] = float(ev.get("magnitude", 0.0))
	})
	var dir: Vector2 = Vector2(float(d.x), float(d.y))
	for _i in FOOTSTEP_TICKS:
		_walk(world, player, dir)
		world.step()
	if int(steps["count"]) == 0:
		_fail(lane, "footsteps: the walking player published no noise.emitted in %d ticks (attention.emit-movement)" % FOOTSTEP_TICKS)
	else:
		_ok(lane, "footsteps: %d noise.emitted from the player in %d ticks of walking, magnitude %.2f each" % [int(steps["count"]), FOOTSTEP_TICKS, float(steps["magnitude"])])


# INFO: the walking player (magnitude 1.0) walks toward a wall-free shambler. The distance at which the
# shambler first turns is printed. Not a verdict.
func _walking_distance() -> void:
	var lane: String = "NOISE"
	var boot: Dictionary = _boot()
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	var lines: Array = _open_lines(map, WALK_START_METRES + 1, 1)
	if lines.is_empty():
		_fail(lane, "no %d m open line for the walking check" % WALK_START_METRES)
		return
	var from: Vector2i = (lines[0] as Dictionary)["from"]
	var d: Vector2i = (lines[0] as Dictionary)["dir"]
	var player: int = int(world.player)
	_place(world, player, _centre(from))
	var zed: int = _spawn(world, _centre(from + d * WALK_START_METRES))
	_settle(world, 4)
	var dir: Vector2 = Vector2(float(d.x), float(d.y))
	var turned: int = -1
	var turn_gap: float = -1.0
	var turn_sight: bool = false
	for t in range(1, WALK_LIMIT_TICKS + 1):
		_walk(world, player, dir)
		world.step()
		if _investigating_or_hunting(world, zed):
			turned = t
			turn_gap = _dist(world, zed, player)
			turn_sight = _detail(world, zed, player) > 0
			break
		if _dist(world, zed, player) <= WALK_STOP_METRES:
			break
	if turned < 0:
		_info(lane, "walking noise (magnitude 1.0): the shambler did not turn before the player was %.1f m away (started %d m); state %s" % [WALK_STOP_METRES, WALK_START_METRES, _state_name(_state(world, zed))])
	else:
		_info(lane, "walking noise (magnitude 1.0): the shambler first turned %d ticks in, %.1f m from the walking player, %s" % [turned, turn_gap, "inside the sight reach" if turn_sight else "outside sight, so it heard"])


# --- CONTACT ---------------------------------------------------------------------------------------

func _contact_lane() -> void:
	var lane: String = "CONTACT"
	var boot: Dictionary = _boot()
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	var setup: Dictionary = _encounter(world, map, NEAR_METRES)
	if setup.is_empty():
		_fail(lane, "no %d m open line with sight in the %d m district" % [NEAR_METRES, DISTRICT_TILES])
		return
	var player: int = int(setup["player"])
	var zed: int = int(setup["zed"])
	var grab_tick: int = -1
	for t in range(1, GRAB_TICKS + 1):
		world.step()
		if _held(world, zed, player):
			grab_tick = t
			break
	if grab_tick < 0:
		_fail(lane, "no grab within %d ticks (%.0f s): state %s, %.1f m from the player" % [GRAB_TICKS, float(GRAB_TICKS) / 20.0, _state_name(_state(world, zed)), _dist(world, zed, player)])
		return
	var grab_at: int = _rel(world)
	if not SimShambler._clear_contact(world, _pos_dict(world, zed), _pos_dict(world, player), zed, player):
		_fail(lane, "the grab formed at tick +%d, but SimShambler._clear_contact says the reach is not clear" % grab_at)
		return
	var wounds_before: int = _wound_count(world, player)
	var bite_tick: int = -1
	for t in range(1, BITE_TICKS + 1):
		world.step()
		if _wound_count(world, player) > wounds_before:
			bite_tick = _rel(world)
			break
	if bite_tick < 0:
		_fail(lane, "held for %d ticks and no wound landed on the player" % BITE_TICKS)
		return
	var wound: Dictionary = _last_wound(world, player)
	_ok(lane, "grab at tick +%d (_clear_contact true); first wound at tick +%d: %s %s, %s (%d wound(s))" % [grab_at, bite_tick, str(wound.get("presentation", "?")), str(wound.get("bodyPart", "?")), str(wound.get("kind", "?")), _wound_count(world, player)])


# --- DEATH -----------------------------------------------------------------------------------------

# DEATH-NOESCAPE: the struggle is refused (stamina held at 0), so the player cannot get out. Must die and
# hand over to an heir, or set runOver.
func _death_noescape() -> void:
	var lane: String = "DEATH-NOESCAPE"
	var boot: Dictionary = _boot()
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	var setup: Dictionary = _encounter(world, map, NEAR_METRES)
	if setup.is_empty():
		_fail(lane, "no %d m open line with sight in the %d m district" % [NEAR_METRES, DISTRICT_TILES])
		return
	var player: int = int(setup["player"])
	var zed: int = int(setup["zed"])
	if not _step_until_held(world, zed, player):
		_fail(lane, "no grab within %d ticks, so there is no contact to die from" % GRAB_TICKS)
		return
	var contact: int = int(world.tick)
	var deaths: Array = []
	_listen_deaths(world, player, deaths)
	var ended: bool = false
	for _i in DEATH_TICKS:
		_force_stamina(world, player, 0.0)
		world.step()
		if not deaths.is_empty() or int(world.player) != player or bool(world.runOver):
			ended = true
			break
	# The death is published in the tick and its handoff (succession or run-over) is handled after the
	# tick's events drain, so read the end state after a few more ticks.
	if ended:
		_settle(world, 10)
	if not ended:
		_fail(lane, "the player (stamina held at 0) was alive after %d ticks (%.0f s) in contact; %d wound(s), bloodLoss %.1f, bledOut %s" % [DEATH_TICKS, float(DEATH_TICKS) / 20.0, _wound_count(world, player), _blood(world, player), str(_bled_out(world, player))])
		return
	var ticks: int = int(world.tick) - contact
	var cause: String = "bled out" if _bled_out(world, player) else ("killed (head), by entity %d" % int((deaths[0] as Dictionary).get("killer", -1)) if not deaths.is_empty() else "unknown")
	if int(world.player) != player:
		var heir: String = _identity_id(world, int(world.player))
		if heir == "survivor.unique.mara" or heir == "survivor.unique.ellis":
			_ok(lane, "the player died %d ticks (%.1f s) after first contact, cause %s; world.player moved to heir %s" % [ticks, float(ticks) / 20.0, cause, heir])
		else:
			_fail(lane, "world.player moved to %d (%s), which is neither Mara nor Ellis" % [int(world.player), heir])
		return
	if bool(world.runOver):
		_ok(lane, "the player died %d ticks (%.1f s) after first contact, cause %s; world.runOver set" % [ticks, float(ticks) / 20.0, cause])
	else:
		_fail(lane, "the player died, but world.player is unmoved and world.runOver is false: no end state for the scene")


# DEATH-NOESCAPE, no heir: the other survivors are removed. The run must end with world.runOver set.
func _death_noescape_no_heir() -> void:
	var lane: String = "DEATH-NOESCAPE"
	var boot: Dictionary = _boot(true)
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	var setup: Dictionary = _encounter(world, map, NEAR_METRES)
	if setup.is_empty():
		_fail(lane, "no-heir: no %d m open line with sight" % NEAR_METRES)
		return
	var player: int = int(setup["player"])
	var zed: int = int(setup["zed"])
	if not _step_until_held(world, zed, player):
		_fail(lane, "no-heir: no grab within %d ticks, so no contact to die from" % GRAB_TICKS)
		return
	var contact: int = int(world.tick)
	for _i in DEATH_TICKS:
		_force_stamina(world, player, 0.0)
		world.step()
		if bool(world.runOver):
			break
	if not bool(world.runOver):
		_fail(lane, "no-heir (stamina held at 0): no run-over in %d ticks; world.player %d, alive %s" % [DEATH_TICKS, int(world.player), str(world.entities.is_alive(player))])
		return
	var ticks: int = int(world.tick) - contact
	_ok(lane, "no heir left: world.runOver set %d ticks (%.1f s) after first contact" % [ticks, float(ticks) / 20.0])


# DEATH: the attentive player (normal stamina, the struggle open) must not be killed by a lone shambler
# inside DEATH_TICKS. FAIL while it survives: the struggle is what lets them live.
func _death_attentive() -> void:
	var lane: String = "DEATH"
	var boot: Dictionary = _boot()
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	var setup: Dictionary = _encounter(world, map, NEAR_METRES)
	if setup.is_empty():
		_fail(lane, "attentive: no %d m open line with sight" % NEAR_METRES)
		return
	var player: int = int(setup["player"])
	var zed: int = int(setup["zed"])
	if not _step_until_held(world, zed, player):
		_fail(lane, "attentive: no grab within %d ticks, so there was no contact" % GRAB_TICKS)
		return
	var breaks: Array = []
	var deaths: Array = []
	_listen_breaks(world, player, breaks)
	_listen_deaths(world, player, deaths)
	var zed_kills: Array = []
	_sub_serial += 1
	world.events.subscribe({"type": "entity.killed", "id": "fp_encounter.zed-kill.%d" % _sub_serial, "handler": func(ev: Dictionary) -> void:
		if int(ev.get("entity", -1)) == zed:
			zed_kills.append(ev)
	})
	var contact: int = int(world.tick)
	for _i in DEATH_TICKS:
		world.step()
		if not deaths.is_empty() or int(world.player) != player or not zed_kills.is_empty():
			break
	if not zed_kills.is_empty():
		_fail(lane, "attentive player (normal stamina) is not killed by a lone shambler: the player killed it at +%d (killer %d, player %d) after %d holds broke; the lane asks the question, and the answer is no" % [_rel(world), int((zed_kills[0] as Dictionary).get("killer", -1)), player, breaks.size()])
		return
	if not deaths.is_empty() or int(world.player) != player:
		_ok(lane, "attentive player died %d ticks (%.1f s) after first contact" % [int(world.tick) - contact, float(int(world.tick) - contact) / 20.0])
		return
	var last: String = "no hold ended"
	if not breaks.is_empty():
		var b: Dictionary = breaks[breaks.size() - 1] as Dictionary
		last = "%d hold(s) ended, last at tick +%d (cause %s, by %d)" % [breaks.size(), int(b["tick"]), str(b["cause"]), int(b["by"])]
	var zed_note: String = "shambler %s, %.1f m away" % [_state_name(_state(world, zed)), _dist(world, zed, player)] if world.entities.is_alive(zed) else "the shambler is gone (entity not alive)"
	_fail(lane, "attentive player (normal stamina): a lone shambler does not kill them; alive after %d ticks (%.0f s) in contact, %d wound(s), held: %s; %s; %s; contact at tick +%d" % [DEATH_TICKS, float(DEATH_TICKS) / 20.0, _wound_count(world, player), str(world.components.has_component(player, "grabbed")), last, zed_note, contact - _base_tick])


# REPRESS: a grab is broken by the player's struggle; the shambler must press again. The player does not
# move: after the break-away the freed body must come to rest (a stale shove velocity walking it off is a
# FAIL), and the same shambler must re-grab, and a bite must land on the player, within REPRESS_TICKS.
func _repress_lane() -> void:
	var lane: String = "REPRESS"
	var boot: Dictionary = _boot()
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	var setup: Dictionary = _encounter(world, map, NEAR_METRES)
	if setup.is_empty():
		_fail(lane, "no %d m open line with sight in the %d m district" % [NEAR_METRES, DISTRICT_TILES])
		return
	var player: int = int(setup["player"])
	var zed: int = int(setup["zed"])
	if not _step_until_held(world, zed, player):
		_fail(lane, "no grab within %d ticks, so no contact to break" % GRAB_TICKS)
		return
	var breaks: Array = []
	_listen_breaks(world, player, breaks)
	var regrabs: Array = []
	_sub_serial += 1
	world.events.subscribe({"type": "grab.started", "id": "fp_encounter.repress-grab.%d" % _sub_serial, "handler": func(ev: Dictionary) -> void:
		if int(ev.get("source", -1)) == zed and int(ev.get("victim", -1)) == player:
			regrabs.append(_rel(world))
	})
	var released: int = -1
	for _t in range(1, DEATH_TICKS + 1):
		world.step()
		if not breaks.is_empty():
			released = _rel(world)
			break
	if released < 0:
		_fail(lane, "the grab did not break within %d ticks; nothing to press again" % DEATH_TICKS)
		return
	var rest_at: Vector2 = _entity_pos(world, player)
	_settle(world, REST_TICKS)
	var drift: float = _entity_pos(world, player).distance_to(rest_at)
	var still_moving: bool = _velocity(world, player).length() >= MOVED_METRES
	if still_moving:
		_fail(lane, "the freed player is still moving %.2f m/s %d ticks after the break with no command; the break-away velocity was never cleared" % [_velocity(world, player).length(), REST_TICKS])
		return
	var pressed: int = -1
	for t in range(1, REPRESS_TICKS + 1):
		world.step()
		if not regrabs.is_empty():
			pressed = t
			break
	if pressed < 0:
		_fail(lane, "the shambler did not press again within %d ticks of the break (%.1f m away, %s, toGrab %d)" % [REPRESS_TICKS, _dist(world, zed, player), _state_name(_state(world, zed)), int((world.components.get_component(zed, "shambler") as Dictionary)["ticksToGrab"])])
		return
	var wounds_before: int = _wound_count(world, player)
	var bite_at: int = -1
	for t in range(1, BITE_TICKS + 1):
		world.step()
		if _wound_count(world, player) > wounds_before:
			bite_at = t
			break
	if bite_at < 0:
		_fail(lane, "the shambler pressed again at +%d but no bite landed within %d ticks" % [pressed, BITE_TICKS])
		return
	_ok(lane, "break at tick +%d; the player came to rest %.2f m from the break point; the shambler pressed again %d ticks after the break; the next bite landed %d ticks after the re-grab" % [released, drift, pressed, bite_at])


# DRIFT: a grab broken by the player's struggle leaves a break-away shove on the controlled player. When the
# shove's record expires the body must come to rest (no move command), and the total travel must not exceed
# the shove's own distance. A held move command must survive the expiry: a steered body is not zeroed.
func _drift_lane() -> void:
	var lane: String = "DRIFT"
	var shove_metres: float = SimShambler.BREAK_AWAY_SPEED * float(SimShambler.BREAK_AWAY_TICKS) / 20.0
	var boot: Dictionary = _boot()
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	var setup: Dictionary = _encounter(world, map, NEAR_METRES)
	if setup.is_empty():
		_fail(lane, "no %d m open line with sight in the %d m district" % [NEAR_METRES, DISTRICT_TILES])
		return
	var player: int = int(setup["player"])
	var zed: int = int(setup["zed"])
	if not _step_until_held(world, zed, player):
		_fail(lane, "no grab within %d ticks, so no break to drift from" % GRAB_TICKS)
		return
	var breaks: Array = []
	_listen_breaks(world, player, breaks)
	var start: Vector2 = Vector2.ZERO
	var broke: bool = false
	for _t in range(1, DEATH_TICKS + 1):
		start = _entity_pos(world, player)
		world.step()
		if not breaks.is_empty():
			broke = true
			break
	if not broke:
		_fail(lane, "the grab did not break within %d ticks" % DEATH_TICKS)
		return
	if str((breaks[0] as Dictionary)["cause"]) != "struggle":
		_info(lane, "the break was cause %s, not struggle; the shove still applies" % str((breaks[0] as Dictionary)["cause"]))
	var break_at: Vector2 = start
	var expire: int = -1
	for k in range(1, 3 * SimShambler.BREAK_AWAY_TICKS + 1):
		world.step()
		if not world.components.has_component(player, "breakAway"):
			expire = k
			break
	if expire < 0:
		_fail(lane, "the break-away record never expired within %d ticks" % (3 * SimShambler.BREAK_AWAY_TICKS))
		return
	var rest_from: Vector2 = _entity_pos(world, player)
	_settle(world, DRIFT_SETTLE_TICKS)
	var drift: float = _entity_pos(world, player).distance_to(rest_from)
	var speed: float = _velocity(world, player).length()
	var travelled: float = _entity_pos(world, player).distance_to(break_at)
	var zero_at: int = 0
	if speed >= MOVED_METRES:
		_fail(lane, "the break-away velocity %.2f m/s is still on the controlled player %d ticks after its record expired; the body drifted %.2f m in %d ticks" % [speed, expire, drift, DRIFT_SETTLE_TICKS])
		return
	if travelled > shove_metres + DRIFT_SLACK_METRES:
		_fail(lane, "the body travelled %.2f m from the break, past the shove's %.2f m" % [travelled, shove_metres])
		return
	_ok(lane, "record expired %d ticks after the break; the body came to rest (drift %.4f m over %d ticks after expiry); travelled %.2f m from the break against a shove of %.2f m" % [expire, drift, DRIFT_SETTLE_TICKS, travelled, shove_metres])
	_drift_guard()


# A held move command survives the expiry of the shove that preceded it: the body is steered every tick, the
# record expires, and the steered velocity must still be on the body.
func _drift_guard() -> void:
	var lane: String = "DRIFT"
	var boot: Dictionary = _boot()
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	var setup: Dictionary = _encounter(world, map, NEAR_METRES)
	if setup.is_empty():
		_fail(lane, "guard: no %d m open line with sight" % NEAR_METRES)
		return
	var player: int = int(setup["player"])
	var zed: int = int(setup["zed"])
	if not _step_until_held(world, zed, player):
		_fail(lane, "guard: no grab within %d ticks" % GRAB_TICKS)
		return
	var breaks: Array = []
	_listen_breaks(world, player, breaks)
	for _t in range(1, DEATH_TICKS + 1):
		world.step()
		if not breaks.is_empty():
			break
	if breaks.is_empty():
		_fail(lane, "guard: the grab did not break")
		return
	var steer: Vector2 = Vector2(WALK_SPEED, 0.0)
	var expire: int = -1
	for k in range(1, 3 * SimShambler.BREAK_AWAY_TICKS + 1):
		_walk(world, player, Vector2(1.0, 0.0))
		world.step()
		if expire < 0 and not world.components.has_component(player, "breakAway"):
			expire = k
	if expire < 0:
		_fail(lane, "guard: the break-away record never expired")
		return
	var v: Vector2 = _velocity(world, player)
	if absf(v.x - steer.x) > 0.01:
		_fail(lane, "guard: a held move command (%.2f m/s) was overridden at the shove's expiry; the velocity is now %.2f" % [steer.x, v.x])
		return
	_ok(lane, "guard: a held move command (%.2f m/s) survives the shove's expiry at +%d ticks; the body is still steered" % [steer.x, expire])

# DRIFT-WALL: the break-away shove runs into a wall tile WALL_AHEAD_METRES along its own direction. The collision
# zeroes the axis it hits and the other axis keeps the shove's value (DRIFT.md step 7). Both axes must be zero,
# and the body must not move, after the record expires. The wall is a fixture: one map tile set to Wall once the
# shove exists.
func _drift_wall() -> void:
	var lane: String = "DRIFT-WALL"
	var boot: Dictionary = _boot()
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	var setup: Dictionary = _encounter(world, map, NEAR_METRES)
	if setup.is_empty():
		_fail(lane, "no %d m open line with sight in the %d m district" % [NEAR_METRES, DISTRICT_TILES])
		return
	var player: int = int(setup["player"])
	var zed: int = int(setup["zed"])
	if not _step_until_held(world, zed, player):
		_fail(lane, "no grab within %d ticks, so no break to drift from" % GRAB_TICKS)
		return
	var breaks: Array = []
	_listen_breaks(world, player, breaks)
	var broke: bool = false
	for _t in range(1, DEATH_TICKS + 1):
		world.step()
		if not breaks.is_empty():
			broke = true
			break
	if not broke:
		_fail(lane, "the grab did not break within %d ticks" % DEATH_TICKS)
		return
	var rec: Variant = world.components.get_component(player, "breakAway")
	if not (rec is Dictionary):
		_fail(lane, "no break-away record on the player at the break")
		return
	# The sim's shove here is a pure x shove (the straight-away heading was blocked, so the fan took east), which
	# leaves no second axis to keep. The record's y component is set to DRIFT.md's measured value (0.1035 at 2.1 m/s),
	# so the shove has the stale axis the lane is about. The dx is the sim's own.
	(rec as Dictionary)["dy"] = DRIFT_WALL_SHOVE_DY
	var sx: float = float((rec as Dictionary)["dx"])
	var sy: float = float((rec as Dictionary)["dy"])
	var n: float = sqrt(sx * sx + sy * sy)
	if n == 0.0:
		_fail(lane, "the break-away record has no direction")
		return
	var p0: Vector2 = _entity_pos(world, player)
	var ahead: Vector2 = p0 + Vector2(sx, sy) / n * WALL_AHEAD_METRES
	var wall: Vector2i = Vector2i(floori(ahead.x), floori(ahead.y))
	# The wall is both the tile and the movement cell (world.map_cells is what the integrator reads, as
	# fortify.gd and check_vehicles.gd write it).
	map.tiles[wall.y * int(map.w) + wall.x] = SimTileMap.Tile.Wall
	world.map_cells[wall.y * int(world.map_width) + wall.x] = 1
	world.invalidateMap()
	var collided: int = -1
	var kept_dy: float = 0.0
	var expire: int = -1
	for k in range(1, 3 * SimShambler.BREAK_AWAY_TICKS + 1):
		world.step()
		var v: Vector2 = _velocity(world, player)
		if collided < 0 and absf(v.x) < 0.0001 and absf(v.y) > MOVED_METRES:
			collided = k
			kept_dy = v.y
		if not world.components.has_component(player, "breakAway"):
			expire = k
			break
	if collided < 0:
		_fail(lane, "the shove never hit the wall at %s (%.1f m ahead); the fixture did not produce the one-axis collision" % [str(wall), WALL_AHEAD_METRES])
		return
	if expire < 0:
		_fail(lane, "the break-away record never expired within %d ticks" % (3 * SimShambler.BREAK_AWAY_TICKS))
		return
	var rest_from: Vector2 = _entity_pos(world, player)
	_settle(world, DRIFT_SETTLE_TICKS)
	var v_end: Vector2 = _velocity(world, player)
	var drift: float = _entity_pos(world, player).distance_to(rest_from)
	if absf(v_end.x) > 0.0001 or absf(v_end.y) > 0.0001:
		_fail(lane, "after the wall at +%d and expiry at +%d the velocity is (%.4f, %.4f), not zero: the stale axis is still on the body" % [collided, expire, v_end.x, v_end.y])
		return
	if drift > 0.01:
		_fail(lane, "the body drifted %.4f m in the %d ticks after expiry" % [drift, DRIFT_SETTLE_TICKS])
		return
	_ok(lane, "shove into a wall %.1f m ahead: the wall zeroed x at +%d (y kept %.4f); expiry at +%d; both axes zero after, drift %.4f m over %d ticks" % [WALL_AHEAD_METRES, collided, kept_dy, expire, drift, DRIFT_SETTLE_TICKS])

# --- BREAK -----------------------------------------------------------------------------------------

func _break_lane() -> void:
	var lane: String = "BREAK"
	var boot: Dictionary = _boot()
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	var setup: Dictionary = _encounter(world, map, NEAR_METRES)
	if setup.is_empty():
		_fail(lane, "no %d m open line with sight in the %d m district" % [NEAR_METRES, DISTRICT_TILES])
		return
	var player: int = int(setup["player"])
	var zed: int = int(setup["zed"])
	if not _step_until_held(world, zed, player):
		_fail(lane, "no contact to break: no grab within %d ticks (%.0f s)" % [GRAB_TICKS, float(GRAB_TICKS) / 20.0])
		return
	var grab_at: int = _rel(world)
	# One melee attempt while held. The sim refuses it (melee.gd try_begin_swing, grabbed): a finding.
	if SimMelee.try_begin_swing(world, player):
		_finding(lane, "melee started while grabbed; the refusal the sim documents (melee.gd try_begin_swing, grabbed) did not hold")
	else:
		_finding(lane, "melee refused while grabbed (melee.gd try_begin_swing: grabbed); the answer to a grab is the struggle (F, shambler.gd struggle intake)")
	var total_grip: float = 0.0
	var sources: Array = (world.components.get_component(player, "grabbed") as Dictionary)["sources"] as Array
	for src in sources:
		var holder: Variant = world.components.get_component(int(src), "shambler")
		if holder is Dictionary:
			total_grip += float((holder as Dictionary)["grabStrength"])
	var odds: float = SimAptitudes.escape_chance(world, player, total_grip)
	var stamina: float = float((world.components.get_component(player, "stamina") as Dictionary).get("current", 0.0))
	_info(lane, "escape odds %.3f per roll against %d holder(s) (grip %.2f), stamina %.0f, %d ticks to each roll; grab at tick +%d" % [odds, sources.size(), total_grip, stamina, STRUGGLE_TICKS, grab_at])
	var broke: Dictionary = {}
	var hit: Dictionary = {}
	_sub_serial += 1
	world.events.subscribe({"type": "grab.broken", "id": "fp_encounter.break.%d" % _sub_serial, "handler": func(ev: Dictionary) -> void:
		if int(ev.get("victim", -1)) == player:
			broke["ev"] = ev
			broke["tick"] = _rel(world)
	})
	_sub_serial += 1
	world.events.subscribe({"type": "attack.connected", "id": "fp_encounter.hit.%d" % _sub_serial, "handler": func(ev: Dictionary) -> void:
		if int(ev.get("target", -1)) == zed and int(ev.get("attacker", -1)) == player:
			hit["ev"] = ev
	})
	var presses: int = 0
	for t in range(1, BREAK_TICKS + 1):
		if t % SWING_EVERY_TICKS == 0:
			world.commands.push({"type": "swing"})
			presses += 1
		world.step()
		if broke.has("ev") or hit.has("ev"):
			break
	if broke.has("ev"):
		var ev: Dictionary = broke["ev"] as Dictionary
		_ok(lane, "grab.broken at tick +%d, %d ticks after the grab, after %d F presses (cause %s, by %d, the victim)" % [int(broke["tick"]), int(broke["tick"]) - grab_at, presses, str(ev.get("cause", "?")), int(ev.get("by", -1))])
		return
	if hit.has("ev"):
		var hev: Dictionary = hit["ev"] as Dictionary
		_ok(lane, "the zombie took a hit (%s, %s damage) from the player while the grab held" % [str(hev.get("bodyPart", "?")), str(hev.get("damage", "?"))])
		return
	_fail(lane, "neither the grab broke nor the zombie took a hit in %d F presses over %d ticks; still held: %s; escape odds %.3f per roll" % [presses, BREAK_TICKS, str(_held(world, zed, player)), odds])
