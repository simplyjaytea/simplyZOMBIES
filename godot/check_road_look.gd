extends SceneTree
# The ground and road dressing: the street manifest the generator now carves alongside its
# streets (`map.streets`), the draw-time paint resolved from it (presentation/road_paint.gd),
# the warm dark-fantasy palette regrade the docs/30 art decision asked for, and the rubble
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
#   5. the palette holds the warm dark-fantasy mood by property, and provably refuses the old
#      table;
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
		ok = _the_three_sockets_are_wired(stash) and ok
		ok = _rubble_is_placed_and_lawful(stash) and ok

	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	ok = _the_gate_stayed_inside_its_own_budget(seconds) and ok

	if ok:
		print("ROAD_LOOK_OK manifest true (exact on layout, worst dressed span %.2f over a %.2f floor), layout untouched, paint on streets only, centre line centred on %d fixture spans with %d lanes a side and the old placement refused, the shipped %d district carries %d centred dashes at width %d, variation hashed not drawn, palette propertied with the old table refused, the ground atlas %d cells each averaging its palette tint with a flat cell and a bright cell refused, floors blit their cell at zoom %.0f and up with no grid, mask/speed/tint sockets wired, %d rubble tiles lawful; %.1f s of a %.0f s budget" % [
			float(stash.get("worst_span", 0.0)), SPAN_PAVED_FLOOR, int(stash.get("centred_spans", 0)), LANE_MIN, PLAYED_SIZE, int(stash.get("played_dashes", 0)), int(stash.get("played_width", 0)), int(stash.get("atlas_cells", 0)), Palette.GROUND_TEXTURE_MIN_ZOOM, int(stash.get("rubble", 0)), seconds, BUDGET_SECONDS,
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

# Properties, not hexes, so the owner can tune by screenshot inside the bounds and a revert to
# the pre-regrade table is caught mechanically. One deliberate divergence from the slice spec's
# sketch: the sketch floored *pairwise V-distance* at 0.02, but the authored table separates
# dirt, grass and undergrowth by hue at near-equal value -- warm and low-key, on purpose -- so
# the distinctness floor is on RGB distance instead, which still reds two-identical tints and
# does not outlaw the mood the regrade exists to hit. The mood itself is warmth held by
# property too: a cool near-black dark around a warm-lit district, so WARM_MARGIN pins r - b (or
# b - r for the dark) rather than a hue pin that would refuse every tune inside the mood along
# with every one outside it.
const PAIR_DISTANCE_MIN: float = 0.02
const WARM_MARGIN: float = 0.02

# The district's own surfaces, walls, props and screen marks -- everything the warm-lit street
# is built from. Judged with _warm_ok (r - b >= WARM_MARGIN), together with all five ground
# tints in Palette.SURFACE_TINTS below.
const WARM_FAMILY: Array[String] = [
	"sidewalk", "kerb", "threshold", "indoorFloor", "wall", "roadPaint", "prop", "low",
	"screen", "tree", "groundItem", "glimpse", "memory",
]
# The dark the district sits inside: the night, the background behind it, and the one district
# surface meant to read as glass rather than as ground. Judged with _cool_ok (b - r >=
# WARM_MARGIN).
const COOL_FAMILY: Array[String] = ["background", "night", "window", "windowRim"]

# The five ground tints, named to match Palette.SURFACE_TINTS' order, for the warm-family print
# below -- SURFACE_TINTS itself carries no names, only an index.
const SURFACE_NAMES: Array[String] = ["floor", "dirt", "grass", "undergrowth", "rubble"]

func _sat_ok(c: Color) -> bool:
	return c.s <= 0.30


func _paved_value_ok(c: Color) -> bool:
	return c.v >= 0.20 and c.v <= 0.40


func _warm_ok(c: Color) -> bool:
	return c.r - c.b >= WARM_MARGIN


func _cool_ok(c: Color) -> bool:
	return c.b - c.r >= WARM_MARGIN


func _rgb_distance(a: Color, b: Color) -> float:
	return sqrt(pow(a.r - b.r, 2.0) + pow(a.g - b.g, 2.0) + pow(a.b - b.b, 2.0))


func _the_palette_holds_the_mood_and_can_say_no() -> bool:
	for s in Palette.SURFACE_TINTS.size():
		if not _sat_ok(Palette.SURFACE_TINTS[s]):
			push_error("surface tint %d has saturation %.3f, over the 0.30 warm-mood cap" % [s, (Palette.SURFACE_TINTS[s] as Color).s])
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

	# Warmth and coolness, held the same way as saturation and value above: a measured margin,
	# not a hex pin, so a tune stays legal inside the mood and a creep toward neutral shows up in
	# the thinnest margin before it goes grey.
	var warm_min: float = INF
	var warm_min_key: String = ""
	for si in Palette.SURFACE_TINTS.size():
		var sc: Color = Palette.SURFACE_TINTS[si]
		var smargin: float = sc.r - sc.b
		if smargin < warm_min:
			warm_min = smargin
			warm_min_key = SURFACE_NAMES[si]
		if not _warm_ok(sc):
			push_error("ground %s has r - b = %.4f, under WARM_MARGIN %.2f; it has cooled out of the district" % [SURFACE_NAMES[si], smargin, WARM_MARGIN])
			return false
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

	# The built-in true negative: the exact table this regrade replaced must fail these
	# properties, or a quiet revert would pass the lane that exists to catch it. #1a1c1f is the
	# old floor (value 0.12, under the paved floor); #1b2a1b the old grass (saturation 0.36, over
	# the warm-mood cap); #3f4143 the old floor again, now judged for warmth; #2a1f18 a warm
	# background; #4a4a4a a neutral grey that must fail both family pins at once, at exactly zero.
	if _paved_value_ok(Color("#1a1c1f")):
		push_error("the old floor #1a1c1f passes the paved value band; a revert to the cave grade would not be caught")
		return false
	if _sat_ok(Color("#1b2a1b")):
		push_error("the old grass #1b2a1b passes the saturation cap; a revert to the saturated grade would not be caught")
		return false
	if _warm_ok(Color("#3f4143")):
		push_error("the old overcast floor #3f4143 passes the warm pin; the whole overcast table would slip back in on this one line")
		return false
	if _cool_ok(Color("#2a1f18")):
		push_error("a warm background #2a1f18 passes the cool pin; the dark would stop reading as dark")
		return false
	var neutral := Color("#4a4a4a")
	if _warm_ok(neutral) or _cool_ok(neutral):
		push_error("neutral grey #4a4a4a passes a family pin; the margin is a strict floor, not a sign test")
		return false

	print("PALETTE OK 5 surface tints under S 0.30, paved V %.2f in [0.20, 0.40], sidewalk > paved > background, roadPaint brightest of the family, pairwise RGB >= %.2f (min %.4f); warm family r-b >= %.2f (thinnest %s +%.4f), cool family b-r >= %.2f (thinnest %s +%.4f); the pre-regrade table refused throughout" % [
		paved.v, PAIR_DISTANCE_MIN, min_pair, WARM_MARGIN, warm_min_key, warm_min, WARM_MARGIN, cool_min_key, cool_min,
	])
	return true


# --- 6. the dead sockets ---------------------------------------------------------------------

# The rule this milestone paid for ten times: a resolver nothing calls is not a feature. (a) the
# draw loop reads the mask; (b) a placed rubble tile reaches the one sim mechanism that reads
# surfaces; (c) the rubble tint is resolved through the draw path's own resolver, not merely
# defined in the table.
# --- 6. the ground atlas ---------------------------------------------------------------------

# The atlas is the shape of a ground and the palette is still its colour. Each cell is judged on
# its decoded pixels against the tint its row was authored around: the mean within
# CELL_MEAN_MAX of the tint (so the modulated blit averages to the flat colour), the brightest
# pixel no more than CELL_BRIGHT_MAX luma over it (so palette.py's ground-contrast guards keep
# their clearance against the brightest pixel a body can stand on), and a variance that is not
# zero (a flat cell is a texture in name only). The predicate is one function so the fabricated
# negatives below refuse through the same code the real cells pass through.
const CELL_MEAN_MAX: float = 0.03
const CELL_BRIGHT_MAX: float = 0.06


func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


# "" when the n x n cell at (x0, y0) is a lawful picture of `tint`, else what is wrong with it.
func _cell_problem(img: Image, x0: int, y0: int, n: int, tint: Color) -> String:
	var sum: Vector3 = Vector3.ZERO
	var brightest: float = 0.0
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
			brightest = maxf(brightest, _luma(c))
	var count: float = float(n * n)
	var mean: Vector3 = sum / count
	if not textured:
		return "flat -- every pixel the same colour, a texture in name only"
	var d: float = Vector3(tint.r, tint.g, tint.b).distance_to(mean)
	if d > CELL_MEAN_MAX:
		return "mean (%.3f, %.3f, %.3f) sits %.3f from its tint %s, over %.2f" % [mean.x, mean.y, mean.z, d, tint.to_html(false), CELL_MEAN_MAX]
	if brightest > _luma(tint) + CELL_BRIGHT_MAX:
		return "brightest pixel luma %.3f is %.3f over the tint's %.3f, past %.2f" % [brightest, brightest - _luma(tint), _luma(tint), CELL_BRIGHT_MAX]
	return ""


func _the_ground_is_a_texture_whose_mean_is_the_palette(stash: Dictionary) -> bool:
	Appearance.forget()
	var atlas: Texture2D = Appearance.ground_atlas()
	if atlas == null:
		push_error("no %s.png resolves; the floors have no picture to blit" % Appearance.GROUND_ATLAS_KEY)
		return false
	var n: int = int(CameraUtil.ART_NATIVE)
	var want: Vector2i = Appearance.canvas_of(Appearance.GROUND_ATLAS_KEY)
	if Vector2i(atlas.get_size()) != want:
		push_error("the atlas is %s, its canvas is %s (%d variants x %d rows of %d px)" % [str(atlas.get_size()), str(want), Appearance.GROUND_VARIANTS, Appearance.GROUND_ROWS, n])
		return false
	var img: Image = atlas.get_image()
	if img == null:
		push_error("the atlas texture yields no image to judge")
		return false
	var judged: int = 0
	for row in Appearance.GROUND_ROWS:
		var tint: Color = Appearance.ground_row_tint(row)
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
		for a in cells.size():
			for b in range(a + 1, cells.size()):
				if cells[a] == cells[b]:
					push_error("atlas row %d: variants %d and %d are the same pixels; four names for one picture" % [row, a, b])
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
	# brighter than its tint must both be refused, or a dead atlas would pass the lane above.
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
	stash["atlas_cells"] = judged
	print("TEXTURE OK %s is %dx%d: %d cells, every one averaging within %.2f of its row tint with no pixel over %.2f luma above it and none flat, %d variants a row pixel-distinct; the flat cell and the brightened cell both refused" % [
		Appearance.GROUND_ATLAS_KEY, want.x, want.y, judged, CELL_MEAN_MAX, CELL_BRIGHT_MAX, Appearance.GROUND_VARIANTS,
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
