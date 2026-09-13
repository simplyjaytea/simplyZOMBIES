class_name SimInventory
extends RefCounted

const SimItems = preload("res://sim/modules/items.gd")
const SimGrid = preload("res://sim/inventory/grid.gd")
const SimSerialize = preload("res://sim/kernel/serialize.gd")

# The slot taxonomy, expanded 2026-08-19 on the owner's cut: only slots with a system that
# reads them today. face/eyes/gloves/legs/feet all carry armor coverage (max-composed per
# part by SimInfection.armor_coverage_of, which is what reduces bite transmission and marks
# the paperdoll). Warmth/hygiene slots (undershirt, socks, underwear) deliberately wait for
# the systems that would give them meaning -- an unreadable slot is a dead socket.
# Layering is basic on purpose: slots are independent, no layered armour resolution.
const EQUIP_SLOTS: Array[String] = ["back", "vest", "belt", "primary", "secondary", "head", "face", "eyes", "torso", "gloves", "legs", "feet"]
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


# The best thing in a pack, ranked by one flat content key. One scan, one rank, one home.
#
# This started life as `SimTreatment._best_by_key`, private and serving bandages and sutures. Three
# more supplies wanted the identical pick -- antibiotics, painkillers, and whatever settles a
# stomach -- and the alternative to lifting it here was four copies of the same twelve lines, which
# is how most of this milestone's dead sockets were born: the same idea written twice, and only one
# copy kept current. It sits in `inventory.gd` rather than in `treatment.gd` because treatment
# preloads wounds, infection *and* needs, so those three cannot preload it back; this file depends
# on nothing but items, the grid and the serializer, so everybody can reach it.
#
# `order` is best-first and the index doubles as the rank: reach for the sterile dressing before the
# dirty rag, the clinical course before whatever somebody brewed in a shed. A value the order does
# not name is ignored rather than ranked last -- an unknown grade is content that has outrun its
# reader, and quietly treating it as the worst option would hide exactly that.
#
# `label` names the value in the returned record because callers speak different words for one
# shape: a bandage has a tier, a suture has a kind. The `item` entity rides along so a caller that
# has to *spend* the thing does not go looking for it a second time by base id and find a different
# copy of it. Returns {} when nothing in the pack declares the key at all.
static func best_by_content_key(world: Variant, actor: int, key: String, order: Array[String], label: String) -> Dictionary:
	var best_rank: int = order.size()
	var out: Dictionary = {}
	for item in carried_items(world, actor):
		var base: Variant = SimItems.item_base_of(world, int(item))
		if not (base is Dictionary):
			continue
		var value: String = String((base as Dictionary).get(key, ""))
		if value == "":
			continue
		var rank: int = order.find(value)
		if rank < 0 or rank >= best_rank:
			continue
		best_rank = rank
		out = {label: value, "baseId": String((base as Dictionary).get("id", "")), "item": int(item)}
	return out

static func carried_mass_kg(world: Variant, actor: int) -> float:
	var fn: Callable = func(container: int) -> Array[int]: return contents_of(world, container)
	var mass: float = 0.0
	for item in contents_of(world, actor):
		mass += SimItems.item_mass_kg(world, item, fn)
	for eq in equipped_items(world, actor):
		mass += SimItems.item_mass_kg(world, eq, fn)
	return mass

