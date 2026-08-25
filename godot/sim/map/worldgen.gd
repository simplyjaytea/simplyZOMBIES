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
# The pipeline, in order. Each pass has its own named stream, and passes 1-6 (the layout) draw
# from none of the dressing streams -- so turning the dressing off leaves the layout byte-identical,
# which is the property docs/30 already recorded for the occluder pass, under new names. It is
# asserted rather than asserted-by-comment: check_m2_district.gd's dressing-independence lane.
#
#   1. border            -- the district wall
#   2. worldgen.streets  -- an irregular grid, plus a ring road, terminating at the district's
#                           declared connection points (the M3B road seam, made live)
#   3. worldgen.parcels  -- blocks split into lots
#   4. (reserve)         -- the annex's rect is left alone; SimBoot stamps the colony onto it
#   5. worldgen.buildings-- a weighted pick per lot from the district's pool, thinned by density
#   6. worldgen.sites    -- where the loot is, from the district's lootProfile: interiors first,
#                           the odd car boot on a driveway, the rare tables once per district
#   7. worldgen.occluders-- windows, screening, wrecks
#   8. worldgen.terrain  -- lawns, stands of trees, thickets, the trodden edge of a green
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
const ContentLoaderRes = preload("res://platform/content_loader.gd")

const DEFAULT_DISTRICT: String = "district.residential_suburb"

# Where the civic annex goes, and the one place that says so. `SimBoot.ANNEX_ORIGIN` is the origin
# it stamps at and check_m2_district.gd pins the two together, so this rect and that origin cannot
# drift apart in silence. The generator does not stamp the annex -- it *reserves* the ground:
# no street is carved through this rect and no building is placed within a tile of it, so the
# colony lands on open ground with a walkable ring around it whatever the seed rolled. Siting it
# per seed is the next slice; this is the seam it will replace.
const ANNEX_RESERVE: Rect2i = Rect2i(38, 38, 26, 26)
# One tile of clear ground around the reserve, so the colony always has a way out even when the
# lot next door is built up.
const RESERVE_MARGIN: int = 1

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


# --- entry points ---------------------------------------------------------------------------

# The whole pipeline. `content` is a loaded content tree ({path: entry}); hand it the one the
# caller already has rather than making this walk the directory again (`load_tree` is a full
# directory walk, and this is called once per campaign seed by the balance harness).
#
# `dress` exists for the layout/dressing independence property: with it false, passes 7 and 8 do
# not run and the map carries layout only -- the same buildings, on the same lots, holding the same
# loot sites. Nothing in the game turns it off; it is what lets a gate assert that the dressing
# streams cannot move a wall or a cupboard.
static func generate(seed_val: int, size: int = SimTileMapRes.DISTRICT_TILES, content: Variant = null, district_id: String = DEFAULT_DISTRICT, dress: bool = true) -> Variant:
	var tree: Dictionary = content as Dictionary if content is Dictionary else ContentLoaderRes.load_tree()
	var district: Dictionary = district_of(tree, district_id)
	var templates: Array = templates_of(tree)
	var map: Variant = SimTileMapRes.blank_map(size, size)

	_border(map)
	var streets: Dictionary = _streets(map, seed_val, district)
	var parcels: Array = _parcels(seed_val, streets)
	var placed: Array = _buildings(map, seed_val, district, templates, parcels)
	map.buildings = placed
	_sites(map, seed_val, district, templates, placed)
	if dress:
		# Read back off the map rather than out of the local: the manifest is the thing the loot
		# slice will walk, and a pass that reads it here is what keeps it honest in the meantime.
		var protected: Dictionary = _protected_tiles(map)
		_dress_occluders(map, seed_val, protected)
		_dress_terrain(map, seed_val, streets, protected)
	return map


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
static func _streets(map: Variant, seed_val: int, district: Dictionary) -> Dictionary:
	var rng: Variant = _stream(seed_val, "streets")
	var spec: Dictionary = district.get("streets", {}) as Dictionary
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
	for span in x_axis["streets"] as Array:
		_carve_street(map, int((span as Array)[0]), 1, int((span as Array)[1]), int(map.h) - 2)
	for span in y_axis["streets"] as Array:
		_carve_street(map, 1, int((span as Array)[0]), int(map.w) - 2, int((span as Array)[1]))

	_connection_points(map, rng, district, x_axis, y_axis, width)
	# Only the blocks: they are what passes 3 and 7 read. The street spans and the openings are on
	# the map by now, and a returned copy of them would be a field nothing looks at -- the gate
	# reads the openings off the tiles instead, which is the stronger question anyway.
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


