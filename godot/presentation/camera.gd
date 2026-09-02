extends RefCounted
# Plain data owned by render/, never by sim.
const TopDownProjection = preload("res://presentation/projection.gd")

# zoom is pixels per metre, so a 1 m tile draws zoom x zoom pixels. 32 is the
# art-native scale: assets/sprites/ is authored against a 32 px tile, and every
# zoom step is a power-of-two multiple of it so nearest-neighbour scaling stays
# clean -- the default zoom of 64 (create_camera below) is the art at a clean 2x.
# Changing the art-native scale changes the size of every future sprite, so it is
# a content decision rather than a camera preference: 64 -> 32 was the owner's
# 2026-09-02 reference-look decision (docs/30), and every gate that pins a canvas
# size reads this constant rather than carrying its own copy of the number.
const ZOOM_STEPS: Array[float] = [16.0, 32.0, 64.0, 128.0]

# The zoom at which one art pixel is one screen pixel. It is a member of ZOOM_STEPS on
# purpose, and check_topdown.gd asserts the membership: an art-native scale the camera
# cannot reach is a 1:1 body nobody can ever see. Appearance.blit_scale divides by this,
# which is the whole of how a 32 px rig knows what size to draw at zoom 16 or 64.
# tools/sprites/draw.py carries SIZE = 32 as its own copy -- Python cannot read this
# file -- and the pair is cross-checked by sprites:check and check_appearance.gd: a PNG
# at the wrong size fails both.
const ART_NATIVE: float = 32.0

# No zoom smoothing -- a deliberate refusal, not an oversight. A tween between two of
# the steps above would pass through non-integer scales -- 47.3 px/m, say -- and
# nearest-neighbour has no clean answer for that: every tile edge shimmers while it's
# in flight. Wheel zoom stays an instant step through ZOOM_STEPS for exactly the
# reason the ladder is pinned to powers of two in the first place. Follow and shake
# below are unaffected -- both operate on camera["x"]/["y"], never on camera["zoom"].

# How quickly the displayed centre closes the gap on the clamped follow target, in
# nats/second -- see follow_smoothed. At this rate the gap halves roughly every
# ln(2)/RATE =~ 0.116 s and is under 5% within half a second: brisk enough that the
# view is never visibly lagging the player through a doorway, slow enough that a
# stagger or a knockback reads as motion rather than as a snap.
const FOLLOW_RATE: float = 6.0

# Shake decays the same frame-rate-independent way follow closes: a multiplicative
# factor per second rather than a fixed per-frame subtraction, so a slow machine
# does not feel a longer or jumpier shake in wall-clock time than a fast one.
const SHAKE_DECAY_RATE: float = 10.0
# Below this magnitude the offset is inert -- not worth another queue_redraw, and
# where "decayed" is judged.
const SHAKE_EPSILON: float = 0.05
# Kick sizes, in screen pixels at whatever zoom is current when the offset is
# converted to world units -- see main.gd's _update_camera. All comfortably clear
# of "1 px at rest zoom 64" so pixel snapping never quantizes a kick away.
const SHAKE_HIT_PX: float = 5.0 # attack.connected landing on a survivor
const SHAKE_BITE_PX: float = 8.0 # bite.landed on the player -- worse than a swing connecting
const SHAKE_GRAB_PX: float = 4.0 # grab.started on the player -- a hand closing, not a hit
const SHAKE_CAP_PX: float = 14.0 # the combined offset never exceeds this many px
const SHAKE_FALL_PER_M: float = 1.5 # px of kick lost per metre of distance from the viewer

static func create_camera(zoom: float = 64.0) -> Dictionary:
	return {"x": 0.0, "y": 0.0, "width": 0.0, "height": 0.0, "zoom": zoom}

# Step through the fixed zoom ladder; dir is +1 in, -1 out. Clamps at the ends.
static func zoom_step(camera: Dictionary, dir: int) -> void:
	var at: int = ZOOM_STEPS.find(float(camera["zoom"]))
	if at < 0:
		at = 2
	camera["zoom"] = ZOOM_STEPS[clampi(at + dir, 0, ZOOM_STEPS.size() - 1)]

# Where the camera would sit if it snapped this instant -- the clamp alone, pure and
# unmutating, so a caller (the per-frame follow below, snap, or a gate) can ask "what
# is the target" without moving anything. This is today's follow_camera, renamed:
# the mutation that name used to do is follow_smoothed's job now.
static func follow_target(target_x: float, target_y: float, map_w: int, map_h: int) -> Dictionary:
	return {"x": clampf(target_x, 0.0, float(map_w)), "y": clampf(target_y, 0.0, float(map_h))}

