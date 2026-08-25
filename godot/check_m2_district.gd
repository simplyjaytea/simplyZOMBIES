extends SceneTree
# The district: generated from a district type, stamped with the civic annex, booted.
#
# The blit/annex/boot lanes are the originals. Everything from `_the_generator_builds_a_district`
# down is the worldgen rebuild -- docs/24's "authored templates, procedurally assembled" -- and
# holds down the five claims the rebuild makes:
#
#   1. **It builds a district.** 40-70 buildings at the shipped 256, per docs/24's suburban
#      density, and a real miniature at the gate's 64 rather than the *zero* the old block lattice
#      put there. A density-0 fixture district is the true negative: it places none, and the band
#      has to reject that.
#   2. **The road seam is live.** Every connection point a district declares is an opening in the
#      wall with a street behind it, and a flood fill from one of them reaches essentially all the
#      outdoor ground -- no sealed quadrants (docs/30: a dead field named `connectionPoints` would
#      be the tenth socket).
#   3. **Buildings can be entered.** The sandbox goal, made mechanical: every indoor room on the
#      booted map -- the annex included -- is reachable from the street through a doorway. A
#      fixture whose door is bricked over is the true negative.
#   4. **It is a function of its inputs.** Same seed, same district, byte-identical; a different
#      seed, different; and the layout is independent of the dressing streams, so a change to the
#      trees cannot move a wall.
#   5. **The district data is read.** A fixture district with a different density and a different
#      pool builds a measurably different place on the same seed, and the second shipped type
#      (town centre) generates and puts its commercial footprints down.
#   6. **The colony is sited per seed, and the start is survivable.** docs/01's fairness rule --
#      "No unwinnable starts: generated starting positions are validated for basic survivability"
#      -- made mechanical: eight seeds at the gate size and two at the shipped one, every clause
#      of the survivability pass true on each, and each clause shown to be able to say no.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimTemplates = preload("res://sim/map/templates.gd")
const SimWorldgen = preload("res://sim/map/worldgen.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimDirector = preload("res://sim/modules/director.gd")
const ContentLoader = preload("res://platform/content_loader.gd")
const ContentValidator = preload("res://platform/content_validator.gd")

const CANON_SEED: int = 20260805
const GATE_SIZE: int = 64
const SHIPPED_SIZE: int = 256
# Too small to hold the annex and its clear ring, so the generator sites no colony on it: the one
# shape that comes back with no anchors, and what the two isolation worlds boot at.
const ISOLATION_SIZE: int = 32
# The seeds the siting lane walks: the four the balance harness runs, and four more, because a
# property asserted on the four campaigns it is measured against is a property asserted on the four
# campaigns it is measured against.
const SITING_SEEDS: Array[int] = [20260805, 404, 31337, 90210, 1, 2, 7, 12345]
const SITING_SEEDS_256: Array[int] = [20260805, 404]
# docs/24: "At suburban density a 256 m district holds ~40-70 buildings." Re-measured on the shipped
# residential type after the annex moved off its fixed corner rect: 47, 63, 51, 50 on the four
# harness seeds, canonical 47 (51 before).
const BUILDINGS_256_MIN: int = 40
const BUILDINGS_256_MAX: int = 70
# The assertion that was impossible before: at 64 the old generator's block loop never ran, so
# every gate but check_loot's booted a district with no buildings in it at all.
#
# Re-measured after the siting slice, across twelve seeds: **3..10**, and 4..7 on the four the
# balance harness uses (7, 4, 4, 6). It was 4..10 and 6..8 when the annex sat in the map's corner
# with a quarter of its 26x26 footprint over the ring road and the wall. A colony sited inside the
# district takes its whole footprint out of the buildable lots, and at 64 -- a *model* of a district
# rather than a quarter of one -- that is roughly a third of them. The floor is what it has always
# been for: zero buildings is the old lattice bug coming back, and three is a thin suburb.
const BUILDINGS_64_MIN: int = 3
# Outdoor ground a walk from a connection point has to reach. Not 100%: dressing can ring a pocket
# of lawn with trees, which is a garden rather than a bug. Measured: 100.0% at both sizes.
const REACH_SHARE_MIN: float = 0.9

var _tree_cache: Dictionary = {}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _content_valid() and ok
	ok = _blit_confined() and ok
	ok = _annex_shell() and ok
	ok = _playable_boot() and ok
	ok = _the_booted_world_carries_its_colony_anchors() and ok
	ok = _two_worlds_do_not_share_an_attention_field() and ok
	ok = _the_generator_builds_a_district() and ok
	ok = _the_roads_leave_where_the_district_says_they_do() and ok
	ok = _every_building_can_be_entered() and ok
	ok = _the_same_inputs_build_the_same_district() and ok
	ok = _the_district_entry_is_read() and ok
	ok = _the_generator_reserves_the_ground_it_sited() and ok
	ok = _the_colony_is_sited_per_seed_and_survivable() and ok
	ok = _the_survivability_pass_can_fail() and ok
	ok = _a_refused_candidate_moves_the_colony_to_the_next_one() and ok
	if ok:
		print("M2_DISTRICT_OK validate blit annex anchors boot isolation generator roads enterable determinism district-data reserve siting survivability re-site")
		quit(0)
	else:
		push_error("M2_DISTRICT_FAIL")
		quit(1)


func _tree() -> Dictionary:
	# One directory walk for the whole gate: `load_tree` reads every JSON under content/.
	if _tree_cache.is_empty():
		_tree_cache = ContentLoader.load_tree()
	return _tree_cache

func _content_valid() -> bool:
	var issues: Array = ContentValidator.validate_tree("res://content")
	if not issues.is_empty():
		push_error("content invalid: %s" % str(issues[0]))
		return false
	print("CONTENT OK")
	return true

func _blit_confined() -> bool:
	var seed_val: int = 20260805
	var raw: Variant = SimTileMap.generate_district(seed_val, 64)
	var patched: Variant = SimTileMap.generate_district(seed_val, 64)
	var content: Dictionary = ContentLoader.load_tree()
	var patch: Variant = SimTileMap.load_patch_from_content(content, "map.district.alpha")
	if not patch is Dictionary:
		push_error("missing district_alpha patch")
		return false
	SimTileMap.apply_patch(patched, patch as Dictionary)
	var rect: Dictionary = (patch as Dictionary)["rect"] as Dictionary
	var rx: int = int(rect["x"])
	var ry: int = int(rect["y"])
	var rw: int = int(rect["w"])
	var rh: int = int(rect["h"])
	var changed: int = 0
	var leaked: int = 0
	for y in 64:
		for x in 64:
			var a: int = int(raw.tiles[y * raw.w + x])
			var b: int = int(patched.tiles[y * patched.w + x])
			var inside: bool = x >= rx and x < rx + rw and y >= ry and y < ry + rh
			if a != b:
				changed += 1
				if not inside:
					leaked += 1
	if leaked != 0:
		push_error("patch leaked %d tiles outside rect" % leaked)
		return false
	if changed == 0:
		push_error("patch changed nothing")
		return false
	print("BLIT OK changed=%d leaked=0" % changed)
	return true

func _annex_shell() -> bool:
	# The colony arrives with the district now -- sited, stamped and reserved by the generator -- so
	# this reads the rect off the map rather than stamping one itself and remembering where.
	var map: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, _tree())
	var rect: Rect2i = SimTileMap.annex_rect(map)
	if rect.size.x <= 0 or rect.size.y <= 0:
		push_error("the generated district carries no annex, so this shell check is measuring nothing")
		return false
	var windows: int = 0
	var screens: int = 0
	var lows: int = 0
	var indoors: int = 0
	for j in rect.size.y:
		for i in rect.size.x:
			var tx: int = rect.position.x + i
			var ty: int = rect.position.y + j
			var t: int = SimTileMap.tile_at(map, tx, ty)
			if t == SimTileMap.Tile.Window:
				windows += 1
			elif t == SimTileMap.Tile.Screen:
				screens += 1
			elif t == SimTileMap.Tile.Low:
				lows += 1
			if SimTileMap.is_indoors(map, tx, ty):
				indoors += 1
	if windows < 6:
		push_error("annex windows %d < 6" % windows)
		return false
	if screens < 1 or lows < 1:
		push_error("annex missing screen/low s=%d l=%d" % [screens, lows])
		return false
	if indoors < 20:
		push_error("annex indoors %d" % indoors)
		return false
	# Gate: three floor tiles on the south door -- the two the template anchors, and the one east
	# of them that makes the doorway three wide. Where they are is read off the stamped map, so
	# this still holds when the annex moves.
	var gate_a: Vector2i = SimTileMap.gate_a(map)
	var gate_b: Vector2i = SimTileMap.gate_b(map)
	if gate_a.x < 0 or gate_b.x < 0:
		push_error("the stamped annex named no gate, so this assertion is measuring nothing")
		return false
	var gate: int = 0
	for tile in [gate_a, gate_b, gate_b + Vector2i(1, 0)]:
		if SimTileMap.tile_at(map, (tile as Vector2i).x, (tile as Vector2i).y) == SimTileMap.Tile.Floor:
			gate += 1
	if gate < 2:
		push_error("gate missing at %s..%s" % [str(gate_a), str(gate_b + Vector2i(1, 0))])
		return false
	print("ANNEX OK at %s windows=%d screens=%d indoors=%d" % [str(rect), windows, screens, indoors])
	return true

