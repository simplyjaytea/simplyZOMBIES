extends SceneTree
# The afterimage and the remembered map -- slice 2 of the four QOL slices, "sight memory". A body
# that leaves the player's cone used to vanish the same frame and become an 8 px dot fading in
# three seconds, while the sim remembered it for two minutes and every tile outside the shadowcast
# cut to black. This is the gate for the fix: a frozen picture where the body last stood, and a
# dimmed street where the observer has walked before.
#
# Boots `res://presentation/main.tscn` the way check_play.gd does -- Enter past the title,
# Escape past the legend, the scene's own `_process` off so this gate owns the clock -- because
# `_last_look` is written by `_draw_entities` and the composite tile look is drawn by
# `_draw_district`, and neither runs headless without a real CanvasItem draw pass.
#
# Lanes, each with its own true negative:
#   CACHE      a Focal body enters `_last_look`; a body behind the player, Peripheral at best,
#              never does
#   AFTERIMAGE the pure fade (afterimage_alpha) has a ceiling near 1 and a floor at exactly 0; a
#              body that leaves view keeps a remembered record and the frame still finishes
#              drawing; textual: `_draw_afterimages` reads the sim's memory and never a live
#              position, proved on a fabricated body first
#   MAP        a tile walked away from stays known (`SimSightings.knows_tile`) after it drops out
#              of `seen`, the frame still draws it without error, and the tile loop's own text
#              reaches `Palette.remembered(` with its escape hatch (`continue`) intact
#   NO-BODIES  the ground-item, prop and body branches still gate on Focal/Unseen exactly as
#              before -- nothing here widened who gets to stand on a remembered tile
#   STOCKPILE  the stockpile on the street (presentation/stockpile_look.gd, slice S2 of the
#              stockpile plan), on fabricated sight sets: never on an unexplored tile, a remembered
#              tile pulled through Palette.remembered and a seen one not, a roofed tile absent with
#              the brush up or down, the rim on outer sides only with the concave notch, the rest
#              look quieter than the marking look, the drag preview only on explored unroofed
#              tiles, the rim's contrast at least 3:1 on every ground the district has, in its own
#              colours and under the noon day grade (the measure proved on a rim that matches its
#              ground first, the graded measure on the grade lowering some rim); by firelight (NIGHT_POOL) the wash at
#              least as plain as the day wash at noon on every ground, at rest and marking, which the
#              day alphas fail; textual: `_draw_world` reaches
#              `_draw_stockpile`, which paints StockpileLook's cells over `SimStockpile.tiles` (read
#              again only when `SimStockpile.signature` moves, and batched again only when the zone,
#              the tick, the brush, the zoom or the roof moves) with the explored set and the roof,
#              batched (`StockpileLook.batch`: a row of one wash is one fill, a change of wash
#              breaks it)
#
# A lane with no data to judge says so and skips (`_skip`), never passes quietly.

const SCENE_PATH: String = "res://presentation/main.tscn"
const MAIN_GD: String = "res://presentation/main.gd"

