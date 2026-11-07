extends SceneTree
# The first-person zombie tells: prose cues the HUD draws from the sim, so the player hears a zombie before the
# swipe. Each lane builds the real hud.gd node, sets the scene in the sim (placement; a fixture write only where a
# lane names one), steps the sim, reads lines(), and prints one line. A FAIL names what is missing.
#
#   QUIET    a sleeping (dormant) shambler 3 m away and a wandering one 30 m away: no tell line over 60 ticks.
#   NOTICED  a shambler 7 m ahead by day, on open ground, notices the player (zombie.noticed): the notice line
#            "ahead" is drawn, at +59 ticks after the notice still drawn, at +60 gone (the 3 s window).
#   SIDE     the same notice from the right, the left and behind (the look is fixed at east): "right", "left",
#            "behind".
#   CLOSE    a Pursuing shambler 4 m behind: the close line; the same 4 m in front: none. (Pursue is a fixture write:
#            the sim reaches it only by contact.)
#   SEVERAL  three shamblers notice at once: "Several things stir." and no single-direction notice line.
#   SCREAM   a screamer sees the player (zombie.screamed): the scream line at +100 ticks after the scream, gone at +101.
#   DIGITS   every line every lane drew passes the digit scan.
#
# Plant (run by hand, restored): hud.gd TELL_NOTICE_TICKS raised to a million; NOTICED's +60 check goes red.
# Placement only: the district's zombies are removed and the other survivors parked, as in the other gates.

const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimAim = preload("res://sim/aim.gd")
const Hud = preload("res://presentation/first_person/hud.gd")

const SEED: int = SimBoot.DISTRICT_SEED
const DISTRICT_TILES: int = 64
const PARK_METRES: float = 40.0
# The shambler's sight reach on this branch is its content reach, 3.8 m by day (the 8 m daylight floor is on the
# bundle branch). The notice lanes place it inside that reach, as the spec says; the screamer's reach is 11.4 m.
const AHEAD_METRES: int = 3
const SCREAM_METRES: int = 7
const CLOSE_METRES: int = 4
const WAIT_TICKS: int = 200
const NOTICE_WINDOW: int = 60
const SCREAM_WINDOW: int = 100
const CANDIDATES: int = 200

var _fails: int = 0
var _all_lines: Array[String] = []
var _sub_serial: int = 0
var _hud: Control = null
# Notices and screams, recorded from the moment of boot: a shambler inside its reach notices during the placement
# settle, before a lane could subscribe.
var _notices: Dictionary = {}
var _screams: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_quiet()
	_noticed()
	_side()
	_close()
	_several()
	_scream()
	_digits()
	print("FP_TELLS_RESULT gate %s: %d FAIL" % ["green" if _fails == 0 else "red", _fails])
	quit(0 if _fails == 0 else 1)


func _ok(lane: String, message: String) -> void:
	print("FP_TELLS_OK %s %s" % [lane, message])


func _fail(lane: String, message: String) -> void:
	_fails += 1
	push_error("FP_TELLS_FAIL %s %s" % [lane, message])


# --- SETUP -----------------------------------------------------------------------------------------

func _boot() -> Dictionary:
	var boot: Dictionary = SimBoot.playable(SEED, DISTRICT_TILES)
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	var player: int = int(world.player)
	_notices = {}
	_screams = {}
	_sub_serial += 1
	world.events.subscribe({"type": "zombie.noticed", "id": "fp_tells.log-notice.%d" % _sub_serial, "handler": func(ev: Dictionary) -> void:
		var ent: int = int(ev.get("entity", -1))
		if not _notices.has(ent):
			_notices[ent] = int(world.tick)
	})
	_sub_serial += 1
	world.events.subscribe({"type": "zombie.screamed", "id": "fp_tells.log-scream.%d" % _sub_serial, "handler": func(ev: Dictionary) -> void:
		var ent: int = int(ev.get("entity", -1))
		if not _screams.has(ent):
			_screams[ent] = int(world.tick)
	})
	var doomed: Array = []
	for ent in world.components.query(["zombieType"]):
		doomed.append(int(ent))
	for ent in world.components.query(["shambler"]):
		if not doomed.has(int(ent)):
			doomed.append(int(ent))
	for ent in doomed:
		world.despawn(int(ent))
	var far: Vector2 = _centre(_far_open_tile(map, _pos(world, player)))
	for ent in world.components.query(["identity", "position"]):
		if int(ent) != player:
			_place(world, int(ent), far)
	SimMelee.make_melee_armed(world, player)
	SimHealth.make_stamina(world, player, 100)
	# The look is east (radians 0): the sim's aim, the same value the scene pushes for a look east.
	world.components.set_component(player, "aim", {"radians": 0.0})
	return {"world": world, "map": map}


