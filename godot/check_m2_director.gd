extends SceneTree
# Slice director: day-1 shamblers only, day-8 edge packet, never the gate, lull after breach.

const SimBoot = preload("res://sim/boot.gd")
const Clock = preload("res://sim/time/clock.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
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
	ok = _the_cap_scales_with_the_district() and ok
	ok = _two_grace_nights_then_the_table() and ok
	ok = _a_lull_opens_at_the_next_dawn_and_a_second_breach_extends_it() and ok
	if ok:
		print("M2_DIRECTOR_OK boot packet gate lull seed, nights vary within docs/17's bounds, the cap scales with the district, two grace nights then the table, and a lull opens at dawn")
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
	if s != SimBoot.wanderers_for(64) or other != 0:
		push_error("day1 z shambler=%d (want %d) other=%d" % [s, SimBoot.wanderers_for(64), other])
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


# --- the live cap scales with the district (2026-09-06, with the boot density) ----------------
#
# `LIVE_CAP` was a flat 32: with 80 booted at 256 the first dusk would have read "cap" and every
# dusk after it -- the despawn trap's refusal loop, reached at once. Now `live_cap_for(world)` is
# 32 per 64 tiles of side: 32 at 64 (unchanged, the true negative), 128 at 256, and a 256 world's
# first dusk with 80 live is "grace", not "cap". The fixture with no map reads the 64 number.
func _the_cap_scales_with_the_district() -> bool:
	var w64: Variant = SimBoot.playable(20260805, 64)["world"]
	if SimDirector.live_cap_for(w64) != 32:
		push_error("cap: a 64 world reads %d, want 32" % SimDirector.live_cap_for(w64))
		return false
	var w: Variant = SimBoot.playable(20260805, 256)["world"]
	if SimDirector.live_cap_for(w) != 128:
		push_error("cap: a 256 world reads %d, want 128" % SimDirector.live_cap_for(w))
		return false
	if _live(w) != 80:
		push_error("cap: the 256 boot stood %d, not 80; the night below judges the wrong district" % _live(w))
		return false
	var night: Variant = _run_night(w, 1)
	if not night is Dictionary:
		push_error("cap: no director.night on the 256 world's first dusk")
		return false
	var reason: String = String((night as Dictionary).get("reason", ""))
	if reason == "cap":
		push_error("cap: the 256 world's first dusk was refused for the cap with 80 live")
		return false
	print("CAP OK 32 at 64, 128 at 256; the 256 world's first dusk with 80 live reads '%s', not 'cap'" % reason)
	return true



# --- The playable state, slice 6: two grace nights, then the table; the lull's edge -------------

# Nights 1 and 2 say "grace" and leave the night stream untouched (its saved state is the
# proof, not a count of packets -- a quiet draw would look the same); night 3 draws, exactly
# once, and says so; a night 3 standing at the live cap says "cap" instead, which is the one
# thing that outranks the table besides a lull. The old rule sent nothing before night 8.
func _two_grace_nights_then_the_table() -> bool:
	var was: int = SimDirector.GRACE_NIGHTS
	SimDirector.GRACE_NIGHTS = 2
	var ok: bool = _grace_lane()
	SimDirector.GRACE_NIGHTS = was
	if not ok:
		return false
	# The shipped value is read: at the shipped GRACE_NIGHTS night 3 is still grace, and the
	# night after the last grace night draws -- the flip is one number, and this is the proof
	# that the number is the one the shipped default reads.
	var w: Variant = _boot()["world"]
	var shipped: Variant = _run_night(w, 3)
	var expect: String = "grace" if was >= 3 else "drawn"
	if not shipped is Dictionary or (expect == "grace" and String((shipped as Dictionary)["reason"]) != "grace"):
		push_error("GRACE: at the shipped GRACE_NIGHTS %d, night 3 should be %s, got %s" % [was, expect, str(shipped)])
		return false
	var first_drawn: Variant = _run_night(w, was + 1)
	if not first_drawn is Dictionary or String((first_drawn as Dictionary)["reason"]) == "grace":
		push_error("GRACE: at the shipped GRACE_NIGHTS %d, night %d should draw, got %s" % [was, was + 1, str(first_drawn)])
		return false
	print("GRACE OK shipped GRACE_NIGHTS=%d: night 3 '%s', night %d '%s'" % [was, String((shipped as Dictionary)["reason"]), was + 1, String((first_drawn as Dictionary)["reason"])])
	return true


func _grace_lane() -> bool:
	var w: Variant = _boot()["world"]
	var stream: Variant = w.rng.stream(SimDirector.NIGHT_STREAM)
	var before: int = int(stream.call("save"))
	for day in [1, 2]:
		var night: Variant = _run_night(w, day)
		if not night is Dictionary or String((night as Dictionary)["reason"]) != "grace" or int((night as Dictionary)["size"]) != 0:
			push_error("GRACE: night %d should be grace with nobody sent, got %s" % [day, str(night)])
			return false
		if int(stream.call("save")) != before:
			push_error("GRACE: night %d touched the night stream" % day)
			return false
	var third: Variant = _run_night(w, 3)
	if not third is Dictionary:
		push_error("GRACE: night 3 said nothing")
		return false
	var reason: String = String((third as Dictionary)["reason"])
	if reason == "grace" or reason == "grace-trickle" or reason == "cap" or reason == "lull":
		push_error("GRACE: night 3 was '%s', not drawn from the table" % reason)
		return false
	var after: int = int(stream.call("save"))
	if after == before:
		push_error("GRACE: night 3 did not touch the night stream -- nothing was drawn")
		return false
	# Exactly one draw: a fresh stream at the same state, drawn once, lands where the night did.
	var probe: Variant = w.rng.stream(SimDirector.NIGHT_STREAM)
	probe.call("restore", before)
	probe.call("int_range", 0, 99)
	var once: int = int(probe.call("save"))
	probe.call("restore", after)
	if once != after:
		push_error("GRACE: night 3 drew more than once from the night stream")
		return false
	# The cap outranks the table on night 3 as on any other.
	var capped: Variant = _boot()["world"]
	var rng: Variant = capped.rng.stream("placement")
	while _live(capped) < SimDirector.live_cap_for(capped):
		SimRoster.spawn_zombie(capped, 2.5, 2.5, SimRoster.TYPE_SHAMBLER, rng)
	var cap_night: Variant = _run_night(capped, 3)
	if not cap_night is Dictionary or String((cap_night as Dictionary)["reason"]) != "cap":
		push_error("GRACE: a night 3 at the live cap should say 'cap', got %s" % str(cap_night))
		return false
	print("GRACE OK nights 1-2 grace with the stream untouched; night 3 '%s' (%s) after exactly one draw; at the cap night 3 says cap" % [reason, String((third as Dictionary)["shape"])])
	return true


# The lull's opening edge. A breach on night 8 writes `lullFromTick` as day 9's dawn -- not 0,
# which is what every lull used to carry, making the `tick >= lullFromTick` half of the check
# dead -- and a second breach while that lull runs extends `lullUntilTick` and leaves the edge
# alone. The negative: before any breach, both fields are 0.
func _a_lull_opens_at_the_next_dawn_and_a_second_breach_extends_it() -> bool:
	var w: Variant = _boot()["world"]
	var st: Dictionary = w.director as Dictionary
	if int(st.get("lullFromTick", 0)) != 0 or int(st.get("lullUntilTick", 0)) != 0:
		push_error("LULL-EDGE: a fresh district already carries a lull %s" % str(st))
		return false
	_jump_dusk(w, 8)
	w.events.publish({"type": "fortify.breached", "tx": 46, "ty": 42})
	w.events.drain()
	var from_tick: int = int(st.get("lullFromTick", 0))
	var until_tick: int = int(st.get("lullUntilTick", 0))
	var dawn9: int = Clock.tick_on_day(9, Clock.DAY_BEGINS)
	if from_tick != dawn9:
		push_error("LULL-EDGE: the lull opens at %d, day 9's dawn is %d" % [from_tick, dawn9])
		return false
	if until_tick != dawn9 + Clock.DAY_TICKS:
		push_error("LULL-EDGE: one night's lull should close at %d, got %d" % [dawn9 + Clock.DAY_TICKS, until_tick])
		return false
	# Inside the lull, a second breach extends the close and keeps the edge.
	var night9: Variant = _run_night(w, 9)
	if not night9 is Dictionary or String((night9 as Dictionary)["reason"]) != "lull":
		push_error("LULL-EDGE: night 9 inside the lull was %s" % str(night9))
		return false
	w.events.publish({"type": "fortify.breached", "tx": 46, "ty": 42})
	w.events.drain()
	if int(st.get("lullFromTick", 0)) != dawn9:
		push_error("LULL-EDGE: a second breach moved the edge to %d" % int(st.get("lullFromTick", 0)))
		return false
	var dawn10: int = Clock.tick_on_day(10, Clock.DAY_BEGINS)
	if int(st.get("lullUntilTick", 0)) != dawn10 + Clock.DAY_TICKS:
		push_error("LULL-EDGE: a second breach should close the lull at %d, got %d" % [dawn10 + Clock.DAY_TICKS, int(st.get("lullUntilTick", 0))])
		return false
	print("LULL-EDGE OK breach at dusk 8 opens the lull at dawn 9 (%d) and closes it a day later; a second breach on night 9 extends the close to %d and keeps the edge" % [dawn9, int(st.get("lullUntilTick", 0))])
	return true
