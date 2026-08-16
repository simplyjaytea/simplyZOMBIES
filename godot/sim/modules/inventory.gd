class_name SimInventory
extends RefCounted

const SimItems = preload("res://sim/modules/items.gd")
const SimGrid = preload("res://sim/inventory/grid.gd")
const SimSerialize = preload("res://sim/kernel/serialize.gd")

const EQUIP_SLOTS: Array[String] = ["back", "vest", "belt", "primary", "secondary", "head", "torso"]
const POCKET_GRID: Dictionary = {"w": 4, "h": 2}
const MAX_CONTAINER_DEPTH: int = 3
const PICKUP_REACH: float = 1.5
const OVERLOAD_SPEED_PENALTY: float = 0.5
const MIN_OVERLOAD_SPEED: float = 0.35
const ENCUMBRANCE_SOURCE: String = "item.encumbrance"

# ---- queries ----

static func contents_of(world: Variant, container: int) -> Array[int]:
	var box: Variant = world.components.get_component(container, "container")
	if box == null:
		return [] as Array[int]
	var out: Array[int] = []
	for p in (box as Dictionary).get("items", []) as Array:
		out.append(int((p as Dictionary)["item"]))
	return out

static func equipped_items(world: Variant, actor: int) -> Array[int]:
	var eq: Variant = world.components.get_component(actor, "equipment")
	if eq == null:
		return [] as Array[int]
	var slots: Dictionary = (eq as Dictionary).get("slots", {}) as Dictionary
	var keys: Array = slots.keys()
	keys.sort()
	var out: Array[int] = []
	for k in keys:
		out.append(int(slots[k]))
	return out

static func carried_items(world: Variant, actor: int) -> Array[int]:
	var out: Array[int] = []
	_collect_carried(world, actor, out)
	for eq in equipped_items(world, actor):
		out.append(eq)
		_collect_carried(world, eq, out)
	return out


static func _collect_carried(world: Variant, container: int, out: Array[int]) -> void:
	for item in contents_of(world, container):
		out.append(item)
		_collect_carried(world, item, out)

static func carried_mass_kg(world: Variant, actor: int) -> float:
	var fn: Callable = func(container: int) -> Array[int]: return contents_of(world, container)
	var mass: float = 0.0
	for item in contents_of(world, actor):
		mass += SimItems.item_mass_kg(world, item, fn)
	for eq in equipped_items(world, actor):
		mass += SimItems.item_mass_kg(world, eq, fn)
	return mass

static func container_depth(world: Variant, container: int) -> Variant:
	var depth: int = 0
	var current: int = container
	var seen: Dictionary = {}
	while true:
		if seen.has(current):
			return null
		seen[current] = true
		var stored: Variant = world.components.get_component(current, "stored")
		if stored == null:
			return depth + 1 if world.components.has_component(current, "itemBase") else depth
		depth += 1
		if depth > MAX_CONTAINER_DEPTH + 1:
			return null
		current = int((stored as Dictionary)["container"])
	return null

static func is_within(world: Variant, container: int, item: int) -> bool:
	var cur: Variant = container
	var seen: Dictionary = {}
	while cur != null:
		var ci: int = int(cur)
		if ci == item:
			return true
		if seen.has(ci):
			return false
		seen[ci] = true
		var stored: Variant = world.components.get_component(ci, "stored")
		if stored == null:
			return false
		cur = int((stored as Dictionary)["container"])
	return false

static func grid_of(world: Variant, container: int) -> Variant:
	var box: Variant = world.components.get_component(container, "container")
	if box == null:
		return null
	return {"w": int((box as Dictionary)["w"]), "h": int((box as Dictionary)["h"])}

static func remove_from_container(world: Variant, item: int) -> void:
	var stored: Variant = world.components.get_component(item, "stored")
	if stored == null:
		return
	var cont: int = int((stored as Dictionary)["container"])
	var box: Variant = world.components.get_component(cont, "container")
	if box != null:
		var items: Array = (box as Dictionary)["items"] as Array
		var filtered: Array = []
		for p in items:
			if int((p as Dictionary)["item"]) != item:
				filtered.append(p)
		(box as Dictionary)["items"] = filtered
	world.components.remove(item, "stored")

static func _sizes_in(world: Variant) -> Callable:
	return func(item: int) -> Dictionary: return SimItems.size_of_item(world, item)

