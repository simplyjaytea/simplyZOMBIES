extends Node3D
# Data-driven architectural finishes. The sim's building records select GLBs; this view only reads
# them. Each template has one merged spatial mesh and one merged finish mesh, with glass as a second
# surface where needed. Per-instance tint is a stable function of the district seed, template id and
# stamped position, never a runtime random draw.

const Assets = preload("res://presentation/first_person/assets.gd")
const MANIFEST_PATH: String = "res://assets/first_person/buildings.manifest.json"

var instances: Array = []
var manifest: Dictionary = {}


func build(map: Variant, salt: int) -> void:
	instances.clear()
	manifest = read_manifest()
	var entries: Dictionary = {}
	for entry_v in manifest.get("models", []) as Array:
		var entry: Dictionary = entry_v as Dictionary
		entries[String((entry.get("match", {}) as Dictionary).get("id", ""))] = entry
	var sources: Dictionary = {}
	for record_v in map.buildings as Array:
		var record: Dictionary = record_v as Dictionary
		var id: String = String(record.get("id", ""))
		var entry: Dictionary = entries.get(id, {}) as Dictionary
		if entry.is_empty():
			continue
		if not sources.has(id):
			var loaded: Dictionary = Assets.load_model(String(entry.get("glb", "")))
			var source: Node3D = loaded["node"] as Node3D
			if source == null:
				continue
			sources[id] = source
		var node: Node3D = (sources[id] as Node3D).duplicate() as Node3D
		node.name = "Finish_" + id.replace("building.", "").replace(".", "_")
		node.position = Vector3(float(int(record["x"])), 0.0, float(int(record["y"])))
		add_child(node)
		var variants: Array = entry.get("variation", ["#ffffff"]) as Array
		var variant: int = placement_hash(salt, record) % variants.size()
		_tint_opaque(node, Color.from_string(String(variants[variant]), Color.WHITE))
		instances.append({"building": record, "entry": entry, "node": node, "variant": variant})
	for source_v in sources.values():
		(source_v as Node).free()


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
