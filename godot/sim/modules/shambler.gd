class_name SimShambler
extends RefCounted

# Port of src/sim/modules/shambler.ts — 5 states, gradient+bias pursuit, plus the
# grab -> struggle -> bite loop ("Make harm real" slice, Part B), and -- as of the cripple/stagger
# slice -- the two sockets that used to be cut here and wired to nothing.
#
# **Stagger.** docs/09 is explicit about what a stagger is for: "landing a solid hit interrupts the
# target ... stagger is the actual survival mechanic in a crowd, because a staggered zombie isn't
# grabbing you." The `Staggered` state and its `ticksStaggered` countdown were both already here
# and already handled by the state machine; nothing ever put a shambler *into* them, because this
# file subscribed to no `entity.staggered`. It does now (`shambler.stagger`), and because the
# clause says "isn't grabbing you" rather than "is slower", a stagger also breaks whatever hold
# the shambler had -- `grab.broken` cause `staggered` -- and arms the ordinary re-grab cooldown so
# the answer to a grab is not one swing followed by an instant re-take.
#
# **Cripple.** `crawlFactor` was on the component from the start and read by nothing. A shambler
# whose legs are gone now moves at that fraction of whatever speed it would otherwise use, through
# `_speed_of` -- one accessor rather than a multiply at each of the four read sites, because four
# sites is three chances to miss one. It is derived from the body every tick rather than latched
# off `injury.sustained`: a flag set by an event has to be kept in step with the body through
# amputation, save/load and anything else that edits integrity, and reading `SimHealth.is_crawling`
# cannot drift from the thing it describes. The event still fires and is still the right hook for
# anything that wants to *react* to the moment; it is just not the source of truth for the speed.

const ShamblerState: Dictionary = {
	"Wander": 0,
	"Seek": 1,
	"Investigate": 2,
	"Staggered": 3,
	"Pursue": 4,
}

const DEFAULT_LOCOMOTION: Dictionary = {"speed": 0.8, "wander": 0.35, "mill": 0.25, "crawl": 0.25}
const DEFAULT_GRAB_STRENGTH: float = 0.5

const SPREAD_RADIANS: float = 0.62
const NOISE_SENSITIVITY: float = 0.2
const SCENT_SENSITIVITY: float = 0.9
const SCENT_BIAS: float = 0.35
const LIGHT_SENSITIVITY: float = 0.1
const LIGHT_BIAS: float = 0.5
const CONTACT_METRES: float = 1.6
const GRAB_METRES: float = 1.0
const RELEASE_METRES: float = 3.2
const MILL_TICKS: int = 90
const COMMIT_TICKS: int = 400

# The swipe: a clawed cuff from a Pursuing shambler -- landed as the one zombie damage path
# outside GRABS_ENABLED while that flag was false, and kept deliberately not a bite now that
# grabs are live. It publishes `attack.connected`, the same channel a survivor's swing uses, so
# it lands as a "cut" wound through health.take-damage with no infection roll; infection stays
# the bite's alone, behind the grab loop. Small on purpose,
# and part-scaled the way a bite is (CLAUDE.md's standing trap: parts do not share a scale) --
# the first cut of this shipped flat 3.0 and the diagnosis driver measured what that means: a
# passive body's 15-point head is destroyed by five swipes, and both hard balance seeds wiped on
# day one by exactly that execution, 16-21 swipes each, five to the head. 0.15 of the part's
# maximum, floored and capped, lands every swipe at the Scratch/Laceration boundary of its own
# part -- never DeepWound (that band starts at 0.40), and a head takes seven, not five. A swipe
# threatens by attrition, bleeding and crowds, never by execution; execution stays the grab
# loop's. Reach sits just past GRAB_METRES so the grab is the closer and worse outcome of the
# same approach.
const SWIPE_METRES: float = 1.1
# One second of raised arms before the first swipe lands, so walking into reach is a mistake you
# can still step back out of. The clock only runs while a mark is in reach and resets the moment
# nobody is: re-approaching costs the windup again.
const SWIPE_FIRST_TICKS: int = 20
# Three seconds between swipes -- deliberately quicker than REPEAT_BITE_TICKS (4 s) because a
# swipe is a fraction of a bite's damage, and slow enough that one shambler is pressure rather
# than a blender. Two or three of them in reach at once is what kills, which is the crowd rule
# docs/09 wants.
const SWIPE_RECOVER_TICKS: int = 60
# The ceiling on a swipe, not the value of one -- swipe_damage_for scales to the part, the
# bite_damage_for shape at half the fraction.
const SWIPE_DAMAGE: float = 3.0
const SWIPE_DAMAGE_PART_FRACTION: float = 0.15
const SWIPE_DAMAGE_MIN: float = 1.0

# The grab -> struggle -> bite loop. Originally ported verbatim from src/sim/modules/shambler.ts;
# four of these values have since moved off the oracle's numbers in the bite-lethality re-tune
# docs/23's Milestone 2 status records. The frozen TypeScript reference deliberately keeps the old
# ones -- R1 parity covers movement, so the divergence is expected and is not drift.
#
# 1.5 s to the first bite, four seconds between later ones, a bite costs a wound rather than
# health-bar damage, and the contextual F commits four fifths of a second before the escape roll
# lands.
const FIRST_BITE_TICKS: int = 30
# 80, not the oracle's 40. A held survivor cannot fight back, so this clock *is* the lethality of
# a hold: at 40 the same hold delivered twice as many bites in the window it took the colony to
# come and pull it off.
const REPEAT_BITE_TICKS: int = 80
# The ceiling on a bite, not the value of one -- see BITE_DAMAGE_PART_FRACTION below.
const BITE_DAMAGE: float = 8.0
# A bite takes a fraction of the part's *maximum* rather than a flat number, floored so that no
# bite is ever free. CLAUDE.md's standing trap: parts do not share a scale, so a flat 8 was a
# scratch on a 40-torso and a death sentence on a 15-head. 0.35 puts a head at three bites rather
# than two; a torso still takes the full 8 (0.35 * 40 = 14, clamped by BITE_DAMAGE); hands and
# feet drop to 3.5. The floor matters mechanically as well as tonally: health.gd:141 records no
# wound for a hit that removed no integrity, so a bite that rounded to nothing would leave no
# mark to treat.
const BITE_DAMAGE_PART_FRACTION: float = 0.35
const BITE_DAMAGE_MIN: float = 2.0
# 16 and 15, down from the oracle's 20/20: the contest itself is untouched (SimAptitudes gives one
# shambler 1/1.5 = 0.667, pinned in check_m2_stats.gd), but a survivor gets to have it slightly
# sooner and can afford six attempts on a full tank rather than five. It no longer doubles as the
# re-grab cooldown -- see REGRAB_COOLDOWN_TICKS below.
const STRUGGLE_TICKS: int = 16
const STRUGGLE_STAMINA: float = 15.0
# How long a held body waits for a decision before it fights back on its own. Two seconds: long
# enough that an attentive player's F is always the thing that answers a grab, short enough that
# nobody stands still being eaten because the person at the keyboard is looking elsewhere -- or,
# in a harness, because there is nobody at the keyboard at all. It is a gap between *attempts*
# rather than the age of the hold (every arming site resets `grabbed.heldTicks`), so a survivor
# who has just failed an escape gets the same beat before the next one.
const STRUGGLE_INSTINCT_TICKS: int = 40
# How long a shambler that has just lost its grip must wait before it can take anyone again.
# This was STRUGGLE_TICKS doing double duty, which meant the escape lever silently moved it: a
# cheaper, faster struggle also handed the shambler its hands back sooner, and instrumenting a
# live district showed the same shambler re-taking the same survivor every 24 to 36 ticks. Named
# separately and pinned at its old value, so the two can be tuned apart, and so BREAK_AWAY_TICKS
# keeps outliving it the way its own note says it should.
const REGRAB_COOLDOWN_TICKS: int = 20

