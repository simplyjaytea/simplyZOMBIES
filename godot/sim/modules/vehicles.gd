class_name SimVehicles
extends RefCounted
# The parked cars, driven. Every `map.vehicles` record the layout wrote becomes an entity at boot
# (`spawn_from_manifest`), and from then on the entity is the truth and the record is its shadow:
# `sync_map` rewrites the Tile.Low under the footprint and the manifest record beside it whenever
# the car moves, so every reader that already asks the record -- the tile branch, the loot host,
# the pictures -- keeps asking it and never learns the car can move. A save carries the entity
# (components round-trip, the map does not), and `world.restore` re-syncs the shadow from it, the
# same way `SimFortify.sync_map` puts boards back on windows.
#
# What a car is here, in the sim's terms:
#
#   * a `vehicle` component -- {class, w, l, heading, speed, driver, intent, home}. `w` and `l`
#     are the content footprint (breadth across, length along); `heading` is one of n/s/e/w,
#     because nobody rotates (docs/30, the Dungeon Settlers look) and a car has exactly two
#     pictures; `speed` is metres a second along the heading, never negative -- a car that wants
#     to go the other way brakes to a stop and then turns round; `driver` is the entity at the
#     wheel or NO_DRIVER; `intent` is the last move command the driver gave, kept until replaced,
#     exactly as a body's velocity is; `home` is the corner the layout parked it on, which is what
#     the paint hashes on so a car keeps its colour when it leaves the kerb.
#   * `position` at the footprint's centre, `velocity` for the attention emitter and for
#     `Appearance.moving`, `facing` in radians for whoever reads it.
#   * an `attention_emitter` whose walking and sprinting are both the engine's noise and whose
#     ambient is the idle -- set on mount, cleared on dismount -- so the one emit-movement system
#     that already reads every footstep reads the engine too. Scent 0: a car has no smell it
#     leaves behind, and a trail would be a second channel nothing here earns.
#
# The driver is a body with a `mounted` component. Its position is pinned to the car every tick
# (movement, after the car has moved, before the kernel refreshes vision at 100), its velocity is
# pinned to zero so it emits no footsteps of its own, and `SimShambler._gather_survivors` leaves
# it off the menu: a body inside a car cannot be swiped or grabbed. What it can still do -- swing,
# fire, crouch -- is nothing this module refuses, and docs/23 says so.
#
# Steering is four headings and a `move` intent. The dominant axis of the intent names the wanted
# heading: the same heading accelerates, the opposite one brakes and then turns the car round in
# place (a 180 changes no tile), a perpendicular one brakes to a stop and then tries to turn the
# footprint about its centre, which is refused -- silently, the car just does not turn -- when the
# turned footprint would cover something. No intent coasts to a stop. Collision is the leading
# edge: every across-tile of the footprint is probed one step ahead, and a car that would enter
# a solid tile, an indoor tile, another car, or a heap (a Low tile no record covers) stops flush
# against it. Bodies are not probed: a parked car is walk-through cover today and a moving one
# stays walk-through, so nothing is run over -- named in docs/23 rather than half-built here.
#
# Fuel and condition (the "hitpoints"), both numbers the sim keeps and the player never sees as
# numbers -- the condition-view rule (CLAUDE.md's health-bar ban) applied to a car. `fuel` is
# litres against the class's `tank`, burned per metre under way (`range` metres on a full tank)
# and per second idling (`idleMinutes` on a full tank); `integrity` is 0..100, rolled at spawn
# and spent by crashes -- a car that hits something at speed takes damage in proportion to the
# square of that speed and puts a bang on the attention field. What the player reads is
# `hood_view`: the state word for the engine (sound, scuffed, battered, failing, wrecked) and the
# fuel word (dry .. full), reached by standing at the nose and pressing the interact key
# (`check_hood`, on fortify's E ladder before the door). HOOD_KEYS is the allowlist the gate holds
# the view to, exactly as SimCondition.PART_KEYS is held: a numeric field there is a red build.
# A dry tank or a wrecked engine will not run: the car coasts to a stop and the idle goes quiet.
#
# The light vehicles (the owner's goal of 2026-09-05, the fourth of the driving session): a
# bicycle, an electric bike, an electric scooter, a kick scooter and a skateboard are the same
# module and the same component, told apart by content and not by code. The class's `drive.power`
# says what moves it -- `engine` (the cars), `battery` (charge that runs flat, and then the rider
# pedals or kicks at `unpowered`), `muscle` (the rider, never dry) -- and picks the words: a
# battery reads flat..full, a hood check on a bike is a look over the frame. `cab` says whether
# the driver is inside anything: a car's driver is off the shambler's menu and is not drawn; a
# rider is on it, is drawn on the machine, and is put off it by a grab or by a crash at speed
# (`_unseat`) -- the balance a light vehicle buys with its speed. `dash` names which instrument
# layout the seat shows (`dash_view.layout`): a car's cluster, a handlebar computer, or the
# next-to-nothing a board gives you. Speeds sit between a walk (2.1) and a car (8..10): a bicycle
# just outruns a sprint (6.3) and a skateboard does not, which is the balance the goal asked for.
#
# Determinism: the one RNG here is the `vehicles` stream, drawn exactly twice per record at spawn
# (fuel, then condition) in manifest order, so a seed parks the same tanks every boot. Everything
# after that is a function of the commands and the map, and a replay of the same commands drives
# the same car to the same tile with the same litres left.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimAttention = preload("res://sim/modules/attention_emitter.gd")
const SimPath = preload("res://sim/path.gd")
const SimWorldgen = preload("res://sim/map/worldgen.gd")

