extends Node2D
# R4 presentation — top-down district, camera, visibility, light, paperdoll glimpse,
# grid inventory (Controls), keyboard/pointer/pause/speed/save. Reads sim, never writes it.
# Port of src/render/* + src/ui/inventory.ts + src/main.ts split for Godot native;
# projection since diverged to top-down (the TS oracle stays isometric, frozen).
# ponytail: no atlases yet (circles/rects for bodies and tiles). Add ModelSprites when art lands.

const WorldRes = preload("res://sim/world.gd")
const ContentLoader = preload("res://platform/content_loader.gd")
const TopDownProjection = preload("res://presentation/projection.gd")
const CameraUtil = preload("res://presentation/camera.gd")
const Palette = preload("res://presentation/palette.gd")
const Appearance = preload("res://presentation/appearance.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimSurface = preload("res://sim/map/surface.gd")
const Clock = preload("res://sim/time/clock.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimCondition = preload("res://sim/condition.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimSurvivors = preload("res://sim/modules/survivors.gd")
const SimAptitudes = preload("res://sim/modules/aptitudes.gd")
const SimSave = preload("res://sim/save.gd")
const PlatformStorage = preload("res://platform/storage.gd")
const ContentReload = preload("res://platform/content_reload.gd")
const ContentValidator = preload("res://platform/content_validator.gd")
const SimVisibility = preload("res://sim/vision/visibility.gd")
const SimSightings = preload("res://sim/modules/sightings.gd")
const SimLight = preload("res://sim/vision/light.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const PresentationSfx = preload("res://presentation/sfx.gd")

const TICK_HZ: int = 20
const TICK_SECONDS: float = 1.0 / 20.0
const NIGHT_WASH: float = 0.8
const MEMORY_TICKS: int = 60

var world: Variant = null
var content: Dictionary = {}
var fixture: Dictionary = {}
# The district id the session started with, so F2 ("leave for another city") rerolls the seed
# but keeps the same district rather than silently switching one out from under the player.
var _district_id: String = SimBoot.DEFAULT_DISTRICT
var camera: Dictionary = CameraUtil.create_camera()
var commands_by_tick: Dictionary = {}
var accumulator: float = 0.0
var paused: bool = false
var speed: int = 1
var attention_channel: String = "off" # off/noise/scent/sight/light
var inventory_open: bool = false
var work_open: bool = false
var show_sheets: bool = false
var tick_count: int = 0

# ui refs (created in _ready if CanvasLayer available)
var _hud: Control = null
var _legend: Control = null
var _inventory_panel: Control = null
var _work_panel: Control = null
var _paperdoll: Control = null
var _settings: Control = null
var _debug_panel: Control = null
var _selected: int = -1

# paperdoll glimpse state (bottom-right diagram, not world sprite)
var _glimpse_parts: Array = []
var _glimpse_stance: int = 2 # Walk
var _glimpse_worst: int = 0

var _fingerprint: String = ""
var _fingerprint_at: float = -1e9
var _visibility: Variant = null
var _light: Variant = null
var _map: Variant = null
var _content_error: String = ""
# Doorway tiles, {tile index: true}, and the map object they were read off. Rebuilt when the map
# changes identity (a reboot, a load) and never per frame -- see _threshold_tiles.
var _thresholds: Dictionary = {}
var _thresholds_from: Variant = null
var _content_poll_at: float = -1e9
var _sfx: Node = null

# movement input held
var _held: Dictionary = {}
var _last_dx: float = 0.0
var _last_dy: float = 0.0
# Last aim angle pushed, so mouse motion only sends a command when the cursor has actually
# swung the bearing -- the sim ignores aim while moving anyway (world.gd's "aim" case), this
# just keeps the command queue from carrying a no-op per polled motion event.
var _last_aim: float = 1e9
# Which of the non-sprint rungs (Z/X/C/V) is selected, so releasing Shift returns to it rather
# than to a fixed default. Presentation-local only -- the sim never reads this, it only ever
# sees the stance commands _push_stance sends.
var _selected_stance: int = 2 # Walk

# Cardinal: screen axes are world axes under the top-down projection, so W is
# straight up. Holding two adjacent keys still sums to a diagonal, same as ever.
const MOVE_KEYS: Dictionary = {
	KEY_W: {"dx": 0.0, "dy": -1.0}, KEY_UP: {"dx": 0.0, "dy": -1.0},
	KEY_S: {"dx": 0.0, "dy": 1.0}, KEY_DOWN: {"dx": 0.0, "dy": 1.0},
	KEY_A: {"dx": -1.0, "dy": 0.0}, KEY_LEFT: {"dx": -1.0, "dy": 0.0},
	KEY_D: {"dx": 1.0, "dy": 0.0}, KEY_RIGHT: {"dx": 1.0, "dy": 0.0},
}

func _ready() -> void:
	content = ContentLoader.load_tree()
	var parity: bool = false
	var seed_arg: int = SimBoot.DISTRICT_SEED
	var district_arg: String = SimBoot.DEFAULT_DISTRICT
	# `--seed=N` / `--district=<id>` follow the `--parity` precedent (args after `--`, no
	# separate lookup table) but carry their value inline rather than as a following token,
	# since there is exactly one of each and never a bare flag needing a next-arg peek.
	for arg in OS.get_cmdline_user_args():
		var a: String = String(arg)
		if a == "--parity":
			parity = true
		elif a.begins_with("--seed="):
			var raw_seed: String = a.trim_prefix("--seed=")
			if raw_seed.is_valid_int():
				seed_arg = int(raw_seed)
			else:
				push_warning("main: malformed --seed=%s, using default %d" % [raw_seed, seed_arg])
		elif a.begins_with("--district="):
			var raw_district: String = a.trim_prefix("--district=")
			if raw_district.is_empty():
				push_warning("main: malformed --district=, using default %s" % district_arg)
			else:
				district_arg = raw_district
	if parity:
		_visibility = SimVisibility.new()
		_light = SimLight.new()
		var fixture_path: String = "res://parity/r1-walking-skeleton.json"
		var f := FileAccess.open(fixture_path, FileAccess.READ)
		if f != null:
			fixture = JSON.parse_string(f.get_as_text())
			world = WorldRes.new(fixture)
			for cmd_v in fixture.get("commands", []):
				var timed: Dictionary = cmd_v as Dictionary
				var at_tick: int = int(timed.get("tick", 0))
				var cmd: Dictionary = timed.duplicate(true)
				cmd.erase("tick")
				if not commands_by_tick.has(at_tick):
					commands_by_tick[at_tick] = []
				(commands_by_tick[at_tick] as Array).append(cmd)
		if world != null:
			SimSurvivors.boot_playable(world)
	else:
		_boot_world(seed_arg, district_arg)
	_resize_camera()
	_ensure_ui()
	_sfx = PresentationSfx.new()
	add_child(_sfx)
	queue_redraw()
	print("GODOT_R1_READY")
	if world != null:
		print("GODOT_R4_READY zoom %.1f map %dx%d" % [float(camera["zoom"]), int(world.map_width), int(world.map_height)])

# Boots (or reboots) the playable world on a given seed and district. _ready calls this once on
# startup and F2 ("leave for another city") calls it again on a fresh random seed, so the two
# share exactly one boot path -- nothing about standing up a world may live only in _ready.
# Does not touch _ensure_ui() or _sfx: those are scene children created once, not per-run state.
func _boot_world(seed_val: int, district_id: String) -> void:
	var boot: Dictionary = SimBoot.playable(seed_val, SimTileMap.DISTRICT_TILES, district_id)
	world = boot["world"]
	_map = boot["map"]
	_visibility = world.vision
	_light = world.light
	fixture = {"seed": int(world.seed), "tick_hz": TICK_HZ}
	_district_id = district_id
	# Per-run presentation state that _ready would otherwise leave stale on a reboot: the
	# cached player-id selection, the paperdoll glimpse and dev-sheet fingerprint (all read
	# models over the *previous* world), and the tick tally. The camera itself has no target
	# to reset -- follow_camera recentres it below, unsmoothed.
	_selected = -1
	_glimpse_parts = []
	_glimpse_stance = 2
	_glimpse_worst = 0
	_fingerprint = ""
	_fingerprint_at = -1e9
	_content_error = ""
	tick_count = 0
	_resize_camera()

# F2: a fresh run on a new random seed, same district the session started with. The seed is
# generated here, presentation-side, and everything downstream of it is deterministic --
# RandomNumberGenerator is fine in godot/presentation/ (the sim/ RNG ban is sim/ only).
func _leave_for_another_city() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var new_seed: int = rng.randi_range(1, 0x7fffffff) # positive 32-bit: SimBoot.playable's seed
	_boot_world(new_seed, _district_id)
	queue_redraw()

func _notification(what: int) -> void:
	if what == 413: # NOTIFICATION_RESIZED
		_resize_camera()
		queue_redraw()

func _resize_camera() -> void:
	var vp: Vector2 = get_viewport_rect().size
	if vp.x < 1: vp = Vector2(1920, 1080)
	camera["width"] = vp.x
	camera["height"] = vp.y
	# follow player
	if world != null:
		var pos: Variant = world.components.get_component(world.player, "position")
		if pos is Dictionary:
			CameraUtil.follow_camera(camera, float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]), int(world.map_width), int(world.map_height))

func _ensure_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "R4UI"
	add_child(layer)
	# The player HUD. Four corners of prose; the old developer string lives inside it behind M.
	var hud_script: GDScript = load("res://ui/hud.gd") as GDScript
	if hud_script != null:
		_hud = hud_script.new() as Control
		_hud.name = "Hud"
		layer.add_child(_hud)
	# The keys, shown once on a fresh run so the bindings are discoverable without README.md.
	var legend_script: GDScript = load("res://ui/legend.gd") as GDScript
	if legend_script != null:
		_legend = legend_script.new() as Control
		_legend.name = "Legend"
		_legend.visible = true
		layer.add_child(_legend)
	# inventory layer (always present: draws the full screen on Tab, and any pinned bag
	# windows while playing; input passes through it when closed)
	var inv_script: GDScript = load("res://ui/inventory_panel.gd") as GDScript
	if inv_script != null:
		_inventory_panel = inv_script.new() as Control
		layer.add_child(_inventory_panel)
	var work_script: GDScript = load("res://ui/work_panel.gd") as GDScript
	if work_script != null:
		_work_panel = work_script.new() as Control
		_work_panel.visible = false
		_work_panel.position = Vector2(16, 240)
		# Taller than before: work_panel.gd's rows grew a second line (person_clause) and then a
		# third (what they know, and what a Manual survivor could learn), so ROW_H grew with
		# them -- the same six rows now need more height to stay on screen at once.
		_work_panel.size = Vector2(1520, 540)
		layer.add_child(_work_panel)
	# paperdoll glimpse bottom-left (always visible, cheap); the HUD keys hint moved to the
	# bottom-right corner to make this one free.
	var doll_script: GDScript = load("res://ui/paperdoll.gd") as GDScript
	if doll_script != null:
		_paperdoll = doll_script.new() as Control
		_paperdoll.custom_minimum_size = Vector2(280, 280)
		_paperdoll.anchor_left = 0.0; _paperdoll.anchor_top = 1.0; _paperdoll.anchor_right = 0.0; _paperdoll.anchor_bottom = 1.0
		_paperdoll.offset_left = 16; _paperdoll.offset_top = -296; _paperdoll.offset_right = 296; _paperdoll.offset_bottom = -16
		layer.add_child(_paperdoll)
	# debug spawn menu (F8) -- dev tooling beside the M raw sheet
	var debug_script: GDScript = load("res://ui/debug_panel.gd") as GDScript
	if debug_script != null:
		_debug_panel = debug_script.new() as Control
		_debug_panel.visible = false
		_debug_panel.position = Vector2(16, 120)
		_debug_panel.size = Vector2(480, 820)
		layer.add_child(_debug_panel)
	# settings (Esc), topmost so it draws over every other screen
	var settings_script: GDScript = load("res://ui/settings_panel.gd") as GDScript
	if settings_script != null:
		_settings = settings_script.new() as Control
		_settings.visible = false
		_settings.set("on_changed", _on_ui_prefs_changed)
		layer.add_child(_settings)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var ke: InputEventKey = event as InputEventKey
		match ke.keycode:
			KEY_F5: _save()
			KEY_F9: _load()
			KEY_F2: _leave_for_another_city()
			KEY_P: _toggle_pause()
			KEY_M:
				show_sheets = not show_sheets
				if _hud != null: _hud.set("show_raw", show_sheets)
			KEY_O: _cycle_overlay()
			KEY_F1: _toggle_legend()
			KEY_ENTER, KEY_KP_ENTER:
				# Dismiss-only: Enter closes the legend but never opens anything.
				if _legend != null and _legend.visible: _legend.visible = false
			KEY_ESCAPE:
				# Escape peels layers in order: the legend first, then settings toggles.
				if _legend != null and _legend.visible:
					_legend.visible = false
				elif _settings != null:
					_settings.visible = not _settings.visible
			KEY_TAB:
				inventory_open = not inventory_open
				if _inventory_panel != null and _inventory_panel.has_method("set_open"):
					_inventory_panel.call("set_open", inventory_open)
					if inventory_open and _inventory_panel.has_method("set_world"):
						_inventory_panel.call("set_world", world, world.player)
				if _hud != null: _hud.visible = not inventory_open
				# The body panel has its own doll; the corner glimpse duplicating it under
				# the open screen is noise.
				if _paperdoll != null: _paperdoll.visible = not inventory_open
			KEY_J:
				work_open = not work_open
				if _work_panel != null:
					_work_panel.visible = work_open
					if work_open and _work_panel.has_method("set_world"):
						_work_panel.call("set_world", world)
			KEY_SPACE:
				if world != null: world.commands.push({"type": "shout"})
			KEY_F:
				if world != null: world.commands.push({"type": "swing"})
			KEY_H:
				# Its own key rather than another meaning for F: swinging at the shambler that
				# has hold of somebody is a different answer, and both must stay available.
				# Who gets pulled out is the sim's decision -- see SimShambler.rescue_target.
				if world != null: world.commands.push({"type": "rescue"})
			KEY_G:
				if world != null: world.commands.push({"type": "fire"})
			KEY_R:
				if inventory_open and _inventory_panel != null and _inventory_panel.has_method("rotate"):
					_inventory_panel.call("rotate")
				elif world != null:
					world.commands.push({"type": "reload"})
			KEY_E:
				if world != null: world.commands.push({"type": "use.context"})
			KEY_T:
				# One key, two meanings, both decided in the sim: start first aid on the
				# wound that matters, or stop the one already in progress. Presentation
				# picks neither the target nor the verb -- see SimTreatment.context.
				if world != null: world.commands.push({"type": "treat.context"})
			KEY_1: speed = 1
			KEY_2: speed = 3
			KEY_3: speed = 10
			KEY_F8:
				if _debug_panel != null:
					_debug_panel.visible = not _debug_panel.visible
					if _debug_panel.visible and _debug_panel.has_method("set_world"):
						_debug_panel.call("set_world", world)
		# movement keys tracked for pump
		if MOVE_KEYS.has(ke.keycode):
			_held[ke.keycode] = true
		# Shift is a latch on rung 4 (Sprint), not a key with its own stance number: press
		# pushes Sprint, release returns to whichever of Z/X/C/V was last selected. The sim
		# decides whether the request is honoured -- see the zero-stamina gate in world.gd's
		# "stance" command case.
		if ke.keycode == KEY_SHIFT: _push_stance(4)
		# stance keys Z/X/C/V
		if ke.keycode == KEY_Z: _selected_stance = 0; _push_stance(0)
		if ke.keycode == KEY_X: _selected_stance = 1; _push_stance(1)
		if ke.keycode == KEY_C: _selected_stance = 2; _push_stance(2)
		if ke.keycode == KEY_V: _selected_stance = 3; _push_stance(3)
		queue_redraw()
	if event is InputEventKey and not event.pressed:
		var ke2: InputEventKey = event as InputEventKey
		if MOVE_KEYS.has(ke2.keycode): _held.erase(ke2.keycode)
		if ke2.keycode == KEY_SHIFT: _push_stance(_selected_stance)

# Pointer input lives in _unhandled_input, not _input, so any Control that consumed the
# click -- a pinned bag window, the settings sheet, the work grid -- has already eaten it
# and a click on UI never doubles as a trigger pull. GUI handling runs between the two.
func _unhandled_input(event: InputEvent) -> void:
	# Wheel zoom through the fixed ladder -- power-of-two multiples of the art-native
	# 64 so nearest-neighbour scaling never shimmers. Not while the inventory is open:
	# the wheel belongs to the panel there.
	if event is InputEventMouseButton and event.pressed and not inventory_open:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			CameraUtil.zoom_step(camera, 1)
			queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			CameraUtil.zoom_step(camera, -1)
			queue_redraw()
	# Mouse motion proposes an aim bearing; the sim takes it only while the body is
	# stationary (world.gd's "aim" case), so this is turning on the spot to track the
	# cursor, never steering.
	if event is InputEventMouseMotion and world != null and not inventory_open:
		var bearing: Variant = _aim_at((event as InputEventMouseMotion).position)
		if bearing != null and absf(angle_difference(float(bearing), _last_aim)) > 0.02:
			_last_aim = float(bearing)
			world.commands.push({"type": "aim", "radians": _last_aim})
	if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if world != null and not inventory_open:
			# Aim at the click first, then attack with whatever is actually in hand: the
			# trigger if a ranged weapon is equipped (fire converts itself to a reload on an
			# empty magazine -- ranged.gd owns that), the swing otherwise. G and F remain as
			# the key equivalents; the sim decides everything past the verb.
			var at: Variant = _aim_at((event as InputEventMouseButton).position)
			if at != null:
				_last_aim = float(at)
				world.commands.push({"type": "aim", "radians": _last_aim})
			if world.components.has_component(int(world.player), "rangedWeapon"):
				world.commands.push({"type": "fire"})
			else:
				world.commands.push({"type": "swing"})


# The bearing from the player's body to a screen point, in world space -- what an aim command
# carries. Null when there is nothing to aim from.
func _aim_at(screen_pos: Vector2) -> Variant:
	if world == null:
		return null
	var pos: Variant = world.components.get_component(int(world.player), "position")
	if not (pos is Dictionary):
		return null
	var at: Dictionary = CameraUtil.screen_to_world(camera, screen_pos.x, screen_pos.y)
	var dx: float = float(at["x"]) - float((pos as Dictionary)["x"])
	var dy: float = float(at["y"]) - float((pos as Dictionary)["y"])
	if dx == 0.0 and dy == 0.0:
		return null
	return atan2(dy, dx)

func _on_ui_prefs_changed() -> void:
	if _inventory_panel != null and _inventory_panel.has_method("refresh_style"):
		_inventory_panel.call("refresh_style")

func _push_stance(target: int) -> void:
	if world == null: return
	# Reads sim, never writes it -- this file's own header. The stance module (world.gd's
	# "stance" command case and the player.advance-posture system) owns ticks_left and the
	# current/target transition entirely; this used to reach into posture directly and set
	# ticks_left on a dict that (pre-SimStances.make_posture) never had that key at all, an
	# invalid-index crash on every Z/X/C/V press.
	world.commands.push({"type": "stance", "stance": target})

func _pump_input() -> void:
	if world == null: return
	var dx: float = 0.0; var dy: float = 0.0
	for k in _held.keys():
		var d: Dictionary = MOVE_KEYS.get(int(k), {}) as Dictionary
		dx += float(d.get("dx", 0.0)); dy += float(d.get("dy", 0.0))
	if dx != _last_dx or dy != _last_dy:
		world.commands.push({"type": "move", "dx": dx, "dy": dy})
		_last_dx = dx; _last_dy = dy

func _toggle_legend() -> void:
	if _legend != null:
		_legend.visible = not _legend.visible


func _cycle_overlay() -> void:
	var order: Array[String] = ["off", "noise", "scent", "sight", "light"]
	var idx: int = order.find(attention_channel)
	attention_channel = order[(idx + 1) % order.size()]

func _toggle_pause() -> void:
	paused = not paused

func _save() -> void:
	if world == null: return
	var text: String = SimSave.encode_save(SimSave.create_save(world))
	PlatformStorage.write_save(text)

func _load() -> void:
	if world == null: return
	if bool(world.runOver): return
	var raw: String = PlatformStorage.read_save()
	if raw.is_empty(): return
	var parsed: Dictionary = SimSave.decode_save(raw)
	if parsed.has("__error"): return
	var snap: Variant = parsed.get("snapshot", {})
	if snap is Dictionary and bool((snap as Dictionary).get("runOver", false)):
		return
	SimSave.apply_save(world, parsed)

func _poll_content_reload() -> void:
	if not OS.is_debug_build():
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _content_poll_at < 0.5:
		return
	_content_poll_at = now
	# lightweight mtime check via ContentValidator: validate_tree is cheap on small tree
	var issues: Array = ContentValidator.validate_tree("res://content") as Array
	if issues.is_empty():
		if not _content_error.is_empty():
			_content_error = ""
		# reload tree onto world (Dictionary only, no Resources in sim)
		var res: Dictionary = ContentReload.try_reload_world(world)
		if not bool(res.get("ok", true)):
			_content_error = "; ".join(res.get("issues", []) as Array)
	else:
		_content_error = String(issues[0]) if not issues.is_empty() else "content error"
		# invalid edit does not reload — run keeps going, HUD shows file/entry/field

func _process(delta: float) -> void:
	if world == null: return
	_poll_content_reload()
	if paused:
		_update_hud()
		return
	_pump_input()
	# speed scales tick debt: more ticks per frame, not smaller tick
	var ticks_needed: int = int(floor(delta / TICK_SECONDS * float(speed) + accumulator / TICK_SECONDS))
	accumulator += delta * float(speed)
	var ticks_done: int = 0
	var cap: int = maxi(1, 5 * speed)
	while accumulator >= TICK_SECONDS and ticks_done < cap:
		accumulator -= TICK_SECONDS
		var next_tick: int = int(world.tick) + 1
		for cmd_v in commands_by_tick.get(next_tick, []):
			world.commands.push(cmd_v as Dictionary)
		world.step()
		tick_count += 1
		ticks_done += 1
		_resize_camera()
		if _sfx != null:
			_sfx.tick(world, camera, world.events.drained)
		if speed >= 10:
			speed = SimFortify.speed_after_events(speed, world.events.drained)
			if speed < 10:
				accumulator = 0.0
				break
	if ticks_done > 0:
		_update_condition_view()
		_update_hud()
	queue_redraw()

func _update_condition_view() -> void:
	if world == null: return
	# The view is built by sim/condition.gd, which is what check_ban_health_bar.gd gates.
	var cv: Dictionary = SimCondition.view(world, world.player)
	if cv.is_empty(): return
	var parts: Array = cv["parts"] as Array
	var worst: int = int(cv["worst"])
	# Infection diagnosis (read model only, never exposes transmitted — consumes examiner skill via CON stub 0)
	var diag: Variant = SimInfection.diagnosis_of(world, world.player, 0)
	if diag is Dictionary and String((diag as Dictionary).get("label", "clear")) != "clear":
		parts.append({"part": "infection", "state": int((diag as Dictionary).get("stage", 0)), "prose": String((diag as Dictionary).get("label", ""))})
	var stance: int = int(cv["stance"])
	_glimpse_parts = parts; _glimpse_worst = worst; _glimpse_stance = stance
	if _paperdoll != null and _paperdoll.has_method("set_view"):
		_paperdoll.call("set_view", {"parts": parts, "stance": stance, "worst": worst})

func _update_hud() -> void:
	if _hud == null or world == null: return
	var pos: Variant = world.components.get_component(world.player, "position")
	var x: float = 0.0; var y: float = 0.0
	if pos is Dictionary: x = float((pos as Dictionary)["x"]); y = float((pos as Dictionary)["y"])
	var tod: float = Clock.time_of_day(int(world.tick))
	var phase: String = Clock.PHASE_NAMES[Clock.phase_at(tod)]
	var light: float = Clock.ambient_light(tod)
	var now: float = Time.get_ticks_msec() / 1000.0
	# Only while the sheet is actually up. `world.serialize()` is the whole save path --
	# canonical JSON over every component, the entity store, the modifier table and the
	# attention field -- and it was measured at **12.58 ms** on a two-hour-old seed-404 world
	# with 46 entities. At four times a second that is 50 ms of every wall-clock second, or one
	# blown 16.7 ms frame four times a second, spent hashing the world for a field nobody is
	# looking at: `show_sheets` defaults to false and M is what reveals it. It also grows with
	# the colony, so the cost was worst exactly when frames were tightest. docs/00 pillar 6:
	# budgets are correctness. Pressing M recomputes within a quarter-second, which is the
	# same latency the field always had.
	if show_sheets and now - _fingerprint_at > 0.25:
		# A hash, not a prefix. serialize() returns canonical JSON, so its first 8 characters
		# are always the literal `{"compon` -- the field could never change and so could
		# never show the divergence it exists to show.
		_fingerprint = "%08x" % (world.serialize().hash() & 0xffffffff)
		_fingerprint_at = now
	elif not show_sheets:
		# Cleared rather than left stale: a fingerprint from before the sheet was hidden would
		# read as live and would be the one thing on the sheet that is quietly a lie.
		_fingerprint = "--------"
		_fingerprint_at = -1e9
	var diag2: Dictionary = SimInfection.diagnosis_of(world, world.player, 0) as Dictionary
	var diag_label: String = String(diag2.get("label", "clear"))
	var apt: Dictionary = SimAptitudes.of(world, world.player)
	var companion: String = ""
	for ent in world.components.query(["identity", "position"]):
		var ident: Variant = world.components.get_component(int(ent), "identity")
		if ident is Dictionary:
			companion = String((ident as Dictionary).get("name", ""))
			break
	# `count` reads the table's size; `query` allocated an Array and sorted it so the loop could
	# throw every id away. Measured 0.0007 ms against 0.0068 ms -- small, but it was ten times
	# the price for strictly less information.
	var zeds: int = int(world.components.count("shambler"))
	var base: String = "tick %d  pos %.1f,%.1f  %s %.2f  light %.2f  %s  %dx %s  STR %d CON %d DEX %d  %s  zed %d  F swing G fire  fp %s  dx:%s  seed %d  district %s" % [int(world.tick), x, y, phase, tod, light, attention_channel, speed, ("PAUSED" if paused else ""), int(apt["str"]), int(apt["con"]), int(apt["dex"]), companion, zeds, _fingerprint, diag_label, int(world.seed), _district_id]
	# One look-at, read twice. It used to be computed once for the dev sheet and again, with
	# identical arguments on the same tick, for the player's context line a few lines below.
	var look: Dictionary = {}
	if world.tilemap != null:
		look = SimFortify.look_at(world, world.player)
		if not String(look.get("window", "")).is_empty():
			base += "  %s" % String(look["window"])
		if not String(look.get("noisemaker", "")).is_empty():
			base += "  %s" % String(look["noisemaker"])
	if not _content_error.is_empty():
		base += "  content: %s" % _content_error
	var who: int = _selected if _selected >= 0 else int(world.player)
	if bool(world.runOver):
		base += "  RUN OVER"
	# `base` is the developer sheet: ticks, raw positions, aptitude integers, the
	# serialisation fingerprint. It is genuinely useful and it is not a HUD, so it goes to
	# the HUD's raw layer, which only M reveals. Everything the player reads is prose the
	# HUD assembles from sim read models.
	if _hud != null:
		# Fortify look-at is contextual and belongs on the player's line, not the dev sheet.
		var context: String = ""
		for k in ["window", "noisemaker"]:
			if not String(look.get(k, "")).is_empty():
				context = String(look[k])
				break
		if not _content_error.is_empty():
			context = "content: %s" % _content_error
		_hud.set("hint", context)
		_hud.call("refresh", world, who, base)
	if _work_panel != null and _work_panel.visible and _work_panel.has_method("set_world"):
		_work_panel.call("set_world", world)
	# Always refreshed, not only while open: pinned bag windows read the same view during
	# ordinary play, and a stale pinned bag is a lie about what you are carrying.
	if _inventory_panel != null and _inventory_panel.has_method("set_world"):
		_inventory_panel.call("set_world", world, world.player)

func _draw() -> void:
	if world == null: return
	# background
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Palette.COLOURS["background"])
	_draw_district()
	_draw_entities()
	_draw_night_wash()
	# glimpse drawn by Control; nothing else needed here

