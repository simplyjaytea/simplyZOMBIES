extends RefCounted
# The UI's one look: military-surplus panels on a dark field -- olive, gunmetal, worn khaki
# text, one amber accent. The reference points are the STALKER PDA and Zero Sievert's kit
# screens: utilitarian chrome that reads as equipment, not as a website. Since the owner's
# decision of 2026-09-25 (docs/30, "The UI Field Kit, live") the frames are the approved UI
# Field Kit's nine-slice textures rather than drawn rectangles and corner brackets: `ui/kit.gd`
# resolves them, and this file is still the whole skin as far as a screen is concerned --
# presentation/palette.gd stays what the *district* is and this file is what the *screens* are.
# Every helper keeps a drawn fallback (the old fill and hairline edge) for a rect smaller than
# a texture's own nine-slice margins, or a kit file that does not resolve.
#
# Every panel helper takes the CanvasItem it draws on, so windows, the body panel and the
# settings sheet cannot drift apart one literal at a time -- that is the SLOT_PLACEMENTS
# lesson applied to style. `godot:check:ui_skin` holds the file to the kit: its PANEL lane
# follows `panel` to the kit style it draws, and its HELPERS lane refuses a helper here that
# nothing outside this file calls.

const Kit = preload("res://ui/kit.gd")

# The skin. Warm dark olives; text in worn khaki; amber for the one thing that matters.
const FIELD: Color = Color(0.043, 0.051, 0.039) # the dim wash behind an open screen
const PANEL: Color = Color("#141810")
const PANEL_EDGE: Color = Color("#3c422c")
const HEADER: Color = Color("#1d2314")
const ACCENT: Color = Color("#c99a3f")
const TEXT: Color = Color("#c8c2a6")
const TEXT_DIM: Color = Color("#807a63")
# Dimmer than a label: a column nobody works, a priority set to never, a slot with nothing in it.
# It exists because three files had grown their own hex literal for the same idea, each a shade
# off the others -- which is the drift the whole of this file is a cure for.
const TEXT_FAINT: Color = Color("#4e4a45")
const DANGER: Color = Color("#b5502f")
const OK: Color = Color("#8a9a5b")
const CELL_BG: Color = Color("#181d12")
const CELL_EDGE: Color = Color("#272e1b")
const ITEM_FILL: Color = Color("#2e3a24")
const ITEM_EDGE: Color = Color("#5d6b41")
const SLOT_EMPTY: Color = Color("#161b11")

const HEADER_H: float = 40.0
# The kit panel's border is five kit pixels deep; the header strip sits inside it. Both it and
# the divider's height are kit pixels, so they follow the kit's draw scale.
const HEADER_INSET: float = 5.0 * Kit.SCALE
const DIVIDER_H: float = 4.0 * Kit.SCALE
const GLYPH_SMALL: float = 16.0 * Kit.GLYPH_SCALE
const KEYCAP_MIN: float = 24.0
const FONT_SIZE: int = 25
# Every size a screen draws text at. 25 and 50 are VT323's pixel-exact sizes; 20 and 30 are the
# rungs either side of 25 a layout may take when 25 is too big for a dense grid or too small for
# a line meant to be read across the room. `godot:check:ui_skin`'s FONT lane refuses a text size
# under godot/ui/ or in main.gd that is not on this list.
const LADDER: Array[int] = [20, 25, 30, 50]

# The one typeface (docs/30, "The UI Field Kit, live"): the kit's VT323, as the kit itself
# configured it for Godot -- `VT323-Pixel.res` is the TTF with antialiasing and hinting off, so
# a glyph lands as hard pixels -- with the engine's own fallback font behind it. VT323 draws on a
# grid of 0.04 em, so it is pixel-exact at 25 px (one font pixel, one screen pixel) and at 50, and
# every size a screen asks for is on the ladder in docs/23's record, "UI -- one typeface".
#
# Loaded lazily and never through `preload`, for the reason kit.gd gives about the kit's .tres:
# nothing is imported in a headless gate. The .res is a self-contained FontFile and does load
# there, but a preload that ever failed would stop this file compiling for every screen, and a
# `load` that fails only falls back to the engine font.
const FONT_PATH: String = "res://art/simplyzombies-ui/fonts/VT323-Pixel.res"