func _playable_boot() -> bool:
	var boot: Dictionary = SimBoot.playable(20260805, 64)
	var world: Variant = boot["world"]
	if int(world.map_width) != 64:
		push_error("playable map %d" % world.map_width)
		return false
	var zeds: int = 0
	var screamers: int = 0
	var bloaters: int = 0
	for e in world.components.query(["shambler"]):
		zeds += 1
		var zt: Variant = world.components.get_component(int(e), "zombieType")
		var id: String = String((zt as Dictionary).get("id", "")) if zt is Dictionary else ""
		if id == "zombie.screamer":
			screamers += 1
		elif id == "zombie.bloater":
			bloaters += 1
	if zeds != SimBoot.WANDERERS or screamers != 0 or bloaters != 0:
		push_error("day-1 boot z=%d s=%d b=%d want %d shamblers" % [zeds, screamers, bloaters, SimBoot.WANDERERS])
		return false
	var ground: int = 0
	for e2 in world.components.query(["itemBase", "position"]):
		if world.components.has_component(int(e2), "stored"):
			continue
		ground += 1
	# The early game has to have something loose on the floor to find. The sites come from the
	# district's `lootProfile` now rather than from seven hand-placed rows in the annex's map entry,
	# so this floor was re-measured across the six seeds the gates boot at 64: 16, 17, 12, 17, 20, 12
	# loose items behind 9..13 sites, most of which stand as containers rather than scattering.
	# Canonical seed 20260805: 16 loose and 8 containers, against 15 loose before the profile landed.
	# The floor is 8 rather than the measured 12 because a scatter's yield is a range; zero would be
	# a profile that starves the start, which is a content bug rather than a re-pin.
	var boxes: int = world.components.query(["searchable", "position"]).size()
	if ground < 8:
		push_error("loot missing ground=%d containers=%d" % [ground, boxes])
		return false
	if boxes < 1:
		push_error("the booted district stands no searchable container at all: ground=%d" % ground)
		return false
	if not world.components.has_component(world.player, "meleeWeapon"):
		push_error("player not armed")
		return false

	# Not one of them inside the colony's own walls. The director has always refused to put a night
	# packet in the annex; the boot scatter used to get the same answer for free, because the annex
	# was a fixed rect in the district's corner and the box those rolls come from barely reached it.
	# With the colony sited per seed it lands in the middle of that box, and before `SCATTER_TRIES`
	# went in this booted 2, 7, 5 and 7 shamblers *inside* the annex on the four balance seeds --
	# and the three seeds with five or more lost a colonist on day 1, 2 or 3 to one of them.
	var map: Variant = boot["map"]
	var annex: Rect2i = SimTileMap.annex_rect(map)
	if annex.size.x <= 0:
		push_error("the playable boot carries no annex, so this exclusion is measuring nothing")
		return false
	var indoors_at_boot: int = _wanderers_inside(world, annex)
	if indoors_at_boot != 0:
		push_error("%d of the %d boot wanderers stand inside the colony at %s" % [indoors_at_boot, zeds, str(annex)])
		return false
	# The true negative: "none inside" is also what a counter that cannot see anybody returns. Put
	# one there by hand and the count has to move by exactly one.
	var planted: int = int(world.entities.spawn())
	world.components.set_component(planted, "shambler", {})
	world.components.set_component(planted, "position", {
		"x": float(annex.position.x + annex.size.x / 2) + 0.5,
		"y": float(annex.position.y + annex.size.y / 2) + 0.5,
	})
	if _wanderers_inside(world, annex) != 1:
		push_error("a shambler stood in the middle of the annex and the count still read %d" % _wanderers_inside(world, annex))
		return false

	print("BOOT OK zeds=%d loot=%d containers=%d, none of them inside the colony at %s" % [zeds, ground, boxes, str(annex)])
	return true


func _wanderers_inside(world: Variant, annex: Rect2i) -> int:
	var n: int = 0
	for e in world.components.query(["shambler", "position"]):
		var p: Variant = world.components.get_component(int(e), "position")
		if not p is Dictionary:
			continue
		if annex.has_point(Vector2i(floori(float((p as Dictionary)["x"])), floori(float((p as Dictionary)["y"])))):
			n += 1
	return n


# The colony's fixed points are map state, not compile-time constants: `SimDirector.ANNEX` and
# `SimFortify.GATE_A`/`GATE_B` are gone, and every consumer reads the stamped district instead.
# check_buildings.gd asserts the stamp *writes* them; this asserts the world the game actually
# boots *carries* them, and that they name tiles a colony could use.
#
# Determinism gets its own half because the accessors read a Dictionary that a stamp merges into:
# two boots of one seed must agree, or every band measured against seed 20260805 is measuring a
# different district each time.
func _the_booted_world_carries_its_colony_anchors() -> bool:
	var first: Dictionary = SimBoot.playable(20260805, 64)
	var map: Variant = first["map"]
	var world: Variant = first["world"]

	var gate_a: Vector2i = SimTileMap.gate_a(map)
	var gate_b: Vector2i = SimTileMap.gate_b(map)
	var start: Vector2i = SimTileMap.player_start(map)
	var well: Vector2i = SimTileMap.well_tile(map)
	var annex: Rect2i = SimTileMap.annex_rect(map)
	if gate_a.x < 0 or gate_b.x < 0 or start.x < 0 or well.x < 0:
		push_error("the playable boot is missing an anchor: gates %s/%s, start %s, well %s" % [
			str(gate_a), str(gate_b), str(start), str(well),
		])
		return false
	if annex.size.x <= 0 or annex.size.y <= 0:
		push_error("the playable boot carries no annex rect")
		return false

	# Standing room. A gate nobody can walk through and a start inside masonry are both anchors
	# that parse and mean nothing.
	for named in [["gate_a", gate_a], ["gate_b", gate_b], ["player_start", start]]:
		var tile: Vector2i = (named as Array)[1] as Vector2i
		if SimTileMap.tile_at(map, tile.x, tile.y) != SimTileMap.Tile.Floor:
			push_error("anchor %s at %s is not open floor" % [String((named as Array)[0]), str(tile)])
			return false
		if SimTileMap.is_solid(map, tile.x, tile.y):
			push_error("anchor %s at %s is solid" % [String((named as Array)[0]), str(tile)])
			return false
	if not annex.has_point(start):
		push_error("the start anchor %s is outside the annex %s" % [str(start), str(annex)])
		return false

	# A reader, not just a coordinate: `place_stations` sites the well off the well anchor, so a
	# water source must be standing on that exact tile.
	var on_the_well: bool = false
	for e in world.components.query(["water_source", "position"]):
		var p: Variant = world.components.get_component(int(e), "position")
		if not p is Dictionary:
			continue
		if Vector2i(floori(float((p as Dictionary)["x"])), floori(float((p as Dictionary)["y"]))) == well:
			on_the_well = true
			break
	if not on_the_well:
		push_error("no water source stands on the well anchor at %s" % str(well))
		return false

	# Same seed, same district, same anchors.
	var again: Variant = SimBoot.playable(20260805, 64)["map"]
	if SimTileMap.gate_a(again) != gate_a or SimTileMap.gate_b(again) != gate_b \
			or SimTileMap.player_start(again) != start or SimTileMap.well_tile(again) != well \
			or SimTileMap.annex_rect(again) != annex:
		push_error("two boots of seed 20260805 disagreed about where the colony is")
		return false

	# The true negative: a district with no colony on it must report absence rather than invent the
	# colony's coordinates. Without this half, accessors that had started answering from a default
	# would pass everything above. ISOLATION_SIZE is a map too small to hold the annex and its clear
	# ring, which is the one shape that now comes back anchorless -- and it is the shape the two
	# isolation worlds below boot at.
	var bare_map: Variant = SimTileMap.generate_district(20260805, ISOLATION_SIZE)
	if SimTileMap.gate_a(bare_map) != Vector2i(-1, -1) or SimTileMap.gate_b(bare_map) != Vector2i(-1, -1) \
			or SimTileMap.player_start(bare_map) != Vector2i(-1, -1) or SimTileMap.well_tile(bare_map) != Vector2i(-1, -1):
		push_error("a district too small for a colony answered with a coordinate instead of the absent sentinel")
		return false
	if SimTileMap.annex_rect(bare_map) != Rect2i(0, 0, 0, 0):
		push_error("a district too small for a colony claimed an annex at %s" % str(SimTileMap.annex_rect(bare_map)))
		return false

	print("ANCHORS OK boot carries gates %s/%s, start %s, well %s, annex %s; stable across two boots; an unstamped district reports none" % [
		str(gate_a), str(gate_b), str(start), str(well), str(annex),
	])
	return true


