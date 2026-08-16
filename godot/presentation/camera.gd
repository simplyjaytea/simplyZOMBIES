extends RefCounted
# Port of src/render/camera.ts — plain data owned by render/, never by sim.
const IsoProjection = preload("res://presentation/projection.gd")

# zoom is pixels per metre along the tile half-axis, so with the 2:1 ratio in
# projection.gd a tile diamond is (zoom * 2) x zoom pixels. 16 gives a 32x16 tile --
# the standard isometric pixel grid, and what assets/sprites/ is authored against.
# Changing this changes the size of every future sprite, so it is a content decision
# rather than a camera preference.
static func create_camera(zoom: float = 16.0) -> Dictionary:
	return {"x": 0.0, "y": 0.0, "width": 0.0, "height": 0.0, "zoom": zoom}

static func follow_camera(camera: Dictionary, target_x: float, target_y: float, map_w: int, map_h: int) -> void:
	camera["x"] = clampf(target_x, 0.0, float(map_w))
	camera["y"] = clampf(target_y, 0.0, float(map_h))

static func world_to_screen(camera: Dictionary, x: float, y: float) -> Dictionary:
	return IsoProjection.world_to_screen(camera, x, y)

static func screen_to_world(camera: Dictionary, sx: float, sy: float) -> Dictionary:
	return IsoProjection.screen_to_world(camera, sx, sy)
