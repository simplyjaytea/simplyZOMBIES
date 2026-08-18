extends RefCounted
# The condition view: everything the screen is allowed to know about a body.
#
# docs/05-health-injury.md#the-condition-view. A state and a sentence per part, and
# deliberately **no integrity value, no maximum, and no fraction** -- so a fill is not
# merely discouraged, it is not computable from what the screen has. That is
# hardcore-contract clause 4 made mechanical rather than merely stated, and
# check_ban_health_bar.gd serialises the result and asserts the absence.
#
# It lives here rather than in presentation because it is a read model over the body
# component, and because presentation/main.gd and ui/inventory_panel.gd each built it
# inline and had already drifted apart. One builder means one place to gate.
#
# Adding a numeric field to the dictionary this returns is the change that breaks the ban.
# The gate will fail; re-read clause 4 before widening it.

const SimHealth = preload("res://sim/modules/health.gd")
const SimCombat = preload("res://sim/combat.gd")
const SimInfection = preload("res://sim/modules/infection.gd")

# Survivor order, head down, anatomical left before right. docs/05: the view is read as a
# body, not as a list. Ten parts, not six -- docs/05's permanent consequences describe "a
# one-armed survivor" as a real outcome, which needs two independently-damageable arms to
# produce; see docs/30-decisions.md. This is combat.gd's SURVIVOR_BODY_PARTS, not a second
# copy of it -- the view's order and the hit-roll's order are the same order because there
# is exactly one canonical part list.
const PART_ORDER: Array[String] = SimCombat.SURVIVOR_BODY_PARTS

# The only keys a part may carry. The gate asserts this exactly.
#
# wounded, infected, and armored joined this session, for the paperdoll revamp -- all three
# are words or booleans, never the number behind them: `wounded` says a wound was recorded
# on this part, not what kind or how bad; `infected` is diagnosis_of_part's `actionable`
# word ("none"/"watch"/"treat"/"critical"), the exact same non-leaking read the HUD already
# uses, never a stage number and never `transmitted`; `armored` says coverage exists, never
# the coverage fraction itself. Extending this dictionary with a raw one is still the change
# that breaks the ban -- these three were chosen because none of them can become one.
#
# `bleeding` joined for Slice 2 Part A -- a bool, never the bleed rate or the blood-loss
# fraction behind it. `bandage` does NOT join yet: every wound's bandage is "none" until
# Part B writes anything else, and CLAUDE.md is explicit that a field which can only take
# one value is a gate that cannot fail. It lands with Part B, with its true negative.
const PART_KEYS: Array[String] = ["part", "state", "prose", "wounded", "infected", "armored", "bleeding"]

# Humanized display for the sided parts. Head and torso need no entry -- the raw key is
# already the word. Without this, "arm_left" would be the literal text a screen shows,
# which is the same class of leak as a raw number: the player should never read the sim's
# key, only what it means.
const PART_LABELS: Dictionary = {
	"arm_left": "left arm", "arm_right": "right arm",
	"hand_left": "left hand", "hand_right": "right hand",
	"leg_left": "left leg", "leg_right": "right leg",
	"foot_left": "left foot", "foot_right": "right foot",
}

static func label_of(part: String) -> String:
	return String(PART_LABELS.get(part, part))


# Does this part have a recorded wound? injuries.wounds is append-only today -- nothing
# ever marks one treated (docs/05's fracture/sprain/burn/concussion types and treatment
# state are open items, see HANDOFF) -- so this says a wound was sustained here, not that it
# is still open. Honest about what the sim actually knows rather than implying more.
static func _has_wound(world: Variant, actor: int, part: String) -> bool:
	var inj: Variant = world.components.get_component(actor, "injuries")
	if not (inj is Dictionary):
		return false
	for wound in (inj as Dictionary).get("wounds", []) as Array:
		if String((wound as Dictionary).get("bodyPart", "")) == part:
			return true
	return false


# Same shape as _has_wound, but true only while this part carries a wound that is still
# open (bleeding == true) -- a clotted wound still counts for `wounded` above, but not here.
static func _is_bleeding(world: Variant, actor: int, part: String) -> bool:
	var inj: Variant = world.components.get_component(actor, "injuries")
	if not (inj is Dictionary):
		return false
	for wound in (inj as Dictionary).get("wounds", []) as Array:
		var w: Dictionary = wound as Dictionary
		if String(w.get("bodyPart", "")) == part and bool(w.get("bleeding", false)):
			return true
	return false


# Returns {"parts": [{part, state, prose, wounded, infected, armored}], "stance": int,
# "worst": int}, or {} when the entity has no body -- a zombie has no condition view, same
# as the oracle's null.
static func view(world: Variant, actor: int) -> Dictionary:
	if world == null:
		return {}
	var body: Variant = world.components.get_component(actor, "body")
	if not (body is Dictionary):
		return {}
	var b: Dictionary = body as Dictionary

	var parts: Array = []
	var worst: int = 0
	for part in PART_ORDER:
		if not b.has(part):
			continue
		var st: Variant = SimHealth.part_state(b, part)
		if st == null:
			continue
		var s: int = int(st)
		worst = maxi(worst, s)
		# The untrained tier, same as everywhere else this screen reads a diagnosis --
		# HANDOFF's "one voice" note: there is no skill web yet to scale against.
		var diag: Dictionary = SimInfection.diagnosis_of_part(world, actor, 0, part)
		# state is the discrete grade, never the integrity behind it. wounded/infected/armored
		# are words and booleans for the same reason -- see PART_KEYS above.
		parts.append({
			"part": part,
			"state": s,
			"prose": label_of(part),
			"wounded": _has_wound(world, actor, part),
			"infected": String(diag.get("actionable", "none")),
			"armored": SimInfection.armor_coverage_of(world, actor, part) > 0.0,
			"bleeding": _is_bleeding(world, actor, part),
		})

	var posture: Variant = world.components.get_component(actor, "posture")
	var stance: int = 2 # Walk
	if posture is Dictionary:
		stance = int((posture as Dictionary).get("current", 2))

	return {"parts": parts, "stance": stance, "worst": worst}
