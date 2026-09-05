extends Control
# The driver's seat: a makeshift dashboard, drawn while the player is at a wheel and hidden
# otherwise. Two dials with needles and no numbers -- a speedometer on the left, a fuel gauge
# on the right with E and F at its ends -- the gear letters P N D with the one you are in lit,
# a brake lamp, an engine lamp that goes amber when the engine is battered or worse and red when
# it is wrecked, and one line of prose under them.
#
# This is the one gauge on the screen, and it is not the HUD's: hud.gd's rule ("no gauges, not
# for needs, not for condition, not for threat") is about the *body*, and the instruments here
# are the *car's* -- a speedometer is what a driver looks at, and a needle with no dial numbers
# is exactly as scarce as a real one. Every value comes from SimVehicles.dash_view, whose keys
# are DASH_KEYS and whose only numbers are the two needle fractions; not a digit is drawn here,
# and check_vehicles.gd's DASH lane scans this file's string literals to hold that.

const Palette = preload("res://presentation/palette.gd")
const SimVehicles = preload("res://sim/modules/vehicles.gd")

const PANEL_W: float = 520.0
const PANEL_H: float = 178.0
const BOTTOM: float = 16.0
const DIAL_R: float = 52.0
# A dial sweeps from seven o'clock round to five o'clock: 225 degrees, needle at the fraction.
const DIAL_FROM: float = 0.75 * PI
const DIAL_SWEEP: float = 1.25 * PI
const TICKS: int = 9
const FONT_SIZE: int = 22
const SMALL_SIZE: int = 18
const LETTER_SIZE: int = 30

const PANEL: Color = Color("#1b1a17e6")
const RIM: Color = Color("#4d4740")
const DIAL: Color = Color("#2a2823")
const NEEDLE: Color = Color("#e0c46a")
const LIT: Color = Color("#e8d7a0")
const DIM: Color = Color("#5b564e")
const AMBER: Color = Color("#d9932d")
const RED: Color = Color("#c4402f")
const BRAKE: Color = Color("#c4402f")

var _view: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_view(view: Dictionary) -> void:
	_view = view
	visible = not view.is_empty()
	queue_redraw()


func _draw() -> void:
	if _view.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var vp: Vector2 = get_viewport_rect().size
	var origin := Vector2((vp.x - PANEL_W) / 2.0, vp.y - BOTTOM - PANEL_H)
	var panel := Rect2(origin, Vector2(PANEL_W, PANEL_H))
	draw_rect(panel, PANEL)
	draw_rect(panel, RIM, false, 2.0)

	# The speedometer, left: no numbers on the dial, nine tick marks, a needle.
	var speedo_c := origin + Vector2(80.0, 72.0)
	_dial(speedo_c, float(_view.get("speedo", 0.0)))
	draw_string(font, speedo_c + Vector2(-DIAL_R - 8.0, DIAL_R + 22.0), String(_view.get("speed", "")), HORIZONTAL_ALIGNMENT_CENTER, DIAL_R * 2.0 + 16.0, SMALL_SIZE, LIT)

	# The fuel gauge, right: E to F, a needle.
	var fuel_c := origin + Vector2(PANEL_W - 80.0, 72.0)
	_dial(fuel_c, float(_view.get("gauge", 0.0)))
	draw_string(font, fuel_c + Vector2(-DIAL_R - 4.0, 8.0), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE, LIT)
	draw_string(font, fuel_c + Vector2(DIAL_R - 10.0, 8.0), "F", HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE, LIT)
	draw_string(font, fuel_c + Vector2(-DIAL_R - 8.0, DIAL_R + 22.0), String(_view.get("fuel", "")), HORIZONTAL_ALIGNMENT_CENTER, DIAL_R * 2.0 + 16.0, SMALL_SIZE, LIT)

	# The gear letters, centre: the one you are in lit, the others dim.
	var gear: String = String(_view.get("gear", "park"))
	var letters: Array = [["P", "park"], ["N", "neutral"], ["D", "drive"]]
	var lx: float = origin.x + PANEL_W / 2.0 - 60.0
	for pair in letters:
		var lit: bool = String((pair as Array)[1]) == gear
		draw_string(font, Vector2(lx, origin.y + 52.0), String((pair as Array)[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, LETTER_SIZE, LIT if lit else DIM)
		lx += 44.0

	# The lamps: brake when the driver is on it, engine when the car is battered or worse.
	var lamp_y: float = origin.y + 88.0
	var brake_on: bool = bool(_view.get("braking", false))
	draw_circle(Vector2(origin.x + PANEL_W / 2.0 - 52.0, lamp_y), 7.0, BRAKE if brake_on else DIM)
	draw_string(font, Vector2(origin.x + PANEL_W / 2.0 - 40.0, lamp_y + 7.0), "brake", HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE, LIT if brake_on else DIM)
	var engine: String = String(_view.get("engine", "sound"))
	var engine_col: Color = DIM
	if engine == "wrecked":
		engine_col = RED
	elif bool(_view.get("warning", false)):
		engine_col = AMBER
	draw_circle(Vector2(origin.x + PANEL_W / 2.0 + 22.0, lamp_y), 7.0, engine_col)
	draw_string(font, Vector2(origin.x + PANEL_W / 2.0 + 34.0, lamp_y + 7.0), "engine", HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE, LIT if engine_col != DIM else DIM)

	# One line of prose on its own row under the dial words, the same words the dials show.
	draw_line(origin + Vector2(16.0, PANEL_H - 38.0), origin + Vector2(PANEL_W - 16.0, PANEL_H - 38.0), RIM, 1.0)
	draw_string(font, Vector2(origin.x + 16.0, origin.y + PANEL_H - 12.0), String(_view.get("prose", "")), HORIZONTAL_ALIGNMENT_CENTER, PANEL_W - 32.0, SMALL_SIZE, LIT)


# A dial: a dark disc, a rim, tick marks round the sweep, and the needle at `fraction`.
func _dial(centre: Vector2, fraction: float) -> void:
	draw_circle(centre, DIAL_R, DIAL)
	draw_arc(centre, DIAL_R, DIAL_FROM, DIAL_FROM + DIAL_SWEEP, 48, RIM, 2.0)
	for i in TICKS:
		var a: float = DIAL_FROM + DIAL_SWEEP * float(i) / float(TICKS - 1)
		var dir := Vector2(cos(a), sin(a))
		draw_line(centre + dir * (DIAL_R - 10.0), centre + dir * (DIAL_R - 3.0), RIM, 2.0)
	var na: float = DIAL_FROM + DIAL_SWEEP * clampf(fraction, 0.0, 1.0)
	var ndir := Vector2(cos(na), sin(na))
	draw_line(centre - ndir * 8.0, centre + ndir * (DIAL_R - 12.0), NEEDLE, 3.0)
	draw_circle(centre, 4.0, NEEDLE)
