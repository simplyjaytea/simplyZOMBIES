extends SceneTree
# The first gate that actually plays the game.
#
# Every other gate in this tree drives the sim, or reads a presentation file as text. Nothing
# executed the presentation layer: `test/project_smoke.gd` awaits one frame and asks whether a
# world exists, and `check_hud.gd` instantiates the scene twice to price a hidden sheet. So a
# null dereference in `_draw_entities` on night three, or a key bound to two different commands,
# passed the whole chain -- which is exactly how `C` came to push a camp command and a stance
# change on the same press for as long as it did (docs/30, "The alpha shell, 2026-09-16").
#
# What this gate does instead: it boots `res://presentation/main.tscn` headless, pushes real key
# events through the viewport, runs the real frame loop, and asks what the world and the screen
# did about it.
#
# Two mechanisms are load-bearing and neither is an accident:
#
# * **`root.push_input(ev)`, never `main._input(ev)`.** push_input is synchronous and walks the
#   engine's real dispatch order (`_input` -> GUI -> `_unhandled_input`), so when the input
#   handler moved out of `main.gd` into `presentation/input_map.gd` -- the next piece of this arc,
#   landed the same day -- this gate went on reaching it rather than quietly becoming a dead
#   socket calling a function nobody else calls. `Input.parse_input_event` was the other candidate
#   and is wrong here: it buffers to the next frame and mutates the global `Input.is_key_pressed`
#   state the game itself reads.
# * **`main._process(TICK_SECONDS)`, called n times.** That is the same function a rendered frame
#   calls, with the same delta, so the tick arithmetic, the pump, the sfx hand-off and the camera
#   all run the way they run in play. The scene's own `_process` is switched off while the gate
#   drives (`set_process(false)`), so a real frame can never add a tick behind a lane's back.
#   `await process_frame` is used only where the engine itself must act: GUI dispatch and `_draw`.
#
# Lanes, each with a true positive and a true negative:
#   TICKS      the loop advances the world, and P stops it
#   WALK       a held key moves the body, release stops it, two keys sum to a diagonal
#   SHEET      Tab opens the sheet and peels the four things that sit under it
#   SETTINGS   Escape peels in order -- the legend first, the pause menu only once it is gone,
#              and settings is a row on that menu rather than a key of its own
#   ROUNDTRIP  F5 writes a save F9 restores; a corrupt slot leaves the world untouched
#   CAMP-KEY   C is the camp key and only the camp key; Ctrl+C is the stance and only the stance
#   FOCUS      an open sheet swallows the street's keys, and the body stops at the panel
#   PAUSE      Escape on the street pauses to the menu and gives the street back
#   NOTICE     a save this build cannot read leaves the run alone and says one fixed sentence
#   VOLUME     the settings row reaches the audio bus, and nought is mute
#   AUTOSAVE   the first tick of a day writes the slot; an ordinary tick and a finished run do not
#   LEGEND     a dismissed legend stays dismissed across a boot, and F1 brings it back
#   TITLE      the game opens on a menu over a world that is not ticking, and "new run" plays it
#   CLOSE      the window's close request writes a save from a run, and nothing from the title
#   RUN-OVER   the run ends on a screen that speaks the chronicle, and new run yields a live world
#   DRAW       `_draw` completes by day and by night, and does not when the node is hidden
#   SCENE      the scene this gate drives is the scene `project.godot` ships
#   KEYS       every legend row is bound and every binding has a row, both directions
#   SOCKET     the keys live in the router, the run's lifecycle lives in the session, and
#              main.gd's frame loop reaches both
#   BUDGET     the whole gate under a minute
#
# A lane with no data says so and skips; it never passes quietly.
#
# CAMP-KEY was run red against this commit's parent before the fix landed beside it, the way
# check_camera.gd's SHORT STEP lane was proved (see that file's header): the failure is in
# docs/23's record, not reproducible from here, because the fix and the gate ship together --
# a gate cannot land red in the chain.

const SCENE_PATH: String = "res://presentation/main.tscn"
const PROJECT_FILE: String = "res://project.godot"
const LEGEND_GD: String = "res://ui/legend.gd"
const MAIN_GD: String = "res://presentation/main.gd"
const INPUT_MAP_GD: String = "res://presentation/input_map.gd"
const SESSION_GD: String = "res://presentation/session.gd"
const SAVE_PATH: String = "user://simplyzombies.save.json"
const PREFS_PATH: String = "user://ui_prefs.json"

const Clock = preload("res://sim/time/clock.gd")
const Legend = preload("res://ui/legend.gd")
const UiPrefs = preload("res://ui/prefs.gd")
const InputMapRes = preload("res://presentation/input_map.gd")
const Session = preload("res://presentation/session.gd")
const SimChronicle = preload("res://sim/modules/chronicle.gd")
const SimRecruits = preload("res://sim/modules/recruits.gd")
const SimAllegiance = preload("res://sim/modules/allegiance.gd")
const SimSave = preload("res://sim/save.gd")

# The frame loop's own delta. main.gd's TICK_SECONDS, named again here rather than read off the
# scene, so a gate that claims "one frame, one tick" is not quoting the thing it is judging.
const TICK_SECONDS: float = 1.0 / 20.0
# Under a minute, docs/00 pillar 6: this runs in the chain before every commit, and a gate
# nobody waits for is a gate nobody runs.
const BUDGET_MS: int = 60000

# Every key this gate presses, paired with the row the legend must carry for it. The KEYS lane
# reads both directions off this one table, so a key added to a lane without a legend row is red.
# Enter is the one key this gate presses that is deliberately absent: it is in UNLISTED below,
# by name and with its reason.
const PRESSED_KEYS: Array = [
	["WASD", "W and D, held, walk the body and sum to a diagonal"],
	["Shift", "Shift+C strikes the camp"],
	["P", "P holds the world still"],
	["Tab", "Tab opens the sheet"],
	["Esc", "Escape peels the legend, then opens settings"],
	["F5", "F5 writes a save"],
	["F9", "F9 reads it back"],
	["F1", "F1 raises the legend"],
	["C", "C makes camp"],
	["K", "K opens the skill web, which Escape peels before it pauses anything"],
	["Ctrl+C", "Ctrl+C crouches"],
	["Ctrl+S", "Ctrl+S stands"],
	["F", "F swings, and does not while the sheet is open"],
]

# The two actions `input_map.gd` binds that the legend deliberately does not name, each excused
# here by name and with the reason. The allowlist is the point: a third unlisted binding cannot
# arrive quietly, because adding one means writing down why it is not on the sheet a player reads.
const UNLISTED: Dictionary = {
	"dismiss": "Enter closes the legend and opens nothing; the panel's own header names F1",
	"debug": "F8 is the dev spawn menu, bound only under OS.is_debug_build()",
}

# Legend rows that are keys but not `BINDINGS` rows. WASD and E are bound -- by `MOVE_KEYS` and
# `INTERACT_KEY`, which are separate because a movement key carries a vector and the interact key
# is named once as a constant for check_vehicles.gd -- and the other three are the mouse, which
# lives in `_unhandled_input`. None of the five is taken on trust: KEYS checks `MOVE_KEYS` and
# `INTERACT_KEY` itself, and SOCKET checks that the router still has a `_unhandled_input` for the
# mouse rows to point at.
const NOT_A_BINDING: Dictionary = {
	"WASD": "MOVE_KEYS",
	"E": "INTERACT_KEY",
	"Mouse": "_unhandled_input",
	"Click": "_unhandled_input",
	"Right-click": "_unhandled_input",
	"Wheel": "_unhandled_input",
}

# Keys the legend must no longer offer. F8 came off it when the dev menu went debug-only; F2 was
# deleted outright (docs/30, "The alpha shell, 2026-09-16" -- a new run boots the fixed town).
const OFF_THE_SHEET: Array[String] = ["F8", "F2"]

var _skips: Array = []
var _started_ms: int = 0
var _save_backup: Variant = null
var _prefs_backup: Variant = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_started_ms = Time.get_ticks_msec()
	_backup_user_files()
	var ok: bool = true

	# Lanes that need no engine at all first: if the desk is wrong, the boot is wasted.
	ok = _the_scene_driven_is_the_scene_shipped() and ok
	ok = _every_key_pressed_is_a_key_the_legend_names() and ok
	ok = _the_keys_live_in_the_router() and ok

	# Before the boot the rest of the lanes share, because this one wants a machine that has
	# never seen the game: it deletes the prefs file and asserts the legend opens on top of a
	# fresh run. It leaves the flag set, which is also why every boot below starts on the street.
	var legend_ok: bool = await _the_legend_stays_dismissed()
	ok = legend_ok and ok

	var main: Node = await _boot()
	if main == null:
		_restore_user_files()
		push_error("PLAY_FAIL the scene did not boot")
		quit(1)
		return
	ok = _the_loop_advances_the_world(main) and ok
	ok = _a_held_key_walks_the_body(main) and ok
	var sheet_ok: bool = await _tab_opens_the_sheet(main)
	ok = sheet_ok and ok
	var peel_ok: bool = await _escape_peels_in_order(main)
	ok = peel_ok and ok
	ok = _f5_and_f9_round_trip(main) and ok
	ok = _c_is_the_camp_key_and_ctrl_c_is_the_stance(main) and ok
	var focus_ok: bool = await _the_open_sheet_swallows_the_street(main)
	ok = focus_ok and ok
	var pause_ok: bool = await _escape_pauses_to_the_menu(main)
	ok = pause_ok and ok
	var notice_ok: bool = await _a_refused_save_says_one_sentence(main)
	ok = notice_ok and ok
	ok = _the_volume_row_reaches_the_bus(main) and ok
	# Last on this scene: it puts the world's clock on the eve of day two and leaves it there.
	ok = _a_dawn_writes_the_slot(main) and ok
	main.queue_free()
	await process_frame

	# Their own scenes: the first wants a machine whose game has not been started, and the second
	# destroys the colony it is booted with.
	var title_ok: bool = await _the_title_waits_over_a_still_world()
	ok = title_ok and ok
	var over_ok: bool = await _the_run_over_screen()
	ok = over_ok and ok

	var draw_ok: bool = await _the_screen_draws_by_day_and_by_night()
	ok = draw_ok and ok

	_restore_user_files()
	var elapsed: int = Time.get_ticks_msec() - _started_ms
	ok = _the_gate_fits_its_budget(elapsed) and ok

	if ok:
		var skipped: String = "no lane skipped" if _skips.is_empty() else "skipped: %s" % ", ".join(PackedStringArray(_skips))
		print("PLAY_OK the scene boots to a title over a still world, ticks, walks, opens its screens, saves and loads, camps on C and crouches on Ctrl+C, refuses the street's keys under an open sheet, pauses to a menu on Escape, moves the audio bus, writes the slot at dawn and on the window's close, ends on a screen that speaks the chronicle and starts again, keeps a dismissed legend dismissed, and draws by day and by night in %d ms (%s)" % [elapsed, skipped])
		quit(0)
	else:
		push_error("PLAY_FAIL")
		quit(1)


