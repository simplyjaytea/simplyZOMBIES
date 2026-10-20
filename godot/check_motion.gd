extends SceneTree
# Motion between ticks: render interpolation and the clamped tick accumulator
# (presentation/interp.gd, main.gd's `_process` and `_draw_entities`).
#
# The sim steps at 20 Hz. Drawn straight off the position component, a walking body holds still
# for a tick and then jumps a tick's worth of street at once, however many frames come in between
# -- at 60 frames a second that is two frames standing and one frame leaping, which is what "the
# bodies stutter" was. This gate boots the shipped scene, walks the player with the sim's own
# `move` command, drives the real frame loop with chosen deltas, lets the engine run the real
# draw, and reads back where the body was *drawn* (`_focal_drawn`, the list the draw writes for
# the speech bubbles) and where the camera stood.
#
# Lanes, each with its true positive and its true negative:
#   HELPERS  between() is on `prev` at 0, on `cur` at 1 and strictly between them at 0.5, a jump
#            past SNAP_METRES draws on `cur`; turn_between() turns the short way across +-pi;
#            fraction() and clamp_debt() clamp, and a debt under the cap is left exactly alone.
#   CLAMP    a ten-second frame runs the per-frame cap and *drops* the rest (accumulator under one
#            tick), so the next half-tick frame runs nothing -- the old loop carried the debt and
#            ran the cap again; and an ordinary 75 ms frame runs one tick and keeps its 25 ms.
#   DRAWN    a frame that ends exactly on a tick draws the walking body on the *previous* tick's
#            point, not the current one (fraction 0); a half-tick frame after it draws the body
#            strictly between the two ticks on the line joining them.
#   SMOOTH   the measurement: per-frame apparent speed of the drawn body and of the camera, at a
#            steady 60 Hz and at a jittered ~10 fps, against the same numbers for the raw sim
#            point and a camera that follows it (which is what shipped before). Interpolated must
#            be smooth (coefficient of variation under SMOOTH_CV) and the raw must not be -- the
#            negative proves the measure can see a stutter at all.
#   READERS  the frame loop snapshots before every step, the camera follows the interpolated
#            point, a ridden or driven vehicle slides with its entity: the textual half, for the
#            branches this boot does not drive.

const SCENE_PATH: String = "res://presentation/main.tscn"
const MAIN_GD: String = "res://presentation/main.gd"
const RenderInterp = preload("res://presentation/interp.gd")
const TopDownProjection = preload("res://presentation/projection.gd")
const CameraUtil = preload("res://presentation/camera.gd")
const Session = preload("res://presentation/session.gd")

# main.gd's tick, named again so the gate is not quoting the thing it judges.
const TICK_SECONDS: float = 1.0 / 20.0
const EPS: float = 0.0001
# Coefficient of variation (stdev / mean) of per-frame apparent speed. A steady walk drawn
# interpolated sits near zero; drawn on the tick it is ~1.4 at 60 Hz (two still frames, one leap).
const SMOOTH_CV: float = 0.15
const RAW_CV_FLOOR: float = 0.5
# The camera is already a smoothed follow, so a stepping target shows up as a smaller wobble on
# it: 0.036 / 0.051 following the drawn point, 0.104 / 0.109 with the interpolation sabotaged
# (offset() returning zero) on 2026-10-19. The frame schedules are fixed and seeded, so these
# are the same numbers on every run.
const CAM_CV: float = 0.075
# Frames measured after the walk is up to speed.
const WARM_FRAMES: int = 12
const STEADY_FRAMES: int = 60
const JITTER_FRAMES: int = 24
# Fewer measured frames than this and a window says so and skips rather than judging noise.
const MIN_FRAMES: int = 12

var _skips: Array = []
var _report: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _helpers() and ok
	ok = _readers() and ok
	var main: Node = await _boot()
	if main == null:
		push_error("MOTION_FAIL the scene did not boot")
		quit(1)
		return
	ok = _clamp(main) and ok
	var drawn_ok: bool = await _drawn(main)
	ok = drawn_ok and ok
	var smooth_ok: bool = await _smooth(main)
	ok = smooth_ok and ok
	main.queue_free()
	await process_frame
	if ok:
		var skipped: String = "no lane skipped" if _skips.is_empty() else "skipped: %s" % ", ".join(PackedStringArray(_skips))
		print("MOTION_OK bodies draw between ticks (on the previous tick at fraction 0, strictly between at 0.5), the camera follows the drawn point, a slow frame drops its debt instead of carrying it; %s (%s)" % ["; ".join(PackedStringArray(_report)), skipped])
		quit(0)
	else:
		push_error("MOTION_FAIL")
		quit(1)


