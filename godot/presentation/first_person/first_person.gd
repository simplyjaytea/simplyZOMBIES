extends Node3D
# The opt-in first-person foundation. It boots the real `SimBoot.playable` district, steps the same
# deterministic 20 Hz sim the top-down screen does, and reads the sim -- it never writes it.
#
# The one authority that matters here is collision. There is no CharacterBody3D, no RigidBody3D and
# no CollisionShape3D anywhere under this scene: the player's `position` component is moved by
# `SimWorld._integrate_movement`, against the map's own cells, and the camera is placed at that
# position between ticks. A physics body moving the player would be a second truth, and the gate
# asserts there is none.
#
# Mapping: sim `(x, y)` -> Godot `(x, z)`, one tile is one metre. `y` is the sim's south and Godot's
# `+z`; the camera's eye height is presentation only. Yaw is about Godot `+y`, with -Z forward.
#
# This scene is opt-in (`npm run godot:run:first_person`); the shipped main scene is untouched.
#
# Containers are the second physical interaction: the district's sim cupboards stand as labelled
# placeholders, and E at one sends the same `container.open` command the top-down screen's context
# menu sends before opening the real grid inventory sheet. Taking an item out is an ordinary
# `item.move` the sheet proposes; this file never touches a component or an item.

const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimContainers = preload("res://sim/modules/containers.gd")
const SimChronicle = preload("res://sim/modules/chronicle.gd")
const DistrictView = preload("res://presentation/first_person/district_view.gd")
const BodyView = preload("res://presentation/first_person/body_view.gd")
const PropView = preload("res://presentation/first_person/prop_view.gd")
const ContainerView = preload("res://presentation/first_person/container_view.gd")
const Hud = preload("res://presentation/first_person/hud.gd")
const WorkPanel = preload("res://ui/work_panel.gd")
const WebPanel = preload("res://ui/web_panel.gd")
const InventoryPanel = preload("res://ui/inventory_panel.gd")

const SEED: int = 20260805
# The shipped district, at the size the top-down game ships. The foundation booted a 64-tile cut;
# from the title the owner should walk the world the game is about, not the miniature the gates
# used while the scene was being built.
const DISTRICT_TILES: int = SimTileMap.DISTRICT_TILES
const TICK_HZ: int = 20
const TICK_SECONDS: float = 1.0 / float(TICK_HZ)
# The game's own title lives in this scene; leaving the experiment means going back to it.
const TITLE_SCENE: String = "res://presentation/main.tscn"

const EYE_HEIGHT_M: float = 1.62
const LOOK_SENSITIVITY: float = 0.0024
const PITCH_LIMIT: float = 1.30
const LEDGER_REACH_M: float = 1.80
# cos(30 degrees): the ledger must be inside a narrow cone in front of the eye, not merely near.
const LEDGER_AIM_DOT: float = 0.866
# Where the eye aims on a container box: its middle, not its top or its foot.
const CONTAINER_AIM_HEIGHT_M: float = 0.92

const MOVE_KEYS: Array[int] = [KEY_W, KEY_A, KEY_S, KEY_D]

# Presentation only: a fixed district seed so a first boot is the same district every time. The
# world's own generation remains the sim's business.
var world: Variant = null
var map: Variant = null
var camera: Camera3D = null
var yaw: float = 0.0
var pitch: float = 0.0
var menu_open: bool = false
var paused: bool = false
var inventory_open: bool = false

var _rig: Node3D = null
var _district: Node3D = null
var _bodies: Node3D = null
var _props: Node3D = null
var _containers: Node3D = null
var _hud: Control = null
var _work_layer: CanvasLayer = null
var _work_panel: Control = null
var _web_panel: Control = null
var _web_open: bool = false
var _inventory_layer: CanvasLayer = null
var _inventory_panel: Control = null

var _held: Dictionary = {}
var _last_dx: float = 0.0
var _last_dy: float = 0.0
var _last_aim: float = 1.0e9
var _accumulator: float = 0.0
var _prev_player: Vector2 = Vector2.ZERO
var _curr_player: Vector2 = Vector2.ZERO
var _ledger_sim: Vector2 = Vector2.ZERO
var _ledger_approach: Vector2 = Vector2.ZERO
var _mouse_captured: bool = true
var _alert: String = ""
var _alert_until_ms: int = 0
# Succession and the end of the run: which entity the camera is riding, whether the end panel is
# up, the chronicle's succession sentence, and the epitaph the panel speaks.
var _player_seen: int = -1
var _run_over_open: bool = false
var _news: String = ""
var _news_until_ms: int = 0
var _epitaph: Array[String] = []


func _ready() -> void:
	_boot()
	_build_environment()
	_build_views()
	_build_rig()
	_build_hud()
	_capture_mouse()


func _exit_tree() -> void:
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _notification(what: int) -> void:
	# Alt-tab must not leave a held key walking the body: the window stops receiving the release,
	# so the held set is cleared and a zero move is queued, and the pointer is let go rather than
	# trapped by a window that no longer has focus. Focus back does not grab it again; the HUD
	# asks for a click, which is the one deliberate way back into mouse look.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_clear_held()
		_push_zero_move()
		if not menu_open:
			_release_mouse()


# --- boot and views -------------------------------------------------------------------------

