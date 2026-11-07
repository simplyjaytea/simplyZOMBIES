extends SceneTree
# Every zombie kind against the first-person player. One body of a kind is placed in the seeded district, the
# controlled player stands (or walks, where a lane says so) with a clear line, the sim is stepped, and one line is
# printed per kind. The sim is read and stepped, never changed. A mechanic the sim does not have is a FAIL with what is
# missing; the gate may end red and that is the finding.
#
#   RUNNER     acquires at 9 m by day; closing speed (player still) against 1.4 x 2.1 = 2.94 m/s; a walking player (2.1)
#              is caught, a sprinting one (6.3) is not (gap after 100 ticks).
#   STALKER    acquires at 7 m by day; behind a wall at 10 m, a sprint at 20 m turns it (hearing): distance at the turn.
#   SCREAMER   acquires and screams at 9 m (zombie.screamed, noise 300); one scream in the 600-tick cooldown; a shambler
#              40 m away turns toward the scream.
#   BLOATER    killed at 4 m: scent 30 and a contamination cloud; the player with an open wound at 4 m takes an exposure
#              within 200 ticks; the player at 8 m does not (cloud radius 6).
#   HEAVY      acquires at 5 m; closing speed against 0.6 x 2.1 = 1.26 m/s; the bat's swing leaves it alive where a
#              shambler dies. ARMORED: a torso hit does less than on a shambler (both printed).
#   CRAWLER    closing speed against the shambler's (ratio); the legs share of its bite (bite weights).
#   BLOODHOUND 25 m, no sight: the player walks 40 m then stands; Track reaches within 2 m (ticks); a rifle shot 40 m
#              away: stays out of Seek, Pursue and Investigate.
#   LURKER     dormant indoors; a walking player outdoors does not wake it; a rifle shot on its floor does (ticks).
#   FEIGNER    lies (is_lying); a living body within 2.5 m rises (distance and tick); it grabs after.
#   JUGGERNAUT a timber wall between it and a living player: the damage each shove does to the wall.
#
# Plants (run by hand, restored): runner.json speed 1.4 -> 0.8 (RUNNER red); the bloater's bloom disabled (BLOATER red).

const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const SimStances = preload("res://sim/stances.gd")
const SimAim = preload("res://sim/aim.gd")

const SEED: int = SimBoot.DISTRICT_SEED
const DISTRICT_TILES: int = 64
const WALK: float = 2.1
const SPRINT: float = 6.3
const TICK_S: float = 0.05
const WAIT: int = 240
const CANDIDATES: int = 200
const CONTACT: float = 1.6

var _fails: int = 0
var _sub: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_runner()
	_stalker()
	_screamer()
	_bloater()
	_heavy_armored()
	_crawler()
	_bloodhound()
	_lurker()
	_feigner()
	_juggernaut()
	print("FP_KINDS_RESULT gate %s: %d FAIL" % ["green" if _fails == 0 else "red", _fails])
	quit(0 if _fails == 0 else 1)


func _ok(lane: String, msg: String) -> void:
	print("FP_KINDS_OK %s %s" % [lane, msg])


func _fail(lane: String, msg: String) -> void:
	_fails += 1
	push_error("FP_KINDS_FAIL %s %s" % [lane, msg])


func _finding(lane: String, msg: String) -> void:
	print("FP_KINDS_FINDING %s %s" % [lane, msg])


func _info(lane: String, msg: String) -> void:
	print("FP_KINDS_INFO %s %s" % [lane, msg])


# --- SETUP -----------------------------------------------------------------------------------------

func _boot(tiles: int = DISTRICT_TILES) -> Dictionary:
	var boot: Dictionary = SimBoot.playable(SEED, tiles)
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	var player: int = int(world.player)
	var doomed: Array = []
	for ent in world.components.query(["zombieType"]):
		doomed.append(int(ent))
	for ent in world.components.query(["shambler"]):
		if not doomed.has(int(ent)):
			doomed.append(int(ent))
	for ent in doomed:
		world.despawn(int(ent))
	# Colonists are removed, not parked: they walk back into the lane, and a zombie that has found one
	# pursues it instead of the player (seen as a zero closing speed at 9 m, RUNNER, 2026-11-07).
	for ent in world.components.query(["identity"]):
		if int(ent) != player:
			world.despawn(int(ent))
	world.components.set_component(player, "controlled", {})
	SimMelee.make_melee_armed(world, player)
	SimHealth.make_stamina(world, player, 100)
	# Screams are logged from the boot on: a screamer that sees the player screams during the placement's settle.
	var screams: Dictionary = {}
	_sub += 1
	world.events.subscribe({"type": "zombie.screamed", "id": "fp_kinds.log-scream.%d" % _sub, "handler": func(ev: Dictionary) -> void:
		var ent: int = int(ev.get("entity", -1))
		if not screams.has(ent):
			screams[ent] = []
		(screams[ent] as Array).append(int(world.tick))
	})
	return {"world": world, "map": map, "player": player, "screams": screams}


func _far_tile(map: Variant, here: Vector2, min_m: float) -> Vector2i:
	for y in range(1, int(map.h) - 1):
		for x in range(1, int(map.w) - 1):
			if _open(map, x, y) and _centre(Vector2i(x, y)).distance_to(here) >= min_m:
				return Vector2i(x, y)
	return Vector2i(1, 1)


