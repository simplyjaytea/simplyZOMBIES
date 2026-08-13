class_name SimTileMap
extends RefCounted

const TILE_METRES: int = 1
const DISTRICT_TILES: int = 256

enum Tile { FLOOR = 0, WALL = 1, WINDOW = 2, SCREEN = 3, LOW = 4, TREE = 5 }
enum Opacity { CLEAR = 0, OPAQUE = 1, LOW = 2 }
enum Eye { STANDING = 0, CROUCHED = 1 }

const OPACITY: Array[int] = [Opacity.CLEAR, Opacity.OPAQUE, Opacity.CLEAR, Opacity.OPAQUE, Opacity.LOW, Opacity.OPAQUE]
const SOLID: Array[bool] = [false, true, true, false, false, true]

const RngStream = preload("res://sim/rng_stream.gd")
const SurfaceUtil = preload("res://sim/surface.gd")


static func tile_range(metres: float) -> int:
	return maxi(1, ceili(metres / float(TILE_METRES)))


static func blank_map(w: int, h: int, tile: int = Tile.FLOOR) -> Dictionary:
	var tiles: Variant = PackedByteArray()
	tiles.resize(w * h)
	if tile != Tile.FLOOR:
		tiles.fill(tile)
	var surfaces: Variant = PackedByteArray()
	surfaces.resize(w * h)
	var indoors: Variant = PackedByteArray()
	indoors.resize(w * h)
	return {"w": w, "h": h, "tiles": tiles, "surfaces": surfaces, "indoors": indoors}


