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

# The one dressing entry presentation asks for. Named here so main.gd carries no content id, the
# same rule PROP_KINDS and PLAYER_LOOK_ID follow.
const BLOCK_ID: String = "dressing.street"

# One paved floor tile in LITTER_RARITY carries a scrap on the street, and one in
# LITTER_RARITY_INDOORS in a room. Still sparse: litter is texture, and texture that lands on a
# third of the floor stops being texture and becomes a surface. It was 1 in 17 on the street until
# the A12 density slice, whose before shots read as bare street. The rooms roll more often because
# the overlap rule (`_kept_top`) takes the litter under a table or a shelf and a room is mostly
# furniture: the roll is set so the rate that is kept lands near 1 in 6 of the visible floor, as
# A12's round-4 measure counts it. Measured, not a reference.
const LITTER_RARITY: int = 5
const LITTER_RARITY_INDOORS: int = 2

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
const SALT_FLIP: int = 402

# Which tile keeps a picture where two would meet (the overlap rule, `_kept_top`): one rank per kind
# of picture, highest first, and the hash that breaks a tie within a rank.
const RANK_NATURE: int = 1
const RANK_FLAT: int = 2
const RANK_STANDING: int = 3
const SALT_WINNER: int = 403

# The largest side a picture may have in art pixels: a canvas in the block's `sizes` is checked
# against it, so a fabricated size cannot make a picture that covers the district.
const SIZE_LIMIT: int = 64
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
# `{key, where, surfaces, rarity, beside?, standing?}`: the picture, `"indoors"` or `"outdoors"`, the ground
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
# wall within one tile in any direction (or a kerb, for the bags), and no entry is placed with a door directly north or
# south of it.

# Well clear of SALT_NATURE's block of entries.
const SALT_FURNISH: int = 300

# How far dressing keeps off the colony's start, in tiles (Chebyshev). The square is one tile
# wider than the three tiles check_trees.gd holds it to: a picture hangs across the tiles it
# overlaps, so a shelf on the square's edge reached into the three-tile zone it was meant to keep
# clear. Litter keeps off the same square.
const FURNISH_CLEAR: int = 4

# A flat picture is placed in whole art pixels. A tile is ART_PER_TILE art pixels across, and its
# jitter is at most JITTER_PX of them either way, so every placement lands on the art grid the
# ground is drawn on at any zoom (one art pixel is blit_scale screen pixels).
const ART_PER_TILE: int = 32
const JITTER_PX: int = 6

# The fields a furnishing entry is read by, in `_furnishing_entries`' arrays.
const FE_STANDING: int = 6

# The one thing a `beside` may name here, and the tile class it means.
const FURNISH_BESIDE_WALL: String = "wall"
const FURNISH_INDOORS: String = "indoors"
const FURNISH_OUTDOORS: String = "outdoors"


# The block's `furnishings` list as plain arrays, one per usable entry, in list order: `[key,
# rarity, salt_term, surface_mask, indoors, beside_wall, standing]` -- `_nature_entries`'
# shape with the ground's `where`, the wall clause in place of the water one, and the standing
# flag the overlap rule reads (FE_STANDING). An entry with no key, a rarity under two, no
# real surface or a `where` that is not one of the two is dropped rather than carpeting the
# district; `[]` for a block that declares none. Pure.
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
		out.append([key, rarity, (SALT_FURNISH + i) * _HASH_SALT, mask, where == FURNISH_INDOORS, beside == FURNISH_BESIDE_WALL, bool(entry.get("standing", false))])
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


# Whether an outdoor tile beside the paving's edge lies within one tile of this one: a grass or dirt
# tile that is some neighbour's kerb. A trash bag may stand on either side of a kerb.
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
	return _wall_within_one(map, tx, ty) or _kerb_within_one(map, tx, ty)


# The picture one tile's own roll and ground give it, before the placement rules, or "". The first
# entry whose `where` and surface match, whose roll lands and whose ground fits. The roll is
# `nature`'s -- `hash_at` shifted before the modulo, written out with the salt already multiplied.
# The overlap rule reads each neighbour's raw top (`_raw_top`), so the raw picks never recurse.
static func _furnishing_raw(entries: Array, map: Variant, seed_term: int, tx: int, ty: int, clear: Rect2i) -> String:
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
		if bool(entry[4]) != indoors:
			continue
		if (int(entry[3]) >> surface) & 1 == 0:
			continue
		if _mix((base ^ int(entry[2])) & 0x7fffffff) % int(entry[1]) != 0:
			continue
		if _furnishing_ground_fits(entry as Array, map, tx, ty):
			return String(entry[0])
	return ""


