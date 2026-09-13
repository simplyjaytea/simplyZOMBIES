class_name SimNoiseDevice
extends RefCounted

## Noise that is an item -- docs/03-attention.md#playing-the-field, and the owner's decision of
## 2026-09-12.
##
## The defect this closes. The attention field has been finished and gated since Milestone 1, and
## **the only thing in the game that spent an item to make a noise was firing a gun**
## (`ranged.noise`). Every other publisher of `noise.emitted` is a system rather than a thing you
## carry: melee on a connect, fortify on a construct and on its alarm, the screamer, footsteps,
## infection, the weather, the jobs, the cars, and world.gd's shout. Meanwhile docs/03 has promised
## "a wind-up noisemaker, a lit lamp on a timer, a hung carcass" under **Bait** since the field was
## specified, and the two distraction devices that existed -- fortify's alarm line and its
## noisemaker -- are world-entity singletons built out of nothing at all.
##
## Those two stay exactly as they are, by the owner's decision. The build-materials slice
## deliberately left five verbs free and `check_m2_materials.gd`'s PINNED lane asserts by name that
## none of them has since acquired a price; making the shipped bait cost something would be a
## rebalance wearing a retrofit's hat. What this module adds is a **second kind of bait that is an
## item**: bases that declare a `noise` block, are found in loot rather than conjured, are stood on
## a tile with a verb, wind up, go off, run down -- and, by the owner's decision, are **picked back
## up and placed again**.
##
## The contrast with the light slice is deliberate and worth stating where somebody will read it:
## `item.floodlight.rigged` is planted **one-way** -- it becomes furniture, there is no verb to take
## it down, and it matches `_place_bench`. A noise device is the opposite. Bait is a thing you move;
## a floodlight is a thing you site. Whether the two placement mechanisms should eventually converge
## is a real question and it is deliberately not answered here.

const SimInventoryRes = preload("res://sim/modules/inventory.gd")
const SimItemsRes = preload("res://sim/modules/items.gd")
const SimAttentionRes = preload("res://sim/modules/attention_emitter.gd")

## How near you must be to take a placed device back off its tile. The same reach fortify uses for
## everything else done with the hands; a literal rather than a reach into fortify because this file
## is loaded by fortify and a constant read across that edge is a cycle nobody needs.
const LIFT_REACH: float = 1.5

## What a placed device says on the player's context line, in words. There is no number here and
## nowhere to derive one from: docs/01 clause 4, and the rule the lamp's `fuel_clause` follows.
## `SimFortify.look_at` is the one reader and `main.gd` puts it on the HUD.
const WOUND_WORD: String = "wound tight"
const SOUNDING_WORD: String = "sounding"
const SPENT_WORD: String = "gone quiet"


# Placing is fortify's job and the channel is fortify's `construct`, exactly as it is for the
# floodlight. Loaded rather than preloaded in both directions, because fortify reaches back here to
# finish the job and a preload either way would be a cycle at parse time.
static func _Fortify() -> GDScript:
	return load("res://sim/modules/fortify.gd") as GDScript


# --- content ------------------------------------------------------------------------------------

## The base id behind an entity, whether it is still an item in a pocket or standing on a tile.
## `placedNoise` carries it for the same reason `placedLight` does: a thing that is furniture has no
## `itemBase` while it is furniture, and the block has to stay readable from where the thing is.
static func base_id_of(world: Variant, entity: int) -> String:
	var item_comp: Variant = world.components.get_component(entity, "itemBase")
	if item_comp is Dictionary:
		return String((item_comp as Dictionary).get("baseId", ""))
	var placed: Variant = world.components.get_component(entity, "placedNoise")
	if placed is Dictionary:
		return String((placed as Dictionary).get("baseId", ""))
	return ""


## The `noise` block of whatever this entity is, or null.
static func noise_block_of(world: Variant, entity: int) -> Variant:
	var base_id: String = base_id_of(world, entity)
	if base_id.is_empty():
		return null
	var base: Variant = SimItemsRes.content_entry(world, "item", base_id)
	if not (base is Dictionary):
		return null
	var block: Variant = (base as Dictionary).get("noise")
	return block if block is Dictionary else null


