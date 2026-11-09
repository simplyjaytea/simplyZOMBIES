extends Node3D
# The first-person street dressing's drawing node: resolves the manifest once, places the props from the sim's own
# tile classes (street_dressing.gd), and draws them under the district. Presentation only: no collision, no entity,
# nothing written to the sim, nothing saved. A missing manifest draws nothing and the district is as it was.

const StreetDressing = preload("res://presentation/first_person/street_dressing.gd")

const BOX_FALLBACK_SALT: int = 17
const WIRE_COLOUR: Color = Color(0.12, 0.12, 0.13)

# The placements and wire spans of the last build, for the gates and the report.
var placed: Array = []
var wire_spans: Array = []


# Clears any earlier build, then places the props for `map_ref` (a sim map) with `seed_val`, from the manifest at
# `manifest_path`. An empty manifest leaves the node with no children.
func build(map_ref: Variant, seed_val: int, manifest_path: String) -> void:
	clear()
	var entries: Array = StreetDressing.load_manifest(manifest_path)
	if entries.is_empty() or map_ref == null:
		return
	placed = StreetDressing.placements(map_ref, seed_val, entries)
	wire_spans = StreetDressing.wire_spans(placed)
	for p in placed:
		add_child(_prop_node(p as Dictionary))
	if not wire_spans.is_empty():
		add_child(_wire_node())


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	placed = []
	wire_spans = []


func prop_count() -> int:
	var n: int = 0
	for child in get_children():
		if child is MeshInstance3D and String(child.name).begins_with("Prop_"):
			n += 1
	return n


# One prop: a box of the manifest's measured size, standing on its base point. The model's own GLB replaces the box
# when the manifest names one that loads; until then the box is the honest stand-in.
func _prop_node(p: Dictionary) -> Node3D:
	var size: Vector3 = p["size"] as Vector3
	var holder: MeshInstance3D = MeshInstance3D.new()
	holder.name = "Prop_%s_%d_%d" % [String(p["id"]), int(p["tx"]), int(p["ty"])]
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	holder.mesh = box
	holder.material_override = _box_material(String(p["id"]))
	holder.position = (p["pos"] as Vector3) + Vector3(0.0, size.y * 0.5, 0.0)
	holder.rotation = Vector3(0.0, float(p["yaw"]), 0.0)
	return holder


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