# What this body can carry: its own `carry_capacity` (STR, the web) plus what the gear on it
# adds. An affix on an item is scoped to the item -- `items.gd` adds it under the item's own id,
# where `resolve(stat, actor)` never looks -- so a pack "of Deep Pockets" was rolled, named,
# saved and felt by nobody (docs/23's defect list, fixed 2026-09-13). Read here at use time from
# what is worn, the `worn_scent_of` pattern: nothing is pushed onto the wearer, so nothing has
# to be taken off them when the pack is dropped, given away or stolen. Worn only, deliberately --
# the suffix applies to containers and armour, and a pack inside a pack does not compound.
# An item's own contribution is its scoped value less the unscoped one, so the stat's base is
# counted once and a global modifier is not counted per item.
static func capacity_of(world: Variant, actor: int) -> float:
	if not ("modifiers" in world and world.modifiers != null and world.modifiers.has_method("resolve")):
		return 0.0
	var capacity: float = float(world.modifiers.call("resolve", "carry_capacity", actor))
	var unscoped: float = float(world.modifiers.call("resolve", "carry_capacity"))
	for item in equipped_items(world, actor):
		var own: float = float(world.modifiers.call("resolve", "carry_capacity", int(item))) - unscoped
		if own > 0.0:
			capacity += own
	return capacity


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
		# docs/10's `pocket` slot: a pouch fitted to a rig is carried by the rig, so a vest with
		# one on it genuinely holds more. A fitted part is **not** in its host's grid -- `attach`
		# takes it out of whatever container it was in, which is what stops one object occupying
		# two places -- so the walk above cannot reach it and this is the reader that can.
		# Without it the `container` block on an armour part would be the milestone's twelfth
		# dead socket: content, a grid, and nothing that could ever put a tin in it.
		#
		# Loaded on demand, not preloaded: attachments.gd preloads this file, and a preload the
		# other way is a cycle and a parse error. `attachments.gd`'s own `_may` does the same.
		for fitted in (_Attachments().call("attached", world, eq) as Dictionary).values():
			if world.components.has_component(int(fitted), "container"):
				out.append(int(fitted))
				walk.call(int(fitted), 2, out, walk)
	return out

static func stow(world: Variant, actor: int, item: int) -> bool:
	if merge_into_stack(world, actor, item):
		return true
	for container in reachable_containers(world, actor):
		if store_anywhere(world, item, container):
			return true
	return false

# ---- stacking ----

# Pour `from` into `into`. Three answers, and the caller must tell them apart:
#   -1  refused -- nothing moved, `from` is exactly as it was;
#    0  merged entirely -- `from` is consumed and despawned;
#    N  N left in `from`, which still exists and still needs a home.
# Every refusal used to return 0, the same word as "merged entirely", so `merge_into_stack`
# read a same-base item with no stack, or a base with no limit, as stored -- and `stow` reported
# an item put away that had gone nowhere (docs/23's defect list, fixed 2026-09-13;
# check_inventory.gd's STACK lane).
static func merge_stacks(world: Variant, from: int, into: int) -> int:
	var base: Variant = SimItems.item_base_of(world, into)
	if base == null:
		return -1
	var limit: int = SimItems.base_stack_limit(base as Dictionary)
	if limit <= 1:
		return -1
	var from_base: Variant = world.components.get_component(from, "itemBase")
	var into_base: Variant = world.components.get_component(into, "itemBase")
	if from_base == null or into_base == null:
		return -1
	if String((from_base as Dictionary).get("baseId", "")) != String((into_base as Dictionary).get("baseId", "")):
		return -1
	var source: Variant = world.components.get_component(from, "stack")
	var target: Variant = world.components.get_component(into, "stack")
	if source == null or target == null:
		return -1
	var room: int = limit - int((target as Dictionary).get("count", 0))
	if room <= 0:
		var left: int = int((source as Dictionary).get("count", 0))
		return left if left > 0 else -1
	var moved: int = mini(room, int((source as Dictionary).get("count", 0)))
	(target as Dictionary)["count"] = int((target as Dictionary).get("count", 0)) + moved
	(source as Dictionary)["count"] = int((source as Dictionary).get("count", 0)) - moved
	if int((source as Dictionary).get("count", 0)) <= 0:
		remove_from_container(world, from)
		world.despawn(from)
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
		if world.components.get_component(candidate, "stack") == null:
			continue
		# 0 alone is "stored": a refusal (-1) or a remainder moves on to the next stack, and
		# whatever is left after the last one is the caller's to put somewhere.
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
		world.despawn(half)
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

# The public name for `_view_of`. A world container's grid is drawn by the same code the pack's is,
# so it needs the same per-item view -- and one builder rather than two is what stops a tin in a
# cupboard from being described differently to the same tin in a pocket.
static func view_of(world: Variant, item: int, placement: Variant) -> Dictionary:
	return _view_of(world, item, placement)


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

