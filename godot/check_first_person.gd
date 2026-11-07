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
#   PITCH     looking up sends the camera's pitch on the `aim` command and the sim's aim holds it
#             (`SimAim.pitch_of`); the mouse stops at the sim's own limit; looking level again
#             sends level and the sim's aim keeps no pitch key (docs/40, slice 3).
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
#   HELD      the equipped weapon in the lower right is the item's own model, assembled from the
#             sim's installed visible parts, each under its socket: a service pistol shows its
#             receiver, barrel and magazine; fitting the suppressor through `item.attach` puts it on
#             the barrel's socket_muzzle; a view that no longer matches the sim fails its own check;
#             bare hands show nothing; the bat is drawn whole with no added head.
#   BENCH     a gunsmith bench is drawn where the sim has one; E at it in reach and on the aim opens
#             the sim's own assembly screen on the held pistol, a part fitted through the screen
#             moves the sim's installed parts and the held view, a refused recipe leaves the parts
#             unchanged with the sim's words, and out of reach, off the aim or through a wall opens
#             no screen.
#   PRIORITY  a click on the panel's first priority cell dispatches a real `job.priority`, the
#             colonist's row changes and turns Manual, and the player is never one of the rows.
#   LEGEND    the key reference (F1) lists every key the scene handles and no other: the handled keys are
#             read from the scene's own source and from input_map's stance bindings, and compared both ways
#             with the codes the legend is built from; a planted phantom code is refused. F1 opens and closes
#             it, Escape closes it, and walking keys do nothing while it is up.
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
#   BODIES    a walking colonist plays walk at the sim's phase and faces the sim's heading; a lunging shambler
#             plays lunge; a corpse plays death and holds its last frame after 300 ticks; loops loop and one-shots
#             do not; a body the sim cannot see is not drawn; a missing model falls back to the capsule.
#   ANIM      the animation read model names the pose from sim facts: standing, a walk, a run, a
#             crouch, a crouch walk, a crawl, a swing (wind-up and recover), a shambler's armed swipe
#             as a lunge, a hold as a grab, a stagger, and a corpse as death. A body that stops is
#             idle on the next tick; a corpse stays death after many ticks; a living body is never
#             death. Every phase is 0..1.
#   TALK      E on one of your colonists in reach and on the aim opens the conversation panel with
#             the sim's name, the read models' own feel and doing lines; every line is digit-free;
#             walking is swallowed while it is up and Escape closes it and recaptures the mouse. Out
#             of reach, off the aim, through a wall, at a zombie and at a raider: no panel.

#   ARMS      the view-model arms (`arms_view.gd`) are what the scene uses: the node under the Eye with an
#             identity transform carries that script, the scene's frame drives it, and the held weapon's
#             grip is under it (a node with another script fails the same test). In first person the
#             arms are up and idle; F2 hides them and F2 brings them back; the key reference and the
#             sheet lower them out of the frame and closing brings them back. The hold class follows
#             the item the sim's own `item.equip` and `item.unequip` commands put in hand -- bare hands
#             unarmed, the service pistol pistol, the bat melee2, the kitchen knife melee1, the hunting
#             rifle long -- and a swap lowers a copy of the old model before the new one is drawn. The
#             weapon's grip node is a child of the `grip_r` bone attachment, and at idle frame 0 the
#             weapon sits on the class's anchor from `arms.json` within 5 mm and 1 degree in camera
#             space, while the same weapon is refused against another class's anchor. Inspect plays only
#             while L is held (it goes round while held and is idle a frame after the release), never
#             with bare hands and never through a screen. Every view-model surface draws with the view
#             model's own lens and pulled-in depth, and a planted plain mesh in the hand is refused.
#   MODELS    every weapons-manifest entry loads and its box is its sizeM within 1 cm; an id match beats a class match and an unknown id resolves to null; two GLBs that embed the atlas share one mipmapped texture; a loose bat the sim drops is drawn with its model at its resting position, and an item with no model has no node.


const SCENE_PATH: String = "res://presentation/first_person/first_person.tscn"
const WorkPanel = preload("res://ui/work_panel.gd")
const InventoryPanel = preload("res://ui/inventory_panel.gd")
const AnimState = preload("res://presentation/first_person/anim_state.gd")
const BodyView = preload("res://presentation/first_person/body_view.gd")
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
const SimAttachments = preload("res://sim/modules/attachments.gd")
const SimGunsmith = preload("res://sim/modules/gunsmith.gd")
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
const InputMapRes = preload("res://presentation/input_map.gd")
const Assets = preload("res://presentation/first_person/assets.gd")
const SimAim = preload("res://sim/aim.gd")
const SaveSlot = preload("res://presentation/first_person/save_slot.gd")
const Models = preload("res://presentation/first_person/models.gd")
const Appearance = preload("res://presentation/appearance.gd")
const ArmsView = preload("res://presentation/first_person/arms_view.gd")
const Hud = preload("res://presentation/first_person/hud.gd")

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
# A model's drawn box against its manifest sizeM, and a loose item against the floor: 1 cm.
const MODEL_TOLERANCE_M: float = 0.01
# A clip position against the sim's phase, in seconds: a frame of slack on a 1 s clip is far below a visible step.
const PHASE_EPSILON: float = 0.001

var _failures: Array[String] = []
var _skips: Array[String] = []
# [name, clause] for every lane that ran and passed. The OK line is built from this, so a new lane
# adds a row at its call site instead of editing one long sentence.
var _lanes: Array = []


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
	var ok: bool = _lane("DISTRICT", _district_default(packed), "the scene boots the shipped district size and seed by default and the gate walks a smaller one")
	ok = _lane("BOOT", _default_boot(), "project.godot boots the first-person scene, and a project that names the top-down scene is refused") and ok
	var scene: Node = packed.instantiate()
	scene.set("district_tiles", SMALL_DISTRICT_TILES)
	root.add_child(scene)
	scene.set_process(false)
	await process_frame

	ok = _lane("SHAPE", _scene_shape(scene), "the scene is the opt-in scene with a district, a HUD and no physics body") and ok
	if ok:
		ok = _district(scene) and ok
		var spawn: Vector2 = scene.call("rendered_player_position")
		ok = _lane("NPC", _npc(scene), "a fresh boot has no working colonist and the colony is at work after a second") and ok
		ok = _lane("MAPPING", _mapping(scene), "sim x/y maps to Godot x/z with the eye at the sim's own height") and ok
		ok = _lane("MOVE", _movement(scene), "W walks the sim's body through the move command and the camera follows") and ok
		ok = _lane("YAW", _yaw(scene), "a turn sends the new move and aim bearings, even with W held") and ok
		ok = _lane("PITCH", _pitch(scene), "the camera's pitch reaches the sim's aim through the aim command") and ok
		ok = _lane("BLOCK", _blocked(scene), "a wall stops the body in its tile and the other way crosses it") and ok
		ok = _lane("CONTAINER", _container(scene), "a sim container opens through container.open into the real sheet and a take moves one item") and ok
		ok = _lane("FIGHT", _fight(scene), "a bat swing lands and a gun spends a round while the ledger refuses both") and ok
		ok = _lane("HELD", _held(scene), "the equipped weapon is drawn from the sim's installed parts on their sockets and a mismatch fails") and ok
		ok = _lane("BENCH", _bench(scene), "E at a bench opens the sim's own assembly screen and a swap moves the sim and the held view") and ok
		ok = _lane("LEDGER", _ledger(scene, spawn), "the ledger opens in reach and on the aim and refuses a look away") and ok
		ok = _lane("PRIORITY", _priority(scene), "a priority click dispatches a real job.priority and the row turns Manual") and ok
		ok = _lane("MENU", _menu(scene), "the ledger's screens open and close on Escape") and ok
		ok = _lane("SPEECH", _speech(scene), "the HUD is digit-free prose with no progress bar") and ok
		ok = _lane("VERBS", _verbs(scene), "E on a door uses the sim's own verb and a plain wall offers none") and ok
		ok = _lane("STANCE", _stance(scene), "the stance keys change the sim's posture and the eye eases to it") and ok
		ok = _lane("REPORTS", _reports(scene), "the ledger's Reports page reads the chronicle's own lines and moves the read mark") and ok
		# The speed lane reads keys, so it runs before the run-over lane, which leaves input swallowed.
		# Save before the lanes that kill the colony: the run-over lane leaves input swallowed.
		ok = _lane("SPEED", _speed(scene), "the top-down speed keys step the clock 1x and 3x and P holds it, with the ledger refusing them") and ok
		ok = _lane("SAVE", _save(scene), "F5 and F9 save and load through the sim's own save in its own slot") and ok
		ok = _lane("ART", _art(scene), "the desk and ledger load from their GLBs at the published sizes") and ok
		ok = _lane("PREVIEW", _preview(), "the prop preview stands every prop on its base") and ok
		ok = _lane("MODELS", _models(scene), "every weapons-manifest entry loads at its declared size with an id match beating a class match") and ok
		ok = _lane("LIGHT", _light(scene), "noon is bright and midnight dark, and a carried torch lights the eye") and ok
		ok = _lane("SUCCESSION", _succession(scene), "a death hands the camera to an heir and the dead body is drawn") and ok
		ok = _lane("LEGEND", _legend(scene), "F1 lists every key the scene handles and the scene handles every key it lists") and ok
		ok = _lane("ARMS", _arms(scene), "the view-model arms are the scene's own under the Eye, lower for screens and third person, follow the sim's equipped hold class, hold the weapon on grip_r at the anchor, inspect only while L is held and never cut into a wall") and ok
		ok = _lane("HANDS", await _hands(scene), "the bare hands at 16:9 and 4:3 do not reach the key bar, and the overlap test sees a bar placed on them") and ok
		ok = _lane("THIRD", _third_person(scene), "F2 steps the camera behind the eye and back, the own body is drawn and plays the sim's clip only in third person, and a wall pulls the camera in while an open line does not") and ok
		ok = _lane("HIDE", _held_visibility(scene), "the held weapon hides while the bench, inventory, ledger, talk and third-person screens are open and shows otherwise") and ok
		ok = _lane("TALK", _talk(scene), "a colonist in reach talks in the read models' own words") and ok
		ok = _lane("ANIM", _anim(scene), "every body names its animation state from the sim with a phase in 0..1") and ok
		ok = _lane("RUN-OVER", _run_over(scene), "killing the colony opens the end panel and W sends nothing") and ok
	scene.queue_free()
	await process_frame
	# The body lane runs its own 300 ticks, so it gets a fresh scene of its own: the colony the other lanes read
	# is not changed by it, and the lane reads a colony that is all there.
	var bodies_scene: Node = packed.instantiate()
	bodies_scene.set("district_tiles", SMALL_DISTRICT_TILES)
	root.add_child(bodies_scene)
	bodies_scene.set_process(false)
	await process_frame
	ok = _lane("BODIES", _character_bodies(bodies_scene), "a walking colonist plays walk at the sim's phase, a lunging shambler plays lunge, a corpse holds death, loops loop and one-shots hold, a body the sim cannot see is hidden, and a missing model falls back to the capsule") and ok
	bodies_scene.queue_free()
	await process_frame
	_finish(old_size, ok)


func _finish(old_size: Vector2i, ok: bool = false) -> void:
	root.size = old_size
	if ok:
		for skip in _skips:
			print("FIRST_PERSON_SKIP " + skip)
		var clauses: Array[String] = []
		for row in _lanes:
			clauses.append(String((row as Array)[1]))
		print("FIRST_PERSON_OK " + ". ".join(clauses) + ". lanes: %d" % _lanes.size())
		quit(0)
		return
	for failure in _failures:
		push_error("FIRST_PERSON_FAIL " + failure)
	quit(1)


## Records a lane that passed, with its one-sentence clause for the OK line, and hands the result back
## so a call site stays `ok = _lane("NAME", _lane_func(...), "clause") and ok`.
func _lane(name: String, passed: bool, clause: String) -> bool:
	if passed:
		_lanes.append([name, clause])
	return passed


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
		var visible_view: Node3D = scene.call("body_node_for", visible_ent) as Node3D
		if visible_view == null or not visible_view.visible:
			ok = _fail("NPC", "a body the sim can see was not drawn")
	if int(scene.call("body_view_visible_count")) <= 0:
		ok = _fail("NPC", "no sim body is visible after the player looked at one")
	# True negative for visibility: a body the sim's own eyes cannot see is not drawn. A lane with
	# no such body says so rather than passing quietly.
	var hidden: int = _first_out_of_sight_body(world)
	if hidden >= 0:
		var hidden_view: Node3D = scene.call("body_node_for", hidden) as Node3D
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


# --- PITCH ----------------------------------------------------------------------------------

