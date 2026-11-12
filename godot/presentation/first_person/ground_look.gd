extends Node
# The ground's look (docs/46, "The ground"): one continuous surface in the valley's materials, instead
# of a board of flat tiles. `district_view.gd` asks this file for the ground's mesh and hands it the
# built MeshInstance3D to dress; everything about how the ground is drawn lives here, in
# `ground.gdshader` and in the three textures `tools/look/build_ground.py` builds.
#
# The picture is the sim's. A tile's material is a pure function of the map: the sim's surface
# (`SimSurface`), whether a carved street covers the tile (`map.streets`), whether it is indoors, and
# whether it is deep water. Nothing here writes to the map or the world, draws a random number, makes
# a physics body or gives light. The ground stays flat at y = 0 with deep water at `WATER_Y`, and the
# mesh stays non-indexed with face normals, which is what `godot:check:fp_geometry` FLAT holds.
#
# Three things reach the shader:
#   the tile map   one texel a tile: material, flags, road paint. Nearest, never filtered.
#   the far map    one texel a tile: the tile's mean colour, filtered with mipmaps. Past a few tens of
#                  metres a tile is a pixel or less, and the ground is read from here, so distance blurs
#                  instead of shimmering.
#   the textures   nine seamless 4 m tiles at 64 texels a metre (nearest, with mipmaps), a metre of
#                  worn road line in four states, and a noise tile that frays the edge between two
#                  materials and lays damp patches and a slow tint over a long street.
#
# The node this script makes sits under the ground mesh and follows the sim's season
# (`SimWeather.season_of`): it finds the scene's world by walking up the tree, and looks again when
# the sim's day changes. A district built with no world above it (a gate's fixture) stays in spring.
#
# `godot:check:fp_look` GROUND holds this to the booted scene; `--plant=ground` paints one tile as
# what the sim does not say and must end red.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimSurface = preload("res://sim/map/surface.gd")
const SimWeather = preload("res://sim/modules/weather.gd")
const SimClock = preload("res://sim/time/clock.gd")

# =====================================================================================================
# PRESENTATION TUNING: every colour, distance and density the ground chooses. Colours are sRGB under
# neutral white light, from docs/46's colour script. The textures' own palettes are in
# tools/look/build_ground.py (TARGET and each surface's ramp).
# =====================================================================================================

## Deep water's surface, below the floor. The sim's ford is a floor tile and stays at 0.
const WATER_Y: float = -0.08

## The season's grass (docs/46). The grass tile is painted in spring's colour; another season
## multiplies it by its colour over spring's, in linear light.
const GRASS_COLOURS: Dictionary = {
	"spring": Color("6f8448"),
	"summer": Color("57733b"),
	"autumn": Color("7a7a45"),
	"winter": Color("7b7559"),
}
const DEFAULT_SEASON: String = "spring"
## How much of the season's tint each material takes, in `Layer` order: grass all of it, undergrowth
## some (cedar litter and evergreen leaves hold their colour), nothing else any.
const SEASON_WEIGHT: PackedFloat32Array = [0.0, 0.0, 0.0, 1.0, 0.35, 0.0, 0.0, 0.0, 0.0]

## Worn road paint (docs/46: `#C9C7B8`), and the same gone grey.
const PAINT_COLOUR: Color = Color("c9c7b8")
const PAINT_WORN_COLOUR: Color = Color("b4b2a4")
## How much of the asphalt under a line the paint covers where it is still there.
const PAINT_STRENGTH: float = 0.88
## A street this many tiles wide or wider gets an edge line down each side.
const EDGE_LINE_MIN_WIDTH: int = 4
## A street this wide or wider, and odd, gets a dashed centre line.
const CENTRE_LINE_MIN_WIDTH: int = 5
## The centre line's dash: this many metres painted, then this many bare.
const DASH_ON_M: int = 3
const DASH_OFF_M: int = 3
## One line tile in this many is worn away altogether.
const LINE_GONE_ONE_IN: int = 9

## How far, in metres, the boundary between two materials wanders from the tile's edge. Under half a
## tile, so a tile's material never reaches past its neighbour.
const EDGE_WANDER_M: float = 0.38
## The size, in metres, of the noise tile that pushes the boundary: smaller frays faster.
const EDGE_PERIOD_M: float = 13.0

