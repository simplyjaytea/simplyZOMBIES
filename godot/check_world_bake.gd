extends SceneTree
# The world, baked (presentation/world_layers.gd, world_mask.gdshader, main.gd's _draw_world and
# _bake_layer; docs/22, "The world, baked"; plan item A4).
#
# The ground, the walls and the roofs used to be drawn tile by tile every frame, with the sight
# question (`has_tile`, `continue`) asked of every tile in the loop. Now each chunk's looks are
# baked once into layers that keep their commands, and a mask shader picks per tile which look
# shows. Two things can go wrong with that, and this gate holds both:
#   the bake goes stale  -- a tile changes and its chunk keeps the old picture, or the zoom or
#                           the content changes and the screen keeps the old scale or art;
#   the mask leaks       -- a tile the survivor cannot see shows its live look, which is drawing
#                           through a wall, the thing the information ban forbids.
# And the third thing, which is the reason the work was done: it must not rebake on a frame where
# nothing it was baked from moved.
#
# Lanes, each with its true positive and its true negative:
#   MASK-RULE  the shader's bit constants and discard rule are the ones world_layers.gd carries,
#              read out of the shader text by a scanner that is first shown a sabotaged copy; the
#              rule table means what the layer comments say (LIVE where seen and no module, A2
#              where both, REMEMBERED where explored and not seen, ROOF where roofed and never
#              explored, ROOF_DIM where roofed and explored), and the three tile layers never show
#              two looks on one tile -- a rule table with LIVE's deny dropped is shown to fail it.
#   SOCKET     _draw calls _draw_world and never _draw_district; _draw_district is reached from
#              _bake_layer alone; and no baked helper draws to main's own frame (a bare
#              `draw_rect(`), proven on a fabricated helper body that does.
#   BAKED      the first frame bakes every chunk under the view; the frames after it finish the
#              prefetch ring and then bake nothing, frame after frame; a camera step inside the
#              baked ring bakes nothing either.
#   REBAKE     a ground change on one tile plus invalidateMap rebakes the chunks that tile's look
#              reaches (its own, and a neighbour's apron) and leaves a far chunk's items alone;
#              invalidateMap with no change rebakes nothing. A zoom change rebakes everything; a
#              content tree swapped for a copy does too.
#   NO-LEAK    over every tile in the view, the mask's LIVE bit is the observer's own `has_tile`
#              and its EXPLORED bit the remembered map's; with both seen and unseen tiles present,
#              a tile neither seen nor explored shows no tile layer at all, and a seen one shows
#              exactly one.
#   ROOF       the ROOF bit is set on exactly the tiles RoofLook.roof_tiles chose this frame.
#   CULL       a chunk's layer item is hidden only where no tile of that chunk shows that layer
#              (world_layers.gd's _cull): every chunk in the view with a tile that shows a layer
#              has that item drawn, and some items are hidden, so the cull is doing something;
#              the checker is shown a chunk with a seen tile and its LIVE item marked hidden.
#   SNOW       driven on a bare WorldLayers with a slow fake bake: a snow step marks every chunk
#              stale, the first frame rebakes at least one and not all of them (the budget), and
#              a few frames later every chunk carries the new step and a frame bakes none.

const SCENE_PATH: String = "res://presentation/main.tscn"
const MAIN_GD: String = "res://presentation/main.gd"
const SHADER_PATH: String = "res://presentation/world_mask.gdshader"
const LAYERS_GD: String = "res://presentation/world_layers.gd"
const WorldLayers = preload("res://presentation/world_layers.gd")
const TopDownProjection = preload("res://presentation/projection.gd")
const RoofLook = preload("res://presentation/roof_look.gd")
const SimSightings = preload("res://sim/modules/sightings.gd")
const Session = preload("res://presentation/session.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")

# Every helper _bake_layer reaches. Each draws through `_pen`, never to main's frame.
const BAKED_HELPERS: Array[String] = [
	"_draw_district", "_draw_floor_tile", "_draw_water_shore", "_draw_ground_edges", "_draw_heap",
	"_draw_scatter", "_draw_road_dash", "_draw_kerbs", "_draw_solid_tile", "_draw_window_glass",
	"_draw_threshold", "_draw_wall_art", "_draw_door_face", "_draw_roofs", "_draw_a2_floor_underlay",
]
const DRAW_CALLS: Array[String] = ["draw_rect(", "draw_circle(", "draw_texture_rect(", "draw_texture_rect_region("]
# Frames the prefetch ring may take to finish after the first frame (one chunk a frame at worst).
const SETTLE_FRAMES: int = 40

