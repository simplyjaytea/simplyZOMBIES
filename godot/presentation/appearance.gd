extends RefCounted
# What a thing looks like, resolved from content rather than decided in the draw loop.
#
# docs/20-ecs-and-content.md: adding a type should be "a JSON entry with zero code".
# Appearance was the last axis where that was untrue -- _draw_entities used to carry
#   if ztype == "zombie.screamer": col = Color(0.85, 0.35, 0.28)
# so a new zombie type needed a presentation edit to look like anything. Those colours now
# live in zombies/*.json as `appearance.tint`.
#
# Presentation-only, per ui/README.md's boundary: sim/ must never import this. It reads
# world.content, which is the same tree the sim modules read.
#
# Sprites are optional: `resolve` returns null for a key with no file, and every caller falls
# back to the procedural shapes -- the fallback is a supported path, not a temporary one, and
# check_appearance.gd asserts it stays that way. Every shipped body, prop and street key has
# art today, authored on the ART_NATIVE (32 px) centre-anchored canvas camera.gd names.

const Palette = preload("res://presentation/palette.gd")
const CameraUtil = preload("res://presentation/camera.gd")
const SimSurface = preload("res://sim/map/surface.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")

const SPRITE_DIR: String = "res://assets/sprites"

# The content id the player's own body resolves its look from.
#
# Every other body on screen carries an id already: a zombie hands over its type id, a unique
# survivor its identity (or rolled `look`) id, a raider its archetype id. The player carries none
# of the three, so `for_entity` had nothing to look up and the shipped game had no player art at
# all -- which is what the style fixtures turned up. This constant is the one place the id is
# named, so `main.gd` still contains no `if id == ...` (the same rule PROP_KINDS follows).
#
# It lives under content/players/, not content/survivors/: survivor.schema.json pins ids to
# ^survivor\.unique\. and `SimSurvivors.list_uniques` boots everything in that directory, so an
# entry there would both fail the frozen oracle's Ajv and spawn a phantom colonist.
const PLAYER_LOOK_ID: String = "player.body"

# The pawn canvas: one ART_NATIVE tile wide and one and a half tall, anchored on the feet
# (assets/sprites/README.md). The reference's own proportion -- a person about 0.7 of a tile wide
# and 1.3 tall -- with three or four pixels of side margin so the flip never clips, and eight rows
# of headroom. Its blit height is 1.5 x zoom, an integer on every rung of the ladder; a 64-tall
# canvas was refused because it wastes 24 rows and a full-tile overhang north clips against wall
# rows. Every body and every equip overlay is authored on it (PAWN_KEYS); tools/sprites/build.py
# carries the mirror list, because Python cannot read GDScript.
const PAWN_CANVAS: Vector2i = Vector2i(int(CameraUtil.ART_NATIVE), int(CameraUtil.ART_NATIVE) * 3 / 2)
const PAWN_KEYS: Array[String] = [
	"player_body", "survivor_mara", "survivor_ellis", "survivor_colonist",
	"zombie_shambler", "zombie_screamer", "zombie_bloater", "raider_body",
	"item_pack_hiking_equip", "item_pack_hiking_equip_front", "item_bat_aluminium_equip",
]

# Where a picture hangs on its entity's ground point. A square canvas is a tile-sized thing seen
# from above and centres on the point; anything else is a standing picture and stands on it --
# derived from the shape rather than from a second list of keys, so the tree and vehicle sheets
# the later slices add are feet-anchored by construction (a second list is the dead-socket
# family: one entry forgotten and a picture floats half a tile high without ever erroring).
enum Anchor { Centre = 0, Feet = 1 }

# How far below the ground point the soles stand, in screen pixels: the contact shadow's own
# offset, which main.gd draws at exactly this drop, so the shadow line and the sole line are one
# number and cannot drift apart. A screen-pixel constant on purpose, like the facing line's +12:
# a readout of the interface, not a length in the world.
const FOOT_DROP_PX: float = 3.0

