extends Node3D
# The district's green (docs/46, "What is a plain box today"): the trees, the thickets and the low
# ground cover. Presentation only: it reads the map and never writes it, adds no body, no collision
# and no light, and every variation is a hash of the district's seed and the tile, so one seed is one
# picture.
#
# What the sim holds is drawn exactly, and everything else is dressing above or beside it:
#
#   - A Tree tile blocks movement, sight and shots over its whole tile to 2550 mm (docs/40: "the view
#     must not draw a thin trunk with gaps the sim treats as opaque"). So the tile is drawn as its
#     band, a full-tile column of bark from the floor to 2550 mm: the foot of a great trunk. Above the
#     band the trunk narrows to an octagon and carries the crown, which overhangs its neighbours only
#     above 2550 mm.
#   - An outdoor Screen tile is opaque to 2550 mm and a body walks through it. It is drawn as its
#     band too, a full-tile column, but of leaves and twigs with no bark in it, so it reads as brush.
#     Its faces are opaque: a gap between leaves is deep shade, never a hole. Sprigs rise above the
#     band. An indoor Screen (a shop's shelving) is not green and stays the district's band box.
#   - Ground cover stands under COVER_MAX_HEIGHT_M on outdoor grass and undergrowth floor only.
#     Roots at a trunk's foot stay under the same height. Nothing else stands below 2550 mm outside
#     a column's own tile, except a fringe at most FRINGE_PROUD_M proud of a thicket's face.
#
# `DistrictView` leaves the band boxes of these tiles out of its solid mesh and this node draws the
# same boxes (`*Columns`), so the band is drawn once. `godot:check:fp_look`'s GREEN lane measures the
# columns against `SimSpace.PROFILE` and the dressing against the rules above; `tile_mesh` in the
# district view is unchanged and `godot:check:fp_geometry` still judges it.
#
# The textures come from `tools/look/build_green.py` (64 texels a metre, drawn nearest with
# mipmaps); `green.manifest.json` names them and the card cells. Meshes are merged per texture.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimSurface = preload("res://sim/map/surface.gd")
const SimSpace = preload("res://sim/space/space.gd")
const SimWeather = preload("res://sim/modules/weather.gd")

# ==== PRESENTATION TUNING ===========================================================================
# Every colour, distance and density of the green. Colours are docs/46's sRGB under neutral white
# light; the textures carry the hues (tools/look/build_green.py holds their ramps) and the values
# here only tint them. Retune here; the logic below reads nothing else.

# Cedars (sugi). Heights in metres; a tree's own figure is a hash of the seed and its tile.
const CEDAR_HEIGHT_MIN_M: float = 8.0
const CEDAR_HEIGHT_MAX_M: float = 14.0
# Where the crown starts, as a share of the tree's height (bare trunk below it).
const CEDAR_CROWN_BASE_MIN: float = 0.26
const CEDAR_CROWN_BASE_MAX: float = 0.44
# The lowest tier's radius for an 11 m tree; it scales with the square root of the height.
const CEDAR_CROWN_RADIUS_MIN_M: float = 1.7
const CEDAR_CROWN_RADIUS_MAX_M: float = 2.4
const CEDAR_TIER_SPACING_M: float = 1.35
const CEDAR_TIER_BOUGHS: int = 8
# How far a bough's tip hangs below its tier and how far the gap between boughs rises, per metre of radius.
const CEDAR_BOUGH_DROOP: float = 0.16
const CEDAR_BOUGH_NOTCH: float = 0.20
const CEDAR_LEAN_MAX_DEGREES: float = 2.5
# Tints over the cedar foliage texture: the lit top of a tier, the shade between boughs, the underside.
const CEDAR_TINT_MIN: float = 0.90
const CEDAR_TINT_MAX: float = 1.08
const CEDAR_TIER_TOP_SHADE: float = 1.12
const CEDAR_TIER_RIM_SHADE: float = 0.94
const CEDAR_TIER_NOTCH_SHADE: float = 0.70
const CEDAR_UNDERSIDE_SHADE: float = 0.55
# The trunk above the band: an octagon inside the tile at 2550 mm, narrowing to this radius at the top.
const TRUNK_TOP_RADIUS_M: float = 0.10
const TRUNK_SHOULDER_M: float = 1.3
const TRUNK_SHOULDER_RADIUS_M: float = 0.45
const BROADLEAF_TRUNK_TOP_RADIUS_M: float = 0.26
const BROADLEAF_LIMB_RADIUS_M: float = 0.15
# Roots at the foot: how far they run from the tile and how high they leave the trunk.
const ROOT_REACH_MIN_M: float = 0.16
const ROOT_REACH_MAX_M: float = 0.34
const ROOT_HEIGHT_M: float = 0.22
const ROOT_HALF_WIDTH_M: float = 0.17
const ROOT_TOE_SHADE: float = 0.86

# Broadleaf trees. One tree in BROADLEAF_ONE_IN is broadleaf by its hash, and so is any tree within
# BROADLEAF_NEAR_BUILDING_TILES of a wall, a window or a door (docs/42: plum and persimmon by houses).
const BROADLEAF_ONE_IN: int = 9
const BROADLEAF_NEAR_BUILDING_TILES: int = 4
const BROADLEAF_HEIGHT_MIN_M: float = 5.6
const BROADLEAF_HEIGHT_MAX_M: float = 7.8
const BROADLEAF_CROWN_RADIUS_MIN_M: float = 2.3
const BROADLEAF_CROWN_RADIUS_MAX_M: float = 3.1
const BROADLEAF_LOBES_MIN: int = 5
const BROADLEAF_LOBES_MAX: int = 7
const BROADLEAF_TINT_MIN: float = 0.94
const BROADLEAF_TINT_MAX: float = 1.04
const BROADLEAF_UNDERSIDE_SHADE: float = 0.70
const BROADLEAF_TOP_SHADE: float = 1.06
# The crown texture per season (docs/46: plum blossom in spring, persimmon and maple in autumn).
const BROADLEAF_SEASON_TEXTURES: Dictionary = {
	"spring": "broadleaf_spring.png",
	"summer": "broadleaf_summer.png",
	"autumn": "broadleaf_autumn.png",
	"winter": "broadleaf_winter.png",
}

# Thickets. Sprigs rise above the band from each tile; the fringe stands proud of an open face.
const THICKET_SPRIGS_MIN: int = 2
const THICKET_SPRIGS_MAX: int = 4
const THICKET_TOP_SHADE: float = 1.0
const FRINGE_PROUD_M: float = 0.09375
const FRINGE_PER_FACE: int = 2

