extends SceneTree
# Slice 5, "Walls have thickness, roofs come off": docs/30's Dungeon Settlers wall-and-roof
# treatment. presentation/roof_look.gd is pure rules over a map and a seen set; this gate holds
# every one of them against a hand-built map both ways, then proves the two resolvers
# (presentation/dressing.gd's material tables, presentation/appearance.gd's file resolve) and
# the draw loop that reaches for all three.
#
# Named lanes, every assertion with a true positive and a true negative, because a gate that
# cannot fail is worse than no gate:
#
#   A2_FLOOR actual main.tscn floor calls: accepted wall/window owners reuse room Boards and
#            unweathered tint at normal/low zoom and without the atlas; snow outdoors remains;
#            door thresholds, rejected states, remembered/unseen cells and sim metadata stand.
#   LOOK     every building template and the annex name a roof/wall material the enum allows,
#            and the dressing block resolves art for it -- refused for an unlisted material, an
#            absent look, and a wall cap naming a file that does not exist.
#   FACADE   facade_at reads a hand map's south wall, window, door and garage tiles, and answers
#            NONE for the north row, the interior partition and the map's own south edge --
#            sabotaged by probing the row above, which must disagree with every south-row answer.
#   WALL FACE  wall_face_at and south_open agree with the same map: a face only where the south
#              neighbour is genuinely open ground, never past a wall, an indoor tile or the edge.
#   ROOF     roof_tiles covers the interior the survivor cannot see, of a building it has glimpsed
#            any part of, unless it stands inside -- with the known() gate proven as a standing
#            negative: drop it and an unseen building would roof anyway.
#   SLOPE    slope_of's ridge row, and Dressing.roof_pitched/roof_key over fabricated tables.
#   INDEX    building_index maps every tile to its building, the annex, or neither.
#   PLAYED   the shipped suburb: every roofed tile is indoors, unseen and inside a known
#            building, and every building index resolves a look.
#   MOOD     every wall cap/face, roof sheet and window/door/garage overlay decodes opaque and
#            warm, clears the ground family by a measured margin, and the face's own top rows
#            match its cap -- refused for a flat grey fixture, a ground-tinted one and an overlay
#            drawn above its allowed rows.
#   SOCKETS  the draw loop actually reaches every rule above, in the order the plan named, with
#            the procedural fallback still standing beside it -- the needle scanner proven on a
#            fabricated body first, check_topdown.gd's convention.
#
# LOOK and MOOD are the two lanes that decode the sixteen wall/roof/face PNGs
# (tools/sprites/parts/buildings.py); everything else is pure geometry, or textual against
# main.gd, and would stay green with the art deleted -- which is why LOOK names a missing file.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimWorldgen = preload("res://sim/map/worldgen.gd")
const SimSurface = preload("res://sim/map/surface.gd")
const SimBoot = preload("res://sim/boot.gd")
const World = preload("res://sim/world.gd")
const ContentLoader = preload("res://platform/content_loader.gd")
const Appearance = preload("res://presentation/appearance.gd")
const Dressing = preload("res://presentation/dressing.gd")
const RoofLook = preload("res://presentation/roof_look.gd")
const Palette = preload("res://presentation/palette.gd")
const CameraUtil = preload("res://presentation/camera.gd")
const MainRenderer = preload("res://presentation/main.gd")
const TopDownProjection = preload("res://presentation/projection.gd")
const Session = preload("res://presentation/session.gd")
const SimVisibility = preload("res://sim/vision/visibility.gd")

const MAIN_GD: String = "res://presentation/main.gd"
const ROOF_GD: String = "res://presentation/roof_look.gd"
const CANON_SEED: int = 20260805
const GATE_SIZE: int = 64
const BUDGET_SECONDS: float = 60.0

const ROOFS: Array[String] = ["shingle", "tin", "tar"]
const WALLS: Array[String] = ["timber", "brick", "render", "block"]

# check_road_look.gd's WARM_MARGIN, copied: that file is a SceneTree entrypoint, not a class
# another script can import, so the value travels by comment rather than by reference.
const WARM_MARGIN: float = 0.02
# How far a material's luma must sit from every ground tint (the six surfaces, sidewalk,
# indoorFloor) for a wall or a roof to read as its own thing rather than as more ground.
#
# The owner's answer of 2026-09-27 (docs/23, "The ground is the pack's"; relayed by the
# coordinator) kept this guard on the warm-dark table the generated art was authored against,
# Palette.GENERATOR_GROUNDS, rather than the pack's ground the district now draws: regrading that
# art is the job of the slice that replaces it, and this guard retires with it.
# Against the pack's own table the four generated wall caps and the lit roofs fall inside the
# margin (wall_timber_cap sits 0.023 from the pack's dirt); docs/23's record carries the numbers.
const GROUND_CLEAR_MARGIN: float = 0.08
# How close a wall face's top 20 rows must sit to its cap's own mean, in RGB.
const FACE_TOP_MEAN_MAX: float = 0.04

var _stash: Dictionary = {}


# The whole interface roof_tiles and known() ask an observer for: has_tile(tx, ty). A plain
# Dictionary of tiles rather than the real shadowcast index, the check_light_look.gd convention
# for a fixture that stands in for SimVisibility without booting one.
class FakeSeen extends RefCounted:
	var tiles: Dictionary = {}

	func has_tile(tx: int, ty: int) -> bool:
		return tiles.has(Vector2i(tx, ty))


class AllFocalVision extends RefCounted:
	var hidden: Dictionary = {}

	func tiles_for(_observer: int) -> Variant:
		return self

	func has_tile(tx: int, ty: int) -> bool:
		return not hidden.has(Vector2i(tx, ty))

	func detail(_observer: int, _x: float, _y: float) -> int:
		return SimVisibility.Detail.Focal


# Instrument only the gate's scene instance. These overrides forward to the actual renderer,
# then remember its arguments, so the underlay proof must reach the same floor blit as a room.
class FloorRecordingRenderer extends MainRenderer:
	var floor_calls: Dictionary = {}
	var underlay_tiles: Dictionary = {}
	var threshold_tiles: Dictionary = {}

	func _draw_floor_tile(rect: Rect2, col: Color, tx: int, ty: int, row: int) -> void:
		super._draw_floor_tile(rect, col, tx, ty, row)
		floor_calls[Vector2i(tx, ty)] = {"colour": col, "row": row, "rect": rect}

	func _draw_a2_floor_underlay(rect: Rect2, tx: int, ty: int) -> void:
		super._draw_a2_floor_underlay(rect, tx, ty)
		underlay_tiles[Vector2i(tx, ty)] = true

	func _draw_threshold(rect: Rect2, col: Color, tx: int, ty: int) -> void:
		super._draw_threshold(rect, col, tx, ty)
		threshold_tiles[Vector2i(tx, ty)] = true


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var started: int = Time.get_ticks_msec()
	var ok: bool = true
	ok = _the_a2_native_map_is_exact() and ok
	ok = _the_a2_runtime_placements_and_fallbacks() and ok
	var scene_draw_ok: bool = await _the_a2_scene_draws_walls_and_body()
	ok = scene_draw_ok and ok
	ok = _the_look_resolves_and_can_say_no() and ok
	ok = _the_facade_reads_the_street_and_can_say_no() and ok
	ok = _the_wall_face_and_south_open_agree_with_the_map() and ok
	ok = _the_roof_covers_what_the_survivor_cannot_see() and ok
	ok = _the_slope_and_pitch_answer_correctly() and ok
	ok = _the_building_index_maps_tiles_to_buildings() and ok
	ok = _the_shipped_suburb_roofs_what_it_should() and ok
	ok = _the_art_is_warm_and_reads_against_the_ground() and ok
	ok = _the_draw_loop_reaches_every_helper() and ok

	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	if seconds > BUDGET_SECONDS:
		push_error("check_roof_look ran %.1f s against a %.0f s budget" % [seconds, BUDGET_SECONDS])
		ok = false

	if ok:
		print(
			(
				"ROOF_LOOK_OK %d look blocks resolve wall/roof/face art; %d facade thresholds read correctly; roof case (a) covered %d tiles and case (e) %d, both proven against known() and the ty-1 probe; suburb@%d roofed %d of %d indoor tiles with every building's look resolving; %d material keys read warm against the ground; the draw loop reaches every helper in order; %.1f s of a %.0f s budget"
				% [
					int(_stash.get("look_entries", 0)),
					int(_stash.get("thresholds", 0)),
					int(_stash.get("roof_a", 0)),
					int(_stash.get("roof_e", 0)),
					GATE_SIZE,
					int(_stash.get("played_roofed", 0)),
					int(_stash.get("played_indoor", 0)),
					int(_stash.get("mood_keys", 0)),
					seconds,
					BUDGET_SECONDS,
				]
			)
		)
		quit(0)
	else:
		push_error("ROOF_LOOK_FAIL")
		quit(1)


# --- fixtures ------------------------------------------------------------------------------