func _open(map: Variant, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= int(map.w) or y >= int(map.h):
		return false
	if SimTileMap.tile_at(map, x, y) != SimTileMap.Tile.Floor or SimTileMap.is_solid(map, x, y):
		return false
	return not SimTileMap.is_indoors(map, x, y)


# A three-wide open strip along the line: a body walks straight at the player, not around a corner it cannot see.
func _line_ok(map: Variant, from: Vector2i, dir: Vector2i, metres: int, back: int = 0) -> bool:
	var side := Vector2i(-dir.y, dir.x)
	for k in range(-back, metres + 1):
		var c: Vector2i = from + dir * k
		if not _open(map, c.x, c.y) or not _open(map, c.x + side.x, c.y + side.y) or not _open(map, c.x - side.x, c.y - side.y):
			return false
	return true


# Places the player and one body of `type_id` `metres` away along `dir`. With `sight`, the body must see the player (the
# sim's own detail). Returns {player, zed, from, dir} or {}.
func _placement(b: Dictionary, type_id: String, metres: int, dir: Vector2i, sight: bool, back: int = 0) -> Dictionary:
	var world: Variant = b["world"]
	var map: Variant = b["map"]
	var player: int = int(b["player"])
	var tries: int = 0
	for y in range(1, int(map.h) - 1):
		for x in range(1, int(map.w) - 1):
			var from := Vector2i(x, y)
			if not _line_ok(map, from, dir, metres, back):
				continue
			tries += 1
			_place(world, player, _centre(from))
			var zed: int = _spawn(world, _centre(from + dir * metres), type_id)
			_settle(world, 6)
			if not sight:
				return {"player": player, "zed": zed, "from": from, "dir": dir}
			var at: Vector2 = _pos(world, player)
			# A view is cast a few quadrants a tick, so a new observer sees nothing until its cast lands.
			for _w in range(10):
				if _sees(world, zed, player):
					return {"player": player, "zed": zed, "from": from, "dir": dir}
				_settle(world, 4)
			if _sees(world, zed, player):
				return {"player": player, "zed": zed, "from": from, "dir": dir}
			world.despawn(zed)
			if tries >= CANDIDATES:
				return {}
	return {}


func _sees(world: Variant, zed: int, player: int) -> bool:
	var at: Vector2 = _pos(world, player)
	return int(world.vision.call("detail", zed, at.x, at.y, -1, player)) > 0


func _spawn(world: Variant, at: Vector2, type_id: String) -> int:
	return int(SimRoster.spawn_zombie(world, at.x, at.y, type_id, world.rng.stream("shambler")))


func _place(world: Variant, ent: int, at: Vector2) -> void:
	world.components.set_component(ent, "position", {"x": at.x, "y": at.y})
	var vel: Variant = world.components.get_component(ent, "velocity")
	if vel is Dictionary:
		(vel as Dictionary)["dx"] = 0.0
		(vel as Dictionary)["dy"] = 0.0


func _vel(world: Variant, ent: int, v: Vector2) -> void:
	var vel: Variant = world.components.get_component(ent, "velocity")
	if vel is Dictionary:
		(vel as Dictionary)["dx"] = v.x
		(vel as Dictionary)["dy"] = v.y


func _settle(world: Variant, ticks: int) -> void:
	for _i in ticks:
		world.step()


func _centre(t: Vector2i) -> Vector2:
	return Vector2(float(t.x) + 0.5, float(t.y) + 0.5)


func _pos(world: Variant, ent: int) -> Vector2:
	var pos: Variant = world.components.get_component(ent, "position")
	if not (pos is Dictionary):
		return Vector2.ZERO
	return Vector2(float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]))


func _state(world: Variant, zed: int) -> int:
	var sd: Variant = world.components.get_component(zed, "shambler")
	return int((sd as Dictionary).get("state", -1)) if sd is Dictionary else -1


func _st(name: String) -> int:
	return int(SimShambler.ShamblerState[name])


func _hunting(world: Variant, zed: int) -> bool:
	var s: int = _state(world, zed)
	return s == _st("Seek") or s == _st("Pursue")


func _dist(world: Variant, a: int, b: int) -> float:
	return _pos(world, a).distance_to(_pos(world, b))


# Steps until `zed` acquires the player; returns the tick, or -1.
func _acquire(world: Variant, zed: int) -> int:
	for t in range(1, WAIT + 1):
		world.step()
		if _hunting(world, zed):
			return t
	return -1


# Speed toward the still player over `ticks`, in metres per second.
func _closing_speed(world: Variant, zed: int, player: int, ticks: int) -> float:
	var d0: float = _dist(world, zed, player)
	for _t in ticks:
		world.step()
	var d1: float = _dist(world, zed, player)
	return (d0 - d1) / (float(ticks) * TICK_S)


func _line(map: Variant, metres: int) -> Dictionary:
	for y in range(1, int(map.h) - 1):
		for x in range(1, int(map.w) - 1):
			for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
				if _line_ok(map, Vector2i(x, y), d, metres):
					return {"from": Vector2i(x, y), "dir": d}
	return {}


# --- RUNNER --------------------------------------------------------------------------------------

