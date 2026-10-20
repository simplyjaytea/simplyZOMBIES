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
#
# Since the Salvage Locker (docs/23, "The inventory, redone") a cell is thirty art pixels -- sixty
# on screen at the world's 2x -- so an item's 32 px picture, whose painted part is about 28 px, sits
# in a single cell at exactly the pixel size the same thing has on the floor. The look is
# `ui/locker.gd`'s; this file is where a container's panel, cells and plates go.

const Chrome = preload("res://ui/chrome.gd")
const Locker = preload("res://ui/locker.gd")
const UiText = preload("res://ui/text.gd")
const Appearance = preload("res://presentation/appearance.gd")
const ItemPicture = preload("res://ui/item_picture.gd")
const Motion = preload("res://ui/motion.gd")

const CELL: int = 60
# The panel's side and bottom margin round its cells, and the header strip above them.
const PAD: float = 8.0
const HEAD: float = Locker.HEAD_H
const NAME_SIZE: int = 20
const COUNT_SIZE: int = 20
# A plate sits a pixel inside the cells it covers, so the grid's lines show between two plates.
const INSET: float = Locker.PX


# The panel one grid needs, header included.
static func size_of(w: int, h: int) -> Vector2:
	return Vector2(float(w * CELL) + PAD * 2.0, HEAD + float(h * CELL) + PAD)


# Where the cells start inside a panel drawn at `at`.
static func origin_of(at: Vector2) -> Vector2:
	return at + Vector2(PAD, HEAD)


# The content class of what an item is, "" when the world cannot say: what its plate is tinted by.
static func class_of(world: Variant, base_id: String) -> String:
	if world == null or base_id.is_empty():
		return ""
	return String(Appearance.entry_of(world, "item", base_id).get("class", ""))


# The whole thing: panel, header, empty cells, then the items. `exclude` is the item being dragged,
# which is drawn under the cursor instead of in its old home. `matches` is the list's filter, as a
# Callable over an item view: a plate it refuses is drawn faded -- never hidden, because a filtered
# grid must not turn an occupied cell into what looks like room (docs/32).
static func draw_bag(ci: CanvasItem, at: Vector2, column: Dictionary, alpha: float, exclude: int, note: String, world: Variant = null, matches: Callable = Callable()) -> void:
	var w: int = int(column.get("w", 0))
	var h: int = int(column.get("h", 0))
	var rect := Rect2(at, size_of(w, h))
	Locker.panel(ci, rect, alpha)
	# The kit's inventory glyph, small, at the far end of the header: which kind of panel this is,
	# said the way every other kit screen says it. The note sits to its left.
	var glyph_at := Vector2(rect.end.x - Chrome.GLYPH_SMALL - Locker.PX * 5.0, rect.position.y + Locker.PX * 2.0 + floorf((Locker.TAPE_H - Chrome.GLYPH_SMALL) / 2.0))
	Locker.header(ci, rect, String(column.get("label", "")), alpha, note, Chrome.GLYPH_SMALL + Locker.PX * 3.0)
	Chrome.glyph(ci, "inventory", glyph_at, true, alpha * 0.7)
	var origin: Vector2 = origin_of(at)
	Locker.cells(ci, origin, w, h, CELL, alpha)
	for entry in column.get("items", []) as Array:
		var d: Dictionary = entry as Dictionary
		if int(d.get("item", -1)) == exclude:
			continue
		var faded: bool = matches.is_valid() and not bool(matches.call(d))
		draw_item(ci, origin, d, alpha * (0.3 if faded else 1.0), false, world)


# The plate an item view covers, with its top-left cell at `origin`: its cells, a pixel in.
static func plate_rect(origin: Vector2, d: Dictionary) -> Rect2:
	var at: Vector2 = origin + Vector2(float(int(d.get("x", 0)) * CELL), float(int(d.get("y", 0)) * CELL))
	return Rect2(at + Vector2(INSET, INSET), Vector2(float(int(d.get("w", 1)) * CELL), float(int(d.get("h", 1)) * CELL)) - Vector2(INSET, INSET) * 2.0)


# One item plate. `highlight` is the selection ring the inspect pane's subject wears, so what the
# pane is talking about and what you clicked cannot look like two different things. `focus_s` is
# how long, in wall-clock seconds the caller measured, that ring has been on this item: with a
# highlight and a `focus_s` of nought or more, the kit's focus pulse breathes around the plate
# (`ui/motion.gd`), and the frame it drew is returned so the caller can redraw only when that
# frame turns over. -1 when no pulse was drawn. This file is statics and keeps no clock of its own.
static func draw_item(ci: CanvasItem, origin: Vector2, d: Dictionary, alpha: float, highlight: bool, world: Variant = null, focus_s: float = -1.0) -> int:
	var plate: Rect2 = plate_rect(origin, d)
	var base: String = String(d.get("baseId", ""))
	Locker.plate(ci, plate, class_of(world, base), alpha)
	# The picture, through the same resolver the floor uses: a thing in a bag and the same thing
	# dropped on the ground must not be able to look like two different objects -- and, since the
	# Salvage Locker, not two different pixel sizes either.
	if world != null:
		var look: Dictionary = Appearance.item_look(world, base)
		ItemPicture.draw(ci, plate.grow(-Locker.PX), look, alpha)
	# A name only on a plate two cells wide or more: on one cell "Kitchen Knife" trims to "Kit…",
	# which looks like a defect and says less than the picture already does. The list and the
	# inspect pane are where the name lives.
	var font: Font = Chrome.font()
	var name: String = String(d.get("name", ""))
	if plate.size.x >= float(CELL) * 1.5:
		Locker.text_shadowed(ci, plate.position + Vector2(Locker.PX * 3.0, Locker.PX * 2.0 + Chrome.ascent(NAME_SIZE)), UiText.fit(font, name, NAME_SIZE, plate.size.x - Locker.PX * 10.0), NAME_SIZE, Locker.TEXT, alpha)
	# The one number on this screen, and docs/10 says why it is allowed: counting discrete objects
	# is not uncertainty being collapsed. Drawn in the corner in the accent so it reads as a tally
	# rather than as a measurement of the item.
	var count: int = int(d.get("count", 1))
	if count > 1:
		var tally: String = "x%d" % count
		var cw: float = font.get_string_size(tally, HORIZONTAL_ALIGNMENT_LEFT, -1, COUNT_SIZE).x
		Locker.text_shadowed(ci, plate.end - Vector2(cw + Locker.PX * 2.0, Locker.PX * 2.0), tally, COUNT_SIZE, Locker.ACCENT, alpha)
	if highlight:
		Locker.selected(ci, plate, alpha)
	# The pulse last, over the picture and the name, so its brackets are never painted under them.
	if highlight and focus_s >= 0.0:
		return Motion.draw_focus(ci, plate, focus_s, Motion.reduced(), minf(1.0, alpha + 0.1))
	return -1


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