# A world with a full content tree and no district, check_appearance.gd's `_fixture()` shape --
# for resolving the dressing block without booting anything.
func _fixture() -> Dictionary:
	return {
		"seed": 77,
		"tick_hz": 20,
		"map": {"width": 12, "height": 10, "walls": []},
		"player": {"id": 0, "x": 6.0, "y": 5.0, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	}


# The hand map every geometry lane below reads: a 10x10 street with two shells.
#
# Shell 1, a 5x4 house at (1,1): a south window at its middle (3,4), a south door at (2,4), a
# north window at (3,1) that must NOT read as a door despite being glass, and an interior
# partition wall at (3,2) with indoors on both sides of it.
#
# Shell 2, a 4x4 garage at (6,1): a two-wide garage mouth on its south row, (7,4) and (8,4).
#
# A stray wall at (8,6) with a Low tile -- cover, not shelter -- to its south at (8,7): Low is
# not solid, so a wall still reads its face over cover the way it does over open street.
func _facade_map() -> Variant:
	var map: Variant = SimTileMap.blank_map(10, 10)
	var w: int = int(map.w)

	var wall1: Array = [
		Vector2i(1, 1), Vector2i(2, 1), Vector2i(4, 1), Vector2i(5, 1),
		Vector2i(1, 2), Vector2i(1, 3), Vector2i(5, 2), Vector2i(5, 3),
		Vector2i(1, 4), Vector2i(4, 4), Vector2i(5, 4),
	]
	for t in wall1:
		map.tiles[t.y * w + t.x] = SimTileMap.Tile.Wall
	map.tiles[1 * w + 3] = SimTileMap.Tile.Window  # north window: reads NONE (south is indoors)
	map.tiles[4 * w + 3] = SimTileMap.Tile.Window  # south window
	map.tiles[2 * w + 3] = SimTileMap.Tile.Wall  # the interior partition
	# (2, 4) stays Floor: the south door.
	var interior1: Array = [
		Vector2i(2, 2), Vector2i(4, 2), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3), Vector2i(3, 2),
	]
	for t1 in interior1:
		map.indoors[t1.y * w + t1.x] = 1

	var wall2: Array = [
		Vector2i(6, 1), Vector2i(7, 1), Vector2i(8, 1), Vector2i(9, 1),
		Vector2i(6, 2), Vector2i(6, 3), Vector2i(9, 2), Vector2i(9, 3),
		Vector2i(6, 4), Vector2i(9, 4),
	]
	for t2 in wall2:
		map.tiles[t2.y * w + t2.x] = SimTileMap.Tile.Wall
	# (7, 4) and (8, 4) stay Floor: the two-wide garage mouth.
	for t3 in [Vector2i(7, 2), Vector2i(8, 2), Vector2i(7, 3), Vector2i(8, 3)]:
		map.indoors[t3.y * w + t3.x] = 1

	map.tiles[6 * w + 8] = SimTileMap.Tile.Wall
	map.tiles[7 * w + 8] = SimTileMap.Tile.Low

	map.buildings = [
		{"id": "b0", "x": 1, "y": 1, "w": 5, "h": 4, "doors": [{"x": 2, "y": 4}]},
		{"id": "b1", "x": 6, "y": 1, "w": 4, "h": 4, "doors": [{"x": 7, "y": 4}, {"x": 8, "y": 4}]},
	]
	return map


# --- lane 1: LOOK ----------------------------------------------------------------------------


# "" when a look resolves every wall/roof/face key it needs against `dress`, else what is wrong
# with it. One predicate so the fabricated negatives below refuse through the same code the real
# templates pass through.
func _material_resolves(dress: Dictionary, look: Dictionary) -> String:
	var roof: String = String(look.get("roof", ""))
	var wall: String = String(look.get("wall", ""))
	if not ROOFS.has(roof):
		return "look.roof '%s' is not one of %s" % [roof, str(ROOFS)]
	if not WALLS.has(wall):
		return "look.wall '%s' is not one of %s" % [wall, str(WALLS)]
	var native: int = int(CameraUtil.ART_NATIVE)
	var want := Vector2i(native, native)

	var cap_key: String = Dressing.wall_key(dress, wall, false)
	var cap_tex: Variant = Appearance.resolve(cap_key)
	if cap_tex == null:
		return "wall cap '%s' (material %s) resolves no picture" % [cap_key, wall]
	if Vector2i((cap_tex as Texture2D).get_size()) != want:
		return "wall cap '%s' is %s, not %s" % [cap_key, str((cap_tex as Texture2D).get_size()), str(want)]

	var face_key: String = Dressing.wall_key(dress, wall, true)
	var face_tex: Variant = Appearance.resolve(face_key)
	if face_tex == null:
		return "wall face '%s' (material %s) resolves no picture" % [face_key, wall]
	if Vector2i((face_tex as Texture2D).get_size()) != want:
		return "wall face '%s' is %s, not %s" % [face_key, str((face_tex as Texture2D).get_size()), str(want)]

	var pitched: bool = Dressing.roof_pitched(dress, roof)
	var slopes: Array = [RoofLook.Slope.NORTH, RoofLook.Slope.SOUTH] if pitched else [RoofLook.Slope.FLAT]
	for slope in slopes:
		var roof_key: String = Dressing.roof_key(dress, roof, int(slope))
		var roof_tex: Variant = Appearance.resolve(roof_key)
		if roof_tex == null:
			return "roof key '%s' (material %s, slope %d) resolves no picture" % [roof_key, roof, int(slope)]
		if Vector2i((roof_tex as Texture2D).get_size()) != want:
			return "roof key '%s' is %s, not %s" % [roof_key, str((roof_tex as Texture2D).get_size()), str(want)]
	return ""


func _a2_mapping_fault(block: Dictionary) -> String:
	var expected: Dictionary = {
		"render": {"west": "a2_plaster_west", "middle": "a2_plaster_middle", "east": "a2_plaster_east", "window": "a2_window_intact", "door_open": "a2_door_open", "door_closed": "a2_door_closed", "corner_west": "a2_corner_nw", "corner_east": "a2_corner_ne", "leg_west": "a2_leg_west", "leg_east": "a2_leg_east"},
		"brick": {"west": "a2_brick_west", "middle": "a2_brick_middle", "east": "a2_brick_east"},
	}
	for material_v in expected.keys():
		var material: String = String(material_v)
		var actual: Dictionary = Dressing.wall_modules(block, material)
		for slot_v in (expected[material] as Dictionary).keys():
			var slot: String = String(slot_v)
			if String(actual.get(slot, "")) != String((expected[material] as Dictionary)[slot_v]):
				return "%s.%s does not name the selected native module" % [material, slot]
	return ""


func _the_a2_native_map_is_exact() -> bool:
	var shipped: Dictionary = Dressing.block_of(World.new(_fixture()))
	var render_modules: Dictionary = Dressing.wall_modules(shipped, "render")
	var brick_modules: Dictionary = Dressing.wall_modules(shipped, "brick")
	if String(render_modules.get("west", "")) != "a2_plaster_west" or String(render_modules.get("middle", "")) != "a2_plaster_middle" or String(render_modules.get("east", "")) != "a2_plaster_east" or String(brick_modules.get("west", "")) != "a2_brick_west":
		push_error("A2 run roles do not read the exact selected west/middle/east authored keys")
		return false
	var wrong_material: Dictionary = Dressing.wall_modules({"wall_modules": {"timber": {"west": "a2_plaster_west"}}}, "timber")
	var wrong_role: Dictionary = Dressing.wall_modules({"wall_modules": {"render": {"west": "a2_plaster_east"}}}, "render")
	if not wrong_material.is_empty() or String(wrong_role.get("west", "")) != "a2_plaster_east" or _a2_mapping_fault({"wall_modules": {"render": wrong_role}}).is_empty():
		push_error("A2 mapping accepted unsupported timber art or the opposite endpoint key")
		return false
	var rect := Rect2i(1, 1, 5, 4)
	if RoofLook.a2_south_corner_x(rect, true) != 1 or RoofLook.a2_south_corner_x(rect, false) != 4:
		push_error("A2 corner plates did not map to the selected south-west/south-east anchors")
		return false
	if RoofLook.a2_south_corner_x(rect, true) == rect.end.x - 2 or RoofLook.a2_south_corner_x(rect, false) == rect.position.x:
		push_error("A2 accepted the opposite corner placement")
		return false
	var visibility_map: Variant = _facade_map()
	var seen := FakeSeen.new()
	seen.tiles[Vector2i(1, 4)] = true
	var corner_footprint := Rect2i(1, 3, 2, 2)
	if RoofLook.a2_span_visible(visibility_map, corner_footprint, seen):
		push_error("A2 corner overhang became visible from its single seen anchor")
		return false
	for y in range(corner_footprint.position.y, corner_footprint.end.y):
		for x in range(corner_footprint.position.x, corner_footprint.end.x):
			seen.tiles[Vector2i(x, y)] = true
	if not RoofLook.a2_span_visible(visibility_map, corner_footprint, seen) or RoofLook.a2_span_visible(visibility_map, Rect2i(-1, 3, 2, 2), seen):
		push_error("A2 corner span accepted a partially seen or off-map footprint")
		return false
	var topology: Variant = _facade_map()
	var topology_w: int = int(topology.w)
	for y in range(1, 5):
		for x in range(6, 10):
			topology.tiles[y * topology_w + x] = SimTileMap.Tile.Floor
			topology.indoors[y * topology_w + x] = 0
	topology.buildings = [topology.buildings[0]]
	topology.tiles[4 * topology_w + 2] = SimTileMap.Tile.Door
	var prototype_rect := Rect2i(1, 1, 5, 4)
	if not RoofLook.a2_rectangular_ring(topology, prototype_rect, 0):
		push_error("A2 refused the approved rectangular prototype ring")
		return false
	topology.tiles[2 * topology_w + 1] = SimTileMap.Tile.Floor
	if RoofLook.a2_rectangular_ring(topology, prototype_rect, 0):
		push_error("A2 accepted a notched bounding rectangle as a wall ring")
		return false
	topology.tiles[2 * topology_w + 1] = SimTileMap.Tile.Wall
	topology.tiles[2 * topology_w + 6] = SimTileMap.Tile.Wall
	if RoofLook.a2_rectangular_ring(topology, prototype_rect, 0):
		push_error("A2 accepted touching outside masonry as a guessed compound ring")
		return false
	for key in ["a2_plaster_west", "a2_plaster_middle", "a2_plaster_east", "a2_corner_nw", "a2_corner_ne", "a2_leg_west", "a2_leg_east", "a2_window_intact", "a2_door_open", "a2_door_closed"]:
		if not render_modules.values().has(key) or Appearance.resolve(String(key)) == null:
			push_error("A2 plaster module %s is unresolved" % String(key))
			return false
	for key in ["a2_brick_west", "a2_brick_middle", "a2_brick_east"]:
		if not brick_modules.values().has(key) or Appearance.resolve(String(key)) == null:
			push_error("A2 brick run %s is unresolved" % String(key))
			return false
	if not Dressing.wall_modules({}, "render").is_empty() or not Dressing.wall_modules(shipped, "timber").is_empty():
		push_error("A2 missing material block did not retain the generated fallback")
		return false
	var unknown_role: Dictionary = shipped.duplicate(true)
	((unknown_role["wall_modules"] as Dictionary)["render"] as Dictionary)["unused"] = "a2_plaster_middle"
	if Dressing.wall_modules_fault(shipped) != "" or Dressing.wall_modules_fault(unknown_role) == "":
		push_error("A2 wall module shape predicate did not reject a dead unknown role")
		return false
	var swapped_slot: Dictionary = shipped.duplicate(true)
	((swapped_slot["wall_modules"] as Dictionary)["render"] as Dictionary)["corner_west"] = "a2_corner_ne"
	if _a2_mapping_fault(shipped) != "" or _a2_mapping_fault(swapped_slot) == "":
		push_error("A2 mapping predicate did not refuse the opposite native corner in the west role")
		return false
	print("A2_MAP OK rectangular shell, plaster/brick slices and shape-matched south corners resolve; opposite placement/end crop, unsupported timber, notched/touching shells, partial visibility and off-map overhangs refuse")
	return true