const NO_DRIVER: int = -1
# How close a body has to be to the footprint's edge to get in. Fortify's REACH, the same arm.
const REACH: float = 1.5
const TICK_SECONDS: float = 0.05
# A hair inside the footprint's edges, so a car whose edge sits exactly on a tile boundary covers
# the tiles it stands on and not the neighbour it merely touches.
const EPS: float = 0.001
const HEADINGS: Dictionary = {
	"n": Vector2(0.0, -1.0),
	"s": Vector2(0.0, 1.0),
	"e": Vector2(1.0, 0.0),
	"w": Vector2(-1.0, 0.0),
}
const OPPOSITE: Dictionary = {"n": "s", "s": "n", "e": "w", "w": "e"}
const TOGGLE: String = "vehicle.toggle"
# Coasting with no intent loses speed at this fraction of the class's braking. Engine braking,
# not a handbrake: a car you take your foot off rolls on for a while.
const COAST_FRACTION: float = 0.5
# Condition. 0..100 in the sim; the words below are the whole of what leaves it. The bands are
# the body-part convention: compare states, never the number.
const INTEGRITY_MAX: float = 100.0
const CONDITION_WORDS: Array[String] = ["wrecked", "failing", "battered", "scuffed", "sound"]
const CONDITION_FLOORS: Array[float] = [0.0, 0.0, 30.0, 60.0, 85.0]
# What each band does to the class's top speed: a failing engine crawls, a wrecked one is dead.
const CONDITION_CAP: Array[float] = [0.0, 0.45, 0.7, 0.9, 1.0]
# One in ten parked cars is a wreck at boot; the rest roll 40..100.
const WRECKED_AT_BOOT: float = 0.1
const INTEGRITY_ROLL_FLOOR: float = 40.0
# A crash: below this speed a bump costs nothing; at the class's own top speed it costs
# CRASH_DAMAGE_AT_CAP, scaling with the square of the speed between. The cap is the class's, so
# a battered car crashing at the lower top it can still reach is hurt less: a sound sedan takes
# four runs at a wall to wreck (55, 27, 11, 11), not two. The bang on the field is CRASH_NOISE
# at the cap, scaled the same way -- louder than a shout at full tilt (120), because sheet
# metal on a wall is.
const CRASH_MIN_SPEED: float = 2.0
const CRASH_DAMAGE_AT_CAP: float = 55.0
const CRASH_NOISE: float = 150.0
# Fuel, in words: the thresholds are fractions of the tank, the words are the whole readout.
const FUEL_WORDS: Array[String] = ["dry", "a splash in the tank", "under a quarter", "about half a tank", "most of a tank", "full"]
const FUEL_FLOORS: Array[float] = [0.0, 0.0, 0.1, 0.3, 0.6, 0.9]
# How long a hood report stays on the HUD after the look, in ticks: ten seconds.
const HOOD_REPORT_TICKS: int = 200
# The hood view's keys, every one a word or a boolean. check_vehicles.gd's HOOD lane holds the
# view to this list the way check_ban_health_bar.gd holds the condition view to PART_KEYS.
const HOOD_KEYS: Array[String] = ["name", "condition", "fuel", "runs", "prose"]
# The dashboard: what the driver sees from the seat, a makeshift instrument cluster (the
# owner's third goal of 2026-09-05). Words and booleans, plus exactly two needles -- `speedo`
# and `gauge`, fractions of the class's top and of the tank -- which are the machine's own
# instruments and not the body's, docs/30 records why that is not the health bar. No digits
# anywhere in it; a speedometer with no numbers on the dial is still a speedometer.
# `layout`, `motion` and `powered` came with the light vehicles: which instrument layout the
# screen draws (the class's `dash` word), the gear in the vehicle's own words (a car is in drive,
# a bicycle is pedalling, a board is being pushed), and whether there is a tank or a battery to
# gauge at all -- a bicycle's dash has no fuel needle because a bicycle has no fuel.
const DASH_KEYS: Array[String] = ["name", "layout", "gear", "motion", "braking", "throttle", "running", "powered", "speed", "speedo", "engine", "warning", "fuel", "gauge", "prose"]
const DASH_NEEDLES: Array[String] = ["speedo", "gauge"]
const GEARS: Array[String] = ["park", "neutral", "drive"]
# What moves a class, the schema's `drive.power` enum. Judged whole with the rest of the block.
const POWER_ENGINE: String = "engine"
const POWER_BATTERY: String = "battery"
const POWER_MUSCLE: String = "muscle"
const POWERS: Array[String] = [POWER_ENGINE, POWER_BATTERY, POWER_MUSCLE]
# The drive keys a tank needs: required for an engine or a battery, zero for muscle.
const TANK_KEYS: Array[String] = ["tank", "range", "idleMinutes"]
# The instrument layouts the schema's `dash` enum names; ui/dashboard.gd draws one per word.
const DASH_LAYOUTS: Array[String] = ["cluster", "handlebar", "board"]
# A battery's six words, on the same fractions as the tank's: the whole readout of a charge.
const CHARGE_WORDS: Array[String] = ["flat", "a sliver of charge", "under a quarter", "about half a charge", "most of a charge", "full"]
# The gear in each layout's own words, indexed park / neutral / drive. A battery class under
# power says so; with the charge flat it says what the rider is doing instead.
const MOTION_WORDS: Dictionary = {
	"cluster": ["in park", "in neutral", "in drive"],
	"handlebar": ["stopped", "coasting", "pedalling"],
	"board": ["stopped", "rolling", "pushing"],
}
const MOTION_POWERED: String = "under power"
# Speed, in words, on the fraction of the class's top: the whole readout beside the needle.
const SPEED_WORDS: Array[String] = ["stopped", "crawling", "rolling", "a fair clip", "flat out"]
const SPEED_FLOORS: Array[float] = [0.0, 0.0, 0.25, 0.5, 0.8]


static func register_module(world: Variant) -> void:
	# Input order 4: after world's apply-commands (0) has written the driver's velocity from the
	# move command -- so the pin below zeroes what it wrote rather than racing it -- and before
	# fortify's intake at 5, whose E ladder (SimFortify._use_context) is how the player gets in
	# and out: from the wheel E dismounts, from the kerb it mounts after the loot and the people
	# beside the car (the owner's 2026-09-05 decision, docs/30 "Driving"). TOGGLE stays a command
	# of its own for gates and replays; nothing in presentation pushes it.
	world.systems.register("vehicle.intake", "input", 4, func(w: Variant) -> void:
		_intake(w)
	)
	# Movement order 1: world's integrate at 0 has skipped every vehicle (world.gd says so), the
	# kernel refreshes light at 75 and vision at 100 -- so the driver's pinned position is where
	# the car now is by the time anybody looks out of it.
	world.systems.register("vehicle.drive", "movement", 1, func(w: Variant) -> void:
		_drive(w)
	)


# --- content ------------------------------------------------------------------------------------

# The class entry for a content id, or {} when the world declares no such class.
static func class_of(world: Variant, id: String) -> Dictionary:
	if world == null or not (world.content is Dictionary) or id.is_empty():
		return {}
	# The tree is keyed by content path ("vehicles/sedan.json"), and the worldgen pass already
	# knows how to read the vehicle entries out of it; one reader, not two that could disagree.
	for entry in SimWorldgen.vehicles_of(world.content as Dictionary):
		if String((entry as Dictionary).get("id", "")) == id:
			return entry as Dictionary
	return {}


const DRIVE_KEYS: Array[String] = ["speed", "accel", "brake", "noise", "idle", "tank", "range", "idleMinutes"]


# The power word and the eight numbers a class drives on -- {power, speed, accel, brake, noise,
# idle, tank, range, idleMinutes, unpowered} -- or {} when the class declares no usable `drive`
# block. Judged whole rather than defaulted a key at a time: the validator does not recurse, so a
# class missing `brake` would otherwise drive on a silent guess, and a car that never stops is
# exactly the wrong number nothing reports. The one allowance is the power's own: a muscle class
# has no tank, so its three tank keys may be absent or zero and read as zero; an engine or a
# battery must declare all three above zero. `unpowered` is optional and zero when absent -- what
# a battery class does with the charge flat. A class with no drive block cannot be mounted, and
# `mount_problem` says so.
static func drive_of(entry: Dictionary) -> Dictionary:
	var block: Variant = entry.get("drive")
	if not (block is Dictionary):
		return {}
	var d: Dictionary = block as Dictionary
	var power: String = String(d.get("power", ""))
	if not POWERS.has(power):
		return {}
	var out: Dictionary = {"power": power}
	for key in DRIVE_KEYS:
		var needed: bool = power != POWER_MUSCLE or not TANK_KEYS.has(key)
		var v: Variant = d.get(key)
		if v == null and not needed:
			out[key] = 0.0
			continue
		if not (v is float or v is int):
			return {}
		var f: float = float(v)
		if f < 0.0 or (key != "idle" and needed and f <= 0.0):
			return {}
		out[key] = f
	var fallback: Variant = d.get("unpowered")
	if fallback == null:
		out["unpowered"] = 0.0
	elif not (fallback is float or fallback is int) or float(fallback) < 0.0:
		return {}
	else:
		out["unpowered"] = float(fallback)
	return out


# What moves a class: one of POWERS, or "" for a block `drive_of` refused.
static func power_of(drive: Dictionary) -> String:
	return String(drive.get("power", ""))


# Whether the driver sits inside a closed body. Read off the class entry's `cab`; a class that
# says nothing is open, because a shelter nobody declared is a shelter nobody should get.
static func has_cab(entry: Dictionary) -> bool:
	return bool(entry.get("cab", false))


# Which instrument layout the seat shows, one of DASH_LAYOUTS; a word nobody declared, or one
# not on the list, falls to the board -- the least instrument, never the most.
static func dash_layout(entry: Dictionary) -> String:
	var word: String = String(entry.get("dash", ""))
	return word if DASH_LAYOUTS.has(word) else "board"


# Whether the motor is turning over: an engine or a battery with something in the tank on a
# vehicle that is not a wreck. A muscle class has no motor and answers false always -- its rider
# is what moves it, which is `can_ride`.
static func motor_runs(v: Dictionary, drive: Dictionary) -> bool:
	if drive.is_empty() or power_of(drive) == POWER_MUSCLE:
		return false
	return engine_runs(v)


# The speed the rider makes with no motor helping: a muscle class's own top, a battery class's
# `unpowered`, nothing at all for an engine.
static func muscle_top(drive: Dictionary) -> float:
	match power_of(drive):
		POWER_MUSCLE:
			return float(drive.get("speed", 0.0))
		POWER_BATTERY:
			return float(drive.get("unpowered", 0.0))
	return 0.0


