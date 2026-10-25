extends RefCounted
# One body part, in words, and what the survivor can do about it: the inspect pane's other face.
# A click on a part of the survivor's figure (`ui/paperdoll.gd`'s `part_at`) hands the pane over to
# that part until something else is picked -- docs/32's "selecting a body region opens known
# condition and available care information", and the step of the first playable journey that goes
# from "inspect" to "available care" (docs/32, "Acceptance").
#
# Everything on it comes out of three sim read models and nothing is worked out here:
#
#   what is wrong   `SimCondition.view`'s entry for the part: a state word and a handful of words and
#                   booleans. No integrity, no maximum, no fraction (`godot:ban:healthbar`) -- the
#                   pane has nothing to draw a fill from, so it draws none.
#   what to do      `SimTreatment.options_for(world, actor, patient, part)`: the channel verbs
#                   the T key and the street menu already offer, each dry-run through the same
#                   `_can_begin` and `_plan` the command takes. A verb the sim would allow is a
#                   button; a verb refused for a reason the survivor can act on (no dressing, the
#                   wound still bleeding, a wound too deep for these hands) is a dim line saying so;
#                   a verb refused because there is nothing for it to do is absent. So the pane
#                   cannot offer what the sim would refuse, and does not suggest that every verb can
#                   be aimed at every part -- only the four that `treat.begin` actually takes.
#   what is under way  the actor's `treatment` channel, by its verb and part alone. How long is
#                   left is not read: busy says *that*, never how long (docs/30, "The UI Field Kit,
#                   live").
#
# The button sends `treat.begin` with the patient and part named -- the same command the street
# menu's treat row carries (`sim/context.gd`'s `_treat_row`) -- and "stop" sends `treat.cancel`.

const Chrome = preload("res://ui/chrome.gd")
const Locker = preload("res://ui/locker.gd")
const UiText = preload("res://ui/text.gd")
const Palette = preload("res://presentation/palette.gd")
const SimCondition = preload("res://sim/condition.gd")
const SimTreatment = preload("res://sim/modules/treatment.gd")

const PAD: float = 16.0
# 25, not 30: the face draws whole at 2x there, and 30 drew the heading at a fraction.
const TITLE_TEXT: int = 25
const BODY_TEXT: int = 25
const LINE: float = 26.0
const BUTTON_H: float = 36.0
const BUTTON_GAP: float = 8.0

const STATE_WORDS: Array[String] = ["unhurt", "hurt", "badly hurt", "unusable"]

# The verbs in words a person would say, on a button.
const VERB_WORDS: Dictionary = {
	"pressure": "hold pressure",
	"bandage": "dress it",
	"clean": "clean it",
	"close": "close it",
	"tourniquet": "tie a tourniquet",
	"loosen": "loosen the tourniquet",
}
# The same verbs as what is going on, for the line that says a channel is under way.
const DOING_WORDS: Dictionary = {
	"pressure": "holding pressure on it",
	"bandage": "dressing it",
	"clean": "cleaning it",
	"close": "closing it",
	"tourniquet": "tying a tourniquet on it",
	"loosen": "loosening the tourniquet",
}
# Refusals the survivor can do something about, in their words. A reason missing from this table is
# one that only says there is nothing to do ("not-bleeding", "nothing-to-do"), and its verb is left
# off the pane rather than shown greyed: an absent verb and a refused one are different news.
const REASON_WORDS: Dictionary = {
	"no-bandage": "no dressing on you",
	"no-supply": "nothing to clean it with",
	"no-kit": "nothing to close it with",
	"no-tourniquet": "no tourniquet on you",
	"still-bleeding": "stop the bleeding first",
	"unskilled": "too deep for your hands",
	"cannot-channel": "not while you are moving like this",
	"patient-busy": "someone is already at it",
	"out-of-reach": "out of reach",
}
const STOP_VERB: String = "stop"


# Everything the pane draws for `part` of `patient`, as `actor` would treat it. {} when the part is
# not one the condition view knows -- the pane then says nothing rather than guess.
static func view_for(world: Variant, actor: int, patient: int, part: String) -> Dictionary:
	if world == null or part.is_empty():
		return {}
	var entry: Dictionary = {}
	for e in SimCondition.view(world, patient).get("parts", []) as Array:
		if String((e as Dictionary).get("part", "")) == part:
			entry = e as Dictionary
			break
	if entry.is_empty():
		return {}
	var running: String = ""
	var t: Variant = world.components.get_component(actor, "treatment")
	if t is Dictionary and String((t as Dictionary).get("part", "")) == part and int((t as Dictionary).get("patient", -1)) == patient:
		running = String((t as Dictionary).get("verb", ""))
	var offered: Array[String] = []
	var refused: Array[Dictionary] = []
	if running.is_empty():
		for o in SimTreatment.options_for(world, actor, patient, part):
			var d: Dictionary = o as Dictionary
			var verb: String = String(d.get("verb", ""))
			if not VERB_WORDS.has(verb):
				continue
			if bool(d.get("ok", false)):
				offered.append(verb)
			elif REASON_WORDS.has(String(d.get("reason", ""))):
				refused.append({"verb": verb, "reason": String(d.get("reason", ""))})
	return {
		"part": part,
		"label": SimCondition.label_of(part),
		"state": int(entry.get("state", 0)),
		"notes": _notes(entry),
		"running": running,
		"offered": offered,
		"refused": refused,
		"patient": patient,
	}