var _skips: Array = []
var _report: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _mask_rule() and ok
	ok = _socket() and ok
	ok = _snow() and ok
	var main: Node = await _boot()
	if main == null:
		push_error("WORLD_BAKE_FAIL the scene did not boot")
		quit(1)
		return
	var baked_ok: bool = await _baked(main)
	ok = baked_ok and ok
	ok = _no_leak(main, "boot") and ok
	ok = _cull(main, "boot") and ok
	# Out to a front door, where a building is half seen and its roof stands over the rest; then
	# a few steps back into the street, so what was seen through the door is remembered, not seen.
	var door: Vector2i = _front_door(main)
	if door.x < 0:
		_skip("DOOR", "no front door with open street south of it on this map")
	else:
		await _stand(main, Vector2(float(door.x) + 0.5, float(door.y) + 1.5))
		ok = _no_leak(main, "at the door") and ok
		ok = _cull(main, "at the door") and ok
		ok = _roof(main) and ok
		await _stand(main, Vector2(float(door.x) + 0.5, float(door.y) + 5.5))
		ok = _no_leak(main, "back in the street") and ok
		ok = _cull(main, "back in the street") and ok
	var rebake_ok: bool = await _rebake(main)
	ok = rebake_ok and ok
	main.queue_free()
	await process_frame
	if ok:
		var skipped: String = "no lane skipped" if _skips.is_empty() else "skipped: %s" % ", ".join(PackedStringArray(_skips))
		print("WORLD_BAKE_OK the ground, walls and roofs bake once per chunk and the mask shows only what the survivor sees; %s (%s)" % ["; ".join(PackedStringArray(_report)), skipped])
		quit(0)
	else:
		push_error("WORLD_BAKE_FAIL")
		quit(1)


func _skip(lane: String, why: String) -> bool:
	print("%s SKIP %s" % [lane, why])
	_skips.append("%s (%s)" % [lane, why])
	return true


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


# --- MASK-RULE --------------------------------------------------------------------------------

# `const int NAME = value;` out of shader text, comment lines ignored.
static func _shader_consts(text: String) -> Dictionary:
	var out: Dictionary = {}
	for raw in text.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("//") or not line.begins_with("const int "):
			continue
		var body: String = line.trim_prefix("const int ").trim_suffix(";")
		var parts: PackedStringArray = body.split("=")
		if parts.size() != 2:
			continue
		out[parts[0].strip_edges()] = int(parts[1].strip_edges())
	return out


static func _consts_match(consts: Dictionary) -> bool:
	return int(consts.get("LIVE", -1)) == WorldLayers.BIT_LIVE and int(consts.get("EXPLORED", -1)) == WorldLayers.BIT_EXPLORED \
		and int(consts.get("ROOF", -1)) == WorldLayers.BIT_ROOF and int(consts.get("A2", -1)) == WorldLayers.BIT_A2


static func _shows(rules: Array, layer: int, state: int) -> bool:
	var want: int = int(rules[layer][0])
	var deny: int = int(rules[layer][1])
	return (state & want) == want and (state & deny) == 0


# At most one of the three tile layers on any state, and exactly one wherever the tile is seen.
static func _one_look(rules: Array) -> bool:
	for state in 16:
		var n: int = 0
		for layer in [WorldLayers.Layer.LIVE, WorldLayers.Layer.A2, WorldLayers.Layer.REMEMBERED]:
			if _shows(rules, int(layer), state):
				n += 1
		if n > 1 or ((state & WorldLayers.BIT_LIVE) != 0 and n != 1):
			return false
	return true