static func can_place(world: Variant, item: int, container: int, x: int, y: int, rotated: bool) -> Dictionary:
	var box: Variant = world.components.get_component(container, "container")
	if box == null:
		return {"ok": false, "reason": "not-a-container"}
	if not world.components.has_component(item, "itemBase"):
		return {"ok": false, "reason": "not-an-item"}
	if is_within(world, container, item):
		return {"ok": false, "reason": "would-nest-inside-itself"}
	var depth: Variant = container_depth(world, container)
	if depth == null or int(depth) > MAX_CONTAINER_DEPTH:
		return {"ok": false, "reason": "too-deep"}
	if world.components.has_component(item, "container") and int(depth) + 1 > MAX_CONTAINER_DEPTH:
		return {"ok": false, "reason": "too-deep"}
	var candidate: Dictionary = {"item": item, "x": x, "y": y, "rotated": rotated}
	if not SimGrid.fits((box as Dictionary), (box as Dictionary)["items"] as Array, _sizes_in(world), candidate):
		return {"ok": false, "reason": "does-not-fit"}
	return {"ok": true}

static func place_at(world: Variant, item: int, container: int, x: int, y: int, rotated: bool) -> Dictionary:
	var verdict: Dictionary = can_place(world, item, container, x, y, rotated)
	if not bool(verdict["ok"]):
		return verdict
	var was_in: Variant = world.components.get_component(item, "stored")
	var was_cont: Variant = null
	if was_in != null:
		was_cont = int((was_in as Dictionary)["container"])
	remove_from_container(world, item)
	unequip_item(world, item)
	world.components.remove(item, "position")
	var box: Variant = world.components.get_component(container, "container")
	(box as Dictionary)["items"].append({"item": item, "x": x, "y": y, "rotated": rotated})
	SimGrid.sort_placements((box as Dictionary)["items"] as Array)
	world.components.set_component(item, "stored", {"container": container, "x": x, "y": y, "rotated": rotated})
	if was_cont != null and int(was_cont) != container:
		var prev: Variant = world.components.get_component(int(was_cont), "container")
		if prev != null:
			SimGrid.sort_placements((prev as Dictionary)["items"] as Array)
	return {"ok": true}

static func store_anywhere(world: Variant, item: int, container: int) -> bool:
	var box: Variant = world.components.get_component(container, "container")
	if box == null:
		return false
	if is_within(world, container, item):
		return false
	var depth: Variant = container_depth(world, container)
	if depth == null or int(depth) > MAX_CONTAINER_DEPTH:
		return false
	var slot: Variant = SimGrid.find_free_slot((box as Dictionary), (box as Dictionary)["items"] as Array, _sizes_in(world), item)
	if slot == null:
		return false
	var s: Dictionary = slot as Dictionary
	return bool(place_at(world, item, container, int(s["x"]), int(s["y"]), bool(s["rotated"]))["ok"])

static func reachable_containers(world: Variant, actor: int) -> Array[int]:
	var out: Array[int] = []
	if world.components.has_component(actor, "container"):
		out.append(actor)
	var walk: Callable = func(container: int, depth: int, acc: Array[int], recurse: Callable) -> void:
		if depth > MAX_CONTAINER_DEPTH:
			return
		for item in contents_of(world, container):
			if world.components.has_component(item, "container"):
				acc.append(item)
				recurse.call(item, depth + 1, acc, recurse)
	walk.call(actor, 1, out, walk)
	for eq in equipped_items(world, actor):
		if world.components.has_component(eq, "container"):
			out.append(eq)
			walk.call(eq, 2, out, walk)
	return out

static func stow(world: Variant, actor: int, item: int) -> bool:
	if merge_into_stack(world, actor, item):
		return true
	for container in reachable_containers(world, actor):
		if store_anywhere(world, item, container):
			return true
	return false

# ---- stacking ----

static func merge_stacks(world: Variant, from: int, into: int) -> int:
	var base: Variant = SimItems.item_base_of(world, into)
	if base == null:
		return 0
	var limit: int = SimItems.base_stack_limit(base as Dictionary)
	if limit <= 1:
		return 0
	var from_base: Variant = world.components.get_component(from, "itemBase")
	var into_base: Variant = world.components.get_component(into, "itemBase")
	if from_base == null or into_base == null:
		return 0
	if String((from_base as Dictionary).get("baseId", "")) != String((into_base as Dictionary).get("baseId", "")):
		return 0
	var source: Variant = world.components.get_component(from, "stack")
	var target: Variant = world.components.get_component(into, "stack")
	if source == null or target == null:
		return 0
	var room: int = limit - int((target as Dictionary).get("count", 0))
	if room <= 0:
		return int((source as Dictionary).get("count", 0))
	var moved: int = mini(room, int((source as Dictionary).get("count", 0)))
	(target as Dictionary)["count"] = int((target as Dictionary).get("count", 0)) + moved
	(source as Dictionary)["count"] = int((source as Dictionary).get("count", 0)) - moved
	if int((source as Dictionary).get("count", 0)) <= 0:
		remove_from_container(world, from)
		world.entities.despawn(from)
		world.components.removeAll(from)
		return 0
	return int((source as Dictionary).get("count", 0))

