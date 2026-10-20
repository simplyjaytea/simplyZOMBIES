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
const SimSurface = preload("res://sim/map/surface.gd")
const Dressing = preload("res://presentation/dressing.gd")

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
const SEARCH_TILES: int = 80
# How far, in tiles (Chebyshev), a shot's survivor stands from any dressing picture. A room shot
# takes the clearest spot its rooms offer, which may be less (`_interior_spot`).
const SPOT_CLEAR: int = 3
# How far past the colony's clearing a room shot stands, in tiles.
const START_MARGIN: int = 3
# The share of a room shot's window, in percent, that has to be indoor floor to count as a room.
const ROOM_SHARE: int = 30

# The street a day shot wants: a window the size of the 1280x720 view (20 x 11 tiles at 64 px a
# tile, centred on the body), and the share of it that has to be paved outdoor street for the spot
# to count as mostly street. The shots were 50 percent building at 1280 before this.
const STREET_WINDOW_HALF: Vector2i = Vector2i(10, 5)
const STREET_WINDOW_AREA: int = 21 * 11
const STREET_SHARE: int = 75


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
			# The body starts indoors, so a day shot taken where it stands is a room, not a street.
			# Move it to the nearest open paved street tile first.
			world.tick = Clock.tick_on_day(DAY, NOON)
			var street: Vector2 = _street_spot(world)
			if street.x < 0.0:
				return "no open paved street within %d tiles" % SEARCH_TILES
			world.components.set_component(world.player, "position", {"x": street.x, "y": street.y})
		"night_lights":
			world.tick = Clock.tick_on_day(DAY, NIGHT)
		"interior":
			world.tick = Clock.tick_on_day(DAY, NOON)
			var spot: Vector2 = _interior_spot(world)
			if spot.x < 0.0:
				return "no indoor floor within %d tiles" % SEARCH_TILES
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
	# The camera jumps to where the body now stands. Without this the follow lerp was still walking
	# from the body's old tile when the shot was taken, so the body sat off centre (or at the top
	# edge) and a shot of the old spot's neighbourhood was the one photographed.
	main.call("_snap_camera")
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
			if Clock.phase_of(int(world.tick)) != Clock.Phase.Day:
				return "it is not day"
			return "" if _outdoor_paved(world.tilemap, _tile_under_player(world)) else "the body is not on an open paved street tile"
		"night_lights":
			return "" if Clock.phase_of(int(world.tick)) == Clock.Phase.Night else "it is not night"
		"interior":
			var at: Vector2i = _tile_under_player(world)
			if SimTileMap.tile_at(world.tilemap, at.x, at.y) != SimTileMap.Tile.Floor:
				return "the body is not on a floor tile"
			return "" if SimTileMap.is_indoors(world.tilemap, at.x, at.y) else "the body is not indoors"
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


## Whether a tile is open, paved ground outside a building: the street a day shot needs.
static func _outdoor_paved(map: Variant, at: Vector2i) -> bool:
	if at.x < 0 or at.y < 0 or at.x >= int(map.w) or at.y >= int(map.h):
		return false
	var idx: int = at.y * int(map.w) + at.x
	return int(map.tiles[idx]) == SimTileMap.Tile.Floor \
		and int(map.indoors[idx]) == 0 \
		and int(map.surfaces[idx]) == SimSurface.Surface.Paved


## The open paved street tile nearest the body whose surroundings are mostly street: the first
## candidate, out to SEARCH_TILES, that has at least STREET_SHARE of its STREET_WINDOW paved outdoor
## tiles; failing that, the candidate with the most. Open means outdoor paved on all four sides, so
## the shot sees street and not a kerb. Its centre, or (-1, -1) when the search finds none.
static func _street_spot(world: Variant) -> Vector2:
	var from: Vector2i = _tile_under_player(world)
	var occ: Dictionary = _spot_occupancy(world)
	var best := Vector2(-1.0, -1.0)
	var best_count: int = -1
	for ring in range(1, SEARCH_TILES + 1):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var t := Vector2i(from.x + dx, from.y + dy)
				if world.is_blocked_tile(t.x, t.y) or not _outdoor_paved(world.tilemap, t):
					continue
				var open: bool = true
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if not _outdoor_paved(world.tilemap, t + d):
						open = false
						break
				if not open:
					continue
				if not _ring_free(occ, t):
					continue
				var count: int = _street_count(world.tilemap, t)
				if count * 100 >= STREET_SHARE * STREET_WINDOW_AREA:
					return Vector2(float(t.x) + 0.5, float(t.y) + 0.5)
				if count > best_count:
					best_count = count
					best = Vector2(float(t.x) + 0.5, float(t.y) + 0.5)
	return best


