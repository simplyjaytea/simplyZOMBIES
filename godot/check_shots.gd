extends SceneTree
# The gate for the screenshot review (`review/shots.gd`, `godot:shots`).
#
# The driver is a tool, not a test, so nothing else would notice it going stale: a scene whose
# setup stops producing its state, a renamed node the capture reads, a window size dropped. This
# gate runs the same `review/scenes.gd` functions the driver runs and asks the world what it made.
#
# Lanes, each with a true positive and a true negative:
#   NAMES     every scene and the two windows, by name -- a scene added to the driver has to be
#             added here too
#   UNKNOWN   a scene name nothing knows is refused by setup and by verify, not passed quietly
#   SETUP     each scene boots, is set up, and the world says it is that scene
#   NEGATIVE  a day street is not a night, is not a combat, is not the torch shot, is not the
#             stockpile being marked or the stockpile window, and has no sheet open; the night with no torch in hand is not the torch shot; the plain Colony
#             screen is not Mara picked, not a crowd and not scrolled: verify refuses a state that is not the one
#             named, so a before/after pair cannot compare two states
#   PIXELS    with a display, the day street and the combat scene each capture to a picture that is
#             not blank and is not the other picture; headless, it says SKIP and passes on nothing
#
# A lane with no data says so and skips; it never passes quietly.

const Scenes = preload("res://review/scenes.gd")

var _ok: bool = true
var _pixels_note: String = ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_names()
	await _unknown()
	await _setup()
	await _negative()
	await _pixels()
	if _ok:
		print("SHOTS_OK %d scenes boot, set up and verify at 1280x720 and 1920x1080; %s" % [Scenes.NAMES.size(), _pixels_note])
	quit(0 if _ok else 1)


func _names() -> void:
	if Scenes.NAMES != ["day_street", "interior", "night_lights", "combat", "inventory", "care", "skills", "colony", "viewing", "colony_picked", "colony_crowd", "colony_scrolled", "bench_drop", "bench", "bench_field", "context_menu", "night_torch",
			"stockpile_mark",
			"stockpile_rest",
			"stockpile_night",
			"colony_stockpile",
			"colony_stockpile_picked",
			"stockpile_window",
			"dusk_street",
			"raised_walls",
			"name_field"]:
		_fail("NAMES: the scene list is %s" % str(Scenes.NAMES))
	var sizes: Array[Vector2i] = Scenes.SIZES
	if not sizes.has(Vector2i(1280, 720)) or not sizes.has(Vector2i(1920, 1080)):
		_fail("NAMES: the capture sizes are %s, not both 1280x720 and 1920x1080" % str(sizes))


func _unknown() -> void:
	var main: Node = await Scenes.boot(self)
	if main == null:
		_fail("UNKNOWN: the main scene did not boot")
		return
	var setup_err: String = await Scenes.setup(self, main, "no_such_scene")
	if setup_err.is_empty():
		_fail("UNKNOWN: setup accepted a scene nothing names")
	if Scenes.verify(main, "no_such_scene").is_empty():
		_fail("UNKNOWN: verify passed a scene nothing names")
	await _discard(main)


func _setup() -> void:
	# At the smallest window the game ships at, not the headless default: the care scene clicks a
	# part on the figure, and the sheet has no room to draw one in a 64-pixel window.
	root.size = Vector2i(1280, 720)
	for scene in Scenes.NAMES:
		var main: Node = await Scenes.boot(self)
		if main == null:
			_fail("SETUP: %s: the main scene did not boot" % scene)
			continue
		var err: String = await Scenes.setup(self, main, scene)
		if err.is_empty():
			err = Scenes.verify(main, scene)
		if not err.is_empty():
			_fail("SETUP: %s: %s" % [scene, err])
		await _discard(main)


