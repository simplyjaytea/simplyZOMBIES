extends Node
# Alpha SFX — presentation only. Sim stays mute (ticket 12).
# Picks: Q1:A committed WAVs · Q2:B camera listener · Q3:B bow clip ·
# Q4:B oneshot pool · Q5:B stop/restart bait by reach · Q6:A no gate.

const FALL_PER_M: float = 0.7
const REF_MAG: float = 180.0
const POOL: int = 3

const PATHS: Dictionary = {
	"shout": "res://assets/sfx/shout.wav",
	"gunshot": "res://assets/sfx/gunshot.wav",
	"bow": "res://assets/sfx/bow.wav",
	"board": "res://assets/sfx/board.wav",
	"alarm": "res://assets/sfx/alarm.wav",
	"noisemaker": "res://assets/sfx/noisemaker.wav",
}

var _oneshots: Array[AudioStreamPlayer] = []
var _loop: AudioStreamPlayer = null
var _streams: Dictionary = {}
var _pool_i: int = 0
var _constructing: Dictionary = {} # entity -> true while channeling
var _bait_was_in_reach: bool = false
var _hud: Label = null
var _hud_until_ms: int = 0


func _ready() -> void:
	for _i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_oneshots.append(p)
	_loop = AudioStreamPlayer.new()
	add_child(_loop)
	for key in PATHS.keys():
		var stream: Variant = _load_wav(String(PATHS[key]))
		if stream != null:
			_streams[key] = stream
	_hud = Label.new()
	_hud.name = "SfxHud"
	_hud.position = Vector2(8, 500)
	_hud.add_theme_font_size_override("font_size", 14)
	_hud.add_theme_color_override("font_color", Color(1.0, 0.92, 0.4))
	_hud.text = "SFX: (waiting)"
	var layer := CanvasLayer.new()
	layer.name = "SfxHudLayer"
	layer.layer = 20
	add_child(layer)
	layer.add_child(_hud)


func _flash(clip: String, vol: float) -> void:
	if _hud == null:
		return
	_hud.text = "SFX: %s  vol=%.2f" % [clip, vol]
	_hud_until_ms = Time.get_ticks_msec() + 2500
	print("SFX_PLAY %s vol=%.2f" % [clip, vol])


func _load_wav(path: String) -> Variant:
	# Runtime PCM load — avoids needing editor-generated .import for CI/export.
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var bytes: PackedByteArray = f.get_buffer(int(f.get_length()))
	f.close()
	if bytes.size() < 44:
		return null
	var channels: int = bytes[22] | (bytes[23] << 8)
	var rate: int = bytes[24] | (bytes[25] << 8) | (bytes[26] << 16) | (bytes[27] << 24)
	var bits: int = bytes[34] | (bytes[35] << 8)
	var data_off: int = 12
	while data_off + 8 <= bytes.size():
		var chunk_id: String = (
			char(bytes[data_off])
			+ char(bytes[data_off + 1])
			+ char(bytes[data_off + 2])
			+ char(bytes[data_off + 3])
		)
		var chunk_size: int = (
			bytes[data_off + 4]
			| (bytes[data_off + 5] << 8)
			| (bytes[data_off + 6] << 16)
			| (bytes[data_off + 7] << 24)
		)
		if chunk_id == "data":
			var end: int = mini(bytes.size(), data_off + 8 + chunk_size)
			var pcm: PackedByteArray = bytes.slice(data_off + 8, end)
			var stream := AudioStreamWAV.new()
			stream.format = AudioStreamWAV.FORMAT_16_BITS if bits == 16 else AudioStreamWAV.FORMAT_8_BITS
			stream.mix_rate = rate
			stream.stereo = channels > 1
			stream.data = pcm
			return stream
		data_off += 8 + chunk_size
		if chunk_size < 0:
			break
	return null


func tick(world: Variant, camera: Dictionary, drained: Array) -> void:
	if world == null:
		return
	if _hud != null and Time.get_ticks_msec() > _hud_until_ms and not String(_hud.text).begins_with("SFX: (waiting)"):
		if not String(_hud.text).begins_with("SFX: noisemaker"):
			_hud.text = "SFX: —"
	var lx: float = float(camera.get("x", 0.0))
	var ly: float = float(camera.get("y", 0.0))
	_oneshots_from_events(world, drained, lx, ly)
	_board_on_construct_start(world, lx, ly)
	_noisemaker_loop(world, lx, ly)


