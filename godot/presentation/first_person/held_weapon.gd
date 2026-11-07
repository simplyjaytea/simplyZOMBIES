extends Node3D
# The equipped weapon in the first-person view, built from the sim's own parts. Its model's origin is
# `grip_r` (the weapon kit's held pose), so the model is parented with an identity transform under the
# grip node. `arms_view.gd` mounts that grip node under the arms' own `grip_r` bone (`mount`), so the
# hand holds it and the clips move it; without the arms it hangs off the camera at the lower right,
# at the anchor below, with its own small sway.
#
# What is drawn is read, not decided:
#   rangedWeapon.source   the equipped firearm item; its base id names the receiver model.
#   meleeWeapon.source    the equipped melee item; its whole model is drawn and no parts are added
#                         (the fire axe already draws its own head and haft, so the content's
#                         defaultParts must not be stacked on top).
#   SimAttachments        every fitted part, by slot; each part's model is parented under the
#                         receiver's `socket_<slot>`, except a muzzle device, which goes under the
#                         installed barrel's own `socket_muzzle` when the barrel carries one.
# The visible set is rebuilt only when the assembly changes (equip, a field swap, a bench), compared
# by base ids, so a frame that changes nothing does no model work.
#
# Hidden slots are skipped in the held view: `internal`, `spring`, `sear` and `extractor` sit inside
# the receiver and are unseen in hand, and skipping them saves 324 triangles on a default pistol.
# A part with no model leaves its socket empty and is listed in `missing_parts()`; it is never
# replaced by a default. An item with no model keeps the interim placeholder box, sized by its
# profile, so the screen still says something is in hand.
#
# Presentation only: no sim component is written. The model is visual; the sim decides every hit.
# Materials come from the manifest loader (`models.gd`): one shared, mipmapped texture per atlas.
#
# THE MODEL SEAM. `godot/presentation/first_person/models.gd` (the manifest loader) is the only
# loader. `_weapon_entry` resolves the manifest entry, passing the host receiver for a part, and
# `Models.instance_of` creates the instance. The item's class is read from its content base, exactly
# as `loose_view.gd` reads it. There is no second loader here, and no fallback: an item the manifests
# do not name keeps the placeholder box.

const SimItems = preload("res://sim/modules/items.gd")
const SimAttachments = preload("res://sim/modules/attachments.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const Models = preload("res://presentation/first_person/models.gd")

# The held anchor: lower right, a little below the eye, angled inward. The model is real scale
# (a service pistol is 192 mm), so it sits close to the eye.
const MODEL_POSITION: Vector3 = Vector3(0.22, -0.20, -0.45)
const MODEL_ROTATION_DEG: Vector3 = Vector3(-6.0, 14.0, 0.0)
# The interim box's own anchor, kept from the fight piece so the fallback reads as it did.
const PLACEHOLDER_POSITION: Vector3 = Vector3(0.33, -0.24, -0.58)
const PLACEHOLDER_ROTATION_DEG: Vector3 = Vector3(-6.0, 14.0, 0.0)
# A little sway so a still body is not a welded prop; the camera kick moves this with the view.
const SWAY_POSITION_M: float = 0.003
const SWAY_ROTATION_RAD: float = 0.004

var _pivot: Node3D = null
# Between the grip node and what is drawn: the arms hide it while a copy of the old model is lowered.
var _in_hand: Node3D = null
var _mounted: bool = false
# Counts rebuilds, so the arms know when there are new meshes to put through the view-model lens.
var _revision: int = 0
var _model: Node3D = null
var _receiver: Node3D = null
var _placeholder: MeshInstance3D = null
var _placeholder_size: Vector3 = Vector3.ZERO
# {slot: base_id} for what is drawn, plus "receiver"; the socket each part sits under, by name and
# node; and the part nodes themselves.
var _drawn: Dictionary = {}
var _drawn_sockets: Dictionary = {}
var _drawn_parents: Dictionary = {}
var _part_nodes: Dictionary = {}
var _missing: Array[String] = []
var _signature: String = ""
var _armed: bool = false
var _ranged_drawn: bool = false


func _ready() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Grip"
	_pivot.position = MODEL_POSITION
	_pivot.rotation_degrees = MODEL_ROTATION_DEG
	add_child(_pivot)
	_in_hand = Node3D.new()
	_in_hand.name = "InHand"
	_pivot.add_child(_in_hand)
	_build_placeholder()


## Moves the grip node under `parent` (the arms' `grip_r`) with an identity transform. From then on the
## parent places the weapon; the eye anchor and its sway are not used.
func mount(parent: Node3D) -> void:
	if _pivot == null or parent == null:
		return
	_pivot.get_parent().remove_child(_pivot)
	parent.add_child(_pivot)
	_pivot.transform = Transform3D.IDENTITY
	_mounted = true
	_placeholder.position = Vector3.ZERO
	_placeholder.rotation = Vector3.ZERO


## Shows or hides what is drawn in the hand, without changing what is drawn.
func set_in_hand(shown: bool) -> void:
	if _in_hand != null:
		_in_hand.visible = shown


func revision() -> int:
	return _revision


## The grip node: the weapon's frame, under the arms' `grip_r` once mounted.
func grip_node() -> Node3D:
	return _pivot


## What is drawn in the hand now: the assembled model, the placeholder box, or null.
func drawn_node() -> Node3D:
	if not visible_any():
		return null
	if _model != null:
		return _model
	return _placeholder if _placeholder.visible else null


func _build_placeholder() -> void:
	_placeholder = MeshInstance3D.new()
	_placeholder.name = "ItemWithoutModel"
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.08, 0.09, 0.45)
	_placeholder.mesh = box
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.36, 0.31, 0.24)
	material.roughness = 1.0
	_placeholder.material_override = material
	_placeholder.position = PLACEHOLDER_POSITION
	_placeholder.rotation_degrees = PLACEHOLDER_ROTATION_DEG
	_placeholder.visible = false
	_in_hand.add_child(_placeholder)


