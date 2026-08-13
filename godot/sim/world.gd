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
const SimSerialize = preload("res://sim/kernel/serialize.gd")

const TICK_HZ: int = 20
const TICK_SECONDS: float = 1.0 / TICK_HZ
const BODY_RADIUS: float = 0.35
const WALK_SPEED: float = 2.1
const STANCE_FACTORS: Array[float] = [0.25, 0.5, 1.0, 1.8, 3.0]

var tick: int = 0
var seed: int
var map_width: int
var map_height: int
var map_cells: Array[int] = []
var player: int
var mapGeneration: int = 0

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
	components.set_component(player, "posture", {"current": int(player_fixture["stance"])})

	systems.register("player.apply-commands", "input", 0, _apply_commands)
	systems.register("movement.integrate", "movement", 0, _integrate_movement)


func step() -> void:
	tick += 1
	commands.take(tick)
	systems.run(self)


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


func serialize() -> String:
	return SimSerialize.canonicalize(snapshot())


func invalidateMap() -> void:
	mapGeneration += 1


func is_blocked_tile(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= map_width or y >= map_height:
		return true
	return map_cells[y * map_width + x] == 1


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
					var speed: float = WALK_SPEED * STANCE_FACTORS[stance]
					velocity["dx"] = dx / length * speed
					velocity["dy"] = dy / length * speed
				"wait":
					velocity["dx"] = 0.0
					velocity["dy"] = 0.0


func _integrate_movement(_world: Variant) -> void:
	for entity in (components as RefCounted).call("query", ["position", "velocity"]) as Array:
		var position: Dictionary = components.get_component(int(entity), "position") as Dictionary
		var velocity: Dictionary = components.get_component(int(entity), "velocity") as Dictionary
		var dx: float = float(velocity["dx"])
		var dy: float = float(velocity["dy"])
		if dx == 0.0 and dy == 0.0:
			continue

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


func _sign(value: float) -> float:
	if value > 0.0:
		return 1.0
	if value < 0.0:
		return -1.0
	return 0.0