## How many outdoor paved tiles lie in the STREET_WINDOW box centred on `at`: the share of the
## picture a day shot at that spot would show as street.
static func _street_count(map: Variant, at: Vector2i) -> int:
	var n: int = 0
	for dy in range(-STREET_WINDOW_HALF.y, STREET_WINDOW_HALF.y + 1):
		for dx in range(-STREET_WINDOW_HALF.x, STREET_WINDOW_HALF.x + 1):
			if _outdoor_paved(map, Vector2i(at.x + dx, at.y + dy)):
				n += 1
	return n


## Whether the survivor may stand on `at` in a shot: no picture of any kind reaches within
## SPOT_CLEAR tiles of it, so no shot has a table or a scrap drawn over or beside the survivor.
## Dressing's own test, on an occupancy that holds the world's props the way main.gd's does.
static func _ring_free(occ: Dictionary, at: Vector2i, radius: int = SPOT_CLEAR) -> bool:
	return Dressing.clear_around(occ, at.x, at.y, radius)


## Whether a room shot's spot lies well away from the colony's start: the dressing keeps a clearing
## round the start (Dressing.FURNISH_CLEAR), and a room shot taken in it judges the clearing rather
## than the furnished rooms. START_MARGIN tiles past the clearing's edge.
static func _clear_of_start(world: Variant, at: Vector2i) -> bool:
	var clear: Rect2i = Dressing._clear_of(world.tilemap)
	return not clear.grow(START_MARGIN).has_point(at)


## The occupancy a spot search tests every candidate against, built once per search.
static func _spot_occupancy(world: Variant) -> Dictionary:
	return Dressing.occupancy(Dressing.block_of(world), world.tilemap, int(world.seed), Dressing.held_props(world))


## The indoor floor tile a room shot stands on: walkable, outside the colony's clearing, in a room
## of at least ROOM_SHARE percent of the STREET_WINDOW, and as far from any dressing picture as such
## a room offers -- SPOT_CLEAR tiles if one does, else one fewer, down to a tile. A furnished room
## seldom has a clear seven-tile square (the density rule asks for no empty floor block over six),
## so the shot takes the clearest spot the rooms have rather than a bare room. Nearest by Chebyshev
## ring within each radius, so the answer is the same on every run from the same seed; failing a
## room that large, the candidate in the biggest room. Its centre, or (-1, -1) for none.
static func _interior_spot(world: Variant) -> Vector2:
	var from: Vector2i = _tile_under_player(world)
	var occ: Dictionary = _spot_occupancy(world)
	var best := Vector2(-1.0, -1.0)
	var best_count: int = -1
	var by_radius: Dictionary = {}
	for ring in range(1, SEARCH_TILES + 1):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var t := Vector2i(from.x + dx, from.y + dy)
				if SimTileMap.tile_at(world.tilemap, t.x, t.y) != SimTileMap.Tile.Floor:
					continue
				if world.is_blocked_tile(t.x, t.y) or not SimTileMap.is_indoors(world.tilemap, t.x, t.y):
					continue
				if not _clear_of_start(world, t) or not _ring_free(occ, t, 1):
					continue
				var count: int = _room_count(world.tilemap, t)
				var centre := Vector2(float(t.x) + 0.5, float(t.y) + 0.5)
				if count > best_count:
					best_count = count
					best = centre
				if count * 100 < ROOM_SHARE * STREET_WINDOW_AREA:
					continue
				for radius in range(SPOT_CLEAR, 0, -1):
					if by_radius.has(radius):
						break
					if _ring_free(occ, t, radius):
						by_radius[radius] = centre
						break
		if by_radius.has(SPOT_CLEAR):
			break
	for radius in range(SPOT_CLEAR, 0, -1):
		if by_radius.has(radius):
			return by_radius[radius]
	return best


## How many tiles of the room `at` stands in lie in the STREET_WINDOW box centred on it: indoor
## floor reached from `at` by side steps without leaving the box, so the count is the room the
## survivor sees and not the rooms behind its walls.
static func _room_count(map: Variant, at: Vector2i) -> int:
	var seen: Dictionary = {at: true}
	var queue: Array[Vector2i] = [at]
	var n: int = 0
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		n += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: Vector2i = c + d
			if seen.has(nx) or absi(nx.x - at.x) > STREET_WINDOW_HALF.x or absi(nx.y - at.y) > STREET_WINDOW_HALF.y:
				continue
			if SimTileMap.tile_at(map, nx.x, nx.y) != SimTileMap.Tile.Floor or not SimTileMap.is_indoors(map, nx.x, nx.y):
				continue
			seen[nx] = true
			queue.append(nx)
	return n
