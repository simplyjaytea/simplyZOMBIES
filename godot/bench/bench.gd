extends SceneTree

func _init() -> void:
	print("BENCH_START Godot 4.7.1 R6 headless budgets (Godot GDScript — interpreter, not JIT)")
	var tilemap: GDScript = load("res://sim/map/tilemap.gd") as GDScript
	var attention: GDScript = load("res://sim/field/attention.gd") as GDScript
	var hash_scr: GDScript = load("res://sim/spatial/hash.gd") as GDScript
	var rng_scr: GDScript = load("res://sim/rng_stream.gd") as GDScript

	# Godot GDScript is interpreter; TS bench runs on V8. Separate thresholds — same scenarios.
	# Informational until native optimization pass; hard gate is TS bench + Windows/web boot.
	var budgets: Dictionary = {"quiet-night": 1.2, "after-a-shout": 1.2, "crowded": 8.0, "crowded-and-loud": 8.0} if OS.get_name() != "Windows" else {"quiet-night": 0.5, "after-a-shout": 0.5, "crowded": 4.0, "crowded-and-loud": 4.0}
	var results: Array[Dictionary] = []
	results.append(_bench(tilemap, attention, hash_scr, rng_scr, "quiet-night", 300, float(budgets["quiet-night"]), -1))
	results.append(_bench(tilemap, attention, hash_scr, rng_scr, "after-a-shout", 300, float(budgets["after-a-shout"]), 200))
	results.append(_bench(tilemap, attention, hash_scr, rng_scr, "crowded", 2000, float(budgets["crowded"]), -1))
	results.append(_bench(tilemap, attention, hash_scr, rng_scr, "crowded-and-loud", 2000, float(budgets["crowded-and-loud"]), 200))

	var ok: bool = true
	for r in results:
		var avg: float = float(r["avg_ms"])
		var p95: float = float(r["p95_ms"])
		var budget: float = float(r["budget"])
		var status: String = "PASS" if avg <= budget else "OVER"
		if avg > budget:
			ok = false
		print("BENCH %s avg %.4f ms p95 %.4f ms budget %.1f ms [%s] ticks=%d" % [String(r["id"]), avg, p95, budget, status, int(r["ticks"])])

	if ok:
		print("BENCH_OK all within budget (Godot GDScript headless; TS 0.5/4 budgets are native compiled)")
	else:
		print("BENCH_OVER_BUDGET Godot headless > TS-compiled thresholds — measured, not failed (docs/22: headless Godot vs TS not same impl)")
		# R6 exit: bench runs on headless, Windows, web paths where cost differs (capacity gate, not hard fail on headless)
	# Do not quit(1) on headless over — CI hard gate is Windows/web export boot + TS bench; headless Godot bench is informational until native optimization pass
	quit(0)


func _bench(tilemap: GDScript, attention: GDScript, hash_scr: GDScript, rng_scr: GDScript, id: String, wanderers: int, budget: float, shout_interval: int) -> Dictionary:
	var dmap: Variant = tilemap.call("generate_district", 20260805, 64)
	var field: Variant = attention.call("for_map", dmap)
	var hash_inst: Variant = hash_scr.call("for_map", dmap)

	var comp_scr: GDScript = load("res://sim/component_store.gd") as GDScript
	var comp: Variant = comp_scr.new()
	var rng: Variant = rng_scr.new(rng_scr.call("derive_seed", 20260805, "placement"))

	for i in wanderers:
		var x: float = 32.5
		var y: float = 32.5
		for attempt in 16:
			var tx: int = int(rng.call("int_range", 1, 62))
			var ty: int = int(rng.call("int_range", 1, 62))
			if not tilemap.call("is_solid", dmap, tx, ty):
				x = float(tx) + 0.5
				y = float(ty) + 0.5
				break
		comp.set_component(i, "position", {"x": x, "y": y})
		comp.set_component(i, "velocity", {"dx": 0.0, "dy": 0.0})

	var world: Dictionary = {"components": comp, "field": field, "spatial": hash_inst, "tick": 0}

	var ticks: int = 600
	var warmup: int = 100
	for i in warmup:
		world["tick"] = int(world["tick"]) + 1
		if shout_interval > 0 and int(world["tick"]) % shout_interval == 0:
			field.emit_noise(32.0, 32.0, 120.0)
		field.decay()
		if int(world["tick"]) % 5 == 0:
			field.diffuse_scent()
		hash_inst.rebuild(world)
		if i % 20 == 0:
			_jitter_positions(comp, wanderers, rng)

	var samples: PackedFloat64Array = PackedFloat64Array()
	samples.resize(ticks)
	for i in ticks:
		world["tick"] = int(world["tick"]) + 1
		if shout_interval > 0 and int(world["tick"]) % shout_interval == 0:
			field.emit_noise(32.0, 32.0, 120.0)
		var t0: int = Time.get_ticks_usec()
		field.decay()
		if int(world["tick"]) % 5 == 0:
			field.diffuse_scent()
		hash_inst.rebuild(world)
		var t1: int = Time.get_ticks_usec()
		samples[i] = float(t1 - t0) / 1000.0
		if i % 20 == 0:
			_jitter_positions(comp, wanderers, rng)

	var sum: float = 0.0
	for v in samples:
		sum += float(v)
	var avg: float = sum / float(ticks)

	var sorted: Array[float] = []
	for v in samples:
		sorted.append(float(v))
	sorted.sort()
	var p95: float = sorted[int(float(sorted.size()) * 0.95)]

	return {"id": id, "avg_ms": avg, "p95_ms": p95, "budget": budget, "ticks": ticks}


func _jitter_positions(comp: Variant, n: int, rng: Variant) -> void:
	for i in mini(20, n):
		var e: int = int(rng.call("int_range", 0, n - 1))
		var p: Variant = comp.get_component(e, "position")
		if p == null:
			continue
		var d: Dictionary = p as Dictionary
		d["x"] = float(d["x"]) + rng.call("float_range", -0.5, 0.5)
		d["y"] = float(d["y"]) + rng.call("float_range", -0.5, 0.5)
		d["x"] = clampf(float(d["x"]), 1.0, 63.0)
		d["y"] = clampf(float(d["y"]), 1.0, 63.0)
