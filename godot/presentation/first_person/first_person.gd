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
const SimSave = preload("res://sim/save.gd")
const SaveSlot = preload("res://presentation/first_person/save_slot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimContainers = preload("res://sim/modules/containers.gd")
const SimAllegiance = preload("res://sim/modules/allegiance.gd")
const SimChronicle = preload("res://sim/modules/chronicle.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimContext = preload("res://sim/context.gd")
const SimStances = preload("res://sim/stances.gd")
const SimSpace = preload("res://sim/space/space.gd")
const InputMapRes = preload("res://presentation/input_map.gd")
const SessionRes = preload("res://presentation/session.gd")
const RenderInterp = preload("res://presentation/interp.gd")
const DistrictView = preload("res://presentation/first_person/district_view.gd")
const BodyView = preload("res://presentation/first_person/body_view.gd")
const PropView = preload("res://presentation/first_person/prop_view.gd")
const ContainerView = preload("res://presentation/first_person/container_view.gd")
const SkyView = preload("res://presentation/first_person/sky_view.gd")
const Hud = preload("res://presentation/first_person/hud.gd")
const WorkPanel = preload("res://ui/work_panel.gd")
const WebPanel = preload("res://ui/web_panel.gd")
const InventoryPanel = preload("res://ui/inventory_panel.gd")
const ReportsPanel = preload("res://ui/reports_panel.gd")
const TalkPanel = preload("res://ui/talk_panel.gd")

const SEED: int = SimBoot.DISTRICT_SEED
# The shipped district size, the one `session.gd` boots by default. The gate overrides
# `district_tiles` with a small district before adding the scene, so it stays fast.
const DISTRICT_TILES: int = SimTileMap.DISTRICT_TILES
const TICK_HZ: int = 20
const TICK_SECONDS: float = 1.0 / float(TICK_HZ)
# The clock's ladder, as main.gd has it: 1x and 3x. 10x waits on the tick budget.
const SPEED_LADDER: Array[int] = [1, 3]
# The game's own title lives in this scene; leaving the experiment means going back to it.
const TITLE_SCENE: String = "res://presentation/main.tscn"

# The camera's eye eases to the sim's eye height (`SimSpace.eye_of`) with this time constant, so a
# crouch is not a teleport: within 1 cm of its target in about 0.15 s.
const EYE_EASE_TAU_S: float = 0.035
const LOOK_SENSITIVITY: float = 0.0024
const PITCH_LIMIT: float = 1.30
const LEDGER_REACH_M: float = 1.80
# cos(30 degrees): the ledger must be inside a narrow cone in front of the eye, not merely near.
const LEDGER_AIM_DOT: float = 0.866
# Where the eye aims on a container box: its middle, not its top or its foot.
const CONTAINER_AIM_HEIGHT_M: float = 0.92
# Interim combat feedback: a short view kick on a swing or shot, and the placeholder viewmodel's
# anchor in the lower right. No reticle and no centre dot -- docs/40 owner question 6's default.
const KICK_RADIANS: float = 0.022
const KICK_DECAY_PER_SECOND: float = 0.15
const HELD_WEAPON_POSITION: Vector3 = Vector3(0.33, -0.24, -0.58)
const HELD_WEAPON_ROTATION_DEG: Vector3 = Vector3(-6.0, 14.0, 0.0)
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
# The clock's speed: one of SPEED_LADDER. Presentation state, the same ladder main.gd keeps.
var speed: int = 1
var inventory_open: bool = false
# The conversation panel is up. A public flag because the gate reads it: every key is swallowed
# while it is true, exactly as the inventory does, and the clock keeps running.
var talk_open: bool = false

var _rig: Node3D = null
var _district: Node3D = null
var _bodies: Node3D = null
var _props: Node3D = null
var _containers: Node3D = null
var _sky: Node3D = null
var _hud: Control = null
var _work_layer: CanvasLayer = null
var _work_panel: Control = null
var _web_panel: Control = null
var _web_open: bool = false
var _inventory_layer: CanvasLayer = null
var _inventory_panel: Control = null
# The conversation panel: one of your colonists, E in reach and on the aim. `_talk_entity` is the
# body being spoken to; the panel reads the sim each frame while it is up.
var _talk_layer: CanvasLayer = null
var _talk: Control = null
var _talk_entity: int = -1
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
# Succession and the end of the run: which entity the camera is riding, whether the end panel is
# up, the chronicle's succession sentence, and the epitaph the panel speaks.
var _player_seen: int = -1
var _run_over_open: bool = false
var _news: String = ""
var _news_until_ms: int = 0
var _epitaph: Array[String] = []
# The placeholder viewmodel in the lower right, and the kick it answers a swing or shot with.
var _held_weapon: MeshInstance3D = null
var _held_weapon_size: Vector3 = Vector3.ZERO
var _kick: float = 0.0
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
	_player_seen = int(world.player)
	_choose_ledger_site()
	_eye_m = _eye_target()
	# Open on the desk rather than a random wall: the foundation's one interaction should be in
	# front of the player on the first frame.
	var to_ledger: Vector2 = _ledger_sim - _curr_player
	if to_ledger.length_squared() > 0.01:
		yaw = atan2(-to_ledger.x, -to_ledger.y)
	_push_aim()


func _build_environment() -> void:
	# The sky, the sun and the eye's light are `sky_view.gd`'s; the camera attaches them in
	# `_build_rig`, once it exists.
	_sky = SkyView.new()
	_sky.name = "Sky"
	add_child(_sky)


func _build_views() -> void:
	_district = DistrictView.new()
	_district.name = "District"
	add_child(_district)
	_district.call("build", map, SEED)

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
	camera.position = Vector3(0.0, _eye_m, 0.0)
	camera.fov = 75.0
	camera.near = 0.05
	camera.far = 240.0
	camera.current = true
	_rig.add_child(camera)
	_build_held_weapon()
	if _sky != null:
		_sky.call("build", camera)


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
	if _sky != null:
		# Day, night, weather and the carried light every frame -- the sim's tick and the light
		# component can change between frames, and the end panel's dim still has a sky behind it.
		_sky.call("update", world)
	if _run_over_open:
		# The top-down end screen holds the clock still; so does this one. Input is swallowed in
		# `_input`, and no move or aim is proposed.
		_update_render(clampf(_accumulator / TICK_SECONDS, 0.0, 1.0))
		_update_hud()
		return
	if not paused:
		# main.gd's rule: the clock runs at the speed, the debt is clamped to what one frame may run,
		# and the ticks per frame are capped the same way (five ticks at each speed step).
		var rate: int = SessionRes.run_rate(speed, world)
		var cap: int = maxi(1, 5 * rate)
		_accumulator = RenderInterp.clamp_debt(_accumulator + delta * float(rate), TICK_SECONDS, cap)
		var guard: int = 0
		while _accumulator + 0.000001 >= TICK_SECONDS and guard < cap:
			_accumulator -= TICK_SECONDS
			step_sim_once()
			guard += 1
	if inventory_open:
		_refresh_inventory()
	if talk_open:
		_refresh_talk()
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
	_kick = move_toward(_kick, 0.0, delta * KICK_DECAY_PER_SECOND)
	_update_held_weapon()
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
		camera.rotation = Vector3(pitch + _kick, 0.0, 0.0)
		camera.position = Vector3(0.0, _eye_m, 0.0)
	if _bodies != null:
		_bodies.call("apply", world, alpha)


func _update_hud() -> void:
	if _hud == null or world == null:
		return
	var prompt: String = ""
	if inventory_open:
		# The sheet is over the world and takes the words with it; Escape is the way back.
		prompt = ""
	elif talk_open:
		# The conversation panel carries every word; the HUD is hidden while it is up.
		prompt = ""
	elif not menu_open and not _mouse_captured:
		prompt = "Mouse released. Click to look again."
	elif not menu_open:
		var verdict: String = interaction_verdict()
		if verdict == "ok":
			prompt = _ledger_prompt()
		else:
			var box_verdict: String = container_verdict()
			var box_name: String = _container_kind(container_focus())
			var verb: String = verb_prompt()
			var person_verdict: String = talk_verdict()
			var person_name: String = _talk_name(talk_focus())
			if box_verdict == "ok":
				prompt = "E open the %s" % box_name
			elif person_verdict == "ok":
				prompt = "E talk to %s" % person_name
			elif verb != "":
				prompt = verb
			elif box_verdict == "away":
				prompt = "Turn to the %s." % box_name
			elif box_verdict == "spent":
				prompt = "You have already been through this %s." % box_name
			elif person_verdict == "away":
				prompt = "Turn to %s." % person_name
			elif verdict == "away":
				prompt = "Turn to the ledger."
			elif _curr_player.distance_to(_ledger_sim) < 4.5:
				prompt = "The ledger stands near."
	_hud.set("time_words", SessionRes.speed_words(speed, paused, world))
	_hud.call("set_state", world, int(world.player), prompt, _live_alert(), menu_open, paused, inventory_open, _live_news())
	_hud.visible = not inventory_open and not talk_open


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
	if talk_open:
		# The conversation takes every key while it is up: walking, the aim, the fight buttons, the
		# stance ladder and the save keys never reach the world. Goodbye is the one action.
		if ke.pressed and code == KEY_ESCAPE:
			close_talk()
		get_viewport().set_input_as_handled()
		return
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
	if ke.pressed and code == KEY_F:
		swing()
		get_viewport().set_input_as_handled()
		return
	if ke.pressed and code == KEY_G:
		fire()
		get_viewport().set_input_as_handled()
		return
	if ke.pressed and code == KEY_R:
		reload_weapon()
		get_viewport().set_input_as_handled()
		return
	# The clock's keys, the top-down game's own (`input_map.gd`'s "slower" and "faster"). Refused under the
	# ledger, the sheet and the end panel, which consume every key before this point, as main.gd refuses them.
	var step: int = _speed_step_of(ke)
	if step != 0:
		if ke.pressed:
			_step_speed(step)
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
	if ke.pressed and code == KEY_F5:
		save_game()
		get_viewport().set_input_as_handled()
		return
	if ke.pressed and code == KEY_F9:
		load_game()
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
	if talk_open:
		# The conversation has the mouse: a click is the panel's Goodbye, never a recapture or a
		# swing. The panel's own `_gui_input` handles it.
		return
	if event is InputEventMouseMotion and _mouse_captured and not menu_open and not inventory_open:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		look_by(motion.relative.x, motion.relative.y)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and not menu_open and not inventory_open:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if not _mouse_captured:
			# The first click is the way back into mouse look, and only that.
			if button.pressed:
				_capture_mouse()
				get_viewport().set_input_as_handled()
			return
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			# The top-down left click: the trigger with a firearm in hand, the swing otherwise.
			attack()
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


func _push_aim(force: bool = false) -> void:
	if world == null or _run_over_open or _waiting_for_heir():
		return
	var dir: Vector3 = _forward_horizontal()
	var radians: float = atan2(dir.z, dir.x)
	if radians == 0.0:
		radians = 0.0
	if force or _last_aim > 1.0e8 or absf(angle_difference(radians, _last_aim)) > 0.0005:
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


# --- interim combat input --------------------------------------------------------------------
#
# INTERIM. docs/40-first-person-spatial-contract slices 3 ("Pitch on the aim"), 5 ("The shot as a
# ray") and 6 ("Parts from geometry") replace all of this. Until then the planar sim is still the
# authority and it takes one bearing: the camera's look yaw is pushed as the ordinary `aim`
# command, and the sim projects that bearing itself -- melee selects a body at the weapon's
# `reachMetres`, ranged at `rangeMetres`, both through `SimAim.radians_of`. The look direction's
# floor projection (`_forward_horizontal`) IS the aim; no target point and no pitch crosses this
# boundary, because the sim has neither a height nor a ray yet. Slice 3 adds pitch to `aim`, slice
# 5 makes the shot a ray with a contact point, and slice 6 takes the body part from that contact.
#
# The buttons and keys are the top-down screen's own (`input_map.gd`): the left mouse click is
# "the trigger if a firearm is in hand, the swing otherwise", F is swing, G is fire, R is reload.
# A refused action is the sim's refusal; the scene adds no words for it.

func attack() -> void:
	if not _can_fight():
		return
	# The aim is pushed with the press, as the top-down click does, so the bearing the sim resolves
	# is the bearing the camera shows even if the last look event was a while ago.
	_push_aim(true)
	if world.components.has_component(int(world.player), "rangedWeapon"):
		world.commands.push({"type": "fire"})
	else:
		world.commands.push({"type": "swing"})
	_kick_camera()


func swing() -> void:
	if not _can_fight():
		return
	_push_aim(true)
	world.commands.push({"type": "swing"})
	_kick_camera()


func fire() -> void:
	if not _can_fight():
		return
	_push_aim(true)
	world.commands.push({"type": "fire"})
	_kick_camera()


func reload_weapon() -> void:
	if not _can_fight():
		return
	world.commands.push({"type": "reload"})


func _can_fight() -> bool:
	return world != null and not menu_open and not inventory_open and not talk_open and not _run_over_open and not _waiting_for_heir()


func _kick_camera() -> void:
	# A short view kick, not a shake and not a number: the one piece of felt feedback a swing or a
	# shot gets here. The top-down screen shows a hit flash and a shake on the body; it shows no
	# hit or miss word, so this scene adds none either.
	_kick = -KICK_RADIANS


# The placeholder viewmodel: a box in the lower right, sized by the weapon's own class cue (a
# firearm's range, a melee weapon's reach), hidden for bare hands. Art comes later; this is the
# shape that says something is in hand. It has no collision and never moves on its own.
func _build_held_weapon() -> void:
	_held_weapon = MeshInstance3D.new()
	_held_weapon.name = "HeldWeaponPlaceholder"
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.08, 0.09, 0.45)
	_held_weapon.mesh = box
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.36, 0.31, 0.24)
	material.roughness = 1.0
	_held_weapon.material_override = material
	_held_weapon.position = HELD_WEAPON_POSITION
	_held_weapon.rotation_degrees = HELD_WEAPON_ROTATION_DEG
	_held_weapon.visible = false
	camera.add_child(_held_weapon)