## Reads the equipped item and redraws when its assembly changed. `now` is presentation seconds for
## the sway; `hide` is the end panel. Called once a frame.
func update(world: Variant, now: float, hide: bool = false) -> void:
	if _pivot == null:
		return
	if world == null or hide:
		_set_shown(false)
		return
	var player: int = int(world.player)
	if SimMelee.is_unarmed(world, player):
		_set_shown(false)
		return
	_armed = true
	var ranged: Variant = world.components.get_component(player, "rangedWeapon")
	var melee: Variant = world.components.get_component(player, "meleeWeapon")
	var item: int = -1
	var is_ranged: bool = false
	var range_metres: float = 12.0
	var reach: float = 1.0
	if ranged is Dictionary:
		item = int((ranged as Dictionary).get("source", -1))
		is_ranged = true
		range_metres = float((ranged as Dictionary).get("rangeMetres", 12.0))
	elif melee is Dictionary:
		item = int((melee as Dictionary).get("source", -1))
		reach = float((melee as Dictionary).get("reachMetres", 1.0))
	var base_id: String = _base_id(world, item)
	var signature: String = _assembly_signature(world, item, base_id, is_ranged)
	if signature != _signature:
		_signature = signature
		_rebuild(world, item, base_id, is_ranged)
	var has_model: bool = _receiver != null
	_placeholder.visible = not has_model
	if _mounted:
		# The arms' grip bone places the weapon and the arms sway; only the box's size is ours.
		if not has_model:
			_size_placeholder(is_ranged, range_metres, reach)
	elif has_model:
		_placeholder_size = Vector3.ZERO
		_pivot.position = MODEL_POSITION + Vector3(sin(now * 1.6) * SWAY_POSITION_M, cos(now * 2.1) * SWAY_POSITION_M * 0.7, 0.0)
		_pivot.rotation_degrees = MODEL_ROTATION_DEG + Vector3(sin(now * 1.1) * rad_to_deg(SWAY_ROTATION_RAD), cos(now * 1.3) * rad_to_deg(SWAY_ROTATION_RAD), 0.0)
	else:
		_pivot.position = PLACEHOLDER_POSITION + Vector3(sin(now * 1.6) * SWAY_POSITION_M, cos(now * 2.1) * SWAY_POSITION_M * 0.7, 0.0)
		_pivot.rotation_degrees = PLACEHOLDER_ROTATION_DEG
		_size_placeholder(is_ranged, range_metres, reach)
	_pivot.visible = true
	_placeholder.visible = not has_model


func _set_shown(shown: bool) -> void:
	_armed = shown
	_pivot.visible = shown
	_placeholder.visible = false
	if not shown:
		_signature = ""
		_clear_model()
		_drawn = {}
		_drawn_sockets = {}
		_drawn_parents = {}
		_part_nodes = {}
		_missing = []
		_ranged_drawn = false


## Something is in hand and drawn: a model, or the placeholder for an item with no model.
func visible_any() -> bool:
	return _armed and _pivot != null and _pivot.visible


## Presentation-only visibility toggle for screens that cover the view (bench, inventory, ledger, talk,
## third person). Keeps the assembled model and its signature intact so it redraws correctly when the
## screen closes; only the drawn pivot is hidden.
func set_view_visible(shown: bool) -> void:
	if _pivot == null:
		return
	_pivot.visible = shown
	if not shown and _placeholder != null:
		_placeholder.visible = false


