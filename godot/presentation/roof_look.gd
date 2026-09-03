extends RefCounted
# Walls with thickness, roofs cut out where the sim sees -- the rules, with no state.
#
# docs/30's Dungeon Settlers decision (2026-09-03): every wall tile draws inside its own footprint
# as thick mass with a lit cap and, where its south neighbour is open ground, a south face in the
# building's `look` material, with that tile's window or door drawn in the face; a roof draws over
# the interior tiles the player cannot see, of a building at least one tile of which is in view,
# while the player is outside. Draw is a subset of the unseen: a tile the sim says is seen never
# takes a roof, so an interior seen through a door keeps its floor and its bodies (the 2026-09-02
# roof rule, the lit-pool discipline again). Nothing hangs over a walkable tile and no tile is
# depth-sorted: a face is drawn in the wall tile's own rect, a roof in the interior tile's own
# rect, and a door's face in the doorway's.
#
# Every rule here is a pure function of the map, the seen set and tile coordinates, so
# check_roof_look.gd holds each one to a hand-built map both ways. main.gd owns the per-map
# cache and the blits; this file owns what is true.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimWorldgen = preload("res://sim/map/worldgen.gd")
const Appearance = preload("res://presentation/appearance.gd")

# What a tile shows to the street on its south side.
enum Face { NONE = 0, WALL = 1, WINDOW = 2, DOOR = 3, GARAGE = 4 }
# Which half of a pitched roof an interior tile takes, or the flat sheet.
enum Slope { FLAT = 0, NORTH = 1, SOUTH = 2 }

# building_index answers these for a tile in no building and for the annex; every other value is
# an index into map.buildings.
const INDEX_NONE: int = -1
const INDEX_ANNEX: int = -2


# Whether the tile south of (tx, ty) is open ground: in bounds, not solid, outdoors. A wall with
# open ground to its south is the building's front and draws its face; one with another wall, an
# interior or the map edge to its south is mass seen from above and draws its cap. Per tile,
# never a rect's south row: a gabled house's front is not one flat row, and the annex's south
# wall is compound.
static func south_open(map: Variant, tx: int, ty: int) -> bool:
	if map == null:
		return false
	var sy: int = ty + 1
	if tx < 0 or sy < 0 or tx >= int(map.w) or sy >= int(map.h):
		return false
	if SimTileMap.is_indoors(map, tx, sy):
		return false
	return not SimTileMap.is_solid(map, tx, sy)


# Whether a Wall or Window tile draws its face rather than its cap. Anything that is not a wall
# has no face to draw, whatever lies south of it.
static func wall_face_at(map: Variant, tx: int, ty: int) -> bool:
	if map == null:
		return false
	var tile: int = int(SimTileMap.tile_at(map, tx, ty))
	if tile != SimTileMap.Tile.Wall and tile != SimTileMap.Tile.Window:
		return false
	return south_open(map, tx, ty)


# What the tile shows in its face: nothing unless its south neighbour is open ground; a doorway
# (a tile in `thresholds`, Appearance.door_tiles' index dictionary) is a door, or a garage mouth
# when the tile east or west of it is a doorway too; a Window tile is a window; a Wall tile is
# plain wall; anything else shows nothing.
static func facade_at(map: Variant, thresholds: Dictionary, tx: int, ty: int) -> int:
	if map == null or not south_open(map, tx, ty):
		return Face.NONE
	var w: int = int(map.w)
	if thresholds.has(ty * w + tx):
		var west: bool = tx > 0 and thresholds.has(ty * w + tx - 1)
		var east: bool = tx + 1 < w and thresholds.has(ty * w + tx + 1)
		if west or east:
			return Face.GARAGE
		return Face.DOOR
	var tile: int = int(SimTileMap.tile_at(map, tx, ty))
	if tile == SimTileMap.Tile.Window:
		return Face.WINDOW
	if tile == SimTileMap.Tile.Wall:
		return Face.WALL
	return Face.NONE


# The footprint of one building: an index into map.buildings, or the annex.
static func rect_of(map: Variant, index: int) -> Rect2i:
	if map == null:
		return Rect2i()
	if index == INDEX_ANNEX:
		return SimTileMap.annex_rect(map)
	var records: Array = map.buildings as Array
	if index < 0 or index >= records.size() or not (records[index] is Dictionary):
		return Rect2i()
	var r: Dictionary = records[index] as Dictionary
	return Rect2i(int(r.get("x", 0)), int(r.get("y", 0)), int(r.get("w", 0)), int(r.get("h", 0)))


