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
const LightLook = preload("res://presentation/light_look.gd")
const RoadPaint = preload("res://presentation/road_paint.gd")
const RoofLook = preload("res://presentation/roof_look.gd")
const RainLook = preload("res://presentation/rain_look.gd")
const Dressing = preload("res://presentation/dressing.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimSurface = preload("res://sim/map/surface.gd")
const Clock = preload("res://sim/time/clock.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimCondition = preload("res://sim/condition.gd")
const SimVehicles = preload("res://sim/modules/vehicles.gd")
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
# The true, unshaken follow centre -- what follow_smoothed advances every frame. `camera`
# itself is the *displayed* camera (centre + shake, combined in _update_camera, the one
# place world_to_screen/screen_to_world ever see), so shake must live somewhere else or it
# would feed back into next frame's follow and the view would slowly drift off in whatever
# direction the last few kicks happened to land.
var _camera_centre: Dictionary = {"x": 0.0, "y": 0.0}
# Decaying screen-shake offset, in pixels -- see camera.gd's shake_impulse/shake_decay.
var _shake: Dictionary = {"x": 0.0, "y": 0.0}
# Direction for shake kicks only. Presentation-side and never seeded from the sim: shake is
# feel, not simulation, and a sim stream here would put the camera's wobble on the seeded
# sequence and make a replay's *view* depend on how hard something got hit.
var _shake_rng: RandomNumberGenerator = RandomNumberGenerator.new()
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
var _dashboard: Control = null
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
# The road-paint mask, {byte per tile}, and the map object it was resolved from. Same shape and
# same reason as _thresholds above: RoadPaint.mask_for is pure, and the cache lives on this node
# because a static one would be shared between the two worlds a gate boots. Rebuilt when the map
# changes identity (a reboot, a load) and never per frame -- see _road_mask.
var _road_mask_cache: PackedByteArray = PackedByteArray()
var _road_mask_from: Variant = null
# tile -> building, and building -> look, both cached against the map object (RoofLook builds
# them; a static cache would be shared between the two worlds a gate boots).
var _roof_index_cache: PackedInt32Array = PackedInt32Array()
var _roof_index_from: Variant = null
var _looks: Dictionary = {}
# One byte per tile, the ground row every floor draws (Appearance.ROW_NONE where there is no
# ground), cached against the map object: the edge rule reads nine of these per tile, and nine
# ground_row_for calls per tile per frame is what this replaces.
var _ground_rows_cache: PackedByteArray = PackedByteArray()
var _ground_rows_from: Variant = null
# tile -> parked-vehicle manifest index (Dressing.VEHICLE_NONE where none), cached against the
# map object for the same reason as the three above. This is what makes the Low branch's two
# cases exclusive without walking `map.vehicles` per tile.
var _vehicle_index_cache: PackedInt32Array = PackedInt32Array()
var _vehicle_index_from: Variant = null
var _vehicle_index_gen: int = -1
# The map-dressing block (heap and debris sprite keys), and the content tree it came from. Third
# instance of the same pattern for the third time it is the right one: the lookup is a scan over
# content and this is asked once per drawn tile, the resolution is pure, and a static cache would
# be shared between the two worlds a gate boots. A content hot-reload swaps the tree, which is
# what invalidates it -- see _dressing.
var _dressing_cache: Dictionary = {}
var _dressing_from: Variant = null
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
# The interact key. E, by the owner's 2026-09-05 decision: doors, hoods, loot and everything
# else on the context ladder hang off this one key, and the legend names it once.
const INTERACT_KEY: Key = KEY_E
# A rider drawn on an open vehicle: how far above the machine's ground point the pawn's soles
# stand (a saddle is about that high off the road), and how far in front of the picture it
# sorts. Both are readouts of the interface, not lengths the sim knows.
const RIDER_LIFT_M: float = 0.35
const RIDER_DEPTH_EPS: float = 0.01
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
	_shake_rng.randomize()
	_resize_camera()
	_snap_camera()
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
	# models over the *previous* world), and the tick tally. The camera itself recentres
	# below, unsmoothed -- _snap_camera, not the per-frame follow, so a reboot is never
	# watched swooping in from wherever the old world's camera happened to be.
	_selected = -1
	_glimpse_parts = []
	_glimpse_stance = 2
	_glimpse_worst = 0
	_fingerprint = ""
	_fingerprint_at = -1e9
	_content_error = ""
	tick_count = 0
	_resize_camera()
	_snap_camera()

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

# Jumps the follow centre straight to the clamped player position and clears any shake in
# flight -- boot, F2 and F9 all call this instead of letting the per-frame follow arrive on
# its own, so a fresh or loaded world is never watched swooping in from an unrelated camera
# position (or shaking from a hit that happened in a different run entirely).
func _snap_camera() -> void:
	if world == null: return
	var pos: Variant = world.components.get_component(world.player, "position")
	if not (pos is Dictionary): return
	CameraUtil.snap(camera, float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]), int(world.map_width), int(world.map_height))
	_camera_centre["x"] = float(camera["x"])
	_camera_centre["y"] = float(camera["y"])
	_shake["x"] = 0.0
	_shake["y"] = 0.0

# The per-frame camera update: runs every rendered frame (wall-clock delta), not every sim
# tick, so the follow lerp and the shake decay both advance smoothly whether the tick loop
# below this frame ran zero ticks, one, or the fast-forward cap. `camera` -- the Dictionary
# every draw call and _aim_at reads -- becomes the *displayed* camera here: smoothed centre
# plus the shake offset, combined in this one place, so world_to_screen and screen_to_world
# always agree (aim never drifts against what the shake is doing to the view). `_camera_centre`
# stays unshaken so shake never feeds back into next frame's follow target.
func _update_camera(delta: float) -> void:
	_resize_camera()
	if world != null:
		var pos: Variant = world.components.get_component(world.player, "position")
		if pos is Dictionary:
			var target: Dictionary = CameraUtil.follow_target(float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]), int(world.map_width), int(world.map_height))
			CameraUtil.follow_smoothed(_camera_centre, float(target["x"]), float(target["y"]), CameraUtil.FOLLOW_RATE, delta)
	CameraUtil.shake_decay(_shake, CameraUtil.SHAKE_DECAY_RATE, delta)
	var zoom: float = maxf(1.0, float(camera["zoom"]))
	camera["x"] = float(_camera_centre["x"]) + float(_shake["x"]) / zoom
	camera["y"] = float(_camera_centre["y"]) + float(_shake["y"]) / zoom

