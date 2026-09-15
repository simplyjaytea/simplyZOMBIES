class_name SimStrangers
extends RefCounted

# Somebody sheltering in a building out in the district, who comes out when they see you.
#
# docs/07 says recruitment happens "through director-paced events: a scavenging encounter, a
# faction referral, someone at the gate during a bad night", and until this slice the colony had
# exactly one of the three: `SimRecruits._tick_beats` puts a rolled survivor at the gate on days 8,
# 12 and 16 and takes them away again at dawn. This is the first of the other two -- the encounter
# out in the district -- and the owner approved it with the rest of the procedural-population arc
# on 2026-09-14.
#
# Almost none of it is new mechanism, which is the point:
#
#   * the body is `SimRecruits.spawn_generated`, the same call the gate beat makes, so a stranger
#     is the same kind of person a gate recruit is -- rolled off `SimPeople.roll`, kitted, given
#     eyes, colony-aligned;
#   * the placement is the dormant slice's `SimWorldgen.far_buildings` + `indoor_tiles_of`, which
#     were made public for exactly this caller;
#   * the walk is `SimWalk.step`, the stepper lifted out of `SimRaiders`;
#   * and the acceptance is the **existing** E rung. `SimFortify`'s ladder already calls
#     `SimRecruits.waiting_in_reach` then `accept`, and `accept` already carries the hidden-bite
#     roll at `TRANSMIT_P`. A stranger is accepted by walking up to them and pressing E because
#     they carry the same `recruit {waiting: true}` tag a gate recruit does. There is deliberately
#     no second acceptance path: one rung, one roll, one place where a recruit can be carrying
#     something you cannot see.
#
# **The bite is exactly as hidden as the gate recruit's.** No field on the `stranger` component
# says anything about it, nothing is published about it, and the module never asks. Information
# stays scarce (CLAUDE.md's standing ban, docs/01 clause 4): the whole mechanism is the roll inside
# `accept`, and adding a tell here would be the one change this slice must not make.
#
# **The colony is told nothing when one is placed.** A gate recruit publishes `recruit.arrived` and
# the chronicle turns it into "Someone is waiting at the gate." A stranger hiding in a house two
# hundred metres away is not news, and a line saying otherwise would hand the player a fact nobody
# in the colony has -- the same clause again. What tells you there is somebody in that house is
# seeing them walk out of it.
#
# What keeps a hidden stranger off the colony's books is the `recruit` tag, which already means
# "a body that is not one of yours yet" everywhere it is read: `jobs.gd` will not schedule them,
# `needs.gd` will not drain them, `npc_combat.gd` will not fight for them, and
# `check_m2_balance.gd`'s `_survivors_alive` does not count them. That is why the tag is the one
# the stranger wears, rather than a marker of its own.

const Clock = preload("res://sim/time/clock.gd")
const SimAllegianceRes = preload("res://sim/modules/allegiance.gd")
const SimDirectorRes = preload("res://sim/modules/director.gd")
const SimHealthRes = preload("res://sim/modules/health.gd")
const SimPeopleRes = preload("res://sim/modules/people.gd")
const SimRecruitsRes = preload("res://sim/modules/recruits.gd")
const SimWalkRes = preload("res://sim/walk.gd")
const SimWorldgenRes = preload("res://sim/map/worldgen.gd")

## Hiding until somebody is seen, then walking to them, then standing. Stored as an int on the
## component, so a save carries a number and not an enum name.
enum StrangerState { Hiding = 0, Approaching = 1 }

# --- the first cuts, all five of them ----------------------------------------------------------
#
# Recorded as first cuts rather than as balance (docs/30, 2026-09-15): they are the plan's
# numbers, measured only for "the colony still survives", which is what the balance run below the
# fold of this slice's record actually asserts.

## Days a stranger turns up in a building. Between the gate beats (8, 12, 16) rather than on them,
## so the two routes into the colony are felt as two rather than as a busy week. **In daylight**,
## for the reason measured at the guard in `_tick_beats`.
const BEATS: Array[int] = [5, 10, 14]