func _update_held_weapon() -> void:
	if _held_weapon == null or world == null:
		return
	if _run_over_open:
		_held_weapon.visible = false
		return
	var player: int = int(world.player)
	var armed: bool = not SimMelee.is_unarmed(world, player)
	_held_weapon.visible = armed
	if not armed:
		return
	# `SimMelee.is_unarmed` is the one predicate for "fighting with nothing" (BARE_HANDS carries
	# the `unarmed` flag; a ranged weapon always counts). The box's length follows the profile's
	# own reach: a rifle reads longer than a pistol, a bat shorter than a spear.
	var size: Vector3 = Vector3(0.07, 0.08, 0.45)
	var ranged: Variant = world.components.get_component(player, "rangedWeapon")
	if ranged is Dictionary:
		var range_metres: float = float((ranged as Dictionary).get("rangeMetres", 12.0))
		size = Vector3(0.09, 0.10, clampf(0.30 + range_metres * 0.018, 0.38, 0.95))
	else:
		var melee: Variant = world.components.get_component(player, "meleeWeapon")
		if melee is Dictionary:
			var reach: float = float((melee as Dictionary).get("reachMetres", 1.0))
			size = Vector3(0.07, 0.07, clampf(0.18 + reach * 0.35, 0.30, 0.85))
	if not size.is_equal_approx(_held_weapon_size):
		_held_weapon_size = size
		(_held_weapon.mesh as BoxMesh).size = size