func _runner() -> void:
	var lane: String = "RUNNER"
	var b: Dictionary = _boot()
	var s: Dictionary = _placement(b, "zombie.runner", 9, Vector2i(1, 0), true)
	if s.is_empty():
		_fail(lane, "no 9 m open line with sight for a runner")
		return
	var world: Variant = b["world"]
	var zed: int = int(s["zed"])
	var player: int = int(s["player"])
	var t: int = _acquire(world, zed)
	if t < 0:
		_fail(lane, "a runner 9 m away by day did not acquire the player in %d ticks (state %d)" % [WAIT, _state(world, zed)])
		return
	var speed: float = _closing_speed(world, zed, player, 40)
	var want: float = 1.4 * WALK
	if absf(speed - want) > 0.3:
		_fail(lane, "closing at %.2f m/s, content 1.4 x 2.1 = %.2f m/s (acquired at +%d)" % [speed, want, t])
		return
	# A walking player (2.1) is caught; a sprinting one (6.3) is not, after 100 ticks.
	var walk: Dictionary = _run_away(_boot(), "zombie.runner", 9, WALK, 400)
	var sprint: Dictionary = _run_away(_boot(), "zombie.runner", 9, SPRINT, 100)
	if walk.is_empty() or sprint.is_empty():
		_fail(lane, "no 9 m line for the chase check")
		return
	if not bool(walk["caught"]):
		_fail(lane, "a walking player (2.1 m/s) was not caught in 400 ticks (gap %.2f m)" % float(walk["gap"]))
		return
	if bool(sprint["caught"]):
		_fail(lane, "a sprinting player (6.3 m/s) was caught by a runner")
		return
	_ok(lane, "acquires at +%d at 9 m by day; closing %.2f m/s (1.4 x 2.1 = %.2f); walking 2.1 m/s caught at +%d; sprinting 6.3 m/s gap %.2f m after 100 ticks" % [t, speed, want, int(walk["caught_at"]), float(sprint["gap"])])


# The player walks (or sprints) directly away from the body placed `metres` off along +x; caught when within CONTACT.
func _run_away(b: Dictionary, type_id: String, metres: int, speed: float, limit: int) -> Dictionary:
	# The player runs away along -x, so the line must be open behind it for the whole run: 40 tiles.
	var s: Dictionary = _placement(b, type_id, metres, Vector2i(1, 0), true, 40)
	if s.is_empty():
		return {}
	var world: Variant = b["world"]
	var zed: int = int(s["zed"])
	var player: int = int(s["player"])
	if speed > WALK:
		world.components.set_component(player, "posture", SimStances.make_posture(SimStances.Stance.Sprint))
	_acquire(world, zed)
	var caught_at: int = -1
	for t in range(1, limit + 1):
		_vel(world, player, Vector2(-speed, 0.0))
		world.step()
		if caught_at < 0 and _dist(world, zed, player) <= CONTACT:
			caught_at = t
		if t == 100 and caught_at < 0:
			pass
	_vel(world, player, Vector2.ZERO)
	return {"caught": caught_at >= 0, "caught_at": caught_at, "gap": _dist(world, zed, player)}


# --- STALKER -------------------------------------------------------------------------------------

func _stalker() -> void:
	var lane: String = "STALKER"
	var b: Dictionary = _boot()
	var line: Dictionary = _line(b["map"], 42)
	if line.is_empty():
		_fail(lane, "no 42 m open line for the approach")
		return
	var from: Vector2i = line["from"]
	var d: Vector2i = line["dir"]
	# The player walks in from 40 m, one stance at a time, the stalker and a shambler at the same spot. Hearing
	# (0.9 for the stalker, 0.2 for the shambler) is what a turn by hearing shows; a turn by sight is named apart.
	var stances: Array = [["walking", SimStances.Stance.Walk], ["jogging", SimStances.Stance.Jog], ["sprinting", SimStances.Stance.Sprint]]
	var sprint_turn: float = -1.0
	var ok_all: bool = true
	for pair in stances:
		var name: String = pair[0]
		var stance: int = pair[1]
		var sr: Dictionary = _approach("zombie.stalker", stance, from, d)
		var hr: Dictionary = _approach("zombie.shambler", stance, from, d)
		_info(lane, "%s: stalker %s; shambler %s" % [name, _turn_text(sr), _turn_text(hr)])
		var sh: float = _hear_d(sr)
		var hh: float = _hear_d(hr)
		# One tick of the approach is the finest step a turn can be ordered by: a sprint moves 0.32 m a tick.
		if sh < hh - SPRINT * TICK_S:
			_fail(lane, "%s: the stalker turns at %.1f m by hearing, the shambler at %.1f m; hearing 0.9 must reach at least as far as 0.2" % [name, sh, hh])
			ok_all = false
		if stance == SimStances.Stance.Sprint:
			sprint_turn = sh
	if sprint_turn <= 0.0 or sprint_turn > 14.0:
		_fail(lane, "a sprint turns the stalker at %.1f m by hearing; the claim is a finite distance no greater than 14 m" % sprint_turn)
		return
	if not ok_all:
		return
	_ok(lane, "approach from 40 m, same fixture as the shambler: a sprint turns the stalker by hearing at %.1f m; the stalker never turns nearer than the shambler for the same stance (see the INFO lines)" % sprint_turn)