func _oneshots_from_events(world: Variant, drained: Array, lx: float, ly: float) -> void:
	for e in drained:
		if not e is Dictionary:
			continue
		var ev: Dictionary = e as Dictionary
		var kind: String = String(ev.get("type", ""))
		if kind == "alarm.tripped":
			var ax: float = lx
			var ay: float = ly
			var alarms: Array[int] = world.components.query(["alarmLine"])
			if not alarms.is_empty():
				var line: Variant = world.components.get_component(alarms[0], "alarmLine")
				if line is Dictionary:
					var cells: Array = (line as Dictionary).get("cells", []) as Array
					if not cells.is_empty() and cells[0] is Dictionary:
						ax = float((cells[0] as Dictionary).get("x", lx)) + 0.5
						ay = float((cells[0] as Dictionary).get("y", ly)) + 0.5
			_play_oneshot("alarm", 8.0, ax, ay, lx, ly)
			continue
		if kind != "noise.emitted":
			continue
		var mag: float = float(ev.get("magnitude", 0.0))
		var x: float = float(ev.get("x", lx))
		var y: float = float(ev.get("y", ly))
		# Construction 30 is one-shot on channel start (see _board_on_construct_start).
		if absf(mag - 30.0) < 0.01:
			continue
		if absf(mag - 180.0) < 0.01:
			_play_oneshot("gunshot", mag, x, y, lx, ly)
		elif absf(mag - 120.0) < 0.01:
			_play_oneshot("shout", mag, x, y, lx, ly)
		elif absf(mag - 4.0) < 0.01:
			_play_oneshot("bow", mag, x, y, lx, ly)


func _board_on_construct_start(world: Variant, lx: float, ly: float) -> void:
	var live: Dictionary = {}
	for ent in world.components.query(["construct", "position"]):
		var id: int = int(ent)
		live[id] = true
		if _constructing.has(id):
			continue
		_constructing[id] = true
		var pos: Variant = world.components.get_component(id, "position")
		var x: float = lx
		var y: float = ly
		if pos is Dictionary:
			x = float((pos as Dictionary)["x"])
			y = float((pos as Dictionary)["y"])
		_play_oneshot("board", 30.0, x, y, lx, ly)
	for id in _constructing.keys():
		if not live.has(id):
			_constructing.erase(id)


func _noisemaker_loop(world: Variant, lx: float, ly: float) -> void:
	var stream: Variant = _streams.get("noisemaker")
	if stream == null or _loop == null:
		return
	var mag: float = 45.0
	var reach: float = mag / FALL_PER_M
	var active: bool = false
	var bx: float = lx
	var by: float = ly
	for ent in world.components.query(["noisemaker", "position"]):
		var nm: Variant = world.components.get_component(int(ent), "noisemaker")
		if not nm is Dictionary:
			continue
		if int(world.tick) >= int((nm as Dictionary).get("expiresAtTick", 0)):
			continue
		var pos: Variant = world.components.get_component(int(ent), "position")
		if pos is Dictionary:
			bx = float((pos as Dictionary)["x"])
			by = float((pos as Dictionary)["y"])
		active = true
		break
	var dist: float = sqrt((bx - lx) * (bx - lx) + (by - ly) * (by - ly))
	var in_reach: bool = active and dist <= reach
	if in_reach:
		var vol: float = _vol(mag, dist)
		_loop.volume_db = linear_to_db(maxf(0.0001, vol))
		if not _bait_was_in_reach or not _loop.playing:
			if stream is AudioStreamWAV:
				var wav: AudioStreamWAV = stream as AudioStreamWAV
				wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
				var bytes_per_sample: int = 2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1
				var num_channels: int = 2 if wav.stereo else 1
				wav.loop_end = wav.data.size() / (bytes_per_sample * num_channels)
			_loop.stream = stream as AudioStream
			_loop.play()
			_flash("noisemaker", vol)
		elif _hud != null:
			_hud.text = "SFX: noisemaker  vol=%.2f  (loop)" % vol
		_bait_was_in_reach = true
	else:
		if _loop.playing:
			_loop.stop()
		_bait_was_in_reach = false


func _play_oneshot(key: String, mag: float, x: float, y: float, lx: float, ly: float) -> void:
	var stream: Variant = _streams.get(key)
	if stream == null or _oneshots.is_empty():
		return
	var dist: float = sqrt((x - lx) * (x - lx) + (y - ly) * (y - ly))
	var vol: float = _vol(mag, dist)
	if vol <= 0.0:
		return
	var p: AudioStreamPlayer = _oneshots[_pool_i]
	_pool_i = (_pool_i + 1) % _oneshots.size()
	p.stream = stream as AudioStream
	p.volume_db = linear_to_db(maxf(0.0001, vol))
	p.play()
	_flash(key, vol)


func _vol(mag: float, dist: float) -> float:
	if mag <= 0.0:
		return 0.0
	var base: float = clampf(mag / REF_MAG, 0.0, 1.0)
	var fall: float = clampf(1.0 - dist * FALL_PER_M / mag, 0.0, 1.0)
	return base * fall
