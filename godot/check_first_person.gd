extends SceneTree
# The first-person foundation's gate. It instantiates the actual scene, drives it with the engine's
# real input dispatch (`root.push_input`) and the scene's own 20 Hz frame function, and asks what
# the sim and the screen did about it.
#
# Lanes, each with a true positive and a true negative:
#   SHAPE     the scene is the opt-in scene, it builds a district and a HUD, boots a real world,
#             and contains no physics body or collision shape at all. The physics scan is proved
#             against a deliberately added CharacterBody3D before it is trusted.
#   MAPPING   sim (x, y) lands on Godot (x, z) with the eye at presentation height, and the
#             axes are not swapped (a point whose x and y differ proves it).
#   NPC       the fresh boot has no colonist doing a job; the same colony after twenty sim ticks
#             has one, the tick count advanced by exactly the steps taken, and a colonist has a
#             body view while the player has none.
#   MOVE      W walks the sim's body, the `move` command carries the camera's forward vector and
#             the `aim` command its bearing; the camera follows the interpolated sim position;
#             releasing W stops the body dead. A frame without a key moves nothing.
#   YAW       yaw zero walks toward -z and proposes the sim's north bearing; a quarter turn walks
#             toward +x and proposes east. Both directions are asserted, so an axis swap is red.
#   BLOCK     walking into a wall leaves the body in its tile; walking the other way crosses it.
#             The collision is the sim's own `_integrate_movement`, because there is no other body.
#   LEDGER    E far away is refused and says so; E within reach but looking away is refused and
#             says so; E within reach and looking at the ledger opens the real work panel. J is not
#             a way to open it, before or after. Escape closes it and gives the mouse and walking
#             back.
#   PRIORITY  a click on the panel's first priority cell dispatches a real `job.priority`, the
#             colonist's row changes and turns Manual, and the player is never one of the rows.
#   SPEECH    every line the first-person HUD draws is digit-free, it names the controls and the
#             ledger, there is no progress bar in the tree, and the digit scanner is proved against
#             a fabricated line.