# One approach: a fresh world, the body at `from`, the player at 40 m along `d` walking in at the stance's speed.
func _approach(type_id: String, stance: int, from: Vector2i, d: Vector2i) -> Dictionary:
	var b: Dictionary = _boot()
	var world: Variant = b["world"]
	var player: int = int(b["player"])
	var toward: Vector2i = -d
	world.components.set_component(player, "aim", {"radians": atan2(float(toward.y), float(toward.x))})
	world.components.set_component(player, "posture", SimStances.make_posture(stance))
	_place(world, player, _centre(from + d * 40))
	var zed: int = _spawn(world, _centre(from), type_id)
	# No eyes: without an observer the body cannot see, so any turn in this approach is a turn by hearing.
	world.components.remove_component(zed, "observer")
	_settle(world, 4)
	var speed: float = WALK * SimStances.speed_factor_of(stance)
	var dir: Vector2 = Vector2(float(toward.x), float(toward.y))
	var turn: float = -1.0
	var cause: String = ""
	for _k in range(1200):
		if _dist(world, zed, player) <= 1.8:
			break
		_vel(world, player, dir * speed)
		world.step()
		var st: int = _state(world, zed)
		if st == _st("Investigate") or st == _st("Seek") or st == _st("Pursue"):
			turn = _dist(world, zed, player)
			cause = "hearing"
			break
	_vel(world, player, Vector2.ZERO)
	return {"turn": turn, "cause": cause}


func _hear_d(r: Dictionary) -> float:
	return float(r["turn"]) if String(r["cause"]) == "hearing" else 0.0


func _turn_text(r: Dictionary) -> String:
	if float(r["turn"]) < 0.0:
		return "no turn in 1200 ticks"
	return "turns at %.1f m by %s" % [float(r["turn"]), String(r["cause"])]


# --- SCREAMER ------------------------------------------------------------------------------------

func _screamer() -> void:
	var lane: String = "SCREAMER"
	var b: Dictionary = _boot()
	var s: Dictionary = _placement(b, "zombie.screamer", 9, Vector2i(1, 0), true)
	if s.is_empty():
		_fail(lane, "no 9 m open line with sight for a screamer")
		return
	var world: Variant = b["world"]
	var zed: int = int(s["zed"])
	var screams: Array = []
	var log: Dictionary = b["screams"]
	for _t in range(WAIT):
		if log.has(zed):
			screams = (log[zed] as Array).duplicate()
			break
		world.step()
	if screams.is_empty():
		_fail(lane, "the screamer 9 m away did not scream in %d ticks" % WAIT)
		return
	var at: int = int(screams[0])
	# A shambler 40 m from the screamer; does it turn toward the scream?
	var far: Vector2i = _far_tile(b["map"], _pos(world, zed), 40.0)
	var listener: int = _spawn(world, _centre(far), "zombie.shambler")
	var turned: int = -1
	for _t in range(600):
		world.step()
		if turned < 0 and _state(world, listener) in [_st("Investigate"), _st("Seek"), _st("Pursue")]:
			turned = int(world.tick) - at
	for _t in range(600 - (int(world.tick) - at)):
		world.step()
	var count: int = screams.size()
	if count != 1:
		_fail(lane, "%d screams in the 600-tick cooldown (wanted 1)" % count)
		return
	if turned < 0:
		_finding(lane, "a shambler 40 m from the scream did not turn toward it in 600 ticks (scream at +%d, one scream in the cooldown)" % at)
		return
	_ok(lane, "screamed at +%d at 9 m: one scream in the 600-tick cooldown; a shambler 40 m away turned %d ticks after the scream" % [at, turned])


# --- BLOATER -------------------------------------------------------------------------------------

func _bloater() -> void:
	var lane: String = "BLOATER"
	var near: Dictionary = _bloat_exposure(4)
	var far: Dictionary = _bloat_exposure(8)
	if near.is_empty() or far.is_empty():
		_fail(lane, "no line for the bloater check")
		return
	if not bool(near["burst"]):
		_fail(lane, "the bloater killed at 4 m did not bloom (no scent 30, no contamination cloud)")
		return
	if int(near["exposures"]) <= 0:
		_fail(lane, "the player at 4 m with an open wound took no exposure from the cloud in %d ticks (cloud radius 6; the gas hurts only an open wound)" % WAIT)
		return
	if int(far["exposures"]) > 0:
		_fail(lane, "the player at 8 m took an exposure outside the cloud radius")
		return
	_ok(lane, "killed at 4 m: scent %.0f and a cloud; the player with an open wound took %d exposure(s) in %d ticks; at 8 m, %d" % [float(near["scent"]), int(near["exposures"]), int(near["ticks"]), int(far["exposures"])])


