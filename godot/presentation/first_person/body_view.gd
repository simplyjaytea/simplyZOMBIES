extends Node3D
# Sim-driven bodies as placeholders. One cylinder per living body the sim owns and per human corpse
# it leaves, placed at the sim's position between ticks and sized from `SimSpace.body_of`: the
# radius is the hit radius and the height follows the body's posture, or a zombie's state. Nothing
# here moves anything: the body's `position` component is the only truth, and this view reads it
# after `world.step()`.
#
# A corpse stays a body the screen draws: on a succession the dead player is the first one the heir
# can see, and a body that vanished would be the camera changing without a reason on screen. It
# wears the corpse's colour, and it is gated by sight like every other body.
#
# The player's own body is deliberately absent -- in first person the camera is the body's eyes,
# and a cylinder at the eye would be a blue screen. `body_node_for(player)` returning null is the
# structural half of "the camera is the player", asserted by the gate. After a handoff the dead
# body is no longer `world.player`, so it comes back as the corpse it now is.

const SimHealth = preload("res://sim/modules/health.gd")
const SimSpace = preload("res://sim/space/space.gd")

const COLONIST_COLOUR: Color = Color(0.33, 0.62, 0.56)
const ZOMBIE_COLOUR: Color = Color(0.58, 0.32, 0.28)
const CORPSE_COLOUR: Color = Color(0.30, 0.27, 0.24)

var _views: Dictionary = {}
var _prev: Dictionary = {}
var _curr: Dictionary = {}
var _colonist_material: StandardMaterial3D = null
var _zombie_material: StandardMaterial3D = null
var _corpse_material: StandardMaterial3D = null


func build() -> void:
	_colonist_material = _material(COLONIST_COLOUR)
	_zombie_material = _material(ZOMBIE_COLOUR)
	_corpse_material = _material(CORPSE_COLOUR)


## The first snapshot, where previous and current are the same. Called once after boot.
func reset(world: Variant) -> void:
	_prev = _collect(world)
	_curr = _prev.duplicate()
	_sync_views(world, 1.0)


## Before a tick: the current snapshot becomes the previous one.
func begin_tick() -> void:
	_prev = _curr


## After a tick: the sim's new positions become the current snapshot.
func end_tick(world: Variant) -> void:
	_curr = _collect(world)


func apply(world: Variant, alpha: float) -> void:
	_sync_views(world, alpha)


func count() -> int:
	return _views.size()


func visible_count() -> int:
	var total: int = 0
	for view in _views.values():
		var mesh: MeshInstance3D = view as MeshInstance3D
		if mesh != null and mesh.visible:
			total += 1
	return total


func node_for(entity: int) -> MeshInstance3D:
	return _views.get(entity) as MeshInstance3D


func _collect(world: Variant) -> Dictionary:
	var out: Dictionary = {}
	if world == null:
		return out
	for ent in world.components.query(["position", "body"]):
		var e: int = int(ent)
		if e == int(world.player):
			continue
		if not world.entities.is_alive(e):
			continue
		# A corpse stays a body the screen draws: on a succession the dead player is the first
		# one the heir can see, and a body that vanished would be the camera changing without a
		# reason on screen. A corpse has no living body left to test; the living still must.
		if not world.components.has_component(e, "corpse"):
			var body: Variant = world.components.get_component(e, "body")
			if body is Dictionary and not SimHealth.is_alive(body as Dictionary):
				continue
		var pos: Variant = world.components.get_component(e, "position")
		if not (pos is Dictionary):
			continue
		out[e] = Vector2(float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]))
	return out


func _sync_views(world: Variant, alpha: float) -> void:
	if world == null:
		return
	var a: float = clampf(alpha, 0.0, 1.0)
	for ent in _views.keys():
		if not _curr.has(ent):
			var stale: MeshInstance3D = _views[ent] as MeshInstance3D
			_views.erase(ent)
			if stale != null:
				stale.queue_free()
	for ent in _curr.keys():
		var e: int = int(ent)
		var view: MeshInstance3D = _views.get(e) as MeshInstance3D
		if view == null:
			view = _make_view(e, world)
			_views[e] = view
		# A body that died since the view was made wears the corpse's colour from that frame on,
		# and a stance change or a lost leg re-sizes the cylinder the same frame.
		if world.components.has_component(e, "corpse") and view.material_override != _corpse_material:
			view.material_override = _corpse_material
		_fit(view, world, e)
		var then: Vector2 = _prev.get(e, _curr[e]) as Vector2
		var now: Vector2 = _curr[e] as Vector2
		var at: Vector2 = then.lerp(now, a)
		view.position = Vector3(at.x, view.position.y, at.y)
		# The screen may not know more than the sim does: a body behind a wall or beyond the
		# player's range is not drawn, even though the 3D depth buffer would hide some of them.
		# `vision.detail` is the same read model the top-down screen and the work read use.
		view.visible = _in_sight(world, now)


func _in_sight(world: Variant, at: Vector2) -> bool:
	if world == null or world.vision == null:
		return false
	return int(world.vision.call("detail", int(world.player), at.x, at.y)) != 0


# The cylinder follows the body's volume from the sim: its height is re-read every frame, because a
# stance change (or a zombie losing its legs) changes it between ticks.
func _fit(view: MeshInstance3D, world: Variant, entity: int) -> void:
	var cylinder: CylinderMesh = view.mesh as CylinderMesh
	if cylinder == null:
		return
	var volume: Dictionary = SimSpace.body_of(world, entity)
	var height: float = float(int(volume["height"])) / 1000.0
	var radius: float = float(int(volume["radius"])) / 1000.0
	if cylinder.height != height or cylinder.top_radius != radius:
		cylinder.height = height
		cylinder.top_radius = radius
		cylinder.bottom_radius = radius
		view.position.y = height * 0.5


func _make_view(entity: int, world: Variant) -> MeshInstance3D:
	var zombie: bool = world.components.has_component(entity, "zombieType")
	var corpse: bool = world.components.has_component(entity, "corpse")
	var view: MeshInstance3D = MeshInstance3D.new()
	view.name = "Body%d" % entity
	view.mesh = CylinderMesh.new()
	if corpse:
		view.material_override = _corpse_material
	else:
		view.material_override = _zombie_material if zombie else _colonist_material
	_fit(view, world, entity)
	add_child(view)
	return view


func _material(colour: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.9
	return material
