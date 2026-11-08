extends Node3D
# The district as geometry, not a picture. Every tile's floor is a quad, and every height band
# `SimSpace.PROFILE` gives the tile is a box over the full tile footprint: a window is a sill and a
# lintel with an aperture between, a Low tile is drawn, a doorway has a lintel. Nothing here decides
# a height. The bands are the sim's, and this view draws them and nothing else (docs/40, "The one
# authority": "the presentation builds its geometry from SimSpace.PROFILE and from nothing else").
#
# A manifested building draws its own walls and windows (`building_view.gd`), chosen per tile from
# the stamped map: a wall at 0..2550 mm over the full tile, a window as its 0..1000 mm sill and
# 2100..2550 mm lintel. Where it drew the tile's sim profile, that tile's band boxes here are dropped;
# anywhere else, including a tile it drew as something the sim does not say, the band boxes stay.
# Other full walls use `wall_module.glb`, scaled to the same band and flush with a tile edge.
# `godot:check:fp_geometry` measures both paths, and casts rays through the windows of a real district.
#
# Doors and boards always keep their ordinary dynamic band boxes; their textured faces and casings are
# presentation-only surfaces inside the same tiles. Roofs, ceilings, floors and trim add no collision
# and never choose a height the sim does not publish. `building_finishes_enabled` lets the capture
# and benchmark drivers retain an exact baseline.
#
# The meshes stay merged by category: one ground mesh, one opaque solid mesh and one see-through
# mesh for the wire fence, MultiMesh wall modules and barricades, and per manifested building two
# merged atlas meshes (spatial bands and finishes) plus one `Openings` mesh of its per-tile pieces.
# The per-tile geometry comes from `tile_boxes`, which is also what `tile_mesh` builds for the gate to
# judge a tile against its bands.
#
# Sim x/y maps to Godot x/z, one tile to one metre (`SimTileMap.TILE_METRES`). There is no second
# map and no second collision pass here.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimSurface = preload("res://sim/map/surface.gd")
const SimSpace = preload("res://sim/space/space.gd")
const Assets = preload("res://presentation/first_person/assets.gd")
const BuildingView = preload("res://presentation/first_person/building_view.gd")

# Two placement variants of the wall module: as authored, and turned half a turn about its own
# centre, so a long row does not repeat one face. The kit's three plaster variants live inside the
# mesh's atlas and cannot be re-picked per instance, so the turn is the per-tile variation the
# geometry offers.
const WALL_MODULE_VARIANTS: int = 2
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
# The kit art this build drew: one instance record per wall tile {tile, variant, transform}, and one
# per barricade {tile, transform}. The gate reads these to measure the drawn geometry; the lists are
# empty when the GLBs are missing, which is how the KIT lane knows to skip.
var wall_instances: Array = []
var barricade_instances: Array = []
var building_finishes: Node3D = null
var building_finishes_enabled: bool = true
# The gate's planted error, handed to the building view before it builds (see its `force_wall`).
var building_force_wall: Dictionary = {}
# Map tile -> "wall" or "window": what the finished buildings drew there.
var _drawn: Dictionary = {}


## Builds the district. `salt` is mixed with each tile's index to pick a wall-module variant; the
## scene passes its district seed, because the map is regenerated from that seed and does not carry
## one. It is not a sim value and nothing reads it but this placement.
func build(map_ref: Variant, salt: int = 0) -> void:
	map = map_ref
	for child in get_children():
		remove_child(child)
		child.queue_free()
	wall_instances.clear()
	barricade_instances.clear()
	_drawn = {}
	building_finishes = null
	if map == null:
		return
	if building_finishes_enabled:
		building_finishes = BuildingView.new()
		building_finishes.name = "BuildingFinishes"
		building_finishes.set("force_wall", building_force_wall)
		add_child(building_finishes)
		building_finishes.call("build", map, salt)
		_drawn = building_finishes.get("drawn") as Dictionary
	var wall_mesh: Mesh = _loaded_mesh(Assets.WALL_MODULE)
	ground = _build_mesh("GroundTiles", _ground_surface(), false)
	solids = _build_mesh("SolidTiles", _band_surface(false, wall_mesh != null), false)
	fence = _build_mesh("FenceTiles", _band_surface(true, false), true)
	if wall_mesh != null:
		_build_wall_modules(wall_mesh, salt)
	_build_barricades(_loaded_mesh(Assets.BARRICADE))