func _bloat_exposure(metres: int) -> Dictionary:
	var b: Dictionary = _boot()
	var s: Dictionary = _placement(b, "zombie.bloater", metres, Vector2i(1, 0), false)
	if s.is_empty():
		return {}
	var world: Variant = b["world"]
	var player: int = int(b["player"])
	var zed: int = int(s["zed"])
	SimWounds.append_wound(world, player, "cut", "torso", -1, 10.0)
	var scent: Array = []
	_sub += 1
	world.events.subscribe({"type": "scent.accumulated", "id": "fp_kinds.scent.%d" % _sub, "handler": func(ev: Dictionary) -> void:
		scent.append(float(ev.get("magnitude", 0.0)))
	})
	world.events.publish({"type": "attack.connected", "attacker": player, "target": zed, "bodyPart": "head", "damage": 999.0})
	world.step()
	var burst: bool = not world.entities.is_alive(zed) or world.components.has_component(zed, "corpse") or not scent.is_empty()
	var base: int = _exposures(world, player)
	var exposed: int = 0
	for t in range(1, WAIT + 1):
		world.step()
		exposed = maxi(exposed, _exposures(world, player) - base)
		if exposed > 0:
			break
	return {"burst": burst, "scent": (scent[0] if not scent.is_empty() else 0.0), "exposures": exposed, "ticks": WAIT}


func _exposures(world: Variant, ent: int) -> int:
	var st: Variant = world.components.get_component(ent, "zombieInfection")
	return ((st as Dictionary).get("exposures", []) as Array).size() if st is Dictionary else 0


# --- HEAVY and ARMORED ---------------------------------------------------------------------------

func _heavy_armored() -> void:
	var lane: String = "HEAVY"
	var b: Dictionary = _boot()
	var s: Dictionary = _placement(b, "zombie.heavy", 5, Vector2i(1, 0), true)
	if s.is_empty():
		_fail(lane, "no 5 m open line with sight for a heavy")
		return
	var world: Variant = b["world"]
	var zed: int = int(s["zed"])
	var player: int = int(s["player"])
	var t: int = _acquire(world, zed)
	if t < 0:
		_fail(lane, "a heavy 5 m away did not acquire the player")
		return
	var speed: float = _closing_speed(world, zed, player, 40)
	var grab: float = float((world.components.get_component(zed, "shambler") as Dictionary).get("grabStrength", -1.0))
	var want: float = 0.6 * WALK
	# One swing of the default melee profile (damage 11) at the same body 1 m in front; alive or dead by its head.
	var hv: Vector2 = _swing_head(_boot(), "zombie.heavy")
	var sv: Vector2 = _swing_head(_boot(), "zombie.shambler")
	var hf: float = (hv.x - hv.y) / hv.x
	var sf: float = (sv.x - sv.y) / sv.x
	if absf(speed - want) > 0.2:
		_fail(lane, "closing at %.2f m/s, content 0.6 x 2.1 = %.2f m/s; grab strength %.2f" % [speed, want, grab])
		return
	if hf >= sf:
		_fail(lane, "one swing: the heavy loses %.1f of %.1f (%.1f%%), the shambler %.1f of %.1f (%.1f%%): the heavy does not lose the smaller share" % [hv.x - hv.y, hv.x, hf * 100.0, sv.x - sv.y, sv.x, sf * 100.0])
		_armored()
		return
	_ok(lane, "acquires at +%d at 5 m; closing %.2f m/s (0.6 x 2.1 = %.2f); grab strength %.2f; one swing: the heavy loses %.1f of %.1f (%.1f%%), the shambler %.1f of %.1f (%.1f%%); neither dies in one swing" % [t, speed, want, grab, hv.x - hv.y, hv.x, hf * 100.0, sv.x - sv.y, sv.x, sf * 100.0])
	_armored()


# The body's total (head, torso, legs) before and after one swing, as Vector2(before, after). The body stands one metre in front of
# the player with no shambler behaviour, so it cannot grab during the wind-up: the lane measures the blow.
func _swing_head(b: Dictionary, type_id: String) -> Vector2:
	var world: Variant = b["world"]
	var map: Variant = b["map"]
	var player: int = int(b["player"])
	var line: Dictionary = _line(map, 3)
	if line.is_empty():
		return Vector2(-999.0, -999.0)
	var from: Vector2i = line["from"]
	var d: Vector2i = line["dir"]
	_place(world, player, _centre(from))
	var zed: int = _spawn(world, _centre(from + d), type_id)
	world.components.remove_component(zed, "shambler")
	var before: float = _body_total(world, zed)
	world.components.set_component(player, "aim", {"radians": atan2(float(d.y), float(d.x))})
	world.commands.push({"type": "swing"})
	_settle(world, 30)
	return Vector2(before, _body_total(world, zed))


func _body_total(world: Variant, zed: int) -> float:
	var body: Variant = world.components.get_component(zed, "body")
	if not body is Dictionary:
		return -999.0
	var total: float = 0.0
	for k in (body as Dictionary).keys():
		var v: Variant = (body as Dictionary)[k]
		if v is float or v is int:
			total += float(v)
	return total


func _head_of(world: Variant, zed: int) -> float:
	var body: Variant = world.components.get_component(zed, "body")
	return float((body as Dictionary).get("head", -999.0)) if body is Dictionary else -999.0