# The top speed this vehicle can be asked for right now, before the ground and the condition
# take their cut: the class's top under power, the rider's own without it, nothing for a wreck.
static func top_of(v: Dictionary, drive: Dictionary) -> float:
	if drive.is_empty() or condition_band(float(v.get("integrity", 0.0))) == 0:
		return 0.0
	if motor_runs(v, drive):
		return float(drive.get("speed", 0.0))
	return muscle_top(drive)


# Whether the vehicle will move at all under the driver's intent: a running motor or a rider
# who can push it, on something that is not a wreck.
static func can_ride(v: Dictionary, drive: Dictionary) -> bool:
	return top_of(v, drive) > 0.0


# --- spawning and the map shadow ---------------------------------------------------------------

# One entity per manifest record. Called by SimBoot.playable after the map is adopted; a record
# whose class the content does not declare, or declares without a footprint, is left as it is --
# a parked picture nobody can drive -- and reported, because the generator wrote it from a class
# it found and this should never happen on a coherent tree.
static func spawn_from_manifest(world: Variant, map: Variant) -> Array[int]:
	var spawned: Array[int] = []
	if map == null:
		return spawned
	var records: Variant = map.get("vehicles")
	if not (records is Array):
		return spawned
	# Its own named stream (the loot-table precedent): two draws a record, fuel then condition,
	# always both, so a record that is refused below still costs its draws and every car after
	# it rolls the same tank whatever came before.
	var rng: Variant = world.rng.stream("vehicles")
	for rec in records as Array:
		if not (rec is Dictionary):
			continue
		var r: Dictionary = rec as Dictionary
		if r.has("entity"):
			continue
		var fuel_roll: float = float(rng.call("next"))
		var wear_roll: float = float(rng.call("next"))
		var entry: Dictionary = class_of(world, String(r.get("class", "")))
		var foot: Dictionary = entry.get("footprint", {}) as Dictionary
		var breadth: int = int(foot.get("w", 0))
		var length: int = int(foot.get("l", 0))
		if breadth < 1 or length < 1:
			push_error("vehicles: record %s names %s, which declares no footprint; it stays a picture" % [str(r), String(r.get("class", ""))])
			continue
		var facing: String = String(r.get("facing", "n"))
		if not HEADINGS.has(facing):
			facing = "n"
		var x: int = int(r.get("x", 0))
		var y: int = int(r.get("y", 0))
		var w: int = int(r.get("w", 0))
		var h: int = int(r.get("h", 0))
		var entity: int = int(world.entities.spawn())
		world.components.set_component(entity, "vehicle", {
			"class": String(r.get("class", "")),
			"w": breadth,
			"l": length,
			"heading": facing,
			"speed": 0.0,
			"driver": NO_DRIVER,
			"intent": {"dx": 0.0, "dy": 0.0},
			"home": {"x": x, "y": y},
			"fuel": rolled_fuel(drive_of(entry), fuel_roll),
			"integrity": rolled_integrity(wear_roll),
			"gear": "park",
			"braking": false,
		})
		world.components.set_component(entity, "position", {"x": float(x) + float(w) / 2.0, "y": float(y) + float(h) / 2.0})
		var dir: Vector2 = HEADINGS[facing] as Vector2
		world.components.set_component(entity, "facing", {"radians": atan2(dir.y, dir.x)})
		# No `velocity` and no `attention_emitter` while parked: those are the engine, and they
		# arrive with the driver (`mount`) and leave with them (`dismount`). A parked car is then
		# outside every per-tick query that walks velocities -- world's integrate, the emitter's
		# footsteps, this module's own drive loop -- which is what keeps a hundred parked cars at
		# 256 from costing a tick anything. Measured at 128 with 33 cars: 0.35 ms a tick with the
		# components on every parked car, none with them off.
		# Claimed, so the sync below replaces this record with the entity's shadow rather than
		# keeping it beside one -- the first probe stood sixty-six records over thirty-three cars.
		r["entity"] = entity
		spawned.append(entity)
	if not spawned.is_empty():
		sync_map(world)
	return spawned


# The engine: a velocity to integrate and an emitter for the one system that already hears every
# footstep. `walking` and `sprinting` are both the engine under way (the emitter picks by speed,
# and a car is never quiet at either), `ambient` the idle, scent nothing.
static func _start_engine(world: Variant, entity: int, drive: Dictionary) -> void:
	world.components.set_component(entity, "velocity", {"dx": 0.0, "dy": 0.0})
	SimAttention.make_emitter(world, entity, {"walking": 0.0, "sprinting": 0.0, "ambient": 0.0, "scent": 0.0})
	var v: Dictionary = world.components.get_component(entity, "vehicle") as Dictionary
	_set_engine_noise(world, entity, drive, can_ride(v, drive), motor_runs(v, drive))


# The emitter's three figures follow the machine: the moving noise (an engine's roar, a bike's
# tyres and chain) whenever the thing can move at all, the idle only while a motor turns over.
# A dry or wrecked car rolls in silence; a bicycle is never idle-loud, because it has no idle.
static func _set_engine_noise(world: Variant, entity: int, drive: Dictionary, moving: bool, motor: bool) -> void:
	var em: Variant = world.components.get_component(entity, "attention_emitter")
	if not (em is Dictionary):
		return
	var noise: float = float(drive.get("noise", 0.0)) if moving else 0.0
	(em as Dictionary)["walking"] = noise
	(em as Dictionary)["sprinting"] = noise
	(em as Dictionary)["ambient"] = (float(drive.get("idle", 0.0)) if motor else 0.0)


static func _stop_engine(world: Variant, entity: int) -> void:
	world.components.remove(entity, "velocity")
	world.components.remove(entity, "attention_emitter")


# --- fuel and condition -------------------------------------------------------------------------

# Litres in a parked tank for one roll in [0, 1): the square of the roll times the tank, so most
# cars stand low and a full one is rare -- a street of abandoned cars, not a forecourt. A class
# with no drive block has no tank and parks dry.
static func rolled_fuel(drive: Dictionary, roll: float) -> float:
	return float(drive.get("tank", 0.0)) * roll * roll


# Condition for one roll in [0, 1): the bottom tenth is a wreck, the rest lands evenly between
# INTEGRITY_ROLL_FLOOR and the maximum.
static func rolled_integrity(roll: float) -> float:
	if roll < WRECKED_AT_BOOT:
		return 0.0
	return INTEGRITY_ROLL_FLOOR + (INTEGRITY_MAX - INTEGRITY_ROLL_FLOOR) * (roll - WRECKED_AT_BOOT) / (1.0 - WRECKED_AT_BOOT)


# The condition band an integrity falls in: an index into CONDITION_WORDS and CONDITION_CAP.
static func condition_band(integrity: float) -> int:
	if integrity <= 0.0:
		return 0
	for i in range(CONDITION_FLOORS.size() - 1, 0, -1):
		if integrity >= CONDITION_FLOORS[i]:
			return i
	return 1


static func condition_word(integrity: float) -> String:
	return CONDITION_WORDS[condition_band(integrity)]


# The fuel band, on the fraction of the tank: an index into FUEL_WORDS.
static func fuel_band(fuel: float, tank: float) -> int:
	if fuel <= 0.0 or tank <= 0.0:
		return 0
	var fraction: float = fuel / tank
	for i in range(FUEL_FLOORS.size() - 1, 0, -1):
		if fraction >= FUEL_FLOORS[i]:
			return i
	return 1


static func fuel_word(fuel: float, tank: float) -> String:
	return FUEL_WORDS[fuel_band(fuel, tank)]


# The word for what is in the tank, in the class's own vocabulary: litres for an engine, charge
# for a battery, and for a muscle class the one word that says there is nothing to fill.
static func charge_word(fuel: float, tank: float) -> String:
	return CHARGE_WORDS[fuel_band(fuel, tank)]


const NO_TANK_WORD: String = "no tank"


static func fill_word(drive: Dictionary, fuel: float) -> String:
	var tank: float = float(drive.get("tank", 0.0))
	match power_of(drive):
		POWER_BATTERY:
			return charge_word(fuel, tank)
		POWER_MUSCLE:
			return NO_TANK_WORD
	return fuel_word(fuel, tank)


