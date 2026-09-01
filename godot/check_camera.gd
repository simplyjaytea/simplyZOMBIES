extends SceneTree
# Camera feel: a smoothed follow and a decaying screen shake, both pure statics in camera.gd so
# this gate can drive them headlessly with a fabricated {"x", "y"} Dictionary -- no world, no
# kernel, the same reason check_topdown.gd's projection lanes need neither.
#
# Why a lerp needed a gate at all: a hard snap (yesterday's `follow_camera`, called every tick)
# satisfies "the camera tracks the player" perfectly and reads as an instant, jerky cut on every
# stagger and knockback. CONVERGES alone cannot tell the two apart -- a hard snap converges in
# exactly one step -- so SHORT STEP is the lane that actually distinguishes them, and it is shown
# to fail against the old implementation below (see the report, not this file: the red only shows
# up by temporarily reverting follow_smoothed to a snap and running the gate, which is a
# development-time proof, not a standing assertion).
#
# Every lane carries its true negative. A gate that cannot fail is worse than no gate.

const CameraUtil = preload("res://presentation/camera.gd")

const MAIN_GD: String = "res://presentation/main.gd"
const EPS: float = 0.000001
const FRAME_DT: float = 1.0 / 60.0
# 300 frames at 60 fps is 5 s of wall clock -- at FOLLOW_RATE the remaining gap is
# exp(-6*5) =~ 6e-14 of where it started, and at SHAKE_DECAY_RATE it is exp(-10*5) =~ 2e-22.
# Both converge orders of magnitude inside this bound; it exists to keep "bounded" honest, not
# because either lane is close to needing it.
const MAX_STEPS: int = 300


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _converges_to_the_target() and ok
	ok = _short_step_lands_strictly_short_and_rate_zero_holds() and ok
	ok = _clamp_identity_matches_todays_semantics() and ok
	ok = _shake_decays_and_never_exceeds_the_impulse() and ok
	ok = _dead_socket_main_gd_wires_the_helpers() and ok
	if ok:
		print("CAMERA_OK follow converges and clamps like today's snap, one step lands short (not on) the target, rate 0 holds, shake decays within bound and never overshoots its own impulse, and main.gd's frame loop calls every helper")
		quit(0)
	else:
		push_error("CAMERA_FAIL")
		quit(1)


func _dist(a: Dictionary, b: Dictionary) -> float:
	var dx: float = float(a["x"]) - float(b["x"])
	var dy: float = float(a["y"]) - float(b["y"])
	return sqrt(dx * dx + dy * dy)


# --- lanes --------------------------------------------------------------------------------

# CONVERGES. Repeated follow_smoothed steps close on the clamped target -- the ordinary case,
# an in-bounds target nowhere near the map edge, so this lane is about the lerp's shape and not
# about clamping (CLAMP IDENTITY owns that).
func _converges_to_the_target() -> bool:
	var target: Dictionary = CameraUtil.follow_target(140.25, 88.5, 256, 256)
	var cam: Dictionary = {"x": 0.0, "y": 0.0}
	for i in MAX_STEPS:
		CameraUtil.follow_smoothed(cam, float(target["x"]), float(target["y"]), CameraUtil.FOLLOW_RATE, FRAME_DT)
	if _dist(cam, target) > EPS:
		push_error("%d steps at FOLLOW_RATE %.1f left the camera %f m short of (%s)" % [MAX_STEPS, CameraUtil.FOLLOW_RATE, _dist(cam, target), str(target)])
		return false
	print("CONVERGES OK %d steps closed on (%.2f, %.2f) within %.6f" % [MAX_STEPS, float(target["x"]), float(target["y"]), EPS])
	return true


