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
#   CONTAINER every sim container has a labelled placeholder at its sim position; E in reach and
#             in aim sends the top-down `container.open` command and opens the real grid inventory
#             sheet with the box beside the player's own bags; a take moves one real item into the
#             player's inventory through `item.move`, and the box-plus-player total is unchanged.
#             E out of reach, off the aim and through an opaque wall is refused with words, and a
#             walking key does not move the body behind the open sheet. Escape closes it and gives
#             the mouse back.
#   FIGHT     the top-down buttons' own commands: left click/F swing, G fire, R reload; a bat hits
#             a shambler in front and its body changes, a loaded gun spends a round, the HUD gets a
#             camera kick and no reticle or centre dot, the placeholder weapon shows only with
#             something in hand, the ledger refuses the same press, a look away misses, and a
#             reload with nothing to load is the sim's refusal with no words from the scene.
#   PRIORITY  a click on the panel's first priority cell dispatches a real `job.priority`, the
#             colonist's row changes and turns Manual, and the player is never one of the rows.
#   SPEECH    every line the first-person HUD draws is digit-free, it names the controls and the
#             ledger, there is no progress bar in the tree, and the digit scanner is proved against
#             a fabricated line.
#   VERBS     E on a door in reach and aimed at, through the sim's own door verb, opens and shuts it; E
#             out of reach or looking away changes nothing; a plain wall offers no prompt.
#   STANCE    the top-down stance keys change the sim's posture, the camera's eye eases to SimSpace's
#             eye for it, and the ledger refuses the keys.
#   REPORTS   the ledger's Reports page shows the chronicle's own lines, marks the new ones, moves the
#             read mark and returns through Escape; no row is an invented line or a digit.
#   LIGHT     noon is bright and midnight is dark by named thresholds, rain darkens the grade and
#             fog turns the depth fog on from the sim's own sight multiplier, an equipped and lit
#             torch becomes the eye's spot at the sim's range and cone, the sim burning it out turns
#             it off, and a body behind a wall is not drawn inside the torch's cone.
#   SUCCESSION a killing of somebody who is not the player moves nothing; killing the player with
#             an heir alive hands the camera to the heir on the next frame with no glide, says the
#             chronicle's succession sentence on the HUD, walks the heir, and draws the dead body
#             when the heir can see it.
#   RUN-OVER  killing every colony body opens the end panel in the chronicle's words, releases the
#             mouse, and W proposes no move or aim.
#   DISTRICT  a fresh scene boots the shipped district size and seed (true positive), and the
#             gate's small override really boots a smaller district, the one every lane above
#             walks (true negative). Only a fresh, unparented instance is read for the default: no
#             sim world is built for it.
#   SAVE      F5 writes the sim's save into the first-person slot and F9 restores it: the body, the
#             camera and the tick go back to the saved values after the walk on. F9 with no save
#             says so and changes nothing; F5 with the ledger open writes nothing. The lane swaps in
#             its own slot key and deletes it afterwards, so no real save is touched.
#   ART       the desk and ledger load from their GLBs with no import cache and are drawn at the
#             published sizes on the floor and the desk top, with nearest-filtered materials; the
#             prop preview stands every prop on its authored base. Missing art skips to the boxes,
#             and a planted wrong-size GLB and a raised prop are refused by the same tests.
#   ANIM      the animation read model names the pose from sim facts: standing, a walk, a run, a
#             crouch, a crouch walk, a crawl, a swing (wind-up and recover), a shambler's armed swipe
#             as a lunge, a hold as a grab, a stagger, and a corpse as death. A body that stops is
#             idle on the next tick; a corpse stays death after many ticks; a living body is never
#             death. Every phase is 0..1.
#   TALK      E on one of your colonists in reach and on the aim opens the conversation panel with
#             the sim's name, the read models' own feel and doing lines; every line is digit-free;
#             walking is swallowed while it is up and Escape closes it and recaptures the mouse. Out
#             of reach, off the aim, through a wall, at a zombie and at a raider: no panel.