# Rescue: somebody else's hands on the problem. Until this landed, a hold had exactly one exit --
# the held survivor's own contest -- and the balance harness measured what that costs: colonies
# that died spent two thirds of their living ticks held, and a third to a half of those ticks with
# a tank too empty to pay STRUGGLE_STAMINA. Nothing in the build could pull anybody free. This is
# that, and it is a contest rather than a guaranteed break, because a shambler that lets go the
# moment a second person arrives would make being grabbed a formality.
#
# It rolls SimAptitudes.escape_chance with the *rescuer's* grab_escape power against the same total
# grip the victim contests. Purely additive: the victim's own contest and the 0.667 single-holder
# pin (check_m2_stats.gd) are untouched, and the draw comes from its own named RNG stream so the
# "grab" stream's sequence is unchanged whether anybody rescues or not.
#
# Reach. The same 1.6 m a shambler needs to reach *you* -- measured rescuer-to-victim, because
# what you are grabbing hold of is the person, not the thing on them.
const RESCUE_METRES: float = 1.6
# Commitment before the roll, deliberately inside FIRST_BITE_TICKS (30) so that somebody who
# reacts at once beats the first bite rather than arriving in time to watch it.
const RESCUE_TICKS: int = 12
# Between a swing (6) and a struggle (15). Hauling somebody out of a grip is work, but it is
# cheaper than being the one in the grip -- and it has to be, or the second colonist runs dry
# answering the first one's holds. Refused below the cost, and refusal charges nothing, which is
# the _arm_struggle idiom and the thing that turns an empty tank into a pause rather than a wall.
const RESCUE_STAMINA: float = 10.0
# Per-rescuer, after any resolution, win or lose. Without it a held colonist is worth a re-roll
# every tick, which is not a rescue, it is a slot machine; with it an attempt costs 12 ticks of
# commitment and 20 of recovery, and an NPC has room to swing at the holder in between.
const RESCUE_RETRY_TICKS: int = 20

# An escape that leaves you standing inside arm's reach is not an escape. Without this the
# balance harness lost a whole colony on 1 seed in 4: a survivor would tear free, stand exactly
# where they were, be re-taken the moment the holder's cooldown lapsed, and pay another tankful
# of stamina for the privilege until there was none left. The player solves this by walking away;
# nothing in the build did it for anyone else.
#
# BREAK_AWAY_TICKS being a shade longer than the re-grab cooldown is necessary and was never
# sufficient, and for one slice this comment claimed otherwise. What decides whether separation
# survives the cooldown is the *speed*, not the duration: both bodies are pinned for the whole
# hold, so a release starts from at most GRAB_METRES, and if the escapee is slower than the
# shambler's seek the gap closes no matter how long the running lasts. It was, by 0.08 m/s, and
# the instrumentation showed exactly what that predicts -- a median inter-grab window of 20
# ticks, the re-grab landing on the very tick the cooldown lapsed, 149 separate holds on one
# victim in a ten-day compressed campaign. See BREAK_AWAY_SPEED for the arithmetic that fixes it.

# Grabs are ON -- the owner's 2026-09-01 decision, taken together with the bigger colony that
# unblocked it. The flag spent Milestone 2 false while six recorded reasons were answered one
# measurement at a time; docs/23's flag record (the "survival loop" entries under "Where
# Milestone 2 stands") is the seed-by-seed history, and its final entry is the flip itself: a
# third boot colonist (survivor.unique.ellis), spawn offsets spread so the colony stands inside
# rescue reach of itself, a third bed, and the before/after table over the four fast balance
# seeds. `survivors_end >= 1` in check_m2_balance.gd now measures the shipped default with
# grabs live, which makes M2_BALANCE_OK the standing "the colony survives its own contact
# loop" assertion.
#
# A static var rather than a const purely so gates can drive it both ways:
# `_the_flag_actually_gates_acquisition` in check_m2_contact.gd exercises both directions,
# which is what keeps the flag honest, and any lane that pins it must restore the previous
# value -- one gate process shares this static across every world it boots. Treat it as a
# compile-time constant everywhere else. It is deliberately NOT world state and deliberately
# not saved -- a flag that could differ between a save and its reload would be a determinism
# bug, and this one is set once, at boot or by a gate, and never again.
static var GRABS_ENABLED: bool = true
const BREAK_AWAY_TICKS: int = 26
# 2.1 m/s, which is SimLocomotion.WALK_SPEED -- a shove-off at your own stride, not a free sprint
# at 6.3. The number that matters is the difference against the shambler's seek, 2.1 * 0.8 = 1.68:
# at the old 1.6 the holder *gained* 0.08 m/s on somebody who had just escaped it, so over the
# 20-tick REGRAB_COOLDOWN_TICKS (one second at 20 Hz) the gap shrank and the re-grab was
# unconditional. At 2.1 the escapee gains 0.42 m/s, so the gap at cooldown expiry is d0 + 0.42 --
# 1.34 to 1.42 m against GRAB_METRES 1.0 -- and d0 + 0.55 by the time BREAK_AWAY_TICKS runs out,
# after which a walking NPC keeps opening it until RELEASE_METRES 3.2 drops the holder out of
# Pursue. It is a reduction in churn rather than immunity: a release from d0 < 0.58 m can still be
# inside reach when the cooldown lapses. CLEAR-AWAY in check_m2_contact.gd pins the speed against
# the seek so a locomotion retune cannot quietly re-create the treadmill.
#
# Two things measured since move that threshold, and both are in the rationale block above rather
# than here because neither is about the speed. A press cancelled at the escape costs one pinned
# tick before flight begins, which is 0.105 m of gap and lifts the 0.58 m to about 0.69 m. And in
# an actual district the arithmetic above is the *ceiling*, not the outcome: 86% of break-away
# ticks on seed 404 have the committed heading blocked on both axes, so the body covers 0.010 m per
# tick rather than 0.105 and this open-field reasoning simply does not apply to it.
const BREAK_AWAY_SPEED: float = 2.1
# The fan _break_away chooses its heading from, in the order it tries them: straight away first,
# then widening in 22.5-degree pairs. Order is the policy -- the first clear candidate wins, so a
# heading is only ever traded for a wider one when the narrower one is into a wall. Sixteenths of
# a turn is fine enough that a wall parallel to the escape always has a candidate within 22.5
# degrees of sliding along it, and coarse enough that the probe stays thirteen cheap tile lookups.
# Stops at +/-135: past that the shove-off would be through the holder.
const BREAK_AWAY_FAN_DEGREES: Array = [
	0.0, 22.5, -22.5, 45.0, -45.0, 67.5, -67.5, 90.0, -90.0, 112.5, -112.5, 135.0, -135.0,
]
# How far a candidate has to be clear to be taken as-is: 1.5 m, which is a shade over GRAB_METRES
# plus the 0.42 m/s the escapee gains over the seek across the re-grab cooldown. Further than this
# does not change whether the escape works and does make an indoor release more likely to find
# nothing at all and fall back.
const BREAK_AWAY_PROBE_METRES: float = 1.5
# 0.25 m, comfortably under the 0.7 m body diameter, so no sample can straddle a wall.
const BREAK_AWAY_PROBE_STEP: float = 0.25

const SimLocomotionRes = preload("res://sim/locomotion.gd")
const SimTileMapRes = preload("res://sim/map/tilemap.gd")
# _roll_body_part is reused rather than reimplemented -- CLAUDE.md's shape is "one canonical
# place", and melee.gd:31 already is it.
const SimMeleeRes = preload("res://sim/modules/melee.gd")
# escape_chance already resolves the STR-scaled grab_escape modifier; this module has no
# business rolling its own escape maths.
const SimAptitudesRes = preload("res://sim/modules/aptitudes.gd")
# entity_index, so a victim's `grabbed.sources` sorts the same way regardless of spawn order --
# the save/replay-stable ordering the oracle's Grabbed component keeps.
const SimEntityStoreRes = preload("res://sim/entity_store.gd")
# max_of, so bite_damage_for scales against the same part table health.gd damages, and the
# held-bite location table -- preloaded rather than leaning on the global class name, the way
# every other cross-module reference in this file is.
const SimHealthRes = preload("res://sim/modules/health.gd")
const SimCombatRes = preload("res://sim/combat.gd")
# `is_person` -- the one answer to "would a zombie chase that", shared with screamer.gd and
# bloater.gd so a new kind of person (the raiders slice added one) reaches all three at once.
const SimAllegianceRes = preload("res://sim/modules/allegiance.gd")


static func default_shambler_speeds() -> Dictionary:
	var seek: float = SimLocomotionRes.zombie_speed(DEFAULT_LOCOMOTION["speed"])
	return {
		"seekSpeed": seek,
		"wanderSpeed": seek * float(DEFAULT_LOCOMOTION["wander"]),
		"millSpeed": seek * float(DEFAULT_LOCOMOTION["mill"]),
		"crawlFactor": float(DEFAULT_LOCOMOTION["crawl"]),
		"grabStrength": DEFAULT_GRAB_STRENGTH,
		"canGrab": true,
		"ticksToGrab": 0,
		"ticksToSwipe": SWIPE_FIRST_TICKS,
	}