# Screen shake, fed from the same drained-events read sfx.gd uses -- never a subscription to
# the sim bus. `attack.connected` kicks the view when the target is any survivor (`controlled`:
# the player or a colonist, never a raider or a zombie taking the hit), distance-attenuated off
# the player's own position so a colonist getting hit across the district is felt faintly rather
# than not at all. `grab.started` and `bite.landed` neither carry a useful distance for a body
# that is not the player (a hand closing or a bite lands with no "how hard" to attenuate), so
# both are scoped to the player alone. Direction is randomised through _shake_rng.
func _camera_shake_from_events(drained: Array) -> void:
	if world == null: return
	var player_pos: Variant = world.components.get_component(world.player, "position")
	if not (player_pos is Dictionary): return
	var px: float = float((player_pos as Dictionary)["x"])
	var py: float = float((player_pos as Dictionary)["y"])
	for e in drained:
		if not (e is Dictionary): continue
		var ev: Dictionary = e as Dictionary
		var base_px: float = 0.0
		var at_x: float = px
		var at_y: float = py
		match String(ev.get("type", "")):
			"attack.connected":
				var target: int = int(ev.get("target", -1))
				if not world.components.has_component(target, "controlled"):
					continue
				var tp: Variant = world.components.get_component(target, "position")
				if tp is Dictionary:
					at_x = float((tp as Dictionary)["x"])
					at_y = float((tp as Dictionary)["y"])
				base_px = CameraUtil.SHAKE_HIT_PX
			"grab.started":
				if int(ev.get("victim", -1)) != int(world.player): continue
				base_px = CameraUtil.SHAKE_GRAB_PX
			"bite.landed":
				if int(ev.get("victim", -1)) != int(world.player): continue
				base_px = CameraUtil.SHAKE_BITE_PX
			_:
				continue
		var dist: float = sqrt((at_x - px) * (at_x - px) + (at_y - py) * (at_y - py))
		var mag: float = CameraUtil.shake_attenuate(base_px, dist, CameraUtil.SHAKE_FALL_PER_M)
		if mag <= 0.0: continue
		CameraUtil.shake_impulse(_shake, mag, _shake_rng.randf_range(0.0, TAU), CameraUtil.SHAKE_CAP_PX)

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
	# The driver's dashboard, bottom centre: visible only while the player is at a wheel, fed by
	# SimVehicles.dash_view in _update_hud. The one gauge on screen, and the car's, not the
	# body's -- dashboard.gd's header says why that is not the health bar.
	var dash_script: GDScript = load("res://ui/dashboard.gd") as GDScript
	if dash_script != null:
		_dashboard = dash_script.new() as Control
		_dashboard.name = "Dashboard"
		_dashboard.visible = false
		layer.add_child(_dashboard)
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
		# The one interact key, named once (INTERACT_KEY) rather than as a literal in the match
		# below, because a match arm binds an identifier instead of comparing against it. It
		# pushes `use.context` and nothing else: fortify's ladder (SimFortify._use_context)
		# decides what "interact" means where you stand -- a loose item, a container, a
		# survivor at the gate, a car's hood from the nose, its door from the side, out from
		# the wheel, a window, a bed. Nothing here knows which; the sim decides.
		if ke.keycode == INTERACT_KEY:
			if world != null: world.commands.push({"type": "use.context"})
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
	# 32 so nearest-neighbour scaling never shimmers. Not while the inventory is open:
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
	# The loaded body can be anywhere on the map; recentre unsmoothed rather than let the
	# per-frame follow visibly pan there from wherever the camera sat before the load.
	_snap_camera()

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
	# Every rendered frame, paused or not: the follow lerp and shake decay both run on
	# wall-clock delta, not on the sim's fixed tick, so they must not wait behind `paused`'s
	# early return below or a shake in flight would freeze mid-decay instead of finishing.
	_update_camera(delta)
	if paused:
		_update_hud()
		if CameraUtil.shake_magnitude(_shake) > CameraUtil.SHAKE_EPSILON:
			queue_redraw()
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
		if _sfx != null:
			_sfx.tick(world, camera, world.events.drained)
		_camera_shake_from_events(world.events.drained)
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
		# The car beside you, or the one you are in: prose from the sim's own read model, words
		# only, after fortify's look-at because a window you are facing is the nearer thing.
		if context.is_empty():
			context = SimVehicles.hud_clause(world, world.player)
		if not _content_error.is_empty():
			context = "content: %s" % _content_error
		_hud.set("hint", context)
		_hud.call("refresh", world, who, base)
	# The dashboard reads the seat every refresh: {} off the wheel hides it.
	if _dashboard != null and _dashboard.has_method("set_view"):
		_dashboard.call("set_view", SimVehicles.dash_view(world, world.player))
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
	_draw_light_pools()
	_draw_entities()
	_draw_rain()
	_draw_night_wash()
	# glimpse drawn by Control; nothing else needed here