func _draw_district() -> void:
	var zoom: float = float(camera["zoom"])
	var half: float = zoom / 2.0
	var seen: Variant = null
	if world.vision != null:
		seen = world.vision.tiles_for(int(world.player))
	var bounds: Dictionary = TopDownProjection.visible_bounds(camera, 2.0)
	var min_x: int = maxi(0, floori(float(bounds["minX"])))
	var max_x: int = mini(int(world.map_width) - 1, ceili(float(bounds["maxX"])))
	var min_y: int = maxi(0, floori(float(bounds["minY"])))
	var max_y: int = mini(int(world.map_height) - 1, ceili(float(bounds["maxY"])))
	# Row-major, no sort: flat tiles never overlap. Bodies overlap tiles and each
	# other; they sort in _draw_entities.
	for ty in range(min_y, max_y + 1):
		for tx in range(min_x, max_x + 1):
			# Walls block sight: only draw tiles the player has a sightline to (windows stay Clear).
			if seen != null and not (seen as Object).call("has_tile", tx, ty):
				continue
			var sc: Dictionary = TopDownProjection.world_to_screen(camera, float(tx) + 0.5, float(ty) + 0.5)
			var rect := Rect2(roundf(float(sc["sx"]) - half), roundf(float(sc["sy"]) - half), zoom, zoom)
			var tile: int = SimTileMap.Tile.Floor
			# The ground, resolved before the tile: docs/24's surface layer is a second array
			# over the same grid, so every tile that shows floor shows the ground it stands on
			# rather than one shared slab colour. Paved resolves to the old floor colour, which
			# is why a street looks exactly as it did (check_topdown.gd pins that identity).
			var ground: Color = Appearance.ground_colour(world.tilemap, tx, ty)
			var col: Color = ground
			if world.tilemap != null:
				tile = int(SimTileMap.tile_at(world.tilemap, tx, ty))
				match tile:
					SimTileMap.Tile.Wall:
						col = Palette.COLOURS["wall"]
					SimTileMap.Tile.Window:
						col = Palette.COLOURS["window"]
					SimTileMap.Tile.Screen:
						col = Palette.COLOURS["screen"]
					SimTileMap.Tile.Low:
						col = Palette.COLOURS["low"]
					SimTileMap.Tile.Tree:
						col = Palette.COLOURS["tree"]
				var ov: Variant = SimTileMap.overlay_at(world.tilemap, tx, ty)
				if ov is Dictionary:
					var kind: String = String((ov as Dictionary).get("kind", ""))
					if kind == "board":
						col = Palette.COLOURS["wall"] if int((ov as Dictionary).get("stage", 0)) < 3 else Palette.COLOURS["window"].lightened(0.15)
						# Boarded window reads as wall so you cannot peek through.
						if int((ov as Dictionary).get("stage", 0)) < 3:
							tile = SimTileMap.Tile.Wall
					elif kind == "scrap":
						col = Palette.COLOURS["rubble"]
						tile = SimTileMap.Tile.Wall
			elif world.is_blocked_tile(tx, ty):
				col = Palette.COLOURS["wall"]
				tile = SimTileMap.Tile.Wall
			match tile:
				SimTileMap.Tile.Wall, SimTileMap.Tile.Screen:
					_draw_solid_tile(rect, col, tx, ty)
				SimTileMap.Tile.Window:
					# A window is a hole in masonry, so the tile is masonry and the glass is the
					# pane: the tile colour that used to fill it edge to edge is handed to the
					# pane instead, which is where the state a boarded-up window reaches stage 3
					# in still shows.
					_draw_solid_tile(rect, Palette.COLOURS["wall"], tx, ty)
					_draw_window_glass(rect, tx, ty, col)
				SimTileMap.Tile.Low:
					_draw_floor_tile(rect, Appearance.indoor_floor(world.tilemap, tx, ty, ground))
					# Inset block with floor showing around it reads as waist-high.
					var inset: float = zoom * 0.15625
					draw_rect(Rect2(rect.position + Vector2(inset, inset), rect.size - Vector2(inset * 2.0, inset * 2.0)), col)
				SimTileMap.Tile.Tree:
					_draw_floor_tile(rect, Appearance.indoor_floor(world.tilemap, tx, ty, ground))
					var centre: Vector2 = rect.get_center()
					draw_circle(centre, zoom * 0.42, col)
					draw_circle(centre, zoom * 0.0625, col.darkened(0.45))
				_:
					# A floor knows whether it is inside a building and whether it is the tile you
					# step through to get there. Both are read from the map -- `indoors` is an
					# array the generator writes, and the doorway is a record in map.buildings --
					# so a shell reads as a room and a doorway reads as a way in without any tile
					# type existing for either.
					var floor_col: Color = Appearance.indoor_floor(world.tilemap, tx, ty, col)
					if _is_threshold(tx, ty):
						_draw_threshold(rect, floor_col, tx, ty)
					else:
						_draw_floor_tile(rect, floor_col)
	# Props last, over the ground and under the bodies _draw_entities sorts: a container, a bed,
	# a campfire and the well all stood invisible in this district until this call existed.
	_draw_props()