static func merge_into_stack(world: Variant, actor: int, item: int) -> bool:
	var item_stack: Variant = world.components.get_component(item, "stack")
	if item_stack == null:
		return false
	var base: Variant = world.components.get_component(item, "itemBase")
	if base == null:
		return false
	var bid: String = String((base as Dictionary).get("baseId", ""))
	for candidate in carried_items(world, actor):
		if candidate == item:
			continue
		var cb: Variant = world.components.get_component(candidate, "itemBase")
		if cb == null or String((cb as Dictionary).get("baseId", "")) != bid:
			continue
		if merge_stacks(world, item, candidate) == 0:
			return true
	return false

static func split_stack(world: Variant, item: int, count: int) -> Variant:
	var stack: Variant = world.components.get_component(item, "stack")
	var base: Variant = world.components.get_component(item, "itemBase")
	if stack == null or base == null:
		return null
	var cur: int = int((stack as Dictionary).get("count", 0))
	if count < 1 or count >= cur:
		return null
	# TS: Number.isInteger — in GDScript count is int already; still guard
	var stored: Variant = world.components.get_component(item, "stored")
	if stored == null:
		return null
	var half: int = int(world.entities.spawn())
	world.components.set_component(half, "itemBase", {"baseId": String((base as Dictionary).get("baseId", ""))})
	world.components.set_component(half, "stack", {"count": count})
	var aff: Variant = world.components.get_component(item, "affixes")
	if aff is Dictionary:
		var d: Dictionary = aff as Dictionary
		world.components.set_component(half, "affixes", {
			"prefixes": (d.get("prefixes", []) as Array).duplicate(true),
			"suffixes": (d.get("suffixes", []) as Array).duplicate(true),
		})
	var cond: Variant = world.components.get_component(item, "condition")
	if cond is Dictionary:
		world.components.set_component(half, "condition", (cond as Dictionary).duplicate(true))
	var cont: int = int((stored as Dictionary)["container"])
	if not store_anywhere(world, half, cont):
		world.entities.despawn(half)
		world.components.removeAll(half)
		return null
	(stack as Dictionary)["count"] = cur - count
	return half

# ---- equipment ----

static func equip_slot_for(world: Variant, item: int) -> Variant:
	var base: Variant = SimItems.item_base_of(world, item)
	if base == null:
		return null
	return SimItems.base_equip_slot(base as Dictionary)

static func unequip_item(world: Variant, item: int) -> void:
	for actor in world.components.query(["equipment"]):
		var eq: Variant = world.components.get_component(int(actor), "equipment")
		if eq == null:
			continue
		var slots: Dictionary = (eq as Dictionary)["slots"] as Dictionary
		for slot in slots.keys():
			if int(slots[slot]) == item:
				slots.erase(slot)
				world.events.publish({"type": "item.unequipped", "entity": int(actor), "item": item, "slot": String(slot)})

static func equip(world: Variant, actor: int, item: int, slot: String = "") -> bool:
	var b: Variant = SimItems.item_base_of(world, item)
	var base_slot: Variant = SimItems.base_equip_slot(b as Dictionary) if b is Dictionary else null
	var wanted: String = slot if slot != "" else (String(base_slot) if base_slot != null else "")
	if wanted == "" or wanted == "<null>":
		return false
	if not EQUIP_SLOTS.has(wanted):
		return false
	if base_slot == null or String(base_slot) != wanted:
		return false
	var eq: Variant = world.components.get_component(actor, "equipment")
	if eq == null:
		eq = {"slots": {}}
		world.components.set_component(actor, "equipment", eq)
	if is_within(world, actor, item):
		return false
	var slots: Dictionary = (eq as Dictionary)["slots"] as Dictionary
	var displaced: Variant = slots.get(wanted)
	if displaced != null and int(displaced) == item:
		return true
	remove_from_container(world, item)
	unequip_item(world, item)
	world.components.remove(item, "position")
	slots[wanted] = item
	if displaced != null and not stow(world, actor, int(displaced)):
		drop_at_feet(world, actor, int(displaced))
	world.events.publish({"type": "item.equipped", "entity": actor, "item": item, "slot": wanted})
	return true

