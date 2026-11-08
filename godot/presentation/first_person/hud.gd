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
const SimStances = preload("res://sim/stances.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")

const TITLE_SIZE: int = 25
const BODY_SIZE: int = 25
const HELP_SIZE: int = 20
const MARGIN: float = 28.0
# Worst-part states from condition.gd, as a sentence rather than a grade. Kept local because it is
# wording, not a sim fact, and `ui/hud.gd` owns the top-down screen's own copy of the same words.
const CONDITION_WORDS: Array[String] = ["", "hurt", "badly hurt", "barely standing"]
const HELP: String = "WASD walk   mouse look   E use/ledger   LMB/F swing   G fire   R reload   P hold   Esc release or title   click to look"
# The end-of-run panel: the shell's heading and frame, held to this screen's own size. One action,
# and it goes back to the game's title rather than quitting the process.
const RUN_OVER_HEADING: String = "the run is over"
const RUN_OVER_ACTION: String = "Escape returns to the title"
const END_PANEL_W: float = 720.0
const END_PAD: float = 40.0
const END_LINE_H: float = 34.0
# The harm lines (docs/05, docs/01's scarce information). A wound is named for this long after it lands.
const WOUND_HUD_TICKS: int = 80
const HELD_LINE: String = "Something has hold of you. F struggles free."
const HELD_SEVERAL_LINE: String = "Several things have hold of you. F struggles free."
const BLEEDING_LINE: String = "You are bleeding."
# wounds.gd's own first-person bleeding clause, which the line above already says; not repeated.
const BLEEDING_CLAUSE_FIRST: String = "You're bleeding."
const INFECTED_LINE: String = "You have been bitten and the wound is wrong."

var world: Variant = null
var player: int = -1
var prompt: String = ""
# The clock in words, from session.gd's speed_words: "normal speed", "fast", "paused".
var time_words: String = ""
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


## The harm, the weapon and the state lines, in the order the panel draws them: held, the newest wound,
## bleeding, the blood-loss words, infected, the weapon, then the body's posture and needs. One list, so the
## gate and the eyes agree.
func _state_lines() -> Array[String]:
	var out: Array[String] = []
	if world != null and player >= 0:
		out.append_array(_body_lines())
		var needs: String = SimNeeds.hud_clause(world, player)
		out.append(needs if needs != "" else "You feel steady.")
		# The posture word the top-down paper doll shows under the figure (`SimStances.name_of`).
		out.append("You are " + SimStances.name_of(SimStances.stance_of(world.components, player)) + ".")
		if not time_words.is_empty():
			out.append("Time is " + time_words + ".")
		var view: Dictionary = SimCondition.view(world, player)
		var worst: int = int(view.get("worst", 0)) if not view.is_empty() else 0
		if worst > 0 and worst < CONDITION_WORDS.size():
			out.append("You are " + CONDITION_WORDS[worst] + ".")
	if news != "":
		out.append(news)
	return out


func _body_lines() -> Array[String]:
	var out: Array[String] = []
	var grabbed: Variant = world.components.get_component(player, "grabbed")
	if grabbed is Dictionary:
		var holders: int = ((grabbed as Dictionary).get("sources", []) as Array).size()
		out.append(HELD_SEVERAL_LINE if holders > 1 else HELD_LINE)
	var wound: String = _newest_wound_line()
	if wound != "":
		out.append(wound)
	var view: Dictionary = SimCondition.view(world, player)
	var bleeding: bool = false
	for part in (view.get("parts", []) as Array):
		var pd: Dictionary = part as Dictionary
		if bool(pd.get("bleeding", false)):
			bleeding = true
	if bleeding:
		out.append(BLEEDING_LINE)
	var blood: String = SimWounds.hud_clause(world, player)
	if blood != "" and blood != BLEEDING_CLAUSE_FIRST:
		out.append(blood)
	if _transmitted_exposure():
		out.append(INFECTED_LINE)
	var weapon: String = _weapon_line()
	if weapon != "":
		out.append(weapon)
	return out