## What this thing is worth on the noise channel, in docs/03's metres, or 0.0 for anything that is
## not a noise device. The one place the content number becomes a magnitude, so the device that is
## sounding and the gate that asks what it is worth cannot disagree.
static func magnitude_of(world: Variant, entity: int) -> float:
	var block: Variant = noise_block_of(world, entity)
	if block == null:
		return 0.0
	var mag: Variant = (block as Dictionary).get("magnitude")
	if not (mag is float or mag is int):
		return 0.0
	return maxf(0.0, float(mag))


## How long it sounds once it starts, in ticks, or 0 for anything that is not a noise device.
static func duration_of(world: Variant, entity: int) -> int:
	var block: Variant = noise_block_of(world, entity)
	if block == null:
		return 0
	var ticks: Variant = (block as Dictionary).get("durationTicks")
	if not (ticks is float or ticks is int):
		return 0
	return maxi(0, int(ticks))


## How long after being placed before it starts, in ticks. Absent is zero, which is what an air horn
## says: you blow it where you stand.
static func delay_of(world: Variant, entity: int) -> int:
	var block: Variant = noise_block_of(world, entity)
	if block == null:
		return 0
	var ticks: Variant = (block as Dictionary).get("delayTicks")
	if not (ticks is float or ticks is int):
		return 0
	return maxi(0, int(ticks))


## Whether this item is something you stand on a tile rather than something you hold. The predicate
## is "declares a noise block and cannot be worn", not a list of ids, so a ninth device costs a
## content edit -- the rule `SimLightModule.is_plantable` set for the floodlight.
static func is_placeable(world: Variant, item: int) -> bool:
	if noise_block_of(world, item) == null:
		return false
	if world.components.has_component(item, "placedNoise"):
		return false
	var base_id: String = base_id_of(world, item)
	var base: Variant = SimItemsRes.content_entry(world, "item", base_id)
	if not (base is Dictionary):
		return false
	return String((base as Dictionary).get("equipSlot", "")).is_empty()


## The first placeable noise device this body is carrying, or -1.
static func carried_placeable(world: Variant, actor: int) -> int:
	for item_v in SimInventoryRes.carried_items(world, actor):
		if is_placeable(world, int(item_v)):
			return int(item_v)
	return -1


## The nearest placed device within arm's reach of this body, or -1. The nearest rather than the
## first, because two of them standing side by side is a thing the player can do and "whichever the
## component store happened to list first" is not an answer anybody could predict.
static func placed_in_reach(world: Variant, actor: int) -> int:
	var here: Variant = world.components.get_component(actor, "position")
	if not (here is Dictionary):
		return -1
	var best: int = -1
	var best_d: float = LIFT_REACH * LIFT_REACH
	for entity in world.components.query(["placedNoise", "position"]):
		var pos: Variant = world.components.get_component(int(entity), "position")
		if not (pos is Dictionary):
			continue
		var dx: float = float((pos as Dictionary)["x"]) - float((here as Dictionary)["x"])
		var dy: float = float((pos as Dictionary)["y"]) - float((here as Dictionary)["y"])
		var d: float = dx * dx + dy * dy
		if d > best_d:
			continue
		# A tie goes to the lower entity id rather than to the query order, so two devices on the
		# same tile resolve the same way on every machine and after every save.
		if d == best_d and best >= 0 and int(entity) >= best:
			continue
		best = int(entity)
		best_d = d
	return best


# --- placing, arming, and taking back up ------------------------------------------------------

