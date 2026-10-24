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
#   STUBS      the work grid draws the columns that have a consumer, and no others (A15)
#   STOCKPILE  the Colony screen's stockpile block says the read model's words and names, reads
#              none with the pile emptied, carries no digit but an item's name, and its button
#              shows the pile for a picked colonist without moving the pick (stockpile plan, S5)
#   SETTINGS   Escape peels in order -- the legend first, the pause menu only once it is gone,
#              and settings is a row on that menu rather than a key of its own
#   ROUNDTRIP  F5 writes a save F9 restores; a corrupt slot leaves the world untouched
#   CAMP-KEY   C is the camp key and only the camp key; Ctrl+C is the stance and only the stance
#   FOCUS      an open sheet swallows the street's keys, and the body stops at the panel
#   NAV        one navigation bar over Survivor, Colony and Skills: Tab, J and K switch between them
#              in one press and put the one in front away; a click on a tab does the same and a
#              click on the bar's free room does nothing; Escape closes a screen about people
#              rather than opening settings over it, and on the sheet it puts a picked part down
#              before it closes anything; the street's HUD is never lit under any of the three
#   PAUSE      Escape on the street pauses to the menu and gives the street back
#   NOTICE     a save this build cannot read leaves the run alone and says one fixed sentence
#   HINT       a first-day hint is offered on the street, a click on its card clears it, and the
#              seen mark rides the slot F5 writes and F9 reads back
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
#   BENCH      the assembly screen (UI overhaul, slice 3) at 1280x720 and 1920x1080: E at a bench
#              with a rifle opens it; its frame is inside the window, where the fixed rect it
#              replaced is not at 720; a click on a plate then a candidate fits it, "take off"
#              detaches, the arrows and Enter do the same from the keys; a click on the wash
#              swings at nothing; every word drawn is digit-free but an item's name; Escape closes
#              it and clears `benchFocus`
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
const Chrome = preload("res://ui/chrome.gd")
const UiPrefs = preload("res://ui/prefs.gd")
const InputMapRes = preload("res://presentation/input_map.gd")
const Session = preload("res://presentation/session.gd")
const Onboarding = preload("res://presentation/onboarding.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const SimOrders = preload("res://sim/modules/orders.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimChronicle = preload("res://sim/modules/chronicle.gd")
const SimRecruits = preload("res://sim/modules/recruits.gd")
const SimAllegiance = preload("res://sim/modules/allegiance.gd")
const SimSave = preload("res://sim/save.gd")
const SimSurvivors = preload("res://sim/modules/survivors.gd")
const WorkRead = preload("res://sim/work_read.gd")
const UiText = preload("res://ui/text.gd")
const SimGunsmith = preload("res://sim/modules/gunsmith.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimAttachments = preload("res://sim/modules/attachments.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const ReviewScenes = preload("res://review/scenes.gd")
const CheckInventory = preload("res://check_inventory.gd")
const BenchPanel = preload("res://ui/bench_panel.gd")

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
	["J", "J opens Work, whose priority cells fit the window"],
	["Ctrl+C", "Ctrl+C crouches"],
	["Ctrl+S", "Ctrl+S stands"],
	["F", "F swings, and does not while the sheet is open"],
	["X", "X drafts the colonist you picked, and again sets them free"],
]

# The two actions `input_map.gd` binds that the legend deliberately does not name, each excused
# here by name and with the reason. The allowlist is the point: a third unlisted binding cannot
# arrive quietly, because adding one means writing down why it is not on the sheet a player reads.
const UNLISTED: Dictionary = {
	"dismiss": "Enter closes the legend and opens nothing; the panel's own header names F1",
	"debug": "F8 is the dev spawn menu, bound only under OS.is_debug_build()",
	"sheets": "M is the raw developer sheet, bound only under OS.is_debug_build() (A22)",
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
	ok = await _the_body_card_clears_the_you_card(main) and ok
	ok = await _the_work_grid_fits_and_keeps_its_clicks(main) and ok
	ok = await _the_work_grid_draws_only_what_something_does(main) and ok
	ok = await _the_colony_screen_is_one_survivor_context(main) and ok
	ok = await _the_colony_screen_reads_the_stockpile(main) and ok
	var sheet_ok: bool = await _tab_opens_the_sheet(main)
	ok = sheet_ok and ok
	var peel_ok: bool = await _escape_peels_in_order(main)
	ok = peel_ok and ok
	ok = _f5_and_f9_round_trip(main) and ok
	var hint_ok: bool = await _a_first_day_hint_shows_clears_and_saves(main)
	ok = hint_ok and ok
	ok = _c_is_the_camp_key_and_ctrl_c_is_the_stance(main) and ok
	ok = _x_drafts_the_colonist_picked(main) and ok
	var focus_ok: bool = await _the_open_sheet_swallows_the_street(main)
	ok = focus_ok and ok
	var nav_ok: bool = await _one_bar_reaches_all_three_screens(main)
	ok = nav_ok and ok
	var menu_ok: bool = await _escape_closes_the_menu_first(main)
	ok = menu_ok and ok
	var pause_ok: bool = await _escape_pauses_to_the_menu(main)
	ok = pause_ok and ok
	var notice_ok: bool = await _a_refused_save_says_one_sentence(main)
	ok = notice_ok and ok
	ok = _the_volume_row_reaches_the_bus(main) and ok
	ok = _the_clock_says_its_speed_and_sleep_skips(main) and ok
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
	# Its own scene: it puts a rifle and a pack on the survivor and a bench in the house.
	var bench_ok: bool = await _the_bench_opens_fits_and_closes()
	ok = bench_ok and ok

	_restore_user_files()
	var elapsed: int = Time.get_ticks_msec() - _started_ms
	ok = _the_gate_fits_its_budget(elapsed) and ok

	if ok:
		var skipped: String = "no lane skipped" if _skips.is_empty() else "skipped: %s" % ", ".join(PackedStringArray(_skips))
		print("PLAY_OK the scene boots to a title over a still world, ticks, walks, opens its screens, saves and loads, camps on C and crouches on Ctrl+C, refuses the street's keys under an open sheet, pauses to a menu on Escape, moves the audio bus, names its speed and sleeps through the night unless something is near, writes the slot at dawn and on the window's close, ends on a screen that speaks the chronicle and starts again, keeps a dismissed legend dismissed, offers a first-day hint that a click clears and a save keeps seen, and draws by day and by night in %d ms (%s)" % [elapsed, skipped])
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


# --- LIVABLE TIME -----------------------------------------------------------------------------

# The clock's speed is words on the HUD and a step in the loop. The lane asks the loop how far a
# frame carries the world at each speed (the frames are deterministic: each one is a fixed tick),
# the HUD what it says, and the sim whether anything living is within ten metres of a sleeper. A
# words-only lane would pass with the loop ignoring sleep; a loop-only lane would pass with the HUD
# silent. Both halves are asserted.
func _the_clock_says_its_speed_and_sleep_skips(main: Node) -> bool:
	var world: Variant = main.get("world")
	var hud: Variant = main.get("_hud")
	main.set("paused", false)
	main.set("speed", 1)
	_frames(main, 2)
	if str(hud.get("time_words")) != "normal speed":
		push_error("CLOCK: at 1x the HUD says '%s', not 'normal speed'" % str(hud.get("time_words")))
		return false
	_tap(KEY_EQUAL)
	_frames(main, 1)
	if int(main.get("speed")) != 3 or str(hud.get("time_words")) != "fast":
		push_error("CLOCK: '=' left the speed at %d and the HUD saying '%s', not 3 and 'fast'" % [int(main.get("speed")), str(hud.get("time_words"))])
		return false
	var before: int = int(world.tick)
	_frames(main, 20)
	if int(world.tick) - before != 60:
		push_error("CLOCK: 20 frames at fast advanced the world %d ticks, not 60" % (int(world.tick) - before))
		return false
	_tap(KEY_P)
	_frames(main, 1)
	if str(hud.get("time_words")) != "paused":
		push_error("CLOCK: a paused clock says '%s', not 'paused'" % str(hud.get("time_words")))
		return false
	_tap(KEY_P)
	_tap(KEY_MINUS)
	# Asleep with nothing near: the loop runs at the sleep step whatever the user chose. The boot
	# street has zombies in it, so the lane clears the living ones within ten metres first.
	var player: int = int(world.player)
	var here: Variant = world.components.get_component(player, "position")
	for e in world.components.query(["position", "shambler"]):
		var there: Variant = world.components.get_component(int(e), "position")
		if world.entities.is_alive(int(e)) and there is Dictionary and Vector2(float(there["x"]) - float(here["x"]), float(there["y"]) - float(here["y"])).length() <= Session.THREAT_METRES:
			world.despawn(int(e))
	SimNeeds._start_sleep(world, player, -1)
	_frames(main, 1)
	if str(hud.get("time_words")) != "asleep, fast-forwarding":
		push_error("CLOCK: asleep with nothing near the HUD says '%s'" % str(hud.get("time_words")))
		return false
	before = int(world.tick)
	_frames(main, 20)
	if int(world.tick) - before != 60:
		push_error("CLOCK: 20 frames asleep at 1x advanced the world %d ticks, not 60" % (int(world.tick) - before))
		return false
	# A living zombie five metres off stops it, and the loop drops back to the user's own step.
	var at: Variant = world.components.get_component(player, "position")
	var zombie: int = world.entities.spawn()
	world.components.set_component(zombie, "position", {"x": float(at["x"]) + 5.0, "y": float(at["y"])})
	# Built the way the sim builds one, so the body carries the state the sim reads every tick.
	SimShambler.make_shambler(world, zombie, world.rng.stream("shambler"))
	_frames(main, 1)
	if str(hud.get("time_words")) != "asleep, zombie near, normal speed":
		push_error("CLOCK: a zombie five metres off, the HUD says '%s'" % str(hud.get("time_words")))
		return false
	before = int(world.tick)
	_frames(main, 20)
	if int(world.tick) - before != 20:
		push_error("CLOCK: a zombie near advanced the world %d ticks in 20 frames, not 20" % (int(world.tick) - before))
		return false
	# A despawned body keeps its components. It must not hold the fast-forward back.
	world.despawn(zombie)
	_frames(main, 1)
	if str(hud.get("time_words")) != "asleep, fast-forwarding":
		push_error("CLOCK: a dead zombie still stops the sleep, the HUD says '%s'" % str(hud.get("time_words")))
		return false
	world.components.remove_component(player, "sleeping")
	_frames(main, 1)
	if str(hud.get("time_words")) != "normal speed":
		push_error("CLOCK: awake again at 1x the HUD says '%s'" % str(hud.get("time_words")))
		return false
	print("CLOCK OK 1x, 3x and paused read in words; asleep runs 60 ticks a 20-frame stretch, a living zombie within ten metres drops it to 20, a dead one does not")
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


# --- HINT -------------------------------------------------------------------------------------

# The first-day hint, played through the real path: a wounded survivor on the street is offered the wound
# hint on a frame the HUD draws, a real left click on its card clears it through the engine's input
# dispatch, and the seen set is written into the slot F5 writes and comes back out of F9. The injuries
# are put back afterwards, so no later lane inherits a bleed it did not ask for.
func _a_first_day_hint_shows_clears_and_saves(main: Node) -> bool:
	var world: Variant = main.get("world")
	var hud: Variant = main.get("_hud")
	var session_now: Variant = main.get("session")
	if _state(main) != Session.State.PLAYING or hud == null or bool(main.get("paused")) or not bool(hud.visible):
		return _skip("HINT", "the street is not up, so no frame can offer a hint")
	var before: Variant = world.components.get_component(world.player, "injuries")
	var pristine: Variant = (before as Dictionary).duplicate(true) if before is Dictionary else null
	session_now.onboarding.reset()
	SimWounds.append_wound(world, world.player, "laceration", "torso", -1, 30.0)
	_frames(main, 2)
	await process_frame
	var shown: String = String(hud.get("_onboarding_line"))
	if shown != Onboarding.prose_of("wound"):
		push_error("HINT: a wounded survivor on the street was offered '%s', not the wound hint" % shown)
		return false
	var rect: Rect2 = hud.get("_hint_rect")
	if rect.size == Vector2.ZERO:
		push_error("HINT: the wound hint was on screen but drew no card to click")
		return false
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = rect.get_center()
	root.push_input(click)
	await process_frame
	_frames(main, 2)
	await process_frame
	# Not the wound any more. Another hint may come due in its place (a zombie seen on the way here, say),
	# and that is the next hint speaking, not this one left up.
	if String(hud.get("_onboarding_line")) == Onboarding.prose_of("wound"):
		push_error("HINT: a click on the hint's card left the wound hint up")
		return false
	_tap(KEY_F5)
	var decoded: Dictionary = SimSave.decode_save(FileAccess.get_file_as_string(SAVE_PATH))
	if decoded.has("__error") or not (decoded.get("onboarding", []) as Array).has("wound"):
		push_error("HINT: the slot F5 wrote does not carry the wound hint as seen")
		return false
	session_now.onboarding.reset()
	_tap(KEY_F9)
	_frames(main, 2)
	await process_frame
	if not (session_now.onboarding.to_save() as Array).has("wound"):
		push_error("HINT: F9 did not bring the seen wound hint back")
		return false
	if String(hud.get("_onboarding_line")) == Onboarding.prose_of("wound"):
		push_error("HINT: a save that had told its player the wound hint offered it again")
		return false
	if pristine != null:
		world.components.set_component(world.player, "injuries", pristine)
	else:
		world.components.set_component(world.player, "injuries", {"wounds": [], "bloodLoss": 0.0, "bledOut": false})
	print("HINT OK the wound hint is offered on the street, a click on its card clears it, and the seen mark goes into the slot and comes back out of F9 without offering it again")
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


# --- DRAFT ------------------------------------------------------------------------------------

# X drafts the colonist picked on the street: the first press holds them where they stand, the
# second sets them free. With nobody picked the press pushes nothing at all, and the pushed
# command is the one the sim's `SimOrders.draft_command` decides, judged here by its shape.
func _x_drafts_the_colonist_picked(main: Node) -> bool:
	var world: Variant = main.get("world")
	var mara: int = -1
	for e in world.components.query(["identity"]):
		var ident: Variant = world.components.get_component(int(e), "identity")
		if ident is Dictionary and String((ident as Dictionary).get("id", "")) == "survivor.unique.mara":
			mara = int(e)
	if mara < 0:
		return _skip("DRAFT", "the boot colony has no Mara to draft")
	main.set("_selected", -1)
	_drain(main)
	_tap(KEY_X)
	if not _pending(main).is_empty():
		push_error("DRAFT: X with nobody picked pushed %d command(s)" % _pending(main).size())
		return false
	main.set("_selected", mara)
	_drain(main)
	_tap(KEY_X)
	var held: Array = _pending(main)
	var held_ok: bool = held.size() == 1 and String((held[0] as Dictionary).get("kind", "")) == "hold" and int((held[0] as Dictionary).get("entity", -1)) == mara
	# Left pending on purpose: the frames below are what the sim takes it with.
	_frames(main, 2)
	var on_record: bool = SimOrders.holds(world, mara)
	_tap(KEY_X)
	var freed: Array = _pending(main)
	var freed_ok: bool = freed.size() == 1 and String((freed[0] as Dictionary).get("kind", "")) == "clear" and int((freed[0] as Dictionary).get("entity", -1)) == mara
	_drain(main)
	main.set("_selected", -1)
	if not held_ok or not on_record or not freed_ok:
		push_error("DRAFT: the first press pushed a hold %s and held Mara %s; the second press pushed a clear %s" % [held_ok, on_record, freed_ok])
		return false
	print("DRAFT OK X holds the colonist you picked where they stand, X again sets them free, and nothing is pushed with nobody picked")
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
# --- NAV ----------------------------------------------------------------------------------------

# The shared navigation frame of the UI overhaul's first slice (docs/32, "Navigation and layout").
# Driven the way a player drives it: real key presses and real clicks through the viewport, and the
# answer read off main.gd's own flags and the bar's own visibility.
func _one_bar_reaches_all_three_screens(main: Node) -> bool:
	var nav: Control = main.get("_nav_bar") as Control
	var hud: Control = main.get("_hud") as Control
	var sheet: Control = main.get("_inventory_panel") as Control
	if nav == null or hud == null or sheet == null or main.get("_work_panel") == null or main.get("_web_panel") == null:
		return _skip("NAV", "the scene built no navigation bar, HUD or one of the three screens")
	var NavBar: GDScript = load("res://ui/nav_bar.gd") as GDScript
	# The headless window is tiny; the clicks below want the smallest window the game ships at, where
	# the bar is in its compact form and every tab still has to fit.
	var old_size: Vector2i = root.size
	root.size = Vector2i(1280, 720)
	main.call("_show_screen", "")
	await process_frame
	var ok: bool = true
	# Keys: a walk round all three and back to the street.
	var walk: Array = [
		[KEY_TAB, "survivor"], [KEY_J, "colony"], [KEY_K, "skills"], [KEY_TAB, "survivor"],
		[KEY_K, "skills"], [KEY_J, "colony"], [KEY_J, ""],
	]
	for step in walk:
		_tap(step[0] as Key)
		await process_frame
		var want: String = String(step[1])
		var up: String = String(main.call("_screen"))
		var open: int = int(bool(main.get("inventory_open"))) + int(bool(main.get("work_open"))) + int(bool(main.get("web_open")))
		if up != want or open != (0 if want.is_empty() else 1):
			push_error("NAV: %s left %s up (%d screens open), not %s" % [OS.get_keycode_string(step[0] as Key), up, open, want if not want.is_empty() else "the street"])
			ok = false
		if hud.visible != want.is_empty():
			push_error("NAV: the HUD is %s with %s up" % ["lit" if hud.visible else "dark", want if not want.is_empty() else "the street"])
			ok = false
		var bar_up: bool = want == "colony" or want == "skills"
		if nav.visible != bar_up or (bar_up and String(nav.get("screen")) != want):
			push_error("NAV: the bar over %s is %s and names %s" % [want, "up" if nav.visible else "down", String(nav.get("screen"))])
			ok = false
		if bool(sheet.get("strip_hidden")) != bar_up:
			push_error("NAV: the belt strip is %s with %s up" % ["put away" if bool(sheet.get("strip_hidden")) else "lit", want if not want.is_empty() else "the street"])
			ok = false
	# Escape on Colony goes to the street, and opens no settings sheet and no menu over it.
	_tap(KEY_J)
	await process_frame
	_tap(KEY_ESCAPE)
	await process_frame
	var settings: Variant = main.get("_settings")
	if not String(main.call("_screen")).is_empty() or (settings != null and bool((settings as CanvasItem).visible)) or bool((_shell_of(main) as CanvasItem).visible if _shell_of(main) != null else false):
		push_error("NAV: Escape on Colony left %s up, settings %s" % [String(main.call("_screen")), str(settings != null and bool((settings as CanvasItem).visible))])
		ok = false
		if settings != null:
			(settings as CanvasItem).visible = false
	# Clicks on the bar over Skills: the Colony tab, then the free room (nothing), then close.
	_tap(KEY_K)
	await process_frame
	# Whose page: the bar and the web name the same person -- you, then a colonist picked on the
	# street while Skills is up -- and the web sits wholly inside the 1280x720 window.
	var web: Control = main.get("_web_panel") as Control
	var world: Variant = main.get("world")
	if not bool(nav.get("subject_is_you")) or not String(web.call("header_label")).ends_with("you"):
		push_error("NAV: Skills on yourself shows the bar's stamp for you %s and the web's %s" % [str(nav.get("subject_is_you")), String(web.call("header_label"))])
		ok = false
	if not Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(web.get_global_rect()):
		push_error("NAV: the skill web %s runs past the %s window" % [str(web.get_global_rect()), str(root.get_visible_rect().size)])
		ok = false
	var other: int = -1
	for e in world.components.query(["identity", "position"]):
		if int(e) != int(world.player) and not world.components.has_component(int(e), "corpse"):
			other = int(e)
			break
	if other < 0:
		print("NAV SKIP viewing: the boot colony has nobody but you to pick")
	else:
		main.set("_selected", other)
		main.call("_sync_nav")
		var their: String = String(main.call("_name_for", other))
		var laid_v: Dictionary = NavBar.call("layout", Rect2(Vector2.ZERO, nav.size), "skills", String(nav.get("subject_name")), bool(nav.get("subject_is_you")), true) as Dictionary
		if bool(nav.get("subject_is_you")) or String(nav.get("subject_name")) != their or String(laid_v["stamp"]) != "viewing" or not String(web.call("header_label")).ends_with(their):
			push_error("NAV: a colonist picked over Skills shows the bar naming %s (%s) and the web %s, not %s viewing" % [String(nav.get("subject_name")), String(laid_v["stamp"]), String(web.call("header_label")), their])
			ok = false
		main.set("_selected", -1)
		main.call("_sync_nav")
		if not bool(nav.get("subject_is_you")) or not String(web.call("header_label")).ends_with("you"):
			push_error("NAV: putting the colonist down left the bar and the web on %s" % String(web.call("header_label")))
			ok = false
	var compact: bool = bool(NavBar.call("compact_for", root.get_visible_rect().size))
	var laid: Dictionary = NavBar.call("layout", Rect2(Vector2.ZERO, nav.size), "skills", String(nav.get("subject_name")), bool(nav.get("subject_is_you")), compact) as Dictionary
	var colony_at: Vector2 = Vector2(-1.0, -1.0)
	for t in laid["tabs"] as Array:
		if String((t as Dictionary)["screen"]) == "colony":
			colony_at = nav.global_position + ((t as Dictionary)["rect"] as Rect2).get_center()
	var free_at: Vector2 = nav.global_position + Vector2((float(laid["left"]) + float(laid["right"])) / 2.0, nav.size.y / 2.0)
	_click_at(free_at)
	await process_frame
	if String(main.call("_screen")) != "skills":
		push_error("NAV: a click on the bar's free room moved Skills to %s" % String(main.call("_screen")))
		ok = false
	_click_at(colony_at)
	await process_frame
	if String(main.call("_screen")) != "colony":
		push_error("NAV: a click on the Colony tab over Skills left %s up" % String(main.call("_screen")))
		ok = false
	var laid2: Dictionary = NavBar.call("layout", Rect2(Vector2.ZERO, nav.size), "colony", "", false, compact) as Dictionary
	_click_at(nav.global_position + (laid2["close"] as Rect2).get_center())
	await process_frame
	if not String(main.call("_screen")).is_empty():
		push_error("NAV: a click on close over Colony left %s up" % String(main.call("_screen")))
		ok = false
	# The sheet draws the same bar in its own title strip: its Skills tab, then Escape's order.
	_tap(KEY_TAB)
	await process_frame
	var on_sheet: Dictionary = sheet.call("_nav_layout") as Dictionary
	for t in on_sheet["tabs"] as Array:
		if String((t as Dictionary)["screen"]) == "skills":
			_click_at(sheet.global_position + ((t as Dictionary)["rect"] as Rect2).get_center())
	await process_frame
	if String(main.call("_screen")) != "skills":
		push_error("NAV: a click on the sheet's Skills tab left %s up" % String(main.call("_screen")))
		ok = false
	_tap(KEY_TAB)
	await process_frame
	sheet.set("_part", "head")
	_tap(KEY_ESCAPE)
	await process_frame
	if not bool(main.get("inventory_open")) or not String(sheet.get("_part")).is_empty():
		push_error("NAV: Escape on the sheet with a part picked did not put the part down and stop there")
		ok = false
	_tap(KEY_ESCAPE)
	await process_frame
	if bool(main.get("inventory_open")):
		push_error("NAV: a second Escape did not close the sheet")
		ok = false
	if settings != null and bool((settings as CanvasItem).visible):
		push_error("NAV: Escape on the sheet opened the settings sheet over it")
		ok = false
		(settings as CanvasItem).visible = false
	# The street's keys stay refused under the two new screens, the focus table's own negative.
	var router: Node = _router(main)
	for focus in ["work", "web"]:
		if bool(router.call("_allows", focus, "swing")):
			push_error("NAV: the %s focus lets a swing through" % focus)
			ok = false
		for k in ["inventory", "work", "web"]:
			if not bool(router.call("_allows", focus, k)):
				push_error("NAV: the %s focus refuses %s, so the bar's key cannot switch from it" % [focus, k])
				ok = false
	main.call("_show_screen", "")
	root.size = old_size
	await process_frame
	if ok:
		print("NAV OK Tab, J and K switch between Survivor, Colony and Skills in one press and put the one in front away, with one screen up, the HUD dark under each and the belt strip put away under Colony and Skills; the bar and the web name the same person, you or a colonist viewing, and the web fits the window; a tab click switches, the free room does nothing and close goes to the street; the sheet's own bar reaches Skills; Escape closes Colony without settings and on the sheet puts a picked part down first; the street's swing stays refused under both new screens")
	return ok


func _click_at(at: Vector2) -> void:
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.position = at
		mb.global_position = at
		root.push_input(mb)


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
	# X is the draft key now (2026-10-24), so it is no longer a stale stance key; the old ladder row
	# "Z / X / C / V" still is, and it is the one that would name X as a stance.
	for stale in ["Z / X / C / V", "Z", "V"]:
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
	# And M, the raw sheet, is guarded the same way (A22): a release build has no key for it.
	var m_key: int = router_src.find("KEY_M:")
	if m_key < 0 or router_src.find("OS.is_debug_build()", m_key) < 0 or router_src.find("OS.is_debug_build()", m_key) > router_src.find("main.show_sheets", m_key):
		push_error("SOCKET: M toggles the raw sheet without an OS.is_debug_build() guard in front of it")
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


# The Work grid's visible cells and actual mouse dispatch share the responsive width.
# The corner glimpse must clear the panel even while P has stopped the simulation.
# The six job columns nothing does (alpha plan A15). The sim still stores their numbers, so this
# lane judges what the grid draws and what its first cell does, not the sim's own dictionary.
const STUB_COLUMNS: Array[String] = ["Firefight", "Hunt", "Farm", "Craft", "Modify", "Butcher"]


func _the_work_grid_draws_only_what_something_does(main: Node) -> bool:
	var panel: Control = main.get("_work_panel") as Control
	var was_paused: bool = bool(main.get("paused"))
	var old_size: Vector2i = root.size
	main.set("paused", true)
	# The grid lays itself out on a viewport change only, and the lane before this one leaves the
	# window at whatever it was restored to, so this lane lays out at the window it means to judge.
	root.size = Vector2i(1920, 1080)
	await process_frame
	var jobs: GDScript = load("res://sim/modules/jobs.gd") as GDScript
	var all: Array = jobs.get("COLUMNS") as Array
	var consumers: Array = jobs.get("CONSUMERS") as Array
	var shown: Array = (panel.get_script() as GDScript).call("shown_columns") as Array
	var expected: Array = all.filter(func(c: Variant) -> bool: return consumers.has(c))
	var ok: bool = true
	# The grid's order is the groups' (UI overhaul, slice 2), so the columns are judged as a set:
	# every column with a consumer exactly once, and nothing else.
	var sorted_shown: Array = shown.duplicate()
	sorted_shown.sort()
	var sorted_expected: Array = expected.duplicate()
	sorted_expected.sort()
	if sorted_shown != sorted_expected:
		push_error("STUBS: the grid draws %s, not the columns with a consumer, %s" % [str(shown), str(expected)])
		ok = false
	for stub in STUB_COLUMNS:
		if shown.has(stub):
			push_error("STUBS: the grid still draws %s, which nothing does" % stub)
			ok = false
		if consumers.has(stub):
			push_error("STUBS: %s is listed as a consumer, so it cannot be a stub" % stub)
			ok = false
	_tap(KEY_J)
	main.call("_process", 0.0)
	await process_frame
	if not panel.visible:
		push_error("STUBS: Work did not open")
		ok = false
	else:
		var edges: Array = panel.call("_column_edges") as Array
		var grid_y: float = float(panel.get_script().get("GRID_Y"))
		var at: Vector2 = panel.position + Vector2((float(edges[0]) + float(edges[1])) / 2.0, grid_y + 28.0)
		_drain(main)
		for down in [true, false]:
			var press := InputEventMouseButton.new()
			press.button_index = MOUSE_BUTTON_LEFT
			press.pressed = down
			press.position = at
			root.push_input(press)
		var edits: Array = _pending(main).filter(func(command: Variant) -> bool: return String((command as Dictionary).get("type", "")) == "job.priority")
		if edits.size() != 1 or String((edits[0] as Dictionary).get("column", "")) != String(shown[0]):
			push_error("STUBS: the first cell did not queue the first column the grid draws")
			ok = false
		_drain(main)
	_tap(KEY_J)
	main.call("_process", 0.0)
	await process_frame
	if panel.visible:
		push_error("STUBS: closing Work left it open")
		ok = false
	root.size = old_size
	main.set("paused", was_paused)
	await process_frame
	if ok:
		print("STUBS OK the grid draws the %d columns with a consumer and none of the six that do nothing, and its first cell queues the first of them" % shown.size())
	return ok


# The street's body card and the "you" card never overlap, however many lines the "you" card
# grows, and the body card stops short of the action bar and lines up with the belt at x 16 (UI
# review round 3: a two-line "you" card ran over the card's top at 1280x720, and the card's foot
# touched the bar). A "you" card that reaches the body card starts right of it; one that ends
# above it stays at the margin (round 4: at 1920x1080 an indented card hung beside an empty
# strip). Judged on the rects the two draws use, at both windows, with one line and with five.
# The negative: with no body card to make room for, the five-line card overlaps it at 1280x720.
func _the_body_card_clears_the_you_card(main: Node) -> bool:
	var hud: Control = main.get("_hud") as Control
	var doll: Control = main.get("_paperdoll") as Control
	if hud == null or doll == null or hud.get("body_card") != doll:
		push_error("HUD-CARDS: the scene has no HUD, no street figure, or a HUD that does not know the figure")
		return false
	var old_size: Vector2i = root.size
	var old_left: Array = (hud.get("_left") as Array).duplicate()
	var margin: float = float(hud.get_script().get("MARGIN"))
	var short: Array[String] = ["You"]
	var crowded: Array[String] = ["You", "You're uncomfortable - cold.", "hungry", "tired", "your left arm is bleeding"]
	var ok: bool = true
	var indented: Dictionary = {}
	for dims in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = dims
		await process_frame
		var card: Rect2 = doll.call("card_rect") as Rect2
		card.position += doll.get_global_rect().position
		if card.end.y > float(hud.call("bar_top")) - 2.0 or int(card.position.x) != 16:
			push_error("HUD-CARDS: the body card %s touches the action bar at %.0f or is not at x 16 (%s)" % [str(card), float(hud.call("bar_top")), str(dims)])
			ok = false
		for lines in [short, crowded]:
			hud.set("_left", lines)
			var you: Rect2 = hud.call("you_card_rect") as Rect2
			if card.intersects(you):
				push_error("HUD-CARDS: the body card %s and a %d-line you card %s overlap at %s" % [str(card), lines.size(), str(you), str(dims)])
				ok = false
			# Indented exactly when the card at the margin would reach the body card.
			var reaches: bool = margin + you.size.y + 16.0 > card.position.y
			if (you.position.x > margin) != reaches:
				push_error("HUD-CARDS: a %d-line you card is at x %.0f where the body card's top is %.0f (%s)" % [lines.size(), you.position.x, card.position.y, str(dims)])
				ok = false
			indented["%dx%d/%d" % [dims.x, dims.y, lines.size()]] = you.position.x > margin
		if dims.y == 720:
			hud.set("_left", crowded)
			hud.set("body_card", null)
			var old_way: Rect2 = hud.call("you_card_rect") as Rect2
			hud.set("body_card", doll)
			if not card.intersects(old_way):
				push_error("HUD-CARDS: a five-line you card from the margin clears the body card, so the check cannot fail")
				ok = false
	hud.set("_left", old_left)
	root.size = old_size
	await process_frame
	if not (bool(indented.get("1280x720/5", false)) and not bool(indented.get("1920x1080/5", true)) and not bool(indented.get("1280x720/1", true))):
		push_error("HUD-CARDS: expected the five-line card indented at 1280 only and the one-line card at the margin: %s" % str(indented))
		ok = false
	if ok:
		print("HUD-CARDS OK the you card makes room for the body card only when it would reach it (five lines at 1280x720, never at 1920x1080), the body card lines up at x 16 and stops short of the action bar; with no body card to make room for, the five-line card overlaps it")
	return ok


func _the_work_grid_fits_and_keeps_its_clicks(main: Node) -> bool:
	var panel: Control = main.get("_work_panel") as Control
	var doll: Control = main.get("_paperdoll") as Control
	var old_size: Vector2i = root.size
	var was_paused: bool = bool(main.get("paused"))
	main.set("paused", true)
	var ok: bool = true
	for dims in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = dims
		await process_frame
		_tap(KEY_J)
		main.call("_process", 0.0)
		await process_frame
		if not panel.visible or doll.visible or not Rect2(Vector2.ZERO, Vector2(dims)).encloses(panel.get_rect()):
			push_error("WORK-LAYOUT: Work is outside the viewport or covered by the corner chart at %s" % str(dims))
			ok = false
		var edges: Array = panel.call("_column_edges") as Array
		var grid_y: float = float(panel.get_script().get("GRID_Y"))
		var columns: Array = (panel.get_script() as GDScript).call("shown_columns") as Array
		var last: int = columns.size() - 1
		var at: Vector2 = panel.position + Vector2((float(edges[last]) + float(edges[last + 1])) / 2.0, grid_y + 28.0)
		# The grid uses the panel's width (UI review round 2: it stopped 200 px short at 1280 and
		# 460 at 1920 while the heads and taglines were cut): it ends at the right gutter, and
		# every column is at least its own head plus the gap, so no head is cut and no two read
		# as one. Both are checked against the drawn edges, which the click math also reads.
		var gutter: float = float(panel.get_script().get("GUTTER"))
		var gap: float = float(panel.get_script().get("COL_GAP"))
		if absf(float(edges[edges.size() - 1]) - (panel.size.x - gutter)) > 2.0:
			push_error("WORK-LAYOUT: the grid stops at %.0f, short of the panel's right gutter at %.0f (%s)" % [float(edges[edges.size() - 1]), panel.size.x - gutter, str(dims)])
			ok = false
		var font: Font = Chrome.font()
		for i in columns.size():
			var head_w: float = font.get_string_size(String(columns[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(panel.get("head_size"))).x
			if float(edges[i + 1]) - float(edges[i]) < head_w + gap or int(edges[i]) % 2 != 0:
				push_error("WORK-LAYOUT: column %s is %.0f px from x %.0f, under its head plus the gap (%.0f) or off the even grid (%s)" % [columns[i], float(edges[i + 1]) - float(edges[i]), float(edges[i]), head_w + gap, str(dims)])
				ok = false
		if not panel.get_rect().has_point(at):
			push_error("WORK-LAYOUT: the last priority cell is outside the frame")
			ok = false
		_drain(main)
		for down in [true, false]:
			var press := InputEventMouseButton.new()
			press.button_index = MOUSE_BUTTON_LEFT
			press.pressed = down
			press.position = at
			root.push_input(press)
		var edits: Array = _pending(main).filter(func(command: Variant) -> bool: return String((command as Dictionary).get("type", "")) == "job.priority")
		if edits.size() != 1 or String((edits[0] as Dictionary).get("column", "")) != String(columns[last]):
			push_error("WORK-LAYOUT: clicking the visible last cell did not queue exactly its priority")
			ok = false
		_drain(main)
		if dims.x == 1280:
			# The boot's two survivors cannot overflow. Repeat real rows for a taller view,
			# with the other real entity last so an unscrolled click cannot accidentally pass.
			var real_rows: Array = panel.get("_rows") as Array
			var crowded: Array[Dictionary] = []
			for i in 8:
				crowded.append((real_rows[0] as Dictionary).duplicate(true))
			crowded[crowded.size() - 1] = (real_rows[1] as Dictionary).duplicate(true)
			panel.set("_rows", crowded)
			panel.call("_sync_layout")
			await process_frame
			var visible_rows: int = int(panel.call("_visible_rows"))
			if visible_rows >= crowded.size():
				push_error("WORK-LAYOUT: crowd fixture did not overflow; no scrolling judged")
				ok = false
			var wheel := InputEventMouseButton.new()
			wheel.pressed = true
			wheel.position = panel.position + Vector2(float(edges[0]) + 4.0, grid_y + 4.0)
			wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
			for i in crowded.size() + 2:
				root.push_input(wheel)
			await process_frame
			if int(panel.get("_row_scroll")) != crowded.size() - visible_rows:
				push_error("WORK-LAYOUT: wheel did not clamp at the last survivor")
				ok = false
			var row_h: float = float(panel.get_script().get("ROW_H"))
			var last_at: Vector2 = panel.position + Vector2((float(edges[last]) + float(edges[last + 1])) / 2.0, grid_y + float(visible_rows - 1) * row_h + 28.0)
			for down in [true, false]:
				var press := InputEventMouseButton.new()
				press.button_index = MOUSE_BUTTON_LEFT
				press.pressed = down
				press.position = last_at
				root.push_input(press)
			var after_scroll: Array = _pending(main).filter(func(command: Variant) -> bool: return String((command as Dictionary).get("type", "")) == "job.priority")
			var last_entity: int = int(crowded[crowded.size() - 1]["entity"])
			if after_scroll.size() != 1 or int((after_scroll[0] as Dictionary).get("entity", -1)) != last_entity or String((after_scroll[0] as Dictionary).get("column", "")) != String(columns[last]):
				push_error("WORK-LAYOUT: scrolled priority click did not target the displayed last survivor")
				ok = false
			_drain(main)
			wheel.button_index = MOUSE_BUTTON_WHEEL_UP
			for i in crowded.size() + 2:
				root.push_input(wheel)
			if int(panel.get("_row_scroll")) != 0:
				push_error("WORK-LAYOUT: wheel did not clamp back at the first survivor")
				ok = false
			panel.call("set_world", main.get("world"))
		_tap(KEY_J)
		main.call("_process", 0.0)
		await process_frame
		if panel.visible or not doll.visible:
			push_error("WORK-LAYOUT: closing Work did not restore the street's chart")
			ok = false
		_tap(KEY_K)
		main.call("_process", 0.0)
		if doll.visible:
			push_error("WORK-LAYOUT: the chart paints over the skill web")
			ok = false
		_tap(KEY_K)
		main.call("_process", 0.0)
		if not doll.visible:
			push_error("WORK-LAYOUT: closing the skill web did not restore the chart")
			ok = false
	root.size = old_size
	main.set("paused", was_paused)
	await process_frame
	if ok:
		print("WORK-LAYOUT OK Work fits 1280/1920 with every column at least its head plus the gap and the grid at the right gutter, the last visible cell receives the click, scrolling reaches both ends and clicks the displayed survivor, Work/web peel the corner chart and restore it while paused")
	return ok



# --- COLONY ---------------------------------------------------------------------------------------

# The Colony screen as one survivor context (UI overhaul, slice 2; docs/32's roster row: "persistent
# identity, readable job groups, explicit priority controls and Focus choices; details open from the
# selected person"). In the real scene at 1280x720 and 1920x1080, through real clicks:
#   - the panel sits under the bar on the even grid and inside the window;
#   - the groups hold every column with a consumer exactly once, and the footer names exactly the
#     job columns nothing does;
#   - nobody is picked until a click, as in the game;
#   - every phrase `WorkRead` can say fits the row's now room whole at both windows, where the line
#     the first review found cut is still cut at 1280 (the negative);
#   - every generated backstory at its longest and every unique reads whole in the drawer, where
#     all of them end to end would be cut (the negative);
#   - each row's "now" line is `WorkRead.doing` for that colonist as drawn, after the fit, and
#     follows the sim when her job changes (cooking, then idle with none);
#   - a right click on a name, a Focus chip or "their skills" does nothing;
#   - a click on a row's name picks that colonist for the whole game (main's selection), a click on
#     the footer picks nobody and queues nothing;
#   - a Focus chip queues exactly that focus for the picked colonist; a right click on a cell counts
#     its number down (1 to never, never to 4);
#   - the drawer's "who" lines are the sim's whole clause, wrapped and never cut, where one line at
#     the row's width would cut it (the negative);
#   - the Focus line describes a row by its preset only when the row is that preset;
#   - "their skills" opens Skills on that colonist, stamped viewing, its top on the Colony screen's;
#   - a roster of seven scrolls to a colonist picked in the game, the wheel still moves it while
#     they are picked, and the strip counts what is scrolled away each way.
func _the_colony_screen_is_one_survivor_context(main: Node) -> bool:
	var panel: Control = main.get("_work_panel") as Control
	var world: Variant = main.get("world")
	if panel == null or world == null:
		return _skip("COLONY", "the scene built no Colony screen")
	var script: GDScript = panel.get_script() as GDScript
	var jobs: GDScript = load("res://sim/modules/jobs.gd") as GDScript
	var NavBar: GDScript = load("res://ui/nav_bar.gd") as GDScript
	var old_size: Vector2i = root.size
	var was_paused: bool = bool(main.get("paused"))
	main.set("paused", true)
	main.call("_show_screen", "")
	main.set("_selected", -1)
	var ok: bool = true
	# The groups and the footer, judged once: they do not depend on the window.
	var flat: Array = []
	for g in script.call("groups") as Array:
		flat.append_array((g as Dictionary)["columns"] as Array)
	var consumers: Array = (jobs.get("CONSUMERS") as Array).duplicate()
	var sorted_flat: Array = flat.duplicate()
	sorted_flat.sort()
	consumers.sort()
	if sorted_flat != consumers or flat != (script.call("shown_columns") as Array):
		push_error("COLONY: the groups hold %s, not every column with a consumer once" % str(flat))
		ok = false
	var mara: int = -1
	var ellis: int = -1
	for row in jobs.call("work_view", world) as Array:
		var nm: String = String((row as Dictionary).get("name", ""))
		if nm.begins_with("Mara"):
			mara = int((row as Dictionary)["entity"])
		elif nm.begins_with("Ellis"):
			ellis = int((row as Dictionary)["entity"])
	if mara < 0 or ellis < 0:
		main.set("paused", was_paused)
		return _skip("COLONY", "the boot colony has no Mara and Ellis to manage")
	for dims in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = dims
		await process_frame
		_tap(KEY_J)
		main.call("_process", 0.0)
		await process_frame
		var view := Vector2(dims)
		var bar: Rect2 = NavBar.call("rect_for", view) as Rect2
		var r: Rect2 = panel.get_rect()
		if not panel.visible or not Rect2(Vector2.ZERO, view).encloses(r) or r.position.y < bar.end.y + 16.0 or int(r.position.x) % 2 != 0 or int(r.position.y) % 2 != 0 or int(r.size.x) % 2 != 0 or int(r.size.y) % 2 != 0:
			push_error("COLONY: the panel %s is not up, not inside %s, not under the bar or off the even grid" % [str(r), str(dims)])
			ok = false
		var foot: String = String((panel.get("drawn") as Dictionary).get("foot", ""))
		var named: PackedStringArray = foot.get_slice(": ", 1).split(", ", false)
		var stubs: Array = (script.call("unworked_columns") as Array).map(func(c: Variant) -> String: return String(c).to_lower())
		if Array(named) != stubs or stubs.size() != 6:
			push_error("COLONY: the footer names %s, not the six job columns nothing does %s" % [str(named), str(stubs)])
			ok = false
		# Nobody is picked until a click (main has nobody), so the bar and the drawer agree.
		if int(panel.call("selected")) != -1 or not ((panel.get("drawn") as Dictionary).get("who", []) as Array).is_empty():
			push_error("COLONY: the screen opened on %d with nobody picked in the game" % int(panel.call("selected")))
			ok = false
		# Every phrase the read model can say fits the row whole; one twice the cap does not.
		var row_font: Font = Chrome.font()
		var room: float = float(panel.call("now_room"))
		for phrase in WorkRead.phrases():
			if UiText.fit(row_font, phrase, 25, room) != phrase:
				push_error("COLONY: the now line %s is cut in %d px at %s" % [phrase, int(room), str(dims)])
				ok = false
		# At 1280 the room is tight: the line the review found cut is still cut there (the negative).
		var too_long: String = "heading home, the dead are close"
		if dims.x == 1280 and UiText.fit(row_font, too_long, 25, room) == too_long:
			push_error("COLONY: %s fits the now room at 1280 (%d px), so the fit was not judged" % [too_long, int(room)])
			ok = false
		# Every backstory the colony can hold reads whole in the drawer: each generated story with the
		# longest age and the three longest features a roll can give, and each unique as authored.
		var clauses: Array[String] = _every_who_clause(world)
		if clauses.size() < 10:
			push_error("COLONY: only %d who clauses to judge, not the eight stories and the two uniques" % clauses.size())
			ok = false
		for clause in clauses:
			var lines: Array = script.call("wrap_text", row_font, clause, 25, float(panel.call("_inner")), int(script.get("WHO_LINES"))) as Array
			if " ".join(PackedStringArray(lines)) != clause:
				push_error("COLONY: the drawer cuts %s at %s" % [clause, str(dims)])
				ok = false
		var piled: String = " ".join(PackedStringArray(_every_who_clause(world)))
		if " ".join(PackedStringArray(script.call("wrap_text", row_font, piled, 25, float(panel.call("_inner")), int(script.get("WHO_LINES"))) as Array)) == piled:
			push_error("COLONY: every clause end to end fits the drawer, so the cut was not judged")
			ok = false
		# The now line, and that it follows the sim.
		var rows_drawn: Dictionary = (panel.get("drawn") as Dictionary).get("rows", {}) as Dictionary
		for ent in [mara, ellis]:
			var said: String = String((rows_drawn.get(ent, {}) as Dictionary).get("now", ""))
			if said.is_empty() or said != WorkRead.doing(world, ent):
				push_error("COLONY: the row for %d says now %s, the read model %s" % [ent, said, WorkRead.doing(world, ent)])
				ok = false
		var job_was: Variant = world.components.get_component(mara, "job")
		var sleep_was: Variant = world.components.get_component(mara, "sleeping")
		world.components.remove_component(mara, "sleeping")
		world.components.set_component(mara, "job", {"kind": "Cook", "ticksLeft": 0})
		panel.queue_redraw()
		await process_frame
		var cooking: String = String((((panel.get("drawn") as Dictionary)["rows"] as Dictionary).get(mara, {}) as Dictionary).get("now", ""))
		world.components.remove_component(mara, "job")
		panel.queue_redraw()
		await process_frame
		var idle: String = String((((panel.get("drawn") as Dictionary)["rows"] as Dictionary).get(mara, {}) as Dictionary).get("now", ""))
		if job_was is Dictionary:
			world.components.set_component(mara, "job", job_was)
		if sleep_was is Dictionary:
			world.components.set_component(mara, "sleeping", sleep_was)
		if cooking != "cooking" or idle != WorkRead.IDLE:
			push_error("COLONY: Mara's now line read %s with a cook job and %s with none" % [cooking, idle])
			ok = false
		# Pick Mara by her name, then a footer click that picks nobody.
		var laid: Dictionary = panel.call("_layout") as Dictionary
		var mara_band: Rect2 = Rect2()
		for row in laid["rows"] as Array:
			if int((row as Dictionary)["entity"]) == mara:
				mara_band = (row as Dictionary)["band"] as Rect2
		_drain(main)
		# A right click on a name picks nobody and queues nothing.
		_mouse(panel.position + mara_band.position + Vector2(24.0, 12.0), MOUSE_BUTTON_RIGHT)
		if int(panel.call("selected")) != -1 or int(main.get("_selected")) != -1 or not _pending(main).is_empty():
			push_error("COLONY: a right click on Mara's name picked %d or queued %s" % [int(panel.call("selected")), str(_pending(main))])
			ok = false
		_mouse(panel.position + mara_band.position + Vector2(24.0, 12.0), MOUSE_BUTTON_LEFT)
		if int(main.get("_selected")) != mara or int(panel.call("selected")) != mara or not _pending(main).is_empty():
			push_error("COLONY: a click on Mara's name picked %d (main %d) and queued %s" % [int(panel.call("selected")), int(main.get("_selected")), str(_pending(main))])
			ok = false
		_mouse(panel.position + Vector2(panel.size.x / 2.0, panel.size.y - 8.0), MOUSE_BUTTON_LEFT)
		if int(panel.call("selected")) != mara or not _pending(main).is_empty():
			push_error("COLONY: a click on the footer changed the pick or queued %s" % str(_pending(main)))
			ok = false
		# An explicit Focus chip.
		laid = panel.call("_layout") as Dictionary
		var worker: Rect2 = Rect2()
		for chip in laid["chips"] as Array:
			if String((chip as Dictionary)["focus"]) == "Worker":
				worker = (chip as Dictionary)["rect"] as Rect2
		# A right click on a chip or on their skills does nothing at all.
		_mouse(panel.position + worker.get_center(), MOUSE_BUTTON_RIGHT)
		_mouse(panel.position + (laid["skills"] as Rect2).get_center(), MOUSE_BUTTON_RIGHT)
		main.call("_process", 0.0)
		if not _pending(main).is_empty() or bool(main.get("web_open")) or int(panel.call("selected")) != mara:
			push_error("COLONY: a right click on a focus chip or their skills queued %s, opened the web or moved the pick" % str(_pending(main)))
			ok = false
		_mouse(panel.position + worker.get_center(), MOUSE_BUTTON_LEFT)
		var focus_cmds: Array = _drain(main).filter(func(c: Variant) -> bool: return String((c as Dictionary).get("type", "")) == "job.focus")
		if focus_cmds.size() != 1 or int((focus_cmds[0] as Dictionary).get("entity", -1)) != mara or String((focus_cmds[0] as Dictionary).get("focus", "")) != "Worker":
			push_error("COLONY: the worker chip queued %s, not one Worker focus for Mara" % str(focus_cmds))
			ok = false
		# A right click counts a cell down: Mara's 1 to never, a never to 4.
		var cols: Dictionary = {}
		for row in jobs.call("work_view", world) as Array:
			if int((row as Dictionary)["entity"]) == mara:
				cols = (row as Dictionary)["cols"] as Dictionary
		var edges: Array = panel.call("_column_edges") as Array
		var shown: Array = script.call("shown_columns") as Array
		var picked_cells: Dictionary = {}
		for i in shown.size():
			var v: int = int(cols.get(String(shown[i]), 0))
			if v == 1 and not picked_cells.has(1):
				picked_cells[1] = i
			if v == 0 and not picked_cells.has(0):
				picked_cells[0] = i
		for v in picked_cells.keys():
			var i: int = int(picked_cells[v])
			var at: Vector2 = panel.position + Vector2((float(edges[i]) + float(panel.call("_column_end", edges, i))) / 2.0, mara_band.position.y + 20.0)
			_mouse(at, MOUSE_BUTTON_RIGHT)
			var edits: Array = _drain(main).filter(func(c: Variant) -> bool: return String((c as Dictionary).get("type", "")) == "job.priority")
			var want: int = 0 if int(v) == 1 else 4
			if edits.size() != 1 or String((edits[0] as Dictionary).get("column", "")) != String(shown[i]) or int((edits[0] as Dictionary).get("value", -1)) != want:
				push_error("COLONY: a right click on Mara's %s (%d) queued %s, not %d" % [String(shown[i]), int(v), str(edits), want])
				ok = false
		if picked_cells.size() < 2:
			push_error("COLONY: Mara's row has no 1 and no never to count down, so the right click was not judged")
			ok = false
		# The whole clause, wrapped, as the next frame draws it for Mara.
		panel.queue_redraw()
		await process_frame
		laid = panel.call("_layout") as Dictionary
		var who_text: String = String(laid["who_text"])
		var who_lines: Array = (panel.get("drawn") as Dictionary).get("who", []) as Array
		var name_room: float = float(edges[0]) - 24.0
		var font: Font = Chrome.font()
		if who_text.is_empty() or " ".join(PackedStringArray(who_lines)) != who_text or who_lines.size() < 2:
			push_error("COLONY: the drawer's who lines %s are not the sim's whole clause %s" % [str(who_lines), who_text])
			ok = false
		if UiText.fit(font, who_text, 25, name_room) == who_text:
			push_error("COLONY: the clause fits one row-width line, so the wrap was not judged")
			ok = false
		# The Focus line: by the preset only when the row is the preset.
		var sel_row: Dictionary = {}
		for row in jobs.call("work_view", world) as Array:
			if int((row as Dictionary)["entity"]) == mara:
				sel_row = row as Dictionary
		var line: String = String(panel.call("focus_line"))
		var is_preset: bool = bool(script.call("row_is_preset", sel_row))
		if is_preset != (line == String(script.call("focus_sentence", String(sel_row.get("focus", "Auto"))))):
			push_error("COLONY: the focus line %s does not match whether Mara's row is her focus's preset (%s)" % [line, str(is_preset)])
			ok = false
		var edited: Dictionary = sel_row.duplicate(true)
		edited["focus"] = "Medic"
		edited["cols"] = jobs.call("preset", "Medic")
		var preset_ok: bool = bool(script.call("row_is_preset", edited))
		(edited["cols"] as Dictionary)["Cook"] = 2
		if not preset_ok or bool(script.call("row_is_preset", edited)):
			push_error("COLONY: a medic preset row is not judged a preset, or one with a cell changed still is")
			ok = false
		if not String(script.call("focus_sentence", "Medic")).begins_with("medic puts doctor first"):
			push_error("COLONY: the medic sentence %s does not put doctor first" % String(script.call("focus_sentence", "Medic")))
			ok = false
		# Their skills.
		var sk: Rect2 = laid["skills"] as Rect2
		_mouse(panel.position + sk.get_center(), MOUSE_BUTTON_LEFT)
		main.call("_process", 0.0)
		await process_frame
		var nav: Control = main.get("_nav_bar") as Control
		var web: Control = main.get("_web_panel") as Control
		if not bool(main.get("web_open")) or bool(main.get("work_open")) or int(web.get("_who")) != mara or bool(nav.get("subject_is_you")) or not String(nav.get("subject_name")).begins_with("Mara"):
			push_error("COLONY: their skills left web %s on %d, the bar on %s" % [str(main.get("web_open")), int(web.get("_who")), String(nav.get("subject_name"))])
			ok = false
		# The two screens hang from one line under the bar, so switching does not move the top edge.
		if web.position.y != panel.position.y:
			push_error("COLONY: Skills starts at y %d and Colony at y %d (%s)" % [int(web.position.y), int(panel.position.y), str(dims)])
			ok = false
		_drain(main)
		main.call("_show_screen", "")
		main.set("_selected", -1)
		await process_frame
	ok = await _a_long_roster_scrolls_to_the_pick(main, panel) and ok
	root.size = old_size
	main.set("paused", was_paused)
	await process_frame
	if ok:
		print("COLONY OK at 1280x720 and 1920x1080 the screen sits under the bar on the even grid and opens on nobody; the groups hold every working column once and the footer names the six nothing does; every now phrase and every backstory fits whole; each now line is the read model's as drawn and follows a job change; a right click on a name, a chip or their skills does nothing; a name click picks the colonist for the game and a footer click picks nobody; a focus chip queues that focus; a right click counts 1 to never and never to 4; the who lines are the whole clause where one line would cut it; the focus line names a preset only for a preset row; their skills opens the web on them, viewing, from the same top edge; a roster of seven scrolls to the pick, keeps the wheel while it is picked and counts the rows scrolled away each way")
	return ok


# The drawer's "who" text for every backstory the colony can hold, less the name the heading says:
# each generated story at its longest (the longest age prose, the three longest features a roll can
# draw) and each unique as authored.
func _every_who_clause(world: Variant) -> Array[String]:
	var out: Array[String] = []
	var pool: Dictionary = {}
	var gen: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/colony/generator.json"))
	if gen is Dictionary:
		pool = gen as Dictionary
	var age: String = ""
	for band in pool.get("ageBands", []) as Array:
		if String((band as Dictionary).get("prose", "")).length() > age.length():
			age = String((band as Dictionary)["prose"])
	var feats: Array = (pool.get("features", []) as Array).duplicate()
	feats.sort_custom(func(x: Variant, y: Variant) -> bool: return String(x).length() > String(y).length())
	var three: String = ", ".join(PackedStringArray(feats.slice(0, 3)))
	for story in pool.get("backstories", []) as Array:
		var line: String = String((story as Dictionary).get("line", ""))
		out.append(line.substr(0, 1).to_upper() + line.substr(1) + ", " + age + "; " + three)
	# The uniques as the boot built them: an identity with no generated story is an authored one.
	for ent in world.components.query(["identity"]):
		var ident: Dictionary = world.components.get_component(ent, "identity") as Dictionary
		if String(ident.get("backstoryId", "")) != "":
			continue
		var clause: String = SimSurvivors.person_clause(world, ent)
		var lead: String = String(ident.get("name", "")) + ", "
		if clause.begins_with(lead):
			clause = clause.substr(lead.length())
			clause = clause.substr(0, 1).to_upper() + clause.substr(1)
		out.append(clause)
	return out


# A roster of seven at 1280x720: the last colonist picked in the game (as a click on their body in
# the street would) scrolls the roster to their row, which the screen would otherwise leave below
# the fold (the negative, at the top); the strip under the rows counts what is scrolled away each
# way and says nothing when every row is drawn; the picked row's brackets are drawn after the
# drawer, whose groove would cut their bottom arms (art QA, slice 2, round two).
func _a_long_roster_scrolls_to_the_pick(main: Node, panel: Control) -> bool:
	var ok: bool = true
	var world: Variant = main.get("world")
	var jobs: GDScript = load("res://sim/modules/jobs.gd") as GDScript
	root.size = Vector2i(1280, 720)
	await process_frame
	_tap(KEY_J)
	main.call("_process", 0.0)
	await process_frame
	if String((panel.get("drawn") as Dictionary).get("more", "?")) != "":
		push_error("COLONY: the boot's two colonists all drawn still say %s" % String((panel.get("drawn") as Dictionary).get("more", "?")))
		ok = false
	var at: Dictionary = world.components.get_component(int(world.player), "position") as Dictionary
	var born: Array[int] = []
	while (jobs.call("work_view", world) as Array).size() < 7:
		born.append(int(SimRecruits.spawn_generated(world, SimRecruits.roll(world, world.rng.stream("recruit")), float(at["x"]) + 2.0 + float(born.size()), float(at["y"]) + 1.0)))
	var rows: Array = jobs.call("work_view", world) as Array
	var last: int = int((rows[rows.size() - 1] as Dictionary)["entity"])
	panel.set("_row_scroll", 0)
	main.call("_process", 0.0)
	panel.queue_redraw()
	await process_frame
	var vis: int = int(panel.call("_visible_rows"))
	var top_more: String = String((panel.get("drawn") as Dictionary).get("more", ""))
	var shown: Array = ((panel.call("_layout") as Dictionary)["rows"] as Array).map(func(r: Variant) -> int: return int((r as Dictionary)["entity"]))
	if vis >= rows.size() or shown.has(last) or top_more != "%d more below · wheel" % (rows.size() - vis):
		push_error("COLONY: seven colonists at 1280 show %d rows, the last drawn %s, the strip %s" % [vis, str(shown.has(last)), top_more])
		ok = false
	main.set("_selected", last)
	main.call("_process", 0.0)
	panel.queue_redraw()
	await process_frame
	shown = ((panel.call("_layout") as Dictionary)["rows"] as Array).map(func(r: Variant) -> int: return int((r as Dictionary)["entity"]))
	var end_more: String = String((panel.get("drawn") as Dictionary).get("more", ""))
	if int(panel.call("selected")) != last or not shown.has(last) or end_more != "%d above · wheel" % (rows.size() - vis):
		push_error("COLONY: the last colonist picked in the game is %s drawn (picked %d), the strip %s" % [str(shown.has(last)), int(panel.call("selected")), end_more])
		ok = false
	# The wheel stays the player's while somebody is picked: one step up, then the frames main
	# runs, and the roster has moved off the pick and stays there (art QA, slice 2, round three:
	# a scroll to the pick on every frame undid every step).
	var end_scroll: int = int(panel.get("_row_scroll"))
	_mouse(panel.position + Vector2(panel.size.x / 2.0, float(panel.get_script().get("GRID_Y")) + 20.0), MOUSE_BUTTON_WHEEL_UP)
	for i in 3:
		main.call("_process", 0.0)
		await process_frame
	var mid_more: String = String((panel.get("drawn") as Dictionary).get("more", ""))
	var mid_scroll: int = int(panel.get("_row_scroll"))
	if mid_scroll != end_scroll - 1 or int(panel.call("selected")) != last or mid_more != "%d above · 1 below · wheel" % mid_scroll:
		push_error("COLONY: a wheel step up with %d picked left the roster at %d (was %d), the strip %s" % [last, mid_scroll, end_scroll, mid_more])
		ok = false
	var body: String = FileAccess.get_file_as_string("res://ui/work_panel.gd")
	var draw_at: int = body.find("func _draw() -> void:")
	if draw_at < 0 or body.find("Locker.brackets(", draw_at) < body.find("_draw_drawer(font", draw_at):
		push_error("COLONY: the picked row's brackets are drawn before the drawer, whose groove cuts them")
		ok = false
	for e in born:
		world.despawn(e)
	main.set("_selected", -1)
	main.call("_show_screen", "")
	await process_frame
	return ok


func _mouse(at: Vector2, button: MouseButton) -> void:
	for down in [true, false]:
		var press := InputEventMouseButton.new()
		press.button_index = button
		press.pressed = down
		press.position = at
		root.push_input(press)


# The Colony screen's stockpile block (stockpile plan, slice S5), in the real scene at 1280x720 and
# 1920x1080, through real clicks:
#   - with nobody picked the drawer shows the stockpile, each group's word is the read model's
#     (`StockpileRead.summary`) and each name drawn is one of its names, in its order; a pile with
#     a stack of rounds is not all "none" (the positive the negative below is judged against);
#   - with the pile emptied (no tick between) and the screen opened again, every group reads
#     "none", dim, and names nothing (the negative);
#   - no string the block draws carries a digit but an item's name that `_name_is_allowed` allows,
#     where the same digits as an amount word would be refused (the check can fail);
#   - every row sits inside the drawer, and the drawer is the same rectangle for the stockpile and
#     for a person, so pressing the button never moves the grid;
#   - a click on Mara's name shows her; "the stockpile" shows the pile without changing the game's
#     pick or queueing anything; a right click on it does nothing; while the pile is shown a click
#     where a Focus chip stood queues nothing; "back to" her name shows her again;
#   - the ink the block uses reads at 4.5:1 or better on the steel.
func _the_colony_screen_reads_the_stockpile(main: Node) -> bool:
	var panel: Control = main.get("_work_panel") as Control
	var world: Variant = main.get("world")
	if panel == null or world == null:
		return _skip("STOCKPILE", "the scene built no Colony screen")
	var Read: GDScript = load("res://sim/stockpile_read.gd") as GDScript
	var SimStockpile: GDScript = load("res://sim/modules/stockpile.gd") as GDScript
	var Locker: GDScript = load("res://ui/locker.gd") as GDScript
	var jobs: GDScript = load("res://sim/modules/jobs.gd") as GDScript
	var pile: Array = SimStockpile.call("tiles", world) as Array
	if pile.is_empty():
		return _skip("STOCKPILE", "the colony has no stockpile tile to stock")
	var mara: int = -1
	for row in jobs.call("work_view", world) as Array:
		if String((row as Dictionary).get("name", "")).begins_with("Mara"):
			mara = int((row as Dictionary)["entity"])
	if mara < 0:
		return _skip("STOCKPILE", "the boot colony has no Mara to pick")
	var old_size: Vector2i = root.size
	var was_paused: bool = bool(main.get("paused"))
	main.set("paused", true)
	var ok: bool = true
	# Rounds on the pile, so the ammunition row names a round whose name carries a digit.
	var rounds: int = SimItems.spawn_item(world, "item.ammo.rifle.match", {"tier": "scavenged", "count": 10})
	var first: Vector2i = pile[0] as Vector2i
	world.components.set_component(rounds, "position", {"x": float(first.x) + 0.5, "y": float(first.y) + 0.5})
	for c in [Locker.get("TEXT"), Locker.get("TEXT_DIM")]:
		for bg in [Locker.get("STEEL"), Locker.get("STEEL_GRAIN")]:
			if _contrast(c as Color, bg as Color) < 4.5:
				push_error("STOCKPILE: ink %s reads %.2f:1 on %s" % [str(c), _contrast(c as Color, bg as Color), str(bg)])
				ok = false
	for dims in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = dims
		main.call("_show_screen", "")
		main.set("_selected", -1)
		await process_frame
		_tap(KEY_J)
		main.call("_process", 0.0)
		panel.set("_stores_key", [])
		panel.queue_redraw()
		await process_frame
		var summary: Array = Read.call("summary", world) as Array
		var drawn: Array = (panel.get("drawn") as Dictionary).get("stores", []) as Array
		if not bool(panel.call("stores_shown")) or drawn.size() != summary.size():
			push_error("STOCKPILE: with nobody picked the drawer shows %d stockpile rows, the read model %d (%s)" % [drawn.size(), summary.size(), str(dims)])
			ok = false
		var stocked: int = 0
		for i in mini(drawn.size(), summary.size()):
			var d: Dictionary = drawn[i] as Dictionary
			var r: Dictionary = summary[i] as Dictionary
			if String(d["group"]) != String(r["group"]) or String(d["words"]) != String(r["words"]):
				push_error("STOCKPILE: row %d draws %s %s, the read model %s %s" % [i, String(d["group"]), String(d["words"]), String(r["group"]), String(r["words"])])
				ok = false
			if not _names_in_order(String(d["names"]), r["names"] as Array):
				push_error("STOCKPILE: %s draws names %s, not the read model's %s in order" % [String(d["group"]), String(d["names"]), str(r["names"])])
				ok = false
			if String(d["words"]) != "none":
				stocked += 1
				if String(d["names"]).is_empty():
					push_error("STOCKPILE: %s reads %s and names nothing" % [String(d["group"]), String(d["words"])])
					ok = false
		if stocked == 0:
			push_error("STOCKPILE: a pile with rounds on it reads none in every group, so the negative is not judged")
			ok = false
		var ammo_names: String = ""
		for d in drawn:
			if String((d as Dictionary)["group"]) == "ammunition":
				ammo_names = String((d as Dictionary)["names"])
		if ammo_names.find(".308 Winchester Match") < 0:
			push_error("STOCKPILE: the ammunition row names %s, not the rounds on the pile" % ammo_names)
			ok = false
		var laid: Dictionary = panel.call("_layout") as Dictionary
		var said: Array[String] = [String(panel.get_script().get("STORES_HEAD")), String(laid["stores_hint"])]
		if not _stores_digits_ok(drawn, said):
			ok = false
		# The same check refuses a digit anywhere but a name: an amount said as a number.
		var doctored: Array = drawn.duplicate(true)
		if not doctored.is_empty():
			(doctored[0] as Dictionary)["words"] = "12"
		if doctored.is_empty() or _stores_digits_ok(doctored, [], true):
			push_error("STOCKPILE: an amount word of 12 passed the digit check, so the check cannot fail")
			ok = false
		var drawer: Rect2 = laid["drawer"] as Rect2
		for r in laid["stores"] as Array:
			var rd: Dictionary = r as Dictionary
			var at: Vector2 = rd["label_at"] as Vector2
			var font: Font = Chrome.font()
			var end_x: float = (rd["names_at"] as Vector2).x + font.get_string_size(String(rd["names"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 25).x
			if at.x < drawer.position.x or end_x > drawer.end.x or at.y - Chrome.ascent(25) < drawer.position.y or at.y > drawer.end.y:
				push_error("STOCKPILE: the %s row at %s to x %d leaves the drawer %s (%s)" % [String(rd["group"]), str(at), int(end_x), str(drawer), str(dims)])
				ok = false
		# Emptied with no tick, as a drop while paused would: closing and opening the screen reads it
		# afresh, and every row reads none, dim, naming nothing.
		var moved: Dictionary = {}
		for item in SimNeeds.stockpile_items(world):
			moved[item] = (world.components.get_component(item, "position") as Dictionary).duplicate()
			world.components.remove_component(item, "position")
		main.call("_show_screen", "")
		await process_frame
		_tap(KEY_J)
		main.call("_process", 0.0)
		panel.queue_redraw()
		await process_frame
		for d in (panel.get("drawn") as Dictionary).get("stores", []) as Array:
			var dd: Dictionary = d as Dictionary
			if String(dd["words"]) != "none" or not String(dd["names"]).is_empty() or (dd["word_col"] as Color) != (Locker.get("TEXT_DIM") as Color):
				push_error("STOCKPILE: the emptied pile draws %s %s %s, not none, dim, with no name" % [String(dd["group"]), String(dd["words"]), String(dd["names"])])
				ok = false
		for item in moved.keys():
			world.components.set_component(int(item), "position", moved[item])
		panel.set("_stores_key", [])
		# The button: Mara picked by her name, then the pile, then back.
		var mara_band: Rect2 = Rect2()
		for row in laid["rows"] as Array:
			if int((row as Dictionary)["entity"]) == mara:
				mara_band = (row as Dictionary)["band"] as Rect2
		_drain(main)
		_mouse(panel.position + mara_band.position + Vector2(24.0, 12.0), MOUSE_BUTTON_LEFT)
		await process_frame
		laid = panel.call("_layout") as Dictionary
		var person_drawer: Rect2 = laid["drawer"] as Rect2
		var toggle: Rect2 = laid["stores_toggle"] as Rect2
		var chip_at: Vector2 = ((laid["chips"] as Array)[0] as Dictionary)["rect"].get_center() if not (laid["chips"] as Array).is_empty() else Vector2.ZERO
		if bool(panel.call("stores_shown")) or String(laid["stores_toggle_label"]) != "the stockpile" or toggle.size.x <= 0.0:
			push_error("STOCKPILE: with Mara picked the drawer shows the pile %s, its button reads %s" % [str(panel.call("stores_shown")), String(laid["stores_toggle_label"])])
			ok = false
		_mouse(panel.position + toggle.get_center(), MOUSE_BUTTON_RIGHT)
		if bool(panel.call("stores_shown")):
			push_error("STOCKPILE: a right click on the stockpile button showed the pile")
			ok = false
		_mouse(panel.position + toggle.get_center(), MOUSE_BUTTON_LEFT)
		await process_frame
		laid = panel.call("_layout") as Dictionary
		if not bool(panel.call("stores_shown")) or int(main.get("_selected")) != mara or int(panel.call("selected")) != mara or not _pending(main).is_empty():
			push_error("STOCKPILE: the stockpile button showed the pile %s, left the pick on %d and queued %s" % [str(panel.call("stores_shown")), int(main.get("_selected")), str(_pending(main))])
			ok = false
		if (laid["drawer"] as Rect2) != person_drawer:
			push_error("STOCKPILE: the drawer is %s for the pile and %s for Mara (%s)" % [str(laid["drawer"]), str(person_drawer), str(dims)])
			ok = false
		if ((panel.get("drawn") as Dictionary).get("stores", []) as Array).size() != summary.size() or not ((panel.get("drawn") as Dictionary).get("who", []) as Array).is_empty():
			push_error("STOCKPILE: with the pile shown for Mara the drawer draws her too, or not the pile")
			ok = false
		_mouse(panel.position + chip_at, MOUSE_BUTTON_LEFT)
		if not _pending(main).is_empty():
			push_error("STOCKPILE: a click where a focus chip stood, the pile shown, queued %s" % str(_pending(main)))
			ok = false
		_drain(main)
		var back: Rect2 = laid["stores_toggle"] as Rect2
		if not String(laid["stores_toggle_label"]).begins_with("back to Mara"):
			push_error("STOCKPILE: the way back reads %s" % String(laid["stores_toggle_label"]))
			ok = false
		_mouse(panel.position + back.get_center(), MOUSE_BUTTON_LEFT)
		await process_frame
		if bool(panel.call("stores_shown")) or ((panel.get("drawn") as Dictionary).get("who", []) as Array).is_empty():
			push_error("STOCKPILE: back to Mara left the pile shown or her drawer empty")
			ok = false
		_drain(main)
		main.call("_show_screen", "")
		main.set("_selected", -1)
		await process_frame
	world.components.remove_component(rounds, "position")
	root.size = old_size
	main.set("paused", was_paused)
	await process_frame
	if ok:
		print("STOCKPILE OK at 1280x720 and 1920x1080 nobody picked shows the pile, each word the read model's and each name one of its names in order; an emptied pile reads none, dim, naming nothing; no digit but an allowed item name, where an amount of 12 is refused; every row inside the drawer, which holds still between the pile and a person; the stockpile button shows the pile without moving the pick or queueing, a right click does nothing, a chip's place queues nothing, back to Mara shows her; both inks read 4.5:1 on the steel")
	return ok


# Is `drawn` (a comma-joined line of names) the read model's names, or a part of them, in order?
func _names_in_order(drawn: String, names: Array) -> bool:
	if drawn.is_empty():
		return true
	var at: int = 0
	for piece in drawn.split(", "):
		var found: bool = false
		while at < names.size():
			var n: String = String(names[at])
			at += 1
			if n == piece or (piece.ends_with("…") and n.begins_with(piece.trim_suffix("…"))):
				found = true
				break
		if not found:
			return false
	return true


# No string the stockpile block draws carries a digit, but an item's name `_name_is_allowed` allows.
# `quiet` judges without reporting, for the check's own negative.
func _stores_digits_ok(rows: Array, also: Array[String], quiet: bool = false) -> bool:
	var ok: bool = true
	var bad: Array[String] = []
	for s in also:
		if _has_digit(s):
			bad.append(s)
	for r in rows:
		var d: Dictionary = r as Dictionary
		for s in [String(d["group"]), String(d["words"])]:
			if _has_digit(s):
				bad.append(s)
		if not String(d["names"]).is_empty():
			for piece in String(d["names"]).split(", "):
				if _has_digit(piece) and not CheckInventory._name_is_allowed(piece):
					bad.append(piece)
	if not bad.is_empty():
		ok = false
		if not quiet:
			push_error("STOCKPILE: the block draws digits in %s" % str(bad))
	return ok


func _has_digit(s: String) -> bool:
	for ch in s:
		if ch >= "0" and ch <= "9":
			return true
	return false


# WCAG contrast of two opaque colours.
func _contrast(a: Color, b: Color) -> float:
	var la: float = _luminance(a)
	var lb: float = _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _luminance(c: Color) -> float:
	var ch: Array[float] = []
	for v in [c.r, c.g, c.b]:
		ch.append(float(v) / 12.92 if float(v) <= 0.03928 else pow((float(v) + 0.055) / 1.055, 2.4))
	return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2]


# --- BENCH ----------------------------------------------------------------------------------------

# The assembly screen in the real scene, at both windows, through real keys and clicks. The world
# is set up through the sim's own calls (a bench where the survivor stands, a hunting rifle in hand,
# a pack of parts that fit it) and everything after that is a press.
const BENCH_RIFLE: String = "item.rifle.hunting"
const BENCH_OPTIC: String = "item.attach.optic.red_dot"
const BENCH_MAG: String = "item.attach.magazine.extended"
# The rect the panel had before slice 3: its bottom forty pixels were off a 720-pixel window.
const OLD_BENCH_RECT: Rect2 = Rect2(Vector2(320, 140), Vector2(960, 620))


func _the_bench_opens_fits_and_closes() -> bool:
	var lane: String = "BENCH"
	var main: Node = await _boot()
	if main == null:
		push_error("%s: the scene did not boot" % lane)
		return false
	var world: Variant = main.get("world")
	var panel: Control = main.get("_bench_panel") as Control
	if world == null or panel == null:
		push_error("%s: no world or no bench panel in the scene" % lane)
		return await _bench_done(main, Vector2i.ZERO, false)
	var me: int = int(world.player)
	var old_size: Vector2i = root.size
	var ok: bool = true
	# The negative for the frame: the old fixed rect does not fit the smaller window.
	if Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(OLD_BENCH_RECT):
		push_error("%s: the old fixed rect fits 1280x720, so the frame check below proves nothing" % lane)
		ok = false
	# Somewhere the top rung of E is the bench: where the survivor stands, or else an open street.
	var home: Dictionary = world.components.get_component(me, "position") as Dictionary
	var bench: int = SimGunsmith.make_bench(world, float(home["x"]), float(home["y"]))
	var rifle: int = SimItems.spawn_item(world, BENCH_RIFLE, {"tier": "scavenged"})
	var pack: int = SimItems.spawn_item(world, "item.pack.hiking", {"tier": "scavenged"})
	if not SimInventory.equip(world, me, rifle) or not SimInventory.equip(world, me, pack):
		push_error("%s: the survivor could not take up the rifle and the pack" % lane)
		return await _bench_done(main, old_size, false)
	var optic: int = SimItems.spawn_item(world, BENCH_OPTIC, {"tier": "scavenged"})
	var mag: int = SimItems.spawn_item(world, BENCH_MAG, {"tier": "scavenged"})
	if not SimInventory.stow(world, me, optic) or not SimInventory.stow(world, me, mag):
		push_error("%s: the pack would not take the parts" % lane)
		return await _bench_done(main, old_size, false)
	if String(SimFortify.rung_of(world, me).get("verb", "")) != "open_bench":
		var street: Vector2 = ReviewScenes._street_spot(world)
		if street.x >= 0.0:
			world.components.set_component(me, "position", {"x": street.x, "y": street.y})
			world.components.set_component(bench, "position", {"x": street.x, "y": street.y})
	if String(SimFortify.rung_of(world, me).get("verb", "")) != "open_bench":
		push_error("%s: no spot was found where E's top rung is the bench (it is %s)" % [lane, str(SimFortify.rung_of(world, me))])
		return await _bench_done(main, old_size, false)

	for dims in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = dims
		await process_frame
		_drain(main)
		# E opens it, through the ladder: the press pushes use.context, the tick takes it.
		_tap(KEY_E)
		_frames(main, 2)
		await process_frame
		if SimGunsmith.focus_of(world, me) != rifle or not panel.visible:
			push_error("%s: E at a bench with a rifle did not open the assembly at %s" % [lane, str(dims)])
			ok = false
			continue
		var frame: Rect2 = panel.call("frame_rect") as Rect2
		var view_rect: Rect2 = Rect2(Vector2.ZERO, Vector2(dims))
		if not view_rect.encloses(Rect2(frame.position + panel.global_position, frame.size)) or not view_rect.encloses(panel.get_global_rect()):
			push_error("%s: the frame %s is not inside the %s window" % [lane, str(frame), str(dims)])
			ok = false
		if dims.x == 1920 and absf(frame.get_center().x - 960.0) > 2.0:
			push_error("%s: the frame is not centred at 1920x1080 (%s)" % [lane, str(frame)])
			ok = false

		# A click on the wash outside the frame is the screen's, and swings at nothing.
		_drain(main)
		_mouse(Vector2(frame.position.x / 2.0, float(dims.y) / 2.0), MOUSE_BUTTON_LEFT)
		for c in _pending(main):
			if ["swing", "fire", "aim"].has(String((c as Dictionary).get("type", ""))):
				push_error("%s: a click on the wash reached the street (%s)" % [lane, str(c)])
				ok = false
		_drain(main)

		# A plate, then a candidate: the sight, then the red dot.
		var lay: Dictionary = panel.call("layout") as Dictionary
		var plates: Dictionary = lay["plates"] as Dictionary
		if not plates.has("optic"):
			push_error("%s: the rifle's sight has no plate" % lane)
			ok = false
			continue
		_mouse((plates["optic"] as Rect2).get_center(), MOUSE_BUTTON_LEFT)
		if String(panel.call("picked_slot")) != "optic":
			push_error("%s: a click on the sight's plate did not pick it" % lane)
			ok = false
		lay = panel.call("layout") as Dictionary
		var cards: Array = lay["offers"] as Array
		if cards.is_empty():
			push_error("%s: the sight is picked and nothing is offered for it" % lane)
			ok = false
			continue
		_mouse(((cards[0] as Dictionary)["rect"] as Rect2).get_center(), MOUSE_BUTTON_LEFT)
		var attach: Array = _pending(main).filter(func(c: Variant) -> bool: return String((c as Dictionary).get("type", "")) == "item.attach")
		if attach.size() != 1 or int((attach[0] as Dictionary).get("item", -1)) != optic or String((attach[0] as Dictionary).get("slot", "")) != "optic":
			push_error("%s: a click on the red dot pushed %s, not one item.attach of it to the sight" % [lane, str(attach)])
			ok = false
		_frames(main, 1)
		await process_frame
		if SimAttachments.in_slot(world, rifle, "optic") != optic:
			push_error("%s: the fit did not reach the rifle" % lane)
			ok = false
		var row: Dictionary = {}
		for r_v in (panel.get("_view") as Dictionary).get("slots", []) as Array:
			if String((r_v as Dictionary).get("slot", "")) == "optic":
				row = r_v as Dictionary
		if int(row.get("part", -1)) != optic:
			push_error("%s: the view did not follow the fit (the sight's row is %s)" % [lane, str(row)])
			ok = false

		# "take off", from the footer, on the picked sight.
		_drain(main)
		lay = panel.call("layout") as Dictionary
		var take_off: Rect2 = Rect2()
		var fit_button: bool = false
		for b_v in lay["buttons"] as Array:
			if String((b_v as Dictionary)["kind"]) == "take off":
				take_off = (b_v as Dictionary)["rect"] as Rect2
			if String((b_v as Dictionary)["kind"]) == "fit":
				fit_button = true
		if not take_off.has_area():
			push_error("%s: a fitted sight has no take off button" % lane)
			ok = false
		else:
			_mouse(take_off.get_center(), MOUSE_BUTTON_LEFT)
			var detach: Array = _pending(main).filter(func(c: Variant) -> bool: return String((c as Dictionary).get("type", "")) == "item.detach")
			if detach.size() != 1 or int((detach[0] as Dictionary).get("item", -1)) != optic:
				push_error("%s: take off pushed %s, not one item.detach of the sight" % [lane, str(detach)])
				ok = false
			_frames(main, 1)
			await process_frame
			if SimAttachments.in_slot(world, rifle, "optic") >= 0:
				push_error("%s: take off did not reach the rifle" % lane)
				ok = false
		# The negative: with the sight empty there is nothing to take off, and the button is gone.
		lay = panel.call("layout") as Dictionary
		for b_v in lay["buttons"] as Array:
			if String((b_v as Dictionary)["kind"]) == "take off":
				push_error("%s: an empty sight still offers take off" % lane)
				ok = false
		if fit_button:
			push_error("%s: the fit button was up while the keys were on the plates" % lane)
			ok = false

		# The same from the keys: Enter on the empty sight crosses to what fits, Enter fits it.
		_drain(main)
		_tap(KEY_ENTER)
		if String(panel.call("side")) != "offers":
			push_error("%s: Enter on an empty slot did not cross to its candidates" % lane)
			ok = false
		_tap(KEY_ENTER)
		var keyed: Array = _pending(main).filter(func(c: Variant) -> bool: return String((c as Dictionary).get("type", "")) == "item.attach")
		if keyed.size() != 1 or String((keyed[0] as Dictionary).get("slot", "")) != "optic":
			push_error("%s: Enter on a candidate pushed %s, not one fit to the sight" % [lane, str(keyed)])
			ok = false
		_frames(main, 1)
		await process_frame
		# Left back to the plates, Down to the picture's row: the stock, the muzzle or the magazine,
		# never the sight again.
		_tap(KEY_LEFT)
		_tap(KEY_DOWN)
		if String(panel.call("side")) != "slots" or String(panel.call("picked_slot")) == "optic":
			push_error("%s: Left then Down left the keys on %s %s" % [lane, String(panel.call("side")), String(panel.call("picked_slot"))])
			ok = false
		# An arrow under the bench is the screen's, never a step.
		for c in _pending(main):
			if String((c as Dictionary).get("type", "")) == "move" and (absf(float((c as Dictionary).get("dx", 0.0))) > 0.0 or absf(float((c as Dictionary).get("dy", 0.0))) > 0.0):
				push_error("%s: an arrow under the bench walked the body (%s)" % [lane, str(c)])
				ok = false

		# Every word drawn: a digit only in an item's name, and a name only where the name rule
		# allows it. The scanner is proved on a fabricated pair first.
		await process_frame
		var said: Array = panel.call("said") as Array
		if said.is_empty():
			push_error("%s: the panel drew no words to judge" % lane)
			ok = false
		if _digits_in("steadiness better").length() != 0 or _digits_in("x 3 rounds").is_empty():
			push_error("%s: the digit scanner is not telling a digit from a word" % lane)
			ok = false
		for t_v in said:
			var t: Dictionary = t_v as Dictionary
			var text: String = String(t.get("text", ""))
			if String(t.get("kind", "")) == "name":
				if not _digits_in(text).is_empty() and not CheckInventory._name_is_allowed(text):
					push_error("%s: an item name drawn on the bench is nothing but a number: '%s'" % [lane, text])
					ok = false
			elif not _digits_in(text).is_empty():
				push_error("%s: a word drawn on the bench carries a digit: '%s'" % [lane, text])
				ok = false

		# The amber corner has its key on screen while some slot wears it, and none once nothing
		# carried fits: the same view with its offers taken away draws no key.
		var says: String = BenchPanel.LEGEND_SAYS
		var corner_keyed: bool = false
		for t_v in said:
			corner_keyed = corner_keyed or String((t_v as Dictionary).get("text", "")) == says
		if not corner_keyed or (lay["legend_at"] as Vector2).x < 0.0:
			push_error("%s: parts that fit are carried, but the amber corner has no key at %s" % [lane, str(dims)])
			ok = false
		# At the bench nothing is locked: the "bench" tape is a by-hand mark (the negative for the
		# by-hand half after this loop).
		if not (panel.call("locked") as Array).is_empty():
			push_error("%s: at the bench the screen draws %s locked" % [lane, str(panel.call("locked"))])
			ok = false
		var kept: Dictionary = panel.get("_view") as Dictionary
		var bare: Dictionary = kept.duplicate()
		bare["offers"] = []
		panel.set("_view", bare)
		panel.queue_redraw()
		await process_frame
		for t_v in panel.call("said") as Array:
			if String((t_v as Dictionary).get("text", "")) == says:
				push_error("%s: the amber corner's key is drawn with nothing that fits" % lane)
				ok = false
		panel.set("_view", kept)
		panel.queue_redraw()
		await process_frame

		# Escape closes it and clears the focus.
		_tap(KEY_ESCAPE)
		_frames(main, 1)
		await process_frame
		if SimGunsmith.focus_of(world, me) >= 0 or panel.visible:
			push_error("%s: Escape left the bench open at %s" % [lane, str(dims)])
			ok = false
		# The fitted sight comes off for the next window, so both windows judge the same rifle.
		var fitted: int = SimAttachments.in_slot(world, rifle, "optic")
		if fitted >= 0:
			SimAttachments.detach(world, fitted)

	# By hand (C1's field work): the bench taken far off, the same rifle opened where the survivor
	# stands. A fitted part the hands cannot take off is drawn locked -- a "bench" tape on each --
	# exactly the slots the read model says are fitted and not `removable`; the magazine, which
	# hands can change, is not among them. (No amber corner on a locked plate is not asserted: by
	# hand the view offers nothing for such a slot, `may_work` filters it, so there is no case to
	# fail; the panel's own guard is belt and braces.)
	root.size = Vector2i(1280, 720)
	await process_frame
	var bench_at: Dictionary = (world.components.get_component(bench, "position") as Dictionary).duplicate()
	world.components.set_component(bench, "position", {"x": float(bench_at["x"]) + 60.0, "y": float(bench_at["y"])})
	_drain(main)
	world.commands.push({"type": "bench.open", "item": rifle})
	_frames(main, 2)
	await process_frame
	await process_frame
	var hand_view: Dictionary = SimGunsmith.bench_view(world, me, rifle)
	if SimGunsmith.focus_of(world, me) != rifle or not panel.visible or bool(hand_view.get("at_bench", true)):
		push_error("%s: the rifle did not open by hand away from the bench (view at_bench %s)" % [lane, str(hand_view.get("at_bench", "?"))])
		ok = false
	else:
		var want: Array[String] = []
		for row_v in hand_view.get("slots", []) as Array:
			var row: Dictionary = row_v as Dictionary
			if int(row.get("part", -1)) >= 0 and not bool(row.get("removable", false)):
				want.append(String(row.get("slot", "")))
		var got: Array[String] = (panel.call("locked") as Array[String]).duplicate()
		want.sort()
		got.sort()
		if want.is_empty() or got != want:
			push_error("%s: by hand the screen draws %s locked where the view says %s" % [lane, str(got), str(want)])
			ok = false
		if got.has("magazine"):
			push_error("%s: by hand the magazine, which hands can change, is drawn locked" % lane)
			ok = false
		var taped: int = 0
		for t_v in panel.call("said") as Array:
			if String((t_v as Dictionary).get("text", "")) == "BENCH":
				taped += 1
		if taped != got.size():
			push_error("%s: %d locked plates but %d \"bench\" tapes" % [lane, got.size(), taped])
			ok = false
	_tap(KEY_ESCAPE)
	_frames(main, 1)
	await process_frame
	world.components.set_component(bench, "position", bench_at)
	return await _bench_done(main, old_size, ok)


func _bench_done(main: Node, old_size: Vector2i, ok: bool) -> bool:
	if old_size != Vector2i.ZERO:
		root.size = old_size
	main.queue_free()
	await process_frame
	if ok:
		print("BENCH OK E at a bench opens the assembly inside 1280x720 and centred at 1920x1080 where the old rect does not fit; plate then candidate fits, take off detaches and then is gone, Enter crosses and fits, arrows stay on the screen, the wash eats a click, every word is digit-free but a name, Escape closes it; by hand the parts only a bench can take off wear a \"bench\" tape and the magazine does not")
	return ok


# --- MENU-ESCAPE ---------------------------------------------------------------------------------

const PickRes = preload("res://presentation/pick.gd")
const ProjectionRes = preload("res://presentation/projection.gd")

# Escape with the street's right-click menu open is the menu's, before any screen: a real right
# click on your own body opens it (headed "you"), Escape closes it, and the pause menu, the sheet,
# the Colony screen, the skill web and the bench all stay down and the run keeps playing. The
# negative is the same Escape with no menu open, which still pauses -- otherwise "the menu took
# it" could be "Escape reaches nothing" -- and a second Escape gives the street back.
func _escape_closes_the_menu_first(main: Node) -> bool:
	var lane: String = "MENU-ESCAPE"
	var menu: Variant = main.get("_context_menu")
	var shell: Variant = main.get("_shell")
	var world: Variant = main.get("world")
	if menu == null or shell == null:
		return _skip(lane, "the scene built no context menu or no shell")
	if _state(main) != Session.State.PLAYING:
		return _skip(lane, "the scene is not playing, so there is no street to right-click")
	var me: int = int(world.player)
	var p: Dictionary = world.components.get_component(me, "position") as Dictionary
	var camera: Dictionary = main.get("camera")
	var sc: Dictionary = ProjectionRes.world_to_screen(camera, float(p["x"]), float(p["y"]))
	var at: Vector2 = Vector2(-1.0, -1.0)
	for lift in range(0, 64, 4):
		var probe := Vector2(float(sc["sx"]), float(sc["sy"]) - float(lift))
		var hit: Dictionary = PickRes.pick_at(world, camera, probe)
		if String(hit.get("kind", "")) == "colonist" and int(hit.get("entity", -1)) == me:
			at = probe
			break
	if at.x < 0.0:
		return _skip(lane, "no point on screen picks your own body")
	# Where it opens: on the art grid, and above the HUD's bottom band however low the click. A
	# click a few pixels above the window's bottom edge is the case the clamp exists for; the old
	# clamp (to the window) would have dropped this menu over the action bar and the belt.
	var hud: Variant = main.get("_hud")
	var old_size: Vector2i = root.size
	root.size = Vector2i(1280, 720)
	await process_frame
	var probe_rows: Array[Dictionary] = [{"text": "walk here", "command": {}, "target": -1}, {"text": "shout", "command": {}, "target": -1}]
	var view_h: float = (menu as Control).get_viewport_rect().size.y
	menu.call("open", Vector2(101.0, view_h - 7.0), probe_rows, "a probe")
	var probe: Rect2 = (menu as Control).get_rect()
	var bar: float = float(hud.call("bar_top")) if hud != null and bool((hud as CanvasItem).visible) else -1.0
	menu.call("close")
	root.size = old_size
	await process_frame
	if bar <= probe.size.y or bar >= view_h:
		push_error("%s: no HUD band to judge the clamp against at 1280x720 (bar top %.0f, window %.0f)" % [lane, bar, view_h])
		return false
	if probe.end.y > bar:
		push_error("%s: a menu opened low ends at %.0f, over the action bar at %.0f" % [lane, probe.end.y, bar])
		return false
	if fmod(probe.position.x, 2.0) != 0.0 or fmod(probe.position.y, 2.0) != 0.0:
		push_error("%s: the menu opened off the art grid at %s" % [lane, str(probe.position)])
		return false
	_mouse(at, MOUSE_BUTTON_RIGHT)
	await process_frame
	if not bool(menu.call("is_open")):
		push_error("%s: a right click on your own body opened no menu" % lane)
		return false
	if String(menu.call("header")) != "you":
		push_error("%s: the menu on your own body is headed '%s', not 'you'" % [lane, String(menu.call("header"))])
		return false
	_tap(KEY_ESCAPE)
	await process_frame
	if bool(menu.call("is_open")):
		push_error("%s: Escape left the menu open" % lane)
		return false
	var screens: Dictionary = {"the pause menu": shell, "the skill web": main.get("_web_panel"), "the bench": main.get("_bench_panel"), "the settings": main.get("_settings")}
	for name in screens.keys():
		var node: Variant = screens[name]
		if node != null and bool((node as CanvasItem).visible):
			push_error("%s: the Escape that closed the menu also raised %s" % [lane, String(name)])
			return false
	if bool(main.get("inventory_open")) or bool(main.get("work_open")) or _state(main) != Session.State.PLAYING:
		push_error("%s: the Escape that closed the menu opened a screen or left the run (state %d)" % [lane, _state(main)])
		return false
	# The negative: no menu, the same key pauses; a second gives the street back.
	_tap(KEY_ESCAPE)
	await process_frame
	if _state(main) != Session.State.PAUSED:
		push_error("%s: with no menu open Escape did not pause, so the lane cannot tell the menu took it" % lane)
		return false
	_tap(KEY_ESCAPE)
	await process_frame
	if _state(main) != Session.State.PLAYING:
		push_error("%s: the second Escape did not give the street back" % lane)
		return false
	print("%s OK a menu opened low stops above the action bar on the art grid, a right click on yourself opens one headed 'you', Escape closes it and raises nothing, and with no menu the same key still pauses" % lane)
	return true
