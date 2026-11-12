extends RefCounted
# How the standing things no kit building owns are drawn (docs/46, "What is a plain box today"): the
# generic wall, a window, a door, a boarded opening, the raised walls, Low cover and the wire fence.
#
# The geometry is not decided here. Every box below is a band of `SimSpace.PROFILE` over its tile's full
# footprint, the same boxes `district_view.gd`'s `tile_boxes` gives and `godot:check:fp_geometry` measures.
# What this file adds is what is painted on them: which band of the structure sheets each face shows, and
# the few trim boxes around a generic window. The sheets are painted by `tools/look/build_structures.py`
# at 64 texels a metre and described by `structures.manifest.json`; nothing here names a pixel.
#
# A face that runs along a wall takes its texture from the world: u is the metre along the run and v the
# height, so courses, moss and stains carry across tiles and no two metres of a wall are the same four
# metres apart. A vehicle takes its texture from its own record instead: the picture is laid along its
# length from the end `facing` names.
#
# Every choice is a hash of the scene's seed salt and the tile, or a fact of the map (the edge ring, the
# well anchor, a vehicle record, a run of Low tiles). Nothing draws from an RNG and nothing here is read
# by the sim.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimSpace = preload("res://sim/space/space.gd")

# === PRESENTATION TUNING ==========================================================================
# Every colour, size and choice of this piece. Colours are sRGB under neutral white light (docs/46).

# A generic wall is drawn over the whole tile the sim blocks, like a window's sill and head and like a
# kit building's wall. False draws only the 0.12 m panel the KIT lane measures, flush to the open face.
const WALL_FILLS_TILE: bool = true
# The material family of a generic wall: the district's edge ring, and every other wall.
const EDGE_WALL: String = "retaining"
const YARD_WALL: String = "block"
# What a run of Low tiles that is no vehicle and no well may be, chosen by a hash of the run's first tile.
const LOW_KINDS: Array[String] = ["timber", "low_block", "rubble", "timber"]
# The form a vehicle class is painted as. A class not listed is a two-wheeler or smaller, under a tarpaulin.
const VEHICLE_FORMS: Dictionary = {
	"vehicle.sedan": "car",
	"vehicle.van": "van",
	"vehicle.truck": "truck",
}
const SMALL_FORM: String = "tarp"
# Paint, multiplied over the near-white body: white, silver, a faded sage, a pale grey-blue, cream.
const VEHICLE_TINTS: Array[Color] = [
	Color("f2f2ee"), Color("f2f2ee"), Color("b9bdbd"), Color("b9bdbd"),
	Color("a9b5a0"), Color("a7b3bb"), Color("ddd3b8"), Color("8f9390"),
]
const TARP_TINTS: Array[Color] = [Color("ffffff"), Color("d9dccf"), Color("c9cfd4")]
const ROUGHNESS: float = 0.95
# A kit building's door tile: the band box behind the leaf takes the door style's frame colour times this.
const DOOR_BOX_SHADE: float = 0.82
# The trim around a generic window: a cast sill ledge, a timber head and timber jambs on the wall beside.
const SILL_COLOUR: Color = Color("aeaca4")
const FRAME_COLOUR: Color = Color("4f4338")
const SILL_PROUD_M: float = 0.06
const SILL_HEIGHT_M: float = 0.07
const FRAME_PROUD_M: float = 0.03
const FRAME_WIDTH_M: float = 0.08
const WINDOW_SILL_M: float = 1.00
const WINDOW_HEAD_M: float = 2.10
# ==================================================================================================

const DIR: String = "res://assets/first_person/structures/"
const MANIFEST: String = DIR + "structures.manifest.json"
const SIDES: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

static var _tried: bool = false
static var _bands: Dictionary = {}
static var _materials: Dictionary = {}
static var _heights: Dictionary = {}
static var _density: float = 64.0
static var _period_m: float = 4.0


