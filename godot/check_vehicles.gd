extends SceneTree
# The parked cars, driven. Slice 10 of the Dungeon Settlers arc made a car a manifest record the
# layout wrote (`map.vehicles`, Tile.Low under it, one picture per axis); this slice makes every
# record an entity at boot and lets the player get in and drive it. `sim/modules/vehicles.gd` is
# the module: `spawn_from_manifest` stands one `vehicle` entity per record, `vehicle.toggle` is
# the command (Q in main.gd) that mounts the car in reach or dismounts, the driver's `move` is the
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
#   SHELTER   a body at the wheel is off the shambler's menu: `_gather_survivors` lists it on
#             foot and not in the car.
#   SAVE      a car driven and saved comes back where it was driven to: the restored world's
#             entity, record, Low tiles and cleared tail all match, in a second world that had
#             the car parked where the layout put it.
#   SOCKETS   textual, every scanner proved on a fabricated string first: world's integrate skips
#             the `vehicle` component and its restore re-syncs the shadow; boot registers the
#             module and spawns from the manifest; the shambler's gather skips `mounted`; main.gd
#             pushes the toggle, skips the mounted body, keys its index on the map's vehicle
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

const CANON_SEED: int = 20260805
const PARK_SIZE: int = 128
const HAND: int = 60
const BUDGET_SECONDS: float = 60.0

const WORLD_GD: String = "res://sim/world.gd"
const BOOT_GD: String = "res://sim/boot.gd"
const SHAMBLER_GD: String = "res://sim/modules/shambler.gd"
const MAIN_GD: String = "res://presentation/main.gd"
const DRESSING_GD: String = "res://presentation/dressing.gd"
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
	ok = _a_driver_is_off_the_menu(stash) and ok
	ok = _a_driven_car_survives_a_save(stash) and ok
	ok = _the_sockets_are_wired() and ok
	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	ok = _the_gate_stayed_inside_its_own_budget(seconds) and ok
	if ok:
		print("M2_VEHICLES_OK %d classes drive; suburb@%d stands %d cars as entities and @64 none; a body gets in, drives to %.1f m/s and no faster, turns, brakes, coasts and gets out; a wall, a car, a heap and a doorway each stop it flush; the field reads %.1f under way, %.1f idling, 0 parked and 0 with the emitter off; a driver is off the shambler's menu; a driven car restores where it was driven; sockets wired; %.1f s of a %.0f s budget" % [
			int(stash.get("classes", 0)), PARK_SIZE, int(stash.get("suburb_cars", 0)),
			float(stash.get("top_speed", 0.0)), float(stash.get("noise_driving", 0.0)), float(stash.get("noise_idle", 0.0)),
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
	var pos: Dictionary = w.components.get_component(w.player, "position") as Dictionary
	pos["x"] = float(CAR_X - 1) + 0.5
	pos["y"] = float(CAR_Y + 2) + 0.5
	return w


func _sedan_record() -> Dictionary:
	return {"x": CAR_X, "y": CAR_Y, "w": 2, "h": 5, "axis": "ns", "class": "vehicle.sedan", "facing": "n"}


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
		if float(drive["speed"]) <= 6.3:
			push_error("CONTENT: %s tops out at %.1f m/s, slower than a sprint (6.3); a car you cannot outrun on foot is not a car" % [id, float(drive["speed"])])
			return false
		if float(drive["noise"]) <= 6.0:
			push_error("CONTENT: %s's engine (%.1f) is no louder than a sprint (6.0)" % [id, float(drive["noise"])])
			return false
	# The negatives: the same reader refuses a block missing a key, a zero speed and a non-number.
	var whole: Dictionary = {"drive": {"speed": 10, "accel": 4, "brake": 8, "noise": 24, "idle": 4}}
	if SimVehicles.drive_of(whole).is_empty():
		push_error("CONTENT: the reader refused a whole block; it cannot say yes")
		return false
	var short: Dictionary = {"drive": {"speed": 10, "accel": 4, "brake": 8, "noise": 24}}
	if not SimVehicles.drive_of(short).is_empty():
		push_error("CONTENT: the reader accepted a block with no idle; a car would drive on a default nothing declared")
		return false
	var still: Dictionary = {"drive": {"speed": 0, "accel": 4, "brake": 8, "noise": 24, "idle": 4}}
	if not SimVehicles.drive_of(still).is_empty():
		push_error("CONTENT: the reader accepted speed 0")
		return false
	var words: Dictionary = {"drive": {"speed": "fast", "accel": 4, "brake": 8, "noise": 24, "idle": 4}}
	if not SimVehicles.drive_of(words).is_empty():
		push_error("CONTENT: the reader accepted a string for a number")
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
	# And a class the world does not declare, or declares without a drive, cannot be mounted:
	# the hand world with a fabricated class that has a footprint and no drive.
	var w: Variant = _hand_world()
	(w.content as Dictionary)["vehicles/zz_fake.json"] = {"id": "vehicle.fake", "name": "Fake", "footprint": {"w": 2, "l": 5}, "appearance": {"variants": []}}
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
	print("CONTENT OK %d classes each declare a whole drive block, faster than a sprint and louder than one; the schema requires it; a block missing idle, a zero speed, a string and no block are refused, and a fabricated class with no drive block cannot be mounted ('%s')" % [classes.size(), problem])
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


# --- 7. SHELTER ----------------------------------------------------------------------------

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
	print("SHELTER OK the player is gathered on foot, not at the wheel, and again once out")
	return true


# --- 8. SAVE -------------------------------------------------------------------------------

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


# --- 9. SOCKETS ----------------------------------------------------------------------------

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
		[SHAMBLER_GD, "_gather_survivors", ["\"mounted\""], "a driver would be chased and grabbed through the door"],
		[MAIN_GD, "_input", ["SimVehicles.TOGGLE"], "no key would push the toggle"],
		[MAIN_GD, "_draw_entities", ["\"mounted\""], "the driver's pawn would draw on the bonnet"],
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
	print("SOCKETS OK world skips the vehicle component and re-syncs the shadow on restore; boot registers the module and spawns from the manifest; the shambler's gather skips mounted; main.gd pushes the toggle, skips the mounted body, keys its index on the vehicle generation and reads the HUD clause; dressing hashes paint on the home corner and stands the picture on the live ground point; the scanner was proved on a fabricated string")
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
