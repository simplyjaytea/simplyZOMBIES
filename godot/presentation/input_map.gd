extends Node
# Every key the game reads, in one place.
#
# This was `main.gd`'s `_input`, `_unhandled_input` and `_pump_input` until the alpha shell's
# input split (docs/30, "The alpha shell, 2026-09-16"). It is a **child Node with its own
# handlers**, not a helper main calls: the engine's own dispatch reaches it, so a gate that
# pushes an event through the viewport still presses a real key, and the textual gates that used
# to slice `_input` out of `main.gd` follow by one path constant rather than losing their needle.
#
# `main.gd` keeps the screens themselves -- `_set_inventory_open`, `_set_web_open`,
# `_toggle_legend`, `_save`, `_load`, `_update_hud` and all the drawing. This file decides only
# which of them a press is allowed to reach, and turns held keys into movement.
#
# Three things live here that did not live in `_input`:
#
# * **`BINDINGS`, the rebind seam.** Raw keycodes in one table, **not** InputMap actions. Two
#   reasons, both load-bearing: the gates read this file as text for `KEY_*` literals, and
#   `Input.is_action_pressed` cannot see an event pushed synchronously through the viewport, so a
#   gate driving the scene would be judging a different input path from the one a player uses.
#   The modifier column is what separates the camp key from the crouch rung -- `C` and `Ctrl+C`
#   are two rows of this table, not one key with two meanings.
# * **`_focus()` and `ALLOWED`.** Which screen has the player's attention, and which actions still
#   fire under it. Before the split every key fired under every open panel: W walked the body
#   while you read the inventory, F swung at nothing while the skill web was up.
# * **Leaving the street stops the body.** Opening a screen with a key still held clears the held
#   set and pushes one zero move, so a walk does not continue behind the panel you just opened.
#
# The sim is never read for presentation state and never written except through a command --
# that rule is main.gd's and it is this file's too. Everything here ends in `commands.push`.

const CameraUtil = preload("res://presentation/camera.gd")
const Pick = preload("res://presentation/pick.gd")

# The node this routes for. Set by main.gd before `add_child`, and `Variant` rather than a typed
# reference on purpose: main.gd preloads this script, so naming its type here would be a cycle.
var main: Variant = null

# movement input held
var _held: Dictionary = {}
var _last_dx: float = 0.0
var _last_dy: float = 0.0
# Last aim angle pushed, so mouse motion only sends a command when the cursor has actually
# swung the bearing -- the sim ignores aim while moving anyway (world.gd's "aim" case), this
# just keeps the command queue from carrying a no-op per polled motion event.
var _last_aim: float = 1e9
# Which of the non-sprint rungs (Ctrl+Z/Ctrl+C/Ctrl+S/Ctrl+V) is selected, so releasing Shift
# returns to it rather than to a fixed default. Presentation-local only -- the sim never reads
# this, it only ever sees the stance commands _push_stance sends.
var _selected_stance: int = 2 # Walk

# Cardinal: screen axes are world axes under the top-down projection, so W is
# straight up. Holding two adjacent keys still sums to a diagonal, same as ever.
# The interact key. E, by the owner's 2026-09-05 decision: doors, hoods, loot and everything
# else on the context ladder hang off this one key, and the legend names it once.
const INTERACT_KEY: Key = KEY_E
const MOVE_KEYS: Dictionary = {
	KEY_W: {"dx": 0.0, "dy": -1.0}, KEY_UP: {"dx": 0.0, "dy": -1.0},
	KEY_S: {"dx": 0.0, "dy": 1.0}, KEY_DOWN: {"dx": 0.0, "dy": 1.0},
	KEY_A: {"dx": -1.0, "dy": 0.0}, KEY_LEFT: {"dx": -1.0, "dy": 0.0},
	KEY_D: {"dx": 1.0, "dy": 0.0}, KEY_RIGHT: {"dx": 1.0, "dy": 0.0},
}

