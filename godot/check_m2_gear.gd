extends SceneTree
# The worn-gear slots -- the taxonomy expansion of 2026-08-19 (face, eyes, gloves, legs,
# feet joining head/torso/vest/back/belt/primary/secondary).
#
# The rule this gate exists to hold: **a slot nothing can fill, or an item nothing reads,
# is a dead socket** -- this milestone found eight of those. So every assertion here pairs
# a slot with the system that gives it meaning: the item is findable in a shipped loot
# table (the check_m2_attach precedent), equipping it moves armor_coverage_of -- the same
# number that reduces bite transmission -- and the condition view's `armored` word follows
# it, which is what the paperdoll draws. Coverage composes by max, never sum, and that is
# pinned here because two head items shipping together is exactly how a sum would sneak in.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const SimCondition = preload("res://sim/condition.gd")
const Clock = preload("res://sim/time/clock.gd")

# id -> {slot, a part it must cover}
const GEAR: Dictionary = {
	"item.mask.cloth": {"slot": "face", "part": "head"},
	"item.glasses.safety": {"slot": "eyes", "part": "head"},
	"item.gloves.work": {"slot": "gloves", "part": "hand_left"},
	"item.pants.canvas": {"slot": "legs", "part": "leg_left"},
	"item.boots.leather": {"slot": "feet", "part": "foot_left"},
}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _content_declares_the_slots_and_the_slots_have_items() and ok
	ok = _every_piece_is_findable_in_a_shipped_table() and ok
	ok = _wearing_it_covers_the_part_and_the_view_says_so() and ok
	ok = _coverage_composes_by_max_not_sum() and ok
	ok = _a_slot_refuses_gear_that_does_not_belong_there() and ok
	if ok:
		print("M2_GEAR_OK slots have items, items are findable, coverage moves and composes by max")
		quit(0)
	else:
		push_error("M2_GEAR_FAIL")
		quit(1)


