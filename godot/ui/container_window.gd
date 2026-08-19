extends Control
# One carried container as its own window: a title bar you can drag, a pin that keeps the
# window on screen while you play, and the grid below. The window owns only window things --
# moving itself, its pin, forwarding input -- while every item decision (what a click picks
# up, where a drop lands, what a command means) belongs to the inventory layer, so drag and
# drop between two windows is one piece of state in one file rather than a negotiation.
#
# Mouse focus in Godot goes to the control that took the press until the button releases,
# so a drag that starts here can end anywhere on screen. Everything item-shaped is therefore
# forwarded to the layer in *layer* coordinates and hit-tested there; this file never
# decides what its own cells mean.

const Chrome = preload("res://ui/chrome.gd")
const UiPrefs = preload("res://ui/prefs.gd")
const UiText = preload("res://ui/text.gd")

const CELL: int = 68
const PAD: float = 12.0
const PIN_W: float = 40.0

var container_id: int = -1
var label: String = ""
var grid_w: int = 0
var grid_h: int = 0
var items: Array = []
var pinned: bool = false
var layer_open: bool = true
var drag_exclude: int = -1
# Quick-access: pockets and anything worn on the belt or vest. A pouch on your front is
# reachable mid-fight, so a pinned quick container stays fully interactive during play;
# a backpack is on your back and needs the inventory open (the owner's call, 2026-08-19).
var quick: bool = false


func interactive() -> bool:
	return layer_open or (pinned and quick)

# All set by the layer at creation. press/release/rightclick receive layer-local points.
var on_press: Callable = Callable()
var on_release: Callable = Callable()
var on_rightclick: Callable = Callable()
var on_pin_toggle: Callable = Callable()
var on_moved: Callable = Callable()

var _win_drag: bool = false
var _win_drag_grab: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func configure(id: int, new_label: String, w: int, h: int, new_items: Array) -> void:
	container_id = id
	label = new_label
	grid_w = w
	grid_h = h
	items = new_items
	custom_minimum_size = Vector2(float(grid_w * CELL) + PAD * 2.0, Chrome.HEADER_H + float(grid_h * CELL) + PAD * 2.0)
	size = custom_minimum_size
	queue_redraw()


func grid_origin() -> Vector2:
	return Vector2(PAD, Chrome.HEADER_H + PAD)


# Which cell a layer-local point lands in, or null when outside this window's grid.
func cell_from_layer(p: Vector2) -> Variant:
	var local: Vector2 = p - position - grid_origin()
	var cx: int = floori(local.x / float(CELL))
	var cy: int = floori(local.y / float(CELL))
	if cx < 0 or cy < 0 or cx >= grid_w or cy >= grid_h:
		return null
	return Vector2i(cx, cy)


func _pin_rect() -> Rect2:
	return Rect2(Vector2(size.x - PIN_W, 0.0), Vector2(PIN_W, Chrome.HEADER_H))


func _alpha() -> float:
	return UiPrefs.opacity("inventory_opacity") if layer_open else UiPrefs.opacity("pinned_opacity")


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		var layer_p: Vector2 = position + mb.position
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if _pin_rect().has_point(mb.position):
				pinned = not pinned
				UiPrefs.set_window(label, position, pinned)
				if on_pin_toggle.is_valid():
					on_pin_toggle.call(self)
				queue_redraw()
			elif mb.position.y < Chrome.HEADER_H:
				_win_drag = true
				_win_drag_grab = mb.position
			elif interactive() and on_press.is_valid():
				on_press.call(layer_p)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if _win_drag:
				_win_drag = false
				UiPrefs.set_window(label, position, pinned)
				if on_moved.is_valid():
					on_moved.call(self)
			elif on_release.is_valid():
				# The layer decides whether a drag was in flight; release routes even when
				# the pointer has left this window, which is exactly the cross-window case.
				on_release.call(layer_p)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if interactive() and on_rightclick.is_valid():
				on_rightclick.call(layer_p)
			accept_event()
	elif event is InputEventMouseMotion and _win_drag:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		var view: Vector2 = get_viewport_rect().size
		var next: Vector2 = position + mm.position - _win_drag_grab
		next.x = clampf(next.x, 0.0, maxf(0.0, view.x - size.x))
		next.y = clampf(next.y, 0.0, maxf(0.0, view.y - Chrome.HEADER_H))
		position = next
		accept_event()


func _draw() -> void:
	var a: float = _alpha()
	var rect := Rect2(Vector2.ZERO, size)
	Chrome.panel(self, rect, a)
	Chrome.header(self, rect, label, a)
	Chrome.pin(self, _pin_rect(), pinned, a)
	var origin: Vector2 = grid_origin()
	for cy in range(grid_h):
		for cx in range(grid_w):
			Chrome.cell(self, Rect2(origin + Vector2(float(cx * CELL) + 2.0, float(cy * CELL) + 2.0), Vector2(float(CELL) - 4.0, float(CELL) - 4.0)), a)
	var font: Font = Chrome.font()
	for it in items:
		var d: Dictionary = it as Dictionary
		if int(d.get("item", -1)) == drag_exclude:
			continue
		var iw: int = int(d.get("w", 1))
		var ih: int = int(d.get("h", 1))
		var at: Vector2 = origin + Vector2(float(int(d.get("x", 0)) * CELL) + 4.0, float(int(d.get("y", 0)) * CELL) + 4.0)
		var plate := Rect2(at, Vector2(float(iw * CELL) - 8.0, float(ih * CELL) - 8.0))
		Chrome.item_plate(self, plate, a)
		# The name, fitted to the plate rather than cut at a character count -- "Fire Axe"
		# must never read as "Fire A".
		var text: String = String(d.get("name", ""))
		if int(d.get("count", 1)) > 1:
			text += " x%d" % int(d.get("count", 1))
		var fitted: String = UiText.fit(font, text, 18, plate.size.x - 12.0)
		var tcol: Color = Chrome.TEXT
		tcol.a = a
		draw_string(font, at + Vector2(6.0, 24.0), fitted, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, tcol)