func _draw_district() -> void:
	var zoom: float = float(camera["zoom"])
	# Resolved once per frame rather than once per tile: the lookup is a scan over the content
	# tree and the loop below asks about every visible tile.
	var dress: Dictionary = _dressing()
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
					# A wall in a building with a look draws its material: the cap seen from
					# above, or the face where the street is to its south (RoofLook decides,
					# Dressing names the picture). Everything else -- a screen, a barricade, a
					# wall no template stamped -- keeps the procedural cap and bands, the
					# supported fallback and check_topdown.gd's WALL lane's subject.
					if not _draw_wall_art(rect, dress, tx, ty, false):
						_draw_solid_tile(rect, col, tx, ty)
				SimTileMap.Tile.Window:
					# A window is a hole in masonry, so the tile is masonry and the glass is the
					# pane: the tile colour that used to fill it edge to edge is handed to the
					# pane instead, which is where the state a boarded-up window reaches stage 3
					# in still shows. In a face the pane is the face's own window picture.
					if not _draw_wall_art(rect, dress, tx, ty, true):
						_draw_solid_tile(rect, Palette.COLOURS["wall"], tx, ty)
						_draw_window_glass(rect, tx, ty, col)
				SimTileMap.Tile.Low:
					_draw_floor_tile(rect, Appearance.indoor_floor(world.tilemap, tx, ty, ground), tx, ty, Appearance.ground_row_for(world.tilemap, tx, ty, false))
					# A Low tile is one of exactly two things, and the manifest says which: a tile
					# a parked vehicle covers is part of one feet-anchored picture standing in the
					# entity sort (_draw_entities blits it through _blit_vehicle), so this branch
					# draws only the ground under it; every other Low tile is a heap, out of
					# content through Dressing. The two are mutually exclusive by construction and
					# check_wrecks.gd holds this branch to it. When content declares no heap the
					# inset block still draws -- the procedural cover shape is a supported path
					# here as everywhere, not a stopgap.
					if Dressing.vehicle_at(_vehicle_index(), world.tilemap, tx, ty) == Dressing.VEHICLE_NONE:
						if not _draw_heap(rect, dress, tx, ty):
							# Inset block with floor showing around it reads as waist-high.
							var inset: float = zoom * 0.15625
							draw_rect(Rect2(rect.position + Vector2(inset, inset), rect.size - Vector2(inset * 2.0, inset * 2.0)), col)
				SimTileMap.Tile.Tree:
					_draw_floor_tile(rect, Appearance.indoor_floor(world.tilemap, tx, ty, ground), tx, ty, Appearance.ground_row_for(world.tilemap, tx, ty, false))
					# A tree with a picture stands in the entity sort (Dressing.tree_tiles feeds
					# _draw_entities, which blits it through _blit_tree), so this branch draws
					# only the ground under it. The two discs stay as the fallback for a
					# dressing block that names no tree, or a key with no file behind it.
					var tree_key: String = Dressing.tree_key(dress, int(world.seed), tx, ty)
					if tree_key.is_empty() or Appearance.resolve(tree_key) == null:
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
						_draw_door_face(rect, dress, tx, ty)
					else:
						# The road dressing, composed over the same rect: RoadPaint.mask_for
						# (cached per map in _road_mask) says what this tile of pavement is, a
						# sidewalk substitutes its slab colour before the fill, the dash and the
						# kerb lines draw after it, and every plain floor takes the position-hash
						# value offset so the ground stops being one flat slab up close. All of it
						# is paint over the tile the sim already owns -- the fill still comes
						# through Appearance.ground_colour above, and a map with no street
						# manifest simply draws unpainted.
						var mask: PackedByteArray = _road_mask()
						var paint: int = _mask_at(mask, tx, ty)
						if paint == RoadPaint.MASK_SIDEWALK:
							floor_col = Palette.COLOURS["sidewalk"]
						var vo: float = RoadPaint.vary(tx, ty)
						floor_col = Color(
							clampf(floor_col.r + vo, 0.0, 1.0),
							clampf(floor_col.g + vo, 0.0, 1.0),
							clampf(floor_col.b + vo, 0.0, 1.0),
							floor_col.a)
						_draw_floor_tile(rect, floor_col, tx, ty, Appearance.ground_row_for(world.tilemap, tx, ty, paint == RoadPaint.MASK_SIDEWALK))
						# The edges of the ground: where a darker ground lies beside this one,
						# its ragged fringe over this tile's floor -- before the dash, the
						# kerbs and the scatter, all of which lie on top of the ground.
						_draw_ground_edges(rect, _ground_rows(), tx, ty)
						if paint == RoadPaint.MASK_DASH:
							_draw_road_dash(rect, mask, tx, ty)
						if paint != RoadPaint.MASK_NONE:
							_draw_kerbs(rect, RoadPaint.kerb_edges(world.tilemap, mask, tx, ty))
						# And the loose stuff on top of all of it: broken concrete where the
						# rubble pass laid rubble, a scrap of litter every so many tiles of
						# pavement. Cosmetic, hash-picked, and drawn over the paint rather than
						# under it, because litter blows onto a road marking and not beneath one.
						_draw_scatter(rect, dress, tx, ty)
	# The roofs, over the interiors the survivor cannot see: they fill tiles the loop above
	# skipped as unseen, so a roof draws where the screen was black and never where the sim
	# can see (RoofLook.roof_tiles is the rule; check_roof_look.gd holds it both ways).
	_draw_roofs(dress, seen, bounds)
	# Props last, over the ground and under the bodies _draw_entities sorts: a container, a bed,
	# a campfire and the well all stood invisible in this district until this call existed.
	_draw_props()

# A floor is its ground's atlas cell, modulated to the flat colour the palette would have drawn,
# at GROUND_TEXTURE_MIN_ZOOM and above; below that (16 px a tile, where the texture is noise) and
# whenever no atlas resolves, the flat colour alone -- the supported fallback, not a stopgap. No
# hairline grid in either branch any more: the reference has no tile grid, and the cells' own
# edges carry the tiling. One region blit from one texture per tile so the batcher keeps
# consecutive floors in one call; the cell is a position hash through Dressing, never an RNG.
func _draw_floor_tile(rect: Rect2, col: Color, tx: int, ty: int, row: int) -> void:
	var atlas: Texture2D = Appearance.ground_atlas()
	if atlas != null and float(camera["zoom"]) >= Palette.GROUND_TEXTURE_MIN_ZOOM:
		var variant: int = Dressing.variant_index(int(world.seed), tx, ty, Dressing.SALT_GROUND, Appearance.GROUND_VARIANTS)
		draw_texture_rect_region(atlas, rect, Appearance.ground_cell(row, variant), Appearance.ground_modulate(col, Appearance.ground_row_tint(row)))
	else:
		draw_rect(rect, col)

# The ground row of every tile, one byte each, cached against the map object like the road mask
# it is built from: a wall, a window, a screen or a tree is ROW_NONE, everything else is what
# ground_row_for answers for it, the sidewalk paint included. Nine lookups here per drawn floor
# is the whole cost of the edge rule.
func _ground_rows() -> PackedByteArray:
	var map: Variant = world.tilemap
	if map == _ground_rows_from:
		return _ground_rows_cache
	_ground_rows_from = map
	_ground_rows_cache = PackedByteArray()
	if map == null:
		return _ground_rows_cache
	var mask: PackedByteArray = _road_mask()
	var w: int = int(map.w)
	var h: int = int(map.h)
	_ground_rows_cache.resize(w * h)
	for ty in h:
		for tx in w:
			var i: int = ty * w + tx
			var tile: int = int(SimTileMap.tile_at(map, tx, ty))
			if tile == SimTileMap.Tile.Wall or tile == SimTileMap.Tile.Window or tile == SimTileMap.Tile.Screen or tile == SimTileMap.Tile.Tree:
				_ground_rows_cache[i] = Appearance.ROW_NONE
			else:
				_ground_rows_cache[i] = Appearance.ground_row_for(map, tx, ty, _mask_at(mask, tx, ty) == RoadPaint.MASK_SIDEWALK)
	return _ground_rows_cache


# A neighbour's row off the cache, ROW_NONE past the map's edge.
func _row_at(rows: PackedByteArray, tx: int, ty: int) -> int:
	var map: Variant = world.tilemap
	if map == null or tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return Appearance.ROW_NONE
	var i: int = ty * int(map.w) + tx
	if i >= rows.size():
		return Appearance.ROW_NONE
	return int(rows[i])


# The darker neighbours' fringes over this tile's floor: Appearance.edge_shapes says which
# (row, shape) cells the lighter tile takes, and each is one region blit of the same atlas
# the floor came from, modulated white because the cell's own mean is the row tint (the ground
# slice's rule, re-applied). Only at the zoom the texture itself draws at: below it the floor
# is a flat fill and a fringe on a flat fill is a smudge.
func _draw_ground_edges(rect: Rect2, rows: PackedByteArray, tx: int, ty: int) -> void:
	var atlas: Texture2D = Appearance.ground_atlas()
	if atlas == null or float(camera["zoom"]) < Palette.GROUND_TEXTURE_MIN_ZOOM:
		return
	var centre: int = _row_at(rows, tx, ty)
	if centre == Appearance.ROW_NONE:
		return
	var around := PackedInt32Array([
		_row_at(rows, tx, ty - 1), _row_at(rows, tx + 1, ty), _row_at(rows, tx, ty + 1), _row_at(rows, tx - 1, ty),
		_row_at(rows, tx + 1, ty - 1), _row_at(rows, tx + 1, ty + 1), _row_at(rows, tx - 1, ty + 1), _row_at(rows, tx - 1, ty - 1),
	])
	for cell in Appearance.edge_shapes(centre, around):
		draw_texture_rect_region(atlas, rect, Appearance.edge_cell(cell.x, cell.y), Color.WHITE)