## How many may be hiding in the district at once. Two, because the point of the feature is that
## finding one is an event; a district with a stranger in every other house is a population.
const LIVE_CAP: int = 2

## How far from the colony a building has to be to hold one, in metres. `SimDirector.GATE_EXCLUSION`
## rather than a number of its own: it is already the answer to "far enough from home that this is
## something you went out and found", it is what the dormant bodies are placed by, and a second
## constant here would be a second answer that drifts.
const MIN_METRES: float = SimDirectorRes.GATE_EXCLUSION

## Days they will wait before giving up on the colony. Three, so a stranger found on a beat day is
## still there on the next working day but not on the next beat.
const STRANGER_DAYS: int = 3

## How close they come before they stand and wait. Half a metre outside `SimFortify.REACH`, on
## purpose: somebody who does not know you yet stops a pace short, and the player closes the last
## half-metre themselves. So arriving is not the same moment as being in range of E, and the
## gate's RECRUIT lane presses from 0.9 m rather than from where they stopped.
const APPROACH_METRES: float = 2.0

## Walking pace, metres per second. A person walking towards somebody, not a raider closing.
const SPEED: float = 1.2

## Identity off `strangers`, age and look off `strangerLook` -- two streams, the shape
## `SimPeople.roll` takes and `SimRecruits.roll` already uses for the gate. New randomness gets its
## own named stream (CLAUDE.md): sharing the gate's would make every stranger placed shift the
## recruit sequence, and the two features would stop being independently measurable.
const STREAM: String = "strangers"
const LOOK_STREAM: String = "strangerLook"


static func default_state() -> Dictionary:
	return {"spawned": []}


static func register_module(world: Variant) -> void:
	if not "strangers" in world or not world.strangers is Dictionary:
		world.strangers = default_state()
	# "director"/11, one slot after `recruits.beats`: this is a director-paced arrival like the
	# gate beat, and it must run after the gate beat rather than before so the two cannot both
	# claim the same day's decision in a different order on a restore. The velocity it writes is
	# spent by `movement.integrate` on the next tick -- the director phase runs after movement --
	# which is the same one-tick lag `recruits._tick_leave` has always walked a departing colonist
	# out on.
	world.systems.register("strangers.tick", "director", 11, func(w: Variant) -> void:
		_tick_beats(w)
		_tick_behaviour(w)
	)


# --- placement ----------------------------------------------------------------------------------

static func _tick_beats(world: Variant) -> void:
	var day: int = Clock.day_number(int(world.tick))
	if not BEATS.has(day):
		return
	# **Daylight, and this is a measurement rather than a mood.** The beat used to fire on whatever
	# tick of the beat day the world happened to be running, which in a real campaign is dawn and
	# in the balance harness's compressed tier is *dusk* -- and a stranger placed at dusk in a
	# district the director is filling is dead inside one 2,000-tick window. Measured on seed
	# 31337: placed on day 5, killed and **turned** before the window ended, which put a shambler
	# in the district the director never placed and took `check_m2_balance.gd`'s live-cap
	# invariant to 33 against a cap of 32.
	#
	# So the arrival has a time of day, the way the dawn leave does. It is also the honest rule:
	# somebody sheltering in a building comes out when they see a colonist, and a colonist is out
	# in the district during the working day. `check_m2_strangers.gd`'s DAYLIGHT lane holds both
	# halves.
	if Clock.phase_of(int(world.tick)) != Clock.Phase.Day:
		return
	var st: Dictionary = world.strangers as Dictionary
	var spawned: Array = st.get("spawned", []) as Array
	if spawned.has(day):
		return
	if live_count(world) >= LIVE_CAP:
		return
	# Strangers share the gate's cap. `SimRecruits.CAP` is how big the colony may get by taking
	# people in, and a second route in that had a cap of its own would quietly double it -- which
	# is a balance change smuggled in beside a feature. `accept` refuses past the cap anyway; this
	# is the same rule one step earlier, so a colony that is full never has somebody standing in a
	# house waiting to be told no.
	if int((world.recruits as Dictionary).get("accepted", 0)) >= SimRecruitsRes.CAP:
		return
	# Somewhere to put one, before the day is marked spent and before a single draw: a district
	# whose every building sits in the colony's lap (the 64-tile miniature the gates boot is often
	# exactly this) has nowhere for a stranger to hide, and the beat must cost it neither the day
	# nor the stream. The gate beat's missing-anchor guard is the precedent.
	# `null` for the stream, because this call draws nothing: asking `world.rng` for a stream
	# creates it, and a district that never places anybody would then carry an extra entry in
	# every save from the first beat day onwards.
	var spot: Vector2i = _spot(world, null, false)
	if spot.x < 0:
		return
	spawned.append(day)
	st["spawned"] = spawned
	place(world, day)


