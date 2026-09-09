class_name SimSurface
extends RefCounted

const SimTileMapRes = preload("res://sim/map/tilemap.gd")

# Water is the sixth surface and the wadeable half of a river: an ordinary `Tile.Floor` standing
# on it is a ford, and `SimTileMap.Tile.Water` standing on it is the deep channel. Deep water is
# solid, so it never reads SPEED at all -- every number below describes the ford.
enum Surface { Paved = 0, Dirt = 1, Grass = 2, Undergrowth = 3, Rubble = 4, Water = 5 }

# docs/24's ground table, with water added. Water is the slowest surface by a clear margin and
# the loudest: you wade it, and wading carries. It is deliberately worse than every other ground
# on both axes, which does **not** break docs/29's "nothing may be strictly better than anything
# else" -- that rule forbids a free lunch, and a ford is the opposite of one. A ford is not
# weighed against walking on grass; it is weighed against walking all the way round, which is the
# only reason anybody steps in.
#
# 0.45 and 1.8 are **first cuts taken without an owner** (docs/30's water entry lists them for
# the owner the way the driving and weather numbers are listed): each is one constant here, and
# the ten-day playtest is what they are for. Read against docs/03's emitter table, a walk across
# a ford carries 2.5 m against 1.4 m on tarmac and a sprint across one carries 15.5 m -- most of
# a street, which is the point.
const SPEED: Array[float] = [1.0, 0.95, 0.9, 0.6, 0.7, 0.45]
const NOISE: Array[float] = [1.0, 0.85, 0.6, 1.3, 1.7, 1.8]


static func surface_at(map: Variant, tx: int, ty: int) -> int:
	if tx < 0 or ty < 0 or tx >= map.w or ty >= map.h:
		return Surface.Paved
	return int(map.surfaces[ty * map.w + tx])


static func speed_on(surface: int) -> float:
	return SPEED[surface]


static func noise_on(surface: int) -> float:
	return NOISE[surface]
