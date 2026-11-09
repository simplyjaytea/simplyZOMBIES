extends Node3D
# The player's own arms in the first-person view, holding what the sim says is in hand (docs/41 W1,
# "the held weapon": the arms plus the equipped item; bare hands show the arms alone). The art and
# its contract are the arms kit's (`tools/blender/first_person_arms/README.md`): one GLB in camera
# space (the origin is the eye, +Y up, -Z forward), a 43-bone skeleton whose `grip_r` leaf is the
# weapon frame, and 23 clips at 60 fps in one AnimationPlayer.
#
# Where it hangs. This node is a child of the camera (`Eye`) with an identity transform, and the GLB
# is under a sway pivot under it, so a number in the GLB is a camera-space number. A BoneAttachment3D
# named `grip_r` follows the skeleton's `grip_r` bone, and the held weapon's grip node
# (`held_weapon.gd`, which still assembles the item from the sim's installed parts) is parented under
# it with an identity transform: the weapon GLB's origin is its own `grip_r`, so the hand holds it.
#
# What is read, never decided:
#   SimMelee.is_unarmed            bare hands: the `unarmed` class, and no weapon.
#   rangedWeapon.source            a firearm in hand. Its base's equip slot names the class: the
#                                  sidearm slot (`secondary`) is `pistol`, anything carried in the
#                                  primary slot is `long`.
#   meleeWeapon.source             a melee item in hand. A polearm, or a base two cells wide or four
#                                  long in the grid, is carried in both fists (`melee2`); anything
#                                  shorter is one-handed (`melee1`).
#   SimRanged.cone_half            how far the idle breath sways the arms, as the README asks: the
#                                  sim's felt cone, never a number on the screen.
#
# The clips, played by phase. `draw_<class>` brings the hands up from below the frame and hands over to
# the `idle_<class>` loop. A change of the item in hand lowers the old class first (`lower_<class>`,
# with a copy of the old model still in the hand) and then draws the new one, so the sim's truth
# (`held_weapon.gd`'s drawn set) changes on the tick it changes while the picture takes 0.8 s. A
# screen over the view (`covered`) lowers the arms and holds them below the frame, hidden; when it
# goes they are drawn again. The third-person testing view hides them at once. `inspect_<class>`
# plays only while the inspect key is held, from idle, and goes back to idle the moment it is let go;
# the bare hands have no inspect clip. The fire state (`fire_of`, read from the sim's `rangedWeapon`)
# drives a firearm's clips: `raise_<class>` is held at the sim's own progress through its raise, so a
# heavier weapon's longer raise stretches the clip; `aim_<class>` loops while the sim is steady;
# recover and reload blend back to `idle_<class>`, since there is no reload clip yet. A melee class
# or bare hands ignore the fire state. Draw, lower, inspect and covered win over it.
#
# The view-model lens. Every surface under this node draws through a copy of its material with Godot's
# view-model switches on: `use_fov_override` at VIEW_MODEL_FOV_DEG, so the arms keep their own lens
# whatever the world camera does, and `use_z_clip_scale` at Z_CLIP_SCALE, which pulls the view
# model's depth toward the near plane in the vertex stage (the shadow pass excepted), so a wall in
# front of the eye can never cut through the hands or the weapon while the hands still hide each
# other in the right order. Both work in the Compatibility renderer this project ships. The copies
# are cached per source material, so the shared atlases the world draws with are never changed.
# View-model meshes cast no shadow.
#
# Presentation only: no sim component is written, and the clips run on this node's own clock
# (`advance` with the frame's delta, manual process mode), so the gate drives them frame by frame.