## One mesh surface being gathered: non-indexed triangles, each vertex carrying its face's normal, so the
## result is flat-shaded (the FLAT lane).
class Batch:
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var colours: PackedColorArray = PackedColorArray()

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, colour: Color) -> void:
		# Godot's front face is the clockwise one: for (a, b, c) the face normal is (c - a) x (b - a).
		if (c - a).cross(b - a).dot(outward) < 0.0:
			_tri(a, c, b, outward, ua, uc, ub, colour)
			_tri(a, d, c, outward, ua, ud, uc, colour)
		else:
			_tri(a, b, c, outward, ua, ub, uc, colour)
			_tri(a, c, d, outward, ua, uc, ud, colour)

	func _tri(a: Vector3, b: Vector3, c: Vector3, normal: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, colour: Color) -> void:
		vertices.append(a)
		vertices.append(b)
		vertices.append(c)
		for _i in 3:
			normals.append(normal)
			colours.append(colour)
		uvs.append(ua)
		uvs.append(ub)
		uvs.append(uc)

	func is_empty() -> bool:
		return vertices.is_empty()

	func add_to(mesh: ArrayMesh, material: Material) -> void:
		if vertices.is_empty():
			return
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_COLOR] = colours
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)


## True when the sheets and their manifest loaded. Without them the district keeps its flat band boxes.
static func ready() -> bool:
	if not _tried:
		_tried = true
		_load()
	return not _materials.is_empty()


## Whether a profile key's bands are drawn by this file rather than as flat boxes.
static func draws(key: String) -> bool:
	return key != "tree" and key != "screen" and key != "floor" and key != "water"


## The material of a sheet ("walls", "low", "fence"), or null.
static func material_of(sheet: String) -> StandardMaterial3D:
	if not ready():
		return null
	return _materials.get(sheet) as StandardMaterial3D


## Whether a material shows a structure sheet the way the look requires: a texture with mipmaps, nearest
## filtered. The STRUCTURES lane asks this of what the scene drew, and of a planted linear one.
static func is_pixel_true(material: Material) -> bool:
	var base: BaseMaterial3D = material as BaseMaterial3D
	if base == null or base.albedo_texture == null:
		return false
	var image: Image = base.albedo_texture.get_image()
	if image == null or not image.has_mipmaps():
		return false
	return base.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS


## Texels per metre the sheets were painted at.
static func density() -> float:
	return _density


static func _load() -> void:
	_bands = {}
	_materials = {}
	_heights = {}
	if not FileAccess.file_exists(MANIFEST):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not (parsed is Dictionary):
		return
	var manifest: Dictionary = parsed as Dictionary
	_density = float(manifest.get("density", 64.0))
	_period_m = float(manifest.get("period_px", 256.0)) / _density
	var bands: Dictionary = {}
	var materials: Dictionary = {}
	var sheets: Dictionary = manifest.get("sheets", {}) as Dictionary
	for sheet_v in sheets.keys():
		var sheet: String = String(sheet_v)
		var entry: Dictionary = sheets[sheet] as Dictionary
		var image: Image = _image(DIR + String(entry.get("file", "")))
		if image == null:
			return
		image.generate_mipmaps()
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_texture = ImageTexture.create_from_image(image)
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		material.vertex_color_use_as_albedo = true
		material.vertex_color_is_srgb = true
		material.roughness = ROUGHNESS
		if sheet == "fence":
			# The wire is opaque and the gaps are not there: the sim's fence passes sight and a shot.
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
		else:
			material.cull_mode = BaseMaterial3D.CULL_BACK
		materials[sheet] = material
		_heights[sheet] = float(entry.get("height", 1.0))
		var listed: Dictionary = entry.get("bands", {}) as Dictionary
		for name_v in listed.keys():
			var band: Dictionary = (listed[name_v] as Dictionary).duplicate()
			band["sheet"] = sheet
			band["sheet_h"] = float(entry.get("height", 1.0))
			band["sheet_w"] = float(entry.get("width", 256.0))
			bands[String(name_v)] = band
	_bands = bands
	_materials = materials


# The sheet as an image: read from its bytes where the file is on disk (a clean checkout has no import
# state), or from the imported texture where only that is packed (an export).
static func _image(path: String) -> Image:
	var image: Image = null
	if FileAccess.file_exists(path):
		var loaded: Image = Image.new()
		if loaded.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
			image = loaded
	if image == null and ResourceLoader.exists(path):
		var texture: Texture2D = load(path) as Texture2D
		if texture != null:
			image = texture.get_image()
	if image != null and image.is_compressed():
		image.decompress()
	return image


# --- the district's structures --------------------------------------------------------------------

