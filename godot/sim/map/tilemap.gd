class_name SimTileMap
extends RefCounted

const RngStream = preload("res://sim/rng_stream.gd")

const TILE_METRES: int = 1
const DISTRICT_TILES: int = 256

enum Tile { Floor = 0, Wall = 1, Window = 2, Screen = 3, Low = 4, Tree = 5 }
enum Opacity { Clear = 0, Opaque = 1, Low = 2 }
enum Eye { Standing = 0, Crouched = 1 }

const OPACITY: Array[int] = [
	Opacity.Clear,
	Opacity.Opaque,
	Opacity.Clear,
	Opacity.Opaque,
	Opacity.Low,
	Opacity.Opaque,
]
const SOLID: Array[bool] = [
	false,
	true,
	true,
	false,
	false,
	true,
]

const SURFACE_PAVED: int = 0
const SURFACE_DIRT: int = 1
const SURFACE_GRASS: int = 2
const SURFACE_UNDERGROWTH: int = 3
const SURFACE_RUBBLE: int = 4

var w: int
var h: int
var tiles: PackedByteArray
var surfaces: PackedByteArray
var indoors: PackedByteArray

func _init(width: int, height: int, tile: int = Tile.Floor) -> void:
	w = width
	h = height
	tiles = PackedByteArray()
	tiles.resize(w * h)
	if tile != Tile.Floor:
		for i in tiles.size():
			tiles[i] = tile
	surfaces = PackedByteArray()
	surfaces.resize(w * h)
	indoors = PackedByteArray()
	indoors.resize(w * h)


static func blank_map(width: int, height: int, tile: int = Tile.Floor) -> Variant:
	var script: GDScript = load("res://sim/map/tilemap.gd") as GDScript
	return script.new(width, height, tile)


static func tile_range(metres: float) -> int:
	return maxi(1, ceili(metres / float(TILE_METRES)))


static func tile_at(map: Variant, tx: int, ty: int) -> int:
	if tx < 0 or ty < 0 or tx >= map.w or ty >= map.h:
		return Tile.Wall
	return int(map.tiles[ty * map.w + tx])


static func is_solid(map: Variant, tx: int, ty: int) -> bool:
	return SOLID[tile_at(map, tx, ty)]


static func opacity_at(map: Variant, tx: int, ty: int) -> int:
	return OPACITY[tile_at(map, tx, ty)]


static func blocks_sight(map: Variant, tx: int, ty: int, eye: int = Eye.Standing) -> bool:
	var opacity := opacity_at(map, tx, ty)
	return opacity == Opacity.Opaque or (opacity == Opacity.Low and eye == Eye.Crouched)


static func blocked_at(map: Variant, x: float, y: float) -> bool:
	return is_solid(map, floori(x / float(TILE_METRES)), floori(y / float(TILE_METRES)))


