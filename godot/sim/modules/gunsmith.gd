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


## Why not, as a reason id, or "" when they may. Kept beside `may_work` so the two cannot drift.
static func refusal(world: Variant, actor: int, part: int) -> String:
	return "" if may_work(world, actor, part) else "no-bench"


## The survivor whose hands this operation is in. The commands carry no actor -- nothing else in
## the inventory vocabulary does either -- so it is the one the player is driving, the same set
## SimFortify's ladder walks.
static func acting(world: Variant) -> int:
	for actor in world.components.query(["controlled", "position"]):
		return int(actor)
	return -1
