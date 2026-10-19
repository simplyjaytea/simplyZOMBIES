extends RefCounted
# The animation clock: which walk or breath frame a body shows, on the render clock rather than
# the sim tick (docs/23, "Frames on the render clock"). Presentation only -- nothing here writes a
# component, and `godot/sim/` never reads this file.
#
# Until this landed a walk frame was `tick * fps / 20 + id`: the frame moved only when a tick did,
# so at 20 Hz a body changed pose in 50 ms steps whatever the screen's rate, and the cadence was the
# same for a crawl and a sprint -- a limping survivor's feet moonwalked and a sprinter's skated.
# Here the walk is driven by ground covered: every draw hands over where the body is *drawn*
# (presentation/interp.gd's glide), the metres since the last draw advance the body's place in its
# cycle, and the cycle picks the frame. Faster bodies step faster, a body that stops stops stepping,
# and the same path walked at 30 or at 144 frames a second ends on the same frame.
#
# The cadence follows a real gait rather than a treadmill: a body moving at its family's own pace
# (authored.json's `pace`) takes one cycle per `stride` metres, and away from that pace the stride
# lengthens with the square root of the speed -- a sprint at three times the pace steps about 1.7
# times as often, not three, and a crouch at half the pace about 0.7 times. Fixed stride would have
# a sprinter's legs a blur and a crawler's frozen.
#
# A body standing still breathes: its idle loop runs on presentation time (seconds of game time,
# so it stops on pause and quickens under fast-forward with everything else), at the family's
# `breath_fps`, staggered by id so a crowd does not inhale as one.
#
# The motion a draw asks about is one Dictionary, {walking, cycle, idle}, built by `motion()` and
# read by `Appearance.frame_key`. That Dictionary is the hook the action animations (alpha plan A8:
# a swing, a recoil, a flinch, a fall) plug into: one more key -- an action and its elapsed time --
# that frame_key answers before the walk. Nothing here builds them.

# A drawn body that moved farther than this between two draws did not walk there (a load, a mount,
# a body that was off screen and came back): the clock re-seats it rather than spinning its legs
# through the whole distance. The same number as presentation/interp.gd's snap.
const SNAP_METRES: float = 4.0
# Below this many metres per second of game time a drawn body counts as standing: the tail of a
# glide after the sim has already stopped it is still walking, a float jitter is not.
const STILL_MPS: float = 0.05
# The slowest and fastest a stride may stretch to, as multiples of the family's own: the square-root
# law above is a gait, not a law of nature, and it should not answer a zero or a teleport.
const STRIDE_MIN: float = 0.5
const STRIDE_MAX: float = 2.0

# id -> {"x", "y", "cycle", "idle", "seen"}: one record per body drawn last frame.
var _bodies: Dictionary = {}
# Which draw pass this is, so a body nobody drew last pass is forgotten and re-seated if it returns.
var _pass: int = 0
# Presentation time at the last pass, and the game seconds this pass covers.
var _time: float = 0.0
var _dt: float = 0.0


# Where a body is in its walk after covering `metres` at `mps` metres per second, for a family
# whose own stride is `stride` metres a cycle at `pace` metres per second. 0 to 1, wrapping. Pure,
# so the gates can walk a path through it without a scene.
static func cycle_after(cycle: float, metres: float, mps: float, stride: float, pace: float) -> float:
	if metres <= 0.0 or stride <= 0.0:
		return fposmod(cycle, 1.0)
	return fposmod(cycle + metres / stride_at(mps, stride, pace), 1.0)


# The stride at `mps`: the family's own at its own pace, longer when faster and shorter when slower,
# by the square root of the ratio, clamped.
static func stride_at(mps: float, stride: float, pace: float) -> float:
	if pace <= 0.0 or mps <= 0.0:
		return stride
	return stride * clampf(sqrt(mps / pace), STRIDE_MIN, STRIDE_MAX)


# The frame a cycle shows out of `frames`. A cycle of exactly 1.0 is frame 0 again.
static func frame_at(cycle: float, frames: int) -> int:
	if frames <= 0:
		return 0
	return clampi(int(floor(fposmod(cycle, 1.0) * float(frames))), 0, frames - 1)


# The breath frame after `seconds` of standing, at `fps` frames a second out of `frames`.
static func breath_at(seconds: float, fps: float, frames: int) -> int:
	if frames <= 0 or fps <= 0.0 or seconds <= 0.0:
		return 0
	return int(floor(seconds * fps)) % frames


# Where a body first seen starts its walk and its breath: spread by id with the golden ratio, so
# neighbours land far apart in the cycle and a crowd that set off together does not step as one.
static func seat(id: int) -> float:
	return fposmod(float(id) * 0.6180339887, 1.0)


func clear() -> void:
	_bodies = {}
	_pass = 0
	_time = 0.0
	_dt = 0.0


# The start of a draw pass. `now` is presentation time in game seconds -- the frame loop's own
# running total of `delta * speed` while the world runs, held still while it does not. A pass with
# no time behind it (a second draw in one frame, a paused world) moves nothing.
func begin_draw(now: float) -> void:
	_dt = maxf(0.0, now - _time)
	_time = now
	_pass += 1


# The motion of one body this pass, from where it is drawn and whether the sim says it moves:
# {walking, cycle, idle}. `stride` and `pace` are its family's (Appearance.stride_of / pace_of).
# Called once per drawn body per pass; a body not drawn in the last pass is re-seated.
func motion(id: int, drawn: Vector2, sim_moving: bool, stride: float, pace: float) -> Dictionary:
	var rec: Variant = _bodies.get(id)
	if not (rec is Dictionary) or int((rec as Dictionary)["seen"]) < _pass - 1:
		rec = {"x": drawn.x, "y": drawn.y, "cycle": seat(id), "idle": seat(id + 7919) * 4.0, "seen": _pass}
		_bodies[id] = rec
	var r: Dictionary = rec as Dictionary
	var moved: float = drawn.distance_to(Vector2(float(r["x"]), float(r["y"])))
	if moved > SNAP_METRES:
		moved = 0.0
	var mps: float = moved / _dt if _dt > 0.0 else 0.0
	# Walking is the sim's word or the picture's: a body the sim has just stopped still glides the
	# last tick out, and a paused body the sim says is moving holds its stride rather than standing.
	var walking: bool = sim_moving or mps > STILL_MPS
	if walking:
		r["cycle"] = cycle_after(float(r["cycle"]), moved, mps, stride, pace)
		r["idle"] = 0.0
	else:
		r["idle"] = float(r["idle"]) + _dt
	r["x"] = drawn.x
	r["y"] = drawn.y
	r["seen"] = _pass
	return {"walking": walking, "cycle": float(r["cycle"]), "idle": float(r["idle"])}


# How many bodies the clock is holding -- a reader for the gate, so "a body nobody drew is
# forgotten" is a number it can judge.
func held() -> int:
	return _bodies.size()


# Drops every record not drawn in the last pass. Called after a draw so the table never outgrows
# what is on screen.
func end_draw() -> void:
	for id in _bodies.keys():
		if int((_bodies[id] as Dictionary)["seen"]) < _pass:
			_bodies.erase(id)
