class_name SimDirector
extends RefCounted

const Clock = preload("res://sim/time/clock.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")

const GRACE_COMPOSITION_UNTIL_DAY: int = 3
const GRACE_PRESSURE_UNTIL_DAY: int = 8
const LIVE_CAP: int = 24
const TRICKLE_LIVE: int = 8
const TRICKLE_SIZE: int = 2
const BASE_SIZE: int = 3
const FLOOR_SIZE: int = 3
const FLOOR_QUIET_NIGHTS: int = 3
const QUIET_NOISE: float = 25.0
const FOOTPRINT_NOISE: float = 120.0
const GATE_EXCLUSION: float = 32.0
const ANNEX := Rect2i(40, 40, 22, 20)
const ARMOR_IDS: Array[String] = ["item.wrap.cloth", "item.vest.scrap"]
const AMMO_IDS: Array[String] = ["item.ammo.9mm", "item.ammo.arrow"]


static func default_state() -> Dictionary:
	return {"lullUntilTick": 0, "lastMigrationTick": 0, "nightsSinceQuiet": 0}


static func snapshot_of(world: Variant) -> Dictionary:
	var d: Dictionary = world.director if world.director is Dictionary else default_state()
	return {
		"lullUntilTick": int(d.get("lullUntilTick", 0)),
		"lastMigrationTick": int(d.get("lastMigrationTick", 0)),
		"nightsSinceQuiet": int(d.get("nightsSinceQuiet", 0)),
	}


static func register_module(world: Variant) -> void:
	if world.director == null or not world.director is Dictionary:
		world.director = default_state()
	else:
		var d: Dictionary = world.director as Dictionary
		if not d.has("lullUntilTick"):
			d["lullUntilTick"] = 0
		if not d.has("lastMigrationTick"):
			d["lastMigrationTick"] = 0
		if not d.has("nightsSinceQuiet"):
			d["nightsSinceQuiet"] = 0
	world.systems.register("director.dusk", "director", 0, func(w: Variant) -> void:
		_tick_peak(w)
		if Clock.phase_of(int(w.tick)) != Clock.Phase.Dusk:
			return
		if Clock.phase_of(int(w.tick) - 1) == Clock.Phase.Dusk:
			return
		_on_dusk(w)
	)
	world.events.subscribe({"id": "director.breach-lull", "type": "fortify.breached", "handler": func(_event: Dictionary) -> void:
		_begin_lull(world, 1)
	})
	world.events.subscribe({"id": "director.mara-lull", "type": "entity.killed", "handler": func(event: Dictionary) -> void:
		var ident: Variant = world.components.get_component(int(event.get("entity", -1)), "identity")
		if ident is Dictionary and bool((ident as Dictionary).get("unique", false)):
			_begin_lull(world, 2)
	})


static func _on_dusk(world: Variant) -> void:
	var day: int = Clock.day_number(int(world.tick))
	var live: int = world.components.query(["shambler"]).size()
	var annex_peak: float = _annex_peak(world)
	var st: Dictionary = world.director as Dictionary
	var lull: bool = int(world.tick) < int(st.get("lullUntilTick", 0))
	var size: int = 0
	if not lull and live < LIVE_CAP:
		if day < GRACE_COMPOSITION_UNTIL_DAY:
			size = 0
		elif day < GRACE_PRESSURE_UNTIL_DAY:
			if live < TRICKLE_LIVE:
				size = TRICKLE_SIZE
		else:
			size = BASE_SIZE
			if _power(world) >= 3:
				size += 1
			if float(st.get("weekPeakNoise", 0.0)) >= FOOTPRINT_NOISE:
				size += 1
			size = clampi(size, 2, 6)
		if size == 0 and day >= GRACE_PRESSURE_UNTIL_DAY and int(st.get("nightsSinceQuiet", 0)) >= FLOOR_QUIET_NIGHTS and annex_peak < QUIET_NOISE:
			size = FLOOR_SIZE
	if size > 0 and live + size > LIVE_CAP:
		size = LIVE_CAP - live
	if size > 0:
		_emit_packet(world, size)
		st["nightsSinceQuiet"] = 0
	else:
		if annex_peak < QUIET_NOISE:
			st["nightsSinceQuiet"] = int(st.get("nightsSinceQuiet", 0)) + 1
		else:
			st["nightsSinceQuiet"] = 0


static func _emit_packet(world: Variant, size: int) -> void:
	var rng: Variant = world.rng.stream("director")
	var south: Array[Vector2i] = []
	var rest: Array[Vector2i] = []
	_collect_edges(world, south, rest)
	var pool: Array[Vector2i] = south if not south.is_empty() else rest
	if pool.is_empty():
		return
	for _i in size:
		var pick: Vector2i = pool[int(rng.call("int_range", 0, pool.size() - 1))]
		var type_id: String = SimRoster.pick_type(world, rng)
		SimRoster.spawn_zombie(world, float(pick.x) + 0.5, float(pick.y) + 0.5, type_id, rng)
	(world.director as Dictionary)["lastMigrationTick"] = int(world.tick)
	world.events.publish({"type": "director.packet", "size": size})


