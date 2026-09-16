extends Control
# The three screens that are not the game: the title, the pause menu, and the one that says the
# run is over.
#
# The owner's decision of 2026-09-16 (docs/30, "The alpha shell"): a title over the already-booted
# world, new run from every screen booting the **fixed default town**, quit to title autosaving
# first, and **no digit anywhere on any of the three**. That last one is why this file has no day
# number on the run-over screen and no slot date on the title: the epitaph is the chronicle's own
# prose, which is digit-free by its contract, and everything else here is a word.
#
# It draws in `ui/chrome.gd`'s skin, like every other screen, so the menu reads as the same piece
# of equipment as the settings sheet and the inventory. Nothing is a `Button`: the rows are drawn
# and their hit rects are kept beside them, for the same reason the rest of this UI is drawn --
# a themed Control would be a second skin to keep in step with the first.
#
# Two ways in, one way out. Keys arrive through `presentation/input_map.gd`'s **`shell` focus**,
# which is at the front of its focus order because this panel sits in front of everything else on
# screen: the router hands the event to `key()` and nothing else in the game sees it. Clicks
# arrive through `_gui_input`. Both end in the same place -- `on_action`, one Callable `main.gd`
# sets, carrying the id of the row that was chosen. This file decides nothing about what a row
# *does*; it only says which one was asked for.
#
# `rows()`, `lines()` and `words()` are the read side, and they exist because `check_hud.gd` has a
# lane that scans every word these screens can draw for a digit. A gate that had to read pixels
# could not do that; a gate that read the source could not tell a drawn string from a comment.

const Chrome = preload("res://ui/chrome.gd")

# The four states, named again here rather than imported from `presentation/session.gd`: this is
# a UI panel and the sim-side lifecycle is not its dependency. `show_state` takes the int.
const TITLE: int = 0
const PLAYING: int = 1
const PAUSED: int = 2
const RUN_OVER: int = 3

const GAME_NAME: String = "simplyZOMBIES"

const PANEL_W: float = 640.0
const ROW_H: float = 56.0
const ROW_GAP: float = 6.0
const PAD: float = 40.0
const TITLE_SIZE: int = 52
const ROW_SIZE: int = 26
const LINE_SIZE: int = 22
const LINE_H: float = 34.0

# The rows each screen offers, as `[id, label]`. Ids are what `on_action` carries and labels are
# what the screen says; they are not the same string because "quit to title" is two words the
# player reads and `quit_to_title` is one token main.gd matches on.
const TITLE_ROWS: Array = [["new_run", "new run"], ["continue", "continue"], ["quit", "quit"]]
const PAUSE_ROWS: Array = [
	["resume", "resume"],
	["save", "save"],
	["load", "load"],
	["settings", "settings"],
	["quit_to_title", "quit to title"],
]
const OVER_ROWS: Array = [["new_run", "new run"], ["quit_to_title", "quit to title"]]

# The heading each screen carries in its chrome header, and the one sentence under the title's
# name. Words, all of them.
const HEADINGS: Dictionary = {TITLE: "", PAUSED: "paused", RUN_OVER: "the run is over"}

var state: int = TITLE
# The chosen row, as an index into `_rows`. Moves on Up/Down and on W/S, wraps at both ends
# because a menu of three rows is not somewhere a player should have to count.
var cursor: int = 0
# Called with the id of the row that was chosen. main.gd sets it; nothing here calls anything
# else, so a shell with no callable is a shell that draws and decides nothing.
var on_action: Callable = Callable()

var _rows: Array = []
var _lines: Array[String] = []
var _notice: String = ""
var _hits: Array[Rect2] = []


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = get_viewport_rect().size


# Raise one of the three screens. `ctx` carries what the shell cannot work out for itself:
# `has_continue` (a save exists and is not a finished run), `epitaph` (the chronicle's last
# lines), `is_web` (the browser owns the tab, so there is nothing for "quit" to do) and `notice`
# (one fixed sentence when a save would not load).
func show_state(next_state: int, ctx: Dictionary) -> void:
	state = next_state
	_notice = String(ctx.get("notice", ""))
	_lines = []
	_rows = []
	match state:
		TITLE:
			var has_continue: bool = bool(ctx.get("has_continue", false))
			var is_web: bool = bool(ctx.get("is_web", false))
			for row in TITLE_ROWS:
				var id: String = String((row as Array)[0])
				if id == "continue" and not has_continue:
					continue
				# Nothing to quit to in a browser tab: the page is the process, and a row that
				# does nothing is worse than a row that is not there.
				if id == "quit" and is_web:
					continue
				_rows.append(row)
		PAUSED:
			_rows = PAUSE_ROWS.duplicate()
		RUN_OVER:
			for line in ctx.get("epitaph", []) as Array:
				var text: String = String(line)
				if not text.is_empty():
					_lines.append(text)
			if _lines.is_empty():
				# The chronicle can be empty -- a run that ended before anything was written down.
				# Something has to be said, and it is a sentence rather than a blank panel.
				_lines.append("There is nobody left to be.")
			_rows = OVER_ROWS.duplicate()
	cursor = 0
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = get_viewport_rect().size
	queue_redraw()


func close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice = ""
	queue_redraw()


# The labels this screen is offering, in order. The read side: `check_play.gd`'s TITLE lane asks
# whether "continue" is among them, and `check_hud.gd`'s lane scans them for a digit.
func rows() -> Array[String]:
	var out: Array[String] = []
	for row in _rows:
		out.append(String((row as Array)[1]))
	return out