# Built once: a FontVariation is a Resource, and a new one per draw would churn a resource per
# string per frame. Static for the reason kit.gd's caches are -- it is derived from a file on
# disk, identical for every world, and nothing under godot/sim/ reads it.
static var _font: Font = null


# The font every screen draws with. The fallback chain is the engine's font: VT323 carries Latin,
# and what it lacks (Cyrillic, some Greek and symbols) falls through to it before the OS's own
# fallback is asked -- which is where → ▲ ▼ ↔ come from, since neither face has them. It is the only place in godot/ui/ and godot/presentation/ that names the
# engine font; `godot:check:ui_skin`'s FONT lane holds every other file to that.
static func font() -> Font:
	if _font != null:
		return _font
	var base: Resource = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null
	if not (base is FontFile):
		_font = ThemeDB.fallback_font
		return _font
	var v := FontVariation.new()
	v.base_font = base as FontFile
	v.fallbacks = [ThemeDB.fallback_font]
	# VT323 carries an "fi" ligature, which on a monospace pixel face draws "first" one cell short
	# and breaks the grid every other word sits on; a measured width would disagree with a
	# counted one. Off.
	v.opentype_features = {"liga": 0}
	_font = v
	return _font


# The typeface's own ascent, line height and capital height at `size`. Not `font().get_ascent`:
# a Font's metrics are the tallest of it and its fallbacks, so the variation above answers with
# the engine font's taller line (35 px at 25, where VT323's is 25) while every glyph it draws is
# VT323's. A layout that centres or stacks lines asks these instead.
static func ascent(size: int) -> float:
	return _metrics().get_ascent(size)


static func line_height(size: int) -> float:
	return _metrics().get_height(size)


# VT323's capitals are 0.56 em against an ascent of 0.8 em.
static func cap_height(size: int) -> float:
	return roundf(ascent(size) * 0.7)


static func _metrics() -> Font:
	var f: Font = font()
	if f is FontVariation and (f as FontVariation).base_font != null:
		return (f as FontVariation).base_font
	return f


# A panel: the kit's panel_standard frame at the given opacity, then its border alone at a
# little more, so a panel faded to the 0.15 floor still shows where its edge is.
static func panel(ci: CanvasItem, rect: Rect2, alpha: float) -> void:
	var r: Rect2 = _snap(rect)
	if frame(ci, r, "panel_standard", alpha):
		var edge_pass: StyleBoxTexture = Kit.style("panel_standard", r, minf(1.0, alpha + 0.15), false)
		if edge_pass != null:
			edge_pass.draw(ci.get_canvas_item(), r)
		return
	_drawn(ci, r, PANEL, PANEL_EDGE, alpha, minf(1.0, alpha + 0.15), 1.5)


# A header strip along the panel's top: uppercase label over the kit's divider, an optional
# small glyph before the label. The strip sits inside the frame's border so the frame still
# reads around it. Returns the y where content below the header begins.
static func header(ci: CanvasItem, rect: Rect2, label: String, alpha: float, glyph_name: String = "") -> float:
	var r: Rect2 = _snap(rect)
	var inset: float = HEADER_INSET if r.size.x > HEADER_INSET * 4.0 else 0.0
	var strip: Color = HEADER
	strip.a = alpha
	ci.draw_rect(Rect2(r.position + Vector2(inset, inset), Vector2(r.size.x - inset * 2.0, HEADER_H - inset)), strip)
	var rule: Rect2 = Rect2(r.position + Vector2(inset, HEADER_H - DIVIDER_H), Vector2(r.size.x - inset * 2.0, DIVIDER_H))
	if not frame(ci, rule, "divider", minf(1.0, alpha)):
		var under: Color = ACCENT
		under.a = minf(1.0, alpha)
		ci.draw_rect(Rect2(r.position + Vector2(0.0, HEADER_H - 2.0), Vector2(r.size.x, 2.0)), under)
	var x: float = maxf(14.0, inset + 10.0)
	if not glyph_name.is_empty() and Kit.glyph(glyph_name, true) != null:
		glyph(ci, glyph_name, r.position + Vector2(x, floorf((HEADER_H - GLYPH_SMALL) / 2.0)), true, alpha)
		x += GLYPH_SMALL + 8.0
	ci.draw_string(font(), r.position + Vector2(x, header_baseline(inset)), label.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT)
	return rect.position.y + HEADER_H