# Whether the engine can turn over at all: fuel in the tank and a car that is not a wreck.
static func engine_runs(v: Dictionary) -> bool:
	return float(v.get("fuel", 0.0)) > 0.0 and condition_band(float(v.get("integrity", 0.0))) > 0


# Litres a second idling and litres a metre under way, from the class's tank and reach.
static func idle_burn(drive: Dictionary) -> float:
	var minutes: float = float(drive.get("idleMinutes", 0.0))
	if minutes <= 0.0:
		return 0.0
	return float(drive.get("tank", 0.0)) / (minutes * 60.0)


static func move_burn(drive: Dictionary) -> float:
	var reach: float = float(drive.get("range", 0.0))
	if reach <= 0.0:
		return 0.0
	return float(drive.get("tank", 0.0)) / reach


# A crash, at `speed` against a class whose top is `cap`: the damage taken and the bang made,
# both scaling with the square of the speed fraction, and nothing at all under CRASH_MIN_SPEED.
static func crash_damage(speed: float, cap: float) -> float:
	if speed < CRASH_MIN_SPEED or cap <= 0.0:
		return 0.0
	var f: float = speed / cap
	return CRASH_DAMAGE_AT_CAP * f * f


static func crash_noise(speed: float, cap: float) -> float:
	if speed < CRASH_MIN_SPEED or cap <= 0.0:
		return 0.0
	var f: float = speed / cap
	return CRASH_NOISE * f * f


# --- the hood -----------------------------------------------------------------------------------

# Whether a body stands at the nose of this car: within REACH of the nose edge along the heading
# and inside the car's breadth across it (half a metre of slack either side). The door is the
# side; the hood is the front; a body at a corner is at the hood if it is past the nose.
static func at_hood(world: Variant, actor: int, entity: int) -> bool:
	var v: Variant = world.components.get_component(entity, "vehicle")
	var vpos: Variant = world.components.get_component(entity, "position")
	var pos: Variant = world.components.get_component(actor, "position")
	if not (v is Dictionary) or not (vpos is Dictionary) or not (pos is Dictionary):
		return false
	var heading: String = String((v as Dictionary).get("heading", "n"))
	var dir: Vector2 = HEADINGS[heading] as Vector2
	var ext: Vector2i = extent_of(v as Dictionary, heading)
	var rel: Vector2 = Vector2(float((pos as Dictionary)["x"]) - float((vpos as Dictionary)["x"]), float((pos as Dictionary)["y"]) - float((vpos as Dictionary)["y"]))
	var along: float = rel.dot(dir)
	var across: float = absf(rel.dot(Vector2(-dir.y, dir.x)))
	var half_along: float = float(ext.x if dir.x != 0.0 else ext.y) / 2.0
	var half_across: float = float(ext.y if dir.x != 0.0 else ext.x) / 2.0
	return along > half_along and along <= half_along + REACH and across <= half_across + 0.5


# What a look under the hood tells: words and booleans only, per HOOD_KEYS. The engine's
# condition band, the fuel band, whether it would turn over, and one sentence built from them.
static func hood_view(world: Variant, entity: int) -> Dictionary:
	var v: Variant = world.components.get_component(entity, "vehicle")
	if not (v is Dictionary):
		return {}
	var d: Dictionary = v as Dictionary
	var entry: Dictionary = class_of(world, String(d.get("class", "")))
	var drive: Dictionary = drive_of(entry)
	var name: String = String(entry.get("name", "car")).to_lower()
	var condition: String = condition_word(float(d.get("integrity", 0.0)))
	var fuel: String = fill_word(drive, float(d.get("fuel", 0.0)))
	var runs: bool = can_ride(d, drive)
	var prose: String
	match power_of(drive):
		POWER_MUSCLE:
			# Nothing under a bicycle's hood but the bicycle: the frame is the whole report.
			if condition == "wrecked":
				prose = "looking the %s over: the frame is wrecked; nobody rides that again" % name
			else:
				prose = "looking the %s over: the frame is %s; nothing to fill" % [name, condition]
		POWER_BATTERY:
			if condition == "wrecked":
				prose = "looking the %s over: the frame is wrecked; nobody rides that again" % name
			elif fuel == CHARGE_WORDS[0]:
				prose = "looking the %s over: the frame is %s, and the battery is flat" % [name, condition]
			else:
				prose = "looking the %s over: the frame is %s; %s" % [name, condition, fuel]
		_:
			if condition == "wrecked":
				prose = "under the %s's hood: the engine is wrecked; it will never run again" % name
			elif fuel == "dry":
				prose = "under the %s's hood: the engine is %s, but the tank is dry" % [name, condition]
			else:
				prose = "under the %s's hood: the engine is %s; %s" % [name, condition, fuel]
	return {"name": name, "condition": condition, "fuel": fuel, "runs": runs, "prose": prose}


# Looking under the hood: the report sits on the body for HOOD_REPORT_TICKS, where the HUD
# clause reads it, and the bus hears that it happened. Refused off the nose.
static func check_hood(world: Variant, actor: int, entity: int) -> bool:
	if not at_hood(world, actor, entity):
		return false
	world.components.set_component(actor, "hoodReport", {"vehicle": entity, "until": int(world.tick) + HOOD_REPORT_TICKS})
	world.events.publish({"type": "vehicle.hood.checked", "entity": entity, "actor": actor})
	return true


# --- the dashboard ------------------------------------------------------------------------------

static func speed_band(speed: float, top: float) -> int:
	if speed <= 0.0 or top <= 0.0:
		return 0
	var fraction: float = speed / top
	for i in range(SPEED_FLOORS.size() - 1, 0, -1):
		if fraction >= SPEED_FLOORS[i]:
			return i
	return 1


static func speed_word(speed: float, top: float) -> String:
	return SPEED_WORDS[speed_band(speed, top)]


# What the driver's seat shows, or {} for a body not at a wheel. DASH_KEYS is the whole of it:
# the gear, the brake lamp, whether the throttle is down and the engine turning over, the speed
# as a word and as a needle (fraction of the class's top -- an unlabelled dial), the engine's
# condition word and its warning lamp, the fuel as a word and as a needle (fraction of the
# tank, E to F), and one line of prose. Never a digit.
static func dash_view(world: Variant, actor: int) -> Dictionary:
	var m: Variant = world.components.get_component(actor, "mounted")
	if not (m is Dictionary):
		return {}
	var entity: int = int((m as Dictionary).get("vehicle", NO_DRIVER))
	var v: Variant = world.components.get_component(entity, "vehicle")
	if not (v is Dictionary):
		return {}
	var d: Dictionary = v as Dictionary
	var entry: Dictionary = class_of(world, String(d.get("class", "")))
	var drive: Dictionary = drive_of(entry)
	var name: String = String(entry.get("name", "car")).to_lower()
	var layout: String = dash_layout(entry)
	var power: String = power_of(drive)
	# The needle's full-scale is the class's top under power, so a flat e-bike pedalled at its
	# unpowered speed reads part-way up the same dial -- the dial did not shrink, the ride did.
	var top: float = float(drive.get("speed", 0.0))
	var tank: float = float(drive.get("tank", 0.0))
	var speed: float = float(d.get("speed", 0.0))
	var fuel: float = float(d.get("fuel", 0.0))
	var integrity: float = float(d.get("integrity", 0.0))
	var gear: String = String(d.get("gear", "park"))
	var motor: bool = motor_runs(d, drive)
	var running: bool = can_ride(d, drive)
	var band: int = condition_band(integrity)
	var powered: bool = power == POWER_ENGINE or power == POWER_BATTERY
	var words: Array = MOTION_WORDS.get(layout, MOTION_WORDS["board"]) as Array
	var motion: String = String(words[maxi(0, GEARS.find(gear))])
	if gear == "drive" and power == POWER_BATTERY and motor:
		motion = MOTION_POWERED
	var view: Dictionary = {
		"name": name,
		"layout": layout,
		"gear": gear,
		"motion": motion,
		"braking": bool(d.get("braking", false)),
		"throttle": gear == "drive",
		"running": running,
		"powered": powered,
		"speed": speed_word(speed, top),
		"speedo": clampf(speed / top, 0.0, 1.0) if top > 0.0 else 0.0,
		"engine": condition_word(integrity),
		"warning": band <= 2,
		"fuel": fill_word(drive, fuel),
		"gauge": clampf(fuel / tank, 0.0, 1.0) if tank > 0.0 else 0.0,
	}
	var prose: String
	if band == 0:
		prose = "the %s is wrecked; nothing on the dash answers" % name if layout == "cluster" else "the %s is wrecked; it goes nowhere" % name
	elif power == POWER_ENGINE and not motor:
		prose = "%s, %s; the tank is dry" % [motion, view["speed"]]
	elif power == POWER_BATTERY and not motor:
		prose = "%s, %s; the battery is flat" % [motion, view["speed"]]
	elif powered:
		prose = "%s, %s; %s" % [motion, view["speed"], view["fuel"]]
	else:
		prose = "%s, %s" % [motion, view["speed"]]
	if bool(view["braking"]):
		prose += "; braking" if layout != "board" else "; a foot down"
	view["prose"] = prose
	return view


