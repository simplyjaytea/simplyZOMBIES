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
	ok = _unequipping_one_coat_undresses_one_survivor() and ok
	ok = _the_catalogue_is_findable_and_read() and ok
	if ok:
		print("M2_GEAR_OK slots have items, items are findable, coverage moves and composes by max, a command undresses one person, and every base in the catalogue is reachable and read by something")
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


# One command, one wearer.
#
# `inventory.intake`'s `item.unequip` case looped every entity with an `equipment` component and
# called `unequip(actor, slot)` on all of them -- no ownership test, where the `item.equip`,
# `item.drop` and `item.pickUp` cases beside it all had one. ui/inventory_panel.gd pushes this
# command straight off the paperdoll, so clicking your own coat took the coat off everybody in the
# colony. A slot name cannot say whose command it is; the item in the slot can, so the command
# carries one.
#
# Both directions: the addressed survivor must actually be undressed (or "nobody is undressed"
# would pass), and the bystander must still be dressed.
func _unequipping_one_coat_undresses_one_survivor() -> bool:
	var w: Variant = _world()
	var them: int = int(w.entities.spawn())
	w.components.set_component(them, "position", {"x": 9.5, "y": 12.5})
	SimHealth.make_survivor_body(w, them)
	SimInventory.make_inventory(w, them)

	var mine: int = _spawn(w, "item.gloves.work")
	var theirs: int = _spawn(w, "item.gloves.work")
	if not SimInventory.equip(w, w.player, mine) or not SimInventory.equip(w, them, theirs):
		push_error("could not dress both survivors for the assertion")
		return false
	var slot: String = String(SimInventory.equip_slot_for(w, mine))
	if slot.is_empty():
		push_error("the fixture item has no equip slot")
		return false

	w.commands.push({"type": "item.unequip", "slot": slot, "item": mine})
	w.step()

	if _worn(w, w.player, slot) != null:
		push_error("the survivor the command named is still wearing it")
		return false
	if _worn(w, them, slot) == null:
		push_error("unequipping one survivor's %s took the bystander's off too" % slot)
		return false
	print("UNEQUIP OK one command, one wearer, the bystander keeps their gear")
	return true


func _worn(w: Variant, actor: int, slot: String) -> Variant:
	var eq: Variant = w.components.get_component(actor, "equipment")
	if not (eq is Dictionary):
		return null
	return ((eq as Dictionary)["slots"] as Dictionary).get(slot)


# --- CATALOGUE --------------------------------------------------------------------------------
#
# The dead-socket rule, applied to the whole tree rather than to five named pieces: a base that
# does something -- a slot, a weapon profile, armour, a grid, food, drink, fuel, light, a bench
# operation -- and that nothing in the world can hand a survivor is content nobody will ever hold.
# Reachable means: rolled by a shipped loot table, carried in a shipped kit, left behind by another
# base's `empties`, or produced by a job (cooked food, the one such base, allowed by name below).
# The first run of this lane found the demolition sledge in no table at all -- complete, drawn,
# gated by the worn look, and unreachable since it shipped; it is in the military cache now. Beside it, the class the request called "tools": a `tool` base with no
# `light` and no `modification` block is a tool nothing reads, which is exactly the socket this
# milestone keeps paying for, so the lane refuses it.

# `ammo` joined this list with the caliber slice. A round was `class: material` with a `stack`
# and nothing else, so it declared none of these keys and this lane never asked whether it was
# reachable -- the CATALOGUE lane below reached the eight shipped rounds only through the
# weapons that name them in `ranged.ammo`. A *variant* round is named by no weapon, so without
# this key a slug in no loot table would have been complete, correct and unfindable.
#
# `attachment` is deliberately **not** on this list, and the armour-slot slice is when that became
# worth writing down. Every base carrying one is already required to be in a loot table by
# check_m2_attach.gd's CONTENT lane -- by a *stricter* rule than this one, which also accepts a
# kit, somebody's empties or a job. Adding the key here would make two gates assert the same fact
# through two different predicates, which is the shape infection.gd's `_diagnosis_for_stage`
# comment names: two things that say the same thing independently drift the moment only one is
# updated. The armour parts this slice shipped -- plates, a lining, a visor -- are covered there.
# A pouch is covered *here*, because it declares a `container` and that is a different claim.
const READ_KEYS: Array[String] = ["equipSlot", "melee", "ranged", "armor", "container", "food", "drink", "fuel", "light", "modification", "ammo", "filter", "buildMaterial"]
# The bases a *job or verb* produces rather than a table rolls, each with the sim file that names
# it, so the allowance cannot outlive the code it describes: cooked food out of SimJobs' cook job,
# and well water out of SimNeeds.fill_bottle.
const PRODUCED: Array[Dictionary] = [
	{"id": "item.food.cooked", "in": "res://sim/modules/jobs.gd"},
	{"id": "item.water.bottle.untreated", "in": "res://sim/modules/needs.gd"},
]