# Floors are flat fill plus a hairline grid line.
func _draw_floor_tile(rect: Rect2, col: Color) -> void:
	draw_rect(rect, col)
	draw_rect(rect, Palette.COLOURS["background"] * 0.9, false, 1.0)

# Solid tiles (walls, screens, boards, scrap): the whole tile is filled, because the whole tile
# is what the sim blocks, but it is filled with the cap -- the top of the wall seen from above --
# and only the edges that meet something walkable get the lit face. A run of wall is then one
# dark band with a bright edge instead of a row of bright blocks each the size of a room, which
# is the proportion complaint; the tile that is blocked is still the tile that is drawn, so
# nothing here offers a way through that the sim refuses.
#
# Which edges are exposed is read off the neighbours rather than off a stored orientation, the
# same way _draw_window_glass reads its pane, so a wall boarded up or torn open this tick is
# shaded against what stands now.
func _draw_solid_tile(rect: Rect2, col: Color, tx: int, ty: int) -> void:
	draw_rect(rect, col.darkened(Palette.WALL_CAP_DARKEN))
	var b: float = maxf(2.0, rect.size.x * Palette.WALL_FACE_SHARE)
	# Light from the top-left, as the old bevel had it: the north and west faces catch it, the
	# south and east ones are the same mass in shade. Both are lighter than the cap and than any
	# ground -- an edge against floor is always drawn as a line, never as an absence of one.
	var light: Color = col.lightened(Palette.WALL_FACE_LIT)
	var dim: Color = col.lightened(Palette.WALL_FACE_DIM)
	if not _is_solid_at(tx, ty - 1):
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, b)), light)
	if not _is_solid_at(tx - 1, ty):
		draw_rect(Rect2(rect.position, Vector2(b, rect.size.y)), light)
	if not _is_solid_at(tx, ty + 1):
		draw_rect(Rect2(rect.position + Vector2(0.0, rect.size.y - b), Vector2(rect.size.x, b)), dim)
	if not _is_solid_at(tx + 1, ty):
		draw_rect(Rect2(rect.position + Vector2(rect.size.x - b, 0.0), Vector2(b, rect.size.y)), dim)

