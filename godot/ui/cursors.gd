extends RefCounted
# The pointer, in the kit's own pictures (docs/30, "The UI Field Kit, live", 2026-09-25): the
# UI Field Kit ships four OS cursors -- arrow, hand, move and blocked -- and this is the one table
# that installs them. The outpost pack's crosshair and interaction hand (docs/23's what's left,
# "The cursor", still open) join this same table when that slice lands, rather than a second
# cursor system beside it.
#
# What each screen does is say *which* shape it wants where, through a pure `cursor_at(p)` of its
# own and the Control's `mouse_default_cursor_shape`; the engine then draws whatever picture is
# installed for that shape. So a screen names a shape and never a texture, and this file is the
# only place a shape becomes a picture.
#
# **Scale.** The chrome draws at the owner's 2x (`Kit.SCALE`), and a pointer is drawn over that
# chrome, so a pointer is the same 2x: the kit's 24 px pictures install at 48 px, and every
# hotspot is scaled with its picture, as the kit's integration notes ask ("scale both together").
# The native values stay in TABLE, so `godot:check:ui_skin`'s CURSORS lane compares them against
# `manifest.json` unscaled, the way KIT compares `Kit.NINE`.
#
# **Headless.** `Input.set_custom_mouse_cursor` reaches the display server, and the headless one
# every gate runs under has no pointer to dress, so there it does nothing and raises nothing.
# `install()` is safe to call there; the gate judges the table and who reaches it, never the OS.

const Kit = preload("res://ui/kit.gd")

# Screen pixels per kit pixel for a pointer: the chrome's own scale, so a pointer's pixels are
# the same size as the frame's under it.
const SCALE: int = Kit.SCALE

const MOVE: Dictionary = {"id": "control_cursor_move", "size": Vector2i(24, 24), "hotspot": Vector2i(12, 12)}

# Input.CursorShape -> the kit pointer that shape wears, at the kit's native pixels: `size` and
# `hotspot` are manifest.json's, copied, and the CURSORS lane holds this table to it. Six shapes,
# four pictures: a held item wears `move` under every shape the engine or a screen may name for
# it -- DRAG while it is lifted, CAN_DROP over a place that takes it, MOVE, which is what the
# inventory sheet names -- so no path through a drag falls back to the operating system's arrow.
const TABLE: Dictionary = {
	Input.CURSOR_ARROW: {"id": "control_cursor_arrow", "size": Vector2i(24, 24), "hotspot": Vector2i(6, 2)},
	Input.CURSOR_POINTING_HAND: {"id": "control_cursor_hand", "size": Vector2i(24, 24), "hotspot": Vector2i(9, 2)},
	Input.CURSOR_DRAG: MOVE,
	Input.CURSOR_CAN_DROP: MOVE,
	Input.CURSOR_MOVE: MOVE,
	Input.CURSOR_FORBIDDEN: {"id": "control_cursor_blocked", "size": Vector2i(24, 24), "hotspot": Vector2i(12, 12)},
}


# The picture a shape wears, at SCALE, or null for a shape the table does not name or a picture
# that did not resolve. Through `Kit.texture`, the one two-path loader.
static func texture_of(shape: int) -> Texture2D:
	if not TABLE.has(shape):
		return null
	return Kit.texture("controls/%s.png" % String((TABLE[shape] as Dictionary)["id"]), SCALE)


# Where the click lands inside that picture, in installed pixels: the manifest's hotspot times
# SCALE, because the picture was scaled by the same.
static func hotspot_of(shape: int) -> Vector2:
	if not TABLE.has(shape):
		return Vector2.ZERO
	return Vector2((TABLE[shape] as Dictionary)["hotspot"] as Vector2i * SCALE)


# Dresses every shape in TABLE. Once, from `main.gd`'s `_ensure_ui`, before any screen exists to
# name a shape. Returns how many shapes were given a picture -- a shape whose picture did not
# resolve keeps the operating system's own pointer rather than an empty one.
static func install() -> int:
	var dressed: int = 0
	for shape_v in TABLE.keys():
		var shape: int = int(shape_v)
		var tex: Texture2D = texture_of(shape)
		if tex == null:
			continue
		Input.set_custom_mouse_cursor(tex, shape as Input.CursorShape, hotspot_of(shape))
		dressed += 1
	return dressed
