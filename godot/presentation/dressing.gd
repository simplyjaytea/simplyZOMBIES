extends RefCounted
# What the map looks like where the sim only knows a tile class -- wrecked cars on runs of Low
# tiles, debris over rubble, litter over street pavement, bushes, reeds, rocks, stumps and logs on
# open ground, and the furnishings -- a table, a chair, a dumpster, a traffic cone -- inside and
# outside the buildings.
#
# The sim's vocabulary here is deliberately coarse: `Tile.Low` is "cover you can shoot over" to
# everything that walks, sees or shoots, and `SURFACE_RUBBLE` is "slower and louder underfoot".
# Neither says car, skip or broken concrete, and neither should -- so this file turns the class
# into a picture, out of content (`content/dressing/street.json`), at draw time.
#
# **Dressing is never sim state.** Nothing here writes a component, a tile, a surface or an event,
# and nothing under `godot/sim/` reads this file: a heap is a Low tile the sim already had, a
# tree a Tree tile, and a bush, a stump or a rock is a *picture* drawn over open floor that the
# sim still sees as open floor -- it does not block a step, a sightline or a shot, it is not
# cover, it is not looted, it is not a path the colony avoids. Which floor tile carries which is a
# pure function of the map seed, the tile and the tile's own surface, so the picture of a stump
# is a property of the map the way the colour of a car is. `check_trees.gd`'s NATURE and INERT
# lanes hold this both ways.
#
# Three properties are load-bearing, and check_wrecks.gd holds each of them:
#
#   * **No RNG.** Not `randi`, not a stream off the world registry, not a `static var` counter.
#     A presentation draw from a sim stream is a draw the layout has to account for, and a
#     presentation stream reseeded per boot is a district whose cars change colour when you load
#     a save. Everything varies by a pure hash of the map seed and a tile position, which is
#     identical across boots, saves and the two worlds a gate process boots, by construction.
#     road_paint.gd's `vary` set the precedent one slice ago.
#   * **A car picks one variant for the whole car.** A sedan is ten tiles of car, and hashing each
#     tile separately would paint a pale bonnet on a burnt-out boot. So the hash is taken once on
#     the manifest record's own north-west corner, never per tile.
#   * **Pure statics, no static state.** Same reason road_paint.gd has none: a cache here would
#     be shared between the two worlds one gate process boots. The content block is resolved once
#     per frame by the drawing node and passed in.
#
# A Low tile is one of exactly two things, and it is not a guess: `map.vehicles` is the manifest
# the layout wrote, so a tile inside a record is part of a parked car -- drawn as one feet-anchored
# three-quarter picture in the entity sort, the way a tree is -- and every Low tile outside one is
# a heap of junk, drawn into its own tile. The two are mutually exclusive by construction, and
# check_wrecks.gd holds the draw loop to it.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimSurface = preload("res://sim/map/surface.gd")
const Appearance = preload("res://presentation/appearance.gd")

# The one dressing entry presentation asks for. Named here so main.gd carries no content id, the
# same rule PROP_KINDS and PLAYER_LOOK_ID follow.
const BLOCK_ID: String = "dressing.street"

# One street tile in LITTER_RARITY carries a scrap. Sparse on purpose: litter is texture, and
# texture that lands on a third of the street stops being texture and becomes a surface.
const LITTER_RARITY: int = 17

# Hash salts, one per independent decision, so two choices about the same tile cannot correlate.
# Which heap picture an uncovered Low tile takes out of the block's `heaps` list.
const SALT_HEAP: int = 1
const SALT_LITTER_PICK: int = 2
const SALT_LITTER_KEY: int = 3
const SALT_RUBBLE_KEY: int = 4
# The ground atlas variant under a floor tile (Appearance.ground_cell): one salt, four cells a row.
const SALT_GROUND: int = 5
# Which tall tree picture a Tree tile takes out of the block's `trees.tall` list.
const SALT_TREE: int = 6
# Which colour a parked vehicle takes, hashed on its record's corner and so once for the whole car.
const SALT_VEHICLE: int = 7
# A tree's alpha while a Focal body's ground point lies inside its screen rect: the tree fades,
# never the body (docs/30 decision 10). Opaque otherwise.
const TREE_FADE_ALPHA: float = 0.55


# Independent hash salts for the nature entries: entry `i` of the block's `nature` list takes
# `SALT_NATURE + i`, so appending an entry never reshuffles the ones above it. Well clear of the
# seven salts above.
const SALT_NATURE: int = 100

# The dressing block for a world, or {} when content declares none -- a fixture tree, an old save,
# a district generated before this file existed. Absence is graceful everywhere below: every
# resolver returns "" and the district draws exactly as it did.
static func block_of(world: Variant) -> Dictionary:
	return Appearance.entry_of(world, "dressing", BLOCK_ID)


# A stable non-negative hash of (seed, tile, salt). The two primes are road_paint.gd's, which are
# the spatial hash's, so the whole presentation layer scatters on one arithmetic.
static func hash_at(seed_val: int, tx: int, ty: int, salt: int) -> int:
	var bits: int = (tx * 73856093) ^ (ty * 19349663) ^ (seed_val * 83492791) ^ (salt * 2654435761)
	return bits & 0x7fffffff


# Which of `count` variants this tile takes. -1 when there is nothing to pick from, which every
# caller reads as "draw nothing" rather than as index 0.
static func variant_index(seed_val: int, tx: int, ty: int, salt: int, count: int) -> int:
	if count <= 0:
		return -1
	return hash_at(seed_val, tx, ty, salt) % count


