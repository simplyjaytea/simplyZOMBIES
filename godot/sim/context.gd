class_name SimContext
extends RefCounted
# What you may do with whatever `presentation/pick.gd`'s `pick_at` found under the cursor, in one
# list the right-click menu draws without deciding anything for itself -- `work_panel.gd`'s rule,
# repeated at every panel this milestone has built: presence is the sim's question alone, so a row
# is offered iff the command behind it would be accepted and a thing you cannot do is simply
# absent rather than a greyed word with a reason attached.
#
# Every row but one reuses a command an existing key already sends: `container.open`, `treat.begin`,
# `rescue`, `use.context` are the E ladder's and T's own verbs, so a colonist offered "open the
# door" here and a player pressing E at the same door run the identical code -- one vocabulary,
# not a second one the menu invented. The exception is "walk here": the stick and the click both
# write a velocity, but only the click is a standing intent the sim has to keep from tick to tick
# while a body crosses the district, and `move`'s shape (a direction, spent the instant it moves
# you) has nowhere to keep a destination. That is `walk.to`, in world.gd.
#
# `sim/` never reads presentation state and never will just because this file sits beside a menu:
# every read here is a module's own predicate (`SimContainers.nearest`, `SimFortify.rung_of`,
# `SimShambler.rescue_target`, ...), the same one `ui/hud.gd`'s action bar and the E/T keys already
# ask. The one place this and hud.gd's `_aid_clause` cannot share code is the treatment row's
# prose: hud.gd lives under `ui/` and `sim/` may not depend on it, so `VERB_PROSE` and
# `_worst_part` below are the same four words and the same ranking a second time, on purpose,
# rather than a dependency arrow this module must never carry.

const SimInventoryRes = preload("res://sim/modules/inventory.gd")
const SimContainersRes = preload("res://sim/modules/containers.gd")
const SimFortifyRes = preload("res://sim/modules/fortify.gd")
const SimVehiclesRes = preload("res://sim/modules/vehicles.gd")
const SimTreatmentRes = preload("res://sim/modules/treatment.gd")
const SimConditionRes = preload("res://sim/condition.gd")
const SimShamblerRes = preload("res://sim/modules/shambler.gd")
const SimRecruitsRes = preload("res://sim/modules/recruits.gd")
const SimCampRes = preload("res://sim/modules/camp.gd")
const SimPathRes = preload("res://sim/path.gd")
const SimItemsRes = preload("res://sim/modules/items.gd")

# A tile more than this from the actor reads as a walk *over* rather than a walk *here* -- the same
# distinction the word already carries in speech, an errand across the street versus a step to the
# side. Cosmetic only: both rows carry the identical `walk.to` command.
const WALK_OVER_METRES: float = 3.0

# hud.gd's own table, kept here a second time -- see the header for why a shared const cannot cross
# the sim/ui boundary.
const VERB_PROSE: Dictionary = {
	"pressure": "press",
	"bandage": "dress",
	"clean": "clean",
	"close": "stitch",
}


static func _name_of(world: Variant, entity: int, fallback: String) -> String:
	var ident: Variant = world.components.get_component(entity, "identity")
	if ident is Dictionary:
		var name: String = String((ident as Dictionary).get("name", ""))
		if not name.is_empty():
			return name
	return fallback


static func _tile_of(world: Variant, actor: int) -> Vector2i:
	var p: Variant = world.components.get_component(actor, "position")
	if not (p is Dictionary):
		return Vector2i(-1, -1)
	return Vector2i(floori(float((p as Dictionary)["x"])), floori(float((p as Dictionary)["y"])))


static func _within(world: Variant, actor: int, other: int, reach: float) -> bool:
	var a: Variant = world.components.get_component(actor, "position")
	var b: Variant = world.components.get_component(other, "position")
	if not (a is Dictionary) or not (b is Dictionary):
		return false
	var dx: float = float((b as Dictionary)["x"]) - float((a as Dictionary)["x"])
	var dy: float = float((b as Dictionary)["y"]) - float((a as Dictionary)["y"])
	return dx * dx + dy * dy <= reach * reach


# The same ranking `ui/hud.gd`'s `_worst_part` uses: bleeding first, because blood loss is the only
# thing on this ladder that kills; otherwise the first wounded part the condition view names.
static func _worst_part(world: Variant, patient: int) -> String:
	var view: Dictionary = SimConditionRes.view(world, patient)
	if view.is_empty():
		return ""
	var wounded: String = ""
	for entry in view.get("parts", []) as Array:
		var d: Dictionary = entry as Dictionary
		if bool(d.get("bleeding", false)):
			return String(d.get("part", ""))
		if wounded.is_empty() and bool(d.get("wounded", false)):
			wounded = String(d.get("part", ""))
	return wounded


static func _treat_row(world: Variant, actor: int, patient: int) -> Dictionary:
	var part: String = _worst_part(world, patient)
	if part.is_empty():
		return {}
	var verb: String = ""
	for option in SimTreatmentRes.options_for(world, actor, patient, part):
		var o: Dictionary = option as Dictionary
		if bool(o.get("ok", false)):
			verb = String(o.get("verb", ""))
			break
	if verb.is_empty() or not VERB_PROSE.has(verb):
		return {}
	var label: String = SimConditionRes.label_of(part)
	var who: String = "your" if patient == actor else "%s's" % _name_of(world, patient, "their")
	var text: String = "%s %s %s" % [String(VERB_PROSE[verb]), who, label]
	return {"text": text, "command": {"type": "treat.begin", "patient": patient, "part": part, "verb": verb}, "target": patient}


