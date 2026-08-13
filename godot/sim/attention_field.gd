class_name SimAttentionField
extends RefCounted

# Keep in sync with src/sim/field/attention.ts
# ponytail: calibration as Dictionary; upgrade to typed Resource when content registry lands.

const CALIBRATION_ID: String = "calibration.attention"

const DEFAULT_CALIBRATION: Dictionary = {
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

var cols: int
var rows: int
var cellMetres: float
var calibration: Dictionary

var noise: PackedFloat32Array
var scent: PackedFloat32Array
var _solid: PackedByteArray
var _staged: PackedFloat32Array
var _queue: PackedInt32Array
var _queued: PackedByteArray
var _touched: PackedInt32Array
var _scent_next: PackedFloat32Array

var lastEmitCells: int = 0

var _step_cost: float
var _diagonal_cost: float
var _wall_cost: float
var _decay_per_tick: float
var _wind_weights: PackedFloat32Array
var _scent_decay_per_step: float


func _init(cols_: int, rows_: int, solid_: PackedByteArray, calibration_: Dictionary, tick_hz: int = 20) -> void:
	cols = cols_
	rows = rows_
	cellMetres = float(calibration_["cellMetres"])
	calibration = calibration_
	_solid = solid_
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
	_step_cost = float(calibration["cellMetres"]) * float(calibration["attenuationPerMetre"])
	_diagonal_cost = _step_cost * sqrt(2.0)
	_wall_cost = float(calibration["wallPenaltyMetres"]) * float(calibration["attenuationPerMetre"])
	_decay_per_tick = pow(0.5, 1.0 / (float(calibration["noiseHalfLifeSeconds"]) * float(tick_hz)))
	var scent_interval: int = maxi(1, int(round(float(calibration["scentIntervalTicks"]))))
	var steps_per_half_life: float = (float(calibration["scentHalfLifeMinutes"]) * 60.0 * float(tick_hz)) / float(scent_interval)
	_scent_decay_per_step = pow(0.5, 1.0 / steps_per_half_life)
	var raw_xp: float = maxf(0.0, 1.0 + float(calibration["windX"]))
	var raw_xn: float = maxf(0.0, 1.0 - float(calibration["windX"]))
	var raw_yp: float = maxf(0.0, 1.0 + float(calibration["windY"]))
	var raw_yn: float = maxf(0.0, 1.0 - float(calibration["windY"]))
	var total: float = raw_xp + raw_xn + raw_yp + raw_yn
	_wind_weights = PackedFloat32Array([raw_xp / total, raw_xn / total, raw_yp / total, raw_yn / total])


static func for_map(map: Dictionary, calibration_: Dictionary = DEFAULT_CALIBRATION, tick_hz: int = 20) -> Variant:
	var TileMapScript: Variant = load("res://sim/tilemap.gd")
	var per: int = maxi(1, int(round(float(calibration_["cellMetres"]))))
	var w: int = int(map["w"])
	var h: int = int(map["h"])
	var c: int = ceili(float(w) / float(per))
	var r: int = ceili(float(h) / float(per))
	var solid: PackedByteArray = PackedByteArray()
	solid.resize(c * r)
	for cy: int in range(r):
		for cx: int in range(c):
			var all: bool = true
			for ty: int in range(per):
				if not all:
					break
				for tx: int in range(per):
					if not TileMapScript.is_solid(map, cx * per + tx, cy * per + ty):
						all = false
						break
			solid[cy * c + cx] = 1 if all else 0
	return load("res://sim/attention_field.gd").new(c, r, solid, calibration_, tick_hz)


static func empty(calibration_: Dictionary = DEFAULT_CALIBRATION, tick_hz: int = 20) -> Variant:
	return load("res://sim/attention_field.gd").new(0, 0, PackedByteArray(), calibration_, tick_hz)


func get_cell_count() -> int:
	return cols * rows


func cell_at(x: float, y: float) -> int:
	if cols * rows == 0:
		return -1
	var cx: int = clampi(floori(x / cellMetres), 0, cols - 1)
	var cy: int = clampi(floori(y / cellMetres), 0, rows - 1)
	return cy * cols + cx


func is_solid(cell: int) -> bool:
	return _solid[cell] == 1


func noise_at(x: float, y: float) -> float:
	var cell: int = cell_at(x, y)
	if cell == -1:
		return 0.0
	return noise[cell]


func scent_at(x: float, y: float) -> float:
	var cell: int = cell_at(x, y)
	if cell == -1:
		return 0.0
	return scent[cell]


func emit_noise(x: float, y: float, magnitude: float) -> void:
	lastEmitCells = 0
	var start: int = cell_at(x, y)
	if start == -1 or magnitude < float(calibration["floor"]):
		return
	var floor_val: float = float(calibration["floor"])
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
		if value < floor_val:
			continue
		var cx: int = cell % cols
		var cy: int = (cell - cx) / cols
		for dy: int in range(-1, 2):
			var ny: int = cy + dy
			if ny < 0 or ny >= rows:
				continue
			for dx: int in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nx: int = cx + dx
				if nx < 0 or nx >= cols:
					continue
				var nxt: int = ny * cols + nx
				var cost: float = _diagonal_cost if (dx != 0 and dy != 0) else _step_cost
				if _solid[nxt] == 1:
					cost += _wall_cost
				var arriving: float = value - cost
				if arriving < floor_val:
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
	for i: int in range(n_touched):
		var cell2: int = _touched[i]
		if _staged[cell2] > noise[cell2]:
			noise[cell2] = _staged[cell2]
		_staged[cell2] = 0.0
	lastEmitCells = n_touched


func add_scent(x: float, y: float, magnitude: float) -> void:
	var cell: int = cell_at(x, y)
	if cell == -1 or magnitude <= 0.0:
		return
	var total: float = scent[cell] + magnitude
	var ceiling: float = float(calibration["scentCeiling"])
	scent[cell] = ceiling if total > ceiling else total


func diffuse_scent() -> void:
	var scent_floor: float = float(calibration["scentFloor"])
	var rate: float = float(calibration["scentDiffusionRate"])
	var keep: float = 1.0 - rate
	var w_px: float = _wind_weights[0]
	var w_nx: float = _wind_weights[1]
	var w_py: float = _wind_weights[2]
	var w_ny: float = _wind_weights[3]
	for cy: int in range(rows):
		for cx: int in range(cols):
			var here: int = cy * cols + cx
			var value: float = scent[here] * keep
			if cx + 1 < cols:
				value += scent[here + 1] * rate * w_nx
			if cx - 1 >= 0:
				value += scent[here - 1] * rate * w_px
			if cy + 1 < rows:
				value += scent[here + cols] * rate * w_ny
			if cy - 1 >= 0:
				value += scent[here - cols] * rate * w_py
			var decayed: float = value * _scent_decay_per_step
			_scent_next[here] = 0.0 if decayed < scent_floor else decayed
	for i: int in range(scent.size()):
		scent[i] = _scent_next[i]


func decay() -> void:
	var floor_val: float = float(calibration["floor"])
	for i: int in range(noise.size()):
		var value: float = noise[i]
		if value == 0.0:
			continue
		var decayed: float = value * _decay_per_tick
		noise[i] = 0.0 if decayed < floor_val else decayed


func uphill_noise(x: float, y: float) -> Variant:
	return _uphill(noise, x, y)


func uphill_scent(x: float, y: float) -> Variant:
	return _uphill(scent, x, y)


func _uphill(layer: PackedFloat32Array, x: float, y: float) -> Variant:
	var here: int = cell_at(x, y)
	if here == -1:
		return null
	var cx: int = here % cols
	var cy: int = (here - cx) / cols
	var best: float = layer[here]
	var best_dx: int = 0
	var best_dy: int = 0
	for dy: int in range(-1, 2):
		var ny: int = cy + dy
		if ny < 0 or ny >= rows:
			continue
		for dx: int in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx: int = cx + dx
			if nx < 0 or nx >= cols:
				continue
			var nxt: int = ny * cols + nx
			if _solid[nxt] == 1:
				continue
			var v: float = layer[nxt]
			if v > best:
				best = v
				best_dx = dx
				best_dy = dy
	if best_dx == 0 and best_dy == 0:
		return null
	return {"dx": best_dx, "dy": best_dy, "value": best}


func live_cells() -> int:
	var n: int = 0
	for i: int in range(noise.size()):
		if noise[i] != 0.0:
			n += 1
	return n


func live_scent_cells() -> int:
	var n: int = 0
	for i: int in range(scent.size()):
		if scent[i] != 0.0:
			n += 1
	return n


func peak_noise() -> float:
	var peak: float = 0.0
	for i: int in range(noise.size()):
		if noise[i] > peak:
			peak = noise[i]
	return peak


func peak_scent() -> float:
	var peak: float = 0.0
	for i: int in range(scent.size()):
		if scent[i] > peak:
			peak = scent[i]
	return peak


func clear() -> void:
	for i: int in range(noise.size()):
		noise[i] = 0.0
	for i: int in range(scent.size()):
		scent[i] = 0.0
	for i: int in range(_scent_next.size()):
		_scent_next[i] = 0.0


func save() -> Dictionary:
	return {"cols": cols, "rows": rows, "noise": _sparse(noise), "scent": _sparse(scent)}


func restore(saved: Dictionary) -> void:
	if int(saved["cols"]) != cols or int(saved["rows"]) != rows:
		push_error("Attention field %dx%d but save is %dx%d" % [cols, rows, int(saved["cols"]), int(saved["rows"])])
		return
	clear()
	_fill(noise, saved["noise"])
	_fill(scent, saved["scent"])


func _sparse(layer: PackedFloat32Array) -> Array:
	var live: Array = []
	for i: int in range(layer.size()):
		if layer[i] != 0.0:
			live.append([i, layer[i]])
	return live


func _fill(layer: PackedFloat32Array, saved: Array) -> void:
	for entry: Variant in saved:
		var pair: Array = entry
		var cell: int = int(pair[0])
		var value: float = float(pair[1])
		layer[cell] = value
