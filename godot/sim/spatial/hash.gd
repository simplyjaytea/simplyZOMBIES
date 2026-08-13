class_name SimSpatialHash
extends RefCounted

const SimTileMapRes = preload("res://sim/map/tilemap.gd")

const CELL_METRES: float = 2.0

var cols: int
var rows: int
var _starts: PackedInt32Array
var _cursor: PackedInt32Array
var _ids: PackedInt32Array
var _xs: PackedFloat64Array
var _ys: PackedFloat64Array
var _indexed: int = 0


func _init(c: int, r: int) -> void:
	cols = maxi(1, c)
	rows = maxi(1, r)
	var cells := cols * rows
	_starts = PackedInt32Array()
	_starts.resize(cells + 1)
	_cursor = PackedInt32Array()
	_cursor.resize(cells)
	_ids = PackedInt32Array()
	_xs = PackedFloat64Array()
	_ys = PackedFloat64Array()


static func for_map(map: Variant) -> Variant:
	var scr: GDScript = load("res://sim/spatial/hash.gd") as GDScript
	return scr.new(
		ceili(float(map.w * SimTileMapRes.TILE_METRES) / CELL_METRES),
		ceili(float(map.h * SimTileMapRes.TILE_METRES) / CELL_METRES)
	)


static func for_extent(width_metres: float, height_metres: float) -> Variant:
	var scr: GDScript = load("res://sim/spatial/hash.gd") as GDScript
	return scr.new(
		ceili(width_metres / CELL_METRES),
		ceili(height_metres / CELL_METRES)
	)


static func empty_hash() -> Variant:
	var scr: GDScript = load("res://sim/spatial/hash.gd") as GDScript
	return scr.new(1, 1)


func _cell_of(x: float, y: float) -> int:
	var cx := clampi(floori(x / CELL_METRES), 0, cols - 1)
	var cy := clampi(floori(y / CELL_METRES), 0, rows - 1)
	return cy * cols + cx


func rebuild(world: Variant) -> void:
	var cells := cols * rows
	for i in cells + 1:
		_starts[i] = 0
	var indexed := 0
	for entity in world.components.query(["position"]):
		var pos: Variant = world.components.get_component(entity, "position")
		if pos == null:
			continue
		var slot := _cell_of(float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"])) + 1
		_starts[slot] = _starts[slot] + 1
		indexed += 1
	_indexed = indexed
	if indexed > _ids.size():
		var cap := maxi(64, 1 << (32 - _clz32(indexed - 1)))
		_ids.resize(cap)
		_xs.resize(cap)
		_ys.resize(cap)
	for i in cells:
		_starts[i + 1] = _starts[i + 1] + _starts[i]
	for i in cells:
		_cursor[i] = _starts[i]
	for entity in world.components.query(["position"]):
		var pos: Variant = world.components.get_component(entity, "position")
		if pos == null:
			continue
		var cell := _cell_of(float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]))
		var at: int = _cursor[cell]
		_cursor[cell] = at + 1
		_ids[at] = entity
		_xs[at] = float((pos as Dictionary)["x"])
		_ys[at] = float((pos as Dictionary)["y"])


func query_radius(x: float, y: float, radius_metres: float, out: Array = []) -> Array:
	out.clear()
	if !(radius_metres > 0.0):
		return out
	var min_x := clampi(floori((x - radius_metres) / CELL_METRES), 0, cols - 1)
	var max_x := clampi(floori((x + radius_metres) / CELL_METRES), 0, cols - 1)
	var min_y := clampi(floori((y - radius_metres) / CELL_METRES), 0, rows - 1)
	var max_y := clampi(floori((y + radius_metres) / CELL_METRES), 0, rows - 1)
	var limit := radius_metres * radius_metres
	for cy in range(min_y, max_y + 1):
		var row := cy * cols
		for cx in range(min_x, max_x + 1):
			var cell := row + cx
			var end: int = _starts[cell + 1]
			var start: int = _starts[cell]
			for i in range(start, end):
				var dx := _xs[i] - x
				var dy := _ys[i] - y
				if dx * dx + dy * dy <= limit:
					out.append(int(_ids[i]))
	out.sort()
	return out


func size_count() -> int:
	return _indexed


func cell_count() -> int:
	return cols * rows


static func _clz32(v: int) -> int:
	if v == 0:
		return 32
	var n := 0
	if (v & 0xFFFF0000) == 0:
		n += 16
		v <<= 16
	if (v & 0xFF000000) == 0:
		n += 8
		v <<= 8
	if (v & 0xF0000000) == 0:
		n += 4
		v <<= 4
	if (v & 0xC0000000) == 0:
		n += 2
		v <<= 2
	if (v & 0x80000000) == 0:
		n += 1
	return n
