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
# Two things here depart from the kit's own files, both by the owner's decision of 2026-09-25
# (docs/30, "The UI Field Kit, live"), and the gate names each rather than letting it pass
# silently:
#  - **2x.** The approved mockups read at twice the kit's native pixels, the same 2x the world's
#    32 px tile is drawn at, so every kit texture is scaled SCALE times with nearest filtering once,
#    at load, and every margin is NINE * SCALE. NINE itself stays at the manifest's native values,
#    so the gate still compares it against the manifest and the .tres unscaled.
#  - **A tiled centre.** The .tres files stretch (they set no axis mode). Stretched across a tall
#    panel the centre's fine noise smeared into blotches and streaks, so the styles tile instead.
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
# How a built style fills its edges and centre -- the .tres files' STRETCH, deliberately not.
const AXIS_MODE: StyleBoxTexture.AxisStretchMode = StyleBoxTexture.AXIS_STRETCH_MODE_TILE

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
# "id@draw_center@percent" -> StyleBoxTexture.
static var _styles: Dictionary = {}


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
static func style(id: String, rect: Rect2, alpha: float, draw_center: bool = true) -> StyleBoxTexture:
	if not NINE.has(id):
		return null
	var m: Array[int] = margins(id)
	if rect.size.x < float(m[0] + m[2]) or rect.size.y < float(m[1] + m[3]):
		return null
	var pct: int = clampi(roundi(alpha * 100.0), 0, 100)
	var key: String = "%s@%s@%d" % [id, str(draw_center), pct]
	if _styles.has(key):
		return _styles[key] as StyleBoxTexture
	var tex: Texture2D = texture("textures/%s.png" % id, scale_of(id))
	if tex == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = float(m[0])
	sb.texture_margin_top = float(m[1])
	sb.texture_margin_right = float(m[2])
	sb.texture_margin_bottom = float(m[3])
	# Tiled, not the .tres files' stretch: see the header, and the gate's CENTRE_MODE_DEVIATION.
	sb.axis_stretch_horizontal = AXIS_MODE
	sb.axis_stretch_vertical = AXIS_MODE
	sb.draw_center = draw_center
	sb.modulate_color = Color(1.0, 1.0, 1.0, float(pct) / 100.0)
	_styles[key] = sb
	return sb


# How many screen pixels a kit pixel of this style takes: SCALE, or 1 for NATIVE_STYLES.
static func scale_of(id: String) -> int:
	return 1 if NATIVE_STYLES.has(id) else SCALE


# The margins a built style uses, in screen pixels: the manifest's native NINE times the style's
# scale. Empty for an id NINE does not name.
static func margins(id: String) -> Array[int]:
	var out: Array[int] = []
	if not NINE.has(id):
		return out
	for n in NINE[id] as Array:
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


# Clears both caches. For gates that probe resolution with and without a file present.
static func forget() -> void:
	_textures.clear()
	_styles.clear()