# SHORT STEP, the true negative that actually separates a lerp from a hard snap. One step from
# far away must move the camera closer without arriving -- a hard snap arrives in exactly one
# step and this lane is red against it (see the file header and the report). Rate 0 rides along
# as the other true negative: it must hold exactly, not crawl.
func _short_step_lands_strictly_short_and_rate_zero_holds() -> bool:
	var target: Dictionary = CameraUtil.follow_target(1000.0, 1000.0, 2000, 2000)
	var cam: Dictionary = {"x": 0.0, "y": 0.0}
	var start_dist: float = _dist(cam, target)
	CameraUtil.follow_smoothed(cam, float(target["x"]), float(target["y"]), CameraUtil.FOLLOW_RATE, FRAME_DT)
	var after_dist: float = _dist(cam, target)
	if after_dist <= EPS:
		push_error("one frame at 1/60 s landed exactly on the target (%f m short) -- this is the hard snap the lane exists to catch" % after_dist)
		return false
	if after_dist >= start_dist:
		push_error("one step left the camera %f m from the target, no closer than the starting %f m" % [after_dist, start_dist])
		return false
	var held: Dictionary = {"x": 111.0, "y": 222.0}
	CameraUtil.follow_smoothed(held, float(target["x"]), float(target["y"]), 0.0, FRAME_DT)
	if float(held["x"]) != 111.0 or float(held["y"]) != 222.0:
		push_error("rate 0 moved (111, 222) to (%f, %f); a paused or frozen frame must not move the camera" % [float(held["x"]), float(held["y"])])
		return false
	print("SHORT STEP OK one step closed %.1f%% of a %.1f m gap and stopped short of it; rate 0 held (111, 222) exactly" % [100.0 * (1.0 - after_dist / start_dist), start_dist])
	return true


# CLAMP IDENTITY. For a target outside the map, the smoothed steady state must equal the clamp
# today's semantics already give -- against an oracle spelled out by hand here (clampf, the same
# formula the old follow_camera used) rather than against follow_target itself, so a broken clamp
# in follow_target cannot grade its own homework.
func _clamp_identity_matches_todays_semantics() -> bool:
	var map_w: int = 256
	var map_h: int = 256
	var raw_x: float = -75.0
	var raw_y: float = 9001.0
	var want_x: float = clampf(raw_x, 0.0, float(map_w))
	var want_y: float = clampf(raw_y, 0.0, float(map_h))
	var target: Dictionary = CameraUtil.follow_target(raw_x, raw_y, map_w, map_h)
	if absf(float(target["x"]) - want_x) > EPS or absf(float(target["y"]) - want_y) > EPS:
		push_error("follow_target(%.1f, %.1f, %d, %d) = (%f, %f), want the clamp (%f, %f)" % [raw_x, raw_y, map_w, map_h, float(target["x"]), float(target["y"]), want_x, want_y])
		return false
	var cam: Dictionary = {"x": 40.0, "y": 210.0}
	for i in MAX_STEPS:
		CameraUtil.follow_smoothed(cam, float(target["x"]), float(target["y"]), CameraUtil.FOLLOW_RATE, FRAME_DT)
	if absf(float(cam["x"]) - want_x) > EPS or absf(float(cam["y"]) - want_y) > EPS:
		push_error("the smoothed steady state (%f, %f) does not equal the clamp (%f, %f) an off-map target must settle on" % [float(cam["x"]), float(cam["y"]), want_x, want_y])
		return false
	print("CLAMP IDENTITY OK an off-map target (%.1f, %.1f) clamps to (%.1f, %.1f) and the smoothed steady state lands there too" % [raw_x, raw_y, want_x, want_y])
	return true


