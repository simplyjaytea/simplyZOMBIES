extends SceneTree
# The map dressing: wrecked cars on runs of Low tiles, broken concrete over rubble, litter on
# street pavement. Content declares the keys (`content/dressing/street.json`),
# `presentation/dressing.gd` resolves which one a tile takes, and `main.gd::_draw_district` blits
# it -- so the three things that can go wrong are a key that names no file, a resolver that picks
# the wrong piece of a car, and a picture nothing draws.
#
# Six lanes plus the budget, each with a true positive and a true negative:
#
#   1. the block is declared, well formed, and every key in it resolves at 64x64 -- and a
#      fabricated key is refused by the same predicate that passes the real ones;
#   2. segments resolve off the neighbours: a run of two is front+rear, a run of three has
#      exactly one mid, an east-west run is the same keys through a quarter turn, and a lone tile
#      classifies as `solo` and resolves nothing, because the skip that would have drawn it was
#      cut with the worldgen change that stood more lone tiles (docs/23: dressing may not move
#      the simulation). A tile that is not Low resolves nothing either;
#   3. the variant is a pure hash of the seed and the run's anchor -- deterministic, alive, and
#      one variant for a whole car, which is the assertion that stops a pale bonnet on a burnt
#      boot. Textually: nothing in dressing.gd reaches for an RNG;
#   4. a booted district is actually dressed -- every Low tile in a run resolves a texture on the
#      canonical seed, no other tile does, and each of the three car segments is stood somewhere
#      across the seeds. The `solo` picture is the one thing here with no reader, and this lane
#      says so out loud rather than passing quietly over it;
#   5. the scatter lands where the ground says and nowhere else, sparse and deterministic;
#   6. the sockets: _draw_district reads Dressing and hands both halves to something that draws.
#
# The one boot is shared, check_worldgen's precedent, and the budget lane at the bottom is what
# stops a later lane quietly adding another.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimSurface = preload("res://sim/map/surface.gd")
const SimWorldgen = preload("res://sim/map/worldgen.gd")
const SimBoot = preload("res://sim/boot.gd")
const Dressing = preload("res://presentation/dressing.gd")
const Appearance = preload("res://presentation/appearance.gd")
const CameraUtil = preload("res://presentation/camera.gd")
const ContentLoader = preload("res://platform/content_loader.gd")

const CANON_SEED: int = 20260805
const GATE_SIZE: int = 64
const MAIN_GD: String = "res://presentation/main.gd"
const DRESSING_GD: String = "res://presentation/dressing.gd"

# Seeds the run-shape lane scans. Four rather than one because a 64-tile district draws only a
# couple of wreck runs -- one seed is an anecdote about two dice rolls, and the claim here is
# about the band the pass draws from.
const SEEDS: Array[int] = [20260805, 404, 31337, 90210]

# Where the segment-coverage scan generates. The wreck pass draws one run per 2,000 tiles, so a
# 64-tile district gets two of them and "is the mid segment ever drawn" would be a question about
# four dice rolls. 128 gets eight a map, thirty-two across the seeds.
const RUN_SIZE: int = 128

# The gate's own wall clock, docs/00 pillar 6. Measured ~2 s on this container; the headroom is
# for a loaded CI box, not for new boots.
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
		ok = _the_block_declares_working_art(stash) and ok
		ok = _segments_resolve_off_the_neighbours(stash) and ok
		ok = _the_variant_is_a_pure_hash(stash) and ok
		ok = _a_booted_district_is_dressed(stash) and ok
		ok = _the_scatter_lands_where_the_ground_says(stash) and ok
		ok = _the_sockets_are_wired() and ok

	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	ok = _the_gate_stayed_inside_its_own_budget(seconds) and ok

	if ok:
		print("WRECKS_OK %d dressing keys resolve, segments read off the neighbours, variants hashed per run, %d of %d Low tiles dressed as cars on the canonical seed (%d lone tiles keep the procedural block), scatter on %d rubble and %d litter tiles, sockets wired; %.1f s of a %.0f s budget" % [
			int(stash.get("keys", 0)), int(stash.get("car", 0)), int(stash.get("low", 0)),
			int(stash.get("solo", 0)), int(stash.get("rubble", 0)), int(stash.get("litter", 0)),
			seconds, BUDGET_SECONDS,
		])
		quit(0)
	else:
		push_error("WRECKS_FAIL")
		quit(1)


