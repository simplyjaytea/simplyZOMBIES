class_name SimTileMap
extends RefCounted

const TILE_METRES: int = 1
const DISTRICT_TILES: int = 256

enum Tile { Floor = 0, Wall = 1, Window = 2, Screen = 3, Low = 4, Tree = 5 }
enum Opacity { Clear = 0, Opaque = 1, Low = 2 }
enum Eye { Standing = 0, Crouched = 1 }

const OPACITY: Array[int] = [
	Opacity.Clear,
	Opacity.Opaque,
	Opacity.Clear,
	Opacity.Opaque,
	Opacity.Low,
	Opacity.Opaque,
]
const SOLID: Array[bool] = [
	false,
	true,
	true,
	false,
	false,
	true,
]

const SURFACE_PAVED: int = 0
const SURFACE_DIRT: int = 1
const SURFACE_GRASS: int = 2
const SURFACE_UNDERGROWTH: int = 3
const SURFACE_RUBBLE: int = 4

var w: int
var h: int
var tiles: PackedByteArray
var surfaces: PackedByteArray
var indoors: PackedByteArray
# ponytail: overlay Dictionary on the window/scrap tile, not Tile.Barricade.
var overlays: Dictionary = {}
# Where the colony's fixed points ended up, written by SimTemplates.stamp from the template's own
# relative anchors. Empty on a bare generated district, which is why every accessor below has an
# absent sentinel rather than a default coordinate.
var anchors: Dictionary = {}
# What the generator placed, in placement order: {id, x, y, w, h, doors:[{x,y}]} per building, in
# absolute tiles. An Array of records rather than a Dictionary keyed by anything, per CLAUDE.md --
# and it never round-trips through a save, because the map is regenerated from the seed rather
# than serialised. Empty on a blank map and on any district nobody generated.
var buildings: Array = []
# The streets the generator carved, in carve order: {axis, at, width, from, to} per span, in
# absolute tiles -- axis "x" is a vertical street standing at column `at`, axis "y" a horizontal
# one at row `at`, each `width` tiles wide running `from`..`to` inclusive along its length. Layout
# metadata, not tiles: `_streets` appends one record per `_carve_street` call and draws nothing
# extra for it, so the layout stays byte-identical (check_road_look.gd holds that). A plain Array
# of plain Dictionaries (the `buildings` precedent), never serialised -- the map is regenerated
# from the seed -- and empty on fixture maps and `blank_map`, which is what "no paint" means to
# the draw path that reads it (presentation/road_paint.gd).
var streets: Array = []
# The cars the generator parked, in placement order: {x, y, w, h, axis, class, facing} per
# vehicle, in absolute tiles -- (x, y) the footprint's north-west corner, `axis` "ns" for a car
# standing along a vertical street (w 2, h 5) and "ew" for one along a horizontal street (w 5,
# h 2), `facing` which way it points ("n"/"s" on a vertical street, "e"/"w" on a horizontal one),
# `class` the content id it was drawn from. Unlike `streets` this is *not* only metadata: the
# `worldgen.vehicles` pass writes Tile.Low under every footprint tile, so a car is cover on the
# map as well as a record here -- the record is what says which picture stands on it and which
# way round. A plain Array of plain Dictionaries (the `buildings` and `streets` precedent), never
# serialised -- the map is regenerated from the seed -- and empty on fixture maps, on `blank_map`,
# and on every district that declares no `vehicles` block.
var vehicles: Array = []
# Bumped by SimVehicles every time a car's footprint tiles or record change, so a reader that
# caches something derived from `vehicles` (the drawing node's tile -> record index) can tell a
# moved car from the map object it already knows. Never serialised; the module re-syncs after a
# restore and bumps it then.
var vehicle_generation: int = 0
# Where the loot is, in absolute tiles: {x, y, table, container?} per site, in placement order.
# Written by the generator's `worldgen.sites` pass and by `SimTemplates.stamp` for a template that
# carries a `loot` block (the civic annex's two rows, and any building template that grows one);
# read by `SimBoot.place_loot`, which scatters a plain site and stands a container for one that
# names a `container`.
#
# An Array of records for the reason CLAUDE.md gives: a Dictionary keyed by a tile index comes back
# from JSON with String keys and misses silently. This one never round-trips -- the map is
# regenerated from the seed -- but the shape is the shape regardless, and iterating an Array is
# also what keeps the pass's draw order independent of Dictionary ordering.
var sites: Array = []

