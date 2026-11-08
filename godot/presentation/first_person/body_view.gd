extends Node3D
# Sim-driven bodies. One view per living body the sim owns and per human corpse it leaves, placed at the
# sim's position between ticks. A body is drawn with its character model when one loads, and with the
# placeholder capsule when it does not. Nothing here moves anything: the body's `position` component is
# the only truth, and this view reads it after `world.step()`.
#
# The model is the character kit's GLB, shared through `models.gd`: a survivor for every person (colonists,
# raiders, settlers) and a shambler for every zombie, until zombie kinds have models of their own. Each body
# gets its own AnimationPlayer on its own instance, and the sim picks the clip. `anim_state.gd` names the
# state and the phase from sim facts; the player is set to speed zero and seeked to the phase every frame,
# so the animation follows the sim and never its own clock. Loops (idle, walk, crouch_idle, shamble) are
# set LOOP_LINEAR; the one-shots (lunge, death) are LOOP_NONE and hold their last frame, so a corpse stays
# dead after any number of ticks.
#
# A body with no model -- the GLB is missing, or it carries no AnimationPlayer -- keeps the capsule: one
# cylinder at the sim's hit volume (`SimSpace.body_of`), with the foundation's lean for the states it can
# show. A corpse wears the corpse colour on the capsule.
#
# The player's own body is deliberately absent -- in first person the camera is the body's eyes, and a
# body at the eye would be a blank screen. `body_node_for(player)` returning null is the structural half of
# "the camera is the player", asserted by the gate. After a handoff the dead body is no longer
# `world.player`, so it comes back as the corpse it now is.
#
# Visibility is the sim's: a body the player's eye cannot see is not drawn, wherever it stands.
#
# A body with a model also carries what the sim says it holds: the held-weapon assembly `held_weapon.gd` draws for
# the arms, mounted under its right hand (`mount_held`, on the rig's `hand.R`) and read from the sim every frame.

const SimHealth = preload("res://sim/modules/health.gd")
const SimSpace = preload("res://sim/space/space.gd")
const AnimState = preload("res://presentation/first_person/anim_state.gd")
const Models = preload("res://presentation/first_person/models.gd")
const HeldWeapon = preload("res://presentation/first_person/held_weapon.gd")

# The character rig's right hand bone (the kit's `hand.R`, in both survivor.glb and shambler.glb). A body's
# held weapon is mounted under it.
const HAND_BONE: String = "hand.R"
# The turn from the hand bone's rest frame to the weapon's grip frame, one constant for every weapon. Measured by
# the HELD gate's orientation line on the shipped survivor rig before the turn: the grip's bore (-Z) pointed backwards
# (dot with the body's forward -0.960) and the grip's top (+Y) pointed down the arm, because the hand bone's Y runs
# down the arm. A half turn about the hand's X (the body's right side) sends the bore forward and the top up.
const HAND_TO_GRIP_RADIANS: Vector3 = Vector3(PI, 0.0, 0.0)

const SURVIVOR_GLB: String = "res://assets/first_person/survivor.glb"
const SHAMBLER_GLB: String = "res://assets/first_person/shambler.glb"
# The clips that loop. The GLB keeps the clip names and the importer leaves every clip LOOP_NONE, so the
# consumer sets the loop here (the character kit's README: "consumers set LOOP_LINEAR on these"). Every
# other clip is a one-shot.
const LOOPING_CLIPS: Array[String] = ["idle", "walk", "crouch_idle", "shamble"]
# The sim's facing is an angle from +x toward +y (world.gd: atan2(dy, dx)). A model faces -Z, and the sim's
# y is Godot's +z, so a yaw of -facing - PI/2 turns the model's front onto the sim's heading.
const FACING_YAW_OFFSET: float = -PI * 0.5
# How far short of a clip's end a held pose sits: 0.1 ms, below any keyframe's difference.
const HOLD_EPSILON_S: float = 0.0001
# A phase that moved less than this since the last seek is the same pose: 0.1 ms.
const SEEK_EPSILON_S: float = 0.0001