# Two worlds, two attention fields. The spine (docs/03) is per-world state, and for as long as
# `attach_kernel` existed it was not: SimBoot kept "the last world that called attach_kernel" in a
# `static var` and the `noise.emitted` / `scent.accumulated` handlers wrote into *that* world's
# field rather than the field of the world that published. Measured before the fix -- boot A
# (seed 101), boot B (seed 102), publish magnitude 500 at (8,8) on A, step A -- A's own field read
# 0.0000 and B's read 500.0000. Every gate that boots a positive world and a negative world was
# reading the wrong field for anything about noise or scent, negative controls included, and three
# gates carried fixture comments explaining that they stayed off `attach_kernel` to dodge it.
#
# docs/30 records the same hazard twice already, for `putDown` and `mourned`: "a static would be
# shared between the two worlds a gate boots."
#
# Both directions, because "B got nothing" would also be true of a field that had stopped
# recording anything at all: A must receive its own noise, **and** B must receive none of it.
func _two_worlds_do_not_share_an_attention_field() -> bool:
	var a: Variant = SimBoot.bare(101, ISOLATION_SIZE)["world"]
	var b: Variant = SimBoot.bare(102, ISOLATION_SIZE)["world"]
	var cell_a: int = int(a.field.cell_at(8.0, 8.0))
	var cell_b: int = int(b.field.cell_at(8.0, 8.0))
	a.events.publish({"type": "noise.emitted", "x": 8.0, "y": 8.0, "magnitude": 500.0})
	a.step()
	var got_a: float = float(a.field.noise[cell_a])
	var got_b: float = float(b.field.noise[cell_b])
	if got_a <= 0.0:
		push_error("the world that published its own noise did not hear it: %.4f" % got_a)
		return false
	if got_b != 0.0:
		push_error("world A's noise landed in world B's field: A %.4f, B %.4f" % [got_a, got_b])
		return false

	# Same again for scent, which travels the other subscription.
	b.events.publish({"type": "scent.accumulated", "x": 8.0, "y": 8.0, "magnitude": 40.0})
	b.step()
	if float(b.field.scent[cell_b]) <= 0.0:
		push_error("world B did not receive its own scent: %.4f" % float(b.field.scent[cell_b]))
		return false
	if float(a.field.scent[cell_a]) != 0.0:
		push_error("world B's scent landed in world A's field: %.4f" % float(a.field.scent[cell_a]))
		return false
	print("ISOLATION OK A hears %.2f of its own noise and B hears none of it, both ways" % got_a)
	return true


# --- the worldgen rebuild ----------------------------------------------------------------------

# --- shared walks ---