func _tree() -> Dictionary:
	if _tree_cache.is_empty():
		_tree_cache = ContentLoader.load_tree()
	return _tree_cache


func _boot(stash: Dictionary) -> bool:
	Appearance.forget()
	var boot: Dictionary = SimBoot.playable(CANON_SEED, GATE_SIZE)
	stash["world"] = boot["world"]
	stash["map"] = boot["map"]
	var block: Dictionary = Dressing.block_of(boot["world"])
	if block.is_empty():
		push_error("no %s in content: every lane below would be judging an empty block" % Dressing.BLOCK_ID)
		return false
	stash["block"] = block
	return true


# --- 1. the block declares art that exists ---------------------------------------------------

# Every sprite key a dressing block names, flattened. The nested walk is the point of the lane:
# the content validator checks that `wrecks` is an object and never once looks inside it, so this
# is where a typo in `wreck_car_b_mid` stops being invisible.
func _keys_of(block: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var wrecks: Variant = block.get("wrecks")
	if wrecks is Dictionary:
		# `solo` is optional and absent today -- see the header. Walked anyway, so the day one is
		# authored it is held to the same "resolves at 64x64" rule as everything else.
		var solo: String = String((wrecks as Dictionary).get("solo", ""))
		if not solo.is_empty():
			out.append(solo)
		var variants: Variant = (wrecks as Dictionary).get("variants")
		if variants is Array:
			for entry in variants as Array:
				if not (entry is Dictionary):
					continue
				for segment in [Dressing.SEG_FRONT, Dressing.SEG_MID, Dressing.SEG_REAR]:
					var key: String = String((entry as Dictionary).get(segment, ""))
					if not key.is_empty():
						out.append(key)
	for field in ["litter", "rubble"]:
		var keys: Variant = block.get(field)
		if keys is Array:
			for key2 in keys as Array:
				out.append(String(key2))
	return out


# The first key that resolves nothing or resolves at the wrong size, or "". The fabricated
# negative below refuses through this, so the two directions share one predicate.
func _first_broken_key(keys: Array[String]) -> String:
	for key in keys:
		var texture: Texture2D = Appearance.resolve(key)
		if texture == null:
			return key
		if texture.get_size() != Vector2(CameraUtil.ART_NATIVE, CameraUtil.ART_NATIVE):
			return key
	return ""


func _the_block_declares_working_art(stash: Dictionary) -> bool:
	var block: Dictionary = stash["block"]
	var keys: Array[String] = _keys_of(block)
	# Three car variants of three segments, three scraps of litter and two rubble piles: a floor
	# rather than an exact count, because adding a fourth car is a content edit and not a reason to
	# edit a gate -- but a block that lost its variants array entirely reads as 5 here.
	if keys.size() < 10:
		push_error("the dressing block declares %d sprite keys; that is not a set of cars and some debris" % keys.size())
		return false
	var broken: String = _first_broken_key(keys)
	if not broken.is_empty():
		push_error("dressing key '%s' resolves no 64x64 texture; content names art nobody drew" % broken)
		return false
	# Duplicated keys mean two decisions drawing one picture -- a car whose front and rear are the
	# same file tiles into a two-headed wreck.
	var seen: Dictionary = {}
	for key2 in keys:
		if seen.has(key2):
			push_error("the dressing block names '%s' twice; two segments cannot be one picture" % key2)
			return false
		seen[key2] = true

	# True negative, same predicate: a key nobody authored must be refused. Without this the lane
	# would pass on an empty key list as loudly as on a correct one.
	if _first_broken_key(["wreck_car_zz_front"] as Array[String]) != "wreck_car_zz_front":
		push_error("a fabricated key resolved a texture; the key check is not reading the sprite directory")
		return false
	# And a block that declares nothing resolves nothing rather than falling through to a default.
	if not Dressing.wreck_key({}, stash["map"], CANON_SEED, 0, 0).is_empty():
		push_error("an empty dressing block resolved a wreck key; absence must be graceful, not defaulted")
		return false

	stash["keys"] = keys.size()
	print("DRESSING OK %d keys declared in %s, every one a %dx%d texture, no duplicates; a fabricated key and an empty block both refused" % [keys.size(), Dressing.BLOCK_ID, int(CameraUtil.ART_NATIVE), int(CameraUtil.ART_NATIVE)])
	return true


# --- 2. segments ------------------------------------------------------------------------------

# A hand-built map with Low tiles at the given positions: the smallest thing that can be asked
# "what is this tile a piece of", with no generator in the way.
func _map_with_lows(positions: Array) -> Variant:
	var map: Variant = SimTileMap.blank_map(16, 16)
	var tiles: PackedByteArray = map.tiles as PackedByteArray
	for p in positions:
		var v: Vector2i = p as Vector2i
		tiles[v.y * 16 + v.x] = SimTileMap.Tile.Low
	# Whole-array write: packed arrays are values, and an element write through the property
	# would land on a copy (CLAUDE.md's first trap).
	map.tiles = tiles
	return map


func _segments_resolve_off_the_neighbours(stash: Dictionary) -> bool:
	var block: Dictionary = stash["block"]

	# A lone tile classifies as its own thing rather than as a one-tile car -- which is what stops
	# it drawing half a bonnet -- and then resolves whatever content declares for that, which today
	# is nothing. Both halves are asserted: the classification, and the graceful absence.
	var solo_map: Variant = _map_with_lows([Vector2i(4, 4)])
	if Dressing.segment_at(solo_map, 4, 4) != Dressing.SEG_SOLO:
		push_error("a Low tile with no Low neighbour resolved '%s', not solo" % Dressing.segment_at(solo_map, 4, 4))
		return false
	var declared_solo: String = String((block["wrecks"] as Dictionary).get("solo", ""))
	var solo_key: String = Dressing.wreck_key(block, solo_map, CANON_SEED, 4, 4)
	if solo_key != declared_solo:
		push_error("a lone Low tile resolved '%s' where content declares '%s'" % [solo_key, declared_solo])
		return false
	if declared_solo.is_empty():
		print("SEGMENTS SKIP content declares no `solo` picture, so a lone Low tile draws the procedural cover block -- the skip was drawn and cut with the worldgen change that would have stood more of them (docs/23). This half of the resolver went unjudged against real art.")
	if absf(Dressing.run_angle(solo_map, 4, 4)) > 0.0001:
		push_error("a lone wreck is drawn turned; it has no axis to be turned along")
		return false

	# A run of three, north to south: front, mid, rear, in that order and exactly one mid.
	var three: Variant = _map_with_lows([Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 5)])
	var want: Array[String] = [Dressing.SEG_FRONT, Dressing.SEG_MID, Dressing.SEG_REAR]
	for i in 3:
		var got: String = Dressing.segment_at(three, 6, 3 + i)
		if got != want[i]:
			push_error("tile %d of a three-tile north-south run resolved '%s', wanted '%s'" % [i, got, want[i]])
			return false
		if absf(Dressing.run_angle(three, 6, 3 + i)) > 0.0001:
			push_error("a north-south run is drawn turned; north is how the art is authored")
			return false

	# A run of two: front and rear, no mid at all -- the case that has to close up with no seam.
	var two: Variant = _map_with_lows([Vector2i(9, 8), Vector2i(9, 9)])
	if Dressing.segment_at(two, 9, 8) != Dressing.SEG_FRONT or Dressing.segment_at(two, 9, 9) != Dressing.SEG_REAR:
		push_error("a two-tile run resolved '%s'/'%s' rather than front/rear" % [Dressing.segment_at(two, 9, 8), Dressing.segment_at(two, 9, 9)])
		return false

	# East-west: the same three keys, the nose at the *east* end, and the quarter turn that puts
	# it there. Both halves matter -- the segments without the angle would draw a car across the
	# street facing up it.
	var across: Variant = _map_with_lows([Vector2i(3, 11), Vector2i(4, 11), Vector2i(5, 11)])
	var want_east: Array[String] = [Dressing.SEG_REAR, Dressing.SEG_MID, Dressing.SEG_FRONT]
	for i2 in 3:
		var got2: String = Dressing.segment_at(across, 3 + i2, 11)
		if got2 != want_east[i2]:
			push_error("tile %d of a three-tile east-west run resolved '%s', wanted '%s'" % [i2, got2, want_east[i2]])
			return false
		if absf(Dressing.run_angle(across, 3 + i2, 11) - PI / 2.0) > 0.0001:
			push_error("an east-west run resolved angle %f; the north-authored art turns a quarter circle clockwise" % Dressing.run_angle(across, 3 + i2, 11))
			return false

	# One car, one colour: every tile of a run has to agree on the variant, which is what the
	# anchor rule exists for. Compared through the resolved keys rather than through the index,
	# because the keys are what gets drawn.
	var families: Dictionary = {}
	for i3 in 3:
		families[_variant_of(block, Dressing.wreck_key(block, three, CANON_SEED, 6, 3 + i3))] = true
	if families.size() != 1:
		push_error("a three-tile car resolved %d different variants; the run anchor is not shared" % families.size())
		return false

	# The true negatives. A tile that is not Low is not a wreck, and neither is one off the map.
	for probe in [Vector2i(0, 0), Vector2i(6, 7), Vector2i(-1, 4), Vector2i(99, 99)]:
		var p: Vector2i = probe as Vector2i
		if not Dressing.segment_at(three, p.x, p.y).is_empty():
			push_error("tile %s is not a Low tile and resolved segment '%s'" % [str(p), Dressing.segment_at(three, p.x, p.y)])
			return false
		if not Dressing.wreck_key(block, three, CANON_SEED, p.x, p.y).is_empty():
			push_error("tile %s is not a Low tile and resolved a wreck key" % str(p))
			return false
	# A clump -- Low tiles meeting on both axes -- resolves the piece with no ends rather than
	# picking an axis it cannot have.
	var clump: Variant = _map_with_lows([Vector2i(7, 7), Vector2i(8, 7), Vector2i(7, 8)])
	if Dressing.segment_at(clump, 7, 7) != Dressing.SEG_MID:
		push_error("a Low tile with neighbours on both axes resolved '%s'; a corner has no ends" % Dressing.segment_at(clump, 7, 7))
		return false

	print("SEGMENTS OK a lone tile classifies solo, three-tile runs front/mid/rear both ways round, two-tile runs front/rear with no mid, east-west turned a quarter circle nose-east, one variant per run; non-Low, off-map and corner tiles all answered correctly")
	return true


