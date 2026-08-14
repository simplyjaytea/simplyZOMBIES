class_name SimStats
extends RefCounted

var _defs: Dictionary = {}

func define(def: Dictionary) -> void:
	var id: String = String(def["id"])
	assert(not _defs.has(id), "Stat already defined: " + id)
	_defs[id] = def

func has(id: String) -> bool:
	return _defs.has(id)

func get_def(id: String) -> Variant:
	return _defs.get(id)

func get_or_throw(id: String) -> Dictionary:
	assert(_defs.has(id), "Unknown stat: " + id)
	return _defs[id] as Dictionary

func ids() -> Array[String]:
	var out: Array[String] = []
	for k in _defs.keys():
		out.append(String(k))
	out.sort()
	return out

static func define_core_stats(reg: SimStats) -> void:
	var core: Array[Dictionary] = [
		{"id": "noise_emission", "base": 1.0, "min": 0.0},
		{"id": "noise_propagation", "base": 1.0, "min": 0.0},
		{"id": "ranged_accuracy", "base": 1.0, "min": 0.0},
		{"id": "healing_rate", "base": 1.0, "min": 0.0},
		{"id": "structure_decay", "base": 1.0, "min": 0.0},
		{"id": "spoilage_rate", "base": 1.0, "min": 0.0},
		{"id": "move_speed", "base": 1.0, "min": 0.0},
		{"id": "mood", "base": 0.0, "min": -100.0, "max": 100.0},
		{"id": "temperature", "base": 0.0},
		{"id": "melee_damage", "base": 1.0, "min": 0.0},
		{"id": "melee_reach", "base": 1.0, "min": 0.0},
		{"id": "melee_stagger", "base": 1.0, "min": 0.0},
		{"id": "swing_speed", "base": 1.0, "min": 0.1},
		{"id": "swing_recovery", "base": 1.0, "min": 0.1},
		{"id": "swing_stamina", "base": 1.0, "min": 0.0},
		{"id": "condition_loss", "base": 1.0, "min": 0.0},
		{"id": "repair_cost", "base": 1.0, "min": 0.0},
		{"id": "bleed_on_hit", "base": 0.0, "min": 0.0},
		{"id": "carry_capacity", "base": 25.0, "min": 1.0},
		{"id": "stamina_recovery", "base": 1.0, "min": 0.0},
		{"id": "infection_progression", "base": 1.0, "min": 0.75, "max": 1.25},
		{"id": "grab_escape", "base": 1.0, "min": 0.1},
		{"id": "damage_taken", "base": 1.0, "min": 0.80, "max": 1.15},
	]
	for d in core:
		reg.define(d)
