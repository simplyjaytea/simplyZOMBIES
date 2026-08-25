extends SceneTree
# Slice director: day-1 shamblers only, day-8 edge packet, never the gate, lull after breach.

const SimBoot = preload("res://sim/boot.gd")
const Clock = preload("res://sim/time/clock.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimDirector = preload("res://sim/modules/director.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _day1_boot() and ok
	ok = _day8_packet() and ok
	ok = _nights_vary_within_bounds() and ok
	ok = _the_bounds_fire_when_they_should() and ok
	ok = _packets_arrive_from_more_than_one_side() and ok
	ok = _never_gate() and ok
	ok = _lull_skips() and ok
	ok = _same_seed() and ok
	if ok:
		print("M2_DIRECTOR_OK boot packet gate lull seed, nights vary within docs/17's bounds")
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
	if s != SimBoot.WANDERERS or other != 0:
		push_error("day1 z shambler=%d (want %d) other=%d" % [s, SimBoot.WANDERERS, other])
		return false
	var before: int = _live(w)
	_jump_dusk(w, 1)
	if _live(w) != before:
		push_error("day1 dusk packet live=%d" % _live(w))
		return false
	print("DAY1 OK shamblers=%d no packet" % s)
	return true

# A night is drawn now, so "day 8 spawns exactly 3" is no longer a fact about the director -- it
# was the symptom. What must still hold is that the announcement and the district agree: whatever
# `director.night` says it sent is what turned up.
func _day8_packet() -> bool:
	var w: Variant = _boot()["world"]
	var packets: int = 0
	var nights: int = 0
	for day in range(8, 24):
		var before: Array[int] = _ids(w)
		var night: Variant = _run_night(w, day)
		if not night is Dictionary:
			push_error("day %d passed without the director saying anything -- rule 5 is that its decisions are observable" % day)
			return false
		nights += 1
		var arrived: int = _edge_new(w, before).size()
		if arrived != int((night as Dictionary)["size"]):
			push_error("day %d: the director announced %d and %d arrived" % [day, int((night as Dictionary)["size"]), arrived])
			return false
		if String((night as Dictionary).get("reason", "")).is_empty():
			push_error("day %d: a night with no stated reason" % day)
			return false
		if int((night as Dictionary)["size"]) > 0:
			packets += 1
		_cull(w)
	if packets < 1:
		push_error("sixteen nights and not one packet -- the director has gone quiet")
		return false
	print("DAY8 OK %d nights, %d with a packet, every announcement matched what arrived" % [nights, packets])
	return true


# Steps one dusk and returns the `director.night` event it published, or null.
func _run_night(world: Variant, day: int) -> Variant:
	world.tick = Clock.tick_on_day(day, Clock.DAY_ENDS) - 1
	world.step()
	for e in world.events.drained:
		if String((e as Dictionary).get("type", "")) == "director.night":
			return e
	return null


# Clears the district between nights. Without it the live count reaches LIVE_CAP after a few
# packets and every subsequent night is refused for that reason rather than drawn -- the harness
# would be measuring the cap, not the pacing. A colony that kills what arrives is the normal case.
func _cull(world: Variant) -> void:
	for e in world.components.query(["shambler"]):
		# The component, not just the entity: `entities.despawn` flips an alive bit and
		# `components.query` does not consult it, so despawning alone leaves every body in the
		# director's live count and every night after the fourth is refused for LIVE_CAP rather
		# than drawn. That read as "56 quiet nights in a row" the first time this ran.
		world.components.remove(int(e), "shambler")
		world.entities.despawn(int(e))


func _never_gate() -> bool:
	var w: Variant = _boot()["world"]
	# Off the booted world, not off a pair of constants -- the gates and the annex are map state
	# now, so when the generator moves the colony this assertion moves with it. Hoisted once
	# because the loop below asks about every tile the night placed.
	var gate_a: Vector2i = SimTileMap.gate_a(w.tilemap)
	var gate_b: Vector2i = SimTileMap.gate_b(w.tilemap)
	var annex: Rect2i = SimTileMap.annex_rect(w.tilemap)
	if gate_a.x < 0 or gate_b.x < 0 or annex.size.x <= 0:
		push_error("the booted district names no gates or annex, so the exclusion is unmeasurable")
		return false
	var before: Array[int] = _ids(w)
	_jump_dusk(w, 8)
	for tile in _edge_new(w, before):
		if tile == gate_a or tile == gate_b:
			push_error("packet on gate %s" % str(tile))
			return false
		if annex.has_point(tile):
			push_error("packet in annex %s" % str(tile))
			return false
		var gx: float = float(tile.x) + 0.5
		var gy: float = float(tile.y) + 0.5
		for gate in [gate_a, gate_b]:
			var dx: float = gx - (float((gate as Vector2i).x) + 0.5)
			var dy: float = gy - (float((gate as Vector2i).y) + 0.5)
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
	var night: Variant = _run_night(w, 9)
	if not night is Dictionary:
		push_error("lull night said nothing")
		return false
	# Asserted on the stated reason, not on the live count. Counting bodies passed for free the
	# moment a night could legitimately draw quiet: 0 == 0 whether the lull did anything or not.
	if String((night as Dictionary)["reason"]) != "lull":
		push_error("the night after a breach was '%s', not a lull" % String((night as Dictionary)["reason"]))
		return false
	if _live(w) != after_packet:
		push_error("lull leaked packet live=%d was=%d" % [_live(w), after_packet])
		return false
	print("LULL OK the night after a breach is refused, and says so")
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


# --- docs/17 rule 4: a variance floor and a ceiling ---------------------------------------------
#
# "Nights are never all quiet or all siege. The director maintains distribution bounds so that both
# 'nothing has happened in ten days' and 'every night is a siege' are impossible states."
#
# Run long enough for a distribution to exist, at the strain where sieges are actually on the
# table, and assert both ends: something happened, not everything happened, and neither cap was
# exceeded. Each cap also has to *fire* -- a bound nothing ever reaches is not evidence the bound
# works, so an unfired one says so and fails rather than passing quietly.
const LONG_NIGHTS: int = 60

func _nights_vary_within_bounds() -> bool:
	var w: Variant = _boot()["world"]
	var counts: Dictionary = {"quiet": 0, "probe": 0, "press": 0, "siege": 0}
	var reasons: Dictionary = {}
	var run_siege: int = 0
	var worst_siege_run: int = 0
	var run_quiet: int = 0
	var worst_quiet_run: int = 0
	for day in range(8, 8 + LONG_NIGHTS):
		# A colony that can fight and has been loud, so the draw sits in the top strain band and
		# sieges are reachable at all. Set rather than played out: this assertion is about the
		# distribution, and earning the strain would cost an hour of sim per run.
		(w.director as Dictionary)["weekPeakNoise"] = SimDirector.FOOTPRINT_NOISE
		var night: Variant = _run_night(w, day)
		if not night is Dictionary:
			push_error("day %d said nothing" % day)
			return false
		var shape: String = String((night as Dictionary)["shape"])
		counts[shape] = int(counts.get(shape, 0)) + 1
		var reason: String = String((night as Dictionary)["reason"])
		reasons[reason] = int(reasons.get(reason, 0)) + 1
		run_siege = run_siege + 1 if shape == "siege" else 0
		worst_siege_run = maxi(worst_siege_run, run_siege)
		run_quiet = run_quiet + 1 if shape == "quiet" else 0
		worst_quiet_run = maxi(worst_quiet_run, run_quiet)
		_cull(w)

	# Printed before the assertions, not after: a distribution that fails one bound is exactly
	# when its shape is worth seeing, and a gate that dies before printing it makes the next
	# person re-run it with a print statement added.
	print("VARIANCE over %d nights: quiet=%d probe=%d press=%d siege=%d, longest siege run %d, longest quiet run %d, reasons %s" % [
		LONG_NIGHTS, int(counts["quiet"]), int(counts["probe"]), int(counts["press"]), int(counts["siege"]),
		worst_siege_run, worst_quiet_run, str(reasons),
	])
	if int(counts["quiet"]) == 0:
		push_error("no quiet night in %d -- the floor half of rule 4 has become the whole rule" % LONG_NIGHTS)
		return false
	if int(counts["siege"]) + int(counts["press"]) == 0:
		push_error("nothing worse than a probe in %d nights -- 'nothing has happened' is supposed to be impossible" % LONG_NIGHTS)
		return false
	if worst_siege_run > SimDirector.MAX_CONSECUTIVE_SIEGE:
		push_error("%d sieges in a row, ceiling is %d" % [worst_siege_run, SimDirector.MAX_CONSECUTIVE_SIEGE])
		return false
	if worst_quiet_run > SimDirector.FLOOR_QUIET_NIGHTS:
		push_error("%d quiet nights in a row, floor is %d" % [worst_quiet_run, SimDirector.FLOOR_QUIET_NIGHTS])
		return false
	print("VARIANCE OK both ends reached, neither bound exceeded")
	return true


# The two bounds above are only evidence if they actually fire, and at these weights a natural
# three-siege run is rare enough that waiting for one would make the gate a coin toss. So each
# bound is put in the position it exists for and asked directly: the state is pinned, and the
# first night that *draws* the forbidden shape has to come out as something else. `drawn` is in
# the event for exactly this -- without it there would be no way to tell a bound that fired from
# a night that never tested it.
func _the_bounds_fire_when_they_should() -> bool:
	var w: Variant = _boot()["world"]
	var capped: Variant = null
	for day in range(8, 8 + LONG_NIGHTS):
		(w.director as Dictionary)["weekPeakNoise"] = SimDirector.FOOTPRINT_NOISE
		(w.director as Dictionary)["consecutiveSiege"] = SimDirector.MAX_CONSECUTIVE_SIEGE
		var night: Variant = _run_night(w, day)
		_cull(w)
		if night is Dictionary and String((night as Dictionary)["drawn"]) == "siege":
			capped = night
			break
	if not capped is Dictionary:
		push_error("no night drew a siege in %d tries at full strain -- the ceiling is untested" % LONG_NIGHTS)
		return false
	if String((capped as Dictionary)["shape"]) == "siege":
		push_error("a third consecutive siege was allowed through")
		return false
	if String((capped as Dictionary)["reason"]) != "siege-cap":
		push_error("the siege was stepped down for '%s' rather than the ceiling" % String((capped as Dictionary)["reason"]))
		return false

	var w2: Variant = _boot()["world"]
	var floored: Variant = null
	for day in range(8, 8 + LONG_NIGHTS):
		(w2.director as Dictionary)["nightsSinceQuiet"] = SimDirector.FLOOR_QUIET_NIGHTS
		var night2: Variant = _run_night(w2, day)
		_cull(w2)
		if night2 is Dictionary and String((night2 as Dictionary)["drawn"]) == "quiet":
			floored = night2
			break
	if not floored is Dictionary:
		push_error("no night drew quiet in %d tries -- the floor is untested" % LONG_NIGHTS)
		return false
	if String((floored as Dictionary)["shape"]) == "quiet":
		push_error("a fourth consecutive quiet night was allowed through")
		return false
	if String((floored as Dictionary)["reason"]) != "quiet-floor":
		push_error("the quiet night was stepped up for '%s' rather than the floor" % String((floored as Dictionary)["reason"]))
		return false
	print("BOUNDS OK a drawn siege became '%s' and a drawn quiet became '%s'" % [String((capped as Dictionary)["shape"]), String((floored as Dictionary)["shape"])])
	return true


# docs/17's migration lever: a crowd arrives "somewhere the field decides". Every packet used to
# come from the south, because south was the one authored approach and `_emit_packet` preferred it
# outright -- ten nights of a campaign down the same street.
func _packets_arrive_from_more_than_one_side() -> bool:
	var w: Variant = _boot()["world"]
	var sides: Dictionary = {}
	for day in range(8, 8 + LONG_NIGHTS):
		(w.director as Dictionary)["weekPeakNoise"] = SimDirector.FOOTPRINT_NOISE
		var night: Variant = _run_night(w, day)
		if night is Dictionary and not String((night as Dictionary)["side"]).is_empty():
			sides[String((night as Dictionary)["side"])] = int(sides.get(String((night as Dictionary)["side"]), 0)) + 1
		_cull(w)
	if sides.is_empty():
		push_error("no packet arrived at all, so this asserts nothing about where they come from")
		return false
	if sides.size() < 2:
		push_error("every packet in %d nights came from the %s -- the side is not being chosen" % [LONG_NIGHTS, str(sides.keys())])
		return false
	print("SIDES OK packets arrived from %d of four sides: %s" % [sides.size(), str(sides)])
	return true
