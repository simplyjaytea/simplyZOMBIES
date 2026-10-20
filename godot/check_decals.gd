extends SceneTree
# The marks a fight leaves (plan item A13; docs/30, "Blood and bullet decals persist, for
# everything"). `npm run godot:check:decals` -> DECALS_OK.
#
# The owner's call is two halves, and this gate holds both: **every** hit, bite, death, bleed,
# stray round and lightning strike leaves a mark whether or not the player saw it happen
# (sim/modules/decals.gd), and a mark is **drawn only where the player sees now**
# (presentation/decal_look.gd) -- so a mark made behind a wall is in the record and on nobody's
# screen until the player walks round and looks. Each lane is red both ways.
#
#   HIT      a blow leaves one splat, thrown past the body away from the attacker; a bite leaves
#            one under the bitten body. TN: a step with no blow leaves nothing; a splat that would
#            land in a wall lands under the body instead.
#   UNSEEN   a blow behind a wall is recorded and draws nothing; the same mark draws once its tile
#            is in the player's sight. TN: a mark on a seen tile draws on the first frame.
#   POOL     a death leaves one pool however many times `entity.killed` fires for it (three
#            here), two deaths two pools; the pool is a splash, then the pack's fresh pool, then its
#            dry pool, as it ages.
#   BLEED    a body with a deep wound drips as wounds.bleed takes its blood, a still body's drips
#            pool into one another, and a crawling body leaves smears. TN: the same body unhurt
#            leaves nothing.
#   ROUND    a real pistol shot that hits nobody marks the wall it flies into, inside the wall's
#            tile; a tree takes chips, a shut door chips, a parked car a dent; glass lets the
#            round through to the wall behind. TN: a round that found a body marks no wall, and a
#            round with nothing in its reach marks nothing.
#   SCORCH   a lightning strike leaves a scorch where it came down. TN: one with no place, none.
#   BOUND    a chunk never holds more than PER_CHUNK marks, a body's pool outlives the splats
#            pushed out round it, and every change bumps the chunk's revision (the renderer's
#            rebake signal). TN: a chunk below the bound loses nothing.
#   BAKE     the ground marks are baked per chunk and a frame re-bakes only what changed: a frame
#            after a frame bakes nothing, a mark in a chunk's middle re-bakes that chunk alone, one
#            that crosses a border re-bakes the neighbour it reaches too, and blood drying re-bakes
#            the chunks it lies in. Blood spilling onto a wall's tile is cleared from the bake, so it
#            never paints over the cap. TN: the same pool on open ground keeps both tiles it covers.
#   SAVE     the record survives a JSON round trip exactly, and an older save without one
#            restores none. TN: a restore replaces the marks, never adds to them.
#   WALL     a hole in a wall standing as a picture is drawn by that picture's own call, on its
#            face, and not by the ground pass; seen or not decides it there too.
#   MATTE    every blood picture is the pack's dark blood: no solid pixel brighter than
#            MATTE_VALUE_MAX. TN: a fabricated bright red picture is refused by the same predicate.
#   DRAWN    the real scene: _draw_district calls the ground pass and _draw_a2_wall_piece the
#            wall pass, one frame of main.gd blits a seen mark, and a mark behind the wall is not
#            blitted. Every picture art_for names resolves at the pack's 32x32.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const SimDecals = preload("res://sim/modules/decals.gd")
const SimStances = preload("res://sim/stances.gd")
const SimVisibility = preload("res://sim/vision/visibility.gd")
const Clock = preload("res://sim/time/clock.gd")
const DecalLook = preload("res://presentation/decal_look.gd")
const Appearance = preload("res://presentation/appearance.gd")

const MAIN_GD: String = "res://presentation/main.gd"
const SCENE_PATH: String = "res://presentation/main.tscn"
const WALL_X: int = 4
const MATTE_VALUE_MAX: float = 0.56
const CAMERA: Dictionary = {"x": 12.0, "y": 12.0, "zoom": 64.0, "width": 1280.0, "height": 720.0}
const BOUNDS: Dictionary = {"minX": 0.0, "minY": 0.0, "maxX": 23.0, "maxY": 23.0}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _a_blow_leaves_a_splat() and ok
	ok = _unseen_is_kept_and_not_drawn() and ok
	ok = _a_death_leaves_one_pool() and ok
	ok = _a_bleeding_body_drips() and ok
	ok = _a_stray_round_marks_what_stops_it() and ok
	ok = _lightning_scorches() and ok
	ok = _a_chunk_is_bounded() and ok
	ok = _a_new_mark_rebakes_its_chunk() and ok
	ok = _the_record_survives_a_save() and ok
	ok = _a_wall_picture_wears_its_holes() and ok
	ok = _blood_is_matte() and ok
	var drawn: bool = await _the_scene_draws_what_is_seen()
	ok = drawn and ok
	if ok:
		print("DECALS_OK")
		quit(0)
	else:
		push_error("DECALS_FAILED")
		quit(1)


# --- fixtures --------------------------------------------------------------------------------

