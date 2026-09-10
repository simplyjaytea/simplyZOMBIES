class_name SimLightModule
extends RefCounted

const HAND_SLOTS: Array[String] = ["primary", "secondary"]


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


static func light_reach_of(world: Variant, item: int) -> Variant:
	var item_comp: Variant = world.components.get_component(item, "itemBase")
	if not item_comp is Dictionary:
		return null
	var base: Variant = _Items().call("content_entry", world, "item", String((item_comp as Dictionary).get("baseId", "")))
	if not base is Dictionary:
		return null
	var light: Variant = (base as Dictionary).get("light")
	if light == null:
		return null
	var mag: Variant = (light as Dictionary).get("magnitude")
	if mag is float or mag is int:
		var f: float = float(mag)
		return f if f > 0.0 else null
	return null


# Loaded on demand rather than preloaded: `attachments.gd` reaches items and inventory, and a
# preload here would be one more edge in a graph this module sits at the leaf of.
static func _Attachments() -> GDScript:
	return load("res://sim/modules/attachments.gd") as GDScript


## The light one *item* throws, counting anything fitted to it. docs/10 has promised since
## attachments landed that a weapon light is "a real light source and therefore a real emitter",
## and this is the half of that sentence the light field reads: a torch taped under a barrel
## lights the person holding the barrel.
##
## The brightest wins rather than the sum. Two lamps do not carry twice as far -- reach is a
## radius, and adding radii is not what adding lamps does.
static func item_light_of(world: Variant, item: int) -> float:
	var best: float = 0.0
	var own: Variant = light_reach_of(world, item)
	if own != null:
		best = float(own)
	var slots: Dictionary = _Attachments().call("attached", world, item) as Dictionary
	for slot in slots.keys():
		var part: Variant = light_reach_of(world, int(slots[slot]))
		if part != null:
			best = maxf(best, float(part))
	return best


## The light a *person* carries, across both hands and everything fitted to what is in them.
static func carried_magnitude(world: Variant, entity: int) -> float:
	var held: Dictionary = _hand_items(world, entity)
	var best: float = 0.0
	for slot in held.keys():
		best = maxf(best, item_light_of(world, int(held[slot])))
	return best


## What this entity has in either hand, by slot. `equipment` nests its contents one level down --
## `{"slots": {...}}` -- and reading it flat is a key nothing writes, which raises nothing and
## quietly finds no light at all.
static func _hand_items(world: Variant, entity: int) -> Dictionary:
	var equipment: Variant = world.components.get_component(entity, "equipment")
	if not equipment is Dictionary:
		return {}
	var slots: Variant = (equipment as Dictionary).get("slots")
	if not slots is Dictionary:
		return {}
	var out: Dictionary = {}
	for slot in HAND_SLOTS:
		if (slots as Dictionary).has(slot):
			out[slot] = int((slots as Dictionary)[slot])
	return out


## Sets this entity's `light_source` to whatever it is *currently* carrying, or removes it when
## that is nothing. One writer for the whole carried-light story -- equipping, unequipping,
## fitting a light to a weapon, taking it off again, and a muzzle flash burning out.
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
	# Equipping and unequipping both just ask what the person is carrying now. The old pair asked
	# instead whether *this item* had a light and set or removed the component accordingly, which
	# could not see a light fitted to something else in the other hand -- and, more to the point,
	# could not see one fitted to the weapon being equipped.
	world.events.subscribe({"id": "light.equip-source", "type": "item.equipped", "handler": func(event: Dictionary) -> void:
		if not HAND_SLOTS.has(str(event["slot"])):
			return
		refresh_carried(world, int(event["entity"]))
	})
	world.events.subscribe({"id": "light.unequip-source", "type": "item.unequipped", "handler": func(event: Dictionary) -> void:
		if not HAND_SLOTS.has(str(event["slot"])):
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


## Whoever is holding `host`, refreshed. A part fitted to a weapon in a crate changes nobody's
## light; one fitted to the weapon in your hand changes yours.
static func _refresh_holder_of(world: Variant, host: int) -> void:
	var carrier: Variant = _Attachments().call("carrier_of", world, host)
	if carrier == null or int(carrier) < 0:
		return
	for slot in _hand_items(world, int(carrier)).values():
		if int(slot) == host:
			refresh_carried(world, int(carrier))
			return
