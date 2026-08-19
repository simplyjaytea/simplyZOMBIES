class_name SimDebug
extends RefCounted
# Developer spawning, command-driven like everything else: presentation proposes
# `debug.spawn` and this module executes it inside the tick, so a spawn is ordered,
# deterministic (its randomness comes from a dedicated `debug` stream -- new randomness
# gets its own stream, per the loot-table precedent), and replayable like any other
# command. This is dev tooling for the F8 panel, not a game mechanism: nothing in
# ordinary play pushes it.

const SimItems = preload("res://sim/modules/items.gd")
const SimRoster = preload("res://sim/modules/roster.gd")


static func register_module(world: Variant) -> void:
	world.systems.register("debug.intake", "input", 12, func(w: Variant) -> void:
		for cmd in w.commands.current as Array:
			var c: Dictionary = cmd as Dictionary
			if String(c.get("type", "")) != "debug.spawn":
				continue
			var x: float = float(c.get("x", 0.0))
			var y: float = float(c.get("y", 0.0))
			var id: String = String(c.get("id", ""))
			if id.is_empty():
				continue
			match String(c.get("kind", "")):
				"item":
					var item: int = SimItems.spawn_item(w, id, {})
					w.components.set_component(item, "position", {"x": x, "y": y})
					w.events.publish({"type": "debug.spawned", "kind": "item", "id": id, "entity": item})
				"zombie":
					var rng: Variant = w.rng.stream("debug")
					var ent: int = SimRoster.spawn_zombie(w, x, y, id, rng)
					w.events.publish({"type": "debug.spawned", "kind": "zombie", "id": id, "entity": ent})
	)