# The overlap rule. A tile's raw top (`_raw_top`) is one picture: the furnishing its roll gives,
# else the nature picture its roll gives, else nothing. A tile keeps its top unless a neighbour's
# raw top outranks it and the two art rects meet (`_kept_top`). Ranks: a standing furnishing
# (RANK_STANDING) over a flat one (RANK_FLAT), a flat one over a nature picture (RANK_NATURE), and
# a scrap of litter (rank 0, below RANK_NATURE) gives way to any of them. A tie in rank goes to the tile whose
# SALT_WINNER hash is higher. So two pictures that meet are never both kept, and nothing a
# furnishing holds is taken by nature or litter.
#
# The rule reads raw tops, not kept ones: a picture that loses its place still blocks the pictures
# beside it. That costs a little furniture and keeps every answer local and pure, because no tile
# needs a chain of its neighbours' decisions to know its own. Every picture fits within one tile of
# its own tile (the tallest, the streetlamp, is 62 art px in a 32 px tile), so the eight neighbours
# are the only tiles whose pictures can meet it.

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
		if w > 0 and h > 0 and w <= SIZE_LIMIT and h <= SIZE_LIMIT:
			out[String(key_v)] = Vector2i(w, h)
	return out


# The block's `litter` keys that have a size, in list order: the only scraps a tile can draw.
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
# sizes, the seed and its term, the clearing, the map itself, and `memo`, each tile's raw top by
# tile index. An occupancy belongs to one map; a caller that keeps one across frames rebuilds it
# when the map changes.
static func occupancy(block: Dictionary, map: Variant, seed_val: int) -> Dictionary:
	return {"map": map, "furnish": _furnishing_entries(block), "nature": _nature_entries(block), "litter": _litter_keys(block), "sizes": _sizes(block), "seed": seed_val, "seed_term": seed_val * _HASH_SEED, "clear": _clear_of(map), "memo": {}}


# The one flag `_entry_flag` reads, or false for a key no entry carries.
static func _entry_flag(entries: Array, key: String, index: int) -> bool:
	if key.is_empty():
		return false
	for entry in entries:
		if String((entry as Array)[0]) == key:
			return bool((entry as Array)[index])
	return false


# A picture's art rect in its own tile's frame, in whole art pixels: `size` centred on the tile's
# centre line (`ox`), its base `oy` above the tile's south edge. The left edge is taken on the art
# grid with an odd width rounded down, so a scrap of five pixels lands on the same grid as a table.
static func _art_rect(size: Vector2i, ox: int, oy: int) -> Rect2i:
	var left: int = (ART_PER_TILE >> 1) + ox - (size.x >> 1)
	return Rect2i(left, ART_PER_TILE + oy - size.y, size.x, size.y)


# The rect of a flat or nature picture on tile (tx, ty), from its size and that tile's own offset.
static func _top_rect(occ: Dictionary, top: Dictionary, tx: int, ty: int) -> Rect2i:
	var size: Vector2i = (occ["sizes"] as Dictionary)[String(top["key"])]
	var seed_val: int = int(occ["seed"])
	return _art_rect(size, _jitter(seed_val, tx, ty, SALT_JITTER_X), _lift(seed_val, tx, ty, SALT_JITTER_Y))


# The rect of a scrap of litter on tile (tx, ty), on the litter salts.
static func _litter_rect(occ: Dictionary, key: String, tx: int, ty: int) -> Rect2i:
	var size: Vector2i = (occ["sizes"] as Dictionary)[key]
	var seed_val: int = int(occ["seed"])
	return _art_rect(size, _jitter(seed_val, tx, ty, SALT_LITTER_JITTER_X), _lift(seed_val, tx, ty, SALT_LITTER_JITTER_Y))


# Whether rect `a` meets rect `b` once `b` is moved by `shift` tiles. Open intervals: pictures that
# only touch an edge do not meet.
static func _meet(a: Rect2i, b: Rect2i, shift: Vector2i) -> bool:
	var bx: int = b.position.x + shift.x * ART_PER_TILE
	var by: int = b.position.y + shift.y * ART_PER_TILE
	return a.position.x < bx + b.size.x and bx < a.position.x + a.size.x and a.position.y < by + b.size.y and by < a.position.y + a.size.y


