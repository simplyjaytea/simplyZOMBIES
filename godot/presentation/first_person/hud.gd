extends Control
# The first-person screen's words. It follows the standing HUD rules rather than inventing a
# second language: condition and needs arrive as prose from `sim/condition.gd` and
# `needs.hud_clause`, there is no bar to fill and no number to read, and the help line carries no
# digit. The gate scans every line this file will draw, so a numeric slip is red rather than a
# matter of taste.
#
# Drawn with `draw_string` rather than anchored Labels for the same reason `ui/hud.gd` does: a
# Control parented to a CanvasLayer has no rect of its own until one is set, and anchor presets on
# children resolve against nothing. `lines()` is the one list both the draw and the gate read.

const Chrome = preload("res://ui/chrome.gd")
const SimCondition = preload("res://sim/condition.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")

const TITLE_SIZE: int = 25
const BODY_SIZE: int = 25
const HELP_SIZE: int = 20
const MARGIN: float = 28.0
# Worst-part states from condition.gd, as a sentence rather than a grade. Kept local because it is
# wording, not a sim fact, and `ui/hud.gd` owns the top-down screen's own copy of the same words.
const CONDITION_WORDS: Array[String] = ["", "hurt", "badly hurt", "barely standing"]
const HELP: String = "WASD walk   mouse look   E ledger or open   P hold   Esc release or title   click to look"
# The end-of-run panel: the shell's heading and frame, held to this screen's own size. One action,
# and it goes back to the game's title rather than quitting the process.
const RUN_OVER_HEADING: String = "the run is over"
const RUN_OVER_ACTION: String = "Escape returns to the title"
const END_PANEL_W: float = 720.0
const END_PAD: float = 40.0
const END_LINE_H: float = 34.0

var world: Variant = null
var player: int = -1
var prompt: String = ""
var alert: String = ""
var menu_open: bool = false
var paused: bool = false
var inventory_open: bool = false
# A chronicle line the scene wants said once -- the succession sentence ("You are Mara Sato now.").
var news: String = ""
var run_over: bool = false
var _end_lines: Array[String] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sync_size()
	get_viewport().size_changed.connect(_sync_size)


func _sync_size() -> void:
	size = get_viewport_rect().size
	queue_redraw()


func set_state(world_ref: Variant, player_ref: int, prompt_text: String, alert_text: String, menu: bool, is_paused: bool, inventory: bool = false, news_text: String = "") -> void:
	world = world_ref
	player = player_ref
	prompt = prompt_text
	alert = alert_text
	menu_open = menu
	paused = is_paused
	inventory_open = inventory
	news = news_text
	queue_redraw()


## The end of the run: `lines` is the chronicle's epitaph, already prose. The screen stays up until
## the process leaves; the first-person title flow is a later piece.
func set_run_over(end_lines: Array) -> void:
	run_over = true
	_end_lines.clear()
	for line in end_lines:
		_end_lines.append(String(line))
	if _end_lines.is_empty():
		_end_lines.append("There is nobody left to be.")
	visible = true
	queue_redraw()


## Every line of prose this screen can show, for the gate's digit scan and the player's eyes.
func lines() -> Array[String]:
	var out: Array[String] = []
	if run_over:
		out.append(RUN_OVER_HEADING)
		for line in _end_lines:
			out.append(line)
		out.append(RUN_OVER_ACTION)
		return out
	if world != null and player >= 0:
		var needs: String = SimNeeds.hud_clause(world, player)
		out.append(needs if needs != "" else "You feel steady.")
		var view: Dictionary = SimCondition.view(world, player)
		var worst: int = int(view.get("worst", 0)) if not view.is_empty() else 0
		if worst > 0 and worst < CONDITION_WORDS.size():
			out.append("You are " + CONDITION_WORDS[worst] + ".")
		var bleeding: bool = false
		for part in (view.get("parts", []) as Array):
			if bool((part as Dictionary).get("bleeding", false)):
				bleeding = true
				break
		if bleeding:
			out.append("You are bleeding.")
	if news != "":
		out.append(news)
	out.append(HELP)
	if menu_open:
		out.append("The ledger is open. Escape closes it.")
	if inventory_open:
		out.append("The inventory is open. Escape closes it.")
	out.append(prompt)
	out.append(alert)
	return out