## Gathers every face this file draws for a map. Returns {} when the sheets are missing. Otherwise:
##   solids   {sheet: Batch}  the opaque bands that belong in the district's SolidTiles mesh
##   walls    {sheet: Batch}  the generic walls, when a wall module draws them (`wall_records` non-empty)
##   fence    Batch           the wire fence's bands
##   trim     Array           {min, max, colour} boxes around generic windows, colours linear
##   counts   {key: int}      how many tiles of each profile key were drawn here
## `drawn` is what the finished buildings drew (tile -> "wall" | "window"); those tiles are theirs.
## `wall_records` is the district's `wall_instances`, read only when WALL_FILLS_TILE is off.
## `owned` answers whether a kit building owns a tile (a door's style); `style_of` gives its door style.
static func gather(map: Variant, salt: int, drawn: Dictionary, wall_records: Array, walls_by_module: bool, style_of: Callable) -> Dictionary:
	if not ready() or map == null:
		return {}
	var out: Dictionary = {
		"solids": {"walls": Batch.new(), "low": Batch.new()},
		"walls": {"walls": Batch.new()},
		"fence": Batch.new(),
		"trim": [],
		"counts": {},
	}
	var solids: Dictionary = out["solids"] as Dictionary
	var w: int = int(map.w)
	var h: int = int(map.h)
	var tiles: PackedByteArray = map.tiles
	var overlays: Dictionary = map.overlays if map.overlays is Dictionary else {}
	var vehicle_at: Dictionary = _vehicle_tiles(map)
	var well: Vector2i = _well_tile(map)
	var counts: Dictionary = out["counts"] as Dictionary
	for ty in h:
		for tx in w:
			var idx: int = ty * w + tx
			if int(tiles[idx]) == SimTileMap.Tile.Floor and not overlays.has(idx):
				continue
			var key: String = SimSpace.profile_key(map, tx, ty)
			if not draws(key):
				continue
			var theirs: String = String(drawn.get(Vector2i(tx, ty), ""))
			if key == "wall":
				if theirs == "wall":
					continue
				counts[key] = int(counts.get(key, 0)) + 1
				var family: String = EDGE_WALL if (tx == 0 or ty == 0 or tx == w - 1 or ty == h - 1) else YARD_WALL
				var target: Batch = (out["walls"] as Dictionary)["walls"] if walls_by_module else solids["walls"]
				if walls_by_module and not WALL_FILLS_TILE:
					continue
				_tiling_box(target, Vector3(tx, 0.0, ty), Vector3(tx + 1, _top_m(key), ty + 1), family + "_side", _top_of(family), _hidden(map, tx, ty, 0, SimSpace.FULL_MM), true, Color.WHITE)
				continue
			if key == "window" and theirs == "window":
				continue
			counts[key] = int(counts.get(key, 0)) + 1
			if key == "fence":
				_fence_tile(out["fence"] as Batch, map, tx, ty)
				continue
			if key == "low":
				_low_tile(solids["low"] as Batch, map, tx, ty, salt, vehicle_at, well)
				continue
			var axis_x: bool = _axis_x(map, tx, ty)
			for band in SimSpace.bands(key):
				var lo_mm: int = int(band[0])
				var hi_mm: int = int(band[1])
				var lo: Vector3 = Vector3(tx, float(lo_mm) / 1000.0, ty)
				var hi: Vector3 = Vector3(tx + 1, float(hi_mm) / 1000.0, ty + 1)
				var hidden: int = _hidden(map, tx, ty, lo_mm, hi_mm)
				var side: String = ""
				var top: String = "dark_top"
				var colour: Color = Color.WHITE
				if key == "window":
					side = "block_head" if lo_mm > 0 else "block_side"
					top = "concrete_top"
				elif key.begins_with("door."):
					var style: Variant = style_of.call(tx, ty)
					if style is Dictionary:
						side = "white"
						top = "white"
						colour = ((style as Dictionary)["frame"] as Color).linear_to_srgb() * DOOR_BOX_SHADE
						colour.a = 1.0
					else:
						side = "gate_head" if lo_mm > 0 else "gate_side"
				elif key.begins_with("board:"):
					side = "planks_side"
				elif key == "scrap":
					side = "sheet_side"
				elif key == "timber":
					side = "cedar_side"
				elif key == "stone":
					side = "stone_side"
					top = "stone_top"
				else:
					side = YARD_WALL + "_side"
					top = _top_of(YARD_WALL)
				_tiling_box(solids["walls"] as Batch, lo, hi, side, top, hidden, axis_x, colour)
			if key == "window":
				(out["trim"] as Array).append_array(window_trim(map, tx, ty))
	if walls_by_module and not WALL_FILLS_TILE:
		for record_v in wall_records:
			var record: Dictionary = record_v as Dictionary
			var tile: Vector2i = record["tile"] as Vector2i
			var box: AABB = (record["transform"] as Transform3D) * AABB(Vector3(-0.5, 0.0, -0.06), Vector3(1.0, 2.6, 0.12))
			var family: String = EDGE_WALL if (tile.x == 0 or tile.y == 0 or tile.x == w - 1 or tile.y == h - 1) else YARD_WALL
			_tiling_box((out["walls"] as Dictionary)["walls"] as Batch, box.position, box.end, family + "_side", _top_of(family), 0, box.size.x >= box.size.z, Color.WHITE)
	return out


