extends Node2D
# R4 presentation — isometric district, camera, visibility, light, paperdoll glimpse,
# grid inventory (Controls), keyboard/pointer/pause/speed/save. Reads sim, never writes it.
# Port of src/render/* + src/ui/inventory.ts + src/main.ts split for Godot native.
# ponytail: no atlases yet (circles/rects for bodies, diamonds for tiles). Add ModelSprites when art lands.

const WorldRes = preload("res://sim/world.gd")
const ContentLoader = preload("res://platform/content_loader.gd")
const IsoProjection = preload("res://presentation/projection.gd")
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
const SimLight = preload("res://sim/vision/light.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const PresentationSfx = preload("res://presentation/sfx.gd")

const TICK_HZ: int = 20
const TICK_SECONDS: float = 1.0 / 20.0
const NIGHT_WASH: float = 0.8
const MEMORY_TICKS: int = 60
# Drawing heights (metres), not a z-axis. Walls tall enough to hide rooms; windows are a sill.
const OCCLUDER_RISE: Dictionary = {
	SimTileMap.Tile.Wall: 4.8,
	SimTileMap.Tile.Window: 2.6,
	SimTileMap.Tile.Screen: 3.6,
	SimTileMap.Tile.Low: 0.7,
	SimTileMap.Tile.Tree: 3.2,
}
const OCCLUDER_FADED_ALPHA: float = 0.28
# When indoors, walls drop to a stub so the room stays readable (LOS still blocks outdoors).
const INDOOR_WALL_RISE_M: float = 0.4

var world: Variant = null
var content: Dictionary = {}
var fixture: Dictionary = {}
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
var _selected: int = -1

# paperdoll glimpse state (bottom-right diagram, not world sprite)
var _glimpse_parts: Array = []
var _glimpse_stance: int = 2 # Walk
var _glimpse_worst: int = 0

# memory marks for last-known positions
var _memory: Dictionary = {} # entity -> {x,y,tick}
var _fingerprint: String = ""
var _fingerprint_at: float = -1e9
var _visibility: Variant = null
var _light: Variant = null
var _map: Variant = null
var _content_error: String = ""
var _content_poll_at: float = -1e9
var _sfx: Node = null

# movement input held
var _held: Dictionary = {}
var _last_dx: float = 0.0
var _last_dy: float = 0.0
# Which of the non-sprint rungs (Z/X/C/V) is selected, so releasing Shift returns to it rather
# than to a fixed default. Presentation-local only -- the sim never reads this, it only ever
# sees the stance commands _push_stance sends.
var _selected_stance: int = 2 # Walk

const DIAG: float = 0.70710678
const MOVE_KEYS: Dictionary = {
	KEY_W: {"dx": -DIAG, "dy": -DIAG}, KEY_UP: {"dx": -DIAG, "dy": -DIAG},
	KEY_S: {"dx": DIAG, "dy": DIAG}, KEY_DOWN: {"dx": DIAG, "dy": DIAG},
	KEY_A: {"dx": -DIAG, "dy": DIAG}, KEY_LEFT: {"dx": -DIAG, "dy": DIAG},
	KEY_D: {"dx": DIAG, "dy": -DIAG}, KEY_RIGHT: {"dx": DIAG, "dy": -DIAG},
}

func _ready() -> void:
	content = ContentLoader.load_tree()
	var parity: bool = false
	for arg in OS.get_cmdline_user_args():
		if String(arg) == "--parity":
			parity = true
			break
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
		var boot: Dictionary = SimBoot.playable()
		world = boot["world"]
		_map = boot["map"]
		_visibility = world.vision
		_light = world.light
		fixture = {"seed": int(world.seed), "tick_hz": TICK_HZ}
	_resize_camera()
	_ensure_ui()
	_sfx = PresentationSfx.new()
	add_child(_sfx)
	queue_redraw()
	print("GODOT_R1_READY")
	if world != null:
		print("GODOT_R4_READY zoom %.1f map %dx%d" % [float(camera["zoom"]), int(world.map_width), int(world.map_height)])

func _notification(what: int) -> void:
	if what == 413: # NOTIFICATION_RESIZED
		_resize_camera()
		queue_redraw()

func _resize_camera() -> void:
	var vp: Vector2 = get_viewport_rect().size
	if vp.x < 1: vp = Vector2(960, 540)
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
	# inventory panel (hidden until Tab)
	var inv_script: GDScript = load("res://ui/inventory_panel.gd") as GDScript
	if inv_script != null:
		_inventory_panel = inv_script.new() as Control
		_inventory_panel.visible = false
		layer.add_child(_inventory_panel)
	var work_script: GDScript = load("res://ui/work_panel.gd") as GDScript
	if work_script != null:
		_work_panel = work_script.new() as Control
		_work_panel.visible = false
		_work_panel.position = Vector2(8, 120)
		_work_panel.size = Vector2(760, 160)
		layer.add_child(_work_panel)
	# paperdoll glimpse bottom-right (always visible, cheap)
	var doll_script: GDScript = load("res://ui/paperdoll.gd") as GDScript
	if doll_script != null:
		_paperdoll = doll_script.new() as Control
		_paperdoll.custom_minimum_size = Vector2(140, 140)
		_paperdoll.anchor_left = 1.0; _paperdoll.anchor_top = 1.0; _paperdoll.anchor_right = 1.0; _paperdoll.anchor_bottom = 1.0
		_paperdoll.offset_left = -148; _paperdoll.offset_top = -148; _paperdoll.offset_right = -8; _paperdoll.offset_bottom = -8
		layer.add_child(_paperdoll)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var ke: InputEventKey = event as InputEventKey
		match ke.keycode:
			KEY_F5: _save()
			KEY_F9: _load()
			KEY_P: _toggle_pause()
			KEY_M:
				show_sheets = not show_sheets
				if _hud != null: _hud.set("show_raw", show_sheets)
			KEY_O: _cycle_overlay()
			KEY_F1: _toggle_legend()
			KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER:
				# Dismiss-only: Escape and Enter close the legend but never open it, so they
				# stay free for whatever wants them later.
				if _legend != null and _legend.visible: _legend.visible = false
			KEY_TAB:
				inventory_open = not inventory_open
				if _inventory_panel != null: _inventory_panel.visible = inventory_open
				if _hud != null: _hud.visible = not inventory_open
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
			KEY_G:
				if world != null: world.commands.push({"type": "fire"})
			KEY_R:
				if inventory_open and _inventory_panel != null and _inventory_panel.has_method("rotate"):
					_inventory_panel.call("rotate")
				elif world != null:
					world.commands.push({"type": "reload"})
			KEY_E:
				if world != null: world.commands.push({"type": "use.context"})
			KEY_1: speed = 1
			KEY_2: speed = 3
			KEY_3: speed = 10
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
	if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if world != null and not inventory_open:
			world.commands.push({"type": "fire"})

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
	if now - _fingerprint_at > 0.25:
		# A hash, not a prefix. serialize() returns canonical JSON, so its first 8 characters
		# are always the literal `{"compon` -- the field could never change and so could
		# never show the divergence it exists to show.
		_fingerprint = "%08x" % (world.serialize().hash() & 0xffffffff)
		_fingerprint_at = now
	var diag2: Dictionary = SimInfection.diagnosis_of(world, world.player, 0) as Dictionary
	var diag_label: String = String(diag2.get("label", "clear"))
	var apt: Dictionary = SimAptitudes.of(world, world.player)
	var companion: String = ""
	for ent in world.components.query(["identity", "position"]):
		var ident: Variant = world.components.get_component(int(ent), "identity")
		if ident is Dictionary:
			companion = String((ident as Dictionary).get("name", ""))
			break
	var zeds: int = 0
	for _z in world.components.query(["shambler"]):
		zeds += 1
	var base: String = "tick %d  pos %.1f,%.1f  %s %.2f  light %.2f  %s  %dx %s  STR %d CON %d DEX %d  %s  zed %d  F swing G fire  fp %s  dx:%s" % [int(world.tick), x, y, phase, tod, light, attention_channel, speed, ("PAUSED" if paused else ""), int(apt["str"]), int(apt["con"]), int(apt["dex"]), companion, zeds, _fingerprint, diag_label]
	if world.tilemap != null:
		var look: Dictionary = SimFortify.look_at(world, world.player)
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
		if world.tilemap != null:
			var look2: Dictionary = SimFortify.look_at(world, world.player)
			for k in ["window", "noisemaker"]:
				if not String(look2.get(k, "")).is_empty():
					context = String(look2[k])
					break
		if not _content_error.is_empty():
			context = "content: %s" % _content_error
		_hud.set("hint", context)
		_hud.call("refresh", world, who, base)
	if _work_panel != null and _work_panel.visible and _work_panel.has_method("set_world"):
		_work_panel.call("set_world", world)
	if _inventory_panel != null and _inventory_panel.visible and _inventory_panel.has_method("set_world"):
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
	var half_w: float = zoom * float(IsoProjection.TILE_WIDTH_RATIO) / 2.0
	var half_h: float = zoom * float(IsoProjection.TILE_HEIGHT_RATIO) / 2.0
	var seen: Variant = null
	if world.vision != null:
		seen = world.vision.tiles_for(int(world.player))
	var player_depth: float = -1e9
	var player_sx: float = 0.0
	var player_sy: float = 0.0
	var player_indoors: bool = false
	var ppos: Variant = world.components.get_component(world.player, "position")
	if ppos is Dictionary:
		var px: float = float((ppos as Dictionary)["x"])
		var py: float = float((ppos as Dictionary)["y"])
		player_depth = IsoProjection.depth_of(px, py)
		var psc: Dictionary = IsoProjection.world_to_screen(camera, px, py)
		player_sx = float(psc["sx"])
		player_sy = float(psc["sy"])
		if world.tilemap != null:
			player_indoors = SimTileMap.is_indoors(world.tilemap, floori(px), floori(py))
	# depth sort tiles by x+y (same as bodies)
	var tiles: Array[Dictionary] = []
	var bounds: Dictionary = IsoProjection.visible_bounds(camera, 2.0)
	var min_x: int = maxi(0, floori(float(bounds["minX"])))
	var max_x: int = mini(int(world.map_width) - 1, ceili(float(bounds["maxX"])))
	var min_y: int = maxi(0, floori(float(bounds["minY"])))
	var max_y: int = mini(int(world.map_height) - 1, ceili(float(bounds["maxY"])))
	for ty in range(min_y, max_y + 1):
		for tx in range(min_x, max_x + 1):
			# Walls block sight: only draw tiles the player has a sightline to (windows stay Clear).
			if seen != null and not (seen as Object).call("has_tile", tx, ty):
				continue
			tiles.append({"x": tx, "y": ty, "d": float(tx + ty), "blocked": world.is_blocked_tile(tx, ty)})
	tiles.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))
	var max_visible_depth: float = -1e9
	for t in tiles:
		max_visible_depth = maxf(max_visible_depth, float(t["d"]))
	for t in tiles:
		var tx: int = int(t["x"]); var ty: int = int(t["y"])
		var sc: Dictionary = IsoProjection.world_to_screen(camera, float(tx) + 0.5, float(ty) + 0.5)
		var sx: float = float(sc["sx"]); var sy: float = float(sc["sy"])
		var tile: int = SimTileMap.Tile.Floor
		var col: Color = Palette.COLOURS["floor"]
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
					# Boarded window reads as wall height so you cannot peek through.
					if int((ov as Dictionary).get("stage", 0)) < 3:
						tile = SimTileMap.Tile.Wall
				elif kind == "scrap":
					col = Palette.COLOURS["rubble"]
					tile = SimTileMap.Tile.Wall
		elif bool(t["blocked"]):
			col = Palette.COLOURS["wall"]
			tile = SimTileMap.Tile.Wall
		# diamond
		var pts: PackedVector2Array = PackedVector2Array([
			Vector2(sx, sy - half_h), Vector2(sx + half_w, sy),
			Vector2(sx, sy + half_h), Vector2(sx - half_w, sy)
		])
		draw_colored_polygon(pts, col)
		draw_polyline(pts + PackedVector2Array([pts[0]]), Palette.COLOURS["background"] * 0.9, 1.0)
		var rise_m: float = float(OCCLUDER_RISE.get(tile, 0.0))
		if player_indoors and (tile == SimTileMap.Tile.Wall or tile == SimTileMap.Tile.Screen or tile == SimTileMap.Tile.Window):
			rise_m = minf(rise_m, INDOOR_WALL_RISE_M)
		if rise_m <= 0.0:
			continue
		var rise: float = IsoProjection.metres_to_rise(rise_m, zoom)
		var top_pts: PackedVector2Array = PackedVector2Array([
			Vector2(sx, sy - half_h - rise), Vector2(sx + half_w, sy - rise),
			Vector2(sx, sy + half_h - rise), Vector2(sx - half_w, sy - rise)
		])
		# Near walls that cover the player fade so indoor play stays readable, but only if
		# there are visible tiles behind them (otherwise outdoors facades fade over void).
		var tile_depth: float = float(tx + ty)
		var hides: bool = tile_depth > player_depth and absf(sx - player_sx) < half_w * 2.2 and player_sy > sy - rise - 8.0 and player_sy < sy + half_h + 8.0
		var has_backdrop: bool = max_visible_depth > tile_depth + 0.01
		if hides and has_backdrop:
			col = Color(col.r, col.g, col.b, OCCLUDER_FADED_ALPHA)
		# Windows: bright glass faces + rim so they read against masonry.
		var is_window: bool = tile == SimTileMap.Tile.Window
		var face: Color = col.lightened(0.28) if is_window else col.lightened(0.12)
		draw_colored_polygon(top_pts, face)
		draw_colored_polygon(PackedVector2Array([Vector2(sx - half_w, sy), Vector2(sx, sy + half_h), Vector2(sx, sy + half_h - rise), Vector2(sx - half_w, sy - rise)]), col.darkened(0.08 if is_window else 0.18))
		draw_colored_polygon(PackedVector2Array([Vector2(sx, sy + half_h), Vector2(sx + half_w, sy), Vector2(sx + half_w, sy - rise), Vector2(sx, sy + half_h - rise)]), col.lightened(0.1) if is_window else col.darkened(0.08))
		if is_window:
			draw_polyline(top_pts + PackedVector2Array([top_pts[0]]), Color("#b8eaff"), 2.0)

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
		if world.components.has_component(int(ent), "itemBase"):
			continue
		if not is_player and not is_unique and not is_zed and not is_bait:
			continue
		# Walls / boards block; windows stay Clear — match sim vision, not camera frustum.
		if not is_player and world.vision != null:
			var det: int = int(world.vision.detail(int(world.player), x, y))
			if det == SimVisibility.Detail.Unseen:
				continue
			if det == SimVisibility.Detail.Peripheral:
				var vel: Variant = world.components.get_component(int(ent), "velocity")
				if vel is Dictionary and float((vel as Dictionary).get("dx", 0.0)) == 0.0 and float((vel as Dictionary).get("dy", 0.0)) == 0.0:
					continue
			_memory[int(ent)] = {"x": x, "y": y, "tick": int(world.tick)}
		var sc: Dictionary = IsoProjection.world_to_screen(camera, x, y)
		var depth: float = IsoProjection.depth_of(x, y)
		var ztype: String = ""
		if is_zed:
			var zt: Variant = world.components.get_component(int(ent), "zombieType")
			if zt is Dictionary:
				ztype = String((zt as Dictionary).get("id", ""))
		# Content id for a unique survivor, so appearance resolves for people as well as for
		# zombies. Generated survivors have no content entry and stay on the role colour.
		var cid: String = ""
		if is_unique:
			var ident: Variant = world.components.get_component(int(ent), "identity")
			if ident is Dictionary:
				cid = String((ident as Dictionary).get("id", ""))
		items.append({"x": x, "y": y, "sx": float(sc["sx"]), "sy": float(sc["sy"]), "d": depth, "player": is_player, "unique": is_unique, "zed": is_zed, "bait": is_bait, "ztype": ztype, "cid": cid, "id": int(ent)})
	items.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))
	for it in items:
		var sx: float = float(it["sx"]); var sy: float = float(it["sy"])
		# Colours and sprites come from content now, not from a chain of type-id checks here.
		var look: Dictionary = Appearance.for_entity(world, it)
		var col: Color = look["tint"] as Color
		var r: float = float(look["radius"])
		# contact shadow — under both branches, so a sprite still sits on the ground.
		draw_circle(Vector2(sx, sy + 3), r * 0.9, Color(0, 0, 0, 0.35))
		var texture: Texture2D = look["texture"] as Texture2D
		if texture != null:
			# Feet-anchored: the sprite stands on the entity's ground position rather than
			# being centred on it. Rounded so a 1:1 pixel sprite never lands on a half-pixel
			# as the camera follows the player.
			var size: Vector2 = texture.get_size()
			var at := Vector2(roundf(sx - size.x / 2.0), roundf(sy - size.y))
			draw_texture_rect(texture, Rect2(at, size), false, col)
		else:
			draw_circle(Vector2(sx, sy), r, col)
			draw_circle(Vector2(sx, sy), r, col.lightened(0.25), false, 1.2 if bool(it["player"]) else 0.8)
		# Facing + aim sway (cone half-angle). No hit % — wobble is the readout.
		var eid: int = int(it["id"])
		var facing_v: Variant = world.components.get_component(eid, "facing")
		var face: float = 0.0
		if facing_v is Dictionary:
			face = float((facing_v as Dictionary).get("radians", 0.0))
		var screen_ang: float = face - PI * 0.5
		draw_line(
			Vector2(sx, sy),
			Vector2(sx + cos(screen_ang) * (r + 6.0), sy + sin(screen_ang) * (r + 6.0)),
			Color(1, 1, 1, 0.55),
			1.2 if bool(it["player"]) else 0.8,
		)
		if bool(it["player"]) and world.components.has_component(eid, "rangedWeapon"):
			var rw: Variant = world.components.get_component(eid, "rangedWeapon")
			if rw is Dictionary and int((rw as Dictionary).get("state", 0)) in [1, 2]:
				var half: float = float((rw as Dictionary).get("coneHalf", 0.55))
				var reach_px: float = r + 18.0 + half * 22.0
				var a0: float = screen_ang - half
				var a1: float = screen_ang + half
				draw_arc(Vector2(sx, sy), reach_px, a0, a1, 12, Color(0.85, 0.9, 1.0, 0.35), 1.4)
				draw_line(Vector2(sx, sy), Vector2(sx + cos(a0) * reach_px, sy + sin(a0) * reach_px), Color(0.85, 0.9, 1.0, 0.25), 1.0)
				draw_line(Vector2(sx, sy), Vector2(sx + cos(a1) * reach_px, sy + sin(a1) * reach_px), Color(0.85, 0.9, 1.0, 0.25), 1.0)
	# ground items as lozenges — focal only (searching a room is an action)
	for ent in world.components.query(["position", "itemBase"]):
		if world.components.has_component(int(ent), "stored"): continue
		var p: Variant = world.components.get_component(int(ent), "position")
		if not p is Dictionary: continue
		var ix: float = float((p as Dictionary)["x"]); var iy: float = float((p as Dictionary)["y"])
		if world.vision != null and int(world.vision.detail(int(world.player), ix, iy)) != SimVisibility.Detail.Focal:
			continue
		var sc: Dictionary = IsoProjection.world_to_screen(camera, ix, iy)
		var sx: float = float(sc["sx"]); var sy: float = float(sc["sy"])
		var w: float = 6.0; var h: float = 3.2
		var pts: PackedVector2Array = PackedVector2Array([Vector2(sx, sy - h), Vector2(sx + w, sy), Vector2(sx, sy + h), Vector2(sx - w, sy)])
		draw_colored_polygon(pts, Palette.COLOURS["groundItem"])
		draw_polyline(pts + PackedVector2Array([pts[0]]), Palette.COLOURS["groundItemEdge"], 1.0)
	# last-known marks fading
	for eid in _memory.keys():
		var m: Dictionary = _memory[eid] as Dictionary
		var age: int = int(world.tick) - int(m["tick"])
		if age <= 0 or age > MEMORY_TICKS: continue
		var sc: Dictionary = IsoProjection.world_to_screen(camera, float(m["x"]), float(m["y"]))
		var a: float = 0.5 * (1.0 - float(age) / float(MEMORY_TICKS))
		draw_circle(Vector2(float(sc["sx"]), float(sc["sy"])), 4.0, Color(0.24, 0.29, 0.24, a))

func _draw_night_wash() -> void:
	var tod: float = Clock.time_of_day(int(world.tick))
	var light: float = Clock.ambient_light(tod)
	if light >= 1.0: return
	var a: float = (1.0 - light) * NIGHT_WASH
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.023, 0.039, 0.102, a))
