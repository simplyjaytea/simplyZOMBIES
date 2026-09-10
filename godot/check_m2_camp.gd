extends SceneTree
# The camp the player establishes, and the relocatable home it exists to move.
#
# Nine lanes, each with a true negative, because a gate that cannot fail is worse than no gate:
#
#   HOME      with no camp, every `SimHome` resolver answers exactly what the map anchors answer.
#             This is the lane that says the shipped game did not quietly move.
#             TN: a camp must make at least one of them differ.
#   CREATE    establishing is deterministic and refuses only what is not ground -- Task 8's "any
#             location can host a camp; there are no hard suitability restrictions".
#             TN: `can_establish` must be true somewhere, or the refusals prove nothing.
#   READS     **the dead-socket lane.** The three readers that were given a relocatable home
#             actually consult it: the raiders' objective, the jobs' home centre, and the
#             director's spawn legality. A resolver nothing reads is this milestone's twelfth
#             dead socket, so this asserts the callers rather than the read model.
#             TN: abandoning must send all three back to the anchors.
#   CHANNEL   establishing is an interruptible commitment, not a menu click (Task 8).
#             TN: an uninterrupted channel must complete, or "interrupted" proves nothing.
#   SAVE      a camp round-trips with no `SAVE_VERSION` bump, and the band is rebuilt on restore.
#             TN: a world that never had a camp must restore without one.
#   BAND      on a region, the night band follows home into the camp's cell (owner, 2026-09-10).
#             TN: a camp in the annex's *own* cell must leave the band exactly where it was --
#             otherwise the lane is only proving that "a camp exists", not that the cell decides.
#   ABANDON   abandoning is free and leaves the site behind as a known empty one (Task 8).
#             TN: home must have been the camp beforehand.
#   PROSE     the HUD clause carries no digits, and is empty for a run that made no camp.
#             TN: the digit scanner must reject a fabricated clause that does carry one.
#   OPTIONAL  a run stays viable with no camp at all (Task 8), and making one is not fatal either.
#             TN: the camp world's fingerprint must differ, or the comparison is vacuous.
#
# The gate size is 64 like every other M2 gate, except where a lane needs the shipped 256: the
# director's `GATE_EXCLUSION` is 32 m, which on a 64-tile world is half the map, so a "this tile is
# legal now that home moved" probe there answers false for the exclusion rather than for the rect.
# That cost a wrong reading once already while this gate was being written.

