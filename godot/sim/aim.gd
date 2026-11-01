class_name SimAim
extends RefCounted
# Aim is a second heading, priced at a walk (docs/30, the decoupled paperdoll, decision 7; docs/23's
# "Aim is a second heading"; alpha plan A9 with the owner's 2026-10-19 answer to Q3: the cursor is
# the aimer, the weapon points at it and the body follows, the way Project Zomboid plays it).
#
# A body carries `facing` -- where its feet go, written from its velocity every tick it moves -- and,
# once the player has proposed one, `aim` -- where its torso, its head and its weapon point. The
# shot, the swing and the shadowcast read the aim (`radians_of`); motion keeps the heading. **An
# absent `aim` reads as `facing`**, which is what keeps every fixture, every headless campaign and
# every body that never received an `aim` command describing exactly the world it described before:
# nothing but the `aim` command ever writes one, and only presentation pushes that command.
#
# The price, and it is the hardcore half of the decision: an aim that differs from the heading is
# held only at Walk pace or slower (`holds`). At Jog and Sprint the aim snaps to the heading every
# tick (`world._integrate_movement`), so a running survivor looks and shoots where they run -- you
# do not track a target over your shoulder at a jog. A walking one may, and pays for it in the cone
# (`twist`, read by `SimRanged._refresh_cone`), which widens *past* `WIDE_HALF` because a moving
# shooter is already pinned there and a term under that clamp would be a dead socket.
#
# Anything else that turns a body -- an NPC facing a threat, a car turning its driver -- turns the
# aim with it (`follow_facing`), so a stale proposal can never point a swing the body no longer
# faces. A zombie never grows one.
#
# The aim also has a pitch (docs/40, "Aim: yaw and pitch", slice 3): radians above level, positive
# up, clamped to PITCH_LIMIT. It is an optional `pitch` key on the `aim` component, and **an absent
# key reads 0** (`pitch_of`), so an aim written before pitch existed, an old save and every top-down
# command describe a level aim exactly as before. A level pitch is stored as the absent key rather
# than as 0, which keeps every aim the top-down game writes byte for byte what it was, and leaves a
# negative zero nowhere to be stored. `propose` writes the yaw and the pitch together or neither.
# `follow_facing` leaves the pitch alone: snapping the yaw to the heading does not tilt the head.
#
# An NPC that turns to a body tilts its head as well (`set_pitch`, from `npc_combat._face_at`), and
# an NPC has no yaw proposal of its own, so it carries a **pitch-only aim**: an `aim` with a `pitch`
# and no `radians`. That shape holds no yaw. `radians_of` reads its facing, `twist` is 0 and
# `follow_facing` writes no yaw into it, so the colonist turns, walks, sees and shoots exactly as a
# body with no `aim` does. Only the `aim` command gives it a yaw (docs/30, "A pitch with no yaw").
# Nothing reads the pitch for a hit yet; docs/40's slices 5 and 6 do.

const SimStancesRes = preload("res://sim/stances.gd")

# The fastest rung that may hold an aim apart from the heading.
const HELD_UP_TO: int = SimStancesRes.Stance.Walk
# How far the aim tilts from level, either way: the first-person camera's own limit (docs/40).
const PITCH_LIMIT: float = 1.30


# The heading the shot, the swing and the eyes use: the `aim` component's, or `facing` when there
# is none, or 0 when there is neither.
static func radians_of(components: Variant, entity: int) -> float:
	var aim: Variant = components.get_component(entity, "aim")
	if aim is Dictionary and (aim as Dictionary).has("radians"):
		return float((aim as Dictionary)["radians"])
	var facing: Variant = components.get_component(entity, "facing")
	if facing is Dictionary:
		return float((facing as Dictionary).get("radians", 0.0))
	return 0.0


# The pitch the aim holds, radians above level: the `aim` component's `pitch`, or 0 when the key or
# the component is absent.
static func pitch_of(components: Variant, entity: int) -> float:
	var aim: Variant = components.get_component(entity, "aim")
	if aim is Dictionary:
		return float((aim as Dictionary).get("pitch", 0.0))
	return 0.0


# Whether `entity` may hold an aim apart from its heading this tick: a body on Walk or a slower
# rung, or one with no posture at all (it has no rung to be too fast on) -- and never one riding or driving a vehicle. Presentation asks the same
# question before it draws the cursor's bearing ahead of the tick that will take it, so the drawn
# weapon and the sim's rule cannot disagree.
static func holds(components: Variant, entity: int) -> bool:
	# A rider faces the way the machine points (SimVehicles._pin_driver), and so does their aim.
	if components.has_component(entity, "mounted"):
		return false
	var posture: Variant = components.get_component(entity, "posture")
	if not (posture is Dictionary):
		return true
	return int((posture as Dictionary).get("current", SimStancesRes.DEFAULT_STANCE)) <= HELD_UP_TO


