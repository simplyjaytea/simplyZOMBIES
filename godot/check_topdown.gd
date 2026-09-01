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
	ok = _only_the_player_rotates() and ok
	if ok:
		print("TOPDOWN_OK axes aligned, round-trip exact, depth is y, bounds are the AABB, ground tinted from the map, interiors and doorways drawn, props resolved from content, built mass capped and faced, one body rotates")
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
	print("WALL OK cap -%.2f, faces +%.2f/+%.2f over a %.2f-tile band, lit face %.3f clear of the brightest ground %.3f" % [Palette.WALL_CAP_DARKEN, Palette.WALL_FACE_LIT, Palette.WALL_FACE_DIM, Palette.WALL_FACE_SHARE, _luma(lit), brightest])
	return true


# One body rotates, and it is the player's.
#
# docs/30's art decision takes the reference's rotating player and refuses the rest of it: NPCs,
# colonists and zombies stay face-on, because a loop that spun every body would leak facing for
# the people docs/01 clause 4 says the player has not earned to read. That clause is not a comment
# here -- it is `body_rotation` answering 0.0 for everybody who is not the player, and it is the
# draw loop having exactly one transform in it.
#
# The pure half is exact maths on two static functions, both true positives and true negatives.
# The textual half is the dead-socket assertion: `crawlFactor`, `SimStances.CAN_AIM` and seven
# others were correct helpers nothing called, and a rotation helper nobody reaches is a player who
# does not turn. A draw pass cannot be run headless, so what the frame loop calls is read.
func _only_the_player_rotates() -> bool:
	# The head-up convention: the rig is authored pointing up-canvas, so a body facing north
	# (-PI/2 under the top-down projection, screen +y south) draws exactly as it was painted.
	if absf(Appearance.body_rotation(true, -PI / 2.0)) > EPS:
		push_error("a player facing north must draw unrotated (the art is authored head-up), got %f" % Appearance.body_rotation(true, -PI / 2.0))
		return false
	# And the sign: east is a quarter turn clockwise, not anticlockwise. A body that turns the
	# wrong way passes every "it rotates" assertion and looks backwards on every frame.
	if absf(Appearance.body_rotation(true, 0.0) - PI / 2.0) > EPS:
		push_error("a player facing east must draw a quarter turn clockwise (+PI/2), got %f" % Appearance.body_rotation(true, 0.0))
		return false
	# The clause itself. Nobody else turns, at any heading.
	for f in [0.0, 1.3, -PI / 2.0, PI]:
		if Appearance.body_rotation(false, f) != 0.0:
			push_error("a body that is not the player must not rotate: facing %f gave %f, and peripheral anonymity is what that costs" % [f, Appearance.body_rotation(false, f)])
			return false

	# The indicator line: it stands in for a front the art does not have, so it comes off exactly
	# one body -- the player, once the player's art resolves -- and nowhere else.
	if Appearance.wants_facing_line(true, true):
		push_error("the player's art has a front of its own; the indicator line must come off it")
		return false
	if not Appearance.wants_facing_line(true, false):
		push_error("a player drawn as a procedural disc has no front and must keep the line; the fallback is a supported path")
		return false
	for has_art in [true, false]:
		if not Appearance.wants_facing_line(false, has_art):
			push_error("an NPC must keep its indicator line (art on disk: %s); their sprites are face-on and their bodies do not turn" % str(has_art))
			return false

	var body: String = _function_body(MAIN_GD, "_draw_entities")
	if body.is_empty():
		push_error("could not read _draw_entities out of %s -- the rotation lane had nothing to judge" % MAIN_GD)
		return false
	# Called by the frame loop, with the player guard as its *argument* rather than around it:
	# that is what makes the 0.0 above load-bearing instead of a rule stated in a file nothing
	# reads, and it is why the anonymity clause cannot be lost by rewriting an `if` here.
	if not body.contains("Appearance.body_rotation(bool(it[\"player\"])"):
		push_error("_draw_entities does not call Appearance.body_rotation with the player flag: the rotation rule resolves an angle nothing turns")
		return false
	# Exactly one. Two would mean a second body somewhere in the loop had learned to rotate.
	var transforms: int = body.count("draw_set_transform(")
	if transforms != 1:
		push_error("_draw_entities holds %d draw_set_transform( calls; exactly one body rotates, and it is the player's" % transforms)
		return false
	# Reset by matrix, not by a second draw_set_transform -- otherwise the count above stops
	# being able to tell a reset from a second rotating body. A missing reset leaves the
	# transform in force for the aim cone, the ground items and the memory marks below it.
	if not body.contains("draw_set_transform_matrix(Transform2D.IDENTITY)"):
		push_error("_draw_entities never resets the canvas transform; everything drawn after the player would inherit the player's rotation")
		return false
	if not body.contains("Appearance.wants_facing_line("):
		push_error("_draw_entities does not ask Appearance whether the facing line is still wanted; the rule would be a second copy in the draw loop")
		return false
	# The equip layers ride the rig because they are drawn by the same helper inside the same
	# transform. Pull them out of it and a backpack floats beside a turned body.
	if not body.contains("_blit_body("):
		push_error("_draw_entities does not composite through _blit_body; the equipped layers no longer ride the transform the body is drawn under")
		return false
	print("ROTATION OK head-up at -PI/2, +PI/2 east, 0.0 for everybody else, %d transform in the draw loop, reset by matrix" % transforms)
	return true


# The source text of one function, from its `func` line to the next top-level `func`. Used for
# the reach assertion above: `_draw_district` cannot be called headless (it is a CanvasItem draw
# pass), so what it calls is read rather than exercised.
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
