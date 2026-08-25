class_name SimAttentionField
extends RefCounted

const SimTileMapRes = preload("res://sim/map/tilemap.gd")

const CELL_METRES: float = 4.0

var cols: int
var rows: int
var cell_metres: float
var calibration: Dictionary
var noise: PackedFloat32Array
var scent: PackedFloat32Array
var _solid: PackedByteArray
var _staged: PackedFloat32Array
var _queue: PackedInt32Array
var _queued: PackedByteArray
var _touched: PackedInt32Array
var _scent_next: PackedFloat32Array
var last_emit_cells: int = 0

var _step_cost: float
var _diagonal_cost: float
var _wall_cost: float
var _decay_per_tick: float
var _wind_weights: PackedFloat32Array
var _scent_decay_per_step: float


func _init(c: int, r: int, solid: PackedByteArray, calib: Dictionary, tick_hz: float) -> void:
	cols = c
	rows = r
	cell_metres = float(calib["cellMetres"])
	calibration = calib
	_solid = solid
	var n: int = cols * rows
	noise = PackedFloat32Array()
	noise.resize(n)
	scent = PackedFloat32Array()
	scent.resize(n)
	_scent_next = PackedFloat32Array()
	_scent_next.resize(n)
	_staged = PackedFloat32Array()
	_staged.resize(n)
	_queue = PackedInt32Array()
	_queue.resize(n + 1)
	_queued = PackedByteArray()
	_queued.resize(n)
	_touched = PackedInt32Array()
	_touched.resize(n)
	_step_cost = float(calib["cellMetres"]) * float(calib["attenuationPerMetre"])
	_diagonal_cost = _step_cost * sqrt(2.0)
	_wall_cost = float(calib["wallPenaltyMetres"]) * float(calib["attenuationPerMetre"])
	_decay_per_tick = pow(0.5, 1.0 / (float(calib["noiseHalfLifeSeconds"]) * tick_hz))
	var scent_interval: int = maxi(1, int(round(float(calib["scentIntervalTicks"]))))
	var steps_per_half: float = (float(calib["scentHalfLifeMinutes"]) * 60.0 * tick_hz) / float(scent_interval)
	_scent_decay_per_step = pow(0.5, 1.0 / steps_per_half)
	var raw: Array[float] = [
		max(0.0, 1.0 + float(calib["windX"])),
		max(0.0, 1.0 - float(calib["windX"])),
		max(0.0, 1.0 + float(calib["windY"])),
		max(0.0, 1.0 - float(calib["windY"])),
	]
	var total: float = raw[0] + raw[1] + raw[2] + raw[3]
	_wind_weights = PackedFloat32Array()
	_wind_weights.resize(4)
	for i in 4:
		_wind_weights[i] = raw[i] / total


static func default_calibration() -> Dictionary:
	return {
		"cellMetres": 4.0,
		"attenuationPerMetre": 0.7,
		"wallPenaltyMetres": 18.0,
		"noiseHalfLifeSeconds": 3.0,
		"floor": 0.05,
		"scentHalfLifeMinutes": 90.0,
		"scentDiffusionRate": 0.02,
		"scentFloor": 0.005,
		"scentIntervalTicks": 5,
		"scentCeiling": 5000.0,
		"windX": 0.6,
		"windY": -0.2,
	}


