extends Control
# The right-click menu on the street: whatever `SimContext.verbs_at` named for whatever
# `Pick.pick_at` found, drawn through `ItemMenu`'s own layout so a row here and a row in the loot
# sheet cannot drift apart.
#
# Sized exactly to its own rect and its `mouse_filter` toggled between STOP and IGNORE --
# `ui/inventory_panel.gd`'s `_loot_layer` is the precedent, word for word: closed, it ignores the
# mouse entirely and every click still reaches `presentation/input_map.gd`'s `_unhandled_input`
# (a swing at the street behind it); open, it stops the mouse over its own small rect and nowhere
# else, so a click three inches away still swings too rather than being silently eaten by an
# invisible full-screen Control.
#
# This file decides nothing about *what* is on offer -- `main._context_pick` reads the row's own
# `command` Dictionary and pushes it, and the sim decided that Dictionary before this ever drew.
#
# Over the rows, a header names what was clicked (`SimContext.target_label`, handed in by main.gd):
# dim, not a row, not clickable. The keys while it is open, handed over by `input_map.gd`: Up and
# Down move an amber ring between the rows, Enter dispatches the ringed row through the same
# `main._context_pick` a click uses, Escape closes it with nothing dispatched. The ring opens on the
# first row, so Enter straight away does what the first row says -- the row the action bar's E
# clause names whenever the clicked thing is the one in reach.

const ItemMenu = preload("res://ui/item_menu.gd")
const Locker = preload("res://ui/locker.gd")

# Set by main.gd before `add_child`, `Variant` for the reason `input_map.gd`'s own `main` field
# is: this script preloads nothing that would preload it back, but naming the type here would
# still make main.gd's own preload of *this* file a cycle the moment main.gd typed the field.
var main: Variant = null

var _rows: Array[Dictionary] = []
var _header: String = ""
var _focus: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func is_open() -> bool:
	return visible


func rows() -> Array[Dictionary]:
	return _rows


func header() -> String:
	return _header


# The ringed row, the one Enter would dispatch.
func focused() -> int:
	return _focus


# Each row's rect in this control's own frame, the same `ItemMenu.verb_rects` the draw and the
# press use -- for a gate or a caller that has to click a row it found by its words.
func row_rects() -> Array[Dictionary]:
	return ItemMenu.verb_rects(Vector2.ZERO, _texts(), _header)


# `rows_in` empty opens nothing -- the caller (`input_map.gd`) already knows this from
# `SimContext.verbs_at` coming back empty, but a menu that could draw zero rows and sit there
# eating clicks over a wall tile would be its own small bug, so the guard is here too.
func open(at: Vector2, rows_in: Array[Dictionary], header_in: String = "") -> void:
	if rows_in.is_empty():
		close()
		return
	_rows = rows_in
	_header = header_in
	_focus = 0
	var sz: Vector2 = ItemMenu.size_of(_texts(), _header)
	var view: Vector2 = get_viewport_rect().size
	position = Vector2(clampf(at.x, 0.0, maxf(0.0, view.x - sz.x)), clampf(at.y, 0.0, maxf(0.0, view.y - sz.y)))
	size = sz
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = true
	queue_redraw()


func close() -> void:
	if _rows.is_empty() and not visible:
		return
	_rows = []
	_header = ""
	_focus = 0
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _texts() -> Array:
	var out: Array = []
	for r in _rows:
		out.append(String((r as Dictionary).get("text", "")))
	return out


func _draw() -> void:
	ItemMenu.draw_menu(self, Vector2.ZERO, _texts(), 1.0, _header)
	var rects: Array[Dictionary] = row_rects()
	if _focus >= 0 and _focus < rects.size():
		var r: Rect2 = rects[_focus]["rect"] as Rect2
		Locker.rim(self, Rect2(r.position + Vector2(Locker.PX * 3.0, 0.0), r.size - Vector2(Locker.PX * 6.0, 0.0)), Locker.ACCENT)


# A key while the menu is open, from `input_map.gd`. True when the key was the menu's: Up and Down
# move the ring and wrap, Enter dispatches the ringed row, Escape closes with nothing dispatched.
# Any other key is not the menu's, and the caller closes it and lets the key do what it does.
func key(ke: InputEventKey) -> bool:
	if not visible or _rows.is_empty():
		return false
	match ke.keycode:
		KEY_UP:
			_focus = (_focus - 1 + _rows.size()) % _rows.size()
			queue_redraw()
			return true
		KEY_DOWN:
			_focus = (_focus + 1) % _rows.size()
			queue_redraw()
			return true
		KEY_ENTER, KEY_KP_ENTER:
			var picked: Dictionary = _rows[clampi(_focus, 0, _rows.size() - 1)]
			close()
			if main != null and main.has_method("_context_pick"):
				main.call("_context_pick", picked)
			return true
		KEY_ESCAPE:
			close()
			return true
	return false


# Which pointer the kit dresses the mouse in at `p`, in this control's own frame (ui/cursors.gd):
# the hand over a verb, the arrow over the menu's padding. The rows are `ItemMenu.verb_rects`, the
# same rects a press is tested against, so the hand and the pick cannot disagree about a row.
func cursor_at(p: Vector2) -> int:
	for row in row_rects():
		if (row["rect"] as Rect2).has_point(p):
			return Input.CURSOR_POINTING_HAND
	return Input.CURSOR_ARROW


# Every press this control receives closes it -- a row picks first when the press landed on one,
# and either way the event is consumed here rather than falling through to `_unhandled_input`,
# which is what keeps a click on the menu from also swinging at whatever is behind it.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var at: Vector2 = (event as InputEventMouseMotion).position
		mouse_default_cursor_shape = cursor_at(at) as Control.CursorShape
		# The ring follows the pointer, so the hand and the ring never name two rows.
		var rects_m: Array[Dictionary] = row_rects()
		for i in rects_m.size():
			if (rects_m[i]["rect"] as Rect2).has_point(at) and i != _focus:
				_focus = i
				queue_redraw()
		return
	if not (event is InputEventMouseButton) or not (event as InputEventMouseButton).pressed:
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	accept_event()
	var picked: Dictionary = {}
	if mb.button_index == MOUSE_BUTTON_LEFT:
		var rects: Array[Dictionary] = row_rects()
		for i in rects.size():
			if (rects[i]["rect"] as Rect2).has_point(mb.position):
				picked = _rows[i]
				break
	close()
	if not picked.is_empty() and main != null and main.has_method("_context_pick"):
		main.call("_context_pick", picked)
