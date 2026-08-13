class_name SimStance
extends RefCounted

# Keep in sync with src/sim/stances.ts + src/sim/modules/stance.ts
# Ponytail: single Stamina int in component dict; upgrade to typed resource when needs grow.

enum Stance { CRAWL = 0, CROUCH = 1, WALK = 2, JOG = 3, SPRINT = 4 }

const STANCES: Array[int] = [Stance.CRAWL, Stance.CROUCH, Stance.WALK, Stance.JOG, Stance.SPRINT]
const DEFAULT_STANCE: int = Stance.WALK
const STANCE_CHANGE_TICKS: int = 4
const STAMINA_MAX: int = 100
const TICK_HZ: int = 20

# Eye values mirror SimTileMap.Eye
const EYE_STANDING: int = 0
const EYE_CROUCHED: int = 1


static func _drain_per_tick(seconds: Variant) -> float:
	if seconds == null:
		return 0.0
	return float(STAMINA_MAX) / (float(seconds) * float(TICK_HZ))


static func seconds_to_empty(stance: int) -> Variant:
	match stance:
		Stance.CRAWL: return 120
		Stance.CROUCH: return null
		Stance.WALK: return null
		Stance.JOG: return 90
		Stance.SPRINT: return 14
		_: return null


static func stance_spec(stance: int) -> Dictionary:
	match stance:
		Stance.CRAWL:
			return {"speedFactor": 0.25, "noise": 0.4, "staminaPerTick": _drain_per_tick(120), "canSwing": false, "canAim": false, "eye": EYE_CROUCHED, "name": "crawling"}
		Stance.CROUCH:
			return {"speedFactor": 0.5, "noise": 0.7, "staminaPerTick": 0.0, "canSwing": true, "canAim": true, "eye": EYE_CROUCHED, "name": "crouching"}
		Stance.WALK:
			return {"speedFactor": 1.0, "noise": 1.0, "staminaPerTick": 0.0, "canSwing": true, "canAim": true, "eye": EYE_STANDING, "name": "walking"}
		Stance.JOG:
			return {"speedFactor": 1.8, "noise": 2.0, "staminaPerTick": _drain_per_tick(90), "canSwing": true, "canAim": true, "eye": EYE_STANDING, "name": "jogging"}
		Stance.SPRINT:
			return {"speedFactor": 3.0, "noise": 6.0, "staminaPerTick": _drain_per_tick(14), "canSwing": true, "canAim": false, "eye": EYE_STANDING, "name": "sprinting"}
		_:
			return {}


static func stance_change_ticks(from: int, to: int) -> int:
	return absi(to - from) * STANCE_CHANGE_TICKS


static func make_posture(world: Variant, entity: int, stance: int = DEFAULT_STANCE) -> void:
	world.components.set_component(entity, "Posture", {"current": stance, "target": stance, "ticksLeft": 0})


static func stance_of(world: Variant, entity: int) -> int:
	var posture: Variant = world.components.get_component(entity, "Posture")
	if posture == null:
		return DEFAULT_STANCE
	return int(posture["current"])


static func stance_spec_of(world: Variant, entity: int) -> Dictionary:
	return stance_spec(stance_of(world, entity))


static func capable_of(world: Variant, entity: int, of: String) -> bool:
	var posture: Variant = world.components.get_component(entity, "Posture")
	if posture == null:
		return bool(stance_spec(DEFAULT_STANCE)[of])
	var cur: int = int(posture["current"])
	var tgt: int = int(posture["target"])
	return bool(stance_spec(cur)[of]) and bool(stance_spec(tgt)[of])


static func request_stance(posture: Dictionary, target: int) -> void:
	if int(posture["target"]) == target:
		return
	posture["target"] = target
	if int(posture["current"]) != target and int(posture["ticksLeft"]) == 0:
		posture["ticksLeft"] = STANCE_CHANGE_TICKS
	if int(posture["current"]) == target:
		posture["ticksLeft"] = 0


static func interrupt_stance(posture: Dictionary) -> void:
	posture["target"] = int(posture["current"])
	posture["ticksLeft"] = 0
