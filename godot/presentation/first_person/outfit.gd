extends RefCounted
# The outfit resolver (docs/44, "The resolver"): a body's worn equipment becomes its picture. Presentation
# only: pure and static, it writes no component, draws nothing, and keeps no state beyond the manifest it
# reads once and the per-body cache the callers hand in. `godot/sim/` never reads this file.
#
# The picture: {layers: [{family, variant, node, slot, layer}], paint: [], hair, hairNode, sleeve, hand,
# handExtra, errors}. The three callers (`body_view.gd`, `own_body.gd`, `arms_view.gd`) are the only places
# that ask for it, and nothing else decides what a body wears.
#
# What it reads, and only this: each worn slot's base id (`itemBase.baseId`), and whether the vest's `plate`
# slot holds a part (`SimAttachments.in_slot`). It never reads tier (`itemTier`), condition, affixes, a
# container's contents, a corpse marker, or an archetype. The manifest's `parts` and `drawnBeyond` describe
# what a worn item covers, and the coverage gate reads them; the drawn parts are `parts` + `drawnBeyond`.
#
# Draw order: torso layers `inner` < `mid` < the vest slot < `over`, then everything else. A vest under a torso
# item on the `over` layer shows no node, when that item draws one (the reading docs/44 leaves open is the
# default in docs/30).
#
# A `none` entry draws nothing. A base id missing from the manifest is an error in `errors`, which the OUTFIT
# lane plants and asserts on: it is never a silent skip.

const SimAttachments = preload("res://sim/modules/attachments.gd")

const MANIFEST_PATH: String = "res://assets/first_person/clothing/clothing.json"
const LAYER_DIR: String = "res://assets/first_person/clothing/"
# Metadata on each layer mesh this file attached, so a re-dress removes exactly its own meshes.
const LAYER_META: String = "outfit_layer"
const MISSING_BONES_META: String = "outfit_missing_bones"
# The worn slots, the sim's clothing slots (`inventory.gd` EQUIP_SLOTS minus the weapon slots).
const WORN_SLOTS: Array[String] = ["back", "vest", "belt", "head", "face", "eyes", "torso", "gloves", "legs", "feet"]
# Draw rank: torso layers first (inner 0, mid 1, the vest 2, over 3), then the rest (4).
const RANK_VEST: int = 2
const RANK_OTHER: int = 4
const LAYER_RANK: Dictionary = {"inner": 0, "mid": 1, "over": 3}
const HAIR_RANK: Dictionary = {"default": 0, "tucked": 1, "hidden": 2}
const DEFAULT_SLEEVE: String = "knit"
const DEFAULT_HAND: String = "bare"

static var _manifest: Dictionary = {}
static var _loaded: bool = false


## The published manifest, read once. {} when the file is missing or not a JSON object.
static func manifest() -> Dictionary:
	if not _loaded:
		_loaded = true
		var text: String = FileAccess.get_file_as_string(MANIFEST_PATH) if FileAccess.file_exists(MANIFEST_PATH) else ""
		var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
		_manifest = parsed as Dictionary if parsed is Dictionary else {}
	return _manifest


## The worn base ids of `entity` (slot -> base id) and whether its vest holds a plate. The only sim reads the
## resolver makes.
static func worn_of(world: Variant, entity: int) -> Dictionary:
	var worn: Dictionary = {}
	var slots: Dictionary = {}
	var eq: Variant = world.components.get_component(entity, "equipment")
	if eq is Dictionary:
		slots = (eq as Dictionary).get("slots", {}) as Dictionary
	for slot in WORN_SLOTS:
		if not slots.has(slot):
			continue
		var base: Variant = world.components.get_component(int(slots[slot]), "itemBase")
		worn[slot] = String((base as Dictionary).get("baseId", "")) if base is Dictionary else ""
	var plate: bool = slots.has("vest") and SimAttachments.in_slot(world, int(slots["vest"]), "plate") >= 0
	return {"worn": worn, "plate": plate}


## The cheap key a body is dressed by: its worn base ids and the vest's plate. Equal keys draw equal pictures,
## so a caller resolves only when the key changes.
static func worn_key(world: Variant, entity: int) -> String:
	var read: Dictionary = worn_of(world, entity)
	var worn: Dictionary = read["worn"] as Dictionary
	var parts: PackedStringArray = []
	for slot in WORN_SLOTS:
		if worn.has(slot):
			parts.append("%s=%s" % [slot, String(worn[slot])])
	parts.append("plate=%s" % str(bool(read["plate"])))
	return ";".join(parts)


## The picture for one body, from its sim equipment.
static func picture_for(world: Variant, entity: int) -> Dictionary:
	var read: Dictionary = worn_of(world, entity)
	return resolve(manifest(), read["worn"] as Dictionary, bool(read["plate"]))


