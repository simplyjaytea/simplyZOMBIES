class_name SimLightModule
extends RefCounted

## Every slot a carried light is looked for in -- the owner's decision of 2026-09-12, and the
## repair of a dead socket that had been in the schema since lights shipped. This list used to be
## `HAND_SLOTS = ["primary", "secondary"]` and it was the *only* list `carried_magnitude` walked,
## so `head` and `eyes` -- both legal `equipSlot` values, both perfectly spellable in content --
## were invisible to the light field and a headlamp was literally impossible: the content would
## validate, the item would equip, the pawn would wear it and the district would stay dark.
##
## The two hands come first and the order is load-bearing: `brightest_carried` keeps the first of
## two equal magnitudes, so a torch in the hand wins a tie against a band on the head, which is
## the one you would actually be pointing at the thing.
const LIGHT_SLOTS: Array[String] = ["primary", "secondary", "head", "eyes"]

## What refills a lamp. Matched exactly against an item's top-level `lightFuel`, never ranked and
## never converted -- the rule a caliber follows, for the same reason: a battery either goes into
## the thing or it does not, and "close enough" is a conversion nobody asked for. The vocabulary
## lives here and in item.schema.json's two enums, and check_m2_light_burn.gd's CONTENT lane
## asserts both directions because neither list can see the other.
const FUEL_KINDS: Array[String] = ["cell", "oil", "gas"]

## How near you must be to top up something standing in the yard. A floodlight is furniture and
## you have to walk to it.
const FEED_REACH: float = 1.8


# The canonical content accessor, borrowed rather than copied. This module used to carry its own,
# and its own was broken in a way nothing could see: the fallback scan over a path-keyed tree sat
# *inside* a `has(type_id)` guard, and `ContentLoader.load_tree` returns a dictionary keyed by path
# ("items/light.json"), never by type. So `has("item")` was false, the scan never ran, and
# `light_reach_of` returned null for every item in the game -- the candle, the lamp and the oil
# lantern have all declared a `light` block that nothing carried has ever read. `items.gd`'s
# `content_entry` says in its own comment that other modules "should not each grow their own copy
# of it", which is exactly the bill this module was running up.
#
# Loaded rather than preloaded: `items.gd` is a large module and this one is a leaf.
static func _Items() -> GDScript:
	return load("res://sim/modules/items.gd") as GDScript


# Loaded on demand rather than preloaded: `attachments.gd` reaches items and inventory, and a
# preload here would be one more edge in a graph this module sits at the leaf of.
static func _Attachments() -> GDScript:
	return load("res://sim/modules/attachments.gd") as GDScript


static func _Inventory() -> GDScript:
	return load("res://sim/modules/inventory.gd") as GDScript


# `needs.gd` owns `consume_item`, which is the one place in the game a unit of anything is spent
# and therefore the one place `empties` is decided. A cell spent here goes through it rather than
# through a second decrement that would forget the stack.
static func _Needs() -> GDScript:
	return load("res://sim/modules/needs.gd") as GDScript


# Planting furniture is fortify's job and the channel is fortify's `construct`. Loaded rather than
# preloaded in both directions, because fortify reaches back here to finish the job.
static func _Fortify() -> GDScript:
	return load("res://sim/modules/fortify.gd") as GDScript


# --- content ------------------------------------------------------------------------------------

## The `light` block of whatever this entity is -- an item in a pocket, or a lamp planted in the
## yard, which carries its base id on `placedLight` because it is furniture and has no `itemBase`.
static func light_block_of(world: Variant, entity: int) -> Variant:
	var base_id: String = base_id_of(world, entity)
	if base_id.is_empty():
		return null
	var base: Variant = _Items().call("content_entry", world, "item", base_id)
	if not (base is Dictionary):
		return null
	var light: Variant = (base as Dictionary).get("light")
	return light if light is Dictionary else null


## The base id behind an entity, whether it is still an item or has been planted as furniture.
static func base_id_of(world: Variant, entity: int) -> String:
	var item_comp: Variant = world.components.get_component(entity, "itemBase")
	if item_comp is Dictionary:
		return String((item_comp as Dictionary).get("baseId", ""))
	var planted: Variant = world.components.get_component(entity, "placedLight")
	if planted is Dictionary:
		return String((planted as Dictionary).get("baseId", ""))
	return ""


