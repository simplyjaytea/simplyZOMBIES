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
#   SETTINGS   Escape peels in order -- the legend first, settings only once it is gone
#   ROUNDTRIP  F5 writes a save F9 restores; a corrupt slot leaves the world untouched
#   CAMP-KEY   C is the camp key and only the camp key; Ctrl+C is the stance and only the stance
#   FOCUS      an open sheet swallows the street's keys, and the body stops at the panel
#   LEGEND     a dismissed legend stays dismissed across a boot, and F1 brings it back
#   DRAW       `_draw` completes by day and by night, and does not when the node is hidden
#   RUN-OVER   skipped, loudly, until the shell exists
#   SCENE      the scene this gate drives is the scene `project.godot` ships
#   KEYS       every legend row is bound and every binding has a row, both directions
#   SOCKET     the keys live in the router, and main.gd's frame loop reaches it
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
	ok = _the_run_over_screen() and ok

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
	main.queue_free()

	var draw_ok: bool = await _the_screen_draws_by_day_and_by_night()
	ok = draw_ok and ok

	_restore_user_files()
	var elapsed: int = Time.get_ticks_msec() - _started_ms
	ok = _the_gate_fits_its_budget(elapsed) and ok

	if ok:
		var skipped: String = "no lane skipped" if _skips.is_empty() else "skipped: %s" % ", ".join(PackedStringArray(_skips))
		print("PLAY_OK the scene boots, ticks, walks, opens its screens, saves and loads, camps on C and crouches on Ctrl+C, refuses the street's keys under an open sheet, keeps a dismissed legend dismissed, and draws by day and by night in %d ms (%s)" % [elapsed, skipped])
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


# The same boot, with the player standing on the street. The legend is a focus of its own since
# the input split -- it swallows every key but F1, Escape and Enter, which is exactly what a modal
# panel should do and exactly what would make TICKS, WALK and ROUNDTRIP judge nothing at all. So
# it is peeled the way a player peels it, with Escape, before any lane presses anything.
func _boot() -> Node:
	var main: Node = await _boot_scene()
	if main == null:
		return null
	var legend: Variant = main.get("_legend")
	if legend != null and bool((legend as CanvasItem).visible):
		_tap(KEY_ESCAPE)
		await process_frame
	return main


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

# Escape peels layers in an order main.gd's own comment states: the legend first, because it is
# the thing in front of you, and settings only once nothing else is open. The negative is the
# first press -- if Escape opened settings while the legend was up, the player would be reading
# two panels at once, and the assertion that catches that is "settings is still hidden here".
func _escape_peels_in_order(main: Node) -> bool:
	var legend: Variant = main.get("_legend")
	var settings: Variant = main.get("_settings")
	if legend == null or settings == null:
		return _skip("SETTINGS", "the scene built no legend or settings panel")
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
	if bool((settings as CanvasItem).visible):
		push_error("SETTINGS: Escape opened settings behind the legend it was closing")
		return false
	_tap(KEY_ESCAPE)
	await process_frame
	if not bool((settings as CanvasItem).visible):
		push_error("SETTINGS: a second Escape did not open settings")
		return false
	_tap(KEY_ESCAPE)
	await process_frame
	if bool((settings as CanvasItem).visible):
		push_error("SETTINGS: Escape did not close settings again")
		return false
	print("SETTINGS OK Escape peels the legend first and opens settings only once it is gone")
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
	if not bool((legend as CanvasItem).visible):
		first.queue_free()
		push_error("LEGEND: a fresh machine did not open on the keys")
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

# The lane the shell turns on. Today the last survivor dies, `world.runOver` goes true, the HUD
# prints one line and the sim keeps ticking over the corpse -- there is no screen to assert and
# nothing to stop. Skipping loudly rather than passing quietly is the rule (CLAUDE.md's
# conventions); when `presentation/session.gd` exists this becomes: run over halts the ticks, the
# screen names the chronicle's last lines, and a new run yields a world that moves again.
func _the_run_over_screen() -> bool:
	if ResourceLoader.exists(SESSION_GD):
		push_error("RUN-OVER: %s exists now, so this lane must stop skipping and assert the shell" % SESSION_GD)
		return false
	return _skip("RUN-OVER", "the shell does not exist yet; the lane lands with presentation/session.gd")


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
	print("SOCKET OK main.gd handles no input, the router has _input, _unhandled_input and pump, _ready builds it, _process pumps it, F2 is gone and F8 is debug-only")
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