# The rebind seam: action -> the keycodes that fire it, the modifier column, the token
# `ui/legend.gd` prints for it, and (for the ladder) the rung it asks the sim for.
#
# `keys` is a list because a key row is genuinely plural -- the number pad's `+` is the same
# action as the row's `=`, and nothing downstream should care which one arrived. `ctrl` is the
# modifier column and it is compared exactly: a row with `ctrl: false` does not fire under Ctrl,
# which is the whole reason `C` (camp) and `Ctrl+C` (crouch) can both exist. `legend` is the key
# column `ui/legend.gd` shows, and `godot:check:play`'s KEYS lane reads it in both directions --
# a binding with no legend row is red unless the gate excuses it by name, and a legend row naming
# a key nothing binds is red too.
#
# Movement and interact are deliberately *not* rows here: `MOVE_KEYS` carries a vector per key
# and `INTERACT_KEY` is named once as a constant because `check_vehicles.gd` reads it that way.
# `_action_for` folds both into the same action vocabulary, so the focus table below can speak
# about them.
const BINDINGS: Dictionary = {
	"save": {"keys": [KEY_F5], "ctrl": false, "legend": ["F5"]},
	"load": {"keys": [KEY_F9], "ctrl": false, "legend": ["F9"]},
	"pause": {"keys": [KEY_P], "ctrl": false, "legend": ["P"]},
	"sheets": {"keys": [KEY_M], "ctrl": false, "legend": ["M"]},
	"overlay": {"keys": [KEY_O], "ctrl": false, "legend": ["O"]},
	"legend": {"keys": [KEY_F1], "ctrl": false, "legend": ["F1"]},
	"dismiss": {"keys": [KEY_ENTER, KEY_KP_ENTER], "ctrl": false, "legend": []},
	"escape": {"keys": [KEY_ESCAPE], "ctrl": false, "legend": ["Esc"]},
	"inventory": {"keys": [KEY_TAB], "ctrl": false, "legend": ["Tab"]},
	"work": {"keys": [KEY_J], "ctrl": false, "legend": ["J"]},
	"web": {"keys": [KEY_K], "ctrl": false, "legend": ["K"]},
	"shout": {"keys": [KEY_SPACE], "ctrl": false, "legend": ["Space"]},
	"swing": {"keys": [KEY_F], "ctrl": false, "legend": ["F"]},
	"rescue": {"keys": [KEY_H], "ctrl": false, "legend": ["H"]},
	"fire": {"keys": [KEY_G], "ctrl": false, "legend": ["G"]},
	"reload": {"keys": [KEY_R], "ctrl": false, "legend": ["R"]},
	"treat": {"keys": [KEY_T], "ctrl": false, "legend": ["T"]},
	"camp": {"keys": [KEY_C], "ctrl": false, "legend": ["C"]},
	"slower": {"keys": [KEY_MINUS, KEY_KP_SUBTRACT], "ctrl": false, "legend": ["-"]},
	"faster": {"keys": [KEY_EQUAL, KEY_KP_ADD], "ctrl": false, "legend": ["="]},
	"strip": {"keys": [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6], "ctrl": false, "legend": ["1 … 6"]},
	"sprint": {"keys": [KEY_SHIFT], "ctrl": false, "legend": ["Shift"]},
	"stance.prone": {"keys": [KEY_Z], "ctrl": true, "legend": ["Ctrl+Z"], "stance": 0},
	"stance.crouch": {"keys": [KEY_C], "ctrl": true, "legend": ["Ctrl+C"], "stance": 1},
	"stance.stand": {"keys": [KEY_S], "ctrl": true, "legend": ["Ctrl+S"], "stance": 2},
	"stance.jog": {"keys": [KEY_V], "ctrl": true, "legend": ["Ctrl+V"], "stance": 3},
	"debug": {"keys": [KEY_F8], "ctrl": false, "legend": []},
}

# The screens, in the order `_focus` asks about them. `shell` -- the title, the pause menu and
# the run-over screen -- is at the front because it sits in front of everything else on screen,
# so it takes the keys first: the slot this list reserved for it in a comment until the shell
# landed (docs/30, "The alpha shell, 2026-09-16").
const FOCUSES: Array[String] = ["shell", "legend", "settings", "web", "bench", "sheet", "work", "street"]