# The report a body is still reading, or {} once it has lapsed (and the lapsed component gone).
static func hood_report(world: Variant, actor: int) -> Dictionary:
	var report: Variant = world.components.get_component(actor, "hoodReport")
	if not (report is Dictionary):
		return {}
	if int((report as Dictionary).get("until", 0)) < int(world.tick):
		world.components.remove(actor, "hoodReport")
		return {}
	return hood_view(world, int((report as Dictionary).get("vehicle", NO_DRIVER)))


# Rebuilds the map's shadow of every vehicle entity: the Tile.Low under each footprint and the
# `map.vehicles` record beside it. Records that name an entity are replaced wholesale; records
# that name none (a manifest nobody spawned from -- a gate booting `bare`, a fixture) are kept as
# they are, so a map with parked pictures and no module still draws them. Called at spawn, after
# a restore, and by `_drive` whenever a footprint's tiles change.
static func sync_map(world: Variant) -> void:
	var map: Variant = world.tilemap
	if map == null:
		return
	var records: Variant = map.get("vehicles")
	if not (records is Array):
		return
	var kept: Array = []
	for rec in records as Array:
		if not (rec is Dictionary):
			continue
		var r: Dictionary = rec as Dictionary
		if r.has("entity"):
			_clear_tiles(map, _rect_of_record(r))
		else:
			kept.append(r)
	for entity in world.components.query(["vehicle", "position"]):
		var v: Dictionary = world.components.get_component(int(entity), "vehicle") as Dictionary
		var pos: Dictionary = world.components.get_component(int(entity), "position") as Dictionary
		var rect: Rect2i = footprint(v, pos)
		_write_tiles(map, rect)
		kept.append(_record_for(int(entity), v, pos, rect))
	map.vehicles = kept
	map.vehicle_generation = int(map.vehicle_generation) + 1
	world.invalidateMap()


static func _record_for(entity: int, v: Dictionary, pos: Dictionary, rect: Rect2i) -> Dictionary:
	var heading: String = String(v.get("heading", "n"))
	var home: Dictionary = v.get("home", {}) as Dictionary
	var gp: Vector2 = ground_point(v, pos)
	return {
		"x": rect.position.x, "y": rect.position.y,
		"w": rect.size.x, "h": rect.size.y,
		"axis": axis_of(heading),
		"class": String(v.get("class", "")),
		"facing": heading,
		"entity": entity,
		# The corner the layout parked it on, which is what the paint hashes on: a car that
		# drives off keeps its colour, and two cars never share a home.
		"hx": int(home.get("x", rect.position.x)),
		"hy": int(home.get("y", rect.position.y)),
		# Where the picture stands this tick, in metres -- the live centre of the south edge,
		# so a moving car draws where it is rather than snapping tile to tile.
		"gx": gp.x,
		"gy": gp.y,
	}


static func _rect_of_record(r: Dictionary) -> Rect2i:
	return Rect2i(int(r.get("x", 0)), int(r.get("y", 0)), int(r.get("w", 0)), int(r.get("h", 0)))


static func _clear_tiles(map: Variant, rect: Rect2i) -> void:
	for ty in range(rect.position.y, rect.end.y):
		for tx in range(rect.position.x, rect.end.x):
			if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
				continue
			var i: int = ty * int(map.w) + tx
			if int(map.tiles[i]) == SimTileMap.Tile.Low:
				map.tiles[i] = SimTileMap.Tile.Floor


static func _write_tiles(map: Variant, rect: Rect2i) -> void:
	for ty in range(rect.position.y, rect.end.y):
		for tx in range(rect.position.x, rect.end.x):
			if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
				continue
			map.tiles[ty * int(map.w) + tx] = SimTileMap.Tile.Low


# --- geometry ----------------------------------------------------------------------------------

static func axis_of(heading: String) -> String:
	return "ns" if heading == "n" or heading == "s" else "ew"


# The footprint's extent in tiles for a heading: (across x, across y).
static func extent_of(v: Dictionary, heading: String) -> Vector2i:
	var breadth: int = int(v.get("w", 2))
	var length: int = int(v.get("l", 5))
	if axis_of(heading) == "ns":
		return Vector2i(breadth, length)
	return Vector2i(length, breadth)


# The tiles a car covers standing at `pos` -- every tile its rectangle overlaps by more than EPS,
# so a car mid-step covers the tile it is entering as well as the one it is leaving.
static func footprint(v: Dictionary, pos: Dictionary) -> Rect2i:
	var ext: Vector2i = extent_of(v, String(v.get("heading", "n")))
	var cx: float = float(pos.get("x", 0.0))
	var cy: float = float(pos.get("y", 0.0))
	var x0: int = floori(cx - float(ext.x) / 2.0 + EPS)
	var y0: int = floori(cy - float(ext.y) / 2.0 + EPS)
	var x1: int = ceili(cx + float(ext.x) / 2.0 - EPS)
	var y1: int = ceili(cy + float(ext.y) / 2.0 - EPS)
	return Rect2i(x0, y0, maxi(1, x1 - x0), maxi(1, y1 - y0))


# Where the picture stands: the centre of the footprint's south edge, in metres.
static func ground_point(v: Dictionary, pos: Dictionary) -> Vector2:
	var ext: Vector2i = extent_of(v, String(v.get("heading", "n")))
	return Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)) + float(ext.y) / 2.0)


# Snaps one coordinate of the centre so the footprint sits on whole tiles: an even extent wants
# the centre on a tile boundary, an odd one on a tile's middle.
static func _snap(value: float, extent: int) -> float:
	var frac: float = fmod(float(extent) / 2.0, 1.0)
	return floorf(value - frac + 0.5) + frac


# The centre a car would have after turning to `heading`, snapped to the grid for that heading.
static func turned_centre(v: Dictionary, pos: Dictionary, heading: String) -> Dictionary:
	var ext: Vector2i = extent_of(v, heading)
	return {"x": _snap(float(pos.get("x", 0.0)), ext.x), "y": _snap(float(pos.get("y", 0.0)), ext.y)}


# The tiles a car would cover after turning to `heading` about its (snapped) centre. Public so
# the gate fabricates its wall on a tile this answer names rather than on one it computed twice.
static func turned_footprint(v: Dictionary, pos: Dictionary, heading: String) -> Rect2i:
	var turned: Dictionary = v.duplicate(true)
	turned["heading"] = heading
	return footprint(turned, turned_centre(v, pos, heading))


# --- what a car may drive into ----------------------------------------------------------------

