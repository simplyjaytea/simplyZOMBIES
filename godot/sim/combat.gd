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

static func windup_ticks(weight: float, speed: float = 1.0) -> int:
    return maxi(1, int(round(float(WINDUP_TICKS) * weight / speed)))

static func recover_ticks(weight: float, recovery: float = 1.0) -> int:
    return maxi(1, int(round(float(RECOVER_TICKS) * weight * recovery)))

static func swing_stamina(weight: float, stamina: float = 1.0) -> int:
    return int(float(SWING_STAMINA) * weight * stamina)