func _pitch(scene: Node) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var map: Variant = scene.get("map")
	var area: Vector2 = _find_open_area(map, 2)
	if area == Vector2(-1.0, -1.0):
		return _fail("PITCH", "the district has no open area to look up in")
	var player: int = int(world.player)
	_place_player(scene, area)
	scene.call("set_look", 0.0, 0.0)
	scene.call("_process", TICK_SECONDS)

	# Looking up sends the camera's pitch on the aim, and the sim holds it.
	world.commands.recorded.clear()
	var tick_before: int = int(world.tick)
	scene.call("set_look", 0.0, 0.4)
	scene.call("_process", TICK_SECONDS)
	var up: Dictionary = _last_command(world, "aim", tick_before)
	if up.is_empty() or absf(float(up.get("pitch", 99.0)) - 0.4) > 0.001:
		ok = _fail("PITCH", "looking 0.4 up sent the aim %s" % str(up))
	if absf(SimAim.pitch_of(world.components, player) - 0.4) > 0.001:
		ok = _fail("PITCH", "looking 0.4 up left the sim's aim pitched %.3f" % SimAim.pitch_of(world.components, player))

	# The mouse cannot look past the sim's limit, and the sim holds the limit it was sent.
	scene.call("look_by", 0.0, -100000.0)
	scene.call("_process", TICK_SECONDS)
	if absf(SimAim.pitch_of(world.components, player) - SimAim.PITCH_LIMIT) > 0.001 or absf(float(scene.get("pitch")) - SimAim.PITCH_LIMIT) > 0.001:
		ok = _fail("PITCH", "looking straight up pitched the camera %.3f and the sim %.3f; want both at the %.2f limit" % [float(scene.get("pitch")), SimAim.pitch_of(world.components, player), SimAim.PITCH_LIMIT])

	# Level again: the command says level and the sim's aim keeps no pitch at all.
	world.commands.recorded.clear()
	tick_before = int(world.tick)
	scene.call("set_look", 0.0, 0.0)
	scene.call("_process", TICK_SECONDS)
	var level: Dictionary = _last_command(world, "aim", tick_before)
	var aim: Variant = world.components.get_component(player, "aim")
	if level.is_empty() or float(level.get("pitch", 99.0)) != 0.0:
		ok = _fail("PITCH", "looking level again sent the aim %s" % str(level))
	if not (aim is Dictionary) or (aim as Dictionary).has("pitch") or SimAim.pitch_of(world.components, player) != 0.0:
		ok = _fail("PITCH", "looking level again left the sim's aim %s" % str(aim))
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


# --- BOOT -----------------------------------------------------------------------------------

# The default boot: project.godot names the first-person scene as its main scene, and the scene this gate
# loads is that scene. The reader is proved on fabricated lines first, so "no match" and "a match that
# happens to agree" cannot look the same.
func _default_boot() -> bool:
	if _main_scene_in("run/main_scene=\"res://presentation/main.tscn\"") == SCENE_PATH:
		return _fail("BOOT", "the reader answers the first-person scene for a project that names the top-down one")
	if _main_scene_in("[application]\nconfig/name=\"simplyZOMBIES\"") != "":
		return _fail("BOOT", "the reader invented a main scene for a project file that names none")
	var text: String = FileAccess.get_file_as_string("res://project.godot")
	if text.is_empty():
		return _fail("BOOT", "cannot read res://project.godot")
	var booted: String = _main_scene_in(text)
	if booted != SCENE_PATH:
		return _fail("BOOT", "the game boots '%s', not the first-person scene %s" % [booted, SCENE_PATH])
	return true


func _main_scene_in(text: String) -> String:
	for raw in text.split("\n"):
		var line: String = String(raw).strip_edges()
		if line.begins_with("run/main_scene="):
			return line.substr("run/main_scene=".length()).strip_edges().trim_prefix("\"").trim_suffix("\"")
	return ""


# --- THIRD ----------------------------------------------------------------------------------

# The testing view (docs/39). F2 toggles it. First person hides the player's own body and keeps the camera
# at the eye. Third person draws survivor.glb, plays the clip the sim's state names, and steps the camera
# back to the shoulder spot. A wall on that line pulls the camera in; an open line does not. Every case
# reads the sim and the scene, never the key.
func _third_person(scene: Node) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var map: Variant = scene.get("map")
	var body: Node3D = scene.get("own_body") as Node3D
	var camera: Camera3D = scene.get("camera") as Camera3D
	var rig: Node3D = scene.get("_rig") as Node3D
	if body == null or camera == null or rig == null:
		return _fail("THIRD", "the scene built no own body, no camera or no rig")
	var player: AnimationPlayer = body.get("player") as AnimationPlayer
	if player == null:
		return _fail("THIRD", "the player's own body has no model with an AnimationPlayer: survivor.glb did not load")
	var setup: Dictionary = _find_open_line(map)
	if setup.is_empty():
		return _fail("THIRD", "the district has no floor with three tiles of clear floor behind and ahead")
	var tile: Vector2i = setup["tile"] as Vector2i
	var dir: Vector2i = setup["dir"] as Vector2i
	var centre: Vector2 = Vector2(float(tile.x) + 0.5, float(tile.y) + 0.5)
	var face: float = atan2(-float(dir.x), -float(dir.y))

	# First person: the body is hidden and the camera sits at the eye.
	_place_player(scene, centre)
	scene.call("set_look", face, 0.0)
	_settle_eye(scene)
	scene.call("_update_render", 1.0)
	var eye_local: Vector3 = Vector3(0.0, float(scene.get("_eye_m")), 0.0)
	if bool(scene.get("third_person")) or body.visible:
		ok = _fail("THIRD", "a fresh first-person view shows the player's own body")
	if camera.position.distance_to(eye_local) > 0.001:
		ok = _fail("THIRD", "first person puts the camera at %s, not the eye %s" % [str(camera.position), str(eye_local)])

	# F2 on: the body is drawn, and the camera is behind and above the eye, a little to the right.
	_key(FirstPerson.VIEW_KEY, true)
	_key(FirstPerson.VIEW_KEY, false)
	scene.call("_update_render", 1.0)
	if not bool(scene.get("third_person")):
		return _fail("THIRD", "F2 did not switch to third person")
	if not body.visible:
		ok = _fail("THIRD", "third person hides the player's own body")
	var want: Vector3 = Vector3(FirstPerson.THIRD_RIGHT_M, eye_local.y + FirstPerson.THIRD_UP_M, FirstPerson.THIRD_BACK_M)
	if camera.position.distance_to(want) > 0.01:
		ok = _fail("THIRD", "the open-line camera is at %s, not the shoulder spot %s" % [str(camera.position), str(want)])
	if camera.position.z <= eye_local.z + 1.0:
		ok = _fail("THIRD", "the camera is not behind the eye (z %.3f)" % camera.position.z)

	# The clip is the sim's: standing names the sim's state, walking names walk, and standing again names
	# the standing clip rather than walk.
	var player_id: int = int(world.player)
	var state_now: String = AnimState.state_of(world, player_id)
	var want_clip: String = AnimState.clip_for(AnimState.kind_of(world, player_id), state_now)
	if String(player.current_animation) != want_clip:
		ok = _fail("THIRD", "the own body plays '%s' while the sim's %s state names '%s'" % [String(player.current_animation), state_now, want_clip])
	_key(KEY_W, true)
	for _i in 6:
		scene.call("_process", TICK_SECONDS)
	# Read while W is still held: the tick after a release sends a zero move, and the body stops.
	var moving_state: String = AnimState.state_of(world, player_id)
	var moving_clip: String = String(player.current_animation)
	if not ["walk", "run"].has(moving_state):
		ok = _fail("THIRD", "a survivor walking forward reads '%s', not walk or run" % moving_state)
	if moving_clip != AnimState.clip_for(AnimState.kind_of(world, player_id), moving_state):
		ok = _fail("THIRD", "the own body plays '%s' while the sim's walking state is '%s'" % [moving_clip, moving_state])
	_key(KEY_W, false)
	for _i in 12:
		scene.call("_process", TICK_SECONDS)
	var still_state: String = AnimState.state_of(world, player_id)
	var still_clip: String = String(player.current_animation)
	if ["walk", "run"].has(still_state) or still_clip == "walk" or still_clip == "run":
		ok = _fail("THIRD", "a standing survivor still reads '%s' and plays '%s'" % [still_state, still_clip])
	if still_clip != AnimState.clip_for(AnimState.kind_of(world, player_id), still_state):
		ok = _fail("THIRD", "the own body plays '%s' for the sim's '%s' state" % [still_clip, still_state])

	# F2 off: the body is hidden again and the camera returns to the eye.
	_key(FirstPerson.VIEW_KEY, true)
	_key(FirstPerson.VIEW_KEY, false)
	scene.call("_update_render", 1.0)
	if bool(scene.get("third_person")) or body.visible:
		ok = _fail("THIRD", "F2 back to first person still shows the own body")
	if camera.position.distance_to(eye_local) > 0.001:
		ok = _fail("THIRD", "the camera did not return to the eye (%s)" % str(camera.position))

	# A wall on the line from the eye to the shoulder spot pulls the camera in. The sim's own sight line
	# to the full spot is blocked, and the camera stops short of the full distance.
	var wall: Dictionary = _find_blocked_setup(map)
	if wall.is_empty():
		return _fail("THIRD", "the district has no floor tile with a wall behind it to test the pull-in against")
	var wtile: Vector2i = wall["tile"] as Vector2i
	var wdir: Vector2i = wall["dir"] as Vector2i
	_place_player(scene, Vector2(float(wtile.x) + 0.5, float(wtile.y) + 0.5))
	# Facing away from the wall, so the shoulder spot lies toward it.
	scene.call("set_look", atan2(float(wdir.x), float(wdir.y)), 0.0)
	_settle_eye(scene)
	_key(FirstPerson.VIEW_KEY, true)
	_key(FirstPerson.VIEW_KEY, false)
	scene.call("_update_render", 1.0)
	if not bool(scene.get("third_person")):
		return _fail("THIRD", "F2 did not switch to third person at the wall")
	var pulled: float = camera.position.z
	if pulled >= FirstPerson.THIRD_BACK_M - 1.0:
		ok = _fail("THIRD", "a wall behind the body left the camera at %.3f m, not pulled in" % pulled)
	var eye_w: Vector3 = rig.global_transform * eye_local
	var spot_w: Vector3 = rig.global_transform * want
	var from: Dictionary = {"x": eye_w.x, "y": eye_w.z, "h": roundi(eye_w.y * 1000.0)}
	var to: Dictionary = {"x": spot_w.x, "y": spot_w.z, "h": roundi(spot_w.y * 1000.0)}
	if SimSpace.segment_clear(SimSpace.map_of(world), from, to, SimSpace.SIGHT):
		ok = _fail("THIRD", "the sim's sight line to the full shoulder spot is clear, so the pull-in had no wall to answer")
	_key(FirstPerson.VIEW_KEY, true)
	_key(FirstPerson.VIEW_KEY, false)
	scene.call("_update_render", 1.0)
	return ok


# A floor tile with clear floor three tiles behind and ahead along one cardinal direction, so the shoulder
# spot and a short walk both have room. `dir` is the sim direction the body faces.
func _find_open_line(map: Variant) -> Dictionary:
	var dirs: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	for ty in range(4, int(map.h) - 4):
		for tx in range(4, int(map.w) - 4):
			if not _walkable_floor(map, tx, ty):
				continue
			for d in dirs:
				var clear: bool = true
				for k in [-3, -2, -1, 1, 2, 3]:
					var t: Vector2i = Vector2i(tx, ty) + d * int(k)
					if not _walkable_floor(map, t.x, t.y):
						clear = false
						break
				if clear:
					return {"tile": Vector2i(tx, ty), "dir": d}
	return {}


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


# --- HELD -----------------------------------------------------------------------------------

# The equipped weapon view, read from the sim's own equipment. A real pistol item is spawned and
# equipped through `SimInventory.equip`; the sim's equip handler builds `rangedWeapon` with its
# `source`. The muzzle swap goes through the sim's own `item.attach` command. The negative detaches
# the part in the sim and asks the view's own `verify` before it repaints.
const HELD_HIDDEN_SLOTS: Array[String] = ["internal", "spring", "sear", "extractor"]