static func _carve_street(map: Variant, x: int, y: int, w: int, h: int) -> void:
	for j in h:
		for i in w:
			var tx: int = x + i
			var ty: int = y + j
			if tx <= 0 or ty <= 0 or tx >= int(map.w) - 1 or ty >= int(map.h) - 1:
				continue
			if _in_reserve(tx, ty, 0):
				continue
			var idx: int = ty * int(map.w) + tx
			map.tiles[idx] = SimTileMapRes.Tile.Floor
			map.surfaces[idx] = SimTileMapRes.SURFACE_PAVED


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
		var tiers: Array = _opening_candidates(map, side, length, x_axis if horizontal else y_axis, width)
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
			_carve_opening(map, side, at, width)


# Where a road could leave, in two tiers: the centre of a street, because a road that continues a
# street is a road; and, when the streets are used up, anywhere far enough from a corner. Both are
# filtered by the annex reserve, which at gate size reaches the wall -- an opening there would be
# a hole in the colony's own back fence.
static func _opening_candidates(map: Variant, side: String, length: int, axis: Dictionary, width: int) -> Array:
	var primary: Array = []
	var fallback: Array = []
	var seen: Dictionary = {}
	for span in axis["streets"] as Array:
		var at: int = int((span as Array)[0]) + int((span as Array)[1]) / 2
		if seen.has(at):
			continue
		seen[at] = true
		if _opening_fits(map, side, at, length, width):
			primary.append(at)
	for at2 in range(OPENING_WIDTH, length - OPENING_WIDTH, OPENING_WIDTH + 2):
		if seen.has(int(at2)):
			continue
		seen[int(at2)] = true
		if _opening_fits(map, side, int(at2), length, width):
			fallback.append(int(at2))
	return [primary, fallback]


static func _apart_from(candidates: Array, at: int) -> Array:
	var kept: Array = []
	for c in candidates:
		if absi(int(c) - at) > OPENING_WIDTH + 1:
			kept.append(int(c))
	return kept


static func _opening_fits(map: Variant, side: String, at: int, length: int, width: int) -> bool:
	var half: int = OPENING_WIDTH / 2
	if at - half < 1 or at + half > length - 2:
		return false
	# The opening and the ground it runs onto must both be clear of the reserve, and the ground
	# must be street: an opening onto somebody's back garden is not a road.
	for step in range(0, width + 1):
		for offset in range(-half, half + 1):
			var tile: Vector2i = _opening_tile(map, side, at + offset, step)
			if _in_reserve(tile.x, tile.y, RESERVE_MARGIN):
				return false
	return true


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


static func _carve_opening(map: Variant, side: String, at: int, width: int) -> void:
	var half: int = OPENING_WIDTH / 2
	for step in range(0, width + 1):
		for offset in range(-half, half + 1):
			var tile: Vector2i = _opening_tile(map, side, at + offset, step)
			if tile.x < 0 or tile.y < 0 or tile.x >= int(map.w) or tile.y >= int(map.h):
				continue
			var idx: int = tile.y * int(map.w) + tile.x
			map.tiles[idx] = SimTileMapRes.Tile.Floor
			map.surfaces[idx] = SimTileMapRes.SURFACE_PAVED


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


# --- 4. the reserve -------------------------------------------------------------------------

static func _in_reserve(tx: int, ty: int, margin: int) -> bool:
	return tx >= ANNEX_RESERVE.position.x - margin \
			and ty >= ANNEX_RESERVE.position.y - margin \
			and tx < ANNEX_RESERVE.position.x + ANNEX_RESERVE.size.x + margin \
			and ty < ANNEX_RESERVE.position.y + ANNEX_RESERVE.size.y + margin


static func _rect_in_reserve(rect: Rect2i, margin: int) -> bool:
	return rect.position.x < ANNEX_RESERVE.position.x + ANNEX_RESERVE.size.x + margin \
			and rect.position.x + rect.size.x > ANNEX_RESERVE.position.x - margin \
			and rect.position.y < ANNEX_RESERVE.position.y + ANNEX_RESERVE.size.y + margin \
			and rect.position.y + rect.size.y > ANNEX_RESERVE.position.y - margin


# --- 5. the buildings -----------------------------------------------------------------------

