class_name SimBloater
extends RefCounted

# blooms_on_death: scent 30 at corpse + contamination flag 6 m / 90 s.
# ponytail: replace flag with diffusive plume when scent floor/ceiling tuned; upgrade path is scent channel write + timed decay.

const SimRosterRes = preload("res://sim/modules/roster.gd")
const SimInfectionRes = preload("res://sim/modules/infection.gd")

const SCENT_BURST: float = 30.0
const FLAG_RADIUS: float = 6.0
const FLAG_TICKS: int = 90 * 20
const EXTRA_CHANCE: float = 0.4
const STREAM: String = "contamination"


static func register_module(world: Variant) -> void:
	world.events.subscribe({"id": "bloater.bloom", "type": "entity.killed", "handler": func(event: Dictionary) -> void:
		var ent: int = int(event["entity"])
		var type_id: String = String(event.get("zombieType", ""))
		if type_id == "":
			var zt: Variant = world.components.get_component(ent, "zombieType")
			if zt is Dictionary:
				type_id = String((zt as Dictionary).get("id", ""))
		if type_id == "" or not SimRosterRes.has_behavior(world, type_id, "blooms_on_death"):
			return
		var x: float = float(event.get("x", 0.0))
		var y: float = float(event.get("y", 0.0))
		if not event.has("x") or not event.has("y"):
			var pos: Variant = world.components.get_component(ent, "position")
			if pos is Dictionary:
				x = float((pos as Dictionary)["x"])
				y = float((pos as Dictionary)["y"])
		world.events.publish({"type": "scent.accumulated", "x": x, "y": y, "magnitude": SCENT_BURST})
		var flag: int = int(world.entities.spawn())
		world.components.set_component(flag, "position", {"x": x, "y": y})
		world.components.set_component(flag, "contamination", {
			"radius": FLAG_RADIUS,
			"expiresAtTick": int(world.tick) + FLAG_TICKS,
			"source": ent,
		})
	})

	world.systems.register("bloater.contamination", "infection", 20, func(w: Variant) -> void:
		var rng: Variant = w.rng.stream(STREAM)
		var flags: Array = []
		for entity in w.components.query(["contamination", "position"]):
			var c: Variant = w.components.get_component(int(entity), "contamination")
			if c == null:
				continue
			var cd: Dictionary = c as Dictionary
			if int(w.tick) >= int(cd.get("expiresAtTick", 0)):
				w.despawn(int(entity))
				continue
			flags.append({"entity": int(entity), "x": float((w.components.get_component(int(entity), "position") as Dictionary)["x"]), "y": float((w.components.get_component(int(entity), "position") as Dictionary)["y"]), "radius": float(cd.get("radius", FLAG_RADIUS)), "source": int(cd.get("source", 0))})
		if flags.is_empty():
			return
		for survivor in w.components.query(["position"]):
			if not (w.components.has_component(int(survivor), "controlled") or w.components.has_component(int(survivor), "identity")):
				continue
			if not _has_open_wound(w, int(survivor)):
				continue
			var rolled: Variant = w.components.get_component(int(survivor), "contaminationRolled")
			if rolled != null:
				continue
			var pos: Variant = w.components.get_component(int(survivor), "position")
			if pos == null:
				continue
			var px: float = float((pos as Dictionary)["x"])
			var py: float = float((pos as Dictionary)["y"])
			for f in flags:
				var fd: Dictionary = f as Dictionary
				var dx: float = px - float(fd["x"])
				var dy: float = py - float(fd["y"])
				var r: float = float(fd["radius"])
				if dx * dx + dy * dy > r * r:
					continue
				w.components.set_component(int(survivor), "contaminationRolled", {"atTick": int(w.tick)})
				# Extra exposure. Do not flip an existing transmitted flag.
				SimInfectionRes.record_extra_exposure(w, int(survivor), int(fd["source"]), rng, EXTRA_CHANCE)
				break
	)


static func _has_open_wound(world: Variant, entity: int) -> bool:
	var inj: Variant = world.components.get_component(entity, "injuries")
	if inj == null:
		return false
	var wounds: Array = (inj as Dictionary).get("wounds", []) as Array
	for w in wounds:
		var wd: Dictionary = w as Dictionary
		if String(wd.get("kind", "")) == "bite":
			return true
	return false