## Puts what `gather` found into the district's nodes: appends the textured bands to SolidTiles and the
## fence's to FenceTiles, each surface under its own sheet's material, and returns the generic walls' mesh
## (null when there are none). A mesh that held only flat boxes keeps them as its first surface.
static func dress(solids: MeshInstance3D, fence: MeshInstance3D, look: Dictionary) -> ArrayMesh:
	if look.is_empty():
		return null
	var batches: Dictionary = look["solids"] as Dictionary
	var any: bool = false
	for sheet in batches.keys():
		if not (batches[sheet] as Batch).is_empty():
			any = true
	if any and solids != null:
		var mesh: ArrayMesh = solids.mesh as ArrayMesh
		if mesh == null:
			mesh = ArrayMesh.new()
			solids.mesh = mesh
		elif solids.material_override != null:
			for s in mesh.get_surface_count():
				mesh.surface_set_material(s, solids.material_override)
		solids.material_override = null
		for sheet in batches.keys():
			(batches[sheet] as Batch).add_to(mesh, _materials[sheet] as Material)
	var wire: Batch = look["fence"] as Batch
	if not wire.is_empty() and fence != null:
		var fence_mesh: ArrayMesh = ArrayMesh.new()
		wire.add_to(fence_mesh, _materials["fence"] as Material)
		fence.mesh = fence_mesh
		fence.material_override = null
	var walls: Dictionary = look["walls"] as Dictionary
	var wall_mesh: ArrayMesh = null
	for sheet in walls.keys():
		if (walls[sheet] as Batch).is_empty():
			continue
		if wall_mesh == null:
			wall_mesh = ArrayMesh.new()
		(walls[sheet] as Batch).add_to(wall_mesh, _materials[sheet] as Material)
	return wall_mesh


# --- faces ----------------------------------------------------------------------------------------

static func _top_m(key: String) -> float:
	var top: int = 0
	for band in SimSpace.bands(key):
		top = maxi(top, int(band[1]))
	return float(top) / 1000.0


static func _top_of(family: String) -> String:
	return "stone_top" if family == "stone" else ("dark_top" if family == "cedar" or family == "sheet" else "concrete_top")


static func _band(band_name: String) -> Dictionary:
	return _bands.get(band_name, _bands.get("white", {})) as Dictionary


# The v of a height on a side band: the band's first row stands at its `top_m`.
static func _v(band: Dictionary, height_m: float) -> float:
	return (float(band["y"]) + (float(band["top_m"]) - height_m) * _density) / float(band["sheet_h"])


# One band box whose faces tile from the world. `hidden` is a bit per side (SIDES order) the neighbour
# covers. `axis_x` says which way the run goes: the top's texture runs along it, and a material with an
# end band (stacked timber) shows its ends across it.
static func _tiling_box(batch: Batch, lo: Vector3, hi: Vector3, side_name: String, top_name: String, hidden: int, axis_x: bool, colour: Color, end_name: String = "") -> void:
	var side: Dictionary = _band(side_name)
	var top: Dictionary = _band(top_name)
	if side.is_empty() or top.is_empty():
		return
	var end: Dictionary = _band(end_name) if end_name != "" else side
	var per_m: float = 1.0 / _period_m
	for i in SIDES.size():
		if (hidden >> i) & 1 == 1:
			continue
		var n: Vector2i = SIDES[i]
		var band: Dictionary = side
		if end_name != "" and ((n.x != 0) == axis_x):
			band = end
		var v_lo: float = _v(band, lo.y)
		var v_hi: float = _v(band, hi.y)
		var a: Vector3
		var b: Vector3
		var u_a: float
		var u_b: float
		if n.y != 0:
			var z: float = hi.z if n.y > 0 else lo.z
			a = Vector3(lo.x, lo.y, z)
			b = Vector3(hi.x, lo.y, z)
			u_a = lo.x * per_m
			u_b = hi.x * per_m
		else:
			var x: float = hi.x if n.x > 0 else lo.x
			a = Vector3(x, lo.y, lo.z)
			b = Vector3(x, lo.y, hi.z)
			u_a = lo.z * per_m
			u_b = hi.z * per_m
		var rise: Vector3 = Vector3(0.0, hi.y - lo.y, 0.0)
		batch.quad(a, b, b + rise, a + rise, Vector3(n.x, 0.0, n.y), Vector2(u_a, v_lo), Vector2(u_b, v_lo), Vector2(u_b, v_hi), Vector2(u_a, v_hi), colour)
	_flat_face(batch, lo, hi, hi.y, Vector3.UP, top, axis_x, colour)
	if lo.y > 0.0:
		_flat_face(batch, lo, hi, lo.y, Vector3.DOWN, top, axis_x, colour)


