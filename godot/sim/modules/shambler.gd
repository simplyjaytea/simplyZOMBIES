class_name SimShambler
extends RefCounted

# Port of src/sim/modules/shambler.ts — 5 states, gradient+bias pursuit
# ponytail: grab/cripple/stagger/bite sub-systems omitted; add when combat R3 lands.

const ShamblerState: Dictionary = {
	"Wander": 0,
	"Seek": 1,
	"Investigate": 2,
	"Staggered": 3,
	"Pursue": 4,
}

const DEFAULT_LOCOMOTION: Dictionary = {"speed": 0.8, "wander": 0.35, "mill": 0.25, "crawl": 0.25}
const DEFAULT_GRAB_STRENGTH: float = 0.5

const SPREAD_RADIANS: float = 0.62
const NOISE_SENSITIVITY: float = 0.2
const SCENT_SENSITIVITY: float = 0.9
const SCENT_BIAS: float = 0.35
const LIGHT_SENSITIVITY: float = 0.1
const LIGHT_BIAS: float = 0.5
const CONTACT_METRES: float = 1.6
const GRAB_METRES: float = 1.0
const RELEASE_METRES: float = 3.2
const MILL_TICKS: int = 90
const COMMIT_TICKS: int = 400

const SimLocomotionRes = preload("res://sim/locomotion.gd")
const SimTileMapRes = preload("res://sim/map/tilemap.gd")


static func default_shambler_speeds() -> Dictionary:
	var seek: float = SimLocomotionRes.zombie_speed(DEFAULT_LOCOMOTION["speed"])
	return {
		"seekSpeed": seek,
		"wanderSpeed": seek * float(DEFAULT_LOCOMOTION["wander"]),
		"millSpeed": seek * float(DEFAULT_LOCOMOTION["mill"]),
		"crawlFactor": float(DEFAULT_LOCOMOTION["crawl"]),
		"grabStrength": DEFAULT_GRAB_STRENGTH,
		"canGrab": true,
		"ticksToGrab": 0,
	}


static func make_shambler(world: Variant, entity: int, rng: Variant, type_id: String = "zombie.shambler") -> void:
	var loco: Dictionary = _locomotion_of(world, type_id)
	var grab: Dictionary = _grab_of(world, type_id)
	var seek_speed: float = SimLocomotionRes.zombie_speed(float(loco["speed"]))
	world.components.set_component(entity, "shambler", {
		"state": ShamblerState["Wander"],
		"ticksToTurn": int(rng.call("int_range", 20, 120)),
		"ticksMilling": 0,
		"ticksCommitted": 0,
		"bias": rng.call("float_range", -SPREAD_RADIANS, SPREAD_RADIANS),
		"ticksStaggered": 0,
		"seekSpeed": seek_speed,
		"wanderSpeed": seek_speed * float(loco["wander"]),
		"millSpeed": seek_speed * float(loco["mill"]),
		"crawlFactor": float(loco["crawl"]),
		"grabStrength": float(grab["strength"]),
		"canGrab": bool(grab["enabled"]),
		"ticksToGrab": 0,
	})


static func _locomotion_of(world: Variant, type_id: String) -> Dictionary:
	var entry: Variant = null
	if world.content != null and world.content.has_method("get"):
		entry = world.content.call("get", "zombie", type_id)
	var loco: Dictionary = {}
	if entry != null:
		var l: Variant = (entry as Dictionary).get("locomotion")
		if l != null:
			loco = l as Dictionary
	return {
		"speed": float(loco.get("speed", DEFAULT_LOCOMOTION["speed"])),
		"wander": float(loco.get("wander", DEFAULT_LOCOMOTION["wander"])),
		"mill": float(loco.get("mill", DEFAULT_LOCOMOTION["mill"])),
		"crawl": float(loco.get("crawl", DEFAULT_LOCOMOTION["crawl"])),
	}


static func _grab_of(world: Variant, type_id: String) -> Dictionary:
	var entry: Variant = null
	if world.content != null and world.content.has_method("get"):
		entry = world.content.call("get", "zombie", type_id)
	if entry == null:
		return {"enabled": true, "strength": DEFAULT_GRAB_STRENGTH}
	var behaviours: Variant = (entry as Dictionary).get("behaviors")
	var enabled: bool = true
	if behaviours is Array:
		enabled = (behaviours as Array).has("grab")
	else:
		enabled = true
	var grab: Dictionary = {}
	var g: Variant = (entry as Dictionary).get("grab")
	if g != null:
		grab = g as Dictionary
	return {"enabled": enabled, "strength": float(grab.get("strength", DEFAULT_GRAB_STRENGTH))}