const SimBoot = preload("res://sim/boot.gd")
const SimCamp = preload("res://sim/modules/camp.gd")
const SimHome = preload("res://sim/home.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimDirector = preload("res://sim/modules/director.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimRaiders = preload("res://sim/modules/raiders.gd")
const SimSerialize = preload("res://sim/kernel/serialize.gd")

const CANON_SEED: int = 20260805
const GATE_SIZE: int = 64
# Where `GATE_EXCLUSION` stops swallowing the map. See the header.
const WIDE_SIZE: int = 256
const BUDGET_SECONDS: float = 120.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var started: int = Time.get_ticks_msec()
	var ok: bool = true
	ok = _home_with_no_camp_is_the_map_anchors() and ok
	ok = _establishing_is_deterministic_and_refuses_only_non_ground() and ok
	ok = _the_three_readers_actually_consult_home() and ok
	ok = _establishing_is_an_interruptible_commitment() and ok
	ok = _a_camp_survives_a_save() and ok
	ok = _the_night_band_follows_home_into_its_cell() and ok
	ok = _abandoning_is_free_and_leaves_the_site() and ok
	ok = _the_camp_clause_is_words() and ok
	ok = _a_run_is_viable_with_no_camp() and ok

	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	if seconds > BUDGET_SECONDS:
		push_error("BUDGET: %.1f s over the %.0f s budget" % [seconds, BUDGET_SECONDS])
		ok = false
	if ok:
		print(
			(
				"M2_CAMP_OK home resolves to the map anchors until a camp exists and to the camp after; establishing is deterministic, refuses only what is not ground, and is an interruptible channel; the raiders' objective, the jobs' home centre and the director's spawn legality all move with it; a camp round-trips a save with no version bump; on a region the night band follows home into its own cell; abandoning is free and leaves the site behind; the clause is words; and a run with no camp is unchanged (%.1f s of a %.0f s budget)"
				% [seconds, BUDGET_SECONDS]
			)
		)
		quit(0)
	else:
		push_error("M2_CAMP_FAIL")
		quit(1)


func _world(size: int = GATE_SIZE) -> Variant:
	return SimBoot.playable(CANON_SEED, size)["world"]


# The first tile inside `rect` that is plain walkable floor. A rect's corner is usually wall, so a
# probe taken as `position + (2, 2)` answers "illegal" for the wrong reason -- which it did, once.
func _floor_in(map: Variant, rect: Rect2i) -> Vector2i:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if SimTileMap.tile_at(map, x, y) != SimTileMap.Tile.Floor:
				continue
			if SimTileMap.is_solid(map, x, y):
				continue
			return Vector2i(x, y)
	return Vector2i(-1, -1)


# Somewhere a camp can go that is at least `away` metres from home, so a lane measuring "home moved"
# is not reading one 32 m exclusion disc overlapping the other.
func _spot_away_from_home(world: Variant, away: float) -> Vector2i:
	var map: Variant = world.tilemap
	var c: Vector2 = SimHome.centre(world)
	for y in range(2, int(map.h) - 2):
		for x in range(2, int(map.w) - 2):
			if not SimCamp.can_establish(world, x, y):
				continue
			if Vector2(float(x), float(y)).distance_to(c) < away:
				continue
			return Vector2i(x, y)
	return Vector2i(-1, -1)


func _legal(world: Variant, t: Vector2i) -> bool:
	return SimDirector._legal_tile(
		world.tilemap, t.x, t.y, SimHome.rect(world), SimHome.gate_a(world), SimHome.gate_b(world)
	)


func _band_bounds(map: Variant) -> Rect2i:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-1, -1)
	for record in map.spawn_edges as Array:
		var d: Dictionary = record as Dictionary
		lo.x = mini(lo.x, int(d["x"]))
		lo.y = mini(lo.y, int(d["y"]))
		hi.x = maxi(hi.x, int(d["x"]))
		hi.y = maxi(hi.y, int(d["y"]))
	if hi.x < 0:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(lo, hi - lo)


# 1. HOME: the lane that says the shipped game did not move.
func _home_with_no_camp_is_the_map_anchors() -> bool:
	var world: Variant = _world()
	var map: Variant = world.tilemap
	if SimHome.rect(world) != SimTileMap.annex_rect(map):
		push_error("HOME: rect %s != annex %s with no camp" % [str(SimHome.rect(world)), str(SimTileMap.annex_rect(map))])
		return false
	if SimHome.gate_a(world) != SimTileMap.gate_a(map):
		push_error("HOME: gate_a %s != map gate_a %s with no camp" % [str(SimHome.gate_a(world)), str(SimTileMap.gate_a(map))])
		return false
	if SimHome.gate_b(world) != SimTileMap.gate_b(map):
		push_error("HOME: gate_b %s != map gate_b %s with no camp" % [str(SimHome.gate_b(world)), str(SimTileMap.gate_b(map))])
		return false
	# The centre, against the formula `SimJobs._home_centre` carried before this slice.
	var annex: Rect2i = SimTileMap.annex_rect(map)
	var want: Vector2 = Vector2(
		float(annex.position.x) + float(annex.size.x) * 0.5,
		float(annex.position.y) + float(annex.size.y) * 0.5
	)
	if SimHome.centre(world) != want:
		push_error("HOME: centre %s != the annex centre %s" % [str(SimHome.centre(world)), str(want)])
		return false
	if SimHome.approach(world) != SimTileMap.gate_a(map):
		push_error("HOME: approach %s != gate_a with no camp" % str(SimHome.approach(world)))
		return false

	# The true negative: a camp has to move at least one of them, or every assertion above is
	# reading a constant.
	var spot: Vector2i = _spot_away_from_home(world, 8.0)
	if spot.x < 0:
		push_error("HOME: no tile on a %d-tile district can host a camp, so the negative cannot run" % GATE_SIZE)
		return false
	SimCamp.create(world, spot.x, spot.y)
	if SimHome.rect(world) == SimTileMap.annex_rect(map) and SimHome.centre(world) == want:
		push_error("HOME: a camp at %s moved neither the rect nor the centre, so this lane cannot fail" % str(spot))
		return false
	return true


