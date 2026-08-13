extends SceneTree
# R6 — soak: memory growth / save corruption / input loss / pause-resume / tab focus.
# Long runs headless; no UI needed — only sim correctness.

const World = preload("res://sim/world.gd")
const SimSave = preload("res://sim/save.gd")
const SimSerialize = preload("res://sim/kernel/serialize.gd")
const PlatformStorage = preload("res://platform/storage.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _soak_memory() and ok
	ok = _soak_save_corruption() and ok
	ok = _soak_input_loss() and ok
	ok = _soak_pause_resume() and ok
	ok = _soak_tab_focus() and ok
	if ok:
		print("R6_SOAK_OK memory save input pause tab")
		quit(0)
	else:
		push_error("R6_SOAK_FAIL")
		quit(1)

func _soak_memory() -> bool:
	var fixture: Dictionary = {"seed": 20260805, "tick_hz": 20, "map": {"width": 32, "height": 32, "walls": []}, "player": {"id": 0, "x": 10.0, "y": 10.0, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}, "commands": []}
	var w: Variant = World.new(fixture)
	var base_mem: int = OS.get_static_memory_usage()
	for i in 5000:
		w.step()
		if i % 500 == 0:
			w.commands.push({"type": "move", "dx": 0.1, "dy": 0.0})
		if i % 1000 == 0:
			# serialize size should be bounded (no leak in snapshot)
			var s: String = w.serialize()
			if s.length() > 500000:
				push_error("soak memory: serialize grew unbounded %d" % s.length())
				return false
	var end_mem: int = OS.get_static_memory_usage()
	var growth: int = end_mem - base_mem
	# Allow growth but not leak: < 50 MB over 5k ticks
	if growth > 50 * 1024 * 1024:
		push_error("soak memory: grew %d bytes" % growth)
		return false
	print("SOAK memory OK ticks %d growth %d bytes" % [w.tick, growth])
	return true

func _soak_save_corruption() -> bool:
	var fixture: Dictionary = {"seed": 55, "tick_hz": 20, "map": {"width": 16, "height": 16, "walls": []}, "player": {"id": 0, "x": 5.0, "y": 5.0, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	var w: Variant = World.new(fixture)
	for i in 100:
		w.step()
	var save: Dictionary = SimSave.create_save(w)
	var text: String = SimSave.encode_save(save)
	# corrupt: truncated
	var trunc: String = text.substr(0, text.length() / 2)
	var bad: Dictionary = SimSave.decode_save(trunc)
	if not bad.has("__error"):
		push_error("soak save: truncated should be error")
		return false
	# corrupt: bad version
	var tampered: Dictionary = JSON.parse_string(text) as Dictionary
	(tampered["snapshot"] as Dictionary)["version"] = 999
	if String(SimSave.decode_save(JSON.stringify(tampered)).get("__error", "")) != "StaleSaveError":
		push_error("soak save: stale not caught")
		return false
	# atomic: write via platform, read back, restore, verify tick
	PlatformStorage.write_save(text)
	var raw: String = PlatformStorage.read_save()
	var decoded: Dictionary = SimSave.decode_save(raw)
	if decoded.has("__error"):
		push_error("soak save: platform round-trip")
		return false
	var w2: Variant = World.new(fixture)
	SimSave.apply_save(w2, decoded)
	if w2.tick != w.tick or w2.serialize() != w.serialize():
		push_error("soak save: restore mismatch")
		return false
	print("SOAK save OK")
	return true

func _soak_input_loss() -> bool:
	# input queued at tick N must be consumed exactly at N, not lost or duplicated
	var fixture: Dictionary = {"seed": 7, "tick_hz": 20, "map": {"width": 12, "height": 10, "walls": []}, "player": {"id": 0, "x": 3.5, "y": 3.5, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	var w: Variant = World.new(fixture)
	# queue 10 moves, one per tick
	for t in range(1, 11):
		w.commands.push({"type": "move", "dx": 0.1, "dy": 0.0})
		w.step()
	if w.tick != 10:
		push_error("soak input tick %d" % w.tick)
		return false
	# commands recorded should be 10
	if w.commands.recorded.size() != 10:
		push_error("soak input recorded %d" % w.commands.recorded.size())
		return false
	print("SOAK input OK")
	return true

func _soak_pause_resume() -> bool:
	var fixture: Dictionary = {"seed": 9, "tick_hz": 20, "map": {"width": 12, "height": 10, "walls": []}, "player": {"id": 0, "x": 3.5, "y": 3.5, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	var w: Variant = World.new(fixture)
	for i in 20:
		w.step()
	var snap: Dictionary = w.snapshot()
	var before: String = SimSerialize.canonicalize(snap)
	# pause: don't step, then resume — snapshot should resume identically
	# (sim has no real time, so pause is just not calling step)
	var w2: Variant = World.new(fixture)
	w2.restore(snap)
	for i in 20:
		w2.step()
	var w_expected: Variant = World.new(fixture)
	for i in 40:
		w_expected.step()
	if w2.serialize() != w_expected.serialize():
		push_error("soak pause: resume diverged")
		return false
	print("SOAK pause OK")
	return true

func _soak_tab_focus() -> bool:
	# tab focus: world should be deterministic across pause-like gaps (engine inactive)
	# Simulate: run 20 ticks, snapshot, restore on "refocus", run 20 more — same as 40 straight.
	var fixture: Dictionary = {"seed": 13, "tick_hz": 20, "map": {"width": 12, "height": 10, "walls": []}, "player": {"id": 0, "x": 3.5, "y": 3.5, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	var straight: Variant = World.new(fixture)
	for i in 40:
		straight.step()
	var refocus: Variant = World.new(fixture)
	for i in 20:
		refocus.step()
	var snap: Dictionary = refocus.snapshot()
	var resumed: Variant = World.new(fixture)
	resumed.restore(snap)
	for i in 20:
		resumed.step()
	if resumed.serialize() != straight.serialize():
		push_error("soak tab: refocus diverged")
		return false
	print("SOAK tab OK")
	return true