func _boot() -> void:
	var boot: Dictionary = SimBoot.playable(SEED, DISTRICT_TILES)
	world = boot["world"]
	map = boot["map"]
	var pos: Variant = world.components.get_component(int(world.player), "position")
	if pos is Dictionary:
		_curr_player = Vector2(float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]))
	_prev_player = _curr_player
	_player_seen = int(world.player)
	_choose_ledger_site()
	# Open on the desk rather than a random wall: the foundation's one interaction should be in
	# front of the player on the first frame.
	var to_ledger: Vector2 = _ledger_sim - _curr_player
	if to_ledger.length_squared() > 0.01:
		yaw = atan2(-to_ledger.x, -to_ledger.y)
	_push_aim()


func _build_environment() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.09, 0.11, 0.12)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.75, 0.78)
	environment.ambient_light_energy = 1.10
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.name = "FirstPersonEnvironment"
	world_env.environment = environment
	add_child(world_env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "FirstPersonSun"
	sun.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = false
	add_child(sun)


func _build_views() -> void:
	_district = DistrictView.new()
	_district.name = "District"
	add_child(_district)
	_district.call("build", map)

	_props = PropView.new()
	_props.name = "SafeSpawnProps"
	add_child(_props)
	_props.call("build", _ledger_sim)

	_containers = ContainerView.new()
	_containers.name = "Containers"
	add_child(_containers)
	_containers.call("build", world)

	_bodies = BodyView.new()
	_bodies.name = "Bodies"
	add_child(_bodies)
	_bodies.call("build")
	_bodies.call("reset", world)


func _build_rig() -> void:
	_rig = Node3D.new()
	_rig.name = "PlayerRig"
	_rig.position = Vector3(_curr_player.x, 0.0, _curr_player.y)
	add_child(_rig)
	camera = Camera3D.new()
	camera.name = "Eye"
	camera.position = Vector3(0.0, EYE_HEIGHT_M, 0.0)
	camera.fov = 75.0
	camera.near = 0.05
	camera.far = 240.0
	camera.current = true
	_rig.add_child(camera)


func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "FirstPersonHUD"
	add_child(layer)
	_hud = Hud.new()
	_hud.name = "Words"
	layer.add_child(_hud)


# --- the ledger site ------------------------------------------------------------------------

# A desk within a few metres of the safe spawn, on open floor, with at least one open orthogonal
# neighbour to stand on. A tile backed by a real wall with open floor on the wall's far side is
# preferred: it looks like a desk against a wall, and it gives the gate a genuine through-wall case
# for the ledger's line-of-sight rule. The search is row-major over rings, so it is deterministic;
# no RNG is drawn and the sim does not learn the desk exists.
func _choose_ledger_site() -> void:
	var start: Vector2i = Vector2i(floori(_curr_player.x), floori(_curr_player.y))
	var site: Dictionary = _find_site(start, true)
	if site.is_empty():
		site = _find_site(start, false)
	if site.is_empty():
		site = {"tile": start, "approach": start}
	_ledger_sim = Vector2(float((site["tile"] as Vector2i).x) + 0.5, float((site["tile"] as Vector2i).y) + 0.5)
	_ledger_approach = Vector2(float((site["approach"] as Vector2i).x) + 0.5, float((site["approach"] as Vector2i).y) + 0.5)


func _find_site(start: Vector2i, require_blocking_wall: bool) -> Dictionary:
	for radius in range(2, 8):
		var best: Vector2i = Vector2i(-1, -1)
		var approach: Vector2i = Vector2i(-1, -1)
		var best_d: int = 1 << 30
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var tile: Vector2i = start + Vector2i(dx, dy)
				if not _furniture_tile(tile):
					continue
				if require_blocking_wall and _blocking_wall(tile) == Vector2i(-1, -1):
					continue
				var side: Vector2i = _approach_for(tile, start)
				if side == Vector2i(-1, -1):
					continue
				var distance: int = absi(dx) + absi(dy)
				if distance < best_d:
					best_d = distance
					best = tile
					approach = side
		if best != Vector2i(-1, -1):
			return {"tile": best, "approach": approach}
	return {}


func _furniture_tile(tile: Vector2i) -> bool:
	if tile.x <= 0 or tile.y <= 0 or tile.x >= int(map.w) - 1 or tile.y >= int(map.h) - 1:
		return false
	if SimTileMap.is_solid(map, tile.x, tile.y):
		return false
	if SimTileMap.tile_at(map, tile.x, tile.y) != SimTileMap.Tile.Floor:
		return false
	var index: int = tile.y * int(map.w) + tile.x
	return int(map.surfaces[index]) != SimTileMap.SURFACE_WATER


func _blocking_wall(tile: Vector2i) -> Vector2i:
	var sides: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	for side in sides:
		var wall: Vector2i = tile + side
		if not SimTileMap.is_solid(map, wall.x, wall.y):
			continue
		# A window is solid but clear: the ledger test needs a wall the sim's eyes cannot see
		# through, so the desk prefers one that blocks sight.
		if not SimTileMap.blocks_sight(map, wall.x, wall.y):
			continue
		if _furniture_tile(wall + side):
			return side
	return Vector2i(-1, -1)


func _approach_for(tile: Vector2i, start: Vector2i) -> Vector2i:
	var sides: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: int = 1 << 30
	for side in sides:
		var at: Vector2i = tile + side
		if not _furniture_tile(at):
			continue
		var d: int = absi(at.x - start.x) + absi(at.y - start.y)
		if d < best_d:
			best_d = d
			best = at
	return best


# --- the frame ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if world == null:
		return
	# A death the gate (or any caller) triggers outside a step is seen on this frame, not when the
	# accumulator next reaches a tick: succession and the end panel are edges, not per-tick state.
	_watch_identity()
	if _run_over_open:
		# The top-down end screen holds the clock still; so does this one. Input is swallowed in
		# `_input`, and no move or aim is proposed.
		_update_render(clampf(_accumulator / TICK_SECONDS, 0.0, 1.0))
		_update_hud()
		return
	if not paused:
		_accumulator += delta
		var guard: int = 0
		while _accumulator + 0.000001 >= TICK_SECONDS and guard < 8:
			_accumulator -= TICK_SECONDS
			step_sim_once()
			guard += 1
		if guard >= 8:
			_accumulator = 0.0
	if inventory_open:
		_refresh_inventory()
	if menu_open:
		if _web_open and _web_panel != null and _web_panel.visible:
			_web_panel.call("set_world", world, int(_web_panel.get("_who")))
		elif _work_panel != null and _work_panel.visible:
			var who: int = -1
			if _work_panel.has_method("selected"):
				who = int(_work_panel.call("selected"))
			_work_panel.call("set_world", world, who)
	var alpha: float = clampf(_accumulator / TICK_SECONDS, 0.0, 1.0)
	_update_render(alpha)
	_update_hud()


## One deterministic sim tick. The gate calls this directly; `_process` calls it on the 20 Hz
## accumulator, so there is one stepper and not a second loop in the test.
func step_sim_once() -> void:
	if world == null or _run_over_open:
		return
	_watch_identity()
	if _run_over_open:
		return
	_prev_player = _curr_player
	_bodies.call("begin_tick")
	world.step()
	var pos: Variant = world.components.get_component(int(world.player), "position")
	if pos is Dictionary:
		_curr_player = Vector2(float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]))
	_bodies.call("end_tick", world)
	# A death inside the tick moves `world.player`; the camera jumps here, before the next frame's
	# interpolation could glide it across the map.
	_watch_identity()
	# Keep the views and their sim-gated visibility current even when the gate drives ticks
	# without a frame; `_process` overlays the interpolated position afterwards.
	_bodies.call("apply", world, 1.0)


