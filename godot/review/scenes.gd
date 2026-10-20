extends RefCounted
# The fixed scenes the screenshot review captures, and the one boot every scene starts from.
#
# `review/shots.gd` photographs these and `check_shots.gd` judges them, and both call the same
# functions here: the gate checks the setups the driver really makes, not a copy of them. Every
# scene boots a fresh `main.tscn` through real key presses (the title, the legend), then sets the
# world up through the sim's own commands and clock, and `verify` asks the world whether the
# setup is what the scene's name says. A scene the world does not match is refused rather than
# photographed, so a before/after pair cannot silently compare two different states.
#
# The capture itself is the one `check_shots.gd` skips without a display: `root.get_texture()`
# is empty under `--headless`, so the pixels need `DISPLAY` (AGENTS.md, "Screenshots").

const Clock = preload("res://sim/time/clock.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")

const SCENE_PATH: String = "res://presentation/main.tscn"
# The two windows the game supports: check_play's WORK-LAYOUT lane lays out at both.
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080)]
const NAMES: Array[String] = ["day_street", "interior", "night_lights", "combat", "inventory"]

const TICK_SECONDS: float = 1.0 / 20.0
const DAY: int = 1
const NOON: float = 0.5
const NIGHT: float = 0.9
# A zombie is placed this many metres east of the body, close enough to read as a fight in frame.
const ZOMBIE_METRES: float = 3.0
const ZOMBIE_ID: String = "zombie.base"
# How far from the body the verifier looks for the zombie it asked for.
const ZOMBIE_NEAR: float = 4.5
# How far the interior search walks from the body, in tiles.
const SEARCH_TILES: int = 40


## Boot a fresh main scene the way a player reaches the street: the title takes Enter, the
## legend takes Escape. Returns null when the scene does not come up with a world.
static func boot(tree: SceneTree) -> Node:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		return null
	var main: Node = packed.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	if main.get("world") == null:
		main.queue_free()
		return null
	main.set_process(false)
	main.set("accumulator", 0.0)
	var shell: Variant = main.get("_shell")
	if shell != null and bool((shell as CanvasItem).visible):
		press(tree, KEY_ENTER)
		await tree.process_frame
	var legend: Variant = main.get("_legend")
	if legend != null and bool((legend as CanvasItem).visible):
		press(tree, KEY_ESCAPE)
		await tree.process_frame
	main.set("accumulator", 0.0)
	return main


## One real key press, down and up, through the viewport's own dispatch.
static func press(tree: SceneTree, code: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.physical_keycode = code
	down.pressed = true
	tree.root.push_input(down)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	tree.root.push_input(up)


## Set up the named scene on a booted `main`. Returns "" on success, or the reason it could not.
static func setup(tree: SceneTree, main: Node, scene: String) -> String:
	var world: Variant = main.get("world")
	if world == null:
		return "no world"
	match scene:
		"day_street":
			world.tick = Clock.tick_on_day(DAY, NOON)
		"night_lights":
			world.tick = Clock.tick_on_day(DAY, NIGHT)
		"interior":
			world.tick = Clock.tick_on_day(DAY, NOON)
			var spot: Vector2 = _interior_spot(world)
			if spot.x < 0.0:
				return "no floor with a wall beside it within %d tiles" % SEARCH_TILES
			world.components.set_component(world.player, "position", {"x": spot.x, "y": spot.y})
		"combat":
			world.tick = Clock.tick_on_day(DAY, NOON)
			var at: Dictionary = world.components.get_component(world.player, "position") as Dictionary
			world.commands.push({
				"type": "debug.spawn", "kind": "zombie", "id": ZOMBIE_ID,
				"x": float(at["x"]) + ZOMBIE_METRES, "y": float(at["y"]),
			})
		"inventory":
			world.tick = Clock.tick_on_day(DAY, NOON)
			press(tree, KEY_TAB)
		_:
			return "unknown scene %s" % scene
	# Two ticks: the first runs the spawn intake and the second lets its components settle. The
	# frame after draws the result.
	for i in 2:
		main.call("_process", TICK_SECONDS)
	await tree.process_frame
	return ""


## Ask the world whether it is the scene `scene` names. "" when it is, else the reason it is not.
static func verify(main: Node, scene: String) -> String:
	var world: Variant = main.get("world")
	if world == null:
		return "no world"
	match scene:
		"day_street":
			return "" if Clock.phase_of(int(world.tick)) == Clock.Phase.Day else "it is not day"
		"night_lights":
			return "" if Clock.phase_of(int(world.tick)) == Clock.Phase.Night else "it is not night"
		"interior":
			var at: Vector2i = _tile_under_player(world)
			if SimTileMap.tile_at(world.tilemap, at.x, at.y) != SimTileMap.Tile.Floor:
				return "the body is not on a floor tile"
			return "" if _walls_beside(world, at) >= 1 else "no wall stands beside the body"
		"combat":
			var at_pos: Dictionary = world.components.get_component(world.player, "position") as Dictionary
			for e in world.components.query(["zombieType", "position"]):
				if int(e) == int(world.player):
					continue
				var p: Dictionary = world.components.get_component(int(e), "position") as Dictionary
				var dx: float = float(p["x"]) - float(at_pos["x"])
				var dy: float = float(p["y"]) - float(at_pos["y"])
				if dx * dx + dy * dy <= ZOMBIE_NEAR * ZOMBIE_NEAR:
					return ""
			return "no zombie stands within %.1f m of the body" % ZOMBIE_NEAR
		"inventory":
			return "" if bool(main.get("inventory_open")) else "the inventory sheet is not open"
		_:
			return "unknown scene %s" % scene


## The tile the body stands on, from the sim's own position.
static func _tile_under_player(world: Variant) -> Vector2i:
	var at: Dictionary = world.components.get_component(world.player, "position") as Dictionary
	return Vector2i(floori(float(at["x"])), floori(float(at["y"])))


## How many of the four cardinal neighbours of `at` are walls.
static func _walls_beside(world: Variant, at: Vector2i) -> int:
	var n: int = 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var t: Vector2i = at + d
		if SimTileMap.tile_at(world.tilemap, t.x, t.y) == SimTileMap.Tile.Wall:
			n += 1
	return n


## The nearest floor tile, walkable and with a wall beside it, that a body can stand on. Its
## centre, or (-1, -1) when the search finds none. Nearest by Chebyshev ring, so the answer is the
## same on every run from the same seed.
static func _interior_spot(world: Variant) -> Vector2:
	var from: Vector2i = _tile_under_player(world)
	for ring in range(1, SEARCH_TILES + 1):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var t := Vector2i(from.x + dx, from.y + dy)
				if SimTileMap.tile_at(world.tilemap, t.x, t.y) != SimTileMap.Tile.Floor:
					continue
				if world.is_blocked_tile(t.x, t.y):
					continue
				if _walls_beside(world, t) >= 1:
					return Vector2(float(t.x) + 0.5, float(t.y) + 0.5)
	return Vector2(-1.0, -1.0)