# What the condition view says about the part, one short phrase each, in the order a person would
# notice them: the blood first.
static func _notes(entry: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var dressing: String = String(entry.get("bandage", "none"))
	if bool(entry.get("bleeding", false)):
		out.append("bleeding")
	elif dressing != "none":
		out.append("under a %s dressing" % dressing)
	elif bool(entry.get("wounded", false)):
		out.append("a wound")
	var infected: String = String(entry.get("infected", "none"))
	if infected != "none":
		out.append(infected)
	var lasting: String = String(entry.get("lasting", "none"))
	if lasting != "none":
		out.append("an old %s" % lasting)
	if bool(entry.get("armored", false)):
		out.append("under armour")
	return out


# The verbs the pane's buttons carry, in the order they are drawn: the channel's stop when one is
# under way, else what the sim would allow.
static func verbs_of(view: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if view.is_empty():
		return out
	if not String(view.get("running", "")).is_empty():
		out.append(STOP_VERB)
		return out
	for v in view.get("offered", []) as Array:
		out.append(String(v))
	return out


static func word_of(verb: String) -> String:
	return "stop" if verb == STOP_VERB else String(VERB_WORDS.get(verb, verb))


# The command a button sends, or {} for none.
static func command_for(view: Dictionary, verb: String) -> Dictionary:
	if verb == STOP_VERB:
		return {"type": "treat.cancel"}
	if not VERB_WORDS.has(verb) or view.is_empty():
		return {}
	return {"type": "treat.begin", "patient": int(view.get("patient", -1)), "part": String(view.get("part", "")), "verb": verb}


# Where each button sits in a pane at `rect`: down the pane under the "care" groove, one a row, so a
# long verb never shares a row with another and the click lands on what it says. The draw and the
# click both come from here.
static func button_rects(rect: Rect2, view: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# On the art-pixel grid, like the frame `Locker.panel` snaps to: half a 26 px line is odd.
	var y: float = roundf((_care_top(rect, view) + LINE * 0.5) / Locker.PX) * Locker.PX
	for v in verbs_of(view):
		var w: float = minf(rect.size.x - PAD * 2.0, maxf(Locker.label_width(word_of(v), Locker.LABEL_SIZE), Locker.PX * 60.0))
		out.append({"verb": v, "rect": Rect2(Vector2(rect.position.x + PAD, y), Vector2(w, BUTTON_H))})
		y += BUTTON_H + BUTTON_GAP
	return out


# How tall the pane has to be to say everything about the part: the sheet gives it this much of the
# right column, taking it from the list above, so a refusal is never cut off at 1280x720.
static func height_for(view: Dictionary, wide: float) -> float:
	if view.is_empty():
		return 0.0
	var rect := Rect2(Vector2.ZERO, Vector2(1.0, 1.0))
	var y: float = _care_top(rect, view) + LINE * 0.5
	y += float(verbs_of(view).size()) * (BUTTON_H + BUTTON_GAP)
	var lines: int = 1
	if String(view.get("running", "")).is_empty() and not (view.get("refused", []) as Array).is_empty():
		lines = 0
		for r in view.get("refused", []) as Array:
			lines += refusal_lines(r as Dictionary, wide).size()
	return y + float(lines) * LINE + PAD


# A refusal as the pane writes it: "verb — why" on one line where it fits the pane's `wide`, else
# the verb on its line and the reason under it, indented -- never cut off with an ellipsis, which
# hid the reason itself at 1280x720.
static func refusal_lines(d: Dictionary, wide: float) -> Array[String]:
	var font: Font = Chrome.font()
	var verb: String = word_of(String(d.get("verb", "")))
	var why: String = String(REASON_WORDS.get(String(d.get("reason", "")), ""))
	var one: String = "%s — %s" % [verb, why]
	if font.get_string_size(one, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_TEXT).x <= wide:
		return [one]
	return [verb + " —", REFUSAL_INDENT + why]


const REFUSAL_INDENT: String = "  "


# Where the care section starts: under the header, the part's name, its state and its notes.
static func _care_top(rect: Rect2, view: Dictionary) -> float:
	var notes: int = maxi(1, (view.get("notes", []) as Array).size())
	return rect.position.y + Locker.HEAD_H + PAD + LINE * 2.0 + LINE * float(notes) + PAD + LINE


static func draw_pane(ci: CanvasItem, rect: Rect2, view: Dictionary, alpha: float) -> void:
	Locker.panel(ci, rect, alpha)
	var top: float = Locker.header(ci, rect, "body", alpha, "", Chrome.GLYPH_SMALL + Locker.PX * 3.0)
	Chrome.glyph(ci, "condition", Vector2(rect.end.x - Chrome.GLYPH_SMALL - Locker.PX * 5.0, rect.position.y + Locker.PX * 2.0 + floorf((Locker.TAPE_H - Chrome.GLYPH_SMALL) / 2.0)), true, alpha * 0.7)
	if view.is_empty():
		return
	var font: Font = Chrome.font()
	var x: float = rect.position.x + PAD
	var wide: float = rect.size.x - PAD * 2.0
	var y: float = top + PAD + Chrome.ascent(TITLE_TEXT)
	ci.draw_string(font, Vector2(x, y), UiText.fit(font, String(view.get("label", "")), TITLE_TEXT, wide), HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_TEXT, Locker._a(Locker.TEXT, alpha))
	y += LINE + 4.0
	# The state word in its condition tint, the only colour here that carries meaning -- and the word
	# beside it says the same thing, so it reads without the colour.
	var st: int = clampi(int(view.get("state", 0)), 0, STATE_WORDS.size() - 1)
	var tint: Color = Palette.CONDITION_TINTS[st] if st > 0 and st < Palette.CONDITION_TINTS.size() else Locker.TEXT_DIM
	ci.draw_string(font, Vector2(x, y), STATE_WORDS[st], HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_TEXT, Locker._a(tint, alpha))
	y += LINE
	var notes: Array = view.get("notes", []) as Array
	if notes.is_empty():
		ci.draw_string(font, Vector2(x, y), UiText.fit(font, "nothing you can see", BODY_TEXT, wide), HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_TEXT, Locker._a(Locker.TEXT_FAINT, alpha))
		y += LINE
	# The notes wear the part's tint too, the way the sheet's summary line under the figure does, so
	# "hurt" and "bleeding" read as one finding rather than two of different weight.
	for n in notes:
		ci.draw_string(font, Vector2(x, y), UiText.fit(font, String(n), BODY_TEXT, wide), HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_TEXT, Locker._a(tint if st > 0 else Locker.TEXT, alpha))
		y += LINE
	var care_y: float = _care_top(rect, view)
	Locker.groove(ci, Vector2(x, care_y - LINE - PAD / 2.0), wide, alpha)
	ci.draw_string(font, Vector2(x, care_y - LINE * 0.25), "care", HORIZONTAL_ALIGNMENT_LEFT, -1, Locker.SMALL_SIZE, Locker._a(Locker.TEXT_DIM, alpha))
	var buttons: Array[Dictionary] = button_rects(rect, view)
	var running: String = String(view.get("running", ""))
	var after: float = care_y + LINE * 0.5
	for n in buttons.size():
		var b: Dictionary = buttons[n]
		var r: Rect2 = b["rect"] as Rect2
		Locker.button(ci, r, word_of(String(b["verb"])), true, alpha)
		after = r.end.y + BUTTON_GAP
	var line_y: float = after + Chrome.ascent(BODY_TEXT)
	if not running.is_empty():
		ci.draw_string(font, Vector2(x, line_y), UiText.fit(font, "you are " + String(DOING_WORDS.get(running, running)), BODY_TEXT, wide), HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_TEXT, Locker._a(Locker.ACCENT, alpha))
		return
	var refused: Array = view.get("refused", []) as Array
	if buttons.is_empty() and refused.is_empty():
		ci.draw_string(font, Vector2(x, line_y), UiText.fit(font, "nothing to do for it", BODY_TEXT, wide), HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_TEXT, Locker._a(Locker.TEXT_FAINT, alpha))
		return
	var lines: Array[String] = []
	for r2 in refused:
		lines.append_array(refusal_lines(r2 as Dictionary, wide))
	for i in lines.size():
		# The sheet sizes the pane from `height_for`, so this only bites on a window too short for
		# even that; the last line that fits then says there is more rather than stopping mid-list.
		if line_y + LINE > rect.end.y - PAD / 2.0 and i < lines.size() - 1:
			ci.draw_string(font, Vector2(x, line_y), "and more besides", HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_TEXT, Locker._a(Locker.TEXT_FAINT, alpha))
			break
		ci.draw_string(font, Vector2(x, line_y), UiText.fit(font, lines[i], BODY_TEXT, wide), HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_TEXT, Locker._a(Locker.TEXT_DIM, alpha))
		line_y += LINE
