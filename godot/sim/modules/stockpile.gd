class_name SimStockpile
extends RefCounted
# The stockpile as tiles in the sim -- docs/12's "Stockpiles are physical and lootable", first
# slice. Until now "the stockpile" was one test with no record behind it: indoors, a floor, inside
# the annex. This module keeps the same answer as the default and lets the player change it.
#
# The zone is a record on the player entity, `stockpile: {"tiles": {"tx,ty": true}}`, keyed by the
# String "tx,ty" because a component never holds a Dictionary keyed by an int (JSON hands the keys
# back as Strings). The record is created the first time anything changes the zone, seeded from the
# default, so until then the zone IS the default and no entity, save key or boot step exists for it.
# A save from before this slice has no record and reads as the default, with no version bump. The
# record sits on the player rather than a new entity so no entity id after it moves.
#
# A zone tile answers `has_tile` only while the map leaves it open: a tile walled over after it was
# marked is not a stockpile tile, and reads again once it is opened. The default zone answers the
# same way, which changes nothing for the annex, where nothing is solid on a floor.
#
# `SimNeeds.is_stockpile_tile` is the one caller-facing predicate and it now asks here. Beds do not
# follow the zone: `SimNeeds.is_annex_floor` still answers where a bed goes, and it delegates to
# `is_annex_floor` below. This file preloads nothing that reaches back to `needs.gd`, so `needs.gd`
# can preload this one without a cycle.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimSurface = preload("res://sim/map/surface.gd")
const SimSightings = preload("res://sim/modules/sightings.gd")

const COMMAND: String = "stockpile.mark"
const COMPONENT: String = "stockpile"
# The most tiles a zone may hold, and the most a single `on` rectangle may cover. Both bound every
# scan of the zone (the Haul search, the drop point, the window that lists it). A mark that would
# pass the cap is refused whole, never applied in part.
const MAX_TILES: int = 400


static func register_module(world: Variant) -> void:
	# Input order 16: after orders' intake at 15, so a mark issued this tick is in force from the
	# `jobs.ai` pass of the same tick, as an order is.
	world.systems.register("stockpile.intake", "input", 16, func(w: Variant) -> void:
		for cmd in w.commands.current as Array:
			var c: Dictionary = cmd as Dictionary
			if String(c.get("type", "")) == COMMAND:
				mark(w, c)
	)


## The annex's indoor floor: the default zone, and nothing else. Beds are placed here and only here.
static func is_annex_floor(world: Variant, tx: int, ty: int) -> bool:
	if world.tilemap == null:
		return false
	if not SimTileMap.is_indoors(world.tilemap, tx, ty):
		return false
	if SimTileMap.tile_at(world.tilemap, tx, ty) != SimTileMap.Tile.Floor:
		return false
	# Where the annex is comes off the map now rather than out of `SimDirector.ANNEX`. An unstamped
	# district reports the empty rect, which has no points -- so it has no stockpile, rather than
	# one at somebody else's coordinates.
	var annex: Rect2i = SimTileMap.annex_rect(world.tilemap)
	if annex.size.x <= 0 or annex.size.y <= 0:
		return false
	return annex.has_point(Vector2i(tx, ty))


## Is (tx, ty) a stockpile tile right now: in the zone and open ground.
static func has_tile(world: Variant, tx: int, ty: int) -> bool:
	if world.tilemap == null:
		return false
	var rec: Variant = _record(world)
	if rec == null:
		if not is_annex_floor(world, tx, ty):
			return false
	elif not (rec as Dictionary)["tiles"].has(_key(tx, ty)):
		return false
	return not SimTileMap.is_solid(world.tilemap, tx, ty)