func _update_render(alpha: float) -> void:
	var at: Vector2 = _prev_player.lerp(_curr_player, clampf(alpha, 0.0, 1.0))
	if _rig != null:
		_rig.position = Vector3(at.x, 0.0, at.y)
		_rig.rotation = Vector3(0.0, yaw, 0.0)
	if camera != null:
		camera.rotation = Vector3(pitch, 0.0, 0.0)
	if _bodies != null:
		_bodies.call("apply", world, alpha)


func _update_hud() -> void:
	if _hud == null or world == null:
		return
	var prompt: String = ""
	if inventory_open:
		# The sheet is over the world and takes the words with it; Escape is the way back.
		prompt = ""
	elif not menu_open and not _mouse_captured:
		prompt = "Mouse released. Click to look again."
	elif not menu_open:
		var verdict: String = interaction_verdict()
		if verdict == "ok":
			prompt = "E read the ledger"
		elif verdict == "away":
			prompt = "Turn to the ledger."
		else:
			var box_verdict: String = container_verdict()
			var box_name: String = _container_kind(container_focus())
			if box_verdict == "ok":
				prompt = "E open the %s" % box_name
			elif box_verdict == "away":
				prompt = "Turn to the %s." % box_name
			elif box_verdict == "spent":
				prompt = "You have already been through this %s." % box_name
			elif _curr_player.distance_to(_ledger_sim) < 4.5:
				prompt = "The ledger stands near."
	_hud.call("set_state", world, int(world.player), prompt, _live_alert(), menu_open, paused, inventory_open, _live_news())
	_hud.visible = not inventory_open


