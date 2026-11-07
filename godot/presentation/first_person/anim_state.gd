extends RefCounted
# The animation read model: for a drawn body, the animation state it should play, and how far into
# that clip it is. Presentation only, pure and static -- nothing here writes a component, draws, or
# keeps state, and `godot/sim/` never reads this file.
#
# The state comes from what the sim already holds, never from a guess:
#   corpse                death
#   grabbed / grabState   grab
#   swing.state           swing (a survivor's WindUp and Recover are both the strike)
#   shambler.state        Staggered = stagger; Pursue with an armed swipe = lunge; a zombie with no
#                         use of its legs = crawl; otherwise moving = walk, still = idle
#   posture.current       Crouch = crouch_idle / crouch_walk; Crawl = crawl
#   velocity              walk, run and the idle/crouch distinction
# The top-down's `presentation/anim_clock.gd` times the same facts on the render clock; this file
# names the pose, and the art clock will time it when the character GLBs land. The one state the sim
# only publishes as an event is a survivor's stagger (`entity.staggered`); with no component to read
# it is not reported here, and a survivor in that moment reads as its locomotion state.
#
# A state with no clip in the character art yet maps to the nearest one that exists (`CLIP_FOR`), so
# the table can grow as the art grows and no caller changes. The clip names and lengths are the
# character kit's (tools/blender/first_person_kit/README.md on its branch):
#   survivor: idle 2.0 s, walk 1.0 s loop, crouch_idle 2.0 s loop, death 1.5 s held
#   shambler: idle 2.4 s, shamble 1.4 s loop, lunge 1.0 s held, death 1.7 s held
#
# Phase is 0..1 within the chosen clip. Loops advance on the sim tick with a per-entity seat (the
# golden-ratio stagger `AnimClock.seat` uses), so a crowd does not breathe or step as one. One-shots
# use the sim's own countdown where there is one (a swipe's wind-up, a hold's next bite); a held
# final pose reports 1.0. `of()` is the readable API; `state_of()` + `phase_of()` are the same answer
# without building a Dictionary, which is what `body_view.gd` calls per body per frame.

const SimStances = preload("res://sim/stances.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")

const IDLE: String = "idle"
const WALK: String = "walk"
const RUN: String = "run"
const CROUCH_IDLE: String = "crouch_idle"
const CROUCH_WALK: String = "crouch_walk"
const CRAWL: String = "crawl"
const SWING: String = "swing"
const LUNGE: String = "lunge"
const GRAB: String = "grab"
const STAGGER: String = "stagger"
const DEATH: String = "death"

const STATES: Array[String] = [IDLE, WALK, RUN, CROUCH_IDLE, CROUCH_WALK, CRAWL, SWING, LUNGE, GRAB, STAGGER, DEATH]
const LOOPING: Array[String] = [IDLE, WALK, RUN, CROUCH_IDLE, CROUCH_WALK, CRAWL]

# Below this many metres per second the sim's velocity is a stopped body, not a step.
const STILL_MPS: float = 0.05
# The sim's tick rate, for turning `world.tick` into seconds of clip.
const TICK_HZ: float = 20.0
# The golden ratio, the same stagger the top-down clock seats a crowd with.
const SEAT_RATIO: float = 0.6180339887

# The nearest existing clip for every state, per character kind. Anything the art has not recorded
# still names its state; only the clip it borrows changes.
const CLIP_FOR: Dictionary = {
	"survivor": {
		IDLE: "idle",
		WALK: "walk",
		# There is no run clip: the one walk cycle is the nearest, and the phase runs faster.
		RUN: "walk",
		CROUCH_IDLE: "crouch_idle",
		# No crouch walk clip: the crouched idle is the nearest, and the phase still names the step.
		CROUCH_WALK: "crouch_idle",
		# No prone clip: a crawling body borrows the crouched idle.
		CRAWL: "crouch_idle",
		# No attack clip: the walk's arm swing is nearer than the breathing idle.
		SWING: "walk",
		LUNGE: "walk",
		GRAB: "idle",
		STAGGER: "idle",
		DEATH: "death",
	},
	"shambler": {
		IDLE: "idle",
		WALK: "shamble",
		RUN: "shamble",
		CROUCH_IDLE: "idle",
		CROUCH_WALK: "shamble",
		CRAWL: "shamble",
		# A shambler's swipe is the lunge clip.
		SWING: "lunge",
		LUNGE: "lunge",
		GRAB: "lunge",
		STAGGER: "idle",
		DEATH: "death",
	},
}