static func make_shambler(world: Variant, entity: int, rng: Variant, type_id: String = "zombie.shambler") -> void:
	var loco: Dictionary = _locomotion_of(world, type_id)
	var grab: Dictionary = _grab_of(world, type_id)
	var seek_speed: float = SimLocomotionRes.zombie_speed(float(loco["speed"]))
	world.components.set_component(entity, "shambler", {
		"state": ShamblerState["Wander"],
		"ticksToTurn": int(rng.call("int_range", 20, 120)),
		"ticksMilling": 0,
		"ticksCommitted": 0,
		"bias": rng.call("float_range", -SPREAD_RADIANS, SPREAD_RADIANS),
		"ticksStaggered": 0,
		"seekSpeed": seek_speed,
		"wanderSpeed": seek_speed * float(loco["wander"]),
		"millSpeed": seek_speed * float(loco["mill"]),
		"crawlFactor": float(loco["crawl"]),
		"grabStrength": float(grab["strength"]),
		"canGrab": bool(grab["enabled"]),
		"ticksToGrab": 0,
		"ticksToSwipe": SWIPE_FIRST_TICKS,
	})


static func _get_content_entry(world: Variant, type_id: String, id: String) -> Variant:
	if world == null or world.content == null:
		return null
	var c: Variant = world.content
	if c is Object and (c as Object).has_method("get"):
		return (c as Object).call("get", type_id, id)
	if c is Dictionary:
		if (c as Dictionary).has(type_id):
			var by_id: Variant = (c as Dictionary)[type_id]
			if by_id is Dictionary:
				var hit: Variant = (by_id as Dictionary).get(id)
				if hit != null:
					return hit
		for v in (c as Dictionary).values():
			if v is Array:
				for entry in v as Array:
					if entry is Dictionary and String((entry as Dictionary).get("id", "")) == id:
						return entry
			elif v is Dictionary and String((v as Dictionary).get("id", "")) == id:
				return v as Dictionary
	return null

static func _locomotion_of(world: Variant, type_id: String) -> Dictionary:
	var entry: Variant = _get_content_entry(world, "zombie", type_id)
	var loco: Dictionary = {}
	if entry != null:
		var l: Variant = (entry as Dictionary).get("locomotion")
		if l != null:
			loco = l as Dictionary
	return {
		"speed": float(loco.get("speed", DEFAULT_LOCOMOTION["speed"])),
		"wander": float(loco.get("wander", DEFAULT_LOCOMOTION["wander"])),
		"mill": float(loco.get("mill", DEFAULT_LOCOMOTION["mill"])),
		"crawl": float(loco.get("crawl", DEFAULT_LOCOMOTION["crawl"])),
	}


static func _grab_of(world: Variant, type_id: String) -> Dictionary:
	var entry: Variant = _get_content_entry(world, "zombie", type_id)
	if entry == null:
		return {"enabled": true, "strength": DEFAULT_GRAB_STRENGTH}
	var behaviours: Variant = (entry as Dictionary).get("behaviors")
	var enabled: bool = true
	if behaviours is Array:
		enabled = (behaviours as Array).has("grab")
	else:
		enabled = true
	var grab: Dictionary = {}
	var g: Variant = (entry as Dictionary).get("grab")
	if g != null:
		grab = g as Dictionary
	return {"enabled": enabled, "strength": float(grab.get("strength", DEFAULT_GRAB_STRENGTH))}


# The one place a shambler's speed is read. Every movement site goes through this so the cripple
# penalty cannot be applied to three of the four and quietly missed on the fourth.
static func _speed_of(world: Variant, entity: int, shambler_data: Dictionary, key: String) -> float:
	var base: float = float(shambler_data.get(key, 0.0))
	if not _is_crawling(world, entity):
		return base
	return base * float(shambler_data.get("crawlFactor", DEFAULT_LOCOMOTION["crawl"]))


# Derived, never latched. SimHealth.is_crawling reads the body itself -- "legs" for a zombie,
# both leg_* for a survivor -- so a leg that is destroyed, amputated, or restored by a save
# reload all say the same thing here without a flag to keep in step.
static func _is_crawling(world: Variant, entity: int) -> bool:
	var body: Variant = world.components.get_component(entity, "body")
	return body is Dictionary and SimHealthRes.is_crawling(body as Dictionary)


# `seek` is passed rather than read off shambler_data so the cripple penalty applies here too --
# see _speed_of, which is the only thing that should ever turn a stored speed into a used one.
static func _steer_uphill(field: Variant, pos: Dictionary, vel: Dictionary, shambler_data: Dictionary, seek: float) -> bool:
	var uphill: Variant = field.uphill_noise(float(pos["x"]), float(pos["y"]))
	if uphill == null:
		return false
	var angle: float = atan2(float((uphill as Dictionary)["dy"]), float((uphill as Dictionary)["dx"])) + float(shambler_data["bias"])
	vel["dx"] = cos(angle) * seek
	vel["dy"] = sin(angle) * seek
	return true


static func _drift_upscent(field: Variant, pos: Dictionary, vel: Dictionary, shambler_data: Dictionary, seek: float) -> void:
	var uphill: Variant = field.uphill_scent(float(pos["x"]), float(pos["y"]))
	if uphill == null:
		return
	var speed: float = sqrt(float(vel["dx"]) * float(vel["dx"]) + float(vel["dy"]) * float(vel["dy"]))
	if speed == 0.0:
		return
	var current: float = atan2(float(vel["dy"]), float(vel["dx"]))
	var toward: float = atan2(float((uphill as Dictionary)["dy"]), float((uphill as Dictionary)["dx"])) + float(shambler_data["bias"])
	var delta: float = toward - current
	while delta > PI:
		delta -= PI * 2.0
	while delta < -PI:
		delta += PI * 2.0
	var angle: float = current + delta * SCENT_BIAS
	vel["dx"] = cos(angle) * speed
	vel["dy"] = sin(angle) * speed


static func _contact_target(survivors: Array, pos: Dictionary, radius_metres: float) -> Variant:
	var limit: float = radius_metres * radius_metres
	var best: Variant = null
	var best_dist: float = limit
	for survivor in survivors:
		var s: Dictionary = survivor as Dictionary
		var dx: float = float(s["x"]) - float(pos["x"])
		var dy: float = float(s["y"]) - float(pos["y"])
		var dist: float = dx * dx + dy * dy
		if dist <= best_dist:
			best = s["entity"]
			best_dist = dist
	return best


# Who a shambler can see worth chasing. The corpse skip is not cosmetic: `identity` survives
# SimHealth's _make_corpse, so without it a dead colonist stays in this list forever -- pursued,
# reached, and grabbed, with `grab.started` and a hold that only geometry ever ends. That is a
# contact the district pays for and nobody can answer, and it inflated every hold counter the
# balance harness reports. A shambler that has already killed you has no further use for you.
#
# "Is that a person" is `SimAllegiance.is_person` rather than a pair of `has_component` calls
# written out here, because the raiders slice added a third marker and three copies of this test
# (here, screamer.gd, bloater.gd) would have learned about it separately or not at all. A zombie
# has no side and asks no allegiance question: a raider is meat on legs like everybody else.
static func _gather_survivors(world: Variant) -> Array:
	var out: Array = []
	for entity in world.components.query(["position"]):
		if not SimAllegianceRes.is_person(world, int(entity)):
			continue
		if world.components.has_component(int(entity), "corpse"):
			continue
		# A body at a wheel is inside a car, and a shambler has no way through the door: not
		# chased, not swiped, not grabbed. The engine it is sitting behind is what the shambler
		# hears instead (SimVehicles' emitter), which is the trade the car makes -- shelter for
		# noise. Only a car: `mounted.cab` is false on a bicycle, a scooter or a board, and a
		# rider in the open is as much on the menu as a body on foot -- the trade a light vehicle
		# makes is speed for no shelter. check_vehicles.gd's SHELTER lane holds this both ways.
		var mounted: Variant = world.components.get_component(int(entity), "mounted")
		if mounted is Dictionary and bool((mounted as Dictionary).get("cab", false)):
			continue
		var at: Variant = world.components.get_component(int(entity), "position")
		if at == null:
			continue
		out.append({"entity": int(entity), "x": float((at as Dictionary)["x"]), "y": float((at as Dictionary)["y"])})
	return out


static func _chase(world: Variant, target: int, pos: Dictionary, vel: Dictionary, shambler_data: Dictionary, seek: float) -> void:
	var at: Variant = world.components.get_component(target, "position")
	if at == null:
		return
	var dx: float = float((at as Dictionary)["x"]) - float(pos["x"])
	var dy: float = float((at as Dictionary)["y"]) - float(pos["y"])
	var dist: float = sqrt(dx * dx + dy * dy)
	if dist == 0.0:
		return
	vel["dx"] = dx / dist * seek
	vel["dy"] = dy / dist * seek


