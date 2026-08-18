class_name SimSurvivors
extends RefCounted

# Unique survivor pipeline per .scratch/simplyzombies/issues/05-unique-npc.md.
# Drop another JSON in godot/content/survivors/uniques/ — no code change. Generator is later.

const SimAptitudesRes = preload("res://sim/modules/aptitudes.gd")
const SimStancesRes = preload("res://sim/stances.gd")
const SimHealthRes = preload("res://sim/modules/health.gd")
const SimItemsRes = preload("res://sim/modules/items.gd")
const SimInventoryRes = preload("res://sim/modules/inventory.gd")
const SimAttentionRes = preload("res://sim/modules/attention_emitter.gd")
const SimNeedsRes = preload("res://sim/modules/needs.gd")
const SimJobsRes = preload("res://sim/modules/jobs.gd")
const SimSkillsRes = preload("res://sim/modules/skills.gd")


static func entry_of(world: Variant, id: String) -> Variant:
	if world == null or world.content == null:
		return null
	var c: Variant = world.content
	if c is Dictionary:
		if (c as Dictionary).has("survivor"):
			var by_id: Variant = (c as Dictionary)["survivor"]
			if by_id is Dictionary:
				var hit: Variant = (by_id as Dictionary).get(id)
				if hit != null:
					return hit
		for v in (c as Dictionary).values():
			if v is Dictionary and String((v as Dictionary).get("id", "")) == id:
				return v
			if v is Array:
				for entry in v as Array:
					if entry is Dictionary and String((entry as Dictionary).get("id", "")) == id:
						return entry
	return null


static func list_uniques(world: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world == null or world.content == null:
		return out
	var c: Variant = world.content
	if not (c is Dictionary):
		return out
	for path in (c as Dictionary).keys():
		if not String(path).begins_with("survivors/"):
			continue
		var raw: Variant = (c as Dictionary)[path]
		var entries: Array = raw as Array if raw is Array else [raw]
		for entry_v in entries:
			if entry_v is Dictionary and String((entry_v as Dictionary).get("id", "")).begins_with("survivor.unique."):
				out.append(entry_v as Dictionary)
	out.sort_custom(func(a, b): return String(a.get("id", "")) < String(b.get("id", "")))
	return out


static func spawn_unique(world: Variant, id: String, x: float, y: float) -> int:
	var entry: Variant = entry_of(world, id)
	if entry == null:
		for u in list_uniques(world):
			if String(u.get("id", "")) == id:
				entry = u
				break
	assert(entry is Dictionary, "Unknown unique survivor: " + id)
	var e: Dictionary = entry as Dictionary
	var ent: int = int(world.entities.spawn())
	world.components.set_component(ent, "position", {"x": x, "y": y})
	world.components.set_component(ent, "velocity", {"dx": 0.0, "dy": 0.0})
	world.components.set_component(ent, "posture", SimStancesRes.make_posture(SimStancesRes.Stance.Walk))
	world.components.set_component(ent, "facing", {"radians": 0.0})
	world.components.set_component(ent, "identity", {
		"id": String(e.get("id", id)),
		"name": String(e.get("name", id)),
		"unique": true,
		"traits": (e.get("traits", []) as Array).duplicate() if e.get("traits", []) is Array else [],
	})
	SimHealthRes.make_survivor_body(world, ent)
	SimHealthRes.make_stamina(world, ent)
	SimInventoryRes.make_inventory(world, ent)
	SimAttentionRes.make_emitter(world, ent)
	SimAptitudesRes.apply(world, ent, e.get("aptitudes", {}))
	SimNeedsRes.attach(world, ent)
	var focus: String = String(e.get("focus", "Auto"))
	var row: Dictionary = {}
	if e.get("jobPriorities", {}) is Dictionary:
		var raw: Dictionary = e["jobPriorities"] as Dictionary
		row = SimJobsRes.empty_row()
		for k in raw.keys():
			row[String(k)] = int(raw[k])
	SimJobsRes.attach(world, ent, focus, row)
	SimSkillsRes.attach(world, ent)
	var kit: Variant = e.get("kit", [])
	if kit is Array:
		for item_id in kit as Array:
			var item: int = SimItemsRes.spawn_item(world, String(item_id), {"tier": "scavenged"})
			# Anything the kit lists that can be *held* is held, rather than packed. A weapon in
			# a satchel is not a weapon: `melee.gd` builds the meleeWeapon profile off
			# `item.equipped`, so a stowed knife left a colonist with nothing to swing and
			# npc_combat.gd with nothing to reach with -- which is exactly how the second
			# colonist came to boot unarmed while carrying her own kit. Bandages and pills have
			# no equipSlot and are unaffected; a second primary falls through to the pack.
			if _hold_it(world, ent, item):
				continue
			if not SimInventoryRes.stow(world, ent, item):
				world.components.set_component(item, "position", {"x": x, "y": y})
	world.events.publish({"type": "survivor.joined", "entity": ent, "id": id})
	return ent


# Puts a kit item in the hand or on the body it belongs to, if that place is still empty.
# Returns false for anything with no equipSlot at all, and for a second item competing for a slot
# already filled -- `equip` would displace the first, and a kit is a list, not a priority order.
static func _hold_it(world: Variant, ent: int, item: int) -> bool:
	var slot: Variant = SimInventoryRes.equip_slot_for(world, item)
	if slot == null:
		return false
	var eq: Variant = world.components.get_component(ent, "equipment")
	if eq is Dictionary and ((eq as Dictionary).get("slots", {}) as Dictionary).has(String(slot)):
		return false
	return SimInventoryRes.equip(world, ent, item)


static func boot_playable(world: Variant) -> int:
	# Player: midpoint stats so a fixture boot without this stays parity-neutral.
	SimHealthRes.make_survivor_body(world, world.player)
	SimHealthRes.make_stamina(world, world.player)
	SimInventoryRes.make_inventory(world, world.player)
	SimAttentionRes.make_emitter(world, world.player)
	if not world.components.has_component(world.player, "facing"):
		world.components.set_component(world.player, "facing", {"radians": 0.0})
	SimAptitudesRes.apply(world, world.player, {"str": SimAptitudesRes.DEFAULT, "dex": SimAptitudesRes.DEFAULT, "con": SimAptitudesRes.DEFAULT})
	SimNeedsRes.attach(world, world.player)
	SimSkillsRes.attach(world, world.player)
	var pos: Variant = world.components.get_component(world.player, "position")
	var px: float = float((pos as Dictionary)["x"]) if pos is Dictionary else 5.0
	var py: float = float((pos as Dictionary)["y"]) if pos is Dictionary else 5.0
	var mara: int = -1
	for u in list_uniques(world):
		var id: String = String(u.get("id", ""))
		var ox: float = 1.6
		var oy: float = 0.0
		if world.is_blocked_tile(floori(px + ox), floori(py + oy)):
			ox = -1.6
		mara = spawn_unique(world, id, px + ox, py + oy)
	return mara