# Writes a proposed aim. A stationary body turns its feet with it, the way the single heading always
# did; a moving one keeps its heading and turns only the aim, and only on a rung that `holds`.
# The pitch is written with the yaw or not at all, so a refused proposal leaves both as they were.
# Returns whether the proposal took.
static func propose(components: Variant, entity: int, radians: float, moving: bool, pitch: float = 0.0) -> bool:
	# A yaw that is not a number is no proposal: it would pass `canonical` and be stored.
	if not is_finite(radians):
		return false
	if moving and not holds(components, entity):
		return false
	var r: float = canonical(radians)
	if not moving:
		var facing: Variant = components.get_component(entity, "facing")
		if facing is Dictionary:
			(facing as Dictionary)["radians"] = r
	var aim: Variant = components.get_component(entity, "aim")
	if aim is Dictionary:
		(aim as Dictionary)["radians"] = r
	else:
		aim = {"radians": r}
		components.set_component(entity, "aim", aim)
	_write_pitch(aim as Dictionary, pitch)
	return true


# Tilts a body's head without turning it: what an NPC does when it faces a body
# (`npc_combat._face_at`). A body with an aim keeps its yaw. One without grows a pitch-only aim, and
# a level pitch on a pitch-only aim removes it, so a colonist who looks level again carries exactly
# what it carried before.
static func set_pitch(components: Variant, entity: int, pitch: float) -> void:
	var aim: Variant = components.get_component(entity, "aim")
	if aim is Dictionary:
		_write_pitch(aim as Dictionary, pitch)
		if (aim as Dictionary).is_empty():
			components.remove(entity, "aim")
		return
	var p: float = clamp_pitch(pitch)
	if p != 0.0:
		components.set_component(entity, "aim", {"pitch": p})


# The pitch from an eye to a point `rise_mm` above it (negative: below) and `run_metres` away on the
# ground, clamped and canonical. Level for a point straight overhead or underfoot.
static func pitch_toward(rise_mm: int, run_metres: float) -> float:
	if not (run_metres > 0.0):
		return 0.0
	return clamp_pitch(atan2(float(rise_mm) / 1000.0, run_metres))


# A pitch the component may hold: finite, inside PITCH_LIMIT, and never a negative zero. Anything
# that is not a number reads as level.
static func clamp_pitch(pitch: float) -> float:
	if not is_finite(pitch):
		return 0.0
	return canonical(clampf(pitch, -PITCH_LIMIT, PITCH_LIMIT))


# The one write of the key: a level pitch is the absent key, so neither 0 nor -0.0 is ever stored.
static func _write_pitch(aim: Dictionary, pitch: float) -> void:
	var p: float = clamp_pitch(pitch)
	if p == 0.0:
		aim.erase("pitch")
	else:
		aim["pitch"] = p


# The aim follows the heading: called wherever something other than the `aim` command turns a body,
# and every tick a body moves faster than `holds` allows. A body with no `aim` is left without one,
# a pitch-only aim is left without a yaw, and the pitch is left where it was.
static func follow_facing(components: Variant, entity: int) -> void:
	var aim: Variant = components.get_component(entity, "aim")
	var facing: Variant = components.get_component(entity, "facing")
	if aim is Dictionary and (aim as Dictionary).has("radians") and facing is Dictionary:
		(aim as Dictionary)["radians"] = float((facing as Dictionary).get("radians", 0.0))


# How far the aim is turned from the heading, 0 to PI: the cone's price for looking one way and
# walking another. Zero for a body with no `aim`.
static func twist(components: Variant, entity: int) -> float:
	var aim: Variant = components.get_component(entity, "aim")
	var facing: Variant = components.get_component(entity, "facing")
	if not (aim is Dictionary) or not (aim as Dictionary).has("radians") or not (facing is Dictionary):
		return 0.0
	return absf(angle_difference(float((facing as Dictionary).get("radians", 0.0)), float((aim as Dictionary).get("radians", 0.0))))


# atan2 reaches negative zero due east. `SimSerialize.canonicalize` means to refuse one but cannot
# see it (`str(-0.0)` prints "0.0"; docs/37), so a negative zero would be written silently as 0 and
# come back positive. -0.0 == 0.0, so this assignment is the collapse `headingOf` and
# `npc_combat._face_at` do, and the stored value is the one the save gives back.
static func canonical(radians: float) -> float:
	if radians == 0.0:
		return 0.0
	return radians