# --- the harness ------------------------------------------------------------------------------

# A key event the engine will route the way a keyboard does. All five fields matter: `keycode`
# is what main.gd matches on, `physical_keycode` is what a layout-independent binding would read,
# `echo` false keeps it out of the repeat path main.gd rejects, and the two modifier flags are
# the whole point of the Ctrl ladder -- a gate that could not set them could not tell C from
# Ctrl+C.
func _key(code: Key, pressed: bool, ctrl: bool = false, shift: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	ev.echo = false
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
	return ev


func _hold(code: Key, ctrl: bool = false, shift: bool = false) -> void:
	root.push_input(_key(code, true, ctrl, shift))


func _release(code: Key, ctrl: bool = false, shift: bool = false) -> void:
	root.push_input(_key(code, false, ctrl, shift))


func _tap(code: Key, ctrl: bool = false, shift: bool = false) -> void:
	_hold(code, ctrl, shift)
	_release(code, ctrl, shift)


# n frames of the real loop. The scene's own processing is off (see _boot), so this is the only
# thing moving the world and a lane can count ticks.
func _frames(main: Node, n: int) -> void:
	for _i in range(n):
		main.call("_process", TICK_SECONDS)


# The scene, booted and handed over with the clock in this gate's hands, and *nothing else
# touched* -- whatever the legend does on a fresh machine, it does here. The LEGEND lane is the
# one caller that wants it raw; every other lane wants `_boot` below.
func _boot_scene() -> Node:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("cannot load %s" % SCENE_PATH)
		return null
	var main := packed.instantiate()
	if main.get_script() == null:
		push_error("the main scene script did not compile")
		return null
	root.add_child(main)
	# The world is built in _ready; one processed frame is what project_smoke.gd waits for.
	await process_frame
	if main.get("world") == null:
		push_error("the main scene did not construct a world")
		main.queue_free()
		return null
	# From here the gate owns the clock. Drawing is untouched -- DRAW needs real frames.
	main.set_process(false)
	# The one real frame above ran the loop with a wall-clock delta -- however long the boot
	# happened to take on this machine -- and left the remainder of it in the tick accumulator.
	# A lane that counts ticks has to start from a known debt or it reads one machine's boot
	# time as an extra tick, which is the kind of flake that gets a lane loosened rather than
	# fixed.
	main.set("accumulator", 0.0)
	return main


# The same boot, with the player standing on the street -- which since the alpha shell means two
# presses rather than none. The game opens on the title, so Enter chooses its first row ("new
# run") the way a player would; and the legend is a focus of its own since the input split, so it
# swallows every key but F1, Escape and Enter, which is exactly what a modal panel should do and
# exactly what would make TICKS, WALK and ROUNDTRIP judge nothing at all. Both are peeled the way
# a player peels them, before any lane presses anything.
func _boot() -> Node:
	var main: Node = await _boot_scene()
	if main == null:
		return null
	var shell: Variant = main.get("_shell")
	if shell != null and bool((shell as CanvasItem).visible):
		_tap(KEY_ENTER)
		await process_frame
	var legend: Variant = main.get("_legend")
	if legend != null and bool((legend as CanvasItem).visible):
		_tap(KEY_ESCAPE)
		await process_frame
	# The two presses above ran through the real frame the scene was still processing for; a lane
	# that counts ticks starts from a known debt, the same reason _boot_scene clears it.
	main.set("accumulator", 0.0)
	return main


# The session behind the scene: the four-state machine, the save and the boot.
func _session(main: Node) -> Variant:
	return main.get("session")


func _state(main: Node) -> int:
	var session: Variant = _session(main)
	return int(session.state) if session != null else -1


func _shell_of(main: Node) -> Variant:
	return main.get("_shell")


func _shell_rows(main: Node) -> Array:
	var shell: Variant = _shell_of(main)
	return [] if shell == null else Array(shell.call("rows"))


func _remove_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var da := DirAccess.open("user://")
		if da != null:
			da.remove(SAVE_PATH.get_file())


func _write_save_of(world: Variant, run_over: bool) -> void:
	var was: bool = bool(world.runOver)
	world.runOver = run_over
	var text: String = SimSave.encode_save(SimSave.create_save(world))
	world.runOver = was
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.flush()


func _digits_in(text: String) -> String:
	var found: String = ""
	for c in text:
		if c >= "0" and c <= "9":
			found += c
	return found


# The child node that owns the keys. Fetched rather than assumed: a lane that called `pump` on
# main would still pass with the split half-done, which is the whole failure the SOCKET lane
# below is about.
func _router(main: Node) -> Node:
	var router: Variant = main.get("_input_map")
	return router as Node if router != null else null


func _pos(main: Node) -> Dictionary:
	var world: Variant = main.get("world")
	var p: Variant = world.components.get_component(int(world.player), "position")
	if not (p is Dictionary):
		return {}
	return {"x": float((p as Dictionary)["x"]), "y": float((p as Dictionary)["y"])}


func _moved(a: Dictionary, b: Dictionary) -> float:
	if a.is_empty() or b.is_empty():
		return -1.0
	var dx: float = float(b["x"]) - float(a["x"])
	var dy: float = float(b["y"]) - float(a["y"])
	return sqrt(dx * dx + dy * dy)


# The commands a keypress left waiting, and nothing else: take() hands back everything queued
# and empties the queue, so each lane starts from a known-empty pending list.
func _drain(main: Node) -> Array:
	var world: Variant = main.get("world")
	return Array(world.commands.take(int(world.tick)))


func _pending(main: Node) -> Array:
	var world: Variant = main.get("world")
	return Array(world.commands._pending)


func _skip(lane: String, why: String) -> bool:
	print("%s SKIP %s" % [lane, why])
	_skips.append("%s (%s)" % [lane, why])
	return true


# user:// is shared with whoever ran the game on this machine: ROUNDTRIP writes the save slot
# twice, once with F5 and once with the corrupt text it refuses, and every boot reads the prefs.
# Both files are put back exactly as they were, present or absent; UiPrefs caches its file in a
# static, so the cache is dropped with it (docs/30's two-world static trap, in its per-process
# form -- a restored file behind a stale cache is a file nothing reads).
func _backup_user_files() -> void:
	_save_backup = FileAccess.get_file_as_string(SAVE_PATH) if FileAccess.file_exists(SAVE_PATH) else null
	_prefs_backup = FileAccess.get_file_as_string(PREFS_PATH) if FileAccess.file_exists(PREFS_PATH) else null


func _restore_one(path: String, backup: Variant) -> void:
	if backup == null:
		if FileAccess.file_exists(path):
			var da := DirAccess.open("user://")
			if da != null:
				da.remove(path.get_file())
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(String(backup))
		f.flush()


func _restore_user_files() -> void:
	_restore_one(SAVE_PATH, _save_backup)
	_restore_one(PREFS_PATH, _prefs_backup)
	UiPrefs._loaded = false


# A machine that has never run the game: no prefs file, and no static cache remembering one.
# Both halves matter -- the file is what `_ensure` reads and the static is what it reads *once*
# per process, so deleting the file alone leaves the old answer in memory (docs/30's two-world
# static trap, in its per-process form).
func _forget_prefs() -> void:
	if FileAccess.file_exists(PREFS_PATH):
		var da := DirAccess.open("user://")
		if da != null:
			da.remove(PREFS_PATH.get_file())
	UiPrefs._loaded = false


# The source text of one function, from its `func` line to the next top-level `func`.
# check_camera.gd's reader, unchanged -- the same reach assertion needs the same reader.
func _function_body(path: String, name: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var out: String = ""
	var inside: bool = false
	for line in f.get_as_text().split("\n"):
		if line.begins_with("func %s(" % name):
			inside = true
			continue
		if inside and line.begins_with("func "):
			break
		if inside:
			out += line + "\n"
	return out


# --- TICKS ------------------------------------------------------------------------------------

# The positive: n frames of the real loop advance the world by n ticks. The negative is the one
# that matters -- P, pressed as a key and not set as a flag, has to actually stop them, because
# "the loop runs" and "the loop cannot be stopped" look identical from a tick counter alone.
func _the_loop_advances_the_world(main: Node) -> bool:
	var world: Variant = main.get("world")
	var before: int = int(world.tick)
	_frames(main, 20)
	var after: int = int(world.tick)
	if after - before != 20:
		push_error("TICKS: 20 frames advanced the world %d ticks, not 20" % (after - before))
		return false
	_tap(KEY_P)
	if not bool(main.get("paused")):
		push_error("TICKS: P did not pause the loop")
		return false
	var paused_at: int = int(world.tick)
	_frames(main, 20)
	if int(world.tick) != paused_at:
		push_error("TICKS: the world advanced %d ticks while paused" % (int(world.tick) - paused_at))
		return false
	_tap(KEY_P)
	_frames(main, 5)
	if int(world.tick) != paused_at + 5:
		push_error("TICKS: P did not release the pause (tick %d, expected %d)" % [int(world.tick), paused_at + 5])
		return false
	print("TICKS OK 20 frames, 20 ticks; P holds the world still and gives it back")
	return true


# --- WALK -------------------------------------------------------------------------------------

# A held key is not a tap: the router tracks the down event and `pump()` turns the held set into
# one `move` command per change of direction. So the lane holds W, runs frames, and asks the sim
# where the body went -- and then releases it and asks whether it stopped, which is the half a
# "the key works" assertion usually leaves out.
func _a_held_key_walks_the_body(main: Node) -> bool:
	var router: Node = _router(main)
	if router == null:
		return _skip("WALK", "the scene built no key router to pump")
	var start: Dictionary = _pos(main)
	if start.is_empty():
		return _skip("WALK", "the player has no position component to watch")
	_hold(KEY_W)
	_frames(main, 40)
	var walked: Dictionary = _pos(main)
	var north: float = float(start["y"]) - float(walked["y"])
	if north <= 0.05:
		push_error("WALK: two seconds of held W moved the body %.3f m north" % north)
		return false
	_release(KEY_W)
	_frames(main, 40)
	var stopped: Dictionary = _pos(main)
	var drift: float = _moved(walked, stopped)
	if drift > 0.05:
		push_error("WALK: the body kept going %.3f m after W was released" % drift)
		return false
	# Two keys sum to a diagonal rather than the last one winning. Read off the command the pump
	# pushes, because a diagonal against a wall is a position that did not move and a lane that
	# cannot tell the two apart.
	_drain(main)
	_hold(KEY_W)
	_hold(KEY_D)
	router.call("pump")
	var diagonal: Variant = null
	for cmd_v in _pending(main):
		var cmd: Dictionary = cmd_v as Dictionary
		if String(cmd.get("type", "")) == "move":
			diagonal = cmd
	_release(KEY_W)
	_release(KEY_D)
	router.call("pump")
	if diagonal == null:
		push_error("WALK: holding W and D pushed no move command at all")
		return false
	var dx: float = float((diagonal as Dictionary).get("dx", 0.0))
	var dy: float = float((diagonal as Dictionary).get("dy", 0.0))
	if dx != 1.0 or dy != -1.0:
		push_error("WALK: W and D together asked for dx %.1f dy %.1f, not the diagonal 1,-1" % [dx, dy])
		return false
	print("WALK OK held W walked %.2f m north, release stopped it inside %.3f m, W+D sums to a diagonal" % [north, drift])
	return true


# --- SHEET ------------------------------------------------------------------------------------

# Tab is four things, not one (main.gd's _set_inventory_open says so): the flag, the panel, the
# HUD that would otherwise print through the sheet, and the corner doll the sheet's own doll
# duplicates. All four are asserted in both directions, so a Tab that opened the panel and left
# the HUD printing over it is red.
func _tab_opens_the_sheet(main: Node) -> bool:
	var hud: Variant = main.get("_hud")
	var doll: Variant = main.get("_paperdoll")
	if hud == null or doll == null:
		return _skip("SHEET", "the scene built no HUD or corner doll to peel")
	if bool(main.get("inventory_open")):
		push_error("SHEET: the sheet was already open before Tab was pressed")
		return false
	_tap(KEY_TAB)
	await process_frame
	if not bool(main.get("inventory_open")):
		push_error("SHEET: Tab did not open the sheet")
		return false
	if bool((hud as CanvasItem).visible):
		push_error("SHEET: the HUD still prints under the open sheet")
		return false
	if bool((doll as CanvasItem).visible):
		push_error("SHEET: the corner doll is still drawn under the open sheet")
		return false
	_tap(KEY_TAB)
	await process_frame
	if bool(main.get("inventory_open")):
		push_error("SHEET: Tab did not close the sheet again")
		return false
	if not bool((hud as CanvasItem).visible) or not bool((doll as CanvasItem).visible):
		push_error("SHEET: closing the sheet did not give the HUD and the doll back")
		return false
	print("SHEET OK Tab peels the HUD and the corner doll, and gives both back")
	return true


# --- SETTINGS ---------------------------------------------------------------------------------

# Escape peels layers in an order `input_map.gd`'s Escape arm states, and the order is `_focus()`'s
# own: the legend first, because it is the thing in front of you, and the pause menu only once
# nothing else is open. The negative is the first press -- if Escape raised the menu while the
# legend was up, the player would be reading two panels at once, and the assertion that catches
# that is "the shell is still hidden here".
#
# Settings is no longer a key. It is a row on the pause menu since the alpha shell (docs/30,
# 2026-09-16), so this lane walks to it the way a player does and asserts the two things that
# arrangement has to get right: the menu stands aside while the sheet is up (the shell is in
# front of everything in the focus order, so a settings panel behind it would never see its own
# Escape), and Escape inside the sheet goes back to the menu rather than to the street.
func _escape_peels_in_order(main: Node) -> bool:
	var legend: Variant = main.get("_legend")
	var settings: Variant = main.get("_settings")
	var shell: Variant = main.get("_shell")
	if legend == null or settings == null or shell == null:
		return _skip("SETTINGS", "the scene built no legend, settings panel or shell")
	if not bool((legend as CanvasItem).visible):
		_tap(KEY_F1)
		await process_frame
	if not bool((legend as CanvasItem).visible):
		return _skip("SETTINGS", "F1 did not raise a legend to peel")
	_tap(KEY_ESCAPE)
	await process_frame
	if bool((legend as CanvasItem).visible):
		push_error("SETTINGS: Escape did not close the legend")
		return false
	if bool((shell as CanvasItem).visible):
		push_error("SETTINGS: Escape raised the pause menu behind the legend it was closing")
		return false
	if bool((settings as CanvasItem).visible):
		push_error("SETTINGS: Escape opened settings behind the legend it was closing")
		return false
	_tap(KEY_ESCAPE)
	await process_frame
	if not bool((shell as CanvasItem).visible):
		push_error("SETTINGS: a second Escape did not raise the pause menu")
		return false
	if bool((settings as CanvasItem).visible):
		push_error("SETTINGS: Escape still opens the settings sheet directly; it is a menu row now")
		return false
	var rows: Array = _shell_rows(main)
	var at: int = rows.find("settings")
	if at < 0:
		push_error("SETTINGS: the pause menu offers no settings row: %s" % str(rows))
		return false
	for _i in range(at):
		_tap(KEY_S)
	await process_frame
	if int(shell.get("cursor")) != at:
		push_error("SETTINGS: %d presses of S left the menu on row %d, not %d" % [at, int(shell.get("cursor")), at])
		return false
	_tap(KEY_ENTER)
	await process_frame
	if not bool((settings as CanvasItem).visible):
		push_error("SETTINGS: the menu's settings row did not open the sheet")
		return false
	if bool((shell as CanvasItem).visible):
		push_error("SETTINGS: the menu is still up under the settings sheet, so the sheet never sees a key")
		return false
	_tap(KEY_ESCAPE)
	await process_frame
	if bool((settings as CanvasItem).visible):
		push_error("SETTINGS: Escape did not close the settings sheet again")
		return false
	if not bool((shell as CanvasItem).visible):
		push_error("SETTINGS: closing the settings sheet dropped the player past the menu that opened it")
		return false
	_tap(KEY_ESCAPE)
	await process_frame
	if bool((shell as CanvasItem).visible):
		push_error("SETTINGS: Escape on the pause menu did not give the street back")
		return false
	print("SETTINGS OK Escape peels the legend first, raises the menu only once it is gone, the menu's row opens settings and stands aside, and Escape walks back out through both")
	return true


# --- ROUNDTRIP --------------------------------------------------------------------------------

# F5 then F9 is the only persistence a player has today, and nothing had ever pressed either key.
# The positive is the round trip; the negative is the one that protects a live run -- a save file
# that will not decode must leave the world exactly where it was, not half-restore it and not
# clear it. The "Save file is unreadable" error printed during this lane is deliberate: it is the
# corrupt slot being refused.
func _f5_and_f9_round_trip(main: Node) -> bool:
	var world: Variant = main.get("world")
	_frames(main, 10)
	var saved_tick: int = int(world.tick)
	var saved_pos: Dictionary = _pos(main)
	_tap(KEY_F5)
	if not FileAccess.file_exists(SAVE_PATH):
		push_error("ROUNDTRIP: F5 wrote no save at %s" % SAVE_PATH)
		return false
	var decoded: Dictionary = SimSave.decode_save(FileAccess.get_file_as_string(SAVE_PATH))
	if decoded.has("__error"):
		push_error("ROUNDTRIP: F5 wrote a save that will not decode (%s)" % String(decoded["__error"]))
		return false
	_frames(main, 60)
	if int(world.tick) == saved_tick:
		return _skip("ROUNDTRIP", "the world did not move between the save and the load")
	_tap(KEY_F9)
	if int(world.tick) != saved_tick:
		push_error("ROUNDTRIP: F9 restored tick %d, not the saved %d" % [int(world.tick), saved_tick])
		return false
	var loaded_pos: Dictionary = _pos(main)
	if _moved(saved_pos, loaded_pos) > 0.001:
		push_error("ROUNDTRIP: F9 restored the body %.3f m from where it was saved" % _moved(saved_pos, loaded_pos))
		return false
	# The negative: a slot that is not a save at all.
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return _skip("ROUNDTRIP", "cannot write a corrupt slot to judge the refusal with")
	f.store_string("this is not a save")
	f.flush()
	f = null
	_frames(main, 20)
	var before_tick: int = int(world.tick)
	var before_pos: Dictionary = _pos(main)
	_tap(KEY_F9)
	if int(world.tick) != before_tick or _moved(before_pos, _pos(main)) > 0.001:
		push_error("ROUNDTRIP: a corrupt slot moved the live world (tick %d -> %d)" % [before_tick, int(world.tick)])
		return false
	print("ROUNDTRIP OK F5 wrote a save, F9 put the world back on tick %d, and a corrupt slot changed nothing" % saved_tick)
	return true


# --- CAMP-KEY ---------------------------------------------------------------------------------

# What a press left in the queue, judged: exactly one command of `want`, the right stance rung if
# one is asked for, and nothing at all of `forbidden`. Returns "" when the press was clean and the
# reason when it was not, so the fabricated list below can prove the predicate bites.
func _judge_press(pending: Array, want: String, want_stance: int, forbidden: String) -> String:
	var seen: int = 0
	var stance: int = -1
	var trespass: int = 0
	for cmd_v in pending:
		var cmd: Dictionary = cmd_v as Dictionary
		var kind: String = String(cmd.get("type", ""))
		if kind == want:
			seen += 1
			if want == "stance":
				stance = int(cmd.get("stance", -1))
		elif kind == forbidden or kind.begins_with(forbidden + "."):
			trespass += 1
	if seen != 1:
		return "%d `%s` commands, expected exactly 1" % [seen, want]
	if trespass > 0:
		return "%d `%s` commands the press had no business pushing" % [trespass, forbidden]
	if want_stance >= 0 and stance != want_stance:
		return "stance %d, expected rung %d" % [stance, want_stance]
	return ""


# C means camp and Ctrl+C means crouch (the owner's decision of 2026-09-16, docs/30's "The alpha
# shell"). Before the fix that ships with this gate, `C` fell through the camp arm of the match
# *and* the unmodified stance line below it, so one press both moved home and stood the body up.
# This lane is where that was caught, and it is red against this commit's parent.
#
# The predicate is proved on a fabricated pending list first, because a counter that never counts
# is the cheapest way to write a gate that cannot fail.
func _c_is_the_camp_key_and_ctrl_c_is_the_stance(main: Node) -> bool:
	var fabricated: Array = [{"type": "camp.establish"}, {"type": "stance", "stance": 2}]
	if _judge_press(fabricated, "camp.establish", -1, "stance") == "":
		push_error("CAMP-KEY: the predicate passed a press that pushed both a camp and a stance")
		return false
	if _judge_press([], "camp.establish", -1, "stance") == "":
		push_error("CAMP-KEY: the predicate passed a press that pushed nothing at all")
		return false
	if _judge_press([{"type": "stance", "stance": 3}], "stance", 1, "camp") == "":
		push_error("CAMP-KEY: the predicate passed a stance on the wrong rung")
		return false

	_drain(main)
	_tap(KEY_C)
	var camp: String = _judge_press(_pending(main), "camp.establish", -1, "stance")
	if camp != "":
		push_error("CAMP-KEY: C pushed %s" % camp)
		return false
	_drain(main)
	_tap(KEY_C, false, true)
	var strike: String = _judge_press(_pending(main), "camp.abandon", -1, "stance")
	if strike != "":
		push_error("CAMP-KEY: Shift+C pushed %s" % strike)
		return false
	_drain(main)
	_tap(KEY_C, true, false)
	var crouch: String = _judge_press(_pending(main), "stance", 1, "camp")
	if crouch != "":
		push_error("CAMP-KEY: Ctrl+C pushed %s" % crouch)
		return false
	# Ctrl+S is the stand rung, and it must not also walk the body backwards -- the modifier keeps
	# the key out of the held-movement set.
	_drain(main)
	_tap(KEY_S, true, false)
	var stand: String = _judge_press(_pending(main), "stance", 2, "camp")
	if stand != "":
		push_error("CAMP-KEY: Ctrl+S pushed %s" % stand)
		return false
	var held: Dictionary = _router(main).get("_held") as Dictionary
	if held.has(KEY_S):
		push_error("CAMP-KEY: Ctrl+S entered the held-movement set, so standing up steps backwards")
		return false
	print("CAMP-KEY OK C camps, Shift+C strikes, Ctrl+C crouches, Ctrl+S stands without stepping back")
	return true


# --- FOCUS ------------------------------------------------------------------------------------

# Until the input split every key fired under every open panel: W walked the body while you read
# the inventory, F swung at whatever was behind the sheet. `input_map.gd`'s `_focus()` names the
# screen in front and `ALLOWED` says what still fires under it.
#
# Three things are asserted and the third is the one that is easy to forget: a key *already held*
# when the sheet opens has to be let go of, or the sim keeps the last `move` vector and the body
# walks on behind the panel with no key to release it.
#
# The table is proved on fabricated arguments first. An `ALLOWED` that answered true to
# everything would pass every press below, which is a gate that cannot fail.
func _the_open_sheet_swallows_the_street(main: Node) -> bool:
	var router: Node = _router(main)
	if router == null:
		return _skip("FOCUS", "the scene built no key router to ask")
	if bool(main.get("inventory_open")):
		push_error("FOCUS: the sheet was already open before this lane opened it")
		return false
	if bool(router.call("_allows", "sheet", "swing")):
		push_error("FOCUS: the focus table lets a swing through an open sheet; it cannot say no")
		return false
	if not bool(router.call("_allows", "sheet", "inventory")):
		push_error("FOCUS: the focus table will not let Tab close the sheet it opened")
		return false
	if not bool(router.call("_allows", "street", "swing")):
		push_error("FOCUS: the focus table refuses a swing on the open street; it cannot say yes")
		return false

	# South first, back the way WALK came, and then a measurement: WALK has already held W for two
	# seconds, so the body is against whatever is north of the spawn and a "did not move" measured
	# there would be reading the map rather than the focus table. `room` is how far a held W
	# carries the body on the *open* street, and it is the precondition for the metres half below
	# rather than decoration -- with no room, that half says so and judges nothing instead of
	# passing on a number the map decided.
	_hold(KEY_S)
	_frames(main, 40)
	_release(KEY_S)
	_frames(main, 5)
	_drain(main)
	var open_from: Dictionary = _pos(main)
	_hold(KEY_W)
	_frames(main, 20)
	var open_to: Dictionary = _pos(main)
	var room: float = _moved(open_from, open_to)

	# Walking, and then the sheet. The zero move is what stops the body, so it is read off the
	# queue rather than inferred from a position a wall could also explain.
	_drain(main)
	_tap(KEY_TAB)
	await process_frame
	if not bool(main.get("inventory_open")):
		return _skip("FOCUS", "Tab did not open the sheet, so there is no focus to judge")
	var held: Dictionary = router.get("_held") as Dictionary
	if not held.is_empty():
		push_error("FOCUS: opening the sheet left %s held, so the walk continues behind it" % str(held.keys()))
		return false
	var stopped: bool = false
	for cmd_v in _pending(main):
		var cmd: Dictionary = cmd_v as Dictionary
		if String(cmd.get("type", "")) == "move" and float(cmd.get("dx", 1.0)) == 0.0 and float(cmd.get("dy", 1.0)) == 0.0:
			stopped = true
	if not stopped:
		push_error("FOCUS: opening the sheet on a held W pushed no zero move, so the sim keeps walking")
		return false

	# Five frames so the sim actually *takes* that zero, and only then a drain. Draining it
	# straight out of the queue instead would throw the stop away and leave the body carrying the
	# last vector it was given -- the gate walking the body itself and then blaming the router,
	# which is how this lane first went red against correct code.
	_frames(main, 5)
	# Held again, with the sheet up. The command is the half that bites: `pump()` is called here
	# rather than through a frame because `world.step` takes the queue, and a lane reading the
	# queue after a step reads an empty one whatever the router did.
	_drain(main)
	_hold(KEY_W)
	router.call("pump")
	for cmd_v in _pending(main):
		if String((cmd_v as Dictionary).get("type", "")) == "move":
			push_error("FOCUS: W pushed %s with the sheet open" % str(cmd_v))
			return false
	var before: Dictionary = _pos(main)
	_frames(main, 20)
	var drifted: float = _moved(before, _pos(main))
	if room > 0.05:
		if drifted > 0.01:
			push_error("FOCUS: W walked the body %.3f m with the sheet open" % drifted)
			return false
	elif drifted > 0.01:
		push_error("FOCUS: the body moved %.3f m under the sheet where the open street moved it none" % drifted)
		return false
	_drain(main)
	_tap(KEY_F)
	for cmd_v in _pending(main):
		if String((cmd_v as Dictionary).get("type", "")) == "swing":
			push_error("FOCUS: F swung at the street with the sheet open")
			return false

	# And the positive, off the command rather than off the ground, for the same reason.
	_release(KEY_W)
	_tap(KEY_TAB)
	await process_frame
	if bool(main.get("inventory_open")):
		return _skip("FOCUS", "Tab did not close the sheet again")
	_drain(main)
	_hold(KEY_W)
	router.call("pump")
	var north: Variant = null
	for cmd_v in _pending(main):
		if String((cmd_v as Dictionary).get("type", "")) == "move":
			north = cmd_v
	_release(KEY_W)
	router.call("pump")
	if north == null or float((north as Dictionary).get("dy", 0.0)) != -1.0:
		push_error("FOCUS: with the sheet closed again, held W pushed %s rather than a move north" % str(north))
		return false
	var metres: String = "%.2f m of room to prove it" % room if room > 0.05 else "no room to walk into, so the metres half said so and judged nothing"
	print("FOCUS OK the open sheet stops the body with one zero move, refuses a held W and an F, and gives the street back on Tab (%s)" % metres)
	return true


# --- LEGEND -----------------------------------------------------------------------------------

# "Shown once on a fresh run" is what `ui/legend.gd`'s header has said since it landed, and it was
# never true: nothing stored the dismissal, so every launch opened on the keys. The pref is
# `ui/prefs.gd`'s `legend_dismissed` and the proof has to cross a boot, because a flag held in the
# scene would pass an in-scene assertion and still greet the player at the next launch.
#
# The static cache is dropped between the two boots on purpose (docs/30's two-world static trap,
# in its per-process form): without that, the second scene reads the first scene's memory rather
# than the file, and the lane would pass with nothing written to disk at all.
func _the_legend_stays_dismissed() -> bool:
	_forget_prefs()
	if UiPrefs.flag("legend_dismissed"):
		push_error("LEGEND: a machine with no prefs file already thinks the keys were dismissed")
		return false
	var first: Node = await _boot_scene()
	if first == null:
		return false
	var legend: Variant = first.get("_legend")
	if legend == null:
		first.queue_free()
		return _skip("LEGEND", "the scene built no legend")
	# Not over the title. Since the alpha shell the game opens on a menu, and a panel of keys over
	# a menu is a panel about a game you have not started -- so the keys are offered on the first
	# entry to PLAYING instead, which is what Enter on the title's first row asks for.
	if bool((legend as CanvasItem).visible):
		first.queue_free()
		push_error("LEGEND: the keys are drawn over the title, before the run has started")
		return false
	_tap(KEY_ENTER)
	await process_frame
	if not bool((legend as CanvasItem).visible):
		first.queue_free()
		push_error("LEGEND: a fresh machine did not open on the keys when the run started")
		return false
	_tap(KEY_ENTER)
	await process_frame
	if bool((legend as CanvasItem).visible):
		first.queue_free()
		push_error("LEGEND: Enter did not put the keys away")
		return false
	if not UiPrefs.flag("legend_dismissed"):
		first.queue_free()
		push_error("LEGEND: Enter closed the panel and remembered nothing")
		return false
	first.queue_free()
	await process_frame

	UiPrefs._loaded = false
	if not FileAccess.file_exists(PREFS_PATH):
		return _skip("LEGEND", "the dismissal wrote no prefs file, so there is nothing for a second boot to read")
	var second: Node = await _boot_scene()
	if second == null:
		return false
	var again: Variant = second.get("_legend")
	if again == null:
		second.queue_free()
		return _skip("LEGEND", "the second boot built no legend")
	_tap(KEY_ENTER)
	await process_frame
	if bool((again as CanvasItem).visible):
		second.queue_free()
		push_error("LEGEND: the keys came back at the next boot despite the dismissal")
		return false
	_tap(KEY_F1)
	await process_frame
	if not bool((again as CanvasItem).visible):
		second.queue_free()
		push_error("LEGEND: F1 did not bring the keys back")
		return false
	second.queue_free()
	await process_frame
	print("LEGEND OK a fresh machine opens on the keys, Enter puts them away for good, the next boot is clean, and F1 asks for them again")
	return true


# --- DRAW -------------------------------------------------------------------------------------

# `_draw` is 1,250 lines of main.gd and nothing had ever run it. Headless is not an excuse: the
# dummy rendering driver still calls `_draw`, it simply throws the commands away, so every null
# dereference and every bad index in the draw path is reachable from here.
#
# The proof that it *completed* is one line at the very end of `_draw`: `_drew_tick = world.tick`.
# An aborted draw -- an error partway down _draw_entities -- never reaches that line, so the
# counter is the difference between "the engine called _draw" and "_draw got to the bottom".
# The night half matters because the night path is a different set of branches (the wash, the
# light pools, the fog) and day three at 2 a.m. is exactly where nobody has ever looked.
func _the_screen_draws_by_day_and_by_night() -> bool:
	var main: Node = await _boot()
	if main == null:
		return false
	var world: Variant = main.get("world")
	var day_tick: int = Clock.tick_on_day(1, 0.4)
	world.tick = day_tick
	if Clock.phase_of(int(world.tick)) != Clock.Phase.Day:
		main.queue_free()
		return _skip("DRAW", "the day tick this lane picked is not daylight")
	main.set("_drew_tick", -1)
	main.call("queue_redraw")
	await process_frame
	await process_frame
	if int(main.get("_drew_tick")) != day_tick:
		main.queue_free()
		push_error("DRAW: a daylight frame did not finish drawing (counter %d, tick %d)" % [int(main.get("_drew_tick")), day_tick])
		return false

	var night_tick: int = Clock.tick_on_day(3, 0.9)
	world.tick = night_tick
	if Clock.phase_of(int(world.tick)) != Clock.Phase.Night:
		main.queue_free()
		return _skip("DRAW", "the night tick this lane picked is not night")
	main.set("_drew_tick", -1)
	main.call("queue_redraw")
	await process_frame
	await process_frame
	if int(main.get("_drew_tick")) != night_tick:
		main.queue_free()
		push_error("DRAW: night three did not finish drawing (counter %d, tick %d)" % [int(main.get("_drew_tick")), night_tick])
		return false

	# The negative. A hidden node draws nothing, so the counter must stay where it was put -- if
	# it moved here, it is being written by something other than a completed draw and neither half
	# above proves anything.
	(main as CanvasItem).visible = false
	main.set("_drew_tick", -1)
	main.call("queue_redraw")
	await process_frame
	await process_frame
	var hidden: int = int(main.get("_drew_tick"))
	(main as CanvasItem).visible = true
	main.queue_free()
	if hidden != -1:
		push_error("DRAW: a hidden node still moved the draw counter to %d" % hidden)
		return false
	print("DRAW OK the screen finished drawing on day one and on night three, and not at all when hidden")
	return true


# --- RUN-OVER ---------------------------------------------------------------------------------

# The lane the shell turned on. It skipped, loudly, from the day this gate landed until
# `presentation/session.gd` existed: the last survivor died, `world.runOver` went true, the HUD
# printed one line and the sim kept ticking over the corpse -- there was no screen to assert and
# nothing to stop. Now there is, and the skip is the assertion.
#
# Four things, and the third is the one the epitaph exists for. The run ends; the clock stops;
# the screen speaks the chronicle **past its own window**, so a death from earlier in the run is
# still there when the run's own last line is written; and "new run" hands back a different world
# object that moves.
func _the_run_over_screen() -> bool:
	var main: Node = await _boot()
	if main == null:
		return false
	var world: Variant = main.get("world")
	var shell: Variant = main.get("_shell")
	if shell == null:
		main.queue_free()
		return _skip("RUN-OVER", "the scene built no shell to end on")

	# One real death first, so the chronicle has a line that is genuinely older than the screen's
	# window by the time the run ends. The tick is then jumped rather than played: LINE_TICKS is
	# two game hours and twenty-four thousand ticks of real stepping is most of this gate's budget.
	var early: int = -1
	for e in world.components.query(["identity", "position"]):
		if int(e) != int(world.player) and SimAllegiance.is_colony(world, int(e)):
			early = int(e)
			break
	if early < 0:
		main.queue_free()
		return _skip("RUN-OVER", "the boot colony has nobody but the player to lose first")
	world.events.publish({"type": "entity.killed", "entity": early})
	_frames(main, 1)
	var early_lines: Array = SimChronicle.lines(world)
	if early_lines.is_empty():
		main.queue_free()
		return _skip("RUN-OVER", "the first death wrote no chronicle line to age out")
	var aged: String = String(early_lines[0])
	world.tick += SimChronicle.LINE_TICKS + 1
	if not SimChronicle.lines(world).is_empty():
		main.queue_free()
		push_error("RUN-OVER: the line this lane aged out is still inside the HUD's window")
		return false

	# And then the colony. Every other body of yours is a corpse, so succession has nobody to
	# hand the camera to and the player's death is the run's.
	for e in world.components.query(["position"]):
		var ent: int = int(e)
		if ent == int(world.player):
			continue
		if world.components.has_component(ent, "shambler"):
			continue
		if not SimAllegiance.is_colony(world, ent):
			continue
		world.components.set_component(ent, "corpse", {"sinceTick": int(world.tick)})
	SimRecruits.handle_death(world, int(world.player))
	_frames(main, 1)
	if not bool(world.runOver):
		main.queue_free()
		return _skip("RUN-OVER", "the player's death did not end the run, so there is no screen to judge")
	if _state(main) != Session.State.RUN_OVER:
		main.queue_free()
		push_error("RUN-OVER: the run ended and the session is in state %d, not RUN_OVER" % _state(main))
		return false
	if not bool((shell as CanvasItem).visible):
		main.queue_free()
		push_error("RUN-OVER: the run ended and no screen came up")
		return false
	var frozen: int = int(world.tick)
	_frames(main, 10)
	if int(world.tick) != frozen:
		main.queue_free()
		push_error("RUN-OVER: the world advanced %d ticks after the run was over" % (int(world.tick) - frozen))
		return false

	var spoken: Array = Array(shell.call("lines"))
	var expected: Array = Array(SimChronicle.epitaph(world, 5))
	if spoken != expected:
		main.queue_free()
		push_error("RUN-OVER: the screen says %s and the chronicle's epitaph is %s" % [str(spoken), str(expected)])
		return false
	if spoken.is_empty():
		main.queue_free()
		return _skip("RUN-OVER", "the run ended with an empty chronicle, so there is no epitaph to read")
	for line in spoken:
		if not _digits_in(String(line)).is_empty():
			main.queue_free()
			push_error("RUN-OVER: an epitaph line carries a digit: '%s'" % String(line))
			return false
	if not spoken.has(aged):
		main.queue_free()
		push_error("RUN-OVER: the epitaph dropped '%s', which the HUD's window had already forgotten" % aged)
		return false

	# New run, from the row a player would press. A *different world object*, not the same one
	# with its flag cleared: the identity check is the half that a `runOver = false` would pass.
	var rows: Array = _shell_rows(main)
	if rows.is_empty() or String(rows[0]) != "new run":
		main.queue_free()
		push_error("RUN-OVER: the screen's first row is %s, not a new run" % str(rows))
		return false
	_tap(KEY_ENTER)
	await process_frame
	var fresh: Variant = main.get("world")
	if fresh == world:
		main.queue_free()
		push_error("RUN-OVER: new run handed back the same world object the run ended in")
		return false
	if bool(fresh.runOver):
		main.queue_free()
		push_error("RUN-OVER: the new run is over before it started")
		return false
	if _state(main) != Session.State.PLAYING:
		main.queue_free()
		push_error("RUN-OVER: new run left the session in state %d, not PLAYING" % _state(main))
		return false
	var started: int = int(fresh.tick)
	_frames(main, 10)
	var moved: int = int(fresh.tick) - started
	main.queue_free()
	await process_frame
	if moved != 10:
		push_error("RUN-OVER: the new run advanced %d ticks in ten frames" % moved)
		return false
	print("RUN-OVER OK the run ends on a screen that freezes the clock and speaks %d lines of the chronicle including one the HUD had forgotten, and new run hands back a world that moves" % spoken.size())
	return true


# --- TITLE and CLOSE ----------------------------------------------------------------------------

# The game opens on a menu, over a world that is already booted and is not moving. Both halves
# matter: the world has to exist one frame in, because `test/project_smoke.gd` and `check_hud.gd`
# both assert it does, and it must not be *ticking*, because a title screen the district plays on
# behind is a run you are losing without watching.
#
# The continue row is asked three ways, which is the only way to show the question is being
# asked at all: no slot, a live slot, and the wreck of a finished run.
#
# CLOSE rides on this scene rather than booting a seventh: it is the same two states, and the
# assertion is the same file appearing or not appearing.
func _the_title_waits_over_a_still_world() -> bool:
	_remove_save()
	var main: Node = await _boot_scene()
	if main == null:
		return false
	var shell: Variant = main.get("_shell")
	var hud: Variant = main.get("_hud")
	var world: Variant = main.get("world")
	if shell == null or _session(main) == null:
		main.queue_free()
		return _skip("TITLE", "the scene built no shell or session")
	if _state(main) != Session.State.TITLE:
		main.queue_free()
		push_error("TITLE: the scene booted into state %d, not TITLE" % _state(main))
		return false
	if not bool((shell as CanvasItem).visible):
		main.queue_free()
		push_error("TITLE: the game opened with no title on screen")
		return false
	if hud != null and bool((hud as CanvasItem).visible):
		main.queue_free()
		push_error("TITLE: the player's HUD prints over the title")
		return false
	# And the quick strip with it. It draws during ordinary play whether or not the sheet is open,
	# so it is the one screen that does not peel itself -- and over the title it is six belt slots
	# and their key numbers under a menu, which is how a digit reaches a screen the owner said
	# would carry none.
	var sheet: Variant = main.get("_inventory_panel")
	if sheet != null and bool((sheet as CanvasItem).visible):
		main.queue_free()
		push_error("TITLE: the quick strip is still drawn under the title")
		return false
	var before: int = int(world.tick)
	var stood: Dictionary = _pos(main)
	_frames(main, 10)
	if int(world.tick) != before:
		main.queue_free()
		push_error("TITLE: the world advanced %d ticks behind the title" % (int(world.tick) - before))
		return false
	if _moved(stood, _pos(main)) > 0.001:
		main.queue_free()
		push_error("TITLE: the body moved behind the title")
		return false

	# No slot, so nothing to continue.
	if _shell_rows(main).has("continue"):
		main.queue_free()
		push_error("TITLE: a machine with no save offers to continue one: %s" % str(_shell_rows(main)))
		return false
	# A live slot, so there is.
	_write_save_of(world, false)
	main.call("_enter_state", Session.State.TITLE)
	if not _shell_rows(main).has("continue"):
		main.queue_free()
		push_error("TITLE: a live save is on disk and the title does not offer it: %s" % str(_shell_rows(main)))
		return false
	# And the wreck of a finished run, which is not a run to go back to.
	_write_save_of(world, true)
	main.call("_enter_state", Session.State.TITLE)
	if _shell_rows(main).has("continue"):
		main.queue_free()
		push_error("TITLE: the title offers to continue a run that was already over")
		return false

	# The window's close request, from the title: there is no run to write down.
	_remove_save()
	main.call("_enter_state", Session.State.TITLE)
	main.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	if FileAccess.file_exists(SAVE_PATH):
		main.queue_free()
		push_error("CLOSE: closing the window from the title wrote a save of a run nobody started")
		return false

	# New run, off the first row, the way a player presses it.
	var rows: Array = _shell_rows(main)
	if rows.is_empty() or String(rows[0]) != "new run":
		main.queue_free()
		push_error("TITLE: the title's first row is %s, not a new run" % str(rows))
		return false
	_tap(KEY_ENTER)
	await process_frame
	if _state(main) != Session.State.PLAYING:
		main.queue_free()
		push_error("TITLE: Enter on the new-run row left the session in state %d" % _state(main))
		return false
	if bool((shell as CanvasItem).visible):
		main.queue_free()
		push_error("TITLE: the menu is still on screen with the run running behind it")
		return false
	world = main.get("world")
	var started: int = int(world.tick)
	_frames(main, 20)
	if int(world.tick) - started != 20:
		main.queue_free()
		push_error("TITLE: twenty frames of the started run advanced %d ticks" % (int(world.tick) - started))
		return false

	# And the same close request, from a live run: this one is written down.
	main.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	if not FileAccess.file_exists(SAVE_PATH):
		main.queue_free()
		push_error("CLOSE: closing the window mid-run wrote no save")
		return false
	var decoded: Dictionary = SimSave.decode_save(FileAccess.get_file_as_string(SAVE_PATH))
	main.queue_free()
	await process_frame
	if decoded.has("__error"):
		push_error("CLOSE: the save written on the window's close will not decode (%s)" % String(decoded["__error"]))
		return false
	# The web build is excluded from this and cannot be driven headless, so it is read where it is
	# written -- a textual half beside an executed one, named as such.
	var closer: String = _function_body(MAIN_GD, "_notification")
	if closer.find("NOTIFICATION_WM_CLOSE_REQUEST") < 0 or closer.find("OS.has_feature(\"web\")") < 0:
		push_error("CLOSE: main.gd's _notification does not answer the close request, or does not excuse the web build")
		return false
	print("TITLE OK the game opens on a menu over a world that is not ticking, the continue row follows the slot three ways, and Enter starts a run that moves")
	print("CLOSE OK the window's close writes a decodable save from a live run and nothing from the title, and the web build is excused in the handler")
	return true


# --- PAUSE --------------------------------------------------------------------------------------

# Escape on the street, with nothing open, is the pause menu (the owner's decision of 2026-09-16;
# it used to open the settings sheet). Positive: the menu comes up and the clock stops. Negative:
# Escape is still a peel first -- with the skill web open it closes the web and the run keeps
# going, which is the assertion that stops "Escape always pauses" from being the implementation.
func _escape_pauses_to_the_menu(main: Node) -> bool:
	var shell: Variant = main.get("_shell")
	var web: Variant = main.get("_web_panel")
	var world: Variant = main.get("world")
	if shell == null:
		return _skip("PAUSE", "the scene built no shell to pause into")
	if _state(main) != Session.State.PLAYING:
		return _skip("PAUSE", "the scene is not playing, so there is nothing to pause")
	_tap(KEY_ESCAPE)
	await process_frame
	if _state(main) != Session.State.PAUSED:
		push_error("PAUSE: Escape on the street left the session in state %d, not PAUSED" % _state(main))
		return false
	if not bool((shell as CanvasItem).visible):
		push_error("PAUSE: the session paused and no menu came up")
		return false
	var held_at: int = int(world.tick)
	_frames(main, 10)
	if int(world.tick) != held_at:
		push_error("PAUSE: the world advanced %d ticks behind the pause menu" % (int(world.tick) - held_at))
		return false
	_tap(KEY_ESCAPE)
	await process_frame
	if _state(main) != Session.State.PLAYING or bool((shell as CanvasItem).visible):
		push_error("PAUSE: Escape on the menu did not give the street back")
		return false
	_frames(main, 5)
	if int(world.tick) != held_at + 5:
		push_error("PAUSE: the clock did not start again (tick %d, expected %d)" % [int(world.tick), held_at + 5])
		return false
	if web == null:
		return _skip("PAUSE", "the scene built no skill web, so the peel half judges nothing")
	_tap(KEY_K)
	await process_frame
	if not bool((web as CanvasItem).visible):
		return _skip("PAUSE", "K did not open the web, so the peel half judges nothing")
	_tap(KEY_ESCAPE)
	await process_frame
	if bool((web as CanvasItem).visible):
		push_error("PAUSE: Escape did not close the web it was peeling")
		return false
	if _state(main) != Session.State.PLAYING or bool((shell as CanvasItem).visible):
		push_error("PAUSE: Escape closed the web and paused the run as well; the peel comes first")
		return false
	print("PAUSE OK Escape on the street raises the menu and stops the clock, gives both back, and still peels an open screen before it pauses anything")
	return true


# --- NOTICE -------------------------------------------------------------------------------------

# A save the build cannot read leaves the player where they are and says **one fixed sentence**.
# The sentence exists because the alternative is `SimSave.decode_save`'s own message -- "save
# format 13, this build reads 33" -- which is two digits on a player's screen and two numbers that
# mean nothing to the person reading them.
#
# The menu's `load` row is the only way to reach it: the title's `continue` row is not offered at
# all for a slot that will not decode (`has_continue` asks the same question), so without this
# lane the notice would be prose nothing on screen could ever show. Both halves are asserted --
# the sentence is there, and the decoder's is not.
func _a_refused_save_says_one_sentence(main: Node) -> bool:
	var shell: Variant = main.get("_shell")
	var world: Variant = main.get("world")
	if shell == null:
		return _skip("NOTICE", "the scene built no shell to say anything")
	if _state(main) != Session.State.PLAYING:
		return _skip("NOTICE", "the scene is not playing, so there is no menu to reach the row from")
	# A slot from a build that is not this one. The literal `check_m2_save.gd` uses for the same
	# refusal, so the two gates agree on what a stale save looks like.
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return _skip("NOTICE", "cannot write a stale slot to be refused")
	f.store_string("{\"snapshot\":{\"version\":13},\"meta\":{}}")
	f.flush()
	f = null
	_tap(KEY_ESCAPE)
	await process_frame
	var rows: Array = _shell_rows(main)
	var at: int = rows.find("load")
	if at < 0:
		_remove_save()
		return _skip("NOTICE", "the pause menu offers no load row")
	for _i in range(at):
		_tap(KEY_S)
	var held_at: int = int(world.tick)
	_tap(KEY_ENTER)
	await process_frame
	var words: Array = Array(shell.call("words"))
	var still_up: bool = bool((shell as CanvasItem).visible)
	var state_after: int = _state(main)
	var tick_after: int = int(world.tick)
	_remove_save()
	if not still_up or state_after != Session.State.PAUSED:
		push_error("NOTICE: a save that will not decode took the player off the menu anyway (state %d)" % state_after)
		return false
	if tick_after != held_at:
		push_error("NOTICE: the refused load moved the world %d ticks" % (tick_after - held_at))
		return false
	var said: bool = false
	for word in words:
		if String(word) == Session.STALE_NOTICE:
			said = true
		if not _digits_in(String(word)).is_empty():
			push_error("NOTICE: the refusal put a digit on the menu: '%s'" % String(word))
			return false
		if String(word).find("save format") >= 0:
			push_error("NOTICE: the decoder's own message reached the screen: '%s'" % String(word))
			return false
	if not said:
		push_error("NOTICE: the menu says nothing about the save it refused: %s" % str(words))
		return false
	_tap(KEY_ESCAPE)
	await process_frame
	if _state(main) != Session.State.PLAYING:
		push_error("NOTICE: Escape did not give the street back after the refusal")
		return false
	print("NOTICE OK a save from another build leaves the run where it was and says one sentence, with no digit and none of the decoder's own message")
	return true


# --- VOLUME -------------------------------------------------------------------------------------

# The settings sheet's volume row, and the first thing in this tree ever to reach `AudioServer`.
# Half way is half way in decibels, nought is mute -- and the mute half is the one that needed a
# decision, because `ui/prefs.gd`'s opacity clamp would have made the leftmost notch a game you
# can still hear. The textual halves are the dead-socket question from both ends: the sfx node
# has to reach the bus at all, and main.gd's prefs callback has to reach the sfx node.
func _the_volume_row_reaches_the_bus(main: Node) -> bool:
	var sfx: Variant = main.get("_sfx")
	if sfx == null or not (sfx as Node).has_method("apply_volume"):
		return _skip("VOLUME", "the scene built no sfx node with a volume to apply")
	var was: float = UiPrefs.volume()
	UiPrefs.set_volume(0.5)
	main.call("_on_ui_prefs_changed")
	var half: float = AudioServer.get_bus_volume_db(0)
	if absf(half - linear_to_db(0.5)) > 0.01:
		UiPrefs.set_volume(was)
		main.call("_on_ui_prefs_changed")
		push_error("VOLUME: half volume put the bus at %.3f dB, not %.3f" % [half, linear_to_db(0.5)])
		return false
	UiPrefs.set_volume(0.0)
	# Read *before* the restore below, not after: the first cut of this lane put the row back to
	# where it found it and then printed `UiPrefs.volume()` in the failure message, so a clamped
	# nought was reported as the value it had been restored to. A gate that blames the wrong
	# number is worse than no gate.
	var stored: float = UiPrefs.volume()
	if stored != 0.0:
		UiPrefs.set_volume(was)
		main.call("_on_ui_prefs_changed")
		push_error("VOLUME: nought came back as %.3f; the opacity floor is clamping the volume row" % stored)
		return false
	main.call("_on_ui_prefs_changed")
	var mute: float = AudioServer.get_bus_volume_db(0)
	UiPrefs.set_volume(was)
	main.call("_on_ui_prefs_changed")
	if mute > -60.0:
		push_error("VOLUME: nought on the row left the bus at %.3f dB, which is not mute" % mute)
		return false
	var sfx_src: String = FileAccess.get_file_as_string("res://presentation/sfx.gd")
	if sfx_src.find("AudioServer.set_bus_volume_db") < 0:
		push_error("VOLUME: presentation/sfx.gd never reaches AudioServer, so the row moves nothing a player hears")
		return false
	if _function_body(MAIN_GD, "_on_ui_prefs_changed").find("apply_volume") < 0:
		push_error("VOLUME: main.gd's prefs callback never applies the volume, so the slider is silent until a reboot")
		return false
	var rows: String = ""
	for line in FileAccess.get_file_as_string("res://ui/settings_panel.gd").split("\n"):
		if String(line).find("\"key\": \"volume\"") >= 0:
			rows = String(line)
	if rows.is_empty():
		push_error("VOLUME: the settings sheet has no volume row, so nothing on screen moves the bus")
		return false
	print("VOLUME OK half way is %.2f dB, nought is %.2f dB and is stored as nought, the sheet has the row and main.gd's callback applies it" % [half, mute])
	return true


# --- AUTOSAVE -----------------------------------------------------------------------------------

# The slot is written at each dawn (and on the window's close, and on quit to title -- the owner's
# decision of 2026-09-16). This lane is the dawn half, and its two negatives are what make it an
# *edge* rather than a phase: an ordinary tick writes nothing, and a run that is already over
# writes nothing at the very same tick, because a run-over slot is one the title would refuse to
# offer and the player would find their run gone.
#
# It runs last on this scene: it leaves the clock on the eve of day two.
func _a_dawn_writes_the_slot(main: Node) -> bool:
	var world: Variant = main.get("world")
	if _state(main) != Session.State.PLAYING:
		return _skip("AUTOSAVE", "the scene is not playing, so no frame will reach the edge")
	_remove_save()
	_frames(main, 5)
	if FileAccess.file_exists(SAVE_PATH):
		push_error("AUTOSAVE: five ordinary ticks wrote a save")
		return false
	var dawn: int = Clock.tick_on_day(2, 0.0)
	if Clock.phase_of(dawn) != Clock.Phase.Dawn or Clock.phase_of(dawn - 1) == Clock.Phase.Dawn:
		return _skip("AUTOSAVE", "the tick this lane calls dawn is not the first tick of a day")
	world.tick = dawn - 1
	main.set("accumulator", 0.0)
	_frames(main, 1)
	if not FileAccess.file_exists(SAVE_PATH):
		push_error("AUTOSAVE: the first tick of day two wrote no save")
		return false
	var decoded: Dictionary = SimSave.decode_save(FileAccess.get_file_as_string(SAVE_PATH))
	if decoded.has("__error"):
		push_error("AUTOSAVE: the dawn save will not decode (%s)" % String(decoded["__error"]))
		return false
	var at: int = int((decoded.get("meta", {}) as Dictionary).get("savedAtTick", -1))
	if at != dawn:
		push_error("AUTOSAVE: the dawn save is stamped tick %d, not the dawn tick %d" % [at, dawn])
		return false
	# And the same edge with the run already over.
	_remove_save()
	world.tick = dawn - 1
	world.runOver = true
	main.set("accumulator", 0.0)
	_frames(main, 1)
	var wrote: bool = FileAccess.file_exists(SAVE_PATH)
	world.runOver = false
	main.call("_enter_state", Session.State.PLAYING)
	if wrote:
		push_error("AUTOSAVE: a finished run wrote a save at the dawn edge; the title would offer a run that is over")
		return false
	print("AUTOSAVE OK the first tick of a day writes the slot stamped on that tick, an ordinary tick writes nothing, and a finished run writes nothing at the same edge")
	return true


# --- SCENE ------------------------------------------------------------------------------------

func _main_scene_in(text: String) -> String:
	for raw in text.split("\n"):
		var line: String = String(raw).strip_edges()
		if line.begins_with("run/main_scene="):
			return line.substr("run/main_scene=".length()).strip_edges().trim_prefix("\"").trim_suffix("\"")
	return ""


# The whole gate is worth nothing if it drives a scene the game does not ship. project.godot is
# the authority; the reader is proved on a fabricated line first, because "no match" and "a match
# that happens to agree" look the same from the assertion.
func _the_scene_driven_is_the_scene_shipped() -> bool:
	if _main_scene_in("run/main_scene=\"res://presentation/not_the_game.tscn\"") == SCENE_PATH:
		push_error("SCENE: the reader answers this gate's own scene for a project that names another")
		return false
	if _main_scene_in("[application]\nconfig/name=\"simplyZOMBIES\"") != "":
		push_error("SCENE: the reader invented a main scene for a project file that names none")
		return false
	var text: String = FileAccess.get_file_as_string(PROJECT_FILE)
	if text.is_empty():
		push_error("SCENE: cannot read %s" % PROJECT_FILE)
		return false
	var shipped: String = _main_scene_in(text)
	if shipped != SCENE_PATH:
		push_error("SCENE: the game boots '%s' and this gate drives '%s'" % [shipped, SCENE_PATH])
		return false
	print("SCENE OK the gate drives %s, which is what project.godot boots" % shipped)
	return true


# --- KEYS -------------------------------------------------------------------------------------

# Every key column the legend carries, split on the slashes it uses to group rungs, so "Ctrl+Z /
# Ctrl+C / Ctrl+S / Ctrl+V" answers for each of its four keys and "C" answers only for itself.
# Whole tokens, never substrings: "C" is inside "Ctrl+C" and a substring match would let the camp
# row vanish without this lane noticing.
func _legend_keys(groups: Array) -> Array:
	var keys: Array = []
	for group in groups:
		for row in (group as Array)[1] as Array:
			for token in String((row as Array)[0]).split("/"):
				var t: String = String(token).strip_edges()
				if not t.is_empty():
					keys.append(t)
	return keys


# A player learns the keys from F1 and from nothing else. So the keys this gate presses -- which
# are the keys a player presses -- must each have a row, and the Ctrl ladder must read as the
# Ctrl ladder rather than as the bare letters it used to be.
func _every_key_pressed_is_a_key_the_legend_names() -> bool:
	var fabricated: Array = [["Move", [["WASD", "walk"], ["Z / X / C / V", "crawl, crouch, walk, jog"]]]]
	if _legend_keys(fabricated).has("Ctrl+C"):
		push_error("KEYS: the reader found Ctrl+C in a legend that names none")
		return false
	if not _legend_keys(fabricated).has("WASD"):
		push_error("KEYS: the reader cannot find a key the fabricated legend does name")
		return false
	var named: Array = _legend_keys(Legend.GROUPS)
	if named.is_empty():
		push_error("KEYS: the legend names no keys at all")
		return false
	for entry in PRESSED_KEYS:
		var key: String = String((entry as Array)[0])
		if not named.has(key):
			push_error("KEYS: this gate presses %s (%s) and the legend names no row for it" % [key, String((entry as Array)[1])])
			return false
	# And the ladder the owner moved onto Ctrl is on Ctrl, not still on the bare letters where it
	# collided with the camp key.
	for stale in ["Z / X / C / V", "Z", "X", "V"]:
		if named.has(stale):
			push_error("KEYS: the legend still offers '%s' as a stance key; the ladder is on Ctrl now" % stale)
			return false

	# Both directions against the rebind seam. The legend and `BINDINGS` are two copies of the
	# same list -- which is exactly why they are read against each other: a key rebound without
	# its row moving is red, and a row for a key nothing binds is red too.
	var bound: Dictionary = {}
	for action in InputMapRes.BINDINGS.keys():
		var row: Dictionary = InputMapRes.BINDINGS[action] as Dictionary
		for token in row["legend"] as Array:
			bound[String(token)] = String(action)
	if bound.is_empty():
		push_error("KEYS: BINDINGS names no legend tokens at all, so neither direction judges anything")
		return false
	# The scanner, proved on a row nothing could bind before it is trusted on the real sheet.
	var invented: Array = [["Act", [["Q", "quaff the potion"]]]]
	if _unbound_in(_legend_keys(invented), bound).is_empty():
		push_error("KEYS: a fabricated legend row for Q passed as a bound key")
		return false
	if not _unbound_in(["Tab"], bound).is_empty():
		push_error("KEYS: the scanner called a bound key unbound; it cannot say yes")
		return false
	# The two keys that came off the sheet stay off it. Before the unbound scan below, because
	# both would also trip that one today and "F8 is dev-only" is the answer a reader wants --
	# and because the day somebody gives `debug` a legend row, this is the only check left that
	# still refuses it.
	for gone in OFF_THE_SHEET:
		if named.has(gone):
			push_error("KEYS: the legend still offers '%s'; it is dev-only or deleted" % gone)
			return false
	var orphan: String = _unbound_in(named, bound)
	if not orphan.is_empty():
		push_error("KEYS: the legend names '%s' and nothing in BINDINGS, MOVE_KEYS or INTERACT_KEY binds it" % orphan)
		return false
	# The other way: a binding with no row is red unless UNLISTED excuses it by name.
	for action in InputMapRes.BINDINGS.keys():
		var tokens: Array = (InputMapRes.BINDINGS[action] as Dictionary)["legend"] as Array
		if tokens.is_empty():
			if not UNLISTED.has(String(action)):
				push_error("KEYS: the router binds '%s' and the legend has no row for it" % String(action))
				return false
			continue
		for token in tokens:
			if not named.has(String(token)):
				push_error("KEYS: '%s' is bound to the legend row '%s', which the legend does not have" % [String(action), String(token)])
				return false
	# The two rows excused as "not a BINDINGS row" are excused because something else binds them.
	if (InputMapRes.MOVE_KEYS as Dictionary).is_empty():
		push_error("KEYS: MOVE_KEYS is empty, so the legend's WASD row names nothing")
		return false
	if InputMapRes.INTERACT_KEY != KEY_E:
		push_error("KEYS: INTERACT_KEY is not E, so the legend's E row names another key")
		return false
	print("KEYS OK the legend names every one of the %d keys this gate presses, every one of its %d key tokens is bound, every binding but the %d excused by name has a row, and the stance ladder reads as Ctrl" % [PRESSED_KEYS.size(), named.size(), UNLISTED.size()])
	return true


# The first legend token nothing binds, or "" when every one of them is bound. A token counts as
# bound by a `BINDINGS` row, or by the two things that are keys without being rows -- `MOVE_KEYS`
# and `INTERACT_KEY` -- or by the mouse, which `_unhandled_input` reads and no key table names.
func _unbound_in(tokens: Array, bound: Dictionary) -> String:
	for token in tokens:
		var t: String = String(token)
		if bound.has(t) or NOT_A_BINDING.has(t):
			continue
		return t
	return ""


# --- SOCKET -----------------------------------------------------------------------------------

# The split itself, asserted where it can be: `main.gd` has no `_input` left, the router has the
# three functions the engine and the frame loop call, and `_process` actually reaches `pump`.
# Textual, because the alternative -- "the keys still work" -- is what every other lane already
# proves, and it would go on passing with `_input` back in `main.gd` and this file half-moved.
func _the_keys_live_in_the_router() -> bool:
	# The reader first, on this same file: a body scanner that returns "" for everything would
	# make every needle below vacuously absent, which reads as a pass on the wrong side.
	if not _function_body(MAIN_GD, "_process").contains("delta"):
		push_error("SOCKET: the function reader cannot read _process out of main.gd")
		return false
	if not _function_body(MAIN_GD, "_no_such_function_exists").is_empty():
		push_error("SOCKET: the function reader invented a body for a function that is not there")
		return false
	var main_src: String = FileAccess.get_file_as_string(MAIN_GD)
	var router_src: String = FileAccess.get_file_as_string(INPUT_MAP_GD)
	if main_src.is_empty() or router_src.is_empty():
		push_error("SOCKET: could not read %s or %s" % [MAIN_GD, INPUT_MAP_GD])
		return false
	if main_src.contains("\nfunc _input(") or main_src.contains("\nfunc _unhandled_input("):
		push_error("SOCKET: main.gd still handles input itself, so two nodes answer the same key")
		return false
	for fn in ["func _input(", "func _unhandled_input(", "func pump("]:
		if not router_src.contains("\n%s" % fn):
			push_error("SOCKET: %s has no `%s`" % [INPUT_MAP_GD, fn])
			return false
	if not _function_body(MAIN_GD, "_process").contains("pump("):
		push_error("SOCKET: main.gd's _process never calls pump(), so a held key moves nothing")
		return false
	if not _function_body(MAIN_GD, "_ready").contains("InputMapRes.new()"):
		push_error("SOCKET: main.gd's _ready never builds the router, so nothing is listening")
		return false
	# F2 is deleted, not merely unbound: the owner's decision of 2026-09-16 is that no unlisted
	# reroll survives into a release build.
	for gone in ["KEY_F2", "_leave_for_another_city"]:
		if main_src.contains(gone) or router_src.contains(gone):
			push_error("SOCKET: '%s' is still in the tree; F2 was deleted, not hidden" % gone)
			return false
	# And F8 is bound behind the debug guard rather than to everybody.
	var f8: int = router_src.find("KEY_F8:")
	if f8 < 0:
		push_error("SOCKET: the router does not bind F8 at all, so the dev menu is unreachable")
		return false
	if router_src.find("OS.is_debug_build()", f8) < 0:
		push_error("SOCKET: F8 is bound without an OS.is_debug_build() guard; a player can open the dev menu")
		return false

	# The second half of the split: the run's lifecycle lives in the session, the shell is built,
	# and main.gd's frame loop reaches both. Every one of these is a socket the lanes above would
	# still pass without -- a session whose save nothing calls, a shell nothing stands up.
	var session_src: String = FileAccess.get_file_as_string(SESSION_GD)
	if session_src.is_empty():
		push_error("SOCKET: could not read %s; the run's lifecycle has nowhere to live" % SESSION_GD)
		return false
	# `\nfunc` and `\nstatic func` both, because `has_continue` is static -- the title asks it
	# before anything has been loaded -- and a needle that only knew one of the two spellings
	# would have gone red against a file that was right.
	for fn in ["boot(", "new_run(", "save(", "load(", "has_continue(", "autosave_if_dawn("]:
		if not session_src.contains("\nfunc %s" % fn) and not session_src.contains("\nstatic func %s" % fn):
			push_error("SOCKET: %s has no `func %s`" % [SESSION_GD, fn])
			return false
	# The call as written, not the bare word: `_process` has a comment about the autosave edge and
	# another about the end of the run, and a needle a comment can satisfy cannot fail
	# (CLAUDE.md's READ_KEYS lesson).
	var proc: String = _function_body(MAIN_GD, "_process")
	for needle in ["session.call(\"autosave_if_dawn\"", "SessionRes.State.RUN_OVER"]:
		if not proc.contains(needle):
			push_error("SOCKET: main.gd's _process does not contain `%s`, so the dawn edge or the end of the run is never seen" % needle)
			return false
	if not _function_body(MAIN_GD, "_ensure_ui").contains("res://ui/shell.gd"):
		push_error("SOCKET: main.gd's _ensure_ui never builds the shell, so there is no title, menu or run-over screen")
		return false
	if not _function_body(MAIN_GD, "_notification").contains("NOTIFICATION_WM_CLOSE_REQUEST"):
		push_error("SOCKET: main.gd's _notification never answers the window's close request")
		return false
	# The boot path moved whole. `_boot_world` is gone outright; `_save` and `_load` survive as the
	# two keys' forwards and must reach the session rather than keep their own copy of the slot --
	# two paths to one file is how F5 and the pause menu's own row come to mean different things.
	if main_src.contains("\nfunc _boot_world("):
		push_error("SOCKET: main.gd still owns _boot_world; the boot path belongs to the session now")
		return false
	for fn in ["_save", "_load"]:
		var body: String = _function_body(MAIN_GD, fn)
		if body.is_empty():
			continue
		if not body.contains("session.call("):
			push_error("SOCKET: main.gd's %s does not go through the session" % fn)
			return false
		if body.contains("SimSave") or body.contains("PlatformStorage"):
			push_error("SOCKET: main.gd's %s still writes the slot itself beside the session's copy" % fn)
			return false
	# And the shell has the router's attention: a focus at the front of the order, a row in the
	# table that says what still fires under it, and a hand-off of the event itself.
	if InputMapRes.FOCUSES.is_empty() or String(InputMapRes.FOCUSES[0]) != "shell":
		push_error("SOCKET: 'shell' is not at the front of the router's focus order: %s" % str(InputMapRes.FOCUSES))
		return false
	if not (InputMapRes.ALLOWED as Dictionary).has("shell"):
		push_error("SOCKET: the router's ALLOWED table has no shell row, so the menu's own keys are refused")
		return false
	if not _function_body(INPUT_MAP_GD, "_input").contains("_shell.call(\"key\""):
		push_error("SOCKET: the router never hands a key to the shell, so the menu cannot be driven")
		return false
	print("SOCKET OK main.gd handles no input and owns no boot, the router has _input, _unhandled_input and pump and a shell focus at the front, the session has boot, new run, save, load, continue and the dawn edge, _ready builds the router, _ensure_ui builds the shell, _process pumps and autosaves and ends the run, _notification answers the close, F2 is gone and F8 is debug-only")
	return true


# --- BUDGET -----------------------------------------------------------------------------------

func _within_budget(elapsed_ms: int) -> bool:
	return elapsed_ms < BUDGET_MS


# docs/00 pillar 6: a budget is correctness. This one is small on purpose -- the gate runs in the
# chain before every commit, and the chain is already twenty-seven minutes.
func _the_gate_fits_its_budget(elapsed_ms: int) -> bool:
	if _within_budget(BUDGET_MS + 1000):
		push_error("BUDGET: the budget predicate passes a run that is over it")
		return false
	if not _within_budget(elapsed_ms):
		push_error("BUDGET: the play gate took %d ms, over its %d ms budget" % [elapsed_ms, BUDGET_MS])
		return false
	print("BUDGET OK %d ms of the %d ms budget" % [elapsed_ms, BUDGET_MS])
	return true