# The mesh of a kit model, or null when the file is missing. The loaded node is only a carrier: the
# mesh keeps the material `load_model` filtered, and the node is freed here.
func _loaded_mesh(path: String) -> Mesh:
	var loaded: Dictionary = Assets.load_model(path)
	var node: Node = loaded["node"] as Node
	var mesh: Mesh = Assets.first_mesh(node)
	if node != null:
		node.free()
	return mesh


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
	st.set_smooth_group(-1)
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
# there is nothing to draw, so the node exists without a mesh. Full walls yield to either their kit
# module or a finished building; a window yields only to a finished building that drew it as one.
func _band_surface(see_through: bool, skip_walls: bool) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var drew: bool = false
	for ty in int(map.h):
		for tx in int(map.w):
			var key: String = SimSpace.profile_key(map, tx, ty)
			var drawn: String = String(_drawn.get(Vector2i(tx, ty), ""))
			if not see_through and key == "wall" and (skip_walls or drawn == "wall"):
				continue
			if not see_through and key == "window" and drawn == "window":
				continue
			for box in tile_boxes(map, tx, ty):
				if bool(box["transparent"]) != see_through:
					continue
				_add_box_of(st, box)
				drew = true
	if not drew:
		return null
	st.generate_normals()
	return st.commit()


# --- kit art: walls and barricades ----------------------------------------------------------

func _build_wall_modules(mesh: Mesh, salt: int) -> void:
	var size: Vector3 = mesh.get_aabb().size
	if size.y <= 0.0:
		return
	var groups: Array = []
	for variant in WALL_MODULE_VARIANTS:
		groups.append([])
	for ty in int(map.h):
		for tx in int(map.w):
			if SimSpace.profile_key(map, tx, ty) != "wall":
				continue
			if String(_drawn.get(Vector2i(tx, ty), "")) == "wall":
				continue
			var variant: int = _tile_hash(salt, tx, ty) % WALL_MODULE_VARIANTS
			var xform: Transform3D = wall_placement(map, tx, ty, size, variant)
			(groups[variant] as Array).append(xform)
			wall_instances.append({"tile": Vector2i(tx, ty), "variant": variant, "transform": xform})
	for variant in WALL_MODULE_VARIANTS:
		_multimesh_node("WallModules%d" % variant, mesh, groups[variant])


func _build_barricades(mesh: Mesh) -> void:
	if mesh == null:
		return
	var size: Vector3 = mesh.get_aabb().size
	var transforms: Array = []
	for ty in int(map.h):
		for tx in int(map.w):
			if not SimSpace.profile_key(map, tx, ty).begins_with("board:"):
				continue
			var xform: Transform3D = barricade_placement(map, tx, ty, size)
			transforms.append(xform)
			barricade_instances.append({"tile": Vector2i(tx, ty), "transform": xform})
	_multimesh_node("Barricades", mesh, transforms)


func _multimesh_node(node_name: String, mesh: Mesh, transforms: Array) -> MultiMeshInstance3D:
	if transforms.is_empty():
		return null
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i] as Transform3D)
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	# The scene draws no shadows, so the modules do not pay for them.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