# The road-paint mask, cached against the map object it was resolved from. RoadPaint.mask_for is
# pure and the cache lives here because a static one would be shared between the two worlds a
# gate boots (the _thresholds precedent, two functions down). A reboot or a load hands over a
# different map object, which is what invalidates it.
func _road_mask() -> PackedByteArray:
	var map: Variant = world.tilemap
	if map == _road_mask_from:
		return _road_mask_cache
	_road_mask_from = map
	_road_mask_cache = RoadPaint.mask_for(map)
	return _road_mask_cache


# The map-dressing block, cached against the content tree it was read from -- the _road_mask and
# _thresholds pattern, and here for the same two reasons: a static cache would be shared between
# the two worlds a gate boots, and the resolution itself (Dressing.block_of) is pure. A content
# hot-reload hands over a different tree object, which is what invalidates it.
func _dressing() -> Dictionary:
	var tree: Variant = world.content
	if tree == _dressing_from:
		return _dressing_cache
	_dressing_from = tree
	_dressing_cache = Dressing.block_of(world)
	return _dressing_cache


# One heap of junk over a Low tile no parked vehicle covers. False when content declares no
# dressing or no heaps, which is the caller's cue to draw the procedural cover block instead.
#
# There is no transform here and no second one to reset. The quarter turn that used to draw an
# east-west run of car segments retired with the segments themselves: a car is one three-quarter
# picture per axis now (docs/30, the Dungeon Settlers look, decision 11), and a heap is a heap
# whichever way its neighbours lie. This file now sets no transform anywhere.
func _draw_heap(rect: Rect2, dress: Dictionary, tx: int, ty: int) -> bool:
	if dress.is_empty():
		return false
	var key: String = Dressing.heap_key(dress, world.tilemap, int(world.seed), tx, ty)
	var texture: Texture2D = Appearance.resolve(key)
	if texture == null:
		return false
	draw_texture_rect(texture, rect, false)
	return true


# The loose stuff: broken concrete over a rubble tile, a scrap of litter over street pavement.
# Both keys are resolved from content and both are hash-picked from the map seed and the tile, so
# a district's debris is the same debris on every boot and after every load. Which tiles are
# eligible is Dressing's business, not this loop's -- it draws whatever comes back and nothing
# when nothing does.
func _draw_scatter(rect: Rect2, dress: Dictionary, tx: int, ty: int) -> void:
	if dress.is_empty():
		return
	var seed_val: int = int(world.seed)
	var key: String = Dressing.rubble_key(dress, world.tilemap, seed_val, tx, ty)
	if key.is_empty():
		key = Dressing.litter_key(dress, world.tilemap, seed_val, tx, ty)
	if key.is_empty():
		return
	var texture: Texture2D = Appearance.resolve(key)
	if texture == null:
		return
	draw_texture_rect(texture, rect, false)


func _mask_at(mask: PackedByteArray, tx: int, ty: int) -> int:
	if world == null or tx < 0 or ty < 0 or tx >= int(world.map_width) or ty >= int(world.map_height):
		return RoadPaint.MASK_NONE
	var idx: int = ty * int(world.map_width) + tx
	if idx >= mask.size():
		return RoadPaint.MASK_NONE
	return int(mask[idx])


# Lane paint: a worn dash on the street's centre row. Orientation is read off the mask itself --
# the next dash along the same street sits two tiles away on the same row or column (the
# (tx+ty)%2 alternation skips one) -- so a probe two out says which way the line runs, and a dash
# with no neighbour, boxed in by junctions or worn ends, falls back to a square blotch of the
# same paint rather than guessing an axis.
func _draw_road_dash(rect: Rect2, mask: PackedByteArray, tx: int, ty: int) -> void:
	var vertical: bool = _mask_at(mask, tx, ty - 2) == RoadPaint.MASK_DASH \
			or _mask_at(mask, tx, ty + 2) == RoadPaint.MASK_DASH
	var horizontal: bool = _mask_at(mask, tx - 2, ty) == RoadPaint.MASK_DASH \
			or _mask_at(mask, tx + 2, ty) == RoadPaint.MASK_DASH
	var centre: Vector2 = rect.get_center()
	var long_side: float = rect.size.x * 0.62
	var short_side: float = maxf(2.0, rect.size.x * 0.14)
	var dash: Rect2
	if vertical and not horizontal:
		dash = Rect2(centre - Vector2(short_side / 2.0, long_side / 2.0), Vector2(short_side, long_side))
	elif horizontal and not vertical:
		dash = Rect2(centre - Vector2(long_side / 2.0, short_side / 2.0), Vector2(long_side, short_side))
	else:
		dash = Rect2(centre - Vector2(short_side, short_side), Vector2(short_side * 2.0, short_side * 2.0))
	draw_rect(dash, Palette.COLOURS["roadPaint"])


# The kerb: a thin strip on each edge where pavement meets ground that is not pavement, read per
# frame off the neighbours the way _draw_solid_tile reads its exposed faces.
func _draw_kerbs(rect: Rect2, edges: int) -> void:
	if edges == 0:
		return
	var t: float = maxf(1.0, rect.size.x * 0.09)
	var kerb: Color = Palette.COLOURS["kerb"]
	if (edges & RoadPaint.EDGE_N) != 0:
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, t)), kerb)
	if (edges & RoadPaint.EDGE_S) != 0:
		draw_rect(Rect2(rect.position + Vector2(0.0, rect.size.y - t), Vector2(rect.size.x, t)), kerb)
	if (edges & RoadPaint.EDGE_W) != 0:
		draw_rect(Rect2(rect.position, Vector2(t, rect.size.y)), kerb)
	if (edges & RoadPaint.EDGE_E) != 0:
		draw_rect(Rect2(rect.position + Vector2(rect.size.x - t, 0.0), Vector2(t, rect.size.y)), kerb)

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
	draw_rect(pane, Palette.COLOURS["windowRim"], false, 2.0)

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
	_draw_floor_tile(rect, col.lerp(Palette.COLOURS["threshold"], 0.75), tx, ty, Appearance.GroundRow.Boards)
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


# tile -> building index, cached against the map object like the road mask: a reboot or a load
# hands over a different map, which is what invalidates it.
func _building_index() -> PackedInt32Array:
	var map: Variant = world.tilemap
	if map == _roof_index_from:
		return _roof_index_cache
	_roof_index_from = map
	_roof_index_cache = RoofLook.building_index(map)
	_looks = {}
	return _roof_index_cache


