class_name SimSurface
extends RefCounted

const SimTileMapRes = preload("res://sim/map/tilemap.gd")

enum Surface { Paved = 0, Dirt = 1, Grass = 2, Undergrowth = 3, Rubble = 4 }

const SPEED: Array[float] = [1.0, 0.95, 0.9, 0.6, 0.7]
const NOISE: Array[float] = [1.0, 0.85, 0.6, 1.3, 1.7]


static func surface_at(map: Variant, tx: int, ty: int) -> int:
	if tx < 0 or ty < 0 or tx >= map.w or ty >= map.h:
		return Surface.Paved
	return int(map.surfaces[ty * map.w + tx])


static func speed_on(surface: int) -> float:
	return SPEED[surface]


static func noise_on(surface: int) -> float:
	return NOISE[surface]
