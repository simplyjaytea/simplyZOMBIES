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
const SimBootRes = preload("res://sim/boot.gd")
const Appearance = preload("res://presentation/appearance.gd")
const RoadPaint = preload("res://presentation/road_paint.gd")

# The one dressing entry presentation asks for. Named here so main.gd carries no content id, the
# same rule PROP_KINDS and PLAYER_LOOK_ID follow.
const BLOCK_ID: String = "dressing.street"

# Scraps are dealt by block (`_block_litter`): the floor is cut into LITTER_BLOCK-square blocks, and
# each block takes one scrap per LITTER_TENTHS / 10 of its paved floor, the street's and a room's
# counted apart. The tile's litter weight (`_litter_weight`: its block's clutter and its walls and
# kerbs) only says which of a block's tiles take them, so the floor keeps its gradient toward kerbs
# and walls without the clumps and the bare stretches a per-tile roll laid down (A12's round-2 review
# counted 1 in 4.4 on one side of a street and 1 in 12 on the other, and a small room, all edge, ran
# at 1 in 3.6). It was 1 in 17, evenly, until the A12 density slice, whose before shots read as bare
# street. Set so the kept rate lands near 1 in 6 of the visible floor as A12's measure counts it.
# Measured, not a reference.
const LITTER_BLOCK: int = 6
const LITTER_TENTHS: int = 55

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
# Which way a scrap of litter faces, and which way a flat picture is mirrored: its own salts, so
# a flip cannot correlate with the roll that placed the picture.
const SALT_LITTER_FLIP: int = 11
# Whether a scrap is also turned top to bottom (a half turn, with the mirror), and which of the
# block's `litter_tints` it takes: the pack draws one crumpled paper, so a street of it is a street
# of one stamp unless its turns and its grime vary.
const SALT_LITTER_FLIP_V: int = 14
const SALT_LITTER_TINT: int = 15
const SALT_FLIP: int = 402

# Which tile keeps a picture where two would meet (the overlap rule, `_kept_top`): one rank per kind
# of picture, highest first, and the hash that breaks a tie within a rank.
const RANK_NATURE: int = 1
const RANK_FLAT: int = 2
const RANK_STANDING: int = 3
# What the sim holds on a tile (a vehicle's Low tile, a tree, a placed prop): never drawn by the
# dressing, but it beats every picture that would meet it.
const RANK_HELD: int = 9
const SALT_WINNER: int = 403

# The largest side a picture may have in art pixels: a canvas in the block's `sizes` is checked
# against it, so a fabricated size cannot make a picture that covers the district.
const MAX_EXTENT: int = 64
# Where a flat picture sits inside its tile: one salt per axis, never the placement roll's.
const SALT_JITTER_X: int = 400
const SALT_JITTER_Y: int = 401
# A scrap of litter's own placement salts: no tile holds a scrap and a furnishing, but its offset
# should not lean on that rule to stay independent.
const SALT_LITTER_JITTER_X: int = 12
const SALT_LITTER_JITTER_Y: int = 13
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
# the tile's own ground, and the overlap rule (`_kept_top`). Absent or malformed entries draw
# nothing, never a default.
static func nature_key(block: Dictionary, map: Variant, seed_val: int, tx: int, ty: int) -> String:
	if map == null or _nature_entries(block).is_empty():
		return ""
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return ""
	return _kept_key(occupancy(block, map, seed_val), map, tx, ty, RANK_NATURE, RANK_NATURE)


