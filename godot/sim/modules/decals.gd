extends RefCounted
# Decals: the marks a fight leaves behind (plan item A13; docs/30, "Blood and bullet decals
# persist, for everything").
#
# The owner's call of 2026-10-19: **every** bleed, hit and shot leaves a mark, whether or not the
# player saw it happen, and the mark is kept for the run. What the player is allowed to *know*
# is the renderer's question, not this file's: presentation/decal_look.gd draws a mark only on a
# tile the player sees right now, the same rule a floor tile is drawn by, so a mark made behind
# a wall exists here and shows nothing until the player walks round and looks. That split is
# the whole design. This file never reads the player's sight and never asks who was watching.
#
# **What leaves a mark**, one subscription per event kind (kept small on purpose -- several
# open branches touch the modules these events come from):
#   attack.connected  a splat on the ground just past the struck body, thrown away from the
#                     attacker (`splat`)
#   bite.landed       the same splat, under the bitten body
#   entity.killed     a pool under the body, once per body however often the event fires for it
#                     (CLAUDE.md's trap list: it fires up to three times for one death) (`pool`)
#   weapon.fired      a round that hit nobody flies on along the shooter's facing to its reach;
#                     the first wall, tree, shut door, boarded window or parked car in its path
#                     takes a hole (`hole`, `chips` for timber, `dent` for a car's metal)
#   weather.lightning a scorch where the bolt came down (`scorch`), the one fire the sim places
#                     on the ground today -- a campfire is a pit whose own picture is its char
# and one system, `decals.drip`, that reads `injuries.bloodLoss` (the number wounds.bleed already
# keeps) and drops a drip every DRIP_LOSS of it, so a deep wound leaves a trail a scratch does not.
# A drip landing on an earlier one pools into it (`s` grows); a body crawling while it bleeds
# leaves a `smear` from its last drop to this one instead of a drop.
#
# **Shape: chunked records, never an id-keyed Dictionary.** `world.decals` maps a chunk key
# ("cx:cy", a String -- JSON keeps String keys, it is integer keys that come back wrong) to
# `{rev, d}`: `d` an Array of records in the order they landed, `rev` bumped on every change so a
# renderer that baked the chunk knows to bake it again. A record is
#   {k: kind, x, y: position in art pixels (1/32 m, ints so a save round-trips exactly),
#    t: tick it landed, v: variant 0..63 (low three bits the turn, the rest the picture), s: size 1..4,
#    e: the body a pool belongs to (-1 otherwise), a, b: a smear's run in art pixels}
# CHUNK matches the world bake's chunk (presentation/world_layers.gd), so one new mark is one
# chunk to rebake. PER_CHUNK bounds what any one chunk can hold -- the draw cost of a chunk is
# bounded by it, which is what keeps a long siege inside the frame budget -- and the oldest mark
# that is not a pool goes first, because the pool under a body is the mark that says who died.
#
# Randomness (where a splat lands, which way a picture turns) comes off its own named stream,
# `decals`, so adding marks moves no other stream a gate or the balance harness is pinned to.