static func _lean_to_light(world: Variant, entity: int, pos: Dictionary, vel: Dictionary) -> void:
	if not world.components.has_component(entity, "observer"):
		return
	var speed: float = sqrt(float(vel["dx"]) * float(vel["dx"]) + float(vel["dy"]) * float(vel["dy"]))
	if speed == 0.0:
		return
	var best_rem: float = 0.0
	var best_x: float = 0.0
	var best_y: float = 0.0
	for source in world.light.sources():
		var at: Variant = world.light.source_at(int(source))
		if at == null:
			continue
		var dx: float = float((at as Dictionary)["x"]) - float(pos["x"])
		var dy: float = float((at as Dictionary)["y"]) - float(pos["y"])
		var rem: float = float((at as Dictionary)["magnitude"]) - sqrt(dx * dx + dy * dy)
		if rem <= best_rem:
			continue
		if world.vision.detail(int(entity), float((at as Dictionary)["x"]), float((at as Dictionary)["y"])) == 0:
			continue
		best_rem = rem
		best_x = float((at as Dictionary)["x"])
		best_y = float((at as Dictionary)["y"])
	if best_rem <= 0.0:
		return
	var current: float = atan2(float(vel["dy"]), float(vel["dx"]))
	var toward: float = atan2(best_y - float(pos["y"]), best_x - float(pos["x"]))
	var delta: float = toward - current
	while delta > PI:
		delta -= PI * 2.0
	while delta < -PI:
		delta += PI * 2.0
	var angle: float = current + delta * LIGHT_BIAS * LIGHT_SENSITIVITY
	vel["dx"] = cos(angle) * speed
	vel["dy"] = sin(angle) * speed


# What one bite takes out of one part. Public and static so a gate can assert the arithmetic
# without standing up a hold, and so there is exactly one place the scaling lives -- the publish
# site below is the only caller.
#
# The band edge is deliberate and worth naming, because it moves a wound's severity, not just its
# number: wounds.gd bands severity on damage / part max, and an arm bite used to be 8/20 = 0.40,
# sitting exactly on the DeepWound boundary. Scaled, an arm takes 7.0 of 20 = 0.35, which is a
# Laceration -- a fifth of the bleed rate (BLEED_PER_TICK 0.004 against 0.02). That is the
# intended side of the line: a bite on a forearm you were using to fend a mouth off should be a
# nasty tear you can bandage, and the deep wounds should belong to the torso and the throat.
static func bite_damage_for(body: Variant, part: String) -> float:
	if not (body is Dictionary):
		return BITE_DAMAGE
	var part_max: Variant = SimHealthRes.max_of(body as Dictionary, part)
	if part_max == null or int(part_max) <= 0:
		return BITE_DAMAGE
	return maxf(BITE_DAMAGE_MIN, minf(BITE_DAMAGE, BITE_DAMAGE_PART_FRACTION * float(int(part_max))))


# The bite_damage_for shape at half the fraction -- see the SWIPE constants for why a swipe must
# not share a bite's numbers, and the CLAUDE.md trap for why neither may be flat.
static func swipe_damage_for(body: Variant, part: String) -> float:
	if not (body is Dictionary):
		return SWIPE_DAMAGE
	var part_max: Variant = SimHealthRes.max_of(body as Dictionary, part)
	if part_max == null or int(part_max) <= 0:
		return SWIPE_DAMAGE
	return maxf(SWIPE_DAMAGE_MIN, minf(SWIPE_DAMAGE, SWIPE_DAMAGE_PART_FRACTION * float(int(part_max))))


# A short physical reach may cross screening foliage, but never a solid wall or window.
# Three samples along the ray rather than a full raycast, matching the oracle's clearContact
# (src/sim/modules/shambler.ts:628) -- world.is_blocked_tile is the Godot equivalent of the
# oracle's blockedAt, and floori() here matches world.gd's own _blocked_at exactly.
static func _clear_contact(world: Variant, from: Dictionary, to: Dictionary) -> bool:
	for fraction in [0.25, 0.5, 0.75]:
		var x: float = float(from["x"]) + (float(to["x"]) - float(from["x"])) * fraction
		var y: float = float(from["y"]) + (float(to["y"]) - float(from["y"])) * fraction
		if world.is_blocked_tile(floori(x), floori(y)):
			return false
	return true


# Opens a hold. Idempotent: a source that already has a grabState is left alone rather than
# re-rolling ticksUntilBite, and a victim already held by someone else just gains a second
# source rather than a second `grabbed` component.
static func _start_grab(world: Variant, source: int, victim: int) -> void:
	if world.components.has_component(source, "grabState"):
		return
	world.components.set_component(source, "grabState", {"victim": victim, "ticksUntilBite": FIRST_BITE_TICKS})
	var existing: Variant = world.components.get_component(victim, "grabbed")
	var grabbed: Dictionary
	if existing is Dictionary:
		grabbed = existing as Dictionary
	else:
		# CLAUDE.md trap #1: a plain Array, never a PackedInt32Array -- appending to a packed
		# array read out of a Dictionary appends to a copy and silently does nothing.
		grabbed = {"sources": [], "struggleTicks": 0, "heldTicks": 0}
		world.components.set_component(victim, "grabbed", grabbed)
	var sources: Array = grabbed["sources"] as Array
	if not sources.has(source):
		sources.append(source)
		# Slot-ordered by entity index, not insertion order, so a save/load or a replay sees
		# the same holder list regardless of which shambler's think-loop happened to run first.
		sources.sort_custom(func(a, b) -> bool: return SimEntityStoreRes.entity_index(int(a)) < SimEntityStoreRes.entity_index(int(b)))
	world.events.publish({"type": "grab.started", "victim": victim, "source": source})


# Closes one hold. Always arms the REGRAB_COOLDOWN_TICKS re-grab cooldown on the source,
# regardless of why the hold ended (escape, rescue, geometry, or either body dying) -- a freed
# survivor gets one clear second before the same shambler can close on them again.
#
# `cause` and `by` are carried through to the `grab.broken` published at the single point a victim
# becomes *fully* free, below. They are defaulted rather than required because both release paths
# are also reached from the entity.killed subscription, where there is no caller to ask.
static func _release_grab(world: Variant, source: int, cause: String = "geometry", by: int = -1) -> void:
	var hold: Variant = world.components.get_component(source, "grabState")
	if not (hold is Dictionary):
		return
	world.components.remove(source, "grabState")
	var shambler_data: Variant = world.components.get_component(source, "shambler")
	if shambler_data is Dictionary:
		(shambler_data as Dictionary)["ticksToGrab"] = REGRAB_COOLDOWN_TICKS
	var grabbed: Variant = world.components.get_component(int((hold as Dictionary)["victim"]), "grabbed")
	if not (grabbed is Dictionary):
		return
	var sources: Array = (grabbed as Dictionary)["sources"] as Array
	var index: int = sources.find(source)
	if index != -1:
		sources.remove_at(index)
	if sources.is_empty():
		var freed: int = int((hold as Dictionary)["victim"])
		world.components.remove(freed, "grabbed")
		# One event per hold that actually ended, published here and nowhere else, because here is
		# the only place a victim goes from held to free -- a partial release, one hand off a
		# survivor two shamblers have, is not somebody getting out and says nothing. `by` is
		# whoever is responsible where that means anything (the rescuer, or the victim's own
		# struggle) and -1 where it does not. No RNG is drawn, nothing is decided: this is the
		# observation channel a bus-only harness needs to count releases at all.
		world.events.publish({"type": "grab.broken", "victim": freed, "by": by, "cause": cause})
		_break_away(world, freed, source)


