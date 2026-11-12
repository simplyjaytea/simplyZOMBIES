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
# that guards it must then fail; a planted run that stays green is a gate that cannot fail. `_planted(name)` is
# how a lane asks. A plant never touches a file.
#
#   npm run godot:check:fp_look
#   npm run godot:check:fp_look -- --plant=boot      (must end red)

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
# The scene the other lanes judge is the game's own: it has a world, a camera, a sky view holding the one
# WorldEnvironment and the sun, a district view and the HUD's words. Plant `boot`: the sky view is taken out
# of the tree before the lane looks, and the lane must miss it.
func _boot(scene: Node) -> void:
	if _planted("boot"):
		var doomed: Node = scene.call("sky_view") as Node
		if doomed != null and doomed.get_parent() != null:
			doomed.get_parent().remove_child(doomed)
			doomed.queue_free()
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