func _held(scene: Node) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var player: int = int(world.player)
	# Start from bare hands whatever the fight lane left.
	world.components.remove(player, "rangedWeapon")
	world.components.remove(player, "meleeWeapon")
	SimMelee.ensure_hands(world, player)
	scene.call("_process", TICK_SECONDS)
	if bool(scene.call("held_weapon_visible")):
		ok = _fail("HELD", "bare hands drew a weapon")
	var held: Node3D = scene.call("held_weapon_node") as Node3D
	if held == null:
		return _fail("HELD", "the scene has no held-weapon view")

	# The service pistol: the receiver plus exactly its installed visible parts.
	var pistol: int = int(SimItems.spawn_item(world, "item.pistol.service", {"tier": "scavenged"}))
	if pistol < 0:
		return _fail("HELD", "the service pistol would not spawn")
	if not SimInventory.equip(world, player, pistol):
		return _fail("HELD", "the service pistol would not equip")
	scene.call("step_sim_once")
	scene.call("_process", TICK_SECONDS)
	var want: Dictionary = _held_visible_parts(world, pistol)
	var drawn: Dictionary = held.call("drawn") as Dictionary
	if String(drawn.get("receiver", "")) != "item.pistol.service":
		ok = _fail("HELD", "the pistol drew receiver '%s', not item.pistol.service" % String(drawn.get("receiver", "")))
	var slots: Array = held.call("drawn_slots") as Array
	var want_slots: Array = want.keys()
	want_slots.sort()
	if slots != want_slots:
		ok = _fail("HELD", "the pistol drew slots %s, not the sim's visible %s" % [slots, want_slots])
	for slot_v in want.keys():
		var slot: String = String(slot_v)
		ok = _held_socket_ok(held, slot, String(want[slot_v]), "socket_%s" % slot) and ok
	if not (held.call("missing_parts") as Array).is_empty():
		ok = _fail("HELD", "the default pistol has parts with no model: %s" % str(held.call("missing_parts")))
	if not bool(held.call("verify", world)):
		ok = _fail("HELD", "the pistol view does not match the sim's installed parts")

	# The muzzle swap through the sim's own command: the can lands on the barrel's socket_muzzle.
	var can: int = int(SimItems.spawn_item(world, "item.attach.suppressor", {"tier": "scavenged"}))
	if can < 0:
		return _fail("HELD", "the suppressor would not spawn")
	world.commands.push({"type": "item.attach", "host": pistol, "item": can, "slot": "muzzle"})
	scene.call("step_sim_once")
	scene.call("_process", TICK_SECONDS)
	drawn = held.call("drawn") as Dictionary
	if String(drawn.get("muzzle", "")) != "item.attach.suppressor":
		ok = _fail("HELD", "the fitted suppressor is not drawn (muzzle is '%s')" % String(drawn.get("muzzle", "")))
	if String(held.call("socket_name", "muzzle")) != "socket_muzzle":
		ok = _fail("HELD", "the suppressor is not on a socket_muzzle (it is on '%s')" % String(held.call("socket_name", "muzzle")))
	var barrel: Node3D = held.call("part_node", "barrel") as Node3D
	var muzzle_socket: Node3D = held.call("socket_node", "muzzle") as Node3D
	if barrel == null or muzzle_socket == null or not barrel.is_ancestor_of(muzzle_socket):
		ok = _fail("HELD", "the suppressor is not under the installed barrel's own muzzle socket")
	if not bool(held.call("verify", world)):
		ok = _fail("HELD", "the suppressed view does not match the sim")

	# True negative: detach the can in the sim and do not repaint. The drawn set is now a lie, and
	# `verify` must say so; one update later it is true again.
	if not SimAttachments.detach(world, can):
		ok = _fail("HELD", "the suppressor would not detach through the sim")
	elif bool(held.call("verify", world)):
		ok = _fail("HELD", "a view that disagrees with the sim verified as true")
	scene.call("_process", TICK_SECONDS)
	if not bool(held.call("verify", world)):
		ok = _fail("HELD", "the view did not repaint after the part was detached")
	if (held.call("drawn") as Dictionary).has("muzzle"):
		ok = _fail("HELD", "the drawn set still holds a muzzle part the sim does not")

	# Nothing hidden and nothing uninstalled is ever drawn.
	for slot_v in held.call("drawn_slots") as Array:
		var slot: String = String(slot_v)
		if HELD_HIDDEN_SLOTS.has(slot):
			ok = _fail("HELD", "a hidden slot %s was drawn" % slot)
		if not (held.call("socket_name", slot) as String).begins_with("socket_"):
			ok = _fail("HELD", "slot %s is not on a socket node" % slot)

	# Bare hands again, then the bat whole.
	SimInventory.unequip(world, player, "secondary")
	scene.call("step_sim_once")
	scene.call("_process", TICK_SECONDS)
	if bool(scene.call("held_weapon_visible")):
		ok = _fail("HELD", "unequipping the pistol left a weapon drawn")
	var bat: int = int(SimItems.spawn_item(world, "item.bat.wood", {"tier": "scavenged"}))
	if bat < 0:
		return _fail("HELD", "the bat would not spawn")
	if not SimInventory.equip(world, player, bat):
		return _fail("HELD", "the bat would not equip")
	scene.call("step_sim_once")
	scene.call("_process", TICK_SECONDS)
	drawn = held.call("drawn") as Dictionary
	if String(drawn.get("receiver", "")) != "item.bat.wood":
		ok = _fail("HELD", "the bat drew receiver '%s'" % String(drawn.get("receiver", "")))
	if not (held.call("drawn_slots") as Array).is_empty():
		ok = _fail("HELD", "the bat drew parts on top of its whole model: %s" % str(held.call("drawn_slots")))
	if held.call("part_node", "head") != null:
		ok = _fail("HELD", "the bat added a head part over its own model")
	if bool(held.call("drawn_is_ranged")):
		ok = _fail("HELD", "the bat is drawn as a ranged assembly")
	if not bool(held.call("verify", world)):
		ok = _fail("HELD", "the bat view does not match the sim's item")
	return ok


# The visible installed parts of a host, as {slot: base id} -- the same set the assembler must draw.
func _held_visible_parts(world: Variant, host: int) -> Dictionary:
	var out: Dictionary = {}
	var fitted: Dictionary = SimAttachments.attached(world, host)
	for slot_v in fitted.keys():
		var slot: String = String(slot_v)
		if HELD_HIDDEN_SLOTS.has(slot):
			continue
		var base: Variant = SimItems.item_base_of(world, int(fitted[slot_v]))
		if base is Dictionary:
			out[slot] = String((base as Dictionary).get("id", ""))
	return out


func _held_socket_ok(held: Node3D, slot: String, want_id: String, want_socket: String) -> bool:
	var drawn: Dictionary = held.call("drawn") as Dictionary
	if String(drawn.get(slot, "")) != want_id:
		return _fail("HELD", "%s draws '%s', not '%s'" % [slot, String(drawn.get(slot, "")), want_id])
	var part: Node3D = held.call("part_node", slot) as Node3D
	var socket: Node3D = held.call("socket_node", slot) as Node3D
	if part == null or socket == null:
		return _fail("HELD", "%s is not parented on a socket" % slot)
	if socket.get_parent() == null:
		return _fail("HELD", "%s's socket is not in the receiver" % slot)
	if String(socket.name) != want_socket:
		return _fail("HELD", "%s is on '%s', not '%s'" % [slot, String(socket.name), want_socket])
	return true


# --- BENCH -----------------------------------------------------------------------------------
#
# The gunsmith bench as a physical place. A bench is built through the sim's own `bench.build`
# channel when the small district has none, which is exactly the path a player's 3 scrap and a
# colonist's Construct job both end in (`SimGunsmith.make_bench`). E at it opens the sim's own
# `benchFocus`; the assembly screen is `ui/bench_panel.gd`, and every operation it pushes is a sim
# command. A bench is the E ladder's fourth rung, after the ledger and the boxes, before a colonist.
func _bench(scene: Node) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var map: Variant = scene.get("map")
	var player: int = int(world.player)
	if bool(scene.get("bench_open")):
		world.commands.push({"type": "bench.close"})
		scene.call("step_sim_once")
	var bench: int = _bench_first(world)
	if bench < 0:
		bench = _bench_build(scene, world, map)
	if bench < 0:
		return _fail("BENCH", "no gunsmith bench exists and the sim would not build one")
	scene.call("_process", TICK_SECONDS)
	# Drawn where the sim has it.
	var node: Node3D = scene.call("bench_node_for", bench) as Node3D
	if node == null:
		ok = _fail("BENCH", "the sim's bench %d has no node in the scene" % bench)
	else:
		var at: Vector2 = _entity_pos(world, bench)
		if absf(node.position.x - at.x) > EPSILON or absf(node.position.z - at.y) > EPSILON:
			ok = _fail("BENCH", "the bench is drawn at (%.3f, %.3f), not its sim position (%.3f, %.3f)" % [node.position.x, node.position.z, at.x, at.y])

	# The pistol on the bench: the equipped weapon is the first workpiece, as top-down takes it.
	# The HELD lane leaves a bat in the primary hand; the bench would rightly offer that first, so
	# the gate puts it away to make the pistol the workpiece under test.
	world.components.remove(player, "rangedWeapon")
	world.components.remove(player, "meleeWeapon")
	if world.components.has_component(player, "equipment"):
		SimInventory.unequip(world, player, "primary")
	var pistol: int = int(SimItems.spawn_item(world, "item.pistol.service", {"tier": "scavenged"}))
	if pistol < 0 or not SimInventory.equip(world, player, pistol):
		return _fail("BENCH", "the service pistol would not spawn and equip")
	scene.call("step_sim_once")
	var bench_at: Vector2 = _entity_pos(world, bench)
	var stand: Vector2 = _bench_stand(map, bench_at)
	_place_player(scene, stand)
	scene.call("look_toward", scene.call("bench_world_point", bench))
	_settle_vision(scene, 6)
	if String(scene.call("bench_verdict")) != "ok":
		ok = _fail("BENCH", "a bench in reach and on the aim reads '%s', not ok" % String(scene.call("bench_verdict")))
	_key(KEY_E, true)
	scene.call("step_sim_once")
	scene.call("_process", TICK_SECONDS)
	if not bool(scene.get("bench_open")):
		ok = _fail("BENCH", "E at a bench did not open the assembly screen")
	if SimGunsmith.focus_of(world, player) != pistol:
		ok = _fail("BENCH", "the bench opened on %d, not the held pistol %d" % [SimGunsmith.focus_of(world, player), pistol])
	var panel: Control = scene.call("bench_panel_node") as Control
	if panel == null or not panel.visible:
		ok = _fail("BENCH", "the bench panel is not visible")
	# Input capture and the clock.
	var before: Vector2 = _player_pos(world)
	var tick: int = int(world.tick)
	_key(KEY_W, true)
	scene.call("step_sim_once")
	scene.call("_process", TICK_SECONDS)
	_key(KEY_W, false)
	if _player_pos(world).distance_to(before) > EPSILON:
		ok = _fail("BENCH", "a walking key moved the body under the bench screen")
	if int(world.tick) <= tick:
		ok = _fail("BENCH", "the clock stopped under the bench screen")

	# A swap through the screen's command: the suppressor into the empty muzzle slot.
	var can: int = int(SimItems.spawn_item(world, "item.attach.suppressor", {"tier": "scavenged"}))
	if can < 0 or not _stow_with_room(world, player, can):
		ok = _fail("BENCH", "the suppressor would not spawn and stow")
	else:
		world.commands.push({"type": "item.attach", "host": pistol, "item": can, "slot": "muzzle"})
		scene.call("step_sim_once")
		scene.call("_process", TICK_SECONDS)
		if SimAttachments.in_slot(world, pistol, "muzzle") != can:
			ok = _fail("BENCH", "the screen's fit did not put the suppressor on the pistol")
		var held: Node3D = scene.call("held_weapon_node") as Node3D
		if held == null:
			ok = _fail("BENCH", "the scene has no held-weapon view")
		elif String((held.call("drawn") as Dictionary).get("muzzle", "")) != "item.attach.suppressor":
			ok = _fail("BENCH", "the held view did not redraw with the fitted suppressor")

	# Escape pushes the sim's own close; the screen goes with the focus.
	_key(KEY_ESCAPE, true)
	scene.call("step_sim_once")
	scene.call("_process", TICK_SECONDS)
	if bool(scene.get("bench_open")) or SimGunsmith.focus_of(world, player) != -1:
		ok = _fail("BENCH", "Escape did not close the bench through the sim")

	# A refused operation: the pistol's slots take no improvised recipe (the parts are made for
	# melee studs, weights and wraps), so the gate opens the screen on a bat and asks for a part
	# with the pack emptied of every build material. The screen's words must be the sim's, and the
	# bat's parts must not move.
	for item_v in SimInventory.carried_items(world, player) as Array:
		if SimFortify.material_of(world, int(item_v)) != "":
			SimInventory.drop_at_feet(world, player, int(item_v))
	var bat: int = int(SimItems.spawn_item(world, "item.bat.wood", {"tier": "scavenged"}))
	if bat < 0 or not _stow_with_room(world, player, bat) or not SimInventory.equip(world, player, bat):
		ok = _fail("BENCH", "a bat would not spawn, stow and equip for the refusal")
	else:
		scene.call("step_sim_once")
		_key(KEY_E, true)
		scene.call("step_sim_once")
		scene.call("_process", TICK_SECONDS)
		if not bool(scene.get("bench_open")) or SimGunsmith.focus_of(world, player) != bat:
			ok = _fail("BENCH", "E did not open the bench on the bat the survivor carries")
		var screen: Dictionary = panel.get("_view") as Dictionary
		var refused: Dictionary = {}
		for row_v in screen.get("recipes", []) as Array:
			var row: Dictionary = row_v as Dictionary
			if not bool(row.get("makeable", true)) and String(row.get("needs", "")) != "":
				refused = row
				break
		if refused.is_empty():
			ok = _fail("BENCH", "the bench offers no recipe the sim refuses, so the refusal is unjudged")
		else:
			var slot: String = String(refused.get("slot", ""))
			var recipe: String = String(refused.get("recipe", ""))
			var reason: String = SimAttachments.improvise_refusal(world, player, bat, slot, recipe)
			if reason == "":
				ok = _fail("BENCH", "the row the screen calls unmakeable is not refused by the sim")
			if String(refused.get("needs", "")) != SimAttachments.improvise_needs(world, player, recipe, reason):
				ok = _fail("BENCH", "the screen's needs words are not the sim's")
			var fitted_before: Dictionary = SimAttachments.attached(world, bat)
			world.commands.push({"type": "item.improvise", "host": bat, "slot": slot, "recipe": recipe})
			scene.call("step_sim_once")
			if SimAttachments.attached(world, bat) != fitted_before:
				ok = _fail("BENCH", "a refused recipe changed the bat's parts")
			var refused_event: bool = false
			for event_v in world.events.drained as Array:
				var event: Dictionary = event_v as Dictionary
				if String(event.get("type", "")) == "attachment.refused" and String(event.get("reason", "")) == reason:
					refused_event = true
			if not refused_event:
				ok = _fail("BENCH", "the refused recipe published no attachment.refused with the sim's reason")
		_key(KEY_ESCAPE, true)
		scene.call("step_sim_once")
		scene.call("_process", TICK_SECONDS)
		if bool(scene.get("bench_open")) or SimGunsmith.focus_of(world, player) != -1:
			ok = _fail("BENCH", "Escape did not close the bench after the refusal")

	# True negatives: out of reach, off the aim, and through a wall.
	_place_player(scene, bench_at + Vector2(0.0, 4.0))
	scene.call("look_toward", scene.call("bench_world_point", bench))
	scene.call("step_sim_once")
	if String(scene.call("bench_verdict")) != "far":
		ok = _fail("BENCH", "a bench four metres away reads '%s', not far" % String(scene.call("bench_verdict")))
	_key(KEY_E, true)
	scene.call("step_sim_once")
	if SimGunsmith.focus_of(world, player) != -1 or bool(scene.get("bench_open")):
		ok = _fail("BENCH", "E opened a bench out of reach")
	_place_player(scene, stand)
	scene.call("look_toward", scene.call("bench_world_point", bench) + Vector3(4.0, 0.0, 0.0))
	scene.call("step_sim_once")
	if String(scene.call("bench_verdict")) != "away":
		ok = _fail("BENCH", "a bench in reach but off the aim reads '%s', not away" % String(scene.call("bench_verdict")))
	_key(KEY_E, true)
	scene.call("step_sim_once")
	if SimGunsmith.focus_of(world, player) != -1 or bool(scene.get("bench_open")):
		ok = _fail("BENCH", "E opened a bench the look was turned away from")
	var setup: Dictionary = _find_blocked_setup(map)
	if setup.is_empty():
		ok = _fail("BENCH", "no wall with open floor beyond it for the sight negative")
	else:
		var tile: Vector2i = setup["tile"] as Vector2i
		var dir: Vector2i = setup["dir"] as Vector2i
		var here: Vector2 = Vector2(float(tile.x) + 0.5, float(tile.y) + 0.5)
		_place_player(scene, here)
		scene.call("set_look", 0.0, 0.0)
		_settle_vision(scene, 6)
		var beyond: Vector2 = here + Vector2(float(dir.x), float(dir.y)) * 1.4
		var walled: int = SimGunsmith.make_bench(world, beyond.x, beyond.y)
		scene.call("_process", TICK_SECONDS)
		scene.call("look_toward", Vector3(beyond.x, 0.8, beyond.y))
		if String(scene.call("bench_verdict")) != "blocked":
			ok = _fail("BENCH", "a bench through a wall reads '%s', not blocked" % String(scene.call("bench_verdict")))
		_key(KEY_E, true)
		scene.call("step_sim_once")
		if SimGunsmith.focus_of(world, player) != -1 or bool(scene.get("bench_open")):
			ok = _fail("BENCH", "E opened a bench through a wall")
		world.despawn(walled)
		scene.call("_process", TICK_SECONDS)

	# The other way a bench arrives: a colonist's Construct job ends in the same `make_bench`, so a
	# bench the player did not build is drawn too.
	var free: Vector2 = _find_open_area(map, 2)
	var built_elsewhere: int = SimGunsmith.make_bench(world, free.x, free.y)
	scene.call("_process", TICK_SECONDS)
	if scene.call("bench_node_for", built_elsewhere) == null:
		ok = _fail("BENCH", "a bench made outside the player's build is not drawn")
	world.despawn(built_elsewhere)
	scene.call("_process", TICK_SECONDS)
	return ok


