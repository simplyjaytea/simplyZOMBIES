class_name SimItems
extends RefCounted

const FULL_CONDITION: float = 1.0
const CONDITION_FLOOR: float = 0.55
# ponytail: flat wear per hit; jam/miss wear later.
const WEAR_PER_HIT: float = 0.005
const REPAIR_GAIN: float = 0.25
const REPAIR_CEILING_DROP: float = 0.05
const REPAIR_CEILING_FLOOR: float = 0.2
const CONDITION_BANDS: Array[Dictionary] = [
	{"atLeast": 0.8, "name": "sound"},
	{"atLeast": 0.5, "name": "worn"},
	{"atLeast": 0.2, "name": "failing"},
	{"atLeast": 0.01, "name": "barely holding"},
	{"atLeast": 0.0, "name": "broken"},
]
const TIERS: Array[Dictionary] = [
	{"id": "scavenged", "affixes": 0, "weight": 100},
	{"id": "modified", "affixes": 2, "weight": 35},
	{"id": "field_tested", "affixes": 4, "weight": 6},
]

static func condition_band(cond: Dictionary) -> String:
	for band in CONDITION_BANDS:
		if float(cond.get("current", 0.0)) >= float(band["atLeast"]):
			return String(band["name"])
	return "broken"

static func base_size(base: Dictionary) -> Dictionary:
	var s: Variant = base.get("size")
	if s is Dictionary:
		return {"w": int((s as Dictionary).get("w", 1)), "h": int((s as Dictionary).get("h", 1))}
	return {"w": 1, "h": 1}

static func base_mass_kg(base: Dictionary) -> float:
	var m: Variant = base.get("massKg")
	return float(m) if m is float or m is int else 0.0

static func base_stack_limit(base: Dictionary) -> int:
	var st: Variant = base.get("stack")
	if st is int or st is float:
		return maxi(1, int(st))
	return 1

static func base_class(base: Dictionary) -> String:
	var c: Variant = base.get("class")
	return String(c) if c is String else "material"

static func base_container_grid(base: Dictionary) -> Variant:
	var g: Variant = base.get("container")
	if g is Dictionary:
		return {"w": int((g as Dictionary).get("w", 0)), "h": int((g as Dictionary).get("h", 0))}
	return null

static func base_equip_slot(base: Dictionary) -> Variant:
	var s: Variant = base.get("equipSlot")
	return String(s) if s is String else null

# ---- content helpers (supports both registry object and flat Dict from ContentLoader) ----

static func _content_get(world: Variant, type_id: String, id: String) -> Variant:
	if world == null:
		return null
	var c: Variant = null
	if world is Dictionary:
		c = (world as Dictionary).get("content")
	elif "content" in world:
		c = world.content
	else:
		c = world
	if c == null:
		return null
	# Flat Dictionary from ContentLoader.load_tree(): path -> JSON value
	if c is Dictionary:
		# Indexed map form type->id->entry if someone pre-indexed
		if (c as Dictionary).has(type_id):
			var by_id: Variant = (c as Dictionary)[type_id]
			if by_id is Dictionary:
				var hit: Variant = (by_id as Dictionary).get(id)
				if hit != null:
					return hit
		for v in (c as Dictionary).values():
			if v is Array:
				for entry in v as Array:
					if entry is Dictionary and String((entry as Dictionary).get("id", "")) == id:
						return entry
			elif v is Dictionary:
				var d: Dictionary = v as Dictionary
				if String(d.get("id", "")) == id:
					return d
		return null
	if c is Object and (c as Object).has_method("get"):
		return (c as Object).call("get", type_id, id)
	return null

static func _content_has(world: Variant, type_id: String, id: String) -> bool:
	return _content_get(world, type_id, id) != null

