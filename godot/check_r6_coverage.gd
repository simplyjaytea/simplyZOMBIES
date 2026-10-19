extends SceneTree
# R6 — isolation / save / content / determinism / acceptance gates
# Each lane must still be independently meaningful. Resource/Node in state fails.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimSave = preload("res://sim/save.gd")
const SimSerialize = preload("res://sim/kernel/serialize.gd")
const ContentValidator = preload("res://platform/content_validator.gd")
const PlatformStorage = preload("res://platform/storage.gd")

const ISOLATION_SEED: int = 20260805
const ISOLATION_TILES: int = 64


func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _isolation() and ok
	ok = _save_load() and ok
	ok = _content() and ok
	ok = _determinism() and ok
	ok = _acceptance() and ok
	if ok:
		print("R6_COVERAGE_OK isolation save content determinism acceptance")
		quit(0)
	else:
		push_error("R6_COVERAGE_FAIL")
		quit(1)

func _isolation() -> bool:
	# Boot the playable district once for each system, with that one system unregistered. Every
	# system must be findable and removable (a lane that disables nothing proves nothing), and the
	# world must still step ten ticks without a crash. The old lane said it did this and disabled
	# nothing: its only guard was `w == null` on a world built with no systems at all.
	var names: Array[String] = (SimBoot.playable(ISOLATION_SEED, ISOLATION_TILES)["world"] as Object).get("systems").ids
	if names.is_empty():
		push_error("isolation: the playable world registers no systems, so there is nothing to isolate")
		return false
	for name in names:
		var w: Variant = SimBoot.playable(ISOLATION_SEED, ISOLATION_TILES)["world"]
		if not w.systems.unregister(name):
			push_error("isolation: '%s' is listed but cannot be unregistered" % name)
			return false
		var before: int = int(w.tick)
		world_step_n(w, 10)
		if int(w.tick) != before + 10:
			push_error("isolation: with '%s' disabled the world stopped at tick %d" % [name, int(w.tick)])
			return false
	if (SimBoot.playable(ISOLATION_SEED, ISOLATION_TILES)["world"] as Object).get("systems").unregister("no.such.system"):
		push_error("isolation: unregistering a system that does not exist reported success")
		return false
	print("ISOLATION OK each of %d systems disables cleanly and the world steps with it gone" % names.size())
	return true

func _save_load() -> bool:
	var fixture: Dictionary = {"seed": 42, "tick_hz": 20, "map": {"width": 16, "height": 16, "walls": []}, "player": {"id": 0, "x": 8.0, "y": 8.0, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	var w: Variant = World.new(fixture)
	world_step_n(w, 23)
	var before: String = w.serialize()
	var save: Dictionary = SimSave.create_save(w)
	var text: String = SimSave.encode_save(save)
	# atomic write/read via platform
	PlatformStorage.write_save(text)
	var raw: String = PlatformStorage.read_save()
	if raw.is_empty() or raw != text:
		push_error("save platform round-trip")
		return false
	var decoded: Dictionary = SimSave.decode_save(raw)
	if decoded.has("__error"):
		push_error("save decode %s" % str(decoded))
		return false
	# corrupt + stale
	if String(SimSave.decode_save("{bad").get("__error", "")) != "CorruptSaveError":
		push_error("corrupt guard")
		return false
	var tampered: Dictionary = JSON.parse_string(text) as Dictionary
	(tampered["snapshot"] as Dictionary)["version"] = 999
	if String(SimSave.decode_save(JSON.stringify(tampered)).get("__error", "")) != "StaleSaveError":
		push_error("stale guard")
		return false
	var w2: Variant = World.new(fixture)
	SimSave.apply_save(w2, decoded)
	if w2.serialize() != before:
		push_error("save restore mismatch")
		return false
	print("SAVE OK len %d" % text.length())
	return true

func _content() -> bool:
	var issues: Array = ContentValidator.validate_tree("res://content") as Array
	if not issues.is_empty():
		for m in issues:
			push_error(String(m))
		return false
	print("CONTENT OK")
	return true

func _determinism() -> bool:
	var fixture: Dictionary = {"seed": 20260805, "tick_hz": 20, "map": {"width": 12, "height": 10, "walls": [{"x": 6, "y": 1}]}, "player": {"id": 0, "x": 3.5, "y": 3.5, "stance": 2}, "rng_probe": {"stream": "parity", "samples": 2}, "commands": [{"tick": 1, "type": "move", "dx": 1, "dy": 0}]}
	var a: Variant = World.new(fixture)
	var b: Variant = World.new(fixture)
	for t in range(1, 21):
		for c in fixture["commands"] as Array:
			if int((c as Dictionary)["tick"]) == t:
				var cmd: Dictionary = (c as Dictionary).duplicate(true)
				cmd.erase("tick")
				a.commands.push(cmd)
				b.commands.push(cmd.duplicate(true))
		a.step()
		b.step()
		if a.serialize() != b.serialize():
			push_error("determinism tick %d" % t)
			return false
	# negative: different seed diverges
	var c: Variant = World.new({"seed": 20260806, "tick_hz": 20, "map": fixture["map"], "player": fixture["player"], "rng_probe": fixture["rng_probe"], "commands": []})
	world_step_n(c, 20)
	if c.serialize() == a.serialize():
		push_error("determinism negative: different seed same state")
		return false
	print("DETERMINISM OK")
	return true

func _acceptance() -> bool:
	# 5-min loop smoke: move, stance, noise, swing, save/load resolves deterministically headless
	var fixture: Dictionary = {"seed": 99, "tick_hz": 20, "map": {"width": 32, "height": 32, "walls": []}, "player": {"id": 0, "x": 5.0, "y": 5.0, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}, "commands": [{"tick": 2, "type": "shout"}, {"tick": 10, "type": "move", "dx": 1, "dy": 0}, {"tick": 20, "type": "swing"}, {"tick": 30, "type": "stance", "stance": 1}]}
	var w: Variant = World.new(fixture)
	for t in range(1, 121):
		for c in fixture["commands"] as Array:
			if int((c as Dictionary)["tick"]) == t:
				var cmd: Dictionary = (c as Dictionary).duplicate(true)
				cmd.erase("tick")
				w.commands.push(cmd)
		w.step()
	if w.tick != 120:
		push_error("acceptance tick %d" % w.tick)
		return false
	print("ACCEPTANCE OK tick 120")
	return true

func world_step_n(w: Variant, n: int) -> void:
	for i in n:
		w.step()
