extends SceneTree
# The ground and road dressing: the street manifest the generator now carves alongside its
# streets (`map.streets`), the draw-time paint resolved from it (presentation/road_paint.gd),
# the palette (the warm dark-fantasy regrade the docs/30 art decision asked for, with the ground
# on the outpost pack's own measured table since 2026-09-27), the ground atlas, and the rubble
# pass -- the tenth worldgen pass, closing the "rubble is never placed" debt entry. Seven
# lanes, every assertion with a true positive and a true negative, because a gate that cannot
# fail is worse than no gate:
#
#   1. the manifest tells the truth -- exactly, on the pure layout; by a measured majority, on
#      the finished map the annex stamp and the terrain pass have legitimately worn through;
#   2. the manifest and the rubble pass moved no layout -- dress=false is deterministic,
#      manifest included, and the dressing appends nothing to it;
#   3. paint lands on streets and nowhere else, junctions read worn, narrow streets get kerbs
#      only, and a map with no manifest draws nothing;
#   4. the ground variation is deterministic and alive -- a hash, deliberately not a stream;
#   5. the palette holds the warm dark-fantasy mood by property off the ground, pins the ground
#      to the pack's measured table exactly, and provably refuses the warm-dark ground it replaced;
#   6. the three dead sockets are wired: the draw loop reads the mask, the one mechanism that
#      reads surfaces reads a placed rubble tile, and the rubble tint is resolved, not defined;
#   7. rubble is placed, dressing-only, and only ever on outdoor open Floor (the `_footing`
#      trap: rubble under a Low wreck would silently delete walkability);
#   8. the centre line is centred -- painted only where the carriageway has a middle row, with
#      the same number of lanes either side, and the old off-centre placement refused;
#   9. each lane beside the line is wide enough for a two-tile vehicle, which is what the roads
#      slice widened the suburb for;
#  10. the shipped suburb at the size the player sees (256) actually carries that line -- or the
#      two lanes above are claims about no lines.
#
# Boots are shared through one stash (check_worldgen's precedent) and the budget lane at the
# bottom is what keeps a future lane from quietly doubling them.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimSurface = preload("res://sim/map/surface.gd")
const SimWorldgen = preload("res://sim/map/worldgen.gd")
const SimBoot = preload("res://sim/boot.gd")
const RoadPaint = preload("res://presentation/road_paint.gd")
const Palette = preload("res://presentation/palette.gd")
const Appearance = preload("res://presentation/appearance.gd")
const CameraUtil = preload("res://presentation/camera.gd")
const ContentLoader = preload("res://platform/content_loader.gd")

const CANON_SEED: int = 20260805
const OTHER_SEED: int = 404
const GATE_SIZE: int = 64
const MAIN_GD: String = "res://presentation/main.gd"

# The in-gate fixture district: blocks of exactly 8 (MIN_BLOCK -- they cannot go smaller) and
# streetWidth 7, generated at FIXTURE_SIZE rather than GATE_SIZE. The arithmetic is the reason:
# `_fit_scale` wants BLOCKS_PER_AXIS_MIN (4) blocks on an axis, and at 64 a width-7 street
# leaves usable 48, fits 3, so the width scales back to 6 -- an even carriageway that the paint
# now correctly refuses to mark. At 80, usable 64, fits 4, scale 1.0, and the fixture keeps its
# 7. The shipped suburb still scales to width 2 at 64 and correctly gets kerbs only, so the
# wide positives need this fixture; the shipped 256 district is generated once, in lane 10.
const FIXTURE_ID: String = "district.fixture.road_wide"
const FIXTURE_SIZE: int = 80
const FIXTURE_WIDTH: int = 7
# The size the player plays at (main.gd boots SimTileMap.DISTRICT_TILES); lane 10 generates it.
const PLAYED_SIZE: int = 256
# Tiles of carriageway each side of the line -- one two-tile vehicle per direction.
const LANE_MIN: int = 2

# How much of a manifest span must still be paved outdoor floor on the *finished* map. The
# manifest is exact at carve time (lane 1 proves 1.0 on the pure layout); the annex stamp and
# the terrain pass then legitimately overwrite parts of a span -- measured on the canonical
# seed: worst span 0.44 at 64, 0.88 at 256 -- and worn-through winning is the paint's own rule.
# A fabricated span over a lawn sits near 0.0, so the floor separates truth from fabrication
# with margin on both sides.
const SPAN_PAVED_FLOOR: float = 0.33

# The gate's own wall clock, docs/00 pillar 6. Measured ~0.5 s on this container; the headroom
# is for a loaded CI box, not for new boots.
const BUDGET_SECONDS: float = 60.0

var _tree_cache: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var started: int = Time.get_ticks_msec()
	var ok: bool = true
	var stash: Dictionary = {}

	ok = _boot(stash) and ok
	if ok:
		ok = _the_manifest_tells_the_truth(stash) and ok
		ok = _the_manifest_and_the_rubble_moved_no_layout(stash) and ok
		ok = _paint_lands_on_streets_and_nowhere_else(stash) and ok
		ok = _the_centre_line_is_centred(stash) and ok
		ok = _each_lane_is_wide_enough(stash) and ok
		ok = _the_shipped_district_carries_a_centred_line(stash) and ok
		ok = _variation_is_deterministic_and_alive() and ok
		ok = _the_palette_holds_the_mood_and_can_say_no() and ok
		ok = _the_ground_is_a_texture_whose_mean_is_the_palette(stash) and ok
		ok = _the_floor_blits_its_cell_and_draws_no_grid() and ok
		ok = _the_ground_has_edges(stash) and ok
		ok = _the_three_sockets_are_wired(stash) and ok
		ok = _rubble_is_placed_and_lawful(stash) and ok
		# Slice 9: the street-surface name a district can declare.
		ok = _street_surface_of_defaults_to_paved_and_dirt_is_named(stash) and ok

	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	ok = _the_gate_stayed_inside_its_own_budget(seconds) and ok

	if ok:
		print("ROAD_LOOK_OK manifest true (exact on layout, worst dressed span %.2f over a %.2f floor), layout untouched, paint on streets only, centre line centred on %d fixture spans with %d lanes a side and the old placement refused, the shipped %d district carries %d centred dashes at width %d, variation hashed not drawn, palette propertied and the ground pinned to the pack's measured table with the warm-dark table refused, the ground atlas %d pack cells each averaging its row and every row's integer mean the pinned hex, floors blit their cell at zoom %.0f and up with no grid, %d edge cells authored with %d/%d shipped floor tiles edged/plain, mask/speed/tint sockets wired, %d rubble tiles lawful, street_surface_of paved-by-default with dirt named and %d suburb spans carrying it; %.1f s of a %.0f s budget" % [
			float(stash.get("worst_span", 0.0)), SPAN_PAVED_FLOOR, int(stash.get("centred_spans", 0)), LANE_MIN, PLAYED_SIZE, int(stash.get("played_dashes", 0)), int(stash.get("played_width", 0)), int(stash.get("atlas_cells", 0)), Palette.GROUND_TEXTURE_MIN_ZOOM, int(stash.get("edge_cells", 0)), int(stash.get("edge_with", 0)), int(stash.get("edge_without", 0)), int(stash.get("rubble", 0)), int(stash.get("surfaced_spans", 0)), seconds, BUDGET_SECONDS,
		])
		quit(0)
	else:
		push_error("ROAD_LOOK_FAIL")
		quit(1)


func _tree() -> Dictionary:
	if _tree_cache.is_empty():
		_tree_cache = ContentLoader.load_tree()
	return _tree_cache


func _fixture_district() -> Dictionary:
	return {
		"id": FIXTURE_ID,
		"name": "fixture",
		"type": "fixture",
		"streets": {"blockMin": 8, "blockMax": 8, "streetWidth": FIXTURE_WIDTH},
		"density": 0.0,
		"pool": [{"tag": "residential", "weight": 1}],
	}


func _tree_with_fixture() -> Dictionary:
	var tree: Dictionary = _tree().duplicate()
	tree["districts/zz_road_fixture.json"] = _fixture_district()
	return tree


# One boot and three generations, shared by every lane.
func _boot(stash: Dictionary) -> bool:
	var boot: Dictionary = SimBoot.playable(CANON_SEED, GATE_SIZE)
	stash["world"] = boot["world"]
	stash["map"] = boot["map"]
	var district: Dictionary = SimWorldgen.district_of(_tree(), SimWorldgen.DEFAULT_DISTRICT)
	if district.is_empty():
		push_error("no %s in content; the gate has no district to judge" % SimWorldgen.DEFAULT_DISTRICT)
		return false
	stash["layout"] = SimWorldgen.layout(CANON_SEED, GATE_SIZE, district)["map"]
	stash["fixture"] = SimWorldgen.generate(CANON_SEED, FIXTURE_SIZE, _tree_with_fixture(), FIXTURE_ID)
	if (stash["map"].streets as Array).is_empty() or (stash["fixture"].streets as Array).is_empty():
		push_error("a generated district carries no street manifest at all; every lane below would judge nothing")
		return false
	return true


# The fraction of a span's tiles that are still paved outdoor floor -- the one predicate both
# the exact lane and the majority lane apply, so the fabricated spans below refuse through the
# same code path the true positives pass through.
func _span_paved_fraction(map: Variant, span: Dictionary) -> float:
	var w: int = int(map.w)
	var tiles: int = 0
	var paved: int = 0
	for along in range(int(span["from"]), int(span["to"]) + 1):
		for off in int(span["width"]):
			var tx: int = int(span["at"]) + off if String(span["axis"]) == "x" else along
			var ty: int = along if String(span["axis"]) == "x" else int(span["at"]) + off
			tiles += 1
			if tx < 0 or ty < 0 or tx >= w or ty >= int(map.h):
				continue
			var idx: int = ty * w + tx
			if int(map.tiles[idx]) != SimTileMap.Tile.Floor:
				continue
			if int(map.indoors[idx]) == 1:
				continue
			if int(map.surfaces[idx]) == SimTileMap.SURFACE_PAVED:
				paved += 1
	if tiles == 0:
		return 0.0
	return float(paved) / float(tiles)


func _span_well_formed(map: Variant, span: Dictionary) -> bool:
	if not ["x", "y"].has(String(span.get("axis", ""))):
		return false
	if int(span.get("width", 0)) < 2 or int(span.get("from", 1)) > int(span.get("to", 0)):
		return false
	var limit: int = int(map.w) if String(span["axis"]) == "x" else int(map.h)
	return int(span["at"]) >= 1 and int(span["at"]) + int(span["width"]) <= limit - 1


# --- 1. manifest truth ---------------------------------------------------------------------

func _the_manifest_tells_the_truth(stash: Dictionary) -> bool:
	var map: Variant = stash["map"]
	var layout: Variant = stash["layout"]
	var spans: Array = map.streets as Array

	# Exact, on the ground the pass itself carved: before the annex stamp and the dressing,
	# every tile a span names is Floor, paved, outdoors -- the manifest is a transcript of the
	# carving, not an estimate of it.
	for span_value in layout.streets as Array:
		var span: Dictionary = span_value as Dictionary
		if not _span_well_formed(layout, span):
			push_error("the layout manifest carries a malformed span: %s" % str(span))
			return false
		var exact: float = _span_paved_fraction(layout, span)
		if exact < 1.0:
			push_error("span %s is %.2f paved on the pure layout, where the manifest must be exact" % [str(span), exact])
			return false

	# By majority, on the finished map: the annex and the terrain legitimately wear a span
	# through, and the floor is what separates a worn street from a fabricated one.
	var worst: float = 1.0
	for span_value2 in spans:
		var span2: Dictionary = span_value2 as Dictionary
		if not _span_well_formed(map, span2):
			push_error("the booted manifest carries a malformed span: %s" % str(span2))
			return false
		var frac: float = _span_paved_fraction(map, span2)
		worst = minf(worst, frac)
		if frac < SPAN_PAVED_FLOOR:
			push_error("span %s is only %.2f paved outdoor floor on the finished map (floor %.2f)" % [str(span2), frac, SPAN_PAVED_FLOOR])
			return false
	stash["worst_span"] = worst

	# Determinism: one seed, one manifest; two seeds, two.
	var again: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, _tree())
	if str(again.streets) != str(map.streets):
		push_error("two generations of seed %d carved different street manifests" % CANON_SEED)
		return false
	var other: Variant = SimWorldgen.generate(OTHER_SEED, GATE_SIZE, _tree())
	if str(other.streets) == str(map.streets):
		push_error("seeds %d and %d carved identical manifests -- the seed is not reaching the streets pass" % [CANON_SEED, OTHER_SEED])
		return false

	# The true negatives, through the same predicate. A span across the border wall fails the
	# exact check; a span over a lawn fails the majority floor.
	var walled: Dictionary = {"axis": "x", "at": 1, "width": 2, "from": 0, "to": int(layout.h) - 1}
	if _span_paved_fraction(layout, walled) >= 1.0:
		push_error("a fabricated span across the border wall read as exactly paved; the truth predicate is not reading the tiles")
		return false
	var lawn: Dictionary = _span_over_grass(map)
	if lawn.is_empty():
		push_error("no all-grass window found to fabricate the negative span from -- this lane had nothing to refuse")
		return false
	var lied: float = _span_paved_fraction(map, lawn)
	if lied >= SPAN_PAVED_FLOOR:
		push_error("a fabricated span over grass at %s read %.2f paved, over the %.2f floor -- the majority check cannot say no" % [str(lawn), lied, SPAN_PAVED_FLOOR])
		return false

	print("MANIFEST OK %d spans exact on the layout, worst %.2f on the finished map (floor %.2f), deterministic per seed; a border span and a %.2f-paved lawn span both refused" % [
		spans.size(), worst, SPAN_PAVED_FLOOR, lied,
	])
	return true