static func is_indoors(map: Dictionary, tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= int(map["w"]) or ty >= int(map["h"]):
		return false
	var indoors: PackedByteArray = map["indoors"]
	return indoors[ty * int(map["w"]) + tx] == 1


static func tile_at(map: Dictionary, tx: int, ty: int) -> int:
	if tx < 0 or ty < 0 or tx >= int(map["w"]) or ty >= int(map["h"]):
		return Tile.WALL
	var tiles: PackedByteArray = map["tiles"]
	return int(tiles[ty * int(map["w"]) + tx])


static func is_solid(map: Dictionary, tx: int, ty: int) -> bool:
	return SOLID[tile_at(map, tx, ty)]


static func opacity_at(map: Dictionary, tx: int, ty: int) -> int:
	return OPACITY[tile_at(map, tx, ty)]


static func blocks_sight(map: Dictionary, tx: int, ty: int, eye: int = Eye.STANDING) -> bool:
	var opacity: Variant = opacity_at(map, tx, ty)
	return opacity == Opacity.OPAQUE or (opacity == Opacity.LOW and eye == Eye.CROUCHED)


static func blocked_at(map: Dictionary, x: float, y: float) -> bool:
	return is_solid(map, floori(x / float(TILE_METRES)), floori(y / float(TILE_METRES)))


static func _fill(map: Dictionary, x: int, y: int, w: int, h: int, tile: int) -> void:
	var tiles: PackedByteArray = map["tiles"]
	var mw: int = int(map["w"])
	var mh: int = int(map["h"])
	for j in range(h):
		for i in range(w):
			var tx: Variant = x + i
			var ty: Variant = y + j
			if tx < 0 or ty < 0 or tx >= mw or ty >= mh:
				continue
			tiles[ty * mw + tx] = tile


static func _building(map: Dictionary, x: int, y: int, w: int, h: int, door: int) -> void:
	_fill(map, x, y, w, 1, Tile.WALL)
	_fill(map, x, y + h - 1, w, 1, Tile.WALL)
	_fill(map, x, y, 1, h, Tile.WALL)
	_fill(map, x + w - 1, y, 1, h, Tile.WALL)
	var indoors: PackedByteArray = map["indoors"]
	var mw: int = int(map["w"])
	var mh: int = int(map["h"])
	for j in range(1, h - 1):
		for i in range(1, w - 1):
			var tx: Variant = x + i
			var ty: Variant = y + j
			if tx < 0 or ty < 0 or tx >= mw or ty >= mh:
				continue
			indoors[ty * mw + tx] = 1
	var mid_x: Variant = x + (w >> 1)
	var mid_y: Variant = y + (h >> 1)
	match door & 3:
		0: _fill(map, mid_x, y, 2, 1, Tile.FLOOR)
		1: _fill(map, x + w - 1, mid_y, 1, 2, Tile.FLOOR)
		2: _fill(map, mid_x, y + h - 1, 2, 1, Tile.FLOOR)
		_: _fill(map, x, mid_y, 1, 2, Tile.FLOOR)


static func generate_district(seed: int, size: int = DISTRICT_TILES) -> Dictionary:
	var map: Variant = blank_map(size, size)
	var rng: Variant = RngStream.new(seed ^ 0x5eed0a95)
	_fill(map, 0, 0, size, 1, Tile.WALL)
	_fill(map, 0, size - 1, size, 1, Tile.WALL)
	_fill(map, 0, 0, 1, size, Tile.WALL)
	_fill(map, size - 1, 0, 1, size, Tile.WALL)
	var block: Variant = 40
	var street: Variant = 12
	var by: Variant = street
	while by + block < size:
		var bx: Variant = street
		while bx + block < size:
			var count: int = rng.int_range(2, 3)
			for i in range(count):
				var w2: int = rng.int_range(10, 18)
				var h2: int = rng.int_range(10, 16)
				var ox: int = bx + rng.int_range(0, maxi(0, block - w2))
				var oy: int = by + rng.int_range(0, maxi(0, block - h2))
				_building(map, ox, oy, w2, h2, rng.int_range(0, 3))
			bx += block + street
		by += block + street
	_dress_occluders(map, seed)
	_dress_terrain(map, seed)
	return map


static func _dress_occluders(map: Dictionary, seed: int) -> void:
	var rng: Variant = RngStream.new(seed ^ 0x516874)
	var mw: int = int(map["w"])
	var mh: int = int(map["h"])
	var tiles: PackedByteArray = map["tiles"]
	for ty in range(1, mh - 1):
		for tx in range(1, mw - 1):
			if int(tiles[ty * mw + tx]) != Tile.WALL:
				continue
			var horiz: Variant = not is_solid(map, tx - 1, ty) and not is_solid(map, tx + 1, ty)
			var vert: Variant = not is_solid(map, tx, ty - 1) and not is_solid(map, tx, ty + 1)
			if not horiz and not vert:
				continue
			if rng.int_range(0, 4) != 0:
				continue
			tiles[ty * mw + tx] = Tile.WINDOW
	var clumps: int = maxi(1, (mw * mh) / 3000)
	for i in range(clumps):
		var ox: int = rng.int_range(1, mw - 2)
		var oy: int = rng.int_range(1, mh - 2)
		var w2: int = rng.int_range(2, 4)
		var h2: int = rng.int_range(2, 4)
		for dy in range(h2):
			for dx in range(w2):
				var tx: int = ox + dx
				var ty: int = oy + dy
				if tx <= 0 or ty <= 0 or tx >= mw - 1 or ty >= mh - 1:
					continue
				if is_indoors(map, tx, ty):
					continue
				if int(tiles[ty * mw + tx]) != Tile.FLOOR:
					continue
				tiles[ty * mw + tx] = Tile.SCREEN
	var wrecks: int = maxi(1, (mw * mh) / 2000)
	for i in range(wrecks):
		var ox: int = rng.int_range(1, mw - 2)
		var oy: int = rng.int_range(1, mh - 2)
		var along: bool = rng.int_range(0, 1) == 0
		var length: int = rng.int_range(2, 3)
		for step in range(length):
			var tx: int = ox + step if along else ox
			var ty: int = oy if along else oy + step
			if tx <= 0 or ty <= 0 or tx >= mw - 1 or ty >= mh - 1:
				continue
			if is_indoors(map, tx, ty):
				continue
			if int(tiles[ty * mw + tx]) != Tile.FLOOR:
				continue
			tiles[ty * mw + tx] = Tile.LOW


static func _dress_terrain(map: Dictionary, seed: int) -> void:
	var rng: Variant = RngStream.new(seed ^ 0x6e7ee15)
	var mw: int = int(map["w"])
	var mh: int = int(map["h"])
	var tiles: PackedByteArray = map["tiles"]
	var surfaces: PackedByteArray = map["surfaces"]
	var block: Variant = 40
	var street: Variant = 12
	var by: Variant = street
	while by + block < mh:
		var bx: Variant = street
		while bx + block < mw:
			var cx: float = float(bx) + float(block) / 2.0
			var cy: float = float(by) + float(block) / 2.0
			var radius: float = float(block) * 0.5
			for ty in range(by - 2, by + block + 2):
				for tx in range(bx - 2, bx + block + 2):
					if tx < 0 or ty < 0 or tx >= mw or ty >= mh:
						continue
					if int(tiles[ty * mw + tx]) != Tile.FLOOR or is_indoors(map, tx, ty):
						continue
					var dist: float = (Vector2(float(tx) + 0.5, float(ty) + 0.5) - Vector2(cx, cy)).length()
					if dist > radius + float(rng.int_range(-3, 3)):
						continue
					surfaces[ty * mw + tx] = SurfaceUtil.Surface.GRASS
			if rng.int_range(0, 1) != 0:
				bx += block + street
				continue
			var stands: int = rng.int_range(3, 6)
			for i in range(stands):
				var ox: int = bx + rng.int_range(1, block - 2)
				var oy: int = by + rng.int_range(1, block - 2)
				var trees: int = rng.int_range(3, 8)
				for t in range(trees):
					var tx: int = ox + rng.int_range(-2, 2)
					var ty: int = oy + rng.int_range(-2, 2)
					if tx < 0 or ty < 0 or tx >= mw or ty >= mh:
						continue
					if is_indoors(map, tx, ty):
						continue
					if int(tiles[ty * mw + tx]) != Tile.FLOOR:
						continue
					if int(surfaces[ty * mw + tx]) != SurfaceUtil.Surface.GRASS:
						continue
					tiles[ty * mw + tx] = Tile.TREE
			var thickets: int = rng.int_range(2, 5)
			for i in range(thickets):
				var ox: int = bx + rng.int_range(1, block - 2)
				var oy: int = by + rng.int_range(1, block - 2)
				for dy in range(rng.int_range(2, 4)):
					for dx in range(rng.int_range(2, 4)):
						var tx: int = ox + dx
						var ty: int = oy + dy
						if tx < 0 or ty < 0 or tx >= mw or ty >= mh:
							continue
						if is_indoors(map, tx, ty):
							continue
						if int(tiles[ty * mw + tx]) != Tile.FLOOR:
							continue
						if int(surfaces[ty * mw + tx]) != SurfaceUtil.Surface.GRASS:
							continue
						tiles[ty * mw + tx] = Tile.SCREEN
			bx += block + street
		by += block + street
	for i in range(tiles.size()):
		if int(tiles[i]) == Tile.SCREEN:
			surfaces[i] = SurfaceUtil.Surface.UNDERGROWTH
	var grass: Array[int] = []
	for ty in range(1, mh - 1):
		for tx in range(1, mw - 1):
			var idx: Variant = ty * mw + tx
			if int(surfaces[idx]) != SurfaceUtil.Surface.GRASS or int(tiles[idx]) != Tile.FLOOR:
				continue
			var edge: int = int(surfaces[ty * mw + (tx - 1)]) == SurfaceUtil.Surface.PAVED or int(surfaces[ty * mw + (tx + 1)]) == SurfaceUtil.Surface.PAVED or int(surfaces[(ty - 1) * mw + tx]) == SurfaceUtil.Surface.PAVED or int(surfaces[(ty + 1) * mw + tx]) == SurfaceUtil.Surface.PAVED
			if edge and rng.int_range(0, 2) != 0:
				grass.append(idx)
	for idx in grass:
		surfaces[idx] = SurfaceUtil.Surface.DIRT
	for ty in range(1, mh - 1):
		for tx in range(1, mw - 1):
			var idx: Variant = ty * mw + tx
			if int(tiles[idx]) == Tile.LOW:
				surfaces[idx] = SurfaceUtil.Surface.RUBBLE
				continue
			if int(tiles[idx]) != Tile.FLOOR or int(surfaces[idx]) != SurfaceUtil.Surface.PAVED:
				continue
			var beside: Variant = is_solid(map, tx - 1, ty) or is_solid(map, tx + 1, ty) or is_solid(map, tx, ty - 1) or is_solid(map, tx, ty + 1)
			if beside and rng.int_range(0, 3) == 0:
				surfaces[idx] = SurfaceUtil.Surface.RUBBLE


static func find_open_tile(map: Dictionary, prefer_x: int, prefer_y: int) -> Dictionary:
	var limit: int = maxi(int(map["w"]), int(map["h"]))
	for radius in range(limit):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var tx: Variant = prefer_x + dx
				var ty: Variant = prefer_y + dy
				if not is_solid(map, tx, ty):
					return {"x": float(tx) + 0.5, "y": float(ty) + 0.5}
	return {}