## Damp patches: the noise tile stretched over this many metres, dark where it passes the threshold.
## A wet street is `#4A4D50` with patches of `#3A3D40` (docs/46).
const PATCH_PERIOD_M: float = 37.0
const PATCH_THRESHOLD: float = 0.60
## How much of the patch field is the middle-sized noise that breaks a patch's shore up.
const PATCH_BREAKUP: float = 0.45
## What a damp patch multiplies each material by, in linear light, in `Layer` order.
const PATCH_TINT: PackedFloat32Array = [0.70, 0.91, 0.86, 0.95, 0.95, 0.92, 1.0, 1.0, 1.0]
## A damp patch is also smoother: its roughness is the material's times this.
const PATCH_ROUGHNESS: float = 0.55
## The slow tint that keeps a long street from being one flat tone: the noise tile over this many
## metres, lightening and darkening by this share.
const MACRO_PERIOD_M: float = 211.0
const MACRO_STRENGTH: float = 0.07

## Roughness per material, in `Layer` order: wet asphalt and water take a sheen, the rest are matt.
const ROUGHNESS: PackedFloat32Array = [0.62, 0.90, 0.97, 0.97, 0.97, 0.95, 0.22, 0.16, 0.85]

## The ground hands over from its pixel tiles to the filtered far map between these two sizes of a
## screen pixel on the ground, in metres.
const FAR_START_M: float = 0.15
const FAR_END_M: float = 0.60

## How fast water's ripples drift, in metres a second.
const WATER_DRIFT_M: float = 0.05
## The upright bank under the lip of deep water: the tile behind it, darkened by this.
const BANK_SHADE: float = 0.55

# =====================================================================================================

const SHADER_PATH: String = "res://presentation/first_person/ground.gdshader"
const SURFACES_PATH: String = "res://assets/first_person/ground/ground_surfaces.png"
const PAINT_PATH: String = "res://assets/first_person/ground/ground_paint.png"
const NOISE_PATH: String = "res://assets/first_person/ground/ground_noise.png"

## World surfaces hold 64 texels a metre (docs/46). A surface tile is 256 texels, so it spans 4 m.
const TEXELS_PER_METRE: int = 64
const SURFACE_TEXELS: int = 256
const SURFACE_PERIOD_M: float = float(SURFACE_TEXELS) / float(TEXELS_PER_METRE)
const SURFACE_GRID: int = 3
const PAINT_TEXELS: int = 64
const PAINT_VARIANTS: int = 4

## The materials, in the order of the texture's tiles (`LAYERS` in tools/look/build_ground.py).
enum Layer { ASPHALT, CONCRETE, DIRT, GRASS, UNDERGROWTH, RUBBLE, FORD, WATER, FLOOR }
const LAYER_COUNT: int = 9
const LAYER_NAMES: Array[String] = ["asphalt", "concrete", "dirt", "grass", "undergrowth", "rubble", "ford", "water", "floor"]

## Tile-map flags. Firm: paving, which meets other paving along a straight line. Sealed: a room or a
## wall's footing, which keeps its square against everything.
const FLAG_FIRM: int = 1
const FLAG_SEALED: int = 2

## Road paint codes in the tile map's blue: 0 none, else 1 + variant, + PAINT_EAST_WEST for a line that
## runs east-west.
const PAINT_EAST_WEST: int = 4

## The ground mesh merges runs of tiles into strips this many metres long.
const STRIP_M: int = 32

# The textures are the same for every district and never written after they are built, so one copy
# serves every view a process builds (a gate builds dozens).
static var _textures: Dictionary = {}

var map: Variant = null
var salt: int = 0
var material: ShaderMaterial = null
## The tile map as the shader has it: R material, G flags, B paint.
var tile_image: Image = null
var tile_texture: ImageTexture = null
var far_texture: ImageTexture = null
var season: String = DEFAULT_SEASON
var _day: int = -1