# SHAKE DECAYS. An impulse produces an offset that decays below SHAKE_EPSILON within MAX_STEPS,
# and the offset's magnitude never exceeds the impulse that produced it at any step along the
# way. The true negative is the assertion's own ability to fail: a decay factor of 1.0 -- rate 0,
# "no decay at all" -- fed to the same helper must NOT decay below epsilon in the same bound, or
# the "decays within bound" assertion above is one that can never go red.
func _shake_decays_and_never_exceeds_the_impulse() -> bool:
	var mag: float = 10.0
	var shake: Dictionary = {"x": 0.0, "y": 0.0}
	CameraUtil.shake_impulse(shake, mag, 0.0, mag * 2.0)
	if absf(CameraUtil.shake_magnitude(shake) - mag) > EPS:
		push_error("a %.1f px impulse at angle 0 produced offset magnitude %f, not the impulse itself" % [mag, CameraUtil.shake_magnitude(shake)])
		return false
	var decayed: bool = false
	var steps_taken: int = 0
	for i in MAX_STEPS:
		CameraUtil.shake_decay(shake, CameraUtil.SHAKE_DECAY_RATE, FRAME_DT)
		steps_taken = i + 1
		var m: float = CameraUtil.shake_magnitude(shake)
		if m > mag + EPS:
			push_error("shake magnitude %f exceeded the %.1f px impulse that produced it, at step %d" % [m, mag, i])
			return false
		if m < CameraUtil.SHAKE_EPSILON:
			decayed = true
			break
	if not decayed:
		push_error("a %.1f px impulse did not decay below %.4f within %d frames of real decay" % [mag, CameraUtil.SHAKE_EPSILON, MAX_STEPS])
		return false
	var stuck: Dictionary = {"x": 0.0, "y": 0.0}
	CameraUtil.shake_impulse(stuck, mag, 0.0, mag * 2.0)
	for i in MAX_STEPS:
		CameraUtil.shake_decay(stuck, 0.0, FRAME_DT)
	if CameraUtil.shake_magnitude(stuck) < CameraUtil.SHAKE_EPSILON:
		push_error("a decay factor of 1.0 (rate 0) still decayed the offset below epsilon within %d steps -- the DECAYS assertion above cannot go red" % MAX_STEPS)
		return false
	print("SHAKE DECAYS OK a %.0f px impulse never exceeded itself, decayed below %.4f within %d/%d frames, and a decay factor of 1.0 correctly does not decay at all" % [mag, CameraUtil.SHAKE_EPSILON, steps_taken, MAX_STEPS])
	return true


# DEAD SOCKET. Everything above is true of helpers nothing in the frame loop calls -- exactly the
# state a hard-coded follow was in before this slice. None of this can be exercised headless (the
# frame loop needs a running Node's _process), so what the functions contain is read, the way
# check_topdown.gd and check_respond.gd both read main.gd.
func _dead_socket_main_gd_wires_the_helpers() -> bool:
	var update_camera: String = _function_body(MAIN_GD, "_update_camera")
	if update_camera.is_empty():
		push_error("could not read _update_camera out of %s -- the reach assertion had nothing to judge" % MAIN_GD)
		return false
	if not update_camera.contains("CameraUtil.follow_smoothed("):
		push_error("_update_camera does not call CameraUtil.follow_smoothed: the follow lerp is not wired into the frame loop")
		return false
	if not update_camera.contains("CameraUtil.shake_decay("):
		push_error("_update_camera does not call CameraUtil.shake_decay: a shake offset would never fade")
		return false

	var snap_fn: String = _function_body(MAIN_GD, "_snap_camera")
	if snap_fn.is_empty():
		push_error("could not read _snap_camera out of %s" % MAIN_GD)
		return false
	if not snap_fn.contains("CameraUtil.snap("):
		push_error("_snap_camera does not call CameraUtil.snap: boot/load/F2 would recentre through the smoothed follow instead of jumping")
		return false

	var shake_fn: String = _function_body(MAIN_GD, "_camera_shake_from_events")
	if shake_fn.is_empty():
		push_error("could not read _camera_shake_from_events out of %s" % MAIN_GD)
		return false
	if not shake_fn.contains("CameraUtil.shake_impulse("):
		push_error("_camera_shake_from_events does not call CameraUtil.shake_impulse: a landed hit produces no kick")
		return false

	var proc_fn: String = _function_body(MAIN_GD, "_process")
	if proc_fn.is_empty():
		push_error("could not read _process out of %s -- the reach assertion had nothing to judge" % MAIN_GD)
		return false
	if not proc_fn.contains("_update_camera("):
		push_error("_process does not call _update_camera: the follow/shake update never runs")
		return false
	if not proc_fn.contains("_camera_shake_from_events("):
		push_error("_process does not call _camera_shake_from_events: drained events never reach the shake")
		return false
	print("DEAD SOCKET OK _process calls _update_camera every frame (-> follow_smoothed, shake_decay) and _camera_shake_from_events every tick (-> shake_impulse); _snap_camera calls snap")
	return true


# The source text of one function, from its `func` line to the next top-level `func`.
# check_topdown.gd's and check_respond.gd's reader, unchanged -- the same reach assertion needs
# the same reader.
func _function_body(path: String, name: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var lines: PackedStringArray = f.get_as_text().split("\n")
	var out: String = ""
	var inside: bool = false
	for line in lines:
		if line.begins_with("func %s(" % name):
			inside = true
			continue
		if inside and line.begins_with("func "):
			break
		if inside:
			out += line + "\n"
	return out