func _a2_runtime_map() -> Variant:
	var map: Variant = SimTileMap.blank_map(12, 10)
	var w: int = int(map.w)
	var rect := Rect2i(2, 2, 7, 5)
	for x in range(rect.position.x, rect.end.x):
		map.tiles[rect.position.y * w + x] = SimTileMap.Tile.Wall
		map.tiles[(rect.end.y - 1) * w + x] = SimTileMap.Tile.Wall
	for y in range(rect.position.y + 1, rect.end.y - 1):
		map.tiles[y * w + rect.position.x] = SimTileMap.Tile.Wall
		map.tiles[y * w + rect.end.x - 1] = SimTileMap.Tile.Wall
		for x in range(rect.position.x + 1, rect.end.x - 1):
			map.indoors[y * w + x] = 1
	map.tiles[6 * w + 4] = SimTileMap.Tile.Window
	map.tiles[6 * w + 5] = SimTileMap.Tile.Door
	map.tiles[4 * w + 8] = SimTileMap.Tile.Window
	map.buildings = [{"id": "a2.fixture", "x": 2, "y": 2, "w": 7, "h": 5, "doors": [{"x": 5, "y": 6}]}]
	return map


func _a2_runtime_select(renderer: Variant, map: Variant, block: Dictionary, seen: Variant) -> Dictionary:
	var bounds: Dictionary = {"minX": 0.0, "minY": 0.0, "maxX": float(map.w), "maxY": float(map.h)}
	return renderer.call("_a2_wall_modules", block, seen, null, bounds) as Dictionary


func _the_a2_scene_draws_walls_and_body() -> bool:
	var main: Node = load("res://presentation/main.tscn").instantiate()
	main.set_script(FloorRecordingRenderer)
	root.add_child(main)
	await process_frame
	main.call("_enter_state", Session.State.PLAYING)
	main.set_physics_process(false)
	main.set_process(false)
	var world: Variant = main.get("world")
	var map: Variant = _a2_runtime_map()
	world.tilemap = map
	world.map_width = int(map.w)
	world.map_height = int(map.h)
	world.mapGeneration += 1
	world.map_cells.resize(int(map.w) * int(map.h))
	for y in map.h:
		for x in map.w:
			world.map_cells[y * int(map.w) + x] = 1 if SimTileMap.is_solid(map, x, y) else 0
	for entity in world.components.query(["position"]):
		var pos: Variant = world.components.get_component(entity, "position")
		if pos is Dictionary:
			(pos as Dictionary)["x"] = 200.0
			(pos as Dictionary)["y"] = 200.0
	var player_pos: Dictionary = world.components.get_component(int(world.player), "position") as Dictionary
	player_pos["x"] = 5.5
	player_pos["y"] = 5.4
	world.vision = AllFocalVision.new()
	var camera: Dictionary = main.get("camera")
	camera["zoom"] = 32.0
	camera["width"] = float(main.get_viewport_rect().size.x)
	camera["height"] = float(main.get_viewport_rect().size.y)
	camera["x"] = 6.0
	camera["y"] = 5.0
	main.set("camera", camera)
	main.call("_building_index")
	main.set("_looks", {0: {"wall": "render", "roof": "tar"}})
	main.queue_redraw()
	await process_frame
	await process_frame
	var pieces: Array = main.get("_a2_wall_pieces")
	var focal: Array = main.get("_focal_drawn")
	var blits: Array = main.get("_a2_wall_drawn")
	var player_was_drawn: bool = false
	for body_v in focal:
		player_was_drawn = player_was_drawn or int((body_v as Dictionary).get("id", -1)) == int(world.player)
	var completed: bool = int(main.get("_drew_tick")) == int(world.tick)
	if pieces.is_empty() or blits.is_empty() or not player_was_drawn or not completed:
		push_error("A2 actual scene draw did not blit wall fragments and complete the Focal body path (pieces=%d blits=%d focal=%d tick=%d/%d)" % [pieces.size(), blits.size(), focal.size(), int(main.get("_drew_tick")), int(world.tick)])
		main.queue_free()
		return false
	print("A2_SCENE_DRAW OK main.tscn completed a full frame with %d wall pieces, %d actual texture blits, and player in _focal_drawn" % [pieces.size(), blits.size()])
	var underlay_ok: bool = await _the_a2_scene_underlay_stays_inside_coverage(main)
	main.queue_free()
	return underlay_ok


func _redraw_floor_probe(main: Node) -> void:
	(main.get("floor_calls") as Dictionary).clear()
	(main.get("underlay_tiles") as Dictionary).clear()
	(main.get("threshold_tiles") as Dictionary).clear()
	main.queue_redraw()
	await process_frame
	await process_frame


func _the_a2_scene_underlay_stays_inside_coverage(main: Node) -> bool:
	var world: Variant = main.get("world")
	var map: Variant = world.tilemap
	var original_tiles: PackedByteArray = map.tiles.duplicate()
	var original_indoors: PackedByteArray = map.indoors.duplicate()
	var original_surface: PackedByteArray = map.surfaces.duplicate()
	var original_buildings: Array = map.buildings.duplicate(true)
	var atlas: Texture2D = Appearance.ground_atlas()
	if atlas == null:
		push_error("A2_FLOOR needs the shipped atlas before testing its missing-atlas fallback")
		return false
	var camera: Dictionary = main.get("camera")
	# Headless can report a tiny root viewport; cover the complete fixture at every test zoom.
	camera["width"] = 384.0
	camera["height"] = 320.0
	var expected: Color = Appearance.indoor_floor(map, 3, 3, Appearance.ground_colour(map, 3, 3))
	var ok: bool = true
	for scenario in ["clear", "snow", "low_zoom", "missing_atlas"]:
		world.weather["snowCover"] = 0.0 if scenario == "clear" else 1.0
		camera["zoom"] = Palette.GROUND_TEXTURE_MIN_ZOOM - 1.0 if scenario == "low_zoom" else 32.0
		Appearance._cache[Appearance.GROUND_ATLAS_KEY] = null if scenario == "missing_atlas" else atlas
		await _redraw_floor_probe(main)
		var calls: Dictionary = main.get("floor_calls")
		var underlays: Dictionary = main.get("underlay_tiles")
		if underlays.size() != 18 or underlays.has(Vector2i(8, 4)) or underlays.has(Vector2i(5, 6)):
			push_error("A2_FLOOR %s expected 18 wall/window owners only, got %s" % [scenario, str(underlays.keys())])
			ok = false
		for cell in underlays:
			var floor_call: Dictionary = calls.get(cell, {})
			if int(floor_call.get("row", -1)) != Appearance.GroundRow.Boards or not (floor_call.get("colour", Color.TRANSPARENT) as Color).is_equal_approx(expected):
				push_error("A2_FLOOR %s owner %s did not reach room Boards and its unweathered tint" % [scenario, str(cell)])
				ok = false
		# The same scene must still snow-tint outdoor ground, and the accepted door must reach
		# the separate threshold drawer. Checking both keeps a blanket no-snow/floor fix red.
		var outdoor: Color = (calls.get(Vector2i(0, 0), {}) as Dictionary).get("colour", Color.TRANSPARENT)
		if not (main.get("threshold_tiles") as Dictionary).has(Vector2i(5, 6)) or outdoor.is_equal_approx(expected):
			push_error("A2_FLOOR %s changed the door threshold or painted room floor outdoors" % scenario)
			ok = false
		if scenario == "clear":
			_stash["a2_clear_outdoor"] = outdoor
		elif outdoor.is_equal_approx(_stash["a2_clear_outdoor"] as Color):
			push_error("A2_FLOOR %s no longer applies snow to outdoor floor" % scenario)
			ok = false
	Appearance._cache[Appearance.GROUND_ATLAS_KEY] = atlas
	camera["zoom"] = 32.0
	world.weather["snowCover"] = 0.0
	if map.tiles != original_tiles or map.indoors != original_indoors or map.surfaces != original_surface or map.buildings != original_buildings:
		push_error("A2_FLOOR presentation changed map geometry, indoor flags, surface or building metadata")
		ok = false
	# Fallback states must reach no underlay on the rejected cell, even when it used A2 in
	# the preceding frame. The current renderer instance and its caches stay alive throughout.
	for overlay in [{"kind": "board", "stage": 2}, {"kind": "scrap", "stage": 0}]:
		map.overlays[6 * int(map.w) + 4] = overlay
		await _redraw_floor_probe(main)
		if (main.get("underlay_tiles") as Dictionary).has(Vector2i(4, 6)):
			push_error("A2_FLOOR leaked underlay into %s window fallback" % str(overlay))
			ok = false
	map.overlays.erase(6 * int(map.w) + 4)
	main.set("_looks", {0: {"wall": "timber", "roof": "tar"}})
	await _redraw_floor_probe(main)
	if not (main.get("underlay_tiles") as Dictionary).is_empty():
		push_error("A2_FLOOR unsupported timber received A2 boards")
		ok = false
	main.set("_looks", {0: {"wall": "render", "roof": "tar"}})
	# All remembered, but no currently seen tiles: the generated remembered treatment must
	# remain. Never-seen is tested on the same scene after removing that memory.
	var vision: Variant = world.vision
	for y in map.h:
		for x in map.w:
			vision.hidden[Vector2i(x, y)] = true
	var bits := PackedByteArray()
	bits.resize(ceili(float(int(map.w) * int(map.h)) / 8.0))
	bits.fill(255)
	world.components.set_component(int(world.player), "explored", {"w": int(map.w), "h": int(map.h), "bits": Marshalls.raw_to_base64(bits)})
	await _redraw_floor_probe(main)
	if not (main.get("underlay_tiles") as Dictionary).is_empty() or (main.get("floor_calls") as Dictionary).is_empty():
		push_error("A2_FLOOR remembered-only frame did not keep generated fallback floor without A2 underlays")
		ok = false
	world.components.remove_component(int(world.player), "explored")
	await _redraw_floor_probe(main)
	if not (main.get("underlay_tiles") as Dictionary).is_empty() or not (main.get("floor_calls") as Dictionary).is_empty():
		push_error("A2_FLOOR never-seen frame drew floor")
		ok = false
	if ok:
		print("A2_FLOOR OK actual main.tscn draws 18 owner-cell Boards underlays matching room tint; snow, low zoom and missing atlas preserve that floor; doors, side-window/board/scrap/timber fallback, remembered and never-seen cells refuse it; map metadata unchanged")
	return ok