# What still fires under each screen. `street` is deliberately absent: it is the one focus with
# no gate at all, and an empty row here would read as "nothing fires" rather than "everything
# does". Each row was read off today's behaviour rather than invented -- the sheet has always
# rotated on R and spent the belt on the number row, the web has always closed on its own K, and
# the legend has always gone down on any of F1, Escape and Enter.
const ALLOWED: Dictionary = {
	# The shell is a menu and nothing else gets through it: the four navigation keys and the two
	# that choose or go back. `move` is here because Up, Down, W and S answer "move" in the
	# vocabulary below -- they are the same four keys, and under this focus they walk a cursor
	# rather than a body. Nothing else fires, so a title screen is not somewhere you can shoot.
	"shell": ["move", "dismiss", "escape"],
	"legend": ["legend", "escape", "dismiss"],
	"settings": ["escape"],
	"web": ["web", "escape", "legend"],
	# The bench is the sim's own screen -- `benchFocus` on the survivor opens it and
	# `bench.close` shuts it -- so Escape is the only key that has anything to say to it.
	"bench": ["escape"],
	"sheet": ["inventory", "escape", "reload", "strip", "sheets", "legend"],
	"work": ["work", "escape"],
}


# Which screen has the player. Precedence, not a set: two panels can be up at once (settings over
# an open sheet), and the one in front is the one whose keys mean something.
func _focus() -> String:
	if main == null:
		return "street"
	# The shell first: the title, the pause menu and the run-over screen are in front of
	# everything, including the settings sheet the pause menu itself opens (which is why opening
	# settings from the menu closes the menu -- see main.gd's `_on_shell_action`).
	if _is_up(main._shell):
		return "shell"
	if _is_up(main._legend):
		return "legend"
	if _is_up(main._settings):
		return "settings"
	if _is_up(main._web_panel):
		return "web"
	if _is_up(main._bench_panel):
		return "bench"
	if bool(main.inventory_open):
		return "sheet"
	if bool(main.work_open):
		return "work"
	return "street"


func _is_up(node: Variant) -> bool:
	return node != null and bool((node as CanvasItem).visible)


# The action a key event asks for, or "" for a key nothing binds. Movement and interact answer
# here too, so the focus table can name them without a second vocabulary.
func _action_for(ke: InputEventKey) -> String:
	for action in BINDINGS.keys():
		var row: Dictionary = BINDINGS[action] as Dictionary
		if bool(row["ctrl"]) != ke.ctrl_pressed:
			continue
		if (row["keys"] as Array).has(ke.keycode):
			return String(action)
	if ke.ctrl_pressed:
		return ""
	if ke.keycode == INTERACT_KEY:
		return "interact"
	if MOVE_KEYS.has(ke.keycode):
		return "move"
	return ""


func _allows(focus: String, action: String) -> bool:
	if focus == "street":
		return true
	return (ALLOWED.get(focus, []) as Array).has(action)