static func unequip(world: Variant, actor: int, slot: String) -> bool:
	var eq: Variant = world.components.get_component(actor, "equipment")
	if eq == null:
		return false
	var slots: Dictionary = (eq as Dictionary)["slots"] as Dictionary
	var item: Variant = slots.get(slot)
	if item == null:
		return false
	slots.erase(slot)
	world.events.publish({"type": "item.unequipped", "entity": actor, "item": int(item), "slot": slot})
	if not stow(world, actor, int(item)):
		drop_at_feet(world, actor, int(item))
	return true

# ---- ground ----

static func drop_at_feet(world: Variant, actor: int, item: int) -> bool:
	var pos: Variant = world.components.get_component(actor, "position")
	if pos == null:
		return false
	remove_from_container(world, item)
	unequip_item(world, item)
	world.components.set_component(item, "position", {"x": float((pos as Dictionary)["x"]), "y": float((pos as Dictionary)["y"])})
	world.events.publish({"type": "item.dropped", "entity": actor, "item": item})
	return true

static func ground_items(world: Variant) -> Array[int]:
	var out: Array[int] = []
	for item in world.components.query(["position", "itemBase"]):
		if not world.components.has_component(int(item), "stored"):
			out.append(int(item))
	return out

static func nearest_ground_item(world: Variant, actor: int) -> Variant:
	var here: Variant = world.components.get_component(actor, "position")
	if here == null:
		return null
	var best: Variant = null
	var best_dist: float = PICKUP_REACH * PICKUP_REACH
	for item in ground_items(world):
		var there: Variant = world.components.get_component(item, "position")
		if there == null:
			continue
		var dx: float = float((there as Dictionary)["x"]) - float((here as Dictionary)["x"])
		var dy: float = float((there as Dictionary)["y"]) - float((here as Dictionary)["y"])
		var d: float = dx * dx + dy * dy
		if d <= best_dist:
			best_dist = d
			best = item
	return best

static func pick_up_nearest(world: Variant, actor: int) -> bool:
	var item: Variant = nearest_ground_item(world, actor)
	if item == null:
		return false
	world.components.remove(int(item), "position")
	if not stow(world, actor, int(item)) and not equip(world, actor, int(item)):
		drop_at_feet(world, actor, int(item))
		return false
	world.events.publish({"type": "item.pickedUp", "entity": actor, "item": int(item)})
	return true

static func make_inventory(world: Variant, entity: int) -> void:
	world.components.set_component(entity, "container", {"w": int(POCKET_GRID["w"]), "h": int(POCKET_GRID["h"]), "items": []})
	world.components.set_component(entity, "equipment", {"slots": {}})
	world.components.set_component(entity, "encumbrance", {"kg": 0.0, "ratio": 0.0})

static func make_container_from_base(world: Variant, item: int) -> void:
	var base: Variant = SimItems.item_base_of(world, item)
	if base == null:
		return
	var grid: Variant = SimItems.base_container_grid(base as Dictionary)
	if grid == null:
		return
	world.components.set_component(item, "container", {"w": int((grid as Dictionary)["w"]), "h": int((grid as Dictionary)["h"]), "items": []})

# ---- read model ----

static func _view_of(world: Variant, item: int, placement: Variant) -> Dictionary:
	var size: Dictionary = SimItems.size_of_item(world, item)
	var turned: bool = placement != null and bool((placement as Dictionary).get("rotated", false))
	var w: int = int(size["h"]) if turned else int(size["w"])
	var h: int = int(size["w"]) if turned else int(size["h"])
	var cond: Variant = world.components.get_component(item, "condition")
	var band: String = "sound" if cond == null else SimItems.condition_band(cond as Dictionary)
	var base_id: String = ""
	var b: Variant = world.components.get_component(item, "itemBase")
	if b is Dictionary:
		base_id = String((b as Dictionary).get("baseId", ""))
	var count: int = 1
	var st: Variant = world.components.get_component(item, "stack")
	if st is Dictionary:
		count = int((st as Dictionary).get("count", 1))
	var opens: bool = world.components.has_component(item, "container")
	var x: int = 0
	var y: int = 0
	if placement is Dictionary:
		x = int((placement as Dictionary).get("x", 0))
		y = int((placement as Dictionary).get("y", 0))
	return {
		"item": item, "name": SimItems.item_name(world, item), "baseId": base_id,
		"x": x, "y": y, "w": w, "h": h, "rotated": turned, "count": count, "condition": band, "opens": opens,
	}

