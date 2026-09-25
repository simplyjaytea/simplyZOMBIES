extends Control
# The settings sheet, on Escape. Presentation preferences only -- how the screens look,
# never what the world is -- so everything here writes ui/prefs.gd and nothing touches the
# sim. Sliders carry no numerals: the handle's position is the readout, which keeps this
# panel inside the same no-digits spirit the HUD is gated on even though the gate does not
# reach it.

const Chrome = preload("res://ui/chrome.gd")
const Kit = preload("res://ui/kit.gd")
const UiPrefs = preload("res://ui/prefs.gd")

# Tall enough for every row below -- the two sliders and the one toggle -- at ROW_H each.
const PANEL_SIZE: Vector2 = Vector2(640, 402)
const ROW_H: float = 72.0
const TRACK_W: float = 300.0
const TRACK_H: float = 6.0
const HANDLE_R: float = 11.0

# The rail is a control, not a chrome nine-slice -- it has no `nine_slice_ltrb` in the manifest,
# so `godot:check:ui_skin`'s KIT lane does not hold it, and this file draws it by hand: two end
# caps at the texture's own pixels and a stretched middle, the way a pill-shaped rail with rounded
# ends has to be drawn without a nine-slice declaring where the ends stop.
const RAIL_PATH: String = "controls/control_slider_rail.png"
const RAIL_CAP_W: float = 4.0

# Each row is one preference, and the floor it clamps to lives in `ui/prefs.gd`'s FLOORS -- the
# panel draws the handle between that floor and one, so the two cannot disagree about where the
# leftmost notch is. The pinned-bag row went with the pinnable bags in the 2026-09-08 overhaul --
# there is nothing left to pin. The volume row is the alpha shell's (docs/30, 2026-09-16) and it
# is the first thing in the tree that reaches `AudioServer`, through `presentation/sfx.gd`.
const ROWS: Array[Dictionary] = [
	{"key": "inventory_opacity", "label": "panel opacity"},
	{"key": "volume", "label": "volume"},
]

# The on/off rows, laid out under the sliders at the same ROW_H, each a flag in `ui/prefs.gd`. The
# one switch this game has wears the kit's toggle (docs/30, "The UI Field Kit, live": checkbox and
# radio stay unused), drawn at the chrome's scale -- a control with no `nine_slice_ltrb`, so it is
# a picture, never stretched. Reduced motion stands every UI animation still (`ui/motion.gd`).
const TOGGLES: Array[Dictionary] = [
	{"key": "reduced_motion", "label": "reduced motion"},
]
const TOGGLE_ON_PATH: String = "controls/control_toggle_on.png"
const TOGGLE_OFF_PATH: String = "controls/control_toggle_off.png"
# The toggle's native size in kit pixels (manifest.json's 32 x 16), so the row can lay it out
# before, and without, the picture resolving.
const TOGGLE_NATIVE: Vector2 = Vector2(32, 16)

# Called with no arguments after a value changes, so open screens can re-tint immediately.
var on_changed: Callable = Callable()

var _drag_row: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = get_viewport_rect().size


func _panel_rect() -> Rect2:
	var view: Vector2 = get_viewport_rect().size
	return Rect2(((view - PANEL_SIZE) / 2.0).round(), PANEL_SIZE)


# The top of layout row `row`: the sliders first, then the toggles, one ROW_H apart.
func _row_top(row: int) -> float:
	return _panel_rect().position.y + Chrome.HEADER_H + 44.0 + float(row) * ROW_H


func _track_rect(row: int) -> Rect2:
	var p: Rect2 = _panel_rect()
	var y: float = _row_top(row) + 26.0
	return Rect2(Vector2(p.position.x + PANEL_SIZE.x - 40.0 - TRACK_W, y), Vector2(TRACK_W, TRACK_H))


# Where toggle `index` is drawn and where a press flips it -- one rect for both, so the switch you
# can see and the switch the mouse answers to cannot drift apart. Right-aligned with the slider
# tracks' right end, centred on the line they sit on.
func _toggle_rect(index: int) -> Rect2:
	var p: Rect2 = _panel_rect()
	var sz: Vector2 = TOGGLE_NATIVE * float(Kit.SCALE)
	var mid_y: float = _row_top(ROWS.size() + index) + 26.0 + TRACK_H / 2.0
	return Rect2(Vector2(p.position.x + PANEL_SIZE.x - 40.0 - sz.x, roundf(mid_y - sz.y / 2.0)), sz)


# Flip toggle `index`'s flag, the one writer of it, and tell the open screens. A click on the
# toggle's rect lands here.
func toggle(index: int) -> void:
	if index < 0 or index >= TOGGLES.size():
		return
	var key: String = String(TOGGLES[index]["key"])
	UiPrefs.set_flag(key, not UiPrefs.flag(key))
	if on_changed.is_valid():
		on_changed.call()
	queue_redraw()


# Where the leftmost notch of a row sits. Read off prefs rather than the old literal 0.15: the
# volume row's floor is nought, because mute is a setting and a volume you cannot turn off is the
# same mistake as a legend you cannot dismiss.
func _floor_of(row: int) -> float:
	return float(UiPrefs.FLOORS.get(String(ROWS[row]["key"]), 0.0))


func _set_from(row: int, x: float) -> void:
	var track: Rect2 = _track_rect(row)
	var t: float = clampf((x - track.position.x) / track.size.x, 0.0, 1.0)
	UiPrefs.set_level(String(ROWS[row]["key"]), lerpf(_floor_of(row), 1.0, t))
	if on_changed.is_valid():
		on_changed.call()
	queue_redraw()