const COLONIST_COLOUR: Color = Color(0.33, 0.62, 0.56)
const ZOMBIE_COLOUR: Color = Color(0.58, 0.32, 0.28)
const CORPSE_COLOUR: Color = Color(0.30, 0.27, 0.24)
# The capsule's pose, for the states it can show. A swing or a lunge leans forward, a hold leans a little,
# a stagger tips sideways and death lies the cylinder down. The lean is about the feet (the centre drops
# by cos), so a tilted body does not float.
const SWING_LEAN_RADIANS: float = 0.35
const LUNGE_LEAN_RADIANS: float = 0.55
const GRAB_LEAN_RADIANS: float = 0.25
const STAGGER_ROLL_RADIANS: float = 0.45

# The model path for each kind. A test can point either one at a missing file to see the capsule.
var survivor_glb: String = SURVIVOR_GLB
var shambler_glb: String = SHAMBLER_GLB
# False draws every body as the capsule: the fallback, and the foundation's own cylinder check.
var models_enabled: bool = true

var _views: Dictionary = {}
var _players: Dictionary = {}
# entity -> the held-weapon mount of a body with a model (`mount_held`): {held, bone, skeleton}.
var _held: Dictionary = {}
# entity -> the clip position last sought, so a body whose phase has not moved is not sought again.
var _sought: Dictionary = {}
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


## How many bodies are drawn with a character model rather than the capsule.
func model_count() -> int:
	return _players.size()


func visible_count() -> int:
	var total: int = 0
	for view in _views.values():
		var node: Node3D = view as Node3D
		if node != null and node.visible:
			total += 1
	return total


func node_for(entity: int) -> Node3D:
	return _views.get(entity) as Node3D


## The AnimationPlayer playing a body's model, or null for a capsule or an unknown body.
func player_of(entity: int) -> AnimationPlayer:
	return _players.get(entity) as AnimationPlayer


## The held-weapon view under a body's right hand, or null for a capsule or a body whose model has no hand bone.
func held_for(entity: int) -> Node3D:
	var entry: Variant = _held.get(entity)
	if not (entry is Dictionary):
		return null
	return (entry as Dictionary)["held"] as Node3D


## The right hand's attachment for a body, or null (the same cases as `held_for`).
func hand_for(entity: int) -> BoneAttachment3D:
	var entry: Variant = _held.get(entity)
	if not (entry is Dictionary):
		return null
	return (entry as Dictionary)["bone"] as BoneAttachment3D


## Mounts the held-weapon view under the right hand of the model under `root`: the same assembly the arms view
## draws (`held_weapon.gd`, with its `holder` set to the entity whose weapon it is), parented to a BoneAttachment3D
## on the skeleton's `hand.R`, so the weapon moves with the hand. `root` must already be in the tree. Returns
## {held, bone, skeleton}, or {} when the model has no skeleton or no such bone, which is a body that carries nothing.
static func mount_held(root: Node3D, holder: int) -> Dictionary:
	var skeleton: Skeleton3D = _skeleton_in(root)
	if skeleton == null or skeleton.find_bone(HAND_BONE) < 0:
		return {}
	var bone: BoneAttachment3D = BoneAttachment3D.new()
	bone.name = HAND_BONE
	bone.bone_name = HAND_BONE
	skeleton.add_child(bone)
	var held: HeldWeapon = HeldWeapon.new()
	held.name = "HeldWeapon"
	held.holder = holder
	root.add_child(held)
	held.mount(bone)
	(held.grip_node() as Node3D).transform = Transform3D(Basis.from_euler(HAND_TO_GRIP_RADIANS), Vector3.ZERO)
	return {"held": held, "bone": bone, "skeleton": skeleton}