func _walkable_outdoors(map: Variant, tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return false
	if SimTileMap.is_solid(map, tx, ty):
		return false
	return not SimTileMap.is_indoors(map, tx, ty)


# A flood fill over open outdoor ground from `start`, plus how much of it there was. Returns
# {seen, total, reached} -- `seen` is per-tile so the enterability lane can ask "is this doorway
# on the street side of the map" without walking it again.
func _outdoor_reach(map: Variant, start: Vector2i) -> Dictionary:
	var w: int = int(map.w)
	var h: int = int(map.h)
	var total: int = 0
	for y in h:
		for x in w:
			if _walkable_outdoors(map, x, y):
				total += 1
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(w * h)
	var reached: int = 0
	if not _walkable_outdoors(map, start.x, start.y):
		return {"seen": seen, "total": total, "reached": 0}
	var queue: Array[Vector2i] = [start]
	seen[start.y * w + start.x] = 1
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		reached += 1
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = at + (step as Vector2i)
			if next.x < 0 or next.y < 0 or next.x >= w or next.y >= h:
				continue
			if seen[next.y * w + next.x] == 1:
				continue
			if not _walkable_outdoors(map, next.x, next.y):
				continue
			seen[next.y * w + next.x] = 1
			queue.append(next)
	return {"seen": seen, "total": total, "reached": reached}


# Every opening in the district wall, as {side, at, run}. Read off the map rather than off what
# the generator says it did: an opening the generator recorded but never carved would pass a
# manifest check and fail this one.
func _wall_openings(map: Variant) -> Array:
	var out: Array = []
	var w: int = int(map.w)
	var h: int = int(map.h)
	for side in ["north", "south", "east", "west"]:
		var length: int = w if (side == "north" or side == "south") else h
		var run: int = 0
		for i in range(length + 1):
			var open: bool = false
			if i < length:
				var tile: Vector2i = _wall_tile(map, String(side), i)
				open = SimTileMap.tile_at(map, tile.x, tile.y) == SimTileMap.Tile.Floor
			if open:
				run += 1
				continue
			if run > 0:
				out.append({"side": String(side), "at": i - run, "run": run})
			run = 0
	return out


func _wall_tile(map: Variant, side: String, along: int) -> Vector2i:
	match side:
		"north":
			return Vector2i(along, 0)
		"south":
			return Vector2i(along, int(map.h) - 1)
		"east":
			return Vector2i(int(map.w) - 1, along)
		_:
			return Vector2i(0, along)


# --- 1. it builds a district ---

func _the_generator_builds_a_district() -> bool:
	var shipped: Variant = SimWorldgen.generate(CANON_SEED, SHIPPED_SIZE, _tree())
	var count: int = (shipped.buildings as Array).size()
	if not _count_in_band(count, SHIPPED_SIZE):
		push_error("seed %d at %d placed %d buildings, docs/24's band is %d..%d" % [
			CANON_SEED, SHIPPED_SIZE, count, BUILDINGS_256_MIN, BUILDINGS_256_MAX,
		])
		return false
	var kinds: Dictionary = {}
	for record in shipped.buildings as Array:
		kinds[String((record as Dictionary)["id"])] = true
	if kinds.size() < 6:
		push_error("a district of %d buildings drew only %d different footprints" % [count, kinds.size()])
		return false

	# The miniature, on every seed the balance harness runs, because those are the campaigns whose
	# bands are measured against this layout.
	var small: Array[int] = []
	for seed_value in [20260805, 404, 31337, 90210]:
		var map: Variant = SimWorldgen.generate(int(seed_value), GATE_SIZE, _tree())
		var n: int = (map.buildings as Array).size()
		small.append(n)
		if not _count_in_band(n, GATE_SIZE):
			push_error("seed %d at %d placed %d buildings, floor is %d -- the gate size is generating an empty district again" % [
				int(seed_value), GATE_SIZE, n, BUILDINGS_64_MIN,
			])
			return false

	# The true negative. A district that declares density 0 places nothing, and the band above has
	# to say so -- without this, a count lane that had stopped counting would pass on every seed.
	var empty: Dictionary = _fixture_district("district.fixture.empty", 0.0, [{"tag": "residential", "weight": 1}])
	var barren: Variant = SimWorldgen.generate(CANON_SEED, SHIPPED_SIZE, _tree_with(empty), String(empty["id"]))
	if (barren.buildings as Array).size() != 0:
		push_error("a district with density 0 still placed %d buildings" % (barren.buildings as Array).size())
		return false
	if _count_in_band(0, SHIPPED_SIZE) or _count_in_band(0, GATE_SIZE):
		push_error("the building-count band accepts zero buildings, which is what it exists to reject")
		return false

	print("DENSITY OK %d buildings at %d over %d footprints, %s at %d across four seeds; a density-0 district places none" % [
		count, SHIPPED_SIZE, kinds.size(), str(small), GATE_SIZE,
	])
	return true


func _count_in_band(count: int, size: int) -> bool:
	if size >= SHIPPED_SIZE:
		return count >= BUILDINGS_256_MIN and count <= BUILDINGS_256_MAX
	return count >= BUILDINGS_64_MIN


# A district type built here rather than shipped, so a lane can change one field and watch the
# world change. Shipping it would be content nothing plays.
func _fixture_district(id: String, density: float, pool: Array) -> Dictionary:
	return {
		"id": id,
		"name": "fixture",
		"type": "fixture",
		"streets": {"blockMin": 24, "blockMax": 40, "streetWidth": 6},
		"connectionPoints": {"north": 1, "south": 1, "east": 1, "west": 1},
		"density": density,
		"pool": pool,
	}


func _tree_with(district: Dictionary) -> Dictionary:
	var tree: Dictionary = _tree().duplicate()
	tree["districts/zz_fixture.json"] = district
	return tree


# --- 2. the roads leave where the district says they do ---

func _the_roads_leave_where_the_district_says_they_do() -> bool:
	var district: Dictionary = SimWorldgen.district_of(_tree(), SimWorldgen.DEFAULT_DISTRICT)
	var declared: Dictionary = district.get("connectionPoints", {}) as Dictionary
	var wanted: int = 0
	for side in declared.keys():
		wanted += int(declared[side])
	if wanted < 1:
		push_error("the shipped district declares no connection points, so this lane judges nothing")
		return false

	for size in [GATE_SIZE, SHIPPED_SIZE]:
		var map: Variant = SimWorldgen.generate(CANON_SEED, int(size), _tree())
		var openings: Array = _wall_openings(map)
		var by_side: Dictionary = {}
		for opening in openings:
			var side: String = String((opening as Dictionary)["side"])
			by_side[side] = int(by_side.get(side, 0)) + 1
		for side in ["north", "south", "east", "west"]:
			if int(by_side.get(side, 0)) != int(declared.get(side, 0)):
				push_error("at %d the %s wall has %d openings, the district declares %d" % [
					int(size), String(side), int(by_side.get(side, 0)), int(declared.get(side, 0)),
				])
				return false
		# A road, not a hole: paved ground on the inside of every opening, and the opening itself
		# walkable.
		var first_inside: Vector2i = Vector2i(-1, -1)
		for opening in openings:
			var o: Dictionary = opening as Dictionary
			var centre: int = int(o["at"]) + int(o["run"]) / 2
			var mouth: Vector2i = _wall_tile(map, String(o["side"]), centre)
			if not _walkable_outdoors(map, mouth.x, mouth.y):
				push_error("the %s opening at %d is not walkable" % [String(o["side"]), centre])
				return false
			var inside: Vector2i = _inward(map, String(o["side"]), mouth)
			if int(map.surfaces[inside.y * int(map.w) + inside.x]) != SimTileMap.SURFACE_PAVED:
				push_error("the %s opening at %d has no street behind it: surface %d" % [
					String(o["side"]), centre, int(map.surfaces[inside.y * int(map.w) + inside.x]),
				])
				return false
			if first_inside.x < 0:
				first_inside = inside

		# And no sealed quadrants: a walk in through the first road reaches the district.
		var walk: Dictionary = _outdoor_reach(map, first_inside)
		var share: float = float(walk["reached"]) / float(maxi(1, int(walk["total"])))
		if share < REACH_SHARE_MIN:
			push_error("at %d a walk in from a connection point reached %.1f%% of the outdoor ground, floor is %.0f%%" % [
				int(size), 100.0 * share, 100.0 * REACH_SHARE_MIN,
			])
			return false
		print("ROADS OK at %d: %d openings matching the declared %s, each with pavement behind it, and a walk in covers %.1f%% of %d outdoor tiles" % [
			int(size), openings.size(), str(declared), 100.0 * share, int(walk["total"]),
		])

	# The true negative: a district that declares none gets none, so the count above is reading the
	# entry rather than counting whatever the generator felt like carving.
	var shut: Dictionary = _fixture_district("district.fixture.shut", 0.4, [{"tag": "residential", "weight": 1}])
	shut["connectionPoints"] = {"north": 0, "south": 0, "east": 0, "west": 0}
	var sealed: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, _tree_with(shut), String(shut["id"]))
	if not _wall_openings(sealed).is_empty():
		push_error("a district declaring no connection points still opened %s" % str(_wall_openings(sealed)))
		return false
	print("ROADS OK a district that declares no roads has an unbroken wall")
	return true


func _inward(map: Variant, side: String, mouth: Vector2i) -> Vector2i:
	match side:
		"north":
			return Vector2i(mouth.x, mouth.y + 1)
		"south":
			return Vector2i(mouth.x, mouth.y - 1)
		"east":
			return Vector2i(mouth.x - 1, mouth.y)
		_:
			return Vector2i(mouth.x + 1, mouth.y)


# --- 3. every building can be entered ---

# The sandbox goal made mechanical. Rooms are found on the map rather than read off the
# generator's manifest -- connected runs of indoor floor -- so this holds the annex to the same
# standard as anything the placer put down, and a manifest that lied about a building would show
# up as a room count that disagrees.
func _room_problems(map: Variant, reached: PackedByteArray) -> Dictionary:
	var w: int = int(map.w)
	var h: int = int(map.h)
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(w * h)
	var problems: Array[String] = []
	var rooms: int = 0
	for y in h:
		for x in w:
			var idx: int = y * w + x
			if seen[idx] == 1:
				continue
			if not SimTileMap.is_indoors(map, x, y) or SimTileMap.is_solid(map, x, y):
				continue
			rooms += 1
			var members: Array[Vector2i] = []
			var queue: Array[Vector2i] = [Vector2i(x, y)]
			seen[idx] = 1
			var enterable: bool = false
			while not queue.is_empty():
				var at: Vector2i = queue.pop_back()
				members.append(at)
				for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var next: Vector2i = at + (step as Vector2i)
					if next.x < 0 or next.y < 0 or next.x >= w or next.y >= h:
						continue
					# A doorway is the tile that is open, not indoors, and stands on ground the
					# street reaches. Standing next to one is what "you can get in" means.
					if reached[next.y * w + next.x] == 1:
						enterable = true
						continue
					if seen[next.y * w + next.x] == 1:
						continue
					if not SimTileMap.is_indoors(map, next.x, next.y) or SimTileMap.is_solid(map, next.x, next.y):
						continue
					seen[next.y * w + next.x] = 1
					queue.append(next)
			if not enterable:
				problems.append("the room of %d tiles at %s has no doorway onto ground the street reaches" % [members.size(), str(members[0])])
	return {"problems": problems, "rooms": rooms}


