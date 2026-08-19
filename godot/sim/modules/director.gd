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
const ANNEX := Rect2i(38, 38, 26, 26)
const ARMOR_IDS: Array[String] = ["item.wrap.cloth", "item.vest.scrap"]

# --- the shape of a night (docs/17) ------------------------------------------------------------
#
# docs/17: "The director doesn't pick a number for the night. It maintains a set of dials and seeds
# events." It was picking a number: `size` fell straight out of the day, the live count, colony
# power and the week's noise peak, none of which the seed moves -- which is why the balance
# harness reported *the same 3 sieges and 7 quiet nights on every seed it ran*, and why
# check_m2_balance.gd's own comment says the seed reaches nothing but the edge pick.
#
# A night is drawn from a weighted table now, and the table is conditioned on strain. Strain still
# decides how hard the week leans; it no longer decides the night. That is the difference between
# pacing and a schedule.
#
# Rule 5 -- "never rubber-band silently" -- is why every decision publishes `director.night` with
# the shape it drew and the reason it kept or overrode it. An adjustment the player cannot reason
# about is prohibited, and one nothing can even observe is worse.
enum Night { Quiet = 0, Probe = 1, Press = 2, Siege = 3 }

const NIGHT_NAMES: Array[String] = ["quiet", "probe", "press", "siege"]
const NIGHT_SIZES: Array[int] = [0, 2, 4, 6]

# Rows are strain bands, columns are the four shapes. Every row keeps a non-zero weight on quiet
# and on siege: docs/17 rule 4 asks for a variance floor *and* ceiling, and a row that zeroed
# either end would make one of them unreachable at that strain rather than merely unlikely.
const NIGHT_WEIGHTS: Array = [
	[55, 30, 12, 3],
	[25, 35, 27, 13],
	[10, 25, 35, 30],
]

# docs/17 rule 4: "every night is a siege" is an impossible state, not an unlikely one. The quiet
# half of the same rule is FLOOR_QUIET_NIGHTS, which has been in this file all along -- as an
# unreachable branch. See _on_dusk.
const MAX_CONSECUTIVE_SIEGE: int = 2

# Its own stream, so adding a draw per night leaves the `director` stream's existing sequence --
# edge picks and zombie types -- byte-identical. A new decision must not reshuffle old ones.
const NIGHT_STREAM: String = "directorNight"

# Sides, in the order _edges_by_side returns them.
const SIDE_NAMES: Array[String] = ["north", "east", "south", "west"]
# Every fourth edge tile is sampled when asking the field which way the noise points. The field is
# a diffusion, not a texture: neighbouring tiles differ by very little, and sampling all of them
# costs four times as much to move the answer by nothing.
const SIDE_SAMPLE_STRIDE: int = 4
const AMMO_IDS: Array[String] = ["item.ammo.9mm", "item.ammo.arrow"]


static func default_state() -> Dictionary:
	return {"lullFromTick": 0, "lullUntilTick": 0, "lastMigrationTick": 0, "nightsSinceQuiet": 0, "consecutiveSiege": 0}


static func snapshot_of(world: Variant) -> Dictionary:
	var d: Dictionary = world.director if world.director is Dictionary else default_state()
	return {
		"lullFromTick": int(d.get("lullFromTick", 0)),
		"lullUntilTick": int(d.get("lullUntilTick", 0)),
		"lastMigrationTick": int(d.get("lastMigrationTick", 0)),
		"nightsSinceQuiet": int(d.get("nightsSinceQuiet", 0)),
		"consecutiveSiege": int(d.get("consecutiveSiege", 0)),
	}


static func register_module(world: Variant) -> void:
	if world.director == null or not world.director is Dictionary:
		world.director = default_state()
	else:
		var d: Dictionary = world.director as Dictionary
		if not d.has("lullFromTick"):
			d["lullFromTick"] = 0
		if not d.has("lullUntilTick"):
			d["lullUntilTick"] = 0
		if not d.has("lastMigrationTick"):
			d["lastMigrationTick"] = 0
		if not d.has("nightsSinceQuiet"):
			d["nightsSinceQuiet"] = 0
		if not d.has("consecutiveSiege"):
			d["consecutiveSiege"] = 0
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
	var lull: bool = int(world.tick) >= int(st.get("lullFromTick", 0)) and int(world.tick) < int(st.get("lullUntilTick", 0))

	var shape: int = Night.Quiet
	var drawn: int = Night.Quiet
	var reason: String = "drawn"
	if lull:
		# docs/17 rule 1. The quiet after a disaster is the rule the whole document is proudest
		# of, and it outranks the draw rather than weighting it.
		reason = "lull"
	elif live >= LIVE_CAP:
		reason = "cap"
	elif day < GRACE_COMPOSITION_UNTIL_DAY:
		# docs/17 rule 2: week one is quiet.
		reason = "grace"
	elif day < GRACE_PRESSURE_UNTIL_DAY:
		reason = "grace-trickle"
		if live < TRICKLE_LIVE:
			shape = Night.Probe
	else:
		drawn = _draw_night(world, _strain_band(world, st))
		shape = drawn
		# Rule 4, ceiling half. Two sieges in a row is a bad week; three is a schedule.
		if shape == Night.Siege and int(st.get("consecutiveSiege", 0)) >= MAX_CONSECUTIVE_SIEGE:
			shape = Night.Press
			reason = "siege-cap"
		# Rule 4, floor half -- and rule 3's escalating quiet. This existed before as
		# `if size == 0 and nightsSinceQuiet >= FLOOR_QUIET_NIGHTS`, sitting after an
		# unconditional `size = BASE_SIZE`, so `size == 0` was never true and the variance floor
		# was written, gated and unreachable. It is reachable now because a night can genuinely
		# draw quiet.
		elif shape == Night.Quiet and int(st.get("nightsSinceQuiet", 0)) >= FLOOR_QUIET_NIGHTS and annex_peak < QUIET_NOISE:
			shape = Night.Probe
			reason = "quiet-floor"

	var size: int = NIGHT_SIZES[shape]
	if size > 0 and live + size > LIVE_CAP:
		size = maxi(0, LIVE_CAP - live)
	var side: String = ""
	if size > 0:
		side = _emit_packet(world, size)
		st["nightsSinceQuiet"] = 0
	else:
		if annex_peak < QUIET_NOISE:
			st["nightsSinceQuiet"] = int(st.get("nightsSinceQuiet", 0)) + 1
		else:
			st["nightsSinceQuiet"] = 0
	st["consecutiveSiege"] = int(st.get("consecutiveSiege", 0)) + 1 if shape == Night.Siege else 0

	# Rule 5. Everything the director just decided, in one event: what it drew, what it did, and
	# why the two differ when they do.
	world.events.publish({
		"type": "director.night",
		"day": day,
		"shape": NIGHT_NAMES[shape],
		"drawn": NIGHT_NAMES[drawn],
		"size": size,
		"side": side,
		"reason": reason,
	})