# 2. CREATE: deterministic, and Task 8's "no hard suitability restrictions".
func _establishing_is_deterministic_and_refuses_only_non_ground() -> bool:
	var a: Variant = _world()
	var b: Variant = _world()
	var spot: Vector2i = _spot_away_from_home(a, 8.0)
	if spot.x < 0:
		push_error("CREATE: nowhere to camp on the gate district")
		return false
	var ca: int = SimCamp.create(a, spot.x, spot.y)
	var cb: int = SimCamp.create(b, spot.x, spot.y)
	if ca < 0 or cb < 0:
		push_error("CREATE: refused a tile `can_establish` had just allowed (%d, %d)" % [ca, cb])
		return false
	if ca != cb or SimCamp.tile_of(a, ca) != SimCamp.tile_of(b, cb):
		push_error("CREATE: two worlds on one seed disagree -- %d at %s against %d at %s" % [ca, str(SimCamp.tile_of(a, ca)), cb, str(SimCamp.tile_of(b, cb))])
		return false

	# Refusals: off the map, a wall, and a tile already camped. Nothing about whether the spot is a
	# *good* one -- that is the cost Task 8 wants paid in danger and exposure, not in a veto.
	var map: Variant = a.tilemap
	if SimCamp.can_establish(a, -1, 4):
		push_error("CREATE: a tile off the map was allowed")
		return false
	var wall := Vector2i(-1, -1)
	for y in range(0, int(map.h)):
		for x in range(0, int(map.w)):
			if SimTileMap.is_solid(map, x, y):
				wall = Vector2i(x, y)
				break
		if wall.x >= 0:
			break
	if wall.x >= 0 and SimCamp.can_establish(a, wall.x, wall.y):
		push_error("CREATE: a solid tile at %s was allowed" % str(wall))
		return false
	if SimCamp.can_establish(a, spot.x, spot.y):
		push_error("CREATE: the tile a live camp already stands on was allowed a second one")
		return false

	# The true negative: `can_establish` has to say yes somewhere, or the three refusals above are
	# satisfied by a function that always answers false.
	if _spot_away_from_home(a, 8.0).x < 0:
		push_error("CREATE: `can_establish` refuses every tile on the map, so the refusals prove nothing")
		return false
	return true


