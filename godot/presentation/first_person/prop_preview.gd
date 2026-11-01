extends Node3D
# A render-only shelf for the five optional first-person GLBs. It exists so every export in
# `res://assets/first_person/` has a real reader when the art lands, without pretending any of it
# affects gameplay: the props are meshes, there is no collision body, and no sim entity is created.
# Desk and ledger are already read by the playable scene; this scene adds the shelf, barricade and
# wall module, and shows the whole set together.
#
# Launch it with `npm run godot:run:first_person:props`. A missing GLB becomes a box of the
# published size, so the preview is useful before the art merges as well as after.

const Assets = preload("res://presentation/first_person/assets.gd")
const Chrome = preload("res://ui/chrome.gd")

const FLOOR_COLOUR: Color = Color(0.16, 0.17, 0.17)
const DESK_COLOUR: Color = Color(0.35, 0.27, 0.19)
const LEDGER_COLOUR: Color = Color(0.72, 0.68, 0.55)
const SHELF_COLOUR: Color = Color(0.38, 0.30, 0.22)
const BARRICADE_COLOUR: Color = Color(0.34, 0.36, 0.34)
const WALL_COLOUR: Color = Color(0.42, 0.40, 0.36)
const INK_COLOUR: Color = Color(0.18, 0.16, 0.14)


func _ready() -> void:
	_build_environment()
	_build_floor()
	_build_camera()
	# Desk and ledger together, then the three props that the playable scene does not place yet.
	_add_prop(Assets.DESK, Vector3(Assets.DESK_WIDTH_M, Assets.DESK_HEIGHT_M, Assets.DESK_DEPTH_M), Vector3(-3.1, 0.0, 0.0), DESK_COLOUR, "desk")
	_add_prop(Assets.LEDGER, Vector3(Assets.LEDGER_WIDTH_M, Assets.LEDGER_THICKNESS_M, Assets.LEDGER_DEPTH_M), Vector3(-3.1, Assets.DESK_HEIGHT_M, 0.0), LEDGER_COLOUR, "ledger", true, 0.55)
	_add_prop(Assets.SHELF, Assets.SHELF_SIZE, Vector3(-0.8, 0.0, 0.0), SHELF_COLOUR, "shelf")
	_add_prop(Assets.BARRICADE, Assets.BARRICADE_SIZE, Vector3(1.2, 0.0, 0.0), BARRICADE_COLOUR, "barricade")
	_add_prop(Assets.WALL_MODULE, Assets.WALL_MODULE_SIZE, Vector3(3.0, 0.0, 0.0), WALL_COLOUR, "wall module")
	_label("FIRST-PERSON PROP PREVIEW - RENDER ONLY", Vector3(0.0, 3.55, 0.0), 50)
	_label("A missing GLB is a box of the published size. No collision, no gameplay.", Vector3(0.0, 3.15, 0.0), 30)


func _build_environment() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.07, 0.08, 0.09)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.64, 0.66, 0.70)
	environment.ambient_light_energy = 0.8
	var holder: WorldEnvironment = WorldEnvironment.new()
	holder.environment = environment
	add_child(holder)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = false
	add_child(sun)


func _build_floor() -> void:
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(12.0, 6.0)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = FLOOR_COLOUR
	material.roughness = 0.95
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "PreviewFloor"
	mesh.mesh = plane
	mesh.material_override = material
	add_child(mesh)


func _build_camera() -> void:
	var camera: Camera3D = Camera3D.new()
	camera.name = "PreviewCamera"
	camera.position = Vector3(0.0, 2.1, 5.8)
	camera.fov = 68.0
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, 0.0))


func _add_prop(path: String, size: Vector3, at: Vector3, colour: Color, label: String, bottom_centre: bool = false, label_lift: float = 0.25) -> void:
	var packed: PackedScene = Assets.model(path)
	var node: Node3D = null
	if packed != null:
		node = packed.instantiate() as Node3D
	if node == null:
		var box: BoxMesh = BoxMesh.new()
		box.size = size
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = colour
		material.roughness = 0.9
		var placeholder: MeshInstance3D = MeshInstance3D.new()
		placeholder.mesh = box
		placeholder.material_override = material
		node = placeholder
	var y: float = at.y + (size.y * 0.5 if not bottom_centre else 0.0)
	node.position = Vector3(at.x, y, at.z)
	add_child(node)
	var label_y: float = at.y + size.y + label_lift
	_label(label + "  %.3f x %.3f x %.3f m" % [size.x, size.y, size.z], Vector3(at.x, label_y, 0.0), 30)


func _label(text: String, at: Vector3, size: int) -> void:
	var label: Label3D = Label3D.new()
	label.text = text
	label.font = Chrome.font()
	label.font_size = size
	label.pixel_size = 0.006
	label.modulate = Color(0.94, 0.88, 0.66)
	label.position = at
	add_child(label)