# The clip lengths, per kind, from the character kit. A state that borrows a clip takes that clip's
# length.
const CLIP_SECONDS: Dictionary = {
	"survivor": {"idle": 2.0, "walk": 1.0, "crouch_idle": 2.0, "death": 1.5},
	"shambler": {"idle": 2.4, "shamble": 1.4, "lunge": 1.0, "death": 1.7},
}


## The readable answer: {"state": one of STATES, "phase": 0..1 in the chosen clip}.
static func of(world: Variant, entity: int) -> Dictionary:
	var state: String = state_of(world, entity)
	return {"state": state, "phase": phase_of(world, entity, state)}


## The animation state a drawn body should play. A dead body is always `death`; an unknown or
## missing body reads `idle` rather than inventing a pose.
static func state_of(world: Variant, entity: int) -> String:
	if world == null or entity < 0:
		return IDLE
	if world.components.has_component(entity, "corpse"):
		return DEATH
	# A feigner lying among the dead has the death clip: the rig's own corpse frame, no new picture.
	if SimShambler.is_lying(world, entity):
		return DEATH
	if world.components.has_component(entity, "grabbed"):
		return GRAB
	if is_zombie(world, entity):
		return _zombie_state(world, entity)
	return _survivor_state(world, entity)


## "survivor" or "shambler": which clip table this body reads.
static func kind_of(world: Variant, entity: int) -> String:
	return "shambler" if is_zombie(world, entity) else "survivor"


## The clip a body's state borrows, from `CLIP_FOR`.
static func clip_for(kind: String, state: String) -> String:
	var table: Variant = CLIP_FOR.get(kind, {})
	if not (table is Dictionary):
		return "idle"
	return String((table as Dictionary).get(state, "idle"))


## How far into the chosen clip the body is, 0..1. Loops run on the sim tick with a per-entity seat;
## one-shots use the sim's countdown; a held pose is 1.0.
static func phase_of(world: Variant, entity: int, state: String) -> float:
	if world == null:
		return 0.0
	var kind: String = kind_of(world, entity)
	if LOOPING.has(state):
		return _loop_phase(world, entity, kind, clip_for(kind, state))
	match state:
		LUNGE:
			return _swipe_phase(world, entity)
		GRAB:
			return _grab_phase(world, entity)
		SWING:
			var swing: Variant = world.components.get_component(entity, "swing")
			if swing is Dictionary and int((swing as Dictionary).get("state", 0)) == SimMelee.SwingState.Recover:
				return 1.0
			return 0.0
		DEATH:
			return 1.0
	return 0.0


static func is_zombie(world: Variant, entity: int) -> bool:
	return world.components.has_component(entity, "zombieType") or world.components.has_component(entity, "shambler")


static func _zombie_state(world: Variant, entity: int) -> String:
	var shambler: Variant = world.components.get_component(entity, "shambler")
	var state: int = SimShambler.ShamblerState["Wander"]
	var ticks_to_swipe: int = SimShambler.SWIPE_FIRST_TICKS
	if shambler is Dictionary:
		var data: Dictionary = shambler as Dictionary
		state = int(data.get("state", state))
		ticks_to_swipe = int(data.get("ticksToSwipe", ticks_to_swipe))
	if world.components.has_component(entity, "grabState"):
		return GRAB
	if state == SimShambler.ShamblerState["Staggered"]:
		return STAGGER
	# A swipe is armed when the countdown has left its resting value; the sim resets it to the first
	# swing's length whenever no victim is in reach, so any other value means contact and a wind-up.
	if state == SimShambler.ShamblerState["Pursue"] and ticks_to_swipe != SimShambler.SWIPE_FIRST_TICKS:
		return LUNGE
	if _crawling(world, entity):
		return CRAWL
	return WALK if _moving(world, entity) else IDLE


