class_name SimWorld
extends RefCounted

const EntityStore = preload("res://sim/entity_store.gd")
const ComponentStore = preload("res://sim/component_store.gd")
const CommandQueue = preload("res://sim/command_queue.gd")
const RngStream = preload("res://sim/rng_stream.gd")
const RngRegistry = preload("res://sim/rng_registry.gd")
const SystemRegistry = preload("res://sim/system_registry.gd")
const EventBus = preload("res://sim/event_bus.gd")
const SimStatsRes = preload("res://sim/modifiers/stats.gd")
const SimModifiersRes = preload("res://sim/modifiers/modifiers.gd")
const ContentLoader = preload("res://platform/content_loader.gd")
const AttentionFieldRes = preload("res://sim/field/attention.gd")
const SimTileMapRes = preload("res://sim/map/tilemap.gd")
const SimSurfaceRes = preload("res://sim/map/surface.gd")
const SimSerialize = preload("res://sim/kernel/serialize.gd")
const SimFortifyRes = preload("res://sim/modules/fortify.gd")
const SimStancesRes = preload("res://sim/stances.gd")

const TICK_HZ: int = 20
const TICK_SECONDS: float = 1.0 / TICK_HZ
const BODY_RADIUS: float = 0.35
const WALK_SPEED: float = 2.1
# Per-rung speed multiplier used to live here as a verbatim duplicate of SimStances.SPEED_FACTOR
# -- one const, one caller (world.gd:_apply_commands), zero reason for two copies to drift.

var tick: int = 0
var seed: int
var map_width: int
var map_height: int
var map_cells: Array[int] = []
var player: int
var mapGeneration: int = 0
var tilemap: Variant = null
var vision: Variant = null
var light: Variant = null

var map_generation: int:
	get:
		return mapGeneration
	set(v):
		mapGeneration = v

var content: Variant = null
var entities: Variant = null
var components: Variant = null
var commands: Variant = null
var systems: Variant = null
var rng: Variant = null
var stats: Variant = null
var modifiers: Variant = null
var field: Variant = null
var events: Variant = null
var director: Dictionary = {"lullUntilTick": 0, "lastMigrationTick": 0, "nightsSinceQuiet": 0}
var needsHoldMax: bool = false
var runOver: bool = false
var recruits: Dictionary = {"accepted": 0, "spawned": []}


func _init(fixture: Dictionary) -> void:
	# Content: fixture may carry inline or world loads canonical tree. Stored on world for SimItems/SimInventory.
	if fixture.has("content_tree") and fixture["content_tree"] is Dictionary:
		content = fixture["content_tree"]
	else:
		content = ContentLoader.load_tree()
	seed = int(fixture["seed"])
	assert(int(fixture["tick_hz"]) == TICK_HZ, "Fixture tick rate differs from the simulation")
	entities = EntityStore.new()
	components = ComponentStore.new()
	commands = CommandQueue.new()
	systems = SystemRegistry.new()
	events = EventBus.new()
	stats = SimStatsRes.new()
	SimStatsRes.define_core_stats(stats)
	modifiers = SimModifiersRes.new(stats)
	rng = RngRegistry.new(seed)
	# Field: empty until sized to a map. R1 fixtures still need one for snapshot shape.
	field = AttentionFieldRes.empty_field()
	_build_map(fixture["map"])
	# Re-size field to the fixture map so its save has correct cols/rows.
	# Populate a TileMap so the attention field's solid mask matches the sim walls,
	# not a blank floor (otherwise noise leaks through walls in parity).
	var mmap: Variant = SimTileMapRes.blank_map(map_width, map_height)
	for y in map_height:
		for x in map_width:
			var blocked: bool = is_blocked_tile(x, y)
			(mmap as Variant).tiles[y * int((mmap as Variant).w) + x] = int(SimTileMapRes.Tile.Wall) if blocked else int(SimTileMapRes.Tile.Floor)
	field = AttentionFieldRes.for_map(mmap)
	player = entities.spawn()
	var player_fixture: Dictionary = fixture["player"]
	assert(player == int(player_fixture["id"]), "Fixture entity identity changed")
	components.set_component(player, "position", {
		"x": float(player_fixture["x"]),
		"y": float(player_fixture["y"]),
	})
	components.set_component(player, "velocity", {"dx": 0.0, "dy": 0.0})
	components.set_component(player, "controlled", {})
	components.set_component(player, "posture", SimStancesRes.make_posture(int(player_fixture["stance"])))

	systems.register("player.apply-commands", "input", 0, _apply_commands)
	# Order 1: after apply-commands enqueues a stance request, before movement reads the
	# rung that request may just have changed. This is what makes a stance change *take
	# time* rather than snap -- hardcore-contract clause 2 -- and it is where the ladder's
	# stamina drain (SimStances.drain_per_tick) is published, not mutated in place, so
	# health.gd's stamina.spent channel stays the one writer of the pool.
	systems.register("player.advance-posture", "input", 1, _advance_posture)
	systems.register("movement.integrate", "movement", 0, _integrate_movement)


