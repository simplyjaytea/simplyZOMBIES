extends SceneTree
# The ground and road dressing: the street manifest the generator now carves alongside its
# streets (`map.streets`), the draw-time paint resolved from it (presentation/road_paint.gd),
# the overcast palette regrade the docs/30 art decision asked for, and the rubble pass -- the
# tenth worldgen pass, closing the "rubble is never placed" debt entry. Seven lanes, every
# assertion with a true positive and a true negative, because a gate that cannot fail is worse
# than no gate:
#
#   1. the manifest tells the truth -- exactly, on the pure layout; by a measured majority, on
#      the finished map the annex stamp and the terrain pass have legitimately worn through;
#   2. the manifest and the rubble pass moved no layout -- dress=false is deterministic,
#      manifest included, and the dressing appends nothing to it;
#   3. paint lands on streets and nowhere else, junctions read worn, narrow streets get kerbs
#      only, and a map with no manifest draws nothing;
#   4. the ground variation is deterministic and alive -- a hash, deliberately not a stream;
#   5. the palette holds the overcast mood by property, and provably refuses the old table;
#   6. the three dead sockets are wired: the draw loop reads the mask, the one mechanism that
#      reads surfaces reads a placed rubble tile, and the rubble tint is resolved, not defined;
#   7. rubble is placed, dressing-only, and only ever on outdoor open Floor (the `_footing`
#      trap: rubble under a Low wreck would silently delete walkability).
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
const ContentLoader = preload("res://platform/content_loader.gd")

const CANON_SEED: int = 20260805
const OTHER_SEED: int = 404
const GATE_SIZE: int = 64
const MAIN_GD: String = "res://presentation/main.gd"

# The in-gate fixture district: blocks of exactly 8 so `_fit_scale` leaves the declared
# streetWidth 6 unscaled at 64 (usable 50, four blocks fit), which is what puts sidewalks and
# dashes on a 64-tile boot -- the shipped suburb scales to width 2 there and correctly gets
# kerbs only, so the wide positives need this fixture rather than a 256 generation.
const FIXTURE_ID: String = "district.fixture.road_wide"

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
		ok = _variation_is_deterministic_and_alive() and ok
		ok = _the_palette_holds_the_mood_and_can_say_no() and ok
		ok = _the_three_sockets_are_wired(stash) and ok
		ok = _rubble_is_placed_and_lawful(stash) and ok

	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	ok = _the_gate_stayed_inside_its_own_budget(seconds) and ok

	if ok:
		print("ROAD_LOOK_OK manifest true (exact on layout, worst dressed span %.2f over a %.2f floor), layout untouched, paint on streets only, variation hashed not drawn, palette propertied with the old table refused, mask/speed/tint sockets wired, %d rubble tiles lawful; %.1f s of a %.0f s budget" % [
			float(stash.get("worst_span", 0.0)), SPAN_PAVED_FLOOR, int(stash.get("rubble", 0)), seconds, BUDGET_SECONDS,
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
		"streets": {"blockMin": 8, "blockMax": 8, "streetWidth": 6},
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
	stash["fixture"] = SimWorldgen.generate(CANON_SEED, GATE_SIZE, _tree_with_fixture(), FIXTURE_ID)
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
		push_error("the width-6 fixture resolved %d dashes and %d sidewalk cells; wide streets are not being marked" % [int(counts["dash"]), int(counts["sidewalk"])])
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
# dirt, grass and undergrowth by hue at near-equal value -- muted overcast, on purpose -- so the
# distinctness floor is on RGB distance instead, which still reds two-identical tints and does
# not outlaw the mood the regrade exists to hit.
const PAIR_DISTANCE_MIN: float = 0.02

func _sat_ok(c: Color) -> bool:
	return c.s <= 0.25


func _paved_value_ok(c: Color) -> bool:
	return c.v >= 0.20 and c.v <= 0.40


func _rgb_distance(a: Color, b: Color) -> float:
	return sqrt(pow(a.r - b.r, 2.0) + pow(a.g - b.g, 2.0) + pow(a.b - b.b, 2.0))


func _the_palette_holds_the_mood_and_can_say_no() -> bool:
	for s in Palette.SURFACE_TINTS.size():
		if not _sat_ok(Palette.SURFACE_TINTS[s]):
			push_error("surface tint %d has saturation %.3f, over the 0.25 overcast cap" % [s, (Palette.SURFACE_TINTS[s] as Color).s])
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
	for a in Palette.SURFACE_TINTS.size():
		for b in range(a + 1, Palette.SURFACE_TINTS.size()):
			var d: float = _rgb_distance(Palette.SURFACE_TINTS[a], Palette.SURFACE_TINTS[b])
			if d < PAIR_DISTANCE_MIN:
				push_error("surface tints %d and %d sit %.4f apart in RGB; two grounds you cannot tell apart are one ground" % [a, b, d])
				return false

	# The built-in true negative: the exact table this regrade replaced must fail these
	# properties, or a quiet revert would pass the lane that exists to catch it. #1a1c1f is the
	# old floor (value 0.12, under the paved floor); #1b2a1b the old grass (saturation 0.36,
	# over the overcast cap).
	if _paved_value_ok(Color("#1a1c1f")):
		push_error("the old floor #1a1c1f passes the paved value band; a revert to the cave grade would not be caught")
		return false
	if _sat_ok(Color("#1b2a1b")):
		push_error("the old grass #1b2a1b passes the saturation cap; a revert to the saturated grade would not be caught")
		return false

	print("PALETTE OK 5 surface tints under S 0.25, paved V %.2f in [0.20, 0.40], sidewalk > paved > background, roadPaint brightest of the family, pairwise RGB >= %.2f; the pre-regrade floor and grass both refused" % [
		paved.v, PAIR_DISTANCE_MIN,
	])
	return true


# --- 6. the dead sockets ---------------------------------------------------------------------

# The rule this milestone paid for ten times: a resolver nothing calls is not a feature. (a) the
# draw loop reads the mask; (b) a placed rubble tile reaches the one sim mechanism that reads
# surfaces; (c) the rubble tint is resolved through the draw path's own resolver, not merely
# defined in the table.
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