static func _survivor_state(world: Variant, entity: int) -> String:
	var swing: Variant = world.components.get_component(entity, "swing")
	if swing is Dictionary and int((swing as Dictionary).get("state", 0)) != SimMelee.SwingState.Idle:
		return SWING
	if _crawling(world, entity):
		return CRAWL
	var stance: int = SimStances.stance_of(world.components, entity)
	if stance == SimStances.Stance.Crawl:
		return CRAWL
	var moving: bool = _moving(world, entity)
	if stance == SimStances.Stance.Crouch:
		return CROUCH_WALK if moving else CROUCH_IDLE
	if not moving:
		return IDLE
	if stance == SimStances.Stance.Jog or stance == SimStances.Stance.Sprint:
		return RUN
	return WALK


static func _moving(world: Variant, entity: int) -> bool:
	var velocity: Variant = world.components.get_component(entity, "velocity")
	if not (velocity is Dictionary):
		return false
	var dx: float = float((velocity as Dictionary).get("dx", 0.0))
	var dy: float = float((velocity as Dictionary).get("dy", 0.0))
	return dx * dx + dy * dy > STILL_MPS * STILL_MPS


# The sim's own read of a body with no working legs, for a survivor or a zombie.
static func _crawling(world: Variant, entity: int) -> bool:
	var body: Variant = world.components.get_component(entity, "body")
	return body is Dictionary and SimHealth.is_crawling(body as Dictionary)


static func _loop_phase(world: Variant, entity: int, kind: String, clip: String) -> float:
	var seconds: float = _clip_seconds(kind, clip)
	if seconds <= 0.0:
		return 0.0
	var seat: float = fposmod(float(entity) * SEAT_RATIO, 1.0) * seconds
	var now: float = float(int(world.tick)) / TICK_HZ
	return fposmod((now + seat) / seconds, 1.0)


static func _clip_seconds(kind: String, clip: String) -> float:
	var table: Variant = CLIP_SECONDS.get(kind, {})
	if not (table is Dictionary):
		return 0.0
	return float((table as Dictionary).get(clip, 0.0))


# A swipe's wind-up: the countdown runs from the first swing's 20 ticks, and from the longer recovery
# after a strike; either way 1 is the moment of contact and the top is the arming.
static func _swipe_phase(world: Variant, entity: int) -> float:
	var shambler: Variant = world.components.get_component(entity, "shambler")
	if not (shambler is Dictionary):
		return 0.0
	var ticks: int = int((shambler as Dictionary).get("ticksToSwipe", SimShambler.SWIPE_FIRST_TICKS))
	var span: int = SimShambler.SWIPE_FIRST_TICKS if ticks <= SimShambler.SWIPE_FIRST_TICKS else SimShambler.SWIPE_RECOVER_TICKS
	if span <= 0:
		return 0.0
	return clampf(1.0 - float(ticks) / float(span), 0.0, 1.0)


# A hold's next bite countdown: 0 at the bite, 1 at the arming.
static func _grab_phase(world: Variant, entity: int) -> float:
	var hold: Variant = world.components.get_component(entity, "grabState")
	if not (hold is Dictionary):
		return 0.0
	var ticks: int = int((hold as Dictionary).get("ticksUntilBite", SimShambler.FIRST_BITE_TICKS))
	if SimShambler.FIRST_BITE_TICKS <= 0:
		return 0.0
	return clampf(1.0 - float(ticks) / float(SimShambler.FIRST_BITE_TICKS), 0.0, 1.0)