static func inventory_view(world: Variant, actor: int) -> Dictionary:
	var eq: Variant = world.components.get_component(actor, "equipment")
	var slots: Array = []
	for slot in EQUIP_SLOTS:
		var item: Variant = null
		if eq is Dictionary:
			item = (eq as Dictionary).get("slots", {}).get(slot)
		slots.append({"slot": slot, "item": null if item == null else _view_of(world, int(item), null)})
	var containers: Array = []
	for container in reachable_containers(world, actor):
		var box: Variant = world.components.get_component(container, "container")
		if box == null:
			continue
		var label: String = "pockets" if container == actor else SimItems.item_name(world, container)
		var items: Array = []
		for placement in (box as Dictionary).get("items", []) as Array:
			var p: Dictionary = placement as Dictionary
			items.append(_view_of(world, int(p["item"]), p))
		containers.append({"container": container, "label": label, "w": int((box as Dictionary)["w"]), "h": int((box as Dictionary)["h"]), "items": items})
	var enc: Variant = world.components.get_component(actor, "encumbrance")
	var overload: float = 0.0
	if enc is Dictionary:
		overload = float((enc as Dictionary).get("ratio", 0.0))
	return {"actor": actor, "slots": slots, "containers": containers, "overload": overload}

static func owns(world: Variant, actor: int, item: int) -> bool:
	return carried_items(world, actor).has(item)

# ---- module registration ----

static func register_module(world: Variant) -> void:
	world.events.subscribe({"id": "inventory.attach-container", "type": "item.spawned", "handler": func(event: Dictionary) -> void:
		make_container_from_base(world, int(event["item"]))
	})
	world.systems.register("inventory.intake", "input", 10, func(w: Variant) -> void:
		for cmd in w.commands.current as Array:
			var c: Dictionary = cmd as Dictionary
			match String(c.get("type", "")):
				"item.move":
					place_at(w, int(c["item"]), int(c["container"]), int(c["x"]), int(c["y"]), bool(c["rotated"]))
				"item.equip":
					for actor in w.components.query(["equipment"]):
						if owns(w, int(actor), int(c["item"])):
							equip(w, int(actor), int(c["item"]), String(c.get("slot", "")))
				"item.unequip":
					for actor in w.components.query(["equipment"]):
						unequip(w, int(actor), String(c["slot"]))
				"item.drop":
					for actor in w.components.query(["equipment"]):
						if owns(w, int(actor), int(c["item"])):
							drop_at_feet(w, int(actor), int(c["item"]))
				"item.pickUp":
					for actor in w.components.query(["equipment"]):
						pick_up_nearest(w, int(actor))
				"item.split":
					split_stack(w, int(c["item"]), int(c["count"]))
				"item.use", "item.wash":
					pass
	)
	world.systems.register("inventory.encumbrance", "needs", 0, func(w: Variant) -> void:
		for actor in w.components.query(["equipment", "encumbrance"]):
			var state: Variant = w.components.get_component(int(actor), "encumbrance")
			if not state is Dictionary:
				continue
			var kg: float = carried_mass_kg(w, int(actor))
			if is_equal_approx(float((state as Dictionary)["kg"]), kg):
				continue
			var capacity: float = 0.0
			if "modifiers" in w and w.modifiers != null and w.modifiers.has_method("resolve"):
				capacity = float(w.modifiers.call("resolve", "carry_capacity", int(actor)))
			var ratio: float = 0.0 if capacity <= 0.0 else kg / capacity
			(state as Dictionary)["kg"] = kg
			(state as Dictionary)["ratio"] = ratio
			w.modifiers.call("remove_by_source", ENCUMBRANCE_SOURCE, int(actor))
			if ratio <= 1.0:
				continue
			var penalty: float = maxf(MIN_OVERLOAD_SPEED, 1.0 - (ratio - 1.0) * OVERLOAD_SPEED_PENALTY)
			w.modifiers.call("add", {"stat": "move_speed", "op": "mul", "value": penalty, "source": ENCUMBRANCE_SOURCE}, int(actor))
			w.modifiers.call("add", {"stat": "stamina_recovery", "op": "mul", "value": penalty, "source": ENCUMBRANCE_SOURCE}, int(actor))
	)
