extends Node3D
# Data-driven architectural finishes. The sim's building records select GLBs; this view only reads
# them and the stamped map. Per-instance tint is a stable function of the district seed, template id
# and stamped position, never a runtime random draw.
#
# Each GLB has two merged meshes that every instance draws (`spatial_bands`, the walls that are
# always walls, and `finish`), and one small named node per tile whose drawing depends on the sim:
#
#   <slug>-wall-X-Y         a wall worldgen may open into a window, drawn while the tile is a wall
#   <slug>-window-X-Y       a window's sill, lintel, casing and glazing, drawn while it is a window
#   <slug>-jamb-X-Y-SIDE    wall X,Y's face into its neighbour, drawn while X,Y is a wall and the
#                           neighbour is a window
#
# X,Y are template tiles. Worldgen's occluder pass opens template walls into windows after the stamp
# (`SimWorldgen._dress_occluders`), so the picture follows the stamped map, not the template (docs/41,
# rule 1: the picture is the sim). The pieces an instance draws are merged into one `Openings` mesh
# per instance, so the district keeps a few draws per building. `drawn` records what each footprint
# tile was drawn as; `district_view.gd` drops its band boxes only where that matches the sim, and
# `godot:check:fp_geometry` FINISHES casts rays through every window of a real district.

const Assets = preload("res://presentation/first_person/assets.gd")
const SimSpace = preload("res://sim/space/space.gd")
const MANIFEST_PATH: String = "res://assets/first_person/buildings.manifest.json"

var instances: Array = []
var manifest: Dictionary = {}
# Map tile (Vector2i) -> "wall" or "window": what a finished building drew there.
var drawn: Dictionary = {}
# The gate's planted error only: map tiles whose wall piece is drawn whatever the sim says. Empty in
# play; `godot:check:fp_geometry` sets one to prove its aperture rays refuse a wall over a window.
var force_wall: Dictionary = {}

var _sources: Dictionary = {}
var _merged: Dictionary = {}


func build(map: Variant, salt: int) -> void:
	instances.clear()
	drawn.clear()
	_merged.clear()
	manifest = read_manifest()
	var entries: Dictionary = {}
	for entry_v in manifest.get("models", []) as Array:
		var entry: Dictionary = entry_v as Dictionary
		entries[String((entry.get("match", {}) as Dictionary).get("id", ""))] = entry
	for record_v in map.buildings as Array:
		var record: Dictionary = record_v as Dictionary
		var id: String = String(record.get("id", ""))
		var entry: Dictionary = entries.get(id, {}) as Dictionary
		if entry.is_empty():
			continue
		var source: Dictionary = _source(id, entry)
		if source.is_empty():
			continue
		var origin: Vector2i = Vector2i(int(record["x"]), int(record["y"]))
		var node: Node3D = (source["node"] as Node3D).duplicate() as Node3D
		node.name = "Finish_" + id.replace("building.", "").replace(".", "_")
		node.position = Vector3(float(origin.x), 0.0, float(origin.y))
		var chosen: Array = []
		var kinds: Dictionary = {}
		for tile_v in source["fixed"] as Array:
			kinds[tile_v as Vector2i] = "wall"
		for piece_v in source["pieces"] as Array:
			var piece: Dictionary = piece_v as Dictionary
			if piece_drawn(map, origin, piece, source, force_wall):
				chosen.append(piece)
				if String(piece["kind"]) != "jamb":
					kinds[piece["tile"] as Vector2i] = String(piece["kind"])
		var openings: Mesh = _openings(id, chosen)
		if openings != null:
			var instance: MeshInstance3D = MeshInstance3D.new()
			instance.name = "Openings"
			instance.mesh = openings
			node.add_child(instance)
		add_child(node)
		var variants: Array = entry.get("variation", ["#ffffff"]) as Array
		var variant: int = placement_hash(salt, record) % variants.size()
		_tint_opaque(node, Color.from_string(String(variants[variant]), Color.WHITE))
		for local_v in kinds:
			drawn[origin + (local_v as Vector2i)] = kinds[local_v]
		instances.append({"building": record, "entry": entry, "node": node, "variant": variant, "pieces": chosen.size()})
	for source_v in _sources.values():
		((source_v as Dictionary)["node"] as Node).free()
	_sources.clear()