func _mask_rule() -> bool:
	var shader: String = _read(SHADER_PATH)
	if shader.is_empty():
		push_error("MASK-RULE: %s did not read" % SHADER_PATH)
		return false
	var consts: Dictionary = _shader_consts(shader)
	if not _consts_match(consts):
		push_error("MASK-RULE: the shader's bits %s are not world_layers.gd's" % consts)
		return false
	# The scanner, shown a sabotaged copy, must say no.
	if _consts_match(_shader_consts(shader.replace("const int LIVE = 1;", "const int LIVE = 2;"))):
		push_error("MASK-RULE: the constant scanner passed a shader whose LIVE bit is 2")
		return false
	var rule_line: String = "if ((state & want) != want || (state & deny) != 0) {"
	var rule_found: bool = false
	for raw in shader.split("\n"):
		if raw.strip_edges() == rule_line:
			rule_found = true
	if not rule_found:
		push_error("MASK-RULE: the shader's discard rule is not `%s`" % rule_line)
		return false
	var layers: String = _read(LAYERS_GD)
	for needle in ["mat.set_shader_parameter(\"want\", int(RULES[layer][0]))", "mat.set_shader_parameter(\"deny\", int(RULES[layer][1]))", "mat.shader = MaskShader"]:
		if layers.find(needle) < 0:
			push_error("MASK-RULE: world_layers.gd's attach no longer has `%s`" % needle)
			return false
	# What each layer means, written out here rather than read back from RULES.
	var L: int = WorldLayers.BIT_LIVE
	var E: int = WorldLayers.BIT_EXPLORED
	var R: int = WorldLayers.BIT_ROOF
	var A: int = WorldLayers.BIT_A2
	for state in 16:
		var expect: Array = [
			(state & L) != 0 and (state & A) == 0,
			(state & L) != 0 and (state & A) != 0,
			(state & E) != 0 and (state & L) == 0,
			(state & R) != 0 and (state & E) == 0,
			(state & R) != 0 and (state & E) != 0,
		]
		for layer in WorldLayers.LAYER_COUNT:
			if WorldLayers.shows(layer, state) != bool(expect[layer]):
				push_error("MASK-RULE: layer %d on state %d shows %s, the layer table says %s" % [layer, state, WorldLayers.shows(layer, state), expect[layer]])
				return false
	if not _one_look(WorldLayers.RULES):
		push_error("MASK-RULE: some tile state shows two ground looks at once, or a seen tile none")
		return false
	var sabotaged: Array = WorldLayers.RULES.duplicate(true)
	sabotaged[WorldLayers.Layer.LIVE] = [L, 0]
	if _one_look(sabotaged):
		push_error("MASK-RULE: the one-look check passed a rule table with LIVE's deny dropped")
		return false
	print("MASK-RULE OK shader bits and discard rule match world_layers.gd; five layers mean what they say; one ground look a tile")
	return true


# --- SOCKET -----------------------------------------------------------------------------------

# A function's body: from its `func` line to the next top-level declaration.
static func _func_body(text: String, name: String) -> String:
	var lines: PackedStringArray = text.split("\n")
	var out: PackedStringArray = []
	var inside: bool = false
	for line in lines:
		if line.begins_with("func %s(" % name):
			inside = true
			continue
		if inside and (line.begins_with("func ") or line.begins_with("static func ") or line.begins_with("var ") or line.begins_with("const ")):
			break
		if inside:
			out.append(line)
	return "\n".join(out)


# Bare draw calls in a body: a CanvasItem draw not through `_pen.` (comment lines ignored).
static func _bare_draws(body: String) -> Array:
	var found: Array = []
	for raw in body.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("#"):
			continue
		for call in DRAW_CALLS:
			var at: int = line.find(call)
			while at >= 0:
				var before: String = line.substr(0, at)
				var is_word: bool = at == 0 or not (line[at - 1] == "_" or line[at - 1].is_valid_identifier())
				if is_word and not before.ends_with("_pen.") and not before.ends_with("texture."):
					found.append(line)
				at = line.find(call, at + 1)
	return found