# Equipment slots the renderer draws on a body. A slot with no anchor point defined here
# stays declarable in content (item.schema.json) but is silently not drawn -- extending this
# list is a renderer change, not a content one, because a new slot needs a decision about
# whether it draws under or over the body.
const EQUIP_UNDER_BODY: Array[String] = ["back"]
const EQUIP_OVER_BODY: Array[String] = ["primary", "secondary"]

# key -> Texture2D, or null when the key has no file. Cached either way: a miss is the
# common case and re-probing the filesystem every frame would cost more than the sprites.
static var _cache: Dictionary = {}


# Both lookups matter, and neither is sufficient alone.
#
# A PNG dropped into the project is not a Resource until Godot imports it -- ResourceLoader
# cannot see it, so an artist adding art would get nothing until an editor round-trip, and
# headless CI would never see a new sprite at all. Loading the raw file fixes that.
#
# But an exported build ships imported resources, and the raw .png is not in the .pck unless
# it matches an export filter -- so the raw path fails there and ResourceLoader is the one
# that works. Trying imported first, then raw, covers dev, CI, and export.
static func resolve(key: String) -> Texture2D:
	if key.is_empty():
		return null
	if _cache.has(key):
		return _cache[key] as Texture2D
	var path: String = "%s/%s.png" % [SPRITE_DIR, key]
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Texture2D:
			texture = res as Texture2D
	if texture == null and FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(path) == OK:
			texture = ImageTexture.create_from_image(img)
	_cache[key] = texture
	return texture


# Clears the texture cache. For gates that probe resolution with and without files present.
static func forget() -> void:
	_cache.clear()


# What the ground under a tile looks like: docs/24's surface layer, resolved to a flat tint.
#
# The map carries two independent arrays over one grid -- what is *in* a tile (the occluder
# classes, docs/28) and what is *under* it (this) -- so the ground is never a tile type and
# never a branch on one. `_draw_district` fills with this and then draws whatever the tile
# itself is on top; a tree stands on grass and rubble lies on tarmac because the two layers
# are asked separately.
#
# Out of bounds resolves to Paved, because SimSurface.surface_at says so -- the edge of the
# map reads as street rather than as a hole, which is the same answer the sim gives a body
# walking off the edge.
static func ground_colour(map: Variant, tx: int, ty: int) -> Color:
	if map == null:
		return Palette.COLOURS["floor"]
	var surface: int = int(SimSurface.surface_at(map, tx, ty))
	if surface < 0 or surface >= Palette.SURFACE_TINTS.size():
		return Palette.COLOURS["floor"]
	return Palette.SURFACE_TINTS[surface]


# What a floor tile looks like once it is known to be inside a building.
#
# `indoors` is a third array over the same grid -- docs/24's surface layer is the second -- so an
# interior is no more a tile type than the ground is. The floor keeps the surface it stands on and
# is pulled towards the board colour by INDOOR_MIX: a shop floored on rubble and a house floored
# on paving stay different floors, while both read as inside from across the street. Out of bounds
# and a null map both answer "outdoors", which is what `SimTileMap.is_indoors` says too.
static func indoor_floor(map: Variant, tx: int, ty: int, col: Color) -> Color:
	if map == null or not SimTileMap.is_indoors(map, tx, ty):
		return col
	return col.lerp(Palette.COLOURS["indoorFloor"], Palette.INDOOR_MIX)