func _far_open_tile(map: Variant, here: Vector2) -> Vector2i:
	for y in range(1, int(map.h) - 1):
		for x in range(1, int(map.w) - 1):
			if _open(map, x, y) and _centre(Vector2i(x, y)).distance_to(here) >= PARK_METRES:
				return Vector2i(x, y)
	return Vector2i(1, 1)


func _open(map: Variant, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= int(map.w) or y >= int(map.h):
		return false
	if SimTileMap.tile_at(map, x, y) != SimTileMap.Tile.Floor or SimTileMap.is_solid(map, x, y):
		return false
	return not SimTileMap.is_indoors(map, x, y)


# A line of `metres + 1` open tiles from `from` in `dir`.
func _line_from(map: Variant, from: Vector2i, dir: Vector2i, metres: int) -> bool:
	for k in range(0, metres + 1):
		if not _open(map, from.x + dir.x * k, from.y + dir.y * k):
			return false
	return true


# Places the player and a zombie of `type_id` `metres` away in `dir`, on the first open line from a tile the sim's
# own detail sees (the zombie's detail on the player above zero). Returns {player, zed, from} or {}.
func _placement(world: Variant, map: Variant, dir: Vector2i, metres: int, type_id: String) -> Dictionary:
	var player: int = int(world.player)
	var tried: int = 0
	for y in range(1, int(map.h) - 1):
		for x in range(1, int(map.w) - 1):
			var from: Vector2i = Vector2i(x, y)
			if not _line_from(map, from, dir, metres):
				continue
			tried += 1
			_place(world, player, _centre(from))
			var zed: int = _spawn(world, _centre(from + dir * metres), type_id)
			_settle(world, 6)
			var at: Vector2 = _pos(world, player)
			if int(world.vision.call("detail", zed, at.x, at.y, -1, player)) > 0:
				return {"player": player, "zed": zed, "from": from}
			world.despawn(zed)
			if tried >= CANDIDATES:
				return {}
	return {}


func _spawn(world: Variant, at: Vector2, type_id: String) -> int:
	return int(SimRoster.spawn_zombie(world, at.x, at.y, type_id, world.rng.stream("shambler")))


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


func _pos(world: Variant, ent: int) -> Vector2:
	var pos: Variant = world.components.get_component(ent, "position")
	if not (pos is Dictionary):
		return Vector2.ZERO
	return Vector2(float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]))


func _hud_for(world: Variant, player: int) -> Control:
	if _hud != null:
		_hud.queue_free()
	var h: Control = Hud.new()
	root.add_child(h)
	h.set_state(world, player, "", "", false, false)
	_hud = h
	return h


func _tell_lines(lines: Array) -> Array[String]:
	var out: Array[String] = []
	var known: Array = []
	known.append_array(Hud.NOTICE_LINES.values())
	known.append_array(Hud.CLOSE_LINES.values())
	known.append(Hud.SEVERAL_STIR_LINE)
	known.append(Hud.SCREAM_LINE)
	for l in lines:
		if known.has(String(l)):
			out.append(String(l))
	return out


func _notice_of(lines: Array) -> String:
	for l in lines:
		if Hud.NOTICE_LINES.values().has(String(l)):
			return String(l)
	return ""


# The tick `zed` noticed the player: from the log, else stepped until it does. -1 if it does not in WAIT_TICKS.
func _until_noticed(world: Variant, zed: int) -> int:
	if _notices.has(zed):
		return int(_notices[zed])
	for _t in range(WAIT_TICKS):
		world.step()
		if _notices.has(zed):
			return int(_notices[zed])
	return -1