const SCENE_PATH: String = "res://presentation/first_person/first_person.tscn"
const WorkPanel = preload("res://ui/work_panel.gd")
const InventoryPanel = preload("res://ui/inventory_panel.gd")
const AnimState = preload("res://presentation/first_person/anim_state.gd")
const TalkPanel = preload("res://ui/talk_panel.gd")
const WorkRead = preload("res://sim/work_read.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimCondition = preload("res://sim/condition.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimContainers = preload("res://sim/modules/containers.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimAllegiance = preload("res://sim/modules/allegiance.gd")
const SimRecruits = preload("res://sim/modules/recruits.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimLightMod = preload("res://sim/modules/light.gd")
const SimWeather = preload("res://sim/modules/weather.gd")
const Clock = preload("res://sim/time/clock.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const SimStances = preload("res://sim/stances.gd")
const SimSpace = preload("res://sim/space/space.gd")
const SimChronicle = preload("res://sim/modules/chronicle.gd")
const ReportsPanel = preload("res://ui/reports_panel.gd")
const SimBoot = preload("res://sim/boot.gd")
const FirstPerson = preload("res://presentation/first_person/first_person.gd")
const Assets = preload("res://presentation/first_person/assets.gd")
const SaveSlot = preload("res://presentation/first_person/save_slot.gd")

# The district the gate boots. Small on purpose: every lane walks the sim, and the shipped 256 district
# is for the player, not for a gate. DISTRICT proves this is really smaller than the shipped default.
const SMALL_DISTRICT_TILES: int = 64
# The LIGHT lane's named thresholds. The sun and ambient must be well up at noon and well down at
# midnight; these are the numbers the presentation constants are judged against.
const LIGHT_NOON_SUN_MIN: float = 0.5
const LIGHT_NOON_AMBIENT_MIN: float = 0.5
const LIGHT_NIGHT_SUN_MAX: float = 0.05
const LIGHT_NIGHT_AMBIENT_MAX: float = 0.15
# SAVE writes and reads its own slot under this key and deletes it afterwards. It must never be the
# real first-person slot, which is what the SAVE lane asserts before it touches anything.
const GATE_SAVE_KEY: String = "first_person_save_gate.slot"
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
	var ok: bool = _district_default(packed)
	var scene: Node = packed.instantiate()
	scene.set("district_tiles", SMALL_DISTRICT_TILES)
	root.add_child(scene)
	scene.set_process(false)
	await process_frame

	ok = _scene_shape(scene) and ok
	if ok:
		ok = _district(scene) and ok
		var spawn: Vector2 = scene.call("rendered_player_position")
		ok = _npc(scene) and ok
		ok = _mapping(scene) and ok
		ok = _movement(scene) and ok
		ok = _yaw(scene) and ok
		ok = _blocked(scene) and ok
		ok = _container(scene) and ok
		ok = _fight(scene) and ok
		ok = _ledger(scene, spawn) and ok
		ok = _priority(scene) and ok
		ok = _menu(scene) and ok
		ok = _speech(scene) and ok
		ok = _verbs(scene) and ok
		ok = _stance(scene) and ok
		ok = _reports(scene) and ok
		# Save before the lanes that kill the colony: the run-over lane leaves input swallowed.
		ok = _save(scene) and ok
		ok = _art(scene) and ok
		ok = _preview() and ok
		ok = _light(scene) and ok
		ok = _succession(scene) and ok
		ok = _talk(scene) and ok
		ok = _anim(scene) and ok
		ok = _run_over(scene) and ok
	scene.queue_free()
	await process_frame
	_finish(old_size, ok)


func _finish(old_size: Vector2i, ok: bool = false) -> void:
	root.size = old_size
	if ok:
		for skip in _skips:
			print("FIRST_PERSON_SKIP " + skip)
		print("FIRST_PERSON_OK the opt-in scene boots the shipped district size and seed by default and the real sim (the gate walks a smaller one), maps sim x/y to Godot x/z, walks only through sim commands and sim collision, interpolates the camera, draws the district's sim containers as labelled placeholders and opens one in reach through the top-down container.open command into the real grid inventory sheet, moves a real item into the player's inventory without duplication, holds the body still under the open sheet, refuses E out of reach, off the aim and through a wall for the ledger and for containers, swings a bat into a shambler and fires a round through the top-down commands while the ledger refuses both, misses a body behind the look, and leaves a refused reload wordless, opens and shuts a door through the sim's own verb from the tile the eye is on while a door out of reach or looked away from sends nothing, takes the top-down stance keys and eases the eye to the sim's posture height while the ledger refuses the keys, reads the chronicle's own lines on the ledger's Reports page and moves the read mark, lights noon by the sim's clock and darkens midnight, turns a carried torch into the eye's spot at the sim's range and cone and out when it burns, and keeps a body behind a wall undrawn, opens the real work panel and the read-only skill web in reach, releases and resumes the mouse on Escape and click, dispatches a priority that changes a colonist's row, closes cleanly, steps NPC jobs, saves and loads through the sim's own save in its own slot, loads the desk and ledger from their GLBs at the published sizes with nearest-filtered materials and stands every preview prop on its base, names every body's animation state from the sim (stand, walk, run, crouch, crawl, swing, lunge, grab, stagger, death) with a phase in 0..1 while a corpse stays dead and a living body never does, talks to a colonist in reach and on the aim in the read models' own words while a walk is swallowed and Escape gives the mouse back, and refuses a colonist out of reach, off the aim, through a wall, a shambler and a raider, draws a digit-free prose HUD, and cuts the camera to an heir with the chronicle's succession words while drawing the dead body, then shows a digit-free end panel that ignores W when the last colony body dies")
		quit(0)
		return
	for failure in _failures:
		push_error("FIRST_PERSON_FAIL " + failure)
	quit(1)


func _fail(lane: String, message: String) -> bool:
	_failures.append(lane + ": " + message)
	return false


# --- DISTRICT -------------------------------------------------------------------------------

# True positive: the scene's default boot is the shipped district size and seed, the ones
# `session.gd` and `main.gd` boot. The fresh instance is freed unparented, so no sim world is built.
func _district_default(packed: PackedScene) -> bool:
	var fresh: Node = packed.instantiate()
	var default_tiles: int = int(fresh.get("district_tiles"))
	fresh.free()
	var ok: bool = true
	if default_tiles != SimTileMap.DISTRICT_TILES:
		ok = _fail("DISTRICT", "a fresh scene boots %d tiles, not the shipped %d" % [default_tiles, SimTileMap.DISTRICT_TILES])
	if FirstPerson.SEED != SimBoot.DISTRICT_SEED:
		ok = _fail("DISTRICT", "the scene seed %d is not the shipped district seed %d" % [FirstPerson.SEED, SimBoot.DISTRICT_SEED])
	return ok


# True negative: the override this gate sets really boots a smaller district than the shipped one,
# and the map every other lane walks is that smaller one.
func _district(scene: Node) -> bool:
	var map: Variant = scene.get("map")
	if map == null:
		return _fail("DISTRICT", "the small-district scene kept no map")
	var booted: int = int(map.w)
	var ok: bool = true
	if int(scene.get("district_tiles")) != SMALL_DISTRICT_TILES or booted != SMALL_DISTRICT_TILES:
		ok = _fail("DISTRICT", "the gate's override booted %d tiles, not %d" % [booted, SMALL_DISTRICT_TILES])
	if SMALL_DISTRICT_TILES >= SimTileMap.DISTRICT_TILES or booted >= SimTileMap.DISTRICT_TILES:
		ok = _fail("DISTRICT", "the gate's district (%d) is not smaller than the shipped %d" % [booted, SimTileMap.DISTRICT_TILES])
	return ok


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
	if desk_model != FileAccess.file_exists(Assets.DESK):
		ok = _fail("SHAPE", "the desk model use does not match what is on disk")
	if ledger_model != FileAccess.file_exists(Assets.LEDGER):
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


# --- CONTAINER ------------------------------------------------------------------------------

## The district's sim cupboards are drawn, opened through the top-down command, scavenged through
## the real sheet, and refused by the same three rules the ledger uses.
func _container(scene: Node) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var listed: Array = world.components.query(["searchable", "position"])
	if listed.is_empty():
		return _fail("CONTAINER", "the booted district stands no sim containers")
	if int(scene.call("container_view_count")) != listed.size():
		ok = _fail("CONTAINER", "the scene drew %d placeholders for %d sim containers" % [int(scene.call("container_view_count")), listed.size()])

	# Every sim container is a labelled box at its own sim position.
	for entity in listed:
		var ent: int = int(entity)
		var node: Node3D = scene.call("container_node_for", ent) as Node3D
		if node == null:
			ok = _fail("CONTAINER", "sim container %d has no placeholder" % ent)
			continue
		var at: Vector2 = scene.call("container_sim_position", ent)
		if not is_equal_approx(node.position.x, at.x) or not is_equal_approx(node.position.z, at.y):
			ok = _fail("CONTAINER", "container %d is drawn at (%.2f, %.2f), not its sim position (%.2f, %.2f)" % [ent, node.position.x, node.position.z, at.x, at.y])
		var state: Variant = world.components.get_component(ent, "searchable")
		var kind: String = String((state as Dictionary).get("kind", "")) if state is Dictionary else ""
		if String(scene.call("container_label_for", ent)) != kind:
			ok = _fail("CONTAINER", "container %d is labelled \"%s\", not \"%s\"" % [ent, String(scene.call("container_label_for", ent)), kind])

	# A real box, in reach, with the eye on it.
	var spot: Dictionary = _find_container_approach(scene)
	if spot.is_empty():
		return _fail("CONTAINER", "no sim container has a standable spot in reach with a clear line")
	var box: int = int(spot["entity"])
	var stand: Vector2 = spot["at"] as Vector2
	_place_player(scene, stand)
	scene.call("look_toward", scene.call("container_world_point", box))
	_settle_vision(scene, 6)
	if int(scene.call("container_target")) != box:
		ok = _fail("CONTAINER", "aiming at container %d selected %d" % [box, int(scene.call("container_target"))])
	if String(scene.call("container_verdict")) != "ok":
		ok = _fail("CONTAINER", "a container in reach and in aim did not read as usable (%s)" % String(scene.call("container_verdict")))

	# E sends the context menu's own command and opens the real inventory sheet.
	world.commands.record = true
	world.commands.recorded.clear()
	var tick_before: int = int(world.tick)
	_key(KEY_E, true)
	_key(KEY_E, false)
	if not bool(scene.get("inventory_open")):
		ok = _fail("CONTAINER", "E at a container did not open the inventory")
	var panel: Control = scene.call("inventory_panel_node") as Control
	if panel == null or not panel.visible:
		ok = _fail("CONTAINER", "the inventory panel was not visible after E")
	elif panel.get_script() != InventoryPanel:
		ok = _fail("CONTAINER", "E opened something other than the real inventory sheet")
	if bool(scene.call("mouse_captured")):
		ok = _fail("CONTAINER", "the mouse stayed captured with the inventory open")
	# The scene's own frame steps the sim and refreshes the sheet, so the box is a column.
	scene.call("_process", TICK_SECONDS)
	var open_cmd: Dictionary = _last_command(world, "container.open", tick_before)
	if open_cmd.is_empty():
		ok = _fail("CONTAINER", "no container.open command reached the sim")
	elif int(open_cmd.get("container", -1)) != box:
		ok = _fail("CONTAINER", "container.open named %d, not the aimed %d" % [int(open_cmd.get("container", -1)), box])
	if int(SimContainers.opened_by(world, int(world.player))) != box:
		ok = _fail("CONTAINER", "the sim does not have that container open")
	var loot: Dictionary = SimContainers.open_view(world, int(world.player))
	if loot.is_empty():
		ok = _fail("CONTAINER", "the open container has no grid view for the sheet")
	if panel != null:
		if not bool(panel.call("is_open")):
			ok = _fail("CONTAINER", "the inventory sheet is not open")
		var labels: Array = panel.call("column_labels") as Array
		if labels.is_empty() or String(labels[0]) != String(loot.get("label", "")):
			ok = _fail("CONTAINER", "the open box is not the sheet's first column: %s" % str(labels))
		if not labels.has("pockets"):
			ok = _fail("CONTAINER", "the sheet does not show the player's own pockets")

	# A take is the sheet's own quick move: one real item crosses by `item.move`, and nothing is
	# duplicated -- the box-plus-player total is exactly what it was.
	var box_items: Array = SimContainers.contents_of(world, box)
	if box_items.is_empty():
		ok = _fail("CONTAINER", "the opened container rolled no items to take")
	elif panel == null:
		ok = _fail("CONTAINER", "no sheet to take an item with")
	else:
		var item: int = int(box_items[0])
		var before_total: int = box_items.size() + SimInventory.contents_of(world, int(world.player)).size()
		world.commands.recorded.clear()
		var transfer_tick: int = int(world.tick)
		panel.call("_act", "take", item)
		scene.call("_process", TICK_SECONDS)
		var move_cmd: Dictionary = _last_command(world, "item.move", transfer_tick)
		if move_cmd.is_empty() or int(move_cmd.get("container", -1)) != int(world.player):
			ok = _fail("CONTAINER", "the take did not go through an item.move into the player")
		if not SimInventory.owns(world, int(world.player), item):
			ok = _fail("CONTAINER", "the taken item is not in the player's inventory")
		if SimContainers.contents_of(world, box).has(item):
			ok = _fail("CONTAINER", "the taken item is still in the container")
		var after_total: int = SimContainers.contents_of(world, box).size() + SimInventory.contents_of(world, int(world.player)).size()
		if after_total != before_total:
			ok = _fail("CONTAINER", "the transfer changed the box-plus-player count from %d to %d" % [before_total, after_total])

	# The body stands still under the sheet, and the clock runs -- main.gd's own inventory
	# default (only P stops the world), marked reversible in first_person.gd and the report.
	var still: Vector2 = _player_pos(world)
	var clock_before: int = int(world.tick)
	_key(KEY_W, true)
	scene.call("_process", TICK_SECONDS)
	scene.call("_process", TICK_SECONDS)
	_key(KEY_W, false)
	if not _player_pos(world).is_equal_approx(still):
		ok = _fail("CONTAINER", "a walking key moved the body behind the open inventory")
	if int(world.tick) <= clock_before:
		ok = _fail("CONTAINER", "the clock stopped under the open inventory, which main.gd does not do")

	# Escape closes it, tells the sim, and gives the mouse and walking back.
	world.commands.recorded.clear()
	var close_tick: int = int(world.tick)
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	if bool(scene.get("inventory_open")):
		ok = _fail("CONTAINER", "Escape did not close the inventory")
	if panel != null and panel.visible:
		ok = _fail("CONTAINER", "the inventory panel stayed visible after Escape")
	if not bool(scene.call("mouse_captured")):
		ok = _fail("CONTAINER", "Escape did not give the mouse back")
	var held: Variant = scene.get("_held")
	if held is Dictionary and not (held as Dictionary).is_empty():
		ok = _fail("CONTAINER", "Escape left a movement key held")
	scene.call("_process", TICK_SECONDS)
	if _last_command(world, "container.close", close_tick).is_empty():
		ok = _fail("CONTAINER", "Escape did not send container.close")
	if int(SimContainers.opened_by(world, int(world.player))) != -1:
		ok = _fail("CONTAINER", "the sim still has the container open after Escape")

	# Off the aim, in reach: refused in the ledger's words.
	_place_player(scene, stand)
	scene.call("look_toward", scene.call("container_world_point", box))
	_settle_vision(scene, 6)
	scene.call("set_look", float(scene.get("yaw")) + PI, 0.0)
	if String(scene.call("container_verdict")) != "away":
		ok = _fail("CONTAINER", "a container in reach but off the aim did not read as away")
	scene.set("_alert", "")
	_key(KEY_E, true)
	_key(KEY_E, false)
	if bool(scene.get("inventory_open")):
		ok = _fail("CONTAINER", "E opened a container while looking away from it")
	var away_alert: String = String(scene.get("_alert"))
	if away_alert == "" or not away_alert.contains("not looking at it"):
		ok = _fail("CONTAINER", "the off-aim refusal did not say so: \"%s\"" % away_alert)

	# Out of reach: refused with words, and the sim is never asked.
	var box_at: Vector2 = scene.call("container_sim_position", box)
	_place_player(scene, box_at + Vector2(5.0, 0.0))
	scene.call("look_toward", scene.call("container_world_point", box))
	if String(scene.call("container_verdict")) != "far":
		ok = _fail("CONTAINER", "a container five metres away did not read as far (%s)" % String(scene.call("container_verdict")))
	scene.set("_alert", "")
	_key(KEY_E, true)
	_key(KEY_E, false)
	if bool(scene.get("inventory_open")):
		ok = _fail("CONTAINER", "E opened a container from five metres away")
	var far_alert: String = String(scene.get("_alert"))
	if far_alert == "" or not far_alert.contains("Nothing within reach"):
		ok = _fail("CONTAINER", "the out-of-reach refusal did not say so: \"%s\"" % far_alert)

	# Through an opaque wall, still inside the sim's own reach. A whole wall tile is two metres
	# between tile centres and SEARCH_REACH is 1.5, so the fixture slides the box 0.3 m toward
	# the wall and stands the body just past it: close enough to reach, blind because of the wall.
	var walled: Dictionary = _find_walled_container(scene)
	if walled.is_empty():
		ok = _fail("CONTAINER", "no container stands beside an opaque wall with floor beyond it")
	else:
		var wall_ent: int = int(walled["entity"])
		var direction: Vector2i = walled["dir"] as Vector2i
		var original: Vector2 = scene.call("container_sim_position", wall_ent)
		var axis: Vector2 = Vector2(float(direction.x), float(direction.y))
		var nudged: Vector2 = original + axis * 0.30
		var behind: Vector2 = original + axis * 1.55
		if behind.distance_to(nudged) > float(SimContainers.SEARCH_REACH):
			ok = _fail("CONTAINER", "the through-wall fixture is outside reach")
		world.components.set_component(wall_ent, "position", {"x": nudged.x, "y": nudged.y})
		_place_player(scene, behind)
		scene.call("look_toward", scene.call("container_world_point", wall_ent))
		_settle_vision(scene, 6)
		if String(scene.call("container_verdict")) != "blocked":
			ok = _fail("CONTAINER", "a container through an opaque wall did not read as blocked (%s)" % String(scene.call("container_verdict")))
		scene.set("_alert", "")
		_key(KEY_E, true)
		_key(KEY_E, false)
		if bool(scene.get("inventory_open")):
			ok = _fail("CONTAINER", "E opened a container through a wall")
		var wall_alert: String = String(scene.get("_alert"))
		if wall_alert == "" or not wall_alert.contains("behind a wall"):
			ok = _fail("CONTAINER", "the through-wall refusal did not say so: \"%s\"" % wall_alert)
		world.components.set_component(wall_ent, "position", {"x": original.x, "y": original.y})
	scene.set("_alert", "")
	return ok


## A box and a standable floor tile within the sim's own reach from which the eye has a clear
## line to it. Places the player and settles the sim's sight, because that is what "in reach and
## in sight" means to the presentation.
func _find_container_approach(scene: Node) -> Dictionary:
	var world: Variant = scene.get("world")
	var map: Variant = scene.get("map")
	for entity in world.components.query(["searchable", "position"]):
		var ent: int = int(entity)
		var at: Vector2 = scene.call("container_sim_position", ent)
		var base: Vector2i = Vector2i(floori(at.x), floori(at.y))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var tx: int = base.x + dx
				var ty: int = base.y + dy
				if not _walkable_floor(map, tx, ty):
					continue
				var stand: Vector2 = Vector2(float(tx) + 0.5, float(ty) + 0.5)
				if stand.distance_to(at) > float(SimContainers.SEARCH_REACH) - 0.05:
					continue
				_place_player(scene, stand)
				scene.call("look_toward", scene.call("container_world_point", ent))
				_settle_vision(scene, 6)
				if int(scene.call("container_target")) == ent and String(scene.call("container_verdict")) == "ok":
					return {"entity": ent, "at": stand}
	return {}


## A container with an opaque wall directly beside it and walkable floor on the wall's far side.
func _find_walled_container(scene: Node) -> Dictionary:
	var world: Variant = scene.get("world")
	var map: Variant = scene.get("map")
	var directions: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	for entity in world.components.query(["searchable", "position"]):
		var ent: int = int(entity)
		var at: Vector2 = scene.call("container_sim_position", ent)
		var base: Vector2i = Vector2i(floori(at.x), floori(at.y))
		for direction in directions:
			var wall: Vector2i = base + direction
			var beyond: Vector2i = wall + direction
			if not SimTileMap.is_solid(map, wall.x, wall.y):
				continue
			if not SimTileMap.blocks_sight(map, wall.x, wall.y):
				continue
			if not _walkable_floor(map, beyond.x, beyond.y):
				continue
			return {"entity": ent, "dir": direction}
	return {}


# --- FIGHT -----------------------------------------------------------------------------------

## The interim combat input: the top-down buttons' own commands, the sim's melee hit and a spent
## round, the ledger refusing everything, a look away not hitting, and a reload the sim refuses
## without the scene inventing words.
func _fight(scene: Node) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var map: Variant = scene.get("map")
	var camera: Camera3D = scene.get("camera") as Camera3D
	if camera == null:
		return _fail("FIGHT", "the scene has no camera to kick")
	var area: Vector2 = _find_open_area(map, 2)
	if area == Vector2(-1.0, -1.0):
		return _fail("FIGHT", "the district has no open area for a swing")
	_place_player(scene, area)
	scene.call("set_look", 0.0, 0.0)
	scene.call("_process", TICK_SECONDS)

	# The viewmodel: hidden for bare hands, shown with a bat in hand.
	var player: int = int(world.player)
	world.components.remove(player, "rangedWeapon")
	world.components.remove(player, "meleeWeapon")
	SimMelee.ensure_hands(world, player)
	scene.call("_process", TICK_SECONDS)
	if bool(scene.call("held_weapon_visible")):
		ok = _fail("FIGHT", "the placeholder weapon is drawn for bare hands")
	SimMelee.make_melee_armed(world, player)
	SimHealth.make_stamina(world, player, 100)
	scene.call("_process", TICK_SECONDS)
	if not bool(scene.call("held_weapon_visible")):
		ok = _fail("FIGHT", "the placeholder weapon is not drawn with a bat in hand")

	# A shambler in front, inside the bat's reach, held still so the swing is the only thing that
	# can move it.
	var rng: Variant = world.rng.stream("shambler")
	var front: int = int(SimRoster.spawn_zombie(world, area.x, area.y - 1.2, SimRoster.TYPE_SHAMBLER, rng))
	_zero_shambler(world, front)
	var body_before: Dictionary = _body_of(world, front)
	world.commands.record = true
	world.commands.recorded.clear()
	var tick_before: int = int(world.tick)
	_key(KEY_F, true)
	_key(KEY_F, false)
	scene.call("_process", TICK_SECONDS)
	if absf(camera.rotation.x - float(scene.get("pitch"))) <= 0.0001:
		ok = _fail("FIGHT", "a swing produced no camera kick")
	var hit: bool = false
	for _i in range(39):
		scene.call("_process", TICK_SECONDS)
		for event in world.events.drained:
			var e: Dictionary = event as Dictionary
			if String(e.get("type", "")) == "attack.connected" and int(e.get("attacker", -1)) == player and int(e.get("target", -1)) == front:
				hit = true
	if not hit:
		ok = _fail("FIGHT", "the swing button produced no attack.connected on the shambler in front")
	if _last_command(world, "swing", tick_before).is_empty():
		ok = _fail("FIGHT", "the swing button sent no swing command")
	if _body_total(_body_of(world, front)) >= _body_total(body_before):
		ok = _fail("FIGHT", "the shambler's body did not change on a landed swing")
	world.despawn(front)

	# A ranged weapon with six rounds in the magazine: the fire button spends one. The left click
	# is the top-down trigger; the profile names no ammo id, so the counter is the magazine.
	SimRanged.make_ranged_armed(world, player, {"magSize": 6, "rangeMetres": 12.0, "damage": 12.0, "weight": 1.0, "handling": 1.0, "reloadTicks": 20})
	scene.call("_process", TICK_SECONDS)
	var ranged: Dictionary = world.components.get_component(player, "rangedWeapon") as Dictionary
	var mag_before: int = int(ranged.get("mag", 0))
	if mag_before != 6:
		ok = _fail("FIGHT", "the ranged fixture did not start with six rounds (%d)" % mag_before)
	if not bool(scene.call("mouse_captured")):
		_click_mouse()
	world.commands.recorded.clear()
	tick_before = int(world.tick)
	_click_mouse()
	for _i in 60:
		scene.call("_process", TICK_SECONDS)
	if _last_command(world, "fire", tick_before).is_empty():
		ok = _fail("FIGHT", "the left mouse button sent no fire command with a firearm in hand")
	var mag_after: int = int((world.components.get_component(player, "rangedWeapon") as Dictionary).get("mag", -1))
	if mag_after != mag_before - 1:
		ok = _fail("FIGHT", "the fire button did not spend a round (%d -> %d)" % [mag_before, mag_after])

	# Behind the player, with the look turned away: the same press does not hit it.
	var back: int = int(SimRoster.spawn_zombie(world, area.x, area.y + 1.2, SimRoster.TYPE_SHAMBLER, rng))
	_zero_shambler(world, back)
	var back_before: Dictionary = _body_of(world, back)
	_place_player(scene, area)
	scene.call("set_look", 0.0, 0.0)
	scene.call("_process", TICK_SECONDS)
	world.commands.recorded.clear()
	_key(KEY_F, true)
	_key(KEY_F, false)
	var back_hit: bool = false
	for _i in 40:
		scene.call("_process", TICK_SECONDS)
		for event in world.events.drained:
			var e2: Dictionary = event as Dictionary
			if String(e2.get("type", "")) == "attack.connected" and int(e2.get("attacker", -1)) == player and int(e2.get("target", -1)) == back:
				back_hit = true
	if back_hit:
		ok = _fail("FIGHT", "a swing at a shambler behind the player hit it anyway")
	if _body_total(_body_of(world, back)) != _body_total(back_before):
		ok = _fail("FIGHT", "the shambler behind the player lost health to a swing aimed away")
	world.despawn(back)

	# The ledger open: the same press sends nothing.
	scene.call("open_ledger_menu")
	world.commands.recorded.clear()
	var ledger_tick: int = int(world.tick)
	_key(KEY_F, true)
	_key(KEY_F, false)
	_click_mouse()
	scene.call("_process", TICK_SECONDS)
	if not _last_command(world, "swing", ledger_tick).is_empty():
		ok = _fail("FIGHT", "a swing was sent with the ledger open")
	if not _last_command(world, "fire", ledger_tick).is_empty():
		ok = _fail("FIGHT", "a shot was sent with the ledger open")
	scene.call("close_ledger_menu")
	scene.call("_process", TICK_SECONDS)

	# Reload with nothing to load: the sim refuses and the scene says nothing of its own. A fed
	# weapon (an ammo id) with no rounds in the pack opens with an empty magazine and no reload.
	SimRanged.make_ranged_armed(world, player, {"magSize": 6, "ammo": "ammo.9mm", "rangeMetres": 12.0, "damage": 12.0, "weight": 1.0, "handling": 1.0, "reloadTicks": 20})
	scene.call("_process", TICK_SECONDS)
	scene.set("_alert", "")
	world.commands.recorded.clear()
	var reload_tick: int = int(world.tick)
	var reloaded: bool = false
	_key(KEY_R, true)
	_key(KEY_R, false)
	for _i in 30:
		scene.call("_process", TICK_SECONDS)
		for event in world.events.drained:
			if String((event as Dictionary).get("type", "")) == "weapon.reloaded":
				reloaded = true
	if _last_command(world, "reload", reload_tick).is_empty():
		ok = _fail("FIGHT", "the reload key sent no reload command")
	if reloaded:
		ok = _fail("FIGHT", "a reload with nothing to load completed")
	if String(scene.get("_alert")) != "":
		ok = _fail("FIGHT", "the scene invented a reload refusal: %s" % String(scene.get("_alert")))
	scene.set("_kick", 0.0)
	return ok


func _zero_shambler(world: Variant, entity: int) -> void:
	var state: Variant = world.components.get_component(entity, "shambler")
	if state is Dictionary:
		(state as Dictionary)["seekSpeed"] = 0.0
		(state as Dictionary)["wanderSpeed"] = 0.0
		(state as Dictionary)["millSpeed"] = 0.0


func _body_of(world: Variant, entity: int) -> Dictionary:
	var body: Variant = world.components.get_component(entity, "body")
	return (body as Dictionary).duplicate() if body is Dictionary else {}


func _body_total(body: Dictionary) -> float:
	var total: float = 0.0
	for value in body.values():
		if value is float or value is int:
			total += float(value)
	return total


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

	# Outside the ledger, Escape releases the pointer rather than trapping it, and a click resumes
	# mouse look. The HUD says so in the same press.
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	if bool(scene.call("mouse_captured")):
		ok = _fail("LEDGER", "Escape outside the ledger did not release the mouse")
	_click_mouse()
	if not bool(scene.call("mouse_captured")):
		ok = _fail("LEDGER", "a click did not resume mouse look")

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

	# The panel's "their skills" button is a real door: it opens the existing read-only skill web
	# for the picked colonist, and Escape returns to the work grid rather than dropping the whole
	# ledger. No placeholder text is put in front of the player.
	var web: Control = scene.call("web_panel_node") as Control
	if web == null:
		ok = _fail("PRIORITY", "the ledger built no skill web to open")
	else:
		if web.visible:
			ok = _fail("PRIORITY", "the skill web was visible before it was asked for")
		panel.emit_signal("navigate", "skills")
		if not bool(scene.get("_web_open")):
			ok = _fail("PRIORITY", "the panel's skills button did not open the web")
		if not web.visible or panel.visible:
			ok = _fail("PRIORITY", "the web did not replace the work grid")
		if int(web.get("_who")) != ent:
			ok = _fail("PRIORITY", "the web opened on the wrong colonist")
		_key(KEY_ESCAPE, true)
		_key(KEY_ESCAPE, false)
		if bool(scene.get("_web_open")):
			ok = _fail("PRIORITY", "Escape did not leave the skill web")
		if not panel.visible:
			ok = _fail("PRIORITY", "leaving the web did not return to the work grid")
		if not bool(scene.get("menu_open")):
			ok = _fail("PRIORITY", "leaving the web closed the whole ledger")
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
	if bool(scene.call("mouse_captured")):
		ok = _fail("MENU", "focus loss kept the mouse captured")
	_click_mouse()
	if not bool(scene.call("mouse_captured")):
		ok = _fail("MENU", "a click after focus loss did not resume mouse look")
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
	if not joined.contains("release") or not joined.contains("click"):
		ok = _fail("SPEECH", "the HUD does not explain how to release and resume the mouse")
	if not joined.contains("P hold"):
		ok = _fail("SPEECH", "the HUD does not name the pause control")
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


# --- LIGHT -----------------------------------------------------------------------------------

## The sim's day, night, weather and carried light on the 3D screen, and the rule that a torch
## never draws a body the sim says is unseen.
func _light(scene: Node) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var map: Variant = scene.get("map")
	var sky: Node3D = scene.call("sky_view") as Node3D
	if sky == null:
		return _fail("LIGHT", "the scene has no sky view")
	var player: int = int(world.player)

	# Noon: the sun and the ambient are up; an unlit torch leaves the eye light off.
	world.tick = Clock.tick_on_day(1, 0.5)
	scene.call("_process", TICK_SECONDS)
	var noon_sun: float = float(sky.call("sun_energy"))
	var noon_ambient: float = float(sky.call("ambient_energy"))
	if noon_sun <= LIGHT_NOON_SUN_MIN:
		ok = _fail("LIGHT", "the noon sun is %.3f, not above %.2f" % [noon_sun, LIGHT_NOON_SUN_MIN])
	if noon_ambient <= LIGHT_NOON_AMBIENT_MIN:
		ok = _fail("LIGHT", "the noon ambient is %.3f, not above %.2f" % [noon_ambient, LIGHT_NOON_AMBIENT_MIN])
	if bool(sky.call("eye_light_on")):
		ok = _fail("LIGHT", "the eye light is on at noon with nothing lit")

	# Rain darkens the same noon grade, and fog turns the depth fog on.
	SimWeather.set_kind(world, "rain", int(world.tick) + 100)
	scene.call("_process", TICK_SECONDS)
	var rain_sun: float = float(sky.call("sun_energy"))
	if String(sky.call("weather_kind")) != "rain" or rain_sun >= noon_sun * 0.9:
		ok = _fail("LIGHT", "rain did not darken the noon grade (sun %.3f from %.3f)" % [rain_sun, noon_sun])
	SimWeather.set_kind(world, "fog", int(world.tick) + 100)
	scene.call("_process", TICK_SECONDS)
	if not bool(sky.call("fog_enabled")):
		ok = _fail("LIGHT", "the sim's fog did not turn the depth fog on")
	SimWeather.set_kind(world, SimWeather.CLEAR, int(world.tick) + 100)
	scene.call("_process", TICK_SECONDS)

	# Midnight: the sun and the ambient fall below the named thresholds. Pin the sky clear first:
	# jumping the clock lands past the previous span and would otherwise roll a new one.
	world.tick = Clock.tick_on_day(1, 0.8)
	SimWeather.set_kind(world, SimWeather.CLEAR, int(world.tick) + 100)
	scene.call("_process", TICK_SECONDS)
	var night_sun: float = float(sky.call("sun_energy"))
	var night_ambient: float = float(sky.call("ambient_energy"))
	if night_sun >= LIGHT_NIGHT_SUN_MAX:
		ok = _fail("LIGHT", "the midnight sun is %.3f, not below %.2f" % [night_sun, LIGHT_NIGHT_SUN_MAX])
	if night_ambient >= LIGHT_NIGHT_AMBIENT_MAX:
		ok = _fail("LIGHT", "the midnight ambient is %.3f, not below %.2f" % [night_ambient, LIGHT_NIGHT_AMBIENT_MAX])
	if bool(sky.call("eye_light_on")):
		ok = _fail("LIGHT", "the eye light is on at midnight with nothing lit")

	# A torch in hand: the sim's 25 m and 22 degrees become the eye's own spot.
	var torch: int = int(SimItems.spawn_item(world, "item.torch.handheld", {"tier": "scavenged"}))
	if not SimInventory.equip(world, player, torch):
		ok = _fail("LIGHT", "the torch would not go in a hand")
	# One frame drains the equip event, the next reads the light component it wrote.
	scene.call("_process", TICK_SECONDS)
	scene.call("_process", TICK_SECONDS)
	if not bool(sky.call("eye_light_on")):
		ok = _fail("LIGHT", "an equipped, lit torch did not turn the eye light on")
	if absf(float(sky.call("eye_light_range")) - 25.0) > 0.01:
		ok = _fail("LIGHT", "the eye light range is %.2f, not the torch's 25 m" % float(sky.call("eye_light_range")))
	if not bool(sky.call("eye_light_is_spot")):
		ok = _fail("LIGHT", "the torch's beam is not a spot")
	if absf(float(sky.call("eye_light_angle_degrees")) - 22.0) > 0.01:
		ok = _fail("LIGHT", "the eye spot's angle is %.2f, not the torch's 22" % float(sky.call("eye_light_angle_degrees")))

	# An unseen body inside the torch's cone is still not drawn: a wall is the sim's refusal.
	var setup: Dictionary = _find_wall_room(map)
	if setup.is_empty():
		ok = _fail("LIGHT", "no wall with open floor beyond it for the unseen-body negative")
	else:
		var near: Vector2i = setup["tile"] as Vector2i
		var dir: Vector2i = setup["dir"] as Vector2i
		var here: Vector2 = Vector2(float(near.x) + 0.5, float(near.y) + 0.5)
		var far: Vector2 = here + Vector2(float(dir.x), float(dir.y)) * 2.0
		var body: int = int(SimRoster.spawn_zombie(world, far.x, far.y, SimRoster.TYPE_SHAMBLER, world.rng.stream("shambler")))
		_zero_shambler(world, body)
		_place_player(scene, here)
		scene.call("look_toward", Vector3(far.x, 0.9, far.y))
		_settle_vision(scene, 6)
		var detail: int = int(world.vision.call("detail", player, far.x, far.y))
		if detail != 0:
			ok = _fail("LIGHT", "a body behind a wall is seen (%d), so the negative judges nothing" % detail)
		var node: MeshInstance3D = scene.call("body_node_for", body) as MeshInstance3D
		if node == null:
			ok = _fail("LIGHT", "the unseen shambler has no body view, so visibility is unjudged")
		elif node.visible:
			ok = _fail("LIGHT", "the eye light drew a body the sim says is unseen")
		world.despawn(body)

	# The sim burns the torch out; the eye light follows on the next frame.
	var fuel: Variant = world.components.get_component(torch, "lightFuel")
	if not (fuel is Dictionary):
		ok = _fail("LIGHT", "the torch carries no burn clock")
	else:
		(fuel as Dictionary)["ticksLeft"] = 1
		scene.call("_process", TICK_SECONDS)
		scene.call("_process", TICK_SECONDS)
		if bool(sky.call("eye_light_on")):
			ok = _fail("LIGHT", "the eye light stayed on after the torch burnt out")

	# Leave the scene at noon for the lanes after this one.
	world.tick = Clock.tick_on_day(1, 0.5)
	scene.call("_process", TICK_SECONDS)
	return ok


func _find_wall_room(map: Variant) -> Dictionary:
	var directions: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	for ty in range(2, int(map.h) - 2):
		for tx in range(2, int(map.w) - 2):
			if not _walkable_floor(map, tx, ty):
				continue
			for direction in directions:
				var wall: Vector2i = Vector2i(tx, ty) + direction
				var far: Vector2i = wall + direction
				if not SimTileMap.is_solid(map, wall.x, wall.y):
					continue
				if not SimTileMap.blocks_sight(map, wall.x, wall.y):
					continue
				if not _walkable_floor(map, far.x, far.y):
					continue
				return {"tile": Vector2i(tx, ty), "dir": direction}
	return {}


# --- VERBS ----------------------------------------------------------------------------------

# E at a door is the sim's own door verb (`SimContext.verbs_at`), reached from the tile the eye is on.
# Each case is judged on the sim's door state, not on what the view draws.
func _verbs(scene: Node) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var map: Variant = scene.get("map")
	if bool(scene.get("menu_open")):
		scene.call("close_ledger_menu")
	var site: Dictionary = _find_door_site(world, map)
	if site.is_empty():
		return _fail("VERBS", "the district has no closed door with an open floor tile beside it")
	var door: Vector2i = site["door"] as Vector2i
	var stand: Vector2 = site["stand"] as Vector2
	var centre: Vector2 = Vector2(float(door.x) + 0.5, float(door.y) + 0.5)
	var toward: Vector2 = (centre - stand).normalized()
	var was_shut: bool = not _door_open(world, door)

	# True negative: the same door out of reach, three tiles back along the line, looking at it.
	_place_player(scene, centre - toward * 3.0)
	scene.call("look_toward", Vector3(centre.x, 1.0, centre.y))
	scene.call("step_sim_once")
	_key(KEY_E, true)
	scene.call("step_sim_once")
	if _door_open(world, door) != not was_shut:
		ok = _fail("VERBS", "E out of reach changed the door")
	if String(scene.call("verb_prompt")).contains("door"):
		ok = _fail("VERBS", "a door out of reach was offered as a prompt")

	# True negative: the door in reach, but the look turned away from it.
	_place_player(scene, stand)
	scene.call("look_toward", Vector3(stand.x - toward.x * 2.0, 1.0, stand.y - toward.y * 2.0))
	scene.call("step_sim_once")
	_key(KEY_E, true)
	scene.call("step_sim_once")
	if _door_open(world, door) != not was_shut:
		ok = _fail("VERBS", "E with the look turned away changed the door")
	if String(scene.call("verb_prompt")).contains("door"):
		ok = _fail("VERBS", "a door the look is turned away from was offered as a prompt")

	# True positive: in reach and aimed at, the prompt names the sim's row and E opens the door.
	_place_player(scene, stand)
	scene.call("look_toward", Vector3(centre.x, 1.0, centre.y))
	scene.call("step_sim_once")
	var first_prompt: String = String(scene.call("verb_prompt"))
	var want_open: String = "E open the door" if was_shut else "E shut the door"
	if first_prompt != want_open:
		ok = _fail("VERBS", "the prompt at the door is '%s', not '%s'" % [first_prompt, want_open])
	if _has_digit(first_prompt):
		ok = _fail("VERBS", "the door prompt has a digit: %s" % first_prompt)
	_key(KEY_E, true)
	scene.call("step_sim_once")
	if _door_open(world, door) != was_shut:
		ok = _fail("VERBS", "E in reach and aimed at did not change the door")
	# And again: the row flips, and E closes the door it opened.
	var second_prompt: String = String(scene.call("verb_prompt"))
	var want_shut: String = "E shut the door" if was_shut else "E open the door"
	if second_prompt != want_shut:
		ok = _fail("VERBS", "after E the prompt is '%s', not '%s'" % [second_prompt, want_shut])
	_key(KEY_E, true)
	scene.call("step_sim_once")
	if _door_open(world, door) != not was_shut:
		ok = _fail("VERBS", "the second E did not put the door back")

	# True negative: a plain wall in reach and aimed at offers nothing.
	var wall: Dictionary = _find_wall_site(map)
	if wall.is_empty():
		_skips.append("VERBS: no plain wall beside an open floor tile in this district")
	else:
		_place_player(scene, wall["stand"] as Vector2)
		scene.call("look_toward", Vector3((wall["wall"] as Vector2).x, 1.0, (wall["wall"] as Vector2).y))
		scene.call("step_sim_once")
		if String(scene.call("verb_prompt")) != "":
			ok = _fail("VERBS", "a plain wall offered a prompt: %s" % String(scene.call("verb_prompt")))
	return ok


func _door_open(world: Variant, door: Vector2i) -> bool:
	var d: Variant = SimFortify.door_state(world, door.x, door.y)
	return d is Dictionary and bool((d as Dictionary).get("open", false))


# A closed door with an open floor tile orthogonally beside it: the player stands there, on the far side
# of nothing, and looks across the door. The stand is the tile's centre.
func _find_door_site(world: Variant, map: Variant) -> Dictionary:
	for ent in world.components.query(["door"]):
		var d: Variant = world.components.get_component(int(ent), "door")
		if not (d is Dictionary) or bool((d as Dictionary).get("open", false)):
			continue
		var tx: int = int((d as Dictionary).get("tx", 0))
		var ty: int = int((d as Dictionary).get("ty", 0))
		for n in [Vector2i(tx - 1, ty), Vector2i(tx + 1, ty), Vector2i(tx, ty - 1), Vector2i(tx, ty + 1)]:
			if _open_floor(map, n.x, n.y):
				return {"door": Vector2i(tx, ty), "stand": Vector2(float(n.x) + 0.5, float(n.y) + 0.5)}
	return {}


# A plain wall (no overlay, not a door or window) with an open floor tile beside it, for the negative.
func _find_wall_site(map: Variant) -> Dictionary:
	for ty in range(1, int(map.h) - 1):
		for tx in range(1, int(map.w) - 1):
			if SimTileMap.tile_at(map, tx, ty) != SimTileMap.Tile.Wall or SimTileMap.overlay_at(map, tx, ty) != null:
				continue
			for n in [Vector2i(tx - 1, ty), Vector2i(tx + 1, ty), Vector2i(tx, ty - 1), Vector2i(tx, ty + 1)]:
				if _open_floor(map, n.x, n.y):
					return {"wall": Vector2(float(tx) + 0.5, float(ty) + 0.5), "stand": Vector2(float(n.x) + 0.5, float(n.y) + 0.5)}
	return {}


func _open_floor(map: Variant, tx: int, ty: int) -> bool:
	return SimTileMap.tile_at(map, tx, ty) == SimTileMap.Tile.Floor and not SimTileMap.is_solid(map, tx, ty) and SimTileMap.overlay_at(map, tx, ty) == null


# --- STANCE ---------------------------------------------------------------------------------

# The top-down stance keys (Ctrl+Z, Ctrl+C, Ctrl+S, Ctrl+V, and Shift for the sprint latch) push the sim's
# stance command, and the camera's eye follows the posture the sim reports. Each case reads the sim and the
# camera, not the key.
func _stance(scene: Node) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var map: Variant = scene.get("map")
	var camera: Camera3D = scene.get("camera") as Camera3D
	var player: int = int(world.player)
	if bool(scene.get("menu_open")):
		scene.call("close_ledger_menu")
	var origin: Vector2 = _find_open_area(map, 2)
	if origin == Vector2(-1.0, -1.0):
		return _fail("STANCE", "the district has no open area to stand in")
	_place_player(scene, origin)
	scene.call("set_look", 0.0, 0.0)
	_settle_eye(scene)
	if SimStances.stance_of(world.components, player) != SimStances.Stance.Walk:
		return _fail("STANCE", "the fixture did not start standing")
	var eye_walk: float = _eye_of_m(world, player)
	if absf(camera.position.y - eye_walk) > 0.01:
		ok = _fail("STANCE", "the camera stands at %.3f m, not the sim's %.3f m" % [camera.position.y, eye_walk])

	# True positive: Ctrl+C crouches; the eye eases there, and is not already there after one frame.
	_key_ctrl(KEY_C, true)
	_key_ctrl(KEY_C, false)
	_step_ticks(scene, 10)
	if SimStances.stance_of(world.components, player) != SimStances.Stance.Crouch:
		return _fail("STANCE", "Ctrl+C did not make the body crouch")
	var eye_crouch: float = _eye_of_m(world, player)
	scene.call("_process", 1.0 / 60.0)
	if absf(camera.position.y - eye_crouch) < 0.05:
		ok = _fail("STANCE", "the eye jumped to the crouch in one frame, not an ease")
	_settle_eye(scene)
	if absf(camera.position.y - eye_crouch) > 0.01:
		ok = _fail("STANCE", "the eye stands at %.3f m after the crouch, not the sim's %.3f m" % [camera.position.y, eye_crouch])
	if absf(eye_crouch - 0.95) > 0.0001:
		ok = _fail("STANCE", "the sim's crouched eye is %.3f m, not 0.950" % eye_crouch)

	# True positive: Ctrl+S stands the body back up, and the eye comes back to standing height.
	_key_ctrl(KEY_S, true)
	_key_ctrl(KEY_S, false)
	_step_ticks(scene, 10)
	_settle_eye(scene)
	if SimStances.stance_of(world.components, player) != SimStances.Stance.Walk:
		ok = _fail("STANCE", "Ctrl+S did not stand the body back up")
	if absf(camera.position.y - eye_walk) > 0.01:
		ok = _fail("STANCE", "the eye stays at %.3f m after standing, not %.3f m" % [camera.position.y, eye_walk])

	# True positive: Ctrl+Z goes prone, the crawl eye, and Ctrl+S brings it back.
	_key_ctrl(KEY_Z, true)
	_key_ctrl(KEY_Z, false)
	_step_ticks(scene, 10)
	_settle_eye(scene)
	if SimStances.stance_of(world.components, player) != SimStances.Stance.Crawl:
		ok = _fail("STANCE", "Ctrl+Z did not make the body prone")
	elif absf(camera.position.y - _eye_of_m(world, player)) > 0.01:
		ok = _fail("STANCE", "the eye is %.3f m prone, not the sim's crawl eye" % camera.position.y)
	_key_ctrl(KEY_S, true)
	_key_ctrl(KEY_S, false)
	_step_ticks(scene, 10)
	_settle_eye(scene)

	# True negative: with the ledger open, Ctrl+C changes nothing.
	scene.call("open_ledger_menu")
	_key_ctrl(KEY_C, true)
	_key_ctrl(KEY_C, false)
	_step_ticks(scene, 10)
	_settle_eye(scene)
	if SimStances.stance_of(world.components, player) != SimStances.Stance.Walk:
		ok = _fail("STANCE", "Ctrl+C with the ledger open changed the stance")
	if absf(camera.position.y - eye_walk) > 0.01:
		ok = _fail("STANCE", "Ctrl+C with the ledger open moved the eye")
	scene.call("close_ledger_menu")

	# True negative: a sprint the sim refuses on an empty tank leaves the body and the eye standing.
	var stamina: Variant = world.components.get_component(player, "stamina")
	if not (stamina is Dictionary):
		_skips.append("STANCE: the player has no stamina component to empty")
	else:
		var saved: float = float((stamina as Dictionary)["current"])
		(stamina as Dictionary)["current"] = 0.0
		world.components.set_component(player, "stamina", stamina)
		_key(KEY_SHIFT, true)
		_step_ticks(scene, 10)
		if SimStances.stance_of(world.components, player) == SimStances.Stance.Sprint:
			ok = _fail("STANCE", "a sprint was granted on an empty tank")
		_settle_eye(scene)
		if absf(camera.position.y - eye_walk) > 0.01:
			ok = _fail("STANCE", "a refused sprint moved the eye to %.3f m" % camera.position.y)
		_key(KEY_SHIFT, false)
		(stamina as Dictionary)["current"] = saved
		world.components.set_component(player, "stamina", stamina)
	# And with a full tank Shift does sprint, and releasing it returns to the walk.
	_key(KEY_SHIFT, true)
	_step_ticks(scene, 10)
	if SimStances.stance_of(world.components, player) != SimStances.Stance.Sprint:
		ok = _fail("STANCE", "Shift with a full tank did not sprint")
	_key(KEY_SHIFT, false)
	_step_ticks(scene, 10)
	if SimStances.stance_of(world.components, player) != SimStances.Stance.Walk:
		ok = _fail("STANCE", "releasing Shift did not return to the walk")
	return ok


func _eye_of_m(world: Variant, player: int) -> float:
	return float(SimSpace.eye_of(world, player)) / 1000.0


# Steps the sim by whole ticks, as the frame would, so a stance change lands.
func _step_ticks(scene: Node, ticks: int) -> void:
	for i in ticks:
		scene.call("step_sim_once")


# Lets the camera's eye ease to its target: 0.3 s of frames, several times the 0.15 s settle.
func _settle_eye(scene: Node) -> void:
	for i in 18:
		scene.call("_process", 1.0 / 60.0)


func _key_ctrl(code: Key, pressed: bool) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.ctrl_pressed = true
	ev.pressed = pressed
	root.push_input(ev)


# --- REPORTS --------------------------------------------------------------------------------

# The ledger's Reports page: a death written through the sim's event bus is read off the chronicle and shown
# in its own words, marked new; the prompt asks about new reports until the page is read. Escape goes back
# to the work grid, then to the street. The read mark is presentation state, set here as a fixture.
func _reports(scene: Node) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	if bool(scene.get("menu_open")):
		scene.call("close_ledger_menu")
	var props: Node3D = scene.get_node_or_null("SafeSpawnProps") as Node3D
	if props == null:
		return _fail("REPORTS", "the scene has no ledger to stand at")
	_place_player(scene, scene.call("ledger_approach_position") as Vector2)
	scene.call("look_toward", props.call("ledger_world_point") as Vector3)
	_settle_vision(scene)
	var verdict: String = String(scene.call("interaction_verdict"))
	if verdict != "ok":
		return _fail("REPORTS", "the ledger is not in reach and aimed at from its approach (%s)" % verdict)

	# True negative: nothing new, so the prompt does not ask about reports.
	scene.set("_reports_read", (world.chronicle as Array).size())
	scene.call("_update_hud")
	var quiet: String = _joined_hud(scene)
	if not quiet.contains("E read the ledger") or quiet.contains("new reports"):
		ok = _fail("REPORTS", "with nothing new the ledger prompt is not the plain one")

	# A survivor's death, through the event bus the sim's own health code publishes on.
	var victim: int = -1
	for ent in world.components.query(["identity"]):
		var e: int = int(ent)
		if e != int(world.player) and not world.components.has_component(e, "zombieType"):
			victim = e
			break
	if victim < 0:
		return _fail("REPORTS", "the boot has no colonist to write a death for")
	var name: String = String((world.components.get_component(victim, "identity") as Dictionary).get("name", ""))
	var before: int = (world.chronicle as Array).size()
	world.events.publish({"type": "entity.killed", "entity": victim, "killer": -1})
	scene.call("step_sim_once")
	var wrote: bool = false
	for i in range(before, (world.chronicle as Array).size()):
		var rec: Dictionary = (world.chronicle as Array)[i] as Dictionary
		if String(rec.get("kind", "")) == "died" and int(rec.get("e", -1)) == victim:
			wrote = true
	if not wrote:
		return _fail("REPORTS", "the death of %s wrote no chronicle record" % name)
	var expected: String = "%s is dead." % name

	# The prompt asks, now that something is new.
	scene.call("_update_hud")
	if not _joined_hud(scene).contains("E read the ledger, new reports"):
		ok = _fail("REPORTS", "the prompt did not ask about new reports after a death")

	# Open the ledger with E, then the Reports page with a real click on its chip.
	_key(KEY_E, true)
	if not bool(scene.get("menu_open")):
		return _fail("REPORTS", "E in reach and aimed at did not open the ledger")
	var chip: Control = scene.call("reports_chip_node") as Control
	if chip == null or not chip.visible:
		return _fail("REPORTS", "the ledger has no Reports chip")
	_click_at(chip.get_global_rect().get_center())
	var page: Control = scene.call("reports_node") as Control
	if page == null or not page.visible:
		return _fail("REPORTS", "clicking the Reports chip did not show the page")
	var rows: Array = page.call("shown") as Array
	var found: bool = false
	for row in rows:
		var r: Dictionary = row as Dictionary
		if String(r["text"]) == expected:
			found = true
			if not bool(r["new"]):
				ok = _fail("REPORTS", "the page showed '%s' but not marked new" % expected)
	if not found:
		ok = _fail("REPORTS", "the page does not show the chronicle's '%s'" % expected)

	# True negative: every line the page shows is one the chronicle holds; nothing is invented.
	for row in rows:
		var text: String = String((row as Dictionary)["text"])
		if _has_digit(text):
			ok = _fail("REPORTS", "the page shows a digit: %s" % text)
		var held: bool = false
		for rec in world.chronicle as Array:
			if SimChronicle._line_of(world, rec as Dictionary) == text:
				held = true
		if not held:
			ok = _fail("REPORTS", "the page shows a line the chronicle does not hold: %s" % text)

	# Reading moved the mark: the prompt stops asking once the ledger is shut again.
	if int(scene.get("_reports_read")) != (world.chronicle as Array).size():
		ok = _fail("REPORTS", "reading the page did not move the read mark to the end of the record")

	# True negative: Escape from Reports returns to the work grid, not the street.
	_key(KEY_ESCAPE, true)
	if page.visible or not bool(scene.get("menu_open")):
		ok = _fail("REPORTS", "Escape from Reports left the ledger or the page up")
	var grid: Control = scene.call("work_panel_node") as Control
	if grid == null or not grid.visible:
		ok = _fail("REPORTS", "Escape from Reports did not return to the work grid")
	# The next Escape leaves the ledger for the street.
	_key(KEY_ESCAPE, true)
	if bool(scene.get("menu_open")):
		ok = _fail("REPORTS", "the second Escape did not return to the street")
	scene.call("_update_hud")
	var after: String = _joined_hud(scene)
	if after.contains("new reports"):
		ok = _fail("REPORTS", "the prompt still asks about new reports after reading")
	return ok


# --- SAVE -----------------------------------------------------------------------------------

# F5 and F9 go through the sim's own save API, into a slot this lane names and deletes. The key is
# swapped before anything is written and restored after, so a real player's save is never touched.
func _save(scene: Node) -> bool:
	var saved_key: String = SaveSlot.slot_key
	if GATE_SAVE_KEY == SaveSlot.DEFAULT_KEY:
		return _fail("SAVE", "the gate's save key is the real first-person slot")
	SaveSlot.slot_key = GATE_SAVE_KEY
	SaveSlot.remove()
	var ok: bool = _save_lane(scene)
	SaveSlot.remove()
	SaveSlot.slot_key = saved_key
	return ok


func _save_lane(scene: Node) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var map: Variant = scene.get("map")
	var origin: Vector2 = _find_open_area(map, 2)
	if origin == Vector2(-1.0, -1.0):
		return _fail("SAVE", "the district has no open area for a walk")
	_place_player(scene, origin)
	scene.call("set_look", 0.0, 0.0)

	# True negative: F9 with no save present says so and changes nothing.
	var tick_empty: int = int(world.tick)
	var pos_empty: Vector2 = _player_pos(world)
	_key(KEY_F9, true)
	if not _joined_hud(scene).contains("Nothing to load."):
		ok = _fail("SAVE", "F9 with no save did not say so on the HUD")
	if not SaveSlot.read().is_empty():
		ok = _fail("SAVE", "F9 with no save wrote a save")
	if int(world.tick) != tick_empty or _player_pos(world).distance_to(pos_empty) > EPSILON:
		ok = _fail("SAVE", "F9 with no save changed the world")

	# True negative: F5 while the ledger is open does not save, the same way other keys are refused.
	scene.call("open_ledger_menu")
	_key(KEY_F5, true)
	if not SaveSlot.read().is_empty():
		ok = _fail("SAVE", "F5 with the ledger open wrote a save")
	if not bool(scene.get("menu_open")):
		ok = _fail("SAVE", "F5 with the ledger open closed it")
	scene.call("close_ledger_menu")

	# The walk the save is taken in.
	_key(KEY_W, true)
	for i in 10:
		scene.call("step_sim_once")
	_key(KEY_W, false)
	scene.call("step_sim_once")
	var saved_pos: Vector2 = _player_pos(world)
	var saved_tick: int = int(world.tick)
	if saved_pos.distance_to(origin) < 0.15:
		ok = _fail("SAVE", "the walk before the save did not move the body")

	_key(KEY_F5, true)
	if SaveSlot.read().is_empty():
		return _fail("SAVE", "F5 wrote no save")
	if not _joined_hud(scene).contains("Saved."):
		ok = _fail("SAVE", "F5 did not say Saved. on the HUD")

	# Walk further, so a load that did nothing would be visible.
	_key(KEY_W, true)
	for i in 15:
		scene.call("step_sim_once")
	_key(KEY_W, false)
	scene.call("step_sim_once")
	if _player_pos(world).distance_to(saved_pos) < 0.5:
		ok = _fail("SAVE", "the walk after the save did not move the body")
	if int(world.tick) == saved_tick:
		ok = _fail("SAVE", "the world did not advance past the save")

	_key(KEY_F9, true)
	var loaded_pos: Vector2 = _player_pos(world)
	if loaded_pos.distance_to(saved_pos) > EPSILON:
		ok = _fail("SAVE", "F9 put the body at %s, not the saved %s" % [loaded_pos, saved_pos])
	if int(world.tick) != saved_tick:
		ok = _fail("SAVE", "F9 restored tick %d, not the saved %d" % [int(world.tick), saved_tick])
	var rendered: Vector2 = scene.call("rendered_player_position")
	if rendered.distance_to(saved_pos) > EPSILON:
		ok = _fail("SAVE", "the scene still renders the body at %s after F9" % rendered)
	var camera: Camera3D = scene.get("camera") as Camera3D
	var eye: Vector2 = Vector2(camera.global_position.x, camera.global_position.z)
	if eye.distance_to(saved_pos) > 0.001:
		ok = _fail("SAVE", "the camera is at %s after F9, not the saved %s" % [eye, saved_pos])
	if not _joined_hud(scene).contains("Loaded."):
		ok = _fail("SAVE", "F9 did not say Loaded. on the HUD")
	return ok


# The words the HUD is drawing, joined, for the lanes that check what it says. The scene's frame is
# off in this gate, so the HUD is refreshed here the way a frame would refresh it.
func _joined_hud(scene: Node) -> String:
	scene.call("_update_hud")
	var joined: String = ""
	for line in scene.call("hud_lines") as Array:
		joined += String(line) + "\n"
	return joined


# A left click at a screen point, through the engine's own input dispatch.
func _click_at(point: Vector2) -> void:
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = point
	ev.global_position = point
	root.push_input(ev)


# --- SUCCESSION -----------------------------------------------------------------------------

## An heir takes the camera in one cut, the HUD says so in the chronicle's words, the heir walks,
## and the dead body is drawn when the heir can see it. The true negative is a body that is not the
## player: killing it moves nothing.
func _succession(scene: Node) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var map: Variant = scene.get("map")
	var camera: Camera3D = scene.get("camera") as Camera3D
	if camera == null:
		return _fail("SUCCESSION", "the scene has no camera to hand over")

	# True negative: somebody else's death is not the player's, and the eye does not move.
	var npc: int = _non_player_body(world)
	if npc < 0:
		_skips.append("SUCCESSION: no non-player body was left to kill, so the camera's stillness on somebody else's death is unjudged")
	else:
		var player_before: int = int(world.player)
		var camera_before: Vector3 = camera.global_position
		SimHealth.finish_death(world, npc)
		scene.call("_process", TICK_SECONDS)
		if int(world.player) != player_before:
			ok = _fail("SUCCESSION", "an NPC death moved the player to %d" % int(world.player))
		if not camera.global_position.is_equal_approx(camera_before):
			ok = _fail("SUCCESSION", "an NPC death moved the camera")

	if _other_colonists(world).is_empty():
		return _fail("SUCCESSION", "the booted colony has no heir alive, so the player's death cannot hand over")
	var dead: int = int(world.player)
	var dead_pos: Vector2 = _player_pos(world)
	SimHealth.finish_death(world, dead)
	# Drive the tick the handoff landed in, as the game does: the chronicle writes the succession
	# line at drain, and the scene reads it on the next frame.
	world.step()
	if bool(world.runOver):
		return _fail("SUCCESSION", "the player died with an heir alive and the run ended anyway")
	var heir: int = int(world.player)
	if heir == dead:
		return _fail("SUCCESSION", "the player's death left world.player on the dead body")
	if not world.components.has_component(heir, "controlled"):
		ok = _fail("SUCCESSION", "the heir is not controlled")

	# The next frame, the camera is on the heir's sim position -- a cut, not a glide.
	scene.call("_process", TICK_SECONDS)
	var heir_pos: Vector2 = _player_pos(world)
	var rendered: Vector2 = scene.call("rendered_player_position")
	if not rendered.is_equal_approx(heir_pos):
		ok = _fail("SUCCESSION", "the rendered eye is at %s, not the heir at %s" % [str(rendered), str(heir_pos)])
	if not is_equal_approx(camera.global_position.x, heir_pos.x) or not is_equal_approx(camera.global_position.z, heir_pos.y):
		ok = _fail("SUCCESSION", "the camera glided to (%.2f, %.2f), not the heir's (%.2f, %.2f)" % [camera.global_position.x, camera.global_position.z, heir_pos.x, heir_pos.y])

	# The top-down game's own succession sentence, from the chronicle.
	var joined: String = _hud_words(scene)
	if not joined.contains("You are ") or not joined.contains(" now."):
		ok = _fail("SUCCESSION", "the HUD did not name the succession: %s" % joined.strip_edges())
	var identity: Variant = world.components.get_component(heir, "identity")
	var heir_name: String = String((identity as Dictionary).get("name", "")) if identity is Dictionary else ""
	if heir_name != "" and not joined.contains("You are %s now." % heir_name):
		ok = _fail("SUCCESSION", "the HUD said %s, not the chronicle's \"You are %s now.\"" % [joined.strip_edges(), heir_name])

	# The heir is the one who walks now.
	var area: Vector2 = _find_open_area(map, 2)
	if area != Vector2(-1.0, -1.0):
		_place_player(scene, area)
	scene.call("set_look", 0.0, 0.0)
	var walk_from: Vector2 = _player_pos(world)
	_key(KEY_W, true)
	scene.call("_process", TICK_SECONDS)
	scene.call("_process", TICK_SECONDS)
	_key(KEY_W, false)
	scene.call("_process", TICK_SECONDS)
	if _player_pos(world).distance_to(walk_from) < 0.15:
		ok = _fail("SUCCESSION", "W did not walk the heir")

	# The dead body is a body the screen draws, when the heir can see it.
	if not world.components.has_component(dead, "corpse"):
		ok = _fail("SUCCESSION", "the dead player did not become a corpse")
	else:
		_place_player(scene, dead_pos)
		scene.call("look_toward", Vector3(dead_pos.x, 0.90, dead_pos.y))
		_settle_vision(scene, 6)
		var corpse: MeshInstance3D = scene.call("body_node_for", dead) as MeshInstance3D
		if corpse == null:
			ok = _fail("SUCCESSION", "the dead body has no body view")
		elif not corpse.visible:
			ok = _fail("SUCCESSION", "the dead body was not drawn with the heir looking at it")
	return ok


## A living body that is not the player. A shambler first, because killing it cannot shrink the
## heir pool; a colonist only when at least two others are alive (so one is left to succeed).
func _non_player_body(world: Variant) -> int:
	var fallback: int = -1
	var spare: bool = _other_colonists(world).size() >= 2
	for entity in world.components.query(["position", "body"]):
		var ent: int = int(entity)
		if ent == int(world.player) or not world.entities.is_alive(ent):
			continue
		if world.components.has_component(ent, "corpse"):
			continue
		if world.components.has_component(ent, "shambler"):
			return ent
		if fallback < 0:
			fallback = ent
	return fallback if spare else -1


func _other_colonists(world: Variant) -> Array[int]:
	var out: Array[int] = []
	for entity in world.components.query(["position", "body"]):
		var ent: int = int(entity)
		if ent == int(world.player) or not world.entities.is_alive(ent):
			continue
		if world.components.has_component(ent, "corpse"):
			continue
		if world.components.has_component(ent, "recruit"):
			continue
		if not world.components.has_component(ent, "needs") and not world.components.has_component(ent, "identity"):
			continue
		if not SimAllegiance.is_colony(world, ent):
			continue
		out.append(ent)
	return out


func _hud_words(scene: Node) -> String:
	var raw: Variant = scene.call("hud_lines")
	var out: String = ""
	if raw is Array:
		for line in raw as Array:
			out += String(line) + "\n"
	return out


# --- RUN OVER -------------------------------------------------------------------------------

## Kill every colony body. The end panel is up, the mouse is out, the words are the chronicle's,
## and W proposes nothing at all.
func _run_over(scene: Node) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var camera: Camera3D = scene.get("camera") as Camera3D
	for entity in world.components.query(["needs", "body"]):
		var ent: int = int(entity)
		if ent == int(world.player) or not world.entities.is_alive(ent):
			continue
		SimHealth.finish_death(world, ent)
	# The player is last. The loop also takes any heir the sim finds (a body with an identity but
	# no needs, a recruit) so "every colony body" means every one.
	for _i in 8:
		if bool(world.runOver):
			break
		var current: int = int(world.player)
		if not world.entities.is_alive(current):
			break
		SimHealth.finish_death(world, current)
	if not bool(world.runOver):
		return _fail("RUN-OVER", "killing every colony body did not end the run")
	# Drain the tick that ended it, as the game does, so the chronicle has the run-over line.
	world.step()

	scene.call("_process", TICK_SECONDS)
	if not bool(scene.call("run_over_open")):
		ok = _fail("RUN-OVER", "the end-of-run panel did not open")
	if bool(scene.call("mouse_captured")):
		ok = _fail("RUN-OVER", "the mouse stayed captured on the end screen")
	var joined: String = _hud_words(scene)
	if not joined.contains("the run is over"):
		ok = _fail("RUN-OVER", "the end screen has no heading: %s" % joined.strip_edges())
	if not joined.contains("There is nobody left to be."):
		ok = _fail("RUN-OVER", "the end screen does not speak the chronicle's run-over line: %s" % joined.strip_edges())
	var raw: Variant = scene.call("hud_lines")
	if raw is Array:
		for line in raw as Array:
			if _has_digit(String(line)):
				ok = _fail("RUN-OVER", "the end screen drew a digit: %s" % String(line))

	# W is not a command and the eye does not move.
	if camera == null:
		return _fail("RUN-OVER", "the scene lost its camera")
	var camera_before: Vector3 = camera.global_position
	world.commands.record = true
	world.commands.recorded.clear()
	var tick_before: int = int(world.tick)
	_key(KEY_W, true)
	scene.call("_process", TICK_SECONDS)
	scene.call("_process", TICK_SECONDS)
	_key(KEY_W, false)
	scene.call("_process", TICK_SECONDS)
	if not _last_command(world, "move", tick_before).is_empty():
		ok = _fail("RUN-OVER", "W sent a move command on the end screen")
	if not _last_command(world, "aim", tick_before).is_empty():
		ok = _fail("RUN-OVER", "the end screen sent an aim command")
	if not camera.global_position.is_equal_approx(camera_before):
		ok = _fail("RUN-OVER", "the camera moved on the end screen")
	return ok
# --- ART ------------------------------------------------------------------------------------

# The desk and ledger art. When the GLBs are on disk the scene must draw them, not the boxes, at the
# published sizes and on the floor and the desk top. When they are not (a clean checkout before the art
# merges) the lane says so and the boxes are the ones under test. The planted wrong-size GLB is the
# true negative: the same comparison must refuse it.
func _art(scene: Node) -> bool:
	var ok: bool = true
	var desk_on_disk: bool = FileAccess.file_exists(Assets.DESK)
	var ledger_on_disk: bool = FileAccess.file_exists(Assets.LEDGER)
	if not desk_on_disk or not ledger_on_disk:
		_skips.append("ART: desk.glb and ledger.glb are not on disk, so the placeholder boxes are under test (the art arrives with the first-person art PR)")
		if not desk_on_disk and scene.get_node_or_null("SafeSpawnProps/DeskPlaceholder") == null:
			ok = _fail("ART", "desk.glb is absent but the scene did not draw the desk box")
		if not ledger_on_disk and scene.get_node_or_null("SafeSpawnProps/LedgerPlaceholder") == null:
			ok = _fail("ART", "ledger.glb is absent but the scene did not draw the ledger box")
		return ok
	var props: Node3D = scene.get_node_or_null("SafeSpawnProps") as Node3D
	var desk: Node3D = null
	var ledger: Node3D = null
	if props != null:
		desk = props.get_node_or_null("DeskModel") as Node3D
		ledger = props.get_node_or_null("LedgerModel") as Node3D
	if desk == null:
		return _fail("ART", "desk.glb is on disk but the scene drew the placeholder box")
	if ledger == null:
		return _fail("ART", "ledger.glb is on disk but the scene drew the placeholder box")
	var desk_box: AABB = _world_aabb(desk)
	if not _fits(desk_box, Vector3(Assets.DESK_WIDTH_M, Assets.DESK_HEIGHT_M, Assets.DESK_DEPTH_M), 0.0):
		ok = _fail("ART", "the desk model is %s, not the published %.2f x %.2f x %.2f m on the floor" % [desk_box, Assets.DESK_WIDTH_M, Assets.DESK_HEIGHT_M, Assets.DESK_DEPTH_M])
	var ledger_box: AABB = _world_aabb(ledger)
	var ledger_size: Vector3 = Vector3(Assets.LEDGER_WIDTH_M, Assets.LEDGER_THICKNESS_M, Assets.LEDGER_DEPTH_M)
	if not _fits(ledger_box, ledger_size, Assets.DESK_HEIGHT_M):
		ok = _fail("ART", "the ledger model is %s, not the published %s on the desk top" % [ledger_box, ledger_size])
	if not _nearest_everywhere(desk) or not _nearest_everywhere(ledger):
		ok = _fail("ART", "the loaded desk or ledger has a material that is not nearest-filtered")
	var sim: Vector2 = scene.call("ledger_sim_position")
	if absf(ledger_box.get_center().x - sim.x) > 0.01 or absf(ledger_box.get_center().z - sim.y) > 0.01:
		ok = _fail("ART", "the ledger model is not centred on the desk")

	# True negative: a material that is linear-filtered is refused by the same filter test.
	var soft: MeshInstance3D = MeshInstance3D.new()
	soft.mesh = BoxMesh.new()
	soft.material_override = StandardMaterial3D.new()
	scene.add_child(soft)
	if _nearest_everywhere(soft):
		ok = _fail("ART", "a linear-filtered material passed the nearest-filter test")
	soft.free()

	# True negative: a planted GLB of the wrong size, written and read through the same loader, is refused.
	var planted: String = _write_wrong_glb()
	if planted == "":
		return _fail("ART", "could not write the planted wrong-size GLB")
	var wrong: Node3D = Assets.load_model(planted)["node"] as Node3D
	if wrong == null:
		ok = _fail("ART", "the planted GLB did not load, so the refusal proves nothing")
	else:
		scene.add_child(wrong)
		if _fits(_world_aabb(wrong), Vector3(Assets.DESK_WIDTH_M, Assets.DESK_HEIGHT_M, Assets.DESK_DEPTH_M), 0.0):
			ok = _fail("ART", "a planted GLB half the published desk size was accepted")
		wrong.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(planted))
	return ok


# A prop preview whose every prop stands on its authored base: the floor for the desk, the shelf, the
# barricade and the wall, the desk top for the ledger. A loaded model is checked as it was authored, and a
# placeholder box is checked as the preview places it. The planted lift is the M4 fault (a model raised by
# half its height), and it must be refused.
func _preview() -> bool:
	var ok: bool = true
	var packed: PackedScene = load("res://presentation/first_person/prop_preview.tscn") as PackedScene
	if packed == null:
		return _fail("PREVIEW", "could not load the prop preview scene")
	var preview: Node = packed.instantiate()
	root.add_child(preview)
	var bases: Dictionary = {
		"desk": 0.0,
		"ledger": Assets.DESK_HEIGHT_M,
		"shelf": 0.0,
		"barricade": 0.0,
		"wall_module": 0.0,
	}
	for prop in bases.keys():
		var node: Node3D = preview.get_node_or_null(String(prop)) as Node3D
		if node == null:
			ok = _fail("PREVIEW", "the preview has no %s" % prop)
			continue
		var box: AABB = _world_aabb(node)
		if absf(box.position.y - float(bases[prop])) > 0.01:
			ok = _fail("PREVIEW", "the preview's %s floats: its base is at %.3f m, not %.3f m" % [prop, box.position.y, float(bases[prop])])
	# True negative: a model lifted by half its height (the fault) fails the same test.
	var lifted: MeshInstance3D = MeshInstance3D.new()
	var block: BoxMesh = BoxMesh.new()
	block.size = Vector3(Assets.DESK_WIDTH_M, Assets.DESK_HEIGHT_M, Assets.DESK_DEPTH_M)
	lifted.mesh = block
	lifted.position = Vector3(0.0, Assets.DESK_HEIGHT_M, 0.0)
	preview.add_child(lifted)
	if absf(_world_aabb(lifted).position.y) <= 0.01:
		ok = _fail("PREVIEW", "a box lifted by half its height passed as standing on the floor")
	lifted.free()
	preview.queue_free()
	return ok


# The world-space box of a node and everything under it, from each mesh's own bounds.
func _world_aabb(node: Node3D) -> AABB:
	var out: AABB = AABB()
	var found: bool = false
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(node, meshes)
	for mesh in meshes:
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		out = box if not found else out.merge(box)
		found = true
	return out


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, out)


# Every material under the node is nearest-filtered, and there is at least one to judge.
func _nearest_everywhere(node: Node3D) -> bool:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(node, meshes)
	var judged: int = 0
	for m in meshes:
		if m.mesh == null:
			continue
		var surfaces: int = m.mesh.get_surface_count()
		for i in surfaces:
			var material: Material = m.mesh.surface_get_material(i)
			if m.material_override is BaseMaterial3D:
				material = m.material_override
			if material is BaseMaterial3D:
				judged += 1
				if (material as BaseMaterial3D).texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST:
					return false
	return judged > 0


# Size within a centimetre per axis, and the base within a centimetre of `base_y`.
func _fits(box: AABB, size: Vector3, base_y: float) -> bool:
	return absf(box.size.x - size.x) <= 0.01 and absf(box.size.y - size.y) <= 0.01 and absf(box.size.z - size.z) <= 0.01 and absf(box.position.y - base_y) <= 0.01


# Writes a half-size desk as a GLB through the engine's own exporter, so the loader reads a real file.
func _write_wrong_glb() -> String:
	var root: Node3D = Node3D.new()
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var block: BoxMesh = BoxMesh.new()
	block.size = Vector3(Assets.DESK_WIDTH_M * 0.5, Assets.DESK_HEIGHT_M * 0.5, Assets.DESK_DEPTH_M * 0.5)
	mesh.mesh = block
	mesh.position = Vector3(0.0, block.size.y * 0.5, 0.0)
	root.add_child(mesh)
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	if document.append_from_scene(root, state) != OK:
		root.free()
		return ""
	var path: String = "user://fp_art_gate_wrong_desk.glb"
	var err: Error = document.write_to_filesystem(state, ProjectSettings.globalize_path(path))
	root.free()
	return path if err == OK else ""


# --- TALK -----------------------------------------------------------------------------------
#
# The conversation panel, opened by the sim's own E ladder. The words are the read models': the
# identity name, `SimNeeds` / `SimCondition` for how they feel (the mutter content when it exists,
# otherwise the read model's clause), and `WorkRead.doing` for what they are doing. The true
# negatives are the same reach, aim and sight rules the ledger and the boxes use, plus a zombie and a
# raider. The panel is staged with a healthy, fed colonist, then a hungry one; the needs are restored
# afterwards.
func _talk(scene: Node) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var map: Variant = scene.get("map")
	var area: Vector2 = _find_open_area(map, 2)
	if area == Vector2(-1.0, -1.0):
		return _fail("TALK", "the district has no open area to stand in")
	var ent: int = _living_colonist(world, int(world.player))
	if ent < 0:
		return _fail("TALK", "the colony has no second survivor to talk to")
	var name: String = TalkPanel.name_of(world, ent)
	var needs_before: Dictionary = (world.components.get_component(ent, "needs") as Dictionary).duplicate()
	var body_before: Dictionary = (world.components.get_component(ent, "body") as Dictionary).duplicate()
	var injuries_before: Variant = world.components.get_component(ent, "injuries")
	_steady(world, ent)
	_place_player(scene, area)
	scene.call("set_look", 0.0, 0.0)
	_settle_vision(scene, 6)

	# True positive: in reach and aimed at, E opens the panel with the sim's own words.
	_place_talker(world, ent, area + Vector2(0.0, -1.1))
	scene.call("look_toward", Vector3(area.x, _eye_of_m(world, ent), area.y - 1.1))
	_key(KEY_E, true)
	if not bool(scene.get("talk_open")):
		ok = _fail("TALK", "E on a colonist in reach and on the aim opened no panel")
	else:
		var panel: Control = scene.call("talk_panel_node") as Control
		if panel == null:
			ok = _fail("TALK", "the scene has no talk panel")
		else:
			var shown: Dictionary = panel.call("shown") as Dictionary
			if String(shown.get("name", "")) != name:
				ok = _fail("TALK", "the panel names '%s', not the sim's '%s'" % [String(shown.get("name", "")), name])
			if String(shown.get("feel", "")) != TalkPanel.STEADY:
				ok = _fail("TALK", "a steady, fed colonist says '%s', not '%s'" % [String(shown.get("feel", "")), TalkPanel.STEADY])
			var doing: String = WorkRead.doing(world, ent)
			if String(shown.get("doing", "")) != doing:
				ok = _fail("TALK", "the panel's doing line '%s' is not the read model's '%s'" % [String(shown.get("doing", "")), doing])
			for line in panel.call("lines") as Array:
				if _has_digit(String(line)):
					ok = _fail("TALK", "the panel drew a digit: %s" % String(line))
			# Input capture: walking is swallowed while the panel is up.
			var before: Vector2 = _player_pos(world)
			_key(KEY_W, true)
			scene.call("step_sim_once")
			_key(KEY_W, false)
			scene.call("step_sim_once")
			if _player_pos(world).distance_to(before) > EPSILON:
				ok = _fail("TALK", "a walking key moved the body under the talk panel")
			# Escape closes it and gives the mouse back.
			_key(KEY_ESCAPE, true)
			if bool(scene.get("talk_open")):
				ok = _fail("TALK", "Escape did not close the talk panel")
			if not bool(scene.call("mouse_captured")):
				ok = _fail("TALK", "Escape left the mouse free")

	# The need's own line: a hungry colonist says a mutter line, not a sentence the panel invented.
	if ok:
		var needs: Dictionary = world.components.get_component(ent, "needs") as Dictionary
		needs["hunger"] = 1.0
		world.components.set_component(ent, "needs", needs)
		_place_player(scene, area)
		scene.call("set_look", 0.0, 0.0)
		_settle_vision(scene, 6)
		_place_talker(world, ent, area + Vector2(0.0, -1.1))
		scene.call("look_toward", Vector3(area.x, _eye_of_m(world, ent), area.y - 1.1))
		_key(KEY_E, true)
		if not bool(scene.get("talk_open")):
			ok = _fail("TALK", "E on a hungry colonist opened no panel")
		else:
			var hungry: Array[String] = _content_lines(world, "speech.mutter.hungry")
			var said: String = String((scene.call("talk_panel_node") as Control).call("shown")["feel"])
			if hungry.is_empty() or not hungry.has(said):
				ok = _fail("TALK", "a hungry colonist says '%s', not one of the mutter lines %s" % [said, hungry])
			_key(KEY_ESCAPE, true)

	# True negatives. Out of reach.
	_place_talker(world, ent, area + Vector2(0.0, -3.0))
	scene.call("look_toward", Vector3(area.x, _eye_of_m(world, ent), area.y - 3.0))
	_key(KEY_E, true)
	if bool(scene.get("talk_open")):
		ok = _fail("TALK", "E talked to a colonist out of reach")
	# Off the aim.
	_place_talker(world, ent, area + Vector2(0.0, -1.1))
	scene.call("look_toward", Vector3(area.x, _eye_of_m(world, ent), area.y + 4.0))
	_key(KEY_E, true)
	if bool(scene.get("talk_open")):
		ok = _fail("TALK", "E talked to a colonist the look was turned away from")
	# Through a wall.
	var setup: Dictionary = _find_blocked_setup(map)
	if setup.is_empty():
		ok = _fail("TALK", "no wall with open floor beyond it for the sight negative")
	else:
		var tile: Vector2i = setup["tile"] as Vector2i
		var dir: Vector2i = setup["dir"] as Vector2i
		var here: Vector2 = Vector2(float(tile.x) + 0.5, float(tile.y) + 0.5)
		_place_player(scene, here)
		scene.call("set_look", 0.0, 0.0)
		_settle_vision(scene, 6)
		var beyond: Vector2 = here + Vector2(float(dir.x), float(dir.y)) * 1.6
		_place_talker(world, ent, beyond)
		scene.call("look_toward", Vector3(beyond.x, _eye_of_m(world, ent), beyond.y))
		if String(scene.call("talk_verdict")) != "blocked":
			ok = _fail("TALK", "a colonist through a wall reads '%s', not blocked" % String(scene.call("talk_verdict")))
		_key(KEY_E, true)
		if bool(scene.get("talk_open")):
			ok = _fail("TALK", "E talked to a colonist through a wall")
	# A zombie and a raider are never talkable.
	_place_player(scene, area)
	scene.call("set_look", 0.0, 0.0)
	_settle_vision(scene, 6)
	var zombie: int = _living_zombie(world)
	if zombie < 0:
		ok = _fail("TALK", "the colony has no shambler for the never-talkable negative")
	else:
		_place_talker(world, zombie, area + Vector2(0.0, -1.1))
		scene.call("look_toward", Vector3(area.x, _eye_of_m(world, zombie), area.y - 1.1))
		_key(KEY_E, true)
		if bool(scene.get("talk_open")):
			ok = _fail("TALK", "E talked to a shambler")
		var old_faction: Variant = world.components.get_component(ent, "allegiance")
		world.components.set_component(ent, "allegiance", {"faction": "raiders"})
		_place_talker(world, zombie, area + Vector2(3.0, -3.0))
		_place_talker(world, ent, area + Vector2(0.0, -1.1))
		scene.call("look_toward", Vector3(area.x, _eye_of_m(world, ent), area.y - 1.1))
		_key(KEY_E, true)
		if bool(scene.get("talk_open")):
			ok = _fail("TALK", "E talked to a raider")
		if old_faction is Dictionary:
			world.components.set_component(ent, "allegiance", old_faction)
		else:
			world.components.remove(ent, "allegiance")

	# Put the colonist back as found.
	world.components.set_component(ent, "needs", needs_before)
	world.components.set_component(ent, "body", body_before)
	if injuries_before is Dictionary:
		world.components.set_component(ent, "injuries", injuries_before)
	else:
		world.components.remove(ent, "injuries")
	return ok


# A healthy, fed, rested, comfortable colonist: the steady case's fixture. The body is set to its own
# maxima and the wounds are cleared; the caller restores both.
func _steady(world: Variant, ent: int) -> void:
	var needs: Dictionary = world.components.get_component(ent, "needs") as Dictionary
	for key in ["thirst", "hunger", "rest", "relief"]:
		needs[key] = 100.0
	needs["crisis"] = "none"
	needs["temperature"] = "comfortable"
	needs["hygiene"] = "clean"
	needs["grief"] = 0.0
	needs["soiled"] = 0.0
	needs["slept"] = "rested"
	world.components.set_component(ent, "needs", needs)
	var body: Dictionary = world.components.get_component(ent, "body") as Dictionary
	for part in body.keys():
		var max_v: Variant = SimHealth.max_of(body, String(part))
		if max_v != null:
			body[part] = max_v
	world.components.set_component(ent, "body", body)
	world.components.remove(ent, "injuries")


func _place_talker(world: Variant, entity: int, at: Vector2) -> void:
	world.components.set_component(entity, "position", {"x": at.x, "y": at.y})
	world.components.set_component(entity, "velocity", {"dx": 0.0, "dy": 0.0})


func _content_lines(world: Variant, id: String) -> Array[String]:
	var out: Array[String] = []
	if world == null or not ("content" in world) or not (world.content is Dictionary):
		return out
	var rows: Variant = (world.content as Dictionary).get("speech/lines.json", [])
	if not (rows is Array):
		return out
	for row in rows as Array:
		var e: Dictionary = row as Dictionary
		if String(e.get("id", "")) != id:
			continue
		for line in e.get("lines", []) as Array:
			out.append(String(line))
	return out


# --- ANIM -----------------------------------------------------------------------------------

# The animation read model, driven from the sim's own facts. A stance command and a move command are
# the sim's own routes; a swing is the scene's F; a shambler's swipe, hold and stagger are set as the
# sim stores them (they have no command); a death is `finish_death`. A body that stops is idle on the
# next tick, a corpse stays death, and a living body is never death. Every phase is 0..1.
func _anim(scene: Node) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var map: Variant = scene.get("map")
	var player: int = int(world.player)
	var area: Vector2 = _find_open_area(map, 2)
	if area == Vector2(-1.0, -1.0):
		return _fail("ANIM", "the district has no open area to stand in")
	_place_player(scene, area)
	scene.call("set_look", 0.0, 0.0)

	# Standing, then walking on the sim's own move command.
	_push_stance(world, SimStances.Stance.Walk)
	_push_move(world, 0.0, 0.0)
	_step_ticks(scene, 10)
	ok = _expect_state(world, player, AnimState.IDLE, "standing") and ok
	_push_move(world, 1.0, 0.0)
	scene.call("step_sim_once")
	ok = _expect_state(world, player, AnimState.WALK, "a walk command") and ok

	# A jog is a run; the stance changes on the ladder before the step is asked for.
	_push_stance(world, SimStances.Stance.Jog)
	_push_move(world, 0.0, 0.0)
	_step_ticks(scene, 10)
	_push_move(world, 1.0, 0.0)
	scene.call("step_sim_once")
	ok = _expect_state(world, player, AnimState.RUN, "a jog") and ok

	# Crouched, still and moving.
	_push_stance(world, SimStances.Stance.Crouch)
	_push_move(world, 0.0, 0.0)
	_step_ticks(scene, 10)
	ok = _expect_state(world, player, AnimState.CROUCH_IDLE, "a crouch at rest") and ok
	_push_move(world, 1.0, 0.0)
	scene.call("step_sim_once")
	ok = _expect_state(world, player, AnimState.CROUCH_WALK, "a crouched step") and ok

	# Prone.
	_push_stance(world, SimStances.Stance.Crawl)
	_push_move(world, 0.0, 0.0)
	_step_ticks(scene, 10)
	ok = _expect_state(world, player, AnimState.CRAWL, "a crawl") and ok

	# A swing: the top-down button's own F, read in its wind-up and in its recover.
	_push_stance(world, SimStances.Stance.Walk)
	_step_ticks(scene, 10)
	SimMelee.make_melee_armed(world, player)
	SimHealth.make_stamina(world, player, 100)
	_key(KEY_F, true)
	_key(KEY_F, false)
	scene.call("step_sim_once")
	var swing: Variant = world.components.get_component(player, "swing")
	if swing is Dictionary and int((swing as Dictionary).get("state", 0)) == SimMelee.SwingState.WindUp:
		ok = _expect_state(world, player, AnimState.SWING, "a swing's wind-up") and ok
		(world.components.get_component(player, "swing") as Dictionary)["state"] = SimMelee.SwingState.Recover
		ok = _expect_state(world, player, AnimState.SWING, "a swing's recover") and ok
	else:
		ok = _fail("ANIM", "F did not put the body in a swing wind-up")
	world.components.set_component(player, "swing", {"state": SimMelee.SwingState.Idle, "ticksLeft": 0})

	# Stopping returns to idle within one tick: the move command stops the body, and the next step
	# zeroes its velocity.
	_push_move(world, 1.0, 0.0)
	scene.call("step_sim_once")
	ok = _expect_state(world, player, AnimState.WALK, "a walk before the stop") and ok
	_push_move(world, 0.0, 0.0)
	scene.call("step_sim_once")
	ok = _expect_state(world, player, AnimState.IDLE, "a stop, one tick later") and ok

	# A shambler's armed swipe is a lunge, its hold is a grab, and its Staggered state is a stagger.
	var zombie: int = _living_zombie(world)
	if zombie < 0:
		ok = _fail("ANIM", "the colony has no living shambler to pose")
	else:
		var original: Dictionary = (world.components.get_component(zombie, "shambler") as Dictionary).duplicate()
		var shambler: Dictionary = world.components.get_component(zombie, "shambler") as Dictionary
		world.components.remove(zombie, "grabState")
		world.components.remove(zombie, "grabbed")
		shambler["state"] = SimShambler.ShamblerState["Pursue"]
		shambler["ticksToSwipe"] = SimShambler.SWIPE_FIRST_TICKS - 5
		ok = _expect_state(world, zombie, AnimState.LUNGE, "a shambler's armed swipe") and ok
		world.components.set_component(zombie, "grabState", {"victim": player, "ticksUntilBite": SimShambler.FIRST_BITE_TICKS - 4})
		ok = _expect_state(world, zombie, AnimState.GRAB, "a shambler's hold") and ok
		world.components.remove(zombie, "grabState")
		shambler["state"] = SimShambler.ShamblerState["Staggered"]
		shambler["ticksStaggered"] = 10
		ok = _expect_state(world, zombie, AnimState.STAGGER, "a shambler's stagger") and ok
		world.components.set_component(zombie, "shambler", original)

	# A death: a colonist who is not the player dies into a corpse and stays death.
	var victim: int = _living_colonist(world, player)
	if victim < 0:
		ok = _fail("ANIM", "the colony has no second survivor to kill")
	else:
		SimHealth.finish_death(world, victim)
		ok = _expect_state(world, victim, AnimState.DEATH, "a corpse") and ok
		_step_ticks(scene, 30)
		ok = _expect_state(world, victim, AnimState.DEATH, "a corpse after thirty ticks") and ok
		if AnimState.state_of(world, victim) == AnimState.IDLE:
			ok = _fail("ANIM", "a corpse returned to idle")

	# A living body is never death, and every named phase lies in 0..1.
	for ent in world.components.query(["position", "body"]):
		var e: int = int(ent)
		if not world.entities.is_alive(e) or world.components.has_component(e, "corpse"):
			continue
		var answer: Dictionary = AnimState.of(world, e)
		var state: String = String(answer["state"])
		if state == AnimState.DEATH:
			ok = _fail("ANIM", "living body %d reports death" % e)
		var phase: float = float(answer["phase"])
		if phase < 0.0 or phase > 1.0:
			ok = _fail("ANIM", "body %d's %s phase is %.3f, outside 0..1" % [e, state, phase])
		if not AnimState.STATES.has(state):
			ok = _fail("ANIM", "body %d names an unknown state %s" % [e, state])
	return ok


func _expect_state(world: Variant, entity: int, want: String, what: String) -> bool:
	var answer: Dictionary = AnimState.of(world, entity)
	var got: String = String(answer["state"])
	var phase: float = float(answer["phase"])
	if got != want:
		return _fail("ANIM", "%s reads %s, not %s" % [what, got, want])
	if phase < 0.0 or phase > 1.0:
		return _fail("ANIM", "%s names %s with phase %.3f, outside 0..1" % [what, got, phase])
	return true


func _push_stance(world: Variant, stance: int) -> void:
	world.commands.push({"type": "stance", "stance": stance})


func _push_move(world: Variant, dx: float, dy: float) -> void:
	world.commands.push({"type": "move", "dx": dx, "dy": dy})


func _living_zombie(world: Variant) -> int:
	for ent in world.components.query(["position", "body", "shambler"]):
		var e: int = int(ent)
		if world.entities.is_alive(e) and not world.components.has_component(e, "corpse"):
			return e
	return -1


func _living_colonist(world: Variant, exclude: int) -> int:
	for ent in world.components.query(["position", "body", "identity"]):
		var e: int = int(ent)
		if e == exclude or not world.entities.is_alive(e):
			continue
		if world.components.has_component(e, "corpse") or world.components.has_component(e, "zombieType"):
			continue
		return e
	return -1


# --- fixtures -------------------------------------------------------------------------------

func _key(code: Key, pressed: bool) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	root.push_input(ev)


func _click_mouse() -> void:
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
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
