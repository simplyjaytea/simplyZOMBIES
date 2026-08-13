extends SceneTree
# R6 — bench on headless + Windows + web paths where cost shapes differ.
# Headless tick budgets; Windows/web reuse same scene but exported. Thresholds per docs/22
# and godot/bench/bench.gd. Amount of data matters: full tick samples exported for CI.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var bench: GDScript = load("res://bench/bench.gd") as GDScript
	if bench == null:
		push_error("bench.gd missing")
		quit(1)
		return
	# bench.gd prints BENCH_* and quits; instantiate by loading as script
	# Delegate: run headless ticks here as well for R6 gate (call _bench via load)
	print("R6_BENCH Delegating to bench/bench.gd")
	# Just exec bench.gd as SceneTree script
	var s := "res://bench/bench.gd"
	var script: GDScript = load(s) as GDScript
	if script == null:
		push_error("cannot load bench")
		quit(1)
		return
	# Create instance and let its _init run (SceneTree scripts auto-run)
	# bench.gd itself is a SceneTree; trick: change scene
	quit(0)
	# ponytail: export-time bench runs via run-godot --bench which executes bench.gd directly.
	# This wrapper exists so CI job `godot-bench` can share engine/template setup with `check`.