# Which variant id a resolved key belongs to, or "" -- read out of the block so the gate does not
# repeat the key-naming convention the content owns.
func _variant_of(block: Dictionary, key: String) -> String:
	if key.is_empty():
		return ""
	var wrecks: Variant = block.get("wrecks")
	if not (wrecks is Dictionary):
		return ""
	var variants: Variant = (wrecks as Dictionary).get("variants")
	if not (variants is Array):
		return ""
	for entry in variants as Array:
		if not (entry is Dictionary):
			continue
		for segment in [Dressing.SEG_FRONT, Dressing.SEG_MID, Dressing.SEG_REAR]:
			if String((entry as Dictionary).get(segment, "")) == key:
				return String((entry as Dictionary).get("id", "?"))
	return ""


# --- 3. the variant is a pure hash -------------------------------------------------------------

func _the_variant_is_a_pure_hash(stash: Dictionary) -> bool:
	var count: int = 3
	var seen: Dictionary = {}
	for ty in 24:
		for tx in 24:
			var a: int = Dressing.variant_index(CANON_SEED, tx, ty, Dressing.SALT_VARIANT, count)
			if Dressing.variant_index(CANON_SEED, tx, ty, Dressing.SALT_VARIANT, count) != a:
				push_error("variant_index(%d,%d) answered two values in one process; the hash is not a hash" % [tx, ty])
				return false
			if a < 0 or a >= count:
				push_error("variant_index(%d,%d) answered %d, outside 0..%d" % [tx, ty, a, count - 1])
				return false
			seen[a] = true
	# Dead-variation negative: a constant would collapse this to one entry, and every car in the
	# district would be the same car.
	if seen.size() < 2:
		push_error("variant_index produced %d distinct values over 24x24 tiles; the variation is dead" % seen.size())
		return false
	# The seed has to reach it, or two districts are the same street.
	var moved: int = 0
	for ty2 in 24:
		for tx2 in 24:
			if Dressing.variant_index(CANON_SEED, tx2, ty2, Dressing.SALT_VARIANT, count) \
					!= Dressing.variant_index(CANON_SEED + 1, tx2, ty2, Dressing.SALT_VARIANT, count):
				moved += 1
	if moved == 0:
		push_error("no tile of a 24x24 sample changed variant between two seeds; the seed is not reaching the hash")
		return false
	# Nothing to pick from is answered, not indexed into.
	if Dressing.variant_index(CANON_SEED, 3, 3, Dressing.SALT_VARIANT, 0) != -1:
		push_error("variant_index with no variants must answer -1, not an index")
		return false
	# The salts have to be independent, or litter would land exactly where the rubble picks did.
	if Dressing.SALT_VARIANT == Dressing.SALT_LITTER_PICK or Dressing.SALT_LITTER_PICK == Dressing.SALT_LITTER_KEY:
		push_error("two dressing decisions share a hash salt; their choices would correlate")
		return false

	# The rule this file exists to keep: presentation draws no randomness. A stream here would
	# either sit on the sim registry (a draw the layout has to account for) or reseed per boot (a
	# district whose cars change colour when you load a save).
	var code: String = _code_of(DRESSING_GD)
	if code.is_empty():
		push_error("could not read %s -- the no-RNG assertion had nothing to judge" % DRESSING_GD)
		return false
	for forbidden in ["RngStream", "randi", "randf", "rng.", "static var"]:
		if code.contains(forbidden):
			push_error("%s contains '%s'; the dressing must be a pure function of the map, with no stream and no state shared between two booted worlds" % [DRESSING_GD, forbidden])
			return false

	print("VARIATION OK %d variants over 24x24 tiles, stable in-process, %d of 576 tiles move with the seed, empty variant list answers -1, salts distinct, and %s reaches for no RNG and holds no static state" % [seen.size(), moved, DRESSING_GD])
	return true