# Stows an item, making room by dropping the carried item in the first pocket when the pack is full.
# The gate is deep in a run by this lane and the player's kit is already settled, so one drop is the
# honest way to hold the sim's own three scrap; the dropped item stays in the world.
func _stow_with_room(world: Variant, player: int, item: int) -> bool:
	if SimInventory.stow(world, player, item):
		return true
	for _i in 8:
		var carried: Array = SimInventory.contents_of(world, player) as Array
		if carried.is_empty():
			return false
		SimInventory.drop_at_feet(world, player, int(carried[0]))
		if SimInventory.stow(world, player, item):
			return true
	return false


# The first walkable floor tile orthogonally beside a bench, as its stand point, or the bench's own
# position when every side is solid.
func _bench_stand(map: Variant, at: Vector2) -> Vector2:
	var base: Vector2i = Vector2i(floori(at.x), floori(at.y))
	for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]:
		var t: Vector2i = base + d
		if _walkable_floor(map, t.x, t.y):
			return Vector2(float(t.x) + 0.5, float(t.y) + 0.5)
	return at


# The first gunsmith bench in the world, or -1.
func _bench_first(world: Variant) -> int:
	for entity in world.components.query(["workbench", "position"]):
		var state: Variant = world.components.get_component(int(entity), "workbench")
		if state is Dictionary and String((state as Dictionary).get("kind", "")) == SimGunsmith.KIND:
			return int(entity)
	return -1


# Builds a bench through the sim's own bench channel: an adjacent empty floor tile, the sim's own
# BENCH_SCRAP of metal in the pack, `bench.build`, then the 160 ticks the channel takes.
func _bench_build(scene: Node, world: Variant, map: Variant) -> int:
	var player: int = int(world.player)
	var area: Vector2 = _find_open_area(map, 2)
	if area == Vector2(-1.0, -1.0):
		return -1
	_place_player(scene, area)
	scene.call("set_look", 0.0, 0.0)
	var base: Vector2i = Vector2i(floori(area.x), floori(area.y))
	var tile: Vector2i = Vector2i(-1, -1)
	for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var t: Vector2i = base + d
		if _walkable_floor(map, t.x, t.y):
			tile = t
			break
	if tile == Vector2i(-1, -1):
		return -1
	var scrap: int = int(SimItems.spawn_item(world, "item.scrap.metal", {"tier": "scavenged", "count": int(SimGunsmith.BENCH_SCRAP)}))
	if scrap < 0 or not _stow_with_room(world, player, scrap):
		return -1
	world.commands.push({"type": "bench.build", "tx": tile.x, "ty": tile.y})
	for _i in 220:
		scene.call("step_sim_once")
		var built: int = _bench_first(world)
		if built >= 0:
			return built
	return -1


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
		var node: Node3D = scene.call("body_node_for", body) as Node3D
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
		var corpse: Node3D = scene.call("body_node_for", dead) as Node3D
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
				# Nearest magnification keeps the pixel art crisp; mipmaps keep a wall at 8 m from
				# shimmering (the art review's note on #281). Linear magnification is still refused.
				if (material as BaseMaterial3D).texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS:
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


# --- LEGEND ---------------------------------------------------------------------------------

# The engine's key constants the first-person source names. A key the source names that is missing from
# this map is a failure, so a new key cannot slip past the check unnamed.
const KEY_NAMES: Dictionary = {
	"KEY_A": KEY_A, "KEY_D": KEY_D, "KEY_E": KEY_E, "KEY_ENTER": KEY_ENTER, "KEY_ESCAPE": KEY_ESCAPE,
	"KEY_F": KEY_F, "KEY_F1": KEY_F1, "KEY_F2": KEY_F2, "KEY_F5": KEY_F5, "KEY_F9": KEY_F9, "KEY_G": KEY_G,
	"KEY_KP_ENTER": KEY_KP_ENTER, "KEY_P": KEY_P, "KEY_R": KEY_R, "KEY_S": KEY_S, "KEY_SHIFT": KEY_SHIFT,
	"KEY_W": KEY_W, "KEY_MINUS": KEY_MINUS, "KEY_KP_SUBTRACT": KEY_KP_SUBTRACT, "KEY_EQUAL": KEY_EQUAL,
	"KEY_KP_ADD": KEY_KP_ADD, "KEY_L": KEY_L,
}


func _legend(scene: Node) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	if bool(scene.get("menu_open")):
		scene.call("close_ledger_menu")
	if bool(scene.get("inventory_open")):
		scene.call("close_inventory")
	if bool(scene.call("legend_open")):
		scene.call("close_legend")
	var source: String = FileAccess.get_file_as_string("res://presentation/first_person/first_person.gd")
	var handled: Array = []
	for name in _handled_key_names(source):
		if not KEY_NAMES.has(name):
			return _fail("LEGEND", "the scene names %s, which the LEGEND lane's key map does not know" % name)
		if not handled.has(int(KEY_NAMES[name])):
			handled.append(int(KEY_NAMES[name]))
	# The stance keys reach the scene through input_map's BINDINGS, not a name in the source.
	for action in InputMapRes.BINDINGS.keys():
		var row: Dictionary = InputMapRes.BINDINGS[action] as Dictionary
		if row.has("stance") and not handled.has(int((row["keys"] as Array)[0])):
			handled.append(int((row["keys"] as Array)[0]))
	# So do the clock's keys: the scene reads input_map's "slower" and "faster" rows, every key of each.
	for action in ["slower", "faster"]:
		if not source.contains("\"%s\"" % action):
			continue
		for code in (InputMapRes.BINDINGS[action] as Dictionary)["keys"] as Array:
			if not handled.has(int(code)):
				handled.append(int(code))
	var listed: Array = FirstPerson.reference_codes()
	# Both ways: every key the scene handles is listed, and no listed key is one the scene does not handle.
	if not _codes_missing(handled, listed).is_empty():
		ok = _fail("LEGEND", "the scene handles keys the key reference does not list: %s" % str(_codes_missing(handled, listed)))
	if not _codes_missing(listed, handled).is_empty():
		ok = _fail("LEGEND", "the key reference lists keys the scene does not handle: %s" % str(_codes_missing(listed, handled)))
	# True negative: a planted phantom row (a key nothing handles) is refused by the same comparison.
	var planted: Array = listed.duplicate()
	planted.append(KEY_BRACKETLEFT)
	if _codes_missing(planted, handled).is_empty():
		ok = _fail("LEGEND", "a planted phantom key passed the comparison")

	# The toggle: F1 opens the reference, F1 again and Escape each put it down.
	_key(KEY_F1, true)
	if not bool(scene.call("legend_open")) or not (scene.call("legend_node") as Control).visible:
		ok = _fail("LEGEND", "F1 did not open the key reference")
	_place_player(scene, _find_open_area((scene.get("map") as Variant), 2))
	var before: Vector2 = _player_pos(world)
	_key(KEY_W, true)
	for i in 20:
		scene.call("_process", 1.0 / 60.0)
	_key(KEY_W, false)
	if _player_pos(world).distance_to(before) > 0.01:
		ok = _fail("LEGEND", "walking moved the body while the key reference was open")
	_key(KEY_ESCAPE, true)
	if bool(scene.call("legend_open")) or (scene.call("legend_node") as Control).visible:
		ok = _fail("LEGEND", "Escape did not close the key reference")
	_key(KEY_F1, true)
	_key(KEY_F1, true)
	if bool(scene.call("legend_open")):
		ok = _fail("LEGEND", "a second F1 did not close the key reference")
	return ok


# --- ARMS ------------------------------------------------------------------------------------
#
# The view-model arms. Everything is driven through the scene's own frame (`_process` at 60 fps) and its
# real key dispatch; the item in hand changes only through the sim's own equip commands.

const ARMS_SCRIPT: String = "res://presentation/first_person/arms_view.gd"
const ARMS_FRAME_S: float = 1.0 / 60.0
# The kit's own anchor tolerance (`--check`'s `anchor`): 5 mm and 1 degree.
const ARMS_ANCHOR_M: float = 0.005
const ARMS_ANCHOR_DEG: float = 1.0


