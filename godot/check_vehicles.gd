extends SceneTree
# The parked cars, driven. Slice 10 of the Dungeon Settlers arc made a car a manifest record the
# layout wrote (`map.vehicles`, Tile.Low under it, one picture per axis); this slice makes every
# record an entity at boot and lets the player get in and drive it. `sim/modules/vehicles.gd` is
# the module: `spawn_from_manifest` stands one `vehicle` entity per record, `vehicle.toggle` is
# the command (and E, through fortify's ladder) that mounts the car in reach or dismounts, the driver's `move` is the
# car's intent, `_drive` integrates a four-heading car with a leading-edge probe, and `sync_map`
# keeps the map's Low tiles and its records as the entity's shadow -- at spawn, after every
# footprint change, and after a restore.
#
# Ten lanes plus the budget, each with a true positive and a true negative, because a gate that
# cannot fail is worse than no gate:
#
#   CONTENT   every class content declares carries a whole `drive` block -- speed, accel, brake,
#             noise, idle -- and the schema names it. A class fabricated without one is refused
#             by the same reader that accepts the real ones, and a body cannot get into it.
#   SPAWN     the suburb at 128 stands exactly one entity per manifest record, every record
#             names its entity, its footprint is Low and the entity's position is its centre.
#             `bare` at 128 stands the records and no entities (the bare-world guarantee every
#             two-world gate rests on), and `playable` at 64 stands nothing at all, because its
#             streets are too narrow to park -- so the balance harness never sees a car.
#   MOUNT     on a hand-built map with a hand-placed sedan: a body beside it gets in (mounted,
#             driver set, position pinned to the centre), a body out of reach does not, a second
#             body cannot take a wheel somebody holds, the door does not open at speed, and the
#             door opens onto a free tile beside the car when it has stopped. The HUD clause is
#             words, and the right words, in all three states.
#   DRIVE     the driver's move is the car's intent: holding the heading accelerates to the
#             class's cap and no further, the position and the driver's position move together,
#             the record and the Low tiles follow the footprint and the tiles left behind go back
#             to Floor; the opposite key brakes to a stop and turns the car round; no key coasts
#             to a stop; a perpendicular key turns the stopped car about its centre onto whole
#             tiles, and is refused when the turned footprint would cover a wall.
#   BLOCK     the leading-edge probe: a wall, another car, a heap (a Low tile no record covers)
#             and an indoor tile each stop the car flush against them with nothing overlapped,
#             and the same road with nothing on it does not.
#   NOISE     the engine reaches the attention field through the one emitter system every
#             footstep uses: the field under a driven car is louder than under an idling one,
#             which is louder than under a parked one, which is silent -- and with the emitter
#             component taken off the car the field stays silent, which is the dead-socket
#             assertion that the field reads the component and not the module.
#   E-KEY     the owner's 2026-09-05 decision: E is the door. On fortify's ladder, `use.context`
#             from the wheel gets out (never picks up what the car stands over), from the kerb
#             gets in -- after a loose item beside the car, which E still picks up first.
#   FUEL      the tank: spawn rolls every car's litres off the `vehicles` stream (varying by car
#             and by seed, never above the tank), driving burns them at the class's range and
#             idling at its idle minutes, a dry tank takes no throttle and rolls to a stop in
#             silence, and a fabricated full tank drives the same road. The words are the only
#             readout, and they move with the litres.
#   CONDITION the hitpoints: spawn rolls integrity (some wrecks, none over the maximum), a crash
#             at speed costs integrity on the square of the speed and puts a bang on the field,
#             a bump under CRASH_MIN_SPEED costs nothing, a battered car is slower than a sound
#             one and a wrecked one will not move at all. The five words are the whole readout.
#   HOOD      E at the nose looks under the hood and E at the side gets in, on fortify's ladder;
#             the report is words on the HUD for HOOD_REPORT_TICKS and then gone; the view's keys
#             are HOOD_KEYS and nothing else, every value a word or a boolean -- the health-bar
#             ban's allowlist, applied to a car -- and a numeric key fabricated into it is caught.
#   DASH      the driver's seat: `dash_view` is {} off the wheel and DASH_KEYS on it -- words
#             and booleans plus exactly the two needle fractions, in [0, 1], never a digit in a
#             string -- with the gear following the pedals (park stopped, drive under throttle,
#             neutral coasting, the brake lamp on the other keys), the speed word rising to
#             "flat out" at the cap, the engine lamp on a battered car and red on a wreck, the
#             fuel needle at the tank's fraction; a fabricated numeric key is caught; main.gd
#             feeds ui/dashboard.gd every refresh, and that file's string literals carry no
#             digit -- the scanner proved on a fabricated one.
#   SHELTER   a body at the wheel is off the shambler's menu: `_gather_survivors` lists it on
#             foot and not in the car -- and a rider on a bicycle IS listed, because the shelter
#             is the cab and a bicycle has none.
#   LIGHT     the light vehicles (the owner's fourth goal of 2026-09-05): every class content
#             declares names a power, a cab and a dash the schema allows; a muscle class rides
#             with no tank and burns nothing, a battery class rides under power and, flat, at
#             its unpowered speed; a bicycle outruns a sprint and a skateboard does not, both
#             quieter than a sprint; a grab and a crash at speed put a rider off an open vehicle
#             and never a driver out of a cab; each layout's dash carries its own motion words
#             and no digit; the HUD says get on and off; a light class parks one tile wide at
#             128 with a kerb row free either side and never hosts a car-boot site.
#   SAVE      a car driven and saved comes back where it was driven to: the restored world's
#             entity, record, Low tiles and cleared tail all match, in a second world that had
#             the car parked where the layout put it.
#   SOCKETS   textual, every scanner proved on a fabricated string first: world's integrate skips
#             the `vehicle` component and its restore re-syncs the shadow; boot registers the
#             module and spawns from the manifest; the shambler's gather skips `mounted`; fortify's
#             E ladder mounts and dismounts; main.gd skips the mounted body, keys its index on the map's vehicle
#             generation and reads the HUD clause; dressing hashes paint on the home corner and
#             stands the picture on the live ground point.
#   BUDGET    the whole gate inside a minute.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimVehicles = preload("res://sim/modules/vehicles.gd")
const SimAttention = preload("res://sim/modules/attention_emitter.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimWorldgen = preload("res://sim/map/worldgen.gd")
const ContentLoader = preload("res://platform/content_loader.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimItems = preload("res://sim/modules/items.gd")

const CANON_SEED: int = 20260805
const PARK_SIZE: int = 128
const HAND: int = 60
const BUDGET_SECONDS: float = 60.0

const WORLD_GD: String = "res://sim/world.gd"
const BOOT_GD: String = "res://sim/boot.gd"
const SHAMBLER_GD: String = "res://sim/modules/shambler.gd"
const MAIN_GD: String = "res://presentation/main.gd"
const DRESSING_GD: String = "res://presentation/dressing.gd"
const DASH_GD: String = "res://ui/dashboard.gd"
const FORTIFY_GD: String = "res://sim/modules/fortify.gd"
const WORLDGEN_GD: String = "res://sim/map/worldgen.gd"
const SCHEMA: String = "res://content/schemas/vehicle.schema.json"

# The hand sedan: 2x5, nose north, parked in the middle of an empty paved square, so a drive in
# any direction has twenty tiles of road before the edge.
const CAR_X: int = 29
const CAR_Y: int = 40


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var started: int = Time.get_ticks_msec()
	var ok: bool = true
	var stash: Dictionary = {}
	ok = _every_class_declares_how_it_drives(stash) and ok
	ok = _the_suburb_stands_one_entity_per_record(stash) and ok
	ok = _a_body_gets_in_and_out(stash) and ok
	ok = _the_driver_moves_the_car(stash) and ok
	ok = _the_leading_edge_stops_it(stash) and ok
	ok = _the_engine_reaches_the_field(stash) and ok
	ok = _e_is_the_door(stash) and ok
	ok = _the_tank_runs_down(stash) and ok
	ok = _a_crash_costs_condition(stash) and ok
	ok = _the_hood_speaks_in_words(stash) and ok
	ok = _the_dash_shows_the_seat(stash) and ok
	ok = _a_driver_is_off_the_menu(stash) and ok
	ok = _the_light_vehicles_ride(stash) and ok
	ok = _a_driven_car_survives_a_save(stash) and ok
	ok = _the_sockets_are_wired() and ok
	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	ok = _the_gate_stayed_inside_its_own_budget(seconds) and ok
	if ok:
		print("M2_VEHICLES_OK %d classes drive; suburb@%d stands %d cars as entities and @64 none; a body gets in, drives to %.1f m/s and no faster, turns, brakes, coasts and gets out; a wall, a car, a heap and a doorway each stop it flush; the field reads %.1f under way, %.1f idling, 0 parked and 0 with the emitter off; E gets in after the loot and out from the wheel; the tank runs down and a dry one stops the car; a crash costs condition and a wreck will not move; the hood speaks in words; the dash shows gear, speed, fuel and the engine lamp with no digit; a driver is off the shambler's menu and a rider on it; the bicycle rides at %.1f with no tank, the e-bike drops to %.1f flat, a grab and a crash unseat a rider and never a driver, three dash layouts and no digit; a driven car restores where it was driven; sockets wired; %.1f s of a %.0f s budget" % [
			int(stash.get("classes", 0)), PARK_SIZE, int(stash.get("suburb_cars", 0)),
			float(stash.get("top_speed", 0.0)), float(stash.get("noise_driving", 0.0)), float(stash.get("noise_idle", 0.0)),
			float(stash.get("bicycle_top", 0.0)), float(stash.get("ebike_flat", 0.0)),
			seconds, BUDGET_SECONDS,
		])
		quit(0)
	else:
		push_error("M2_VEHICLES_FAIL")
		quit(1)


# --- the hand world --------------------------------------------------------------------------

# A world on an empty paved 60x60 map with one sedan parked nose-north at (CAR_X, CAR_Y), the
# kernel attached (so the field and the map are live), the vehicle and attention modules
# registered, and the player standing on the tile west of the driver's door.
func _hand_world(record: Dictionary = {}) -> Variant:
	var fixture: Dictionary = {
		"seed": 7, "tick_hz": 20,
		"map": {"width": HAND, "height": HAND, "walls": []},
		"player": {"id": 0, "x": 5.0, "y": 5.0, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	}
	var w: Variant = World.new(fixture)
	var map: Variant = SimTileMap.blank_map(HAND, HAND)
	SimBoot.attach_kernel(w, map)
	SimVehicles.register_module(w)
	SimAttention.register_module(w, map)
	var rec: Dictionary = record if not record.is_empty() else _sedan_record()
	_park(map, rec)
	SimVehicles.spawn_from_manifest(w, map)
	# The hand car is fuelled and sound whatever the stream rolled, so every lane that drives it
	# is judging steering and collision and not a tank; FUEL and CONDITION set their own.
	for c in w.components.query(["vehicle"]):
		var hv: Dictionary = w.components.get_component(int(c), "vehicle") as Dictionary
		hv["fuel"] = float(SimVehicles.drive_of(SimVehicles.class_of(w, String(hv["class"]))).get("tank", 0.0))
		hv["integrity"] = SimVehicles.INTEGRITY_MAX
	var pos: Dictionary = w.components.get_component(w.player, "position") as Dictionary
	pos["x"] = float(CAR_X - 1) + 0.5
	pos["y"] = float(CAR_Y + 2) + 0.5
	return w


func _sedan_record() -> Dictionary:
	return {"x": CAR_X, "y": CAR_Y, "w": 2, "h": 5, "axis": "ns", "class": "vehicle.sedan", "facing": "n"}


# A light vehicle parked where the sedan would be: one tile across, nose north, the player's
# tile west of it still beside it.
func _light_record(cls: String, length: int) -> Dictionary:
	return {"x": CAR_X, "y": CAR_Y, "w": 1, "h": length, "axis": "ns", "class": "vehicle.%s" % cls, "facing": "n"}


func _bicycle_record() -> Dictionary:
	return _light_record("bicycle", 2)


# What the generator does for a record: the record into the manifest and Low under it.
func _park(map: Variant, rec: Dictionary) -> void:
	for ty in range(int(rec["y"]), int(rec["y"]) + int(rec["h"])):
		for tx in range(int(rec["x"]), int(rec["x"]) + int(rec["w"])):
			map.tiles[ty * int(map.w) + tx] = SimTileMap.Tile.Low
	(map.vehicles as Array).append(rec)


func _wall(w: Variant, tx: int, ty: int, solid: bool = true) -> void:
	var map: Variant = w.tilemap
	map.tiles[ty * int(map.w) + tx] = SimTileMap.Tile.Wall if solid else SimTileMap.Tile.Floor
	w.map_cells[ty * int(w.map_width) + tx] = 1 if solid else 0


func _car_of(w: Variant) -> int:
	var cars: Array = w.components.query(["vehicle"])
	return int(cars[0]) if not cars.is_empty() else -1


func _v(w: Variant, car: int) -> Dictionary:
	return w.components.get_component(car, "vehicle") as Dictionary


func _pos(w: Variant, e: int) -> Dictionary:
	return w.components.get_component(e, "position") as Dictionary


func _record_of(map: Variant, car: int) -> Dictionary:
	for rec in map.vehicles as Array:
		if rec is Dictionary and int((rec as Dictionary).get("entity", -1)) == car:
			return rec as Dictionary
	return {}


func _low_tiles(map: Variant) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for ty in int(map.h):
		for tx in int(map.w):
			if int(map.tiles[ty * int(map.w) + tx]) == SimTileMap.Tile.Low:
				out.append(Vector2i(tx, ty))
	return out


# Whether the Low tiles of the map are exactly the record's rectangle.
func _low_matches(map: Variant, rec: Dictionary) -> String:
	var rect := Rect2i(int(rec["x"]), int(rec["y"]), int(rec["w"]), int(rec["h"]))
	var lows: Array[Vector2i] = _low_tiles(map)
	if lows.size() != rect.size.x * rect.size.y:
		return "%d Low tiles against a %dx%d record" % [lows.size(), rect.size.x, rect.size.y]
	for t in lows:
		if not rect.has_point(t):
			return "Low at %s outside the record %s" % [str(t), str(rect)]
	return ""


func _toggle(w: Variant) -> void:
	w.commands.push({"type": SimVehicles.TOGGLE})
	w.step()


func _move(w: Variant, dx: float, dy: float, ticks: int) -> void:
	w.commands.push({"type": "move", "dx": dx, "dy": dy})
	for i in ticks:
		w.step()


func _has_digit(text: String) -> bool:
	for i in text.length():
		var c: int = text.unicode_at(i)
		if c >= 48 and c <= 57:
			return true
	return false


# --- 1. CONTENT ----------------------------------------------------------------------------

func _every_class_declares_how_it_drives(stash: Dictionary) -> bool:
	var tree: Dictionary = ContentLoader.load_tree()
	var classes: Array = SimWorldgen.vehicles_of(tree)
	if classes.is_empty():
		push_error("CONTENT: no vehicle classes in content; nothing to judge")
		return false
	for entry in classes:
		var id: String = String((entry as Dictionary).get("id", "?"))
		var drive: Dictionary = SimVehicles.drive_of(entry as Dictionary)
		if drive.is_empty():
			push_error("CONTENT: %s declares no whole drive block {speed, accel, brake, noise, idle}" % id)
			return false
		# The speed and noise rules follow the power: an engine is faster and louder than a
		# sprint or it is not a car; a muscle or battery class is faster than a walk (or it is
		# not worth getting on) and no louder than a sprint (tyres and a hub motor are not).
		var power: String = SimVehicles.power_of(drive)
		if power == SimVehicles.POWER_ENGINE:
			if float(drive["speed"]) <= 6.3:
				push_error("CONTENT: %s tops out at %.1f m/s, slower than a sprint (6.3); a car you cannot outrun on foot is not a car" % [id, float(drive["speed"])])
				return false
			if float(drive["noise"]) <= 6.0:
				push_error("CONTENT: %s's engine (%.1f) is no louder than a sprint (6.0)" % [id, float(drive["noise"])])
				return false
		else:
			if float(drive["speed"]) <= 2.1:
				push_error("CONTENT: %s tops out at %.1f m/s, no faster than a walk (2.1); a ride slower than walking is not worth getting on" % [id, float(drive["speed"])])
				return false
			if float(drive["noise"]) > 6.0:
				push_error("CONTENT: %s makes %.1f under way, louder than a sprint (6.0); a bicycle is not an engine" % [id, float(drive["noise"])])
				return false
			if float(drive["speed"]) >= 8.0:
				push_error("CONTENT: %s tops out at %.1f m/s, as fast as a truck (8); the light classes sit between a walk and a car" % [id, float(drive["speed"])])
				return false
		if power == SimVehicles.POWER_MUSCLE and float(drive["tank"]) != 0.0:
			push_error("CONTENT: %s is muscle-powered and declares a tank" % id)
			return false
		if power != SimVehicles.POWER_MUSCLE and float(drive["tank"]) <= 0.0:
			push_error("CONTENT: %s has a motor and no tank or battery" % id)
			return false
		if not SimVehicles.DASH_LAYOUTS.has(String((entry as Dictionary).get("dash", ""))):
			push_error("CONTENT: %s declares dash '%s', not one of %s" % [id, String((entry as Dictionary).get("dash", "")), str(SimVehicles.DASH_LAYOUTS)])
			return false
		if not ((entry as Dictionary).get("cab") is bool):
			push_error("CONTENT: %s declares no boolean `cab`" % id)
			return false
		if bool((entry as Dictionary).get("cab", false)) != (power == SimVehicles.POWER_ENGINE):
			push_error("CONTENT: %s's cab (%s) disagrees with its power (%s); every car here has a cab and nothing else does" % [id, str((entry as Dictionary).get("cab")), power])
			return false
	# The negatives: the same reader refuses a block missing a key, a zero speed and a non-number.
	var whole: Dictionary = {"drive": {"power": "engine", "speed": 10, "accel": 4, "brake": 8, "noise": 24, "idle": 4, "tank": 40, "range": 12000, "idleMinutes": 90}}
	if SimVehicles.drive_of(whole).is_empty():
		push_error("CONTENT: the reader refused a whole block; it cannot say yes")
		return false
	var short: Dictionary = {"drive": {"power": "engine", "speed": 10, "accel": 4, "brake": 8, "noise": 24, "tank": 40, "range": 12000, "idleMinutes": 90}}
	if not SimVehicles.drive_of(short).is_empty():
		push_error("CONTENT: the reader accepted a block with no idle; a car would drive on a default nothing declared")
		return false
	var no_tank: Dictionary = {"drive": {"power": "engine", "speed": 10, "accel": 4, "brake": 8, "noise": 24, "idle": 4, "range": 12000, "idleMinutes": 90}}
	if not SimVehicles.drive_of(no_tank).is_empty():
		push_error("CONTENT: the reader accepted a block with no tank; a car would burn fuel it never had")
		return false
	var still: Dictionary = {"drive": {"power": "engine", "speed": 0, "accel": 4, "brake": 8, "noise": 24, "idle": 4, "tank": 40, "range": 12000, "idleMinutes": 90}}
	if not SimVehicles.drive_of(still).is_empty():
		push_error("CONTENT: the reader accepted speed 0")
		return false
	var words: Dictionary = {"drive": {"power": "engine", "speed": "fast", "accel": 4, "brake": 8, "noise": 24, "idle": 4, "tank": 40, "range": 12000, "idleMinutes": 90}}
	if not SimVehicles.drive_of(words).is_empty():
		push_error("CONTENT: the reader accepted a string for a number")
		return false
	# The power's own negatives: no power, a power nobody named, a battery with no tank, a
	# muscle block with none -- accepted, its tank keys reading zero -- and a negative unpowered.
	var unpowered: Dictionary = {"drive": {"speed": 10, "accel": 4, "brake": 8, "noise": 24, "idle": 4, "tank": 40, "range": 12000, "idleMinutes": 90}}
	if not SimVehicles.drive_of(unpowered).is_empty():
		push_error("CONTENT: the reader accepted a block that names no power")
		return false
	var steam: Dictionary = {"drive": {"power": "steam", "speed": 10, "accel": 4, "brake": 8, "noise": 24, "idle": 4, "tank": 40, "range": 12000, "idleMinutes": 90}}
	if not SimVehicles.drive_of(steam).is_empty():
		push_error("CONTENT: the reader accepted a power nobody named")
		return false
	var flat_battery: Dictionary = {"drive": {"power": "battery", "speed": 7, "accel": 2, "brake": 5, "noise": 4, "idle": 0}}
	if not SimVehicles.drive_of(flat_battery).is_empty():
		push_error("CONTENT: the reader accepted a battery class with no tank; it would spend charge it never had")
		return false
	var legs: Dictionary = {"drive": {"power": "muscle", "speed": 6, "accel": 2, "brake": 5, "noise": 3, "idle": 0}}
	var legs_read: Dictionary = SimVehicles.drive_of(legs)
	if legs_read.is_empty() or float(legs_read["tank"]) != 0.0 or float(legs_read["range"]) != 0.0 or float(legs_read["unpowered"]) != 0.0:
		push_error("CONTENT: a muscle block with no tank keys was refused or read a tank: %s" % str(legs_read))
		return false
	var backwards: Dictionary = {"drive": {"power": "battery", "speed": 7, "accel": 2, "brake": 5, "noise": 4, "idle": 0, "tank": 500, "range": 8000, "idleMinutes": 600, "unpowered": -1}}
	if not SimVehicles.drive_of(backwards).is_empty():
		push_error("CONTENT: the reader accepted a negative unpowered speed")
		return false
	if not SimVehicles.drive_of({}).is_empty():
		push_error("CONTENT: the reader accepted an entry with no drive block at all")
		return false
	# The schema names the block and requires it, so a class written without one is loud at
	# `godot:validate` and not only here.
	var schema_text: String = _code_of(SCHEMA)
	if not schema_text.contains("\"drive\"") or not schema_text.contains("\"required\": [\"id\", \"name\", \"drive\""):
		push_error("CONTENT: %s does not require a drive block" % SCHEMA)
		return false
	for key in SimVehicles.DRIVE_KEYS:
		if not schema_text.contains("\"%s\"" % key):
			push_error("CONTENT: %s never names drive.%s; a class could omit it and only the reader would notice" % [SCHEMA, key])
			return false
	for key2 in ["\"power\"", "\"unpowered\"", "\"cab\"", "\"dash\"", "\"muscle\"", "\"battery\"", "\"handlebar\"", "\"board\""]:
		if not schema_text.contains(String(key2)):
			push_error("CONTENT: %s never names %s; the light-vehicle keys are unschema'd" % [SCHEMA, String(key2)])
			return false
	if not schema_text.contains("\"required\": [\"id\", \"name\", \"drive\", \"cab\", \"dash\""):
		push_error("CONTENT: %s does not require cab and dash" % SCHEMA)
		return false
	# And a class the world does not declare, or declares without a drive, cannot be mounted:
	# the hand world with a fabricated class that has a footprint and no drive.
	var w: Variant = _hand_world()
	(w.content as Dictionary)["vehicles/zz_fake.json"] = {"id": "vehicle.fake", "name": "Fake", "cab": true, "dash": "cluster", "footprint": {"w": 2, "l": 5}, "appearance": {"variants": []}}
	var fake: Dictionary = {"x": CAR_X + 10, "y": CAR_Y, "w": 2, "h": 5, "axis": "ns", "class": "vehicle.fake", "facing": "n"}
	_park(w.tilemap, fake)
	var spawned: Array[int] = SimVehicles.spawn_from_manifest(w, w.tilemap)
	if spawned.size() != 1:
		push_error("CONTENT: expected the fake class to spawn one entity (it has a footprint), got %d" % spawned.size())
		return false
	var p: Dictionary = _pos(w, w.player)
	p["x"] = float(CAR_X + 9) + 0.5
	p["y"] = float(CAR_Y + 2) + 0.5
	var problem: String = SimVehicles.mount_problem(w, w.player, spawned[0])
	if not problem.contains("drive"):
		push_error("CONTENT: a class with no drive block was not refused at the wheel (problem: '%s')" % problem)
		return false
	stash["classes"] = classes.size()
	print("CONTENT OK %d classes each declare a power, a cab, a dash and a whole drive block of %d keys -- the engines faster and louder than a sprint, the rest faster than a walk, quieter than a sprint and slower than a truck; the schema requires it and names every key; a block missing idle, one missing its tank, a zero speed, a string, no block, no power, a power nobody named, a battery with no tank and a negative unpowered are refused, a muscle block with no tank keys reads zero, and a fabricated class with no drive block cannot be mounted ('%s')" % [classes.size(), SimVehicles.DRIVE_KEYS.size(), problem])
	return true


# --- 2. SPAWN ------------------------------------------------------------------------------

func _the_suburb_stands_one_entity_per_record(stash: Dictionary) -> bool:
	var boot: Dictionary = SimBoot.playable(CANON_SEED, PARK_SIZE)
	var w: Variant = boot["world"]
	var map: Variant = boot["map"]
	var cars: Array = w.components.query(["vehicle"])
	var records: Array = map.vehicles as Array
	if cars.is_empty():
		push_error("SPAWN: the suburb at %d stood no vehicle entities" % PARK_SIZE)
		return false
	if cars.size() != records.size():
		push_error("SPAWN: %d entities against %d records; the shadow and the truth disagree" % [cars.size(), records.size()])
		return false
	var named: Dictionary = {}
	for rec in records:
		var r: Dictionary = rec as Dictionary
		var e: int = int(r.get("entity", -1))
		if e < 0 or not w.components.has_component(e, "vehicle"):
			push_error("SPAWN: record %s names no vehicle entity" % str(r))
			return false
		if named.has(e):
			push_error("SPAWN: entity %d is named by two records" % e)
			return false
		named[e] = true
		var v: Dictionary = _v(w, e)
		var p: Dictionary = _pos(w, e)
		var want_x: float = float(int(r["x"])) + float(int(r["w"])) / 2.0
		var want_y: float = float(int(r["y"])) + float(int(r["h"])) / 2.0
		if absf(float(p["x"]) - want_x) > 1e-6 or absf(float(p["y"]) - want_y) > 1e-6:
			push_error("SPAWN: entity %d stands at (%.2f, %.2f), not its record's centre (%.2f, %.2f)" % [e, float(p["x"]), float(p["y"]), want_x, want_y])
			return false
		if String(v["heading"]) != String(r["facing"]) or String(v["class"]) != String(r["class"]):
			push_error("SPAWN: entity %d's heading/class %s/%s differ from its record's %s/%s" % [e, v["heading"], v["class"], r["facing"], r["class"]])
			return false
		if int(r.get("hx", -1)) != int(r["x"]) or int(r.get("hy", -1)) != int(r["y"]):
			push_error("SPAWN: a freshly parked record's home corner is not its corner: %s" % str(r))
			return false
		for ty in range(int(r["y"]), int(r["y"]) + int(r["h"])):
			for tx in range(int(r["x"]), int(r["x"]) + int(r["w"])):
				if SimTileMap.tile_at(map, tx, ty) != SimTileMap.Tile.Low:
					push_error("SPAWN: (%d, %d) under record %s is not Low" % [tx, ty, str(r)])
					return false
		if w.components.has_component(e, "velocity") or w.components.has_component(e, "attention_emitter"):
			push_error("SPAWN: parked entity %d carries an engine (velocity or emitter); a parked car must cost the tick nothing" % e)
			return false
	# The same manifest as the generator's own, record for record on the footprint keys: spawning
	# moved nothing.
	var generated: Variant = SimWorldgen.generate(CANON_SEED, PARK_SIZE, w.content)
	var pristine: Array = generated.vehicles as Array
	if pristine.size() != records.size():
		push_error("SPAWN: the booted manifest has %d records against the generator's %d" % [records.size(), pristine.size()])
		return false
	for i in pristine.size():
		for k in ["x", "y", "w", "h", "axis", "class", "facing"]:
			if str((pristine[i] as Dictionary)[k]) != str((records[i] as Dictionary)[k]):
				push_error("SPAWN: record %d differs from the generator's on %s: %s vs %s" % [i, k, str(records[i]), str(pristine[i])])
				return false
	# The bare world: records and no entities.
	var bare: Dictionary = SimBoot.bare(CANON_SEED, PARK_SIZE)
	var bw: Variant = bare["world"]
	if (bare["map"].vehicles as Array).is_empty():
		push_error("SPAWN: bare@%d parked nothing; the negative has nothing to judge" % PARK_SIZE)
		return false
	if not (bw.components.query(["vehicle"]) as Array).is_empty():
		push_error("SPAWN: bare@%d stood vehicle entities; every two-world gate boots bare and its entity table must not change" % PARK_SIZE)
		return false
	# And 64: nothing, for the width reason check_wrecks.gd holds.
	var small: Dictionary = SimBoot.playable(CANON_SEED, 64)
	if not ((small["world"]).components.query(["vehicle"]) as Array).is_empty() or not ((small["map"]).vehicles as Array).is_empty():
		push_error("SPAWN: playable@64 stood a vehicle; the balance harness would now see cars and its FAST lines could move")
		return false
	# Drive one of the real ones, to prove the hand world below is not the only road this works
	# on: the first car with a free tile beside it.
	var driven: int = -1
	var door: Variant = null
	for c in cars:
		door = SimVehicles.exit_tile(w, _v(w, int(c)), _pos(w, int(c)))
		if door != null:
			driven = int(c)
			break
	if driven < 0:
		push_error("SPAWN: no suburb car has a free tile beside it")
		return false
	var pp: Dictionary = _pos(w, w.player)
	pp["x"] = float((door as Vector2i).x) + 0.5
	pp["y"] = float((door as Vector2i).y) + 0.5
	var gen_before: int = int(map.vehicle_generation)
	_toggle(w)
	if not w.components.has_component(w.player, "mounted"):
		push_error("SPAWN: the player could not get into suburb car %d from %s (%s)" % [driven, str(door), SimVehicles.mount_problem(w, w.player, driven)])
		return false
	var dv: Dictionary = _v(w, driven)
	var dir: Vector2 = SimVehicles.HEADINGS[String(dv["heading"])] as Vector2
	var start: Vector2 = Vector2(float(_pos(w, driven)["x"]), float(_pos(w, driven)["y"]))
	_move(w, dir.x, dir.y, 30)
	var now: Vector2 = Vector2(float(_pos(w, driven)["x"]), float(_pos(w, driven)["y"]))
	if start.distance_to(now) < 1.0:
		push_error("SPAWN: suburb car %d drove %.2f m in 30 ticks; expected at least a metre" % [driven, start.distance_to(now)])
		return false
	if int(map.vehicle_generation) <= gen_before:
		push_error("SPAWN: the car moved a tile and the map's vehicle generation did not; the drawing node's index would be stale")
		return false
	stash["suburb_cars"] = cars.size()
	print("SPAWN OK suburb@%d stands %d cars as entities, one per record, each at its record's centre on Low tiles with no engine running, the manifest identical to the generator's; bare@%d stands %d records and no entities; playable@64 stands none; suburb car %d drove %.1f m in 30 ticks and bumped the vehicle generation" % [PARK_SIZE, cars.size(), PARK_SIZE, (bare["map"].vehicles as Array).size(), driven, start.distance_to(now)])
	return true


# --- 3. MOUNT ------------------------------------------------------------------------------

func _a_body_gets_in_and_out(stash: Dictionary) -> bool:
	var w: Variant = _hand_world()
	var car: int = _car_of(w)
	if car < 0:
		push_error("MOUNT: the hand world stood no car")
		return false
	# Out of reach first: the player moved three tiles off the door.
	var p: Dictionary = _pos(w, w.player)
	var door_x: float = float(p["x"])
	var door_y: float = float(p["y"])
	p["x"] = door_x - 3.0
	var far_clause: String = SimVehicles.hud_clause(w, w.player)
	if not far_clause.is_empty():
		push_error("MOUNT: the HUD offers a car three tiles away: '%s'" % far_clause)
		return false
	_toggle(w)
	if w.components.has_component(w.player, "mounted"):
		push_error("MOUNT: a body three tiles from the door got in")
		return false
	if String(SimVehicles.mount_problem(w, w.player, car)) != "out of reach":
		push_error("MOUNT: the problem three tiles off is '%s', not 'out of reach'" % SimVehicles.mount_problem(w, w.player, car))
		return false
	# Beside it: in.
	p["x"] = door_x
	var near_clause: String = SimVehicles.hud_clause(w, w.player)
	if not near_clause.contains("beside you") or not near_clause.contains("sedan") or _has_digit(near_clause):
		push_error("MOUNT: the clause beside a sedan reads '%s'" % near_clause)
		return false
	_toggle(w)
	if not w.components.has_component(w.player, "mounted"):
		push_error("MOUNT: a body beside the door did not get in (%s)" % SimVehicles.mount_problem(w, w.player, car))
		return false
	var v: Dictionary = _v(w, car)
	if int(v["driver"]) != int(w.player):
		push_error("MOUNT: driver is %d, not the player" % int(v["driver"]))
		return false
	var cp: Dictionary = _pos(w, car)
	if absf(float(p["x"]) - float(cp["x"])) > 1e-6 or absf(float(p["y"]) - float(cp["y"])) > 1e-6:
		push_error("MOUNT: the driver stands at (%.2f, %.2f), not the car's centre (%.2f, %.2f)" % [p["x"], p["y"], cp["x"], cp["y"]])
		return false
	if not w.components.has_component(car, "velocity") or not w.components.has_component(car, "attention_emitter"):
		push_error("MOUNT: the engine did not start (no velocity or emitter on the car)")
		return false
	var in_clause: String = SimVehicles.hud_clause(w, w.player)
	if not in_clause.contains("wheel") or _has_digit(in_clause):
		push_error("MOUNT: the clause at the wheel reads '%s'" % in_clause)
		return false
	# A second body cannot take the wheel.
	var other: int = int(w.entities.spawn())
	w.components.set_component(other, "position", {"x": door_x, "y": door_y})
	var taken: String = SimVehicles.mount_problem(w, other, car)
	if not taken.contains("driving"):
		push_error("MOUNT: a second body beside a driven car was not refused ('%s')" % taken)
		return false
	# The door stays shut at speed.
	v["speed"] = 3.0
	var moving_clause: String = SimVehicles.hud_clause(w, w.player)
	if not moving_clause.contains("driving") or _has_digit(moving_clause):
		push_error("MOUNT: the clause under way reads '%s'" % moving_clause)
		return false
	if SimVehicles.dismount(w, w.player):
		push_error("MOUNT: the door opened at 3 m/s")
		return false
	v["speed"] = 0.0
	# Stopped: out, onto a free tile beside the car, engine off.
	_toggle(w)
	if w.components.has_component(w.player, "mounted"):
		push_error("MOUNT: the stopped car did not let the driver out")
		return false
	if int(v["driver"]) != SimVehicles.NO_DRIVER:
		push_error("MOUNT: the car still names a driver after the dismount")
		return false
	if w.components.has_component(car, "velocity") or w.components.has_component(car, "attention_emitter"):
		push_error("MOUNT: the engine kept running after the dismount")
		return false
	var rect := Rect2i(CAR_X, CAR_Y, 2, 5)
	var out_tile := Vector2i(floori(float(p["x"])), floori(float(p["y"])))
	if rect.has_point(out_tile):
		push_error("MOUNT: the driver got out onto the car's own footprint %s" % str(out_tile))
		return false
	if SimTileMap.tile_at(w.tilemap, out_tile.x, out_tile.y) != SimTileMap.Tile.Floor:
		push_error("MOUNT: the driver got out onto a non-Floor tile %s" % str(out_tile))
		return false
	if rect.grow(1).has_point(out_tile) == false:
		push_error("MOUNT: the driver got out at %s, not beside the car %s" % [str(out_tile), str(rect)])
		return false
	# A car walled in has no door: every ring tile a wall, and the driver stays.
	_toggle(w)
	if not w.components.has_component(w.player, "mounted"):
		push_error("MOUNT: could not get back in for the walled-in case")
		return false
	for t in _ring(rect):
		_wall(w, t.x, t.y)
	_toggle(w)
	if not w.components.has_component(w.player, "mounted"):
		push_error("MOUNT: a driver got out of a car with a wall on every side")
		return false
	for t in _ring(rect):
		_wall(w, t.x, t.y, false)
	_toggle(w)
	if w.components.has_component(w.player, "mounted"):
		push_error("MOUNT: with the walls gone the door still did not open")
		return false
	print("MOUNT OK out of reach refused ('out of reach'), beside the door in with the driver pinned to the centre and the engine started, a second body refused ('%s'), the door shut at speed, out onto %s with the engine off, and a walled-in car keeps its driver until the walls go; the three clauses are words: '%s' / '%s' / '%s'" % [taken, str(out_tile), near_clause, in_clause, moving_clause])
	return true


func _ring(rect: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for ty in range(rect.position.y - 1, rect.end.y + 1):
		for tx in range(rect.position.x - 1, rect.end.x + 1):
			if not rect.has_point(Vector2i(tx, ty)):
				out.append(Vector2i(tx, ty))
	return out


# --- 4. DRIVE ------------------------------------------------------------------------------

func _the_driver_moves_the_car(stash: Dictionary) -> bool:
	var w: Variant = _hand_world()
	var map: Variant = w.tilemap
	var car: int = _car_of(w)
	_toggle(w)
	if not w.components.has_component(w.player, "mounted"):
		push_error("DRIVE: could not mount")
		return false
	var v: Dictionary = _v(w, car)
	var cp: Dictionary = _pos(w, car)
	var pp: Dictionary = _pos(w, w.player)
	var drive: Dictionary = SimVehicles.drive_of(SimVehicles.class_of(w, "vehicle.sedan"))
	var cap: float = float(drive["speed"])
	var y0: float = float(cp["y"])
	# North, forty ticks: two seconds at accel 4 is eight metres of road and a speed under the cap.
	var top: float = 0.0
	w.commands.push({"type": "move", "dx": 0.0, "dy": -1.0})
	for i in 40:
		w.step()
		top = maxf(top, float(v["speed"]))
		if float(v["speed"]) > cap + 1e-6:
			push_error("DRIVE: %.2f m/s over the class's %.1f cap on tick %d" % [float(v["speed"]), cap, i])
			return false
		if absf(float(pp["x"]) - float(cp["x"])) > 1e-6 or absf(float(pp["y"]) - float(cp["y"])) > 1e-6:
			push_error("DRIVE: the driver came unpinned on tick %d: (%.2f, %.2f) vs car (%.2f, %.2f)" % [i, pp["x"], pp["y"], cp["x"], cp["y"]])
			return false
	var travelled: float = y0 - float(cp["y"])
	if travelled < 5.0 or travelled > 10.0:
		push_error("DRIVE: forty ticks north travelled %.2f m; expected roughly eight" % travelled)
		return false
	if absf(float(cp["x"]) - float(CAR_X + 1)) > 1e-6:
		push_error("DRIVE: a northbound car drifted across to x %.3f" % float(cp["x"]))
		return false
	var rec: Dictionary = _record_of(map, car)
	if rec.is_empty():
		push_error("DRIVE: the moving car has no record")
		return false
	if int(rec["y"]) >= CAR_Y:
		push_error("DRIVE: the record still sits at y %d after the car drove north to %.2f" % [int(rec["y"]), float(cp["y"])])
		return false
	var problem: String = _low_matches(map, rec)
	if not problem.is_empty():
		push_error("DRIVE: the Low tiles do not match the moved record: %s" % problem)
		return false
	if SimTileMap.tile_at(map, CAR_X, CAR_Y + 4) != SimTileMap.Tile.Floor:
		push_error("DRIVE: the tail tile the car left is still Low")
		return false
	if absf(float(rec["gx"]) - float(cp["x"])) > 1e-6 or absf(float(rec["gy"]) - (float(cp["y"]) + 2.5)) > 1e-6:
		push_error("DRIVE: the record's ground point (%.2f, %.2f) is not the live south-edge centre (%.2f, %.2f)" % [rec["gx"], rec["gy"], cp["x"], float(cp["y"]) + 2.5])
		return false
	# Hold north until the cap: it gets there and stays there.
	for i in 40:
		w.step()
		top = maxf(top, float(v["speed"]))
	if absf(top - cap) > 1e-6:
		push_error("DRIVE: eighty ticks of throttle peaked at %.2f, not the cap %.1f" % [top, cap])
		return false
	stash["top_speed"] = top
	# The opposite key: brakes to a stop, then turns round -- heading and the record's facing both.
	var y_brake: float = float(cp["y"])
	var stopped_at: int = -1
	w.commands.push({"type": "move", "dx": 0.0, "dy": 1.0})
	for i in 60:
		w.step()
		if stopped_at < 0 and String(v["heading"]) == "s":
			stopped_at = i
	if stopped_at < 0:
		push_error("DRIVE: sixty ticks of the opposite key never turned the car round")
		return false
	if stopped_at < 10:
		push_error("DRIVE: the car turned round on tick %d from %.1f m/s; a 180 is not a snap" % [stopped_at, cap])
		return false
	if float(v["speed"]) <= 0.0:
		push_error("DRIVE: turned round and not moving off again")
		return false
	if float(cp["y"]) < y_brake:
		push_error("DRIVE: braking from north to south still ended further north")
		return false
	rec = _record_of(map, car)
	if String(rec["facing"]) != "s":
		push_error("DRIVE: the record's facing is %s after the turn" % rec["facing"])
		return false
	# No key: coasts to a stop -- still moving after five ticks, stopped inside eighty.
	w.commands.push({"type": "wait"})
	for i in 5:
		w.step()
	if float(v["speed"]) <= 0.0:
		push_error("DRIVE: a car with the foot off the pedal stopped dead inside five ticks")
		return false
	for i in 75:
		w.step()
	if float(v["speed"]) != 0.0:
		push_error("DRIVE: still rolling at %.2f eighty ticks after the foot came off" % float(v["speed"]))
		return false
	# Perpendicular from a stop: the car turns about its centre onto whole tiles, the record and
	# the Low tiles follow, and the count of Low tiles on the map is still one sedan.
	var before_turn: Vector2 = Vector2(float(cp["x"]), float(cp["y"]))
	_move(w, 1.0, 0.0, 1)
	if String(v["heading"]) != "e":
		push_error("DRIVE: a stopped car asked east is heading %s" % v["heading"])
		return false
	rec = _record_of(map, car)
	if int(rec["w"]) != 5 or int(rec["h"]) != 2 or String(rec["axis"]) != "ew":
		push_error("DRIVE: the turned record is %s, not a 5x2 ew one" % str(rec))
		return false
	problem = _low_matches(map, rec)
	if not problem.is_empty():
		push_error("DRIVE: after the turn the Low tiles do not match: %s" % problem)
		return false
	if before_turn.distance_to(Vector2(float(cp["x"]), float(cp["y"]))) > 0.75:
		push_error("DRIVE: the turn moved the centre %.2f m; snapping to the grid should move it half a tile at most" % before_turn.distance_to(Vector2(float(cp["x"]), float(cp["y"]))))
		return false
	if absf(fmod(float(cp["x"]), 1.0) - 0.5) > 1e-6 or absf(fmod(float(cp["y"]), 1.0)) > 1e-6:
		push_error("DRIVE: an east-west sedan's centre (%.2f, %.2f) is not on the half-tile across and the boundary down" % [cp["x"], cp["y"]])
		return false
	# Let it roll east a little, stop, and then refuse a turn north into a wall: the ns footprint
	# would cover (cx-1, cy-2.5) -> the tile north of the ew body's west end.
	_move(w, 1.0, 0.0, 10)
	_move(w, 0.0, 0.0, 80)
	if float(v["speed"]) != 0.0:
		push_error("DRIVE: not stopped before the refused-turn case")
		return false
	rec = _record_of(map, car)
	var own := Rect2i(int(rec["x"]), int(rec["y"]), int(rec["w"]), int(rec["h"]))
	var turned: Rect2i = SimVehicles.turned_footprint(v, cp, "n")
	if turned.size != Vector2i(2, 5):
		push_error("DRIVE: the turned footprint is %s, not 2x5" % str(turned))
		return false
	# The northernmost tile of the turned footprint is outside the ew body: that is where the
	# wall goes, so the case proves the turn is judged on the tiles it would cover and not on
	# the ones it already does.
	var blocked_tile := Vector2i(turned.position.x, turned.position.y)
	if own.has_point(blocked_tile):
		push_error("DRIVE: the fabricated wall would sit inside the car's own footprint; the case would prove nothing")
		return false
	_wall(w, blocked_tile.x, blocked_tile.y)
	_move(w, 0.0, -1.0, 3)
	if String(v["heading"]) != "e":
		push_error("DRIVE: the car turned north through a wall at %s" % str(blocked_tile))
		return false
	_wall(w, blocked_tile.x, blocked_tile.y, false)
	_move(w, 0.0, -1.0, 3)
	if String(v["heading"]) != "n":
		push_error("DRIVE: with the wall gone the car still would not turn north")
		return false
	# Moving off north already, so the footprint is mid-tile: the Low tiles are exactly what the
	# record says, twelve rather than ten, and nothing of the east-west body was left behind.
	problem = _low_matches(map, _record_of(map, car))
	if not problem.is_empty():
		push_error("DRIVE: after the turn north the Low tiles do not match: %s" % problem)
		return false
	print("DRIVE OK forty ticks north travelled %.1f m with the driver pinned every tick, the record and its Low tiles following and the tail going back to Floor; eighty ticks peaked at the %.1f cap and no more; the opposite key turned the car round on tick %d and the record's facing with it; no key rolled on past five ticks and stopped inside eighty; east from a stop turned onto a 5x2 record on whole tiles; a wall at %s refused the turn north and its removal allowed it" % [travelled, top, stopped_at, str(blocked_tile)])
	return true


# --- 5. BLOCK ------------------------------------------------------------------------------

# Drives the hand sedan north for `ticks` and answers where its centre ended.
func _north_ends_at(w: Variant, ticks: int) -> Dictionary:
	var car: int = _car_of(w)
	_toggle(w)
	if not w.components.has_component(w.player, "mounted"):
		return {}
	_move(w, 0.0, -1.0, ticks)
	return {"car": car, "y": float(_pos(w, car)["y"]), "speed": float(_v(w, car)["speed"])}


func _the_leading_edge_stops_it(stash: Dictionary) -> bool:
	# The open road: sixty ticks north from centre y 42.5 gets well past y 36.
	var open_w: Variant = _hand_world()
	var open: Dictionary = _north_ends_at(open_w, 60)
	if open.is_empty() or float(open["y"]) >= 36.0:
		push_error("BLOCK: on an open road sixty ticks north ended at %s; the blocked cases below would prove nothing" % str(open))
		return false
	# A wall across y 35: the nose (centre - 2.5) stops at 36, so the centre at 38.5, speed 0.
	var walled: Variant = _hand_world()
	for tx in range(CAR_X - 2, CAR_X + 4):
		_wall(walled, tx, 35)
	var hit: Dictionary = _north_ends_at(walled, 60)
	if absf(float(hit["y"]) - 38.5) > 1e-6 or float(hit["speed"]) != 0.0:
		push_error("BLOCK: against a wall at y 35 the car ended at y %.3f, speed %.2f; expected 38.5 and stopped" % [hit["y"], hit["speed"]])
		return false
	for tx in range(CAR_X - 2, CAR_X + 4):
		if SimTileMap.tile_at(walled.tilemap, tx, 35) != SimTileMap.Tile.Wall:
			push_error("BLOCK: the car overwrote the wall at (%d, 35)" % tx)
			return false
	# Held against it, it stays put and stays stopped.
	_move(walled, 0.0, -1.0, 20)
	if absf(float(_pos(walled, int(hit["car"]))["y"]) - 38.5) > 1e-6:
		push_error("BLOCK: twenty more ticks against the wall moved the car")
		return false
	# Another car across the road at y 30..34: the nose stops at 35, the centre at 37.5.
	var traffic: Variant = _hand_world()
	var ahead: Dictionary = {"x": CAR_X, "y": 30, "w": 2, "h": 5, "axis": "ns", "class": "vehicle.sedan", "facing": "s"}
	_park(traffic.tilemap, ahead)
	SimVehicles.spawn_from_manifest(traffic, traffic.tilemap)
	var jam: Dictionary = _north_ends_at(traffic, 60)
	if absf(float(jam["y"]) - 37.5) > 1e-6 or float(jam["speed"]) != 0.0:
		push_error("BLOCK: behind a parked car the driven one ended at y %.3f, speed %.2f; expected 37.5 and stopped" % [jam["y"], jam["speed"]])
		return false
	if _low_tiles(traffic.tilemap).size() != 20:
		push_error("BLOCK: two sedans stand %d Low tiles, not 20; one drove into the other" % _low_tiles(traffic.tilemap).size())
		return false
	# A heap: one Low tile no record covers, at (CAR_X, 34).
	var junk: Variant = _hand_world()
	junk.tilemap.tiles[34 * HAND + CAR_X] = SimTileMap.Tile.Low
	var heap: Dictionary = _north_ends_at(junk, 60)
	if absf(float(heap["y"]) - 37.5) > 1e-6 or float(heap["speed"]) != 0.0:
		push_error("BLOCK: against a heap at y 34 the car ended at y %.3f, speed %.2f; expected 37.5 and stopped" % [heap["y"], heap["speed"]])
		return false
	if SimTileMap.tile_at(junk.tilemap, CAR_X, 34) != SimTileMap.Tile.Low:
		push_error("BLOCK: the heap is gone; the car drove over it and its sync cleared it")
		return false
	# A doorway: an indoor tile at (CAR_X + 1, 34) -- Floor, walkable, and not a road.
	var house: Variant = _hand_world()
	house.tilemap.indoors[34 * HAND + CAR_X + 1] = 1
	var porch: Dictionary = _north_ends_at(house, 60)
	if absf(float(porch["y"]) - 37.5) > 1e-6 or float(porch["speed"]) != 0.0:
		push_error("BLOCK: against an indoor tile at y 34 the car ended at y %.3f, speed %.2f; expected 37.5 and stopped" % [porch["y"], porch["speed"]])
		return false
	# And the probe is the one that says so: `tile_blocks` refuses each kind and accepts open road.
	var probe_w: Variant = _hand_world()
	var pc: int = _car_of(probe_w)
	if SimVehicles.tile_blocks(probe_w, probe_w.tilemap, pc, CAR_X, 20):
		push_error("BLOCK: tile_blocks refused open paved floor")
		return false
	if not SimVehicles.tile_blocks(probe_w, probe_w.tilemap, pc, -1, 20) or not SimVehicles.tile_blocks(probe_w, probe_w.tilemap, pc, CAR_X, HAND):
		push_error("BLOCK: tile_blocks accepted a tile off the map")
		return false
	if SimVehicles.tile_blocks(probe_w, probe_w.tilemap, pc, CAR_X, CAR_Y):
		push_error("BLOCK: tile_blocks refused the car its own footprint; it could never move")
		return false
	print("BLOCK OK open road: sixty ticks north ended at y %.1f; a wall at y 35 stopped the car flush at 38.5 and twenty more ticks did not move it; a parked car ahead stopped it at 37.5 with both cars' twenty tiles intact; a heap at y 34 stopped it at 37.5 and stayed a heap; a doorway at y 34 stopped it at 37.5; the probe refuses off-map tiles and accepts open road and the car's own tiles" % float(open["y"]))
	return true


# --- 6. NOISE ------------------------------------------------------------------------------

func _the_engine_reaches_the_field(stash: Dictionary) -> bool:
	# Parked: nothing at all, twenty ticks.
	var parked: Variant = _hand_world()
	var car: int = _car_of(parked)
	var cp: Dictionary = _pos(parked, car)
	for i in 20:
		parked.step()
	var silent: float = float(parked.field.noise_at(float(cp["x"]), float(cp["y"])))
	if silent != 0.0:
		push_error("NOISE: a parked car with nobody in it reads %.2f on the field" % silent)
		return false
	# Idling: mounted, no intent.
	var idling: Variant = _hand_world()
	var ic: int = _car_of(idling)
	_toggle(idling)
	for i in 20:
		idling.step()
	var icp: Dictionary = _pos(idling, ic)
	var idle: float = float(idling.field.noise_at(float(icp["x"]), float(icp["y"])))
	if idle <= 0.0:
		push_error("NOISE: an idling engine reads %.2f on the field; the emitter's ambient is not reaching it" % idle)
		return false
	# Driving: louder still, read under the car where it now is.
	var driving: Variant = _hand_world()
	var dc: int = _car_of(driving)
	_toggle(driving)
	_move(driving, 0.0, -1.0, 20)
	var dcp: Dictionary = _pos(driving, dc)
	var loud: float = float(driving.field.noise_at(float(dcp["x"]), float(dcp["y"])))
	if loud <= idle:
		push_error("NOISE: driving reads %.2f against %.2f idling; the engine under way is no louder than at rest" % [loud, idle])
		return false
	# The driver's own feet are silent: every noise.emitted this tick names the car, never the body.
	var feet: int = 0
	var engine: int = 0
	driving.commands.push({"type": "move", "dx": 0.0, "dy": -1.0})
	driving.step()
	for e in driving.events.drained:
		if String((e as Dictionary).get("type", "")) != "noise.emitted":
			continue
		if int((e as Dictionary).get("source", -1)) == int(driving.player):
			feet += 1
		elif int((e as Dictionary).get("source", -1)) == dc:
			engine += 1
	if feet != 0 or engine != 1:
		push_error("NOISE: on a driving tick the bus carried %d footstep(s) from the driver and %d engine note(s); expected 0 and 1" % [feet, engine])
		return false
	# The dead-socket assertion: take the emitter off the car and the field goes quiet while the
	# car still drives -- so the field is reading the component, and the module wrote it.
	# Mounted through the module call rather than the toggle tick, so the engine's first idle
	# note never reaches the field: the first cut of this lane read 3.2 from that one note,
	# still decaying twenty ticks later, and blamed the module for it.
	var muted: Variant = _hand_world()
	var mc: int = _car_of(muted)
	if not SimVehicles.mount(muted, muted.player, mc):
		push_error("NOISE: could not mount the muted car")
		return false
	muted.components.remove(mc, "attention_emitter")
	var mp: Dictionary = _pos(muted, mc)
	var y0: float = float(mp["y"])
	_move(muted, 0.0, -1.0, 20)
	if float(mp["y"]) >= y0:
		push_error("NOISE: the muted car did not drive; the negative proves nothing")
		return false
	var quiet: float = float(muted.field.noise_at(float(mp["x"]), float(mp["y"])))
	if quiet != 0.0:
		push_error("NOISE: with the emitter gone the field still reads %.2f under a driving car; something else is emitting" % quiet)
		return false
	stash["noise_driving"] = loud
	stash["noise_idle"] = idle
	print("NOISE OK parked 0.0, idling %.1f, driving %.1f on the field under the car; a driving tick puts one engine note and no footstep on the bus; the emitter taken off, a driving car reads 0.0" % [idle, loud])
	return true


# --- 7. E-KEY ------------------------------------------------------------------------------

func _e_is_the_door(stash: Dictionary) -> bool:
	var w: Variant = _hand_world()
	SimHealth.register_module(w)
	SimInventory.register_module(w)
	SimFortify.register_module(w)
	SimHealth.make_survivor_body(w, w.player)
	SimHealth.make_stamina(w, w.player)
	SimInventory.make_inventory(w, w.player)
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	var car: int = _car_of(w)
	var p: Dictionary = _pos(w, w.player)
	var door_x: float = float(p["x"])
	var door_y: float = float(p["y"])
	# A loose knife on the door tile: E picks it up and does not get in.
	var knife: int = SimItems.spawn_item(w, "item.knife.kitchen", {"tier": "scavenged"})
	w.components.set_component(knife, "position", {"x": door_x, "y": door_y})
	w.commands.push({"type": "use.context"})
	w.step()
	if w.components.has_component(knife, "position"):
		push_error("E-KEY: E beside a car did not pick up the knife at the driver's feet")
		return false
	if w.components.has_component(w.player, "mounted"):
		push_error("E-KEY: E got into the car with a knife at the driver's feet; the loot rung must come first")
		return false
	# Nothing loose: E gets in.
	w.commands.push({"type": "use.context"})
	w.step()
	if not w.components.has_component(w.player, "mounted"):
		push_error("E-KEY: E beside the car with nothing else in reach did not get in (%s)" % SimVehicles.mount_problem(w, w.player, car))
		return false
	# A knife under the car: from the wheel E gets out and leaves it where it is.
	var under: int = SimItems.spawn_item(w, "item.knife.kitchen", {"tier": "scavenged"})
	w.components.set_component(under, "position", {"x": float(p["x"]), "y": float(p["y"])})
	w.commands.push({"type": "use.context"})
	w.step()
	if w.components.has_component(w.player, "mounted"):
		push_error("E-KEY: E from the wheel did not get out")
		return false
	if not w.components.has_component(under, "position"):
		push_error("E-KEY: E from the wheel picked up the knife under the car instead of opening the door")
		return false
	# And at speed, E from the wheel does nothing at all -- no dismount, no fall-through.
	w.commands.push({"type": "use.context"})
	w.step()
	if not w.components.has_component(w.player, "mounted"):
		push_error("E-KEY: could not get back in for the at-speed case (%s)" % SimVehicles.mount_problem(w, w.player, car))
		return false
	_v(w, car)["speed"] = 3.0
	w.commands.push({"type": "use.context"})
	w.step()
	if not w.components.has_component(w.player, "mounted"):
		push_error("E-KEY: E opened the door at speed")
		return false
	if not w.components.has_component(under, "position"):
		push_error("E-KEY: E at speed fell through the ladder and picked up the knife under the car")
		return false
	_v(w, car)["speed"] = 0.0
	# Nothing in presentation pushes the toggle any more: E is the one door.
	var input_body: String = _function_body(MAIN_GD, "_input")
	if input_body.contains("SimVehicles.TOGGLE") or input_body.contains("vehicle.toggle"):
		push_error("E-KEY: main.gd still pushes the toggle from a key of its own; the owner's decision is E")
		return false
	print("E-KEY OK a knife at the door is picked up before the car; with nothing loose E gets in; from the wheel E gets out and leaves the knife under the car; at speed E does nothing; no key of its own remains in main.gd")
	return true


# --- 8. FUEL -------------------------------------------------------------------------------

func _the_tank_runs_down(stash: Dictionary) -> bool:
	var tank: float = float(SimVehicles.drive_of(SimVehicles.class_of(_hand_world(), "vehicle.sedan"))["tank"])
	# Spawn: the suburb's tanks vary car to car, none over the tank, and move with the seed.
	var a: Dictionary = SimBoot.playable(CANON_SEED, PARK_SIZE)
	var b: Dictionary = SimBoot.playable(CANON_SEED + 1, PARK_SIZE)
	var seen: Dictionary = {}
	var a_fuels: Array = []
	for c in (a["world"]).components.query(["vehicle"]):
		var v: Dictionary = (a["world"]).components.get_component(int(c), "vehicle") as Dictionary
		var t: float = float(SimVehicles.drive_of(SimVehicles.class_of(a["world"], String(v["class"])))["tank"])
		if float(v["fuel"]) < 0.0 or float(v["fuel"]) > t:
			push_error("FUEL: car %d spawned with %.2f litres in a %.0f litre tank" % [int(c), float(v["fuel"]), t])
			return false
		seen[snappedf(float(v["fuel"]), 0.01)] = true
		a_fuels.append(float(v["fuel"]))
	if seen.size() < 5:
		push_error("FUEL: %d cars spawned with only %d distinct tanks; the roll is not reaching the litres" % [a_fuels.size(), seen.size()])
		return false
	var b_fuels: Array = []
	for c in (b["world"]).components.query(["vehicle"]):
		b_fuels.append(float((b["world"]).components.get_component(int(c), "vehicle")["fuel"]))
	if a_fuels.size() == b_fuels.size() and a_fuels == b_fuels:
		push_error("FUEL: two seeds parked identical tanks; the stream is not seeded")
		return false
	var again: Dictionary = SimBoot.playable(CANON_SEED, PARK_SIZE)
	var again_fuels: Array = []
	for c in (again["world"]).components.query(["vehicle"]):
		again_fuels.append(float((again["world"]).components.get_component(int(c), "vehicle")["fuel"]))
	if again_fuels != a_fuels:
		push_error("FUEL: the same seed parked different tanks twice; the roll is not deterministic")
		return false
	# The roll itself: a low roll is a low tank, a roll of one a full one, and a class with no
	# drive block parks dry.
	if SimVehicles.rolled_fuel({"tank": 40.0}, 0.5) != 10.0 or SimVehicles.rolled_fuel({"tank": 40.0}, 1.0) != 40.0 or SimVehicles.rolled_fuel({}, 0.9) != 0.0:
		push_error("FUEL: rolled_fuel is not the square of the roll times the tank")
		return false
	# Driving burns it, idling burns less, and the word follows the litres.
	var w: Variant = _hand_world()
	var car: int = _car_of(w)
	var v: Dictionary = _v(w, car)
	v["fuel"] = tank * 0.5
	_toggle(w)
	for i in 40:
		w.step()
	var after_idle: float = float(v["fuel"])
	if after_idle >= tank * 0.5:
		push_error("FUEL: forty ticks idling burned nothing")
		return false
	var idle_cost: float = tank * 0.5 - after_idle
	_move(w, 0.0, -1.0, 40)
	var drive_cost: float = after_idle - float(v["fuel"])
	if drive_cost <= idle_cost:
		push_error("FUEL: forty ticks driving (%.4f L) burned no more than forty idling (%.4f L)" % [drive_cost, idle_cost])
		return false
	if SimVehicles.fuel_word(float(v["fuel"]), tank) != "about half a tank":
		push_error("FUEL: half a tank reads '%s'" % SimVehicles.fuel_word(float(v["fuel"]), tank))
		return false
	# The words, over the whole range, in order, and never a digit.
	var last: int = -1
	for f in [0.0, 0.05, 0.2, 0.45, 0.75, 0.95, 1.0]:
		var band: int = SimVehicles.fuel_band(f * tank, tank)
		if band < last:
			push_error("FUEL: the fuel bands are not monotone")
			return false
		last = band
		if _has_digit(SimVehicles.fuel_word(f * tank, tank)):
			push_error("FUEL: a fuel word carries a digit: '%s'" % SimVehicles.fuel_word(f * tank, tank))
			return false
	if SimVehicles.fuel_word(0.0, tank) != "dry" or SimVehicles.fuel_word(tank, tank) != "full":
		push_error("FUEL: the ends of the scale are not dry and full")
		return false
	# A dry tank: no throttle, the car rolls to a stop, the engine goes quiet on the field, and
	# the clause at the wheel says so.
	var dry: Variant = _hand_world()
	var dc: int = _car_of(dry)
	var dv: Dictionary = _v(dry, dc)
	_toggle(dry)
	_move(dry, 0.0, -1.0, 40)
	var y_running: float = float(_pos(dry, dc)["y"])
	dv["fuel"] = 0.0
	_move(dry, 0.0, -1.0, 100)
	if float(dv["speed"]) != 0.0:
		push_error("FUEL: a dry car is still doing %.2f m/s a hundred ticks on" % float(dv["speed"]))
		return false
	if float(_pos(dry, dc)["y"]) >= y_running:
		push_error("FUEL: the dry car did not even coast")
		return false
	var em: Dictionary = dry.components.get_component(dc, "attention_emitter") as Dictionary
	if float(em["ambient"]) != 0.0 or float(em["walking"]) != 0.0:
		push_error("FUEL: a dry engine still idles at %.1f on the emitter" % float(em["ambient"]))
		return false
	var clause: String = SimVehicles.hud_clause(dry, dry.player)
	if not clause.contains("dry") or _has_digit(clause):
		push_error("FUEL: the clause at a dry wheel reads '%s'" % clause)
		return false
	# And a splash makes it go again.
	dv["fuel"] = tank * 0.05
	_move(dry, 0.0, -1.0, 20)
	if float(dv["speed"]) <= 0.0:
		push_error("FUEL: a splash in the tank did not move the car")
		return false
	stash["tank"] = tank
	print("FUEL OK suburb@%d spawns %d cars with %d distinct tanks inside their capacity, differing between seeds and identical on one; the roll is the square; forty ticks idling burned %.3f L and forty driving %.3f L off a %.0f L tank; six words in order, dry to full, no digits; a dry car takes no throttle, coasts to a stop in silence and says so, and a splash starts it again" % [PARK_SIZE, a_fuels.size(), seen.size(), idle_cost, drive_cost, tank])
	return true


# --- 9. CONDITION --------------------------------------------------------------------------

func _a_crash_costs_condition(stash: Dictionary) -> bool:
	# Spawn: integrity within 0..100, some wrecks over four seeds and most not.
	var wrecked: int = 0
	var total: int = 0
	for seed_val in [CANON_SEED, CANON_SEED + 1, CANON_SEED + 2, CANON_SEED + 3]:
		var boot: Dictionary = SimBoot.playable(seed_val, PARK_SIZE)
		for c in (boot["world"]).components.query(["vehicle"]):
			var v: Dictionary = (boot["world"]).components.get_component(int(c), "vehicle") as Dictionary
			var integrity: float = float(v["integrity"])
			if integrity < 0.0 or integrity > SimVehicles.INTEGRITY_MAX:
				push_error("CONDITION: car %d spawned at integrity %.1f" % [int(c), integrity])
				return false
			total += 1
			if SimVehicles.condition_band(integrity) == 0:
				wrecked += 1
	if wrecked == 0 or wrecked == total:
		push_error("CONDITION: %d of %d cars over four seeds are wrecks; the roll is not reaching the street" % [wrecked, total])
		return false
	# The roll's shape: the bottom tenth is a wreck, just over it is the floor, one is the top.
	if SimVehicles.rolled_integrity(0.05) != 0.0 or SimVehicles.rolled_integrity(0.1) != SimVehicles.INTEGRITY_ROLL_FLOOR or absf(SimVehicles.rolled_integrity(1.0) - SimVehicles.INTEGRITY_MAX) > 1e-9:
		push_error("CONDITION: rolled_integrity's shape is off")
		return false
	# The words: five, in order, no digits, and the bands the caps follow.
	var last_band: int = -1
	for integrity in [0.0, 10.0, 45.0, 70.0, 100.0]:
		var band: int = SimVehicles.condition_band(integrity)
		if band <= last_band:
			push_error("CONDITION: the bands are not strictly rising through 0, 10, 45, 70, 100")
			return false
		last_band = band
		if _has_digit(SimVehicles.condition_word(integrity)):
			push_error("CONDITION: a condition word carries a digit")
			return false
	if SimVehicles.condition_word(0.0) != "wrecked" or SimVehicles.condition_word(100.0) != "sound":
		push_error("CONDITION: the ends of the scale are not wrecked and sound")
		return false
	# A crash into a wall at speed costs integrity, bangs on the bus, and a bump costs nothing.
	var w: Variant = _hand_world()
	for tx in range(CAR_X - 2, CAR_X + 4):
		_wall(w, tx, 30)
	var car: int = _car_of(w)
	var v: Dictionary = _v(w, car)
	_toggle(w)
	var bangs: Array = []
	var crashes: Array = []
	w.commands.push({"type": "move", "dx": 0.0, "dy": -1.0})
	for i in 60:
		w.step()
		for e in w.events.drained:
			var ev: Dictionary = e as Dictionary
			if String(ev.get("type", "")) == "vehicle.crashed":
				crashes.append(ev)
			if String(ev.get("type", "")) == "noise.emitted" and int(ev.get("source", -1)) == car and float(ev.get("magnitude", 0.0)) > 50.0:
				bangs.append(ev)
	if crashes.size() != 1:
		push_error("CONDITION: a run at a wall produced %d crash events, not one" % crashes.size())
		return false
	var damage: float = float((crashes[0] as Dictionary)["damage"])
	if damage <= 0.0 or absf((SimVehicles.INTEGRITY_MAX - damage) - float(v["integrity"])) > 1e-6:
		push_error("CONDITION: the crash reported %.1f damage and the car is at %.1f" % [damage, float(v["integrity"])])
		return false
	if bangs.size() != 1:
		push_error("CONDITION: the crash put %d bangs on the bus, not one" % bangs.size())
		return false
	if SimVehicles.condition_band(float(v["integrity"])) >= SimVehicles.condition_band(SimVehicles.INTEGRITY_MAX):
		push_error("CONDITION: a full-speed crash left the car sound")
		return false
	var crash_speed: float = float((crashes[0] as Dictionary)["speed"])
	if absf(damage - SimVehicles.crash_damage(crash_speed, 10.0)) > 1e-6:
		push_error("CONDITION: damage %.2f is not crash_damage(%.2f) = %.2f" % [damage, crash_speed, SimVehicles.crash_damage(crash_speed, 10.0)])
		return false
	# A bump: a wall hard against the nose, so the car meets it on its first tick at a fifth of
	# a metre a second, costs nothing. (A tile of run-up is not a bump: over one metre at the
	# sedan's acceleration a car is already doing 2.8 m/s, above CRASH_MIN_SPEED, and the first
	# cut of this case learned that the expensive way.)
	if SimVehicles.crash_damage(1.5, 10.0) != 0.0 or SimVehicles.crash_noise(1.5, 10.0) != 0.0:
		push_error("CONDITION: a bump under CRASH_MIN_SPEED costs or sounds")
		return false
	var bump: Variant = _hand_world()
	for tx in range(CAR_X - 2, CAR_X + 4):
		_wall(bump, tx, CAR_Y - 1)
	var bc: int = _car_of(bump)
	_toggle(bump)
	var bumped: bool = false
	bump.commands.push({"type": "move", "dx": 0.0, "dy": -1.0})
	for i in 20:
		bump.step()
		for e in bump.events.drained:
			if String((e as Dictionary).get("type", "")) == "vehicle.crashed":
				bumped = true
	if bumped or float(_v(bump, bc)["integrity"]) != SimVehicles.INTEGRITY_MAX:
		push_error("CONDITION: a bump from one tile off cost the car condition")
		return false
	if float(_pos(bump, bc)["y"]) != float(CAR_Y) + 2.5 or float(_v(bump, bc)["speed"]) != 0.0:
		push_error("CONDITION: the bump case moved or is still rolling (y %.2f, %.2f m/s)" % [float(_pos(bump, bc)["y"]), float(_v(bump, bc)["speed"])])
		return false
	# Battered is slower than sound over the same road, and wrecked does not move.
	var sound: Variant = _hand_world()
	var sc: int = _car_of(sound)
	_toggle(sound)
	_move(sound, 0.0, -1.0, 60)
	var sound_y: float = float(_pos(sound, sc)["y"])
	var battered: Variant = _hand_world()
	var bat: int = _car_of(battered)
	_v(battered, bat)["integrity"] = 45.0
	_toggle(battered)
	_move(battered, 0.0, -1.0, 60)
	var battered_y: float = float(_pos(battered, bat)["y"])
	if battered_y <= sound_y:
		push_error("CONDITION: a battered car (y %.2f) drove as far as a sound one (y %.2f)" % [battered_y, sound_y])
		return false
	var wreck: Variant = _hand_world()
	var wc: int = _car_of(wreck)
	_v(wreck, wc)["integrity"] = 0.0
	_toggle(wreck)
	if not wreck.components.has_component(wreck.player, "mounted"):
		push_error("CONDITION: a wreck cannot even be sat in")
		return false
	_move(wreck, 0.0, -1.0, 40)
	if float(_pos(wreck, wc)["y"]) != float(CAR_Y) + 2.5 or float(_v(wreck, wc)["speed"]) != 0.0:
		push_error("CONDITION: a wrecked car moved")
		return false
	var wreck_clause: String = SimVehicles.hud_clause(wreck, wreck.player)
	if not wreck_clause.contains("wrecked") or _has_digit(wreck_clause):
		push_error("CONDITION: the clause at a wrecked wheel reads '%s'" % wreck_clause)
		return false
	# Runs at a wall wreck a sound car -- four of them, because each crash lowers the cap the
	# next one is made at (55 at full speed, then 27 battered, 11 failing, 11 again): the
	# vehicle.wrecked event, exactly once, and the car in the wrecked band at the end.
	var twice: Variant = _hand_world()
	for tx in range(CAR_X - 2, CAR_X + 4):
		_wall(twice, tx, 20)
	var tc: int = _car_of(twice)
	_toggle(twice)
	var wrecks: int = 0
	for run in 6:
		# Back off to the kerb and run at the wall again, at whatever speed the car still makes.
		var tp: Dictionary = _pos(twice, tc)
		tp["y"] = float(CAR_Y) + 2.5
		_v(twice, tc)["speed"] = 0.0
		twice.commands.push({"type": "move", "dx": 0.0, "dy": -1.0})
		for i in 120:
			twice.step()
			for e in twice.events.drained:
				if String((e as Dictionary).get("type", "")) == "vehicle.wrecked":
					wrecks += 1
	if wrecks != 1:
		push_error("CONDITION: six runs at a wall produced %d vehicle.wrecked events; expected exactly one" % wrecks)
		return false
	if SimVehicles.condition_band(float(_v(twice, tc)["integrity"])) != 0:
		push_error("CONDITION: six runs at a wall left the car %s" % SimVehicles.condition_word(float(_v(twice, tc)["integrity"])))
		return false
	stash["crash_damage"] = damage
	print("CONDITION OK %d of %d cars over four seeds spawn wrecked and the rest 40..100; five words in order, no digits; a run at a wall at %.1f m/s cost %.1f, bangs once on the bus and leaves the car %s, a bump against the nose costs nothing; battered drove %.1f m against sound's %.1f in sixty ticks; a wreck can be sat in and does not move; repeated runs at a wall wreck a sound car with one vehicle.wrecked, each crash slower than the last" % [wrecked, total, crash_speed, damage, SimVehicles.condition_word(float(v["integrity"])), float(CAR_Y) + 2.5 - battered_y, float(CAR_Y) + 2.5 - sound_y])
	return true


# --- 10. HOOD ------------------------------------------------------------------------------

func _the_hood_speaks_in_words(stash: Dictionary) -> bool:
	var w: Variant = _hand_world()
	SimHealth.register_module(w)
	SimInventory.register_module(w)
	SimFortify.register_module(w)
	SimHealth.make_survivor_body(w, w.player)
	SimHealth.make_stamina(w, w.player)
	SimInventory.make_inventory(w, w.player)
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	var car: int = _car_of(w)
	var v: Dictionary = _v(w, car)
	var p: Dictionary = _pos(w, w.player)
	# The view's shape, on a car in a known state: every key allowed, every value a word or a
	# boolean, and the words the state says.
	v["integrity"] = 45.0
	v["fuel"] = float(stash.get("tank", 40.0)) * 0.5
	var view: Dictionary = SimVehicles.hood_view(w, car)
	for key in view.keys():
		if not SimVehicles.HOOD_KEYS.has(String(key)):
			push_error("HOOD: the view carries a disallowed key '%s'; allowed: %s" % [key, SimVehicles.HOOD_KEYS])
			return false
		var value: Variant = view[key]
		if not (value is String or value is bool):
			push_error("HOOD: the view's '%s' is a %s, not a word or a boolean -- that is the number the ban forbids" % [key, type_string(typeof(value))])
			return false
		if value is String and _has_digit(String(value)):
			push_error("HOOD: the view's '%s' carries a digit: '%s'" % [key, value])
			return false
	for required in SimVehicles.HOOD_KEYS:
		if not view.has(required):
			push_error("HOOD: the view is missing '%s'" % required)
			return false
	if String(view["condition"]) != "battered" or String(view["fuel"]) != "about half a tank" or not bool(view["runs"]):
		push_error("HOOD: a battered half-full sedan reads %s" % str(view))
		return false
	# The allowlist can say no: a numeric key fabricated into a copy is caught by the same test.
	var leaked: Dictionary = view.duplicate()
	leaked["integrity"] = 45.0
	var caught: bool = false
	for key in leaked.keys():
		if not SimVehicles.HOOD_KEYS.has(String(key)) or not (leaked[key] is String or leaked[key] is bool):
			caught = true
	if not caught:
		push_error("HOOD: the allowlist passed a view with a numeric integrity in it; it cannot say no")
		return false
	# At the nose: E looks under the hood, the report is words on the HUD, and it lapses.
	p["x"] = float(CAR_X) + 1.0
	p["y"] = float(CAR_Y) - 0.5
	if not SimVehicles.at_hood(w, w.player, car):
		push_error("HOOD: a body a tile off the nose is not at the hood")
		return false
	var nose_clause: String = SimVehicles.hud_clause(w, w.player)
	if not nose_clause.contains("hood") or _has_digit(nose_clause):
		push_error("HOOD: the clause at the nose reads '%s'" % nose_clause)
		return false
	w.commands.push({"type": "use.context"})
	w.step()
	if w.components.has_component(w.player, "mounted"):
		push_error("HOOD: E at the nose got into the car instead of looking under the hood")
		return false
	var report: String = SimVehicles.hud_clause(w, w.player)
	if report != String(view["prose"]) or not report.contains("battered") or not report.contains("half"):
		push_error("HOOD: after E at the nose the HUD reads '%s'" % report)
		return false
	for i in SimVehicles.HOOD_REPORT_TICKS + 2:
		w.step()
	if SimVehicles.hud_clause(w, w.player) == report:
		push_error("HOOD: the report never lapsed")
		return false
	if w.components.has_component(w.player, "hoodReport"):
		push_error("HOOD: the lapsed report is still on the body")
		return false
	# At the side: not at the hood, and E gets in.
	p["x"] = float(CAR_X - 1) + 0.5
	p["y"] = float(CAR_Y + 2) + 0.5
	if SimVehicles.at_hood(w, w.player, car):
		push_error("HOOD: a body at the driver's door is at the hood")
		return false
	w.commands.push({"type": "use.context"})
	w.step()
	if not w.components.has_component(w.player, "mounted"):
		push_error("HOOD: E at the side did not get in")
		return false
	# The tail is not the hood either: the nose is where the heading points.
	w.commands.push({"type": "use.context"})
	w.step()
	p["x"] = float(CAR_X) + 1.0
	p["y"] = float(CAR_Y + 5) + 0.5
	if SimVehicles.at_hood(w, w.player, car):
		push_error("HOOD: a body at the tail of a north-facing car is at the hood")
		return false
	if not SimVehicles.check_hood(w, w.player, car):
		pass
	else:
		push_error("HOOD: check_hood accepted a body at the tail")
		return false
	# A wreck and a dry tank each read as what they are.
	v["integrity"] = 0.0
	if not SimVehicles.hood_view(w, car)["prose"].contains("wrecked") or bool(SimVehicles.hood_view(w, car)["runs"]):
		push_error("HOOD: a wreck reads %s" % str(SimVehicles.hood_view(w, car)))
		return false
	v["integrity"] = 100.0
	v["fuel"] = 0.0
	if not SimVehicles.hood_view(w, car)["prose"].contains("dry") or bool(SimVehicles.hood_view(w, car)["runs"]):
		push_error("HOOD: a dry tank reads %s" % str(SimVehicles.hood_view(w, car)))
		return false
	# The interact key is named once in main.gd and the legend says what E does at a car.
	var main_code: String = _code_of(MAIN_GD)
	if not main_code.contains("const INTERACT_KEY: Key = KEY_E"):
		push_error("HOOD: main.gd does not name INTERACT_KEY as E")
		return false
	var input_body: String = _function_body(MAIN_GD, "_input")
	if not input_body.contains("INTERACT_KEY") or input_body.contains("KEY_E:"):
		push_error("HOOD: main.gd's _input does not route the named interact key, or still matches a literal E")
		return false
	var legend: String = _code_of("res://ui/legend.gd")
	if not legend.contains("\"E\"") or not legend.contains("hood"):
		push_error("HOOD: the legend's E row does not mention the hood")
		return false
	print("HOOD OK the view is %s, every value a word or a boolean, and a numeric key fabricated in is caught; E at the nose reads '%s' for %d ticks and then lapses; E at the side gets in; the tail is not the hood; a wreck and a dry tank read as such; INTERACT_KEY is E, routed by name, and the legend says so" % [str(SimVehicles.HOOD_KEYS), report, SimVehicles.HOOD_REPORT_TICKS])
	return true


# --- 11. DASH ------------------------------------------------------------------------------

func _string_literal_digit(code: String) -> String:
	# The first string literal in `code` that carries a digit, or "" -- skipping colour codes
	# and resource paths, which are literals nobody draws (the first cut caught "#1b1a17e6").
	var rx := RegEx.new()
	rx.compile("\"[^\"\\n]*\"")
	for m in rx.search_all(code):
		var literal: String = m.get_string()
		if literal.begins_with("\"#") or literal.begins_with("\"res://"):
			continue
		if _has_digit(literal):
			return literal
	return ""


func _dash_problem(view: Dictionary) -> String:
	for key in view.keys():
		if not SimVehicles.DASH_KEYS.has(String(key)):
			return "disallowed key '%s'" % key
		var value: Variant = view[key]
		if SimVehicles.DASH_NEEDLES.has(String(key)):
			if not (value is float):
				return "needle '%s' is not a float" % key
			if float(value) < 0.0 or float(value) > 1.0:
				return "needle '%s' is %.3f, outside [0, 1]" % [key, float(value)]
		elif not (value is String or value is bool):
			return "'%s' is a %s, not a word or a boolean" % [key, type_string(typeof(value))]
		elif value is String and _has_digit(String(value)):
			return "'%s' carries a digit: '%s'" % [key, value]
	for required in SimVehicles.DASH_KEYS:
		if not view.has(required):
			return "missing '%s'" % required
	return ""


func _the_dash_shows_the_seat(stash: Dictionary) -> bool:
	var w: Variant = _hand_world()
	var car: int = _car_of(w)
	var v: Dictionary = _v(w, car)
	var top: float = float(SimVehicles.drive_of(SimVehicles.class_of(w, "vehicle.sedan"))["speed"])
	var tank: float = float(stash.get("tank", 40.0))
	# Off the wheel: nothing.
	if not SimVehicles.dash_view(w, w.player).is_empty():
		push_error("DASH: a body on foot has a dashboard")
		return false
	# At the wheel, stopped: park, stopped, needle at zero, gauge full, engine sound, no lamps.
	_toggle(w)
	var view: Dictionary = SimVehicles.dash_view(w, w.player)
	var problem: String = _dash_problem(view)
	if not problem.is_empty():
		push_error("DASH: %s in %s" % [problem, str(view)])
		return false
	if String(view["gear"]) != "park" or String(view["speed"]) != "stopped" or float(view["speedo"]) != 0.0 or bool(view["braking"]) or bool(view["throttle"]) or not bool(view["running"]):
		push_error("DASH: at a stopped wheel the dash reads %s" % str(view))
		return false
	# The toggle tick already idled once, so the gauge sits a hair under full.
	if float(view["gauge"]) < 0.999 or String(view["fuel"]) != "full" or String(view["engine"]) != "sound" or bool(view["warning"]):
		push_error("DASH: a full sound sedan's dash reads %s" % str(view))
		return false
	# Throttle: drive, the needle climbing, the word climbing to flat out at the cap.
	var words: Array = []
	var last_needle: float = 0.0
	w.commands.push({"type": "move", "dx": 0.0, "dy": -1.0})
	for i in 60:
		w.step()
		view = SimVehicles.dash_view(w, w.player)
		problem = _dash_problem(view)
		if not problem.is_empty():
			push_error("DASH: %s on tick %d" % [problem, i])
			return false
		if String(view["gear"]) != "drive" or not bool(view["throttle"]):
			push_error("DASH: under throttle on tick %d the gear is %s" % [i, view["gear"]])
			return false
		if float(view["speedo"]) < last_needle:
			push_error("DASH: the speedo fell under steady throttle on tick %d" % i)
			return false
		last_needle = float(view["speedo"])
		if words.is_empty() or String(words[-1]) != String(view["speed"]):
			words.append(String(view["speed"]))
	if String(view["speed"]) != "flat out" or absf(float(view["speedo"]) - 1.0) > 1e-9:
		push_error("DASH: sixty ticks of throttle read '%s' at needle %.2f" % [view["speed"], float(view["speedo"])])
		return false
	if words.size() < 3:
		push_error("DASH: the speed word passed through only %s on the way to flat out" % str(words))
		return false
	if float(view["gauge"]) >= 1.0:
		push_error("DASH: the fuel needle did not move off full after sixty ticks of driving")
		return false
	if absf(float(view["gauge"]) - float(v["fuel"]) / tank) > 1e-9:
		push_error("DASH: the fuel needle %.4f is not the tank's fraction %.4f" % [float(view["gauge"]), float(v["fuel"]) / tank])
		return false
	# Foot off: neutral while rolling, then park at rest.
	w.commands.push({"type": "wait"})
	w.step()
	view = SimVehicles.dash_view(w, w.player)
	if String(view["gear"]) != "neutral" or bool(view["throttle"]) or String(view["speed"]) == "stopped":
		push_error("DASH: coasting reads %s" % str(view))
		return false
	for i in 80:
		w.step()
	view = SimVehicles.dash_view(w, w.player)
	if String(view["gear"]) != "park" or String(view["speed"]) != "stopped":
		push_error("DASH: at rest after coasting the dash reads %s" % str(view))
		return false
	# The brake lamp: the opposite key while rolling, and off once stopped.
	_move(w, 0.0, -1.0, 30)
	w.commands.push({"type": "move", "dx": 0.0, "dy": 1.0})
	w.step()
	view = SimVehicles.dash_view(w, w.player)
	if not bool(view["braking"]) or String(view["gear"]) != "neutral" or not String(view["prose"]).contains("braking"):
		push_error("DASH: braking from speed reads %s" % str(view))
		return false
	for i in 60:
		w.step()
	view = SimVehicles.dash_view(w, w.player)
	if bool(view["braking"]) and float(v["speed"]) == 0.0:
		push_error("DASH: the brake lamp stayed on at rest")
		return false
	# The engine lamp: off sound, on battered, red on a wreck; a dry tank reads as such.
	w.commands.push({"type": "wait"})
	for i in 80:
		w.step()
	v["integrity"] = 45.0
	view = SimVehicles.dash_view(w, w.player)
	if not bool(view["warning"]) or String(view["engine"]) != "battered":
		push_error("DASH: a battered engine reads %s" % str(view))
		return false
	v["integrity"] = 0.0
	view = SimVehicles.dash_view(w, w.player)
	if String(view["engine"]) != "wrecked" or bool(view["running"]) or not String(view["prose"]).contains("wrecked"):
		push_error("DASH: a wreck reads %s" % str(view))
		return false
	v["integrity"] = 100.0
	v["fuel"] = 0.0
	view = SimVehicles.dash_view(w, w.player)
	if bool(view["running"]) or float(view["gauge"]) != 0.0 or String(view["fuel"]) != "dry" or not String(view["prose"]).contains("dry"):
		push_error("DASH: a dry tank reads %s" % str(view))
		return false
	# The allowlist can say no.
	var leaked: Dictionary = view.duplicate()
	leaked["kph"] = 32.0
	if _dash_problem(leaked).is_empty():
		push_error("DASH: a numeric kph fabricated into the view passed the allowlist")
		return false
	var leaked2: Dictionary = view.duplicate()
	leaked2["speed"] = "32 km/h"
	if _dash_problem(leaked2).is_empty():
		push_error("DASH: a speed word with digits passed the allowlist")
		return false
	var leaked3: Dictionary = view.duplicate()
	leaked3["speedo"] = 1.5
	if _dash_problem(leaked3).is_empty():
		push_error("DASH: a needle past the end of its dial passed the allowlist")
		return false
	# The screen: main.gd stands the dashboard and feeds it, and dashboard.gd draws no digit.
	if _string_literal_digit("draw_string(f, p, \"32 km/h\")").is_empty():
		push_error("DASH: the literal scanner passed a string with a digit in it; it cannot say no")
		return false
	if not _string_literal_digit("draw_string(f, p, \"flat out\") + 32.0; Color(\"#1b1a17\")").is_empty():
		push_error("DASH: the literal scanner blamed a number outside a string, or a colour code; it cannot say yes")
		return false
	var dash_code: String = _code_of(DASH_GD)
	if dash_code.is_empty():
		push_error("DASH: could not read %s" % DASH_GD)
		return false
	var digit_literal: String = _string_literal_digit(dash_code)
	if not digit_literal.is_empty():
		push_error("DASH: %s draws a string with a digit in it: %s" % [DASH_GD, digit_literal])
		return false
	# `_draw` dispatches on the view's layout word and each layout draws its own instruments; the
	# needles are read in the layout bodies, so those are what is scanned.
	var draw_body: String = _function_body(DASH_GD, "_draw")
	if _missing_needle(draw_body, ["\"layout\"", "_draw_cluster(", "_draw_handlebar(", "_draw_board("]) != "":
		push_error("DASH: dashboard.gd's _draw does not dispatch on the layout to all three drawings")
		return false
	var cluster_body: String = _function_body(DASH_GD, "_draw_cluster")
	var missing: String = _missing_needle(cluster_body, ["_dial(", "\"gear\"", "\"braking\"", "\"prose\"", "_engine_colour("])
	if not missing.is_empty():
		push_error("DASH: dashboard.gd's _draw_cluster never reads %s" % missing)
		return false
	if _missing_needle(_function_body(DASH_GD, "_engine_colour"), ["\"engine\"", "\"warning\""]) != "":
		push_error("DASH: the engine lamp reads neither the engine word nor the warning")
		return false
	var handlebar_body: String = _function_body(DASH_GD, "_draw_handlebar")
	missing = _missing_needle(handlebar_body, ["_dial(", "\"motion\"", "\"braking\"", "\"powered\"", "\"gauge\"", "\"prose\""])
	if not missing.is_empty():
		push_error("DASH: dashboard.gd's _draw_handlebar never reads %s" % missing)
		return false
	if handlebar_body.contains("\"P\"") or handlebar_body.contains("\"D\""):
		push_error("DASH: the handlebar layout draws a car's gear letters; a bicycle has no P N D")
		return false
	var board_body: String = _function_body(DASH_GD, "_draw_board")
	missing = _missing_needle(board_body, ["\"motion\"", "\"speedo\"", "\"braking\"", "\"prose\""])
	if not missing.is_empty():
		push_error("DASH: dashboard.gd's _draw_board never reads %s" % missing)
		return false
	if board_body.contains("_dial(") or board_body.contains("\"gauge\""):
		push_error("DASH: the board layout draws a dial or a gauge; a skateboard has neither")
		return false
	var dial_body: String = _function_body(DASH_GD, "_dial")
	if _missing_needle(dial_body, ["draw_arc(", "draw_line("]) != "":
		push_error("DASH: the dial draws no arc or needle")
		return false
	var ensure: String = _function_body(MAIN_GD, "_ensure_ui")
	if not ensure.contains("res://ui/dashboard.gd"):
		push_error("DASH: main.gd never stands the dashboard")
		return false
	var hud_body: String = _function_body(MAIN_GD, "_update_hud")
	if _missing_needle(hud_body, ["SimVehicles.dash_view(", "_dashboard"]) != "":
		push_error("DASH: main.gd's _update_hud never feeds the dashboard the seat's view")
		return false
	print("DASH OK off the wheel nothing; stopped it reads park and stopped with the needle at zero and the gauge full; under throttle it reads drive with the needle climbing through %s to flat out and the gauge off full at the tank's fraction; foot off reads neutral then park; the brake lamp lights on the opposite key; the engine lamp on battered and red on a wreck; a dry tank reads dry; a numeric kph, a speed with digits and a needle past its dial are all caught; dashboard.gd draws no digit and main.gd feeds it every refresh" % str(words))
	return true


# --- 12. SHELTER ---------------------------------------------------------------------------

func _a_driver_is_off_the_menu(stash: Dictionary) -> bool:
	var w: Variant = _hand_world()
	var listed: bool = false
	for s in SimShambler._gather_survivors(w):
		if int((s as Dictionary)["entity"]) == int(w.player):
			listed = true
	if not listed:
		push_error("SHELTER: a body on foot is not on the shambler's menu; the positive has nothing to judge")
		return false
	_toggle(w)
	if not w.components.has_component(w.player, "mounted"):
		push_error("SHELTER: could not mount")
		return false
	for s in SimShambler._gather_survivors(w):
		if int((s as Dictionary)["entity"]) == int(w.player):
			push_error("SHELTER: a body at the wheel is on the shambler's menu")
			return false
	_toggle(w)
	var back: bool = false
	for s in SimShambler._gather_survivors(w):
		if int((s as Dictionary)["entity"]) == int(w.player):
			back = true
	if not back:
		push_error("SHELTER: out of the car and still not on the menu")
		return false
	# The true negative of the shelter: a rider on a bicycle is still on the menu, because the
	# shelter is the cab and a bicycle has none -- `mounted.cab` says so and the gather reads it.
	var b: Variant = _hand_world(_bicycle_record())
	_toggle(b)
	var bm: Variant = b.components.get_component(b.player, "mounted")
	if not (bm is Dictionary) or bool((bm as Dictionary).get("cab", true)):
		push_error("SHELTER: could not get on the bicycle, or its mount claims a cab: %s" % str(bm))
		return false
	var riding: bool = false
	for s in SimShambler._gather_survivors(b):
		if int((s as Dictionary)["entity"]) == int(b.player):
			riding = true
	if not riding:
		push_error("SHELTER: a rider on a bicycle is off the shambler's menu; a bicycle is not a shelter")
		return false
	# And the gather reads the mount's own word: a bicycle whose mount lies about a cab is spared,
	# which is the dead-socket assertion that the boolean is what the shambler asks.
	(bm as Dictionary)["cab"] = true
	for s in SimShambler._gather_survivors(b):
		if int((s as Dictionary)["entity"]) == int(b.player):
			push_error("SHELTER: the gather does not read mounted.cab; it would shelter or expose every vehicle alike")
			return false
	(bm as Dictionary)["cab"] = false
	print("SHELTER OK the player is gathered on foot, not at the wheel, and again once out; a rider on a bicycle is gathered, and the gather reads mounted.cab")
	return true


# --- 12b. LIGHT ----------------------------------------------------------------------------

# Whether the bus carried a `vehicle.unseated` for `why` this tick.
func _unseated_for(w: Variant, why: String) -> bool:
	for ev in w.events.drained as Array:
		if String((ev as Dictionary).get("type", "")) == "vehicle.unseated" and String((ev as Dictionary).get("why", "")) == why:
			return true
	return false


func _the_light_vehicles_ride(stash: Dictionary) -> bool:
	var sprint: float = 6.3
	# --- the bicycle: no tank, rides at its own top, quieter than a sprint, drawn on -------
	var b: Variant = _hand_world(_bicycle_record())
	var bike: int = _car_of(b)
	var bv: Dictionary = _v(b, bike)
	var bdrive: Dictionary = SimVehicles.drive_of(SimVehicles.class_of(b, "vehicle.bicycle"))
	if SimVehicles.power_of(bdrive) != SimVehicles.POWER_MUSCLE or float(bdrive["tank"]) != 0.0:
		push_error("LIGHT: the bicycle is not a muscle class with no tank: %s" % str(bdrive))
		return false
	if SimVehicles.motor_runs(bv, bdrive) or not SimVehicles.can_ride(bv, bdrive):
		push_error("LIGHT: a sound bicycle has a motor running, or cannot be ridden")
		return false
	var beside: String = SimVehicles.hud_clause(b, b.player)
	if not beside.contains("bicycle") or not beside.contains("get on") or beside.contains("get in"):
		push_error("LIGHT: beside a bicycle the HUD says '%s'" % beside)
		return false
	_toggle(b)
	var bm: Variant = b.components.get_component(b.player, "mounted")
	if not (bm is Dictionary) or bool((bm as Dictionary).get("cab", true)):
		push_error("LIGHT: could not get on the bicycle, or the mount claims a cab (%s)" % SimVehicles.mount_problem(b, b.player, bike))
		return false
	var em: Variant = b.components.get_component(bike, "attention_emitter")
	if not (em is Dictionary) or float((em as Dictionary)["walking"]) != float(bdrive["noise"]) or float((em as Dictionary)["ambient"]) != 0.0:
		push_error("LIGHT: a ridden bicycle's emitter reads %s; wanted the tyres at %.1f and no idle" % [str(em), float(bdrive["noise"])])
		return false
	if float((em as Dictionary)["walking"]) > sprint:
		push_error("LIGHT: a bicycle is louder than a sprint")
		return false
	var saddle: String = SimVehicles.hud_clause(b, b.player)
	if not saddle.contains("saddle") or not saddle.contains("get off"):
		push_error("LIGHT: in the saddle the HUD says '%s'" % saddle)
		return false
	var peak: float = 0.0
	var seen_motion: Dictionary = {}
	b.commands.push({"type": "move", "dx": 0.0, "dy": -1.0})
	for i in 80:
		b.step()
		peak = maxf(peak, float(bv["speed"]))
		var dv: Dictionary = SimVehicles.dash_view(b, b.player)
		var problem: String = _dash_problem(dv)
		if not problem.is_empty():
			push_error("LIGHT: the bicycle's dash: %s in %s" % [problem, str(dv)])
			return false
		if String(dv["layout"]) != "handlebar" or bool(dv["powered"]) or float(dv["gauge"]) != 0.0 or String(dv["fuel"]) != SimVehicles.NO_TANK_WORD:
			push_error("LIGHT: pedalling, the bicycle's dash reads %s" % str(dv))
			return false
		seen_motion[String(dv["motion"])] = true
	if absf(peak - float(bdrive["speed"])) > 1e-6:
		push_error("LIGHT: eighty ticks of pedalling peaked at %.2f against the bicycle's %.2f" % [peak, float(bdrive["speed"])])
		return false
	if peak <= sprint:
		push_error("LIGHT: the bicycle (%.1f) does not outrun a sprint (%.1f)" % [peak, sprint])
		return false
	if not seen_motion.has("pedalling") or seen_motion.has("in drive"):
		push_error("LIGHT: the bicycle's motion words were %s; a bicycle pedals, it is never in drive" % str(seen_motion.keys()))
		return false
	if float(bv["fuel"]) != 0.0:
		push_error("LIGHT: a bicycle burned or gained fuel: %.3f" % float(bv["fuel"]))
		return false
	var riding: String = SimVehicles.hud_clause(b, b.player)
	if not riding.begins_with("riding the bicycle") or not riding.contains("get off"):
		push_error("LIGHT: under way the HUD says '%s'" % riding)
		return false
	b.commands.push({"type": "wait"})
	b.step()
	if String(SimVehicles.dash_view(b, b.player)["motion"]) != "coasting":
		push_error("LIGHT: foot off, the bicycle reads %s" % str(SimVehicles.dash_view(b, b.player)))
		return false
	for i in 80:
		b.step()
	if String(SimVehicles.dash_view(b, b.player)["motion"]) != "stopped" or float(bv["speed"]) != 0.0:
		push_error("LIGHT: at rest the bicycle reads %s" % str(SimVehicles.dash_view(b, b.player)))
		return false
	# A wrecked bicycle goes nowhere, muscle or not.
	bv["integrity"] = 0.0
	_move(b, 0.0, -1.0, 20)
	if float(bv["speed"]) != 0.0:
		push_error("LIGHT: a wrecked bicycle moved")
		return false
	if not SimVehicles.hud_clause(b, b.player).contains("frame is wrecked"):
		push_error("LIGHT: on a wrecked bicycle the HUD says '%s'" % SimVehicles.hud_clause(b, b.player))
		return false
	bv["integrity"] = SimVehicles.INTEGRITY_MAX
	stash["bicycle_top"] = peak
	# The sedan is faster than the bicycle and the skateboard slower than a sprint: the spread
	# the goal asked for, read off content and held here so a rebalance that flattens it says so.
	var sedan_top: float = float(SimVehicles.drive_of(SimVehicles.class_of(b, "vehicle.sedan"))["speed"])
	var board_top: float = float(SimVehicles.drive_of(SimVehicles.class_of(b, "vehicle.skateboard"))["speed"])
	if not (sedan_top > peak and peak > sprint and sprint > board_top and board_top > 2.1):
		push_error("LIGHT: the speeds do not spread: sedan %.1f, bicycle %.1f, sprint %.1f, skateboard %.1f, walk 2.1" % [sedan_top, peak, sprint, board_top])
		return false

	# --- a grab puts the rider off; a car's driver stays in ------------------------------------
	b.components.set_component(b.player, "grabbed", {"sources": [], "struggleTicks": 0, "heldTicks": 0})
	b.step()
	if b.components.has_component(b.player, "mounted") or int(bv["driver"]) != SimVehicles.NO_DRIVER or not _unseated_for(b, "grabbed"):
		push_error("LIGHT: a grabbed rider stayed in the saddle (mounted %s, driver %d)" % [str(b.components.has_component(b.player, "mounted")), int(bv["driver"])])
		return false
	if b.components.has_component(bike, "velocity"):
		push_error("LIGHT: an unseated bicycle kept its engine components")
		return false
	b.components.remove(b.player, "grabbed")
	var c: Variant = _hand_world()
	var car: int = _car_of(c)
	_toggle(c)
	c.components.set_component(c.player, "grabbed", {"sources": [], "struggleTicks": 0, "heldTicks": 0})
	c.step()
	if not c.components.has_component(c.player, "mounted") or _unseated_for(c, "grabbed"):
		push_error("LIGHT: a grab reached a driver through the car door and unseated them")
		return false
	c.components.remove(c.player, "grabbed")

	# --- a crash at speed throws the rider; the driver keeps the seat ---------------------------
	var b2: Variant = _hand_world(_bicycle_record())
	var bike2: int = _car_of(b2)
	var bv2: Dictionary = _v(b2, bike2)
	_wall(b2, CAR_X, CAR_Y - 6)
	_toggle(b2)
	b2.commands.push({"type": "move", "dx": 0.0, "dy": -1.0})
	var crashed_at: float = -1.0
	for i in 120:
		var before_speed: float = float(bv2["speed"])
		b2.step()
		if _unseated_for(b2, "crashed"):
			crashed_at = before_speed
			break
	if crashed_at < SimVehicles.CRASH_MIN_SPEED:
		push_error("LIGHT: a bicycle ridden at a wall did not throw its rider (unseated at speed %.2f)" % crashed_at)
		return false
	if b2.components.has_component(b2.player, "mounted") or float(bv2["integrity"]) >= SimVehicles.INTEGRITY_MAX:
		push_error("LIGHT: after the crash the rider is still on (%s) or the frame is unmarked (%.1f)" % [str(b2.components.has_component(b2.player, "mounted")), float(bv2["integrity"])])
		return false
	var c2: Variant = _hand_world()
	var car2: int = _car_of(c2)
	_wall(c2, CAR_X, CAR_Y - 8)
	_wall(c2, CAR_X + 1, CAR_Y - 8)
	_toggle(c2)
	var car_crashed: bool = false
	c2.commands.push({"type": "move", "dx": 0.0, "dy": -1.0})
	for i in 120:
		c2.step()
		for ev in c2.events.drained as Array:
			if String((ev as Dictionary).get("type", "")) == "vehicle.crashed":
				car_crashed = true
		if car_crashed:
			break
	if not car_crashed:
		push_error("LIGHT: the sedan never crashed; the negative has nothing to judge")
		return false
	if not c2.components.has_component(c2.player, "mounted") or _unseated_for(c2, "crashed"):
		push_error("LIGHT: a crash threw the driver out of a car; a car has a windscreen")
		return false

	# --- the e-bike: under power to its top, flat to its unpowered speed, the charge in words -----
	var e: Variant = _hand_world(_light_record("ebike", 2))
	var ebike: int = _car_of(e)
	var ev2: Dictionary = _v(e, ebike)
	var edrive: Dictionary = SimVehicles.drive_of(SimVehicles.class_of(e, "vehicle.ebike"))
	if SimVehicles.power_of(edrive) != SimVehicles.POWER_BATTERY or float(edrive["unpowered"]) <= 0.0:
		push_error("LIGHT: the e-bike is not a battery class with an unpowered speed: %s" % str(edrive))
		return false
	var full: float = float(ev2["fuel"])
	if full != float(edrive["tank"]):
		push_error("LIGHT: the hand e-bike is not on a full charge")
		return false
	var hood: Dictionary = SimVehicles.hood_view(e, ebike)
	if String(hood["fuel"]) != "full" or not String(hood["prose"]).begins_with("looking the electric bike over"):
		push_error("LIGHT: the e-bike's hood view reads %s" % str(hood))
		return false
	_toggle(e)
	var epeak: float = 0.0
	var powered_word: bool = false
	# Sixty ticks is exactly the run to the e-bike's top at its accel, and keeps the flat run
	# after it a dozen tiles short of the map's north edge -- the first cut ran it into the edge
	# and read a crash as a flat battery.
	e.commands.push({"type": "move", "dx": 0.0, "dy": -1.0})
	for i in 60:
		e.step()
		epeak = maxf(epeak, float(ev2["speed"]))
		var dv2: Dictionary = SimVehicles.dash_view(e, e.player)
		if not _dash_problem(dv2).is_empty():
			push_error("LIGHT: the e-bike's dash: %s" % _dash_problem(dv2))
			return false
		if String(dv2["motion"]) == SimVehicles.MOTION_POWERED:
			powered_word = true
		if not bool(dv2["powered"]) or String(dv2["layout"]) != "handlebar":
			push_error("LIGHT: under power the e-bike's dash reads %s" % str(dv2))
			return false
	if absf(epeak - float(edrive["speed"])) > 1e-6 or not powered_word:
		push_error("LIGHT: sixty ticks under power peaked at %.2f (top %.2f), powered word %s" % [epeak, float(edrive["speed"]), str(powered_word)])
		return false
	if float(ev2["fuel"]) >= full:
		push_error("LIGHT: sixty ticks under power spent no charge")
		return false
	var spent: float = full - float(ev2["fuel"])
	# Flat: the rider pedals on at the unpowered speed, the words say so, no charge moves.
	ev2["fuel"] = 0.0
	for i in 50:
		e.step()
	var flat_speed: float = float(ev2["speed"])
	if absf(flat_speed - float(edrive["unpowered"])) > 1e-6:
		push_error("LIGHT: with the battery flat the e-bike rides at %.2f, not its unpowered %.2f" % [flat_speed, float(edrive["unpowered"])])
		return false
	var flat: Dictionary = SimVehicles.dash_view(e, e.player)
	if String(flat["motion"]) != "pedalling" or String(flat["fuel"]) != SimVehicles.CHARGE_WORDS[0] or not bool(flat["running"]) or float(flat["gauge"]) != 0.0 or not String(flat["prose"]).contains("flat"):
		push_error("LIGHT: with the battery flat the e-bike's dash reads %s" % str(flat))
		return false
	if float(flat["speedo"]) >= 1.0 or float(flat["speedo"]) <= 0.0:
		push_error("LIGHT: a flat e-bike pedalled at its unpowered speed reads a needle of %.2f; the dial is the class's top" % float(flat["speedo"]))
		return false
	var eem: Dictionary = e.components.get_component(ebike, "attention_emitter") as Dictionary
	if float(eem["walking"]) != float(edrive["noise"]):
		push_error("LIGHT: a flat e-bike under way is silent; the tyres still roll")
		return false
	if float(ev2["fuel"]) != 0.0:
		push_error("LIGHT: a flat battery moved")
		return false
	e.commands.push({"type": "wait"})
	for i in 100:
		e.step()
	if not SimVehicles.hud_clause(e, e.player).contains("battery is flat"):
		push_error("LIGHT: on a flat e-bike the HUD says '%s'" % SimVehicles.hud_clause(e, e.player))
		return false
	if SimVehicles.hood_view(e, ebike)["fuel"] != SimVehicles.CHARGE_WORDS[0]:
		push_error("LIGHT: a flat e-bike's hood reads %s" % str(SimVehicles.hood_view(e, ebike)))
		return false
	for word in SimVehicles.CHARGE_WORDS:
		if _has_digit(String(word)):
			push_error("LIGHT: a charge word carries a digit: '%s'" % String(word))
			return false
	if SimVehicles.charge_word(full * 0.5, full) != "about half a charge":
		push_error("LIGHT: half a charge reads '%s'" % SimVehicles.charge_word(full * 0.5, full))
		return false
	stash["ebike_flat"] = flat_speed

	# --- the skateboard: a board's strip, a foot down, turns on its own tile -------------------
	var k: Variant = _hand_world(_light_record("skateboard", 1))
	var board: int = _car_of(k)
	var kv: Dictionary = _v(k, board)
	var kp: Dictionary = _pos(k, k.player)
	kp["x"] = float(CAR_X - 1) + 0.5
	kp["y"] = float(CAR_Y) + 0.5
	if not SimVehicles.hud_clause(k, k.player).contains("skateboard"):
		push_error("LIGHT: beside a skateboard the HUD says '%s'" % SimVehicles.hud_clause(k, k.player))
		return false
	_toggle(k)
	if not k.components.has_component(k.player, "mounted"):
		push_error("LIGHT: could not get on the skateboard (%s)" % SimVehicles.mount_problem(k, k.player, board))
		return false
	if not SimVehicles.hud_clause(k, k.player).begins_with("standing on the skateboard"):
		push_error("LIGHT: on the skateboard the HUD says '%s'" % SimVehicles.hud_clause(k, k.player))
		return false
	_move(k, 0.0, -1.0, 40)
	var kd: Dictionary = SimVehicles.dash_view(k, k.player)
	if not _dash_problem(kd).is_empty() or String(kd["layout"]) != "board" or String(kd["motion"]) != "pushing" or bool(kd["powered"]):
		push_error("LIGHT: pushing, the skateboard's dash reads %s (%s)" % [str(kd), _dash_problem(kd)])
		return false
	if float(kv["speed"]) > sprint:
		push_error("LIGHT: a skateboard outruns a sprint")
		return false
	k.commands.push({"type": "move", "dx": 0.0, "dy": 1.0})
	k.step()
	kd = SimVehicles.dash_view(k, k.player)
	if not bool(kd["braking"]) or not String(kd["prose"]).contains("a foot down") or String(kd["prose"]).contains("braking"):
		push_error("LIGHT: a foot dragged on the skateboard reads %s" % str(kd))
		return false
	# The opposite key brakes, turns the board round and then rides it south; foot off and let
	# it roll to a stop before asking for east, which is a turn about its one tile.
	k.commands.push({"type": "wait"})
	for i in 100:
		k.step()
	if float(kv["speed"]) != 0.0:
		push_error("LIGHT: the skateboard did not roll to a stop in a hundred ticks")
		return false
	var before_turn: Rect2i = SimVehicles.footprint(kv, _pos(k, board))
	_move(k, 1.0, 0.0, 1)
	var after_turn: Rect2i = SimVehicles.footprint(kv, _pos(k, board))
	if String(kv["heading"]) != "e" or after_turn.size != Vector2i(1, 1) or not before_turn.grow(1).intersects(after_turn):
		push_error("LIGHT: a stopped skateboard asked east reads heading %s on %s (was %s); a 1x1 turns on its own tile" % [String(kv["heading"]), str(after_turn), str(before_turn)])
		return false

	# --- the words: three layouts, three motion words each, no digit; an unknown dash is a board --
	for layout in SimVehicles.DASH_LAYOUTS:
		var words: Array = SimVehicles.MOTION_WORDS[layout] as Array
		if words.size() != SimVehicles.GEARS.size():
			push_error("LIGHT: layout %s has %d motion words for %d gears" % [layout, words.size(), SimVehicles.GEARS.size()])
			return false
		for word in words:
			if _has_digit(String(word)):
				push_error("LIGHT: a motion word carries a digit: '%s'" % String(word))
				return false
	if SimVehicles.dash_layout({"dash": "cockpit"}) != "board" or SimVehicles.dash_layout({}) != "board" or SimVehicles.dash_layout({"dash": "cluster"}) != "cluster":
		push_error("LIGHT: dash_layout does not fall to the board on a word nobody drew")
		return false
	if SimVehicles.has_cab({}) or not SimVehicles.has_cab({"cab": true}):
		push_error("LIGHT: has_cab defaults to sheltered, or refuses a declared cab")
		return false

	# --- the street: the suburb at 128 parks light classes one tile wide, kerb free, no boot on them --
	var tree: Dictionary = ContentLoader.load_tree()
	var map: Variant = SimWorldgen.generate(CANON_SEED, PARK_SIZE, tree)
	var light: int = 0
	var narrow_tiles: Dictionary = {}
	for rec in map.vehicles as Array:
		var r: Dictionary = rec as Dictionary
		if mini(int(r["w"]), int(r["h"])) != 1:
			continue
		light += 1
		for dy in int(r["h"]):
			for dx in int(r["w"]):
				narrow_tiles[(int(r["y"]) + dy) * int(map.w) + int(r["x"]) + dx] = true
	if light == 0:
		push_error("LIGHT: the suburb at %d parked no light vehicle on seed %d; the pass never reaches them" % [PARK_SIZE, CANON_SEED])
		return false
	for tail in SimWorldgen._vehicle_tails(map) as Array:
		if narrow_tiles.has(int(tail)):
			push_error("LIGHT: a car-boot tail stands on a one-wide vehicle at tile %d" % int(tail))
			return false
	# The tails scanner has to be able to say yes on a car, or the line above judges nothing.
	if (SimWorldgen._vehicle_tails(map) as Array).is_empty():
		push_error("LIGHT: no car tail at all at %d; the boot-on-a-bicycle assertion judged nothing" % PARK_SIZE)
		return false
	stash["light_parked"] = light
	print("LIGHT OK the bicycle rides at %.1f (a sprint is %.1f, a sedan %.1f, a skateboard %.1f) with no tank, its tyres at %.1f and no idle, pedalling then coasting then stopped, and a wreck goes nowhere; a grab and a crash at %.1f m/s put the rider off and neither reaches a car's driver; the e-bike peaks at %.1f under power, spends %.2f of its charge, and flat rides at %.1f pedalling with the needle part-way up the same dial; the skateboard pushes, drags a foot and turns on its own tile; three layouts, nine motion words, no digit, an unknown dash is a board; suburb@%d parks %d light vehicles and hosts no boot on any" % [
		peak, sprint, sedan_top, board_top, float(bdrive["noise"]), crashed_at, epeak, spent, flat_speed, PARK_SIZE, light,
	])
	return true


# --- 13. SAVE -------------------------------------------------------------------------------

func _a_driven_car_survives_a_save(stash: Dictionary) -> bool:
	var a: Variant = _hand_world()
	var car: int = _car_of(a)
	_toggle(a)
	_move(a, 0.0, -1.0, 40)
	_move(a, 1.0, 0.0, 80)
	var ap: Dictionary = _pos(a, car)
	var av: Dictionary = _v(a, car)
	var arec: Dictionary = _record_of(a.tilemap, car)
	if int(arec["y"]) >= CAR_Y or String(av["heading"]) != "e":
		push_error("SAVE: the car did not drive off and turn east before the save (%s, heading %s)" % [str(arec), av["heading"]])
		return false
	var snap: Dictionary = a.snapshot()
	# A second world with the car parked where the layout put it, restored from the first.
	var b: Variant = _hand_world()
	var brec_before: Dictionary = _record_of(b.tilemap, car)
	if int(brec_before["y"]) != CAR_Y:
		push_error("SAVE: the second world's car is not at the kerb before the restore")
		return false
	b.restore(snap)
	if not b.components.has_component(car, "vehicle"):
		push_error("SAVE: the restored world has no vehicle entity %d" % car)
		return false
	var bp: Dictionary = _pos(b, car)
	var bv: Dictionary = _v(b, car)
	if absf(float(bp["x"]) - float(ap["x"])) > 1e-9 or absf(float(bp["y"]) - float(ap["y"])) > 1e-9:
		push_error("SAVE: restored at (%.3f, %.3f), driven to (%.3f, %.3f)" % [bp["x"], bp["y"], ap["x"], ap["y"]])
		return false
	if String(bv["heading"]) != String(av["heading"]) or int(bv["driver"]) != int(av["driver"]):
		push_error("SAVE: restored heading/driver %s/%d against %s/%d" % [bv["heading"], int(bv["driver"]), av["heading"], int(av["driver"])])
		return false
	if float(av["fuel"]) >= float(SimVehicles.drive_of(SimVehicles.class_of(a, "vehicle.sedan"))["tank"]):
		push_error("SAVE: the drive burned no fuel, so the restored litres would prove nothing")
		return false
	if absf(float(bv["fuel"]) - float(av["fuel"])) > 1e-9 or absf(float(bv["integrity"]) - float(av["integrity"])) > 1e-9:
		push_error("SAVE: restored fuel/integrity %.4f/%.1f against %.4f/%.1f" % [bv["fuel"], bv["integrity"], av["fuel"], av["integrity"]])
		return false
	if not b.components.has_component(b.player, "mounted"):
		push_error("SAVE: the driver came back on foot")
		return false
	var brec: Dictionary = _record_of(b.tilemap, car)
	for k in ["x", "y", "w", "h", "axis", "class", "facing", "hx", "hy", "entity"]:
		if str(brec.get(k)) != str(arec.get(k)):
			push_error("SAVE: the restored record differs on %s: %s vs %s" % [k, str(brec), str(arec)])
			return false
	var problem: String = _low_matches(b.tilemap, brec)
	if not problem.is_empty():
		push_error("SAVE: the restored map's Low tiles: %s" % problem)
		return false
	if SimTileMap.tile_at(b.tilemap, CAR_X, CAR_Y) == SimTileMap.Tile.Low:
		push_error("SAVE: the kerb the layout parked on is still Low after the restore; the old shadow was not cleared")
		return false
	# And it drives on from there: the restored world and the original agree tick for tick.
	_move(a, 1.0, 0.0, 20)
	_move(b, 1.0, 0.0, 20)
	if absf(float(_pos(a, car)["x"]) - float(_pos(b, car)["x"])) > 1e-9:
		push_error("SAVE: twenty ticks after the restore the two worlds' cars are at x %.4f and %.4f" % [_pos(a, car)["x"], _pos(b, car)["x"]])
		return false
	print("SAVE OK a car driven %d tiles north and turned east restores at (%.2f, %.2f) heading east with its driver in, its record and Low tiles matching, the kerb cleared, and drives on in step with the original" % [CAR_Y - int(arec["y"]), bp["x"], bp["y"]])
	return true


# --- 14. SOCKETS ----------------------------------------------------------------------------

func _missing_needle(body: String, needles: Array) -> String:
	for needle in needles:
		if not body.contains(String(needle)):
			return String(needle)
	return ""


func _the_sockets_are_wired() -> bool:
	if _missing_needle("func nothing() -> void:\n\tpass\n", ["sync_map("]) != "sync_map(":
		push_error("SOCKETS: the needle scanner found nothing missing in a body missing everything; it cannot say no")
		return false
	if not _missing_needle("SimVehiclesRes.sync_map(self)", ["sync_map("]).is_empty():
		push_error("SOCKETS: the needle scanner called a present needle missing; it cannot say yes")
		return false
	var checks: Array = [
		[WORLD_GD, "_integrate_movement", ["has_component(int(entity), \"vehicle\")"], "world's integrate would move a car by its two body corners as well as the module moving it"],
		[WORLD_GD, "restore", ["SimVehiclesRes.sync_map(self)"], "a restored car would stand on the kerb's Low tiles with its picture where it was driven"],
		[BOOT_GD, "register_playable_modules", ["SimVehicles.register_module(world)"], "the toggle and the drive would run in no world"],
		[BOOT_GD, "playable", ["SimVehicles.spawn_from_manifest(world, map)"], "no record would ever become an entity"],
		[SHAMBLER_GD, "_gather_survivors", ["\"mounted\"", "\"cab\""], "a driver would be chased and grabbed through the door, or a rider sheltered by a bicycle"],
		[FORTIFY_GD, "_use_context", ["SimVehicles.dismount(", "SimVehicles.mount(", "SimVehicles.nearest_in_reach(", "SimVehicles.at_hood(", "SimVehicles.check_hood("], "E would never open a car door or a hood"],
		[MAIN_GD, "_input", ["\"use.context\""], "no key would push the context command"],
		[MAIN_GD, "_draw_entities", ["\"mounted\"", "\"cab\"", "SimVehicles.ground_point("], "the driver's pawn would draw on the bonnet, or a rider would vanish off a bicycle"],
		[WORLDGEN_GD, "_vehicle_tails", ["mini(cw, ch) < 2"], "a car-boot site could stand on a bicycle"],
		[WORLDGEN_GD, "_vehicles", ["width - 1 - breadth"], "a one-wide class would park in a two-wide lane"],
		[MAIN_GD, "_vehicle_index", ["vehicle_generation"], "the tile index would go stale the moment a car moved"],
		[MAIN_GD, "_update_hud", ["SimVehicles.hud_clause("], "the HUD would never say a car is beside you"],
		[DRESSING_GD, "vehicle_key", ["\"hx\"", "\"hy\""], "a car would change colour every tile it drove"],
		[DRESSING_GD, "vehicle_ground_point", ["\"gx\"", "\"gy\""], "the picture would snap tile to tile"],
	]
	for check in checks:
		var body: String = _function_body(String(check[0]), String(check[1]))
		if body.is_empty():
			push_error("SOCKETS: could not read %s out of %s" % [check[1], check[0]])
			return false
		var missing: String = _missing_needle(body, check[2] as Array)
		if not missing.is_empty():
			push_error("SOCKETS: %s::%s does not contain %s; %s" % [check[0], check[1], missing, check[3]])
			return false
	print("SOCKETS OK world skips the vehicle component and re-syncs the shadow on restore; boot registers the module and spawns from the manifest; the shambler's gather skips a mounted cab; main draws a rider on an open vehicle; worldgen parks a one-wide body in a one-wide lane and hosts no boot on it; fortify's E ladder mounts and dismounts; main.gd pushes the context command, skips the mounted body, keys its index on the vehicle generation and reads the HUD clause; dressing hashes paint on the home corner and stands the picture on the live ground point; the scanner was proved on a fabricated string")
	return true


func _the_gate_stayed_inside_its_own_budget(seconds: float) -> bool:
	if seconds > BUDGET_SECONDS:
		push_error("BUDGET: %.1f s over the %.0f s budget" % [seconds, BUDGET_SECONDS])
		return false
	print("BUDGET OK %.1f s of a %.0f s budget" % [seconds, BUDGET_SECONDS])
	return true


# --- text helpers ----------------------------------------------------------------------------

func _code_of(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


# The source text of one function, from its `func` line to the next top-level `func`, comments
# stripped so a needle in a comment does not count as a call.
func _function_body(path: String, name: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var lines: PackedStringArray = f.get_as_text().split("\n")
	var out: String = ""
	var inside: bool = false
	for line in lines:
		if line.begins_with("func %s(" % name) or line.begins_with("static func %s(" % name):
			inside = true
			continue
		if inside and (line.begins_with("func ") or line.begins_with("static func ")):
			break
		if inside:
			var at: int = String(line).find("#")
			out += (String(line) if at < 0 else String(line).substr(0, at)) + "\n"
	return out