## Where one wall module stands for tile (tx, ty), given the module's authored size. The module's top
## is scaled to the wall band's top; its width spans the tile along the run; its depth is its own
## authored thickness, with the outer face on the tile edge toward open ground and the body inside the
## tile. Shared with `godot:check:fp_geometry`'s KIT lane, which plants a wrong-size mesh here and
## expects the same measurement to refuse it.
static func wall_placement(map: Variant, tx: int, ty: int, module_size: Vector3, variant: int = 0) -> Transform3D:
	var top_m: float = _band_top_m("wall")
	var scale_y: float = top_m / module_size.y if module_size.y > 0.0 else 1.0
	var along_x: bool = _runs_along_x(map, tx, ty)
	var face: Vector2i = _open_face(map, tx, ty, along_x)
	var angle: float = 0.0 if along_x else PI * 0.5
	if variant % 2 == 1:
		angle += PI
	var depth: float = module_size.z
	# Local +Z is the depth axis; the width (local X) is one metre along the run. The module's origin
	# is its floor centre, so the Y translation is zero and the scale is applied before the turn.
	var centre: Vector3 = Vector3(float(tx) + 0.5, 0.0, float(ty) + 0.5)
	centre.x += float(face.x) * (0.5 - depth * 0.5)
	centre.z += float(face.y) * (0.5 - depth * 0.5)
	return Transform3D(Basis(Vector3.UP, angle).scaled(Vector3(1.0, scale_y, 1.0)), centre)


## Where one barricade stands for a boarded tile. Its back face is flush with the tile edge toward
## open ground and the boards hang outside the tile, as boards nailed over a window do; the band boxes
## underneath are unchanged and stay the occlusion authority.
static func barricade_placement(map: Variant, tx: int, ty: int, module_size: Vector3) -> Transform3D:
	var along_x: bool = _runs_along_x(map, tx, ty)
	var face: Vector2i = _open_face(map, tx, ty, along_x)
	var angle: float = 0.0 if along_x else PI * 0.5
	var depth: float = module_size.z
	var centre: Vector3 = Vector3(float(tx) + 0.5, 0.0, float(ty) + 0.5)
	centre.x += float(face.x) * (0.5 + depth * 0.5)
	centre.z += float(face.y) * (0.5 + depth * 0.5)
	return Transform3D(Basis(Vector3.UP, angle), centre)


# A wall run is along X when more of its neighbours in X are walls; a tie (an isolated tile) runs X.
static func _runs_along_x(map: Variant, tx: int, ty: int) -> bool:
	var x: int = 0
	for d in [Vector2i(-1, 0), Vector2i(1, 0)]:
		if _is_wall(map, tx + d.x, ty + d.y):
			x += 1
	var y: int = 0
	for d in [Vector2i(0, -1), Vector2i(0, 1)]:
		if _is_wall(map, tx + d.x, ty + d.y):
			y += 1
	return x >= y


static func _is_wall(map: Variant, tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return false
	return SimSpace.profile_key(map, tx, ty) == "wall"


# The perpendicular side of the tile that faces open ground: the first one in a fixed order, so a
# boot is repeatable. A tile with no open side uses the first side anyway.
static func _open_face(map: Variant, tx: int, ty: int, along_x: bool) -> Vector2i:
	var sides: Array = [Vector2i(0, -1), Vector2i(0, 1)] if along_x else [Vector2i(-1, 0), Vector2i(1, 0)]
	for side in sides:
		var n: Vector2i = side as Vector2i
		var nx: int = tx + n.x
		var ny: int = ty + n.y
		if nx >= 0 and ny >= 0 and nx < int(map.w) and ny < int(map.h) and not SimTileMap.is_solid(map, nx, ny):
			return n
	return sides[0] as Vector2i


# A stable per-tile choice from the scene's seed salt and the tile index. Not a sim RNG: this is
# placement only, so it never draws from a world stream that another system measures.
static func _tile_hash(salt: int, tx: int, ty: int) -> int:
	var h: int = (salt * 73856093) ^ (tx * 19349663) ^ (ty * 83492791)
	h = h & 0x7fffffff
	h = h ^ (h >> 13)
	return h & 0x7fffffff


# The top of a profile key's highest band, in metres: 2.55 for the wall.
static func _band_top_m(key: String) -> float:
	var top: int = 0
	for band in SimSpace.bands(key):
		top = maxi(top, int(band[1]))
	return float(top) / 1000.0


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
	st.set_smooth_group(-1)
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