func _skip(lane: String, why: String) -> bool:
	print("%s SKIP %s" % [lane, why])
	_skips.append("%s (%s)" % [lane, why])
	return true


# --- HELPERS ----------------------------------------------------------------------------------

func _helpers() -> bool:
	var a := Vector2(10.0, 20.0)
	var b := Vector2(10.3, 19.6)
	var at0: Vector2 = RenderInterp.between(a, b, 0.0)
	var at1: Vector2 = RenderInterp.between(a, b, 1.0)
	var mid: Vector2 = RenderInterp.between(a, b, 0.5)
	if not at0.is_equal_approx(a) or at0.is_equal_approx(b):
		push_error("HELPERS: between(t=0) is %s, not the previous point %s" % [at0, a])
		return false
	if not at1.is_equal_approx(b):
		push_error("HELPERS: between(t=1) is %s, not the current point %s" % [at1, b])
		return false
	if not _strictly_between(mid, a, b):
		push_error("HELPERS: between(t=0.5) is %s, not strictly between %s and %s" % [mid, a, b])
		return false
	var far := Vector2(10.0 + RenderInterp.SNAP_METRES + 1.0, 20.0)
	var near := Vector2(10.0 + RenderInterp.SNAP_METRES - 1.0, 20.0)
	if not RenderInterp.between(a, far, 0.5).is_equal_approx(far):
		push_error("HELPERS: a jump past SNAP_METRES glided instead of snapping")
		return false
	if RenderInterp.between(a, near, 0.5).is_equal_approx(near):
		push_error("HELPERS: a step under SNAP_METRES snapped instead of gliding")
		return false
	# Across the seam: 3.0 rad to -3.0 rad is 0.28 rad the short way; the long way passes 0.
	var turned: float = RenderInterp.turn_between(3.0, -3.0, 0.5)
	if absf(absf(turned) - PI) > 0.01:
		push_error("HELPERS: turn_between(3.0, -3.0, 0.5) = %.3f, the long way round" % turned)
		return false
	if not is_equal_approx(RenderInterp.turn_between(0.0, 1.0, 0.5), 0.5):
		push_error("HELPERS: turn_between(0, 1, 0.5) is not 0.5")
		return false
	if not is_equal_approx(RenderInterp.turn_between(NAN, 1.0, 0.25), 1.0):
		push_error("HELPERS: no previous facing should draw the current one")
		return false
	if RenderInterp.fraction(0.2, TICK_SECONDS) != 1.0 or RenderInterp.fraction(-1.0, TICK_SECONDS) != 0.0 or not is_equal_approx(RenderInterp.fraction(0.025, TICK_SECONDS), 0.5):
		push_error("HELPERS: fraction() does not clamp to 0..1 or misreads a half tick")
		return false
	var capped: float = RenderInterp.clamp_debt(10.0, TICK_SECONDS, 5)
	var kept: float = RenderInterp.clamp_debt(0.12, TICK_SECONDS, 5)
	if not is_equal_approx(capped, 0.25) or not is_equal_approx(kept, 0.12):
		push_error("HELPERS: clamp_debt(10 s) = %.3f (want 0.25), clamp_debt(0.12 s) = %.3f (want it untouched)" % [capped, kept])
		return false
	print("HELPERS OK between() on prev at 0, cur at 1, strictly between at 0.5, snaps past %.1f m and glides under it; turns the short way; fraction and clamp_debt clamp and leave a small debt alone" % RenderInterp.SNAP_METRES)
	return true


func _strictly_between(p: Vector2, a: Vector2, b: Vector2) -> bool:
	var ab: Vector2 = b - a
	if ab.length_squared() < EPS * EPS:
		return false
	var t: float = (p - a).dot(ab) / ab.length_squared()
	var off_line: float = (p - (a + ab * t)).length()
	return t > EPS and t < 1.0 - EPS and off_line < EPS


# --- READERS ----------------------------------------------------------------------------------