static func _all_entries(world: Variant, type_id: String) -> Array:
	var out: Array = []
	if world == null:
		return out
	var c: Variant = null
	if world is Dictionary:
		c = (world as Dictionary).get("content")
	elif "content" in world:
		c = world.content
	else:
		c = world
	if c == null:
		return out
	if c is Object and (c as Object).has_method("all"):
		return (c as Object).call("all", type_id) as Array
	if c is Dictionary:
		# flat tree path -> json
		for v in (c as Dictionary).values():
			if v is Array:
				for entry in v as Array:
					if entry is Dictionary:
						if type_id == "affix" and (entry as Dictionary).has("slot"):
							out.append(entry)
						elif type_id == "item" and (entry as Dictionary).has("massKg"):
							out.append(entry)
		if (c as Dictionary).has(type_id):
			var by_id: Variant = (c as Dictionary)[type_id]
			if by_id is Dictionary:
				for e in (by_id as Dictionary).values():
					out.append(e)
			elif by_id is Array:
				out.append_array(by_id as Array)
	return out

static func item_base_of(world: Variant, item: int) -> Variant:
	var b: Variant = world.components.get_component(item, "itemBase")
	if b == null:
		return null
	var base_id: String = String((b as Dictionary).get("baseId", ""))
	var entry: Variant = _content_get(world, "item", base_id)
	if entry == null:
		# TS throws here; in Godot push_error so verify_content_references can catch batch
		push_error("Item %d references item base \"%s\", which is not loaded" % [item, base_id])
		return null
	return entry

static func size_of_item(world: Variant, item: int) -> Dictionary:
	var base: Variant = item_base_of(world, item)
	if base == null:
		return {"w": 1, "h": 1}
	return base_size(base as Dictionary)

static func item_mass_kg(world: Variant, item: int, contents_of: Callable) -> float:
	var base: Variant = item_base_of(world, item)
	if base == null:
		return 0.0
	var stack: Variant = world.components.get_component(item, "stack")
	var mass: float = base_mass_kg(base as Dictionary) * float(1 if stack == null else int((stack as Dictionary).get("count", 1)))
	for child in contents_of.call(item) as Array:
		mass += item_mass_kg(world, int(child), contents_of)
	return mass

static func condition_factor(world: Variant, item: int) -> float:
	var c: Variant = world.components.get_component(item, "condition")
	if c == null:
		return 1.0
	var cur: float = float((c as Dictionary).get("current", 1.0))
	if cur <= 0.0:
		return 0.0
	return CONDITION_FLOOR + (1.0 - CONDITION_FLOOR) * clampf(cur, 0.0, 1.0)


static func apply_wear(world: Variant, item: int, amount: float = WEAR_PER_HIT) -> void:
	if item < 0 or amount <= 0.0:
		return
	var c: Variant = world.components.get_component(item, "condition")
	if not c is Dictionary:
		return
	var before: float = float((c as Dictionary).get("current", 1.0))
	if before <= 0.0:
		return
	var after: float = maxf(0.0, before - amount)
	(c as Dictionary)["current"] = after
	if after <= 0.0:
		world.events.publish({"type": "item.broke", "item": item})
		var Inv: GDScript = load("res://sim/modules/inventory.gd") as GDScript
		if Inv != null:
			Inv.call("unequip_item", world, item)
		return
	_refresh_armed(world, item)


static func repair_item(world: Variant, item: int) -> bool:
	var c: Variant = world.components.get_component(item, "condition")
	if not c is Dictionary:
		return false
	var cur: float = float((c as Dictionary).get("current", 1.0))
	var ceil: float = float((c as Dictionary).get("ceiling", FULL_CONDITION))
	if cur >= ceil:
		return false
	ceil = maxf(REPAIR_CEILING_FLOOR, ceil - REPAIR_CEILING_DROP)
	(c as Dictionary)["ceiling"] = ceil
	(c as Dictionary)["current"] = minf(ceil, cur + REPAIR_GAIN)
	_refresh_armed(world, item)
	world.events.publish({"type": "item.repaired", "item": item})
	return true