static func _steer_uphill(field: Variant, pos: Dictionary, vel: Dictionary, shambler_data: Dictionary) -> bool:
	var uphill: Variant = field.uphill_noise(float(pos["x"]), float(pos["y"]))
	if uphill == null:
		return false
	var angle: float = atan2(float((uphill as Dictionary)["dy"]), float((uphill as Dictionary)["dx"])) + float(shambler_data["bias"])
	vel["dx"] = cos(angle) * float(shambler_data["seekSpeed"])
	vel["dy"] = sin(angle) * float(shambler_data["seekSpeed"])
	return true


static func _drift_upscent(field: Variant, pos: Dictionary, vel: Dictionary, shambler_data: Dictionary) -> void:
	var uphill: Variant = field.uphill_scent(float(pos["x"]), float(pos["y"]))
	if uphill == null:
		return
	var speed: float = sqrt(float(vel["dx"]) * float(vel["dx"]) + float(vel["dy"]) * float(vel["dy"]))
	if speed == 0.0:
		return
	var current: float = atan2(float(vel["dy"]), float(vel["dx"]))
	var toward: float = atan2(float((uphill as Dictionary)["dy"]), float((uphill as Dictionary)["dx"])) + float(shambler_data["bias"])
	var delta: float = toward - current
	while delta > PI:
		delta -= PI * 2.0
	while delta < -PI:
		delta += PI * 2.0
	var angle: float = current + delta * SCENT_BIAS
	vel["dx"] = cos(angle) * speed
	vel["dy"] = sin(angle) * speed


static func _contact_target(survivors: Array, pos: Dictionary, radius_metres: float) -> Variant:
	var limit: float = radius_metres * radius_metres
	var best: Variant = null
	var best_dist: float = limit
	for survivor in survivors:
		var s: Dictionary = survivor as Dictionary
		var dx: float = float(s["x"]) - float(pos["x"])
		var dy: float = float(s["y"]) - float(pos["y"])
		var dist: float = dx * dx + dy * dy
		if dist <= best_dist:
			best = s["entity"]
			best_dist = dist
	return best


static func _gather_survivors(world: Variant) -> Array:
	var out: Array = []
	for entity in world.components.query(["position", "controlled"]):
		var at: Variant = world.components.get_component(int(entity), "position")
		if at == null:
			continue
		out.append({"entity": int(entity), "x": float((at as Dictionary)["x"]), "y": float((at as Dictionary)["y"])})
	return out


static func _chase(world: Variant, target: int, pos: Dictionary, vel: Dictionary, shambler_data: Dictionary) -> void:
	var at: Variant = world.components.get_component(target, "position")
	if at == null:
		return
	var dx: float = float((at as Dictionary)["x"]) - float(pos["x"])
	var dy: float = float((at as Dictionary)["y"]) - float(pos["y"])
	var dist: float = sqrt(dx * dx + dy * dy)
	if dist == 0.0:
		return
	vel["dx"] = dx / dist * float(shambler_data["seekSpeed"])
	vel["dy"] = dy / dist * float(shambler_data["seekSpeed"])


static func _lean_to_light(world: Variant, entity: int, pos: Dictionary, vel: Dictionary) -> void:
	if not world.components.has_component(entity, "observer"):
		return
	var speed: float = sqrt(float(vel["dx"]) * float(vel["dx"]) + float(vel["dy"]) * float(vel["dy"]))
	if speed == 0.0:
		return
	var best_rem: float = 0.0
	var best_x: float = 0.0
	var best_y: float = 0.0
	for source in world.light.sources():
		var at: Variant = world.light.source_at(int(source))
		if at == null:
			continue
		var dx: float = float((at as Dictionary)["x"]) - float(pos["x"])
		var dy: float = float((at as Dictionary)["y"]) - float(pos["y"])
		var rem: float = float((at as Dictionary)["magnitude"]) - sqrt(dx * dx + dy * dy)
		if rem <= best_rem:
			continue
		if world.vision.detail(int(entity), float((at as Dictionary)["x"]), float((at as Dictionary)["y"])) == 0:
			continue
		best_rem = rem
		best_x = float((at as Dictionary)["x"])
		best_y = float((at as Dictionary)["y"])
	if best_rem <= 0.0:
		return
	var current: float = atan2(float(vel["dy"]), float(vel["dx"]))
	var toward: float = atan2(best_y - float(pos["y"]), best_x - float(pos["x"]))
	var delta: float = toward - current
	while delta > PI:
		delta -= PI * 2.0
	while delta < -PI:
		delta += PI * 2.0
	var angle: float = current + delta * LIGHT_BIAS * LIGHT_SENSITIVITY
	vel["dx"] = cos(angle) * speed
	vel["dy"] = sin(angle) * speed


