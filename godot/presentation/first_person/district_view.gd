extends Node3D
# The district as geometry, not a picture. Every tile's floor is a quad, and every height band
# `SimSpace.PROFILE` gives the tile is a box over the full tile footprint: a window is a sill and a
# lintel with an aperture between, a Low tile is drawn, a doorway has a lintel. Nothing here decides
# a height. The bands are the sim's, and this view draws them and nothing else (docs/40, "The one
# authority": "the presentation builds its geometry from SimSpace.PROFILE and from nothing else").
#
# The meshes stay merged by category: one ground mesh, one opaque solid mesh and one see-through
# mesh for the wire fence. The per-tile geometry comes from `tile_boxes`, which is also what
# `tile_mesh` builds for the gate to judge a tile against its bands.
#
# Sim x/y maps to Godot x/z, one tile to one metre (`SimTileMap.TILE_METRES`). There is no second
# map and no second collision pass here.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimSurface = preload("res://sim/map/surface.gd")
const SimSpace = preload("res://sim/space/space.gd")

const WATER_Y: float = -0.08

const WALL_COLOUR: Color = Color(0.42, 0.40, 0.36)
const WINDOW_COLOUR: Color = Color(0.42, 0.52, 0.58)
const SCREEN_COLOUR: Color = Color(0.35, 0.47, 0.38)
const DOOR_COLOUR: Color = Color(0.36, 0.25, 0.16)
const BOARD_COLOUR: Color = Color(0.44, 0.31, 0.19)
const SCRAP_COLOUR: Color = Color(0.46, 0.33, 0.27)
const TIMBER_COLOUR: Color = Color(0.52, 0.38, 0.24)
const STONE_COLOUR: Color = Color(0.50, 0.49, 0.46)
const LOW_COLOUR: Color = Color(0.44, 0.38, 0.28)
const TREE_COLOUR: Color = Color(0.20, 0.36, 0.20)
const WATER_COLOUR: Color = Color(0.16, 0.34, 0.45)
# Alpha is the one thing the wire fence says about itself: it is see-through, as the sim says.
const FENCE_COLOUR: Color = Color(0.62, 0.64, 0.64, 0.30)

const SURFACE_COLOURS: Array[Color] = [
	Color(0.58, 0.57, 0.54),
	Color(0.50, 0.43, 0.33),
	Color(0.38, 0.50, 0.31),
	Color(0.29, 0.40, 0.24),
	Color(0.47, 0.44, 0.39),
	Color(0.22, 0.42, 0.53),
]

var map: Variant = null
var ground: MeshInstance3D = null
var solids: MeshInstance3D = null
var fence: MeshInstance3D = null


func build(map_ref: Variant) -> void:
	map = map_ref
	for child in get_children():
		child.queue_free()
	if map == null:
		return
	ground = _build_mesh("GroundTiles", _ground_surface(), false)
	solids = _build_mesh("SolidTiles", _band_surface(false), false)
	fence = _build_mesh("FenceTiles", _band_surface(true), true)


func _build_mesh(node_name: String, mesh: Mesh, see_through: bool) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	if see_through:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	else:
		# Back-face culling stays on. Every quad is wound to its outward normal, so a hole in the
		# district is a missing mesh and not a face quietly drawn from behind.
		material.cull_mode = BaseMaterial3D.CULL_BACK
	instance.material_override = material
	add_child(instance)
	return instance


func _ground_surface() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w: int = int(map.w)
	var h: int = int(map.h)
	for ty in h:
		for tx in w:
			var idx: int = ty * w + tx
			var tile: int = int(map.tiles[idx])
			var surface: int = int(map.surfaces[idx])
			var colour: Color = WATER_COLOUR if tile == SimTileMap.Tile.Water else _surface_colour(surface)
			# A subtle per-tile even/odd shade, so the metre grid reads on the floor even before
			# the pixel textures land.
			if (tx + ty) % 2 != 0:
				colour = colour * 0.90
			var y: float = WATER_Y if tile == SimTileMap.Tile.Water else 0.0
			_add_quad_up(st,
				Vector3(float(tx) + 0.02, y, float(ty) + 0.02),
				Vector3(float(tx) + 0.98, y, float(ty) + 0.02),
				Vector3(float(tx) + 0.98, y, float(ty) + 0.98),
				Vector3(float(tx) + 0.02, y, float(ty) + 0.98),
				colour)
	st.generate_normals()
	return st.commit()


# The opaque bands (or, with `see_through`, the fence's bands) of every tile, as one mesh. Null when
# there is nothing to draw, so the node exists without a mesh.
func _band_surface(see_through: bool) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var drew: bool = false
	for ty in int(map.h):
		for tx in int(map.w):
			for box in tile_boxes(map, tx, ty):
				if bool(box["transparent"]) != see_through:
					continue
				_add_box_of(st, box)
				drew = true
	if not drew:
		return null
	st.generate_normals()
	return st.commit()