# One frame-rate-independent lerp step of `camera["x"]/["y"]` towards (target_x,
# target_y). The closed form `1 - exp(-rate*delta)` is what makes this the same curve
# at 20 fps and 240 fps -- a per-frame constant blend (`pos = lerp(pos, target, k)`)
# is not, because a fixed k compounds more times a second at a higher frame rate and
# the camera would visibly follow faster on a smoother machine. `rate <= 0` (or a
# zero/negative delta) is a deliberate no-op: a paused or frozen frame must not move
# the camera, which check_camera.gd's SHORT STEP lane pins directly.
static func follow_smoothed(camera: Dictionary, target_x: float, target_y: float, rate: float, delta: float) -> void:
	if rate <= 0.0 or delta <= 0.0:
		return
	var k: float = 1.0 - exp(-rate * delta)
	camera["x"] = float(camera["x"]) + (target_x - float(camera["x"])) * k
	camera["y"] = float(camera["y"]) + (target_y - float(camera["y"])) * k

# Jump straight to the clamped target -- boot, load, F2, and anywhere else a recentre
# must not be watched happening. No smoothing state to reset beyond this: follow_smoothed
# reads only camera["x"]/["y"], so snapping those is the whole job.
static func snap(camera: Dictionary, target_x: float, target_y: float, map_w: int, map_h: int) -> void:
	var t: Dictionary = follow_target(target_x, target_y, map_w, map_h)
	camera["x"] = float(t["x"])
	camera["y"] = float(t["y"])

# Screen shake: a decaying offset, kept by the caller in its own {"x", "y"} Dictionary
# -- never a static here, so two worlds a gate boots in the same process cannot bleed
# shake into each other, the same reason the camera itself is a plain Dictionary and
# not a singleton.

# Add one kick at `angle` radians, magnitude `magnitude` px, capping the combined
# offset's length at `cap`. Direction is the caller's business (main.gd draws it from
# a presentation-side RandomNumberGenerator, never a sim stream) so this stays pure
# and the gate can drive it with fixed angles.
static func shake_impulse(shake: Dictionary, magnitude: float, angle: float, cap: float) -> void:
	if magnitude <= 0.0:
		return
	var x: float = float(shake.get("x", 0.0)) + cos(angle) * magnitude
	var y: float = float(shake.get("y", 0.0)) + sin(angle) * magnitude
	var length: float = sqrt(x * x + y * y)
	if cap > 0.0 and length > cap:
		x = x / length * cap
		y = y / length * cap
	shake["x"] = x
	shake["y"] = y

# One frame-rate-independent decay step, mirroring follow_smoothed's shape: the
# offset multiplies by `exp(-rate*delta)` rather than losing a fixed per-frame amount.
# `rate <= 0` (or a zero/negative delta) leaves the factor at 1.0 -- no decay at all --
# which is deliberate: it is the true negative check_camera.gd's SHAKE DECAYS lane
# uses to prove the "decays within bounded steps" assertion can actually go red.
static func shake_decay(shake: Dictionary, rate: float, delta: float) -> void:
	var factor: float = 1.0
	if rate > 0.0 and delta > 0.0:
		factor = exp(-rate * delta)
	shake["x"] = float(shake.get("x", 0.0)) * factor
	shake["y"] = float(shake.get("y", 0.0)) * factor

static func shake_magnitude(shake: Dictionary) -> float:
	var x: float = float(shake.get("x", 0.0))
	var y: float = float(shake.get("y", 0.0))
	return sqrt(x * x + y * y)

# Linear falloff from a base kick size, the sfx.gd FALL_PER_M precedent (there it
# thins volume over distance; here it thins pixels). Never negative.
static func shake_attenuate(base_px: float, dist_m: float, fall_per_m: float) -> float:
	if base_px <= 0.0:
		return 0.0
	return maxf(0.0, base_px - dist_m * fall_per_m)

static func world_to_screen(camera: Dictionary, x: float, y: float) -> Dictionary:
	return TopDownProjection.world_to_screen(camera, x, y)

static func screen_to_world(camera: Dictionary, sx: float, sy: float) -> Dictionary:
	return TopDownProjection.screen_to_world(camera, sx, sy)