## True when the assembly drawn is the assembly the sim holds now. The gate's mismatch negative uses
## it: draw, change the sim's parts, and the drawn set no longer answers true until `update` runs.
func verify(world: Variant) -> bool:
	if not visible_any() or world == null or world.player < 0:
		return false
	var expected: Dictionary = _expected(world, int(world.player))
	if expected.is_empty():
		return false
	if not _drawn.has("receiver") or String(_drawn["receiver"]) != String(expected["receiver"]):
		return false
	for slot in expected["parts"] as Dictionary:
		if not _drawn.has(slot) or String(_drawn[slot]) != String((expected["parts"] as Dictionary)[slot]):
			return false
	return _drawn.size() == (expected["parts"] as Dictionary).size() + 1


func drawn() -> Dictionary:
	return _drawn.duplicate()


func drawn_is_ranged() -> bool:
	return _ranged_drawn


func drawn_slots() -> Array[String]:
	var out: Array[String] = []
	for key in _drawn.keys():
		if String(key) != "receiver":
			out.append(String(key))
	out.sort()
	return out


func receiver_node() -> Node3D:
	return _receiver


func part_node(slot: String) -> Node3D:
	return _part_nodes.get(slot, null) as Node3D


func socket_node(slot: String) -> Node3D:
	return _drawn_parents.get(slot, null) as Node3D


func socket_name(slot: String) -> String:
	return String(_drawn_sockets.get(slot, ""))


func missing_parts() -> Array[String]:
	return _missing.duplicate()


func placeholder_visible() -> bool:
	return _placeholder != null and _placeholder.visible


func _rebuild(world: Variant, item: int, base_id: String, is_ranged: bool) -> void:
	_clear_model()
	_drawn = {}
	_drawn_sockets = {}
	_missing = []
	if base_id == "":
		return
	var spec: Dictionary = _resolve(world, item, base_id)
	if spec.is_empty():
		_missing.append(base_id)
		return
	var receiver: Node3D = _instance(world, item, base_id)
	if receiver == null:
		_missing.append(base_id)
		return
	_model = Node3D.new()
	_model.name = "WeaponModel"
	_in_hand.add_child(_model)
	_revision += 1
	_model.add_child(receiver)
	_receiver = receiver
	_drawn["receiver"] = base_id
	_ranged_drawn = is_ranged
	if not is_ranged:
		# The melee model is whole. The fire axe draws its own head and haft, so the content's
		# default parts are not stacked on it; separate melee part models are a later art piece.
		return
	var sockets: Dictionary = spec.get("sockets", {}) as Dictionary
	var installed: Dictionary = SimAttachments.attached(world, item)
	# The barrel first, because a muzzle device goes on the barrel's own socket_muzzle when it has
	# one, and that node only exists once the barrel is in the tree.
	var barrel_slot: int = int(installed.get("barrel", -1))
	var barrel_node: Node3D = null
	if barrel_slot >= 0:
		barrel_node = _place_part(world, item, "barrel", barrel_slot, receiver, sockets, null)
	var slots: Array = installed.keys()
	slots.sort()
	for slot_v in slots:
		var slot: String = String(slot_v)
		if slot == "barrel" or Models.HIDDEN_SLOTS.has(slot):
			continue
		var part_item: int = int(installed[slot])
		var muzzle_host: Node3D = null
		if slot == "muzzle" and barrel_node != null:
			muzzle_host = barrel_node.find_child("socket_muzzle", true, false) as Node3D
		_place_part(world, item, slot, part_item, receiver, sockets, muzzle_host)


# Returns the placed part's node (the barrel needs it for the muzzle), or null.
func _place_part(world: Variant, host: int, slot: String, part_item: int, receiver: Node3D, sockets: Dictionary, muzzle_host: Node3D) -> Node3D:
	var part_id: String = _base_id(world, part_item)
	if part_id == "":
		_missing.append("slot:%s" % slot)
		return null
	var receiver_id: String = _base_id(world, host)
	var part_spec: Dictionary = _resolve(world, part_item, part_id, receiver_id)
	if part_spec.is_empty():
		_missing.append(part_id)
		return null
	var part: Node3D = _instance(world, part_item, part_id, receiver_id)
	if part == null:
		_missing.append(part_id)
		return null
	var parent: Node3D = muzzle_host
	var socket_name: String = ""
	if parent == null:
		socket_name = String(sockets.get(slot, ""))
		if socket_name == "":
			part.free()
			_missing.append("socket:%s" % slot)
			return null
		parent = receiver.find_child(socket_name, true, false) as Node3D
		if parent == null:
			part.free()
			_missing.append("socket:%s" % slot)
			return null
	else:
		socket_name = "socket_muzzle"
	parent.add_child(part)
	_drawn[slot] = part_id
	_drawn_sockets[slot] = String(parent.name)
	_drawn_parents[slot] = parent
	_part_nodes[slot] = part
	return part