func _the_a2_runtime_placements_and_fallbacks() -> bool:
	var map: Variant = _a2_runtime_map()
	var w: int = int(map.w)
	var seen := FakeSeen.new()
	for y in map.h:
		for x in map.w:
			seen.tiles[Vector2i(x, y)] = true
	var world: Variant = World.new(_fixture())
	world.tilemap = map
	world.vision = seen
	var renderer: Variant = MainRenderer.new()
	renderer.set("world", world)
	renderer.set("camera", {"zoom": 32.0, "x": 6.0, "y": 5.0, "width": 384.0, "height": 320.0})
	renderer.call("_building_index")
	renderer.set("_looks", {0: {"wall": "render"}})
	var block: Dictionary = Dressing.block_of(world)
	var covered: Dictionary = _a2_runtime_select(renderer, map, block, seen)
	var south: int = 6
	for x in range(2, 9):
		if not covered.has(south * w + x):
			push_error("A2 runtime left supported south owner tile %d to the generated path" % x)
			return false
	if covered.has(4 * w + 8):
		push_error("A2 runtime suppressed the east-side window and its generated pane fallback")
		return false
	var pieces: Array = renderer.get("_a2_wall_pieces")
	var corner_w: bool = false
	var corner_e: bool = false
	var west_leg_count: int = 0
	var west_intervals: Array[Vector2] = []
	var west_sources: Array[Vector2i] = []
	var corner_records: Dictionary = {}
	var east_window_pane_visible: bool = int(SimTileMap.tile_at(map, 8, 4)) == SimTileMap.Tile.Window and not covered.has(4 * w + 8)
	for piece_v in pieces:
		var piece: Dictionary = piece_v as Dictionary
		var key: String = String(piece.get("key", ""))
		corner_w = corner_w or key == "a2_corner_nw"
		corner_e = corner_e or key == "a2_corner_ne"
		if key in ["a2_corner_nw", "a2_corner_ne"]:
			corner_records[key] = piece
		if key == "a2_leg_west":
			west_leg_count += 1
			var leg_crop: Rect2i = piece["crop"] as Rect2i
			var leg_top: float = float(piece["top"])
			var native_start: int = roundi(leg_top * 32.0 - 66.0)
			west_intervals.append(Vector2(leg_top, leg_top + float(leg_crop.size.y) / 32.0))
			west_sources.append(Vector2i(leg_crop.position.y, leg_crop.size.y))
			if native_start < 0 or leg_crop.position.y != posmod(native_start, 16):
				push_error("A2 leg fragment lost its repeated 16px global source phase")
				return false
			if not is_equal_approx(float(piece.get("d", -1.0)), float(floori(float(piece["top"])) + 1)):
				push_error("A2 leg fragment is not sorted at its owner row's foot")
				return false
	west_intervals.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var covered_y: float = 66.0 / 32.0 # north row 2 plus the prototype's 2px inset
	for interval in west_intervals:
		if not is_equal_approx(interval.x, covered_y):
			push_error("A2 west leg contains a gap/overlap or lost global phase at %s" % str(interval))
			return false
		covered_y = interval.y
	if not is_equal_approx(covered_y, 160.0 / 32.0) or west_sources.is_empty():
		push_error("A2 west leg union is not exactly y=[66,160) in repeated native 16px bands")
		return false
	for corner_key in ["a2_corner_nw", "a2_corner_ne"]:
		if not corner_records.has(corner_key):
			push_error("A2 placement omitted actual corner record %s" % corner_key)
			return false
		var corner: Dictionary = corner_records[corner_key] as Dictionary
		var expected_x: float = 2.0 if corner_key == "a2_corner_nw" else 7.0
		if not is_equal_approx(float(corner["left"]), expected_x) or not is_equal_approx(float(corner["top"]), 5.0) or not is_equal_approx(float(corner["d"]), 7.0) or not is_equal_approx(float(corner["order"]), 0.2) or (corner["crop"] as Rect2i) != Rect2i(0, 0, 64, 64):
			push_error("A2 corner %s has wrong source crop, footprint, depth, or stable body tie" % corner_key)
			return false
	var actual_corner: Dictionary = corner_records["a2_corner_nw"] as Dictionary
	var body_north := {"d": 6.9, "order": 1.0}
	var body_on_foot := {"d": 7.0, "order": 1.0}
	var body_south := {"d": 7.1, "order": 1.0}
	if not RoofLook.a2_item_before(body_north, actual_corner) or not RoofLook.a2_item_before(actual_corner, body_on_foot) or not RoofLook.a2_item_before(actual_corner, body_south):
		push_error("Actual A2 corner sort record is not behind bodies north/south of its foot")
		return false
	if covered.has(5 * w + 3) or covered.has(5 * w + 7):
		push_error("A2 corner support reservation extended into an unrelated upper/interior cell")
		return false
	if not corner_w or not corner_e or west_leg_count < 5 or not east_window_pane_visible:
		push_error("A2 runtime missed the 64x64 corners, continuous clipped side-leg phase or east window fallback")
		return false
	var body_tie := {"d": 7.0, "order": 1.0}
	var wall_tie := {"d": 7.0, "order": 0.2}
	if not RoofLook.a2_item_before(wall_tie, body_tie) or RoofLook.a2_item_before(body_tie, wall_tie) or not RoofLook.a2_item_before({"d": 6.9}, body_tie) or RoofLook.a2_item_before({"d": 7.1}, body_tie):
		push_error("A2 equal-foot tie order did not put the wall behind a body at the same line")
		return false
	var horizontal_rect := Rect2(4.0, 5.625, 1.0, 1.5) # native y=[32*ty-12, 32*(ty+1)+4)
	var anchor_only := FakeSeen.new()
	anchor_only.tiles[Vector2i(4, 6)] = true
	var clipped: Array[Dictionary] = RoofLook.a2_visible_fragments(map, horizontal_rect, anchor_only)
	if clipped.size() != 1 or (clipped[0]["rect"] as Rect2) != Rect2(4.0, 6.0, 1.0, 1.0):
		push_error("A2 owner-only visibility leaked its north 12 or south 4 overhang pixels")
		return false
	anchor_only.tiles[Vector2i(4, 5)] = true
	clipped = RoofLook.a2_visible_fragments(map, horizontal_rect, anchor_only)
	if clipped.size() != 2 or not (clipped[0]["rect"] as Rect2).has_area():
		push_error("A2 seen northern destination did not reveal only its clipped source fragment")
		return false
	anchor_only.tiles[Vector2i(4, 7)] = true
	clipped = RoofLook.a2_visible_fragments(map, horizontal_rect, anchor_only)
	if clipped.size() != 3 or not RoofLook.a2_span_visible(map, Rect2i(4, 6, 1, 1), seen):
		push_error("A2 seen southern destination did not reveal exactly the 4px clipped tail")
		return false
	var east_leg := Rect2(5.0 + 15.0 / 32.0, 6.0, 17.0 / 32.0, 1.0)
	var east_seen := FakeSeen.new()
	east_seen.tiles[Vector2i(5, 6)] = true
	var east_fragments: Array[Dictionary] = RoofLook.a2_visible_fragments(map, east_leg, east_seen)
	if east_fragments.size() != 1 or (east_fragments[0]["rect"] as Rect2).end.x != 6.0:
		push_error("A2 east leg's visible fragment crosses into its unseen east neighbor")
		return false
	var fractional_camera := {"zoom": 16.0, "x": 5.0, "y": 6.0, "width": 320.0, "height": 200.0}
	var fragment_screen_start: Dictionary = TopDownProjection.world_to_screen(fractional_camera, east_leg.position.x, east_leg.position.y)
	var fragment_screen_end: Dictionary = TopDownProjection.world_to_screen(fractional_camera, east_leg.end.x, east_leg.end.y)
	var snapped_fragment: Rect2 = RoofLook.a2_rounded_screen_rect(Vector2(fragment_screen_start["sx"], fragment_screen_start["sy"]), Vector2(fragment_screen_end["sx"], fragment_screen_end["sy"]))
	var seen_edge: Dictionary = TopDownProjection.world_to_screen(fractional_camera, 6.0, 6.0)
	if snapped_fragment.size.x != 8.0 or snapped_fragment.end.x != roundf(float(seen_edge["sx"])) or roundf(17.0 / 32.0 * 16.0) == snapped_fragment.size.x:
		push_error("A2 zoom16 fractional rounding did not end at the rounded seen-tile boundary")
		return false
	# A corner reserves precisely its three L-shaped support cells, and refuses a window/door
	# that would be hidden underneath the source plate.
	map.tiles[6 * w + 3] = SimTileMap.Tile.Window
	covered = _a2_runtime_select(renderer, map, block, seen)
	pieces = renderer.get("_a2_wall_pieces")
	for piece_v2 in pieces:
		if String((piece_v2 as Dictionary).get("key", "")) == "a2_corner_nw":
			push_error("A2 runtime stamped a full corner over its south-window support")
			return false
	if not covered.has(6 * w + 3):
		push_error("A2 runtime did not preserve the adjacent south-window tile as its own module/fallback")
		return false
	map.tiles[6 * w + 3] = SimTileMap.Tile.Wall
	# Board and scrap overlays are not evidence of broken glass; retain the generated window arm.
	map.overlays[6 * w + 4] = {"kind": "board", "stage": 2}
	covered = _a2_runtime_select(renderer, map, block, seen)
	if covered.has(6 * w + 4):
		push_error("A2 runtime replaced a boarded window")
		return false
	map.overlays[6 * w + 4] = {"kind": "scrap", "stage": 0}
	covered = _a2_runtime_select(renderer, map, block, seen)
	if covered.has(6 * w + 4):
		push_error("A2 runtime misread scrap as broken glass")
		return false
	map.overlays.erase(6 * w + 4)
	# Door open/closed source choice and no-overlay broken/open state.
	map.overlays[6 * w + 5] = {"kind": "door", "open": false, "stage": 0}
	_a2_runtime_select(renderer, map, block, seen)
	var has_closed: bool = false
	for piece_v3 in renderer.get("_a2_wall_pieces"):
		has_closed = has_closed or String((piece_v3 as Dictionary).get("key", "")) == "a2_door_closed"
	if not has_closed:
		push_error("A2 runtime missed the closed doorway state")
		return false
	map.overlays[6 * w + 5] = {"kind": "door", "open": true, "stage": 0}
	_a2_runtime_select(renderer, map, block, seen)
	var has_open: bool = false
	for piece_v4 in renderer.get("_a2_wall_pieces"):
		has_open = has_open or String((piece_v4 as Dictionary).get("key", "")) == "a2_door_open"
	if not has_open:
		push_error("A2 runtime missed the open doorway state")
		return false
	map.overlays.erase(6 * w + 5)
	_a2_runtime_select(renderer, map, block, seen)
	has_open = false
	for piece_v5 in renderer.get("_a2_wall_pieces"):
		has_open = has_open or String((piece_v5 as Dictionary).get("key", "")) == "a2_door_open"
	if not has_open:
		push_error("A2 runtime missed the no-overlay open/broken doorway fallback")
		return false
	# Brick lacks openings/corners, so those source modules must not replace the generated faces.
	renderer.set("_looks", {0: {"wall": "brick"}})
	covered = _a2_runtime_select(renderer, map, block, seen)
	if covered.has(6 * w + 4) or covered.has(6 * w + 5):
		push_error("A2 brick runtime replaced an unsupported opening")
		return false
	if not covered.has(6 * w + 2) or not covered.has(6 * w + 8):
		push_error("A2 brick runtime dropped its source-supported west/east run end tiles")
		return false
	# Removing one declared module cannot reserve a tile that will fall back to generated art.
	var missing: Dictionary = block.duplicate(true)
	var missing_render: Dictionary = (missing["wall_modules"] as Dictionary)["render"] as Dictionary
	missing_render.erase("middle")
	renderer.set("_looks", {0: {"wall": "render"}})
	covered = _a2_runtime_select(renderer, map, missing, seen)
	if covered.has(2 * w + 4):
		push_error("A2 runtime covered a tile whose selected asset key is missing")
		return false
	# A notched footprint and an owner hidden from the current cone draw no A2 modules.
	map.tiles[4 * w + 2] = SimTileMap.Tile.Floor
	covered = _a2_runtime_select(renderer, map, block, seen)
	if not covered.is_empty():
		push_error("A2 runtime invented a rectangular ring over a notched footprint")
		return false
	map.tiles[4 * w + 2] = SimTileMap.Tile.Wall
	var owner_only := FakeSeen.new()
	owner_only.tiles[Vector2i(2, 2)] = true
	covered = _a2_runtime_select(renderer, map, block, owner_only)
	if not covered.has(2 * w + 2) or covered.has(2 * w + 3):
		push_error("A2 runtime did not gate each piece by its seen logical owner")
		return false
	print("A2_RUNTIME OK 7x5 placements, L support reservations, continuous half-tile legs, state/opening fallback, missing keys, ring rejection, owner/destination clipping and equal-foot body order are exercised through main.gd")
	renderer.free()
	return true


