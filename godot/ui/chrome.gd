extends RefCounted
# The UI's one look: military-surplus panels on a dark field -- olive, gunmetal, worn khaki
# text, one amber accent. The reference points are the STALKER PDA and Zero Sievert's kit
# screens: utilitarian chrome that reads as equipment, not as a website. Everything is drawn
# (no textures), so the whole skin is this file; presentation/palette.gd stays what the
# *district* is and this file is what the *screens* are.
#
# Every panel helper takes the CanvasItem it draws on, so windows, the body panel and the
# settings sheet cannot drift apart one literal at a time -- that is the SLOT_PLACEMENTS
# lesson applied to style.

# The skin. Warm dark olives; text in worn khaki; amber for the one thing that matters.
const FIELD: Color = Color(0.043, 0.051, 0.039) # the dim wash behind an open screen
const PANEL: Color = Color("#141810")
const PANEL_EDGE: Color = Color("#3c422c")
const HEADER: Color = Color("#1d2314")
const ACCENT: Color = Color("#c99a3f")
const TEXT: Color = Color("#c8c2a6")
const TEXT_DIM: Color = Color("#807a63")
const DANGER: Color = Color("#b5502f")
const OK: Color = Color("#8a9a5b")
const CELL_BG: Color = Color("#181d12")
const CELL_EDGE: Color = Color("#272e1b")
const ITEM_FILL: Color = Color("#2e3a24")
const ITEM_EDGE: Color = Color("#5d6b41")
const SLOT_EMPTY: Color = Color("#161b11")

const HEADER_H: float = 40.0
const BRACKET: float = 14.0
const FONT_SIZE: int = 20


static func font() -> Font:
	return ThemeDB.fallback_font


# A panel: fill at the given opacity, hairline edge, and corner brackets -- the ticks are
# what makes a rectangle read as instrument housing rather than a div.
static func panel(ci: CanvasItem, rect: Rect2, alpha: float) -> void:
	var fill: Color = PANEL
	fill.a = alpha
	ci.draw_rect(rect, fill)
	var edge: Color = PANEL_EDGE
	edge.a = minf(1.0, alpha + 0.15)
	ci.draw_rect(rect, edge, false, 1.5)
	var b: float = BRACKET
	var ac: Color = ACCENT
	ac.a = minf(1.0, alpha + 0.1)
	for corner in [rect.position, rect.position + Vector2(rect.size.x, 0.0), rect.position + Vector2(0.0, rect.size.y), rect.position + rect.size]:
		var dx: float = 1.0 if (corner as Vector2).x <= rect.get_center().x else -1.0
		var dy: float = 1.0 if (corner as Vector2).y <= rect.get_center().y else -1.0
		ci.draw_line(corner, (corner as Vector2) + Vector2(b * dx, 0.0), ac, 2.0)
		ci.draw_line(corner, (corner as Vector2) + Vector2(0.0, b * dy), ac, 2.0)


# A header strip along the panel's top: uppercase label, amber underline. Returns the y
# where content below the header begins.
static func header(ci: CanvasItem, rect: Rect2, label: String, alpha: float) -> float:
	var strip: Color = HEADER
	strip.a = alpha
	ci.draw_rect(Rect2(rect.position, Vector2(rect.size.x, HEADER_H)), strip)
	var under: Color = ACCENT
	under.a = minf(1.0, alpha)
	ci.draw_rect(Rect2(rect.position + Vector2(0.0, HEADER_H - 2.0), Vector2(rect.size.x, 2.0)), under)
	ci.draw_string(font(), rect.position + Vector2(14.0, HEADER_H - 13.0), label.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT)
	return rect.position.y + HEADER_H


# One grid cell backing.
static func cell(ci: CanvasItem, rect: Rect2, alpha: float) -> void:
	var bg: Color = CELL_BG
	bg.a = alpha
	ci.draw_rect(rect, bg)
	var edge: Color = CELL_EDGE
	edge.a = alpha
	ci.draw_rect(rect, edge, false, 1.0)


# An item plate over its cells.
static func item_plate(ci: CanvasItem, rect: Rect2, alpha: float) -> void:
	var fill: Color = ITEM_FILL
	fill.a = alpha
	ci.draw_rect(rect, fill)
	var edge: Color = ITEM_EDGE
	edge.a = alpha
	ci.draw_rect(rect, edge, false, 1.5)


# The pin toggle: a drawn stud, filled when pinned. Rect is the hit target; the glyph
# centres inside it.
static func pin(ci: CanvasItem, rect: Rect2, pinned: bool, alpha: float) -> void:
	var c: Vector2 = rect.get_center()
	var r: float = minf(rect.size.x, rect.size.y) * 0.28
	var col: Color = ACCENT if pinned else TEXT_DIM
	col.a = alpha
	if pinned:
		ci.draw_circle(c + Vector2(0.0, -r * 0.2), r, col)
		ci.draw_line(c + Vector2(0.0, r * 0.4), c + Vector2(0.0, r * 1.6), col, 2.0)
	else:
		ci.draw_circle(c + Vector2(0.0, -r * 0.2), r, col, false, 2.0)
		ci.draw_line(c + Vector2(0.0, r * 0.4), c + Vector2(0.0, r * 1.6), col, 2.0)
