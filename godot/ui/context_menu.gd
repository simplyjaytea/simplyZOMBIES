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

const ItemMenu = preload("res://ui/item_menu.gd")

# Set by main.gd before `add_child`, `Variant` for the reason `input_map.gd`'s own `main` field
# is: this script preloads nothing that would preload it back, but naming the type here would
# still make main.gd's own preload of *this* file a cycle the moment main.gd typed the field.
var main: Variant = null

var _rows: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func is_open() -> bool:
	return visible


func rows() -> Array[Dictionary]:
	return _rows


# `rows_in` empty opens nothing -- the caller (`input_map.gd`) already knows this from
# `SimContext.verbs_at` coming back empty, but a menu that could draw zero rows and sit there
# eating clicks over a wall tile would be its own small bug, so the guard is here too.
func open(at: Vector2, rows_in: Array[Dictionary]) -> void:
	if rows_in.is_empty():
		close()
		return
	_rows = rows_in
	var sz: Vector2 = ItemMenu.size_of(_texts())
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
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _texts() -> Array:
	var out: Array = []
	for r in _rows:
		out.append(String((r as Dictionary).get("text", "")))
	return out


func _draw() -> void:
	ItemMenu.draw_menu(self, Vector2.ZERO, _texts(), 1.0)


# Every press this control receives closes it -- a row picks first when the press landed on one,
# and either way the event is consumed here rather than falling through to `_unhandled_input`,
# which is what keeps a click on the menu from also swinging at whatever is behind it.
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not (event as InputEventMouseButton).pressed:
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	accept_event()
	var picked: Dictionary = {}
	if mb.button_index == MOUSE_BUTTON_LEFT:
		var rects: Array[Dictionary] = ItemMenu.verb_rects(Vector2.ZERO, _texts())
		for i in rects.size():
			if (rects[i]["rect"] as Rect2).has_point(mb.position):
				picked = _rows[i]
				break
	close()
	if not picked.is_empty() and main != null and main.has_method("_context_pick"):
		main.call("_context_pick", picked)