# tile -> parked vehicle, cached against the map object exactly as the building index is -- but
# holding only the records that will actually be *drawn* as a picture, which is a stronger thing
# than the manifest says and is what the Low branch needs.
#
# Dressing.vehicle_index is pure and content-innocent: it marks every footprint tile of every
# record. A record whose class declares no art, or whose key has no file behind it, still occupies
# those tiles -- and if the tile branch deferred to a picture that never draws, ten tiles of cover
# the sim knows about would show as bare road. So the records that resolve nothing are cleared
# here, and their tiles fall through to a heap and then to the procedural cover block, the same
# graceful absence the tree branch has when a dressing block names no tree. Resolved once per map,
# never per tile: the content lookup is a scan over the tree.
func _vehicle_index() -> PackedInt32Array:
	var map: Variant = world.tilemap
	# The map object alone is not the key any more: a driven car moves its record and its Low
	# tiles under the same map, and SimVehicles bumps `vehicle_generation` every time it does.
	var gen: int = 0 if map == null else int(map.vehicle_generation)
	if map == _vehicle_index_from and gen == _vehicle_index_gen:
		return _vehicle_index_cache
	_vehicle_index_from = map
	_vehicle_index_gen = gen
	_vehicle_index_cache = Dressing.vehicle_index(map)
	var records: Variant = null if map == null else map.get("vehicles")
	if not (records is Array):
		return _vehicle_index_cache
	var undrawn: Dictionary = {}
	for i in (records as Array).size():
		var rec: Variant = (records as Array)[i]
		if not (rec is Dictionary):
			continue
		var key: String = Dressing.vehicle_key(world, rec as Dictionary, int(world.seed))
		if key.is_empty() or Appearance.resolve(key) == null:
			undrawn[i] = true
	if undrawn.is_empty():
		return _vehicle_index_cache
	for i2 in _vehicle_index_cache.size():
		if undrawn.has(int(_vehicle_index_cache[i2])):
			_vehicle_index_cache[i2] = Dressing.VEHICLE_NONE
	return _vehicle_index_cache


# The look of the building a tile lies in, or {} for a tile in none. Resolved once per building
# per map, never per tile: the content lookup is a scan over the tree.
func _look_at(tx: int, ty: int) -> Dictionary:
	var map: Variant = world.tilemap
	if map == null:
		return {}
	var index: PackedInt32Array = _building_index()
	var at: int = ty * int(map.w) + tx
	if at < 0 or at >= index.size():
		return {}
	return _look_for(index[at])


func _look_for(building: int) -> Dictionary:
	if building == RoofLook.INDEX_NONE:
		return {}
	if not _looks.has(building):
		_looks[building] = RoofLook.look_of(world, building)
	return _looks[building] as Dictionary


# A wall tile in a building with a look: its material's cap, or its face where the street is to
# the south, blitted into the tile's own rect; a window in a face is the face's window picture,
# and a window in a cap is the pane the procedural path draws. False when there is nothing to
# draw this way -- no building, no look, a material with no art, or a barricade overlay, which
# keeps the procedural cap so a boarded window still reads as boarded -- and the caller falls
# back. Nothing here reaches outside the rect: the face is inside the wall tile, not over the
# street.
func _draw_wall_art(rect: Rect2, dress: Dictionary, tx: int, ty: int, window: bool) -> bool:
	var look: Dictionary = _look_at(tx, ty)
	if look.is_empty():
		return false
	if SimTileMap.overlay_at(world.tilemap, tx, ty) is Dictionary:
		return false
	var face: bool = RoofLook.wall_face_at(world.tilemap, tx, ty)
	var texture: Texture2D = Appearance.resolve(Dressing.wall_key(dress, String(look.get("wall", "")), face))
	if texture == null:
		return false
	draw_texture_rect(texture, rect, false)
	if window:
		var pane: Texture2D = null
		if face:
			pane = Appearance.resolve(Dressing.face_key(dress, "window"))
		if pane != null:
			draw_texture_rect(pane, rect, false)
		else:
			_draw_window_glass(rect, tx, ty)
	return true


# The door in a front face: a doorway whose south neighbour is the street takes the door
# picture, or the garage mouth when the doorway beside it is one too, over the boards
# _draw_threshold already drew. In the doorway's own rect -- a body walking through draws over
# it, because entities draw after the district -- and nothing when the building has no look or
# the dressing names no picture.
func _draw_door_face(rect: Rect2, dress: Dictionary, tx: int, ty: int) -> void:
	if _look_at(tx, ty).is_empty():
		return
	var kind: int = RoofLook.facade_at(world.tilemap, _threshold_tiles(), tx, ty)
	var key: String = ""
	if kind == RoofLook.Face.DOOR:
		key = Dressing.face_key(dress, "door")
	elif kind == RoofLook.Face.GARAGE:
		key = Dressing.face_key(dress, "garage")
	if key.is_empty():
		return
	var texture: Texture2D = Appearance.resolve(key)
	if texture != null:
		draw_texture_rect(texture, rect, false)


# The roofs: RoofLook.roof_tiles says which interior tiles the survivor cannot see belong to a
# building they can see part of, and each takes its material's sheet -- the north or south half
# of a pitched roof about the footprint's ridge row, or the flat one -- or, with no art for the
# material, the palette's roof slab. Drawn after the tile loop (those tiles were skipped as
# unseen, so this is the first paint on them) and before the props, which are never drawn on
# an unseen tile anyway.
func _draw_roofs(dress: Dictionary, seen: Variant, bounds: Dictionary) -> void:
	if world.tilemap == null or seen == null:
		return
	var zoom: float = float(camera["zoom"])
	var half: float = zoom / 2.0
	var player_tile := Vector2i(-1, -1)
	var pos: Variant = world.components.get_component(int(world.player), "position")
	if pos is Dictionary:
		player_tile = Vector2i(floori(float((pos as Dictionary)["x"])), floori(float((pos as Dictionary)["y"])))
	var index: PackedInt32Array = _building_index()
	var w: int = int(world.tilemap.w)
	for t in RoofLook.roof_tiles(world.tilemap, seen, bounds, player_tile):
		var sc: Dictionary = TopDownProjection.world_to_screen(camera, float(t.x) + 0.5, float(t.y) + 0.5)
		var rect := Rect2(roundf(float(sc["sx"]) - half), roundf(float(sc["sy"]) - half), zoom, zoom)
		var building: int = index[t.y * w + t.x]
		var look: Dictionary = _look_for(building)
		var texture: Texture2D = null
		if not look.is_empty():
			var material: String = String(look.get("roof", ""))
			var slope: int = RoofLook.slope_of(RoofLook.rect_of(world.tilemap, building), t.y, Dressing.roof_pitched(dress, material))
			texture = Appearance.resolve(Dressing.roof_key(dress, material, slope))
		if texture != null:
			draw_texture_rect(texture, rect, false)
		else:
			draw_rect(rect, Palette.COLOURS["roof"])


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

