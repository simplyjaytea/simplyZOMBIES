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
	# The open set is a binary heap of [f, seq, x, y] ordered by (f, seq), where `seq` is the order a
	# tile first entered the open set. That is exactly the order the old linear scan chose in: it
	# took the lowest f, and among equal f the earliest entry still in its insertion-ordered list.
	# A tile whose g improves while open is pushed again under its original `seq`; the stale entry
	# is skipped when it surfaces. Same pops in the same order, so the same path, tie for tie --
	# at O(log n) a pop instead of O(n), which was most of a 100 ms re-plan on a 256-tile district
	# (A3's second slice; `check_m2_tick.gd` PATH holds it to the scan).
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
