extends Control
# The keys, on screen, because "playable end to end without a developer explaining it" is
# Milestone 2's exit criterion and the bindings previously lived only in README.md.
#
# Shown once on a fresh run and dismissed with any of F1, Escape, or Enter -- then it stays
# dismissed, because a legend you cannot turn off is a legend you resent. F1 brings it back.
#
# The groupings are the ones a new player needs in the order they need them: move first,
# fight second, look third, and the meta keys last.

const Palette = preload("res://presentation/palette.gd")

const PAD: float = 18.0
const LINE: float = 19.0
const TITLE_GAP: float = 10.0
const GROUP_GAP: float = 9.0
const KEY_COLUMN: float = 132.0
const FONT_SIZE: int = 12
const TITLE_SIZE: int = 15

const GROUPS: Array = [
	["Move", [
		["WASD", "walk"],
		["Shift", "sprint — fast, and loud, latches while held"],
		["Z / X / C / V", "crawl, crouch, walk, jog"],
	]],
	["Act", [
		["F", "swing, or struggle out of a grab"],
		["H", "pull someone out of a grab"],
		["G / click", "fire"],
		["R", "reload"],
		["E", "pick up"],
		["T", "first aid — bandage if you have one, bare hands if not; again to stop"],
		["Space", "shout — heard across the district"],
	]],
	["Look", [
		["Tab", "gear and injuries"],
		["J", "work priorities"],
		["O", "attention overlay: noise, scent, sight, light"],
		["M", "raw developer sheets"],
	]],
	["Run", [
		["1 / 2 / 3", "speed: 1x, 3x, 10x"],
		["P", "pause"],
		["F5 / F9", "save and load"],
		["F1", "these keys"],
	]],
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	# The viewport rect, not `size`: a Control parented to a CanvasLayer keeps a zero-sized
	# rect, so centring against `size` puts the panel off the top-left of the screen.
	var view: Vector2 = get_viewport_rect().size
	var rows: int = 0
	for group in GROUPS:
		rows += ((group as Array)[1] as Array).size()
	var height: float = PAD * 2.0 + TITLE_GAP + LINE * float(rows + GROUPS.size()) + GROUP_GAP * float(GROUPS.size())
	var width: float = 430.0
	var origin := Vector2(
		roundf((view.x - width) / 2.0),
		roundf((view.y - height) / 2.0),
	)

	# Dim the district behind, so the legend reads as a layer over the game rather than as
	# part of it.
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.02, 0.03, 0.04, 0.72))
	draw_rect(Rect2(origin, Vector2(width, height)), Color(0.07, 0.08, 0.09, 0.97))
	draw_rect(Rect2(origin, Vector2(width, height)), Palette.COLOURS["outline"], false, 1.0)

	var y: float = origin.y + PAD + TITLE_SIZE
	draw_string(font, Vector2(origin.x + PAD, y), "Keys", HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, Palette.COLOURS["player"])
	draw_string(font, Vector2(origin.x + width - PAD - 96.0, y), "F1 to close", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Palette.COLOURS["outline"])
	y += TITLE_GAP

	for group in GROUPS:
		y += LINE
		draw_string(font, Vector2(origin.x + PAD, y), String((group as Array)[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Palette.COLOURS["outline"])
		for row in (group as Array)[1] as Array:
			y += LINE
			var r: Array = row as Array
			draw_string(font, Vector2(origin.x + PAD + 12.0, y), String(r[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Palette.COLOURS["player"])
			draw_string(font, Vector2(origin.x + KEY_COLUMN, y), String(r[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Palette.COLOURS["survivor"])
		y += GROUP_GAP