func _armored() -> void:
	var lane: String = "ARMORED"
	var torso: Dictionary = {}
	for type_id in ["zombie.shambler", "zombie.armored"]:
		var b: Dictionary = _boot()
		var s: Dictionary = _placement(b, type_id, 3, Vector2i(1, 0), false)
		if s.is_empty():
			_fail(lane, "no 3 m line for %s" % type_id)
			return
		var world: Variant = b["world"]
		var zed: int = int(s["zed"])
		var before: float = float((world.components.get_component(zed, "body") as Dictionary)["torso"])
		world.events.publish({"type": "attack.connected", "attacker": int(s["player"]), "target": zed, "bodyPart": "torso", "damage": 20.0})
		world.step()
		var body: Variant = world.components.get_component(zed, "body")
		var after: float = float((body as Dictionary).get("torso", before)) if body is Dictionary else before
		torso[type_id] = before - after
	var sh: float = float(torso["zombie.shambler"])
	var ar: float = float(torso["zombie.armored"])
	if ar >= sh:
		_finding(lane, "a 20-point torso hit takes %.1f off an armored body and %.1f off a shambler: no armour in the sim (zombie.armored has the shambler's torso and no mitigation block)" % [ar, sh])
		return
	_ok(lane, "a 20-point torso hit takes %.1f off an armored body, %.1f off a shambler" % [ar, sh])


# --- CRAWLER -------------------------------------------------------------------------------------

func _crawler() -> void:
	var lane: String = "CRAWLER"
	var b: Dictionary = _boot()
	var s: Dictionary = _placement(b, "zombie.crawler", 4, Vector2i(1, 0), true)
	if s.is_empty():
		_fail(lane, "no 4 m open line with sight for a crawler")
		return
	var world: Variant = b["world"]
	var zed: int = int(s["zed"])
	var player: int = int(s["player"])
	_acquire(world, zed)
	var cspeed: float = _closing_speed(world, zed, player, 40)
	var want: float = 0.8 * WALK * 0.45
	var cb: Dictionary = _boot()
	var sp: Dictionary = _placement(cb, "zombie.shambler", 4, Vector2i(1, 0), true)
	var sspeed: float = -1.0
	if not sp.is_empty():
		_acquire(cb["world"], int(sp["zed"]))
		sspeed = _closing_speed(cb["world"], int(sp["zed"]), int(sp["player"]), 40)
	var weights: Dictionary = SimShambler.bite_weights_of(world, "zombie.crawler")
	var legs: float = 0.0
	for k in weights.keys():
		if String(k).begins_with("leg"):
			legs += float(weights[k])
	if absf(cspeed - want) > 0.15:
		_fail(lane, "closes at %.2f m/s; content 0.8 x 2.1 x crawl 0.45 = %.2f m/s" % [cspeed, want])
		return
	if not SimHealth.is_crawling(world.components.get_component(zed, "body")):
		_fail(lane, "the crawler is not born legless (SimHealth.is_crawling is false)")
		return
	if legs < 0.5:
		_fail(lane, "a crawler's bite lands on the legs %.2f of the time (wanted over half)" % legs)
		return
	if sspeed > 0.0:
		_finding(lane, "the crawler closes at %.2f of the shambler's %.2f m/s in this lane (ratio %.2f, the shambler measured below its nominal 1.68). The sim applies each kind's own content crawl: the crawler's 0.45 (0.8 x 2.1 x 0.45 = 0.76, measured). The 0.25 is m2:variance's pin for a shambler with its legs gone, the shambler default, not the crawler" % [cspeed / sspeed, cspeed, sspeed])
	_ok(lane, "closes at %.2f m/s (0.8 x 2.1 x 0.45 = %.2f); born legless; its bite lands on the legs %.2f of the time" % [cspeed, want, legs])


# --- BLOODHOUND ----------------------------------------------------------------------------------

