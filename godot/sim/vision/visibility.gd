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

## How far a `lit_target` observer (a zombie) walks from where it last cast before it casts
## again, in tiles (Chebyshev). See `refresh`.
const ZOMBIE_RECAST_TILES: int = 2

## Daylight eyes — 48 m, 60° focal, 190° total FoV. Port of DAYLIGHT_EYES.
static func daylight_eyes() -> Dictionary:
	return {"range_metres": 48.0, "focal_half_angle": PI / 6.0, "peripheral_half_angle": 95.0 * PI / 180.0, "eye": 0}

## Shambler eyes — 12 m, mostly peripheral. Port of SHAMBLER_EYES, plus `lit_target`: a
## zombie's sight samples the light at the thing it is looking at, not at its own feet. The
## oracle's rule (`_sight_metres`: min(eyes, max(ambient, lit at the observer))) left every
## zombie 0.48 m of sight after dark and blind to a survivor under a floodlight -- the screamer's
## purpose inverted. The player's eyes keep the oracle's rule: `tiles_for(player)` is what cuts
## roofs out and pools the light wash, and a 48 m shadowcast at night would open every roof in
## sight. `check_m2_sight.gd` NIGHT-LIT pins both halves.
static func shambler_eyes() -> Dictionary:
	return {"range_metres": 12.0, "focal_half_angle": PI / 8.0, "peripheral_half_angle": 110.0 * PI / 180.0, "eye": 0, "lit_target": true}


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
		var lit_target: bool = bool((obs as Dictionary).get("lit_target", false))
		# A lit-target observer's ambient reach is ambient alone: standing in a light does not
		# let the dead see further into the dark (the light at the *target* is what `detail`
		# asks), and `lit_metres` walks every source in the district -- eighty observers asking
		# it every tick was the cost the eyes slice's driver found.
		var metres: float = _ambient_metres(world, obs as Dictionary) if lit_target else _sight_metres(world, obs as Dictionary, float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]))
		# A lit-target observer casts at its eyes' full reach: the geometry is walls, and whether
		# a tile inside it is *seen* is decided per target in `detail`, by distance or by light.
		var cast_metres: float = float((obs as Dictionary)["range_metres"]) if lit_target else metres
		var range_tiles: int = SimTileMapRes.tile_range(cast_metres)
		var eye: int = int((obs as Dictionary)["eye"])

		var view: Variant = _views.get(entity)
		if view == null:
			view = {
				# The cache key, as five ints rather than one formatted string: with eighty
				# observers this comparison runs eighty times a tick, and formatting a String
				# for each was a measurable share of a 256-tile step (the eyes slice's driver).
				"tile_x": -1, "tile_y": -1, "range_tiles": -1, "eye": -1, "gen": -1,
				"tiles": Shadowcast.VisibleTiles.new(),
				"x": 0.0, "y": 0.0,
				"facing_x": 1.0, "facing_y": 0.0,
				"cos_focal": 1.0, "cos_peripheral": 1.0,
				"range_squared": 0.0,
				"full_squared": 0.0, "lit_target": false, "light": null,
			}
			_views[entity] = view

		var vd: Dictionary = view as Dictionary
		# The dead recast only once they have walked ZOMBIE_RECAST_TILES from where they last
		# cast, on the same map and range: a 12-tile cast is ~1.5 ms of GDScript and eighty
		# bodies crossing tiles cast ~2.6 times a tick, a third of a 256-tile step (the eyes
		# slice's driver). Walls a tile or two off their true offset are an approximation the
		# dead can afford; a person's cast moves with their tile as it always has.
		var moved: int = maxi(absi(tile_x - int(vd["tile_x"])), absi(tile_y - int(vd["tile_y"])))
		var stale: bool = int(vd["range_tiles"]) != range_tiles or int(vd["eye"]) != eye or int(vd["gen"]) != gen
		if stale or (moved >= ZOMBIE_RECAST_TILES if lit_target else moved > 0):
			Shadowcast.shadowcast(map, tile_x, tile_y, range_tiles, vd["tiles"] as Shadowcast.VisibleTiles, eye)
			vd["tile_x"] = tile_x
			vd["tile_y"] = tile_y
			vd["range_tiles"] = range_tiles
			vd["eye"] = eye
			vd["gen"] = gen
			recomputes += 1

		(view as Dictionary)["x"] = float((pos as Dictionary)["x"])
		(view as Dictionary)["y"] = float((pos as Dictionary)["y"])
		(view as Dictionary)["facing_x"] = cos(facing_rad)
		(view as Dictionary)["facing_y"] = sin(facing_rad)
		(view as Dictionary)["cos_focal"] = cos(float((obs as Dictionary)["focal_half_angle"]))
		(view as Dictionary)["cos_peripheral"] = cos(float((obs as Dictionary)["peripheral_half_angle"]))
		(view as Dictionary)["range_squared"] = metres * metres
		(view as Dictionary)["full_squared"] = cast_metres * cast_metres
		(view as Dictionary)["lit_target"] = lit_target
		(view as Dictionary)["light"] = _light_index(world) if lit_target else null
		seen[entity] = true

	for entity in _views.keys():
		if not seen.has(entity):
			_views.erase(entity)