# A key still held when a screen opens would otherwise keep walking the body behind it. Clearing
# the set is not enough -- the sim holds the last `move` command's vector until a new one
# arrives -- so the pump runs once more and pushes the zero.
#
# Called on exactly two edges, and deliberately not on every off-street press: the press that
# *took* the focus off the street, and a press the focus table *refused*. Calling it after every
# press instead would stop the body whatever `ALLOWED` said, which sounds safer and is not -- it
# would make the table unfalsifiable, and a focus table no gate can turn red is a focus table
# that quietly stops being read. The refused-press edge is what covers a screen the sim opened
# by itself, like the bench: the next movement key is refused, and the refusal lets go.
func _release_the_street() -> void:
	if _held.is_empty():
		return
	_held.clear()
	pump()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var ke: InputEventKey = event as InputEventKey
		if main == null:
			return
		# What this press asks for, and whether the screen in front lets it through. Resolved
		# once: the same answer gates the press, drives the stance ladder and decides whether the
		# key joins the held-movement set, so BINDINGS is read on every keystroke rather than
		# sitting beside a switch that repeats it.
		var action: String = _action_for(ke)
		var focus: String = _focus()
		if not _allows(focus, action):
			_release_the_street()
			return
		# The shell answers its own keys and the game sees none of them. It returns here rather
		# than falling through the match below, because every key it takes means something else
		# down there: Enter dismisses the legend, Escape peels a panel, W joins the held set and
		# walks the body behind the menu.
		if focus == "shell":
			if main._shell != null and bool(main._shell.call("key", ke)):
				main.queue_redraw()
			return
		# The one interact key, named once (INTERACT_KEY) rather than as a literal in the match
		# below, because a match arm binds an identifier instead of comparing against it. It
		# pushes `use.context` and nothing else: fortify's ladder (SimFortify._use_context)
		# decides what "interact" means where you stand -- a loose item, a container, a
		# survivor at the gate, a car's hood from the nose, its door from the side, out from
		# the wheel, a window, a bed. Nothing here knows which; the sim decides.
		if ke.keycode == INTERACT_KEY:
			if main.world != null: main.world.commands.push({"type": "use.context"})
		match ke.keycode:
			KEY_F5: main._save()
			KEY_F9: main._load()
			KEY_P: main._toggle_pause()
			KEY_M:
				main.show_sheets = not main.show_sheets
				if main._hud != null: main._hud.set("show_raw", main.show_sheets)
			KEY_O: main._cycle_overlay()
			KEY_F1: main._toggle_legend()
			KEY_ENTER, KEY_KP_ENTER:
				# Dismiss-only: Enter closes the legend but never opens anything. One of the
				# three explicit dismissals that make it stay down across a boot.
				if main._legend != null and main._legend.visible: main._dismiss_legend()
			KEY_ESCAPE:
				# Escape peels layers in order, and the order is `_focus()`'s own rather than a
				# second list beside it: the screen in front is the screen Escape is talking to.
				# It used to be a chain of `elif`s over the same panels in a different order, and
				# a settings sheet over an open web closed the web underneath it.
				#
				# The legend first (it is drawn over everything but the shell), then settings,
				# then the web before the bench -- the web is the thing most recently opened by a
				# key, and closing it is what looking back at the street would have done.
				if main._legend != null and main._legend.visible:
					main._dismiss_legend()
				elif main._web_panel != null and focus == "web":
					main._set_web_open(false)
				elif main.world != null and main._bench_panel != null and focus == "bench":
					main.world.commands.push({"type": "bench.close"})
				elif main._settings != null and main._settings.visible:
					# Back to whatever opened it, which is the pause menu when the run is paused.
					main.call("_close_settings")
				elif main.world != null and main._inventory_panel != null and main._inventory_panel.has_method("loot_open") and bool(main._inventory_panel.call("loot_open")):
					main.world.commands.push({"type": "container.close"})
				elif focus == "street":
					# Nothing open: the pause menu. Escape used to open the settings sheet from
					# here, and settings is a row on that menu now (docs/30, "The alpha shell").
					main.call("_pause_to_menu")
				elif main._settings != null:
					main._settings.visible = true
			KEY_TAB:
				main._set_inventory_open(not main.inventory_open)
			KEY_J:
				main.work_open = not main.work_open
				if main._work_panel != null:
					main._work_panel.visible = main.work_open
					if main.work_open and main._work_panel.has_method("set_world"):
						main._work_panel.call("set_world", main.world)
			KEY_K:
				# Tab owns the screen while the sheet is up, the same rule the R arm keeps.
				if not main.inventory_open:
					main._set_web_open(not main.web_open)
			KEY_SPACE:
				if main.world != null: main.world.commands.push({"type": "shout"})
			KEY_F:
				if main.world != null: main.world.commands.push({"type": "swing"})
			KEY_H:
				# Its own key rather than another meaning for F: swinging at the shambler that
				# has hold of somebody is a different answer, and both must stay available.
				# Who gets pulled out is the sim's decision -- see SimShambler.rescue_target.
				if main.world != null: main.world.commands.push({"type": "rescue"})
			KEY_G:
				if main.world != null: main.world.commands.push({"type": "fire"})
			KEY_R:
				if main.inventory_open and main._inventory_panel != null and main._inventory_panel.has_method("rotate"):
					main._inventory_panel.call("rotate")
				elif main.world != null:
					main.world.commands.push({"type": "reload"})
			KEY_T:
				# One key, two meanings, both decided in the sim: start first aid on the
				# wound that matters, or stop the one already in progress. Presentation
				# picks neither the target nor the verb -- see SimTreatment.context.
				if main.world != null: main.world.commands.push({"type": "treat.context"})
			KEY_C:
				# Camp: its own key rather than a rung on E's ladder, because establishing one
				# moves where home is and doing that by accident -- pressing E on empty ground
				# with a trap and a bait already down -- is worse than one more key. E stays
				# "act on what is in front of you"; C is a deliberate commitment, which is what
				# Task 8 asks a camp to be. Shift+C strikes it; the sim decides which camp.
				#
				# `not ke.ctrl_pressed` is the half of the double bind that lived here: C used to
				# fall through this arm *and* the walk-stance line below, so one press moved home
				# and stood the body up. The owner kept camp on C and moved the ladder onto Ctrl
				# (docs/30, "The alpha shell, 2026-09-16"), so Ctrl+C is the crouch and belongs to
				# the ladder below, not to this arm. BINDINGS' modifier column is where that is
				# written down now; this guard is what the match arm itself can see.
				#
				# `ke.shift_pressed`, not `Input.is_key_pressed(KEY_SHIFT)`: the flag rides on the
				# event, so a pushed event carries its own modifier and check_play.gd's CAMP-KEY
				# lane can tell a strike from an establish. The global read saw only a physical
				# keyboard, which is why nothing could ever test it.
				if main.world != null and not ke.ctrl_pressed:
					if ke.shift_pressed:
						main.world.commands.push({"type": "camp.abandon"})
					else:
						main.world.commands.push({"type": "camp.establish"})
			# The number row belongs to the quick strip since the 2026-09-08 overhaul, so
			# speed moved to the two keys beside it. A key that means two things mid-fight
			# is what the one-interact-key rule exists to avoid; P still pauses.
			KEY_MINUS, KEY_KP_SUBTRACT: main._step_speed(-1)
			KEY_EQUAL, KEY_KP_ADD: main._step_speed(1)
			KEY_1: main._strip_use(0)
			KEY_2: main._strip_use(1)
			KEY_3: main._strip_use(2)
			KEY_4: main._strip_use(3)
			KEY_5: main._strip_use(4)
			KEY_6: main._strip_use(5)
			KEY_F8:
				# The developer spawn menu, and only where there is a developer: the owner's
				# decision of 2026-09-16 keeps it out of a release build entirely, which is also
				# why `ui/legend.gd` no longer lists it. A player never finds this key.
				if OS.is_debug_build() and main._debug_panel != null:
					main._debug_panel.visible = not main._debug_panel.visible
					if main._debug_panel.visible and main._debug_panel.has_method("set_world"):
						main._debug_panel.call("set_world", main.world)
		# movement keys tracked for pump -- but never a Ctrl-modified one. Ctrl+S is the stand
		# rung of the ladder below, and a body that stood up and walked backwards at the same
		# time would be the double bind again in a second place. `_action_for` is what keeps them
		# apart: a Ctrl-modified S answers "stance.stand", never "move".
		if action == "move":
			_held[ke.keycode] = true
		# Shift is a latch on rung 4 (Sprint), not a key with its own stance number: press
		# pushes Sprint, release returns to whichever rung of the Ctrl ladder was last selected.
		# The sim decides whether the request is honoured -- see the zero-stamina gate in world.gd's
		# "stance" command case.
		if action == "sprint": _push_stance(4)
		# The stance ladder, on Ctrl since the owner's decision of 2026-09-16 (docs/30, "The
		# alpha shell"): Ctrl+Z prone, Ctrl+C crouch, Ctrl+S stand, Ctrl+V jog, Shift the sprint
		# latch above. It used to be the bare letters Z/X/C/V, and the C rung fired on the same
		# press as the camp arm in the match above -- standing up from a crouch started moving
		# home. The modifier is what separates them, and BINDINGS' `ctrl` column is where it is
		# written down; `_action_for` reads it off the event, so a gate can inject it. Ctrl+W is
		# deliberately not a rung: the browser owns it.
		if action.begins_with("stance."):
			var rung: int = int((BINDINGS[action] as Dictionary)["stance"])
			_selected_stance = rung
			_push_stance(rung)
		# And if that press is what took the focus off the street, the street lets go of whatever
		# was held: the walk stops at the panel rather than continuing behind it. The edge, not
		# the state -- see _release_the_street on why that distinction is the gate's.
		if focus == "street" and _focus() != "street":
			_release_the_street()
		main.queue_redraw()
	if event is InputEventKey and not event.pressed:
		var ke2: InputEventKey = event as InputEventKey
		# Releases are never focus-gated. They only ever *clear* state, and a key that went down
		# on the street and came up over an open sheet has to be let go of somewhere.
		if MOVE_KEYS.has(ke2.keycode): _held.erase(ke2.keycode)
		if ke2.keycode == KEY_SHIFT: _push_stance(_selected_stance)