func _bloodhound() -> void:
	var lane: String = "BLOODHOUND"
	# A bloodhound has no eyes or ears (content: sensory noise 0, light 0), so sight is not what brings it. It leaves
	# Wander only on a rise of sensory.trail (20) over its own cell.
	var b: Dictionary = _boot(256)
	var map: Variant = b["map"]
	var world: Variant = b["world"]
	var player: int = int(b["player"])
	var line: Dictionary = _line(map, 66)
	if line.is_empty():
		_fail(lane, "no 66 m open line on the 256 district")
		return
	var from: Vector2i = line["from"]
	var d: Vector2i = line["dir"]
	var zed: int = _spawn(world, _centre(from), "zombie.bloodhound")
	_place(world, player, _centre(from + d * 2))
	var emitter: Variant = world.components.get_component(player, "attention_emitter")
	var scent_emit: float = float((emitter as Dictionary).get("scent", 0.0)) if emitter is Dictionary else 0.0
	var walked: int = 0
	for t in range(1, 40 * 20 + 1):
		_vel(world, player, Vector2(float(d.x) * WALK, float(d.y) * WALK))
		world.step()
		walked = t
		if int(float(t) * WALK * TICK_S) >= 40:
			break
	_vel(world, player, Vector2.ZERO)
	var trail: Array = []
	var reach: int = -1
	for t in range(1, 800):
		world.step()
		if t % 200 == 0:
			var zq: Vector2 = _pos(world, zed)
			trail.append("+%d state %d scent %.2f" % [t, _state(world, zed), float(world.field.scent_at(zq.x, zq.y))])
		if _dist(world, zed, player) <= 2.0:
			reach = t
			break
	var rise: float = _largest_rise(world, zed)
	_info(lane, "walk: trail laid 2 m from it, walked 40 m in %d ticks; %s; its cell reads %.2f" % [walked, ", ".join(trail), _scent_here(world, zed)])
	if reach < 0:
		_finding(lane, "a walking player never produces a scent rise of 20 over a cell (largest rise to a neighbour cell within 8 m: %.2f; content scent emitter %.1f); Track never starts, so the bloodhound cannot find the player (%.1f m away at +800 ticks, state %d)" % [rise, scent_emit, _dist(world, zed, player), _state(world, zed)])
	else:
		_ok(lane, "walk: Track reached within 2 m at +%d ticks" % reach)

	# The bloater's burst is 30 at its corpse (bloater.gd SCENT_BURST). The same question for a big source, once in its
	# own cell (2 m) and once in a neighbour cell (6 m), with the bloodhound standing still.
	for k in [2, 6]:
		var bb: Dictionary = _boot(256)
		var bworld: Variant = bb["world"]
		var bline: Dictionary = _line(bb["map"], 66)
		var bfrom: Vector2i = bline["from"]
		var bd: Vector2i = bline["dir"]
		var bz: int = _spawn(bworld, _centre(bfrom), "zombie.bloodhound")
		var src: Vector2 = _centre(bfrom + bd * k)
		bworld.events.publish({"type": "scent.accumulated", "x": src.x, "y": src.y, "magnitude": 30.0})
		bworld.step()
		var here0: float = _scent_here(bworld, bz)
		var brise: float = 0.0
		var got: int = -1
		var tracked: bool = false
		for t in range(1, 401):
			bworld.step()
			if t <= 60:
				brise = maxf(brise, _largest_rise(bworld, bz))
			if _state(bworld, bz) == _st("Track"):
				tracked = true
			if got < 0 and _pos(bworld, bz).distance_to(src) <= 1.0 and tracked:
				got = t
				break
		if got >= 0:
			_ok(lane, "a 30 scent burst (the bloater's) %d m from it: its cell reads %.2f after the burst, largest rise to a neighbour %.2f; Track brings it within 1 m of the burst at +%d ticks" % [k, here0, brise, got])
		else:
			_finding(lane, "a 30 scent burst (the bloater's) %d m from it: its cell reads %.2f after the burst, largest rise to a neighbour cell in 60 ticks %.2f (sensory.trail 20); Track %s (state %d at +400)" % [k, here0, brise, "entered, but did not reach the burst" if tracked else "never entered", _state(bworld, bz)])

	# Deaf: a rifle shot 40 m away.
	var dw: Dictionary = _boot(256)
	var dmap: Variant = dw["map"]
	var dline: Dictionary = _line(dmap, 42)
	if dline.is_empty():
		_fail(lane, "no 42 m line for the deafness check")
		return
	var dworld: Variant = dw["world"]
	var dz: int = _spawn(dworld, _centre(dline["from"]), "zombie.bloodhound")
	var shot_at: Vector2 = _centre((dline["from"] as Vector2i) + (dline["dir"] as Vector2i) * 40)
	dworld.events.publish({"type": "noise.emitted", "x": shot_at.x, "y": shot_at.y, "magnitude": 200.0, "source": int(dw["player"])})
	var heard: bool = false
	for _t in range(200):
		dworld.step()
		var st: int = _state(dworld, dz)
		if st == _st("Investigate") or st == _st("Seek") or st == _st("Pursue") or st == _st("Track"):
			heard = true
	if heard:
		_fail(lane, "the bloodhound turned to a rifle shot 40 m away")
		return
	_ok(lane, "deaf: a rifle shot 40 m away, no turn in 200 ticks")


# The largest scent rise from the body's own cell to a cell within two cells of it (the field's cells are 4 m;
# Track reads the neighbour cells). A level at the body's cell is returned as `here` through `_scent_here`.
func _largest_rise(world: Variant, zed: int) -> float:
	var zc: Vector2 = _pos(world, zed)
	var here: float = float(world.field.scent_at(zc.x, zc.y))
	var rise: float = 0.0
	for ox in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		for oy in [-8.0, -4.0, 0.0, 4.0, 8.0]:
			if ox == 0.0 and oy == 0.0:
				continue
			rise = maxf(rise, float(world.field.scent_at(zc.x + ox, zc.y + oy)) - here)
	return rise


func _scent_here(world: Variant, zed: int) -> float:
	var zc: Vector2 = _pos(world, zed)
	return float(world.field.scent_at(zc.x, zc.y))


# --- LURKER --------------------------------------------------------------------------------------