## What one item throws on its own, or null. **Null once its fuel is out**, which is the whole burn
## mechanism expressed at the one choke point every other reader goes through: `brightest_of` takes
## a max over this, `brightest_carried` takes a max over that, and `refresh_carried` writes the
## result -- so a dead cell makes the lamp dark everywhere at once and the next-brightest thing in
## your hands takes over without a single one of those three knowing what a battery is.
static func light_reach_of(world: Variant, item: int) -> Variant:
	var light: Variant = light_block_of(world, item)
	if light == null:
		return null
	var mag: Variant = (light as Dictionary).get("magnitude")
	if not (mag is float or mag is int):
		return null
	var f: float = float(mag)
	if f <= 0.0:
		return null
	if spent(world, item):
		return null
	return f


## How long a full charge, wick or fill lasts for this entity's base, or 0 when it burns for ever.
## Zero is the pre-slice behaviour and is still legal content: a campfire is not a battery.
static func capacity_of(world: Variant, entity: int) -> int:
	var light: Variant = light_block_of(world, entity)
	if light == null:
		return 0
	var ticks: Variant = (light as Dictionary).get("burnTicks")
	if not (ticks is float or ticks is int):
		return 0
	return maxi(0, int(ticks))


## What refills this entity's base, or "" when nothing does. A candle has no feed: it burns down
## and what is left is a stub, which is the trade it makes against a lamp that is brighter and
## hungrier.
static func feed_kind_of(world: Variant, entity: int) -> String:
	var light: Variant = light_block_of(world, entity)
	if light == null:
		return ""
	return String((light as Dictionary).get("feed", ""))


## What this item feeds, or "" when it is not fuel. The top-level `lightFuel`, flat under an enum
## for the reason `buildMaterial` is flat -- the content validator is shallow, so up here the enum
## is actually enforced.
static func fuel_kind_of(world: Variant, item: int) -> String:
	var base_id: String = base_id_of(world, item)
	if base_id.is_empty():
		return ""
	var base: Variant = _Items().call("content_entry", world, "item", base_id)
	if not (base is Dictionary):
		return ""
	return String((base as Dictionary).get("lightFuel", ""))


# --- the burn clock -------------------------------------------------------------------------

## The fuel record on one lamp, made on demand from content the first time it is asked for. Made
## lazily rather than at spawn so every lamp that already exists in a running world -- and every
## one inside a save written before this slice -- starts full rather than starting dark, and so
## `items.gd` does not have to learn what a light is. Null for anything that burns for ever.
static func _fuel_of(world: Variant, entity: int) -> Variant:
	var cap: int = capacity_of(world, entity)
	if cap <= 0:
		return null
	var comp: Variant = world.components.get_component(entity, "lightFuel")
	if comp is Dictionary:
		return comp
	world.components.set_component(entity, "lightFuel", {"ticksLeft": cap})
	return world.components.get_component(entity, "lightFuel")


## Ticks of burn left, the capacity when nothing has been spent yet, and -1 for a light that burns
## for ever. A number, and deliberately not something the screen is handed -- `fuel_clause` is.
static func fuel_left(world: Variant, entity: int) -> int:
	var cap: int = capacity_of(world, entity)
	if cap <= 0:
		return -1
	var comp: Variant = world.components.get_component(entity, "lightFuel")
	if not (comp is Dictionary):
		return cap
	return maxi(0, int((comp as Dictionary).get("ticksLeft", cap)))


## Whether this lamp is out. An absent record means full, never empty: that is what makes the lazy
## record above safe, and it is the difference between "nobody has burned this yet" and "this is
## dark", which a zero default would collapse.
static func spent(world: Variant, entity: int) -> bool:
	var comp: Variant = world.components.get_component(entity, "lightFuel")
	if not (comp is Dictionary):
		return false
	return int((comp as Dictionary).get("ticksLeft", 1)) <= 0


