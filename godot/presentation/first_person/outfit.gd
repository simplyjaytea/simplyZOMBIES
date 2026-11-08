extends RefCounted
# The outfit resolver (docs/44, "The resolver"): a body's worn equipment becomes its picture. Presentation
# only: pure and static, it writes no component, draws nothing, and keeps no state beyond the manifest it
# reads once. `godot/sim/` never reads this file.
#
# The picture: {layers: [{family, variant, node, slot, layer}], paint: [], hair, hairNode, sleeve, hand,
# handExtra, errors}. The three callers (`body_view.gd`, `own_body.gd`, `arms_view.gd`) are the only places
# that ask for it, and nothing else decides what a body wears.
#
# What it reads, and only this: each worn slot's base id (`itemBase.baseId`), and whether the vest's
# `plate` slot holds a part (`SimAttachments.in_slot`). It never reads tier, condition, affixes, or what a
# container holds. The manifest's `parts` and `drawnBeyond` are not read here: they describe what a worn
# item covers, and the coverage gate reads them.
#
# Draw order: torso layers `inner` < `mid` < the vest slot < `over`, then everything else (back, head,
# belt, face, eyes, gloves, legs, feet). A vest under a torso item on the `over` layer shows no node, when
# that item draws one (the reading docs/44 leaves open is recorded in REPORT-code.md as a card).
#
# A `none` entry draws nothing. A base id missing from the manifest is an error in `errors`, which the
# OUTFIT lane plants and asserts on: it is never a silent skip.

const SimAttachments = preload("res://sim/modules/attachments.gd")
const MANIFEST_PATH: String = "res://assets/first_person/clothing/clothing.json"
const LAYER_DIR: String = "res://assets/first_person/clothing/"
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


## The picture for one body, from its sim equipment. Reads the base ids in the worn slots and the vest's
## plate, then resolves them. The sim is read through `SimItems` and `SimAttachments`, never a raw component
## other than `itemBase`.
static func picture_for(world: Variant, entity: int) -> Dictionary:
	var worn: Dictionary = {}
	var plate: bool = false
	var eq: Variant = world.components.get_component(entity, "equipment")
	var slots: Dictionary = {}
	if eq is Dictionary:
		slots = (eq as Dictionary).get("slots", {}) as Dictionary
	for slot in WORN_SLOTS:
		if not slots.has(slot):
			continue
		var item: int = int(slots[slot])
		var base: Variant = world.components.get_component(item, "itemBase")
		worn[slot] = String((base as Dictionary).get("baseId", "")) if base is Dictionary else ""
	if slots.has("vest"):
		plate = SimAttachments.in_slot(world, int(slots["vest"]), "plate") >= 0
	return resolve(manifest(), worn, plate)


## The pure resolver. `worn` maps a worn slot name to its base id; `plate` says whether the vest holds a
## plate. `manifest` is the parsed clothing.json (or an edited copy, for the gate's plants).
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
		var node: String = String(variants[variant])
		var layer: String = String(entry.get("layer", ""))
		if slot == "vest":
			vest_entry = {"family": family, "variant": variant, "node": node, "slot": slot, "layer": layer, "rank": layer_rank}
		else:
			drawn.append({"family": family, "variant": variant, "node": node, "slot": slot, "layer": layer, "rank": layer_rank})
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
	var hand_extras: Dictionary = manifest_data.get("handExtras", {}) as Dictionary
	return {
		"layers": layers,
		"paint": [],
		"hair": hair_state,
		"hairNode": hair_node,
		"sleeve": sleeve,
		"hand": hand,
		"handExtra": String(hand_extras.get(hand, "")),
		"errors": errors,
	}


## Node names a body's model should show for `picture`, or the model's hair nodes to toggle: the one named
## by `hairNode` is visible, every other hair node is hidden. A model without the node is left as it is.
static func apply_hair(model: Node, picture: Dictionary) -> void:
	var wanted: String = String(picture.get("hairNode", ""))
	for name in ["hair", "hair_tucked"]:
		var found: Node = model.find_child(name, true, false)
		if found is Node3D:
			(found as Node3D).visible = name == wanted


## Dresses the body whose model root is `root` with its picture, when the picture changed since `cache` last
## saw it (`cache` maps entity to the last key). Returns the picture either way.
static func dress(root: Node3D, world: Variant, entity: int, cache: Dictionary) -> Dictionary:
	var picture: Dictionary = picture_for(world, entity)
	var key: String = JSON.stringify(picture)
	if String(cache.get(entity, "")) == key:
		return picture
	cache[entity] = key
	apply_hair(root, picture)
	attach_layers(root, picture)
	return picture


## Instances each shown layer's family GLB under the body's `Outfit` holder, showing only the layer's own node.
## A family whose GLB is not in the build is skipped: it draws nothing and the gate says so. Returns the node
## names shown. Attached under the model root, not bound to the skeleton: skinned layers wait for round 2.
static func attach_layers(root: Node3D, picture: Dictionary) -> Array:
	var holder: Node3D = root.get_node_or_null("Outfit") as Node3D
	if holder == null:
		holder = Node3D.new()
		holder.name = "Outfit"
		root.add_child(holder)
	for old in holder.get_children():
		holder.remove_child(old)
		old.queue_free()
	var families: Dictionary = manifest().get("families", {}) as Dictionary
	var shown: Array = []
	for layer in picture.get("layers", []) as Array:
		var fam: Dictionary = families.get(String(layer["family"]), {}) as Dictionary
		var path: String = LAYER_DIR + String(fam.get("glb", ""))
		if String(fam.get("glb", "")).is_empty() or not ResourceLoader.exists(path):
			continue
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			continue
		var instance: Node = packed.instantiate()
		var want: String = String(layer["node"])
		# The GLB's top-level nodes are its variants: show the layer's own, hide the rest.
		for child in instance.get_children():
			if child is Node3D:
				(child as Node3D).visible = String(child.name) == want
		holder.add_child(instance)
		shown.append(want)
	return shown