func _kit_ids(w: Variant) -> Dictionary:
	var out: Dictionary = {}
	for file_v in (w.content as Dictionary).values():
		var entries: Array = []
		if file_v is Array:
			entries = file_v as Array
		elif file_v is Dictionary:
			entries = [file_v]
		for e_v in entries:
			if not (e_v is Dictionary):
				continue
			var e: Dictionary = e_v as Dictionary
			var kits: Array = []
			if e.get("kit") is Array:
				kits.append(e["kit"])
			if e.get("archetypes") is Array:
				for a in e["archetypes"] as Array:
					if a is Dictionary and (a as Dictionary).get("kit") is Array:
						kits.append((a as Dictionary)["kit"])
			for kit_v in kits:
				for k in kit_v as Array:
					if k is String:
						out[String(k)] = true
					elif k is Dictionary:
						out[String((k as Dictionary).get("item", ""))] = true
	return out


func _the_catalogue_is_findable_and_read() -> bool:
	var w: Variant = _world()
	var findable: Dictionary = {}
	for file_v in (w.content as Dictionary).values():
		if not (file_v is Array):
			continue
		for t_v in file_v as Array:
			if t_v is Dictionary and String((t_v as Dictionary).get("id", "")).begins_with("loot."):
				for row_v in (t_v as Dictionary).get("entries", []) as Array:
					findable[String((row_v as Dictionary).get("item", ""))] = true
	var kits: Dictionary = _kit_ids(w)
	var by_id: Dictionary = {}
	var empties: Dictionary = {}
	for entry_v in SimItems.content_entries(w, "item"):
		var e: Dictionary = entry_v as Dictionary
		by_id[String(e.get("id", ""))] = e
		if e.has("empties"):
			empties[String(e["empties"])] = String(e.get("id", ""))
	if findable.is_empty() or kits.is_empty():
		push_error("CATALOGUE: %d findable ids and %d kit ids -- the scans have nothing to judge" % [findable.size(), kits.size()])
		return false
	# The one base a *job* produces rather than a table rolls: cooked food, out of SimJobs' cook
	# job. Allowed by name, and the producer's source is read for the id so the allowance cannot
	# outlive the code it describes.
	var produced_ids: Dictionary = {}
	for row in PRODUCED:
		var pid: String = String(row["id"])
		var code: String = FileAccess.get_file_as_string(String(row["in"]))
		if not code.contains("\"%s\"" % pid):
			push_error("CATALOGUE: %s is allowed as produced but %s never names it" % [pid, row["in"]])
			return false
		produced_ids[pid] = true
	var judged: int = 0
	var unreachable: Array[String] = []
	for id in by_id.keys():
		var e: Dictionary = by_id[id] as Dictionary
		var read: bool = false
		for k in READ_KEYS:
			if e.has(k):
				read = true
		if not read:
			continue
		judged += 1
		if not (findable.has(String(id)) or kits.has(String(id)) or empties.has(String(id)) or produced_ids.has(String(id))):
			unreachable.append(String(id))
	if not unreachable.is_empty():
		push_error("CATALOGUE: %s do something and are in no loot table, no kit and nobody's empties -- complete, correct, and unreachable" % str(unreachable))
		return false
	# Every round names a real, reachable base; every empties resolves; every tool is read.
	for id in by_id.keys():
		var e: Dictionary = by_id[id] as Dictionary
		if e.get("ranged") is Dictionary:
			var ammo: String = String((e["ranged"] as Dictionary).get("ammo", ""))
			if not ammo.is_empty() and (not by_id.has(ammo) or not findable.has(ammo)):
				push_error("CATALOGUE: %s fires %s, which is not a base or is in no table" % [String(id), ammo])
				return false
		if e.has("empties") and not by_id.has(String(e["empties"])):
			push_error("CATALOGUE: %s leaves %s, which is not a base" % [String(id), String(e["empties"])])
			return false
		if String(e.get("class", "")) == "tool" and not (e.has("light") or e.has("modification")):
			push_error("CATALOGUE: %s is a tool with no light and no modification block -- a tool nothing reads" % String(id))
			return false
	# The true negatives: the scans do not see ids that are not there, and the two predicates
	# can say no to a fabricated armoured orphan and a fabricated mute tool.
	if findable.has("item.gate.orphan") or kits.has("item.gate.orphan") or empties.has("item.gate.orphan"):
		push_error("CATALOGUE: the scans found an id that does not exist")
		return false
	var orphan: Dictionary = {"id": "item.gate.orphan", "class": "armor", "armor": {"head": 0.1}}
	var orphan_read: bool = false
	for k in READ_KEYS:
		if orphan.has(k):
			orphan_read = true
	if not orphan_read:
		push_error("CATALOGUE: a fabricated armoured orphan would not have been judged at all")
		return false
	var mute_tool: Dictionary = {"id": "item.gate.mutetool", "class": "tool"}
	if mute_tool.has("light") or mute_tool.has("modification"):
		push_error("CATALOGUE: the tool predicate cannot say no")
		return false
	print("  CATALOGUE: %d bases that do something are each rolled by a table, carried in a kit or left as somebody's empties (%d table ids, %d kit ids, %d empties); every round is a findable base; every tool is a light or a bench consumable; an orphan and a mute tool are refused" % [judged, findable.size(), kits.size(), empties.size()])
	return true
