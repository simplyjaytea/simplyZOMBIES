class_name SimGunsmith
extends RefCounted

# The bench a weapon is taken apart on -- docs/11-crafting.md, and the owner's decision of
# 2026-09-09 that modification happens at one rather than in the field.
#
# The whole of this module is a *place*. `SimAttachments` already knew how to fit a part and
# `SimModification` already knew how to reroll an affix; what neither had was a reason to go home,
# and both were reachable only from a gate. A bench is that reason: it is built through the same
# E-key ladder that boards a window (`SimFortify`, which owns the channel, the noise, the stagger
# interrupt and the material), it sits in the colony, and the commands the screen pushes ask this
# module whether the survivor is standing at one.
#
# **Why the check lives on the command and not inside `SimAttachments.attach`.** `attach` is the
# mechanism -- it is what a save restores through, what `assemble` calls when a weapon spawns, and
# what a gate drives directly. Requiring a bench inside it would mean a weapon could not be built
# at spawn time without a workbench in the world, which is absurd. The requirement belongs to the
# *player's way in*, so it sits on `item.attach` / `item.detach` / `item.modify`, which is exactly
# where the fiction lives too: the operation is not harder in a field, it is that you have not got
# your tools.
#
# **What is field-swappable is content.** `attachment.fieldSwap` marks the parts a person can
# change with their hands -- a magazine, a sight -- and everything else wants the bench. A part
# that declares nothing needs the bench, which is the safe default: a new part is bench-only until
# somebody says otherwise.

const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimAttachments = preload("res://sim/modules/attachments.gd")
const SimBarrel = preload("res://sim/barrel.gd")

## How close you have to stand. The same figure SimFortify reaches a window at, deliberately: one
## number for "arm's length" across the whole game.
const REACH: float = 1.5

## What a gunsmithing bench costs to build, in scrap, and how long it takes. Four times a
## barricade's channel -- it is furniture, not a plank across a window -- and it is the same
## channel, so it makes the same noise and a stagger cancels it the same way.
const BENCH_SCRAP: int = 3
const BENCH_TICKS: int = 160
const KIND: String = "gunsmith"


static func make_bench(world: Variant, x: float, y: float) -> int:
	var ent: int = int(world.entities.spawn())
	world.components.set_component(ent, "position", {"x": x, "y": y})
	world.components.set_component(ent, "workbench", {"kind": KIND})
	world.events.publish({"type": "bench.built", "bench": ent, "x": x, "y": y})
	return ent


## The bench this actor is standing at, or -1. One function, so there is exactly one answer to
## "am I at a bench" for the commands, the verb list and the screen alike.
static func bench_in_reach(world: Variant, actor: int) -> int:
	var here: Variant = world.components.get_component(actor, "position")
	if not here is Dictionary:
		return -1
	var ax: float = float((here as Dictionary)["x"])
	var ay: float = float((here as Dictionary)["y"])
	var best: int = -1
	var best_sq: float = REACH * REACH
	for ent in world.components.query(["workbench", "position"]):
		var there: Variant = world.components.get_component(int(ent), "position")
		if not there is Dictionary:
			continue
		var dx: float = float((there as Dictionary)["x"]) - ax
		var dy: float = float((there as Dictionary)["y"]) - ay
		var d: float = dx * dx + dy * dy
		if d <= best_sq:
			best_sq = d
			best = int(ent)
	return best


## Whether this part can be changed without a bench. Content decides; absent means no, so a part
## nobody has thought about is bench-only rather than silently field-swappable.
static func is_field_swap(world: Variant, part: int) -> bool:
	var spec: Variant = SimAttachments.spec_of(world, part)
	return spec is Dictionary and bool((spec as Dictionary).get("fieldSwap", false))


## Whether this actor may work on this part right now: at a bench, or holding something simple
## enough to change with their hands. `part` may be -1 when the question is about the actor alone.
static func may_work(world: Variant, actor: int, part: int) -> bool:
	if part >= 0 and is_field_swap(world, part):
		return true
	return bench_in_reach(world, actor) >= 0


## The same rule for a part that does not exist yet -- an improvised recipe, asked by its content entry
## rather than by an item. A recipe is field work when its content says so, and bench work otherwise.
static func may_work_spec(world: Variant, actor: int, spec: Dictionary) -> bool:
	return bool(spec.get("fieldSwap", false)) or bench_in_reach(world, actor) >= 0


