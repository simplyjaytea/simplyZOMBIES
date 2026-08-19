extends Control
# The keys, on screen, because "playable end to end without a developer explaining it" is
# Milestone 2's exit criterion and the bindings previously lived only in README.md.
#
# Shown once on a fresh run and dismissed with any of F1, Escape, or Enter -- then it stays
# dismissed, because a legend you cannot turn off is a legend you resent. F1 brings it back.
#
# The groupings are the ones a new player needs in the order they need them: move first,
# fight second, look third, and the meta keys last.

const Chrome = preload("res://ui/chrome.gd")

const PAD: float = 36.0
const LINE: float = 38.0
const TITLE_GAP: float = 20.0
const GROUP_GAP: float = 18.0
const KEY_COLUMN: float = 264.0
const FONT_SIZE: int = 24
const TITLE_SIZE: int = 30

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
		["Tab", "gear and injuries — drag a bag by its title, pin it to keep it on screen"],
		["J", "work priorities"],
		["O", "attention overlay: noise, scent, sight, light"],
		["M", "raw developer sheets"],
		["Wheel", "zoom"],
	]],
	["Run", [
		["1 / 2 / 3", "speed: 1x, 3x, 10x"],
		["P", "pause"],
		["F5 / F9", "save and load"],
		["Esc", "settings"],
		["F8", "debug spawn menu (dev)"],
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
	var width: float = 1060.0
	var origin := Vector2(
		roundf((view.x - width) / 2.0),
		roundf((view.y - height) / 2.0),
	)

	# Dim the district behind, so the legend reads as a layer over the game rather than as
	# part of it. Panel chrome comes from ui/chrome.gd, the one place the skin lives.
	var dim: Color = Chrome.FIELD
	dim.a = 0.72
	draw_rect(Rect2(Vector2.ZERO, view), dim)
	Chrome.panel(self, Rect2(origin, Vector2(width, height)), 0.97)
	Chrome.header(self, Rect2(origin, Vector2(width, height)), "keys", 0.97)
	draw_string(font, Vector2(origin.x + width - PAD - 156.0, origin.y + Chrome.HEADER_H - 13.0), "F1 to close", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Chrome.TEXT_DIM)

	var y: float = origin.y + Chrome.HEADER_H + TITLE_GAP

	for group in GROUPS:
		y += LINE
		draw_string(font, Vector2(origin.x + PAD, y), String((group as Array)[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Chrome.TEXT_DIM)
		for row in (group as Array)[1] as Array:
			y += LINE
			var r: Array = row as Array
			draw_string(font, Vector2(origin.x + PAD + 24.0, y), String(r[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Chrome.ACCENT)
			draw_string(font, Vector2(origin.x + KEY_COLUMN, y), String(r[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Chrome.TEXT)
		y += GROUP_GAP