func _init(width: int, height: int, tile: int = Tile.Floor) -> void:
	w = width
	h = height
	tiles = PackedByteArray()
	tiles.resize(w * h)
	if tile != Tile.Floor:
		for i in tiles.size():
			tiles[i] = tile
	surfaces = PackedByteArray()
	surfaces.resize(w * h)
	indoors = PackedByteArray()
	indoors.resize(w * h)
	overlays = {}
	anchors = {}
	buildings = []
	streets = []
	vehicles = []
	vehicle_generation = 0
	sites = []


static func blank_map(width: int, height: int, tile: int = Tile.Floor) -> Variant:
	var script: GDScript = load("res://sim/map/tilemap.gd") as GDScript
	return script.new(width, height, tile)


static func tile_range(metres: float) -> int:
	return maxi(1, ceili(metres / float(TILE_METRES)))


static func tile_at(map: Variant, tx: int, ty: int) -> int:
	if tx < 0 or ty < 0 or tx >= map.w or ty >= map.h:
		return Tile.Wall
	return int(map.tiles[ty * map.w + tx])


static func overlay_at(map: Variant, tx: int, ty: int) -> Variant:
	if tx < 0 or ty < 0 or tx >= map.w or ty >= map.h:
		return null
	var table: Variant = map.overlays
	if not table is Dictionary:
		return null
	return (table as Dictionary).get(ty * int(map.w) + tx)


static func is_solid(map: Variant, tx: int, ty: int) -> bool:
	var ov: Variant = overlay_at(map, tx, ty)
	if ov is Dictionary and String((ov as Dictionary).get("kind", "")) == "scrap":
		return true
	return SOLID[tile_at(map, tx, ty)]


static func opacity_at(map: Variant, tx: int, ty: int) -> int:
	var ov: Variant = overlay_at(map, tx, ty)
	if ov is Dictionary:
		var kind: String = String((ov as Dictionary).get("kind", ""))
		if kind == "scrap":
			return Opacity.Opaque
		if kind == "board":
			if int((ov as Dictionary).get("stage", 0)) >= 3:
				return Opacity.Low
			return Opacity.Opaque
	return OPACITY[tile_at(map, tx, ty)]


static func blocks_sight(map: Variant, tx: int, ty: int, eye: int = Eye.Standing) -> bool:
	var opacity := opacity_at(map, tx, ty)
	return opacity == Opacity.Opaque or (opacity == Opacity.Low and eye == Eye.Crouched)


static func blocked_at(map: Variant, x: float, y: float) -> bool:
	return is_solid(map, floori(x / float(TILE_METRES)), floori(y / float(TILE_METRES)))


