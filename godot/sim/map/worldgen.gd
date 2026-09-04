class_name SimWorldgen
extends RefCounted

# The district generator. docs/24's "authored templates, procedurally assembled", built for real:
# the buildings are designed (content/buildings/*.json), the world is rolled, and *what kind of
# world* is a data entry too (content/districts/*.json).
#
# What replaced what. The old `SimTileMap.generate_district` was a fixed block=64 / street=12
# lattice with one hollow room per block: nine buildings at 256 where docs/24 asks for 40-70, and
# **zero** at 64, which is the size every gate but check_loot boots -- so every band in this repo
# was measured on a map with no buildings in it. It also carried three magic XOR salts where
# docs/30 asks for named derivations.
#
# The pipeline, in order. Each pass has its own named stream, and passes 1-7 (the layout) draw
# from none of the dressing streams -- so turning the dressing off leaves the layout byte-identical,
# which is the property docs/30 already recorded for the occluder pass, under new names. It is
# asserted rather than asserted-by-comment: check_m2_district.gd's dressing-independence lane.
#
#   1. border            -- the district wall
#   2. worldgen.streets  -- an irregular grid, plus a ring road, terminating at the district's
#                           declared connection points (the M3B road seam, made live)
#   3. worldgen.parcels  -- blocks split into lots
#   4. worldgen.annex    -- where the colony stands: lots ranked, the winner stamped and reserved
#   5. worldgen.buildings-- a weighted pick per lot from the district's pool, thinned by density
#   6. worldgen.vehicles -- the cars left in the carriageway, from the district's `vehicles` block
#   7. worldgen.sites    -- where the loot is, from the district's lootProfile: interiors first,
#                           the odd car boot on a driveway, the rare tables once per district
#   8. (survivability)   -- docs/01's fairness rule, judged; a district that fails re-sites the
#                           annex on the next-ranked lot and runs 4-7 again
#   9. worldgen.occluders-- windows, screening, wrecks
#  10. worldgen.terrain  -- lawns, stands of trees, thickets, the trodden edge of a green
#  11. worldgen.rubble   -- the decay: aprons of broken slab round the buildings, blobs on open
#                           ground, patches heaved up through the street
#
# Sites are **layout, not dressing**: they are chosen before a tree is planted, they are the same
# with the dressing switched off, and the dressing is then forbidden to plant anything on one
# (`_protected_tiles` carries them). A car boot that a stand of trees had grown over would be loot
# standing inside a solid tile, which is the one thing check_loot.gd's standing lane exists to
# reject.
#
# Generation is a pure function of (seed, size, content, district) and runs before a world exists,
# so the RNG stays off the world registry (docs/30) -- but the salts are `RngStream.derive_seed`
# now, one stream per pass, so adding a draw to the dressing cannot move a building.

const RngStream = preload("res://sim/rng_stream.gd")
const SimTileMapRes = preload("res://sim/map/tilemap.gd")
const SimTemplatesRes = preload("res://sim/map/templates.gd")
const SimPathRes = preload("res://sim/path.gd")
const ContentLoaderRes = preload("res://platform/content_loader.gd")

const DEFAULT_DISTRICT: String = "district.residential_suburb"

# The colony's own template, and the one place its id is written. It is a map patch rather than a
# `content/buildings/` entry -- authored at a district's scale, carrying the four anchors and its
# own two loot rows -- but it stamps through the same `SimTemplates.stamp` a house does.
const ANNEX_PATCH_ID: String = "map.district.alpha"

# One tile of clear ground around the sited annex, so the colony always has a way out even when the
# lot next door is built up. The dressing keeps two (`_protected_tiles`), because a tree at arm's
# length from the wall is a tree somebody has to walk around and a thicket against it is a wall.
const RESERVE_MARGIN: int = 1

# How far the colony keeps off the district wall, authored for a full 256 m district and scaled to
# the map the way the blocks are -- 24 at 256, 6 at the gate's 64, and below the floor at 32, where
# the annex plus its ring simply does not fit and the district gets no colony at all.
#
# The number is `SimDirector.GATE_EXCLUSION` reasoned about rather than picked. The director refuses
# to spawn a night packet within 32 m of either gate, and it draws those packets from a three-tile
# band inside each district wall: an annex shoved against a wall puts that whole band inside the
# disc, and the side stops being an approach. At 256 a 24-tile margin keeps the gate ~30 tiles off
# the nearest wall and every side keeps a pool. At 64 no margin can hold 32 m off four walls of a
# 64-tile map -- the disc is bigger than the district -- so the margin there is the pragmatic one
# that keeps the annex whole, off the ring road, and central enough that each wall keeps a run of
# legal tiles outside the disc. check_m2_district.gd's siting lane measures exactly that, per side,
# rather than trusting this paragraph.
const ANNEX_BORDER_FULL: int = 24
const ANNEX_BORDER_MIN: int = 3

# `SimBoot.place_stations` wants a campfire and two beds on indoor floor inside the annex, and
# docs/01's fairness rule is that a generated start is *survivable* -- so a colony with nowhere to
# put the fire is an unwinnable start rather than a cramped one.
const STATION_TILES: int = 6

# A road leaving the district is three tiles of opening in the wall. Narrower than most streets on
# purpose: the wall is the district's edge, and a gap you can see the far side of is a landmark.
const OPENING_WIDTH: int = 3

# Lot sizing. A lot is split off a block until it is about PARCEL_TARGET on a side, and never
# below MIN_PARCEL -- which is the smallest lot the smallest shed still fits on with a tile of
# ground around it. Blocks that come up short stay whole, which is what puts the occasional big
# lot in a suburb and gives the retail footprints somewhere to stand.
const MIN_PARCEL: int = 12
const PARCEL_TARGET: int = 20
const PARCEL_JITTER: int = 2
# The smallest block worth carving out. Below this there is no lot a shed fits on.
const MIN_BLOCK: int = 8

# A district is 256 m (docs/24), and the gates boot 64 for speed. A map that small is a *model* of
# a district rather than a quarter of one: if a district's declared blocks would not fit a street
# grid on it, the blocks and the street shrink until they do. Without this a 64-tile map is simply
# a sixteenth of the shipped one -- four blocks and a ring road -- and a building count that holds
# at 256 puts two or three on it.
#
# Only districts that need it are scaled. A town centre's blocks are 12-20 and already fit three
# to an axis at 64, so it generates at its authored size; a suburb's 24-40 do not, and it does.
#
# The floor is what stops the scaling going somewhere silly: the footprints are authored and do
# not shrink, so past a point a block holds nothing but a shed, and a district of sheds is not a
# district.
const BLOCKS_PER_AXIS_MIN: int = 4
const SCALE_FLOOR: float = 0.32
# Every building keeps this much clear ground inside its own lot, on all four sides. It is what
# makes the space between buildings walkable without a pathfinder having to prove it: lot
# boundaries are always open, so the ring around any building reaches the street.
const BUILDING_INSET: int = 1

# Parking. A car is 2 tiles across and must keep a kerb row free on each side of it, so the
# narrowest street it fits in is four tiles wide -- the usable lane offsets for a 2-wide body on a
# span of `width` are 1..width-3, which is empty below four. Measured on seed 20260805, that is
# what keeps the town centre (streets 2/3/3 at 64/128/256) and the forest edge (2/2/3) empty and
# the suburb (2/5/7) parked at 128 and 256 but not at the 64 every gate boots.
const VEHICLE_MIN_WIDTH: int = 4
# How often a slot comes up along a span: a sedan is five tiles long, so eight leaves three tiles
# of gap between two parked bumper to bumper. Slots are walked whatever the street's width, and
# every one of them draws the same four times -- see `_vehicles`.
const VEHICLE_SLOT: int = 8


# --- entry points ---------------------------------------------------------------------------

# The whole pipeline. `content` is a loaded content tree ({path: entry}); hand it the one the
# caller already has rather than making this walk the directory again (`load_tree` is a full
# directory walk, and this is called once per campaign seed by the balance harness).
#
# `dress` exists for the layout/dressing independence property: with it false, passes 8 and 9 do
# not run and the map carries layout only -- the same buildings, on the same lots, holding the same
# loot sites, with the colony on the same lot. Nothing in the game turns it off; it is what lets a
# gate assert that the dressing streams cannot move a wall or a cupboard.
#
# `reject` is a test hook and says so. The re-site loop below advances to the next-ranked lot when a
# district comes out unsurvivable, and no shipped seed yet makes the first-ranked lot fail -- so
# without a way to refuse one from outside, the loop would be code nothing has ever run.
# check_m2_district.gd's re-site lane hands it a predicate that refuses the top candidate and
# asserts the second is taken; the game passes nothing and gets the empty Callable.
static func generate(seed_val: int, size: int = SimTileMapRes.DISTRICT_TILES, content: Variant = null, district_id: String = DEFAULT_DISTRICT, dress: bool = true, reject: Callable = Callable()) -> Variant:
	var tree: Dictionary = content as Dictionary if content is Dictionary else ContentLoaderRes.load_tree()
	var district: Dictionary = district_of(tree, district_id)
	var templates: Array = templates_of(tree)
	var vehicles: Array = vehicles_of(tree)
	var patch: Variant = annex_template_of(tree)
	var footprint: Vector2i = SimTemplatesRes.footprint(patch as Dictionary) if patch is Dictionary else Vector2i.ZERO

	# One attempt is the whole district downstream of the layout: the colony stamped on one lot, the
	# buildings that fit around it, the loot they hold, and the verdict on all three. The layout
	# itself is re-run rather than copied -- it is a pure function of (seed, size, district), so
	# every attempt regenerates the identical streets and lots, and a tilemap has no deep copy that
	# would be cheaper to trust.
	var ground: Dictionary = {}
	var map: Variant = null
	var candidates: Array = []
	var reserve: Rect2i = Rect2i(0, 0, 0, 0)
	var report: Dictionary = {}
	var attempt: int = 0
	while true:
		ground = layout(seed_val, size, district)
		map = ground["map"]
		var parcels: Array = ground["parcels"] as Array
		if attempt == 0:
			candidates = annex_candidates(seed_val, map, parcels, footprint)
		reserve = Rect2i(0, 0, 0, 0)
		if attempt < candidates.size():
			reserve = candidates[attempt] as Rect2i
			SimTemplatesRes.stamp(map, patch as Dictionary, reserve.position.x, reserve.position.y)
		var placed: Array = _buildings(map, seed_val, district, templates, parcels, reserve)
		map.buildings = placed
		# Before the loot and after the buildings; `_vehicles` says why both halves matter.
		_vehicles(map, seed_val, district, vehicles, reserve)
		_sites(map, seed_val, district, templates, placed, reserve)
		report = survivability_report(map)
		var refused: bool = not bool(report["ok"])
		if not refused and not reject.is_null():
			refused = bool(reject.call(reserve))
		if not refused:
			break
		if attempt + 1 >= candidates.size():
			# Loud, not silent, and the last candidate is kept: a district that can site no
			# survivable colony anywhere is a content bug -- a pool of sealed footprints, a profile
			# whose only table lives behind a locked door -- and shipping it quietly would put a
			# player on a start docs/01 says may not exist. The gate is what turns this into red.
			if not candidates.is_empty():
				push_error("worldgen: %s at %d sited no survivable colony on any of its %d candidate lots; keeping %s, which failed %s" % [
					district_id, size, candidates.size(), str(reserve), str(report.get("failed", [])),
				])
			break
		attempt += 1

	if dress:
		# Read back off the map rather than out of the local: the manifest is the thing the loot
		# slice will walk, and a pass that reads it here is what keeps it honest in the meantime.
		var protected: Dictionary = _protected_tiles(map, reserve)
		_dress_occluders(map, seed_val, protected)
		var terrain: Dictionary = _terrain_of(district)
		_dress_terrain(map, seed_val, ground["streets"] as Dictionary, protected, terrain)
		_rubble(map, seed_val, ground["streets"] as Dictionary, protected)
		if bool(terrain["paths"]):
			_paths(map, seed_val, protected)
		# The siting decision is made on the layout, because the layout is what the dressing is
		# forbidden to depend on: a colony sited off the trees would move when the trees were
		# switched off, and the dressing-independence property (docs/30) would stop being true. So
		# the finished map is asked the same question a second time, and a clause that was true
		# before the trees went in and false after is a *dressing* bug -- something planted across
		# the last route to a cupboard -- which is why it says so here rather than re-siting.
		var after: Dictionary = survivability_report(map)
		if bool(report["ok"]) and not bool(after["ok"]):
			push_error("worldgen: the dressing broke %s on a district that was survivable without it (seed %d, %s at %d)" % [
				str(after["failed"]), seed_val, district_id, size,
			])
	return map


