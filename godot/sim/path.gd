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
	var open: Array[Vector2i] = [from]
	var came: Dictionary = {}
	var g: Dictionary = {from: 0}
	var seen: Dictionary = {from: true}
	var guard: int = 0
	var cap: int = 4096
	while not open.is_empty() and guard < cap:
		guard += 1
		var best_i: int = 0
		var best_f: int = 1 << 30
		for i in open.size():
			var n: Vector2i = open[i]
			var f: int = int(g.get(n, 1 << 20)) + absi(n.x - to.x) + absi(n.y - to.y)
			if f < best_f:
				best_f = f
				best_i = i
		var cur: Vector2i = open[best_i]
		open.remove_at(best_i)
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
				open.append(nxt)
				seen[nxt] = true
	return empty


static func _rebuild(came: Dictionary, cur: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var n: Vector2i = cur
	while came.has(n):
		out.push_front(n)
		n = came[n] as Vector2i
	return out
