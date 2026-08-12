class_name SimSystemRegistry
extends RefCounted

const PHASES: Array[String] = ["input", "movement"]

var _systems: Array[Dictionary] = []


func register(id: String, phase: String, order: int, runner: Callable) -> void:
	assert(PHASES.has(phase), "Unknown simulation phase: %s" % phase)
	_systems.append({"id": id, "phase": phase, "order": order, "runner": runner})
	_systems.sort_custom(_comes_before)


func run(world: Variant) -> void:
	for system in _systems:
		var runner: Callable = system["runner"]
		runner.call(world)


func _comes_before(a: Dictionary, b: Dictionary) -> bool:
	var phase_a := PHASES.find(String(a["phase"]))
	var phase_b := PHASES.find(String(b["phase"]))
	if phase_a != phase_b:
		return phase_a < phase_b
	var order_a := int(a["order"])
	var order_b := int(b["order"])
	if order_a != order_b:
		return order_a < order_b
	return String(a["id"]) < String(b["id"])