# Loaded lazily rather than preloaded, for `SimItems._Attachments`'s reason: all three of these
# preload *this* file, and a preload cycle in GDScript is a parse error rather than something the
# engine resolves. Named as functions rather than inlined at each call site so a path typo is one
# place, and so the `has_method` guards below name a function this file can be grepped against.
static func _Attachments() -> GDScript:
	return load("res://sim/modules/attachments.gd") as GDScript


static func _Needs() -> GDScript:
	return load("res://sim/modules/needs.gd") as GDScript


static func _Treatment() -> GDScript:
	return load("res://sim/modules/treatment.gd") as GDScript


static func _Light() -> GDScript:
	return load("res://sim/modules/light.gd") as GDScript


static func _Noise() -> GDScript:
	return load("res://sim/modules/noise_device.gd") as GDScript


# What the inspect pane on the inventory sheet says about one item: a name, a condition *word*, a
# sentence, where it is worn, and what is fitted to it. `{}` for anything that is not an item.
#
# There is deliberately no number in it and none could be added by accident: the gate serialises
# this and refuses a digit anywhere in it, the same shape `check_ban_health_bar` uses on the
# condition view. Footprint, mass, damage and range are all *known* here and all deliberately
# absent -- the grid already shows the footprint as a shape, weight is the invisible pressure
# docs/10 keeps unprinted, and what a weapon does is the sentence, not the table.
static func inspect_view(world: Variant, actor: int, item: int) -> Dictionary:
	var base: Variant = SimItems.item_base_of(world, item)
	if not (base is Dictionary):
		return {}
	var base_id: String = ""
	var b: Variant = world.components.get_component(item, "itemBase")
	if b is Dictionary:
		base_id = String((b as Dictionary).get("baseId", ""))
	var cond: Variant = world.components.get_component(item, "condition")
	var slot: Variant = SimItems.base_equip_slot(base as Dictionary)
	var worn: bool = false
	var eq: Variant = world.components.get_component(actor, "equipment")
	if eq is Dictionary:
		for s2 in ((eq as Dictionary).get("slots", {}) as Dictionary).values():
			if int(s2) == item:
				worn = true
	# What is on it, and what would go on it. A host lists its own slots and names what fills
	# each; an attachment lists the slots it fits instead, because that is the question the pane
	# is being asked about a scope lying in a bag.
	var fitted: Array = []
	var Att: GDScript = _Attachments()
	var attached: Dictionary = Att.call("attached", world, item)
	for name in Att.call("slots_of", world, item) as Array:
		var in_it: Variant = attached.get(String(name))
		fitted.append({"slot": String(name), "name": "" if in_it == null else SimItems.item_name(world, int(in_it))})
	var fits: Array = []
	var spec: Variant = Att.call("spec_of", world, item)
	if spec is Dictionary:
		for f in (spec as Dictionary).get("fits", []) as Array:
			fits.append(String(f))
	return {
		"item": item,
		"name": SimItems.item_name(world, item),
		"condition": "sound" if cond == null else SimItems.condition_band(cond as Dictionary),
		"description": SimItems.description_of(world, base_id),
		"slot": "" if slot == null else String(slot),
		"worn": worn,
		"attachments": fitted,
		"fits": fits,
		# How much is left in a lamp, as a **word**: "burning steadily", "burning low",
		# "guttering", "dark", and "" for the overwhelming majority of items, which are not lamps.
		# Never a fraction and never a count, for the reason `condition` is a band rather than an
		# integrity: docs/01 clause 4, and the gate above serialises this whole view and refuses a
		# digit anywhere in it. It is also the one reader `SimLightModule.fuel_clause` has, which
		# is the difference between a read model and a dead socket.
		"fuel": _Light().call("fuel_clause", world, item),
	}