# A 2x6 window of tiles none of which is paved outdoor floor, as a fabricated street record.
func _span_over_grass(map: Variant) -> Dictionary:
	var w: int = int(map.w)
	for ty in range(2, int(map.h) - 8):
		for tx in range(2, w - 4):
			var clean: bool = true
			for dy in 6:
				for dx in 2:
					var idx: int = (ty + dy) * w + tx + dx
					if int(map.tiles[idx]) == SimTileMap.Tile.Floor \
							and int(map.indoors[idx]) == 0 \
							and int(map.surfaces[idx]) == SimTileMap.SURFACE_PAVED:
						clean = false
						break
				if not clean:
					break
			if clean:
				return {"axis": "x", "at": tx, "width": 2, "from": ty, "to": ty + 5}
	return {}


# --- 2. the layout is untouched --------------------------------------------------------------

func _the_manifest_and_the_rubble_moved_no_layout(stash: Dictionary) -> bool:
	var first: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, _tree(), SimWorldgen.DEFAULT_DISTRICT, false)
	var second: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, _tree(), SimWorldgen.DEFAULT_DISTRICT, false)
	for field in ["tiles", "surfaces", "indoors"]:
		var a: PackedByteArray = first.get(String(field)) as PackedByteArray
		var b: PackedByteArray = second.get(String(field)) as PackedByteArray
		var at: int = _first_difference(a, b)
		if at >= 0:
			push_error("two undressed generations of seed %d differ in %s at %d -- the manifest is drawing or writing" % [CANON_SEED, String(field), at])
			return false
	if str(first.streets) != str(second.streets) or (first.streets as Array).is_empty():
		push_error("two undressed generations of seed %d carved different (or empty) manifests" % CANON_SEED)
		return false

	# The dressing -- rubble pass included -- appends nothing to the manifest: what the paint
	# reads is layout metadata, full stop.
	if str(stash["map"].streets) != str(first.streets):
		push_error("the dressed manifest differs from the undressed one; a dressing pass is writing street records")
		return false

	# The comparator's own true negative: a bogus record appended to a copy must unequal it,
	# or every equality above is a comparison that stopped comparing.
	var forged: Array = (first.streets as Array).duplicate(true)
	forged.append({"axis": "y", "at": 3, "width": 2, "from": 1, "to": 4})
	if str(forged) == str(first.streets):
		push_error("an appended bogus record left the manifests comparing equal")
		return false

	print("LAYOUT OK dress=false byte-identical twice (tiles, surfaces, indoors) with an equal non-empty manifest the dressing does not touch; a forged record un-equals it. Dressed-vs-undressed tile movement stays check_m2_district's dressing-independence lane.")
	return true


func _first_difference(a: PackedByteArray, b: PackedByteArray) -> int:
	if a.size() != b.size():
		return 0
	for i in a.size():
		if a[i] != b[i]:
			return i
	return -1


# --- 3. paint on streets, none off -----------------------------------------------------------

func _paint_lands_on_streets_and_nowhere_else(stash: Dictionary) -> bool:
	var wide: Variant = stash["fixture"]
	var mask: PackedByteArray = RoadPaint.mask_for(wide)
	var counts: Dictionary = _mask_counts(wide, mask)
	if int(counts["dash"]) < 1 or int(counts["sidewalk"]) < 1:
		push_error("the width-%d fixture resolved %d dashes and %d sidewalk cells; wide streets are not being marked" % [FIXTURE_WIDTH, int(counts["dash"]), int(counts["sidewalk"])])
		return false
	if int(counts["kerbed"]) < 1:
		push_error("not one masked tile on the fixture meets non-paved ground; kerb_edges is finding no boundary")
		return false
	if int(counts["off_paved"]) > 0 or int(counts["indoors"]) > 0:
		push_error("%d masked tiles are not paved and %d are indoors -- the paint has left the street" % [int(counts["off_paved"]), int(counts["indoors"])])
		return false

	# Junctions read worn: a tile inside both an x-span and a y-span that is still paved
	# carries plain asphalt, never a marking. At least one must be judged or the suppression
	# is a claim about no tiles.
	var junctions: int = 0
	for span_value in wide.streets as Array:
		var span: Dictionary = span_value as Dictionary
		if String(span["axis"]) != "x":
			continue
		for other_value in wide.streets as Array:
			var other: Dictionary = other_value as Dictionary
			if String(other["axis"]) != "y":
				continue
			for dx in int(span["width"]):
				for dy in int(other["width"]):
					var tx: int = int(span["at"]) + dx
					var ty: int = int(other["at"]) + dy
					var idx: int = ty * int(wide.w) + tx
					if int(wide.surfaces[idx]) != SimTileMap.SURFACE_PAVED or int(wide.indoors[idx]) == 1:
						continue
					junctions += 1
					if int(mask[idx]) != RoadPaint.MASK_ASPHALT:
						push_error("junction tile (%d,%d) carries mask %d; crossings must read worn asphalt, not markings" % [tx, ty, int(mask[idx])])
						return false
	if junctions == 0:
		push_error("the fixture yielded no paved junction tile to judge -- the suppression assertion had nothing to say no to")
		return false

	# Narrow streets get kerbs only. The shipped suburb at 64 scales to width 2, so its whole
	# mask must carry no sidewalk and no dash while still carrying asphalt; and a hand-built
	# width-3 street -- the shipped town-centre width -- must answer the same.
	var suburb_mask: PackedByteArray = RoadPaint.mask_for(stash["map"])
	var suburb_counts: Dictionary = _mask_counts(stash["map"], suburb_mask)
	if int(suburb_counts["sidewalk"]) != 0 or int(suburb_counts["dash"]) != 0:
		push_error("the suburb's width-2 streets at %d resolved %d sidewalk and %d dash cells; narrow streets get kerbs only" % [GATE_SIZE, int(suburb_counts["sidewalk"]), int(suburb_counts["dash"])])
		return false
	if int(suburb_counts["asphalt"]) < 1:
		push_error("the suburb resolved no asphalt at all, so 'no markings' is true of an empty mask")
		return false
	var narrow: Variant = SimTileMap.blank_map(16, 16)
	var surfaces := PackedByteArray()
	surfaces.resize(16 * 16)
	# Whole-array writes, never element writes through the property -- packed arrays are values.
	for i in surfaces.size():
		surfaces[i] = SimTileMap.SURFACE_GRASS
	for ty2 in range(1, 15):
		for off in 3:
			surfaces[ty2 * 16 + 4 + off] = SimTileMap.SURFACE_PAVED
	narrow.surfaces = surfaces
	narrow.streets = [{"axis": "x", "at": 4, "width": 3, "from": 1, "to": 14}]
	var narrow_mask: PackedByteArray = RoadPaint.mask_for(narrow)
	var narrow_counts: Dictionary = _mask_counts(narrow, narrow_mask)
	if int(narrow_counts["sidewalk"]) != 0 or int(narrow_counts["dash"]) != 0:
		push_error("a width-3 street resolved %d sidewalk and %d dash cells; the shipped town-centre width gets kerbs only" % [int(narrow_counts["sidewalk"]), int(narrow_counts["dash"])])
		return false
	if int(narrow_counts["asphalt"]) != 3 * 14:
		push_error("a width-3 street of 42 tiles resolved %d asphalt cells" % int(narrow_counts["asphalt"]))
		return false
	if (RoadPaint.kerb_edges(narrow, narrow_mask, 4, 5) & RoadPaint.EDGE_W) == 0:
		push_error("the west row of a street beside grass carries no west kerb edge")
		return false
	if RoadPaint.kerb_edges(narrow, narrow_mask, 5, 5) != 0:
		push_error("the centre of a width-3 street carries kerb edges against its own pavement")
		return false

	# Off-street stays quiet: every indoor tile of the booted suburb, and a grass tile, mask 0.
	var map: Variant = stash["map"]
	for i2 in (map.indoors as PackedByteArray).size():
		if int(map.indoors[i2]) == 1 and int(suburb_mask[i2]) != RoadPaint.MASK_NONE:
			push_error("indoor tile %d carries mask %d" % [i2, int(suburb_mask[i2])])
			return false
	# And a manifest-free map draws nothing at all -- graceful absence, blank_map included.
	var blank_mask: PackedByteArray = RoadPaint.mask_for(SimTileMap.blank_map(8, 8))
	for i3 in blank_mask.size():
		if int(blank_mask[i3]) != RoadPaint.MASK_NONE:
			push_error("a blank map with no manifest resolved paint at %d" % i3)
			return false
	if RoadPaint.mask_for(null).size() != 0:
		push_error("a null map must resolve an empty mask")
		return false

	print("PAINT OK fixture: %d asphalt, %d sidewalk, %d dash, %d kerbed, all paved outdoors; %d junction tiles all worn; suburb width-2 and a width-3 street kerbs-only; indoors and blank maps silent" % [
		int(counts["asphalt"]), int(counts["sidewalk"]), int(counts["dash"]), int(counts["kerbed"]), junctions,
	])
	return true


func _mask_counts(map: Variant, mask: PackedByteArray) -> Dictionary:
	var out: Dictionary = {"asphalt": 0, "sidewalk": 0, "dash": 0, "kerbed": 0, "off_paved": 0, "indoors": 0}
	var w: int = int(map.w)
	for i in mask.size():
		var value: int = int(mask[i])
		if value == RoadPaint.MASK_NONE:
			continue
		match value:
			RoadPaint.MASK_ASPHALT:
				out["asphalt"] = int(out["asphalt"]) + 1
			RoadPaint.MASK_SIDEWALK:
				out["sidewalk"] = int(out["sidewalk"]) + 1
			RoadPaint.MASK_DASH:
				out["dash"] = int(out["dash"]) + 1
		if int(map.surfaces[i]) != SimTileMap.SURFACE_PAVED:
			out["off_paved"] = int(out["off_paved"]) + 1
		if int(map.indoors[i]) == 1:
			out["indoors"] = int(out["indoors"]) + 1
		if RoadPaint.kerb_edges(map, mask, i % w, i / w) != 0:
			out["kerbed"] = int(out["kerbed"]) + 1
	return out


# --- 8, 9, 10. the centre line ---------------------------------------------------------------

# How a span's rows split around its painted line at one position along it, read off the MASK
# and never off the formula that placed the line -- an assertion that recomputed `dash_row` would
# agree with itself by construction. `dash` is the offset of the MASK_DASH row (-1 if none at this
# position), `before`/`after` count MASK_ASPHALT rows either side of it (sidewalks are their own
# mask value and fall out), and `complete` says every row of the span carried some paint here --
# a worn-through row (lawn to the kerb, the annex wall) would undercount a side and blame the
# line for it, so only complete positions are judged.
func _lane_split(map: Variant, mask: PackedByteArray, span: Dictionary, along: int) -> Dictionary:
	var w: int = int(map.w)
	var at: int = int(span["at"])
	var vertical: bool = String(span["axis"]) == "x"
	var dash: int = -1
	var asphalt: Array[int] = []
	var painted: int = 0
	for off in int(span["width"]):
		var tx: int = at + off if vertical else along
		var ty: int = along if vertical else at + off
		if tx < 0 or ty < 0 or tx >= w or ty >= int(map.h):
			continue
		var value: int = int(mask[ty * w + tx])
		if value != RoadPaint.MASK_NONE:
			painted += 1
		if value == RoadPaint.MASK_DASH:
			dash = off
		elif value == RoadPaint.MASK_ASPHALT:
			asphalt.append(off)
	var before: int = 0
	var after: int = 0
	for off2 in asphalt:
		if dash >= 0 and off2 < dash:
			before += 1
		elif dash >= 0 and off2 > dash:
			after += 1
	return {"dash": dash, "before": before, "after": after, "complete": painted == int(span["width"])}