func _readers() -> bool:
	var proc: String = _function_body(MAIN_GD, "_process")
	var cam: String = _function_body(MAIN_GD, "_update_camera")
	var ents: String = _function_body(MAIN_GD, "_draw_entities")
	if proc.is_empty() or cam.is_empty() or ents.is_empty():
		push_error("READERS: could not read _process, _update_camera or _draw_entities out of %s -- nothing to judge" % MAIN_GD)
		return false
	var snap_at: int = proc.find("_interp.before_step(world)")
	var step_at: int = proc.find("world.step()")
	if snap_at < 0 or step_at < 0 or snap_at > step_at:
		push_error("READERS: _process does not snapshot (_interp.before_step) before world.step() (%d, %d)" % [snap_at, step_at])
		return false
	var clamp_at: int = proc.find("RenderInterp.clamp_debt(")
	var loop_at: int = proc.find("while accumulator >= TICK_SECONDS")
	if clamp_at < 0 or loop_at < 0 or clamp_at > loop_at:
		push_error("READERS: _process does not clamp the accumulator before its tick loop")
		return false
	# The running branch updates the camera after its ticks, so the follow reads this frame's point.
	var last_cam: int = proc.rfind("_update_camera(delta)")
	if last_cam < step_at:
		push_error("READERS: _process never updates the camera after its ticks")
		return false
	if not cam.contains("_interp.offset(world, int(world.player), _sub_tick())"):
		push_error("READERS: _update_camera follows the raw tick point, not the drawn one")
		return false
	if not ents.contains("_interp.begin_draw()"):
		push_error("READERS: _draw_entities never resets the watch set, so it would grow forever")
		return false
	var body_at: int = ents.find("_interp.offset(world, carrier, sub_tick)")
	var screen_at: int = ents.find("TopDownProjection.world_to_screen(camera, x, y)")
	if body_at < 0 or screen_at < 0 or body_at > screen_at:
		push_error("READERS: _draw_entities does not slide a body before projecting it")
		return false
	if not ents.contains("carrier = ridden"):
		push_error("READERS: a rider is not drawn with the motion of the vehicle it rides")
		return false
	if not ents.contains("gp += _interp.offset(world, int(rec[\"entity\"]), sub_tick)"):
		push_error("READERS: a live vehicle's picture does not slide with its entity")
		return false
	if not ents.contains("_interp.facing(eid,"):
		push_error("READERS: the facing line and aim cone turn on the tick, not between")
		return false
	print("READERS OK the loop clamps then snapshots before every step and moves the camera after; the draw slides bodies, riders, vehicles and facing")
	return true