# Ground cover. A tuft is a pair of crossed cards. The share of tiles that carry tufts follows a slow
# patchwork over the district, and rises beside a trunk or a thicket.
const COVER_MAX_HEIGHT_M: float = 0.30
const COVER_TUFTS_PER_TILE: float = 0.9
const COVER_PATCH_TILES: int = 7
const COVER_PATCH_LOW: float = 0.0
const COVER_PATCH_HIGH: float = 2.4
const COVER_BESIDE_GREEN_BONUS: float = 1.6
const COVER_FERN_ONE_IN: int = 14
const COVER_FLOWER_ONE_IN: int = 22
const COVER_CHUNK_TILES: int = 32
# Beyond this the tufts are a few pixels of shimmer; the chunk stops drawing.
const COVER_DRAW_DISTANCE_M: float = 70.0
# The grass tint per season over the spring-coloured cards: docs/46's grass colour for the season
# divided by spring's #6F8448.
const COVER_SEASON_TINTS: Dictionary = {
	"spring": Color(1.0, 1.0, 1.0),
	"summer": Color(0.784, 0.871, 0.819),
	"autumn": Color(1.099, 0.924, 0.958),
	"winter": Color(1.108, 0.886, 1.236),
}
const ALPHA_SCISSOR: float = 0.5
# ==== end of PRESENTATION TUNING ====================================================================

const ASSET_DIR: String = "res://assets/first_person/green"
const MANIFEST_PATH: String = "res://assets/first_person/green/green.manifest.json"
const BAND_KEY_TREE: String = "tree"
const BAND_KEY_SCREEN: String = "screen"
const SEASON_POLL_SECONDS: float = 1.0

var map: Variant = null
# One record per Tree tile {tile, kind, height, crown_base}, and the outdoor Screen tiles, in map order.
var trees: Array = []
var thicket_tiles: Array = []
# One record per tuft {tile, card, pos}: the gate checks each against the tile's surface.
var cover: Array = []
var season: String = "spring"
# False when a texture or the manifest was missing and the green fell back to flat colour.
var textures_loaded: bool = false
# The gate's planted error: the band columns are drawn 0.3 m thinner than their tile.
var plant_thin_columns: bool = false

var _salt: int = 0
var _cells: Dictionary = {}
var _texels: float = 64.0
var _broadleaf_crown_material: StandardMaterial3D = null
var _cover_material: StandardMaterial3D = null
var _poll: float = 0.0

static var _texture_cache: Dictionary = {}


## True when this node, not the district's solid mesh, draws the tile's band: a tree, or a screen
## that stands outdoors.
static func draws(map_ref: Variant, tx: int, ty: int) -> bool:
	var key: String = SimSpace.profile_key(map_ref, tx, ty)
	if key == BAND_KEY_TREE:
		return true
	return key == BAND_KEY_SCREEN and not SimTileMap.is_indoors(map_ref, tx, ty)


## Builds the green for `map_ref`. `salt` is the district's seed, the same one the wall modules use.
func build(map_ref: Variant, salt: int = 0) -> void:
	map = map_ref
	_salt = salt
	for child in get_children():
		remove_child(child)
		child.queue_free()
	trees.clear()
	thicket_tiles.clear()
	cover.clear()
	_broadleaf_crown_material = null
	_cover_material = null
	if map == null:
		return
	_load_manifest()
	var cedar_columns: Soup = Soup.new(64, 192)
	var cedar_wood: Soup = Soup.new(64, 64)
	var cedar_crowns: Soup = Soup.new(64, 64)
	var leaf_columns: Soup = Soup.new(64, 192)
	var leaf_wood: Soup = Soup.new(64, 64)
	var leaf_crowns: Soup = Soup.new(64, 64)
	var thicket_columns: Soup = Soup.new(128, 192)
	var thicket_tops: Soup = Soup.new(64, 64)
	var thicket_cards: Soup = Soup.new(256, 128)
	var w: int = int(map.w)
	var h: int = int(map.h)
	for ty in h:
		for tx in w:
			var key: String = SimSpace.profile_key(map, tx, ty)
			if key == BAND_KEY_TREE:
				if _is_broadleaf(tx, ty):
					_add_broadleaf(tx, ty, leaf_columns, leaf_wood, leaf_crowns)
				else:
					_add_cedar(tx, ty, cedar_columns, cedar_wood, cedar_crowns)
			elif key == BAND_KEY_SCREEN and not SimTileMap.is_indoors(map, tx, ty):
				_add_thicket(tx, ty, thicket_columns, thicket_tops, thicket_cards)
	var all_loaded: bool = not _cells.is_empty()
	all_loaded = _commit("CedarColumns", cedar_columns, "cedar_base.png", false, true) and all_loaded
	all_loaded = _commit("CedarTrunks", cedar_wood, "cedar_bark.png", false, true) and all_loaded
	all_loaded = _commit("CedarCrowns", cedar_crowns, "cedar_foliage.png", false, true) and all_loaded
	all_loaded = _commit("BroadleafColumns", leaf_columns, "broadleaf_base.png", false, true) and all_loaded
	all_loaded = _commit("BroadleafTrunks", leaf_wood, "broadleaf_bark.png", false, true) and all_loaded
	all_loaded = _commit("BroadleafCrowns", leaf_crowns, String(BROADLEAF_SEASON_TEXTURES[season]), false, true) and all_loaded
	all_loaded = _commit("ThicketColumns", thicket_columns, "thicket_face.png", false, true) and all_loaded
	all_loaded = _commit("ThicketTops", thicket_tops, "thicket_top.png", false, true) and all_loaded
	all_loaded = _commit("ThicketCards", thicket_cards, "green_cards.png", true, true) and all_loaded
	all_loaded = _build_cover() and all_loaded
	textures_loaded = all_loaded
	var crowns: MeshInstance3D = get_node_or_null("BroadleafCrowns") as MeshInstance3D
	if crowns != null:
		_broadleaf_crown_material = crowns.material_override as StandardMaterial3D
	set_season(season)


## The season's dress: the broadleaf crowns' texture and the ground cover's tint. The scene's world
## is read once a second (`_process`); a view built without a world keeps spring, the sim's start.
func set_season(name_of_season: String) -> void:
	if not BROADLEAF_SEASON_TEXTURES.has(name_of_season):
		return
	season = name_of_season
	if _broadleaf_crown_material != null:
		var texture: Texture2D = _texture(String(BROADLEAF_SEASON_TEXTURES[season]))
		if texture != null:
			_broadleaf_crown_material.albedo_texture = texture
	if _cover_material != null:
		_cover_material.albedo_color = COVER_SEASON_TINTS[season] as Color


func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = SEASON_POLL_SECONDS
	var world: Variant = _world_above()
	if world == null:
		return
	var now: String = SimWeather.season_of(world)
	if now != season:
		set_season(now)