static func register_module(world: Variant, _map: Variant) -> void:
	world.systems.register("shambler.think", "ai", 0, func(w: Variant) -> void:
		var rng: Variant = w.rng.stream("shambler")
		var field: Variant = w.field
		var survivors: Array = _gather_survivors(w)
		var audible: float = float(field.calibration["floor"]) / NOISE_SENSITIVITY
		var detectable: float = float(field.calibration["scentFloor"]) / SCENT_SENSITIVITY
		for entity in w.components.query(["position", "velocity", "shambler"]):
			var shambler_comp: Variant = w.components.get_component(int(entity), "shambler")
			var pos: Variant = w.components.get_component(int(entity), "position")
			var vel: Variant = w.components.get_component(int(entity), "velocity")
			if shambler_comp == null or pos == null or vel == null:
				continue
			var sd: Dictionary = shambler_comp as Dictionary
			var vd: Dictionary = vel as Dictionary
			var pd: Dictionary = pos as Dictionary
			var heard: bool = field.noise_at(float(pd["x"]), float(pd["y"])) >= audible
			var smelled: bool = field.scent_at(float(pd["x"]), float(pd["y"])) >= detectable
			if int(sd["ticksToGrab"]) > 0:
				sd["ticksToGrab"] = int(sd["ticksToGrab"]) - 1
			# GrabState pin omitted (needs GrabState component — R3)
			match int(sd["state"]):
				ShamblerState["Staggered"]:
					vd["dx"] = 0.0
					vd["dy"] = 0.0
					sd["ticksStaggered"] = int(sd["ticksStaggered"]) - 1
					if int(sd["ticksStaggered"]) <= 0:
						sd["state"] = ShamblerState["Wander"]
						sd["ticksToTurn"] = 0
				ShamblerState["Pursue"]:
					var target: Variant = _contact_target(survivors, pd, RELEASE_METRES)
					if target == null:
						sd["state"] = ShamblerState["Wander"]
						sd["ticksToTurn"] = int(rng.call("int_range", 20, 120))
					else:
						_chase(w, int(target), pd, vd, sd)
				ShamblerState["Seek"]:
					var caught: Variant = _contact_target(survivors, pd, CONTACT_METRES)
					if caught != null:
						sd["state"] = ShamblerState["Pursue"]
						sd["ticksCommitted"] = 0
						_chase(w, int(caught), pd, vd, sd)
					elif _steer_uphill(field, pd, vd, sd):
						sd["ticksCommitted"] = COMMIT_TICKS
					elif heard:
						sd["state"] = ShamblerState["Investigate"]
						sd["ticksMilling"] = MILL_TICKS
						sd["ticksToTurn"] = 0
					elif int(sd["ticksCommitted"]) - 1 > 0:
						sd["ticksCommitted"] = int(sd["ticksCommitted"]) - 1
					else:
						sd["ticksCommitted"] = 0
						sd["state"] = ShamblerState["Investigate"]
						sd["ticksMilling"] = MILL_TICKS
						sd["ticksToTurn"] = 0
				ShamblerState["Investigate"]:
					sd["ticksMilling"] = int(sd["ticksMilling"]) - 1
					if int(sd["ticksMilling"]) <= 0:
						sd["state"] = ShamblerState["Wander"]
						sd["ticksToTurn"] = 0
					elif int(sd["ticksToTurn"]) <= 0:
						var angle: float = rng.call("float_range", 0.0, PI * 2.0)
						vd["dx"] = cos(angle) * float(sd["millSpeed"])
						vd["dy"] = sin(angle) * float(sd["millSpeed"])
						sd["ticksToTurn"] = int(rng.call("int_range", 10, 25))
					else:
						sd["ticksToTurn"] = int(sd["ticksToTurn"]) - 1
				_:
					var caught2: Variant = _contact_target(survivors, pd, CONTACT_METRES)
					if caught2 != null:
						sd["state"] = ShamblerState["Pursue"]
						_chase(w, int(caught2), pd, vd, sd)
					elif heard:
						sd["state"] = ShamblerState["Seek"]
						sd["ticksCommitted"] = COMMIT_TICKS
						_steer_uphill(field, pd, vd, sd)
					elif int(sd["ticksToTurn"]) <= 0:
						var angle2: float = rng.call("float_range", 0.0, PI * 2.0)
						vd["dx"] = cos(angle2) * float(sd["wanderSpeed"])
						vd["dy"] = sin(angle2) * float(sd["wanderSpeed"])
						sd["ticksToTurn"] = int(rng.call("int_range", 20, 120))
					else:
						sd["ticksToTurn"] = int(sd["ticksToTurn"]) - 1
					if smelled:
						_drift_upscent(field, pd, vd, sd)
					_lean_to_light(w, int(entity), pd, vd)
	)