func held_weapon_visible() -> bool:
	return _held_weapon != null and _held_weapon.visible


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
	var eye: Vector3 = Vector3(_rendered_player().x, _eye_m, _rendered_player().y)
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


## The one interaction. The order is the ledger, then an openable container, then a colonist in reach
## and on the aim, then the world's first tile verb (a door or window), then the container's, the
## person's and the ledger's refusals -- so a higher rung always wins, an aimed door is not blocked
## by a box or a body merely standing near it, and every refusal says which rule failed in the
## ledger's words.
func try_interact() -> bool:
	if menu_open or inventory_open or talk_open:
		return false
	if interaction_verdict() == "ok":
		open_ledger_menu()
		return true
	var box_verdict: String = container_verdict()
	if box_verdict == "ok":
		open_container(container_focus())
		return true
	var person_verdict: String = talk_verdict()
	if person_verdict == "ok":
		open_talk(talk_focus())
		return true
	var row: Dictionary = verb_row()
	if not row.is_empty():
		world.commands.push(row["command"])
		return true
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
	if person_verdict != "none":
		var person_name: String = _talk_name(talk_focus())
		match person_verdict:
			"far":
				_set_alert("Nothing within reach. Walk closer to %s." % person_name)
				return false
			"blocked":
				_set_alert("%s is behind a wall." % person_name)
				return false
			"away":
				_set_alert("You are near %s, but not looking at them." % person_name)
				return false
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


