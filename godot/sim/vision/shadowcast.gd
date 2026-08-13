class_name SimShadowcast
extends RefCounted
## Recursive shadowcasting — geometry half of visibility.
## Port of src/sim/vision/shadowcast.ts — Albert Ford's symmetric variant.
## Determinism: integer slopes as {n,d} cross-multiplied, never floats.
## Symmetry: floor tile revealed only when centre inside wedge.

const SimTileMapRes = preload("res://sim/map/tilemap.gd")

enum Quadrant { North = 0, East = 1, South = 2, West = 3 }

class VisibleTiles extends RefCounted:
	var origin_x: int = 0
	var origin_y: int = 0
	var range_tiles: int = 0
	var size: int = 0
	var cells: PackedByteArray = PackedByteArray()
	var count: int = 0

	func reset(ox: int, oy: int, r: int) -> void:
		var s := r * 2 + 1
		if size != s:
			size = s
			cells = PackedByteArray()
			cells.resize(s * s)
		else:
			for i in cells.size():
				cells[i] = 0
		origin_x = ox
		origin_y = oy
		range_tiles = r
		count = 0

	func has_tile(tx: int, ty: int) -> bool:
		var dx := tx - origin_x + range_tiles
		var dy := ty - origin_y + range_tiles
		if dx < 0 or dy < 0 or dx >= size or dy >= size:
			return false
		return cells[dy * size + dx] == 1

	# Alias matching oracle naming (`has`).
	func has(tx: int, ty: int) -> bool:
		return has_tile(tx, ty)

	func mark(tx: int, ty: int) -> void:
		var dx := tx - origin_x + range_tiles
		var dy := ty - origin_y + range_tiles
		if dx < 0 or dy < 0 or dx >= size or dy >= size:
			return
		var i := dy * size + dx
		if cells[i] == 1:
			return
		cells[i] = 1
		count += 1


static func _trunc_div(a: int, b: int) -> int:
	# Math.trunc(a/b) without intermediate float drift.
	return int(float(a) / float(b))


static func floor_div(a: int, b: int) -> int:
	var q := _trunc_div(a, b)
	return q - 1 if q * b > a else q


static func ceil_div(a: int, b: int) -> int:
	var q := _trunc_div(a, b)
	return q + 1 if q * b < a else q


## Compute every tile with a sightline from (origin_x, origin_y) out to range_tiles.
## Results written into `out` (reused across recomputes). Own tile always visible.
static func shadowcast(map: Variant, origin_x: int, origin_y: int, range_tiles: int, out: VisibleTiles, eye: int = 0) -> VisibleTiles:
	out.reset(origin_x, origin_y, range_tiles)
	out.mark(origin_x, origin_y)
	var range_sq := range_tiles * range_tiles
	if eye != SimTileMapRes.Eye.Crouched and eye != SimTileMapRes.Eye.Standing:
		eye = SimTileMapRes.Eye.Standing

	for q in range(Quadrant.North, Quadrant.West + 1):
		var stack: Array[Dictionary] = [{"depth": 1, "start_n": -1, "start_d": 1, "end_n": 1, "end_d": 1}]
		while stack.size() > 0:
			var frame: Dictionary = stack.pop_back()
			var depth: int = int(frame["depth"])
			if depth > range_tiles:
				continue
			var start_n: int = int(frame["start_n"])
			var start_d: int = int(frame["start_d"])
			var end_n: int = int(frame["end_n"])
			var end_d: int = int(frame["end_d"])
			var min_col := floor_div(2 * depth * start_n + start_d, 2 * start_d)
			var max_col := ceil_div(2 * depth * end_n - end_d, 2 * end_d)
			var prev_blocking: Variant = null
			var cur_start_n := start_n
			var cur_start_d := start_d
			for column in range(min_col, max_col + 1):
				var tx: int
				var ty: int
				if q == Quadrant.North or q == Quadrant.South:
					tx = origin_x + column
				elif q == Quadrant.East:
					tx = origin_x + depth
				else:
					tx = origin_x - depth
				if q == Quadrant.East or q == Quadrant.West:
					ty = origin_y + column
				elif q == Quadrant.South:
					ty = origin_y + depth
				else:
					ty = origin_y - depth

				var blocking: bool = SimTileMapRes.blocks_sight(map, tx, ty, eye)
				var centre_inside: bool = column * cur_start_d >= depth * cur_start_n and column * end_d <= depth * end_n
				if blocking or centre_inside:
					if depth * depth + column * column <= range_sq:
						out.mark(tx, ty)
				if prev_blocking == true and not blocking:
					cur_start_n = 2 * column - 1
					cur_start_d = 2 * depth
				if prev_blocking == false and blocking:
					stack.push_back({"depth": depth + 1, "start_n": cur_start_n, "start_d": cur_start_d, "end_n": 2 * column - 1, "end_d": 2 * depth})
				prev_blocking = blocking
			if prev_blocking == false:
				stack.push_back({"depth": depth + 1, "start_n": cur_start_n, "start_d": cur_start_d, "end_n": end_n, "end_d": end_d})
	return out
