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
const SURVIVOR_HIT_LOCATION_WEIGHTS: Dictionary = {"head": 0.2, "torso": 0.55, "arms": 0.09, "hands": 0.03, "legs": 0.1, "feet": 0.03}
const SURVIVOR_BODY_PARTS: Array[String] = ["head", "torso", "arms", "hands", "legs", "feet"]
const SURVIVOR_BODY: Dictionary = {"head": 15, "torso": 40, "arms": 20, "hands": 10, "legs": 25, "feet": 10}
const ZOMBIE_BODY: Dictionary = {"head": 25, "torso": 60, "legs": 40}

static func windup_ticks(weight: float, speed: float = 1.0) -> int:
    return maxi(1, int(round(float(WINDUP_TICKS) * weight / speed)))

static func recover_ticks(weight: float, recovery: float = 1.0) -> int:
    return maxi(1, int(round(float(RECOVER_TICKS) * weight * recovery)))

static func swing_stamina(weight: float, stamina: float = 1.0) -> int:
    return int(float(SWING_STAMINA) * weight * stamina)