func _every_building_can_be_entered() -> bool:
	# The booted map, because the colony is a building too and the one that matters most.
	for size in [GATE_SIZE, SHIPPED_SIZE]:
		var boot: Dictionary = SimBoot.bare(CANON_SEED, int(size))
		var map: Variant = boot["map"]
		var start: Vector2i = _first_open_street(map)
		var walk: Dictionary = _outdoor_reach(map, start)
		var found: Dictionary = _room_problems(map, walk["seen"] as PackedByteArray)
		var problems: Array = found["problems"] as Array
		if not problems.is_empty():
			for p in problems:
				push_error("at %d: %s" % [int(size), String(p)])
			return false
		var placed: int = (map.buildings as Array).size()
		if int(found["rooms"]) < placed + 1:
			push_error("at %d the placer recorded %d buildings and the annex, but the map holds only %d indoor rooms" % [
				int(size), placed, int(found["rooms"]),
			])
			return false
		# The annex specifically: its own door has to be on the reachable side.
		var gate: Vector2i = SimTileMap.gate_a(map)
		if (walk["seen"] as PackedByteArray)[gate.y * int(map.w) + gate.x] != 1:
			push_error("at %d the colony's gate at %s is not reachable from the street" % [int(size), str(gate)])
			return false
		print("ENTERABLE OK at %d: %d rooms behind %d placed buildings and the annex, every one has a doorway onto the street, the gate included" % [
			int(size), int(found["rooms"]), placed,
		])

	# The true negative: brick the door up and the same walk has to fail. Without this, a lane that
	# had stopped finding rooms at all would report every district enterable.
	var bricked: Dictionary = _bricked_template()
	var tree: Dictionary = _tree_with(_fixture_district("district.fixture.sealed", 1.0, [{"tag": "sealed", "weight": 1}]))
	tree["buildings/zz_sealed.json"] = bricked
	var sealed_map: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, tree, "district.fixture.sealed")
	if (sealed_map.buildings as Array).is_empty():
		push_error("the sealed fixture district placed nothing, so the negative proves nothing")
		return false
	var sealed_walk: Dictionary = _outdoor_reach(sealed_map, _first_open_street(sealed_map))
	var sealed_found: Dictionary = _room_problems(sealed_map, sealed_walk["seen"] as PackedByteArray)
	if (sealed_found["problems"] as Array).is_empty():
		push_error("%d bricked-up buildings and the enterability walk found nothing wrong with any of them" % (sealed_map.buildings as Array).size())
		return false
	print("ENTERABLE OK a district of %d bricked-up shells reports %d unreachable rooms" % [
		(sealed_map.buildings as Array).size(), (sealed_found["problems"] as Array).size(),
	])
	return true


# The sound 9x7 house with its one door replaced by wall. Everything else -- the doors list, the
# indoors flags -- still says there is a door there, which is exactly the lie the lane has to see
# through.
func _bricked_template() -> Dictionary:
	var w: int = 9
	var h: int = 7
	var tiles: Array = []
	var surfaces: Array = []
	var indoors: Array = []
	for y in h:
		for x in w:
			var edge: bool = x == 0 or y == 0 or x == w - 1 or y == h - 1
			tiles.append(SimTileMap.Tile.Wall if edge else SimTileMap.Tile.Floor)
			surfaces.append(SimTileMap.SURFACE_PAVED)
			indoors.append(0 if edge else 1)
	return {
		"id": "building.fixture.sealed",
		"name": "bricked up",
		"size": {"w": w, "h": h},
		"tiles": tiles,
		"surfaces": surfaces,
		"indoors": indoors,
		"doors": [{"x": 4, "y": 6}],
		"tags": ["sealed"],
		"weight": 1,
	}


func _first_open_street(map: Variant) -> Vector2i:
	# The tile inside the first opening in the wall, or failing that the first walkable tile.
	var openings: Array = _wall_openings(map)
	for opening in openings:
		var o: Dictionary = opening as Dictionary
		var mouth: Vector2i = _wall_tile(map, String(o["side"]), int(o["at"]) + int(o["run"]) / 2)
		var inside: Vector2i = _inward(map, String(o["side"]), mouth)
		if _walkable_outdoors(map, inside.x, inside.y):
			return inside
	for y in int(map.h):
		for x in int(map.w):
			if _walkable_outdoors(map, x, y):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


# --- 4. the same inputs build the same district ---

func _the_same_inputs_build_the_same_district() -> bool:
	var first: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, _tree())
	var again: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, _tree())
	for field in ["tiles", "surfaces", "indoors"]:
		if _first_difference(first.get(String(field)) as PackedByteArray, again.get(String(field)) as PackedByteArray) >= 0:
			push_error("two generations of seed %d disagreed about %s" % [CANON_SEED, String(field)])
			return false
	if (first.buildings as Array).size() != (again.buildings as Array).size():
		push_error("two generations of seed %d placed different numbers of buildings" % CANON_SEED)
		return false
	var other: Variant = SimWorldgen.generate(CANON_SEED + 1, GATE_SIZE, _tree())
	if _first_difference(first.tiles as PackedByteArray, other.tiles as PackedByteArray) < 0:
		push_error("a different seed built the identical district -- the seed is not reaching the generator")
		return false

	# Layout and dressing are independent, which is the property docs/30 recorded for the occluder
	# pass and this rebuild had to keep under new stream names. Generated with the dressing off,
	# every tile is either the tile the full run has, or a tile the dressing is allowed to have put
	# there: a window in a wall, or screening, a wreck or a tree on open ground. `indoors` may not
	# move at all -- nothing the dressing does is allowed to make or unmake a room.
	var layout: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, _tree(), SimWorldgen.DEFAULT_DISTRICT, false)
	if _first_difference(first.indoors as PackedByteArray, layout.indoors as PackedByteArray) >= 0:
		push_error("the dressing passes changed which tiles are indoors")
		return false
	if (layout.buildings as Array).size() != (first.buildings as Array).size():
		push_error("the dressing passes changed how many buildings were placed")
		return false
	var moved: int = 0
	for i in (first.tiles as PackedByteArray).size():
		var before: int = int((layout.tiles as PackedByteArray)[i])
		var after: int = int((first.tiles as PackedByteArray)[i])
		if before == after:
			continue
		moved += 1
		var window: bool = before == SimTileMap.Tile.Wall and after == SimTileMap.Tile.Window
		var planted: bool = before == SimTileMap.Tile.Floor and (
			after == SimTileMap.Tile.Screen or after == SimTileMap.Tile.Low or after == SimTileMap.Tile.Tree
		)
		if not window and not planted:
			push_error("tile %d is %d with the dressing off and %d with it on -- the dressing moved the layout" % [i, before, after])
			return false
	if moved == 0:
		push_error("the dressing changed nothing at all, so this property is asserting nothing")
		return false
	print("DETERMINISM OK seed %d is byte-identical twice and differs from %d; the dressing moved %d tiles and no walls" % [
		CANON_SEED, CANON_SEED + 1, moved,
	])
	return true


func _first_difference(a: PackedByteArray, b: PackedByteArray) -> int:
	if a.size() != b.size():
		return 0
	for i in a.size():
		if a[i] != b[i]:
			return i
	return -1


# --- 5. the district entry is read ---

