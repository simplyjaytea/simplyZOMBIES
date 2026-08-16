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

# Survivor order, head down, anatomical left before right. docs/05: the view is read as a
# body, not as a list. Ten parts, not six -- docs/05's permanent consequences describe "a
# one-armed survivor" as a real outcome, which needs two independently-damageable arms to
# produce; see docs/30-decisions.md. This is combat.gd's SURVIVOR_BODY_PARTS, not a second
# copy of it -- the view's order and the hit-roll's order are the same order because there
# is exactly one canonical part list.
const PART_ORDER: Array[String] = SimCombat.SURVIVOR_BODY_PARTS

# The only keys a part may carry. The gate asserts this exactly.
const PART_KEYS: Array[String] = ["part", "state", "prose"]

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


# Returns {"parts": [{part, state, prose}], "stance": int, "worst": int}, or {} when the
# entity has no body -- a zombie has no condition view, same as the oracle's null.
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
		# state is the discrete grade, never the integrity behind it.
		parts.append({"part": part, "state": s, "prose": label_of(part)})

	var posture: Variant = world.components.get_component(actor, "posture")
	var stance: int = 2 # Walk
	if posture is Dictionary:
		stance = int((posture as Dictionary).get("current", 2))

	return {"parts": parts, "stance": stance, "worst": worst}
