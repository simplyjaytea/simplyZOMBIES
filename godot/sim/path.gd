class_name SimPath
extends RefCounted

# Survivor-only grid A*. Zombies never call this (field grind stays).
# ponytail: 4-connected linear open-set; heap if a 256 m haul shows up in the 8 ms tick.

const SimTileMap = preload("res://sim/map/tilemap.gd")

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


static func walkable(world: Variant, tx: int, ty: int) -> bool:
	if world == null:
		return false
	var map: Variant = world.tilemap
	if world.is_blocked_tile(tx, ty):
		# A closed door blocks the kernel and not a person: they open it as the step through
		# it (SimJobs._walk, SimRaiders._walk), so the planner routes through it. The dead do
		# not plan, and a closed door is a wall to them.
		return map != null and SimTileMap.tile_at(map, tx, ty) == SimTileMap.Tile.Door
	if map == null:
		return not world.is_blocked_tile(tx, ty)
	return _footing(map, tx, ty)


# The same question with the world taken out: what a survivor could put a foot on, read off a map
# nobody has booted. `world.is_blocked_tile` is `SimTileMap.is_solid` over an adopted map (see
# `World.adopt_map`), so the two answers agree tile for tile -- which is the point, because the
# worldgen survivability pass judges routes before a world exists and must judge the routes this
# pathfinder will actually accept rather than a second opinion about what counts as ground.
static func walkable_tile(map: Variant, tx: int, ty: int) -> bool:
	if map == null:
		return false
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return false
	if SimTileMap.is_solid(map, tx, ty):
		# The same door rule as `walkable` above: a shut door is a wall to the kernel and a
		# step to a person, and this judgement is asked of booted maps whose doors are shut.
		return SimTileMap.tile_at(map, tx, ty) == SimTileMap.Tile.Door
	return _footing(map, tx, ty)


# Open floor, or anything paved: a wreck in the road is cover you walk round the side of, and the
# pavement under it is still pavement. Undergrowth is not, which is what makes a thicket a barrier.
static func _footing(map: Variant, tx: int, ty: int) -> bool:
	var tile: int = SimTileMap.tile_at(map, tx, ty)
	if tile == SimTileMap.Tile.Floor or tile == SimTileMap.Tile.Door:
		return true
	return int(map.surfaces[ty * int(map.w) + tx]) == SimTileMap.SURFACE_PAVED


