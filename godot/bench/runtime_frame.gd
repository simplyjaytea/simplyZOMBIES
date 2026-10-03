extends SceneTree
const MeasuredMain = preload("res://bench/measured_main.gd")
const Roster = preload("res://sim/modules/roster.gd")
const Visibility = preload("res://sim/vision/visibility.gd")
const DrawProjection = preload("res://presentation/projection.gd")
const WARMUP: int = 30
const SAMPLES: int = 120
const CROWD: int = 1000
var _server_start: int = 0
var _server_ms: float = 0.0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("a real display and Compatibility renderer are required; headless drawing is not a frame measurement")
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1280, 720)
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false
	var scene := load("res://presentation/main.tscn") as PackedScene
	var main: Node = scene.instantiate()
	# Keep the actual scene's children/settings as it evolves; the wrapper only times super.
	main.set_script(MeasuredMain)
	root.add_child(main)
	await process_frame
	main.call("_on_shell_action", "new_run")
	main.set_process(false)
	main.set("paused", true)
	# Resize the SceneTree Window after scene initialization. Resizing only the native
	# DisplayServer window can leave the Viewport at its original project dimensions.
	root.size = Vector2i(1280, 720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await process_frame
	if root.size != Vector2i(1280, 720):
		_fail("the viewport did not resize to 1280 x 720")
		return
	var legend: Variant = main.get("_legend")
	if legend != null:
		legend.visible = false
	var w: Variant = main.get("world")
	# Populate the real sim sight index once; timing render must not include the sim tick.
	w.step()
	main.call("_update_camera", 0.0)
	RenderingServer.frame_pre_draw.connect(func() -> void: _server_start = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func() -> void: _server_ms = float(Time.get_ticks_usec() - _server_start) / 1000.0)
	var ok: bool = await _sample(main, "shipped-draw", [])
	var crowd: Array[int] = _add_visible_crowd(main, w)
	if crowd.size() != CROWD:
		_fail("the crowd fixture could not place 1,000 visible bodies")
		return
	ok = await _sample(main, "crowded-draw", crowd) and ok
	if not ok:
		_fail("a sample did not finish the real draw consumer or failed its visible-body floor")
		return
	print("RUNTIME_MEASUREMENT_COMPLETE frame")
	main.queue_free()
	quit(0)

func _sample(main: Node, id: String, crowd: Array[int]) -> bool:
	var samples: Array[float] = []
	var server: Array[float] = []
	var intervals: Array[float] = []
	var visible_min: int = CROWD
	var textured_min: int = CROWD
	var previous: int = 0
	var crowd_ids: Dictionary = {}
	for ent in crowd:
		crowd_ids[ent] = true
	for i in WARMUP + SAMPLES:
		var before: int = int(main.get("bench_draw_count"))
		main.set("_drew_tick", -1)
		var previous_focal: Array = main.get("_focal_drawn")
		previous_focal.clear()
		# A previous frame's successful texture resolve cannot satisfy this frame's floor.
		var previous_looks: Dictionary = main.get("_last_look")
		for ent in crowd:
			previous_looks.erase(ent)
		main.call("queue_redraw")
		await RenderingServer.frame_post_draw
		var now: int = Time.get_ticks_usec()
		if int(main.get("bench_draw_count")) != before + 1 or int(main.get("_drew_tick")) != int(main.get("world").tick):
			return false
		if not crowd.is_empty():
			var count: int = 0
			var textured: int = 0
			var looks: Dictionary = main.get("_last_look")
			for drawn in main.get("_focal_drawn"):
				if crowd_ids.has(int(drawn["id"])):
					count += 1
					if looks.has(int(drawn["id"])) and looks[int(drawn["id"])].get("texture") != null:
						textured += 1
			visible_min = mini(visible_min, count)
			textured_min = mini(textured_min, textured)
			if count != CROWD or textured != CROWD:
				return false
		if i >= WARMUP:
			samples.append(float(main.get("bench_draw_us")) / 1000.0)
			server.append(_server_ms)
			intervals.append(float(now - previous) / 1000.0)
		previous = now
	print("RUNTIME_RESULT " + JSON.stringify({
		"id": id, "samples_ms": samples, "server_ms": server, "interval_ms": intervals,
		"warmup": WARMUP, "visible_crowd_min": visible_min if not crowd.is_empty() else 0,
		"textured_crowd_min": textured_min if not crowd.is_empty() else 0,
		"viewport": [root.size.x, root.size.y], "tiles": int(main.get("world").map_width),
		"renderer": RenderingServer.get_video_adapter_name(), "display": DisplayServer.get_name(),
		"engine": Engine.get_version_info()["string"], "vsync_requested": "disabled",
		"vsync_reported": DisplayServer.window_get_vsync_mode(), "cpu": OS.get_processor_name(),
		"scope": "main.tscn world _draw CPU stage only; simulation and _process held; UI draw excluded; server wall time and harness-inclusive intervals separate; not GPU time or fps"
	}))
	return true

func _add_visible_crowd(main: Node, w: Variant) -> Array[int]:
	var player: Dictionary = w.components.get_component(int(w.player), "position")
	var camera: Dictionary = main.get("camera")
	var positions: Array[Vector2] = []
	# Ordinary sight and viewport rules stay live. This is a dense renderer stress fixture,
	# not a physical horde simulation: repeated positions deliberately force 1,000 body blits.
	for dy in range(-8, 9):
		for dx in range(-8, 9):
			var at := Vector2(float(player["x"]) + float(dx) * 0.4, float(player["y"]) + float(dy) * 0.4)
			if w.is_blocked_tile(floori(at.x), floori(at.y)) or w.vision.detail(int(w.player), at.x, at.y) != Visibility.Detail.Focal:
				continue
			var screen: Dictionary = DrawProjection.world_to_screen(camera, at.x, at.y)
			if float(screen["sx"]) > 48 and float(screen["sx"]) < float(root.size.x - 48) and float(screen["sy"]) > 64 and float(screen["sy"]) < float(root.size.y - 48):
				positions.append(at)
	var ids: Array[int] = []
	if positions.is_empty():
		return ids
	var rng: Variant = w.rng.stream("benchmark.placement")
	for i in CROWD:
		var at: Vector2 = positions[i % positions.size()]
		ids.append(Roster.spawn_zombie(w, at.x, at.y, "zombie.shambler", rng))
	return ids

func _fail(message: String) -> void:
	push_error("RUNTIME_FRAME_FAIL " + message)
	quit(1)
