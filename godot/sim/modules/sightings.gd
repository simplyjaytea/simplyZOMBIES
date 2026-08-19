class_name SimSightings
extends RefCounted

# Memory, not deletion. docs/28-visibility-and-sightlines.md#memory-not-deletion:
#
#   "A survivor who watched three bodies walk behind a building does not forget them the instant
#    the wall intervenes, and the game must not act as though they did. Each observer keeps a
#    last-known position for what it has seen, with a sense of how stale it is."
#
# The renderer has had half of this since the top-down pass -- `main.gd` faded a mark where a body
# was last drawn -- but the *simulation* had no memory at all, so an NPC forgot a shambler the
# instant a wall intervened and no prose could say otherwise. This is the sim half, and the
# renderer now reads it rather than keeping a second copy: a mark on screen and a colonist's
# decision are the same recollection or the feature is a lie in one of the two places.
#
# **A record is a position and a tick, never a track.** Nothing in here follows an unseen body.
# The remembered point is where the thing was standing when it was last in view, and it goes stale
# on a clock: docs/01's fairness rules say uncertainty is never a lie, and a marker that moved
# with a body you cannot see would be exactly that.
#
# Storage is an Array of records rather than a Dictionary keyed by entity, because a component
# round-trips through JSON on every save and JSON has no integer keys -- a dictionary would come
# back with String keys and the first `seen[entity]` after a load would silently miss. The arrays
# are short (what one survivor can see at once) and every read is a linear scan.

const SimHealth = preload("res://sim/modules/health.gd")

# Two minutes at 20 Hz. Past this a sighting is not stale, it is gone -- the prose says nothing
# and `recall` refuses, so nothing downstream can act on a memory the survivor no longer has.
const MEMORY_TICKS: int = 2400
# Ten seconds: still where you left it, near enough to act on.
const FRESH_TICKS: int = 200
# A minute: worth mentioning, not worth trusting.
const RECENT_TICKS: int = 1200

enum Freshness { Fresh = 0, Recent = 1, Stale = 2, Forgotten = 3 }

const WHEN_WORDS: Array[String] = ["a moment ago", "a little while ago", "a while ago"]

# Eight points, indexed by (bearing + 22.5 degrees) / 45. +x is east and +y is south, which is the
# screen convention the whole sim uses for position.
const BEARINGS: Array[String] = ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]

# Counting degrades with the memory. A fresh sighting is something you just looked at, so it gets
# a number; anything older gets a hedge, because "three of them, a while ago" claims a precision
# nobody has after a minute of not looking. The hardcore contract's clause 4 forbids handing the
# player certainty they have not earned, and docs/28 asks for prose that "degrades" -- this is
# both, in one table.
const EXACT_WORDS: Array[String] = ["", "one of them", "two of them", "three of them"]
const VAGUE_ONE: String = "one of them"
const VAGUE_FEW: String = "a few of them"
const VAGUE_MANY: String = "several of them"


## Somewhere to keep what this observer has seen. Every survivor gets one; a shambler does not,
## because nothing in docs/14 gives the dead a memory and rule 1 there says sight does not make
## them tactical.
static func attach(world: Variant, entity: int) -> void:
	if world.components.has_component(entity, "sightings"):
		return
	world.components.set_component(entity, "sightings", {"seen": []})


static func register_module(world: Variant) -> void:
	# movement/101: one slot after `kernel.visibility` (movement/100) refreshes the shadowcasts,
	# and before the combat phase reads memory to decide where to shoot. Observing on stale views
	# would remember a body one tick after it stepped behind the wall, which is the exact error
	# this module exists to avoid making in the other direction.
	world.systems.register("sightings.observe", "movement", 101, func(w: Variant) -> void:
		observe(w)
	)


static func observe(world: Variant) -> void:
	if world.vision == null:
		return
	var hostiles: Array = []
	for other in world.components.query(["shambler", "position"]):
		hostiles.append(int(other))
	for ent in world.components.query(["sightings", "observer", "position"]):
		_observe_one(world, int(ent), hostiles)


static func _observe_one(world: Variant, observer: int, hostiles: Array) -> void:
	var comp: Variant = world.components.get_component(observer, "sightings")
	if not comp is Dictionary:
		return
	var seen: Array = (comp as Dictionary)["seen"] as Array
	var tick: int = int(world.tick)
	for other in hostiles:
		var there: Variant = world.components.get_component(int(other), "position")
		if not there is Dictionary:
			continue
		var x: float = float((there as Dictionary)["x"])
		var y: float = float((there as Dictionary)["y"])
		if not bool(world.vision.call("line_of_sight", observer, x, y)):
			continue
		# Watched it fall. A body you saw go down is not a body you are still wary of, so the
		# record goes rather than ageing out -- and a kill out of sight leaves its record
		# standing, which is the same asymmetry as everything else here.
		var body: Variant = world.components.get_component(int(other), "body")
		if not body is Dictionary or not SimHealth.is_alive(body as Dictionary):
			_erase(seen, int(other))
			continue
		_record(seen, int(other), x, y, tick)
	_prune(seen, tick)


