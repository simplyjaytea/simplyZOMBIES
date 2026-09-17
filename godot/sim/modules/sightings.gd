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
#
# **Everybody is remembered, with a kind.** A record used to hold only a shambler; every body with
# a `body` and a `position` other than the observer now qualifies, and each carries a `kind` --
# "zombie", "raider" or "person" -- so a colonist glimpsed behind a wall is a memory too, and the
# renderer's afterimage (main.gd's `_draw_afterimages`) has something to draw for it. A record read
# back without a `kind` (an older save) is "zombie", the value every row carried before this slice.
# `clause()` and `freshest_within()` narrow to the hostile kinds on purpose: nobody shoots at where
# Mara was standing, and the HUD does not warn about her either.
#
# **The remembered map.** A second, per-observer component, `explored` -- a base64 bitset over
# `map.w x map.h`, one bit per tile ever inside this observer's shadowcast. It is merged from the
# shadowcast's own `VisibleTiles` only on the tick that cast actually recomputes
# (`SimVisibility.cast_generation`), never every tick, so a body standing still costs this module
# nothing extra. `main.gd`'s tile loop reads it through `explored_view` to draw a dimmed street
# outside the current cone -- the remembered map docs/23 named, wired to the same clock as
# everything else in this file.

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

# Kinds a record can carry. A record with no `kind` at all (a save from before this slice) reads
# as this default -- the only kind that ever existed then.
const DEFAULT_KIND: String = "zombie"
# What the prose and the recall-fire job are willing to act on. A remembered colonist is not a
# threat, so "person" never reaches either.
const HOSTILE_KINDS: Array[String] = ["zombie", "raider"]


## A per-observer's remembered map, decoded once per read: `has_tile` duck-types the same call
## `main.gd` already makes on a shadowcast's own `VisibleTiles`. Bytes rather than a live reference
## into the component -- a caller that mutates this cannot corrupt the saved bitset by accident.
class ExploredView extends RefCounted:
	var w: int = 0
	var h: int = 0
	var bytes: PackedByteArray = PackedByteArray()

	func has_tile(tx: int, ty: int) -> bool:
		if tx < 0 or ty < 0 or tx >= w or ty >= h:
			return false
		var bit: int = ty * w + tx
		var byte_i: int = bit / 8
		if byte_i < 0 or byte_i >= bytes.size():
			return false
		return (bytes[byte_i] & (1 << (bit % 8))) != 0


## Somewhere to keep what this observer has seen. Every survivor gets one; a shambler does not,
## because nothing in docs/14 gives the dead a memory and rule 1 there says sight does not make
## them tactical.
static func attach(world: Variant, entity: int) -> void:
	if not world.components.has_component(entity, "sightings"):
		# `containers` is the same shape as `seen`: an Array of `{e, x, y}` records, never a dict
		# keyed by entity id (a save turns those keys into Strings). It is what a survivor
		# remembers of the cupboards they have looked at, and what the Scavenge job searches from.
		world.components.set_component(entity, "sightings", {"seen": [], "containers": []})
	_ensure_explored(world, entity)


## The `explored` component, sized to the map: a zeroed bitset the first time, kept as-is on a
## repeat call so a mid-run observe never wipes what has already been walked. A world with no
## tilemap yet (attach can run before `SimBoot.attach_kernel`, in a hand-built fixture) leaves this
## for the next call -- `observe`'s own merge step calls it again every tick until it takes.
static func _ensure_explored(world: Variant, entity: int) -> void:
	if world.tilemap == null:
		return
	var w: int = int(world.tilemap.w)
	var h: int = int(world.tilemap.h)
	if w <= 0 or h <= 0:
		return
	var existing: Variant = world.components.get_component(entity, "explored")
	if existing is Dictionary and int((existing as Dictionary).get("w", -1)) == w and int((existing as Dictionary).get("h", -1)) == h:
		return
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize((w * h + 7) / 8)
	world.components.set_component(entity, "explored", {"w": w, "h": h, "bits": Marshalls.raw_to_base64(bytes)})


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
	# Every body, not only the dead: a colonist glimpsed behind a wall is a memory too, and
	# `_kind_of` is what tells the prose and the recall-fire job apart from a threat.
	var candidates: Array = []
	for other in world.components.query(["body", "position"]):
		candidates.append(int(other))
	var boxes: Array = []
	for box in world.components.query(["searchable", "position"]):
		boxes.append(int(box))
	for ent in world.components.query(["sightings", "observer", "position"]):
		_observe_one(world, int(ent), candidates)
		_observe_containers(world, int(ent), boxes)
		_merge_explored(world, int(ent))


static func _kind_of(world: Variant, entity: int) -> String:
	if world.components.has_component(entity, "shambler"):
		return "zombie"
	if world.components.has_component(entity, "raider"):
		return "raider"
	return "person"


