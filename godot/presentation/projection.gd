extends RefCounted
# Port of src/render/projection.ts — one answer to where a world point lands on screen.
# Isometric 2:1, no z. Sim never imports this.

const TILE_WIDTH_RATIO: int = 2
const TILE_HEIGHT_RATIO: int = 1
const RISE_SCALE: float = 0.62

static func _axes(zoom: float) -> Dictionary:
	var half_w: float = zoom * float(TILE_WIDTH_RATIO) / 2.0
	var half_h: float = zoom * float(TILE_HEIGHT_RATIO) / 2.0
	return {"ax": half_w, "ay": half_h, "bx": -half_w, "by": half_h}

static func world_to_screen(camera: Dictionary, x: float, y: float) -> Dictionary:
	var a: Dictionary = _axes(float(camera["zoom"]))
	var dx: float = x - float(camera["x"])
	var dy: float = y - float(camera["y"])
	return {
		"sx": dx * float(a["ax"]) + dy * float(a["bx"]) + float(camera["width"]) / 2.0,
		"sy": dx * float(a["ay"]) + dy * float(a["by"]) + float(camera["height"]) / 2.0,
	}

static func screen_to_world(camera: Dictionary, sx: float, sy: float) -> Dictionary:
	var a: Dictionary = _axes(float(camera["zoom"]))
	var px: float = sx - float(camera["width"]) / 2.0
	var py: float = sy - float(camera["height"]) / 2.0
	var ax: float = float(a["ax"])
	var ay: float = float(a["ay"])
	var bx: float = float(a["bx"])
	var by: float = float(a["by"])
	var det: float = ax * by - bx * ay
	return {
		"x": (px * by - bx * py) / det + float(camera["x"]),
		"y": (ax * py - px * ay) / det + float(camera["y"]),
	}

static func depth_of(x: float, y: float) -> float:
	return x + y

static func visible_bounds(camera: Dictionary, margin_metres: float = 2.0) -> Dictionary:
	var corners: Array[Dictionary] = [
		screen_to_world(camera, 0.0, 0.0),
		screen_to_world(camera, float(camera["width"]), 0.0),
		screen_to_world(camera, 0.0, float(camera["height"])),
		screen_to_world(camera, float(camera["width"]), float(camera["height"])),
	]
	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF
	for c in corners:
		min_x = minf(min_x, float(c["x"]))
		max_x = maxf(max_x, float(c["x"]))
		min_y = minf(min_y, float(c["y"]))
		max_y = maxf(max_y, float(c["y"]))
	return {"minX": min_x - margin_metres, "minY": min_y - margin_metres, "maxX": max_x + margin_metres, "maxY": max_y + margin_metres}

static func metres_to_rise(metres: float, zoom: float) -> float:
	return metres * zoom * RISE_SCALE

static func project_angle(world_radians: float) -> float:
	return world_radians + PI / 4.0

static func projected_radii(metres: float, zoom: float) -> Dictionary:
	var rx: float = metres * zoom * (float(TILE_WIDTH_RATIO) / 2.0 * sqrt(2.0))
	return {"rx": rx, "ry": rx * float(TILE_HEIGHT_RATIO) / float(TILE_WIDTH_RATIO)}

static func map_raster_size(map_w: int, map_h: int, zoom: float) -> Dictionary:
	var half_w: float = zoom * float(TILE_WIDTH_RATIO) / 2.0
	var half_h: float = zoom * float(TILE_HEIGHT_RATIO) / 2.0
	return {
		"width": ceili(float(map_w + map_h) * half_w),
		"height": ceili(float(map_w + map_h) * half_h),
		"originX": float(map_h) * half_w,
		"originY": 0.0,
	}

static func tile_raster_position(tx: int, ty: int, zoom: float, origin_x: float) -> Dictionary:
	var half_w: float = zoom * float(TILE_WIDTH_RATIO) / 2.0
	var half_h: float = zoom * float(TILE_HEIGHT_RATIO) / 2.0
	return {"sx": origin_x + float(tx - ty - 1) * half_w, "sy": float(tx + ty) * half_h}