## Why not, as a reason id, or "" when they may. Kept beside `may_work` so the two cannot drift.
static func refusal(world: Variant, actor: int, part: int) -> String:
	return "" if may_work(world, actor, part) else "no-bench"


## Whether this survivor can work on this host where they stand, with their hands alone: it wears
## a part that can be changed by hand, or it carries one that fits a slot of the host and can be.
## A bench is not needed for either. Asked by the verb and by the open alike, so they cannot drift.
static func field_work(world: Variant, actor: int, host: int) -> bool:
	if host < 0 or SimAttachments.slots_of(world, host).is_empty():
		return false
	for part in SimAttachments.attached(world, host).values():
		if int(part) >= 0 and is_field_swap(world, int(part)):
			return true
	for item in SimInventory.carried_items(world, actor):
		var spare: int = int(item)
		if spare == host or world.components.has_component(spare, "attachedTo"):
			continue
		if not is_field_swap(world, spare):
			continue
		for slot in SimAttachments.slots_of(world, host):
			if SimAttachments.plausible(world, host, spare, String(slot)):
				return true
	return false


## Whether this survivor may open this item on the bench screen: standing at a bench, or with
## their hands alone when `field_work` says there is something to change. One predicate for the
## open command and for the verb `SimInventory.verbs_for` offers.
static func may_open(world: Variant, actor: int, item: int) -> bool:
	return bench_in_reach(world, actor) >= 0 or field_work(world, actor, item)

## The slot a part dropped on a host would go into, or "" for none: the first empty slot the part
## `fits`, for an actor who may work on that part here. The screen asks this and decides nothing.
## An occupied slot is never swapped by a drop -- the assembly screen does the swapping.
static func drop_slot(world: Variant, actor: int, part: int, host: int) -> String:
	if part < 0 or host < 0 or part == host or world.components.has_component(part, "attachedTo"):
		return ""
	if not may_work(world, actor, part):
		return ""
	var fitted: Dictionary = SimAttachments.attached(world, host)
	for slot_v in SimAttachments.slots_of(world, host):
		var slot: String = String(slot_v)
		if int(fitted.get(slot, -1)) >= 0:
			continue
		if SimAttachments.plausible(world, host, part, slot):
			return slot
	return ""


## The survivor whose hands this operation is in. The commands carry no actor -- nothing else in
## the inventory vocabulary does either -- so it is the one the player is driving, the same set
## SimFortify's ladder walks.
static func acting(world: Variant) -> int:
	for actor in world.components.query(["controlled", "position"]):
		return int(actor)
	return -1


# --- the screen's read model -------------------------------------------------------------------
#
# One dictionary, all words, and the panel prints it. The rule the whole HUD lives under applies
# here in its strictest form: there is no magnitude anywhere in this view, so "no digits" is
# structural rather than a discipline -- a delta the screen could print does not exist to be
# printed. Directions are the words "better", "worse" and "different"; the panel draws an arrow.
#
# Entity ids are the one exception and they are named: `bench`, `host`, `part` and `item` are
# handles the screen hands back on a command, never anything a player reads.

## Which entity the player has open on the bench, if any. A component on the actor rather than a
## flag on the panel, because the sim decides what E means and the screen draws what it is told.
static func focus_of(world: Variant, actor: int) -> int:
	var f: Variant = world.components.get_component(actor, "benchFocus")
	return int((f as Dictionary).get("item", -1)) if f is Dictionary else -1


static func open_bench(world: Variant, actor: int, item: int) -> bool:
	if not may_open(world, actor, item):
		return false
	if not SimAttachments.slots_of(world, item).is_empty():
		world.components.set_component(actor, "benchFocus", {"item": item})
		world.events.publish({"type": "bench.opened", "entity": actor, "item": item})
		return true
	return false


static func close_bench(world: Variant, actor: int) -> void:
	if world.components.has_component(actor, "benchFocus"):
		world.components.remove(actor, "benchFocus")