# --- input ----------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# A scene change can free this node while the same `push_input` call is still delivering the
	# event (the press that asked to go back to the title has a release behind it). A node on its
	# way out has no viewport, so there is nothing to consume the event with.
	if not is_inside_tree() or get_viewport() == null:
		return
	if not (event is InputEventKey):
		return
	var ke: InputEventKey = event as InputEventKey
	if ke.echo:
		return
	var code: int = ke.keycode if ke.keycode != 0 else ke.physical_keycode
	if _run_over_open:
		# One action, and it is the top-down over screen's own quiet exit: back to the title.
		# Nothing else reaches the world, so W cannot walk a body that is no longer anybody's.
		if ke.pressed and (code == KEY_ESCAPE or code == KEY_ENTER or code == KEY_KP_ENTER):
			# The scene change frees this node; there is no viewport left to consume with.
			return_to_title()
			return
		get_viewport().set_input_as_handled()
		return
	if _waiting_for_heir():
		# The gap between a death and the handoff: no command is proposed and no key is remembered.
		get_viewport().set_input_as_handled()
		return
	if inventory_open:
		# The sheet takes every key while it is up, exactly as `input_map.gd`'s "sheet" focus does:
		# walking keys are swallowed (the body was stopped when the sheet opened), the name field
		# takes its own typing, R turns a lifted item, and Escape puts down what the sheet is
		# holding before it closes the sheet -- one press, one thing.
		if ke.pressed and _inventory_panel != null:
			if _inventory_panel.has_method("naming") and bool(_inventory_panel.call("naming")):
				_inventory_panel.call("name_key", ke)
			elif code == KEY_ESCAPE:
				if not bool(_inventory_panel.call("escape")):
					close_inventory()
			elif code == KEY_R and _inventory_panel.has_method("rotate"):
				_inventory_panel.call("rotate")
		get_viewport().set_input_as_handled()
		return
	if menu_open:
		if ke.pressed and code == KEY_ESCAPE:
			if _web_open:
				_show_work_panel()
			else:
				close_ledger_menu()
			get_viewport().set_input_as_handled()
			return
		if ke.pressed and _work_panel != null and _work_panel.has_method("key") and not _web_open:
			_work_panel.call("key", ke)
		get_viewport().set_input_as_handled()
		return
	if ke.pressed and code == KEY_ESCAPE:
		# Outside the ledger, Escape is the way out of the pointer trap: the first press releases
		# the mouse and the HUD asks for a click to resume looking. A second press, with the mouse
		# already free, is the quiet way back to the title -- the first-person screen's only
		# retreat now that the title can open it.
		if not _mouse_captured:
			# The scene change frees this node; there is no viewport left to consume with.
			return_to_title()
			return
		else:
			_release_mouse()
			_push_zero_move()
		get_viewport().set_input_as_handled()
		return
	if ke.pressed and code == KEY_E:
		try_interact()
		get_viewport().set_input_as_handled()
		return
	if code in MOVE_KEYS:
		_held[code] = ke.pressed
		_push_move_from_held()
		get_viewport().set_input_as_handled()
		return
	if ke.pressed and code == KEY_P:
		paused = not paused
		if paused:
			_push_zero_move()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not is_inside_tree() or get_viewport() == null:
		return
	if _run_over_open or _waiting_for_heir():
		# No mouse look and no click-to-recapture under the end panel or between a death and an
		# heir. The pointer stays where `_release_mouse` left it.
		return
	if event is InputEventMouseMotion and _mouse_captured and not menu_open and not inventory_open:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		look_by(motion.relative.x, motion.relative.y)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and not menu_open and not inventory_open and not _mouse_captured:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.pressed:
			_capture_mouse()
			get_viewport().set_input_as_handled()


# --- mouse look (the gate's entry point too) ------------------------------------------------

