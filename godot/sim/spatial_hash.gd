class_name SimSpatialHash
extends RefCounted

const CELL_METRES: int = 2

var cols: int
var rows: int
var _starts: PackedInt32Array
var _cursor: PackedInt32Array
var _ids: PackedInt32Array
var _xs: PackedFloat64Array
var _ys: PackedFloat64Array
var _indexed: int = 0


func _init(cols_: int, rows_: int) -> void:
	cols = maxi(1, cols_)
	rows = maxi(1, rows_)
	var cells: int = cols * rows
	_starts = PackedInt32Array()
	_starts.resize(cells + 1)
	_cursor = PackedInt32Array()
	_cursor.resize(cells)
	_ids = PackedInt32Array()
	_xs = PackedFloat64Array()
	_ys = PackedFloat64Array()
	_indexed = 0


static func for_map(map: Dictionary) -> Variant:
	var w: int = int(map["w"])
	var h: int = int(map["h"])
	var c: int = ceili(float(w) / float(CELL_METRES))
	var r: int = ceili(float(h) / float(CELL_METRES))
	return load("res://sim/spatial_hash.gd").new(c, r)


static func for_extent(width_metres: float, height_metres: float) -> Variant:
	var c: int = ceili(width_metres / float(CELL_METRES))
	var r: int = ceili(height_metres / float(CELL_METRES))
	return load("res://sim/spatial_hash.gd").new(c, r)


static func empty() -> Variant:
	return load("res://sim/spatial_hash.gd").new(1, 1)


func _cell_of(x: float, y: float) -> int:
	var cx: int = _clamp_col(floori(x / float(CELL_METRES)))
	var cy: int = _clamp_row(floori(y / float(CELL_METRES)))
	return cy * cols + cx


func _clamp_col(cx: int) -> int:
	if cx < 0:
		return 0
	if cx > cols - 1:
		return cols - 1
	return cx


func _clamp_row(cy: int) -> int:
	if cy < 0:
		return 0
	if cy > rows - 1:
		return rows - 1
	return cy


func rebuild(world: Variant) -> void:
	var cells: int = cols * rows
	for i: int in range(cells + 1):
		_starts[i] = 0
	var indexed: int = 0
	var entities: Array[int] = world.components.query(["Position"])
	for entity: int in entities:
		var pos: Variant = world.components.get_component(entity, "Position")
		if pos == null:
			continue
		var px: float = float(pos["x"])
		var py: float = float(pos["y"])
		var slot: int = _cell_of(px, py) + 1
		_starts[slot] = _starts[slot] + 1
		indexed += 1
	_indexed = indexed
	if indexed > _ids.size():
		var capacity: int = 64
		if indexed > 1:
			capacity = maxi(64, 1 << (32 - _clz32(indexed - 1)))
		_ids.resize(capacity)
		_xs.resize(capacity)
		_ys.resize(capacity)
	for i: int in range(cells):
		_starts[i + 1] = _starts[i + 1] + _starts[i]
	for i: int in range(cells):
		_cursor[i] = _starts[i]
	for entity: int in entities:
		var pos2: Variant = world.components.get_component(entity, "Position")
		if pos2 == null:
			continue
		var px2: float = float(pos2["x"])
		var py2: float = float(pos2["y"])
		var cell: int = _cell_of(px2, py2)
		var at: int = _cursor[cell]
		_cursor[cell] = at + 1
		_ids[at] = entity
		_xs[at] = px2
		_ys[at] = py2


func query_radius(x: float, y: float, radius_metres: float, out: Array[int] = []) -> Array[int]:
	out.clear()
	if not (radius_metres > 0.0):
		return out
	var min_x: int = _clamp_col(floori((x - radius_metres) / float(CELL_METRES)))
	var max_x: int = _clamp_col(floori((x + radius_metres) / float(CELL_METRES)))
	var min_y: int = _clamp_row(floori((y - radius_metres) / float(CELL_METRES)))
	var max_y: int = _clamp_row(floori((y + radius_metres) / float(CELL_METRES)))
	var limit: float = radius_metres * radius_metres
	for cy: int in range(min_y, max_y + 1):
		var row: int = cy * cols
		for cx: int in range(min_x, max_x + 1):
			var cell: int = row + cx
			var end: int = _starts[cell + 1]
			for i: int in range(_starts[cell], end):
				var dx: float = _xs[i] - x
				var dy: float = _ys[i] - y
				if dx * dx + dy * dy <= limit:
					out.append(_ids[i])
	out.sort()
	return out


func get_size() -> int:
	return _indexed


func get_cell_count() -> int:
	return cols * rows


static func _clz32(v: int) -> int:
	var n: int = 0
	var x: int = v & 0xffffffff
	if x == 0:
		return 32
	if (x & 0xffff0000) == 0:
		n += 16
		x <<= 16
	if (x & 0xff000000) == 0:
		n += 8
		x <<= 8
	if (x & 0xf0000000) == 0:
		n += 4
		x <<= 4
	if (x & 0xc0000000) == 0:
		n += 2
		x <<= 2
	if (x & 0x80000000) == 0:
		n += 1
	return n
