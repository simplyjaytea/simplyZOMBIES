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
#
# A lane with no data to judge says so and skips (`_skip`), never passes quietly.

const SCENE_PATH: String = "res://presentation/main.tscn"
const MAIN_GD: String = "res://presentation/main.gd"

const SimVisibility = preload("res://sim/vision/visibility.gd")
const SimSightings = preload("res://sim/modules/sightings.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const MainScript = preload("res://presentation/main.gd")

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
		print("MEMORY_LOOK_OK a Focal body caches its look and a Peripheral one does not, the afterimage fades over the sim's own FRESH_TICKS band and reads only SimSightings.remembered, a walked-away tile stays known and the tile loop reaches Palette.remembered( with its continue intact, and the ground-item/prop/body branches still gate on Focal and Unseen (%s)" % skipped)
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
	# player's own (non-lit-target) shadowcast, so one step is enough.
	var far: Vector2 = _pos_of(world, int(world.player)) - Vector2(200.0, 200.0)
	world.components.set_component(int(world.player), "position", {"x": clampf(far.x, 1.0, float(world.map_width) - 2.0), "y": clampf(far.y, 1.0, float(world.map_height) - 2.0)})
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
	if district.count("continue") != 1:
		push_error("MAP-READER: _draw_district holds %d `continue` statements in its tile loop, not the one escape hatch for a tile that is neither seen nor explored" % district.count("continue"))
		return false
	print("MAP OK a tile explored a moment ago stays known after walking away, the frame carrying it finished drawing (tick %d), and the tile loop reaches Palette.remembered( with its one continue intact" % after)
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