# Pointer input lives in _unhandled_input, not _input, so any Control that consumed the
# click -- a pinned bag window, the settings sheet, the work grid -- has already eaten it
# and a click on UI never doubles as a trigger pull. GUI handling runs between the two.
func _unhandled_input(event: InputEvent) -> void:
	if main == null:
		return
	# Wheel zoom through the fixed ladder -- power-of-two multiples of the art-native
	# 32 so nearest-neighbour scaling never shimmers. Not while the inventory is open:
	# the wheel belongs to the panel there.
	if event is InputEventMouseButton and event.pressed and not main.inventory_open:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			CameraUtil.zoom_step(main.camera, 1)
			main.queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			CameraUtil.zoom_step(main.camera, -1)
			main.queue_redraw()
	# Mouse motion proposes an aim bearing; the sim takes it only while the body is
	# stationary (world.gd's "aim" case), so this is turning on the spot to track the
	# cursor, never steering.
	if event is InputEventMouseMotion and main.world != null and not main.inventory_open:
		var bearing: Variant = _aim_at((event as InputEventMouseMotion).position)
		if bearing != null and absf(angle_difference(float(bearing), _last_aim)) > 0.02:
			_last_aim = float(bearing)
			main.world.commands.push({"type": "aim", "radians": _last_aim})
	if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if main.world != null and not main.inventory_open:
			# A click on a colonist selects them -- their needs, pain and condition take the
			# HUD's left column in the third person until you click yourself or they die. A
			# click on your own pawn clears it. Anything else is the attack below, exactly as
			# before: Pick answers -1 for the street, a zombie, a corpse, a body you cannot see.
			var hit: int = Pick.pick_colonist(main.world, main.camera, (event as InputEventMouseButton).position)
			if hit >= 0:
				main._selected = -1 if hit == int(main.world.player) else hit
				main._update_hud()
				main.queue_redraw()
				return
			# Aim at the click first, then attack with whatever is actually in hand: the
			# trigger if a ranged weapon is equipped (fire converts itself to a reload on an
			# empty magazine -- ranged.gd owns that), the swing otherwise. G and F remain as
			# the key equivalents; the sim decides everything past the verb.
			var at: Variant = _aim_at((event as InputEventMouseButton).position)
			if at != null:
				_last_aim = float(at)
				main.world.commands.push({"type": "aim", "radians": _last_aim})
			if main.world.components.has_component(int(main.world.player), "rangedWeapon"):
				main.world.commands.push({"type": "fire"})
			else:
				main.world.commands.push({"type": "swing"})


