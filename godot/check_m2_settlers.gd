extends SceneTree
# The settlers' camp -- the twelfth piece of the owner's 2026-09-14 procedural-population arc, and
# the first time the allegiance seam carries bodies the sim actually spawned.
#
# A camp is easy to get wrong in a way nothing notices: three more people standing in a district
# of forty buildings look, to anything that only counts, exactly like three more colonists. So
# every lane here carries its true negative in the same fixture as its positive.
#
#   CONTENT  `content/colony/settlers.json`'s shape. Nothing else in the tree will ever check it:
#            `content/colony/` has no schema and no validator type (`content_validator.gd` does
#            not list it) and the frozen oracle's CONTENT_TYPES never reaches it. Negative: six
#            fabricated blocks, each refused by the same predicate.
#   SITED    the camp is indoors, inside the building the component names, at least the declared
#            distance from both gates, outside the annex, **and not in a building the generator
#            already put a body to sleep in**, and the same seed sites it twice in the same place.
#            Negative: the predicates are shown refusing a fabricated outdoor tile and a
#            fabricated rect sitting on a gate, and the sleeper filter is shown refusing a
#            building the manifest names.
#   BODIES   the declared count exists, each carries `identity` and the settlers faction, and
#            **none** carries `needs` or `jobPriorities`. Negative, in the same world: the
#            colony's own people must carry both, or the scanner cannot tell present from absent.
#   LEDGER   the harness's colonist count does not move for the camp. Two halves: the count of
#            `needs` + `body` in a booted world with a camp equals the colony's own size, and
#            giving one settler a `needs` component raises it by one -- so the counter can see a
#            body it is supposed to exclude. Plus the textual half, because a ledger that stops
#            keying on `needs` would make the first half vacuous: `check_m2_balance.gd`'s
#            `_survivors_alive` query line is isolated by name and asked for `"needs"` inside it,
#            never searched for as a bare word anywhere in that file (CLAUDE.md's comfort-gate
#            precedent: a needle a comment can satisfy cannot fail).
#   NO-HEIR  a dying player with a real settler nearer than any colonist: the colonist inherits.
#            Negative: the same body declared colony does inherit. The allegiance gate asserts
#            this on hand-built bodies; this is the same claim against the ones that ship.
#   PROSE    `person_clause` renders every real settler non-empty and digit-free. Negative: the
#            digit scanner must refuse a fabricated clause that carries one.
#   SAVE     the camp round-trips: the settlement's rect, its member Array, and each member still
#            a settler with no `needs`. Negative: a world booted on a seed with no camp restores
#            without one, and the member ids are resolved back to live bodies rather than
#            compared as numbers -- an Array of ids that comes back pointing at nothing is
#            exactly the silent-empty-memory shape CLAUDE.md's JSON-keys trap describes.
#   SKIP     a seed whose district has nowhere legal for a camp says so on its own line and the
#            lane fails only if *every* pair is empty. This is not hypothetical: at 64 tiles seed
#            20260805 has no building far enough from home at all, and seed 404's one far building
#            already holds a sleeping body, so two of the eight pairs skip. Measured.
#
# What this gate deliberately does not assert, because the slice deliberately does not build it:
# that a settler does anything. They stand where they were spawned. Behaviour is docs/23's next
# piece.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimAllegiance = preload("res://sim/modules/allegiance.gd")
const SimDirector = preload("res://sim/modules/director.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimPeople = preload("res://sim/modules/people.gd")
const SimRecruits = preload("res://sim/modules/recruits.gd")
const SimSave = preload("res://sim/save.gd")
const SimSettlers = preload("res://sim/modules/settlers.gd")
const SimSurvivors = preload("res://sim/modules/survivors.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimWorldgen = preload("res://sim/map/worldgen.gd")
const ContentLoader = preload("res://platform/content_loader.gd")

# The balance harness's seeds, so this lane and that one are talking about the same districts, and
# the two sizes every gate cares about: the 64-tile miniature the chain boots and the shipped 256.
const FAST_SEEDS: Array[int] = [20260805, 404, 31337, 90210]
const GATE_TILES: int = 64
const SHIPPED_TILES: int = 256

# The one seed/size pair the whole gate leans on for its single-world lanes. Picked because it has
# a camp at the gates' own size, so the expensive lanes never pay for a 256-tile boot. It was 404
# until the sleeper filter landed: that district has exactly one building far enough from home and
# the generator had already put a body to sleep in it, so 404 now sites no camp at 64 at all. Any
# lane that finds no camp here says so and fails rather than passing quietly, which is how that
# was noticed.
const LANE_SEED: int = 31337
const LANE_TILES: int = GATE_TILES

const BALANCE_SOURCE: String = "res://check_m2_balance.gd"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _content() and ok
	ok = _sited() and ok
	ok = _bodies() and ok
	ok = _ledger() and ok
	ok = _no_heir() and ok
	ok = _prose() and ok
	ok = _save() and ok
	if ok:
		print("M2_SETTLERS_OK content sited bodies ledger no-heir prose save")
		quit(0)
	else:
		push_error("M2_SETTLERS_FAIL")
		quit(1)


# --- CONTENT ------------------------------------------------------------------------------------

# Why the block is bad, or "" when it is not. One predicate, fed the shipped file and then six
# fabrications, so the lane's positive and its negative are literally the same code.
#
# `item_ids` is the set of base ids in the content tree: a kit naming an item that does not exist
# spawns nothing and drops nothing, which is a silent empty pack rather than an error.
func _block_bad(block: Variant, item_ids: Dictionary) -> String:
	if not (block is Dictionary):
		return "is not an object"
	var b: Dictionary = block as Dictionary
	if String(b.get("id", "")) != SimSettlers.POOL_ID:
		return "has id `%s`, not `%s` -- `SimPeople.pool` finds this block by id and nothing else" % [String(b.get("id", "")), SimSettlers.POOL_ID]
	if not b.has("count"):
		return "declares no `count`"
	if typeof(b["count"]) != TYPE_INT and typeof(b["count"]) != TYPE_FLOAT:
		return "declares a `count` that is not a number"
	if int(b["count"]) < 1:
		return "declares `count` %d -- a camp of nobody is a camp nothing can find" % int(b["count"])
	if not b.has("minMetres"):
		return "declares no `minMetres`"
	if typeof(b["minMetres"]) != TYPE_INT and typeof(b["minMetres"]) != TYPE_FLOAT:
		return "declares a `minMetres` that is not a number"
	if float(b["minMetres"]) < SimDirector.GATE_EXCLUSION:
		return "declares `minMetres` %.1f, inside the director's own gate exclusion of %.1f -- a camp may not sit where a night packet may not land" % [float(b["minMetres"]), SimDirector.GATE_EXCLUSION]
	if not (b.get("kit") is Array):
		return "declares no `kit` array"
	var kit: Array = b["kit"] as Array
	if kit.is_empty():
		return "declares an empty `kit`"
	for row in kit:
		var item_id: String = ""
		if row is Dictionary:
			var r: Dictionary = row as Dictionary
			item_id = String(r.get("item", ""))
			if item_id.is_empty():
				return "has a kit row `%s` naming no item" % str(r)
			if r.has("chance"):
				var c: float = float(r["chance"])
				if c <= 0.0 or c > 1.0:
					return "has a kit row for `%s` with chance %.2f, which is not odds" % [item_id, c]
			if r.has("count") and int(r["count"]) < 1:
				return "has a kit row for `%s` with count %d" % [item_id, int(r["count"])]
		elif row is String:
			item_id = String(row)
		else:
			return "has a kit row that is neither an id nor an object: %s" % str(row)
		if not item_ids.has(item_id):
			return "names `%s` in its kit, which is not an item in the content tree" % item_id
	return ""


func _item_ids(tree: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for path in tree.keys():
		if not String(path).begins_with("items/"):
			continue
		var raw: Variant = tree[path]
		var entries: Array = raw as Array if raw is Array else [raw]
		for entry in entries:
			if entry is Dictionary:
				out[String((entry as Dictionary).get("id", ""))] = true
	return out


func _content() -> bool:
	var lane: String = "CONTENT"
	var tree: Dictionary = ContentLoader.load_tree()
	var items: Dictionary = _item_ids(tree)
	if items.size() < 10:
		push_error("%s: the content tree yielded %d item ids, so the kit check below judges nothing" % [lane, items.size()])
		return false
	# Found the way the sim finds it -- by id through `SimPeople.pool` -- rather than by path, so
	# a file renamed or moved under `content/colony/` fails here for the same reason it would fail
	# at boot.
	var block: Dictionary = SimPeople.pool(_pool_world(tree), SimSettlers.POOL_ID)
	if block.is_empty():
		push_error("%s: no block with id `%s` anywhere in the content tree" % [lane, SimSettlers.POOL_ID])
		return false
	var why: String = _block_bad(block, items)
	if why != "":
		push_error("%s: the shipped settlers block %s" % [lane, why])
		return false
	# The negative, through the identical predicate. Each of these is a real mistake somebody
	# could make in this file, and the shallow validator would pass every one of them.
	var good: Dictionary = block.duplicate(true)
	var fabrications: Array[Dictionary] = []
	var no_id: Dictionary = good.duplicate(true)
	no_id["id"] = "colony.generator.settler"
	fabrications.append({"why": "a near-miss id", "block": no_id})
	var no_count: Dictionary = good.duplicate(true)
	no_count.erase("count")
	fabrications.append({"why": "no count", "block": no_count})
	var near: Dictionary = good.duplicate(true)
	near["minMetres"] = 4.0
	fabrications.append({"why": "a camp on the doorstep", "block": near})
	var bad_item: Dictionary = good.duplicate(true)
	bad_item["kit"] = ["item.does.not.exist"]
	fabrications.append({"why": "a kit naming nothing", "block": bad_item})
	var bad_chance: Dictionary = good.duplicate(true)
	bad_chance["kit"] = [{"item": "item.bandage.cloth", "chance": 60.0}]
	fabrications.append({"why": "a percentage where odds go", "block": bad_chance})
	fabrications.append({"why": "not an object at all", "block": {}})
	for f in fabrications:
		var fb: Variant = f["block"]
		if fb is Dictionary and (fb as Dictionary).is_empty():
			fb = []
		if _block_bad(fb, items) == "":
			push_error("%s: the predicate accepted %s, so its acceptance of the shipped file proves nothing" % [lane, String(f["why"])])
			return false
	print("%s OK count=%d minMetres=%.1f kit=%d rows over %d known items; %d fabrications refused" % [
		lane, SimSettlers.count_of(block), SimSettlers.min_metres_of(block),
		(block["kit"] as Array).size(), items.size(), fabrications.size(),
	])
	return true


# A content-only stand-in for a world: `SimPeople.pool` reads `world.content` and nothing else, so
# this saves the gate a district boot it does not need.
func _pool_world(tree: Dictionary) -> Variant:
	var w: Variant = World.new(_fixture(1))
	w.content = tree
	return w


func _fixture(seed_val: int) -> Dictionary:
	return {"seed": seed_val, "tick_hz": 20, "map": {"width": 24, "height": 24, "walls": []}, "player": {"id": 0, "x": 2.0, "y": 2.0, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}


# --- SITED (and SKIP) ---------------------------------------------------------------------------

# The camp entity of a booted world, or -1. Exactly one is expected; two would be a boot that ran
# the spawner twice, which is worth saying out loud rather than silently reading the first.
func _camp_of(w: Variant) -> int:
	var found: Array = w.components.query(["settlement"])
	if found.size() > 1:
		return -2
	return int(found[0]) if found.size() == 1 else -1


# The nearest distance from a rect to either gate anchor, in metres -- `far_buildings`' own
# measure, written out here rather than imported, so the lane is judging the geometry and not
# re-running the code that chose it.
func _metres_to_home(map: Variant, rect: Rect2i) -> float:
	var best: float = 1e12
	for gate in [SimTileMap.gate_a(map), SimTileMap.gate_b(map)]:
		if gate.x < 0 or gate.y < 0:
			continue
		var nx: float = float(clampi(gate.x, rect.position.x, rect.position.x + rect.size.x - 1))
		var ny: float = float(clampi(gate.y, rect.position.y, rect.position.y + rect.size.y - 1))
		var dx: float = nx - float(gate.x)
		var dy: float = ny - float(gate.y)
		best = minf(best, sqrt(dx * dx + dy * dy))
	return best


func _tile_of(w: Variant, ent: int) -> Vector2i:
	var p: Variant = w.components.get_component(ent, "position")
	if not (p is Dictionary):
		return Vector2i(-1, -1)
	return Vector2i(floori(float((p as Dictionary)["x"])), floori(float((p as Dictionary)["y"])))


func _sited() -> bool:
	var lane: String = "SITED"
	var judged: int = 0
	var skipped: int = 0
	for size in [GATE_TILES, SHIPPED_TILES]:
		for seed_value in FAST_SEEDS:
			var w: Variant = SimBoot.playable(int(seed_value), int(size))["world"]
			var camp: int = _camp_of(w)
			if camp == -2:
				push_error("%s: seed %d at %d booted more than one settlement" % [lane, int(seed_value), int(size)])
				return false
			if camp < 0:
				var far: Array[int] = SimWorldgen.far_buildings(w.tilemap, SimSettlers.min_metres_of(SimSettlers.pool(w)))
				# Said out loud rather than passed quietly. At 64 the miniature's gate exclusion
				# disc covers most of the map, so this is the ordinary case there, not a defect.
				print("SETTLERS SKIP seed %d at %d has %d building(s) far enough out and no camp" % [int(seed_value), int(size), far.size()])
				skipped += 1
				continue
			var s: Dictionary = w.components.get_component(camp, "settlement") as Dictionary
			var rect: Rect2i = Rect2i(int(s["x"]), int(s["y"]), int(s["w"]), int(s["h"]))
			var declared: float = SimSettlers.min_metres_of(SimSettlers.pool(w))
			var why: String = _camp_bad(w, rect, declared)
			if why != "":
				push_error("%s: seed %d at %d -- the camp %s" % [lane, int(seed_value), int(size), why])
				return false
			# The building the component names is the building the layout has there.
			var building: Dictionary = (w.tilemap.buildings as Array)[int(s["building"])] as Dictionary
			if Rect2i(int(building["x"]), int(building["y"]), int(building["w"]), int(building["h"])) != rect:
				push_error("%s: seed %d at %d -- the settlement's rect %s is not building %d's %s" % [lane, int(seed_value), int(size), str(rect), int(s["building"]), str(building)])
				return false
			# And nobody was already asleep in it. The dormant pass draws from the same
			# `far_buildings` list at the same distance, so the two compete for one set of
			# houses; `check_m2_dormant.gd`'s ASLEEP lane went red the first time the camp was
			# allowed to share one, because people breathing beside a body that wakes on scent
			# wakes it. Asserted here rather than left to that gate to rediscover.
			if _sleepers_in(w.tilemap).has(int(s["building"])):
				push_error("%s: seed %d at %d -- the camp is in building %d, which the generator already put a body to sleep in" % [lane, int(seed_value), int(size), int(s["building"])])
				return false
			for m in s["members"] as Array:
				var tile: Vector2i = _tile_of(w, int(m))
				if not rect.has_point(tile):
					push_error("%s: seed %d at %d -- a settler stands at %s, outside the camp's own rect %s" % [lane, int(seed_value), int(size), str(tile), str(rect)])
					return false
				if _tile_bad(w.tilemap, tile) != "":
					push_error("%s: seed %d at %d -- a settler stands at %s, which %s" % [lane, int(seed_value), int(size), str(tile), _tile_bad(w.tilemap, tile)])
					return false
			judged += 1
	if judged < 1:
		push_error("%s: not one of the %d seed/size pairs sited a camp, so nothing here was judged" % [lane, FAST_SEEDS.size() * 2])
		return false
	# Deterministic for a seed: the same district booted twice puts the camp in the same building
	# and its people on the same tiles.
	var a: Variant = SimBoot.playable(LANE_SEED, LANE_TILES)["world"]
	var b: Variant = SimBoot.playable(LANE_SEED, LANE_TILES)["world"]
	if _camp_of(a) < 0 or _camp_of(b) < 0:
		push_error("%s: seed %d at %d sites no camp, so the determinism half has nothing to compare -- pick another LANE_SEED" % [lane, LANE_SEED, LANE_TILES])
		return false
	var sa: Dictionary = a.components.get_component(_camp_of(a), "settlement") as Dictionary
	var sb: Dictionary = b.components.get_component(_camp_of(b), "settlement") as Dictionary
	if int(sa["building"]) != int(sb["building"]):
		push_error("%s: seed %d sited the camp in building %d and then in building %d" % [lane, LANE_SEED, int(sa["building"]), int(sb["building"])])
		return false
	var tiles_a: Array[Vector2i] = []
	var tiles_b: Array[Vector2i] = []
	for m in sa["members"] as Array:
		tiles_a.append(_tile_of(a, int(m)))
	for m in sb["members"] as Array:
		tiles_b.append(_tile_of(b, int(m)))
	if tiles_a != tiles_b:
		push_error("%s: seed %d put its settlers on %s and then on %s" % [lane, LANE_SEED, str(tiles_a), str(tiles_b)])
		return false
	# The negatives, through the same two predicates the positive used. A fabricated rect sitting
	# on a gate anchor must fail the distance test, and a fabricated outdoor tile the indoor one --
	# otherwise every assertion above is a scanner that says yes to anything.
	var map: Variant = a.tilemap
	var gate: Vector2i = SimTileMap.gate_a(map)
	var on_the_gate: Rect2i = Rect2i(gate.x, gate.y, 2, 2)
	if _camp_bad(a, on_the_gate, SimSettlers.min_metres_of(SimSettlers.pool(a))) == "":
		push_error("%s: a camp rect sitting on gate A at %s passed the distance test" % [lane, str(gate)])
		return false
	var outdoors: Vector2i = _an_outdoor_tile(map)
	if outdoors.x < 0:
		push_error("%s: the district has no outdoor floor tile, so the indoor test proves nothing" % lane)
		return false
	if _tile_bad(map, outdoors) == "":
		push_error("%s: the outdoor tile %s passed the indoor test" % [lane, str(outdoors)])
		return false
	# And the sleeper filter's own negative: it has to be able to *find* a building the manifest
	# names, or "the camp is never in one" is a sentence about an empty set. A district with no
	# dormant manifest at all would satisfy the assertion above for free, so the lane insists on a
	# fixture that has one and then shows `site` refusing every building in it.
	var with_sleepers: int = 0
	var judged_filter: int = 0
	for size2 in [GATE_TILES, SHIPPED_TILES]:
		for seed2 in FAST_SEEDS:
			var w2: Variant = SimBoot.playable(int(seed2), int(size2))["world"]
			var sleepers: Dictionary = _sleepers_in(w2.tilemap)
			if sleepers.is_empty():
				continue
			with_sleepers += 1
			var declared2: float = SimSettlers.min_metres_of(SimSettlers.pool(w2))
			var far2: Array[int] = SimWorldgen.far_buildings(w2.tilemap, declared2)
			# Every far building has a sleeper in it: `site` must now answer -1 whatever it rolls.
			var all_taken: bool = true
			for index2 in far2:
				if not sleepers.has(int(index2)):
					all_taken = false
					break
			if not all_taken:
				continue
			judged_filter += 1
			if SimSettlers.site(w2.tilemap, declared2, w2.rng.stream("settlersFilterProbe")) >= 0:
				push_error("%s: seed %d at %d has a sleeper in every far building and `site` chose one anyway" % [lane, int(seed2), int(size2)])
				return false
	if with_sleepers < 1:
		push_error("%s: not one of the %d seed/size pairs has a dormant manifest, so the sleeper filter judged nothing" % [lane, FAST_SEEDS.size() * 2])
		return false
	print("%s OK %d camp(s) judged over %d seed/size pairs (%d skipped); seed %d deterministic at building %d on %s; a rect on the gate and an outdoor tile both refused; %d pair(s) carry sleepers and %d of them are fully taken and refused" % [
		lane, judged, FAST_SEEDS.size() * 2, skipped, LANE_SEED, int(sa["building"]), str(tiles_a),
		with_sleepers, judged_filter,
	])
	return true


# The building indices the generator's `dormant` manifest names, read off the map the way
# `SimSettlers._buildings_with_a_sleeper` does but written out here, so the lane is judging the
# manifest rather than re-running the code that consults it.
func _sleepers_in(map: Variant) -> Dictionary:
	var out: Dictionary = {}
	var records: Variant = map.get("dormant")
	if not (records is Array):
		return out
	for rec in records as Array:
		if rec is Dictionary and (rec as Dictionary).has("building"):
			out[int((rec as Dictionary)["building"])] = true
	return out


# Why the camp's rect is wrong, or "". Distance from both gates and clear of the annex.
func _camp_bad(w: Variant, rect: Rect2i, declared: float) -> String:
	var map: Variant = w.tilemap
	var d: float = _metres_to_home(map, rect)
	if d < declared:
		return "sits %.1f m from the nearer gate, inside the declared %.1f m" % [d, declared]
	var annex: Rect2i = SimTileMap.annex_rect(map)
	if annex.size.x > 0 and annex.size.y > 0 and annex.intersects(rect):
		return "overlaps the colony's own annex %s" % str(annex)
	return ""


# Why the tile is no place to stand, or "".
func _tile_bad(map: Variant, tile: Vector2i) -> String:
	if not SimTileMap.is_indoors(map, tile.x, tile.y):
		return "is outdoors"
	if SimTileMap.tile_at(map, tile.x, tile.y) != SimTileMap.Tile.Floor:
		return "is not floor"
	if SimTileMap.is_solid(map, tile.x, tile.y):
		return "is solid"
	return ""


func _an_outdoor_tile(map: Variant) -> Vector2i:
	for j in int(map.h):
		for i in int(map.w):
			if SimTileMap.is_indoors(map, i, j):
				continue
			if SimTileMap.tile_at(map, i, j) != SimTileMap.Tile.Floor:
				continue
			return Vector2i(i, j)
	return Vector2i(-1, -1)


# --- BODIES ---------------------------------------------------------------------------------

# Every component a settler is supposed to carry, and the reason each is on the list rather than
# a hopeful "it looked like a survivor": each of these is read by something that will treat a
# settler as an ordinary body only if it is there.
const REQUIRED: Array[String] = [
	"position", "velocity", "facing", "posture", "identity", "allegiance",
	"body", "stamina", "container", "equipment", "encumbrance", "attention_emitter", "aptitudes",
	"observer", "sightings", "lootKit",
]
# And the two that must not be, which is the whole of how the camp stays off the colony's books.
const FORBIDDEN: Array[String] = ["needs", "jobPriorities"]


func _bodies() -> bool:
	var lane: String = "BODIES"
	var w: Variant = SimBoot.playable(LANE_SEED, LANE_TILES)["world"]
	var camp: int = _camp_of(w)
	if camp < 0:
		push_error("%s: seed %d at %d booted no camp, so this lane has nothing to judge -- pick another LANE_SEED" % [lane, LANE_SEED, LANE_TILES])
		return false
	var s: Dictionary = w.components.get_component(camp, "settlement") as Dictionary
	var members: Array = s["members"] as Array
	var wanted: int = SimSettlers.count_of(SimSettlers.pool(w))
	if members.size() != wanted:
		push_error("%s: the content declares %d settlers and the camp lists %d" % [lane, wanted, members.size()])
		return false
	var by_faction: Array[int] = SimSettlers.members_of(w)
	if by_faction.size() != wanted:
		push_error("%s: the camp lists %d members and %d bodies in the district read as `%s`" % [lane, members.size(), by_faction.size(), SimAllegiance.SETTLERS])
		return false
	for m in members:
		var ent: int = int(m)
		if not by_faction.has(ent):
			push_error("%s: the camp lists %d, which is not one of the district's settlers" % [lane, ent])
			return false
		for key in REQUIRED:
			if not w.components.has_component(ent, String(key)):
				push_error("%s: settler %d carries no `%s`" % [lane, ent, String(key)])
				return false
		for key in FORBIDDEN:
			if w.components.has_component(ent, String(key)):
				push_error("%s: settler %d carries `%s` -- that is what puts them on the colony's ledger and its job scheduler" % [lane, ent, String(key)])
				return false
		if SimAllegiance.is_colony(w, ent):
			push_error("%s: settler %d reads as one of the colony's own" % [lane, ent])
			return false
		var body: Variant = w.components.get_component(ent, "body")
		if not (body is Dictionary) or not SimHealth.is_alive(body as Dictionary):
			push_error("%s: settler %d booted dead" % [lane, ent])
			return false
	# The negative, in the same world: the scanner above has to be able to *find* those two
	# components, or "none of them carries needs" is a sentence about a spelling mistake. The
	# colony's own people carry both.
	var colonists: int = 0
	for e in w.components.query(["identity"]):
		var c: int = int(e)
		if not SimAllegiance.is_colony(w, c):
			continue
		colonists += 1
		for key in FORBIDDEN:
			if not w.components.has_component(c, String(key)):
				push_error("%s: colonist %d carries no `%s` either, so the settlers' lack of it proves nothing" % [lane, c, String(key)])
				return false
	if colonists < 1:
		push_error("%s: the booted district has no colonists at all, so the contrast above is empty" % lane)
		return false
	print("%s OK %d settlers, each with %d components and neither of %s; %d colonists carry both" % [
		lane, members.size(), REQUIRED.size(), str(FORBIDDEN), colonists,
	])
	return true


# --- LEDGER ---------------------------------------------------------------------------------

# `check_m2_balance.gd`'s `_survivors_alive`, reimplemented here rather than imported -- a gate may
# not preload another gate, and the textual half below is what keeps the two honest about being
# the same count.
func _survivors_alive(w: Variant) -> int:
	var n: int = 0
	for ent in w.components.query(["needs", "body"]):
		if w.components.has_component(int(ent), "corpse"):
			continue
		if w.components.has_component(int(ent), "recruit"):
			continue
		var body: Variant = w.components.get_component(int(ent), "body")
		if body is Dictionary and SimHealth.is_alive(body as Dictionary):
			n += 1
	return n


func _ledger() -> bool:
	var lane: String = "LEDGER"
	var w: Variant = SimBoot.playable(LANE_SEED, LANE_TILES)["world"]
	var camp: int = _camp_of(w)
	if camp < 0:
		push_error("%s: seed %d at %d booted no camp" % [lane, LANE_SEED, LANE_TILES])
		return false
	var settlers: Array[int] = SimSettlers.members_of(w)
	if settlers.is_empty():
		push_error("%s: no settlers to exclude" % lane)
		return false
	var colony: int = 0
	for e in w.components.query(["identity"]):
		if SimAllegiance.is_colony(w, int(e)):
			colony += 1
	# The player carries `needs` and a body and no `identity` component, so the colony's ledger is
	# the identities plus one.
	var expected: int = colony + 1
	var counted: int = _survivors_alive(w)
	if counted != expected:
		push_error("%s: the harness's count reads %d against a colony of %d + the player -- %d settler(s) are on the ledger" % [lane, counted, colony, counted - expected])
		return false
	# The negative: the counter has to be able to see a body it is supposed to exclude, or the
	# equality above is satisfied by a counter that counts nothing.
	w.components.set_component(int(settlers[0]), "needs", {"hunger": 50.0, "thirst": 50.0, "rest": 50.0})
	var raised: int = _survivors_alive(w)
	if raised != counted + 1:
		push_error("%s: giving a settler `needs` moved the count from %d to %d -- the ledger is not keyed on the component the sim withholds" % [lane, counted, raised])
		return false
	w.components.remove(int(settlers[0]), "needs")
	# And the textual half, because the two above would both still pass if the harness stopped
	# keying on `needs` tomorrow. The query line is isolated by name first and asked for `"needs"`
	# *inside it* -- never searched for as a bare word in that file, where a comment could satisfy
	# the needle (CLAUDE.md, the comfort gate's wrong needle).
	var src: String = FileAccess.get_file_as_string(BALANCE_SOURCE)
	if src.is_empty():
		push_error("%s: could not read %s" % [lane, BALANCE_SOURCE])
		return false
	var in_func: bool = false
	var query_line: String = ""
	for raw in src.split("\n"):
		var line: String = String(raw)
		if line.begins_with("func _survivors_alive"):
			in_func = true
			continue
		if in_func:
			if line.begins_with("func "):
				break
			if line.strip_edges().begins_with("for ") and line.contains("components.query("):
				query_line = line
				break
	if query_line.is_empty():
		push_error("%s: %s's `_survivors_alive` has no `components.query` loop -- the ledger moved and this lane is reading the wrong thing" % [lane, BALANCE_SOURCE])
		return false
	if not query_line.contains("\"needs\""):
		push_error("%s: the harness's colonist scan is `%s`, which no longer keys on `needs` -- a settler may now be on the ledger" % [lane, query_line.strip_edges()])
		return false
	print("%s OK %d on the ledger for a colony of %d + the player with %d settlers standing; one `needs` raises it to %d; the harness scan is `%s`" % [
		lane, counted, colony, settlers.size(), raised, query_line.strip_edges(),
	])
	return true


# --- NO-HEIR ---------------------------------------------------------------------------------

func _no_heir() -> bool:
	var lane: String = "NO-HEIR"
	var w: Variant = SimBoot.playable(LANE_SEED, LANE_TILES)["world"]
	var camp: int = _camp_of(w)
	if camp < 0:
		push_error("%s: seed %d at %d booted no camp" % [lane, LANE_SEED, LANE_TILES])
		return false
	var settlers: Array[int] = SimSettlers.members_of(w)
	if settlers.is_empty():
		push_error("%s: the camp booted no bodies reading as `%s`, so there is nothing for succession to refuse" % [lane, SimAllegiance.SETTLERS])
		return false
	var settler: int = int(settlers[0])
	# Mara is short-circuited to by id in `_succession_pick`, so she is sent away first: a lane
	# that let the short circuit answer would be measuring the short circuit, not the filter.
	for e in w.components.query(["identity"]):
		var ident: Variant = w.components.get_component(int(e), "identity")
		if ident is Dictionary and String((ident as Dictionary).get("id", "")) == "survivor.unique.mara":
			w.despawn(int(e))
	var pos: Variant = w.components.get_component(settler, "position")
	var sx: float = float((pos as Dictionary)["x"])
	var sy: float = float((pos as Dictionary)["y"])
	# The player dies half a metre from a settler, and every colonist is across the district.
	var dying: int = int(w.player)
	w.components.set_component(dying, "position", {"x": sx + 0.5, "y": sy})
	var heir: int = SimRecruits._succession_pick(w, dying)
	if heir == settler:
		push_error("%s: the player's body went to the settler standing 0.5 m away" % lane)
		return false
	if heir < 0:
		push_error("%s: nobody inherited at all, so the refusal above says nothing about allegiance" % lane)
		return false
	if not SimAllegiance.is_colony(w, heir):
		push_error("%s: the body went to %d, which is not one of the colony's own" % [lane, heir])
		return false
	var far: float = _distance(w, dying, heir)
	# The negative: the settler was a candidate in every other respect -- an identity, a living
	# body, nearer than the heir. One field kept them out, and putting it back puts them in.
	SimAllegiance.attach(w, settler, SimAllegiance.COLONY)
	if SimRecruits._succession_pick(w, dying) != settler:
		push_error("%s: the same body declared `%s` still did not inherit, so the refusal proves nothing" % [lane, SimAllegiance.COLONY])
		return false
	print("%s OK a colonist at %.1f m inherited over a settler at 0.5 m; the same body declared colony inherited" % [lane, far])
	return true


func _distance(w: Variant, a: int, b: int) -> float:
	var pa: Variant = w.components.get_component(a, "position")
	var pb: Variant = w.components.get_component(b, "position")
	if not (pa is Dictionary) or not (pb is Dictionary):
		return 1e12
	var dx: float = float((pb as Dictionary)["x"]) - float((pa as Dictionary)["x"])
	var dy: float = float((pb as Dictionary)["y"]) - float((pa as Dictionary)["y"])
	return sqrt(dx * dx + dy * dy)


# --- PROSE ---------------------------------------------------------------------------------

func _has_digit(s: String) -> bool:
	for i in s.length():
		if s[i] >= "0" and s[i] <= "9":
			return true
	return false


func _prose() -> bool:
	var lane: String = "PROSE"
	var w: Variant = SimBoot.playable(LANE_SEED, LANE_TILES)["world"]
	var camp: int = _camp_of(w)
	if camp < 0:
		push_error("%s: seed %d at %d booted no camp" % [lane, LANE_SEED, LANE_TILES])
		return false
	var lines: Array[String] = []
	for ent in SimSettlers.members_of(w):
		var clause: String = SimSurvivors.person_clause(w, ent)
		if clause.strip_edges().is_empty():
			push_error("%s: settler %d renders an empty clause -- a named person with nothing to say about them" % [lane, ent])
			return false
		if _has_digit(clause):
			push_error("%s: settler %d renders `%s`, which carries a digit -- the HUD ban" % [lane, ent, clause])
			return false
		lines.append(clause)
	if lines.is_empty():
		push_error("%s: no settlers to describe" % lane)
		return false
	# The negative: the scanner has to be able to see a digit, or every clause above passed a test
	# that cannot fail. The fabrication is an age printed rather than translated, which is exactly
	# the mistake the ban exists to catch.
	if not _has_digit(lines[0] + ", 41"):
		push_error("%s: the digit scanner accepted a clause with an age printed in it" % lane)
		return false
	print("%s OK %d clauses, digit-free; first reads `%s`" % [lane, lines.size(), lines[0]])
	return true


# --- SAVE ---------------------------------------------------------------------------------

func _save() -> bool:
	var lane: String = "SAVE"
	var w: Variant = SimBoot.playable(LANE_SEED, LANE_TILES)["world"]
	var camp: int = _camp_of(w)
	if camp < 0:
		push_error("%s: seed %d at %d booted no camp" % [lane, LANE_SEED, LANE_TILES])
		return false
	var before: Dictionary = (w.components.get_component(camp, "settlement") as Dictionary).duplicate(true)
	var text: String = SimSave.encode_save(SimSave.create_save(w))
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary) or not ((parsed as Dictionary)["snapshot"] is Dictionary):
		push_error("%s: the save did not come back as an object" % lane)
		return false
	var w2: Variant = SimBoot.bare(LANE_SEED, LANE_TILES)["world"]
	w2.restore((parsed as Dictionary)["snapshot"] as Dictionary)
	var after: Variant = w2.components.get_component(camp, "settlement")
	if not (after is Dictionary):
		push_error("%s: the settlement did not come back at all" % lane)
		return false
	var a: Dictionary = after as Dictionary
	for key in ["x", "y", "w", "h", "building"]:
		if int(a[key]) != int(before[key]):
			push_error("%s: the camp's `%s` came back %d, was %d" % [lane, String(key), int(a[key]), int(before[key])])
			return false
	if not (a.get("members") is Array):
		push_error("%s: `members` came back as %s -- it must be an Array of ids, because JSON has no integer keys and a Dictionary keyed by entity id comes back with String keys and misses silently" % [lane, type_string(typeof(a.get("members")))])
		return false
	var back: Array = a["members"] as Array
	if back.size() != (before["members"] as Array).size():
		push_error("%s: the camp listed %d members and came back with %d" % [lane, (before["members"] as Array).size(), back.size()])
		return false
	# Resolved back to bodies rather than compared as numbers. An Array of ids that survives the
	# round trip and points at nothing is the silent-empty-memory shape, and comparing two lists of
	# integers would not notice it.
	for i in back.size():
		var ent: int = int(back[i])
		if ent != int((before["members"] as Array)[i]):
			push_error("%s: member %d came back as %d, was %d" % [lane, i, ent, int((before["members"] as Array)[i])])
			return false
		if not w2.components.has_component(ent, "identity"):
			push_error("%s: member %d came back pointing at a body with no identity" % [lane, ent])
			return false
		if SimAllegiance.faction_of(w2, ent) != SimAllegiance.SETTLERS:
			push_error("%s: member %d came back reading as `%s`" % [lane, ent, SimAllegiance.faction_of(w2, ent)])
			return false
		if w2.components.has_component(ent, "needs"):
			push_error("%s: member %d came back carrying `needs`" % [lane, ent])
			return false
	# The negative: a district that never had a camp restores without one, so "the settlement came
	# back" is not a sentence about a component every restore invents.
	var empty_seed: int = _a_seed_with_no_camp()
	if empty_seed == 0:
		print("%s SKIP every %d-tile seed in the set sites a camp, so the empty restore has no fixture" % [lane, GATE_TILES])
	else:
		var e1: Variant = SimBoot.playable(empty_seed, GATE_TILES)["world"]
		var e_text: String = SimSave.encode_save(SimSave.create_save(e1))
		var e_parsed: Variant = JSON.parse_string(e_text)
		var e2: Variant = SimBoot.bare(empty_seed, GATE_TILES)["world"]
		e2.restore((e_parsed as Dictionary)["snapshot"] as Dictionary)
		if not e2.components.query(["settlement"]).is_empty():
			push_error("%s: seed %d has no camp and restored with %d" % [lane, empty_seed, e2.components.query(["settlement"]).size()])
			return false
	print("%s OK the camp at %s round-tripped with %d members, each still a settler with no needs%s" % [
		lane, str(Rect2i(int(a["x"]), int(a["y"]), int(a["w"]), int(a["h"]))), back.size(),
		"" if empty_seed == 0 else "; seed %d restored campless" % empty_seed,
	])
	return true


func _a_seed_with_no_camp() -> int:
	for seed_value in FAST_SEEDS:
		var w: Variant = SimBoot.playable(int(seed_value), GATE_TILES)["world"]
		if w.components.query(["settlement"]).is_empty():
			return int(seed_value)
	return 0
