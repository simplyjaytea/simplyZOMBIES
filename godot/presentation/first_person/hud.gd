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
const HELP: String = "WASD walk   mouse look   E ledger or open   P hold   Esc back or release   click to look"

var world: Variant = null
var player: int = -1
var prompt: String = ""
var alert: String = ""
var menu_open: bool = false
var paused: bool = false
var inventory_open: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sync_size()
	get_viewport().size_changed.connect(_sync_size)


func _sync_size() -> void:
	size = get_viewport_rect().size
	queue_redraw()


func set_state(world_ref: Variant, player_ref: int, prompt_text: String, alert_text: String, menu: bool, is_paused: bool, inventory: bool = false) -> void:
	world = world_ref
	player = player_ref
	prompt = prompt_text
	alert = alert_text
	menu_open = menu
	paused = is_paused
	inventory_open = inventory
	queue_redraw()


## Every line of prose this screen can show, for the gate's digit scan and the player's eyes.
func lines() -> Array[String]:
	var out: Array[String] = []
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
	var title: String = "SimplyZOMBIES / first person"
	var state: Array[String] = []
	if world != null and player >= 0:
		var needs: String = SimNeeds.hud_clause(world, player)
		state.append(needs if needs != "" else "You feel steady.")
		var view: Dictionary = SimCondition.view(world, player)
		var worst: int = int(view.get("worst", 0)) if not view.is_empty() else 0
		if worst > 0 and worst < CONDITION_WORDS.size():
			state.append("You are " + CONDITION_WORDS[worst] + ".")
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


## True when `text` contains a decimal digit, the same test the top-down HUD gate makes.
static func has_digit(text: String) -> bool:
	for i in text.length():
		if text[i].is_valid_int():
			return true
	return false