# The sim world of the scene this view hangs in: the first ancestor that holds one. Read only.
func _world_above() -> Variant:
	var node: Node = get_parent()
	while node != null:
		if "world" in node and node.get("world") != null:
			return node.get("world")
		node = node.get_parent()
	return null


## A digest of every vertex this node drew: two builds of one map and one seed give the same string.
func signature() -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for child in get_children():
		var instance: MeshInstance3D = child as MeshInstance3D
		if instance == null or instance.mesh == null:
			continue
		ctx.update(String(instance.name).to_utf8_buffer())
		for s in instance.mesh.get_surface_count():
			var arrays: Array = instance.mesh.surface_get_arrays(s)
			ctx.update((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array())
	return ctx.finish().hex_encode()


# --- hashes ----------------------------------------------------------------------------------------

# A stable 31-bit value from the seed, the tile and a channel. Not a sim stream: placement only.
func _hash(tx: int, ty: int, channel: int) -> int:
	var v: int = (_salt * 73856093) ^ (tx * 19349663) ^ (ty * 83492791) ^ (channel * 2654435761)
	v = v & 0x7fffffff
	v = (v ^ (v >> 15)) * 0x2c1b3c6d
	v = v & 0x7fffffff
	v = (v ^ (v >> 12)) * 0x297a2d39
	v = v & 0x7fffffff
	return v ^ (v >> 15)


func _unit(tx: int, ty: int, channel: int) -> float:
	return float(_hash(tx, ty, channel) % 100000) / 100000.0


func _range(tx: int, ty: int, channel: int, lo: float, hi: float) -> float:
	return lerpf(lo, hi, _unit(tx, ty, channel))


# --- trees -----------------------------------------------------------------------------------------

func _is_broadleaf(tx: int, ty: int) -> bool:
	if _hash(tx, ty, 1) % BROADLEAF_ONE_IN == 0:
		return true
	var reach: int = BROADLEAF_NEAR_BUILDING_TILES
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			if tx + dx < 0 or ty + dy < 0 or tx + dx >= int(map.w) or ty + dy >= int(map.h):
				continue
			var tile: int = SimTileMap.tile_at(map, tx + dx, ty + dy)
			if tile == SimTileMap.Tile.Wall or tile == SimTileMap.Tile.Window or tile == SimTileMap.Tile.Door:
				return true
	return false


func _band_top_m(key: String) -> float:
	var top: int = 0
	for band in SimSpace.bands(key):
		top = maxi(top, int(band[1]))
	return float(top) / 1000.0


# The band of a tree or a screen tile as a column: four faces and a cap, over the tile's full
# footprint from the floor to the band's top. `u_of` maps a face's run in metres onto the texture.
func _add_column(soup: Soup, tx: int, ty: int, top: float, tint: Color, world_u: bool, cap: Soup, cap_tint: Color) -> void:
	# A face's run, left to right as it is seen from outside, so a texture is never mirrored and a
	# thicket's leaves run on from one tile's face into the next.
	var inset: float = 0.3 if plant_thin_columns else 0.0
	var x0: float = float(tx) + inset
	var x1: float = float(tx) + 1.0 - inset
	var z0: float = float(ty) + inset
	var z1: float = float(ty) + 1.0 - inset
	var v_top: float = 1.0 - top * _texels / float(soup.tex_h)
	var faces: Array = [
		[Vector3(x0, 0.0, z1), Vector3(x1, 0.0, z1), Vector3.BACK, x0, x1],
		[Vector3(x1, 0.0, z0), Vector3(x0, 0.0, z0), Vector3.FORWARD, -x1, -x0],
		[Vector3(x1, 0.0, z1), Vector3(x1, 0.0, z0), Vector3.RIGHT, -z1, -z0],
		[Vector3(x0, 0.0, z0), Vector3(x0, 0.0, z1), Vector3.LEFT, z0, z1],
	]
	for face_v in faces:
		var face: Array = face_v as Array
		var a: Vector3 = face[0] as Vector3
		var b: Vector3 = face[1] as Vector3
		var u0: float = 0.0
		var u1: float = (x1 - x0) * _texels / float(soup.tex_w)
		if world_u:
			u0 = float(face[3]) * _texels / float(soup.tex_w)
			u1 = float(face[4]) * _texels / float(soup.tex_w)
		soup.quad(a, b, b + Vector3(0.0, top, 0.0), a + Vector3(0.0, top, 0.0),
			Vector2(u0, 1.0), Vector2(u1, 1.0), Vector2(u1, v_top), Vector2(u0, v_top),
			face[2] as Vector3, tint, tint, tint, tint)
	if cap == soup:
		# A trunk's cap takes plain bark from the top of its own column texture.
		var v_cap: float = (x1 - x0) * _texels / float(soup.tex_h)
		cap.quad(Vector3(x0, top, z0), Vector3(x1, top, z0), Vector3(x1, top, z1), Vector3(x0, top, z1),
			Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, v_cap), Vector2(0.0, v_cap),
			Vector3.UP, cap_tint, cap_tint, cap_tint, cap_tint)
	else:
		cap.quad_planar(Vector3(x0, top, z0), Vector3(x1, top, z0), Vector3(x1, top, z1), Vector3(x0, top, z1),
			Vector3.UP, cap_tint, cap_tint, cap_tint, cap_tint, Vector2.ZERO)


# The trunk above the band. Its first ring is the column's own square top, so the foot runs into
# the bole without a ledge; a shoulder above it the trunk is an octagon, narrowing to `top_radius`.
func _add_trunk(soup: Soup, base: Vector3, band_top: float, top_y: float, top_radius: float, lean: Vector2, shade: float) -> void:
	var rings: Array = []
	var shoulder: float = minf(band_top + TRUNK_SHOULDER_M, lerpf(band_top, top_y, 0.5))
	var levels: Array = [band_top, shoulder, lerpf(shoulder, top_y, 0.45), top_y]
	for li in levels.size():
		var y: float = float(levels[li])
		var t: float = (y - shoulder) / maxf(0.001, top_y - shoulder)
		var radius: float = lerpf(TRUNK_SHOULDER_RADIUS_M, top_radius, clampf(t, 0.0, 1.0))
		var ring: Array = []
		for k in 8:
			var ang: float = TAU * float(k) / 8.0
			var dir: Vector2 = Vector2(cos(ang), sin(ang))
			if li == 0:
				# On the square: the face centres and the corners of the tile.
				dir = dir / maxf(absf(dir.x), absf(dir.y)) * 0.5
			else:
				dir = dir * radius
			ring.append(base + Vector3(dir.x + lean.x * (y - band_top), y, dir.y + lean.y * (y - band_top)))
		rings.append(ring)
	var tint: Color = Color(shade, shade, shade)
	for r in rings.size() - 1:
		var lower: Array = rings[r] as Array
		var upper: Array = rings[r + 1] as Array
		for k in 8:
			var k2: int = (k + 1) % 8
			var a: Vector3 = lower[k] as Vector3
			var b: Vector3 = lower[k2] as Vector3
			var c: Vector3 = upper[k2] as Vector3
			var d: Vector3 = upper[k] as Vector3
			var outward: Vector3 = (a + b) * 0.5 - Vector3(base.x + lean.x * (a.y - band_top), a.y, base.z + lean.y * (a.y - band_top))
			soup.quad_planar(a, b, c, d, outward, tint, tint, tint, tint, Vector2(float(k) * 0.37, 0.0))