func _arms(scene: Node) -> bool:
	var world: Variant = scene.get("world")
	var player: int = int(world.player)
	var camera: Camera3D = scene.get("camera") as Camera3D
	_arms_clear_screens(scene)
	if bool(scene.get("third_person")):
		scene.call("toggle_view")
	# The clock is held so the many frames below change nothing the later lanes read; the equip
	# commands still run, one explicit tick each.
	var was_paused: bool = bool(scene.get("paused"))
	scene.set("paused", true)
	var ok_arms: bool = _arms_body(scene, world, player, camera)
	scene.set("paused", was_paused)
	return ok_arms


func _arms_body(scene: Node, world: Variant, player: int, camera: Camera3D) -> bool:
	var ok: bool = true
	_place_player(scene, _find_open_area((scene.get("map") as Variant), 2))
	scene.call("set_look", 0.0, 0.0)

	# The dead socket: the node under the Eye is arms_view.gd, the frame drives it, and the weapon is in it.
	var arms: Node3D = scene.call("arms_node") as Node3D
	if arms == null:
		return _fail("ARMS", "the scene has no arms view")
	if not _is_arms_view(arms):
		return _fail("ARMS", "the scene's view model is not %s" % ARMS_SCRIPT)
	if arms.get_parent() != camera or String(camera.name) != "Eye" or not arms.transform.is_equal_approx(Transform3D.IDENTITY):
		ok = _fail("ARMS", "the arms are not under the Eye with an identity transform")
	if not bool(arms.call("arms_loaded")):
		return _fail("ARMS", "arms_base.glb did not load: no skeleton, no AnimationPlayer or no grip_r bone")
	var held: Node3D = scene.call("held_weapon_node") as Node3D
	if held == null or not arms.is_ancestor_of(held.call("grip_node") as Node3D):
		ok = _fail("ARMS", "the held weapon's grip is not inside the arms the scene uses")
	if _is_arms_view(held):
		ok = _fail("ARMS", "the dead-socket test passed the held-weapon node, which is not the arms view")
	var updates: int = int(arms.call("updates"))
	scene.call("_process", ARMS_FRAME_S)
	if int(arms.call("updates")) <= updates:
		ok = _fail("ARMS", "the scene's frame does not update the arms")

	# Bare hands through the sim's own unequip: the unarmed class, up and idle, with nothing in hand.
	_arms_unequip_all(scene, world, player)
	_arms_settle(scene, 1.5)
	ok = _arms_shows(arms, "unarmed", "bare hands") and ok
	if bool(scene.call("held_weapon_visible")):
		ok = _fail("ARMS", "bare hands drew a weapon")
	if not (arms.call("arms_model") as Node3D).is_visible_in_tree():
		ok = _fail("ARMS", "the arms model is not drawn in first person")

	# Inspect is refused with bare hands: the unarmed class has no inspect clip.
	_key(KEY_L, true)
	_arms_settle(scene, 0.5)
	if String(arms.call("clip_playing")) != "idle_unarmed":
		ok = _fail("ARMS", "L with bare hands played '%s', not idle_unarmed" % String(arms.call("clip_playing")))
	_key(KEY_L, false)

	# The service pistol through item.equip: the old class lowers first, then the pistol is drawn.
	var pistol: int = _arms_equip(scene, world, player, "item.pistol.service")
	if pistol < 0:
		return _fail("ARMS", "the service pistol would not spawn, stow and equip through item.equip")
	if String(arms.call("clip_playing")) != "lower_unarmed":
		ok = _fail("ARMS", "equipping the pistol played '%s', not lower_unarmed first" % String(arms.call("clip_playing")))
	_arms_settle(scene, 1.5)
	ok = _arms_shows(arms, "pistol", "the service pistol") and ok
	ok = _arms_on_grip(scene, arms, camera, "pistol") and ok

	# Inspect: only while L is held. Four seconds without it never inspect; held, it inspects and goes
	# round past the clip's three seconds; one frame after the release it is idle again.
	for _i in 240:
		scene.call("_process", ARMS_FRAME_S)
		if String(arms.call("clip_playing")).begins_with("inspect_"):
			ok = _fail("ARMS", "the arms inspected with L up")
			break
	_key(KEY_L, true)
	scene.call("_process", ARMS_FRAME_S)
	if String(arms.call("clip_playing")) != "inspect_pistol":
		ok = _fail("ARMS", "L held played '%s', not inspect_pistol" % String(arms.call("clip_playing")))
	_arms_settle(scene, 3.5)
	if String(arms.call("clip_playing")) != "inspect_pistol":
		ok = _fail("ARMS", "with L still held past the clip's end the arms play '%s'" % String(arms.call("clip_playing")))
	_key(KEY_L, false)
	scene.call("_process", ARMS_FRAME_S)
	if String(arms.call("clip_playing")) != "idle_pistol":
		ok = _fail("ARMS", "a frame after L was let go the arms play '%s', not idle_pistol" % String(arms.call("clip_playing")))
	# L held when a screen opens is let go with the walking keys: no inspect after the screen closes.
	_key(KEY_L, true)
	scene.call("_process", ARMS_FRAME_S)
	_key(KEY_F1, true)
	_key(KEY_F1, false)
	_key(KEY_L, false)
	_key(KEY_F1, true)
	_key(KEY_F1, false)
	_arms_settle(scene, 1.5)
	if bool(scene.call("inspect_held")) or String(arms.call("clip_playing")).begins_with("inspect_"):
		ok = _fail("ARMS", "an L swallowed by the key reference left the arms inspecting")

	# Screens: the key reference and the sheet each lower the arms out of the frame and hide them; closing
	# brings them back up.
	_key(KEY_F1, true)
	_key(KEY_F1, false)
	scene.call("_process", ARMS_FRAME_S)
	if String(arms.call("clip_playing")) != "lower_pistol":
		ok = _fail("ARMS", "the key reference opened and the arms play '%s', not lower_pistol" % String(arms.call("clip_playing")))
	_arms_settle(scene, 0.5)
	if bool(arms.call("arms_shown")):
		ok = _fail("ARMS", "the arms are still drawn behind the key reference")
	_key(KEY_F1, true)
	_key(KEY_F1, false)
	_arms_settle(scene, 1.0)
	ok = _arms_shows(arms, "pistol", "the pistol after the key reference closed") and ok
	scene.call("open_inventory")
	_arms_settle(scene, 0.5)
	if bool(arms.call("arms_shown")):
		ok = _fail("ARMS", "the arms are still drawn behind the sheet")
	scene.call("close_inventory")
	_arms_settle(scene, 1.0)
	ok = _arms_shows(arms, "pistol", "the pistol after the sheet closed") and ok

	# Third person hides them at once; first person brings them back.
	_key(FirstPerson.VIEW_KEY, true)
	_key(FirstPerson.VIEW_KEY, false)
	scene.call("_process", ARMS_FRAME_S)
	if bool(arms.call("arms_shown")):
		ok = _fail("ARMS", "the arms are drawn in the third-person view")
	_key(FirstPerson.VIEW_KEY, true)
	_key(FirstPerson.VIEW_KEY, false)
	_arms_settle(scene, 1.0)
	ok = _arms_shows(arms, "pistol", "the pistol back in first person") and ok

	# No wall clipping: every surface in the view model, the pistol's parts included, draws through the
	# view model's lens; a plain mesh planted in the hand is refused by the same test.
	var judged: int = _collect_meshes_count(arms)
	if judged < 3:
		ok = _fail("ARMS", "the view model has %d meshes, not the arms and a weapon" % judged)
	var unlensed: Array = ArmsView.unlensed_meshes(arms)
	if not unlensed.is_empty():
		ok = _fail("ARMS", "%d view-model meshes draw with the world's lens and depth (%s)" % [unlensed.size(), String((unlensed[0] as Node).name)])
	var planted: MeshInstance3D = MeshInstance3D.new()
	planted.mesh = BoxMesh.new()
	planted.material_override = StandardMaterial3D.new()
	(arms.call("grip_r") as Node3D).add_child(planted)
	if not ArmsView.unlensed_meshes(arms).has(planted):
		ok = _fail("ARMS", "a plain mesh planted in the hand passed the lens test")
	planted.free()

	# A swap: pistol to bat. The pistol's copy lowers in the hand, then the bat is drawn two-handed.
	_arms_unequip_all(scene, world, player)
	var bat: int = _arms_equip(scene, world, player, "item.bat.wood")
	if bat < 0:
		return _fail("ARMS", "the bat would not spawn, stow and equip through item.equip")
	var lowering: Node = (arms.call("grip_r") as Node).find_child("Lowering", false, false)
	if not bool(arms.call("swapping")) or lowering == null or _collect_meshes_count(lowering) == 0:
		ok = _fail("ARMS", "a swap from the pistol did not lower a copy of the pistol in the hand")
	_arms_settle(scene, 1.5)
	ok = _arms_shows(arms, "melee2", "the bat") and ok
	if (arms.call("grip_r") as Node).find_child("Lowering", false, false) != null:
		ok = _fail("ARMS", "the lowered copy is still in the hand after the swap")
	ok = _arms_on_grip(scene, arms, camera, "melee2") and ok

	# The knife is one-handed and the hunting rifle long.
	_arms_unequip_all(scene, world, player)
	if _arms_equip(scene, world, player, "item.knife.kitchen") < 0:
		return _fail("ARMS", "the kitchen knife would not equip through item.equip")
	_arms_settle(scene, 1.5)
	ok = _arms_shows(arms, "melee1", "the kitchen knife") and ok
	_arms_unequip_all(scene, world, player)
	if _arms_equip(scene, world, player, "item.rifle.hunting") < 0:
		return _fail("ARMS", "the hunting rifle would not equip through item.equip")
	_arms_settle(scene, 1.5)
	ok = _arms_shows(arms, "long", "the hunting rifle") and ok

	# Back to bare hands for the lanes after this one.
	_arms_unequip_all(scene, world, player)
	_arms_settle(scene, 1.5)
	ok = _arms_shows(arms, "unarmed", "bare hands again") and ok
	ok = _arms_clip_order(arms) and ok
	return ok


# Review N1: a clip's pose must not depend on the clip before it. GLTFDocument drops every track equal to
# its bone's rest pose, so a bone a clip leaves at rest keeps the previous clip's pose unless the mixer is
# deterministic. Two clips that leave the index finger at different poses play to their end, then
# idle_pistol settles; the finger must read what it reads after a fresh load that plays idle_pistol first.
const ARMS_GLB_PATH: String = "res://assets/first_person/arms/arms_base.glb"
const CLIP_ORDER_BONES: Array = ["index_02.R", "index_03.R"]
const CLIP_ORDER_DEG: float = 0.5


func _arms_clip_order(arms: Node3D) -> bool:
	var player: AnimationPlayer = arms.get("_player") as AnimationPlayer
	var skeleton: Skeleton3D = arms.get("_skeleton") as Skeleton3D
	if player == null or skeleton == null:
		return _fail("ARMS", "the arms view has no AnimationPlayer or skeleton to read a clip order from")
	# The view's own clip and place are put back after the reads, so the lanes after this one see the same arms.
	var was_clip: String = player.current_animation
	var was_pos: float = player.current_animation_position
	var ok: bool = true
	var fresh: Node3D = Models.instance_of(ARMS_GLB_PATH)
	if fresh == null:
		return _fail("ARMS", "%s did not load for the fresh-load pose" % ARMS_GLB_PATH)
	arms.get_parent().add_child(fresh)
	var fresh_player: AnimationPlayer = _arms_first(fresh, "AnimationPlayer") as AnimationPlayer
	var fresh_skeleton: Skeleton3D = _arms_first(fresh, "Skeleton3D") as Skeleton3D
	fresh_player.deterministic = player.deterministic
	var reference: Dictionary = {}
	var after_melee: Dictionary = {}
	var after_unarmed: Dictionary = {}
	for bone in CLIP_ORDER_BONES:
		reference[bone] = _clip_pose(fresh_player, fresh_skeleton, ["idle_pistol"], String(bone))
		after_melee[bone] = _clip_pose(player, skeleton, ["idle_melee2", "idle_pistol"], String(bone))
		after_unarmed[bone] = _clip_pose(player, skeleton, ["idle_unarmed", "idle_pistol"], String(bone))
	arms.get_parent().remove_child(fresh)
	fresh.free()
	if not was_clip.is_empty():
		player.play(was_clip, 0.0)
		player.seek(was_pos, true)
	for bone in CLIP_ORDER_BONES:
		for seq_name in [["after idle_melee2", after_melee], ["after idle_unarmed", after_unarmed]]:
			var got: Quaternion = (seq_name[1] as Dictionary)[bone] as Quaternion
			var want: Quaternion = reference[bone] as Quaternion
			var deg: float = rad_to_deg(got.angle_to(want))
			if deg > CLIP_ORDER_DEG:
				ok = _fail("ARMS", "a clip's pose depends on the clip before it (%s differs by %.1f deg, %s against a fresh load)" % [bone, deg, String(seq_name[0])])
				return ok
	return ok