# Windows: a bright glass pane + rim so they read against masonry. Orientation
# follows the neighbouring walls; a corner window falls back to a square pane.
func _draw_window_glass(rect: Rect2, tx: int, ty: int, col: Color = Palette.COLOURS["window"]) -> void:
	var glass: Color = col.lightened(0.28)
	var horizontal_walls: bool = _is_solid_at(tx - 1, ty) and _is_solid_at(tx + 1, ty)
	var vertical_walls: bool = _is_solid_at(tx, ty - 1) and _is_solid_at(tx, ty + 1)
	var c: Vector2 = rect.get_center()
	var pane_long: float = rect.size.x * 0.75
	var pane_short: float = rect.size.x * 0.25
	var pane: Rect2
	if horizontal_walls and not vertical_walls:
		pane = Rect2(c - Vector2(pane_long / 2.0, pane_short / 2.0), Vector2(pane_long, pane_short))
	elif vertical_walls and not horizontal_walls:
		pane = Rect2(c - Vector2(pane_short / 2.0, pane_long / 2.0), Vector2(pane_short, pane_long))
	else:
		pane = Rect2(c - Vector2(pane_short * 0.75, pane_short * 0.75), Vector2(pane_short * 1.5, pane_short * 1.5))
	draw_rect(pane, glass)
	draw_rect(pane, Color("#b8eaff"), false, 2.0)