func step() -> void:
	tick += 1
	var eb: Variant = events as RefCounted
	eb.call("clear_record")
	commands.take(tick)
	systems.run(self)
	eb.call("drain")


func run_fixture(fixture: Dictionary) -> Dictionary:
	var by_tick: Dictionary = {}
	for command_value: Variant in fixture["commands"]:
		var timed: Dictionary = command_value as Dictionary
		var at_tick: int = int(timed["tick"])
		var command: Dictionary = timed.duplicate(true)
		command.erase("tick")
		if not by_tick.has(at_tick):
			by_tick[at_tick] = []
		(by_tick[at_tick] as Array).append(command)

	for next_tick in range(1, int(fixture["ticks"]) + 1):
		for command_value: Variant in by_tick.get(next_tick, []):
			commands.push(command_value as Dictionary)
		step()

	return parity_snapshot(fixture)


func parity_snapshot(fixture: Dictionary) -> Dictionary:
	var position: Dictionary = components.get_component(player, "position") as Dictionary
	var velocity: Dictionary = components.get_component(player, "velocity") as Dictionary
	var posture: Dictionary = components.get_component(player, "posture") as Dictionary
	var probe_fixture: Dictionary = fixture["rng_probe"] as Dictionary
	var stream_name: String = String(probe_fixture["stream"])
	var probe: Variant = RngStream.new(RngStream.derive_seed(seed, stream_name))
	var samples: Array[float] = []
	for _index in int(probe_fixture["samples"]):
		samples.append(float((probe as RefCounted).call("next")))

	return {
		"contract": String(fixture["contract"]),
		"tick": tick,
		"seed": seed,
		"player": {
			"id": player,
			"position": {"x": position["x"], "y": position["y"]},
			"velocity": {"dx": velocity["dx"], "dy": velocity["dy"]},
			"stance": posture["current"],
		},
		"commands": commands.recorded,
		"rng": {"stream": stream_name, "samples": samples, "state": (probe as RefCounted).call("save")},
	}