# --- talking to a colonist -------------------------------------------------------------------
#
# The first slice of docs/39's conversations: E at one of your own people, in reach and on the aim,
# opens a small panel that says how they are and what they are doing. Every word is a read model's
# (`TalkPanel`), so the conversation cannot know more than the Colony drawer does. It decides
# nothing: the one action is Goodbye. Raiders, settlers and zombies are never talkable --
# `SimAllegiance.is_colony` is the faction gate, and the identity requirement is what makes it a
# person with a name rather than any body the sim owns.
#
# THE PAUSE POLICY is the inventory's, the same reversible default docs/33 leaves open: this panel
# does not stop the clock. `_clear_held` + `_push_zero_move` stop the body, `_input` swallows every
# key while it is open, and the sim keeps stepping. If the owner later chooses time-stopped
# conversations, the one change is to hold the accumulator.

## True for a body the player can talk to: alive, not a corpse, not the player, not a zombie, and a
## named member of the colony. A raider or a settler has an identity and is still not one of yours.
func talkable(entity: int) -> bool:
	if world == null or entity < 0:
		return false
	if entity == int(world.player):
		return false
	if not world.entities.is_alive(entity):
		return false
	if world.components.has_component(entity, "corpse"):
		return false
	if world.components.has_component(entity, "zombieType") or world.components.has_component(entity, "shambler"):
		return false
	if not world.components.has_component(entity, "identity"):
		return false
	return SimAllegiance.is_colony(world, entity)


