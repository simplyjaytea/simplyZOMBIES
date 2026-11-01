extends Node3D
# The gunsmith's bench as a physical place: one node per sim `workbench`, at the sim's position.
# The furniture is the starter kit's desk model with a vice and a tool tray as code placeholders on
# top (a bench model is a later art piece); the label is the sim's own kind word, "gunsmith bench",
# so the player walks up to the thing the bench screen belongs to. Presentation only -- nothing here
# writes a component, and the bench blocks nothing (the sim's E rung decides what it is for).

const Assets = preload("res://presentation/first_person/assets.gd")

const DESK_SIZE: Vector3 = Vector3(Assets.DESK_WIDTH_M, Assets.DESK_HEIGHT_M, Assets.DESK_DEPTH_M)
# The vice and the tray sit on the desk top, toward its front edge.
const VICE_SIZE: Vector3 = Vector3(0.16, 0.14, 0.12)
const TRAY_SIZE: Vector3 = Vector3(0.34, 0.04, 0.16)
const LABEL_HEIGHT_M: float = 1.05
const BENCH_KIND: String = "gunsmith"

var _nodes: Dictionary = {}
var _key: String = ""


## Brings the drawn benches in line with the sim's workbenches. Cheap between builds: the set and
## each position are read once per tick and the nodes are rebuilt only when that changes.
func refresh(world: Variant) -> void:
	if world == null:
		return
	var found: Array[Dictionary] = []
	for entity in world.components.query(["workbench", "position"]):
		var ent: int = int(entity)
		var pos: Variant = world.components.get_component(ent, "position")
		var state: Variant = world.components.get_component(ent, "workbench")
		if not (pos is Dictionary) or not (state is Dictionary):
			continue
		var kind: String = String((state as Dictionary).get("kind", ""))
		if kind != BENCH_KIND:
			continue
		found.append({
			"entity": ent,
			"x": float((pos as Dictionary)["x"]),
			"y": float((pos as Dictionary)["y"]),
			"kind": kind,
		})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["entity"]) < int(b["entity"]))
	var key: String = ""
	for row in found:
		key += "%d:%s:%.3f:%.3f;" % [int(row["entity"]), String(row["kind"]), float(row["x"]), float(row["y"])]
	if key == _key:
		return
	_key = key
	for ent in _nodes.keys():
		if not _has(found, int(ent)):
			var gone: Node3D = _nodes[ent] as Node3D
			_nodes.erase(ent)
			if gone != null:
				gone.queue_free()
	for row in found:
		var ent: int = int(row["entity"])
		var node: Node3D = _nodes.get(ent) as Node3D
		if node == null:
			node = _make(row)
			_nodes[ent] = node
			add_child(node)
		node.position = Vector3(float(row["x"]), 0.0, float(row["y"]))


func node_for(entity: int) -> Node3D:
	return _nodes.get(entity, null) as Node3D


func _has(rows: Array[Dictionary], entity: int) -> bool:
	for row in rows:
		if int(row["entity"]) == entity:
			return true
	return false


func _make(row: Dictionary) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = "Bench%d" % int(row["entity"])
	var model: Node3D = Assets.load_model(Assets.DESK)["node"] as Node3D
	if model != null:
		model.name = "BenchDesk"
		node.add_child(model)
	else:
		var desk: MeshInstance3D = _box("BenchPlaceholder", DESK_SIZE, Color(0.35, 0.27, 0.19))
		desk.position = Vector3(0.0, DESK_SIZE.y * 0.5, 0.0)
		node.add_child(desk)
	# The vice and the tool tray: code placeholders until the bench art lands.
	var vice: MeshInstance3D = _box("Vice", VICE_SIZE, Color(0.30, 0.32, 0.34))
	vice.position = Vector3(-0.34, Assets.DESK_HEIGHT_M + VICE_SIZE.y * 0.5, 0.12)
	node.add_child(vice)
	var tray: MeshInstance3D = _box("ToolTray", TRAY_SIZE, Color(0.26, 0.27, 0.28))
	tray.position = Vector3(0.24, Assets.DESK_HEIGHT_M + TRAY_SIZE.y * 0.5, 0.10)
	node.add_child(tray)
	node.add_child(_label(String(row["kind"])))
	return node


func _label(kind: String) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = "Label"
	label.text = "gunsmith bench" if kind == BENCH_KIND else kind
	label.position = Vector3(0.0, LABEL_HEIGHT_M, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.pixel_size = 0.004
	label.modulate = Color(0.96, 0.92, 0.72)
	label.outline_size = 12
	label.outline_modulate = Color(0.05, 0.05, 0.05, 0.85)
	return label


func _box(node_name: String, size: Vector3, colour: Color) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.9
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	return instance
