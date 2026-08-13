class_name SimSurface
extends RefCounted

# Keep in sync with src/sim/map/surface.ts
enum Surface {
	PAVED = 0,
	DIRT = 1,
	GRASS = 2,
	UNDERGROWTH = 3,
	RUBBLE = 4,
}

const SPEED: Array[float] = [1.0, 0.95, 0.9, 0.6, 0.7]
const NOISE: Array[float] = [1.0, 0.85, 0.6, 1.3, 1.7]


static func surface_at(map: Dictionary, tx: int, ty: int) -> int:
	if tx < 0 or ty < 0 or tx >= int(map["w"]) or ty >= int(map["h"]):
		return Surface.PAVED
	var surfaces: PackedByteArray = map["surfaces"]
	return int(surfaces[ty * int(map["w"]) + tx])


static func speed_on(surface: int) -> float:
	return SPEED[surface]


static func noise_on(surface: int) -> float:
	return NOISE[surface]
