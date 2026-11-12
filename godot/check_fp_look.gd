extends SceneTree
# The first-person look (docs/46). Pixels are judged by eye, from the look sheet (`npm run godot:shots:look`):
# fixed stations, fixed hours, before and after. This gate holds what a sheet cannot: that each mechanism of the
# look is in the scene the game really boots, and that it still answers to the sim. It reads nodes, meshes and
# materials, never pixels, so it runs headless.
#
# Each lane documents itself above its own function: what it asserts, and the plant that turns it red. The lanes
# run in the order of `_run`. A lane with nothing built to judge prints FP_LOOK_SKIP and its reason, and judges
# nothing: it never passes quietly, and the result line counts the skips.
#
# Plants: `-- --plant=<name>` breaks one thing on purpose after the boot, in the gate's own scene, and the lane
# that guards it must then fail with its own FP_LOOK_FAIL line; a planted run that stays green is a gate that
# cannot fail. `_planted(name)` is how a lane asks. A plant never touches a file. A name no lane asks for ends
# red on a PLANT line instead, which proves nothing about any lane: read the lane on the FAIL line.
#
# A stub lane is temporary. The piece that builds a mechanism replaces its stub in the same change; a stub
# still skipping beside a built mechanism is a defect.
#
#   npm run godot:check:fp_look
#   npm run godot:check:fp_look -- --plant=boot-sky      (must end red on a BOOT line)

const SCENE_PATH: String = "res://presentation/first_person/first_person.tscn"
# The gate walks a small district, as the first-person gate does; a lane that needs the shipped size boots its own.
const SMALL_DISTRICT_TILES: int = 64

var _fails: int = 0
var _skips: int = 0
var _plant: String = ""
var _plant_asked: bool = false
var _packed: PackedScene = null


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--plant="):
			_plant = a.substr(8)
	call_deferred("_run")


func _run() -> void:
	_packed = load(SCENE_PATH) as PackedScene
	if _packed == null:
		_fail("BOOT", "could not load %s" % SCENE_PATH)
		_finish()
		return
	var scene: Node = _boot_scene(SMALL_DISTRICT_TILES)
	await process_frame
	await process_frame
	# The lanes read a still scene: a plant may leave it unfit to run another frame, and a lane that needs one
	# calls the scene's `_process` itself, as the first-person gate does.
	scene.set_process(false)
	_boot(scene)
	_sky(scene)
	_air(scene)
	_valley(scene)
	_ground(scene)
	_green(scene)
	_structures(scene)
	_words(scene)
	scene.queue_free()
	await process_frame
	if _plant != "" and not _plant_asked:
		_fail("PLANT", "no lane asks for the plant '%s'" % _plant)
	_finish()


func _finish() -> void:
	print("FP_LOOK_RESULT gate %s: %d FAIL, %d SKIP" % ["green" if _fails == 0 else "red", _fails, _skips])
	quit(0 if _fails == 0 else 1)


# A first-person scene on a district of `tiles`, booted the way every first-person gate boots it.
func _boot_scene(tiles: int) -> Node:
	var scene: Node = _packed.instantiate()
	scene.set("district_tiles", tiles)
	scene.set("skip_title", true)
	root.add_child(scene)
	return scene


func _ok(lane: String, message: String) -> void:
	print("FP_LOOK_OK %s %s" % [lane, message])


func _fail(lane: String, message: String) -> void:
	_fails += 1
	push_error("FP_LOOK_FAIL %s %s" % [lane, message])


func _skip(lane: String, reason: String) -> void:
	_skips += 1
	print("FP_LOOK_SKIP %s %s" % [lane, reason])


# True when this run was asked to plant `plant_name`. The lane that guards it breaks the thing and judges as usual.
func _planted(plant_name: String) -> bool:
	if _plant == plant_name:
		_plant_asked = true
		return true
	return false