# Where a header label's baseline sits below the panel's top: its capitals centred in the strip
# between the frame's border and the divider, from the font's own metrics rather than a
# hand-tuned offset -- so a hint a screen draws at the header's far end sits on the same line.
static func header_baseline(inset: float = HEADER_INSET) -> float:
	var cap: float = cap_height(FONT_SIZE)
	return floorf(inset + (HEADER_H - DIVIDER_H - inset - cap) / 2.0 + cap)


# One grid cell backing: the kit's empty slot.
static func cell(ci: CanvasItem, rect: Rect2, alpha: float) -> void:
	var r: Rect2 = _snap(rect)
	if frame(ci, r, "slot_empty", alpha):
		return
	_drawn(ci, r, CELL_BG, CELL_EDGE, alpha, alpha, 1.0)


# An item plate over its cells: the kit's inset panel.
static func item_plate(ci: CanvasItem, rect: Rect2, alpha: float) -> void:
	var r: Rect2 = _snap(rect)
	if frame(ci, r, "panel_inset", alpha):
		return
	_drawn(ci, r, ITEM_FILL, ITEM_EDGE, alpha, alpha, 1.5)


# Any kit style by id into `rect`. False when it could not -- the id is not one the screens
# consume, the texture did not resolve, or the rect is smaller than the style's margins -- so
# the caller can draw its own fallback.
static func frame(ci: CanvasItem, rect: Rect2, id: String, alpha: float) -> bool:
	var r: Rect2 = _snap(rect)
	var sb: StyleBoxTexture = Kit.style(id, r, alpha)
	if sb == null:
		return false
	sb.draw(ci.get_canvas_item(), r)
	return true


# A key drawn as a keycap with its label centred, its top-left at `at`. Returns the width it
# took, so a caller laying out a row of keys and words can advance by it.
static func keycap(ci: CanvasItem, at: Vector2, label: String, size: int, alpha: float) -> float:
	var text_w: float = ceilf(font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	# The label clears the cap's rim by four pixels either side.
	var pad: float = float(Kit.margins("keycap")[0]) + 4.0 if not Kit.margins("keycap").is_empty() else 9.0
	var h: float = maxf(KEYCAP_MIN, float(size) + 8.0)
	var w: float = maxf(h, text_w + pad * 2.0)
	var r: Rect2 = _snap(Rect2(at, Vector2(w, h)))
	if not frame(ci, r, "keycap", alpha):
		_drawn(ci, r, PANEL, ACCENT, alpha, alpha, 1.5)
	var ink: Color = TEXT
	ink.a = alpha
	var f: Font = font()
	var base: float = floorf(r.position.y + (h - line_height(size)) / 2.0 + ascent(size))
	ci.draw_string(f, Vector2(r.position.x + floorf((w - text_w) / 2.0), base), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)
	return w


# One kit glyph at `at` (top-left, whole pixels), 24 px or the 16 px small variant. Draws
# nothing for a glyph that does not resolve.
static func glyph(ci: CanvasItem, glyph_name: String, at: Vector2, small: bool, alpha: float) -> void:
	var tex: Texture2D = Kit.glyph(glyph_name, small)
	if tex == null:
		return
	ci.draw_texture(tex, at.round(), Color(1.0, 1.0, 1.0, alpha))


# The drawn fallback every framed helper shares: fill, then a hairline edge.
static func _drawn(ci: CanvasItem, r: Rect2, fill_col: Color, edge_col: Color, fill_a: float, edge_a: float, width: float) -> void:
	var fill: Color = fill_col
	fill.a = fill_a
	ci.draw_rect(r, fill)
	var edge: Color = edge_col
	edge.a = edge_a
	ci.draw_rect(r, edge, false, width)


# Whole pixels: a nine-slice drawn at a half-pixel offset smears its corners.
static func _snap(rect: Rect2) -> Rect2:
	return Rect2(rect.position.round(), rect.size.round())