# Whether `entity` may cover this tile: off the map, solid, indoors, and any Low tile that is not
# already this car's own are all refusals. A Low tile no record covers is a heap of junk; one
# another record covers is another car.
static func tile_blocks(world: Variant, map: Variant, entity: int, tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return true
	if world.is_blocked_tile(tx, ty):
		return true
	var i: int = ty * int(map.w) + tx
	if int(map.indoors[i]) != 0:
		return true
	if int(map.tiles[i]) != SimTileMap.Tile.Low:
		return false
	return not _own_record_covers(map, entity, tx, ty)


static func _own_record_covers(map: Variant, entity: int, tx: int, ty: int) -> bool:
	var records: Variant = map.get("vehicles")
	if not (records is Array):
		return false
	for rec in records as Array:
		if not (rec is Dictionary):
			continue
		var r: Dictionary = rec as Dictionary
		if int(r.get("entity", NO_DRIVER)) != entity:
			continue
		return _rect_of_record(r).has_point(Vector2i(tx, ty))
	return false


static func _rect_clear(world: Variant, map: Variant, entity: int, rect: Rect2i) -> bool:
	for ty in range(rect.position.y, rect.end.y):
		for tx in range(rect.position.x, rect.end.x):
			if tile_blocks(world, map, entity, tx, ty):
				return false
	return true


# --- mounting ----------------------------------------------------------------------------------

# The vehicle a body could get into from where it stands, or NO_DRIVER: the nearest footprint
# whose edge is within REACH, that nobody is driving, whose class can be driven at all.
static func nearest_in_reach(world: Variant, actor: int) -> int:
	var pos: Variant = world.components.get_component(actor, "position")
	if not (pos is Dictionary):
		return NO_DRIVER
	var px: float = float((pos as Dictionary).get("x", 0.0))
	var py: float = float((pos as Dictionary).get("y", 0.0))
	var best: int = NO_DRIVER
	var best_d: float = REACH + 1.0
	for entity in world.components.query(["vehicle", "position"]):
		var v: Dictionary = world.components.get_component(int(entity), "vehicle") as Dictionary
		if int(v.get("driver", NO_DRIVER)) != NO_DRIVER:
			continue
		var d: float = _distance_to_footprint(v, world.components.get_component(int(entity), "position") as Dictionary, px, py)
		if d <= REACH and d < best_d:
			best_d = d
			best = int(entity)
	return best


static func _distance_to_footprint(v: Dictionary, pos: Dictionary, px: float, py: float) -> float:
	var ext: Vector2i = extent_of(v, String(v.get("heading", "n")))
	var cx: float = float(pos.get("x", 0.0))
	var cy: float = float(pos.get("y", 0.0))
	var dx: float = maxf(0.0, absf(px - cx) - float(ext.x) / 2.0)
	var dy: float = maxf(0.0, absf(py - cy) - float(ext.y) / 2.0)
	return sqrt(dx * dx + dy * dy)


# Why this body cannot get into this car right now, or "" when it can.
static func mount_problem(world: Variant, actor: int, entity: int) -> String:
	if world.components.has_component(actor, "mounted"):
		return "already at a wheel"
	var v: Variant = world.components.get_component(entity, "vehicle")
	if not (v is Dictionary):
		return "not a vehicle"
	if int((v as Dictionary).get("driver", NO_DRIVER)) != NO_DRIVER:
		return "somebody is driving it"
	if drive_of(class_of(world, String((v as Dictionary).get("class", "")))).is_empty():
		return "its class declares no drive block"
	for busy in ["grabbed", "treatment", "treated", "rescue", "corpse", "construct"]:
		if world.components.has_component(actor, busy):
			return "hands are not free (%s)" % busy
	var pos: Variant = world.components.get_component(actor, "position")
	if not (pos is Dictionary):
		return "no position"
	var d: float = _distance_to_footprint(v as Dictionary, world.components.get_component(entity, "position") as Dictionary, float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]))
	if d > REACH:
		return "out of reach"
	return ""


static func mount(world: Variant, actor: int, entity: int) -> bool:
	if not mount_problem(world, actor, entity).is_empty():
		return false
	var v: Dictionary = world.components.get_component(entity, "vehicle") as Dictionary
	var vpos: Dictionary = world.components.get_component(entity, "position") as Dictionary
	v["driver"] = actor
	v["intent"] = {"dx": 0.0, "dy": 0.0}
	var entry: Dictionary = class_of(world, String(v.get("class", "")))
	# `cab` rides on the mount so the shambler's gather and the drawing loop read a boolean and
	# never look a class up per body per tick (the 1.9 ms lesson, docs/23).
	world.components.set_component(actor, "mounted", {"vehicle": entity, "cab": has_cab(entry)})
	_pin_driver(world, actor, vpos, v)
	_start_engine(world, entity, drive_of(entry))
	world.events.publish({"type": "vehicle.mounted", "entity": entity, "driver": actor})
	return true


# Out through the nearest door: the first free walkable tile in the ring around the footprint,
# nearest the driver's side of the car (west of a north-south car, north of an east-west one,
# the way the pictures are drawn) and then any other. Refused when the ring has nowhere to stand,
# which a car wedged between walls can manage; the driver stays put and nothing changes.
static func dismount(world: Variant, actor: int) -> bool:
	var m: Variant = world.components.get_component(actor, "mounted")
	if not (m is Dictionary):
		return false
	var entity: int = int((m as Dictionary).get("vehicle", NO_DRIVER))
	var v: Variant = world.components.get_component(entity, "vehicle")
	if not (v is Dictionary):
		world.components.remove(actor, "mounted")
		return false
	# Not at speed: the door opens when the car has stopped, and the HUD clause says so.
	if float((v as Dictionary).get("speed", 0.0)) > 0.0:
		return false
	var vpos: Dictionary = world.components.get_component(entity, "position") as Dictionary
	var out: Variant = exit_tile(world, v as Dictionary, vpos)
	if out == null:
		return false
	var tile: Vector2i = out as Vector2i
	(v as Dictionary)["driver"] = NO_DRIVER
	(v as Dictionary)["speed"] = 0.0
	(v as Dictionary)["intent"] = {"dx": 0.0, "dy": 0.0}
	(v as Dictionary)["gear"] = "park"
	(v as Dictionary)["braking"] = false
	_stop_engine(world, entity)
	world.components.remove(actor, "mounted")
	var pos: Dictionary = world.components.get_component(actor, "position") as Dictionary
	pos["x"] = float(tile.x) + 0.5
	pos["y"] = float(tile.y) + 0.5
	world.events.publish({"type": "vehicle.dismounted", "entity": entity, "driver": actor, "x": pos["x"], "y": pos["y"]})
	return true


static func exit_tile(world: Variant, v: Dictionary, vpos: Dictionary) -> Variant:
	var rect: Rect2i = footprint(v, vpos)
	var ring: Array[Vector2i] = []
	var ns: bool = axis_of(String(v.get("heading", "n"))) == "ns"
	# Driver's side first, then the far side, then the ends.
	if ns:
		for ty in range(rect.position.y, rect.end.y):
			ring.append(Vector2i(rect.position.x - 1, ty))
		for ty in range(rect.position.y, rect.end.y):
			ring.append(Vector2i(rect.end.x, ty))
		for tx in range(rect.position.x, rect.end.x):
			ring.append(Vector2i(tx, rect.position.y - 1))
			ring.append(Vector2i(tx, rect.end.y))
	else:
		for tx in range(rect.position.x, rect.end.x):
			ring.append(Vector2i(tx, rect.position.y - 1))
		for tx in range(rect.position.x, rect.end.x):
			ring.append(Vector2i(tx, rect.end.y))
		for ty in range(rect.position.y, rect.end.y):
			ring.append(Vector2i(rect.position.x - 1, ty))
			ring.append(Vector2i(rect.end.x, ty))
	for t in ring:
		if not SimPath.walkable(world, t.x, t.y):
			continue
		if SimTileMap.tile_at(world.tilemap, t.x, t.y) == SimTileMap.Tile.Low:
			continue
		if not world.body_fits_at(float(t.x) + 0.5, float(t.y) + 0.5):
			continue
		return t
	return null


static func _pin_driver(world: Variant, actor: int, vpos: Dictionary, v: Dictionary = {}) -> void:
	var pos: Variant = world.components.get_component(actor, "position")
	if pos is Dictionary:
		(pos as Dictionary)["x"] = float(vpos.get("x", 0.0))
		(pos as Dictionary)["y"] = float(vpos.get("y", 0.0))
	var vel: Variant = world.components.get_component(actor, "velocity")
	if vel is Dictionary:
		(vel as Dictionary)["dx"] = 0.0
		(vel as Dictionary)["dy"] = 0.0
	# A rider faces the way the machine points: the pinned velocity is zero, so nothing else
	# would turn the pawn drawn on an open vehicle, and a bicycle ridden west with its rider
	# facing east is a picture contradicting itself.
	if not v.is_empty():
		var facing: Variant = world.components.get_component(actor, "facing")
		if facing is Dictionary and HEADINGS.has(String(v.get("heading", ""))):
			var dir: Vector2 = HEADINGS[String(v.get("heading", ""))] as Vector2
			(facing as Dictionary)["radians"] = atan2(dir.y, dir.x)