# The first complete, dash-bearing position along each span that has one, as {span, split}.
# Spans the rule refuses to mark (narrow, or an even carriageway) contribute nothing, which is
# what lets the caller say "had nothing to judge" instead of passing on an empty set.
func _judged_splits(map: Variant, mask: PackedByteArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for span_value in map.streets as Array:
		var span: Dictionary = span_value as Dictionary
		for along in range(int(span["from"]), int(span["to"]) + 1):
			var split: Dictionary = _lane_split(map, mask, span, along)
			if int(split["dash"]) >= 0 and bool(split["complete"]):
				out.append({"span": span, "split": split})
				break
	return out


# A 16x16 blank map with one paved width-6 span, and a mask for it painted the way the OLD rule
# painted it (sidewalks outermost, the dash on `at + width / 2` = row 3 of a 1..4 carriageway):
# the exact off-centre picture the shipped suburb carried. Both negatives below read this.
func _old_width_six() -> Dictionary:
	var map: Variant = SimTileMap.blank_map(16, 16)
	var surfaces := PackedByteArray()
	surfaces.resize(16 * 16)
	for i in surfaces.size():
		surfaces[i] = SimTileMap.SURFACE_GRASS
	for ty in range(1, 15):
		for off in 6:
			surfaces[ty * 16 + 4 + off] = SimTileMap.SURFACE_PAVED
	map.surfaces = surfaces
	map.streets = [{"axis": "x", "at": 4, "width": 6, "from": 1, "to": 14}]
	var old := PackedByteArray()
	old.resize(16 * 16)
	for ty2 in range(1, 15):
		for off2 in 6:
			var value: int = RoadPaint.MASK_ASPHALT
			if off2 == 0 or off2 == 5:
				value = RoadPaint.MASK_SIDEWALK
			elif off2 == 3:
				value = RoadPaint.MASK_DASH
			old[ty2 * 16 + 4 + off2] = value
	return {"map": map, "old_mask": old}


func _the_centre_line_is_centred(stash: Dictionary) -> bool:
	# The rule itself, both ways: a 7 paints at at+3 (rows 1..5, the middle), a 5 at at+2; a 6
	# and a 4 are even carriageways and refuse; a 3 is under DASH_MIN_WIDTH and refuses.
	var expect: Dictionary = {7: 13, 5: 12, 9: 14, 6: -1, 4: -1, 3: -1, 2: -1}
	for width in expect.keys():
		if RoadPaint.dash_row(10, int(width)) != int(expect[width]):
			push_error("dash_row(10, %d) answered %d, want %d" % [int(width), RoadPaint.dash_row(10, int(width)), int(expect[width])])
			return false

	# On the fixture, read off the paint: every marked span splits evenly around its line.
	var wide: Variant = stash["fixture"]
	var mask: PackedByteArray = RoadPaint.mask_for(wide)
	var judged: Array[Dictionary] = _judged_splits(wide, mask)
	if judged.is_empty():
		push_error("no span on the width-%d fixture carries a complete dash-bearing row; the symmetry assertion had nothing to judge" % FIXTURE_WIDTH)
		return false
	for j in judged:
		var split: Dictionary = j["split"]
		var span: Dictionary = j["span"]
		if int(split["before"]) != int(split["after"]):
			push_error("span %s splits %d lanes before its line and %d after -- the line is off-centre" % [str(span), int(split["before"]), int(split["after"])])
			return false
		if int(split["dash"]) != RoadPaint.dash_row(int(span["at"]), int(span["width"])) - int(span["at"]):
			push_error("span %s carries its dash on row %d, not the row dash_row names" % [str(span), int(split["dash"])])
			return false
	stash["centred_spans"] = judged.size()

	# The negatives, through the same predicate. The old width-6 picture -- sidewalks outermost,
	# dash on row 3 of 1..4 -- must read asymmetric; and the new rule must paint that span with
	# no dash at all rather than a shifted one.
	var six: Dictionary = _old_width_six()
	var old_split: Dictionary = _lane_split(six["map"], six["old_mask"], (six["map"].streets as Array)[0] as Dictionary, 5)
	if int(old_split["dash"]) < 0 or not bool(old_split["complete"]):
		push_error("the fabricated old-rule mask carries no complete dash row at along 5; the negative is malformed")
		return false
	if int(old_split["before"]) == int(old_split["after"]):
		push_error("the old off-centre placement (%d before, %d after) read as symmetric; the split predicate reads nothing" % [int(old_split["before"]), int(old_split["after"])])
		return false
	var new_mask: PackedByteArray = RoadPaint.mask_for(six["map"])
	var new_counts: Dictionary = _mask_counts(six["map"], new_mask)
	if int(new_counts["dash"]) != 0:
		push_error("a width-6 span resolved %d dashes under the new rule; an even carriageway has no row to paint" % int(new_counts["dash"]))
		return false
	if int(new_counts["sidewalk"]) != 2 * 14 or int(new_counts["asphalt"]) != 4 * 14:
		push_error("a width-6 span resolved %d sidewalk and %d asphalt cells; refusing the line must not refuse the street" % [int(new_counts["sidewalk"]), int(new_counts["asphalt"])])
		return false
	print("CENTRE OK dash_row 7->at+3, 5->at+2, 9->at+4 and 6/4/3/2 refused; %d fixture spans split evenly (%d|%d); the old width-6 placement reads %d|%d and is refused, and the new rule paints that span with sidewalks and asphalt but no line" % [
		judged.size(), int((judged[0]["split"] as Dictionary)["before"]), int((judged[0]["split"] as Dictionary)["after"]), int(old_split["before"]), int(old_split["after"]),
	])
	return true


func _each_lane_is_wide_enough(stash: Dictionary) -> bool:
	var wide: Variant = stash["fixture"]
	var mask: PackedByteArray = RoadPaint.mask_for(wide)
	var judged: Array[Dictionary] = _judged_splits(wide, mask)
	if judged.is_empty():
		push_error("no marked span on the fixture to measure a lane on")
		return false
	var narrowest: int = 999
	for j in judged:
		var split: Dictionary = j["split"]
		narrowest = mini(narrowest, mini(int(split["before"]), int(split["after"])))
	if narrowest < LANE_MIN:
		push_error("a lane beside the centre line is %d tiles wide; a two-tile vehicle needs %d each side, which is what the width went to %d for" % [narrowest, LANE_MIN, FIXTURE_WIDTH])
		return false
	# The old geometry, through the same measure: one of its lanes is a single tile.
	var six: Dictionary = _old_width_six()
	var old_split: Dictionary = _lane_split(six["map"], six["old_mask"], (six["map"].streets as Array)[0] as Dictionary, 5)
	if mini(int(old_split["before"]), int(old_split["after"])) >= LANE_MIN:
		push_error("the old width-6 geometry passes the lane-width floor; the floor reads nothing")
		return false
	print("LANES OK every fixture lane beside the line is >= %d tiles (narrowest %d); the old width-6 geometry's %d-tile lane refused" % [LANE_MIN, narrowest, mini(int(old_split["before"]), int(old_split["after"]))])
	return true


# The shipped district, at the size the player actually sees. Every other lane judges the
# suburb at 64, where it scales to width 2 and carries no line at all -- so without this
# generation, "the line is centred" is true of no shipped line. ~0.6 s, inside the budget.
func _the_shipped_district_carries_a_centred_line(stash: Dictionary) -> bool:
	var played: Variant = SimWorldgen.generate(CANON_SEED, PLAYED_SIZE, _tree())
	stash["played_map"] = played
	var widest: int = 0
	for span_value in played.streets as Array:
		widest = maxi(widest, int((span_value as Dictionary)["width"]))
	if widest != FIXTURE_WIDTH:
		push_error("the shipped suburb at %d carves streets %d wide; the content declares %d and the fixture is judged at %d" % [PLAYED_SIZE, widest, FIXTURE_WIDTH, FIXTURE_WIDTH])
		return false
	var mask: PackedByteArray = RoadPaint.mask_for(played)
	var counts: Dictionary = _mask_counts(played, mask)
	if int(counts["dash"]) < 1:
		push_error("the shipped suburb at %d resolved no dashes; the centred line is a claim about no lines" % PLAYED_SIZE)
		return false
	var judged: Array[Dictionary] = _judged_splits(played, mask)
	if judged.is_empty():
		push_error("the shipped suburb at %d has dashes but no complete dash-bearing row to judge them on" % PLAYED_SIZE)
		return false
	for j in judged:
		var split: Dictionary = j["split"]
		if int(split["before"]) != int(split["after"]) or mini(int(split["before"]), int(split["after"])) < LANE_MIN:
			push_error("shipped span %s splits %d|%d around its line" % [str(j["span"]), int(split["before"]), int(split["after"])])
			return false
	stash["played_dashes"] = int(counts["dash"])
	stash["played_width"] = widest
	# The true negative stays where it already is: the same suburb at GATE_SIZE scales to width
	# 2 and lane 3 requires it to resolve zero dashes -- one district, two sizes, two answers.
	var small_counts: Dictionary = _mask_counts(stash["map"], RoadPaint.mask_for(stash["map"]))
	if int(small_counts["dash"]) != 0:
		push_error("the suburb at %d resolved %d dashes; the size split this lane rests on has collapsed" % [GATE_SIZE, int(small_counts["dash"])])
		return false
	print("PLAYED OK the shipped suburb at %d carves width %d, resolves %d dashes on %d centred spans with >= %d lanes a side; at %d it stays width 2 with no line" % [
		PLAYED_SIZE, widest, int(counts["dash"]), judged.size(), LANE_MIN, GATE_SIZE,
	])
	return true


# --- 4. variation --------------------------------------------------------------------------

func _variation_is_deterministic_and_alive() -> bool:
	var seen: Dictionary = {}
	var worst: float = 0.0
	for ty in 32:
		for tx in 32:
			var v: float = RoadPaint.vary(tx, ty)
			if RoadPaint.vary(tx, ty) != v:
				push_error("vary(%d,%d) answered two values in one process; the hash is not a hash" % [tx, ty])
				return false
			if absf(v) > RoadPaint.VARIATION_MAX + 0.000001:
				push_error("vary(%d,%d) = %f exceeds VARIATION_MAX %f" % [tx, ty, v, RoadPaint.VARIATION_MAX])
				return false
			worst = maxf(worst, absf(v))
			seen[str(v)] = true
	# The dead-variation negative: an identity (or constant) vary would collapse this to one
	# value, and a ground with no variation is the flat slab this slice exists to break up.
	if seen.size() < 2:
		push_error("vary produced %d distinct values over a 32x32 sample; the variation is dead" % seen.size())
		return false
	print("VARIATION OK %d distinct values over 32x32, |v| <= %.3f (max seen %.4f), position-hashed -- no RNG stream, so identical on every boot by construction" % [
		seen.size(), RoadPaint.VARIATION_MAX, worst,
	])
	return true


# --- 5. the palette -------------------------------------------------------------------------

# Two halves since "The ground is the pack's" (docs/23, 2026-09-27).
#
# **The ground** is pinned, not propertied. docs/30's "The whole outpost pack" records the owner's
# answer of 2026-09-25: the pack's tiles are brighter and more saturated than the warm-dark table
# (grass, dirt, water and wood all past the 0.30 saturation cap this lane used to hold), and "the
# ground lanes are re-pinned to a measured pack table, the old warm-dark table becomes the case
# they refuse". So the eight ground entries are held to PACK_GROUND exactly -- each the integer mean
# of its atlas row, measured off the pack's own pixels (TEXTURE below re-measures every one from
# the decoded atlas, so the pin cannot drift from the art) -- and WARM_DARK_GROUND, the table they
# replaced, is refused through the same predicate. The saturation cap and the ground's warm pin
# went with the table they described: the pack's asphalt is a neutral grey (r - b = 0.004) and its
# dirt and grass sit past S 0.50, which is the pack's grade and the owner's choice, not drift. What
# the pack's ground still has to be is kept as properties beside the pin, because they are what the
# rest of the district reads it by: paved in its value band, sidewalk over paved over background,
# the road paint brightest of the road family, six surfaces pairwise distinct, and water cool.
#
# **Everything else** -- walls, props, paint, marks, the dark -- keeps the warm dark-fantasy mood
# by property, so a tune stays legal inside the mood and a creep toward neutral shows in the
# thinnest margin before it goes grey. One deliberate divergence from the regrade spec's sketch:
# the distinctness floor is on RGB distance rather than on value, which still reds two identical
# tints without outlawing grounds separated by hue.
const PAIR_DISTANCE_MIN: float = 0.02
const WARM_MARGIN: float = 0.02

# The pack's ground, measured: each row of `ground_atlas.png`, both cells, integer-rounded mean of
# every pixel ((sum + count / 2) / count per channel -- never a float sum, CLAUDE.md's CPython
# trap). Keyed by the Palette.COLOURS entry each row draws with.
const PACK_GROUND: Dictionary = {
	"floor": "474646", "dirt": "896840", "grass": "485127", "undergrowth": "404820",
	"rubble": "595149", "water": "244e56", "sidewalk": "999793", "indoorFloor": "6d4f36",
}
# The warm-dark table the pack replaced -- the refused case. It is not dead data: it lives on as
# Palette.GENERATOR_GROUNDS for the guards that judge generated art, and this lane asserts the
# two agree, so the refused case is always the table the generator actually drew against.
const WARM_DARK_GROUND: Dictionary = {
	"floor": "474240", "dirt": "584e40", "grass": "4f5440", "undergrowth": "414a37",
	"rubble": "4e4a46", "water": "424f5c", "sidewalk": "5e5852", "indoorFloor": "6a5540",
}
# The COLOURS key each GroundRow draws with, in GroundRow order.
const ROW_KEYS: Array[String] = ["floor", "dirt", "grass", "undergrowth", "rubble", "water", "sidewalk", "indoorFloor"]

# The district's own walls, props and screen marks -- everything the warm-lit street is built
# from that is not the pack's ground. Judged with _warm_ok (r - b >= WARM_MARGIN). The sidewalk
# and the indoor floor are pack ground now and pinned above; they stay here because they still
# pass (r - b 0.024 and 0.216), and a later pack tile that cooled either would want saying.
const WARM_FAMILY: Array[String] = [
	"sidewalk", "kerb", "threshold", "indoorFloor", "wall", "roadPaint", "prop", "low",
	"screen", "tree", "groundItem", "glimpse", "memory", "roof",
]
# The dark the district sits inside: the night, the background behind it, and the one district
# surface meant to read as glass rather than as ground. Judged with _cool_ok (b - r >=
# WARM_MARGIN).
const COOL_FAMILY: Array[String] = ["background", "night", "window", "windowRim", "water"]

# The one *ground* that must be cool, by the owner's amendment to the 2026-09-03 Dungeon Settlers
# look (docs/30): water reads as water or it reads as nothing. The pack's teal keeps it (b - r =
# 0.196), and it is judged here from that side, so a water drifting to neutral fails.
const COOL_SURFACES: Array[int] = [SimSurface.Surface.Water]

# The six ground tints, named to match Palette.SURFACE_TINTS' order, for the prints below --
# SURFACE_TINTS itself carries no names, only an index.
const SURFACE_NAMES: Array[String] = ["floor", "dirt", "grass", "undergrowth", "rubble", "water"]

func _paved_value_ok(c: Color) -> bool:
	return c.v >= 0.20 and c.v <= 0.40


func _warm_ok(c: Color) -> bool:
	return c.r - c.b >= WARM_MARGIN


func _cool_ok(c: Color) -> bool:
	return c.b - c.r >= WARM_MARGIN


func _rgb_distance(a: Color, b: Color) -> float:
	return sqrt(pow(a.r - b.r, 2.0) + pow(a.g - b.g, 2.0) + pow(a.b - b.b, 2.0))


# The first ground key whose colour in `table` ({key: Color}) is not PACK_GROUND's hex, or "" when
# every one of the eight is. One predicate for the shipped palette and the refused tables.
func _ground_pin_problem(table: Dictionary) -> String:
	for key in PACK_GROUND.keys():
		if not table.has(key):
			return "%s is missing" % key
		var got: String = (table[key] as Color).to_html(false)
		if got != String(PACK_GROUND[key]):
			return "%s is #%s, not the pack's measured #%s" % [key, got, String(PACK_GROUND[key])]
	return ""


func _hex_table(hexes: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in hexes.keys():
		out[key] = Color("#" + String(hexes[key]))
	return out


func _the_palette_holds_the_mood_and_can_say_no() -> bool:
	# The ground: the eight entries exactly the pack's measured table, and the surface array built
	# from the same entries, so a tint cannot be pinned in one place and drawn from another.
	var shipped: Dictionary = {}
	for key in PACK_GROUND.keys():
		shipped[key] = Palette.COLOURS[key]
	var problem: String = _ground_pin_problem(shipped)
	if not problem.is_empty():
		push_error("PALETTE: the ground is not the pack's: %s (docs/30, 'The whole outpost pack': the ground takes the pack's own grade)" % problem)
		return false
	for si in Palette.SURFACE_TINTS.size():
		if Palette.SURFACE_TINTS[si] != Palette.COLOURS[ROW_KEYS[si]]:
			push_error("PALETTE: SURFACE_TINTS[%d] is %s, not COLOURS[%s]" % [si, str(Palette.SURFACE_TINTS[si]), ROW_KEYS[si]])
			return false
	# The refused case is the table the generated art is still judged against, so it has to be
	# that table and not a copy that drifted.
	for key2 in WARM_DARK_GROUND.keys():
		if (Palette.GENERATOR_GROUNDS[key2] as Color).to_html(false) != String(WARM_DARK_GROUND[key2]):
			push_error("PALETTE: GENERATOR_GROUNDS[%s] is #%s, not the warm-dark #%s this lane refuses" % [key2, (Palette.GENERATOR_GROUNDS[key2] as Color).to_html(false), String(WARM_DARK_GROUND[key2])])
			return false
	# TN: the warm-dark table is refused whole, and so is the pack table with any one entry nudged by
	# one step of one channel -- a pin that tolerates a neighbour is a band, not a pin.
	if _ground_pin_problem(_hex_table(WARM_DARK_GROUND)).is_empty():
		push_error("PALETTE: the warm-dark ground table passes the pack pin; a revert to the generated ground would not be caught")
		return false
	for key3 in PACK_GROUND.keys():
		var nudged: Dictionary = _hex_table(PACK_GROUND)
		var c: Color = nudged[key3] as Color
		nudged[key3] = Color8(mini(c.r8 + 1, 255), c.g8, c.b8)
		if _ground_pin_problem(nudged).is_empty():
			push_error("PALETTE: the pack table with %s nudged one step still passes; the pin reads nothing" % key3)
			return false

	var paved: Color = Palette.SURFACE_TINTS[SimSurface.Surface.Paved]
	if not _paved_value_ok(paved):
		push_error("paved sits at value %.3f, outside [0.20, 0.40] -- a cave floor or a bleached one" % paved.v)
		return false
	var sidewalk: Color = Palette.COLOURS["sidewalk"]
	var background: Color = Palette.COLOURS["background"]
	if not (sidewalk.v > paved.v and paved.v > background.v):
		push_error("value order broken: sidewalk %.3f, paved %.3f, background %.3f must descend" % [sidewalk.v, paved.v, background.v])
		return false
	var road_paint: Color = Palette.COLOURS["roadPaint"]
	for member in ["floor", "sidewalk", "kerb"]:
		if road_paint.v <= (Palette.COLOURS[member] as Color).v:
			push_error("roadPaint (%.3f) is not brighter than %s (%.3f); worn markings must read against the whole road family" % [road_paint.v, member, (Palette.COLOURS[member] as Color).v])
			return false
	var min_pair: float = INF
	for a in Palette.SURFACE_TINTS.size():
		for b in range(a + 1, Palette.SURFACE_TINTS.size()):
			var d: float = _rgb_distance(Palette.SURFACE_TINTS[a], Palette.SURFACE_TINTS[b])
			min_pair = minf(min_pair, d)
			if d < PAIR_DISTANCE_MIN:
				push_error("surface tints %d and %d sit %.4f apart in RGB; two grounds you cannot tell apart are one ground" % [a, b, d])
				return false
	for si2 in COOL_SURFACES:
		var sc: Color = Palette.SURFACE_TINTS[si2]
		if not _cool_ok(sc):
			push_error("ground %s is a COOL_SURFACES entry with b - r = %.4f, under WARM_MARGIN %.2f; water has to be cool, not merely un-warm" % [SURFACE_NAMES[si2], sc.b - sc.r, WARM_MARGIN])
			return false

	var warm_min: float = INF
	var warm_min_key: String = ""
	for key in WARM_FAMILY:
		var wc: Color = Palette.COLOURS[key] as Color
		var wmargin: float = wc.r - wc.b
		if wmargin < warm_min:
			warm_min = wmargin
			warm_min_key = key
		if not _warm_ok(wc):
			push_error("%s has r - b = %.4f, under WARM_MARGIN %.2f; it has cooled out of the district" % [key, wmargin, WARM_MARGIN])
			return false
	var cool_min: float = INF
	var cool_min_key: String = ""
	for key2 in COOL_FAMILY:
		var cc: Color = Palette.COLOURS[key2] as Color
		var cmargin: float = cc.b - cc.r
		if cmargin < cool_min:
			cool_min = cmargin
			cool_min_key = key2
		if not _cool_ok(cc):
			push_error("%s has b - r = %.4f, under WARM_MARGIN %.2f; the dark has warmed into the district" % [key2, cmargin, WARM_MARGIN])
			return false

	# The property half's own negatives: #1a1c1f (an old cave floor, value 0.12) fails the paved
	# band; #3f4143 (the old overcast floor) the warm pin; #2a1f18 (a warm background) the cool pin;
	# #5c4f42 (a warm silt river, the shape the water call was made against) the cool pin; and a
	# neutral grey must fail both family pins at once, at exactly zero.
	if _paved_value_ok(Color("#1a1c1f")):
		push_error("the old floor #1a1c1f passes the paved value band; a revert to the cave grade would not be caught")
		return false
	if _warm_ok(Color("#3f4143")):
		push_error("the old overcast floor #3f4143 passes the warm pin; the whole overcast table would slip back in on this one line")
		return false
	if _cool_ok(Color("#2a1f18")):
		push_error("a warm background #2a1f18 passes the cool pin; the dark would stop reading as dark")
		return false
	if _cool_ok(Color("#5c4f42")):
		push_error("a warm silt #5c4f42 passes the cool pin; a murky river would satisfy the water call and it would mean nothing")
		return false
	var neutral := Color("#4a4a4a")
	if _warm_ok(neutral) or _cool_ok(neutral):
		push_error("neutral grey #4a4a4a passes a family pin; the margin is a strict floor, not a sign test")
		return false

	print("PALETTE OK the 8 ground entries are the pack's measured table exactly (docs/30, the ground takes the pack's own grade), the warm-dark table and every one-step nudge of the pack's refused, GENERATOR_GROUNDS still the refused table; paved V %.2f in [0.20, 0.40], sidewalk > paved > background, roadPaint brightest of the family, 6 surfaces pairwise RGB >= %.2f (min %.4f), water cool; warm family r-b >= %.2f (thinnest %s +%.4f), cool family b-r >= %.2f (thinnest %s +%.4f)" % [
		paved.v, PAIR_DISTANCE_MIN, min_pair, WARM_MARGIN, warm_min_key, warm_min, WARM_MARGIN, cool_min_key, cool_min,
	])
	return true


# --- 6. the dead sockets ---------------------------------------------------------------------

# The rule this milestone paid for ten times: a resolver nothing calls is not a feature. (a) the
# draw loop reads the mask; (b) a placed rubble tile reaches the one sim mechanism that reads
# surfaces; (c) the rubble tint is resolved through the draw path's own resolver, not merely
# defined in the table.
# --- 6. the ground atlas ---------------------------------------------------------------------

# The atlas is the pack's pictures and the palette is their measured colour (docs/23, "The ground is
# the pack's"). Each cell is judged on its decoded pixels: opaque, not flat, and its mean within
# CELL_MEAN_MAX of its row's tint, so the modulated blit averages to the flat colour the palette
# draws when zoomed out. Each row's integer mean over both of its cells must then *be* the pinned
# hex PALETTE holds the palette to -- the measurement the pin was taken from, re-taken every run,
# with the warm-dark tint refused by the same comparison. The generated atlas also held every
# pixel to within 0.06 luma of its tint, for palette.py's ground guards' sake; those guards judge
# generated art against GENERATOR_GROUNDS now, and the pack's own highlights are the pack's.
const CELL_MEAN_MAX: float = 0.03
# The rows the pack paints once, so both variant cells are the same picture: its one water and its
# one wood floor. Named, not skipped -- the lane holds these two cells *identical*, so a second
# picture arriving in either is a thing somebody has to come and say.
const ONE_PICTURE_ROWS: Array[int] = [Appearance.GroundRow.Water, Appearance.GroundRow.Boards]


func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


# "" when the n x n cell at (x0, y0) is a lawful picture of `tint`, else what is wrong with it.
func _cell_problem(img: Image, x0: int, y0: int, n: int, tint: Color) -> String:
	var sum: Vector3 = Vector3.ZERO
	# Flatness is an exact question, not a variance under a float epsilon: a Vector3 running sum
	# of squares over a thousand pixels carries enough rounding to read a flat cell as textured.
	var first: Color = img.get_pixel(x0, y0)
	var textured: bool = false
	for y in n:
		for x in n:
			var c: Color = img.get_pixel(x0 + x, y0 + y)
			if c.a < 0.999:
				return "a transparent pixel at (%d, %d); ground is opaque" % [x0 + x, y0 + y]
			sum += Vector3(c.r, c.g, c.b)
			if c != first:
				textured = true
	var count: float = float(n * n)
	var mean: Vector3 = sum / count
	if not textured:
		return "flat -- every pixel the same colour, a texture in name only"
	var d: float = Vector3(tint.r, tint.g, tint.b).distance_to(mean)
	if d > CELL_MEAN_MAX:
		return "mean (%.3f, %.3f, %.3f) sits %.3f from its tint %s, over %.2f" % [mean.x, mean.y, mean.z, d, tint.to_html(false), CELL_MEAN_MAX]
	return ""


# The integer-rounded mean of a pixel rectangle as "rrggbb": whole-number channel sums and
# (sum + count / 2) / count, so the answer is the same on every machine (CLAUDE.md's float trap).
func _integer_mean_hex(img: Image, rect: Rect2i) -> String:
	var sums: Array[int] = [0, 0, 0]
	var count: int = 0
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var c: Color = img.get_pixel(x, y)
			sums[0] += c.r8
			sums[1] += c.g8
			sums[2] += c.b8
			count += 1
	if count == 0:
		return ""
	return "%02x%02x%02x" % [(sums[0] + count / 2) / count, (sums[1] + count / 2) / count, (sums[2] + count / 2) / count]


func _the_ground_is_a_texture_whose_mean_is_the_palette(stash: Dictionary) -> bool:
	Appearance.forget()
	var atlas: Texture2D = Appearance.ground_atlas()
	if atlas == null:
		push_error("no %s.png resolves; the floors have no picture to blit" % Appearance.GROUND_ATLAS_KEY)
		return false
	var n: int = int(CameraUtil.ART_NATIVE)
	var want: Vector2i = Appearance.canvas_of(Appearance.GROUND_ATLAS_KEY)
	if Vector2i(atlas.get_size()) != want or want != Vector2i((Appearance.GROUND_VARIANTS + Appearance.EDGE_SHAPES) * n, Appearance.GROUND_ROWS * n):
		push_error("the atlas is %s and its canvas %s, not %d variants + %d edge shapes x %d rows of %d px" % [str(atlas.get_size()), str(want), Appearance.GROUND_VARIANTS, Appearance.EDGE_SHAPES, Appearance.GROUND_ROWS, n])
		return false
	var img: Image = atlas.get_image()
	if img == null:
		push_error("the atlas texture yields no image to judge")
		return false
	var judged: int = 0
	for row in Appearance.GROUND_ROWS:
		var tint: Color = Appearance.ground_row_tint(row)
		if tint != Palette.COLOURS[ROW_KEYS[row]]:
			push_error("ground_row_tint(%d) is %s, not COLOURS[%s]" % [row, str(tint), ROW_KEYS[row]])
			return false
		var cells: Array[PackedByteArray] = []
		for v in Appearance.GROUND_VARIANTS:
			var region: Rect2 = Appearance.ground_cell(row, v)
			if region != Rect2(float(v * n), float(row * n), float(n), float(n)):
				push_error("ground_cell(%d, %d) answered %s, not the cell at column %d row %d" % [row, v, str(region), v, row])
				return false
			var problem: String = _cell_problem(img, int(region.position.x), int(region.position.y), n, tint)
			if not problem.is_empty():
				push_error("atlas row %d variant %d: %s" % [row, v, problem])
				return false
			cells.append(img.get_region(Rect2i(region)).get_data())
			judged += 1
		var one_picture: bool = ONE_PICTURE_ROWS.has(row)
		for a in cells.size():
			for b in range(a + 1, cells.size()):
				if one_picture and cells[a] != cells[b]:
					push_error("atlas row %d is a ONE_PICTURE_ROWS row and its variants %d and %d differ; the pack painted a second picture and nobody said so" % [row, a, b])
					return false
				if not one_picture and cells[a] == cells[b]:
					push_error("atlas row %d: variants %d and %d are the same pixels; two names for one picture" % [row, a, b])
					return false
		# The measurement the pin was taken from, re-taken: this row's integer mean is the hex
		# PALETTE holds the palette to, and the warm-dark tint is refused by the same comparison.
		var measured: String = _integer_mean_hex(img, Rect2i(0, row * n, Appearance.GROUND_VARIANTS * n, n))
		if measured != String(PACK_GROUND[ROW_KEYS[row]]):
			push_error("atlas row %d (%s) measures #%s, not the pinned #%s" % [row, ROW_KEYS[row], measured, String(PACK_GROUND[ROW_KEYS[row]])])
			return false
		if measured == String(WARM_DARK_GROUND[ROW_KEYS[row]]):
			push_error("atlas row %d measures the warm-dark #%s; the pin and the refused table agree, so the comparison reads nothing" % [row, measured])
			return false
	# The pure helpers: a row past the end clamps and a variant wraps, so no caller can ask for
	# pixels outside the picture; the modulate is the identity on a row's own tint and the exact
	# ratio otherwise.
	if Appearance.ground_cell(99, Appearance.GROUND_VARIANTS + 1) != Rect2(float(n), float((Appearance.GROUND_ROWS - 1) * n), float(n), float(n)):
		push_error("ground_cell does not clamp the row and wrap the variant: %s" % str(Appearance.ground_cell(99, Appearance.GROUND_VARIANTS + 1)))
		return false
	var grass: Color = Appearance.ground_row_tint(Appearance.GroundRow.Grass)
	var same: Color = Appearance.ground_modulate(grass, grass)
	if absf(same.r - 1.0) > 0.0001 or absf(same.g - 1.0) > 0.0001 or absf(same.b - 1.0) > 0.0001:
		push_error("ground_modulate(tint, tint) is %s, not white" % str(same))
		return false
	var doubled: Color = Appearance.ground_modulate(Color(0.6, 0.6, 0.6), Color(0.3, 0.3, 0.3))
	if absf(doubled.r - 2.0) > 0.0001:
		push_error("ground_modulate(0.6, 0.3) answered %s, not the 2.0 ratio" % str(doubled))
		return false
	if Appearance.ground_row_for(null, 0, 0, true) != Appearance.GroundRow.Sidewalk or Appearance.ground_row_for(null, 0, 0, false) != Appearance.GroundRow.Paved:
		push_error("ground_row_for does not answer Sidewalk for painted and Paved for an absent map")
		return false
	# The built-in negatives, through the one predicate: a flat cell and a cell painted a tenth
	# brighter than its tint must both be refused, or a dead atlas would pass the lane above; and
	# the integer mean must tell a real row from a nudged one.
	var flat: Image = Image.create(n, n, false, Image.FORMAT_RGBA8)
	flat.fill(Appearance.ground_row_tint(0))
	if _cell_problem(flat, 0, 0, n, Appearance.ground_row_tint(0)).is_empty():
		push_error("a flat cell passed the texture predicate; a dead atlas would pass this lane")
		return false
	var bright: Image = img.get_region(Rect2i(0, 0, n, n))
	for y in n:
		for x in n:
			var c: Color = bright.get_pixel(x, y)
			bright.set_pixel(x, y, Color(minf(c.r + 0.1, 1.0), minf(c.g + 0.1, 1.0), minf(c.b + 0.1, 1.0), 1.0))
	if _cell_problem(bright, 0, 0, n, Appearance.ground_row_tint(0)).is_empty():
		push_error("a cell a tenth brighter than its tint passed the texture predicate; the mean pin reads nothing")
		return false
	if _integer_mean_hex(bright, Rect2i(0, 0, n, n)) == _integer_mean_hex(img, Rect2i(0, 0, n, n)):
		push_error("the integer mean of a brightened cell equals the real one's; the measurement reads nothing")
		return false
	stash["atlas_cells"] = judged
	print("TEXTURE OK %s is %dx%d: %d pack cells, every one opaque, textured and averaging within %.2f of its row tint, every row's integer mean exactly its pinned pack hex (the warm-dark tint refused), variants pixel-distinct except the %d rows the pack paints once, held identical; the flat cell and the brightened cell both refused" % [
		Appearance.GROUND_ATLAS_KEY, want.x, want.y, judged, CELL_MEAN_MAX, ONE_PICTURE_ROWS.size(),
	])
	return true


# The socket and the deletion: _draw_floor_tile blits the cell through every helper above, at the
# zoom floor the palette names, and the hairline grid the flat fill used to draw is gone from
# both branches. Textual, on the function body, because the assertion is about what the draw
# loop reaches for and not about a number a helper returns.
func _the_floor_blits_its_cell_and_draws_no_grid() -> bool:
	var body: String = _function_body(MAIN_GD, "_draw_floor_tile")
	if body.is_empty():
		push_error("could not read _draw_floor_tile out of %s -- the grid lane had nothing to judge" % MAIN_GD)
		return false
	for needle in ["draw_texture_rect_region(", "Appearance.ground_atlas(", "Appearance.ground_cell(", "Dressing.SALT_GROUND", "Appearance.ground_modulate(", "Appearance.ground_row_tint(", "Palette.GROUND_TEXTURE_MIN_ZOOM", "draw_rect(rect, col)"]:
		if not body.contains(needle):
			push_error("_draw_floor_tile does not contain %s; the atlas resolves a cell nothing blits, or the flat fallback is gone" % needle)
			return false
	if body.contains(", false, 1.0)"):
		push_error("_draw_floor_tile still draws the hairline grid; the reference has no tile grid")
		return false
	if not CameraUtil.ZOOM_STEPS.has(Palette.GROUND_TEXTURE_MIN_ZOOM):
		push_error("GROUND_TEXTURE_MIN_ZOOM %.0f is not on the zoom ladder; a floor nobody can zoom to" % Palette.GROUND_TEXTURE_MIN_ZOOM)
		return false
	# Every caller hands the row over: the district loop for its three floor kinds and the
	# threshold for its boards. A caller that fell back to a flat colour and no row would draw
	# the paved cell under a lawn.
	var district: String = _function_body(MAIN_GD, "_draw_district")
	var calls: int = district.count("_draw_floor_tile(")
	var rows: int = district.count("Appearance.ground_row_for(")
	if calls < 3 or rows != calls:
		push_error("_draw_district calls _draw_floor_tile %d times and resolves a row %d times; every floor wants its row" % [calls, rows])
		return false
	var threshold: String = _function_body(MAIN_GD, "_draw_threshold")
	if not threshold.contains("Appearance.GroundRow.Boards"):
		push_error("_draw_threshold does not draw a doorway on boards")
		return false
	print("GRID OK _draw_floor_tile blits the atlas cell through the resolver at zoom >= %.0f, keeps the flat fill as its fallback, draws no hairline; %d district callers and the threshold all name their row" % [Palette.GROUND_TEXTURE_MIN_ZOOM, calls])
	return true


# --- EDGES: the ground has edges --------------------------------------------------------------
#
# docs/23's edges slice put a fringe column per side of a tile into the atlas, so a boundary
# between two grounds reads as a boundary and not a hard seam. Since "The ground is the pack's"
# (2026-09-27) the fringes are the pack's four grass fringes, on the two green rows only
# (Appearance.FRINGE_ROWS), and the pack paints no corner. The rule (Appearance.edge_shapes,
# row_luma, _edge_wins) is pure over a tile's row and its side neighbours' rows; this lane judges it
# five ways -- the atlas pixels (CELLS), the pure rule itself (MASK), the atlas region it addresses
# (REGION), whether the draw loop actually reaches it (SOCKET) -- and then plays the rule out on the
# shipped district (EDGE PLAYED). Only CELLS reads the atlas pixels.

# Each pack fringe, measured: how many of its pixels are solid (alpha >= 128) and their integer
# mean. Pinned exactly, because the cells are the pack's pictures and not a generator's
# approximation of a contract -- `sprites:check` proves each is its source pixel for pixel, and
# this is the half a Godot process can re-measure. Indexed by EdgeShape (N, E, S, W).
const FRINGE_SOLID: Array[int] = [283, 266, 258, 257]
const FRINGE_MEAN: Array[String] = ["3e471f", "3c441e", "3e461f", "3d451f"]
const FRINGE_ALPHA_SOLID: int = 128

# GroundRow's names, for the MASK lane's luma-order print -- GroundRow itself carries no names.
const ROW_NAMES: Array[String] = [
	"paved", "dirt", "grass", "undergrowth", "rubble", "water", "sidewalk", "boards",
]

# The side neighbour offsets in EdgeShape's own order, N first -- what a (row, shape) answer from
# edge_shapes names as "the neighbour this cell's fringe belongs to".
const EDGE_OFFSETS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
]


# The half of an n x n cell a fringe of `shape` lies in: the pack paints each fringe inside the
# half of its tile on its named side.
func _fringe_half(shape: int, n: int) -> Rect2i:
	var h: int = n / 2
	match shape:
		Appearance.EdgeShape.N:
			return Rect2i(0, 0, n, h)
		Appearance.EdgeShape.E:
			return Rect2i(n - h, 0, h, n)
		Appearance.EdgeShape.S:
			return Rect2i(0, n - h, n, h)
	return Rect2i(0, 0, h, n)


func _point_in_rect(x: int, y: int, r: Rect2i) -> bool:
	return x >= r.position.x and x < r.position.x + r.size.x and y >= r.position.y and y < r.position.y + r.size.y


# "" when the n x n cell at (x0, y0) is the pack's `shape` fringe, else what is wrong: every pixel
# with any alpha inside the shape's half, exactly FRINGE_SOLID[shape] solid pixels, and their
# integer mean exactly FRINGE_MEAN[shape]. One function so the fabricated negatives below refuse
# through the same code the real cells pass through.
func _edge_cell_problem(img: Image, x0: int, y0: int, n: int, shape: int) -> String:
	var half: Rect2i = _fringe_half(shape, n)
	var sums: Array[int] = [0, 0, 0]
	var solid: int = 0
	for y in n:
		for x in n:
			var c: Color = img.get_pixel(x0 + x, y0 + y)
			if c.a8 == 0:
				continue
			if not _point_in_rect(x, y, half):
				return "a fringe pixel at (%d, %d), alpha %d, lies outside the %s half" % [x, y, c.a8, str(half)]
			if c.a8 >= FRINGE_ALPHA_SOLID:
				solid += 1
				sums[0] += c.r8
				sums[1] += c.g8
				sums[2] += c.b8
	if solid != FRINGE_SOLID[shape]:
		return "%d solid pixels, not the pack fringe's %d" % [solid, FRINGE_SOLID[shape]]
	var mean: String = "%02x%02x%02x" % [(sums[0] + solid / 2) / solid, (sums[1] + solid / 2) / solid, (sums[2] + solid / 2) / solid]
	if mean != FRINGE_MEAN[shape]:
		return "solid mean #%s, not the pack fringe's #%s" % [mean, FRINGE_MEAN[shape]]
	return ""


# "" when the cell is transparent throughout -- an edge column on a row the pack gives no fringe.
func _blank_cell_problem(img: Image, x0: int, y0: int, n: int) -> String:
	for y in n:
		for x in n:
			if img.get_pixel(x0 + x, y0 + y).a8 != 0:
				return "a pixel at (%d, %d) carries alpha; this row has no fringe to draw" % [x, y]
	return ""


# 2. CELLS: every (row, shape) cell of the atlas sits at the region edge_cell names; on the fringe
# rows it is the pack's fringe for that side, and on every other row it is transparent. A fully
# opaque cell, a fringe judged on the wrong side, a brightened fringe and a real fringe judged as
# a blank are all refused through the same predicates.
func _the_edge_cells_are_lawful(stash: Dictionary) -> bool:
	Appearance.forget()
	var atlas: Texture2D = Appearance.ground_atlas()
	if atlas == null:
		push_error("CELLS: no %s.png resolves; the edge cells have no picture to blit" % Appearance.GROUND_ATLAS_KEY)
		return false
	var n: int = int(CameraUtil.ART_NATIVE)
	var want: Vector2i = Appearance.canvas_of(Appearance.GROUND_ATLAS_KEY)
	if Vector2i(atlas.get_size()) != want:
		push_error("CELLS: the atlas is %s, its canvas is %s -- the edge columns are not landed at %d variants + %d shapes" % [str(atlas.get_size()), str(want), Appearance.GROUND_VARIANTS, Appearance.EDGE_SHAPES])
		return false
	var img: Image = atlas.get_image()
	if img == null:
		push_error("CELLS: the atlas texture yields no image to judge")
		return false
	var fringes: int = 0
	var blanks: int = 0
	for row in Appearance.GROUND_ROWS:
		for shape in Appearance.EDGE_SHAPES:
			var region: Rect2 = Appearance.edge_cell(row, shape)
			var expect: Rect2 = Rect2(float((Appearance.GROUND_VARIANTS + shape) * n), float(row * n), float(n), float(n))
			if region != expect:
				push_error("CELLS: edge_cell(%d, %d) answered %s, not %s" % [row, shape, str(region), str(expect)])
				return false
			var problem: String
			if Appearance.FRINGE_ROWS.has(row):
				problem = _edge_cell_problem(img, int(region.position.x), int(region.position.y), n, shape)
				fringes += 1
			else:
				problem = _blank_cell_problem(img, int(region.position.x), int(region.position.y), n)
				blanks += 1
			if not problem.is_empty():
				push_error("CELLS: atlas row %d shape %d: %s" % [row, shape, problem])
				return false

	# The negatives, through the same predicates.
	var opaque: Image = Image.create(n, n, false, Image.FORMAT_RGBA8)
	opaque.fill(Appearance.ground_row_tint(0))
	if _edge_cell_problem(opaque, 0, 0, n, Appearance.EdgeShape.N).is_empty():
		push_error("CELLS: a fully opaque cell passed the edge predicate; the half and count pins read nothing")
		return false
	var n_region: Rect2 = Appearance.edge_cell(Appearance.GroundRow.Grass, Appearance.EdgeShape.N)
	var wrong_edge: Image = img.get_region(Rect2i(n_region))
	if _edge_cell_problem(wrong_edge, 0, 0, n, Appearance.EdgeShape.S).is_empty():
		push_error("CELLS: the real N fringe, judged as an S cell, passed the edge predicate; the half pin reads nothing")
		return false
	if _blank_cell_problem(wrong_edge, 0, 0, n).is_empty():
		push_error("CELLS: the real N fringe passed as a blank cell; the blank predicate reads nothing")
		return false
	var bright: Image = img.get_region(Rect2i(n_region))
	for y in n:
		for x in n:
			var c: Color = bright.get_pixel(x, y)
			if c.a > 0.0:
				bright.set_pixel(x, y, Color(minf(c.r + 0.1, 1.0), minf(c.g + 0.1, 1.0), minf(c.b + 0.1, 1.0), c.a))
	if _edge_cell_problem(bright, 0, 0, n, Appearance.EdgeShape.N).is_empty():
		push_error("CELLS: a fringe a tenth brighter than the pack's passed the edge predicate; the mean pin reads nothing")
		return false

	stash["edge_cells"] = fringes
	print("CELLS OK %d edge cells (%d rows x %d shapes): the %d on the green rows each the pack's grass fringe for its side (inside its half, %s solid pixels, means #%s), the other %d transparent; a flat cell, a fringe on the wrong side, a brightened fringe and a fringe passed off as blank all refused" % [
		fringes + blanks, Appearance.GROUND_ROWS, Appearance.EDGE_SHAPES, fringes, str(FRINGE_SOLID), "/#".join(FRINGE_MEAN), blanks,
	])
	return true


# 3. MASK: Appearance.edge_shapes, pure -- the true negative first, then the darker-wins rule over
# the green rows, the new refusal (a darker ground with no fringe draws nothing), side order, the
# diagonals ignored, ROW_NONE and a malformed neighbours array, and the tie rule (row_luma is a
# strict total order, so _edge_wins is never true both ways for a pair).
func _the_edge_mask_never_draws_both_ways() -> bool:
	var grass: int = Appearance.GroundRow.Grass
	var under: int = Appearance.GroundRow.Undergrowth
	var paved: int = Appearance.GroundRow.Paved
	var dirt: int = Appearance.GroundRow.Dirt
	var none: int = Appearance.ROW_NONE

	var same := PackedInt32Array([grass, grass, grass, grass, grass, grass, grass, grass])
	if not Appearance.edge_shapes(grass, same).is_empty():
		push_error("MASK: edge_shapes(Grass, [Grass x 8]) answered %s, not []" % str(Appearance.edge_shapes(grass, same)))
		return false

	# Grass (luma 0.298) is darker than the pack's dirt (0.424): its fringe draws onto dirt.
	var grass_on_dirt := PackedInt32Array([grass, dirt, dirt, dirt, dirt, dirt, dirt, dirt])
	var got: Array[Vector2i] = Appearance.edge_shapes(dirt, grass_on_dirt)
	if got != [Vector2i(grass, Appearance.EdgeShape.N)]:
		push_error("MASK: edge_shapes(Dirt, N=Grass) answered %s, want [(Grass, N)]" % str(got))
		return false

	# ...and never the other way: grass is lighter than asphalt, so it draws nothing onto it.
	var grass_on_paved := PackedInt32Array([grass, paved, paved, paved, paved, paved, paved, paved])
	if not Appearance.edge_shapes(paved, grass_on_paved).is_empty():
		push_error("MASK: edge_shapes(Paved, N=Grass) answered %s, not [] -- the lighter drew onto the darker" % str(Appearance.edge_shapes(paved, grass_on_paved)))
		return false

	# The pack paints no fringe but grass: asphalt is darker than dirt and still draws nothing.
	var paved_on_dirt := PackedInt32Array([paved, dirt, dirt, dirt, dirt, dirt, dirt, dirt])
	if not Appearance.edge_shapes(dirt, paved_on_dirt).is_empty():
		push_error("MASK: edge_shapes(Dirt, N=Paved) answered %s, not [] -- a ground with no fringe art drew one" % str(Appearance.edge_shapes(dirt, paved_on_dirt)))
		return false

	# Undergrowth (0.264) is darker than asphalt (0.275), so the thicket spills onto the road.
	var two_sides := PackedInt32Array([grass, under, dirt, dirt, dirt, dirt, dirt, dirt])
	var got2: Array[Vector2i] = Appearance.edge_shapes(dirt, two_sides)
	if got2 != [Vector2i(grass, Appearance.EdgeShape.N), Vector2i(under, Appearance.EdgeShape.E)]:
		push_error("MASK: edge_shapes(Dirt, N=Grass, E=Undergrowth) answered %s, want [(Grass, N), (Undergrowth, E)]" % str(got2))
		return false
	var under_on_paved := PackedInt32Array([paved, paved, paved, under, paved, paved, paved, paved])
	if Appearance.edge_shapes(paved, under_on_paved) != [Vector2i(under, Appearance.EdgeShape.W)]:
		push_error("MASK: edge_shapes(Paved, W=Undergrowth) answered %s, want [(Undergrowth, W)]" % str(Appearance.edge_shapes(paved, under_on_paved)))
		return false

	# The pack paints no corner: a darker green diagonal alone draws nothing.
	var corner_only := PackedInt32Array([dirt, dirt, dirt, dirt, grass, grass, grass, grass])
	if not Appearance.edge_shapes(dirt, corner_only).is_empty():
		push_error("MASK: edge_shapes(Dirt, diagonals=Grass) answered %s, not [] -- a corner drew with no corner art" % str(Appearance.edge_shapes(dirt, corner_only)))
		return false

	var absent := PackedInt32Array([none, grass, grass, grass, grass, grass, grass, grass])
	if not Appearance.edge_shapes(grass, absent).is_empty():
		push_error("MASK: edge_shapes(Grass, N=ROW_NONE) answered %s, not []" % str(Appearance.edge_shapes(grass, absent)))
		return false
	if not Appearance.edge_shapes(none, same).is_empty():
		push_error("MASK: edge_shapes(ROW_NONE, ...) answered %s, not []" % str(Appearance.edge_shapes(none, same)))
		return false

	var short := PackedInt32Array([grass, grass, grass])
	if not Appearance.edge_shapes(grass, short).is_empty():
		push_error("MASK: edge_shapes with a 3-long neighbours array answered %s, not []" % str(Appearance.edge_shapes(grass, short)))
		return false

	var rows: Array = []
	for r in Appearance.GROUND_ROWS:
		rows.append(r)
	rows.sort_custom(func(a, b): return Appearance.row_luma(a) < Appearance.row_luma(b))
	var order_names: PackedStringArray = PackedStringArray()
	for r2 in rows:
		order_names.append(ROW_NAMES[int(r2)])
	for i in range(rows.size() - 1):
		var la: float = Appearance.row_luma(int(rows[i]))
		var lb: float = Appearance.row_luma(int(rows[i + 1]))
		if lb - la <= 0.0:
			push_error("MASK: row_luma is not strictly ordered: %s (%.4f) then %s (%.4f)" % [ROW_NAMES[int(rows[i])], la, ROW_NAMES[int(rows[i + 1])], lb])
			return false
	for a2 in Appearance.GROUND_ROWS:
		for b2 in Appearance.GROUND_ROWS:
			if a2 == b2:
				continue
			if Appearance._edge_wins(a2, b2) and Appearance._edge_wins(b2, a2):
				push_error("MASK: _edge_wins(%d, %d) and _edge_wins(%d, %d) are both true" % [a2, b2, b2, a2])
				return false

	for r3 in Appearance.GROUND_ROWS:
		var c: Color = Appearance.ground_row_tint(r3)
		var recomputed: float = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
		if absf(recomputed - Appearance.row_luma(r3)) > 0.000001:
			push_error("MASK: row_luma(%d) = %.6f does not match Rec. 709 of ground_row_tint: %.6f" % [r3, Appearance.row_luma(r3), recomputed])
			return false

	print("MASK OK identical neighbours draw nothing; a darker green side draws its fringe in side order and the lighter never draws on the darker; a darker ground with no fringe art, and a diagonal (no corner art), draw nothing; ROW_NONE and a short array draw nothing; luma order %s, no pair of the %d rows ever wins both ways, row_luma matches Rec. 709 of ground_row_tint" % [
		", ".join(order_names), Appearance.GROUND_ROWS,
	])
	return true


# 4. REGION: edge_cell clamps like ground_cell, and no edge cell's x range ever overlaps a
# variant cell's -- the two halves of the atlas never address the same pixels.
func _the_edge_region_is_clamped_and_disjoint() -> bool:
	var n: int = int(CameraUtil.ART_NATIVE)
	var last_row: int = Appearance.GROUND_ROWS - 1
	var last_shape: int = Appearance.EDGE_SHAPES - 1
	var clamped: Rect2 = Appearance.edge_cell(99, 99)
	var want: Rect2 = Rect2(float((Appearance.GROUND_VARIANTS + last_shape) * n), float(last_row * n), float(n), float(n))
	if clamped != want:
		push_error("REGION: edge_cell(99, 99) answered %s, not the last row's W cell %s" % [str(clamped), str(want)])
		return false
	if clamped != Appearance.edge_cell(last_row, last_shape):
		push_error("REGION: edge_cell(99, 99) does not equal edge_cell(%d, %d)" % [last_row, last_shape])
		return false

	for row in Appearance.GROUND_ROWS:
		for v in Appearance.GROUND_VARIANTS:
			var gc: Rect2 = Appearance.ground_cell(row, v)
			var gx0: float = gc.position.x
			var gx1: float = gc.position.x + gc.size.x
			for row2 in Appearance.GROUND_ROWS:
				for shape in Appearance.EDGE_SHAPES:
					var ec: Rect2 = Appearance.edge_cell(row2, shape)
					var ex0: float = ec.position.x
					var ex1: float = ec.position.x + ec.size.x
					if gx0 < ex1 and ex0 < gx1:
						push_error("REGION: ground_cell(%d, %d) x[%.0f, %.0f) overlaps edge_cell(%d, %d) x[%.0f, %.0f)" % [row, v, gx0, gx1, row2, shape, ex0, ex1])
						return false
	print("REGION OK edge_cell(99, 99) clamps to row %d shape %d (W); every variant cell's x range sits disjoint from every edge cell's" % [last_row, last_shape])
	return true


# The first needle missing from a body, or "" when every needle is present. Proven on a
# fabricated body before the real scan below -- the check_topdown.gd convention.
func _needles_missing(body: String, needles: Array[String]) -> String:
	for needle in needles:
		if not body.contains(needle):
			return needle
	return ""


# 5. SOCKET: the draw loop actually reaches edge_shapes/edge_cell, the row cache it reads is
# built from ground_row_for and the road mask, and the fringe draws after its own floor and
# before the dash -- textual, because a CanvasItem draw pass cannot run headless.
func _the_edges_socket_is_wired() -> bool:
	if _needles_missing("var x = 1\n", ["Appearance.edge_shapes("]).is_empty():
		push_error("SOCKET: the needle scanner passed a fabricated body with no needles in it; the socket assertion reads nothing")
		return false

	var edges_body: String = _function_body(MAIN_GD, "_draw_ground_edges")
	if edges_body.is_empty():
		push_error("SOCKET: could not read _draw_ground_edges out of %s" % MAIN_GD)
		return false
	var missing: String = _needles_missing(edges_body, [
		"Appearance.edge_shapes(", "Appearance.edge_cell(", "draw_texture_rect_region(",
		"Appearance.ground_atlas(", "Palette.GROUND_TEXTURE_MIN_ZOOM", "Color.WHITE",
	])
	if not missing.is_empty():
		push_error("SOCKET: _draw_ground_edges does not contain %s; the fringe resolves and draws nothing" % missing)
		return false

	var rows_body: String = _function_body(MAIN_GD, "_ground_rows")
	if rows_body.is_empty():
		push_error("SOCKET: could not read _ground_rows out of %s" % MAIN_GD)
		return false
	var missing2: String = _needles_missing(rows_body, [
		"Appearance.ROW_NONE", "Appearance.ground_row_for(", "_road_mask()",
	])
	if not missing2.is_empty():
		push_error("SOCKET: _ground_rows does not contain %s; the row cache is not what the edge rule reads" % missing2)
		return false

	var district: String = _function_body(MAIN_GD, "_draw_district")
	if district.is_empty():
		push_error("SOCKET: could not read _draw_district out of %s" % MAIN_GD)
		return false
	var floor_at: int = district.find("_draw_floor_tile(rect, floor_col")
	var edges_at: int = district.find("_draw_ground_edges(")
	var dash_at: int = district.find("_draw_road_dash(")
	if floor_at < 0 or edges_at < 0 or dash_at < 0:
		push_error("SOCKET: _draw_district is missing the outdoor floor blit, the edge call or the dash call")
		return false
	if not (floor_at < edges_at and edges_at < dash_at):
		push_error("SOCKET: _draw_district calls floor at %d, edges at %d, dash at %d; the fringe must draw between them" % [floor_at, edges_at, dash_at])
		return false

	print("SOCKET OK _draw_ground_edges names edge_shapes, edge_cell, the atlas blit and its zoom floor; _ground_rows names ROW_NONE, ground_row_for and the road mask; the district draws the fringe after its own floor and before the dash")
	return true


# A neighbour's row for the PLAYED lane's own row array, ROW_NONE past the map's edge -- the
# same answer main.gd's `_row_at` gives, recomputed here because a gate cannot call an instance
# method on a CanvasItem.
func _played_row_at(rows: PackedByteArray, w: int, h: int, tx: int, ty: int) -> int:
	if tx < 0 or ty < 0 or tx >= w or ty >= h:
		return Appearance.ROW_NONE
	return int(rows[ty * w + tx])


# 6. EDGE PLAYED: the shipped 256 district, with the same row array _ground_rows would build
# (recomputed here, per the dead-socket rule, so this is a claim about the actual map and not
# about the pure rule in isolation) -- edges are drawn, a uniformly-neighboured tile draws none,
# and every boundary the rule draws is drawn by exactly one side of it.
func _edges_play_out_on_the_shipped_district(stash: Dictionary) -> bool:
	var played: Variant = stash.get("played_map")
	if played == null:
		played = SimWorldgen.generate(CANON_SEED, PLAYED_SIZE, _tree())
		stash["played_map"] = played
	var w: int = int(played.w)
	var h: int = int(played.h)
	var mask: PackedByteArray = RoadPaint.mask_for(played)
	var rows := PackedByteArray()
	rows.resize(w * h)
	for ty in h:
		for tx in w:
			var idx: int = ty * w + tx
			var tile: int = int(SimTileMap.tile_at(played, tx, ty))
			if tile == SimTileMap.Tile.Wall or tile == SimTileMap.Tile.Window or tile == SimTileMap.Tile.Screen or tile == SimTileMap.Tile.Tree:
				rows[idx] = Appearance.ROW_NONE
			else:
				rows[idx] = int(Appearance.ground_row_for(played, tx, ty, int(mask[idx]) == RoadPaint.MASK_SIDEWALK))

	var with_edges: int = 0
	var without_edges: int = 0
	var total_pairs: int = 0
	var boundaries: Dictionary = {}
	for ty2 in h:
		for tx2 in w:
			var idx2: int = ty2 * w + tx2
			var centre: int = int(rows[idx2])
			if centre == Appearance.ROW_NONE:
				continue
			var around := PackedInt32Array([
				_played_row_at(rows, w, h, tx2, ty2 - 1), _played_row_at(rows, w, h, tx2 + 1, ty2),
				_played_row_at(rows, w, h, tx2, ty2 + 1), _played_row_at(rows, w, h, tx2 - 1, ty2),
				_played_row_at(rows, w, h, tx2 + 1, ty2 - 1), _played_row_at(rows, w, h, tx2 + 1, ty2 + 1),
				_played_row_at(rows, w, h, tx2 - 1, ty2 + 1), _played_row_at(rows, w, h, tx2 - 1, ty2 - 1),
			])
			var cells: Array[Vector2i] = Appearance.edge_shapes(centre, around)
			var is_outdoor_floor: bool = int(SimTileMap.tile_at(played, tx2, ty2)) == SimTileMap.Tile.Floor and int(played.indoors[idx2]) == 0
			if is_outdoor_floor:
				var uniform: bool = true
				for nb in around:
					if int(nb) != centre:
						uniform = false
						break
				if uniform and not cells.is_empty():
					push_error("EDGE PLAYED: tile (%d, %d) has eight same-row neighbours yet drew %d edge cells" % [tx2, ty2, cells.size()])
					return false
				if cells.is_empty():
					without_edges += 1
				else:
					with_edges += 1
			for cell in cells:
				total_pairs += 1
				var off: Vector2i = EDGE_OFFSETS[int(cell.y)]
				var ax: int = tx2
				var ay: int = ty2
				var bx: int = tx2 + off.x
				var by: int = ty2 + off.y
				var key: String
				if ay < by or (ay == by and ax < bx):
					key = "%d,%d|%d,%d" % [ax, ay, bx, by]
				else:
					key = "%d,%d|%d,%d" % [bx, by, ax, ay]
				if boundaries.has(key):
					push_error("EDGE PLAYED: boundary %s is drawn twice -- both tiles either side drew a fringe onto each other" % key)
					return false
				boundaries[key] = true

	if with_edges == 0:
		push_error("EDGE PLAYED: no outdoor Floor tile on the shipped %d district drew an edge cell" % PLAYED_SIZE)
		return false
	if total_pairs != boundaries.size():
		push_error("EDGE PLAYED: %d (tile, cell) pairs drawn but %d distinct boundaries -- some boundary drawn twice" % [total_pairs, boundaries.size()])
		return false

	stash["edge_with"] = with_edges
	stash["edge_without"] = without_edges
	print("EDGE PLAYED OK the shipped %d district: %d outdoor floor tiles draw >= 1 edge and %d draw none, no uniform-neighbourhood tile draws one, and its %d edge draws are %d distinct boundaries, each drawn once" % [
		PLAYED_SIZE, with_edges, without_edges, total_pairs, boundaries.size(),
	])
	return true


# The lane itself: every sub-assertion above runs regardless of an earlier one failing (the
# _run convention), so a red CELLS lane -- the one that needs the wide atlas -- does not hide a
# red MASK, REGION, SOCKET or EDGE PLAYED. Prints EDGES OK only when every one of them did.
func _the_ground_has_edges(stash: Dictionary) -> bool:
	var ok: bool = true
	ok = _the_edge_cells_are_lawful(stash) and ok
	ok = _the_edge_mask_never_draws_both_ways() and ok
	ok = _the_edge_region_is_clamped_and_disjoint() and ok
	ok = _the_edges_socket_is_wired() and ok
	ok = _edges_play_out_on_the_shipped_district(stash) and ok
	if not ok:
		return false
	print("EDGES OK %d authored edge cells, the mask and its region pure and disjoint from the variants, the socket wired, %d/%d floor tiles on the shipped %d district edged/plain" % [
		int(stash.get("edge_cells", 0)), int(stash.get("edge_with", 0)), int(stash.get("edge_without", 0)), PLAYED_SIZE,
	])
	return true


func _the_three_sockets_are_wired(stash: Dictionary) -> bool:
	var district: String = _function_body(MAIN_GD, "_draw_district")
	if district.is_empty():
		push_error("could not read _draw_district out of %s -- the reach assertion had nothing to judge" % MAIN_GD)
		return false
	if not district.contains("RoadPaint."):
		push_error("_draw_district never touches RoadPaint: the mask resolves paint nothing draws")
		return false
	for helper in ["_draw_road_dash(", "_draw_kerbs("]:
		if not district.contains(helper):
			push_error("_draw_district does not call %s; that half of the paint resolves and draws nothing" % helper)
			return false

	var map: Variant = stash["map"]
	var world: Variant = stash["world"]
	var rubble_at: Vector2i = Vector2i(-1, -1)
	var paved_at: Vector2i = Vector2i(-1, -1)
	for ty in int(map.h):
		for tx in int(map.w):
			var idx: int = ty * int(map.w) + tx
			if rubble_at.x < 0 and int(map.surfaces[idx]) == SimTileMap.SURFACE_RUBBLE:
				rubble_at = Vector2i(tx, ty)
			if paved_at.x < 0 and int(map.surfaces[idx]) == SimTileMap.SURFACE_PAVED and int(map.tiles[idx]) == SimTileMap.Tile.Floor:
				paved_at = Vector2i(tx, ty)
	if rubble_at.x < 0:
		push_error("the canonical seed placed no rubble tile for the socket lanes to read")
		return false
	var speed: float = float(world.surface_speed_at(float(rubble_at.x) + 0.5, float(rubble_at.y) + 0.5))
	if absf(speed - SimSurface.SPEED[SimSurface.Surface.Rubble]) > 0.000001 or absf(speed - 0.7) > 0.000001:
		push_error("a placed rubble tile reads x%.3f through the world's surface-speed path; SPEED[Rubble] is %.2f" % [speed, SimSurface.SPEED[SimSurface.Surface.Rubble]])
		return false
	# The control: pavement still reads 1.0, or the read above proves only that everything slowed.
	if absf(float(world.surface_speed_at(float(paved_at.x) + 0.5, float(paved_at.y) + 0.5)) - 1.0) > 0.000001:
		push_error("a paved tile no longer reads x1.0 through the surface-speed path")
		return false

	var tint: Color = Appearance.ground_colour(map, rubble_at.x, rubble_at.y)
	if tint != Palette.COLOURS["rubble"]:
		push_error("a placed rubble tile resolves %s, not the rubble tint" % str(tint))
		return false
	if tint == Palette.COLOURS["floor"]:
		push_error("the rubble tint is indistinguishable from paved; the resolution proves nothing")
		return false

	print("SOCKETS OK _draw_district reads RoadPaint and draws both paint halves; rubble at %s reads x%.1f speed against pavement's x1.0 and resolves its own tint" % [str(rubble_at), speed])
	return true


# --- 7. rubble placed, dressing-only, floor-only ---------------------------------------------

# Returns the index of the first unlawful rubble tile, or -1. Named so the sabotage below
# refuses through the same predicate the true positive passes.
func _first_unlawful_rubble(map: Variant) -> int:
	for i in (map.surfaces as PackedByteArray).size():
		if int(map.surfaces[i]) != SimTileMap.SURFACE_RUBBLE:
			continue
		if int(map.tiles[i]) != SimTileMap.Tile.Floor or int(map.indoors[i]) == 1:
			return i
	return -1


func _rubble_is_placed_and_lawful(stash: Dictionary) -> bool:
	var map: Variant = stash["map"]
	var placed: int = 0
	for i in (map.surfaces as PackedByteArray).size():
		if int(map.surfaces[i]) == SimTileMap.SURFACE_RUBBLE:
			placed += 1
	# The floor is deliberately modest: the pass is ~1-in-4 over building aprons plus a blob and
	# the street patches, and the canonical 64 map measures ~129 -- the assertion is "the pass
	# reaches the map", scaled expectation printed, not a band nobody measured.
	if placed < 8:
		push_error("the canonical seed at %d placed %d rubble tiles; the pass is not reaching the map" % [GATE_SIZE, placed])
		return false
	stash["rubble"] = placed
	var offender: int = _first_unlawful_rubble(map)
	if offender >= 0:
		push_error("rubble at index %d lies on tile %d indoors=%d; the write rule is Floor-and-outdoors only" % [
			offender, int(map.tiles[offender]), int(map.indoors[offender]),
		])
		return false

	# Dressing-only: the undressed generation carries none.
	var bare: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, _tree(), SimWorldgen.DEFAULT_DISTRICT, false)
	for i2 in (bare.surfaces as PackedByteArray).size():
		if int(bare.surfaces[i2]) == SimTileMap.SURFACE_RUBBLE:
			push_error("dress=false still placed rubble at %d; the pass has left the dressing" % i2)
			return false

	# The `_footing` trap, refused twice through the same predicate: rubble hand-written under a
	# Low wreck (walkability silently deleted) and under an indoor floor, on a throwaway map so
	# the stash stays honest.
	var sab: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, _tree())
	var surfaces: PackedByteArray = sab.surfaces as PackedByteArray
	var tiles: PackedByteArray = sab.tiles as PackedByteArray
	var low: int = -1
	var indoor: int = -1
	for i3 in tiles.size():
		if low < 0 and int(tiles[i3]) == SimTileMap.Tile.Low:
			low = i3
		if indoor < 0 and int(sab.indoors[i3]) == 1 and int(tiles[i3]) == SimTileMap.Tile.Floor:
			indoor = i3
	if low < 0 or indoor < 0:
		push_error("the sabotage map stood no Low tile (%d) or indoor floor (%d); the negatives had nothing to write on" % [low, indoor])
		return false
	surfaces[low] = SimTileMap.SURFACE_RUBBLE
	sab.surfaces = surfaces
	if _first_unlawful_rubble(sab) != low:
		push_error("rubble hand-written under a Low wreck was not refused; the checker cannot see the _footing trap")
		return false
	surfaces[low] = SimTileMap.SURFACE_PAVED
	surfaces[indoor] = SimTileMap.SURFACE_RUBBLE
	sab.surfaces = surfaces
	if _first_unlawful_rubble(sab) != indoor:
		push_error("rubble hand-written on an indoor floor was not refused")
		return false

	print("RUBBLE OK %d tiles on the canonical %d map (expectation: aprons at ~1-in-4 over two rings per building, one blob, street patches), every one outdoor open Floor; dress=false places 0; a wreck and an indoor floor both refused" % [
		placed, GATE_SIZE,
	])
	return true