static func _collect_edges(world: Variant, south: Array[Vector2i], rest: Array[Vector2i]) -> void:
	var map: Variant = world.tilemap
	if map == null:
		return
	var w: int = int(map.w)
	var h: int = int(map.h)
	for y in h:
		for x in w:
			if x > 2 and x < w - 3 and y > 2 and y < h - 3:
				continue
			if not _legal_tile(world, x, y):
				continue
			if y >= h - 3:
				south.append(Vector2i(x, y))
			else:
				rest.append(Vector2i(x, y))


static func _legal_tile(world: Variant, tx: int, ty: int) -> bool:
	var map: Variant = world.tilemap
	if SimTileMap.tile_at(map, tx, ty) != SimTileMap.Tile.Floor:
		return false
	if SimTileMap.is_solid(map, tx, ty):
		return false
	if ANNEX.has_point(Vector2i(tx, ty)):
		return false
	var gx: float = float(tx) + 0.5
	var gy: float = float(ty) + 0.5
	for gate in [SimFortify.GATE_A, SimFortify.GATE_B]:
		var dx: float = gx - (float(gate.x) + 0.5)
		var dy: float = gy - (float(gate.y) + 0.5)
		if dx * dx + dy * dy < GATE_EXCLUSION * GATE_EXCLUSION:
			return false
	return true


static func _annex_peak(world: Variant) -> float:
	if world.field == null:
		return 0.0
	var peak: float = 0.0
	for y in range(ANNEX.position.y, ANNEX.position.y + ANNEX.size.y):
		for x in range(ANNEX.position.x, ANNEX.position.x + ANNEX.size.x):
			var n: float = float(world.field.noise_at(float(x) + 0.5, float(y) + 0.5))
			if n > peak:
				peak = n
	return peak


static func _tick_peak(world: Variant) -> void:
	if world.field == null:
		return
	var st: Dictionary = world.director as Dictionary
	var week: int = int((Clock.day_number(int(world.tick)) - 1) / 7)
	if int(st.get("weekIndex", -1)) != week:
		st["weekIndex"] = week
		st["weekPeakNoise"] = 0.0
	var peak: float = float(world.field.peak_noise())
	if peak > float(st.get("weekPeakNoise", 0.0)):
		st["weekPeakNoise"] = peak


static func _power(world: Variant) -> int:
	var n: int = 0
	if not world.components.query(["windowBoard"]).is_empty():
		n += 1
	if not world.components.query(["scrapBarricade"]).is_empty():
		n += 1
	var alarm: Array[int] = world.components.query(["alarmLine"])
	if not alarm.is_empty():
		var line: Variant = world.components.get_component(alarm[0], "alarmLine")
		if line is Dictionary and bool((line as Dictionary).get("armed", false)):
			n += 1
	for bait in world.components.query(["noisemaker"]):
		var nm: Variant = world.components.get_component(int(bait), "noisemaker")
		if nm is Dictionary and int(world.tick) < int((nm as Dictionary).get("expiresAtTick", 0)):
			n += 1
			break
	if _has_ammo(world):
		n += 1
	if _has_armor(world):
		n += 1
	return n


static func _has_ammo(world: Variant) -> bool:
	for item in SimInventory.carried_items(world, world.player):
		var base: Variant = world.components.get_component(item, "itemBase")
		if not base is Dictionary:
			continue
		if not AMMO_IDS.has(String((base as Dictionary).get("baseId", ""))):
			continue
		var stack: Variant = world.components.get_component(item, "stack")
		var count: int = int((stack as Dictionary).get("count", 1)) if stack is Dictionary else 1
		if count > 0:
			return true
	return false


static func _has_armor(world: Variant) -> bool:
	var bodies: Array[int] = [world.player]
	for ent in world.components.query(["identity"]):
		bodies.append(int(ent))
	for actor in bodies:
		for item in SimInventory.equipped_items(world, actor):
			var base: Variant = world.components.get_component(item, "itemBase")
			if base is Dictionary and ARMOR_IDS.has(String((base as Dictionary).get("baseId", ""))):
				return true
	return false


static func _begin_lull(world: Variant, nights: int) -> void:
	var day: int = Clock.day_number(int(world.tick))
	var start: int = day * Clock.DAY_TICKS + Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	var until: int = start + nights * Clock.DAY_TICKS
	var st: Dictionary = world.director as Dictionary
	st["lullUntilTick"] = maxi(int(st.get("lullUntilTick", 0)), until)