# Warm pools where the district is lit *and* the survivor can see it. docs/30's clause on the
# overlay: lit alone is a fact about the world, lit and seen is a fact about the survivor, and a
# pool painted where nobody has a sightline is the screen asserting what the simulation denies.
# The set of tiles is light_look.gd's, so the no-leak rule is one function with a gate on it
# rather than a condition repeated in a draw loop.
#
# Over the floor and under the bodies: the pool is light landing on the ground, so a body standing
# in one is drawn on top of it rather than tinted by it -- the entity pass owns what a body looks
# like, and this may not reach into that.
func _draw_light_pools() -> void:
	if world == null: return
	var overlay: bool = attention_channel == "light"
	# At noon a lamp changes nothing about what anyone can see -- sight_metres caps at the
	# observer's own range -- so an ordinary frame paints no pools at all in full daylight, and
	# the warm look belongs to dusk, night and dawn. The O channel is a developer overlay reading
	# the light index directly and draws them regardless, which is the whole point of it.
	if not overlay and LightLook.ambient_of(world) >= 1.0: return
	var bounds: Dictionary = TopDownProjection.visible_bounds(camera, 2.0)
	var pools: Dictionary = LightLook.lit_pool_tiles(world, int(world.player), bounds)
	_fill_pool_tiles(pools["near"] as Array, Palette.LIGHT_POOL_NEAR_OVERLAY if overlay else Palette.LIGHT_POOL_NEAR)
	_fill_pool_tiles(pools["far"] as Array, Palette.LIGHT_POOL_FAR_OVERLAY if overlay else Palette.LIGHT_POOL_FAR)


# Geometry only, and the same tile rect _draw_district lays down, so a pool covers its floor tile
# exactly rather than sitting a half-pixel off it at some zooms.
func _fill_pool_tiles(tiles: Array, col: Color) -> void:
	var zoom: float = float(camera["zoom"])
	var half: float = zoom / 2.0
	for t in tiles:
		var tile: Vector2i = t as Vector2i
		var sc: Dictionary = TopDownProjection.world_to_screen(camera, float(tile.x) + 0.5, float(tile.y) + 0.5)
		draw_rect(Rect2(roundf(float(sc["sx"]) - half), roundf(float(sc["sy"]) - half), zoom, zoom), col)