## The colonist the eye is on, or -1: the nearest talkable body inside the same narrow cone the
## ledger and the containers use.
func talk_target() -> int:
	if world == null:
		return -1
	var eye: Vector3 = Vector3(_rendered_player().x, _eye_m, _rendered_player().y)
	var look: Vector3 = look_direction()
	var best: int = -1
	var best_distance: float = 1.0e9
	for entity in world.components.query(["position", "body"]):
		var e: int = int(entity)
		if not talkable(e):
			continue
		var to: Vector3 = _talk_point(e) - eye
		var distance: float = to.length()
		if distance <= 0.000001:
			continue
		if look.dot(to / distance) < LEDGER_AIM_DOT:
			continue
		if distance < best_distance:
			best_distance = distance
			best = e
	return best


## The nearest talkable body within reach whatever the aim, for the "turn to them" refusal.
func talk_near() -> int:
	if world == null:
		return -1
	var best: int = -1
	var best_distance: float = LEDGER_REACH_M
	for entity in world.components.query(["position", "body"]):
		var e: int = int(entity)
		if not talkable(e):
			continue
		var distance: float = _curr_player.distance_to(_entity_position(e))
		if distance <= best_distance:
			best_distance = distance
			best = e
	return best


## "ok", "far", "away", "blocked" or "none", the same ladder the containers use: the aimed person is
## measured against the reach, then the sim's own sight. A person in reach but not aimed at reads
## "away", so the refusal says to turn rather than to walk closer.
func talk_verdict() -> String:
	if world == null:
		return "none"
	var target: int = talk_target()
	var near: int = talk_near()
	if target < 0:
		return "away" if near >= 0 else "none"
	if _curr_player.distance_to(_entity_position(target)) > LEDGER_REACH_M:
		return "away" if near >= 0 else "far"
	if not talk_in_sight(target):
		return "blocked"
	return "ok"


## The person the verdict is speaking about: the near one for "away", the aimed one otherwise.
func talk_focus() -> int:
	var target: int = talk_target()
	var near: int = talk_near()
	if near >= 0 and (target < 0 or _curr_player.distance_to(_entity_position(target)) > LEDGER_REACH_M):
		return near
	return target


## A person through an opaque wall is not in reach, however close the geometry is -- the same
## `vision.detail` read the ledger and the boxes make.
func talk_in_sight(entity: int) -> bool:
	if world == null or world.vision == null or entity < 0:
		return false
	var at: Vector2 = _entity_position(entity)
	return int(world.vision.call("detail", int(world.player), at.x, at.y)) != 0


## The point a look is judged against: the colonist's own eye, the height the sim gives them.
func _talk_point(entity: int) -> Vector3:
	var at: Vector2 = _entity_position(entity)
	return Vector3(at.x, float(SimSpace.eye_of(world, entity)) / 1000.0, at.y)


func _entity_position(entity: int) -> Vector2:
	if world == null or entity < 0:
		return Vector2.ZERO
	var pos: Variant = world.components.get_component(entity, "position")
	if not (pos is Dictionary):
		return Vector2.ZERO
	return Vector2(float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]))


func _talk_name(entity: int) -> String:
	if entity < 0:
		return "them"
	return TalkPanel.name_of(world, entity)


func _ensure_talk_panel() -> void:
	if _talk != null:
		return
	_talk_layer = CanvasLayer.new()
	_talk_layer.name = "TalkUI"
	add_child(_talk_layer)
	_talk = TalkPanel.new()
	_talk.name = "TalkPanel"
	_talk.visible = false
	_talk_layer.add_child(_talk)
	if _talk.has_signal("closed"):
		_talk.connect("closed", close_talk)


