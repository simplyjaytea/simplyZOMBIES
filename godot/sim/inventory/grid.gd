class_name SimGrid
extends RefCounted

static func footprint(size: Dictionary, rotated: bool) -> Dictionary:
	if rotated:
		return {"w": int(size["h"]), "h": int(size["w"])}
	return {"w": int(size["w"]), "h": int(size["h"])}

static func within_bounds(grid: Dictionary, x: int, y: int, size: Dictionary) -> bool:
	return x >= 0 and y >= 0 and x + int(size["w"]) <= int(grid["w"]) and y + int(size["h"]) <= int(grid["h"])

static func _rects_overlap(ax: int, ay: int, a: Dictionary, bx: int, by: int, b: Dictionary) -> bool:
	return ax < bx + int(b["w"]) and bx < ax + int(a["w"]) and ay < by + int(b["h"]) and by < ay + int(a["h"])

static func fits(grid: Dictionary, placements: Array, size_of: Callable, candidate: Dictionary) -> bool:
	# TS guard: Number.isInteger(x/y) — reject fractional coordinates that JSON might carry.
	if typeof(candidate["x"]) == TYPE_FLOAT and float(candidate["x"]) != float(int(candidate["x"])):
		return false
	if typeof(candidate["y"]) == TYPE_FLOAT and float(candidate["y"]) != float(int(candidate["y"])):
		return false
	var size: Dictionary = footprint(size_of.call(int(candidate["item"])), bool(candidate["rotated"]))
	if not within_bounds(grid, int(candidate["x"]), int(candidate["y"]), size):
		return false
	for placed in placements:
		var p: Dictionary = placed as Dictionary
		if int(p["item"]) == int(candidate["item"]):
			continue
		var other: Dictionary = footprint(size_of.call(int(p["item"])), bool(p["rotated"]))
		if _rects_overlap(int(candidate["x"]), int(candidate["y"]), size, int(p["x"]), int(p["y"]), other):
			return false
	return true

static func find_free_slot(grid: Dictionary, placements: Array, size_of: Callable, item: int) -> Variant:
	var size: Dictionary = size_of.call(item) as Dictionary
	var orientations: Array = [false] if int(size["w"]) == int(size["h"]) else [false, true]
	for rotated in orientations:
		var turned: Dictionary = footprint(size, rotated as bool)
		for y in range(0, int(grid["h"]) - int(turned["h"]) + 1):
			for x in range(0, int(grid["w"]) - int(turned["w"]) + 1):
				var cand: Dictionary = {"item": item, "x": x, "y": y, "rotated": rotated}
				if fits(grid, placements, size_of, cand):
					return cand
	return null

static func occupancy(grid: Dictionary, placements: Array, size_of: Callable) -> PackedInt32Array:
	var cells: PackedInt32Array = PackedInt32Array()
	cells.resize(int(grid["w"]) * int(grid["h"]))
	for i in cells.size():
		cells[i] = -1
	for placed in placements:
		var p: Dictionary = placed as Dictionary
		var size: Dictionary = footprint(size_of.call(int(p["item"])), bool(p["rotated"]))
		for dy in int(size["h"]):
			for dx in int(size["w"]):
				var x: int = int(p["x"]) + dx
				var y: int = int(p["y"]) + dy
				if x < 0 or y < 0 or x >= int(grid["w"]) or y >= int(grid["h"]):
					continue
				cells[y * int(grid["w"]) + x] = int(p["item"])
	return cells

static func item_at(placements: Array, size_of: Callable, x: int, y: int) -> Variant:
	for placed in placements:
		var p: Dictionary = placed as Dictionary
		var size: Dictionary = footprint(size_of.call(int(p["item"])), bool(p["rotated"]))
		if x >= int(p["x"]) and x < int(p["x"]) + int(size["w"]) and y >= int(p["y"]) and y < int(p["y"]) + int(size["h"]):
			return int(p["item"])
	return null

static func sort_placements(placements: Array) -> void:
	placements.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["y"]) != int(b["y"]):
			return int(a["y"]) < int(b["y"])
		if int(a["x"]) != int(b["x"]):
			return int(a["x"]) < int(b["x"])
		return int(a["item"]) < int(b["item"])
	)