func _draw_entities() -> void:
	if world == null: return
	# One art pixel in screen pixels, asked once: the camera cannot change inside a draw
	# pass, and every body, shadow and glimpse disc below is sized off the same answer --
	# a rig that ignored the zoom would draw a 64 px body over a 16 px tile.
	var px_scale: float = Appearance.blit_scale(float(camera["zoom"]))
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
		# A body at a wheel is inside the car, and the car's picture is what stands there: the
		# sim pins its position to the car's centre, so drawing it too would stand a pawn on the
		# bonnet. The car itself joins the sort below as a manifest record SimVehicles keeps.
		# A rider on an open vehicle (`mounted.cab` false -- a bicycle, a scooter, a board) is
		# drawn: the pawn stands on the machine's own ground point, lifted a little off it, and
		# sorts a hair in front of the picture so the frame does not paint over the legs.
		var mounted: Variant = world.components.get_component(int(ent), "mounted")
		var rider_depth: float = -1.0
		if mounted is Dictionary:
			if bool((mounted as Dictionary).get("cab", false)):
				continue
			var ridden: int = int((mounted as Dictionary).get("vehicle", -1))
			var rv: Variant = world.components.get_component(ridden, "vehicle")
			var rpos: Variant = world.components.get_component(ridden, "position")
			if rv is Dictionary and rpos is Dictionary:
				var gp: Vector2 = SimVehicles.ground_point(rv as Dictionary, rpos as Dictionary)
				x = gp.x
				y = gp.y - RIDER_LIFT_M
				rider_depth = TopDownProjection.depth_of(gp.x, gp.y) + RIDER_DEPTH_EPS
		# Walls / boards block; windows stay Clear — match sim vision, not camera frustum.
		var det: int = SimVisibility.Detail.Focal
		if not is_player and world.vision != null:
			det = int(world.vision.detail(int(world.player), x, y))
			if det == SimVisibility.Detail.Unseen:
				continue
			if det == SimVisibility.Detail.Peripheral:
				# A glimpse is motion or nothing. Appearance.moving owns what "moving" means --
				# a missing velocity component is motionless (a corpse), not unknown -- so the
				# still, the dead and the parked all stay undrawn here.
				var vel: Variant = world.components.get_component(int(ent), "velocity")
				if not Appearance.moving(vel):
					continue
		var sc: Dictionary = TopDownProjection.world_to_screen(camera, x, y)
		var depth: float = TopDownProjection.depth_of(x, y) if rider_depth < 0.0 else rider_depth
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
	# The trees join the same sort: each is a picture standing on its trunk tile's south-edge
	# centre, so a body north of the trunk sorts behind it and one south sorts in front
	# (docs/30, the Dungeon Settlers look, decision 9). Draw is a subset of seen --
	# Dressing.tree_tiles asks the survivor's own seen set, and an unseen trunk draws nothing.
	# The Focal bodies' ground points are gathered first, for the one fade rule: the tree
	# fades while a body stands inside its rect, and the body is never dimmed.
	var focal_points: Array[Vector2] = []
	for body in items:
		if int(body["det"]) == SimVisibility.Detail.Focal:
			focal_points.append(Vector2(float(body["sx"]), float(body["sy"])))
	var dress: Dictionary = _dressing()
	var seen: Variant = null
	if world.vision != null:
		seen = world.vision.tiles_for(int(world.player))
	for t in Dressing.tree_tiles(world.tilemap, seen, TopDownProjection.visible_bounds(camera, 2.0)):
		var tree_key: String = Dressing.tree_key(dress, int(world.seed), t.x, t.y)
		if tree_key.is_empty() or Appearance.resolve(tree_key) == null:
			continue
		var tx_w: float = float(t.x) + 0.5
		var ty_w: float = float(t.y) + 1.0
		var tsc: Dictionary = TopDownProjection.world_to_screen(camera, tx_w, ty_w)
		items.append({"kind": "tree", "key": tree_key, "sx": float(tsc["sx"]), "sy": float(tsc["sy"]), "d": TopDownProjection.depth_of(tx_w, ty_w), "det": SimVisibility.Detail.Focal})
	# The parked vehicles join the same sort on the same rule: each is one three-quarter picture
	# standing on its footprint's south-edge centre (docs/30, decision 11), so a body north of a
	# car is behind it and one south is in front. Draw is a subset of seen -- vehicle_records
	# asks the survivor's own seen set -- and the tile branch has already deferred every covered
	# Low tile to this picture, so an unseen car draws nothing at all. The margin is wider than
	# the trees' and follows the footprint table rather than any one class: a vehicle whose
	# ground point is off the bottom of the screen still has most of its picture on it, and the
	# longest class decides how far off that can be (Appearance.vehicle_reach_tiles -- a margin
	# that remembered the sedan's six popped an eight-tile truck out with its cab still showing).
	var records: Variant = null
	if world.tilemap != null:
		records = world.tilemap.get("vehicles")
	if records is Array:
		var box: Dictionary = TopDownProjection.visible_bounds(camera, float(Appearance.vehicle_reach_tiles()))
		for i in Dressing.vehicle_records(world.tilemap, seen, box):
			var rec: Dictionary = (records as Array)[i] as Dictionary
			var vkey: String = Dressing.vehicle_key(world, rec, int(world.seed))
			if vkey.is_empty() or Appearance.resolve(vkey) == null:
				continue
			var gp: Vector2 = Dressing.vehicle_ground_point(rec)
			var vsc: Dictionary = TopDownProjection.world_to_screen(camera, gp.x, gp.y)
			var flip: float = Appearance.vehicle_flip(String(rec.get("facing", "")))
			items.append({"kind": "vehicle", "key": vkey, "flip": flip, "sx": float(vsc["sx"]), "sy": float(vsc["sy"]), "d": TopDownProjection.depth_of(gp.x, gp.y), "det": SimVisibility.Detail.Focal})
	items.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))
	for it in items:
		if String(it.get("kind", "")) == "tree":
			_blit_tree(it, px_scale, focal_points)
			continue
		if String(it.get("kind", "")) == "vehicle":
			_blit_vehicle(it, px_scale)
			continue
		var sx: float = float(it["sx"]); var sy: float = float(it["sy"])
		# Colours and sprites come from content now, not from a chain of type-id checks here.
		var look: Dictionary = Appearance.for_entity(world, it)
		var col: Color = look["tint"] as Color
		# The radius is authored in art pixels (the resolver is zoom-innocent); the glimpse
		# disc, contact shadow, fallback disc and outline ring all follow this one scaling.
		var r: float = float(look["radius"]) * px_scale
		# A peripheral glimpse is one anonymous shape: no sprite, no gear, no facing
		# (docs/30 -- posture and facing are information the glimpse did not earn).
		if int(it["det"]) == SimVisibility.Detail.Peripheral:
			# The alpha stays a call-site fact: the palette key is the glimpse's colour, and how
			# solid the disc draws is this branch's own business, not a second colour to tune.
			var glimpse: Color = Palette.COLOURS["glimpse"] as Color
			draw_circle(Vector2(sx, sy), r, Color(glimpse.r, glimpse.g, glimpse.b, 0.75))
			continue
		# Facing, read once and before anything is drawn: the body's flip, the indicator line
		# and the aim cone are three readings of one number, and the sim is the only thing that
		# arbitrates it: the `aim` command turns a stationary body, and `world._integrate_movement`
		# overwrites facing from the velocity of a moving one, in that order. Nothing here
		# computes a second aim angle of its own.
		var eid: int = int(it["id"])
		var facing_v: Variant = world.components.get_component(eid, "facing")
		var face: float = 0.0
		if facing_v is Dictionary:
			face = float((facing_v as Dictionary).get("radians", 0.0))
		# Screen axes are world axes under the top-down projection: no rotation.
		var screen_ang: float = face
		# contact shadow — under both branches, on the ground point: an ellipse the body's width
		# and a fifth as tall, because a pawn's feet are not the overhead rig's silhouette and the
		# reference's shadow is a small dark pool under the soles, not a disc the figure stands in.
		# FOOT_DROP_PX is a screen-pixel constant on purpose, like the facing line's +12 and the
		# aim cone's +36/+44 below: a readout of the interface, not a length in the world -- and
		# it is the same number Appearance.body_rect stands a pawn's soles on, so the shadow line
		# and the sole line cannot drift apart.
		draw_colored_polygon(_shadow_ellipse(sx, sy + Appearance.FOOT_DROP_PX, r * 0.55, r * 0.22), Color(0, 0, 0, 0.35))
		var texture: Texture2D = look["texture"] as Texture2D
		if texture != null:
			# Scaled by px_scale so a body covers the same fraction of a tile at every step on
			# the zoom ladder. Where the picture hangs is Appearance.body_rect's answer: a pawn
			# (taller than wide) stands with its soles on the shadow line, a tile-square picture
			# centres on the ground point, and a body facing west is the same picture in a
			# negative-width rect -- the renderer mirrors it, and no transform is set anywhere in
			# this loop. Nobody rotates, the player included (docs/30, the Dungeon Settlers look);
			# check_topdown.gd's flip lane counts the transforms here and requires zero.
			var size: Vector2 = texture.get_size() * px_scale
			# Equipped gear composites at the identical rect the body draws at -- an
			# equipSprite is authored on the same feet-anchored canvas, so there is no per-item
			# offset to compute here, and a negative width mirrors the gear with its wearer.
			# Drawn white, never the role/tint colour: a backpack is its own object, not a
			# stand-in shape for the entity itself.
			var equip: Array[Dictionary] = Appearance.equipment_layers_for(world, eid)
			_blit_body(Appearance.body_rect(sx, sy, size, Appearance.body_flip(screen_ang)), texture, col, equip)
		else:
			draw_circle(Vector2(sx, sy), r, col)
			draw_circle(Vector2(sx, sy), r, col.lightened(0.25), false, 2.4 if bool(it["player"]) else 1.6)
		# Facing + aim sway (cone half-angle). No hit % — wobble is the readout.
		# The line draws for every body, the player's included: a flip is a two-state readout of
		# a continuous heading, so the picture can never say more than "east or west" and the
		# line carries the exact facing for everybody. (The 2026-09-01 rule that took it off the
		# player's rotating rig retired with the rotation -- docs/30, the Dungeon Settlers look.)
		draw_line(
			Vector2(sx, sy),
			Vector2(sx + cos(screen_ang) * (r + 12.0), sy + sin(screen_ang) * (r + 12.0)),
			Palette.COLOURS["facing"],
			2.4 if bool(it["player"]) else 1.6,
		)
		if bool(it["player"]) and world.components.has_component(eid, "rangedWeapon"):
			var rw: Variant = world.components.get_component(eid, "rangedWeapon")
			if rw is Dictionary and int((rw as Dictionary).get("state", 0)) in [1, 2]:
				var half: float = float((rw as Dictionary).get("coneHalf", 0.55))
				var reach_px: float = r + 36.0 + half * 44.0
				var a0: float = screen_ang - half
				var a1: float = screen_ang + half
				# One colour, drawn twice: the arc at the key's own alpha, the edge rays dimmed
				# by the palette's factor -- never a second literal to keep in step.
				var cone: Color = Palette.COLOURS["aimCone"] as Color
				var edge: Color = Color(cone.r, cone.g, cone.b, cone.a * Palette.AIM_EDGE_DIM)
				draw_arc(Vector2(sx, sy), reach_px, a0, a1, 12, cone, 2.8)
				draw_line(Vector2(sx, sy), Vector2(sx + cos(a0) * reach_px, sy + sin(a0) * reach_px), edge, 2.0)
				draw_line(Vector2(sx, sy), Vector2(sx + cos(a1) * reach_px, sy + sin(a1) * reach_px), edge, 2.0)
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
	var mem: Color = Palette.COLOURS["memory"] as Color
	for row in SimSightings.remembered(world, int(world.player)):
		var m: Dictionary = row as Dictionary
		var age: int = int(m["age"])
		if age <= 0 or age > MEMORY_TICKS: continue
		var sc: Dictionary = TopDownProjection.world_to_screen(camera, float(m["x"]), float(m["y"]))
		var a: float = 0.5 * (1.0 - float(age) / float(MEMORY_TICKS))
		draw_circle(Vector2(float(sc["sx"]), float(sc["sy"])), 8.0, Color(mem.r, mem.g, mem.b, a))