func _the_district_entry_is_read() -> bool:
	var shipped: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, _tree())
	var baseline: int = (shipped.buildings as Array).size()

	# Same seed, same size, a different entry: twice the density and a pool of nothing but sheds.
	# If the generator were reading anything but the district, this would come back identical.
	var denser: Dictionary = _fixture_district("district.fixture.dense", 0.94, [{"tag": "shed", "weight": 1}])
	var dense_map: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, _tree_with(denser), String(denser["id"]))
	var count: int = (dense_map.buildings as Array).size()
	if count <= baseline:
		push_error("doubling the density placed %d buildings against the shipped district's %d" % [count, baseline])
		return false
	var tree: Dictionary = _tree()
	for record in dense_map.buildings as Array:
		var id: String = String((record as Dictionary)["id"])
		var tags: Array = _tags_of(tree, id)
		if not tags.has("shed"):
			push_error("a shed-only pool placed %s, whose tags are %s" % [id, str(tags)])
			return false

	# The second shipped type, which is the whole of docs/30's "two district types ship live, not
	# one and not seven". This is town centre's only reader until the `--district` boot argument
	# lands in the seeded-sandbox slice, and saying so here is cheaper than a comment nobody reads.
	var town: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, _tree(), "district.town_center")
	var placed: int = (town.buildings as Array).size()
	if placed < BUILDINGS_64_MIN:
		push_error("the town centre placed %d buildings at %d" % [placed, GATE_SIZE])
		return false
	var commercial: int = 0
	for record in town.buildings as Array:
		if _tags_of(tree, String((record as Dictionary)["id"])).has("commercial"):
			commercial += 1
	if commercial < 1:
		push_error("a commercial-heavy district placed %d buildings and not one of them commercial" % placed)
		return false
	# `type` is docs/24's character label, and the field the loot slice will select a profile with.
	# Until then this is its only reader, and what it can honestly hold down is that the two live
	# types are declared, distinct, and not a copy of each other's name.
	var types: Dictionary = {}
	for id in [SimWorldgen.DEFAULT_DISTRICT, "district.town_center"]:
		var entry: Dictionary = SimWorldgen.district_of(tree, String(id))
		var label: String = String(entry.get("type", ""))
		if label.is_empty():
			push_error("%s declares no type" % String(id))
			return false
		if types.has(label):
			push_error("%s and %s both call themselves \"%s\"" % [String(id), String(types[label]), label])
			return false
		types[label] = String(id)

	print("DISTRICT DATA OK the shipped suburb places %d at %d, a denser shed-only entry places %d and only sheds, the town centre places %d of which %d are commercial; the two live types are %s" % [
		baseline, GATE_SIZE, count, placed, commercial, str(types.keys()),
	])
	return true


func _tags_of(tree: Dictionary, id: String) -> Array:
	for t in SimWorldgen.templates_of(tree):
		if String((t as Dictionary).get("id", "")) == id:
			return (t as Dictionary).get("tags", []) as Array
	return []


# --- the reserve ---

# The reserve used to be a constant rect two files had to agree about -- `SimWorldgen.ANNEX_RESERVE`
# and `SimBoot.ANNEX_ORIGIN` -- and this lane pinned them together. Both are gone: the generator
# chooses the rect per seed, stamps it, and then holds it clear for the two passes that follow. So
# the question is no longer "do the two constants match" but "does the ground the generator sited
# actually stay the colony's", which is the thing the constants were a proxy for.
func _the_generator_reserves_the_ground_it_sited() -> bool:
	if SimBoot.DEFAULT_DISTRICT != SimWorldgen.DEFAULT_DISTRICT:
		push_error("the boot and the generator disagree about the default district: %s vs %s" % [
			SimBoot.DEFAULT_DISTRICT, SimWorldgen.DEFAULT_DISTRICT,
		])
		return false
	for size in [GATE_SIZE, SHIPPED_SIZE]:
		var map: Variant = SimWorldgen.generate(CANON_SEED, int(size), _tree())
		var sited: Rect2i = SimTileMap.annex_rect(map)
		if sited.size.x <= 0 or sited.size.y <= 0:
			push_error("at %d the generator sited no colony, so there is no reserve to judge" % int(size))
			return false
		# The template's own footprint, so the rect is the annex rather than a number restated here.
		var patch: Variant = SimWorldgen.annex_template_of(_tree())
		if SimTemplates.footprint(patch as Dictionary) != sited.size:
			push_error("the annex rect %s is not the template's footprint %s" % [
				str(sited.size), str(SimTemplates.footprint(patch as Dictionary)),
			])
			return false
		# Nothing built on it or against it: the reserve's whole job downstream of the stamp.
		for record in map.buildings as Array:
			var b: Dictionary = record as Dictionary
			var footprint := Rect2i(int(b["x"]), int(b["y"]), int(b["w"]), int(b["h"]))
			if footprint.intersects(sited.grow(SimWorldgen.RESERVE_MARGIN)):
				push_error("at %d %s at %s was built on the colony's ground %s" % [
					int(size), String(b["id"]), str(footprint), str(sited),
				])
				return false
		# And no generated loot site inside it either -- the only sites in there are the annex
		# template's own two rows, which arrive with the stamp rather than from the district profile.
		var inside: int = 0
		for site in map.sites as Array:
			var s: Dictionary = site as Dictionary
			if sited.has_point(Vector2i(int(s["x"]), int(s["y"]))):
				inside += 1
		var authored: int = ((SimWorldgen.annex_template_of(_tree()) as Dictionary).get("loot", []) as Array).size()
		if inside != authored:
			push_error("at %d the colony's %s holds %d loot sites and its template authored %d" % [
				int(size), str(sited), inside, authored,
			])
			return false
		# The margin it is held clear by is the one the district wall keeps too: a colony jammed
		# against the wall is what ANNEX_BORDER_FULL exists to prevent.
		var margin: int = SimWorldgen.annex_border(int(size))
		if sited.position.x < margin or sited.position.y < margin \
				or sited.position.x + sited.size.x > int(size) - margin \
				or sited.position.y + sited.size.y > int(size) - margin:
			push_error("at %d the colony %s sits inside the %d-tile border margin" % [int(size), str(sited), margin])
			return false
		print("RESERVE OK at %d the colony is sited at %s, %d tiles off the wall, nothing built within %d of it, and the only loot inside it is the %d rows its own template carries" % [
			int(size), str(sited), margin, SimWorldgen.RESERVE_MARGIN, authored,
		])
	return true