## Every band of one tile as a box: {min, max, colour, transparent}, in Godot metres. This is the
## whole per-tile answer; `_band_surface` and `tile_mesh` both build from it.
static func tile_boxes(map: Variant, tx: int, ty: int) -> Array:
	var out: Array = []
	var key: String = SimSpace.profile_key(map, tx, ty)
	var colour: Color = _colour_of(key)
	var see_through: bool = key == "fence"
	for band in SimSpace.bands(key):
		var lo: float = float(int(band[0])) / 1000.0
		var hi: float = float(int(band[1])) / 1000.0
		out.append({
			"min": Vector3(float(tx), lo, float(ty)),
			"max": Vector3(float(tx) + 1.0, hi, float(ty) + 1.0),
			"colour": colour,
			"transparent": see_through,
		})
	return out


## One tile's built mesh, for a gate to measure against its bands. Null when the tile draws nothing.
static func tile_mesh(map: Variant, tx: int, ty: int) -> ArrayMesh:
	var boxes: Array = tile_boxes(map, tx, ty)
	if boxes.is_empty():
		return null
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for box in boxes:
		_add_box_of(st, box)
	st.generate_normals()
	return st.commit()


static func _colour_of(key: String) -> Color:
	if key.begins_with("board:"):
		return BOARD_COLOUR
	match key:
		"wall":
			return WALL_COLOUR
		"window":
			return WINDOW_COLOUR
		"screen":
			return SCREEN_COLOUR
		"low":
			return LOW_COLOUR
		"tree":
			return TREE_COLOUR
		"door.open", "door.closed":
			return DOOR_COLOUR
		"scrap":
			return SCRAP_COLOUR
		"timber":
			return TIMBER_COLOUR
		"stone":
			return STONE_COLOUR
		"fence":
			return FENCE_COLOUR
	return WALL_COLOUR


static func _surface_colour(surface: int) -> Color:
	if surface < 0 or surface >= SURFACE_COLOURS.size():
		return SURFACE_COLOURS[SimSurface.Surface.Dirt]
	return SURFACE_COLOURS[surface]


static func _add_box_of(st: SurfaceTool, box: Dictionary) -> void:
	var lo: Vector3 = box["min"] as Vector3
	var hi: Vector3 = box["max"] as Vector3
	_add_box(st, (lo + hi) * 0.5, hi - lo, box["colour"] as Color)


static func _add_quad_up(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, colour: Color) -> void:
	_add_quad_facing(st, a, b, c, d, Vector3.UP, colour)


# Adds the quad as two triangles wound so the normal `generate_normals` will produce along
# `outward`. Godot's convention is the clockwise one: for triangle (a, b, c) the generated normal
# is `(c - a) x (b - a)`, not `(b - a) x (c - a)`. The corner order is flipped only when that
# generated normal disagrees with the outward one. That is what lets one helper build a floor (up),
# a wall (sideways) and a box without a second convention or double-sided geometry.
static func _add_quad_facing(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, colour: Color) -> void:
	var generated: Vector3 = (c - a).cross(b - a)
	if generated.dot(outward) < 0.0:
		_add_tri(st, a, c, b, colour)
		_add_tri(st, a, d, c, colour)
	else:
		_add_tri(st, a, b, c, colour)
		_add_tri(st, a, c, d, colour)


static func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, colour: Color) -> void:
	st.set_color(colour)
	st.add_vertex(a)
	st.set_color(colour)
	st.add_vertex(b)
	st.set_color(colour)
	st.add_vertex(c)


static func _add_box(st: SurfaceTool, centre: Vector3, size: Vector3, colour: Color) -> void:
	var hx: float = size.x * 0.5
	var hy: float = size.y * 0.5
	var hz: float = size.z * 0.5
	var p000: Vector3 = centre + Vector3(-hx, -hy, -hz)
	var p100: Vector3 = centre + Vector3(hx, -hy, -hz)
	var p110: Vector3 = centre + Vector3(hx, hy, -hz)
	var p010: Vector3 = centre + Vector3(-hx, hy, -hz)
	var p001: Vector3 = centre + Vector3(-hx, -hy, hz)
	var p101: Vector3 = centre + Vector3(hx, -hy, hz)
	var p111: Vector3 = centre + Vector3(hx, hy, hz)
	var p011: Vector3 = centre + Vector3(-hx, hy, hz)
	_add_quad_facing(st, p000, p100, p110, p010, Vector3.FORWARD, colour)
	_add_quad_facing(st, p001, p011, p111, p101, Vector3.BACK, colour)
	_add_quad_facing(st, p000, p001, p101, p100, Vector3.DOWN, colour)
	_add_quad_facing(st, p010, p110, p111, p011, Vector3.UP, colour)
	_add_quad_facing(st, p000, p010, p011, p001, Vector3.LEFT, colour)
	_add_quad_facing(st, p100, p101, p111, p110, Vector3.RIGHT, colour)