const Clock = preload("res://sim/time/clock.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimStances = preload("res://sim/stances.gd")

const ART_PX: int = 32
const CHUNK: int = 8
const PER_CHUNK: int = 32
# The whole run's bound: a save never carries more marks than this. Over it, the fullest chunk
# gives up its oldest mark that is not a pool.
const MAX_TOTAL: int = 6000
const KINDS: Array[String] = ["splat", "drip", "smear", "pool", "hole", "chips", "dent", "scorch"]

# Blood lost per drip. wounds.gd's BLEED_PER_TICK is 0.02 for a deep wound, 0.004 for a
# laceration and 0.0006 for a scratch, so this is a drop every 1.25 s, every 6 s and every 42 s
# respectively -- a deep wound leaves a trail, a scratch leaves a drop or two before it clots.
const DRIP_LOSS: float = 0.5
const DRIP_EVERY: int = 5
# A drop this close to an earlier drip pools into it rather than starting a new mark (art px).
const POOL_MERGE_PX: int = 10
# A crawling bleeder whose last drop is between these is dragged, not dripping: a smear joins the
# two. Farther than SMEAR_MAX_PX is a body that was moved, not dragged.
const SMEAR_MIN_PX: int = 10
const SMEAR_MAX_PX: int = 48
# How far past a struck body its splat is thrown, in metres.
const SPLAT_MIN_M: float = 0.15
const SPLAT_MAX_M: float = 0.55
# The step a stray round's path is walked in, in metres.
const RAY_STEP_M: float = 0.125
# Subscription order: after health.gd has written the blow (so a killed body is already a corpse)
# and before the chronicle, which reads names rather than places.
const ORDER: int = 800
const STREAM: String = "decals"


static func register_module(world: Variant) -> void:
	world.events.subscribe({"type": "attack.connected", "id": "decals.hit", "order": ORDER, "handler": func(ev: Dictionary) -> void:
		_on_struck(world, int(ev.get("target", -1)), int(ev.get("attacker", -1)))
	})
	world.events.subscribe({"type": "bite.landed", "id": "decals.bite", "order": ORDER, "handler": func(ev: Dictionary) -> void:
		_on_struck(world, int(ev.get("victim", -1)), -1)
	})
	world.events.subscribe({"type": "entity.killed", "id": "decals.killed", "order": ORDER, "handler": func(ev: Dictionary) -> void:
		_on_killed(world, ev)
	})
	world.events.subscribe({"type": "weapon.fired", "id": "decals.round", "order": ORDER, "handler": func(ev: Dictionary) -> void:
		_on_round(world, ev)
	})
	world.events.subscribe({"type": "weather.lightning", "id": "decals.lightning", "order": ORDER, "handler": func(ev: Dictionary) -> void:
		if ev.has("x") and ev.has("y"):
			add(world, "scorch", float(ev["x"]), float(ev["y"]))
	})
	world.systems.register("decals.drip", "health", 5, func(w: Variant) -> void:
		if int(w.tick) % DRIP_EVERY == 0:
			_drip(w)
	)


# --- the record -----------------------------------------------------------------------------

static func chunk_key(cx: int, cy: int) -> String:
	return "%d:%d" % [cx, cy]


static func chunk_of_px(x: int, y: int) -> Vector2i:
	return Vector2i(floori(float(x) / float(CHUNK * ART_PX)), floori(float(y) / float(CHUNK * ART_PX)))


# The records in one chunk, oldest first. Empty for a chunk nothing has marked.
static func in_chunk(world: Variant, cx: int, cy: int) -> Array:
	var c: Variant = (world.decals as Dictionary).get(chunk_key(cx, cy))
	return (c as Dictionary)["d"] as Array if c is Dictionary else []


# A chunk's revision: 0 for one nothing has ever marked, and different after every change.
static func rev_of(world: Variant, cx: int, cy: int) -> int:
	var c: Variant = (world.decals as Dictionary).get(chunk_key(cx, cy))
	return int((c as Dictionary)["rev"]) if c is Dictionary else 0


static func count(world: Variant) -> int:
	var n: int = 0
	for c in (world.decals as Dictionary).values():
		n += ((c as Dictionary)["d"] as Array).size()
	return n


# Leaves one mark at (x, y) metres and returns its record, or {} when there is nowhere to put it
# (off the map, or a kind this file does not know). `extra` may carry `e`, `s`, `a`, `b`.
static func add(world: Variant, kind: String, x: float, y: float, extra: Dictionary = {}) -> Dictionary:
	if not KINDS.has(kind) or not is_finite(x) or not is_finite(y):
		return {}
	if x < 0.0 or y < 0.0 or x >= float(world.map_width) or y >= float(world.map_height):
		return {}
	var rng: Variant = world.rng.stream(STREAM)
	var px: int = roundi(x * ART_PX)
	var py: int = roundi(y * ART_PX)
	var rec: Dictionary = {
		"k": kind, "x": px, "y": py, "t": int(world.tick),
		"v": int(rng.call("int_range", 0, 63)),
		"s": clampi(int(extra.get("s", 1)), 1, 4),
		"e": int(extra.get("e", -1)),
	}
	if kind == "smear":
		rec["a"] = int(extra.get("a", 0))
		rec["b"] = int(extra.get("b", 0))
	var ch: Vector2i = chunk_of_px(px, py)
	var key: String = chunk_key(ch.x, ch.y)
	var all: Dictionary = world.decals as Dictionary
	if not all.has(key):
		all[key] = {"rev": 0, "d": []}
	var c: Dictionary = all[key] as Dictionary
	var d: Array = c["d"] as Array
	d.append(rec)
	while d.size() > PER_CHUNK:
		_evict_one(d)
	_touch(world, c)
	# Counting is a walk over every chunk, so it is only asked once enough chunks exist that the
	# bound could be passed at all; a run that has marked fewer than MAX_TOTAL / PER_CHUNK chunks
	# never pays for it.
	if all.size() * PER_CHUNK > MAX_TOTAL and count(world) > MAX_TOTAL:
		_evict_fullest(world)
	return rec


# Drops the oldest mark that is not a pool, or the oldest of all when every one is a pool. By
# index, never `erase` -- erase matches Dictionaries by value (CLAUDE.md's trap list).
static func _evict_one(d: Array) -> void:
	for i in d.size():
		if String((d[i] as Dictionary)["k"]) != "pool":
			d.remove_at(i)
			return
	d.remove_at(0)


static func _evict_fullest(world: Variant) -> void:
	var best: String = ""
	var most: int = -1
	for key in (world.decals as Dictionary).keys():
		var n: int = (((world.decals as Dictionary)[key] as Dictionary)["d"] as Array).size()
		if n > most:
			most = n
			best = String(key)
	if best.is_empty():
		return
	var c: Dictionary = (world.decals as Dictionary)[best] as Dictionary
	_evict_one(c["d"] as Array)
	_touch(world, c)


# Every change to a chunk bumps its revision and the world's.
static func _touch(world: Variant, c: Dictionary) -> void:
	c["rev"] = int(c["rev"]) + 1
	world.decals_rev = int(world.decals_rev) + 1


# --- the sources ----------------------------------------------------------------------------

static func _pos(world: Variant, entity: int) -> Variant:
	if entity < 0:
		return null
	var p: Variant = world.components.get_component(entity, "position")
	if not (p is Dictionary):
		return null
	return Vector2(float((p as Dictionary)["x"]), float((p as Dictionary)["y"]))


# A blow landed: the blood goes on the ground just past the body, thrown along the line from the
# attacker (straight down where there is no attacker to throw it from), and never into a wall --
# a splat that would land on a solid tile lands under the body instead.
static func _on_struck(world: Variant, target: int, attacker: int) -> void:
	var at: Variant = _pos(world, target)
	if at == null:
		return
	var rng: Variant = world.rng.stream(STREAM)
	var dir := Vector2(float(rng.call("float_range", -1.0, 1.0)), float(rng.call("float_range", -1.0, 1.0)))
	var from: Variant = _pos(world, attacker)
	if from != null and (at as Vector2).distance_squared_to(from as Vector2) > 0.0001:
		dir = ((at as Vector2) - (from as Vector2)).normalized()
	elif dir.length_squared() > 0.0001:
		dir = dir.normalized()
	var throw: float = float(rng.call("float_range", SPLAT_MIN_M, SPLAT_MAX_M))
	var land: Vector2 = (at as Vector2) + dir * throw
	if world.tilemap != null and SimTileMap.is_solid(world.tilemap, floori(land.x), floori(land.y)):
		land = at as Vector2
	add(world, "splat", land.x, land.y)


static func _on_killed(world: Variant, ev: Dictionary) -> void:
	var entity: int = int(ev.get("entity", -1))
	var at: Variant = null
	if ev.has("x") and ev.has("y") and (float(ev["x"]) != 0.0 or float(ev["y"]) != 0.0):
		at = Vector2(float(ev["x"]), float(ev["y"]))
	else:
		at = _pos(world, entity)
	if at == null:
		return
	if entity >= 0 and has_pool_of(world, entity, at as Vector2):
		return
	add(world, "pool", (at as Vector2).x, (at as Vector2).y, {"e": entity, "s": 4})


# Whether a body already has its pool. A body's pool lies within a step of where it fell, so the
# chunks round that point are the only ones asked -- the record is never scanned whole.
static func has_pool_of(world: Variant, entity: int, near: Vector2) -> bool:
	var ch: Vector2i = chunk_of_px(roundi(near.x * ART_PX), roundi(near.y * ART_PX))
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			for r in in_chunk(world, ch.x + ox, ch.y + oy):
				if int((r as Dictionary)["e"]) == entity and String((r as Dictionary)["k"]) == "pool":
					return true
	return false


# A round that found no body. ranged.gd says where it left the muzzle, which way it went, how far
# it carries and whether it hit; this walks that line and marks the first thing that stops it.
static func _on_round(world: Variant, ev: Dictionary) -> void:
	if int(ev.get("hit", -1)) >= 0 or not ev.has("dx") or world.tilemap == null:
		return
	var o := Vector2(float(ev.get("x", 0.0)), float(ev.get("y", 0.0)))
	var d := Vector2(float(ev.get("dx", 0.0)), float(ev.get("dy", 0.0)))
	if d.length_squared() < 0.0001:
		return
	d = d.normalized()
	var stop: Dictionary = stopped_by(world, o, d, float(ev.get("reach", 0.0)))
	if not stop.is_empty():
		add(world, String(stop["kind"]), float(stop["x"]), float(stop["y"]))


# Where a round from `o` along `d` stops within `reach` metres, as {kind, x, y, tx, ty}, or {} if
# it carries its whole reach. The point is just inside the tile it struck. Glass, a screen, a
# heap of low cover and water do not stop it; the shooter's own tile is never the target.
static func stopped_by(world: Variant, o: Vector2, d: Vector2, reach: float) -> Dictionary:
	var map: Variant = world.tilemap
	var start := Vector2i(floori(o.x), floori(o.y))
	var steps: int = int(ceil(reach / RAY_STEP_M))
	var last := Vector2i(-1, -1)
	for i in range(1, steps + 1):
		var p: Vector2 = o + d * (float(i) * RAY_STEP_M)
		var t := Vector2i(floori(p.x), floori(p.y))
		if t == last or t == start:
			continue
		last = t
		if t.x < 0 or t.y < 0 or t.x >= int(map.w) or t.y >= int(map.h):
			return {}
		var kind: String = surface_of(world, t.x, t.y)
		if kind.is_empty():
			continue
		return {"kind": kind, "x": p.x, "y": p.y, "tx": t.x, "ty": t.y}
	return {}


# What a tile is made of, as the mark a round leaves in it: "" for a tile a round passes.
static func surface_of(world: Variant, tx: int, ty: int) -> String:
	var map: Variant = world.tilemap
	var tile: int = SimTileMap.tile_at(map, tx, ty)
	var ov: Variant = SimTileMap.overlay_at(map, tx, ty)
	var ov_kind: String = String((ov as Dictionary).get("kind", "")) if ov is Dictionary else ""
	if ov_kind == "board" and int((ov as Dictionary).get("stage", 0)) < 3:
		return "chips"
	if ov_kind == "scrap":
		return "dent"
	# The raised walls take the round themselves, so the mark is on them and not on what is behind:
	# timber chips like a board, a stone course is holed like a wall. A wire fence is not here, the
	# same as glass: it stops a body and a round goes through it.
	if ov_kind == "timber":
		return "chips"
	if ov_kind == "stone":
		return "hole"
	match tile:
		SimTileMap.Tile.Wall:
			return "hole"
		SimTileMap.Tile.Tree:
			return "chips"
		SimTileMap.Tile.Door:
			if ov_kind == "door" and not bool((ov as Dictionary).get("open", false)):
				return "chips"
		SimTileMap.Tile.Low:
			if _car_covers(map, tx, ty):
				return "dent"
	return ""


static func _car_covers(map: Variant, tx: int, ty: int) -> bool:
	for v in map.vehicles:
		var r := Rect2i(int((v as Dictionary).get("x", 0)), int((v as Dictionary).get("y", 0)), int((v as Dictionary).get("w", 0)), int((v as Dictionary).get("h", 0)))
		if r.has_point(Vector2i(tx, ty)):
			return true
	return false


# Every body losing blood drops a drip for every DRIP_LOSS it has lost since its last one. The
# body's own trail record (`bloodTrail`: the loss at its last drop, and where that drop was) is a
# component, so it rides the save with the body.
static func _drip(world: Variant) -> void:
	for ent in world.components.query(["injuries", "position"]):
		var e: int = int(ent)
		if world.components.has_component(e, "corpse"):
			continue
		var inj: Dictionary = world.components.get_component(e, "injuries") as Dictionary
		var loss: float = float(inj.get("bloodLoss", 0.0))
		var trail: Variant = world.components.get_component(e, "bloodTrail")
		if not (trail is Dictionary):
			if loss < DRIP_LOSS:
				continue
			trail = {"at": 0.0, "x": -1, "y": -1}
			world.components.set_component(e, "bloodTrail", trail)
		var tr: Dictionary = trail as Dictionary
		if loss < float(tr["at"]):
			# Blood came back (a transfusion, a save edited by hand): the trail starts again here.
			tr["at"] = loss
			continue
		if loss - float(tr["at"]) < DRIP_LOSS:
			continue
		tr["at"] = float(tr["at"]) + DRIP_LOSS * floorf((loss - float(tr["at"])) / DRIP_LOSS)
		var at: Vector2 = _pos(world, e) as Vector2
		_drop(world, e, at, tr)


static func _drop(world: Variant, entity: int, at: Vector2, tr: Dictionary) -> void:
	var rng: Variant = world.rng.stream(STREAM)
	var here := Vector2(at.x + float(rng.call("float_range", -0.12, 0.12)), at.y + float(rng.call("float_range", -0.12, 0.12)))
	var px: int = roundi(here.x * ART_PX)
	var py: int = roundi(here.y * ART_PX)
	var lx: int = int(tr.get("x", -1))
	var ly: int = int(tr.get("y", -1))
	tr["x"] = px
	tr["y"] = py
	if lx >= 0 and SimStances.stance_of(world.components, entity) == SimStances.Stance.Crawl:
		var run := Vector2i(px - lx, py - ly)
		var len_sq: int = run.x * run.x + run.y * run.y
		if len_sq >= SMEAR_MIN_PX * SMEAR_MIN_PX and len_sq <= SMEAR_MAX_PX * SMEAR_MAX_PX:
			add(world, "smear", here.x, here.y, {"a": run.x, "b": run.y})
			return
	# A drop on an earlier drip pools into it.
	var ch: Vector2i = chunk_of_px(px, py)
	var c: Variant = (world.decals as Dictionary).get(chunk_key(ch.x, ch.y))
	if c is Dictionary:
		for r in (c as Dictionary)["d"] as Array:
			var rd: Dictionary = r as Dictionary
			if String(rd["k"]) != "drip":
				continue
			var dx: int = int(rd["x"]) - px
			var dy: int = int(rd["y"]) - py
			if dx * dx + dy * dy <= POOL_MERGE_PX * POOL_MERGE_PX:
				if int(rd["s"]) < 4:
					rd["s"] = int(rd["s"]) + 1
					_touch(world, c as Dictionary)
				return
	add(world, "drip", here.x, here.y)