## Where a stranger may stand, drawn off `rng`, or (-1, -1) when the district has nowhere.
##
## `draw` false asks the question without spending the stream, which is what `_tick_beats` needs
## before it commits the day -- the two calls agree because they run the same scan, and the
## no-draw one picks the first legal tile it finds rather than a random one.
static func _spot(world: Variant, rng: Variant, draw: bool) -> Vector2i:
	var map: Variant = world.tilemap
	if map == null:
		return Vector2i(-1, -1)
	var far: Array[int] = SimWorldgenRes.far_buildings(map, MIN_METRES)
	if far.is_empty():
		return Vector2i(-1, -1)
	# Only the buildings with somewhere to stand in them, gathered before anything is drawn so a
	# draw cannot land on an empty one and have to be re-rolled (the worldgen idiom: the draw costs
	# the same whatever the map holds).
	var usable: Array = []
	for index in far:
		var building: Dictionary = (map.buildings as Array)[index] as Dictionary
		var tiles: Array = SimWorldgenRes.indoor_tiles_of(map, building)
		if not tiles.is_empty():
			usable.append(tiles)
	if usable.is_empty():
		return Vector2i(-1, -1)
	if not draw:
		return (usable[0] as Array)[0] as Vector2i
	var tiles_of: Array = usable[int(rng.call("int_range", 0, usable.size() - 1))] as Array
	return tiles_of[int(rng.call("int_range", 0, tiles_of.size() - 1))] as Vector2i


## Rolls a person, puts them indoors in a far building, and tags them. Returns the entity, or -1
## when the district has nowhere to put one. Public because the gate drives it directly: a fixture
## that had to wait for a beat day on a map that happens to qualify would be testing the map.
static func place(world: Variant, day: int) -> int:
	var rng: Variant = world.rng.stream(STREAM)
	var spot: Vector2i = _spot(world, rng, true)
	if spot.x < 0:
		return -1
	var rolled: Dictionary = SimPeopleRes.roll(rng, world.rng.stream(LOOK_STREAM), SimPeopleRes.pool(world, SimPeopleRes.SURVIVORS_POOL_ID))
	var ent: int = SimRecruitsRes.spawn_generated(world, rolled, float(spot.x) + 0.5, float(spot.y) + 0.5)
	return mark(world, ent, day)