static func find(world: Variant, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if from == to:
		return empty
	if not walkable(world, to.x, to.y) and from != to:
		# allow targeting a bed/campfire tile even if we treat it occupied
		if not walkable(world, to.x, to.y):
			var ok_near: bool = false
			for d in DIRS:
				if walkable(world, to.x + d.x, to.y + d.y):
					ok_near = true
					break
			if not ok_near:
				return empty
	# The open set is a binary heap ordered by (f, seq), where `seq` is the order a tile first
	# entered the open set. That is exactly the order the old linear scan chose in: it took the
	# lowest f, and among equal f the earliest entry still in its insertion-ordered list. A tile
	# whose g improves while open is pushed again under its original `seq`; the stale entry is
	# skipped when it surfaces. Same pops in the same order, so the same path, tie for tie -- at
	# O(log n) a pop instead of O(n), which was most of a 100 ms re-plan on a 256-tile district
	# (A3's second slice; `check_m2_tick.gd` PATH holds it to the scan).
	#
	# Each heap entry is one int, f << 40 | seq << 20 | tile index, so comparing two is comparing
	# two ints: f leads, seq breaks ties, and a tile's seq never changes, so the index never decides
	# anything. g, seq and the way back live in flat arrays indexed by tile, and `walkable` is read
	# straight off the world's and the map's arrays rather than called per neighbour. A 59-step plan
	# round a block was a 21 ms tick (A3's eighth slice); the expansions are the same ones.
	var ww: int = int(world.map_width) if "map_cells" in world else 0
	var wh: int = int(world.map_height) if "map_cells" in world else 0
	var fast: bool = ww > 0 and wh > 0 and from.x >= 0 and from.y >= 0 and from.x < ww and from.y < wh and to.x >= 0 and to.y >= 0 and to.x < ww and to.y < wh and ww * wh <= 1 << 20
	if not fast:
		return _find_general(world, from, to)
	var cells: Array[int] = world.map_cells
	var map: Variant = world.tilemap
	var has_map: bool = map != null
	var tw: int = int(map.w) if has_map else 0
	var th: int = int(map.h) if has_map else 0
	var tiles: PackedByteArray = map.tiles if has_map else PackedByteArray()
	var surfaces: PackedByteArray = map.surfaces if has_map else PackedByteArray()
	var n: int = ww * wh
	var g := PackedInt32Array()
	g.resize(n)
	g.fill(-1)
	var seq_of := PackedInt32Array()
	seq_of.resize(n)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	var from_i: int = from.y * ww + from.x
	var to_i: int = to.y * ww + to.x
	g[from_i] = 0
	var next_seq: int = 1
	var open_count: int = 1
	var heap: Array[int] = [((absi(from.x - to.x) + absi(from.y - to.y)) << 40) | from_i]
	var guard: int = 0
	var cap: int = 4096
	while open_count > 0 and guard < cap:
		var top: int = _int_heap_pop(heap)
		var cur_i: int = top & 0xFFFFF
		var cx: int = cur_i % ww
		var cy: int = cur_i / ww
		if closed[cur_i] == 1 or (top >> 40) != g[cur_i] + absi(cx - to.x) + absi(cy - to.y):
			continue
		guard += 1
		closed[cur_i] = 1
		open_count -= 1
		if cur_i == to_i:
			return _rebuild_flat(came, cur_i, ww)
		var ng: int = g[cur_i] + 1
		for k in 4:
			var nx: int = cx + (1 if k == 0 else (-1 if k == 1 else 0))
			var ny: int = cy + (1 if k == 2 else (-1 if k == 3 else 0))
			var inside: bool = nx >= 0 and ny >= 0 and nx < ww and ny < wh
			var nxt_i: int = ny * ww + nx
			if not (inside and nxt_i == to_i):
				# `walkable`, inlined: blocked (off the world, or a solid cell) passes only as a shut
				# door; open ground is Floor, a Door, or anything paved.
				var ok: bool
				if not inside or cells[nxt_i] == 1:
					ok = has_map and nx < tw and ny < th and inside and tiles[ny * tw + nx] == SimTileMap.Tile.Door
				elif not has_map:
					ok = true
				elif nx >= tw or ny >= th:
					ok = false
				else:
					var t: int = tiles[ny * tw + nx]
					ok = t == SimTileMap.Tile.Floor or t == SimTileMap.Tile.Door or surfaces[ny * tw + nx] == SimTileMap.SURFACE_PAVED
				if not ok:
					continue
			var seen: bool = g[nxt_i] >= 0
			if seen and ng >= g[nxt_i]:
				continue
			came[nxt_i] = cur_i
			g[nxt_i] = ng
			var h: int = absi(nx - to.x) + absi(ny - to.y)
			if not seen:
				seq_of[nxt_i] = next_seq
				next_seq += 1
				open_count += 1
				_int_heap_push(heap, ((ng + h) << 40) | (seq_of[nxt_i] << 20) | nxt_i)
			elif closed[nxt_i] == 0:
				_int_heap_push(heap, ((ng + h) << 40) | (seq_of[nxt_i] << 20) | nxt_i)
	return empty


static func _int_heap_push(heap: Array[int], item: int) -> void:
	heap.append(item)
	var i: int = heap.size() - 1
	while i > 0:
		var parent: int = (i - 1) >> 1
		var pv: int = heap[parent]
		if item >= pv:
			break
		heap[i] = pv
		i = parent
	heap[i] = item


static func _int_heap_pop(heap: Array[int]) -> int:
	var top: int = heap[0]
	var last: int = heap.pop_back()
	var n: int = heap.size()
	if n == 0:
		return top
	var i: int = 0
	while true:
		var l: int = i * 2 + 1
		if l >= n:
			break
		var best: int = l
		var r: int = l + 1
		if r < n and heap[r] < heap[l]:
			best = r
		if heap[best] >= last:
			break
		heap[i] = heap[best]
		i = best
	heap[i] = last
	return top


static func _rebuild_flat(came: PackedInt32Array, cur_i: int, ww: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var at: int = cur_i
	while came[at] >= 0:
		out.push_front(Vector2i(at % ww, at / ww))
		at = came[at]
	return out


# The same search with `walkable` asked per neighbour, for a world without flat cells or an end
# off its edge: the shape the flat search above was cut from, kept for the cases it does not take.
static func _find_general(world: Variant, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	var heap: Array = []
	var seq_of: Dictionary = {from: 0}
	var next_seq: int = 1
	var closed: Dictionary = {}
	var open_count: int = 1
	_heap_push(heap, [absi(from.x - to.x) + absi(from.y - to.y), 0, from.x, from.y])
	var came: Dictionary = {}
	var g: Dictionary = {from: 0}
	var seen: Dictionary = {from: true}
	var guard: int = 0
	var cap: int = 4096
	while open_count > 0 and guard < cap:
		var top: Array = _heap_pop(heap)
		var cur := Vector2i(int(top[2]), int(top[3]))
		if closed.has(cur) or int(top[0]) != int(g[cur]) + absi(cur.x - to.x) + absi(cur.y - to.y):
			continue
		guard += 1
		closed[cur] = true
		open_count -= 1
		if cur == to:
			return _rebuild(came, cur)
		for d in DIRS:
			var nxt: Vector2i = cur + d
			var step_ok: bool = walkable(world, nxt.x, nxt.y) or nxt == to
			if not step_ok:
				continue
			var ng: int = int(g.get(cur, 0)) + 1
			if seen.has(nxt) and ng >= int(g.get(nxt, 1 << 20)):
				continue
			came[nxt] = cur
			g[nxt] = ng
			if not seen.has(nxt):
				seen[nxt] = true
				seq_of[nxt] = next_seq
				next_seq += 1
				open_count += 1
				_heap_push(heap, [ng + absi(nxt.x - to.x) + absi(nxt.y - to.y), int(seq_of[nxt]), nxt.x, nxt.y])
			elif not closed.has(nxt):
				_heap_push(heap, [ng + absi(nxt.x - to.x) + absi(nxt.y - to.y), int(seq_of[nxt]), nxt.x, nxt.y])
	return empty


static func _before(a: Array, b: Array) -> bool:
	return int(a[0]) < int(b[0]) or (int(a[0]) == int(b[0]) and int(a[1]) < int(b[1]))


static func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i: int = heap.size() - 1
	while i > 0:
		var parent: int = (i - 1) >> 1
		if not _before(heap[i], heap[parent]):
			break
		var t: Variant = heap[i]
		heap[i] = heap[parent]
		heap[parent] = t
		i = parent


static func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Variant = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var i: int = 0
	var n: int = heap.size()
	while true:
		var l: int = i * 2 + 1
		if l >= n:
			break
		var best: int = l
		var r: int = l + 1
		if r < n and _before(heap[r], heap[l]):
			best = r
		if not _before(heap[best], heap[i]):
			break
		var t: Variant = heap[i]
		heap[i] = heap[best]
		heap[best] = t
		i = best
	return top


static func _rebuild(came: Dictionary, cur: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var n: Vector2i = cur
	while came.has(n):
		out.push_front(n)
		n = came[n] as Vector2i
	return out