# A 4 m attention cell covers a 4x4 block of 1 m tiles. It counts as solid when **at least half**
# of the tiles it really covers are solid -- `solid_subtiles * 2 >= subtiles`, which is the
# "8 of 16" rule stated without assuming the block is full.
#
# It used to demand all sixteen, and that made the mask a dead socket: a district's buildings are
# one tile thick, one-tile walls can never fill a 4x4 block, and the shipped 256 map had **0 of
# 4,096** cells marked solid. `wallPenaltyMetres` and `_wall_cost` were therefore applied on zero
# transitions and `_uphill`'s solid skip never ran -- docs/23's open defect #1, and docs/03 makes
# wall attenuation load-bearing. Measured under the new rule on the canonical seed: 9 cells at 256
# (11/7/8 on the other balance seeds) and 0 on the 64 miniature, whose buildings are too sparse to
# fill half a cell anywhere.
#
# The threshold **scales with the cell**, because the edge cells of a map whose size is not a
# multiple of 4 cover fewer than sixteen tiles. Only real tiles are counted -- `SimTileMap.is_solid`
# answers "solid" for anything out of bounds, so padding an edge cell with the void would have let
# the map's own border vote itself solid. Half of what is there, whatever is there.
#
# Still one pass over the subtiles, as before, and it stops as soon as the verdict cannot change:
# the field is rebuilt on every boot and on every `world.adopt_map`.
static func for_map(map: Variant, calib: Variant = null, tick_hz: float = 20.0) -> Variant:
	var c: Dictionary = calib if calib != null else default_calibration()
	var per: int = maxi(1, int(round(float(c["cellMetres"]))))
	var mw: int = int(map.w)
	var mh: int = int(map.h)
	var ncols: int = ceili(float(mw) / float(per))
	var nrows: int = ceili(float(mh) / float(per))
	var solid := PackedByteArray()
	solid.resize(ncols * nrows)
	for cy in nrows:
		var hspan: int = mini(per, mh - cy * per)
		for cx in ncols:
			var wspan: int = mini(per, mw - cx * per)
			var subtiles: int = wspan * hspan
			if subtiles <= 0:
				solid[cy * ncols + cx] = 0
				continue
			# solid * 2 >= subtiles, restated as a count so the loop can stop early either way.
			var need: int = (subtiles + 1) / 2
			var found: int = 0
			var seen: int = 0
			for ty in hspan:
				if found >= need or found + (subtiles - seen) < need:
					break
				for tx in wspan:
					seen += 1
					if SimTileMapRes.is_solid(map, cx * per + tx, cy * per + ty):
						found += 1
			solid[cy * ncols + cx] = 1 if found >= need else 0
	var scr: GDScript = load("res://sim/field/attention.gd") as GDScript
	return scr.new(ncols, nrows, solid, c, tick_hz)


static func empty_field(calib: Variant = null, tick_hz: float = 20.0) -> Variant:
	var c: Dictionary = calib if calib != null else default_calibration()
	var scr: GDScript = load("res://sim/field/attention.gd") as GDScript
	return scr.new(0, 0, PackedByteArray(), c, tick_hz)


func cell_count() -> int:
	return cols * rows


func cell_at(x: float, y: float) -> int:
	if cell_count() == 0:
		return -1
	var cx: int = clampi(floori(x / cell_metres), 0, cols - 1)
	var cy: int = clampi(floori(y / cell_metres), 0, rows - 1)
	return cy * cols + cx


func is_solid(cell: int) -> bool:
	return _solid[cell] == 1


func noise_at(x: float, y: float) -> float:
	var c: int = cell_at(x, y)
	if c == -1:
		return 0.0
	return noise[c]


func emit_noise(x: float, y: float, magnitude: float) -> void:
	last_emit_cells = 0
	var start: int = cell_at(x, y)
	if start == -1 or magnitude < float(calibration["floor"]):
		return
	var floor_v: float = float(calibration["floor"])
	var capacity: int = _queue.size()
	var head: int = 0
	var tail: int = 0
	var n_touched: int = 0
	_staged[start] = magnitude
	_touched[n_touched] = start
	n_touched += 1
	_queue[tail] = start
	tail = (tail + 1) % capacity
	_queued[start] = 1
	while head != tail:
		var cell: int = _queue[head]
		head = (head + 1) % capacity
		_queued[cell] = 0
		var value: float = _staged[cell]
		if value < floor_v:
			continue
		var cx: int = cell % cols
		var cy: int = int(cell / cols)
		for dy in range(-1, 2):
			var ny: int = cy + dy
			if ny < 0 or ny >= rows:
				continue
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nx: int = cx + dx
				if nx < 0 or nx >= cols:
					continue
				var nxt: int = ny * cols + nx
				var cost: float = _diagonal_cost if dx != 0 and dy != 0 else _step_cost
				if _solid[nxt] == 1:
					cost += _wall_cost
				var arriving: float = value - cost
				if arriving < floor_v:
					continue
				if arriving <= _staged[nxt]:
					continue
				if _staged[nxt] == 0.0:
					_touched[n_touched] = nxt
					n_touched += 1
				_staged[nxt] = arriving
				if _queued[nxt] == 0:
					_queued[nxt] = 1
					_queue[tail] = nxt
					tail = (tail + 1) % capacity
	for i in n_touched:
		var cell: int = _touched[i]
		if _staged[cell] > noise[cell]:
			noise[cell] = _staged[cell]
		_staged[cell] = 0.0
	last_emit_cells = n_touched