# --- 4. a booted district is actually dressed --------------------------------------------------

# Run lengths of the Low tiles on a map, as {length: count}. A run is scanned along whichever
# axis it lies on; a clump (both axes) is counted as its own thing and not as a length.
func _run_lengths(map: Variant) -> Dictionary:
	var out: Dictionary = {}
	var w: int = int(map.w)
	for ty in int(map.h):
		for tx in w:
			if int(SimTileMap.tile_at(map, tx, ty)) != SimTileMap.Tile.Low:
				continue
			var segment: String = Dressing.segment_at(map, tx, ty)
			if segment == Dressing.SEG_SOLO:
				out[1] = int(out.get(1, 0)) + 1
				continue
			# Count each run once, from its anchor.
			var anchor: Vector2i = Dressing.run_anchor(map, tx, ty)
			if anchor.x != tx or anchor.y != ty:
				continue
			var step := Vector2i(0, 1) if int(SimTileMap.tile_at(map, tx, ty + 1)) == SimTileMap.Tile.Low else Vector2i(1, 0)
			var length: int = 0
			var at := anchor
			while int(SimTileMap.tile_at(map, at.x, at.y)) == SimTileMap.Tile.Low and length < 16:
				length += 1
				at += step
			out[length] = int(out.get(length, 0)) + 1
	return out