func _tick_of(world: Variant) -> int:
	if world is Dictionary:
		return int(world.get("tick", 0))
	if world != null and "tick" in world:
		return int(world.tick)
	return 0


func _ambient_metres(world: Variant, observer: Dictionary) -> float:
	return float(observer["range_metres"]) * Clock.ambient_light_at(_tick_of(world))


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
	if d2 > float((view as Dictionary)["range_squared"]) and not _lit_in_reach(view as Dictionary, d2, x, y):
		return Detail.Unseen
	if d2 == 0.0:
		return Detail.Focal
	var cosine: float = (dx * float((view as Dictionary)["facing_x"]) + dy * float((view as Dictionary)["facing_y"])) / sqrt(d2)
	if cosine >= float((view as Dictionary)["cos_focal"]):
		return Detail.Focal
	if cosine >= float((view as Dictionary)["cos_peripheral"]):
		return Detail.Peripheral
	return Detail.Unseen


# The lit-target half of `detail`: beyond the ambient reach, a `lit_target` observer still sees
# a target whose own tile is lit, out to its eyes' full range. The shadowcast (walls) has
# already been asked by the caller; this is only the range question.
func _lit_in_reach(view: Dictionary, d2: float, x: float, y: float) -> bool:
	if not bool(view.get("lit_target", false)):
		return false
	if d2 > float(view.get("full_squared", 0.0)):
		return false
	var light_idx: Variant = view.get("light")
	if light_idx == null:
		return false
	return float(light_idx.lit_metres(x, y)) > 0.0


func can_see(observer: int, x: float, y: float) -> bool:
	return detail(observer, x, y) != Detail.Unseen


func observer_count() -> int:
	return _views.size()


## Geometry only — walls and range, with no facing arc. What a bullet is stopped by, which is not
## the same question as what an observer is looking at: `detail` narrows by focal and peripheral
## cones because attention is directional, and a shot leaving a barrel is not. `ranged.gd` and,
## through it, `npc_combat.gd` ask this one; anything about *noticing* something asks `detail`.
## Unseen for an observer with no view at all — callers that must stay permissive for a fixture
## without eyes check `tiles_for` first, which is the one thing that distinguishes "no eyes" from
## "eyes, and a wall".
func line_of_sight(observer: int, x: float, y: float) -> bool:
	var view: Variant = _views.get(observer)
	if view == null:
		return false
	var tiles: Variant = (view as Dictionary)["tiles"]
	if not (tiles as Shadowcast.VisibleTiles).has_tile(floori(x / float(SimTileMapRes.TILE_METRES)), floori(y / float(SimTileMapRes.TILE_METRES))):
		return false
	var dx: float = x - float((view as Dictionary)["x"])
	var dy: float = y - float((view as Dictionary)["y"])
	return dx * dx + dy * dy <= float((view as Dictionary)["range_squared"])