func add_scent(x: float, y: float, magnitude: float) -> void:
	var cell: int = cell_at(x, y)
	if cell == -1 or magnitude <= 0.0:
		return
	var total: float = scent[cell] + magnitude
	var ceiling: float = float(calibration["scentCeiling"])
	scent[cell] = ceiling if total > ceiling else total


func diffuse_scent() -> void:
	var keep: float = 1.0 - float(calibration["scentDiffusionRate"])
	var rate: float = float(calibration["scentDiffusionRate"])
	var floor_v: float = float(calibration["scentFloor"])
	var w_px: float = _wind_weights[0]
	var w_mx: float = _wind_weights[1]
	var w_py: float = _wind_weights[2]
	var w_my: float = _wind_weights[3]
	for cy in rows:
		for cx in cols:
			var here: int = cy * cols + cx
			var value: float = scent[here] * keep
			if cx + 1 < cols:
				value += scent[here + 1] * rate * w_mx
			if cx - 1 >= 0:
				value += scent[here - 1] * rate * w_px
			if cy + 1 < rows:
				value += scent[here + cols] * rate * w_my
			if cy - 1 >= 0:
				value += scent[here - cols] * rate * w_py
			var decayed: float = value * _scent_decay_per_step
			_scent_next[here] = 0.0 if decayed < floor_v else decayed
	for i in scent.size():
		scent[i] = _scent_next[i]


func decay() -> void:
	var floor_v: float = float(calibration["floor"])
	for i in noise.size():
		var v: float = noise[i]
		if v == 0.0:
			continue
		var d: float = v * _decay_per_tick
		noise[i] = 0.0 if d < floor_v else d


func uphill_noise(x: float, y: float) -> Variant:
	return _uphill(noise, x, y)


func uphill_scent(x: float, y: float) -> Variant:
	return _uphill(scent, x, y)


func _uphill(layer: PackedFloat32Array, x: float, y: float) -> Variant:
	var here: int = cell_at(x, y)
	if here == -1:
		return null
	var cx: int = here % cols
	var cy: int = int(here / cols)
	var best: float = layer[here]
	var best_dx: int = 0
	var best_dy: int = 0
	for dy in range(-1, 2):
		var ny: int = cy + dy
		if ny < 0 or ny >= rows:
			continue
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx: int = cx + dx
			if nx < 0 or nx >= cols:
				continue
			var nxt: int = ny * cols + nx
			if _solid[nxt] == 1:
				continue
			if layer[nxt] > best:
				best = layer[nxt]
				best_dx = dx
				best_dy = dy
	if best_dx == 0 and best_dy == 0:
		return null
	return {"dx": best_dx, "dy": best_dy, "value": best}


func scent_at(x: float, y: float) -> float:
	var c: int = cell_at(x, y)
	if c == -1:
		return 0.0
	return scent[c]


func live_cells() -> int:
	var n: int = 0
	for i in noise.size():
		if noise[i] != 0.0:
			n += 1
	return n


func live_scent_cells() -> int:
	var n: int = 0
	for i in scent.size():
		if scent[i] != 0.0:
			n += 1
	return n


func peak_noise() -> float:
	var peak: float = 0.0
	for i in noise.size():
		if noise[i] > peak:
			peak = noise[i]
	return peak


func peak_scent() -> float:
	var peak: float = 0.0
	for i in scent.size():
		if scent[i] > peak:
			peak = scent[i]
	return peak


func clear_field() -> void:
	for i in noise.size():
		noise[i] = 0.0
	for i in scent.size():
		scent[i] = 0.0
	for i in _scent_next.size():
		_scent_next[i] = 0.0

func save() -> Dictionary:
	var n: Array = []
	var s: Array = []
	for i in noise.size():
		var v: float = noise[i]
		if v != 0.0:
			n.append([i, v])
	for i in scent.size():
		var v2: float = scent[i]
		if v2 != 0.0:
			s.append([i, v2])
	return {"cols": cols, "rows": rows, "noise": n, "scent": s}

func restore(saved: Dictionary) -> void:
	assert(int(saved["cols"]) == cols and int(saved["rows"]) == rows, "Field geometry mismatch on restore")
	clear_field()
	for pair in saved.get("noise", []) as Array:
		var p: Array = pair as Array
		noise[int(p[0])] = float(p[1])
	for pair2 in saved.get("scent", []) as Array:
		var p2: Array = pair2 as Array
		scent[int(p2[0])] = float(p2[1])