static func _refresh_armed(world: Variant, item: int) -> void:
	for actor in world.components.query(["equipment"]):
		var eq: Variant = world.components.get_component(int(actor), "equipment")
		if not eq is Dictionary:
			continue
		var slots: Dictionary = (eq as Dictionary).get("slots", {}) as Dictionary
		var found := false
		for slot in slots.keys():
			if int(slots[slot]) == item:
				found = true
				break
		if not found:
			continue
		var melee: Variant = melee_profile_of(world, item)
		if melee is Dictionary:
			world.components.set_component(int(actor), "meleeWeapon", melee as Dictionary)
			continue
		var ranged: Variant = ranged_profile_of(world, item)
		if ranged is Dictionary:
			# Wear changes the weapon, not the shot already in flight. This used to overwrite the
			# whole component, which dropped the runtime keys `make_ranged_armed` puts there --
			# `state`, `mag`, `ticksLeft`, `flashTicks`, `coneHalf` -- and left `ranged.resolve`
			# reading a `state` that no longer existed. Merge the refreshed numbers into the live
			# weapon instead; the equip subscription stays the only thing that creates one.
			var live: Variant = world.components.get_component(int(actor), "rangedWeapon")
			if live is Dictionary:
				for key in (ranged as Dictionary).keys():
					(live as Dictionary)[key] = (ranged as Dictionary)[key]


static func _weapon_for_attacker(world: Variant, attacker: int) -> int:
	var eq: Variant = world.components.get_component(attacker, "equipment")
	if not eq is Dictionary:
		return -1
	var slots: Dictionary = (eq as Dictionary).get("slots", {}) as Dictionary
	for slot in ["primary", "secondary"]:
		if slots.has(slot):
			var item: int = int(slots[slot])
			if melee_profile_of(world, item) != null or ranged_profile_of(world, item) != null:
				return item
	return -1


static func register_module(world: Variant) -> void:
	world.events.subscribe({"id": "items.wear-on-hit", "type": "attack.connected", "handler": func(event: Dictionary) -> void:
		var attacker: int = int(event.get("attacker", -1))
		if attacker < 0:
			return
		var weapon: int = _weapon_for_attacker(world, attacker)
		if weapon >= 0:
			apply_wear(world, weapon)
	})

static func melee_profile_of(world: Variant, item: int) -> Variant:
	var base: Variant = item_base_of(world, item)
	if base == null:
		return null
	var melee: Variant = (base as Dictionary).get("melee")
	if not melee is Dictionary:
		return null
	var wear: float = condition_factor(world, item)
	var resolve := func(stat: String) -> float:
		if world.modifiers != null and (world.modifiers as Object).has_method("resolve"):
			return float(world.modifiers.call("resolve", stat, item))
		return 1.0
	var m: Dictionary = melee as Dictionary
	return {
		"reachMetres": float(m.get("reachMetres", 1.4)) * resolve.call("melee_reach"),
		"weight": float(m.get("weight", 1.0)),
		"damage": float(m.get("damage", 11)) * resolve.call("melee_damage") * wear,
		"staggerTicks": maxi(0, int(round(float(m.get("staggerTicks", 8)) * resolve.call("melee_stagger")))),
		"speed": resolve.call("swing_speed") * wear,
		"recovery": resolve.call("swing_recovery"),
		"stamina": resolve.call("swing_stamina"),
	}

static func ranged_profile_of(world: Variant, item: int) -> Variant:
	var base: Variant = item_base_of(world, item)
	if base == null:
		return null
	var ranged: Variant = (base as Dictionary).get("ranged")
	if not ranged is Dictionary:
		return null
	var wear: float = condition_factor(world, item)
	var r: Dictionary = ranged as Dictionary
	return {
		"damage": float(r.get("damage", 12)) * wear,
		"noise": float(r.get("noise", 4)),
		"flash": float(r.get("flash", 0)),
		"ammo": String(r.get("ammo", "")),
		"recoverable": float(r.get("recoverable", 0.0)),
		"magSize": int(r.get("magSize", 0)),
		"reloadTicks": int(r.get("reloadTicks", 24)),
		"rangeMetres": float(r.get("rangeMetres", 30)),
	}

# ---- affixes ----

static func roll_tier(rng: Variant) -> String:
	var total: int = 0
	for t in TIERS:
		total += int(t["weight"])
	var roll: float = float(rng.call("float_range", 0.0, float(total)))
	for t in TIERS:
		roll -= float(t["weight"])
		if roll < 0.0:
			return String(t["id"])
	return "scavenged"

static func affix_pool(world: Variant, item_class: String, slot: String) -> Array:
	var pool: Array = []
	for affix in _all_entries(world, "affix"):
		var d: Dictionary = affix as Dictionary
		if String(d.get("slot", "")) != slot:
			continue
		var applies: Variant = d.get("appliesTo")
		if applies is Array and (applies as Array).has(item_class):
			pool.append(d)
	return pool

