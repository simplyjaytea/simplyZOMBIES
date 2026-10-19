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
			cells.fill(0)
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
	# `SimTileMap.blocks_sight`, read straight off the map's arrays: the same answer per tile --
	# out of bounds is a Wall, an overlay outranks the class, Low blocks only a crouched eye -- with
	# the four calls per tile it cost folded into this loop. A 48-tile cast visits about seven
	# thousand tiles, and the calls were most of what a recast cost (A3's third slice;
	# `check_m2_tick.gd` CAST holds this to `blocks_sight` tile for tile).
	var mw: int = int(map.w)
	var mh: int = int(map.h)
	var tiles: PackedByteArray = map.tiles
	var overlays: Dictionary = map.overlays if map.overlays is Dictionary else {}
	var has_overlays: bool = not overlays.is_empty()
	var crouched: bool = eye == SimTileMapRes.Eye.Crouched
	var opacity: Array[int] = SimTileMapRes.OPACITY
	var cells: PackedByteArray = out.cells
	var size: int = out.size
	var base_x: int = range_tiles - origin_x
	var base_y: int = range_tiles - origin_y
	# A frame is five ints [depth, start_n, start_d, end_n, end_d], pushed and popped in the order
	# the Dictionary frames were.
	for q in range(Quadrant.North, Quadrant.West + 1):
		var stack: Array[int] = [1, -1, 1, 1, 1]
		while stack.size() > 0:
			var end_d: int = stack.pop_back()
			var end_n: int = stack.pop_back()
			var start_d: int = stack.pop_back()
			var start_n: int = stack.pop_back()
			var depth: int = stack.pop_back()
			if depth > range_tiles:
				continue
			# floor_div / ceil_div, inlined: the same truncate-then-correct on the same ints.
			var fa: int = 2 * depth * start_n + start_d
			var fb: int = 2 * start_d
			var min_col: int = int(float(fa) / float(fb))
			if min_col * fb > fa:
				min_col -= 1
			var ca: int = 2 * depth * end_n - end_d
			var cb: int = 2 * end_d
			var max_col: int = int(float(ca) / float(cb))
			if max_col * cb < ca:
				max_col += 1
			# 0 = no tile yet, 1 = the last tile was open, 2 = it was blocking.
			var prev: int = 0
			var cur_start_n := start_n
			var cur_start_d := start_d
			var depth_sq: int = depth * depth
			# The row, resolved once rather than per tile: North and South walk x along a fixed
			# y, East and West walk y along a fixed x. `fixed` is the row's coordinate on the
			# axis that does not move, `along` the moving one's at column 0.
			var ns: bool = q == Quadrant.North or q == Quadrant.South
			var fixed: int
			if q == Quadrant.North:
				fixed = origin_y - depth
			elif q == Quadrant.South:
				fixed = origin_y + depth
			elif q == Quadrant.East:
				fixed = origin_x + depth
			else:
				fixed = origin_x - depth
			var along: int = origin_x if ns else origin_y
			var fixed_in: bool = fixed >= 0 and fixed < (mh if ns else mw)
			var along_lim: int = mw if ns else mh
			var idx_base: int = fixed * mw + along if ns else along * mw + fixed
			var idx_step: int = 1 if ns else mw
			var cell_base: int = (fixed + base_y) * size + (along + base_x) if ns else (along + base_y) * size + (fixed + base_x)
			var cell_step: int = 1 if ns else size
			for column in range(min_col, max_col + 1):
				var a: int = along + column
				var blocking: bool
				if not fixed_in or a < 0 or a >= along_lim:
					blocking = true
				else:
					var idx: int = idx_base + column * idx_step
					var op: int = -1
					if has_overlays:
						var ov: Variant = overlays.get(idx)
						if ov is Dictionary:
							op = _overlay_opacity(ov as Dictionary)
					if op < 0:
						op = opacity[tiles[idx]]
					blocking = op == SimTileMapRes.Opacity.Opaque or (op == SimTileMapRes.Opacity.Low and crouched)
				if blocking or (column * cur_start_d >= depth * cur_start_n and column * end_d <= depth * end_n):
					# Inside the range circle a tile is inside the square (depth and |column| are
					# both at most range_tiles), so the cell index needs no bounds test.
					if depth_sq + column * column <= range_sq:
						var ci: int = cell_base + column * cell_step
						if cells[ci] != 1:
							cells[ci] = 1
							out.count += 1
				if prev == 2 and not blocking:
					cur_start_n = 2 * column - 1
					cur_start_d = 2 * depth
				if prev == 1 and blocking:
					stack.append_array([depth + 1, cur_start_n, cur_start_d, 2 * column - 1, 2 * depth])
				prev = 2 if blocking else 1
			if prev == 1:
				stack.append_array([depth + 1, cur_start_n, cur_start_d, end_n, end_d])
	out.cells = cells
	return out


# `SimTileMap.opacity_at`'s overlay half: -1 where the overlay says nothing and the class decides.
static func _overlay_opacity(ov: Dictionary) -> int:
	var kind: String = String(ov.get("kind", ""))
	if kind == "scrap":
		return SimTileMapRes.Opacity.Opaque
	if kind == "board":
		if int(ov.get("stage", 0)) >= 3:
			return SimTileMapRes.Opacity.Low
		return SimTileMapRes.Opacity.Opaque
	if kind == "door":
		return SimTileMapRes.Opacity.Clear if bool(ov.get("open", false)) else SimTileMapRes.Opacity.Opaque
	return -1
