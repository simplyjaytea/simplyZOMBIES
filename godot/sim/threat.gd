class_name SimThreat
extends RefCounted

const THREAT_METRES: float = 12.0


static func threat_within(world: Variant, entity: int, metres: float = THREAT_METRES) -> bool:
	var pos: Variant = world.components.get_component(entity, "position")
	if pos == null:
		return false
	var hx: float = float((pos as Dictionary)["x"])
	var hy: float = float((pos as Dictionary)["y"])
	var limit: float = metres * metres
	for other in world.components.query(["position", "shambler"]):
		var there: Variant = world.components.get_component(int(other), "position")
		if there == null:
			continue
		var dx: float = float((there as Dictionary)["x"]) - hx
		var dy: float = float((there as Dictionary)["y"]) - hy
		if dx * dx + dy * dy <= limit:
			return true
	return false