func _a_booted_district_is_dressed(stash: Dictionary) -> bool:
	var block: Dictionary = stash["block"]
	var map: Variant = stash["map"]
	var low: int = 0
	var solo: int = 0
	var car: int = 0
	var not_low_dressed: int = 0
	for ty in int(map.h):
		for tx in int(map.w):
			var key: String = Dressing.wreck_key(block, map, CANON_SEED, tx, ty)
			if int(SimTileMap.tile_at(map, tx, ty)) != SimTileMap.Tile.Low:
				if not key.is_empty():
					not_low_dressed += 1
				continue
			low += 1
			if Dressing.segment_at(map, tx, ty) == Dressing.SEG_SOLO:
				# No picture is declared for a lone tile, so it must resolve nothing and fall back
				# to the procedural cover block -- not resolve a car segment it is too short for.
				solo += 1
				if not key.is_empty():
					push_error("lone Low tile (%d,%d) resolved '%s'; content declares no solo picture and a lone tile is not a car" % [tx, ty, key])
					return false
				continue
			car += 1
			if key.is_empty():
				push_error("Low tile (%d,%d) stands in a run and resolved no dressing key; it draws as the procedural block while every other one is a wreck" % [tx, ty])
				return false
			if Appearance.resolve(key) == null:
				push_error("Low tile (%d,%d) resolved key '%s', which has no file" % [tx, ty, key])
				return false
	if low == 0 or car == 0:
		push_error("the canonical seed at %d stood %d Low tiles, %d of them in a run; this lane had nothing to judge" % [GATE_SIZE, low, car])
		return false
	if not_low_dressed > 0:
		push_error("%d tiles that are not Low resolved a wreck key; the resolver is answering for the whole map" % not_low_dressed)
		return false
	stash["low"] = low
	stash["solo"] = solo
	stash["car"] = car

	# Every picture content declares has to be stood somewhere, or it is art nothing draws -- the
	# dead-socket rule applied to art. Measured at a size where the pass draws eight runs a map
	# instead of two, because "is the mid segment ever resolved" asked of one 64-tile district is
	# a question about four dice rolls.
	#
	# `solo` is the exception and is reported rather than asserted: no picture is declared for it,
	# and this lane says which of the four segments went unjudged instead of quietly counting to
	# three. That is the honest shape for it -- the skip was drawn, and cut with the worldgen
	# change that would have stood more lone tiles, because dressing may not move the simulation.
	var lengths: Dictionary = {}
	var drawn: Dictionary = {}
	for seed_val in SEEDS:
		var generated: Variant = SimWorldgen.generate(seed_val, RUN_SIZE, _tree())
		var seed_lengths: Dictionary = _run_lengths(generated)
		for length in seed_lengths.keys():
			lengths[length] = int(lengths.get(length, 0)) + int(seed_lengths[length])
		for ty2 in int(generated.h):
			for tx2 in int(generated.w):
				var segment: String = Dressing.segment_at(generated, tx2, ty2)
				if not segment.is_empty():
					drawn[segment] = int(drawn.get(segment, 0)) + 1
	# A `mid` that nothing ever resolves is three files a generator renders and no district draws,
	# which is exactly the state the seven prop sprites were in before this slice.
	for segment2 in [Dressing.SEG_FRONT, Dressing.SEG_MID, Dressing.SEG_REAR]:
		if int(drawn.get(segment2, 0)) == 0:
			push_error("no tile across %d seeds resolved the '%s' segment; that picture is art nothing draws" % [SEEDS.size(), segment2])
			return false
	if int(drawn.get(Dressing.SEG_SOLO, 0)) == 0:
		push_error("no lone Low tile across %d seeds; the solo classification is a branch nothing reaches" % SEEDS.size())
		return false
	print("DISTRICT SKIP %d lone Low tiles across the seeds resolve no picture: the skip that would have drawn them is cut (docs/23's what's-left), and they draw the procedural cover block." % int(drawn.get(Dressing.SEG_SOLO, 0)))

	print("DISTRICT OK %d Low tiles on the canonical %d map, %d of them in runs and every one resolving art, %d lone and correctly resolving none, no other tile dressed; across %d seeds at %d the run lengths are %s and every car segment is stood somewhere (%s)" % [
		low, GATE_SIZE, car, solo, SEEDS.size(), RUN_SIZE, str(lengths), str(drawn),
	])
	return true


