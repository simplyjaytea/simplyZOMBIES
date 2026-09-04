extends SceneTree
# The map dressing, and the cars parked in it. Slice 10 of the Dungeon Settlers arc ("the sedan is
# two by five"): a vehicle stopped being a run of Low tiles read off its neighbours and became a
# **manifest record**. `SimWorldgen._vehicles` parks `{x, y, w, h, axis, class, facing}` into
# `map.vehicles` and writes Tile.Low under the footprint; `presentation/dressing.gd` turns that
# record into one three-quarter picture per class x variant x axis; `main.gd::_draw_entities`
# stands it feet-anchored on the footprint's south edge, y-sorted with the bodies and the trees.
#
# The per-tile segment vocabulary retired with it -- `segment_at`, `run_angle`, `run_anchor`,
# `wreck_key`, the four SEG_ names, the nine `wreck_car_*` sprites, `main.gd::_draw_wreck` and the
# dressing block's `wrecks` key. SOCKETS asserts the names stay out of `dressing.gd` and `main.gd`,
# so the convention cannot grow back one helper at a time. A Low tile the
# manifest does not cover is now a **heap** of junk, one tile, hashed per tile out of the block's
# `heaps` list -- and that mutual exclusion is this slice's central new property: a Low tile is a
# car or a heap, never both, never neither, and it is the *draw loop's* branch that separates them
# rather than the resolver's, because `heap_key` answers for any Low tile at all.
#
# Nine lanes plus the budget, each with a true positive and a true negative, because a gate that
# cannot fail is worse than no gate:
#
#   DRESSING   the block is declared and every key in it resolves art at the canvas it is authored
#              on -- heaps at one tile, and every key every `content/vehicles/*.json` variant names
#              at its own `Appearance.canvas_of`. Refused for a fabricated key, a duplicated key
#              and an empty block.
#   MANIFEST   the whole record surface, on a HAND-BUILT map with a HAND-BUILT manifest, so not one
#              assertion here depends on a dice roll: `vehicle_index` marks exactly the footprint,
#              `vehicle_at` answers inside and VEHICLE_NONE outside/off-map/past the array end,
#              `vehicle_ground_point` is exact on both axes, `vehicle_key` is the axis's key and one
#              key for the whole car, `vehicle_records` is a subset of seen, `vehicle_flip` mirrors
#              only west. Refused for an unknown class, an unknown axis, a record hanging off the
#              map edge and a manifest that is not an Array.
#   VARIATION  the colour is a pure hash of the seed and the record's north-west corner:
#              deterministic in-process, alive, moving with the seed, and independent of the car's
#              extent and facing -- which is what "one variant for a whole car" means when the only
#              thing a per-tile hash could reach is the footprint. Heaps hash per tile instead.
#              Textually: dressing.gd reaches for no RNG and holds no static state, and the scanner
#              that says so is proven on a fabricated string first.
#   LAYOUT     a car is layout, not dressing: the same seed and size generated with `dress` true and
#              false carry IDENTICAL manifests, and the footprint is Tile.Low in both. That is the
#              property that says a car is not a picture.
#   PLACED     the generator actually parks them. Suburb at 128 over four seeds: cars on every map,
#              every footprint tile Low, none on a junction, a doorway or an indoor tile, every
#              record inside a carriageway with a kerb row free either side. Then the negative --
#              suburb at 64 stands exactly zero, and the lane asserts the *reason* (every street
#              there is narrower than VEHICLE_MIN_WIDTH), so a change that widens them says so
#              rather than passing quietly.
#   EXCLUSIVE  the mutual exclusion, over every Low tile of every parked district: covered by a
#              record, or resolving a heap -- never both, never neither. And textually, because the
#              exclusion is the branch's and not the resolver's: the Tile.Low arm of
#              `_draw_district` that DRAWS tests `Dressing.vehicle_at(` before it reaches
#              `_draw_heap(`. (Plural on purpose -- that loop matches on the tile class twice, and
#              a scanner that took the first arm read the colour pick and blamed the draw loop.)
#              The order scanner is proven on four fabricated bodies first. Then the graceful
#              absence, because a deferred tile is the one tile in this pipeline that could lose
#              it: a car whose class resolves no picture leaves its tiles heap-able, not blank.
#   HOST       the manifest's OTHER reader, on the sim side: an outdoor loot row declaring
#              `host: "vehicle"` stands its site on a car's tail tile where the district parked
#              one, and falls back to open driveway floor where it did not -- both branches with a
#              live shipped reader (the suburb at 128, and `forest_edge`, whose streets are too
#              narrow at any size). Refused for a site fabricated onto a nose tile and for one
#              fabricated onto a Low tile.
#   SCATTER    the loose stuff lands where the ground says and nowhere else, sparse and
#              deterministic. Unchanged by this slice and deliberately untouched.
#   SOCKETS    the dead-socket rule: every helper above is reached by something that draws, the
#              per-map accessor filters the undrawable records out, the procedural cover block
#              survives as the fallback, and the retired names are gone from both files. Every
#              scanner proven on a fabricated string first -- one that answers "present" for
#              everything is a gate that cannot fail.
#
# One thing this file deliberately says nothing about: a parked car does not take walkable ground
# away. `SimPath._footing` grants a non-Floor tile walkability while its surface is paved, so the
# footprint stays walk-through cover and a count of `Tile.Floor` is not a count of where a body can
# stand. Reachability is check_m2_district.gd's lane, and it still reports a walk over every
# outdoor tile with the cars in.
#
# The one boot is shared (check_worldgen's precedent) and the four parked districts and the one
# forest edge are generated once and cached; the budget lane at the bottom is what stops a later
# lane quietly adding another.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimSurface = preload("res://sim/map/surface.gd")
const SimWorldgen = preload("res://sim/map/worldgen.gd")
const SimBoot = preload("res://sim/boot.gd")
const Dressing = preload("res://presentation/dressing.gd")
const Appearance = preload("res://presentation/appearance.gd")
const CameraUtil = preload("res://presentation/camera.gd")
const ContentLoader = preload("res://platform/content_loader.gd")

const CANON_SEED: int = 20260805
const MAIN_GD: String = "res://presentation/main.gd"
const DRESSING_GD: String = "res://presentation/dressing.gd"

# The size every gate boots, and the size the suburb actually parks at. Both are load-bearing and
# neither is arbitrary: measured on the four seeds below, a 64-tile suburb carves its streets two
# tiles wide and a 128-tile one carves them five, so 64 is where the zero lives and 128 is where
# the cars do. PLACED asserts both halves and asserts the reason for the zero.
const GATE_SIZE: int = 64
const PARK_SIZE: int = 128

# Four rather than one: a claim about what the generator parks is a claim about the band the pass
# draws from, and one seed is an anecdote about a handful of dice rolls. Measured, the four stand
# 27 to 38 cars each at PARK_SIZE.
const SEEDS: Array[int] = [20260805, 404, 31337, 90210]

# The hand-built map the MANIFEST lane works on. Big enough to hold both axes of sedan clear of
# each other and of the edge, small enough to scan exhaustively.
const HAND_SIZE: int = 16

# The gate's own wall clock, docs/00 pillar 6. Measured 2.1 s on this container -- one playable
# boot at 64, eight district generations at 128, one town centre at 128 and one forest edge at 256,
# which is the single most expensive thing in here at ~0.7 s. The headroom is for a loaded CI box,
# not for new boots; three lanes share the four parked districts for exactly that reason.
const BUDGET_SECONDS: float = 60.0

const FOREST_ID: String = "district.forest_edge"
const TOWN_ID: String = "district.town_center"

# Where the `host: vehicle` fallback has a live shipped reader. `forest_edge` parks nothing at any
# size -- its streets come out 2 and 3 wide -- and its car-boot row declares `host: "vehicle"`
# anyway, so it is the district that exercises the driveway half. 256 rather than 128 because a
# per-district count is authored for a full district and scaled by area: one car boot survives the
# scaling at 256 and rounds to none at 128, so a smaller map would give the lane nothing to judge.
const FOREST_SIZE: int = 256
# `town_center` at the cheaper size: the assertion there is only about widths and the absent block.
const TOWN_SIZE: int = 128

var _tree_cache: Dictionary = {}
var _parked_cache: Array = []
var _forest_cache: Variant = null


# The whole interface `vehicle_records` asks an observer for: has_tile(tx, ty). A plain Dictionary
# of tiles rather than a booted shadowcast -- check_trees.gd's FakeSeen convention, reused for the
# same reason.
class FakeSeen extends RefCounted:
	var tiles: Dictionary = {}

	func has_tile(tx: int, ty: int) -> bool:
		return tiles.has(Vector2i(tx, ty))