func look_by(delta_x: float, delta_y: float) -> void:
	yaw = wrapf(yaw - delta_x * LOOK_SENSITIVITY, -PI, PI)
	pitch = clampf(pitch - delta_y * LOOK_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
	_push_aim()
	# Walking is relative to the yaw, so a turn while W is held must also send the new direction.
	# Without this the body kept walking the direction of the last key event until another key.
	if not _held.is_empty():
		_push_move_from_held()


func set_look(new_yaw: float, new_pitch: float) -> void:
	yaw = wrapf(new_yaw, -PI, PI)
	pitch = clampf(new_pitch, -PITCH_LIMIT, PITCH_LIMIT)
	_update_render(clampf(_accumulator / TICK_SECONDS, 0.0, 1.0))
	_push_aim()
	if not _held.is_empty():
		_push_move_from_held()


## Points the eye at a Godot-space point. Used by the gate and by nothing else in the frame loop;
## it is the inverse of `look_direction` and the same arithmetic a mouse could only reach slowly.
func look_toward(point: Vector3) -> void:
	var eye: Vector3 = Vector3(_rendered_player().x, EYE_HEIGHT_M, _rendered_player().y)
	var d: Vector3 = point - eye
	if d.length_squared() <= 0.000001:
		return
	var flat: Vector2 = Vector2(d.x, d.z)
	var new_yaw: float = yaw if flat.length_squared() <= 0.000001 else atan2(-d.x, -d.z)
	var new_pitch: float = asin(clampf(d.normalized().y, -1.0, 1.0))
	set_look(new_yaw, new_pitch)


func look_direction() -> Vector3:
	var c: float = cos(pitch)
	return Vector3(-sin(yaw) * c, sin(pitch), -cos(yaw) * c)


func _forward_horizontal() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _right_horizontal() -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


func _push_aim() -> void:
	if world == null or _run_over_open or _waiting_for_heir():
		return
	var dir: Vector3 = _forward_horizontal()
	var radians: float = atan2(dir.z, dir.x)
	if radians == 0.0:
		radians = 0.0
	if _last_aim > 1.0e8 or absf(angle_difference(radians, _last_aim)) > 0.0005:
		_last_aim = radians
		world.commands.push({"type": "aim", "radians": radians})


func _push_move_from_held() -> void:
	var forward: float = 0.0
	var strafe: float = 0.0
	if bool(_held.get(KEY_W, false)):
		forward += 1.0
	if bool(_held.get(KEY_S, false)):
		forward -= 1.0
	if bool(_held.get(KEY_D, false)):
		strafe += 1.0
	if bool(_held.get(KEY_A, false)):
		strafe -= 1.0
	_push_move_axes(forward, strafe)


func _push_move_axes(forward: float, strafe: float) -> void:
	if world == null or _run_over_open or _waiting_for_heir():
		return
	var direction: Vector3 = _forward_horizontal() * forward + _right_horizontal() * strafe
	if direction.length_squared() > 0.000001:
		direction = direction.normalized()
	var dx: float = direction.x
	var dy: float = direction.z
	if absf(dx - _last_dx) > 0.000001 or absf(dy - _last_dy) > 0.000001:
		_last_dx = dx
		_last_dy = dy
		world.commands.push({"type": "move", "dx": dx, "dy": dy})


func _push_zero_move() -> void:
	if world == null:
		return
	_last_dx = 0.0
	_last_dy = 0.0
	world.commands.push({"type": "move", "dx": 0.0, "dy": 0.0})


func _clear_held() -> void:
	_held.clear()


# --- containers and the inventory sheet ------------------------------------------------------
#
# A container is a sim entity with `searchable` and `position`; `container_view.gd` stands a
# placeholder for each. E reads it the way the ledger is read -- reach, aim, then the sim's own
# sight -- and, when all three agree, pushes the same command the top-down context menu pushes:
# `container.open`, naming the box. The screen is the top-down game's own `ui/inventory_panel.gd`,
# opened on the player's inventory with the open box as its first column
# (`SimContainers.open_view`), so a take is the `item.move` the sheet has always sent.
#
# INVENTORY PAUSE POLICY -- reversible default, not a new design decision (docs/33 leaves the
# inventory/ledger pause question open). `main.gd` does not stop the clock for its inventory
# sheet: `_process` steps the world whenever the session is PLAYING and P is not held, while
# `input_map.gd` gives the sheet focus, clears the held set and queues one zero move so the body
# stops under the screen. This scene copies exactly that: `paused` is untouched by the sheet, the
# body is stopped by `_clear_held` + `_push_zero_move`, and movement keys are swallowed by the
# `inventory_open` branch of `_input`. If the owner later chooses time-stopped inventories, the
# one change is to hold the accumulator while `inventory_open` is true.
const INVENTORY_COMMAND_CLOSE: String = "container.close"
const INVENTORY_COMMAND_OPEN: String = "container.open"


## The container the eye is on, or -1. The nearest box inside the same narrow cone the ledger
## uses; distance is not the only test, so a cupboard under your nose but behind you is not it.
func container_target() -> int:
	if world == null or _containers == null:
		return -1
	if int(_containers.call("count")) <= 0:
		return -1
	var eye: Vector3 = Vector3(_rendered_player().x, EYE_HEIGHT_M, _rendered_player().y)
	var look: Vector3 = look_direction()
	var best: int = -1
	var best_distance: float = 1.0e9
	for entity in _containers.call("entities") as Array:
		var point: Vector3 = container_world_point(int(entity))
		var to: Vector3 = point - eye
		var distance: float = to.length()
		if distance <= 0.000001:
			continue
		if look.dot(to / distance) < LEDGER_AIM_DOT:
			continue
		if distance < best_distance:
			best_distance = distance
			best = int(entity)
	return best


## "ok", "far", "away", "blocked", "spent" or "none". The same order the ledger is judged in:
## an aimed box is measured against the sim's own reach, then the sim's own sight. A box nearer
## than the one the eye found -- or one in reach with nothing in the aim at all -- is "away", so
## the refusal is "turn to the cupboard beside you", never "walk closer" about a distant one in
## the same diagonal. "spent" is the sim's own three-state reading of a searched box
## (`SimContainers.contents_of`): an emptied cupboard is not offered, because E at it would fall
## through the top-down ladder rather than open a blank grid.
func container_verdict() -> String:
	if world == null or _containers == null:
		return "none"
	var target: int = container_target()
	var near: int = int(SimContainers.nearest(world, int(world.player), false, SimContainers.Want.Any))
	if target < 0:
		return "away" if near >= 0 else "none"
	if _curr_player.distance_to(_container_sim_position(target)) > float(SimContainers.SEARCH_REACH):
		return "away" if near >= 0 else "far"
	if not container_in_sight(target):
		return "blocked"
	if not _container_openable(target):
		return "spent"
	return "ok"


## The box the verdict is speaking about: the near one for "away", the aimed one otherwise.
func container_focus() -> int:
	if world == null or _containers == null:
		return -1
	var target: int = container_target()
	var near: int = int(SimContainers.nearest(world, int(world.player), false, SimContainers.Want.Any))
	if near >= 0 and (target < 0 or _curr_player.distance_to(_container_sim_position(target)) > float(SimContainers.SEARCH_REACH)):
		return near
	return target


## A box through an opaque wall is not in reach, however close the geometry is -- the same read
## `main.gd`'s HUD and the E ladder make, on the sim's own visibility.
func container_in_sight(entity: int) -> bool:
	if world == null or world.vision == null or entity < 0:
		return false
	var at: Vector2 = _container_sim_position(entity)
	return int(world.vision.call("detail", int(world.player), at.x, at.y)) != 0


func container_world_point(entity: int) -> Vector3:
	var at: Vector2 = _container_sim_position(entity)
	return Vector3(at.x, CONTAINER_AIM_HEIGHT_M, at.y)


## The one interaction. An aimed, reachable container is opened with the top-down command and the
## real inventory sheet; a refusal says which of the three rules failed, in the ledger's words.
func try_interact() -> bool:
	if menu_open or inventory_open:
		return false
	if interaction_verdict() == "ok":
		open_ledger_menu()
		return true
	var box_verdict: String = container_verdict()
	if box_verdict != "none":
		var box_name: String = _container_kind(container_focus())
		match box_verdict:
			"far":
				_set_alert("Nothing within reach. Walk closer to the %s." % box_name)
				return false
			"blocked":
				_set_alert("The %s is behind a wall." % box_name)
				return false
			"away":
				_set_alert("You are near the %s, but not looking at it." % box_name)
				return false
			"spent":
				_set_alert("You have already been through this %s." % box_name)
				return false
			"ok":
				open_container(container_focus())
				return true
	match interaction_verdict():
		"far":
			_set_alert("Nothing within reach. Walk closer to the ledger.")
			return false
		"blocked":
			_set_alert("The ledger is behind a wall.")
			return false
		"away":
			_set_alert("You are near the ledger, but not looking at it.")
			return false
	_set_alert("There is nothing here to use.")
	return false


## Opens `entity` through the sim and puts the player's own inventory on screen beside it. The
## command is the context menu's `container.open` with the box named, so reach and the table roll
## stay the sim's (`sim/modules/containers.gd`); this file only asks for it.
func open_container(entity: int) -> void:
	if world == null or entity < 0:
		return
	world.commands.push({"type": INVENTORY_COMMAND_OPEN, "container": entity})
	open_inventory()


func open_inventory() -> void:
	if inventory_open:
		return
	_ensure_inventory_panel()
	if _inventory_panel == null:
		return
	inventory_open = true
	_inventory_panel.visible = true
	_inventory_panel.call("set_open", true)
	_inventory_panel.call("set_world", world, int(world.player))
	_inventory_panel.call("set_loot", SimContainers.open_view(world, int(world.player)))
	_clear_held()
	_push_zero_move()
	_release_mouse()
	_alert = ""
	if _hud != null:
		_hud.visible = false


func close_inventory() -> void:
	if not inventory_open:
		return
	if world != null:
		# The top-down Escape does the same when a transfer window is up: tell the sim the box is
		# no longer being opened, so `item.move` stops accepting a transfer to it.
		world.commands.push({"type": INVENTORY_COMMAND_CLOSE})
	inventory_open = false
	if _inventory_panel != null:
		_inventory_panel.visible = false
		_inventory_panel.call("set_open", false)
	if _hud != null:
		_hud.visible = true
	_clear_held()
	_push_zero_move()
	_capture_mouse()
	_alert = ""


func _ensure_inventory_panel() -> void:
	if _inventory_panel != null:
		return
	_inventory_layer = CanvasLayer.new()
	_inventory_layer.name = "InventoryUI"
	add_child(_inventory_layer)
	_inventory_panel = InventoryPanel.new()
	_inventory_panel.name = "InventoryPanel"
	_inventory_layer.add_child(_inventory_panel)


# Every frame the sheet is up: a fresh `open_view` and a fresh inventory snapshot, in `main.gd`'s
# order (`set_loot`, then `set_world`). Without the refresh a take would leave the old grid on.
func _refresh_inventory() -> void:
	if _inventory_panel == null or world == null:
		return
	_inventory_panel.call("set_loot", SimContainers.open_view(world, int(world.player)))
	_inventory_panel.call("set_world", world, int(world.player))


func _container_sim_position(entity: int) -> Vector2:
	if world == null or entity < 0:
		return Vector2.ZERO
	var pos: Variant = world.components.get_component(entity, "position")
	if not (pos is Dictionary):
		return Vector2.ZERO
	return Vector2(float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]))