## Whether one per-tile piece is drawn for a building stamped at `origin`. A tile the GLB always
## draws as a wall (`fixed`) counts as a wall for a jamb. `planted` is the gate's force_wall.
static func piece_drawn(map: Variant, origin: Vector2i, piece: Dictionary, source: Dictionary, planted: Dictionary = {}) -> bool:
	var tile: Vector2i = piece["tile"] as Vector2i
	match String(piece["kind"]):
		"wall":
			return _kind(map, origin, tile, source, planted) == "wall"
		"window":
			return _kind(map, origin, tile, source, planted) == "window"
		"jamb":
			return _kind(map, origin, tile, source, planted) == "wall" and _kind(map, origin, piece["other"] as Vector2i, source, planted) == "window"
	return false


static func _kind(map: Variant, origin: Vector2i, tile: Vector2i, source: Dictionary, planted: Dictionary) -> String:
	var at: Vector2i = origin + tile
	if planted.has(at) and (source["walls"] as Dictionary).has(tile):
		return "wall"
	if (source["fixed_set"] as Dictionary).has(tile):
		return "wall"
	return SimSpace.profile_key(map, at.x, at.y)


# The loaded GLB with its per-tile nodes taken out: {node, pieces, fixed, fixed_set, walls}. `fixed`
# is every template tile the merged `spatial_bands` mesh caps at the wall top, read from the mesh
# itself, so what counts as an always-wall is what is drawn.
func _source(id: String, entry: Dictionary) -> Dictionary:
	if _sources.has(id):
		return _sources[id] as Dictionary
	var loaded: Dictionary = Assets.load_model(String(entry.get("glb", "")))
	var node: Node3D = loaded["node"] as Node3D
	if node == null:
		return {}
	var pieces: Array = []
	var walls: Dictionary = {}
	for child in mesh_nodes(node):
		var parsed: Dictionary = parse_piece(String(child.name))
		if parsed.is_empty():
			continue
		parsed["mesh"] = (child as MeshInstance3D).mesh
		pieces.append(parsed)
		if String(parsed["kind"]) == "wall":
			walls[parsed["tile"]] = true
		child.get_parent().remove_child(child)
		child.free()
	var fixed: Array = capped_tiles(node, "spatial_bands")
	var fixed_set: Dictionary = {}
	for tile_v in fixed:
		fixed_set[tile_v] = true
	var source: Dictionary = {"node": node, "pieces": pieces, "fixed": fixed, "fixed_set": fixed_set, "walls": walls}
	_sources[id] = source
	return source


## A per-tile node's name read back: {kind, tile, other}, or {} for a merged mesh. Names are
## `<slug>-<kind>-X-Y[-SIDE]`; the slug never holds a hyphen.
static func parse_piece(node_name: String) -> Dictionary:
	var parts: PackedStringArray = node_name.split("-")
	if parts.size() < 4:
		return {}
	var kind: String = parts[1]
	if not kind in ["wall", "window", "jamb"]:
		return {}
	var tile: Vector2i = Vector2i(int(parts[2]), int(parts[3]))
	var other: Vector2i = tile
	if kind == "jamb":
		if parts.size() < 5:
			return {}
		var offsets: Dictionary = {"north": Vector2i(0, -1), "east": Vector2i(1, 0), "south": Vector2i(0, 1), "west": Vector2i(-1, 0)}
		if not offsets.has(parts[4]):
			return {}
		other = tile + (offsets[parts[4]] as Vector2i)
	return {"kind": kind, "tile": tile, "other": other}


