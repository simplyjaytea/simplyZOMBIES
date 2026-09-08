extends RefCounted
# One container's grid, drawn. Statics on a CanvasItem rather than a Control of its own, for the
# reason the windows this replaced eventually proved: mouse focus in Godot pins an event to the
# control that took the press, so a drag beginning in one bag and ending in another had to be
# forwarded, translated and re-hit-tested by hand. One Control owns the whole sheet now, every
# grid is drawn into it, and a drop is tested against every grid in one pass.
#
# The cell is a constant. It is tempting to size it to the column so a nine-row pack always fits,
# and it would be wrong: a footprint is docs/10's honest picture of capacity ("you see that the
# axe no longer fits"), and an axe that is four cells tall in one bag and three in another is a
# picture that has stopped being about the shape of the thing.

const Chrome = preload("res://ui/chrome.gd")
const UiText = preload("res://ui/text.gd")

const CELL: int = 56
const PAD: float = 10.0
const NAME_SIZE: int = 15
const COUNT_SIZE: int = 15


# The panel one grid needs, header included.
static func size_of(w: int, h: int) -> Vector2:
	return Vector2(float(w * CELL) + PAD * 2.0, Chrome.HEADER_H + float(h * CELL) + PAD * 2.0)


# Where the cells start inside a panel drawn at `at`.
static func origin_of(at: Vector2) -> Vector2:
	return at + Vector2(PAD, Chrome.HEADER_H + PAD)


# The whole thing: panel, header, empty cells, then the items. `exclude` is the item being dragged,
# which is drawn under the cursor instead of in its old home.
static func draw_bag(ci: CanvasItem, at: Vector2, column: Dictionary, alpha: float, exclude: int, note: String) -> void:
	var w: int = int(column.get("w", 0))
	var h: int = int(column.get("h", 0))
	var rect := Rect2(at, size_of(w, h))
	Chrome.panel(ci, rect, alpha)
	Chrome.header(ci, rect, String(column.get("label", "")), alpha)
	var font: Font = Chrome.font()
	if not note.is_empty():
		var nw: float = font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x
		ci.draw_string(font, at + Vector2(rect.size.x - nw - 12.0, Chrome.HEADER_H - 14.0), note, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE, Chrome.TEXT_DIM)
	var origin: Vector2 = origin_of(at)
	for cy in range(h):
		for cx in range(w):
			Chrome.cell(ci, Rect2(origin + Vector2(float(cx * CELL) + 2.0, float(cy * CELL) + 2.0), Vector2(float(CELL) - 4.0, float(CELL) - 4.0)), alpha)
	for entry in column.get("items", []) as Array:
		var d: Dictionary = entry as Dictionary
		if int(d.get("item", -1)) == exclude:
			continue
		draw_item(ci, origin, d, alpha, false)


# One item plate. `highlight` is the selection ring the inspect pane's subject wears, so what the
# pane is talking about and what you clicked cannot look like two different things.
static func draw_item(ci: CanvasItem, origin: Vector2, d: Dictionary, alpha: float, highlight: bool) -> void:
	var iw: int = int(d.get("w", 1))
	var ih: int = int(d.get("h", 1))
	var at: Vector2 = origin + Vector2(float(int(d.get("x", 0)) * CELL) + 4.0, float(int(d.get("y", 0)) * CELL) + 4.0)
	var plate := Rect2(at, Vector2(float(iw * CELL) - 8.0, float(ih * CELL) - 8.0))
	Chrome.item_plate(ci, plate, alpha)
	if highlight:
		var ring: Color = Chrome.ACCENT
		ring.a = minf(1.0, alpha + 0.1)
		ci.draw_rect(plate, ring, false, 2.0)
	# A name only where enough of one fits to be read. On a single cell "Kitchen Knife" trims to
	# "Kit…", which looks like a defect and says less than the footprint already does; the inspect
	# pane is where the name lives, and the glyph is what a one-cell plate carries.
	var font: Font = Chrome.font()
	var name: String = String(d.get("name", ""))
	if plate.size.x >= float(CELL) * 1.5 or font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x <= plate.size.x - 10.0:
		var tcol: Color = Chrome.TEXT
		tcol.a = alpha
		ci.draw_string(font, at + Vector2(5.0, 20.0), UiText.fit(font, name, NAME_SIZE, plate.size.x - 10.0), HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE, tcol)
	# The one number on this screen, and docs/10 says why it is allowed: counting discrete objects
	# is not uncertainty being collapsed. Drawn in the corner in the accent so it reads as a tally
	# rather than as a measurement of the item.
	var count: int = int(d.get("count", 1))
	if count > 1:
		var tally: String = "x%d" % count
		var cw: float = font.get_string_size(tally, HORIZONTAL_ALIGNMENT_LEFT, -1, COUNT_SIZE).x
		var ccol: Color = Chrome.ACCENT
		ccol.a = alpha
		ci.draw_string(font, at + plate.size - Vector2(cw + 4.0, 4.0), tally, HORIZONTAL_ALIGNMENT_LEFT, -1, COUNT_SIZE, ccol)


# Which cell a point lands in, or null when it is outside this grid. `at` is where the panel was
# drawn, so the caller passes the same value it drew with and there is no second copy of the
# layout arithmetic to drift.
static func cell_at(at: Vector2, column: Dictionary, p: Vector2) -> Variant:
	var origin: Vector2 = origin_of(at)
	var local: Vector2 = p - origin
	var cx: int = floori(local.x / float(CELL))
	var cy: int = floori(local.y / float(CELL))
	if cx < 0 or cy < 0 or cx >= int(column.get("w", 0)) or cy >= int(column.get("h", 0)):
		return null
	return Vector2i(cx, cy)


# The item view occupying a cell, or null. Footprints, so a click anywhere on a four-cell axe
# finds the axe.
static func item_at(column: Dictionary, cell: Vector2i) -> Variant:
	for entry in column.get("items", []) as Array:
		var d: Dictionary = entry as Dictionary
		var rx: int = int(d.get("x", 0))
		var ry: int = int(d.get("y", 0))
		if cell.x >= rx and cell.x < rx + int(d.get("w", 1)) and cell.y >= ry and cell.y < ry + int(d.get("h", 1)):
			return d
	return null