# How hard the week is leaning, as a row index into NIGHT_WEIGHTS. The three signals the old size
# calculation used, unchanged in meaning: a colony that can fight, a colony that has been loud,
# and a colony that has been left alone too long. What changed is that they choose a *distribution*
# rather than a number.
static func _strain_band(world: Variant, st: Dictionary) -> int:
	var strain: int = 0
	if _power(world) >= 3:
		strain += 1
	if float(st.get("weekPeakNoise", 0.0)) >= FOOTPRINT_NOISE:
		strain += 1
	if int(st.get("nightsSinceQuiet", 0)) >= FLOOR_QUIET_NIGHTS:
		strain += 1
	return clampi(strain, 0, NIGHT_WEIGHTS.size() - 1)


static func _draw_night(world: Variant, band: int) -> int:
	var row: Array = NIGHT_WEIGHTS[band] as Array
	var total: int = 0
	for weight in row:
		total += int(weight)
	if total <= 0:
		return Night.Quiet
	var rng: Variant = world.rng.stream(NIGHT_STREAM)
	var roll: int = int(rng.call("int_range", 0, total - 1))
	for i in row.size():
		roll -= int(row[i])
		if roll < 0:
			return i
	return Night.Quiet


# Returns the side it came from, for the `director.night` event. docs/17's migration lever says a
# crowd arrives "somewhere the field decides", and it always arrived from the south -- the one
# authored approach -- so ten nights of a campaign all came down the same street.
static func _emit_packet(world: Variant, size: int) -> String:
	var rng: Variant = world.rng.stream("director")
	var sides: Array = _edges_by_side(world)
	var side: int = _side_from_field(world, sides, rng)
	if side < 0:
		return ""
	var pool: Array = sides[side] as Array
	for _i in size:
		var pick: Vector2i = pool[int(rng.call("int_range", 0, pool.size() - 1))]
		var type_id: String = SimRoster.pick_type(world, rng)
		SimRoster.spawn_zombie(world, float(pick.x) + 0.5, float(pick.y) + 0.5, type_id, rng)
	(world.director as Dictionary)["lastMigrationTick"] = int(world.tick)
	world.events.publish({"type": "director.packet", "size": size, "side": SIDE_NAMES[side]})
	return SIDE_NAMES[side]


# The legal edge tiles of the district, split by side. North and south take the corners, which is
# arbitrary and only has to be consistent: a corner belonging to two sides could be drawn twice
# from one pool.
static func _edges_by_side(world: Variant) -> Array:
	var sides: Array = [[], [], [], []]
	var map: Variant = world.tilemap
	if map == null:
		return sides
	var w: int = int(map.w)
	var h: int = int(map.h)
	for y in h:
		for x in w:
			if x > 2 and x < w - 3 and y > 2 and y < h - 3:
				continue
			if not _legal_tile(world, x, y):
				continue
			if y <= 2:
				(sides[0] as Array).append(Vector2i(x, y))
			elif y >= h - 3:
				(sides[2] as Array).append(Vector2i(x, y))
			elif x >= w - 3:
				(sides[1] as Array).append(Vector2i(x, y))
			else:
				(sides[3] as Array).append(Vector2i(x, y))
	return sides


# Which way the noise points. Sampling the field along each edge answers "where has this colony
# been operating", and that is where a crowd moving through the region meets them -- the field
# deciding rather than the map deciding once, at authoring time.
#
# A silent district has no answer, and gets a seeded one rather than a default: falling back to a
# fixed side would put the whole distribution back where it was on every quiet week.
static func _side_from_field(world: Variant, sides: Array, rng: Variant) -> int:
	var usable: Array = []
	for i in sides.size():
		if not (sides[i] as Array).is_empty():
			usable.append(i)
	if usable.is_empty():
		return -1
	var best: int = -1
	var best_noise: float = 0.0
	if world.field != null:
		for i in usable:
			var tiles: Array = sides[i] as Array
			var total: float = 0.0
			var at: int = 0
			while at < tiles.size():
				var t: Vector2i = tiles[at]
				total += float(world.field.noise_at(float(t.x) + 0.5, float(t.y) + 0.5))
				at += SIDE_SAMPLE_STRIDE
			if total > best_noise:
				best_noise = total
				best = int(i)
	if best >= 0:
		return best
	return int(usable[int(rng.call("int_range", 0, usable.size() - 1))])


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
	if until > int(st.get("lullUntilTick", 0)):
		if int(world.tick) < int(st.get("lullFromTick", 0)):
			st["lullFromTick"] = start
		st["lullUntilTick"] = until