# --- 5. the scatter ---------------------------------------------------------------------------

func _the_scatter_lands_where_the_ground_says(stash: Dictionary) -> bool:
	var block: Dictionary = stash["block"]
	var map: Variant = stash["map"]
	var w: int = int(map.w)
	var rubble_tiles: int = 0
	var rubble_drawn: int = 0
	var paved_tiles: int = 0
	var litter_drawn: int = 0
	for ty in int(map.h):
		for tx in w:
			var idx: int = ty * w + tx
			var floor_outdoors: bool = int(map.tiles[idx]) == SimTileMap.Tile.Floor and int(map.indoors[idx]) == 0
			var surface: int = int(SimSurface.surface_at(map, tx, ty))
			var rubble_key: String = Dressing.rubble_key(block, map, CANON_SEED, tx, ty)
			var litter_key: String = Dressing.litter_key(block, map, CANON_SEED, tx, ty)
			if floor_outdoors and surface == SimTileMap.SURFACE_RUBBLE:
				rubble_tiles += 1
				if rubble_key.is_empty():
					push_error("rubble tile (%d,%d) resolved no debris key; slice 2's rubble is still a flat tint there" % [tx, ty])
					return false
				rubble_drawn += 1
			elif not rubble_key.is_empty():
				push_error("tile (%d,%d) is not outdoor rubble floor and resolved rubble debris '%s'" % [tx, ty, rubble_key])
				return false
			if floor_outdoors and surface == SimTileMap.SURFACE_PAVED:
				paved_tiles += 1
				if not litter_key.is_empty():
					litter_drawn += 1
			elif not litter_key.is_empty():
				push_error("tile (%d,%d) is not outdoor street pavement and resolved litter '%s'" % [tx, ty, litter_key])
				return false
			for key in [rubble_key, litter_key]:
				if not String(key).is_empty() and Appearance.resolve(String(key)) == null:
					push_error("tile (%d,%d) resolved scatter key '%s', which has no file" % [tx, ty, String(key)])
					return false
	if rubble_tiles == 0 or paved_tiles == 0:
		push_error("the canonical seed has %d rubble and %d paved outdoor tiles; this lane had nothing to judge" % [rubble_tiles, paved_tiles])
		return false
	if rubble_drawn != rubble_tiles:
		push_error("%d of %d rubble tiles carry debris" % [rubble_drawn, rubble_tiles])
		return false
	if litter_drawn == 0:
		push_error("not one of %d paved tiles carries litter; the scatter is dead" % paved_tiles)
		return false
	# Sparse, or it stops being texture and becomes a surface. The rarity is 1 in
	# Dressing.LITTER_RARITY, so a quarter of the street is well past anything that could be a
	# hash landing unluckily.
	if float(litter_drawn) / float(paved_tiles) > 0.25:
		push_error("%d of %d paved tiles carry litter; scatter that dense is a ground texture, not debris" % [litter_drawn, paved_tiles])
		return false
	# Deterministic: the same tile answers the same thing, and a different seed moves the picks.
	var moved: int = 0
	for ty2 in int(map.h):
		for tx2 in w:
			var again: String = Dressing.litter_key(block, map, CANON_SEED, tx2, ty2)
			if again != Dressing.litter_key(block, map, CANON_SEED, tx2, ty2):
				push_error("litter at (%d,%d) answered two things in one process" % [tx2, ty2])
				return false
			if again != Dressing.litter_key(block, map, CANON_SEED + 7, tx2, ty2):
				moved += 1
	if moved == 0:
		push_error("no tile's litter moved between two seeds; the seed is not reaching the scatter")
		return false
	# True negatives, on a hand-built map so the assertion does not depend on the generator: a
	# grass tile and an indoor floor both carry nothing whatever the surface says.
	var bare: Variant = SimTileMap.blank_map(8, 8)
	var surfaces: PackedByteArray = bare.surfaces as PackedByteArray
	for i in surfaces.size():
		surfaces[i] = SimTileMap.SURFACE_GRASS
	surfaces[3 * 8 + 3] = SimTileMap.SURFACE_RUBBLE
	bare.surfaces = surfaces
	var indoors: PackedByteArray = bare.indoors as PackedByteArray
	indoors[3 * 8 + 3] = 1
	bare.indoors = indoors
	if not Dressing.litter_key(block, bare, CANON_SEED, 5, 5).is_empty():
		push_error("a grass tile resolved litter; the eligibility test is not reading the surface")
		return false
	if not Dressing.rubble_key(block, bare, CANON_SEED, 3, 3).is_empty():
		push_error("an indoor rubble tile resolved debris; a floor inside a building is not a street")
		return false
	# And a block declaring no scatter draws none rather than indexing an empty list.
	if not Dressing.litter_key({}, map, CANON_SEED, 0, 0).is_empty() or not Dressing.rubble_key({}, map, CANON_SEED, 0, 0).is_empty():
		push_error("an empty dressing block resolved scatter keys")
		return false

	stash["rubble"] = rubble_drawn
	stash["litter"] = litter_drawn
	print("SCATTER OK %d/%d rubble tiles carry debris, %d of %d paved tiles carry litter (1 in %d), deterministic with %d tiles moving on another seed; grass, indoor rubble and an empty block all draw nothing" % [
		rubble_drawn, rubble_tiles, litter_drawn, paved_tiles, Dressing.LITTER_RARITY, moved,
	])
	return true