# Off the machine where it stands: the rider is released in place (the tile under an open
# vehicle is Low and walkable, so there is nowhere to fall to), the vehicle stops and goes quiet.
# What a grab or a crash does to a rider; a car's driver is never unseated, because a car has
# doors. The body takes no injury from it -- named in docs/23 rather than half-built here.
static func _unseat(world: Variant, entity: int, v: Dictionary, driver: int, why: String) -> void:
	if world.components.has_component(driver, "mounted"):
		world.components.remove(driver, "mounted")
	v["driver"] = NO_DRIVER
	v["intent"] = {"dx": 0.0, "dy": 0.0}
	v["speed"] = 0.0
	v["gear"] = "park"
	v["braking"] = false
	_stop_engine(world, entity)
	world.events.publish({"type": "vehicle.unseated", "entity": entity, "driver": driver, "why": why})


# --- the systems --------------------------------------------------------------------------------

static func _intake(w: Variant) -> void:
	var current: Array = w.commands.current as Array
	if current.is_empty():
		return
	for cmd in current:
		var c: Dictionary = cmd as Dictionary
		var kind: String = String(c.get("type", ""))
		for actor in w.components.query(["controlled", "position"]):
			match kind:
				TOGGLE:
					if w.components.has_component(int(actor), "mounted"):
						dismount(w, int(actor))
					else:
						var near: int = nearest_in_reach(w, int(actor))
						if near != NO_DRIVER:
							mount(w, int(actor), near)
				"move", "wait":
					var m: Variant = w.components.get_component(int(actor), "mounted")
					if not (m is Dictionary):
						continue
					var v: Variant = w.components.get_component(int((m as Dictionary).get("vehicle", NO_DRIVER)), "vehicle")
					if not (v is Dictionary):
						continue
					if kind == "wait":
						(v as Dictionary)["intent"] = {"dx": 0.0, "dy": 0.0}
					else:
						(v as Dictionary)["intent"] = {"dx": float(c.get("dx", 0.0)), "dy": float(c.get("dy", 0.0))}
	# The pin, every tick a command arrived: world's apply-commands wrote the driver's velocity from
	# the move, and a driver's feet do not move the car.
	for actor2 in w.components.query(["mounted", "velocity"]):
		var vel: Dictionary = w.components.get_component(int(actor2), "velocity") as Dictionary
		vel["dx"] = 0.0
		vel["dy"] = 0.0


# The heading an intent asks for, or "" for no intent. Dominant axis; a tie goes to the current
# heading if it is one of the two, so a diagonal keeps the car straight rather than wobbling.
static func wanted_heading(intent: Dictionary, current: String) -> String:
	var dx: float = float(intent.get("dx", 0.0))
	var dy: float = float(intent.get("dy", 0.0))
	if dx == 0.0 and dy == 0.0:
		return ""
	if absf(dx) == absf(dy):
		var hx: String = "e" if dx > 0.0 else "w"
		var hy: String = "s" if dy > 0.0 else "n"
		if current == hx or current == hy:
			return current
		return hy
	if absf(dx) > absf(dy):
		return "e" if dx > 0.0 else "w"
	return "s" if dy > 0.0 else "n"


static func _drive(w: Variant) -> void:
	var map: Variant = w.tilemap
	if map == null:
		return
	for entity in w.components.query(["vehicle", "position", "velocity"]):
		var e: int = int(entity)
		var v: Dictionary = w.components.get_component(e, "vehicle") as Dictionary
		var pos: Dictionary = w.components.get_component(e, "position") as Dictionary
		var vel: Dictionary = w.components.get_component(e, "velocity") as Dictionary
		var driver: int = int(v.get("driver", NO_DRIVER))
		if driver != NO_DRIVER:
			var m: Variant = w.components.get_component(driver, "mounted")
			# A driver who is no longer a driver -- despawned, dead at the wheel, or a component
			# somebody else removed -- releases the car; a corpse is not driving anywhere.
			if not (m is Dictionary) or int((m as Dictionary).get("vehicle", NO_DRIVER)) != e or w.components.has_component(driver, "corpse"):
				if m is Dictionary and int((m as Dictionary).get("vehicle", NO_DRIVER)) == e:
					w.components.remove(driver, "mounted")
				v["driver"] = NO_DRIVER
				v["intent"] = {"dx": 0.0, "dy": 0.0}
				v["speed"] = 0.0
				_stop_engine(w, e)
				continue
			# A rider in the open who has been grabbed is off the machine: the hold pins the body
			# where it is and the pin below would drag it along, so the grab wins and the bike
			# stops under it. A driver behind a door is never on the menu (the shambler skips a
			# cab), so this only ever fires on an open vehicle.
			if not bool((m as Dictionary).get("cab", false)) and w.components.has_component(driver, "grabbed"):
				_unseat(w, e, v, driver, "grabbed")
				continue
		var speed: float = float(v.get("speed", 0.0))
		var heading: String = String(v.get("heading", "n"))
		var moved: bool = false
		var thrown: bool = false
		# Only a car with a driver has a velocity, so only a car with a driver is in this loop --
		# and only then is the class looked up. Looking it up for every parked car every tick was
		# measured at 1.9 ms a tick at 128 (`SimWorldgen.vehicles_of` sorts the whole content
		# tree's keys to answer), which is why a parked car has no engine components at all.
		if driver == NO_DRIVER:
			_stop_engine(w, e)
			continue
		else:
			var drive: Dictionary = drive_of(class_of(w, String(v.get("class", ""))))
			# `running` is whether the thing will go at all under the driver's intent -- a motor
			# turning over, or a rider who can pedal or push it -- and `motor` whether there is a
			# motor turning over to burn anything or to idle out loud.
			var running: bool = can_ride(v, drive)
			var motor: bool = motor_runs(v, drive)
			_set_engine_noise(w, e, drive, running, motor)
			# The gear and the brake lamp, derived here and read by the dashboard: drive is the
			# throttle held along the heading with an engine that runs, neutral is rolling with
			# no throttle (or a dead engine coasting), park is stopped with no throttle; the lamp
			# is any key that is not the heading while the car still moves.
			var gear: String = "park"
			var braking: bool = false
			if drive.is_empty():
				speed = 0.0
			else:
				var brake: float = float(drive["brake"]) * TICK_SECONDS
				var want: String = wanted_heading(v.get("intent", {}) as Dictionary, heading)
				# A dead engine takes no throttle: the car coasts on whatever it had, and the
				# steering below is refused too -- a car that will not run does not turn.
				if not running:
					want = ""
				elif motor:
					# The idle, every tick the motor turns over; the metres are charged below.
					v["fuel"] = maxf(0.0, float(v.get("fuel", 0.0)) - idle_burn(drive) * TICK_SECONDS)
				if want.is_empty():
					speed = maxf(0.0, speed - brake * COAST_FRACTION)
					gear = "neutral" if speed > 0.0 else "park"
				elif want == heading:
					gear = "drive"
					# The class's top under power, the rider's own without it (top_of), the ground's
					# cut and the condition's.
					var cap: float = top_of(v, drive) * w.surface_speed_at(float(pos["x"]), float(pos["y"])) * CONDITION_CAP[condition_band(float(v.get("integrity", 0.0)))]
					speed += float(drive["accel"]) * TICK_SECONDS
					# Over the cap -- a paved car rolling onto grass -- sheds speed at the brake
					# rather than snapping down to it.
					if speed > cap:
						speed = maxf(cap, speed - brake - float(drive["accel"]) * TICK_SECONDS)
				else:
					speed = maxf(0.0, speed - brake)
					braking = speed > 0.0
					gear = "neutral" if speed > 0.0 else "park"
					if speed == 0.0:
						if want == String(OPPOSITE[heading]):
							# Turning round in place covers the same tiles; the record's facing and
							# the picture's flip follow the heading through sync below.
							heading = want
							moved = true
						else:
							var centre: Dictionary = turned_centre(v, pos, want)
							if _rect_clear(w, map, e, turned_footprint(v, pos, want)):
								heading = want
								pos["x"] = float(centre["x"])
								pos["y"] = float(centre["y"])
								moved = true
			v["heading"] = heading
			v["gear"] = gear
			v["braking"] = braking
			if speed > 0.0:
				var dir: Vector2 = HEADINGS[heading] as Vector2
				var ext: Vector2i = extent_of(v, heading)
				var along_axis_x: bool = dir.x != 0.0
				var sign: float = dir.x if along_axis_x else dir.y
				var half: float = float(ext.x if along_axis_x else ext.y) / 2.0
				var along: float = float(pos["x"] if along_axis_x else pos["y"])
				var step: float = speed * TICK_SECONDS
				var front: float = along + sign * half
				var probe: float = front + sign * (step + EPS)
				var probe_tile: int = floori(probe)
				var rect: Rect2i = footprint(v, pos)
				var blocked: bool = false
				if along_axis_x:
					for ty in range(rect.position.y, rect.end.y):
						if tile_blocks(w, map, e, probe_tile, ty):
							blocked = true
							break
				else:
					for tx in range(rect.position.x, rect.end.x):
						if tile_blocks(w, map, e, tx, probe_tile):
							blocked = true
							break
				if blocked:
					# Flush against the tile it cannot enter, and stopped -- and at speed, a crash:
					# the car takes damage on the square of its speed and the field hears the bang.
					var boundary: float = float(probe_tile) if sign > 0.0 else float(probe_tile + 1)
					along = boundary - sign * half
					var class_cap: float = float(drive.get("speed", 0.0)) if not drive.is_empty() else 0.0
					var damage: float = crash_damage(speed, class_cap)
					if damage > 0.0:
						var before: float = float(v.get("integrity", 0.0))
						v["integrity"] = maxf(0.0, before - damage)
						w.events.publish({"type": "vehicle.crashed", "entity": e, "speed": speed, "damage": damage})
						w.events.publish({"type": "noise.emitted", "x": float(pos["x"]), "y": float(pos["y"]), "magnitude": crash_noise(speed, class_cap), "source": e})
						if before > 0.0 and float(v["integrity"]) <= 0.0:
							w.events.publish({"type": "vehicle.wrecked", "entity": e})
						# Over the handlebars: a crash that costs the machine anything puts a rider
						# in the open off it. The car's driver stays in the seat.
						var mm: Variant = w.components.get_component(driver, "mounted")
						if mm is Dictionary and not bool((mm as Dictionary).get("cab", false)):
							thrown = true
					speed = 0.0
				else:
					along += sign * step
					# The metres, charged only to a running engine: a dead one coasting is free.
					if running:
						v["fuel"] = maxf(0.0, float(v.get("fuel", 0.0)) - move_burn(drive) * step)
				if along_axis_x:
					pos["x"] = along
				else:
					pos["y"] = along
				moved = true
		v["speed"] = speed
		var dir2: Vector2 = HEADINGS[heading] as Vector2
		vel["dx"] = dir2.x * speed
		vel["dy"] = dir2.y * speed
		var facing: Variant = w.components.get_component(e, "facing")
		if facing is Dictionary:
			(facing as Dictionary)["radians"] = atan2(dir2.y, dir2.x)
		if moved:
			_sync_one(w, map, e, v, pos)
		if driver != NO_DRIVER:
			_pin_driver(w, driver, pos, v)
			if thrown:
				_unseat(w, e, v, driver, "crashed")