static func is_indoors(map: Variant, tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= map.w or ty >= map.h:
		return false
	return map.indoors[ty * map.w + tx] == 1


static func _fill(map: Variant, x: int, y: int, fw: int, fh: int, tile: int) -> void:
	for j in fh:
		for i in fw:
			var tx := x + i
			var ty := y + j
			if tx < 0 or ty < 0 or tx >= map.w or ty >= map.h:
				continue
			map.tiles[ty * map.w + tx] = tile


# The canonical district, kept as a two-argument call because most of the tree asks for a district
# by seed and size and has no opinion about its type. The pipeline lives in `SimWorldgen` now --
# streets from district JSON, lots, a weighted pick from an authored template pool -- and this
# hands it the residential suburb.
#
# `load()` rather than `preload()` on purpose: worldgen.gd preloads this file for its tile enums,
# and two preloads pointing at each other is a cycle the parser will not take.
static func generate_district(seed: int, size: int = DISTRICT_TILES, content: Variant = null) -> Variant:
	var worldgen: GDScript = load("res://sim/map/worldgen.gd") as GDScript
	# Three arguments, so the district and the dressing both come off SimWorldgen's own defaults
	# rather than being restated here where they could drift.
	return worldgen.call("generate", seed, size, content)


static func find_open_tile(map: Variant, start_x: int, start_y: int) -> Dictionary:
	var sx: int = clampi(start_x, 1, map.w - 2)
	var sy: int = clampi(start_y, 1, map.h - 2)
	if not is_solid(map, sx, sy):
		return {"x": sx, "y": sy}
	for radius in range(1, maxi(map.w, map.h)):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var tx: int = sx + dx
				var ty: int = sy + dy
				if tx <= 0 or ty <= 0 or tx >= map.w - 1 or ty >= map.h - 1:
					continue
				if not is_solid(map, tx, ty):
					return {"x": tx, "y": ty}
	return {"x": sx, "y": sy}


static func _anchor(map: Variant, key: String) -> Variant:
	# A world without a tilemap is a world without anchors, and the absent sentinels below say so.
	# Callers now hand this `world.tilemap` directly, which some fixture worlds leave null.
	if map == null:
		return null
	var table: Variant = map.anchors
	if not (table is Dictionary):
		return null
	var point: Variant = (table as Dictionary).get(key)
	if point is Dictionary:
		return point
	return null


# (-1, -1) rather than (0, 0) for "no such anchor": (0, 0) is a real tile, and a caller that
# forgot to check would quietly site the colony in the map's corner instead of failing.
static func _anchor_tile(map: Variant, key: String) -> Vector2i:
	var point: Variant = _anchor(map, key)
	if not (point is Dictionary):
		return Vector2i(-1, -1)
	return Vector2i(int((point as Dictionary).get("x", -1)), int((point as Dictionary).get("y", -1)))


static func annex_rect(map: Variant) -> Rect2i:
	var point: Variant = _anchor(map, "annex")
	if not (point is Dictionary):
		return Rect2i(0, 0, 0, 0)
	var d: Dictionary = point as Dictionary
	return Rect2i(int(d.get("x", 0)), int(d.get("y", 0)), int(d.get("w", 0)), int(d.get("h", 0)))


static func gate_a(map: Variant) -> Vector2i:
	return _anchor_tile(map, "gate_a")


static func gate_b(map: Variant) -> Vector2i:
	return _anchor_tile(map, "gate_b")


static func player_start(map: Variant) -> Vector2i:
	return _anchor_tile(map, "player_start")


static func well_tile(map: Variant) -> Vector2i:
	return _anchor_tile(map, "well")


static func apply_patch(map: Variant, patch: Dictionary) -> void:
	# Deterministic blit. No RNG. Diff vs generate_district is limited to patch.rect.
	var rect: Dictionary = patch.get("rect", {}) as Dictionary
	var rx: int = int(rect.get("x", 0))
	var ry: int = int(rect.get("y", 0))
	var rw: int = int(rect.get("w", 0))
	var rh: int = int(rect.get("h", 0))
	var tiles: Array = patch.get("tiles", []) as Array
	var surfaces: Array = patch.get("surfaces", []) as Array
	var indoors_arr: Array = patch.get("indoors", []) as Array
	for j in rh:
		for i in rw:
			var tx: int = rx + i
			var ty: int = ry + j
			if tx < 0 or ty < 0 or tx >= map.w or ty >= map.h:
				continue
			var li: int = j * rw + i
			var dst: int = ty * map.w + tx
			if li < tiles.size():
				map.tiles[dst] = int(tiles[li])
			if li < surfaces.size():
				map.surfaces[dst] = int(surfaces[li])
			if li < indoors_arr.size():
				map.indoors[dst] = int(indoors_arr[li])


static func load_patch_from_content(content: Variant, id: String = "map.district.alpha") -> Variant:
	if content == null:
		return null
	if content is Dictionary:
		for v in (content as Dictionary).values():
			if v is Dictionary and String((v as Dictionary).get("id", "")) == id:
				return v
			if v is Array:
				for entry in v as Array:
					if entry is Dictionary and String((entry as Dictionary).get("id", "")) == id:
						return entry
	return null