# What a tile would draw before the overlap rule: the furnishing its roll gives, else the nature
# picture, as `{key, rank}`, or {} for nothing. Memoised per tile in `occ`.
static func _raw_top(occ: Dictionary, map: Variant, tx: int, ty: int) -> Dictionary:
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return {}
	var memo: Dictionary = occ["memo"]
	var index: int = ty * int(map.w) + tx
	if not memo.has(index):
		memo[index] = _raw_top_uncached(occ, map, tx, ty)
	return memo[index] as Dictionary


static func _raw_top_uncached(occ: Dictionary, map: Variant, tx: int, ty: int) -> Dictionary:
	var clear: Rect2i = occ["clear"]
	if clear.has_point(Vector2i(tx, ty)):
		return {}
	var sizes: Dictionary = occ["sizes"]
	var seed_term: int = int(occ["seed_term"])
	var furnish: Array = occ["furnish"]
	var key: String = _furnishing_raw(furnish, map, seed_term, tx, ty, clear)
	if not key.is_empty() and sizes.has(key):
		return {"key": key, "rank": RANK_STANDING if _entry_flag(furnish, key, FE_STANDING) else RANK_FLAT}
	key = _nature_pick(occ["nature"], map, seed_term, tx, ty)
	if not key.is_empty() and sizes.has(key):
		return {"key": key, "rank": RANK_NATURE}
	return {}


# Whether the picture on tile (nx, ny) beats the one on (tx, ty) for the space they share.
static func _beats(occ: Dictionary, other: Dictionary, nx: int, ny: int, mine: Dictionary, tx: int, ty: int) -> bool:
	if int(other["rank"]) != int(mine["rank"]):
		return int(other["rank"]) > int(mine["rank"])
	var seed_val: int = int(occ["seed"])
	var theirs: int = _mix(hash_at(seed_val, nx, ny, SALT_WINNER))
	var ours: int = _mix(hash_at(seed_val, tx, ty, SALT_WINNER))
	if theirs != ours:
		return theirs > ours
	return ny > ty or (ny == ty and nx > tx)


# The picture a tile keeps among the furnishings and nature, as `{key, rank}`, or {}: its raw top,
# unless an overlapping neighbour's raw top beats it.
static func _kept_top(occ: Dictionary, map: Variant, tx: int, ty: int) -> Dictionary:
	var top: Dictionary = _raw_top(occ, map, tx, ty)
	if top.is_empty():
		return {}
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
			if _meet(rect, _top_rect(occ, other, nx, ny), Vector2i(dx, dy)):
				return {}
	return top


# The kept picture's key on a tile when its rank lies between `lowest` and `highest`, or "".
static func _kept_key(occ: Dictionary, map: Variant, tx: int, ty: int, lowest: int, highest: int) -> String:
	var top: Dictionary = _kept_top(occ, map, tx, ty)
	if top.is_empty() or int(top["rank"]) < lowest or int(top["rank"]) > highest:
		return ""
	return String(top["key"])


# The roll for a scrap of litter on one tile, or "": paved floor outside the clearing, one tile in
# LITTER_RARITY, and then a scrap of the list by its own hash.
static func _litter_raw(occ: Dictionary, map: Variant, tx: int, ty: int) -> String:
	if not _paved_floor(map, tx, ty) or (occ["clear"] as Rect2i).has_point(Vector2i(tx, ty)):
		return ""
	var keys: Array = occ["litter"]
	if keys.is_empty():
		return ""
	var seed_val: int = int(occ["seed"])
	var indoors: bool = int(map.indoors[ty * int(map.w) + tx]) == 1
	var rarity: int = LITTER_RARITY_INDOORS if indoors else LITTER_RARITY
	if _mix(hash_at(seed_val, tx, ty, SALT_LITTER_PICK)) % rarity != 0:
		return ""
	return String(keys[variant_index(seed_val, tx, ty, SALT_LITTER_KEY, keys.size())])


# The scrap a tile keeps, or "". A scrap yields to any picture on its own tile and to any picture
# whose art meets its own; it never meets another scrap, so it is judged against the furnishings and
# nature alone.
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