## What the inspect pane says about a lamp's fuel: a word, never a number and never a fraction.
## "" for anything that is not a light or that burns for ever, which is what every other item in
## the game gets. docs/01 clause 4 -- what a thing does is a sentence and how well it is doing it
## is a word.
static func fuel_clause(world: Variant, entity: int) -> String:
	var cap: int = capacity_of(world, entity)
	if cap <= 0:
		return ""
	var left: int = fuel_left(world, entity)
	if left <= 0:
		return "dark"
	if left * 8 <= cap:
		return "guttering"
	if left * 3 <= cap:
		return "burning low"
	return "burning steadily"


## One tick off whatever is actually alight. Only the thing that is *lighting* somebody burns:
## max-not-sum means the candle in your off hand is not lit while the lamp in your right hand is,
## so it does not burn down while the lamp does. A planted floodlight is its own light source and
## burns itself.
static func _tick_burn(world: Variant) -> void:
	var lit: Array[int] = []
	for entity in world.components.query(["light_source"]):
		lit.append(int(entity))
	# Two passes rather than one. `_fuel_of` writes a component the first time it sees a lamp, and
	# mutating the component store inside its own query is how a scan starts skipping rows.
	var spent_now: Array = []
	for holder in lit:
		var burner: int = holder if world.components.has_component(holder, "placedLight") else int(brightest_carried(world, holder).get("item", -1))
		if burner < 0:
			continue
		var fuel: Variant = _fuel_of(world, burner)
		if not (fuel is Dictionary):
			continue
		var left: int = int((fuel as Dictionary).get("ticksLeft", 0))
		if left <= 0:
			continue
		left -= 1
		(fuel as Dictionary)["ticksLeft"] = left
		if left <= 0:
			spent_now.append({"holder": holder, "item": burner})
	for rec_v in spent_now:
		var rec: Dictionary = rec_v as Dictionary
		var holder2: int = int(rec["holder"])
		var item2: int = int(rec["item"])
		world.events.publish({"type": "light.spent", "entity": holder2, "item": item2})
		if holder2 == item2:
			world.components.remove(holder2, "light_source")
			world.events.publish({"type": "light.changed", "entity": holder2, "magnitude": 0.0})
		else:
			refresh_carried(world, holder2)


# --- feeding ------------------------------------------------------------------------------------

## The lamp this unit of fuel would go into, or -1. The emptiest match wins, so a spare cell tops
## up the torch that is guttering rather than the one you have barely used -- and a lamp that is
## already full is not a match at all, which is what stops `use` being offered on a battery you
## have nowhere to put.
##
## Carried lamps and planted ones both, because a floodlight in the yard is exactly the thing a
## propane cylinder is for and walking it back into your pack to refill it would be silly.
static func feed_target(world: Variant, actor: int, fuel_item: int) -> int:
	var kind: String = fuel_kind_of(world, fuel_item)
	if kind.is_empty() or not FUEL_KINDS.has(kind):
		return -1
	var best: int = -1
	var best_left: int = -1
	for lamp_v in _Inventory().call("carried_items", world, actor) as Array:
		var lamp: int = int(lamp_v)
		if lamp == fuel_item:
			continue
		if feed_kind_of(world, lamp) != kind:
			continue
		var cap: int = capacity_of(world, lamp)
		var left: int = fuel_left(world, lamp)
		if cap <= 0 or left >= cap:
			continue
		if best < 0 or left < best_left:
			best = lamp
			best_left = left
	for planted in world.components.query(["placedLight", "position"]):
		var lamp2: int = int(planted)
		if feed_kind_of(world, lamp2) != kind:
			continue
		if not _within(world, actor, lamp2, FEED_REACH):
			continue
		var cap2: int = capacity_of(world, lamp2)
		var left2: int = fuel_left(world, lamp2)
		if cap2 <= 0 or left2 >= cap2:
			continue
		if best < 0 or left2 < best_left:
			best = lamp2
			best_left = left2
	return best