func _the_look_resolves_and_can_say_no() -> bool:
	var tree: Dictionary = ContentLoader.load_tree()
	var templates: Array = SimWorldgen.templates_of(tree)
	var annex_patch: Variant = SimTileMap.load_patch_from_content(tree, SimWorldgen.ANNEX_PATCH_ID)
	if templates.is_empty():
		push_error("no building templates ship; LOOK has nothing to judge")
		return false
	if not (annex_patch is Dictionary):
		push_error("no %s patch in content; the annex has no look to judge" % SimWorldgen.ANNEX_PATCH_ID)
		return false

	var entries: Array = []
	for t in templates:
		var td: Dictionary = t as Dictionary
		entries.append({"id": String(td.get("id", "")), "look": td.get("look", {})})
	entries.append({"id": SimWorldgen.ANNEX_PATCH_ID, "look": (annex_patch as Dictionary).get("look", {})})

	# The membership check first: enum enforcement content_validator.gd never reaches, since
	# `look` is a top-level key whose sub-fields the shallow validator does not recurse into.
	for e in entries:
		var ed: Dictionary = e as Dictionary
		var look: Dictionary = (ed["look"] as Dictionary) if ed["look"] is Dictionary else {}
		if not ROOFS.has(String(look.get("roof", ""))) or not WALLS.has(String(look.get("wall", ""))):
			push_error("%s: look %s carries no look, or names a material outside the enum" % [String(ed["id"]), str(look)])
			return false
	print("LOOK ENUM OK %d templates and the annex all name roof in %s, wall in %s" % [entries.size(), str(ROOFS), str(WALLS)])

	var world: Variant = World.new(_fixture())
	var dress: Dictionary = Dressing.block_of(world)
	if dress.is_empty():
		push_error("dressing.street resolves no block; nothing below it can resolve art")
		return false

	var resolved: int = 0
	for e2 in entries:
		var ed2: Dictionary = e2 as Dictionary
		var problem: String = _material_resolves(dress, ed2["look"] as Dictionary)
		if not problem.is_empty():
			push_error("%s: %s" % [String(ed2["id"]), problem])
			return false
		resolved += 1

	var native: int = int(CameraUtil.ART_NATIVE)
	var want := Vector2i(native, native)
	for kind in ["window", "door", "garage"]:
		var key: String = Dressing.face_key(dress, kind)
		var tex: Variant = Appearance.resolve(key)
		if tex == null:
			push_error("face '%s' (%s) resolves no picture" % [key, kind])
			return false
		if Vector2i((tex as Texture2D).get_size()) != want:
			push_error("face '%s' is %s, not %s" % [key, str((tex as Texture2D).get_size()), str(want)])
			return false

	# True negatives, through the same predicate as the real templates above.
	if _material_resolves(dress, {"roof": "thatch", "wall": "timber"}).is_empty():
		push_error("a fabricated look naming 'thatch' resolved cleanly; the table refusal is dead")
		return false
	if _material_resolves(dress, {}).is_empty():
		push_error("a template with no look resolved cleanly; the absence refusal is dead")
		return false
	var broken: Dictionary = dress.duplicate(true)
	var broken_walls: Dictionary = broken["walls"] as Dictionary
	var broken_timber: Dictionary = broken_walls["timber"] as Dictionary
	broken_timber["cap"] = "wall_no_such_file"
	if _material_resolves(broken, {"roof": "shingle", "wall": "timber"}).is_empty():
		push_error("a wall cap naming a nonexistent file resolved cleanly; resolve()'s null is not reaching this lane")
		return false

	_stash["look_entries"] = resolved
	print("LOOK OK %d templates + the annex resolve wall cap/face, roof slope(s) and the 3 faces (%d entries); thatch, a missing look and a bad filename all refused" % [templates.size(), resolved])
	return true


# --- lane 2: FACADE ----------------------------------------------------------------------------


func _the_facade_reads_the_street_and_can_say_no() -> bool:
	var map: Variant = _facade_map()
	var thresholds: Dictionary = Appearance.door_tiles(map)
	if thresholds.size() != 3:
		push_error("the hand map's doorways resolved %d thresholds, want 3 (one door, two garage tiles)" % thresholds.size())
		return false

	var south_wall: Array = [Vector2i(1, 4), Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4), Vector2i(9, 4)]
	for t in south_wall:
		if RoofLook.facade_at(map, thresholds, t.x, t.y) != RoofLook.Face.WALL:
			push_error("south wall tile %s did not read WALL" % str(t))
			return false
	if RoofLook.facade_at(map, thresholds, 3, 4) != RoofLook.Face.WINDOW:
		push_error("the south window did not read WINDOW")
		return false
	if RoofLook.facade_at(map, thresholds, 2, 4) != RoofLook.Face.DOOR:
		push_error("the south door did not read DOOR")
		return false
	for t2 in [Vector2i(7, 4), Vector2i(8, 4)]:
		if RoofLook.facade_at(map, thresholds, t2.x, t2.y) != RoofLook.Face.GARAGE:
			push_error("garage tile %s did not read GARAGE" % str(t2))
			return false

	var north_row: Array = [
		Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1),
		Vector2i(6, 1), Vector2i(7, 1), Vector2i(8, 1), Vector2i(9, 1),
	]
	for t3 in north_row:
		if RoofLook.facade_at(map, thresholds, t3.x, t3.y) != RoofLook.Face.NONE:
			push_error("north-row tile %s did not read NONE" % str(t3))
			return false
	if RoofLook.facade_at(map, thresholds, 3, 2) != RoofLook.Face.NONE:
		push_error("the interior partition read a face")
		return false
	if RoofLook.facade_at(map, thresholds, 8, 8) != RoofLook.Face.NONE:
		push_error("open ground read a face")
		return false
	if RoofLook.facade_at(map, thresholds, 5, 9) != RoofLook.Face.NONE:
		push_error("the map's bottom row read a face; south of it is out of bounds")
		return false
	if RoofLook.facade_at(map, thresholds, 8, 6) != RoofLook.Face.WALL:
		push_error("a wall with Low cover to its south did not read WALL")
		return false

	# Sabotage: every south-row tile's true answer is non-NONE; probing the row above it (whose
	# south neighbour IS the real wall/door/window) must differ every time, or this table is not
	# actually reading the row the plan named.
	var probed: int = 0
	var south_all: Array = south_wall + [Vector2i(3, 4), Vector2i(2, 4), Vector2i(7, 4), Vector2i(8, 4)]
	for t4 in south_all:
		var real: int = RoofLook.facade_at(map, thresholds, t4.x, t4.y)
		var probe: int = RoofLook.facade_at(map, thresholds, t4.x, t4.y - 1)
		if probe == real:
			push_error("the ty-1 probe at %s answered the same as the real row (%d); the sabotage is dead" % [str(t4), real])
			return false
		probed += 1

	_stash["thresholds"] = thresholds.size()
	print("FACADE OK %d thresholds; south wall/window/door/garage all read, north row/partition/open-ground/edge all NONE, cover-not-shelter reads WALL; the ty-1 probe differs on all %d south-row tiles" % [thresholds.size(), probed])
	return true


