extends Node3D
# Sim-driven bodies as placeholders. One capsule per living body and per human corpse the sim
# owns, placed at the sim's position between ticks. Nothing here moves anything: the body's
# `position` component is the only truth, and this view reads it after `world.step()`. A corpse is
# what the dead body becomes at a succession, and it is drawn in the corpse's own colour if the
# living eye can see it.
#
# The player's own body is deliberately absent -- in first person the camera is the body's eyes,
# and a capsule at the eye would be a blue screen. `body_node_for(player)` returning null is the
# structural half of "the camera is the player", asserted by the gate. After a handoff the dead
# body is no longer `world.player`, so it comes back as the corpse it now is.

const SimHealth = preload("res://sim/modules/health.gd")

const COLONIST_COLOUR: Color = Color(0.33, 0.62, 0.56)
const ZOMBIE_COLOUR: Color = Color(0.58, 0.32, 0.28)
const CORPSE_COLOUR: Color = Color(0.30, 0.27, 0.24)
const COLONIST_HEIGHT_M: float = 1.70
const ZOMBIE_HEIGHT_M: float = 1.55
const BODY_RADIUS_M: float = 0.30

var _views: Dictionary = {}
var _prev: Dictionary = {}
var _curr: Dictionary = {}
var _colonist_mesh: CapsuleMesh = null
var _zombie_mesh: CapsuleMesh = null
var _colonist_material: StandardMaterial3D = null
var _zombie_material: StandardMaterial3D = null
var _corpse_material: StandardMaterial3D = null


func build() -> void:
	_colonist_mesh = CapsuleMesh.new()
	_colonist_mesh.radius = BODY_RADIUS_M
	_colonist_mesh.height = COLONIST_HEIGHT_M
	_zombie_mesh = CapsuleMesh.new()
	_zombie_mesh.radius = BODY_RADIUS_M
	_zombie_mesh.height = ZOMBIE_HEIGHT_M
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
		# A body that died since the view was made wears the corpse's colour from that frame on.
		if world.components.has_component(e, "corpse") and view.material_override != _corpse_material:
			view.material_override = _corpse_material
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


func _make_view(entity: int, world: Variant) -> MeshInstance3D:
	var zombie: bool = world.components.has_component(entity, "zombieType")
	var corpse: bool = world.components.has_component(entity, "corpse")
	var view: MeshInstance3D = MeshInstance3D.new()
	view.name = "Body%d" % entity
	view.mesh = _zombie_mesh if zombie else _colonist_mesh
	if corpse:
		view.material_override = _corpse_material
	else:
		view.material_override = _zombie_material if zombie else _colonist_material
	var height: float = ZOMBIE_HEIGHT_M if zombie else COLONIST_HEIGHT_M
	view.position = Vector3(0.0, height * 0.5, 0.0)
	add_child(view)
	return view


func _material(colour: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.9
	return material