# A 24x24 street with a wall down column 4, four tiles behind the player, who stands at (8, 12)
# looking east: what is west of the wall is out of sight in every direction.
func _world(map_edit: Callable = Callable()) -> Variant:
	var f: Dictionary = {"seed": 33, "tick_hz": 20, "map": {"width": 24, "height": 24, "walls": []}, "player": {"id": 0, "x": 8.0, "y": 12.0, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	var w: Variant = World.new(f)
	w.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	var map: Variant = SimTileMap.blank_map(24, 24)
	for y in 24:
		map.tiles[y * 24 + WALL_X] = SimTileMap.Tile.Wall
	if map_edit.is_valid():
		map_edit.call(map)
	SimBoot.attach_kernel(w, map)
	SimHealth.register_module(w)
	SimWounds.register_module(w)
	SimMelee.register_module(w)
	SimRanged.register_module(w)
	SimInventory.register_module(w)
	SimDecals.register_module(w)
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	w.components.set_component(w.player, "observer", SimVisibility.daylight_eyes())
	SimHealth.make_survivor_body(w, w.player)
	SimHealth.make_stamina(w, w.player)
	SimInventory.make_inventory(w, w.player)
	w.step()
	w.events.drain()
	return w


func _all(w: Variant) -> Array:
	var out: Array = []
	for c in (w.decals as Dictionary).values():
		out.append_array((c as Dictionary)["d"] as Array)
	return out


func _of(w: Variant, kind: String) -> Array:
	var out: Array = []
	for r in _all(w):
		if String((r as Dictionary)["k"]) == kind:
			out.append(r)
	return out


func _shambler_at(w: Variant, at: Vector2) -> int:
	var z: int = SimRoster.spawn_zombie(w, at.x, at.y, SimRoster.TYPE_SHAMBLER, w.rng.stream("shambler"))
	w.events.drain()
	return z


func _at_m(r: Dictionary) -> Vector2:
	return Vector2(float(r["x"]) / SimDecals.ART_PX, float(r["y"]) / SimDecals.ART_PX)


func _publish_and_step(w: Variant, events: Array) -> void:
	for ev in events:
		w.events.publish(ev)
	w.events.drain()


# --- HIT ---------------------------------------------------------------------------------------

func _a_blow_leaves_a_splat() -> bool:
	var w: Variant = _world()
	var z: int = _shambler_at(w, Vector2(12.0, 12.0))
	for i in 3:
		w.step()
	if not _all(w).is_empty():
		push_error("HIT: three quiet steps left %s" % str(_all(w)))
		return false
	_publish_and_step(w, [{"type": "attack.connected", "attacker": w.player, "target": z, "bodyPart": "torso", "damage": 1.0}])
	var splats: Array = _of(w, "splat")
	if splats.size() != 1:
		push_error("HIT: one blow left %d splats" % splats.size())
		return false
	var at: Vector2 = _at_m(splats[0] as Dictionary)
	var off: Vector2 = at - Vector2(12.0, 12.0)
	if off.x <= 0.0 or off.length() > SimDecals.SPLAT_MAX_M + 0.05 or off.length() < SimDecals.SPLAT_MIN_M - 0.05:
		push_error("HIT: the splat landed at %s, %s from a body struck from the west; it is thrown east, %s..%s m" % [str(at), str(off), SimDecals.SPLAT_MIN_M, SimDecals.SPLAT_MAX_M])
		return false
	# A bite: under the bitten body, no attacker to throw it from.
	_publish_and_step(w, [{"type": "bite.landed", "victim": w.player, "source": z, "bodyPart": "arm_l", "damage": 1.0}])
	if _of(w, "splat").size() != 2:
		push_error("HIT: a bite left no splat")
		return false
	# TN: struck against the wall from the east, a throw west would land in the wall; it lands
	# under the body.
	var w2: Variant = _world()
	var hugger: int = _shambler_at(w2, Vector2(5.1, 12.5))
	w2.components.set_component(w2.player, "position", {"x": 9.0, "y": 12.5})
	for i in 12:
		_publish_and_step(w2, [{"type": "attack.connected", "attacker": w2.player, "target": hugger, "bodyPart": "torso", "damage": 1.0}])
	for r in _of(w2, "splat"):
		var p: Vector2 = _at_m(r as Dictionary)
		if SimTileMap.is_solid(w2.tilemap, floori(p.x), floori(p.y)):
			push_error("HIT: a splat landed inside the wall at %s" % str(p))
			return false
	print("HIT OK a blow threw one splat %.2f m east of a body struck from the west, a bite left one, quiet steps left none, and twelve blows against a wall put nothing in it" % off.length())
	return true


# --- UNSEEN ------------------------------------------------------------------------------------

func _unseen_is_kept_and_not_drawn() -> bool:
	var w: Variant = _world()
	var behind: int = _shambler_at(w, Vector2(2.5, 12.5))
	var front: int = _shambler_at(w, Vector2(12.5, 12.5))
	_publish_and_step(w, [{"type": "attack.connected", "attacker": front, "target": behind, "bodyPart": "torso", "damage": 1.0}])
	var kept: Array = _of(w, "splat")
	if kept.size() != 1:
		push_error("UNSEEN: a blow behind the wall left %d marks; every event leaves one, seen or not" % kept.size())
		return false
	var look: RefCounted = DecalLook.new()
	var seen: Variant = w.vision.tiles_for(int(w.player))
	var draws: Array = look.call("ground_draws", w, CAMERA, seen, {}, BOUNDS) as Array
	if not draws.is_empty():
		push_error("UNSEEN: a splat behind the wall at %s drew %s" % [str(_at_m(kept[0] as Dictionary)), str(draws)])
		return false
	# TN: one on a seen tile draws.
	_publish_and_step(w, [{"type": "attack.connected", "attacker": w.player, "target": front, "bodyPart": "torso", "damage": 1.0}])
	draws = look.call("ground_draws", w, CAMERA, seen, {}, BOUNDS) as Array
	if draws.is_empty() or not ((draws[0] as Dictionary)["keys"] as Array).has(DecalLook.art_for("splat", 1, 0, int((_of(w, "splat")[1] as Dictionary)["v"]))):
		push_error("UNSEEN: a splat in front of the player drew %s" % str(draws))
		return false
	# Walk round: put the player west of the wall; the first mark's tile is seen now and it draws.
	w.components.set_component(w.player, "position", {"x": 1.5, "y": 12.5})
	w.step()
	seen = w.vision.tiles_for(int(w.player))
	var tile: Vector2i = Vector2i(floori(_at_m(kept[0] as Dictionary).x), floori(_at_m(kept[0] as Dictionary).y))
	if not DecalLook.visible(seen, tile):
		push_error("UNSEEN: the player west of the wall still does not see %s; the fixture proves nothing" % str(tile))
		return false
	draws = look.call("ground_draws", w, CAMERA, seen, {}, BOUNDS) as Array
	var hit_west: bool = false
	for d in draws:
		if ((d as Dictionary)["rect"] as Rect2).position.x < (float(WALL_X) - float(CAMERA["x"])) * 64.0 + 640.0:
			hit_west = true
	if not hit_west:
		push_error("UNSEEN: with the player beside it, the mark behind the wall still drew nothing (%s)" % str(draws))
		return false
	print("UNSEEN OK a blow behind the wall was recorded and drew nothing, one in front drew on the first frame, and the hidden one drew once the player walked round to it")
	return true


# --- POOL --------------------------------------------------------------------------------------

func _a_death_leaves_one_pool() -> bool:
	var w: Variant = _world()
	var z: int = _shambler_at(w, Vector2(10.5, 12.5))
	var z2: int = _shambler_at(w, Vector2(14.5, 10.5))
	var death: Dictionary = {"type": "entity.killed", "entity": z, "x": 10.5, "y": 12.5}
	_publish_and_step(w, [death, death.duplicate(), {"type": "entity.killed", "entity": z}])
	if _of(w, "pool").size() != 1:
		push_error("POOL: one body killed three times left %d pools" % _of(w, "pool").size())
		return false
	_publish_and_step(w, [{"type": "entity.killed", "entity": z2, "x": 14.5, "y": 10.5}])
	if _of(w, "pool").size() != 2:
		push_error("POOL: a second body left no pool of its own")
		return false
	var rec: Dictionary = _of(w, "pool")[0] as Dictionary
	var t: int = int(rec["t"])
	var ages: Array = [[t, "fx_blood_hit_0"], [t + DecalLook.POOL_SPREAD_TICKS, "fx_blood_pool_fresh"], [t + DecalLook.DRY_TICKS, "fx_blood_pool_dry"]]
	for a in ages:
		var items: Array = DecalLook.items_for(w, rec, int(a[0]))
		if items.size() != 1 or String((items[0] as Dictionary)["key"]) != String(a[1]):
			push_error("POOL: at age %d the pool drew %s, not %s" % [int(a[0]) - t, str(items), String(a[1])])
			return false
	print("POOL OK one body killed three times left one pool, a second body its own, and a pool spreads from a splash to the fresh pool to the dry one")
	return true


# --- BLEED -------------------------------------------------------------------------------------

func _bleeder(w: Variant, at: Vector2, wounded: bool) -> int:
	var e: int = w.entities.spawn()
	w.components.set_component(e, "position", {"x": at.x, "y": at.y})
	w.components.set_component(e, "posture", SimStances.make_posture(SimStances.Stance.Walk))
	SimHealth.make_survivor_body(w, e)
	if wounded:
		SimWounds.append_wound(w, e, "cut", "torso", -1, 30.0, "", SimWounds.Severity.DeepWound)
	else:
		w.components.set_component(e, "injuries", {"wounds": [], "bloodLoss": 0.0, "bledOut": false})
	return e


func _a_bleeding_body_drips() -> bool:
	var w: Variant = _world()
	var still: int = _bleeder(w, Vector2(14.5, 6.5), true)
	var fine: int = _bleeder(w, Vector2(14.5, 18.5), false)
	for i in 400:
		w.step()
	var loss: float = float((w.components.get_component(still, "injuries") as Dictionary)["bloodLoss"])
	var drops: int = floori(loss / SimDecals.DRIP_LOSS)
	var drips: Array = _of(w, "drip")
	if loss <= SimDecals.DRIP_LOSS * 3.0 or drips.is_empty():
		push_error("BLEED: a deep wound lost %.2f over 400 ticks and left %d drips" % [loss, drips.size()])
		return false
	var grown: int = 0
	for r in drips:
		var p: Vector2 = _at_m(r as Dictionary)
		if p.distance_to(Vector2(14.5, 18.5)) < 1.0:
			push_error("BLEED: the unhurt body left a drip at %s" % str(p))
			return false
		if int((r as Dictionary)["s"]) > 1:
			grown += 1
	if drips.size() >= drops or grown == 0:
		push_error("BLEED: %d drops from a body standing still made %d drips, none pooled" % [drops, drips.size()])
		return false
	# Crawling: the same wound on a body dragging itself east leaves smears.
	var w2: Variant = _world()
	var crawler: int = _bleeder(w2, Vector2(10.5, 6.5), true)
	(w2.components.get_component(crawler, "posture") as Dictionary)["current"] = SimStances.Stance.Crawl
	for i in 400:
		var p2: Dictionary = w2.components.get_component(crawler, "position") as Dictionary
		p2["x"] = float(p2["x"]) + 0.02
		w2.step()
	var smears: Array = _of(w2, "smear")
	if smears.is_empty():
		push_error("BLEED: a crawling bleeder left %s and no smear" % str(_all(w2)))
		return false
	for r in smears:
		if int((r as Dictionary)["a"]) <= 0:
			push_error("BLEED: a smear %s runs against the crawl" % str(r))
			return false
	if fine < 0:
		return false
	print("BLEED OK a deep wound lost %.1f over 400 ticks: %d drops pooled into %d drips (%d grown), the unhurt body left none, and a crawl east left %d smears running east" % [loss, drops, drips.size(), grown, smears.size()])
	return true


# --- ROUND -------------------------------------------------------------------------------------

func _shoot(w: Variant) -> Array:
	var pistol: int = SimItems.spawn_item(w, "item.pistol.service", {"tier": "scavenged"})
	SimInventory.equip(w, w.player, pistol)
	SimInventory.stow(w, w.player, SimItems.spawn_item(w, "item.ammo.9mm", {"tier": "scavenged", "count": 6}))
	w.events.drain()
	var fired: Array = []
	w.commands.push({"type": "fire"})
	for i in 40:
		w.step()
		for e in w.events.drained:
			if String((e as Dictionary).get("type", "")) == "weapon.fired":
				fired.append(e)
		if not fired.is_empty():
			break
	return fired


func _a_stray_round_marks_what_stops_it() -> bool:
	# A real shot west into the wall: nobody in the cone.
	var w: Variant = _world()
	w.components.set_component(w.player, "facing", {"radians": PI})
	var fired: Array = _shoot(w)
	if fired.is_empty():
		push_error("ROUND: the pistol never fired; the lane has nothing to judge")
		return false
	if not (fired[0] as Dictionary).has("dx") or int((fired[0] as Dictionary).get("hit", 0)) != -1:
		push_error("ROUND: weapon.fired carries %s; decals need the line, the reach and hit -1" % str(fired[0]))
		return false
	var holes: Array = _of(w, "hole")
	if holes.size() != 1:
		push_error("ROUND: a miss into the wall left %s" % str(_all(w)))
		return false
	var hp: Vector2 = _at_m(holes[0] as Dictionary)
	if floori(hp.x) != WALL_X:
		push_error("ROUND: the hole is at %s, not inside the wall's column %d" % [str(hp), WALL_X])
		return false
	# TN: the same shot with a body in the cone marks no wall.
	var w2: Variant = _world()
	w2.components.set_component(w2.player, "facing", {"radians": PI})
	_shambler_at(w2, Vector2(6.5, 12.0))
	var fired2: Array = _shoot(w2)
	if fired2.is_empty() or int((fired2[0] as Dictionary).get("hit", -1)) < 0 or not _of(w2, "hole").is_empty():
		push_error("ROUND: a round that found a body (%s) left %s" % [str(fired2), str(_of(w2, "hole"))])
		return false
	# Surfaces, by the event's own line (the handler is what is under test here).
	var cases: Array = [
		["tree", SimTileMap.Tile.Tree, null, "chips"],
		["shut door", SimTileMap.Tile.Door, {"kind": "door", "open": false}, "chips"],
		["open door", SimTileMap.Tile.Door, {"kind": "door", "open": true}, "hole"],
		["window", SimTileMap.Tile.Window, null, "hole"],
		["boarded window", SimTileMap.Tile.Window, {"kind": "board", "stage": 1}, "chips"],
	]
	for c in cases:
		var tile_kind: int = int(c[1])
		var ov: Variant = c[2]
		var w3: Variant = _world(func(map: Variant) -> void:
			map.tiles[12 * 24 + 15] = tile_kind
			# The wall behind it, so a round that passes still stops somewhere.
			map.tiles[12 * 24 + 20] = SimTileMap.Tile.Wall
			if ov != null:
				map.overlays[12 * 24 + 15] = ov
		)
		_publish_and_step(w3, [{"type": "weapon.fired", "entity": w3.player, "item": -1, "x": 8.5, "y": 12.5, "dx": 1.0, "dy": 0.0, "reach": 30.0, "hit": -1}])
		var marks: Array = _all(w3)
		var want_x: int = 20 if String(c[3]) == "hole" else 15
		if marks.size() != 1 or String((marks[0] as Dictionary)["k"]) != String(c[3]) or floori(_at_m(marks[0] as Dictionary).x) != want_x:
			push_error("ROUND: a round into a %s left %s; it should leave %s at column %d" % [String(c[0]), str(marks), String(c[3]), want_x])
			return false
	# A parked car: a Low tile under a vehicle record.
	var w4: Variant = _world(func(map: Variant) -> void:
		for x in range(14, 19):
			for y in range(12, 14):
				map.tiles[y * 24 + x] = SimTileMap.Tile.Low
		map.vehicles = [{"x": 14, "y": 12, "w": 5, "h": 2, "axis": "ew", "class": "vehicle.sedan", "facing": "e"}]
	)
	_publish_and_step(w4, [{"type": "weapon.fired", "entity": w4.player, "item": -1, "x": 8.5, "y": 12.5, "dx": 1.0, "dy": 0.0, "reach": 30.0, "hit": -1}])
	if _of(w4, "dent").size() != 1:
		push_error("ROUND: a round into a parked car left %s" % str(_all(w4)))
		return false
	# TN: nothing in reach.
	var w5: Variant = _world()
	_publish_and_step(w5, [{"type": "weapon.fired", "entity": w5.player, "item": -1, "x": 8.5, "y": 12.5, "dx": 1.0, "dy": 0.0, "reach": 6.0, "hit": -1}])
	if not _all(w5).is_empty():
		push_error("ROUND: a round with an empty street in its reach left %s" % str(_all(w5)))
		return false
	print("ROUND OK a real pistol miss holed the wall inside its column at %s, a hit marked no wall, a tree and a shut door took chips, an open door and glass let the round through to the wall, a car took a dent, and an empty reach left nothing" % str(hp))
	return true


# --- SCORCH ------------------------------------------------------------------------------------

func _lightning_scorches() -> bool:
	var w: Variant = _world()
	_publish_and_step(w, [{"type": "weather.lightning", "tick": int(w.tick)}])
	if not _all(w).is_empty():
		push_error("SCORCH: a bolt with no place left %s" % str(_all(w)))
		return false
	_publish_and_step(w, [{"type": "weather.lightning", "x": 16.5, "y": 5.5, "tick": int(w.tick)}])
	var s: Array = _of(w, "scorch")
	if s.size() != 1 or _at_m(s[0] as Dictionary).distance_to(Vector2(16.5, 5.5)) > 0.05:
		push_error("SCORCH: a bolt at (16.5, 5.5) left %s" % str(_all(w)))
		return false
	print("SCORCH OK a lightning strike scorched the ground where it came down, and a bolt with no place left nothing")
	return true


# --- BOUND -------------------------------------------------------------------------------------

func _a_chunk_is_bounded() -> bool:
	var w: Variant = _world()
	SimDecals.add(w, "pool", 9.5, 9.5, {"e": 77})
	var below: int = SimDecals.PER_CHUNK - 1
	for i in below - 1:
		SimDecals.add(w, "splat", 8.0 + float(i % 8) * 0.9, 8.0 + float(i / 8) * 0.9)
	var ch: Vector2i = SimDecals.chunk_of_px(roundi(9.5 * 32), roundi(9.5 * 32))
	if SimDecals.in_chunk(w, ch.x, ch.y).size() != below:
		push_error("BOUND: %d marks in a chunk below the bound kept %d" % [below, SimDecals.in_chunk(w, ch.x, ch.y).size()])
		return false
	var rev: int = SimDecals.rev_of(w, ch.x, ch.y)
	for i in 100:
		SimDecals.add(w, "splat", 8.2 + float(i % 7) * 0.9, 8.2 + float(i % 5) * 0.9)
	var kept: Array = SimDecals.in_chunk(w, ch.x, ch.y)
	if kept.size() != SimDecals.PER_CHUNK:
		push_error("BOUND: a chunk holds %d marks; the bound is %d" % [kept.size(), SimDecals.PER_CHUNK])
		return false
	var pool_kept: bool = false
	for r in kept:
		if String((r as Dictionary)["k"]) == "pool":
			pool_kept = true
	if not pool_kept:
		push_error("BOUND: the body's pool was pushed out by splats")
		return false
	if SimDecals.rev_of(w, ch.x, ch.y) <= rev:
		push_error("BOUND: a hundred new marks left the chunk's revision at %d" % rev)
		return false
	var look: RefCounted = DecalLook.new()
	var items: Array = look.call("chunk_items", w, ch.x, ch.y) as Array
	if items.size() > SimDecals.PER_CHUNK * (SimDecals.SMEAR_MAX_PX / DecalLook.SMEAR_STEP_PX + 2):
		push_error("BOUND: one chunk drew %d items" % items.size())
		return false
	print("BOUND OK a chunk below the bound kept all %d marks, one pushed past it held %d with the body's pool still there, its revision moved, and its draw list is %d items" % [below, kept.size(), items.size()])
	return true


# --- BAKE --------------------------------------------------------------------------------------

func _bakes_for(look: RefCounted, w: Variant, seen: Variant) -> int:
	var before: int = int(look.get("bakes"))
	look.call("ground_draws", w, CAMERA, seen, {}, BOUNDS)
	return int(look.get("bakes")) - before


func _row_bits(look: RefCounted, chunk: Vector2i, row: int) -> int:
	var b: Variant = (look.get("_baked") as Dictionary).get(chunk)
	return int(((b as Dictionary)["rows"] as PackedInt32Array)[row]) if b is Dictionary else 0


func _a_new_mark_rebakes_its_chunk() -> bool:
	var w: Variant = _world()
	var look: RefCounted = DecalLook.new()
	var seen: Variant = w.vision.tiles_for(int(w.player))
	SimDecals.add(w, "splat", 12.0, 12.0)
	var first: int = _bakes_for(look, w, seen)
	if first != 9:
		push_error("BAKE: the first frame over nine chunks baked %d" % first)
		return false
	var again: int = _bakes_for(look, w, seen)
	if again != 0:
		push_error("BAKE: a frame with nothing new re-baked %d chunks" % again)
		return false
	SimDecals.add(w, "splat", 12.0, 12.0)
	var middle: int = _bakes_for(look, w, seen)
	if middle != 1:
		push_error("BAKE: a mark in the middle of chunk (1, 1) re-baked %d chunks, not 1" % middle)
		return false
	SimDecals.add(w, "splat", 15.9, 12.0)
	var border: int = _bakes_for(look, w, seen)
	if border != 2:
		push_error("BAKE: a mark across the border of (1, 1) and (2, 1) re-baked %d chunks, not 2" % border)
		return false
	w.tick += DecalLook.DRY_TICKS
	var dried: int = _bakes_for(look, w, seen)
	if dried != 2:
		push_error("BAKE: blood drying re-baked %d chunks, not the 2 it lies in" % dried)
		return false
	# A pool on the wall's east edge: half of it would lie on the wall tile.
	var w2: Variant = _world()
	var look2: RefCounted = DecalLook.new()
	SimDecals.add(w2, "pool", float(WALL_X) + 1.0, 12.5, {"e": 5})
	SimDecals.add(w2, "pool", float(WALL_X) + 2.0, 20.5, {"e": 6})
	w2.tick += DecalLook.POOL_SPREAD_TICKS
	look2.call("ground_draws", w2, CAMERA, null, {}, BOUNDS)
	var wall_row: int = _row_bits(look2, Vector2i(0, 1), 12 - 8)
	if (wall_row & (1 << WALL_X)) != 0 or (wall_row & (1 << (WALL_X + 1))) == 0:
		push_error("BAKE: the pool beside the wall baked row bits %s; the wall tile must be clear and the floor tile held" % String.num_int64(wall_row, 2))
		return false
	var open_row: int = _row_bits(look2, Vector2i(0, 2), 20 - 16)
	if (open_row & (1 << (WALL_X + 1))) == 0 or (open_row & (1 << (WALL_X + 2))) == 0:
		push_error("BAKE: the pool on open ground baked row bits %s; it covers two tiles and both must hold it" % String.num_int64(open_row, 2))
		return false
	print("BAKE OK the first frame baked nine chunks and the next none, a mark in a chunk's middle re-baked 1, one across a border 2, drying 2, and a pool beside a wall kept off the wall's tile while the same pool on open ground held both of its tiles")
	return true


# --- SAVE --------------------------------------------------------------------------------------

func _the_record_survives_a_save() -> bool:
	var w: Variant = _world()
	SimDecals.add(w, "pool", 9.5, 9.5, {"e": 3})
	SimDecals.add(w, "smear", 15.25, 3.75, {"a": 12, "b": -6})
	SimDecals.add(w, "hole", 4.5, 12.25)
	var snap: Dictionary = w.snapshot()
	var back: Variant = JSON.parse_string(JSON.stringify(snap))
	var w2: Variant = _world()
	SimDecals.add(w2, "scorch", 20.5, 20.5)
	w2.restore(back as Dictionary)
	if JSON.stringify(w2.decals) != JSON.stringify(w.decals):
		push_error("SAVE: the record came back as %s, not %s" % [JSON.stringify(w2.decals), JSON.stringify(w.decals)])
		return false
	var legacy: Dictionary = (JSON.parse_string(JSON.stringify(snap)) as Dictionary)
	legacy.erase("decals")
	var w3: Variant = _world()
	SimDecals.add(w3, "scorch", 20.5, 20.5)
	w3.restore(legacy)
	if not (w3.decals as Dictionary).is_empty():
		push_error("SAVE: an older save with no marks restored %s" % str(w3.decals))
		return false
	print("SAVE OK the marks came back exactly through JSON and replaced the world's own, and an older save restored none")
	return true


# --- WALL --------------------------------------------------------------------------------------

func _a_wall_picture_wears_its_holes() -> bool:
	var w: Variant = _world()
	SimDecals.add(w, "hole", 4.5, 12.4)
	var look: RefCounted = DecalLook.new()
	var seen: Variant = w.vision.tiles_for(int(w.player))
	var standing: Dictionary = {12 * 24 + WALL_X: true}
	if not DecalLook.visible(seen, Vector2i(WALL_X, 12)):
		push_error("WALL: the player does not see the wall tile; the fixture proves nothing")
		return false
	if not (look.call("ground_draws", w, CAMERA, seen, standing, BOUNDS) as Array).is_empty():
		push_error("WALL: the ground pass drew a hole on a tile a wall picture stands on")
		return false
	if (look.call("ground_draws", w, CAMERA, seen, {}, BOUNDS) as Array).size() != 1:
		push_error("WALL: the ground pass did not draw a hole in a wall cap with no picture")
		return false
	# The picture: one tile wide, 44 px of it above the tile's south edge.
	var rect := Rect2(float(WALL_X), 13.0 - 44.0 / 32.0, 1.0, 48.0 / 32.0)
	var on_face: Array = look.call("wall_draws", w, CAMERA, seen, rect) as Array
	if on_face.size() != 1:
		push_error("WALL: the wall picture drew %d holes on its face" % on_face.size())
		return false
	var r: Rect2 = (on_face[0] as Dictionary)["rect"] as Rect2
	var top: Dictionary = {"sx": (rect.position.x - float(CAMERA["x"])) * 64.0 + 640.0, "sy": (rect.position.y - float(CAMERA["y"])) * 64.0 + 360.0}
	var centre: Vector2 = r.get_center()
	if centre.x < float(top["sx"]) or centre.x > float(top["sx"]) + 64.0 or centre.y < float(top["sy"]) or centre.y > float(top["sy"]) + rect.size.y * 64.0:
		push_error("WALL: the hole drew at %s, off the picture at %s" % [str(centre), str(top)])
		return false
	# TN: another tile's picture wears none of it, and an unseen wall none.
	if not (look.call("wall_draws", w, CAMERA, seen, Rect2(float(WALL_X), 9.0 - 44.0 / 32.0, 1.0, 48.0 / 32.0)) as Array).is_empty():
		push_error("WALL: a picture three tiles north wore the hole")
		return false
	# The same hole seen from behind a second wall: sight is a shadowcast, not a facing, so the
	# player is walled off from it rather than turned away.
	var w2: Variant = _world(func(map: Variant) -> void:
		for y in 24:
			map.tiles[y * 24 + 12] = SimTileMap.Tile.Wall
	)
	w = w2
	SimDecals.add(w, "hole", 4.5, 12.4)
	w.components.set_component(w.player, "position", {"x": 20.5, "y": 12.5})
	w.step()
	seen = w.vision.tiles_for(int(w.player))
	if DecalLook.visible(seen, Vector2i(WALL_X, 12)):
		push_error("WALL: the player walked away and still sees the wall; the true negative proves nothing")
		return false
	if not (look.call("wall_draws", w, CAMERA, seen, rect) as Array).is_empty():
		push_error("WALL: a wall the player cannot see wore its hole")
		return false
	print("WALL OK a hole in a standing wall drew on the picture's face and not on the ground, a cap with no picture took it on the ground, a picture elsewhere wore none, and the same wall walled off from the player wore none")
	return true


# --- MATTE -------------------------------------------------------------------------------------

static func too_bright(img: Image) -> float:
	var worst: float = 0.0
	for y in img.get_height():
		for x in img.get_width():
			var c: Color = img.get_pixel(x, y)
			if c.a >= 0.5:
				worst = maxf(worst, maxf(c.r, maxf(c.g, c.b)))
	return worst


func _blood_is_matte() -> bool:
	var keys: Array = []
	for kind in ["splat", "drip", "smear", "pool"]:
		for size in [1, 2, 3, 4]:
			for age in [0, DecalLook.POOL_SPREAD_TICKS, DecalLook.DRY_TICKS]:
				for v in [0, 1]:
					var k: String = DecalLook.art_for(kind, size, age, v)
					if not keys.has(k):
						keys.append(k)
	for k in keys:
		var tex: Texture2D = Appearance.resolve(String(k))
		if tex == null:
			push_error("MATTE: '%s' resolves to nothing" % String(k))
			return false
		var v2: float = too_bright(tex.get_image())
		if v2 > MATTE_VALUE_MAX:
			push_error("MATTE: '%s' has a pixel at value %.2f; blood here is the pack's dark blood, at most %.2f" % [String(k), v2, MATTE_VALUE_MAX])
			return false
	var bright := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	bright.fill(Color(0.9, 0.05, 0.05, 1.0))
	if too_bright(bright) <= MATTE_VALUE_MAX:
		push_error("MATTE: the predicate passed a bright red; it proves nothing")
		return false
	print("MATTE OK all %d blood pictures %s stay at or under value %.2f, and a bright red is refused" % [keys.size(), str(keys), MATTE_VALUE_MAX])
	return true


# --- DRAWN -------------------------------------------------------------------------------------

func _function_body(path: String, name: String) -> String:
	var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
	var out: String = ""
	var inside: bool = false
	for line in lines:
		if line.begins_with("func %s(" % name) or line.begins_with("static func %s(" % name):
			inside = true
			continue
		if inside and (line.begins_with("func ") or line.begins_with("static func ")):
			break
		if inside and not line.strip_edges().begins_with("#"):
			out += line + "\n"
	return out


func _tap(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		root.push_input(ev)


func _the_scene_draws_what_is_seen() -> bool:
	if not _function_body(MAIN_GD, "_draw_district").contains("_draw_decals(seen, a2_wall_tiles, bounds)"):
		push_error("DRAWN: _draw_district never calls the ground pass")
		return false
	if not _function_body(MAIN_GD, "_draw_a2_wall_piece").contains("\"wall_draws\""):
		push_error("DRAWN: _draw_a2_wall_piece never draws the holes in its wall")
		return false
	# TN for the scanner: a function that does not call it is refused.
	if _function_body(MAIN_GD, "_draw_props").contains("_draw_decals("):
		push_error("DRAWN: the scanner found the ground pass in _draw_props; it proves nothing")
		return false
	for kind in SimDecals.KINDS:
		var key: String = DecalLook.art_for(kind, 4, DecalLook.POOL_SPREAD_TICKS, 0)
		var tex: Texture2D = Appearance.resolve(key)
		if tex == null or Vector2i(tex.get_size()) != Vector2i(32, 32):
			push_error("DRAWN: kind '%s' names '%s', which resolves to %s" % [kind, key, str(tex)])
			return false
	var packed := load(SCENE_PATH) as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	if main.get("world") == null:
		push_error("DRAWN: the main scene did not construct a world")
		main.queue_free()
		return false
	main.set_process(false)
	var shell: Variant = main.get("_shell")
	if shell != null and bool((shell as CanvasItem).visible):
		_tap(KEY_ENTER)
		await process_frame
	var legend: Variant = main.get("_legend")
	if legend != null and bool((legend as CanvasItem).visible):
		_tap(KEY_ESCAPE)
		await process_frame
	main.set_process(false)
	var world: Variant = main.get("world")
	world.step()
	var p: Dictionary = world.components.get_component(world.player, "position") as Dictionary
	var here := Vector2(float(p["x"]), float(p["y"]))
	# The player's own tile is always seen; far off the map's other side is not.
	SimDecals.add(world, "pool", here.x, here.y, {"e": 999999})
	var seen: Variant = world.vision.tiles_for(int(world.player))
	var hidden := Vector2.INF
	for r in range(6, 20):
		for a in 16:
			var q: Vector2 = here + Vector2(cos(TAU * a / 16.0), sin(TAU * a / 16.0)) * float(r)
			if q.x > 0.0 and q.y > 0.0 and q.x < float(world.map_width) and q.y < float(world.map_height) and not DecalLook.visible(seen, Vector2i(floori(q.x), floori(q.y))):
				hidden = q
				break
		if hidden != Vector2.INF:
			break
	if hidden != Vector2.INF:
		SimDecals.add(world, "scorch", hidden.x, hidden.y)
	world.tick += DecalLook.POOL_SPREAD_TICKS
	main.call("queue_redraw")
	await process_frame
	await process_frame
	var keys: Array = []
	for d in main.get("_decals_drawn") as Array:
		if d is Array:
			keys.append_array(d as Array)
		else:
			keys.append(String(d))
	main.queue_free()
	await process_frame
	if not keys.has("fx_blood_pool_fresh"):
		push_error("DRAWN: one frame of the real scene with a pool at the player's feet blitted %s" % str(keys))
		return false
	if hidden == Vector2.INF:
		push_error("DRAWN: no unseen tile near the player; the true negative has nothing to judge")
		return false
	if keys.has("fx_scorch_mark"):
		push_error("DRAWN: a scorch on an unseen tile at %s was blitted" % str(hidden))
		return false
	print("DRAWN OK _draw_district calls the ground pass and _draw_a2_wall_piece the wall pass, every kind names a 32x32 pack picture, and one frame of the real scene blitted the pool at the player's feet and not the scorch out of sight at %s" % str(hidden))
	return true