## The zone's tiles, row-major (`ty` then `tx`), each one `has_tile` answers for right now. The
## drop point and every other ordered reader take their order from here.
static func tiles(world: Variant) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if world.tilemap == null:
		return out
	var rec: Variant = _record(world)
	if rec == null:
		var annex: Rect2i = SimTileMap.annex_rect(world.tilemap)
		for j in range(annex.position.y, annex.position.y + annex.size.y):
			for i in range(annex.position.x, annex.position.x + annex.size.x):
				if has_tile(world, i, j):
					out.append(Vector2i(i, j))
		return out
	for key in (rec as Dictionary)["tiles"].keys():
		var t: Vector2i = _parse(String(key))
		if has_tile(world, t.x, t.y):
			out.append(t)
	out.sort_custom(_row_major)
	return out


static func count(world: Variant) -> int:
	return tiles(world).size()


## The zone's patches: groups of zone tiles that touch edge to edge, each row-major. A pile marked at
## a camp is its own patch however far it is from the annex. Patches come out in the row-major order
## of their first tile, so the list has one order whatever the record's keys were.
static func patches(world: Variant) -> Array:
	var zone: Array[Vector2i] = tiles(world)
	var member: Dictionary = {}
	for t in zone:
		member[_key(t.x, t.y)] = true
	var seen: Dictionary = {}
	var out: Array = []
	for t in zone:
		if seen.has(_key(t.x, t.y)):
			continue
		var group: Array[Vector2i] = []
		var pending: Array[Vector2i] = [t]
		seen[_key(t.x, t.y)] = true
		while not pending.is_empty():
			var c: Vector2i = pending.pop_back()
			group.append(c)
			for n in [Vector2i(c.x + 1, c.y), Vector2i(c.x - 1, c.y), Vector2i(c.x, c.y + 1), Vector2i(c.x, c.y - 1)]:
				var k: String = _key(n.x, n.y)
				if member.has(k) and not seen.has(k):
					seen[k] = true
					pending.append(n)
		group.sort_custom(_row_major)
		out.append(group)
	return out


## Where a hauled item goes down, from `from`. The nearest patch with a free zone tile takes it, and
## inside that patch the free tile with the fewest items on it wins, ties to the nearest to `from`,
## ties again to row-major order. `lying` holds the tile of every loose item, one entry each, and
## `free` says whether a tile can take an item at all (no bed, no campfire). The zone is never full:
## a tile's count only rises as it fills, so nothing is refused for room. (-1, -1) when no zone tile
## is free.
static func drop_tile(world: Variant, from: Vector2, lying: Array[Vector2i], free: Callable) -> Vector2i:
	var load: Dictionary = {}
	for t in lying:
		load[_key(t.x, t.y)] = int(load.get(_key(t.x, t.y), 0)) + 1
	var ranked: Array = []
	for p in patches(world):
		ranked.append({"d": _patch_distance(p, from), "patch": p, "i": ranked.size()})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["d"] < b["d"] or (a["d"] == b["d"] and a["i"] < b["i"])
	)
	for entry in ranked:
		var best := Vector2i(-1, -1)
		var best_load: int = 0
		var best_d: float = INF
		for t in entry["patch"]:
			if not free.call(t.x, t.y):
				continue
			var n: int = int(load.get(_key(t.x, t.y), 0))
			var d: float = _centre_distance(from, t)
			if best.x < 0 or n < best_load or (n == best_load and d < best_d):
				best = t
				best_load = n
				best_d = d
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


## May the player mark this tile: open, dry, a floor, a door left out, and ground the player has seen.
## Indoors and out are both allowed. An unexplored tile is refused, because a player cannot mark
## ground they have never seen.
static func markable(world: Variant, tx: int, ty: int) -> bool:
	if world.tilemap == null:
		return false
	var map: Variant = world.tilemap
	if tx < 0 or ty < 0 or tx >= map.w or ty >= map.h:
		return false
	if SimTileMap.tile_at(map, tx, ty) != SimTileMap.Tile.Floor:
		return false
	if SimTileMap.is_solid(map, tx, ty):
		return false
	if SimSurface.surface_at(map, tx, ty) == SimSurface.Surface.Water:
		return false
	var ov: Variant = SimTileMap.overlay_at(map, tx, ty)
	if ov is Dictionary and String((ov as Dictionary).get("kind", "")) == "door":
		return false
	return SimSightings.knows_tile(world, world.player, tx, ty)


