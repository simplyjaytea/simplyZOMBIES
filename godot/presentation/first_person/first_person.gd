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
const SimContext = preload("res://sim/context.gd")
const SimStances = preload("res://sim/stances.gd")
const SimSpace = preload("res://sim/space/space.gd")
const InputMapRes = preload("res://presentation/input_map.gd")
const DistrictView = preload("res://presentation/first_person/district_view.gd")
const BodyView = preload("res://presentation/first_person/body_view.gd")
const PropView = preload("res://presentation/first_person/prop_view.gd")
const Hud = preload("res://presentation/first_person/hud.gd")
const WorkPanel = preload("res://ui/work_panel.gd")
const WebPanel = preload("res://ui/web_panel.gd")
const ReportsPanel = preload("res://ui/reports_panel.gd")

const SEED: int = SimBoot.DISTRICT_SEED
# The shipped district size, the one `session.gd` boots by default. The gate overrides
# `district_tiles` with a small district before adding the scene, so it stays fast.
const DISTRICT_TILES: int = SimTileMap.DISTRICT_TILES
const TICK_HZ: int = 20
const TICK_SECONDS: float = 1.0 / float(TICK_HZ)

# The camera's eye eases to the sim's eye height (`SimSpace.eye_of`) with this time constant, so a
# crouch is not a teleport: within 1 cm of its target in about 0.15 s.
const EYE_EASE_TAU_S: float = 0.035
const LOOK_SENSITIVITY: float = 0.0024
const PITCH_LIMIT: float = 1.30
const LEDGER_REACH_M: float = 1.80
# cos(30 degrees): the ledger must be inside a narrow cone in front of the eye, not merely near.
const LEDGER_AIM_DOT: float = 0.866
# How finely the look ray is walked through the tile grid when it looks for a door or window (metres).
const VERB_STEP_M: float = 0.02

const MOVE_KEYS: Array[int] = [KEY_W, KEY_A, KEY_S, KEY_D]

# Presentation only: a fixed district seed so a first boot is the same district every time. The
# world's own generation remains the sim's business.
var world: Variant = null
var map: Variant = null
# The district size this scene boots. Set before the scene enters the tree (the gate's small override).
var district_tiles: int = DISTRICT_TILES
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
var _web_panel: Control = null
var _web_open: bool = false
# The ledger's Reports page. `_reports_read` is the chronicle's read mark: entries before it have been read.
# Presentation state only -- the sim is never written -- and it starts at 0 on every boot.
var _reports_open: bool = false
var _reports_read: int = 0
var _reports: Control = null
var _reports_chip: Control = null

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
# The camera's eye height in metres, eased toward the sim's posture eye. Presentation only.
var _eye_m: float = 1.62
# The Ctrl-ladder rung last chosen; releasing Shift returns to it (as input_map.gd does).
var _selected_stance: int = SimStances.Stance.Walk
var _verb_key: Array = []
var _verb_row: Dictionary = {}


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
	var boot: Dictionary = SimBoot.playable(SEED, district_tiles)
	world = boot["world"]
	map = boot["map"]
	var pos: Variant = world.components.get_component(int(world.player), "position")
	if pos is Dictionary:
		_curr_player = Vector2(float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]))
	_prev_player = _curr_player
	_choose_ledger_site()
	_eye_m = _eye_target()
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
	camera.position = Vector3(0.0, _eye_m, 0.0)
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
	if not paused:
		_accumulator += delta
		var guard: int = 0
		while _accumulator + 0.000001 >= TICK_SECONDS and guard < 8:
			_accumulator -= TICK_SECONDS
			step_sim_once()
			guard += 1
		if guard >= 8:
			_accumulator = 0.0
	if menu_open:
		if _web_open and _web_panel != null and _web_panel.visible:
			_web_panel.call("set_world", world, int(_web_panel.get("_who")))
		elif _work_panel != null and _work_panel.visible:
			var who: int = -1
			if _work_panel.has_method("selected"):
				who = int(_work_panel.call("selected"))
			_work_panel.call("set_world", world, who)
	_ease_eye(delta)
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
		camera.position = Vector3(0.0, _eye_m, 0.0)
	if _bodies != null:
		_bodies.call("apply", world, alpha)


