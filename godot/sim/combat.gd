class_name SimCombat
extends RefCounted

const MELEE_CONNECT_NOISE: int = 8
const SWING_HALF_ANGLE: float = 0.6
const COS_SWING_HALF_ANGLE: float = 0.8253356149096783
const WINDUP_TICKS: int = 6
const RECOVER_TICKS: int = 8
const STAMINA_MAX: int = 100
const SWING_STAMINA: int = 6
const STAMINA_RECOVERY_DELAY_TICKS: int = 20
const STAMINA_PER_TICK: float = 0.6
const HEAD_DAMAGE_MULTIPLIER: int = 3

const HIT_LOCATION_WEIGHTS: Dictionary = {"head": 0.2, "torso": 0.55, "legs": 0.25}
const BODY_PARTS: Array[String] = ["head", "torso", "legs"]
const ZOMBIE_BODY: Dictionary = {"head": 25, "torso": 60, "legs": 40}

# Survivors carry independent left and right limbs. docs/05-health-injury.md's permanent
# consequences already describe "a one-armed survivor" as an outcome the colony has to plan
# around -- can't fight, can still cook, haul, watch, and talk -- which is not an outcome the
# previous single aggregate "arms" value could produce: amputating "arms" took both arms at
# once. This is docs/30's decision entry "survivor limbs are sided", not a UI change.
#
# Order is anatomical left before right, head down, matching docs/05's reading order.
# SURVIVOR_BODY keeps each limb's own toughness rather than halving it: there is no
# aggregate HP pool, so "how hard is it to ruin one arm" is the felt quantity, and it must
# stay what it was. SURVIVOR_HIT_LOCATION_WEIGHTS instead halves each split entry, so the
# chance of hitting *an* arm is unchanged and existing lethality balance holds.
const SURVIVOR_BODY_PARTS: Array[String] = [
	"head", "torso",
	"arm_left", "arm_right",
	"hand_left", "hand_right",
	"leg_left", "leg_right",
	"foot_left", "foot_right",
]
const SURVIVOR_BODY: Dictionary = {
	"head": 15, "torso": 40,
	"arm_left": 20, "arm_right": 20,
	"hand_left": 10, "hand_right": 10,
	"leg_left": 25, "leg_right": 25,
	"foot_left": 10, "foot_right": 10,
}
const SURVIVOR_HIT_LOCATION_WEIGHTS: Dictionary = {
	"head": 0.2, "torso": 0.55,
	"arm_left": 0.045, "arm_right": 0.045,
	"hand_left": 0.015, "hand_right": 0.015,
	"leg_left": 0.05, "leg_right": 0.05,
	"foot_left": 0.015, "foot_right": 0.015,
}

# Where a mouth lands when it already has hold of you, as distinct from where a swing lands on a
# body that is still moving. A free hit is aimed: SURVIVOR_HIT_LOCATION_WEIGHTS puts a fifth of
# them on the head because that is what someone swinging *wants*. A shambler that has closed its
# hands on a forearm is not aiming at anything -- it bites what it is already holding, which is
# overwhelmingly the arm, the hand, the shoulder-line of the torso. The head is the hardest thing
# to reach from inside a grapple, not the easiest.
#
# So this is a design statement about lethality as much as anatomy. Measured on the fast balance
# tier with the free-hit table in use, a held survivor died in two head bites (a head is 15,
# BITE_DAMAGE was a flat 8) and both starting colonists on seed 404 were dead before day 2 with
# `cause=head-destroyed`. Dropping the head share from 0.20 to 0.05 and pushing the weight onto
# graspable parts is one of the four levers docs/23 records for that re-tune; the others are the
# repeat-bite clock, part-scaled bite damage, and the struggle's cost.
#
# Sums to 1.0 exactly, like its free-hit twin: _roll_body_part walks the parts in
# SURVIVOR_BODY_PARTS order and falls through to the last part, so a table that summed short
# would quietly over-weight the feet.
const HELD_HIT_LOCATION_WEIGHTS: Dictionary = {
	"head": 0.05, "torso": 0.30,
	"arm_left": 0.14, "arm_right": 0.14,
	"hand_left": 0.09, "hand_right": 0.09,
	"leg_left": 0.07, "leg_right": 0.07,
	"foot_left": 0.025, "foot_right": 0.025,
}

static func windup_ticks(weight: float, speed: float = 1.0) -> int:
    return maxi(1, int(round(float(WINDUP_TICKS) * weight / speed)))

static func recover_ticks(weight: float, recovery: float = 1.0) -> int:
    return maxi(1, int(round(float(RECOVER_TICKS) * weight * recovery)))

static func swing_stamina(weight: float, stamina: float = 1.0) -> int:
    return int(float(SWING_STAMINA) * weight * stamina)