## Brings the held weapon to the sim's hand this frame: the body's assembly is read from the sim, and when something
## is drawn the skeleton's pose is taken so the attachment sits on the hand that the clip just played.
static func update_held(mounted: Dictionary, world: Variant) -> void:
	if mounted.is_empty():
		return
	var held: HeldWeapon = mounted["held"] as HeldWeapon
	held.update(world, 0.0)
	if held.visible_any():
		(mounted["skeleton"] as Skeleton3D).force_update_all_bone_transforms()
		(mounted["bone"] as BoneAttachment3D).on_skeleton_update()


static func _skeleton_in(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found: Skeleton3D = _skeleton_in(child)
		if found != null:
			return found
	return null


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
		# A corpse stays a body the screen draws: on a succession the dead player is the first one the heir can
		# see, and a body that vanished would be the camera changing without a reason on screen. A corpse has no
		# living body left to test; the living still must.
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
			var stale: Node3D = _views[ent] as Node3D
			_views.erase(ent)
			_players.erase(ent)
			_held.erase(ent)
			_sought.erase(ent)
			if stale != null:
				stale.queue_free()
	for ent in _curr.keys():
		var e: int = int(ent)
		var view: Node3D = _views.get(e) as Node3D
		if view == null:
			view = _make_view(e, world)
			_views[e] = view
		var then: Vector2 = _prev.get(e, _curr[e]) as Vector2
		var now: Vector2 = _curr[e] as Vector2
		var at: Vector2 = then.lerp(now, a)
		if _players.has(e):
			view.position = Vector3(at.x, 0.0, at.y)
			_face(view, world, e)
			_animate(e, world)
			if _held.has(e):
				update_held(_held[e] as Dictionary, world)
		else:
			_draw_capsule(view as MeshInstance3D, world, e, at)
		# The screen may not know more than the sim does: a body behind a wall or beyond the player's range is
		# not drawn, even though the 3D depth buffer would hide some of them. `vision.detail` is the same read
		# model the top-down screen and the work read use.
		view.visible = _in_sight(world, now)


func _in_sight(world: Variant, at: Vector2) -> bool:
	if world == null or world.vision == null:
		return false
	return int(world.vision.call("detail", int(world.player), at.x, at.y)) != 0


# The model turns to the sim's facing. The sim's facing is read every frame, so a turn between ticks shows as
# soon as the sim makes it.
func _face(view: Node3D, world: Variant, entity: int) -> void:
	var facing: Variant = world.components.get_component(entity, "facing")
	if facing is Dictionary:
		view.rotation.y = -float((facing as Dictionary).get("radians", 0.0)) + FACING_YAW_OFFSET


# Plays the clip `anim_state.gd` names for the body's state, held at the state's phase. The player never runs
# on its own clock: its speed is zero, and the seek sets the pose.
func _animate(entity: int, world: Variant) -> void:
	var player: AnimationPlayer = _players[entity] as AnimationPlayer
	var state: String = AnimState.state_of(world, entity)
	var clip: String = AnimState.clip_for(AnimState.kind_of(world, entity), state)
	if not player.has_animation(clip):
		return
	if player.current_animation != clip:
		player.play(clip)
		_sought.erase(entity)
	var length: float = player.get_animation(clip).length
	# A one-shot seeked to its exact end finishes, and a finished clip clears `current_animation`. The held
	# pose is one hair short of the end, which is the last frame to the eye.
	var at: float = minf(AnimState.phase_of(world, entity, state) * length, length - HOLD_EPSILON_S)
	# The phase moves on the sim's ticks, so a body between ticks keeps the pose it had; seeking it again
	# would rebuild the same skeleton pose every frame.
	if not _sought.has(entity) or absf(float(_sought[entity]) - at) > SEEK_EPSILON_S:
		player.seek(at, true)
		_sought[entity] = at


# The capsule's own pose, for a body with no model.
func _draw_capsule(view: MeshInstance3D, world: Variant, entity: int, at: Vector2) -> void:
	view.position = Vector3(at.x, view.position.y, at.y)
	if world.components.has_component(entity, "corpse") and view.material_override != _corpse_material:
		view.material_override = _corpse_material
	var height: float = _fit(view, world, entity)
	_pose(view, world, entity, height)


# The cylinder follows the body's volume from the sim: its height is re-read every frame, because a stance
# change (or a zombie losing its legs) changes it between ticks. Returns the height in metres, which `_pose`
# needs for the lean's pivot.
func _fit(view: MeshInstance3D, world: Variant, entity: int) -> float:
	var cylinder: CylinderMesh = view.mesh as CylinderMesh
	if cylinder == null:
		return 0.0
	var volume: Dictionary = SimSpace.body_of(world, entity)
	var height: float = float(int(volume["height"])) / 1000.0
	var radius: float = float(int(volume["radius"])) / 1000.0
	if cylinder.height != height or cylinder.top_radius != radius:
		cylinder.height = height
		cylinder.top_radius = radius
		cylinder.bottom_radius = radius
		view.position.y = height * 0.5
	return height


# The capsule's pose for the state `anim_state.gd` names: a lean into a swing, lunge or hold, a sideways roll
# for a stagger, and the cylinder on its side for a corpse. The cylinder's own height already carries crouch
# and crawl, so those need no pose. Rotation is reset every frame.
func _pose(view: MeshInstance3D, world: Variant, entity: int, height: float) -> void:
	var state: String = AnimState.state_of(world, entity)
	if state == AnimState.DEATH:
		var radius: float = float(SimSpace.HIT_RADIUS_MM) / 1000.0
		view.rotation = Vector3(0.0, 0.0, PI * 0.5)
		view.position.y = radius
		return
	var rotation: Vector3 = Vector3.ZERO
	if state == AnimState.SWING:
		rotation.x = -SWING_LEAN_RADIANS
	elif state == AnimState.LUNGE:
		rotation.x = -LUNGE_LEAN_RADIANS
	elif state == AnimState.GRAB:
		rotation.x = -GRAB_LEAN_RADIANS
	elif state == AnimState.STAGGER:
		rotation.z = STAGGER_ROLL_RADIANS
	view.rotation = rotation
	var tilt: float = sqrt(rotation.x * rotation.x + rotation.z * rotation.z)
	view.position.y = height * 0.5 * cos(tilt)


func _make_view(entity: int, world: Variant) -> Node3D:
	if models_enabled:
		var model_view: Node3D = _model_view(entity, world)
		if model_view != null:
			add_child(model_view)
			var mounted: Dictionary = mount_held(model_view, entity)
			if not mounted.is_empty():
				_held[entity] = mounted
			return model_view
	var capsule: MeshInstance3D = _capsule_view(entity, world)
	add_child(capsule)
	return capsule


# A body's own instance of its kind's model, with its own AnimationPlayer. Null when the model is missing or
# has no player, so the body keeps the capsule.
func _model_view(entity: int, world: Variant) -> Node3D:
	var path: String = shambler_glb if AnimState.is_zombie(world, entity) else survivor_glb
	var model: Node3D = Models.instance_of(path)
	if model == null:
		return null
	var player: AnimationPlayer = _player_in(model)
	if player == null:
		model.free()
		return null
	_set_loop_modes(player)
	player.speed_scale = 0.0
	var root: Node3D = Node3D.new()
	root.name = "Body%d" % entity
	root.add_child(model)
	_players[entity] = player
	return root


# The loop flags are on the shared clip resources, so setting them again for the next body changes nothing.
static func _set_loop_modes(player: AnimationPlayer) -> void:
	for clip in player.get_animation_list():
		var animation: Animation = player.get_animation(clip)
		animation.loop_mode = Animation.LOOP_LINEAR if LOOPING_CLIPS.has(String(clip)) else Animation.LOOP_NONE


static func _player_in(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found: AnimationPlayer = _player_in(child)
		if found != null:
			return found
	return null


func _capsule_view(entity: int, world: Variant) -> MeshInstance3D:
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
	return view


func _material(colour: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.9
	return material