# A limb: a tapered four-sided bough from `from` to `to`.
func _add_limb(soup: Soup, from: Vector3, to: Vector3, r_from: float, r_to: float, shade: float) -> void:
	var axis: Vector3 = (to - from).normalized()
	var side: Vector3 = axis.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = Vector3.RIGHT
	side = side.normalized()
	var other: Vector3 = axis.cross(side).normalized()
	var tint: Color = Color(shade, shade, shade)
	for k in 4:
		var a0: float = TAU * float(k) / 4.0
		var a1: float = TAU * float(k + 1) / 4.0
		var d0: Vector3 = side * cos(a0) + other * sin(a0)
		var d1: Vector3 = side * cos(a1) + other * sin(a1)
		soup.quad_planar(from + d0 * r_from, from + d1 * r_from, to + d1 * r_to, to + d0 * r_to, d0 + d1, tint, tint, tint, tint, Vector2(float(k) * 0.41, 0.0))


# Roots: low wedges running out from the foot of the column. They stay under COVER_MAX_HEIGHT_M, so
# like the tufts they hide nobody.
func _add_roots(soup: Soup, tx: int, ty: int, shade: float) -> void:
	var sides: Array = [Vector2(0.0, 1.0), Vector2(0.0, -1.0), Vector2(1.0, 0.0), Vector2(-1.0, 0.0)]
	var centre: Vector3 = Vector3(float(tx) + 0.5, 0.0, float(ty) + 0.5)
	var tint: Color = Color(shade, shade, shade)
	var dark: Color = Color(shade * ROOT_TOE_SHADE, shade * ROOT_TOE_SHADE, shade * ROOT_TOE_SHADE)
	for s in sides.size():
		var out: Vector2 = sides[s] as Vector2
		var along: Vector2 = Vector2(-out.y, out.x)
		var count: int = 1 + _hash(tx, ty, 40 + s) % 2
		for r in count:
			var offset: float = _range(tx, ty, 50 + s * 4 + r, -0.30, 0.30)
			var reach: float = _range(tx, ty, 60 + s * 4 + r, ROOT_REACH_MIN_M, ROOT_REACH_MAX_M)
			var skew: float = _range(tx, ty, 70 + s * 4 + r, -0.08, 0.08)
			var foot: Vector2 = out * 0.5 + along * offset
			var top: Vector3 = centre + Vector3(foot.x, minf(ROOT_HEIGHT_M, COVER_MAX_HEIGHT_M - 0.01), foot.y)
			var left: Vector3 = centre + Vector3(foot.x - along.x * ROOT_HALF_WIDTH_M, 0.0, foot.y - along.y * ROOT_HALF_WIDTH_M)
			var right: Vector3 = centre + Vector3(foot.x + along.x * ROOT_HALF_WIDTH_M, 0.0, foot.y + along.y * ROOT_HALF_WIDTH_M)
			var toe: Vector3 = centre + Vector3(foot.x + out.x * reach + along.x * skew, 0.0, foot.y + out.y * reach + along.y * skew)
			var up_out: Vector3 = Vector3(out.x, 1.0, out.y)
			soup.tri_planar(top, left, toe, up_out - Vector3(along.x, 0.0, along.y), tint, tint, dark, Vector2(float(r), 0.0))
			soup.tri_planar(top, toe, right, up_out + Vector3(along.x, 0.0, along.y), tint, dark, tint, Vector2(float(r), 0.5))


func _add_cedar(tx: int, ty: int, columns: Soup, wood: Soup, crowns: Soup) -> void:
	var band_top: float = _band_top_m(BAND_KEY_TREE)
	var height: float = _range(tx, ty, 2, CEDAR_HEIGHT_MIN_M, CEDAR_HEIGHT_MAX_M)
	var crown_base: float = maxf(band_top + 0.45, height * _range(tx, ty, 3, CEDAR_CROWN_BASE_MIN, CEDAR_CROWN_BASE_MAX))
	var radius: float = _range(tx, ty, 4, CEDAR_CROWN_RADIUS_MIN_M, CEDAR_CROWN_RADIUS_MAX_M) * sqrt(height / 11.0)
	var lean_angle: float = deg_to_rad(_range(tx, ty, 5, 0.0, CEDAR_LEAN_MAX_DEGREES))
	var lean_dir: float = _range(tx, ty, 6, 0.0, TAU)
	var lean: Vector2 = Vector2(cos(lean_dir), sin(lean_dir)) * tan(lean_angle)
	var tint: float = _range(tx, ty, 7, CEDAR_TINT_MIN, CEDAR_TINT_MAX)
	var bark: float = _range(tx, ty, 8, 0.92, 1.06)
	var base: Vector3 = Vector3(float(tx) + 0.5, 0.0, float(ty) + 0.5)
	trees.append({"tile": Vector2i(tx, ty), "kind": "cedar", "height": height, "crown_base": crown_base})
	var bark_tint: Color = Color(bark, bark, bark)
	_add_column(columns, tx, ty, band_top, bark_tint, false, columns, Color(bark * 0.55, bark * 0.55, bark * 0.55))
	_add_trunk(wood, base, band_top, height - 0.6, TRUNK_TOP_RADIUS_M, lean, bark)
	_add_roots(wood, tx, ty, bark)
	var tiers: int = clampi(roundi((height - crown_base) / CEDAR_TIER_SPACING_M), 4, 8)
	var span: float = (height - crown_base) / float(tiers)
	for i in tiers:
		var t: float = float(i) / float(tiers)
		var y_rim: float = crown_base + span * float(i)
		var r_rim: float = radius * pow(1.0 - t, 0.8) + 0.22
		var y_top: float = y_rim + span * 1.7
		var r_top: float = r_rim * 0.26
		var last: bool = i == tiers - 1
		if last:
			y_top = height
			r_top = 0.0
		var spin: float = _range(tx, ty, 100 + i, 0.0, TAU)
		var shade: float = tint * lerpf(0.86, 1.06, t)
		_add_tier(crowns, base, band_top, lean, y_rim, r_rim, y_top, r_top, spin, shade, tx, ty, i)