## The ground's mesh: flat at y = 0, deep water at WATER_Y, an upright bank under each lip of deep
## water. Non-indexed, each vertex carrying its triangle's face normal. Every row of tiles is cut at
## the same columns, so no triangle's corner lands on another's edge.
static func mesh_of(map_ref: Variant) -> ArrayMesh:
	var w: int = int(map_ref.w)
	var h: int = int(map_ref.h)
	var cut: PackedByteArray = PackedByteArray()
	cut.resize(w + 1)
	for x in range(0, w + 1, STRIP_M):
		cut[x] = 1
	cut[w] = 1
	var wet: bool = false
	for ty in h:
		for tx in w:
			if int(map_ref.tiles[ty * w + tx]) == SimTileMap.Tile.Water:
				cut[tx] = 1
				cut[tx + 1] = 1
				wet = true
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	for ty in h:
		var x0: int = 0
		while x0 < w:
			var x1: int = x0 + 1
			while cut[x1] == 0:
				x1 += 1
			var deep: bool = int(map_ref.tiles[ty * w + x0]) == SimTileMap.Tile.Water
			var y: float = WATER_Y if deep else 0.0
			_quad(verts, normals,
				Vector3(float(x0), y, float(ty)), Vector3(float(x1), y, float(ty)),
				Vector3(float(x1), y, float(ty + 1)), Vector3(float(x0), y, float(ty + 1)), Vector3.UP)
			x0 = x1
	if wet:
		for ty in h:
			for tx in w:
				if int(map_ref.tiles[ty * w + tx]) != SimTileMap.Tile.Water:
					continue
				for side in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
					var nx: int = tx + side.x
					var ny: int = ty + side.y
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					if int(map_ref.tiles[ny * w + nx]) == SimTileMap.Tile.Water:
						continue
					# The shared edge, and a face on it that looks back over the water.
					var a: Vector3 = Vector3(float(tx) + (1.0 if side.x > 0 else 0.0), 0.0, float(ty) + (1.0 if side.y > 0 else 0.0))
					var b: Vector3 = a + (Vector3(0.0, 0.0, 1.0) if side.x != 0 else Vector3(1.0, 0.0, 0.0))
					var drop: Vector3 = Vector3(0.0, WATER_Y, 0.0)
					_quad(verts, normals, a, b, b + drop, a + drop, Vector3(float(-side.x), 0.0, float(-side.y)))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# Two triangles wound the way `district_view.gd` winds its own: clockwise seen from `outward`, so the