# Scalars only: ints, floats, bools and strings. A component or a callable in here would not
# survive JSON and would not be a director dial either.
func _scalars(source: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in source.keys():
		var v: Variant = source[k]
		if v is int or v is float or v is bool or v is String:
			out[String(k)] = v
	return out


func snapshot() -> Dictionary:
	return {
		"version": int(SimSerialize.SAVE_VERSION),
		"tick": tick,
		"seed": seed,
		"rng": (rng as RefCounted).call("save"),
		"entities": (entities as RefCounted).call("save"),
		"components": (components as RefCounted).call("save"),
		"modifiers": (modifiers as RefCounted).call("save"),
		"field": (field as RefCounted).call("save"),
		# Whatever the director module put here, rather than a hand-listed subset of it. The
		# subset had already drifted: `lullFromTick` and `weekPeakNoise` were both being written
		# every night and dropped by every save, so a restored colony forgot when its lull began
		# and how loud its week had been. `SimDirector.snapshot_of` existed to prevent exactly
		# that and was called by nothing. This stays module-agnostic -- world.gd must not depend
		# on a module -- and copies scalars only, so a future key is saved without world.gd
		# learning what it means.
		"director": _scalars(director),
		"recruits": {
			"accepted": int(recruits.get("accepted", 0)),
			"spawned": (recruits.get("spawned", []) as Array).duplicate(),
		},
		"runOver": runOver,
		"player": int(player),
	}


func restore(snap: Dictionary) -> void:
	assert(int(snap["version"]) == int(SimSerialize.SAVE_VERSION), "Save version %s != %s" % [snap["version"], SimSerialize.SAVE_VERSION])
	assert(int(snap["seed"]) == seed, "Save seed %s != world seed %s" % [snap["seed"], seed])
	tick = int(snap["tick"])
	(rng as RefCounted).call("restore", snap["rng"])
	(entities as RefCounted).call("restore", snap["entities"])
	(components as RefCounted).call("restore", snap["components"])
	(modifiers as RefCounted).call("restore", snap["modifiers"])
	(field as RefCounted).call("restore", snap["field"])
	if snap.has("director") and snap["director"] is Dictionary:
		# Merged over what is already there rather than replacing it, so a key the module set at
		# registration and an older save never heard of keeps its default instead of vanishing.
		for k in (snap["director"] as Dictionary).keys():
			director[String(k)] = (snap["director"] as Dictionary)[k]
	if snap.has("recruits") and snap["recruits"] is Dictionary:
		var r: Dictionary = snap["recruits"] as Dictionary
		recruits = {
			"accepted": int(r.get("accepted", 0)),
			"spawned": (r.get("spawned", []) as Array).duplicate(),
		}
	runOver = bool(snap.get("runOver", false))
	if snap.has("player"):
		player = int(snap["player"])
	elif components != null:
		# Pre-0013 saves: rebind from controlled.
		for e in components.query(["controlled"]):
			player = int(e)
			break
	if tilemap != null:
		SimFortifyRes.sync_map(self)


func serialize() -> String:
	return SimSerialize.canonicalize(snapshot())


func despawn(entity: int) -> bool:
	var ok: bool = bool((entities as RefCounted).call("destroy", entity))
	if not ok:
		return false
	(components as RefCounted).call("removeAll", entity)
	# `remove_scope`, not `removeScope`. The guard used to name the camelCase spelling, which no
	# script method has, so `has_method` was false on every despawn and the whole line was a
	# no-op for as long as it existed: every dead zombie's affix and wound modifiers stayed in
	# `_entries`, went into every save, and left `_invalidate(GLOBAL, ...)` scanning a `_cache`
	# that only ever grew. A `has_method` guard naming a method that does not exist is the
	# `vel["x"]` trap in another costume -- it raises nothing and does nothing.
	if modifiers != null and (modifiers as Object).has_method("remove_scope"):
		(modifiers as RefCounted).call("remove_scope", entity)
	return true

func invalidateMap() -> void:
	mapGeneration += 1


func adopt_map(map: Variant) -> void:
	# Rebuild blocking + attention field from a real TileMap (district overlay).
	# Not called from _init — R1 fixtures stay on the wall-list path.
	tilemap = map
	map_width = int(map.w)
	map_height = int(map.h)
	map_cells.resize(map_width * map_height)
	for y in map_height:
		for x in map_width:
			map_cells[y * map_width + x] = 1 if SimTileMapRes.is_solid(map, x, y) else 0
	field = AttentionFieldRes.for_map(map)
	invalidateMap()


func is_blocked_tile(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= map_width or y >= map_height:
		return true
	return map_cells[y * map_width + x] == 1


# How fast the ground here lets a body move, as the multiplier docs/24 tables: ×1.0 paved,
# ×0.6 undergrowth, and the three in between. Metres in, multiplier out, so the caller does
# not have to know that surfaces are indexed by tile.
#
# A world with no TileMap has no surface array to read -- every R1 parity fixture is built
# from `_build_map`'s wall list and never adopts one -- and answers exactly 1.0, which is why
# wiring this in did not move the frozen fixture by a float. Not a legacy path: the same
# answer is correct for a body standing off the edge of a real map, where
# `SimSurface.surface_at` returns Paved for the same reason.
func surface_speed_at(x: float, y: float) -> float:
	if tilemap == null:
		return 1.0
	var tx: int = floori(x / float(SimTileMapRes.TILE_METRES))
	var ty: int = floori(y / float(SimTileMapRes.TILE_METRES))
	return SimSurfaceRes.speed_on(SimSurfaceRes.surface_at(tilemap, tx, ty))


func _build_map(map_fixture: Dictionary) -> void:
	map_width = int(map_fixture["width"])
	map_height = int(map_fixture["height"])
	map_cells.resize(map_width * map_height)
	map_cells.fill(0)
	for x in map_width:
		map_cells[x] = 1
		map_cells[(map_height - 1) * map_width + x] = 1
	for y in map_height:
		map_cells[y * map_width] = 1
		map_cells[y * map_width + map_width - 1] = 1
	for wall_value: Variant in map_fixture["walls"]:
		var wall: Dictionary = wall_value as Dictionary
		map_cells[int(wall["y"]) * map_width + int(wall["x"])] = 1


func _apply_commands(_world: Variant) -> void:
	if (commands as Variant).current.is_empty():
		return
	for entity in (components as RefCounted).call("query", ["position", "velocity", "controlled"]) as Array:
		var velocity: Dictionary = components.get_component(int(entity), "velocity") as Dictionary
		var posture: Dictionary = components.get_component(int(entity), "posture") as Dictionary
		var body_pos: Dictionary = components.get_component(int(entity), "position") as Dictionary
		for command in (commands as Variant).current as Array:
			match String((command as Dictionary)["type"]):
				"move":
					var dx: float = float((command as Dictionary)["dx"])
					var dy: float = float((command as Dictionary)["dy"])
					var length: float = sqrt(dx * dx + dy * dy)
					if length == 0.0:
						velocity["dx"] = 0.0
						velocity["dy"] = 0.0
						continue
					var stance: int = int(posture["current"])
					var speed: float = WALK_SPEED * SimStancesRes.SPEED_FACTOR[stance]
					# The ground you are standing on, beside the rung you are on: docs/24's
					# surface table, ×1.0 on paved down to ×0.6 through undergrowth. Sampled
					# here rather than at integration so it sits with the other two multipliers
					# and answers the same question they do -- how fast is this body allowed to
					# go this tick. Noise deliberately does *not* follow it (docs/30): emission
					# reads the rung, so wading into undergrowth slows you without quieting you.
					speed *= surface_speed_at(float(body_pos["x"]), float(body_pos["y"]))
					if modifiers != null and (modifiers as Object).has_method("resolve"):
						speed *= float(modifiers.call("resolve", "move_speed", int(entity)))
					velocity["dx"] = dx / length * speed
					velocity["dy"] = dy / length * speed
				"wait":
					velocity["dx"] = 0.0
					velocity["dy"] = 0.0
				"aim":
					# Presentation proposes a facing; the sim decides whether it takes. Only a
					# stationary body turns to aim -- movement.integrate derives facing from
					# velocity, so a moving one faces where it goes and the proposal is simply
					# ignored. That is the hardcore rule, not a compromise: you do not track a
					# target over your shoulder at a jog. Checked against the velocity this same
					# command list may just have written, so a move and an aim on one tick agree.
					if float(velocity["dx"]) == 0.0 and float(velocity["dy"]) == 0.0:
						var aim_facing: Variant = components.get_component(int(entity), "facing")
						if aim_facing is Dictionary:
							(aim_facing as Dictionary)["radians"] = float((command as Dictionary).get("radians", 0.0))
				"shout":
					var pos: Dictionary = components.get_component(int(entity), "position") as Dictionary
					events.publish({
						"type": "noise.emitted",
						"x": float(pos["x"]),
						"y": float(pos["y"]),
						"magnitude": 120.0,
						"source": int(entity)
					})
				"stance":
					# Presentation only ever pushes the command (main.gd:_push_stance) -- this is
					# the one place a stance request actually lands on posture. Out-of-range is
					# silently ignored rather than asserted: a malformed replay log should not
					# crash R1 parity, it should just do nothing.
					var target: int = int((command as Dictionary)["stance"])
					if target < 0 or target > SimStancesRes.Stance.Sprint:
						continue
					if target == SimStancesRes.Stance.Sprint:
						# Zero-stamina gate: refuse to *request* a sprint on an empty tank.
						# Walking and melee (which does its own refusal) stay possible.
						var sprint_stamina: Variant = components.get_component(int(entity), "stamina")
						if sprint_stamina is Dictionary and float((sprint_stamina as Dictionary)["current"]) <= 0.0:
							continue
					SimStancesRes.request_stance(posture, target)


# Advances every posture toward its requested target and pays for the ladder's upper rungs
# out of stamina. Iterates components.query(["posture"]) rather than just the player, so NPCs
# (unique survivors, generated survivors) get the same transition delay and drain the moment
# they carry a posture -- posture is not a player-only component.
func _advance_posture(_world: Variant) -> void:
	for entity in (components as RefCounted).call("query", ["posture"]) as Array:
		var posture: Dictionary = components.get_component(int(entity), "posture") as Dictionary
		if int(posture["ticks_left"]) > 0:
			posture["ticks_left"] = int(posture["ticks_left"]) - 1
			if int(posture["ticks_left"]) == 0:
				posture["current"] = posture["target"]
		var stamina: Variant = components.get_component(int(entity), "stamina")
		if not (stamina is Dictionary):
			continue
		var st: Dictionary = stamina as Dictionary
		# Zero-stamina demotion: an in-progress or already-completed sprint that drains the
		# pool to empty mid-run gets knocked down to Jog rather than left sprinting for free.
		# request_stance is not reused here -- this is an involuntary drop, not a request, so
		# it lands immediately with no transition delay.
		if int(posture["current"]) == SimStancesRes.Stance.Sprint and float(st["current"]) <= 0.0:
			posture["current"] = SimStancesRes.Stance.Jog
			posture["target"] = SimStancesRes.Stance.Jog
			posture["ticks_left"] = 0
			# Published, not acted on. docs/05 lists exhaustion as a cause of sprains and
			# wounds.gd is what turns this into one; world.gd must not grow a dependency on a
			# module, so the collapse is announced and whoever cares subscribes.
			events.publish({"type": "stance.collapsed", "entity": int(entity), "from": SimStancesRes.Stance.Sprint})
		var drain: float = SimStancesRes.drain_per_tick(int(posture["current"]))
		# You are not jogging inside a grapple. A held body's posture is whatever it was when the
		# hands closed, and shambler.pin already refuses it a step, so the ladder's drain is
		# charging for locomotion that is not happening. Left in, it also silently cancels the
		# held-body regen exemption in health.recover: the drain publishes stamina.spent every
		# single tick, and every stamina.spent re-arms ticksUntilRecovery, so a survivor grabbed
		# mid-jog would regenerate nothing, forever, and the exemption would read as if it worked.
		if drain > 0.0 and not components.has_component(int(entity), "grabbed"):
			# Publish, don't mutate: stamina.spent is the one write channel (health.gd) and
			# it resets ticksUntilRecovery, which is what makes exertion pause recovery.
			events.publish({"type": "stamina.spent", "entity": int(entity), "amount": drain})


func _integrate_movement(_world: Variant) -> void:
	for entity in (components as RefCounted).call("query", ["position", "velocity"]) as Array:
		var position: Dictionary = components.get_component(int(entity), "position") as Dictionary
		var velocity: Dictionary = components.get_component(int(entity), "velocity") as Dictionary
		var dx: float = float(velocity["dx"])
		var dy: float = float(velocity["dy"])
		if dx == 0.0 and dy == 0.0:
			continue
		if components.has_component(int(entity), "facing"):
			var facing: Dictionary = components.get_component(int(entity), "facing") as Dictionary
			facing["radians"] = atan2(dy, dx)

		var nx: float = float(position["x"]) + dx * TICK_SECONDS
		if not _blocked_at(nx + _sign(dx) * BODY_RADIUS, float(position["y"]) - BODY_RADIUS) \
				and not _blocked_at(nx + _sign(dx) * BODY_RADIUS, float(position["y"]) + BODY_RADIUS):
			position["x"] = nx
		else:
			velocity["dx"] = 0.0

		var ny: float = float(position["y"]) + dy * TICK_SECONDS
		if not _blocked_at(float(position["x"]) - BODY_RADIUS, ny + _sign(dy) * BODY_RADIUS) \
				and not _blocked_at(float(position["x"]) + BODY_RADIUS, ny + _sign(dy) * BODY_RADIUS):
			position["y"] = ny
		else:
			velocity["dy"] = 0.0


func _blocked_at(x: float, y: float) -> bool:
	return is_blocked_tile(floori(x), floori(y))


# Whether a body of BODY_RADIUS centred here has room to stand. This is a different question from
# the one _integrate_movement asks: that one tests the two leading corners of the axis it is about
# to move along, because it is deciding "may I take this step". This tests the whole footprint,
# because callers use it to ask "is there anywhere over there" about a point the body is not at
# yet. Conservative by construction -- a footprint that fits here would also have passed either
# axis test -- which is the safe direction for a probe.
#
# Public because SimShambler._break_away picks its heading with it, and a sim module must not
# reach into world's privates to do collision maths that lives here.
func body_fits_at(x: float, y: float) -> bool:
	return not _blocked_at(x - BODY_RADIUS, y - BODY_RADIUS) \
			and not _blocked_at(x + BODY_RADIUS, y - BODY_RADIUS) \
			and not _blocked_at(x - BODY_RADIUS, y + BODY_RADIUS) \
			and not _blocked_at(x + BODY_RADIUS, y + BODY_RADIUS)


func _sign(value: float) -> float:
	if value > 0.0:
		return 1.0
	if value < 0.0:
		return -1.0
	return 0.0