const SCENE_PATH: String = "res://presentation/first_person/first_person.tscn"
const WorkPanel = preload("res://ui/work_panel.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const Assets = preload("res://presentation/first_person/assets.gd")

const TICK_SECONDS: float = 1.0 / 20.0
const EPSILON: float = 0.0001

var _failures: Array[String] = []
var _skips: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var old_size: Vector2i = root.size
	root.size = Vector2i(1280, 720)
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		_fail("SCENE", "could not load %s" % SCENE_PATH)
		_finish(old_size)
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	scene.set_process(false)
	await process_frame

	var ok: bool = _scene_shape(scene)
	if ok:
		var spawn: Vector2 = scene.call("rendered_player_position")
		ok = _npc(scene) and ok
		ok = _mapping(scene) and ok
		ok = _movement(scene) and ok
		ok = _yaw(scene) and ok
		ok = _blocked(scene) and ok
		ok = _ledger(scene, spawn) and ok
		ok = _priority(scene) and ok
		ok = _menu(scene) and ok
		ok = _speech(scene) and ok
	scene.queue_free()
	await process_frame
	_finish(old_size, ok)


func _finish(old_size: Vector2i, ok: bool = false) -> void:
	root.size = old_size
	if ok:
		for skip in _skips:
			print("FIRST_PERSON_SKIP " + skip)
		print("FIRST_PERSON_OK the opt-in scene boots the real sim, maps sim x/y to Godot x/z, walks only through sim commands and sim collision, interpolates the camera, refuses E out of reach or off the aim and opens the real work panel in reach, dispatches a priority that changes a colonist's row, closes cleanly on Escape, steps NPC jobs, and draws a digit-free prose HUD")
		quit(0)
		return
	for failure in _failures:
		push_error("FIRST_PERSON_FAIL " + failure)
	quit(1)


func _fail(lane: String, message: String) -> bool:
	_failures.append(lane + ": " + message)
	return false


# --- SHAPE ----------------------------------------------------------------------------------

func _scene_shape(scene: Node) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var map: Variant = scene.get("map")
	var camera: Camera3D = scene.get("camera") as Camera3D
	if world == null:
		return _fail("SHAPE", "the scene booted no sim world")
	if map == null:
		return _fail("SHAPE", "the scene kept no map")
	if camera == null or not camera.current:
		ok = _fail("SHAPE", "the scene has no current Camera3D")
	if scene.get_node_or_null("District/GroundTiles") == null:
		ok = _fail("SHAPE", "the district did not build its ground mesh")
	if scene.get_node_or_null("District/SolidTiles") == null:
		ok = _fail("SHAPE", "the district did not build its solid-tile mesh")
	if scene.get_node_or_null("SafeSpawnProps") == null:
		ok = _fail("SHAPE", "the safe spawn has no desk and ledger")
	if scene.get_node_or_null("FirstPersonHUD/Words") == null:
		ok = _fail("SHAPE", "the scene has no first-person HUD")
	if int(scene.call("body_view_count")) <= 0:
		ok = _fail("SHAPE", "no sim body has a placeholder view")

	var bodies: Array[Node] = []
	_collect_physics(scene, bodies)
	if not bodies.is_empty():
		ok = _fail("SHAPE", "the scene owns a physics body or collision shape: " + str(bodies))
	# True negative for the scanner: it must find a body when one is there.
	var probe: CharacterBody3D = CharacterBody3D.new()
	scene.add_child(probe)
	var found: Array[Node] = []
	_collect_physics(scene, found)
	if found.is_empty():
		ok = _fail("SHAPE", "the physics scan missed a planted CharacterBody3D")
	probe.free()

	if not bool(scene.call("mouse_captured")):
		ok = _fail("SHAPE", "the scene did not capture the mouse at boot")

	# The asset seam is checked as data: the contract is what the art pass will read.
	if not Assets.DESK.ends_with("assets/first_person/desk.glb"):
		ok = _fail("SHAPE", "the desk seam points at the wrong path")
	if not Assets.LEDGER.ends_with("assets/first_person/ledger.glb"):
		ok = _fail("SHAPE", "the ledger seam points at the wrong path")
	if not is_equal_approx(Assets.DESK_HEIGHT_M, 0.78):
		ok = _fail("SHAPE", "the desk height is not the published 0.78 m")
	if not is_equal_approx(Assets.DESK_WIDTH_M, 1.20) or not is_equal_approx(Assets.DESK_DEPTH_M, 0.62):
		ok = _fail("SHAPE", "the desk footprint is not the published 1.20 x 0.62 m")
	if not is_equal_approx(Assets.LEDGER_WIDTH_M, 0.30) or not is_equal_approx(Assets.LEDGER_DEPTH_M, 0.22):
		ok = _fail("SHAPE", "the ledger footprint is not the published 0.30 x 0.22 m")
	if not is_equal_approx(Assets.LEDGER_THICKNESS_M, 0.026):
		ok = _fail("SHAPE", "the ledger thickness is not the published 0.026 m")
	if not is_equal_approx(Assets.SHELF_SIZE.x, 0.90) or not is_equal_approx(Assets.SHELF_SIZE.y, 1.85):
		ok = _fail("SHAPE", "the shelf seam is not the published 0.90 x 1.85 m")
	if not is_equal_approx(Assets.BARRICADE_SIZE.x, 1.20) or not is_equal_approx(Assets.BARRICADE_SIZE.y, 1.10):
		ok = _fail("SHAPE", "the barricade seam is not the published 1.20 x 1.10 m")
	if not is_equal_approx(Assets.WALL_MODULE_SIZE.x, 1.00) or not is_equal_approx(Assets.WALL_MODULE_SIZE.y, 2.60):
		ok = _fail("SHAPE", "the wall seam is not the published 1.00 x 2.60 m")
	# The loader is a seam, not a dependency: each model is used exactly when its file is there.
	var props: Node = scene.get_node_or_null("SafeSpawnProps")
	var desk_model: bool = bool(props.get("used_desk_model")) if props != null else false
	var ledger_model: bool = bool(props.get("used_ledger_model")) if props != null else false
	if desk_model != ResourceLoader.exists(Assets.DESK):
		ok = _fail("SHAPE", "the desk model use does not match what is on disk")
	if ledger_model != ResourceLoader.exists(Assets.LEDGER):
		ok = _fail("SHAPE", "the ledger model use does not match what is on disk")
	return ok


func _collect_physics(node: Node, out: Array[Node]) -> void:
	if node is CollisionObject3D or node is CollisionShape3D or node is CollisionPolygon3D:
		out.append(node)
	for child in node.get_children():
		_collect_physics(child, out)


# --- MAPPING --------------------------------------------------------------------------------

func _mapping(scene: Node) -> bool:
	var ok: bool = true
	var point: Vector2 = Vector2(12.3, 7.8)
	_place_player(scene, point)
	var camera: Camera3D = scene.get("camera") as Camera3D
	if not is_equal_approx(camera.global_position.x, point.x):
		ok = _fail("MAPPING", "sim x is not Godot x (%.3f vs %.3f)" % [point.x, camera.global_position.x])
	if not is_equal_approx(camera.global_position.z, point.y):
		ok = _fail("MAPPING", "sim y is not Godot z (%.3f vs %.3f)" % [point.y, camera.global_position.z])
	if camera.global_position.y < 1.0 or camera.global_position.y > 2.2:
		ok = _fail("MAPPING", "the eye is not at presentation height (%.2f)" % camera.global_position.y)
	# True negative: the axes are not swapped.
	if absf(camera.global_position.x - point.y) < 0.01:
		ok = _fail("MAPPING", "the camera put sim y on Godot x as well")
	# Leave the player somewhere walkable, so the NPC lane does not step a body inside a wall.
	var safe: Vector2 = _find_open_area(scene.get("map"), 2)
	if safe != Vector2(-1.0, -1.0):
		_place_player(scene, safe)
	return ok


# --- NPC ------------------------------------------------------------------------------------

func _npc(scene: Node) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var rows: Array = SimJobs.work_view(world)
	if rows.is_empty():
		return _fail("NPC", "the booted colony has no colonists on the work roster")
	# True negative: a fresh boot has nobody doing a job yet.
	if _jobs_running(world) > 0:
		ok = _fail("NPC", "a colonist already had a job before the gate stepped the sim")
	var before: int = int(world.tick)
	for _i in 20:
		scene.call("step_sim_once")
	var after: int = int(world.tick)
	if after != before + 20:
		ok = _fail("NPC", "twenty steps advanced the tick by %d, not 20" % (after - before))
	if _jobs_running(world) <= 0:
		ok = _fail("NPC", "no colonist took a job after twenty sim ticks")
	var ent: int = int((rows[0] as Dictionary).get("entity", -1))
	var job: Variant = world.components.get_component(ent, "job")
	if not (job is Dictionary) or String((job as Dictionary).get("kind", "")) == "":
		ok = _fail("NPC", "the first colonist has no job after stepping")
	if world.components.has_component(int(world.player), "job"):
		ok = _fail("NPC", "the player is carrying a colonist job")
	if scene.call("body_node_for", world.player) != null:
		ok = _fail("NPC", "the player has a third-person body in first person")
	if scene.call("body_node_for", ent) == null:
		ok = _fail("NPC", "the working colonist has no sim-driven body view")
	# True positive for visibility: aim at bodies until the sim says one is in sight, then require
	# its view to be visible. The screen cannot show a body the sim does not know.
	var visible_ent: int = -1
	for candidate in world.components.query(["position", "body"]):
		var ce: int = int(candidate)
		if ce == int(world.player) or not world.entities.is_alive(ce):
			continue
		var cp: Variant = world.components.get_component(ce, "position")
		if not (cp is Dictionary):
			continue
		var cx: float = float((cp as Dictionary)["x"])
		var cy: float = float((cp as Dictionary)["y"])
		scene.call("look_toward", Vector3(cx, 1.0, cy))
		scene.call("step_sim_once")
		if int(world.vision.call("detail", int(world.player), cx, cy)) > 0:
			visible_ent = ce
			break
	if visible_ent < 0:
		ok = _fail("NPC", "no body came into the sim's sight when the player looked at it")
	else:
		var visible_view: MeshInstance3D = scene.call("body_node_for", visible_ent) as MeshInstance3D
		if visible_view == null or not visible_view.visible:
			ok = _fail("NPC", "a body the sim can see was not drawn")
	if int(scene.call("body_view_visible_count")) <= 0:
		ok = _fail("NPC", "no sim body is visible after the player looked at one")
	# True negative for visibility: a body the sim's own eyes cannot see is not drawn. A lane with
	# no such body says so rather than passing quietly.
	var hidden: int = _first_out_of_sight_body(world)
	if hidden >= 0:
		var hidden_view: MeshInstance3D = scene.call("body_node_for", hidden) as MeshInstance3D
		if hidden_view == null:
			ok = _fail("NPC", "an out-of-sight body had no view to hide")
		elif hidden_view.visible:
			ok = _fail("NPC", "an out-of-sight body was drawn through the world")
	else:
		_skips.append("NPC: no out-of-sight body at this spawn to judge visibility against")
	return ok


func _first_out_of_sight_body(world: Variant) -> int:
	if world.vision == null:
		return -1
	for ent in world.components.query(["position", "body"]):
		var e: int = int(ent)
		if e == int(world.player) or not world.entities.is_alive(e):
			continue
		var pos: Variant = world.components.get_component(e, "position")
		if not (pos is Dictionary):
			continue
		if int(world.vision.call("detail", int(world.player), float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]))) == 0:
			return e
	return -1


