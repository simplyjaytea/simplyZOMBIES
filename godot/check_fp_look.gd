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
# The words on the screen (docs/46, "Words on the screen"), read from the HUD's own `marks()`, the one list its
# draw paints, on the scene the gate booted:
#   COVERED  the words show in plain play, are hidden while the key reference is up and while the ledger is open,
#            and come back when each is put away.
#   SCANNED  everything painted is a sentence, a keycap or a wash; every painted word and keycap is in a line of
#            `lines()` (what the digit gates scan), and none carries a digit; `lines()` still carries the help
#            line and the prompt whole.
#   PLACED   the state sentences stand at the left margin in the lower half; a harm line (a grab planted on the
#            gate's own world) is in rust and the rest in bone; the prompt stands under the centre and over the
#            hands' rest, in amber, its key on a keycap.
#   FADES    on the HUD's wall clock: a sentence that only says all is well is at full strength when new and at
#            its rest afterwards, weaker and never gone; harm stays at full strength; a sentence that changes
#            arrives again at full strength while the others stay at rest.
#   KEYS     the key strip is painted in exactly `help_rect`, says nothing the help line does not, leaves once
#            the pointer has been in the look for a while, and comes back when the pointer is free.
# Plant `words`: the scene forgets that the key reference is up, so the words are painted under it, and COVERED
# must say so. Plant `words_still`: the HUD is given no wall clock (its ticks are thrown away), so nothing
# recedes and nothing leaves, and FADES and KEYS must say so.
func _words(scene: Node) -> void:
	var hud: Control = scene.get_node_or_null("FirstPersonHUD/Words") as Control
	if hud == null or not hud.has_method("marks") or not hud.has_method("tick_wall"):
		_fail("WORDS", "the scene's HUD has no marks to read")
		return
	var konst: GDScript = hud.get_script() as GDScript
	var world: Variant = scene.get("world")
	var player: int = int(world.player)
	var view: Vector2 = Vector2(1280.0, 720.0)
	var still: bool = _planted("words_still")
	var faults: Array[String] = []

	# COVERED.
	scene.call("_update_hud")
	if not hud.visible:
		faults.append("COVERED: the words are not shown in plain play")
	scene.call("open_legend")
	if _planted("words"):
		scene.set("_legend_open", false)
	scene.call("_update_hud")
	var legend: Control = scene.call("legend_node") as Control
	if legend == null or not legend.visible:
		faults.append("COVERED: the key reference did not come up, so nothing was judged under it")
	elif hud.visible:
		faults.append("COVERED: the words are painted under the key reference")
	scene.call("close_legend")
	scene.call("_update_hud")
	if not hud.visible:
		faults.append("COVERED: the words did not come back when the key reference was put away")
	scene.call("open_ledger_menu")
	scene.call("_update_hud")
	if not bool(scene.get("menu_open")):
		faults.append("COVERED: the ledger did not open, so nothing was judged under it")
	elif hud.visible:
		faults.append("COVERED: the words are painted under the open ledger")
	scene.call("close_ledger_menu")
	scene.call("_update_hud")
	if not hud.visible:
		faults.append("COVERED: the words did not come back when the ledger was shut")

	# The rest drives the HUD itself, between two of the scene's frames: a grab on the gate's own world for a
	# harm line, a prompt with a key, the pointer in the look, the clock running.
	var prompt: String = "E read the ledger"
	var held_line: String = String(konst.get("HELD_LINE"))
	var help: String = String(konst.get("HELP"))
	var had_grab: bool = world.components.has_component(player, "grabbed")
	if not had_grab:
		world.components.set_component(player, "grabbed", {"sources": [-1]})
	hud.set("time_words", "normal speed")
	hud.set("pointer_free", false)
	hud.call("set_state", world, player, prompt, "", false, false)
	_words_tick(hud, float(konst.get("ARRIVE_S")), false)
	var fresh: Array = hud.call("marks", view) as Array
	var said: Array = hud.call("lines") as Array

	# SCANNED.
	var joined: String = "\n".join(PackedStringArray(said))
	if not said.has(help) or not said.has(prompt):
		faults.append("SCANNED: lines() no longer carries the help line and the prompt whole")
	var painted_lines: int = 0
	for mark_v in fresh:
		var mark: Dictionary = mark_v as Dictionary
		var what: String = String(mark.get("what", ""))
		if what != "line" and what != "keycap" and what != "wash":
			faults.append("SCANNED: the HUD paints a '%s', which is neither a sentence, a keycap nor a wash" % what)
			continue
		if what == "wash":
			continue
		painted_lines += 1
		var text: String = String(mark["text"])
		if not joined.contains(text):
			faults.append("SCANNED: '%s' is painted and is in no line of lines()" % text)
		if bool(hud.call("has_digit", text)):
			faults.append("SCANNED: '%s' is painted with a digit" % text)
	if painted_lines == 0:
		faults.append("SCANNED: the HUD paints no word at all")
	if joined.contains("zz not a line zz") or not bool(hud.call("has_digit", "day 4")):
		faults.append("SCANNED: the reader cannot say no")

	# PLACED.
	var harm: Dictionary = _words_find(fresh, "line", held_line)
	var steady: Dictionary = _words_find(fresh, "line", "Time is normal speed.")
	if harm.is_empty() or steady.is_empty():
		faults.append("PLACED: the grab's sentence or the clock's sentence is not painted")
	else:
		if (harm["ink"] as Color) != (konst.get("INK_HARM") as Color):
			faults.append("PLACED: the harm line is not in rust")
		if (steady["ink"] as Color) != (konst.get("INK") as Color) or (steady["ink"] as Color) == (harm["ink"] as Color):
			faults.append("PLACED: a sentence that is not harm is not in bone, or bone and rust are one ink")
		for row in [harm, steady]:
			var at: Vector2 = (row as Dictionary)["at"] as Vector2
			if at.x != float(konst.get("MARGIN")) or at.y <= view.y * 0.5 or at.y >= view.y:
				faults.append("PLACED: '%s' stands at %s, not at the left margin in the lower half" % [String((row as Dictionary)["text"]), str(at)])
	var cap: Dictionary = _words_find(fresh, "keycap", "E", "prompt")
	var rest: Dictionary = _words_find(fresh, "line", "read the ledger")
	if cap.is_empty() or rest.is_empty():
		faults.append("PLACED: the prompt is not painted as a keycap and its words")
	else:
		var cap_at: Vector2 = cap["at"] as Vector2
		var rest_at: Vector2 = rest["at"] as Vector2
		if (rest["ink"] as Color) != (konst.get("INK_PROMPT") as Color):
			faults.append("PLACED: the prompt is not in amber")
		if cap_at.x >= view.x * 0.5 or rest_at.x <= cap_at.x or rest_at.x >= view.x * 0.75:
			faults.append("PLACED: the prompt does not straddle the middle of the view (keycap at %s, words at %s)" % [str(cap_at), str(rest_at)])
		# The hands rest from 0.78 of the view's height down (the first-person gate's HANDS lane).
		if cap_at.y <= view.y * 0.5 or rest_at.y >= view.y * 0.75:
			faults.append("PLACED: the prompt is not under the centre and over the hands (keycap top %.0f, baseline %.0f)" % [cap_at.y, rest_at.y])

	# FADES.
	var rest_steady: float = float(konst.get("REST_STEADY"))
	var fresh_alpha: float = float(steady.get("alpha", -1.0))
	_words_tick(hud, float(konst.get("FRESH_S")) + float(konst.get("RECEDE_S")) + 1.0, still)
	var rested: Array = hud.call("marks", view) as Array
	var steady_rested: float = float(_words_find(rested, "line", "Time is normal speed.").get("alpha", -1.0))
	var harm_rested: float = float(_words_find(rested, "line", held_line).get("alpha", -1.0))
	if fresh_alpha != 1.0:
		faults.append("FADES: a new sentence stands at %.2f, not at full strength" % fresh_alpha)
	if steady_rested <= 0.0 or steady_rested >= 1.0 or not is_equal_approx(steady_rested, rest_steady):
		faults.append("FADES: a steady sentence stands at %.2f after its time, not at its rest (%.2f): weaker, never gone" % [steady_rested, rest_steady])
	if harm_rested != 1.0:
		faults.append("FADES: the harm line stands at %.2f after the same time, not at full strength" % harm_rested)
	hud.set("time_words", "fast")
	hud.call("set_state", world, player, prompt, "", false, false)
	var arriving: float = float(_words_find(hud.call("marks", view) as Array, "line", "Time is fast.").get("alpha", -1.0))
	_words_tick(hud, float(konst.get("ARRIVE_S")), still)
	var arrived: Array = hud.call("marks", view) as Array
	var changed_alpha: float = float(_words_find(arrived, "line", "Time is fast.").get("alpha", -1.0))
	var other_alpha: float = float(_words_find(arrived, "line", "You are walking.").get("alpha", -1.0))
	if _words_find(arrived, "line", "You are walking.").is_empty():
		faults.append("FADES: the posture sentence is not painted, so nothing was judged beside the new one")
	elif arriving >= 1.0 or changed_alpha != 1.0 or not is_equal_approx(other_alpha, rest_steady):
		faults.append("FADES: a changed sentence does not arrive (%.2f, then %.2f) while the one beside it stays at rest (%.2f)" % [arriving, changed_alpha, other_alpha])

	# KEYS.
	var strip: Array = konst.get("KEY_STRIP") as Array
	for pair in strip:
		if not help.contains(String((pair as Array)[0])) or not help.contains(String((pair as Array)[1])):
			faults.append("KEYS: the strip says '%s %s', which the help line does not" % [String((pair as Array)[0]), String((pair as Array)[1])])
	var bar: Rect2 = hud.call("help_rect", view) as Rect2
	var laid: Rect2 = _words_strip_rect(hud, fresh)
	if _words_count(fresh, "keycap", "key") != strip.size():
		faults.append("KEYS: %d keycaps are painted in the strip when it is called for, not %d" % [_words_count(fresh, "keycap", "key"), strip.size()])
	elif not laid.is_equal_approx(bar):
		faults.append("KEYS: the strip is laid out in %s and help_rect says %s" % [str(laid), str(bar)])
	_words_tick(hud, float(konst.get("KEYS_SHOW_S")) + float(konst.get("KEYS_FADE_S")) + 1.0, still)
	var walked: Array = hud.call("marks", view) as Array
	if float(konst.get("KEYS_REST_ALPHA")) == 0.0 and _words_count(walked, "keycap", "key") != 0:
		faults.append("KEYS: the strip is still painted long after the pointer went into the look")
	hud.set("pointer_free", true)
	hud.call("set_state", world, player, prompt, "", false, false)
	var freed: Array = hud.call("marks", view) as Array
	if _words_count(freed, "keycap", "key") != strip.size() or float(_words_find(freed, "keycap", String((strip[0] as Array)[0]), "key").get("alpha", 0.0)) != 1.0:
		faults.append("KEYS: the strip does not come back at full strength when the pointer is free")

	# The gate's own fixture goes back, and the scene's next frame re-reads the sim.
	if not had_grab:
		world.components.remove_component(player, "grabbed")
	scene.call("_update_hud")
	if not faults.is_empty():
		for fault in faults:
			_fail("WORDS", fault)
		return
	_ok("WORDS", "the words hide under the key reference and the ledger and come back; %d painted marks are all in lines() and digit-free; harm in rust, the rest in bone, at the left margin low; the prompt in amber under the centre on a keycap; a steady sentence rests at %.2f, harm stays full, a changed one arrives; the key strip is help_rect, leaves and comes back" % [fresh.size(), steady_rested])


