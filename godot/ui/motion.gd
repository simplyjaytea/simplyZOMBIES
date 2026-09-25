extends RefCounted
# The UI Field Kit's four animations, as the screens play them (docs/30, "The UI Field Kit, live",
# 2026-09-25). The kit ships each as four frame PNGs and a SpriteFrames `.tres`; the `.tres` does not
# parse headless for the reason `ui/kit.gd`'s header gives, so the frames load through `Kit.texture`
# like every other kit picture and the timing lives in TABLE below -- a copy of `manifest.json`'s
# animation records, which `godot:check:ui_skin`'s MOTION lane holds to the manifest.
#
# **The wall clock, never the sim's.** Every elapsed time handed in here is seconds of real time a
# caller measured with `Time.get_ticks_msec()`. A pulse that followed the sim's tick would freeze on
# a paused game -- which is exactly where the pause menu's cursor row wears it -- and a sim that
# knew about it would be a sim reading presentation. Nothing under godot/sim/ reads this file.
#
# **Reduced motion** is a presentation preference (`ui/prefs.gd`'s `reduced_motion`, default off --
# the owner's decision of 2026-09-25), not a flag the sim reads. On, every animation stands still on
# the one frame the manifest names for it, at any elapsed time.
#
# `frame_of` and `is_live` are pure: the same id, time and preference give the same answer, so the
# gate can ask them at any instant without a frame. The screens redraw only when `is_live` says an
# animation is still moving and `frame_of` has turned over -- a pulse at six frames a second costs six
# redraws a second, not sixty, and a settled one costs none.

const Kit = preload("res://ui/kit.gd")
const UiPrefs = preload("res://ui/prefs.gd")

# id -> {frames, fps, loop, reduced}, copied from manifest.json's `assets` records (category
# "animation"): `frames` is the length of its frame list, `reduced` its `reduced_motion_frame`. A
# one-shot (`loop` false) holds its last frame once it has played -- the kit README's "one shot,
# hold completion" for saved_tick, and the only sensible end for item_ping.
const TABLE: Dictionary = {
	"focus_pulse": {"frames": 4, "fps": 6, "loop": true, "reduced": 0},
	"busy": {"frames": 4, "fps": 8, "loop": true, "reduced": 0},
	"item_ping": {"frames": 4, "fps": 12, "loop": false, "reduced": 0},
	"saved_tick": {"frames": 4, "fps": 10, "loop": false, "reduced": 2},
}

# The focus pulse is four corner brackets that breathe in and out; it has no `nine_slice_ltrb` in
# the manifest, so this file says how it is laid over a rect. Measured from the pixels of all four
# 32 x 32 frames: no ink in any frame touches the rows or columns either side of the texture's
# centre lines (rows 14-16 and columns 14-17 are empty in every frame), so each quadrant holds
# exactly one bracket and PULSE_CORNER is half the frame -- every quadrant drawn 1:1 in its corner,
# nothing stretched between them, so a bracket keeps its drawn length on a 48 px plate and a 560 px
# row alike. PULSE_OUTSET is how far inside the frame's edge the rest frame's (frame 0's) bracket
# starts on its left and top: the frame is grown by that much, so at rest the bracket's corner sits
# on the focused rect's corner and the breath goes outward from it. (Frame 0's bottom brackets sit a
# kit pixel higher than its top ones sit low -- the kit's own drawing, left as drawn.) Both are
# native kit pixels, drawn at Kit.SCALE; the MOTION lane re-measures both.
const PULSE_ID: String = "focus_pulse"
const PULSE_CORNER: int = 16
const PULSE_OUTSET: int = 8


# The player's reduced-motion preference. The screens ask this once per draw and hand it to the
# pure functions below, so the gate can ask those with either answer.
static func reduced() -> bool:
	return UiPrefs.flag("reduced_motion")


# How long one pass of `id` lasts, in seconds; 0 for an id TABLE does not name.
static func period_of(id: String) -> float:
	var rec: Dictionary = TABLE.get(id, {}) as Dictionary
	if rec.is_empty() or int(rec["fps"]) <= 0:
		return 0.0
	return float(int(rec["frames"])) / float(int(rec["fps"]))


# Which frame of `id` shows `elapsed_s` seconds after it started. A loop wraps; a one-shot holds its
# last frame once it has played; reduced motion gives the manifest's still frame at any time. A
# negative elapsed is the first frame. -1 for an id TABLE does not name.
static func frame_of(id: String, elapsed_s: float, reduced_motion: bool) -> int:
	if not TABLE.has(id):
		return -1
	var rec: Dictionary = TABLE[id] as Dictionary
	var count: int = int(rec["frames"])
	if reduced_motion:
		return int(rec["reduced"])
	var n: int = floori(maxf(elapsed_s, 0.0) * float(int(rec["fps"])))
	if bool(rec["loop"]):
		return n % count
	return mini(n, count - 1)


# Whether `id` is still moving at `elapsed_s`: false under reduced motion, and false for a one-shot
# that has reached its held last frame -- the point at which a screen stops asking for redraws.
static func is_live(id: String, elapsed_s: float, reduced_motion: bool) -> bool:
	if reduced_motion or not TABLE.has(id):
		return false
	if bool((TABLE[id] as Dictionary)["loop"]):
		return true
	return elapsed_s < period_of(id)


# One frame's picture, through Kit.texture at the chrome's scale. Null for a frame the kit does not
# ship.
static func texture_of(id: String, frame: int, scale: int = Kit.SCALE) -> Texture2D:
	if not TABLE.has(id) or frame < 0 or frame >= int((TABLE[id] as Dictionary)["frames"]):
		return null
	return Kit.texture("animations/%s_%d.png" % [id, frame], scale)


# The rect the pulse frame is laid over for a focused `rect`: grown by PULSE_OUTSET at Kit.SCALE.
static func pulse_rect(rect: Rect2) -> Rect2:
	return rect.grow(float(PULSE_OUTSET * Kit.SCALE))


# The focus pulse around `rect`, at the frame `elapsed_s` gives: each quadrant of the frame drawn
# 1:1 in its corner of `pulse_rect(rect)` (see PULSE_CORNER). Returns the frame drawn, so a screen
# can remember what is on it and redraw only when that changes; -1 when nothing was drawn -- a
# missing picture, or a rect too small to hold four corners apart.
static func draw_focus(ci: CanvasItem, rect: Rect2, elapsed_s: float, reduced_motion: bool, alpha: float = 1.0) -> int:
	var frame: int = frame_of(PULSE_ID, elapsed_s, reduced_motion)
	var tex: Texture2D = texture_of(PULSE_ID, frame)
	if tex == null:
		return -1
	var r: Rect2 = pulse_rect(rect)
	var c: float = float(PULSE_CORNER * Kit.SCALE)
	if r.size.x < c * 2.0 or r.size.y < c * 2.0:
		return -1
	var t: Vector2 = tex.get_size()
	var tint := Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0))
	var corner := Vector2(c, c)
	ci.draw_texture_rect_region(tex, Rect2(r.position, corner), Rect2(Vector2.ZERO, corner), tint)
	ci.draw_texture_rect_region(tex, Rect2(Vector2(r.end.x - c, r.position.y), corner), Rect2(Vector2(t.x - c, 0.0), corner), tint)
	ci.draw_texture_rect_region(tex, Rect2(Vector2(r.position.x, r.end.y - c), corner), Rect2(Vector2(0.0, t.y - c), corner), tint)
	ci.draw_texture_rect_region(tex, Rect2(r.end - corner, corner), Rect2(t - corner, corner), tint)
	return frame
