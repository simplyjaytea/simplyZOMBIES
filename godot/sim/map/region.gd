class_name SimRegion
extends RefCounted

# The region assembler. One continuous coordinate space holding several districts, which is docs/24's
# region built at the size the measurement allows rather than at the size docs/24 asks for.
#
# **It calls the district generator; it does not fork it.** `SimWorldgen.generate` assumes a square
# map whose edge it walls (`_border`) and whose whole area every pass scans -- the streets, the
# parcels, the siting, the survivability walk and all four dressing passes. Making those eleven
# passes rect-relative would be a rewrite that moved every layout and invalidated every measured
# band. So each cell is generated **as its own district, at its own full size**, and blitted in.
# Per district the assumption is exactly right: docs/24 says a district *has* a border wall, and
# `connectionPoints` are the openings in it.
#
# The property that buys: a cell's sub-rect in the finished region is byte-identical to generating
# that district alone on the same seed. `check_m2_region.gd`'s IDENTITY lane asserts it, and it is
# the strongest assertion available here -- it proves the assembler moved nothing rather than
# proving it moved the right things.
#
# **Determinism costs nothing.** A cell's seed is `derive_seed(region_seed, "region.<x>.<y>.<id>")`
# and *that* is what the existing `_stream(seed, "worldgen.<pass>")` chain derives from, so no
# worldgen pass changed at all and swapping one cell's district re-rolls only that cell. The
# region's own passes take their own names off the region seed, the way every worldgen pass does.
#
# **One colony, sited across the whole region.** The owner's call is that the colony can be
# established anywhere, so the annex is not assigned to a district: every cell is generated with
# `annex = false`, candidate lots are gathered from all of them, and the same frontage -> centrality
# -> toss -> ordinal ranking `SimWorldgen.annex_candidates` uses within one district picks the
# winner across four. What that does *not* build is the runtime half -- a player choosing where to
# establish -- which is the vertical-slice plan's Task 8 and is named in docs/23 rather than smuggled
# in here.

const SimTileMapRes = preload("res://sim/map/tilemap.gd")
const SimWorldgenRes = preload("res://sim/map/worldgen.gd")
const SimTemplatesRes = preload("res://sim/map/templates.gd")
const SimPathRes = preload("res://sim/path.gd")
const RngStream = preload("res://sim/rng_stream.gd")
const ContentLoaderRes = preload("res://platform/content_loader.gd")

const DEFAULT_REGION: String = "region.main_area"

# How wide a seam road is, matching `SimWorldgen.OPENING_WIDTH` so a road leaving one district is
# the same width as the road arriving at the next.
const SEAM_WIDTH: int = 3

# How many times the assembler will re-site the colony before giving up. Each attempt re-stamps one
# annex and re-judges; the cells themselves are never regenerated, so this is cheap.
const MAX_SITINGS: int = 12


# A region's own stream, named the way the worldgen passes are so the two cannot collide.
static func _stream(seed_val: int, pass_name: String) -> Variant:
	return RngStream.new(RngStream.derive_seed(seed_val, "region.%s" % pass_name))


# The seed one cell generates under. The district id is in the derivation on purpose: changing which
# district sits in a cell re-rolls that cell and leaves its neighbours untouched, which is the
# property the procedural-expansion end goal will want.
static func _cell_seed(seed_val: int, cx: int, cy: int, district_id: String) -> int:
	return RngStream.derive_seed(seed_val, "region.%d.%d.%s" % [cx, cy, district_id])


# Every region a content tree declares, by id. Absent is loud for the same reason a missing district
# is: a default region would build a world that is not the one the run asked for, and nothing
# downstream would ever say so.
static func region_of(tree: Dictionary, region_id: String) -> Dictionary:
	for path in _sorted_keys(tree):
		if not path.begins_with("regions/"):
			continue
		var entry: Variant = tree[path]
		if entry is Dictionary and String((entry as Dictionary).get("id", "")) == region_id:
			return entry as Dictionary
	push_error("region: no region %s in content" % region_id)
	return {}