# --- lane 3: WALL FACE ---------------------------------------------------------------------


func _the_wall_face_and_south_open_agree_with_the_map() -> bool:
	var map: Variant = _facade_map()

	var faced: Array = [Vector2i(1, 4), Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4), Vector2i(9, 4)]
	for t in faced:
		if not RoofLook.wall_face_at(map, t.x, t.y):
			push_error("south wall/window %s did not draw its face" % str(t))
			return false

	var capped: Array = [
		Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1),
		Vector2i(6, 1), Vector2i(7, 1), Vector2i(8, 1), Vector2i(9, 1),
		Vector2i(1, 2), Vector2i(1, 3), Vector2i(5, 2), Vector2i(5, 3),
		Vector2i(6, 2), Vector2i(6, 3), Vector2i(9, 2), Vector2i(9, 3),
		Vector2i(3, 2),
	]
	for t2 in capped:
		if RoofLook.wall_face_at(map, t2.x, t2.y):
			push_error("wall %s drew a face; its south neighbour is not open ground" % str(t2))
			return false
	if RoofLook.wall_face_at(map, 8, 8):
		push_error("a Floor tile drew a wall face")
		return false

	if RoofLook.south_open(map, 5, 9):
		push_error("south_open is true past the map's south edge")
		return false
	if RoofLook.south_open(map, 2, 1):
		push_error("south_open is true where the south neighbour is indoors")
		return false
	if RoofLook.south_open(map, 1, 2):
		push_error("south_open is true where the south neighbour is solid")
		return false
	if not RoofLook.south_open(map, 1, 4):
		push_error("south_open is false over open outdoor street")
		return false
	if not RoofLook.south_open(map, 8, 6):
		push_error("south_open is false where the south neighbour is Low cover, not solid")
		return false

	print("WALL FACE OK %d south wall/window tiles draw their face, %d capped tiles and a Floor tile do not; south_open is true only past a solid, indoors or out-of-bounds neighbour" % [faced.size(), capped.size() + 1])
	return true


# --- lane 4: ROOF --------------------------------------------------------------------------


func _seen_of(coords: Array) -> FakeSeen:
	var s := FakeSeen.new()
	for c in coords:
		s.tiles[c] = true
	return s


func _same_tiles(got: Array, want: Array) -> bool:
	if got.size() != want.size():
		return false
	var g: Dictionary = {}
	for t in got:
		g[t] = true
	for t2 in want:
		if not g.has(t2):
			return false
	return true


func _the_roof_covers_what_the_survivor_cannot_see() -> bool:
	var map: Variant = _facade_map()
	var whole_bounds: Dictionary = {"minX": 0.0, "minY": 0.0, "maxX": 9.0, "maxY": 9.0}
	var shell1_interior: Array = [
		Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3),
	]

	# (a) outside, seeing the south row and, through the door, one interior tile.
	var seen_a: FakeSeen = _seen_of([
		Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4), Vector2i(2, 3),
	])
	var got_a: Array[Vector2i] = RoofLook.roof_tiles(map, seen_a, whole_bounds, Vector2i(2, 6))
	var want_a: Array = [Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(3, 3), Vector2i(4, 3)]
	if not _same_tiles(got_a, want_a):
		push_error("case (a) roofed %s, want %s" % [str(got_a), str(want_a)])
		return false

	# (b) the same sightline, but the player stands inside the first shell: zero for it.
	var got_b: Array[Vector2i] = RoofLook.roof_tiles(map, seen_a, whole_bounds, Vector2i(3, 3))
	if not got_b.is_empty():
		push_error("case (b) roofed %s with the player inside the shell; want none" % str(got_b))
		return false

	# (c) nothing seen at all. This IS the known() test as a standing negative: drop known()
	# from roof_tiles and this case returns shell1_interior's 6 tiles instead of none.
	var seen_c := FakeSeen.new()
	var got_c: Array[Vector2i] = RoofLook.roof_tiles(map, seen_c, whole_bounds, Vector2i(2, 6))
	if not got_c.is_empty():
		push_error("case (c) roofed %s with nothing seen; the known() gate is not being asked" % str(got_c))
		return false

	# (d) no observer at all.
	var got_d: Array[Vector2i] = RoofLook.roof_tiles(map, null, whole_bounds, Vector2i(2, 6))
	if not got_d.is_empty():
		push_error("case (d) roofed %s with seen == null" % str(got_d))
		return false

	# (e) both shells known, bounds excludes the second: it must contribute nothing.
	var seen_e: FakeSeen = _seen_of([
		Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4),
		Vector2i(6, 4), Vector2i(7, 4), Vector2i(8, 4), Vector2i(9, 4),
	])
	var narrow_bounds: Dictionary = {"minX": 0.0, "minY": 0.0, "maxX": 5.0, "maxY": 9.0}
	var got_e: Array[Vector2i] = RoofLook.roof_tiles(map, seen_e, narrow_bounds, Vector2i(2, 6))
	if not _same_tiles(got_e, shell1_interior):
		push_error("case (e) roofed %s, want exactly shell1's interior %s" % [str(got_e), str(shell1_interior)])
		return false
	for t in got_e:
		if t.x >= 6:
			push_error("case (e) roofed %s from the out-of-bounds second shell" % str(t))
			return false

	_stash["roof_a"] = got_a.size()
	_stash["roof_e"] = got_e.size()
	print("ROOF OK case (a) %d of %d shell1 tiles roofed with the door-seen one excluded, (b) 0 with the player inside, (c) 0 with nothing seen (the known() negative), (d) 0 with no observer, (e) %d in-bounds and none of the excluded shell" % [got_a.size(), shell1_interior.size(), got_e.size()])
	return true


# --- lane 5: SLOPE -------------------------------------------------------------------------


func _the_slope_and_pitch_answer_correctly() -> bool:
	var rect4 := Rect2i(0, 0, 5, 4)
	var want4: Array = [RoofLook.Slope.NORTH, RoofLook.Slope.NORTH, RoofLook.Slope.SOUTH, RoofLook.Slope.SOUTH]
	for ty in 4:
		if RoofLook.slope_of(rect4, ty, true) != int(want4[ty]):
			push_error("slope_of(4-tall rect, %d, true) = %d, want %d" % [ty, RoofLook.slope_of(rect4, ty, true), int(want4[ty])])
			return false

	var rect5 := Rect2i(0, 0, 5, 5)
	var want5: Array = [
		RoofLook.Slope.NORTH, RoofLook.Slope.NORTH, RoofLook.Slope.SOUTH, RoofLook.Slope.SOUTH, RoofLook.Slope.SOUTH,
	]
	for ty2 in 5:
		if RoofLook.slope_of(rect5, ty2, true) != int(want5[ty2]):
			push_error("slope_of(5-tall rect, %d, true) = %d, want %d" % [ty2, RoofLook.slope_of(rect5, ty2, true), int(want5[ty2])])
			return false

	for ty3 in 4:
		if RoofLook.slope_of(rect4, ty3, false) != RoofLook.Slope.FLAT:
			push_error("slope_of(.., %d, false) is not FLAT" % ty3)
			return false

	if not Dressing.roof_pitched({"roofs": {"x": {"n": "a", "s": "b"}}}, "x"):
		push_error("a material declaring n and s did not read pitched")
		return false
	if Dressing.roof_pitched({"roofs": {"y": {"flat": "c"}}}, "y"):
		push_error("a flat-only material read pitched")
		return false
	if Dressing.roof_pitched({}, "x"):
		push_error("a block with no roofs table read pitched")
		return false

	var pitched_block: Dictionary = {"roofs": {"x": {"n": "a", "s": "b"}}}
	if Dressing.roof_key(pitched_block, "x", RoofLook.Slope.NORTH) != "a":
		push_error("roof_key(north) did not resolve 'a'")
		return false
	if Dressing.roof_key(pitched_block, "x", RoofLook.Slope.SOUTH) != "b":
		push_error("roof_key(south) did not resolve 'b'")
		return false
	var flat_block: Dictionary = {"roofs": {"y": {"flat": "c"}}}
	if Dressing.roof_key(flat_block, "y", RoofLook.Slope.FLAT) != "c":
		push_error("roof_key(flat) did not resolve 'c'")
		return false
	if not Dressing.roof_key(pitched_block, "nosuchmaterial", RoofLook.Slope.NORTH).is_empty():
		push_error("roof_key resolved a key for a material with no table entry")
		return false

	print("SLOPE OK ridge at h/2 on a 4- and a 5-tall rect (NORTH before it, SOUTH from it), unpitched is FLAT throughout; roof_pitched is true only with n+s, roof_key resolves n/s/flat and refuses an unknown material")
	return true


# --- lane 6: INDEX -------------------------------------------------------------------------