# Lets `seconds` of wall clock pass on the HUD. The `words_still` plant throws the time away: a HUD whose clock
# does not run.
func _words_tick(hud: Control, seconds: float, still: bool) -> void:
	hud.call("tick_wall", 0.0 if still else seconds)


# The first mark of `what` whose text is `text` (and whose kind is `kind`, when one is asked for); {} when none.
func _words_find(marks: Array, what: String, text: String, kind: String = "") -> Dictionary:
	for mark_v in marks:
		var mark: Dictionary = mark_v as Dictionary
		if String(mark.get("what", "")) == what and String(mark.get("text", "")) == text and (kind == "" or str(mark.get("kind", "")) == kind):
			return mark
	return {}


func _words_count(marks: Array, what: String, kind: String) -> int:
	var n: int = 0
	for mark_v in marks:
		var mark: Dictionary = mark_v as Dictionary
		if String(mark.get("what", "")) == what and str(mark.get("kind", "")) == kind:
			n += 1
	return n


# The rectangle the strip's marks cover: every strip keycap's box and every strip word's cell, by the HUD's own
# measures.
func _words_strip_rect(hud: Control, marks: Array) -> Rect2:
	var font: Font = (load("res://ui/chrome.gd") as GDScript).call("font") as Font
	var out: Rect2 = Rect2()
	for mark_v in marks:
		var mark: Dictionary = mark_v as Dictionary
		if str(mark.get("kind", "")) != "key":
			continue
		var at: Vector2 = mark["at"] as Vector2
		var text: String = String(mark["text"])
		var box: Rect2
		if String(mark["what"]) == "keycap":
			box = Rect2(at, Vector2(float(hud.call("_keycap_w", font, text)), float(hud.call("_keycap_h"))))
		else:
			box = Rect2(Vector2(at.x, at.y - float(hud.call("_keycap_base"))), Vector2(float(hud.call("_text_w", font, text)), float(hud.call("_keycap_h"))))
		out = box if not out.has_area() else out.merge(box)
	return out
