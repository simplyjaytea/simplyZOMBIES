extends SceneTree
# The look sheet's driver (docs/46): the first-person scene photographed, or timed, from fixed stations at fixed
# hours, so a change to the look is judged by before and after pictures made the same way.
#
# The district is the shipped boot district, the sim is paused, and every station is computed from the map, so
# two runs of one build give the same pictures (0 pixels apart) and two builds compare station by station.
# Needs a display: the pixels come from the root viewport.
#
#   xvfb-run -a npm run godot:shots:look -- --out=<dir> [--times=noon,dusk,night] [--weather=<kind>] [--stations=a,b]
#   xvfb-run -a npm run godot:frames:look -- --out=<dir> [--times=noon] [--stations=a,b] [--measure=200]
#
#   --times     any of dawn, morning, noon, afternoon, dusk, night (default noon,dusk,night)
#   --weather   a sim weather kind (clear, rain, storm, fog, snow, cold_snap, heat_wave); default: the boot
#               weather, untouched
#   --stations  a subset of station names (default: all); the names are printed as LOOK station lines
#   --measure=N instead of pictures, time N frames at each station (after 20 to settle) and print
#               LOOK_FRAME <time> <station> render_cpu_ms render_gpu_ms wall_* draw_calls primitives.
#               render_cpu_ms + render_gpu_ms is the frame's draw cost (the viewport's measured render time);
#               the wall figures include presenting to the virtual display, which dominates under xvfb.
#
# Pictures land in <out>/<time>_<station>.png with <out>/stations.json beside them. `tools/look/look_sheet.py`
# lays them out: one labelled sheet, before | after pairs, or a pixel diff of two folders.
#
# The only writes to the sim are `world.tick` and `SimWeather.set_kind`, the way `review/scenes.gd` sets a scene
# up before a shot. The scene is paused before it enters the tree, so no tick is ever stepped; that is also why
# the `eye_boot` picture carries the HUD's two paused lines, which a player does not see at boot.
#
# This is a review tool with no gate of its own, so it refuses rather than guesses: a wrong argument (a time, a
# station or a weather kind it does not know, a missing --out) ends the run with LOOK_FAIL and a non-zero exit,
# and a station that cannot be placed on this map is left out and printed as `LOOK skipped`, never photographed
# from somewhere else.

