extends Node3D
# The first-person street dressing's drawing node: resolves the manifest once, places the props from the sim's own
# tile classes (street_dressing.gd), and draws them under the district. Presentation only: no collision, no entity,
# nothing written to the sim, nothing saved. A missing manifest draws nothing and the district is as it was.

const StreetDressing = preload("res://presentation/first_person/street_dressing.gd")
const Assets = preload("res://presentation/first_person/assets.gd")

const BOX_FALLBACK_SALT: int = 17
# The mix: weight and cap per prop id (presentation data; absent means every id weight 1, no caps).
const MIX_PATH: String = "res://presentation/first_person/street_dressing_mix.json"
# Plant (gate): when true the loader ignores every GLB path and the box shows instead; the DRESSING lane must go red.
const PLANT_IGNORE_GLB: bool = false
const WIRE_COLOUR: Color = Color(0.12, 0.12, 0.13)

# The placements and wire spans of the last build, for the gates and the report.
var placed: Array = []
var wire_spans: Array = []
# GLB path -> loaded model root (a template, duplicated per prop), or null when the file is absent or unreadable.
var _models: Dictionary = {}


# Clears any earlier build, then places the props for `map_ref` (a sim map) with `seed_val`, from the manifest at
# `manifest_path`. An empty manifest leaves the node with no children.
func build(map_ref: Variant, seed_val: int, manifest_path: String) -> void:
	clear()
	var entries: Array = StreetDressing.load_manifest(manifest_path)
	if entries.is_empty() or map_ref == null:
		return
	placed = StreetDressing.placements(map_ref, seed_val, entries, StreetDressing.load_mix(MIX_PATH))
	wire_spans = StreetDressing.wire_spans(placed)
	for p in placed:
		add_child(_prop_node(p as Dictionary))
	if not wire_spans.is_empty():
		add_child(_wire_node())


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	for path in _models.keys():
		var template: Variant = _models[path]
		if template is Node:
			(template as Node).free()
	_models = {}
	placed = []
	wire_spans = []


func prop_count() -> int:
	var n: int = 0
	for child in get_children():
		if String(child.name).begins_with("Prop_"):
			n += 1
	return n


# One prop: the entry's own GLB, instanced at its base point and yaw, when the manifest names a file that loads.
# A wall_back_centre model is placed by its back face: the wall-facing point, half its depth past the centre.
# Otherwise (no GLB named, or the file absent or unreadable) the prop is a box of the manifest's measured size.
func _prop_node(p: Dictionary) -> Node3D:
	var size: Vector3 = p["size"] as Vector3
	var model: Node3D = _model_for(String(p.get("glb", "")))
	if model != null:
		var holder: Node3D = Node3D.new()
		holder.name = "Prop_%s_%d_%d" % [String(p["id"]), int(p["tx"]), int(p["ty"])]
		holder.add_child(model.duplicate())
		holder.position = _anchor_position(p)
		holder.rotation = Vector3(0.0, float(p["yaw"]), 0.0)
		return holder
	var box_holder: MeshInstance3D = MeshInstance3D.new()
	box_holder.name = "Prop_%s_%d_%d" % [String(p["id"]), int(p["tx"]), int(p["ty"])]
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	box_holder.mesh = box
	box_holder.material_override = _box_material(String(p["id"]))
	box_holder.position = (p["pos"] as Vector3) + Vector3(0.0, size.y * 0.5, 0.0)
	box_holder.rotation = Vector3(0.0, float(p["yaw"]), 0.0)
	return box_holder


# The point a GLB is instanced at: the base point for floor_centre; the wall-facing back for wall_back_centre.
func _anchor_position(p: Dictionary) -> Vector3:
	var base: Vector3 = p["pos"] as Vector3
	if String(p.get("origin", "")) != "wall_back_centre":
		return base
	var wd: Vector2 = p.get("wall_dir", Vector2.ZERO) as Vector2
	var size: Vector3 = p["size"] as Vector3
	return base + Vector3(wd.x, 0.0, wd.y) * (size.z * 0.5)


# The loaded model for a GLB path, cached per path. Null for no path, an absent or unreadable file, or the plant.
func _model_for(path: String) -> Node3D:
	if PLANT_IGNORE_GLB or path == "":
		return null
	if not _models.has(path):
		var loaded: Dictionary = Assets.load_model(path)
		_models[path] = loaded["node"]
	var found: Variant = _models[path]
	return found as Node3D


func _box_material(id: String) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	var h: int = absi(id.hash() + BOX_FALLBACK_SALT) % 1000
	mat.albedo_color = Color(0.35 + float(h % 7) * 0.05, 0.36 + float((h / 7) % 6) * 0.05, 0.38 + float((h / 42) % 5) * 0.05)
	return mat


# All wire spans as one line mesh, one strip per span.
func _wire_node() -> MeshInstance3D:
	var holder: MeshInstance3D = MeshInstance3D.new()
	holder.name = "Wires"
	var im: ImmediateMesh = ImmediateMesh.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = WIRE_COLOUR
	for span in wire_spans:
		var pts: PackedVector3Array = (span as Dictionary)["points"] as PackedVector3Array
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
		for pt in pts:
			im.surface_add_vertex(pt)
		im.surface_end()
	holder.mesh = im
	return holder
