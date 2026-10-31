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

const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const DistrictView = preload("res://presentation/first_person/district_view.gd")
const BodyView = preload("res://presentation/first_person/body_view.gd")
const PropView = preload("res://presentation/first_person/prop_view.gd")
const Hud = preload("res://presentation/first_person/hud.gd")
const WorkPanel = preload("res://ui/work_panel.gd")

const SEED: int = 20260805
const DISTRICT_TILES: int = 64
const TICK_HZ: int = 20
const TICK_SECONDS: float = 1.0 / float(TICK_HZ)

const EYE_HEIGHT_M: float = 1.62
const LOOK_SENSITIVITY: float = 0.0024
const PITCH_LIMIT: float = 1.30
const LEDGER_REACH_M: float = 1.80
# cos(30 degrees): the ledger must be inside a narrow cone in front of the eye, not merely near.
const LEDGER_AIM_DOT: float = 0.866

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

var _rig: Node3D = null
var _district: Node3D = null
var _bodies: Node3D = null
var _props: Node3D = null
var _hud: Control = null
var _work_layer: CanvasLayer = null
var _work_panel: Control = null

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


# --- boot and views -------------------------------------------------------------------------

func _boot() -> void:
	var boot: Dictionary = SimBoot.playable(SEED, DISTRICT_TILES)
	world = boot["world"]
	map = boot["map"]
	var pos: Variant = world.components.get_component(int(world.player), "position")
	if pos is Dictionary:
		_curr_player = Vector2(float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]))
	_prev_player = _curr_player
	_choose_ledger_site()
	# Open on the desk rather than a random wall: the foundation's one interaction should be in
	# front of the player on the first frame.
	var to_ledger: Vector2 = _ledger_sim - _curr_player
	if to_ledger.length_squared() > 0.01:
		yaw = atan2(-to_ledger.x, -to_ledger.y)


func _build_environment() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.09, 0.11, 0.12)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.66, 0.70)
	environment.ambient_light_energy = 0.75
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
# neighbour to stand on. The search is row-major over rings, so it is deterministic; no RNG is
# drawn and the sim does not learn the desk exists.
func _choose_ledger_site() -> void:
	var start: Vector2i = Vector2i(floori(_curr_player.x), floori(_curr_player.y))
	var best: Vector2i = Vector2i(-1, -1)
	var approach: Vector2i = Vector2i(-1, -1)
	var best_d: int = 1 << 30
	for radius in range(2, 8):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var tile: Vector2i = start + Vector2i(dx, dy)
				if not _furniture_tile(tile):
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
			break
	if best == Vector2i(-1, -1):
		best = start
		approach = start
	_ledger_sim = Vector2(float(best.x) + 0.5, float(best.y) + 0.5)
	_ledger_approach = Vector2(float(approach.x) + 0.5, float(approach.y) + 0.5)


func _furniture_tile(tile: Vector2i) -> bool:
	if tile.x <= 0 or tile.y <= 0 or tile.x >= int(map.w) - 1 or tile.y >= int(map.h) - 1:
		return false
	if SimTileMap.is_solid(map, tile.x, tile.y):
		return false
	if SimTileMap.tile_at(map, tile.x, tile.y) != SimTileMap.Tile.Floor:
		return false
	var index: int = tile.y * int(map.w) + tile.x
	return int(map.surfaces[index]) != SimTileMap.SURFACE_WATER


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
	if not paused:
		_accumulator += delta
		var guard: int = 0
		while _accumulator + 0.000001 >= TICK_SECONDS and guard < 8:
			_accumulator -= TICK_SECONDS
			step_sim_once()
			guard += 1
		if guard >= 8:
			_accumulator = 0.0
	if menu_open and _work_panel != null and _work_panel.visible:
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
	if world == null:
		return
	_prev_player = _curr_player
	_bodies.call("begin_tick")
	world.step()
	var pos: Variant = world.components.get_component(int(world.player), "position")
	if pos is Dictionary:
		_curr_player = Vector2(float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]))
	_bodies.call("end_tick", world)


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
	if not menu_open:
		var verdict: String = interaction_verdict()
		if verdict == "ok":
			prompt = "E read the ledger"
		elif verdict == "away":
			prompt = "Turn to the ledger."
		elif _curr_player.distance_to(_ledger_sim) < 4.5:
			prompt = "The ledger stands near."
	_hud.call("set_state", world, int(world.player), prompt, _live_alert(), menu_open, paused)