# Where a press takes hold of a row's slider: the track, grown by the handle's reach. One rect for
# the press and the pointer, so the hand shows exactly where a press would grab.
func _grab_rect(row: int) -> Rect2:
	return _track_rect(row).grow_individual(HANDLE_R, HANDLE_R * 2.0, HANDLE_R, HANDLE_R * 2.0)


# Which pointer the kit dresses the mouse in at `p` (ui/cursors.gd): the hand over a slider a press
# would take hold of and a toggle a press would flip, and all the way through a drag that has one,
# the arrow everywhere else.
func cursor_at(p: Vector2) -> int:
	if _drag_row != -1:
		return Input.CURSOR_POINTING_HAND
	for i in ROWS.size():
		if _grab_rect(i).has_point(p):
			return Input.CURSOR_POINTING_HAND
	for j in TOGGLES.size():
		if _toggle_rect(j).has_point(p):
			return Input.CURSOR_POINTING_HAND
	return Input.CURSOR_ARROW


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			for i in ROWS.size():
				var track: Rect2 = _grab_rect(i)
				if track.has_point(mb.position):
					_drag_row = i
					_set_from(i, mb.position.x)
					break
			for j in TOGGLES.size():
				if _toggle_rect(j).has_point(mb.position):
					toggle(j)
					break
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_drag_row = -1
			accept_event()
	elif event is InputEventMouseMotion and _drag_row != -1:
		_set_from(_drag_row, (event as InputEventMouseMotion).position.x)
		accept_event()
	if event is InputEventMouse:
		mouse_default_cursor_shape = cursor_at((event as InputEventMouse).position) as Control.CursorShape


func _draw() -> void:
	var view: Vector2 = get_viewport_rect().size
	size = view
	var dim: Color = Chrome.FIELD
	dim.a = 0.72
	draw_rect(Rect2(Vector2.ZERO, view), dim)
	var p: Rect2 = _panel_rect()
	Chrome.panel(self, p, 0.97)
	Chrome.header(self, p, "settings", 0.97, "settings")
	var font: Font = Chrome.font()
	for i in ROWS.size():
		var label_y: float = p.position.y + Chrome.HEADER_H + 44.0 + float(i) * ROW_H + 34.0
		draw_string(font, Vector2(p.position.x + 40.0, label_y), String(ROWS[i]["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Chrome.TEXT)
		var track: Rect2 = _track_rect(i)
		_draw_rail(track)
		var t: float = inverse_lerp(_floor_of(i), 1.0, UiPrefs.level(String(ROWS[i]["key"])))
		var filled: Rect2 = Rect2(track.position, Vector2(track.size.x * clampf(t, 0.0, 1.0), track.size.y))
		draw_rect(filled, Chrome.ACCENT)
		var handle: Vector2 = track.position + Vector2(track.size.x * clampf(t, 0.0, 1.0), track.size.y / 2.0)
		draw_circle(handle, HANDLE_R, Chrome.TEXT)
		draw_circle(handle, HANDLE_R, Chrome.ACCENT, false, 2.0)
	for j in TOGGLES.size():
		var row_y: float = _row_top(ROWS.size() + j) + 34.0
		draw_string(font, Vector2(p.position.x + 40.0, row_y), String(TOGGLES[j]["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Chrome.TEXT)
		_draw_toggle(_toggle_rect(j), UiPrefs.flag(String(TOGGLES[j]["key"])))
	var hint_y: float = p.position.y + PANEL_SIZE.y - 28.0
	draw_string(font, Vector2(p.position.x + 40.0, hint_y), "Esc to close · changes apply immediately", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Chrome.TEXT_DIM)


# One switch: the kit's `control_toggle_on.png` or `control_toggle_off.png`, whole, at Kit.SCALE.
# A toggle the kit does not resolve falls back to a drawn box, filled when on.
func _draw_toggle(rect: Rect2, on: bool) -> void:
	var tex: Texture2D = Kit.texture(TOGGLE_ON_PATH if on else TOGGLE_OFF_PATH, Kit.SCALE)
	if tex != null:
		draw_texture_rect(tex, rect, false)
		return
	if on:
		draw_rect(rect, Chrome.ACCENT)
	draw_rect(rect, Chrome.CELL_EDGE, false, 2.0)


# The slider rail: the kit's `control_slider_rail.png`, whole pixels, its rounded ends drawn 1:1
# from the texture's own left and right `RAIL_CAP_W` kit pixels (at `Kit.SCALE`) and the pill's
# straight middle stretched to fill whatever is left. A rail the kit does not resolve falls back
# to the hairline this replaced.
func _draw_rail(rect: Rect2) -> void:
	var r: Rect2 = Rect2(rect.position.round(), rect.size.round())
	var tex: Texture2D = Kit.texture(RAIL_PATH)
	if tex == null:
		draw_rect(r, Chrome.CELL_EDGE)
		return
	var tex_size: Vector2 = tex.get_size()
	var cap: float = RAIL_CAP_W * float(Kit.SCALE)
	var left_src := Rect2(Vector2.ZERO, Vector2(cap, tex_size.y))
	var right_src := Rect2(Vector2(tex_size.x - cap, 0.0), Vector2(cap, tex_size.y))
	var mid_src := Rect2(Vector2(cap, 0.0), Vector2(tex_size.x - cap * 2.0, tex_size.y))
	draw_texture_rect_region(tex, Rect2(r.position, Vector2(cap, r.size.y)), left_src)
	draw_texture_rect_region(tex, Rect2(r.position + Vector2(r.size.x - cap, 0.0), Vector2(cap, r.size.y)), right_src)
	var mid_w: float = r.size.x - cap * 2.0
	if mid_w > 0.0:
		draw_texture_rect_region(tex, Rect2(r.position + Vector2(cap, 0.0), Vector2(mid_w, r.size.y)), mid_src)