func _socket() -> bool:
	var src: String = _read(MAIN_GD)
	var draw: String = _func_body(src, "_draw")
	if draw.find("_draw_world()") < 0 or draw.find("_draw_district(") >= 0:
		push_error("SOCKET: _draw must call _draw_world() and never _draw_district(")
		return false
	var callers: Array = []
	var current: String = ""
	for line in src.split("\n"):
		if line.begins_with("func "):
			current = line.substr(5, line.find("(") - 5)
			continue
		if line.strip_edges().begins_with("#"):
			continue
		if line.find("_draw_district(") >= 0 and current != "_draw_district":
			callers.append(current)
	if callers.is_empty() or callers.any(func(c: Variant) -> bool: return String(c) != "_bake_layer"):
		push_error("SOCKET: _draw_district is reached from %s, not from _bake_layer alone" % [callers])
		return false
	var bake: String = _func_body(src, "_bake_layer")
	for needle in ["_pen = pen", "_pen = kept_pen", "camera = CameraUtil.create_camera(", "camera = kept_camera", "_draw_roofs("]:
		if bake.find(needle) < 0:
			push_error("SOCKET: _bake_layer no longer has `%s`" % needle)
			return false
	for helper in BAKED_HELPERS:
		var body: String = _func_body(src, helper)
		if body.is_empty():
			push_error("SOCKET: baked helper %s not found in main.gd" % helper)
			return false
		var bare: Array = _bare_draws(body)
		if not bare.is_empty():
			push_error("SOCKET: %s draws to main's own frame, not the pen: %s" % [helper, bare[0]])
			return false
	# The scanner on fabricated bodies: one bare call caught, the pen and a texture's own draw not.
	var fabricated: String = "\t_pen.draw_rect(rect, col)\n\tdraw_rect(rect, col)\n"
	if _bare_draws(fabricated).size() != 1:
		push_error("SOCKET: the bare-draw scanner missed a bare draw_rect( in a fabricated body")
		return false
	if not _bare_draws("\t_pen.draw_texture_rect_region(t, r, s)\n\ttexture.draw_rect(item, r, false)\n\t# draw_rect(x)\n").is_empty():
		push_error("SOCKET: the bare-draw scanner flagged a pen call, a texture's own draw or a comment")
		return false
	print("SOCKET OK _draw reaches the bake through _draw_world; _draw_district only from _bake_layer; %d baked helpers draw through the pen" % BAKED_HELPERS.size())
	return true


# --- SNOW (a bare WorldLayers) ----------------------------------------------------------------

func _snow() -> bool:
	var layers: RefCounted = WorldLayers.new()
	var parent: RID = RenderingServer.canvas_item_create()
	layers.call("attach", parent)
	var calls: Array = [0]
	var bake := func(_region: Rect2i, _layer: int, _pen: Object) -> void:
		calls[0] = int(calls[0]) + 1
		# A bake that costs something, so the budget has something to cut.
		var until: int = Time.get_ticks_usec() + 400
		while Time.get_ticks_usec() < until:
			pass
	var signature := func(_region: Rect2i) -> int: return 0
	var map_obj := RefCounted.new()
	var ctx: Dictionary = {
		"zoom": 64.0, "offset": Vector2.ZERO, "viewport": Vector2(1280, 720), "background": Color.BLACK,
		"map": map_obj, "content": {}, "seed": 1, "generation": 0, "map_w": 64, "map_h": 64,
		"view": Rect2i(0, 0, 24, 16), "snow": 0.0, "signature": signature, "bake": bake,
	}
	var visible: int = 3 * 2
	# Settle at no snow: the visible chunks, then the ring.
	layers.call("frame", ctx)
	var first: int = int(layers.get("baked_last_frame"))
	for i in SETTLE_FRAMES:
		layers.call("frame", ctx)
		if int(layers.get("baked_last_frame")) == 0:
			break
	var resting: int = int(layers.get("baked_last_frame"))
	var count: int = int(layers.call("chunk_count"))
	ctx["snow"] = 1.0
	layers.call("frame", ctx)
	var step: int = int(layers.get("baked_last_frame"))
	var frames: int = 1
	while int(layers.get("baked_last_frame")) > 0 and frames < SETTLE_FRAMES:
		layers.call("frame", ctx)
		frames += 1
	var settled: int = int(layers.get("baked_last_frame"))
	var stale: int = 0
	for rec in (layers.get("_chunks") as Dictionary).values():
		if int((rec as Dictionary)["snow"]) != int(WorldLayers.SNOW_STEPS):
			stale += 1
	layers.call("detach")
	RenderingServer.free_rid(parent)
	if first < visible:
		push_error("SNOW: the first frame baked %d chunks, the view covers %d" % [first, visible])
		return false
	if resting != 0:
		push_error("SNOW: an unchanged frame still baked %d chunks after %d frames" % [resting, SETTLE_FRAMES])
		return false
	if step < 1 or step >= count:
		push_error("SNOW: a snow step rebaked %d of %d chunks in one frame; the budget wants at least one and not all" % [step, count])
		return false
	if settled != 0 or stale != 0:
		push_error("SNOW: %d frames after the step, %d chunks still bake a frame and %d hold the old snow" % [frames, settled, stale])
		return false
	_report.append("snow step: %d of %d chunks the first frame, settled in %d" % [step, count, frames])
	print("SNOW OK a snow step rebakes %d of %d chunks the first frame and settles in %d frames" % [step, count, frames])
	return true