func _jobs_running(world: Variant) -> int:
	var count: int = 0
	for row in SimJobs.work_view(world):
		var ent: int = int((row as Dictionary).get("entity", -1))
		var job: Variant = world.components.get_component(ent, "job")
		if job is Dictionary and String((job as Dictionary).get("kind", "")) != "":
			count += 1
	return count


# --- MOVE -----------------------------------------------------------------------------------

func _movement(scene: Node) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var map: Variant = scene.get("map")
	var origin: Vector2 = _find_open_area(map, 2)
	if origin == Vector2(-1.0, -1.0):
		return _fail("MOVE", "the district has no open area for a walk")
	_place_player(scene, origin)
	scene.call("set_look", 0.0, 0.0)
	# The real mouse path, not just the setter: a rightward motion turns the view and the aim.
	var yaw_before: float = float(scene.get("yaw"))
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(40.0, 12.0)
	root.push_input(motion)
	if absf(float(scene.get("yaw")) - yaw_before) < 0.01:
		ok = _fail("MOVE", "a mouse motion did not turn the view")
	if absf(float(scene.get("pitch"))) < 0.001:
		ok = _fail("MOVE", "a downward mouse motion did not pitch the view")
	scene.call("set_look", 0.0, 0.0)
	world.commands.record = true
	world.commands.recorded.clear()
	var tick_before: int = int(world.tick)
	_key(KEY_W, true)
	scene.call("_process", TICK_SECONDS)
	scene.call("_process", TICK_SECONDS)
	var walked: Vector2 = _player_pos(world)
	if walked.distance_to(origin) < 0.15:
		ok = _fail("MOVE", "W did not walk the sim's body")
	var move_cmd: Dictionary = _last_command(world, "move", tick_before)
	if move_cmd.is_empty():
		ok = _fail("MOVE", "no move command reached the sim")
	else:
		if absf(float(move_cmd.get("dx", 9.0))) > 0.02:
			ok = _fail("MOVE", "yaw zero sent a sideways dx of %.3f" % float(move_cmd.get("dx", 9.0)))
		if absf(float(move_cmd.get("dy", 9.0)) + 1.0) > 0.02:
			ok = _fail("MOVE", "yaw zero did not send dy -1 (%.3f)" % float(move_cmd.get("dy", 9.0)))
	var aim_cmd: Dictionary = _last_command(world, "aim", tick_before)
	if aim_cmd.is_empty():
		ok = _fail("MOVE", "no aim command followed the yaw")
	elif absf(angle_difference(float(aim_cmd.get("radians", 99.0)), -PI / 2.0)) > 0.02:
		ok = _fail("MOVE", "the aim did not carry the camera's north bearing (%.3f)" % float(aim_cmd.get("radians", 99.0)))

	var camera: Camera3D = scene.get("camera") as Camera3D
	var rendered: Vector2 = scene.call("rendered_player_position")
	if not is_equal_approx(camera.global_position.x, rendered.x) or not is_equal_approx(camera.global_position.z, rendered.y):
		ok = _fail("MOVE", "the camera is not on the interpolated sim position")
	# True positive for interpolation: half a tick must be between the two tick states, not on
	# either of them.
	var at_tick: Vector2 = rendered
	scene.call("_process", TICK_SECONDS * 0.5)
	var midway: Vector2 = scene.call("rendered_player_position")
	if midway.is_equal_approx(at_tick):
		ok = _fail("MOVE", "the camera jumped rather than interpolating between ticks")
	if not is_equal_approx(camera.global_position.x, midway.x) or not is_equal_approx(camera.global_position.z, midway.y):
		ok = _fail("MOVE", "the camera left the interpolated point")

	_key(KEY_W, false)
	scene.call("_process", TICK_SECONDS)
	var stopped: Vector2 = _player_pos(world)
	scene.call("_process", TICK_SECONDS)
	if not _player_pos(world).is_equal_approx(stopped):
		ok = _fail("MOVE", "the body kept walking after W was released")
	return ok