func _container_kind(entity: int) -> String:
	if world == null or entity < 0:
		return SimContainers.DEFAULT_KIND
	var state: Variant = world.components.get_component(entity, "searchable")
	if not (state is Dictionary):
		return SimContainers.DEFAULT_KIND
	return String((state as Dictionary).get("kind", SimContainers.DEFAULT_KIND))


func _container_openable(entity: int) -> bool:
	if world == null or entity < 0:
		return false
	var state: Variant = world.components.get_component(entity, "searchable")
	if not (state is Dictionary):
		return false
	if bool((state as Dictionary).get("searched", false)):
		return not SimContainers.contents_of(world, entity).is_empty()
	return true


# --- the ledger ------------------------------------------------------------------------------

## "ok", "far", "blocked" or "away". Reach is measured in the sim's own metres from the body the
## sim moved; the sim's own visibility decides whether a wall is in the way; the look is the
## camera's forward cone. Every one must pass.
func interaction_verdict() -> String:
	if world == null or _props == null:
		return "none"
	if _curr_player.distance_to(_ledger_sim) > LEDGER_REACH_M:
		return "far"
	var point: Vector3 = _props.call("ledger_world_point")
	var eye: Vector3 = Vector3(_rendered_player().x, EYE_HEIGHT_M, _rendered_player().y)
	var to: Vector3 = point - eye
	if to.length_squared() <= 0.000001:
		return "away"
	if look_direction().dot(to.normalized()) < LEDGER_AIM_DOT:
		return "away"
	if not ledger_in_sight():
		return "blocked"
	return "ok"