# --- the scene --------------------------------------------------------------------------------

func _boot() -> Node:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		return null
	# The bench's window: a headless root is 64 px square, which is one chunk of view.
	root.size = Vector2i(1280, 720)
	var main: Node = packed.instantiate()
	root.add_child(main)
	await process_frame
	if main.get("world") == null:
		return null
	main.set_process(false)
	main.call("_enter_state", Session.State.PLAYING)
	main.set("paused", true)
	# One tick, so the observer has a view (vision refreshes inside the step).
	main.get("world").step()
	main.call("_resize_camera")
	await _redraw(main)
	return main


func _redraw(main: Node) -> void:
	(main as CanvasItem).queue_redraw()
	await process_frame
	await process_frame


func _layers(main: Node) -> RefCounted:
	return main.get("_layers") as RefCounted


func _view_chunks(main: Node) -> Rect2i:
	var world: Variant = main.get("world")
	var b: Dictionary = TopDownProjection.visible_bounds(main.get("camera") as Dictionary, 2.0)
	return WorldLayers.chunks_over(floori(float(b["minX"])), floori(float(b["minY"])), ceili(float(b["maxX"])), ceili(float(b["maxY"])), int(world.map_width), int(world.map_height))


# Frames until one bakes nothing; how many it took, or -1.
func _settle(main: Node) -> int:
	for i in SETTLE_FRAMES:
		await _redraw(main)
		if int(_layers(main).get("baked_last_frame")) == 0:
			return i + 1
	return -1


func _baked(main: Node) -> bool:
	var layers: RefCounted = _layers(main)
	if layers == null:
		push_error("BAKED: main has no _layers")
		return false
	var view: Rect2i = _view_chunks(main)
	var missing: Array = []
	for cy in range(view.position.y, view.end.y):
		for cx in range(view.position.x, view.end.x):
			if not bool(layers.call("is_baked", Vector2i(cx, cy))):
				missing.append(Vector2i(cx, cy))
	if not missing.is_empty() or view.get_area() == 0:
		push_error("BAKED: after the first frame %d of %d chunks under the view are unbaked: %s" % [missing.size(), view.get_area(), missing.slice(0, 4)])
		return false
	var took: int = await _settle(main)
	if took < 0:
		push_error("BAKED: %d frames on, a frame with nothing changed still bakes" % SETTLE_FRAMES)
		return false
	var total: int = int(layers.get("baked_total"))
	for i in 3:
		await _redraw(main)
	if int(layers.get("baked_total")) != total:
		push_error("BAKED: three unchanged frames baked %d chunks" % (int(layers.get("baked_total")) - total))
		return false
	# A camera step of one tile stays inside the baked ring: nothing to bake.
	var camera: Dictionary = main.get("camera") as Dictionary
	camera["x"] = float(camera["x"]) + 1.0
	await _redraw(main)
	var stepped: int = int(layers.get("baked_total")) - total
	camera["x"] = float(camera["x"]) - 1.0
	await _redraw(main)
	if stepped != 0:
		push_error("BAKED: a one-tile camera step baked %d chunks" % stepped)
		return false
	_report.append("%d chunks under the view baked the first frame, ring done in %d" % [view.get_area(), took])
	print("BAKED OK %d chunks under the view on the first frame; the ring done in %d frames; unchanged frames and a camera step bake none" % [view.get_area(), took])
	return true


func _sight(main: Node) -> Array:
	var world: Variant = main.get("world")
	var seen: Variant = null if world.vision == null else world.vision.tiles_for(int(world.player))
	var explored: Variant = SimSightings.explored_view(world, int(world.player))
	return [seen, explored]


func _view_tiles(main: Node) -> Rect2i:
	var world: Variant = main.get("world")
	var b: Dictionary = TopDownProjection.visible_bounds(main.get("camera") as Dictionary, 2.0)
	var x0: int = maxi(0, floori(float(b["minX"])))
	var y0: int = maxi(0, floori(float(b["minY"])))
	var x1: int = mini(int(world.map_width) - 1, ceili(float(b["maxX"])))
	var y1: int = mini(int(world.map_height) - 1, ceili(float(b["maxY"])))
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