## The first thing worth putting on the bench: what is in your hands, then whatever in the pack
## comes apart. Used by the E rung, so standing at a bench with a rifle opens the rifle.
static func first_workpiece(world: Variant, actor: int) -> int:
	for item in SimInventory.equipped_items(world, actor):
		if not SimAttachments.slots_of(world, int(item)).is_empty():
			return int(item)
	for item in SimInventory.carried_items(world, actor):
		if not SimAttachments.slots_of(world, int(item)).is_empty():
			return int(item)
	return -1


## Everything the bench screen draws about one weapon. Empty when there is nothing to draw.
static func _barrel_words(world: Variant, part: int) -> String:
	var spec: Variant = SimAttachments.spec_of(world, part) if part >= 0 else null
	return SimBarrel.words_of(spec as Dictionary) if spec is Dictionary else ""


static func bench_view(world: Variant, actor: int, host: int) -> Dictionary:
	var base: Variant = SimItems.item_base_of(world, host)
	if not base is Dictionary:
		return {}
	var slots: Array = SimAttachments.slots_of(world, host)
	if slots.is_empty():
		return {}
	var required: Array = SimAttachments.required_slots_of(world, host)
	var fitted: Dictionary = SimAttachments.attached(world, host)
	var rows: Array = []
	for slot_v in slots:
		var slot: String = String(slot_v)
		var part: int = int(fitted.get(slot, -1))
		rows.append({
			"slot": slot,
			"noun": String(SimAttachments.SLOT_NOUN.get(slot, slot)),
			"part": part,
			"name": _name_of(world, part) if part >= 0 else "empty",
			"condition": _band_of(world, part) if part >= 0 else "",
			# A fitted barrel's words, "" for everything else (sim/barrel.gd `words_of`).
			"barrel": _barrel_words(world, part),
			"required": _has(required, slot),
			"structural": part >= 0 and _is_structural(world, part),
			"removable": part >= 0 and may_work(world, actor, part),
			"field": part >= 0 and is_field_swap(world, part),
		})
	var offers: Array = []
	for item in SimInventory.carried_items(world, actor):
		var part2: int = int(item)
		if part2 == host or world.components.has_component(part2, "attachedTo"):
			continue
		var spec: Variant = SimAttachments.spec_of(world, part2)
		if not spec is Dictionary:
			continue
		for slot_v2 in slots:
			var slot2: String = String(slot_v2)
			if not SimAttachments.plausible(world, host, part2, slot2):
				continue
			if not may_work(world, actor, part2):
				continue
			offers.append({
				"slot": slot2,
				"noun": String(SimAttachments.SLOT_NOUN.get(slot2, slot2)),
				"item": part2,
				"name": _name_of(world, part2),
				"condition": _band_of(world, part2),
				# The barrel's words the player compares before taking it, "" for a scope or a grip.
				"barrel": SimBarrel.words_of(spec as Dictionary),
				"changes": SimAttachments.compare_view(world, host, slot2, part2),
			})
	return {
		"bench": bench_in_reach(world, actor),
		"at_bench": bench_in_reach(world, actor) >= 0,
		"host": host,
		# The name the player gave it when there is one (docs/33 item 24); the base's plain noun
		# otherwise, as the bench has always said it.
		"name": SimItems.given_name(world, host) if not SimItems.given_name(world, host).is_empty() else String((base as Dictionary).get("name", "weapon")),
		"condition": SimItems.condition_band({"current": SimItems.assembly_condition(world, host)}),
		"refusal": SimAttachments.refusal_clause(world, actor),
		"slots": rows,
		"offers": offers,
		"recipes": _recipe_rows(world, actor, host, base as Dictionary, slots, fitted),
	}