# One tier of a cedar: a cone whose rim is cut into drooping boughs, closed from below so that a
# look up into the crown meets shade, not sky.
func _add_tier(soup: Soup, base: Vector3, band_top: float, lean: Vector2, y_rim: float, r_rim: float, y_top: float, r_top: float, spin: float, shade: float, tx: int, ty: int, tier: int) -> void:
	var boughs: int = CEDAR_TIER_BOUGHS
	var top_ring: Array = []
	var rim: Array = []
	var floor_y: float = band_top + 0.02
	for k in boughs:
		var ang: float = spin + TAU * float(k) / float(boughs)
		var jitter: float = _range(tx, ty, 200 + tier * 16 + k, 0.86, 1.12)
		var tip_r: float = r_rim * jitter
		var tip_y: float = maxf(floor_y, y_rim - CEDAR_BOUGH_DROOP * tip_r)
		var mid: float = ang + TAU * 0.5 / float(boughs)
		var notch_r: float = r_rim * 0.70
		var notch_y: float = maxf(floor_y, y_rim + CEDAR_BOUGH_NOTCH * r_rim)
		top_ring.append(_leaned(base, lean, band_top, cos(ang) * r_top, y_top, sin(ang) * r_top))
		rim.append(_leaned(base, lean, band_top, cos(ang) * tip_r, tip_y, sin(ang) * tip_r))
		rim.append(_leaned(base, lean, band_top, cos(mid) * notch_r, notch_y, sin(mid) * notch_r))
	var lit: Color = Color(shade * CEDAR_TIER_TOP_SHADE, shade * CEDAR_TIER_TOP_SHADE, shade * CEDAR_TIER_TOP_SHADE)
	var tip: Color = Color(shade * CEDAR_TIER_RIM_SHADE, shade * CEDAR_TIER_RIM_SHADE, shade * CEDAR_TIER_RIM_SHADE)
	var notch: Color = Color(shade * CEDAR_TIER_NOTCH_SHADE, shade * CEDAR_TIER_NOTCH_SHADE, shade * CEDAR_TIER_NOTCH_SHADE)
	var under: Color = Color(shade * CEDAR_UNDERSIDE_SHADE, shade * CEDAR_UNDERSIDE_SHADE, shade * CEDAR_UNDERSIDE_SHADE)
	var axis: Vector3 = _leaned(base, lean, band_top, 0.0, (y_rim + y_top) * 0.5, 0.0)
	var hub: Vector3 = _leaned(base, lean, band_top, 0.0, maxf(floor_y, y_rim + CEDAR_BOUGH_NOTCH * r_rim + 0.12), 0.0)
	for k in boughs:
		var k2: int = (k + 1) % boughs
		var t0: Vector3 = top_ring[k] as Vector3
		var t1: Vector3 = top_ring[k2] as Vector3
		var tip0: Vector3 = rim[k * 2] as Vector3
		var gap0: Vector3 = rim[k * 2 + 1] as Vector3
		var tip1: Vector3 = rim[k2 * 2] as Vector3
		var prev_gap: Vector3 = rim[(k * 2 + boughs * 2 - 1) % (boughs * 2)] as Vector3
		var offset: Vector2 = Vector2(float(k) * 0.61 + float(tier) * 0.37, float(tier) * 0.53)
		# The bough: its tip between the two notches beside it, under the top ring.
		soup.tri_planar(t0, prev_gap, tip0, tip0 - axis, lit, notch, tip, offset)
		soup.tri_planar(t0, tip0, gap0, tip0 - axis, lit, tip, notch, offset)
		if r_top > 0.0:
			soup.tri_planar(t0, gap0, t1, gap0 - axis, lit, notch, lit, offset)
		# The underside, down-facing.
		soup.tri_planar(hub, tip0, prev_gap, Vector3.DOWN, under, under, under, offset)
		soup.tri_planar(hub, gap0, tip0, Vector3.DOWN, under, under, under, offset)


func _leaned(base: Vector3, lean: Vector2, band_top: float, x: float, y: float, z: float) -> Vector3:
	return base + Vector3(x + lean.x * (y - band_top), y, z + lean.y * (y - band_top))


func _add_broadleaf(tx: int, ty: int, columns: Soup, wood: Soup, crowns: Soup) -> void:
	var band_top: float = _band_top_m(BAND_KEY_TREE)
	var height: float = _range(tx, ty, 12, BROADLEAF_HEIGHT_MIN_M, BROADLEAF_HEIGHT_MAX_M)
	var radius: float = _range(tx, ty, 13, BROADLEAF_CROWN_RADIUS_MIN_M, BROADLEAF_CROWN_RADIUS_MAX_M)
	var tint: float = _range(tx, ty, 14, BROADLEAF_TINT_MIN, BROADLEAF_TINT_MAX)
	var bark: float = _range(tx, ty, 15, 0.94, 1.06)
	var base: Vector3 = Vector3(float(tx) + 0.5, 0.0, float(ty) + 0.5)
	var crown_base: float = band_top + 0.35
	trees.append({"tile": Vector2i(tx, ty), "kind": "broadleaf", "height": height, "crown_base": crown_base})
	var bark_tint: Color = Color(bark, bark, bark)
	_add_column(columns, tx, ty, band_top, bark_tint, false, columns, Color(bark * 0.55, bark * 0.55, bark * 0.55))
	var fork: Vector3 = base + Vector3(0.0, lerpf(crown_base, height, 0.30), 0.0)
	_add_trunk(wood, base, band_top, fork.y, BROADLEAF_TRUNK_TOP_RADIUS_M, Vector2.ZERO, bark)
	_add_roots(wood, tx, ty, bark)
	# The crown: a cap over the fork and a ring of lobes around it, each on its own limb.
	var floor_y: float = band_top + 0.05
	var cap_y: float = lerpf(crown_base, height, 0.62)
	_add_lobe(crowns, base + Vector3(0.0, cap_y, 0.0), Vector3(radius * 0.72, height - cap_y, radius * 0.72), floor_y, tint, tx, ty, 0)
	var lobes: int = BROADLEAF_LOBES_MIN + _hash(tx, ty, 16) % (BROADLEAF_LOBES_MAX - BROADLEAF_LOBES_MIN + 1)
	var turn: float = _range(tx, ty, 17, 0.0, TAU)
	for i in lobes:
		var ang: float = turn + TAU * float(i) / float(lobes) + _range(tx, ty, 300 + i, -0.25, 0.25)
		var out: float = radius * _range(tx, ty, 310 + i, 0.44, 0.60)
		var lobe_r: float = radius * _range(tx, ty, 320 + i, 0.44, 0.58)
		var lobe_h: float = lobe_r * _range(tx, ty, 340 + i, 0.70, 0.9)
		var lobe_y: float = maxf(floor_y + lobe_h * 0.5 + 0.2, lerpf(crown_base, height, _range(tx, ty, 330 + i, 0.24, 0.52)))
		var centre: Vector3 = base + Vector3(cos(ang) * out, lobe_y, sin(ang) * out)
		_add_lobe(crowns, centre, Vector3(lobe_r, lobe_h, lobe_r), floor_y, tint * _range(tx, ty, 350 + i, 0.95, 1.04), tx, ty, i + 1)
		_add_limb(wood, fork - Vector3(0.0, 0.5, 0.0), centre, BROADLEAF_LIMB_RADIUS_M, BROADLEAF_LIMB_RADIUS_M * 0.45, bark * 0.92)