# A door tile with an indoor tile north of it and open outdoor ground for five tiles south.
func _front_door(main: Node) -> Vector2i:
	var world: Variant = main.get("world")
	var map: Variant = world.tilemap
	if map == null:
		return Vector2i(-1, -1)
	var w: int = int(map.w)
	var h: int = int(map.h)
	for ty in range(1, h - 6):
		for tx in range(w):
			if int(map.tiles[ty * w + tx]) != SimTileMap.Tile.Door or int(map.indoors[(ty - 1) * w + tx]) == 0:
				continue
			var open: bool = true
			for dy in range(1, 6):
				var i: int = (ty + dy) * w + tx
				if int(map.indoors[i]) != 0 or SimTileMap.is_solid(map, tx, ty + dy) or int(map.tiles[i]) != SimTileMap.Tile.Floor:
					open = false
					break
			if open:
				return Vector2i(tx, ty)
	return Vector2i(-1, -1)


# The player put at `at`, one tick stepped so the sight sets follow, the camera centred on them,
# and the bake left to settle.
func _stand(main: Node, at: Vector2) -> void:
	var world: Variant = main.get("world")
	world.components.set_component(int(world.player), "position", {"x": at.x, "y": at.y})
	world.step()
	var camera: Dictionary = main.get("camera") as Dictionary
	camera["x"] = at.x
	camera["y"] = at.y
	await _settle(main)


func _no_leak(main: Node, where: String) -> bool:
	var layers: RefCounted = _layers(main)
	var sight: Array = _sight(main)
	var seen: Variant = sight[0]
	var explored: Variant = sight[1]
	if seen == null:
		return _skip("NO-LEAK %s" % where, "no observer view")
	var view: Rect2i = _view_tiles(main)
	var n_seen: int = 0
	var n_dark: int = 0
	var n_remembered: int = 0
	for ty in range(view.position.y, view.end.y):
		for tx in range(view.position.x, view.end.x):
			var state: int = int(layers.call("state_at", tx, ty))
			var live: bool = bool(seen.has_tile(tx, ty))
			var known: bool = explored != null and bool(explored.has_tile(tx, ty))
			if ((state & WorldLayers.BIT_LIVE) != 0) != live:
				push_error("NO-LEAK: tile (%d, %d) mask LIVE %s, observer has_tile %s" % [tx, ty, (state & WorldLayers.BIT_LIVE) != 0, live])
				return false
			if ((state & WorldLayers.BIT_EXPLORED) != 0) != known:
				push_error("NO-LEAK: tile (%d, %d) mask EXPLORED %s, remembered map %s" % [tx, ty, (state & WorldLayers.BIT_EXPLORED) != 0, known])
				return false
			var looks: int = 0
			for layer in [WorldLayers.Layer.LIVE, WorldLayers.Layer.A2, WorldLayers.Layer.REMEMBERED]:
				if WorldLayers.shows(int(layer), state):
					looks += 1
			if live:
				n_seen += 1
				if looks != 1:
					push_error("NO-LEAK: seen tile (%d, %d) shows %d ground looks" % [tx, ty, looks])
					return false
			elif known:
				n_remembered += 1
				if not WorldLayers.shows(WorldLayers.Layer.REMEMBERED, state) or WorldLayers.shows(WorldLayers.Layer.LIVE, state):
					push_error("NO-LEAK: remembered tile (%d, %d) does not show the remembered look alone" % [tx, ty])
					return false
			else:
				n_dark += 1
				if looks != 0:
					push_error("NO-LEAK: tile (%d, %d) is neither seen nor explored and shows a ground look" % [tx, ty])
					return false
	if n_seen == 0 or n_dark == 0:
		return _skip("NO-LEAK %s" % where, "the view had %d seen and %d dark tiles; both are needed to judge" % [n_seen, n_dark])
	# Off the map is nothing at all.
	if int(layers.call("state_at", -1, -1)) != 0:
		push_error("NO-LEAK: a tile off the map has state %d" % int(layers.call("state_at", -1, -1)))
		return false
	_report.append("mask agrees with sight %s on %d seen, %d remembered, %d dark tiles" % [where, n_seen, n_remembered, n_dark])
	print("NO-LEAK OK %s: %d seen, %d remembered, %d dark tiles in the view, every one masked as the observer sees it" % [where, n_seen, n_remembered, n_dark])
	return true