## The same vision read the top-down screen uses: a ledger through a wall is not in reach,
## however close the geometry is.
func ledger_in_sight() -> bool:
	if world == null or world.vision == null:
		return false
	return int(world.vision.call("detail", int(world.player), _ledger_sim.x, _ledger_sim.y)) != 0


## The work panel is the ledger's real screen; it is opened only by `try_interact` after the
## three ledger rules agree.
func open_ledger_menu() -> void:
	if _work_panel == null:
		_work_layer = CanvasLayer.new()
		_work_layer.name = "LedgerMenu"
		add_child(_work_layer)
		_work_panel = WorkPanel.new()
		_work_panel.name = "WorkPanel"
		_work_layer.add_child(_work_panel)
		if _work_panel.has_signal("navigate"):
			_work_panel.connect("navigate", _on_ledger_navigate)
		_web_panel = WebPanel.new()
		_web_panel.name = "WebPanel"
		_web_panel.visible = false
		_web_panel.size = Vector2(_web_panel.get_script().get("NATURAL"))
		_work_layer.add_child(_web_panel)
	_work_panel.call("set_world", world, -1)
	_work_panel.visible = true
	if _web_panel != null:
		_web_panel.visible = false
	_web_open = false
	menu_open = true
	_clear_held()
	_push_zero_move()
	_release_mouse()
	_alert = ""


func close_ledger_menu() -> void:
	if _work_panel != null:
		_work_panel.visible = false
	if _web_panel != null:
		_web_panel.visible = false
	_web_open = false
	menu_open = false
	_clear_held()
	_push_zero_move()
	_capture_mouse()
	_alert = ""


# The work panel's "their skills" button is a real door: it opens the existing read-only skill web
# for the colonist the drawer has picked. No second screen is invented and no placeholder note is
# put in front of the player. Escape comes back to the grid; a second Escape closes the ledger.
func _on_ledger_navigate(screen: String) -> void:
	if screen != "skills" or _work_panel == null or _web_panel == null:
		return
	var who: int = int(_work_panel.call("selected"))
	if who < 0:
		return
	_work_panel.visible = false
	_web_panel.call("set_world", world, who)
	_place_web()
	_web_panel.visible = true
	_web_open = true


func _show_work_panel() -> void:
	if _web_panel != null:
		_web_panel.visible = false
	_web_open = false
	if _work_panel != null:
		_work_panel.visible = true
		_work_panel.call("set_world", world, int(_work_panel.call("selected")))


# The web centred under the same top line the top-down screen uses, shrunk to the window when the
# natural size does not fit. This is `main.gd`'s `_place_web` without the navigation bar.
func _place_web() -> void:
	if _web_panel == null:
		return
	var view: Vector2 = get_viewport().get_visible_rect().size
	var natural: Vector2 = Vector2(_web_panel.get_script().get("NATURAL"))
	var top: float = 16.0 + 48.0 + 16.0
	var room: Vector2 = Vector2(view.x - 32.0, view.y - top - 16.0)
	var fit: Vector2 = Vector2(floorf(minf(natural.x, room.x) / 2.0) * 2.0, floorf(minf(natural.y, room.y) / 2.0) * 2.0)
	if _web_panel.size != fit:
		_web_panel.size = fit
		_web_panel.queue_redraw()
	var at: Vector2 = Vector2(16.0 + (room.x - fit.x) / 2.0, top)
	_web_panel.position = Vector2(maxf(16.0, floorf(at.x / 2.0) * 2.0), floorf(top / 2.0) * 2.0)


func work_panel_node() -> Control:
	return _work_panel


func web_panel_node() -> Control:
	return _web_panel


func inventory_panel_node() -> Control:
	return _inventory_panel


# --- succession and the end of a run ---------------------------------------------------------
#
# The sim owns both facts. `SimRecruits._handoff` moves `world.player` to an heir and clears
# `runOver`; `SimRecruits.handle_death` sets `runOver` when nobody is left. This file only watches
# those two fields after every tick and at the top of every frame -- no subscription and no second
# death check, because `runOver` is read once the tick that set it has finished (main.gd's own
# rule at its `world.runOver` read).
#
# The camera jumps rather than glides: a handoff is a cut, and interpolating from the dead body's
# last position to an heir across the district would be a lie about where the eye went. The dead
# body is collected by `body_view.gd` as a corpse from that frame on.

func _watch_identity() -> void:
	if world == null:
		return
	var now: int = int(world.player)
	if now != _player_seen:
		_player_seen = now
		_on_succession()
	if bool(world.runOver) and not _run_over_open:
		_show_run_over()


## The camera is the new survivor now. Any screen that was talking to the dead body goes, held
## keys are cleared, and the chronicle's own succession sentence is put on the HUD.
func _on_succession() -> void:
	if inventory_open:
		close_inventory()
	if menu_open:
		close_ledger_menu()
	_clear_held()
	_push_zero_move()
	_snap_to_player()
	# Collect again with the heir as the eye, so the dead body is drawn on this frame when the
	# heir can see it rather than waiting for the next `end_tick`.
	if _bodies != null:
		_bodies.call("reset", world)
	_set_news(_succession_words())
	_alert = ""


