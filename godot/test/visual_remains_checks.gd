extends RefCounted

# Shared by the zombie presentation gate: the pictures need a real death/save reader as well
# as a texture. Compare death against the pre-art drop/despawn path, not a fabricated result.
const World = preload("res://sim/world.gd")
const Entities = preload("res://sim/entity_store.gd")
const Roster = preload("res://sim/modules/roster.gd")
const Recruits = preload("res://sim/modules/recruits.gd")
const Save = preload("res://sim/save.gd")
const Serialize = preload("res://sim/kernel/serialize.gd")
const Shambler = preload("res://sim/modules/shambler.gd")
const Appearance = preload("res://presentation/appearance.gd")


static func _world() -> Variant:
	return World.new({
		"seed": 20261002,
		"tick_hz": 20,
		"map": {"width": 32, "height": 32, "walls": []},
		"player": {"id": 0, "x": 16.5, "y": 16.5, "stance": 2},
	})


static func run() -> bool:
	if not _turned_survivors_draw_their_type():
		return false
	var w: Variant = _world()
	var entity: int = Roster.spawn_zombie(w, 9.5, 12.25, "zombie.armored", w.rng.stream("shambler"))
	w.tick = 417
	var type_before: Dictionary = (w.components.get_component(entity, "zombieType") as Dictionary).duplicate()
	var control: Variant = _world()
	# Component snapshots retain Dictionary references; independent worlds must not share the
	# same equipment slots while the control unequips them.
	control.restore(w.snapshot().duplicate(true))
	# A genuinely equipped body is necessary to judge the unchanged loot outcome.
	if not w.components.has_component(entity, "equipment"):
		push_error("REMAINS: armored fixture has no equipment; the drop comparison would judge nothing")
		return false
	Recruits._drop_kit(control, entity)
	control.despawn(entity)
	if not Recruits.handle_death(w, entity):
		push_error("REMAINS: a living zombie refused the real death path")
		return false
	var sim_after: Dictionary = w.snapshot()
	sim_after.erase("visualRemains")
	var sim_control: Dictionary = control.snapshot()
	sim_control.erase("visualRemains")
	if Serialize.canonicalize(sim_after) != Serialize.canonicalize(sim_control):
		push_error("REMAINS: death changed simulation state beyond the settled picture (entities, drops, RNG, field or components)")
		return false
	var records: Array = w.visualRemains as Array
	if records.size() != 1:
		push_error("REMAINS: one death must leave one visual record")
		return false
	var expected: Dictionary = {
		"entity": entity, "x": 9.5, "y": 12.25, "ztype": "zombie.armored",
		"tint": String(type_before.get("tint", "")), "sinceTick": 417,
	}
	if Serialize.canonicalize(records[0]) != Serialize.canonicalize(expected):
		push_error("REMAINS: the corpse lost the original identity, location, tint or death tick")
		return false
	var before_repeat: String = w.serialize()
	if Recruits.handle_death(w, entity) or w.serialize() != before_repeat:
		push_error("REMAINS: repeated death of a removed zombie changed the world")
		return false
	# Entity slots recycle, but their generations make a second body a second identity.
	var second: int = Roster.spawn_zombie(w, 10.5, 12.25, "zombie.shambler", w.rng.stream("shambler"))
	if second == entity or Entities.entity_index(second) != Entities.entity_index(entity):
		push_error("REMAINS: the fixture did not recycle the dead body's slot with a new identity")
		return false
	Recruits.handle_death(w, second)
	if (w.visualRemains as Array).size() != 2:
		push_error("REMAINS: slot reuse overwrote or deduplicated a different body")
		return false
	var encoded: String = Save.encode_save(Save.create_save(w))
	var decoded: Dictionary = Save.decode_save(encoded)
	if decoded.has("__error"):
		push_error("REMAINS: a current save failed to decode")
		return false
	var restored: Variant = _world()
	Save.apply_save(restored, decoded)
	if restored.serialize() != w.serialize():
		push_error("REMAINS: visual records changed through real save text")
		return false
	var legacy: Dictionary = w.snapshot()
	legacy.erase("visualRemains")
	restored.restore(legacy)
	if not (restored.visualRemains as Array).is_empty():
		push_error("REMAINS: loading an older save left newer pictures in the world")
		return false
	# Bounded in both live capture and load, oldest first; a duplicate does not evict anything.
	for i in range(World.VISUAL_REMAINS_MAX + 3):
		restored.remember_visual_remains({"entity": 10000 + i, "x": 1.0, "y": 2.0, "ztype": "zombie.shambler", "sinceTick": i})
	var bounded: Array = restored.visualRemains as Array
	if bounded.size() != World.VISUAL_REMAINS_MAX or int((bounded[0] as Dictionary)["entity"]) != 10003:
		push_error("REMAINS: retention did not discard exactly the oldest records")
		return false
	var before_duplicate: String = restored.serialize()
	restored.remember_visual_remains(bounded.back() as Dictionary)
	restored.remember_visual_remains({"entity": -1, "ztype": "zombie.shambler"})
	if restored.serialize() != before_duplicate:
		push_error("REMAINS: duplicate or invalid history changed the retained records")
		return false
	var oversized: Dictionary = restored.snapshot()
	var oversized_records: Array = oversized["visualRemains"] as Array
	oversized_records.append({"entity": 90000, "x": 1.0, "y": 2.0, "ztype": "zombie.heavy", "sinceTick": 999})
	w.restore(oversized)
	if (w.visualRemains as Array).size() != World.VISUAL_REMAINS_MAX or int(((w.visualRemains as Array)[0] as Dictionary)["entity"]) != 10004:
		push_error("REMAINS: restoring oversized history bypassed its bound")
		return false
	print("REMAINS OK actual equipped zombie death changes only bounded visual data; drops, RNG, field, entities and components match the old path; duplicate death, recycled slots, save text and old saves hold")
	return true