# 3. READS: the dead-socket lane. A relocatable home nothing consults is worth nothing.
func _the_three_readers_actually_consult_home() -> bool:
	# The shipped size, because `GATE_EXCLUSION` is 32 m and the director probe below needs the old
	# annex to be further than that from the new camp.
	var world: Variant = _world(WIDE_SIZE)
	var map: Variant = world.tilemap
	var annex: Rect2i = SimTileMap.annex_rect(map)
	var probe: Vector2i = _floor_in(map, annex)
	if probe.x < 0:
		push_error("READS: the annex holds no plain floor tile to probe")
		return false
	if _legal(world, probe):
		push_error("READS: a tile inside the annex at %s was already legal, so the director probe cannot fail" % str(probe))
		return false

	var spot: Vector2i = _spot_away_from_home(world, 80.0)
	if spot.x < 0:
		push_error("READS: nowhere far enough from the annex to camp on a %d-tile district" % WIDE_SIZE)
		return false
	var camp: int = SimCamp.create(world, spot.x, spot.y)
	if camp < 0:
		push_error("READS: could not establish at %s" % str(spot))
		return false
	var want: Vector2 = Vector2(float(spot.x) + 0.5, float(spot.y) + 0.5)

	# (a) the jobs' home centre
	if SimJobs._home_centre(world) != want:
		push_error("READS: SimJobs._home_centre is %s, not the camp at %s -- jobs does not read home" % [str(SimJobs._home_centre(world)), str(want)])
		return false
	# (b) the raiders' objective. A fresh record, so the per-raider cache is not answering.
	var fresh: Dictionary = {}
	if SimRaiders._objective(world, fresh) != spot:
		push_error("READS: a raider's objective is %s, not the camp at %s -- raiders do not read home" % [str(SimRaiders._objective(world, fresh)), str(spot)])
		return false
	# (c) the director's spawn legality: the camp is refused, and the annex it left is not.
	if _legal(world, spot):
		push_error("READS: the director would spawn on the camp itself at %s" % str(spot))
		return false
	if not _legal(world, probe):
		push_error("READS: the old annex at %s is still refused after home moved -- the director does not read home" % str(probe))
		return false

	# The true negative: abandon, and all three must go back to the anchors.
	SimCamp.abandon(world, camp)
	var back: bool = true
	back = back and SimJobs._home_centre(world) != want
	back = back and SimRaiders._objective(world, {}) == SimTileMap.gate_a(map)
	back = back and not _legal(world, probe)
	if not back:
		push_error("READS: abandoning the camp did not send the three readers back to the map anchors, so this lane cannot fail")
		return false
	return true


# 4. CHANNEL: Task 8's "a deliberate, interruptible commitment -- not a menu click".
func _establishing_is_an_interruptible_commitment() -> bool:
	# Interrupted.
	var world: Variant = _world()
	var actor: int = int(world.player)
	world.commands.push({"type": "camp.establish"})
	world.step()
	if not world.components.has_component(actor, "construct"):
		push_error("CHANNEL: `camp.establish` started no channel, so a camp is a menu click")
		return false
	if SimCamp.home_of(world) >= 0:
		push_error("CHANNEL: a camp existed after one tick -- the channel is not doing anything")
		return false
	world.events.publish({"type": "entity.staggered", "entity": actor})
	world.step()
	if world.components.has_component(actor, "construct"):
		push_error("CHANNEL: a stagger did not interrupt the channel")
		return false
	for _i in 200:
		world.step()
	if SimCamp.home_of(world) >= 0:
		push_error("CHANNEL: an interrupted channel still produced a camp")
		return false

	# The true negative: left alone, the same command must finish. Without this the lane passes on
	# a `camp.establish` that never builds anything at all.
	var clean: Variant = _world()
	clean.commands.push({"type": "camp.establish"})
	for _i in 200:
		clean.step()
	if SimCamp.home_of(clean) < 0:
		push_error("CHANNEL: an uninterrupted channel produced no camp, so 'interrupted' proves nothing")
		return false
	return true