# A crown lobe: a low-poly ellipsoid, flat-shaded, darker underneath, never below `floor_y`.
func _add_lobe(soup: Soup, centre: Vector3, radii: Vector3, floor_y: float, tint: float, tx: int, ty: int, lobe: int) -> void:
	var segments: int = 7
	var latitudes: Array = [-0.5 * PI, -0.26 * PI, 0.0, 0.25 * PI, 0.5 * PI]
	var spin: float = _range(tx, ty, 400 + lobe, 0.0, TAU)
	var rings: Array = []
	for li in latitudes.size():
		var lat: float = float(latitudes[li])
		var ring: Array = []
		for k in segments:
			var ang: float = spin + TAU * (float(k) + 0.5 * float(li % 2)) / float(segments)
			var bump: float = _range(tx, ty, 500 + lobe * 40 + li * 8 + k, 0.86, 1.1)
			var p: Vector3 = centre + Vector3(cos(lat) * cos(ang) * radii.x * bump, sin(lat) * radii.y * (bump if lat > 0.0 else 0.5), cos(lat) * sin(ang) * radii.z * bump)
			p.y = maxf(floor_y, p.y)
			ring.append(p)
		rings.append(ring)
	for li in rings.size() - 1:
		var lower: Array = rings[li] as Array
		var upper: Array = rings[li + 1] as Array
		var lat_mid: float = (float(latitudes[li]) + float(latitudes[li + 1])) * 0.5
		var shade: float = tint * lerpf(BROADLEAF_UNDERSIDE_SHADE, BROADLEAF_TOP_SHADE, clampf((sin(lat_mid) + 0.75) / 1.5, 0.0, 1.0))
		var colour: Color = Color(shade, shade, shade)
		for k in segments:
			var k2: int = (k + 1) % segments
			var a: Vector3 = lower[k] as Vector3
			var b: Vector3 = lower[k2] as Vector3
			var c: Vector3 = upper[k2] as Vector3
			var d: Vector3 = upper[k] as Vector3
			var offset: Vector2 = Vector2(float(k) * 0.43 + float(lobe) * 0.29, float(li) * 0.31)
			if a.distance_squared_to(b) > 1e-8:
				soup.tri_planar(a, b, d, (a + b + d) / 3.0 - centre, colour, colour, colour, offset)
			if c.distance_squared_to(d) > 1e-8:
				soup.tri_planar(b, c, d, (b + c + d) / 3.0 - centre, colour, colour, colour, offset)


# --- thickets --------------------------------------------------------------------------------------

