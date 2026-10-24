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

# The spill round a beam throws at its feet: a tile this close to the source is lit whatever way the
# beam points, so a torch lights the ground under the holder's hand and a zombie at arm's length.
const SPILL_M: float = 1.5

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
			c = {"tile_x": -1, "tile_y": -1, "range_tiles": -1, "gen": -1, "tiles": Shadowcast.VisibleTiles.new(), "x": 0.0, "y": 0.0, "magnitude": 0.0, "beam": 0.0, "facing": 0.0}
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
		# The beam is the carrier's to aim: its facing is read here, every tick, and never recasts the
		# round shadowcast above, so turning moves the wedge without costing a cast.
		(c as Dictionary)["beam"] = float((src as Dictionary).get("beam", 0.0))
		(c as Dictionary)["facing"] = _facing_of(world, entity)
		seen[entity] = true
		_ordered_sources.append(entity)
	for entity in _casts.keys():
		if not seen.has(entity):
			_casts.erase(entity)


## Whether `source`'s light lands on tile (tx, ty). A round light: the shadowcast has the tile. A
## beam: the same, and the tile is inside the wedge (its bearing from the source within the beam's
## half-angle of the carrier's facing) or inside the spill round the source. Facing turns the wedge
## only; the cast it clips is the round one.
func lights_tile(source: int, tx: int, ty: int) -> bool:
	var c: Variant = _casts.get(source)
	if c == null:
		return false
	var cd: Dictionary = c as Dictionary
	var tiles: Shadowcast.VisibleTiles = cd["tiles"]
	if not tiles.has_tile(tx, ty):
		return false
	var beam: float = float(cd["beam"])
	if beam <= 0.0:
		return true
	var dx: float = (float(tx) + 0.5) * float(SimTileMapRes.TILE_METRES) - float(cd["x"])
	var dy: float = (float(ty) + 0.5) * float(SimTileMapRes.TILE_METRES) - float(cd["y"])
	if dx * dx + dy * dy <= SPILL_M * SPILL_M:
		return true
	var off: float = wrapf(atan2(dy, dx) - float(cd["facing"]), -PI, PI)
	return absf(off) <= beam


static func _facing_of(world: Variant, entity: int) -> float:
	var facing: Variant = world.components.get_component(entity, "facing")
	if facing is Dictionary:
		return float((facing as Dictionary).get("radians", 0.0))
	return 0.0


## How much light reaches (x,y) in metres of usable reach. Max across sources, never sum.
func lit_metres(x: float, y: float) -> float:
	var tx: int = floori(x / float(SimTileMapRes.TILE_METRES))
	var ty: int = floori(y / float(SimTileMapRes.TILE_METRES))
	var best: float = 0.0
	for entity in _ordered_sources:
		var c: Variant = _casts.get(entity)
		if c == null:
			continue
		if not lights_tile(int(entity), tx, ty):
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
	return {"x": float((c as Dictionary)["x"]), "y": float((c as Dictionary)["y"]), "magnitude": float((c as Dictionary)["magnitude"]), "beam": float((c as Dictionary)["beam"]), "facing": float((c as Dictionary)["facing"])}

func sourceAt(entity: int) -> Variant:
	return source_at(entity)


## How far observer can see from (x,y) — min(eyes, max(ambient, lit)).
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
	return min(float(observer["range_metres"]), max(ambient, lit))

static func sightMetres(world: Variant, observer: Dictionary, x: float, y: float) -> float:
	return sight_metres(world, observer, x, y)
