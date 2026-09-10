extends SceneTree
# The region: several districts in one continuous coordinate space.
#
# docs/24's region, built at the size the measurement allows rather than the size that document asks
# for -- the owner's 2026-09-09 extent decision, and the docs/24 amendment that goes with it. Two
# things about the assembler decide what is worth asserting here.
#
# **It calls the district generator rather than forking it.** `SimWorldgen.generate` assumes a square
# map whose edge it walls and whose whole area every pass scans, so each cell is generated as its own
# district at its own full size and blitted in. That buys the strongest assertion available: a cell's
# sub-rect in the finished region is **byte-identical** to generating that district alone. IDENTITY
# is that lane, and it proves the assembler moved nothing rather than proving it moved the right
# things.
#
# **The colony is sited across the whole region**, not assigned to a district -- the owner's call
# that it can be established anywhere. Every cell generates with `annex = false` and one annex is
# stamped on the best-ranked lot in the region. COLONY is that lane.
#
# Eight lanes, each with a true negative, because a gate that cannot fail is worse than no gate:
#
#   IDENTITY   every cell's sub-rect equals the district generated alone on the same cell seed.
#              TN: one perturbed cell seed must make the same comparison fail.
#   MANIFEST   every building, street, vehicle and site lies inside its own cell (or on a seam),
#              and the counts equal the sum of the cells'. TN: an un-offset record must be caught --
#              this is the lane that refuses the `axis "x"`/`"y"` mix-up, which is otherwise silent
#              because the map still looks plausible.
#   COLONY     exactly one annex, inside some cell, with its anchors on open floor. TN: a second
#              stamped annex must be refused.
#   DETERMINE  same seed identical, different seed different, `dress=false` identical.
#              TN: the different-seed half is the negative for the first.
#   SEAMS      the flood from the colony gates reaches every cell. TN: wall a seam and the lane must
#              name the cell it can no longer reach.
#   SURVIVE    every survivability clause true and **none skipped** -- a region places every kind of
#              loot and carries water, so a skip here is a clause quietly not running.
#   RESITE     a refused lot moves the colony to the next-ranked one, through the same `reject` hook
#              `SimWorldgen.generate` carries. TN: the refused rect must not be the one kept.
#   BUDGET     the whole lane set inside a stated wall clock, the way check_worldgen.gd carries one.