# Doorways, cached against the map object rather than recomputed per frame: the derivation itself
# is Appearance.door_tiles, which is pure, and the cache lives here because a static one would be
# shared between the two worlds a gate boots. A reboot or a load hands over a different map object,
# which is what invalidates it.
func _threshold_tiles() -> Dictionary:
	var map: Variant = world.tilemap
	if map == _thresholds_from:
		return _thresholds
	_thresholds_from = map
	_thresholds = Appearance.door_tiles(map)
	return _thresholds


func _is_threshold(tx: int, ty: int) -> bool:
	if world.tilemap == null:
		return false
	return _threshold_tiles().has(ty * int(world.tilemap.w) + tx)


# The doorway: worn boards between whichever jambs are actually there. The jambs are read off the
# neighbouring tiles rather than off a stored orientation, the same way _draw_window_glass reads
# its pane orientation, so a door in a rebuilt or barricaded wall is drawn against what stands now.
func _draw_threshold(rect: Rect2, col: Color, tx: int, ty: int) -> void:
	_draw_floor_tile(rect, col.lerp(Palette.COLOURS["threshold"], 0.75))
	# The jamb is the cap of the wall it belongs to, so a doorway is a gap in one mass rather than
	# two stubs in a colour of their own -- the lit faces of the wall tiles either side already
	# draw the line where the opening starts.
	var jamb: Color = (Palette.COLOURS["wall"] as Color).darkened(Palette.WALL_CAP_DARKEN)
	var t: float = maxf(2.0, rect.size.x * 0.14)
	if _is_solid_at(tx - 1, ty):
		draw_rect(Rect2(rect.position, Vector2(t, rect.size.y)), jamb)
	if _is_solid_at(tx + 1, ty):
		draw_rect(Rect2(rect.position + Vector2(rect.size.x - t, 0.0), Vector2(t, rect.size.y)), jamb)
	if _is_solid_at(tx, ty - 1):
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, t)), jamb)
	if _is_solid_at(tx, ty + 1):
		draw_rect(Rect2(rect.position + Vector2(0.0, rect.size.y - t), Vector2(rect.size.x, t)), jamb)


