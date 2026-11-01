extends Control
# The ledger's Reports page: what happened at the colony, in the chronicle's own words. Every line is
# `SimChronicle`'s own line builder (`_line_of`, the one the HUD and the run-over screen read), so the page
# cannot say an event differently and cannot say one the record does not hold. Newest first, at most
# REPORTS_MAX lines. An entry written after the player's read mark is marked new, in words.
#
# Presentation only. The read mark belongs to the caller (`presentation/first_person/first_person.gd`), and
# this page reads the world and writes nothing to it. No digit: the chronicle's lines have none, the tags are
# words, and the page shows no day counter (the top-down chronicle shows none either).

const Chrome = preload("res://ui/chrome.gd")
const Locker = preload("res://ui/locker.gd")
const SimChronicle = preload("res://sim/modules/chronicle.gd")

const REPORTS_MAX: int = 12
const TITLE: String = "Reports"
const NEW_TAG: String = "since you last looked"
const NEW_CHIP: String = "new"
const EMPTY_LINE: String = "No reports."
const WIDTH: float = 720.0
const PAD: float = 24.0
const ROW_GAP: float = 6.0
const BODY_SIZE: int = 25
const TAG_SIZE: int = 20

# A row of the page: the chronicle's text, and whether it was written after the player's read mark.
var _rows: Array[Dictionary] = []
var _unread: int = 0


## The rows the page shows for `world` given the player's read mark, newest first. Pure: it reads the
## chronicle and writes nothing. An entry is new when its index is at or past `read`.
static func rows(world: Variant, read: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world == null or not (world.chronicle is Array):
		return out
	var recs: Array = world.chronicle as Array
	for i in range(recs.size() - 1, -1, -1):
		var line: String = SimChronicle._line_of(world, recs[i] as Dictionary)
		if line.is_empty():
			continue
		out.append({"text": line, "new": i >= read})
		if out.size() >= REPORTS_MAX:
			break
	return out


## How many entries were written after the read mark. The prompt reads this, so it is the whole record,
## not only the rows the page can show.
static func unread(world: Variant, read: int) -> int:
	if world == null or not (world.chronicle is Array):
		return 0
	return maxi(0, (world.chronicle as Array).size() - read)


## Sets what the page shows. `read` is the mark before this viewing; the caller moves the mark after.
func show_reports(world: Variant, read: int) -> void:
	_rows = rows(world, read)
	_unread = unread(world, read)
	custom_minimum_size = Vector2(WIDTH, natural_height())
	size = custom_minimum_size
	queue_redraw()


## The rows as shown, for the gate: text and whether each is new.
func shown() -> Array[Dictionary]:
	return _rows


func unread_count() -> int:
	return _unread


func has_new() -> bool:
	for row in _rows:
		if bool(row["new"]):
			return true
	return false


## The height the page needs for its rows, so the caller can place it.
func natural_height() -> float:
	var body: float = Chrome.line_height(BODY_SIZE) + ROW_GAP
	var tag: float = Chrome.line_height(TAG_SIZE) + ROW_GAP if has_new() else 0.0
	var rows_h: float = maxf(1.0, float(_rows.size())) * body
	return Chrome.HEADER_H + PAD + tag + rows_h + PAD


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	Chrome.panel(self, rect, 1.0)
	var y: float = Chrome.header(self, rect, TITLE, 1.0)
	var font: Font = Chrome.font()
	var body_base: float = Chrome.ascent(BODY_SIZE)
	var tag_base: float = Chrome.ascent(TAG_SIZE)
	y += PAD
	if _rows.is_empty():
		draw_string(font, Vector2(PAD, y + body_base), EMPTY_LINE, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, Chrome.TEXT_DIM)
		return
	if has_new():
		draw_string(font, Vector2(PAD, y + tag_base), NEW_TAG, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_SIZE, Chrome.ACCENT)
		y += Chrome.line_height(TAG_SIZE) + ROW_GAP
	var row_h: float = Chrome.line_height(BODY_SIZE)
	for row in _rows:
		var is_new: bool = bool(row["new"])
		var ink: Color = Chrome.ACCENT if is_new else Chrome.TEXT
		draw_string(font, Vector2(PAD, y + body_base), String(row["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, ink)
		if is_new:
			var tag_w: float = ceilf(font.get_string_size(NEW_CHIP, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_SIZE).x) + 16.0
			Locker.chip(self, Rect2(Vector2(rect.size.x - PAD - tag_w, y), Vector2(tag_w, row_h)), NEW_CHIP, true, 1.0, TAG_SIZE)
		y += row_h + ROW_GAP


## The button on the ledger that opens this page, in the chrome the work grid's own buttons use. A click
## emits `activated`; it decides nothing.
class Chip extends Control:
	signal activated

	const LABEL: String = "reports"
	const CHIP_H: float = 44.0

	func _ready() -> void:
		var w: float = ceilf(Chrome.font().get_string_size(LABEL, HORIZONTAL_ALIGNMENT_LEFT, -1, Locker.LABEL_SIZE).x) + 40.0
		custom_minimum_size = Vector2(w, CHIP_H)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		Locker.button(self, Rect2(Vector2.ZERO, size), LABEL, false, 1.0)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				accept_event()
				activated.emit()