# The layers of chunk `key` that some tile of it shows, as bits.
static func _needed(layers: RefCounted, key: Vector2i, map_w: int, map_h: int) -> int:
	var bits: int = 0
	var region: Rect2i = WorldLayers.chunk_region(key, map_w, map_h)
	for ty in range(region.position.y, region.end.y):
		for tx in range(region.position.x, region.end.x):
			var state: int = int(layers.call("state_at", tx, ty))
			for layer in WorldLayers.LAYER_COUNT:
				if WorldLayers.shows(layer, state):
					bits |= 1 << layer
	return bits


# A layer some tile needs and the item does not draw, or -1.
static func _cull_breach(needed: int, drawn: int) -> int:
	for layer in WorldLayers.LAYER_COUNT:
		if (needed & (1 << layer)) != 0 and (drawn & (1 << layer)) == 0:
			return layer
	return -1


func _cull(main: Node, where: String) -> bool:
	var world: Variant = main.get("world")
	var layers: RefCounted = _layers(main)
	var view: Rect2i = _view_chunks(main)
	var hidden: int = 0
	var live_chunk := Vector2i(-1, -1)
	for cy in range(view.position.y, view.end.y):
		for cx in range(view.position.x, view.end.x):
			var key := Vector2i(cx, cy)
			var needed: int = _needed(layers, key, int(world.map_width), int(world.map_height))
			var drawn: int = 0
			for layer in WorldLayers.LAYER_COUNT:
				if bool(layers.call("layer_shown", key, layer)):
					drawn |= 1 << layer
				else:
					hidden += 1
			var breach: int = _cull_breach(needed, drawn)
			if breach >= 0:
				push_error("CULL %s: chunk %s hides layer %d, which one of its tiles shows" % [where, key, breach])
				return false
			if (needed & (1 << WorldLayers.Layer.LIVE)) != 0:
				live_chunk = key
	if live_chunk.x < 0:
		return _skip("CULL %s" % where, "no chunk in view has a seen tile")
	# The checker, shown the same chunk with its LIVE item marked hidden, must say no.
	var needed_live: int = _needed(layers, live_chunk, int(world.map_width), int(world.map_height))
	if _cull_breach(needed_live, needed_live & ~(1 << WorldLayers.Layer.LIVE)) != WorldLayers.Layer.LIVE:
		push_error("CULL %s: the checker passed a seen chunk whose LIVE item is hidden" % where)
		return false
	if hidden == 0:
		return _skip("CULL %s" % where, "every layer of every chunk in view is drawn; nothing to judge the cull by")
	_report.append("cull %s hides %d of %d chunk layers" % [where, hidden, view.get_area() * WorldLayers.LAYER_COUNT])
	print("CULL OK %s: %d of %d chunk layers in view hidden, none that a tile shows" % [where, hidden, view.get_area() * WorldLayers.LAYER_COUNT])
	return true


func _roof(main: Node) -> bool:
	var world: Variant = main.get("world")
	var layers: RefCounted = _layers(main)
	var seen: Variant = _sight(main)[0]
	if world.tilemap == null or seen == null:
		return _skip("ROOF", "no tilemap or no observer view")
	var bounds: Dictionary = TopDownProjection.visible_bounds(main.get("camera") as Dictionary, 2.0)
	var chosen: Dictionary = {}
	for t in RoofLook.roof_tiles(world.tilemap, seen, bounds, main.call("_player_tile") as Vector2i):
		chosen[t] = true
	if chosen.is_empty():
		return _skip("ROOF", "the roof rule chose no tile in this view")
	var view: Rect2i = _view_tiles(main)
	var off: int = 0
	for ty in range(view.position.y, view.end.y):
		for tx in range(view.position.x, view.end.x):
			var roofed: bool = (int(layers.call("state_at", tx, ty)) & WorldLayers.BIT_ROOF) != 0
			if roofed != chosen.has(Vector2i(tx, ty)):
				push_error("ROOF: tile (%d, %d) mask ROOF %s, roof rule %s" % [tx, ty, roofed, chosen.has(Vector2i(tx, ty))])
				return false
			if not roofed:
				off += 1
	if off == 0:
		return _skip("ROOF", "every tile in view is roofed; no negative to judge")
	_report.append("ROOF bit on the %d tiles the roof rule chose" % chosen.size())
	print("ROOF OK the ROOF bit is on the %d tiles RoofLook.roof_tiles chose and off on the other %d" % [chosen.size(), off])
	return true