static func _record(seen: Array, entity: int, x: float, y: float, tick: int) -> void:
	for row in seen:
		if int((row as Dictionary)["e"]) == entity:
			(row as Dictionary)["x"] = x
			(row as Dictionary)["y"] = y
			(row as Dictionary)["tick"] = tick
			return
	seen.append({"e": entity, "x": x, "y": y, "tick": tick})


static func _erase(seen: Array, entity: int) -> void:
	for i in range(seen.size() - 1, -1, -1):
		if int((seen[i] as Dictionary)["e"]) == entity:
			seen.remove_at(i)


static func _prune(seen: Array, tick: int) -> void:
	for i in range(seen.size() - 1, -1, -1):
		if tick - int((seen[i] as Dictionary)["tick"]) > MEMORY_TICKS:
			seen.remove_at(i)


## Everything this observer still remembers, freshest first, with an `age` in ticks. Forgotten
## records never appear -- the horizon is enforced here as well as in the tick, so a read taken
## before the next `observe` cannot see past it either.
static func remembered(world: Variant, observer: int) -> Array:
	var comp: Variant = world.components.get_component(observer, "sightings")
	if not comp is Dictionary:
		return []
	var tick: int = int(world.tick)
	var out: Array = []
	for row in (comp as Dictionary)["seen"] as Array:
		var age: int = tick - int((row as Dictionary)["tick"])
		if age < 0 or age > MEMORY_TICKS:
			continue
		out.append({
			"entity": int((row as Dictionary)["e"]),
			"x": float((row as Dictionary)["x"]),
			"y": float((row as Dictionary)["y"]),
			"tick": int((row as Dictionary)["tick"]),
			"age": age,
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["age"]) < int(b["age"]))
	return out


## What this observer remembers about one body, or null. Same horizon as `remembered`.
static func recall(world: Variant, observer: int, entity: int) -> Variant:
	for row in remembered(world, observer):
		if int((row as Dictionary)["entity"]) == entity:
			return row
	return null


## The freshest thing remembered within `metres` of where the observer is standing now, or null.
## What an NPC shoots at when it has lost sight of everything -- see npc_combat.gd.
static func freshest_within(world: Variant, observer: int, metres: float) -> Variant:
	var here: Variant = world.components.get_component(observer, "position")
	if not here is Dictionary or metres <= 0.0:
		return null
	var hx: float = float((here as Dictionary)["x"])
	var hy: float = float((here as Dictionary)["y"])
	var limit_sq: float = metres * metres
	for row in remembered(world, observer):
		var dx: float = float((row as Dictionary)["x"]) - hx
		var dy: float = float((row as Dictionary)["y"]) - hy
		if dx * dx + dy * dy <= limit_sq:
			return row
	return null


static func freshness(age: int) -> int:
	if age < 0 or age > MEMORY_TICKS:
		return Freshness.Forgotten
	if age <= FRESH_TICKS:
		return Freshness.Fresh
	if age <= RECENT_TICKS:
		return Freshness.Recent
	return Freshness.Stale


static func bearing_word(dx: float, dy: float) -> String:
	if dx == 0.0 and dy == 0.0:
		return "right here"
	var degrees: float = rad_to_deg(atan2(dy, dx))
	if degrees < 0.0:
		degrees += 360.0
	return BEARINGS[int(floor((degrees + 22.5) / 45.0)) % 8]


static func count_word(n: int, fresh: bool) -> String:
	if n <= 0:
		return ""
	if fresh and n < EXACT_WORDS.size():
		return EXACT_WORDS[n]
	if n == 1:
		return VAGUE_ONE
	if n <= 4:
		return VAGUE_FEW
	return VAGUE_MANY


## One line for the HUD, or "" when this survivor is not carrying anything worth saying.
##
## Built off the freshest record and everything remembered in the same direction from it, so the
## sentence describes one group rather than summing the district: "two of them, north-east, a
## moment ago". No distance, because a remembered distance is exactly the kind of precision
## clause 4 refuses -- a bearing is what somebody would actually say.
static func clause(world: Variant, observer: int) -> String:
	var rows: Array = remembered(world, observer)
	if rows.is_empty():
		return ""
	var here: Variant = world.components.get_component(observer, "position")
	if not here is Dictionary:
		return ""
	var hx: float = float((here as Dictionary)["x"])
	var hy: float = float((here as Dictionary)["y"])
	var lead: Dictionary = rows[0] as Dictionary
	var bearing: String = bearing_word(float(lead["x"]) - hx, float(lead["y"]) - hy)
	var n: int = 0
	for row in rows:
		if bearing_word(float((row as Dictionary)["x"]) - hx, float((row as Dictionary)["y"]) - hy) == bearing:
			n += 1
	var band: int = freshness(int(lead["age"]))
	if band == Freshness.Forgotten:
		return ""
	var count: String = count_word(n, band == Freshness.Fresh)
	if count.is_empty():
		return ""
	return "%s, %s, %s" % [count, bearing, WHEN_WORDS[band]]
