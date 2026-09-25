extends Control
# The driver's seat: a makeshift dashboard, drawn while the player is on a vehicle and hidden
# otherwise. Which dashboard is the class's own `dash` word, carried in the view as `layout`:
#
#   cluster    a car's. Two dials with needles and no numbers -- a speedometer on the left, a
#              fuel gauge on the right with E and F at its ends -- the gear letters P N D with the
#              one you are in lit, a brake lamp, an engine lamp that goes amber when the engine is
#              battered or worse and red when it is wrecked, and one line of prose under them.
#   handlebar  a bicycle's, an e-bike's or an e-scooter's: a small panel. One small speed dial
#              (a handlebar computer), the motion word (pedalling, coasting, under power), a
#              brake lamp, a frame lamp, and -- only when the class has a battery -- a charge
#              bar with no marks on it. A bicycle has no fuel, so its dash has no gauge.
#   board      a skateboard's or a kick scooter's: a strip. The motion word (pushing, rolling),
#              a row of speed pips, and a foot-down lamp for braking -- the least a rider could
#              be said to read off the thing under their feet.
#
# This is the one gauge on the screen, and it is not the HUD's: hud.gd's rule ("no gauges, not
# for needs, not for condition, not for threat") is about the *body*, and the instruments here
# are the *machine's* -- a speedometer is what a driver looks at, and a needle with no dial
# numbers is exactly as scarce as a real one. Every value comes from SimVehicles.dash_view, whose
# keys are DASH_KEYS and whose only numbers are the two needle fractions; not a digit is drawn
# here, and check_vehicles.gd's DASH lane scans this file's string literals to hold that.

const Palette = preload("res://presentation/palette.gd")
const SimVehicles = preload("res://sim/modules/vehicles.gd")
const Chrome = preload("res://ui/chrome.gd")

# Sized for VT323 at the size ladder's rungs (docs/23's record, "UI -- one typeface"): the longest
# word a dial carries ("a splash in the tank", "about half a charge") centred under its dial
# without leaving the panel, and the words, the rule and the prose line each on their own row.
const PANEL_W: float = 600.0
const PANEL_H: float = 200.0
# The handlebar panel and the board strip: smaller, because there is less to show.
const HANDLEBAR_W: float = 460.0
const HANDLEBAR_H: float = 160.0
const BOARD_W: float = 320.0
const BOARD_H: float = 80.0
const BOTTOM: float = 16.0
const DIAL_R: float = 52.0
const SMALL_DIAL_R: float = 34.0
# A dial sweeps from seven o'clock round to five o'clock: 225 degrees, needle at the fraction.
const DIAL_FROM: float = 0.75 * PI
const DIAL_SWEEP: float = 1.25 * PI
const TICKS: int = 9
const PIPS: int = 6
const FONT_SIZE: int = 30
const SMALL_SIZE: int = 25
# The prose line on the two small dashes, whose sentence is as long as the car's on a panel not
# much more than half as wide.
const PROSE_SMALL: int = 20
const LETTER_SIZE: int = 50
# Where a dial's word hangs under it, and where the dials sit in from the panel's ends.
const WORD_DROP: float = 24.0
const DIAL_INSET: float = 110.0
# A lamp's disc to its word, and one lamp's word to the next lamp's disc.
const LAMP_GAP: float = 6.0
const LAMP_BETWEEN: float = 18.0

const PANEL: Color = Color("#1b1a17e6")
const RIM: Color = Color("#4d4740")
const DIAL: Color = Color("#2a2823")
const NEEDLE: Color = Color("#e0c46a")
const LIT: Color = Color("#e8d7a0")
const DIM: Color = Color("#5b564e")
const AMBER: Color = Color("#d9932d")
const RED: Color = Color("#c4402f")
const BRAKE: Color = Color("#c4402f")
const CHARGE: Color = Color("#7fae6a")

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
	# One entry point, three layouts: the view's own word picks which, and a word nobody drew
	# falls to the board -- the least instrument, never a car's cluster on a skateboard.
	match String(_view.get("layout", "board")):
		"cluster":
			_draw_cluster()
		"handlebar":
			_draw_handlebar()
		_:
			_draw_board()