func _arms_first(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found: Node = _arms_first(child, type_name)
		if found != null:
			return found
	return null


# The pose of `bone` after the clips play in order: each clip but the last runs to its end, the last
# settles for half a second. Bone rotation as the skeleton holds it after the advance.
func _clip_pose(player: AnimationPlayer, skeleton: Skeleton3D, seq: Array, bone: String) -> Quaternion:
	for i in seq.size():
		var clip: String = String(seq[i])
		player.play(clip, 0.0)
		if i < seq.size() - 1:
			player.seek(player.get_animation(clip).length, true)
		else:
			player.seek(0.0, true)
			player.advance(0.5)
	var idx: int = skeleton.find_bone(bone)
	return skeleton.get_bone_pose_rotation(idx) if idx >= 0 else Quaternion.IDENTITY


func _is_arms_view(node: Node) -> bool:
	var script: Script = node.get_script() as Script if node != null else null
	return script != null and script.resource_path == ARMS_SCRIPT


# The arms are up and idle in `want`, and the sim agrees that is the class in hand.
# HANDS. The key bar is the strip along the bottom of the view (`Hud.help_rect`, the same rectangle
# the HUD draws). The bare hands are the arms' hand and finger bones, projected through the Eye at the
# view-model lens, each padded by a hand's radius. At 1280x720 and 960x720 the two rectangles must not
# meet. The plant is the detector: a bar placed on the hands must read as overlapping.
const HANDS_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(960, 720)]
const HAND_RADIUS_M: float = 0.05
const HAND_BONE_PREFIXES: Array[String] = ["hand.", "thumb_", "index_", "middle_", "ring_", "pinky_"]


func _hands(scene: Node) -> bool:
	var world: Variant = scene.get("world")
	var player: int = int(world.player)
	var camera: Camera3D = scene.get("camera") as Camera3D
	var arms: Node3D = scene.call("arms_node") as Node3D
	var hud: Control = scene.get("_hud") as Control
	if arms == null or camera == null or hud == null:
		return _fail("HANDS", "the scene has no arms, camera or HUD to measure")
	_place_player(scene, _find_open_area((scene.get("map") as Variant), 2))
	scene.call("set_look", 0.0, 0.0)
	_arms_unequip_all(scene, world, player)
	_arms_settle(scene, 1.5)
	if not _arms_shows(arms, "unarmed", "bare hands"):
		return false
	var ok: bool = true
	var report: Array[String] = []
	var hands_1280: Rect2 = Rect2()
	for size in HANDS_SIZES:
		root.size = size
		await process_frame
		await process_frame
		var view: Vector2 = Vector2(size)
		var hands: Rect2 = _hands_rect(arms, camera, view)
		var bar: Rect2 = Hud.help_rect(view)
		if hands.size == Vector2.ZERO:
			ok = _fail("HANDS", "no hand bone projects in front of the Eye at %dx%d" % [size.x, size.y]) and ok
			continue
		if hands.intersects(bar):
			ok = _fail("HANDS", "the bare hands at %dx%d (%s) reach the key bar (%s)" % [size.x, size.y, str(hands), str(bar)]) and ok
		report.append("%dx%d hands y %.0f..%.0f, key bar y %.0f..%.0f" % [size.x, size.y, hands.position.y, hands.end.y, bar.position.y, bar.end.y])
		if size == Vector2i(1280, 720):
			hands_1280 = hands
	if hands_1280.size == Vector2.ZERO:
		return false
	# The plant: a bar sitting on the hands must read as overlapping, or the test above proves nothing.
	var on_hands: Rect2 = Rect2(hands_1280.position, Hud.help_rect(Vector2(1280, 720)).size)
	if not on_hands.intersects(hands_1280):
		ok = _fail("HANDS", "a key bar placed on the hands does not read as overlapping them") and ok
	root.size = Vector2i(1280, 720)
	await process_frame
	if ok:
		print("HANDS OK " + "; ".join(report) + "; a bar placed on the hands reads as overlapping")
	return ok


# The hands' drawn rectangle on screen at `view`: every hand and finger bone projected through the
# camera, padded by HAND_RADIUS_M at its own depth, and the bounds of all of them. Empty when no
# hand bone is in front of the camera.
func _hands_rect(arms: Node3D, camera: Camera3D, view: Vector2) -> Rect2:
	var skeleton: Skeleton3D = arms.get("_skeleton") as Skeleton3D
	if skeleton == null:
		return Rect2()
	var focal: float = (view.y * 0.5) / tan(deg_to_rad(ArmsView.VIEW_MODEL_FOV_DEG) * 0.5)
	var lo: Vector2 = Vector2(INF, INF)
	var hi: Vector2 = Vector2(-INF, -INF)
	var any: bool = false
	var to_local: Transform3D = camera.global_transform.affine_inverse()
	for index in skeleton.get_bone_count():
		var bone: String = skeleton.get_bone_name(index)
		var is_hand: bool = false
		for prefix in HAND_BONE_PREFIXES:
			if bone.begins_with(prefix):
				is_hand = true
				break
		if not is_hand:
			continue
		var at: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(index).origin
		if camera.is_position_behind(at):
			continue
		var depth: float = maxf(-(to_local * at).z, 0.01)
		var pad: float = HAND_RADIUS_M * focal / depth
		var point: Vector2 = camera.unproject_position(at)
		lo = Vector2(minf(lo.x, point.x - pad), minf(lo.y, point.y - pad))
		hi = Vector2(maxf(hi.x, point.x + pad), maxf(hi.y, point.y + pad))
		any = true
	if not any:
		return Rect2()
	return Rect2(lo, hi - lo)


func _arms_shows(arms: Node3D, want: String, what: String) -> bool:
	var ok: bool = true
	if String(arms.call("shown_class")) != want:
		ok = _fail("ARMS", "%s shows the %s class, not %s" % [what, String(arms.call("shown_class")), want])
	if String(arms.call("clip_playing")) != "idle_" + want:
		ok = _fail("ARMS", "%s plays '%s', not idle_%s" % [what, String(arms.call("clip_playing")), want])
	if not bool(arms.call("arms_shown")):
		ok = _fail("ARMS", "%s: the arms are not drawn in first person with no screen up" % what)
	return ok


# The weapon's grip node is the child of the `grip_r` bone attachment, and at idle frame 0 the weapon is
# on the class's anchor in camera space; the same transform is refused against another class's anchor.
func _arms_on_grip(scene: Node, arms: Node3D, camera: Camera3D, hold_class: String) -> bool:
	var ok: bool = true
	var held: Node3D = scene.call("held_weapon_node") as Node3D
	var grip: Node3D = held.call("grip_node") as Node3D
	var parent: Node = grip.get_parent()
	if not (parent is BoneAttachment3D) or String(parent.name) != "grip_r" or String((parent as BoneAttachment3D).bone_name) != "grip_r":
		return _fail("ARMS", "the %s's grip node hangs under '%s', not the grip_r bone" % [hold_class, String(parent.name)])
	var weapon: Node3D = held.call("receiver_node") as Node3D
	if weapon == null or not weapon.is_visible_in_tree():
		return _fail("ARMS", "the %s has no drawn model in the hand" % hold_class)
	arms.set("sway_scale", 0.0)
	scene.call("_process", ARMS_FRAME_S)
	arms.call("pose_at", "idle_" + hold_class, 0.0)
	var at: Transform3D = camera.global_transform.affine_inverse() * weapon.global_transform
	var want: Transform3D = arms.call("anchor_of", hold_class) as Transform3D
	if not _arms_near(at, want):
		ok = _fail("ARMS", "the %s sits at %s, %.2f deg off, not on its anchor %s" % [hold_class, str(at.origin), rad_to_deg(_arms_angle(at.basis, want.basis)), str(want.origin)])
	var other: String = "melee2" if hold_class != "melee2" else "pistol"
	if _arms_near(at, arms.call("anchor_of", other) as Transform3D):
		ok = _fail("ARMS", "the %s also passed against the %s anchor" % [hold_class, other])
	arms.set("sway_scale", 1.0)
	return ok


func _arms_near(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) <= ARMS_ANCHOR_M and rad_to_deg(_arms_angle(a.basis, b.basis)) <= ARMS_ANCHOR_DEG


func _arms_angle(a: Basis, b: Basis) -> float:
	var q: Quaternion = (a.orthonormalized().inverse() * b.orthonormalized()).get_rotation_quaternion()
	return 2.0 * acos(clampf(absf(q.w), 0.0, 1.0))


func _arms_settle(scene: Node, seconds: float) -> void:
	for _i in int(ceil(seconds / ARMS_FRAME_S)):
		scene.call("_process", ARMS_FRAME_S)


func _arms_clear_screens(scene: Node) -> void:
	if bool(scene.get("menu_open")):
		scene.call("close_ledger_menu")
	if bool(scene.get("inventory_open")):
		scene.call("close_inventory")
	if bool(scene.get("talk_open")):
		scene.call("close_talk")
	if bool(scene.call("legend_open")):
		scene.call("close_legend")


# Spawns an item at the player's feet, picks it up through the sim's `item.pickup` command and equips
# it through `item.equip` (a pick-up that found no room in the bags has already put it in hand), then
# runs the one frame that sees it. -1 when any step is refused.
func _arms_equip(scene: Node, world: Variant, player: int, item_id: String) -> int:
	var item: int = int(SimItems.spawn_item(world, item_id, {"tier": "scavenged"}))
	if item < 0:
		return -1
	var at: Vector2 = _player_pos(world)
	world.components.set_component(item, "position", {"x": at.x, "y": at.y})
	world.commands.push({"type": "item.pickup", "item": item})
	scene.call("step_sim_once")
	if not SimInventory.owns(world, player, item):
		return -1
	if not SimInventory.equipped_items(world, player).has(item):
		world.commands.push({"type": "item.equip", "item": item})
		scene.call("step_sim_once")
	scene.call("_process", ARMS_FRAME_S)
	if not SimInventory.equipped_items(world, player).has(item):
		return -1
	return item


# Empties both hands through the sim's `item.unequip` command, and drops what came out of them with
# `item.drop`, so the bags have room for the next item.
func _arms_unequip_all(scene: Node, world: Variant, player: int) -> void:
	var eq: Variant = world.components.get_component(player, "equipment")
	var emptied: Array[int] = []
	if eq is Dictionary:
		var slots: Dictionary = (eq as Dictionary).get("slots", {}) as Dictionary
		for slot in ["primary", "secondary"]:
			if slots.get(slot) != null:
				emptied.append(int(slots[slot]))
				world.commands.push({"type": "item.unequip", "slot": slot, "item": int(slots[slot])})
	scene.call("step_sim_once")
	for item in emptied:
		world.commands.push({"type": "item.drop", "item": item})
	scene.call("step_sim_once")
	scene.call("_process", ARMS_FRAME_S)


func _collect_meshes_count(node: Node) -> int:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(node, meshes)
	return meshes.size()


# The key names a source file's code compares or names: KEY_ identifiers on lines that are not comments,
# and not in the KEY_REFERENCE table (the table is what is checked, so it is not evidence of handling).
func _handled_key_names(source: String) -> Array:
	var names: Array = []
	var in_table: bool = false
	var pattern: RegEx = RegEx.new()
	pattern.compile("KEY_[A-Z0-9_]+")
	for line in source.split("\n"):
		if line.begins_with("const KEY_REFERENCE"):
			in_table = true
			continue
		if in_table:
			if line == "]":
				in_table = false
			continue
		if line.strip_edges().begins_with("#"):
			continue
		for hit in pattern.search_all(line):
			var name: String = hit.get_string()
			if name == "KEY_REFERENCE" or names.has(name):
				continue
			names.append(name)
	return names


# The codes in `a` that `b` does not hold.
func _codes_missing(a: Array, b: Array) -> Array:
	var out: Array = []
	for code in a:
		if not b.has(int(code)):
			out.append(int(code))
	return out


# --- SPEED ----------------------------------------------------------------------------------