## The parts the survivor could make for this weapon's empty slots (the owner's call of 2026-10-27: the
## bench lists what it cannot make yet, and says why). One row per recipe whose spec fits the slot
## and that this host takes -- `spec_fits` and `takes`, the pair `improvise` asks -- so a part the
## command would call implausible is never a row. A filled slot offers none: the bench makes into
## an empty slot and swaps only what you carry. Whether a row can be made now is
## `SimAttachments.improvise_refusal`, the command's own check, asked without spending.
##
## Each row: `recipe`, the base id that goes back out on `item.improvise` and is never drawn; the
## slot and its noun; the part's name; `spends`, the materials as words; `makeable`; and `needs`,
## the refusal in words, "" when it can be made. Makeable rows first, then by name.
static func _recipe_rows(world: Variant, actor: int, host: int, base: Dictionary, slots: Array, fitted: Dictionary) -> Array:
	var out: Array = []
	var recipes: Array = _recipes(world)
	for slot_v in slots:
		var slot: String = String(slot_v)
		if int(fitted.get(slot, -1)) >= 0:
			continue
		var rows: Array = []
		for entry_v in recipes:
			var entry: Dictionary = entry_v as Dictionary
			var spec: Dictionary = entry["attachment"] as Dictionary
			if not SimAttachments.spec_fits(spec, slot) or not SimAttachments.takes(base, spec):
				continue
			var id: String = String(entry.get("id", ""))
			var why: String = SimAttachments.improvise_refusal(world, actor, host, slot, id)
			if why == "not-plausible" or why == "no-recipe":
				continue
			rows.append({
				"slot": slot,
				"noun": String(SimAttachments.SLOT_NOUN.get(slot, slot)),
				"recipe": id,
				"name": String(entry.get("name", "part")),
				"spends": String(_fortify().call("material_words", SimAttachments.recipe_kinds(world, id))),
				"makeable": why == "",
				"needs": SimAttachments.improvise_needs(world, actor, id, why),
			})
		rows.sort_custom(func(a: Variant, b: Variant) -> bool:
			var am: bool = bool((a as Dictionary)["makeable"])
			var bm: bool = bool((b as Dictionary)["makeable"])
			if am != bm:
				return am
			return String((a as Dictionary)["name"]) < String((b as Dictionary)["name"])
		)
		out.append_array(rows)
	return out


## Every loaded item base that is made rather than found: an attachment carrying `recipe.kinds`.
static func _recipes(world: Variant) -> Array:
	var out: Array = []
	for entry_v in SimItems.content_entries(world, "item"):
		if not entry_v is Dictionary:
			continue
		var spec: Variant = (entry_v as Dictionary).get("attachment")
		if not spec is Dictionary:
			continue
		var recipe: Variant = (spec as Dictionary).get("recipe")
		if recipe is Dictionary and (recipe as Dictionary).get("kinds") is Array:
			out.append(entry_v)
	return out


# Loaded lazily, as attachments.gd does: fortify.gd loads this file to build a bench, and a preload
# cycle is a parse error.
static func _fortify() -> GDScript:
	return load("res://sim/modules/fortify.gd") as GDScript


static func _name_of(world: Variant, item: int) -> String:
	var base: Variant = SimItems.item_base_of(world, item)
	return String((base as Dictionary).get("name", "part")) if base is Dictionary else "part"


static func _band_of(world: Variant, item: int) -> String:
	var c: Variant = world.components.get_component(item, "condition")
	return SimItems.condition_band(c as Dictionary) if c is Dictionary else ""


static func _is_structural(world: Variant, part: int) -> bool:
	var spec: Variant = SimAttachments.spec_of(world, part)
	return spec is Dictionary and bool((spec as Dictionary).get("structural", false))


static func _has(list: Array, want: String) -> bool:
	for x in list:
		if String(x) == want:
			return true
	return false


static func register_module(world: Variant) -> void:
	world.systems.register("gunsmith.intake", "input", 9, func(w: Variant) -> void:
		for cmd in w.commands.current as Array:
			var c: Dictionary = cmd as Dictionary
			var kind: String = String(c.get("type", ""))
			if kind != "bench.open" and kind != "bench.close":
				continue
			var actor: int = acting(w)
			if actor < 0:
				continue
			if kind == "bench.close":
				close_bench(w, actor)
				continue
			var item: int = int(c.get("item", -1))
			if item < 0:
				item = first_workpiece(w, actor)
			if not open_bench(w, actor, item):
				w.events.publish({"type": "bench.refused", "entity": actor, "reason": refusal(w, actor, -1)})
	)
	# Walking away closes it, the way `SimContainers` closes a box that has gone out of reach:
	# a screen about a place you are no longer standing in is a screen showing a lie. The one
	# exception is a weapon you can still change with your hands, which stays open where you stand.
	world.systems.register("gunsmith.reach", "structures", 6, func(w: Variant) -> void:
		for actor in w.components.query(["benchFocus"]):
			var a: int = int(actor)
			if not may_open(w, a, focus_of(w, a)):
				close_bench(w, a)
	)