static func _is_low(map: Variant, tx: int, ty: int) -> bool:
	if map == null:
		return false
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return false
	return int(SimTileMap.tile_at(map, tx, ty)) == SimTileMap.Tile.Low


# The picture for a Low tile no manifest record covers: a heap of junk, out of the block's
# `heaps` list by a pure hash of the seed and the tile. "" when the tile is not Low or the block
# declares no heaps, which is the caller's cue to draw the procedural cover block -- the
# supported fallback everywhere in this pipeline, not a stopgap.
#
# Per tile, unlike the whole-car pick below: a heap is one tile of junk and has no run to agree
# with. The occluder pass still stands two- and three-tile runs of Low, and a run of heaps reads
# as a spill of rubbish rather than as one object -- which is what a heap is, and is why the
# front/mid/rear segment vocabulary retired with the cars it was built for.
static func heap_key(block: Dictionary, map: Variant, seed_val: int, tx: int, ty: int) -> String:
	if not _is_low(map, tx, ty):
		return ""
	var heaps: Variant = block.get("heaps")
	if not (heaps is Array) or (heaps as Array).is_empty():
		return ""
	var index: int = variant_index(seed_val, tx, ty, SALT_HEAP, (heaps as Array).size())
	if index < 0:
		return ""
	return String((heaps as Array)[index])


# --- the parked vehicles ---------------------------------------------------------------------
# A car is a manifest record, not a run of tiles read off its neighbours: worldgen's vehicles pass
# writes `{x, y, w, h, axis, class, facing}` into `map.vehicles` and the Tile.Low under it, and
# everything below reads that record. One three-quarter picture per class x variant x axis
# (docs/30, the Dungeon Settlers look, decision 11), standing feet-anchored on the footprint's
# south-edge centre and y-sorted with the bodies and the trees.

# What `vehicle_at` answers for a tile no record covers.
const VEHICLE_NONE: int = -1


# One int per tile: the index into `map.vehicles` of the record covering it, or VEHICLE_NONE.
# Built once per map by the drawing node and cached there against the map object -- never in a
# static var, because one gate process boots two worlds -- exactly as RoofLook.building_index is.
# An empty array for a map with no manifest, which is every fixture map and every map generated
# with dressing off: absence is graceful, and every Low tile is then a heap.
static func vehicle_index(map: Variant) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	if map == null:
		return out
	var w: int = int(map.w)
	var h: int = int(map.h)
	out.resize(w * h)
	out.fill(VEHICLE_NONE)
	var records: Variant = map.get("vehicles")
	if not (records is Array):
		return out
	for i in (records as Array).size():
		var rec: Variant = (records as Array)[i]
		if not (rec is Dictionary):
			continue
		var r: Dictionary = rec as Dictionary
		var x: int = int(r.get("x", 0))
		var y: int = int(r.get("y", 0))
		for dy in int(r.get("h", 0)):
			for dx in int(r.get("w", 0)):
				var tx: int = x + dx
				var ty: int = y + dy
				if tx < 0 or ty < 0 or tx >= w or ty >= h:
					continue
				out[ty * w + tx] = i
	return out


# The record covering a tile, or VEHICLE_NONE. Reads the index the drawing node built rather than
# walking the manifest per tile: a district can stand thirty cars, and the tile loop asks this
# question once for every Low tile it draws.
static func vehicle_at(index: PackedInt32Array, map: Variant, tx: int, ty: int) -> int:
	if map == null or tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return VEHICLE_NONE
	var i: int = ty * int(map.w) + tx
	if i < 0 or i >= index.size():
		return VEHICLE_NONE
	return int(index[i])


# Which manifest records draw this frame: every record with at least one footprint tile inside
# `bounds` (the visible AABB in tiles) that the observer can see. `seen` is the observer's tile
# set (SimVisibility.tiles_for) or null for nobody, and nobody sees no cars -- the same shape as
# tree_tiles and LightLook.lit_pool_tiles, so draw stays a subset of seen.
#
# Any footprint tile, not the anchor tile: a sedan is ten tiles of car, and a bonnet showing past
# the corner of a wall is a car you can see. Asking the anchor alone would blink a whole picture
# in and out on one tile's visibility.
static func vehicle_records(map: Variant, seen: Variant, bounds: Dictionary) -> Array[int]:
	var out: Array[int] = []
	if map == null or seen == null:
		return out
	var records: Variant = map.get("vehicles")
	if not (records is Array):
		return out
	var min_x: int = maxi(0, floori(float(bounds.get("minX", 0.0))))
	var max_x: int = mini(int(map.w) - 1, ceili(float(bounds.get("maxX", 0.0))))
	var min_y: int = maxi(0, floori(float(bounds.get("minY", 0.0))))
	var max_y: int = mini(int(map.h) - 1, ceili(float(bounds.get("maxY", 0.0))))
	var box := Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
	for i in (records as Array).size():
		var rec: Variant = (records as Array)[i]
		if not (rec is Dictionary):
			continue
		if _record_is_seen(rec as Dictionary, seen, box):
			out.append(i)
	return out


