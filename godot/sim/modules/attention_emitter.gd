class_name SimAttentionEmitter
extends RefCounted

const SimTileMapRes = preload("res://sim/map/tilemap.gd")
const SimSurface = preload("res://sim/map/surface.gd")

const SPRINT_THRESHOLD: float = 4.2
const SHOUT_MAGNITUDE: float = 120.0
const SCENT_EMIT_INTERVAL: int = 20

const PERSON_EMITTER: Dictionary = {
	"walking": 1.0,
	"sprinting": 6.0,
	"ambient": 0.0,
	"scent": 1.0,
}


static func make_emitter(world: Variant, entity: int, emitter: Variant = null) -> void:
	var e: Dictionary = (emitter if emitter != null else PERSON_EMITTER.duplicate(true)) as Dictionary
	world.components.set_component(entity, "attention_emitter", e)


static func register_module(world: Variant, map: Variant) -> void:
	world.systems.register("attention.emit-movement", "attention-emit", 0, func(w: Variant) -> void:
		for entity in w.components.query(["position", "velocity", "attention_emitter"]):
			var emitter: Variant = w.components.get_component(int(entity), "attention_emitter")
			var vel: Variant = w.components.get_component(int(entity), "velocity")
			if emitter == null or vel == null:
				continue
			var speed: float = sqrt(float((vel as Dictionary)["dx"]) * float((vel as Dictionary)["dx"]) + float((vel as Dictionary)["dy"]) * float((vel as Dictionary)["dy"]))
			var posture: Variant = w.components.get_component(int(entity), "posture")
			var base: float
			if posture != null:
				var cur: int = int((posture as Dictionary)["current"])
				# stance noise lookup: stances.gd NOISE array
				var stances_scr: GDScript = load("res://sim/stances.gd") as GDScript
				var noise_arr: Array = stances_scr.NOISE as Array
				base = float(noise_arr[cur]) if speed > 0.0 else float((emitter as Dictionary)["ambient"])
			else:
				if speed >= SPRINT_THRESHOLD:
					base = float((emitter as Dictionary)["sprinting"])
				elif speed > 0.0:
					base = float((emitter as Dictionary)["walking"])
				else:
					base = float((emitter as Dictionary)["ambient"])
			if base <= 0.0:
				continue
			var pos: Variant = w.components.get_component(int(entity), "position")
			if pos == null:
				continue
			var magnitude: float = base
			# DEX speeds the body; scale per-tick noise by move_speed so noise-per-metre stays put (docs/23 DEX guardrail).
			if speed > 0.0 and w.modifiers != null and (w.modifiers as Object).has_method("resolve"):
				magnitude *= float(w.modifiers.call("resolve", "move_speed", int(entity)))
			# Only footsteps scaled by surface; ambient not
			if not (float((emitter as Dictionary)["ambient"]) > 0.0 and speed == 0.0):
				var surf: int = SimSurface.surface_at(map, floori(float((pos as Dictionary)["x"]) / float(SimTileMapRes.TILE_METRES)), floori(float((pos as Dictionary)["y"]) / float(SimTileMapRes.TILE_METRES)))
				magnitude = base * SimSurface.noise_on(surf)
			w.events.publish({"type": "noise.emitted", "x": float((pos as Dictionary)["x"]), "y": float((pos as Dictionary)["y"]), "magnitude": magnitude, "source": int(entity)})
	)
	world.systems.register("attention.emit-scent", "attention-emit", 0, func(w: Variant) -> void:
		if int(w.tick) % SCENT_EMIT_INTERVAL != 0:
			return
		for entity in w.components.query(["position", "attention_emitter"]):
			var emitter: Variant = w.components.get_component(int(entity), "attention_emitter")
			if emitter == null or float((emitter as Dictionary)["scent"]) <= 0.0:
				continue
			var pos: Variant = w.components.get_component(int(entity), "position")
			if pos == null:
				continue
			w.events.publish({"type": "scent.accumulated", "x": float((pos as Dictionary)["x"]), "y": float((pos as Dictionary)["y"]), "magnitude": float((emitter as Dictionary)["scent"])})
	)