static func _roll_affix_tier(affix: Dictionary, rng: Variant) -> int:
	var tiers: Variant = affix.get("tiers")
	if not tiers is Array or (tiers as Array).is_empty():
		return 0
	var arr: Array = tiers as Array
	var total: float = 0.0
	for t in arr:
		total += float((t as Dictionary).get("weight", 0))
	var roll: float = float(rng.call("float_range", 0.0, total))
	for i in arr.size():
		roll -= float((arr[i] as Dictionary).get("weight", 0))
		if roll < 0.0:
			return i
	return arr.size() - 1

static func roll_affixes(world: Variant, item_class: String, tier: String, rng: Variant) -> Dictionary:
	var wanted: int = 0
	for t in TIERS:
		if String(t["id"]) == tier:
			wanted = int(t["affixes"])
			break
	var out: Dictionary = {"prefixes": [], "suffixes": []}
	if wanted == 0:
		return out
	var split: Dictionary = {"prefix": int(ceil(float(wanted) / 2.0)), "suffix": int(floor(float(wanted) / 2.0))}
	for slot in ["prefix", "suffix"]:
		var available: Array = affix_pool(world, item_class, slot)
		# draw without replacement — copy to avoid mutating registry
		var bag: Array = available.duplicate()
		for _i in range(int(split[slot])):
			if bag.is_empty():
				break
			var pick: int = int(rng.call("int_range", 0, bag.size() - 1))
			var affix: Dictionary = bag[pick] as Dictionary
			bag.remove_at(pick)
			var rolled: Dictionary = {"id": String(affix["id"]), "tier": _roll_affix_tier(affix, rng)}
			if slot == "prefix":
				(out["prefixes"] as Array).append(rolled)
			else:
				(out["suffixes"] as Array).append(rolled)
	(out["prefixes"] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if String(a["id"]) != String(b["id"]): return String(a["id"]) < String(b["id"])
		return int(a["tier"]) < int(b["tier"]))
	(out["suffixes"] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if String(a["id"]) != String(b["id"]): return String(a["id"]) < String(b["id"])
		return int(a["tier"]) < int(b["tier"]))
	return out

static func affix_modifiers(world: Variant, item: int) -> Array:
	var aff: Variant = world.components.get_component(item, "affixes")
	if aff == null:
		return []
	var out: Array = []
	var d: Dictionary = aff as Dictionary
	var all: Array = []
	all.append_array(d.get("prefixes", []) as Array)
	all.append_array(d.get("suffixes", []) as Array)
	for rolled_v in all:
		var rolled: Dictionary = rolled_v as Dictionary
		var affix: Variant = _content_get(world, "affix", String(rolled["id"]))
		if affix == null:
			push_error("Item %d references affix \"%s\", which is not loaded" % [item, String(rolled["id"])])
			continue
		var tiers: Variant = (affix as Dictionary).get("tiers")
		if not tiers is Array:
			continue
		var tier_idx: int = int(rolled["tier"])
		if tier_idx < 0 or tier_idx >= (tiers as Array).size():
			push_error("Item %d rolled tier %d of affix \"%s\" which declares %d" % [item, tier_idx, String(rolled["id"]), (tiers as Array).size()])
			continue
		var tier_data: Dictionary = (tiers as Array)[tier_idx] as Dictionary
		for mod in tier_data.get("modifiers", []) as Array:
			var m: Dictionary = (mod as Dictionary).duplicate(true)
			m["source"] = String(rolled["id"])
			out.append(m)
	return out

static func item_name(world: Variant, item: int) -> String:
	var base: Variant = item_base_of(world, item)
	if base == null:
		return "something"
	var plain: String = String((base as Dictionary).get("name", (base as Dictionary).get("id", "something")))
	var aff: Variant = world.components.get_component(item, "affixes")
	if aff == null:
		return plain
	var d: Dictionary = aff as Dictionary
	var name_of: Callable = func(rolled: Dictionary) -> String:
		var affix: Variant = _content_get(world, "affix", String(rolled["id"]))
		if affix is Dictionary and (affix as Dictionary).has("name"):
			return String((affix as Dictionary)["name"])
		return ""
	var prefixes: Array = []
	for r in d.get("prefixes", []) as Array:
		var n: String = String(name_of.call(r as Dictionary))
		if n != "":
			prefixes.append(n)
	var suffixes: Array = []
	for r in d.get("suffixes", []) as Array:
		var n: String = String(name_of.call(r as Dictionary))
		if n != "":
			suffixes.append(n)
	var parts: Array = []
	parts.append_array(prefixes)
	parts.append(plain)
	parts.append_array(suffixes)
	# GDScript join via String
	var out: String = ""
	for i in parts.size():
		if i > 0:
			out += " "
		out += String(parts[i])
	return out