# --- REBAKE -----------------------------------------------------------------------------------

func _items_of(layers: RefCounted, chunk: Vector2i) -> Array:
	var rec: Variant = (layers.get("_chunks") as Dictionary).get(chunk)
	return [] if not (rec is Dictionary) else ((rec as Dictionary)["items"] as Array).duplicate()


func _rebake(main: Node) -> bool:
	var world: Variant = main.get("world")
	var layers: RefCounted = _layers(main)
	var map: Variant = world.tilemap
	if map == null:
		return _skip("REBAKE", "no tilemap")
	var view: Rect2i = _view_chunks(main)
	if view.size.x < 3:
		return _skip("REBAKE", "the view is under three chunks wide")
	# A tile in the middle of a chunk near the view's left edge, so its own chunk alone covers it
	# and its apron; and a chunk two to the right of it, out of reach.
	var near := Vector2i(view.position.x, view.position.y + view.size.y / 2)
	var far := near + Vector2i(2, 0)
	var tx: int = near.x * WorldLayers.CHUNK + WorldLayers.CHUNK / 2
	var ty: int = near.y * WorldLayers.CHUNK + WorldLayers.CHUNK / 2
	var i: int = ty * int(map.w) + tx
	if not (await _settle(main) >= 0):
		push_error("REBAKE: the bake did not settle before the lane")
		return false
	var total: int = int(layers.get("baked_total"))
	# The negative first: a generation bump with nothing changed.
	world.invalidateMap()
	await _redraw(main)
	if int(layers.get("baked_total")) != total:
		push_error("REBAKE: invalidateMap with no change rebaked %d chunks" % (int(layers.get("baked_total")) - total))
		return false
	var near_before: Array = _items_of(layers, near)
	var far_before: Array = _items_of(layers, far)
	var was: int = int(map.surfaces[i])
	map.surfaces[i] = (was + 1) % 4
	world.invalidateMap()
	await _redraw(main)
	var rebaked: int = int(layers.get("baked_total")) - total
	var near_after: Array = _items_of(layers, near)
	var far_after: Array = _items_of(layers, far)
	map.surfaces[i] = was
	world.invalidateMap()
	await _redraw(main)
	if rebaked != 1 or near_after == near_before or near_after.is_empty():
		push_error("REBAKE: a ground change at (%d, %d) rebaked %d chunks (wanted its own chunk alone)" % [tx, ty, rebaked])
		return false
	if far_after != far_before or far_after.is_empty():
		push_error("REBAKE: a ground change two chunks away rebaked chunk %s" % far)
		return false
	# Zoom: everything goes.
	var camera: Dictionary = main.get("camera") as Dictionary
	var zoom: float = float(camera["zoom"])
	total = int(layers.get("baked_total"))
	camera["zoom"] = zoom / 2.0
	main.call("_resize_camera")
	await _redraw(main)
	var zoomed_near: Array = _items_of(layers, near)
	var zoom_baked: int = int(layers.get("baked_total")) - total
	camera["zoom"] = zoom
	main.call("_resize_camera")
	await _redraw(main)
	if zoom_baked < view.get_area() or zoomed_near == _items_of(layers, near):
		push_error("REBAKE: a zoom change rebaked %d chunks, fewer than the %d under the old view" % [zoom_baked, view.get_area()])
		return false
	# Content: a copy of the tree is a different tree, and everything goes.
	await _settle(main)
	var before: Array = _items_of(layers, near)
	var content: Variant = world.content
	world.content = (content as Dictionary).duplicate() if content is Dictionary else content
	await _redraw(main)
	var swapped: Array = _items_of(layers, near)
	world.content = content
	await _redraw(main)
	if not (content is Dictionary):
		return _skip("REBAKE", "content is not a Dictionary; the content swap was not judged")
	if swapped == before or swapped.is_empty():
		push_error("REBAKE: swapping the content tree left chunk %s's bake in place" % near)
		return false
	_report.append("a tile change rebakes 1 chunk, a zoom change %d" % zoom_baked)
	print("REBAKE OK a ground change rebakes its own chunk and not one two away; a bare invalidateMap rebakes none; zoom rebakes %d, a content swap everything" % zoom_baked)
	return true
