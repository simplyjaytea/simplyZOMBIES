extends Node3D
# The district as geometry, not a picture: every tile becomes a floor quad, and every tile the sim
# says is solid becomes a box. This is deliberately the simplest possible reading of the map -- the
# art pass replaces the boxes, and the pixel-textured look is later work. What matters today is
# that what you see is the map the sim collides against: `SimTileMap.is_solid` is asked for every
# tile, including doors, so a closed door is a box and an open one is a doorway.
#
# Sim x/y maps to Godot x/z, one tile to one metre (`SimTileMap.TILE_METRES`). There is no second
# map and no second collision pass here; the body's position is the sim's, and this view only
# draws the ground it stands on.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimSurface = preload("res://sim/map/surface.gd")

const WALL_HEIGHT_M: float = 2.55
const LOW_HEIGHT_M: float = 0.55
const TREE_HEIGHT_M: float = 2.25
const DOOR_HEIGHT_M: float = 2.20
const WATER_Y: float = -0.08

const WALL_COLOUR: Color = Color(0.42, 0.40, 0.36)
const WINDOW_COLOUR: Color = Color(0.42, 0.52, 0.58)
const SCREEN_COLOUR: Color = Color(0.35, 0.47, 0.38)
const DOOR_COLOUR: Color = Color(0.36, 0.25, 0.16)
const LOW_COLOUR: Color = Color(0.44, 0.38, 0.28)
const TREE_COLOUR: Color = Color(0.20, 0.36, 0.20)
const WATER_COLOUR: Color = Color(0.16, 0.34, 0.45)

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


func build(map_ref: Variant) -> void:
	map = map_ref
	for child in get_children():
		child.queue_free()
	if map == null:
		return
	ground = _build_mesh("GroundTiles", _ground_surface())
	solids = _build_mesh("SolidTiles", _solid_surface())


func _build_mesh(node_name: String, mesh: Mesh) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	# Back-face culling stays on. Every quad is wound to its outward normal below, so a hole in the
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


func _solid_surface() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w: int = int(map.w)
	var h: int = int(map.h)
	for ty in h:
		for tx in w:
			if not SimTileMap.is_solid(map, tx, ty):
				continue
			var tile: int = int(map.tiles[ty * w + tx])
			if tile == SimTileMap.Tile.Water:
				continue
			var centre: Vector3 = Vector3(float(tx) + 0.5, 0.0, float(ty) + 0.5)
			match tile:
				SimTileMap.Tile.Low:
					_add_box(st, centre + Vector3(0.0, LOW_HEIGHT_M * 0.5, 0.0), Vector3(0.92, LOW_HEIGHT_M, 0.92), LOW_COLOUR)
				SimTileMap.Tile.Tree:
					_add_box(st, centre + Vector3(0.0, TREE_HEIGHT_M * 0.5, 0.0), Vector3(0.72, TREE_HEIGHT_M, 0.72), TREE_COLOUR)
				SimTileMap.Tile.Door:
					_add_box(st, centre + Vector3(0.0, DOOR_HEIGHT_M * 0.5, 0.0), Vector3(0.94, DOOR_HEIGHT_M, 0.94), DOOR_COLOUR)
				SimTileMap.Tile.Window:
					_add_box(st, centre + Vector3(0.0, WALL_HEIGHT_M * 0.5, 0.0), Vector3(1.0, WALL_HEIGHT_M, 1.0), WINDOW_COLOUR)
				SimTileMap.Tile.Screen:
					_add_box(st, centre + Vector3(0.0, WALL_HEIGHT_M * 0.5, 0.0), Vector3(1.0, WALL_HEIGHT_M, 1.0), SCREEN_COLOUR)
				_:
					_add_box(st, centre + Vector3(0.0, WALL_HEIGHT_M * 0.5, 0.0), Vector3(1.0, WALL_HEIGHT_M, 1.0), WALL_COLOUR)
	st.generate_normals()
	return st.commit()


func _surface_colour(surface: int) -> Color:
	if surface < 0 or surface >= SURFACE_COLOURS.size():
		return SURFACE_COLOURS[SimSurface.Surface.Dirt]
	return SURFACE_COLOURS[surface]


func _add_quad_up(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, colour: Color) -> void:
	_add_quad_facing(st, a, b, c, d, Vector3.UP, colour)


# Adds the quad as two triangles wound so the normal `generate_normals` will produce along
# `outward`. Godot's convention is the clockwise one: for triangle (a, b, c) the generated normal
# is `(c - a) x (b - a)`, not `(b - a) x (c - a)`. The corner order is flipped only when that
# generated normal disagrees with the outward one. That is what lets one helper build a floor (up),
# a wall (sideways) and a box without a second convention or double-sided geometry.
func _add_quad_facing(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, colour: Color) -> void:
	var generated: Vector3 = (c - a).cross(b - a)
	if generated.dot(outward) < 0.0:
		_add_tri(st, a, c, b, colour)
		_add_tri(st, a, d, c, colour)
	else:
		_add_tri(st, a, b, c, colour)
		_add_tri(st, a, c, d, colour)


func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, colour: Color) -> void:
	st.set_color(colour)
	st.add_vertex(a)
	st.set_color(colour)
	st.add_vertex(b)
	st.set_color(colour)
	st.add_vertex(c)


func _add_box(st: SurfaceTool, centre: Vector3, size: Vector3, colour: Color) -> void:
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
