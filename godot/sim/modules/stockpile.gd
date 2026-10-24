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
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return out


## A number that changes whenever `tiles` could answer differently: the zone record, whose record it
## is, and the map's generation (a tile walled over or opened bumps it). For a reader that keeps the zone between
## frames -- the overlay asks every frame, and walks the zone only when this moves.
static func signature(world: Variant) -> int:
	var rec: Variant = _record(world)
	return hash([int(world.map_generation), int(world.player), (rec as Dictionary)["tiles"] if rec is Dictionary else null])


static func count(world: Variant) -> int:
	return tiles(world).size()


## May the player mark this tile: open, dry, a floor, a door left out, and ground the player has seen.
## Indoors and out are both allowed. An unexplored tile is refused, because a player cannot mark
## ground they have never seen.
static func markable(world: Variant, tx: int, ty: int) -> bool:
	return markable_in(world, SimSightings.explored_view(world, world.player), tx, ty)


## `markable` with the player's explored set already decoded (`SimSightings.explored_view`), for a
## caller that asks about many tiles at once -- the drag preview asks about a whole rectangle every
## frame, and decoding the bitset once per tile would be most of its cost. Same answer, same order of
## tests; `markable` is this with the view fetched for one tile.
static func markable_in(world: Variant, explored: Variant, tx: int, ty: int) -> bool:
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
	return explored != null and bool((explored as Object).call("has_tile", tx, ty))


## What `stockpile.mark` would change, without changing it: {"tiles": the tiles it would add (`on`)
## or take back (`off`), row-major; "refused": true when an `on` would be refused whole}. `mark`
## below applies exactly this answer, so the screen's drag preview and the command cannot disagree
## about a tile: what the preview draws is what the release changes, and a refused rectangle draws
## nothing because it changes nothing.
static func preview(world: Variant, cmd: Dictionary) -> Dictionary:
	var x0: int = mini(int(cmd.get("x0", 0)), int(cmd.get("x1", 0)))
	var x1: int = maxi(int(cmd.get("x0", 0)), int(cmd.get("x1", 0)))
	var y0: int = mini(int(cmd.get("y0", 0)), int(cmd.get("y1", 0)))
	var y1: int = maxi(int(cmd.get("y0", 0)), int(cmd.get("y1", 0)))
	var out: Array[Vector2i] = []
	if world.tilemap == null:
		return {"tiles": out, "refused": false}
	var on: bool = bool(cmd.get("on", true))
	if on and (x1 - x0 + 1) * (y1 - y0 + 1) > MAX_TILES:
		return {"tiles": out, "refused": true}
	var rec: Variant = _record(world)
	if on:
		var have: Dictionary = (rec as Dictionary)["tiles"] if rec is Dictionary else _default_keys(world)
		var explored: Variant = SimSightings.explored_view(world, world.player)
		for ty in range(y0, y1 + 1):
			for tx in range(x0, x1 + 1):
				if not have.has(_key(tx, ty)) and markable_in(world, explored, tx, ty):
					out.append(Vector2i(tx, ty))
		if have.size() + out.size() > MAX_TILES:
			return {"tiles": [] as Array[Vector2i], "refused": true}
		return {"tiles": out, "refused": false}
	var keys: Array = (rec as Dictionary)["tiles"].keys() if rec is Dictionary else _default_keys(world).keys()
	for key in keys:
		var t: Vector2i = _parse(String(key))
		if t.x >= x0 and t.x <= x1 and t.y >= y0 and t.y <= y1:
			out.append(t)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return {"tiles": out, "refused": false}


## `stockpile.mark {x0, y0, x1, y1, on}`: an inclusive rectangle. `on` adds every markable tile in it,
## and a rectangle larger than MAX_TILES is refused whole, as is an `on` that would take the zone past
## MAX_TILES. `off` takes back every zone tile inside it, markable or not; it scans the zone rather
## than the rectangle, so a rectangle of any size is safe to clear. What changes is `preview`'s answer.
static func mark(world: Variant, cmd: Dictionary) -> void:
	if world.tilemap == null:
		return
	var change: Dictionary = preview(world, cmd)
	var tiles_changed: Array = change["tiles"] as Array
	if bool(change["refused"]) or tiles_changed.is_empty():
		return
	var on: bool = bool(cmd.get("on", true))
	var set_tiles: Dictionary = _ensure(world)["tiles"]
	for t in tiles_changed:
		var key: String = _key((t as Vector2i).x, (t as Vector2i).y)
		if on:
			set_tiles[key] = true
		else:
			set_tiles.erase(key)
	world.events.publish({"type": "stockpile.changed", "added": tiles_changed.size() if on else 0, "removed": 0 if on else tiles_changed.size()})


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


# The default zone as the record would hold it, for `preview` to ask about before any record exists.
static func _default_keys(world: Variant) -> Dictionary:
	var out: Dictionary = {}
	for t in _default_tiles(world):
		out[_key(t.x, t.y)] = true
	return out


static func _key(tx: int, ty: int) -> String:
	return "%d,%d" % [tx, ty]


static func _parse(key: String) -> Vector2i:
	var parts: PackedStringArray = key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))