## Stand the device on a tile and start its clock. Called by fortify when the channel completes, and
## re-derived here rather than trusted from the start -- `_place_bench`'s rule, because a channel
## that began with a firecracker in the pack and ended without one must leave nothing behind.
##
## The item *becomes* the placed thing rather than being destroyed and replaced, exactly as the
## floodlight does: one entity, so a device you take back up is the same object with the same id and
## a save does not have to explain where the second one came from.
##
## Placing is arming. `startsAtTick` is now plus the base's delay and `endsAtTick` is that plus its
## duration; the emitter goes down **silent** and the clock below turns it on. A device that went
## down loud would make the delay decorative, and the delay is the only reason a wind-up clock is a
## different item from an air horn.
static func plant(world: Variant, actor: int, tx: int, ty: int) -> int:
	var item: int = carried_placeable(world, actor)
	if item < 0:
		return -1
	var base_id: String = base_id_of(world, item)
	var starts: int = int(world.tick) + delay_of(world, item)
	var ends: int = starts + duration_of(world, item)
	SimInventoryRes.remove_from_container(world, item)
	SimInventoryRes.unequip_item(world, item)
	world.components.set_component(item, "position", {"x": float(tx) + 0.5, "y": float(ty) + 0.5})
	# `velocity` and not a bare position: `attention.emit-movement` is the one system that turns an
	# `ambient` into a `noise.emitted`, and it queries ["position", "velocity", "attention_emitter"]
	# -- a device with no velocity is a device the field never hears. `dx`/`dy` and never `x`/`y`,
	# per the trap the shambler pin was written around.
	world.components.set_component(item, "velocity", {"dx": 0.0, "dy": 0.0})
	world.components.set_component(item, "placedNoise", {
		"baseId": base_id, "tx": tx, "ty": ty, "startsAtTick": starts, "endsAtTick": ends,
	})
	# It stops being loot the moment it is standing somewhere, the same way a planted floodlight
	# does: `SimInventory.ground_items` is "has a position and is not stored", so without this the
	# armed firecracker would be the thing E picks up instead of the tin of beans beside it. Stored
	# in itself, and `take_up` is the one thing that undoes it.
	world.components.set_component(item, "stored", {"container": item, "x": 0, "y": 0, "rotated": false})
	var emitter: Dictionary = SimAttentionRes.PERSON_EMITTER.duplicate(true)
	emitter["ambient"] = 0.0
	emitter["walking"] = 0.0
	emitter["sprinting"] = 0.0
	emitter["scent"] = 0.0
	SimAttentionRes.make_emitter(world, item, emitter)
	world.events.publish({"type": "noise.device.placed", "entity": item, "actor": actor, "tx": tx, "ty": ty, "startsAtTick": starts, "endsAtTick": ends})
	return item


## Take a placed device back off its tile and into a pocket. The owner's decision of 2026-09-12:
## these are multi-use, which is the opposite of what the light slice chose for the floodlight, and
## the difference is that bait is a thing you move.
##
## The pack is asked **first**. A device lifted into a pack with no room for it would be an entity
## with no position, no container and no owner -- gone, silently, which is the worst shape a refusal
## can take. So the self-store is cleared, the stow is attempted, and a failure puts the self-store
## straight back: the device stands where it stood and nothing else has changed.
static func take_up(world: Variant, actor: int) -> bool:
	var device: int = placed_in_reach(world, actor)
	if device < 0:
		return false
	SimInventoryRes.remove_from_container(world, device)
	if not SimInventoryRes.stow(world, actor, device):
		world.components.set_component(device, "stored", {"container": device, "x": 0, "y": 0, "rotated": false})
		return false
	world.components.remove(device, "placedNoise")
	world.components.remove(device, "attention_emitter")
	world.components.remove(device, "velocity")
	world.components.remove(device, "position")
	world.events.publish({"type": "noise.device.lifted", "entity": device, "actor": actor})
	return true


# --- the clock ----------------------------------------------------------------------------------

## Which of the three things a placed device is doing, as a word. "" for anything that is not one.
## The screen's half, and the only thing the HUD is ever handed about a device: docs/01 clause 4,
## and `check_hud.gd` refuses a digit on the player's line regardless.
static func state_of(world: Variant, device: int) -> String:
	var placed: Variant = world.components.get_component(device, "placedNoise")
	if not (placed is Dictionary):
		return ""
	var p: Dictionary = placed as Dictionary
	var t: int = int(world.tick)
	if t < int(p.get("startsAtTick", 0)):
		return WOUND_WORD
	if t < int(p.get("endsAtTick", 0)):
		return SOUNDING_WORD
	return SPENT_WORD


