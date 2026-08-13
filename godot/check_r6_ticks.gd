extends SceneTree
# R6 — per-tick parity: shared seed + command log through both engines,
# compare canonical snapshots AFTER EVERY RELEVANT TICK, not only at end.
# Runs headless Godot side; compares against TS oracle's per-tick stream if present,
# else self-checks Godot determinism tick-by-tick (catches non-deterministic step).

const World = preload("res://sim/world.gd")
const SimSerialize = preload("res://sim/kernel/serialize.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var opts := _opts(OS.get_cmdline_user_args())
	var fixture_path: String = String(opts.get("fixture", "res://parity/r1-walking-skeleton.json"))
	var ticks_path: String = String(opts.get("ticks", "")) # optional TS per-tick canonicals JSON
	var fixture := _read_json(fixture_path)
	if fixture.is_empty():
		push_error("r6 ticks: fixture missing %s" % fixture_path)
		quit(2)
		return
	var expected_ticks: Array = []
	if not ticks_path.is_empty():
		var j := _read_json(ticks_path)
		if j.has("ticks"):
			expected_ticks = j["ticks"] as Array

	var snapshots: Array[String] = []
	var world: Variant = World.new(fixture)
	var by_tick: Dictionary = {}
	for c in fixture.get("commands", []) as Array:
		var d: Dictionary = c as Dictionary
		var at: int = int(d.get("tick", 0))
		var cmd: Dictionary = d.duplicate(true)
		cmd.erase("tick")
		if not by_tick.has(at):
			by_tick[at] = []
		(by_tick[at] as Array).append(cmd)

	var total: int = int(fixture.get("ticks", 0))
	for t in range(1, total + 1):
		for cmd in by_tick.get(t, []) as Array:
			world.commands.push(cmd as Dictionary)
		world.step()
		var canon: String = SimSerialize.canonicalize(world.snapshot())
		snapshots.append(canon)
		if expected_ticks.size() > 0:
			var exp: String = String(expected_ticks[t - 1]) if t - 1 < expected_ticks.size() else ""
			if not exp.is_empty() and exp != canon:
				push_error("tick %d differs\n expected %s\n actual   %s" % [t, exp.substr(0, 120), canon.substr(0, 120)])
				quit(1)
				return
			if exp.is_empty():
				push_warning("no expected for tick %d" % t)

	# self-determinism: replay and compare
	var world2: Variant = World.new(fixture)
	for t in range(1, total + 1):
		for cmd in by_tick.get(t, []) as Array:
			world2.commands.push(cmd as Dictionary)
		world2.step()
		var c2: String = SimSerialize.canonicalize(world2.snapshot())
		if c2 != snapshots[t - 1]:
			push_error("non-deterministic replay at tick %d" % t)
			quit(1)
			return

	print("R6_TICK_PARITY_OK %d ticks%s" % [total, " vs oracle" if not expected_ticks.is_empty() else " (self)"])
	quit(0)

func _opts(args: PackedStringArray) -> Dictionary:
	var r: Dictionary = {}
	var i := 0
	while i < args.size():
		var a := String(args[i])
		if a.begins_with("--") and i + 1 < args.size():
			r[a.trim_prefix("--")] = args[i + 1]
			i += 2
		else:
			i += 1
	return r

func _read_json(path: String) -> Dictionary:
	if path.is_empty():
		return {}
	var f: Variant = null
	if path.begins_with("res://"):
		f = FileAccess.open(path, FileAccess.READ)
		if f == null:
			return {}
	else:
		f = FileAccess.open(path, FileAccess.READ)
		if f == null:
			# try as res:// relative
			f = FileAccess.open("res://" + path, FileAccess.READ)
			if f == null:
				return {}
	var v: Variant = JSON.parse_string((f as FileAccess).get_as_text())
	return v as Dictionary if v is Dictionary else {}