# face normal `(c - a) x (b - a)` is the outward one and back-face culling keeps the face.
static func _quad(verts: PackedVector3Array, normals: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	var order: Array = [a, b, c, a, c, d]
	if (c - a).cross(b - a).dot(outward) < 0.0:
		order = [a, c, b, a, d, c]
	for v in order:
		verts.append(v as Vector3)
		normals.append(outward)


## Which tiles a carved street covers: a byte a tile, bit 0 for a street running north-south (the
## sim's axis "x"), bit 1 for one running east-west. Both bits is a junction.
static func street_mask(map_ref: Variant) -> PackedByteArray:
	var w: int = int(map_ref.w)
	var h: int = int(map_ref.h)
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(w * h)
	for span_v in map_ref.streets as Array:
		var span: Dictionary = span_v as Dictionary
		var north_south: bool = String(span.get("axis", "x")) == "x"
		var at: int = int(span.get("at", 0))
		var width: int = int(span.get("width", 0))
		for along in range(int(span.get("from", 0)), int(span.get("to", -1)) + 1):
			for across in range(at, at + width):
				var tx: int = across if north_south else along
				var ty: int = along if north_south else across
				if tx < 0 or ty < 0 or tx >= w or ty >= h:
					continue
				mask[ty * w + tx] = mask[ty * w + tx] | (1 if north_south else 2)
	return mask


## The material of one tile, from the sim's map alone. `streets` is `street_mask(map)`.
##   deep water                    WATER
##   the sim's Water surface       FORD (a floor tile you wade)
##   Paved, indoors                FLOOR (a kit building lays its own floor over it)
##   Paved, on a carved street     ASPHALT
##   Paved, anywhere else          CONCRETE
##   Dirt, Grass, Undergrowth, Rubble: themselves, indoors or out, because the sim's speed and noise
##   on them are theirs wherever they lie.
static func layer_of(map_ref: Variant, streets: PackedByteArray, tx: int, ty: int) -> int:
	var idx: int = ty * int(map_ref.w) + tx
	if int(map_ref.tiles[idx]) == SimTileMap.Tile.Water:
		return Layer.WATER
	match int(map_ref.surfaces[idx]):
		SimSurface.Surface.Water:
			return Layer.FORD
		SimSurface.Surface.Dirt:
			return Layer.DIRT
		SimSurface.Surface.Grass:
			return Layer.GRASS
		SimSurface.Surface.Undergrowth:
			return Layer.UNDERGROWTH
		SimSurface.Surface.Rubble:
			return Layer.RUBBLE
	if map_ref.indoors[idx] == 1:
		return Layer.FLOOR
	if streets[idx] != 0:
		return Layer.ASPHALT
	return Layer.CONCRETE


static func _flags_of(map_ref: Variant, layer: int, tx: int, ty: int) -> int:
	var idx: int = ty * int(map_ref.w) + tx
	var flags: int = 0
	if layer == Layer.ASPHALT or layer == Layer.CONCRETE or layer == Layer.FLOOR:
		flags |= FLAG_FIRM
	var tile: int = int(map_ref.tiles[idx])
	if map_ref.indoors[idx] == 1 or tile == SimTileMap.Tile.Wall or tile == SimTileMap.Tile.Window or tile == SimTileMap.Tile.Door:
		flags |= FLAG_SEALED
	return flags


# The road line on one tile, as a tile-map code. A line is paint on asphalt and nothing else: no tile
# off the street, none where the paving is gone, none on a junction.
static func _paint_of(map_ref: Variant, streets: PackedByteArray, lines: PackedByteArray, salt_val: int, tx: int, ty: int) -> int:
	var idx: int = ty * int(map_ref.w) + tx
	var kind: int = lines[idx]
	if kind == 0 or streets[idx] == 3:
		return 0
	var pick: int = tile_hash(salt_val, tx, ty)
	if pick % LINE_GONE_ONE_IN == 0:
		return 0
	var variant: int = (pick >> 8) % PAINT_VARIANTS
	return 1 + variant + (PAINT_EAST_WEST if kind == 2 else 0)


# Where the lines lie: a byte a tile, 1 for a line running north-south, 2 for east-west. An edge line
# runs down the outermost tile each side of a wide enough street; a dashed centre line down the middle
# tile of an odd width.
static func _line_mask(map_ref: Variant) -> PackedByteArray:
	var w: int = int(map_ref.w)
	var h: int = int(map_ref.h)
	var lines: PackedByteArray = PackedByteArray()
	lines.resize(w * h)
	for span_v in map_ref.streets as Array:
		var span: Dictionary = span_v as Dictionary
		var north_south: bool = String(span.get("axis", "x")) == "x"
		var at: int = int(span.get("at", 0))
		var width: int = int(span.get("width", 0))
		var rows: Array[int] = []
		if width >= EDGE_LINE_MIN_WIDTH:
			rows.append(at)
			rows.append(at + width - 1)
		var centre: int = at + width / 2 if width >= CENTRE_LINE_MIN_WIDTH and width % 2 == 1 else -1
		for along in range(int(span.get("from", 0)), int(span.get("to", -1)) + 1):
			for across in rows:
				_mark(lines, w, h, across if north_south else along, along if north_south else across, 1 if north_south else 2)
			if centre >= 0 and posmod(along, DASH_ON_M + DASH_OFF_M) < DASH_ON_M:
				_mark(lines, w, h, centre if north_south else along, along if north_south else centre, 1 if north_south else 2)
	return lines


static func _mark(bytes: PackedByteArray, w: int, h: int, tx: int, ty: int, value: int) -> void:
	if tx >= 0 and ty >= 0 and tx < w and ty < h:
		bytes[ty * w + tx] = value


## A stable per-tile number from the district's seed and the tile: `district_view.gd`'s own hash, so
## the ground varies the way the walls do. Not a sim stream.
static func tile_hash(salt_val: int, tx: int, ty: int) -> int:
	var hsh: int = (salt_val * 73856093) ^ (tx * 19349663) ^ (ty * 83492791)
	hsh = hsh & 0x7fffffff
	hsh = hsh ^ (hsh >> 13)
	return hsh & 0x7fffffff


## The tile map of a district: one RGB texel a tile, as the shader reads it.
static func tile_image_of(map_ref: Variant, salt_val: int) -> Image:
	var w: int = int(map_ref.w)
	var h: int = int(map_ref.h)
	var streets: PackedByteArray = street_mask(map_ref)
	var lines: PackedByteArray = _line_mask(map_ref)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(w * h * 3)
	for ty in h:
		for tx in w:
			var layer: int = layer_of(map_ref, streets, tx, ty)
			var at: int = (ty * w + tx) * 3
			bytes[at] = layer
			bytes[at + 1] = _flags_of(map_ref, layer, tx, ty)
			bytes[at + 2] = _paint_of(map_ref, streets, lines, salt_val, tx, ty) if layer == Layer.ASPHALT else 0
	return Image.create_from_data(w, h, false, Image.FORMAT_RGB8, bytes)


## The season's grass over spring's, in linear light: what the shader multiplies grass by.
static func season_tint_of(season_name: String) -> Vector3:
	var spring: Color = (GRASS_COLOURS[DEFAULT_SEASON] as Color).srgb_to_linear()
	var now: Color = (GRASS_COLOURS.get(season_name, GRASS_COLOURS[DEFAULT_SEASON]) as Color).srgb_to_linear()
	return Vector3(now.r / spring.r, now.g / spring.g, now.b / spring.b)


## Dresses the ground mesh `district_view.gd` built: the shader, its maps and textures, and this node
## under the mesh to keep the season. Returns the node, or null when the map is missing.
static func dress(ground: MeshInstance3D, map_ref: Variant, salt_val: int) -> Node:
	if ground == null or map_ref == null:
		return null
	var look: Node = new()
	look.name = "GroundLook"
	ground.add_child(look)
	look.call("_setup", ground, map_ref, salt_val)
	return look


func _setup(ground: MeshInstance3D, map_ref: Variant, salt_val: int) -> void:
	map = map_ref
	salt = salt_val
	var textures: Dictionary = _load_textures()
	tile_image = tile_image_of(map, salt)
	tile_texture = ImageTexture.create_from_image(tile_image)
	material = ShaderMaterial.new()
	material.shader = load(SHADER_PATH) as Shader
	material.set_shader_parameter("tile_map", tile_texture)
	material.set_shader_parameter("surfaces", textures["surfaces"])
	material.set_shader_parameter("paint", textures["paint"])
	material.set_shader_parameter("noise", textures["noise"])
	material.set_shader_parameter("map_size", Vector2(float(int(map.w)), float(int(map.h))))
	material.set_shader_parameter("texels_per_metre", float(TEXELS_PER_METRE))
	material.set_shader_parameter("surface_period_m", SURFACE_PERIOD_M)
	# The noise sits somewhere else on every district seed.
	material.set_shader_parameter("noise_offset", Vector2(float(tile_hash(salt, 3, 7) % 256) / 256.0, float(tile_hash(salt, 11, 5) % 256) / 256.0))
	material.set_shader_parameter("edge_wander_m", EDGE_WANDER_M)
	material.set_shader_parameter("edge_period_m", EDGE_PERIOD_M)
	material.set_shader_parameter("patch_period_m", PATCH_PERIOD_M)
	material.set_shader_parameter("patch_threshold", PATCH_THRESHOLD)
	material.set_shader_parameter("patch_breakup", PATCH_BREAKUP)
	material.set_shader_parameter("patch_roughness", PATCH_ROUGHNESS)
	material.set_shader_parameter("patch_tint", PATCH_TINT)
	material.set_shader_parameter("macro_period_m", MACRO_PERIOD_M)
	material.set_shader_parameter("macro_strength", MACRO_STRENGTH)
	material.set_shader_parameter("roughness_of", ROUGHNESS)
	material.set_shader_parameter("season_weight", SEASON_WEIGHT)
	material.set_shader_parameter("far_start_m", FAR_START_M)
	material.set_shader_parameter("far_end_m", FAR_END_M)
	material.set_shader_parameter("paint_colour", PAINT_COLOUR)
	material.set_shader_parameter("paint_worn_colour", PAINT_WORN_COLOUR)
	material.set_shader_parameter("paint_strength", PAINT_STRENGTH)
	material.set_shader_parameter("water_drift_m", WATER_DRIFT_M)
	material.set_shader_parameter("bank_shade", BANK_SHADE)
	ground.material_override = material
	# The ground is flat: it takes the sun's shadow and throws none.
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_season(DEFAULT_SEASON)
	follow_season()


func _process(_delta: float) -> void:
	follow_season()


## Reads the sim's season when the sim's day has changed. With no world above this node, nothing moves.
func follow_season() -> void:
	var world: Variant = _world()
	if world == null:
		return
	var day: int = SimClock.day_number(int(world.tick))
	if day == _day:
		return
	_day = day
	set_season(SimWeather.season_of(world))


## Sets the season the grass is drawn in: the near tiles through the tint, the far map by rebuilding it.
func set_season(season_name: String) -> void:
	if far_texture != null and season_name == season:
		return
	season = season_name
	if material == null:
		return
	material.set_shader_parameter("season_tint", season_tint_of(season))
	var far: Image = _far_image()
	if far_texture == null or far_texture.get_size() != Vector2(far.get_size()):
		far_texture = ImageTexture.create_from_image(far)
		material.set_shader_parameter("far_map", far_texture)
	else:
		far_texture.update(far)


# The world of the scene this ground is drawn in: the first node above it that holds one.
func _world() -> Variant:
	var node: Node = get_parent()
	while node != null:
		if "world" in node:
			var world: Variant = node.get("world")
			if world != null:
				return world
		node = node.get_parent()
	return null


# One texel a tile: the tile's mean colour in this season, and in alpha what a damp patch does to it.
# A painted tile leans toward the paint by the share of the tile its line covers.
func _far_image() -> Image:
	var textures: Dictionary = _load_textures()
	var means: Array = textures["means"] as Array
	var cover: Array = textures["paint_cover"] as Array
	var tint: Vector3 = season_tint_of(season)
	var rows: Array[PackedByteArray] = []
	for layer in LAYER_COUNT:
		var lin: Color = (means[layer] as Color).srgb_to_linear()
		var k: float = SEASON_WEIGHT[layer]
		lin = Color(lin.r * lerpf(1.0, tint.x, k), lin.g * lerpf(1.0, tint.y, k), lin.b * lerpf(1.0, tint.z, k))
		rows.append(_texel(lin.linear_to_srgb(), PATCH_TINT[layer]))
	var painted: Array[PackedByteArray] = []
	for variant in PAINT_VARIANTS:
		var share: float = float(cover[variant]) * PAINT_STRENGTH
		painted.append(_texel((means[Layer.ASPHALT] as Color).lerp(PAINT_COLOUR, share), PATCH_TINT[Layer.ASPHALT]))
	var src: PackedByteArray = tile_image.get_data()
	var n: int = tile_image.get_width() * tile_image.get_height()
	var out: PackedByteArray = PackedByteArray()
	out.resize(n * 4)
	for i in n:
		var code: int = src[i * 3 + 2]
		var texel: PackedByteArray = painted[(code - 1) % PAINT_EAST_WEST] if code > 0 else rows[src[i * 3]]
		out[i * 4] = texel[0]
		out[i * 4 + 1] = texel[1]
		out[i * 4 + 2] = texel[2]
		out[i * 4 + 3] = texel[3]
	var image: Image = Image.create_from_data(tile_image.get_width(), tile_image.get_height(), false, Image.FORMAT_RGBA8, out)
	image.generate_mipmaps()
	return image


static func _texel(colour: Color, alpha: float) -> PackedByteArray:
	return PackedByteArray([
		clampi(roundi(colour.r * 255.0), 0, 255), clampi(roundi(colour.g * 255.0), 0, 255),
		clampi(roundi(colour.b * 255.0), 0, 255), clampi(roundi(alpha * 255.0), 0, 255)])


## The built textures, loaded once: {surfaces: Texture2DArray, paint: Texture2DArray, noise:
## ImageTexture, means: [Color per layer], paint_cover: [float per variant], built: bool}. `built` is
## false when a file is missing, and the ground is then flat colour from docs/46 so it never draws
## as nothing.
static func _load_textures() -> Dictionary:
	if not _textures.is_empty():
		return _textures
	var out: Dictionary = {"built": true}
	var sheet: Image = _image_at(SURFACES_PATH)
	var layers: Array[Image] = []
	var means: Array = []
	if sheet != null and sheet.get_width() == SURFACE_GRID * SURFACE_TEXELS and sheet.get_height() == SURFACE_GRID * SURFACE_TEXELS:
		for i in LAYER_COUNT:
			var tile: Image = sheet.get_region(Rect2i((i % SURFACE_GRID) * SURFACE_TEXELS, (i / SURFACE_GRID) * SURFACE_TEXELS, SURFACE_TEXELS, SURFACE_TEXELS))
			tile.generate_mipmaps()
			layers.append(tile)
			means.append(_smallest_mip(tile))
	else:
		out["built"] = false
		for flat in ["4a4d50", "8c8b84", "6b5a45", "6f8448", "535735", "77726a", "5a6b68", "3b4d52", "6c6055"]:
			var one: Image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
			one.fill(Color(String(flat)))
			one.generate_mipmaps()
			layers.append(one)
			means.append(Color(String(flat)))
	var surfaces: Texture2DArray = Texture2DArray.new()
	surfaces.create_from_images(layers)
	out["surfaces"] = surfaces
	out["means"] = means
	out["surface_images"] = layers

	var strip: Image = _image_at(PAINT_PATH)
	var lines: Array[Image] = []
	var cover: Array = []
	if strip != null and strip.get_width() == PAINT_VARIANTS * PAINT_TEXELS and strip.get_height() == PAINT_TEXELS:
		for v in PAINT_VARIANTS:
			var line: Image = strip.get_region(Rect2i(v * PAINT_TEXELS, 0, PAINT_TEXELS, PAINT_TEXELS))
			line.generate_mipmaps()
			lines.append(line)
			cover.append(_smallest_mip(line).r)
	else:
		out["built"] = false
		for v in PAINT_VARIANTS:
			var none: Image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
			none.fill(Color(0.0, 0.0, 0.0, 1.0))
			none.generate_mipmaps()
			lines.append(none)
			cover.append(0.0)
	var paint: Texture2DArray = Texture2DArray.new()
	paint.create_from_images(lines)
	out["paint"] = paint
	out["paint_cover"] = cover

	var field: Image = _image_at(NOISE_PATH)
	if field == null:
		out["built"] = false
		field = Image.create(4, 4, false, Image.FORMAT_RGBA8)
		field.fill(Color(0.5, 0.5, 0.5, 1.0))
	field.generate_mipmaps()
	out["noise"] = ImageTexture.create_from_image(field)
	_textures = out
	return out


## Whether the three built textures were found. False means the flat fallback is on screen.
static func textures_built() -> bool:
	return bool(_load_textures().get("built", false))


## The surface tiles as images, in `Layer` order, with their mipmaps: what the gate measures.
static func surface_images() -> Array:
	return _load_textures().get("surface_images", []) as Array


# A built PNG as an RGBA image. An exported build carries the imported texture and not the file; a
# gate's fresh checkout has the file and no import (`ui/kit.gd` reads its kit the same two ways).
static func _image_at(path: String) -> Image:
	var image: Image = null
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Texture2D:
			image = (res as Texture2D).get_image()
	if image == null and FileAccess.file_exists(path):
		var raw: Image = Image.new()
		if raw.load(path) == OK:
			image = raw
	if image == null or image.is_empty():
		return null
	if image.is_compressed():
		image.decompress()
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	return image


# The colour of an image's last mipmap: its mean, as the far end of its own mip chain shows it.
static func _smallest_mip(image: Image) -> Color:
	var data: PackedByteArray = image.get_data()
	var at: int = data.size() - 4
	return Color(float(data[at]) / 255.0, float(data[at + 1]) / 255.0, float(data[at + 2]) / 255.0, float(data[at + 3]) / 255.0)