## Spend one unit of fuel into the lamp it fits. The unit goes through needs' `consume_item`, the
## one place a unit of anything is spent, so a stack of cells loses one and an `empties` -- should
## a fuel ever declare one -- is still left in the hand.
static func feed(world: Variant, actor: int, fuel_item: int) -> bool:
	var lamp: int = feed_target(world, actor, fuel_item)
	if lamp < 0:
		return false
	var cap: int = capacity_of(world, lamp)
	if cap <= 0:
		return false
	var kind: String = fuel_kind_of(world, fuel_item)
	world.components.set_component(lamp, "lightFuel", {"ticksLeft": cap})
	if not bool(_Needs().call("consume_item", world, actor, fuel_item)):
		return false
	world.events.publish({"type": "light.fed", "entity": actor, "item": lamp, "kind": kind})
	if world.components.has_component(lamp, "placedLight"):
		var mag: Variant = light_reach_of(world, lamp)
		if mag != null:
			make_light_source(world, lamp, float(mag))
	else:
		refresh_carried(world, actor)
	return true


# --- planting -----------------------------------------------------------------------------------

## A light nobody can hold is a light meant to stand somewhere: `item.floodlight.rigged` is 3x3,
## magnitude 90, sits in the military cache's table and declares **no equipSlot at all**, so until
## this slice a player could find one and do precisely nothing with it. The predicate is "declares
## a light and cannot be worn", not a list of ids, so the second one costs a content edit.
static func is_plantable(world: Variant, item: int) -> bool:
	if light_block_of(world, item) == null:
		return false
	if world.components.has_component(item, "placedLight"):
		return false
	var base_id: String = base_id_of(world, item)
	var base: Variant = _Items().call("content_entry", world, "item", base_id)
	if not (base is Dictionary):
		return false
	return String((base as Dictionary).get("equipSlot", "")).is_empty()


## The first plantable light this body is carrying, or -1.
static func carried_plantable(world: Variant, actor: int) -> int:
	for item_v in _Inventory().call("carried_items", world, actor) as Array:
		if is_plantable(world, int(item_v)):
			return int(item_v)
	return -1


## Stand the thing up on a tile and turn it on. Called by fortify when the channel completes, and
## re-derived here rather than trusted from the start -- `_place_bench`'s rule, because a channel
## that began over open ground and ended over somebody's camp must leave nothing behind.
##
## The item *becomes* the furniture rather than being destroyed and replaced: one entity, so the
## fuel it had in it is the fuel it stands there with, and a floodlight half burnt in the pack is
## the same object half burnt in the yard.
static func plant(world: Variant, actor: int, tx: int, ty: int) -> int:
	var item: int = carried_plantable(world, actor)
	if item < 0:
		return -1
	var mag: Variant = light_reach_of(world, item)
	var base_id: String = base_id_of(world, item)
	_Inventory().call("remove_from_container", world, item)
	_Inventory().call("unequip_item", world, item)
	world.components.set_component(item, "position", {"x": float(tx) + 0.5, "y": float(ty) + 0.5})
	world.components.set_component(item, "placedLight", {"baseId": base_id, "tx": tx, "ty": ty})
	# It stops being loot the moment it becomes furniture. `SimInventory.ground_items` is "has a
	# position and is not stored", so without this line the yard light would be the thing E picks
	# up instead of the tin of beans beside it, and it would then go on lighting the district from
	# inside a rucksack. Stored in itself, which is the one container it can never be taken out of.
	world.components.set_component(item, "stored", {"container": item, "x": 0, "y": 0, "rotated": false})
	# A floodlight planted with a dead cell stands there dark, which is honest: it is planted, it
	# just is not lit, and one bottle of gas fixes it.
	if mag != null:
		make_light_source(world, item, float(mag))
	world.events.publish({"type": "light.planted", "entity": item, "actor": actor, "tx": tx, "ty": ty})
	return item


# --- the `use` verb -------------------------------------------------------------------------

## Whether picking `use` on this item would do anything -- the same predicate the word menu asks
## and the same one the intake runs, so the menu and the sim cannot disagree. This is the shape
## `SimNeeds.can_use` and `SimTreatment.can_use_supply` already have, and `verbs_for` now asks all
## three.
static func can_use(world: Variant, actor: int, item: int) -> bool:
	if not bool(_Inventory().call("owns", world, actor, item)):
		return false
	if feed_target(world, actor, item) >= 0:
		return true
	if is_plantable(world, item):
		return bool(_Fortify().call("can_place_light", world, actor))
	return false