# --- YAW ------------------------------------------------------------------------------------

func _yaw(scene: Node) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var map: Variant = scene.get("map")
	var area: Vector2 = _find_open_area(map, 2)
	if area == Vector2(-1.0, -1.0):
		return _fail("YAW", "the district has no open area for a turn")

	_place_player(scene, area)
	scene.call("set_look", 0.0, 0.0)
	world.commands.recorded.clear()
	var tick_before: int = int(world.tick)
	_key(KEY_W, true)
	scene.call("_process", TICK_SECONDS)
	var north: Dictionary = _last_command(world, "move", tick_before)
	# Held W and a camera turn must send the new direction immediately, not wait for the next key.
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(655.0, 0.0)
	root.push_input(motion)
	scene.call("_process", TICK_SECONDS)
	var turned: Dictionary = _last_command(world, "move", tick_before)
	var turned_aim: Dictionary = _last_command(world, "aim", tick_before)
	_key(KEY_W, false)
	scene.call("_process", TICK_SECONDS)
	if north.is_empty() or absf(float(north.get("dx", 9.0))) > 0.02 or absf(float(north.get("dy", 9.0)) + 1.0) > 0.02:
		ok = _fail("YAW", "yaw zero did not walk toward sim north")
	if turned.is_empty():
		ok = _fail("YAW", "a turn while W was held sent no new move")
	elif absf(float(turned.get("dx", 9.0)) - 1.0) > 0.02 or absf(float(turned.get("dy", 9.0))) > 0.02:
		ok = _fail("YAW", "a turn while W was held kept the old direction (dx %.3f dy %.3f)" % [float(turned.get("dx", 9.0)), float(turned.get("dy", 9.0))])
	if turned_aim.is_empty() or absf(angle_difference(float(turned_aim.get("radians", 99.0)), 0.0)) > 0.02:
		ok = _fail("YAW", "a turn while W was held did not send the new aim")

	_place_player(scene, area)
	scene.call("set_look", -PI / 2.0, 0.0)
	world.commands.recorded.clear()
	tick_before = int(world.tick)
	_key(KEY_W, true)
	scene.call("_process", TICK_SECONDS)
	var east: Dictionary = _last_command(world, "move", tick_before)
	var aim: Dictionary = _last_command(world, "aim", tick_before)
	_key(KEY_W, false)
	scene.call("_process", TICK_SECONDS)
	if east.is_empty():
		ok = _fail("YAW", "a quarter turn sent no move")
	else:
		if absf(float(east.get("dx", 9.0)) - 1.0) > 0.02:
			ok = _fail("YAW", "a quarter turn did not walk toward sim east (dx %.3f)" % float(east.get("dx", 9.0)))
		if absf(float(east.get("dy", 9.0))) > 0.02:
			ok = _fail("YAW", "a quarter turn still walked north/south (dy %.3f)" % float(east.get("dy", 9.0)))
	if aim.is_empty():
		ok = _fail("YAW", "a quarter turn sent no aim")
	elif absf(angle_difference(float(aim.get("radians", 99.0)), 0.0)) > 0.02:
		ok = _fail("YAW", "the aim did not follow the quarter turn (%.3f)" % float(aim.get("radians", 99.0)))
	return ok