func _function_body(path: String, name: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var out: String = ""
	var inside: bool = false
	for line in f.get_as_text().split("\n"):
		if line.begins_with("func %s(" % name):
			inside = true
			continue
		if inside and line.begins_with("func "):
			break
		if inside:
			out += line + "\n"
	return out


# --- the scene --------------------------------------------------------------------------------

func _boot() -> Node:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		return null
	var main: Node = packed.instantiate()
	root.add_child(main)
	await process_frame
	if main.get("world") == null:
		return null
	main.set_process(false)
	main.call("_enter_state", Session.State.PLAYING)
	main.set("paused", false)
	main.set("accumulator", 0.0)
	return main


func _world(main: Node) -> Variant:
	return main.get("world")


func _sim_point(main: Node) -> Vector2:
	var world: Variant = _world(main)
	var p: Variant = world.components.get_component(int(world.player), "position")
	if not (p is Dictionary):
		return Vector2(NAN, NAN)
	return Vector2(float((p as Dictionary)["x"]), float((p as Dictionary)["y"]))


# Where the last draw put the player, in world metres: `_focal_drawn`'s screen point, taken back
# through the same camera the draw used (nothing moves the camera between the draw and here).
func _drawn_point(main: Node) -> Vector2:
	var world: Variant = _world(main)
	for b_v in main.get("_focal_drawn") as Array:
		var b: Dictionary = b_v as Dictionary
		if int(b.get("id", -1)) == int(world.player):
			var w: Dictionary = TopDownProjection.screen_to_world(main.get("camera") as Dictionary, float(b["sx"]), float(b["sy"]))
			return Vector2(float(w["x"]), float(w["y"]))
	return Vector2(NAN, NAN)


func _walk(main: Node, dx: float, dy: float) -> void:
	_world(main).commands.push({"type": "move", "dx": dx, "dy": dy})


# One frame of the real loop with this delta, then one real draw.
func _frame(main: Node, delta: float) -> void:
	main.call("_process", delta)
	main.queue_redraw()
	await process_frame
	await process_frame


# --- CLAMP ------------------------------------------------------------------------------------

func _clamp(main: Node) -> bool:
	var world: Variant = _world(main)
	main.set("speed", 1)
	main.set("accumulator", 0.0)
	var t0: int = int(world.tick)
	main.call("_process", 10.0)
	var ran: int = int(world.tick) - t0
	var left: float = float(main.get("accumulator"))
	var cap: int = 5
	if ran != cap:
		push_error("CLAMP: a ten-second frame ran %d ticks, not the per-frame cap of %d" % [ran, cap])
		return false
	if left >= TICK_SECONDS:
		push_error("CLAMP: a ten-second frame left %.3f s owed -- the debt carries into the next frame" % left)
		return false
	var t1: int = int(world.tick)
	main.call("_process", TICK_SECONDS * 0.5)
	var after: int = int(world.tick) - t1
	if after > 1:
		push_error("CLAMP: the half-tick frame after a hitch ran %d ticks -- the dropped debt came back" % after)
		return false
	# The negative: an ordinary frame is not clamped. 75 ms is one tick and 25 ms kept.
	main.set("accumulator", 0.0)
	var t2: int = int(world.tick)
	main.call("_process", 0.075)
	var one: int = int(world.tick) - t2
	var kept: float = float(main.get("accumulator"))
	if one != 1 or absf(kept - 0.025) > 0.0005:
		push_error("CLAMP: a 75 ms frame ran %d ticks and kept %.4f s (want 1 tick and 0.025 s)" % [one, kept])
		return false
	print("CLAMP OK a 10 s frame ran the cap of %d and dropped the rest (%.3f s left), the next half-tick frame ran %d; a 75 ms frame ran 1 and kept %.3f s" % [ran, left, after, kept])
	return true


# --- DRAWN ------------------------------------------------------------------------------------

func _drawn(main: Node) -> bool:
	_walk(main, 0.0, -1.0)
	for _i in range(WARM_FRAMES):
		await _frame(main, TICK_SECONDS)
	main.set("accumulator", 0.0)
	var before: Vector2 = _sim_point(main)
	await _frame(main, TICK_SECONDS)
	var now: Vector2 = _sim_point(main)
	var at_zero: Vector2 = _drawn_point(main)
	if is_nan(at_zero.x):
		push_error("DRAWN: the draw placed no player body in _focal_drawn")
		return false
	if before.distance_to(now) < 0.01:
		return _skip("DRAWN", "the player did not move this tick (blocked?) -- nothing to interpolate")
	if at_zero.distance_to(before) > EPS:
		push_error("DRAWN: at fraction 0 the body drew at %s, not the previous tick's %s (current %s)" % [at_zero, before, now])
		return false
	if at_zero.distance_to(now) < EPS:
		push_error("DRAWN: at fraction 0 the body drew on the current tick -- nothing is interpolated")
		return false
	await _frame(main, TICK_SECONDS * 0.5)
	if not _sim_point(main).is_equal_approx(now):
		push_error("DRAWN: a half-tick frame stepped the sim")
		return false
	var half: Vector2 = _drawn_point(main)
	if not _strictly_between(half, before, now):
		push_error("DRAWN: at fraction 0.5 the body drew at %s, not strictly between %s and %s" % [half, before, now])
		return false
	_walk(main, 0.0, 0.0)
	print("DRAWN OK at fraction 0 the body drew on the previous tick %s (sim %s); half a tick later it drew at %s, strictly between" % [before, now, half])
	return true


# --- SMOOTH -----------------------------------------------------------------------------------

func _cv(xs: Array) -> float:
	if xs.size() < 2:
		return INF
	var mean: float = 0.0
	for x in xs:
		mean += float(x)
	mean /= float(xs.size())
	if mean <= 0.0:
		return INF
	var v: float = 0.0
	for x in xs:
		v += (float(x) - mean) * (float(x) - mean)
	return sqrt(v / float(xs.size())) / mean


# One window: walk (dx, dy), warm up, then for each frame read the drawn point, the raw sim point,
# the camera centre the scene follows with, and a shadow camera that follows the raw point the
# way the old loop did (updated before the ticks, on the tick point). Speeds are distance / delta.
func _window(main: Node, dx: float, dy: float, deltas: Array) -> Dictionary:
	_walk(main, dx, dy)
	main.set("accumulator", 0.0)
	for _i in range(WARM_FRAMES):
		await _frame(main, TICK_SECONDS)
	var world: Variant = _world(main)
	var shadow: Dictionary = (main.get("_camera_centre") as Dictionary).duplicate()
	var drawn: Array = []
	var raw: Array = []
	var cam: Array = []
	var old_cam: Array = []
	var ticks: Array = []
	var last_drawn: Vector2 = _drawn_point(main)
	var last_raw: Vector2 = _sim_point(main)
	var last_cam := Vector2(float(main.get("_camera_centre")["x"]), float(main.get("_camera_centre")["y"]))
	var last_old := Vector2(float(shadow["x"]), float(shadow["y"]))
	for d_v in deltas:
		var d: float = float(d_v)
		var r0: Vector2 = _sim_point(main)
		var tgt: Dictionary = CameraUtil.follow_target(r0.x, r0.y, int(world.map_width), int(world.map_height))
		CameraUtil.follow_smoothed(shadow, float(tgt["x"]), float(tgt["y"]), CameraUtil.FOLLOW_RATE, d)
		var t0: int = int(world.tick)
		await _frame(main, d)
		ticks.append(int(world.tick) - t0)
		var dp: Vector2 = _drawn_point(main)
		var rp: Vector2 = _sim_point(main)
		var cp := Vector2(float(main.get("_camera_centre")["x"]), float(main.get("_camera_centre")["y"]))
		var op := Vector2(float(shadow["x"]), float(shadow["y"]))
		# A body that ran a tick and went nowhere has walked into something: the window ends
		# there, and the frame before it goes too, because the drawn body trails a tick behind.
		if ticks[-1] > 0 and rp.distance_to(last_raw) < 0.000001:
			ticks.pop_back()
			for xs in [drawn, raw, cam, old_cam]:
				if not (xs as Array).is_empty():
					(xs as Array).pop_back()
			break
		drawn.append(dp.distance_to(last_drawn) / d)
		raw.append(rp.distance_to(last_raw) / d)
		cam.append(cp.distance_to(last_cam) / d)
		old_cam.append(op.distance_to(last_old) / d)
		last_drawn = dp; last_raw = rp; last_cam = cp; last_old = op
	_walk(main, 0.0, 0.0)
	return {"drawn": _cv(drawn), "raw": _cv(raw), "cam": _cv(cam), "old_cam": _cv(old_cam), "ticks": ticks, "speeds": raw}


func _smooth(main: Node) -> bool:
	var steady: Array = []
	for _i in range(STEADY_FRAMES):
		steady.append(1.0 / 60.0)
	# A ~10 fps frame clock with a seeded jitter (60-140 ms): the shipped build's frame rate today,
	# where a frame carries one, two or three ticks depending on how long it took.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261019
	var jitter: Array = []
	for _i in range(JITTER_FRAMES):
		jitter.append(rng.randf_range(0.06, 0.14))
	# South with the long window, then back north with the short one, so neither walks past the
	# street DRAWN already proved is open.
	var b: Dictionary = await _window(main, 0.0, 1.0, jitter)
	var a: Dictionary = await _window(main, 0.0, -1.0, steady)
	var ok: bool = true
	for pair in [["60 Hz", a], ["jittered 10 fps", b]]:
		var name: String = String(pair[0])
		var m: Dictionary = pair[1] as Dictionary
		var total: int = 0
		for t in m["ticks"] as Array:
			total += int(t)
		if total == 0 or float(m["raw"]) == INF or (m["speeds"] as Array).size() < MIN_FRAMES:
			ok = _skip("SMOOTH", "%s: the body walked %d frames before something stopped it -- too few to measure" % [name, (m["speeds"] as Array).size()]) and ok
			continue
		var line: String = "%s: body speed CV %.3f drawn vs %.3f on the tick, camera speed CV %.3f vs %.3f before" % [name, float(m["drawn"]), float(m["raw"]), float(m["cam"]), float(m["old_cam"])]
		print("SMOOTH %s" % line)
		_report.append(line)
		if float(m["drawn"]) >= SMOOTH_CV:
			push_error("SMOOTH: %s -- the drawn body's per-frame speed varies (CV %.3f >= %.2f)" % [name, float(m["drawn"]), SMOOTH_CV])
			ok = false
		if float(m["cam"]) >= CAM_CV:
			push_error("SMOOTH: %s -- the camera's per-frame speed varies (CV %.3f >= %.3f)" % [name, float(m["cam"]), CAM_CV])
			ok = false
	# The negative: the raw tick point at 60 Hz must read as a stutter, or this measure is blind.
	if float(a["raw"]) != INF and float(a["raw"]) <= RAW_CV_FLOOR:
		push_error("SMOOTH: the raw tick point at 60 Hz reads as smooth (CV %.3f) -- the measure cannot see a stutter" % float(a["raw"]))
		ok = false
	return ok