# --- QUIET -----------------------------------------------------------------------------------------

func _quiet() -> void:
	var lane: String = "QUIET"
	var b: Dictionary = _boot()
	var world: Variant = b["world"]
	var map: Variant = b["map"]
	var player: int = int(world.player)
	# The sleeper is made dormant before the world steps at all, so it never wakes into a notice.
	var line: Dictionary = {}
	for y in range(1, int(map.h) - 1):
		for x in range(1, int(map.w) - 1):
			if line.is_empty() and _line_from(map, Vector2i(x, y), Vector2i(1, 0), 3):
				line = {"from": Vector2i(x, y)}
	if line.is_empty():
		_fail(lane, "no 3 m open line for the sleeper")
		return
	_place(world, player, _centre(line["from"]))
	var sleeper: int = _spawn(world, _centre((line["from"] as Vector2i) + Vector2i(3, 0)), SimRoster.TYPE_SHAMBLER)
	SimShambler.make_dormant(world, sleeper)
	var wanderer: int = -1
	var spot: Vector2i = _far_open_tile(map, _pos(world, player))
	if spot != Vector2i(1, 1):
		wanderer = _spawn(world, _centre(spot), SimRoster.TYPE_SHAMBLER)
	var h: Control = _hud_for(world, player)
	var seen: Array[String] = []
	for _t in range(60):
		world.step()
		for l in _tell_lines(h.call("lines")):
			seen.append(l)
	_all_lines.append_array([])
	if not seen.is_empty():
		_fail(lane, "a sleeping shambler at 3 m and a wandering one at 30 m drew a tell over 60 ticks: %s" % str(seen))
		return
	_ok(lane, "a sleeping shambler at 3 m and a %s one %s m away drew no tell over 60 ticks" % ["wandering" if wanderer >= 0 else "(no far tile; only the sleeper)", "40+" if wanderer >= 0 else "-"])


# --- NOTICED ---------------------------------------------------------------------------------------

func _noticed() -> void:
	var lane: String = "NOTICED"
	var b: Dictionary = _boot()
	var world: Variant = b["world"]
	var map: Variant = b["map"]
	var player: int = int(world.player)
	var setup: Dictionary = _placement(world, map, Vector2i(1, 0), AHEAD_METRES, SimRoster.TYPE_SHAMBLER)
	if setup.is_empty():
		_fail(lane, "no %d m open line ahead with sight" % AHEAD_METRES)
		return
	var zed: int = int(setup["zed"])
	var h: Control = _hud_for(world, player)
	var noticed_at: int = _until_noticed(world, zed)
	if noticed_at < 0:
		_fail(lane, "the shambler %d m ahead did not notice the player in %d ticks" % [AHEAD_METRES, WAIT_TICKS])
		return
	var line: String = _notice_of(h.call("lines"))
	if line != Hud.NOTICE_LINES["ahead"]:
		_fail(lane, "the notice is not drawn as ahead; drawn: \"%s\"" % line)
		return
	while int(world.tick) - noticed_at < NOTICE_WINDOW - 1:
		world.step()
	if _notice_of(h.call("lines")) == "":
		_fail(lane, "the notice line left at +%d, before the 3 s window closed" % (int(world.tick) - noticed_at))
		return
	world.step()
	if _notice_of(h.call("lines")) != "":
		_fail(lane, "the notice line is still drawn at +%d, past the 3 s window" % (int(world.tick) - noticed_at))
		return
	_ok(lane, "noticed at tick +%d, %d m ahead: \"%s\" drawn; still at +%d, gone at +%d (the 3 s window)" % [noticed_at - setup["base"] if false else noticed_at, AHEAD_METRES, Hud.NOTICE_LINES["ahead"], NOTICE_WINDOW - 1, NOTICE_WINDOW])


# --- SIDE ------------------------------------------------------------------------------------------

