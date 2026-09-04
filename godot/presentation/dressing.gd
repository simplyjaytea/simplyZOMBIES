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
#   * **The whole run picks one variant.** A car spans two or three tiles, and hashing each tile
#     separately would paint a pale bonnet on a burnt-out boot. So the hash is taken on the run's
#     *anchor* -- its north or west end -- which every tile of the run agrees on.
#   * **Pure statics, no static state.** Same reason road_paint.gd has none: a cache here would
#     be shared between the two worlds one gate process boots. The content block is resolved once
#     per frame by the drawing node and passed in.
#
# North-authored, one tile wide: a run lying east-west draws the same keys through a quarter-turn
# transform (`run_angle`) rather than through a second set of files. `main.gd` owns that transform
# the way it owns the player's, and `assets/sprites/README.md` records the convention.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimSurface = preload("res://sim/map/surface.gd")
const Appearance = preload("res://presentation/appearance.gd")

# The one dressing entry presentation asks for. Named here so main.gd carries no content id, the
# same rule PROP_KINDS and PLAYER_LOOK_ID follow.
const BLOCK_ID: String = "dressing.street"

# Which piece of a run a tile is. `solo` is its own thing rather than a degenerate front: a
# single Low tile is one tile long, and a car is not. Nothing in content declares a picture for
# it today -- the skip that would have was cut with the worldgen change that stood more lone
# tiles, because dressing may not move the simulation (docs/23) -- so a solo classifies here,
# resolves no key, and draws the procedural cover block. The classification stays because it is
# what stops a lone tile being drawn as half a car.
const SEG_SOLO: String = "solo"
const SEG_FRONT: String = "front"
const SEG_MID: String = "mid"
const SEG_REAR: String = "rear"

# How far `run_anchor` will walk before giving up. Wreck runs are 2-3 tiles (worldgen's
# `_dress_occluders`), but the annex template stamps Low tiles too and nothing stops a future
# pass from laying a longer one; the cap keeps a per-tile draw-time walk bounded whatever the map
# does, and a run longer than this simply anchors early -- which changes a colour, not a shape.
const ANCHOR_MAX_STEPS: int = 8

# One street tile in LITTER_RARITY carries a scrap. Sparse on purpose: litter is texture, and
# texture that lands on a third of the street stops being texture and becomes a surface.
const LITTER_RARITY: int = 17

# Hash salts, one per independent decision, so two choices about the same tile cannot correlate.
const SALT_VARIANT: int = 1
const SALT_LITTER_PICK: int = 2
const SALT_LITTER_KEY: int = 3
const SALT_RUBBLE_KEY: int = 4
# The ground atlas variant under a floor tile (Appearance.ground_cell): one salt, four cells a row.
const SALT_GROUND: int = 5
# Which tall tree picture a Tree tile takes out of the block's `trees.tall` list.
const SALT_TREE: int = 6
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


# Which piece of a wreck this tile is, or "" when it is not a Low tile at all.
#
# The axis is read off the neighbours per tile rather than stored, the same way _draw_solid_tile
# reads its exposed faces and kerb_edges its boundary: a run cut short by a doorway or a protected
# tile is shorter *now*, and the picture has to agree with the map that stands.
#
# A tile with neighbours on both axes -- an L, a cross, a clump the annex stamped -- resolves MID.
# Mid is the piece with no ends, so it tiles against anything, and a junction of wrecks reads as
# one mass rather than as two cars fighting over a corner.
static func segment_at(map: Variant, tx: int, ty: int) -> String:
	if not _is_low(map, tx, ty):
		return ""
	var n: bool = _is_low(map, tx, ty - 1)
	var s: bool = _is_low(map, tx, ty + 1)
	var e: bool = _is_low(map, tx + 1, ty)
	var w: bool = _is_low(map, tx - 1, ty)
	var vertical: bool = n or s
	var horizontal: bool = e or w
	if not vertical and not horizontal:
		return SEG_SOLO
	if vertical and horizontal:
		return SEG_MID
	if vertical:
		if not n:
			return SEG_FRONT
		if not s:
			return SEG_REAR
		return SEG_MID
	# East-west, drawn through a quarter turn clockwise, so up-canvas becomes east: the nose is
	# the *east* end of the run and the tail the west one.
	if not e:
		return SEG_FRONT
	if not w:
		return SEG_REAR
	return SEG_MID


# How far to spin the north-authored art for the run this tile belongs to. 0 for a vertical run
# and for a solo; a quarter turn clockwise for an east-west one. Nothing else -- a wreck has an
# axis, not a facing, and there is no third case for it to have.
static func run_angle(map: Variant, tx: int, ty: int) -> float:
	if not _is_low(map, tx, ty):
		return 0.0
	var vertical: bool = _is_low(map, tx, ty - 1) or _is_low(map, tx, ty + 1)
	if vertical:
		return 0.0
	if _is_low(map, tx + 1, ty) or _is_low(map, tx - 1, ty):
		return PI / 2.0
	return 0.0


# The tile every member of a run agrees to hash on: the north end of a vertical run, the west end
# of a horizontal one, the tile itself for a solo. This is what makes a three-tile car one colour.
static func run_anchor(map: Variant, tx: int, ty: int) -> Vector2i:
	var here := Vector2i(tx, ty)
	if not _is_low(map, tx, ty):
		return here
	var step := Vector2i.ZERO
	if _is_low(map, tx, ty - 1) or _is_low(map, tx, ty + 1):
		step = Vector2i(0, -1)
	elif _is_low(map, tx + 1, ty) or _is_low(map, tx - 1, ty):
		step = Vector2i(-1, 0)
	else:
		return here
	var at := here
	for _i in ANCHOR_MAX_STEPS:
		var next := at + step
		if not _is_low(map, next.x, next.y):
			break
		at = next
	return at


# The sprite key for a Low tile, or "" when the tile is not Low, the block declares nothing, or
# the variant is missing the segment it was asked for.
static func wreck_key(block: Dictionary, map: Variant, seed_val: int, tx: int, ty: int) -> String:
	var segment: String = segment_at(map, tx, ty)
	if segment.is_empty():
		return ""
	var wrecks: Variant = block.get("wrecks")
	if not (wrecks is Dictionary):
		return ""
	if segment == SEG_SOLO:
		# "" when content declares no solo picture, which is the shipped state: the caller draws
		# the procedural cover block, the same graceful absence an empty block gets.
		return String((wrecks as Dictionary).get("solo", ""))
	var variants: Variant = (wrecks as Dictionary).get("variants")
	if not (variants is Array):
		return ""
	var anchor: Vector2i = run_anchor(map, tx, ty)
	var index: int = variant_index(seed_val, anchor.x, anchor.y, SALT_VARIANT, (variants as Array).size())
	if index < 0:
		return ""
	var chosen: Variant = (variants as Array)[index]
	if not (chosen is Dictionary):
		return ""
	return String((chosen as Dictionary).get(segment, ""))


# Whether a tile is outdoor open floor carrying `surface` -- the eligibility both scatters share.

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