## The pure resolver. `worn` maps a worn slot name to its base id; `plate` says whether the vest holds a
## plate. `manifest_data` is the parsed clothing.json, or an edited copy for the gate's plants.
static func resolve(manifest_data: Dictionary, worn: Dictionary, plate: bool) -> Dictionary:
	var items: Dictionary = manifest_data.get("items", {}) as Dictionary
	var families: Dictionary = manifest_data.get("families", {}) as Dictionary
	var errors: Array[String] = []
	var drawn: Array = []
	var torso_layer: String = ""
	var torso_draws: bool = false
	var hair_state: String = "default"
	var sleeve: String = DEFAULT_SLEEVE
	var hand: String = DEFAULT_HAND
	var vest_entry: Dictionary = {}
	for slot in worn:
		var base_id: String = String(worn[slot])
		if not items.has(base_id):
			errors.append("%s: %s is not in the clothing manifest" % [slot, base_id])
			continue
		var entry: Dictionary = items[base_id] as Dictionary
		if entry.has("hair") and HAIR_RANK.get(String(entry["hair"]), -1) > HAIR_RANK[hair_state]:
			hair_state = String(entry["hair"])
		if slot == "torso":
			if entry.has("sleeve"):
				sleeve = String(entry["sleeve"])
			torso_layer = String(entry.get("layer", "mid"))
		if slot == "gloves" and entry.has("hand"):
			hand = String(entry["hand"])
		if not entry.has("family"):
			continue
		var family: String = String(entry["family"])
		if not families.has(family):
			errors.append("%s: family %s is not in the manifest" % [base_id, family])
			continue
		var variants: Dictionary = (families[family] as Dictionary).get("variants", {}) as Dictionary
		var variant: String = String(entry.get("variant", "default"))
		if entry.has("loadedWhen") and String(entry["loadedWhen"]) == "plate":
			variant = "loaded" if plate else "flat"
		if not variants.has(variant):
			errors.append("%s: variant %s is not in family %s" % [base_id, variant, family])
			continue
		var layer_rank: int = RANK_OTHER
		if slot == "torso":
			layer_rank = int(LAYER_RANK.get(String(entry.get("layer", "mid")), 1))
			torso_draws = true
		elif slot == "vest":
			layer_rank = RANK_VEST
		var draw: Dictionary = {"family": family, "variant": variant, "node": String(variants[variant]), "slot": slot,
			"layer": String(entry.get("layer", "")), "rank": layer_rank}
		if slot == "vest":
			vest_entry = draw
		else:
			drawn.append(draw)
	# A carrier under an `over` torso item that draws a node shows no node.
	var over_covers_vest: bool = torso_draws and torso_layer == "over"
	if not vest_entry.is_empty() and not over_covers_vest:
		drawn.append(vest_entry)
	drawn.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["rank"]) != int(b["rank"]):
			return int(a["rank"]) < int(b["rank"])
		return String(a["slot"]) < String(b["slot"]))
	var layers: Array = []
	for d in drawn:
		layers.append({"family": d["family"], "variant": d["variant"], "node": d["node"], "slot": d["slot"], "layer": d["layer"]})
	var hair_nodes: Dictionary = manifest_data.get("hair", {}) as Dictionary
	var hair_node: String = String(hair_nodes.get(hair_state, "")) if hair_state != "hidden" else ""
	# Tucked hair leaves survivor.glb for its own GLB when the manifest names one (hair.tuckedGlb, additive).
	var hair_glb: String = String(hair_nodes.get("tuckedGlb", "")) if hair_state == "tucked" else ""
	var hand_extras: Dictionary = manifest_data.get("handExtras", {}) as Dictionary
	return {
		"layers": layers,
		"paint": [],
		"hair": hair_state,
		"hairNode": hair_node,
		"hairGlb": hair_glb,
		"sleeve": sleeve,
		"hand": hand,
		"handExtra": String(hand_extras.get(hand, "")),
		"errors": errors,
	}


## The survivor's own hair. Default: survivor `hair` shows. Tucked: the tucked GLB shows (attached by `attach_layers`),
## and survivor `hair` is hidden; a survivor still carrying `hair_tucked` (before the GLB exists) shows that node
## instead. Hidden: neither. A model without a node is left as it is.
static func apply_hair(model: Node, picture: Dictionary) -> void:
	var state: String = String(picture.get("hair", "default"))
	var glb_drawn: bool = not String(picture.get("hairGlb", "")).is_empty()
	var wanted_survivor: String = "hair" if state == "default" else ("hair_tucked" if state == "tucked" and not glb_drawn else "")
	for name in ["hair", "hair_tucked"]:
		var found: Node = model.find_child(name, true, false)
		if found is Node3D:
			(found as Node3D).visible = name == wanted_survivor