# Everything standing in the district that is neither a body nor a carried item. What each one
# looks like comes from content through Appearance.prop_look; this loop owns only where it is,
# whether you can see it, and which primitive draws it.
func _draw_props() -> void:
	if world == null or world.components == null:
		return
	var zoom: float = float(camera["zoom"])
	var bounds: Dictionary = TopDownProjection.visible_bounds(camera, 2.0)
	var seen: Variant = null
	if world.vision != null:
		seen = world.vision.tiles_for(int(world.player))
	# One query per prop component rather than one pass over every position: query picks the
	# smallest store, so this walks the 137 containers rather than the whole district.
	var drawn: Dictionary = {}
	for kind in Appearance.PROP_KINDS:
		for ent in world.components.query([String(kind["component"]), "position"]):
			var e: int = int(ent)
			if drawn.has(e):
				continue
			# components.query does not check alive (CLAUDE.md); a despawned prop keeps its
			# components and would otherwise keep standing here.
			if world.entities != null and not world.entities.is_alive(e):
				continue
			var p: Variant = world.components.get_component(e, "position")
			if not (p is Dictionary):
				continue
			var x: float = float((p as Dictionary)["x"])
			var y: float = float((p as Dictionary)["y"])
			if x < float(bounds["minX"]) or x > float(bounds["maxX"]) or y < float(bounds["minY"]) or y > float(bounds["maxY"]):
				continue
			# The same sightline the tiles use. A cupboard on the far side of a wall is not
			# visible through it -- information stays scarce, and the tile it stands on is not
			# drawn either, so drawing the prop would be a thing floating on the background.
			if seen != null and not (seen as Object).call("has_tile", floori(x), floori(y)):
				continue
			var look: Dictionary = Appearance.prop_look(world, e)
			if look.is_empty():
				continue
			drawn[e] = true
			_draw_prop(look, x, y, zoom)


