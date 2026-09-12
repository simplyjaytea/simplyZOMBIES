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
# The NAMED lane's reach. Each of these is a system that *charges* one of the six drawbacks, and
# the lane measures the cost through it rather than reading the number back off the content that
# declared it: melee for the noise a swing makes, the emitter for what a body smells of, wounds
# for what a filthy weapon does to a cut, attachments for the slot a rifle does not have.
const SimMelee = preload("res://sim/modules/melee.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const SimAttachments = preload("res://sim/modules/attachments.gd")
const SimAttentionEmitter = preload("res://sim/modules/attention_emitter.gd")
const SimCombat = preload("res://sim/combat.gd")

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
	ok = _the_named_tier_is_authored_and_every_name_costs_something() and ok
	if ok:
		print("M2_GEAR_OK slots have items, items are findable, coverage moves and composes by max, a command undresses one person, every base in the catalogue is reachable and read by something, and the six named items are hand-authored, off both ladders, and each one charged for what it gives")
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
# gated by the worn look, and unreachable since it shipped; it is in the military cache now.
# Beside it, the class the request called "tools": a `tool` base with no
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
#
# `cooksInto`, `boilsInto` and `purifies` joined with the transform slice, and the first two
# widened the *reachability* half as well as the read half. They are the grammar of `empties` --
# a flat top-level string naming another base id -- so a meal named by an ingredient's `cooksInto`
# is reachable exactly the way an empty bottle named by a drink's `empties` is, and `TRANSFORMS`
# below is the one list of keys that count. That is also what let `item.food.cooked` come off
# PRODUCED: it is no longer a literal in jobs.gd to be found by name, it is what the shipped raw
# says it becomes, and `check_m2_transform.gd` is the gate that judges the pair.
# `comfort` joined with the comfort slice, and it widened the *tool* predicate below as well as
# this list. A deck of cards and a harmonica are tools in the class enum's sense and carry no
# light, no bench modification and no noise block, so the predicate that refuses "a tool nothing
# reads" had to learn the fourth thing a tool can be for -- otherwise the choice was a red gate or
# a harmonica filed as a building material.
# `teaches` joined with the books slice, and it is the key that makes the dead-socket rule
# automatic for a whole new category: a book is a `consumable` with no food, no drink and no
# medical grade, so without this key a field manual in no loot table would have been complete,
# gated, and unfindable -- the exact shape the demolition sledge was in when this lane first ran.
# `noise` joined this list with the noise-device slice. A placeable noise device declares no
# equipSlot, no melee and no ranged block -- it is a `tool` you stand on a tile -- so without this
# key a firecracker in no loot table would have been exactly the shape `item.floodlight.rigged` was
# before the light slice reached it: shipped, correct, and unreachable.
# The bases a *job or verb* produces rather than a table rolls, each with the sim file that names
# it, so the allowance cannot outlive the code it describes: cooked food out of SimJobs' cook job,
# and well water out of SimNeeds.fill_bottle.
const READ_KEYS: Array[String] = ["equipSlot", "melee", "ranged", "armor", "container", "food", "drink", "fuel", "light", "modification", "ammo", "filter", "buildMaterial", "warmth", "shedsRain", "lightFuel", "cooksInto", "boilsInto", "purifies", "noise", "comfort", "teaches"]
# The keys whose value is another base id this one turns into, and therefore a way of reaching that
# other base without a loot table. One list, walked twice below: once to collect what is reachable,
# and once to refuse a target that is not a base at all.
const TRANSFORMS: Array[String] = ["empties", "cooksInto", "boilsInto"]
# The bases a *job or verb* produces rather than a table rolls or another base turns into, each with
# the sim file that names it, so the allowance cannot outlive the code it describes: well water out
# of SimNeeds.fill_bottle, which is still a literal there because the well fills a bottle with a
# named thing rather than transforming one base into another.
const PRODUCED: Array[Dictionary] = [
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
		for tk in TRANSFORMS:
			if e.has(tk):
				empties[String(e[tk])] = String(e.get("id", ""))
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
		for tk in TRANSFORMS:
			if e.has(tk) and not by_id.has(String(e[tk])):
				push_error("CATALOGUE: %s's %s names %s, which is not a base" % [String(id), tk, String(e[tk])])
				return false
		if String(e.get("class", "")) == "tool" and not (e.has("light") or e.has("modification") or e.has("noise") or e.has("comfort")):
			push_error("CATALOGUE: %s is a tool with no light, no modification, no noise and no comfort block -- a tool nothing reads" % String(id))
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
	if mute_tool.has("light") or mute_tool.has("modification") or mute_tool.has("noise") or mute_tool.has("comfort"):
		push_error("CATALOGUE: the tool predicate cannot say no")
		return false
	print("  CATALOGUE: %d bases that do something are each rolled by a table, carried in a kit or left as somebody's empties (%d table ids, %d kit ids, %d empties); every round is a findable base; every tool is a light, a bench consumable, a noise device or a comfort; an orphan and a mute tool are refused" % [judged, findable.size(), kits.size(), empties.size()])
	return true


# --- NAMED ------------------------------------------------------------------------------------
#
# docs/10's fourth tier: "Hand-authored, fixed rolls, very rare ... a capability nobody else gets,
# and a cost you have to build around" -- and the clause this lane exists for, **always with a
# drawback**.
#
# The cheap version of this lane asserts that six named items spawn. That version passes on six
# strictly-better weapons, which is the one shape docs/10 says this tier must never take, so every
# item below is judged twice: once on the capability and once on the **cost**. And the cost is
# always measured through the system that charges it rather than read back off the content that
# declares it -- a number in a JSON file is not a drawback until something reads it. Three of the
# six ride readers this slice added (melee.gd's connect noise, attention_emitter.gd's worn scent,
# wounds.gd's filthy wound) and are driven end to end through a stepped world for exactly that
# reason; the other three ride readers that already shipped and are judged on the resolved profile,
# which is the dictionary those readers are handed.
#
# Each row names the ordinary base its named one is measured against, because "enormous noise" and
# "very low damage" are comparisons, not absolutes, and the thing compared against should be
# shipped content rather than a number written into a gate.
const NAMED_AGAINST: Dictionary = {
	"item.named.sirens_bell": "item.sledge.demolition",
	"item.named.long_argument": "item.spear.improvised",
	"item.named.deer_rifle": "item.rifle.hunting",
	"item.named.tetanus_special": "item.pipe.steel",
	"item.named.quietkeeper": "item.bow.hunting",
	"item.named.butchers_apron": "item.vest.riot",
}


func _the_named_tier_is_authored_and_every_name_costs_something() -> bool:
	if not _the_tier_is_in_code_and_on_neither_ladder():
		return false
	if not _every_named_base_carries_its_own_tier():
		return false
	if not _the_rolls_are_fixed_and_something_reads_them():
		return false
	if not _each_name_is_charged_for():
		return false
	print("  NAMED: the fourth tier is in code, weightless and off the upgrade ladder; %d named bases each carry their own tier whatever they are asked for, take no bench affixes, and roll the same on every seed; and each of the six pays for what it gives" % NAMED_AGAINST.size())
	return true


# The tier itself. Two separate claims, because `weight: 0` and `authored: true` do different jobs
# and losing either one is a different bug: the weight is why the world at large never hands a
# named item out, and the flag is why a Scrap Kit cannot manufacture one.
func _the_tier_is_in_code_and_on_neither_ladder() -> bool:
	var w: Variant = _world()
	var row: Variant = null
	for t in SimItems.TIERS:
		if String((t as Dictionary)["id"]) == SimItems.NAMED_TIER:
			row = t
	if not (row is Dictionary):
		push_error("NAMED: SimItems.TIERS has no \"%s\" row -- docs/10 names four tiers and code has three" % SimItems.NAMED_TIER)
		return false
	if int((row as Dictionary)["affixes"]) != 0:
		push_error("NAMED: the named tier permits %d rolled affixes; hand-authored means none are rolled at all" % int((row as Dictionary)["affixes"]))
		return false
	# Two locks, asserted separately because they fail separately. `rollable_tiers()` is the lock --
	# it is what roll_tier walks and what Salvage Rights climbs -- and the zero weight is the second
	# one, so a future refactor that drops the filter does not start handing named items out of
	# every table on the same day. A sabotage run put a weight of 5 on this row and nothing went
	# red, which is how this assertion came to exist: the behavioural test below cannot see the
	# weight through the filter, so the weight is checked here where it can actually fail.
	if int((row as Dictionary).get("weight", -1)) != 0:
		push_error("NAMED: the named tier carries a global roll weight of %d -- the second lock is off" % int((row as Dictionary).get("weight", -1)))
		return false
	for t in SimItems.rollable_tiers():
		if String((t as Dictionary)["id"]) == SimItems.NAMED_TIER:
			push_error("NAMED: the named tier is on the rollable ladder, so roll_tier can draw it and Salvage Rights can step a field-tested item into a named one with no author, no fixed roll and no drawback")
			return false
	if SimItems.rollable_tiers().size() != SimItems.TIERS.size() - 1:
		push_error("NAMED: %d of %d tiers are rollable -- exactly one, the authored one, should have been held back" % [SimItems.rollable_tiers().size(), SimItems.TIERS.size()])
		return false
	# The composite, measured on rolls: with both locks on, nothing anywhere in this chain hands a
	# named tier out. It takes *both* locks being off to turn this red -- sabotaging either alone
	# leaves it green, which the two assertions above are there to catch -- so it is deliberately a
	# backstop rather than the proof, and it is worth having because it is the only one of the three
	# that would notice a fourth way in nobody has thought of yet. The second half is the true
	# positive that keeps it honest: a sampler that returned "scavenged" every time would also never
	# produce a named item and would prove nothing at all, and a sabotage run confirmed it fires.
	var rng: Variant = w.rng.stream("loot")
	var seen: Dictionary = {}
	for _i in 4000:
		seen[SimItems.roll_tier(rng)] = true
	if seen.has(SimItems.NAMED_TIER):
		push_error("NAMED: 4000 global tier rolls turned up a named item -- roll_tier is not walking the rollable pool")
		return false
	if seen.size() < SimItems.rollable_tiers().size():
		push_error("NAMED: 4000 tier rolls produced only %s, so 'never named' is not evidence of anything" % str(seen.keys()))
		return false
	return true


# A named base is its own tier, whatever it was asked for. The loot roller picks an entry and rolls
# a tier independently, so without this a military cache rolling "modified" and then picking the
# Siren's Bell would hand out a Modified Siren's Bell -- a hand-authored item at a rolled tier,
# which is the tier's own definition contradicted.
func _every_named_base_carries_its_own_tier() -> bool:
	var w: Variant = _world()
	for id in NAMED_AGAINST.keys():
		var item: int = SimItems.spawn_item(w, String(id), {"tier": "scavenged"})
		if not SimItems.is_named(w, item):
			push_error("NAMED: %s does not read as a named item" % String(id))
			return false
		if SimItems.tier_of(w, item) != SimItems.NAMED_TIER:
			push_error("NAMED: %s was asked for scavenged and came out \"%s\" -- a named base must overrule the roll that found it" % [String(id), SimItems.tier_of(w, item)])
			return false
		# Capacity zero is what stops a bench adding to a hand-authored roll. check_mods.gd's KIT
		# lane already proves a Scrap Kit refuses an item with no free slot and keeps itself; this
		# is the other half of that -- that a named item is always such an item.
		if SimItems.affix_capacity(w, item) != 0:
			push_error("NAMED: %s has %d free affix slots, so a Scrap Kit could add to a hand-authored item" % [String(id), SimItems.affix_capacity(w, item)])
			return false
	# The true negatives: the predicate and the tier can both say no, and affix_capacity is capable
	# of returning something other than zero -- otherwise reading 0 off a named item says nothing.
	var plain: int = SimItems.spawn_item(w, "item.pipe.steel", {"tier": "scavenged"})
	if SimItems.is_named(w, plain):
		push_error("NAMED: an ordinary steel pipe reads as named -- the predicate cannot say no")
		return false
	if SimItems.tier_of(w, plain) != "scavenged":
		push_error("NAMED: an ordinary steel pipe asked for scavenged came out \"%s\"" % SimItems.tier_of(w, plain))
		return false
	var good: int = SimItems.spawn_item(w, "item.axe.fire", {"tier": "field_tested"})
	if SimItems.affix_capacity(w, good) <= 0:
		push_error("NAMED: a field-tested axe reports %d affix slots, so reading 0 off a named item proves nothing" % SimItems.affix_capacity(w, good))
		return false
	return true


# Fixed rolls, and rolls that reach something.
func _the_rolls_are_fixed_and_something_reads_them() -> bool:
	var a: Variant = _world()
	var b: Variant = _world_seeded(90210)
	var bell_a: String = str(_affixes_of(a, SimItems.spawn_item(a, "item.named.sirens_bell")))
	var bell_b: String = str(_affixes_of(b, SimItems.spawn_item(b, "item.named.sirens_bell")))
	if bell_a != bell_b:
		push_error("NAMED: two Siren's Bells on two seeds carry different affixes (%s vs %s) -- the roll is not fixed" % [bell_a, bell_b])
		return false
	if bell_a == str({"prefixes": [], "suffixes": []}):
		push_error("NAMED: the Siren's Bell carries no authored affixes at all, so 'the same on every seed' has nothing to judge")
		return false
	# The true positive the comparison needs: the same comparison, run on a *rolled* item, has to be
	# able to tell the two worlds apart. Five draws rather than one, because two field-tested axes
	# agreeing once is luck rather than a broken assertion.
	var rolled_a: Array[String] = []
	var rolled_b: Array[String] = []
	for _i in 5:
		rolled_a.append(str(_affixes_of(a, SimItems.spawn_item(a, "item.axe.fire", {"tier": "field_tested"}))))
		rolled_b.append(str(_affixes_of(b, SimItems.spawn_item(b, "item.axe.fire", {"tier": "field_tested"}))))
	if str(rolled_a) == str(rolled_b):
		push_error("NAMED: five field-tested axes rolled identically on two seeds, so this comparison cannot tell a fixed roll from a rolled one")
		return false
	# And the authored roll is not decoration: it reaches the modifier table and moves the profile
	# the melee module is handed. The Siren's Bell's authored prefix is a stagger affix, so its
	# resolved staggerTicks must stand above the number its own content declares.
	var bell: int = SimItems.spawn_item(a, "item.named.sirens_bell")
	var prof: Variant = SimItems.melee_profile_of(a, bell)
	if not (prof is Dictionary):
		push_error("NAMED: the Siren's Bell has no melee profile")
		return false
	var declared: int = int((_base(a, "item.named.sirens_bell")["melee"] as Dictionary)["staggerTicks"])
	if int((prof as Dictionary)["staggerTicks"]) <= declared:
		push_error("NAMED: the Siren's Bell staggers for %d against the %d its own content declares -- its fixed affix reaches nothing" % [int((prof as Dictionary)["staggerTicks"]), declared])
		return false
	return true


# --- the six costs ----------------------------------------------------------------------------

func _each_name_is_charged_for() -> bool:
	var ok: bool = _the_bell_is_heard()
	ok = _the_argument_barely_kills() and ok
	ok = _the_deer_rifle_takes_nothing_and_reloads_forever() and ok
	ok = _the_special_is_filthy() and ok
	ok = _the_quietkeeper_is_slow() and ok
	ok = _the_apron_stinks() and ok
	return ok


# Siren's Bell: "devastating damage and stagger" against "enormous noise on every connect --
# audible across the map". Driven through a real swing in a stepped world rather than read off the
# profile, because `connectNoise` is a reader this slice added to melee.gd and the whole question is
# whether that line runs. The ordinary sledge is the true negative: it must publish exactly the
# constant melee.gd used to publish for every weapon, or a gate that only ever saw one weapon could
# not tell a weapon-specific number from a louder global one.
func _the_bell_is_heard() -> bool:
	var bell: float = _swing_noise("item.named.sirens_bell")
	var sledge: float = _swing_noise(String(NAMED_AGAINST["item.named.sirens_bell"]))
	if bell < 0.0 or sledge < 0.0:
		push_error("NAMED/BELL: a swing did not connect (bell %.1f, sledge %.1f), so there is no noise to judge" % [bell, sledge])
		return false
	if absf(sledge - float(SimCombat.MELEE_CONNECT_NOISE)) > 0.001:
		push_error("NAMED/BELL: an ordinary sledge connected at %.1f, not the %d every weapon used to publish -- the default moved" % [sledge, SimCombat.MELEE_CONNECT_NOISE])
		return false
	if bell <= sledge * 4.0:
		push_error("NAMED/BELL: the Siren's Bell connected at %.1f against a sledge's %.1f -- 'audible across the map' is not a drawback at that margin" % [bell, sledge])
		return false
	# The capability, so the lane is not merely certifying a louder, worse sledge.
	var w: Variant = _world()
	var mine: Variant = SimItems.melee_profile_of(w, SimItems.spawn_item(w, "item.named.sirens_bell"))
	var theirs: Variant = SimItems.melee_profile_of(w, SimItems.spawn_item(w, String(NAMED_AGAINST["item.named.sirens_bell"])))
	if float((mine as Dictionary)["damage"]) <= float((theirs as Dictionary)["damage"]) or int((mine as Dictionary)["staggerTicks"]) <= int((theirs as Dictionary)["staggerTicks"]):
		push_error("NAMED/BELL: it is louder than a sledge without hitting harder than one")
		return false
	print("    NAMED/BELL: %.0f of noise on the connect against an ordinary sledge's %.0f, and it hits harder for it" % [bell, sledge])
	return true


# The Long Argument: "exceptional reach; near-zero bite risk" against "very low damage; kills take
# forever". Both halves are the resolved melee profile, which is the dictionary SimMelee is handed:
# `reachMetres` is what _resolve_strike measures its arc with and `damage` is what it publishes.
#
# The bite-risk half is deliberately **not** asserted here and is not faked: there is no bite-risk
# stat in this simulation. What docs/10 describes is emergent -- a survivor killing at four metres
# is not inside a shambler's grab -- and it is emergent out of the reach this lane does measure.
func _the_argument_barely_kills() -> bool:
	var w: Variant = _world()
	var mine: Variant = SimItems.melee_profile_of(w, SimItems.spawn_item(w, "item.named.long_argument"))
	var theirs: Variant = SimItems.melee_profile_of(w, SimItems.spawn_item(w, String(NAMED_AGAINST["item.named.long_argument"])))
	if not (mine is Dictionary) or not (theirs is Dictionary):
		push_error("NAMED/ARGUMENT: no melee profile to compare")
		return false
	var reach: float = float((mine as Dictionary)["reachMetres"])
	var their_reach: float = float((theirs as Dictionary)["reachMetres"])
	var dmg: float = float((mine as Dictionary)["damage"])
	var their_dmg: float = float((theirs as Dictionary)["damage"])
	if reach <= their_reach * 1.5:
		push_error("NAMED/ARGUMENT: %.2f m against an ordinary spear's %.2f m is not exceptional reach" % [reach, their_reach])
		return false
	if dmg >= their_dmg * 0.5:
		push_error("NAMED/ARGUMENT: %.1f damage against an ordinary spear's %.1f -- reach with no cost attached" % [dmg, their_dmg])
		return false
	print("    NAMED/ARGUMENT: %.2f m of reach against a spear's %.2f m, bought with %.1f damage against its %.1f" % [reach, their_reach, dmg, their_dmg])
	return true


# Grandfather's Deer Rifle: "superb accuracy and stopping power" against "single shot, agonizing
# reload, cannot take a suppressor". The first two are the resolved ranged profile; the third is a
# slot the base does not declare, driven through SimAttachments.attach because a refusal is only a
# drawback if the attach path actually refuses.
#
# The magazine slot is missing for the same reason the muzzle is, and it is the one that gives
# "single shot" its teeth: `magSize` is a scalable field, so a drum on a one-round rifle would have
# multiplied the drawback away. Both refusals are checked against the ordinary hunting rifle, which
# must accept both parts -- otherwise a broken suppressor would pass here as a missing slot.
func _the_deer_rifle_takes_nothing_and_reloads_forever() -> bool:
	var w: Variant = _world()
	var mine: Variant = SimItems.ranged_profile_of(w, SimItems.spawn_item(w, "item.named.deer_rifle"))
	var theirs: Variant = SimItems.ranged_profile_of(w, SimItems.spawn_item(w, String(NAMED_AGAINST["item.named.deer_rifle"])))
	if not (mine is Dictionary) or not (theirs is Dictionary):
		push_error("NAMED/RIFLE: no ranged profile to compare")
		return false
	if int((mine as Dictionary)["magSize"]) != 1:
		push_error("NAMED/RIFLE: it holds %d rounds, not one" % int((mine as Dictionary)["magSize"]))
		return false
	if int((mine as Dictionary)["reloadTicks"]) <= int((theirs as Dictionary)["reloadTicks"]) * 2:
		push_error("NAMED/RIFLE: %d ticks to reload against an ordinary rifle's %d is not agonizing" % [int((mine as Dictionary)["reloadTicks"]), int((theirs as Dictionary)["reloadTicks"])])
		return false
	if float((mine as Dictionary)["cone"]) >= float((theirs as Dictionary)["cone"]) or float((mine as Dictionary)["damage"]) <= float((theirs as Dictionary)["damage"]):
		push_error("NAMED/RIFLE: it pays for accuracy and stopping power it does not have (cone %.2f vs %.2f, damage %.1f vs %.1f)" % [float((mine as Dictionary)["cone"]), float((theirs as Dictionary)["cone"]), float((mine as Dictionary)["damage"]), float((theirs as Dictionary)["damage"])])
		return false
	# Both hosts are spawned bare -- `assemble: false` -- so the comparison is about which slots the
	# two bases *declare* and nothing else. An assembled hunting rifle comes out of spawn with its
	# default magazine already in the magazine slot, and `attach` refuses a full slot for reasons
	# that have nothing to do with the deer rifle; the first run of this lane hit exactly that and
	# reported it as "a drum will not fit an ordinary rifle either", which is the true negative
	# doing its job.
	for pair in [["item.attach.suppressor", "muzzle"], ["item.attach.magazine.drum", "magazine"]]:
		var part_id: String = String((pair as Array)[0])
		var slot: String = String((pair as Array)[1])
		var deer: int = SimItems.spawn_item(w, "item.named.deer_rifle", {"assemble": false})
		var hunting: int = SimItems.spawn_item(w, String(NAMED_AGAINST["item.named.deer_rifle"]), {"assemble": false})
		if SimAttachments.attach(w, deer, SimItems.spawn_item(w, part_id), slot):
			push_error("NAMED/RIFLE: a %s went onto the deer rifle's %s slot, which it does not have" % [part_id, slot])
			return false
		if not SimAttachments.attach(w, hunting, SimItems.spawn_item(w, part_id), slot):
			push_error("NAMED/RIFLE: a %s will not fit an ordinary rifle's %s either, so refusing the deer rifle proves nothing about the deer rifle" % [part_id, slot])
			return false
	print("    NAMED/RIFLE: one round, %d ticks to feed it against an ordinary rifle's %d, a tighter cone and more of a hit; neither a can nor a drum will go on it" % [int((mine as Dictionary)["reloadTicks"]), int((theirs as Dictionary)["reloadTicks"])])
	return true


# The Tetanus Special: "heavy bleed; free to repair from scrap" against "any damage you take while
# holding it risks a serious infection". The drawback is the half this lane can measure: a wound
# taken while it is equipped is flagged when it is made, and sepsis_chance prices the flag.
#
# The ordinary steel pipe is the true negative and it matters more than usual here, because the same
# line writes the flag for both weapons -- if the predicate could not say no, every wound in the
# game would be a filthy one and the multiplier would be a global difficulty change wearing a named
# item's clothes.
func _the_special_is_filthy() -> bool:
	var dirty: Dictionary = _wound_while_holding("item.named.tetanus_special")
	var clean: Dictionary = _wound_while_holding(String(NAMED_AGAINST["item.named.tetanus_special"]))
	if dirty.is_empty() or clean.is_empty():
		push_error("NAMED/SPECIAL: could not equip a weapon and take a wound, so there is nothing to judge")
		return false
	if not bool(dirty["filthy"]):
		push_error("NAMED/SPECIAL: a wound taken holding it is not flagged filthy")
		return false
	if bool(clean["filthy"]):
		push_error("NAMED/SPECIAL: a wound taken holding an ordinary steel pipe is flagged filthy too -- the predicate cannot say no")
		return false
	if float(dirty["chance"]) <= float(clean["chance"]):
		push_error("NAMED/SPECIAL: the filthy wound goes septic at %.4f against a clean one's %.4f -- the flag is priced at nothing" % [float(dirty["chance"]), float(clean["chance"])])
		return false
	# A cost you can work against rather than a sentence: the same filthy wound, cleaned and
	# dressed, has to come down. If it did not, the multiplier would be sitting outside the
	# expression the other five sepsis factors share and no medic could touch it.
	if float(dirty["treated"]) >= float(dirty["chance"]):
		push_error("NAMED/SPECIAL: cleaning and dressing the filthy wound left it at %.4f of %.4f -- the drawback is untreatable" % [float(dirty["treated"]), float(dirty["chance"])])
		return false
	# The capability half, such as this simulation can carry it: it hits harder than the pipe it is
	# made of, which is the chain docs/10's "heavy bleed" actually runs down -- more damage is a
	# worse severity is a faster bleed.
	var w: Variant = _world()
	var mine: Variant = SimItems.melee_profile_of(w, SimItems.spawn_item(w, "item.named.tetanus_special"))
	var theirs: Variant = SimItems.melee_profile_of(w, SimItems.spawn_item(w, String(NAMED_AGAINST["item.named.tetanus_special"])))
	if float((mine as Dictionary)["damage"]) <= float((theirs as Dictionary)["damage"]):
		push_error("NAMED/SPECIAL: it is filthier than a steel pipe without opening anything wider than one")
		return false
	print("    NAMED/SPECIAL: a wound taken holding it goes septic at %.3f against an ordinary pipe's %.3f, and down to %.3f once cleaned and dressed" % [float(dirty["chance"]), float(clean["chance"]), float(dirty["treated"])])
	return true


# Quietkeeper: "silent, arrows never break" against "very slow; useless against armored types".
# The slow half is the resolved ranged profile -- `reloadTicks` is the draw, and `handling` is what
# sim/combat.gd's raise / steady / recover rungs are scaled by.
#
# The armoured half is **not** asserted and is not faked: no zombie in this content tree declares
# armour of any kind, so there is nothing for "useless against" to be measured against. It is named
# here so the omission is on the record rather than quietly absent.
func _the_quietkeeper_is_slow() -> bool:
	var w: Variant = _world()
	var mine: Variant = SimItems.ranged_profile_of(w, SimItems.spawn_item(w, "item.named.quietkeeper"))
	var theirs: Variant = SimItems.ranged_profile_of(w, SimItems.spawn_item(w, String(NAMED_AGAINST["item.named.quietkeeper"])))
	if not (mine is Dictionary) or not (theirs is Dictionary):
		push_error("NAMED/QUIETKEEPER: no ranged profile to compare")
		return false
	if int((mine as Dictionary)["reloadTicks"]) <= int((theirs as Dictionary)["reloadTicks"]) * 3:
		push_error("NAMED/QUIETKEEPER: %d ticks to draw against an ordinary bow's %d is not very slow" % [int((mine as Dictionary)["reloadTicks"]), int((theirs as Dictionary)["reloadTicks"])])
		return false
	var handling: float = float((mine as Dictionary)["handling"])
	if handling >= float((theirs as Dictionary)["handling"]):
		push_error("NAMED/QUIETKEEPER: it handles at %.2f against an ordinary bow's %.2f -- its content-declared handling never reached the profile" % [handling, float((theirs as Dictionary)["handling"])])
		return false
	# Isolated on handling and nothing else: the same weapon at its own weight, once with the
	# handling it declares and once neutral. The first version of this compared the Quietkeeper's
	# raise against the hunting bow's, and a sabotage run proved that assertion could not fail --
	# the Quietkeeper is the heavier bow, so it came up slower on weight alone and the comparison
	# passed with `handling` hardcoded back to 1.0. It was measuring heft and reporting handling.
	var raise_mine: int = SimCombat.raise_ticks(float((mine as Dictionary)["weight"]), handling)
	var raise_neutral: int = SimCombat.raise_ticks(float((mine as Dictionary)["weight"]), 1.0)
	var raise_theirs: int = SimCombat.raise_ticks(float((theirs as Dictionary)["weight"]), float((theirs as Dictionary)["handling"]))
	if raise_mine <= raise_neutral:
		push_error("NAMED/QUIETKEEPER: it comes up in %d ticks where the same weapon at a neutral handling takes %d -- its handling costs nothing" % [raise_mine, raise_neutral])
		return false
	if float((mine as Dictionary)["noise"]) != 0.0:
		push_error("NAMED/QUIETKEEPER: it makes %.1f of noise, so it is not silent" % float((mine as Dictionary)["noise"]))
		return false
	if float((theirs as Dictionary)["noise"]) <= 0.0:
		push_error("NAMED/QUIETKEEPER: an ordinary bow is silent too, so silence is not this weapon's capability")
		return false
	if float((mine as Dictionary)["recoverable"]) < 1.0 or float((theirs as Dictionary)["recoverable"]) >= 1.0:
		push_error("NAMED/QUIETKEEPER: arrows recover at %.2f against an ordinary bow's %.2f -- 'never break' is not what shipped" % [float((mine as Dictionary)["recoverable"]), float((theirs as Dictionary)["recoverable"])])
		return false
	print("    NAMED/QUIETKEEPER: silent and every arrow back, bought with %d ticks a draw against a bow's %d and %d ticks to the shoulder against its %d" % [int((mine as Dictionary)["reloadTicks"]), int((theirs as Dictionary)["reloadTicks"]), raise_mine, raise_theirs])
	return true


# Butcher's Apron: "excellent torso coverage" against "permanent, powerful scent emission". Driven
# through a stepped world and counted off the `scent.accumulated` channel the dead actually follow,
# rather than read off SimItems.worn_scent_of, because the helper returning the right number is not
# the claim -- the claim is that attention_emitter.gd adds it to what a body gives off.
func _the_apron_stinks() -> bool:
	var worn: float = _scent_over(40, true)
	var bare: float = _scent_over(40, false)
	if worn < 0.0:
		push_error("NAMED/APRON: the apron would not go on")
		return false
	if bare <= 0.0:
		push_error("NAMED/APRON: a survivor wearing nothing emitted %.2f of scent, so there is no baseline to judge against" % bare)
		return false
	if worn <= bare * 3.0:
		push_error("NAMED/APRON: wearing it emits %.2f against a bare survivor's %.2f -- 'powerful' is not what reaches the spine" % [worn, bare])
		return false
	# Coverage is the capability, and it has to beat the best ordinary torso armour shipped, or the
	# smell is being charged for nothing.
	var w: Variant = _world()
	SimInventory.equip(w, w.player, SimItems.spawn_item(w, "item.named.butchers_apron"))
	var cov: float = SimInfection.armor_coverage_of(w, w.player, "torso")
	var w2: Variant = _world()
	SimInventory.equip(w2, w2.player, SimItems.spawn_item(w2, String(NAMED_AGAINST["item.named.butchers_apron"])))
	var their_cov: float = SimInfection.armor_coverage_of(w2, w2.player, "torso")
	if cov < their_cov or cov <= 0.0:
		push_error("NAMED/APRON: it covers the torso at %.2f against a riot vest's %.2f" % [cov, their_cov])
		return false
	print("    NAMED/APRON: %.2f of torso coverage, paid for with %.1f of scent onto the spine against a bare survivor's %.1f" % [cov, worn, bare])
	return true


# --- the drivers ------------------------------------------------------------------------------

# One survivor, one weapon, one body half a metre in front of them, swung for real. Returns the
# loudest noise the world published while the swing resolved, or -1.0 if it never connected.
func _swing_noise(base_id: String) -> float:
	var w: Variant = _world()
	SimMelee.register_module(w)
	var prof: Variant = SimItems.melee_profile_of(w, SimItems.spawn_item(w, base_id))
	if not (prof is Dictionary):
		return -1.0
	SimMelee.make_melee_armed(w, w.player, prof as Dictionary)
	var mark: int = int(w.entities.spawn())
	SimHealth.make_survivor_body(w, mark)
	var me: Dictionary = w.components.get_component(w.player, "position") as Dictionary
	# Facing is 0 radians, so straight along +x, and well inside every reach compared here.
	w.components.set_component(mark, "position", {"x": float(me["x"]) + 0.5, "y": float(me["y"])})
	# An Array, not a float: a lambda assigning to a captured primitive mutates its own copy
	# (CLAUDE.md's lambda-capture trap), and this one would read back 0.0 for every weapon.
	var loudest: Array = [0.0]
	w.events.subscribe({"id": "gate.named.noise", "type": "noise.emitted", "handler": func(ev: Dictionary) -> void:
		loudest[0] = maxf(float(loudest[0]), float(ev.get("magnitude", 0.0)))
	})
	if not SimMelee.try_begin_swing(w, w.player):
		return -1.0
	for _i in 400:
		w.step()
		if float(loudest[0]) > 0.0:
			break
	return float(loudest[0]) if float(loudest[0]) > 0.0 else -1.0


# The same survivor takes the same laceration in the same place, once holding each weapon. The
# severity is pinned rather than rolled off the damage, because otherwise the two wounds would
# differ by what the weapon hits like and the comparison would be measuring the wrong thing.
func _wound_while_holding(base_id: String) -> Dictionary:
	var w: Variant = _world()
	if not SimInventory.equip(w, w.player, SimItems.spawn_item(w, base_id)):
		return {}
	var wound: Dictionary = SimWounds.append_wound(w, w.player, "cut", "arm_left", -1, 9.0, "", SimWounds.Severity.Laceration)
	var raw: float = SimWounds.sepsis_chance(wound, 1.0, 0)
	# The same wound after the care docs/05 prices: cleaned with antiseptic, dressed sterile, by
	# somebody who knows how.
	var cared: Dictionary = wound.duplicate(true)
	cared["cleaned"] = true
	cared["cleanTier"] = "antiseptic"
	cared["bandage"] = "sterile"
	return {
		"filthy": bool(wound.get("filthy", false)),
		"chance": raw,
		"treated": SimWounds.sepsis_chance(cared, 1.0, 4),
	}


# What one survivor puts onto the scent channel over `ticks`, with the apron on or off.
func _scent_over(ticks: int, wear_it: bool) -> float:
	var w: Variant = _world()
	SimAttentionEmitter.register_module(w, SimTileMap.blank_map(24, 24))
	SimAttentionEmitter.make_emitter(w, w.player)
	if wear_it:
		if not SimInventory.equip(w, w.player, SimItems.spawn_item(w, "item.named.butchers_apron")):
			return -1.0
	var total: Array = [0.0]
	w.events.subscribe({"id": "gate.named.scent", "type": "scent.accumulated", "handler": func(ev: Dictionary) -> void:
		total[0] = float(total[0]) + float(ev.get("magnitude", 0.0))
	})
	for _i in ticks:
		w.step()
	return float(total[0])


func _world_seeded(seed_value: int) -> Variant:
	var f: Dictionary = {"seed": seed_value, "tick_hz": 20, "map": {"width": 24, "height": 24, "walls": []}, "player": {"id": 0, "x": 8.5, "y": 12.5, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
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


func _affixes_of(w: Variant, item: int) -> Dictionary:
	var aff: Variant = w.components.get_component(item, "affixes")
	return (aff as Dictionary) if aff is Dictionary else {}


func _base(w: Variant, id: String) -> Dictionary:
	for entry_v in SimItems.content_entries(w, "item"):
		if String((entry_v as Dictionary).get("id", "")) == id:
			return entry_v as Dictionary
	return {}
