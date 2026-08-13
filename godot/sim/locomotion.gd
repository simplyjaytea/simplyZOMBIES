class_name SimLocomotion
extends RefCounted

const HUMAN_WALK_MPS: float = 1.4
const PACE: float = 1.5
const WALK_SPEED: float = 2.1 # HUMAN_WALK_MPS * PACE
const SPRINT_SPEED: float = 6.3 # WALK_SPEED * 3
const SPRINT_THRESHOLD: float = 4.2 # (WALK+SPRINT)/2


static func zombie_speed(locomotion_speed: float) -> float:
	return WALK_SPEED * locomotion_speed
