extends Control
# The player's HUD. What someone who has never seen the code needs in order to play.
#
# This replaces a single Label carrying one concatenated developer string -- tick counts,
# raw positions, aptitude integers, a serialisation fingerprint. That string still exists
# and is still useful; it moved behind the `M` raw-sheets toggle where it belongs.
#
# Two rules from docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable shape
# everything here, and check_hud.gd enforces them:
#
#   No gauges. Not for needs, not for condition, not for threat. A bar invites optimising a
#   number; a sentence makes you decide. Every clause on this screen comes from a sim read
#   model that returns prose -- needs.hud_clause, attention_read.clause, condition.view.
#
#   No raw pool values. The HUD never prints hunger 34 or integrity 12. If a number would
#   be genuinely useful it is because the design owes the player a sentence instead.
#
# Drawn with draw_string rather than anchored Labels, matching paperdoll.gd and
# work_panel.gd. A Control parented to a CanvasLayer keeps a zero-sized rect, so anchor
# presets on child Labels resolve against nothing and collapse into the top-left corner --
# which is exactly what the first version of this file did.

const SimNeeds = preload("res://sim/modules/needs.gd")
const SimAttentionRead = preload("res://sim/attention_read.gd")
const SimCondition = preload("res://sim/condition.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const SimContainers = preload("res://sim/modules/containers.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const Clock = preload("res://sim/time/clock.gd")
const Palette = preload("res://presentation/palette.gd")

const MARGIN: float = 24.0
const LINE: float = 34.0
const FONT_SIZE: int = 26
const SMALL_SIZE: int = 22

# Worst-part states from condition.gd, as a sentence rather than a grade.
const CONDITION_PROSE: Array[String] = ["", "hurt", "badly hurt", "barely standing"]

var show_raw: bool = false
var hint: String = ""

var _left: Array[String] = []
var _right: Array[String] = []
var _raw: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# `raw` is the old developer string, passed through unchanged and shown only on M.
func refresh(world: Variant, actor: int, raw: String) -> void:
	if world == null:
		return
	_left = _self_lines(world, actor)
	_right = _world_lines(world, actor)
	_raw = raw
	queue_redraw()


func _self_lines(world: Variant, actor: int) -> Array[String]:
	var lines: Array[String] = []

	var name: String = "You"
	var ident: Variant = world.components.get_component(actor, "identity")
	if ident is Dictionary and actor != int(world.player):
		name = String((ident as Dictionary).get("name", "They"))

	# Condition, from the same read model the paperdoll uses -- a state, never a fraction.
	var head: String = name
	var view: Dictionary = SimCondition.view(world, actor)
	if not view.is_empty():
		var worst: int = int(view.get("worst", 0))
		if worst > 0 and worst < CONDITION_PROSE.size() and not CONDITION_PROSE[worst].is_empty():
			head = "%s — %s" % [name, CONDITION_PROSE[worst]]
	lines.append(head)

	# Blood loss, ahead of needs because it is measured in minutes and thirst is measured in
	# hours. Same read-model contract: prose, no numbers, "" when there is nothing to say.
	var bleeding: String = SimWounds.hud_clause(world, actor)
	if not bleeding.is_empty():
		lines.append(bleeding)

	# Needs, already prose. hud_clause returns "" when there is nothing worth saying, which
	# is the correct amount of HUD for a survivor who is fine.
	var needs: String = SimNeeds.hud_clause(world, actor, false)
	if not needs.is_empty():
		lines.append(needs)

	# What you are standing next to, if it is worth going through. Prose and no digits, like every
	# other clause here -- it never says how much came out, only that there is something, or that
	# you have already had it. Placed after the body and before the diagnosis because it is the
	# least urgent thing on this list and the most easily ignored.
	var here: String = SimContainers.hud_clause(world, actor)
	if not here.is_empty():
		lines.append(here)

	# Infection reads as a symptom, never as a diagnosis the player has not earned.
	var diag: Variant = SimInfection.diagnosis_of(world, actor, 0)
	if diag is Dictionary:
		var label: String = String((diag as Dictionary).get("label", "clear"))
		if label != "clear" and not label.is_empty():
			lines.append(label)

	if not hint.is_empty():
		lines.append(hint)
	if bool(world.runOver):
		lines.append("The run is over.")
	return lines


func _world_lines(world: Variant, actor: int) -> Array[String]:
	var lines: Array[String] = []
	var tod: float = Clock.time_of_day(int(world.tick))
	lines.append("day %d, %s" % [Clock.day_number(int(world.tick)), Clock.PHASE_NAMES[Clock.phase_at(tod)]])

	# The spine, in words. docs/03 -- this is the trade the whole game is about, and it was
	# previously only visible through the developer overlay on O.
	var att: Dictionary = SimAttentionRead.clause(world, actor)
	lines.append(String(att["light"]))
	lines.append(String(att["worst"]))
	return lines


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var view: Vector2 = get_viewport_rect().size

	var y: float = MARGIN + FONT_SIZE
	for i in _left.size():
		# The first line is who you are; the rest are what is happening to you.
		var colour: Color = Palette.COLOURS["player"] if i == 0 else Palette.COLOURS["survivor"]
		draw_string(font, Vector2(MARGIN, y), _left[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, colour)
		y += LINE

	y = MARGIN + FONT_SIZE
	for line in _right:
		var w: float = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		draw_string(font, Vector2(view.x - MARGIN - w, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Palette.COLOURS["survivor"])
		y += LINE

	var keys: String = "F1 keys · Tab gear · J work · O overlay · M raw"
	draw_string(font, Vector2(MARGIN, view.y - MARGIN), keys, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE, Palette.COLOURS["outline"])

	if show_raw and not _raw.is_empty():
		# The developer sheet, wrapped so a long line does not run off the district.
		draw_string(font, Vector2(MARGIN, view.y - MARGIN - LINE * 2.0), _raw, HORIZONTAL_ALIGNMENT_LEFT, view.x - MARGIN * 2.0, SMALL_SIZE, Palette.COLOURS["outline"])