# Passes 1-3: the district wall, the streets, the lots. Split out because the siting pass has to be
# handed the same ground the generator gives it -- a gate that wants to rank the candidate lots
# itself, or to know which one the generator picked, rebuilds this and gets the identical map.
static func layout(seed_val: int, size: int, district: Dictionary) -> Dictionary:
	var map: Variant = SimTileMapRes.blank_map(size, size)
	_border(map)
	var streets: Dictionary = _streets(map, seed_val, district)
	var parcels: Array = _parcels(seed_val, streets)
	return {"map": map, "streets": streets, "parcels": parcels}


# The colony's template out of a content tree. Absent is loud: every district in the game is a
# district somebody lives in, and one generated without the annex would boot a world with no
# anchors, no stations and no gate -- which reads downstream as "an old fixture map" rather than as
# the content bug it is.
static func annex_template_of(tree: Dictionary) -> Variant:
	var patch: Variant = SimTileMapRes.load_patch_from_content(tree, ANNEX_PATCH_ID)
	if not (patch is Dictionary):
		push_error("worldgen: no %s in content, so no district can be given a colony" % ANNEX_PATCH_ID)
		return null
	return patch


# Every district type in a content tree, by id. Missing means the caller named one nobody wrote,
# which is loud rather than silent: a default district would generate a world that is not the one
# the run asked for and nothing downstream would ever say so.
static func district_of(tree: Dictionary, district_id: String) -> Dictionary:
	for path in _sorted_keys(tree):
		if not path.begins_with("districts/"):
			continue
		var entry: Variant = tree[path]
		if entry is Dictionary and String((entry as Dictionary).get("id", "")) == district_id:
			return entry as Dictionary
	push_error("worldgen: no district %s in content" % district_id)
	return {}


# The building pool, sorted by id so the placer's draw order never depends on directory order.
static func templates_of(tree: Dictionary) -> Array:
	var out: Array = []
	for path in _sorted_keys(tree):
		if not path.begins_with("buildings/"):
			continue
		var entry: Variant = tree[path]
		if entry is Dictionary:
			out.append(entry as Dictionary)
	out.sort_custom(func(a, b): return String(a.get("id", "")) < String(b.get("id", "")))
	return out


# The vehicle classes a content tree declares, sorted by id for the same reason the building pool
# is: nothing this generator draws may depend on directory order. Which of them a district parks
# is the district's own `vehicles.classes` list, not this -- this is only what exists to be named.
static func vehicles_of(tree: Dictionary) -> Array:
	var out: Array = []
	for path in _sorted_keys(tree):
		if not path.begins_with("vehicles/"):
			continue
		var entry: Variant = tree[path]
		if entry is Dictionary:
			out.append(entry as Dictionary)
	out.sort_custom(func(a, b): return String(a.get("id", "")) < String(b.get("id", "")))
	return out