const SCENE: String = "res://presentation/first_person/first_person.tscn"
const Clock = preload("res://sim/time/clock.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimWeather = preload("res://sim/modules/weather.gd")

const EYE: float = 1.62
const TIME_FRACTIONS: Dictionary = {
	"dawn": 0.06, "morning": 0.20, "noon": 0.375, "afternoon": 0.55, "dusk": 0.70, "night": 0.90,
}
const BUILDING_IDS: Array[String] = [
	"building.house.gable", "building.house.large", "building.shrine.village", "building.clinic.storefront",
	"building.kiosk.corner", "building.gatehouse.yard", "building.terrace.pair", "building.shed.garage",
]
const SETTLE_FRAMES: int = 4
# "No tile": what the placing helpers return when the map has no place that fits.
const NONE: Vector2i = Vector2i(-1, -1)

var _scene: Node = null
var _frame: int = 0
var _out: String = ""
var _times: Array[String] = ["noon", "dusk", "night"]
var _weather: String = ""
var _only: Array[String] = []
var _stations: Array = []
var _queue: Array = []
var _i: int = 0
var _settle: int = 0
var _failed: bool = false
var _measure: int = 0
var _samples: PackedFloat64Array = PackedFloat64Array()
var _last_usec: int = 0
var _adapter_said: bool = false
var _cpu_ms: float = 0.0
var _gpu_ms: float = 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--times="):
			_times.clear()
			for t in a.substr(8).split(",", false):
				_times.append(String(t))
		elif a.begins_with("--weather="):
			_weather = a.substr(10)
		elif a.begins_with("--measure="):
			_measure = int(a.substr(10))
			if _measure <= 0:
				_fail("--measure wants a frame count above zero, not '%s'" % a.substr(10))
				return
		elif a.begins_with("--stations="):
			for s in a.substr(11).split(",", false):
				_only.append(String(s))
	if _out == "":
		_fail("--out=<dir> is required")
		return
	for t in _times:
		if not TIME_FRACTIONS.has(t):
			_fail("unknown time '%s'; the times are %s" % [t, ", ".join(TIME_FRACTIONS.keys())])
			return
	DirAccess.make_dir_recursive_absolute(_out)
	var packed: PackedScene = load(SCENE) as PackedScene
	_scene = packed.instantiate()
	_scene.set("skip_title", true)
	# Paused before the first frame: the scene draws and reads the sim, and never steps it.
	_scene.set("paused", true)
	root.add_child(_scene)


func _fail(message: String) -> void:
	push_error("LOOK_FAIL: " + message)
	_failed = true


func _open(map: Variant, tx: int, ty: int) -> bool:
	if tx < 1 or ty < 1 or tx >= int(map.w) - 1 or ty >= int(map.h) - 1:
		return false
	return not SimTileMap.is_solid(map, tx, ty) and not SimTileMap.is_indoors(map, tx, ty)


# The nearest outdoor, walkable tile to (x, y), by rings; NONE when there is none within 16.
func _open_near(map: Variant, x: int, y: int) -> Vector2i:
	for r in range(0, 16):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				if _open(map, x + dx, y + dy):
					return Vector2i(x + dx, y + dy)
	return NONE


# True when no solid tile stands on the line from a to b, ignoring the last `slack` metres before b.
func _clear(map: Variant, a: Vector2, b: Vector2, slack: float) -> bool:
	var d: Vector2 = b - a
	var n: int = maxi(2, int(d.length() / 0.4))
	for i in range(1, n):
		var p: Vector2 = a + d * (float(i) / float(n))
		if (b - p).length() < slack:
			break
		if SimTileMap.tile_at(map, int(floor(p.x)), int(floor(p.y))) != SimTileMap.Tile.Floor:
			return false
	return true


# An outdoor tile about `dist` metres from `target` with a clear line to it, tried around the circle
# starting at `prefer` (radians, sim axes: 0 is east, PI/2 is south) and fanning out both ways, then a
# little nearer and a little farther. NONE when no tile has the line: the station is then left out.
func _vantage(map: Variant, target: Vector2, dist: float, prefer: float, slack: float) -> Vector2i:
	for scale: float in [1.0, 0.8, 1.25]:
		for k in range(0, 17):
			var step: int = (k + 1) / 2
			if k % 2 == 0:
				step = -step
			var ang: float = prefer + float(step) * (PI / 8.0)
			var c: Vector2 = target + Vector2(cos(ang), sin(ang)) * dist * scale
			var t: Vector2i = Vector2i(int(floor(c.x)), int(floor(c.y)))
			if _open(map, t.x, t.y) and _clear(map, Vector2(t.x + 0.5, t.y + 0.5), target, slack):
				return t
	return NONE


# A station the map has no place for: said, and left out.
func _skipped(station: String, why: String) -> void:
	print("LOOK skipped %s: %s" % [station, why])


# Adds a station that stands on `tile` (NONE: left out) and looks at `at`.
func _add_on(station: String, tile: Vector2i, at: Vector3, why: String) -> void:
	if tile == NONE:
		_skipped(station, why)
		return
	_add(station, Vector3(tile.x + 0.5, EYE, tile.y + 0.5), at)


func _look(from: Vector3, at: Vector3) -> Vector2:
	var d: Vector3 = at - from
	return Vector2(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))


func _add(station: String, from: Vector3, at: Vector3) -> void:
	var l: Vector2 = _look(from, at)
	_stations.append({"name": station, "pos": from, "yaw": l.x, "pitch": l.y})


