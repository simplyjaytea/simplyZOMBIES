extends SceneTree
# The top-down projection contract: screen axes are world axes, zoom pixels per
# metre, depth is y alone. Nothing else in CI exercises projection.gd (the TS
# oracle's projection.test.ts stayed frozen on the isometric maths it ports), so
# this gate is what makes the reversal in docs/00 mechanical rather than a claim.
#
# Every assertion here fails against the old isometric implementation -- that is
# the true negative each one carries. Axis alignment is the projection itself
# (iso moved +1 world x by (+half_w, +half_h)); depth-ignores-x is the y-sort
# (iso depth was x + y); the round-trip and bounds pin the inverse to the
# forward map at every zoom step the camera can reach.

const TopDownProjection = preload("res://presentation/projection.gd")
const CameraUtil = preload("res://presentation/camera.gd")
const Palette = preload("res://presentation/palette.gd")
const Appearance = preload("res://presentation/appearance.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimSurface = preload("res://sim/map/surface.gd")
const SimBoot = preload("res://sim/boot.gd")

const ZOOMS: Array[float] = [16.0, 32.0, 64.0, 128.0]
const EPS: float = 0.000001
const MAIN_GD: String = "res://presentation/main.gd"
const APPEARANCE_GD: String = "res://presentation/appearance.gd"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _axes_are_aligned() and ok
	ok = _round_trip_is_exact() and ok
	ok = _depth_is_y_alone() and ok
	ok = _visible_bounds_is_the_camera_aabb() and ok
	ok = _the_ground_reaches_the_draw_path() and ok
	ok = _buildings_read_as_buildings() and ok
	ok = _props_reach_the_draw_path() and ok
	ok = _built_mass_is_thin_and_still_solid() and ok
	ok = _bodies_face_by_flipping() and ok
	ok = _bodies_scale_with_the_zoom() and ok
	ok = _a_still_body_is_not_glimpsed() and ok
	if ok:
		print("TOPDOWN_OK axes aligned, round-trip exact, depth is y, bounds are the AABB, ground tinted from the map, interiors and doorways drawn, props resolved from content, built mass capped and faced, nobody rotates and every body flips, bodies scale with the zoom, a still body is not glimpsed")
		quit(0)
	else:
		push_error("TOPDOWN_FAIL")
		quit(1)

func _camera(zoom: float, cx: float, cy: float) -> Dictionary:
	var cam: Dictionary = CameraUtil.create_camera(zoom)
	cam["width"] = 1920.0
	cam["height"] = 1080.0
	cam["x"] = cx
	cam["y"] = cy
	return cam

# +1 world x is exactly (+zoom, 0) pixels; +1 world y is exactly (0, +zoom).
func _axes_are_aligned() -> bool:
	for zoom in ZOOMS:
		var cam: Dictionary = _camera(zoom, 41.5, 17.25)
		var o: Dictionary = TopDownProjection.world_to_screen(cam, 10.0, 20.0)
		var px: Dictionary = TopDownProjection.world_to_screen(cam, 11.0, 20.0)
		var py: Dictionary = TopDownProjection.world_to_screen(cam, 10.0, 21.0)
		if absf(float(px["sx"]) - float(o["sx"]) - zoom) > EPS or absf(float(px["sy"]) - float(o["sy"])) > EPS:
			push_error("world +x must move (+zoom, 0) px at zoom %.0f, got (%f, %f)" % [zoom, float(px["sx"]) - float(o["sx"]), float(px["sy"]) - float(o["sy"])])
			return false
		if absf(float(py["sy"]) - float(o["sy"]) - zoom) > EPS or absf(float(py["sx"]) - float(o["sx"])) > EPS:
			push_error("world +y must move (0, +zoom) px at zoom %.0f, got (%f, %f)" % [zoom, float(py["sx"]) - float(o["sx"]), float(py["sy"]) - float(o["sy"])])
			return false
	return true

func _round_trip_is_exact() -> bool:
	for zoom in ZOOMS:
		for cam_at in [Vector2(0.0, 0.0), Vector2(128.0, 128.0), Vector2(37.5, 201.25)]:
			var cam: Dictionary = _camera(zoom, cam_at.x, cam_at.y)
			for p in [Vector2(0.0, 0.0), Vector2(255.0, 255.0), Vector2(12.75, 199.5), Vector2(-3.0, 260.0)]:
				var s: Dictionary = TopDownProjection.world_to_screen(cam, p.x, p.y)
				var w: Dictionary = TopDownProjection.screen_to_world(cam, float(s["sx"]), float(s["sy"]))
				if absf(float(w["x"]) - p.x) > EPS or absf(float(w["y"]) - p.y) > EPS:
					push_error("round-trip drift at zoom %.0f cam %s point %s: got (%f, %f)" % [zoom, cam_at, p, float(w["x"]), float(w["y"])])
					return false
	return true

# Painter's order is y and only y: two bodies on one row tie regardless of x,
# and a body lower on the map always draws later.
func _depth_is_y_alone() -> bool:
	if absf(TopDownProjection.depth_of(3.0, 7.0) - TopDownProjection.depth_of(90.0, 7.0)) > EPS:
		push_error("depth must ignore x: depth_of(3,7) != depth_of(90,7)")
		return false
	if not TopDownProjection.depth_of(5.0, 7.1) > TopDownProjection.depth_of(5.0, 7.0):
		push_error("depth must increase with y")
		return false
	return true

# The ground layer, docs/24: `map.surfaces` is a second array over the same grid, and the
# draw loop tints each tile with what is *under* it before drawing what is *in* it. The whole
# array existed and drew nothing until this slice, so the assertions are about reach, not maths:
# distinct surfaces resolve distinct colours, the colours come out of the map rather than out of
# the tile type, and `_draw_district` is the thing that asks.
#
# Paved-is-the-floor-colour is the true negative. A ground layer that repainted the street would
# have "worked" on every other assertion here while changing every district that ships; pinning
# paved to the colour the floor already was is what says the change is additive.
func _the_ground_reaches_the_draw_path() -> bool:
	# Every surface the sim can name must have a colour. Add a sixth to the enum and forget the
	# palette and this is what says so, rather than an out-of-range read at draw time.
	if Palette.SURFACE_TINTS.size() != SimSurface.SPEED.size():
		push_error("%d surface tints for %d surfaces the sim can produce" % [Palette.SURFACE_TINTS.size(), SimSurface.SPEED.size()])
		return false

	if Palette.SURFACE_TINTS[SimSurface.Surface.Paved] != Palette.COLOURS["floor"]:
		push_error("paved must stay the floor colour the district already drew, got %s" % str(Palette.SURFACE_TINTS[SimSurface.Surface.Paved]))
		return false

	var seen: Array[Color] = []
	for s in Palette.SURFACE_TINTS.size():
		var tint: Color = Palette.SURFACE_TINTS[s]
		if seen.has(tint):
			push_error("surface %d reuses tint %s -- two surfaces you cannot tell apart are one surface" % [s, str(tint)])
			return false
		seen.append(tint)

	# Through a real map, because a table lookup proves nothing about whether the *array* is
	# read: one tile of each surface, in a map whose tiles are all Floor, and the colour has to
	# follow the surfaces array and not the tile.
	var map: Variant = SimTileMap.blank_map(8, 8)
	var surfaces := PackedByteArray()
	surfaces.resize(8 * 8)
	# Whole-array assignment, not `map.surfaces[i] = v` in a loop: a packed array read out of a
	# property is a value, and CLAUDE.md's first trap is what happens when you forget that.
	for s2 in Palette.SURFACE_TINTS.size():
		surfaces[3 * 8 + s2] = s2
	map.surfaces = surfaces
	for s3 in Palette.SURFACE_TINTS.size():
		var got: Color = Appearance.ground_colour(map, s3, 3)
		if got != Palette.SURFACE_TINTS[s3]:
			push_error("tile (%d,3) is surface %d; the draw path resolved %s, not %s" % [s3, s3, str(got), str(Palette.SURFACE_TINTS[s3])])
			return false
	# A tile nobody wrote is paved, and so is anywhere off the map -- the same answer the sim
	# gives a body standing off the edge, rather than a hole or a crash.
	if Appearance.ground_colour(map, 7, 7) != Palette.COLOURS["floor"]:
		push_error("an unwritten tile must read as paved")
		return false
	if Appearance.ground_colour(map, -1, 400) != Palette.COLOURS["floor"]:
		push_error("off the map must read as paved, the way SimSurface.surface_at answers")
		return false
	if Appearance.ground_colour(null, 0, 0) != Palette.COLOURS["floor"]:
		push_error("a world with no tilemap must still draw a floor")
		return false

	# The dead-socket assertion. Everything above is true of a resolver nothing calls, which is
	# exactly the state `SimSurface.speed_on` was in before this slice, so the last thing to
	# prove is that the district's draw loop is the one asking.
	var body: String = _function_body(MAIN_GD, "_draw_district")
	if body.is_empty():
		push_error("could not read _draw_district out of %s -- the reach assertion had nothing to judge" % MAIN_GD)
		return false
	if not body.contains("Appearance.ground_colour("):
		push_error("_draw_district does not call Appearance.ground_colour: the surface array resolves a colour nothing draws")
		return false
	print("GROUND OK %d surfaces, distinct tints, paved still #%s, resolved off map.surfaces and read by _draw_district" % [Palette.SURFACE_TINTS.size(), (Palette.COLOURS["floor"] as Color).to_html(false)])
	return true


# A building reads as a building: the floor inside it is not the floor outside it, and the tile you
# walk through to get in is not the wall either side of it. Both are read off arrays and manifests
# the generator already wrote and nothing drew -- `map.indoors` and `map.buildings[].doors` -- so
# these assertions are about reach and about the two answers being distinguishable, not about the
# maths.
#
# The true negative each carries is the outdoor case: an interior tint that also repainted the
# street would satisfy "the two differ" while changing every district that ships, so an outdoor
# tile returning its ground colour *unchanged* is asserted alongside, and so is a map nobody
# stamped having no doorways at all.
func _buildings_read_as_buildings() -> bool:
	if Palette.INDOOR_MIX <= 0.0 or Palette.INDOOR_MIX > 1.0:
		push_error("INDOOR_MIX %f is not a mix: at 0 an interior is indistinguishable from the street" % Palette.INDOOR_MIX)
		return false

	var map: Variant = SimTileMap.blank_map(8, 8)
	var indoors := PackedByteArray()
	indoors.resize(8 * 8)
	indoors[3 * 8 + 3] = 1
	map.indoors = indoors
	var paved: Color = Palette.COLOURS["floor"]
	var inside: Color = Appearance.indoor_floor(map, 3, 3, paved)
	if inside == paved:
		push_error("an indoor floor resolved the same colour as the street; a shell nobody can see into is not a building")
		return false
	if inside != paved.lerp(Palette.COLOURS["indoorFloor"], Palette.INDOOR_MIX):
		push_error("indoor_floor did not mix the ground towards the board colour, got %s" % str(inside))
		return false
	# The surface underneath still shows through: two interiors on different ground are two
	# different floors, which is what keeps the ground lane above meaning what it says.
	if Appearance.indoor_floor(map, 3, 3, Palette.COLOURS["grass"]) == inside:
		push_error("indoor_floor threw the surface away; every interior would be one slab colour")
		return false
	if Appearance.indoor_floor(map, 4, 3, paved) != paved:
		push_error("a tile outside the shell must keep its ground colour exactly")
		return false
	if Appearance.indoor_floor(null, 0, 0, paved) != paved:
		push_error("a world with no tilemap must still draw an outdoor floor")
		return false

	# Doorways off the manifest, including the two entries that must be refused: a door outside
	# the map, and a record carrying none at all.
	map.buildings = [
		{"id": "b0", "x": 0, "y": 0, "w": 4, "h": 4, "doors": [{"x": 2, "y": 3}, {"x": 99, "y": 1}]},
		{"id": "b1", "x": 5, "y": 0, "w": 3, "h": 3},
	]
	var doors: Dictionary = Appearance.door_tiles(map)
	if doors.size() != 1 or not doors.has(3 * 8 + 2):
		push_error("door_tiles should hold exactly the one in-bounds doorway, got %s" % str(doors.keys()))
		return false
	var bare: Variant = SimTileMap.blank_map(8, 8)
	if not Appearance.door_tiles(bare).is_empty():
		push_error("a map nobody built on has no doorways")
		return false
	if not Appearance.door_tiles(null).is_empty():
		push_error("a null map has no doorways")
		return false

	# Reach. Neither of the two can be exercised headless -- both are inside a CanvasItem draw
	# pass -- so what the draw loop calls is read, the same way the ground lane above reads it.
	var district: String = _function_body(MAIN_GD, "_draw_district")
	if district.is_empty():
		push_error("could not read _draw_district out of %s -- the reach assertion had nothing to judge" % MAIN_GD)
		return false
	if not district.contains("Appearance.indoor_floor("):
		push_error("_draw_district does not call Appearance.indoor_floor: map.indoors resolves a colour nothing draws")
		return false
	if not district.contains("_is_threshold("):
		push_error("_draw_district does not ask which tiles are doorways: the manifest's doors draw as plain floor")
		return false
	var thresholds: String = _function_body(MAIN_GD, "_threshold_tiles")
	if not thresholds.contains("Appearance.door_tiles("):
		push_error("_threshold_tiles does not derive its cache from Appearance.door_tiles")
		return false
	print("BUILDINGS OK interiors mix %.2f towards #%s over the surface, %d doorway off a manifest of 3" % [Palette.INDOOR_MIX, (Palette.COLOURS["indoorFloor"] as Color).to_html(false), doors.size()])
	return true


# Props: a container, a bed, a campfire and the well stood in every district and were drawn by
# nothing -- announced in prose and otherwise invisible, with a generated district standing 52-137
# containers. So this lane is the dead-socket assertion in both directions: everything the sim
# stands in a real district resolves a drawable look, and the draw loop is the thing asking.
func _props_reach_the_draw_path() -> bool:
	var boot: Dictionary = SimBoot.playable(4113, 64)
	var world: Variant = boot["world"]
	var found: Dictionary = {}
	var props: int = 0
	for kind in Appearance.PROP_KINDS:
		found[String(kind["component"])] = 0
	# Everything standing in the district that is not a body and not a carried item has to resolve
	# something. This is what catches a fifth kind of prop added without a PROP_KINDS entry: it
	# would stand there invisible, and this fails rather than shipping it.
	#
	# `corpse` is skipped by name: the bodies of the dead are their own listed piece of work
	# (docs/23's defect list) and are drawn -- or not -- by _draw_entities, not here.
	var bodies: Array[String] = ["controlled", "identity", "shambler", "raider", "itemBase", "noisemaker", "corpse"]
	for ent in world.components.query(["position"]):
		var e: int = int(ent)
		var is_body: bool = false
		for c in bodies:
			if world.components.has_component(e, c):
				is_body = true
				break
		if is_body:
			continue
		var look: Dictionary = Appearance.prop_look(world, e)
		if look.is_empty():
			push_error("entity %d stands in the district and resolves no look: neither a body, nor an item, nor a prop anything can draw" % e)
			return false
		if not Appearance.PROP_SHAPES.has(String(look["shape"])):
			push_error("entity %d resolved shape '%s', which the renderer does not draw" % [e, look["shape"]])
			return false
		props += 1
		for kind in Appearance.PROP_KINDS:
			if world.components.has_component(e, String(kind["component"])):
				found[String(kind["component"])] = int(found[String(kind["component"])]) + 1
	if props == 0:
		push_error("no props stood in a booted district -- this lane had nothing to judge")
		return false
	# Every kind is expected on a stamped district, but a missing one says so rather than passing
	# quietly: an anchorless map gets no well, which is a real and legitimate case.
	for comp in found.keys():
		if int(found[comp]) == 0:
			print("PROPS SKIP no `%s` stood in this district; its resolution went unjudged here" % comp)
	# A body must resolve nothing, or the loop above would pass on anything at all.
	var player_look: Dictionary = Appearance.prop_look(world, int(world.player))
	if not player_look.is_empty():
		push_error("the player resolved a prop look; prop_look must answer only for props")
		return false

	# The searched/lit states are what make two content ids necessary; flipping the flag has to
	# change the look, or the second entry is decoration.
	var container: int = -1
	for ent2 in world.components.query(["searchable"]):
		container = int(ent2)
		break
	if container < 0:
		push_error("a booted district stood no container -- the state assertion had nothing to judge")
		return false
	var unsearched: Dictionary = Appearance.prop_look(world, container)
	(world.components.get_component(container, "searchable") as Dictionary)["searched"] = true
	var searched: Dictionary = Appearance.prop_look(world, container)
	if String(unsearched["id"]) == String(searched["id"]):
		push_error("a searched container resolves the same content id as an unsearched one; the flag is not reaching PROP_KINDS")
		return false
	# The two ids have to draw differently, and *how* they differ moved with the art: they were
	# two tints until props had sprites, and are now two pictures drawn unstained (white on both
	# sides, so a tint comparison alone would read "identical" for props that are nothing of the
	# sort). Either axis differing is enough; neither differing is one state wearing two names.
	# check_appearance's prop lane is the finer version, comparing the decoded pixels.
	if unsearched["tint"] == searched["tint"] and unsearched["texture"] == searched["texture"]:
		push_error("a searched container looks exactly like an unsearched one; the state is not readable")
		return false

	# Reach, textual for the same reason as above.
	var district: String = _function_body(MAIN_GD, "_draw_district")
	if not district.contains("_draw_props("):
		push_error("_draw_district does not call _draw_props: every prop in the district resolves a look nothing draws")
		return false
	var draw_props: String = _function_body(MAIN_GD, "_draw_props")
	if not draw_props.contains("Appearance.prop_look(") or not draw_props.contains("_draw_prop("):
		push_error("_draw_props does not resolve looks from content and hand them to _draw_prop")
		return false
	# The shape vocabulary is content-facing (prop.schema.json's enum) and presentation-owned:
	# every name content may ask for has to be a name this function draws.
	var draw_prop: String = _function_body(MAIN_GD, "_draw_prop")
	if draw_prop.is_empty():
		push_error("could not read _draw_prop out of %s" % MAIN_GD)
		return false
	for shape in Appearance.PROP_SHAPES:
		if not draw_prop.contains('"%s"' % shape):
			push_error("_draw_prop draws no '%s'; content can ask for a shape nothing renders" % shape)
			return false
	print("PROPS OK %d props stood and resolved (%s), %d shapes drawn, states distinguishable" % [props, str(found), Appearance.PROP_SHAPES.size()])
	return true


# Built mass, drawn thin. A wall blocks a whole tile and is therefore drawn over a whole tile,
# but a whole tile of flat wall colour made a one-tile wall the brightest and largest thing on the
# screen -- brighter than a survivor, who is a fraction of a tile. So the tile is filled with the
# cap and only the edges that meet something walkable carry a lit face.
#
# The two things that can go wrong pull in opposite directions, and both are asserted:
#   * the mass creeps back to bright -- the face share reaching half a tile, or a face that is not
#     a band but the fill, which is the look this replaced;
#   * the mass recedes so far that a blocked tile reads as an unlit floor, which is worse than a
#     chunky wall because it promises passage the sim refuses. That is measured, not asserted by
#     eye: every ground the district can put against a wall (each surface tint and its indoor mix,
#     the doorway boards) must sit clearly below both faces in luminance.
# The true negative for the first is the old constants (a bevel of 2 px on every edge, cap ==
# fill); for the second, a cap or face pulled down to the floor colours, which the margins below
# fail on immediately.
const FACE_LIT_MARGIN: float = 0.08
const FACE_DIM_MARGIN: float = 0.04

func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b

func _built_mass_is_thin_and_still_solid() -> bool:
	if Palette.WALL_FACE_SHARE <= 0.0 or Palette.WALL_FACE_SHARE >= 0.5:
		push_error("WALL_FACE_SHARE %f is not a band: at 0 the faces vanish, at 0.5 they meet and the tile is face again" % Palette.WALL_FACE_SHARE)
		return false
	var wall: Color = Palette.COLOURS["wall"]
	var cap: Color = wall.darkened(Palette.WALL_CAP_DARKEN)
	var lit: Color = wall.lightened(Palette.WALL_FACE_LIT)
	var dim: Color = wall.lightened(Palette.WALL_FACE_DIM)
	if not (_luma(cap) < _luma(dim) and _luma(dim) < _luma(lit)):
		push_error("cap %.3f, shaded face %.3f, lit face %.3f: a face has to be brighter than the cap it edges, or the mass has no drawn edge" % [_luma(cap), _luma(dim), _luma(lit)])
		return false
	if _luma(cap) >= _luma(wall):
		push_error("the cap is not darker than the wall colour; the tile is as bright as it was and nothing receded")
		return false

	# Every floor a wall can stand beside: the five surfaces, each of them again as an interior,
	# and the doorway. If the dimmest face does not clear the brightest of them, some wall
	# somewhere in the district has an edge you cannot see.
	var grounds: Array[Color] = []
	for s in Palette.SURFACE_TINTS.size():
		var g: Color = Palette.SURFACE_TINTS[s]
		grounds.append(g)
		grounds.append(g.lerp(Palette.COLOURS["indoorFloor"], Palette.INDOOR_MIX))
	grounds.append((Palette.COLOURS["floor"] as Color).lerp(Palette.COLOURS["threshold"], 0.75))
	var brightest: float = -1.0
	for g2 in grounds:
		brightest = maxf(brightest, _luma(g2))
	if _luma(lit) - brightest < FACE_LIT_MARGIN:
		push_error("the lit face is %.3f over the brightest ground (%.3f); a wall edge must read against every floor it touches" % [_luma(lit) - brightest, brightest])
		return false
	if _luma(dim) - brightest < FACE_DIM_MARGIN:
		push_error("the shaded face is %.3f over the brightest ground (%.3f); the south and east edges of a wall would disappear into it" % [_luma(dim) - brightest, brightest])
		return false

	# Reach, textual for the same reason as the lanes above: a draw pass cannot be run headless.
	# The face is only drawn where the mass ends, which is the whole reason a wall run reads as one
	# thick line; a _draw_solid_tile that stopped asking its neighbours would bevel every tile again
	# and this is what would say so.
	var solid: String = _function_body(MAIN_GD, "_draw_solid_tile")
	if solid.is_empty():
		push_error("could not read _draw_solid_tile out of %s -- the wall lane had nothing to judge" % MAIN_GD)
		return false
	for needle in ["Palette.WALL_CAP_DARKEN", "Palette.WALL_FACE_SHARE", "_is_solid_at("]:
		if not solid.contains(needle):
			push_error("_draw_solid_tile does not use %s: the cap, the band width and the exposed-edge test are what make the mass thin" % needle)
			return false
	var district: String = _function_body(MAIN_GD, "_draw_district")
	if not district.contains("_draw_solid_tile(rect, Palette.COLOURS[\"wall\"], tx, ty)"):
		push_error("the window tile is not drawn as masonry; a window that fills its tile with glass is the same proportion problem as a bright wall")
		return false
	if not district.contains("_draw_window_glass(rect, tx, ty, col)"):
		push_error("_draw_window_glass is not handed the tile's colour, so a boarded window's stage stops showing in its pane")
		return false
	print("WALL OK cap -%.2f, faces +%.2f/+%.2f over a %.2f-tile band, lit margin +%.3f (>= %.2f), dim margin +%.3f (>= %.2f), brightest ground %.3f" % [Palette.WALL_CAP_DARKEN, Palette.WALL_FACE_LIT, Palette.WALL_FACE_DIM, Palette.WALL_FACE_SHARE, _luma(lit) - brightest, FACE_LIT_MARGIN, _luma(dim) - brightest, FACE_DIM_MARGIN, brightest])
	return true


# Nobody rotates, and every body flips.
#
# docs/30's Dungeon Settlers decision (2026-09-03) reverses "only the player rotates": every rig
# is a face-on pawn standing on its own point, heading is a horizontal flip, and the one
# transform the old player rig turned under is gone from the loop. The flip is a negative-width
# rect handed to the renderer -- probed in 4.7.1 to mirror the texture at position .. position +
# |width| -- so `body_rect` keeps its left edge and a body never leaves its point. The
# peripheral-anonymity clause (docs/01 clause 4) is unharmed because a glimpsed body never
# reaches the blit: the disc branch `continue`s before facing is read, asserted below as an
# index order in the source rather than trusted.
#
# The pure half is exact maths on three static functions, both true positives and true negatives.
# The textual half is the dead-socket assertion on what the frame loop reaches for, with the
# transform counter proved on a fabricated body first: a counter that answered zero for
# everything would be a lane that cannot fail.
func _bodies_face_by_flipping() -> bool:
	# The flip: mirrored only when the heading has a westward component. North, south and east
	# all draw the one painted picture.
	for probe in [[0.0, 1.0], [PI, -1.0], [PI / 2.0, 1.0], [-PI / 2.0, 1.0], [2.4, -1.0], [-2.4, -1.0]]:
		var facing: float = float((probe as Array)[0])
		var want: float = float((probe as Array)[1])
		if Appearance.body_flip(facing) != want:
			push_error("body_flip(%f) answered %f, not %f" % [facing, Appearance.body_flip(facing), want])
			return false
	if Appearance.body_flip(0.0) == Appearance.body_flip(PI) or Appearance.body_flip(0.0) == 0.0 or Appearance.body_flip(PI) == 0.0:
		push_error("body_flip answers the same, or zero, for east and west; a flip that does not flip draws every body one way")
		return false

	# The anchor is the shape: square centres, anything else stands.
	var native: int = int(CameraUtil.ART_NATIVE)
	if Appearance.anchor_of(Vector2i(native, native)) != Appearance.Anchor.Centre:
		push_error("a tile-square canvas must centre on its point; a prop would float")
		return false
	if Appearance.anchor_of(Appearance.PAWN_CANVAS) != Appearance.Anchor.Feet:
		push_error("the pawn canvas must stand on its point")
		return false
	if Appearance.anchor_of(Vector2i(native * 2, native * 2)) != Appearance.Anchor.Centre or Appearance.anchor_of(Vector2i(native, native * 3)) != Appearance.Anchor.Feet:
		push_error("anchor_of is not derived from the shape: a 2x2-tile square must centre and a 1x3 sheet must stand")
		return false
	if Appearance.PAWN_CANVAS != Vector2i(native, native * 3 / 2):
		push_error("PAWN_CANVAS is %s, not one tile wide by one and a half tall" % str(Appearance.PAWN_CANVAS))
		return false

	# The rect, exact at every rung: a pawn's soles on the shadow line, a tile-square picture on
	# the old symmetric rect, a flipped pawn the same rect with a negative width.
	for zoom in ZOOMS:
		var scale: float = Appearance.blit_scale(zoom)
		var pawn: Vector2 = Vector2(Appearance.PAWN_CANVAS) * scale
		var square: Vector2 = Vector2(native, native) * scale
		var stood: Rect2 = Appearance.body_rect(100.0, 100.0, pawn, 1.0)
		var want_stood := Rect2(roundf(100.0 - pawn.x / 2.0), roundf(100.0 + Appearance.FOOT_DROP_PX - pawn.y), pawn.x, pawn.y)
		if stood != want_stood:
			push_error("body_rect at zoom %.0f stood a pawn at %s, not %s" % [zoom, str(stood), str(want_stood)])
			return false
		if absf(stood.position.y + stood.size.y - (100.0 + Appearance.FOOT_DROP_PX)) > EPS:
			push_error("at zoom %.0f the soles sit at %f, not on the shadow line %f" % [zoom, stood.position.y + stood.size.y, 100.0 + Appearance.FOOT_DROP_PX])
			return false
		var centred: Rect2 = Appearance.body_rect(100.0, 100.0, square, 1.0)
		var want_centred := Rect2(Vector2(roundf(100.0 - square.x / 2.0), roundf(100.0 - square.y / 2.0)), square)
		if centred != want_centred:
			push_error("body_rect at zoom %.0f centred a square at %s, not the old rect %s" % [zoom, str(centred), str(want_centred)])
			return false
		var flipped: Rect2 = Appearance.body_rect(100.0, 100.0, pawn, -1.0)
		if flipped.position != stood.position or flipped.size != Vector2(-pawn.x, pawn.y):
			push_error("a flipped pawn at zoom %.0f is %s; it must keep %s's position with a negative width" % [zoom, str(flipped), str(stood)])
			return false
		# The true negative: a pawn hung symmetrically -- the old rect applied to the new
		# shape -- is refused by the same exact equality, because its soles sit half a body
		# below the point.
		var symmetric := Rect2(Vector2(roundf(100.0 - pawn.x / 2.0), roundf(100.0 - pawn.y / 2.0)), pawn)
		if stood == symmetric:
			push_error("a centred pawn passes the feet-anchor equality at zoom %.0f; the anchor reads nothing" % zoom)
			return false
	# The exact numbers at the boot zoom, so a reader can check the arithmetic by hand.
	var at64: Rect2 = Appearance.body_rect(100.0, 100.0, Vector2(64.0, 96.0), 1.0)
	if at64 != Rect2(68.0, 7.0, 64.0, 96.0):
		push_error("body_rect(100, 100, (64, 96), +1) is %s, not Rect2(68, 7, 64, 96)" % str(at64))
		return false

	# Every pawn key resolves a picture on the pawn canvas: a rig left at the old tile size would
	# stand on the shadow line half a tile short and check_appearance's canvas lanes would say
	# so, but this is the assertion that the roster is pawns, not merely that files are sized.
	Appearance.forget()
	var pawns: int = 0
	for key in Appearance.PAWN_KEYS:
		var tex: Variant = Appearance.resolve(String(key))
		if tex == null:
			push_error("pawn key %s resolves no picture" % key)
			return false
		if Vector2i((tex as Texture2D).get_size()) != Appearance.PAWN_CANVAS:
			push_error("pawn key %s is %s, not the pawn canvas %s -- a rig left on the tile" % [key, str((tex as Texture2D).get_size()), str(Appearance.PAWN_CANVAS)])
			return false
		pawns += 1
	Appearance.forget()
	if pawns < 8:
		push_error("only %d pawn keys resolved; the roster is eight rigs and three overlays" % pawns)
		return false

	# The loop, read: what it reaches for and what it no longer holds.
	var body: String = _function_body(MAIN_GD, "_draw_entities")
	if body.is_empty():
		push_error("could not read _draw_entities out of %s -- the flip lane had nothing to judge" % MAIN_GD)
		return false
	var fabricated: String = "\tdraw_set_transform(a, b, c)\n\tdraw_set_transform_matrix(Transform2D.IDENTITY)\n"
	if fabricated.count("draw_set_transform(") != 1 or fabricated.count("_matrix(") != 1:
		push_error("the transform counter did not count one of each on a fabricated body; a zero below would prove nothing")
		return false
	var transforms: int = body.count("draw_set_transform(")
	var resets: int = body.count("_matrix(")
	if transforms != 0 or resets != 0:
		push_error("_draw_entities holds %d draw_set_transform( and %d _matrix( calls; nobody rotates, so the loop holds none" % [transforms, resets])
		return false
	var missing: String = _needles_missing(body, [
		"Appearance.body_flip(",
		"Appearance.body_rect(",
		"_blit_body(",
		"Palette.COLOURS[\"facing\"]",
		"Appearance.FOOT_DROP_PX",
	])
	if not missing.is_empty():
		push_error("_draw_entities does not contain %s: the flip, the rect, the composite, the line or the shadow drop is resolved by nothing" % missing)
		return false
	if body.contains("wants_facing_line"):
		push_error("_draw_entities still asks wants_facing_line; the line draws for every body since the pawn slice")
		return false
	var peripheral: int = body.find("Detail.Peripheral")
	var blit: int = body.find("Appearance.body_rect(")
	if peripheral < 0 or blit < 0 or peripheral >= blit:
		push_error("the peripheral disc branch (%d) does not precede the body blit (%d); a glimpsed body would reach the flip and leak its heading" % [peripheral, blit])
		return false
	# And the disc branch bails: the `continue` after the glimpse disc is what keeps a glimpsed
	# body out of the blit, so it is found between the disc and the blit rather than assumed.
	var disc: int = body.find("Palette.COLOURS[\"glimpse\"]")
	var bail: int = body.find("continue", disc) if disc >= 0 else -1
	if disc < 0 or bail < 0 or bail >= blit:
		push_error("no `continue` between the glimpse disc (%d) and the body blit (%d); a glimpsed body would be drawn as a pawn with its heading" % [disc, blit])
		return false
	# And now the whole file, not just this loop. The one transform left in main.gd was the tile
	# art's quarter turn for an east-west run of car segments, and that retired with the segments
	# when a vehicle became one three-quarter picture per axis (docs/30, decision 11). So the
	# assertion widens from "the loop holds none and the wreck holds one" to "main.gd holds none",
	# which is both stronger and the truth. Proved on a fabricated file first, the same way the
	# loop's counter is, so a scanner that answers zero for everything cannot pass this.
	var whole: String = _file_text(MAIN_GD)
	if whole.is_empty():
		push_error("could not read %s" % MAIN_GD)
		return false
	if "\tdraw_set_transform(a, b, c)\n".count("draw_set_transform(") != 1:
		push_error("the file-wide transform counter cannot see a transform it was handed")
		return false
	var whole_transforms: int = whole.count("draw_set_transform(")
	if whole_transforms != 0:
		push_error("main.gd holds %d draw_set_transform( calls; nothing rotates since the vehicle slice" % whole_transforms)
		return false
	# The retired helpers are gone, not stubbed: a body_rotation that answers 0.0 for everybody
	# is the dead-socket family.
	var resolver: String = _file_text(APPEARANCE_GD)
	if resolver.is_empty():
		push_error("could not read %s" % APPEARANCE_GD)
		return false
	for gone in ["func body_rotation(", "SPRITE_FORWARD", "func wants_facing_line("]:
		if resolver.contains(gone):
			push_error("appearance.gd still carries %s; the rotation retired with the pawn slice" % gone)
			return false
	print("FLIP OK east +1, west -1, north and south unflipped; square centres and the pawn stands, soles on +%.0f at all %d rungs, Rect2(68, 7, 64, 96) at 64; %d pawn keys on %s; zero transforms in the loop and zero in all of main.gd (both counters proved), the disc bails before the blit, three helpers gone" % [Appearance.FOOT_DROP_PX, ZOOMS.size(), pawns, str(Appearance.PAWN_CANVAS)])
	return true


# The first needle missing from a function body, or "" when all are present. Named so the
# scale and glimpse lanes below can prove the scanner on a fabricated body before trusting
# it on the real one -- a scanner that answers "" for everything is a gate that cannot fail.
func _needles_missing(body: String, needles: Array[String]) -> String:
	for needle in needles:
		if not body.contains(needle):
			return needle
	return ""


# A body's art scales with the camera: one art pixel is `zoom / ART_NATIVE` screen pixels,
# so a rig covers the same fraction of a tile at every step on the ladder. Before this lane
# the blit used the texture's native size, which drew a 64 px body over a 16 px tile -- four
# tiles of survivor at the widest zoom. The resolver stays zoom-innocent (`for_entity`
# answers *what*, `blit_scale` answers *how big*), which is why the pure half needs no world.
func _bodies_scale_with_the_zoom() -> bool:
	# The whole ladder walked, not one probe: a resolver correct at 64 alone is the bug below.
	for step in CameraUtil.ZOOM_STEPS:
		if absf(Appearance.blit_scale(step) * CameraUtil.ART_NATIVE - step) > EPS:
			push_error("blit_scale(%.0f) * ART_NATIVE != %.0f -- one art pixel must be zoom/ART_NATIVE screen pixels" % [step, step])
			return false
	if absf(Appearance.blit_scale(CameraUtil.ART_NATIVE) - 1.0) > EPS:
		push_error("at the art-native zoom the scale must be exactly 1.0, got %f" % Appearance.blit_scale(CameraUtil.ART_NATIVE))
		return false
	if not CameraUtil.ZOOM_STEPS.has(CameraUtil.ART_NATIVE):
		push_error("ART_NATIVE %.0f is not on the zoom ladder -- an art-native scale the camera cannot reach is a 1:1 body nobody can ever see" % CameraUtil.ART_NATIVE)
		return false
	# Graceful absence, stated as behaviour: a degenerate camera scales everything to nothing
	# rather than dividing wrong (the divisor is a nonzero const, so there is no zero to hit).
	if Appearance.blit_scale(0.0) != 0.0:
		push_error("blit_scale(0.0) must answer 0.0, got %f" % Appearance.blit_scale(0.0))
		return false
	# The true negative: a resolver that answered 1.0 at every zoom is exactly the defect this
	# lane exists for, and a lane that probed only 64 would bless it.
	if absf(Appearance.blit_scale(16.0) - 1.0) <= EPS:
		push_error("blit_scale(16.0) answered 1.0 -- the native-size blit is back and the lane read nothing")
		return false
	# The default zoom is the art at a clean multiple, and not at 1:1: since the 2026-09-02
	# move to a 32 px tile the camera boots at 64, so a body draws at exactly 2x. Read off
	# create_camera rather than written here, so the lane follows the default if it moves --
	# and a default equal to ART_NATIVE is the 64-era look back (art at 1:1 on the boot
	# screen), which is the second true negative.
	var default_zoom: float = float(CameraUtil.create_camera()["zoom"])
	if absf(Appearance.blit_scale(default_zoom) - default_zoom / CameraUtil.ART_NATIVE) > EPS:
		push_error("blit_scale at the default zoom %.0f answered %f, not %.1f" % [default_zoom, Appearance.blit_scale(default_zoom), default_zoom / CameraUtil.ART_NATIVE])
		return false
	if absf(Appearance.blit_scale(default_zoom) - 1.0) <= EPS:
		push_error("blit_scale at the default zoom %.0f answered 1.0 -- the boot screen draws art at 1:1, which is the old 64 px native back" % default_zoom)
		return false
	if absf(Appearance.blit_scale(default_zoom) - 2.0) > EPS:
		push_error("the default zoom %.0f is not a clean 2x of ART_NATIVE %.0f; the boot screen's upscale is the reference-look decision (docs/30, 2026-09-02)" % [default_zoom, CameraUtil.ART_NATIVE])
		return false

	# The dead socket: a correct scale nothing multiplies by is a body still drawn native.
	var body: String = _function_body(MAIN_GD, "_draw_entities")
	if body.is_empty():
		push_error("could not read _draw_entities out of %s -- the scale lane had nothing to judge" % MAIN_GD)
		return false
	# Prove the scanner on a fabricated body first (the convention check_weather.gd set):
	# a body lacking the needle must be refused, or the real scan below proves nothing.
	if _needles_missing("var x = 1\n", ["Appearance.blit_scale("]).is_empty():
		push_error("the needle scanner passed a body with no needles in it; the socket assertion reads nothing")
		return false
	var missing: String = _needles_missing(body, [
		"Appearance.blit_scale(",
		"texture.get_size() * px_scale",
		"float(look[\"radius\"]) * px_scale",
	])
	if not missing.is_empty():
		push_error("_draw_entities does not contain %s: the scale resolves a factor nothing multiplies by" % missing)
		return false
	print("SCALE OK blit_scale walks the %d-step ladder, 1.0 at %.0f, 2.0 at the default %.0f, 0.0 at 0, native-size refused, and _draw_entities multiplies by it" % [CameraUtil.ZOOM_STEPS.size(), CameraUtil.ART_NATIVE, default_zoom])
	return true


# A peripheral glimpse is motion or nothing, and "moving" is Appearance.moving's answer.
# The old inline test read a missing velocity component backwards: it culled only entities
# that HAD a velocity of zero, so a corpse -- whose velocity component the sim removes
# outright -- was glimpsed forever as a body standing in the dark. The inversion is the
# mechanical half of the corpse defect; what a corpse *looks* like at Focal stays on the
# roadmap's what's-left list.
func _a_still_body_is_not_glimpsed() -> bool:
	for tp in [{"dx": 1.0, "dy": 0.0}, {"dx": 0.0, "dy": -0.4}]:
		if not Appearance.moving(tp):
			push_error("moving(%s) answered false; a walking body would vanish from the glimpse" % str(tp))
			return false
	if Appearance.moving({"dx": 0.0, "dy": 0.0}):
		push_error("moving({0,0}) answered true; a parked body would be glimpsed")
		return false
	if Appearance.moving(null):
		push_error("moving(null) answered true; the corpse case -- a removed component is motionless, not unknown")
		return false
	if Appearance.moving({}):
		push_error("moving({}) answered true; an empty component is motionless")
		return false
	if Appearance.moving("not a dict"):
		push_error("moving on a non-Dictionary answered true")
		return false
	# CLAUDE.md's velocity trap made mechanical: the component's keys are dx/dy, and a probe
	# written against x/y must read as motionless -- a pin that silently does not pin.
	if Appearance.moving({"x": 1.0, "y": 0.0}):
		push_error("moving({x,y}) answered true; velocity keys are dx/dy and a reader of x/y is reading nothing")
		return false

	# The socket, both halves: the helper is called, and the old inline test is *gone* --
	# an inversion that landed beside the literal it replaced would cull nothing.
	var body: String = _function_body(MAIN_GD, "_draw_entities")
	if body.is_empty():
		push_error("could not read _draw_entities out of %s -- the glimpse lane had nothing to judge" % MAIN_GD)
		return false
	if _needles_missing("var x = 1\n", ["Appearance.moving("]).is_empty():
		push_error("the needle scanner passed a body with no needles in it; the socket assertion reads nothing")
		return false
	if not _needles_missing(body, ["Appearance.moving("]).is_empty():
		push_error("_draw_entities does not call Appearance.moving: the inversion resolves an answer nothing reads")
		return false
	if body.contains(".get(\"dx\", 0.0)) == 0.0"):
		push_error("_draw_entities still carries the old inline stillness test beside the helper; two rules for one glimpse")
		return false
	print("GLIMPSE OK moving true on 2 walks, false on parked/corpse/empty/non-dict/x-y, and _draw_entities asks the helper")
	return true


# The source text of one function, from its `func` line to the next top-level `func`. Used for
# the reach assertion above: `_draw_district` cannot be called headless (it is a CanvasItem draw
# pass), so what it calls is read rather than exercised.
func _file_text(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


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


func _visible_bounds_is_the_camera_aabb() -> bool:
	for zoom in ZOOMS:
		var cam: Dictionary = _camera(zoom, 100.0, 60.0)
		var margin: float = 2.0
		var b: Dictionary = TopDownProjection.visible_bounds(cam, margin)
		var half_w: float = 1920.0 / 2.0 / zoom
		var half_h: float = 1080.0 / 2.0 / zoom
		var want: Dictionary = {
			"minX": 100.0 - half_w - margin, "maxX": 100.0 + half_w + margin,
			"minY": 60.0 - half_h - margin, "maxY": 60.0 + half_h + margin,
		}
		for k in want.keys():
			if absf(float(b[k]) - float(want[k])) > EPS:
				push_error("visible_bounds %s at zoom %.0f: want %f got %f" % [k, zoom, float(want[k]), float(b[k])])
				return false
	return true
