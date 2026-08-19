extends RefCounted
# Plain data owned by render/, never by sim.
const TopDownProjection = preload("res://presentation/projection.gd")

# zoom is pixels per metre, so a 1 m tile draws zoom x zoom pixels. 64 is the
# art-native scale: assets/sprites/ is authored against a 64 px tile, and other
# zoom steps are power-of-two multiples of it so nearest-neighbour scaling stays
# clean. Changing the art-native scale changes the size of every future sprite,
# so it is a content decision rather than a camera preference.
const ZOOM_STEPS: Array[float] = [16.0, 32.0, 64.0, 128.0]

static func create_camera(zoom: float = 64.0) -> Dictionary:
	return {"x": 0.0, "y": 0.0, "width": 0.0, "height": 0.0, "zoom": zoom}

# Step through the fixed zoom ladder; dir is +1 in, -1 out. Clamps at the ends.
static func zoom_step(camera: Dictionary, dir: int) -> void:
	var at: int = ZOOM_STEPS.find(float(camera["zoom"]))
	if at < 0:
		at = 2
	camera["zoom"] = ZOOM_STEPS[clampi(at + dir, 0, ZOOM_STEPS.size() - 1)]

static func follow_camera(camera: Dictionary, target_x: float, target_y: float, map_w: int, map_h: int) -> void:
	camera["x"] = clampf(target_x, 0.0, float(map_w))
	camera["y"] = clampf(target_y, 0.0, float(map_h))

static func world_to_screen(camera: Dictionary, x: float, y: float) -> Dictionary:
	return TopDownProjection.world_to_screen(camera, x, y)

static func screen_to_world(camera: Dictionary, sx: float, sy: float) -> Dictionary:
	return TopDownProjection.screen_to_world(camera, sx, sy)