func _expected(world: Variant, player: int) -> Dictionary:
	var ranged: Variant = world.components.get_component(player, "rangedWeapon")
	var melee: Variant = world.components.get_component(player, "meleeWeapon")
	var item: int = -1
	var is_ranged: bool = false
	if ranged is Dictionary:
		item = int((ranged as Dictionary).get("source", -1))
		is_ranged = true
	elif melee is Dictionary:
		item = int((melee as Dictionary).get("source", -1))
	if item < 0:
		return {}
	var base_id: String = _base_id(world, item)
	if base_id == "":
		return {}
	var parts: Dictionary = {}
	if is_ranged:
		var fitted: Dictionary = SimAttachments.attached(world, item)
		for slot_v in fitted.keys():
			var slot: String = String(slot_v)
			if Models.HIDDEN_SLOTS.has(slot):
				continue
			var part_id: String = _base_id(world, int(fitted[slot_v]))
			if part_id != "":
				parts[slot] = part_id
	return {"receiver": base_id, "parts": parts}


func _assembly_signature(world: Variant, item: int, base_id: String, is_ranged: bool) -> String:
	if base_id == "":
		return ""
	var sig: String = "ranged" if is_ranged else "melee"
	sig += "|" + base_id
	if is_ranged and item >= 0:
		var parts: Dictionary = _expected(world, int(world.player))["parts"] as Dictionary
		var names: Array = parts.keys()
		names.sort()
		for slot in names:
			sig += "|%s=%s" % [slot, String(parts[slot])]
	return sig


func _base_id(world: Variant, item: int) -> String:
	if world == null or item < 0:
		return ""
	var base: Variant = SimItems.item_base_of(world, item)
	if not (base is Dictionary):
		return ""
	return String((base as Dictionary).get("id", ""))


func _clear_model() -> void:
	if _model != null:
		_model.queue_free()
		_revision += 1
	_model = null
	_receiver = null


func _size_placeholder(is_ranged: bool, range_metres: float, reach: float) -> void:
	var size: Vector3 = Vector3(0.07, 0.08, 0.45)
	if is_ranged:
		size = Vector3(0.09, 0.10, clampf(0.30 + range_metres * 0.018, 0.38, 0.95))
	else:
		size = Vector3(0.07, 0.07, clampf(0.18 + reach * 0.35, 0.30, 0.85))
	if not size.is_equal_approx(_placeholder_size):
		_placeholder_size = size
		(_placeholder.mesh as BoxMesh).size = size
		if _mounted:
			# In the hand the box runs forward from the grip, as a weapon's bore does (-Z).
			_placeholder.position = Vector3(0.0, 0.02, -size.z * 0.5 + 0.06)


# --- the manifest loader seam ---------------------------------------------------------------
#
# The equipped assembly is the WEAPON KIT's art, so its manifest is asked first. The loot-item kit
# also names some weapon-part ids (a loose barrel on the floor gets its generic attachment shape),
# and `Models.resolve` reads manifests in file-name order, where items come before weapons. Without
# this order the held view would draw the loose-item fallback instead of the barrel's real model,
# whose own `socket_muzzle` the suppressor needs.

const WEAPON_KIT: String = "weapons"


func _weapon_entry(item_id: String, item_class: String, receiver_id: String = "") -> Variant:
	for manifest in Models.manifests():
		if String((manifest as Dictionary).get("kit", "")) != WEAPON_KIT:
			continue
		var found: Variant = Models.resolve_in([manifest], item_id, item_class, receiver_id)
		if found is Dictionary:
			return found
	return Models.resolve(item_id, item_class, receiver_id)


func _resolve(world: Variant, item: int, item_id: String, receiver_id: String = "") -> Dictionary:
	var entry: Variant = _weapon_entry(item_id, _class_of(world, item), receiver_id)
	return entry as Dictionary if entry is Dictionary else {}


func _instance(world: Variant, item: int, item_id: String, receiver_id: String = "") -> Node3D:
	var entry: Variant = _weapon_entry(item_id, _class_of(world, item), receiver_id)
	if not (entry is Dictionary):
		return null
	return Models.instance_of(String((entry as Dictionary).get("glb", "")))


func _class_of(world: Variant, item: int) -> String:
	if world == null or item < 0:
		return ""
	var base: Variant = SimItems.item_base_of(world, item)
	return String((base as Dictionary).get("class", "")) if base is Dictionary else ""