## Puts the rig and both interpolation ends on the heir's sim position in one step. The public
## `snap_render_to_sim` is the gate's read-only snap; this is the same arithmetic at a handoff.
func _snap_to_player() -> void:
	var pos: Variant = world.components.get_component(int(world.player), "position")
	if pos is Dictionary:
		_curr_player = Vector2(float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]))
	_prev_player = _curr_player
	_accumulator = 0.0
	_update_render(0.0)
	_push_aim()


## The top-down chronicle's own succession line -- "You are Mara Sato now." or "You are someone
## else now." -- read back from the record rather than written a second time.
func _succession_words() -> String:
	for line in SimChronicle.epitaph(world, 6):
		var text: String = String(line)
		if text.begins_with("You are ") and text.ends_with(" now."):
			return text
	return "You are someone else now."


## The way back to the game's own title. A scene change, not a quit: `main.tscn` boots into its
## title state, so the top-down screen and New run are still there when the experiment ends. The
## pivot's default switch is a later piece; this is only the door out of the experiment.
func return_to_title() -> void:
	if get_tree().change_scene_to_file(TITLE_SCENE) != OK:
		_set_alert("The title could not be opened.")


## The run-over screen in words. `ui/shell.gd` is the top-down screen; this scene's one action is
## to return to the game's own title (Escape or Enter), which is the over screen's "quit" half. The
## epitaph is `SimChronicle.epitaph`, the same lines the shell draws.
func _show_run_over() -> void:
	if _run_over_open:
		return
	_run_over_open = true
	if inventory_open:
		close_inventory()
	if menu_open:
		close_ledger_menu()
	_clear_held()
	_push_zero_move()
	_release_mouse()
	_alert = ""
	_news = ""
	_epitaph = SimChronicle.epitaph(world, 5)
	if _epitaph.is_empty():
		# The chronicle's own run-over line, and the shell's fallback when the record is empty.
		_epitaph.append("There is nobody left to be.")
	elif not _epitaph.has("There is nobody left to be."):
		# The screen can be asked for on the frame a death lands, before the tick's events have
		# drained into the record; the run-over sentence is still the reason it is up.
		_epitaph.append("There is nobody left to be.")
	if _hud != null:
		_hud.visible = true
		_hud.call("set_run_over", _epitaph)


## True only in the gap the sim does not currently leave: a frame with the player entity already
## a corpse and the heir not yet assigned. Input is ignored and no command is proposed.
func _waiting_for_heir() -> bool:
	return world != null and world.components.has_component(int(world.player), "corpse")


func _set_news(text: String, seconds: float = 8.0) -> void:
	_news = text
	_news_until_ms = Time.get_ticks_msec() + int(seconds * 1000.0)


func _live_news() -> String:
	if _news != "" and Time.get_ticks_msec() > _news_until_ms:
		_news = ""
	return _news


func run_over_open() -> bool:
	return _run_over_open


# --- small read-only answers the gate and the HUD use ----------------------------------------

func ledger_sim_position() -> Vector2:
	return _ledger_sim


func ledger_approach_position() -> Vector2:
	return _ledger_approach


func container_view_count() -> int:
	return int(_containers.call("count")) if _containers != null else 0


func container_node_for(entity: int) -> Node3D:
	if _containers == null:
		return null
	return _containers.call("node_for", entity) as Node3D


func container_label_for(entity: int) -> String:
	return String(_containers.call("label_for", entity)) if _containers != null else ""


func container_sim_position(entity: int) -> Vector2:
	return _container_sim_position(entity)


func rendered_player_position() -> Vector2:
	return _rendered_player()


func render_alpha() -> float:
	return clampf(_accumulator / TICK_SECONDS, 0.0, 1.0)


func body_view_count() -> int:
	return int(_bodies.call("count")) if _bodies != null else 0


func body_view_visible_count() -> int:
	return int(_bodies.call("visible_count")) if _bodies != null else 0


func body_node_for(entity: int) -> MeshInstance3D:
	return _bodies.call("node_for", entity) as MeshInstance3D


## Re-reads the player's sim position into the render state. Read-only by construction: a gate
## moves the sim body itself and then calls this, so presentation never writes a component. In play
## nothing calls it, because walking is the sim's job.
func snap_render_to_sim() -> void:
	if world == null:
		return
	var pos: Variant = world.components.get_component(int(world.player), "position")
	if pos is Dictionary:
		_curr_player = Vector2(float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]))
	_prev_player = _curr_player
	_accumulator = 0.0
	_update_render(0.0)


func mouse_captured() -> bool:
	return _mouse_captured


func is_world_paused() -> bool:
	return paused


func hud_lines() -> Array[String]:
	var out: Array[String] = []
	if _hud == null:
		return out
	var raw: Variant = _hud.call("lines")
	if raw is Array:
		for line in raw as Array:
			out.append(String(line))
	return out


func _rendered_player() -> Vector2:
	return _prev_player.lerp(_curr_player, render_alpha())


func _set_alert(text: String) -> void:
	_alert = text
	_alert_until_ms = Time.get_ticks_msec() + 3000


func _live_alert() -> String:
	if _alert != "" and Time.get_ticks_msec() > _alert_until_ms:
		_alert = ""
	return _alert


func _release_mouse() -> void:
	_mouse_captured = false
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _capture_mouse() -> void:
	_mouse_captured = true
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