func _world() -> Variant:
	var f: Dictionary = {"seed": 47, "tick_hz": 20, "map": {"width": 24, "height": 24, "walls": []}, "player": {"id": 0, "x": 8.5, "y": 12.5, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	var w: Variant = World.new(f)
	w.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	SimBoot.attach_kernel(w, SimTileMap.blank_map(24, 24))
	SimHealth.register_module(w)
	SimInventory.register_module(w)
	SimItems.register_module(w)
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	SimHealth.make_survivor_body(w, w.player)
	SimInventory.make_inventory(w, w.player)
	return w


func _spawn(w: Variant, id: String) -> int:
	return SimItems.spawn_item(w, id, {"tier": "scavenged"})


# --- CONTENT ----------------------------------------------------------------------------------

func _content_declares_the_slots_and_the_slots_have_items() -> bool:
	var w: Variant = _world()
	var slots_with_items: Dictionary = {}
	var by_id: Dictionary = {}
	for entry_v in SimItems.content_entries(w, "item"):
		var e: Dictionary = entry_v as Dictionary
		by_id[String(e.get("id", ""))] = e
		if e.has("equipSlot"):
			var s: String = String(e["equipSlot"])
			if not SimInventory.EQUIP_SLOTS.has(s):
				push_error("CONTENT: %s declares equipSlot \"%s\" the sim does not have" % [String(e.get("id", "")), s])
				return false
			slots_with_items[s] = true
	for slot in SimInventory.EQUIP_SLOTS:
		if not slots_with_items.has(String(slot)):
			push_error("CONTENT: slot \"%s\" has no shipped item that can fill it -- a dead socket" % String(slot))
			return false
	for id in GEAR.keys():
		var e2: Variant = by_id.get(String(id))
		if not (e2 is Dictionary):
			push_error("CONTENT: %s is not in the content tree" % String(id))
			return false
		if String((e2 as Dictionary).get("equipSlot", "")) != String((GEAR[id] as Dictionary)["slot"]):
			push_error("CONTENT: %s does not declare slot %s" % [String(id), String((GEAR[id] as Dictionary)["slot"])])
			return false
		var armor: Variant = (e2 as Dictionary).get("armor")
		if not (armor is Dictionary) or not (armor as Dictionary).has(String((GEAR[id] as Dictionary)["part"])):
			push_error("CONTENT: %s carries no armor for %s, so equipping it would do nothing" % [String(id), String((GEAR[id] as Dictionary)["part"])])
			return false
	print("  CONTENT: every slot has an item, every gear piece covers its part")
	return true


# --- FINDABLE ---------------------------------------------------------------------------------

func _every_piece_is_findable_in_a_shipped_table() -> bool:
	var w: Variant = _world()
	# `content_entries` only knows items and affixes; loot tables are found by shape in the
	# flat tree, the same way check_loot reaches them.
	var findable: Dictionary = {}
	var tables: int = 0
	for file_v in (w.content as Dictionary).values():
		if not (file_v is Array):
			continue
		for entry_v in file_v as Array:
			if not (entry_v is Dictionary):
				continue
			var t: Dictionary = entry_v as Dictionary
			if not String(t.get("id", "")).begins_with("loot."):
				continue
			tables += 1
			for row_v in t.get("entries", []) as Array:
				findable[String((row_v as Dictionary).get("item", ""))] = true
	if tables == 0:
		push_error("FINDABLE: no loot tables loaded, so this assertion has nothing to judge")
		return false
	for id in GEAR.keys():
		if not findable.has(String(id)):
			push_error("FINDABLE: %s is in no loot table -- complete, correct, and unreachable" % String(id))
			return false
	# The true negative that keeps the scan honest: an id that does not exist must not pass.
	if findable.has("item.gear.imaginary"):
		push_error("FINDABLE: the scan found an item that does not exist")
		return false
	print("  FINDABLE: all five pieces reachable across %d tables" % tables)
	return true


# --- COVERAGE ---------------------------------------------------------------------------------

func _wearing_it_covers_the_part_and_the_view_says_so() -> bool:
	var w: Variant = _world()
	var gloves: int = _spawn(w, "item.gloves.work")
	if SimInfection.armor_coverage_of(w, w.player, "hand_left") != 0.0:
		push_error("COVERAGE: bare hands report coverage")
		return false
	if not SimInventory.equip(w, w.player, gloves):
		push_error("COVERAGE: gloves refused their own slot")
		return false
	var cov: float = SimInfection.armor_coverage_of(w, w.player, "hand_left")
	if absf(cov - 0.4) > 0.001:
		push_error("COVERAGE: worn gloves cover hand_left at %f, expected 0.4" % cov)
		return false
	var armored: bool = false
	for part_v in SimCondition.view(w, w.player).get("parts", []) as Array:
		var p: Dictionary = part_v as Dictionary
		if String(p.get("part", "")) == "hand_left":
			armored = bool(p.get("armored", false))
	if not armored:
		push_error("COVERAGE: the condition view does not mark a gloved hand armored")
		return false
	# The true negative: taking them off takes the word away.
	SimInventory.unequip(w, w.player, "gloves")
	if SimInfection.armor_coverage_of(w, w.player, "hand_left") != 0.0:
		push_error("COVERAGE: coverage survived unequipping")
		return false
	print("  COVERAGE: gloves cover the hand while worn and only while worn")
	return true


func _coverage_composes_by_max_not_sum() -> bool:
	var w: Variant = _world()
	SimInventory.equip(w, w.player, _spawn(w, "item.mask.cloth"))
	SimInventory.equip(w, w.player, _spawn(w, "item.glasses.safety"))
	var cov: float = SimInfection.armor_coverage_of(w, w.player, "head")
	# mask 0.2 and glasses 0.1: max is 0.2; a sum would be 0.3 and would be the exploit.
	if absf(cov - 0.2) > 0.001:
		push_error("MAX: mask + glasses cover head at %f, expected max 0.2" % cov)
		return false
	print("  MAX: two head pieces compose by max, not sum")
	return true


# --- SLOTS ------------------------------------------------------------------------------------

func _a_slot_refuses_gear_that_does_not_belong_there() -> bool:
	var w: Variant = _world()
	var gloves: int = _spawn(w, "item.gloves.work")
	if SimInventory.equip(w, w.player, gloves, "head"):
		push_error("SLOTS: gloves were accepted on the head")
		return false
	if not SimInventory.equip(w, w.player, gloves, "gloves"):
		push_error("SLOTS: gloves refused the gloves slot")
		return false
	print("  SLOTS: an item goes only where it belongs")
	return true
