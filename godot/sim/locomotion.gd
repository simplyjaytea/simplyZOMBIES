class_name SimLocomotion
extends RefCounted

# Keep in sync with src/sim/locomotion.ts
const HUMAN_WALK_MPS: float = 1.4
const PACE: float = 1.5
const WALK_SPEED: float = HUMAN_WALK_MPS * PACE # 2.1
const SPRINT_SPEED: float = WALK_SPEED * 3.0 # 6.3
const SPRINT_THRESHOLD: float = (WALK_SPEED + SPRINT_SPEED) / 2.0 # 4.2
const BODY_RADIUS: float = 0.35


static func zombie_speed(locomotion_speed: float) -> float:
	return WALK_SPEED * locomotion_speed