# A container is remembered when it is *seen* -- `detail`, not `line_of_sight`, so the 170-degree
# arc behind a survivor does not fill their memory the way it (wrongly, docs/23's defect list)
# fills `seen`. A searched container is forgotten: there is nothing left to go back for.
static func _observe_containers(world: Variant, observer: int, boxes: Array) -> void:
	var comp: Variant = world.components.get_component(observer, "sightings")
	if not comp is Dictionary:
		return
	if not (comp as Dictionary).has("containers"):
		(comp as Dictionary)["containers"] = []
	var known: Array = (comp as Dictionary)["containers"] as Array
	for box in boxes:
		var s: Variant = world.components.get_component(int(box), "searchable")
		if not s is Dictionary:
			continue
		if bool((s as Dictionary).get("searched", false)):
			_erase(known, int(box))
			continue
		var there: Variant = world.components.get_component(int(box), "position")
		if not there is Dictionary:
			continue
		var x: float = float((there as Dictionary)["x"])
		var y: float = float((there as Dictionary)["y"])
		# 0 is `SimVisibility.Detail.Unseen`; the literal because this module cannot name that
		# class at parse time (the shambler reads it the same way, `== 0`).
		if int(world.vision.call("detail", observer, x, y)) == 0:
			continue
		var found: bool = false
		for row in known:
			if int((row as Dictionary)["e"]) == int(box):
				found = true
				break
		if not found:
			known.append({"e": int(box), "x": x, "y": y})


## The containers this survivor remembers and has not seen searched, as `{e, x, y}` records.
static func known_containers(world: Variant, entity: int) -> Array:
	var comp: Variant = world.components.get_component(entity, "sightings")
	if not comp is Dictionary:
		return []
	var known: Variant = (comp as Dictionary).get("containers", [])
	return known as Array if known is Array else []


static func _observe_one(world: Variant, observer: int, candidates: Array) -> void:
	var comp: Variant = world.components.get_component(observer, "sightings")
	if not comp is Dictionary:
		return
	var seen: Array = (comp as Dictionary)["seen"] as Array
	var tick: int = int(world.tick)
	for other in candidates:
		if int(other) == observer:
			continue
		var there: Variant = world.components.get_component(int(other), "position")
		if not there is Dictionary:
			continue
		var x: float = float((there as Dictionary)["x"])
		var y: float = float((there as Dictionary)["y"])
		# `detail`, not `line_of_sight` -- the same fix `_observe_containers` above already made,
		# and docs/23's defect list named this call as the one spot that hadn't (2026-09-16). A
		# survivor's field of view is a focal/peripheral cone, not the raw 360-degree shadowcast:
		# `line_of_sight` only asks about walls and range, so a hostile standing in the 170-degree
		# arc behind the observer's facing was being recorded, remembered, and reported on the HUD
		# -- information the hardcore contract's clause 4 says the player has not earned.
		# 0 is `SimVisibility.Detail.Unseen`; the literal because this module cannot name that
		# class at parse time (`_observe_containers` above reads it the same way).
		if int(world.vision.call("detail", observer, x, y)) == 0:
			continue
		# Watched it fall. A body you saw go down is not a body you are still wary of, so the
		# record goes rather than ageing out -- and a kill out of sight leaves its record
		# standing, which is the same asymmetry as everything else here.
		var body: Variant = world.components.get_component(int(other), "body")
		if not body is Dictionary or not SimHealth.is_alive(body as Dictionary):
			_erase(seen, int(other))
			continue
		_record(seen, int(other), x, y, tick, _kind_of(world, int(other)))
	_prune(seen, tick)


static func _record(seen: Array, entity: int, x: float, y: float, tick: int, kind: String) -> void:
	for row in seen:
		if int((row as Dictionary)["e"]) == entity:
			(row as Dictionary)["x"] = x
			(row as Dictionary)["y"] = y
			(row as Dictionary)["tick"] = tick
			(row as Dictionary)["kind"] = kind
			return
	seen.append({"e": entity, "x": x, "y": y, "tick": tick, "kind": kind})


