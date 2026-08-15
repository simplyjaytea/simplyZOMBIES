class_name SimBoot
extends RefCounted

# Playable district boot. Kernel field/vision stay out of World._init so R1 fixtures stay byte-identical.

const WorldRes = preload("res://sim/world.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimVisibility = preload("res://sim/vision/visibility.gd")
const SimLight = preload("res://sim/vision/light.gd")
const Clock = preload("res://sim/time/clock.gd")
const ContentLoader = preload("res://platform/content_loader.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimScreamer = preload("res://sim/modules/screamer.gd")
const SimBloater = preload("res://sim/modules/bloater.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimAttention = preload("res://sim/modules/attention_emitter.gd")
const SimLightMod = preload("res://sim/modules/light.gd")
const SimSurvivors = preload("res://sim/modules/survivors.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimFieldMemory = preload("res://sim/modules/field_memory.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")

const DISTRICT_SEED: int = 20260805
const PATCH_ID: String = "map.district.alpha"
const WANDERERS: int = 12

const RESIDENTIAL_KITS: Array = [
	["item.knife.kitchen", "item.bandage.cloth", "item.painkillers.blister", "item.bow.hunting", "item.ammo.arrow"],
	["item.bat.aluminium", "item.bandage.cloth", "item.food.canned"],
	["item.spear.improvised", "item.bandage.cloth", "item.water.bottle"],
	["item.axe.fire", "item.bandage.cloth", "item.scrap.metal"],
]
const MILITARY_KIT: Array = ["item.pistol.service", "item.ammo.9mm", "item.wrap.cloth", "item.vest.scrap"]

# Last world that called attach_kernel. Headless gates boot one world at a time.
static var _KERNEL_WORLD: Variant = null


static func attach_kernel(world: Variant, map: Variant) -> void:
	_KERNEL_WORLD = world
	world.adopt_map(map)
	world.vision = SimVisibility.new()
	world.light = SimLight.new()
	world.systems.register("kernel.attention-decay", "attention-propagate", 0, _decay)
	world.systems.register("kernel.attention-scent", "attention-propagate", 0, _diffuse)
	world.systems.register("kernel.light", "movement", 75, _refresh_light)
	world.systems.register("kernel.visibility", "movement", 100, _refresh_vision)
	world.events.subscribe({"id": "kernel.attention-noise", "type": "noise.emitted", "handler": _on_noise})
	world.events.subscribe({"id": "kernel.attention-scent-emit", "type": "scent.accumulated", "handler": _on_scent})


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


static func _on_noise(event: Dictionary) -> void:
	# Bound at subscribe time via the world's field; handler is called with the event only.
	# The field lives on the world that published. Event subscribers in this boot always
	# run against the world that owns the bus — look up via a side channel stored below.
	_KERNEL_WORLD.field.emit_noise(float(event["x"]), float(event["y"]), float(event["magnitude"]))


static func _on_scent(event: Dictionary) -> void:
	_KERNEL_WORLD.field.add_scent(float(event["x"]), float(event["y"]), float(event["magnitude"]))


static func register_playable_modules(world: Variant, map: Variant) -> void:
	SimHealth.register_module(world)
	SimInfection.register_module(world)
	SimMelee.register_module(world)
	SimRanged.register_module(world)
	SimInventory.register_module(world)
	SimFortify.register_module(world)
	SimAttention.register_module(world, map)
	SimShambler.register_module(world, map)
	SimScreamer.register_module(world)
	SimBloater.register_module(world)
	SimLightMod.register_module(world)
	SimFieldMemory.register_module(world)


static func place_loot(world: Variant, patch: Dictionary) -> void:
	var loot: Array = patch.get("loot", []) as Array
	var res_i: int = 0
	for entry in loot:
		var e: Dictionary = entry as Dictionary
		var tile: Dictionary = e.get("tile", {}) as Dictionary
		var table: String = String(e.get("table", "residential"))
		var x: float = float(tile.get("x", 0)) + 0.5
		var y: float = float(tile.get("y", 0)) + 0.5
		var kit: Array = MILITARY_KIT
		if table == "residential":
			kit = RESIDENTIAL_KITS[res_i % RESIDENTIAL_KITS.size()] as Array
			res_i += 1
		var ox: float = 0.0
		for item_id in kit:
			var opts: Dictionary = {"tier": "scavenged"}
			if String(item_id) == "item.ammo.arrow":
				opts["count"] = 12
			elif String(item_id) == "item.ammo.9mm":
				opts["count"] = 20
			var item: int = SimItems.spawn_item(world, String(item_id), opts)
			world.components.set_component(item, "position", {"x": x + ox, "y": y})
			ox += 0.4


static func playable(seed_val: int = DISTRICT_SEED, map_size: int = SimTileMap.DISTRICT_TILES) -> Dictionary:
	var content: Dictionary = ContentLoader.load_tree()
	var map: Variant = SimTileMap.generate_district(seed_val, map_size)
	var patch: Variant = SimTileMap.load_patch_from_content(content, PATCH_ID)
	if patch is Dictionary:
		SimTileMap.apply_patch(map, patch as Dictionary)
	var exam: Dictionary = SimTileMap.find_open_tile(map, 46, 45)
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
	var observer: Dictionary = SimVisibility.daylight_eyes()
	world.components.set_component(world.player, "observer", observer)
	SimSurvivors.boot_playable(world)
	# Annex knife is the default find — equip so F works without a scavenger loop.
	var knife: int = SimItems.spawn_item(world, "item.knife.kitchen", {"tier": "scavenged"})
	SimInventory.equip(world, world.player, knife)
	if patch is Dictionary:
		place_loot(world, patch as Dictionary)
	var place_rng: Variant = world.rng.stream("placement")
	for i in WANDERERS:
		var type_id: String = SimRoster.pick_type(world, place_rng)
		# Guarantee one of each threat on the playable boot so the roster is visible on day 1.
		if i == 0:
			type_id = SimRoster.TYPE_SCREAMER
		elif i == 1:
			type_id = SimRoster.TYPE_BLOATER
		elif i < 8:
			type_id = SimRoster.TYPE_SHAMBLER
		var tx: int = int(place_rng.call("int_range", 8, int(map.w) - 9))
		var ty: int = int(place_rng.call("int_range", 8, int(map.h) - 9))
		if i == 0:
			tx = 50
			ty = 62
		elif i == 1:
			tx = 62
			ty = 50
		var tile: Dictionary = SimTileMap.find_open_tile(map, tx, ty)
		SimRoster.spawn_zombie(world, float(tile["x"]) + 0.5, float(tile["y"]) + 0.5, type_id, place_rng)
	world.events.drain()
	return {"world": world, "map": map}