# The shadow of one car after it moved: the record's ground point every time, the tiles and the
# record's rectangle only when the footprint's tiles actually changed -- a car crossing a tile
# rewrites a dozen tiles and bumps the map generation, and a car mid-tile rewrites nothing.
static func _sync_one(w: Variant, map: Variant, entity: int, v: Dictionary, pos: Dictionary) -> void:
	var records: Variant = map.get("vehicles")
	if not (records is Array):
		sync_map(w)
		return
	var rect: Rect2i = footprint(v, pos)
	for i in (records as Array).size():
		var rec: Variant = (records as Array)[i]
		if not (rec is Dictionary):
			continue
		var r: Dictionary = rec as Dictionary
		if int(r.get("entity", NO_DRIVER)) != entity:
			continue
		var old: Rect2i = _rect_of_record(r)
		var fresh: Dictionary = _record_for(entity, v, pos, rect)
		if old == rect and String(r.get("facing", "")) == String(fresh["facing"]):
			r["gx"] = fresh["gx"]
			r["gy"] = fresh["gy"]
			return
		_clear_tiles(map, old)
		_write_tiles(map, rect)
		(records as Array)[i] = fresh
		map.vehicle_generation = int(map.vehicle_generation) + 1
		w.invalidateMap()
		return
	# No record for this entity yet -- a car spawned by hand -- so build the whole shadow.
	sync_map(w)


# --- read models --------------------------------------------------------------------------------

# One prose line for the HUD about the car beside you or under you, or "" when there is neither.
# Words only (the HUD gate allows no digits): the class's own name and the key.
static func hud_clause(world: Variant, actor: int) -> String:
	var m: Variant = world.components.get_component(actor, "mounted")
	if m is Dictionary:
		var v: Variant = world.components.get_component(int((m as Dictionary).get("vehicle", NO_DRIVER)), "vehicle")
		if v is Dictionary:
			var entry: Dictionary = class_of(world, String((v as Dictionary).get("class", "")))
			var drive: Dictionary = drive_of(entry)
			var name: String = String(entry.get("name", "car")).to_lower()
			var out: String = "E to get out" if has_cab(entry) else "E to get off"
			var verb: String = "driving" if has_cab(entry) else "riding"
			var seat: String = seat_phrase(entry)
			if float((v as Dictionary).get("speed", 0.0)) > 0.0:
				return "%s the %s; %s once it stops" % [verb, name, out]
			if condition_band(float((v as Dictionary).get("integrity", 0.0))) == 0:
				if power_of(drive) == POWER_ENGINE:
					return "%s the %s; the engine is wrecked and will not turn over; %s" % [seat, name, out]
				return "%s the %s; the frame is wrecked and it goes nowhere; %s" % [seat, name, out]
			match power_of(drive):
				POWER_ENGINE:
					if float((v as Dictionary).get("fuel", 0.0)) <= 0.0:
						return "%s the %s; the tank is dry; %s" % [seat, name, out]
					return "%s the %s, engine running; %s" % [seat, name, out]
				POWER_BATTERY:
					if float((v as Dictionary).get("fuel", 0.0)) <= 0.0:
						return "%s the %s; the battery is flat, so it is legs from here; %s" % [seat, name, out]
					return "%s the %s, battery humming; %s" % [seat, name, out]
			return "%s the %s; %s" % [seat, name, out]
		return ""
	# A hood you have just looked under outranks the car beside you for as long as the report
	# lasts; then the kerb clauses come back.
	var report: Dictionary = hood_report(world, actor)
	if not report.is_empty():
		return String(report.get("prose", ""))
	var near: int = nearest_in_reach(world, actor)
	if near == NO_DRIVER:
		return ""
	var nv: Dictionary = world.components.get_component(near, "vehicle") as Dictionary
	var near_entry: Dictionary = class_of(world, String(nv.get("class", "")))
	var near_name: String = String(near_entry.get("name", "car")).to_lower()
	if at_hood(world, actor, near):
		if has_cab(near_entry):
			return "the %s's hood before you; E to look under it" % near_name
		return "a %s before you; E to look it over" % near_name
	if has_cab(near_entry):
		return "a %s beside you; E to get in" % near_name
	return "a %s beside you; E to get on" % near_name


# Where the body is, in the class's own words: a car has a wheel, a bicycle a saddle, a board
# is stood on. Picked by the dash layout, which is the same distinction drawn.
static func seat_phrase(entry: Dictionary) -> String:
	match dash_layout(entry):
		"cluster":
			return "at the wheel of"
		"handlebar":
			return "in the saddle of"
	return "standing on"