func _negative() -> void:
	var main: Node = await Scenes.boot(self)
	if main == null:
		_fail("NEGATIVE: the main scene did not boot")
		return
	var err: String = await Scenes.setup(self, main, "day_street")
	if not err.is_empty():
		_fail("NEGATIVE: day street did not set up: %s" % err)
	if not Scenes.verify(main, "day_street").is_empty():
		_fail("NEGATIVE: a day street does not verify as a day street")
	if Scenes.verify(main, "night_lights").is_empty():
		_fail("NEGATIVE: a day street verified as a night")
	if Scenes.verify(main, "combat").is_empty():
		_fail("NEGATIVE: a street with no zombie verified as a combat")
	if Scenes.verify(main, "inventory").is_empty():
		_fail("NEGATIVE: a street with no sheet open verified as the inventory")
	if Scenes.verify(main, "night_torch").is_empty():
		_fail("NEGATIVE: a day street verified as the torch at night")
	if Scenes.verify(main, "stockpile_mark").is_empty():
		_fail("NEGATIVE: a day street with the brush down verified as the stockpile being marked")
	if Scenes.verify(main, "stockpile_rest").is_empty():
		_fail("NEGATIVE: a day street outside the stockpile verified as standing in it")
	if Scenes.verify(main, "stockpile_window").is_empty():
		_fail("NEGATIVE: a day street with no window up verified as the stockpile window")
	await _discard(main)
	# The night with no torch in hand is not the torch shot: night_lights throws no beam.
	main = await Scenes.boot(self)
	if main == null:
		_fail("NEGATIVE: the main scene did not boot for the night")
		return
	err = await Scenes.setup(self, main, "night_lights")
	if not err.is_empty() or not Scenes.verify(main, "night_lights").is_empty():
		_fail("NEGATIVE: the night did not set up: %s" % err)
	if Scenes.verify(main, "night_torch").is_empty():
		_fail("NEGATIVE: the night with no torch in hand verified as the torch shot")
	if Scenes.verify(main, "stockpile_night").is_empty():
		_fail("NEGATIVE: the night with the whole annex in the zone verified as the zone's edge by the fire")
	await _discard(main)
	# The plain Colony screen, nobody picked and the boot's two colonists, is neither fuller shot.
	main = await Scenes.boot(self)
	if main == null:
		_fail("NEGATIVE: the main scene did not boot for the colony")
		return
	err = await Scenes.setup(self, main, "colony")
	if not err.is_empty() or not Scenes.verify(main, "colony").is_empty():
		_fail("NEGATIVE: the colony screen did not set up: %s" % err)
	if Scenes.verify(main, "colony_picked").is_empty():
		_fail("NEGATIVE: the colony with nobody picked verified as Mara picked")
	if Scenes.verify(main, "colony_crowd").is_empty():
		_fail("NEGATIVE: the boot's colony of two verified as a crowd")
	if Scenes.verify(main, "colony_scrolled").is_empty():
		_fail("NEGATIVE: the boot's colony of two verified as a scrolled roster")
	if Scenes.verify(main, "colony_stockpile").is_empty():
		_fail("NEGATIVE: the boot's stockpile verified as the stocked one")
	if Scenes.verify(main, "colony_stockpile_picked").is_empty():
		_fail("NEGATIVE: the colony with nobody picked verified as the stockpile shown for Mara")
	await _discard(main)


func _pixels() -> void:
	if DisplayServer.get_name() == "headless":
		_pixels_note = "PIXELS SKIP no display, so no picture was taken (run with DISPLAY or xvfb-run)"
		print(_pixels_note)
		return
	var day: Image = await _capture("day_street", Vector2i(1280, 720))
	var combat: Image = await _capture("combat", Vector2i(1280, 720))
	if day == null or combat == null:
		_fail("PIXELS: a scene did not capture")
		return
	if day.get_size() != Vector2i(1280, 720) or combat.get_size() != Vector2i(1280, 720):
		_fail("PIXELS: a capture is %s, not the 1280x720 window" % str(day.get_size()))
	if _distinct(day) < 16:
		_fail("PIXELS: the day street is a blank picture")
	if day.get_data() == combat.get_data():
		_fail("PIXELS: the day street and the combat scene captured the same picture")
	_pixels_note = "PIXELS OK the day street and the combat scene are two pictures, neither blank"


func _capture(scene: String, size: Vector2i) -> Image:
	root.size = size
	await process_frame
	var main: Node = await Scenes.boot(self)
	if main == null:
		return null
	var err: String = await Scenes.setup(self, main, scene)
	if err.is_empty():
		err = Scenes.verify(main, scene)
	if not err.is_empty():
		_fail("PIXELS: %s: %s" % [scene, err])
		await _discard(main)
		return null
	await process_frame
	var image: Image = root.get_texture().get_image()
	await _discard(main)
	return image


# Colours in a sample of the picture, every sixteenth pixel each way: enough to tell a drawn
# scene from a flat fill without reading all two million pixels.
func _distinct(image: Image) -> int:
	var seen: Dictionary = {}
	var size: Vector2i = image.get_size()
	for y in range(0, size.y, 16):
		for x in range(0, size.x, 16):
			seen[image.get_pixel(x, y).to_html(false)] = true
	return seen.size()


func _discard(main: Node) -> void:
	main.queue_free()
	await process_frame


func _fail(message: String) -> void:
	push_error("SHOTS %s" % message)
	_ok = false