const SimVisibility = preload("res://sim/vision/visibility.gd")
const SimSightings = preload("res://sim/modules/sightings.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const MainScript = preload("res://presentation/main.gd")
const WorldLayers = preload("res://presentation/world_layers.gd")

const TICK_SECONDS: float = 1.0 / 20.0
# How far off the player the fixture places a test body -- close enough that a district generated
# around the boot spot is very unlikely to wall it in from every direction at once.
const SPOT_METRES: float = 2.0

var _skips: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _the_pure_fade_has_a_ceiling_near_one_and_a_floor_at_zero() and ok
	ok = _the_afterimage_reads_remembered_never_a_live_position() and ok
	ok = _the_entity_branches_still_gate_on_focal_and_unseen() and ok
	ok = _the_stockpile_draws_on_known_ground_and_dims_with_it() and ok

	var main: Node = await _boot()
	if main == null:
		push_error("MEMORY_LOOK_FAIL the scene did not boot")
		quit(1)
		return

	var world: Variant = main.get("world")
	var spot: Dictionary = _focal_spot(world, SPOT_METRES)
	if spot.is_empty():
		main.queue_free()
		await process_frame
		ok = _skip("CACHE", "no direction near the boot spot was Focal -- nothing to place a body in") and ok
		ok = _skip("AFTERIMAGE", "no Focal spot to build the fixture from") and ok
		ok = _skip("MAP", "no Focal spot to build the fixture from") and ok
	else:
		var rng: Variant = world.rng.stream("shambler")
		var facing: float = float(spot["angle"])
		var focal_pos: Vector2 = spot["pos"] as Vector2
		var opposite_pos: Vector2 = _pos_of(world, int(world.player)) - Vector2(cos(facing), sin(facing)) * SPOT_METRES

		var cache_ok: bool = await _cache_holds_a_focal_body_and_not_a_peripheral_one(main, world, rng, focal_pos, opposite_pos)
		ok = cache_ok and ok
		var after_ok: bool = await _a_body_that_leaves_view_keeps_an_afterimage(main, world, rng, focal_pos, opposite_pos)
		ok = after_ok and ok
		var map_ok: bool = await _the_remembered_map_stays_known_after_walking_away(main, world, focal_pos)
		ok = map_ok and ok
		main.queue_free()
		await process_frame

	if ok:
		var skipped: String = "no lane skipped" if _skips.is_empty() else "skipped: %s" % ", ".join(PackedStringArray(_skips))
		print("MEMORY_LOOK_OK a Focal body caches its look and a Peripheral one does not, the afterimage fades over the sim's own FRESH_TICKS band and reads only SimSightings.remembered, a walked-away tile stays known and the tile loop reaches Palette.remembered( with its continue intact, the ground-item/prop/body branches still gate on Focal and Unseen, and the stockpile paints only known unroofed ground, dimmed with it, its rim at least 3:1 on every ground (%s)" % skipped)
		quit(0)
	else:
		push_error("MEMORY_LOOK_FAIL")
		quit(1)


func _skip(lane: String, why: String) -> bool:
	print("%s SKIP %s" % [lane, why])
	_skips.append("%s (%s)" % [lane, why])
	return true


# --- the harness -- check_play.gd's _boot_scene/_boot, unchanged in shape -----------------------

func _tap(code: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.physical_keycode = code
	down.pressed = true
	root.push_input(down)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	root.push_input(up)


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
	await process_frame
	if main.get("world") == null:
		push_error("the main scene did not construct a world")
		main.queue_free()
		return null
	main.set_process(false)
	main.set("accumulator", 0.0)
	return main


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
	main.set("accumulator", 0.0)
	return main


func _redraw(main: Node) -> void:
	main.call("queue_redraw")
	await process_frame
	await process_frame


func _pos_of(world: Variant, ent: int) -> Vector2:
	var p: Variant = world.components.get_component(ent, "position")
	if not p is Dictionary:
		return Vector2.ZERO
	return Vector2(float((p as Dictionary)["x"]), float((p as Dictionary)["y"]))


# A direction the player's own eyes call Focal at `dist` metres, found rather than assumed: the
# boot spot is generated content, and the alternative -- picking one compass point and hoping
# nothing walls it in -- is exactly the fragility CLAUDE.md's traps section is full of. Returns
# {} when every cardinal and diagonal is blocked, which the caller reads as "nothing to judge".
func _focal_spot(world: Variant, dist: float) -> Dictionary:
	var p: Vector2 = _pos_of(world, int(world.player))
	var angles: Array[float] = [0.0, PI / 2.0, PI, -PI / 2.0, PI / 4.0, -PI / 4.0, 3.0 * PI / 4.0, -3.0 * PI / 4.0]
	for ang in angles:
		world.components.set_component(int(world.player), "facing", {"radians": ang})
		world.step()
		var cand: Vector2 = p + Vector2(cos(ang), sin(ang)) * dist
		if int(world.vision.call("detail", int(world.player), cand.x, cand.y)) == SimVisibility.Detail.Focal:
			return {"angle": ang, "pos": cand}
	return {}


# --- CACHE ---------------------------------------------------------------------------------

func _cache_holds_a_focal_body_and_not_a_peripheral_one(main: Node, world: Variant, rng: Variant, focal_pos: Vector2, opposite_pos: Vector2) -> bool:
	var ahead: int = SimRoster.spawn_zombie(world, focal_pos.x, focal_pos.y, SimRoster.TYPE_SHAMBLER, rng)
	var behind: int = SimRoster.spawn_zombie(world, opposite_pos.x, opposite_pos.y, SimRoster.TYPE_SHAMBLER, rng)
	world.events.drain()
	world.step()
	await _redraw(main)
	var cache: Dictionary = main.get("_last_look") as Dictionary
	if not cache.has(ahead):
		push_error("CACHE: a Focal shambler in front of the player never entered _last_look")
		return false
	if cache.has(behind):
		push_error("CACHE: a shambler directly behind the player (Peripheral at best) entered _last_look")
		return false
	print("CACHE OK a Focal body (%d) is cached, a body behind the player (%d) is not" % [ahead, behind])
	return true


# --- AFTERIMAGE ------------------------------------------------------------------------------

func _the_pure_fade_has_a_ceiling_near_one_and_a_floor_at_zero() -> bool:
	var near_one: float = float(MainScript.afterimage_alpha(1))
	if near_one <= 0.9 or near_one >= 1.0:
		push_error("AFTERIMAGE: afterimage_alpha(1) is %f, not close under 1.0" % near_one)
		return false
	var at_horizon: float = float(MainScript.afterimage_alpha(SimSightings.FRESH_TICKS))
	if at_horizon != 0.0:
		push_error("AFTERIMAGE: afterimage_alpha(FRESH_TICKS) is %f, not exactly 0.0" % at_horizon)
		return false
	# The negative: a mid-band age gives something strictly between the two ends, or the curve is
	# a step function rather than a fade.
	var mid: float = float(MainScript.afterimage_alpha(SimSightings.FRESH_TICKS / 2))
	if mid <= 0.0 or mid >= 1.0:
		push_error("AFTERIMAGE: afterimage_alpha(FRESH_TICKS / 2) is %f, not strictly between 0 and 1" % mid)
		return false
	if float(MainScript.afterimage_alpha(0)) != 0.0 or float(MainScript.afterimage_alpha(-1)) != 0.0:
		push_error("AFTERIMAGE: afterimage_alpha is not 0 at age 0 or a negative age")
		return false
	print("AFTERIMAGE OK afterimage_alpha(1)=%.3f, midpoint=%.3f, afterimage_alpha(FRESH_TICKS)=0.0" % [near_one, mid])
	return true


func _a_body_that_leaves_view_keeps_an_afterimage(main: Node, world: Variant, rng: Variant, focal_pos: Vector2, opposite_pos: Vector2) -> bool:
	var ent: int = SimRoster.spawn_zombie(world, focal_pos.x, focal_pos.y, SimRoster.TYPE_SHAMBLER, rng)
	world.events.drain()
	world.step()
	await _redraw(main)
	if not (main.get("_last_look") as Dictionary).has(ent):
		push_error("AFTERIMAGE: the fixture body was never cached Focal -- nothing to judge once it leaves")
		return false

	# Out of view: the same point CACHE proved Unseen from this facing.
	world.components.set_component(ent, "position", {"x": opposite_pos.x, "y": opposite_pos.y})
	world.step()
	var row: Variant = SimSightings.recall(world, int(world.player), ent)
	if row == null:
		push_error("AFTERIMAGE: the body was forgotten the instant it left view -- memory, not deletion")
		return false
	if int((row as Dictionary)["age"]) <= 0:
		push_error("AFTERIMAGE: the remembered record has no age yet -- the control proves nothing")
		return false

	var before: int = int(main.get("_drew_tick"))
	await _redraw(main)
	var after: int = int(main.get("_drew_tick"))
	if after == before:
		push_error("AFTERIMAGE: the frame with an afterimage on screen never finished drawing (stuck at tick %d)" % before)
		return false
	print("AFTERIMAGE OK the body (%d) is still remembered at age %d once out of view, and the frame carrying its afterimage finished drawing (tick %d)" % [ent, int((row as Dictionary)["age"]), after])
	return true


func _the_afterimage_reads_remembered_never_a_live_position() -> bool:
	# Proved on fabricated lines first: a scanner that cannot find its own needle, or cannot find
	# the forbidden one when it is there, cannot fail on the real function either.
	if not "\tfor row in SimSightings.remembered(world, int(world.player)):\n".contains("SimSightings.remembered("):
		push_error("AFTERIMAGE-READER: the scanner cannot find its own needle in a fabricated line")
		return false
	if not "\tvar there: Variant = world.components.get_component(int(m[\"entity\"]), \"position\")\n".contains("get_component("):
		push_error("AFTERIMAGE-READER: the scanner cannot find the forbidden call in a fabricated line that carries it")
		return false

	var body: String = _function_body(MAIN_GD, "_draw_afterimages")
	if body.is_empty():
		push_error("AFTERIMAGE-READER: could not read _draw_afterimages out of %s" % MAIN_GD)
		return false
	if not body.contains("SimSightings.remembered("):
		push_error("AFTERIMAGE-READER: _draw_afterimages does not read SimSightings.remembered -- the picture would not be the sim's memory")
		return false
	if body.contains("get_component("):
		push_error("AFTERIMAGE-READER: _draw_afterimages reads a live component -- the afterimage would follow a body rather than remember where it was")
		return false
	print("AFTERIMAGE-READER OK _draw_afterimages reads SimSightings.remembered( and no get_component(")
	return true


# --- MAP -----------------------------------------------------------------------------------

func _the_remembered_map_stays_known_after_walking_away(main: Node, world: Variant, focal_pos: Vector2) -> bool:
	var tx: int = floori(focal_pos.x)
	var ty: int = floori(focal_pos.y)
	if not SimSightings.knows_tile(world, int(world.player), tx, ty):
		push_error("MAP: the tile a moment ago was Focal at is not marked explored")
		return false

	# Walk far enough away that the tile drops out of the cone -- any movement recasts the
	# player's own (non-lit-target) shadowcast. Under SimVisibility.STAGGER_PLAYER_CAST that
	# recast lands one tick after the step rather than on it, so the control steps twice.
	var far: Vector2 = _pos_of(world, int(world.player)) - Vector2(200.0, 200.0)
	world.components.set_component(int(world.player), "position", {"x": clampf(far.x, 1.0, float(world.map_width) - 2.0), "y": clampf(far.y, 1.0, float(world.map_height) - 2.0)})
	world.step()
	world.step()
	var seen: Variant = world.vision.tiles_for(int(world.player))
	if seen != null and bool((seen as Object).call("has_tile", tx, ty)):
		push_error("MAP: the tile is still in the current cone after walking away -- the control proves nothing")
		return false
	if not SimSightings.knows_tile(world, int(world.player), tx, ty):
		push_error("MAP: a tile explored a moment ago was forgotten once the player walked away")
		return false

	var before: int = int(main.get("_drew_tick"))
	await _redraw(main)
	var after: int = int(main.get("_drew_tick"))
	if after == before:
		push_error("MAP: the frame drawing a remembered, out-of-cone tile never finished (stuck at tick %d)" % before)
		return false

	# Textual: the tile loop reaches Palette.remembered( with its escape hatch intact. Proved on a
	# fabricated body first -- CLAUDE.md's check_m2_comfort lesson, and check_wrecks.gd's
	# _low_arms precedent for reading the arm that actually draws rather than the first match.
	var fabricated_has: String = "\t\t\tif remembered:\n\t\t\t\tcol = Palette.remembered(col)\n\t\t\tmatch tile:\n"
	var fabricated_missing: String = "\t\t\tmatch tile:\n"
	if not fabricated_has.contains("Palette.remembered("):
		push_error("MAP-READER: the scanner cannot find its own needle in a fabricated body that has it")
		return false
	if fabricated_missing.contains("Palette.remembered("):
		push_error("MAP-READER: the scanner found the needle in a fabricated body that does not have it")
		return false
	var district: String = _function_body(MAIN_GD, "_draw_district")
	if district.is_empty():
		push_error("MAP-READER: could not read _draw_district out of %s" % MAIN_GD)
		return false
	if not district.contains("Palette.remembered("):
		push_error("MAP-READER: _draw_district never reaches Palette.remembered( -- a remembered tile would draw exactly as an unseen one")
		return false
	# The escape hatch for a tile that is neither seen nor explored left the tile loop when the world
	# was baked (presentation/world_layers.gd): every tile's looks are baked, and the mask shows none
	# of them on a tile with neither bit. Asked of the mask's own rule, both ways -- a remembered
	# tile shows the remembered layer and only it, a seen one the live layer, and a tile that is
	# neither shows no tile layer at all. The loop keeps one `continue`, the A2 pass's skip of a
	# tile no wall module can stand on.
	if district.count("continue") != 1:
		push_error("MAP-READER: _draw_district holds %d `continue` statements in its tile loop, not the A2 pass's one skip" % district.count("continue"))
		return false
	var tile_layers: Array[int] = [WorldLayers.Layer.LIVE, WorldLayers.Layer.A2, WorldLayers.Layer.REMEMBERED]
	for layer in tile_layers:
		if WorldLayers.shows(layer, 0):
			push_error("MAP-READER: the mask shows tile layer %d on a tile neither seen nor explored -- a tile never cast would be drawn" % layer)
			return false
	if not WorldLayers.shows(WorldLayers.Layer.REMEMBERED, WorldLayers.BIT_EXPLORED) or WorldLayers.shows(WorldLayers.Layer.LIVE, WorldLayers.BIT_EXPLORED):
		push_error("MAP-READER: a remembered tile does not show the remembered layer alone")
		return false
	if not WorldLayers.shows(WorldLayers.Layer.LIVE, WorldLayers.BIT_LIVE | WorldLayers.BIT_EXPLORED) or WorldLayers.shows(WorldLayers.Layer.REMEMBERED, WorldLayers.BIT_LIVE | WorldLayers.BIT_EXPLORED):
		push_error("MAP-READER: a seen tile does not show the live layer alone")
		return false
	print("MAP OK a tile explored a moment ago stays known after walking away, the frame carrying it finished drawing (tick %d), the tile loop reaches Palette.remembered(, and the mask shows the remembered layer on a remembered tile, the live one on a seen tile and no tile layer on a tile never cast" % after)
	return true


# --- NO-BODIES -------------------------------------------------------------------------------

func _the_entity_branches_still_gate_on_focal_and_unseen() -> bool:
	var entities: String = _function_body(MAIN_GD, "_draw_entities")
	if entities.is_empty():
		push_error("NO-BODIES: could not read _draw_entities out of %s" % MAIN_GD)
		return false
	if not entities.contains("SimVisibility.Detail.Unseen"):
		push_error("NO-BODIES: _draw_entities no longer bails a body on Detail.Unseen")
		return false
	if not entities.contains("!= SimVisibility.Detail.Focal"):
		push_error("NO-BODIES: the ground-item branch no longer requires Detail.Focal")
		return false

	var props: String = _function_body(MAIN_GD, "_draw_props")
	if props.is_empty():
		push_error("NO-BODIES: could not read _draw_props out of %s" % MAIN_GD)
		return false
	if not props.contains("(seen as Object).call(\"has_tile\""):
		push_error("NO-BODIES: _draw_props no longer gates on the observer's own seen set")
		return false
	if props.contains("explored") or props.contains("CompositeSeen") or props.contains("remembered"):
		push_error("NO-BODIES: _draw_props widened to the remembered map -- a prop would stand on a tile nobody can currently see")
		return false
	print("NO-BODIES OK _draw_entities still bails a body on Unseen and requires Focal for a ground item; _draw_props still gates on seen alone")
	return true


# The source text of one function, from its `func` line to the next top-level `func`. Same reader
# check_light_look.gd, check_topdown.gd and check_camera.gd already use.
func _function_body(path: String, name: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var lines: PackedStringArray = f.get_as_text().split("\n")
	var out: String = ""
	var inside: bool = false
	for line in lines:
		if line.begins_with("func %s(" % name):
			inside = true
			continue
		if inside and line.begins_with("func "):
			break
		if inside:
			out += line + "\n"
	return out


# --- STOCKPILE --------------------------------------------------------------------------------

const StockpileLook = preload("res://presentation/stockpile_look.gd")
const Palette = preload("res://presentation/palette.gd")
const DayGrade = preload("res://presentation/day_grade.gd")


# A sight set the fixture writes by hand: anything with `has_tile`, which is all the look asks of
# the sim's own two.
class FakeTiles:
	extends RefCounted
	var tiles: Dictionary = {}
	func _init(list: Array) -> void:
		for t in list:
			tiles[t as Vector2i] = true
	func has_tile(tx: int, ty: int) -> bool:
		return tiles.has(Vector2i(tx, ty))


# The grounds the district draws a rim on. COLOURS' own entries, so a regrade of a ground is judged
# against the rim the day it lands.
const RIM_GROUNDS: Array[String] = ["floor", "dirt", "grass", "undergrowth", "rubble", "indoorFloor", "sidewalk"]
const RIM_CONTRAST: float = 3.0
# How far the night pass darkens the ground inside a campfire's pool, as a share of its noon colour:
# the darkest channel of the board floor in the pool in the night_lights review shot is about 0.55 of
# the same floor at noon (the red channel keeps more, up to 0.9, for the fire's warmth). A flat
# multiply is the model, and the darkest share is the hard case for a wash to stay visible.
const NIGHT_POOL: float = 0.55


# The wash over `ground` against the bare ground, both darkened by `light` (1 at noon).
func _wash_contrast(alpha: float, ground: Color, light: float) -> float:
	var wash: Color = Palette.STOCKPILE_WASH
	wash.a = alpha
	var top: Color = StockpileLook.over(wash, ground)
	return StockpileLook.contrast(Color(top.r * light, top.g * light, top.b * light), Color(ground.r * light, ground.g * light, ground.b * light))


func _cell_at(cells: Array[Dictionary], t: Vector2i) -> Dictionary:
	for c in cells:
		if (c["tile"] as Vector2i) == t:
			return c
	return {}


# The better of the tape and its shadow against the ground beside the zone: the pair reads where
# either does.
func _rim_contrast(tape: Color, shadow: Color, ground: Color) -> float:
	return maxf(StockpileLook.contrast(StockpileLook.over(tape, ground), ground), StockpileLook.contrast(StockpileLook.over(shadow, ground), ground))


# The same pair after the noon grade: the ground and the rim over it both graded at full weight, as
# the shader hands them back.
func _rim_contrast_graded(tape: Color, shadow: Color, ground: Color) -> float:
	var g: Color = DayGrade.grade(ground, 1.0)
	return maxf(StockpileLook.contrast(DayGrade.grade(StockpileLook.over(tape, ground), 1.0), g), StockpileLook.contrast(DayGrade.grade(StockpileLook.over(shadow, ground), 1.0), g))


func _the_stockpile_draws_on_known_ground_and_dims_with_it() -> bool:
	var lane: String = "STOCKPILE"
	var ok: bool = true
	# A 3x3 patch at (10,10)-(12,12) with one more tile east of its bottom-right, (13,12): that makes
	# (12,12) a concave tile -- its north (12,11) and east (13,12) are in the zone and its north-east
	# (13,11) is not -- and leaves (11,11) the patch's middle.
	var zone: Array[Vector2i] = []
	for ty in range(10, 13):
		for tx in range(10, 13):
			zone.append(Vector2i(tx, ty))
	zone.append(Vector2i(13, 12))
	var unexplored := Vector2i(10, 10)
	var remembered := Vector2i(11, 10)
	var roofed := Vector2i(12, 10)
	var explored_list: Array = zone.duplicate()
	explored_list.erase(unexplored)
	var explored := FakeTiles.new(explored_list)
	var seen_list: Array = explored_list.duplicate()
	seen_list.erase(remembered)
	var seen := FakeTiles.new(seen_list)
	var view := Rect2i(0, 0, 64, 64)
	var rest: Array[Dictionary] = StockpileLook.cells(zone, seen, explored, [roofed], false, view)
	var marking: Array[Dictionary] = StockpileLook.cells(zone, seen, explored, [roofed], true, view)
	# Explored: an unexplored zone tile is absent, an explored one present; nothing at all without a set.
	if not _cell_at(rest, unexplored).is_empty() or not _cell_at(marking, unexplored).is_empty():
		push_error("%s: the stockpile painted %s, which the player has never seen" % [lane, str(unexplored)])
		ok = false
	if _cell_at(rest, Vector2i(11, 11)).is_empty():
		push_error("%s: a seen zone tile painted nothing, so the absence above proves nothing" % lane)
		ok = false
	if not StockpileLook.cells(zone, seen, null, [], false, view).is_empty():
		push_error("%s: with no explored set the stockpile still painted" % lane)
		ok = false
	# Off the screen: a zone tile outside the view is not painted.
	if not StockpileLook.cells(zone, seen, explored, [], false, Rect2i(0, 0, 4, 4)).is_empty():
		push_error("%s: the stockpile painted tiles outside the view" % lane)
		ok = false
	# Dim: the remembered tile wears Palette.remembered of the seen tile's colours, and they differ.
	var live_c: Dictionary = _cell_at(rest, Vector2i(11, 11))
	var mem_c: Dictionary = _cell_at(rest, remembered)
	if mem_c.is_empty() or bool(mem_c["live"]) or not bool(live_c.get("live", false)):
		push_error("%s: the remembered zone tile is missing or reads as seen" % lane)
		ok = false
	elif (mem_c["wash"] as Color) != Palette.remembered(live_c["wash"] as Color) or (mem_c["tape"] as Color) != Palette.remembered(live_c["tape"] as Color):
		push_error("%s: the remembered zone tile is not pulled through Palette.remembered" % lane)
		ok = false
	elif (mem_c["wash"] as Color) == (live_c["wash"] as Color):
		push_error("%s: the remembered wash equals the seen one; the dim is a dead socket" % lane)
		ok = false
	# Roof: absent with the brush up and down; its neighbour present.
	if not _cell_at(rest, roofed).is_empty() or not _cell_at(marking, roofed).is_empty():
		push_error("%s: the stockpile painted over a roof" % lane)
		ok = false
	if _cell_at(StockpileLook.cells(zone, seen, explored, [], false, view), roofed).is_empty():
		push_error("%s: the roofed tile is absent even with no roof, so the roof proves nothing" % lane)
		ok = false
	# Edges: the patch's middle has none, a corner has its two outer sides, the concave tile its notch.
	var mid: Dictionary = _cell_at(rest, Vector2i(11, 11))
	var corner: Dictionary = _cell_at(rest, Vector2i(10, 12))
	var concave: Dictionary = _cell_at(rest, Vector2i(12, 12))
	if int(mid.get("edges", -1)) != 0 or int(mid.get("corners", -1)) != 0:
		push_error("%s: the middle of the patch carries a rim (edges %d) -- a seam inside the zone" % [lane, int(mid.get("edges", -1))])
		ok = false
	if int(corner.get("edges", 0)) != (StockpileLook.S | StockpileLook.W):
		push_error("%s: the south-west corner's rim is %d, not its south and west sides" % [lane, int(corner.get("edges", 0))])
		ok = false
	if int(concave.get("edges", 0)) != StockpileLook.S or int(concave.get("corners", 0)) != StockpileLook.NE:
		push_error("%s: the concave tile carries edges %d and corners %d, not south and the north-east notch" % [lane, int(concave.get("edges", 0)), int(concave.get("corners", 0))])
		ok = false
	# Paint: a tile with no outer side paints its wash and nothing else; one with a side paints tape;
	# a row of tiles in one wash is one fill, and a change of wash along the row breaks it.
	var mid_paint: Dictionary = StockpileLook.batch([mid], Vector2.ZERO, 64.0, 2.0)
	if (mid_paint["fills"] as Array).size() != 1 or not (mid_paint["lines"] as Dictionary).is_empty():
		push_error("%s: the middle tile paints more than its wash" % lane)
		ok = false
	if (StockpileLook.batch([corner], Vector2.ZERO, 64.0, 2.0)["lines"] as Dictionary).is_empty():
		push_error("%s: the corner tile paints no tape" % lane)
		ok = false
	var row: Array[Dictionary] = [_cell_at(rest, Vector2i(10, 11)), mid, _cell_at(rest, Vector2i(12, 11))]
	var row_fills: Array = StockpileLook.batch(row, Vector2.ZERO, 64.0, 2.0)["fills"]
	if row_fills.size() != 1 or ((row_fills[0] as Array)[0] as Rect2) != Rect2(640.0, 704.0, 192.0, 64.0):
		push_error("%s: a row of three tiles in one wash painted %d fills, not one rect over all three" % [lane, row_fills.size()])
		ok = false
	var odd: Dictionary = (row[2] as Dictionary).duplicate()
	odd["wash"] = Color(1, 0, 0, 0.5)
	if (StockpileLook.batch([row[0], row[1], odd], Vector2.ZERO, 64.0, 2.0)["fills"] as Array).size() != 2:
		push_error("%s: a tile of another wash merged into its neighbour's fill" % lane)
		ok = false
	# The kept shape is what draws: cells reads the geometry it is handed instead of rebuilding it.
	var kept: Dictionary = StockpileLook.geometry(zone)
	kept[Vector2i(11, 11)] = Vector2i(StockpileLook.N, 0)
	if int(_cell_at(StockpileLook.cells(zone, seen, explored, [], false, view, kept), Vector2i(11, 11)).get("edges", 0)) != StockpileLook.N:
		push_error("%s: cells ignored the geometry it was handed, so main.gd's kept shape is a dead socket" % lane)
		ok = false
	# The state key main.gd re-batches by: the same sight gives the same bytes, and a tile coming
	# into sight, or going under a roof, changes them.
	var st: PackedByteArray = StockpileLook.states(zone, seen, explored, [roofed])
	if st != StockpileLook.states(zone, seen, explored, [roofed]):
		push_error("%s: the zone's state bytes differ for the same sight" % lane)
		ok = false
	if st == StockpileLook.states(zone, explored, explored, [roofed]) or st == StockpileLook.states(zone, seen, explored, []):
		push_error("%s: the zone's state bytes did not move when a tile came into sight or a roof lifted, so a kept batch would go stale" % lane)
		ok = false
	# Quieter at rest.
	var rest_c: Dictionary = _cell_at(rest, Vector2i(11, 11))
	var mark_c: Dictionary = _cell_at(marking, Vector2i(11, 11))
	if not ((rest_c["wash"] as Color).a < (mark_c["wash"] as Color).a and (rest_c["tape"] as Color).a < (mark_c["tape"] as Color).a):
		push_error("%s: the rest look is not quieter than the marking look" % lane)
		ok = false
	# Preview: only on explored, unroofed tiles.
	var pv: Array[Dictionary] = StockpileLook.preview_cells([unexplored, roofed, Vector2i(11, 11)], true, explored, [roofed])
	if pv.size() != 1 or (pv[0]["tile"] as Vector2i) != Vector2i(11, 11):
		push_error("%s: the drag preview painted %s, not the one explored unroofed tile" % [lane, str(pv.map(func(c: Dictionary) -> Vector2i: return c["tile"]))])
		ok = false
	if bool(pv[0].get("dashed", true)) if not pv.is_empty() else true:
		push_error("%s: the preview's rim is laid in strips like a zone already made" % lane)
		ok = false
	# Contrast: the measure proved on a rim that is its own ground, then held on every ground.
	var g0: Color = Palette.COLOURS["dirt"] as Color
	if _rim_contrast(g0, Color(g0, 0.0), g0) >= RIM_CONTRAST:
		push_error("%s: a rim the colour of its ground scored %.2f; the measure cannot fail" % [lane, _rim_contrast(g0, Color(g0, 0.0), g0)])
		ok = false
	var add_c: Dictionary = StockpileLook.preview_cells([Vector2i(11, 11)], true, explored, [])[0]
	var clr_c: Dictionary = StockpileLook.preview_cells([Vector2i(11, 11)], false, explored, [])[0]
	var rims: Dictionary = {"rest": rest_c, "marking": mark_c, "mark preview": add_c, "clear preview": clr_c}
	var worst: float = 99.0
	var graded_worst: float = 99.0
	var graded_lower: bool = false
	for key in RIM_GROUNDS:
		var ground: Color = Palette.COLOURS[key] as Color
		for name in rims.keys():
			var c: Dictionary = rims[name] as Dictionary
			var r: float = _rim_contrast(c["tape"] as Color, c["shadow"] as Color, ground)
			worst = minf(worst, r)
			if r < RIM_CONTRAST:
				push_error("%s: the %s rim is %.2f:1 on %s, under %.1f" % [lane, String(name), r, key, RIM_CONTRAST])
				ok = false
			# By day the street is seen through the overcast grade (presentation/day_grade.gd), which
			# veils every pixel toward the sky's grey and so takes contrast off the rim: the rim is held
			# to the same bar in the picture the player sees at noon, not only in the source colours.
			var rg: float = _rim_contrast_graded(c["tape"] as Color, c["shadow"] as Color, ground)
			graded_worst = minf(graded_worst, rg)
			if rg < r:
				graded_lower = true
			if rg < RIM_CONTRAST:
				push_error("%s: under the day grade the %s rim is %.2f:1 on %s, under %.1f" % [lane, String(name), rg, key, RIM_CONTRAST])
				ok = false
	if not graded_lower:
		push_error("%s: the day grade lowered no rim's contrast on any ground, so the graded measure is the source measure and cannot fail apart from it" % lane)
		ok = false
	# NIGHT: by firelight the wash is at least as plain on every ground as the day wash is at noon, at
	# rest and marking. Measured first on the day alphas at night, which must fall short -- else the
	# night pair is not what makes the difference -- and `cells` must use the night alpha when it is
	# handed the dark.
	var night_worst: float = 99.0
	for marking_now in [false, true]:
		var short: bool = false
		for key in RIM_GROUNDS:
			var ground: Color = Palette.COLOURS[key] as Color
			var day_c: float = _wash_contrast(StockpileLook.wash_alpha(marking_now, 1.0), ground, 1.0)
			var night_c: float = _wash_contrast(StockpileLook.wash_alpha(marking_now, 0.0), ground, NIGHT_POOL)
			night_worst = minf(night_worst, night_c / day_c)
			if night_c < day_c:
				push_error("%s: by firelight the %s wash is %.3f:1 on %s, under its %.3f:1 at noon" % [lane, "marking" if marking_now else "rest", night_c, key, day_c])
				ok = false
			if _wash_contrast(StockpileLook.wash_alpha(marking_now, 1.0), ground, NIGHT_POOL) < day_c:
				short = true
		if not short:
			push_error("%s: the day wash already holds its noon contrast by firelight, so the NIGHT measure cannot fail" % lane)
			ok = false
	var dark_cell: Dictionary = _cell_at(StockpileLook.cells(zone, seen, explored, [], false, view, {}, 0.0), Vector2i(11, 11))
	if not is_equal_approx((dark_cell.get("wash", Color()) as Color).a, Palette.STOCKPILE_WASH_REST_NIGHT):
		push_error("%s: cells handed the dark washes at %.2f, not the night alpha" % [lane, (dark_cell.get("wash", Color()) as Color).a])
		ok = false
	# Textual: the frame reaches it, with the sim's zone, the explored set and the roof.
	var world_body: String = _function_body(MAIN_GD, "_draw_world")
	var draw_body: String = _function_body(MAIN_GD, "_draw_stockpile")
	if world_body.is_empty() or draw_body.is_empty():
		push_error("%s: could not read _draw_world or _draw_stockpile out of %s" % [lane, MAIN_GD])
		ok = false
	elif not world_body.contains("_draw_stockpile(seen, explored, roof"):
		push_error("%s: _draw_world never calls _draw_stockpile with the sight sets and the roof" % lane)
		ok = false
	elif not draw_body.contains("SimStockpile.tiles(world)") or not draw_body.contains("SimStockpile.signature(world)") or not draw_body.contains("StockpileLook.cells(_stockpile_zone, seen, explored, roof, marking, whole, _stockpile_geom, light)") or not draw_body.contains("LightLook.ambient_of(world)") or not draw_body.contains("StockpileLook.batch(cells") or not draw_body.contains("int(world.tick)") or not draw_body.contains("StockpileLook.states(_stockpile_zone, seen, explored, roof)"):
		push_error("%s: _draw_stockpile does not paint StockpileLook's cells over SimStockpile.tiles, kept by its signature" % lane)
		ok = false
	if ok:
		print("%s OK never on unexplored ground, remembered tiles dimmed through Palette.remembered, roofs win with the brush up or down, one rim with no inner seams and the concave notch, a row of one wash in one fill, the state bytes move with sight and roof, quieter at rest, the preview on explored unroofed ground in one strip, the rim %.2f:1 at worst on %d grounds (%.2f:1 under the day grade), the wash by firelight at least its noon contrast (worst %.2fx), and _draw_world reaches it" % [lane, worst, RIM_GROUNDS.size(), graded_worst, night_worst])
	return ok