# --- the ground atlas ------------------------------------------------------------------------
#
# One atlas for every floor: GROUND_VARIANTS cells across and one row per ground the renderer
# knows -- rows 0..4 mirror SimSurface.Surface, then the two substitutions the draw loop makes,
# the sidewalk paint and the indoor board mix. The atlas is the *shape* of a ground and the
# palette is still its colour: every cell is authored around its row tint (check_road_look.gd's
# TEXTURE lane pins each cell's mean to it from the decoded pixels) and the blit is modulated by
# `flat / row tint`, so the textured branch averages to exactly the colour the flat branch would
# have drawn. The indoor mix, the sidewalk substitution and the position-hash variation all
# survive as tints over the picture, which is what keeps every palette lane meaning what it says.
# Which cell a tile draws is a hash the drawing node takes through Dressing (SALT_GROUND); this
# file cannot preload dressing.gd, which preloads it.
const GROUND_ATLAS_KEY: String = "ground_atlas"
const GROUND_VARIANTS: int = 4
enum GroundRow { Paved = 0, Dirt = 1, Grass = 2, Undergrowth = 3, Rubble = 4, Sidewalk = 5, Boards = 6 }
const GROUND_ROWS: int = 7
# The edge cells: eight more columns to the right of the variants, one ragged fringe per side
# and outer corner of a tile, authored around the same row tint. In the atlas rather than on a
# sheet of their own because the edge is blitted right after the floor it lies on, and a second
# texture between two floor blits breaks the batch on every boundary tile (measured in the
# edges slice; docs/23). EdgeShape's order is the column order, N first.
enum EdgeShape { N = 0, E = 1, S = 2, W = 3, NE = 4, SE = 5, SW = 6, NW = 7 }
const EDGE_SHAPES: int = 8
# What a tile with no ground reads as in the per-map row cache (a wall, a window, a screen, a
# tree): it takes no edge and gives none, so a floor beside a wall keeps its own colour to the
# wall's foot, where the wall's own picture is the edge.
const ROW_NONE: int = 255
# The trees: one tall feet-anchored picture per tree tile, one tile wide and three tall, hung on
# the trunk tile's south-edge centre and y-sorted with the bodies (docs/30, the Dungeon
# Settlers look, decisions 4 and 9). Named here the way the pawn keys are, because canvas_of is
# what check_appearance.gd's canvas lanes read; mirrored by tools/sprites/build.py's TREE_KEYS.
const TREE_KEYS: Array[String] = ["tree_pine_a", "tree_pine_b", "tree_pine_c"]
const TREE_CANVAS: Vector2i = Vector2i(int(CameraUtil.ART_NATIVE), int(CameraUtil.ART_NATIVE) * 3)


# The canvas a registry key is authored on. Everything is one ART_NATIVE tile except the atlases,
# which are a table of them -- and this is the one table, read by check_appearance.gd's canvas
# lanes and mirrored by tools/sprites/build.py's `canvas_of`, so a second shape is a one-line
# entry here and there rather than a new exception in a gate.
static func canvas_of(key: String) -> Vector2i:
	var n: int = int(CameraUtil.ART_NATIVE)
	if key == GROUND_ATLAS_KEY:
		return Vector2i((GROUND_VARIANTS + EDGE_SHAPES) * n, GROUND_ROWS * n)
	if PAWN_KEYS.has(key):
		return PAWN_CANVAS
	if TREE_KEYS.has(key):
		return TREE_CANVAS
	return Vector2i(n, n)


static func anchor_of(size: Vector2i) -> int:
	if size.x == size.y:
		return Anchor.Centre
	return Anchor.Feet


static func ground_atlas() -> Texture2D:
	return resolve(GROUND_ATLAS_KEY)


# The tint a row was authored around: the surface tint for the five surfaces, the two paints for
# the two substitutions. What `ground_modulate` divides by.
static func ground_row_tint(row: int) -> Color:
	match row:
		GroundRow.Sidewalk:
			return Palette.COLOURS["sidewalk"]
		GroundRow.Boards:
			return Palette.COLOURS["indoorFloor"]
		_:
			if row >= 0 and row < Palette.SURFACE_TINTS.size():
				return Palette.SURFACE_TINTS[row]
			return Palette.COLOURS["floor"]


# Which row a floor tile draws: boards indoors, the sidewalk paint where the road mask says so,
# else the surface under it. Out of bounds reads Paved, as ground_colour does.
static func ground_row_for(map: Variant, tx: int, ty: int, sidewalk: bool) -> int:
	if map != null and SimTileMap.is_indoors(map, tx, ty):
		return GroundRow.Boards
	if sidewalk:
		return GroundRow.Sidewalk
	if map == null:
		return GroundRow.Paved
	var surface: int = int(SimSurface.surface_at(map, tx, ty))
	if surface < 0 or surface >= Palette.SURFACE_TINTS.size():
		return GroundRow.Paved
	return surface