# Whether any tile of a record's footprint is both inside the visible box and in the seen set.
# Split out so `vehicle_records` reads as the list it builds rather than as a nest with a flag --
# and so the break out of two loops is a `return`, which GDScript has no other way to write.
static func _record_is_seen(r: Dictionary, seen: Variant, box: Rect2i) -> bool:
	var foot := Rect2i(int(r.get("x", 0)), int(r.get("y", 0)), int(r.get("w", 0)), int(r.get("h", 0)))
	var clip: Rect2i = foot.intersection(box)
	for ty in range(clip.position.y, clip.end.y):
		for tx in range(clip.position.x, clip.end.x):
			if bool((seen as Object).call("has_tile", tx, ty)):
				return true
	return false


# Whether any tile of a record's whole footprint (not clipped to the visible box, unlike
# `_record_is_seen` above) is in `seen`. What tells the renderer's memory look a currently-visible
# car apart from one it only remembers: `vehicle_records` above answers "draw it" off `seen` union
# `explored` composite, and this answers "with today's own eyes, or from memory" so the picture can
# be tinted accordingly.
static func vehicle_is_seen(r: Dictionary, seen: Variant) -> bool:
	if seen == null:
		return false
	var x: int = int(r.get("x", 0))
	var y: int = int(r.get("y", 0))
	for dy in int(r.get("h", 0)):
		for dx in int(r.get("w", 0)):
			if bool((seen as Object).call("has_tile", x + dx, y + dy)):
				return true
	return false


# The picture for one manifest record: the class's own variant list, picked by a pure hash of the
# map seed and the record's north-west corner -- once for the whole car, never per tile, so a
# sedan is one colour end to end -- and then that variant's key for the axis it is parked on.
#
# "" when the world declares no such class, the class declares no variants, or the variant is
# missing the axis it was asked for. Every one of those draws nothing rather than half a car.
static func vehicle_key(world: Variant, record: Dictionary, seed_val: int) -> String:
	var entry: Dictionary = Appearance.entry_of(world, "vehicle", String(record.get("class", "")))
	if entry.is_empty():
		return ""
	var look: Variant = entry.get("appearance")
	if not (look is Dictionary):
		return ""
	var variants: Variant = (look as Dictionary).get("variants")
	if not (variants is Array) or (variants as Array).is_empty():
		return ""
	# The corner the layout parked it on. A record SimVehicles is keeping for a car that can move
	# carries `hx`/`hy` -- the home corner -- beside the live `x`/`y`, so a car keeps its paint
	# when it leaves the kerb; a record with no home (the generator's own, a hand-built one)
	# hashes on the corner it has, which is the same number.
	var rx: int = int(record.get("hx", record.get("x", 0)))
	var ry: int = int(record.get("hy", record.get("y", 0)))
	var index: int = variant_index(seed_val, rx, ry, SALT_VEHICLE, (variants as Array).size())
	if index < 0:
		return ""
	var chosen: Variant = (variants as Array)[index]
	if not (chosen is Dictionary):
		return ""
	return String((chosen as Dictionary).get(String(record.get("axis", "")), ""))


# Where a record's picture stands, in world tiles: the centre of its footprint's south edge, so a
# body north of a parked car sorts behind it and one south sorts in front. The tree's rule for a
# multi-tile thing, and the reason `d` in the entity sort is the record's own south edge.
#
# A record SimVehicles keeps for a car that can move carries `gx`/`gy`, the same point off the
# car's live centre in metres, and that wins: a car mid-tile draws where it is rather than
# snapping tile to tile. A record without them (the generator's, a hand-built one) stands on
# its tiles.
static func vehicle_ground_point(record: Dictionary) -> Vector2:
	if record.has("gx") and record.has("gy"):
		return Vector2(float(record["gx"]), float(record["gy"]))
	var x: float = float(int(record.get("x", 0)))
	var y: float = float(int(record.get("y", 0)))
	return Vector2(x + float(int(record.get("w", 0))) / 2.0, y + float(int(record.get("h", 0))))


# --- the trees ------------------------------------------------------------------------------
# A tree is a picture standing in the entity sort, not a canopy over the tiles: `tree_tiles`
# says which Tree tiles draw one this frame (seen, and in the visible bounds -- draw is a subset
# of seen, an unseen trunk draws nothing), `tree_key` names the picture out of the dressing
# block's `trees.tall` list by a pure hash of the seed and the tile, and `tree_alpha` is the one
# fade rule: the tree goes to TREE_FADE_ALPHA while a Focal body's ground point is inside its
# rect, and the body is never dimmed. "" from tree_key is the caller's cue to draw the two
# procedural discs the tile branch always drew -- a block with no trees still draws a district.

static func tree_key(block: Dictionary, seed_val: int, tx: int, ty: int) -> String:
	var trees: Variant = block.get("trees")
	if not (trees is Dictionary):
		return ""
	var tall: Variant = (trees as Dictionary).get("tall")
	if not (tall is Array) or (tall as Array).is_empty():
		return ""
	var index: int = variant_index(seed_val, tx, ty, SALT_TREE, (tall as Array).size())
	return String((tall as Array)[index])


