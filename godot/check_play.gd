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
#   handler moves out of `main.gd` into its own node -- the next piece of this arc -- this gate
#   still reaches it instead of quietly becoming a dead socket that calls a function nobody else
#   calls. `Input.parse_input_event` was the other candidate and is wrong here: it buffers to the
#   next frame and mutates the global `Input.is_key_pressed` state the game itself reads.
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
#   DRAW       `_draw` completes by day and by night, and does not when the node is hidden
#   RUN-OVER   skipped, loudly, until the shell exists
#   SCENE      the scene this gate drives is the scene `project.godot` ships
#   KEYS       the keys this gate presses are the keys the legend names
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
const SESSION_GD: String = "res://presentation/session.gd"
const SAVE_PATH: String = "user://simplyzombies.save.json"
const PREFS_PATH: String = "user://ui_prefs.json"

const Clock = preload("res://sim/time/clock.gd")
const Legend = preload("res://ui/legend.gd")
const UiPrefs = preload("res://ui/prefs.gd")
const SimSave = preload("res://sim/save.gd")

# The frame loop's own delta. main.gd's TICK_SECONDS, named again here rather than read off the
# scene, so a gate that claims "one frame, one tick" is not quoting the thing it is judging.
const TICK_SECONDS: float = 1.0 / 20.0
# Under a minute, docs/00 pillar 6: this runs in the chain before every commit, and a gate
# nobody waits for is a gate nobody runs.
const BUDGET_MS: int = 60000

# Every key this gate presses, paired with the row the legend must carry for it. The KEYS lane
# reads both directions off this one table, so a key added to a lane without a legend row is red.
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
]

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
	ok = _the_run_over_screen() and ok

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
	main.queue_free()

	var draw_ok: bool = await _the_screen_draws_by_day_and_by_night()
	ok = draw_ok and ok

	_restore_user_files()
	var elapsed: int = Time.get_ticks_msec() - _started_ms
	ok = _the_gate_fits_its_budget(elapsed) and ok

	if ok:
		var skipped: String = "no lane skipped" if _skips.is_empty() else "skipped: %s" % ", ".join(PackedStringArray(_skips))
		print("PLAY_OK the scene boots, ticks, walks, opens its screens, saves and loads, camps on C and crouches on Ctrl+C, and draws by day and by night in %d ms (%s)" % [elapsed, skipped])
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


func _boot() -> Node:
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

# A held key is not a tap: main.gd tracks the down event and `_pump_input` turns the held set into
# one `move` command per change of direction. So the lane holds W, runs frames, and asks the sim
# where the body went -- and then releases it and asks whether it stopped, which is the half a
# "the key works" assertion usually leaves out.
func _a_held_key_walks_the_body(main: Node) -> bool:
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
	main.call("_pump_input")
	var diagonal: Variant = null
	for cmd_v in _pending(main):
		var cmd: Dictionary = cmd_v as Dictionary
		if String(cmd.get("type", "")) == "move":
			diagonal = cmd
	_release(KEY_W)
	_release(KEY_D)
	main.call("_pump_input")
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
	var held: Dictionary = main.get("_held") as Dictionary
	if held.has(KEY_S):
		push_error("CAMP-KEY: Ctrl+S entered the held-movement set, so standing up steps backwards")
		return false
	print("CAMP-KEY OK C camps, Shift+C strikes, Ctrl+C crouches, Ctrl+S stands without stepping back")
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
	print("KEYS OK the legend names every one of the %d keys this gate presses, and the stance ladder reads as Ctrl" % PRESSED_KEYS.size())
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