func _update_hud() -> void:
	if _hud == null or world == null:
		return
	var prompt: String = ""
	if not menu_open and not _mouse_captured:
		prompt = "Mouse released. Click to look again."
	elif not menu_open:
		var verdict: String = interaction_verdict()
		if verdict == "ok":
			prompt = _ledger_prompt()
		elif verb_prompt() != "":
			prompt = verb_prompt()
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
			if _reports_open:
				close_reports()
			elif _web_open:
				_show_work_panel()
			else:
				close_ledger_menu()
			get_viewport().set_input_as_handled()
			return
		if ke.pressed and _work_panel != null and _work_panel.has_method("key") and not _web_open and not _reports_open:
			_work_panel.call("key", ke)
		get_viewport().set_input_as_handled()
		return
	if ke.pressed and code == KEY_ESCAPE:
		# Outside the ledger, Escape is the way out of the pointer trap: the mouse is released
		# and the HUD asks for a click to resume looking.
		_release_mouse()
		_push_zero_move()
		get_viewport().set_input_as_handled()
		return
	if ke.pressed and code == KEY_E:
		try_interact()
		get_viewport().set_input_as_handled()
		return
	# The stance keys are the top-down game's, read from input_map.gd's BINDINGS. Shift is the sprint
	# latch: press sprints, release returns to the last Ctrl rung. Ctrl+S is a stance, never a step back.
	if code == KEY_SHIFT:
		_push_stance(SimStances.Stance.Sprint if ke.pressed else _selected_stance)
		get_viewport().set_input_as_handled()
		return
	var rung: int = _stance_rung_of(ke)
	if rung >= 0:
		if ke.pressed:
			_selected_stance = rung
			_push_stance(rung)
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
		return
	if event is InputEventMouseButton and not menu_open and not _mouse_captured:
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
	var eye: Vector3 = Vector3(_rendered_player().x, _eye_m, _rendered_player().y)
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

## "ok", "far", "blocked" or "away". Reach is measured in the sim's own metres from the body the
## sim moved; the sim's own visibility decides whether a wall is in the way; the look is the
## camera's forward cone. Every one must pass.
func interaction_verdict() -> String:
	if world == null or _props == null:
		return "none"
	if _curr_player.distance_to(_ledger_sim) > LEDGER_REACH_M:
		return "far"
	var point: Vector3 = _props.call("ledger_world_point")
	var eye: Vector3 = Vector3(_rendered_player().x, _eye_m, _rendered_player().y)
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


## The one interaction the scene offers. False means it did not happen and says why on screen;
## there is no silent no-op and no fake result.
func try_interact() -> bool:
	if menu_open:
		return false
	# The ledger keeps priority when it is in reach and aimed at; otherwise the world's first verb.
	if interaction_verdict() == "ok":
		open_ledger_menu()
		return true
	var row: Dictionary = verb_row()
	if not row.is_empty():
		world.commands.push(row["command"])
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
	_reports_ensure()
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
	_reports_hide()
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


# --- world verbs: E on a door or a window ------------------------------------------------------

# The prompt E would answer with, in the first verb's own words, or "" when the sim offers nothing.
func verb_prompt() -> String:
	var row: Dictionary = verb_row()
	if row.is_empty():
		return ""
	return "E " + String(row["text"])


# The first verb `SimContext.verbs_at` offers for the tile the eye is on, as the right-click menu would
# offer it there: the same rows, and E pushes the row's command verbatim (`main._context_pick`). No
# verb is decided here. Cached per tick and tile, because the sim's answer changes only with those.
func verb_row() -> Dictionary:
	var hit: Dictionary = eye_tile_hit()
	if hit.is_empty() or world == null:
		return {}
	var key: Array = [int(world.tick), hit["tile"], hit["kind"]]
	if key != _verb_key:
		_verb_key = key
		_verb_row = {}
		var offered: Array[Dictionary] = SimContext.verbs_at(world, int(world.player), {"kind": hit["kind"], "entity": -1, "tile": hit["tile"]})
		for row in offered:
			if not (row["command"] as Dictionary).is_empty():
				_verb_row = row
				break
	return _verb_row


# The tile the eye is on: the look ray walked through the tile grid from the sim's position to the
# ledger's reach, and the first tile that is a door, a window or solid. Returns {tile, kind} with kind
# "door" (a door tile, which `pick.gd` would name a door) or "ground", or {} when the ray meets none.
# Presentation-side only: slice 2 of docs/40 moves this test into `SimSpace.segment_clear`, which
# then answers it for the sim too. Until then this one small function is the only place it lives.
func eye_tile_hit() -> Dictionary:
	if world == null or map == null:
		return {}
	var look: Vector3 = look_direction()
	var dir: Vector2 = Vector2(look.x, look.z)
	if dir.length_squared() < 0.000001:
		return {}
	dir = dir.normalized()
	var last: Vector2i = Vector2i(-1000000, -1000000)
	var d: float = 0.0
	while d <= LEDGER_REACH_M:
		var p: Vector2 = _curr_player + dir * d
		var t: Vector2i = Vector2i(floori(p.x), floori(p.y))
		if t != last:
			last = t
			var kind: String = _verb_kind(t)
			if kind != "":
				return {"tile": t, "kind": kind}
		d += VERB_STEP_M
	return {}


