extends RefCounted
# What the map looks like where the sim only knows a tile class -- wrecked cars on runs of Low
# tiles, debris over rubble and litter over street pavement.
#
# The sim's vocabulary here is deliberately coarse: `Tile.Low` is "cover you can shoot over" to
# everything that walks, sees or shoots, and `SURFACE_RUBBLE` is "slower and louder underfoot".
# Neither says car, skip or broken concrete, and neither should -- so this file turns the class
# into a picture, out of content (`content/dressing/street.json`), at draw time.
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
	var rx: int = int(record.get("x", 0))
	var ry: int = int(record.get("y", 0))
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
static func vehicle_ground_point(record: Dictionary) -> Vector2:
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
