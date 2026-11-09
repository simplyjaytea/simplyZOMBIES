extends SceneTree
# The title first on a plain boot (docs/30, 2026-11-09), headless, through the real scenes. The default
# scene is first_person.tscn; a boot that is not skipped goes to the title (presentation/main.tscn)
# before any world, content or view is built in first person.
#
#   BOOT      a plain boot reaches the title, and the boot-to-title time is printed. At frame 1 and frame 8
#             after the title arrives: the title is the current scene, its state is TITLE, its shell is
#             visible, its rows are exactly new run and quit (no slot yet), no first-person node is in the
#             tree, the title's world tick does not move (the clock runs only while playing), and no first-person world was built (boot_count 0).
#   NEW_RUN   the title's new run changes to first person, which builds exactly one world (boot_count +1),
#             with title_seen true, and whose tick advances. No title is shown on the way.
#   BACK      a save, then Esc (return_to_title): the title's rows are new run, continue and quit; its
#             new run goes straight to play, with one more world built and no title on the way.
#   CONTINUE  the continue row loads the slot into first person (its tick is the saved tick), with no title
#             on the way and one more world built.
#   REFUSE    a slot that will not load keeps the title on screen and says the refusal sentence, and builds
#             nothing.
#   SKIP      with title_seen false, a scene whose skip_title is set plays at once (the gates' path): one
#             world built, title_seen still false, no title.
#
# The gate's save key is a throwaway, deleted at the end; the real first-person slot is never touched.
# Plant (by hand, then restore): comment out `if _redirect_to_title(): return` in first_person.gd `_ready`;
# BOOT then fails with "the plain boot did not reach the title".

const FP_SCENE: String = "res://presentation/first_person/first_person.tscn"
const MAIN_SCENE: String = "res://presentation/main.tscn"
const FP_SCRIPT: String = "res://presentation/first_person/first_person.gd"
const GATE_KEY: String = "first_person_title_gate.slot"
const TITLE_WAIT_FRAMES: int = 600
const SCENE_WAIT_FRAMES: int = 600
const TICK_WAIT_FRAMES: int = 30
const TIME_BUDGET_SECONDS: float = 120.0
const SMALL_DISTRICT_TILES: int = 64

const SaveSlot = preload("res://presentation/first_person/save_slot.gd")
const FirstPerson = preload("res://presentation/first_person/first_person.gd")
const MainScript = preload("res://presentation/main.gd")

var _failures: Array[String] = []
var _started_ms: int = 0
var _boot_ms: int = -1


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_started_ms = Time.get_ticks_msec()
	if GATE_KEY == SaveSlot.DEFAULT_KEY:
		_fail("SAVE", "the gate's save key is the real first-person slot")
		_finish(false)
		return
	var saved_key: String = SaveSlot.slot_key
	SaveSlot.slot_key = GATE_KEY
	SaveSlot.remove()
	SaveSlot.title_seen = false
	FirstPerson.boot_count = 0

	var ok: bool = true
	ok = await _lane_boot() and ok
	ok = await _lane_new_run() and ok
	ok = await _lane_back_and_continue() and ok
	ok = await _lane_refuse() and ok
	ok = await _lane_skip() and ok

	SaveSlot.remove()
	SaveSlot.slot_key = saved_key
	_finish(ok and _failures.is_empty())


func _finish(ok: bool) -> void:
	var seconds: float = float(Time.get_ticks_msec() - _started_ms) / 1000.0
	if seconds > TIME_BUDGET_SECONDS:
		_fail("TIME", "the gate took %.1f s, over its %.0f s budget" % [seconds, TIME_BUDGET_SECONDS])
		ok = false
	if ok and _failures.is_empty():
		print("FP_TITLE_OK plain boot to the title (boot-to-title %d ms, frames 1 and 8 checked, title tick unmoved, no first-person world built), new run to play, return from Esc to play, continue loads the slot, a refused slot stays on the title, and the skip path plays at once, in %.1f s" % [_boot_ms, seconds])
		quit(0)
		return
	for failure in _failures:
		push_error("FP_TITLE_FAIL " + failure)
	quit(1)