func _side() -> void:
	var lane: String = "SIDE"
	var cases: Array = [
		{"dir": Vector2i(1, 0), "sector": "ahead"},
		{"dir": Vector2i(0, 1), "sector": "right"},
		{"dir": Vector2i(0, -1), "sector": "left"},
		{"dir": Vector2i(-1, 0), "sector": "behind"},
	]
	var drawn: Array[String] = []
	for c in cases:
		var b: Dictionary = _boot()
		var world: Variant = b["world"]
		var map: Variant = b["map"]
		var player: int = int(world.player)
		var setup: Dictionary = _placement(world, map, c["dir"], AHEAD_METRES, SimRoster.TYPE_SHAMBLER)
		if setup.is_empty():
			_fail(lane, "no %d m open line %s with sight" % [AHEAD_METRES, String(c["sector"])])
			return
		var zed: int = int(setup["zed"])
		var h: Control = _hud_for(world, player)
		if _until_noticed(world, zed) < 0:
			_fail(lane, "no notice from the %s side in %d ticks" % [String(c["sector"]), WAIT_TICKS])
			return
		var line: String = _notice_of(h.call("lines"))
		var want: String = String(Hud.NOTICE_LINES[String(c["sector"])])
		if line != want:
			_fail(lane, "the %s notice is drawn as \"%s\", wanted \"%s\"" % [String(c["sector"]), line, want])
			return
		drawn.append(line)
	_ok(lane, "the notice reads %d ways from a look east: %s" % [drawn.size(), str(drawn)])


# --- CLOSE -----------------------------------------------------------------------------------------

func _close() -> void:
	var lane: String = "CLOSE"
	# Behind, Pursuing at 4 m: the close line.
	var b: Dictionary = _boot()
	var world: Variant = b["world"]
	var map: Variant = b["map"]
	var player: int = int(world.player)
	var behind: Dictionary = _placement(world, map, Vector2i(-1, 0), CLOSE_METRES, SimRoster.TYPE_SHAMBLER)
	if behind.is_empty():
		_fail(lane, "no %d m open line behind with sight" % CLOSE_METRES)
		return
	var zed: int = int(behind["zed"])
	(world.components.get_component(zed, "shambler") as Dictionary)["state"] = SimShambler.ShamblerState["Pursue"]
	var h: Control = _hud_for(world, player)
	var tells: Array[String] = _tell_lines(h.call("lines"))
	if not tells.has(Hud.CLOSE_LINES["behind"]):
		_fail(lane, "a Pursuing shambler 4 m behind draws no close line; drawn: %s" % str(tells))
		return
	# In front, Pursuing at 4 m: no close line (the look covers it).
	world.despawn(zed)
	var front: Dictionary = _placement(world, map, Vector2i(1, 0), CLOSE_METRES, SimRoster.TYPE_SHAMBLER)
	if front.is_empty():
		_fail(lane, "no %d m open line ahead with sight" % CLOSE_METRES)
		return
	var zed2: int = int(front["zed"])
	(world.components.get_component(zed2, "shambler") as Dictionary)["state"] = SimShambler.ShamblerState["Pursue"]
	tells = _tell_lines(h.call("lines"))
	for t in tells:
		if Hud.CLOSE_LINES.values().has(String(t)):
			_fail(lane, "a Pursuing shambler 4 m ahead, inside the look, draws a close line: %s" % str(tells))
			return
	_ok(lane, "Pursuing 4 m behind: \"%s\"; Pursuing 4 m ahead: no tell" % Hud.CLOSE_LINES["behind"])


# --- SEVERAL ---------------------------------------------------------------------------------------