## Tags an already-spawned body as a stranger. Split out from `place` so a gate can stand one
## anywhere it likes -- in a house it chose, behind a wall it built -- and still get exactly the
## body the beat would have produced.
static func mark(world: Variant, ent: int, day: int) -> int:
	# `stranger: true` on the recruit tag, and everything that had to learn about strangers reads
	# that one flag: the gate beat (which refuses to fire while any recruit exists) and the dawn
	# leave (which despawns every waiting one). Both are in recruits.gd, both are narrowed to
	# `not stranger`, and `check_m2_strangers.gd`'s GATE BEAT lane holds both halves.
	world.components.set_component(ent, "recruit", {"waiting": true, "stranger": true, "beatDay": day})
	world.components.set_component(ent, "stranger", {
		"state": int(StrangerState.Hiding),
		"sinceTick": int(world.tick),
		# An Array of `{x, y}` records and a generation stamp, which is what `SimWalk.step` owns.
		# Never a Dictionary keyed by anything: a component round-trips through JSON on every save
		# and JSON has no integer keys (CLAUDE.md's trap list).
		"path": [],
		"pathGen": -1,
		# Where they are walking, which is where the colonist was standing when they were last
		# seen -- a remembered point and never a track, the same rule `sightings.gd` keeps.
		"goalX": -1,
		"goalY": -1,
	})
	return ent


## How many strangers are in the district, hiding or walking. Counts the `stranger` component
## rather than the `recruit` one, so a gate recruit at the gate is never mistaken for one.
static func live_count(world: Variant) -> int:
	var n: int = 0
	for e in world.components.query(["stranger"]):
		if world.components.has_component(int(e), "recruit"):
			n += 1
	return n


# --- behaviour ------------------------------------------------------------------------------

static func _tick_behaviour(world: Variant) -> void:
	for e in world.components.query(["stranger", "position", "velocity"]):
		_one(world, int(e))


static func _one(world: Variant, ent: int) -> void:
	var sd: Variant = world.components.get_component(ent, "stranger")
	if not (sd is Dictionary):
		return
	var s: Dictionary = sd as Dictionary
	# Accepted. `SimRecruits.accept` removed the tag, `jobs.gd` owns this body from the next tick,
	# and the `stranger` component has to go with it or this module would keep steering a
	# colonist -- two systems writing one velocity, which is the shape of every AI bug worth
	# having. It is also what `live_count` reads, so leaving it would burn a slot in `LIVE_CAP`
	# forever, the way a raider corpse once burned a slot in the raid cap.
	if not world.components.has_component(ent, "recruit"):
		world.components.remove(ent, "stranger")
		return
	var vel: Variant = world.components.get_component(ent, "velocity")
	if not (vel is Dictionary):
		return
	var body: Variant = world.components.get_component(ent, "body")
	if not (body is Dictionary) or not SimHealthRes.is_alive(body as Dictionary):
		SimWalkRes.halt(vel as Dictionary)
		return
	# On their way out: `recruits._tick_leave` is walking them to the gate and will despawn them.
	# Nothing here touches a body that has given up -- and E still works on them the whole way,
	# because they are still a waiting recruit.
	if world.components.has_component(ent, "leaving"):
		return
	var r: Variant = world.components.get_component(ent, "recruit")
	var beat_day: int = int((r as Dictionary).get("beatDay", 0)) if r is Dictionary else 0
	if Clock.day_number(int(world.tick)) >= beat_day + STRANGER_DAYS:
		SimWalkRes.halt(vel as Dictionary)
		_give_up(world, ent)
		return
	var seen: int = _colonist_in_sight(world, ent)
	if seen >= 0:
		var there: Dictionary = world.components.get_component(seen, "position") as Dictionary
		s["goalX"] = floori(float(there["x"]))
		s["goalY"] = floori(float(there["y"]))
		if int(s.get("state", 0)) != int(StrangerState.Approaching):
			s["state"] = int(StrangerState.Approaching)
			s["sinceTick"] = int(world.tick)
			world.events.publish({"type": "stranger.approaching", "entity": ent, "colonist": seen})
		if _within(world, ent, seen, APPROACH_METRES):
			# Arrived. Standing still in front of somebody is the whole of the ask: E does the
			# rest, and anything more here would be a second acceptance path.
			s["path"] = []
			s["pathGen"] = -1
			SimWalkRes.halt(vel as Dictionary)
			return
	if int(s.get("state", 0)) != int(StrangerState.Approaching):
		# Hiding. No velocity, no path, no shadowcast beyond the one `_colonist_in_sight` asked
		# for -- a body in a house that nobody has walked past costs a query and a look.
		SimWalkRes.halt(vel as Dictionary)
		return
	var goal := Vector2i(int(s.get("goalX", -1)), int(s.get("goalY", -1)))
	if goal.x < 0 or goal.y < 0:
		SimWalkRes.halt(vel as Dictionary)
		return
	# Out of sight, still walking to where they last saw them. The memory is a point and not a
	# track: a stranger who loses you behind a wall walks to where you were, not to where you are.
	SimWalkRes.step(world, ent, s, goal, SPEED)


