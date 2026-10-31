extends Node3D
# The physical desk and ledger that stand near the safe spawn. They are presentation only: the sim
# does not know they exist and remains the one authority on collision, which is why there is no
# StaticBody3D or CollisionShape3D under here. Walking through the desk is the honest placeholder
# until inventory and physical props are their own slice.
#
# A model at `res://assets/first_person/desk.glb` or `ledger.glb` is used when it exists. Otherwise
# a box of the published size stands in its place, so this branch renders something on day one and
# the art pass is a drop-in, not a code change.

const Assets = preload("res://presentation/first_person/assets.gd")

const DESK_PLACEHOLDER_SIZE: Vector3 = Vector3(1.40, Assets.DESK_HEIGHT_M, 0.70)
const LEDGER_PLACEHOLDER_SIZE: Vector3 = Vector3(Assets.LEDGER_WIDTH_M, Assets.LEDGER_THICKNESS_M, Assets.LEDGER_DEPTH_M)

const DESK_COLOUR: Color = Color(0.35, 0.27, 0.19)
const LEDGER_COLOUR: Color = Color(0.72, 0.68, 0.55)
const INK_COLOUR: Color = Color(0.18, 0.16, 0.14)

var ledger_sim: Vector2 = Vector2.ZERO
var desk_height: float = Assets.DESK_HEIGHT_M
var used_models: bool = false


## Builds the desk at `desk_sim` (sim x/y, in metres) and the ledger on its top. Safe to call once;
## the scene builds a fresh prop view per boot.
func build(desk_sim: Vector2) -> void:
	ledger_sim = desk_sim
	position = Vector3(desk_sim.x, 0.0, desk_sim.y)
	_build_desk()
	_build_ledger()


func _build_desk() -> void:
	var packed: PackedScene = Assets.model(Assets.DESK)
	if packed != null:
		var model: Node3D = packed.instantiate() as Node3D
		if model != null:
			model.name = "DeskModel"
			add_child(model)
			used_models = true
			return
	var box: MeshInstance3D = _box("DeskPlaceholder", DESK_PLACEHOLDER_SIZE, DESK_COLOUR)
	box.position = Vector3(0.0, DESK_PLACEHOLDER_SIZE.y * 0.5, 0.0)


func _build_ledger() -> void:
	var packed: PackedScene = Assets.model(Assets.LEDGER)
	if packed != null:
		var model: Node3D = packed.instantiate() as Node3D
		if model != null:
			model.name = "LedgerModel"
			# Authored origin is the bottom centre, so the desk top is the whole offset.
			model.position = Vector3(0.0, desk_height, 0.0)
			add_child(model)
			used_models = true
			return
	var book: MeshInstance3D = _box("LedgerPlaceholder", LEDGER_PLACEHOLDER_SIZE, LEDGER_COLOUR)
	book.position = Vector3(0.0, desk_height + LEDGER_PLACEHOLDER_SIZE.y * 0.5, 0.0)
	# A dark spine line, so the ledger reads as a book rather than a white slab even at this size.
	var spine: MeshInstance3D = _box("LedgerSpine", Vector3(0.045, LEDGER_PLACEHOLDER_SIZE.y + 0.006, LEDGER_PLACEHOLDER_SIZE.z), INK_COLOUR)
	spine.position = Vector3(-LEDGER_PLACEHOLDER_SIZE.x * 0.5 + 0.022, book.position.y, 0.0)


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
	add_child(instance)
	return instance


## The point a look and an E press are judged against: the top of the ledger, in Godot space.
func ledger_world_point() -> Vector3:
	return Vector3(ledger_sim.x, desk_height + Assets.LEDGER_THICKNESS_M, ledger_sim.y)