static func _sorted_keys(tree: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for k in tree.keys():
		keys.append(String(k))
	keys.sort()
	return keys


static func _stream(seed_val: int, pass_name: String) -> Variant:
	return RngStream.new(RngStream.derive_seed(seed_val, "worldgen.%s" % pass_name))


# --- 1. the border --------------------------------------------------------------------------

static func _border(map: Variant) -> void:
	var size_w: int = int(map.w)
	var size_h: int = int(map.h)
	SimTileMapRes._fill(map, 0, 0, size_w, 1, SimTileMapRes.Tile.Wall)
	SimTileMapRes._fill(map, 0, size_h - 1, size_w, 1, SimTileMapRes.Tile.Wall)
	SimTileMapRes._fill(map, 0, 0, 1, size_h, SimTileMapRes.Tile.Wall)
	SimTileMapRes._fill(map, size_w - 1, 0, 1, size_h, SimTileMapRes.Tile.Wall)


# --- 2. the street skeleton -----------------------------------------------------------------

# Returns {x_streets, y_streets, x_blocks, y_blocks, openings}, all Arrays of plain records, which
# passes 3 and 7 read. Blocks are what is left between streets; the ring road hugs the wall, so
# the tiles the director spawns on stay open on all four sides and every connection point has a
# street waiting on the other side of the wall.
# Which ground a district's streets are laid on. `paved` unless the district says otherwise, so
# every district that existed before this read stays exactly as it was; an unknown name is paved
# too rather than an error, because a street is a street and a typo should not make one vanish.
# The name is content's, the int is the sim's -- SURFACE_* is not an enum content may spell.
const STREET_SURFACES: Dictionary = {
	"paved": SimTileMapRes.SURFACE_PAVED,
	"dirt": SimTileMapRes.SURFACE_DIRT,
}


static func street_surface_of(district: Dictionary) -> int:
	var spec: Variant = district.get("streets")
	if not (spec is Dictionary):
		return SimTileMapRes.SURFACE_PAVED
	var name: String = String((spec as Dictionary).get("surface", "paved"))
	return int(STREET_SURFACES.get(name, SimTileMapRes.SURFACE_PAVED))


# What surface this map's streets were laid on, read back off the manifest the carving wrote.
# Read off the map rather than passed down: `annex_candidates` and `_street_frontage` are called
# by gates with the arguments they have always had, and one answer living on the map cannot
# disagree with a second one threaded through five call sites. A map with no manifest -- a hand
# built fixture -- reads paved, which is what every map was before districts could say otherwise.
static func street_surface_on(map: Variant) -> int:
	if map == null or map.get("streets") == null:
		return SimTileMapRes.SURFACE_PAVED
	for street in map.streets as Array:
		if street is Dictionary and (street as Dictionary).has("surface"):
			return int((street as Dictionary)["surface"])
	return SimTileMapRes.SURFACE_PAVED


static func _streets(map: Variant, seed_val: int, district: Dictionary) -> Dictionary:
	var rng: Variant = _stream(seed_val, "streets")
	var spec: Dictionary = district.get("streets", {}) as Dictionary
	var surface: int = street_surface_of(district)
	var declared_min: int = maxi(MIN_BLOCK, int(spec.get("blockMin", 24)))
	var declared_max: int = maxi(declared_min, int(spec.get("blockMax", 40)))
	var declared_width: int = maxi(2, int(spec.get("streetWidth", 6)))
	var scale: float = _fit_scale(mini(int(map.w), int(map.h)), declared_min, declared_max, declared_width)
	var block_min: int = clampi(int(round(float(declared_min) * scale)), MIN_BLOCK, declared_min)
	var block_max: int = clampi(int(round(float(declared_max) * scale)), block_min, declared_max)
	var width: int = clampi(int(round(float(declared_width) * scale)), 2, declared_width)

	var x_axis: Dictionary = _axis(rng, int(map.w), block_min, block_max, width)
	var y_axis: Dictionary = _axis(rng, int(map.h), block_min, block_max, width)

	# Vertical streets first, then horizontal, so the paved surface under a crossing is written
	# twice and identically -- order matters only for reproducibility, and this is the order.
	# Each carve appends its record to `map.streets` in the same order: the manifest is a
	# transcript of the carving, not a second decision, so it costs no draw and moves no tile.
	for span in x_axis["streets"] as Array:
		_carve_street(map, int((span as Array)[0]), 1, int((span as Array)[1]), int(map.h) - 2, surface)
		map.streets.append({"axis": "x", "at": int((span as Array)[0]), "width": int((span as Array)[1]), "from": 1, "to": int(map.h) - 2, "surface": surface})
	for span in y_axis["streets"] as Array:
		_carve_street(map, 1, int((span as Array)[0]), int(map.w) - 2, int((span as Array)[1]), surface)
		map.streets.append({"axis": "y", "at": int((span as Array)[0]), "width": int((span as Array)[1]), "from": 1, "to": int(map.w) - 2, "surface": surface})

	_connection_points(map, rng, district, x_axis, y_axis, width)
	# Only the blocks: they are what passes 3 and 7 read. The street spans went onto the map as
	# `map.streets` above -- the road-paint pass (presentation/road_paint.gd) and
	# check_road_look.gd's manifest lane read them there -- and the openings stay tiles-only: the
	# gate reads openings off the tiles instead, which is the stronger question anyway, and paint
	# on the short run inside a wall opening would be paint the seam slice re-judges.
	return {"x_blocks": x_axis["blocks"], "y_blocks": y_axis["blocks"]}


# One axis of the grid: a ring street inside each wall, then blocks drawn from blockMin..blockMax
# with a street between them. Exactly one draw per block whatever branch it takes, so the number
# of draws depends on (size, district) and never on which way a comparison went.
static func _axis(rng: Variant, size: int, block_min: int, block_max: int, width: int) -> Dictionary:
	var streets: Array = []
	var blocks: Array = []
	var first: int = 1
	var last: int = size - 2
	var span: int = last - first + 1
	if span <= 0:
		return {"streets": streets, "blocks": blocks}
	if span < 2 * width + block_min:
		# Too small for a ring and a block both: the whole interior is street. This is the 16- and
		# 32-tile fixture maps, which exist to boot a world rather than to be a district.
		streets.append([first, span])
		return {"streets": streets, "blocks": blocks}

	streets.append([first, width])
	var far: int = last - width + 1
	streets.append([far, width])
	var cursor: int = first + width
	var guard: int = 0
	while cursor < far and guard < 256:
		guard += 1
		var room: int = far - cursor
		if room < MIN_BLOCK:
			break
		var block: int = int(rng.call("int_range", block_min, block_max))
		if block >= room:
			block = room
		else:
			var rest: int = room - block - width
			if rest < MIN_BLOCK:
				# A stub is worse than either alternative: swallow it if the whole remainder is
				# still a legal block, otherwise split the remainder down the middle.
				block = room if room <= block_max else maxi(MIN_BLOCK, (room - width) / 2)
		blocks.append([cursor, block])
		cursor += block
		if cursor >= far:
			break
		var w: int = mini(width, far - cursor)
		streets.append([cursor, w])
		cursor += w
	return {"streets": streets, "blocks": blocks}


# 1.0 when the district's own block sizes already put BLOCKS_PER_AXIS_MIN blocks on this map, and
# the fraction that would otherwise. Pure arithmetic on the declared numbers -- no draws, so the
# scale is the same on every seed and a band measured at one size stays a band.
static func _fit_scale(size: int, block_min: int, block_max: int, width: int) -> float:
	var usable: int = size - 2 - 2 * width
	if usable <= 0:
		return SCALE_FLOOR
	var average: int = (block_min + block_max) / 2
	var fits: int = (usable + width) / (average + width)
	if fits >= BLOCKS_PER_AXIS_MIN:
		return 1.0
	return clampf(float(usable + width) / float(BLOCKS_PER_AXIS_MIN * (average + width)), SCALE_FLOOR, 1.0)


static func _carve_street(map: Variant, x: int, y: int, w: int, h: int, surface: int = SimTileMapRes.SURFACE_PAVED) -> void:
	for j in h:
		for i in w:
			var tx: int = x + i
			var ty: int = y + j
			if tx <= 0 or ty <= 0 or tx >= int(map.w) - 1 or ty >= int(map.h) - 1:
				continue
			var idx: int = ty * int(map.w) + tx
			map.tiles[idx] = SimTileMapRes.Tile.Floor
			map.surfaces[idx] = surface


# docs/30: the arc ships the road seam "as district-JSON connection points the street pass must
# terminate at -- data something reads from day one, because a dead field named connectionPoints
# would be the tenth socket". So: every declared point becomes a three-wide opening in the
# district wall with paved ground running inward to the ring road. Milestone 3B joins them up
# between districts; here they are where the roads leave, and where anything walking a road
# arrives. The director's edge pool grows by them, which is the intended cost.
static func _connection_points(map: Variant, rng: Variant, district: Dictionary, x_axis: Dictionary, y_axis: Dictionary, width: int) -> void:
	var declared: Dictionary = district.get("connectionPoints", {}) as Dictionary
	# north/south run along x, east/west along y.
	for side in ["north", "south", "east", "west"]:
		var count: int = int(declared.get(side, 0))
		if count <= 0:
			continue
		var horizontal: bool = side == "north" or side == "south"
		var length: int = int(map.w) if horizontal else int(map.h)
		var tiers: Array = _opening_candidates(length, x_axis if horizontal else y_axis)
		var primary: Array = tiers[0] as Array
		var fallback: Array = tiers[1] as Array
		if primary.is_empty() and fallback.is_empty():
			push_error("worldgen: no room on the %s wall for a connection point" % side)
			continue
		for _i in count:
			var source: Array = primary if not primary.is_empty() else fallback
			if source.is_empty():
				push_error("worldgen: the %s wall ran out of room before its %d roads" % [side, count])
				break
			var pick: int = int(rng.call("int_range", 0, source.size() - 1))
			var at: int = int(source[pick])
			# Removed rather than re-rolled: two roads on the same tiles are one road, and the
			# district would quietly have fewer than it declares.
			primary = _apart_from(primary, at)
			fallback = _apart_from(fallback, at)
			_carve_opening(map, side, at, width, street_surface_of(district))


# Where a road could leave, in two tiers: the centre of a street, because a road that continues a
# street is a road; and, when the streets are used up, anywhere far enough from a corner.
#
# These used to be filtered by the annex reserve, which was a compile-time rect and at gate size
# reached the wall. The colony is sited per seed now, two passes later, so this pass cannot know
# where it will land -- and does not have to: the siting margin keeps the annex clear of the wall by
# more than the run of pavement an opening lays inward, and the survivability pass is what says so
# about the finished district rather than a filter here saying it about a guess.
static func _opening_candidates(length: int, axis: Dictionary) -> Array:
	var primary: Array = []
	var fallback: Array = []
	var seen: Dictionary = {}
	for span in axis["streets"] as Array:
		var at: int = int((span as Array)[0]) + int((span as Array)[1]) / 2
		if seen.has(at):
			continue
		seen[at] = true
		if _opening_fits(at, length):
			primary.append(at)
	for at2 in range(OPENING_WIDTH, length - OPENING_WIDTH, OPENING_WIDTH + 2):
		if seen.has(int(at2)):
			continue
		seen[int(at2)] = true
		if _opening_fits(int(at2), length):
			fallback.append(int(at2))
	return [primary, fallback]


static func _apart_from(candidates: Array, at: int) -> Array:
	var kept: Array = []
	for c in candidates:
		if absi(int(c) - at) > OPENING_WIDTH + 1:
			kept.append(int(c))
	return kept


static func _opening_fits(at: int, length: int) -> bool:
	var half: int = OPENING_WIDTH / 2
	return at - half >= 1 and at + half <= length - 2


# `step` counts inward from the wall: 0 is the wall itself, 1 the first tile inside it.
static func _opening_tile(map: Variant, side: String, along: int, step: int) -> Vector2i:
	match side:
		"north":
			return Vector2i(along, step)
		"south":
			return Vector2i(along, int(map.h) - 1 - step)
		"east":
			return Vector2i(int(map.w) - 1 - step, along)
		_:
			return Vector2i(step, along)


static func _carve_opening(map: Variant, side: String, at: int, width: int, surface: int = SimTileMapRes.SURFACE_PAVED) -> void:
	var half: int = OPENING_WIDTH / 2
	for step in range(0, width + 1):
		for offset in range(-half, half + 1):
			var tile: Vector2i = _opening_tile(map, side, at + offset, step)
			if tile.x < 0 or tile.y < 0 or tile.x >= int(map.w) or tile.y >= int(map.h):
				continue
			var idx: int = tile.y * int(map.w) + tile.x
			map.tiles[idx] = SimTileMapRes.Tile.Floor
			map.surfaces[idx] = surface


# --- 3. parcels -----------------------------------------------------------------------------

# Lots, as a flat Array of Rect2i in a fixed order (block row, block column, lot row, lot column).
# Nothing here touches the map: a lot is a decision about where a building may go, and pass 5 is
# what makes it visible.
static func _parcels(seed_val: int, streets: Dictionary) -> Array:
	var rng: Variant = _stream(seed_val, "parcels")
	var out: Array = []
	for yb in streets["y_blocks"] as Array:
		for xb in streets["x_blocks"] as Array:
			var xs: Array = _split_axis(rng, int((xb as Array)[0]), int((xb as Array)[1]))
			var ys: Array = _split_axis(rng, int((yb as Array)[0]), int((yb as Array)[1]))
			for ry in ys:
				for rx in xs:
					out.append(Rect2i(int((rx as Array)[0]), int((ry as Array)[0]), int((rx as Array)[1]), int((ry as Array)[1])))
	return out


static func _split_axis(rng: Variant, start: int, length: int) -> Array:
	var n: int = maxi(1, int(floor(float(length) / float(PARCEL_TARGET) + 0.5)))
	while n > 1 and length / n < MIN_PARCEL:
		n -= 1
	var cuts: Array[int] = []
	for i in range(1, n):
		var at: int = int(round(float(length) * float(i) / float(n)))
		# The jitter is drawn whether or not it survives the clamp below, so a block's draw count
		# depends on its length alone.
		var jitter: int = int(rng.call("int_range", -PARCEL_JITTER, PARCEL_JITTER))
		var floor_at: int = (cuts[cuts.size() - 1] if not cuts.is_empty() else 0) + MIN_PARCEL
		cuts.append(clampi(at + jitter, floor_at, length - MIN_PARCEL))
	var out: Array = []
	var at_last: int = 0
	for cut in cuts:
		out.append([start + at_last, cut - at_last])
		at_last = cut
	out.append([start + at_last, length - at_last])
	return out


# --- 4. siting the colony -------------------------------------------------------------------

# Where the annex could stand, best first. The rect this returns is both the stamp origin and the
# ground passes 5 and 6 then hold clear, which is what the fixed `ANNEX_RESERVE` used to be -- the
# difference is that it is a decision about this seed's lots rather than a constant two files
# agreed on.
#
# A candidate is one lot's answer to "if the colony went here, where exactly": the annex centred on
# the lot, then pulled back inside the legal band, which is the map minus the border margin minus
# the clear ring. Lots are much smaller than the annex at both shipped sizes -- 12..24 tiles a side
# against 26 -- so a candidate is a *position derived from* a lot rather than a lot the annex fits
# inside, and several lots can pull back to the same position, which is why they are deduplicated.
#
# The ordering, and it is the whole of the ordering:
#
#   1. street frontage, most first -- the count of paved tiles in the ring around the rect. A
#      colony on a junction is a colony you can leave in four directions, and it is what makes the
#      gate open onto a road rather than onto the back of somebody's garden.
#   2. centrality, nearest first -- Manhattan distance from the annex's centre to the district's.
#      This is the director's constraint made into a preference: a colony pushed against a wall
#      puts that wall's whole spawn band inside the 32 m gate exclusion and the side stops being an
#      approach (see ANNEX_BORDER_FULL).
#   3. the `worldgen.annex` stream, as a tie-break, so two equally good lots are not always the
#      same one; and finally the candidate's own ordinal, so the comparator is a total order and
#      the sort's instability cannot reach the result.
#
# Deterministic: parcels arrive as an Array in a fixed order, the draw happens once per distinct
# candidate whether or not it survives the frontage filter, and nothing here iterates a Dictionary.
static func annex_candidates(seed_val: int, map: Variant, parcels: Array, footprint: Vector2i) -> Array:
	var out: Array = []
	if footprint.x <= 0 or footprint.y <= 0:
		return out
	var w: int = int(map.w)
	var h: int = int(map.h)
	var margin: int = annex_border(mini(w, h))
	var lo := Vector2i(margin + RESERVE_MARGIN, margin + RESERVE_MARGIN)
	var hi := Vector2i(w - margin - RESERVE_MARGIN - footprint.x, h - margin - RESERVE_MARGIN - footprint.y)
	if hi.x < lo.x or hi.y < lo.y:
		# No room for the colony and its ring both. The 16- and 32-tile fixture maps, which exist to
		# boot a world rather than to be a district: they get no annex, no anchors, and
		# `SimBoot.colony_start`'s literal fallback, which is exactly what they got before.
		return out
	var rng: Variant = _stream(seed_val, "annex")
	var seen: Dictionary = {}
	var scored: Array = []
	var ordinal: int = 0
	for parcel in parcels:
		var lot: Rect2i = parcel as Rect2i
		var origin := Vector2i(
			clampi(lot.position.x + (lot.size.x - footprint.x) / 2, lo.x, hi.x),
			clampi(lot.position.y + (lot.size.y - footprint.y) / 2, lo.y, hi.y),
		)
		var key: int = origin.y * w + origin.x
		if seen.has(key):
			continue
		seen[key] = true
		# Drawn before the frontage is looked at, so the number of draws depends on the lots alone
		# and not on how much pavement any of them turned out to have.
		var toss: int = int(rng.call("int_range", 0, 1 << 20))
		var rect := Rect2i(origin, footprint)
		var fronting: int = _street_frontage(map, rect)
		ordinal += 1
		if fronting <= 0:
			continue
		scored.append({
			"rect": rect,
			"fronting": fronting,
			"centre": absi(2 * (origin.x + footprint.x / 2) - w) + absi(2 * (origin.y + footprint.y / 2) - h),
			"toss": toss,
			"at": ordinal,
		})
	scored.sort_custom(func(a, b) -> bool:
		var x: Dictionary = a as Dictionary
		var y: Dictionary = b as Dictionary
		if int(x["fronting"]) != int(y["fronting"]):
			return int(x["fronting"]) > int(y["fronting"])
		if int(x["centre"]) != int(y["centre"]):
			return int(x["centre"]) < int(y["centre"])
		if int(x["toss"]) != int(y["toss"]):
			return int(x["toss"]) < int(y["toss"])
		return int(x["at"]) < int(y["at"])
	)
	for entry in scored:
		out.append((entry as Dictionary)["rect"] as Rect2i)
	return out


# 24 at the shipped 256 and scaled to the map, the way `_fit_scale` scales the blocks -- with a
# floor, because past a point the margin is wider than the map and every position is illegal.
static func annex_border(size: int) -> int:
	return maxi(ANNEX_BORDER_MIN, int(round(float(ANNEX_BORDER_FULL) * float(size) / float(SimTileMapRes.DISTRICT_TILES))))


# Paved open ground in the one-tile ring around a rect: how much road this position fronts onto.
# How many tiles around a lot are street. It asks the map which surface its streets are, rather
# than assuming pavement: on a dirt district every street tile is SURFACE_DIRT, and a frontage
# test hunting for pavement would have answered "none" for every lot on it -- which
# `annex_candidates` reads as "this lot does not front a street" and skips. The colony would then
# have been sited only where a paved connection-point opening happened to reach, silently, with
# no gate red. Found by generating a dirt district, not by reading this function.
static func _street_frontage(map: Variant, rect: Rect2i) -> int:
	var n: int = 0
	var w: int = int(map.w)
	var h: int = int(map.h)
	var street: int = street_surface_on(map)
	for tx in range(rect.position.x - 1, rect.position.x + rect.size.x + 1):
		for ty in range(rect.position.y - 1, rect.position.y + rect.size.y + 1):
			if tx >= rect.position.x and tx < rect.position.x + rect.size.x \
					and ty >= rect.position.y and ty < rect.position.y + rect.size.y:
				continue
			if tx < 0 or ty < 0 or tx >= w or ty >= h:
				continue
			var idx: int = ty * w + tx
			if int(map.tiles[idx]) != SimTileMapRes.Tile.Floor:
				continue
			if int(map.surfaces[idx]) == street:
				n += 1
	return n


# `reserve` is the sited annex, or a zero rect on a district that got none. Zero reserves nothing,
# which is what "no colony here" has to mean -- a zero rect treated as a rect at the origin would
# hold the map's own corner clear for a colony that is not there.
static func _in_reserve(reserve: Rect2i, tx: int, ty: int, margin: int) -> bool:
	if reserve.size.x <= 0 or reserve.size.y <= 0:
		return false
	return tx >= reserve.position.x - margin \
			and ty >= reserve.position.y - margin \
			and tx < reserve.position.x + reserve.size.x + margin \
			and ty < reserve.position.y + reserve.size.y + margin


static func _rect_in_reserve(reserve: Rect2i, rect: Rect2i, margin: int) -> bool:
	if reserve.size.x <= 0 or reserve.size.y <= 0:
		return false
	return rect.position.x < reserve.position.x + reserve.size.x + margin \
			and rect.position.x + rect.size.x > reserve.position.x - margin \
			and rect.position.y < reserve.position.y + reserve.size.y + margin \
			and rect.position.y + rect.size.y > reserve.position.y - margin


# --- 5. the buildings -----------------------------------------------------------------------

# One weighted pick per lot, thinned by the district's density, stamped through the same
# `SimTemplates.stamp` the civic annex goes through -- one stamp path, not two.
#
# Returns the manifest: what landed where, with its doors in absolute tiles. The dressing passes
# read it (nothing solid is planted across a doorway) and check_m2_district.gd's enterability lane
# cross-checks it against the map's own indoor regions, so a manifest that lied would fail.
static func _buildings(map: Variant, seed_val: int, district: Dictionary, templates: Array, parcels: Array, reserve: Rect2i) -> Array:
	var rng: Variant = _stream(seed_val, "buildings")
	var density: float = clampf(float(district.get("density", 0.0)), 0.0, 1.0)
	var pool: Array = district.get("pool", []) as Array
	var by_tag: Dictionary = _by_tag(templates)
	var placed: Array = []
	for parcel in parcels:
		var lot: Rect2i = parcel as Rect2i
		if _rect_in_reserve(reserve, lot, RESERVE_MARGIN):
			continue
		if rng.call("next") >= density:
			continue
		var room: Vector2i = Vector2i(lot.size.x - 2 * BUILDING_INSET, lot.size.y - 2 * BUILDING_INSET)
		var tags: Array = []
		var weights: Array = []
		for entry in pool:
			var e: Dictionary = entry as Dictionary
			var tag: String = String(e.get("tag", ""))
			if _fitting(by_tag.get(tag, []) as Array, room).is_empty():
				continue
			tags.append(tag)
			weights.append(maxi(1, int(e.get("weight", 1))))
		if tags.is_empty():
			continue
		var tag_pick: String = String(tags[_weighted(rng, weights)])
		var fits: Array = _fitting(by_tag[tag_pick] as Array, room)
		var template_weights: Array = []
		for t in fits:
			template_weights.append(maxi(1, int((t as Dictionary).get("weight", 1))))
		var template: Dictionary = fits[_weighted(rng, template_weights)] as Dictionary
		var size: Dictionary = template.get("size", {}) as Dictionary
		var tw: int = int(size.get("w", 0))
		var th: int = int(size.get("h", 0))
		var ox: int = int(rng.call("int_range", lot.position.x + BUILDING_INSET, lot.position.x + lot.size.x - BUILDING_INSET - tw))
		var oy: int = int(rng.call("int_range", lot.position.y + BUILDING_INSET, lot.position.y + lot.size.y - BUILDING_INSET - th))
		SimTemplatesRes.stamp(map, template, ox, oy)
		var doors: Array = []
		for door in template.get("doors", []) as Array:
			var d: Dictionary = door as Dictionary
			doors.append({"x": ox + int(d.get("x", 0)), "y": oy + int(d.get("y", 0))})
		placed.append({
			"id": String(template.get("id", "")),
			"x": ox, "y": oy, "w": tw, "h": th,
			"doors": doors,
		})
	return placed


static func _by_tag(templates: Array) -> Dictionary:
	var out: Dictionary = {}
	for t in templates:
		for tag in (t as Dictionary).get("tags", []) as Array:
			var key: String = String(tag)
			if not out.has(key):
				out[key] = []
			(out[key] as Array).append(t)
	return out


# Which of a tag's templates fit the buildable room of a lot. A lot too small for anything in the
# pool is left empty rather than being given something that would overhang it.
static func _fitting(templates: Array, room: Vector2i) -> Array:
	var out: Array = []
	for t in templates:
		var size: Dictionary = (t as Dictionary).get("size", {}) as Dictionary
		if int(size.get("w", 0)) <= room.x and int(size.get("h", 0)) <= room.y:
			out.append(t)
	return out


static func _weighted(rng: Variant, weights: Array) -> int:
	var total: int = 0
	for w in weights:
		total += int(w)
	if total <= 0:
		return 0
	var roll: int = int(rng.call("int_range", 0, total - 1))
	for i in weights.size():
		roll -= int(weights[i])
		if roll < 0:
			return i
	return weights.size() - 1


# --- 6. parked vehicles ---------------------------------------------------------------------

# The cars left standing in the street, from the district's own `vehicles` block: how thickly they
# park and which classes do, both data, neither a branch in here. A district that declares no block
# parks none and draws nothing, which is what lets the two districts whose streets are too narrow
# for a car say so by omission rather than by a zero nobody could tell from a bug.
#
# Runs after the buildings and before the loot, and the order is load-bearing both ways. After the
# buildings, because `_protected_tiles` reads the building manifest and a car may not stand on a
# doorway. Before the loot, because a site written first would be a cupboard this pass could then
# bury under a car -- `_driveway_tiles` and `_interior_floors` both demand Tile.Floor, so running
# second is what makes the sites see the cars instead of the other way round.
#
# THE FOUR DRAWS ARE THE WHOLE DISCIPLINE. An RNG stream is a sequence, so a slot that drew a
# different number of times depending on which way a comparison went would move every decision
# after it -- the same trap the terrain block's dials are documented under. So every slot draws
# presence, class, lane side and facing, in that order, always, and only then is anything decided.
# Draw first, branch second; never `if x: rng.draw()`.
#
# Not drawn at all: a span narrower than VEHICLE_MIN_WIDTH is skipped whole and costs no draw,
# because a street's width is a property of the layout rather than of a roll. That is what keeps
# the 64-tile map every gate boots byte-identical to what it was before this pass existed -- at 64
# the suburb's streets come out two tiles wide, no span qualifies, and the stream is never touched.
static func _vehicles(map: Variant, seed_val: int, district: Dictionary, templates: Array, reserve: Rect2i) -> void:
	var spec: Variant = district.get("vehicles")
	if not (spec is Dictionary):
		return
	var density: float = clampf(float((spec as Dictionary).get("density", 0.0)), 0.0, 1.0)
	var by_id: Dictionary = {}
	for entry in templates:
		by_id[String((entry as Dictionary).get("id", ""))] = entry
	# The classes in the district's own order, so which one a weighted pick lands on depends on the
	# district's list and never on the content directory.
	var classes: Array = []
	var weights: Array = []
	for raw in (spec as Dictionary).get("classes", []) as Array:
		var declared: Dictionary = raw as Dictionary
		var id: String = String(declared.get("id", ""))
		var found: Variant = by_id.get(id)
		if not (found is Dictionary):
			# Loud rather than silent, the same way a missing district is: a class nobody wrote
			# would otherwise be a street that quietly never parks anything, and no gate looking at
			# the map could tell that from a district whose streets are all too narrow.
			push_error("worldgen: district %s parks %s, which no content/vehicles entry declares" % [
				String(district.get("id", "?")), id,
			])
			continue
		# The footprint is judged here rather than defaulted at the slot: the schema requires it but
		# the validator does not recurse, so a class that declares none would otherwise park a
		# silent sedan-shaped guess -- a wrong number nothing reports, which is the trap this
		# project keeps paying for. A class with no footprint parks nothing and says so.
		var footprint: Dictionary = (found as Dictionary).get("footprint", {}) as Dictionary
		if int(footprint.get("w", 0)) < 1 or int(footprint.get("l", 0)) < 1:
			push_error("worldgen: %s declares no usable footprint {w, l}, so nothing can be parked from it" % id)
			continue
		classes.append(found as Dictionary)
		weights.append(maxi(1, int(declared.get("weight", 1))))
	if classes.is_empty():
		return

	var surface: int = street_surface_of(district)
	var protected: Dictionary = _protected_tiles(map, reserve)
	var rng: Variant = _stream(seed_val, "vehicles")
	for street in map.streets as Array:
		if not (street is Dictionary):
			continue
		var span: Dictionary = street as Dictionary
		var width: int = int(span.get("width", 0))
		if width < VEHICLE_MIN_WIDTH:
			continue
		var vertical: bool = String(span.get("axis", "x")) == "x"
		var at: int = int(span.get("at", 0))
		var from: int = int(span.get("from", 0))
		var to: int = int(span.get("to", 0))
		for along in range(from, to + 1, VEHICLE_SLOT):
			var present: bool = float(rng.call("next")) < density
			var pick: int = _weighted(rng, weights)
			# The body sits inside the carriageway with a kerb row free on each side: offset 0 is
			# the near kerb and width-1 the far one, so a 2-wide car starts at 1..width-3.
			var lane: int = int(rng.call("int_range", 1, width - 3))
			var heading: int = int(rng.call("int_range", 0, 1))
			if not present:
				continue
			var shape: Dictionary = (classes[pick] as Dictionary)["footprint"] as Dictionary
			var breadth: int = int(shape["w"])
			var length: int = int(shape["l"])
			var rect := Rect2i(at + lane, along, breadth, length) if vertical else Rect2i(along, at + lane, length, breadth)
			# One picture per class x variant x axis (the owner's decision 11), so the record
			# carries which axis it stands on and which end is the nose, and nothing rotates.
			var axis: String = "ns" if vertical else "ew"
			var facing: String = ("n" if heading == 0 else "s") if vertical else ("e" if heading == 0 else "w")
			if not _vehicle_fits(map, rect, surface, protected, String(span.get("axis", "x"))):
				continue
			for ty in range(rect.position.y, rect.position.y + rect.size.y):
				for tx in range(rect.position.x, rect.position.x + rect.size.x):
					map.tiles[ty * int(map.w) + tx] = SimTileMapRes.Tile.Low
			map.vehicles.append({
				"x": rect.position.x, "y": rect.position.y,
				"w": rect.size.x, "h": rect.size.y,
				"axis": axis,
				"class": String((classes[pick] as Dictionary).get("id", "")),
				"facing": facing,
			})


# All or nothing: a car is a five-tile object and half of one parked through a junction is worse
# than no car, so every tile of the footprint is judged and the first refusal ends the slot. The
# four draws have already happened by the time this is asked, which is the point.
static func _vehicle_fits(map: Variant, rect: Rect2i, surface: int, protected: Dictionary, axis: String) -> bool:
	for ty in range(rect.position.y, rect.position.y + rect.size.y):
		for tx in range(rect.position.x, rect.position.x + rect.size.x):
			if tx <= 0 or ty <= 0 or tx >= int(map.w) - 1 or ty >= int(map.h) - 1:
				return false
			var idx: int = ty * int(map.w) + tx
			if int(map.indoors[idx]) != 0:
				return false
			if int(map.tiles[idx]) != SimTileMapRes.Tile.Floor:
				return false
			# The district's own street surface, not "paved": on a dirt district the carriageway is
			# dirt, and a car parked on grass is a car in somebody's garden.
			if int(map.surfaces[idx]) != surface:
				return false
			# Doorways, loot sites and the colony's ring, the same set every dressing pass refuses.
			if protected.has(idx):
				return false
			if _on_crossing(map, tx, ty, axis):
				return false
	return true


# Is this tile part of a street running the other way? Junctions stay clear: a car in the middle of
# a crossing blocks the one place two routes meet, and it is also the one place the lane offsets
# above stop meaning anything, because the perpendicular street has no kerb there.
static func _on_crossing(map: Variant, tx: int, ty: int, axis: String) -> bool:
	for street in map.streets as Array:
		if not (street is Dictionary):
			continue
		var span: Dictionary = street as Dictionary
		var other: String = String(span.get("axis", "x"))
		if other == axis:
			continue
		var at: int = int(span.get("at", 0))
		var width: int = maxi(1, int(span.get("width", 1)))
		var from: int = int(span.get("from", 0))
		var to: int = int(span.get("to", 0))
		if other == "x":
			if tx >= at and tx < at + width and ty >= from and ty <= to:
				return true
		elif ty >= at and ty < at + width and tx >= from and tx <= to:
			return true
	return false


# --- 7. loot sites --------------------------------------------------------------------------

# Where the loot is, from the district's own `lootProfile`. docs/24 gives every district type "a
# loot profile, a danger profile, and a shape", and this is the first half made real: which tables
# a place yields, how many sites of each, and whether a site stands as a container or is scattered
# on the floor -- all of it a data entry, none of it a branch in here.
#
# Two kinds of entry, because two questions are being asked:
#
#   `perBuilding` -- how much of an ordinary building's kind of loot there is. A count per
#                    qualifying building, so it scales with the district the way the buildings do:
#                    a 64-tile miniature has a handful of houses and gets a handful of cupboards.
#   `perDistrict` -- the rare tables, which are a property of the district rather than of any one
#                    building: one medical store, one cache. Authored for a full 256 m district
#                    and scaled by area, so the miniature carries none of them (see
#                    `_district_count`) and the shipped size carries exactly what it declares.
#
# Interiors dominate on purpose -- docs/24: "interiors are where the game happens" -- and an
# `outdoors` entry is the exception that proves it: a car boot on a driveway, standing on open
# ground beside the house it belongs to.
#
# Deterministic: Arrays iterated in order (the profile's entries, the placement manifest, the
# candidate tiles), never a raw Dictionary's key order, and every draw off this pass's own stream.
static func _sites(map: Variant, seed_val: int, district: Dictionary, templates: Array, placed: Array, reserve: Rect2i) -> void:
	var profile: Variant = district.get("lootProfile")
	if not (profile is Dictionary):
		# A district that declares no profile yields nothing the generator put there. Silent rather
		# than loud: the fixture districts the gates build are exactly this, and the shipped ones
		# are held to having a profile by check_loot.gd instead.
		return
	var rng: Variant = _stream(seed_val, "sites")
	var tags_by_id: Dictionary = _tags_by_id(templates)
	var sites: Array = map.sites as Array
	# Tiles already spoken for, so two sites never stand on one another -- seeded from whatever a
	# template stamp has already written (a building template carrying its own `loot` rows).
	var taken: Dictionary = {}
	for record in sites:
		taken[int((record as Dictionary)["y"]) * int(map.w) + int((record as Dictionary)["x"])] = true

	for entry_v in (profile as Dictionary).get("perBuilding", []) as Array:
		var entry: Dictionary = entry_v as Dictionary
		var tags: Array = entry.get("tags", []) as Array
		for record_v in placed:
			var building: Dictionary = record_v as Dictionary
			if not _tagged(tags_by_id, String(building.get("id", "")), tags):
				continue
			# Drawn before the interior is looked at, so the draw count depends on (seed, district,
			# layout) and never on how big a room turned out to be.
			var wanted: int = _roll_count(rng, entry.get("sites"))
			var floors: Array = _interior_floors(map, building)
			for _i in wanted:
				var tile: int = _take_tile(rng, floors, taken)
				if tile < 0:
					break
				sites.append(_site_record(rng, map, tile, entry))

	var outdoors: Array = []
	var outdoors_built: bool = false
	var tails: Array = []
	var tails_built: bool = false
	for entry_v2 in (profile as Dictionary).get("perDistrict", []) as Array:
		var entry2: Dictionary = entry_v2 as Dictionary
		var count: int = _district_count(int(entry2.get("count", 0)), mini(int(map.w), int(map.h)))
		if count <= 0:
			continue
		var hosts: Array = []
		# Where this entry's outdoor sites may stand. Chosen once for the whole entry and never per
		# site: which list is used is a property of the map (did this district park any cars?) and
		# a per-site fallback would draw a different number of times on a district with one car
		# than on a district with none, which is the stream-shifting trap the vehicles pass is
		# documented under. `_take_tile` costs the same one draw whichever list it is handed.
		var open_ground: Array = []
		if bool(entry2.get("outdoors", false)):
			# `host: vehicle` -- a car boot stands on a car, at the tail end where a boot is.
			# Falling back to the driveway is the normal path rather than a failure: a district
			# with no `vehicles` block parks nothing at any size, and the suburb parks nothing at
			# the 64 every gate boots, because its streets come out two tiles wide there.
			if String(entry2.get("host", "")) == "vehicle":
				if not tails_built:
					tails = _vehicle_tails(map)
					tails_built = true
				open_ground = tails
			if open_ground.is_empty():
				if not outdoors_built:
					outdoors = _driveway_tiles(map, placed, reserve)
					outdoors_built = true
				open_ground = outdoors
		else:
			hosts = _buildings_tagged(placed, tags_by_id, entry2.get("tags", []) as Array)
			if hosts.is_empty():
				# Nowhere to put it: a district whose pool never rolled the kind of building this
				# table lives in gets fewer sites rather than a cache in somebody's shed. The gate
				# is what asserts the shipped districts do have somewhere.
				continue
		for _i in count:
			var tile2: int = -1
			if bool(entry2.get("outdoors", false)):
				tile2 = _take_tile(rng, open_ground, taken)
			else:
				var host: Dictionary = hosts[int(rng.call("int_range", 0, hosts.size() - 1))] as Dictionary
				tile2 = _take_tile(rng, _interior_floors(map, host), taken)
			if tile2 < 0:
				continue
			sites.append(_site_record(rng, map, tile2, entry2))
	map.sites = sites


# A per-district count is authored for a full 256 m district, and a smaller map gets the same
# share of it by area. So the 64-tile miniature -- a sixteenth of the area -- carries none of a
# table that ships one or two, which is the honest answer rather than a rounding accident: the
# rare tables are what makes a *district* worth crossing, and a model of a district that fits four
# of them into 64 tiles would be a different game. Pure arithmetic on the declared number, no
# draws, so the count is the same on every seed.
static func _district_count(count: int, size: int) -> int:
	var full: int = SimTileMapRes.DISTRICT_TILES
	var share: float = float(size * size) / float(full * full)
	return int(round(float(count) * share))


# Inclusive both ends, and one draw whichever way it goes.
static func _roll_count(rng: Variant, spec: Variant) -> int:
	if not (spec is Dictionary):
		return 1
	var lo: int = maxi(0, int((spec as Dictionary).get("min", 1)))
	var hi: int = maxi(lo, int((spec as Dictionary).get("max", lo)))
	return int(rng.call("int_range", lo, hi))


# One site: the tile, the table, and whether it stands as a container. A container is the same
# table rolled later (docs/12's finite site, searched once) -- which of the two a site is, is a
# content decision here rather than a code one.
static func _site_record(rng: Variant, map: Variant, tile: int, entry: Dictionary) -> Dictionary:
	var w: int = int(map.w)
	var record: Dictionary = {"x": tile % w, "y": tile / w, "table": String(entry.get("table", ""))}
	var kinds: Array = entry.get("containers", []) as Array
	if kinds.is_empty():
		return record
	if float(rng.call("next")) >= float(entry.get("containerShare", 0.0)):
		return record
	record["container"] = String(kinds[int(rng.call("int_range", 0, kinds.size() - 1))])
	return record


# One tile out of `candidates`, skipping the ones already spoken for. Picked, then walked forward
# from the pick rather than re-rolled, so a crowded interior costs one draw like an empty one.
# Returns -1 when every candidate is taken.
static func _take_tile(rng: Variant, candidates: Array, taken: Dictionary) -> int:
	if candidates.is_empty():
		return -1
	var at: int = int(rng.call("int_range", 0, candidates.size() - 1))
	for step in candidates.size():
		var tile: int = int(candidates[(at + step) % candidates.size()])
		if taken.has(tile):
			continue
		taken[tile] = true
		return tile
	return -1


# The open indoor floor of one placed building, as tile indices in row-major order. Doorways are
# not indoors (a template flags its perimeter 0), so a site never stands in a doorway.
static func _interior_floors(map: Variant, building: Dictionary) -> Array:
	var out: Array = []
	var w: int = int(map.w)
	for j in int(building.get("h", 0)):
		for i in int(building.get("w", 0)):
			var tx: int = int(building.get("x", 0)) + i
			var ty: int = int(building.get("y", 0)) + j
			if tx < 0 or ty < 0 or tx >= w or ty >= int(map.h):
				continue
			var idx: int = ty * w + tx
			if int(map.indoors[idx]) != 1:
				continue
			if int(map.tiles[idx]) != SimTileMapRes.Tile.Floor:
				continue
			out.append(idx)
	return out


# Open outdoor ground within a couple of tiles of a placed building -- the driveway, the verge, the
# kerb outside the shop. Not "anywhere outdoors": a car boot in the middle of a field is a car boot
# nobody will ever walk past, and the district is mostly field. In placement order, deduplicated,
# and clear of the colony's reserve.
static func _driveway_tiles(map: Variant, placed: Array, reserve: Rect2i) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	var w: int = int(map.w)
	for record in placed:
		var b: Dictionary = record as Dictionary
		for ty in range(int(b.get("y", 0)) - 2, int(b.get("y", 0)) + int(b.get("h", 0)) + 2):
			for tx in range(int(b.get("x", 0)) - 2, int(b.get("x", 0)) + int(b.get("w", 0)) + 2):
				if tx <= 0 or ty <= 0 or tx >= w - 1 or ty >= int(map.h) - 1:
					continue
				var idx: int = ty * w + tx
				if seen.has(idx):
					continue
				seen[idx] = true
				if _in_reserve(reserve, tx, ty, RESERVE_MARGIN):
					continue
				if int(map.indoors[idx]) == 1:
					continue
				if int(map.tiles[idx]) != SimTileMapRes.Tile.Floor:
					continue
				out.append(idx)
	return out


# The back end of every parked car, as tile indices in manifest order: the row (or column) of the
# footprint away from the nose, both tiles of the body's breadth. Where the boot is -- so a
# `host: vehicle` site stands at the back of a car and not on its bonnet.
#
# Pure and drawless, like `_driveway_tiles`, and empty on any map that parked nothing: a fixture,
# a district with no `vehicles` block, and the 64-tile map every gate boots. The tiles are
# Tile.Low rather than Tile.Floor, which is what a car is -- not solid, walkable while the ground
# under it is paved, and cover you can shoot over -- so a site standing on one still stands
# somewhere open, which is the question check_loot.gd asks of it.
static func _vehicle_tails(map: Variant) -> Array:
	var out: Array = []
	var w: int = int(map.w)
	for record in map.vehicles as Array:
		if not (record is Dictionary):
			continue
		var car: Dictionary = record as Dictionary
		var x: int = int(car.get("x", 0))
		var y: int = int(car.get("y", 0))
		var cw: int = int(car.get("w", 0))
		var ch: int = int(car.get("h", 0))
		if cw <= 0 or ch <= 0:
			continue
		var facing: String = String(car.get("facing", ""))
		if String(car.get("axis", "ns")) == "ns":
			# Nose north puts the tail on the southern row, and the other way round.
			var row: int = (y + ch - 1) if facing == "n" else y
			for tx in range(x, x + cw):
				out.append(row * w + tx)
		else:
			var col: int = x if facing == "e" else (x + cw - 1)
			for ty in range(y, y + ch):
				out.append(ty * w + col)
	return out


static func _tags_by_id(templates: Array) -> Dictionary:
	var out: Dictionary = {}
	for t in templates:
		out[String((t as Dictionary).get("id", ""))] = (t as Dictionary).get("tags", []) as Array
	return out


static func _tagged(tags_by_id: Dictionary, id: String, wanted: Array) -> bool:
	var tags: Array = tags_by_id.get(id, []) as Array
	for tag in wanted:
		if tags.has(String(tag)):
			return true
	return false


static func _buildings_tagged(placed: Array, tags_by_id: Dictionary, wanted: Array) -> Array:
	var out: Array = []
	for record in placed:
		if _tagged(tags_by_id, String((record as Dictionary).get("id", "")), wanted):
			out.append(record)
	return out


# Tiles the dressing may not plant anything solid on: every doorway, the ground immediately
# outside it, every loot site, and the ring around the annex reserve. A stand of trees across a
# door would make a building unenterable, which is the one property the sandbox goal asks this
# generator for -- and a tree grown over a car boot would be loot inside a solid tile, which is
# what makes the sites layout rather than dressing.
static func _protected_tiles(map: Variant, reserve: Rect2i) -> Dictionary:
	var out: Dictionary = {}
	for site in map.sites as Array:
		var s: Dictionary = site as Dictionary
		out[int(s["y"]) * int(map.w) + int(s["x"])] = true
	for record in map.buildings as Array:
		for door in (record as Dictionary)["doors"] as Array:
			var d: Dictionary = door as Dictionary
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var tx: int = int(d["x"]) + dx
					var ty: int = int(d["y"]) + dy
					if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
						continue
					out[ty * int(map.w) + tx] = true
	if reserve.size.x <= 0 or reserve.size.y <= 0:
		return out
	var margin: int = RESERVE_MARGIN + 1
	for ty in range(reserve.position.y - margin, reserve.position.y + reserve.size.y + margin):
		for tx in range(reserve.position.x - margin, reserve.position.x + reserve.size.x + margin):
			if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
				continue
			out[ty * int(map.w) + tx] = true
	return out


# --- 8. survivability -------------------------------------------------------------------------

# docs/01's fairness rule, made mechanical: "No unwinnable starts: generated starting positions are
# validated for basic survivability." A pure function of the finished map -- no draws, no world, no
# writes -- so the generator can ask it of a candidate and a gate can ask it of a map somebody
# sabotaged, and both get the same answer for the same reason.
#
# It reads the map through `SimPath.walkable_tile`, which is `SimPath.walkable` with the world taken
# out: the routes it judges are the routes the survivors' own pathfinder will accept, rather than a
# second opinion about what counts as ground. A flood fill rather than repeated A*, because the
# question is reachability and not the route -- and because A* carries a 4096-node guard that a
# 256 m district would hit honestly.
#
# The clauses, and what each one is protecting against:
#
#   player-start     -- the tile the player boots onto is open floor. A start inside masonry is
#                       `find_open_tile` walking somebody out of their own colony.
#   gates-open       -- both gate tiles are open floor. A colony you cannot leave.
#   gates-reachable  -- a road that leaves the district reaches the gate over walkable ground, so
#                       the colony is on the district's own network rather than behind it. A
#                       district whose wall has no opening in it has no road to be reached from, so
#                       this clause **skips** and says so rather than failing a district for a road
#                       it never declared -- the fixture districts that declare no connection
#                       points are exactly that, and a clause with no data to judge that quietly
#                       returned true would be worse than one that failed.
#   stations-room    -- STATION_TILES of indoor floor inside the annex, which is what
#                       `SimBoot.place_stations` needs for a fire and two beds.
#   well-open        -- the well anchor is open ground, or nobody can draw water.
#   loot-reachable   -- every table the district actually placed has at least one site a walk from
#                       the gate can get to. A medical store sealed behind a wall is a table the
#                       campaign is balanced around and the player can never open.
#
# Returned as a report rather than a bool so a gate can assert one clause at a time and name the one
# that failed. `sited` false is a district that got no colony -- the fixture maps too small to hold
# one -- and it says so and judges nothing rather than passing a district it never looked at. A
# clause can also come back `skipped`, which is the same discipline one clause down: it had nothing
# to judge, it says so, and a caller that wants a district fully judged asks for that rather than
# reading `ok` and assuming.
static func survivability_report(map: Variant) -> Dictionary:
	var clauses: Array = []
	var annex: Rect2i = SimTileMapRes.annex_rect(map)
	if annex.size.x <= 0 or annex.size.y <= 0:
		return {"ok": true, "sited": false, "annex": annex, "clauses": clauses, "failed": []}

	var start: Vector2i = SimTileMapRes.player_start(map)
	var gate_a: Vector2i = SimTileMapRes.gate_a(map)
	var gate_b: Vector2i = SimTileMapRes.gate_b(map)
	var well: Vector2i = SimTileMapRes.well_tile(map)

	clauses.append(_clause("player-start", _open_floor(map, start), "the boot tile is %s" % str(start)))

	var gates_open: bool = _open_floor(map, gate_a) and _open_floor(map, gate_b)
	clauses.append(_clause("gates-open", gates_open, "the gate is %s..%s" % [str(gate_a), str(gate_b)]))

	# One fill, from the gates outward, answers both reachability clauses: a road that reaches the
	# gate and a cupboard the gate reaches are the same connected component walked from the same
	# source. Empty when the gates are bricked, which is why those two clauses fail together and
	# say which one caused it.
	var reached: PackedByteArray = _walk_from(map, [gate_a, gate_b])
	var w: int = int(map.w)
	var roads: Array = _connection_tiles(map)
	var joined: int = 0
	for tile in roads:
		var t: Vector2i = tile as Vector2i
		if reached[t.y * w + t.x] == 1:
			joined += 1
	if roads.is_empty():
		clauses.append(_skipped("gates-reachable", "the district wall carries no opening, so there is no road for the gate to be reachable from"))
	else:
		clauses.append(_clause("gates-reachable", joined > 0, "%d of %d roads out of the district reach the gate" % [joined, roads.size()]))

	var floors: int = 0
	for ty in range(annex.position.y, annex.position.y + annex.size.y):
		for tx in range(annex.position.x, annex.position.x + annex.size.x):
			if not SimTileMapRes.is_indoors(map, tx, ty):
				continue
			if SimTileMapRes.tile_at(map, tx, ty) != SimTileMapRes.Tile.Floor:
				continue
			if SimTileMapRes.is_solid(map, tx, ty):
				continue
			floors += 1
	clauses.append(_clause("stations-room", floors >= STATION_TILES, "%d indoor floor tiles inside %s, %d wanted" % [floors, str(annex), STATION_TILES]))

	var well_ok: bool = well.x > 0 and well.y > 0 and well.x < w - 1 and well.y < int(map.h) - 1 \
			and not SimTileMapRes.is_solid(map, well.x, well.y)
	clauses.append(_clause("well-open", well_ok, "the well is %s" % str(well)))

	# An Array of records rather than a Dictionary keyed by table: the order a table is first seen is
	# the order this reports in, and a Dictionary's key order is not something to build a report on.
	var tables: Array = []
	for site in map.sites as Array:
		var s: Dictionary = site as Dictionary
		var table: String = String(s.get("table", ""))
		var at: int = -1
		for i in tables.size():
			if String((tables[i] as Dictionary)["table"]) == table:
				at = i
				break
		if at < 0:
			tables.append({"table": table, "sites": 0, "reached": 0})
			at = tables.size() - 1
		var record: Dictionary = tables[at] as Dictionary
		record["sites"] = int(record["sites"]) + 1
		var tx2: int = int(s.get("x", -1))
		var ty2: int = int(s.get("y", -1))
		if tx2 >= 0 and ty2 >= 0 and tx2 < w and ty2 < int(map.h) and reached[ty2 * w + tx2] == 1:
			record["reached"] = int(record["reached"]) + 1
	var stranded: Array = []
	for record2 in tables:
		if int((record2 as Dictionary)["reached"]) < 1:
			stranded.append(String((record2 as Dictionary)["table"]))
	if tables.is_empty():
		clauses.append(_skipped("loot-reachable", "the district placed no loot at all, so there is no table to be out of reach"))
	else:
		clauses.append(_clause("loot-reachable", stranded.is_empty(), "%d tables placed, %s out of reach" % [
			tables.size(), "none" if stranded.is_empty() else str(stranded),
		]))

	var failed: Array = []
	for clause in clauses:
		if not bool((clause as Dictionary)["ok"]):
			failed.append(String((clause as Dictionary)["name"]))
	return {"ok": failed.is_empty(), "sited": true, "annex": annex, "clauses": clauses, "failed": failed}


# One clause of a report, by name, or {} -- so a gate asserts the clause it means rather than an
# index into a list whose order it would then depend on.
static func clause_of(report: Dictionary, name: String) -> Dictionary:
	for clause in report.get("clauses", []) as Array:
		if String((clause as Dictionary).get("name", "")) == name:
			return clause as Dictionary
	return {}


static func _clause(name: String, ok: bool, said: String) -> Dictionary:
	return {"name": name, "ok": ok, "skipped": false, "said": said}


# A clause with nothing to judge. `ok` is true because there is no failure here to report, and
# `skipped` is what stops that reading as a pass -- a district the generator is entitled to ship is
# not the same thing as a district that answered the question.
static func _skipped(name: String, said: String) -> Dictionary:
	return {"name": name, "ok": true, "skipped": true, "said": said}


static func _open_floor(map: Variant, tile: Vector2i) -> bool:
	if tile.x < 0 or tile.y < 0 or tile.x >= int(map.w) or tile.y >= int(map.h):
		return false
	if SimTileMapRes.tile_at(map, tile.x, tile.y) != SimTileMapRes.Tile.Floor:
		return false
	return not SimTileMapRes.is_solid(map, tile.x, tile.y)


# The tile inside each opening in the district wall: where a road that leaves arrives back. Read off
# the tiles rather than off what `_connection_points` recorded, because an opening the generator
# meant to carve and did not is exactly the failure this is looking for.
static func _connection_tiles(map: Variant) -> Array:
	var out: Array = []
	var w: int = int(map.w)
	var h: int = int(map.h)
	for x in range(1, w - 1):
		if SimTileMapRes.tile_at(map, x, 0) == SimTileMapRes.Tile.Floor:
			out.append(Vector2i(x, 1))
		if SimTileMapRes.tile_at(map, x, h - 1) == SimTileMapRes.Tile.Floor:
			out.append(Vector2i(x, h - 2))
	for y in range(1, h - 1):
		if SimTileMapRes.tile_at(map, 0, y) == SimTileMapRes.Tile.Floor:
			out.append(Vector2i(1, y))
		if SimTileMapRes.tile_at(map, w - 1, y) == SimTileMapRes.Tile.Floor:
			out.append(Vector2i(w - 2, y))
	return out


# Four-connected flood fill over ground `SimPath.walkable_tile` accepts, from every source at once.
#
# The footing is answered once per tile into a mask and the walk then reads the mask, rather than
# asking `walkable_tile` again at every edge into a tile: a four-connected fill reaches most tiles
# from more than one neighbour, and this pass runs twice per generated district at a size where
# `is_solid` is a Dictionary lookup per call. One pass over the map, one queue, and the district is
# judged in a fixed cost the seed cannot move.
static func _walk_from(map: Variant, sources: Array) -> PackedByteArray:
	var w: int = int(map.w)
	var h: int = int(map.h)
	var footing: PackedByteArray = PackedByteArray()
	footing.resize(w * h)
	for y in h:
		for x in w:
			if SimPathRes.walkable_tile(map, x, y):
				footing[y * w + x] = 1
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(w * h)
	var queue: Array[Vector2i] = []
	for source in sources:
		var s: Vector2i = source as Vector2i
		if s.x < 0 or s.y < 0 or s.x >= w or s.y >= h:
			continue
		if seen[s.y * w + s.x] == 1 or footing[s.y * w + s.x] == 0:
			continue
		seen[s.y * w + s.x] = 1
		queue.append(s)
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		for step in SimPathRes.DIRS:
			var next: Vector2i = at + (step as Vector2i)
			if next.x < 0 or next.y < 0 or next.x >= w or next.y >= h:
				continue
			var idx: int = next.y * w + next.x
			if seen[idx] == 1 or footing[idx] == 0:
				continue
			seen[idx] = 1
			queue.append(next)
	return seen


# --- 9. occluder dressing -------------------------------------------------------------------

# Adapted from the old `SimTileMap._dress_occluders`, on its own named stream. Same three ideas:
# a wall with open ground on both sides is a wall you can put a window in; screening clumps break
# a sightline without blocking a route; low wrecks are cover you can shoot over.
static func _dress_occluders(map: Variant, seed_val: int, protected: Dictionary) -> void:
	var rng: Variant = _stream(seed_val, "occluders")
	var w: int = int(map.w)
	for ty in range(1, int(map.h) - 1):
		for tx in range(1, w - 1):
			if int(map.tiles[ty * w + tx]) != SimTileMapRes.Tile.Wall:
				continue
			var horizontal: bool = !SimTileMapRes.is_solid(map, tx - 1, ty) and !SimTileMapRes.is_solid(map, tx + 1, ty)
			var vertical: bool = !SimTileMapRes.is_solid(map, tx, ty - 1) and !SimTileMapRes.is_solid(map, tx, ty + 1)
			if !horizontal and !vertical:
				continue
			if int(rng.call("int_range", 0, 2)) != 0:
				continue
			map.tiles[ty * w + tx] = SimTileMapRes.Tile.Window
	var clumps: int = maxi(1, floori(float(w * int(map.h)) / 3000.0))
	for _i in clumps:
		var ox: int = int(rng.call("int_range", 1, w - 2))
		var oy: int = int(rng.call("int_range", 1, int(map.h) - 2))
		var cw: int = int(rng.call("int_range", 2, 4))
		var ch: int = int(rng.call("int_range", 2, 4))
		for dy in ch:
			for dx in cw:
				_dress_tile(map, ox + dx, oy + dy, SimTileMapRes.Tile.Screen, protected)
	var wrecks: int = maxi(1, floori(float(w * int(map.h)) / 2000.0))
	for _i in wrecks:
		var ox: int = int(rng.call("int_range", 1, w - 2))
		var oy: int = int(rng.call("int_range", 1, int(map.h) - 2))
		var along: bool = int(rng.call("int_range", 0, 1)) == 0
		var length: int = int(rng.call("int_range", 2, 3))
		for step in length:
			_dress_tile(map, ox + step if along else ox, oy if along else oy + step, SimTileMapRes.Tile.Low, protected)


# The one place a dressing pass writes a tile. Outdoor open ground only, never a doorway, never
# the annex's ring.
static func _dress_tile(map: Variant, tx: int, ty: int, tile: int, protected: Dictionary) -> bool:
	if tx <= 0 or ty <= 0 or tx >= int(map.w) - 1 or ty >= int(map.h) - 1:
		return false
	var idx: int = ty * int(map.w) + tx
	if protected.has(idx):
		return false
	if SimTileMapRes.is_indoors(map, tx, ty):
		return false
	if int(map.tiles[idx]) != SimTileMapRes.Tile.Floor:
		return false
	map.tiles[idx] = tile
	return true


# --- 10. terrain dressing --------------------------------------------------------------------

# The old pass, rewritten around the block list instead of a hardcoded block=64 lattice: lawns
# inside a block, a stand or two of trees, thickets of undergrowth, and the trodden dirt where a
# green meets the pavement. docs/24's ground table is what makes this a mechanic rather than a
# texture -- grass is quiet and slow, undergrowth is cover you cannot see out of.
# The terrain pass's numbers, read off a district's optional `terrain` block. Every default here
# is the literal this pass carried before the block existed, so a district that declares none
# dresses exactly as it did -- and that is asserted byte-identical rather than assumed, because
# an RNG stream is a *sequence*: a pass that draws a different number of times, or draws the same
# number of times from a different range, moves every tile decided after it and not just the one
# being tuned. Every entry below therefore changes an argument to a draw, never how many draws
# happen; the loop counts that follow from those values are the only thing allowed to move.
static func _terrain_of(district: Dictionary) -> Dictionary:
	var raw: Variant = district.get("terrain")
	var t: Dictionary = (raw as Dictionary) if raw is Dictionary else {}
	return {
		"grass_jitter": int(t.get("grassJitter", 3)),
		"stand_odds": int(t.get("standOdds", 1)),
		"stands_min": int(t.get("standsMin", 1)),
		"stands_max": int(t.get("standsMax", 3)),
		"trees_min": int(t.get("treesMin", 3)),
		"trees_max": int(t.get("treesMax", 8)),
		"tree_spread": int(t.get("treeSpread", 2)),
		"thickets_min": int(t.get("thicketsMin", 1)),
		"thickets_max": int(t.get("thicketsMax", 3)),
		"thicket_min": int(t.get("thicketMin", 2)),
		"thicket_max": int(t.get("thicketMax", 4)),
		"worn_odds": int(t.get("wornOdds", 2)),
		"paths": bool(t.get("paths", false)),
	}


static func _dress_terrain(map: Variant, seed_val: int, streets: Dictionary, protected: Dictionary, terrain: Dictionary) -> void:
	var rng: Variant = _stream(seed_val, "terrain")
	var w: int = int(map.w)
	for yb in streets["y_blocks"] as Array:
		for xb in streets["x_blocks"] as Array:
			var bx: int = int((xb as Array)[0])
			var bw: int = int((xb as Array)[1])
			var by: int = int((yb as Array)[0])
			var bh: int = int((yb as Array)[1])
			var cx: float = float(bx) + float(bw) / 2.0
			var cy: float = float(by) + float(bh) / 2.0
			var radius: float = float(mini(bw, bh)) * 0.5
			for ty in range(by - 1, by + bh + 1):
				for tx in range(bx - 1, bx + bw + 1):
					if tx <= 0 or ty <= 0 or tx >= w - 1 or ty >= int(map.h) - 1:
						continue
					var idx: int = ty * w + tx
					if int(map.tiles[idx]) != SimTileMapRes.Tile.Floor:
						continue
					if SimTileMapRes.is_indoors(map, tx, ty):
						continue
					var distance: float = sqrt(pow(float(tx) + 0.5 - cx, 2.0) + pow(float(ty) + 0.5 - cy, 2.0))
					if distance > radius + float(rng.call("int_range", -int(terrain["grass_jitter"]), int(terrain["grass_jitter"]))):
						continue
					map.surfaces[idx] = SimTileMapRes.SURFACE_GRASS
			if int(rng.call("int_range", 0, int(terrain["stand_odds"]))) != 0:
				continue
			var stands: int = int(rng.call("int_range", int(terrain["stands_min"]), int(terrain["stands_max"])))
			for _i in stands:
				var ox: int = bx + int(rng.call("int_range", 1, maxi(1, bw - 2)))
				var oy: int = by + int(rng.call("int_range", 1, maxi(1, bh - 2)))
				var trees: int = int(rng.call("int_range", int(terrain["trees_min"]), int(terrain["trees_max"])))
				for _t in trees:
					var tx: int = ox + int(rng.call("int_range", -int(terrain["tree_spread"]), int(terrain["tree_spread"])))
					var ty: int = oy + int(rng.call("int_range", -int(terrain["tree_spread"]), int(terrain["tree_spread"])))
					if not _on_grass(map, tx, ty):
						continue
					_dress_tile(map, tx, ty, SimTileMapRes.Tile.Tree, protected)
			var thickets: int = int(rng.call("int_range", int(terrain["thickets_min"]), int(terrain["thickets_max"])))
			for _i in thickets:
				var ox2: int = bx + int(rng.call("int_range", 1, maxi(1, bw - 2)))
				var oy2: int = by + int(rng.call("int_range", 1, maxi(1, bh - 2)))
				var th: int = int(rng.call("int_range", int(terrain["thicket_min"]), int(terrain["thicket_max"])))
				var tw: int = int(rng.call("int_range", int(terrain["thicket_min"]), int(terrain["thicket_max"])))
				for dy in th:
					for dx in tw:
						if not _on_grass(map, ox2 + dx, oy2 + dy):
							continue
						_dress_tile(map, ox2 + dx, oy2 + dy, SimTileMapRes.Tile.Screen, protected)
	# docs/24: screening is always over undergrowth -- outdoors. A shop's shelving is screening
	# too, and the floor under it is still a floor, so the indoor half is left alone.
	for i in map.tiles.size():
		if int(map.tiles[i]) == SimTileMapRes.Tile.Screen and int(map.indoors[i]) == 0:
			map.surfaces[i] = SimTileMapRes.SURFACE_UNDERGROWTH
	# The trodden edge, last: a green that meets pavement wears through where people cross it.
	var worn: Array[int] = []
	for ty in range(1, int(map.h) - 1):
		for tx in range(1, w - 1):
			var idx: int = ty * w + tx
			if int(map.surfaces[idx]) != SimTileMapRes.SURFACE_GRASS:
				continue
			if int(map.tiles[idx]) != SimTileMapRes.Tile.Floor:
				continue
			var edge: bool = int(map.surfaces[idx - 1]) == SimTileMapRes.SURFACE_PAVED \
					or int(map.surfaces[idx + 1]) == SimTileMapRes.SURFACE_PAVED \
					or int(map.surfaces[idx - w]) == SimTileMapRes.SURFACE_PAVED \
					or int(map.surfaces[idx + w]) == SimTileMapRes.SURFACE_PAVED
			if edge and int(rng.call("int_range", 0, int(terrain["worn_odds"]))) != 0:
				worn.append(idx)
	for idx in worn:
		map.surfaces[idx] = SimTileMapRes.SURFACE_DIRT


static func _on_grass(map: Variant, tx: int, ty: int) -> bool:
	if tx <= 0 or ty <= 0 or tx >= int(map.w) - 1 or ty >= int(map.h) - 1:
		return false
	return int(map.surfaces[ty * int(map.w) + tx]) == SimTileMapRes.SURFACE_GRASS


# --- 11. rubble dressing ----------------------------------------------------------------------

# The last dressing pass: SURFACE_RUBBLE, which docs/24 prices (x0.7 speed, x1.7 noise) and which
# no pass had ever placed -- the debt entry measured 0 tiles on both shipped 256 seeds, so the
# row, its palette colour and its tint were reachable only by hand. Three shapes, every one a
# surface write and nothing else:
#
#   * an apron ring round each placed building, one and two tiles out, roughly one ring tile in
#     four -- the collapsed guttering and shed masonry of a structure nobody maintains;
#   * a few small blobs on open ground, authored 2-4 for a full 256 m district and scaled by
#     area like the rare loot tables -- but floored at one rather than rounded to zero, because
#     a shape the gate's 64-tile miniature never runs is a shape nobody knows runs (the
#     dead-socket rule applied to a generator pass);
#   * the odd 1x2/2x2 patch on the street bordering a block -- frost heave through the tarmac,
#     which is also what gives the road paint something to be worn through by.
#
# Draws happen before eligibility tests, every branch, so the draw count is a function of
# (layout, size, seed) and a refused tile cannot shift what the next building sheds.
# A trodden path from every door to the street it faces. Surfaces only: the ground under a path
# stays Floor, so nothing about sight, cover or what a body can walk through moves -- what moves
# is the surface layer, which `SimSurface` already reads for speed (dirt is x0.95) and noise
# (x0.85), and which the ground atlas already carries a row for. So this pass adds no reader; it
# feeds three that existed, which is why it is a dressing pass and not a layout one.
#
# One draw per door, on `worldgen.paths` -- its own named stream, so treading paths cannot move a
# tile any other pass decided, and a district that treads none draws nothing at all. The draw
# picks which leg of the L runs first, because a path that always turned the same way would read
# as a drawn right angle rather than as a route people wore.
static func _paths(map: Variant, seed_val: int, protected: Dictionary) -> void:
	var rng: Variant = _stream(seed_val, "paths")
	var w: int = int(map.w)
	for record in map.buildings as Array:
		if not (record is Dictionary):
			continue
		var doors: Variant = (record as Dictionary).get("doors", [])
		if not (doors is Array):
			continue
		for door in doors as Array:
			if not (door is Dictionary):
				continue
			var dx: int = int((door as Dictionary).get("x", -1))
			var dy: int = int((door as Dictionary).get("y", -1))
			if dx < 0 or dy < 0 or dx >= w or dy >= int(map.h):
				continue
			var target: Vector2i = _nearest_street_point(map, dx, dy)
			if target.x < 0:
				continue
			var x_first: bool = int(rng.call("int_range", 0, 1)) == 0
			_tread(map, dx, dy, target, x_first, protected)


# The closest point on any street span to a tile, or (-1, -1) when the map carries no street
# manifest at all (a hand-built fixture). Read off `map.streets` rather than off the surfaces,
# because in a dirt district the street and the path are the same surface and "nearest paved"
# would answer nothing.
static func _nearest_street_point(map: Variant, tx: int, ty: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d: int = 1 << 30
	for street in map.streets as Array:
		if not (street is Dictionary):
			continue
		var rec: Dictionary = street as Dictionary
		var at: int = int(rec.get("at", 0))
		var width: int = maxi(1, int(rec.get("width", 1)))
		var from: int = int(rec.get("from", 0))
		var to: int = int(rec.get("to", 0))
		var px: int = 0
		var py: int = 0
		if String(rec.get("axis", "x")) == "x":
			px = clampi(tx, at, at + width - 1)
			py = clampi(ty, from, to)
		else:
			px = clampi(tx, from, to)
			py = clampi(ty, at, at + width - 1)
		var d: int = absi(px - tx) + absi(py - ty)
		if d < best_d:
			best_d = d
			best = Vector2i(px, py)
	return best


# Walk one L from the door to the street, wearing every open outdoor floor it crosses down to
# dirt. A tile that is indoors, not a floor, or protected is stepped over rather than written:
# a path may not pave a doorway shut, and `protected` is the same set every other dressing pass
# refuses to touch.
static func _tread(map: Variant, dx: int, dy: int, target: Vector2i, x_first: bool, protected: Dictionary) -> void:
	var x: int = dx
	var y: int = dy
	var legs: Array = [[target.x, y], [x, target.y]] if x_first else [[x, target.y], [target.x, y]]
	for leg in legs:
		var to_x: int = int((leg as Array)[0])
		var to_y: int = int((leg as Array)[1])
		while x != to_x or y != to_y:
			if x != to_x:
				x += signi(to_x - x)
			elif y != to_y:
				y += signi(to_y - y)
			_wear(map, x, y, protected)
	_wear(map, target.x, target.y, protected)


static func _wear(map: Variant, tx: int, ty: int, protected: Dictionary) -> void:
	var w: int = int(map.w)
	if tx <= 0 or ty <= 0 or tx >= w - 1 or ty >= int(map.h) - 1:
		return
	var idx: int = ty * w + tx
	if int(map.tiles[idx]) != SimTileMapRes.Tile.Floor:
		return
	if SimTileMapRes.is_indoors(map, tx, ty):
		return
	if protected.has(idx):
		return
	map.surfaces[idx] = SimTileMapRes.SURFACE_DIRT


static func _rubble(map: Variant, seed_val: int, streets: Dictionary, protected: Dictionary) -> void:
	var rng: Variant = _stream(seed_val, "rubble")
	var w: int = int(map.w)
	var h: int = int(map.h)

	for record in map.buildings as Array:
		var b: Dictionary = record as Dictionary
		for ring in [1, 2]:
			for tile in _ring_tiles(int(b["x"]), int(b["y"]), int(b["w"]), int(b["h"]), int(ring)):
				# Drawn whether or not the tile survives the write rule, so the count depends on
				# the building manifest alone.
				if int(rng.call("int_range", 0, 3)) != 0:
					continue
				_rubble_tile(map, (tile as Vector2i).x, (tile as Vector2i).y, protected)

	var authored: int = 2 + int(rng.call("int_range", 0, 2))
	var share: float = float(w * h) / float(SimTileMapRes.DISTRICT_TILES * SimTileMapRes.DISTRICT_TILES)
	var blobs: int = maxi(1, int(round(float(authored) * share)))
	for _i in blobs:
		var ox: int = int(rng.call("int_range", 1, w - 2))
		var oy: int = int(rng.call("int_range", 1, h - 2))
		var bw: int = int(rng.call("int_range", 2, 3))
		var bh: int = int(rng.call("int_range", 2, 3))
		for dy in bh:
			for dx in bw:
				_rubble_tile(map, ox + dx, oy + dy, protected)

	for yb in streets["y_blocks"] as Array:
		var by: int = int((yb as Array)[0])
		var bh2: int = int((yb as Array)[1])
		for xb in streets["x_blocks"] as Array:
			var bx: int = int((xb as Array)[0])
			var bw2: int = int((xb as Array)[1])
			# All four draws happen for every block, whichever way presence goes.
			var presence: int = int(rng.call("int_range", 0, 2))
			var side: int = int(rng.call("int_range", 0, 3))
			var along: int = int(rng.call("int_range", 0, maxi(0, (bw2 if side < 2 else bh2) - 1)))
			var square: int = int(rng.call("int_range", 0, 1))
			if presence != 0:
				continue
			for tile2 in _street_patch(bx, by, bw2, bh2, side, along, square == 1):
				_rubble_tile(map, (tile2 as Vector2i).x, (tile2 as Vector2i).y, protected)


# The one place rubble is written. The write rule, pinned by check_road_look.gd's placement
# lane: outdoor open Floor only -- **`tiles[idx] == Tile.Floor and indoors[idx] == 0`** --
# because `_footing` grants a non-Floor tile walkability only while the surface under it stays
# PAVED, so rubble under a Low wreck or a Screen would silently turn cover you walk around into
# a wall; and a room re-grounded through the surface layer would change floors nothing indoors
# ever reads. Protected tiles -- doorway rings, loot sites, the annex ring -- are skipped whole,
# the same courtesy the solid dressing pays them.
static func _rubble_tile(map: Variant, tx: int, ty: int, protected: Dictionary) -> bool:
	if tx <= 0 or ty <= 0 or tx >= int(map.w) - 1 or ty >= int(map.h) - 1:
		return false
	var idx: int = ty * int(map.w) + tx
	if protected.has(idx):
		return false
	if int(map.indoors[idx]) != 0:
		return false
	if int(map.tiles[idx]) != SimTileMapRes.Tile.Floor:
		return false
	map.surfaces[idx] = SimTileMapRes.SURFACE_RUBBLE
	return true


# The one-tile-thick ring `ring` tiles out from a building's footprint: top and bottom rows
# first, then the two sides, in a fixed order so the apron's shape is a function of the manifest
# and never of what any draw refused.
static func _ring_tiles(x: int, y: int, w: int, h: int, ring: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var left: int = x - ring
	var top: int = y - ring
	var right: int = x + w - 1 + ring
	var bottom: int = y + h - 1 + ring
	for tx in range(left, right + 1):
		out.append(Vector2i(tx, top))
		out.append(Vector2i(tx, bottom))
	for ty in range(top + 1, bottom):
		out.append(Vector2i(left, ty))
		out.append(Vector2i(right, ty))
	return out


# A 1x2 (or 2x2, when `square`) patch standing just outside a block on the street that borders
# the chosen side, extending two tiles into the street. Sides 0/1 are north/south, 2/3 west/east.
static func _street_patch(bx: int, by: int, bw: int, bh: int, side: int, along: int, square: bool) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var breadth: int = 2 if square else 1
	for d in 2:
		for b in breadth:
			match side:
				0:
					out.append(Vector2i(bx + along + b, by - 1 - d))
				1:
					out.append(Vector2i(bx + along + b, by + bh + d))
				2:
					out.append(Vector2i(bx - 1 - d, by + along + b))
				_:
					out.append(Vector2i(bx + bw + d, by + along + b))
	return out