# --- BLOCK ----------------------------------------------------------------------------------

func _blocked(scene: Node) -> bool:
	var world: Variant = scene.get("world")
	var map: Variant = scene.get("map")
	var setup: Dictionary = _find_blocked_setup(map)
	if setup.is_empty():
		return _fail("BLOCK", "the district has no floor tile next to a wall with room on the other side")
	var tile: Vector2i = setup["tile"] as Vector2i
	var direction: Vector2i = setup["dir"] as Vector2i
	var centre: Vector2 = Vector2(float(tile.x) + 0.5, float(tile.y) + 0.5)
	var ok: bool = true

	_place_player(scene, centre)
	scene.call("set_look", atan2(-float(direction.x), -float(direction.y)), 0.0)
	_key(KEY_W, true)
	for _i in 6:
		scene.call("_process", TICK_SECONDS)
	_key(KEY_W, false)
	scene.call("_process", TICK_SECONDS)
	var into_wall: Vector2 = _player_pos(world)
	if into_wall.distance_to(centre) > 0.30:
		ok = _fail("BLOCK", "the body passed into the wall by %.3f m" % into_wall.distance_to(centre))
	if floori(into_wall.x) != tile.x or floori(into_wall.y) != tile.y:
		ok = _fail("BLOCK", "the body left its tile against the wall")

	_place_player(scene, centre)
	scene.call("set_look", atan2(float(direction.x), float(direction.y)), 0.0)
	_key(KEY_W, true)
	for _i in 6:
		scene.call("_process", TICK_SECONDS)
	_key(KEY_W, false)
	scene.call("_process", TICK_SECONDS)
	var away: Vector2 = _player_pos(world)
	if away.distance_to(centre) < 0.30:
		ok = _fail("BLOCK", "the open direction did not move the body (%.3f m)" % away.distance_to(centre))
	return ok


# --- LEDGER ---------------------------------------------------------------------------------

func _ledger(scene: Node, spawn: Vector2) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var map: Variant = scene.get("map")
	var ledger: Vector2 = scene.call("ledger_sim_position")
	var approach: Vector2 = scene.call("ledger_approach_position")
	if ledger.distance_to(spawn) > 8.0:
		ok = _fail("LEDGER", "the ledger is not near the safe spawn (%.1f m)" % ledger.distance_to(spawn))
	if ledger.distance_to(approach) < 0.5:
		ok = _fail("LEDGER", "the ledger has no separate standing spot")

	# J is not a global way into the work panel.
	_key(KEY_J, true)
	_key(KEY_J, false)
	if bool(scene.get("menu_open")):
		ok = _fail("LEDGER", "J opened the work panel without the ledger")
	if scene.call("work_panel_node") != null and bool((scene.call("work_panel_node") as Control).visible):
		ok = _fail("LEDGER", "a work panel was visible before the ledger was used")

	# Far away: refused, with words on screen.
	_place_player(scene, ledger + Vector2(6.0, 0.0))
	scene.call("look_toward", Vector3(ledger.x, 0.90, ledger.y))
	if String(scene.call("interaction_verdict")) != "far":
		ok = _fail("LEDGER", "a ledger six metres away did not read as far")
	_key(KEY_E, true)
	_key(KEY_E, false)
	if bool(scene.get("menu_open")):
		ok = _fail("LEDGER", "E opened the ledger from six metres away")
	if String(scene.get("_alert")) == "":
		ok = _fail("LEDGER", "the refused far interaction said nothing")

	# Within reach but through an opaque wall: the sim's own sight decides, so aim alone is not
	# enough. The desk is sited against a sight-blocking wall for exactly this case.
	var wall_dir: Vector2i = _find_through_wall(map, ledger)
	if wall_dir == Vector2i(-1, -1):
		ok = _fail("LEDGER", "the ledger has no opaque wall with open floor beyond it")
	else:
		var wall: Vector2i = Vector2i(floori(ledger.x), floori(ledger.y)) + wall_dir
		var behind: Vector2 = Vector2(float(wall.x) + 0.5 + float(wall_dir.x) * 0.62, float(wall.y) + 0.5 + float(wall_dir.y) * 0.62)
		_place_player(scene, behind)
		scene.call("look_toward", Vector3(ledger.x, 0.90, ledger.y))
		_settle_vision(scene)
		if ledger.distance_to(behind) > 1.80:
			ok = _fail("LEDGER", "the through-wall point is outside reach (%.2f m)" % ledger.distance_to(behind))
		if String(scene.call("interaction_verdict")) != "blocked":
			ok = _fail("LEDGER", "a ledger through a wall did not read as blocked")
		_key(KEY_E, true)
		_key(KEY_E, false)
		if bool(scene.get("menu_open")):
			ok = _fail("LEDGER", "E opened the ledger through a wall")
		if String(scene.get("_alert")) == "":
			ok = _fail("LEDGER", "the refused through-wall interaction said nothing")

	# In reach but looking away: refused, with words on screen.
	_place_player(scene, approach)
	scene.call("look_toward", Vector3(ledger.x, 0.90, ledger.y))
	scene.call("set_look", float(scene.get("yaw")) + PI, 0.0)
	_settle_vision(scene)
	if String(scene.call("interaction_verdict")) != "away":
		ok = _fail("LEDGER", "looking the other way in reach still read as usable")
	_key(KEY_E, true)
	_key(KEY_E, false)
	if bool(scene.get("menu_open")):
		ok = _fail("LEDGER", "E opened the ledger while looking away from it")
	if String(scene.get("_alert")) == "":
		ok = _fail("LEDGER", "the refused off-aim interaction said nothing")

	# In reach and looking at it: the real work panel opens.
	scene.call("look_toward", Vector3(ledger.x, 0.90, ledger.y))
	_settle_vision(scene)
	if String(scene.call("interaction_verdict")) != "ok":
		ok = _fail("LEDGER", "the ledger in reach and in aim did not read as usable")
	_key(KEY_E, true)
	_key(KEY_E, false)
	if not bool(scene.get("menu_open")):
		ok = _fail("LEDGER", "E at the ledger did not open the menu")
	var panel: Control = scene.call("work_panel_node") as Control
	if panel == null or not panel.visible:
		ok = _fail("LEDGER", "the work panel was not visible after E")
	else:
		if panel.get_script() != WorkPanel:
			ok = _fail("LEDGER", "the ledger opened something other than the real work panel")
		if panel.get("_world") == null:
			ok = _fail("LEDGER", "the work panel opened without the sim world")
	if bool(scene.call("mouse_captured")):
		ok = _fail("LEDGER", "the mouse stayed captured with the menu open")
	return ok