# The four ground-footprint primitives. Geometry only: which one, how big and in what colour all
# arrived from content, and Appearance.PROP_SHAPES is the list check_topdown.gd matches against
# this function so a shape content can name is a shape something draws.
func _draw_prop(look: Dictionary, x: float, y: float, zoom: float) -> void:
	var sc: Dictionary = TopDownProjection.world_to_screen(camera, x, y)
	var centre := Vector2(float(sc["sx"]), float(sc["sy"]))
	var tint: Color = look["tint"] as Color
	var texture: Variant = look.get("texture")
	if texture != null:
		# Art, when a prop has any: one tile, centre-anchored, same canvas as a pawn.
		var h: float = zoom / 2.0
		draw_texture_rect(texture as Texture2D, Rect2(centre - Vector2(h, h), Vector2(zoom, zoom)), false, tint)
		return
	var span: float = float(look["size"]) * zoom
	var edge: Color = tint.darkened(0.55)
	match String(look["shape"]):
		"slab":
			var w: float = span * 0.66
			var slab := Rect2(centre - Vector2(w / 2.0, span / 2.0), Vector2(w, span))
			draw_rect(slab, tint)
			draw_rect(Rect2(slab.position, Vector2(w, span * 0.24)), tint.lightened(0.32))
			draw_rect(slab, edge, false, 1.0)
		"disc":
			draw_circle(centre, span / 2.0, tint)
			draw_circle(centre, span * 0.18, tint.darkened(0.45))
		"ring":
			draw_circle(centre, span / 2.0, tint)
			draw_circle(centre, span * 0.28, Palette.COLOURS["background"])
			draw_arc(centre, span / 2.0, 0.0, TAU, 24, edge, 1.0)
		"box", _:
			# A bevelled square -- and the floor for anything a future content entry names that
			# this match has not learned, because an unknown shape must still draw something.
			var box := Rect2(centre - Vector2(span / 2.0, span / 2.0), Vector2(span, span))
			_draw_bevelled_box(box, tint)
			draw_rect(box, edge, false, 1.0)


# A free-standing object lit from the top-left: light along the top and left, dark along the
# bottom and right, all four edges every time. This is the bevel walls used to wear. A crate is
# an object with four visible sides and no neighbours to be continuous with, so it keeps it; a
# wall is a run, and _draw_solid_tile shades it as one.
func _draw_bevelled_box(box: Rect2, col: Color) -> void:
	draw_rect(box, col)
	var b: float = 2.0
	var light: Color = col.lightened(0.18)
	var dark: Color = col.darkened(0.22)
	draw_rect(Rect2(box.position, Vector2(box.size.x, b)), light)
	draw_rect(Rect2(box.position, Vector2(b, box.size.y)), light)
	draw_rect(Rect2(box.position + Vector2(0.0, box.size.y - b), Vector2(box.size.x, b)), dark)
	draw_rect(Rect2(box.position + Vector2(box.size.x - b, 0.0), Vector2(b, box.size.y)), dark)


func _is_solid_at(tx: int, ty: int) -> bool:
	if world.tilemap == null:
		return false
	var t: int = int(SimTileMap.tile_at(world.tilemap, tx, ty))
	return t == SimTileMap.Tile.Wall or t == SimTileMap.Tile.Screen

