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
	if ok:
		print("TOPDOWN_OK axes aligned, round-trip exact, depth is y, bounds are the AABB, ground tinted from the map")
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