# --- PRIORITY -------------------------------------------------------------------------------

func _priority(scene: Node) -> bool:
	if not bool(scene.get("menu_open")):
		return _fail("PRIORITY", "the work panel was not open for the priority click")
	var ok: bool = true
	var world: Variant = scene.get("world")
	var rows: Array = SimJobs.work_view(world)
	if rows.is_empty():
		return _fail("PRIORITY", "the work panel has no colonist rows")
	for row in rows:
		if int((row as Dictionary).get("entity", -1)) == int(world.player):
			ok = _fail("PRIORITY", "the player is drawn as a colonist row")

	var panel: Control = scene.call("work_panel_node") as Control
	var laid: Dictionary = panel.call("_layout")
	var drawn_rows: Array = laid.get("rows", []) as Array
	if drawn_rows.is_empty():
		return _fail("PRIORITY", "the work panel drew no rows to click")
	var row: Dictionary = drawn_rows[0] as Dictionary
	var ent: int = int(row.get("entity", -1))
	var cells: Array = []
	# The panel's row selection must survive the per-frame `set_world` refresh: click the name,
	# step a frame, and still have that colonist selected before editing their grid.
	var name_at: Vector2 = row.get("name_at", Vector2(-1.0, -1.0)) as Vector2
	if name_at.x < 0.0:
		return _fail("PRIORITY", "the first drawn row has no name to select")
	var picked: String = panel.call("_click", name_at, false)
	if picked != "row":
		ok = _fail("PRIORITY", "a click on a colonist's name did not pick the row (%s)" % picked)
	if int(panel.call("selected")) != ent:
		ok = _fail("PRIORITY", "the clicked colonist was not the panel's pick")
	scene.call("_process", TICK_SECONDS)
	if int(panel.call("selected")) != ent:
		ok = _fail("PRIORITY", "the per-frame refresh reset the panel's pick")
	laid = panel.call("_layout")
	drawn_rows = laid.get("rows", []) as Array
	if drawn_rows.is_empty():
		return _fail("PRIORITY", "the work panel drew no rows after the pick")
	row = drawn_rows[0] as Dictionary
	cells = row.get("cells", []) as Array
	if cells.is_empty():
		return _fail("PRIORITY", "the first drawn row has no priority cells")
	var cell: Dictionary = cells[0] as Dictionary
	var column: String = String(cell.get("column", ""))
	var rect: Rect2 = cell.get("rect", Rect2()) as Rect2
	var jp: Variant = world.components.get_component(ent, "jobPriorities")
	if not (jp is Dictionary):
		return _fail("PRIORITY", "the first colonist has no job priorities")
	var cols: Dictionary = (jp as Dictionary).get("cols", {}) as Dictionary
	var before: int = int(cols.get(column, 0))

	world.commands.record = true
	world.commands.recorded.clear()
	var tick_before: int = int(world.tick)
	var did: String = panel.call("_click", rect.get_center(), false)
	if did != "cell":
		ok = _fail("PRIORITY", "the priority cell click did nothing (%s)" % did)
	scene.call("step_sim_once")
	var after: int = int(cols.get(column, 0))
	var expected: int = 0 if before >= 4 else before + 1
	if after != expected:
		ok = _fail("PRIORITY", "%s priority stayed %d, expected %d" % [column, after, expected])
	if String((jp as Dictionary).get("focus", "")) != "Manual":
		ok = _fail("PRIORITY", "editing a priority did not turn the row Manual")
	if String((jp as Dictionary).get("focusSetBy", "")) != "player":
		ok = _fail("PRIORITY", "editing a priority did not stamp the player as its source")
	var cmd: Dictionary = _last_command(world, "job.priority", tick_before)
	if cmd.is_empty():
		ok = _fail("PRIORITY", "the panel click dispatched no job.priority command")
	else:
		if int(cmd.get("entity", -1)) != ent:
			ok = _fail("PRIORITY", "the priority command named the wrong colonist")
		if String(cmd.get("column", "")) != column:
			ok = _fail("PRIORITY", "the priority command named the wrong column")

	# The panel's "their skills" button is a real signal, and this foundation answers it visibly
	# rather than letting a press vanish. No skill web is claimed to exist.
	var note: Label = scene.get("_ledger_note") as Label
	if note == null:
		ok = _fail("PRIORITY", "the ledger built no note for its out-of-scope button")
	elif note.visible:
		ok = _fail("PRIORITY", "the ledger note was visible before anything asked for it")
	panel.emit_signal("navigate", "skills")
	if note == null or not note.visible or note.text == "":
		ok = _fail("PRIORITY", "the panel's skills button did not answer")
	return ok


