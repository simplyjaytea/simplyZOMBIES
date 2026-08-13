class_name SimSystemRegistry
extends RefCounted

const PHASES: Array[String] = [
	"input",
	"ai",
	"movement",
	"combat",
	"attention-emit",
	"attention-propagate",
	"needs",
	"health",
	"infection",
	"structures",
	"director",
	"cleanup",
]

var _systems: Array[Dictionary] = []
var _sorted: bool = false
var _phase_index: Dictionary = {}


func _init() -> void:
	for i in PHASES.size():
		_phase_index[String(PHASES[i])] = i


func register(id: String, phase: String, order: int, runner: Callable) -> void:
	assert(_phase_index.has(phase), "Unknown simulation phase: %s" % phase)
	for s in _systems:
		assert(String(s["id"]) != id, "System \"%s\" is already registered" % id)
	_systems.append({"id": id, "phase": phase, "order": order, "runner": runner})
	_sorted = false


func register_dict(system: Dictionary) -> void:
	register(String(system["id"]), String(system["phase"]), int(system.get("order", 0)), system["run"] as Callable)


func unregister(id: String) -> bool:
	for i in _systems.size():
		if String(_systems[i]["id"]) == id:
			_systems.remove_at(i)
			return true
	return false


func ordered() -> Array[Dictionary]:
	if not _sorted:
		_systems.sort_custom(_comes_before)
		_sorted = true
	return _systems


var ids: Array[String]:
	get:
		var out: Array[String] = []
		for s in ordered():
			out.append(String(s["id"]))
		return out


func run(world: Variant) -> void:
	for system in ordered():
		var runner: Callable = system["runner"] as Callable
		runner.call(world)


func _comes_before(a: Dictionary, b: Dictionary) -> bool:
	var phase_a: int = int(_phase_index.get(String(a["phase"]), 999))
	var phase_b: int = int(_phase_index.get(String(b["phase"]), 999))
	if phase_a != phase_b:
		return phase_a < phase_b
	var order_a: int = int(a["order"])
	var order_b: int = int(b["order"])
	if order_a != order_b:
		return order_a < order_b
	return String(a["id"]) < String(b["id"])
