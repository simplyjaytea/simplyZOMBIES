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
#   (The one dial on the screen is the car's, not this file's: ui/dashboard.gd draws a
#   speedometer and a fuel needle while the player is at a wheel, because those are the
#   machine's own instruments and carry no numbers; docs/30 "The dashboard" records the line.)
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
const SimSightings = preload("res://sim/modules/sightings.gd")
const SimWeather = preload("res://sim/modules/weather.gd")
const SimCondition = preload("res://sim/condition.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const SimContainers = preload("res://sim/modules/containers.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const SimCamp = preload("res://sim/modules/camp.gd")
const SimChronicle = preload("res://sim/modules/chronicle.gd")
const SimAttachments = preload("res://sim/modules/attachments.gd")
const SimTreatment = preload("res://sim/modules/treatment.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimVehicles = preload("res://sim/modules/vehicles.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const Clock = preload("res://sim/time/clock.gd")
const Palette = preload("res://presentation/palette.gd")
const Chrome = preload("res://ui/chrome.gd")

const MARGIN: float = 24.0
const LINE: float = 34.0
const FONT_SIZE: int = 26
const SMALL_SIZE: int = 22
# What the quick strip takes off the bottom of the screen. A hard copy of
# `ui/inventory_panel.gd`'s STRIP_H plus its margin -- the two are the same number in two files
# because this one must not reach into the sheet to draw a line of text, and `godot:check:hud`'s
# key-line lane is what would notice if they drifted far enough to overlap.
const STRIP_CLEARANCE: float = 116.0

# The two cards and the action bar -- the owner's pick of 2026-09-16 ("Option A, two cards",
# docs/30's "The alpha shell"). The numbers are the mockup's, doubled: the artboards were drawn
# at 960x540 against a screenshot of the shipped 1920x1080 screen.
#
# A card is a *minimum* width, not a fixed one. A chronicle line longer than the nominal box
# would otherwise hang off the left edge of a right-aligned card, which is the one way a drawn
# panel can look broken; `_draw_card` grows the box to whatever the widest line needs.
const CARD_ALPHA: float = 0.86
const YOU_CARD_W: float = 472.0
const OUT_CARD_W: float = 496.0
const CARD_PAD: float = 14.0      # inner left/right gutter, and the skirt below the last line
const BAR_W: float = 1296.0
const BAR_H: float = 48.0
const BAR_GAP: float = 12.0       # between a key and its words, and around the separating dot
const ACTION_SEP: String = " · "

# Worst-part states from condition.gd, as a sentence rather than a grade.
const CONDITION_PROSE: Array[String] = ["", "hurt", "badly hurt", "barely standing"]

var show_raw: bool = false
var hint: String = ""

var _left: Array[String] = []
var _right: Array[String] = []
var _raw: String = ""
var _action: String = ""


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

	# How much it hurts -- which is the pain actually felt, not the damage carried. Somebody full
	# of painkillers says less than their wounds warrant, which is docs/05's tactical option
	# working as intended and, deliberately, its trap.
	var hurt: String = SimWounds.pain_clause(world, actor)
	if not hurt.is_empty():
		lines.append(hurt)

	# Fever, if there is any. Deliberately the same word zombie infection's early stages use and
	# deliberately silent about which it is: docs/05 says sepsis "presents as fever, pain, and
	# worsening -- which is also how zombie infection presents in its early stages", and that
	# ambiguity is the feature, not a gap in the read model.
	var fever: String = SimWounds.sepsis_clause(world, actor)
	if not fever.is_empty():
		lines.append(fever)

	# What you are standing next to, if it is worth going through. Prose and no digits, like every
	# other clause here -- it never says how much came out, only that there is something, or that
	# you have already had it. Placed after the body and before the diagnosis because it is the
	# least urgent thing on this list and the most easily ignored.
	var here: String = SimContainers.hud_clause(world, actor)
	if not here.is_empty():
		lines.append(here)

	# A weapon that will not work, and why. Placed high on purpose -- a trigger pull that does
	# nothing and says nothing is the worst way to meet the fact that a gun is an assembly.
	var jammed_up: String = SimAttachments.refusal_clause(world, actor)
	if not jammed_up.is_empty():
		lines.append(jammed_up)

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
	# The sky, in one sentence while it rains and nothing when it does not (docs/adr/0015).
	var sky: String = SimWeather.hud_clause(world)
	if not sky.is_empty():
		lines.append(sky)

	# The spine, in words. docs/03 -- this is the trade the whole game is about, and it was
	# previously only visible through the developer overlay on O.
	var att: Dictionary = SimAttentionRead.clause(world, actor)
	lines.append(String(att["light"]))
	lines.append(String(att["worst"]))

	# Where home is, once it is somewhere you chose. Nothing at all until a camp exists, because
	# until then home is the annex the generator sited and the player has never had to find it.
	var camp: String = SimCamp.hud_clause(world, actor)
	if not camp.is_empty():
		lines.append(camp)

	# What you remember seeing, which is the other half of what the marks on the ground say.
	# docs/28: the prose "degrades -- a moment ago, then a while ago, then nothing" -- and the
	# read model is what decides when nothing is the honest answer, not this line.
	var seen: String = SimSightings.clause(world, actor)
	if not seen.is_empty():
		lines.append(seen)
	# What happened to the colony: a death, a succession, someone at the gate. The sim's
	# chronicle keeps the record; this column shows what is recent enough to still be news,
	# newest first, in words (decision 12 of docs/30's "The playable state").
	for line in SimChronicle.lines(world):
		lines.append(line)
	return lines


# What is written beside the body itself, rather than in a corner. docs/23 has asked for
# "condition and stamina readouts in the world, not a corner" since the prose contract landed;
# this is the half of it that ships.
#
# One line, and only over **the player's own body**. A line over every pawn is a name plate, and a
# name plate is refused three times over in docs/30 -- with the reference HUD on 2026-09-01, with
# the Dungeon Settlers look on 2026-09-03, and again on 2026-09-08 -- because a floating word over
# a figure in the street is a certainty about who and what they are that the peripheral-anonymity
# clause denies. Over your own body it is not a claim about someone else; it is you noticing your
# own arm.
#
# The corner column keeps its lines and this does not replace them: check_hud's quiet-survivor and
# selected-colonist lanes are what prove the prose contract holds, and a tag that emptied them
# would leave those lanes with nothing to judge. It says the things a *glance at yourself* would
# say -- which limb, and whether it is bleeding -- and leaves fever, hunger and the sky to the
# column, which is what the tag deliberately stays silent about.
#
# Digit-free like everything else here, and "" when there is nothing to say, which is the correct
# amount of tag for a survivor who is fine.
const TAG_MAX_PARTS: int = 2
static func pawn_tag(world: Variant, actor: int) -> String:
	if world == null or actor < 0:
		return ""
	var view: Dictionary = SimCondition.view(world, actor)
	if view.is_empty():
		return ""
	var parts: Array[String] = []
	var bleeding: bool = false
	var dressed: String = ""
	for entry in view.get("parts", []) as Array:
		var d: Dictionary = entry as Dictionary
		if bool(d.get("bleeding", false)):
			bleeding = true
		# The worst couple of parts, in the order condition.gd already ranks them, said the way a
		# person would: you favour a limb, you do not report its state.
		if int(d.get("state", 0)) > 0 and parts.size() < TAG_MAX_PARTS:
			parts.append("favouring the " + SimCondition.label_of(String(d.get("part", ""))))
		elif String(d.get("lasting", "none")) == "limp" and parts.size() < TAG_MAX_PARTS:
			parts.append("limping")
		if dressed.is_empty() and String(d.get("bandage", "none")) != "none":
			dressed = String(d.get("bandage", "none")) + " dressing"
	if bleeding:
		parts.append("bleeding")
	elif not dressed.is_empty():
		parts.append(dressed)
	if parts.is_empty():
		return ""
	return " · ".join(parts)


# --- the action line -----------------------------------------------------------------------
#
# What the three contextual keys would do, right here, in the words the sim already uses.
# **The sim decides the verb; presentation names the key.** Nothing here tells the player
# anything a read model was not already willing to say for some other screen, and when no read
# model says anything the line is "" and the bar draws nothing at all.
#
# Digit-free by construction rather than by scrubbing: every clause is either a sim read model
# already under the HUD's digit ban (fortify's window prose, the noise device's one word, the
# container and vehicle clauses) or a phrase built here out of a part label and a person's name.
# check_hud's ACTION lane scans the built line and proves its scanner on "E — 3 boards".
#
# **`SimTreatment.context` is deliberately not called.** It reads like the T key's read model and
# it is not one: it cancels a running channel and calls `begin`, so a HUD that asked it "what
# would T do?" four times a second would *start treating people*. The two facts it branches on
# are pure, and they are what this reads instead -- a channel already on this body, and
# `_nearest_needing_care`, which is `context`'s own patient pick with none of the doing. The verb
# is still the sim's: `options_for` dry-runs every rung and this names the first one that would
# actually be allowed, so the bar cannot offer a rung the sim would refuse.
const VERB_PROSE: Dictionary = {
	"pressure": "press",
	"bandage": "dress",
	"clean": "clean",
	"close": "stitch",
}


static func action_line(world: Variant, actor: int, look: Dictionary, hint: String) -> String:
	if world == null or actor < 0:
		return ""
	var clauses: Array[String] = []
	var reach: String = _reach_clause(world, actor, look, hint)
	if not reach.is_empty():
		clauses.append("E — " + reach)
	var aid: String = _aid_clause(world, actor)
	if not aid.is_empty():
		clauses.append("T — " + aid)
	var rescue: String = _rescue_clause(world, actor)
	if not rescue.is_empty():
		clauses.append("H — " + rescue)
	return ACTION_SEP.join(clauses)


# E, in main.gd's own order: the window you are facing, the bait, the device under your hand,
# then the top rung of the rest of the ladder, then the cupboard, then the car. `hint` is the
# context line main.gd has already resolved for this frame, and it is the last word rather than
# the first -- mostly it is the same fortify look-at read through a different door, so it only
# wins when this file's own sources have gone quiet and main.gd knows about something they do not.
# The content-error hint is not an action: it is a fault report main.gd borrows the hint line for,
# and naming a key beside it would be a lie about what E does.
#
# `SimFortify.rung_of` is deliberately asked after the look-at group and before the cupboard and
# the car: those two already have their own read models (`SimContainers.hud_clause`,
# `SimVehicles.hud_clause`) and `rung_of` says nothing while either would fire, so the order here
# never contradicts the order `_use_context` actually takes. Past that, this is the one place the
# bar names sleep, a fire, a filter, the latrine, a bench, a trap, the bait, a lift, a barricade --
# docs/23's follow-up "the ladder names its rung": the sim decides the verb, this only asks it.
static func _reach_clause(world: Variant, actor: int, look: Dictionary, hint: String) -> String:
	for key in ["window", "noisemaker", "device"]:
		var clause: String = String(look.get(key, ""))
		if not clause.is_empty():
			return clause
	var rung: String = String(SimFortify.rung_of(world, actor).get("prose", ""))
	if not rung.is_empty():
		return rung
	var here: String = SimContainers.hud_clause(world, actor)
	if not here.is_empty():
		return here
	var car: String = SimVehicles.hud_clause(world, actor)
	if not car.is_empty():
		return car
	if not hint.is_empty() and not hint.begins_with("content: "):
		return hint
	return ""


# T. A channel already running says the one thing the key does to it, which is end it; otherwise
# the nearest body that wants a rung, the wound the condition view ranks first, and the rung the
# sim would actually allow.
static func _aid_clause(world: Variant, actor: int) -> String:
	if world.components.has_component(actor, "treatment"):
		return "stop"
	var patient: int = SimTreatment._nearest_needing_care(world, actor)
	if patient < 0:
		return ""
	var part: String = _worst_part(world, patient)
	if part.is_empty():
		return ""
	var verb: String = ""
	for option in SimTreatment.options_for(world, actor, patient, part):
		var o: Dictionary = option as Dictionary
		if bool(o.get("ok", false)):
			verb = String(o.get("verb", ""))
			break
	if verb.is_empty() or not VERB_PROSE.has(verb):
		return ""
	var label: String = SimCondition.label_of(part)
	if patient == actor:
		return "%s your %s" % [String(VERB_PROSE[verb]), label]
	return "%s %s's %s" % [String(VERB_PROSE[verb]), _name_of(world, patient, "their"), label]


# Which wound is "the" wound, in the order the condition view already ranks parts -- bleeding
# first, because blood loss is the only thing on that ladder that kills.
static func _worst_part(world: Variant, patient: int) -> String:
	var view: Dictionary = SimCondition.view(world, patient)
	if view.is_empty():
		return ""
	var wounded: String = ""
	for entry in view.get("parts", []) as Array:
		var d: Dictionary = entry as Dictionary
		if bool(d.get("bleeding", false)):
			return String(d.get("part", ""))
		if wounded.is_empty() and bool(d.get("wounded", false)):
			wounded = String(d.get("part", ""))
	return wounded


# H. Somebody in reach with a zombie's hands on them, by name, because who it is decides whether
# you go.
static func _rescue_clause(world: Variant, actor: int) -> String:
	var victim: int = SimShambler.rescue_target(world, actor)
	if victim < 0:
		return ""
	return "pull %s free" % _name_of(world, victim, "them")


static func _name_of(world: Variant, entity: int, fallback: String) -> String:
	var ident: Variant = world.components.get_component(entity, "identity")
	if ident is Dictionary:
		var name: String = String((ident as Dictionary).get("name", ""))
		if not name.is_empty():
			return name
	return fallback


# main.gd hands the line over once a frame; the bar draws "" as nothing at all.
func set_action(text: String) -> void:
	if text == _action:
		return
	_action = text
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var view: Vector2 = get_viewport_rect().size
	# The two cards. The columns themselves are untouched -- the header is chrome, never a line
	# in `_left`, so a healthy survivor is still a one-line card and check_hud's QUIET lane still
	# has the array it judges.
	_draw_card(font, view, _left, "you", false)
	_draw_card(font, view, _right, "outside", true)
	_draw_action_bar(font, view)

	if show_raw and not _raw.is_empty():
		# The developer sheet, wrapped so a long line does not run off the district, and above
		# the action bar rather than through it.
		draw_string(font, Vector2(MARGIN, view.y - MARGIN - STRIP_CLEARANCE - BAR_H - LINE), _raw, HORIZONTAL_ALIGNMENT_LEFT, view.x - MARGIN * 2.0, SMALL_SIZE, Palette.COLOURS["outline"])


# One card in `ui/chrome.gd`'s skin: panel, bracketed corners, a header strip, and the column's
# lines inside it. It sizes to its content in both directions -- a card with a fixed height would
# either clip the chronicle or hang an empty box over the street on a quiet day.
func _draw_card(font: Font, view: Vector2, lines: Array[String], label: String, right: bool) -> void:
	if lines.is_empty():
		return
	var width: float = OUT_CARD_W if right else YOU_CARD_W
	for line in lines:
		width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + CARD_PAD * 2.0)
	var height: float = Chrome.HEADER_H + lines.size() * LINE + CARD_PAD
	var left: float = view.x - MARGIN - width if right else MARGIN
	var rect := Rect2(Vector2(left, MARGIN), Vector2(width, height))
	Chrome.panel(self, rect, CARD_ALPHA)
	var y: float = Chrome.header(self, rect, label, CARD_ALPHA) + FONT_SIZE + 2.0
	for i in lines.size():
		# The first line of the "you" card is who you are; the rest are what is happening.
		var colour: Color = Palette.COLOURS["player"] if i == 0 and not right else Palette.COLOURS["survivor"]
		var x: float = left + CARD_PAD
		if right:
			x = left + width - CARD_PAD - font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		draw_string(font, Vector2(x, y), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, colour)
		y += LINE


# The action bar, centred above the quick strip: the contextual clauses with their key in amber,
# then the standing key hint in the tail, all measured first and placed as one centred group so
# the bar reads as one line rather than three columns that drift apart as the line changes.
func _draw_action_bar(font: Font, view: Vector2) -> void:
	# Digit-free, like every other line on this screen: the strip draws its own key names, and the
	# speed keys are punctuation now rather than the number row (docs/30, "The inventory sheet").
	var keys: String = "F1 keys · Tab gear · J work · P pause · - = speed · Esc menu · O overlay · M raw"
	var size: int = FONT_SIZE - 2
	var runs: Array = []
	for clause in _action.split(ACTION_SEP, false):
		if not runs.is_empty():
			runs.append(["·", size, Chrome.TEXT_FAINT])
		var parts: PackedStringArray = String(clause).split(" — ")
		if parts.size() >= 2:
			runs.append([String(parts[0]), size, Chrome.ACCENT])
			runs.append([" — ".join(parts.slice(1)), size, Chrome.TEXT])
		else:
			runs.append([String(clause), size, Chrome.TEXT])
	if not runs.is_empty():
		runs.append(["·", size, Chrome.TEXT_FAINT])
	runs.append([keys, SMALL_SIZE - 2, Chrome.TEXT_DIM])
	var total: float = BAR_GAP * float(runs.size() - 1)
	for run in runs:
		total += font.get_string_size(String((run as Array)[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, int((run as Array)[1])).x
	# Like the cards, the bar is a minimum rather than a fixed box: a car's clause is a whole
	# sentence and a group wider than 1296 would otherwise hang out of both ends of its own panel.
	var bar_w: float = clampf(total + CARD_PAD * 2.0, BAR_W, view.x - MARGIN * 2.0)
	var bar := Rect2(Vector2(roundf((view.x - bar_w) * 0.5), view.y - MARGIN - STRIP_CLEARANCE - BAR_H), Vector2(bar_w, BAR_H))
	Chrome.panel(self, bar, CARD_ALPHA)
	var x: float = bar.position.x + (bar.size.x - total) * 0.5
	var baseline: float = bar.position.y + bar.size.y * 0.5 + float(size) * 0.36
	for run in runs:
		var r: Array = run as Array
		draw_string(font, Vector2(x, baseline), String(r[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(r[1]), r[2] as Color)
		x += font.get_string_size(String(r[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(r[1])).x + BAR_GAP