static func _vehicle_row_text(world: Variant, actor: int, car: int) -> String:
	var v: Variant = world.components.get_component(car, "vehicle")
	var cls: String = String((v as Dictionary).get("class", "")) if v is Dictionary else ""
	var entry: Dictionary = SimVehiclesRes.class_of(world, cls)
	var name: String = String(entry.get("name", "car")).to_lower()
	if SimVehiclesRes.at_hood(world, actor, car):
		if SimVehiclesRes.refuel_problem(world, actor, car).is_empty():
			return "fill the %s's tank" % name
		return "look under the %s's hood" % name
	if SimVehiclesRes.has_cab(entry):
		return "get in the %s" % name
	return "get on the %s" % name


## The rows the menu should draw for whatever `hit` names, in the sim's own order: what is in
## reach first, then what is true anywhere (attack, look, walk, the standing-still verbs). `actor`
## is always the controlled body -- the menu is the player's own, never an NPC's.
static func verbs_at(world: Variant, actor: int, hit: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if world == null or actor < 0 or hit.is_empty():
		return rows
	var kind: String = String(hit.get("kind", "ground"))
	var entity: int = int(hit.get("entity", -1))
	var tile: Vector2i = hit.get("tile", Vector2i(-1, -1)) as Vector2i

	# --- in reach ---------------------------------------------------------------------------
	if kind == "item" and entity >= 0 and _within(world, actor, entity, SimInventoryRes.PICKUP_REACH):
		var name: String = SimItemsRes.item_name(world, entity).to_lower()
		rows.append({"text": "pick up the %s" % name, "command": {"type": "item.pickup", "item": entity}, "target": entity})

	if kind == "container" and entity >= 0:
		if int(SimContainersRes.nearest(world, actor, false, SimContainersRes.Want.Openable)) == entity:
			var s: Variant = world.components.get_component(entity, "searchable")
			var label: String = String((s as Dictionary).get("kind", SimContainersRes.DEFAULT_KIND)) if s is Dictionary else SimContainersRes.DEFAULT_KIND
			rows.append({"text": "open the %s" % label, "command": {"type": "container.open", "container": entity}, "target": entity})

	if kind == "door" and tile.x >= 0:
		var reach_tile: Vector2i = SimFortifyRes._door_in_reach(world, actor)
		if reach_tile == tile:
			var d: Variant = SimFortifyRes.door_state(world, tile.x, tile.y)
			var is_open: bool = d is Dictionary and bool((d as Dictionary).get("open", false))
			rows.append({"text": "shut the door" if is_open else "open the door", "command": {"type": "door.toggle", "tx": tile.x, "ty": tile.y}, "target": -1})

	var rung: Dictionary = SimFortifyRes.rung_of(world, actor)
	if not rung.is_empty():
		var rung_target: Variant = rung.get("target", -1)
		var matches: bool = (rung_target is Vector2i and (rung_target as Vector2i) == tile) or (not (rung_target is Vector2i) and int(rung_target) >= 0 and int(rung_target) == entity)
		if matches:
			rows.append({"text": String(rung.get("prose", "")), "command": {"type": "use.context"}, "target": -1})

	if kind == "vehicle" and entity >= 0 and int(SimVehiclesRes.nearest_in_reach(world, actor)) == entity:
		rows.append({"text": _vehicle_row_text(world, actor, entity), "command": {"type": "use.context"}, "target": -1})

	if kind == "colonist" and entity >= 0:
		var treat_row: Dictionary = _treat_row(world, actor, entity)
		if not treat_row.is_empty():
			rows.append(treat_row)
		if int(SimShamblerRes.rescue_target(world, actor)) == entity:
			rows.append({"text": "pull %s free" % _name_of(world, entity, "them"), "command": {"type": "rescue"}, "target": entity})
		if int(SimRecruitsRes.waiting_in_reach(world, actor)) == entity:
			rows.append({"text": "talk to them", "command": {"type": "use.context"}, "target": -1})

	# --- anywhere -----------------------------------------------------------------------------
	if (kind == "zombie" or kind == "raider") and entity >= 0:
		rows.append({"text": "attack", "command": {"type": "attack.context", "target": entity}, "target": entity})

	if kind == "colonist" and entity >= 0:
		rows.append({"text": "look at %s" % _name_of(world, entity, "them"), "command": {}, "target": entity})

	if tile.x >= 0:
		var here: Vector2i = _tile_of(world, actor)
		if tile != here and SimPathRes.walkable(world, tile.x, tile.y):
			var from: Variant = world.components.get_component(actor, "position")
			var fx: float = float((from as Dictionary)["x"]) if from is Dictionary else float(here.x) + 0.5
			var fy: float = float((from as Dictionary)["y"]) if from is Dictionary else float(here.y) + 0.5
			var dx: float = float(tile.x) + 0.5 - fx
			var dy: float = float(tile.y) + 0.5 - fy
			var word: String = "walk over" if dx * dx + dy * dy > WALK_OVER_METRES * WALK_OVER_METRES else "walk here"
			rows.append({"text": word, "command": {"type": "walk.to", "tx": tile.x, "ty": tile.y}, "target": -1})
		if tile == here:
			var home: int = SimCampRes.home_of(world)
			if home >= 0 and SimCampRes.tile_of(world, home) == here:
				rows.append({"text": "strike the camp", "command": {"type": "camp.abandon"}, "target": -1})
			elif SimCampRes.can_establish(world, tile.x, tile.y):
				rows.append({"text": "make camp here", "command": {"type": "camp.establish", "tx": tile.x, "ty": tile.y}, "target": -1})
			rows.append({"text": "shout", "command": {"type": "shout"}, "target": -1})

	return rows