# --- MENU -----------------------------------------------------------------------------------

func _menu(scene: Node) -> bool:
	if not bool(scene.get("menu_open")):
		return _fail("MENU", "the menu was not open for the capture lane")
	var ok: bool = true
	var world: Variant = scene.get("world")
	var map: Variant = scene.get("map")
	var before: Vector2 = _player_pos(world)
	_key(KEY_W, true)
	scene.call("_process", TICK_SECONDS)
	scene.call("_process", TICK_SECONDS)
	_key(KEY_W, false)
	if not _player_pos(world).is_equal_approx(before):
		ok = _fail("MENU", "a walking key moved the body behind the open ledger")
	_key(KEY_J, true)
	_key(KEY_J, false)
	if not bool(scene.get("menu_open")):
		ok = _fail("MENU", "J closed or switched the ledger menu")

	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	if bool(scene.get("menu_open")):
		ok = _fail("MENU", "Escape did not close the ledger menu")
	var panel: Control = scene.call("work_panel_node") as Control
	if panel != null and panel.visible:
		ok = _fail("MENU", "the work panel stayed visible after Escape")
	if not bool(scene.call("mouse_captured")):
		ok = _fail("MENU", "Escape did not give the mouse back")
	var held: Variant = scene.get("_held")
	if held is Dictionary and not (held as Dictionary).is_empty():
		ok = _fail("MENU", "Escape left a movement key held")

	# Alt-tab: a held key must not survive the focus loss, and the queued move must be zero.
	_key(KEY_W, true)
	scene.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var lost: Variant = scene.get("_held")
	if lost is Dictionary and not (lost as Dictionary).is_empty():
		ok = _fail("MENU", "focus loss left a movement key held")
	world.commands.record = true
	world.commands.recorded.clear()
	var loss_tick: int = int(world.tick)
	scene.call("_process", TICK_SECONDS)
	var zero: Dictionary = _last_command(world, "move", loss_tick)
	if zero.is_empty() or absf(float(zero.get("dx", 9.0))) > 0.0001 or absf(float(zero.get("dy", 9.0))) > 0.0001:
		ok = _fail("MENU", "focus loss did not queue a zero move")
	_key(KEY_W, false)

	var area: Vector2 = _find_open_area(map, 2)
	_place_player(scene, area)
	scene.call("set_look", 0.0, 0.0)
	_key(KEY_W, true)
	scene.call("_process", TICK_SECONDS)
	scene.call("_process", TICK_SECONDS)
	_key(KEY_W, false)
	scene.call("_process", TICK_SECONDS)
	if _player_pos(world).distance_to(area) < 0.15:
		ok = _fail("MENU", "walking did not come back after Escape")
	return ok


# --- SPEECH ---------------------------------------------------------------------------------

func _speech(scene: Node) -> bool:
	var ok: bool = true
	var raw: Variant = scene.call("hud_lines")
	if not (raw is Array):
		return _fail("SPEECH", "the HUD returned no lines")
	var lines: Array = raw as Array
	if lines.is_empty():
		return _fail("SPEECH", "the HUD drew no lines")
	var joined: String = ""
	for line in lines:
		var text: String = String(line)
		joined += text + "\n"
		if _has_digit(text):
			ok = _fail("SPEECH", "the HUD drew a digit: %s" % text)
	if not joined.contains("WASD"):
		ok = _fail("SPEECH", "the HUD does not name the walking keys")
	if not joined.contains("ledger"):
		ok = _fail("SPEECH", "the HUD does not name the ledger")
	var bars: Array[Node] = []
	_collect_bars(scene, bars)
	if not bars.is_empty():
		ok = _fail("SPEECH", "the first-person screen owns a progress bar: " + str(bars))
	# True negative for the digit scanner.
	if not _has_digit("health 100"):
		ok = _fail("SPEECH", "the digit scanner missed a fabricated number")
	return ok