func _the_building_index_maps_tiles_to_buildings() -> bool:
	var map: Variant = _facade_map()
	var w: int = int(map.w)
	var idx: PackedInt32Array = RoofLook.building_index(map)

	for ty in range(1, 5):
		for tx in range(1, 6):
			if idx[ty * w + tx] != 0:
				push_error("shell1 tile (%d,%d) indexes to %d, not 0" % [tx, ty, idx[ty * w + tx]])
				return false
	for ty2 in range(1, 5):
		for tx2 in range(6, 10):
			if idx[ty2 * w + tx2] != 1:
				push_error("shell2 tile (%d,%d) indexes to %d, not 1" % [tx2, ty2, idx[ty2 * w + tx2]])
				return false
	for open_t in [Vector2i(8, 8), Vector2i(2, 6)]:
		if idx[open_t.y * w + open_t.x] != RoofLook.INDEX_NONE:
			push_error("open ground %s indexes to %d, not INDEX_NONE" % [str(open_t), idx[open_t.y * w + open_t.x]])
			return false

	map.anchors = {"annex": {"x": 0, "y": 6, "w": 4, "h": 4}}
	var idx2: PackedInt32Array = RoofLook.building_index(map)
	for ty3 in range(6, 10):
		for tx3 in range(0, 4):
			if idx2[ty3 * w + tx3] != RoofLook.INDEX_ANNEX:
				push_error("annex tile (%d,%d) indexes to %d, not INDEX_ANNEX" % [tx3, ty3, idx2[ty3 * w + tx3]])
				return false
	var annex_rect: Rect2i = RoofLook.rect_of(map, RoofLook.INDEX_ANNEX)
	if annex_rect != Rect2i(0, 6, 4, 4):
		push_error("rect_of(INDEX_ANNEX) is %s, not the anchor rect" % str(annex_rect))
		return false
	var ids: PackedInt32Array = RoofLook.indices_of(map)
	if ids.size() != 3 or ids[0] != 0 or ids[1] != 1 or ids[2] != RoofLook.INDEX_ANNEX:
		push_error("indices_of is %s, not [0, 1, INDEX_ANNEX]" % str(ids))
		return false
	if not RoofLook.building_index(null).is_empty():
		push_error("building_index(null) is not empty")
		return false

	print("INDEX OK shell1/shell2 tiles index to 0/1, open ground to INDEX_NONE; the annex anchor indexes to INDEX_ANNEX, rect_of and indices_of agree, a null map answers empty")
	return true


# --- lane 7: PLAYED ------------------------------------------------------------------------


func _the_shipped_suburb_roofs_what_it_should() -> bool:
	var boot: Dictionary = SimBoot.playable(CANON_SEED, GATE_SIZE)
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	world.vision.refresh(world, map)
	var seen: Variant = world.vision.tiles_for(int(world.player))
	if seen == null:
		push_error("the player's vision has not refreshed; PLAYED has nothing to judge")
		return false

	var w: int = int(map.w)
	var h: int = int(map.h)
	var bounds: Dictionary = {"minX": 0.0, "minY": 0.0, "maxX": float(w), "maxY": float(h)}
	var pos: Dictionary = world.components.get_component(int(world.player), "position")
	var player_tile := Vector2i(floori(float(pos["x"])), floori(float(pos["y"])))

	var indoor_total: int = 0
	var indoor_seen: int = 0
	for ty in h:
		for tx in w:
			if SimTileMap.is_indoors(map, tx, ty):
				indoor_total += 1
				if (seen as Object).call("has_tile", tx, ty):
					indoor_seen += 1
	if indoor_total == 0:
		push_error("the shipped suburb at %d placed no indoor tile; PLAYED has nothing to judge" % GATE_SIZE)
		return false

	var index: PackedInt32Array = RoofLook.building_index(map)
	var roofed: Array[Vector2i] = RoofLook.roof_tiles(map, seen, bounds, player_tile)
	if roofed.is_empty():
		push_error("roof_tiles returned nothing on the shipped suburb@%d seed %d" % [GATE_SIZE, CANON_SEED])
		return false
	for t in roofed:
		if not SimTileMap.is_indoors(map, t.x, t.y):
			push_error("roofed tile %s is not indoors" % str(t))
			return false
		if (seen as Object).call("has_tile", t.x, t.y):
			push_error("roofed tile %s is in the seen set" % str(t))
			return false
		if index[t.y * w + t.x] == RoofLook.INDEX_NONE:
			push_error("roofed tile %s lies in no known building" % str(t))
			return false
	if roofed.size() + indoor_seen > indoor_total:
		push_error("%d roofed + %d seen-indoor exceeds %d total indoor tiles" % [roofed.size(), indoor_seen, indoor_total])
		return false

	var looked: int = 0
	for idx in RoofLook.indices_of(map):
		var look: Dictionary = RoofLook.look_of(world, idx)
		if look.is_empty():
			push_error("building index %d resolves no look" % idx)
			return false
		looked += 1

	_stash["played_roofed"] = roofed.size()
	_stash["played_indoor"] = indoor_total
	print("PLAYED OK suburb@%d seed %d: %d roofed of %d indoor tiles (%d seen), every one indoors/unseen/known; %d buildings all resolve a look" % [GATE_SIZE, CANON_SEED, roofed.size(), indoor_total, indoor_seen, looked])
	return true


# --- lane 8: MOOD --------------------------------------------------------------------------


func _image_stats(img: Image, key: String) -> Dictionary:
	var iw: int = img.get_width()
	var ih: int = img.get_height()
	var sum := Vector3.ZERO
	var opaque := true
	for y in ih:
		for x in iw:
			var c: Color = img.get_pixel(x, y)
			if c.a < 0.999:
				opaque = false
			sum += Vector3(c.r, c.g, c.b)
	var mean: Vector3 = sum / float(iw * ih)
	return {"key": key, "opaque": opaque, "mean": Color(mean.x, mean.y, mean.z, 1.0)}


func _decode_stats(key: String) -> Dictionary:
	var tex: Variant = Appearance.resolve(key)
	if tex == null:
		return {}
	var img: Image = (tex as Texture2D).get_image()
	if img == null:
		return {}
	return _image_stats(img, key)


func _region_stats(key: String, x0: int, y0: int, rw: int, rh: int) -> Dictionary:
	var tex: Variant = Appearance.resolve(key)
	if tex == null:
		return {}
	var img: Image = (tex as Texture2D).get_image()
	if img == null:
		return {}
	var sum := Vector3.ZERO
	for y in rh:
		for x in rw:
			var c: Color = img.get_pixel(x0 + x, y0 + y)
			sum += Vector3(c.r, c.g, c.b)
	var mean: Vector3 = sum / float(rw * rh)
	return {"mean": Color(mean.x, mean.y, mean.z, 1.0)}


func _opaque_row_bounds(img: Image) -> Dictionary:
	var min_row: int = 999999
	var max_row: int = -1
	var count: int = 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				min_row = mini(min_row, y)
				max_row = maxi(max_row, y)
				count += 1
	return {"min": min_row, "max": max_row, "count": count}


func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _rgb_distance(a: Color, b: Color) -> float:
	var dr: float = a.r - b.r
	var dg: float = a.g - b.g
	var db: float = a.b - b.b
	return sqrt(dr * dr + dg * dg + db * db)


func _warm_ok(c: Color) -> bool:
	return c.r - c.b >= WARM_MARGIN


func _clears_grounds(luma: float, grounds: Array[Color]) -> bool:
	for g in grounds:
		if absf(luma - _luma(g)) < GROUND_CLEAR_MARGIN:
			return false
	return true


func _the_art_is_warm_and_reads_against_the_ground() -> bool:
	Appearance.forget()
	var world: Variant = World.new(_fixture())
	var dress: Dictionary = Dressing.block_of(world)
	if dress.is_empty():
		push_error("dressing.street resolves no block; MOOD has nothing to judge")
		return false

	# The grounds this generated art was authored against (GROUND_CLEAR_MARGIN's comment says why
	# they are not the pack's).
	var grounds: Array[Color] = []
	for c in Palette.GENERATOR_SURFACES:
		grounds.append(c as Color)
	grounds.append(Palette.GENERATOR_GROUNDS["sidewalk"] as Color)
	grounds.append(Palette.GENERATOR_GROUNDS["indoorFloor"] as Color)

	var judged: int = 0
	var walls: Dictionary = dress.get("walls", {}) as Dictionary
	for material in walls.keys():
		var entry: Dictionary = walls[material] as Dictionary
		var cap_key: String = String(entry.get("cap", ""))
		var face_key: String = String(entry.get("face", ""))
		var cap_stats: Dictionary = _decode_stats(cap_key)
		if cap_stats.is_empty():
			push_error("wall cap '%s' (material %s) resolves no picture" % [cap_key, material])
			return false
		var face_stats: Dictionary = _decode_stats(face_key)
		if face_stats.is_empty():
			push_error("wall face '%s' (material %s) resolves no picture" % [face_key, material])
			return false
		for stats in [cap_stats, face_stats]:
			var mean: Color = stats["mean"] as Color
			if not bool(stats["opaque"]):
				push_error("%s has a transparent pixel; a wall is solid mass" % String(stats["key"]))
				return false
			if not _warm_ok(mean):
				push_error("%s mean %s is not warm (r-b < %.2f)" % [String(stats["key"]), str(mean), WARM_MARGIN])
				return false
			if not _clears_grounds(_luma(mean), grounds):
				push_error("%s luma %.3f does not clear the ground family by %.2f" % [String(stats["key"]), _luma(mean), GROUND_CLEAR_MARGIN])
				return false
			judged += 1
		var face_top: Dictionary = _region_stats(face_key, 0, 0, 32, 20)
		var d: float = _rgb_distance(face_top["mean"] as Color, cap_stats["mean"] as Color)
		if d > FACE_TOP_MEAN_MAX:
			push_error("%s top 20 rows sit %.3f from the cap's mean, over %.2f" % [face_key, d, FACE_TOP_MEAN_MAX])
			return false

	var roofs: Dictionary = dress.get("roofs", {}) as Dictionary
	for material2 in roofs.keys():
		var entry2: Dictionary = roofs[material2] as Dictionary
		for slope_name in entry2.keys():
			var key: String = String(entry2[slope_name])
			var stats2: Dictionary = _decode_stats(key)
			if stats2.is_empty():
				push_error("roof key '%s' (material %s, %s) resolves no picture" % [key, material2, slope_name])
				return false
			var mean2: Color = stats2["mean"] as Color
			if not bool(stats2["opaque"]):
				push_error("%s has a transparent pixel; a roof is solid mass" % key)
				return false
			if not _warm_ok(mean2):
				push_error("%s mean %s is not warm" % [key, str(mean2)])
				return false
			if not _clears_grounds(_luma(mean2), grounds):
				push_error("%s luma %.3f does not clear the ground family by %.2f" % [key, _luma(mean2), GROUND_CLEAR_MARGIN])
				return false
			judged += 1

	var faces: Dictionary = dress.get("faces", {}) as Dictionary
	var face_floor: Dictionary = {"window": 20, "door": 16, "garage": 16}
	for kind in face_floor.keys():
		var fkey: String = String(faces.get(kind, ""))
		var tex: Variant = Appearance.resolve(fkey)
		if tex == null:
			push_error("face '%s' (%s) resolves no picture" % [fkey, kind])
			return false
		var img: Image = (tex as Texture2D).get_image()
		var rows: Dictionary = _opaque_row_bounds(img)
		if int(rows["count"]) == 0:
			push_error("face '%s' has no opaque pixels" % fkey)
			return false
		if int(rows["min"]) < int(face_floor[kind]):
			push_error("face '%s' has an opaque pixel at row %d, under the row-%d floor" % [fkey, int(rows["min"]), int(face_floor[kind])])
			return false
		judged += 1

	# True negatives, through the same predicates as the real art above.
	var grey_img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	grey_img.fill(Color("#4a4a4a"))
	var grey_stats: Dictionary = _image_stats(grey_img, "fixture-grey")
	if _warm_ok(grey_stats["mean"] as Color):
		push_error("a flat grey fixture passes the warmth pin; MOOD cannot say no")
		return false

	var grass_colour: Color = Palette.GENERATOR_SURFACES[SimSurface.Surface.Grass] as Color
	var grass_img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	grass_img.fill(grass_colour)
	var grass_stats: Dictionary = _image_stats(grass_img, "fixture-grass")
	if _clears_grounds(_luma(grass_stats["mean"] as Color), grounds):
		push_error("a fixture filled with the grass tint clears the ground family; the clearance pin cannot say no")
		return false

	var overlay := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	overlay.set_pixel(5, 2, Color(1, 1, 1, 1))
	var overlay_rows: Dictionary = _opaque_row_bounds(overlay)
	if int(overlay_rows["min"]) >= 20:
		push_error("an overlay with a pixel at row 2 passed the row-20 floor; MOOD cannot say no")
		return false

	_stash["mood_keys"] = judged
	print("MOOD OK %d material keys (walls, roofs, faces) decode opaque and warm, clear the ground family by %.2f, faces match their cap within %.2f, window/door/garage rows floor at 20/16; a grey fixture, a grass-tinted fixture and a row-2 overlay all refused" % [judged, GROUND_CLEAR_MARGIN, FACE_TOP_MEAN_MAX])
	return true