# Every verb the word menu may draw, in menu order. A verb is in this list only when its command
# would actually do something, because the screen's rule is that an unavailable verb is *absent*
# rather than greyed with a reason beside it -- `work_panel.gd`'s idiom, and
# `SimTreatment.response_view`'s contract.
#
# Each entry is the sim's own answer to "would this work", not the screen's guess: `use` asks the
# two modules that own `item.use` (needs for anything edible, treatment for anything medical) and
# nothing here re-implements either. That is the dead-socket rule applied to a menu: a verb whose
# availability is computed in the UI is a verb that will one day be offered for a command the sim
# drops on the floor.
const MENU_ORDER: Array[String] = ["equip", "unequip", "use", "modify", "open", "inspect", "split", "drop"]
static func verbs_for(world: Variant, actor: int, item: int) -> Array[String]:
	var out: Array[String] = []
	if item < 0 or not (SimItems.item_base_of(world, item) is Dictionary):
		return out
	if not owns(world, actor, item):
		return out
	var worn: bool = false
	var eq: Variant = world.components.get_component(actor, "equipment")
	if eq is Dictionary:
		for s3 in ((eq as Dictionary).get("slots", {}) as Dictionary).values():
			if int(s3) == item:
				worn = true
	var offered: Dictionary = {"inspect": true}
	# On the bench: offered only for something that comes apart, and only where the survivor could
	# actually work on it. The same rule every verb here follows -- a thing you cannot do is
	# absent, never greyed -- so this appears when you are standing at a bench holding a rifle and
	# at no other time.
	if not _Attachments().call("slots_of", world, item).is_empty():
		var Gunsmith: GDScript = load("res://sim/modules/gunsmith.gd") as GDScript
		if Gunsmith != null and int(Gunsmith.call("bench_in_reach", world, actor)) >= 0:
			offered["modify"] = true
	if worn:
		offered["unequip"] = true
	elif equip_slot_for(world, item) != null:
		offered["equip"] = true
	if not worn:
		offered["drop"] = true
		if world.components.has_component(item, "container"):
			offered["open"] = true
		var st: Variant = world.components.get_component(item, "stack")
		if st is Dictionary and int((st as Dictionary).get("count", 1)) > 1:
			offered["split"] = true
		# Four modules own `item.use` and the menu asks all four, never its own guess: needs for
		# anything edible, treatment for anything medical, light for a cell that has a lamp to go
		# in and a floodlight that has ground to stand on, and noise for a bait device with a patch
		# of ground in front of you to stand it on.
		if bool(_Needs().call("can_use", world, actor, item)) \
				or bool(_Treatment().call("can_use_supply", world, actor, item)) \
				or bool(_Light().call("can_use", world, actor, item)) \
				or bool(_Noise().call("can_use", world, actor, item)):
			offered["use"] = true
	for verb in MENU_ORDER:
		if offered.has(verb):
			out.append(verb)
	return out


# What the quick strip along the bottom of the screen shows, and what the number keys reach: the
# pockets first, then whatever is worn on the belt, in the order the grids hold them. Six at most,
# because six is how many keys the strip has.
#
# The back is deliberately absent, and it is the same rule the old pinnable windows followed: a
# pouch on your front is reachable mid-fight and a backpack is not (the owner's call, 2026-08-19).
# The vest is absent too -- twelve entries would be a strip nobody can read at a glance, and the
# belt is what the fiction says your hand finds.
const STRIP_SLOTS: int = 6
static func quick_strip_view(world: Variant, actor: int) -> Array:
	var out: Array = []
	var boxes: Array[int] = []
	if world.components.has_component(actor, "container"):
		boxes.append(actor)
	var eq: Variant = world.components.get_component(actor, "equipment")
	if eq is Dictionary:
		var belt: Variant = ((eq as Dictionary).get("slots", {}) as Dictionary).get("belt")
		if belt != null and world.components.has_component(int(belt), "container"):
			boxes.append(int(belt))
	for box in boxes:
		var c: Variant = world.components.get_component(box, "container")
		if not (c is Dictionary):
			continue
		for placement in (c as Dictionary).get("items", []) as Array:
			if out.size() >= STRIP_SLOTS:
				return out
			var item: int = int((placement as Dictionary)["item"])
			var count: int = 1
			var st: Variant = world.components.get_component(item, "stack")
			if st is Dictionary:
				count = int((st as Dictionary).get("count", 1))
			out.append({"item": item, "name": SimItems.item_name(world, item), "count": count})
	return out