## Dresses the body whose model root is `root`, when its worn key changed since `cache` last saw it. `cache`
## maps entity to {key, picture}. Returns the body's picture: fresh when the key changed, else the cached one.
static func dress(root: Node3D, world: Variant, entity: int, cache: Dictionary) -> Dictionary:
	var key: String = worn_key(world, entity)
	var held: Dictionary = cache.get(entity, {}) as Dictionary
	if not held.is_empty() and String(held["key"]) == key:
		return held["picture"] as Dictionary
	var picture: Dictionary = picture_for(world, entity)
	cache[entity] = {"key": key, "picture": picture}
	apply_hair(root, picture)
	attach_layers(root, picture)
	return picture


## Instances each shown layer's family GLB and moves its own variant mesh onto the body's Skeleton3D, so the
## layer moves with the body's bones. Each mesh is bound by bone name: a bone the body's skeleton does not have
## is recorded on the mesh (`MISSING_BONES_META`), never skipped quietly. A family whose GLB is not in the
## build is skipped: it draws nothing, and the gate names it. A body with no skeleton gets the layers under an
## `Outfit` holder on its root. Returns {shown, bound, missing_bones}. Re-dressing removes the previous layers.
static func attach_layers(root: Node3D, picture: Dictionary) -> Dictionary:
	var skeleton: Skeleton3D = _skeleton_of(root)
	var host: Node3D = skeleton if skeleton != null else _holder(root)
	for old in host.get_children():
		if old.has_meta(LAYER_META):
			host.remove_child(old)
			old.queue_free()
	var families: Dictionary = manifest().get("families", {}) as Dictionary
	var shown: Array = []
	var missing: Array = []
	for layer in picture.get("layers", []) as Array:
		var fam: Dictionary = families.get(String(layer["family"]), {}) as Dictionary
		var glb: String = String(fam.get("glb", ""))
		var path: String = LAYER_DIR + glb
		if glb.is_empty() or not ResourceLoader.exists(path):
			continue
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			continue
		_attach_variant(packed, String(layer["node"]), host, skeleton, shown, missing)
	var hair_glb: String = String(picture.get("hairGlb", ""))
	if not hair_glb.is_empty() and ResourceLoader.exists(LAYER_DIR + hair_glb):
		var hair_packed: PackedScene = load(LAYER_DIR + hair_glb) as PackedScene
		if hair_packed != null:
			_attach_variant(hair_packed, "hair_tucked", host, skeleton, shown, missing)
	return {"shown": shown, "bound": skeleton != null, "missing_bones": missing}


# One variant mesh of a GLB, moved onto `host` (the body's skeleton when there is one) and bound by bone name.
static func _attach_variant(packed: PackedScene, want: String, host: Node3D, skeleton: Skeleton3D, shown: Array, missing: Array) -> void:
	var instance: Node = packed.instantiate()
	var source_bones: Array = _bone_names_under(instance)
	for mesh in instance.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mesh as MeshInstance3D
		if m.name != want:
			continue
		var rel: Transform3D = _within(m, instance)
		m.get_parent().remove_child(m)
		host.add_child(m)
		m.transform = rel
		m.set_meta(LAYER_META, true)
		var gone: Array = []
		if skeleton != null:
			m.skeleton = NodePath("..")
			for bone in source_bones:
				if skeleton.find_bone(String(bone)) < 0:
					gone.append(String(bone))
		m.set_meta(MISSING_BONES_META, gone)
		missing.append_array(gone)
		shown.append(want)
	instance.queue_free()


## The body's Skeleton3D, or null when its model has none.
static func _skeleton_of(root: Node) -> Skeleton3D:
	for found in root.find_children("*", "Skeleton3D", true, false):
		return found as Skeleton3D
	return null


static func _holder(root: Node3D) -> Node3D:
	var holder: Node3D = root.get_node_or_null("Outfit") as Node3D
	if holder == null:
		holder = Node3D.new()
		holder.name = "Outfit"
		root.add_child(holder)
	return holder


static func _bone_names_under(node: Node) -> Array:
	var names: Array = []
	for found in node.find_children("*", "Skeleton3D", true, false):
		var skel: Skeleton3D = found as Skeleton3D
		for i in skel.get_bone_count():
			names.append(skel.get_bone_name(i))
	return names


## The transform of `node` relative to `ancestor`, by multiplying the locals up the chain.
static func _within(node: Node3D, ancestor: Node) -> Transform3D:
	var t: Transform3D = Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != ancestor:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
