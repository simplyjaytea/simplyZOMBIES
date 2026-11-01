extends Node3D
# Placeholder furniture for the district's sim containers: one labelled box per `searchable` entity,
# at the position the sim gave it. Presentation only -- this file reads `position` and `searchable`
# and writes neither, and it owns no physics body or collision shape (the gate scans for those).
#
# The box is deliberately a placeholder: the art pass will replace the mesh, and the label is the
# sim's own `kind` word ("cupboard", "tool chest", "wardrobe") so the thing you walk up to is named
# in the same words the HUD and the transfer window use. Contents are not drawn here: what is in a
# container is the inventory panel's business, and drawing it twice would be a second truth.
#
# Nothing is hidden by vision or by `searched`: a container is furniture, and the 3D walls already
# occlude it from the eye. A body view is hidden when the sim cannot see it because a body can move;
# a cupboard does not.

const SimContainers = preload("res://sim/modules/containers.gd")
const Assets = preload("res://presentation/first_person/assets.gd")

const BOX_WIDTH_M: float = 0.90
const BOX_HEIGHT_M: float = 1.00
const BOX_DEPTH_M: float = 0.55
# Where the kind label floats, just over the box's top edge.
const LABEL_HEIGHT_M: float = 1.22
# The kit's shelf is 1.85 m to the top shelf, so its label floats above that instead.
const SHELF_LABEL_HEIGHT_M: float = 2.05
# Which sim kind words the kit's open shelf fits: `shelf` itself, and a qualified shelf such as the
# district's `stockroom shelf`. A cupboard, wardrobe, tool chest, larder or locker is a closed thing,
# and an open shelf with no doors would describe it wrongly; those keep the labelled box until the
# kit has a closed cabinet.
const SHELF_KINDS: Array[String] = ["shelf"]

var _entities: Array[int] = []
var _nodes: Dictionary = {}
# How many containers the kit's shelf drew instead of the box. The KIT lane and the report read it.
var shelf_models: int = 0


## Stands one box per sim container. Safe to call again: the old nodes are released first.
func build(world: Variant) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_entities.clear()
	_nodes.clear()
	shelf_models = 0
	if world == null:
		return
	for entity in world.components.query(["searchable", "position"]):
		var ent: int = int(entity)
		var pos: Variant = world.components.get_component(ent, "position")
		if not (pos is Dictionary):
			continue
		var state: Variant = world.components.get_component(ent, "searchable")
		var kind: String = String((state as Dictionary).get("kind", SimContainers.DEFAULT_KIND)) if state is Dictionary else SimContainers.DEFAULT_KIND
		var node: Node3D = Node3D.new()
		node.name = "Container%d" % ent
		node.position = Vector3(float((pos as Dictionary)["x"]), 0.0, float((pos as Dictionary)["y"]))
		var shelf: Node3D = _shelf_model(kind)
		if shelf != null:
			node.add_child(shelf)
			node.add_child(_label(kind, SHELF_LABEL_HEIGHT_M))
			shelf_models += 1
		else:
			node.add_child(_box())
			node.add_child(_label(kind, LABEL_HEIGHT_M))
		add_child(node)
		_entities.append(ent)
		_nodes[ent] = node


func count() -> int:
	return _entities.size()


func entities() -> Array[int]:
	return _entities


func node_for(entity: int) -> Node3D:
	return _nodes.get(entity, null) as Node3D


## The sim's kind word for a container, as the label over it reads it. "" before `build`.
func label_for(entity: int) -> String:
	var node: Node3D = node_for(entity)
	if node == null:
		return ""
	var label: Label3D = node.get_node_or_null("Label") as Label3D
	return label.text if label != null else ""


func _box() -> MeshInstance3D:
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "Placeholder"
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(BOX_WIDTH_M, BOX_HEIGHT_M, BOX_DEPTH_M)
	mesh.mesh = box
	mesh.position = Vector3(0.0, BOX_HEIGHT_M * 0.5, 0.0)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.58, 0.50, 0.36)
	material.roughness = 1.0
	mesh.material_override = material
	return mesh


## The kit's shelf for a shelf-kind container, or null for a box. The shelf's authored origin is its
## floor centre, so it stands at the container's sim position with no offset.
func _shelf_model(kind: String) -> Node3D:
	if not _is_shelf(kind):
		return null
	var model: Node3D = Assets.load_model(Assets.SHELF)["node"] as Node3D
	if model == null:
		return null
	model.name = "ShelfModel"
	return model


## `shelf`, or a qualified shelf such as `stockroom shelf`. The exact word list is above.
func _is_shelf(kind: String) -> bool:
	if SHELF_KINDS.has(kind):
		return true
	return kind.ends_with(" shelf")


func _label(kind: String, height: float) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = "Label"
	label.text = kind
	label.position = Vector3(0.0, height, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.pixel_size = 0.004
	label.modulate = Color(0.96, 0.92, 0.72)
	label.outline_size = 12
	label.outline_modulate = Color(0.05, 0.05, 0.05, 0.85)
	return label