static func owns(world: Variant, actor: int, item: int) -> bool:
	return carried_items(world, actor).has(item)

# Whether a proposed move touches a world container, and if so whether somebody is actually
# standing at it with it open. A move between two things on your own body is nobody's business but
# the grid's and takes the fast path unchanged.
#
# Refusing publishes nothing: a drag that lands on a cupboard you have walked away from is a
# mis-drag, and `container.refused` is for a verb somebody asked for out loud.
static func _move_is_reachable(world: Variant, item: int, container: int) -> bool:
	var Containers: GDScript = _Containers()
	var touches: bool = _is_world_container(world, container) or _is_world_container(world, _holder_of(world, item))
	if not touches:
		return true
	for actor in world.components.query(["controlled", "position"]):
		var open_box: int = int(Containers.call("opened_by", world, int(actor)))
		if open_box < 0:
			continue
		if container == open_box or _holder_of(world, item) == open_box:
			return true
	return false


static func _is_world_container(world: Variant, entity: int) -> bool:
	return entity >= 0 and world.components.has_component(entity, "searchable")


# Which container an item is sitting in, or -1 for worn, held or lying on the ground.
static func _holder_of(world: Variant, item: int) -> int:
	var stored: Variant = world.components.get_component(item, "stored")
	return int((stored as Dictionary).get("container", -1)) if stored is Dictionary else -1


static func _Containers() -> GDScript:
	return load("res://sim/modules/containers.gd") as GDScript


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
					# The reach guard, and the only thing a world container needed that a pack did
					# not. `place_at` has never known who was moving the item, which was safe while
					# every reachable container was on the actor's own body; a cupboard across the
					# room is not, and without this a screen could move a thing into or out of one
					# from anywhere on the map.
					if _move_is_reachable(w, int(c["item"]), int(c["container"])):
						place_at(w, int(c["item"]), int(c["container"]), int(c["x"]), int(c["y"]), bool(c["rotated"]))
				"item.equip":
					for actor in w.components.query(["equipment"]):
						if owns(w, int(actor), int(c["item"])):
							equip(w, int(actor), int(c["item"]), String(c.get("slot", "")))
				"item.unequip":
					# Scoped, like the three cases around it. This used to unequip the named slot
					# on **every** entity carrying an `equipment` component -- and
					# ui/inventory_panel.gd pushes this command straight off the paperdoll, so one
					# click on the player's own coat stripped that slot from every survivor in the
					# colony. A slot name alone cannot say whose command it is, which is why the
					# other three cases all name an item: the command carries one now, and the
					# actor wearing it is the actor this is for. A command with no item falls back
					# to the controlled survivor rather than to everybody.
					for actor in w.components.query(["equipment"]):
						var eq: Variant = w.components.get_component(int(actor), "equipment")
						if not (eq is Dictionary):
							continue
						var worn: Variant = ((eq as Dictionary)["slots"] as Dictionary).get(String(c["slot"]))
						if worn == null:
							continue
						if c.has("item"):
							if int(c["item"]) != int(worn):
								continue
						elif not w.components.has_component(int(actor), "controlled"):
							continue
						unequip(w, int(actor), String(c["slot"]))
				"item.drop":
					for actor in w.components.query(["equipment"]):
						if owns(w, int(actor), int(c["item"])):
							drop_at_feet(w, int(actor), int(c["item"]))
				"item.pickUp":
					# Same shape as item.unequip above: this fired for every entity with an
					# `equipment` component, so one pick-up command had the whole colony reach
					# for whatever was nearest to each of them. The player is who pressed it.
					for actor in w.components.query(["equipment", "controlled"]):
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
			var capacity: float = capacity_of(w, int(actor))
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
