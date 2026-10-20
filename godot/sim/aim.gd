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

const SimStancesRes = preload("res://sim/stances.gd")

# The fastest rung that may hold an aim apart from the heading.
const HELD_UP_TO: int = SimStancesRes.Stance.Walk


# The heading the shot, the swing and the eyes use: the `aim` component's, or `facing` when there
# is none, or 0 when there is neither.
static func radians_of(components: Variant, entity: int) -> float:
	var aim: Variant = components.get_component(entity, "aim")
	if aim is Dictionary:
		return float((aim as Dictionary).get("radians", 0.0))
	var facing: Variant = components.get_component(entity, "facing")
	if facing is Dictionary:
		return float((facing as Dictionary).get("radians", 0.0))
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
# Returns whether the proposal took.
static func propose(components: Variant, entity: int, radians: float, moving: bool) -> bool:
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
		components.set_component(entity, "aim", {"radians": r})
	return true


# The aim follows the heading: called wherever something other than the `aim` command turns a body,
# and every tick a body moves faster than `holds` allows. A body with no `aim` is left without one.
static func follow_facing(components: Variant, entity: int) -> void:
	var aim: Variant = components.get_component(entity, "aim")
	var facing: Variant = components.get_component(entity, "facing")
	if aim is Dictionary and facing is Dictionary:
		(aim as Dictionary)["radians"] = float((facing as Dictionary).get("radians", 0.0))


# How far the aim is turned from the heading, 0 to PI: the cone's price for looking one way and
# walking another. Zero for a body with no `aim`.
static func twist(components: Variant, entity: int) -> float:
	var aim: Variant = components.get_component(entity, "aim")
	var facing: Variant = components.get_component(entity, "facing")
	if not (aim is Dictionary) or not (facing is Dictionary):
		return 0.0
	return absf(angle_difference(float((facing as Dictionary).get("radians", 0.0)), float((aim as Dictionary).get("radians", 0.0))))


# atan2 reaches negative zero due east, which the serializer's `canonicalize` rejects outright; -0.0
# == 0.0, so this assignment is the collapse `headingOf` and `npc_combat._face_at` do.
static func canonical(radians: float) -> float:
	if radians == 0.0:
		return 0.0
	return radians
