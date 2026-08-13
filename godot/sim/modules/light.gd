class_name SimLightModule
extends RefCounted

const HAND_SLOTS: Array[String] = ["primary", "secondary"]


static func _get_content_entry(world: Variant, type_id: String, id: String) -> Variant:
	if world == null or world.content == null:
		return null
	var c: Variant = world.content
	if c is Object and (c as Object).has_method("get"):
		return (c as Object).call("get", type_id, id)
	if c is Dictionary and (c as Dictionary).has(type_id):
		var by_id: Variant = (c as Dictionary)[type_id]
		if by_id is Dictionary:
			var hit: Variant = (by_id as Dictionary).get(id)
			if hit != null:
				return hit
		for v in (c as Dictionary).values():
			if v is Array:
				for e in v as Array:
					if e is Dictionary and String((e as Dictionary).get("id","")) == id:
						return e
			elif v is Dictionary and String((v as Dictionary).get("id","")) == id:
				return v as Dictionary
	return null

static func light_reach_of(world: Variant, item: int) -> Variant:
	var base: Variant = null
	var item_comp: Variant = world.components.get_component(item, "itemBase")
	if item_comp is Dictionary:
		base = _get_content_entry(world, "item", String((item_comp as Dictionary).get("baseId","")))
	if base == null and world.content != null and world.content is Object and (world.content as Object).has_method("get"):
		base = (world.content as Object).call("get", "item", str(item))
	if base == null:
		base = world.components.get_component(item, "item_base")
	if base == null:
		return null
	var light: Variant = (base as Dictionary).get("light")
	if light == null:
		return null
	var mag: Variant = (light as Dictionary).get("magnitude")
	if mag is float or mag is int:
		var f: float = float(mag)
		return f if f > 0.0 else null
	return null


static func make_light_source(world: Variant, entity: int, magnitude: float) -> void:
	world.components.set_component(entity, "light_source", {"magnitude": magnitude})
	world.events.publish({"type": "light.changed", "entity": entity, "magnitude": magnitude})


static func register_module(world: Variant) -> void:
	world.events.subscribe({"id": "light.equip-source", "type": "item.equipped", "handler": func(event: Dictionary) -> void:
		if not HAND_SLOTS.has(str(event["slot"])):
			return
		var mag: Variant = light_reach_of(world, int(event["item"]))
		if mag == null:
			return
		world.components.set_component(int(event["entity"]), "light_source", {"magnitude": float(mag)})
		world.events.publish({"type": "light.changed", "entity": int(event["entity"]), "magnitude": float(mag)})
	})
	world.events.subscribe({"id": "light.unequip-source", "type": "item.unequipped", "handler": func(event: Dictionary) -> void:
		if not HAND_SLOTS.has(str(event["slot"])):
			return
		if light_reach_of(world, int(event["item"])) == null:
			return
		world.components.remove(int(event["entity"]), "light_source")
		world.events.publish({"type": "light.changed", "entity": int(event["entity"]), "magnitude": 0.0})
	})