# The clock's keys are the top-down game's: "faster" (=) and "slower" (-) step the ladder 1x and 3x, P holds
# the world at zero. Over a fixed span of frames, 3x advances three times the ticks of 1x. A key that is not
# a speed key changes nothing, and the ledger refuses the speed keys, as main.gd refuses them under a sheet.
func _speed(scene: Node) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	if bool(scene.get("menu_open")):
		scene.call("close_ledger_menu")
	if bool(scene.get("paused")):
		_key(KEY_P, true)
	_place_player(scene, _find_open_area((scene.get("map") as Variant), 2))
	_key(KEY_MINUS, true)
	_key(KEY_MINUS, true)
	if int(scene.get("speed")) != 1:
		return _fail("SPEED", "the slower key did not settle the clock at 1x (speed %d)" % int(scene.get("speed")))

	# True positive: three times the ticks at 3x as at 1x, over the same frames.
	var at_1x: int = _frames_ticks(scene, world, 60)
	_key(KEY_EQUAL, true)
	if int(scene.get("speed")) != 3:
		return _fail("SPEED", "the faster key did not step the clock to 3x (speed %d)" % int(scene.get("speed")))
	var at_3x: int = _frames_ticks(scene, world, 60)
	if at_1x < 15:
		ok = _fail("SPEED", "1x advanced only %d ticks in 60 frames, so the ratio proves nothing" % at_1x)
	elif absi(at_3x - 3 * at_1x) > 2:
		ok = _fail("SPEED", "3x advanced %d ticks where 1x advanced %d: wanted about three times as many" % [at_3x, at_1x])

	# True positive: P holds the clock at zero, and the same key lets it run again.
	_key(KEY_P, true)
	if not bool(scene.get("paused")):
		ok = _fail("SPEED", "P did not pause the clock")
	if _frames_ticks(scene, world, 60) != 0:
		ok = _fail("SPEED", "the clock advanced while P held it")
	_key(KEY_P, true)

	# True negative: a key that is not a speed key changes nothing (Q is bound to nothing here).
	var before: int = int(scene.get("speed"))
	_key(KEY_Q, true)
	if int(scene.get("speed")) != before or bool(scene.get("paused")):
		ok = _fail("SPEED", "a key that is not a speed key changed the clock")

	# True negative: the ledger refuses the speed keys.
	scene.call("open_ledger_menu")
	_key(KEY_MINUS, true)
	var under_ledger: int = int(scene.get("speed"))
	scene.call("close_ledger_menu")
	if under_ledger != 3:
		ok = _fail("SPEED", "the slower key changed the clock while the ledger was open")

	# The HUD says the clock in words, with no digit.
	var words: String = _joined_hud(scene)
	if not words.contains("Time is normal speed") and not words.contains("Time is fast"):
		ok = _fail("SPEED", "the HUD does not say the clock in words")
	for line in scene.call("hud_lines") as Array:
		if _has_digit(String(line)):
			ok = _fail("SPEED", "the HUD draws a digit: %s" % String(line))

	_key(KEY_MINUS, true)
	return ok


# Frames of the scene's own frame function, each a 60th of a second; returns the sim ticks that ran.
func _frames_ticks(scene: Node, world: Variant, frames: int) -> int:
	var start: int = int(world.tick)
	for i in frames:
		scene.call("_process", 1.0 / 60.0)
	return int(world.tick) - start
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


# --- MODELS ----------------------------------------------------------------------------------------

# The model loader, judged on the committed weapon kit, and a loose item the sim drops drawn with its
# model. The manifest rule and the texture rule are also tested on fabricated input, so a rule that
# never fires cannot pass.
func _models(scene: Node) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var weapons: Array = []
	for manifest in Models.manifests():
		if String((manifest as Dictionary).get("kit", "")) == "weapons":
			weapons = (manifest as Dictionary)["models"] as Array
	if weapons.is_empty():
		return _fail("MODELS", "no weapons manifest was read from res://assets/first_person/")

	# True positive: every weapons entry loads, and its box is its sizeM within 1 cm on each axis. The
	# textures the kit's GLBs use are collected for the sharing and mipmap checks below.
	var textures: Dictionary = {}
	var loaded: int = 0
	for entry in weapons:
		var glb: String = String((entry as Dictionary)["glb"])
		var size: Array = (entry as Dictionary)["sizeM"] as Array
		var want: Vector3 = Vector3(float(size[0]), float(size[1]), float(size[2]))
		var instance: Node3D = Models.instance_of(glb)
		if instance == null:
			ok = _fail("MODELS", "%s does not load" % glb)
			continue
		loaded += 1
		var got: Vector3 = Models.bounds(instance).size
		if absf(got.x - want.x) > MODEL_TOLERANCE_M or absf(got.y - want.y) > MODEL_TOLERANCE_M or absf(got.z - want.z) > MODEL_TOLERANCE_M:
			ok = _fail("MODELS", "%s measures %s, its sizeM says %s" % [glb, str(got), str(want)])
		instance.free()
		var template: Node3D = Models.template_of(glb)
		for texture in _albedo_textures(template):
			textures[texture.get_instance_id()] = texture
		if _filter_of(template) != BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS:
			ok = _fail("MODELS", "%s does not sample with nearest-with-mipmaps" % glb)
	if loaded != weapons.size():
		ok = _fail("MODELS", "%d of %d weapon models loaded" % [loaded, weapons.size()])

	# Two GLBs embedding the same atlas share one texture, and the shared texture has mipmaps. Every GLB in
	# the kit embeds the atlas, so the count of distinct textures over the whole kit is one.
	if textures.size() != 1:
		ok = _fail("MODELS", "the weapon kit holds %d distinct textures, expected one shared atlas" % textures.size())
	else:
		var atlas: Texture2D = textures.values()[0] as Texture2D
		var a: Texture2D = _albedo_textures(Models.template_of("res://assets/first_person/weapons/pistol_service.glb"))[0]
		var b: Texture2D = _albedo_textures(Models.template_of("res://assets/first_person/weapons/pistol_barrel_standard.glb"))[0]
		if a.get_instance_id() != b.get_instance_id():
			ok = _fail("MODELS", "two GLBs embedding the same atlas do not share one texture")
		var image: Image = atlas.get_image()
		var levels: int = image.get_mipmap_count() if image != null else 0
		if levels < 2:
			ok = _fail("MODELS", "the shared atlas has %d mip level, not a chain" % levels)
		# True negatives for the sharing: a new copy of the atlas's pixels is handed back as the shared texture,
		# and a different image is not.
		var copy: ImageTexture = ImageTexture.create_from_image(atlas.get_image().duplicate() as Image)
		if Models._shared_texture(copy).get_instance_id() != atlas.get_instance_id():
			ok = _fail("MODELS", "a copy of the atlas's pixels was not shared with the atlas")
		var other: ImageTexture = ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
		if Models._shared_texture(other).get_instance_id() == atlas.get_instance_id():
			ok = _fail("MODELS", "a different image was shared with the atlas")

	# True positive and true negatives for the resolution rule. An id match beats a class match whatever the
	# order they are listed in; a class alone resolves; an unknown id and class resolve to null.
	var fabricated: Array = [{"kit": "fake", "models": [
		{"match": {"class": "weapon.melee"}, "glb": "class.glb"},
		{"match": {"id": "item.bat.wood"}, "glb": "id.glb"},
	]}]
	var by_id: Variant = Models.resolve_in(fabricated, "item.bat.wood", "weapon.melee")
	if not (by_id is Dictionary) or String((by_id as Dictionary)["glb"]) != "id.glb":
		ok = _fail("MODELS", "an id match did not beat a class match on the same item")
	var by_class: Variant = Models.resolve_in(fabricated, "item.knife.kitchen", "weapon.melee")
	if not (by_class is Dictionary) or String((by_class as Dictionary)["glb"]) != "class.glb":
		ok = _fail("MODELS", "a class match did not resolve an item with no id match")
	if Models.resolve_in(fabricated, "item.nothing.here", "nothing") != null:
		ok = _fail("MODELS", "an unknown id and class resolved to a model")
	if Models.resolve_in(fabricated, "", "") != null:
		ok = _fail("MODELS", "an empty id and class resolved to a model")
	var real_bat: Variant = Models.resolve("item.bat.wood", "weapon.melee")
	if not (real_bat is Dictionary) or not String((real_bat as Dictionary)["glb"]).ends_with("bat_wood.glb"):
		ok = _fail("MODELS", "the committed kit does not resolve item.bat.wood to bat_wood.glb")
	if Models.resolve("item.unknown.nothing", "") != null:
		ok = _fail("MODELS", "the committed kit resolved an unknown id to a model")

	# True positive: a loose bat the sim drops at the player's feet is drawn with its model, on the floor, at
	# the sim's position. The drop is the sim's own command, so the sim did the placing.
	var player: int = int(world.player)
	var bat: int = SimItems.spawn_item(world, "item.bat.wood")
	SimInventory.drop_at_feet(world, player, bat)
	scene.call("_process", TICK_SECONDS)
	var node: Node3D = scene.call("loose_node_for", bat) as Node3D
	if node == null:
		ok = _fail("MODELS", "a loose bat on the floor has no node in the loose-item view")
	else:
		var at: Vector2 = _entity_pos(world, bat)
		if absf(node.position.x - at.x) > EPSILON or absf(node.position.z - at.y) > EPSILON:
			ok = _fail("MODELS", "the loose bat is drawn at (%.3f, %.3f), not its sim position (%.3f, %.3f)" % [node.position.x, node.position.z, at.x, at.y])
		var box: AABB = _world_aabb(node)
		if absf(box.position.y) > MODEL_TOLERANCE_M:
			ok = _fail("MODELS", "the loose bat's lowest point is %.4f m, not on the floor" % box.position.y)
		var bat_size: Array = (real_bat as Dictionary)["sizeM"] as Array
		if absf(box.size.y - float(bat_size[1])) > MODEL_TOLERANCE_M:
			ok = _fail("MODELS", "the loose bat's drawn height %.4f m is not its model's %.4f m" % [box.size.y, float(bat_size[1])])
	# True negative: an item the merged manifests do not name is drawn with no node, so it keeps the
	# scene's placeholder. The item is found in the merged content, not assumed: the loot-item kit
	# draws canned food now, so a hard-coded id would stop being a no-model case.
	var modelless: String = ""
	for base_v in SimItems.content_entries(world, "item") as Array:
		var base: Dictionary = base_v as Dictionary
		var item_id: String = String(base.get("id", ""))
		if item_id != "" and Models.resolve(item_id, String(base.get("class", ""))) == null:
			modelless = item_id
			break
	if modelless == "":
		ok = _fail("MODELS", "every content item has a model, so the no-model negative has no case")
	else:
		var bare: int = SimItems.spawn_item(world, modelless)
		SimInventory.drop_at_feet(world, player, bare)
		scene.call("_process", TICK_SECONDS)
		if scene.call("loose_node_for", bare) != null:
			ok = _fail("MODELS", "an item with no model (%s) was drawn with a node" % modelless)
		world.despawn(bare)
		scene.call("_process", TICK_SECONDS)
	# True negative: a loose item that is gone has its node freed on the next refresh.
	var before: int = int(scene.call("loose_view_count"))
	world.despawn(bat)
	scene.call("_process", TICK_SECONDS)
	if scene.call("loose_node_for", bat) != null:
		ok = _fail("MODELS", "a despawned loose bat still has a node")
	if int(scene.call("loose_view_count")) != before - 1:
		ok = _fail("MODELS", "the loose-item count did not drop by the despawned bat")
	return ok


# Every albedo texture a template's materials carry, one per surface.
func _albedo_textures(root: Node3D) -> Array:
	var out: Array = []
	var nodes: Array[MeshInstance3D] = []
	_collect_meshes(root, nodes)
	for node in nodes:
		for s in node.mesh.get_surface_count():
			var mat: Material = node.mesh.surface_get_material(s)
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null:
				out.append((mat as BaseMaterial3D).albedo_texture)
	return out


# The texture filter of a template's first material.
func _filter_of(root: Node3D) -> int:
	var nodes: Array[MeshInstance3D] = []
	_collect_meshes(root, nodes)
	for node in nodes:
		for s in node.mesh.get_surface_count():
			var mat: Material = node.mesh.surface_get_material(s)
			if mat is BaseMaterial3D:
				return (mat as BaseMaterial3D).texture_filter
	return -1


# --- BODIES ----------------------------------------------------------------------------------------

