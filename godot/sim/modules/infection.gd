class_name SimInfection
extends RefCounted

const BITE_TRANSMISSION_CHANCE: float = 0.85


static func register_module(world: Variant) -> void:
	var rng: Variant = world.rng.stream("infection")
	world.events.subscribe({"id": "infection.record-bite", "type": "bite.landed", "handler": func(event: Dictionary) -> void:
		var victim: int = int(event["victim"])
		var state: Variant = world.components.get_component(victim, "zombieInfection")
		if state == null:
			state = {"exposures": []}
			world.components.set_component(victim, "zombieInfection", state)
		var exposures: Array = (state as Dictionary)["exposures"] as Array
		exposures.append({
			"source": int(event["source"]),
			"bodyPart": String(event["bodyPart"]),
			"exposedAtTick": int(world.tick),
			"transmitted": float(rng.call("next")) < BITE_TRANSMISSION_CHANCE,
		})
	})
