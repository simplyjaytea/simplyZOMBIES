extends RefCounted
# The UI Field Kit, as the running game reads it (docs/30, "The UI Field Kit, live",
# 2026-09-25). The kit itself lives at art/simplyzombies-ui/ exactly as the owner approved it;
# this file is the one door the screens go through to reach it, and `ui/chrome.gd` is the one
# caller that turns what it hands back into panels, headers, cells and plates.
#
# Why this loads PNGs and builds its styles in code rather than loading the kit's .tres files:
# no `.import` file is committed and `.godot/` is ignored, so in every headless gate a kit PNG
# is not a Resource and every `styles/*.tres` that references one fails to parse -- `load()`
# hands back null, and a `preload()` of one would stop chrome.gd compiling for every gate that
# boots main.tscn. So a texture resolves the two-path way `presentation/appearance.gd`'s
# `resolve()` already does (ResourceLoader first, for an exported build whose .pck carries the
# imported texture and not the raw file; then `Image.load` for dev and CI), and each StyleBox is
# built here from the NINE table below. `manifest.json` and the `.tres` text stay the spec:
# `godot:check:ui_skin`'s KIT lane parses both as text and refuses a margin here that disagrees
# with either.
#
# Styles are cached rather than duplicated per draw -- the kit's own `ui_skin.gd` calls
# `duplicate()` on every draw, which would churn a resource per panel per frame. The key carries
# the opacity to the whole percent, so a fading panel costs at most one style per percent.
#
# Four things here depart from the kit's own files, all by the owner's decisions of 2026-09-25
# (docs/30, "The UI Field Kit, live"), and the gate names each rather than letting it pass
# silently:
#  - **2x.** The approved mockups read at twice the kit's native pixels, the same 2x the world's
#    32 px tile is drawn at, so every kit texture is scaled SCALE times with nearest filtering once,
#    at load, and every margin is NINE * SCALE. NINE itself stays at the manifest's native values,
#    so the gate still compares it against the manifest and the .tres unscaled.
#  - **A tiled centre.** The .tres files stretch (they set no axis mode). Stretched across a tall
#    panel the centre's fine noise smeared into blotches and streaks, so every centre tiles.
#  - **Edges by style.** A StyleBoxTexture's axis modes cover its edge strips as well as its
#    centre, and neither mode suits every frame: tiled, a button's or slot's corner-bracket arms,
#    which run past the kit's nine-slice margins into the strips, repeat as a row of tick marks
#    along every border; stretched, a dashed or noisy edge loses its even rhythm and a bracket arm
#    grows with the frame. So the dashed and noisy frames (EDGE_TILED) tile their edges, and the
#    bracketed ones stretch theirs, as the .tres means --
#  - **with their margins widened** (BRACKET_MARGINS) just enough that each whole bracket sits in
#    its corner, where a nine-slice draws it 1:1, so it keeps its drawn length at any size.
# So a built Style is two StyleBoxTextures over one texture: the frame, its edges in its group's
# mode and drawing no centre, and the centre alone -- `region_rect` the texture inset by the
# frame's margins, no margins of its own -- tiled across the frame's content rect.
#
# The caches are static on purpose. CLAUDE.md's static-var trap is about per-world *sim* state
# leaking between two worlds a gate boots; these hold nothing but textures and draw settings
# derived from files on disk, identical for every world, and nothing under godot/sim/ reads them.

const ROOT: String = "res://art/simplyzombies-ui/"
# Every chrome texture is drawn at this many screen pixels per kit pixel.
const SCALE: int = 2
# The one style drawn at the kit's native 1x rather than SCALE. A keycap sits inline in a line of
# 20-30 px text, where the approved HUD mockup draws it with a hairline amber rim; at 2x that rim
# doubles and its 10 px corners crowd a single letter. The gate's KIT lane names this too.
const NATIVE_STYLES: Array[String] = ["keycap"]
# Glyphs have their own scale: a glyph sits beside 20-30 px text, where a 2x glyph would be
# taller than the line it labels.
const GLYPH_SCALE: int = 1
# How every built style fills its centre: tiled, deliberately not the .tres files' stretch (the
# header's second departure; the gate's CENTRE_MODE_DEVIATION).
const CENTRE_MODE: StyleBoxTexture.AxisStretchMode = StyleBoxTexture.AXIS_STRETCH_MODE_TILE

# The owner's per-style edge decision (docs/30, "The UI Field Kit, live", 2026-09-25): the frames
# whose edge strips carry a dashed line or fine noise tile their edges, so the rhythm stays even at
# any size -- slot_empty's dashed inner line, the panels' worn rims, the divider's grain. Every
# other style NINE wears is bracketed and is keyed in BRACKET_MARGINS below; its edges stretch, the
# .tres meaning. The gate's KIT lane holds every style to exactly one of the two.
const EDGE_TILED: Array[String] = [
	"panel_standard", "panel_dialog", "panel_inset", "panel_notice", "panel_danger", "panel_tooltip",
	"slot_empty", "divider",
]