func _fail(lane: String, message: String) -> bool:
	_failures.append(lane + ": " + message)
	return false


func _ok(lane: String, message: String) -> void:
	print("TITLE %s OK %s" % [lane, message])


# --- helpers ---------------------------------------------------------------------------------------

func _current_path() -> String:
	if current_scene == null:
		return ""
	return current_scene.scene_file_path


# Wait until `path` is the current scene. Returns whether it arrived, and whether any polled frame showed
# the title on the way (`saw_title`), so a lane can prove there was no detour.
func _wait_for_scene(path: String, max_frames: int) -> Array:
	var saw_title: bool = false
	for i in max_frames:
		await process_frame
		var here: String = _current_path()
		if here == MAIN_SCENE and path != MAIN_SCENE:
			saw_title = true
		if here == path:
			return [true, saw_title]
	return [false, saw_title]


func _main() -> Node:
	return current_scene if _current_path() == MAIN_SCENE else null


func _first_person() -> Node:
	return current_scene if _current_path() == FP_SCENE else null


func _count_first_person_nodes(node: Node = null) -> int:
	if node == null:
		node = root
	var n: int = 0
	var script: Script = node.get_script()
	if script != null and script.resource_path == FP_SCRIPT:
		n += 1
	for child in node.get_children():
		n += _count_first_person_nodes(child)
	return n


func _shell_of(main: Node) -> Control:
	return main.get("_shell") as Control


func _rows_of(main: Node) -> Array:
	var shell: Control = _shell_of(main)
	if shell == null:
		return []
	var ids: Array = []
	for row in shell.get("_rows"):
		ids.append(String((row as Array)[0]))
	return ids


func _state_of(main: Node) -> int:
	var session: Variant = main.get("session")
	if session == null:
		return -1
	return int(session.get("state"))


func _world_tick(scene: Node) -> int:
	var world: Variant = scene.get("world")
	if world == null:
		return -1
	return int(world.get("tick"))


# --- lanes -----------------------------------------------------------------------------------------

func _lane_boot() -> bool:
	var ok: bool = true
	var started: int = Time.get_ticks_msec()
	# A plain boot: the default scene, not skipped, title_seen false.
	change_scene_to_file(FP_SCENE)
	var arrived: Array = await _wait_for_scene(MAIN_SCENE, TITLE_WAIT_FRAMES)
	if not bool(arrived[0]):
		return _fail("BOOT", "the plain boot did not reach the title (current scene %s)" % _current_path())
	_boot_ms = Time.get_ticks_msec() - started
	var main: Node = _main()
	var title_tick: int = -1
	for frame_label in [1, 8]:
		if frame_label == 8:
			for i in 7:
				await process_frame
		main = _main()
		if main == null:
			ok = _fail("BOOT", "the title is not the current scene at frame %d" % frame_label) and ok
			continue
		if _state_of(main) != 0:
			ok = _fail("BOOT", "the title's state is %d at frame %d, not TITLE (0)" % [_state_of(main), frame_label]) and ok
		var shell: Control = _shell_of(main)
		if shell == null or not shell.visible:
			ok = _fail("BOOT", "the shell is not visible at frame %d" % frame_label) and ok
		var rows: Array = _rows_of(main)
		if rows != ["new_run", "quit"]:
			ok = _fail("BOOT", "the rows at frame %d are %s, not new run and quit with no slot" % [frame_label, str(rows)]) and ok
		var fp_nodes: int = _count_first_person_nodes()
		if fp_nodes != 0:
			ok = _fail("BOOT", "%d first-person node(s) in the tree at frame %d" % [fp_nodes, frame_label]) and ok
		# The title's backdrop is the top-down boot world, at the boot tick (Clock.tick_at_time_of_day(DAY_BEGINS)),
		# and the clock runs only while playing: the tick must not move between frame 1 and frame 8.
		var tick: int = _world_tick(main)
		if frame_label == 1:
			title_tick = tick
		elif tick != title_tick:
			ok = _fail("BOOT", "the title's world tick moved from %d to %d; the clock must not run on the title" % [title_tick, tick]) and ok
		if int(FirstPerson.boot_count) != 0:
			ok = _fail("BOOT", "%d first-person world(s) built before the title, not 0" % int(FirstPerson.boot_count)) and ok
	if ok:
		_ok("BOOT", "title at frame 1 and frame 8: state TITLE, shell visible, rows %s, no first-person node, tick %d unmoved, 0 worlds built; boot-to-title %d ms" % [str(_rows_of(_main())), title_tick, _boot_ms])
	return ok


