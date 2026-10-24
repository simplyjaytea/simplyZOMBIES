class_name SimLight
extends RefCounted
## Light channel — shadowcast from emitter, max-not-sum, wall absolute.
## Port of src/sim/vision/light.ts

const SimTileMapRes = preload("res://sim/map/tilemap.gd")
const Shadowcast = preload("res://sim/vision/shadowcast.gd")
const Clock = preload("res://sim/time/clock.gd")

## Emitter table — metres of reach, straight off docs/03.
const LIGHT_TABLE := {
	"candle": 3,
	"campfire": 20,
	"lamp": 35,
	"floodlight": 90,
}

var _casts: Dictionary = {}
var _ordered_sources: Array[int] = []
var recomputes: int = 0


func _map_generation(world: Variant) -> int:
	if world is Dictionary:
		return int(world.get("map_generation", 0))
	if world != null and "map_generation" in world:
		return int(world.map_generation)
	return 0


func refresh(world: Variant, map: Variant) -> void:
	var seen: Dictionary = {}
	_ordered_sources.clear()
	var gen := _map_generation(world)
	# The visibility cache's rule (visibility.gd's `refresh`): a cast made at an older generation
	# stands when the world logged that nothing changed inside the cast's own square.
	var logs_changes: bool = world is Object and (world as Object).has_method("map_unchanged_within")
	for entity in world.components.query(["position", "light_source"]):
		var pos: Variant = world.components.get_component(entity, "position")
		var src: Variant = world.components.get_component(entity, "light_source")
		if pos == null or src == null:
			continue
		var mag: float = float((src as Dictionary)["magnitude"])
		if not (mag > 0.0):
			continue
		var tile_x: int = floori(float((pos as Dictionary)["x"]) / float(SimTileMapRes.TILE_METRES))
		var tile_y: int = floori(float((pos as Dictionary)["y"]) / float(SimTileMapRes.TILE_METRES))
		var range_tiles: int = SimTileMapRes.tile_range(mag)
		var c: Variant = _casts.get(entity)
		if c == null:
			# The cache key as four ints (the eye is always Standing here), not a formatted String:
			# the same reason visibility.gd's views stopped formatting one per observer per tick.
			c = {"tile_x": -1, "tile_y": -1, "range_tiles": -1, "gen": -1, "tiles": Shadowcast.VisibleTiles.new(), "x": 0.0, "y": 0.0, "magnitude": 0.0}
			_casts[entity] = c
		var cd: Dictionary = c as Dictionary
		var same: bool = int(cd["tile_x"]) == tile_x and int(cd["tile_y"]) == tile_y and int(cd["range_tiles"]) == range_tiles
		if same and int(cd["gen"]) != gen:
			var square := Rect2i(tile_x - range_tiles, tile_y - range_tiles, range_tiles * 2 + 1, range_tiles * 2 + 1)
			if logs_changes and world.map_unchanged_within(int(cd["gen"]), square):
				cd["gen"] = gen
			else:
				same = false
		if not same:
			Shadowcast.shadowcast(map, tile_x, tile_y, range_tiles, cd["tiles"] as Shadowcast.VisibleTiles, SimTileMapRes.Eye.Standing)
			cd["tile_x"] = tile_x
			cd["tile_y"] = tile_y
			cd["range_tiles"] = range_tiles
			cd["gen"] = gen
			recomputes += 1
		(c as Dictionary)["x"] = float((pos as Dictionary)["x"])
		(c as Dictionary)["y"] = float((pos as Dictionary)["y"])
		(c as Dictionary)["magnitude"] = mag
		seen[entity] = true
		_ordered_sources.append(entity)
	for entity in _casts.keys():
		if not seen.has(entity):
			_casts.erase(entity)


## How much light reaches (x,y) in metres of usable reach. Max across sources, never sum.
func lit_metres(x: float, y: float) -> float:
	var tx: int = floori(x / float(SimTileMapRes.TILE_METRES))
	var ty: int = floori(y / float(SimTileMapRes.TILE_METRES))
	var best: float = 0.0
	for entity in _ordered_sources:
		var c: Variant = _casts.get(entity)
		if c == null:
			continue
		var tiles: Shadowcast.VisibleTiles = (c as Dictionary)["tiles"]
		if not tiles.has_tile(tx, ty):
			continue
		var rem: float = float((c as Dictionary)["magnitude"]) - sqrt(pow(x - float((c as Dictionary)["x"]), 2.0) + pow(y - float((c as Dictionary)["y"]), 2.0))
		if rem > best:
			best = rem
	return best

# CamelCase alias for oracle naming.
func litMetres(x: float, y: float) -> float:
	return lit_metres(x, y)


func tiles_for(source: int) -> Variant:
	var c: Variant = _casts.get(source)
	if c == null:
		return null
	return (c as Dictionary)["tiles"]

func tilesFor(source: int) -> Variant:
	return tiles_for(source)


func sources_list() -> Array[int]:
	return _ordered_sources

# Oracle getter alias `sources`.
func sources() -> Array[int]:
	return _ordered_sources


func source_count() -> int:
	return _ordered_sources.size()

func sourceCount() -> int:
	return _ordered_sources.size()

# Property alias for `sourceCount` getter access.
var sourceCount_get: int:
	get:
		return _ordered_sources.size()

var sources_get: Array[int]:
	get:
		return _ordered_sources


func source_at(entity: int) -> Variant:
	var c: Variant = _casts.get(entity)
	if c == null:
		return null
	return {"x": float((c as Dictionary)["x"]), "y": float((c as Dictionary)["y"]), "magnitude": float((c as Dictionary)["magnitude"])}

func sourceAt(entity: int) -> Variant:
	return source_at(entity)


## The least a survivor sees after dark, with no light anywhere (docs/23, "The night's reach on
## screen"): a person who can see at all can see the tile at their feet and the one past it. Only a
## survivor's eyes carry `night_eyes`; a zombie or a raider does not get the floor. Read here and by
## visibility.gd's `_sight_metres`, so the drawn disc (LightLook.eye_disc_metres) and the sim agree.
const NIGHT_EYES_FLOOR_M: float = 3.5

## How far observer can see from (x,y) — min(eyes, max(ambient, lit, night floor)).
static func sight_metres(world: Variant, observer: Dictionary, x: float, y: float) -> float:
	var tick: int = 0
	if world is Dictionary:
		tick = int(world.get("tick", 0))
	elif world != null and "tick" in world:
		tick = int(world.tick)
	var ambient: float = float(observer["range_metres"]) * Clock.ambient_light_at(tick)
	var lit: float = 0.0
	var light_idx: Variant = null
	if world is Dictionary:
		light_idx = world.get("light")
	elif world != null and "light" in world:
		light_idx = world.light
	if light_idx != null:
		lit = light_idx.lit_metres(x, y)
	var floor_m: float = NIGHT_EYES_FLOOR_M if bool(observer.get("night_eyes", false)) else 0.0
	return min(float(observer["range_metres"]), max(ambient, lit, floor_m))

static func sightMetres(world: Variant, observer: Dictionary, x: float, y: float) -> float:
	return sight_metres(world, observer, x, y)