# The bracketed styles' draw margins [left, top, right, bottom] at native kit pixels (docs/30, "The
# UI Field Kit, live", the owner's per-style decision of 2026-09-25). Each is the manifest's
# `nine_slice_ltrb` widened just enough that the whole corner bracket -- its ink and the pixel that
# ends it -- sits inside the corner, where a nine-slice draws it 1:1, so the stretched edge between
# holds nothing of it. Measured from the pixels, not guessed: the gate's KIT lane re-measures every
# entry and refuses one a pixel too narrow on any side, or a pixel wider than it needs. An entry
# equal to NINE is a bracketed style whose bracket already sat inside the kit's own margins.
# NINE stays the manifest's values, which the gate still compares against the manifest and .tres.
const BRACKET_MARGINS: Dictionary = {
	"button_normal": [11, 9, 10, 8],
	"button_hover": [13, 9, 12, 10],
	"button_pressed": [12, 9, 11, 9],
	"button_focus": [18, 10, 17, 10],
	"button_danger": [12, 11, 12, 11],
	"slot_hover": [6, 6, 6, 6],
	"slot_pressed": [6, 6, 6, 6],
	"slot_selected": [7, 7, 7, 7],
	"slot_invalid": [6, 7, 7, 8],
	"keycap": [5, 5, 5, 5],
}

# Nine-slice margins [left, top, right, bottom] for every style the screens consume, copied from
# manifest.json's `nine_slice_ltrb` (and equal to each styles/<id>.tres's texture_margin_*).
# A kit style that is not here is deliberately unused; the gate names each with its reason.
const NINE: Dictionary = {
	"panel_standard": [10, 10, 10, 10],
	"panel_dialog": [12, 12, 12, 12],
	"panel_inset": [10, 10, 10, 10],
	"panel_notice": [10, 10, 10, 10],
	"panel_danger": [10, 10, 10, 10],
	"panel_tooltip": [10, 10, 10, 10],
	"button_normal": [9, 6, 9, 6],
	"button_hover": [9, 6, 9, 6],
	"button_pressed": [9, 6, 9, 6],
	"button_focus": [9, 6, 9, 6],
	"button_danger": [9, 6, 9, 6],
	"slot_empty": [6, 6, 6, 6],
	"slot_hover": [6, 6, 6, 6],
	"slot_pressed": [6, 6, 6, 6],
	"slot_selected": [6, 6, 6, 6],
	"slot_invalid": [6, 6, 6, 6],
	"keycap": [5, 5, 5, 5],
	"divider": [2, 0, 2, 0],
}

# "rel_path@scale" -> Texture2D or null. A miss is cached too: re-probing the filesystem every frame for
# a file that is not there would cost more than the draw.
static var _textures: Dictionary = {}
# "id@draw_center@percent" -> Style.
static var _styles: Dictionary = {}
# "frame|centre:id@percent" -> StyleBoxTexture, shared by the filled and border-only Style of one
# id at one opacity.
static var _parts: Dictionary = {}


# One kit style as the screens draw it: the frame stretched, the centre tiled. `draw()` takes what
# StyleBox.draw() takes, so a caller cannot tell it from one. Built once per key and cached; a draw
# allocates nothing.
class Style extends RefCounted:
	# The nine-slice frame: corners fixed, edges stretched, `draw_center` false.
	var border: StyleBoxTexture = null
	# The centre alone, tiled; null for a border-only style.
	var centre: StyleBoxTexture = null
	# The frame's margins in screen pixels, where the centre's rect starts and stops.
	var inset_begin: Vector2 = Vector2.ZERO
	var inset_end: Vector2 = Vector2.ZERO

	func draw(canvas_item: RID, rect: Rect2) -> void:
		if centre != null:
			var inner: Rect2 = Rect2(rect.position + inset_begin, rect.size - inset_begin - inset_end)
			if inner.size.x > 0.0 and inner.size.y > 0.0:
				centre.draw(canvas_item, inner)
		border.draw(canvas_item, rect)


# One kit PNG, by its path under ROOT, scaled `scale` times with nearest filtering. ResourceLoader
# first (an exported build), then the raw file (dev and headless CI, where nothing is imported).
# Null when neither finds it.
static func texture(rel_path: String, scale: int = SCALE) -> Texture2D:
	if rel_path.is_empty():
		return null
	var key: String = "%s@%d" % [rel_path, scale]
	if _textures.has(key):
		return _textures[key] as Texture2D
	var path: String = ROOT + rel_path
	var img: Image = null
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Texture2D:
			img = (res as Texture2D).get_image()
	if img == null and FileAccess.file_exists(path):
		var raw := Image.new()
		if raw.load(path) == OK:
			img = raw
	var tex: Texture2D = null
	if img != null and not img.is_empty():
		if img.is_compressed():
			img.decompress()
		if scale > 1:
			img.resize(img.get_width() * scale, img.get_height() * scale, Image.INTERPOLATE_NEAREST)
		tex = ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex


# The nine-slice style for `id`, at `alpha`, ready to `.draw()` into `rect`. Null when the id is
# not one the screens consume, when its texture does not resolve, or when `rect` is smaller than
# the style's own margins -- a nine-slice squeezed below its corners draws overlapping corners,
# so the caller falls back to a drawn fill instead.
static func style(id: String, rect: Rect2, alpha: float, draw_center: bool = true) -> Style:
	if not NINE.has(id):
		return null
	var m: Array[int] = margins(id)
	if rect.size.x < float(m[0] + m[2]) or rect.size.y < float(m[1] + m[3]):
		return null
	var pct: int = clampi(roundi(alpha * 100.0), 0, 100)
	var key: String = "%s@%s@%d" % [id, str(draw_center), pct]
	if _styles.has(key):
		return _styles[key] as Style
	var tex: Texture2D = texture("textures/%s.png" % id, scale_of(id))
	if tex == null:
		return null
	var st := Style.new()
	st.border = _part("frame", id, tex, m, pct)
	st.centre = _part("centre", id, tex, m, pct) if draw_center else null
	st.inset_begin = Vector2(float(m[0]), float(m[1]))
	st.inset_end = Vector2(float(m[2]), float(m[3]))
	_styles[key] = st
	return st


# One half of a Style. `frame`: the whole texture as a nine-slice at the style's draw margins, its
# edges in its group's mode (edge_mode), centre not drawn. `centre`: only the region inside those
# margins, with no margins of its own, tiled on both axes -- see the header, and the gate's
# CENTRE_MODE_DEVIATION.
static func _part(which: String, id: String, tex: Texture2D, m: Array[int], pct: int) -> StyleBoxTexture:
	var key: String = "%s:%s@%d" % [which, id, pct]
	if _parts.has(key):
		return _parts[key] as StyleBoxTexture
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	if which == "centre":
		var size: Vector2 = tex.get_size()
		sb.region_rect = Rect2(float(m[0]), float(m[1]), size.x - float(m[0] + m[2]), size.y - float(m[1] + m[3]))
		sb.axis_stretch_horizontal = CENTRE_MODE
		sb.axis_stretch_vertical = CENTRE_MODE
		sb.draw_center = true
	else:
		sb.texture_margin_left = float(m[0])
		sb.texture_margin_top = float(m[1])
		sb.texture_margin_right = float(m[2])
		sb.texture_margin_bottom = float(m[3])
		sb.axis_stretch_horizontal = edge_mode(id)
		sb.axis_stretch_vertical = edge_mode(id)
		sb.draw_center = false
	sb.modulate_color = Color(1.0, 1.0, 1.0, float(pct) / 100.0)
	_parts[key] = sb
	return sb


# How many screen pixels a kit pixel of this style takes: SCALE, or 1 for NATIVE_STYLES.
static func scale_of(id: String) -> int:
	return 1 if NATIVE_STYLES.has(id) else SCALE


# How a style's frame fills its edges: tiled for EDGE_TILED, the .tres files' stretch otherwise.
static func edge_mode(id: String) -> StyleBoxTexture.AxisStretchMode:
	if EDGE_TILED.has(id):
		return StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	return StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH


# The margins a built style uses, in screen pixels: its native draw margins -- BRACKET_MARGINS for a
# bracketed style, the manifest's NINE otherwise -- times the style's scale. Empty for an id NINE
# does not name. This is also every caller's "does it fit" and "how far in does content start".
static func margins(id: String) -> Array[int]:
	var out: Array[int] = []
	if not NINE.has(id):
		return out
	for n in BRACKET_MARGINS.get(id, NINE[id]) as Array:
		out.append(int(n) * scale_of(id))
	return out


# One glyph texture at GLYPH_SCALE: 24 px native, or the 16 px `small` variant. `which` may be
# given with or without its `glyph_` prefix ("head" and "glyph_head" are the same glyph).
static func glyph(which: String, small: bool = false) -> Texture2D:
	if which.is_empty():
		return null
	var id: String = which if which.begins_with("glyph_") else "glyph_" + which
	if small:
		return texture("glyphs/small/%s_small.png" % id, GLYPH_SCALE)
	return texture("glyphs/%s.png" % id, GLYPH_SCALE)


# Clears every cache. For gates that probe resolution with and without a file present.
static func forget() -> void:
	_textures.clear()
	_styles.clear()
	_parts.clear()