static func _sorted_keys(tree: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for k in tree.keys():
		keys.append(String(k))
	keys.sort()
	return keys


# The cells of a region, in a fixed (y, x) order. Sorted rather than taken in declaration order for
# the reason `templates_of` sorts by id: nothing this assembler does may depend on the order content
# happened to be written in.
static func cells_of(region: Dictionary) -> Array:
	var raw: Array = region.get("cells", []) as Array
	var out: Array = []
	for entry in raw:
		if entry is Dictionary:
			out.append(entry as Dictionary)
	out.sort_custom(func(a, b) -> bool:
		var ay: int = int((a as Dictionary).get("y", 0))
		var by: int = int((b as Dictionary).get("y", 0))
		if ay != by:
			return ay < by
		return int((a as Dictionary).get("x", 0)) < int((b as Dictionary).get("x", 0))
	)
	return out


# The region's side in tiles: the cells across an axis at `cellTiles` each, plus a seam between
# every adjacent pair. A content number rather than a constant, because the measurement that sized
# it has no headroom (docs/23's record) and lowering it must not need a code change.
static func side_of(region: Dictionary) -> int:
	var cell_tiles: int = maxi(1, int(region.get("cellTiles", SimTileMapRes.DISTRICT_TILES)))
	var seam: int = maxi(0, int(region.get("seamTiles", 0)))
	var cols: int = 1
	var rows: int = 1
	for cell in cells_of(region):
		cols = maxi(cols, int((cell as Dictionary).get("x", 0)) + 1)
		rows = maxi(rows, int((cell as Dictionary).get("y", 0)) + 1)
	var across: int = maxi(cols, rows)
	return across * cell_tiles + maxi(0, across - 1) * seam


# Where a cell's top-left corner lands in the region.
static func origin_of(region: Dictionary, cell: Dictionary) -> Vector2i:
	var cell_tiles: int = maxi(1, int(region.get("cellTiles", SimTileMapRes.DISTRICT_TILES)))
	var seam: int = maxi(0, int(region.get("seamTiles", 0)))
	return Vector2i(
		int(cell.get("x", 0)) * (cell_tiles + seam),
		int(cell.get("y", 0)) * (cell_tiles + seam),
	)


# The whole assembly. Pure in `(seed, region, content)` the way `SimWorldgen.generate` is pure in
# `(seed, size, content, district)`, so a save keeps regenerating the region from its seed and the
# world's snapshot never grows a map.
# `reject` mirrors `SimWorldgen.generate`'s: a Callable handed the candidate rect, answering true to
# refuse it and move to the next-ranked lot. It exists so the re-site path can be driven from a gate
# without having to author a region that fails on purpose -- the same reason the district generator
# carries one, and the same lane shape (`check_m2_district`'s re-site lane) tests it.
static func generate(seed_val: int, region_id: String = DEFAULT_REGION, content: Variant = null, dress: bool = true, reject: Callable = Callable()) -> Variant:
	var tree: Dictionary = content as Dictionary if content is Dictionary else ContentLoaderRes.load_tree()
	var region: Dictionary = region_of(tree, region_id)
	if region.is_empty():
		return SimTileMapRes.blank_map(SimTileMapRes.DISTRICT_TILES, SimTileMapRes.DISTRICT_TILES)
	var cells: Array = cells_of(region)
	if cells.is_empty():
		push_error("region: %s declares no cells" % region_id)
		return SimTileMapRes.blank_map(SimTileMapRes.DISTRICT_TILES, SimTileMapRes.DISTRICT_TILES)

	var cell_tiles: int = maxi(1, int(region.get("cellTiles", SimTileMapRes.DISTRICT_TILES)))
	var side: int = side_of(region)
	var map: Variant = SimTileMapRes.blank_map(side, side)

	# 1. Every cell as its own district, colonyless, blitted in. `annex = false` throughout: the
	#    colony is sited across the finished region below rather than inside one cell.
	for cell_value in cells:
		var cell: Dictionary = cell_value as Dictionary
		var district_id: String = String(cell.get("district", SimWorldgenRes.DEFAULT_DISTRICT))
		var cell_seed: int = _cell_seed(seed_val, int(cell.get("x", 0)), int(cell.get("y", 0)), district_id)
		var sub: Variant = SimWorldgenRes.generate(cell_seed, cell_tiles, tree, district_id, dress, Callable(), false)
		_paste(map, sub, origin_of(region, cell))

	# 2. The seams, joining the openings the districts already carved in their own walls. Derived
	#    from those openings rather than drawn, so a seam costs no draw and is identical on every
	#    seed for a given pair of districts -- the same argument the bridges over a river make.
	_seams(map, region, cells)

	# 3. The colony, anywhere in the region. Re-sited on the next-ranked lot when the region is not
	#    survivable, which is where `SimWorldgen.generate`'s `reject` hook finally has a production
	#    reader rather than only a gate one.
	_site_colony(seed_val, map, tree, region, cells, cell_tiles, reject)
	# Last, because it needs to know which cell the colony landed in.
	_write_spawn_edges(map, region, cells, cell_tiles)
	# What the map is made of, so the population readings can ask cells rather than extent.
	map.region_cells = cells.size()
	map.region_cell_tiles = cell_tiles
	map.region_cell_stride = cell_tiles + maxi(0, int(region.get("seamTiles", 0)))
	return map


# Blit one generated district into the region, offsetting everything it carries.
#
# Modelled on `SimTemplates.stamp`, which is the precedent for offsetting records as it copies. What
# `stamp` does not have to do -- and this does -- is carry the four manifests the generator writes.
# Each is a plain Array of plain records in absolute tiles, so each needs the origin added, and
# `map.streets` is the one that is not uniform: `axis` says which of its fields is the cross-axis.
static func _paste(map: Variant, sub: Variant, at: Vector2i) -> void:
	var w: int = int(map.w)
	var h: int = int(map.h)
	var sw: int = int(sub.w)
	var sh: int = int(sub.h)
	# Read the packed arrays out to locals and write them back: a PackedByteArray reached through a
	# property is a value in GDScript, and mutating it in place through `sub.tiles[i]` would be
	# editing a copy (CLAUDE.md's first trap). `map.tiles[dst] = ...` is safe because `map.tiles`
	# resolves to the same array object each time, but the read side is copied once here anyway
	# because it is read w*h times.
	var stiles: PackedByteArray = sub.tiles
	var ssurf: PackedByteArray = sub.surfaces
	var sind: PackedByteArray = sub.indoors
	for j in sh:
		var ty: int = at.y + j
		if ty < 0 or ty >= h:
			continue
		for i in sw:
			var tx: int = at.x + i
			if tx < 0 or tx >= w:
				continue
			var src: int = j * sw + i
			var dst: int = ty * w + tx
			map.tiles[dst] = stiles[src]
			map.surfaces[dst] = ssurf[src]
			map.indoors[dst] = sind[src]

	for record in sub.buildings as Array:
		var b: Dictionary = (record as Dictionary).duplicate(true)
		b["x"] = int(b.get("x", 0)) + at.x
		b["y"] = int(b.get("y", 0)) + at.y
		var doors: Array = []
		for door in b.get("doors", []) as Array:
			var d: Dictionary = (door as Dictionary).duplicate(true)
			d["x"] = int(d.get("x", 0)) + at.x
			d["y"] = int(d.get("y", 0)) + at.y
			doors.append(d)
		b["doors"] = doors
		(map.buildings as Array).append(b)

	# The axis convention, and the one place a mix-up here would be silent: `axis == "x"` means the
	# span is a *vertical* street standing at column `at`, running `from`..`to` down the rows. So
	# `at` takes the x offset and `from`/`to` take the y offset, and the other way round for "y".
	# Getting it backwards draws the road paint and the path pass down the wrong lines, on a map
	# that still looks plausible. `check_m2_region.gd`'s MANIFEST lane is what refuses it.
	for span_value in sub.streets as Array:
		var span: Dictionary = (span_value as Dictionary).duplicate(true)
		var horizontal: bool = String(span.get("axis", "x")) == "y"
		span["at"] = int(span.get("at", 0)) + (at.y if horizontal else at.x)
		span["from"] = int(span.get("from", 0)) + (at.x if horizontal else at.y)
		span["to"] = int(span.get("to", 0)) + (at.x if horizontal else at.y)
		(map.streets as Array).append(span)

	for vehicle_value in sub.vehicles as Array:
		var v: Dictionary = (vehicle_value as Dictionary).duplicate(true)
		v["x"] = int(v.get("x", 0)) + at.x
		v["y"] = int(v.get("y", 0)) + at.y
		(map.vehicles as Array).append(v)

	for site_value in sub.sites as Array:
		var site: Dictionary = (site_value as Dictionary).duplicate(true)
		site["x"] = int(site.get("x", 0)) + at.x
		site["y"] = int(site.get("y", 0)) + at.y
		(map.sites as Array).append(site)


# The seams: short roads joining adjacent districts through the openings their own walls already
# carry. Read off the **tiles** rather than off what `connectionPoints` declared, which is the
# discipline `SimWorldgen._connection_tiles` states -- an opening the generator meant to carve and
# did not is exactly the failure this should find rather than paper over.
#
# No draw anywhere in here. A seam is fully determined by where the two districts put their
# openings, so it is the same on every seed for a given pair, and the region's stream stays unspent
# for anything that genuinely needs randomness later.
static func _seams(map: Variant, region: Dictionary, cells: Array) -> void:
	var cell_tiles: int = maxi(1, int(region.get("cellTiles", SimTileMapRes.DISTRICT_TILES)))
	var seam: int = maxi(0, int(region.get("seamTiles", 0)))
	if seam <= 0:
		# Districts butt up against each other: the two walls touch, so there is no gap to bridge
		# and the openings already meet. Legal, and the region gate's seam lane still checks the
		# flood reaches every cell.
		return
	var by_pos: Dictionary = {}
	for cell_value in cells:
		var c: Dictionary = cell_value as Dictionary
		by_pos[Vector2i(int(c.get("x", 0)), int(c.get("y", 0)))] = c
	for cell_value2 in cells:
		var cell: Dictionary = cell_value2 as Dictionary
		var pos := Vector2i(int(cell.get("x", 0)), int(cell.get("y", 0)))
		var origin: Vector2i = origin_of(region, cell)
		# East, then south. Only two directions, because every pair is visited once from its
		# top-left member and a seam is symmetric.
		if by_pos.has(pos + Vector2i(1, 0)):
			var x0: int = origin.x + cell_tiles
			for opening in _openings_on(map, origin, cell_tiles, "east"):
				_carve_seam(map, Vector2i(x0, int(opening)), Vector2i(1, 0), seam)
		if by_pos.has(pos + Vector2i(0, 1)):
			var y0: int = origin.y + cell_tiles
			for opening2 in _openings_on(map, origin, cell_tiles, "south"):
				_carve_seam(map, Vector2i(int(opening2), y0), Vector2i(0, 1), seam)


# The rows (or columns) where a district's own wall is open on one side, read off the tiles. A
# district with no opening on that side answers nothing, and the seam simply is not carved -- which
# `check_m2_district`'s road lane already refuses at the district level, so it cannot be silent.
static func _openings_on(map: Variant, origin: Vector2i, cell_tiles: int, side: String) -> Array:
	var out: Array = []
	var w: int = int(map.w)
	var h: int = int(map.h)
	if side == "east":
		var col: int = origin.x + cell_tiles - 1
		for j in cell_tiles:
			var ty: int = origin.y + j
			if col < 0 or ty < 0 or col >= w or ty >= h:
				continue
			if int(map.tiles[ty * w + col]) == SimTileMapRes.Tile.Floor:
				out.append(ty)
	else:
		var row: int = origin.y + cell_tiles - 1
		for i in cell_tiles:
			var tx: int = origin.x + i
			if tx < 0 or row < 0 or tx >= w or row >= h:
				continue
			if int(map.tiles[row * w + tx]) == SimTileMapRes.Tile.Floor:
				out.append(tx)
	return out


# One seam: a straight run of road across the gap, the district's own street surface under it. Also
# recorded into `map.streets`, so the road paint draws it and the path pass can find it -- a seam
# nothing else agrees is a road is a seam that draws unpainted.
static func _carve_seam(map: Variant, from: Vector2i, step: Vector2i, seam: int) -> void:
	var w: int = int(map.w)
	var h: int = int(map.h)
	var horizontal: bool = step.x != 0
	# The run itself, plus the wall tiles either end that the openings already pierced.
	for i in seam:
		var at: Vector2i = from + step * i
		for k in range(-(SEAM_WIDTH / 2), SEAM_WIDTH / 2 + 1):
			var tx: int = at.x + (0 if horizontal else k)
			var ty: int = at.y + (k if horizontal else 0)
			if tx < 0 or ty < 0 or tx >= w or ty >= h:
				continue
			var idx: int = ty * w + tx
			map.tiles[idx] = SimTileMapRes.Tile.Floor
			map.surfaces[idx] = SimTileMapRes.SURFACE_PAVED
			map.indoors[idx] = 0
	var along_from: int = (from.x if horizontal else from.y)
	# The convention, stated because it is the exact thing `_paste` above warns about and it would
	# be just as silent here: `axis "y"` is a **horizontal** street standing at row `at`, and
	# `axis "x"` a vertical one at column `at`. A seam stepping east-west is therefore "y".
	(map.streets as Array).append({
		"axis": "y" if horizontal else "x",
		"at": (from.y if horizontal else from.x) - (SEAM_WIDTH / 2),
		"width": SEAM_WIDTH,
		"from": along_from,
		"to": along_from + seam - 1,
		"surface": SimTileMapRes.SURFACE_PAVED,
		"seam": true,
	})


# The colony, sited across the whole region rather than inside a district.
#
# This is the owner's "the colony can be established anywhere" made mechanical at generation time.
# Every cell was generated colonyless, so no lot is spoken for; candidates are gathered from all of
# them and ranked by exactly the order `SimWorldgen.annex_candidates` uses within one district --
# street frontage first, then centrality, then a per-lot toss, then the ordinal. Ranking them
# per-cell and then merging is what makes "anywhere" true: the winner is whichever lot in the region
# ranks highest, not whichever district was named first.
#
# The retry loop is `SimWorldgen.generate`'s own, one level up: stamp the best candidate, judge the
# finished region, and on a refusal move to the next-ranked lot. That gives `generate`'s `reject`
# hook -- until now reachable only from `check_m2_district`'s re-site lane, and documented there as
# a test hook -- its first production reader.
static func _site_colony(seed_val: int, map: Variant, tree: Dictionary, region: Dictionary, cells: Array, cell_tiles: int, reject: Callable = Callable()) -> void:
	var patch: Variant = SimWorldgenRes.annex_template_of(tree)
	if not (patch is Dictionary):
		return
	var footprint: Vector2i = SimTemplatesRes.footprint(patch as Dictionary)
	if footprint.x <= 0 or footprint.y <= 0:
		return

	var ranked: Array = _region_candidates(seed_val, map, tree, region, cells, cell_tiles, footprint)
	if ranked.is_empty():
		push_error("region: no lot in any cell can hold the colony; the region ships without one")
		return

	var attempts: int = mini(MAX_SITINGS, ranked.size())
	for attempt in attempts:
		var rect: Rect2i = ranked[attempt] as Rect2i
		SimTemplatesRes.stamp(map, patch as Dictionary, rect.position.x, rect.position.y)
		var report: Dictionary = SimWorldgenRes.survivability_report(map)
		var refused: bool = not bool(report["ok"])
		if not refused and not reject.is_null():
			refused = bool(reject.call(rect))
		if not refused:
			return
		if attempt + 1 >= attempts:
			# Loud and last-kept, the same shape `SimWorldgen.generate` uses when a district can
			# site no survivable colony: a region that cannot is a content bug, and shipping it
			# quietly would put a player on a start docs/01 says may not exist.
			push_error("region: sited no survivable colony on any of %d candidate lots; keeping %s, which failed %s" % [
				attempts, str(rect), str(report.get("failed", [])),
			])
			return
		# Undo the stamp before trying the next lot, by regenerating the cell it landed in. Cheaper
		# and more honest than trying to remember what was under it: the cell is a pure function of
		# its own seed, so this restores exactly what the assembler blitted the first time.
		_restore_cell(seed_val, map, tree, region, cells, cell_tiles, rect)


# Candidate lots from every cell, merged and ranked as one pool.
static func _region_candidates(seed_val: int, map: Variant, tree: Dictionary, region: Dictionary, cells: Array, cell_tiles: int, footprint: Vector2i) -> Array:
	var layout_map: Variant = _layout_region(seed_val, tree, region, cells, cell_tiles)
	var scored: Array = []
	var ordinal: int = 0
	for cell_value in cells:
		var cell: Dictionary = cell_value as Dictionary
		var district_id: String = String(cell.get("district", SimWorldgenRes.DEFAULT_DISTRICT))
		var district: Dictionary = SimWorldgenRes.district_of(tree, district_id)
		if district.is_empty():
			continue
		var cell_seed: int = _cell_seed(seed_val, int(cell.get("x", 0)), int(cell.get("y", 0)), district_id)
		# The same layout the cell was generated from, re-derived rather than remembered: it is a
		# pure function of (seed, size, district), which is the property `SimWorldgen.generate`'s
		# own retry loop already leans on.
		var ground: Dictionary = SimWorldgenRes.layout(cell_seed, cell_tiles, district)
		var origin: Vector2i = origin_of(region, cell)
		for lot_value in SimWorldgenRes.annex_candidates(cell_seed, ground["map"], ground["parcels"] as Array, footprint):
			var lot: Rect2i = lot_value as Rect2i
			var rect := Rect2i(lot.position + origin, lot.size)
			# Scored against the **layout** region rather than the assembled one, and this is the
			# thing that took a diagnosis rather than a guess. Frontage read off the finished map
			# moved the colony 45 tiles when the dressing was switched off: `_rubble` heaves patches
			# up through a street, `_street_frontage` counts paved neighbours, so the dressing was
			# silently re-ranking the lots. docs/30 records the same rule for a district -- "a colony
			# sited off the trees would move when the trees were switched off" -- and this is that
			# rule at region scale. The layout carries the streets and the seams and nothing that a
			# dressing pass may touch, so a lot facing a seam still scores as the through-road lot it
			# is, without the ranking depending on where a puddle of rubble landed.
			var fronting: int = SimWorldgenRes._street_frontage(layout_map, rect)
			ordinal += 1
			if fronting <= 0:
				continue
			# Centrality is measured **within the cell**, not within the region, and that took a
			# measurement to get right. Ranking on region centrality put the colony at the meeting
			# point of the four districts -- which sounds appealing and is not: it lands hard
			# against its own cell's edges, and the night band then starts **32 m** from the gate
			# against a district's 122. `GATE_EXCLUSION` is 32, so packets would arrive at the
			# exclusion radius itself. Per-cell centrality is what `annex_candidates` computes
			# internally and what every measured director band was calibrated under, so the colony
			# sits centrally in whichever district wins on frontage and the distances hold.
			var centre_local := Vector2i(lot.position.x + lot.size.x / 2, lot.position.y + lot.size.y / 2)
			scored.append({
				"rect": rect,
				"fronting": fronting,
				"centre": absi(2 * centre_local.x - cell_tiles) + absi(2 * centre_local.y - cell_tiles),
				"at": ordinal,
			})
	scored.sort_custom(func(a, b) -> bool:
		var x: Dictionary = a as Dictionary
		var y: Dictionary = b as Dictionary
		if int(x["fronting"]) != int(y["fronting"]):
			return int(x["fronting"]) > int(y["fronting"])
		if int(x["centre"]) != int(y["centre"]):
			return int(x["centre"]) < int(y["centre"])
		return int(x["at"]) < int(y["at"])
	)
	var out: Array = []
	for entry in scored:
		out.append((entry as Dictionary)["rect"])
	return out


# Put a cell back the way the assembler blitted it, used to undo a refused colony stamp.
static func _restore_cell(seed_val: int, map: Variant, tree: Dictionary, region: Dictionary, cells: Array, cell_tiles: int, touched: Rect2i) -> void:
	for cell_value in cells:
		var cell: Dictionary = cell_value as Dictionary
		var origin: Vector2i = origin_of(region, cell)
		var bounds := Rect2i(origin, Vector2i(cell_tiles, cell_tiles))
		if not bounds.intersects(touched):
			continue
		var district_id: String = String(cell.get("district", SimWorldgenRes.DEFAULT_DISTRICT))
		var cell_seed: int = _cell_seed(seed_val, int(cell.get("x", 0)), int(cell.get("y", 0)), district_id)
		var sub: Variant = SimWorldgenRes.generate(cell_seed, cell_tiles, tree, district_id, true, Callable(), false)
		_paste_tiles_only(map, sub, origin)


# The tile half of `_paste`, for a restore: the manifests were appended once and are still correct,
# so re-appending them would double every building in the cell.
static func _paste_tiles_only(map: Variant, sub: Variant, at: Vector2i) -> void:
	var w: int = int(map.w)
	var h: int = int(map.h)
	var sw: int = int(sub.w)
	var sh: int = int(sub.h)
	var stiles: PackedByteArray = sub.tiles
	var ssurf: PackedByteArray = sub.surfaces
	var sind: PackedByteArray = sub.indoors
	for j in sh:
		var ty: int = at.y + j
		if ty < 0 or ty >= h:
			continue
		for i in sw:
			var tx: int = at.x + i
			if tx < 0 or tx >= w:
				continue
			var src: int = j * sw + i
			var dst: int = ty * w + tx
			map.tiles[dst] = stiles[src]
			map.surfaces[dst] = ssurf[src]
			map.indoors[dst] = sind[src]


# The region as its layout alone: passes 1 to 3.5 per cell (the wall, the streets, the lots and the
# water) plus the seams, and nothing a dressing pass may touch. Built only to rank the colony's
# candidate lots against, so that ranking cannot depend on the dressing -- see `_region_candidates`.
# Cheap: `layout` is three passes and no siting, no buildings, no loot.
static func _layout_region(seed_val: int, tree: Dictionary, region: Dictionary, cells: Array, cell_tiles: int) -> Variant:
	var side: int = side_of(region)
	var out: Variant = SimTileMapRes.blank_map(side, side)
	for cell_value in cells:
		var cell: Dictionary = cell_value as Dictionary
		var district_id: String = String(cell.get("district", SimWorldgenRes.DEFAULT_DISTRICT))
		var district: Dictionary = SimWorldgenRes.district_of(tree, district_id)
		if district.is_empty():
			continue
		var cell_seed: int = _cell_seed(seed_val, int(cell.get("x", 0)), int(cell.get("y", 0)), district_id)
		var ground: Dictionary = SimWorldgenRes.layout(cell_seed, cell_tiles, district)
		_paste_tiles_only(out, ground["map"], origin_of(region, cell))
	_seams(out, region, cells)
	return out


# How deep the spawn band runs inside the annex cell's wall, matching the three tiles
# `SimDirector._edges_by_side` scans on a district so the two answers are the same shape.
const SPAWN_BAND: int = 3


# The band the director may place night packets on, written as the **annex cell's own inner band**.
#
# The scan this replaces is not broken on a region -- it finds 4,157 legal tiles on Ashgrove, more
# than a district's 1,984 -- it is answering the wrong question. Those tiles sit 215 to 432 m from
# the colony gate where a district's sit at 122 to 182, and docs/24 prices a gunshot at 257 m
# *because* that is one district. A packet starting past that has two districts to cross before it
# is pressure at all, so night after night would arrive diluted rather than absent, which is the
# harder kind of wrong to notice.
#
# Writing the annex cell's band keeps every measured director band at the distance it was
# calibrated against. What it deliberately does **not** do, named so the next session does not think
# it was missed: it does not let the other three districts contribute. Pressure arriving from across
# the region is a design question (and a balance one), not an oversight -- it wants the owner and a
# measurement, not a default.
static func _write_spawn_edges(map: Variant, region: Dictionary, cells: Array, cell_tiles: int) -> void:
	(map.spawn_edges as Array).clear()
	var annex: Rect2i = SimTileMapRes.annex_rect(map)
	if annex.size.x <= 0 or annex.size.y <= 0:
		return
	var host := Rect2i(0, 0, 0, 0)
	for cell_value in cells:
		var bounds := Rect2i(origin_of(region, cell_value as Dictionary), Vector2i(cell_tiles, cell_tiles))
		if bounds.encloses(annex):
			host = bounds
	if host.size.x <= 0:
		return
	write_band(map, host)


# One cell's outer band, written into `map.spawn_edges`.
#
# Public, and separated from the caller above, because the band has a **second** writer now: when
# the player establishes a camp in another cell, `SimCamp.sync_map` moves the band to that cell for
# exactly the reason this one exists. Two copies of the bucketing below is precisely the drift the
# comment above warns about, so there is one.
static func write_band(map: Variant, host: Rect2i) -> void:
	(map.spawn_edges as Array).clear()
	if host.size.x <= 0 or host.size.y <= 0:
		return
	# Row-major over the cell, keeping only its outer band, bucketed by side in
	# `SimDirector.SIDE_NAMES` order. Legality is left to the director: it already asks
	# `_legal_tile`, and asking here as well would be two copies of a rule that can drift.
	var lo: Vector2i = host.position
	var hi: Vector2i = host.position + host.size - Vector2i.ONE
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var north: bool = y - lo.y < SPAWN_BAND
			var south: bool = hi.y - y < SPAWN_BAND
			var west: bool = x - lo.x < SPAWN_BAND
			var east: bool = hi.x - x < SPAWN_BAND
			if not (north or south or east or west):
				continue
			var side: int = 0
			if north:
				side = 0
			elif south:
				side = 2
			elif east:
				side = 1
			else:
				side = 3
			(map.spawn_edges as Array).append({"side": side, "x": x, "y": y})