## Feed a lamp, or stand a floodlight up in front of you. One verb, because from the player's side
## both are "do the thing this is for".
static func use_item(world: Variant, actor: int, item: int) -> bool:
	if not bool(_Inventory().call("owns", world, actor, item)):
		return false
	if feed_target(world, actor, item) >= 0:
		return feed(world, actor, item)
	if is_plantable(world, item):
		return bool(_Fortify().call("place_light", world, actor))
	return false


# --- what a person is carrying ---------------------------------------------------------------

## The light one *item* throws, counting anything fitted to it, and which part of it is throwing
## it. docs/10 has promised since attachments landed that a weapon light is "a real light source
## and therefore a real emitter", and this is the half of that sentence the light field reads: a
## torch taped under a barrel lights the person holding the barrel.
##
## The brightest wins rather than the sum. Two lamps do not carry twice as far -- reach is a
## radius, and adding radii is not what adding lamps does. The *item* comes back beside the
## magnitude because the burn clock has to spend the thing that is actually alight, and a second
## scan deciding that separately is a second scan that would one day disagree with this one.
static func brightest_of(world: Variant, item: int) -> Dictionary:
	var best: float = 0.0
	var who: int = -1
	var own: Variant = light_reach_of(world, item)
	if own != null:
		best = float(own)
		who = item
	var slots: Dictionary = _Attachments().call("attached", world, item) as Dictionary
	for slot in slots.keys():
		var part: int = int(slots[slot])
		var lit: Variant = light_reach_of(world, part)
		if lit != null and float(lit) > best:
			best = float(lit)
			who = part
	return {"item": who, "magnitude": best}


## The brightest thing a *person* has alight, across every slot in LIGHT_SLOTS and everything
## fitted to what is in them, as `{item, magnitude}`.
static func brightest_carried(world: Variant, entity: int) -> Dictionary:
	var held: Dictionary = _slot_items(world, entity)
	var best: float = 0.0
	var who: int = -1
	for slot in LIGHT_SLOTS:
		if not held.has(slot):
			continue
		var pick: Dictionary = brightest_of(world, int(held[slot]))
		if float(pick.get("magnitude", 0.0)) > best:
			best = float(pick["magnitude"])
			who = int(pick["item"])
	return {"item": who, "magnitude": best}


## The light a *person* carries. One scan, not two: this is `brightest_carried`'s magnitude, so
## the number the field is given and the lamp the clock burns are decided in the same place.
static func carried_magnitude(world: Variant, entity: int) -> float:
	return float(brightest_carried(world, entity).get("magnitude", 0.0))


## What this entity has in every slot light is looked for in. `equipment` nests its contents one
## level down -- `{"slots": {...}}` -- and reading it flat is a key nothing writes, which raises
## nothing and quietly finds no light at all.
static func _slot_items(world: Variant, entity: int) -> Dictionary:
	var equipment: Variant = world.components.get_component(entity, "equipment")
	if not equipment is Dictionary:
		return {}
	var slots: Variant = (equipment as Dictionary).get("slots")
	if not slots is Dictionary:
		return {}
	var out: Dictionary = {}
	for slot in LIGHT_SLOTS:
		if (slots as Dictionary).has(slot):
			out[slot] = int((slots as Dictionary)[slot])
	return out


static func _within(world: Variant, actor: int, target: int, reach: float) -> bool:
	var a: Variant = world.components.get_component(actor, "position")
	var b: Variant = world.components.get_component(target, "position")
	if not (a is Dictionary) or not (b is Dictionary):
		return false
	var dx: float = float((a as Dictionary)["x"]) - float((b as Dictionary)["x"])
	var dy: float = float((a as Dictionary)["y"]) - float((b as Dictionary)["y"])
	return dx * dx + dy * dy <= reach * reach