## The template tiles whose full top cap (y = 2.55 m, facing up) a named mesh draws.
static func capped_tiles(node: Node, prefix: String) -> Array:
	var area: Dictionary = {}
	for child in mesh_nodes(node):
		if not String(child.name).begins_with(prefix):
			continue
		var mesh: Mesh = (child as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count: int = indices.size() if not indices.is_empty() else vertices.size()
			for i in range(0, count, 3):
				var a: Vector3 = vertices[indices[i] if not indices.is_empty() else i]
				var b: Vector3 = vertices[indices[i + 1] if not indices.is_empty() else i + 1]
				var c: Vector3 = vertices[indices[i + 2] if not indices.is_empty() else i + 2]
				if absf(a.y - 2.55) > 0.001 or absf(b.y - 2.55) > 0.001 or absf(c.y - 2.55) > 0.001:
					continue
				var centre: Vector3 = (a + b + c) / 3.0
				var tile: Vector2i = Vector2i(floori(centre.x), floori(centre.z))
				area[tile] = float(area.get(tile, 0.0)) + (b - a).cross(c - a).length() * 0.5
	var out: Array = []
	for tile_v in area:
		if float(area[tile_v]) >= 0.99:
			out.append(tile_v)
	out.sort()
	return out


static func mesh_nodes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for child in node.get_children():
		out.append_array(mesh_nodes(child))
	return out


# One merged mesh of the chosen pieces, a surface per material. Instances of one template that open
# the same tiles share it.
func _openings(id: String, chosen: Array) -> Mesh:
	if chosen.is_empty():
		return null
	var names: PackedStringArray = []
	for piece_v in chosen:
		var piece: Dictionary = piece_v as Dictionary
		names.append("%s%s%s" % [piece["kind"], piece["tile"], piece["other"]])
	var key: String = id + "|" + ",".join(names)
	if _merged.has(key):
		return _merged[key] as Mesh
	var tools: Dictionary = {}
	var order: Array = []
	for piece_v in chosen:
		var mesh: Mesh = (piece_v as Dictionary)["mesh"] as Mesh
		for s in mesh.get_surface_count():
			var material: Material = mesh.surface_get_material(s)
			if not tools.has(material):
				var st: SurfaceTool = SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[material] = st
				order.append(material)
			(tools[material] as SurfaceTool).append_from(mesh, s, Transform3D.IDENTITY)
	var merged: ArrayMesh = ArrayMesh.new()
	for material in order:
		(tools[material] as SurfaceTool).commit(merged)
		merged.surface_set_material(merged.get_surface_count() - 1, material)
	_merged[key] = merged
	return merged


static func read_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	return parsed as Dictionary if parsed is Dictionary else {}


static func entry_for(id: String) -> Dictionary:
	for entry_v in read_manifest().get("models", []) as Array:
		var entry: Dictionary = entry_v as Dictionary
		if String((entry.get("match", {}) as Dictionary).get("id", "")) == id:
			return entry
	return {}


static func placement_hash(salt: int, record: Dictionary) -> int:
	var h: int = (salt * 73856093) ^ String(record.get("id", "")).hash()
	h = h ^ (int(record.get("x", 0)) * 19349663) ^ (int(record.get("y", 0)) * 83492791)
	h = h & 0x7fffffff
	h = h ^ (h >> 13)
	return h & 0x7fffffff


func _tint_opaque(node: Node, colour: Color) -> void:
	if node is MeshInstance3D:
		var instance: MeshInstance3D = node as MeshInstance3D
		if instance.mesh != null:
			for surface in instance.mesh.get_surface_count():
				var material: Material = instance.get_active_material(surface)
				if material is StandardMaterial3D and (material as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
					var tinted: StandardMaterial3D = (material as StandardMaterial3D).duplicate() as StandardMaterial3D
					tinted.albedo_color = colour
					instance.set_surface_override_material(surface, tinted)
	for child in node.get_children():
		_tint_opaque(child, colour)