# Every tile inside `bounds` (the visible AABB in tiles) the observer can see that carries a
# nature picture, as `{tx, ty, key}`. `seen` is the observer's tile set or null for nobody, and
# nobody sees no bushes: the same shape as `tree_tiles`, so draw is a subset of seen. A remembered
# tile draws none -- a memory of a surface is not a memory of the stump on it, the rule litter
# already follows. The observer is asked only about a tile that picked something, which is nearly
# none of them.
static func nature_tiles(block: Dictionary, map: Variant, seen: Variant, seed_val: int, bounds: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if map == null or seen == null or _nature_entries(block).is_empty():
		return out
	var occ: Dictionary = occupancy(block, map, seed_val)
	var box: Rect2i = _tile_box(map, bounds)
	for ty in range(box.position.y, box.end.y):
		for tx in range(box.position.x, box.end.x):
			var key: String = _kept_key(occ, map, tx, ty, RANK_NATURE, RANK_NATURE)
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
	if map == null or seen == null or _nature_entries(block).is_empty():
		return out
	var box: Rect2i = _tile_box(map, bounds)
	if box.size.x <= 0 or box.size.y <= 0:
		return out
	var occ: Dictionary = {}
	var chunks_wide: int = ceili(float(int(map.w)) / float(NATURE_CHUNK))
	for cy in range(_chunk_of(box.position.y), _chunk_of(box.end.y - 1) + 1):
		for cx in range(_chunk_of(box.position.x), _chunk_of(box.end.x - 1) + 1):
			var index: int = cy * chunks_wide + cx
			if not cache.has(index):
				if occ.is_empty():
					occ = occupancy(block, map, seed_val)
				cache[index] = _chunk_picks(occ, map, cx, cy, RANK_NATURE, RANK_NATURE)
			for pick in cache[index] as Array:
				var tx: int = int((pick as Dictionary)["tx"])
				var ty: int = int((pick as Dictionary)["ty"])
				if box.has_point(Vector2i(tx, ty)) and (seen as Object).call("has_tile", tx, ty):
					out.append(pick as Dictionary)
	return out


# The chunk a tile coordinate falls in.
static func _chunk_of(tile: int) -> int:
	return floori(float(tile) / float(NATURE_CHUNK))


# Every pick inside one chunk whose rank lies between `lowest` and `highest`, seen or not, in
# row-major order.
static func _chunk_picks(occ: Dictionary, map: Variant, cx: int, cy: int, lowest: int, highest: int) -> Array:
	var out: Array = []
	var x1: int = mini((cx + 1) * NATURE_CHUNK, int(map.w))
	var y1: int = mini((cy + 1) * NATURE_CHUNK, int(map.h))
	for ty in range(cy * NATURE_CHUNK, y1):
		for tx in range(cx * NATURE_CHUNK, x1):
			var key: String = _kept_key(occ, map, tx, ty, lowest, highest)
			if not key.is_empty():
				out.append({"tx": tx, "ty": ty, "key": key})
	return out


# --- the furnishings -------------------------------------------------------------------------
# A table, a chair, a shelf, a medical cabinet and a fridge inside a shell; a dumpster, a concrete barrier,
# a traffic cone, a fence post, a road sign and a streetlamp outside it -- the outpost pack's furnishing props (docs/23,
# "Furnishings and container kinds"), out of the block's `furnishings` list. Each entry is
# `{key, where, surfaces, rarity, beside?, group?, standing?}`: the picture, `"indoors"` or
# `"outdoors"`, the ground names (SimSurface's own, lower-case) it may stand on, how often it lands,
# and optionally where it stands and what it stands with.
#
# **Dressing, never sim state -- the nature list's rule, held by the same INERT lane.** A
# furnishing is a picture over a Floor tile the sim still sees as open floor: it blocks no step,
# no sightline and no shot, it is not cover, it is not looted, nobody paths round it, and it never
# becomes a component. A body walks across a table and is drawn over it. The workbench is missing
# on purpose: the game has a real bench (`SimGunsmith`'s `bench` entity) and a picture of one that
# does nothing would be a lie the player could act on. The three taller than a tile (the fridge,
# the road sign, the streetlamp) say `standing` and join the entity sort a tree stands in.
#
# Where a picture may stand is one rule for every entry: its art rect, at the offset it is placed
# at, must lie over Floor tiles of its own `where` whose ground its `surfaces` list names, on its
# own row (`_footprint_fits`) -- so a dumpster that would hang over the grass verge is refused rather
# than drawn half on the kerb -- and no door may stand directly north or south of it.
#
# How often, and next to what, are four shapes, read by `_furnishing_raw` and `_group_top`:
#
#   * **A plain roll** (no `beside`, no `group`): one tile in `rarity`, the nature roll's arithmetic
#     on the entry's own salt. Indoors that is the whole rule. **Outdoors the roll is weighted**
#     (`_weight`): three times as likely within a tile of a wall, a parked car or a kerb, and more
#     likely again in some blocks of the street than others (`_clutter`), so barrels, pallets and
#     cones gather along the edges and in piles the way a street's junk does, instead of an even
#     sprinkle over the asphalt.
#   * **`"beside": "wall"`**: as above, with a wall within one tile -- or, on paved ground only, the
#     kerb, an unpaved tile within one. A trash bag on the lawn needs a wall; on the pavement it
#     may stand at the kerb.
#   * **`"beside": "edge"`**: at the street's edge (`_edge_at`) -- a wall or a parked car within one,
#     the kerb, or the sidewalk slab -- so barrels and pallets stand along the street, never out in
#     the middle of the carriageway.
#   * **`"beside": "wall_north"`**: against the wall directly north of it, in runs. The wall row is
#     cut into RUN_TILES segments, one segment in `rarity` carries the entry, and in a segment that
#     does every other tile does, so shelves stand side by side along a wall rather than one here
#     and one there. The pack draws these from the front, so they stand only with their backs to a
#     north wall.
#   * **`"group": "table"` and `"group": "seat"`** (`_group_top`): the room's tables and the chairs at
#     them. A table is one per `rarity` floor tiles: the floor is cut into square cells of that many
#     tiles, each cell tries up to CELL_CANDIDATES hashed tiles inside it and keeps the first whose
#     eight neighbours are all its own room's floor, so a table stands out in the room with space
#     round it. A seat entry puts one to three chairs at each table, on its four sides (each side one
#     in the seat's `rarity`, never none and never all four), each placed flush against the table's
#     own art so the two never meet. Cells make tables spread across a whole room; the hashed tile
#     inside each, and the cells that skip, keep them off a lattice.
#
# The overlap rule (`_kept_top`) runs over all of it, so a chair that would meet a shelf still
# gives way. And anything the sim stands on a tile -- a heap or a parked car on a Low tile, a tree,
# a container, a bed, a campfire (`occupancy`'s `props`) -- holds its tile and its picture's rect
# against every picture here (RANK_HELD).

# Well clear of SALT_NATURE's block of entries.
const SALT_FURNISH: int = 300

# How far dressing keeps off the colony's start, in tiles (Chebyshev). The square is one tile
# wider than the three tiles check_trees.gd holds it to: a picture hangs across the tiles it
# overlaps, so a shelf on the square's edge reached into the three-tile zone it was meant to keep
# clear. Litter keeps off the same square.
const FURNISH_CLEAR: int = 4

# A flat picture is placed in whole art pixels. A tile is ART_PER_TILE art pixels across, and its
# jitter is at most JITTER_PX of them either way, so every placement lands on the art grid the
# ground is drawn on at any zoom (one art pixel is blit_scale screen pixels). A picture that fits in
# a tile is jittered only as far as keeps it inside its tile (`_range_x`, `_range_y`); a wider one
# overhangs by its own width anyway, and the footprint rule judges the tiles it reaches.
const ART_PER_TILE: int = 32
const JITTER_PX: int = 6

# The fields a furnishing entry is read by, in `_furnishing_entries`' arrays.
const FE_KEY: int = 0
const FE_RARITY: int = 1
const FE_SALT: int = 2
const FE_MASK: int = 3
const FE_INDOORS: int = 4
const FE_BESIDE: int = 5
const FE_STANDING: int = 6
const FE_GROUP: int = 7
const FE_INDEX: int = 8
const FE_EXTENT: int = 9
const FE_CLUSTER: int = 10
const FE_PER_ROOM: int = 11
const FE_KEPT: int = 12
const FE_SHADOW: int = 13
const FE_ROOMS: int = 14

# What an indoor entry's `rooms` may name: any room (the default), a storage room (a room of a
# building the block lists under `storage`) or a living room (any other).
const ROOMS_ANY: int = 0
const ROOMS_STORAGE: int = 1
const ROOMS_LIVING: int = 2

# What a `roll` may name: the default, and the street furniture's roll as it was before A12 (`_kept_pick`).
const FURNISH_ROLL_KEPT: String = "kept"

# What a `beside` may name here, and what each means.
const FURNISH_BESIDE_WALL: String = "wall"
const FURNISH_BESIDE_WALL_NORTH: String = "wall_north"
const FURNISH_BESIDE_EDGE: String = "edge"
const FURNISH_INDOORS: String = "indoors"
const FURNISH_OUTDOORS: String = "outdoors"
const BESIDE_NONE: int = 0
const BESIDE_WALL: int = 1
const BESIDE_WALL_NORTH: int = 2
const BESIDE_EDGE: int = 3

# What a `group` may name here.
const FURNISH_GROUP_TABLE: String = "table"
const FURNISH_GROUP_SEAT: String = "seat"
const GROUP_NONE: int = 0
const GROUP_TABLE: int = 1
const GROUP_SEAT: int = 2

# A wall run's segment, in tiles: shelves stand together along this much of a wall.
const RUN_TILES: int = 4
# How many tiles of a cell are tried for its table, and one cell in CELL_SKIP stands none.
const CELL_CANDIDATES: int = 6
const CELL_SKIP: int = 12
# The outdoor weighting: a block of the street is CLUTTER_BLOCK tiles square, and its clutter is one of
# CLUTTER_WEIGHTS by a hash of the block; an edge tile weighs EDGE_WEIGHT times an open one, and the
# roll is out of `rarity * WEIGHT_DEN`, so the average tile of a street lands near one in `rarity`.
const CLUTTER_BLOCK: int = 4
const CLUTTER_WEIGHTS: Array[int] = [0, 0, 0, 1, 1, 2, 2, 3, 3, 4]
const EDGE_WEIGHT: int = 3
const WEIGHT_DEN: int = 4
# A `cluster` entry's spacing: each row of the street is cut into SPACING_TILES segments (moved by a
# hash of the row), and only one hashed tile of each may take a cluster pick, so the junk along a
# sidewalk gathers in knots with gaps rather than standing in a picket line.
const SPACING_TILES: int = 3
# One table in PAIR_ODDS stands alone; the rest stand with a second pushed against their east end, a
# long table of two, wherever the tile east of them has room.
const PAIR_ODDS: int = 4
# A paired table's two halves sit this many art pixels west and east of their tiles' centre lines.
# The pack's table is 34 opaque pixels wide (columns 3 to 36 of its 40-pixel canvas), so one pixel
# each way butts the two tops edge to edge with no gap between them: a long table, not two.
const PAIR_SHIFT: int = 1

# The salts the placement rules hash on, one per decision.
const SALT_CELL: int = 404
const SALT_CELL_X: int = 405
const SALT_CELL_Y: int = 406
const SALT_CELL_OFFSET: int = 407
const SALT_SEAT: int = 410
const SALT_SEAT_OFFSET: int = 416
const SALT_RUN: int = 420
const SALT_RUN_PHASE: int = 440
const SALT_RUN_OFFSET: int = 460
const SALT_CLUTTER: int = 480
const SALT_CLUTTER_OFFSET: int = 481
const SALT_PAIR: int = 600
const SALT_SPACE: int = 620
const SALT_SPACE_OFFSET: int = 621
const SALT_ROOM: int = 700
const SALT_LITTER_BLOCK: int = 640
const SALT_LITTER_BLOCK_OFFSET: int = 641
const SALT_LITTER_ROOM: int = 642
# The order a room's pieces are judged in when it keeps its passages (`_room_drops`).
const SALT_PASSAGE: int = 646

# The four sides of a table, in the order a seat mask's bits name them: north, east, south, west.
const SIDES: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


# The block's `furnishings` list as plain arrays, one per usable entry, in list order, read by the
# FE_ indices: the key, the rarity, `hash_at`'s salt term for the entry's own salt, a surface mask
# with bit `n` set for each SimSurface number `n` it may stand on, whether it is an indoor entry,
# its `beside` and `group` codes, its standing flag, its index in the list, its size in art pixels
# (Vector2i.ZERO when the block's `sizes` has none, which the footprint rule refuses), its `cluster`
# flag, its `per_room` cap (0 for none), whether it rolls `kept` and whether it is a `shadow`.
#
# The salt is the entry's `salt` when it names one, else its index in the list: a pinned salt keeps
# an entry's rolls where they were when the list around it changes, so a pass that adds junk to the
# street cannot re-roll the barriers and lamps already standing there. An entry with no key, a
# rarity under two, no real surface, a `where` that is not one of the two, a `beside` or `group` the
# rules do not know, a negative `salt` or `per_room`, a `per_room` outdoors or a salt another entry
# already took is dropped rather than carpeting the district; `[]` for a block that declares none.
# Pure.
static func _furnishing_entries(block: Dictionary) -> Array:
	var out: Array = []
	var listed: Variant = block.get("furnishings")
	if not (listed is Array):
		return out
	var sizes: Dictionary = _sizes(block)
	var taken: Dictionary = {}
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
		var beside: int = _beside_code(String(entry.get("beside", "")))
		var group: int = _group_code(String(entry.get("group", "")))
		if beside < 0 or group < 0:
			continue
		var salt: int = int(entry.get("salt", i))
		var per_room: int = int(entry.get("per_room", 0))
		if salt < 0 or per_room < 0 or (per_room > 0 and where != FURNISH_INDOORS) or taken.has(salt):
			continue
		var roll: String = String(entry.get("roll", ""))
		if not roll.is_empty() and roll != FURNISH_ROLL_KEPT:
			continue
		var kept: bool = roll == FURNISH_ROLL_KEPT
		var shadow: bool = bool(entry.get("shadow", false))
		var rooms_name: String = String(entry.get("rooms", ""))
		var rooms: int = ROOMS_ANY
		match rooms_name:
			"":
				rooms = ROOMS_ANY
			"storage":
				rooms = ROOMS_STORAGE
			"living":
				rooms = ROOMS_LIVING
			_:
				continue
		if rooms != ROOMS_ANY and where != FURNISH_INDOORS:
			continue
		if (kept and (group != GROUP_NONE or per_room > 0 or bool(entry.get("cluster", false)))) or (shadow and not kept):
			continue
		taken[salt] = true
		out.append([key, rarity, (SALT_FURNISH + salt) * _HASH_SALT, mask, where == FURNISH_INDOORS, beside, bool(entry.get("standing", false)), group, i, sizes.get(key, Vector2i.ZERO), bool(entry.get("cluster", false)), per_room, kept, shadow, rooms])
	return out


# A `beside` name's code, or -1 for a name the rules do not know.
static func _beside_code(beside: String) -> int:
	match beside:
		"":
			return BESIDE_NONE
		FURNISH_BESIDE_WALL:
			return BESIDE_WALL
		FURNISH_BESIDE_WALL_NORTH:
			return BESIDE_WALL_NORTH
		FURNISH_BESIDE_EDGE:
			return BESIDE_EDGE
	return -1


# A `group` name's code, or -1 for a name the rules do not know.
static func _group_code(group: String) -> int:
	match group:
		"":
			return GROUP_NONE
		FURNISH_GROUP_TABLE:
			return GROUP_TABLE
		FURNISH_GROUP_SEAT:
			return GROUP_SEAT
	return -1


# `hash_at(seed, tx, ty, salt)` from the seed's term, so the rules that already carry the term need
# not carry the seed as well. The same number, by construction: hash_at's own arithmetic.
static func _hash_t(seed_term: int, tx: int, ty: int, salt: int) -> int:
	return ((tx * _HASH_TX) ^ (ty * _HASH_TY) ^ seed_term ^ (salt * _HASH_SALT)) & 0x7fffffff


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


# Whether an outdoor tile off the paving lies within one tile of this one: a grass or dirt tile
# that is this pavement's kerb.
static func _kerb_within_one(map: Variant, tx: int, ty: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var nx: int = tx + dx
			var ny: int = ty + dy
			if (dx != 0 or dy != 0) and _floor_of(map, nx, ny, false) and int(SimSurface.surface_at(map, nx, ny)) != SimSurface.Surface.Paved:
				return true
	return false


# Whether any of the eight tiles round this one is a wall: a shelf, a cabinet, a dumpster or a
# trash bag stands within one tile of the solid mass it is set against.
static func _wall_within_one(map: Variant, tx: int, ty: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if (dx != 0 or dy != 0) and _wall_at(map, tx + dx, ty + dy):
				return true
	return false


# Whether one of the four tiles straight beside this one is a wall.
static func _wall_beside(map: Variant, tx: int, ty: int) -> bool:
	for side in SIDES:
		if _wall_at(map, tx + side.x, ty + side.y):
			return true
	return false


# Whether one of the four tiles straight beside this one is a window: the tile in front of it.
static func _window_beside(map: Variant, tx: int, ty: int) -> bool:
	for side in SIDES:
		if _tile_is(map, tx + side.x, ty + side.y, SimTileMap.Tile.Window):
			return true
	return false


# Whether a picture's art rect, in its own tile's frame, covers a tile in front of a window: any tile
# of its row with a window straight beside it. A shelf anchored beside the window tile is wider than
# its tile and would still stand across the light.
static func _reaches_window(map: Variant, rect: Rect2i, tx: int, ty: int) -> bool:
	var first: int = floori(float(rect.position.x) / float(ART_PER_TILE))
	var last: int = floori(float(rect.end.x - 1) / float(ART_PER_TILE))
	for dx in range(first, last + 1):
		if _window_beside(map, tx + dx, ty):
			return true
	return false


# Whether a tile is a wall: the solid mass a shelf or a dumpster stands against.
static func _wall_at(map: Variant, tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return false
	return int(map.tiles[ty * int(map.w) + tx]) == SimTileMap.Tile.Wall


static func _door_at(map: Variant, tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return false
	return int(map.tiles[ty * int(map.w) + tx]) == SimTileMap.Tile.Door


static func _tile_is(map: Variant, tx: int, ty: int, tile: int) -> bool:
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return false
	return int(map.tiles[ty * int(map.w) + tx]) == tile


# Whether a tile is an edge of the street: a wall or a Low tile (a parked car, a heap) within one,
# or, on paved ground, the kerb, or a sidewalk slab of the street's paint (`road`, RoadPaint's mask,
# empty for a map with no street manifest), or, off the paving, the verge -- a grass or dirt tile
# with outdoor paving beside it. Where a street's junk gathers.
static func _edge_at(map: Variant, tx: int, ty: int, road: PackedByteArray = PackedByteArray()) -> bool:
	if not road.is_empty() and road[ty * int(map.w) + tx] == RoadPaint.MASK_SIDEWALK:
		return true
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			if _wall_at(map, tx + dx, ty + dy) or _tile_is(map, tx + dx, ty + dy, SimTileMap.Tile.Low):
				return true
	if int(SimSurface.surface_at(map, tx, ty)) == SimSurface.Surface.Paved:
		return _kerb_within_one(map, tx, ty)
	for side in SIDES:
		if _floor_of(map, tx + side.x, ty + side.y, false) and int(SimSurface.surface_at(map, tx + side.x, ty + side.y)) == SimSurface.Surface.Paved:
			return true
	return false


# How cluttered a tile's block of the street is: one of CLUTTER_WEIGHTS by a hash of the block, on a
# grid moved by the seed so it does not line up with the blocks the layout drew.
static func _clutter(seed_term: int, tx: int, ty: int) -> int:
	var shift: int = _mix(_hash_t(seed_term, 0, 0, SALT_CLUTTER_OFFSET))
	var bx: int = floori(float(tx + shift % CLUTTER_BLOCK) / float(CLUTTER_BLOCK))
	var by: int = floori(float(ty + (shift >> 8) % CLUTTER_BLOCK) / float(CLUTTER_BLOCK))
	return CLUTTER_WEIGHTS[_mix(_hash_t(seed_term, bx, by, SALT_CLUTTER)) % CLUTTER_WEIGHTS.size()]


# A paved tile's weight for the litter roll. In a room: one, plus its block's clutter, plus one at a
# wall -- never nought, so no room is swept clean, and at most six.
# On the street: nought in a clean block, so the street keeps its open stretches, else two or three
# by the block's clutter, plus one at an edge -- held to four, so a cluttered block is strewn rather
# than carpeted, the clumps the furnishings' own weight (up to twelve) laid down when litter shared it.
static func _litter_weight(map: Variant, seed_term: int, tx: int, ty: int, road: PackedByteArray = PackedByteArray()) -> int:
	var clutter: int = _clutter(seed_term, tx, ty)
	var edge: int = 1 if _edge_at(map, tx, ty, road) else 0
	if int(map.indoors[ty * int(map.w) + tx]) == 1:
		return 1 + clutter + edge
	if clutter == 0:
		return 0
	return 1 + mini(clutter, 2) + edge


# An outdoor tile's weight for the street rolls: EDGE_WEIGHT at an edge, times its block's clutter,
# never under one -- a clean block thins the street's junk, it does not empty a whole row of it.
static func _weight(map: Variant, seed_term: int, tx: int, ty: int, road: PackedByteArray = PackedByteArray()) -> int:
	return (EDGE_WEIGHT if _edge_at(map, tx, ty, road) else 1) * maxi(1, _clutter(seed_term, tx, ty))


# Whether a weighted roll lands: `roll` out of `rarity * WEIGHT_DEN`, under the weight. A weight that
# would land on every tile is held one short of it.
static func _weighted_hit(roll: int, rarity: int, weight: int) -> bool:
	return _hit_in(roll, rarity * WEIGHT_DEN, weight)


# Whether `roll` out of `span` lands under `weight`, held one short of every tile.
static func _hit_in(roll: int, span: int, weight: int) -> bool:
	return roll % span < mini(weight, span - 1)


# The horizontal offsets a picture `w` art pixels wide may take: the jitter, narrowed so a picture
# that fits in a tile stays inside it. `Vector2i(lo, hi)`, both inclusive.
static func _range_x(w: int) -> Vector2i:
	if w <= ART_PER_TILE:
		return Vector2i(maxi(-JITTER_PX, (w >> 1) - (ART_PER_TILE >> 1)), mini(JITTER_PX, (ART_PER_TILE >> 1) - w + (w >> 1)))
	return Vector2i(-JITTER_PX, JITTER_PX)


# The vertical offsets a picture `h` art pixels tall may take: its base lifted up to JITTER_PX off its
# tile's south edge and never past it, and never so far that a picture that fits in a tile leaves it.
# A picture taller than a tile stands on the edge.
static func _range_y(h: int) -> Vector2i:
	if h <= ART_PER_TILE:
		return Vector2i(maxi(-JITTER_PX, h - ART_PER_TILE), 0)
	return Vector2i(0, 0)


static func _pick_in(span: Vector2i, roll: int) -> int:
	return span.x + roll % (span.y - span.x + 1)


# Where a plain-roll picture sits in its tile, `Vector2i(ox, oy)` in whole art pixels: hashed inside
# its ranges, on the jitter salts. A standing picture is drawn feet-anchored on the tile's south-edge
# centre (main.gd's `_blit_standing`), so it takes no offset; a piece against a north wall keeps its
# top on the wall.
static func _offsets_for(entry: Array, seed_term: int, tx: int, ty: int) -> Vector2i:
	var size: Vector2i = entry[FE_EXTENT]
	if bool(entry[FE_STANDING]):
		return Vector2i.ZERO
	var ox: int = _pick_in(_range_x(size.x), _mix(_hash_t(seed_term, tx, ty, SALT_JITTER_X)))
	if int(entry[FE_BESIDE]) == BESIDE_WALL_NORTH:
		return Vector2i(ox, _range_y(size.y).x)
	return Vector2i(ox, _pick_in(_range_y(size.y), _mix(_hash_t(seed_term, tx, ty, SALT_JITTER_Y))))


# Whether a picture's art rect, in its own tile's frame, lies over ground it may stand on: every tile
# its row reaches is Floor of the same side of the walls, carrying a surface `mask` names. The row is
# the picture's own: a standing picture rises over the tile north of it the way a tree does, and only
# its base has to stand on something.
static func _footprint_fits(map: Variant, rect: Rect2i, tx: int, ty: int, indoors: bool, mask: int) -> bool:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return false
	var first: int = floori(float(rect.position.x) / float(ART_PER_TILE))
	var last: int = floori(float(rect.end.x - 1) / float(ART_PER_TILE))
	for dx in range(first, last + 1):
		if not _floor_of(map, tx + dx, ty, indoors):
			return false
		if (mask >> int(SimSurface.surface_at(map, tx + dx, ty))) & 1 == 0:
			return false
	return true


# Whether a picture's art rect, in its own tile's frame, reaches into the clearing: any tile of its
# row inside it. A picture anchored just outside the clearing is still a picture in it when its art
# is wider than its tile, which is what round 1 of A12's review found two shelves doing.
static func _reaches_clear(clear: Rect2i, rect: Rect2i, tx: int, ty: int) -> bool:
	var first: int = floori(float(rect.position.x) / float(ART_PER_TILE))
	var last: int = floori(float(rect.end.x - 1) / float(ART_PER_TILE))
	for dx in range(first, last + 1):
		if clear.has_point(Vector2i(tx + dx, ty)):
			return true
	return false


# Whether an entry's picture at its own offsets on (tx, ty) reaches into the clearing.
static func _entry_reaches_clear(entry: Array, seed_term: int, tx: int, ty: int, clear: Rect2i) -> bool:
	var off: Vector2i = _offsets_for(entry, seed_term, tx, ty)
	return _reaches_clear(clear, _art_rect(entry[FE_EXTENT], off.x, off.y), tx, ty)


# Whether one prepared entry's ground fits a tile already matched to its `where` and its surface: its
# footprint at its own offsets, no door directly north or south, and its `beside`. In a room a wall
# piece stands with a wall straight beside it (not across a corner), and no tile its art covers has
# a window straight beside it: a shelf does not block the light, and the rest of that wall still
# takes its pieces.
static func _furnishing_ground_fits(entry: Array, map: Variant, seed_term: int, tx: int, ty: int, road: PackedByteArray = PackedByteArray()) -> bool:
	var indoors: bool = bool(entry[FE_INDOORS])
	var off: Vector2i = _offsets_for(entry, seed_term, tx, ty)
	var rect: Rect2i = _art_rect(entry[FE_EXTENT], off.x, off.y)
	if not _footprint_fits(map, rect, tx, ty, indoors, int(entry[FE_MASK])):
		return false
	if _door_at(map, tx, ty - 1) or _door_at(map, tx, ty + 1):
		return false
	match int(entry[FE_BESIDE]):
		BESIDE_WALL:
			if indoors:
				return _wall_beside(map, tx, ty) and not _reaches_window(map, rect, tx, ty)
			return _wall_within_one(map, tx, ty) or (int(SimSurface.surface_at(map, tx, ty)) == SimSurface.Surface.Paved and _kerb_within_one(map, tx, ty))
		BESIDE_WALL_NORTH:
			return _wall_at(map, tx, ty - 1) and not _reaches_window(map, rect, tx, ty)
		BESIDE_EDGE:
			return _edge_at(map, tx, ty, road)
	return true


# Whether a plain or wall entry's roll lands on a tile. One tile in `rarity` (the nature roll,
# mixed): every indoor entry, and every outdoor one that is not a `cluster` -- the street's own
# furniture, the barriers, cones, posts, signs and lamps, which stand where they always stood. A
# cluster entry (the street's junk) rolls on its row segment's one spaced tile (`_spaced`) and is
# weighted by the street (`_weight`). Against a north wall the roll is the wall run's: one segment
# in `rarity`, every other tile of it.
static func _entry_rolls(entry: Array, map: Variant, seed_term: int, tx: int, ty: int, base: int, road: PackedByteArray = PackedByteArray()) -> bool:
	var rarity: int = int(entry[FE_RARITY])
	if int(entry[FE_BESIDE]) == BESIDE_WALL_NORTH:
		var index: int = int(entry[FE_INDEX])
		var shift: int = _mix(_hash_t(seed_term, 0, ty, SALT_RUN_OFFSET + index)) % RUN_TILES
		var segment: int = floori(float(tx + shift) / float(RUN_TILES))
		if _mix(_hash_t(seed_term, segment, ty, SALT_RUN + index)) % rarity != 0:
			return false
		return (tx + _mix(_hash_t(seed_term, segment, ty, SALT_RUN_PHASE + index))) % 2 == 0
	var roll: int = _mix((base ^ int(entry[FE_SALT])) & 0x7fffffff)
	if bool(entry[FE_INDOORS]) or not bool(entry[FE_CLUSTER]):
		return roll % rarity == 0
	if not _spaced(seed_term, tx, ty):
		return false
	return _weighted_hit(roll, rarity, _weight(map, seed_term, tx, ty, road))


# Whether a tile is its row segment's one tile for the street's junk: the row is cut into
# SPACING_TILES segments, moved by a hash of the row, and each segment names one of its tiles.
static func _spaced(seed_term: int, tx: int, ty: int) -> bool:
	var shift: int = _mix(_hash_t(seed_term, 0, ty, SALT_SPACE_OFFSET)) % SPACING_TILES
	var segment: int = floori(float(tx + shift) / float(SPACING_TILES))
	return posmod(tx + shift, SPACING_TILES) == _mix(_hash_t(seed_term, segment, ty, SALT_SPACE)) % SPACING_TILES


# The picture one tile's own roll and ground give it among the plain and wall entries, before the
# placement rules, or "". The first entry whose `where` and surface match, whose roll lands and whose
# ground fits -- and, for a `per_room` entry, that is one of its room's few (`_room_keeps`, which
# needs the occupancy `occ`; without one a per-room entry places nothing). Group entries are
# `_group_top`'s and are skipped here. The overlap rule reads each neighbour's raw top (`_raw_top`),
# so the raw picks never recurse.
static func _furnishing_raw(entries: Array, map: Variant, seed_term: int, tx: int, ty: int, clear: Rect2i, road: PackedByteArray = PackedByteArray(), occ: Dictionary = {}) -> String:
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return ""
	var idx: int = ty * int(map.w) + tx
	if int(map.tiles[idx]) != SimTileMap.Tile.Floor:
		return ""
	if clear.has_point(Vector2i(tx, ty)):
		return ""
	var indoors: bool = int(map.indoors[idx]) == 1
	var surface: int = int(map.surfaces[idx])
	var base: int = (tx * _HASH_TX) ^ (ty * _HASH_TY) ^ seed_term
	for entry in entries:
		if int(entry[FE_GROUP]) != GROUP_NONE or bool(entry[FE_KEPT]):
			continue
		if bool(entry[FE_INDOORS]) != indoors:
			continue
		if (int(entry[FE_MASK]) >> surface) & 1 == 0:
			continue
		if not _entry_rolls(entry as Array, map, seed_term, tx, ty, base, road):
			continue
		if not _furnishing_ground_fits(entry as Array, map, seed_term, tx, ty, road):
			continue
		if _entry_reaches_clear(entry as Array, seed_term, tx, ty, clear):
			continue
		if int(entry[FE_ROOMS]) != ROOMS_ANY and (occ.is_empty() or _room_kind(occ, map, tx, ty) != int(entry[FE_ROOMS])):
			continue
		if int(entry[FE_PER_ROOM]) > 0 and (occ.is_empty() or not _room_keeps(occ, map, entry as Array, tx, ty)):
			continue
		return String(entry[FE_KEY])
	return ""


# --- the few a room keeps -------------------------------------------------------------------

# Whether a `per_room` entry keeps this tile: of every tile in the tile's room where the entry's roll
# lands and its ground fits (outside the clearing, on its surfaces), the `per_room` whose SALT_ROOM
# hash is lowest. So a room holds at most that many, wherever its walls give them room. Memoised per
# room and entry in `occ`.
static func _room_keeps(occ: Dictionary, map: Variant, entry: Array, tx: int, ty: int) -> bool:
	var w: int = int(map.w)
	var room: int = _room_of(occ, map, tx, ty)
	if room < 0:
		return false
	var picks: Dictionary = occ["room_picks"]
	var memo_key: Vector2i = Vector2i(room, int(entry[FE_INDEX]))
	if int(entry[FE_ROOMS]) != ROOMS_ANY and _room_kind(occ, map, tx, ty) != int(entry[FE_ROOMS]):
		return false
	if not picks.has(memo_key):
		var seed_term: int = int(occ["seed_term"])
		var clear: Rect2i = occ["clear"]
		var road: PackedByteArray = occ["road"]
		var ranked: Array = []
		for idx in (occ["room_tiles"] as Array)[room] as PackedInt32Array:
			var cx: int = idx % w
			var cy: int = floori(float(idx) / float(w))
			if clear.has_point(Vector2i(cx, cy)) or (int(entry[FE_MASK]) >> int(map.surfaces[idx])) & 1 == 0:
				continue
			var base: int = (cx * _HASH_TX) ^ (cy * _HASH_TY) ^ seed_term
			if not _entry_rolls(entry, map, seed_term, cx, cy, base, road) or not _furnishing_ground_fits(entry, map, seed_term, cx, cy, road):
				continue
			if _entry_reaches_clear(entry, seed_term, cx, cy, clear):
				continue
			ranked.append([_mix(_hash_t(seed_term, cx, cy, SALT_ROOM + int(entry[FE_INDEX]))), idx])
		ranked.sort_custom(func(p: Array, q: Array) -> bool: return int(p[0]) < int(q[0]) or (int(p[0]) == int(q[0]) and int(p[1]) < int(q[1])))
		var kept: Dictionary = {}
		for i in mini(int(entry[FE_PER_ROOM]), ranked.size()):
			kept[int((ranked[i] as Array)[1])] = true
		picks[memo_key] = kept
	return (picks[memo_key] as Dictionary).has(ty * w + tx)


# Whether a tile's room is a storage room (ROOMS_STORAGE: its first tile lies in a building whose id
# the block lists under `storage`, a warehouse, a unit, a shed) or a living room (ROOMS_LIVING: any
# other room, the colony's hall among them). Memoised per room in `occ`.
static func _room_kind(occ: Dictionary, map: Variant, tx: int, ty: int) -> int:
	var room: int = _room_of(occ, map, tx, ty)
	if room < 0:
		return ROOMS_LIVING
	var kinds: Dictionary = occ.get("room_kinds", {})
	if not kinds.has(room):
		var w: int = int(map.w)
		var first: int = ((occ["room_tiles"] as Array)[room] as PackedInt32Array)[0]
		var at := Vector2i(first % w, floori(float(first) / float(w)))
		var kind: int = ROOMS_LIVING
		var storage: Dictionary = occ.get("storage", {})
		var placed: Variant = map.get("buildings")
		if placed is Array:
			for record in placed as Array:
				var r: Dictionary = record as Dictionary
				if Rect2i(int(r.get("x", 0)), int(r.get("y", 0)), int(r.get("w", 0)), int(r.get("h", 0))).has_point(at):
					if storage.has(String(r.get("id", ""))):
						kind = ROOMS_STORAGE
					break
		kinds[room] = kind
		occ["room_kinds"] = kinds
	return int(kinds[room])


# The block's `storage` building ids, as a set.
static func _storage_of(block: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var listed: Variant = block.get("storage")
	if listed is Array:
		for raw in listed as Array:
			out[String(raw)] = true
	return out


# The room a tile of indoor floor lies in, as an index into `occ["room_tiles"]`, or -1: the indoor
# Floor tiles reached from it by side steps (a door or a wall ends a room). Found on first asking
# and remembered for every tile of the room, so a room is walked once per occupancy.
static func _room_of(occ: Dictionary, map: Variant, tx: int, ty: int) -> int:
	var w: int = int(map.w)
	if not _floor_of(map, tx, ty, true):
		return -1
	var rooms: Dictionary = occ["rooms"]
	var at: int = ty * w + tx
	if rooms.has(at):
		return int(rooms[at])
	var tiles: Array = occ["room_tiles"]
	var room: int = tiles.size()
	var found: PackedInt32Array = PackedInt32Array()
	var queue: Array[int] = [at]
	rooms[at] = room
	while not queue.is_empty():
		var idx: int = queue.pop_back()
		found.append(idx)
		var cx: int = idx % w
		var cy: int = floori(float(idx) / float(w))
		for side in SIDES:
			var nx: int = cx + side.x
			var ny: int = cy + side.y
			var n_idx: int = ny * w + nx
			if not rooms.has(n_idx) and _floor_of(map, nx, ny, true):
				rooms[n_idx] = room
				queue.append(n_idx)
	tiles.append(found)
	return room


# --- the tables and the chairs at them -------------------------------------------------------

# The side of a table entry's cells, in tiles: the square whose area is nearest its rarity, never
# under three so a cell always has an inside.
static func _cell_side(rarity: int) -> int:
	return maxi(3, roundi(sqrt(float(rarity))))


# Where a table sits in its tile: two art pixels either way, its base up to two off the south edge,
# so the chairs fitted round it stay inside their own tiles.
static func _table_offsets(seed_term: int, tx: int, ty: int) -> Vector2i:
	return Vector2i(-2 + _mix(_hash_t(seed_term, tx, ty, SALT_JITTER_X)) % 5, -(_mix(_hash_t(seed_term, tx, ty, SALT_JITTER_Y)) % 3))


# Whether a table entry may stand on a tile: its own room's floor on its surfaces, outside the
# clearing, held by nothing, its eight neighbours all the same room's floor held by nothing (so a
# chair fits on any side and the table stands out in the room), and its footprint on that floor.
static func _anchor_fits(occ: Dictionary, map: Variant, entry: Array, tx: int, ty: int) -> bool:
	var indoors: bool = bool(entry[FE_INDOORS])
	if (occ["clear"] as Rect2i).has_point(Vector2i(tx, ty)):
		return false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if not _floor_of(map, tx + dx, ty + dy, indoors) or _held_rect(occ, map, tx + dx, ty + dy) != null:
				return false
	if (int(entry[FE_MASK]) >> int(SimSurface.surface_at(map, tx, ty))) & 1 == 0:
		return false
	# A wall piece or any plain pick beside it would outrank or crowd the table and leave its chairs
	# round nothing, so a table stands where its eight neighbours roll no plain picture.
	var seed_term: int = int(occ["seed_term"])
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if (dx != 0 or dy != 0) and not _furnishing_raw(occ["furnish"], map, seed_term, tx + dx, ty + dy, occ["clear"], occ["road"], occ).is_empty():
				return false
	var off: Vector2i = _table_offsets(seed_term, tx, ty)
	var rect: Rect2i = _art_rect(entry[FE_EXTENT], off.x, off.y)
	# A pair's halves sit PAIR_SHIFT either way of these offsets, so the clearing is judged on both.
	if _reaches_clear(occ["clear"] as Rect2i, rect.grow_individual(PAIR_SHIFT, 0, PAIR_SHIFT, 0), tx, ty):
		return false
	return _footprint_fits(map, rect, tx, ty, indoors, int(entry[FE_MASK]))


# The tile a table entry stands its table on in the cell holding tile (tx, ty), or (-1, -1) for
# none. The cells are a grid moved by the seed; a cell skips one time in CELL_SKIP, else tries up to
# CELL_CANDIDATES hashed tiles of its inside (every row and column but its last, so two cells' tables
# are never neighbours) and keeps the first that fits. Memoised per cell in `occ`.
static func _anchor_in_cell(occ: Dictionary, map: Variant, entry: Array, tx: int, ty: int) -> Vector2i:
	var seed_term: int = int(occ["seed_term"])
	var index: int = int(entry[FE_INDEX])
	var side: int = _cell_side(int(entry[FE_RARITY]))
	var shift: int = _mix(_hash_t(seed_term, index, 0, SALT_CELL_OFFSET))
	var sx: int = shift % side
	var sy: int = (shift >> 8) % side
	var cx: int = floori(float(tx + sx) / float(side))
	var cy: int = floori(float(ty + sy) / float(side))
	var memo: Dictionary = occ["cells"]
	var memo_key: Vector3i = Vector3i(cx, cy, index)
	if memo.has(memo_key):
		return memo[memo_key]
	var found := Vector2i(-1, -1)
	if _mix(_hash_t(seed_term, cx, cy, SALT_CELL + index)) % CELL_SKIP != 0:
		for k in CELL_CANDIDATES:
			var px: int = cx * side - sx + _mix(_hash_t(seed_term, cx, cy, SALT_CELL_X + 16 * k + index)) % (side - 1)
			var py: int = cy * side - sy + _mix(_hash_t(seed_term, cx, cy, SALT_CELL_Y + 16 * k + index)) % (side - 1)
			if px < 0 or py < 0 or px >= int(map.w) or py >= int(map.h):
				continue
			if _anchor_fits(occ, map, entry, px, py):
				found = Vector2i(px, py)
				break
	memo[memo_key] = found
	return found


# The seats a table offers, each `[offset from the table's anchor tile, the side of the table half
# it sits at (an index into SIDES), which half (0 the anchor's, 1 its east neighbour's)]`. Never the
# south side: the pack's chair is drawn from the front, its back to the north, so a chair south of a
# table would sit with its back to it. A single table takes the north, east and west; a pair takes
# the north of each half and its two ends.
const SINGLE_SEATS: Array = [[Vector2i(0, -1), 0, 0], [Vector2i(1, 0), 1, 0], [Vector2i(-1, 0), 3, 0]]
const PAIR_SEATS: Array = [[Vector2i(0, -1), 0, 0], [Vector2i(1, -1), 0, 1], [Vector2i(-1, 0), 3, 0], [Vector2i(2, 0), 1, 1]]
# The most chairs one table takes.
const SEATS_MAX: int = 3
# One table in FULL_SET_ODDS that seats more than one takes SEATS_MAX chairs; the rest take two.
const FULL_SET_ODDS: int = 4


# Which of a table's `count` seats take a chair, as a mask: one to SEATS_MAX of them, as many by one
# hash and starting from a seat named by another, every other seat round the table after it -- so
# the sets differ in how many sit and on which side. `rarity` is the seat entry's, and one set in
# `rarity` seats exactly one.
static func _seat_slots(seed_term: int, ax: int, ay: int, rarity: int, count: int) -> int:
	var most: int = mini(SEATS_MAX, count)
	var taken: int = 1
	if _mix(_hash_t(seed_term, ax, ay, SALT_SEAT)) % rarity != 0:
		# Two chairs mostly; a full set in FULL_SET_ODDS, so neighbouring tables seldom wear the
		# same cross of three.
		taken = 2
		if most > 2 and _mix(_hash_t(seed_term, ax, ay, SALT_SEAT + 1)) % FULL_SET_ODDS == 0:
			taken = most
	taken = mini(taken, most)
	var start: int = _mix(_hash_t(seed_term, ax, ay, SALT_SEAT + 2)) % count
	var step: int = 1 if count % 2 == 0 or _mix(_hash_t(seed_term, ax, ay, SALT_SEAT + 3)) % 2 == 0 else 2
	var slots: int = 0
	var at: int = start
	while taken > 0:
		if (slots >> at) & 1 == 0:
			slots |= 1 << at
			taken -= 1
		at = (at + step) % count
	return slots


# Whether the table a table entry anchors on (ax, ay) is a pair: one in PAIR_ODDS, when the tile east
# of it would take a table on its own (its eight neighbours its room's open floor) and no other cell's
# table stands beside that east half, so both halves have room round them and the long table never
# touches a second one.
static func _is_pair(occ: Dictionary, map: Variant, table: Array, ax: int, ay: int) -> bool:
	if _mix(_hash_t(int(occ["seed_term"]), ax, ay, SALT_PAIR + int(table[FE_INDEX]))) % PAIR_ODDS == 0:
		return false
	if not _anchor_fits(occ, map, table, ax + 1, ay):
		return false
	for dy in range(-1, 2):
		for dx in range(0, 3):
			if dx == 0 and dy == 0:
				continue
			if _anchor_in_cell(occ, map, table, ax + dx, ay + dy) == Vector2i(ax + dx, ay + dy):
				return false
	return true


# Where a table half sits in its tile: a single table at its own offsets; a pair's halves PAIR_SHIFT
# art pixels west and east, on the anchor's row offset, so the two meet edge to edge.
static func _table_off(seed_term: int, ax: int, ay: int, pair: bool, half: int) -> Vector2i:
	var base: Vector2i = _table_offsets(seed_term, ax, ay)
	if not pair:
		return base
	return Vector2i(PAIR_SHIFT if half == 1 else -PAIR_SHIFT, base.y)


# Where a chair on `side` of a table sits, `Vector2i(ox, oy)`, or (-99, -99) when no offset keeps it
# off the table's art. The chair goes flush against the table's own rect, then up to two art pixels
# further off it by a hash; along the table's edge it wanders a little.
static func _seat_offsets(seed_term: int, tx: int, ty: int, side: int, seat: Vector2i, table: Vector2i, t_off: Vector2i) -> Vector2i:
	var rx: Vector2i = _range_x(seat.x)
	var ry: Vector2i = _range_y(seat.y)
	var t_rect: Rect2i = _art_rect(table, t_off.x, t_off.y)
	var away: int = _mix(_hash_t(seed_term, tx, ty, SALT_SEAT_OFFSET)) % 3
	var along: int = _mix(_hash_t(seed_term, tx, ty, SALT_SEAT_OFFSET + 1))
	var ox: int = 0
	var oy: int = 0
	# The flush offset first, then `away` further off the table only as far as the chair's own range
	# allows: a chair beside the long end of a pair has no room to spare, and sits flush.
	match side:
		0, 2:
			ox = clampi(t_off.x + along % 5 - 2, rx.x, rx.y)
			if side == 0:
				# The chair's base on or above the table's top: oy <= t_rect top, in the table's frame.
				oy = mini(t_rect.position.y, ry.y)
				oy = maxi(oy - away, mini(oy, ry.x))
			else:
				# The chair's top on or below the table's base: 32 + (32 + oy - h) >= t_rect end.
				oy = maxi(t_rect.end.y - 2 * ART_PER_TILE + seat.y, ry.x)
				oy = mini(oy + away, maxi(oy, ry.y))
			if oy < ry.x or oy > ry.y:
				return Vector2i(-99, -99)
		1, 3:
			oy = _pick_in(ry, along)
			if side == 1:
				# The chair's left on or past the table's right: 32 + 16 + ox - w/2 >= t_rect end.
				ox = maxi(t_rect.end.x - ART_PER_TILE - (ART_PER_TILE >> 1) + (seat.x >> 1), rx.x)
				ox = mini(ox + away, maxi(ox, rx.y))
			else:
				# The chair's right on or before the table's left: -32 + 16 + ox - w/2 + w <= t_rect left.
				ox = mini(t_rect.position.x + ART_PER_TILE - (ART_PER_TILE >> 1) + (seat.x >> 1) - seat.x, rx.y)
				ox = maxi(ox - away, mini(ox, rx.x))
			if ox < rx.x or ox > rx.y:
				return Vector2i(-99, -99)
	return Vector2i(ox, oy)


# Whether a table entry stands a table on (tx, ty): its cell's table, or the east half of a pair.
static func _table_on(occ: Dictionary, map: Variant, table: Array, tx: int, ty: int) -> bool:
	if _anchor_in_cell(occ, map, table, tx, ty) == Vector2i(tx, ty):
		return true
	return _anchor_in_cell(occ, map, table, tx - 1, ty) == Vector2i(tx - 1, ty) and _is_pair(occ, map, table, tx - 1, ty)


# The group picture on one tile, or {}: a table where a table entry's cell keeps one (or where the
# cell's table west of it is a pair), else a chair where a seat entry's table beside it puts one in
# this seat. As `_raw_top` answers, with the picture's own offsets and a priority above a plain
# pick's (a table, then a chair), so a tie in the overlap rule keeps the room's set rather than a
# loose piece.
static func _group_top(occ: Dictionary, map: Variant, tx: int, ty: int) -> Dictionary:
	var entries: Array = occ["furnish"]
	var tables: Array = occ["tables"]
	if tables.is_empty():
		return {}
	var seed_term: int = int(occ["seed_term"])
	var seed_val: int = int(occ["seed"])
	var idx: int = ty * int(map.w) + tx
	var indoors: bool = int(map.indoors[idx]) == 1
	var surface: int = int(map.surfaces[idx])
	for table in tables:
		if bool(table[FE_INDOORS]) != indoors or (int(table[FE_MASK]) >> surface) & 1 == 0:
			continue
		if _anchor_in_cell(occ, map, table as Array, tx, ty) == Vector2i(tx, ty):
			var pair: bool = _is_pair(occ, map, table as Array, tx, ty)
			var off: Vector2i = _table_off(seed_term, tx, ty, pair, 0)
			var single: Dictionary = {"key": String(table[FE_KEY]), "rank": RANK_FLAT, "prio": 2, "ox": off.x, "oy": off.y, "flip": flip_at(seed_val, tx, ty, SALT_FLIP)}
			if pair:
				single["pair"] = Vector2i(tx, ty)
			return single
		if _anchor_in_cell(occ, map, table as Array, tx - 1, ty) == Vector2i(tx - 1, ty) and _is_pair(occ, map, table as Array, tx - 1, ty):
			var east: Vector2i = _table_off(seed_term, tx - 1, ty, true, 1)
			return {"key": String(table[FE_KEY]), "rank": RANK_FLAT, "prio": 2, "ox": east.x, "oy": east.y, "flip": flip_at(seed_val, tx - 1, ty, SALT_FLIP), "pair": Vector2i(tx - 1, ty)}
	for seat in entries:
		if int(seat[FE_GROUP]) != GROUP_SEAT or bool(seat[FE_INDOORS]) != indoors or (int(seat[FE_MASK]) >> surface) & 1 == 0:
			continue
		for table in tables:
			if bool(table[FE_INDOORS]) != indoors:
				continue
			for pair in [false, true]:
				var seats: Array = PAIR_SEATS if pair else SINGLE_SEATS
				for slot in seats.size():
					var d: Vector2i = (seats[slot] as Array)[0]
					var ax: int = tx - d.x
					var ay: int = ty - d.y
					if _anchor_in_cell(occ, map, table as Array, ax, ay) != Vector2i(ax, ay):
						continue
					if _is_pair(occ, map, table as Array, ax, ay) != pair:
						continue
					if (_seat_slots(seed_term, ax, ay, int(seat[FE_RARITY]), seats.size()) >> slot) & 1 == 0:
						continue
					var side: int = int((seats[slot] as Array)[1])
					var t_off: Vector2i = _table_off(seed_term, ax, ay, pair, int((seats[slot] as Array)[2]))
					var off: Vector2i = _seat_offsets(seed_term, tx, ty, side, seat[FE_EXTENT], table[FE_EXTENT], t_off)
					if off.x == -99:
						continue
					if not _footprint_fits(map, _art_rect(seat[FE_EXTENT], off.x, off.y), tx, ty, indoors, int(seat[FE_MASK])):
						continue
					if _door_at(map, tx, ty - 1) or _door_at(map, tx, ty + 1) or _reaches_clear(occ["clear"] as Rect2i, _art_rect(seat[FE_EXTENT], off.x, off.y), tx, ty):
						continue
					# A chair between two tables a tile apart would sit with its back to the north one.
					if _table_on(occ, map, table as Array, tx, ty - 1):
						continue
					var faces := Vector2i(ax + int((seats[slot] as Array)[2]), ay)
					return {"key": String(seat[FE_KEY]), "rank": RANK_FLAT, "prio": 1, "ox": off.x, "oy": off.y, "flip": flip_at(seed_val, tx, ty, SALT_FLIP), "table": faces}
	return {}


# The overlap rule. A tile's raw top (`_raw_top`) is one picture: what the sim stands there (held),
# else the room's set (`_group_top`), else the furnishing its roll gives, else the nature picture its
# roll gives, else nothing. A tile keeps its top unless a neighbour's raw top outranks it and the two
# art rects meet (`_kept_top`). Ranks: what the sim holds (RANK_HELD, never drawn here) over a
# standing furnishing (RANK_STANDING) over a flat one (RANK_FLAT) over a nature picture (RANK_NATURE),
# and a scrap of litter (rank 0) gives way to any of them. A tie in rank goes to the higher priority
# (a table, then a chair at it, then a plain pick), then to the tile whose SALT_WINNER hash is higher.
# So two pictures that meet are never both kept, and nothing a furnishing holds is taken by nature or
# litter.
#
# The rule reads raw tops, not kept ones: a picture that loses its place still blocks the pictures
# beside it. That costs a little furniture and keeps every answer local and pure, because no tile
# needs a chain of its neighbours' decisions to know its own. Every picture fits within one tile of
# its own tile (the tallest, the streetlamp, is 62 art px in a 32 px tile; a held rect reaches one
# tile north), so the eight neighbours are the only tiles whose pictures can meet it.

# Every picture's extent in art pixels, by key: `[w, h]` from the block's `sizes`. A key with no
# valid size is not in the map, and a picture with no size draws nothing, because nothing can be
# placed without its extent.
static func _sizes(block: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var named: Variant = block.get("sizes")
	if not (named is Dictionary):
		return out
	for key_v in (named as Dictionary).keys():
		var value: Variant = (named as Dictionary)[key_v]
		if not (value is Array) or (value as Array).size() != 2:
			continue
		var w: int = int((value as Array)[0])
		var h: int = int((value as Array)[1])
		if w > 0 and h > 0 and w <= MAX_EXTENT and h <= MAX_EXTENT:
			out[String(key_v)] = Vector2i(w, h)
	return out


# The block's `litter` keys that have a size, in list order: the only scraps a tile can draw. A key
# listed twice is twice as likely.
# The block's `litter_tints` as colours, or one plain white when it names none. A tint is a modulate
# over the scrap's picture; listing white more than once makes the others rarer.
static func _litter_tints(block: Dictionary) -> Array:
	var out: Array = []
	var listed: Variant = block.get("litter_tints")
	if listed is Array:
		for raw in listed as Array:
			var text: String = String(raw)
			if text.length() == 7 and text.begins_with("#") and text.substr(1).is_valid_hex_number():
				out.append(Color(text))
	if out.is_empty():
		out.append(Color.WHITE)
	return out


static func _litter_keys(block: Dictionary) -> Array:
	var out: Array = []
	var sizes: Dictionary = _sizes(block)
	var listed: Variant = block.get("litter")
	if not (listed is Array):
		return out
	for raw in listed as Array:
		var key: String = String(raw)
		if sizes.has(key):
			out.append(key)
	return out


# Everything the picks are made from, built once per map and seed: the lists as plain arrays, the
# sizes, the seed and its term, the clearing, the map itself, `props` (what the sim stands on a tile
# that the map does not say: `{Vector2i: Rect2i}`, the tile and its picture's art rect in that tile's
# frame, from `held_props`), and the memos -- each tile's raw top by tile index, each table cell's
# answer. An occupancy belongs to one map and one set of props; a caller that keeps one across frames
# rebuilds it when either changes.
static func occupancy(block: Dictionary, map: Variant, seed_val: int, props: Dictionary = {}) -> Dictionary:
	var furnish: Array = _furnishing_entries(block)
	var tables: Array = []
	for entry in furnish:
		if int(entry[FE_GROUP]) == GROUP_TABLE:
			tables.append(entry)
	return {"map": map, "furnish": furnish, "tables": tables, "nature": _nature_entries(block), "litter": _litter_keys(block), "litter_tints": _litter_tints(block), "sizes": _sizes(block), "seed": seed_val, "seed_term": seed_val * _HASH_SEED, "clear": _clear_of(map), "road": RoadPaint.mask_for(map), "props": props, "kept": _kept_entries(furnish), "storage": _storage_of(block), "memo": {}, "cells": {}, "rooms": {}, "room_tiles": [], "room_picks": {}, "litter_blocks": {}}


# The rect a sim object holds on its tile, in that tile's art frame, or null: a prop `occupancy` was
# given, else a Low tile (a heap, or a parked car whose picture rises over the tile north of it) or a
# Tree tile (a trunk, under a canopy that does the same), each held with the tile north of it.
static func _held_rect(occ: Dictionary, map: Variant, tx: int, ty: int) -> Variant:
	var props: Dictionary = occ["props"]
	if not props.is_empty():
		var at := Vector2i(tx, ty)
		if props.has(at):
			return props[at]
	var tile: int = int(map.tiles[ty * int(map.w) + tx])
	if tile == SimTileMap.Tile.Low or tile == SimTileMap.Tile.Tree:
		return Rect2i(0, -ART_PER_TILE, ART_PER_TILE, 2 * ART_PER_TILE)
	return null


# What the sim stands on each tile, as `occupancy` takes it: every live prop's tile and the art rect
# its picture covers there (main.gd's `_draw_prop` placement, read through Appearance.prop_look: a
# feet-anchored picture hangs on the tile's south edge, a square one centres on the prop's point, a
# prop with no picture holds the whole tile).
static func held_props(world: Variant) -> Dictionary:
	var out: Dictionary = {}
	if world == null or world.components == null:
		return out
	for kind in Appearance.PROP_KINDS:
		for ent in world.components.query([String(kind["component"]), "position"]):
			if world.entities != null and not world.entities.is_alive(int(ent)):
				continue
			var p: Variant = world.components.get_component(int(ent), "position")
			if not (p is Dictionary):
				continue
			var x: float = float((p as Dictionary)["x"])
			var y: float = float((p as Dictionary)["y"])
			var at := Vector2i(floori(x), floori(y))
			var cx: int = roundi((x - float(at.x)) * float(ART_PER_TILE))
			var cy: int = roundi((y - float(at.y)) * float(ART_PER_TILE))
			var rect := Rect2i(0, 0, ART_PER_TILE, ART_PER_TILE)
			var look: Dictionary = Appearance.prop_look(world, int(ent))
			var texture: Variant = look.get("texture")
			if texture is Texture2D:
				var size := Vector2i((texture as Texture2D).get_size())
				if bool(look.get("standing", false)) or Appearance.anchor_of(size) == Appearance.Anchor.Feet:
					rect = Rect2i(cx - (size.x >> 1), cy + (ART_PER_TILE >> 1) - size.y, size.x, size.y)
				else:
					rect = Rect2i(cx - (size.x >> 1), cy - (size.y >> 1), size.x, size.y)
			out[at] = rect.merge(Rect2i(0, 0, ART_PER_TILE, ART_PER_TILE))
	return out


# The one flag `_entry_flag` reads, or false for a key no entry carries.
static func _entry_flag(entries: Array, key: String, index: int) -> bool:
	if key.is_empty():
		return false
	for entry in entries:
		if String((entry as Array)[0]) == key:
			return bool((entry as Array)[index])
	return false


# The first entry carrying a key, or [].
static func _entry_of(entries: Array, key: String) -> Array:
	for entry in entries:
		if String((entry as Array)[FE_KEY]) == key and not bool((entry as Array)[FE_SHADOW]):
			return entry as Array
	return []


# A picture's art rect in its own tile's frame, in whole art pixels: `size` centred on the tile's
# centre line (`ox`), its base `oy` above the tile's south edge. The left edge is taken on the art
# grid with an odd width rounded down, so a scrap of five pixels lands on the same grid as a table.
static func _art_rect(size: Vector2i, ox: int, oy: int) -> Rect2i:
	var left: int = (ART_PER_TILE >> 1) + ox - (size.x >> 1)
	return Rect2i(left, ART_PER_TILE + oy - size.y, size.x, size.y)


# The rect of a raw top on its tile, in that tile's frame: a held tile's own rect, else the picture's
# size at the offsets its top carries. A standing picture is drawn feet-anchored with the renderer's
# foot drop below the edge (Appearance.FOOT_DROP_PX, under two art pixels), so its rect reaches two art
# pixels into the tile south of it.
static func _top_rect(occ: Dictionary, top: Dictionary, _tx: int, _ty: int) -> Rect2i:
	if top.has("rect"):
		return top["rect"] as Rect2i
	var size: Vector2i = (occ["sizes"] as Dictionary)[String(top["key"])]
	var rect: Rect2i = _art_rect(size, int(top["ox"]), int(top["oy"]))
	if int(top["rank"]) == RANK_STANDING:
		rect.size.y += 2
	return rect


# The rect of a scrap of litter on tile (tx, ty), at its own offsets.
static func _litter_rect(occ: Dictionary, key: String, tx: int, ty: int) -> Rect2i:
	var size: Vector2i = (occ["sizes"] as Dictionary)[key]
	var off: Vector2i = _litter_offsets(int(occ["seed_term"]), size, tx, ty)
	return _art_rect(size, off.x, off.y)


# Where a scrap lies in its tile: anywhere in it, hashed on the litter salts, in whole art pixels. A
# scrap is flat and small, so it is not held to the furniture's jitter off the tile's south edge --
# held there, every scrap's centre fell in the tile's lower third and the scraps of a street lay in
# rows and columns. It always fits a tile, so it never leaves its own.
static func _litter_offsets(seed_term: int, size: Vector2i, tx: int, ty: int) -> Vector2i:
	var across := Vector2i((size.x >> 1) - (ART_PER_TILE >> 1), (ART_PER_TILE >> 1) - size.x + (size.x >> 1))
	var down := Vector2i(mini(0, size.y - ART_PER_TILE), 0)
	return Vector2i(_pick_in(across, _mix(_hash_t(seed_term, tx, ty, SALT_LITTER_JITTER_X))), _pick_in(down, _mix(_hash_t(seed_term, tx, ty, SALT_LITTER_JITTER_Y))))


# Whether rect `a` meets rect `b` once `b` is moved by `shift` tiles. Open intervals: pictures that
# only touch an edge do not meet.
static func _meet(a: Rect2i, b: Rect2i, shift: Vector2i) -> bool:
	var bx: int = b.position.x + shift.x * ART_PER_TILE
	var by: int = b.position.y + shift.y * ART_PER_TILE
	return a.position.x < bx + b.size.x and bx < a.position.x + a.size.x and a.position.y < by + b.size.y and by < a.position.y + a.size.y


# What a tile would draw before the overlap rule, as `{key, rank, ox, oy, flip, prio}` -- or a held
# tile's `{key: "", rank: RANK_HELD, rect}` -- or {} for nothing. Memoised per tile in `occ`.
static func _raw_top(occ: Dictionary, map: Variant, tx: int, ty: int) -> Dictionary:
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return {}
	var memo: Dictionary = occ["memo"]
	var index: int = ty * int(map.w) + tx
	if not memo.has(index):
		memo[index] = _raw_top_uncached(occ, map, tx, ty)
	return memo[index] as Dictionary


static func _raw_top_uncached(occ: Dictionary, map: Variant, tx: int, ty: int) -> Dictionary:
	var held: Variant = _held_rect(occ, map, tx, ty)
	if held != null:
		return {"key": "", "rank": RANK_HELD, "rect": held}
	var kept: Dictionary = _kept_raw(occ, map, tx, ty)
	if not kept.is_empty():
		return kept
	var clear: Rect2i = occ["clear"]
	if clear.has_point(Vector2i(tx, ty)):
		return {}
	if int(map.tiles[ty * int(map.w) + tx]) != SimTileMap.Tile.Floor:
		return {}
	var sizes: Dictionary = occ["sizes"]
	var seed_term: int = int(occ["seed_term"])
	var seed_val: int = int(occ["seed"])
	var group: Dictionary = _group_top(occ, map, tx, ty)
	if not group.is_empty() and sizes.has(String(group["key"])):
		return group
	var furnish: Array = occ["furnish"]
	var key: String = _furnishing_raw(furnish, map, seed_term, tx, ty, clear, occ["road"], occ)
	if not key.is_empty() and sizes.has(key):
		var entry: Array = _entry_of(furnish, key)
		var off: Vector2i = _offsets_for(entry, seed_term, tx, ty)
		var standing: bool = bool(entry[FE_STANDING])
		# The street's junk gives way to the street's furniture when the two meet: a barrel is put
		# down round a barrier, never in its place.
		var prio: int = -1 if bool(entry[FE_CLUSTER]) else 0
		return {"key": key, "rank": RANK_STANDING if standing else RANK_FLAT, "prio": prio, "ox": off.x, "oy": off.y, "flip": false if standing else flip_at(seed_val, tx, ty, SALT_FLIP)}
	key = _nature_pick(occ["nature"], map, seed_term, tx, ty)
	if not key.is_empty() and sizes.has(key):
		var size: Vector2i = sizes[key]
		var ox: int = _pick_in(_range_x(size.x), _mix(_hash_t(seed_term, tx, ty, SALT_JITTER_X)))
		var oy: int = _pick_in(_range_y(size.y), _mix(_hash_t(seed_term, tx, ty, SALT_JITTER_Y)))
		return {"key": key, "rank": RANK_NATURE, "prio": 0, "ox": ox, "oy": oy, "flip": flip_at(seed_val, tx, ty, SALT_FLIP)}
	return {}


# The street furniture a tile kept from before A12, as a raw top marked `kept`, or {}. The `kept`
# entries roll the way the district rolled them before any of this file's placement rules: in salt
# order (the salt is each one's index in that list), the first whose surface matches, whose roll
# `((hash ^ salt) & 0x7fffffff) >> 8` lands on its rarity and whose ground fits the old way
# (`_kept_fits`) takes the tile -- and a `shadow` entry that takes it (the old wall dumpster) leaves
# it to the rest of the rules, so a tile that rolled a dumpster then rolls no sign. So every barrier,
# cone, post, sign and lamp main drew stands where it stood, ignoring the clearing, and nothing but a
# prop on its own tile (RANK_HELD) takes its place: a kept piece beats every neighbour it meets
# (`_beats`) and gives way to none (`_kept_alone`). Its jitter is the plain rule's, held to the
# middle of its tile where the jitter would leave its ground.
static func _kept_raw(occ: Dictionary, map: Variant, tx: int, ty: int) -> Dictionary:
	var idx: int = ty * int(map.w) + tx
	if int(map.tiles[idx]) != SimTileMap.Tile.Floor:
		return {}
	var entries: Array = occ.get("kept", [])
	if entries.is_empty():
		return {}
	var indoors: bool = int(map.indoors[idx]) == 1
	var surface: int = int(map.surfaces[idx])
	var seed_term: int = int(occ["seed_term"])
	var base: int = (tx * _HASH_TX) ^ (ty * _HASH_TY) ^ seed_term
	for entry in entries:
		if bool(entry[FE_INDOORS]) != indoors or (int(entry[FE_MASK]) >> surface) & 1 == 0:
			continue
		if (((base ^ int(entry[FE_SALT])) & 0x7fffffff) >> 8) % int(entry[FE_RARITY]) != 0:
			continue
		if not _kept_fits(entry as Array, map, tx, ty):
			continue
		if bool(entry[FE_SHADOW]):
			return {}
		var key: String = String(entry[FE_KEY])
		if not (occ["sizes"] as Dictionary).has(key):
			return {}
		var standing: bool = bool(entry[FE_STANDING])
		var off: Vector2i = _offsets_for(entry as Array, seed_term, tx, ty)
		if not _footprint_fits(map, _art_rect(entry[FE_EXTENT], off.x, off.y), tx, ty, indoors, int(entry[FE_MASK])):
			off = Vector2i(0, off.y)
		return {"key": key, "rank": RANK_STANDING if standing else RANK_FLAT, "prio": 3, "ox": off.x, "oy": off.y, "flip": false, "kept": true}
	return {}


# The old ground rule a `kept` entry is judged by: the same side of the walls on both sides of it,
# no door north or south of it, and for a `beside: wall` entry a wall on one of its four sides.
static func _kept_fits(entry: Array, map: Variant, tx: int, ty: int) -> bool:
	var indoors: bool = bool(entry[FE_INDOORS])
	if not (_floor_of(map, tx - 1, ty, indoors) and _floor_of(map, tx + 1, ty, indoors)):
		return false
	if _door_at(map, tx, ty - 1) or _door_at(map, tx, ty + 1):
		return false
	if int(entry[FE_BESIDE]) != BESIDE_WALL:
		return true
	return _wall_at(map, tx, ty - 1) or _wall_at(map, tx, ty + 1) or _wall_at(map, tx - 1, ty) or _wall_at(map, tx + 1, ty)


# The `kept` entries of a block's furnishings, in salt order: the order the old list rolled them in.
static func _kept_entries(furnish: Array) -> Array:
	var out: Array = []
	for entry in furnish:
		if bool((entry as Array)[FE_KEPT]):
			out.append(entry)
	out.sort_custom(func(a: Array, b: Array) -> bool: return int(a[FE_SALT]) < int(b[FE_SALT]))
	return out


# Whether the picture on tile (nx, ny) beats the one on (tx, ty) for the space they share.
static func _beats(occ: Dictionary, other: Dictionary, nx: int, ny: int, mine: Dictionary, tx: int, ty: int) -> bool:
	if other.has("kept"):
		return true
	if int(other["rank"]) != int(mine["rank"]):
		return int(other["rank"]) > int(mine["rank"])
	if int(other.get("prio", 0)) != int(mine.get("prio", 0)):
		return int(other.get("prio", 0)) > int(mine.get("prio", 0))
	var seed_val: int = int(occ["seed"])
	var theirs: int = _mix(hash_at(seed_val, nx, ny, SALT_WINNER))
	var ours: int = _mix(hash_at(seed_val, tx, ty, SALT_WINNER))
	if theirs != ours:
		return theirs > ours
	return ny > ty or (ny == ty and nx > tx)


# The picture a tile keeps among the furnishings and nature, as its raw top, or {}: its raw top,
# unless an overlapping neighbour's raw top beats it. A held tile keeps its hold, which has no key and
# draws nothing here.
static func _kept_top(occ: Dictionary, map: Variant, tx: int, ty: int) -> Dictionary:
	var top: Dictionary = _kept_seated(occ, map, tx, ty)
	if top.is_empty() or not bool(occ.get("keep_passages", true)) or top.has("kept") or int(top["rank"]) < RANK_FLAT or int(top["rank"]) == RANK_HELD:
		return top
	var room: int = _room_of(occ, map, tx, ty)
	if room >= 0 and (_room_drops(occ, map, room) as Dictionary).has(ty * int(map.w) + tx):
		return {}
	return top


# A tile's top after the overlap rule and the chair's table, before a room keeps its passages.
static func _kept_seated(occ: Dictionary, map: Variant, tx: int, ty: int) -> Dictionary:
	var top: Dictionary = _kept_alone(occ, map, tx, ty)
	# A chair is kept only beside its own table: where the overlap rule dropped the table (or the
	# half of a pair it faces), the chair would stand alone or catty-corner to the other half.
	if top.has("table"):
		var at: Vector2i = top["table"]
		var table: Dictionary = _kept_alone(occ, map, at.x, at.y)
		if table.is_empty() or int(table.get("prio", 0)) != 2:
			return {}
	return top


# The furnished tiles a room gives up so that every free tile of it stays one walk: the room's
# standing and flat pieces are taken in turn, the tables first, then the rest, each in its tile's
# SALT_PASSAGE hash order, and a piece is kept only while the room's tiles left free stay one
# four-connected walk and keep every tile inside a doorway free. A piece that would cut a corridor
# or wall in a corner gives way: a two-tile corridor between walls never takes a piece on both of its
# tiles. A chair whose table gave way goes with it. Memoised per room in `occ`. An occupancy whose
# `keep_passages` is false (a gate's, to show the rule has work) skips it.
static func _room_drops(occ: Dictionary, map: Variant, room: int) -> Dictionary:
	var memo: Dictionary = occ.get("room_drops", {})
	if memo.has(room):
		return memo[room] as Dictionary
	var w: int = int(map.w)
	var seed_term: int = int(occ["seed_term"])
	var tiles: PackedInt32Array = (occ["room_tiles"] as Array)[room]
	var in_room: Dictionary = {}
	for idx in tiles:
		in_room[idx] = true
	var pieces: Array = []
	for idx in tiles:
		var cx: int = idx % w
		var cy: int = floori(float(idx) / float(w))
		var top: Dictionary = _kept_seated(occ, map, cx, cy)
		if top.is_empty() or top.has("kept") or int(top["rank"]) < RANK_FLAT or int(top["rank"]) == RANK_HELD:
			continue
		var first: int = 0 if int(top.get("prio", 0)) == 2 else 1
		pieces.append([first, _mix(_hash_t(seed_term, cx, cy, SALT_PASSAGE)), idx, top.get("table", null)])
	pieces.sort_custom(func(a: Array, b: Array) -> bool: return a.slice(0, 3) < b.slice(0, 3))
	var blocked: Dictionary = {}
	var drops: Dictionary = {}
	for piece in pieces:
		var idx: int = int(piece[2])
		var faces: Variant = piece[3]
		if faces != null and drops.has((faces as Vector2i).y * w + (faces as Vector2i).x):
			drops[idx] = true
			continue
		if _by_door(map, idx % w, floori(float(idx) / float(w))):
			drops[idx] = true
			continue
		blocked[idx] = true
		if not _keeps_its_ring(w, idx, in_room, blocked) and not _one_walk(map, tiles, in_room, blocked):
			blocked.erase(idx)
			drops[idx] = true
	# A table left with no chair of its own goes too: a lone table mid-floor reads as a mistake, and
	# a set is one to SEATS_MAX chairs. Tables side by side are judged as one long table.
	var seated: Dictionary = {}
	for piece in pieces:
		if piece[3] != null and not drops.has(int(piece[2])):
			seated[(piece[3] as Vector2i).y * w + (piece[3] as Vector2i).x] = true
	for piece in pieces:
		var idx: int = int(piece[2])
		if int(piece[0]) != 0 or drops.has(idx):
			continue
		var run: Array[int] = [idx]
		var at: int = idx
		while (at + 1) % w != 0 and _is_table_piece(pieces, drops, at + 1):
			at += 1
			run.append(at)
		at = idx
		while at % w != 0 and _is_table_piece(pieces, drops, at - 1):
			at -= 1
			run.append(at)
		var any: bool = false
		for t in run:
			if seated.has(t):
				any = true
		if not any:
			for t in run:
				drops[t] = true
	memo[room] = drops
	occ["room_drops"] = memo
	return drops


# Whether tile `idx` holds a kept table among a room's judged pieces.
static func _is_table_piece(pieces: Array, drops: Dictionary, idx: int) -> bool:
	if drops.has(idx):
		return false
	for piece in pieces:
		if int(piece[2]) == idx:
			return int(piece[0]) == 0
	return false


# Whether taking tile `idx` (already in `blocked`) leaves its free side neighbours joined round the
# ring of its eight neighbours: then the room's walk is whole if it was, and the flood fill is not
# needed. The ring runs N, NE, E, SE, S, SW, W, NW, each next to the one before by a side, so the free
# side neighbours lie on one run of free ring tiles or they may have been cut apart.
static func _keeps_its_ring(w: int, idx: int, in_room: Dictionary, blocked: Dictionary) -> bool:
	var x: int = idx % w
	var ring: Array[int] = [idx - w, idx - w + 1, idx + 1, idx + w + 1, idx + w, idx + w - 1, idx - 1, idx - w - 1]
	var free: Array[bool] = []
	for i in 8:
		var n: int = ring[i]
		var dx: int = [0, 1, 1, 1, 0, -1, -1, -1][i]
		free.append(x + dx >= 0 and x + dx < w and in_room.has(n) and not blocked.has(n))
	var runs_with_a_side: int = 0
	for i in 8:
		if not free[i] or free[(i + 7) % 8]:
			continue
		var j: int = i
		var has_side: bool = false
		while free[j % 8] and j < i + 8:
			if (j % 8) % 2 == 0:
				has_side = true
			j += 1
		if has_side:
			runs_with_a_side += 1
	if runs_with_a_side == 0:
		# Every ring tile free (no run start) or no free side at all: one run, or nothing to cut.
		return true
	return runs_with_a_side == 1


# Whether a tile lies inside a doorway: a door on one of its four sides.
static func _by_door(map: Variant, tx: int, ty: int) -> bool:
	for side in SIDES:
		if _door_at(map, tx + side.x, ty + side.y):
			return true
	return false


# Whether a room's tiles that are not `blocked` are one four-connected walk (an empty set is).
static func _one_walk(map: Variant, tiles: PackedInt32Array, in_room: Dictionary, blocked: Dictionary) -> bool:
	var w: int = int(map.w)
	var start: int = -1
	var free: int = 0
	for idx in tiles:
		if not blocked.has(idx):
			free += 1
			if start < 0:
				start = idx
	if free == 0:
		return true
	var seen: Dictionary = {start: true}
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var at: int = queue.pop_back()
		for side in SIDES:
			var n: int = at + side.y * w + side.x
			if (side.x != 0 and floori(float(n) / float(w)) != floori(float(at) / float(w))):
				continue
			if in_room.has(n) and not blocked.has(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen.size() == free


# A tile's raw top as the overlap rule alone keeps it, before a chair asks after its table.
static func _kept_alone(occ: Dictionary, map: Variant, tx: int, ty: int) -> Dictionary:
	var top: Dictionary = _raw_top(occ, map, tx, ty)
	if top.is_empty() or int(top["rank"]) == RANK_HELD or top.has("kept"):
		return top
	var rect: Rect2i = _top_rect(occ, top, tx, ty)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx: int = tx + dx
			var ny: int = ty + dy
			var other: Dictionary = _raw_top(occ, map, nx, ny)
			if other.is_empty() or not _beats(occ, other, nx, ny, top, tx, ty):
				continue
			# The two halves of one long table butt on their tops; their canvases' clear margins
			# overlap, and that is not a meeting.
			if top.has("pair") and other.get("pair", null) == top["pair"]:
				continue
			if _meet(rect, _top_rect(occ, other, nx, ny), Vector2i(dx, dy)):
				return {}
	return top


# The kept picture's key on a tile when its rank lies between `lowest` and `highest`, or "".
static func _kept_key(occ: Dictionary, map: Variant, tx: int, ty: int, lowest: int, highest: int) -> String:
	var top: Dictionary = _kept_top(occ, map, tx, ty)
	if top.is_empty() or int(top["rank"]) < lowest or int(top["rank"]) > highest:
		return ""
	return String(top["key"])


# The roll for a scrap of litter on one tile, or "": paved floor outside the clearing that its block
# deals a scrap to (`_block_litter`), and then a scrap of the list by its own hash.
static func _litter_raw(occ: Dictionary, map: Variant, tx: int, ty: int) -> String:
	if not _paved_floor(map, tx, ty) or (occ["clear"] as Rect2i).has_point(Vector2i(tx, ty)):
		return ""
	var keys: Array = occ["litter"]
	if keys.is_empty():
		return ""
	var seed_val: int = int(occ["seed"])
	if not _block_litter(occ, map, tx, ty, int(map.indoors[ty * int(map.w) + tx]) == 1):
		return ""
	return String(keys[variant_index(seed_val, tx, ty, SALT_LITTER_KEY, keys.size())])


# Whether a paved tile is one its block deals a scrap to. The floor is cut into LITTER_BLOCK-square
# blocks on a grid moved by the seed; a block's paved floor on the tile's side of the walls, outside
# the clearing, takes `(floor * 10 + jitter) / LITTER_TENTHS` scraps (the jitter, a hash of the block
# under LITTER_TENTHS, rounds the share up or down evenly), and they go to the tiles whose pick hash,
# divided by one plus the tile's litter weight, is lowest -- the kerbs, the walls and the cluttered
# blocks first. A block's street and its rooms are dealt apart, so a room beside a busy street takes
# its own share. Memoised per block and side in `occ`.
static func _block_litter(occ: Dictionary, map: Variant, tx: int, ty: int, indoors: bool) -> bool:
	var seed_val: int = int(occ["seed"])
	var seed_term: int = int(occ["seed_term"])
	var shift: int = _mix(_hash_t(seed_term, 0, 0, SALT_LITTER_BLOCK_OFFSET))
	var ox: int = shift % LITTER_BLOCK
	var oy: int = (shift >> 8) % LITTER_BLOCK
	var side: int = 1 if indoors else 0
	var block := Vector3i(floori(float(tx + ox) / float(LITTER_BLOCK)), floori(float(ty + oy) / float(LITTER_BLOCK)), side)
	var memo: Dictionary = occ["litter_blocks"]
	if not memo.has(block):
		var clear: Rect2i = occ["clear"]
		var road: PackedByteArray = occ["road"]
		var ranked: Array = []
		for dy in LITTER_BLOCK:
			for dx in LITTER_BLOCK:
				var cx: int = block.x * LITTER_BLOCK - ox + dx
				var cy: int = block.y * LITTER_BLOCK - oy + dy
				if not _paved_floor(map, cx, cy) or int(map.indoors[cy * int(map.w) + cx]) != side or clear.has_point(Vector2i(cx, cy)):
					continue
				var score: int = floori(float(_mix(hash_at(seed_val, cx, cy, SALT_LITTER_PICK))) / float(1 + _litter_weight(map, seed_term, cx, cy, road)))
				ranked.append([score, cy * int(map.w) + cx])
		ranked.sort_custom(func(p: Array, q: Array) -> bool: return int(p[0]) < int(q[0]) or (int(p[0]) == int(q[0]) and int(p[1]) < int(q[1])))
		var jitter: int = _mix(_hash_t(seed_term, block.x, block.y, SALT_LITTER_ROOM if indoors else SALT_LITTER_BLOCK)) % LITTER_TENTHS
		var quota: int = floori(float(ranked.size() * 10 + jitter) / float(LITTER_TENTHS))
		var dealt: Dictionary = {}
		for i in mini(quota, ranked.size()):
			dealt[int((ranked[i] as Array)[1])] = true
		memo[block] = dealt
	return (memo[block] as Dictionary).has(ty * int(map.w) + tx)


# The scrap a tile keeps, or "". A scrap yields to any picture or hold on its own tile and to any
# whose rect meets its own; it never meets another scrap, so it is judged against the rest alone.
static func _kept_litter(occ: Dictionary, map: Variant, tx: int, ty: int) -> String:
	var key: String = _litter_raw(occ, map, tx, ty)
	if key.is_empty() or not _raw_top(occ, map, tx, ty).is_empty():
		return ""
	var rect: Rect2i = _litter_rect(occ, key, tx, ty)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx: int = tx + dx
			var ny: int = ty + dy
			var other: Dictionary = _raw_top(occ, map, nx, ny)
			if not other.is_empty() and _meet(rect, _top_rect(occ, other, nx, ny), Vector2i(dx, dy)):
				return ""
	return key


# Whether no picture this file draws reaches within `radius` tiles (Chebyshev) of tile (tx, ty): no
# kept furnishing, nature picture or scrap whose art rect meets that square. The test the review
# harness's survivor spots take, so no shot has dressing within three tiles of the survivor. Pictures
# are scanned two tiles further out than the square, since a standing one rises two tiles. With
# `with_litter` false the scraps are not asked about: the furniture alone.
static func clear_around(occ: Dictionary, tx: int, ty: int, radius: int, with_litter: bool = true) -> bool:
	var map: Variant = occ["map"]
	var span: int = (2 * radius + 1) * ART_PER_TILE
	var square := Rect2i(-radius * ART_PER_TILE, -radius * ART_PER_TILE, span, span)
	for dy in range(-radius - 2, radius + 3):
		for dx in range(-radius - 2, radius + 3):
			var nx: int = tx + dx
			var ny: int = ty + dy
			if nx < 0 or ny < 0 or nx >= int(map.w) or ny >= int(map.h):
				continue
			var top: Dictionary = _kept_top(occ, map, nx, ny)
			if not top.is_empty() and int(top["rank"]) != RANK_HELD and _meet(square, _top_rect(occ, top, nx, ny), Vector2i(dx, dy)):
				return false
			if not with_litter:
				continue
			var scrap: String = _kept_litter(occ, map, nx, ny)
			if not scrap.is_empty() and _meet(square, _litter_rect(occ, scrap, nx, ny), Vector2i(dx, dy)):
				return false
	return true


# The picture standing on one tile, or "". Pure: a hash of the seed, the tile and the entry's
# index, the tile's own ground, and the overlap rule. Absent or malformed entries draw nothing,
# never a default.
static func furnishing_key(block: Dictionary, map: Variant, seed_val: int, tx: int, ty: int) -> String:
	if map == null or _furnishing_entries(block).is_empty():
		return ""
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return ""
	return _kept_key(occupancy(block, map, seed_val), map, tx, ty, RANK_FLAT, RANK_STANDING)


# Every tile inside `bounds` the observer can see that carries a furnishing, as `{tx, ty, key}`.
# `seen` is the observer's tile set or null for nobody, and nobody sees no furniture: the same shape
# as `nature_tiles`, so draw is a subset of seen. A remembered tile draws none -- a memory of a
# floor is not a memory of the chair on it.
static func furnishing_tiles(block: Dictionary, map: Variant, seen: Variant, seed_val: int, bounds: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if map == null or seen == null or _furnishing_entries(block).is_empty():
		return out
	var occ: Dictionary = occupancy(block, map, seed_val)
	var box: Rect2i = _tile_box(map, bounds)
	for ty in range(box.position.y, box.end.y):
		for tx in range(box.position.x, box.end.x):
			var key: String = _kept_key(occ, map, tx, ty, RANK_FLAT, RANK_STANDING)
			if key.is_empty():
				continue
			if (seen as Object).call("has_tile", tx, ty):
				out.append({"tx": tx, "ty": ty, "key": key})
	return out


# `furnishing_tiles` with the picks of each NATURE_CHUNK-square kept in `cache` (owned and reset by
# the caller, exactly as the nature cache is: never a static, because one gate process boots two
# worlds). Answers what `furnishing_tiles` answers for the same map, seed and block. `occ`, when a
# caller passes one, is the occupancy the picks are made against (main.gd's, which holds the props);
# without one the picks are made against the map alone.
static func furnishing_tiles_cached(block: Dictionary, map: Variant, seen: Variant, seed_val: int, bounds: Dictionary, cache: Dictionary, occ: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if map == null or seen == null or _furnishing_entries(block).is_empty():
		return out
	var box: Rect2i = _tile_box(map, bounds)
	if box.size.x <= 0 or box.size.y <= 0:
		return out
	var chunks_wide: int = ceili(float(int(map.w)) / float(NATURE_CHUNK))
	for cy in range(_chunk_of(box.position.y), _chunk_of(box.end.y - 1) + 1):
		for cx in range(_chunk_of(box.position.x), _chunk_of(box.end.x - 1) + 1):
			var index: int = cy * chunks_wide + cx
			if not cache.has(index):
				if occ.is_empty():
					occ = occupancy(block, map, seed_val)
				cache[index] = _chunk_picks(occ, map, cx, cy, RANK_FLAT, RANK_STANDING)
			for pick in cache[index] as Array:
				var tx: int = int((pick as Dictionary)["tx"])
				var ty: int = int((pick as Dictionary)["ty"])
				if box.has_point(Vector2i(tx, ty)) and (seen as Object).call("has_tile", tx, ty):
					out.append(pick as Dictionary)
	return out


# Tall furnishings use the same hash picks and visibility/cache path as flat ones, but join the
# entity depth sort so a body can pass in front of or behind them. An absent flag is the existing
# flat draw path and remains the default for every older content entry.
static func furnishing_is_standing(block: Dictionary, key: String) -> bool:
	var listed: Variant = block.get("furnishings")
	if not (listed is Array):
		return false
	for raw in listed as Array:
		if raw is Dictionary and String((raw as Dictionary).get("key", "")) == key:
			return bool((raw as Dictionary).get("standing", false))
	return false


static func standing_furnishing_tiles_cached(block: Dictionary, map: Variant, seen: Variant, seed_val: int, bounds: Dictionary, cache: Dictionary, occ: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pick in furnishing_tiles_cached(block, map, seen, seed_val, bounds, cache, occ):
		if furnishing_is_standing(block, String(pick.get("key", ""))):
			out.append(pick)
	return out


# The flat dressing a bake region holds (world_layers.gd's DECOR layer): every nature picture and
# every flat furnishing picture on the tiles of `region` (a Rect2i whose `end` is exclusive, clipped
# to the map here), as `{nature: [placed], furnishings: [placed]}` (`_placed`). Nothing is asked of an
# observer -- the bake's LIVE mask decides which of them show, so a picture on a tile nobody sees is
# baked and never drawn. The picks are the per-tile ones nature_tiles and furnishing_tiles make, so a
# baked picture is the picture the per-frame draw made. A standing furnishing is left out: it joins
# the entity sort, as standing_furnishing_tiles_cached says. `occ` as furnishing_tiles_cached takes it.
static func decor_picks(block: Dictionary, map: Variant, seed_val: int, region: Rect2i, occ: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {"nature": [], "furnishings": []}
	if map == null or block.is_empty():
		return out
	if occ.is_empty():
		occ = occupancy(block, map, seed_val)
	var x0: int = maxi(0, region.position.x)
	var y0: int = maxi(0, region.position.y)
	var x1: int = mini(int(map.w), region.end.x)
	var y1: int = mini(int(map.h), region.end.y)
	for ty in range(y0, y1):
		for tx in range(x0, x1):
			var top: Dictionary = _kept_top(occ, map, tx, ty)
			if top.is_empty() or int(top["rank"]) >= RANK_STANDING:
				continue
			var listing: String = "nature" if int(top["rank"]) == RANK_NATURE else "furnishings"
			(out[listing] as Array).append(_placed(top, tx, ty))
	return out


# One flat picture's record: its tile, its key, where in the tile it sits (`ox`, `oy`, in whole art
# pixels from the tile's centre line and its south edge -- see `_range_x` and `_range_y`) and whether
# it is mirrored, all off the tile's raw top. A pure hash of the seed and the tile, so the grid the
# placement rolls make is broken the same way on every boot.
static func _placed(top: Dictionary, tx: int, ty: int) -> Dictionary:
	return {
		"tx": tx,
		"ty": ty,
		"key": String(top["key"]),
		"ox": int(top.get("ox", 0)),
		"oy": int(top.get("oy", 0)),
		"flip": bool(top.get("flip", false)),
	}


# Whether a tile's picture is mirrored, on the salt the caller names.
static func flip_at(seed_val: int, tx: int, ty: int, salt: int) -> bool:
	return _mix(hash_at(seed_val, tx, ty, salt)) & 1 == 1


# The tiles a furnishing may not stand on: a square of FURNISH_CLEAR around the colony's start,
# where the survivor is put on the first frame and where the other boot colonists are offset from
# (within two tiles). Derived from the map alone, so the same map keeps the same clearing on every
# boot.
static func _clear_of(map: Variant) -> Rect2i:
	if map == null:
		return Rect2i()
	var start: Vector2i = SimBootRes.colony_start(map)
	var side: int = FURNISH_CLEAR * 2 + 1
	return Rect2i(start - Vector2i(FURNISH_CLEAR, FURNISH_CLEAR), Vector2i(side, side))


# A second mixing step over the hash. `hash_at` is a plain XOR of products, and taking its low bits
# modulo a small rarity lays the hits on a lattice: the grid the first draft of the furnishings
# showed. The multiply-xorshift finaliser breaks that, and keeps the value non-negative.
static func _mix(value: int) -> int:
	var x: int = value & 0xffffffff
	x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0xffffffff
	x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0xffffffff
	x = x ^ (x >> 16)
	return x & 0x7fffffff


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


# A2's fitted pack modules, keyed by the same material name as the generated fallback. A missing
# table is intentionally an empty dictionary so old dressing blocks keep the prior drawing.
static func wall_modules(block: Dictionary, material: String) -> Dictionary:
	if material not in ["render", "brick"]:
		return {}
	var modules: Variant = block.get("wall_modules")
	if not (modules is Dictionary):
		return {}
	var entry: Variant = (modules as Dictionary).get(material)
	if not entry is Dictionary:
		return {}
	var allowed: Array[String] = ["west", "middle", "east"]
	if material == "render":
		allowed.append_array(["window", "door_open", "door_closed", "corner_west", "corner_east", "leg_west", "leg_east"])
	var result: Dictionary = {}
	for slot_v in allowed:
		var slot: String = String(slot_v)
		var value: Variant = (entry as Dictionary).get(slot, "")
		if value is String and not String(value).is_empty():
			result[slot] = String(value)
	return result


# This is deliberately a shape check, not an art-key table: source and image keys belong to
# street.json/authored.json. It prevents dead material/role declarations the renderer never reads.
static func wall_modules_fault(block: Dictionary) -> String:
	var modules: Variant = block.get("wall_modules")
	if not modules is Dictionary:
		return "wall_modules is not an object"
	var module_map: Dictionary = modules as Dictionary
	for material_v in module_map.keys():
		var material: String = String(material_v)
		if material not in ["render", "brick"]:
			return "unsupported wall module material %s" % material
		var entry: Variant = module_map[material_v]
		if not entry is Dictionary:
			return "wall module material %s is not an object" % material
		var roles: Array[String] = ["west", "middle", "east"]
		if material == "render":
			roles.append_array(["window", "door_open", "door_closed", "corner_west", "corner_east", "leg_west", "leg_east"])
		for role_v in (entry as Dictionary).keys():
			var role: String = String(role_v)
			var value: Variant = (entry as Dictionary)[role_v]
			if role not in roles:
				return "unsupported wall module role %s.%s" % [material, role]
			if not value is String or String(value).is_empty():
				return "wall module role %s.%s has no key" % [material, role]
	return ""


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


# The window shapes `_draw_window_glass` chooses between by the walls either side of the tile: a
# long pane in a run east-west, one in a run north-south, a small square one where neither is clear.
const GLASS_SHAPES: Array[String] = ["ew", "ns", "square"]


# `[pane, frame]`, the two picture keys the faces block's `glass` map names for one window shape,
# or an empty array when the block names no glass, an unknown shape, or only one of the pair -- the
# caller then draws the procedural pane, the supported fallback. Pure over one block.
static func glass_keys(block: Dictionary, shape: String) -> Array[String]:
	var out: Array[String] = []
	var faces: Variant = block.get("faces")
	if not GLASS_SHAPES.has(shape) or not (faces is Dictionary):
		return out
	var glass: Variant = (faces as Dictionary).get("glass")
	if not (glass is Dictionary):
		return out
	var pane: String = String((glass as Dictionary).get("pane_" + shape, ""))
	var frame: String = String((glass as Dictionary).get("frame_" + shape, ""))
	if pane.is_empty() or frame.is_empty():
		return out
	out.append(pane)
	out.append(frame)
	return out


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


# A scrap of litter on paved floor, outdoors or in a room, or "": the roll, then the overlap rule.
# Two independent hashes: one decides whether this tile carries anything at all (`_litter_raw`'s
# weighted roll), the other which scrap it is -- so making the scatter denser cannot silently
# reshuffle which key lands where. Builds its own occupancy, so a caller drawing many tiles keeps one.
static func litter_key(block: Dictionary, map: Variant, seed_val: int, tx: int, ty: int) -> String:
	if map == null or _litter_keys(block).is_empty():
		return ""
	return _kept_litter(occupancy(block, map, seed_val), map, tx, ty)


# The scrap record for one tile, or {}: `{tx, ty, key, ox, oy, flip}`, a flat picture's record on
# the litter salts. A caller drawing many tiles keeps its occupancy across them (main.gd's scatter).
static func litter_placed_in(occ: Dictionary, tx: int, ty: int) -> Dictionary:
	var key: String = _kept_litter(occ, occ["map"], tx, ty)
	if key.is_empty():
		return {}
	var off: Vector2i = _litter_offsets(int(occ["seed_term"]), (occ["sizes"] as Dictionary)[key], tx, ty)
	var seed_val: int = int(occ["seed"])
	var tints: Array = occ.get("litter_tints", [Color.WHITE])
	return {
		"tx": tx, "ty": ty, "key": key, "ox": off.x, "oy": off.y,
		"flip": flip_at(seed_val, tx, ty, SALT_LITTER_FLIP),
		"flip_v": flip_at(seed_val, tx, ty, SALT_LITTER_FLIP_V),
		"tint": tints[variant_index(seed_val, tx, ty, SALT_LITTER_TINT, tints.size())],
	}


# A floor tile on paved ground, indoors or out: the one surface test the litter takes. Rubble stays
# the outdoor surface it always was; a room's floor is paved in the sim, so litter lies on it too.
static func _paved_floor(map: Variant, tx: int, ty: int) -> bool:
	if map == null:
		return false
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return false
	if int(map.tiles[ty * int(map.w) + tx]) != SimTileMap.Tile.Floor:
		return false
	return int(SimSurface.surface_at(map, tx, ty)) == SimSurface.Surface.Paved


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