# 5. SAVE: a new component round-trips for free -- no version bump.
func _a_camp_survives_a_save() -> bool:
	var world: Variant = _world()
	var spot: Vector2i = _spot_away_from_home(world, 8.0)
	var camp: int = SimCamp.create(world, spot.x, spot.y)
	if camp < 0:
		push_error("SAVE: could not establish a camp to save")
		return false
	var snap: Dictionary = world.snapshot()
	var restored: Variant = SimBoot.bare(CANON_SEED, GATE_SIZE)["world"]
	restored.restore(snap)
	var back: int = SimCamp.home_of(restored)
	if back < 0:
		push_error("SAVE: no camp after a restore")
		return false
	if SimCamp.tile_of(restored, back) != spot:
		push_error("SAVE: the camp came back at %s, not %s" % [str(SimCamp.tile_of(restored, back)), str(spot)])
		return false
	if SimHome.centre(restored) != SimHome.centre(world):
		push_error("SAVE: home is %s after a restore, was %s" % [str(SimHome.centre(restored)), str(SimHome.centre(world))])
		return false

	# The true negative: a world that never had one must restore without one, or "the camp came
	# back" is being answered by something other than the save.
	var plain: Variant = _world()
	var empty: Variant = SimBoot.bare(CANON_SEED, GATE_SIZE)["world"]
	empty.restore(plain.snapshot())
	if SimCamp.home_of(empty) >= 0:
		push_error("SAVE: a world that never made a camp restored with one, so this lane cannot fail")
		return false
	return true


# 6. BAND: the owner's 2026-09-10 answer -- night pressure follows home.
func _the_night_band_follows_home_into_its_cell() -> bool:
	var world: Variant = SimBoot.playable_region(CANON_SEED)["world"]
	var map: Variant = world.tilemap
	if int(map.region_cells) <= 0:
		push_error("BAND: the region booted with no cells, so there is nothing to follow")
		return false
	var stride: int = int(map.region_cell_stride)
	if stride <= 0:
		push_error("BAND: the region carries no cell stride, so a runtime reader cannot find its cell")
		return false
	var before: Rect2i = _band_bounds(map)
	if before.size.x <= 0:
		push_error("BAND: the region booted with an empty spawn band")
		return false

	# A camp in the diagonally opposite cell.
	var annex: Rect2i = SimTileMap.annex_rect(map)
	var far := Vector2i(-1, -1)
	for radius in range(0, 40):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var t := Vector2i(annex.position.x + stride + dx, annex.position.y + stride + dy)
				if SimCamp.can_establish(world, t.x, t.y):
					far = t
					break
			if far.x >= 0:
				break
		if far.x >= 0:
			break
	if far.x < 0:
		push_error("BAND: found no campable tile in the opposite cell")
		return false
	SimCamp.create(world, far.x, far.y)
	var after: Rect2i = _band_bounds(map)
	if after == before:
		push_error("BAND: the band stayed at %s after home moved to %s" % [str(before), str(far)])
		return false
	if not after.has_point(far):
		push_error("BAND: the band moved to %s, which does not contain the camp at %s" % [str(after), str(far)])
		return false

	# The true negative: a camp in the annex's *own* cell must leave the band where it started.
	# Without this the lane passes on a `sync_map` that moves the band whenever any camp exists.
	var same: Variant = SimBoot.playable_region(CANON_SEED)["world"]
	var near: Vector2i = _floor_in(same.tilemap, Rect2i(annex.position + Vector2i(6, 6), Vector2i(24, 24)))
	if near.x < 0 or not SimCamp.can_establish(same, near.x, near.y):
		push_error("BAND: found no campable tile in the annex's own cell for the negative")
		return false
	SimCamp.create(same, near.x, near.y)
	if _band_bounds(same.tilemap) != before:
		push_error("BAND: a camp in the annex's own cell moved the band from %s to %s -- the cell is not what decides" % [str(before), str(_band_bounds(same.tilemap))])
		return false
	return true


# 7. ABANDON: free, and the site persists as a known empty one.
func _abandoning_is_free_and_leaves_the_site() -> bool:
	var world: Variant = _world()
	var spot: Vector2i = _spot_away_from_home(world, 8.0)
	var camp: int = SimCamp.create(world, spot.x, spot.y)
	if camp < 0 or SimCamp.home_of(world) != camp:
		push_error("ABANDON: no camp was home before abandoning, so the lane cannot fail")
		return false
	var before: int = SimCamp.camps(world).size()
	SimCamp.abandon(world, camp)
	if SimCamp.home_of(world) >= 0:
		push_error("ABANDON: something is still home after abandoning")
		return false
	if SimHome.rect(world) != SimTileMap.annex_rect(world.tilemap):
		push_error("ABANDON: home did not fall back to the annex")
		return false
	if SimCamp.camps(world).size() != before:
		push_error("ABANDON: the abandoned site was deleted rather than left behind as a known empty one")
		return false
	if not SimCamp.is_abandoned(world, camp):
		push_error("ABANDON: the record is not marked abandoned")
		return false
	return true


