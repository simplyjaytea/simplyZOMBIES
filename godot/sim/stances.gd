class_name SimStances
extends RefCounted

const SimTileMapRes = preload("res://sim/map/tilemap.gd")
const ComponentStore = preload("res://sim/component_store.gd")

enum Stance { Crawl = 0, Crouch = 1, Walk = 2, Jog = 3, Sprint = 4 }

const STANCE_CHANGE_TICKS: int = 4
const STAMINA_MAX: float = 100.0
const TICK_HZ: int = 20
const DEFAULT_STANCE: int = Stance.Walk

const WALK_NOISE: float = 1.0
const SPRINT_NOISE: float = 6.0

# seconds-to-empty per stance; -1 means null (neutral, no drain)
var _SECONDS_TO_EMPTY: Array = []  # filled lazily to avoid const-expression restriction
const SPEED_FACTOR: Array[float] = [0.25, 0.5, 1.0, 1.8, 3.0]
const NOISE: Array[float] = [0.4, 0.7, 1.0, 2.0, 6.0]
const CAN_SWING: Array[bool] = [false, true, true, true, true]
const CAN_AIM: Array[bool] = [false, true, true, true, false]
const NAMES: Array[String] = ["crawling", "crouching", "walking", "jogging", "sprinting"]


static func eye_of(stance: int) -> int:
	return SimTileMapRes.Eye.Crouched if stance == Stance.Crawl or stance == Stance.Crouch else SimTileMapRes.Eye.Standing


static func drain_per_tick(stance: int) -> float:
	var seconds: float = _seconds_for(stance)
	if seconds < 0:
		return 0.0
	return STAMINA_MAX / (seconds * float(TICK_HZ))


static func _seconds_for(stance: int) -> float:
	match stance:
		Stance.Crawl:
			return 120.0
		Stance.Jog:
			return 90.0
		Stance.Sprint:
			return 14.0
		_:
			return -1.0


static func speed_factor_of(stance: int) -> float:
	return SPEED_FACTOR[stance]


static func noise_of(stance: int) -> float:
	return NOISE[stance]


static func can_swing(stance: int) -> bool:
	return CAN_SWING[stance]


static func can_aim(stance: int) -> bool:
	return CAN_AIM[stance]


static func name_of(stance: int) -> String:
	return NAMES[stance]


static func stance_change_ticks(from: int, to: int) -> int:
	return absi(to - from) * STANCE_CHANGE_TICKS


static func make_posture(stance: int = Stance.Walk) -> Dictionary:
	return {"current": stance, "target": stance, "ticks_left": 0}


static func stance_of(components: ComponentStore, entity: int) -> int:
	var posture: Variant = components.get_component(entity, "posture")
	if posture == null:
		return DEFAULT_STANCE
	return int((posture as Dictionary)["current"])


static func request_stance(posture: Dictionary, target: int) -> void:
	if int(posture["target"]) == target:
		return
	posture["target"] = target
	if int(posture["current"]) != target and int(posture["ticks_left"]) == 0:
		posture["ticks_left"] = STANCE_CHANGE_TICKS
	if int(posture["current"]) == target:
		posture["ticks_left"] = 0


static func interrupt_stance(posture: Dictionary) -> void:
	posture["target"] = posture["current"]
	posture["ticks_left"] = 0