const SimMelee = preload("res://sim/modules/melee.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimAim = preload("res://sim/aim.gd")
const Models = preload("res://presentation/first_person/models.gd")
const HeldWeapon = preload("res://presentation/first_person/held_weapon.gd")

const ARMS_GLB: String = "res://assets/first_person/arms/arms_base.glb"
const ARMS_JSON: String = "res://assets/first_person/arms/arms.json"
const CLASSES: Array[String] = ["unarmed", "pistol", "long", "melee1", "melee2"]
# The view model's own vertical field of view. The arms were posed and checked at a vertical 75
# degrees (the kit's near-plane and in-frame checks), which is also the world camera's today; holding
# it here means a later change to the world's lens does not move the hands.
const VIEW_MODEL_FOV_DEG: float = 75.0
# The share of its depth the view model keeps. At 0.05 everything within a metre of the eye draws as
# if it were within 5.3 cm, nearer than any wall the body can stand against, while the 24-bit depth
# buffer still has over half a million steps across the arms to sort the fingers by.
const Z_CLIP_SCALE: float = 0.05
# Cross-fades, in seconds: into a draw or a lower from wherever the arms were, and back from an
# inspect that was let go part way. A one-shot starts and ends at rest, so a full clip needs none.
const SWITCH_BLEND_S: float = 0.08
const INSPECT_RELEASE_BLEND_S: float = 0.2
# Sway. The arms lag a turn of the head (radians of lag per radian a second of turn, capped), bob with
# the body's walking speed, and breathe with the sim's cone. All of it is a few millimetres and a
# fraction of a degree; SWAY_TAU_S is how fast the lag catches up.
const LOOK_LAG_S: float = 0.012
const LOOK_LAG_MAX_RAD: float = 0.035
const SWAY_TAU_S: float = 0.08
const BOB_RAD_PER_M: float = 4.2
const BOB_X_M: float = 0.006
const BOB_Y_M: float = 0.008
const BOB_FULL_SPEED_MPS: float = 2.0
const BREATH_M: float = 0.0025
const BREATH_RAD: float = 0.004
# A weapon that is not ready is drawn lowered: moved by LOWER_OFFSET and tilted by LOWER_PITCH_DEG at no ready
# (ready_amount 0), and level at a steady aim. Presentation only; the sim's cone already says it.
const LOWER_OFFSET: Vector3 = Vector3(0.04, -0.10, 0.05)
const LOWER_PITCH_DEG: float = -18.0

enum Phase { HIDDEN, DRAW, IDLE, INSPECT, LOWER, LOWERED, RAISE, AIM }

# 1 scales every sway term; the gate sets 0 to read the clip's own pose against the anchors.
var sway_scale: float = 1.0
# A fire state the gate sets in place of the sim's, `{"phase", "t"}`; empty reads the sim.
var fire_stub: Dictionary = {}

var _sway: Node3D = null
var _model: Node3D = null
var _player: AnimationPlayer = null
var _skeleton: Skeleton3D = null
var _grip_r: BoneAttachment3D = null
var _grip_l: BoneAttachment3D = null
var _held: Node3D = null
var _anchors: Dictionary = {}
var _phase: int = Phase.HIDDEN
# The class the arms show now, and the item (sim entity) in that hand; -1 is bare hands.
var _class: String = ""
var _item: int = -2
var _clip: String = ""
var _clip_time: float = 0.0
var _swapping: bool = false
var _ghost: Node3D = null
var _held_revision: int = -1
var _updates: int = 0
var _last_look: Vector2 = Vector2.ZERO
var _look_seen: bool = false
var _sway_rot: Vector3 = Vector3.ZERO
var _bob_phase: float = 0.0
var _bob_amount: float = 0.0
var _clock: float = 0.0
# 0 ready .. 1 lowered, smoothed toward the sim's ready amount with the sway time constant.
var _lowered: float = 0.0

static var _view_materials: Dictionary = {}


## Loads the arms and puts the held-weapon view in the right hand. Without the arms GLB the held
## weapon stays at its own eye anchor, as it was before the arms existed, and `arms_loaded` is false.
func build() -> void:
	_held = HeldWeapon.new()
	_held.name = "HeldWeapon"
	add_child(_held)
	_sway = Node3D.new()
	_sway.name = "Sway"
	add_child(_sway)
	_anchors = _read_anchors()
	var model: Node3D = Models.instance_of(ARMS_GLB)
	if model == null:
		return
	var skeleton: Skeleton3D = _first(model, "Skeleton3D") as Skeleton3D
	var player: AnimationPlayer = _first(model, "AnimationPlayer") as AnimationPlayer
	if skeleton == null or player == null or skeleton.find_bone("grip_r") < 0:
		model.free()
		return
	model.name = "ArmsModel"
	_sway.add_child(model)
	_model = model
	_skeleton = skeleton
	_player = player
	for clip in _player.get_animation_list():
		var name_s: String = String(clip)
		var animation: Animation = _player.get_animation(clip)
		animation.loop_mode = Animation.LOOP_LINEAR if (name_s.begins_with("idle_") or name_s.begins_with("aim_")) else Animation.LOOP_NONE
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	# GLTFDocument drops every track equal to its bone's rest pose, so a bone a clip leaves at rest has
	# no track in that clip. Without this the mixer keeps that bone at the previous clip's pose, and the
	# pose of a clip then depends on the clip before it. Deterministic resets an untracked bone to rest.
	_player.deterministic = true
	_grip_r = _attachment("grip_r")
	_grip_l = _attachment("grip_l")
	_held.call("mount", _grip_r)
	_apply_view_lens(_model)
	_sway.visible = false


func _attachment(bone: String) -> BoneAttachment3D:
	var node: BoneAttachment3D = BoneAttachment3D.new()
	node.name = bone
	node.bone_name = bone
	_skeleton.add_child(node)
	return node


## Called once a frame by the scene. `covered` is any screen over the view; `third_person` the testing
## view; `inspect_held` the inspect key; `look` the camera's yaw and pitch; `speed_mps` how fast the
## sim's body is moving. `hide_weapon` is the end panel, as `held_weapon.gd` has always taken it.
func update(world: Variant, delta: float, covered: bool, third_person: bool, inspect_held: bool, look: Vector2, speed_mps: float, hide_weapon: bool = false) -> void:
	_updates += 1
	var want_item: int = -2
	var want_class: String = ""
	var fire: Dictionary = {"phase": "idle", "t": 0.0}
	if world != null and int(world.player) >= 0:
		want_item = equipped_item(world, int(world.player))
		want_class = hold_class_of(world, int(world.player))
		fire = _fire_now(world, int(world.player))
	if _player == null:
		# No arms: the old eye-anchored weapon, untouched.
		if _held != null:
			_held.call("update", world, Time.get_ticks_msec() / 1000.0, hide_weapon)
		return
	# A change of what is in hand while the arms are up: keep a copy of the old model in the hand and
	# lower it before the sim's new item is drawn.
	if _class != "" and want_class != "" and (want_item != _item or want_class != _class) and not _swapping:
		if _phase == Phase.DRAW or _phase == Phase.IDLE or _phase == Phase.INSPECT or _phase == Phase.RAISE or _phase == Phase.AIM:
			_begin_swap()
		elif _phase == Phase.LOWER:
			_swapping = true
		else:
			_class = want_class
			_item = want_item
	if _class == "" and want_class != "":
		_class = want_class
		_item = want_item
	_held.call("update", world, Time.get_ticks_msec() / 1000.0, hide_weapon)
	var revision: int = int(_held.call("revision"))
	if revision != _held_revision:
		_held_revision = revision
		_apply_view_lens(_grip_r)
	_step_phase(delta, covered or want_class == "", third_person, inspect_held, want_class, want_item, fire)
	_held.call("set_in_hand", not _swapping)
	_update_sway(world, delta, look, speed_mps)
	_player.advance(delta)
	if _phase == Phase.RAISE:
		_hold_raise(fire)
	_sync_bones()
	_clip_time += delta


func _step_phase(delta: float, covered: bool, third_person: bool, inspect_held: bool, want_class: String, want_item: int, fire: Dictionary) -> void:
	if third_person:
		_set_phase_hidden()
		return
	# The sim's fire phase, read only for a firearm: a melee class and bare hands have no raise or aim clip.
	var fire_phase: String = String(fire.get("phase", "idle")) if _fires() else "idle"
	match _phase:
		Phase.HIDDEN:
			_finish_swap(want_class, want_item)
			if covered:
				_phase = Phase.LOWERED
				_sway.visible = false
			else:
				_start(Phase.DRAW, "draw_" + _class, 0.0)
		Phase.DRAW:
			if covered:
				_start(Phase.LOWER, "lower_" + _class, SWITCH_BLEND_S)
			elif _clip_done(delta):
				_start(Phase.IDLE, "idle_" + _class, 0.0)
		Phase.IDLE:
			if covered:
				_start(Phase.LOWER, "lower_" + _class, SWITCH_BLEND_S)
			elif inspect_held and _player.has_animation("inspect_" + _class):
				_start(Phase.INSPECT, "inspect_" + _class, SWITCH_BLEND_S)
			elif fire_phase == "raise":
				_start(Phase.RAISE, "raise_" + _class, SWITCH_BLEND_S)
			elif fire_phase == "aim":
				_start(Phase.AIM, "aim_" + _class, SWITCH_BLEND_S)
		Phase.RAISE:
			if covered:
				_start(Phase.LOWER, "lower_" + _class, SWITCH_BLEND_S)
			elif fire_phase == "aim":
				_start(Phase.AIM, "aim_" + _class, SWITCH_BLEND_S)
			elif fire_phase != "raise":
				# A raise that ends without a steady (a stagger, a lost capability): back to idle.
				_start(Phase.IDLE, "idle_" + _class, SWITCH_BLEND_S)
		Phase.AIM:
			if covered:
				_start(Phase.LOWER, "lower_" + _class, SWITCH_BLEND_S)
			elif fire_phase == "raise":
				_start(Phase.RAISE, "raise_" + _class, SWITCH_BLEND_S)
			elif fire_phase != "aim":
				# The shot is fired and the sim recovers, or reloads: the idle is the default for both.
				_start(Phase.IDLE, "idle_" + _class, SWITCH_BLEND_S)
		Phase.INSPECT:
			if covered:
				_start(Phase.LOWER, "lower_" + _class, SWITCH_BLEND_S)
			elif not inspect_held:
				_start(Phase.IDLE, "idle_" + _class, INSPECT_RELEASE_BLEND_S)
			elif _clip_done(delta):
				# Still held at the end: the clip starts and ends at rest, so it simply goes round again.
				_start(Phase.INSPECT, "inspect_" + _class, 0.0)
		Phase.LOWER:
			if _clip_done(delta):
				_finish_swap(want_class, want_item)
				if covered:
					_phase = Phase.LOWERED
					_sway.visible = false
				else:
					_start(Phase.DRAW, "draw_" + _class, 0.0)
		Phase.LOWERED:
			_finish_swap(want_class, want_item)
			if not covered:
				_start(Phase.DRAW, "draw_" + _class, 0.0)


# The skeleton applies a new pose at the end of the frame; the grips are brought up to it now, so the
# weapon and anything that reads the hand this frame see the pose just played.
func _sync_bones() -> void:
	_skeleton.force_update_all_bone_transforms()
	_grip_r.on_skeleton_update()
	_grip_l.on_skeleton_update()


func _start(phase: int, clip: String, blend: float) -> void:
	_phase = phase
	_clip = clip
	_clip_time = 0.0
	_sway.visible = true
	if _player.has_animation(clip):
		_player.play(clip, blend)
		_player.seek(0.0, blend <= 0.0)


# True when the one-shot playing now reaches its end within this frame's advance.
func _clip_done(delta: float) -> bool:
	if not _player.has_animation(_clip):
		return true
	return _clip_time + delta >= _player.get_animation(_clip).length


func _set_phase_hidden() -> void:
	_phase = Phase.HIDDEN
	_sway.visible = false


# The fire state the arms follow this frame: the gate's stub when one is set, else the sim's.
func _fire_now(world: Variant, entity: int) -> Dictionary:
	if not fire_stub.is_empty():
		return fire_stub
	return fire_of(world, entity)


# Only a firearm has a raise and an aim clip.
func _fires() -> bool:
	return _class == "pistol" or _class == "long"


# The raise clip sits at the sim's own progress through the weapon's raise, read after the mixer's
# advance so the pose on screen is the sim's `t` and not one frame later.
func _hold_raise(fire: Dictionary) -> void:
	if not _player.has_animation(_clip):
		return
	var t: float = clampf(float(fire.get("t", 0.0)), 0.0, 1.0)
	_player.seek(t * _player.get_animation(_clip).length, true)


func _begin_swap() -> void:
	_swapping = true
	var shown: Node3D = _held.call("drawn_node") as Node3D
	if shown != null:
		_ghost = shown.duplicate() as Node3D
		_ghost.name = "Lowering"
		_grip_r.add_child(_ghost)
		_ghost.global_transform = shown.global_transform
	_start(Phase.LOWER, "lower_" + _class, SWITCH_BLEND_S)


func _finish_swap(want_class: String, want_item: int) -> void:
	if _ghost != null:
		_ghost.get_parent().remove_child(_ghost)
		_ghost.queue_free()
		_ghost = null
	_swapping = false
	if want_class != "":
		_class = want_class
		_item = want_item


func _update_sway(world: Variant, delta: float, look: Vector2, speed_mps: float) -> void:
	if delta <= 0.0:
		return
	_clock += delta
	var turn: Vector2 = Vector2.ZERO
	if _look_seen:
		turn = Vector2(wrapf(look.x - _last_look.x, -PI, PI), look.y - _last_look.y) / delta
	_last_look = look
	_look_seen = true
	var target: Vector3 = Vector3(clampf(-turn.y * LOOK_LAG_S, -LOOK_LAG_MAX_RAD, LOOK_LAG_MAX_RAD), clampf(-turn.x * LOOK_LAG_S, -LOOK_LAG_MAX_RAD, LOOK_LAG_MAX_RAD), 0.0)
	var k: float = 1.0 - exp(-delta / SWAY_TAU_S)
	_sway_rot = _sway_rot.lerp(target, k)
	_bob_amount = lerpf(_bob_amount, clampf(speed_mps / BOB_FULL_SPEED_MPS, 0.0, 1.5), k)
	_bob_phase = wrapf(_bob_phase + speed_mps * delta * BOB_RAD_PER_M, 0.0, TAU)
	var breath: float = 1.0
	if world != null and int(world.player) >= 0:
		breath = clampf(SimRanged.cone_half(world, int(world.player)) / SimRanged.WIDE_HALF, 0.3, 1.5)
	var target_lowered: float = 0.0
	if world != null and int(world.player) >= 0:
		target_lowered = 1.0 - ready_amount(world, int(world.player))
	_lowered = lerpf(_lowered, target_lowered, k)
	var offset: Vector3 = Vector3(sin(_bob_phase) * BOB_X_M * _bob_amount, -absf(cos(_bob_phase)) * BOB_Y_M * _bob_amount, 0.0)
	offset += LOWER_OFFSET * _lowered
	offset += Vector3(sin(_clock * 0.9) * BREATH_M, sin(_clock * 1.7) * BREATH_M * 0.6, 0.0) * breath
	var rot: Vector3 = _sway_rot + Vector3(sin(_clock * 1.1) * BREATH_RAD, cos(_clock * 1.3) * BREATH_RAD, 0.0) * breath
	rot.x += deg_to_rad(LOWER_PITCH_DEG) * _lowered
	_sway.position = offset * sway_scale
	_sway.rotation = rot * sway_scale


# --- what the sim holds -------------------------------------------------------------------------

## The item in the entity's hand that the view draws, or -1 for bare hands: the firearm first, as
## `held_weapon.gd` reads it.
static func equipped_item(world: Variant, entity: int) -> int:
	if SimMelee.is_unarmed(world, entity):
		return -1
	var ranged: Variant = world.components.get_component(entity, "rangedWeapon")
	if ranged is Dictionary:
		return int((ranged as Dictionary).get("source", -1))
	var melee: Variant = world.components.get_component(entity, "meleeWeapon")
	if melee is Dictionary:
		return int((melee as Dictionary).get("source", -1))
	return -1


## The hold class the sim's equipped item asks for: one of CLASSES.
static func hold_class_of(world: Variant, entity: int) -> String:
	if SimMelee.is_unarmed(world, entity):
		return "unarmed"
	var ranged: Variant = world.components.get_component(entity, "rangedWeapon")
	if ranged is Dictionary:
		var base: Variant = SimItems.item_base_of(world, int((ranged as Dictionary).get("source", -1)))
		if base is Dictionary and String(SimItems.base_equip_slot(base as Dictionary)) == "primary":
			return "long"
		return "pistol"
	var melee: Variant = world.components.get_component(entity, "meleeWeapon")
	if melee is Dictionary:
		var base: Variant = SimItems.item_base_of(world, int((melee as Dictionary).get("source", -1)))
		if base is Dictionary:
			var b: Dictionary = base as Dictionary
			var size: Dictionary = b.get("size", {}) as Dictionary
			if String(b.get("family", "")) == "polearm" or int(size.get("w", 1)) >= 2 or int(size.get("h", 1)) >= 4:
				return "melee2"
		return "melee1"
	return "unarmed"


## How ready the entity's hand is, 0 lowered .. 1 steady, read from the `ranged` component only. Idle is
## 0; a raise climbs 0 to 0.5 through the weapon's own raise; a steady aim climbs 0.5 to 1 through its
## settle; Recover is 0.5; Reload and Clearing 0.25. A body that cannot hold an aim apart from its heading
## (`SimAim.holds` false) is 0. No firearm in hand (melee, bare hands) is 1: nothing to lower.
static func ready_amount(world: Variant, entity: int) -> float:
	var rw: Variant = world.components.get_component(entity, "rangedWeapon")
	if not (rw is Dictionary):
		return 1.0
	if not SimAim.holds(world.components, entity):
		return 0.0
	var r: Dictionary = rw as Dictionary
	var state: int = int(r.get("state", SimRanged.FireState.Idle))
	if state == SimRanged.FireState.Idle:
		return 0.0
	if state == SimRanged.FireState.Raise:
		var raise: float = float(maxi(1, SimRanged._raise_of(r)))
		return 0.5 * clampf(1.0 - float(r.get("ticksLeft", 0)) / raise, 0.0, 1.0)
	if state == SimRanged.FireState.Steady:
		var steady: float = float(maxi(1, SimRanged._steady_of(world, r)))
		return 0.5 + 0.5 * clampf(1.0 - float(r.get("ticksLeft", 0)) / steady, 0.0, 1.0)
	if state == SimRanged.FireState.Recover:
		return 0.5
	if state == SimRanged.FireState.Reload or state == SimRanged.FireState.Clearing:
		return 0.25
	return 1.0


## The fire phase the sim is in for an entity, as the arms show it: `{"phase": "idle"|"raise"|"aim"|
## "recover"|"reload", "t": 0..1}`. `raise` carries the progress through the weapon's own raise, from
## 0 at the trigger; Steady is `aim`; Recover and Clearing are `recover`; Reload is `reload`; no
## `rangedWeapon` or Idle is `idle`. Read only: the sim is never written from here.
static func fire_of(world: Variant, entity: int) -> Dictionary:
	var rw: Variant = world.components.get_component(entity, "rangedWeapon")
	if not (rw is Dictionary):
		return {"phase": "idle", "t": 0.0}
	var r: Dictionary = rw as Dictionary
	var state: int = int(r.get("state", SimRanged.FireState.Idle))
	if state == SimRanged.FireState.Raise:
		var length: float = float(maxi(1, SimRanged._raise_of(r)))
		return {"phase": "raise", "t": clampf(1.0 - float(r.get("ticksLeft", 0)) / length, 0.0, 1.0)}
	if state == SimRanged.FireState.Steady:
		return {"phase": "aim", "t": 0.0}
	if state == SimRanged.FireState.Recover or state == SimRanged.FireState.Clearing:
		return {"phase": "recover", "t": 0.0}
	if state == SimRanged.FireState.Reload:
		return {"phase": "reload", "t": 0.0}
	return {"phase": "idle", "t": 0.0}


# --- the view-model lens ------------------------------------------------------------------------

# Every mesh under `root` draws through the view-model copy of its material and casts no shadow.
func _apply_view_lens(root: Node) -> void:
	for mesh in _meshes(root):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mesh.material_override is BaseMaterial3D:
			mesh.material_override = view_material(mesh.material_override as BaseMaterial3D)
			continue
		for s in mesh.mesh.get_surface_count():
			var source: Material = mesh.get_surface_override_material(s)
			if source == null:
				source = mesh.mesh.surface_get_material(s)
			if source is BaseMaterial3D:
				mesh.set_surface_override_material(s, view_material(source as BaseMaterial3D))


## The view-model copy of a material: its own lens and the depth pulled in. Cached per source, and a
## material that already is one is returned as it is.
static func view_material(source: BaseMaterial3D) -> BaseMaterial3D:
	if is_view_material(source):
		return source
	if _view_materials.has(source):
		return _view_materials[source] as BaseMaterial3D
	var copy: BaseMaterial3D = source.duplicate() as BaseMaterial3D
	copy.use_fov_override = true
	copy.fov_override = VIEW_MODEL_FOV_DEG
	copy.use_z_clip_scale = true
	copy.z_clip_scale = Z_CLIP_SCALE
	_view_materials[source] = copy
	return copy


static func is_view_material(material: Variant) -> bool:
	if not (material is BaseMaterial3D):
		return false
	var m: BaseMaterial3D = material as BaseMaterial3D
	return m.use_fov_override and absf(m.fov_override - VIEW_MODEL_FOV_DEG) < 0.001 and m.use_z_clip_scale and m.z_clip_scale <= Z_CLIP_SCALE + 0.000001


## The meshes under `root` with a surface that would draw with the world's lens and depth: a wall
## could cut through it. The gate asks this of the whole view model and wants it empty.
static func unlensed_meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for mesh in _meshes(root):
		var bad: bool = false
		if mesh.material_override != null:
			bad = not is_view_material(mesh.material_override)
		else:
			for s in mesh.mesh.get_surface_count():
				if not is_view_material(mesh.get_active_material(s)):
					bad = true
		if bad:
			out.append(mesh)
	return out


static func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out


# --- what the gate reads ------------------------------------------------------------------------

func arms_loaded() -> bool:
	return _player != null


func held_weapon() -> Node3D:
	return _held


func grip_r() -> Node3D:
	return _grip_r


func grip_l() -> Node3D:
	return _grip_l


func arms_model() -> Node3D:
	return _model


## The class the arms are showing now ("" before the first frame).
func shown_class() -> String:
	return _class


## The clip the arms are playing, by name.
func clip_playing() -> String:
	return _clip


## The playing clip's position in seconds, as the mixer holds it.
func clip_seconds() -> float:
	return _player.current_animation_position if _player != null else 0.0


func phase_name() -> String:
	return String(Phase.keys()[_phase])


## The arms are on screen: loaded, in first person, and not lowered away.
func arms_shown() -> bool:
	return _player != null and _sway.is_visible_in_tree()


func updates() -> int:
	return _updates


func swapping() -> bool:
	return _swapping


## The class's idle anchor for `grip_r`, in camera space, from the kit's own `arms.json`.
func anchor_of(hold_class: String) -> Transform3D:
	var row: Variant = _anchors.get(hold_class)
	if not (row is Dictionary):
		return Transform3D()
	var p: Array = (row as Dictionary).get("position", [0, 0, 0]) as Array
	var r: Array = (row as Dictionary).get("rotation_degrees", [0, 0, 0]) as Array
	var basis: Basis = Basis.from_euler(Vector3(deg_to_rad(float(r[0])), deg_to_rad(float(r[1])), deg_to_rad(float(r[2]))))
	return Transform3D(basis, Vector3(float(p[0]), float(p[1]), float(p[2])))


## The gate's way to read a clip's own pose: play `clip` from `seconds` and apply it now.
func pose_at(clip: String, seconds: float) -> void:
	if _player == null or not _player.has_animation(clip):
		return
	_player.play(clip, 0.0)
	_player.seek(seconds, true)
	_sync_bones()


func _read_anchors() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ARMS_JSON))
	var out: Dictionary = {}
	if not (parsed is Dictionary):
		return out
	var classes: Variant = (parsed as Dictionary).get("classes")
	if not (classes is Dictionary):
		return out
	for name in classes as Dictionary:
		var anchor: Variant = ((classes as Dictionary)[name] as Dictionary).get("anchor")
		if anchor is Dictionary:
			out[String(name)] = anchor
	return out


static func _first(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found: Node = _first(child, type_name)
		if found != null:
			return found
	return null