func _draw_entities() -> void:
	if world == null: return
	var items: Array[Dictionary] = []
	# collect all positions
	for ent in world.components.query(["position"]):
		var p: Variant = world.components.get_component(int(ent), "position")
		if not p is Dictionary: continue
		var x: float = float((p as Dictionary)["x"]); var y: float = float((p as Dictionary)["y"])
		var is_player: bool = int(ent) == int(world.player)
		var is_unique: bool = world.components.has_component(int(ent), "identity")
		var is_zed: bool = world.components.has_component(int(ent), "shambler")
		var is_bait: bool = world.components.has_component(int(ent), "noisemaker")
		var is_raider: bool = world.components.has_component(int(ent), "raider")
		if world.components.has_component(int(ent), "itemBase"):
			continue
		if not is_player and not is_unique and not is_zed and not is_bait and not is_raider:
			continue
		# Walls / boards block; windows stay Clear — match sim vision, not camera frustum.
		var det: int = SimVisibility.Detail.Focal
		if not is_player and world.vision != null:
			det = int(world.vision.detail(int(world.player), x, y))
			if det == SimVisibility.Detail.Unseen:
				continue
			if det == SimVisibility.Detail.Peripheral:
				var vel: Variant = world.components.get_component(int(ent), "velocity")
				if vel is Dictionary and float((vel as Dictionary).get("dx", 0.0)) == 0.0 and float((vel as Dictionary).get("dy", 0.0)) == 0.0:
					continue
		var sc: Dictionary = TopDownProjection.world_to_screen(camera, x, y)
		var depth: float = TopDownProjection.depth_of(x, y)
		var ztype: String = ""
		if is_zed:
			var zt: Variant = world.components.get_component(int(ent), "zombieType")
			if zt is Dictionary:
				ztype = String((zt as Dictionary).get("id", ""))
		# Content id for a unique survivor, so appearance resolves for people as well as for
		# zombies. A generated colonist has no content entry under its own `identity.id`, but
		# does carry a rolled `identity.look` pointing at one of `colony/looks.json`'s tint-only
		# entries -- a data pass-through, not a branch, same as the raider archetype id below.
		var cid: String = ""
		if is_unique:
			var ident: Variant = world.components.get_component(int(ent), "identity")
			if ident is Dictionary:
				cid = String((ident as Dictionary).get("look", ""))
				if cid.is_empty():
					cid = String((ident as Dictionary).get("id", ""))
		elif is_raider:
			# The archetype id, exactly as a zombie hands over its type id: how a raider looks is
			# a property of its content entry, never an `if id == ...` in this loop.
			var rd: Variant = world.components.get_component(int(ent), "raider")
			if rd is Dictionary:
				cid = String((rd as Dictionary).get("id", ""))
		items.append({"x": x, "y": y, "sx": float(sc["sx"]), "sy": float(sc["sy"]), "d": depth, "det": det, "player": is_player, "unique": is_unique, "zed": is_zed, "bait": is_bait, "raider": is_raider, "ztype": ztype, "cid": cid, "id": int(ent)})
	items.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))
	for it in items:
		var sx: float = float(it["sx"]); var sy: float = float(it["sy"])
		# Colours and sprites come from content now, not from a chain of type-id checks here.
		var look: Dictionary = Appearance.for_entity(world, it)
		var col: Color = look["tint"] as Color
		var r: float = float(look["radius"])
		# A peripheral glimpse is one anonymous shape: no sprite, no gear, no facing
		# (docs/30 -- posture and facing are information the glimpse did not earn).
		if int(it["det"]) == SimVisibility.Detail.Peripheral:
			draw_circle(Vector2(sx, sy), r, Color(0.32, 0.38, 0.32, 0.75))
			continue
		# contact shadow — under both branches, so a sprite still sits on the ground.
		draw_circle(Vector2(sx, sy + 3), r * 0.9, Color(0, 0, 0, 0.35))
		var texture: Texture2D = look["texture"] as Texture2D
		if texture != null:
			# Centre-anchored: the pawn's visual mass sits on the entity's ground position
			# (64x64 canvas, assets/sprites/README.md). Rounded so a 1:1 pixel sprite never
			# lands on a half-pixel as the camera follows the player.
			var size: Vector2 = texture.get_size()
			var at := Vector2(roundf(sx - size.x / 2.0), roundf(sy - size.y / 2.0))
			var rect := Rect2(at, size)
			# Equipped gear composites at the identical rect the body draws at -- an
			# equipSprite is authored on the same feet-anchored canvas, so there is no
			# per-item offset to compute here. Drawn white, never the role/tint colour:
			# a backpack is its own object, not a stand-in shape for the entity itself.
			var equip: Array[Dictionary] = Appearance.equipment_layers_for(world, int(it["id"]))
			for layer in equip:
				if not bool(layer["over"]):
					draw_texture_rect(layer["texture"] as Texture2D, rect, false)
			draw_texture_rect(texture, rect, false, col)
			for layer in equip:
				if bool(layer["over"]):
					draw_texture_rect(layer["texture"] as Texture2D, rect, false)
		else:
			draw_circle(Vector2(sx, sy), r, col)
			draw_circle(Vector2(sx, sy), r, col.lightened(0.25), false, 2.4 if bool(it["player"]) else 1.6)
		# Facing + aim sway (cone half-angle). No hit % — wobble is the readout.
		var eid: int = int(it["id"])
		var facing_v: Variant = world.components.get_component(eid, "facing")
		var face: float = 0.0
		if facing_v is Dictionary:
			face = float((facing_v as Dictionary).get("radians", 0.0))
		# Screen axes are world axes under the top-down projection: no rotation.
		var screen_ang: float = face
		draw_line(
			Vector2(sx, sy),
			Vector2(sx + cos(screen_ang) * (r + 12.0), sy + sin(screen_ang) * (r + 12.0)),
			Color(1, 1, 1, 0.55),
			2.4 if bool(it["player"]) else 1.6,
		)
		if bool(it["player"]) and world.components.has_component(eid, "rangedWeapon"):
			var rw: Variant = world.components.get_component(eid, "rangedWeapon")
			if rw is Dictionary and int((rw as Dictionary).get("state", 0)) in [1, 2]:
				var half: float = float((rw as Dictionary).get("coneHalf", 0.55))
				var reach_px: float = r + 36.0 + half * 44.0
				var a0: float = screen_ang - half
				var a1: float = screen_ang + half
				draw_arc(Vector2(sx, sy), reach_px, a0, a1, 12, Color(0.85, 0.9, 1.0, 0.35), 2.8)
				draw_line(Vector2(sx, sy), Vector2(sx + cos(a0) * reach_px, sy + sin(a0) * reach_px), Color(0.85, 0.9, 1.0, 0.25), 2.0)
				draw_line(Vector2(sx, sy), Vector2(sx + cos(a1) * reach_px, sy + sin(a1) * reach_px), Color(0.85, 0.9, 1.0, 0.25), 2.0)
	# ground items as small squares — focal only (searching a room is an action)
	for ent in world.components.query(["position", "itemBase"]):
		if world.components.has_component(int(ent), "stored"): continue
		var p: Variant = world.components.get_component(int(ent), "position")
		if not p is Dictionary: continue
		var ix: float = float((p as Dictionary)["x"]); var iy: float = float((p as Dictionary)["y"])
		if world.vision != null and int(world.vision.detail(int(world.player), ix, iy)) != SimVisibility.Detail.Focal:
			continue
		var sc: Dictionary = TopDownProjection.world_to_screen(camera, ix, iy)
		var item_rect := Rect2(float(sc["sx"]) - 5.0, float(sc["sy"]) - 5.0, 10.0, 10.0)
		draw_rect(item_rect, Palette.COLOURS["groundItem"])
		draw_rect(item_rect, Palette.COLOURS["groundItemEdge"], false, 1.5)
	# last-known marks fading. The positions are the *simulation's* memory, not a second copy
	# kept by the renderer: a mark on the ground and a colonist's decision to shoot at one have
	# to be the same recollection, or the mark is telling the player something nobody in the
	# world knows. MEMORY_TICKS stays a presentation constant because how long a mark is drawn
	# is a drawing question -- the sim remembers for far longer than this fades.
	for row in SimSightings.remembered(world, int(world.player)):
		var m: Dictionary = row as Dictionary
		var age: int = int(m["age"])
		if age <= 0 or age > MEMORY_TICKS: continue
		var sc: Dictionary = TopDownProjection.world_to_screen(camera, float(m["x"]), float(m["y"]))
		var a: float = 0.5 * (1.0 - float(age) / float(MEMORY_TICKS))
		draw_circle(Vector2(float(sc["sx"]), float(sc["sy"])), 8.0, Color(0.24, 0.29, 0.24, a))

func _draw_night_wash() -> void:
	var tod: float = Clock.time_of_day(int(world.tick))
	var light: float = Clock.ambient_light(tod)
	if light >= 1.0: return
	var a: float = (1.0 - light) * NIGHT_WASH
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.023, 0.039, 0.102, a))