# The character models in the body view: the clip the sim's state names, held at the sim's phase; the loop
# flags; the capsule fallback; and the unseen body. Each rule has its true positive and a true negative. The
# gate writes the components a death or a lunge would write (setup, as the other lanes do): the sim makes a
# corpse for a survivor only, through the private `_make_corpse`, so a zombie's death is set here.
func _character_bodies(scene: Node) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var map: Variant = scene.get("map")
	var bodies: Node3D = scene.get("_bodies") as Node3D
	if bodies == null:
		return _fail("BODIES", "the scene has no body view")
	var colonists: Array[int] = _other_colonists(world)
	if colonists.is_empty():
		return _fail("BODIES", "the boot has no colonist to draw")
	var colonist: int = colonists[0]
	var rng: Variant = world.rng.stream("shambler")

	if scene.call("body_node_for", world.player) != null:
		ok = _fail("BODIES", "the player has a body model")
	var colonist_node: Node3D = scene.call("body_node_for", colonist) as Node3D
	var colonist_player: AnimationPlayer = scene.call("body_player_for", colonist) as AnimationPlayer
	if colonist_node == null or colonist_player == null:
		return _fail("BODIES", "a colonist has no character model with an animation player")

	# A walking colonist plays walk, held at the sim's phase, and its model turns to the sim's facing.
	var posture_before: Variant = world.components.get_component(colonist, "posture")
	var velocity_before: Variant = world.components.get_component(colonist, "velocity")
	var facing_before: Variant = world.components.get_component(colonist, "facing")
	world.components.set_component(colonist, "posture", SimStances.make_posture(SimStances.Stance.Walk))
	world.components.set_component(colonist, "velocity", {"dx": 1.4, "dy": 0.0})
	world.components.set_component(colonist, "facing", {"radians": 0.0})
	bodies.call("end_tick", world)
	bodies.call("apply", world, 1.0)
	if AnimState.state_of(world, colonist) != "walk":
		ok = _fail("BODIES", "a walking colonist reads %s, not walk" % AnimState.state_of(world, colonist))
	if colonist_player.current_animation != "walk":
		ok = _fail("BODIES", "a walking colonist plays %s, not walk" % colonist_player.current_animation)
	var walk_length: float = colonist_player.get_animation("walk").length
	var want_walk: float = AnimState.phase_of(world, colonist, "walk") * walk_length
	if absf(colonist_player.current_animation_position - want_walk) > PHASE_EPSILON:
		ok = _fail("BODIES", "walk is at %.3f s, the sim's phase says %.3f s" % [colonist_player.current_animation_position, want_walk])
	var forward: Vector3 = Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, colonist_node.rotation.y)
	if forward.distance_to(Vector3(1.0, 0.0, 0.0)) > 0.001:
		ok = _fail("BODIES", "a model facing the sim's 0 rad looks along %s, not +x" % str(forward))
	world.components.set_component(colonist, "facing", {"radians": PI * 0.5})
	bodies.call("apply", world, 1.0)
	forward = Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, colonist_node.rotation.y)
	if forward.distance_to(Vector3(0.0, 0.0, 1.0)) > 0.001:
		ok = _fail("BODIES", "a model facing the sim's pi/2 rad looks along %s, not +z" % str(forward))
	_restore(world, colonist, "posture", posture_before)
	_restore(world, colonist, "velocity", velocity_before)
	_restore(world, colonist, "facing", facing_before)

	# A shambler in the middle of a lunge plays lunge, held at the sim's swipe phase. Spawned for the lane.
	var spot: Vector2 = _find_open_area(map, 2)
	if spot == Vector2(-1.0, -1.0):
		return _fail("BODIES", "the district has no open area for the body lane")
	var zed: int = int(SimRoster.spawn_zombie(world, spot.x, spot.y - 1.2, SimRoster.TYPE_SHAMBLER, rng))
	var zed_player: AnimationPlayer = null
	var sd: Dictionary = (world.components.get_component(zed, "shambler") as Dictionary).duplicate()
	sd["state"] = SimShambler.ShamblerState["Pursue"]
	sd["ticksToSwipe"] = SimShambler.SWIPE_FIRST_TICKS - 6
	world.components.set_component(zed, "shambler", sd)
	bodies.call("end_tick", world)
	bodies.call("apply", world, 1.0)
	zed_player = scene.call("body_player_for", zed) as AnimationPlayer
	if zed_player == null:
		ok = _fail("BODIES", "a spawned shambler has no character model")
	elif AnimState.state_of(world, zed) != "lunge":
		ok = _fail("BODIES", "a shambler in its armed swipe reads %s, not lunge" % AnimState.state_of(world, zed))
	elif zed_player.current_animation != "lunge":
		ok = _fail("BODIES", "a lunging shambler plays %s, not lunge" % zed_player.current_animation)
	else:
		var want_lunge: float = AnimState.phase_of(world, zed, "lunge") * zed_player.get_animation("lunge").length
		if absf(zed_player.current_animation_position - want_lunge) > PHASE_EPSILON:
			ok = _fail("BODIES", "lunge is at %.3f s, the sim's phase says %.3f s" % [zed_player.current_animation_position, want_lunge])

	# The lunging zombie is done with: removed before the hold runs, so it cannot reach a colonist in those ticks.
	world.despawn(zed)
	zed_player = null

	# A dead body plays death, and holds the last frame after many ticks. The corpse component is what the
	# sim's own death writes for a body that stays as a corpse.
	var dead: int = int(SimRoster.spawn_zombie(world, spot.x, spot.y + 0.8, SimRoster.TYPE_SHAMBLER, rng))
	world.components.set_component(dead, "corpse", {"sinceTick": int(world.tick)})
	bodies.call("end_tick", world)
	bodies.call("apply", world, 1.0)
	var dead_player: AnimationPlayer = scene.call("body_player_for", dead) as AnimationPlayer
	if dead_player == null:
		ok = _fail("BODIES", "a corpse has no character model")
	else:
		var death_length: float = dead_player.get_animation("death").length
		if dead_player.current_animation != "death":
			ok = _fail("BODIES", "a corpse plays %s, not death" % dead_player.current_animation)
		for i in 300:
			scene.call("_process", TICK_SECONDS)
		if dead_player.current_animation != "death":
			ok = _fail("BODIES", "a corpse stopped on %s after 300 ticks, not death" % dead_player.current_animation)
		if absf(dead_player.current_animation_position - death_length) > PHASE_EPSILON:
			ok = _fail("BODIES", "death is at %.3f s after 300 ticks, not held at its last frame %.3f s" % [dead_player.current_animation_position, death_length])

	# Loops loop and one-shots do not: the flags on the shared clips, and a one-shot seeked past its end stays
	# at its last frame rather than wrapping.
	for clip in ["idle", "walk", "crouch_idle"]:
		if colonist_player.get_animation(clip).loop_mode != Animation.LOOP_LINEAR:
			ok = _fail("BODIES", "the survivor's %s clip does not loop" % clip)
	if colonist_player.get_animation("death").loop_mode != Animation.LOOP_NONE:
		ok = _fail("BODIES", "the survivor's death clip loops")
	if zed_player != null:
		if zed_player.get_animation("shamble").loop_mode != Animation.LOOP_LINEAR:
			ok = _fail("BODIES", "the shambler's shamble clip does not loop")
		if zed_player.get_animation("lunge").loop_mode != Animation.LOOP_NONE:
			ok = _fail("BODIES", "the shambler's lunge clip loops")
		var lunge_end: float = zed_player.get_animation("lunge").length
		zed_player.seek(lunge_end, true)
		if absf(zed_player.current_animation_position - lunge_end) > PHASE_EPSILON:
			ok = _fail("BODIES", "a one-shot seeked to its end did not hold its last frame")

	# A body the sim cannot see is not drawn, and it is one that has a model to hide, so the negative judges
	# something. A lane with no such body says so.
	var hidden: int = _first_out_of_sight_body(world)
	if hidden < 0:
		_skips.append("BODIES: no body is out of the sim's sight in this district, so the unseen rule is not judged here")
	else:
		bodies.call("apply", world, 1.0)
		var hidden_node: Node3D = scene.call("body_node_for", hidden) as Node3D
		if hidden_node == null or scene.call("body_player_for", hidden) == null:
			ok = _fail("BODIES", "an unseen body has no character model to hide")
		elif hidden_node.visible:
			ok = _fail("BODIES", "a body the sim cannot see is drawn")

	# A missing model falls back to the capsule: the same body, with the GLBs pointed at files that are not
	# there, is a cylinder with no player.
	var fallback: Node3D = BodyView.new()
	fallback.survivor_glb = "res://assets/first_person/no_such_survivor.glb"
	fallback.shambler_glb = "res://assets/first_person/no_such_shambler.glb"
	scene.add_child(fallback)
	fallback.call("build")
	fallback.call("reset", world)
	var capsule: Node3D = fallback.call("node_for", colonist) as Node3D
	if not (capsule is MeshInstance3D) or not ((capsule as MeshInstance3D).mesh is CylinderMesh):
		ok = _fail("BODIES", "a missing model did not fall back to the capsule cylinder")
	if fallback.call("player_of", colonist) != null or int(fallback.call("model_count")) != 0:
		ok = _fail("BODIES", "a missing model still gave the body an animation player")
	fallback.queue_free()

	world.despawn(dead)
	scene.call("_process", TICK_SECONDS)
	return ok


# Puts a component back the way the lane found it: a value that was there is written back, and one that was
# not is removed.
func _restore(world: Variant, entity: int, component: String, before: Variant) -> void:
	if before == null:
		world.components.remove(entity, component)
	else:
		world.components.set_component(entity, component, before)


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


func _held_visibility(scene: Node) -> bool:
	var ok: bool = true
	# The ARMS lane leaves the colonist bare-handed. Arm again through the sim's own equip, hold the
	# clock while the arms settle (as the ARMS lane does), and unequip at the end so the later lanes
	# read the same colony they did before this lane ran. A pistol, not the bat: the bench opens on a
	# firearm with slots, and the bench is the one screen this lane opens through the sim.
	var world: Variant = scene.get("world")
	var player: int = int(world.player)
	var was_paused: bool = bool(scene.get("paused"))
	scene.set("paused", true)
	if _arms_equip(scene, world, player, "item.pistol.service") < 0:
		scene.set("paused", was_paused)
		return _fail("HIDE", "the pistol would not equip for the held-weapon lane")
	# Precondition: armed and visible with every screen closed.
	scene.set("inventory_open", false)
	scene.set("_reports_open", false)
	scene.set("talk_open", false)
	scene.set("third_person", false)
	scene.call("_update_render", 1.0)
	_arms_settle(scene, 1.5)
	if not bool(scene.call("held_weapon_drawn")):
		ok = _fail("HIDE", "precondition failed: held weapon not drawn with all screens closed")
	# bench: the sim's bench.open puts benchFocus on the held pistol; _sync_bench_panel shows the panel
	# while the sim holds the focus, and the panel closes itself when the focus goes.
	if not _hide_bench_open(scene, world, player):
		ok = _fail("HIDE", "bench.open did not open the held pistol for the held-weapon lane")
	_arms_settle(scene, 1.5)
	if bool(scene.call("held_weapon_drawn")):
		ok = _fail("HIDE", "held weapon visible while bench open")
	_hide_bench_close(scene, world, player)
	_arms_settle(scene, 1.5)
	if not bool(scene.call("held_weapon_drawn")):
		ok = _fail("HIDE", "held weapon stays hidden after bench closes")
	# inventory
	scene.set("inventory_open", true)
	_arms_settle(scene, 1.5)
	if bool(scene.call("held_weapon_drawn")):
		ok = _fail("HIDE", "held weapon visible while inventory open")
	scene.set("inventory_open", false)
	_arms_settle(scene, 1.5)
	if not bool(scene.call("held_weapon_drawn")):
		ok = _fail("HIDE", "held weapon stays hidden after inventory closes")
	# reports (ledger)
	scene.set("_reports_open", true)
	_arms_settle(scene, 1.5)
	if bool(scene.call("held_weapon_drawn")):
		ok = _fail("HIDE", "held weapon visible while reports open")
	scene.set("_reports_open", false)
	_arms_settle(scene, 1.5)
	if not bool(scene.call("held_weapon_drawn")):
		ok = _fail("HIDE", "held weapon stays hidden after reports closes")
	# talk
	scene.set("talk_open", true)
	_arms_settle(scene, 1.5)
	if bool(scene.call("held_weapon_drawn")):
		ok = _fail("HIDE", "held weapon visible while talk open")
	scene.set("talk_open", false)
	_arms_settle(scene, 1.5)
	if not bool(scene.call("held_weapon_drawn")):
		ok = _fail("HIDE", "held weapon stays hidden after talk closes")
	# third person
	scene.set("third_person", true)
	scene.call("_update_render", 1.0)
	_arms_settle(scene, 1.5)
	if bool(scene.call("held_weapon_drawn")):
		ok = _fail("HIDE", "held weapon visible in third person")
	scene.set("third_person", false)
	scene.call("_update_render", 1.0)
	_arms_settle(scene, 1.5)
	if not bool(scene.call("held_weapon_drawn")):
		ok = _fail("HIDE", "held weapon stays hidden after returning to first person")
	_arms_unequip_all(scene, world, player)
	scene.set("paused", was_paused)
	return ok


# The sim's own bench.open on the held firearm, one tick, the way E at a bench does it. Away from a
# bench it opens only a carried firearm with slots (SimGunsmith.field_work).
func _hide_bench_open(scene: Node, world: Variant, player: int) -> bool:
	var item: int = SimGunsmith.first_workpiece(world, player)
	if item < 0:
		return false
	world.commands.push({"type": "bench.open", "item": item})
	scene.call("step_sim_once")
	return SimGunsmith.focus_of(world, player) == item


func _hide_bench_close(scene: Node, world: Variant, player: int) -> void:
	world.commands.push({"type": "bench.close"})
	scene.call("step_sim_once")
	if SimGunsmith.focus_of(world, player) >= 0:
		push_error("HIDE: bench.close left the sim's bench focus in place")
