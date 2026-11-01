extends Control
# The conversation panel: one of your colonists says how they are and what they are doing. Every line
# is a read model's own answer, not a second description:
#   the name      `identity.name`, the same name the Colony drawer and the HUD use.
#   how they feel `SimCondition.view` (the worst part, in the words the first-person HUD already uses
#                 for the player's own body) and `SimNeeds`: the worst need band's own first-person
#                 mutter line from `speech/lines.json` when that content exists, otherwise
#                 `SimNeeds.hud_clause(world, ent, true)`, the same panel sentence the top-down
#                 drawer shows. A body with nothing wrong says "I feel steady.", the first-person
#                 HUD's own fallback for an empty needs clause.
#   what they do `SimWorkRead.doing`, the Colony row's own "now" phrase.
#
# Presentation only: it reads the world and writes nothing. No numbers, no new information -- every
# word here is one the top-down screens already show. One action, Goodbye, which is Escape; the
# panel emits `closed` and decides nothing. The kit chrome is `Chrome`/`Locker`, the same as the
# Reports page and the work grid.

const Chrome = preload("res://ui/chrome.gd")
const Locker = preload("res://ui/locker.gd")
const SimCondition = preload("res://sim/condition.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const WorkRead = preload("res://sim/work_read.gd")

signal closed

const WIDTH: float = 660.0
const PAD: float = 28.0
const BODY_SIZE: int = 25
const ACTION_SIZE: int = 20
const NOW_LEAD: String = "now "
const GOODBYE: String = "Goodbye"
const GOODBYE_HINT: String = "Escape"
const GOODBYE_W: float = 160.0
const GOODBYE_H: float = 40.0
const ROW_GAP: float = 10.0
# The first-person HUD's own words for the condition view's worst part ("worst" 0..3), and its
# fallback for a body with nothing to report. Kept here as the same words, not a second language.
const CONDITION_WORDS: Array[String] = ["", "hurt", "badly hurt", "barely standing"]
const STEADY: String = "I feel steady."

var _entity: int = -1
var _name: String = ""
var _feel: String = ""
var _doing: String = ""


## The name the panel's header shows: the sim's own identity name.
static func name_of(world: Variant, entity: int) -> String:
	if world == null or entity < 0:
		return "Someone"
	var ident: Variant = world.components.get_component(entity, "identity")
	if ident is Dictionary:
		return String((ident as Dictionary).get("name", "Someone"))
	return "Someone"


## How the colonist feels, in one line: the condition's own words and the worst need's own words,
## both from the read models above. Never a grade, a bar or a number.
static func feel_of(world: Variant, entity: int) -> String:
	if world == null or entity < 0:
		return STEADY
	var condition: String = _condition_sentence(world, entity)
	var need: String = _need_sentence(world, entity)
	if condition != "" and need != "":
		return condition + " " + need
	if condition != "":
		return condition
	if need != "":
		return need
	return STEADY


## What the colonist is doing now, the Colony row's own phrase. "" for a body that read model does
## not describe.
static func doing_of(world: Variant, entity: int) -> String:
	return WorkRead.doing(world, entity)


## Sets the panel to one colonist. The caller owns when it opens and closes.
func show_colonist(world: Variant, entity: int) -> void:
	_entity = entity
	_name = name_of(world, entity)
	_feel = feel_of(world, entity)
	_doing = doing_of(world, entity)
	custom_minimum_size = Vector2(WIDTH, _natural_height())
	size = custom_minimum_size
	queue_redraw()


## What the panel is showing, for the gate: the sim's name, the read models' words, and the entity.
func shown() -> Dictionary:
	return {"entity": _entity, "name": _name, "feel": _feel, "doing": _doing}


func entity() -> int:
	return _entity


## Every line the panel draws, for the gate's digit scan. The header is the name; the goodbye action
## and its key hint are words too.
func lines() -> Array[String]:
	return [_name, _feel, NOW_LEAD + _doing, GOODBYE, GOODBYE_HINT]


func _natural_height() -> float:
	var wrap: float = WIDTH - PAD * 2.0
	var feel_h: float = _text_height(_feel, BODY_SIZE, wrap)
	var doing_h: float = _text_height(NOW_LEAD + _doing, BODY_SIZE, wrap)
	return Chrome.HEADER_H + PAD + feel_h + ROW_GAP + doing_h + ROW_GAP + GOODBYE_H + PAD


func _text_height(text: String, size: int, wrap: float) -> float:
	var font: Font = Chrome.font()
	var one: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var rows: int = maxi(1, ceili(one / maxf(1.0, wrap)))
	return float(rows) * Chrome.line_height(size)


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	Chrome.panel(self, rect, 1.0)
	var y: float = Chrome.header(self, rect, _name, 1.0)
	var font: Font = Chrome.font()
	var base: float = Chrome.ascent(BODY_SIZE)
	var wrap: float = size.x - PAD * 2.0
	y += PAD
	draw_string(font, Vector2(PAD, y + base), _feel, HORIZONTAL_ALIGNMENT_LEFT, wrap, BODY_SIZE, Chrome.TEXT)
	y += _text_height(_feel, BODY_SIZE, wrap) + ROW_GAP
	var lead: float = font.get_string_size(NOW_LEAD, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE).x
	draw_string(font, Vector2(PAD, y + base), NOW_LEAD, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, Chrome.TEXT_DIM)
	draw_string(font, Vector2(PAD + lead, y + base), _doing, HORIZONTAL_ALIGNMENT_LEFT, wrap - lead, BODY_SIZE, Chrome.TEXT)
	y += _text_height(NOW_LEAD + _doing, BODY_SIZE, wrap) + ROW_GAP
	Locker.button(self, _goodbye_rect(), GOODBYE, false, 1.0)
	var hint_base: float = Chrome.ascent(ACTION_SIZE)
	var hint_at: Vector2 = Vector2(PAD + GOODBYE_W + 16.0, y + (GOODBYE_H - Chrome.line_height(ACTION_SIZE)) * 0.5 + hint_base)
	draw_string(font, hint_at, GOODBYE_HINT, HORIZONTAL_ALIGNMENT_LEFT, -1, ACTION_SIZE, Chrome.TEXT_DIM)


func _goodbye_rect() -> Rect2:
	return Rect2(Vector2(PAD, size.y - PAD - GOODBYE_H), Vector2(GOODBYE_W, GOODBYE_H))


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if _goodbye_rect().has_point(mb.position):
		accept_event()
		closed.emit()


# --- the read models' sentences -------------------------------------------------------------

# The condition's own words: the worst part's word from the HUD's list, plus bleeding when a wound is
# open. "" when the body has nothing wrong. A closed wound that healed leaves `worst` 0, which is the
# honest answer the condition view gives.
static func _condition_sentence(world: Variant, entity: int) -> String:
	var view: Dictionary = SimCondition.view(world, entity)
	if view.is_empty():
		return ""
	var worst: int = int(view.get("worst", 0))
	var bleeding: bool = false
	for part in (view.get("parts", []) as Array):
		if bool((part as Dictionary).get("bleeding", false)):
			bleeding = true
			break
	var out: String = ""
	if worst > 0 and worst < CONDITION_WORDS.size():
		out = "I'm " + CONDITION_WORDS[worst] + "."
	if bleeding:
		out += ("" if out == "" else " ") + "I'm bleeding."
	return out


# The worst need's own line: the first-person mutter content when it exists, otherwise the read
# model's own panel clause. The choice of line is deterministic per body, so a conversation does not
# change its sentence every frame.
static func _need_sentence(world: Variant, entity: int) -> String:
	var band: String = SimNeeds.worst_band(world, entity)
	var line: String = _mutter_line(world, entity, band)
	if line != "":
		return line
	return SimNeeds.hud_clause(world, entity, true)


static func _mutter_line(world: Variant, entity: int, band: String) -> String:
	if band.is_empty() or world == null or not ("content" in world) or not (world.content is Dictionary):
		return ""
	var rows: Variant = (world.content as Dictionary).get("speech/lines.json", [])
	if not (rows is Array):
		return ""
	var id: String = "speech.mutter.%s" % band
	for row in rows as Array:
		var e: Dictionary = row as Dictionary
		if String(e.get("id", "")) != id:
			continue
		var lines: Variant = e.get("lines", [])
		if not (lines is Array) or (lines as Array).is_empty():
			return ""
		return String((lines as Array)[absi(entity) % (lines as Array).size()])
	return ""