# Every Tree tile inside `bounds` (the visible AABB, minX/maxX/minY/maxY in tiles) that the
# observer can see. `seen` is the observer's tile set (SimVisibility.tiles_for) or null for
# nobody, and nobody sees no trees: the same shape as LightLook.lit_pool_tiles.
static func tree_tiles(map: Variant, seen: Variant, bounds: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if map == null or seen == null:
		return out
	var min_x: int = maxi(0, floori(float(bounds.get("minX", 0.0))))
	var max_x: int = mini(int(map.w) - 1, ceili(float(bounds.get("maxX", 0.0))))
	var min_y: int = maxi(0, floori(float(bounds.get("minY", 0.0))))
	var max_y: int = mini(int(map.h) - 1, ceili(float(bounds.get("maxY", 0.0))))
	for ty in range(min_y, max_y + 1):
		for tx in range(min_x, max_x + 1):
			if int(SimTileMap.tile_at(map, tx, ty)) != SimTileMap.Tile.Tree:
				continue
			if not (seen as Object).call("has_tile", tx, ty):
				continue
			out.append(Vector2i(tx, ty))
	return out


# The alpha a tree draws at: TREE_FADE_ALPHA while any of `body_points` (Focal bodies' ground
# points, in screen pixels) lies inside `tree_rect` (the tree's screen rect), 1.0 otherwise.
# Pure, so check_trees.gd holds it both ways with a point just inside and one just outside.
static func tree_alpha(tree_rect: Rect2, body_points: Array) -> float:
	for point in body_points:
		if tree_rect.has_point(point as Vector2):
			return TREE_FADE_ALPHA
	return 1.0


# --- the nature dressing ---------------------------------------------------------------------
# Bushes, reeds, rocks, stumps and logs on open outdoor floor, out of the block's `nature` list.
# Each entry is `{key, surfaces, rarity, beside?}`: the picture, the ground names (SimSurface's
# own, lower-cased) it may lie on, one tile in `rarity` of them, and optionally `"beside":
# "water"` for reeds, which only grow where a neighbouring tile is water. The first entry whose
# hash lands and whose ground fits wins the tile.
#
# A tile carries a picture only when it and both of its east and west neighbours are open outdoor
# floor: the log is a tile and a half wide and is drawn after every tile, so this keeps a picture
# from lying across a wall or a doorway it has no business over. The sim knows none of this --
# see the header.
#
# **Cost.** The frame asks this of every visible tile, and a GDScript tile is not free. Measured
# 2026-09-26, headless, over a 34 x 21 screen of seen tiles: 4.9 ms a frame when each tile read
# the list and called `hash_at` once per entry; 1.1 ms once the list was read once per call
# (`_nature_entries`: keys, salts, rarities and a surface mask as plain arrays), a tile's surface
# refused the entries that could not lie on it before any roll was made, and the roll was written
# as `hash_at`'s own arithmetic with the salt term pre-multiplied (`_nature_pick`; the copy is held
# to `nature_key` and to `hash_at` by `check_trees.gd`'s NATURE lane on every tile it looks at).
# That is still a millisecond a frame for a picture that is nearly never there, so
# `nature_tiles_cached` keeps the picks of each 16 x 16 chunk in a dictionary the drawing node owns
# and resets whenever the map, its vehicle generation (a driven car moves Low tiles under it), the
# seed or the content changes -- never a static, because one gate process boots two worlds -- and a
# frame is then a few list walks.

# The one ground name a `beside` may name, and the surface it means.
const NATURE_BESIDE_WATER: String = "water"

# The side of the square of tiles whose picks `nature_tiles_cached` keeps together.
const NATURE_CHUNK: int = 16

# hash_at's own constants, named so the one place `nature_tiles` repeats its arithmetic can be
# read against it.
const _HASH_TX: int = 73856093
const _HASH_TY: int = 19349663
const _HASH_SEED: int = 83492791
const _HASH_SALT: int = 2654435761


# A SimSurface value by its lower-case name, or -1 for a name that is not a surface.
static func surface_named(surface_name: String) -> int:
	var found: Variant = SimSurface.Surface.get(surface_name.capitalize())
	return int(found) if found != null else -1


# The block's `nature` list as plain arrays, one per usable entry, in list order: `[key, rarity,
# salt_term, surface_mask, beside_water]`, where `salt_term` is `hash_at`'s `salt * 2654435761` for
# this entry's own salt and `surface_mask` has bit `n` set for each SimSurface number `n` it may lie
# on. An entry with no key, a
# rarity under two (which would land on every tile) or no real surface is dropped rather than
# carpeting the district; `[]` for a block that declares none. Pure.
static func _nature_entries(block: Dictionary) -> Array:
	var out: Array = []
	var listed: Variant = block.get("nature")
	if not (listed is Array):
		return out
	for i in (listed as Array).size():
		var raw: Variant = (listed as Array)[i]
		if not (raw is Dictionary):
			continue
		var entry: Dictionary = raw as Dictionary
		var key: String = String(entry.get("key", ""))
		var rarity: int = int(entry.get("rarity", 0))
		if key.is_empty() or rarity < 2:
			continue
		var mask: int = 0
		var named: Variant = entry.get("surfaces")
		if named is Array:
			for surface_name in named as Array:
				var number: int = surface_named(String(surface_name))
				if number >= 0:
					mask |= 1 << number
		if mask == 0:
			continue
		var beside: String = String(entry.get("beside", ""))
		if not beside.is_empty() and beside != NATURE_BESIDE_WATER:
			continue
		out.append([key, rarity, (SALT_NATURE + i) * _HASH_SALT, mask, beside == NATURE_BESIDE_WATER])
	return out


# Whether a tile is open outdoor floor: Tile.Floor, not indoors. The ground every nature picture
# lies on and every neighbour it may overhang.
static func _open_ground(map: Variant, tx: int, ty: int) -> bool:
	if map == null:
		return false
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return false
	var idx: int = ty * int(map.w) + tx
	if int(map.tiles[idx]) != SimTileMap.Tile.Floor:
		return false
	return int(map.indoors[idx]) != 1


# Whether any of the four neighbours of a tile stands on the water surface: the deep channel and
# the ford both do, and both are what a reed grows beside.
static func _beside_water(map: Variant, tx: int, ty: int) -> bool:
	for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = tx + (step as Vector2i).x
		var ny: int = ty + (step as Vector2i).y
		if nx < 0 or ny < 0 or nx >= int(map.w) or ny >= int(map.h):
			continue
		if int(SimSurface.surface_at(map, nx, ny)) == SimSurface.Surface.Water:
			return true
	return false


# Whether one prepared entry's ground fits a tile whose surface it has already been matched to:
# open floor here and either side, then the water beside it if the entry wants one.
static func _nature_ground_fits(entry: Array, map: Variant, tx: int, ty: int) -> bool:
	if not _open_ground(map, tx, ty):
		return false
	if not (_open_ground(map, tx - 1, ty) and _open_ground(map, tx + 1, ty)):
		return false
	return not bool(entry[4]) or _beside_water(map, tx, ty)


# The picture one tile takes out of the prepared entries: the first whose surface matches, whose
# roll lands and whose ground fits, or "". The tile has to be inside the map. The surface goes
# first because nearly every tile of a district is paving and no entry lies on it, so the roll --
# the costly part -- is only made for the entries the tile's ground could carry. The roll is `hash_at(seed, tx, ty, SALT_NATURE + i)`, shifted before the
# modulo -- hash_at's low bit is only (tx ^ ty ^ seed) & 1, so an even rarity taken straight off it
# would land on one colour of a checkerboard and nowhere else -- written out as
# `(tx * P1) ^ (ty * P2) ^ (seed * P3) ^ (salt * P4)` with the last factor already multiplied in
# `_nature_entries`. It is the same number `hash_at` answers, which check_trees.gd asserts on
# every tile of a hand map, so the copy cannot drift silently.
static func _nature_pick(entries: Array, map: Variant, seed_term: int, tx: int, ty: int) -> String:
	var surface: int = int(map.surfaces[ty * int(map.w) + tx])
	var base: int = (tx * _HASH_TX) ^ (ty * _HASH_TY) ^ seed_term
	for entry in entries:
		if (int(entry[3]) >> surface) & 1 == 0:
			continue
		if (((base ^ int(entry[2])) & 0x7fffffff) >> 8) % int(entry[1]) != 0:
			continue
		if _nature_ground_fits(entry as Array, map, tx, ty):
			return String(entry[0])
	return ""


# The picture lying on one tile, or "". Pure: a hash of the seed, the tile and the entry's index,
# and the tile's own ground. Absent or malformed entries draw nothing, never a default.
static func nature_key(block: Dictionary, map: Variant, seed_val: int, tx: int, ty: int) -> String:
	var entries: Array = _nature_entries(block)
	if entries.is_empty() or map == null:
		return ""
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return ""
	return _nature_pick(entries, map, seed_val * _HASH_SEED, tx, ty)


# Every tile inside `bounds` (the visible AABB in tiles) the observer can see that carries a
# nature picture, as `{tx, ty, key}`. `seen` is the observer's tile set or null for nobody, and
# nobody sees no bushes: the same shape as `tree_tiles`, so draw is a subset of seen. A remembered
# tile draws none -- a memory of a surface is not a memory of the stump on it, the rule litter
# already follows. The observer is asked only about a tile that picked something, which is nearly
# none of them.
static func nature_tiles(block: Dictionary, map: Variant, seen: Variant, seed_val: int, bounds: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if map == null or seen == null:
		return out
	var entries: Array = _nature_entries(block)
	if entries.is_empty():
		return out
	var seed_term: int = seed_val * _HASH_SEED
	var box: Rect2i = _tile_box(map, bounds)
	for ty in range(box.position.y, box.end.y):
		for tx in range(box.position.x, box.end.x):
			var key: String = _nature_pick(entries, map, seed_term, tx, ty)
			if key.is_empty():
				continue
			if (seen as Object).call("has_tile", tx, ty):
				out.append({"tx": tx, "ty": ty, "key": key})
	return out


# The tiles `bounds` (minX/maxX/minY/maxY in tiles) covers, clipped to the map, as a Rect2i whose
# `end` is exclusive.
static func _tile_box(map: Variant, bounds: Dictionary) -> Rect2i:
	var min_x: int = maxi(0, floori(float(bounds.get("minX", 0.0))))
	var max_x: int = mini(int(map.w) - 1, ceili(float(bounds.get("maxX", 0.0))))
	var min_y: int = maxi(0, floori(float(bounds.get("minY", 0.0))))
	var max_y: int = mini(int(map.h) - 1, ceili(float(bounds.get("maxY", 0.0))))
	return Rect2i(min_x, min_y, maxi(0, max_x - min_x + 1), maxi(0, max_y - min_y + 1))


# `nature_tiles` with the picks of each NATURE_CHUNK-square kept in `cache` (`{chunk index: Array
# of {tx, ty, key}}`, owned and reset by the caller). Answers exactly what `nature_tiles` answers
# for the same map, seed and block -- check_trees.gd asserts it on a hand map and on the suburb --
# in the order chunks are walked rather than tile by tile, and only while the cache is valid: the
# picks include the ground test, so a caller resets the cache whenever a tile can have changed
# under it (see main.gd's `_nature_cache_for`).
static func nature_tiles_cached(block: Dictionary, map: Variant, seen: Variant, seed_val: int, bounds: Dictionary, cache: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if map == null or seen == null:
		return out
	var entries: Array = _nature_entries(block)
	if entries.is_empty():
		return out
	var box: Rect2i = _tile_box(map, bounds)
	if box.size.x <= 0 or box.size.y <= 0:
		return out
	var chunks_wide: int = ceili(float(int(map.w)) / float(NATURE_CHUNK))
	for cy in range(_chunk_of(box.position.y), _chunk_of(box.end.y - 1) + 1):
		for cx in range(_chunk_of(box.position.x), _chunk_of(box.end.x - 1) + 1):
			var index: int = cy * chunks_wide + cx
			if not cache.has(index):
				cache[index] = _nature_chunk_picks(entries, map, seed_val, cx, cy)
			for pick in cache[index] as Array:
				var tx: int = int((pick as Dictionary)["tx"])
				var ty: int = int((pick as Dictionary)["ty"])
				if box.has_point(Vector2i(tx, ty)) and (seen as Object).call("has_tile", tx, ty):
					out.append(pick as Dictionary)
	return out


# The chunk a tile coordinate falls in.
static func _chunk_of(tile: int) -> int:
	return floori(float(tile) / float(NATURE_CHUNK))


# Every pick inside one chunk, seen or not, in row-major order.
static func _nature_chunk_picks(entries: Array, map: Variant, seed_val: int, cx: int, cy: int) -> Array:
	var out: Array = []
	var seed_term: int = seed_val * _HASH_SEED
	var x1: int = mini((cx + 1) * NATURE_CHUNK, int(map.w))
	var y1: int = mini((cy + 1) * NATURE_CHUNK, int(map.h))
	for ty in range(cy * NATURE_CHUNK, y1):
		for tx in range(cx * NATURE_CHUNK, x1):
			var key: String = _nature_pick(entries, map, seed_term, tx, ty)
			if not key.is_empty():
				out.append({"tx": tx, "ty": ty, "key": key})
	return out


# --- the furnishings -------------------------------------------------------------------------
# A table, a chair, a shelf and a medical cabinet inside a shell; a dumpster, a concrete barrier, a
# traffic cone and a fence post outside it -- the outpost pack's furnishing props (docs/23,
# "Furnishings and container kinds"), out of the block's `furnishings` list. Each entry is
# `{key, where, surfaces, rarity, beside?}`: the picture, `"indoors"` or `"outdoors"`, the ground
# names (SimSurface's own, lower-case) it may stand on, one tile in `rarity` of them, and
# optionally `"beside": "wall"` for a thing that stands against a wall.
#
# **Dressing, never sim state -- the nature list's rule, held by the same INERT lane.** A
# furnishing is a picture over a Floor tile the sim still sees as open floor: it blocks no step,
# no sightline and no shot, it is not cover, it is not looted, nobody paths round it, and it never
# becomes a component. A body walks across a table and is drawn over it. Two of the pack's
# furnishing props are missing on purpose: the workbench, because the game has a real bench
# (`SimGunsmith`'s `bench` entity) and a picture of one that does nothing would be a lie the
# player could act on, and the three taller than a tile (the fridge, the road sign, the
# streetlamp), which would want the entity sort a tree stands in and are named for a later slice.
#
# The pick is the nature pick's, on its own salts (`SALT_FURNISH` + the entry's index, so
# appending an entry never reshuffles the ones above it) and its own chunk cache. A tile takes a
# furnishing only when it is a Floor tile of the entry's `where` and its east and west neighbours
# are Floor tiles of the same `where`, which keeps a picture off every doorway (a threshold's
# neighbours are a wall and the far side of it) and off a room's edge; `beside: "wall"` asks for a
# wall a step north, south, east or west, and no entry is placed with a door directly north or
# south of it.

# Well clear of SALT_NATURE's block of entries.
const SALT_FURNISH: int = 300

# The one thing a `beside` may name here, and the tile class it means.
const FURNISH_BESIDE_WALL: String = "wall"
const FURNISH_INDOORS: String = "indoors"
const FURNISH_OUTDOORS: String = "outdoors"


# The block's `furnishings` list as plain arrays, one per usable entry, in list order: `[key,
# rarity, salt_term, surface_mask, indoors, beside_wall]` -- `_nature_entries`' shape with the
# ground's `where` and the wall clause in place of the water one. An entry with no key, a rarity
# under two, no real surface or a `where` that is not one of the two is dropped rather than
# carpeting the district; `[]` for a block that declares none. Pure.
static func _furnishing_entries(block: Dictionary) -> Array:
	var out: Array = []
	var listed: Variant = block.get("furnishings")
	if not (listed is Array):
		return out
	for i in (listed as Array).size():
		var raw: Variant = (listed as Array)[i]
		if not (raw is Dictionary):
			continue
		var entry: Dictionary = raw as Dictionary
		var key: String = String(entry.get("key", ""))
		var rarity: int = int(entry.get("rarity", 0))
		if key.is_empty() or rarity < 2:
			continue
		var where: String = String(entry.get("where", ""))
		if where != FURNISH_INDOORS and where != FURNISH_OUTDOORS:
			continue
		var mask: int = 0
		var named: Variant = entry.get("surfaces")
		if named is Array:
			for surface_name in named as Array:
				var number: int = surface_named(String(surface_name))
				if number >= 0:
					mask |= 1 << number
		if mask == 0:
			continue
		var beside: String = String(entry.get("beside", ""))
		if not beside.is_empty() and beside != FURNISH_BESIDE_WALL:
			continue
		out.append([key, rarity, (SALT_FURNISH + i) * _HASH_SALT, mask, where == FURNISH_INDOORS, beside == FURNISH_BESIDE_WALL])
	return out


# Whether a tile is a Floor tile whose indoor-ness is `indoors`: the ground a furnishing stands on
# and every neighbour it may overhang.
static func _floor_of(map: Variant, tx: int, ty: int, indoors: bool) -> bool:
	if map == null:
		return false
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return false
	var idx: int = ty * int(map.w) + tx
	if int(map.tiles[idx]) != SimTileMap.Tile.Floor:
		return false
	return (int(map.indoors[idx]) == 1) == indoors


# Whether a tile is a wall: the solid mass a shelf or a dumpster stands against.
static func _wall_at(map: Variant, tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return false
	return int(map.tiles[ty * int(map.w) + tx]) == SimTileMap.Tile.Wall


static func _door_at(map: Variant, tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return false
	return int(map.tiles[ty * int(map.w) + tx]) == SimTileMap.Tile.Door


# Whether one prepared entry's ground fits a tile already matched to its `where` and its surface.
static func _furnishing_ground_fits(entry: Array, map: Variant, tx: int, ty: int) -> bool:
	var indoors: bool = bool(entry[4])
	if not (_floor_of(map, tx - 1, ty, indoors) and _floor_of(map, tx + 1, ty, indoors)):
		return false
	if _door_at(map, tx, ty - 1) or _door_at(map, tx, ty + 1):
		return false
	if not bool(entry[5]):
		return true
	return _wall_at(map, tx, ty - 1) or _wall_at(map, tx, ty + 1) or _wall_at(map, tx - 1, ty) or _wall_at(map, tx + 1, ty)


# The picture one tile takes out of the prepared entries: the first whose `where` and surface
# match, whose roll lands and whose ground fits, or "". The roll is `nature`'s -- `hash_at` shifted
# before the modulo, written out with the salt already multiplied.
static func _furnishing_pick(entries: Array, map: Variant, seed_term: int, tx: int, ty: int) -> String:
	var idx: int = ty * int(map.w) + tx
	if int(map.tiles[idx]) != SimTileMap.Tile.Floor:
		return ""
	var indoors: bool = int(map.indoors[idx]) == 1
	var surface: int = int(map.surfaces[idx])
	var base: int = (tx * _HASH_TX) ^ (ty * _HASH_TY) ^ seed_term
	for entry in entries:
		if bool(entry[4]) != indoors:
			continue
		if (int(entry[3]) >> surface) & 1 == 0:
			continue
		if (((base ^ int(entry[2])) & 0x7fffffff) >> 8) % int(entry[1]) != 0:
			continue
		if _furnishing_ground_fits(entry as Array, map, tx, ty):
			return String(entry[0])
	return ""


# The picture standing on one tile, or "". Pure: a hash of the seed, the tile and the entry's
# index, and the tile's own ground. Absent or malformed entries draw nothing, never a default.
static func furnishing_key(block: Dictionary, map: Variant, seed_val: int, tx: int, ty: int) -> String:
	var entries: Array = _furnishing_entries(block)
	if entries.is_empty() or map == null:
		return ""
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return ""
	return _furnishing_pick(entries, map, seed_val * _HASH_SEED, tx, ty)


# Every tile inside `bounds` the observer can see that carries a furnishing, as `{tx, ty, key}`.
# `seen` is the observer's tile set or null for nobody, and nobody sees no furniture: the same shape
# as `nature_tiles`, so draw is a subset of seen. A remembered tile draws none -- a memory of a
# floor is not a memory of the chair on it.
static func furnishing_tiles(block: Dictionary, map: Variant, seen: Variant, seed_val: int, bounds: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if map == null or seen == null:
		return out
	var entries: Array = _furnishing_entries(block)
	if entries.is_empty():
		return out
	var seed_term: int = seed_val * _HASH_SEED
	var box: Rect2i = _tile_box(map, bounds)
	for ty in range(box.position.y, box.end.y):
		for tx in range(box.position.x, box.end.x):
			var key: String = _furnishing_pick(entries, map, seed_term, tx, ty)
			if key.is_empty():
				continue
			if (seen as Object).call("has_tile", tx, ty):
				out.append({"tx": tx, "ty": ty, "key": key})
	return out


# `furnishing_tiles` with the picks of each NATURE_CHUNK-square kept in `cache` (owned and reset by
# the caller, exactly as the nature cache is: never a static, because one gate process boots two
# worlds). Answers what `furnishing_tiles` answers for the same map, seed and block.
static func furnishing_tiles_cached(block: Dictionary, map: Variant, seen: Variant, seed_val: int, bounds: Dictionary, cache: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if map == null or seen == null:
		return out
	var entries: Array = _furnishing_entries(block)
	if entries.is_empty():
		return out
	var box: Rect2i = _tile_box(map, bounds)
	if box.size.x <= 0 or box.size.y <= 0:
		return out
	var chunks_wide: int = ceili(float(int(map.w)) / float(NATURE_CHUNK))
	for cy in range(_chunk_of(box.position.y), _chunk_of(box.end.y - 1) + 1):
		for cx in range(_chunk_of(box.position.x), _chunk_of(box.end.x - 1) + 1):
			var index: int = cy * chunks_wide + cx
			if not cache.has(index):
				cache[index] = _furnishing_chunk_picks(entries, map, seed_val, cx, cy)
			for pick in cache[index] as Array:
				var tx: int = int((pick as Dictionary)["tx"])
				var ty: int = int((pick as Dictionary)["ty"])
				if box.has_point(Vector2i(tx, ty)) and (seen as Object).call("has_tile", tx, ty):
					out.append(pick as Dictionary)
	return out


static func _furnishing_chunk_picks(entries: Array, map: Variant, seed_val: int, cx: int, cy: int) -> Array:
	var out: Array = []
	var seed_term: int = seed_val * _HASH_SEED
	var x1: int = mini((cx + 1) * NATURE_CHUNK, int(map.w))
	var y1: int = mini((cy + 1) * NATURE_CHUNK, int(map.h))
	for ty in range(cy * NATURE_CHUNK, y1):
		for tx in range(cx * NATURE_CHUNK, x1):
			var key: String = _furnishing_pick(entries, map, seed_term, tx, ty)
			if not key.is_empty():
				out.append({"tx": tx, "ty": ty, "key": key})
	return out


# --- the building materials ----------------------------------------------------------------
# `walls`, `roofs` and `faces` in the dressing block: a material name (a template's `look`)
# to the keys the renderer blits. "" for anything the block does not declare, which every
# caller reads as "draw the procedural fallback" -- a district dressed before looks existed,
# or a material nobody has drawn yet, still draws as it did. Which tile takes a cap, a face, a
# door or a roof is roof_look.gd's business; this only names the picture.
static func wall_key(block: Dictionary, material: String, face: bool) -> String:
	var walls: Variant = block.get("walls")
	if not (walls is Dictionary):
		return ""
	var entry: Variant = (walls as Dictionary).get(material)
	if not (entry is Dictionary):
		return ""
	return String((entry as Dictionary).get("face" if face else "cap", ""))


static func _roof_entry(block: Dictionary, material: String) -> Dictionary:
	var roofs: Variant = block.get("roofs")
	if not (roofs is Dictionary):
		return {}
	var entry: Variant = (roofs as Dictionary).get(material)
	return entry as Dictionary if entry is Dictionary else {}


# A pitched material declares a north and a south half; a flat one declares one sheet.
static func roof_pitched(block: Dictionary, material: String) -> bool:
	var entry: Dictionary = _roof_entry(block, material)
	return entry.has("n") and entry.has("s")


static func roof_key(block: Dictionary, material: String, slope: int) -> String:
	var entry: Dictionary = _roof_entry(block, material)
	match slope:
		1:
			return String(entry.get("n", ""))
		2:
			return String(entry.get("s", ""))
		_:
			return String(entry.get("flat", ""))


# `kind` is "window", "door" or "garage": the picture composited over a face or a doorway.
static func face_key(block: Dictionary, kind: String) -> String:
	var faces: Variant = block.get("faces")
	if not (faces is Dictionary):
		return ""
	return String((faces as Dictionary).get(kind, ""))


# Whether a tile is outdoor open floor carrying `surface` -- the eligibility both scatters share.
static func _ground_is(map: Variant, tx: int, ty: int, surface: int) -> bool:
	if map == null:
		return false
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return false
	var idx: int = ty * int(map.w) + tx
	if int(map.tiles[idx]) != SimTileMap.Tile.Floor:
		return false
	if int(map.indoors[idx]) == 1:
		return false
	return int(SimSurface.surface_at(map, tx, ty)) == surface


# A scrap of litter on street pavement, or "". Two independent hashes: one decides whether this
# tile carries anything at all (1 in LITTER_RARITY), the other which scrap it is -- so making the
# scatter denser cannot silently reshuffle which key lands where.
static func litter_key(block: Dictionary, map: Variant, seed_val: int, tx: int, ty: int) -> String:
	if not _ground_is(map, tx, ty, SimSurface.Surface.Paved):
		return ""
	var keys: Variant = block.get("litter")
	if not (keys is Array) or (keys as Array).is_empty():
		return ""
	if hash_at(seed_val, tx, ty, SALT_LITTER_PICK) % LITTER_RARITY != 0:
		return ""
	var index: int = variant_index(seed_val, tx, ty, SALT_LITTER_KEY, (keys as Array).size())
	return String((keys as Array)[index])


# Broken concrete over a rubble tile, or "". Every rubble tile takes one: the surface is already
# the sparse thing (the worldgen rubble pass places ~3% of a district), and a rubble tile with no
# rubble drawn on it is the flat tint slice 2 shipped.
static func rubble_key(block: Dictionary, map: Variant, seed_val: int, tx: int, ty: int) -> String:
	if not _ground_is(map, tx, ty, SimSurface.Surface.Rubble):
		return ""
	var keys: Variant = block.get("rubble")
	if not (keys is Array) or (keys as Array).is_empty():
		return ""
	var index: int = variant_index(seed_val, tx, ty, SALT_RUBBLE_KEY, (keys as Array).size())
	return String((keys as Array)[index])