# Points a just-freed survivor away from whoever was holding them and commits them to that
# heading for BREAK_AWAY_TICKS. Direction is taken once, at the moment of release, rather than
# re-derived per tick: this is somebody shoving off and stumbling clear, not a pursuit solver, and
# re-aiming every tick would have it orbit a shambler that follows.
#
# "Away" is the *preference*, not the commitment, and that distinction is the whole of this
# slice. Straight-away was the commitment for five slices and it was measurably the wrong one: a
# colony is grabbed where a colony lives, which is against the annex walls, so the shove-off
# pointed into masonry and movement.integrate zeroed it. Over three days of seed 404 the committed
# heading was blocked on both axes on 86% of breakAway ticks and the body covered 0.010 m per tick
# against a nominal 0.105 -- an escape that opened no gap at all, which is why the same shambler
# took the same survivor again in 309 of 309 measured windows.
#
# The fix keeps the shove-off and changes only which single heading it commits to: fan out from
# straight-away in BREAK_AWAY_FAN_DEGREES order and take the first candidate with a clear run of
# BREAK_AWAY_PROBE_METRES, falling back to whichever candidate has the longest clear run when none
# is fully clear. Because the fan is ordered by increasing deviation and the comparison is strict,
# the heading chosen is always the closest one to straight-away that qualifies -- in open field
# that is straight-away itself, unchanged, which is the negative AWAY-CLEAR pins. The fan stops at
# +/-135 rather than reaching 180: a survivor shoving off does not run through the thing that had
# hold of them.
#
# This is geometry, not a search: no RNG is drawn and nothing is stored, so the same release in
# the same world commits the same heading.
static func _break_away(world: Variant, victim: int, from_source: int) -> void:
	var at: Variant = world.components.get_component(victim, "position")
	var away_from: Variant = world.components.get_component(from_source, "position")
	if not (at is Dictionary) or not (away_from is Dictionary):
		return
	var dx: float = float((at as Dictionary)["x"]) - float((away_from as Dictionary)["x"])
	var dy: float = float((at as Dictionary)["y"]) - float((away_from as Dictionary)["y"])
	var length: float = sqrt(dx * dx + dy * dy)
	if length == 0.0:
		return
	var heading: float = _somewhere_to_go(world, at as Dictionary, atan2(dy, dx))
	world.components.set_component(victim, "breakAway", {
		"dx": cos(heading) * BREAK_AWAY_SPEED,
		"dy": sin(heading) * BREAK_AWAY_SPEED,
		"ticksLeft": BREAK_AWAY_TICKS,
	})


# The heading the shove-off actually commits to: `away` if it has room, else the nearest thing to
# it that does. Returns `away` unchanged when nothing is fully clear either, which is the old
# behaviour and the right one -- a body wedged in a corner has no better answer, and inventing one
# would be the pursuit solver this deliberately is not.
static func _somewhere_to_go(world: Variant, at: Dictionary, away: float) -> float:
	var best_angle: float = away
	var best_run: float = -1.0
	for degrees in BREAK_AWAY_FAN_DEGREES:
		var angle: float = away + deg_to_rad(float(degrees))
		var run: float = _clear_run(world, at, angle)
		if run >= BREAK_AWAY_PROBE_METRES:
			return angle
		if run > best_run:
			best_run = run
			best_angle = angle
	return best_angle


# How far a body can travel along `angle` from `at` before its footprint stops fitting, capped at
# BREAK_AWAY_PROBE_METRES. Sampled every BREAK_AWAY_PROBE_STEP, which is under the 0.7 m body
# diameter, so a doorway-width gap cannot be stepped over. world.body_fits_at is the same tile
# lookup movement.integrate collides against, so a run this reports as clear is one the integrator
# will not zero.
static func _clear_run(world: Variant, at: Dictionary, angle: float) -> float:
	var cx: float = float(at["x"])
	var cy: float = float(at["y"])
	var ux: float = cos(angle)
	var uy: float = sin(angle)
	var travelled: float = 0.0
	while travelled < BREAK_AWAY_PROBE_METRES:
		var next: float = minf(travelled + BREAK_AWAY_PROBE_STEP, BREAK_AWAY_PROBE_METRES)
		if not world.body_fits_at(cx + ux * next, cy + uy * next):
			return travelled
		travelled = next
	return travelled


# Frees a victim from every hand holding them at once -- the whole point of the contextual F
# struggle, and what entity.killed routes through when the victim dies. Duplicated first: each
# _release_grab call mutates the same sources array the loop would otherwise be walking.
static func _release_victim(world: Variant, victim: int, cause: String = "geometry", by: int = -1) -> void:
	var grabbed: Variant = world.components.get_component(victim, "grabbed")
	if not (grabbed is Dictionary):
		return
	var sources: Array = ((grabbed as Dictionary)["sources"] as Array).duplicate()
	for source in sources:
		_release_grab(world, int(source), cause, by)


# Commits one escape attempt, whoever asked for it. The three intakes below -- the player's F,
# the held survivor's instinct, and an NPC's -- differ only in *when* they call this; what an
# attempt costs and whether it is affordable is decided once, here, so a lever moved for one of
# them cannot quietly miss the other two. Returns whether an attempt was actually armed.
#
# Arming resets `heldTicks`, which is what makes instinct a gap between attempts rather than the
# age of the hold: a survivor who has just spent a tankful failing gets the same beat before the
# next try, and a player who presses F pushes instinct back by doing so.
static func _arm_struggle(world: Variant, victim: int) -> bool:
	var grabbed: Variant = world.components.get_component(victim, "grabbed")
	if not (grabbed is Dictionary):
		return false
	var g: Dictionary = grabbed as Dictionary
	if int(g["struggleTicks"]) > 0:
		return false
	var stamina: Variant = world.components.get_component(victim, "stamina")
	if stamina is Dictionary and float((stamina as Dictionary)["current"]) < STRUGGLE_STAMINA:
		return false
	g["struggleTicks"] = STRUGGLE_TICKS
	g["heldTicks"] = 0
	world.events.publish({"type": "stamina.spent", "entity": victim, "amount": STRUGGLE_STAMINA})
	return true


# Commits one rescue attempt, whoever asked for it -- the H key, or an NPC deciding that the
# thing in front of it is holding somebody. Same shape as _arm_struggle and try_begin_swing, and
# for the same reason: two intakes with independently written preconditions is exactly the drift
# that put condition.gd behind one builder. Returns whether an attempt was actually armed.
#
# What it does not do is decide the outcome. Arming only starts the heave; the contest is rolled
# RESCUE_TICKS later in shambler.think, which re-validates first -- so a hold that ends on its own
# in the meantime costs the rescuer their stamina and nothing else, which is the right price for
# committing to something that turned out to be over.
static func try_begin_rescue(world: Variant, rescuer: int, victim: int) -> bool:
	if rescuer == victim:
		return false
	if not world.components.has_component(victim, "grabbed"):
		return false
	var body: Variant = world.components.get_component(rescuer, "body")
	if body is Dictionary and not SimHealthRes.is_alive(body as Dictionary):
		return false
	# Your own hands have to be free. Being held, holding a dressing on somebody, or being the one
	# under the dressing are all the same answer -- the melee.try_begin_swing list, kept identical
	# on purpose so that "can this person act right now" has one meaning in this simulation.
	for busy in ["grabbed", "treatment", "treated", "rescue", "rescueCooldown", "corpse"]:
		if world.components.has_component(rescuer, busy):
			return false
	var from: Variant = world.components.get_component(rescuer, "position")
	var to: Variant = world.components.get_component(victim, "position")
	if not (from is Dictionary) or not (to is Dictionary):
		return false
	var dx: float = float((to as Dictionary)["x"]) - float((from as Dictionary)["x"])
	var dy: float = float((to as Dictionary)["y"]) - float((from as Dictionary)["y"])
	if sqrt(dx * dx + dy * dy) > RESCUE_METRES:
		return false
	if not _clear_contact(world, from as Dictionary, to as Dictionary):
		return false
	var stamina: Variant = world.components.get_component(rescuer, "stamina")
	if stamina is Dictionary and float((stamina as Dictionary)["current"]) < RESCUE_STAMINA:
		return false
	world.components.set_component(rescuer, "rescue", {"victim": victim, "ticksLeft": RESCUE_TICKS})
	world.events.publish({"type": "stamina.spent", "entity": rescuer, "amount": RESCUE_STAMINA})
	return true


# The nearest held survivor somebody could reach, which is the whole of target selection for a
# rescue and lives in sim rather than in the key handler -- presentation picks neither the target
# nor the verb, the same rule the T key's first aid follows. Ties break on entity_index so two
# survivors held at exactly the same distance resolve the same way on a replay.
static func rescue_target(world: Variant, rescuer: int) -> int:
	var from: Variant = world.components.get_component(rescuer, "position")
	if not (from is Dictionary):
		return -1
	var best: int = -1
	var best_dist: float = RESCUE_METRES * RESCUE_METRES
	for victim in world.components.query(["grabbed", "position"]):
		if int(victim) == rescuer:
			continue
		var at: Dictionary = world.components.get_component(int(victim), "position") as Dictionary
		var dx: float = float(at["x"]) - float((from as Dictionary)["x"])
		var dy: float = float(at["y"]) - float((from as Dictionary)["y"])
		var dist: float = dx * dx + dy * dy
		if dist > best_dist:
			continue
		if dist == best_dist and best >= 0 and SimEntityStoreRes.entity_index(int(victim)) >= SimEntityStoreRes.entity_index(best):
			continue
		best = int(victim)
		best_dist = dist
	return best


