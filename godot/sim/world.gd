class_name SimWorld
extends RefCounted

const EntityStore = preload("res://sim/entity_store.gd")
const ComponentStore = preload("res://sim/component_store.gd")
const CommandQueue = preload("res://sim/command_queue.gd")
const RngStream = preload("res://sim/rng_stream.gd")
const SystemRegistry = preload("res://sim/system_registry.gd")

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

var entities = EntityStore.new()
var components = ComponentStore.new()
var commands = CommandQueue.new()
var systems = SystemRegistry.new()


func _init(fixture: Dictionary) -> void:
	seed = int(fixture["seed"])
	assert(int(fixture["tick_hz"]) == TICK_HZ, "Fixture tick rate differs from the simulation")
	_build_map(fixture["map"])
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
		var timed: Dictionary = command_value
		var at_tick := int(timed["tick"])
		var command := timed.duplicate(true)
		command.erase("tick")
		if not by_tick.has(at_tick):
			by_tick[at_tick] = []
		(by_tick[at_tick] as Array).append(command)

	for next_tick in range(1, int(fixture["ticks"]) + 1):
		for command_value: Variant in by_tick.get(next_tick, []):
			commands.push(command_value)
		step()

	return parity_snapshot(fixture)


func parity_snapshot(fixture: Dictionary) -> Dictionary:
	var position: Dictionary = components.get_component(player, "position")
	var velocity: Dictionary = components.get_component(player, "velocity")
	var posture: Dictionary = components.get_component(player, "posture")
	var probe_fixture: Dictionary = fixture["rng_probe"]
	var stream_name := String(probe_fixture["stream"])
	var probe = RngStream.new(RngStream.derive_seed(seed, stream_name))
	var samples: Array[float] = []
	for _index in int(probe_fixture["samples"]):
		samples.append(probe.next())

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
		"rng": {"stream": stream_name, "samples": samples, "state": probe.save()},
	}


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
		var wall: Dictionary = wall_value
		map_cells[int(wall["y"]) * map_width + int(wall["x"])] = 1


func _apply_commands(_world: Variant) -> void:
	if commands.current.is_empty():
		return
	for entity in components.query(["position", "velocity", "controlled"]):
		var velocity: Dictionary = components.get_component(entity, "velocity")
		var posture: Dictionary = components.get_component(entity, "posture")
		for command in commands.current:
			match String(command["type"]):
				"move":
					var dx := float(command["dx"])
					var dy := float(command["dy"])
					var length := sqrt(dx * dx + dy * dy)
					if length == 0.0:
						velocity["dx"] = 0.0
						velocity["dy"] = 0.0
						continue
					var stance := int(posture["current"])
					var speed := WALK_SPEED * STANCE_FACTORS[stance]
					velocity["dx"] = dx / length * speed
					velocity["dy"] = dy / length * speed
				"wait":
					velocity["dx"] = 0.0
					velocity["dy"] = 0.0


func _integrate_movement(_world: Variant) -> void:
	for entity in components.query(["position", "velocity"]):
		var position: Dictionary = components.get_component(entity, "position")
		var velocity: Dictionary = components.get_component(entity, "velocity")
		var dx := float(velocity["dx"])
		var dy := float(velocity["dy"])
		if dx == 0.0 and dy == 0.0:
			continue

		var nx := float(position["x"]) + dx * TICK_SECONDS
		if not _blocked_at(nx + _sign(dx) * BODY_RADIUS, float(position["y"]) - BODY_RADIUS) \
				and not _blocked_at(nx + _sign(dx) * BODY_RADIUS, float(position["y"]) + BODY_RADIUS):
			position["x"] = nx
		else:
			velocity["dx"] = 0.0

		var ny := float(position["y"]) + dy * TICK_SECONDS
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