# The prose above the rows: the game's name on the title, the epitaph on the run-over screen.
func lines() -> Array[String]:
	return _lines.duplicate()


# Every word this screen would draw, in one array -- the heading, the prose, the rows and the
# notice. This is what the no-digits lane scans, and it exists for the same reason
# `SimSkills.web_map` exists: a screen that can only be judged by its pixels cannot be gated.
func words() -> Array[String]:
	var out: Array[String] = []
	var heading: String = String(HEADINGS.get(state, ""))
	if not heading.is_empty():
		out.append(heading)
	if state == TITLE:
		out.append(GAME_NAME)
	for line in _lines:
		out.append(line)
	for label in rows():
		out.append(label)
	if not _notice.is_empty():
		out.append(_notice)
	out.append(_footer())
	return out


func _footer() -> String:
	return "arrow keys or the mouse · Enter chooses"


# The keys, handed over by the router under its `shell` focus. Returns whether the press was
# used, so the router can say so; every press that reaches here is used, because a menu that
# let a key fall through to the street would be a menu you could shoot through.
func key(ke: InputEventKey) -> bool:
	if not visible or _rows.is_empty():
		return false
	match ke.keycode:
		KEY_UP, KEY_W:
			cursor = (cursor - 1 + _rows.size()) % _rows.size()
			queue_redraw()
			return true
		KEY_DOWN, KEY_S:
			cursor = (cursor + 1) % _rows.size()
			queue_redraw()
			return true
		KEY_ENTER, KEY_KP_ENTER:
			_choose(cursor)
			return true
		KEY_ESCAPE:
			# Escape is not a row: what it means depends on the state, and the state's owner is
			# main.gd. It is sent as its own action rather than resolved here.
			_act("escape")
			return true
	return false


func _choose(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	_act(String((_rows[index] as Array)[0]))


func _act(id: String) -> void:
	# The notice is the answer to one press; it does not survive the next.
	_notice = ""
	if on_action.is_valid():
		on_action.call(id)


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		var at: Vector2 = (event as InputEventMouseMotion).position
		for i in _hits.size():
			if _hits[i].has_point(at):
				if cursor != i:
					cursor = i
					queue_redraw()
				break
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			for i in _hits.size():
				if _hits[i].has_point(mb.position):
					cursor = i
					_choose(i)
					break
			accept_event()


func _panel_rect() -> Rect2:
	var view: Vector2 = get_viewport_rect().size
	var head: float = (TITLE_SIZE + 24.0) if state == TITLE else 0.0
	var prose: float = LINE_H * float(_lines.size())
	var notice: float = LINE_H if not _notice.is_empty() else 0.0
	var body: float = head + prose + float(_rows.size()) * (ROW_H + ROW_GAP) + notice
	var height: float = Chrome.HEADER_H + PAD * 2.0 + body + 30.0
	return Rect2(((view - Vector2(PANEL_W, height)) / 2.0).round(), Vector2(PANEL_W, height))


func _draw() -> void:
	var view: Vector2 = get_viewport_rect().size
	size = view
	# Darker than the settings sheet's wash: the title and the run-over screen are meant to stop
	# the street being the thing you are looking at, where settings is a sheet over a live game.
	var dim: Color = Chrome.FIELD
	dim.a = 0.88
	draw_rect(Rect2(Vector2.ZERO, view), dim)
	var panel: Rect2 = _panel_rect()
	Chrome.panel(self, panel, 0.98)
	var heading: String = String(HEADINGS.get(state, ""))
	if not heading.is_empty():
		Chrome.header(self, panel, heading, 0.98)
	var font: Font = Chrome.font()
	var y: float = panel.position.y + Chrome.HEADER_H + PAD
	if state == TITLE:
		draw_string(font, Vector2(panel.position.x + PAD, y + float(TITLE_SIZE)), GAME_NAME, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, Chrome.ACCENT)
		y += float(TITLE_SIZE) + 24.0
	for line in _lines:
		draw_string(font, Vector2(panel.position.x + PAD, y + LINE_H - 10.0), line, HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - PAD * 2.0, LINE_SIZE, Chrome.TEXT)
		y += LINE_H
	if not _lines.is_empty():
		y += 12.0
	_hits = []
	for i in _rows.size():
		var rect := Rect2(Vector2(panel.position.x + PAD, y), Vector2(panel.size.x - PAD * 2.0, ROW_H))
		_hits.append(rect)
		var chosen: bool = i == cursor
		var fill: Color = Chrome.HEADER if chosen else Chrome.CELL_BG
		draw_rect(rect, fill)
		draw_rect(rect, Chrome.ITEM_EDGE if chosen else Chrome.CELL_EDGE, false, 1.5)
		if chosen:
			# The marker is a bar, not a caret glyph: the fallback font has no reliable arrow and
			# a drawn rectangle reads the same in every locale.
			draw_rect(Rect2(rect.position, Vector2(4.0, rect.size.y)), Chrome.ACCENT)
		draw_string(font, rect.position + Vector2(22.0, ROW_H - 19.0), String((_rows[i] as Array)[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, ROW_SIZE, Chrome.ACCENT if chosen else Chrome.TEXT)
		y += ROW_H + ROW_GAP
	if not _notice.is_empty():
		draw_string(font, Vector2(panel.position.x + PAD, y + LINE_H - 12.0), _notice, HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - PAD * 2.0, LINE_SIZE, Chrome.DANGER)
		y += LINE_H
	draw_string(font, Vector2(panel.position.x + PAD, panel.position.y + panel.size.y - 18.0), _footer(), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Chrome.TEXT_DIM)
