class_name SimSkills
extends RefCounted

# Shallow six-region web (ADR 0012). Points from doing; Focus auto-spend; dies with person.

const WEB_PATH: String = "res://content/colony/skill_web.json"
const SOURCE_PREFIX: String = "web."

const REGIONS: Array[String] = ["Melee", "Ranged", "Medicine", "Craft", "Survival", "Endurance"]

static var _cached: Dictionary = {}


static func _web() -> Dictionary:
	if not _cached.is_empty():
		return _cached
	var f := FileAccess.open(WEB_PATH, FileAccess.READ)
	if f == null:
		push_error("skill web missing: %s" % WEB_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		push_error("skill web corrupt")
		return {}
	_cached = parsed as Dictionary
	return _cached


static func attach(world: Variant, entity: int) -> void:
	var points: Dictionary = {}
	for r in REGIONS:
		points[r] = 0
	world.components.set_component(entity, "skillWeb", {
		"points": points,
		"nodes": [],
	})
	_autospend(world, entity)


static func register_module(world: Variant) -> void:
	world.events.subscribe({"id": "skills.kill-points", "type": "entity.killed", "handler": func(e: Dictionary) -> void:
		var killer: int = int(e.get("killer", -1))
		if killer < 0 or not world.components.has_component(killer, "skillWeb"):
			return
		if not world.components.has_component(int(e.get("entity", -1)), "zombieType"):
			return
		var region: String = "Melee"
		if world.components.has_component(killer, "rangedWeapon"):
			var rw: Variant = world.components.get_component(killer, "rangedWeapon")
			if rw is Dictionary and int((rw as Dictionary).get("state", 0)) != 0:
				region = "Ranged"
			elif world.components.has_component(killer, "meleeWeapon"):
				region = "Melee"
			else:
				region = "Ranged"
		_earn(world, killer, region, 1)
	})
	world.events.subscribe({"id": "skills.job-points", "type": "job.completed", "handler": func(e: Dictionary) -> void:
		var ent: int = int(e.get("entity", -1))
		if ent < 0 or not world.components.has_component(ent, "skillWeb"):
			return
		var kind: String = String(e.get("kind", ""))
		match kind:
			"Haul":
				_earn(world, ent, "Endurance", 1)
			"Cook":
				_earn(world, ent, "Survival", 1)
			"Construct":
				_earn(world, ent, "Craft", 1)
			"Doctor":
				_earn(world, ent, "Medicine", 1)
			_:
				pass
	})
	world.events.subscribe({"id": "skills.focus-respend", "type": "job.focus_changed", "handler": func(e: Dictionary) -> void:
		var ent: int = int(e.get("entity", -1))
		if ent >= 0:
			_autospend(world, ent)
	})


static func _earn(world: Variant, entity: int, region: String, amount: int) -> void:
	var web: Variant = world.components.get_component(entity, "skillWeb")
	if not web is Dictionary:
		return
	var pts: Dictionary = (web as Dictionary).get("points", {}) as Dictionary
	pts[region] = int(pts.get(region, 0)) + amount
	(web as Dictionary)["points"] = pts
	world.components.set_component(entity, "skillWeb", web)
	_autospend(world, entity)


static func _focus_of(world: Variant, entity: int) -> String:
	var jp: Variant = world.components.get_component(entity, "jobPriorities")
	if jp is Dictionary:
		return String((jp as Dictionary).get("focus", "Auto"))
	return "Auto"


static func _autospend(world: Variant, entity: int) -> void:
	var def: Dictionary = _web()
	if def.is_empty():
		return
	var web: Variant = world.components.get_component(entity, "skillWeb")
	if not web is Dictionary:
		return
	var w: Dictionary = web as Dictionary
	var pts: Dictionary = (w.get("points", {}) as Dictionary).duplicate()
	var owned: Array = (w.get("nodes", []) as Array).duplicate()
	var focus: String = _focus_of(world, entity)
	if focus == "Manual":
		return
	var paths: Dictionary = def.get("focusPaths", {}) as Dictionary
	var path: Array = paths.get(focus, paths.get("Auto", [])) as Array
	var nodes_by_id: Dictionary = {}
	for n in def.get("nodes", []) as Array:
		if n is Dictionary:
			nodes_by_id[String((n as Dictionary).get("id", ""))] = n
	var changed: bool = false
	for nid_v in path:
		var nid: String = String(nid_v)
		if owned.has(nid):
			continue
		var node: Variant = nodes_by_id.get(nid)
		if not node is Dictionary:
			continue
		var region: String = String((node as Dictionary).get("region", ""))
		var cost: int = int((node as Dictionary).get("cost", 1))
		if int(pts.get(region, 0)) < cost:
			continue
		pts[region] = int(pts.get(region, 0)) - cost
		owned.append(nid)
		changed = true
	if not changed and owned == (w.get("nodes", []) as Array):
		return
	w["points"] = pts
	w["nodes"] = owned
	world.components.set_component(entity, "skillWeb", w)
	_apply_mods(world, entity, owned, nodes_by_id)


static func _apply_mods(world: Variant, entity: int, owned: Array, nodes_by_id: Dictionary) -> void:
	if world.modifiers == null:
		return
	# Wipe prior web sources then re-add owned.
	for n in nodes_by_id.values():
		if n is Dictionary:
			var src: String = SOURCE_PREFIX + String((n as Dictionary).get("id", ""))
			world.modifiers.call("remove_by_source", src, entity)
	for nid_v in owned:
		var node: Variant = nodes_by_id.get(String(nid_v))
		if not node is Dictionary:
			continue
		var nd: Dictionary = node as Dictionary
		world.modifiers.call("add", {
			"stat": String(nd.get("stat", "move_speed")),
			"op": String(nd.get("op", "mul")),
			"value": float(nd.get("value", 1.0)),
			"source": SOURCE_PREFIX + String(nd.get("id", "")),
		}, entity)


static func node_count(world: Variant, entity: int) -> int:
	var web: Variant = world.components.get_component(entity, "skillWeb")
	if not web is Dictionary:
		return 0
	return ((web as Dictionary).get("nodes", []) as Array).size()


static func points(world: Variant, entity: int, region: String) -> int:
	var web: Variant = world.components.get_component(entity, "skillWeb")
	if not web is Dictionary:
		return 0
	var pts: Dictionary = (web as Dictionary).get("points", {}) as Dictionary
	return int(pts.get(region, 0))