func _several() -> void:
	var lane: String = "SEVERAL"
	var b: Dictionary = _boot()
	var world: Variant = b["world"]
	var map: Variant = b["map"]
	var player: int = int(world.player)
	var dirs: Array = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var from: Vector2i = Vector2i(-1, -1)
	for y in range(1, int(map.h) - 1):
		for x in range(1, int(map.w) - 1):
			var ok: bool = true
			for d in dirs:
				if not _line_from(map, Vector2i(x, y), d, AHEAD_METRES):
					ok = false
					break
			if ok:
				from = Vector2i(x, y)
				break
		if from.x >= 0:
			break
	if from.x < 0:
		_fail(lane, "no tile with %d m open lines ahead, left and right" % AHEAD_METRES)
		return
	_place(world, player, _centre(from))
	var zeds: Array = []
	for d in dirs:
		zeds.append(_spawn(world, _centre(from + d * AHEAD_METRES), SimRoster.TYPE_SHAMBLER))
	var h: Control = _hud_for(world, player)
	for _t in range(WAIT_TICKS):
		var all: bool = true
		for z in zeds:
			if not _notices.has(int(z)):
				all = false
		if all:
			break
		world.step()
	var heard: int = 0
	for z in zeds:
		if _notices.has(int(z)):
			heard += 1
	if heard < zeds.size():
		_fail(lane, "only %d of %d shamblers noticed in %d ticks" % [heard, zeds.size(), WAIT_TICKS])
		return
	# The three noticed on their own schedules, and a notice is only fresh for NOTICE_WINDOW ticks, so their spread
	# can be longer than the window. The lane puts all three in one window: noticedAt is set to now on each, the
	# field shambler.gd's _notice writes. A fixture write, stated in the lane's line.
	for z in zeds:
		(world.components.get_component(int(z), "shambler") as Dictionary)["noticedAt"] = int(world.tick)
	var tells: Array[String] = _tell_lines(h.call("lines"))
	if not tells.has(Hud.SEVERAL_STIR_LINE):
		_fail(lane, "three noticers draw no several line; drawn: %s" % str(tells))
		return
	if _notice_of(h.call("lines")) != "":
		_fail(lane, "three noticers draw a single-direction notice as well: %s" % str(tells))
		return
	_ok(lane, "three shamblers %d m away (ahead, left, right) in one notice window (noticedAt set to now): \"%s\" drawn, no single-direction line" % [AHEAD_METRES, Hud.SEVERAL_STIR_LINE])


# --- SCREAM ----------------------------------------------------------------------------------------

func _scream() -> void:
	var lane: String = "SCREAM"
	var b: Dictionary = _boot()
	var world: Variant = b["world"]
	var map: Variant = b["map"]
	var player: int = int(world.player)
	var setup: Dictionary = _placement(world, map, Vector2i(1, 0), SCREAM_METRES, SimRoster.TYPE_SCREAMER)
	if setup.is_empty():
		_fail(lane, "no %d m open line with sight to a screamer" % SCREAM_METRES)
		return
	var zed: int = int(setup["zed"])
	if not world.components.has_component(zed, "alarm"):
		_fail(lane, "the screamer has no alarm component to read its scream from")
		return
	var h: Control = _hud_for(world, player)
	var at: int = -1
	for _t in range(WAIT_TICKS):
		if _screams.has(zed):
			at = int(_screams[zed])
			break
		world.step()
	if at < 0:
		_fail(lane, "the screamer did not scream in %d ticks" % WAIT_TICKS)
		return
	# The scream happens in the tick it is logged: step to the window's edge from there.
	while int(world.tick) - at < SCREAM_WINDOW:
		world.step()
	if not _tell_lines(h.call("lines")).has(Hud.SCREAM_LINE):
		_fail(lane, "the scream line is gone at +%d, inside its window" % (int(world.tick) - at))
		return
	world.step()
	if _tell_lines(h.call("lines")).has(Hud.SCREAM_LINE):
		_fail(lane, "the scream line is still drawn at +%d, past its window" % (int(world.tick) - at))
		return
	_ok(lane, "screamed at tick %d, %d m away: \"%s\" drawn to +%d, gone at +%d" % [at, SCREAM_METRES, Hud.SCREAM_LINE, SCREAM_WINDOW, SCREAM_WINDOW + 1])


# --- DIGITS ----------------------------------------------------------------------------------------

func _digits() -> void:
	var bad: String = ""
	for line in _all_lines:
		if Hud.has_digit(line):
			bad = line
			break
	if bad != "":
		_fail("DIGITS", "a drawn line has a digit: %s" % bad)
		return
	_ok("DIGITS", "%d drawn lines across every lane, none with a digit" % _all_lines.size())
