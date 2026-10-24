extends SceneTree
# Actual shipped world, including all registered modules and the event drain. The old
# bench.gd's synthetic dictionary does not exercise this consumer.
const Boot = preload("res://sim/boot.gd")
const Clock = preload("res://sim/time/clock.gd")
const SimHome = preload("res://sim/home.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const WARMUP: int = 100
const SAMPLES: int = 600
# A colony mid-run carries more on the ground than the boot does (72 loose items at boot). The
# colony sample adds this many more, on walkable outdoor floor inside the errand radius, from a
# local stream so the world's named draws are not shifted.
const COLONY_EXTRA_ITEMS: int = 200
const COLONY_SEED: int = 20261024
const COLONY_BASES: Array[String] = ["item.food.canned", "item.scrap.metal", "item.bandage.cloth", "item.wood.branch", "item.water.bottle", "item.tape.duct", "item.rag.dirty", "item.food.raw"]

func _init() -> void:
	var w: Variant = Boot.playable()["world"]
	var boot_tick: int = int(w.tick)
	var zombies_start: int = w.components.query(["shambler"]).size()
	for i in WARMUP:
		w.step()
	var start_tick: int = int(w.tick)
	var samples: Array[float] = []
	for i in SAMPLES:
		var started: int = Time.get_ticks_usec()
		w.step()
		samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
	# FULL stops on day ten's end of dusk, not the end of ten complete days. This is
	# an early-day throughput projection, not a campaign result or a completion promise.
	var campaign_ticks: int = Clock.tick_on_day(10, Clock.DUSK_ENDS) - boot_tick
	print("RUNTIME_RESULT " + JSON.stringify({
		"id": "shipped-tick", "samples_ms": samples, "warmup": WARMUP,
		"seed": int(w.seed), "tiles": int(w.map_width), "start_tick": start_tick,
		"end_tick": int(w.tick), "zombies_start": zombies_start,
		"zombies_end": w.components.query(["shambler"]).size(),
		"systems": w.systems.ids.size(), "campaign_ticks": campaign_ticks,
		"engine": Engine.get_version_info()["string"], "os": OS.get_name(),
		"cpu": OS.get_processor_name(), "scope": "SimBoot.playable default; world.step including drain"
	}))
	print("RUNTIME_RESULT " + JSON.stringify(_colony_sample()))
	print("RUNTIME_MEASUREMENT_COMPLETE tick")
	quit(0)

# The same measurement on a booted world with COLONY_EXTRA_ITEMS more loose items on the ground.
func _colony_sample() -> Dictionary:
	var w: Variant = Boot.playable()["world"]
	_scatter_loose_items(w, COLONY_EXTRA_ITEMS)
	var loose_start: int = SimInventory.ground_items(w).size()
	for i in WARMUP:
		w.step()
	var samples: Array[float] = []
	for i in SAMPLES:
		var started: int = Time.get_ticks_usec()
		w.step()
		samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
	return {
		"id": "colony-tick", "samples_ms": samples, "warmup": WARMUP,
		"seed": int(w.seed), "tiles": int(w.map_width), "loose_items_start": loose_start,
		"loose_items_end": SimInventory.ground_items(w).size(),
		"zombies_end": w.components.query(["shambler"]).size(),
		"scope": "SimBoot.playable default plus %d loose items on outdoor floor in the errand radius" % COLONY_EXTRA_ITEMS
	}

func _scatter_loose_items(w: Variant, count: int) -> void:
	var map: Variant = w.tilemap
	var centre: Vector2 = SimHome.centre(w)
	var radius: int = int(SimJobs.ERRAND_RADIUS_TILES)
	var rng := RandomNumberGenerator.new()
	rng.seed = COLONY_SEED
	var placed: int = 0
	var guard: int = 0
	while placed < count and guard < count * 200:
		guard += 1
		var tx: int = floori(centre.x) + rng.randi_range(-radius, radius)
		var ty: int = floori(centre.y) + rng.randi_range(-radius, radius)
		if tx < 0 or ty < 0 or tx >= w.map_width or ty >= w.map_height:
			continue
		if SimTileMap.is_solid(map, tx, ty) or SimTileMap.is_indoors(map, tx, ty):
			continue
		if SimTileMap.tile_at(map, tx, ty) != SimTileMap.Tile.Floor:
			continue
		var base: String = COLONY_BASES[rng.randi_range(0, COLONY_BASES.size() - 1)]
		var item: int = SimItems.spawn_item(w, base, {"tier": "scavenged"})
		w.components.set_component(item, "position", {"x": float(tx) + 0.5, "y": float(ty) + 0.5})
		placed += 1