func _lane_new_run() -> bool:
	var main: Node = _main()
	if main == null:
		return _fail("NEW_RUN", "the title is not the current scene before the new run")
	var before: int = int(FirstPerson.boot_count)
	main.call("_on_shell_action", "new_run")
	var arrived: Array = await _wait_for_scene(FP_SCENE, SCENE_WAIT_FRAMES)
	if not bool(arrived[0]):
		return _fail("NEW_RUN", "the new run did not reach first person (current scene %s)" % _current_path())
	if bool(arrived[1]):
		return _fail("NEW_RUN", "the new run showed the title on the way to first person")
	var fp: Node = _first_person()
	if int(FirstPerson.boot_count) != before + 1:
		return _fail("NEW_RUN", "%d world(s) built by the new run, not 1" % (int(FirstPerson.boot_count) - before))
	if not SaveSlot.title_seen:
		return _fail("NEW_RUN", "title_seen is false after the title's new run")
	var tick0: int = _world_tick(fp)
	for i in TICK_WAIT_FRAMES:
		await process_frame
	var tick1: int = _world_tick(fp)
	if tick1 <= tick0:
		return _fail("NEW_RUN", "the world tick did not advance (%d, then %d)" % [tick0, tick1])
	_ok("NEW_RUN", "first person after one world built, title_seen true, tick %d to %d with no title on the way" % [tick0, tick1])
	return true


func _lane_back_and_continue() -> bool:
	var ok: bool = true
	var fp: Node = _first_person()
	if fp == null:
		return _fail("BACK", "first person is not the current scene before Esc")
	if not bool(fp.call("save_game")):
		return _fail("BACK", "the save did not write for the continue row")
	var saved_tick: int = _world_tick(fp)
	fp.call("return_to_title")
	var arrived: Array = await _wait_for_scene(MAIN_SCENE, SCENE_WAIT_FRAMES)
	if not bool(arrived[0]):
		return _fail("BACK", "Esc did not return to the title (current scene %s)" % _current_path())
	var main: Node = _main()
	if _rows_of(main) != ["new_run", "continue", "quit"]:
		ok = _fail("BACK", "the rows after a save are %s, not new run, continue and quit" % str(_rows_of(main))) and ok
	if not SaveSlot.title_seen:
		ok = _fail("BACK", "title_seen went false on the way back to the title") and ok
	# Esc's title, then its new run: play at once, one more world.
	var before: int = int(FirstPerson.boot_count)
	main.call("_on_shell_action", "new_run")
	arrived = await _wait_for_scene(FP_SCENE, SCENE_WAIT_FRAMES)
	if not bool(arrived[0]) or bool(arrived[1]):
		ok = _fail("BACK", "the new run after Esc did not go straight to play") and ok
	elif int(FirstPerson.boot_count) != before + 1:
		ok = _fail("BACK", "%d world(s) built by the new run after Esc, not 1" % (int(FirstPerson.boot_count) - before)) and ok
	else:
		_ok("BACK", "Esc returns to the title with rows new run, continue, quit; its new run plays at once, one world built")
	if not ok:
		return false

	# CONTINUE: save from this run, back to the title, the continue row loads that slot at boot.
	fp = _first_person()
	if not bool(fp.call("save_game")):
		return _fail("CONTINUE", "the save did not write before the continue")
	saved_tick = _world_tick(fp)
	fp.call("return_to_title")
	arrived = await _wait_for_scene(MAIN_SCENE, SCENE_WAIT_FRAMES)
	if not bool(arrived[0]):
		return _fail("CONTINUE", "Esc did not return to the title before the continue")
	main = _main()
	before = int(FirstPerson.boot_count)
	main.call("_on_shell_action", "continue")
	arrived = await _wait_for_scene(FP_SCENE, SCENE_WAIT_FRAMES)
	if not bool(arrived[0]) or bool(arrived[1]):
		return _fail("CONTINUE", "the continue did not go straight to first person (current scene %s)" % _current_path())
	if int(FirstPerson.boot_count) != before + 1:
		return _fail("CONTINUE", "%d world(s) built by the continue, not 1" % (int(FirstPerson.boot_count) - before))
	var loaded_tick: int = _world_tick(_first_person())
	if absi(loaded_tick - saved_tick) > 2:
		return _fail("CONTINUE", "the continue loaded tick %d, not the saved %d" % [loaded_tick, saved_tick])
	_ok("CONTINUE", "continue loads the slot into first person at its saved tick %d, one world built, no title on the way" % saved_tick)
	return true


