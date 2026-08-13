class_name SimVisibility
extends RefCounted
## Who can see what — observer half of visibility primitive.
## Port of src/sim/vision/visibility.ts.
## One shadowcast per observer per tick at most, cached by tile+range+eye+generation.
## Geometry (shadowcast) + arcs (focal/peripheral dot product) + range check.

const SimTileMapRes = preload("res://sim/map/tilemap.gd")
const Shadowcast = preload("res://sim/vision/shadowcast.gd")
const Clock = preload("res://sim/time/clock.gd")

enum Detail { Unseen = 0, Peripheral = 1, Focal = 2 }

var _views: Dictionary = {}
var recomputes: int = 0

## Daylight eyes — 48 m, 60° focal, 190° total FoV. Port of DAYLIGHT_EYES.
static func daylight_eyes() -> Dictionary:
	return {"range_metres": 48.0, "focal_half_angle": PI / 6.0, "peripheral_half_angle": 95.0 * PI / 180.0, "eye": 0}

## Shambler eyes — 12 m, mostly peripheral. Port of SHAMBLER_EYES.
static func shambler_eyes() -> Dictionary:
	return {"range_metres": 12.0, "focal_half_angle": PI / 8.0, "peripheral_half_angle": 110.0 * PI / 180.0, "eye": 0}


func _map_generation(world: Variant) -> int:
	if world is Dictionary:
		return int(world.get("map_generation", 0))
	if world != null and "map_generation" in world:
		return int(world.map_generation)
	return 0


func _light_index(world: Variant) -> Variant:
	if world is Dictionary:
		return world.get("light")
	if world != null and "light" in world:
		return world.light
	return null


func refresh(world: Variant, map: Variant) -> void:
	var seen: Dictionary = {}
	var gen := _map_generation(world)
	for entity in world.components.query(["position", "observer"]):
		var pos: Variant = world.components.get_component(entity, "position")
		var obs: Variant = world.components.get_component(entity, "observer")
		if pos == null or obs == null:
			continue
		var facing_rad: float = 0.0
		var facing_c: Variant = world.components.get_component(entity, "facing")
		if facing_c != null:
			facing_rad = float((facing_c as Dictionary)["radians"])

		var tile_x: int = floori(float((pos as Dictionary)["x"]) / float(SimTileMapRes.TILE_METRES))
		var tile_y: int = floori(float((pos as Dictionary)["y"]) / float(SimTileMapRes.TILE_METRES))
		var metres: float = _sight_metres(world, obs as Dictionary, float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]))
		var range_tiles: int = SimTileMapRes.tile_range(metres)
		var eye: int = int((obs as Dictionary)["eye"])
		var key: String = "%d,%d,%d,%d,%d" % [tile_x, tile_y, range_tiles, eye, gen]

		var view: Variant = _views.get(entity)
		if view == null:
			view = {
				"key": "",
				"tiles": Shadowcast.VisibleTiles.new(),
				"x": 0.0, "y": 0.0,
				"facing_x": 1.0, "facing_y": 0.0,
				"cos_focal": 1.0, "cos_peripheral": 1.0,
				"range_squared": 0.0,
			}
			_views[entity] = view

		if String((view as Dictionary)["key"]) != key:
			Shadowcast.shadowcast(map, tile_x, tile_y, range_tiles, (view as Dictionary)["tiles"] as Shadowcast.VisibleTiles, eye)
			(view as Dictionary)["key"] = key
			recomputes += 1

		(view as Dictionary)["x"] = float((pos as Dictionary)["x"])
		(view as Dictionary)["y"] = float((pos as Dictionary)["y"])
		(view as Dictionary)["facing_x"] = cos(facing_rad)
		(view as Dictionary)["facing_y"] = sin(facing_rad)
		(view as Dictionary)["cos_focal"] = cos(float((obs as Dictionary)["focal_half_angle"]))
		(view as Dictionary)["cos_peripheral"] = cos(float((obs as Dictionary)["peripheral_half_angle"]))
		(view as Dictionary)["range_squared"] = metres * metres
		seen[entity] = true

	for entity in _views.keys():
		if not seen.has(entity):
			_views.erase(entity)


func _sight_metres(world: Variant, observer: Dictionary, x: float, y: float) -> float:
	var tick: int = 0
	if world is Dictionary:
		tick = int(world.get("tick", 0))
	elif world != null and "tick" in world:
		tick = int(world.tick)
	var ambient: float = float(observer["range_metres"]) * Clock.ambient_light_at(tick)
	var lit: float = 0.0
	var light_idx: Variant = _light_index(world)
	if light_idx != null:
		lit = light_idx.lit_metres(x, y)
	return min(float(observer["range_metres"]), max(ambient, lit))


func tiles_for(observer: int) -> Variant:
	var v: Variant = _views.get(observer)
	if v == null:
		return null
	return (v as Dictionary)["tiles"]


func detail(observer: int, x: float, y: float) -> int:
	var view: Variant = _views.get(observer)
	if view == null:
		return Detail.Unseen
	var tiles: Variant = (view as Dictionary)["tiles"]
	var has: bool = (tiles as Shadowcast.VisibleTiles).has_tile(floori(x / float(SimTileMapRes.TILE_METRES)), floori(y / float(SimTileMapRes.TILE_METRES)))
	if not has:
		return Detail.Unseen
	var dx: float = x - float((view as Dictionary)["x"])
	var dy: float = y - float((view as Dictionary)["y"])
	var d2: float = dx * dx + dy * dy
	if d2 > float((view as Dictionary)["range_squared"]):
		return Detail.Unseen
	if d2 == 0.0:
		return Detail.Focal
	var cosine: float = (dx * float((view as Dictionary)["facing_x"]) + dy * float((view as Dictionary)["facing_y"])) / sqrt(d2)
	if cosine >= float((view as Dictionary)["cos_focal"]):
		return Detail.Focal
	if cosine >= float((view as Dictionary)["cos_peripheral"]):
		return Detail.Peripheral
	return Detail.Unseen


func can_see(observer: int, x: float, y: float) -> bool:
	return detail(observer, x, y) != Detail.Unseen


func observer_count() -> int:
	return _views.size()