# The atlas region of one cell. Pure: a row out of range clamps and a variant wraps, so a caller
# can never ask for pixels outside the picture.
static func ground_cell(row: int, variant: int) -> Rect2:
	var n: float = CameraUtil.ART_NATIVE
	var r: int = clampi(row, 0, GROUND_ROWS - 1)
	var v: int = posmod(variant, GROUND_VARIANTS)
	return Rect2(float(v) * n, float(r) * n, n, n)


# --- the ground edges ------------------------------------------------------------------------
#
# docs/30's edges clause: between two grounds the darker draws the edge, once, onto the lighter
# tile. The rule is pure over a tile's row and its eight neighbours' rows, read off main.gd's
# per-map row cache, and answers which edge cells the *lighter* tile blits over its own floor:
# for each darker 4-neighbour, that neighbour's row in the shape of the side it lies on; for
# each darker diagonal whose two shared 4-neighbours are the centre's own ground, that row in
# the shape of the outer corner. So every boundary is drawn exactly once, by the lighter side,
# and a corner only where no side already carries it. Darker by Rec. 709 luma of the row tint,
# so the order follows the palette rather than a second table.

# Rec. 709 luma of a row's tint, the one ordering the edge rule reads.
static func row_luma(row: int) -> float:
	var c: Color = ground_row_tint(row)
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


# Whether `other` draws its edge onto a tile of `centre`: a different ground, and darker; on
# equal luma the lower row index wins, so the answer is total and never both ways.
static func _edge_wins(other: int, centre: int) -> bool:
	if other == centre or other == ROW_NONE or centre == ROW_NONE:
		return false
	var lo: float = row_luma(other)
	var lc: float = row_luma(centre)
	if absf(lo - lc) < 0.000001:
		return other < centre
	return lo < lc