# --- the annex, sited per seed --------------------------------------------------------------
#
# The slice: where the colony stands is a property of the seed, and docs/01's fairness rule --
# "No unwinnable starts: generated starting positions are validated for basic survivability" -- is
# the thing that makes that safe rather than merely varied.
#
# Generation-only. Every question below is a question about a map, so none of it boots a world:
# eight seeds at the gate size and two at the shipped size cost about four seconds, where ten
# playable boots would cost minutes.
func _the_colony_is_sited_per_seed_and_survivable() -> bool:
	var placements: Dictionary = {}
	var lines: Array[String] = []
	for pair in [[GATE_SIZE, SITING_SEEDS], [SHIPPED_SIZE, SITING_SEEDS_256]]:
		var size: int = int((pair as Array)[0])
		for seed_value in (pair as Array)[1] as Array[int]:
			var map: Variant = SimWorldgen.generate(int(seed_value), size, _tree())
			var sited: Rect2i = SimTileMap.annex_rect(map)
			if sited.size.x <= 0 or sited.size.y <= 0:
				push_error("seed %d at %d generated a district with no colony on it" % [int(seed_value), size])
				return false

			# Anchors: present, standing room, and inside the annex they belong to.
			var anchors: Array[Vector2i] = [
				SimTileMap.gate_a(map), SimTileMap.gate_b(map),
				SimTileMap.player_start(map), SimTileMap.well_tile(map),
			]
			var names: Array[String] = ["gate_a", "gate_b", "player_start", "well"]
			for i in anchors.size():
				var tile: Vector2i = anchors[i]
				if tile.x < 0 or tile.y < 0 or tile.x >= int(map.w) or tile.y >= int(map.h):
					push_error("seed %d at %d: anchor %s is %s" % [int(seed_value), size, names[i], str(tile)])
					return false
				if not sited.has_point(tile):
					push_error("seed %d at %d: anchor %s at %s is outside the colony %s" % [
						int(seed_value), size, names[i], str(tile), str(sited),
					])
					return false
				if SimTileMap.is_solid(map, tile.x, tile.y):
					push_error("seed %d at %d: anchor %s at %s stands in something solid" % [
						int(seed_value), size, names[i], str(tile),
					])
					return false

			# Every clause of the fairness rule, by name, so a failure says which one.
			var report: Dictionary = SimWorldgen.survivability_report(map)
			if not bool(report["sited"]):
				push_error("seed %d at %d: the survivability pass judged nothing" % [int(seed_value), size])
				return false
			if (report["clauses"] as Array).size() < 6:
				push_error("seed %d at %d: the report carries %d clauses" % [int(seed_value), size, (report["clauses"] as Array).size()])
				return false
			for clause in report["clauses"] as Array:
				if not bool((clause as Dictionary)["ok"]):
					push_error("seed %d at %d failed %s: %s" % [
						int(seed_value), size, String((clause as Dictionary)["name"]), String((clause as Dictionary)["said"]),
					])
					return false
				# A clause is allowed to skip when it has nothing to judge, and a shipped district
				# is never that: it declares roads and it places loot. A skip here would be a clause
				# quietly not running on the district the game actually plays.
				if bool((clause as Dictionary)["skipped"]):
					push_error("seed %d at %d skipped %s on a shipped district: %s" % [
						int(seed_value), size, String((clause as Dictionary)["name"]), String((clause as Dictionary)["said"]),
					])
					return false

			# The same seed sites the same colony. Generation is what a save regenerates from
			# (`check_m2_save.gd` restores into a fresh `SimBoot.bare`), so a colony that moved
			# between two generations of one seed would move under a loaded game.
			var again: Variant = SimWorldgen.generate(int(seed_value), size, _tree())
			if SimTileMap.annex_rect(again) != sited or SimTileMap.gate_a(again) != anchors[0] \
					or SimTileMap.player_start(again) != anchors[2] or SimTileMap.well_tile(again) != anchors[3]:
				push_error("two generations of seed %d at %d put the colony in different places" % [int(seed_value), size])
				return false

			if size == GATE_SIZE:
				placements["%s" % str(sited.position)] = true
				# The director still has somewhere to send a night from. This is the reason the
				# border margin exists: `SimDirector._legal_tile` refuses any tile within
				# GATE_EXCLUSION of a gate, and it draws packets from a three-tile band inside each
				# wall -- so a colony sited badly enough turns a side into no side at all.
				var pools: Array = _spawn_pools(map, SimTileMap.gate_a(map), SimTileMap.gate_b(map))
				for s in 4:
					if int(pools[s]) < 1:
						push_error("seed %d: the colony at %s leaves the %s wall with no legal spawn tile at all (pools %s)" % [
							int(seed_value), str(sited), SimDirector.SIDE_NAMES[s], str(pools),
						])
						return false
				lines.append("%d %s pools %s" % [int(seed_value), str(sited.position), str(pools)])
			else:
				lines.append("%d at %d %s" % [int(seed_value), size, str(sited.position)])

	# The seed reaches the siting, or eight seeds would be one seed asserted eight times.
	if placements.size() < 2:
		push_error("all %d seeds sited the colony at %s -- the seed is not reaching the siting pass" % [
			SITING_SEEDS.size(), str(placements.keys()),
		])
		return false

	# The true negative for the pool walk above: it has to be able to report an empty side, or
	# "every side has tiles" is a sentence about a counter that cannot count. A gate fabricated at
	# the centre of the north wall puts that whole band inside the exclusion disc.
	var probe: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, _tree())
	var against_the_wall := Vector2i(int(probe.w) / 2, 4)
	var starved: Array = _spawn_pools(probe, against_the_wall, against_the_wall)
	if int(starved[0]) != 0:
		push_error("a gate at %s, four tiles off the north wall, still left %d legal north tiles -- the pool walk is not measuring the exclusion" % [
			str(against_the_wall), int(starved[0]),
		])
		return false

	print("SITING OK %d districts sited from their own seed, %d distinct places at %d, every anchor standing inside its colony, every survivability clause true, stable across two generations, every wall keeping a spawn pool: %s" % [
		SITING_SEEDS.size() + SITING_SEEDS_256.size(), placements.size(), GATE_SIZE, ", ".join(lines),
	])
	return true


# `SimDirector._edges_by_side`'s question, asked of a map instead of a world: how many legal spawn
# tiles each wall still has. The director's own `_legal_tile` is what answers it, so this measures
# the rule rather than a second opinion about it.
func _spawn_pools(map: Variant, gate_a: Vector2i, gate_b: Vector2i) -> Array:
	var annex: Rect2i = SimTileMap.annex_rect(map)
	var sides: Array = [0, 0, 0, 0]
	var w: int = int(map.w)
	var h: int = int(map.h)
	for y in h:
		for x in w:
			if x > 2 and x < w - 3 and y > 2 and y < h - 3:
				continue
			if not SimDirector._legal_tile(map, x, y, annex, gate_a, gate_b):
				continue
			if y <= 2:
				sides[0] = int(sides[0]) + 1
			elif y >= h - 3:
				sides[2] = int(sides[2]) + 1
			elif x >= w - 3:
				sides[1] = int(sides[1]) + 1
			else:
				sides[3] = int(sides[3]) + 1
	return sides


# --- the survivability pass can fail ----------------------------------------------------------
#
# A validator that has never said no is a validator nobody has tested, and this one runs on every
# generated district in the game. Both negatives are done to a real district after it generated
# clean, so what changed is the sabotage and nothing else.
func _the_survivability_pass_can_fail() -> bool:
	# 1. The gate bricked up. A colony nobody can walk out of fails `gates-open`, and the walk that
	#    starts at the gate then reaches nothing, which is `gates-reachable` as well.
	var bricked: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, _tree())
	if not bool(SimWorldgen.survivability_report(bricked)["ok"]):
		push_error("the district this negative starts from is already failing, so the sabotage proves nothing")
		return false
	for gate in [SimTileMap.gate_a(bricked), SimTileMap.gate_b(bricked)]:
		var t: Vector2i = gate as Vector2i
		bricked.tiles[t.y * int(bricked.w) + t.x] = SimTileMap.Tile.Wall
	var walled: Dictionary = SimWorldgen.survivability_report(bricked)
	if bool(walled["ok"]):
		push_error("the colony's gate was bricked over and the survivability pass reported no problem")
		return false
	if not (walled["failed"] as Array).has("gates-open"):
		push_error("bricking the gate was reported as %s rather than gates-open" % str(walled["failed"]))
		return false
	if bool(SimWorldgen.clause_of(walled, "gates-reachable")["ok"]):
		push_error("a bricked gate was still reported reachable from a road")
		return false
	# And the clauses the sabotage did not touch are still true, so the report is per clause rather
	# than one verdict wearing six names.
	for untouched in ["player-start", "stations-room", "well-open"]:
		if not bool(SimWorldgen.clause_of(walled, String(untouched))["ok"]):
			push_error("bricking the gate also turned %s false" % String(untouched))
			return false

	# 2. A loot table whose only site is sealed inside a doorless shell. This is the clause that
	#    protects a campaign's balance: a medical store the player can never open is a table the
	#    economy is tuned around and nobody will ever draw from.
	var sealed_map: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, _tree())
	var shell: Vector2i = _room_for_a_shell(sealed_map)
	if shell.x < 0:
		push_error("no open ground on the district to build the sealed shell on")
		return false
	_seal_a_shell(sealed_map, shell)
	var reachable_site: Vector2i = SimTileMap.gate_a(sealed_map)
	# The positive control first: one site of one table, standing on the colony's own doorstep.
	sealed_map.sites = [{"x": reachable_site.x, "y": reachable_site.y, "table": "medical"}]
	if not bool(SimWorldgen.clause_of(SimWorldgen.survivability_report(sealed_map), "loot-reachable")["ok"]):
		push_error("a site standing on the gate tile itself was reported out of reach")
		return false
	# The same table, the same count, inside the shell.
	sealed_map.sites = [{"x": shell.x + 1, "y": shell.y + 1, "table": "medical"}]
	var stranded: Dictionary = SimWorldgen.survivability_report(sealed_map)
	if bool(stranded["ok"]):
		push_error("the district's only medical site was sealed inside a doorless shell at %s and the pass reported no problem" % str(shell))
		return false
	if not (stranded["failed"] as Array).has("loot-reachable"):
		push_error("a sealed loot table was reported as %s rather than loot-reachable" % str(stranded["failed"]))
		return false
	if String(SimWorldgen.clause_of(stranded, "loot-reachable")["said"]).find("medical") < 0:
		push_error("the loot-reachable clause did not name the table it could not reach: %s" % String(SimWorldgen.clause_of(stranded, "loot-reachable")["said"]))
		return false

	# 3. A district too small to hold a colony judges nothing and says so, rather than passing a map
	#    it never looked at.
	var tiny: Dictionary = SimWorldgen.survivability_report(SimWorldgen.generate(CANON_SEED, ISOLATION_SIZE, _tree()))
	if bool(tiny["sited"]) or not (tiny["clauses"] as Array).is_empty():
		push_error("a district at %d with no colony on it was judged as though it had one: %s" % [ISOLATION_SIZE, str(tiny)])
		return false

	# 4. And a clause with nothing to judge skips rather than failing or passing. A district that
	#    declares no roads out has no road for its gate to be reachable from, and reporting that as
	#    an unwinnable start would refuse a district the generator is entitled to build -- while
	#    reporting it as a pass would be the quiet kind of green this repo keeps paying for.
	var shut: Dictionary = _fixture_district("district.fixture.roadless", 0.4, [{"tag": "residential", "weight": 1}])
	shut["connectionPoints"] = {"north": 0, "south": 0, "east": 0, "west": 0}
	var walled_in: Dictionary = SimWorldgen.survivability_report(
		SimWorldgen.generate(CANON_SEED, GATE_SIZE, _tree_with(shut), String(shut["id"]))
	)
	var skipped: Dictionary = SimWorldgen.clause_of(walled_in, "gates-reachable")
	if not bool(skipped.get("skipped", false)):
		push_error("a district with no opening in its wall reported gates-reachable as %s rather than skipping it" % str(skipped))
		return false
	if not bool(walled_in["ok"]):
		push_error("a district with no roads out failed %s -- the skip did not stand it down" % str(walled_in["failed"]))
		return false
	if bool(SimWorldgen.clause_of(walled_in, "loot-reachable").get("skipped", false)):
		push_error("the roadless fixture skipped loot-reachable too, so the skip is not per clause")
		return false

	print("SURVIVABILITY OK a bricked gate fails gates-open and gates-reachable and nothing else, a table sealed in a doorless shell fails loot-reachable and names it, a district too small for a colony judges nothing, and a district with no roads out skips the one clause it cannot answer")
	return true