func _lurker() -> void:
	var lane: String = "LURKER"
	var b: Dictionary = _boot()
	var map: Variant = b["map"]
	var world: Variant = b["world"]
	var player: int = int(b["player"])
	var indoor := Vector2i(-1, -1)
	for y in range(2, int(map.h) - 2):
		for x in range(2, int(map.w) - 2):
			if indoor.x < 0 and SimTileMap.tile_at(map, x, y) == SimTileMap.Tile.Floor and SimTileMap.is_indoors(map, x, y):
				indoor = Vector2i(x, y)
	if indoor.x < 0:
		_fail(lane, "no indoor floor tile on the district")
		return
	var lurker: int = _spawn(world, _centre(indoor), "zombie.lurker")
	SimShambler.make_dormant(world, lurker, [])
	var out: Vector2i = _far_outdoor(map, _pos(world, lurker), 10.0)
	_place(world, player, _centre(out))
	var woke: int = -1
	for t in range(1, 101):
		_vel(world, player, Vector2(WALK, 0.0))
		world.step()
		if _state(world, lurker) != _st("Dormant") and woke < 0:
			woke = t
	_vel(world, player, Vector2.ZERO)
	if woke >= 0:
		_fail(lane, "a walking player outdoors woke the lurker at +%d" % woke)
		return
	var shot: Vector2 = _pos(world, lurker)
	world.events.publish({"type": "noise.emitted", "x": shot.x, "y": shot.y, "magnitude": 200.0, "source": player})
	var rose: int = -1
	for t in range(1, 201):
		world.step()
		if _state(world, lurker) != _st("Dormant") and rose < 0:
			rose = t
	if rose < 0:
		_fail(lane, "a rifle shot on the lurker's floor did not wake it in 200 ticks")
		return
	_ok(lane, "dormant indoors; a player walking 100 ticks outdoors (10 m+) did not wake it; a rifle shot on its floor woke it at +%d" % rose)


func _far_outdoor(map: Variant, here: Vector2, min_m: float) -> Vector2i:
	for y in range(1, int(map.h) - 1):
		for x in range(1, int(map.w) - 1):
			if _open(map, x, y) and _centre(Vector2i(x, y)).distance_to(here) >= min_m and _line_ok(map, Vector2i(x, y), Vector2i(1, 0), 4):
				return Vector2i(x, y)
	return Vector2i(1, 1)


# --- FEIGNER -------------------------------------------------------------------------------------

func _feigner() -> void:
	var lane: String = "FEIGNER"
	var b: Dictionary = _boot()
	var world: Variant = b["world"]
	var player: int = int(b["player"])
	var s: Dictionary = _placement(b, "zombie.feigner", 10, Vector2i(1, 0), false)
	if s.is_empty():
		_fail(lane, "no 10 m open line for a feigner")
		return
	var zed: int = int(s["zed"])
	var lying: int = -1
	for t in range(1, 201):
		world.step()
		if SimShambler.is_lying(world, zed):
			lying = t
			break
	if lying < 0:
		_fail(lane, "the feigner never lay down in 200 ticks (feigning %s)" % str(SimShambler.is_feigning(world, zed)))
		return
	var rise_d: float = -1.0
	var rose: int = -1
	for t in range(1, 401):
		_vel(world, player, Vector2(WALK, 0.0))
		world.step()
		if not SimShambler.is_lying(world, zed) and rose < 0:
			rose = t
			rise_d = _dist(world, zed, player)
			break
	_vel(world, player, Vector2.ZERO)
	if rose < 0:
		_fail(lane, "the feigner did not rise when a living body came to it")
		return
	var grabbed: int = -1
	for t in range(1, 301):
		world.step()
		if world.components.has_component(zed, "grabState") and grabbed < 0:
			grabbed = t
	if grabbed < 0:
		_fail(lane, "the feigner rose and did not grab in 300 ticks (state %d)" % _state(world, zed))
		return
	_ok(lane, "lay down at +%d; rose at +%d when the player was %.2f m away; grabbed at +%d after" % [lying, rose, rise_d, grabbed])


# --- JUGGERNAUT ----------------------------------------------------------------------------------

func _juggernaut() -> void:
	var lane: String = "JUGGERNAUT"
	if not FileAccess.file_exists("res://content/zombies/juggernaut.json"):
		_info(lane, "no juggernaut content on this base; skipped")
		return
	var b: Dictionary = _boot()
	var world: Variant = b["world"]
	var map: Variant = b["map"]
	var player: int = int(b["player"])
	var line: Dictionary = _line(map, 3)
	if line.is_empty():
		_fail(lane, "no 3 m open line for the shove check")
		return
	var from: Vector2i = line["from"]
	var wall: Vector2i = from + Vector2i(0, 1)
	var wid: int = int(world.entities.spawn())
	world.components.set_component(wid, "position", {"x": wall.x + 0.5, "y": wall.y + 0.5})
	world.components.set_component(wid, "timberWall", {"kind": "timber", "stage": 0, "contactTicks": 0, "condition": SimFortify.BARRICADE_CONDITION["timber"]})
	SimFortify.sync_map(world, true)
	var jug: int = _spawn(world, _centre(from), "zombie.juggernaut")
	_place(world, player, _centre(from + Vector2i(0, 2)))
	var hits: Array = []
	var prev: float = float((world.components.get_component(wid, "timberWall") as Dictionary)["condition"])
	for k in range(900):
		(world.components.get_component(jug, "velocity") as Dictionary)["dy"] = 2.0
		world.step()
		var now: float = float((world.components.get_component(wid, "timberWall") as Dictionary).get("condition", prev))
		if now < prev:
			hits.append(prev - now)
			prev = now
		if hits.size() >= 3:
			break
	if hits.is_empty():
		_fail(lane, "the juggernaut with a living player behind a timber wall shoved nothing in 900 ticks")
		return
	_ok(lane, "shoves a timber wall: %d shoves, damage per shove %s" % [hits.size(), str(hits)])