# The edge cells a tile of row `centre` draws, given its eight neighbours' rows in the fixed
# order N E S W NE SE SW NW (ROW_NONE for a neighbour with no ground, or off the map). Each
# answer is (row, EdgeShape). Sides first, then the corners that no side already covers.
static func edge_shapes(centre: int, neighbours: PackedInt32Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if neighbours.size() != 8 or centre == ROW_NONE:
		return out
	for side in 4:
		if _edge_wins(neighbours[side], centre):
			out.append(Vector2i(neighbours[side], side))
	# A corner needs both of its sides to be the centre's own ground: with a side already
	# drawing the neighbour's fringe, the corner would draw the same boundary twice.
	var sides_of: Array = [
		[EdgeShape.N, EdgeShape.E],
		[EdgeShape.S, EdgeShape.E],
		[EdgeShape.S, EdgeShape.W],
		[EdgeShape.N, EdgeShape.W],
	]
	for i in 4:
		var corner: int = EdgeShape.NE + i
		var a: int = neighbours[int(sides_of[i][0])]
		var b: int = neighbours[int(sides_of[i][1])]
		if a != centre or b != centre:
			continue
		if _edge_wins(neighbours[corner], centre):
			out.append(Vector2i(neighbours[corner], corner))
	return out


# The atlas region of one edge cell: the shape's column past the variants, on the row. Pure and
# clamped like ground_cell, so no caller can ask for pixels outside the picture.
static func edge_cell(row: int, shape: int) -> Rect2:
	var n: float = CameraUtil.ART_NATIVE
	var r: int = clampi(row, 0, GROUND_ROWS - 1)
	var sh: int = clampi(shape, 0, EDGE_SHAPES - 1)
	return Rect2(float(GROUND_VARIANTS + sh) * n, float(r) * n, n, n)


# `flat / base` per channel: a cell whose pixels average `base` draws averaging `flat`. Identity
# when the flat colour is the row's own tint.
static func ground_modulate(flat: Color, base: Color) -> Color:
	return Color(_ratio(flat.r, base.r), _ratio(flat.g, base.g), _ratio(flat.b, base.b), flat.a)


static func _ratio(a: float, b: float) -> float:
	if b <= 0.0001:
		return 1.0
	return clampf(a / b, 0.0, 4.0)


# The doorways on a map, as {tile index: true}.
#
# Read off the generator's own manifest (`map.buildings[i].doors`, absolute tiles) rather than off
# the tile array, because a door *is* a Floor tile in a wall run and nothing in the tiles tells it
# from the street. Pure and uncached on purpose: the cache belongs to whoever is drawing, keyed on
# the map it came from, because a static cache is shared between the two worlds a gate boots.
static func door_tiles(map: Variant) -> Dictionary:
	var out: Dictionary = {}
	if map == null:
		return out
	for record in map.buildings as Array:
		if not (record is Dictionary):
			continue
		var doors: Variant = (record as Dictionary).get("doors", [])
		if not (doors is Array):
			continue
		for door in doors as Array:
			if not (door is Dictionary):
				continue
			var dx: int = int((door as Dictionary).get("x", -1))
			var dy: int = int((door as Dictionary).get("y", -1))
			if dx < 0 or dy < 0 or dx >= int(map.w) or dy >= int(map.h):
				continue
			out[dy * int(map.w) + dx] = true
	return out


# A whole content entry, or {} when nothing carries that id.
#
# `of_content` below answers with the `appearance` sub-block, which is the right answer for
# everything that draws as a body or a footprint. The map dressing (presentation/dressing.gd) is
# not one of those: its content entry *is* the look -- keys per wreck segment, per debris
# family -- with no pawn for an `appearance` block to hang off. So it asks for the entry, through
# the one content lookup this file already owns, rather than growing a second one beside it.
static func entry_of(world: Variant, kind: String, id: String) -> Dictionary:
	var entry: Variant = _content_entry(world, kind, id)
	return entry as Dictionary if entry is Dictionary else {}


# The appearance block for a content id, or {} when the type declares none.
# Content `extends` is deliberately not merged here: nothing else in the codebase resolves
# inheritance at runtime (content_validator.gd only checks it exists and does not cycle), so
# a type inherits nothing and declares its own look, same as its locomotion or body.
static func of_content(world: Variant, kind: String, id: String) -> Dictionary:
	var entry: Variant = _content_entry(world, kind, id)
	if not (entry is Dictionary):
		return {}
	var block: Variant = (entry as Dictionary).get("appearance")
	return block as Dictionary if block is Dictionary else {}


# The draw instruction for one entity, given the role flags _draw_entities already computed.
# Returns {texture: Texture2D|null, tint: Color, radius: float}.
static func for_entity(world: Variant, it: Dictionary) -> Dictionary:
	var is_player: bool = bool(it.get("player", false))
	var is_unique: bool = bool(it.get("unique", false))
	var is_bait: bool = bool(it.get("bait", false))
	var is_raider: bool = bool(it.get("raider", false))

	# Role colours are the floor: an entity with no content appearance looks exactly as it
	# did before this file existed.
	var role: String = "wanderer"
	if is_player:
		role = "player"
	elif is_unique:
		role = "survivor"
	elif is_raider:
		role = "raider"
	elif is_bait:
		role = "groundItem"
	var tint: Color = Palette.COLOURS[role]
	var sprite_key: String = ""

	# Zombies carry their type id, unique survivors their identity id, raiders their archetype
	# id. All three are content ids, and content is what decides how a thing looks.
	var content_id: String = String(it.get("ztype", ""))
	if content_id.is_empty():
		content_id = String(it.get("cid", ""))
	# The player is the fourth case and the one with no id of its own to hand over. Last, so a
	# player who somehow *does* carry a content id keeps it -- this is a floor, not an override.
	if content_id.is_empty() and is_player:
		content_id = PLAYER_LOOK_ID
	var declared_tint: bool = false
	if not content_id.is_empty():
		var kind: String = "survivor"
		if content_id.begins_with("zombie."):
			kind = "zombie"
		elif content_id.begins_with("raider."):
			kind = "raider"
		elif content_id.begins_with("player."):
			kind = "player"
		var block: Dictionary = of_content(world, kind, content_id)
		if block.has("tint"):
			tint = Color(String(block["tint"]))
			declared_tint = true
		if block.has("sprite"):
			sprite_key = String(block["sprite"])

	var texture: Texture2D = resolve(sprite_key)
	# A raider is drawn at a survivor's radius, deliberately. At Peripheral detail main.gd draws
	# one anonymous disc of exactly this size and nothing else -- no sprite, no gear, no facing --
	# so a shape moving in the dark has to be as ambiguous as the contract says it is. Give
	# raiders the wanderer's smaller radius and the glimpse would quietly tell the player "that
	# one is not one of yours", which is the certainty docs/01 clause 4 refuses them.
	var radius: float = 14.0 if is_player else (12.0 if (is_unique or is_raider) else 10.0)
	return {"texture": texture, "tint": modulate_for(texture != null, declared_tint, tint), "radius": radius}


# How many screen pixels one art pixel covers at this zoom. The sprites are authored against
# an ART_NATIVE px tile (32, CameraUtil); every other zoom step is a power-of-two multiple of
# it, so the factor is exact and nearest-neighbour stays clean. The resolver above is
# deliberately zoom-innocent -- `for_entity` answers *what* a body looks like, this answers
# *how big*, and keeping them apart is what lets a gate probe either without a camera.
# A zero zoom answers zero: a degenerate camera draws nothing rather than dividing wrong.
static func blit_scale(zoom: float) -> float:
	return zoom / CameraUtil.ART_NATIVE


# Whether a body is moving, read off its velocity component -- the peripheral-glimpse test.
#
# A missing component is *motionless, not unknown*: SimRecruits' corpse-making removes
# `velocity` outright, so `null` here is exactly the dead. The old inline test in
# _draw_entities read that backwards -- it culled only entities that HAD a velocity of zero,
# so a corpse (no component at all) was glimpsed forever as a body standing in the dark.
# The keys are `dx`/`dy` and never `x`/`y` (CLAUDE.md's velocity trap); check_topdown.gd
# feeds this `{"x": 1.0}` and requires false, which is that trap made mechanical.
static func moving(vel: Variant) -> bool:
	if not (vel is Dictionary):
		return false
	var d: Dictionary = vel as Dictionary
	return float(d.get("dx", 0.0)) != 0.0 or float(d.get("dy", 0.0)) != 0.0


# The screen rect a body's picture is drawn into, given its ground point, its blit size and
# which way it faces. Pure, so check_topdown.gd's flip lane can hold it to exact numbers at
# every rung of the ladder without a draw pass.
#
# A feet-anchored picture (anchor_of: anything not square) stands with its bottom row on the
# contact-shadow line, sy + FOOT_DROP_PX; a centred one hangs symmetrically around the point,
# which is the rect every tile-square picture has always been drawn into. Rounded so a 1:1 pixel
# sprite never lands on a half-pixel as the camera follows the player.
#
# `flip` is body_flip's answer: -1.0 mirrors the picture by handing the renderer a NEGATIVE
# WIDTH, never a transform. Probed in 4.7.1 before this was written: draw_texture_rect with a
# negative-width rect draws the texture mirrored at position .. position + |width|, so the
# flipped rect keeps the same left edge as the unflipped one and the body stays on its point.
# Nobody rotates, the player included (docs/30, the Dungeon Settlers look) -- the draw loop holds
# zero transforms and the flip lane counts them.
static func body_rect(sx: float, sy: float, size: Vector2, flip: float) -> Rect2:
	var left: float = roundf(sx - size.x / 2.0)
	var top: float = roundf(sy - size.y / 2.0)
	if anchor_of(Vector2i(size)) == Anchor.Feet:
		top = roundf(sy + FOOT_DROP_PX - size.y)
	return Rect2(left, top, size.x * flip, size.y)


# Which way a face-on picture is shown for a heading: mirrored (-1.0) when the body looks west
# of straight up or down, as painted (+1.0) otherwise -- north, south and east all draw the one
# picture. A flip is a two-state readout of a continuous heading, which is why the indicator
# line draws for every body: the picture can never say more than "east or west", and the line
# carries the exact facing. Every body flips, the player included; the peripheral-anonymity
# clause is unharmed because a glimpsed body never reaches the blit -- it draws as the anonymous
# disc and the loop moves on before facing is read.
static func body_flip(facing: float) -> float:
	if cos(facing) < 0.0:
		return -1.0
	return 1.0


# The props that stand in a district, as component -> content id.
#
# A prop is an entity that is neither a body nor a carried item: a container, a bed, a campfire,
# the well. The sim spawns all four (SimContainers.make_container, SimNeeds.make_bed /
# make_campfire / make_water_source) and knows nothing about how they look; this is the whole of
# the mapping, and content/props/*.json is the whole of the look. Adding a fifth prop is an entry
# here plus an entry there -- and check_topdown.gd's PROPS lane boots a real district and fails if
# anything standing in it resolves nothing, so a fifth prop that skips this table is caught rather
# than silently invisible, which is the state all four of these were in until this slice.
#
# `flag` is the one boolean whose value changes the picture; a prop without one leaves it empty.
# Two content ids rather than one entry with two tints, so the resolver stays a lookup.
const PROP_KINDS: Array[Dictionary] = [
	{"component": "searchable", "id": "prop.container", "flag": "searched", "flag_id": "prop.container.searched"},
	{"component": "campfire", "id": "prop.campfire", "flag": "lit", "flag_id": "prop.campfire.lit"},
	{"component": "bed", "id": "prop.bed", "flag": "", "flag_id": ""},
	{"component": "water_source", "id": "prop.well", "flag": "", "flag_id": ""},
	{"component": "latrine", "id": "prop.latrine", "flag": "", "flag_id": ""},
]

# The ground-footprint primitives a prop may ask for. Geometry, not identity -- `box` is a crate
# or a cupboard or anything else square. main.gd's _draw_prop is the one place that draws them and
# check_topdown.gd asserts every name here appears there, so a shape content can name but nothing
# can draw fails the build instead of drawing nothing.
const PROP_SHAPES: Array[String] = ["box", "slab", "disc", "ring"]
const PROP_SHAPE_DEFAULT: String = "box"
const PROP_SIZE: float = 0.6


# What one entity looks like standing on the ground, or {} when it is not a prop at all.
# Returns {id, texture, tint, shape, size} -- the same {texture, tint} pair for_entity returns,
# plus the two keys a footprint needs. Fallbacks are the supported path here as everywhere: an
# unknown id, or content that declares only a tint, still yields something drawable.
static func prop_look(world: Variant, entity: int) -> Dictionary:
	if world == null or world.components == null:
		return {}
	for kind in PROP_KINDS:
		var comp: Variant = world.components.get_component(entity, String(kind["component"]))
		if not (comp is Dictionary):
			continue
		var id: String = String(kind["id"])
		var flag: String = String(kind["flag"])
		if not flag.is_empty() and bool((comp as Dictionary).get(flag, false)):
			id = String(kind["flag_id"])
		return prop_of(world, id)
	return {}


# The look for one prop content id, resolved the same way an entity's is: content decides, the
# role colour is the floor, art passes through white unless content asked for a tint.
static func prop_of(world: Variant, id: String) -> Dictionary:
	var block: Dictionary = of_content(world, "prop", id)
	var tint: Color = Palette.COLOURS["prop"]
	var declared_tint: bool = false
	if block.has("tint"):
		tint = Color(String(block["tint"]))
		declared_tint = true
	var texture: Texture2D = resolve(String(block.get("sprite", "")))
	var shape: String = String(block.get("shape", PROP_SHAPE_DEFAULT))
	if not PROP_SHAPES.has(shape):
		shape = PROP_SHAPE_DEFAULT
	var size: float = clampf(float(block.get("size", PROP_SIZE)), 0.1, 1.0)
	return {
		"id": id,
		"texture": texture,
		"tint": modulate_for(texture != null, declared_tint, tint),
		"shape": shape,
		"size": size,
	}


# Textures for whatever this entity has equipped in a slot the renderer draws, ordered
# under-body first then over-body, each tagged with which side of the body draw call it goes
# on. A slot with nothing equipped, an item with no equipSprite, or an entity with no
# equipment component at all (zombies) all fall out silently -- equipment is optional the
# same way a sprite is. An under-body item may also carry a front piece (straps crossing the
# torso) -- that piece is always an over-body layer, independent of its slot's own default,
# because "in front of the body" is a property of the strap, not of the slot it hangs from.
static func equipment_layers_for(world: Variant, actor: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world == null or world.components == null:
		return out
	var eq: Variant = world.components.get_component(actor, "equipment")
	if not (eq is Dictionary):
		return out
	var slots: Dictionary = (eq as Dictionary).get("slots", {}) as Dictionary
	for group in [{"names": EQUIP_UNDER_BODY, "over": false}, {"names": EQUIP_OVER_BODY, "over": true}]:
		for slot in group["names"] as Array[String]:
			var block: Variant = _equip_block_for(world, slots.get(slot))
			if not (block is Dictionary):
				continue
			var texture: Texture2D = _resolve_equip_key(block as Dictionary, "equipSprite")
			if texture != null:
				out.append({"texture": texture, "over": bool(group["over"])})
			var front: Texture2D = _resolve_equip_key(block as Dictionary, "equipSpriteFront")
			if front != null:
				out.append({"texture": front, "over": true})
	return out


# The appearance block for whatever item base occupies a slot, or null through every exit: no
# item, no itemBase component, no matching content entry, no declared appearance at all.
static func _equip_block_for(world: Variant, item: Variant) -> Variant:
	if item == null:
		return null
	var item_base: Variant = world.components.get_component(int(item), "itemBase")
	if not (item_base is Dictionary):
		return null
	var base_id: String = String((item_base as Dictionary).get("baseId", ""))
	if base_id.is_empty():
		return null
	var entry: Variant = _content_entry(world, "item", base_id)
	if not (entry is Dictionary):
		return null
	var block: Variant = (entry as Dictionary).get("appearance")
	return block if block is Dictionary else null


static func _resolve_equip_key(block: Dictionary, key: String) -> Texture2D:
	if not block.has(key):
		return null
	return resolve(String(block[key]))


# The rule for what colour multiplies a drawn entity, named so it can be asserted without
# needing art on disk.
#
# A role colour stands in for missing art; it must not filter art that exists. Drawn as a
# modulate it multiplies every pixel, so a sprite whose content declares no tint would arrive
# stained with e.g. the tan survivor colour instead of looking like what the artist drew.
# Art passes through white; only a tint the content actually asked for modulates it.
static func modulate_for(has_texture: bool, declared_tint: bool, colour: Color) -> Color:
	if has_texture and not declared_tint:
		return Color.WHITE
	return colour


# Content is keyed by file path, not by id, so a lookup scans. Mirrors the private
# _get_content_entry in sim/modules/{shambler,light,roster}.gd -- which is triplicated there
# already; unifying those is sim-side work and out of scope for a presentation file.
static func _content_entry(world: Variant, kind: String, id: String) -> Variant:
	if world == null or world.content == null:
		return null
	var c: Variant = world.content
	if c is Object and (c as Object).has_method("get"):
		return (c as Object).call("get", kind, id)
	if not (c is Dictionary):
		return null
	for v in (c as Dictionary).values():
		if v is Array:
			for entry in v as Array:
				if entry is Dictionary and String((entry as Dictionary).get("id", "")) == id:
					return entry
		elif v is Dictionary and String((v as Dictionary).get("id", "")) == id:
			return v
	return null