# A map-shaped object whose `vehicles` is deliberately NOT an Array. `SimTileMap.vehicles` is a
# typed `Array`, so the engine itself refuses the assignment there -- and the manifest still
# arrives at `vehicle_index` as a Variant off a `map.get()`, which is the reader that has to cope.
# This is the only way to hand it the shape a fixture, an old save or a hand-written map could.
class LooseMap extends RefCounted:
	var w: int = 8
	var h: int = 8
	var vehicles: Variant = "not an array at all"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var started: int = Time.get_ticks_msec()
	var ok: bool = true
	var stash: Dictionary = {}

	ok = _boot(stash) and ok
	if ok:
		ok = _the_block_declares_working_art(stash) and ok
		ok = _the_manifest_answers_for_its_footprint_alone(stash) and ok
		ok = _the_colour_is_a_pure_hash_of_the_record(stash) and ok
		ok = _a_car_is_layout_and_not_dressing(stash) and ok
		ok = _the_generator_parks_them_lawfully(stash) and ok
		ok = _every_low_tile_is_a_car_or_a_heap(stash) and ok
		ok = _a_hosted_site_stands_on_a_car_or_falls_back(stash) and ok
		ok = _the_scatter_lands_where_the_ground_says(stash) and ok
		ok = _the_sockets_are_wired() and ok

	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	ok = _the_gate_stayed_inside_its_own_budget(seconds) and ok

	if ok:
		print("WRECKS_OK %d sprite keys resolve (%d of them vehicle pictures); the manifest answers for its footprint alone; the colour is one hash per record; the manifest is identical with dressing off; suburb@%d parked %d cars over %d seeds (%d..%d a map) and suburb@%d parked 0 because every street there is %d wide against a %d minimum; %d Low tiles covered by a record and %d heaped, never both and never neither; %d hosted sites stood on a car tail and %d fell back to a driveway; scatter on %d rubble and %d litter tiles; sockets wired and the segment names gone; %.1f s of a %.0f s budget" % [
			int(stash.get("keys", 0)), int(stash.get("vehicle_keys", 0)),
			PARK_SIZE, int(stash.get("parked", 0)), SEEDS.size(),
			int(stash.get("parked_min", 0)), int(stash.get("parked_max", 0)),
			GATE_SIZE, int(stash.get("narrow_width", 0)), SimWorldgen.VEHICLE_MIN_WIDTH,
			int(stash.get("covered", 0)), int(stash.get("heaped", 0)),
			int(stash.get("hosted_on_car", 0)), int(stash.get("hosted_fallback", 0)),
			int(stash.get("rubble", 0)), int(stash.get("litter", 0)),
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


# The four parked districts, generated once and shared by LAYOUT, PLACED and EXCLUSIVE. Cached
# because a 128-tile generation costs ~165 ms and three lanes want the same maps -- the budget lane
# at the bottom is what this cache exists to keep honest.
func _parked() -> Array:
	if _parked_cache.is_empty():
		for seed_val in SEEDS:
			_parked_cache.append(SimWorldgen.generate(seed_val, PARK_SIZE, _tree()))
	return _parked_cache


# The forest edge at full size: the shipped district that parks nothing and asks for a car boot
# anyway. Shared by PLACED (the width it parks nothing for) and HOST (the fallback it exercises),
# because a 256-tile generation is the single most expensive thing this gate does (~0.7 s).
func _forest() -> Variant:
	if _forest_cache == null:
		_forest_cache = SimWorldgen.generate(CANON_SEED, FOREST_SIZE, _tree(), FOREST_ID)
	return _forest_cache


# --- 1. DRESSING: the block declares art that exists -------------------------------------------

# The trouble with one sprite key, or "" when there is none. One predicate, so the fabricated
# negatives below are refused by exactly the rule the real keys pass.
func _key_problem(key: String, want: Vector2i) -> String:
	if key.is_empty():
		return "an empty key"
	if want == Vector2i.ZERO:
		return "'%s' names no canvas Appearance recognises" % key
	var texture: Texture2D = Appearance.resolve(key)
	if texture == null:
		return "'%s' resolves no texture; content names art nobody drew" % key
	if texture.get_size() != Vector2(want):
		return "'%s' decodes at %s but is authored on %s" % [key, str(texture.get_size()), str(want)]
	return ""


# The `ns`/`ew` keys one vehicle class declares, in variant order.
func _variant_keys(entry: Dictionary, axis: String) -> Array[String]:
	var out: Array[String] = []
	var look: Variant = entry.get("appearance")
	if not (look is Dictionary):
		return out
	var variants: Variant = (look as Dictionary).get("variants")
	if not (variants is Array):
		return out
	for raw in variants as Array:
		if raw is Dictionary:
			out.append(String((raw as Dictionary).get(axis, "")))
	return out


# Which variant id a key belongs to, or "" -- read out of content so the gate never repeats the
# key-naming convention the content owns.
func _variant_id_of(entry: Dictionary, key: String) -> String:
	var look: Variant = entry.get("appearance")
	if not (look is Dictionary):
		return ""
	var variants: Variant = (look as Dictionary).get("variants")
	if not (variants is Array):
		return ""
	for raw in variants as Array:
		if not (raw is Dictionary):
			continue
		var v: Dictionary = raw as Dictionary
		if String(v.get("ns", "")) == key or String(v.get("ew", "")) == key:
			return String(v.get("id", "?"))
	return ""


# The first key that appears twice in `keys`, or "". Proved on a fabricated list below: a duplicate
# detector that cannot say yes is a gate that cannot fail.
func _first_duplicate(keys: Array[String]) -> String:
	var seen: Dictionary = {}
	for key in keys:
		if seen.has(key):
			return key
		seen[key] = true
	return ""


func _the_block_declares_working_art(stash: Dictionary) -> bool:
	var block: Dictionary = stash["block"]
	var tile_canvas := Vector2i(int(CameraUtil.ART_NATIVE), int(CameraUtil.ART_NATIVE))
	var keys: Array[String] = []

	# The heaps: one tile each, and deliberately NOT vehicle pictures -- a heap is a tile of junk
	# and a car is a picture that stands in the entity sort, and the canvas is where the two part
	# company. A block that lost the list entirely is what the floor of one catches.
	var heaps: Variant = block.get("heaps")
	if not (heaps is Array) or (heaps as Array).size() < 1:
		push_error("the dressing block declares no `heaps` list; every Low tile no car covers would draw the procedural block and this slice's other half would be invisible")
		return false
	for raw in heaps as Array:
		var heap_key: String = String(raw)
		var problem: String = _key_problem(heap_key, Appearance.canvas_of(heap_key))
		if not problem.is_empty():
			push_error("dressing heap key: %s" % problem)
			return false
		if Appearance.canvas_of(heap_key) != tile_canvas:
			push_error("heap key '%s' is authored on %s, not the one %s tile a heap covers" % [heap_key, str(Appearance.canvas_of(heap_key)), str(tile_canvas)])
			return false
		if Appearance.vehicle_canvas(heap_key) != Vector2i.ZERO:
			push_error("heap key '%s' reads as a vehicle picture; a heap is one tile of junk, not a car" % heap_key)
			return false
		keys.append(heap_key)

	# The scatter, which this slice did not touch but which shares the block and the predicate.
	for field in ["litter", "rubble"]:
		var listed: Variant = block.get(field)
		if not (listed is Array) or (listed as Array).is_empty():
			push_error("the dressing block declares no `%s`; the scatter lane below would have nothing to judge" % field)
			return false
		for raw2 in listed as Array:
			var scrap: String = String(raw2)
			var problem2: String = _key_problem(scrap, Appearance.canvas_of(scrap))
			if not problem2.is_empty():
				push_error("dressing %s key: %s" % [field, problem2])
				return false
			keys.append(scrap)

	# Every picture every vehicle class names, at its own canvas. The nested walk is the point:
	# `godot:validate` checks that `appearance` is an object and never once looks inside it, so this
	# is where a typo in `vehicle_sedan_burnt_ew` stops being invisible -- and the canvas is derived
	# per class from its footprint, so a van whose picture was rendered at a sedan's size fails here
	# rather than drawing stretched.
	var classes: Array = SimWorldgen.vehicles_of(_tree())
	if classes.is_empty():
		push_error("content declares no vehicle classes at all; the whole slice would be a manifest nobody can fill")
		return false
	var vehicle_keys: int = 0
	for raw3 in classes:
		var entry: Dictionary = raw3 as Dictionary
		for axis in [Appearance.AXIS_NS, Appearance.AXIS_EW]:
			var listed2: Array[String] = _variant_keys(entry, String(axis))
			if listed2.is_empty():
				push_error("vehicle class %s declares no `%s` keys; half its variants would draw nothing" % [String(entry.get("id", "?")), String(axis)])
				return false
			for key in listed2:
				var want: Vector2i = Appearance.vehicle_canvas(key)
				var problem3: String = _key_problem(key, want)
				if not problem3.is_empty():
					push_error("vehicle key on %s: %s" % [String(entry.get("id", "?")), problem3])
					return false
				# The table and the deriver have to agree, or a picture that measures correctly
				# here would be blitted at another size by the draw loop.
				if Appearance.canvas_of(key) != want:
					push_error("canvas_of('%s') answers %s where vehicle_canvas answers %s" % [key, str(Appearance.canvas_of(key)), str(want)])
					return false
				keys.append(key)
				vehicle_keys += 1

	# Duplicated keys mean two decisions drawing one picture -- a burnt sedan and a pale one that
	# are the same file, or a heap that is also a scrap of litter.
	var dup: String = _first_duplicate(keys)
	if not dup.is_empty():
		push_error("the dressing and vehicle content name '%s' twice; two decisions cannot be one picture" % dup)
		return false

	# --- the true negatives, all through the predicates the real keys just passed ---
	if _first_duplicate(["a", "b", "a"] as Array[String]) != "a":
		push_error("the duplicate detector found no duplicate in a list built to contain one; it cannot say yes")
		return false
	# A key nobody authored. Both halves matter: a fabricated *heap* has no file, and a fabricated
	# *vehicle* variant is refused a canvas before the filesystem is even asked -- which is what
	# stops a hand-dropped PNG standing in for a class nobody declared.
	if _key_problem("low_heap_zz", Appearance.canvas_of("low_heap_zz")).is_empty():
		push_error("a fabricated heap key passed the key check; it is not reading the sprite directory")
		return false
	if Appearance.vehicle_canvas("vehicle_sedan_zz_ns") != Vector2i.ZERO:
		push_error("a fabricated variant resolved a vehicle canvas; an unknown variant must fall through")
		return false
	if _key_problem("vehicle_sedan_zz_ns", Appearance.vehicle_canvas("vehicle_sedan_zz_ns")).is_empty():
		push_error("a fabricated vehicle key passed the key check")
		return false
	# And a block that declares nothing resolves nothing rather than falling through to a default.
	var hand: Variant = _hand_map()
	if not Dressing.heap_key({}, hand, CANON_SEED, 3, 2).is_empty():
		push_error("an empty dressing block resolved a heap key; absence must be graceful, not defaulted")
		return false
	if not Dressing.heap_key({"heaps": []}, hand, CANON_SEED, 3, 2).is_empty():
		push_error("an empty `heaps` list resolved a key rather than answering nothing")
		return false

	stash["keys"] = keys.size()
	stash["vehicle_keys"] = vehicle_keys
	print("DRESSING OK %d keys resolve: %d heaps at %s, %d scatter scraps, %d vehicle pictures at their own derived canvases, no duplicates; a fabricated heap key, a fabricated variant, an empty block and an empty list are all refused" % [
		keys.size(), (heaps as Array).size(), str(tile_canvas), keys.size() - (heaps as Array).size() - vehicle_keys, vehicle_keys,
	])
	return true


# --- 2. MANIFEST: the record answers for its footprint and nothing else -------------------------

# The hand-built map every assertion in this lane stands on: HAND_SIZE square, Floor everywhere,
# two parked sedans in the manifest and Tile.Low written under both -- one on each axis, clear of
# each other and of the edge. Never the generator: a property of the record shape must not depend
# on a dice roll.
func _hand_map() -> Variant:
	var map: Variant = SimTileMap.blank_map(HAND_SIZE, HAND_SIZE)
	map.vehicles = [
		{"x": 3, "y": 2, "w": 2, "h": 5, "axis": "ns", "class": "vehicle.sedan", "facing": "n"},
		{"x": 8, "y": 9, "w": 5, "h": 2, "axis": "ew", "class": "vehicle.sedan", "facing": "w"},
	]
	# Whole-array write: packed arrays are values, and an element write through the property would
	# land on a copy (CLAUDE.md's first trap).
	var tiles: PackedByteArray = map.tiles as PackedByteArray
	for record in map.vehicles as Array:
		var r: Dictionary = record as Dictionary
		for dy in int(r["h"]):
			for dx in int(r["w"]):
				tiles[(int(r["y"]) + dy) * HAND_SIZE + int(r["x"]) + dx] = SimTileMap.Tile.Low
	map.tiles = tiles
	return map


func _the_manifest_answers_for_its_footprint_alone(stash: Dictionary) -> bool:
	var world: Variant = stash["world"]
	var map: Variant = _hand_map()
	var records: Array = map.vehicles as Array
	var index: PackedInt32Array = Dressing.vehicle_index(map)

	if index.size() != HAND_SIZE * HAND_SIZE:
		push_error("vehicle_index answered %d ints for a %dx%d map" % [index.size(), HAND_SIZE, HAND_SIZE])
		return false

	# Exactly the footprint and nothing else. Counted two ways -- every tile of every record carries
	# that record's own index, and the total marked equals the summed footprints -- so a footprint
	# written one tile short fails the first and a record that overwrote another fails the second.
	var want: int = 0
	for i in records.size():
		var r: Dictionary = records[i] as Dictionary
		want += int(r["w"]) * int(r["h"])
		for dy in int(r["h"]):
			for dx in int(r["w"]):
				var tx: int = int(r["x"]) + dx
				var ty: int = int(r["y"]) + dy
				if Dressing.vehicle_at(index, map, tx, ty) != i:
					push_error("tile (%d,%d) is inside record %d's footprint and vehicle_at answered %d; the index does not cover the car" % [tx, ty, i, Dressing.vehicle_at(index, map, tx, ty)])
					return false
	var marked: int = 0
	for i2 in index.size():
		if int(index[i2]) != Dressing.VEHICLE_NONE:
			marked += 1
	if marked != want:
		push_error("vehicle_index marked %d tiles for %d tiles of footprint; the manifest and the index disagree about what a car covers" % [marked, want])
		return false

	# Outside: the ring around a car, off the map on all four sides, and past the end of a short
	# index array -- which is what a stale cache handed to a bigger map looks like.
	for probe in [Vector2i(2, 2), Vector2i(5, 4), Vector2i(3, 1), Vector2i(3, 7), Vector2i(8, 8), Vector2i(13, 9)]:
		var p: Vector2i = probe as Vector2i
		if Dressing.vehicle_at(index, map, p.x, p.y) != Dressing.VEHICLE_NONE:
			push_error("tile %s is outside every footprint and vehicle_at answered %d" % [str(p), Dressing.vehicle_at(index, map, p.x, p.y)])
			return false
	for off in [Vector2i(-1, 4), Vector2i(4, -1), Vector2i(HAND_SIZE, 4), Vector2i(4, HAND_SIZE)]:
		var o: Vector2i = off as Vector2i
		if Dressing.vehicle_at(index, map, o.x, o.y) != Dressing.VEHICLE_NONE:
			push_error("off-map tile %s answered a record" % str(o))
			return false
	var short := PackedInt32Array([0, 0, 0])
	if Dressing.vehicle_at(short, map, HAND_SIZE - 1, HAND_SIZE - 1) != Dressing.VEHICLE_NONE:
		push_error("a tile past the end of a short index answered a record rather than VEHICLE_NONE")
		return false

	# Where the picture stands: the centre of the footprint's south edge, exactly, on both axes.
	# A north-south sedan at (3,2) 2x5 stands at (4.0, 7.0); an east-west one at (8,9) 5x2 stands at
	# (10.5, 11.0) -- the half tile is the point, because a 5-wide body has no centre column.
	var gp_ns: Vector2 = Dressing.vehicle_ground_point(records[0] as Dictionary)
	var gp_ew: Vector2 = Dressing.vehicle_ground_point(records[1] as Dictionary)
	if gp_ns != Vector2(4.0, 7.0) or gp_ew != Vector2(10.5, 11.0):
		push_error("vehicle_ground_point answered %s and %s, wanted (4, 7) and (10.5, 11)" % [str(gp_ns), str(gp_ew)])
		return false

	# One key for the whole car, and the axis picks which of the variant's two it is. Asked through
	# the index, tile by tile, because that is the question a two-colour car would answer wrongly.
	var entry: Dictionary = Appearance.entry_of(world, "vehicle", "vehicle.sedan")
	if entry.is_empty():
		push_error("no vehicle.sedan in the booted world's content; this lane had nothing to judge")
		return false
	var ns_keys: Array[String] = _variant_keys(entry, Appearance.AXIS_NS)
	var ew_keys: Array[String] = _variant_keys(entry, Appearance.AXIS_EW)
	for i3 in records.size():
		var r2: Dictionary = records[i3] as Dictionary
		var per_tile: Dictionary = {}
		for dy2 in int(r2["h"]):
			for dx2 in int(r2["w"]):
				var at: int = Dressing.vehicle_at(index, map, int(r2["x"]) + dx2, int(r2["y"]) + dy2)
				per_tile[Dressing.vehicle_key(world, records[at] as Dictionary, CANON_SEED)] = true
		if per_tile.size() != 1:
			push_error("record %d resolved %d different keys over its own footprint (%s); a car is one picture" % [i3, per_tile.size(), str(per_tile.keys())])
			return false
		var key: String = String(per_tile.keys()[0])
		var wanted: Array[String] = ns_keys if String(r2["axis"]) == Appearance.AXIS_NS else ew_keys
		if not wanted.has(key):
			push_error("a record on the '%s' axis resolved '%s', which is not one of that axis's keys" % [String(r2["axis"]), key])
			return false

	# The teeth under "one key for the whole car": hashing the same car per tile really would give
	# it two colours here, so the assertion above is a claim with content rather than one a constant
	# would satisfy. If this ever stops being true the lane says so instead of passing quietly.
	var as_tiles: Dictionary = {}
	var first: Dictionary = records[0] as Dictionary
	for dy3 in int(first["h"]):
		for dx3 in int(first["w"]):
			as_tiles[Dressing.vehicle_key(world, {
				"x": int(first["x"]) + dx3, "y": int(first["y"]) + dy3,
				"w": int(first["w"]), "h": int(first["h"]),
				"axis": String(first["axis"]), "class": String(first["class"]),
			}, CANON_SEED)] = true
	if as_tiles.size() < 2:
		push_error("hashing this car per tile would have given it one colour anyway, so the per-record rule is unjudged here; move the fixture car until the per-tile hash disagrees with itself")
		return false

	# Which way it is shown. Only west mirrors: the east-west picture is authored nose-east, and the
	# north-south picture is the one both vertical facings draw (Appearance.vehicle_flip records
	# why decision 11 does not buy a second one).
	if Appearance.vehicle_flip("w") != -1.0:
		push_error("vehicle_flip('w') answered %.1f; a west-facing car is the east picture mirrored" % Appearance.vehicle_flip("w"))
		return false
	for facing in ["n", "s", "e"]:
		if Appearance.vehicle_flip(String(facing)) != 1.0:
			push_error("vehicle_flip('%s') answered %.1f; only west mirrors" % [String(facing), Appearance.vehicle_flip(String(facing))])
			return false

	# Draw is a subset of seen: any footprint tile seen inside the visible box shows the whole car,
	# a car nobody sees shows nothing, and no observer at all shows nothing.
	var box: Dictionary = {"minX": 0.0, "maxX": float(HAND_SIZE - 1), "minY": 0.0, "maxY": float(HAND_SIZE - 1)}
	var sees_all := FakeSeen.new()
	for ty2 in HAND_SIZE:
		for tx2 in HAND_SIZE:
			sees_all.tiles[Vector2i(tx2, ty2)] = true
	if Dressing.vehicle_records(map, sees_all, box).size() != records.size():
		push_error("a see-everything observer drew %d of %d records" % [Dressing.vehicle_records(map, sees_all, box).size(), records.size()])
		return false
	var sees_corner := FakeSeen.new()
	sees_corner.tiles[Vector2i(4, 6)] = true  # one tile of the first car's tail, and nothing else
	var corner: Array[int] = Dressing.vehicle_records(map, sees_corner, box)
	if corner != ([0] as Array[int]):
		push_error("an observer seeing one tile of the first car drew %s; a bonnet past a wall is a car you can see, and nothing else is" % str(corner))
		return false
	if not Dressing.vehicle_records(map, null, box).is_empty():
		push_error("a null observer drew a car; nobody sees no cars")
		return false
	if not Dressing.vehicle_records(map, sees_all, {"minX": 0.0, "maxX": 1.0, "minY": 0.0, "maxY": 1.0}).is_empty():
		push_error("a visible box holding no footprint tile still drew a car")
		return false

	# --- the true negatives ---
	if not Dressing.vehicle_key(world, {"x": 3, "y": 2, "axis": "ns", "class": "vehicle.hovercraft"}, CANON_SEED).is_empty():
		push_error("a record naming a class nobody declared resolved a key; an unknown class draws nothing, not a default car")
		return false
	if not Dressing.vehicle_key(world, {"x": 3, "y": 2, "axis": "up", "class": "vehicle.sedan"}, CANON_SEED).is_empty():
		push_error("a record on an axis no variant declares resolved a key; that is half a car")
		return false
	# A record hanging off the map edge is clipped, not written out of bounds and not a crash.
	var edge: Variant = SimTileMap.blank_map(HAND_SIZE, HAND_SIZE)
	edge.vehicles = [{"x": HAND_SIZE - 2, "y": HAND_SIZE - 3, "w": 2, "h": 5, "axis": "ns", "class": "vehicle.sedan", "facing": "n"}]
	var clipped: PackedInt32Array = Dressing.vehicle_index(edge)
	var inside: int = 0
	for i4 in clipped.size():
		if int(clipped[i4]) != Dressing.VEHICLE_NONE:
			inside += 1
	if clipped.size() != HAND_SIZE * HAND_SIZE or inside != 6:
		push_error("a record hanging 2 tiles off the south edge marked %d tiles of a %d-int index; wanted 6 of %d" % [inside, clipped.size(), HAND_SIZE * HAND_SIZE])
		return false
	# A manifest that is not an Array is absence, not a crash and not a guess.
	var loose := LooseMap.new()
	var loose_index: PackedInt32Array = Dressing.vehicle_index(loose)
	if loose_index.size() != loose.w * loose.h:
		push_error("a map whose manifest is not an Array answered a %d-int index for %d tiles" % [loose_index.size(), loose.w * loose.h])
		return false
	for i5 in loose_index.size():
		if int(loose_index[i5]) != Dressing.VEHICLE_NONE:
			push_error("a map whose manifest is not an Array marked tile %d as covered" % i5)
			return false
	if not Dressing.vehicle_records(loose, sees_all, box).is_empty():
		push_error("a map whose manifest is not an Array drew a car")
		return false
	if not Dressing.vehicle_index(null).is_empty():
		push_error("vehicle_index(null) answered an index rather than nothing")
		return false

	print("MANIFEST OK %d records mark %d tiles and nothing else on a hand-built %dx%d map; vehicle_at says none outside, off-map and past a short index; ground points (4, 7) and (10.5, 11) exact; one key per car over its whole footprint (a per-tile hash would have given %d); only 'w' mirrors; draw is a subset of seen; an unknown class, an unknown axis, an off-edge record and a non-Array manifest all answer nothing" % [
		records.size(), marked, HAND_SIZE, HAND_SIZE, as_tiles.size(),
	])
	return true


# --- 3. VARIATION: the colour is a pure hash of the record --------------------------------------

# The first forbidden name present in `code`, or "". Proved on a fabricated string below -- a
# scanner that answers "" for everything is a gate that cannot fail.
func _first_forbidden(code: String, forbidden: Array) -> String:
	for name in forbidden:
		if code.contains(String(name)):
			return String(name)
	return ""


func _the_colour_is_a_pure_hash_of_the_record(stash: Dictionary) -> bool:
	var world: Variant = stash["world"]
	var block: Dictionary = stash["block"]

	# Deterministic in-process, alive over the corners a district could park on, and moving with
	# the seed -- or two districts are the same street.
	var seen: Dictionary = {}
	var moved: int = 0
	for ry in 24:
		for rx in 24:
			var record: Dictionary = {"x": rx, "y": ry, "w": 2, "h": 5, "axis": "ns", "class": "vehicle.sedan", "facing": "n"}
			var key: String = Dressing.vehicle_key(world, record, CANON_SEED)
			if key.is_empty():
				push_error("a sedan at (%d,%d) resolved no key at all" % [rx, ry])
				return false
			if Dressing.vehicle_key(world, record, CANON_SEED) != key:
				push_error("vehicle_key answered two values for one record in one process; the hash is not a hash")
				return false
			seen[key] = true
			if Dressing.vehicle_key(world, record, CANON_SEED + 1) != key:
				moved += 1
	if seen.size() < 2:
		push_error("576 record corners produced %d distinct pictures; the variation is dead and every car in the district is the same car" % seen.size())
		return false
	if moved == 0:
		push_error("no record corner of a 24x24 sample changed picture between two seeds; the seed is not reaching the hash")
		return false

	# One variant for a whole car, stated as the property that makes it true: the pick reads the
	# record's north-west corner and NOTHING that varies across the car. Two records on one corner
	# with different extents and different facings are the same paint job -- which a hash that had
	# wandered onto a tile, a size or a heading could not be.
	var a: String = Dressing.vehicle_key(world, {"x": 6, "y": 4, "w": 2, "h": 5, "axis": "ns", "class": "vehicle.sedan", "facing": "n"}, CANON_SEED)
	var b: String = Dressing.vehicle_key(world, {"x": 6, "y": 4, "w": 2, "h": 9, "axis": "ns", "class": "vehicle.sedan", "facing": "s"}, CANON_SEED)
	if a != b or a.is_empty():
		push_error("two records on one corner resolved '%s' and '%s'; the pick is reading the car's extent or its heading, not the car" % [a, b])
		return false
	# And the two axes of one corner are the same paint job in two pictures, which is what says the
	# axis chooses the key while the corner chooses the variant.
	var entry: Dictionary = Appearance.entry_of(world, "vehicle", "vehicle.sedan")
	var across: String = Dressing.vehicle_key(world, {"x": 6, "y": 4, "w": 5, "h": 2, "axis": "ew", "class": "vehicle.sedan", "facing": "e"}, CANON_SEED)
	if across == a:
		push_error("the two axes of one corner resolved the same key '%s'; a car seen from the side is a different picture" % a)
		return false
	if _variant_id_of(entry, across) != _variant_id_of(entry, a) or _variant_id_of(entry, a).is_empty():
		push_error("the two axes of one corner resolved variants '%s' and '%s'; the corner picks the paint and the axis picks the picture" % [_variant_id_of(entry, a), _variant_id_of(entry, across)])
		return false

	# Heaps hash per tile, which is the opposite rule and the right one: a heap is one tile of junk
	# with no run to agree with, so two Low tiles side by side may be different heaps.
	var hand: Variant = _hand_map()
	var heaps: Dictionary = {}
	var heap_moved: int = 0
	for record2 in hand.vehicles as Array:
		var r: Dictionary = record2 as Dictionary
		for dy in int(r["h"]):
			for dx in int(r["w"]):
				var tx: int = int(r["x"]) + dx
				var ty: int = int(r["y"]) + dy
				var key2: String = Dressing.heap_key(block, hand, CANON_SEED, tx, ty)
				if key2.is_empty():
					push_error("Low tile (%d,%d) resolved no heap at all" % [tx, ty])
					return false
				heaps[key2] = true
				if Dressing.heap_key(block, hand, CANON_SEED + 1, tx, ty) != key2:
					heap_moved += 1
	if heaps.size() < 2:
		push_error("every Low tile of the hand map took the same heap; the heap variation is dead")
		return false
	if heap_moved == 0:
		push_error("no Low tile changed heap between two seeds; the seed is not reaching the heap hash")
		return false

	# One salt per independent decision, or two choices about the same tile would correlate: the
	# heaps would land exactly where the litter picks did, and a car's paint would track its
	# ground's variant.
	var salts: Array[int] = [
		Dressing.SALT_HEAP, Dressing.SALT_LITTER_PICK, Dressing.SALT_LITTER_KEY,
		Dressing.SALT_RUBBLE_KEY, Dressing.SALT_GROUND, Dressing.SALT_TREE, Dressing.SALT_VEHICLE,
	]
	var salt_seen: Dictionary = {}
	for salt in salts:
		if salt_seen.has(salt):
			push_error("two dressing decisions share hash salt %d; their choices would correlate" % salt)
			return false
		salt_seen[salt] = true

	# The rule this file exists to keep: presentation draws no randomness. A stream here would
	# either sit on the sim registry (a draw the layout has to account for) or reseed per boot (a
	# district whose cars change colour when you load a save), and a static var would be shared
	# between the two worlds one gate process boots.
	var forbidden: Array = ["RngStream", "randi", "randf", "rng.", "static var"]
	if _first_forbidden("var rng = RngStream.new()", forbidden) != "RngStream":
		push_error("the forbidden-name scanner found nothing in a string built to contain a stream; it cannot say yes")
		return false
	var code: String = _code_of(DRESSING_GD)
	if code.is_empty():
		push_error("could not read %s -- the no-RNG assertion had nothing to judge" % DRESSING_GD)
		return false
	var found: String = _first_forbidden(code, forbidden)
	if not found.is_empty():
		push_error("%s contains '%s'; the dressing must be a pure function of the map, with no stream and no state shared between two booted worlds" % [DRESSING_GD, found])
		return false

	print("VARIATION OK %d distinct pictures over 576 record corners, %d of them moving with the seed, the pick blind to extent and heading and the two axes one paint job; heaps hash per tile (%d pictures, %d moving); %d salts distinct; %s reaches for no RNG and holds no static state, and the scanner that says so was proved on a fabricated stream" % [
		seen.size(), moved, heaps.size(), heap_moved, salts.size(), DRESSING_GD,
	])
	return true


# --- 4. LAYOUT: a car is layout, not dressing ---------------------------------------------------

# Whether two manifests are the same manifest, field for field -- the index of the first record
# that differs, or -1. Compared by field rather than by `==` on the Dictionaries so the message can
# say which record and so a key added on one side is a difference rather than a silent pass.
func _manifest_difference(a: Array, b: Array) -> int:
	if a.size() != b.size():
		return mini(a.size(), b.size())
	for i in a.size():
		var ra: Dictionary = a[i] as Dictionary
		var rb: Dictionary = b[i] as Dictionary
		if ra.keys().size() != rb.keys().size():
			return i
		for key in ra.keys():
			# `str()` rather than `String()`: a record's fields are ints and Strings together, and
			# Godot 4 has no String(int) constructor -- the call raises rather than converting.
			if not rb.has(key) or str(ra[key]) != str(rb[key]):
				return i
	return -1


func _a_car_is_layout_and_not_dressing(stash: Dictionary) -> bool:
	var judged: int = 0
	for i in SEEDS.size():
		var dressed: Variant = _parked()[i]
		var bare: Variant = SimWorldgen.generate(SEEDS[i], PARK_SIZE, _tree(), SimWorldgen.DEFAULT_DISTRICT, false)
		var parked: Array = dressed.vehicles as Array
		var unparked: Array = bare.vehicles as Array
		if parked.is_empty():
			push_error("seed %d parked nothing at %d, so the independence claim has nothing to compare" % [SEEDS[i], PARK_SIZE])
			return false
		var at: int = _manifest_difference(parked, unparked)
		if at >= 0:
			push_error("seed %d: the manifest differs at record %d with the dressing off (%d records dressed, %d bare); a car that moves when the trees are switched off is a picture, not layout" % [
				SEEDS[i], at, parked.size(), unparked.size(),
			])
			return false
		# And the tiles under it are Low in both, which is the other half: the record is only a
		# record if the cover it stands for is there without the dressing pass.
		for record in unparked:
			var r: Dictionary = record as Dictionary
			for dy in int(r["h"]):
				for dx in int(r["w"]):
					var tx: int = int(r["x"]) + dx
					var ty: int = int(r["y"]) + dy
					if int(SimTileMap.tile_at(bare, tx, ty)) != SimTileMap.Tile.Low:
						push_error("seed %d: footprint tile (%d,%d) is not Low with the dressing off; the cover a car stands for came from a dressing pass" % [SEEDS[i], tx, ty])
						return false
		judged += parked.size()
	# The negative for the comparator itself: two manifests that differ must be reported as
	# differing, or this lane would pass on any pair at all.
	if _manifest_difference([{"x": 1}], [{"x": 2}]) != 0:
		push_error("the manifest comparator called two different records identical; it cannot say no")
		return false
	if _manifest_difference([{"x": 1}], []) != 0:
		push_error("the manifest comparator called a manifest of one identical to an empty one")
		return false
	print("LAYOUT OK %d records over %d seeds at %d are identical with `dress` true and false, and every footprint tile is Low in both; the comparator refuses two manifests that differ" % [judged, SEEDS.size(), PARK_SIZE])
	return true


# --- 5. PLACED: the generator parks them, lawfully ----------------------------------------------

# Every doorway and the ground immediately outside it, as tile indices. The half of
# `SimWorldgen._protected_tiles` a finished map can be asked about: the annex reserve is not
# reconstructible once the generator has returned, and the loot sites deliberately are NOT in here
# because a `host: vehicle` site stands on a car's boot on purpose (`_vehicle_tails`).
func _doorway_tiles(map: Variant) -> Dictionary:
	var out: Dictionary = {}
	var w: int = int(map.w)
	for record in map.buildings as Array:
		for door in (record as Dictionary)["doors"] as Array:
			var d: Dictionary = door as Dictionary
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var tx: int = int(d["x"]) + dx
					var ty: int = int(d["y"]) + dy
					if tx < 0 or ty < 0 or tx >= w or ty >= int(map.h):
						continue
					out[ty * w + tx] = true
	return out


# The street span a record is parked in, or {} -- the vertical spans for a north-south car and the
# horizontal ones for an east-west car, and the record has to lie inside the span both ways.
func _span_of(map: Variant, r: Dictionary) -> Dictionary:
	var vertical: bool = String(r.get("axis", "")) == Appearance.AXIS_NS
	for street in map.streets as Array:
		var span: Dictionary = street as Dictionary
		if (String(span.get("axis", "x")) == "x") != vertical:
			continue
		var at: int = int(span.get("at", 0))
		var width: int = int(span.get("width", 0))
		var from: int = int(span.get("from", 0))
		var to: int = int(span.get("to", 0))
		var across: int = int(r["x"]) if vertical else int(r["y"])
		var across_end: int = across + (int(r["w"]) if vertical else int(r["h"]))
		var along: int = int(r["y"]) if vertical else int(r["x"])
		var along_end: int = along + (int(r["h"]) if vertical else int(r["w"])) - 1
		if across >= at and across_end <= at + width and along >= from and along_end <= to:
			return span
	return {}


func _the_generator_parks_them_lawfully(stash: Dictionary) -> bool:
	var total: int = 0
	var least: int = 1 << 30
	var most: int = 0
	var junction_probed: bool = false
	for i in SEEDS.size():
		var map: Variant = _parked()[i]
		var records: Array = map.vehicles as Array
		if records.is_empty():
			push_error("seed %d parked no cars at %d, where the streets are wide enough for them" % [SEEDS[i], PARK_SIZE])
			return false
		total += records.size()
		least = mini(least, records.size())
		most = maxi(most, records.size())
		var doors: Dictionary = _doorway_tiles(map)
		var surface: int = SimWorldgen.street_surface_of(SimWorldgen.district_of(_tree(), SimWorldgen.DEFAULT_DISTRICT))
		for record in records:
			var r: Dictionary = record as Dictionary
			var street_axis: String = "x" if String(r["axis"]) == Appearance.AXIS_NS else "y"
			for dy in int(r["h"]):
				for dx in int(r["w"]):
					var tx: int = int(r["x"]) + dx
					var ty: int = int(r["y"]) + dy
					var idx: int = ty * int(map.w) + tx
					if int(SimTileMap.tile_at(map, tx, ty)) != SimTileMap.Tile.Low:
						push_error("seed %d: footprint tile (%d,%d) is %d, not Low; a parked car is cover you can shoot over" % [SEEDS[i], tx, ty, int(SimTileMap.tile_at(map, tx, ty))])
						return false
					if int(map.indoors[idx]) != 0:
						push_error("seed %d: a car is parked indoors at (%d,%d)" % [SEEDS[i], tx, ty])
						return false
					if int(map.surfaces[idx]) != surface:
						push_error("seed %d: the car at (%d,%d) stands on surface %d, not the district's street surface %d -- that is somebody's garden" % [SEEDS[i], tx, ty, int(map.surfaces[idx]), surface])
						return false
					if doors.has(idx):
						push_error("seed %d: a car at (%d,%d) blocks a doorway or the ground outside it" % [SEEDS[i], tx, ty])
						return false
					if SimWorldgen._on_crossing(map, tx, ty, street_axis):
						push_error("seed %d: a car at (%d,%d) stands in a junction, the one place two routes meet" % [SEEDS[i], tx, ty])
						return false
			# Inside a carriageway with a kerb row free either side: offset 0 is the near kerb and
			# width-1 the far one, so a 2-wide body may only start at 1..width-3.
			var span: Dictionary = _span_of(map, r)
			if span.is_empty():
				push_error("seed %d: the car at (%d,%d) lies in no street span of its own axis" % [SEEDS[i], int(r["x"]), int(r["y"])])
				return false
			var at2: int = int(span["at"])
			var width2: int = int(span["width"])
			var near: int = (int(r["x"]) if String(r["axis"]) == Appearance.AXIS_NS else int(r["y"])) - at2
			var far: int = near + (int(r["w"]) if String(r["axis"]) == Appearance.AXIS_NS else int(r["h"]))
			if near < 1 or far > width2 - 1:
				push_error("seed %d: the car at (%d,%d) sits at lane offsets %d..%d of a %d-wide street; a kerb row must stay free on each side" % [
					SEEDS[i], int(r["x"]), int(r["y"]), near, far - 1, width2,
				])
				return false
		# The junction scanner has to be able to say yes, or "no car on a junction" is a claim
		# nothing could ever fail. Every district has crossings; find one and prove it.
		if not junction_probed:
			for street in map.streets as Array:
				var s: Dictionary = street as Dictionary
				if String(s.get("axis", "x")) != "x":
					continue
				if SimWorldgen._on_crossing(map, int(s["at"]), int(s["from"]), "x"):
					junction_probed = true
					break
	if not junction_probed:
		push_error("no tile of any generated district read as a junction; the crossing scanner cannot say yes and the assertion above is judging nothing")
		return false

	# The true negative, and the whole reason GATE_SIZE is where it is: at 64 the suburb's streets
	# come out too narrow to park in, so the pass never touches its stream and the district stands
	# exactly zero cars. The REASON is asserted, not just the count -- if a later change widens the
	# 64-tile streets this lane says so rather than silently passing on a zero that has stopped
	# being true.
	var narrow: Variant = stash["map"]
	var widest: int = 0
	for street2 in narrow.streets as Array:
		widest = maxi(widest, int((street2 as Dictionary).get("width", 0)))
	if widest <= 0:
		push_error("the %d-tile district carved no streets at all; the zero below would be a zero for the wrong reason" % GATE_SIZE)
		return false
	if widest >= SimWorldgen.VEHICLE_MIN_WIDTH:
		push_error("the %d-tile suburb now carves streets %d wide against a %d minimum, so it has room to park; the zero this lane asserts has stopped being true for its stated reason and both halves need re-deriving" % [GATE_SIZE, widest, SimWorldgen.VEHICLE_MIN_WIDTH])
		return false
	if not (narrow.vehicles as Array).is_empty():
		push_error("the %d-tile suburb parked %d cars on streets %d wide, under a %d minimum" % [GATE_SIZE, (narrow.vehicles as Array).size(), widest, SimWorldgen.VEHICLE_MIN_WIDTH])
		return false

	# The other two shipped districts declare no `vehicles` block at all and park nothing at any
	# size -- and the two facts agree, because their streets come out too narrow to park in either.
	# Asserted rather than skipped: a district that quietly started parking cars, or one whose
	# streets were widened past the minimum while its block stayed absent, are both things this
	# lane should start speaking about rather than staying silent through.
	var quiet: Array[String] = []
	for pair in [[FOREST_ID, _forest()], [TOWN_ID, SimWorldgen.generate(CANON_SEED, TOWN_SIZE, _tree(), TOWN_ID)]]:
		var id: String = String((pair as Array)[0])
		var other: Variant = (pair as Array)[1]
		var district: Dictionary = SimWorldgen.district_of(_tree(), id)
		if district.has("vehicles"):
			push_error("%s now declares a `vehicles` block; this lane asserts it parks nothing and the assertion needs re-deriving" % id)
			return false
		if not (other.vehicles as Array).is_empty():
			push_error("%s parked %d cars while declaring no `vehicles` block" % [id, (other.vehicles as Array).size()])
			return false
		var other_widest: int = 0
		for street3 in other.streets as Array:
			other_widest = maxi(other_widest, int((street3 as Dictionary).get("width", 0)))
		if other_widest >= SimWorldgen.VEHICLE_MIN_WIDTH:
			push_error("%s at %d now carves streets %d wide, at or past the %d a car needs; its zero is no longer explained by its layout and the omission of its `vehicles` block has become a choice somebody should state" % [
				id, int(other.w), other_widest, SimWorldgen.VEHICLE_MIN_WIDTH,
			])
			return false
		quiet.append("%s@%d %d wide" % [id, int(other.w), other_widest])

	stash["parked"] = total
	stash["parked_min"] = least
	stash["parked_max"] = most
	stash["narrow_width"] = widest
	print("PLACED OK the two districts that park nothing declare no block and have no room either (%s), against a %d minimum" % [", ".join(quiet), SimWorldgen.VEHICLE_MIN_WIDTH])
	print("PLACED OK %d cars over %d seeds at %d (%d..%d a map), every footprint tile Low, outdoors, on the street surface, clear of doorways and junctions, inside a carriageway with a kerb row free either side; the crossing scanner was proved on a real junction; suburb@%d parked 0 because its widest street is %d against a %d minimum" % [
		total, SEEDS.size(), PARK_SIZE, least, most, GATE_SIZE, widest, SimWorldgen.VEHICLE_MIN_WIDTH,
	])
	return true


# --- 6. EXCLUSIVE: a Low tile is a car or a heap, never both, never neither ----------------------

# Every arm of a `match tile:` that handles Tile.Low, each sliced from its own case label to the
# next case label of any tile class. Plural on purpose: `_draw_district` matches on the tile class
# TWICE -- once to pick a colour and once to draw -- so the arm that draws has to be found rather
# than assumed. Taking the first one read four lines of colour arithmetic and reported that the
# draw loop never asks about vehicles, which is the worst failure a gate has: red, and blaming the
# code under test.
func _low_arms(body: String) -> Array[String]:
	var out: Array[String] = []
	var label: String = "SimTileMap.Tile.Low:"
	var at: int = body.find(label)
	while at >= 0:
		var to: int = body.find("SimTileMap.Tile.", at + label.length())
		out.append(body.substr(at, (to - at) if to >= 0 else -1))
		at = body.find(label, at + label.length())
	return out


# What is wrong with the Low arm's ordering, or "". A heap drawn under a car is exactly what
# happens when the vehicle test is dropped or moved after the draw, so every half is one predicate
# and the fabricated bodies below -- reversed, testless, armless and correct -- all refuse or pass
# through it.
func _order_problem(body: String) -> String:
	var arms: Array[String] = _low_arms(body)
	if arms.is_empty():
		return "there is no Tile.Low arm at all"
	var drawing: int = -1
	for i in arms.size():
		if arms[i].contains("_draw_heap("):
			if drawing >= 0:
				return "two Tile.Low arms call _draw_heap; one of them is drawing junk without asking whether a car covers the tile"
			drawing = i
	if drawing < 0:
		return "no Tile.Low arm calls _draw_heap; no uncovered Low tile would draw anything but the procedural block"
	var arm: String = arms[drawing]
	var test: int = arm.find("Dressing.vehicle_at(")
	if test < 0:
		return "the Tile.Low arm that draws never asks Dressing.vehicle_at; every Low tile would take a heap, including the ten under every sedan"
	if test > arm.find("_draw_heap("):
		return "the Tile.Low arm draws the heap before it asks whether a car covers the tile"
	return ""


func _every_low_tile_is_a_car_or_a_heap(stash: Dictionary) -> bool:
	var block: Dictionary = stash["block"]

	# The branch that keeps the two apart, asserted FIRST because it needs no data and because a
	# missing sprite file downstream must not be able to mask it. The scanner is proved on a
	# fabricated Low arm with the two calls the wrong way round, on one missing the test entirely
	# and on an empty one, before it is trusted; the scan below is what then shows the assertion
	# has teeth.
	# The scanner has to be able to say yes as well as no, and it has to say them about the arm
	# that draws rather than about the first one it trips over -- so the fabricated bodies below
	# carry a colour arm in front of the drawing one, exactly as _draw_district does.
	var colour_arm: String = "SimTileMap.Tile.Low:\n\t\tcol = low\n\tSimTileMap.Tile.Tree:\n\t\tcol = tree\n"
	if not _order_problem(colour_arm + "SimTileMap.Tile.Low:\n\tif Dressing.vehicle_at(i):\n\t\t_draw_heap(rect)\nSimTileMap.Tile.Tree:\n").is_empty():
		push_error("the order scanner refused a well-ordered Low arm standing behind a colour arm; it cannot say yes and would fail the shipped loop")
		return false
	if _order_problem(colour_arm + "SimTileMap.Tile.Low:\n\t_draw_heap(rect)\n\tDressing.vehicle_at(x)\nSimTileMap.Tile.Tree:\n").is_empty():
		push_error("the order scanner passed an arm that draws the heap first; it cannot say no")
		return false
	if _order_problem(colour_arm + "SimTileMap.Tile.Low:\n\t_draw_heap(rect)\nSimTileMap.Tile.Tree:\n").is_empty():
		push_error("the order scanner passed an arm with no vehicle test at all")
		return false
	if _order_problem(colour_arm).is_empty():
		push_error("the order scanner passed a body whose only Low arm draws nothing")
		return false
	if _order_problem("").is_empty():
		push_error("the order scanner passed an empty body")
		return false
	var district: String = _function_body(MAIN_GD, "_draw_district")
	if district.is_empty():
		push_error("could not read _draw_district out of %s -- the exclusion assertion had nothing to judge" % MAIN_GD)
		return false
	var problem: String = _order_problem(district)
	if not problem.is_empty():
		push_error("_draw_district: %s" % problem)
		return false

	var covered: int = 0
	var heaped: int = 0
	var would_have_heaped: int = 0
	for i in SEEDS.size():
		var map: Variant = _parked()[i]
		var index: PackedInt32Array = Dressing.vehicle_index(map)
		for ty in int(map.h):
			for tx in int(map.w):
				if int(SimTileMap.tile_at(map, tx, ty)) != SimTileMap.Tile.Low:
					# Nothing that is not Low may take a heap, or the resolver is answering for the
					# whole map rather than for the tiles the sim called cover.
					if not Dressing.heap_key(block, map, SEEDS[i], tx, ty).is_empty():
						push_error("seed %d: tile (%d,%d) is not Low and resolved a heap" % [SEEDS[i], tx, ty])
						return false
					continue
				var on_car: bool = Dressing.vehicle_at(index, map, tx, ty) != Dressing.VEHICLE_NONE
				var key: String = Dressing.heap_key(block, map, SEEDS[i], tx, ty)
				if on_car:
					covered += 1
					# The resolver is deliberately vehicle-blind: it answers for any Low tile at
					# all, which is exactly why the exclusion has to be the branch's job and why
					# the textual assertion below is load-bearing rather than decorative.
					if not key.is_empty():
						would_have_heaped += 1
					continue
				# Never neither: an uncovered Low tile is a heap, and the heap has a file.
				if key.is_empty():
					push_error("seed %d: Low tile (%d,%d) is covered by no record and resolves no heap; it would draw as the procedural block while every other one is dressed" % [SEEDS[i], tx, ty])
					return false
				if Appearance.resolve(key) == null:
					push_error("seed %d: Low tile (%d,%d) resolved heap '%s', which has no file" % [SEEDS[i], tx, ty, key])
					return false
				heaped += 1
	if covered == 0 or heaped == 0:
		push_error("over %d parked districts %d Low tiles were covered and %d heaped; one side of the exclusion had nothing to judge" % [SEEDS.size(), covered, heaped])
		return false
	if would_have_heaped == 0:
		push_error("not one of %d covered tiles would have resolved a heap, so nothing separates the two cases and the branch assertion above is judging nothing; heap_key has become vehicle-aware, which puts the exclusion in the resolver where it cannot be seen" % covered)
		return false

	# The graceful absence, and the one thing a deferred tile could otherwise lose. Every other
	# resolver in this pipeline degrades to a procedural shape; a covered tile that defers to a
	# picture which never resolves used to draw nothing at all, so ten tiles of cover the sim knows
	# about were a hole in the street. `main.gd::_vehicle_index()` is what clears an undrawable
	# record out of the per-map index -- it is a method on a CanvasItem and cannot run headless, so
	# the property is held in two halves: here, that the ingredients that accessor reads really do
	# say no for an undrawable car and yes for a shipped one, and that the tiles under it are
	# heap-able; in SOCKETS, that the accessor really does read them.
	var world: Variant = stash["world"]
	var ghost: Variant = _hand_map()
	var ghosted: Array = ghost.vehicles as Array
	var undrawable: Dictionary = ghosted[0] as Dictionary
	undrawable["class"] = "vehicle.hovercraft"
	var ghost_key: String = Dressing.vehicle_key(world, undrawable, CANON_SEED)
	if not ghost_key.is_empty():
		push_error("a record naming a class nobody declared resolved '%s'; the filter that clears an undrawable car out of the index would keep it, and its ten tiles would draw as nothing at all" % ghost_key)
		return false
	var shipped_key: String = Dressing.vehicle_key(world, ghosted[1] as Dictionary, CANON_SEED)
	if shipped_key.is_empty() or Appearance.resolve(shipped_key) == null:
		push_error("the shipped sedan beside it resolved '%s', which draws nothing either -- so the filter would clear every record and this assertion is judging a rule that refuses everything" % shipped_key)
		return false
	for dy in int(undrawable["h"]):
		for dx in int(undrawable["w"]):
			var gx: int = int(undrawable["x"]) + dx
			var gy: int = int(undrawable["y"]) + dy
			var fallback: String = Dressing.heap_key(block, ghost, CANON_SEED, gx, gy)
			if fallback.is_empty() or Appearance.resolve(fallback) == null:
				push_error("tile (%d,%d) under a car that resolves no picture falls back to '%s', which draws nothing; a car nobody drew must leave a heap, not a hole" % [gx, gy, fallback])
				return false

	stash["covered"] = covered
	stash["heaped"] = heaped
	print("EXCLUSIVE OK over %d parked districts %d Low tiles are covered by a record and %d resolve a heap, never both and never neither, and no tile that is not Low resolves one; %d of the covered tiles would have heaped had the arm not asked first, _draw_district's drawing Low arm asks Dressing.vehicle_at before it reaches _draw_heap, and a car whose class resolves no picture leaves every one of its tiles heap-able rather than blank" % [
		SEEDS.size(), covered, heaped, would_have_heaped,
	])
	return true


# --- 7. HOST: the sim side reads the manifest too -----------------------------------------------
#
# The other dead-socket assertion, and the one the presentation lanes cannot make. `map.vehicles`
# has a second reader in `SimWorldgen._sites`: an outdoor loot row declaring `host: "vehicle"`
# stands its site on a car's TAIL tile -- the end of the footprint away from the nose, because that
# is where a boot is -- and falls back to the driveway on a map that parked none. `check_loot.gd`
# validates the key itself; what nothing asserted was that either branch is ever *taken*, and both
# have a live shipped reader: the suburb at 128 stands its car boot on a car, and `forest_edge`,
# whose streets are too narrow to park in at any size, stands the same row on open ground.
#
# This also closes a side-find docs/23 carried for a while -- the suburb's car boots used to stand
# on driveways with no car under them, because `_protected_tiles` forbade the dressing from putting
# a wreck on a site tile, so the boot had never once had a car.

# The `perDistrict` loot rows a district declares with `host: "vehicle"`. Read out of content so
# the gate never hard-codes "car boot", which is prose and free to change.
func _host_rows(district: Dictionary) -> Array:
	var out: Array = []
	var profile: Variant = district.get("lootProfile")
	if not (profile is Dictionary):
		return out
	for raw in (profile as Dictionary).get("perDistrict", []) as Array:
		var row: Dictionary = raw as Dictionary
		if String(row.get("host", "")) == "vehicle":
			out.append(row)
	return out


# The sites one such row stood, matched on its own table and its own container names.
func _sites_of_row(map: Variant, row: Dictionary) -> Array:
	var containers: Array = row.get("containers", []) as Array
	var out: Array = []
	for raw in map.sites as Array:
		var site: Dictionary = raw as Dictionary
		if String(site.get("table", "")) != String(row.get("table", "")):
			continue
		if not containers.has(String(site.get("container", ""))):
			continue
		out.append(site)
	return out


# What is wrong with a hosted site on a district that parked cars, or "". A boot has to be on a
# TAIL tile, not merely somewhere on a car: a site on the bonnet is loot in the engine bay. Proved
# on a fabricated site standing on a nose tile before the real ones are judged.
func _boot_on_car_problem(map: Variant, tails: Dictionary, index: PackedInt32Array, site: Dictionary) -> String:
	var tx: int = int(site.get("x", -1))
	var ty: int = int(site.get("y", -1))
	var idx: int = ty * int(map.w) + tx
	if Dressing.vehicle_at(index, map, tx, ty) == Dressing.VEHICLE_NONE:
		return "the boot at (%d,%d) stands on no car at all; the host branch fell through on a district that parked %d" % [tx, ty, (map.vehicles as Array).size()]
	if not tails.has(idx):
		return "the boot at (%d,%d) stands on a car but not on its tail; that is loot in the engine bay" % [tx, ty]
	if int(SimTileMap.tile_at(map, tx, ty)) != SimTileMap.Tile.Low:
		return "the boot at (%d,%d) stands on a car whose footprint tile is not Low" % [tx, ty]
	return ""


# And what is wrong with one on a district that parked none. The fallback is the normal path, not a
# failure: the site stands on open outdoor floor, which is what every outdoor site was before the
# key existed. (A parked car is walk-through cover -- `SimPath._footing` grants a non-Floor tile
# walkability while its surface is paved -- so this is about which ground the site chose, not about
# reachability.)
func _boot_on_driveway_problem(map: Variant, index: PackedInt32Array, site: Dictionary) -> String:
	var tx: int = int(site.get("x", -1))
	var ty: int = int(site.get("y", -1))
	if Dressing.vehicle_at(index, map, tx, ty) != Dressing.VEHICLE_NONE:
		return "the boot at (%d,%d) stands on a car on a district that parked none" % [tx, ty]
	if int(SimTileMap.tile_at(map, tx, ty)) != SimTileMap.Tile.Floor:
		return "the boot at (%d,%d) stands on tile class %d, not open floor" % [tx, ty, int(SimTileMap.tile_at(map, tx, ty))]
	if int(map.indoors[ty * int(map.w) + tx]) != 0:
		return "the boot at (%d,%d) fell back to a tile inside a building rather than to a driveway" % [tx, ty]
	return ""


func _a_hosted_site_stands_on_a_car_or_falls_back(stash: Dictionary) -> bool:
	var district: Dictionary = SimWorldgen.district_of(_tree(), SimWorldgen.DEFAULT_DISTRICT)
	var rows: Array = _host_rows(district)
	if rows.is_empty():
		push_error("the shipped suburb declares no `host: vehicle` loot row, so the branch that reads map.vehicles on the sim side has no reader and this lane has nothing to judge")
		return false

	# The vehicle branch, on the four parked districts.
	var on_cars: int = 0
	var nose_probed: bool = false
	for i in SEEDS.size():
		var map: Variant = _parked()[i]
		var index: PackedInt32Array = Dressing.vehicle_index(map)
		var tails: Dictionary = {}
		for tile in SimWorldgen._vehicle_tails(map):
			tails[int(tile)] = true
		if tails.is_empty():
			push_error("seed %d parked %d cars and _vehicle_tails answered none; the host branch would silently fall back" % [SEEDS[i], (map.vehicles as Array).size()])
			return false
		for row in rows:
			var want: int = SimWorldgen._district_count(int((row as Dictionary).get("count", 0)), mini(int(map.w), int(map.h)))
			var stood: Array = _sites_of_row(map, row as Dictionary)
			if stood.size() != want:
				push_error("seed %d: the '%s' row asked for %d sites at %d and stood %d; a hosted row must not lose sites to its host" % [
					SEEDS[i], String((row as Dictionary).get("table", "?")), want, PARK_SIZE, stood.size(),
				])
				return false
			for site in stood:
				var problem: String = _boot_on_car_problem(map, tails, index, site as Dictionary)
				if not problem.is_empty():
					push_error("seed %d: %s" % [SEEDS[i], problem])
					return false
				on_cars += 1
		# The negative for the tail rule: a site on a footprint tile that is NOT a tail has to be
		# refused, or "stands on the tail" is a claim any tile of the car would satisfy.
		if not nose_probed:
			for record in map.vehicles as Array:
				var r: Dictionary = record as Dictionary
				for dy in int(r["h"]):
					for dx in int(r["w"]):
						var tx: int = int(r["x"]) + dx
						var ty: int = int(r["y"]) + dy
						if tails.has(ty * int(map.w) + tx):
							continue
						if _boot_on_car_problem(map, tails, index, {"x": tx, "y": ty}).is_empty():
							push_error("a fabricated boot on the non-tail footprint tile (%d,%d) passed the tail rule; it cannot say no" % [tx, ty])
							return false
						nose_probed = true
						break
					if nose_probed:
						break
				if nose_probed:
					break
	if on_cars == 0:
		push_error("no hosted site stood on a car across %d parked districts; the vehicle branch is a socket nothing reaches" % SEEDS.size())
		return false
	if not nose_probed:
		push_error("every footprint tile of every car was a tail, so the tail rule was never given a negative to refuse")
		return false

	# The fallback branch, on the shipped district that parks nothing and asks anyway.
	var forest: Variant = _forest()
	if not (forest.vehicles as Array).is_empty():
		push_error("%s parked %d cars; the fallback branch has no shipped reader any more and this half of the lane is judging the wrong thing" % [FOREST_ID, (forest.vehicles as Array).size()])
		return false
	var forest_rows: Array = _host_rows(SimWorldgen.district_of(_tree(), FOREST_ID))
	if forest_rows.is_empty():
		push_error("%s declares no `host: vehicle` row, so nothing shipped exercises the driveway fallback and it is a branch nobody reaches" % FOREST_ID)
		return false
	var forest_index: PackedInt32Array = Dressing.vehicle_index(forest)
	var fell_back: int = 0
	for row2 in forest_rows:
		var want2: int = SimWorldgen._district_count(int((row2 as Dictionary).get("count", 0)), mini(int(forest.w), int(forest.h)))
		var stood2: Array = _sites_of_row(forest, row2 as Dictionary)
		if stood2.size() != want2:
			push_error("%s at %d: the '%s' row asked for %d sites and stood %d; the fallback must not change the count" % [
				FOREST_ID, FOREST_SIZE, String((row2 as Dictionary).get("table", "?")), want2, stood2.size(),
			])
			return false
		if want2 == 0:
			push_error("%s at %d scales its hosted row to zero sites, so the fallback had nothing to stand and this half of the lane is judging nothing" % [FOREST_ID, FOREST_SIZE])
			return false
		for site2 in stood2:
			var problem2: String = _boot_on_driveway_problem(forest, forest_index, site2 as Dictionary)
			if not problem2.is_empty():
				push_error("%s at %d: %s" % [FOREST_ID, FOREST_SIZE, problem2])
				return false
			fell_back += 1
	# And the negative for the fallback rule, through the same predicate: a Low tile is not a
	# driveway, whether or not a car put it there.
	var low_probe: Vector2i = Vector2i(-1, -1)
	for ty2 in int(forest.h):
		for tx2 in int(forest.w):
			if int(SimTileMap.tile_at(forest, tx2, ty2)) == SimTileMap.Tile.Low:
				low_probe = Vector2i(tx2, ty2)
				break
		if low_probe.x >= 0:
			break
	if low_probe.x < 0:
		push_error("%s carries no Low tile at all, so the fallback rule was never given a negative to refuse" % FOREST_ID)
		return false
	if _boot_on_driveway_problem(forest, forest_index, {"x": low_probe.x, "y": low_probe.y}).is_empty():
		push_error("a fabricated boot on the Low tile %s passed the driveway rule; it cannot say no" % str(low_probe))
		return false

	stash["hosted_on_car"] = on_cars
	stash["hosted_fallback"] = fell_back
	print("HOST OK %d hosted sites stood on a car's tail across %d suburbs at %d, and %d stood on open outdoor floor on %s at %d, which parks nothing at all; neither branch changed its row's site count, and a boot fabricated onto a non-tail footprint tile and one onto a Low tile are both refused" % [
		on_cars, SEEDS.size(), PARK_SIZE, fell_back, FOREST_ID, FOREST_SIZE,
	])
	return true


# --- 8. SCATTER: the loose stuff --------------------------------------------------------------
#
# Untouched by this slice and deliberately left as it was: the litter and the broken concrete are
# ground dressing, drawn into the tile under everything above, and neither reads the manifest.

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


# --- 9. SOCKETS -------------------------------------------------------------------------------

# The rule this milestone has paid for nine times: a resolver nothing calls is not a feature. A
# CanvasItem draw pass cannot run headless, so what it calls is read -- check_topdown.gd's
# precedent. The first needle missing from `body`, or "".
func _missing_needle(body: String, needles: Array) -> String:
	for needle in needles:
		if not body.contains(String(needle)):
			return String(needle)
	return ""


# The reach assertions themselves. Two scanners are used here: `_missing_needle` for "is this
# called", and VARIATION's `_first_forbidden` run in reverse for "is this name gone" -- and both
# are proved on a fabricated string before either is trusted.
func _the_sockets_are_wired() -> bool:
	# Both scanners proved before either is trusted: one that answers "present" for everything, or
	# "absent" for everything, is a gate that cannot fail.
	if _missing_needle("func nothing() -> void:\n\tpass\n", ["_draw_heap("]) != "_draw_heap(":
		push_error("SOCKET: the needle scanner found nothing missing in a body missing everything; it cannot say no")
		return false
	if not _missing_needle("_draw_heap(rect)", ["_draw_heap("]).is_empty():
		push_error("SOCKET: the needle scanner called a present needle missing; it cannot say yes")
		return false

	var district: String = _function_body(MAIN_GD, "_draw_district")
	if district.is_empty():
		push_error("could not read _draw_district out of %s -- the reach assertion had nothing to judge" % MAIN_GD)
		return false
	var missing: String = _missing_needle(district, ["_vehicle_index()", "Dressing.vehicle_at(", "_draw_heap(", "_draw_scatter(", "_dressing()"])
	if not missing.is_empty():
		push_error("_draw_district does not call %s; that half of the dressing resolves and draws nothing" % missing)
		return false
	# The fallback stays a supported path: a district whose content declares no heaps still draws
	# the procedural cover block over the Low tiles no car covers.
	if not district.contains("if not _draw_heap("):
		push_error("_draw_district draws the heap unconditionally; a map with no dressing content would draw nothing over its uncovered Low tiles")
		return false

	var entities: String = _function_body(MAIN_GD, "_draw_entities")
	if entities.is_empty():
		push_error("could not read _draw_entities out of %s" % MAIN_GD)
		return false
	var missing2: String = _missing_needle(entities, ["Dressing.vehicle_records(", "Dressing.vehicle_key(", "Appearance.vehicle_flip(", "_blit_vehicle("])
	if not missing2.is_empty():
		push_error("_draw_entities does not call %s; a parked car would be a record nothing stands a picture on" % missing2)
		return false

	var blit: String = _function_body(MAIN_GD, "_blit_vehicle")
	if blit.is_empty():
		push_error("could not read _blit_vehicle out of %s" % MAIN_GD)
		return false
	var missing3: String = _missing_needle(blit, ["Appearance.body_rect(", "draw_texture_rect("])
	if not missing3.is_empty():
		push_error("_blit_vehicle does not contain %s; the picture is resolved but not stood on its feet, or not drawn at all" % missing3)
		return false

	var scatter: String = _function_body(MAIN_GD, "_draw_scatter")
	if scatter.is_empty():
		push_error("could not read _draw_scatter out of %s" % MAIN_GD)
		return false
	var missing4: String = _missing_needle(scatter, ["Dressing.rubble_key(", "Dressing.litter_key(", "draw_texture_rect("])
	if not missing4.is_empty():
		push_error("_draw_scatter does not contain %s" % missing4)
		return false

	# The per-map accessor, which is deliberately a NARROWER thing than the manifest: it clears
	# every record whose picture will not resolve, so an undrawable car falls through to a heap
	# instead of leaving a hole in the street. EXCLUSIVE holds the fallback itself; this is the
	# assertion that the accessor reads the two things that fallback depends on, and writes the
	# sentinel that lets the tile branch see it.
	var accessor: String = _function_body(MAIN_GD, "_vehicle_index")
	if accessor.is_empty():
		push_error("could not read _vehicle_index out of %s" % MAIN_GD)
		return false
	var missing5: String = _missing_needle(accessor, ["Dressing.vehicle_index(", "Dressing.vehicle_key(", "Appearance.resolve(", "Dressing.VEHICLE_NONE"])
	if not missing5.is_empty():
		push_error("_vehicle_index does not read %s; a record whose picture never resolves would stay in the index and its tiles would draw as nothing at all" % missing5)
		return false

	# And the retired vocabulary stays retired. A gate that stopped naming these would let the
	# segment convention grow back one helper at a time, and the nine `wreck_car_*` keys with it.
	var retired: Array = ["segment_at", "run_angle", "run_anchor", "wreck_key", "SEG_", "ANCHOR_MAX_STEPS", "SALT_VARIANT"]
	if _first_forbidden("var s = Dressing.segment_at(map, 0, 0)", retired) != "segment_at":
		push_error("SOCKET: the retired-name scanner found nothing in a string built to contain one")
		return false
	var dressing_code: String = _code_of(DRESSING_GD)
	var back: String = _first_forbidden(dressing_code, retired)
	if not back.is_empty():
		push_error("%s still declares '%s'; the per-tile segment convention retired with slice 10 and a car is one picture now" % [DRESSING_GD, back])
		return false
	var main_code: String = _code_of(MAIN_GD)
	# `_draw_wreck` went with the segments; `draw_set_transform` went with the quarter turn that
	# used to draw an east-west run, and main.gd's own comment now claims the file sets none.
	var main_back: String = _first_forbidden(main_code, ["_draw_wreck(", "draw_set_transform"])
	if not main_back.is_empty():
		push_error("%s still contains '%s'; a car is one picture in the entity sort and nobody rotates" % [MAIN_GD, main_back])
		return false

	print("SOCKETS OK _draw_district reads the vehicle index, the manifest and both dressing halves with the procedural block still beside them; _vehicle_index clears the records whose pictures do not resolve; _draw_entities resolves the record, its key and its flip and blits it; _blit_vehicle stands it on body_rect; _draw_scatter reads both scatter resolvers; the seven retired segment names and both retired draw calls are gone, and every scanner was proved on a fabricated string")
	return true


# --- the budget --------------------------------------------------------------------------------

func _the_gate_stayed_inside_its_own_budget(seconds: float) -> bool:
	if seconds > BUDGET_SECONDS:
		push_error("the wrecks gate took %.1f s against a %.0f s budget -- share boots and generated districts between lanes rather than adding them" % [seconds, BUDGET_SECONDS])
		return false
	if seconds <= 0.0:
		push_error("the gate measured %.1f s of its own wall time, so the budget is measuring nothing" % seconds)
		return false
	print("BUDGET OK %.1f s of a %.0f s budget" % [seconds, BUDGET_SECONDS])
	return true


# A file's source with the comments taken out -- everything from the first `#` on a line to the
# end of it. The forbidden-name scans above have to read *code*: this file's subjects explain in
# their own headers why they use no `randi` and why the segment names are gone, and a scan that
# cannot tell an explanation from a call fails a file for documenting the rule it obeys. (Neither
# file puts a `#` inside a string; main.gd's one such line is a trailing comment.)
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
