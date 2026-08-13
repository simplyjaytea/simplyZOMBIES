class_name SimLightModule
extends RefCounted

const HAND_SLOTS: Array[String] = ["primary", "secondary"]


static func light_reach_of(world: Variant, item: int) -> Variant:
	# Content-backed; requires items module. Minimal stub for boot: reads item base light.magnitude
	var base: Variant = null
	if world.content != null and world.content.has_method("get"):
		base = world.content.call("get", "item", str(item))
	# Fallback: check component
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