static func register_module(world: Variant, _map: Variant) -> void:
	world.systems.register("shambler.think", "ai", 0, func(w: Variant) -> void:
		var rng: Variant = w.rng.stream("shambler")
		var field: Variant = w.field
		var survivors: Array = _gather_survivors(w)
		var audible: float = float(field.calibration["floor"]) / NOISE_SENSITIVITY
		var detectable: float = float(field.calibration["scentFloor"]) / SCENT_SENSITIVITY
		for entity in w.components.query(["position", "velocity", "shambler"]):
			var shambler_comp: Variant = w.components.get_component(int(entity), "shambler")
			var pos: Variant = w.components.get_component(int(entity), "position")
			var vel: Variant = w.components.get_component(int(entity), "velocity")
			if shambler_comp == null or pos == null or vel == null:
				continue
			var sd: Dictionary = shambler_comp as Dictionary
			var vd: Dictionary = vel as Dictionary
			var pd: Dictionary = pos as Dictionary
			var heard: bool = field.noise_at(float(pd["x"]), float(pd["y"])) >= audible
			var smelled: bool = field.scent_at(float(pd["x"]), float(pd["y"])) >= detectable
			# Resolved once per shambler per tick and handed to every steer below it, rather than
			# each of them reaching for sd["seekSpeed"] -- which is what let the cripple penalty
			# sit on the component unread for the whole of Milestone 2.
			var seek: float = _speed_of(w, int(entity), sd, "seekSpeed")
			if int(sd["ticksToGrab"]) > 0:
				sd["ticksToGrab"] = int(sd["ticksToGrab"]) - 1
			if w.components.has_component(int(entity), "grabState"):
				# Holding is neither pathfinding nor pursuit. Both bodies stay exactly where
				# the mistake happened until the survivor escapes or something knocks the
				# grabber away -- see the hold-lifecycle loops below this state machine for
				# what actually resolves a hold (validate, struggle, bite, then acquire).
				vd["dx"] = 0.0
				vd["dy"] = 0.0
				continue
			match int(sd["state"]):
				ShamblerState["Staggered"]:
					vd["dx"] = 0.0
					vd["dy"] = 0.0
					sd["ticksStaggered"] = int(sd["ticksStaggered"]) - 1
					if int(sd["ticksStaggered"]) <= 0:
						sd["state"] = ShamblerState["Wander"]
						sd["ticksToTurn"] = 0
				ShamblerState["Pursue"]:
					var target: Variant = _contact_target(survivors, pd, RELEASE_METRES)
					if target == null:
						sd["state"] = ShamblerState["Wander"]
						sd["ticksToTurn"] = int(rng.call("int_range", 20, 120))
					else:
						_chase(w, int(target), pd, vd, sd, seek)
				ShamblerState["Seek"]:
					var caught: Variant = _contact_target(survivors, pd, CONTACT_METRES)
					if caught != null:
						sd["state"] = ShamblerState["Pursue"]
						sd["ticksCommitted"] = 0
						_chase(w, int(caught), pd, vd, sd, seek)
					elif _steer_uphill(field, pd, vd, sd, seek):
						sd["ticksCommitted"] = COMMIT_TICKS
					elif heard:
						sd["state"] = ShamblerState["Investigate"]
						sd["ticksMilling"] = MILL_TICKS
						sd["ticksToTurn"] = 0
					elif int(sd["ticksCommitted"]) - 1 > 0:
						sd["ticksCommitted"] = int(sd["ticksCommitted"]) - 1
					else:
						sd["ticksCommitted"] = 0
						sd["state"] = ShamblerState["Investigate"]
						sd["ticksMilling"] = MILL_TICKS
						sd["ticksToTurn"] = 0
				ShamblerState["Investigate"]:
					sd["ticksMilling"] = int(sd["ticksMilling"]) - 1
					if int(sd["ticksMilling"]) <= 0:
						sd["state"] = ShamblerState["Wander"]
						sd["ticksToTurn"] = 0
					elif int(sd["ticksToTurn"]) <= 0:
						var angle: float = rng.call("float_range", 0.0, PI * 2.0)
						vd["dx"] = cos(angle) * _speed_of(w, int(entity), sd, "millSpeed")
						vd["dy"] = sin(angle) * _speed_of(w, int(entity), sd, "millSpeed")
						sd["ticksToTurn"] = int(rng.call("int_range", 10, 25))
					else:
						sd["ticksToTurn"] = int(sd["ticksToTurn"]) - 1
				_:
					var caught2: Variant = _contact_target(survivors, pd, CONTACT_METRES)
					if caught2 != null:
						sd["state"] = ShamblerState["Pursue"]
						_chase(w, int(caught2), pd, vd, sd, seek)
					elif heard:
						sd["state"] = ShamblerState["Seek"]
						sd["ticksCommitted"] = COMMIT_TICKS
						_steer_uphill(field, pd, vd, sd, seek)
					elif int(sd["ticksToTurn"]) <= 0:
						var angle2: float = rng.call("float_range", 0.0, PI * 2.0)
						vd["dx"] = cos(angle2) * _speed_of(w, int(entity), sd, "wanderSpeed")
						vd["dy"] = sin(angle2) * _speed_of(w, int(entity), sd, "wanderSpeed")
						sd["ticksToTurn"] = int(rng.call("int_range", 20, 120))
					else:
						sd["ticksToTurn"] = int(sd["ticksToTurn"]) - 1
					if smelled:
						_drift_upscent(field, pd, vd, sd, seek)
					_lean_to_light(w, int(entity), pd, vd)

		# --- Hold lifecycle, alongside the state machine above rather than in a separate
		# combat-phase system (plan deviates from the oracle here on purpose). Order is
		# ported from the oracle's shambler.grab (src/sim/modules/shambler.ts:872-960) and
		# still matters: validate existing holds, resolve a completed struggle, deliver
		# due bites, then begin new holds. An escape that completes this tick therefore
		# wins a same-tick tie against a bite -- the released hold's grabState is gone by
		# the time the bite loop's query runs -- and the re-grab cooldown _release_grab
		# arms stops the final pass from taking the same survivor again immediately.
		var grab_rng: Variant = w.rng.stream("grab")

		# 0. Swipes -- before the hold lifecycle, so a shambler that begins a hold this tick
		# (step 4) has already had its swipe considered as a free body, and a holder never
		# swipes at all: its mouth is the threat, per step 3. Own RNG stream, drawn from only
		# when a swipe actually lands, so the "shambler" and "grab" sequences are untouched
		# whether anything swipes or not.
		var swipe_rng: Variant = w.rng.stream("swipe")
		for swiper in w.components.query(["position", "shambler"]):
			var sw: Dictionary = w.components.get_component(int(swiper), "shambler") as Dictionary
			var mark: Variant = null
			if int(sw["state"]) == ShamblerState["Pursue"] and not w.components.has_component(int(swiper), "grabState"):
				var from_sw: Dictionary = w.components.get_component(int(swiper), "position") as Dictionary
				var reached: Variant = _contact_target(survivors, from_sw, SWIPE_METRES)
				# A held body is being bitten, not swiped -- piling swipes onto a grapple would
				# hand the flip's lethality question a new variable through the back door. And a
				# wall between refuses the swipe the same way it refuses a grab.
				if reached != null and not w.components.has_component(int(reached), "grabbed"):
					var at_sw: Variant = w.components.get_component(int(reached), "position")
					if at_sw is Dictionary and _clear_contact(w, from_sw, at_sw as Dictionary):
						mark = reached
			if mark == null:
				sw["ticksToSwipe"] = SWIPE_FIRST_TICKS
				continue
			var wind: int = int(sw.get("ticksToSwipe", SWIPE_FIRST_TICKS)) - 1
			if wind > 0:
				sw["ticksToSwipe"] = wind
				continue
			sw["ticksToSwipe"] = SWIPE_RECOVER_TICKS
			var mark_body: Variant = w.components.get_component(int(mark), "body")
			if mark_body == null:
				continue
			var struck: String = SimMeleeRes._roll_body_part(swipe_rng, mark_body)
			w.events.publish({
				"type": "attack.connected",
				"attacker": int(swiper),
				"target": int(mark),
				"bodyPart": struck,
				"damage": swipe_damage_for(mark_body, struck),
			})

		# 1. Validate. A grabState pointing at a dead, despawned, or now-unreachable
		# victim does not persist -- the entity.killed subscription below handles death
		# and despawn across tick boundaries; this is the geometry half, the wall that
		# grew or the reach that widened between one tick and the next.
		for source in w.components.query(["grabState", "position", "shambler"]):
			var hold: Dictionary = w.components.get_component(int(source), "grabState") as Dictionary
			var victim: int = int(hold["victim"])
			var from_pos: Dictionary = w.components.get_component(int(source), "position") as Dictionary
			var at_pos: Variant = w.components.get_component(victim, "position")
			var still_here: bool = at_pos is Dictionary and w.entities.is_alive(victim)
			if still_here:
				var dx: float = float((at_pos as Dictionary)["x"]) - float(from_pos["x"])
				var dy: float = float((at_pos as Dictionary)["y"]) - float(from_pos["y"])
				still_here = sqrt(dx * dx + dy * dy) <= RELEASE_METRES and _clear_contact(w, from_pos, at_pos as Dictionary)
			if not still_here:
				_release_grab(w, int(source), "geometry")
				var self_data: Dictionary = w.components.get_component(int(source), "shambler") as Dictionary
				self_data["state"] = ShamblerState["Wander"]
				self_data["ticksToTurn"] = 20
				continue
			var source_vel: Variant = w.components.get_component(int(source), "velocity")
			if source_vel is Dictionary:
				(source_vel as Dictionary)["dx"] = 0.0
				(source_vel as Dictionary)["dy"] = 0.0
			var victim_vel: Variant = w.components.get_component(victim, "velocity")
			if victim_vel is Dictionary:
				(victim_vel as Dictionary)["dx"] = 0.0
				(victim_vel as Dictionary)["dy"] = 0.0

		# 2. Resolve a completed struggle. shambler.struggle-intake (input, order 9) arms
		# struggleTicks; once it counts down to zero the escape roll happens exactly once.
		# A successful escape does not force the holder(s) back to Wander -- only geometry
		# failure (step 1) does that; an escaped-from shambler is still Pursuing and will
		# chase again next tick through the ordinary state machine above.
		# Deliberately not scoped to `controlled`: three intakes arm struggleTicks now -- the
		# player's F, a held survivor's instinct, and an NPC's own -- and all three resolve
		# through this one contest, which is why widening who may struggle has never meant
		# touching the escape maths. Nor does a running first-aid channel enter into it
		# (treatment.gd's R4): a hand on your own wound is not "your action" for the hold, and a
		# survivor made to choose between getting free and not bleeding would only ever lose one of
		# the two. What winning *costs* is the press: the `grab.broken` published below is what
		# treatment.gd's R5 hears, and it ends the victim's hand on their own wound so the
		# break-away is a run rather than a pause. The hand goes back on once they are clear (R6).
		for victim in w.components.query(["grabbed"]):
			var grabbed: Dictionary = w.components.get_component(int(victim), "grabbed") as Dictionary
			if int(grabbed["struggleTicks"]) <= 0:
				continue
			grabbed["struggleTicks"] = int(grabbed["struggleTicks"]) - 1
			if int(grabbed["struggleTicks"]) > 0:
				continue
			var total_strength: float = 0.0
			for source2 in grabbed["sources"] as Array:
				var holder: Variant = w.components.get_component(int(source2), "shambler")
				if holder is Dictionary:
					total_strength += float((holder as Dictionary)["grabStrength"])
			if float(grab_rng.call("next")) < SimAptitudesRes.escape_chance(w, int(victim), total_strength):
				# `by` is the victim: they are who broke it, and a rescue is the only other thing
				# that can, so the two are told apart at the point of release rather than guessed
				# at from the outside.
				_release_victim(w, int(victim), "struggle", int(victim))

		# 2b. Resolve a completed rescue. shambler.rescue-intake (input, order 8) arms the
		# `rescue` component; RESCUE_TICKS later the contest happens exactly once, here, so that
		# a rescue landing on this tick wins the same same-tick tie against a bite that an escape
		# does -- the released hold's grabState is gone before step 3's query runs.
		#
		# Re-validated before anything is rolled: a hold the victim broke out of themselves in the
		# meantime, or walked out of range of, is a fizzle rather than a free release, and it draws
		# no number at all. The cooldown is armed either way -- an attempt was made.
		for rescuer in w.components.query(["rescue"]):
			var attempt: Dictionary = w.components.get_component(int(rescuer), "rescue") as Dictionary
			attempt["ticksLeft"] = int(attempt["ticksLeft"]) - 1
			if int(attempt["ticksLeft"]) > 0:
				continue
			var saved: int = int(attempt["victim"])
			w.components.remove(int(rescuer), "rescue")
			w.components.set_component(int(rescuer), "rescueCooldown", {"ticksLeft": RESCUE_RETRY_TICKS})
			var still_held: Variant = w.components.get_component(saved, "grabbed")
			if not (still_held is Dictionary):
				continue
			var from_r: Variant = w.components.get_component(int(rescuer), "position")
			var at_r: Variant = w.components.get_component(saved, "position")
			if not (from_r is Dictionary) or not (at_r is Dictionary):
				continue
			var rdx: float = float((at_r as Dictionary)["x"]) - float((from_r as Dictionary)["x"])
			var rdy: float = float((at_r as Dictionary)["y"]) - float((from_r as Dictionary)["y"])
			if sqrt(rdx * rdx + rdy * rdy) > RESCUE_METRES:
				continue
			var held_by: float = 0.0
			for holder_id in (still_held as Dictionary)["sources"] as Array:
				var holder2: Variant = w.components.get_component(int(holder_id), "shambler")
				if holder2 is Dictionary:
					held_by += float((holder2 as Dictionary)["grabStrength"])
			# The rescuer's own power against the same total grip, from a stream of its own so the
			# "grab" sequence draws the same numbers in the same order whether anybody rescues or
			# not. Stream seeds are derived from the name (rng_stream.gd derive_seed), never from
			# creation order, so this is deterministic even though it is reached lazily.
			if float(w.rng.stream("rescue").call("next")) < SimAptitudesRes.escape_chance(w, int(rescuer), held_by):
				# Every hand at once. The measured average is 1.4 holders on a survivor who is in
				# trouble, so freeing them from one of two is not freeing them.
				_release_victim(w, saved, "rescue", int(rescuer))

		# 3. Deliver due bites, over the holds that survived steps 1-2 -- a hold released
		# this tick simply no longer matches this query.
		for source3 in w.components.query(["grabState", "shambler"]):
			var hold2: Dictionary = w.components.get_component(int(source3), "grabState") as Dictionary
			var ticks_left: int = int(hold2["ticksUntilBite"]) - 1
			if ticks_left > 0:
				hold2["ticksUntilBite"] = ticks_left
				continue
			hold2["ticksUntilBite"] = REPEAT_BITE_TICKS
			var bite_victim: int = int(hold2["victim"])
			var victim_body: Variant = w.components.get_component(bite_victim, "body")
			# Held geometry, not swing geometry -- SimCombatRes.HELD_HIT_LOCATION_WEIGHTS carries
			# the reasoning for why the head share collapses inside a grapple. A zombie body
			# ignores the override (melee.gd); zombies do not grab each other today, but the
			# roll should not have to care.
			var bitten: String = SimMeleeRes._roll_body_part(grab_rng, victim_body, SimCombatRes.HELD_HIT_LOCATION_WEIGHTS)
			w.events.publish({
				"type": "bite.landed",
				"victim": bite_victim,
				"source": int(source3),
				"bodyPart": bitten,
				"damage": bite_damage_for(victim_body, bitten),
			})

		# 4. Begin new holds. Only a Pursuing shambler not already holding someone, not on
		# the post-release cooldown, and whose content entry permits grab at all.
		for source4 in w.components.query(["position", "shambler"]):
			var self_data2: Dictionary = w.components.get_component(int(source4), "shambler") as Dictionary
			if int(self_data2["state"]) != ShamblerState["Pursue"]:
				continue
			if not GRABS_ENABLED:
				continue
			if not bool(self_data2["canGrab"]) or int(self_data2["ticksToGrab"]) > 0:
				continue
			if w.components.has_component(int(source4), "grabState"):
				continue
			var from4: Dictionary = w.components.get_component(int(source4), "position") as Dictionary
			var new_victim: Variant = _contact_target(survivors, from4, GRAB_METRES)
			if new_victim == null:
				continue
			var at4: Dictionary = w.components.get_component(int(new_victim), "position") as Dictionary
			if _clear_contact(w, from4, at4):
				_start_grab(w, int(source4), int(new_victim))
	)

	# F is contextual: it starts a swing while free (melee.gd:138 already refuses one while
	# grabbed) and a committed escape attempt while held. Neither module writes the other's
	# state -- the meaning of F is decided here, in sim, not in presentation.
	world.systems.register("shambler.struggle-intake", "input", 9, func(w: Variant) -> void:
		var has_swing: bool = false
		for c in w.commands.current:
			if String((c as Dictionary).get("type", "")) == "swing":
				has_swing = true
				break
		# Age every hold once, before anything reads the clock, so the three intakes below all
		# see the same tick's number regardless of the order they run in.
		for held_ent in w.components.query(["grabbed"]):
			var timing: Dictionary = w.components.get_component(int(held_ent), "grabbed") as Dictionary
			timing["heldTicks"] = int(timing.get("heldTicks", 0)) + 1

		# Note the early return moved below the NPC loop's concern: a swing command gates the
		# *player's* struggle only. An NPC's is not a key press and must not depend on one.
		# Controlled only, as the oracle scopes it (src/sim/modules/shambler.ts:686). Without
		# this the player's F would arm a struggle on *every* held body in the district and
		# spend each of their stamina -- one key press buying escapes nobody asked for.
		for victim in (w.components.query(["grabbed", "controlled"]) if has_swing else []):
			_arm_struggle(w, int(victim))

		# Instinct: the same escape, taken without being asked for, once a held survivor has
		# spent STRUGGLE_INSTINCT_TICKS with nobody answering for them. Being grabbed is not a
		# state a person waits politely in, and the balance harness proved the cost of pretending
		# otherwise -- an unattended `controlled` survivor recorded 45 bites and 0 struggles in a
		# campaign, because F is a key press and a harness presses nothing.
		#
		# F stays the better answer rather than the only one: a player who reaches for it commits
		# the escape immediately, two seconds before instinct would have, and resets the clock by
		# arming. So this never takes a decision away from someone making one; it only refuses to
		# stand still on behalf of someone who is not.
		for waiting in w.components.query(["grabbed", "controlled"]):
			var patience: Dictionary = w.components.get_component(int(waiting), "grabbed") as Dictionary
			if int(patience.get("heldTicks", 0)) < STRUGGLE_INSTINCT_TICKS:
				continue
			_arm_struggle(w, int(waiting))

		# NPCs struggle on their own, because they have no F to press. Without this a single
		# shambler disables a survivor permanently: melee.gd:138 refuses a held body its swing
		# and npc_combat.gd's threat loop drops it entirely, so a guard taken at its post could
		# neither fight nor leave, for the rest of the run. That is not the grab being dangerous,
		# it is the grab being absorbing, and it is a regression this loop would otherwise have
		# introduced. They pay the same stamina and roll the same contest as the player; what
		# they lack is the choice of when, so they always take it -- with no instinct delay,
		# because there is no key press for them to be waiting on.
		for npc in w.components.query(["grabbed", "identity"]):
			if w.components.has_component(int(npc), "controlled"):
				continue
			_arm_struggle(w, int(npc))
	)

	# H, and only H. F was not made triple-contextual on purpose: swinging at the shambler that
	# has hold of your neighbour is a legitimate and different answer, and a key that silently
	# picked between the two would take that choice away.
	#
	# Registered as its own system rather than as another branch of shambler.struggle-intake,
	# at order 8 so the cooldown ages before anything reads it. The separation is deliberate and
	# load-bearing for the gates: check_m2_contact's `_no_struggling` silences the struggle
	# intake to measure what a hold does to somebody who cannot get out of it, and a rescue
	# arriving from a system it did not unregister is exactly the exit those assertions are
	# testing for.
	world.systems.register("shambler.rescue-intake", "input", 8, func(w: Variant) -> void:
		for waiting in w.components.query(["rescueCooldown"]):
			var cd: Dictionary = w.components.get_component(int(waiting), "rescueCooldown") as Dictionary
			cd["ticksLeft"] = int(cd["ticksLeft"]) - 1
			if int(cd["ticksLeft"]) <= 0:
				w.components.remove(int(waiting), "rescueCooldown")
		var asked: bool = false
		for c in w.commands.current:
			if String((c as Dictionary).get("type", "")) == "rescue":
				asked = true
				break
		if not asked:
			return
		# Controlled only, the way the player's F is scoped: one key press must not commit every
		# free survivor in the district to a heave and spend their stamina on it.
		for actor in w.components.query(["controlled", "position"]):
			var target: int = rescue_target(w, int(actor))
			if target >= 0:
				try_begin_rescue(w, int(actor), target)
	)

	# Zeroes a grabbed survivor's velocity before movement.integrate (phase "movement" order 0,
	# world.gd) runs, so a hold pins rather than letting the survivor take a step first. Order
	# -1 in the same phase, not "ai": a movement command may still turn the survivor (facing),
	# it just cannot translate them through the bodies holding them.
	world.systems.register("shambler.pin", "movement", -1, func(w: Variant) -> void:
		for victim in w.components.query(["grabbed", "velocity"]):
			var vel: Dictionary = w.components.get_component(int(victim), "velocity") as Dictionary
			vel["dx"] = 0.0
			vel["dy"] = 0.0
		# Break-away runs in the same pass, after the pin, so a survivor re-taken on the very
		# tick they were carrying separation is pinned rather than dragged: being held always
		# wins over getting clear.
		#
		# It overrides an NPC's job velocity on purpose. The first cut only wrote a velocity
		# that was already zero, which read as politeness and meant the feature never fired for
		# a single NPC -- jobs.gd always has them walking somewhere, so the balance harness came
		# back byte-identical. A survivor who has just torn free of a zombie is not resuming
		# their errand for the next second and a bit. The player is the exception: their own
		# move command outranks it, because taking the controls away from someone mid-fight is
		# the one thing worse than being grabbed.
		for freed in w.components.query(["breakAway", "velocity"]):
			var run: Dictionary = w.components.get_component(int(freed), "breakAway") as Dictionary
			run["ticksLeft"] = int(run["ticksLeft"]) - 1
			if int(run["ticksLeft"]) <= 0 or w.components.has_component(int(freed), "grabbed"):
				w.components.remove(int(freed), "breakAway")
				continue
			var vel2: Dictionary = w.components.get_component(int(freed), "velocity") as Dictionary
			var steering: bool = w.components.has_component(int(freed), "controlled") \
				and (float(vel2["dx"]) != 0.0 or float(vel2["dy"]) != 0.0)
			if steering:
				continue
			vel2["dx"] = float(run["dx"])
			vel2["dy"] = float(run["dy"])
	)

	# A grabState pointing at a dead entity, or a grabbed pointing at holders that no longer
	# exist, must not persist -- CLAUDE.md is explicit that entity.killed fires more than once
	# for the same individual (health.gd on a destroyed head, infection.gd on a put-down and
	# again on turning), so both release calls below are written idempotent on purpose: a
	# second firing for the same entity finds nothing left to release and does nothing.
	# A rescuer who is grabbed mid-heave stops being a rescuer. Same shape and the same reason as
	# melee.gd's grab-interrupts on a wind-up: whatever your hands were doing, they are not doing
	# it now. The cooldown is deliberately *not* armed here -- the attempt was taken away rather
	# than made, and the stamina is already gone.
	world.events.subscribe({"id": "shambler.grab-interrupts-rescue", "type": "grab.started", "handler": func(event: Dictionary) -> void:
		world.components.remove(int(event.get("victim", -1)), "rescue")
	})

	world.events.subscribe({"id": "shambler.release-dead", "type": "entity.killed", "handler": func(event: Dictionary) -> void:
		var dead: int = int(event.get("entity", -1))
		_release_grab(world, dead, "holder-died", dead)
		_release_victim(world, dead, "victim-died", dead)
	})

	# docs/09: "landing a solid hit interrupts the target ... a staggered zombie isn't grabbing
	# you." Both halves are here, because the state machine already had a Staggered state that
	# nothing could enter and the clause is about grabbing rather than about speed.
	#
	# The hold is broken *before* the state is set: _release_grab reads `grabState` off this
	# entity, and the ordering is only safe in one direction. It publishes `grab.broken` with
	# cause `staggered` -- a cause rather than a silent release, so a bus-only harness can tell a
	# swing that saved somebody from a struggle that did -- and arms REGRAB_COOLDOWN_TICKS on its
	# way past, so the answer to a grab is not one swing followed by an instant re-take.
	#
	# `ticksStaggered` is taken as the max of what is already running and what this hit is worth,
	# so a second hit during a stagger extends it rather than cutting it short. Melee's own
	# staggerTicks comes off the weapon (melee.gd), which is where "blunt weapons stagger better"
	# lives; nothing about that is decided here.
	world.events.subscribe({"id": "shambler.stagger", "type": "entity.staggered", "handler": func(event: Dictionary) -> void:
		var entity: int = int(event.get("entity", -1))
		var shambler_data: Variant = world.components.get_component(entity, "shambler")
		if not (shambler_data is Dictionary):
			return
		_release_grab(world, entity, "staggered", entity)
		var sd: Dictionary = shambler_data as Dictionary
		sd["state"] = ShamblerState["Staggered"]
		sd["ticksStaggered"] = maxi(int(sd.get("ticksStaggered", 0)), int(event.get("ticks", 0)))
	})