func _plan() -> void:
	var world: Variant = _scene.get("world")
	var map: Variant = _scene.get("map")
	var pos: Dictionary = world.components.get_component(int(world.player), "position") as Dictionary
	var px: int = int(float(pos["x"]))
	var py: int = int(float(pos["y"]))
	var w: int = int(map.w)
	var h: int = int(map.h)

	# 1. The real eye: arms, held item and HUD, exactly as a player boots.
	_stations.append({"name": "eye_boot", "eye": true})

	# 2. The starting building, from inside and from outside.
	var annex: Rect2i = SimTileMap.annex_rect(map)
	print("LOOK annex ", annex, " player ", px, ",", py)
	if annex.size.x > 0:
		var ac: Vector2 = Vector2(annex.position.x + annex.size.x * 0.5, annex.position.y + annex.size.y * 0.5)
		var far_corner: Vector2 = Vector2(annex.position.x + 1.0, annex.position.y + 1.0)
		if Vector2(px, py).distance_to(far_corner) < Vector2(px, py).distance_to(Vector2(annex.end.x - 1.0, annex.end.y - 1.0)):
			far_corner = Vector2(annex.end.x - 1.0, annex.end.y - 1.0)
		var back: Vector2 = (Vector2(px + 0.5, py + 0.5) - far_corner).normalized() * 2.5
		var behind: Vector2 = Vector2(px + 0.5, py + 0.5) + back
		if SimTileMap.is_solid(map, int(floor(behind.x)), int(floor(behind.y))):
			_skipped("annex_in", "the tile behind the start is solid")
		else:
			_add("annex_in", Vector3(behind.x, EYE, behind.y), Vector3(far_corner.x, 1.4, far_corner.y))
		var inside: Vector2 = far_corner.lerp(ac, 0.35)
		if SimTileMap.is_solid(map, int(floor(inside.x)), int(floor(inside.y))):
			_skipped("annex_in_b", "the tile inside the far corner is solid")
		else:
			_add("annex_in_b", Vector3(inside.x, EYE, inside.y), Vector3(px + 0.5, 1.2, py + 0.5))
		var o: Vector2i = _vantage(map, ac, float(maxi(annex.size.x, annex.size.y)) * 0.5 + 12.0, PI * 0.75, float(maxi(annex.size.x, annex.size.y)) * 0.75)
		_add_on("annex_out", o, Vector3(ac.x, 1.8, ac.y), "no outdoor tile has a clear line to the start building")

	# 3. Kit buildings: the nearest record of each id, three-quarter from the door side.
	var best: Dictionary = {}
	for rec_v in map.buildings as Array:
		var rec: Dictionary = rec_v as Dictionary
		var id: String = String(rec.get("id", ""))
		var d: float = Vector2(float(rec["x"]) + float(rec["w"]) * 0.5 - px, float(rec["y"]) + float(rec["h"]) * 0.5 - py).length()
		if not best.has(id) or d < float((best[id] as Dictionary)["d"]):
			best[id] = {"rec": rec, "d": d}
	for id in BUILDING_IDS:
		if not best.has(id):
			continue
		var rec: Dictionary = (best[id] as Dictionary)["rec"] as Dictionary
		var x: int = int(rec["x"])
		var y: int = int(rec["y"])
		var bw: int = int(rec["w"])
		var bh: int = int(rec["h"])
		var door: Vector2i = Vector2i(x + bw / 2, y + bh - 1)
		var doors: Array = rec.get("doors", []) as Array
		if doors.size() > 0:
			door = Vector2i(int((doors[0] as Dictionary)["x"]), int((doors[0] as Dictionary)["y"]))
		var out: Vector2i = Vector2i(0, 1)
		if door.y <= y:
			out = Vector2i(0, -1)
		elif door.x <= x:
			out = Vector2i(-1, 0)
		elif door.x >= x + bw - 1:
			out = Vector2i(1, 0)
		var bc: Vector2 = Vector2(x + bw * 0.5, y + bh * 0.5)
		var prefer: float = atan2(float(out.y), float(out.x)) + PI / 7.0
		var reach: float = float(maxi(bw, bh)) * 0.5
		var t: Vector2i = _vantage(map, bc, reach + 10.0, prefer, reach + 2.0)
		_add_on("b_" + id.replace("building.", "").replace(".", "_"), t, Vector3(bc.x, 1.9, bc.y), "no outdoor tile has a clear line to it")

	# 4. A long street vista: the carved street nearest the start, looked down from one end.
	var street: Dictionary = {}
	var street_d: float = 1.0e9
	for s_v in map.streets as Array:
		var s: Dictionary = s_v as Dictionary
		var mid: float = float(s["at"]) + float(s["width"]) * 0.5
		var d2: float = absf(mid - (float(px) if String(s["axis"]) == "x" else float(py)))
		if d2 < street_d and d2 > 6.0:
			street_d = d2
			street = s
	if not street.is_empty():
		var mid2: float = float(street["at"]) + float(street["width"]) * 0.5
		if String(street["axis"]) == "x":
			var a: Vector2i = _open_near(map, int(mid2), int(street["from"]) + 6)
			_add_on("street_long", a, Vector3(a.x + 0.5, EYE, a.y + 80.0), "no open tile at the street's end")
			var b: Vector2i = _open_near(map, int(mid2), py)
			_add_on("street_mid", b, Vector3(b.x + 6.0, EYE, b.y - 40.0), "no open tile on the street beside the start")
		else:
			var a2: Vector2i = _open_near(map, int(street["from"]) + 6, int(mid2))
			_add_on("street_long", a2, Vector3(a2.x + 80.0, EYE, a2.y + 0.5), "no open tile at the street's end")
			var b2: Vector2i = _open_near(map, px, int(mid2))
			_add_on("street_mid", b2, Vector3(b2.x - 40.0, EYE, b2.y + 6.0), "no open tile on the street beside the start")
	else:
		_skipped("street_long", "the map carries no street clear of the start")
		_skipped("street_mid", "the map carries no street clear of the start")

	# 5. Green: the nearest tree tile, from seven metres.
	var tree: Vector2i = Vector2i(-1, -1)
	for r in range(2, 90):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var tx: int = px + dx
				var ty: int = py + dy
				if tx < 1 or ty < 1 or tx >= w - 1 or ty >= h - 1:
					continue
				if SimTileMap.tile_at(map, tx, ty) == SimTileMap.Tile.Tree:
					tree = Vector2i(tx, ty)
					break
			if tree.x >= 0:
				break
		if tree.x >= 0:
			break
	if tree.x >= 0:
		var tc: Vector2 = Vector2(tree.x + 0.5, tree.y + 0.5)
		var g: Vector2i = _vantage(map, tc, 8.0, PI * 0.5, 1.0)
		_add_on("green", g, Vector3(tc.x, 1.8, tc.y), "no outdoor tile has a clear line to the nearest tree")
	else:
		_skipped("green", "no tree tile within ninety metres of the start")

	# 6. The edge of the district, looking out: what stands beyond the map.
	var en: Vector2i = _open_near(map, w / 2, 26)
	_add_on("edge_north", en, Vector3(en.x + 0.5, EYE + 8.0, en.y - 80.0), "no open tile near the north edge")
	var ee: Vector2i = _open_near(map, w - 27, h / 2)
	_add_on("edge_east", ee, Vector3(ee.x + 80.0, EYE + 8.0, ee.y + 0.5), "no open tile near the east edge")

	# 7. From above: the neighbourhood and the whole district.
	_stations.append({"name": "overview", "pos": Vector3(px + 0.5, 22.0, py + 18.0), "yaw": 0.0, "pitch": -0.85})
	_stations.append({"name": "far", "pos": Vector3(w * 0.5, 150.0, h * 0.5 + 130.0), "yaw": 0.0, "pitch": -0.85})

	if not _only.is_empty():
		var known: Array[String] = []
		for st_v in _stations:
			known.append(String((st_v as Dictionary)["name"]))
		for wanted in _only:
			if not known.has(wanted):
				_fail("no station '%s' on this map; the stations are %s" % [wanted, ", ".join(known)])
				return
		var kept: Array = []
		for st_v in _stations:
			if _only.has(String((st_v as Dictionary)["name"])):
				kept.append(st_v)
		_stations = kept
	if _weather != "" and not SimWeather.kinds(world).has(_weather):
		_fail("the sim has no weather kind '%s'; the kinds are %s" % [_weather, ", ".join(SimWeather.kinds(world))])
		return
	var record: Array = []
	for st_v in _stations:
		var st: Dictionary = st_v as Dictionary
		print("LOOK station ", st["name"])
		var row: Dictionary = {"name": st["name"]}
		if st.has("pos"):
			var p: Vector3 = st["pos"] as Vector3
			row["pos"] = [p.x, p.y, p.z]
			row["yaw"] = st["yaw"]
			row["pitch"] = st["pitch"]
		record.append(row)
	var f: FileAccess = FileAccess.open(_out.path_join("stations.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"times": _times, "weather": _weather, "stations": record}, "\t"))
		f.close()
	for t in _times:
		for st_v in _stations:
			_queue.append({"time": t, "station": st_v})
	print("LOOK %s %d" % ["timings" if _measure > 0 else "shots", _queue.size()])


func _process(_delta: float) -> bool:
	if _failed:
		quit(1)
		return true
	_frame += 1
	if _frame < 8:
		return false
	if _frame == 8:
		_plan()
		return false
	if _i >= _queue.size():
		if _measure > 0:
			print("LOOK_DONE %d stations timed" % _queue.size())
		else:
			print("LOOK_DONE %d pictures in %s" % [_queue.size(), _out])
		return true
	var shot: Dictionary = _queue[_i] as Dictionary
	var st: Dictionary = shot["station"] as Dictionary
	if _settle == 0:
		var world: Variant = _scene.get("world")
		var day: int = int(world.tick) / Clock.DAY_TICKS
		world.tick = day * Clock.DAY_TICKS + int(float(Clock.DAY_TICKS) * float(TIME_FRACTIONS[String(shot["time"])]))
		if _weather != "":
			SimWeather.set_kind(world, _weather, int(world.tick) + Clock.DAY_TICKS * 4)
		if bool(st.get("eye", false)):
			if bool(_scene.get("review_camera")):
				_scene.call("toggle_review_camera")
		else:
			_scene.call("set_review_camera", st["pos"] as Vector3, float(st["yaw"]), float(st["pitch"]))
	_settle += 1
	if _measure > 0:
		return _measure_frame(shot, st)
	if _settle < SETTLE_FRAMES:
		return false
	var image: Image = root.get_texture().get_image()
	image.save_png(_out.path_join("%s_%s.png" % [String(shot["time"]), String(st["name"])]))
	_i += 1
	_settle = 0
	return false


# One frame of the timing mode: twenty frames to settle, then `_measure` wall-clock frame deltas.
func _measure_frame(shot: Dictionary, st: Dictionary) -> bool:
	if not _adapter_said:
		_adapter_said = true
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
		print("LOOK_ADAPTER ", RenderingServer.get_video_adapter_name(), " / ", RenderingServer.get_video_adapter_vendor())
	var now: int = Time.get_ticks_usec()
	if _settle <= 20:
		_last_usec = now
		_samples.clear()
		_cpu_ms = 0.0
		_gpu_ms = 0.0
		return false
	_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()) + RenderingServer.get_frame_setup_time_cpu()
	_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
	_samples.append(float(now - _last_usec) / 1000.0)
	_last_usec = now
	if _samples.size() < _measure:
		return false
	var sorted: PackedFloat64Array = _samples.duplicate()
	sorted.sort()
	var total: float = 0.0
	for v in _samples:
		total += v
	var mean: float = total / float(_samples.size())
	var p95: float = sorted[int(float(sorted.size() - 1) * 0.95)]
	var median: float = sorted[sorted.size() / 2]
	print("LOOK_FRAME %s %s render_cpu_ms=%.3f render_gpu_ms=%.3f wall_mean_ms=%.3f wall_median_ms=%.3f wall_p95_ms=%.3f draw_calls=%d primitives=%d" % [
		String(shot["time"]), String(st["name"]), _cpu_ms / float(_samples.size()), _gpu_ms / float(_samples.size()), mean, median, p95,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])
	_i += 1
	_settle = 0
	return false