# --- 11. dirt roads (slice 9) -----------------------------------------------------------------

# `street_surface_of` reads a district's declared `streets.surface` name through
# `SimWorldgen.STREET_SURFACES`, defaulting to paved for anything it does not recognise -- so a
# typo in a district file draws a street rather than erasing one. Held four ways at the function
# (no `streets` block at all, a block naming no surface, a block naming an unknown surface, and
# the name this slice adds), then on the booted map: every carved span carries the answer as a
# `"surface"` key, and the shipped suburb -- which declares none -- is paved throughout.
func _street_surface_of_defaults_to_paved_and_dirt_is_named(stash: Dictionary) -> bool:
	var no_block: int = int(SimWorldgen.street_surface_of({}))
	if no_block != SimTileMap.SURFACE_PAVED:
		push_error("street_surface_of({}) (no streets block at all) answered %d, not SURFACE_PAVED" % no_block)
		return false
	var no_name: int = int(SimWorldgen.street_surface_of({"streets": {}}))
	if no_name != SimTileMap.SURFACE_PAVED:
		push_error("street_surface_of naming no surface answered %d, not SURFACE_PAVED" % no_name)
		return false
	var unknown_name: int = int(SimWorldgen.street_surface_of({"streets": {"surface": "cobblestone"}}))
	if unknown_name != SimTileMap.SURFACE_PAVED:
		push_error("street_surface_of naming an unknown surface answered %d, not the SURFACE_PAVED default" % unknown_name)
		return false
	var dirt_name: int = int(SimWorldgen.street_surface_of({"streets": {"surface": "dirt"}}))
	if dirt_name != SimTileMap.SURFACE_DIRT:
		push_error("street_surface_of naming \"dirt\" answered %d, not SURFACE_DIRT" % dirt_name)
		return false

	# The true negative this lane exists for: an unknown name has to be reaching the default
	# through the table rather than matching some accident of the fallback -- hand it a name the
	# table *does* recognise and show the answer moves.
	if not (SimWorldgen.STREET_SURFACES as Dictionary).has("dirt"):
		push_error("STREET_SURFACES does not carry \"dirt\" any more; the negative below would prove nothing")
		return false
	if unknown_name == dirt_name:
		push_error("an unknown surface name and \"dirt\" answered the same int (%d); the unknown case may be matching by accident rather than falling through to the default" % unknown_name)
		return false

	# On the booted map: every carved span carries a surface key, and the shipped suburb (which
	# declares no streets.surface) is paved throughout.
	var map: Variant = stash["map"]
	var spans: Array = map.streets as Array
	if spans.is_empty():
		push_error("the booted suburb carries no street manifest at all; the surface-key assertion has nothing to judge")
		return false
	for span_value in spans:
		var span: Dictionary = span_value as Dictionary
		if not span.has("surface"):
			push_error("street span %s carries no \"surface\" key" % str(span))
			return false
		if int(span["surface"]) != SimTileMap.SURFACE_PAVED:
			push_error("the shipped suburb, which declares no streets.surface, carved a span at %s with surface %d, not paved" % [str(span), int(span["surface"])])
			return false

	stash["surfaced_spans"] = spans.size()
	print("DIRT ROADS OK street_surface_of: no block, no name and an unknown name all answer paved, \"dirt\" answers SURFACE_DIRT (the unknown case differs from the known one); all %d carved spans on the suburb carry \"surface\" and read paved" % spans.size())
	return true


# --- the budget ------------------------------------------------------------------------------

func _the_gate_stayed_inside_its_own_budget(seconds: float) -> bool:
	if seconds > BUDGET_SECONDS:
		push_error("the road-look gate took %.1f s against a %.0f s budget -- share boots between lanes rather than adding them" % [seconds, BUDGET_SECONDS])
		return false
	if seconds <= 0.0:
		push_error("the gate measured %.1f s of its own wall time, so the budget is measuring nothing" % seconds)
		return false
	print("BUDGET OK %.1f s of a %.0f s budget" % [seconds, BUDGET_SECONDS])
	return true


# The source text of one function, from its `func` line to the next top-level `func` -- the
# check_topdown precedent: a CanvasItem draw pass cannot run headless, so what it calls is read.
func _function_body(path: String, name: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var lines: PackedStringArray = f.get_as_text().split("\n")
	var out: String = ""
	var inside: bool = false
	for line in lines:
		if line.begins_with("func %s(" % name):
			inside = true
			continue
		if inside and line.begins_with("func "):
			break
		if inside:
			out += line + "\n"
	return out
