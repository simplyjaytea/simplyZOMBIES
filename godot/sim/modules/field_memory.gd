class_name SimFieldMemory
extends RefCounted

const RESIDUE_MAGNITUDE: float = 30.0
const SCENT_EMIT_INTERVAL: int = 20


static func register_module(world: Variant) -> void:
	world.systems.register("field-memory.residue", "attention-emit", 0, func(w: Variant) -> void:
		if int(w.tick) % SCENT_EMIT_INTERVAL != 0:
			return
		for entity in w.components.query(["position", "shambler"]):
			var shambler_data: Variant = w.components.get_component(int(entity), "shambler")
			if shambler_data == null:
				continue
			# Investigate == 2
			if int((shambler_data as Dictionary)["state"]) != 2:
				continue
			var pos: Variant = w.components.get_component(int(entity), "position")
			if pos == null:
				continue
			w.events.publish({"type": "scent.accumulated", "x": float((pos as Dictionary)["x"]), "y": float((pos as Dictionary)["y"]), "magnitude": RESIDUE_MAGNITUDE})
	)