static func is_indoors(map: Variant, tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= map.w or ty >= map.h:
		return false
	return map.indoors[ty * map.w + tx] == 1


static func _fill(map: Variant, x: int, y: int, fw: int, fh: int, tile: int) -> void:
	for j in fh:
		for i in fw:
			var tx := x + i
			var ty := y + j
			if tx < 0 or ty < 0 or tx >= map.w or ty >= map.h:
				continue
			map.tiles[ty * map.w + tx] = tile


static func _building(map: Variant, x: int, y: int, bw: int, bh: int, door: int) -> void:
	_fill(map, x, y, bw, 1, Tile.Wall)
	_fill(map, x, y + bh - 1, bw, 1, Tile.Wall)
	_fill(map, x, y, 1, bh, Tile.Wall)
	_fill(map, x + bw - 1, y, 1, bh, Tile.Wall)
	for j in range(1, bh - 1):
		for i in range(1, bw - 1):
			var tx := x + i
			var ty := y + j
			if tx < 0 or ty < 0 or tx >= map.w or ty >= map.h:
				continue
			map.indoors[ty * map.w + tx] = 1
	var mid_x := x + (bw >> 1)
	var mid_y := y + (bh >> 1)
	match door & 3:
		0:
			_fill(map, mid_x, y, 2, 1, Tile.Floor)
		1:
			_fill(map, x + bw - 1, mid_y, 1, 2, Tile.Floor)
		2:
			_fill(map, mid_x, y + bh - 1, 2, 1, Tile.Floor)
		_:
			_fill(map, x, mid_y, 1, 2, Tile.Floor)


static func generate_district(seed: int, size: int = DISTRICT_TILES) -> Variant:
	var map: Variant = blank_map(size, size)
	var rng: Variant = RngStream.new(seed ^ 0x5eed0a95)
	_fill(map, 0, 0, size, 1, Tile.Wall)
	_fill(map, 0, size - 1, size, 1, Tile.Wall)
	_fill(map, 0, 0, 1, size, Tile.Wall)
	_fill(map, size - 1, 0, 1, size, Tile.Wall)
	var block: int = 40
	var street: int = 12
	var by: int = street
	while by + block < size:
		var bx: int = street
		while bx + block < size:
			var count: int = (rng as RefCounted).call("int_range", 2, 3)
			for i in count:
				var bw: int = (rng as RefCounted).call("int_range", 10, 18)
				var bh: int = (rng as RefCounted).call("int_range", 10, 16)
				var ox: int = bx + (rng as RefCounted).call("int_range", 0, maxi(0, block - bw))
				var oy: int = by + (rng as RefCounted).call("int_range", 0, maxi(0, block - bh))
				_building(map, ox, oy, bw, bh, (rng as RefCounted).call("int_range", 0, 3))
			bx += block + street
		by += block + street
	_dress_occluders(map, seed)
	_dress_terrain(map, seed)
	return map


static func _dress_occluders(map: Variant, seed: int) -> void:
	var rng: Variant = RngStream.new(seed ^ 0x516874)
	for ty in range(1, map.h - 1):
		for tx in range(1, map.w - 1):
			if int(map.tiles[ty * map.w + tx]) != Tile.Wall:
				continue
			var horizontal: bool = !is_solid(map, tx - 1, ty) and !is_solid(map, tx + 1, ty)
			var vertical: bool = !is_solid(map, tx, ty - 1) and !is_solid(map, tx, ty + 1)
			if !horizontal and !vertical:
				continue
			if (rng as RefCounted).call("int_range", 0, 4) != 0:
				continue
			map.tiles[ty * map.w + tx] = Tile.Window
	var clumps: int = maxi(1, floori(float(map.w * map.h) / 3000.0))
	for i in clumps:
		var ox: int = (rng as RefCounted).call("int_range", 1, map.w - 2)
		var oy: int = (rng as RefCounted).call("int_range", 1, map.h - 2)
		var cw: int = (rng as RefCounted).call("int_range", 2, 4)
		var ch: int = (rng as RefCounted).call("int_range", 2, 4)
		for dy in ch:
			for dx in cw:
				var tx: int = ox + dx
				var ty: int = oy + dy
				if tx <= 0 or ty <= 0 or tx >= map.w - 1 or ty >= map.h - 1:
					continue
				if is_indoors(map, tx, ty):
					continue
				if int(map.tiles[ty * map.w + tx]) != Tile.Floor:
					continue
				map.tiles[ty * map.w + tx] = Tile.Screen
	var wrecks: int = maxi(1, floori(float(map.w * map.h) / 2000.0))
	for i in wrecks:
		var ox: int = (rng as RefCounted).call("int_range", 1, map.w - 2)
		var oy: int = (rng as RefCounted).call("int_range", 1, map.h - 2)
		var along: bool = (rng as RefCounted).call("int_range", 0, 1) == 0
		var length: int = (rng as RefCounted).call("int_range", 2, 3)
		for step in length:
			var tx: int = ox + step if along else ox
			var ty: int = oy if along else oy + step
			if tx <= 0 or ty <= 0 or tx >= map.w - 1 or ty >= map.h - 1:
				continue
			if is_indoors(map, tx, ty):
				continue
			if int(map.tiles[ty * map.w + tx]) != Tile.Floor:
				continue
			map.tiles[ty * map.w + tx] = Tile.Low


static func _dress_terrain(map: Variant, seed: int) -> void:
	var rng: Variant = RngStream.new(seed ^ 0x6e7ee15)
	var block: int = 40
	var street: int = 12
	var by: int = street
	while by + block < map.h:
		var bx: int = street
		while bx + block < map.w:
			var cx: float = float(bx) + float(block) / 2.0
			var cy: float = float(by) + float(block) / 2.0
			var radius: float = float(block) * 0.5
			for ty in range(by - 2, by + block + 2):
				for tx in range(bx - 2, bx + block + 2):
					if tx <= 0 or ty <= 0 or tx >= map.w - 1 or ty >= map.h - 1:
						continue
					if int(map.tiles[ty * map.w + tx]) != Tile.Floor:
						continue
					if is_indoors(map, tx, ty):
						continue
					var distance: float = sqrt(pow(float(tx) + 0.5 - cx, 2.0) + pow(float(ty) + 0.5 - cy, 2.0))
					if distance > radius + float((rng as RefCounted).call("int_range", -3, 3)):
						continue
					map.surfaces[ty * map.w + tx] = SURFACE_GRASS
			if (rng as RefCounted).call("int_range", 0, 1) != 0:
				bx += block + street
				continue
			var stands: int = (rng as RefCounted).call("int_range", 3, 6)
			for i in stands:
				var ox: int = bx + (rng as RefCounted).call("int_range", 1, block - 2)
				var oy: int = by + (rng as RefCounted).call("int_range", 1, block - 2)
				var trees: int = (rng as RefCounted).call("int_range", 3, 8)
				for t in trees:
					var tx: int = ox + (rng as RefCounted).call("int_range", -2, 2)
					var ty: int = oy + (rng as RefCounted).call("int_range", -2, 2)
					if tx <= 0 or ty <= 0 or tx >= map.w - 1 or ty >= map.h - 1:
						continue
					if int(map.tiles[ty * map.w + tx]) != Tile.Floor:
						continue
					if is_indoors(map, tx, ty):
						continue
					if int(map.surfaces[ty * map.w + tx]) != SURFACE_GRASS:
						continue
					map.tiles[ty * map.w + tx] = Tile.Tree
			var thickets: int = (rng as RefCounted).call("int_range", 2, 5)
			for i in thickets:
				var ox: int = bx + (rng as RefCounted).call("int_range", 1, block - 2)
				var oy: int = by + (rng as RefCounted).call("int_range", 1, block - 2)
				var th: int = (rng as RefCounted).call("int_range", 2, 4)
				var tw: int = (rng as RefCounted).call("int_range", 2, 4)
				for dy in th:
					for dx in tw:
						var tx: int = ox + dx
						var ty: int = oy + dy
						if tx <= 0 or ty <= 0 or tx >= map.w - 1 or ty >= map.h - 1:
							continue
						if int(map.tiles[ty * map.w + tx]) != Tile.Floor:
							continue
						if is_indoors(map, tx, ty):
							continue
						if int(map.surfaces[ty * map.w + tx]) != SURFACE_GRASS:
							continue
						map.tiles[ty * map.w + tx] = Tile.Screen
			bx += block + street
		by += block + street
	for i in map.tiles.size():
		if int(map.tiles[i]) == Tile.Screen:
			map.surfaces[i] = SURFACE_UNDERGROWTH
	var grass: Array[int] = []
	for ty in range(1, map.h - 1):
		for tx in range(1, map.w - 1):
			var idx: int = ty * map.w + tx
			if int(map.surfaces[idx]) != SURFACE_GRASS:
				continue
			if int(map.tiles[idx]) != Tile.Floor:
				continue
			var edge: bool = int(map.surfaces[ty * map.w + tx - 1]) == SURFACE_PAVED \
					or int(map.surfaces[ty * map.w + tx + 1]) == SURFACE_PAVED \
					or int(map.surfaces[(ty - 1) * map.w + tx]) == SURFACE_PAVED \
					or int(map.surfaces[(ty + 1) * map.w + tx]) == SURFACE_PAVED
			if edge and (rng as RefCounted).call("int_range", 0, 2) != 0:
				grass.append(idx)
	for idx in grass:
		map.surfaces[idx] = SURFACE_DIRT