# A top or an underside: the texture runs along the run and spans the tile across it.
static func _flat_face(batch: Batch, lo: Vector3, hi: Vector3, y: float, normal: Vector3, band: Dictionary, axis_x: bool, colour: Color) -> void:
	var per_m: float = 1.0 / _period_m
	var v0: float = float(band["y"]) / float(band["sheet_h"])
	var v1: float = (float(band["y"]) + minf(float(band["h"]), _density)) / float(band["sheet_h"])
	var a: Vector3 = Vector3(lo.x, y, lo.z)
	var b: Vector3 = Vector3(hi.x, y, lo.z)
	var c: Vector3 = Vector3(hi.x, y, hi.z)
	var d: Vector3 = Vector3(lo.x, y, hi.z)
	if axis_x:
		batch.quad(a, b, c, d, normal, Vector2(lo.x * per_m, v0), Vector2(hi.x * per_m, v0), Vector2(hi.x * per_m, v1), Vector2(lo.x * per_m, v1), colour)
	else:
		batch.quad(a, b, c, d, normal, Vector2(lo.z * per_m, v0), Vector2(lo.z * per_m, v1), Vector2(hi.z * per_m, v1), Vector2(hi.z * per_m, v0), colour)


# Which sides of a band [lo, hi] (mm) the neighbouring tile covers with an opaque band of its own, so the
# face between them is never seen. Trees and thickets are left out: another view draws them.
static func _hidden(map: Variant, tx: int, ty: int, lo_mm: int, hi_mm: int) -> int:
	var mask: int = 0
	for i in SIDES.size():
		var nx: int = tx + SIDES[i].x
		var ny: int = ty + SIDES[i].y
		if nx < 0 or ny < 0 or nx >= int(map.w) or ny >= int(map.h):
			continue
		var key: String = SimSpace.profile_key(map, nx, ny)
		if key == "floor" or key == "tree" or key == "screen" or key == "fence" or key == "water":
			continue
		for band in SimSpace.bands(key):
			if int(band[0]) <= lo_mm and int(band[1]) >= hi_mm:
				mask |= 1 << i
				break
	return mask


# A run goes along x when it has a standing neighbour of any kind on x, or none on y either.
static func _axis_x(map: Variant, tx: int, ty: int) -> bool:
	var x: int = 0
	var y: int = 0
	for i in SIDES.size():
		var nx: int = tx + SIDES[i].x
		var ny: int = ty + SIDES[i].y
		if nx < 0 or ny < 0 or nx >= int(map.w) or ny >= int(map.h):
			continue
		var key: String = SimSpace.profile_key(map, nx, ny)
		if key == "floor" or key == "tree" or key == "screen" or key == "water" or key == "low":
			continue
		if SIDES[i].x != 0:
			x += 1
		else:
			y += 1
	return x >= y


# --- Low cover ------------------------------------------------------------------------------------

