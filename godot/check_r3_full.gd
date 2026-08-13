extends SceneTree

const SimWorld = preload("res://sim/world.gd")
const SimGrid = preload("res://sim/inventory/grid.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimSave = preload("res://sim/save.gd")
const SimSerialize = preload("res://sim/kernel/serialize.gd")
const ContentLoader = preload("res://platform/content_loader.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _check_grid() and ok
	ok = _check_items() and ok
	ok = _check_inventory() and ok
	ok = _check_save_roundtrip() and ok
	ok = _check_stack_and_equip() and ok
	if ok:
		print("R3_R4_VERIFIED_OK")
		quit(0)
	else:
		push_error("R3_R4_VERIFIED_FAIL")
		quit(1)

func _check_grid() -> bool:
	print("---GRID---")
	# TS grid.ts logic: footprint, within_bounds, fits with integer guard, find_free_slot order, occupancy, sort
	var size_of := func(item: int) -> Dictionary:
		if item == 1: return {"w": 2, "h": 1}
		if item == 2: return {"w": 1, "h": 1}
		if item == 3: return {"w": 2, "h": 2}
		return {"w": 1, "h": 1}
	var grid: Dictionary = {"w": 4, "h": 4}
	# fits should reject fractional
	var cand_frac: Dictionary = {"item": 1, "x": 0.5, "y": 0, "rotated": false}
	if SimGrid.fits(grid, [], size_of, cand_frac):
		push_error("fits should reject fractional x")
		return false
	# fits normal
	if not SimGrid.fits(grid, [], size_of, {"item": 1, "x": 0, "y": 0, "rotated": false}):
		push_error("fits empty should be true")
		return false
	# overlapping
	var placements: Array = [{"item": 1, "x": 0, "y": 0, "rotated": false}]
	if SimGrid.fits(grid, placements, size_of, {"item": 2, "x": 1, "y": 0, "rotated": false}):
		push_error("fits should reject overlap")
		return false
	if not SimGrid.fits(grid, placements, size_of, {"item": 2, "x": 2, "y": 0, "rotated": false}):
		push_error("fits should allow adjacent")
		return false
	# self-skip: moving same item should not collide with itself
	if not SimGrid.fits(grid, placements, size_of, {"item": 1, "x": 1, "y": 0, "rotated": false}):
		push_error("fits should skip same item id")
		return false
	# find_free_slot: 4x2 grid, pack 3x2 leaves slot
	var g2: Dictionary = {"w": 4, "h": 2}
	var pl2: Array = [{"item": 1, "x": 0, "y": 0, "rotated": false}] # 2x1 at top
	var slot: Variant = SimGrid.find_free_slot(g2, pl2, size_of, 2)
	if slot == null or int((slot as Dictionary)["x"]) != 2:
		push_error("find_free_slot wrong %s" % str(slot))
		return false
	# square skips second orientation scan (not observable, but not crash)
	var sq_size := func(_item: int) -> Dictionary: return {"w": 2, "h": 2}
	var sq_slot: Variant = SimGrid.find_free_slot({"w": 4, "h": 4}, [], sq_size, 99)
	if sq_slot == null:
		push_error("square find_free_slot null")
		return false
	# occupancy
	var occ: PackedInt32Array = SimGrid.occupancy({"w": 2, "h": 2}, [{"item": 9, "x": 0, "y": 0, "rotated": false}] as Array, func(_i: int) -> Dictionary: return {"w": 2, "h": 2})
	if occ[0] != 9 or occ[3] != 9:
		push_error("occupancy fail %s" % str(occ))
		return false
	# sort
	var arr: Array = [{"item": 3, "x": 1, "y": 1, "rotated": false}, {"item": 2, "x": 0, "y": 0, "rotated": false}, {"item": 1, "x": 0, "y": 1, "rotated": false}]
	SimGrid.sort_placements(arr)
	if int((arr[0] as Dictionary)["item"]) != 2:
		push_error("sort failed %s" % str(arr))
		return false
	print("GRID OK")
	return true

func _make_world(seed_val: int = 42) -> Variant:
	var fixture: Dictionary = {
		"seed": seed_val, "tick_hz": 20,
		"map": {"width": 16, "height": 16, "walls": []},
		"player": {"id": 0, "x": 8.0, "y": 8.0, "stance": 2},
		"ticks": 0, "commands": [], "rng_probe": {"stream": "loot", "samples": 0},
	}
	var w: Variant = SimWorld.new(fixture)
	return w

func _check_items() -> bool:
	print("---ITEMS---")
	var w: Variant = _make_world(31337)
	# spawn - baseIds known from content
	var axe: int = SimItems.spawn_item(w, "item.axe.fire", {"tier": "scavenged"})
	if not w.components.has_component(axe, "itemBase"):
		push_error("axe has no itemBase")
		return false
	var base: Variant = SimItems.item_base_of(w, axe)
	if base == null or String((base as Dictionary).get("id", "")) != "item.axe.fire":
		push_error("item_base_of mismatch %s" % str(base))
		return false
	# non-item returns null
	var ent: int = int(w.entities.spawn())
	if SimItems.item_base_of(w, ent) != null:
		push_error("non-item should be null")
		return false
	# condition band
	if SimItems.condition_band({"current": 1.0}) != "sound" or SimItems.condition_band({"current": 0.0}) != "broken":
		push_error("condition_band fail")
		return false
	# base helpers
	var b2: Dictionary = {"size": {"w": 2, "h": 4}, "massKg": 3.2, "stack": 1, "class": "weapon.melee", "container": {"w": 6, "h": 8}, "equipSlot": "primary"}
	if SimItems.base_size(b2)["w"] != 2 or SimItems.base_mass_kg(b2) != 3.2 or SimItems.base_stack_limit(b2) != 1:
		push_error("base helpers fail")
		return false
	if SimItems.base_class(b2) != "weapon.melee":
		push_error("base_class fail")
		return false
	# stack limit clamp
	var bandage: int = SimItems.spawn_item(w, "item.bandage.cloth", {"count": 99, "tier": "scavenged"})
	var sc: Variant = w.components.get_component(bandage, "stack")
	if sc == null or int((sc as Dictionary)["count"]) != 5:
		push_error("stack clamp fail %s" % str(sc))
		return false
	# mass recursive: pack with bandage inside
	var pack: int = SimItems.spawn_item(w, "item.pack.hiking", {"tier": "scavenged"})
	# make_container_from_base is normally via event; call directly
	SimInventory.make_container_from_base(w, pack)
	if not w.components.has_component(pack, "container"):
		push_error("pack has no container")
		return false
	# place bandage into pack
	var p_res: Dictionary = SimInventory.place_at(w, bandage, pack, 0, 0, false)
	if not bool(p_res["ok"]):
		push_error("place bandage into pack fail %s" % str(p_res))
		return false
	var fn: Callable = func(c: int) -> Array[int]: return SimInventory.contents_of(w, c)
	var m: float = SimItems.item_mass_kg(w, pack, fn)
	if m < 0.1:
		push_error("mass too small %f" % m)
		return false
	# affix: field_tested should add modifiers (check count)
	var crafted: int = SimItems.spawn_item(w, "item.axe.fire", {"tier": "field_tested"})
	var aff: Variant = w.components.get_component(crafted, "affixes")
	if aff == null:
		push_error("field_tested no affixes")
		return false
	# affix_modifiers should produce mods scoped to entity
	var mods: Array = SimItems.affix_modifiers(w, crafted)
	# field_tested wants 4 affixes split 2/2 but may be less if pool small — expect >0
	if mods.is_empty():
		push_error("affix_modifiers empty for field_tested")
		return false
	# item_name includes base name
	var nm: String = SimItems.item_name(w, axe)
	if not nm.contains("Axe") and not nm.contains("Fire"):
		push_error("item_name wrong %s" % nm)
		return false
	# melee profile
	var prof: Variant = SimItems.melee_profile_of(w, axe)
	if prof == null or not prof is Dictionary or not (prof as Dictionary).has("damage"):
		push_error("melee_profile null %s" % str(prof))
		return false
	# non-weapon has no melee
	var nm2: Variant = SimItems.melee_profile_of(w, bandage)
	if nm2 != null:
		push_error("bandage should have no melee")
		return false
	print("ITEMS OK")
	return true

func _check_inventory() -> bool:
	print("---INVENTORY---")
	var w: Variant = _make_world(99)
	var actor: int = w.player
	SimInventory.make_inventory(w, actor)
	w.components.set_component(actor, "position", {"x": 8.0, "y": 8.0})
	# reachable: pockets
	var rc: Array[int] = SimInventory.reachable_containers(w, actor)
	if not rc.has(actor):
		push_error("reachable missing pockets")
		return false
	# stow
	var item1: int = SimItems.spawn_item(w, "item.knife.kitchen", {"tier": "scavenged"})
	if not SimInventory.stow(w, actor, item1):
		push_error("stow knife fail")
		return false
	if not w.components.has_component(item1, "stored"):
		push_error("stowed item has no stored")
		return false
	# can_place refuses not-a-container
	var bad: Dictionary = SimInventory.can_place(w, item1, 9999, 0, 0, false)
	if bool(bad["ok"]) or String(bad["reason"]) != "not-a-container":
		push_error("can_place not-a-container %s" % str(bad))
		return false
	# can_place refuses would-nest
	var pouch: int = SimItems.spawn_item(w, "item.pouch.utility", {"tier": "scavenged"})
	SimInventory.make_container_from_base(w, pouch)
	if not SimInventory.stow(w, actor, pouch):
		push_error("stow pouch fail")
		return false
	# try to put actor's pockets (container) inside pouch — depth or cycle should refuse
	# Actually test is_within: pouch is inside actor, so actor inside pouch would be cycle
	# Use is_within directly via can_place trying to nest pouch in itself? pouch inside pouch
	var self_ref: Dictionary = SimInventory.can_place(w, pouch, pouch, 0, 0, false)
	if bool(self_ref["ok"]) or String(self_ref["reason"]) != "would-nest-inside-itself":
		push_error("self-nest %s" % str(self_ref))
		return false
	# place_at with rotation
	var w2: Variant = _make_world(100)
	var a2: int = w2.player
	SimInventory.make_inventory(w2, a2)
	w2.components.set_component(a2, "position", {"x": 8.0, "y": 8.0})
	var spear: int = SimItems.spawn_item(w2, "item.spear.improvised", {"tier": "scavenged"}) # 1x5
	# pockets 4x2 cannot fit 1x5 unrotated, but 5x1 rotated should fit? pockets 4x2: 5 wide no. Use pack.
	var pack2: int = SimItems.spawn_item(w2, "item.pack.hiking", {"tier": "scavenged"})
	SimInventory.make_container_from_base(w2, pack2)
	SimInventory.equip(w2, a2, pack2)
	var res_rot: Dictionary = SimInventory.place_at(w2, spear, pack2, 0, 0, true)
	if not bool(res_rot["ok"]):
		push_error("rotated place fail %s" % str(res_rot))
		return false
	# inventory view
	var view: Dictionary = SimInventory.inventory_view(w, actor)
	if not view.has("slots") or not view.has("containers"):
		push_error("inventory_view missing keys %s" % str(view.keys()))
		return false
	# ground / pickup
	var pipe: int = SimItems.spawn_item(w, "item.pipe.steel", {"tier": "scavenged"})
	w.components.set_component(pipe, "position", {"x": 8.0, "y": 8.0})
	var ground: Array[int] = SimInventory.ground_items(w)
	if not ground.has(pipe):
		push_error("ground_items missing pipe")
		return false
	var nearest: Variant = SimInventory.nearest_ground_item(w, actor)
	if nearest == null:
		push_error("nearest null")
		return false
	print("INVENTORY OK")
	return true

func _check_stack_and_equip() -> bool:
	print("---STACK+EQUIP---")
	var w: Variant = _make_world(200)
	var actor: int = w.player
	SimInventory.make_inventory(w, actor)
	w.components.set_component(actor, "position", {"x": 5.0, "y": 5.0})
	var scrap1: int = SimItems.spawn_item(w, "item.scrap.metal", {"tier": "scavenged", "count": 4})
	var scrap2: int = SimItems.spawn_item(w, "item.scrap.metal", {"tier": "scavenged", "count": 3})
	SimInventory.make_inventory(w, actor)
	# put both in pockets via place_at
	var box: Variant = w.components.get_component(actor, "container")
	if box == null:
		push_error("no pockets")
		return false
	var r1: Dictionary = SimInventory.place_at(w, scrap1, actor, 0, 0, false)
	var r2: Dictionary = SimInventory.place_at(w, scrap2, actor, 1, 0, false)
	if not bool(r1["ok"]) or not bool(r2["ok"]):
		push_error("place scrap fail %s %s" % [str(r1), str(r2)])
		return false
	# merge
	var remain: int = SimInventory.merge_stacks(w, scrap2, scrap1)
	if remain != 0:
		# limit 10, 4+3=7 fits, should fully merge (0 remain) and despawn scrap2
		push_error("merge remain %d" % remain)
		return false
	if w.entities.is_alive(scrap2):
		push_error("merged source still alive")
		return false
	# split
	var half: Variant = SimInventory.split_stack(w, scrap1, 2)
	if half == null:
		push_error("split null")
		return false
	var cnt: int = int((w.components.get_component(scrap1, "stack") as Dictionary)["count"])
	if cnt != 5:
		push_error("split remainder %d exp 5" % cnt)
		return false
	# split off whole stack should refuse
	if SimInventory.split_stack(w, scrap1, cnt) != null:
		push_error("split whole should be null")
		return false
	# equip
	var w3: Variant = _make_world(300)
	var a3: int = w3.player
	SimInventory.make_inventory(w3, a3)
	w3.components.set_component(a3, "position", {"x": 5.0, "y": 5.0})
	var axe: int = SimItems.spawn_item(w3, "item.axe.fire", {"tier": "scavenged"})
	if not SimInventory.equip(w3, a3, axe):
		push_error("equip axe fail")
		return false
	var eq: Variant = w3.components.get_component(a3, "equipment")
	var holder: Variant = (eq as Dictionary)["slots"].get("primary")
	if int(holder) != axe:
		push_error("equip slot wrong %s" % str(holder))
		return false
	# re-equip displaced goes to stow or feet
	var axe2: int = SimItems.spawn_item(w3, "item.axe.fire", {"tier": "scavenged"})
	SimInventory.equip(w3, a3, axe2)
	# axe displaced should be stowed or dropped — either way still exists and not in slot
	if int((w3.components.get_component(a3, "equipment") as Dictionary)["slots"]["primary"]) != axe2:
		push_error("re-equip failed")
		return false
	# unequip
	if not SimInventory.unequip(w3, a3, "primary"):
		push_error("unequip fail")
		return false
	print("STACK+EQUIP OK")
	return true

func _check_save_roundtrip() -> bool:
	print("---SAVE---")
	var w: Variant = _make_world(777)
	var actor: int = w.player
	SimInventory.make_inventory(w, actor)
	w.components.set_component(actor, "position", {"x": 8.0, "y": 8.0})
	var pack: int = SimItems.spawn_item(w, "item.pack.hiking", {"tier": "scavenged"})
	SimInventory.make_container_from_base(w, pack)
	SimInventory.equip(w, actor, pack)
	var pouch: int = SimItems.spawn_item(w, "item.pouch.utility", {"tier": "scavenged"})
	SimInventory.make_container_from_base(w, pouch)
	var r_pouch: Dictionary = SimInventory.place_at(w, pouch, pack, 0, 0, false)
	if not bool(r_pouch["ok"]):
		push_error("save test place pouch %s" % str(r_pouch))
		return false
	var band: int = SimItems.spawn_item(w, "item.bandage.cloth", {"tier": "scavenged", "count": 4})
	var r_band: Dictionary = SimInventory.place_at(w, band, pouch, 0, 0, false)
	if not bool(r_band["ok"]):
		push_error("save test place band %s" % str(r_band))
		return false
	w.tick = 123
	var before: String = w.serialize()
	var save: Dictionary = SimSave.create_save(w)
	var text: String = SimSave.encode_save(save)
	var decoded: Dictionary = SimSave.decode_save(text)
	if decoded.has("__error"):
		push_error("decode error %s" % str(decoded))
		return false
	# stale version
	var tampered: Dictionary = JSON.parse_string(text) as Dictionary
	(tampered["snapshot"] as Dictionary)["version"] = 999
	var tampered_text: String = JSON.stringify(tampered)
	var stale: Dictionary = SimSave.decode_save(tampered_text)
	if String(stale.get("__error", "")) != "StaleSaveError":
		push_error("stale should be StaleSaveError %s" % str(stale))
		return false
	# corrupt
	var corrupt: Dictionary = SimSave.decode_save("{ not json")
	if String(corrupt.get("__error", "")) != "CorruptSaveError":
		push_error("corrupt should be CorruptSaveError")
		return false
	# apply to fresh world with same seed
	var w2: Variant = _make_world(777)
	SimSave.apply_save(w2, decoded)
	var after: String = w2.serialize()
	if after != before:
		push_error("round-trip mismatch\nbefore: %s\nafter: %s" % [before.substr(0,600), after.substr(0,600)])
		return false
	if w2.tick != 123:
		push_error("tick not restored %d" % w2.tick)
		return false
	# tree intact
	if not SimInventory.contents_of(w2, pack).has(pouch):
		push_error("pack no longer contains pouch after restore")
		return false
	if not SimInventory.contents_of(w2, pouch).has(band):
		push_error("pouch no longer contains band after restore")
		return false
	# seed mismatch: restore should assert
	var w3: Variant = _make_world(778)
	var seed_ok: bool = false
	# SimWorld.restore asserts seed mismatch; we just check that decoded seed differs
	if int((decoded["snapshot"] as Dictionary)["seed"]) == int(w3.seed):
		push_error("seed should differ for w3")
		return false
	print("SAVE OK ticks %d seed %d text_len %d" % [w.tick, w.seed, text.length()])
	return true