# Paid for only on the tick this observer's shadowcast actually recomputed -- `cast_generation`
# is the same counter `SimVisibility.refresh` bumps, so a body standing still (or one whose cast
# has not moved far enough to redo the geometry) costs this nothing: no decode, no re-encode. The
# generation an observer last merged lives on its own `sightings` record (`exploredGen`) rather
# than in a static var, which the kernel-attach trap (docs/30, CLAUDE.md) rules out for anything
# meant to survive between the worlds one gate process boots.
static func _merge_explored(world: Variant, observer: int) -> void:
	if world.vision == null or world.tilemap == null:
		return
	var gen: int = int(world.vision.cast_generation(observer))
	if gen < 0:
		return
	var sc: Variant = world.components.get_component(observer, "sightings")
	if not sc is Dictionary:
		return
	var scd: Dictionary = sc as Dictionary
	if int(scd.get("exploredGen", -1)) == gen:
		return
	_ensure_explored(world, observer)
	var comp: Variant = world.components.get_component(observer, "explored")
	if not comp is Dictionary:
		scd["exploredGen"] = gen
		return
	var ec: Dictionary = comp as Dictionary
	var w: int = int(ec["w"])
	var h: int = int(ec["h"])
	var tiles: Variant = world.vision.tiles_for(observer)
	if tiles == null:
		scd["exploredGen"] = gen
		return
	var bytes: PackedByteArray = Marshalls.base64_to_raw(String(ec["bits"]))
	var origin_x: int = int(tiles.origin_x)
	var origin_y: int = int(tiles.origin_y)
	var range_tiles: int = int(tiles.range_tiles)
	var size: int = int(tiles.size)
	var cells: PackedByteArray = tiles.cells
	var changed: bool = false
	for dy in size:
		var ty: int = origin_y - range_tiles + dy
		if ty < 0 or ty >= h:
			continue
		var row: int = dy * size
		for dx in size:
			if cells[row + dx] != 1:
				continue
			var tx: int = origin_x - range_tiles + dx
			if tx < 0 or tx >= w:
				continue
			var bit: int = ty * w + tx
			var byte_i: int = bit / 8
			var mask: int = 1 << (bit % 8)
			if (bytes[byte_i] & mask) == 0:
				bytes[byte_i] |= mask
				changed = true
	if changed:
		ec["bits"] = Marshalls.raw_to_base64(bytes)
	scd["exploredGen"] = gen


## This observer's remembered map, or null when it has none yet (no tilemap, or never observed).
## `has_tile` duck-types the shadowcast's own `VisibleTiles`, which is what lets `main.gd` hand
## either one to the same drawing code.
static func explored_view(world: Variant, entity: int) -> Variant:
	var comp: Variant = world.components.get_component(entity, "explored")
	if not comp is Dictionary:
		return null
	var ec: Dictionary = comp as Dictionary
	var view: ExploredView = ExploredView.new()
	view.w = int(ec.get("w", 0))
	view.h = int(ec.get("h", 0))
	view.bytes = Marshalls.base64_to_raw(String(ec.get("bits", "")))
	return view


static func knows_tile(world: Variant, entity: int, tx: int, ty: int) -> bool:
	var view: Variant = explored_view(world, entity)
	if view == null:
		return false
	return bool((view as ExploredView).has_tile(tx, ty))


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
## before the next `observe` cannot see past it either. `kinds` narrows to those kinds alone; the
## default, empty, is everybody -- what the renderer's afterimage asks with, since a colonist's
## afterimage is exactly as real as a zombie's.
static func remembered(world: Variant, observer: int, kinds: Array[String] = []) -> Array:
	var comp: Variant = world.components.get_component(observer, "sightings")
	if not comp is Dictionary:
		return []
	var tick: int = int(world.tick)
	var out: Array = []
	for row in (comp as Dictionary)["seen"] as Array:
		var age: int = tick - int((row as Dictionary)["tick"])
		if age < 0 or age > MEMORY_TICKS:
			continue
		var kind: String = String((row as Dictionary).get("kind", DEFAULT_KIND))
		if not kinds.is_empty() and not kinds.has(kind):
			continue
		out.append({
			"entity": int((row as Dictionary)["e"]),
			"x": float((row as Dictionary)["x"]),
			"y": float((row as Dictionary)["y"]),
			"tick": int((row as Dictionary)["tick"]),
			"age": age,
			"kind": kind,
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["age"]) < int(b["age"]))
	return out


## What this observer remembers about one body, or null. Same horizon as `remembered`.
static func recall(world: Variant, observer: int, entity: int) -> Variant:
	for row in remembered(world, observer):
		if int((row as Dictionary)["entity"]) == entity:
			return row
	return null


## The freshest *hostile* thing remembered within `metres` of where the observer is standing now,
## or null -- a remembered colonist never qualifies. What an NPC shoots at when it has lost sight
## of everything -- see npc_combat.gd.
static func freshest_within(world: Variant, observer: int, metres: float) -> Variant:
	var here: Variant = world.components.get_component(observer, "position")
	if not here is Dictionary or metres <= 0.0:
		return null
	var hx: float = float((here as Dictionary)["x"])
	var hy: float = float((here as Dictionary)["y"])
	var limit_sq: float = metres * metres
	for row in remembered(world, observer, HOSTILE_KINDS):
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
## clause 4 refuses -- a bearing is what somebody would actually say. Hostile kinds only: a
## remembered colonist never becomes "one of them".
static func clause(world: Variant, observer: int) -> String:
	var rows: Array = remembered(world, observer, HOSTILE_KINDS)
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