# The nearest living colonist this stranger can actually see, or -1.
#
# `world.vision.line_of_sight` -- the real sightlines, walls and range, asked of the stranger's own
# eyes (`SimRecruits.spawn_generated` gives every generated body `give_eyes`). Not a distance
# check, and that is the whole reason the APPROACHES lane has a negative: a colonist standing six
# metres away through a wall is six metres away, and a stranger who came out to meet them would be
# seeing through the building they are hiding in.
#
# `line_of_sight` rather than `detail`, and the difference is the facing cone: `detail` asks what
# an observer is *looking at*, and somebody hiding in a house is watching the whole room rather
# than holding a heading. The range is the same either way, and it is the honest one -- it closes
# in at night and in fog, so a stranger notices you across a lit room and not across a dark
# district.
static func _colonist_in_sight(world: Variant, ent: int) -> int:
	if world.vision == null:
		return -1
	var here: Variant = world.components.get_component(ent, "position")
	if not (here is Dictionary):
		return -1
	var hx: float = float((here as Dictionary)["x"])
	var hy: float = float((here as Dictionary)["y"])
	var best: int = -1
	var best_d: float = 1e12
	for other in world.components.query(["needs", "position", "body"]):
		var o: int = int(other)
		if o == ent:
			continue
		# Not another stranger, not a gate recruit, not a corpse: what brings one of these people
		# out of a house is a colonist, and a second stranger in the same building is not one.
		if world.components.has_component(o, "recruit") or world.components.has_component(o, "corpse"):
			continue
		if not SimAllegianceRes.is_colony(world, o):
			continue
		var b: Variant = world.components.get_component(o, "body")
		if not (b is Dictionary) or not SimHealthRes.is_alive(b as Dictionary):
			continue
		var there: Dictionary = world.components.get_component(o, "position") as Dictionary
		var x: float = float(there["x"])
		var y: float = float(there["y"])
		if not bool(world.vision.call("line_of_sight", ent, x, y)):
			continue
		var dx: float = x - hx
		var dy: float = y - hy
		var d: float = dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = o
	return best


static func _within(world: Variant, a: int, b: int, metres: float) -> bool:
	var pa: Variant = world.components.get_component(a, "position")
	var pb: Variant = world.components.get_component(b, "position")
	if not (pa is Dictionary) or not (pb is Dictionary):
		return false
	var dx: float = float((pb as Dictionary)["x"]) - float((pa as Dictionary)["x"])
	var dy: float = float((pb as Dictionary)["y"]) - float((pa as Dictionary)["y"])
	return dx * dx + dy * dy <= metres * metres


# They give up and go, through the machinery a recruit who walks out already uses -- the `leaving`
# component, the walk to the gate, the despawn at the end of it. The one thing that is theirs is
# the reason: `recruits._tick_leave` publishes whatever the record names, and the chronicle says
# nothing over a `stranger`. "The stranger at the gate has gone" is false (they were never at the
# gate) and their name is worse -- the colony would be told about somebody it may never have met,
# which is the certainty clause 4 refuses. What you learn about a stranger is what you saw.
static func _give_up(world: Variant, ent: int) -> void:
	SimRecruitsRes.begin_leave(world, ent)
	var lv: Variant = world.components.get_component(ent, "leaving")
	if lv is Dictionary:
		(lv as Dictionary)["reason"] = "stranger"