# Every building footprint on the map, as its index: the manifest's records in order, then the
# annex. A record with no footprint is skipped, and a map with no annex anchor has none.
static func indices_of(map: Variant) -> PackedInt32Array:
	var out := PackedInt32Array()
	if map == null:
		return out
	var records: Array = map.buildings as Array
	for i in records.size():
		if rect_of(map, i).has_area():
			out.append(i)
	if SimTileMap.annex_rect(map).has_area():
		out.append(INDEX_ANNEX)
	return out


# tile -> which building it lies in: an index into map.buildings, INDEX_ANNEX for the annex,
# INDEX_NONE elsewhere. Built once per map by main.gd and cached there (never static: two worlds
# share one gate process), so the draw loop does one lookup per tile, not a scan of the rects.
static func building_index(map: Variant) -> PackedInt32Array:
	var out := PackedInt32Array()
	if map == null:
		return out
	var w: int = int(map.w)
	var h: int = int(map.h)
	out.resize(w * h)
	out.fill(INDEX_NONE)
	for index in indices_of(map):
		var rect: Rect2i = rect_of(map, index)
		for ty in range(maxi(0, rect.position.y), mini(h, rect.end.y)):
			for tx in range(maxi(0, rect.position.x), mini(w, rect.end.x)):
				out[ty * w + tx] = index
	return out


# The building's `look` block -- {roof, wall} material names -- read off the content entry the
# manifest's record names (the annex off the map patch the generator stamped). {} when the
# record, the entry or the block is absent, which every caller reads as "draw the procedural
# fallback": a district generated before looks existed still draws.
static func look_of(world: Variant, index: int) -> Dictionary:
	if world == null or world.tilemap == null:
		return {}
	var entry: Dictionary = {}
	if index == INDEX_ANNEX:
		entry = Appearance.entry_of(world, "map", SimWorldgen.ANNEX_PATCH_ID)
	else:
		var records: Array = world.tilemap.buildings as Array
		if index >= 0 and index < records.size() and records[index] is Dictionary:
			entry = Appearance.entry_of(world, "building", String((records[index] as Dictionary).get("id", "")))
	var look: Variant = entry.get("look")
	return look as Dictionary if look is Dictionary else {}


# Whether the observer has a sightline to any tile of the rect: a building nobody has seen any
# part of is not drawn at all, roof included -- the footprint of a partly-seen building is the
# one soft tell the decision allows, and a building no tile of which is seen is not one.
static func known(rect: Rect2i, seen: Variant) -> bool:
	if seen == null:
		return false
	for ty in range(rect.position.y, rect.end.y):
		for tx in range(rect.position.x, rect.end.x):
			if (seen as Object).call("has_tile", tx, ty):
				return true
	return false


# The interior tiles that take a roof this frame: for every building whose footprint touches
# `bounds` (the visible AABB, minX/maxX/minY/maxY in tiles) and is known, unless the player
# stands inside it, every indoor tile inside the bounds that the observer cannot see. `seen` is
# the observer's tile set (SimVisibility.tiles_for) or null for nobody, and nobody sees no roofs:
# a roof is a fact about what the survivor cannot see, and with no survivor there is no such
# fact.
static func roof_tiles(map: Variant, seen: Variant, bounds: Dictionary, player_tile: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if map == null or seen == null:
		return out
	var min_x: int = maxi(0, floori(float(bounds.get("minX", 0.0))))
	var max_x: int = mini(int(map.w) - 1, ceili(float(bounds.get("maxX", 0.0))))
	var min_y: int = maxi(0, floori(float(bounds.get("minY", 0.0))))
	var max_y: int = mini(int(map.h) - 1, ceili(float(bounds.get("maxY", 0.0))))
	if max_x < min_x or max_y < min_y:
		return out
	var view := Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
	for index in indices_of(map):
		var rect: Rect2i = rect_of(map, index)
		if not rect.intersects(view):
			continue
		if rect.has_point(player_tile):
			continue
		if not known(rect, seen):
			continue
		for ty in range(maxi(rect.position.y, min_y), mini(rect.end.y, max_y + 1)):
			for tx in range(maxi(rect.position.x, min_x), mini(rect.end.x, max_x + 1)):
				if not SimTileMap.is_indoors(map, tx, ty):
					continue
				if (seen as Object).call("has_tile", tx, ty):
					continue
				out.append(Vector2i(tx, ty))
	return out


# Which half of a pitched roof a row takes: the ridge runs east-west through the footprint's
# middle row; rows north of it face north, the ridge row and below face south. A flat material is
# FLAT everywhere -- whether a material is pitched is the dressing block's answer (it declares
# `n` and `s` keys, or one `flat`), passed in rather than guessed from the name.
static func slope_of(rect: Rect2i, ty: int, pitched: bool) -> int:
	if not pitched:
		return Slope.FLAT
	var ridge: int = rect.position.y + rect.size.y / 2
	return Slope.NORTH if ty < ridge else Slope.SOUTH
