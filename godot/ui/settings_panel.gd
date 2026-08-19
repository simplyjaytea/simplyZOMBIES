extends Control
# The settings sheet, on Escape. Presentation preferences only -- how the screens look,
# never what the world is -- so everything here writes ui/prefs.gd and nothing touches the
# sim. Sliders carry no numerals: the handle's position is the readout, which keeps this
# panel inside the same no-digits spirit the HUD is gated on even though the gate does not
# reach it.

const Chrome = preload("res://ui/chrome.gd")
const UiPrefs = preload("res://ui/prefs.gd")

const PANEL_SIZE: Vector2 = Vector2(640, 330)
const ROW_H: float = 72.0
const TRACK_W: float = 300.0
const TRACK_H: float = 6.0
const HANDLE_R: float = 11.0

# Each row is one preference; min is the floor prefs.gd clamps to anyway.
const ROWS: Array[Dictionary] = [
	{"key": "inventory_opacity", "label": "inventory panels"},
	{"key": "pinned_opacity", "label": "pinned bags"},
]

# Called with no arguments after a value changes, so open screens can re-tint immediately.
var on_changed: Callable = Callable()

var _drag_row: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = get_viewport_rect().size


func _panel_rect() -> Rect2:
	var view: Vector2 = get_viewport_rect().size
	return Rect2(((view - PANEL_SIZE) / 2.0).round(), PANEL_SIZE)


func _track_rect(row: int) -> Rect2:
	var p: Rect2 = _panel_rect()
	var y: float = p.position.y + Chrome.HEADER_H + 44.0 + float(row) * ROW_H + 26.0
	return Rect2(Vector2(p.position.x + PANEL_SIZE.x - 40.0 - TRACK_W, y), Vector2(TRACK_W, TRACK_H))


func _set_from(row: int, x: float) -> void:
	var track: Rect2 = _track_rect(row)
	var t: float = clampf((x - track.position.x) / track.size.x, 0.0, 1.0)
	UiPrefs.set_opacity(String(ROWS[row]["key"]), lerpf(0.15, 1.0, t))
	if on_changed.is_valid():
		on_changed.call()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			for i in ROWS.size():
				var track: Rect2 = _track_rect(i).grow_individual(HANDLE_R, HANDLE_R * 2.0, HANDLE_R, HANDLE_R * 2.0)
				if track.has_point(mb.position):
					_drag_row = i
					_set_from(i, mb.position.x)
					break
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_drag_row = -1
			accept_event()
	elif event is InputEventMouseMotion and _drag_row != -1:
		_set_from(_drag_row, (event as InputEventMouseMotion).position.x)
		accept_event()


func _draw() -> void:
	var view: Vector2 = get_viewport_rect().size
	size = view
	var dim: Color = Chrome.FIELD
	dim.a = 0.72
	draw_rect(Rect2(Vector2.ZERO, view), dim)
	var p: Rect2 = _panel_rect()
	Chrome.panel(self, p, 0.97)
	Chrome.header(self, p, "settings", 0.97)
	var font: Font = Chrome.font()
	for i in ROWS.size():
		var label_y: float = p.position.y + Chrome.HEADER_H + 44.0 + float(i) * ROW_H + 34.0
		draw_string(font, Vector2(p.position.x + 40.0, label_y), String(ROWS[i]["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Chrome.TEXT)
		var track: Rect2 = _track_rect(i)
		draw_rect(track, Chrome.CELL_EDGE)
		var t: float = inverse_lerp(0.15, 1.0, UiPrefs.opacity(String(ROWS[i]["key"])))
		var filled: Rect2 = Rect2(track.position, Vector2(track.size.x * clampf(t, 0.0, 1.0), track.size.y))
		draw_rect(filled, Chrome.ACCENT)
		var handle: Vector2 = track.position + Vector2(track.size.x * clampf(t, 0.0, 1.0), track.size.y / 2.0)
		draw_circle(handle, HANDLE_R, Chrome.TEXT)
		draw_circle(handle, HANDLE_R, Chrome.ACCENT, false, 2.0)
	var hint_y: float = p.position.y + PANEL_SIZE.y - 28.0
	draw_string(font, Vector2(p.position.x + 40.0, hint_y), "Esc to close · changes apply immediately", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Chrome.TEXT_DIM)