## What the context line says about the device you are standing at, or "". `SimFortify.look_at`'s
## reader, and the reason `state_of` is not a socket nothing reaches.
static func hud_clause(world: Variant, actor: int) -> String:
	var device: int = placed_in_reach(world, actor)
	if device < 0:
		return ""
	return state_of(world, device)


## One tick of every placed device's clock: silent, then sounding at its own magnitude, then silent
## again for good. The emitter's `ambient` is the only thing written -- the field is reached through
## `attention.emit-movement`, which is what already turns a standing noisemaker into a
## `noise.emitted`, rather than through a second publisher that would one day disagree with it.
##
## Two events, and they fire on the transitions rather than every tick: a handler counting
## `noise.device.triggered` is counting devices going off, not ticks spent sounding.
static func _tick_devices(world: Variant) -> void:
	var t: int = int(world.tick)
	for entity in world.components.query(["placedNoise", "attention_emitter"]):
		var placed: Variant = world.components.get_component(int(entity), "placedNoise")
		var em: Variant = world.components.get_component(int(entity), "attention_emitter")
		if not (placed is Dictionary) or not (em is Dictionary):
			continue
		var p: Dictionary = placed as Dictionary
		var e: Dictionary = em as Dictionary
		var sounding: bool = t >= int(p.get("startsAtTick", 0)) and t < int(p.get("endsAtTick", 0))
		var want: float = magnitude_of(world, int(entity)) if sounding else 0.0
		if absf(want - float(e.get("ambient", 0.0))) <= 0.0:
			continue
		e["ambient"] = want
		if want > 0.0:
			world.events.publish({"type": "noise.device.triggered", "entity": int(entity), "magnitude": want, "x": float(p.get("tx", 0)) + 0.5, "y": float(p.get("ty", 0)) + 0.5})
		else:
			world.events.publish({"type": "noise.device.spent", "entity": int(entity)})


# --- the `use` verb -------------------------------------------------------------------------

## Whether picking `use` on this item would do anything -- the same predicate the word menu asks and
## the same one the intake runs, so the menu and the sim cannot disagree. The shape
## `SimNeeds.can_use`, `SimTreatment.can_use_supply` and `SimLightModule.can_use` already have.
static func can_use(world: Variant, actor: int, item: int) -> bool:
	if not bool(SimInventoryRes.owns(world, actor, item)):
		return false
	if not is_placeable(world, item):
		return false
	return bool(_Fortify().call("can_place_noise", world, actor))


## Stand the device up in front of you. Reached through `use` on the device itself and not through a
## rung on the E ladder, for the reason the floodlight is not one: a string of firecrackers that
## sounds exactly like a gunfight is not a thing to put down because you pressed E on empty ground.
static func use_item(world: Variant, actor: int, item: int) -> bool:
	if not can_use(world, actor, item):
		return false
	return bool(_Fortify().call("place_noise", world, actor))


static func register_module(world: Variant) -> void:
	# `attention-emit` at order -10 rather than `structures`, which is where fortify's own
	# noisemaker clock sits. The difference is one tick and it is the difference between
	# `startsAtTick` meaning what it says and meaning "one after that": `attention.emit-movement`
	# runs at `attention-emit` order 0, so a device armed here is heard on the tick its own clock
	# names. Arming it in `structures` -- three phases later -- would leave every delay in content
	# off by one against the clock a gate measures it with.
	world.systems.register("noise.devices", "attention-emit", -10, func(w: Variant) -> void:
		_tick_devices(w)
	)
	# `item.use` belongs to whichever module the item is: needs at input 12 for anything edible,
	# treatment at 13 for anything medical, light at 14 for a cell or a floodlight, and this one at
	# 15 for a thing you stand somewhere to make a racket. Four modules subscribe to one command
	# without arguing because each refuses what is not its business -- `can_use` above answers false
	# for everything that is not an unplaced noise device with ground to stand on.
	world.systems.register("noise.intake", "input", 15, func(w: Variant) -> void:
		for cmd in w.commands.current as Array:
			var c: Dictionary = cmd as Dictionary
			if String(c.get("type", "")) != "item.use":
				continue
			for actor in w.components.query(["controlled", "equipment"]):
				use_item(w, int(actor), int(c.get("item", -1)))
	)