# --- lane 9: SOCKETS -----------------------------------------------------------------------


# The first needle missing from `body`, or "" when all are present. Proved on a fabricated body
# below before it is trusted on the real one -- check_topdown.gd's convention: a scanner that
# answers "" for everything is a gate that cannot fail.
func _missing_needle(body: String, needles: Array) -> String:
	for n in needles:
		if not body.contains(String(n)):
			return String(n)
	return ""


func _the_draw_loop_reaches_every_helper() -> bool:
	var proof: String = _missing_needle("no keywords appear anywhere in this line", ["TOTALLY_ABSENT_TOKEN"])
	if proof.is_empty():
		push_error("the needle scanner found nothing missing in a fixture missing everything; it cannot say no")
		return false

	var district: String = _function_body(MAIN_GD, "_draw_district")
	if district.is_empty():
		push_error("could not read _draw_district out of %s -- SOCKETS had nothing to judge" % MAIN_GD)
		return false
	var m1: String = _missing_needle(
		district, ["_draw_wall_art(", "_draw_door_face(", "_draw_roofs(", "_draw_solid_tile(rect, col, tx, ty)"]
	)
	if not m1.is_empty():
		push_error("_draw_district does not contain %s" % m1)
		return false

	var at_scatter: int = district.find("_draw_scatter(")
	var at_roofs: int = district.find("_draw_roofs(")
	var at_props: int = district.find("_draw_props()")
	if at_scatter < 0 or at_roofs < 0 or at_props < 0 or not (at_scatter < at_roofs and at_roofs < at_props):
		push_error("_draw_district draws roofs out of order: scatter %d, roofs %d, props %d" % [at_scatter, at_roofs, at_props])
		return false
	# The order predicate's own true negative: a reversed sequence must not read as ascending.
	if at_props < at_roofs and at_roofs < at_scatter:
		push_error("the order check accepted a reversed sequence; it cannot say no")
		return false

	var wall_art: String = _function_body(MAIN_GD, "_draw_wall_art")
	var m2: String = _missing_needle(
		wall_art, ["RoofLook.wall_face_at(", "Dressing.wall_key(", "Appearance.resolve(", "draw_texture_rect(", "Dressing.face_key("]
	)
	if not m2.is_empty():
		push_error("_draw_wall_art does not contain %s" % m2)
		return false

	var door_face: String = _function_body(MAIN_GD, "_draw_door_face")
	var m3: String = _missing_needle(door_face, ["RoofLook.facade_at(", "Dressing.face_key("])
	if not m3.is_empty():
		push_error("_draw_door_face does not contain %s" % m3)
		return false

	var roofs_fn: String = _function_body(MAIN_GD, "_draw_roofs")
	var m4: String = _missing_needle(
		roofs_fn, ["RoofLook.roof_tiles(", "RoofLook.slope_of(", "Dressing.roof_key(", "Palette.COLOURS[\"roof\"]"]
	)
	if not m4.is_empty():
		push_error("_draw_roofs does not contain %s" % m4)
		return false

	var idx_fn: String = _function_body(MAIN_GD, "_building_index")
	if not idx_fn.contains("RoofLook.building_index("):
		push_error("_building_index does not call RoofLook.building_index")
		return false
	var a2_selector: String = _function_body(MAIN_GD, "_a2_wall_modules")
	var a2_entities: String = _function_body(MAIN_GD, "_draw_entities")
	var a2_piece: String = _function_body(MAIN_GD, "_draw_a2_wall_piece")
	if _missing_needle(district, ["_a2_wall_modules(", "a2_wall_tiles.has("]).is_empty() == false:
		push_error("_draw_district does not consume A2 coverage before the generated fallback")
		return false
	if _missing_needle(a2_selector, ["Dressing.wall_modules(", "_a2_supported_ring(", "_a2_corner_supported(", "_add_a2_leg_fragments("]).is_empty() == false:
		push_error("A2 module selection is disconnected from content, topology, corner guards or continuous legs")
		return false
	if not _a2_entity_path_fault(a2_entities).is_empty():
		push_error("A2 entity reader %s" % _a2_entity_path_fault(a2_entities))
		return false
	var early_append: String = a2_entities.replace("items.append_array(_a2_wall_pieces)\n", "")
	var focal_loop: int = early_append.find("var focal_points: Array[Vector2] = []")
	if focal_loop >= 0:
		early_append = early_append.insert(focal_loop, "items.append_array(_a2_wall_pieces)\n")
	if _a2_entity_path_fault(a2_entities.replace("RoofLook.a2_item_before", "body_before_wall")).is_empty() or _a2_entity_path_fault(a2_entities.replace("items.append_array(_a2_wall_pieces)", "")).is_empty() or _a2_entity_path_fault(a2_entities.replace("_draw_a2_wall_piece(", "_draw_unrelated_piece(")).is_empty() or _a2_entity_path_fault(early_append).is_empty():
		push_error("A2 entity reader accepted a missing append, exact sorter, or draw dispatch")
		return false
	if not _a2_wall_drawer_fault(a2_piece).is_empty() or _a2_wall_drawer_fault(a2_piece.replace("draw_texture_rect_region(", "draw_texture_rect_region_removed(")).is_empty():
		push_error("A2 wall blit reader %s" % _a2_wall_drawer_fault(a2_piece))
		return false
	var fragments_fn: String = _function_body(ROOF_GD, "a2_visible_fragments")
	if _missing_needle(fragments_fn, ["seen as Object", "world_rect.intersection("]).is_empty() == false:
		push_error("A2 fragment helper does not intersect geometry with each currently seen tile")
		return false
	var corner_fn: String = _function_body(MAIN_GD, "_a2_corner_supported")
	if _missing_needle(corner_fn, ["SimTileMap.Tile.Wall", "overlay_at(", "index["]).is_empty() == false:
		push_error("A2 full corners do not require plain, unoverlaid owned support walls")
		return false

	if not Palette.COLOURS.has("roof"):
		push_error("Palette.COLOURS has no 'roof' fallback for a material with no art")
		return false

	print("SOCKETS OK _draw_district selects A2 pieces and preserves the solid fallback; supported rings/corners reach content keys; clipped A2 fragments draw through the body depth sort; roofs remain between scatter and props; Palette.COLOURS[\"roof\"] stands")
	return true


# --- readers -------------------------------------------------------------------------------


# The source text of one function, from its `func` line to the next top-level `func` -- the
# check_topdown.gd / check_weather.gd precedent: a CanvasItem draw pass cannot run headless.
func _function_body(path: String, name: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var lines: PackedStringArray = f.get_as_text().split("\n")
	var out: String = ""
	var inside: bool = false
	for line in lines:
		if line.begins_with("func %s(" % name) or line.begins_with("static func %s(" % name):
			inside = true
			continue
		if inside and (line.begins_with("func ") or line.begins_with("static func ")):
			break
		if inside:
			out += line + "\n"
	return out


func _a2_entity_path_fault(source: String) -> String:
	var code: String = ""
	for line in source.split("\n"):
		if not String(line).strip_edges().begins_with("#"):
			code += String(line) + "\n"
	for needle in ["items.append_array(_a2_wall_pieces)", "items.sort_custom(RoofLook.a2_item_before)", "_draw_a2_wall_piece("]:
		if not code.contains(needle):
			return "missing real reader %s" % needle
	if code.find("items.append_array(_a2_wall_pieces)") < code.find("focal_points.append("):
		return "wall modules enter the body-only Focal scan"
	return ""


func _a2_wall_drawer_fault(source: String) -> String:
	var code: String = ""
	for line in source.split("\n"):
		if not String(line).strip_edges().begins_with("#"):
			code += String(line) + "\n"
	for needle in ["RoofLook.a2_visible_fragments(", "RoofLook.a2_rounded_screen_rect(", "draw_texture_rect_region(", "_a2_wall_drawn.append("]:
		if not code.contains(needle):
			return "missing actual wall blit reader %s" % needle
	if code.find("_a2_wall_drawn.append(") < code.find("draw_texture_rect_region("):
		return "wall blit witness is recorded before the draw call"
	return ""