# The bearing from the player's body to a screen point, in world space -- what an aim command
# carries. Null when there is nothing to aim from.
func _aim_at(screen_pos: Vector2) -> Variant:
	if main == null or main.world == null:
		return null
	var pos: Variant = main.world.components.get_component(int(main.world.player), "position")
	if not (pos is Dictionary):
		return null
	var at: Dictionary = CameraUtil.screen_to_world(main.camera, screen_pos.x, screen_pos.y)
	var dx: float = float(at["x"]) - float((pos as Dictionary)["x"])
	var dy: float = float(at["y"]) - float((pos as Dictionary)["y"])
	if dx == 0.0 and dy == 0.0:
		return null
	return atan2(dy, dx)


func _push_stance(target: int) -> void:
	if main == null or main.world == null: return
	# Reads sim, never writes it -- main.gd's own header. The stance module (world.gd's
	# "stance" command case and the player.advance-posture system) owns ticks_left and the
	# current/target transition entirely; this used to reach into posture directly and set
	# ticks_left on a dict that (pre-SimStances.make_posture) never had that key at all, an
	# invalid-index crash on every stance-key press.
	main.world.commands.push({"type": "stance", "stance": target})


# The held set turned into at most one `move` command. Called by main.gd's `_process` every
# unpaused frame; it was `_pump_input` there and lost the prefix with the move, because a method
# another node calls is not private.
func pump() -> void:
	if main == null or main.world == null: return
	var dx: float = 0.0; var dy: float = 0.0
	for k in _held.keys():
		var d: Dictionary = MOVE_KEYS.get(int(k), {}) as Dictionary
		dx += float(d.get("dx", 0.0)); dy += float(d.get("dy", 0.0))
	if dx != _last_dx or dy != _last_dy:
		main.world.commands.push({"type": "move", "dx": dx, "dy": dy})
		_last_dx = dx; _last_dy = dy