func _lane_refuse() -> bool:
	var fp: Node = _first_person()
	if fp == null:
		return _fail("REFUSE", "first person is not the current scene before the refusal case")
	fp.call("return_to_title")
	var arrived: Array = await _wait_for_scene(MAIN_SCENE, SCENE_WAIT_FRAMES)
	if not bool(arrived[0]):
		return _fail("REFUSE", "Esc did not return to the title before the refusal case")
	var garbage: String = "not a save"
	if not SaveSlot.write(garbage):
		return _fail("REFUSE", "the garbage slot did not write")
	var main: Node = _main()
	if _rows_of(main) != ["new_run", "continue", "quit"]:
		return _fail("REFUSE", "the continue row is not offered for a slot that exists (rows %s)" % str(_rows_of(main)))
	var expected: String = MainScript.continue_refusal(garbage)
	if expected.is_empty():
		return _fail("REFUSE", "the garbage slot did not refuse (the gate's premise is wrong)")
	var before: int = int(FirstPerson.boot_count)
	main.call("_on_shell_action", "continue")
	for i in 3:
		await process_frame
	if _current_path() != MAIN_SCENE:
		return _fail("REFUSE", "a refused continue left the title (current scene %s)" % _current_path())
	var shell: Control = _shell_of(_main())
	var notice: String = String(shell.get("_notice")) if shell != null else ""
	if notice != expected:
		return _fail("REFUSE", "the refusal says \"%s\", not \"%s\"" % [notice, expected])
	if int(FirstPerson.boot_count) != before:
		return _fail("REFUSE", "a refused continue built a world")
	if SaveSlot.load_on_boot:
		return _fail("REFUSE", "a refused continue left load_on_boot set")
	_ok("REFUSE", "a refused slot keeps the title on screen and says \"%s\"; no world built" % expected)
	SaveSlot.remove()
	return true


func _lane_skip() -> bool:
	SaveSlot.title_seen = false
	var before: int = int(FirstPerson.boot_count)
	var packed: PackedScene = load(FP_SCENE) as PackedScene
	if packed == null:
		return _fail("SKIP", "could not load %s" % FP_SCENE)
	var node: Node = packed.instantiate()
	node.set("skip_title", true)
	node.set("district_tiles", SMALL_DISTRICT_TILES)
	var old: Node = current_scene
	root.add_child(node)
	current_scene = node
	if old != null:
		old.queue_free()
	var seen_title: bool = false
	for i in 8:
		await process_frame
		if _current_path() == MAIN_SCENE:
			seen_title = true
	if seen_title or _current_path() != FP_SCENE:
		return _fail("SKIP", "the skipped boot went to the title")
	if int(FirstPerson.boot_count) != before + 1:
		return _fail("SKIP", "%d world(s) built by the skipped boot, not 1" % (int(FirstPerson.boot_count) - before))
	if SaveSlot.title_seen:
		return _fail("SKIP", "the skipped boot set title_seen")
	if _world_tick(node) < 0:
		return _fail("SKIP", "the skipped boot has no world")
	_ok("SKIP", "skip_title plays at once: one world built, title_seen still false, no title")
	return true
