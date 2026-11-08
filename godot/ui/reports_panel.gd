extends Control
# The ledger's Reports page: what happened at the colony, in the chronicle's own words. Every line is
# `SimChronicle`'s own line builder (`_line_of`, the one the HUD and the run-over screen read), so the page
# cannot say an event differently and cannot say one the record does not hold. Newest first, REPORTS_MAX
# lines to a page: "older" turns to the next page back, "newer" back toward the newest. An entry written
# after the player's read mark is marked new, in words, wherever its page is.
#
# Once the run is over the page also offers the epitaph: the run-over screen's lines, every one of them,
# paged the same way. Only then; while the colony lives the epitaph is not offered.
#
# Presentation only. The read mark belongs to the caller (`presentation/first_person/first_person.gd`), and
# this page reads the world and writes nothing to it. No digit: the chronicle's lines have none, the labels
# are words, and the page shows no day counter (the top-down chronicle shows none either).

const Chrome = preload("res://ui/chrome.gd")
const Locker = preload("res://ui/locker.gd")
const SimChronicle = preload("res://sim/modules/chronicle.gd")

# The page size, and the cap the epitaph is read with: the whole record, so every epitaph line is in it.
const REPORTS_MAX: int = 12
const EPITAPH_ALL: int = 1000000
const TITLE: String = "Reports"
const EPITAPH_TITLE: String = "Epitaph"
const NEW_TAG: String = "since you last looked"
const NEW_CHIP: String = "new"
const EMPTY_LINE: String = "No reports."
const OLDER_LABEL: String = "older"
const NEWER_LABEL: String = "newer"
const EPITAPH_LABEL: String = "epitaph"
const RECORD_LABEL: String = "record"
const WIDTH: float = 720.0
const PAD: float = 24.0
const ROW_GAP: float = 6.0
const BUTTON_GAP: float = 12.0
const BODY_SIZE: int = 25
const TAG_SIZE: int = 20

enum Mode { RECORD, EPITAPH }

var _mode: int = Mode.RECORD
var _page: int = 0
var _world: Variant = null
var _read: int = 0
var _runover: bool = false
var _unread: int = 0
# Every line of the current mode, newest first, and the rows of the page showing.
var _source: Array[Dictionary] = []
var _rows: Array[Dictionary] = []
var _title: String = TITLE
var _older: PageButton = null
var _newer: PageButton = null
var _mode_button: PageButton = null


