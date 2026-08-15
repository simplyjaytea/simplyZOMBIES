extends SceneTree
# Slice director: day-1 shamblers only, day-8 edge packet, never the gate, lull after breach.

const SimBoot = preload("res://sim/boot.gd")
const Clock = preload("res://sim/time/clock.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const SimDirector = preload("res://sim/modules/director.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _day1_boot() and ok
	ok = _day8_packet() and ok
	ok = _never_gate() and ok
	ok = _lull_skips() and ok
	ok = _same_seed() and ok
	if ok:
		print("M2_DIRECTOR_OK boot packet gate lull seed")
		quit(0)
	else:
		push_error("M2_DIRECTOR_FAIL")
		quit(1)

func _boot() -> Dictionary:
	return SimBoot.playable(20260805, 64)

func _jump_dusk(world: Variant, day: int) -> void:
	world.tick = Clock.tick_on_day(day, Clock.DAY_ENDS) - 1
	world.step()

func _live(world: Variant) -> int:
	return world.components.query(["shambler"]).size()

func _edge_new(world: Variant, before: Array[int]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for e in world.components.query(["shambler", "position"]):
		if before.has(int(e)):
			continue
		var pos: Variant = world.components.get_component(int(e), "position")
		if not pos is Dictionary:
			continue
		out.append(Vector2i(floori(float((pos as Dictionary)["x"])), floori(float((pos as Dictionary)["y"]))))
	return out

func _ids(world: Variant) -> Array[int]:
	return world.components.query(["shambler"])

func _day1_boot() -> bool:
	var boot: Dictionary = _boot()
	var w: Variant = boot["world"]
	var s: int = 0
	var other: int = 0
	for e in w.components.query(["shambler"]):
		var zt: Variant = w.components.get_component(int(e), "zombieType")
		var id: String = String((zt as Dictionary).get("id", "")) if zt is Dictionary else ""
		if id == "zombie.shambler":
			s += 1
		else:
			other += 1
	if s != 12 or other != 0:
		push_error("day1 z shambler=%d other=%d" % [s, other])
		return false
	var before: int = _live(w)
	_jump_dusk(w, 1)
	if _live(w) != before:
		push_error("day1 dusk packet live=%d" % _live(w))
		return false
	print("DAY1 OK shamblers=12 no packet")
	return true

func _day8_packet() -> bool:
	var w: Variant = _boot()["world"]
	var before: Array[int] = _ids(w)
	_jump_dusk(w, 8)
	var spawned: Array[Vector2i] = _edge_new(w, before)
	if spawned.size() != 3:
		push_error("day8 packet %d want 3" % spawned.size())
		return false
	print("DAY8 OK packet=3")
	return true

func _never_gate() -> bool:
	var w: Variant = _boot()["world"]
	var before: Array[int] = _ids(w)
	_jump_dusk(w, 8)
	for tile in _edge_new(w, before):
		if tile == SimFortify.GATE_A or tile == SimFortify.GATE_B:
			push_error("packet on gate %s" % str(tile))
			return false
		if SimDirector.ANNEX.has_point(tile):
			push_error("packet in annex %s" % str(tile))
			return false
		var gx: float = float(tile.x) + 0.5
		var gy: float = float(tile.y) + 0.5
		for gate in [SimFortify.GATE_A, SimFortify.GATE_B]:
			var dx: float = gx - (float(gate.x) + 0.5)
			var dy: float = gy - (float(gate.y) + 0.5)
			if dx * dx + dy * dy < SimDirector.GATE_EXCLUSION * SimDirector.GATE_EXCLUSION:
				push_error("packet within 32m of gate %s" % str(tile))
				return false
	print("GATE OK exclusion")
	return true

func _lull_skips() -> bool:
	var w: Variant = _boot()["world"]
	_jump_dusk(w, 8)
	var after_packet: int = _live(w)
	w.events.publish({"type": "fortify.breached", "tx": 46, "ty": 42})
	w.events.drain()
	_jump_dusk(w, 9)
	if _live(w) != after_packet:
		push_error("lull leaked packet live=%d was=%d" % [_live(w), after_packet])
		return false
	print("LULL OK skipped dusk")
	return true

func _same_seed() -> bool:
	var w1: Variant = _boot()["world"]
	var w2: Variant = _boot()["world"]
	var b1: Array[int] = _ids(w1)
	var b2: Array[int] = _ids(w2)
	_jump_dusk(w1, 8)
	_jump_dusk(w2, 8)
	var a: Array[Vector2i] = _edge_new(w1, b1)
	var b: Array[Vector2i] = _edge_new(w2, b2)
	a.sort()
	b.sort()
	if a != b:
		push_error("seed mismatch %s vs %s" % [str(a), str(b)])
		return false
	print("SEED OK same edge tiles")
	return true