# The lamp colour the frame or engine word earns: off when sound or scuffed, amber battered or
# failing, red wrecked.
func _engine_colour() -> Color:
	var engine: String = String(_view.get("engine", "sound"))
	if engine == "wrecked":
		return RED
	if bool(_view.get("warning", false)):
		return AMBER
	return DIM


# --- a car's cluster ---------------------------------------------------------------------------

func _draw_cluster() -> void:
	var font: Font = Chrome.font()
	var vp: Vector2 = get_viewport_rect().size
	var origin := Vector2(roundf((vp.x - PANEL_W) / 2.0), vp.y - BOTTOM - PANEL_H)
	var panel := Rect2(origin, Vector2(PANEL_W, PANEL_H))
	draw_rect(panel, PANEL)
	draw_rect(panel, RIM, false, 2.0)

	# The speedometer, left: no numbers on the dial, nine tick marks, a needle.
	var speedo_c := origin + Vector2(DIAL_INSET, 72.0)
	_dial(speedo_c, float(_view.get("speedo", 0.0)), DIAL_R)
	_word_under(font, speedo_c, DIAL_R, String(_view.get("speed", "")), DIAL_INSET * 2.0 - 20.0)

	# The fuel gauge, right: E to F, a needle.
	var fuel_c := origin + Vector2(PANEL_W - DIAL_INSET, 72.0)
	_dial(fuel_c, float(_view.get("gauge", 0.0)), DIAL_R)
	draw_string(font, fuel_c + Vector2(-DIAL_R - 4.0, 8.0), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE, LIT)
	draw_string(font, fuel_c + Vector2(DIAL_R - 8.0, 8.0), "F", HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE, LIT)
	_word_under(font, fuel_c, DIAL_R, String(_view.get("fuel", "")), DIAL_INSET * 2.0 - 20.0)

	# The gear letters, centre: the one you are in lit, the others dim, as one centred group.
	var gear: String = String(_view.get("gear", "park"))
	var letters: Array = [["P", "park"], ["N", "neutral"], ["D", "drive"]]
	var letter_w: float = font.get_string_size("P", HORIZONTAL_ALIGNMENT_LEFT, -1, LETTER_SIZE).x
	var letter_gap: float = letter_w * 1.2
	var lx: float = roundf(origin.x + PANEL_W / 2.0 - (letter_w * 3.0 + letter_gap * 2.0) / 2.0)
	for pair in letters:
		var lit: bool = String((pair as Array)[1]) == gear
		draw_string(font, Vector2(lx, origin.y + 64.0), String((pair as Array)[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, LETTER_SIZE, LIT if lit else DIM)
		lx += letter_w + letter_gap

	# The lamps: brake when the driver is on it, engine when the car is battered or worse -- two
	# lamps and their words measured and centred as one row.
	var brake_on: bool = bool(_view.get("braking", false))
	var engine_col: Color = _engine_colour()
	var lamps: Array = [["brake", BRAKE if brake_on else DIM, brake_on], ["engine", engine_col, engine_col != DIM]]
	_lamps(font, origin.x + (PANEL_W - _lamps_width(font, lamps, 7.0, SMALL_SIZE)) / 2.0, origin.y + 100.0, lamps, 7.0, SMALL_SIZE)

	# One line of prose on its own row under the dial words, the same words the dials show.
	draw_line(origin + Vector2(16.0, PANEL_H - 40.0), origin + Vector2(PANEL_W - 16.0, PANEL_H - 40.0), RIM, 1.0)
	draw_string(font, Vector2(origin.x + 16.0, origin.y + PANEL_H - 13.0), String(_view.get("prose", "")), HORIZONTAL_ALIGNMENT_CENTER, PANEL_W - 32.0, SMALL_SIZE, LIT)


# A dial's word, centred under it in a box `wide` across.
func _word_under(font: Font, centre: Vector2, radius: float, word: String, wide: float) -> void:
	draw_string(font, Vector2(roundf(centre.x - wide / 2.0), centre.y + radius + WORD_DROP), word, HORIZONTAL_ALIGNMENT_CENTER, wide, SMALL_SIZE, LIT)


# A row of lamps, each a disc and its word, from `left` along the discs' centre line `y`. Each
# entry is [word, disc colour, whether the word is lit].
func _lamps(font: Font, left: float, y: float, lamps: Array, radius: float, font_size: int) -> void:
	var x: float = roundf(left)
	var cap: float = Chrome.cap_height(font_size)
	for lamp in lamps:
		var l: Array = lamp as Array
		draw_circle(Vector2(x + radius, y), radius, l[1] as Color)
		x += radius * 2.0 + LAMP_GAP
		draw_string(font, Vector2(x, roundf(y + cap / 2.0)), String(l[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LIT if bool(l[2]) else DIM)
		x += font.get_string_size(String(l[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + LAMP_BETWEEN


# How wide `_lamps` draws the same row, so a caller can centre it.
func _lamps_width(font: Font, lamps: Array, radius: float, font_size: int) -> float:
	var total: float = LAMP_BETWEEN * float(lamps.size() - 1)
	for lamp in lamps:
		total += radius * 2.0 + LAMP_GAP + font.get_string_size(String((lamp as Array)[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	return total


# --- a handlebar computer ----------------------------------------------------------------------

func _draw_handlebar() -> void:
	var font: Font = Chrome.font()
	var vp: Vector2 = get_viewport_rect().size
	var origin := Vector2(roundf((vp.x - HANDLEBAR_W) / 2.0), vp.y - BOTTOM - HANDLEBAR_H)
	var panel := Rect2(origin, Vector2(HANDLEBAR_W, HANDLEBAR_H))
	draw_rect(panel, PANEL)
	draw_rect(panel, RIM, false, 2.0)

	# One small speed dial, left, the speed word under it.
	var speedo_c := origin + Vector2(76.0, 56.0)
	_dial(speedo_c, float(_view.get("speedo", 0.0)), SMALL_DIAL_R)
	_word_under(font, speedo_c, SMALL_DIAL_R, String(_view.get("speed", "")), 140.0)

	# The motion word, centre, and the two lamps under it: brake, and the frame's condition.
	var mid_x: float = origin.x + 160.0
	draw_string(font, Vector2(mid_x, origin.y + 46.0), String(_view.get("motion", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, LIT)
	var brake_on: bool = bool(_view.get("braking", false))
	var engine_col: Color = _engine_colour()
	_lamps(font, mid_x, origin.y + 76.0, [["brake", BRAKE if brake_on else DIM, brake_on], ["frame", engine_col, engine_col != DIM]], 6.0, SMALL_SIZE)

	# A charge bar, right, only on a class with a battery: a bicycle has nothing to gauge.
	if bool(_view.get("powered", false)):
		var bar := Rect2(origin + Vector2(HANDLEBAR_W - 44.0, 24.0), Vector2(20.0, 56.0))
		draw_rect(bar, DIAL)
		draw_rect(bar, RIM, false, 1.5)
		var fill: float = clampf(float(_view.get("gauge", 0.0)), 0.0, 1.0)
		var h: float = (bar.size.y - 4.0) * fill
		draw_rect(Rect2(bar.position + Vector2(2.0, bar.size.y - 2.0 - h), Vector2(bar.size.x - 4.0, h)), CHARGE if fill > 0.15 else RED)
		# Right-aligned to the bar's right edge, on the speed word's row.
		var room: float = HANDLEBAR_W - 16.0 - 160.0
		draw_string(font, Vector2(origin.x + HANDLEBAR_W - 16.0 - room, speedo_c.y + SMALL_DIAL_R + WORD_DROP), String(_view.get("fuel", "")), HORIZONTAL_ALIGNMENT_RIGHT, room, SMALL_SIZE, LIT)

	draw_line(origin + Vector2(12.0, HANDLEBAR_H - 36.0), origin + Vector2(HANDLEBAR_W - 12.0, HANDLEBAR_H - 36.0), RIM, 1.0)
	draw_string(font, Vector2(origin.x + 12.0, origin.y + HANDLEBAR_H - 12.0), String(_view.get("prose", "")), HORIZONTAL_ALIGNMENT_CENTER, HANDLEBAR_W - 24.0, PROSE_SMALL, LIT)


# --- a board's strip ---------------------------------------------------------------------------

func _draw_board() -> void:
	var font: Font = Chrome.font()
	var vp: Vector2 = get_viewport_rect().size
	var origin := Vector2(roundf((vp.x - BOARD_W) / 2.0), vp.y - BOTTOM - BOARD_H)
	var panel := Rect2(origin, Vector2(BOARD_W, BOARD_H))
	draw_rect(panel, PANEL)
	draw_rect(panel, RIM, false, 2.0)

	# The motion word, left; the speed pips beside it -- PIPS squares, lit up to the fraction.
	draw_string(font, Vector2(origin.x + 14.0, origin.y + 32.0), String(_view.get("motion", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, LIT)
	var lit_pips: int = int(roundf(clampf(float(_view.get("speedo", 0.0)), 0.0, 1.0) * float(PIPS)))
	for i in PIPS:
		var pip := Rect2(origin + Vector2(BOARD_W - 150.0 + float(i) * 16.0, 16.0), Vector2(11.0, 14.0))
		draw_rect(pip, NEEDLE if i < lit_pips else DIAL)
		draw_rect(pip, RIM, false, 1.0)
	# The foot-down lamp: braking on a board is a foot dragged, and the frame lamp beside it.
	var lamp_y: float = origin.y + 23.0
	var brake_on: bool = bool(_view.get("braking", false))
	draw_circle(Vector2(origin.x + BOARD_W - 42.0, lamp_y), 6.0, BRAKE if brake_on else DIM)
	draw_circle(Vector2(origin.x + BOARD_W - 22.0, lamp_y), 6.0, _engine_colour())

	draw_line(origin + Vector2(12.0, BOARD_H - 32.0), origin + Vector2(BOARD_W - 12.0, BOARD_H - 32.0), RIM, 1.0)
	draw_string(font, Vector2(origin.x + 12.0, origin.y + BOARD_H - 11.0), String(_view.get("prose", "")), HORIZONTAL_ALIGNMENT_CENTER, BOARD_W - 24.0, PROSE_SMALL, LIT)


# A dial: a dark disc, a rim, tick marks round the sweep, and the needle at `fraction`.
func _dial(centre: Vector2, fraction: float, radius: float = DIAL_R) -> void:
	draw_circle(centre, radius, DIAL)
	draw_arc(centre, radius, DIAL_FROM, DIAL_FROM + DIAL_SWEEP, 48, RIM, 2.0)
	for i in TICKS:
		var a: float = DIAL_FROM + DIAL_SWEEP * float(i) / float(TICKS - 1)
		var dir := Vector2(cos(a), sin(a))
		draw_line(centre + dir * (radius - 10.0), centre + dir * (radius - 3.0), RIM, 2.0)
	var na: float = DIAL_FROM + DIAL_SWEEP * clampf(fraction, 0.0, 1.0)
	var ndir := Vector2(cos(na), sin(na))
	draw_line(centre - ndir * 8.0, centre + ndir * (radius - 12.0), NEEDLE, 3.0)
	draw_circle(centre, 4.0, NEEDLE)