# Whether a tile and its eight neighbours carry no picture of any kind before the overlap rule:
# the test the harness's survivor spots take, so no shot has a picture over the survivor's legs.
static func free_ring(block: Dictionary, map: Variant, seed_val: int, tx: int, ty: int) -> bool:
	var occ: Dictionary = occupancy(block, map, seed_val)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if not _raw_top(occ, map, tx + dx, ty + dy).is_empty() or not _litter_raw(occ, map, tx + dx, ty + dy).is_empty():
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
# worlds). Answers what `furnishing_tiles` answers for the same map, seed and block.
static func furnishing_tiles_cached(block: Dictionary, map: Variant, seen: Variant, seed_val: int, bounds: Dictionary, cache: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if map == null or seen == null or _furnishing_entries(block).is_empty():
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


static func standing_furnishing_tiles_cached(block: Dictionary, map: Variant, seen: Variant, seed_val: int, bounds: Dictionary, cache: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pick in furnishing_tiles_cached(block, map, seen, seed_val, bounds, cache):
		if furnishing_is_standing(block, String(pick.get("key", ""))):
			out.append(pick)
	return out


# The flat dressing a bake region holds (world_layers.gd's DECOR layer): every nature picture and
# every flat furnishing picture on the tiles of `region` (a Rect2i whose `end` is exclusive, clipped
# to the map here), as `{nature: [{tx, ty, key}], furnishings: [{tx, ty, key}]}`. Nothing is asked
# of an observer -- the bake's LIVE mask decides which of them show, so a picture on a tile nobody
# sees is baked and never drawn. The picks are the per-tile ones nature_tiles and furnishing_tiles
# make, so a baked picture is the picture the per-frame draw made. A standing furnishing is left
# out: it joins the entity sort, as standing_furnishing_tiles_cached says.
static func decor_picks(block: Dictionary, map: Variant, seed_val: int, region: Rect2i) -> Dictionary:
	var out: Dictionary = {"nature": [], "furnishings": []}
	if map == null or block.is_empty():
		return out
	var occ: Dictionary = occupancy(block, map, seed_val)
	var x0: int = maxi(0, region.position.x)
	var y0: int = maxi(0, region.position.y)
	var x1: int = mini(int(map.w), region.end.x)
	var y1: int = mini(int(map.h), region.end.y)
	for ty in range(y0, y1):
		for tx in range(x0, x1):
			var top: Dictionary = _kept_top(occ, map, tx, ty)
			if top.is_empty() or int(top["rank"]) == RANK_STANDING:
				continue
			var listing: String = "nature" if int(top["rank"]) == RANK_NATURE else "furnishings"
			(out[listing] as Array).append(_placed(String(top["key"]), seed_val, tx, ty))
	return out


# One flat picture's record: its tile, its key, where in the tile it sits (`ox`, `oy`, in whole art
# pixels from the tile's centre line and its south edge -- see `_jitter` and `_lift`) and whether it
# is mirrored. A pure hash of the seed and the tile, so the grid the placement rolls make is broken
# the same way on every boot.
static func _placed(key: String, seed_val: int, tx: int, ty: int) -> Dictionary:
	return {
		"tx": tx,
		"ty": ty,
		"key": key,
		"ox": _jitter(seed_val, tx, ty, SALT_JITTER_X),
		"oy": _lift(seed_val, tx, ty, SALT_JITTER_Y),
		"flip": flip_at(seed_val, tx, ty, SALT_FLIP),
	}


# Horizontal offset from the tile's centre line, in whole art pixels: -JITTER_PX to JITTER_PX. A
# whole art pixel at any zoom is a whole number of screen pixels, so a picture never lands between
# two of the ground's art pixels.
static func _jitter(seed_val: int, tx: int, ty: int, salt: int) -> int:
	return _mix(hash_at(seed_val, tx, ty, salt)) % (2 * JITTER_PX + 1) - JITTER_PX


# Vertical offset of a picture's base from its tile's south edge, in whole art pixels: zero down
# to -JITTER_PX, never past the edge. The base stays on its own tile, so a barrel can no longer
# stand on the grass south of the asphalt it was rolled for.
static func _lift(seed_val: int, tx: int, ty: int, salt: int) -> int:
	return -(_mix(hash_at(seed_val, tx, ty, salt)) % (JITTER_PX + 1))


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
# Two independent hashes: one decides whether this tile carries anything at all (1 in
# LITTER_RARITY), the other which scrap it is -- so making the scatter denser cannot silently
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
	var seed_val: int = int(occ["seed"])
	return {"tx": tx, "ty": ty, "key": key, "ox": _jitter(seed_val, tx, ty, SALT_LITTER_JITTER_X), "oy": _lift(seed_val, tx, ty, SALT_LITTER_JITTER_Y), "flip": flip_at(seed_val, tx, ty, SALT_LITTER_FLIP)}


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