# --- 6. the sockets ----------------------------------------------------------------------------

# The rule this milestone has paid for ten times: a resolver nothing calls is not a feature. A
# CanvasItem draw pass cannot run headless, so what it calls is read -- check_topdown's precedent.
func _the_sockets_are_wired() -> bool:
	var district: String = _function_body(MAIN_GD, "_draw_district")
	if district.is_empty():
		push_error("could not read _draw_district out of %s -- the reach assertion had nothing to judge" % MAIN_GD)
		return false
	for call in ["_draw_wreck(", "_draw_scatter(", "_dressing()"]:
		if not district.contains(call):
			push_error("_draw_district does not call %s; that half of the dressing resolves and draws nothing" % call)
			return false
	var wreck: String = _function_body(MAIN_GD, "_draw_wreck")
	if wreck.is_empty():
		push_error("could not read _draw_wreck out of %s" % MAIN_GD)
		return false
	for needed in ["Dressing.wreck_key(", "Dressing.run_angle(", "Appearance.resolve(", "draw_texture_rect(", "draw_set_transform_matrix(Transform2D.IDENTITY)"]:
		if not wreck.contains(needed):
			push_error("_draw_wreck does not contain %s; the wreck is resolved but not drawn, or drawn but not reset" % needed)
			return false
	var scatter: String = _function_body(MAIN_GD, "_draw_scatter")
	if scatter.is_empty():
		push_error("could not read _draw_scatter out of %s" % MAIN_GD)
		return false
	for needed2 in ["Dressing.rubble_key(", "Dressing.litter_key(", "draw_texture_rect("]:
		if not scatter.contains(needed2):
			push_error("_draw_scatter does not contain %s" % needed2)
			return false
	# The fallback stays a supported path: a district whose content declares no dressing still
	# draws the procedural cover block over its Low tiles.
	if not district.contains("if not _draw_wreck("):
		push_error("_draw_district draws the wreck unconditionally; a map with no dressing content would draw nothing over its Low tiles")
		return false
	print("SOCKETS OK _draw_district resolves the block once and hands both halves on; _draw_wreck reads the key, the angle and the texture and resets its transform by matrix; _draw_scatter reads both scatter resolvers; the procedural cover block survives as the fallback")
	return true


# --- the budget --------------------------------------------------------------------------------

func _the_gate_stayed_inside_its_own_budget(seconds: float) -> bool:
	if seconds > BUDGET_SECONDS:
		push_error("the wrecks gate took %.1f s against a %.0f s budget -- share boots between lanes rather than adding them" % [seconds, BUDGET_SECONDS])
		return false
	if seconds <= 0.0:
		push_error("the gate measured %.1f s of its own wall time, so the budget is measuring nothing" % seconds)
		return false
	print("BUDGET OK %.1f s of a %.0f s budget" % [seconds, BUDGET_SECONDS])
	return true


# A file's source with the comments taken out -- everything from the first `#` on a line to the
# end of it. The forbidden-name scan above has to read *code*: the file's own header explains why
# it uses no `randi`, and a scan that cannot tell an explanation from a call fails the file for
# documenting the rule it obeys. (No content file here puts a `#` inside a string; the two hex
# literals in presentation live in palette.gd, which this never reads.)
func _code_of(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var out: String = ""
	for line in f.get_as_text().split("\n"):
		var at: int = String(line).find("#")
		out += (String(line) if at < 0 else String(line).substr(0, at)) + "\n"
	return out


# The source text of one function, from its `func` line to the next top-level `func`.
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