func _is_thicket(tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return false
	return SimSpace.profile_key(map, tx, ty) == BAND_KEY_SCREEN and not SimTileMap.is_indoors(map, tx, ty)


func _add_thicket(tx: int, ty: int, columns: Soup, tops: Soup, cards: Soup) -> void:
	var band_top: float = _band_top_m(BAND_KEY_SCREEN)
	thicket_tiles.append(Vector2i(tx, ty))
	var top_tint: Color = Color(THICKET_TOP_SHADE, THICKET_TOP_SHADE, THICKET_TOP_SHADE)
	_add_column(columns, tx, ty, band_top, Color.WHITE, true, tops, top_tint)
	if _cells.is_empty():
		return
	# Sprigs above the band: crossed cards standing on the column's top.
	var sprigs: int = THICKET_SPRIGS_MIN + _hash(tx, ty, 20) % (THICKET_SPRIGS_MAX - THICKET_SPRIGS_MIN + 1)
	var names: Array = ["sprig_a", "sprig_b", "sprig_c"]
	for i in sprigs:
		var cell: Array = _cells.get(String(names[_hash(tx, ty, 21 + i) % names.size()]), []) as Array
		if cell.is_empty():
			continue
		var pos: Vector3 = Vector3(float(tx) + _range(tx, ty, 30 + i, 0.14, 0.86), band_top, float(ty) + _range(tx, ty, 40 + i, 0.14, 0.86))
		_add_cross(cards, pos, cell, _range(tx, ty, 50 + i, 0.0, PI), _hash(tx, ty, 60 + i) % 2 == 0, Color.WHITE, false)
	# The fringe: strips of leaves a few centimetres proud of every face that meets open ground.
	var fringes: Array = ["fringe_a", "fringe_b"]
	var sides: Array = [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
	for s in sides.size():
		var side: Vector2i = sides[s] as Vector2i
		if _is_thicket(tx + side.x, ty + side.y):
			continue
		for f in FRINGE_PER_FACE:
			var cell: Array = _cells.get(String(fringes[_hash(tx, ty, 70 + s * 4 + f) % fringes.size()]), []) as Array
			if cell.is_empty():
				continue
			var along: float = _range(tx, ty, 80 + s * 4 + f, 0.04, 0.96)
			var out: Vector3 = Vector3(float(side.x), 0.0, float(side.y))
			var run: Vector3 = Vector3(-out.z, 0.0, out.x)
			var foot: Vector3 = Vector3(float(tx) + 0.5, 0.0, float(ty) + 0.5) + out * 0.5 + run * (along - 0.5)
			_add_fringe(cards, foot, out, band_top, cell, _unit(tx, ty, 90 + s * 4 + f))


# A strip standing out from a face, from the floor to the band's top, in lengths of one cell.
func _add_fringe(soup: Soup, foot: Vector3, out: Vector3, top: float, cell: Array, phase: float) -> void:
	var width: float = minf(FRINGE_PROUD_M, float(cell[2]) / _texels)
	var cell_h: float = float(cell[3]) / _texels
	var y: float = 0.0
	var u0: float = float(cell[0]) / float(soup.tex_w)
	var u1: float = (float(cell[0]) + width * _texels) / float(soup.tex_w)
	while y < top - 0.001:
		var y1: float = minf(top, y + cell_h * (1.0 if y > 0.0 else maxf(0.25, phase)))
		var v_bottom: float = (float(cell[1]) + float(cell[3])) / float(soup.tex_h)
		var v_top: float = v_bottom - (y1 - y) * _texels / float(soup.tex_h)
		soup.card(foot + Vector3(0.0, y, 0.0), foot + out * width + Vector3(0.0, y, 0.0), foot + out * width + Vector3(0.0, y1, 0.0), foot + Vector3(0.0, y1, 0.0),
			Vector2(u0, v_bottom), Vector2(u1, v_bottom), Vector2(u1, v_top), Vector2(u0, v_top), Color.WHITE, Vector3.ZERO)
		y = y1


# Two cards crossed at `pos`, standing up from it; `cell` is [x, y, w, h] in the card sheet's pixels.
func _add_cross(soup: Soup, pos: Vector3, cell: Array, yaw: float, mirror: bool, tint: Color, light_from_above: bool) -> void:
	var half: float = float(cell[2]) / _texels * 0.5
	var height: float = float(cell[3]) / _texels
	var u0: float = float(cell[0]) / float(soup.tex_w)
	var u1: float = (float(cell[0]) + float(cell[2])) / float(soup.tex_w)
	if mirror:
		var swap: float = u0
		u0 = u1
		u1 = swap
	var v0: float = float(cell[1]) / float(soup.tex_h)
	var v1: float = (float(cell[1]) + float(cell[3])) / float(soup.tex_h)
	var normal: Vector3 = Vector3.UP if light_from_above else Vector3.ZERO
	for q in 2:
		var ang: float = yaw + PI * 0.5 * float(q)
		var dir: Vector3 = Vector3(cos(ang), 0.0, sin(ang)) * half
		soup.card(pos - dir, pos + dir, pos + dir + Vector3(0.0, height, 0.0), pos - dir + Vector3(0.0, height, 0.0),
			Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v0), Vector2(u0, v0), tint, normal)


# --- ground cover ----------------------------------------------------------------------------------

## True when ground cover may stand on the tile: open outdoor floor whose surface is grass or
## undergrowth. Never a street, a yard of dirt, rubble, water, a room or a tile that holds anything.
static func cover_allowed(map_ref: Variant, tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= int(map_ref.w) or ty >= int(map_ref.h):
		return false
	if SimTileMap.tile_at(map_ref, tx, ty) != SimTileMap.Tile.Floor:
		return false
	if SimSpace.profile_key(map_ref, tx, ty) != "floor":
		return false
	if SimTileMap.is_indoors(map_ref, tx, ty):
		return false
	var surface: int = SimSurface.surface_at(map_ref, tx, ty)
	return surface == SimSurface.Surface.Grass or surface == SimSurface.Surface.Undergrowth


# The slow patchwork: lattice values a few tiles apart, blended, so tufts gather in drifts.
func _patch(tx: int, ty: int) -> float:
	var cell: int = COVER_PATCH_TILES
	var gx: int = floori(float(tx) / float(cell))
	var gy: int = floori(float(ty) / float(cell))
	var fx: float = float(tx - gx * cell) / float(cell)
	var fy: float = float(ty - gy * cell) / float(cell)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a: float = _unit(gx, gy, 900)
	var b: float = _unit(gx + 1, gy, 900)
	var c: float = _unit(gx, gy + 1, 900)
	var d: float = _unit(gx + 1, gy + 1, 900)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


func _beside_green(tx: int, ty: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx: int = tx + dx
			var ny: int = ty + dy
			if nx < 0 or ny < 0 or nx >= int(map.w) or ny >= int(map.h):
				continue
			if draws(map, nx, ny):
				return true
	return false


func _build_cover() -> bool:
	if _cells.is_empty():
		return false
	var tufts: Array = ["tuft_a", "tuft_b", "tuft_c", "tuft_d"]
	var ferns: Array = ["fern_a", "fern_b"]
	var w: int = int(map.w)
	var h: int = int(map.h)
	var loaded: bool = true
	var chunk: int = COVER_CHUNK_TILES
	for cy in range(0, h, chunk):
		for cx in range(0, w, chunk):
			var soup: Soup = Soup.new(256, 128)
			for ty in range(cy, mini(h, cy + chunk)):
				for tx in range(cx, mini(w, cx + chunk)):
					if not cover_allowed(map, tx, ty):
						continue
					var beside: bool = _beside_green(tx, ty)
					var density: float = COVER_TUFTS_PER_TILE * lerpf(COVER_PATCH_LOW, COVER_PATCH_HIGH, _patch(tx, ty))
					if beside:
						density += COVER_BESIDE_GREEN_BONUS
					var count: int = floori(density + _unit(tx, ty, 901))
					for i in count:
						var card: String = String(tufts[_hash(tx, ty, 910 + i) % tufts.size()])
						if _hash(tx, ty, 920 + i) % (3 if beside else COVER_FERN_ONE_IN) == 0:
							card = String(ferns[_hash(tx, ty, 930 + i) % ferns.size()])
						elif _hash(tx, ty, 940 + i) % COVER_FLOWER_ONE_IN == 0:
							card = "tuft_flower"
						var cell: Array = _cells.get(card, []) as Array
						if cell.is_empty() or float(cell[3]) / _texels > COVER_MAX_HEIGHT_M:
							continue
						var half: float = float(cell[2]) / _texels * 0.5
						# The whole card stays on its own tile, so cover never leans onto a street.
						var pos: Vector3 = Vector3(float(tx) + _range(tx, ty, 950 + i, half, 1.0 - half), 0.0, float(ty) + _range(tx, ty, 960 + i, half, 1.0 - half))
						var shade: float = _range(tx, ty, 970 + i, 0.9, 1.06)
						_add_cross(soup, pos, cell, _range(tx, ty, 980 + i, 0.0, PI), _hash(tx, ty, 990 + i) % 2 == 0, Color(shade, shade, shade), true)
						cover.append({"tile": Vector2i(tx, ty), "card": card, "pos": pos})
			if soup.is_empty():
				continue
			var node: MeshInstance3D = _instance("Cover_%d_%d" % [cx / chunk, cy / chunk], soup, true)
			if _cover_material == null:
				_cover_material = _material("green_cards.png", true)
				loaded = _cover_material.albedo_texture != null
			node.material_override = _cover_material
			# Tufts are too small to be worth a shadow, and far away they are shimmer.
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.visibility_range_end = COVER_DRAW_DISTANCE_M + float(chunk) * 0.75
			node.visibility_range_end_margin = 6.0
			node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	return loaded


# --- meshes, materials, textures -------------------------------------------------------------------

func _load_manifest() -> void:
	_cells = {}
	_texels = 64.0
	if not FileAccess.file_exists(MANIFEST_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not (parsed is Dictionary):
		return
	var manifest: Dictionary = parsed as Dictionary
	_texels = float(manifest.get("texels_per_metre", 64.0))
	var cards: Dictionary = manifest.get("cards", {}) as Dictionary
	_cells = cards.get("cells", {}) as Dictionary


func _commit(node_name: String, soup: Soup, texture_name: String, cards: bool, shadows: bool) -> bool:
	if soup.is_empty():
		return true
	var node: MeshInstance3D = _instance(node_name, soup, cards)
	var material: StandardMaterial3D = _material(texture_name, cards)
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return material.albedo_texture != null


func _instance(node_name: String, soup: Soup, _cards: bool) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = node_name
	node.mesh = soup.mesh()
	add_child(node)
	return node


func _material(texture_name: String, cards: bool) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.metallic_specular = 0.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.texture_repeat = true
	var texture: Texture2D = _texture(texture_name)
	if texture != null:
		material.albedo_texture = texture
	if cards:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = ALPHA_SCISSOR
	material.cull_mode = BaseMaterial3D.CULL_BACK
	return material


# A texture of the kit with its mipmaps built here, because an import sidecar is not tracked and the
# default import builds none (nearest without mipmaps shimmers past about seven metres).
static func _texture(texture_name: String) -> Texture2D:
	if _texture_cache.has(texture_name):
		return _texture_cache[texture_name] as Texture2D
	var path: String = ASSET_DIR.path_join(texture_name)
	var result: Texture2D = null
	if ResourceLoader.exists(path):
		var source: Texture2D = load(path) as Texture2D
		var image: Image = source.get_image() if source != null else null
		if image != null:
			var mipped: Image = image.duplicate() as Image
			if mipped.is_compressed():
				mipped.decompress()
			mipped.generate_mipmaps()
			result = ImageTexture.create_from_image(mipped)
	_texture_cache[texture_name] = result
	return result


# A triangle soup for one texture: positions, flat normals, UVs in the texture's own pixels per metre
# and vertex tints. Front faces follow the engine's winding, as in district_view.gd: for a triangle
# (a, b, c) the face normal is (c - a) x (b - a).
class Soup:
	var tex_w: int = 64
	var tex_h: int = 64
	var texels: float = 64.0
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var colours: PackedColorArray = PackedColorArray()
	# Only the cards are indexed (a card's two faces share their corners); the solid faces stay a
	# plain triangle list, one normal a face.
	var indices: PackedInt32Array = PackedInt32Array()

	func _init(texture_w: int, texture_h: int) -> void:
		tex_w = texture_w
		tex_h = texture_h

	func is_empty() -> bool:
		return vertices.is_empty()

	func _push(p: Vector3, n: Vector3, uv: Vector2, colour: Color) -> void:
		vertices.append(p)
		normals.append(n)
		uvs.append(uv)
		colours.append(colour)

	# One triangle facing `outward`, with the UVs given.
	func tri(a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, outward: Vector3, ca: Color, cb: Color, cc: Color) -> void:
		var face: Vector3 = (c - a).cross(b - a)
		if face.length_squared() < 1e-14:
			return
		if face.dot(outward) < 0.0:
			var swap_p: Vector3 = b
			b = c
			c = swap_p
			var swap_u: Vector2 = ub
			ub = uc
			uc = swap_u
			var swap_c: Color = cb
			cb = cc
			cc = swap_c
			face = -face
		var n: Vector3 = face.normalized()
		_push(a, n, ua, ca)
		_push(b, n, ub, cb)
		_push(c, n, uc, cc)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, outward: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
		tri(a, b, c, ua, ub, uc, outward, ca, cb, cc)
		tri(a, c, d, ua, uc, ud, outward, ca, cc, cd)

	# The UV of a point on a plane with normal `n`: metres along the plane's level direction and up its
	# slope, at this texture's density, so every face holds the same texels a metre whatever its tilt.
	func _planar(p: Vector3, n: Vector3, offset: Vector2) -> Vector2:
		var level: Vector3 = Vector3.UP.cross(n)
		if level.length_squared() < 1e-6:
			level = Vector3.RIGHT
		level = level.normalized()
		var rise: Vector3 = n.cross(level).normalized()
		return Vector2((p.dot(level)) * texels / float(tex_w) + offset.x, -(p.dot(rise)) * texels / float(tex_h) + offset.y)

	func tri_planar(a: Vector3, b: Vector3, c: Vector3, outward: Vector3, ca: Color, cb: Color, cc: Color, offset: Vector2) -> void:
		var face: Vector3 = (c - a).cross(b - a)
		if face.length_squared() < 1e-14:
			return
		var n: Vector3 = face.normalized()
		if n.dot(outward) < 0.0:
			n = -n
		tri(a, b, c, _planar(a, n, offset), _planar(b, n, offset), _planar(c, n, offset), outward, ca, cb, cc)

	func quad_planar(a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, ca: Color, cb: Color, cc: Color, cd: Color, offset: Vector2) -> void:
		tri_planar(a, b, c, outward, ca, cb, cc, offset)
		tri_planar(a, c, d, outward, ca, cc, cd, offset)

	# A card seen from both sides: two faces back to back, each culled from behind. With `normal` zero
	# each face is lit by its own normal; otherwise both take the normal given, which is how a tuft
	# takes the ground's light whichever side is looked at.
	func card(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, colour: Color, normal: Vector3) -> void:
		var face: Vector3 = (c - a).cross(b - a).normalized()
		var front: Vector3 = face if normal == Vector3.ZERO else normal
		var back: Vector3 = -face if normal == Vector3.ZERO else normal
		var first: int = vertices.size()
		for corner in [[a, ua], [b, ub], [c, uc], [d, ud]]:
			_push(corner[0] as Vector3, front, corner[1] as Vector2, colour)
		for i in [0, 1, 2, 0, 2, 3]:
			indices.append(first + i)
		if front != back:
			first = vertices.size()
			for corner in [[a, ua], [b, ub], [c, uc], [d, ud]]:
				_push(corner[0] as Vector3, back, corner[1] as Vector2, colour)
		for i in [0, 2, 1, 0, 3, 2]:
			indices.append(first + i)

	func mesh() -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_COLOR] = colours
		if not indices.is_empty():
			arrays[Mesh.ARRAY_INDEX] = indices
		var out: ArrayMesh = ArrayMesh.new()
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return out