func _collect_bars(node: Node, out: Array[Node]) -> void:
	if node is ProgressBar or node is TextureProgressBar:
		out.append(node)
	for child in node.get_children():
		_collect_bars(child, out)


func _has_digit(text: String) -> bool:
	for i in text.length():
		if text[i].is_valid_int():
			return true
	return false


# --- fixtures -------------------------------------------------------------------------------

func _key(code: Key, pressed: bool) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	root.push_input(ev)


## Test setup, kept in the gate so the presentation never writes a sim component. The scene is
## told only to re-read the position afterwards (`snap_render_to_sim` is read-only).
func _place_player(scene: Node, point: Vector2) -> void:
	var world: Variant = scene.get("world")
	if world == null:
		return
	world.components.set_component(int(world.player), "position", {"x": point.x, "y": point.y})
	var velocity: Variant = world.components.get_component(int(world.player), "velocity")
	if velocity is Dictionary:
		(velocity as Dictionary)["dx"] = 0.0
		(velocity as Dictionary)["dy"] = 0.0
	scene.call("snap_render_to_sim")


## The player's shadowcast is deliberately staggered over a few ticks (`STAGGER_PLAYER_CAST`), so
## a teleport in the gate needs the same few ticks a walk would take before the sim's sight agrees
## with the new position. Six covers the four quadrants and the tick that queues them.
func _settle_vision(scene: Node, ticks: int = 6) -> void:
	for _i in ticks:
		scene.call("step_sim_once")


func _player_pos(world: Variant) -> Vector2:
	var pos: Variant = world.components.get_component(int(world.player), "position")
	if not (pos is Dictionary):
		return Vector2.ZERO
	return Vector2(float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]))


func _entity_pos(world: Variant, entity: int) -> Vector2:
	var pos: Variant = world.components.get_component(entity, "position")
	if not (pos is Dictionary):
		return Vector2.ZERO
	return Vector2(float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]))


func _last_command(world: Variant, type: String, after_tick: int) -> Dictionary:
	var recorded: Array = world.commands.recorded as Array
	for i in range(recorded.size() - 1, -1, -1):
		var rec: Dictionary = recorded[i] as Dictionary
		if int(rec.get("tick", -1)) <= after_tick:
			continue
		var command: Dictionary = rec.get("command", {}) as Dictionary
		if String(command.get("type", "")) == type:
			return command
	return {}


func _find_open_area(map: Variant, radius: int) -> Vector2:
	for ty in range(radius + 1, int(map.h) - radius - 1):
		for tx in range(radius + 1, int(map.w) - radius - 1):
			var clear: bool = true
			for dy in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					if not _walkable_floor(map, tx + dx, ty + dy):
						clear = false
						break
				if not clear:
					break
			if clear:
				return Vector2(float(tx) + 0.5, float(ty) + 0.5)
	return Vector2(-1.0, -1.0)


func _find_blocked_setup(map: Variant) -> Dictionary:
	var directions: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	for ty in range(2, int(map.h) - 2):
		for tx in range(2, int(map.w) - 2):
			if not _walkable_floor(map, tx, ty):
				continue
			for direction in directions:
				var wall: Vector2i = Vector2i(tx, ty) + direction
				var open: Vector2i = Vector2i(tx, ty) - direction
				if not SimTileMap.is_solid(map, wall.x, wall.y):
					continue
				if not _walkable_floor(map, open.x, open.y):
					continue
				return {"tile": Vector2i(tx, ty), "dir": direction}
	return {}


func _find_through_wall(map: Variant, point: Vector2) -> Vector2i:
	var tile: Vector2i = Vector2i(floori(point.x), floori(point.y))
	var directions: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	for direction in directions:
		var wall: Vector2i = tile + direction
		if not SimTileMap.is_solid(map, wall.x, wall.y):
			continue
		if not SimTileMap.blocks_sight(map, wall.x, wall.y):
			continue
		if _walkable_floor(map, wall.x + direction.x, wall.y + direction.y):
			return direction
	return Vector2i(-1, -1)


func _walkable_floor(map: Variant, tx: int, ty: int) -> bool:
	if tx <= 0 or ty <= 0 or tx >= int(map.w) - 1 or ty >= int(map.h) - 1:
		return false
	if SimTileMap.is_solid(map, tx, ty):
		return false
	if SimTileMap.tile_at(map, tx, ty) != SimTileMap.Tile.Floor:
		return false
	var index: int = ty * int(map.w) + tx
	return int(map.surfaces[index]) != SimTileMap.SURFACE_WATER