func _verb_kind(t: Vector2i) -> String:
	if t.x < 0 or t.y < 0 or t.x >= int(map.w) or t.y >= int(map.h):
		return ""
	var tile: int = SimTileMap.tile_at(map, t.x, t.y)
	if tile == SimTileMap.Tile.Door:
		return "door"
	if tile == SimTileMap.Tile.Window or SimTileMap.is_solid(map, t.x, t.y):
		return "ground"
	return ""


# --- stance and gait: the top-down keys, and an eye that follows the posture ------------------

# The stance command the top-down game pushes (`input_map.gd`'s `_push_stance`): the sim decides.
func _push_stance(target: int) -> void:
	if world == null:
		return
	world.commands.push({"type": "stance", "stance": target})


# The Ctrl-ladder rung a key event asks for, read from `input_map.gd`'s BINDINGS -- the table the top-down
# game reads -- or -1 when no stance binding matches the event's keycode and Ctrl state.
func _stance_rung_of(ke: InputEventKey) -> int:
	for action in InputMapRes.BINDINGS.keys():
		var row: Dictionary = InputMapRes.BINDINGS[action] as Dictionary
		if not row.has("stance"):
			continue
		if bool(row["ctrl"]) != ke.ctrl_pressed:
			continue
		if (row["keys"] as Array).has(ke.keycode):
			return int(row["stance"])
	return -1


# The eye height the sim's posture gives, in metres (`SimSpace.eye_of` is millimetres).
func _eye_target() -> float:
	if world == null:
		return _eye_m
	return float(SimSpace.eye_of(world, int(world.player))) / 1000.0


# Moves the eye toward its posture target with an exponential ease, so a stance change is not a jump.
func _ease_eye(delta: float) -> void:
	_eye_m = lerpf(_eye_m, _eye_target(), 1.0 - exp(-delta / EYE_EASE_TAU_S))


# --- the ledger's Reports page --------------------------------------------------------------

# "E read the ledger, new reports" while any entry is past the read mark; the plain ledger prompt otherwise.
func _ledger_prompt() -> String:
	if ReportsPanel.unread(world, _reports_read) > 0:
		return "E read the ledger, new reports"
	return "E read the ledger"


# Builds the Reports page and its chip once, then shows the chip for the open ledger.
func _reports_ensure() -> void:
	if _reports == null:
		_reports = ReportsPanel.new()
		_reports.name = "ReportsPage"
		_reports.visible = false
		_work_layer.add_child(_reports)
		_reports_chip = ReportsPanel.Chip.new()
		_reports_chip.name = "ReportsChip"
		_work_layer.add_child(_reports_chip)
		_reports_chip.activated.connect(open_reports)
	_reports_chip.visible = true
	var view: Vector2 = get_viewport().get_visible_rect().size
	_reports_chip.position = Vector2(view.x - _reports_chip.size.x - 16.0, 16.0)


# The page is up: it shows what was written since the read mark, marks that as new, and then the whole
# record is read -- the mark moves to the end, so the prompt stops asking.
func open_reports() -> void:
	if not menu_open or _reports == null:
		return
	_reports_open = true
	if _work_panel != null:
		_work_panel.visible = false
	if _web_panel != null:
		_web_panel.visible = false
	_web_open = false
	_reports.call("show_reports", world, _reports_read)
	_reports.position = Vector2(16.0, 16.0)
	_reports.visible = true
	_reports_chip.visible = false
	_reports_read = int((world.chronicle as Array).size())


# Escape from the Reports page: back to the work grid, not the street.
func close_reports() -> void:
	if not _reports_open:
		return
	_reports_open = false
	if _reports != null:
		_reports.visible = false
	if _reports_chip != null:
		_reports_chip.visible = menu_open
	_show_work_panel()


func _reports_hide() -> void:
	_reports_open = false
	if _reports != null:
		_reports.visible = false
	if _reports_chip != null:
		_reports_chip.visible = false


func reports_node() -> Control:
	return _reports


func reports_chip_node() -> Control:
	return _reports_chip