func _draw() -> void:
	var font: Font = Chrome.font()
	if run_over:
		_draw_run_over(font)
		return
	var title: String = "SimplyZOMBIES / first person"
	var state: Array[String] = []
	if world != null and player >= 0:
		var needs: String = SimNeeds.hud_clause(world, player)
		state.append(needs if needs != "" else "You feel steady.")
		var view: Dictionary = SimCondition.view(world, player)
		var worst: int = int(view.get("worst", 0)) if not view.is_empty() else 0
		if worst > 0 and worst < CONDITION_WORDS.size():
			state.append("You are " + CONDITION_WORDS[worst] + ".")
	if news != "":
		state.append(news)
	var panel_h: float = 74.0 + float(maxi(1, state.size())) * 30.0
	draw_rect(Rect2(MARGIN - 12.0, MARGIN - 12.0, 560.0, panel_h), Color(0.04, 0.05, 0.05, 0.62))
	draw_string(font, Vector2(MARGIN, MARGIN + 16.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, Color(0.88, 0.84, 0.64))
	var y: float = MARGIN + 50.0
	for line in state:
		draw_string(font, Vector2(MARGIN, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, Color(0.92, 0.92, 0.86))
		y += 30.0
	if paused:
		draw_string(font, Vector2(MARGIN, y), "The world is holding still.", HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, Color(0.92, 0.78, 0.50))

	var view_size: Vector2 = size
	if view_size == Vector2.ZERO:
		view_size = get_viewport_rect().size
	draw_circle(view_size * 0.5, 2.0, Color(0.94, 0.92, 0.82, 0.85))

	var help_at: Vector2 = Vector2(MARGIN, view_size.y - MARGIN - 26.0)
	draw_rect(Rect2(MARGIN - 12.0, help_at.y - 24.0, view_size.x - (MARGIN - 12.0) * 2.0, 44.0), Color(0.04, 0.05, 0.05, 0.58))
	draw_string(font, help_at, HELP, HORIZONTAL_ALIGNMENT_LEFT, -1, HELP_SIZE, Color(0.86, 0.86, 0.80))

	var said: String = prompt
	var colour: Color = Color(0.96, 0.90, 0.66)
	if alert != "":
		said = alert
		colour = Color(0.96, 0.68, 0.52)
	if said != "":
		var width: float = font.get_string_size(said, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE).x
		var at: Vector2 = Vector2((view_size.x - width) * 0.5, view_size.y - MARGIN - 72.0)
		draw_rect(Rect2(at.x - 14.0, at.y - 26.0, width + 28.0, 40.0), Color(0.04, 0.05, 0.05, 0.68))
		draw_string(font, at, said, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, colour)


## The over screen: the shell's danger panel and heading, the chronicle's epitaph, and the one
## action. Nothing numeric, and no bar -- the same words contract as the rest of this HUD.
func _draw_run_over(font: Font) -> void:
	var view_size: Vector2 = size
	if view_size == Vector2.ZERO:
		view_size = get_viewport_rect().size
	var dim: Color = Chrome.FIELD
	dim.a = 0.88
	draw_rect(Rect2(Vector2.ZERO, view_size), dim)
	var panel_h: float = Chrome.HEADER_H + END_PAD * 2.0 + float(_end_lines.size()) * END_LINE_H + 58.0
	var panel: Rect2 = Rect2(((view_size - Vector2(END_PANEL_W, panel_h)) * 0.5).round(), Vector2(END_PANEL_W, panel_h))
	if not Chrome.frame(self, panel, "panel_danger", 0.98):
		var fill: Color = Chrome.PANEL
		fill.a = 0.98
		draw_rect(panel, fill)
		draw_rect(panel, Chrome.DANGER, false, 1.5)
	Chrome.header(self, panel, RUN_OVER_HEADING, 0.98, "warning")
	var y: float = panel.position.y + Chrome.HEADER_H + END_PAD + 24.0
	for line in _end_lines:
		draw_string(font, Vector2(panel.position.x + END_PAD, y), line, HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - END_PAD * 2.0, BODY_SIZE, Chrome.TEXT)
		y += END_LINE_H
	draw_string(font, Vector2(panel.position.x + END_PAD, y + 22.0), RUN_OVER_ACTION, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, Chrome.TEXT_DIM)


## True when `text` contains a decimal digit, the same test the top-down HUD gate makes.
static func has_digit(text: String) -> bool:
	for i in text.length():
		if text[i].is_valid_int():
			return true
	return false
