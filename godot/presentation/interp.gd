extends RefCounted
# Render interpolation: where a body is *drawn* between two sim ticks (docs/23, "Smooth motion
# between ticks"). Presentation only -- nothing here writes a component or reads anything the sim
# does not already publish, and `godot/sim/` never reads this file.
#
# The sim steps at 20 Hz and the screen draws at whatever the frame rate is. Drawn straight off
# the position component, every body holds still for a tick and then jumps 50 ms of travel at
# once, however fast the frames come. Here the frame loop snapshots each drawn body's position
# (and facing) just before every `world.step()`, and the draw places the body at
# `lerp(before_last_step, now, fraction)`, where `fraction` is how far the frame clock has run
# into the next tick (`accumulator / TICK_SECONDS`). At fraction 0 a body stands exactly where
# it was a tick ago and at fraction 1 exactly where the sim has it now -- the usual one-tick
# render delay, traded for motion that never jumps.
#
# The sim stays the only truth: sight, picking, collisions and every gate that reads a position
# read the component. Only the picture and the camera that follows it slide.

# A body that moved farther than this in one tick did not walk there -- a load, a mount, a
# respawn, an id reused -- and gliding it across the street would draw a path it never took.
# The fastest thing that moves on its own is a car, well under two metres a tick.
const SNAP_METRES: float = 4.0

# The ids the last draw placed, which are the only ids worth snapshotting before the next step.
# Rebuilt every draw (begin_draw clears it, offset() refills it), so a body that left the screen
# or the world stops costing anything one frame later.
var _watch: Dictionary = {}
# id -> [x, y, radians]: the state just before the latest step. Replaced wholesale at every step,
# so it never outlives the tick it describes. radians is NAN for a body with no facing.
var _prev: Dictionary = {}


# How far the frame clock has run into the next tick, 0 to 1. A debt the loop could not pay this
# frame (the per-frame cap, or the clamp below) reads as a whole tick, never more.
static func fraction(accumulator: float, tick_seconds: float) -> float:
	if tick_seconds <= 0.0:
		return 0.0
	return clampf(accumulator / tick_seconds, 0.0, 1.0)


# The clamped accumulator: never owe more ticks than one frame is allowed to run. A slow frame
# (a hitch, a dragged window, a tick that costs more than the 50 ms it covers) used to carry the
# unpaid remainder forward, so every later frame ran the cap again and the world never caught up
# -- the spiral where the next frame is slower because this one was. Past the cap, the time is
# dropped: the world runs slower than the wall clock for that stretch instead of snowballing.
static func clamp_debt(accumulator: float, tick_seconds: float, cap_ticks: int) -> float:
	return clampf(accumulator, 0.0, tick_seconds * float(maxi(1, cap_ticks)))


# The drawn point between two sim positions. Strictly between them for 0 < t < 1, on `prev` at
# t = 0 and on `cur` at t = 1; a jump longer than SNAP_METRES draws at `cur` at once.
static func between(prev: Vector2, cur: Vector2, t: float) -> Vector2:
	if prev.distance_squared_to(cur) > SNAP_METRES * SNAP_METRES:
		return cur
	return prev.lerp(cur, clampf(t, 0.0, 1.0))


# The drawn heading, the short way round: a body turning from just under pi to just over -pi
# turns a hair, not a whole circle.
static func turn_between(prev: float, cur: float, t: float) -> float:
	if is_nan(prev):
		return cur
	return lerp_angle(prev, cur, clampf(t, 0.0, 1.0))


func clear() -> void:
	_watch = {}
	_prev = {}


# Called by the frame loop immediately before every `world.step()`. With several ticks in one
# frame the last call wins, which is the point: the draw interpolates across the final tick only.
func before_step(world: Variant) -> void:
	var fresh: Dictionary = {}
	var ids: Array = _watch.keys()
	ids.append(int(world.player))
	for id_v in ids:
		var id: int = int(id_v)
		var p: Variant = world.components.get_component(id, "position")
		if not (p is Dictionary):
			continue
		var r: float = NAN
		var f: Variant = world.components.get_component(id, "facing")
		if f is Dictionary:
			r = float((f as Dictionary).get("radians", 0.0))
		fresh[id] = [float((p as Dictionary)["x"]), float((p as Dictionary)["y"]), r]
	_prev = fresh


# The start of a draw pass: forget who was watched, offset() records who is drawn now.
func begin_draw() -> void:
	_watch = {}


# What to add to the sim position of `id` to draw it at fraction `t`: zero for a body with no
# snapshot yet (a body that just came into view draws on its tick, then glides from the next).
# The offset form lets a derived point -- a rider's seat on a bicycle, a car's ground point --
# slide with the body that carries it, without this file knowing how either is derived.
func offset(world: Variant, id: int, t: float) -> Vector2:
	_watch[id] = true
	if not _prev.has(id):
		return Vector2.ZERO
	var p: Variant = world.components.get_component(id, "position")
	if not (p is Dictionary):
		return Vector2.ZERO
	var cur := Vector2(float((p as Dictionary)["x"]), float((p as Dictionary)["y"]))
	var prev_v: Array = _prev[id] as Array
	var prev := Vector2(float(prev_v[0]), float(prev_v[1]))
	return between(prev, cur, t) - cur


# The drawn heading of `id` at fraction `t`, given the sim's current one.
func facing(id: int, cur_radians: float, t: float) -> float:
	if not _prev.has(id):
		return cur_radians
	return turn_between(float((_prev[id] as Array)[2]), cur_radians, t)


# How many bodies the next step will snapshot -- a reader for the gate, so "the watch set is
# rebuilt every draw" is a number it can judge rather than a comment it has to trust.
func watched() -> int:
	return _watch.size()