static func _turned_art_complaint(world: Variant, entity: int) -> String:
	var type_id: String = Appearance.body_look_id(world, entity)
	if type_id != "zombie.shambler":
		return "the turned body has no default shambler content identity"
	var look: Dictionary = Appearance.for_entity(world, {"id": entity, "ztype": type_id, "zed": true})
	var key: String = String(look.get("sprite", ""))
	if look.get("texture") == null or not Appearance.turns(key):
		return "the turned body resolves no directional sprite family"
	var idle: Texture2D = Appearance.body_texture(look, "e", false, 0, entity)
	var walking: Texture2D = Appearance.body_texture(look, "e", true, 0, entity)
	if idle == null or walking == null or idle == walking:
		return "the turned body has no distinct walk frame"
	return ""


static func _turned_survivors_draw_their_type() -> bool:
	var w: Variant = _world()
	var person: int = int(w.entities.spawn())
	w.components.set_component(person, "position", {"x": 9.0, "y": 11.0})
	w.components.set_component(person, "identity", {"id": "survivor.unique.mara"})
	w.components.set_component(person, "zombieInfection", {"exposures": [{"transmitted": true}]})
	var control: Variant = _world()
	control.restore(w.snapshot().duplicate(true))
	# The old conversion's only random work was making its shambler. Compare that exact
	# reader's stream result against the real death path, so adding a look roll is caught.
	Shambler.make_shambler(control, person, control.rng.stream("shambler"))
	if not Recruits.handle_death(w, person) or bool(w.entities.is_alive(person)):
		push_error("TURNED ART: transmitted survivor did not leave through the real death path")
		return false
	var turned: Array[int] = w.components.query(["turnedFrom"])
	if turned.size() != 1 or not w.components.has_component(turned[0], "shambler"):
		push_error("TURNED ART: transmitted survivor did not become exactly one shambler")
		return false
	var entity: int = turned[0]
	var complaint: String = _turned_art_complaint(w, entity)
	if not complaint.is_empty():
		push_error("TURNED ART: " + complaint)
		return false
	if Serialize.canonicalize(w.rng.save()) != Serialize.canonicalize(control.rng.save()):
		push_error("TURNED ART: assigning the default type spent randomness beyond the existing shambler creation")
		return false
	# The missing component was the actual failure: the same predicate must reject that
	# state, not merely accept any actor with a shambler component and a position.
	var type_record: Dictionary = (w.components.get_component(entity, "zombieType") as Dictionary).duplicate()
	w.components.remove(entity, "zombieType")
	if _turned_art_complaint(w, entity).is_empty():
		push_error("TURNED ART: an untyped shambler passed the art reader")
		return false
	w.components.set_component(entity, "zombieType", type_record)
	Recruits.handle_death(w, entity)
	if (w.visualRemains as Array).size() != 1 or String(((w.visualRemains as Array)[0] as Dictionary)["ztype"]) != "zombie.shambler":
		push_error("TURNED ART: killing the turned body lost its matching corpse type")
		return false
	print("TURNED ART OK the real infected-survivor death creates an animated default shambler without another RNG draw; the untyped state is refused and its later death preserves the type")
	return true