static func spawn_item(world: Variant, base_id: String, options: Dictionary = {}) -> int:
	var item: int = int(world.entities.spawn())
	world.components.set_component(item, "itemBase", {"baseId": base_id})
	# tier roll — needs world.rng.stream("loot")
	var rng: Variant = null
	if "rng" in world and world.rng != null and world.rng.has_method("stream"):
		rng = world.rng.call("stream", "loot")
	var tier: String = String(options.get("tier", "")) if options.has("tier") else ""
	if tier == "" and rng != null:
		tier = roll_tier(rng)
	elif tier == "":
		tier = "scavenged"
	var base: Variant = _content_get(world, "item", base_id)
	var cls: String = base_class(base as Dictionary) if base is Dictionary else "material"
	var aff: Dictionary = {"prefixes": [], "suffixes": []}
	if rng != null and base != null:
		aff = roll_affixes(world, cls, tier, rng)
	world.components.set_component(item, "affixes", aff)
	world.components.set_component(item, "condition", {"current": FULL_CONDITION, "ceiling": FULL_CONDITION})
	var stack_limit: int = base_stack_limit(base as Dictionary) if base is Dictionary else 1
	if stack_limit > 1:
		var count: int = int(options.get("count", 1))
		count = clampi(count, 1, stack_limit)
		world.components.set_component(item, "stack", {"count": count})
	# scope modifiers to item
	for mod in affix_modifiers(world, item):
		world.modifiers.add(mod as Dictionary, item)
	world.events.publish({"type": "item.spawned", "item": item, "baseId": base_id})
	world.events.drain()
	if base_id == "item.food.raw" or base_id == "item.food.cooked":
		var Needs: GDScript = load("res://sim/modules/needs.gd") as GDScript
		if Needs != null and Needs.has_method("mark_spoilage"):
			Needs.call("mark_spoilage", world, item, base_id)
	return item

static func verify_content_references(world: Variant) -> void:
	var problems: Array[String] = []
	for item in world.components.query(["itemBase"]):
		var b: Variant = world.components.get_component(int(item), "itemBase")
		var bid: String = String((b as Dictionary).get("baseId", "")) if b is Dictionary else ""
		if not _content_has(world, "item", bid):
			problems.append("item %d: no item base \"%s\"" % [int(item), bid])
	for item2 in world.components.query(["affixes"]):
		var aff: Variant = world.components.get_component(int(item2), "affixes")
		if not aff is Dictionary:
			continue
		var d2: Dictionary = aff as Dictionary
		var all2: Array = []
		all2.append_array(d2.get("prefixes", []) as Array)
		all2.append_array(d2.get("suffixes", []) as Array)
		for rolled_v in all2:
			var rolled: Dictionary = rolled_v as Dictionary
			var rid: String = String(rolled["id"])
			var affix: Variant = _content_get(world, "affix", rid)
			if affix == null:
				problems.append("item %d: no affix \"%s\"" % [int(item2), rid])
				continue
			var tiers: Variant = (affix as Dictionary).get("tiers")
			var tier_idx: int = int(rolled["tier"])
			var sz: int = (tiers as Array).size() if tiers is Array else 0
			if tier_idx < 0 or tier_idx >= sz:
				problems.append("item %d: affix \"%s\" has no tier %d (it declares %d)" % [int(item2), rid, tier_idx, sz])
	if not problems.is_empty():
		var msg: String = "Content does not match this world (%d %s):\n  %s" % [problems.size(), "problem" if problems.size() == 1 else "problems", "\n  ".join(problems)]
		push_error(msg)
		assert(false, msg)
