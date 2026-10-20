extends SceneTree
# The tick, brought to budget one system at a time (alpha plan A3, docs/22's "Bringing the tick to
# budget"). `npm run godot:bench:runtime` is the number; this gate is what keeps each cut honest.
#
# Every speed-up here is a memo or an index over something the sim already answered the slow way,
# and the defect a memo invites is the quiet kind: a stale answer, no error, no wrong number anyone
# looks at. So every lane holds the fast path to the slow one it replaced -- agreement on the
# shipped data (the true positive) -- and then changes the data underneath it the ways the game and
# its gates actually do, and asks again (the true negative: a memo that cannot go stale is a memo
# this lane cannot fail). The last lane of each slice asks the dead-socket question: does the
# shipped reader reach the fast path at all.
#
# Every lane runs on its own world. The `and ok` order is deliberate: one red lane must not hide
# the ones behind it.

const World = preload("res://sim/world.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const SimVisibility = preload("res://sim/vision/visibility.gd")
const SimShadowcast = preload("res://sim/vision/shadowcast.gd")
const SimPath = preload("res://sim/path.gd")
const Clock = preload("res://sim/time/clock.gd")
const SimAllegiance = preload("res://sim/modules/allegiance.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimSightings = preload("res://sim/modules/sightings.gd")
const ComponentStore = preload("res://sim/component_store.gd")
const SimTreatment = preload("res://sim/modules/treatment.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const SimWeather = preload("res://sim/modules/weather.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimCombat = preload("res://sim/combat.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")

const FIXTURE: Dictionary = {"seed": 71, "tick_hz": 20, "map": {"width": 16, "height": 16, "walls": []}, "player": {"id": 0, "x": 8.5, "y": 8.5, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _content_index_agrees_with_the_scan() and ok
	ok = _content_index_follows_the_tree() and ok
	ok = _content_index_is_what_item_reads_reach() and ok
	ok = _the_map_log_answers_changed_whenever_in_doubt() and ok
	ok = _a_door_rewrites_its_own_cell_and_logs_its_own_tile() and ok
	ok = _a_view_stands_through_a_change_it_cannot_see() and ok
	ok = _the_dead_keep_a_view_a_tile_off_through_a_change_they_cannot_see() and ok
	ok = _the_heap_plans_the_paths_the_scan_planned() and ok
	ok = _the_inlined_cast_sees_what_blocks_sight_says() and ok
	ok = _near_enemies_are_the_enemies_that_are_near() and ok
	ok = _the_people_tables_are_the_people() and ok
	ok = _outside_the_square_nothing_is_seen() and ok
	ok = _the_query_memo_is_the_intersection() and ok
	ok = _one_pass_care_is_the_three_selectors() and ok
	ok = _the_claw_check_asks_distance_first_and_answers_the_same() and ok
	ok = _the_sky_read_once_is_the_sky_read_per_body() and ok
	ok = _each_observer_handed_its_square_sees_what_it_saw() and ok
	ok = _the_hour_read_once_is_the_hour_read_per_observer() and ok
	ok = _every_arm_that_moves_a_body_reads_its_speed() and ok
	ok = _a_far_body_thinks_on_its_quarter() and ok
	ok = _a_persons_cast_lands_whole_and_in_turn() and ok
	ok = _an_unhurt_body_has_nothing_to_strip() and ok
	ok = _the_dress_test_reads_the_base_once_and_answers_the_same() and ok
	ok = _swapped_scent_buffers_are_the_copied_field() and ok
	ok = _an_arc_cosine_follows_its_angle() and ok
	ok = _a_table_is_the_store_it_reads() and ok
	ok = _remembering_by_map_is_remembering_by_walk() and ok
	ok = _the_door_swing_asks_the_set_the_walk_answered() and ok
	if ok:
		print("M2_TICK_OK content-agree content-follows content-reader map-log door-cells view-stands dead-keep path cast enemies people square query care claw sky observe ambient seek far-think spread impair dress scent arcs table recall swing")
		quit(0)
	else:
		push_error("M2_TICK_FAIL")
		quit(1)


func _fail(lane: String, why: String) -> bool:
	push_error("M2_TICK_FAIL %s: %s" % [lane, why])
	return false


func _world() -> Variant:
	return World.new(FIXTURE.duplicate(true))


# Every id in the shipped tree, in tree order, once.
func _ids(tree: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var seen: Dictionary = {}
	for v in tree.values():
		var entries: Array = v as Array if v is Array else [v]
		for e in entries:
			if e is Dictionary and (e as Dictionary).has("id"):
				var id: String = String((e as Dictionary)["id"])
				if not seen.has(id):
					seen[id] = true
					out.append(id)
	return out


# CONTENT-AGREE. For every id the shipped tree carries, the memo hands back the very object the
# old linear scan finds -- asked cold and then warm, so both the build and the hit are judged. An
# id the tree does not carry is null both ways.
func _content_index_agrees_with_the_scan() -> bool:
	var w: Variant = _world()
	var tree: Dictionary = w.content as Dictionary
	var ids: Array[String] = _ids(tree)
	if ids.size() < 100:
		return _fail("CONTENT-AGREE", "the shipped tree has only %d ids; the lane has nothing to judge" % ids.size())
	for pass_name in ["cold", "warm"]:
		for id in ids:
			var fast: Variant = SimItems.content_entry(w, "item", id)
			var slow: Variant = SimItems._scan_for_id(tree, id)
			if not is_same(fast, slow):
				return _fail("CONTENT-AGREE", "%s lookup of %s is not the entry the scan finds" % [pass_name, id])
	if SimItems.content_entry(w, "item", "item.not.in.the.tree") != null:
		return _fail("CONTENT-AGREE", "an id the tree does not carry came back non-null")
	return true


# CONTENT-FOLLOWS. The memo is warmed, then the tree is changed under it the ways gates and the
# reload path change it, and each answer must be the scan's answer for the changed tree:
#   swap   -- an entry replaced at its own key by an edited copy (check_m2_weather pins rain so);
#   remove -- a key erased outright;
#   add    -- a key that did not exist when the memo was built;
#   tree   -- `world.content` replaced wholesale (platform/content_reload.gd);
#   forged -- the memo row itself lies about the object, which only the liveness check can catch.
func _content_index_follows_the_tree() -> bool:
	var w: Variant = _world()
	var tree: Dictionary = w.content as Dictionary
	var path: String = ""
	var id: String = ""
	for p in tree.keys():
		var v: Variant = tree[p]
		if v is Dictionary and (v as Dictionary).has("id"):
			path = String(p)
			id = String((v as Dictionary)["id"])
			break
	if path == "":
		return _fail("CONTENT-FOLLOWS", "no single-entry file in the tree to swap; the lane has nothing to judge")
	var original: Variant = SimItems.content_entry(w, "item", id)
	if not is_same(original, tree[path]):
		return _fail("CONTENT-FOLLOWS", "warming the memo did not find %s at %s" % [id, path])

	var edited: Dictionary = (tree[path] as Dictionary).duplicate(true)
	edited["gateMark"] = "swapped"
	tree[path] = edited
	if not is_same(SimItems.content_entry(w, "item", id), edited):
		return _fail("CONTENT-FOLLOWS", "swap: the memo handed back the entry it was built from")

	tree.erase(path)
	if not is_same(SimItems.content_entry(w, "item", id), SimItems._scan_for_id(tree, id)):
		return _fail("CONTENT-FOLLOWS", "remove: the memo still answers for an erased key")

	var added: Dictionary = {"id": "item.gate.tick.added", "name": "Added after the build"}
	tree["items/gate_tick_added.json"] = added
	if not is_same(SimItems.content_entry(w, "item", "item.gate.tick.added"), added):
		return _fail("CONTENT-FOLLOWS", "add: an entry added after the build was not found")

	var other: Dictionary = {"items/other.json": {"id": id, "name": "From another tree"}}
	w.content = other
	if not is_same(SimItems.content_entry(w, "item", id), other["items/other.json"]):
		return _fail("CONTENT-FOLLOWS", "tree: the memo outlived the tree it was built from")

	var forged: Dictionary = {"id": id, "name": "Not in any tree"}
	((w.content_index as Dictionary)[id] as Dictionary)["e"] = forged
	if not is_same(SimItems.content_entry(w, "item", id), other["items/other.json"]):
		return _fail("CONTENT-FOLLOWS", "forged: a memo row naming an object the tree does not hold was trusted")
	return true


# CONTENT-READER. `item_base_of` is the read that made the scan the tick's biggest cost (about a
# hundred calls a tick in the shipped world). It must reach the memo, not a private copy of the
# scan: on a fresh world nothing has built the memo, and one item read must leave it built over
# this world's tree. A world the reads never reach keeps an empty memo, which is the negative.
func _content_index_is_what_item_reads_reach() -> bool:
	var w: Variant = _world()
	if not (w.content_index as Dictionary).is_empty() or w.content_index_of != null:
		return _fail("CONTENT-READER", "a fresh world already carries a memo, so this lane proves nothing")
	var item: int = SimItems.spawn_item(w, "item.bandage.cloth")
	if item < 0:
		return _fail("CONTENT-READER", "could not spawn the probe item")
	w.content_index = {}
	w.content_index_of = null
	var base: Variant = SimItems.item_base_of(w, item)
	if not base is Dictionary:
		return _fail("CONTENT-READER", "item_base_of found nothing for the probe item")
	if not is_same(w.content_index_of, w.content) or (w.content_index as Dictionary).is_empty():
		return _fail("CONTENT-READER", "item_base_of answered without building this world's memo")
	var quiet: Variant = _world()
	if not (quiet.content_index as Dictionary).is_empty():
		return _fail("CONTENT-READER", "a world nothing read from built a memo anyway")
	return true


# --- slice 2: the map-change spike ---------------------------------------------------------------
#
# One door swinging shut used to rebuild all 65,536 solidity cells (90-170 ms), recast every one of
# the district's 105 observers (200 ms) and re-plan every walk with a linear-scan A* (100 ms) -- a
# 300 ms tick against a 16 ms worst. The world now logs *where* each generation changed the map,
# and the three consumers ask that log instead of assuming everything moved.

# A world on a blank district with one door near the player and one far beyond the player's eyes.
const NEAR_DOOR := Vector2i(14, 10)
const FAR_DOOR := Vector2i(88, 88)


func _door_world() -> Variant:
	var f: Dictionary = {"seed": 72, "tick_hz": 20, "map": {"width": 96, "height": 96, "walls": []}, "player": {"id": 0, "x": 10.5, "y": 10.5, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	var w: Variant = World.new(f)
	w.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	var map: Variant = SimTileMap.blank_map(96, 96)
	for d in [NEAR_DOOR, FAR_DOOR]:
		var door: Vector2i = d as Vector2i
		map.tiles[door.y * 96 + door.x] = SimTileMap.Tile.Door
		# Walls either side, so a door is the only gap and its state is visible to a shadowcast.
		map.tiles[(door.y - 1) * 96 + door.x] = SimTileMap.Tile.Wall
		map.tiles[(door.y + 1) * 96 + door.x] = SimTileMap.Tile.Wall
	SimBoot.attach_kernel(w, map)
	SimFortify.register_module(w)
	SimFortify.spawn_doors(w, map)
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	w.components.set_component(w.player, "observer", SimVisibility.daylight_eyes())
	return w


# MAP-LOG. `map_unchanged_within` is the one question every cache asks, so it must answer
# "unchanged" only when every generation since is a logged rectangle that misses the area -- and
# "changed" for a hit, a whole-map bump, an unlogged bump, a generation that went backwards and a
# span the bounded log no longer covers.
func _the_map_log_answers_changed_whenever_in_doubt() -> bool:
	var w: Variant = _world()
	var area := Rect2i(10, 10, 5, 5)
	var g0: int = int(w.mapGeneration)
	if not w.map_unchanged_within(g0, area):
		return _fail("MAP-LOG", "no change at all read as changed")
	w.invalidate_tiles(Rect2i(40, 40, 1, 1))
	if not w.map_unchanged_within(g0, area):
		return _fail("MAP-LOG", "a change far outside the area read as changed")
	w.invalidate_tiles(Rect2i(14, 14, 1, 1))
	if w.map_unchanged_within(g0, area):
		return _fail("MAP-LOG", "a change on the area's corner tile read as unchanged")
	var g1: int = int(w.mapGeneration)
	w.invalidateMap()
	if w.map_unchanged_within(g1, area):
		return _fail("MAP-LOG", "a whole-map bump read as unchanged")
	var g2: int = int(w.mapGeneration)
	w.mapGeneration += 1
	if w.map_unchanged_within(g2, area):
		return _fail("MAP-LOG", "an unlogged bump read as unchanged")
	var g3: int = int(w.mapGeneration)
	if w.map_unchanged_within(g3 + 5, area):
		return _fail("MAP-LOG", "a generation from the future read as unchanged")
	for i in World.MAP_CHANGES_KEPT + 1:
		w.invalidate_tiles(Rect2i(80, 80, 1, 1))
	if w.map_unchanged_within(g3, area):
		return _fail("MAP-LOG", "a span longer than the log keeps read as unchanged")
	var g4: int = int(w.mapGeneration)
	w.invalidate_tiles(Rect2i(80, 80, 1, 1))
	if not w.map_unchanged_within(g4, area):
		return _fail("MAP-LOG", "the log stopped answering after it wrapped")
	return true


# DOOR-CELLS. A door opened and shut through the shipped calls takes the in-play path: the
# solidity cells it leaves are the full rebuild's cells exactly, and the generation it logs is the
# door's own tile rather than the whole map. Then a full `sync_map` -- the restore and gate path --
# still logs the whole map, which is the negative.
func _a_door_rewrites_its_own_cell_and_logs_its_own_tile() -> bool:
	var w: Variant = _door_world()
	if not w.is_blocked_tile(NEAR_DOOR.x, NEAR_DOOR.y):
		return _fail("DOOR-CELLS", "the fixture's door does not start shut")
	for step in ["open", "close"]:
		var g: int = int(w.mapGeneration)
		var moved: bool = SimFortify.open_door(w, NEAR_DOOR.x, NEAR_DOOR.y) if step == "open" else SimFortify.close_door(w, NEAR_DOOR.x, NEAR_DOOR.y)
		if not moved or int(w.mapGeneration) != g + 1:
			return _fail("DOOR-CELLS", "%s did not move the door by exactly one generation" % step)
		var last: Dictionary = (w.map_changes as Array).back() as Dictionary
		if (last["rect"] as Rect2i) != Rect2i(NEAR_DOOR.x, NEAR_DOOR.y, 1, 1):
			return _fail("DOOR-CELLS", "%s logged %s, not the door's own tile" % [step, str(last["rect"])])
		var cells: Variant = w.map_cells.duplicate()
		SimFortify.sync_map(w)
		if cells != w.map_cells:
			return _fail("DOOR-CELLS", "%s left solidity cells the full rebuild disagrees with" % step)
		if (((w.map_changes as Array).back() as Dictionary)["rect"] as Rect2i).size.x >= 0:
			return _fail("DOOR-CELLS", "a full sync did not log the whole map")
	return true


# The shipped shadowcast, run fresh into its own buffer.
func _fresh_cast(w: Variant, ent: int) -> PackedByteArray:
	var p: Dictionary = w.components.get_component(ent, "position") as Dictionary
	var tiles: Variant = w.vision.tiles_for(ent)
	var out := SimShadowcast.VisibleTiles.new()
	SimShadowcast.shadowcast(w.tilemap, floori(float(p["x"])), floori(float(p["y"])), int(tiles.range_tiles), out, int((w.components.get_component(ent, "observer") as Dictionary)["eye"]))
	return out.cells


# VIEW-STANDS. A door beyond an observer's reach changes nothing it can see, so its view stands --
# no recast, and its cells are still exactly what a fresh shadowcast of the changed map gives. The
# same door inside its reach must recast, and the new cells must be the fresh cast's too: the near
# door is the negative that proves the far one stood because it was far, not because nothing ever
# recasts. Light casts are held to the same rule by the same log.
func _a_view_stands_through_a_change_it_cannot_see() -> bool:
	var w: Variant = _door_world()
	w.vision.refresh(w, w.tilemap)
	var before: int = int(w.vision.recomputes)
	if before < 1:
		return _fail("VIEW-STANDS", "the player has no view to keep")
	SimFortify.open_door(w, FAR_DOOR.x, FAR_DOOR.y)
	w.vision.refresh(w, w.tilemap)
	if int(w.vision.recomputes) != before:
		return _fail("VIEW-STANDS", "a door 78 tiles away recast a 48-tile view")
	if _fresh_cast(w, w.player) != (w.vision.tiles_for(w.player).cells as PackedByteArray):
		return _fail("VIEW-STANDS", "the view that stood is not what a fresh cast of the changed map sees")
	var shut_cells: PackedByteArray = (w.vision.tiles_for(w.player).cells as PackedByteArray).duplicate()
	SimFortify.open_door(w, NEAR_DOOR.x, NEAR_DOOR.y)
	w.vision.refresh(w, w.tilemap)
	if int(w.vision.recomputes) != before + 1:
		return _fail("VIEW-STANDS", "a door four tiles away did not recast the view")
	if _fresh_cast(w, w.player) != (w.vision.tiles_for(w.player).cells as PackedByteArray):
		return _fail("VIEW-STANDS", "the recast view is not what a fresh cast sees")
	if shut_cells == (w.vision.tiles_for(w.player).cells as PackedByteArray):
		return _fail("VIEW-STANDS", "opening the near door changed nothing the player sees, so this lane judges nothing")
	var lamp: int = int(w.entities.spawn())
	w.components.set_component(lamp, "position", {"x": 20.5, "y": 10.5})
	w.components.set_component(lamp, "light_source", {"magnitude": 20.0})
	w.light.refresh(w, w.tilemap)
	var lit: int = int(w.light.recomputes)
	SimFortify.close_door(w, FAR_DOOR.x, FAR_DOOR.y)
	w.light.refresh(w, w.tilemap)
	if int(w.light.recomputes) != lit:
		return _fail("VIEW-STANDS", "a door beyond a lamp's reach recast the lamp")
	SimFortify.close_door(w, NEAR_DOOR.x, NEAR_DOOR.y)
	w.light.refresh(w, w.tilemap)
	if int(w.light.recomputes) != lit + 1:
		return _fail("VIEW-STANDS", "a door inside a lamp's reach did not recast it")
	return true


# DEAD-KEEP. The one behaviour this slice changes, held both ways. A dead observer that has walked
# a tile from where it last cast keeps that cast between map changes (ZOMBIE_RECAST_TILES), and now
# keeps it across a change outside its square too: `DEAD_KEEP_VIEW` on, the far door's swing costs
# it no recast. Off -- the old rule -- the same swing recasts it, which is the negative proving the
# keep is the switch's doing. A change *inside* its square recasts it either way. The flag is
# restored before the lane returns, one gate process sharing it across every world it boots.
func _the_dead_keep_a_view_a_tile_off_through_a_change_they_cannot_see() -> bool:
	var was: bool = SimVisibility.DEAD_KEEP_VIEW
	var ok: bool = _dead_keep_lane()
	SimVisibility.DEAD_KEEP_VIEW = was
	return ok


func _dead_keep_lane() -> bool:
	var w: Variant = _door_world()
	var dead: int = int(w.entities.spawn())
	w.components.set_component(dead, "position", {"x": 80.5, "y": 88.5})
	w.components.set_component(dead, "facing", {"radians": 0.0})
	w.components.set_component(dead, "observer", SimVisibility.shambler_eyes())
	w.vision.refresh(w, w.tilemap)
	var cast: int = int(w.vision.cast_generation(dead))
	(w.components.get_component(dead, "position") as Dictionary)["x"] = 79.5
	w.vision.refresh(w, w.tilemap)
	if int(w.vision.cast_generation(dead)) != cast:
		return _fail("DEAD-KEEP", "a dead body recast a tile off its origin with no map change at all")
	SimVisibility.DEAD_KEEP_VIEW = true
	SimFortify.open_door(w, NEAR_DOOR.x, NEAR_DOOR.y)
	w.vision.refresh(w, w.tilemap)
	if int(w.vision.cast_generation(dead)) != cast:
		return _fail("DEAD-KEEP", "a door 65 tiles off its 12-tile square recast a dead body with DEAD_KEEP_VIEW on")
	SimVisibility.DEAD_KEEP_VIEW = false
	SimFortify.close_door(w, NEAR_DOOR.x, NEAR_DOOR.y)
	w.vision.refresh(w, w.tilemap)
	if int(w.vision.cast_generation(dead)) != cast + 1:
		return _fail("DEAD-KEEP", "with DEAD_KEEP_VIEW off, a map change did not recast a dead body a tile off its origin")
	SimVisibility.DEAD_KEEP_VIEW = true
	(w.components.get_component(dead, "position") as Dictionary)["x"] = 80.5
	w.vision.refresh(w, w.tilemap)
	cast = int(w.vision.cast_generation(dead))
	SimFortify.open_door(w, FAR_DOOR.x, FAR_DOOR.y)
	w.vision.refresh(w, w.tilemap)
	if int(w.vision.cast_generation(dead)) != cast + 1:
		return _fail("DEAD-KEEP", "a door inside a dead body's square did not recast it")
	return true


# The A* `SimPath.find` used before the heap, verbatim but for `prefer_last`: false is the old
# planner exactly; true breaks f-ties towards the *latest* open entry instead, which is the
# negative -- if no pair below plans differently under it, the pairs never met a tie and the
# agreement proves nothing about tie order.
func _linear_find(world: Variant, from: Vector2i, to: Vector2i, prefer_last: bool) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if from == to:
		return empty
	if not SimPath.walkable(world, to.x, to.y):
		var ok_near: bool = false
		for d in SimPath.DIRS:
			if SimPath.walkable(world, to.x + d.x, to.y + d.y):
				ok_near = true
				break
		if not ok_near:
			return empty
	var open: Array[Vector2i] = [from]
	var came: Dictionary = {}
	var g: Dictionary = {from: 0}
	var seen: Dictionary = {from: true}
	var guard: int = 0
	while not open.is_empty() and guard < 4096:
		guard += 1
		var best_i: int = 0
		var best_f: int = 1 << 30
		for i in open.size():
			var n: Vector2i = open[i]
			var f: int = int(g.get(n, 1 << 20)) + absi(n.x - to.x) + absi(n.y - to.y)
			if f < best_f or (prefer_last and f == best_f):
				best_f = f
				best_i = i
		var cur: Vector2i = open[best_i]
		open.remove_at(best_i)
		if cur == to:
			var out: Array[Vector2i] = []
			var n2: Vector2i = cur
			while came.has(n2):
				out.push_front(n2)
				n2 = came[n2] as Vector2i
			return out
		for d in SimPath.DIRS:
			var nxt: Vector2i = cur + d
			if not (SimPath.walkable(world, nxt.x, nxt.y) or nxt == to):
				continue
			var ng: int = int(g.get(cur, 0)) + 1
			if seen.has(nxt) and ng >= int(g.get(nxt, 1 << 20)):
				continue
			came[nxt] = cur
			g[nxt] = ng
			if not seen.has(nxt):
				open.append(nxt)
				seen[nxt] = true
	return empty


# PATH. On the shipped district, from the colony's own door out into the streets: the heap plans
# every pair tile for tile as the linear scan did -- including a target walled in on every side
# and a start that is its own destination -- and the tie-flipped scan plans at least one pair
# differently, so the pairs do meet ties.
func _the_heap_plans_the_paths_the_scan_planned() -> bool:
	var w: Variant = SimBoot.playable()["world"]
	var start: Vector2i = SimBoot.colony_start(w.tilemap)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7303
	var pairs: Array = [[start, start]]
	var tries: int = 0
	while pairs.size() < 24 and tries < 4000:
		tries += 1
		var a := Vector2i(start.x + rng.randi_range(-30, 30), start.y + rng.randi_range(-30, 30))
		var b := Vector2i(start.x + rng.randi_range(-30, 30), start.y + rng.randi_range(-30, 30))
		if SimPath.walkable(w, a.x, a.y) and SimPath.walkable(w, b.x, b.y):
			pairs.append([a, b])
	# And long ones, round blocks and across the district, where a plan meets the expansion cap and
	# the flat search's arrays are widest (A3's eighth slice).
	var long_pairs: int = 0
	while long_pairs < 10 and tries < 8000:
		tries += 1
		var a2 := Vector2i(start.x + rng.randi_range(-90, 90), start.y + rng.randi_range(-90, 90))
		var b2 := Vector2i(start.x + rng.randi_range(-90, 90), start.y + rng.randi_range(-90, 90))
		if absi(a2.x - b2.x) + absi(a2.y - b2.y) >= 60 and SimPath.walkable(w, a2.x, a2.y) and SimPath.walkable(w, b2.x, b2.y):
			pairs.append([a2, b2])
			long_pairs += 1
	var sealed := Vector2i(-1, -1)
	for y in range(1, int(w.tilemap.h) - 1):
		for x in range(1, int(w.tilemap.w) - 1):
			if SimPath.walkable(w, x, y):
				continue
			var boxed: bool = true
			for d in SimPath.DIRS:
				if SimPath.walkable(w, x + (d as Vector2i).x, y + (d as Vector2i).y):
					boxed = false
			if boxed:
				sealed = Vector2i(x, y)
				break
		if sealed.x >= 0:
			break
	if sealed.x >= 0:
		pairs.append([start, sealed])
	if pairs.size() < 30:
		return _fail("PATH", "found only %d walkable pairs near the colony; the lane has too little to judge" % pairs.size())
	var flipped: int = 0
	var found: int = 0
	for pair in pairs:
		var a: Vector2i = pair[0]
		var b: Vector2i = pair[1]
		var heap: Array[Vector2i] = SimPath.find(w, a, b)
		var scan: Array[Vector2i] = _linear_find(w, a, b, false)
		if heap != scan:
			return _fail("PATH", "%s to %s: the heap planned %d steps where the scan planned %d, or the same length by other tiles" % [a, b, heap.size(), scan.size()])
		if not heap.is_empty():
			found += 1
		if _linear_find(w, a, b, true) != scan:
			flipped += 1
	if found < 10:
		return _fail("PATH", "only %d pairs had a route; the lane has too little to judge" % found)
	if flipped == 0:
		return _fail("PATH", "no pair planned differently with ties broken the other way, so tie order was never judged")
	return true


# --- slice 3: the shadowcast itself --------------------------------------------------------------

# The shadowcast as it stood before slice 3, verbatim but for the frame Dictionaries, asking
# `SimTileMap.blocks_sight` per tile -- the definition of what blocks a sightline that the shipped
# cast now reads straight off the map's arrays.
func _reference_cast(map: Variant, ox: int, oy: int, r: int, eye: int) -> PackedByteArray:
	var out := SimShadowcast.VisibleTiles.new()
	out.reset(ox, oy, r)
	out.mark(ox, oy)
	var range_sq := r * r
	for q in range(4):
		var stack: Array = [[1, -1, 1, 1, 1]]
		while stack.size() > 0:
			var frame: Array = stack.pop_back()
			var depth: int = frame[0]
			if depth > r:
				continue
			var start_n: int = frame[1]
			var start_d: int = frame[2]
			var end_n: int = frame[3]
			var end_d: int = frame[4]
			var min_col := SimShadowcast.floor_div(2 * depth * start_n + start_d, 2 * start_d)
			var max_col := SimShadowcast.ceil_div(2 * depth * end_n - end_d, 2 * end_d)
			var prev: Variant = null
			var cur_n := start_n
			var cur_d := start_d
			for column in range(min_col, max_col + 1):
				var tx: int = ox + column if q == 0 or q == 2 else (ox + depth if q == 1 else ox - depth)
				var ty: int = oy + column if q == 1 or q == 3 else (oy + depth if q == 2 else oy - depth)
				var blocking: bool = SimTileMap.blocks_sight(map, tx, ty, eye)
				if blocking or (column * cur_d >= depth * cur_n and column * end_d <= depth * end_n):
					if depth * depth + column * column <= range_sq:
						out.mark(tx, ty)
				if prev == true and not blocking:
					cur_n = 2 * column - 1
					cur_d = 2 * depth
				if prev == false and blocking:
					stack.push_back([depth + 1, cur_n, cur_d, 2 * column - 1, 2 * depth])
				prev = blocking
			if prev == false:
				stack.push_back([depth + 1, cur_n, cur_d, end_n, end_d])
	return out.cells


# CAST. On the shipped district, with its doors, boards and parked cars: from every door, every
# board, a scatter of open tiles and the map's own corner (so the edge is crossed), at short and long
# ranges and both eyes, the shipped cast marks exactly the reference's cells. Then the negatives
# that make the agreement mean something: some origin sees differently crouched than standing, so
# the Low class was exercised; and opening a shut door changes what some origin sees, so the
# overlays were read rather than skipped.
func _the_inlined_cast_sees_what_blocks_sight_says() -> bool:
	var w: Variant = SimBoot.playable()["world"]
	var map: Variant = w.tilemap
	var origins: Array[Vector2i] = [Vector2i(0, 0), Vector2i(int(map.w) - 1, 3)]
	for key in (map.overlays as Dictionary).keys():
		origins.append(Vector2i(int(key) % int(map.w), int(key) / int(map.w)))
		if origins.size() > 40:
			break
	var rng := RandomNumberGenerator.new()
	rng.seed = 9113
	while origins.size() < 70:
		origins.append(Vector2i(rng.randi_range(0, int(map.w) - 1), rng.randi_range(0, int(map.h) - 1)))
	var crouch_differs: bool = false
	var compared: int = 0
	for o in origins:
		for r in [3, 12, 48]:
			var by_eye: Array = []
			for eye in [SimTileMap.Eye.Standing, SimTileMap.Eye.Crouched]:
				var shipped := SimShadowcast.VisibleTiles.new()
				SimShadowcast.shadowcast(map, o.x, o.y, int(r), shipped, int(eye))
				var ref: PackedByteArray = _reference_cast(map, o.x, o.y, int(r), int(eye))
				if shipped.cells != ref:
					return _fail("CAST", "from %s at %d tiles, eye %d, the cast marks other cells than blocks_sight allows" % [o, r, eye])
				var count: int = 0
				for c in ref:
					count += int(c)
				if shipped.count != count:
					return _fail("CAST", "from %s at %d tiles the cast counts %d cells and marks %d" % [o, r, shipped.count, count])
				by_eye.append(ref)
				compared += 1
			if by_eye[0] != by_eye[1]:
				crouch_differs = true
	if not crouch_differs:
		return _fail("CAST", "no origin saw differently crouched, so the Low class was never judged")
	var door: Vector2i = Vector2i(-1, -1)
	for key in (map.overlays as Dictionary).keys():
		var ov: Dictionary = (map.overlays as Dictionary)[key] as Dictionary
		if String(ov.get("kind", "")) == "door" and not bool(ov.get("open", false)):
			door = Vector2i(int(key) % int(map.w), int(key) / int(map.w))
			break
	if door.x < 0:
		return _fail("CAST", "no shut door on the district; the overlay half has nothing to judge")
	var shut := SimShadowcast.VisibleTiles.new()
	var beside: Vector2i = door + Vector2i(0, 1) if not SimTileMap.blocks_sight(map, door.x, door.y + 1) else door + Vector2i(1, 0)
	SimShadowcast.shadowcast(map, beside.x, beside.y, 12, shut)
	var shut_cells: PackedByteArray = shut.cells.duplicate()
	SimFortify.open_door(w, door.x, door.y)
	var opened := SimShadowcast.VisibleTiles.new()
	SimShadowcast.shadowcast(map, beside.x, beside.y, 12, opened)
	if opened.cells != _reference_cast(map, beside.x, beside.y, 12, SimTileMap.Eye.Standing):
		return _fail("CAST", "beside the opened door the cast disagrees with blocks_sight")
	if opened.cells == shut_cells:
		return _fail("CAST", "opening a door changed nothing seen from beside it, so overlays were never judged")
	return true


# --- slice 4: the scans every AI made of the whole district ----------------------------------------

# The district two hundred ticks in, so the dead have moved off their spawn points and the
# colonists off theirs: the shapes the fast paths are judged on are the ones a running game has.
func _stepped_world() -> Variant:
	var w: Variant = SimBoot.playable()["world"]
	for i in 200:
		w.step()
	return w


# The body of `static func <name>(` in `path`, comment lines dropped, so a needle a comment can
# satisfy cannot pass the reader check (CLAUDE.md's dead-socket pattern: a textual assertion has to
# be able to fail). Empty when the function is gone, which every caller reads as red.
func _body_of(path: String, fn_name: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	var at: int = text.find("static func %s(" % fn_name)
	if at < 0:
		return ""
	var out: PackedStringArray = PackedStringArray()
	var first: bool = true
	for line in text.substr(at).split("\n"):
		if not first and (line.begins_with("static func ") or line.begins_with("func ")):
			break
		first = false
		if line.strip_edges().begins_with("#"):
			continue
		out.append(line)
	return "\n".join(out)


func _positioned(w: Variant, e: int) -> Vector2:
	var p: Dictionary = w.components.get_component(e, "position") as Dictionary
	return Vector2(float(p["x"]), float(p["y"]))


# `enemies_within` is `enemies_of` filtered by the same `<=` the two callers apply after it: the
# same ids in the same order, for every person and every zombie on the district at three reaches.
# The negatives: the filter has to drop someone (or the lane judged a district where everyone is
# near everyone), keep someone, and agree on a body standing exactly on the boundary.
func _near_enemies_are_the_enemies_that_are_near() -> bool:
	var w: Variant = _stepped_world()
	var askers: Array[int] = []
	for e in w.components.query(["body", "position"]):
		if SimAllegiance.is_person(w, int(e)) or w.components.has_component(int(e), "shambler"):
			askers.append(int(e))
	if askers.size() < 20:
		return _fail("ENEMIES", "only %d people and zombies on the district; the lane has too little to judge" % askers.size())
	var dropped: int = 0
	var kept: int = 0
	for e in askers:
		var here: Vector2 = _positioned(w, e)
		for metres in [3.0, 12.0, 40.0]:
			var all: Array[int] = SimAllegiance.enemies_of(w, e)
			var want: Array[int] = []
			for o in all:
				if here.distance_squared_to(_positioned(w, o)) <= float(metres) * float(metres):
					want.append(o)
			var got: Array[int] = SimAllegiance.enemies_within(w, e, float(metres))
			if got != want:
				return _fail("ENEMIES", "entity %d at %.0f m: enemies_within gave %s where enemies_of filtered gives %s" % [e, metres, str(got), str(want)])
			dropped += all.size() - want.size()
			kept += want.size()
	if dropped == 0:
		return _fail("ENEMIES", "no enemy was ever out of reach, so the distance filter was never judged")
	if kept == 0:
		return _fail("ENEMIES", "no enemy was ever in reach, so the lane judged only empty lists")
	# The boundary: a colonist and a zombie put exactly five metres apart (a 3-4-5 on whole metres,
	# so the square is exact). Inside at 5, outside at a hair under.
	var person: int = -1
	var dead: int = -1
	for e in askers:
		if person < 0 and w.components.has_component(e, "controlled"):
			person = e
	for e in askers:
		if person >= 0 and dead < 0 and w.components.has_component(e, "shambler") and SimAllegiance.hostile(w, person, e):
			dead = e
	if person < 0 or dead < 0:
		return _fail("ENEMIES", "no player and hostile zombie to stand on the boundary")
	var pp: Dictionary = w.components.get_component(person, "position") as Dictionary
	var dp: Dictionary = w.components.get_component(dead, "position") as Dictionary
	pp["x"] = 40.0
	pp["y"] = 40.0
	dp["x"] = 43.0
	dp["y"] = 44.0
	if not SimAllegiance.enemies_within(w, person, 5.0).has(dead):
		return _fail("ENEMIES", "a zombie exactly five metres off is not within five metres")
	if SimAllegiance.enemies_within(w, person, 4.999).has(dead):
		return _fail("ENEMIES", "a zombie five metres off is within 4.999")
	for spot in [["npc_combat.gd", "_nearest_threat"], ["raiders.gd", "_enemy_within"]]:
		var body: String = _body_of("res://sim/modules/%s" % spot[0], spot[1])
		if body.find("enemies_within(") < 0 or body.find("enemies_of(") >= 0:
			return _fail("ENEMIES", "%s.%s does not ask enemies_within (or still asks enemies_of)" % [spot[0], spot[1]])
	return true


# `_people_with_position` is every positioned entity `is_person` accepts, in id order: on the
# district as it stands, and after a body that was not a person is given each marker in turn (the
# true negative for a marker the table walk forgot). And `PERSON_MARKERS` is exactly the markers
# `is_person` reads, so a fourth one added to the test alone is red here.
func _the_people_tables_are_the_people() -> bool:
	var w: Variant = _stepped_world()
	var spare: Array[int] = []
	for e in w.components.query(["position"]):
		if not SimAllegiance.is_person(w, int(e)) and not w.components.has_component(int(e), "body"):
			spare.append(int(e))
	if spare.size() < SimAllegiance.PERSON_MARKERS.size():
		return _fail("PEOPLE", "only %d positioned things that are not people; the lane cannot hand each marker to one" % spare.size())
	for step_i in SimAllegiance.PERSON_MARKERS.size() + 1:
		if step_i > 0:
			w.components.set_component(spare[step_i - 1], SimAllegiance.PERSON_MARKERS[step_i - 1], {})
		var want: Array[int] = []
		var others: int = 0
		for e in w.components.query(["position"]):
			if SimAllegiance.is_person(w, int(e)):
				want.append(int(e))
			else:
				others += 1
		var got: Array[int] = SimShambler._people_with_position(w)
		if got != want:
			return _fail("PEOPLE", "round %d: the marker tables gave %s where the is_person scan gives %s" % [step_i, str(got), str(want)])
		if step_i == 0 and (want.size() < 3 or others == 0):
			return _fail("PEOPLE", "%d people among %d other positioned things; the scan had nothing to skip or nobody to find" % [want.size(), others])
		if step_i > 0 and not got.has(spare[step_i - 1]):
			return _fail("PEOPLE", "a body given %s did not become a person" % SimAllegiance.PERSON_MARKERS[step_i - 1])
	var markers: Array[String] = []
	var rx := RegEx.new()
	rx.compile("has_component\\(entity, \"(\\w+)\"\\)")
	for m in rx.search_all(_body_of("res://sim/modules/allegiance.gd", "is_person")):
		markers.append(m.get_string(1))
	var listed: Array[String] = SimAllegiance.PERSON_MARKERS.duplicate()
	markers.sort()
	listed.sort()
	if markers.is_empty() or markers != listed:
		return _fail("PEOPLE", "is_person reads %s but PERSON_MARKERS lists %s" % [str(markers), str(listed)])
	if _body_of("res://sim/modules/shambler.gd", "_gather_survivors").find("_people_with_position(") < 0:
		return _fail("PEOPLE", "_gather_survivors does not walk _people_with_position")
	if _body_of("res://sim/modules/shambler.gd", "_people_with_position").find("SimAllegianceRes.people_with_position(") < 0:
		return _fail("PEOPLE", "_people_with_position no longer hands down to SimAllegiance.people_with_position")
	if _body_of("res://sim/modules/screamer.gd", "register_module").find("in SimAllegiance.people_with_position(w)") < 0:
		return _fail("PEOPLE", "the screamer's alarm does not walk SimAllegiance.people_with_position")
	return true


# The sightings prefilter skips only what `detail` would have answered Unseen: for every observer
# and every positioned thing, outside the square means unseen. The negatives: some targets are
# outside a square (or the prefilter skipped nothing), some inside are seen (or the implication was
# judged on a blind district), and the square's own edge falls on the tile `has_tile` stops at.
func _outside_the_square_nothing_is_seen() -> bool:
	var probe := SimShadowcast.VisibleTiles.new()
	probe.reset(10, 10, 5)
	for edge in [[15.5, 10.5, true], [16.5, 10.5, false], [5.5, 10.5, true], [4.99, 10.5, false], [10.5, 15.99, true], [10.5, 16.0, false]]:
		if SimSightings._in_square(probe, float(edge[0]), float(edge[1])) != bool(edge[2]):
			return _fail("SQUARE", "(%.2f, %.2f) against a 5-tile square on (10, 10) read %s" % [edge[0], edge[1], str(not bool(edge[2]))])
	if SimSightings._in_square(null, 10.5, 10.5):
		return _fail("SQUARE", "an observer with no view has a square")
	var w: Variant = _stepped_world()
	var outside: int = 0
	var seen: int = 0
	var observers: int = 0
	for ob in w.components.query(["sightings", "observer", "position"]):
		var tiles: Variant = w.vision.tiles_for(int(ob))
		if tiles == null:
			continue
		observers += 1
		for e in w.components.query(["position"]):
			var at: Vector2 = _positioned(w, int(e))
			var unseen: bool = int(w.vision.detail(int(ob), at.x, at.y)) == 0
			if not SimSightings._in_square(tiles, at.x, at.y):
				outside += 1
				if not unseen:
					return _fail("SQUARE", "observer %d sees entity %d at (%.1f, %.1f), outside its square" % [ob, e, at.x, at.y])
			elif not unseen:
				seen += 1
	if observers < 3:
		return _fail("SQUARE", "only %d observers with a view; the lane has too little to judge" % observers)
	if outside == 0:
		return _fail("SQUARE", "nothing was ever outside a square, so the prefilter skipped nothing")
	if seen == 0:
		return _fail("SQUARE", "nothing inside a square was ever seen, so the lane judged a blind district")
	for fn_name in ["_observe_one", "_observe_containers"]:
		if _body_of("res://sim/modules/sightings.gd", fn_name).find("_in_square(") < 0:
			return _fail("SQUARE", "%s does not ask _in_square" % fn_name)
	return true


# --- slice 5: the component query memo -------------------------------------------------------------

const QUERY_ASKS: Array = [["a"], ["a", "b"], ["b", "a"], ["a", "b", "c"], ["c", "d"], ["d"], ["a", "missing"], ["missing"]]


# `query` is `query_fresh` after every way the store changes membership -- a new member, a value
# replaced, a removal, a removal of nothing, `removeAll`, a brand-new table, and a `restore` of an
# older save -- over four hundred seeded operations. The negatives: the memo has to have answered
# (or the lane judged the slow path twice), a warm row has to have gone stale and been caught (or
# no change ever mattered), and a caller scribbling on its copy must not reach the next answer.
func _the_query_memo_is_the_intersection() -> bool:
	var store: Variant = ComponentStore.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var kinds: Array[String] = ["a", "b", "c", "d"]
	var snapshot: Dictionary = {}
	var last: Dictionary = {}
	var caught: int = 0
	for op in 400:
		var e: int = rng.randi_range(0, 29)
		var k: String = kinds[rng.randi_range(0, 3) if op > 20 else rng.randi_range(0, 2)]
		var roll: int = rng.randi_range(0, 99)
		var what: String = ""
		if roll < 45:
			what = "set"
			store.set_component(e, k, {"v": op})
		elif roll < 75:
			what = "remove"
			store.remove(e, k)
		elif roll < 85:
			what = "removeAll"
			store.removeAll(e)
		elif roll < 92:
			what = "snapshot"
			snapshot = store.save()
		elif not snapshot.is_empty():
			what = "restore"
			store.restore(snapshot.duplicate(true))
		for ask in QUERY_ASKS:
			var got: Array[int] = store.query(ask)
			var want: Array[int] = store.query_fresh(ask)
			if got != want:
				return _fail("QUERY", "op %d (%s %s on %d): query %s gave %s where the intersection is %s" % [op, what, k, e, str(ask), str(got), str(want)])
			var key: String = str(ask)
			if last.has(key) and last[key] != want:
				caught += 1
			last[key] = want
			got.append(-1)
			got.reverse()
		for ask in QUERY_ASKS:
			if store.query(ask) != store.query_fresh(ask):
				return _fail("QUERY", "op %d: a caller's edit to its copy reached the memo for %s" % [op, str(ask)])
	if int(store.memo_hits) == 0:
		return _fail("QUERY", "the memo never answered, so the lane judged the intersection against itself")
	if caught < 50:
		return _fail("QUERY", "only %d answers changed between asks; the lane barely judged staleness" % caught)
	store.set_component(0, "a", {"v": -1})
	store.query(["a"])
	var before: int = int(store.memo_hits)
	store.set_component(0, "a", {"v": -2})
	store.query(["a"])
	if int(store.memo_hits) != before + 1:
		return _fail("QUERY", "replacing a value dropped the memo; only membership should")
	var w: Variant = SimBoot.playable()["world"]
	w.step()
	var hits: int = int(w.components.memo_hits)
	w.step()
	if int(w.components.memo_hits) <= hits:
		return _fail("QUERY", "a shipped tick asked nothing the memo answered")
	return true


# --- slice 6: what each body paid for every tick -----------------------------------------------------

# `_needs_care` in one pass is the composition it replaced -- any bleeding part, or any part
# `_worst_part_for` finds something to clean or close -- over six hundred seeded wound lists drawn
# across every wound kind (an unknown one too), parts a survivor has and parts it does not, every
# severity including one below the selectors' floor, and every flag. Both answers have to occur
# often, and the self-aid system has to ask it.
func _one_pass_care_is_the_three_selectors() -> bool:
	var w: Variant = _world()
	var rng := RandomNumberGenerator.new()
	rng.seed = 6106
	var parts: Array = SimCombat.SURVIVOR_BODY_PARTS.duplicate()
	parts.append_array(["legs", "tail"])
	var kinds: Array = SimWounds.WOUND_KINDS.keys()
	kinds.append("unheard-of")
	var yes: int = 0
	var no: int = 0
	for trial in 600:
		var wounds: Array = []
		for k in rng.randi_range(0, 3):
			wounds.append({
				"bodyPart": parts[rng.randi_range(0, parts.size() - 1)],
				"kind": kinds[rng.randi_range(0, kinds.size() - 1)],
				"severity": rng.randi_range(-1, 2),
				"bleeding": rng.randf() < 0.3,
				"cleaned": rng.randf() < 0.4,
				"closed": rng.randf() < 0.4,
				"bandage": "none" if rng.randf() < 0.5 else "cloth",
			})
		w.components.set_component(5, "injuries", {"wounds": wounds})
		var want: bool = SimTreatment._worst_bleeding_part(w, 5) != "" or SimTreatment._worst_part_for(w, 5, "clean") != "" or SimTreatment._worst_part_for(w, 5, "close") != ""
		if SimTreatment._needs_care(w, 5) != want:
			return _fail("CARE", "trial %d: one pass says %s where the selectors say %s for %s" % [trial, str(not want), str(want), JSON.stringify(wounds)])
		if want:
			yes += 1
		else:
			no += 1
	w.components.remove(5, "injuries")
	if SimTreatment._needs_care(w, 5):
		return _fail("CARE", "a body with no injuries component needs care")
	if yes < 100 or no < 100:
		return _fail("CARE", "%d needed care and %d did not; the lane barely judged one side" % [yes, no])
	if _body_of("res://sim/modules/treatment.gd", "register_module").find("_needs_care(") < 0:
		return _fail("CARE", "the self-aid system does not ask _needs_care")
	return true


# The claw check as it stood before slice 6: health first, then distance.
func _reference_claw(world: Variant, entity: int) -> bool:
	var at: Variant = world.components.get_component(entity, "position")
	if not (at is Dictionary):
		return false
	var reach_sq: float = SimShambler.SWIPE_METRES * SimShambler.SWIPE_METRES
	for z in world.components.query(["shambler", "position"]):
		var zbody: Variant = world.components.get_component(int(z), "body")
		if zbody is Dictionary and not SimHealth.is_alive(zbody as Dictionary):
			continue
		var zp: Dictionary = world.components.get_component(int(z), "position") as Dictionary
		var dx: float = float(zp["x"]) - float((at as Dictionary)["x"])
		var dy: float = float(zp["y"]) - float((at as Dictionary)["y"])
		if dx * dx + dy * dy <= reach_sq:
			return true
	return false


# `_claw_in_reach` answers what the health-first scan answered for every person on the stepped
# district, and for one put a hand's width from a live zombie, then a dead one, then a live one
# just out of reach: both answers have to occur.
func _the_claw_check_asks_distance_first_and_answers_the_same() -> bool:
	var w: Variant = _stepped_world()
	var people: Array[int] = SimShambler._people_with_position(w)
	var zombies: Array[int] = w.components.query(["shambler", "position", "body"])
	if people.is_empty() or zombies.is_empty():
		return _fail("CLAW", "no people or no zombies on the stepped district")
	var p: int = people[0]
	var z: int = zombies[0]
	var pp: Dictionary = w.components.get_component(p, "position") as Dictionary
	var zp: Dictionary = w.components.get_component(z, "position") as Dictionary
	var zb: Dictionary = w.components.get_component(z, "body") as Dictionary
	var head: Variant = zb.get("head", 0)
	var cases: Array = []
	for step_i in 4:
		match step_i:
			1:
				pp["x"] = 40.0
				pp["y"] = 40.0
				zp["x"] = 40.5
				zp["y"] = 40.5
			2:
				zb["head"] = 0
			3:
				zb["head"] = head
				zp["x"] = 41.2
		for e in people:
			var got: bool = SimTreatment._claw_in_reach(w, e)
			if got != _reference_claw(w, e):
				return _fail("CLAW", "case %d, person %d: the claw check says %s where the health-first scan disagrees" % [step_i, e, str(got)])
		cases.append(SimTreatment._claw_in_reach(w, p))
	if cases.slice(1) != [true, false, false]:
		return _fail("CLAW", "a live zombie in reach, a dead one, then one out of reach read %s" % str(cases.slice(1)))
	return true


# Every zombie's speeds and reach with the sky handed in equal the ones read per body, under every
# weather kind the tree declares; a kind has to slow the dead and one has to shorten their sight
# (or handing in 1.0 would pass too); and the think pass reads the sky and hands it to every call.
func _the_sky_read_once_is_the_sky_read_per_body() -> bool:
	var w: Variant = _stepped_world()
	var was: String = SimWeather.kind(w)
	var slowed: bool = false
	var fogged: bool = false
	var zombies: Array[int] = w.components.query(["shambler", "position"])
	for k in SimWeather.kinds(w):
		(w.weather as Dictionary)["kind"] = k
		var sky: float = SimWeather.zombie_move_mul(w)
		var fog: float = SimWeather.sight_mul(w)
		for z in zombies:
			var sd: Dictionary = w.components.get_component(z, "shambler") as Dictionary
			for key in ["seekSpeed", "millSpeed", "wanderSpeed"]:
				var per: float = SimShambler._speed_of(w, z, sd, key)
				if SimShambler._speed_of(w, z, sd, key, sky) != per:
					return _fail("SKY", "%s, zombie %d: %s with the sky handed in is not the one read per body" % [k, z, key])
				if SimShambler._speed_of(w, z, sd, key, 1.0) != per:
					slowed = true
			var reach: float = SimShambler.sight_reach(w, z, sd)
			if SimShambler.sight_reach(w, z, sd, fog) != reach:
				return _fail("SKY", "%s, zombie %d: the reach with the fog handed in is not the one read per body" % [k, z])
			if reach > 0.0 and SimShambler.sight_reach(w, z, sd, 1.0) != reach:
				fogged = true
	(w.weather as Dictionary)["kind"] = was
	if not slowed or not fogged:
		return _fail("SKY", "no weather kind slowed the dead (%s) or shortened their sight (%s); the lane judged only 1.0" % [str(slowed), str(fogged)])
	var think: String = _body_of("res://sim/modules/shambler.gd", "register_module")
	if think.find("zombie_move_mul(") < 0 or think.find("sight_mul(") < 0:
		return _fail("SKY", "the think pass does not read the sky")
	for line in think.split("\n"):
		if line.find("_speed_of(") >= 0 and line.find(", sky)") < 0:
			return _fail("SKY", "a think-pass speed reads the sky per body: %s" % line.strip_edges())
		if line.find("_seen_target(") >= 0 and line.find(", fog)") < 0:
			return _fail("SKY", "a think-pass sight check reads the fog per body: %s" % line.strip_edges())
	return true


# The observe loop as it stood before slice 6: every body and every cupboard to every observer.
func _reference_observe(w: Variant) -> void:
	var candidates: Array = []
	for other in w.components.query(["body", "position"]):
		candidates.append(int(other))
	var boxes: Array = []
	for box in w.components.query(["searchable", "position"]):
		boxes.append(int(box))
	for ent in w.components.query(["sightings", "observer", "position"]):
		SimSightings._observe_one(w, int(ent), candidates)
		SimSightings._observe_containers(w, int(ent), boxes)
		SimSightings._merge_explored(w, int(ent))


# Two identical districts, every observer's memory wiped and handed one far cupboard that has since
# been searched; one observes the shipped way, one the old way, and every observer's record must
# come out the same. The negatives: something was seen, a cupboard was found, the searched one was
# forgotten, and somebody was outside some observer's square (or the prefilter dropped nothing).
# `_square_bounds` is pinned to `_in_square` on the square's edges.
func _each_observer_handed_its_square_sees_what_it_saw() -> bool:
	var probe := SimShadowcast.VisibleTiles.new()
	probe.reset(10, 10, 5)
	var b: Array = SimSightings._square_bounds(probe)
	for xy in [[4.99, 10.5], [5.0, 10.5], [15.99, 10.5], [16.0, 10.5], [10.5, 4.99], [10.5, 5.0], [10.5, 15.99], [10.5, 16.0]]:
		var x: float = float(xy[0])
		var y: float = float(xy[1])
		var inside: bool = x >= float(b[0]) and x < float(b[2]) and y >= float(b[1]) and y < float(b[3])
		if inside != SimSightings._in_square(probe, x, y):
			return _fail("OBSERVE", "(%.2f, %.2f): the bounds say %s and _in_square disagrees" % [x, y, str(inside)])
	if not SimSightings._square_bounds(null).is_empty():
		return _fail("OBSERVE", "an observer with no view has bounds")
	var worlds: Array = [_stepped_world(), _stepped_world()]
	var observers: Array[int] = worlds[0].components.query(["sightings", "observer", "position"])
	var boxes: Array[int] = worlds[0].components.query(["searchable", "position"])
	if observers.size() < 3 or boxes.is_empty():
		return _fail("OBSERVE", "%d observers and %d cupboards; the lane has too little to judge" % [observers.size(), boxes.size()])
	var far: int = boxes[boxes.size() - 1]
	for w in worlds:
		(w.components.get_component(far, "searchable") as Dictionary)["searched"] = true
		for ob in observers:
			var sc: Dictionary = w.components.get_component(ob, "sightings") as Dictionary
			sc["seen"] = []
			sc["containers"] = [{"e": far, "x": 0.0, "y": 0.0}]
	SimSightings.observe(worlds[0])
	_reference_observe(worlds[1])
	var seen_any: bool = false
	var found_any: bool = false
	var outside: bool = false
	for ob in observers:
		var a: Dictionary = worlds[0].components.get_component(ob, "sightings") as Dictionary
		var r: Dictionary = worlds[1].components.get_component(ob, "sightings") as Dictionary
		if JSON.stringify(a) != JSON.stringify(r):
			return _fail("OBSERVE", "observer %d remembers %s where the old loop gives %s" % [ob, JSON.stringify(a), JSON.stringify(r)])
		seen_any = seen_any or not (a["seen"] as Array).is_empty()
		found_any = found_any or not (a["containers"] as Array).is_empty()
		for row in a["containers"] as Array:
			if int((row as Dictionary)["e"]) == far:
				return _fail("OBSERVE", "observer %d still remembers a searched cupboard" % ob)
		var bounds: Array = SimSightings._square_bounds(worlds[0].vision.tiles_for(ob))
		for e in worlds[0].components.query(["body", "position"]):
			var at: Vector2 = _positioned(worlds[0], e)
			if bounds.is_empty() or at.x < float(bounds[0]) or at.x >= float(bounds[2]) or at.y < float(bounds[1]) or at.y >= float(bounds[3]):
				outside = true
	# The prefilter itself against `_in_square`, observer by observer, so a square narrowed where
	# nothing visible happens to stand is still red.
	for ob in observers:
		var tiles: Variant = worlds[0].vision.tiles_for(ob)
		var ids: Array = []
		var xs := PackedFloat64Array()
		var ys := PackedFloat64Array()
		var want: Array = []
		for e in worlds[0].components.query(["position"]):
			var at: Vector2 = _positioned(worlds[0], e)
			ids.append(e)
			xs.append(at.x)
			ys.append(at.y)
			if SimSightings._in_square(tiles, at.x, at.y):
				want.append(e)
		var got: Array = SimSightings._in_bounds(ids, xs, ys, SimSightings._square_bounds(tiles), [])
		if got != want:
			return _fail("OBSERVE", "observer %d: the prefilter keeps %d things where _in_square keeps %d" % [ob, got.size(), want.size()])
		var flags: Array[bool] = []
		for i in ids.size():
			flags.append(i == 0)
		if not SimSightings._in_bounds(ids, xs, ys, [], flags) == [ids[0]]:
			return _fail("OBSERVE", "with no view, a flagged cupboard was not handed over alone")
	if _body_of("res://sim/modules/sightings.gd", "observe").find("_in_bounds(") < 0:
		return _fail("OBSERVE", "observe does not hand each observer _in_bounds")
	if not seen_any or not found_any or not outside:
		return _fail("OBSERVE", "seen %s, found %s, anybody outside a square %s; the lane judged an empty case" % [str(seen_any), str(found_any), str(outside)])
	return true


# --- slice 7: the cast's rows, the hour, and the speed nobody asked for --------------------------

# The sight reaches `refresh` builds, with the hour's ambient factor handed in or read per observer,
# equal the clock-and-lamps formula they were before, for every observer at every half hour of the day; at least two hours have to
# differ (or a constant would pass), and `refresh` has to read the hour and hand it on.
func _the_hour_read_once_is_the_hour_read_per_observer() -> bool:
	var w: Variant = SimBoot.playable()["world"]
	w.step()
	var vis: Variant = w.vision
	var distinct: Dictionary = {}
	var checked: int = 0
	for hour in 48:
		w.tick = int(Clock.DAY_TICKS) * 2 + hour * int(Clock.DAY_TICKS) / 48
		var k: float = Clock.ambient_light_at(int(w.tick))
		distinct[k] = true
		vis.refresh(w, w.tilemap, 1.0)
		for ob in w.components.query(["position", "observer"]):
			var obs: Dictionary = w.components.get_component(ob, "observer") as Dictionary
			var at: Vector2 = _positioned(w, ob)
			# The two reaches as they were written before slice 7, from the clock and the lamps.
			var range_m: float = float(obs["range_metres"])
			var ambient_ref: float = range_m * Clock.ambient_light_at(int(w.tick))
			var lit: float = float(w.light.lit_metres(at.x, at.y)) if w.light != null else 0.0
			var sight_ref: float = min(range_m, max(ambient_ref, lit))
			for got in [vis._sight_metres(w, obs, at.x, at.y), vis._sight_metres(w, obs, at.x, at.y, k)]:
				if got != sight_ref:
					return _fail("AMBIENT", "hour %d, observer %d: a sight reach of %.4f where the clock and the lamps give %.4f" % [hour, ob, got, sight_ref])
			for got in [vis._ambient_metres(w, obs), vis._ambient_metres(w, obs, k)]:
				if got != ambient_ref:
					return _fail("AMBIENT", "hour %d, observer %d: an ambient reach of %.4f where the clock gives %.4f" % [hour, ob, got, ambient_ref])
			# And what `refresh` itself built from the hour it read once.
			var metres: float = ambient_ref if bool(obs.get("lit_target", false)) else sight_ref
			if float((vis._views[ob] as Dictionary)["range_squared"]) != metres * metres:
				return _fail("AMBIENT", "hour %d, observer %d: refresh built a reach of %.4f where the hour gives %.4f" % [hour, ob, sqrt(float((vis._views[ob] as Dictionary)["range_squared"])), metres])
			checked += 1
	if distinct.size() < 4 or checked == 0:
		return _fail("AMBIENT", "%d distinct ambient factors over %d checks; the lane judged a constant" % [distinct.size(), checked])
	var text: String = FileAccess.get_file_as_string("res://sim/vision/visibility.gd")
	var at_fn: int = text.find("func refresh(")
	var end_fn: int = text.find("\nfunc ", at_fn + 1)
	var body: String = text.substr(at_fn, end_fn - at_fn)
	if body.find("Clock.ambient_light_at(") < 0 or body.find("_sight_metres(world, obs as Dictionary, float((pos as Dictionary)[\"x\"]), float((pos as Dictionary)[\"y\"]), ambient_k)") < 0 or body.find("_ambient_metres(world, obs as Dictionary, ambient_k)") < 0:
		return _fail("AMBIENT", "refresh does not read the hour once and hand it to both reaches")
	return true


# The think pass reads a body's seek speed only in the arms that move it, so every such arm has to
# set it: a zombie put in each of Pursue, Seek and Wander with a person at arm's length is chased
# at exactly `_speed_of`'s seek speed by one run of the think pass alone, and a dormant one does
# not move.
func _every_arm_that_moves_a_body_reads_its_speed() -> bool:
	var w: Variant = _stepped_world()
	var think: Callable
	for sys in w.systems.ordered():
		if String((sys as Dictionary)["id"]) == "shambler.think":
			think = (sys as Dictionary)["runner"] as Callable
	if not think.is_valid():
		return _fail("SEEK", "no shambler.think system to run")
	var people: Array[int] = SimShambler._people_with_position(w)
	var z: int = -1
	for e in w.components.query(["shambler", "position", "velocity"]):
		if not w.components.has_component(e, "grabState"):
			z = e
			break
	if people.is_empty() or z < 0:
		return _fail("SEEK", "no person or free zombie on the stepped district")
	var sd: Dictionary = w.components.get_component(z, "shambler") as Dictionary
	var zp: Dictionary = w.components.get_component(z, "position") as Dictionary
	var pp: Dictionary = w.components.get_component(people[0], "position") as Dictionary
	var vd: Dictionary = w.components.get_component(z, "velocity") as Dictionary
	var states: Dictionary = SimShambler.ShamblerState
	for name in ["Pursue", "Seek", "Wander", "Dormant"]:
		zp["x"] = 60.5
		zp["y"] = 60.5
		pp["x"] = 61.1
		pp["y"] = 60.5
		sd["state"] = int(states[name])
		sd["ticksToGrab"] = 1000
		vd["dx"] = 0.0
		vd["dy"] = 0.0
		var want: float = 0.0 if name == "Dormant" else SimShambler._speed_of(w, z, sd, "seekSpeed")
		think.call(w)
		var got: float = sqrt(float(vd["dx"]) * float(vd["dx"]) + float(vd["dy"]) * float(vd["dy"]))
		if absf(got - want) > 1e-9:
			return _fail("SEEK", "a %s zombie beside a person moved at %.4f m/s where its seek speed is %.4f" % [name, got, want])
		if name != "Dormant" and want <= 0.0:
			return _fail("SEEK", "a %s zombie has no seek speed to judge" % name)
	return true


# --- slices 8 and 9: the per-body cuts, the far quarter, the spread cast ----------------------------

func _think_runner(w: Variant) -> Callable:
	for sys in w.systems.ordered():
		if String((sys as Dictionary)["id"]) == "shambler.think":
			return (sys as Dictionary)["runner"] as Callable
	return Callable()


# Puts the world on the tick where `(tick + entity) % FAR_THINK_EVERY == k`.
func _on_phase(w: Variant, entity: int, k: int) -> void:
	var n: int = SimShambler.FAR_THINK_EVERY
	w.tick = int(w.tick) - ((int(w.tick) + entity) % n) + k + n


# FAR-THINK. The one behaviour this slice changes for the dead, held both ways. A wandering body
# with nobody within FAR_THINK_METRES, off its phase, keeps its velocity and its countdowns run:
# due to turn, it does not turn. On its phase it turns. The negatives make the rest mean something:
# with THINK_LOD off the same off-phase body turns, and with a person ten metres away it turns, so
# what held it was the far rule and nothing else. A dormant body off its phase is still pinned. Its
# eyes rest exactly when its next tick is off-phase too, and `refresh` honours the mark: a resting
# view does not move with its body, and one that is not resting does. Last, the reader: the steers
# a far think compounds are handed `steps`. The flag is restored, one gate process sharing it.
func _a_far_body_thinks_on_its_quarter() -> bool:
	var was: bool = SimShambler.THINK_LOD
	var ok: bool = _far_think_lane()
	SimShambler.THINK_LOD = was
	return ok


func _far_think_lane() -> bool:
	var w: Variant = _stepped_world()
	var think: Callable = _think_runner(w)
	if not think.is_valid():
		return _fail("FAR-THINK", "no shambler.think system to run")
	var survivors: Array = SimShambler._gather_survivors(w)
	var people: Array[int] = SimShambler._people_with_position(w)
	var z: int = -1
	for e in w.components.query(["shambler", "position", "velocity", "observer"]):
		if w.components.has_component(e, "grabState"):
			continue
		if SimShambler._nobody_within(survivors, w.components.get_component(e, "position") as Dictionary, SimShambler.FAR_THINK_METRES + 10.0):
			z = e
			break
	if z < 0 or people.is_empty():
		return _fail("FAR-THINK", "no far zombie with eyes, or nobody to bring near, on the stepped district")
	var sd: Dictionary = w.components.get_component(z, "shambler") as Dictionary
	var vd: Dictionary = w.components.get_component(z, "velocity") as Dictionary
	var wander: int = int(SimShambler.ShamblerState["Wander"])
	var cases: Array = [
		# [lod, phase, bring a person near, state, expect it to think]
		[true, 1, false, "Wander", false],
		[true, 3, false, "Wander", false],
		[true, 0, false, "Wander", true],
		[false, 1, false, "Wander", true],
		[true, 1, true, "Wander", true],
		[true, 1, false, "Dormant", false],
	]
	var pp: Dictionary = w.components.get_component(people[0], "position") as Dictionary
	var home := Vector2(float(pp["x"]), float(pp["y"]))
	for c in cases:
		var lod: bool = c[0]
		SimShambler.THINK_LOD = lod
		_on_phase(w, z, int(c[1]))
		var zp: Dictionary = w.components.get_component(z, "position") as Dictionary
		if bool(c[2]):
			pp["x"] = float(zp["x"]) + 10.0
			pp["y"] = float(zp["y"])
		else:
			pp["x"] = home.x
			pp["y"] = home.y
		sd["state"] = int(SimShambler.ShamblerState[String(c[3])])
		sd["ticksToTurn"] = 0
		sd["ticksToGrab"] = 5
		vd["dx"] = 0.3
		vd["dy"] = 0.0
		w.vision.resting = {}
		think.call(w)
		var label: String = "%s, phase %d, lod %s, person %s" % [String(c[3]), int(c[1]), str(lod), "near" if bool(c[2]) else "far"]
		var thought: bool = int(sd["ticksToTurn"]) > 0 or int(sd["state"]) != int(SimShambler.ShamblerState[String(c[3])]) or float(vd["dx"]) != 0.3 or float(vd["dy"]) != 0.0
		if String(c[3]) == "Dormant":
			if float(vd["dx"]) != 0.0 or float(vd["dy"]) != 0.0:
				return _fail("FAR-THINK", "%s: a dormant body off its phase was not pinned" % label)
			if int(sd["ticksToGrab"]) != 4:
				return _fail("FAR-THINK", "%s: the grab countdown did not run" % label)
			continue
		if thought != bool(c[4]):
			return _fail("FAR-THINK", "%s: thought %s where the rule says %s" % [label, str(thought), str(c[4])])
		if not thought and int(sd["ticksToGrab"]) != 4:
			return _fail("FAR-THINK", "%s: the grab countdown did not run while it rested" % label)
		var rests: bool = w.vision.resting.has(z)
		var should_rest: bool = lod and not bool(c[2]) and (int(c[1]) + 1) % SimShambler.FAR_THINK_EVERY != 0
		if rests != should_rest:
			return _fail("FAR-THINK", "%s: its eyes rest %s where its next tick says %s" % [label, str(rests), str(should_rest)])
	sd["state"] = wander
	pp["x"] = home.x
	pp["y"] = home.y
	var zp2: Dictionary = w.components.get_component(z, "position") as Dictionary
	w.vision.refresh(w, w.tilemap)
	var held_x: float = float((w.vision._views[z] as Dictionary)["x"])
	zp2["x"] = float(zp2["x"]) + 0.5
	w.vision.resting = {z: true}
	w.vision.refresh(w, w.tilemap)
	if float((w.vision._views[z] as Dictionary)["x"]) != held_x:
		return _fail("FAR-THINK", "a view marked resting moved with its body")
	if not w.vision.resting.is_empty():
		return _fail("FAR-THINK", "refresh left the resting marks for the next tick")
	w.vision.refresh(w, w.tilemap)
	if float((w.vision._views[z] as Dictionary)["x"]) != float(zp2["x"]):
		return _fail("FAR-THINK", "a view not marked resting did not follow its body")
	if SimShambler._steps_bias(0.35, 1) != 0.35 or absf(SimShambler._steps_bias(0.35, 4) - (1.0 - pow(0.65, 4.0))) > 1e-12:
		return _fail("FAR-THINK", "a steer compounded over four ticks is not four ticks' steer")
	var body: String = _body_of("res://sim/modules/shambler.gd", "register_module")
	if body.find("_drift_upscent(field, pd, vd, sd, seek, steps)") < 0 or body.find("LIGHT_SENSITIVITY)), steps)") < 0:
		return _fail("FAR-THINK", "the think does not hand `steps` to the scent and light steers")
	if body.find("(rest_eyes as Dictionary)[int(entity)] = true") < 0:
		return _fail("FAR-THINK", "the think never marks a far body's eyes as resting")
	return true


# SPREAD. A person who is not the player recasts after PERSON_RECAST_TILES, a quadrant at a time,
# PERSON_QUADRANTS_PER_TICK quadrants a tick for everyone, longest-waiting first, and the view lands
# whole: until it does `tiles_for` is the old cast, and after it is exactly a fresh cast from where
# the person stood when it was queued. The negatives: a tile's walk queues nothing; with the switch
# off a tile's walk recasts at once; the player casts whole and at once with the switch on; a view
# never cast is cast at once; and the cut itself -- four one-quadrant casts mark what one whole
# cast marks -- is held on doors shut and open, both eyes.
func _a_persons_cast_lands_whole_and_in_turn() -> bool:
	var was: bool = SimVisibility.STAGGER_PERSON_CASTS
	SimVisibility.STAGGER_PERSON_CASTS = true
	var ok: bool = _spread_lane()
	SimVisibility.STAGGER_PERSON_CASTS = was
	return ok


func _spread_lane() -> bool:
	var w: Variant = _door_world()
	# Midday, where the hour does not move anyone's reach between one tick and the next.
	w.tick = Clock.tick_at_time_of_day(0.375)
	if not w.components.has_component(w.player, "controlled"):
		return _fail("SPREAD", "the fixture's player is not the controlled body")
	var folk: Array[int] = []
	for i in 2:
		var e: int = int(w.entities.spawn())
		w.components.set_component(e, "position", {"x": 30.5 + float(i) * 20.0, "y": 40.5})
		w.components.set_component(e, "facing", {"radians": 0.0})
		w.components.set_component(e, "observer", SimVisibility.daylight_eyes())
		folk.append(e)
	var a: int = folk[0]
	var b: int = folk[1]
	w.vision.refresh(w, w.tilemap)
	for e in [a, b, w.player]:
		if int(w.vision.cast_generation(int(e))) != 1:
			return _fail("SPREAD", "a view never cast was not cast whole on its first refresh")
	var step := func(dx: float, who: Array) -> void:
		for e in who:
			var p: Dictionary = w.components.get_component(int(e), "position") as Dictionary
			p["x"] = float(p["x"]) + dx
	step.call(1.0, [a])
	w.tick = int(w.tick) + 1
	w.vision.refresh(w, w.tilemap)
	if int(w.vision.cast_generation(a)) != 1 or (w.vision._views[a] as Dictionary).get("pending") != null:
		return _fail("SPREAD", "a person a tile off their cast queued or cast")
	step.call(1.0, [w.player])
	w.tick = int(w.tick) + 1
	w.vision.refresh(w, w.tilemap)
	if int(w.vision.cast_generation(w.player)) != 2:
		return _fail("SPREAD", "the player a tile off their cast did not recast at once")
	# B walks first and waits longest; A follows a tick later with the lower id.
	step.call(1.0, [b])
	step.call(1.0, [b])
	var spread0: int = int(w.vision.quadrants_spread)
	w.tick = int(w.tick) + 1
	w.vision.refresh(w, w.tilemap)
	var b_at := Vector2i(floori(float((w.components.get_component(b, "position") as Dictionary)["x"])), 40)
	step.call(1.0, [a])
	var a_at := Vector2i(floori(float((w.components.get_component(a, "position") as Dictionary)["x"])), 40)
	var landed: Array = []
	for t in 6:
		var before_spread: int = int(w.vision.quadrants_spread)
		var queued: bool = (w.vision._views[a] as Dictionary).get("pending") != null or (w.vision._views[b] as Dictionary).get("pending") != null
		var a_gen: int = int(w.vision.cast_generation(a))
		var b_gen: int = int(w.vision.cast_generation(b))
		w.tick = int(w.tick) + 1
		w.vision.refresh(w, w.tilemap)
		if queued and int(w.vision.quadrants_spread) - before_spread != SimVisibility.PERSON_QUADRANTS_PER_TICK:
			return _fail("SPREAD", "a tick with casts queued spent %d quadrants, not %d" % [int(w.vision.quadrants_spread) - before_spread, SimVisibility.PERSON_QUADRANTS_PER_TICK])
		if int(w.vision.cast_generation(b)) != b_gen:
			landed.append("b")
		if int(w.vision.cast_generation(a)) != a_gen:
			landed.append("a")
	if int(w.vision.quadrants_spread) - spread0 != 8:
		return _fail("SPREAD", "two whole casts took %d quadrants, not eight" % (int(w.vision.quadrants_spread) - spread0))
	if landed != ["b", "a"]:
		return _fail("SPREAD", "the casts landed %s where the longest-waiting goes first" % str(landed))
	for pair in [[a, a_at], [b, b_at]]:
		var e: int = int(pair[0])
		var at: Vector2i = pair[1]
		var tiles: Variant = w.vision.tiles_for(e)
		if int(tiles.origin_x) != at.x or int(tiles.origin_y) != at.y:
			return _fail("SPREAD", "a landed view was cast from %d,%d where its person stood at %d,%d" % [int(tiles.origin_x), int(tiles.origin_y), at.x, at.y])
		var fresh := SimShadowcast.VisibleTiles.new()
		SimShadowcast.shadowcast(w.tilemap, at.x, at.y, int(tiles.range_tiles), fresh, int((w.components.get_component(e, "observer") as Dictionary)["eye"]))
		if fresh.cells != (tiles.cells as PackedByteArray):
			return _fail("SPREAD", "a view landed a quadrant at a time is not what one whole cast sees")
	SimVisibility.STAGGER_PERSON_CASTS = false
	var a_gen2: int = int(w.vision.cast_generation(a))
	step.call(1.0, [a])
	w.tick = int(w.tick) + 1
	w.vision.refresh(w, w.tilemap)
	if int(w.vision.cast_generation(a)) != a_gen2 + 1:
		return _fail("SPREAD", "with the spread off a person a tile off their cast did not recast at once")
	SimVisibility.STAGGER_PERSON_CASTS = true
	# The quadrant split itself, on the district with its doors, against one whole cast.
	var map: Variant = _stepped_world().tilemap
	var rng := RandomNumberGenerator.new()
	rng.seed = 8117
	var opened: bool = false
	for i in 24:
		var o := Vector2i(rng.randi_range(0, int(map.w) - 1), rng.randi_range(0, int(map.h) - 1))
		for eye in [SimTileMap.Eye.Standing, SimTileMap.Eye.Crouched]:
			var whole := SimShadowcast.VisibleTiles.new()
			SimShadowcast.shadowcast(map, o.x, o.y, 48, whole, int(eye))
			var parts := SimShadowcast.VisibleTiles.new()
			for q in 4:
				SimShadowcast.shadowcast(map, o.x, o.y, 48, parts, int(eye), q, q)
			if parts.cells != whole.cells or parts.count != whole.count:
				return _fail("SPREAD", "four one-quadrant casts from %s marked other cells than one whole cast" % str(o))
			var north := SimShadowcast.VisibleTiles.new()
			SimShadowcast.shadowcast(map, o.x, o.y, 48, north, int(eye), 0, 0)
			if north.count < whole.count:
				opened = true
	if not opened:
		return _fail("SPREAD", "one quadrant always saw the whole circle, so the split was never judged")
	return true


func _runner(w: Variant, id: String) -> Callable:
	for sys in w.systems.ordered():
		if String((sys as Dictionary)["id"]) == id:
			return (sys as Dictionary)["runner"] as Callable
	return Callable()


# IMPAIR. `holds_any` answers whether a scope holds any of the named sources, and `remove_by_source`
# looking before it rebuilds changes nothing it does not remove. Then the reader: `wounds.impair`
# skips a body with no wound, no impairing blood loss and none of its sources -- so a stale
# `wound.*` modifier on an unhurt body must still be stripped (a skip that kept it would be the
# stale-memo defect), an unrelated source on the same body survives, and a wounded body is still
# impaired.
func _an_unhurt_body_has_nothing_to_strip() -> bool:
	var w: Variant = _stepped_world()
	var impair: Callable = _runner(w, "wounds.impair")
	if not impair.is_valid():
		return _fail("IMPAIR", "no wounds.impair system to run")
	var z: int = -1
	for e in w.components.query(["injuries"]):
		if w.components.has_component(e, "corpse"):
			continue
		if (((w.components.get_component(e, "injuries") as Dictionary).get("wounds", [])) as Array).is_empty():
			z = e
			break
	if z < 0:
		return _fail("IMPAIR", "no unwounded body on the stepped district")
	var m: Variant = w.modifiers
	var sources: Dictionary = SimWounds._impair_sources()
	if sources.size() != 3 + SimCombat.SURVIVOR_BODY_PARTS.size():
		return _fail("IMPAIR", "the impair sources are %d, not the three families and a source a part" % sources.size())
	m.add({"stat": "move_speed", "op": "mul", "value": 0.9, "source": "lane.keep"}, z)
	if m.holds_any(z, sources):
		return _fail("IMPAIR", "an unrelated source counted as an impair source")
	var size_before: int = int(m.size())
	if int(m.remove_by_source("wound.leg_left", z)) != 0 or int(m.size()) != size_before:
		return _fail("IMPAIR", "removing a source nobody holds removed something")
	m.add({"stat": "move_speed", "op": "mul", "value": 0.5, "source": "wound.leg_left"}, z)
	if not m.holds_any(z, sources):
		return _fail("IMPAIR", "a wound source on the body was not found")
	impair.call(w)
	if m.holds_any(z, {"wound.leg_left": true}):
		return _fail("IMPAIR", "a stale wound modifier on an unhurt body survived wounds.impair")
	if not m.holds_any(z, {"lane.keep": true}):
		return _fail("IMPAIR", "wounds.impair stripped a source that is not its own")
	var inj: Dictionary = w.components.get_component(z, "injuries") as Dictionary
	inj["wounds"] = [{"bodyPart": "leg_left", "kind": "cut", "severity": 2, "bleeding": false}]
	impair.call(w)
	if not m.holds_any(z, {"wound.leg_left": true}):
		return _fail("IMPAIR", "a wounded leg was not impaired")
	inj["wounds"] = []
	impair.call(w)
	if m.holds_any(z, {"wound.leg_left": true}):
		return _fail("IMPAIR", "a healed leg kept its impairment")
	return true


# The Dress test as it stood before slice 8: the slot, then the points, each reading the base.
func _reference_better_armor(world: Variant, ent: int, item: int) -> bool:
	var slot: String = SimJobs._dress_slot(world, item)
	if slot == "":
		return false
	var points: int = SimJobs._armor_points(world, item)
	if points <= 0:
		return false
	var c: Variant = world.components.get_component(item, "condition")
	if c is Dictionary and float((c as Dictionary).get("current", 1.0)) <= 0.0:
		return false
	var eq: Variant = world.components.get_component(ent, "equipment")
	if not eq is Dictionary:
		return true
	var slots: Dictionary = ((eq as Dictionary).get("slots", {})) as Dictionary
	if not slots.has(slot):
		return true
	var worn: int = int(slots[slot])
	if worn == item:
		return false
	return points > SimJobs._armor_points(world, worn)


# DRESS. For every person and every item on the district, carried or lying, the one-read test
# answers what the slot-then-points test did. The negatives: some item passes, some item with an
# armour block fails (a skipped slot, a worn piece, or no better), and some item has no armour.
func _the_dress_test_reads_the_base_once_and_answers_the_same() -> bool:
	var w: Variant = _stepped_world()
	var passed: int = 0
	var twins: int = 0
	var armoured_refused: int = 0
	var bare: int = 0
	for ent in SimShambler._people_with_position(w):
		for item in w.components.query(["itemBase"]):
			var got: bool = SimJobs._is_better_armor(w, int(ent), int(item))
			if got != _reference_better_armor(w, int(ent), int(item)):
				return _fail("DRESS", "person %d, item %d: the one-read test said %s" % [int(ent), int(item), str(got)])
			var base: Variant = SimItems.item_base_of(w, int(item))
			var has_armor: bool = base is Dictionary and (base as Dictionary).get("armor") is Dictionary
			if got:
				passed += 1
			elif has_armor:
				armoured_refused += 1
			else:
				bare += 1
	# A garment each person would put on, put on: the same garment is then refused, as is anything
	# no better in its slot -- the armoured refusals the district may not hold on its own.
	for ent in SimShambler._people_with_position(w):
		var eq: Variant = w.components.get_component(int(ent), "equipment")
		if not eq is Dictionary:
			continue
		for item in w.components.query(["itemBase"]):
			if not SimJobs._is_better_armor(w, int(ent), int(item)):
				continue
			var slots: Dictionary = (eq as Dictionary).get("slots", {}) as Dictionary
			var slot: String = SimJobs._dress_slot(w, int(item))
			var had: Variant = slots.get(slot)
			slots[slot] = int(item)
			# A twin of what is now worn: equal, so not better -- the strictness the rule keeps.
			var twin: int = SimItems.spawn_item(w, String((w.components.get_component(int(item), "itemBase") as Dictionary)["baseId"]))
			if SimJobs._is_better_armor(w, int(ent), twin):
				return _fail("DRESS", "a twin of the garment person %d wears counted as better" % int(ent))
			twins += 1
			for other in w.components.query(["itemBase"]):
				var got2: bool = SimJobs._is_better_armor(w, int(ent), int(other))
				if got2 != _reference_better_armor(w, int(ent), int(other)):
					return _fail("DRESS", "person %d wearing %d, item %d: the one-read test said %s" % [int(ent), int(item), int(other), str(got2)])
				var b2: Variant = SimItems.item_base_of(w, int(other))
				if not got2 and b2 is Dictionary and (b2 as Dictionary).get("armor") is Dictionary:
					armoured_refused += 1
			if had == null:
				slots.erase(slot)
			else:
				slots[slot] = had
			break
	if passed == 0 or armoured_refused == 0 or bare == 0 or twins == 0:
		return _fail("DRESS", "passed %d, armour refused %d, bare %d, twins %d: some answer was never judged" % [passed, armoured_refused, bare, twins])
	return true


# SCENT. Two diffusion steps on the stepped district's field, with the buffers swapped, give the
# field a cell-by-cell copy gives -- the second step is the one that writes into the swapped-out
# buffer. The negative: the field has scent and the steps change it.
func _swapped_scent_buffers_are_the_copied_field() -> bool:
	var w: Variant = _stepped_world()
	var f: Variant = w.field
	var want: PackedFloat32Array = (f.scent as PackedFloat32Array).duplicate()
	var start: PackedFloat32Array = want.duplicate()
	var any: bool = false
	for v in start:
		if v != 0.0:
			any = true
			break
	if not any:
		return _fail("SCENT", "the stepped district has no scent to diffuse")
	for step_i in 2:
		want = _reference_diffuse(f, want)
		f.diffuse_scent(1.0)
	if (f.scent as PackedFloat32Array) != want:
		return _fail("SCENT", "two swapped steps are not two copied steps")
	if want == start:
		return _fail("SCENT", "two steps changed nothing, so the lane judged nothing")
	return true


# `diffuse_scent` at a half-life factor of one, with its copy loop, on a copy of the field.
func _reference_diffuse(f: Variant, scent: PackedFloat32Array) -> PackedFloat32Array:
	var next := PackedFloat32Array()
	next.resize(scent.size())
	var keep: float = 1.0 - float(f.calibration["scentDiffusionRate"])
	var rate: float = float(f.calibration["scentDiffusionRate"])
	var floor_v: float = float(f.calibration["scentFloor"])
	var ww: PackedFloat32Array = f._wind_weights
	var cols: int = int(f.cols)
	var rows: int = int(f.rows)
	for cy in rows:
		for cx in cols:
			var here: int = cy * cols + cx
			var value: float = scent[here] * keep
			if cx + 1 < cols:
				value += scent[here + 1] * rate * float(ww[1])
			if cx - 1 >= 0:
				value += scent[here - 1] * rate * float(ww[0])
			if cy + 1 < rows:
				value += scent[here + cols] * rate * float(ww[3])
			if cy - 1 >= 0:
				value += scent[here - cols] * rate * float(ww[2])
			var decayed: float = value * float(f._scent_decay_per_step)
			next[here] = 0.0 if decayed < floor_v else decayed
	var out := PackedFloat32Array()
	out.resize(scent.size())
	for i in next.size():
		out[i] = next[i]
	return out


# ARCS. A view's arc cosines are kept beside the angle they came from, so they must follow the
# angle: after refresh they are the cosines of the eyes' angles, and after the eyes change they are
# the new angles' cosines, not the old -- the stale-memo negative.
func _an_arc_cosine_follows_its_angle() -> bool:
	var w: Variant = _door_world()
	w.vision.refresh(w, w.tilemap)
	var obs: Dictionary = w.components.get_component(w.player, "observer") as Dictionary
	var view: Dictionary = w.vision._views[w.player] as Dictionary
	if float(view["cos_focal"]) != cos(float(obs["focal_half_angle"])) or float(view["cos_peripheral"]) != cos(float(obs["peripheral_half_angle"])):
		return _fail("ARCS", "a view's arc cosines are not its eyes' angles' cosines")
	var old_focal: float = float(view["cos_focal"])
	obs["focal_half_angle"] = 0.25
	obs["peripheral_half_angle"] = 1.25
	w.vision.refresh(w, w.tilemap)
	if float(view["cos_focal"]) != cos(0.25) or float(view["cos_peripheral"]) != cos(1.25):
		return _fail("ARCS", "a view kept its old arc cosines after its eyes changed")
	if float(view["cos_focal"]) == old_focal:
		return _fail("ARCS", "the new focal arc has the old one's cosine, so the lane judged nothing")
	return true


# --- slice 10: the tables read straight ----------------------------------------------------------

# `_body_of` for a method as well as a static function: the body of `func <name>(` in `path`,
# comment lines dropped. Empty when the function is gone.
func _fn_body(path: String, fn_name: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	var at: int = text.find("func %s(" % fn_name)
	if at < 0:
		return ""
	var out: PackedStringArray = PackedStringArray()
	var first: bool = true
	for line in text.substr(at).split("\n"):
		if not first and (line.begins_with("static func ") or line.begins_with("func ")):
			break
		first = false
		if line.strip_edges().begins_with("#"):
			continue
		out.append(line)
	return "\n".join(out)


# TABLE. `table(c)` is the very table `get_component` and `has_component` read: the same value,
# by identity, for every member of every table on a stepped district, and the same "no" for a body
# that lacks the component. A table held before a member is added sees it and one held before a
# removal loses it, which is what lets a pass hold one. A component with no table answers empty
# and stores nothing, so a save is unchanged by the asking. Every pass this slice moved onto
# tables names `.table(` in its own body.
func _a_table_is_the_store_it_reads() -> bool:
	var w: Variant = _stepped_world()
	var members: int = 0
	var absent: int = 0
	var everybody: Array[int] = w.components.query(["position"])
	for c in ["position", "velocity", "shambler", "observer", "body", "corpse", "door", "facing", "posture", "attention_emitter", "grabState", "searchable", "controlled", "raider", "vehicle"]:
		var t: Dictionary = w.components.table(String(c))
		for e in t.keys():
			members += 1
			if not is_same(t.get(e), w.components.get_component(int(e), String(c))):
				return _fail("TABLE", "%s of %d read through the table is not what get_component reads" % [c, int(e)])
			if not w.components.has_component(int(e), String(c)):
				return _fail("TABLE", "the %s table holds %d and has_component says it does not" % [c, int(e)])
		for e in everybody:
			if t.has(int(e)) != w.components.has_component(int(e), String(c)):
				return _fail("TABLE", "%s of %d: the table says %s and has_component disagrees" % [c, int(e), str(t.has(int(e)))])
			if not t.has(int(e)):
				absent += 1
	if members < 100 or absent < 100:
		return _fail("TABLE", "%d members and %d absences judged; the lane has too little to judge" % [members, absent])
	var held: Dictionary = w.components.table("position")
	var fresh: int = 999999
	w.components.set_component(fresh, "position", {"x": 1.0, "y": 1.0})
	if not held.has(fresh) or not is_same(held.get(fresh), w.components.get_component(fresh, "position")):
		return _fail("TABLE", "a table held before a member was added did not see it")
	w.components.remove(fresh, "position")
	if held.has(fresh):
		return _fail("TABLE", "a table held before a removal still holds the removed member")
	var before: String = JSON.stringify(w.components.save())
	var none: Dictionary = w.components.table("no.such.component")
	if not none.is_empty() or w.components.get_component(0, "no.such.component") != null:
		return _fail("TABLE", "a component with no table answered a member")
	if JSON.stringify(w.components.save()) != before:
		return _fail("TABLE", "asking for a missing table changed what a save writes")
	# Each pass names the tables it now reads, so a table swapped for an empty stand-in is red.
	var readers: Array = [
		["res://sim/world.gd", "_integrate_movement", ["vehicle", "position", "velocity", "facing"]],
		["res://sim/modules/sightings.gd", "observe", ["position", "searchable"]],
		["res://sim/modules/sightings.gd", "_observe_one", ["position", "body", "shambler", "raider"]],
		["res://sim/modules/sightings.gd", "_observe_containers", ["searchable", "position"]],
		["res://sim/modules/settlers.gd", "_threats", ["corpse", "shambler", "body", "position"]],
		["res://sim/modules/allegiance.gd", "enemies_within", ["position", "corpse"]],
		["res://sim/modules/attention_emitter.gd", "register_module", ["attention_emitter", "velocity", "posture", "position"]],
		["res://sim/modules/shambler.gd", "register_module", ["shambler", "position", "velocity", "grabState", "attention_emitter"]],
		["res://sim/vision/visibility.gd", "refresh", ["position", "observer", "facing", "posture", "controlled"]],
		["res://sim/modules/fortify.gd", "_presses", ["velocity"]],
		["res://sim/modules/fortify.gd", "_tick_doors", ["door"]],
		["res://sim/modules/fortify.gd", "_occupied_tiles", ["position"]],
		["res://sim/modules/fortify.gd", "_tick_contact", ["door"]],
	]
	for r in readers:
		var body: String = _fn_body(String(r[0]), String(r[1]))
		if body.is_empty():
			return _fail("TABLE", "%s has no %s; the reader check is reading the wrong file" % [r[0], r[1]])
		for c in r[2] as Array:
			if body.find('.table("%s")' % String(c)) < 0:
				return _fail("TABLE", "%s in %s does not read the %s table" % [r[1], r[0], c])
	return true


# The observe pass's per-observer half as it stood before the tenth slice: every read through
# `get_component`, each record found by walking the list, each cupboard by walking its list.
func _reference_observe_one(w: Variant, observer: int, candidates: Array) -> void:
	var comp: Variant = w.components.get_component(observer, "sightings")
	if not comp is Dictionary:
		return
	var seen: Array = (comp as Dictionary)["seen"] as Array
	var tick: int = int(w.tick)
	var square: Variant = w.vision.tiles_for(observer)
	for other in candidates:
		if int(other) == observer:
			continue
		var there: Variant = w.components.get_component(int(other), "position")
		if not there is Dictionary:
			continue
		var x: float = float((there as Dictionary)["x"])
		var y: float = float((there as Dictionary)["y"])
		if not SimSightings._in_square(square, x, y):
			continue
		if int(w.vision.call("detail", observer, x, y)) == 0:
			continue
		var body: Variant = w.components.get_component(int(other), "body")
		if not body is Dictionary or not SimHealth.is_alive(body as Dictionary):
			SimSightings._erase(seen, int(other))
			continue
		var kind: String = "person"
		if w.components.has_component(int(other), "shambler"):
			kind = "zombie"
		elif w.components.has_component(int(other), "raider"):
			kind = "raider"
		var found: bool = false
		for row in seen:
			if int((row as Dictionary)["e"]) == int(other):
				(row as Dictionary)["x"] = x
				(row as Dictionary)["y"] = y
				(row as Dictionary)["tick"] = tick
				(row as Dictionary)["kind"] = kind
				found = true
				break
		if not found:
			seen.append({"e": int(other), "x": x, "y": y, "tick": tick, "kind": kind})
	SimSightings._prune(seen, tick)


func _reference_observe_containers(w: Variant, observer: int, boxes: Array) -> void:
	var comp: Variant = w.components.get_component(observer, "sightings")
	if not comp is Dictionary:
		return
	if not (comp as Dictionary).has("containers"):
		(comp as Dictionary)["containers"] = []
	var known: Array = (comp as Dictionary)["containers"] as Array
	var square: Variant = w.vision.tiles_for(observer)
	for box in boxes:
		var s: Variant = w.components.get_component(int(box), "searchable")
		if not s is Dictionary:
			continue
		if bool((s as Dictionary).get("searched", false)):
			SimSightings._erase(known, int(box))
			continue
		var there: Variant = w.components.get_component(int(box), "position")
		if not there is Dictionary:
			continue
		var x: float = float((there as Dictionary)["x"])
		var y: float = float((there as Dictionary)["y"])
		if not SimSightings._in_square(square, x, y):
			continue
		if int(w.vision.call("detail", observer, x, y)) == 0:
			continue
		var found: bool = false
		for row in known:
			if int((row as Dictionary)["e"]) == int(box):
				found = true
				break
		if not found:
			known.append({"e": int(box), "x": x, "y": y})


# RECALL. Two identical districts, every observer's memory primed with a stale copy of one body it
# can see, a second record of that body behind it (the walk updated the first and left the second),
# a record of a body that has since died where the observer can see it, a cupboard remembered
# twice and a searched cupboard remembered once; one observes the shipped way and one the old way,
# for every observer, all cupboards to all, over twenty ticks. Every memory must come out the
# same, order included. The negatives: some record was updated in place, some appended, the dead
# body's records erased, and a cupboard newly remembered.
func _remembering_by_map_is_remembering_by_walk() -> bool:
	var worlds: Array = [_stepped_world(), _stepped_world()]
	var observers: Array[int] = worlds[0].components.query(["sightings", "observer", "position"])
	var boxes: Array[int] = worlds[0].components.query(["searchable", "position"])
	var bodies: Array[int] = worlds[0].components.query(["body", "position"])
	if observers.size() < 3 or boxes.size() < 2:
		return _fail("RECALL", "%d observers and %d cupboards; the lane has too little to judge" % [observers.size(), boxes.size()])
	var searched: int = boxes[boxes.size() - 1]
	var updated: int = 0
	var appended: int = 0
	var erased: int = 0
	var newly_known: int = 0
	var primed_dead: bool = false
	for w in worlds:
		(w.components.get_component(searched, "searchable") as Dictionary)["searched"] = true
	# Prime: per observer, the first body it can see gets a stale record and a duplicate; the
	# second one it can see is killed in both worlds and remembered.
	for ob in observers:
		var visible: Array[int] = []
		for e in bodies:
			if int(e) == ob:
				continue
			var at: Vector2 = _positioned(worlds[0], int(e))
			if SimSightings._in_square(worlds[0].vision.tiles_for(ob), at.x, at.y) and int(worlds[0].vision.call("detail", ob, at.x, at.y)) != 0:
				visible.append(int(e))
		for w in worlds:
			var sc: Dictionary = w.components.get_component(ob, "sightings") as Dictionary
			var rows: Array = []
			if visible.size() >= 1:
				rows.append({"e": visible[0], "x": -1.0, "y": -1.0, "tick": int(w.tick) - 5, "kind": "stale"})
				rows.append({"e": visible[0], "x": -2.0, "y": -2.0, "tick": int(w.tick) - 6, "kind": "second"})
			if visible.size() >= 2 and not primed_dead:
				rows.append({"e": visible[1], "x": 0.0, "y": 0.0, "tick": int(w.tick) - 1, "kind": "zombie"})
			sc["seen"] = rows
			sc["containers"] = [{"e": boxes[0], "x": 0.0, "y": 0.0}, {"e": boxes[0], "x": 0.0, "y": 0.0}, {"e": searched, "x": 0.0, "y": 0.0}]
		if visible.size() >= 2 and not primed_dead:
			for w in worlds:
				(w.components.get_component(visible[1], "body") as Dictionary)["head"] = 0
			primed_dead = true
	if not primed_dead:
		return _fail("RECALL", "no observer could see two bodies, so the erase was never judged")
	# The kind a record carries, on all three answers: the district may have no raider in view.
	for k in [[1, "zombie"], [2, "raider"], [3, "person"]]:
		if SimSightings._kind_of({1: {}}, {2: {}}, int(k[0])) != String(k[1]):
			return _fail("RECALL", "entity %d is remembered as %s, not %s" % [int(k[0]), SimSightings._kind_of({1: {}}, {2: {}}, int(k[0])), k[1]])
	for i in 20:
		var before: Dictionary = {}
		for ob in observers:
			before[ob] = JSON.stringify((worlds[0].components.get_component(ob, "sightings") as Dictionary)["seen"])
		var before_boxes: Dictionary = {}
		for ob in observers:
			var ids: Dictionary = {}
			for row in (worlds[0].components.get_component(ob, "sightings") as Dictionary)["containers"] as Array:
				ids[int((row as Dictionary)["e"])] = true
			before_boxes[ob] = ids
		SimSightings.observe(worlds[0])
		var candidates: Array = []
		for e in worlds[1].components.query(["body", "position"]):
			candidates.append(int(e))
		for ob in observers:
			_reference_observe_one(worlds[1], ob, candidates)
			_reference_observe_containers(worlds[1], ob, boxes)
		for ob in observers:
			var a: Dictionary = worlds[0].components.get_component(ob, "sightings") as Dictionary
			var r: Dictionary = worlds[1].components.get_component(ob, "sightings") as Dictionary
			if JSON.stringify(a["seen"]) != JSON.stringify(r["seen"]) or JSON.stringify(a["containers"]) != JSON.stringify(r["containers"]):
				return _fail("RECALL", "tick %d, observer %d remembers %s where the walk gives %s" % [i, ob, JSON.stringify(a), JSON.stringify(r)])
			var was: Array = JSON.parse_string(String(before[ob])) as Array
			var now: Array = a["seen"] as Array
			for row in now:
				var hit: bool = false
				for old in was:
					if int((old as Dictionary)["e"]) == int((row as Dictionary)["e"]):
						hit = true
						if int((old as Dictionary)["tick"]) != int((row as Dictionary)["tick"]):
							updated += 1
						break
				if not hit:
					appended += 1
			var now_ids: Dictionary = {}
			for row in now:
				now_ids[int((row as Dictionary)["e"])] = true
			for old in was:
				if not now_ids.has(int((old as Dictionary)["e"])):
					erased += 1
			for row in a["containers"] as Array:
				if not (before_boxes[ob] as Dictionary).has(int((row as Dictionary)["e"])):
					newly_known += 1
		for w in worlds:
			w.tick += 1
	if updated == 0 or appended == 0 or erased == 0 or newly_known == 0:
		return _fail("RECALL", "updated %d, appended %d, erased %d, newly known %d; the lane judged an empty case" % [updated, appended, erased, newly_known])
	return true


# SWING. `_occupied_tiles` holds exactly the tiles `_tile_occupied` calls occupied: every tile any
# body stands on and every tile beside one, on a stepped district. The negatives: some tile is
# occupied and some is not.
func _the_door_swing_asks_the_set_the_walk_answered() -> bool:
	var w: Variant = _stepped_world()
	var occupied: Dictionary = SimFortify._occupied_tiles(w)
	var yes: int = 0
	var no: int = 0
	for e in w.components.query(["position", "velocity"]):
		var at: Vector2 = _positioned(w, int(e))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var tx: int = floori(at.x) + dx
				var ty: int = floori(at.y) + dy
				var walk: bool = SimFortify._tile_occupied(w, tx, ty)
				if occupied.has(Vector2i(tx, ty)) != walk:
					return _fail("SWING", "tile %d,%d: the set says %s and the walk says %s" % [tx, ty, str(occupied.has(Vector2i(tx, ty))), str(walk)])
				if walk:
					yes += 1
				else:
					no += 1
	if yes == 0 or no == 0:
		return _fail("SWING", "%d occupied and %d empty tiles judged; the lane judged an empty case" % [yes, no])
	if _body_of("res://sim/modules/fortify.gd", "_tick_doors").find("_occupied_tiles(") < 0:
		return _fail("SWING", "the door swing does not ask _occupied_tiles")
	return true