## Every line the record holds, newest first, as the page reads it: the chronicle's own builder, and a line the
## builder keeps is kept. Each carries whether its entry was written after the read mark `read` (an entry at or
## past the mark is new). Pure: it reads the chronicle and writes nothing.
static func entries(world: Variant, read: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world == null or not (world.chronicle is Array):
		return out
	var recs: Array = world.chronicle as Array
	for i in range(recs.size() - 1, -1, -1):
		var line: String = SimChronicle._line_of(world, recs[i] as Dictionary)
		if line.is_empty():
			continue
		out.append({"text": line, "new": i >= read})
	return out


## The rows one page shows: page 0 is the newest REPORTS_MAX lines, page 1 the next REPORTS_MAX, and so on.
static func rows(world: Variant, read: int, page: int = 0) -> Array[Dictionary]:
	return _slice(entries(world, read), page)


## The pages `count` lines fill: at least one, so an empty record has a page to say so on.
static func pages_of(count: int) -> int:
	return maxi(1, int(ceil(float(count) / float(REPORTS_MAX))))


## How many pages the record fills.
static func page_count(world: Variant, read: int = 0) -> int:
	return pages_of(entries(world, read).size())


## Every line of the epitaph, newest first: the chronicle's own epitaph read with no cap, so nothing the run-over
## screen would have shown is left out of the page.
static func epitaph_entries(world: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line in SimChronicle.epitaph(world, EPITAPH_ALL):
		out.append({"text": line, "new": false})
	return out


## How many entries were written after the read mark. The prompt reads this, so it is the whole record,
## not only the rows the page can show.
static func unread(world: Variant, read: int) -> int:
	if world == null or not (world.chronicle is Array):
		return 0
	return maxi(0, (world.chronicle as Array).size() - read)


static func _slice(all: Array[Dictionary], page: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var start: int = maxi(0, page) * REPORTS_MAX
	for i in range(start, mini(start + REPORTS_MAX, all.size())):
		out.append(all[i])
	return out


## Opens the record on its newest page. `read` is the mark before this viewing; the caller moves the mark after.
func show_reports(world: Variant, read: int) -> void:
	_world = world
	_read = read
	_runover = world != null and bool(world.runOver)
	_unread = unread(world, read)
	_mode = Mode.RECORD
	_page = 0
	_refresh()


## Turns to the epitaph, when the run is over. Returns false, and changes nothing, while the colony lives.
func show_epitaph() -> bool:
	if _world == null or not _runover:
		return false
	_mode = Mode.EPITAPH
	_page = 0
	_refresh()
	return true


## Turns back to the record, on its newest page.
func show_record() -> void:
	if _world == null:
		return
	_mode = Mode.RECORD
	_page = 0
	_refresh()


## One page back in time, if there is one.
func older() -> void:
	if _page < pages() - 1:
		_page += 1
		_refresh()


## One page forward, toward the newest, if there is one.
func newer() -> void:
	if _page > 0:
		_page -= 1
		_refresh()


## The page showing, from 0 (the newest) up.
func page() -> int:
	return _page


## The pages the current mode fills.
func pages() -> int:
	return pages_of(_source.size())


## "record" or "epitaph": the mode showing.
func mode_name() -> String:
	return "epitaph" if _mode == Mode.EPITAPH else "record"


## Whether the epitaph is offered: only once the run is over.
func epitaph_available() -> bool:
	return _runover


## Whether the "older" or "newer" buttons are showing: true only when the mode fills more than one page.
func paging_visible() -> bool:
	return (_older != null and _older.visible) or (_newer != null and _newer.visible)


## The rows the page shows: text and whether each is new.
func shown() -> Array[Dictionary]:
	return _rows


## Every line of the current mode, not only the page showing: what the page can reach.
func all_lines() -> Array[Dictionary]:
	return _source


func unread_count() -> int:
	return _unread


## Whether the "since you last looked" banner is up: the record has entries past the read mark, in record mode.
func has_new() -> bool:
	return _banner_shown()


func older_button() -> Control:
	return _older


func newer_button() -> Control:
	return _newer


func mode_button() -> Control:
	return _mode_button


## The height the page needs for its rows and buttons, so the caller can place it.
func natural_height() -> float:
	var buttons: float = PageButton.HEIGHT + PAD if _any_button() else 0.0
	return _content_bottom() + buttons


# Where the rows end: the header, the banner if any, and the rows, with the pad under them.
func _content_bottom() -> float:
	var banner: float = Chrome.line_height(TAG_SIZE) + ROW_GAP if _banner_shown() else 0.0
	var body: float = Chrome.line_height(BODY_SIZE) + ROW_GAP
	var rows_h: float = maxf(1.0, float(_rows.size())) * body
	return Chrome.HEADER_H + PAD + banner + rows_h + PAD


func _banner_shown() -> bool:
	return _mode == Mode.RECORD and _unread > 0


func _any_button() -> bool:
	for b in [_older, _newer, _mode_button]:
		if b != null and (b as Control).visible:
			return true
	return false


func _ensure_buttons() -> void:
	if _older != null:
		return
	_older = PageButton.new()
	_older.name = "OlderButton"
	_older.set_label(OLDER_LABEL)
	add_child(_older)
	_older.activated.connect(older)
	_newer = PageButton.new()
	_newer.name = "NewerButton"
	_newer.set_label(NEWER_LABEL)
	add_child(_newer)
	_newer.activated.connect(newer)
	_mode_button = PageButton.new()
	_mode_button.name = "ModeButton"
	add_child(_mode_button)
	_mode_button.activated.connect(_on_mode_pressed)


func _on_mode_pressed() -> void:
	if _mode == Mode.EPITAPH:
		show_record()
	else:
		show_epitaph()


# Recomputes what the page shows from the mode, the page and the read mark, then the size and the buttons.
func _refresh() -> void:
	_ensure_buttons()
	if _mode == Mode.EPITAPH:
		_source = epitaph_entries(_world)
		_title = EPITAPH_TITLE
	else:
		_source = entries(_world, _read)
		_title = TITLE
	_page = clampi(_page, 0, pages() - 1)
	_rows = _slice(_source, _page)
	_place_buttons()
	custom_minimum_size = Vector2(WIDTH, natural_height())
	size = custom_minimum_size
	queue_redraw()


func _place_buttons() -> void:
	var more: bool = pages() > 1
	_older.visible = more and _page < pages() - 1
	_newer.visible = more and _page > 0
	_mode_button.set_label(RECORD_LABEL if _mode == Mode.EPITAPH else EPITAPH_LABEL)
	_mode_button.visible = (_mode == Mode.RECORD and _runover) or _mode == Mode.EPITAPH
	var y: float = _content_bottom()
	var x: float = PAD
	for b in [_newer, _older, _mode_button]:
		var button: PageButton = b as PageButton
		if not button.visible:
			continue
		button.position = Vector2(x, y)
		x += button.size.x + BUTTON_GAP


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	Chrome.panel(self, rect, 1.0)
	var y: float = Chrome.header(self, rect, _title, 1.0)
	var font: Font = Chrome.font()
	var body_base: float = Chrome.ascent(BODY_SIZE)
	var tag_base: float = Chrome.ascent(TAG_SIZE)
	y += PAD
	if _rows.is_empty():
		draw_string(font, Vector2(PAD, y + body_base), EMPTY_LINE, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, Chrome.TEXT_DIM)
		return
	if _banner_shown():
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


## A kit button on the page: a word, drawn in the chrome the ledger's buttons use. A click emits `activated`;
## it decides nothing. Its width follows its word.
class PageButton extends Control:
	signal activated

	const HEIGHT: float = 44.0

	var label: String = ""

	func set_label(text: String) -> void:
		label = text
		var w: float = ceilf(Chrome.font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, Locker.LABEL_SIZE).x) + 40.0
		custom_minimum_size = Vector2(w, HEIGHT)
		size = custom_minimum_size
		queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		Locker.button(self, Rect2(Vector2.ZERO, size), label, false, 1.0)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				accept_event()
				activated.emit()