# Somewhere a 3x3 shell can be built without touching the colony, its ring, or a doorway: open
# outdoor ground with open outdoor ground all round it.
func _room_for_a_shell(map: Variant) -> Vector2i:
	var annex: Rect2i = SimTileMap.annex_rect(map).grow(3)
	for y in range(2, int(map.h) - 5):
		for x in range(2, int(map.w) - 5):
			if annex.has_point(Vector2i(x, y)) or annex.has_point(Vector2i(x + 3, y + 3)):
				continue
			var clear: bool = true
			for j in range(-1, 4):
				for i in range(-1, 4):
					if not _walkable_outdoors(map, x + i, y + j):
						clear = false
			if clear:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _seal_a_shell(map: Variant, at: Vector2i) -> void:
	var w: int = int(map.w)
	for j in 3:
		for i in 3:
			var idx: int = (at.y + j) * w + at.x + i
			var edge: bool = i == 0 or j == 0 or i == 2 or j == 2
			map.tiles[idx] = SimTileMap.Tile.Wall if edge else SimTileMap.Tile.Floor
			map.indoors[idx] = 0 if edge else 1


# --- re-siting ----------------------------------------------------------------------------------
#
# The loop that advances to the next-ranked lot when a district comes out unsurvivable. It is the
# half of the slice a passing seed never exercises, so this finds out whether any tested seed does
# -- and says so loudly and tests it synthetically when none does, rather than reporting a lane
# that ran nothing as a lane that passed.
func _a_refused_candidate_moves_the_colony_to_the_next_one() -> bool:
	var district: Dictionary = SimWorldgen.district_of(_tree(), SimWorldgen.DEFAULT_DISTRICT)
	var patch: Variant = SimWorldgen.annex_template_of(_tree())
	var footprint: Vector2i = SimTemplates.footprint(patch as Dictionary)
	var natural: Array[String] = []
	var ranked: Array = []
	for seed_value in SITING_SEEDS:
		var ground: Dictionary = SimWorldgen.layout(int(seed_value), GATE_SIZE, district)
		var candidates: Array = SimWorldgen.annex_candidates(int(seed_value), ground["map"], ground["parcels"] as Array, footprint)
		if candidates.size() < 2:
			push_error("seed %d ranked %d candidate lots -- there is no second one to move to" % [int(seed_value), candidates.size()])
			return false
		var sited: Rect2i = SimTileMap.annex_rect(SimWorldgen.generate(int(seed_value), GATE_SIZE, _tree()))
		var at: int = candidates.find(sited)
		if at < 0:
			push_error("seed %d sited the colony at %s, which is not one of the %d lots the scorer ranked" % [
				int(seed_value), str(sited), candidates.size(),
			])
			return false
		if at > 0:
			natural.append("%d took candidate %d" % [int(seed_value), at])
		if int(seed_value) == CANON_SEED:
			ranked = candidates

	if not natural.is_empty():
		print("RE-SITE OK exercised naturally: %s" % ", ".join(natural))
		return true

	# Nothing to judge. Say so -- loudly, and by name -- and then exercise the loop deliberately,
	# because a loop that has never run is a loop nobody has tested.
	print("RE-SITE SKIPPED no tested seed makes its first-ranked lot fail survivability: all %d sited on candidate 0, so the natural half of this lane judged nothing" % SITING_SEEDS.size())

	var first: Rect2i = ranked[0] as Rect2i
	var second: Rect2i = ranked[1] as Rect2i
	var moved: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, _tree(), SimWorldgen.DEFAULT_DISTRICT, true, func(rect: Rect2i) -> bool:
		return rect == first
	)
	var landed: Rect2i = SimTileMap.annex_rect(moved)
	if landed == first:
		push_error("the top candidate %s was refused and the generator sited there anyway" % str(first))
		return false
	if landed != second:
		push_error("refusing %s sited the colony at %s, and the second-ranked lot is %s" % [str(first), str(landed), str(second)])
		return false
	# And the district that came out of the re-site is a whole district, not a stamp moved sideways:
	# the buildings were re-placed around the new reserve and it is survivable in its own right.
	var report: Dictionary = SimWorldgen.survivability_report(moved)
	if not bool(report["ok"]):
		push_error("the re-sited district failed %s" % str(report["failed"]))
		return false
	for record in moved.buildings as Array:
		var b: Dictionary = record as Dictionary
		if Rect2i(int(b["x"]), int(b["y"]), int(b["w"]), int(b["h"])).intersects(landed.grow(SimWorldgen.RESERVE_MARGIN)):
			push_error("after the re-site %s still stands on the colony's new ground %s" % [String(b["id"]), str(landed)])
			return false
	# The anchors followed, rather than staying where the refused candidate would have put them.
	if not landed.has_point(SimTileMap.gate_a(moved)) or not landed.has_point(SimTileMap.player_start(moved)):
		push_error("the colony moved to %s but its anchors are at %s / %s" % [
			str(landed), str(SimTileMap.gate_a(moved)), str(SimTileMap.player_start(moved)),
		])
		return false
	print("RE-SITE OK exercised synthetically: refusing the top lot %s sites the colony at the second, %s, with its buildings re-placed around it and every survivability clause true" % [
		str(first), str(landed),
	])
	return true