# One weighted pick per lot, thinned by the district's density, stamped through the same
# `SimTemplates.stamp` the civic annex goes through -- one stamp path, not two.
#
# Returns the manifest: what landed where, with its doors in absolute tiles. The dressing passes
# read it (nothing solid is planted across a doorway) and check_m2_district.gd's enterability lane
# cross-checks it against the map's own indoor regions, so a manifest that lied would fail.
static func _buildings(map: Variant, seed_val: int, district: Dictionary, templates: Array, parcels: Array) -> Array:
	var rng: Variant = _stream(seed_val, "buildings")
	var density: float = clampf(float(district.get("density", 0.0)), 0.0, 1.0)
	var pool: Array = district.get("pool", []) as Array
	var by_tag: Dictionary = _by_tag(templates)
	var placed: Array = []
	for parcel in parcels:
		var lot: Rect2i = parcel as Rect2i
		if _rect_in_reserve(lot, RESERVE_MARGIN):
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


# --- 6. loot sites --------------------------------------------------------------------------

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
static func _sites(map: Variant, seed_val: int, district: Dictionary, templates: Array, placed: Array) -> void:
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
	for entry_v2 in (profile as Dictionary).get("perDistrict", []) as Array:
		var entry2: Dictionary = entry_v2 as Dictionary
		var count: int = _district_count(int(entry2.get("count", 0)), mini(int(map.w), int(map.h)))
		if count <= 0:
			continue
		var hosts: Array = []
		if bool(entry2.get("outdoors", false)):
			if not outdoors_built:
				outdoors = _driveway_tiles(map, placed)
				outdoors_built = true
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
				tile2 = _take_tile(rng, outdoors, taken)
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
static func _driveway_tiles(map: Variant, placed: Array) -> Array:
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
				if _in_reserve(tx, ty, RESERVE_MARGIN):
					continue
				if int(map.indoors[idx]) == 1:
					continue
				if int(map.tiles[idx]) != SimTileMapRes.Tile.Floor:
					continue
				out.append(idx)
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
static func _protected_tiles(map: Variant) -> Dictionary:
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
	var margin: int = RESERVE_MARGIN + 1
	for ty in range(ANNEX_RESERVE.position.y - margin, ANNEX_RESERVE.position.y + ANNEX_RESERVE.size.y + margin):
		for tx in range(ANNEX_RESERVE.position.x - margin, ANNEX_RESERVE.position.x + ANNEX_RESERVE.size.x + margin):
			if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
				continue
			out[ty * int(map.w) + tx] = true
	return out


# --- 7. occluder dressing -------------------------------------------------------------------

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


# --- 8. terrain dressing --------------------------------------------------------------------

# The old pass, rewritten around the block list instead of a hardcoded block=64 lattice: lawns
# inside a block, a stand or two of trees, thickets of undergrowth, and the trodden dirt where a
# green meets the pavement. docs/24's ground table is what makes this a mechanic rather than a
# texture -- grass is quiet and slow, undergrowth is cover you cannot see out of.
static func _dress_terrain(map: Variant, seed_val: int, streets: Dictionary, protected: Dictionary) -> void:
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
					if distance > radius + float(rng.call("int_range", -3, 3)):
						continue
					map.surfaces[idx] = SimTileMapRes.SURFACE_GRASS
			if int(rng.call("int_range", 0, 1)) != 0:
				continue
			var stands: int = int(rng.call("int_range", 1, 3))
			for _i in stands:
				var ox: int = bx + int(rng.call("int_range", 1, maxi(1, bw - 2)))
				var oy: int = by + int(rng.call("int_range", 1, maxi(1, bh - 2)))
				var trees: int = int(rng.call("int_range", 3, 8))
				for _t in trees:
					var tx: int = ox + int(rng.call("int_range", -2, 2))
					var ty: int = oy + int(rng.call("int_range", -2, 2))
					if not _on_grass(map, tx, ty):
						continue
					_dress_tile(map, tx, ty, SimTileMapRes.Tile.Tree, protected)
			var thickets: int = int(rng.call("int_range", 1, 3))
			for _i in thickets:
				var ox2: int = bx + int(rng.call("int_range", 1, maxi(1, bw - 2)))
				var oy2: int = by + int(rng.call("int_range", 1, maxi(1, bh - 2)))
				var th: int = int(rng.call("int_range", 2, 4))
				var tw: int = int(rng.call("int_range", 2, 4))
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
			if edge and int(rng.call("int_range", 0, 2)) != 0:
				worn.append(idx)
	for idx in worn:
		map.surfaces[idx] = SimTileMapRes.SURFACE_DIRT


static func _on_grass(map: Variant, tx: int, ty: int) -> bool:
	if tx <= 0 or ty <= 0 or tx >= int(map.w) - 1 or ty >= int(map.h) - 1:
		return false
	return int(map.surfaces[ty * int(map.w) + tx]) == SimTileMapRes.SURFACE_GRASS