# A bite that transmitted and was neither cauterised nor amputated (infection.gd's exposures). A bite that did
# not transmit says nothing: the condition view reads every exposure as "watch", and that would tell the player
# about a bite that did nothing.
func _transmitted_exposure() -> bool:
	var state: Variant = world.components.get_component(player, "zombieInfection")
	if not (state is Dictionary):
		return false
	for e in ((state as Dictionary).get("exposures", []) as Array):
		var ed: Dictionary = e as Dictionary
		if bool(ed.get("transmitted", false)) and not bool(ed.get("cauterized", false)) and not bool(ed.get("amputated", false)):
			return true
	return false


# The newest wound, as a sentence: the sim's presentation word (a bite can present as a scratch, docs/01),
# on the part's label. Shown for WOUND_HUD_TICKS after it landed.
func _newest_wound_line() -> String:
	var inj: Variant = world.components.get_component(player, "injuries")
	if not (inj is Dictionary):
		return ""
	var best: Dictionary = {}
	var best_at: int = -1
	for wound in ((inj as Dictionary).get("wounds", []) as Array):
		var wd: Dictionary = wound as Dictionary
		var at: int = int(wd.get("sustainedAtTick", -1))
		if at > best_at:
			best_at = at
			best = wd
	if best.is_empty() or int(world.tick) - best_at >= WOUND_HUD_TICKS:
		return ""
	var noun: String = String(best.get("presentation", best.get("kind", "wound")))
	return "A %s on your %s." % [noun, SimCondition.label_of(String(best.get("bodyPart", "")))]


# The fire state, from the held weapon's own state (ranged.gd's FireState). Idle is nothing. A press in
# Steady does nothing: the shot fires on its own when Steady ends, so Steady says so.
func _weapon_line() -> String:
	var rw: Variant = world.components.get_component(player, "rangedWeapon")
	if not (rw is Dictionary):
		return ""
	var st: int = int((rw as Dictionary).get("state", SimRanged.FireState.Idle))
	if st == SimRanged.FireState.Raise:
		return "You raise the weapon."
	if st == SimRanged.FireState.Steady:
		return "You are steady. The weapon fires on its own."
	if st == SimRanged.FireState.Recover:
		return "The weapon recovers."
	if st == SimRanged.FireState.Reload:
		return "You are reloading."
	if st == SimRanged.FireState.Clearing:
		return "You clear a jam."
	return ""


## Every line of prose this screen can show, for the gate's digit scan and the player's eyes.
func lines() -> Array[String]:
	var out: Array[String] = []
	if run_over:
		out.append(RUN_OVER_HEADING)
		for line in _end_lines:
			out.append(line)
		out.append(RUN_OVER_ACTION)
		return out
	out.append_array(_state_lines())
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
	var state: Array[String] = _state_lines()
	var panel_h: float = 74.0 + float(maxi(1, state.size())) * 30.0
	var panel_w: float = 560.0
	for line in state:
		panel_w = maxf(panel_w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE).x + MARGIN * 2.0)
	draw_rect(Rect2(MARGIN - 12.0, MARGIN - 12.0, panel_w, panel_h), Color(0.04, 0.05, 0.05, 0.62))
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
	# No reticle and no centre dot: docs/40 owner question 6's default, and docs/09 bans a reticle
	# that reports certainty. The placeholder weapon in the hand is the only aiming furniture.

	var keys: Rect2 = help_rect(view_size)
	var help_at: Vector2 = Vector2(MARGIN, keys.position.y + 24.0)
	draw_rect(keys, Color(0.04, 0.05, 0.05, 0.58))
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
# The key bar: the strip that names the keys, full width. It sits above the bare hands' rest frame
# rather than under it: the hands reach to about 0.78 of the view's height at idle (the first-person
# gate's HANDS lane measures it at 1280x720 and 960x720, the same height at both), so the bar's top is
# 0.69 of the height. One rectangle, shared by the draw above and that lane.
const KEY_BAR_TOP_FRACTION: float = 0.69
const KEY_BAR_HEIGHT: float = 44.0


static func help_rect(view_size: Vector2) -> Rect2:
	return Rect2(MARGIN - 12.0, view_size.y * KEY_BAR_TOP_FRACTION, view_size.x - (MARGIN - 12.0) * 2.0, KEY_BAR_HEIGHT)


static func has_digit(text: String) -> bool:
	for i in text.length():
		if text[i].is_valid_int():
			return true
	return false