# The rain, over the bodies and under the night wash: a survivor standing in it is standing in
# it, and rain the night has already darkened is rain you cannot see. Presentation-only
# ambience -- the sim has no weather (docs/16's is Milestone 3, and re-keying this layer to it
# is the named forward edge), so the whole sky is a pure function of the tick and a hash,
# rain_look.gd's own rule. Nothing here reads the night's tunables and nothing draws from a
# generator; check_weather.gd scans this body for both.
func _draw_rain() -> void:
	if world == null:
		return
	var size: Vector2 = get_viewport_rect().size
	# The sub-tick fraction, so streaks fall smoothly between the 20 Hz steps instead of
	# stepping with them. Frozen while paused -- _process returns before either term moves --
	# and 10x under fast-forward, which is accepted and recorded: this is ambience, not a clock.
	var t: float = float(world.tick) + clampf(accumulator / TICK_SECONDS, 0.0, 1.0)
	var pts: PackedVector2Array = RainLook.segments(t, size.x, size.y, RainLook.STREAK_COUNT)
	var map: Variant = world.tilemap
	var open := PackedVector2Array()
	for i in range(0, pts.size(), 2):
		var head: Vector2 = pts[i]
		# The head's ground position, asked of the same projection the district draws through,
		# so a streak stops exactly where the roof it would land on starts.
		var w: Dictionary = TopDownProjection.screen_to_world(camera, head.x, head.y)
		if not RainLook.falls_at(map, floori(float(w["x"])), floori(float(w["y"]))):
			continue
		open.append(head)
		open.append(pts[i + 1])
	if open.is_empty():
		return
	# One call for the whole sky: 140 draw_line calls would be 140 draw commands where one does,
	# on a layer rebuilt every frame.
	var key: Color = Palette.COLOURS["rain"] as Color
	var a: float = key.a * RainLook.alpha_scale(RainLook.intensity(t))
	draw_multiline(open, Color(key.r, key.g, key.b, a), 1.0)


# A tree: one tall picture standing on its trunk tile's south-edge centre, hung the way a pawn
# is (Appearance.body_rect with the feet anchor and FOOT_DROP_PX unchanged), never flipped and
# never rotated, and faded -- the tree, never the body -- while a Focal body's ground point lies
# inside its rect (Dressing.tree_alpha, docs/30 decision 10). Drawn white: a tree is its own
# object, not a stand-in shape for anything.
func _blit_tree(it: Dictionary, px_scale: float, focal_points: Array[Vector2]) -> void:
	var texture: Texture2D = Appearance.resolve(String(it["key"]))
	if texture == null:
		return
	var size: Vector2 = texture.get_size() * px_scale
	var rect: Rect2 = Appearance.body_rect(float(it["sx"]), float(it["sy"]), size, 1.0)
	var alpha: float = Dressing.tree_alpha(rect, focal_points)
	draw_texture_rect(texture, rect, false, Color(1.0, 1.0, 1.0, alpha))


# One parked vehicle: a three-quarter picture standing feet-anchored on its footprint's south-edge
# centre, through the same body_rect a pawn and a tree use. The canvas is never square -- a sedan
# is 2x6 tiles north-south and 5x3 east-west -- so anchor_of answers Feet and the picture stands
# on the line rather than centring on the point.
#
# A west-facing car is the east-facing picture in a negative-width rect: the pawn's own flip, and
# the one place a manifest record's `facing` reaches the art. Appearance.vehicle_flip records why
# the north-south axis has no second picture, and no transform is set here or anywhere else in
# this file.
func _blit_vehicle(it: Dictionary, px_scale: float) -> void:
	var texture: Texture2D = Appearance.resolve(String(it["key"]))
	if texture == null:
		return
	var size: Vector2 = texture.get_size() * px_scale
	draw_texture_rect(texture, Appearance.body_rect(float(it["sx"]), float(it["sy"]), size, float(it["flip"])), false)


# One body and everything it is wearing, composited at one rect: under-body layers, the body,
# then over-body layers.
#
# Factored out of _draw_entities so a body and its gear are literally the *same* composite at
# one rect -- which, since the pawn slice, is also what mirrors them together: a negative-width
# rect flips every layer identically, so a slung pack faces the way its wearer does. The gear is
# generated on the pawn canvas beside the rigs (tools/sprites/parts/gear.py); what a survivor
# wears beyond the pack and the bat is the worn-look slice's work (docs/23).
func _blit_body(rect: Rect2, texture: Texture2D, col: Color, equip: Array[Dictionary]) -> void:
	for layer in equip:
		if not bool(layer["over"]):
			draw_texture_rect(layer["texture"] as Texture2D, rect, false)
	draw_texture_rect(texture, rect, false, col)
	for layer in equip:
		if bool(layer["over"]):
			draw_texture_rect(layer["texture"] as Texture2D, rect, false)



# The contact shadow's outline: a twelve-point ellipse, half-axes `a` across and `b` down, so
# the shadow can be a flat pool under the feet without a transform (the entity loop holds none;
# check_topdown.gd's flip lane counts them).
func _shadow_ellipse(cx: float, cy: float, a: float, b: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 12:
		var t: float = TAU * float(i) / 12.0
		points.append(Vector2(cx + cos(t) * a, cy + sin(t) * b))
	return points

# The night, last, over everything. The alpha is derived from the *same number the survivor's
# range is* -- light_look.gd's sight-derived fraction, not raw ambient -- so the screen and the
# simulation cannot drift apart. Standing in a lit pool visibly lifts the wash, and it lifts it
# because the range genuinely grew (docs/30). With nobody to ask, the fraction falls back to
# ambient, which is what this always was.
func _draw_night_wash() -> void:
	var a: float = LightLook.wash_alpha(world, int(world.player), NIGHT_WASH)
	if a <= 0.0: return
	var night: Color = Palette.COLOURS["night"] as Color
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(night.r, night.g, night.b, a))