## `stockpile.mark {x0, y0, x1, y1, on}`: an inclusive rectangle. `on` adds every markable tile in it,
## and a rectangle larger than MAX_TILES is refused whole, as is an `on` that would take the zone past
## MAX_TILES. `off` takes back every zone tile inside it, markable or not; it scans the zone rather
## than the rectangle, so a rectangle of any size is safe to clear.
static func mark(world: Variant, cmd: Dictionary) -> void:
	var x0: int = mini(int(cmd.get("x0", 0)), int(cmd.get("x1", 0)))
	var x1: int = maxi(int(cmd.get("x0", 0)), int(cmd.get("x1", 0)))
	var y0: int = mini(int(cmd.get("y0", 0)), int(cmd.get("y1", 0)))
	var y1: int = maxi(int(cmd.get("y0", 0)), int(cmd.get("y1", 0)))
	if world.tilemap == null:
		return
	var on: bool = bool(cmd.get("on", true))
	if on and (x1 - x0 + 1) * (y1 - y0 + 1) > MAX_TILES:
		return
	var set_tiles: Dictionary = _ensure(world)["tiles"]
	var added: Array[String] = []
	var removed: int = 0
	if on:
		for ty in range(y0, y1 + 1):
			for tx in range(x0, x1 + 1):
				var key: String = _key(tx, ty)
				if not set_tiles.has(key) and markable(world, tx, ty):
					added.append(key)
		if set_tiles.size() + added.size() > MAX_TILES:
			return
		for key in added:
			set_tiles[key] = true
	else:
		for key in set_tiles.keys():
			var t: Vector2i = _parse(String(key))
			if t.x >= x0 and t.x <= x1 and t.y >= y0 and t.y <= y1:
				set_tiles.erase(key)
				removed += 1
	if added.is_empty() and removed == 0:
		return
	world.events.publish({"type": "stockpile.changed", "added": added.size(), "removed": removed})


# The record, or null while the zone is still the default.
static func _record(world: Variant) -> Variant:
	if world.player < 0 or not world.entities.is_alive(world.player):
		return null
	var comp: Variant = world.components.get_component(world.player, COMPONENT)
	return comp if comp is Dictionary else null


# The record, created from the default zone when there is none yet.
static func _ensure(world: Variant) -> Dictionary:
	var rec: Variant = _record(world)
	if rec is Dictionary:
		return rec as Dictionary
	var tiles_seed: Dictionary = {}
	for t in _default_tiles(world):
		tiles_seed[_key(t.x, t.y)] = true
	var fresh: Dictionary = {"tiles": tiles_seed}
	world.components.set_component(world.player, COMPONENT, fresh)
	return fresh


static func _default_tiles(world: Variant) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var annex: Rect2i = SimTileMap.annex_rect(world.tilemap)
	for j in range(annex.position.y, annex.position.y + annex.size.y):
		for i in range(annex.position.x, annex.position.x + annex.size.x):
			if is_annex_floor(world, i, j):
				out.append(Vector2i(i, j))
	return out


static func _key(tx: int, ty: int) -> String:
	return "%d,%d" % [tx, ty]


static func _parse(key: String) -> Vector2i:
	var parts: PackedStringArray = key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))


static func _row_major(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)


static func _centre_distance(from: Vector2, t: Vector2i) -> float:
	return from.distance_squared_to(Vector2(float(t.x) + 0.5, float(t.y) + 0.5))


static func _patch_distance(patch: Array, from: Vector2) -> float:
	var best: float = INF
	for t in patch:
		best = minf(best, _centre_distance(from, t))
	return best
