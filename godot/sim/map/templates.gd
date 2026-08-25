class_name SimTemplates
extends RefCounted

# Stamping an authored footprint onto a generated district.
#
# docs/24's "authored templates, procedurally assembled": the arrays are content, the origin is
# the generator's. This is `apply_patch` with the origin taken as an argument instead of read out
# of the entry, plus the one thing a blit could not do -- carrying the template's anchors across
# to the map so the colony's coordinates stop being compile-time constants (docs/30, "the
# generator sites the annex").
#
# Deterministic and RNG-free, like the blit it replaces: which template lands where is the
# placer's decision, made before this is called, and stamping the same template at the same
# origin twice produces the same bytes.

const ANNEX_KEY: String = "annex"


# Blits `template` with its top-left corner at (origin_x, origin_y), clipping anything that falls
# outside the map exactly as apply_patch does -- a template stamped near the edge loses the part
# that hangs over rather than wrapping or raising.
#
# `size` is the building-template spelling and `rect` the map-patch one, so the civic annex's
# existing map entry and a future `content/buildings/` entry both stamp through this one path.
#
# Returns where it landed and the absolute anchors it wrote, so a caller that chose the origin
# does not have to recompute either.
static func stamp(map: Variant, template: Dictionary, origin_x: int, origin_y: int) -> Dictionary:
	var footprint: Dictionary = _footprint(template)
	var tw: int = int(footprint.get("w", 0))
	var th: int = int(footprint.get("h", 0))
	var tiles: Array = template.get("tiles", []) as Array
	var surfaces: Array = template.get("surfaces", []) as Array
	var indoors_arr: Array = template.get("indoors", []) as Array
	for j in th:
		for i in tw:
			var tx: int = origin_x + i
			var ty: int = origin_y + j
			if tx < 0 or ty < 0 or tx >= map.w or ty >= map.h:
				continue
			var li: int = j * tw + i
			var dst: int = ty * map.w + tx
			if li < tiles.size():
				map.tiles[dst] = int(tiles[li])
			if li < surfaces.size():
				map.surfaces[dst] = int(surfaces[li])
			if li < indoors_arr.size():
				map.indoors[dst] = int(indoors_arr[li])
	var written: Dictionary = _write_anchors(map, template, origin_x, origin_y, tw, th)
	return {
		"rect": {"x": origin_x, "y": origin_y, "w": tw, "h": th},
		"anchors": written,
	}


static func _footprint(template: Dictionary) -> Dictionary:
	var size: Variant = template.get("size")
	if size is Dictionary:
		return size as Dictionary
	var rect: Variant = template.get("rect")
	if rect is Dictionary:
		return rect as Dictionary
	return {}


# Template anchors are relative to the footprint; the map wants absolute tiles. Merged rather than
# assigned so several stamps onto one district each contribute their own points, and only a
# template that carries anchors at all claims the annex rect -- an ordinary house stamps without
# renaming where the colony is.
static func _write_anchors(map: Variant, template: Dictionary, origin_x: int, origin_y: int, tw: int, th: int) -> Dictionary:
	var relative: Variant = template.get("anchors")
	if not (relative is Dictionary) or (relative as Dictionary).is_empty():
		return {}
	var written: Dictionary = {}
	for key in (relative as Dictionary).keys():
		var point: Variant = (relative as Dictionary)[key]
		if not (point is Dictionary):
			continue
		written[String(key)] = {
			"x": origin_x + int((point as Dictionary).get("x", 0)),
			"y": origin_y + int((point as Dictionary).get("y", 0)),
		}
	written[ANNEX_KEY] = {"x": origin_x, "y": origin_y, "w": tw, "h": th}
	var table: Dictionary = {}
	var existing: Variant = map.anchors
	if existing is Dictionary:
		table = existing as Dictionary
	for key in written.keys():
		table[key] = written[key]
	map.anchors = table
	return written