## Opens the conversation with `entity`. The panel reads the sim; this only shows it and stops the
## body, exactly as the inventory sheet does.
func open_talk(entity: int) -> void:
	if world == null or entity < 0 or menu_open or inventory_open or talk_open:
		return
	_ensure_talk_panel()
	if _talk == null:
		return
	talk_open = true
	_talk_entity = entity
	_talk.call("show_colonist", world, entity)
	_place_talk()
	_talk.visible = true
	_clear_held()
	_push_zero_move()
	_release_mouse()
	_alert = ""
	if _hud != null:
		_hud.visible = false


func close_talk() -> void:
	if not talk_open:
		return
	talk_open = false
	_talk_entity = -1
	if _talk != null:
		_talk.visible = false
	_clear_held()
	_push_zero_move()
	_capture_mouse()
	_alert = ""
	if _hud != null:
		_hud.visible = true


# Every frame the conversation is up: the read models again, so a need or an injury that changes
# while the player listens is said as it is now. A colonist who dies or walks away closes it.
func _refresh_talk() -> void:
	if not talk_open or _talk == null:
		return
	if not talkable(_talk_entity):
		close_talk()
		return
	_talk.call("show_colonist", world, _talk_entity)
	_place_talk()


func _place_talk() -> void:
	if _talk == null:
		return
	var view: Vector2 = get_viewport().get_visible_rect().size
	var want: Vector2 = _talk.size
	var at: Vector2 = Vector2(floorf((view.x - want.x) * 0.5), view.y - want.y - 96.0)
	_talk.position = Vector2(maxf(16.0, at.x), maxf(96.0, at.y))


func talk_panel_node() -> Control:
	return _talk


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


func inventory_panel_node() -> Control:
	return _inventory_panel


func sky_view() -> Node3D:
	return _sky


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
	if talk_open:
		close_talk()
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
	if talk_open:
		close_talk()
	if menu_open:
		close_ledger_menu()
	_clear_held()
	_push_zero_move()
	_release_mouse()
	if _held_weapon != null:
		_held_weapon.visible = false
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
# --- save and load (F5 and F9) ----------------------------------------------------------------

# The top-down game's sim API (`SimSave`), in the first-person slot. The ledger consumes every key
# while it is open, so F5 and F9 are refused there exactly as the other keys are.
func save_game() -> bool:
	if world == null:
		return false
	if not SaveSlot.write(SimSave.encode_save(SimSave.create_save(world))):
		_set_alert("The save did not write.")
		return false
	_set_alert("Saved.")
	return true


func load_game() -> bool:
	if world == null:
		return false
	var raw: String = SaveSlot.read()
	if raw.is_empty():
		_set_alert("Nothing to load.")
		return false
	var parsed: Dictionary = SimSave.decode_save(raw)
	var snap: Variant = parsed.get("snapshot", {})
	# The same two refusals the top-down load makes: a finished run is not a run to go back to.
	if parsed.has("__error") or (snap is Dictionary and bool((snap as Dictionary).get("runOver", false))) or bool(world.runOver):
		_set_alert("That save will not load.")
		return false
	SimSave.apply_save(world, parsed)
	_after_load()
	_set_alert("Loaded.")
	return true


# The restored sim is the same world object, so the view is re-read from it: the camera snaps to the
# restored position with no interpolation from the old one, the body views are rebuilt from the
# restored entities, and an open ledger closes.
func _after_load() -> void:
	if menu_open:
		close_ledger_menu()
	_clear_held()
	_last_aim = 1.0e9
	_push_zero_move()
	_push_aim()
	_bodies.call("reset", world)
	snap_render_to_sim()


# --- the clock's speed: the top-down game's keys and ladder ---------------------------------------

# -1 for "slower", +1 for "faster", 0 for any other key. The keys are read from input_map.gd's BINDINGS,
# the table the top-down game reads, with the Ctrl state matched the same way.
func _speed_step_of(ke: InputEventKey) -> int:
	for action in ["slower", "faster"]:
		var row: Dictionary = InputMapRes.BINDINGS[action] as Dictionary
		if bool(row["ctrl"]) != ke.ctrl_pressed:
			continue
		if (row["keys"] as Array).has(ke.keycode):
			return -1 if action == "slower" else 1
	return 0


# One rung along SPEED_LADDER, clamped at both ends (main.gd's _step_speed).
func _step_speed(step: int) -> void:
	var at: int = SPEED_LADDER.find(speed)
	if at < 0:
		at = 0
	speed = SPEED_LADDER[clampi(at + step, 0, SPEED_LADDER.size() - 1)]