# 8. PROSE: the HUD speaks in words. `check_hud` allows no digit but the day counter.
func _the_camp_clause_is_words() -> bool:
	var world: Variant = _world()
	var actor: int = int(world.player)
	if SimCamp.hud_clause(world, actor) != "":
		push_error("PROSE: a run with no camp still says something about one")
		return false
	var pos: Variant = world.components.get_component(actor, "position")
	var here := Vector2i(floori(float((pos as Dictionary)["x"])), floori(float((pos as Dictionary)["y"])))
	SimCamp.create(world, here.x, here.y)
	var at: String = SimCamp.hud_clause(world, actor)
	if at.is_empty() or _has_digit(at):
		push_error("PROSE: standing on the camp reads '%s'" % at)
		return false
	# And from somewhere else, a bearing rather than a distance.
	(pos as Dictionary)["x"] = float(here.x) + 12.0
	var away: String = SimCamp.hud_clause(world, actor)
	if away.is_empty() or _has_digit(away) or away == at:
		push_error("PROSE: away from the camp reads '%s' (at the camp it reads '%s')" % [away, at])
		return false

	# The true negative: prove the scanner on a string that does carry a digit, the way a scanner
	# is proved on a fabricated body before it is trusted.
	if not _has_digit("your camp lies 12 m north"):
		push_error("PROSE: the digit scanner passed a clause with a number in it, so this lane cannot fail")
		return false
	return true


func _has_digit(s: String) -> bool:
	for i in s.length():
		if s[i] >= "0" and s[i] <= "9":
			return true
	return false


# 9. OPTIONAL: Task 8's "a run stays viable with no camp at all".
func _a_run_is_viable_with_no_camp() -> bool:
	var steps: int = 1200
	var plain: Variant = _world()
	for _i in steps:
		plain.step()
	if _alive(plain) < 1:
		push_error("OPTIONAL: a run with no camp lost every survivor in %d ticks, so the baseline is not a baseline" % steps)
		return false

	# Determinism first: the same world twice must fingerprint the same, or "the camp changed it"
	# below is measuring noise.
	var twin: Variant = _world()
	for _i in steps:
		twin.step()
	var base: String = SimSerialize.fingerprint(plain.serialize())
	if SimSerialize.fingerprint(twin.serialize()) != base:
		push_error("OPTIONAL: two identical no-camp runs fingerprinted differently, so nothing below can be read")
		return false

	# And a run that does make one is viable too -- a camp is a choice, not a trap.
	var camped: Variant = _world()
	camped.commands.push({"type": "camp.establish"})
	for _i in steps:
		camped.step()
	if SimCamp.home_of(camped) < 0:
		push_error("OPTIONAL: the camped run never established one")
		return false
	if _alive(camped) < 1:
		push_error("OPTIONAL: making a camp cost the run every survivor in %d ticks" % steps)
		return false

	# The true negative: the camp must actually change the world, or "unchanged" is vacuous.
	if SimSerialize.fingerprint(camped.serialize()) == base:
		push_error("OPTIONAL: a run that made a camp fingerprinted identically to one that did not, so this lane cannot fail")
		return false
	return true


func _alive(world: Variant) -> int:
	var n: int = 0
	for e in world.components.query(["needs", "body"]):
		# `is_alive`, not `alive`: `components.query` does not check liveness, so a despawned body
		# still answers the query with every component it had (CLAUDE.md's trap).
		if world.entities.is_alive(int(e)):
			n += 1
	return n