## Sets this entity's `light_source` to whatever it is *currently* carrying, or removes it when
## that is nothing. One writer for the whole carried-light story -- equipping, unequipping,
## fitting a light to a weapon, taking it off again, a cell running flat, and a muzzle flash
## burning out.
##
## **This is what the muzzle flash must fall back to rather than delete.** `ranged.gd` used to
## overwrite `light_source` with the flash magnitude and then, when the flash expired, remove the
## component if its magnitude still equalled the flash -- which the overwrite had just guaranteed.
## A mounted light therefore went out permanently on the first shot, silently, and the guard read
## as though it were being careful.
static func refresh_carried(world: Variant, entity: int) -> void:
	var mag: float = carried_magnitude(world, entity)
	if mag > 0.0:
		world.components.set_component(entity, "light_source", {"magnitude": mag})
	elif world.components.has_component(entity, "light_source"):
		world.components.remove(entity, "light_source")
	world.events.publish({"type": "light.changed", "entity": entity, "magnitude": mag})


static func make_light_source(world: Variant, entity: int, magnitude: float) -> void:
	world.components.set_component(entity, "light_source", {"magnitude": magnitude})
	world.events.publish({"type": "light.changed", "entity": entity, "magnitude": magnitude})


static func register_module(world: Variant) -> void:
	# Movement order 70, five before the kernel's own `kernel.light` at 75 and thirty before
	# `kernel.visibility` at 100: a wick that runs out on this tick is dark in *this* tick's
	# shadowcast, rather than throwing one last free step of light at a district that is about to
	# be redrawn. The burn is registered here rather than in `structures` for exactly that reason
	# -- what it changes is what the light index is about to read.
	world.systems.register("light.burn", "movement", 70, func(w: Variant) -> void:
		_tick_burn(w)
	)
	# Equipping and unequipping both just ask what the person is carrying now. The old pair asked
	# instead whether *this item* had a light and set or removed the component accordingly, which
	# could not see a light fitted to something else in the other hand -- and, more to the point,
	# could not see one fitted to the weapon being equipped.
	world.events.subscribe({"id": "light.equip-source", "type": "item.equipped", "handler": func(event: Dictionary) -> void:
		if not LIGHT_SLOTS.has(str(event["slot"])):
			return
		refresh_carried(world, int(event["entity"]))
	})
	world.events.subscribe({"id": "light.unequip-source", "type": "item.unequipped", "handler": func(event: Dictionary) -> void:
		if not LIGHT_SLOTS.has(str(event["slot"])):
			return
		refresh_carried(world, int(event["entity"]))
	})
	# A light bolted to a rifle is a light. Without these two the part would be a dead socket:
	# content could declare `light` on an attachment, the bench would fit it, the pawn would draw
	# it, and nothing in the world would be any brighter.
	world.events.subscribe({"id": "light.part-fitted", "type": "attachment.fitted", "handler": func(event: Dictionary) -> void:
		_refresh_holder_of(world, int(event["host"]))
	})
	world.events.subscribe({"id": "light.part-removed", "type": "attachment.removed", "handler": func(event: Dictionary) -> void:
		_refresh_holder_of(world, int(event["host"]))
	})
	world.events.subscribe({"id": "light.part-broke", "type": "attachment.broke", "handler": func(event: Dictionary) -> void:
		_refresh_holder_of(world, int(event["host"]))
	})
	# `item.use` belongs to whichever module the item is: needs at input 12 for anything edible,
	# treatment at 13 for anything medical, and this one at 14 for a cell, a fill of oil, a bottle
	# of gas and a floodlight looking for a patch of yard. Three modules can subscribe to one
	# command without arguing because each refuses what is not its business -- `use_item` above
	# answers false for everything that is neither fuel with somewhere to go nor a light that
	# wants standing up.
	world.systems.register("light.intake", "input", 14, func(w: Variant) -> void:
		for cmd in w.commands.current as Array:
			var c: Dictionary = cmd as Dictionary
			if String(c.get("type", "")) != "item.use":
				continue
			for actor in w.components.query(["controlled", "equipment"]):
				use_item(w, int(actor), int(c.get("item", -1)))
	)


## Whoever is holding `host`, refreshed. A part fitted to a weapon in a crate changes nobody's
## light; one fitted to the weapon in your hand changes yours.
static func _refresh_holder_of(world: Variant, host: int) -> void:
	var carrier: Variant = _Attachments().call("carrier_of", world, host)
	if carrier == null or int(carrier) < 0:
		return
	for slot in _slot_items(world, int(carrier)).values():
		if int(slot) == host:
			refresh_carried(world, int(carrier))
			return
