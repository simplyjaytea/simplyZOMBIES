class_name SimTemplates
extends RefCounted

# Stamping an authored footprint onto a generated district.
#
# docs/24's "authored templates, procedurally assembled": the arrays are content, the origin is
# the generator's. This is `apply_patch` with the origin taken as an argument instead of read out
# of the entry, plus the two things a blit could not do -- carrying the template's anchors across
# to the map so the colony's coordinates stop being compile-time constants (docs/30, "the
# generator sites the annex"), and carrying its `loot` rows across as absolute `map.sites` records
# so an authored cupboard travels with the template that authored it.
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
	var sites: Array = _write_loot(map, template, origin_x, origin_y)
	return {
		"rect": {"x": origin_x, "y": origin_y, "w": tw, "h": th},
		"anchors": written,
		"sites": sites,
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


# Template loot is template-relative, exactly like the anchors and for the same reason: a template
# may not name an absolute district tile (building.schema.json says so outright), and the origin is
# the placer's decision. So a `loot` row becomes a `map.sites` record here, in absolute tiles, and
# `SimBoot.place_loot` is what turns that into a scatter or a container at boot.
#
# Appended rather than assigned: the generator's `worldgen.sites` pass writes into the same list,
# and several stamps onto one district each contribute their own rows. Clipped the way the tiles
# are -- a row that falls off the map is dropped rather than wrapped, so a template stamped over an
# edge does not put a cupboard on the far side of the district.
#
# Returns what it wrote, so a caller that chose the origin does not have to recompute it.
static func _write_loot(map: Variant, template: Dictionary, origin_x: int, origin_y: int) -> Array:
	var rows: Variant = template.get("loot")
	if not (rows is Array):
		return []
	var written: Array = []
	# Read out, appended to, written back: `map.sites` is a plain Array on the map object rather
	# than a PackedArray, so this is a reference either way -- but the round trip is explicit
	# because the packed-array trap in CLAUDE.md is exactly this shape gone wrong.
	var table: Array = map.sites as Array
	for row_v in rows as Array:
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v as Dictionary
		var tile: Variant = row.get("tile")
		if not (tile is Dictionary):
			continue
		var tx: int = origin_x + int((tile as Dictionary).get("x", 0))
		var ty: int = origin_y + int((tile as Dictionary).get("y", 0))
		if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
			continue
		var record: Dictionary = {"x": tx, "y": ty, "table": String(row.get("table", ""))}
		var kind: String = String(row.get("container", ""))
		if kind != "":
			record["container"] = kind
		table.append(record)
		written.append(record)
	map.sites = table
	return written