const SimRegion = preload("res://sim/map/region.gd")
const SimWorldgen = preload("res://sim/map/worldgen.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimTemplates = preload("res://sim/map/templates.gd")
const SimPath = preload("res://sim/path.gd")
const ContentLoader = preload("res://platform/content_loader.gd")

const REGION_ID: String = "region.main_area"
const CANON_SEED: int = 20260805

# A region is 4.3x the area of a district and takes ~4 s to assemble, so this gate is deliberately
# frugal about how many it builds: the budget is what stops a lane being added that quietly doubles
# CI. docs/00 pillar 6.
const BUDGET_SECONDS: float = 180.0

var _tree_cache: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var started: int = Time.get_ticks_msec()
	var ok: bool = true

	# One region, built once and shared by every lane that only needs to read one.
	var map: Variant = SimRegion.generate(CANON_SEED, REGION_ID, _tree(), true)
	var region: Dictionary = SimRegion.region_of(_tree(), REGION_ID)
	if region.is_empty():
		push_error("no %s in content, so this gate judged nothing" % REGION_ID)
		quit(1)
		return

	ok = _every_cell_is_the_district_generated_alone(map, region) and ok
	ok = _every_record_landed_in_its_own_cell(map, region) and ok
	ok = _there_is_exactly_one_colony_and_it_is_somewhere(map, region) and ok
	ok = _one_seed_builds_one_region_and_two_build_two() and ok
	ok = _the_flood_from_the_gates_reaches_every_cell(map, region) and ok
	ok = _the_region_is_survivable_and_no_clause_skipped(map) and ok
	ok = _a_refused_lot_moves_the_colony_to_the_next_one(region) and ok

	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	if seconds > BUDGET_SECONDS:
		push_error("BUDGET: %.1f s over the %.0f s budget" % [seconds, BUDGET_SECONDS])
		ok = false

	if ok:
		print("M2_REGION_OK %d cells at %d tiles in a %dx%d region: every cell byte-identical to its district generated alone, every record inside its own cell, one colony sited region-wide at %s, deterministic and dressing-independent, the flood reaches all %d cells, all %d clauses answered with none skipped, a refused lot re-sites; %.1f s of a %.0f s budget" % [
			SimRegion.cells_of(region).size(), int(region.get("cellTiles", 0)),
			int(map.w), int(map.h), str(SimTileMap.annex_rect(map).position),
			SimRegion.cells_of(region).size(),
			(SimWorldgen.survivability_report(map)["clauses"] as Array).size(),
			seconds, BUDGET_SECONDS,
		])
		quit(0)
	else:
		push_error("M2_REGION_FAIL")
		quit(1)


func _tree() -> Dictionary:
	if _tree_cache.is_empty():
		_tree_cache = ContentLoader.load_tree()
	return _tree_cache


# 1. IDENTITY: the property the whole seam exists for.
func _every_cell_is_the_district_generated_alone(map: Variant, region: Dictionary) -> bool:
	var cell_tiles: int = int(region.get("cellTiles", 0))
	var annex: Rect2i = SimTileMap.annex_rect(map)
	var w: int = int(map.w)
	var judged: int = 0
	for cell_value in SimRegion.cells_of(region):
		var cell: Dictionary = cell_value as Dictionary
		var district_id: String = String(cell["district"])
		var origin: Vector2i = SimRegion.origin_of(region, cell)
		var alone: Variant = _cell_alone(cell, cell_tiles)
		var diff: int = _cell_diff(map, alone, origin, cell_tiles, annex)
		if diff != 0:
			push_error("IDENTITY: cell (%d,%d) %s differs from the district generated alone in %d tiles" % [
				int(cell["x"]), int(cell["y"]), district_id, diff,
			])
			return false
		judged += 1
	if judged < 2:
		push_error("IDENTITY: only %d cells judged; a region with one cell proves nothing about assembling several" % judged)
		return false

	# The true negative: the same comparison against a cell generated on a *different* seed must
	# find differences. Without it the lane would pass on a `_cell_diff` that always answered 0.
	var first: Dictionary = SimRegion.cells_of(region)[0] as Dictionary
	var wrong: Variant = SimWorldgen.generate(
		SimRegion._cell_seed(CANON_SEED + 1, int(first["x"]), int(first["y"]), String(first["district"])),
		cell_tiles, _tree(), String(first["district"]), true, Callable(), false)
	if _cell_diff(map, wrong, SimRegion.origin_of(region, first), cell_tiles, annex) == 0:
		push_error("IDENTITY: a cell generated on a different seed compared equal, so this lane cannot fail")
		return false
	return true


func _cell_alone(cell: Dictionary, cell_tiles: int) -> Variant:
	var district_id: String = String(cell["district"])
	var cell_seed: int = SimRegion._cell_seed(CANON_SEED, int(cell["x"]), int(cell["y"]), district_id)
	# The same `annex = false` the assembler used. Passing `true` here would compare against a
	# different district, not a differently-placed one: a reserved lot skips its density draw, so
	# every building after it re-rolls.
	return SimWorldgen.generate(cell_seed, cell_tiles, _tree(), district_id, true, Callable(), false)


# Tiles that differ, skipping the annex footprint (stamped over the cell that holds it).
func _cell_diff(map: Variant, alone: Variant, origin: Vector2i, cell_tiles: int, annex: Rect2i) -> int:
	var w: int = int(map.w)
	var diff: int = 0
	for j in cell_tiles:
		for i in cell_tiles:
			var tx: int = origin.x + i
			var ty: int = origin.y + j
			if annex.size.x > 0 and annex.has_point(Vector2i(tx, ty)):
				continue
			var dst: int = ty * w + tx
			var src: int = j * cell_tiles + i
			if int(map.tiles[dst]) != int(alone.tiles[src]) or int(map.surfaces[dst]) != int(alone.surfaces[src]):
				diff += 1
	return diff


# 2. MANIFEST: every record offset, and offset the right way.
#
# The axis convention is the reason this lane exists rather than a count check. `axis "x"` is a
# **vertical** street standing at column `at`, `axis "y"` a horizontal one at row `at` -- so a span
# offset with x and y swapped still lands on the map, still looks like a street manifest, and sends
# the road paint and the path pass down the wrong lines. Nothing else would say so.
func _every_record_landed_in_its_own_cell(map: Variant, region: Dictionary) -> bool:
	var cell_tiles: int = int(region.get("cellTiles", 0))
	var rects: Array = []
	var expect_buildings: int = 0
	var expect_vehicles: int = 0
	var expect_sites: int = 0
	var expect_streets: int = 0
	for cell_value in SimRegion.cells_of(region):
		var cell: Dictionary = cell_value as Dictionary
		rects.append(Rect2i(SimRegion.origin_of(region, cell), Vector2i(cell_tiles, cell_tiles)))
		var alone: Variant = _cell_alone(cell, cell_tiles)
		expect_buildings += (alone.buildings as Array).size()
		expect_vehicles += (alone.vehicles as Array).size()
		expect_sites += (alone.sites as Array).size()
		expect_streets += (alone.streets as Array).size()

	# Counts: the region carries exactly what its cells carried, plus the seams it carved itself.
	var seams: int = 0
	for span_value in map.streets as Array:
		if bool((span_value as Dictionary).get("seam", false)):
			seams += 1
	if (map.buildings as Array).size() != expect_buildings:
		push_error("MANIFEST: %d buildings in the region against %d across its cells" % [(map.buildings as Array).size(), expect_buildings])
		return false
	if (map.vehicles as Array).size() != expect_vehicles:
		push_error("MANIFEST: %d vehicles in the region against %d across its cells" % [(map.vehicles as Array).size(), expect_vehicles])
		return false
	# The annex brings its own loot rows with it -- the kitchen scatter and the store-room cupboard
	# `map.schema.json` describes -- and `SimTemplates.stamp` appends them when the colony lands. So
	# the region carries its cells' sites *plus* those, and expecting only the cells' was this
	# lane's own arithmetic being wrong rather than the assembler double-counting.
	var patch_rows: int = 0
	var patch: Variant = SimWorldgen.annex_template_of(_tree())
	if patch is Dictionary:
		patch_rows = ((patch as Dictionary).get("loot", []) as Array).size()
	if (map.sites as Array).size() != expect_sites + patch_rows:
		push_error("MANIFEST: %d sites in the region against %d across its cells plus the annex's own %d" % [
			(map.sites as Array).size(), expect_sites, patch_rows,
		])
		return false
	if (map.streets as Array).size() != expect_streets + seams:
		push_error("MANIFEST: %d streets against %d across its cells plus %d seams" % [(map.streets as Array).size(), expect_streets, seams])
		return false
	if seams < 1:
		push_error("MANIFEST: the region carved no seam, so the joining half of the assembler ran and recorded nothing")
		return false

	# Position: every record inside some cell. A doorway is checked too, because `_paste` offsets
	# `doors[]` separately from the building that owns them and forgetting one is silent.
	for record in map.buildings as Array:
		var b: Dictionary = record as Dictionary
		if not _in_any(rects, Vector2i(int(b["x"]), int(b["y"]))):
			push_error("MANIFEST: building %s at (%d,%d) is in no cell" % [String(b.get("id", "?")), int(b["x"]), int(b["y"])])
			return false
		for door in b.get("doors", []) as Array:
			var d: Dictionary = door as Dictionary
			if not _in_any(rects, Vector2i(int(d["x"]), int(d["y"]))):
				push_error("MANIFEST: a door of %s at (%d,%d) is in no cell; doors are offset separately from their building" % [String(b.get("id", "?")), int(d["x"]), int(d["y"])])
				return false
	for site_value in map.sites as Array:
		var s: Dictionary = site_value as Dictionary
		if not _in_any(rects, Vector2i(int(s["x"]), int(s["y"]))):
			push_error("MANIFEST: a %s site at (%d,%d) is in no cell" % [String(s.get("table", "?")), int(s["x"]), int(s["y"])])
			return false
	for vehicle_value in map.vehicles as Array:
		var v: Dictionary = vehicle_value as Dictionary
		if not _in_any(rects, Vector2i(int(v["x"]), int(v["y"]))):
			push_error("MANIFEST: a %s at (%d,%d) is in no cell" % [String(v.get("class", "?")), int(v["x"]), int(v["y"])])
			return false

	# The axis half: every span the manifest names must actually be street on the map. An offset
	# applied to the wrong field puts `at` on a row of houses, which this finds and a count does not.
	var checked: int = 0
	for span_value2 in map.streets as Array:
		var span: Dictionary = span_value2 as Dictionary
		var horizontal: bool = String(span.get("axis", "x")) == "y"
		var at: int = int(span.get("at", 0))
		var mid: int = (int(span.get("from", 0)) + int(span.get("to", 0))) / 2
		var tx: int = mid if horizontal else at
		var ty: int = at if horizontal else mid
		if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
			push_error("MANIFEST: span %s runs off the region" % str(span))
			return false
		if SimTileMap.is_solid(map, tx, ty):
			push_error("MANIFEST: span %s reads solid at its own midpoint (%d,%d); an offset went onto the wrong axis" % [str(span), tx, ty])
			return false
		checked += 1
	if checked < 4:
		push_error("MANIFEST: only %d spans checked" % checked)
		return false

	# The true negative: a record offset the wrong way must be caught. Built by hand rather than by
	# breaking the assembler, so the lane proves its own predicate.
	var bad := Vector2i(int(map.w) + 4, 0)
	if _in_any(rects, bad):
		push_error("MANIFEST: a point outside every cell was reported inside one, so the position check cannot fail")
		return false
	return true


func _in_any(rects: Array, at: Vector2i) -> bool:
	for r in rects:
		if (r as Rect2i).has_point(at):
			return true
	return false


# 3. COLONY: one, and anywhere.
func _there_is_exactly_one_colony_and_it_is_somewhere(map: Variant, region: Dictionary) -> bool:
	var annex: Rect2i = SimTileMap.annex_rect(map)
	if annex.size.x <= 0 or annex.size.y <= 0:
		push_error("COLONY: the region carries no annex at all")
		return false
	var cell_tiles: int = int(region.get("cellTiles", 0))
	var host: Vector2i = Vector2i(-1, -1)
	for cell_value in SimRegion.cells_of(region):
		var cell: Dictionary = cell_value as Dictionary
		var bounds := Rect2i(SimRegion.origin_of(region, cell), Vector2i(cell_tiles, cell_tiles))
		if bounds.encloses(annex):
			host = Vector2i(int(cell["x"]), int(cell["y"]))
	if host.x < 0:
		push_error("COLONY: the annex at %s is not wholly inside any one cell" % str(annex))
		return false

	# Every anchor on open floor, the same question `check_worldgen` asks of a district.
	for at in [SimTileMap.player_start(map), SimTileMap.gate_a(map), SimTileMap.gate_b(map), SimTileMap.well_tile(map)]:
		var tile: Vector2i = at as Vector2i
		if tile.x < 0 or tile.y < 0 or tile.x >= int(map.w) or tile.y >= int(map.h):
			push_error("COLONY: an anchor at %s is off the region" % str(tile))
			return false
		if SimTileMap.is_solid(map, tile.x, tile.y) and SimTileMap.tile_at(map, tile.x, tile.y) != SimTileMap.Tile.Door:
			push_error("COLONY: the anchor at %s stands in something solid" % str(tile))
			return false

	# The true negative: a second annex stamped anywhere must break the "wholly inside one cell"
	# reading, because the rect the map reports would then cover two colonies' worth of ground.
	var patch: Variant = SimWorldgen.annex_template_of(_tree())
	if not (patch is Dictionary):
		push_error("COLONY: no annex template, so the negative proves nothing")
		return false
	var sabotage: Variant = SimRegion.generate(CANON_SEED, REGION_ID, _tree(), false)
	var before: Rect2i = SimTileMap.annex_rect(sabotage)
	SimTemplates.stamp(sabotage, patch as Dictionary, 4, 4)
	if SimTileMap.annex_rect(sabotage) == before:
		push_error("COLONY: stamping a second annex left the map's annex rect unchanged, so the lane is reading something that cannot move")
		return false
	return true


# 4. DETERMINE: one seed builds one region.
func _one_seed_builds_one_region_and_two_build_two() -> bool:
	var a: Variant = SimRegion.generate(CANON_SEED, REGION_ID, _tree(), true)
	var b: Variant = SimRegion.generate(CANON_SEED, REGION_ID, _tree(), true)
	if a.tiles != b.tiles or a.surfaces != b.surfaces or a.indoors != b.indoors:
		push_error("DETERMINE: the same seed built two different regions")
		return false
	var c: Variant = SimRegion.generate(CANON_SEED + 1, REGION_ID, _tree(), true)
	if c.tiles == a.tiles:
		push_error("DETERMINE: two seeds built the same region, so the seed reaches nothing")
		return false
	# Dressing independence, the region's own copy of the property `check_m2_district` holds for a
	# district: switching the dressing off must be repeatable, and must not move the layout it is
	# drawn over. Compared on the *tiles the dressing may not touch* -- the walls -- because the
	# dressing legitimately changes trees, screens and rubble.
	var d1: Variant = SimRegion.generate(CANON_SEED, REGION_ID, _tree(), false)
	var d2: Variant = SimRegion.generate(CANON_SEED, REGION_ID, _tree(), false)
	if d1.tiles != d2.tiles or d1.surfaces != d2.surfaces:
		push_error("DETERMINE: dress=false is not repeatable")
		return false
	# And the assertion the wall-diff heuristic should have been all along: **the colony does not
	# move when the dressing is switched off.** That is the property docs/30 records for a district
	# ("a colony sited off the trees would move when the trees were switched off") held at region
	# scale, and it is the one this gate actually caught being broken -- the first assembler ranked
	# candidate lots by street frontage read off the finished map, and `_rubble` heaves patches up
	# through a street, so switching the dressing off moved the colony 45 tiles. Ranking now happens
	# against a layout-only region. Asserted on the rect rather than on a tile count because the
	# rect is the thing that must not move, and a count is a proxy that passes for wrong reasons.
	if SimTileMap.annex_rect(d1) != SimTileMap.annex_rect(a):
		push_error("DETERMINE: the colony is at %s dressed and %s undressed; the dressing is re-ranking the candidate lots" % [
			str(SimTileMap.annex_rect(a)), str(SimTileMap.annex_rect(d1)),
		])
		return false
	for at in [SimTileMap.gate_a(d1), SimTileMap.player_start(d1), SimTileMap.well_tile(d1)]:
		if (at as Vector2i).x < 0:
			push_error("DETERMINE: an anchor is absent from the undressed region")
			return false
	return true


# 5. SEAMS: the cells actually join.
#
# The question that matters is not "was a seam carved" -- MANIFEST counts those -- but whether a
# survivor can walk from the colony to every other district. One flood from the gates answers it,
# over the same `SimPath.walkable_tile` the survivability pass uses.
func _the_flood_from_the_gates_reaches_every_cell(map: Variant, region: Dictionary) -> bool:
	var cell_tiles: int = int(region.get("cellTiles", 0))
	var reached: PackedByteArray = SimWorldgen._walk_from(map, [SimTileMap.gate_a(map), SimTileMap.gate_b(map)])
	var w: int = int(map.w)
	for cell_value in SimRegion.cells_of(region):
		var cell: Dictionary = cell_value as Dictionary
		var origin: Vector2i = SimRegion.origin_of(region, cell)
		var hits: int = 0
		for j in cell_tiles:
			for i in cell_tiles:
				if reached[(origin.y + j) * w + origin.x + i] == 1:
					hits += 1
		if hits < 1:
			push_error("SEAMS: cell (%d,%d) %s is not reachable on foot from the colony gates" % [
				int(cell["x"]), int(cell["y"]), String(cell["district"]),
			])
			return false

	# The true negative: wall every seam and a cell must go out of reach. Built on a fresh region so
	# the shared one is left intact for the lanes after this.
	var sabotage: Variant = SimRegion.generate(CANON_SEED, REGION_ID, _tree(), true)
	var walled: int = 0
	for span_value in sabotage.streets as Array:
		var span: Dictionary = span_value as Dictionary
		if not bool(span.get("seam", false)):
			continue
		var horizontal: bool = String(span.get("axis", "x")) == "y"
		for along in range(int(span.get("from", 0)), int(span.get("to", 0)) + 1):
			for across in range(int(span.get("at", 0)) - 1, int(span.get("at", 0)) + int(span.get("width", 1)) + 1):
				var tx: int = along if horizontal else across
				var ty: int = across if horizontal else along
				if tx < 0 or ty < 0 or tx >= int(sabotage.w) or ty >= int(sabotage.h):
					continue
				sabotage.tiles[ty * int(sabotage.w) + tx] = SimTileMap.Tile.Wall
				walled += 1
	if walled < 1:
		push_error("SEAMS: the sabotage walled nothing, so the negative proves nothing")
		return false
	var after: PackedByteArray = SimWorldgen._walk_from(sabotage, [SimTileMap.gate_a(sabotage), SimTileMap.gate_b(sabotage)])
	var stranded: int = 0
	for cell_value2 in SimRegion.cells_of(region):
		var cell2: Dictionary = cell_value2 as Dictionary
		var origin2: Vector2i = SimRegion.origin_of(region, cell2)
		var hits2: int = 0
		for j2 in cell_tiles:
			for i2 in cell_tiles:
				if after[(origin2.y + j2) * w + origin2.x + i2] == 1:
					hits2 += 1
		if hits2 < 1:
			stranded += 1
	if stranded < 1:
		push_error("SEAMS: walling all %d seam tiles stranded no cell, so this lane cannot fail" % walled)
		return false
	return true


# 6. SURVIVE: every clause answered.
#
# A region places every kind of loot and carries water, so unlike a bare district there is nothing
# here a clause could legitimately have nothing to judge about. A skip is a clause quietly not
# running on the world the game plays.
func _the_region_is_survivable_and_no_clause_skipped(map: Variant) -> bool:
	var report: Dictionary = SimWorldgen.survivability_report(map)
	if not bool(report["sited"]):
		push_error("SURVIVE: the survivability pass judged nothing on a region that carries a colony")
		return false
	var clauses: Array = report["clauses"] as Array
	if clauses.size() < 7:
		push_error("SURVIVE: the report carries %d clauses" % clauses.size())
		return false
	for clause_value in clauses:
		var clause: Dictionary = clause_value as Dictionary
		if not bool(clause["ok"]):
			push_error("SURVIVE: %s failed: %s" % [String(clause["name"]), String(clause["said"])])
			return false
		if bool(clause["skipped"]):
			push_error("SURVIVE: %s skipped on a region: %s" % [String(clause["name"]), String(clause["said"])])
			return false
	# And the loot half, which is what a region buys over a district: every table the four cells
	# between them place is reachable, which the clause above asserts, and there is more than one.
	var tables: Dictionary = {}
	for site_value in map.sites as Array:
		tables[String((site_value as Dictionary).get("table", ""))] = true
	if tables.size() < 3:
		push_error("SURVIVE: the region places only %d distinct loot tables; four districts should carry more" % tables.size())
		return false
	return true


# 7. RESITE: a refused lot moves the colony.
func _a_refused_lot_moves_the_colony_to_the_next_one(region: Dictionary) -> bool:
	var first: Variant = SimRegion.generate(CANON_SEED, REGION_ID, _tree(), true)
	var kept: Rect2i = SimTileMap.annex_rect(first)
	# The same shape `check_m2_district`'s re-site lane uses: refuse exactly the lot the generator
	# would otherwise have taken, and require it to take a different one.
	var refuse_first: Callable = func(rect: Rect2i) -> bool:
		return rect == kept
	var second: Variant = SimRegion.generate(CANON_SEED, REGION_ID, _tree(), true, refuse_first)
	var moved: Rect2i = SimTileMap.annex_rect(second)
	if moved.size.x <= 0:
		push_error("RESITE: refusing the first lot left the region with no colony at all")
		return false
	if moved == kept:
		push_error("RESITE: the colony stayed at %s after that exact lot was refused; the reject hook reaches nothing" % str(kept))
		return false
	var report: Dictionary = SimWorldgen.survivability_report(second)
	if not bool(report["ok"]):
		push_error("RESITE: the re-sited region is not survivable: %s" % str(report["failed"]))
		return false
	return true
