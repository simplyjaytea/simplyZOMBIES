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

const ZOOMS: Array[float] = [16.0, 32.0, 64.0, 128.0]
const EPS: float = 0.000001

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _axes_are_aligned() and ok
	ok = _round_trip_is_exact() and ok
	ok = _depth_is_y_alone() and ok
	ok = _visible_bounds_is_the_camera_aabb() and ok
	if ok:
		print("TOPDOWN_OK axes aligned, round-trip exact, depth is y, bounds are the AABB")
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