# --- input ----------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var ke: InputEventKey = event as InputEventKey
	if ke.echo:
		return
	var code: int = ke.keycode if ke.keycode != 0 else ke.physical_keycode
	if menu_open:
		if ke.pressed and code == KEY_ESCAPE:
			close_ledger_menu()
			get_viewport().set_input_as_handled()
			return
		if ke.pressed and _work_panel != null and _work_panel.has_method("key"):
			_work_panel.call("key", ke)
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
	if event is InputEventMouseMotion and _mouse_captured and not menu_open:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		look_by(motion.relative.x, motion.relative.y)
		get_viewport().set_input_as_handled()


# --- mouse look (the gate's entry point too) ------------------------------------------------

func look_by(delta_x: float, delta_y: float) -> void:
	yaw = wrapf(yaw - delta_x * LOOK_SENSITIVITY, -PI, PI)
	pitch = clampf(pitch - delta_y * LOOK_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
	_push_aim()


func set_look(new_yaw: float, new_pitch: float) -> void:
	yaw = wrapf(new_yaw, -PI, PI)
	pitch = clampf(new_pitch, -PITCH_LIMIT, PITCH_LIMIT)
	_update_render(clampf(_accumulator / TICK_SECONDS, 0.0, 1.0))
	_push_aim()


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
	if world == null:
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
	if world == null:
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


# --- the ledger ------------------------------------------------------------------------------

## "ok", "far" or "away". Reach is measured in the sim's own metres from the body the sim moved;
## the look is the camera's forward cone. Both must pass.
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
	return "ok"


## The one interaction the scene offers. False means it did not happen and says why on screen;
## there is no silent no-op and no fake result.
func try_interact() -> bool:
	if menu_open:
		return false
	match interaction_verdict():
		"far":
			_set_alert("Nothing within reach. Walk closer to the ledger.")
			return false
		"away":
			_set_alert("You are near the ledger, but not looking at it.")
			return false
		"ok":
			open_ledger_menu()
			return true
	_set_alert("There is nothing here to use.")
	return false


func open_ledger_menu() -> void:
	if _work_panel == null:
		_work_layer = CanvasLayer.new()
		_work_layer.name = "LedgerMenu"
		add_child(_work_layer)
		_work_panel = WorkPanel.new()
		_work_panel.name = "WorkPanel"
		_work_layer.add_child(_work_panel)
	_work_panel.call("set_world", world, -1)
	_work_panel.visible = true
	menu_open = true
	_clear_held()
	_push_zero_move()
	_release_mouse()
	_alert = ""


func close_ledger_menu() -> void:
	if _work_panel != null:
		_work_panel.visible = false
	menu_open = false
	_clear_held()
	_push_zero_move()
	_capture_mouse()
	_alert = ""


func work_panel_node() -> Control:
	return _work_panel


# --- small read-only answers the gate and the HUD use ----------------------------------------

func ledger_sim_position() -> Vector2:
	return _ledger_sim


func ledger_approach_position() -> Vector2:
	return _ledger_approach


func rendered_player_position() -> Vector2:
	return _rendered_player()


func render_alpha() -> float:
	return clampf(_accumulator / TICK_SECONDS, 0.0, 1.0)


func body_view_count() -> int:
	return int(_bodies.call("count")) if _bodies != null else 0


func body_node_for(entity: int) -> MeshInstance3D:
	return _bodies.call("node_for", entity) as MeshInstance3D


## Puts the player on a sim point and makes the presentation agree at once. The gate's setup uses
## it; in play nothing calls it, because walking is the sim's job.
func place_player_at(point: Vector2) -> void:
	if world == null:
		return
	world.components.set_component(int(world.player), "position", {"x": point.x, "y": point.y})
	var velocity: Variant = world.components.get_component(int(world.player), "velocity")
	if velocity is Dictionary:
		(velocity as Dictionary)["dx"] = 0.0
		(velocity as Dictionary)["dy"] = 0.0
	_curr_player = point
	_prev_player = point
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