static func _vehicle_tiles(map: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (map.vehicles is Array):
		return out
	for record_v in map.vehicles as Array:
		var record: Dictionary = record_v as Dictionary
		for y in range(int(record["y"]), int(record["y"]) + int(record["h"])):
			for x in range(int(record["x"]), int(record["x"]) + int(record["w"])):
				out[Vector2i(x, y)] = record
	return out


static func _well_tile(map: Variant) -> Vector2i:
	var anchors: Dictionary = map.anchors if map.anchors is Dictionary else {}
	var well: Variant = anchors.get("well")
	if well is Dictionary:
		return Vector2i(int((well as Dictionary).get("x", -1)), int((well as Dictionary).get("y", -1)))
	return Vector2i(-1, -1)


static func _plain_low(map: Variant, x: int, y: int, vehicle_at: Dictionary, well: Vector2i) -> bool:
	if x < 0 or y < 0 or x >= int(map.w) or y >= int(map.h):
		return false
	if vehicle_at.has(Vector2i(x, y)) or Vector2i(x, y) == well:
		return false
	return SimSpace.profile_key(map, x, y) == "low"


## What one Low tile is drawn as: "car", "van", "truck", "tarp", "well", or one of LOW_KINDS.
static func low_form(map: Variant, tx: int, ty: int, salt: int, vehicle_at: Dictionary = {}, well: Vector2i = Vector2i(-2, -2)) -> Dictionary:
	if well == Vector2i(-2, -2):
		vehicle_at = _vehicle_tiles(map)
		well = _well_tile(map)
	var tile: Vector2i = Vector2i(tx, ty)
	if vehicle_at.has(tile):
		var record: Dictionary = vehicle_at[tile] as Dictionary
		return {"form": String(VEHICLE_FORMS.get(String(record.get("class", "")), SMALL_FORM)), "record": record}
	if tile == well:
		return {"form": "well", "axis_x": true}
	var axis_x: bool = true
	if _plain_low(map, tx - 1, ty, vehicle_at, well) or _plain_low(map, tx + 1, ty, vehicle_at, well):
		axis_x = true
	elif _plain_low(map, tx, ty - 1, vehicle_at, well) or _plain_low(map, tx, ty + 1, vehicle_at, well):
		axis_x = false
	else:
		axis_x = _hash(salt, tx, ty) % 2 == 0
	var sx: int = tx
	var sy: int = ty
	if axis_x:
		while _plain_low(map, sx - 1, sy, vehicle_at, well):
			sx -= 1
	else:
		while _plain_low(map, sx, sy - 1, vehicle_at, well):
			sy -= 1
	return {"form": LOW_KINDS[_hash(salt, sx, sy) % LOW_KINDS.size()], "axis_x": axis_x}


static func _low_tile(batch: Batch, map: Variant, tx: int, ty: int, salt: int, vehicle_at: Dictionary, well: Vector2i) -> void:
	var chosen: Dictionary = low_form(map, tx, ty, salt, vehicle_at, well)
	var form: String = String(chosen["form"])
	var lo: Vector3 = Vector3(tx, 0.0, ty)
	var hi: Vector3 = Vector3(tx + 1, _top_m("low"), ty + 1)
	if chosen.has("record"):
		_vehicle_tile(batch, chosen["record"] as Dictionary, tx, ty, form, hi.y, salt)
		return
	var hidden: int = 0
	var axis_x: bool = bool(chosen["axis_x"])
	if form == "timber":
		# A stack's faces between two tiles of the same run are inside it.
		for i in SIDES.size():
			if (SIDES[i].x != 0) == axis_x and _plain_low(map, tx + SIDES[i].x, ty + SIDES[i].y, vehicle_at, well):
				hidden |= 1 << i
		_tiling_box(batch, lo, hi, "timber_long", "timber_top", hidden, axis_x, Color.WHITE, "timber_end")
	elif form == "well":
		_tiling_box(batch, lo, hi, "well_side", "well_top", 0, true, Color.WHITE)
	else:
		_tiling_box(batch, lo, hi, form + "_side", form + "_top", _hidden(map, tx, ty, 0, int(hi.y * 1000.0)), axis_x, Color.WHITE)


# One tile of a vehicle's footprint. `s` runs along the vehicle from the end it faces, `t` across it; the
# sheet's side and top bands are laid along s, and its ends band holds the front and then the back.
static func _vehicle_tile(batch: Batch, record: Dictionary, tx: int, ty: int, form: String, top_m: float, salt: int) -> void:
	var x0: int = int(record["x"])
	var y0: int = int(record["y"])
	var w: int = int(record["w"])
	var h: int = int(record["h"])
	var ns: bool = String(record.get("axis", "ns")) == "ns"
	var facing: String = String(record.get("facing", "n"))
	var length: float = float(h if ns else w)
	var small: bool = form == SMALL_FORM
	var side: Dictionary = _band(form + "_side")
	var ends: Dictionary = _band(form + "_side" if small else form + "_ends")
	var top: Dictionary = _band(form + "_top")
	if side.is_empty() or ends.is_empty() or top.is_empty():
		return
	var tints: Array[Color] = TARP_TINTS if small else VEHICLE_TINTS
	var colour: Color = tints[_hash(salt, x0, y0) % tints.size()]
	var px: float = _density / float(side["sheet_w"])
	# Where the ends' pictures start, in texels: a tarpaulin's end follows its long side on one band.
	var front_px: float = 128.0 if small else 0.0
	var rear_px: float = 128.0
	var only_end: bool = small and length <= 1.0
	for i in SIDES.size():
		var n: Vector2i = SIDES[i]
		var nx: int = tx + n.x
		var ny: int = ty + n.y
		if nx >= x0 and nx < x0 + w and ny >= y0 and ny < y0 + h:
			continue
		var a: Vector3
		var b: Vector3
		if n.y != 0:
			var z: float = float(ty + 1) if n.y > 0 else float(ty)
			a = Vector3(tx, 0.0, z)
			b = Vector3(tx + 1, 0.0, z)
		else:
			var x: float = float(tx + 1) if n.x > 0 else float(tx)
			a = Vector3(x, 0.0, ty)
			b = Vector3(x, 0.0, ty + 1)
		var along_length: bool = (n.x != 0) == ns
		var band: Dictionary = side if (along_length and not only_end) else ends
		var u_a: float
		var u_b: float
		if along_length and not only_end:
			u_a = _s(a, x0, y0, w, h, ns, facing) * px
			u_b = _s(b, x0, y0, w, h, ns, facing) * px
		else:
			var s_here: float = _s(a, x0, y0, w, h, ns, facing)
			var start: float = front_px if (s_here < length * 0.5 or small) else rear_px
			u_a = (start / _density + _t(a, x0, y0, ns)) * px
			u_b = (start / _density + _t(b, x0, y0, ns)) * px
			if only_end and along_length:
				u_a = (start / _density + _s(a, x0, y0, w, h, ns, facing)) * px
				u_b = (start / _density + _s(b, x0, y0, w, h, ns, facing)) * px
		var v_lo: float = _v(band, 0.0)
		var v_hi: float = _v(band, top_m)
		var rise: Vector3 = Vector3(0.0, top_m, 0.0)
		batch.quad(a, b, b + rise, a + rise, Vector3(n.x, 0.0, n.y), Vector2(u_a, v_lo), Vector2(u_b, v_lo), Vector2(u_b, v_hi), Vector2(u_a, v_hi), colour)
	var corners: Array[Vector3] = [Vector3(tx, top_m, ty), Vector3(tx + 1, top_m, ty), Vector3(tx + 1, top_m, ty + 1), Vector3(tx, top_m, ty + 1)]
	var uv: Array[Vector2] = []
	for corner in corners:
		var u: float = _s(corner, x0, y0, w, h, ns, facing) * px
		var v: float = (float(top["y"]) + _t(corner, x0, y0, ns) * _density) / float(top["sheet_h"])
		uv.append(Vector2(u, v))
	batch.quad(corners[0], corners[1], corners[2], corners[3], Vector3.UP, uv[0], uv[1], uv[2], uv[3], colour)


# How far along a vehicle a point is, in metres from the end it faces.
static func _s(p: Vector3, x0: int, y0: int, w: int, h: int, ns: bool, facing: String) -> float:
	if ns:
		return p.z - float(y0) if facing == "n" else float(y0 + h) - p.z
	return p.x - float(x0) if facing == "w" else float(x0 + w) - p.x


# How far across a vehicle a point is, in metres from its north or west side.
static func _t(p: Vector3, x0: int, y0: int, ns: bool) -> float:
	return p.x - float(x0) if ns else p.z - float(y0)


# --- the wire fence -------------------------------------------------------------------------------

# One fence tile: the sim's band (0 to its top over the tile) as four faces of wire, a post at each
# corner. A face shared with the next fence tile is inside the run and is left out.
static func _fence_tile(batch: Batch, map: Variant, tx: int, ty: int) -> void:
	var band: Dictionary = _band("fence_side")
	var top_m: float = _top_m("fence")
	var v_lo: float = _v(band, 0.0)
	var v_hi: float = _v(band, top_m)
	for i in SIDES.size():
		var n: Vector2i = SIDES[i]
		var nx: int = tx + n.x
		var ny: int = ty + n.y
		if nx >= 0 and ny >= 0 and nx < int(map.w) and ny < int(map.h) and SimSpace.profile_key(map, nx, ny) == "fence":
			continue
		var a: Vector3
		var b: Vector3
		if n.y != 0:
			var z: float = float(ty + 1) if n.y > 0 else float(ty)
			a = Vector3(tx, 0.0, z)
			b = Vector3(tx + 1, 0.0, z)
		else:
			var x: float = float(tx + 1) if n.x > 0 else float(tx)
			a = Vector3(x, 0.0, ty)
			b = Vector3(x, 0.0, ty + 1)
		var rise: Vector3 = Vector3(0.0, top_m, 0.0)
		batch.quad(a, b, b + rise, a + rise, Vector3(n.x, 0.0, n.y), Vector2(0.0, v_lo), Vector2(1.0, v_lo), Vector2(1.0, v_hi), Vector2(0.0, v_hi), Color.WHITE)


# --- trim -----------------------------------------------------------------------------------------

## The trim boxes of one generic window: on each face that meets open ground, a cast sill ledge under the
## aperture, a timber head over it, and a timber jamb on the face of the wall beside it where the run
## goes on as wall. Nothing stands in the aperture (1.00 to 2.10 m over the window's own tile): the sim
## leaves it open. Colours are linear, as the district's trim mesh reads them.
static func window_trim(map: Variant, tx: int, ty: int) -> Array:
	var out: Array = []
	var axis_x: bool = _axis_x(map, tx, ty)
	var sill: Color = SILL_COLOUR.srgb_to_linear()
	var frame: Color = FRAME_COLOUR.srgb_to_linear()
	for side in ([Vector2i(0, -1), Vector2i(0, 1)] if axis_x else [Vector2i(-1, 0), Vector2i(1, 0)]):
		var n: Vector2i = side as Vector2i
		if SimTileMap.is_solid(map, tx + n.x, ty + n.y) or SimTileMap.tile_at(map, tx + n.x, ty + n.y) == SimTileMap.Tile.Water:
			continue
		var sign_b: float = float(n.y if axis_x else n.x)
		var face: float = 1.0 if sign_b > 0.0 else 0.0
		out.append(_trim_box(tx, ty, axis_x, 0.0, 1.0, face, face + sign_b * SILL_PROUD_M, WINDOW_SILL_M - SILL_HEIGHT_M, WINDOW_SILL_M, sill))
		out.append(_trim_box(tx, ty, axis_x, 0.0, 1.0, face, face + sign_b * FRAME_PROUD_M, WINDOW_HEAD_M, WINDOW_HEAD_M + FRAME_WIDTH_M, frame))
		for along in [-1, 1]:
			var ax: int = tx + (int(along) if axis_x else 0)
			var ay: int = ty + (0 if axis_x else int(along))
			if ax < 0 or ay < 0 or ax >= int(map.w) or ay >= int(map.h):
				continue
			if SimSpace.profile_key(map, ax, ay) != "wall":
				continue
			var a0: float = -FRAME_WIDTH_M if int(along) < 0 else 1.0
			out.append(_trim_box(tx, ty, axis_x, a0, a0 + FRAME_WIDTH_M, face, face + sign_b * FRAME_PROUD_M, WINDOW_SILL_M - SILL_HEIGHT_M, WINDOW_HEAD_M + FRAME_WIDTH_M, frame))
	return out


# One trim box in a tile's own frame: `a` along the run, `b` through the wall, `h` up.
static func _trim_box(tx: int, ty: int, axis_x: bool, a0: float, a1: float, b0: float, b1: float, h0: float, h1: float, colour: Color) -> Dictionary:
	var lo_b: float = minf(b0, b1)
	var hi_b: float = maxf(b0, b1)
	if axis_x:
		return {"min": Vector3(float(tx) + a0, h0, float(ty) + lo_b), "max": Vector3(float(tx) + a1, h1, float(ty) + hi_b), "colour": colour}
	return {"min": Vector3(float(tx) + lo_b, h0, float(ty) + a0), "max": Vector3(float(tx) + hi_b, h1, float(ty) + a1), "colour": colour}


# A stable choice from the scene's seed salt and a tile: placement only, never a sim stream.
static func _hash(salt: int, tx: int, ty: int) -> int:
	var h: int = (salt * 73856093) ^ (tx * 19349663) ^ (ty * 83492791)
	h = h & 0x7fffffff
	h = h ^ (h >> 13)
	return h & 0x7fffffff
