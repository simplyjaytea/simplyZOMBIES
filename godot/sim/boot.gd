class_name SimBoot
extends RefCounted

# Playable district boot. Kernel field/vision stay out of World._init so R1 fixtures stay byte-identical.

const WorldRes = preload("res://sim/world.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimWorldgen = preload("res://sim/map/worldgen.gd")
const SimVisibility = preload("res://sim/vision/visibility.gd")
const SimLight = preload("res://sim/vision/light.gd")
const Clock = preload("res://sim/time/clock.gd")
const ContentLoader = preload("res://platform/content_loader.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const SimTreatment = preload("res://sim/modules/treatment.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimScreamer = preload("res://sim/modules/screamer.gd")
const SimBloater = preload("res://sim/modules/bloater.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimLoot = preload("res://sim/loot.gd")
const SimContainers = preload("res://sim/modules/containers.gd")
const SimModification = preload("res://sim/modules/modification.gd")
const SimAttention = preload("res://sim/modules/attention_emitter.gd")
const SimLightMod = preload("res://sim/modules/light.gd")
const SimSurvivors = preload("res://sim/modules/survivors.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimFieldMemory = preload("res://sim/modules/field_memory.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const SimDirector = preload("res://sim/modules/director.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimNpcCombat = preload("res://sim/modules/npc_combat.gd")
const SimRecruits = preload("res://sim/modules/recruits.gd")
const SimSkills = preload("res://sim/modules/skills.gd")
const SimSightings = preload("res://sim/modules/sightings.gd")
const SimAttachments = preload("res://sim/modules/attachments.gd")
const SimDebugMod = preload("res://sim/modules/debug.gd")

const DISTRICT_SEED: int = 20260805
const DEFAULT_DISTRICT: String = "district.residential_suburb"
# 20, up from 12 in the basic-combat slice: with swipes live a wanderer is a threat rather than
# scenery, and the district read as empty at 12 across a 64-tile map. check_m2_director.gd pins
# this number exactly -- change both together.
const WANDERERS: int = 20
# How many times a boot wanderer's tile is re-rolled to land outside the colony before it is placed
# wherever it fell. See the scatter loop in `playable`.
const SCATTER_TRIES: int = 8


static func attach_kernel(world: Variant, map: Variant) -> void:
	world.adopt_map(map)
	world.vision = SimVisibility.new()
	world.light = SimLight.new()
	world.systems.register("kernel.attention-decay", "attention-propagate", 0, _decay)
	world.systems.register("kernel.attention-scent", "attention-propagate", 0, _diffuse)
	world.systems.register("kernel.light", "movement", 75, _refresh_light)
	world.systems.register("kernel.visibility", "movement", 100, _refresh_vision)
	# Bound to *this* world, by capture, and not to a static.
	#
	# These two used to be `static func _on_noise(event)` reaching for `SimBoot._KERNEL_WORLD`
	# -- "the last world that called attach_kernel" -- with a comment claiming headless gates
	# boot one world at a time. They do not: a gate boots a positive world and a negative world
	# constantly, and this file's own `bare()` is called twice in a row by several of them. So
	# the second world silently took delivery of the first world's noise and scent. Measured:
	# boot A (seed 101) then B (seed 102), publish magnitude 500 at (8,8) on A and step A --
	# A's own field reads 0.0000 and B's reads 500.0000. On the spine system (docs/03), which
	# means every two-world assertion about noise or scent was reading the wrong field, negative
	# controls included.
	#
	# docs/30 already records this hazard twice, for `putDown` and `mourned`: "a static would be
	# shared between the two worlds a gate boots". It was still live here, in the kernel.
	# `world` is an object, so the closure captures a reference -- the lambda-capture trap in
	# CLAUDE.md is about primitives, and this is the shape that is safe. `world.field` is read
	# at call time rather than captured, so `adopt_map` replacing the field still works.
	world.events.subscribe({"id": "kernel.attention-noise", "type": "noise.emitted", "handler": func(event: Dictionary) -> void:
		world.field.emit_noise(float(event["x"]), float(event["y"]), float(event["magnitude"]))
	})
	world.events.subscribe({"id": "kernel.attention-scent-emit", "type": "scent.accumulated", "handler": func(event: Dictionary) -> void:
		world.field.add_scent(float(event["x"]), float(event["y"]), float(event["magnitude"]))
	})


static func _decay(w: Variant) -> void:
	w.field.decay()


static func _diffuse(w: Variant) -> void:
	if int(w.tick) % int(w.field.calibration["scentIntervalTicks"]) == 0:
		w.field.diffuse_scent()


static func _refresh_light(w: Variant) -> void:
	if w.light != null and w.tilemap != null:
		w.light.refresh(w, w.tilemap)


static func _refresh_vision(w: Variant) -> void:
	if w.vision != null and w.tilemap != null:
		w.vision.refresh(w, w.tilemap)


static func register_playable_modules(world: Variant, map: Variant) -> void:
	SimHealth.register_module(world)
	SimWounds.register_module(world)
	SimTreatment.register_module(world)
	SimInfection.register_module(world)
	SimMelee.register_module(world)
	SimRanged.register_module(world)
	SimInventory.register_module(world)
	SimItems.register_module(world)
	SimFortify.register_module(world)
	SimContainers.register_module(world)
	SimModification.register_module(world)
	SimDirector.register_module(world)
	SimNeeds.register_module(world)
	SimJobs.register_module(world)
	SimNpcCombat.register_module(world)
	SimRecruits.register_module(world)
	SimSkills.register_module(world)
	SimAttention.register_module(world, map)
	SimShambler.register_module(world, map)
	SimScreamer.register_module(world)
	SimBloater.register_module(world)
	SimLightMod.register_module(world)
	SimFieldMemory.register_module(world)
	SimSightings.register_module(world)
	SimAttachments.register_module(world)
	SimDebugMod.register_module(world)


# Scatters each of the map's loot sites from the content table its `table` names, per docs/12:
# "Resources, location loot tables, and spoilage rules are JSON. A loot table declares location
# type, resource weights, tier weights, and quantity ranges." This used to be two hardcoded kits
# in this file -- a fixed list per site, cycled round-robin -- which meant rebalancing the economy
# was a code edit and adding a location type was a new branch, both of which docs/12 says are
# supposed to be data passes. Same shape as the appearance move: what a place yields is content.
#
# The sites are `map.sites` now, not the annex patch's `loot` array: the generator draws them per
# seed from the district's `lootProfile` (`worldgen.sites`), and `SimTemplates.stamp` adds the ones
# a template authored itself -- the annex's kitchen scatter and its cupboard. One list, one shape,
# whichever of the two put a record in it, so a hand-placed cupboard and a generated one are the
# same thing to everything downstream.
#
# Every roll comes off a dedicated `lootTable` stream rather than the `loot` stream
# stream SimItems.spawn_item draws tiers from. New randomness gets its own stream: sharing one
# would have every table roll shift the tier sequence for everything spawned afterwards, which is
# a determinism footgun for anything that measures across a change to this table.
static func place_loot(world: Variant, map: Variant) -> void:
	if map == null:
		return
	var loot: Array = map.sites as Array
	var rng: Variant = SimLoot.stream(world)
	for entry in loot:
		var e: Dictionary = entry as Dictionary
		var location: String = String(e.get("table", "residential"))
		var table: Variant = SimLoot.table_for(world, location)
		if not (table is Dictionary):
			# Loud, not silent: a site naming a table that does not exist would otherwise place an
			# empty site and read as a stingy seed. check_loot.gd asserts every site a shipped
			# district generates resolves, so reaching this in a gate run is a content bug.
			push_error("boot: loot site names unknown table \"%s\"" % location)
			continue
		var x: float = float(int(e.get("x", 0))) + 0.5
		var y: float = float(int(e.get("y", 0))) + 0.5
		# A site with a `container` is not scattered at boot -- it stands there holding its table
		# until somebody opens it. Same table, same roller, rolled later; that is the whole of the
		# difference, and it is what makes a searched cupboard finite rather than a respawn timer
		# (docs/12 puts respawn on the cut list). Which sites are containers is the district's
		# `lootProfile` decision, or the template's, never this file's.
		var kind: String = String(e.get("container", ""))
		if kind != "":
			SimContainers.make_container(world, x, y, kind, location)
			continue
		SimLoot.scatter(world, table as Dictionary, rng, x, y)


static func bare(seed_val: int = DISTRICT_SEED, map_size: int = SimTileMap.DISTRICT_TILES, district_id: String = DEFAULT_DISTRICT) -> Dictionary:
	# Same seed + content + modules. No placement, loot, or spawn_unique — F9 restore target.
	var content: Dictionary = ContentLoader.load_tree()
	# The content tree is handed to the generator rather than letting it walk the directory again:
	# `load_tree` is a full directory walk and the balance harness boots one of these per seed.
	#
	# The colony arrives with the district now. This file used to choose where it went -- one
	# `SimTemplates.stamp` at a compile-time `ANNEX_ORIGIN`, on ground the generator had reserved at
	# a rect two files had to agree about -- and that origin was the last colony coordinate written
	# in code. `SimWorldgen` ranks its own lots and stamps the winner, so where the colony stands is
	# a property of the seed like everything else about the district, and everything downstream --
	# the director's exclusions, the jobs router, the stockpile, the recruit beat, the well -- reads
	# the anchors the stamp wrote, exactly as it did before.
	var map: Variant = SimWorldgen.generate(seed_val, map_size, content, district_id)
	var start: Vector2i = colony_start(map)
	var exam: Dictionary = SimTileMap.find_open_tile(map, start.x, start.y)
	var fixture: Dictionary = {
		"seed": seed_val,
		"tick_hz": 20,
		"ticks": 0,
		"map": {"width": int(map.w), "height": int(map.h), "walls": []},
		"player": {"id": 0, "x": float(exam["x"]) + 0.5, "y": float(exam["y"]) + 0.5, "stance": 2},
		"commands": [],
		"rng_probe": {"stream": "test", "samples": 0},
		"contract": "playable",
		"content_tree": content,
	}
	var world: Variant = WorldRes.new(fixture)
	world.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	attach_kernel(world, map)
	register_playable_modules(world, map)
	world.components.set_component(world.player, "facing", {"radians": 0.0})
	# The patch is not handed back any more: its loot rows are `map.sites` by the time the generator
	# returns, and a `patch` key nobody read would be a socket rather than a return value.
	return {"world": world, "map": map}


# Where the colony starts, read off the map the template was stamped onto rather than off a
# constant. Every compile-time twin of a colony coordinate is gone -- `SimDirector.ANNEX`,
# `SimFortify.GATE_A`/`GATE_B`, the well's `GATE_A + (1, 2)` and now `ANNEX_ORIGIN` itself are all
# map anchors -- and this (46, 45) is the one literal that stays, deliberately: it is the fallback
# for a map that carries no anchors at all, which is what a district too small to hold the annex and
# its clear ring comes back as (the 16- and 32-tile fixture maps the isolation boots use).
# check_buildings.gd's reader lane proves it is the anchor and not the literal that a generated
# district uses, and that the fallback is reachable rather than theoretical.
static func colony_start(map: Variant) -> Vector2i:
	var anchor: Vector2i = SimTileMap.player_start(map)
	if anchor.x < 0 or anchor.y < 0:
		return Vector2i(46, 45)
	return anchor


static func place_stations(world: Variant, map: Variant) -> void:
	var start: Vector2i = colony_start(map)
	var tiles: Array[Vector2i] = _indoor_floors(map, start.x, start.y, 6)
	if tiles.is_empty():
		return
	SimNeeds.make_campfire(world, float(tiles[0].x) + 0.5, float(tiles[0].y) + 0.5, false)
	if tiles.size() > 1:
		SimNeeds.make_bed(world, float(tiles[1].x) + 0.5, float(tiles[1].y) + 0.5)
	if tiles.size() > 2:
		SimNeeds.make_bed(world, float(tiles[2].x) + 0.5, float(tiles[2].y) + 0.5)
	# Outdoor well just south of the gate (ADR 0013) -- the template's own anchor now, not
	# `GATE_A + (1, 2)` computed here. A district nobody stamped has no well anchor and gets no
	# well, which is the honest answer: there is nothing to site it against.
	var well: Vector2i = SimTileMap.well_tile(map)
	if well.x < 0 or well.y < 0:
		return
	if well.x > 0 and well.y > 0 and well.x < int(map.w) - 1 and well.y < int(map.h) - 1:
		if not SimTileMap.is_solid(map, well.x, well.y):
			SimNeeds.make_water_source(world, float(well.x) + 0.5, float(well.y) + 0.5)


static func _indoor_floors(map: Variant, near_x: int, near_y: int, n: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var annex: Rect2i = SimTileMap.annex_rect(map)
	if annex.size.x <= 0 or annex.size.y <= 0:
		return found
	var rx: int = annex.position.x
	var ry: int = annex.position.y
	var rw: int = annex.size.x
	var rh: int = annex.size.y
	var scored: Array[Dictionary] = []
	for j in range(ry, ry + rh):
		for i in range(rx, rx + rw):
			if not SimTileMap.is_indoors(map, i, j):
				continue
			if SimTileMap.tile_at(map, i, j) != SimTileMap.Tile.Floor:
				continue
			if SimTileMap.is_solid(map, i, j):
				continue
			if i == near_x and j == near_y:
				continue
			var d: int = absi(i - near_x) + absi(j - near_y)
			scored.append({"t": Vector2i(i, j), "d": d})
	scored.sort_custom(func(a, b): return int(a["d"]) < int(b["d"]))
	for s in scored:
		found.append(s["t"] as Vector2i)
		if found.size() >= n:
			break
	return found


static func playable(seed_val: int = DISTRICT_SEED, map_size: int = SimTileMap.DISTRICT_TILES, district_id: String = DEFAULT_DISTRICT) -> Dictionary:
	var boot: Dictionary = bare(seed_val, map_size, district_id)
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	var observer: Dictionary = SimVisibility.daylight_eyes()
	world.components.set_component(world.player, "observer", observer)
	place_stations(world, map)
	SimSurvivors.boot_playable(world)
	# Annex knife is the default find — equip so F works without a scavenger loop.
	var knife: int = SimItems.spawn_item(world, "item.knife.kitchen", {"tier": "scavenged"})
	SimInventory.equip(world, world.player, knife)
	place_loot(world, map)
	var place_rng: Variant = world.rng.stream("placement")
	# Never inside the colony's own walls. `SimDirector._legal_tile` has always refused to put a
	# night packet in the annex, and this scatter used to get the same answer for nothing: the annex
	# was a fixed rect in the district's corner and the box these rolls come from barely reached it.
	# The generator sites the colony per seed now, and it lands in the middle of that box -- measured
	# on the four balance seeds, 2, 7, 5 and 7 of the twenty wanderers booted *inside* the annex,
	# and the three seeds with five or more lost a colonist on day 1, 2 or 3 to one of them. A
	# shambler in the kitchen at boot is not difficulty, it is the start docs/01's fairness rule
	# says may not exist -- so the rule the director already follows is said out loud here.
	#
	# Re-rolled rather than pushed out: a walk to "the nearest tile outside the rect" would pile the
	# refused rolls against the annex wall, which is the one place they must not be. The attempt
	# count is fixed so the draw count stays bounded and the campaign stays a function of its seed;
	# a roll that never lands outside places anyway rather than looping, which at these odds
	# (a 26x26 rect inside a 48x48 box, eight times over) is a case nothing has reached.
	var annex: Rect2i = SimTileMap.annex_rect(map)
	for i in WANDERERS:
		var type_id: String = SimRoster.pick_type(world, place_rng)
		var tile: Dictionary = {}
		for _try in SCATTER_TRIES:
			var tx: int = int(place_rng.call("int_range", 8, int(map.w) - 9))
			var ty: int = int(place_rng.call("int_range", 8, int(map.h) - 9))
			tile = SimTileMap.find_open_tile(map, tx, ty)
			if annex.size.x <= 0 or not annex.has_point(Vector2i(int(tile["x"]), int(tile["y"]))):
				break
		SimRoster.spawn_zombie(world, float(tile["x"]) + 0.5, float(tile["y"]) + 0.5, type_id, place_rng)
	world.events.drain()
	return {"world": world, "map": map}
