extends Node3D
# The player's own body, for the third-person testing view (docs/39). `body_view.gd` leaves the player
# out on purpose: in first person the camera is the body's eyes. This node is the one place the player
# is drawn, and it is drawn only while `first_person.gd` says the view is third person.
#
# It is a view of the sim and nothing else. It places itself where the rendered player stands, turns to
# the sim's facing, and plays the clip `anim_state.gd` names for the sim's state, held at the sim's
# phase -- the same rule `body_view.gd` follows for every other body. The player's speed is zero, so the
# animation never runs on its own clock.

const Models = preload("res://presentation/first_person/models.gd")
const AnimState = preload("res://presentation/first_person/anim_state.gd")
const BodyView = preload("res://presentation/first_person/body_view.gd")

const SURVIVOR_GLB: String = "res://assets/first_person/survivor.glb"
# The clips that loop; the others are one-shots that hold their last frame, as in body_view.gd.
const LOOPING_CLIPS: Array[String] = ["idle", "walk", "crouch_idle", "shamble"]
# 0.1 ms short of a one-shot's end, below any keyframe's difference (the same hold body_view uses).
const HOLD_EPSILON_S: float = 0.0001
const SEEK_EPSILON_S: float = 0.0001

# The AnimationPlayer playing the model, or null when the GLB is missing or carries no player.
var player: AnimationPlayer = null
var _sought: float = -1.0
# The held-weapon mount under the right hand (`body_view.gd`'s `mount_held`): {held, bone, skeleton}, or {}.
var _held: Dictionary = {}


## The held-weapon view under the player's right hand, or null when the model did not load or has no hand bone.
func held_node() -> Node3D:
	if _held.is_empty():
		return null
	return _held["held"] as Node3D


## The right hand's attachment, or null (the same cases as `held_node`).
func hand_node() -> BoneAttachment3D:
	if _held.is_empty():
		return null
	return _held["bone"] as BoneAttachment3D


## Loads the survivor model under this node. False when the model is missing, so the screen has no
## body to show and says so rather than drawing nothing silently.
func build() -> bool:
	var model: Node3D = Models.instance_of(SURVIVOR_GLB)
	if model == null:
		return false
	var found: AnimationPlayer = _player_in(model)
	if found == null:
		model.free()
		return false
	for clip in found.get_animation_list():
		var animation: Animation = found.get_animation(clip)
		animation.loop_mode = Animation.LOOP_LINEAR if LOOPING_CLIPS.has(String(clip)) else Animation.LOOP_NONE
	found.speed_scale = 0.0
	add_child(model)
	player = found
	# The weapon the arms hold in first person is drawn in the hand here in third person. The holder is -1, the
	# player, so the held view reads the same sim state the arms do.
	_held = BodyView.mount_held(self, -1)
	return true


## The clip playing now, or "" when there is no model.
func clip_playing() -> String:
	return "" if player == null else String(player.current_animation)


## Places the body at `at` (the rendered ground point, Godot x and z), turns it to the sim's facing for
## `entity`, and plays the clip the sim's state names. Takes nothing from the view.
func update(world: Variant, entity: int, at: Vector2) -> void:
	if player == null:
		return
	position = Vector3(at.x, 0.0, at.y)
	var facing: Variant = world.components.get_component(entity, "facing")
	if facing is Dictionary:
		rotation.y = -float((facing as Dictionary).get("radians", 0.0)) + BodyView.FACING_YAW_OFFSET
	var state: String = AnimState.state_of(world, entity)
	var clip: String = AnimState.clip_for(AnimState.kind_of(world, entity), state)
	if not player.has_animation(clip):
		return
	if player.current_animation != clip:
		player.play(clip)
		_sought = -1.0
	var length: float = player.get_animation(clip).length
	var phase_s: float = minf(AnimState.phase_of(world, entity, state) * length, length - HOLD_EPSILON_S)
	if _sought < 0.0 or absf(_sought - phase_s) > SEEK_EPSILON_S:
		player.seek(phase_s, true)
		_sought = phase_s
	BodyView.update_held(_held, world)


static func _player_in(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found: AnimationPlayer = _player_in(child)
		if found != null:
			return found
	return null
