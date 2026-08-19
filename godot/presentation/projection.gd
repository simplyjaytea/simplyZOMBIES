extends RefCounted
# One answer to where a world point lands on screen: top-down orthographic,
# screen x = world x, screen y = world y, zoom pixels per metre. Replaces the
# isometric 2:1 projection (docs/00's reversal of a reversal); src/render/projection.ts
# stays frozen on the old maths with the rest of the TS oracle. Sim never imports this.

static func world_to_screen(camera: Dictionary, x: float, y: float) -> Dictionary:
	var zoom: float = float(camera["zoom"])
	return {
		"sx": (x - float(camera["x"])) * zoom + float(camera["width"]) / 2.0,
		"sy": (y - float(camera["y"])) * zoom + float(camera["height"]) / 2.0,
	}

static func screen_to_world(camera: Dictionary, sx: float, sy: float) -> Dictionary:
	var zoom: float = float(camera["zoom"])
	return {
		"x": (sx - float(camera["width"]) / 2.0) / zoom + float(camera["x"]),
		"y": (sy - float(camera["height"]) / 2.0) / zoom + float(camera["y"]),
	}

# Painter's order: a body lower on screen draws in front (RimWorld y-sort), so an
# upright figure overlaps the tile behind it and nothing else matters.
static func depth_of(_x: float, y: float) -> float:
	return y

static func visible_bounds(camera: Dictionary, margin_metres: float = 2.0) -> Dictionary:
	var zoom: float = float(camera["zoom"])
	var half_w: float = float(camera["width"]) / 2.0 / zoom
	var half_h: float = float(camera["height"]) / 2.0 / zoom
	return {
		"minX": float(camera["x"]) - half_w - margin_metres,
		"minY": float(camera["y"]) - half_h - margin_metres,
		"maxX": float(camera["x"]) + half_w + margin_metres,
		"maxY": float(camera["y"]) + half_h + margin_metres,
	}