# --- BOOT ------------------------------------------------------------------------------------------
# The scene the other lanes judge is the game's own: it has a world, a camera, a sky view in the tree, exactly
# one WorldEnvironment and it holds an environment, a sun, a district view and the HUD's words. Each of the
# eight is one assertion with one plant that breaks it and nothing else:
#   boot-world, boot-camera, boot-sky, boot-two-environments, boot-no-environment, boot-sun, boot-district,
#   boot-words.
func _boot(scene: Node) -> void:
	_plant_boot(scene)
	if scene.get("world") == null:
		_fail("BOOT", "the scene has no world")
		return
	if scene.get("camera") == null:
		_fail("BOOT", "the scene has no camera")
		return
	var sky: Node = scene.call("sky_view") as Node
	if sky == null or not sky.is_inside_tree():
		_fail("BOOT", "the scene has no sky view in the tree")
		return
	var environments: Array[Node] = scene.find_children("*", "WorldEnvironment", true, false)
	if environments.size() != 1:
		_fail("BOOT", "the scene holds %d WorldEnvironment nodes, not one" % environments.size())
		return
	if (environments[0] as WorldEnvironment).environment == null:
		_fail("BOOT", "the WorldEnvironment has no environment")
		return
	if scene.find_children("*", "DirectionalLight3D", true, false).is_empty():
		_fail("BOOT", "the scene has no sun")
		return
	if scene.get_node_or_null("District") == null:
		_fail("BOOT", "the scene has no District view")
		return
	if scene.get_node_or_null("FirstPersonHUD/Words") == null:
		_fail("BOOT", "the scene has no FirstPersonHUD/Words")
		return
	_ok("BOOT", "the scene boots with a world, a camera, one environment, a sun, a district and the HUD's words")


# The BOOT lane's plants. Each takes one thing out of the gate's own scene (the scene no longer processes, so a
# half-taken-apart scene is never run) and leaves the other seven as they were.
func _plant_boot(scene: Node) -> void:
	if _planted("boot-world"):
		scene.set("world", null)
	if _planted("boot-camera"):
		scene.set("camera", null)
	if _planted("boot-sky"):
		var sky: Node = scene.call("sky_view") as Node
		if sky != null and sky.get_parent() != null:
			sky.get_parent().remove_child(sky)
			sky.queue_free()
	if _planted("boot-two-environments"):
		var second: WorldEnvironment = WorldEnvironment.new()
		second.name = "PlantedSecondWorld"
		scene.add_child(second)
	if _planted("boot-no-environment"):
		for found in scene.find_children("*", "WorldEnvironment", true, false):
			(found as WorldEnvironment).environment = null
	if _planted("boot-sun"):
		for found in scene.find_children("*", "DirectionalLight3D", true, false):
			found.get_parent().remove_child(found)
			found.queue_free()
	if _planted("boot-district"):
		var district: Node = scene.get_node_or_null("District")
		if district != null:
			scene.remove_child(district)
			district.queue_free()
	if _planted("boot-words"):
		var words: Node = scene.get_node_or_null("FirstPersonHUD/Words")
		if words != null:
			words.name = "PlantedAway"


# --- SKY -------------------------------------------------------------------------------------------
# The piece that builds the sky replaces this body with its assertions and names its plant here.
func _sky(_scene: Node) -> void:
	_skip("SKY", "the sky is not built yet")


# --- AIR -------------------------------------------------------------------------------------------
# The piece that builds the haze, the moving sun and its shadows replaces this body and names its plant here.
func _air(_scene: Node) -> void:
	_skip("AIR", "the air, the moving sun and its shadows are not built yet")


# --- VALLEY ----------------------------------------------------------------------------------------
# The piece that builds what stands beyond the district edge replaces this body and names its plant here.
func _valley(_scene: Node) -> void:
	_skip("VALLEY", "the valley beyond the district edge is not built yet")


# --- GROUND ----------------------------------------------------------------------------------------
# The piece that builds the ground's surfaces replaces this body and names its plant here.
func _ground(_scene: Node) -> void:
	_skip("GROUND", "the ground's surfaces are not built yet")


# --- GREEN -----------------------------------------------------------------------------------------
# The piece that builds trees, thickets and ground cover replaces this body and names its plant here.
func _green(_scene: Node) -> void:
	_skip("GREEN", "trees, thickets and ground cover are not built yet")


# --- STRUCTURES ------------------------------------------------------------------------------------
# The piece that dresses the walls, windows, doors and low cover no building owns replaces this body and names
# its plant here.
func _structures(_scene: Node) -> void:
	_skip("STRUCTURES", "walls, windows and low cover outside the kit buildings are not dressed yet")


# --- WORDS -----------------------------------------------------------------------------------------
# The piece that restyles the HUD's words replaces this body and names its plant here.
func _words(_scene: Node) -> void:
	_skip("WORDS", "the HUD's new dress is not built yet")
