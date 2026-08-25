extends SceneTree
# The generator, swept: is *every* seed a district somebody could be dropped into and survive?
#
# check_m2_district.gd asks the deep questions of a few maps -- the bands, the road seam, the
# enterability walk, the survivability pass's own true negatives. This asks a shallower question of
# many worlds, and asks it of a **booted, stepped** world rather than of a generated map: the
# generator is a per-seed function now, the colony moves with the seed, and the failure mode a
# single-seed gate cannot see is the seed that builds a district which generates fine and then
# boots wrong.
#
# What it holds down, per booted world:
#
#   1. **It boots at all.** Not by hooking the error stream -- gates here detect failures by
#      asserting the conditions a `push_error` would accompany, which is the stronger question
#      anyway. Every loud failure worldgen and boot have is covered by a clause below:
#      `district_of`'s "no district in content" by the emptiness check before the sweep;
#      `generate`'s "sited no survivable colony on any candidate lot" and "the dressing broke X"
#      by the survivability report on the finished, dressed map; `_connection_points`' "no room on
#      the wall" by `gates-reachable` being answered rather than skipped; and
#      `place_loot`'s "site names unknown table" by resolving every site's table through the same
#      `SimLoot.table_for` the boot uses.
#   2. **The colony is placed, with anchors somebody can stand on.** A non-empty annex rect, and
#      all four anchors in bounds and on open floor.
#   3. **The start is survivable.** Every clause of `survivability_report` true, and none of them
#      skipped: a shipped district declares roads and places loot, so a clause with nothing to
#      judge here would be a clause quietly not running on the district the game plays.
#   4. **Nobody wakes up in the kitchen.** Exactly `SimBoot.WANDERERS` shamblers, and zero of them
#      inside the annex rect (`SCATTER_TRIES`, made mechanical on twenty-two worlds instead of
#      four).
#   5. **There is something to find.** At least one loose item or standing container, and at least
#      BUILDINGS_MIN buildings to hold them.
#   6. **And it runs.** 200 ticks stepped, the tick counter advancing by exactly 200, the player
#      still on the map and the wanderers still alive at the end of it.
#
# `district.town_center` has never been booted anywhere before this gate -- it shipped as the
# second district type with the worldgen rebuild and only ever had `generate` called on it. Half
# this sweep is its first playable boot, which is the point: a district type nothing boots is a
# district type nobody knows boots.
#
# The sweep boots each world exactly once and every lane reads what that one boot measured; the
# witness and the negatives are handed the records, and the negatives are handed the canonical
# world itself rather than booting a twenty-third. Boots are the whole cost of this gate
# (measured: 67 ms to boot at 64 and 468 ms to step it, 702 and 683 at 256), so the budget lane
# at the bottom is what keeps a future lane from quietly doubling them.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimWorldgen = preload("res://sim/map/worldgen.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimLoot = preload("res://sim/loot.gd")
const SimAttentionField = preload("res://sim/field/attention.gd")
const ContentLoader = preload("res://platform/content_loader.gd")

const GATE_SIZE: int = 64
const SHIPPED_SIZE: int = 256
const RESIDENTIAL: String = "district.residential_suburb"
const TOWN_CENTER: String = "district.town_center"

# The four the balance harness runs come first and are not optional: a robustness claim that skips
# the campaigns the bands were measured against is a robustness claim about other campaigns. The
# six after them are the ones check_m2_district's siting lane walks, plus two more, so a seed that
# only this gate covers is still a seed some other gate has seen the map of.
const BALANCE_SEEDS: Array[int] = [20260805, 404, 31337, 90210]
const SWEEP_SEEDS: Array[int] = [20260805, 404, 31337, 90210, 1, 2, 7, 777, 4242, 12345]
# Two at the shipped size: the canonical one every measured band is pinned to, and one other, so
# "it works at 256" is not one seed asserted once. Generation at 256 runs the survivability
# validator twice and costs ~0.6 s before a world exists, which is why there are two of them and
# not ten.
const SHIPPED_SEEDS: Array[int] = [20260805, 404]

# Ten seconds of game time at 20 Hz. Long enough that every registered system has run many times
# over -- needs, the director's day beat, attention decay, the shambler wander -- and short enough
# that twenty-four of them fit in the budget. It is a "does it run" probe, not a campaign: the
# campaign questions belong to check_m2_balance.gd.
const STEP_TICKS: int = 200

# A floor, not a band. docs/24's 40-70 at 256 is check_m2_district's measurement to keep; what this
# sweep needs is the assertion that a seed did not come out empty, which is the old block-lattice
# bug and the shape a density-0 district has.
const BUILDINGS_MIN: int = 3

# The gate's own wall clock. Measured at ~16 s on this container; the budget is the headroom that
# turns "somebody added a lane that boots ten more worlds" into a red build rather than into a
# slower CI nobody notices. docs/00 pillar 6: budgets are correctness.
const BUDGET_SECONDS: float = 90.0

var _tree_cache: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var started: int = Time.get_ticks_msec()
	var ok: bool = true
	# Every lane's data, gathered by one pass of boots. An Array of records rather than a
	# Dictionary keyed by seed: two districts boot the same seed, and a record carries which.
	var sweep: Array = []
	# The canonical world and its map, kept alive out of the sweep so the negatives lane can
	# sabotage them instead of booting a twenty-third world.
	var stash: Dictionary = {}

	ok = _every_swept_seed_boots_a_district_a_survivor_can_live_in(sweep, stash) and ok
	ok = _the_same_seed_builds_the_same_district_and_two_seeds_do_not() and ok
	# An Array rather than an int, because a lane cannot hand a number back through an `and` chain
	# and this file is not going to grow a member variable for one count.
	var witnessed: Array = []
	ok = _the_attention_field_says_how_much_of_the_map_is_solid(sweep, witnessed) and ok
	ok = _every_expectation_the_sweep_makes_can_say_no(sweep, stash) and ok

	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	ok = _the_gate_stayed_inside_its_own_budget(seconds) and ok

	if ok:
		print("WORLDGEN_OK %d worlds booted and stepped %d ticks each (%d seeds x 2 districts at %d, %d seeds at %d), every colony sited and survivable, no wanderer indoors, loot resolved; one seed builds one district and two build two; %d solid-cell counts witnessed, the largest %d; four expectations shown to say no; %.1f s of a %.0f s budget" % [
			sweep.size(), STEP_TICKS, SWEEP_SEEDS.size(), GATE_SIZE,
			SHIPPED_SEEDS.size(), SHIPPED_SIZE,
			int(witnessed[0]) if not witnessed.is_empty() else 0,
			int(witnessed[1]) if witnessed.size() > 1 else -1,
			seconds, BUDGET_SECONDS,
		])
		quit(0)
	else:
		push_error("WORLDGEN_FAIL")
		quit(1)


func _tree() -> Dictionary:
	# One directory walk for the whole gate. `SimBoot.bare` walks it again per boot -- it takes no
	# tree -- but nothing this file does outside a boot needs to pay for it twice.
	if _tree_cache.is_empty():
		_tree_cache = ContentLoader.load_tree()
	return _tree_cache


# --- 1. the sweep ------------------------------------------------------------------------------

func _every_swept_seed_boots_a_district_a_survivor_can_live_in(sweep: Array, stash: Dictionary) -> bool:
	var tree: Dictionary = _tree()
	var plans: Array = [
		{"district": RESIDENTIAL, "size": GATE_SIZE, "seeds": SWEEP_SEEDS},
		# The town centre's first playable boot, here and nowhere else. It has shipped as a
		# district type since the worldgen rebuild and has only ever had `generate` called on it --
		# no world, no loot placed, no wanderer scattered, no tick stepped.
		{"district": TOWN_CENTER, "size": GATE_SIZE, "seeds": SWEEP_SEEDS},
		{"district": RESIDENTIAL, "size": SHIPPED_SIZE, "seeds": SHIPPED_SEEDS},
	]
	# The balance seeds are named in SWEEP_SEEDS rather than assumed to be there: a later edit that
	# trimmed the list to speed the gate up would otherwise silently stop covering the campaigns.
	for wanted in BALANCE_SEEDS:
		if not SWEEP_SEEDS.has(int(wanted)):
			push_error("balance seed %d is not in the sweep, so this gate no longer covers the campaigns the bands are measured on" % int(wanted))
			return false

	for plan_value in plans:
		var plan: Dictionary = plan_value as Dictionary
		var district_id: String = String(plan["district"])
		var size: int = int(plan["size"])
		# `SimWorldgen.district_of` is loud about a name nobody wrote and then returns {}, which
		# generates the *default* district under the requested name. Catching the empty here is
		# what stops a typo reading as "the town centre boots fine".
		if SimWorldgen.district_of(tree, district_id).is_empty():
			push_error("no district %s in content, so the sweep would be judging the default under another name" % district_id)
			return false
		for seed_value in plan["seeds"] as Array:
			var record: Dictionary = _boot_and_judge(int(seed_value), size, district_id, stash)
			if record.is_empty():
				return false
			sweep.append(record)

	if sweep.size() != SWEEP_SEEDS.size() * 2 + SHIPPED_SEEDS.size():
		push_error("the sweep judged %d worlds and the plan names %d" % [
			sweep.size(), SWEEP_SEEDS.size() * 2 + SHIPPED_SEEDS.size(),
		])
		return false

	# The seed reaches the siting on both district types, or twenty-two worlds are one world
	# asserted twenty-two times. Same discipline as check_m2_district's placement count, asked of
	# the booted map rather than the generated one.
	var sites_by_district: Dictionary = {}
	for record_value in sweep:
		var record: Dictionary = record_value as Dictionary
		if int(record["size"]) != GATE_SIZE:
			continue
		var key: String = String(record["district"])
		if not sites_by_district.has(key):
			sites_by_district[key] = {}
		(sites_by_district[key] as Dictionary)[String(record["annex"])] = true
	for key in [RESIDENTIAL, TOWN_CENTER]:
		var places: Dictionary = sites_by_district.get(String(key), {}) as Dictionary
		if places.size() < 2:
			push_error("all %d seeds sited %s at %s -- the seed is not reaching the siting pass" % [
				SWEEP_SEEDS.size(), String(key), str(places.keys()),
			])
			return false

	var lines: Array[String] = []
	for record_value2 in sweep:
		var r: Dictionary = record_value2 as Dictionary
		lines.append("%d/%d %s b=%d loot=%d+%d" % [
			int(r["seed"]), int(r["size"]), String(r["district"]).trim_prefix("district."),
			int(r["buildings"]), int(r["ground"]), int(r["boxes"]),
		])
	print("SWEEP OK %d worlds booted, judged and stepped %d ticks: %s" % [sweep.size(), STEP_TICKS, ", ".join(lines)])
	return true


# One world: boot it, judge it, step it, and hand back what the other lanes need. Returns {} after
# pushing the failure, so the caller stops on the first bad seed rather than reporting twenty-two
# consequences of one cause.
func _boot_and_judge(seed_value: int, size: int, district_id: String, stash: Dictionary) -> Dictionary:
	var where: String = "seed %d, %s at %d" % [seed_value, district_id, size]
	var boot: Dictionary = SimBoot.playable(seed_value, size, district_id)
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]

	if int(world.map_width) != size or int(world.map_height) != size:
		push_error("%s: booted a %dx%d world" % [where, int(world.map_width), int(world.map_height)])
		return {}

	# 2. The colony, and four anchors somebody can stand on.
	var annex: Rect2i = SimTileMap.annex_rect(map)
	if annex.size.x <= 0 or annex.size.y <= 0:
		push_error("%s: booted a district with no colony sited on it" % where)
		return {}
	var anchors: Dictionary = {
		"gate_a": SimTileMap.gate_a(map),
		"gate_b": SimTileMap.gate_b(map),
		"player_start": SimTileMap.player_start(map),
		"well": SimTileMap.well_tile(map),
	}
	for key in ["gate_a", "gate_b", "player_start", "well"]:
		var tile: Vector2i = anchors[String(key)] as Vector2i
		if tile.x < 1 or tile.y < 1 or tile.x >= size - 1 or tile.y >= size - 1:
			push_error("%s: anchor %s is at %s, which is off the map or on its wall" % [where, String(key), str(tile)])
			return {}
		if SimTileMap.tile_at(map, tile.x, tile.y) != SimTileMap.Tile.Floor or SimTileMap.is_solid(map, tile.x, tile.y):
			push_error("%s: anchor %s at %s is tile %d, which is not open floor" % [
				where, String(key), str(tile), SimTileMap.tile_at(map, tile.x, tile.y),
			])
			return {}
		if not annex.has_point(tile):
			push_error("%s: anchor %s at %s is outside the colony %s it belongs to" % [where, String(key), str(tile), str(annex)])
			return {}

	# 3. Survivability, clause by clause, on the finished dressed map -- which is also what covers
	#    `generate`'s two loud failures, since a district that failed either comes back with a
	#    report saying so.
	var report: Dictionary = SimWorldgen.survivability_report(map)
	if not bool(report["sited"]):
		push_error("%s: the survivability pass judged nothing on a district that carries a colony" % where)
		return {}
	if (report["clauses"] as Array).size() < 6:
		push_error("%s: the report carries %d clauses" % [where, (report["clauses"] as Array).size()])
		return {}
	for clause_value in report["clauses"] as Array:
		var clause: Dictionary = clause_value as Dictionary
		if not bool(clause["ok"]):
			push_error("%s failed %s: %s" % [where, String(clause["name"]), String(clause["said"])])
			return {}
		if bool(clause["skipped"]):
			push_error("%s skipped %s on a shipped district: %s" % [where, String(clause["name"]), String(clause["said"])])
			return {}

	# 1, the last of it: every site names a table the loot roller can resolve. `SimBoot.place_loot`
	# push_errors and skips a site whose table does not exist, which reads downstream as a stingy
	# seed rather than as the content bug it is.
	var unresolved: Array[String] = []
	for site_value in map.sites as Array:
		var table: String = String((site_value as Dictionary).get("table", ""))
		if not (SimLoot.table_for(world, table) is Dictionary):
			unresolved.append(table)
	if not unresolved.is_empty():
		push_error("%s: %d loot sites name tables nothing resolves: %s" % [where, unresolved.size(), str(unresolved)])
		return {}

	# 4. Twenty wanderers, none of them in the colony.
	var zeds: int = world.components.query(["shambler"]).size()
	if zeds != SimBoot.WANDERERS:
		push_error("%s: booted %d shamblers, and SimBoot.WANDERERS is %d" % [where, zeds, SimBoot.WANDERERS])
		return {}
	var inside: int = _wanderers_inside(world, annex)
	if not _exclusion_ok(inside):
		push_error("%s: %d of the %d boot wanderers stand inside the colony at %s" % [where, inside, zeds, str(annex)])
		return {}

	# 5. Something to find, and buildings to have found it in.
	var buildings: int = (map.buildings as Array).size()
	if not _buildings_ok(buildings):
		push_error("%s: placed %d buildings, and the floor is %d -- an empty district is the old block-lattice bug" % [
			where, buildings, BUILDINGS_MIN,
		])
		return {}
	var ground: int = 0
	for e in world.components.query(["itemBase", "position"]):
		if world.components.has_component(int(e), "stored"):
			continue
		ground += 1
	var boxes: int = world.components.query(["searchable", "position"]).size()
	if not _loot_ok(ground, boxes):
		push_error("%s: nothing loose on the ground and nothing standing to search, behind %d sites" % [
			where, (map.sites as Array).size(),
		])
		return {}

	# The regression witness's number, taken here because the field belongs to a world this lane is
	# about to drop. `world.field` is the attention field the kernel built off this map.
	var cells: int = int(world.field.cell_count())
	var solid: int = 0
	for c in cells:
		if bool(world.field.is_solid(c)):
			solid += 1

	# 6. And it runs. A GDScript runtime error inside a system is loud but not fatal in a headless
	#    run, so this asserts what such an error would take with it: the tick counter advancing by
	#    exactly the number of steps asked for, the player still on the map, and the wanderers not
	#    silently gone.
	var before: int = int(world.tick)
	for _i in STEP_TICKS:
		world.step()
	if int(world.tick) != before + STEP_TICKS:
		push_error("%s: %d steps moved the tick from %d to %d" % [where, STEP_TICKS, before, int(world.tick)])
		return {}
	if not world.components.has_component(world.player, "position"):
		push_error("%s: after %d ticks the player has no position" % [where, STEP_TICKS])
		return {}
	var after_zeds: int = world.components.query(["shambler"]).size()
	if after_zeds < 1:
		push_error("%s: after %d ticks not one of the %d wanderers is left" % [where, STEP_TICKS, zeds])
		return {}

	# The canonical residential world at the gate size is the one the negatives lane sabotages.
	if seed_value == BALANCE_SEEDS[0] and size == GATE_SIZE and district_id == RESIDENTIAL:
		stash["world"] = world
		stash["map"] = map
		stash["annex"] = annex

	return {
		"seed": seed_value, "size": size, "district": district_id,
		"annex": str(annex.position), "buildings": buildings,
		"ground": ground, "boxes": boxes, "sites": (map.sites as Array).size(),
		"zeds": zeds, "cells": cells, "solid": solid,
	}


func _wanderers_inside(world: Variant, annex: Rect2i) -> int:
	var n: int = 0
	for e in world.components.query(["shambler", "position"]):
		var p: Variant = world.components.get_component(int(e), "position")
		if not (p is Dictionary):
			continue
		if annex.has_point(Vector2i(floori(float((p as Dictionary)["x"])), floori(float((p as Dictionary)["y"])))):
			n += 1
	return n


# The three expectations the sweep applies, as named predicates rather than as inline comparisons,
# so the negatives lane below can hand each one the value it must refuse. An expectation that lives
# only inside an `if` in the loop is an expectation no true negative can reach.
func _exclusion_ok(inside: int) -> bool:
	return inside == 0


func _buildings_ok(count: int) -> bool:
	return count >= BUILDINGS_MIN


func _loot_ok(ground: int, boxes: int) -> bool:
	return ground + boxes >= 1


# --- 2. determinism ----------------------------------------------------------------------------

# One seed builds one district, and two seeds build two. Generation-only on purpose: this is a
# question about the pure function upstream of every boot, and asking it of a map costs 38 ms where
# asking it of a world costs 535.
#
# check_m2_district's determinism lane asks this of the tiles at the gate size; this asks it of
# `sites` and the anchors as well, and at both sizes -- the two fields the siting and loot slices
# added, which a byte comparison of the tilemap arrays does not reach.
func _the_same_seed_builds_the_same_district_and_two_seeds_do_not() -> bool:
	var lines: Array[String] = []
	for size in [GATE_SIZE, SHIPPED_SIZE]:
		var seed_value: int = BALANCE_SEEDS[0]
		var first: Variant = SimWorldgen.generate(seed_value, int(size), _tree())
		var second: Variant = SimWorldgen.generate(seed_value, int(size), _tree())
		for field in ["tiles", "surfaces", "indoors"]:
			var a: PackedByteArray = first.get(String(field)) as PackedByteArray
			var b: PackedByteArray = second.get(String(field)) as PackedByteArray
			var at: int = _first_difference(a, b)
			if at >= 0:
				push_error("two generations of seed %d at %d differ in %s at index %d (%d vs %d)" % [
					seed_value, int(size), String(field), at, int(a[at]), int(b[at]),
				])
				return false
		# `sites` is an Array of Dictionaries, so this is a deep comparison rather than a byte one:
		# a cupboard that moved between two generations of one seed is a save that reloads into a
		# different district (`check_m2_save.gd` restores into a fresh `SimBoot.bare`).
		if str(first.sites) != str(second.sites):
			push_error("two generations of seed %d at %d placed different loot: %d sites against %d" % [
				seed_value, int(size), (first.sites as Array).size(), (second.sites as Array).size(),
			])
			return false
		if (first.sites as Array).is_empty():
			push_error("seed %d at %d placed no loot sites at all, so comparing them compares nothing" % [seed_value, int(size)])
			return false
		if str(first.anchors) != str(second.anchors):
			push_error("two generations of seed %d at %d put the colony at %s and %s" % [
				seed_value, int(size), str(first.anchors), str(second.anchors),
			])
			return false
		lines.append("%d at %d: %d sites, colony %s" % [
			seed_value, int(size), (first.sites as Array).size(), str(SimTileMap.annex_rect(first).position),
		])

	# The true negative, and the whole reason the comparison above can fail: a different seed has to
	# come out different. Without it, an equality that had stopped comparing would read as a pass.
	var other: Variant = SimWorldgen.generate(BALANCE_SEEDS[1], GATE_SIZE, _tree())
	var canon: Variant = SimWorldgen.generate(BALANCE_SEEDS[0], GATE_SIZE, _tree())
	if _first_difference(canon.tiles as PackedByteArray, other.tiles as PackedByteArray) < 0:
		push_error("seeds %d and %d built byte-identical tiles at %d -- the seed is not reaching the generator" % [
			BALANCE_SEEDS[0], BALANCE_SEEDS[1], GATE_SIZE,
		])
		return false

	print("DETERMINISM OK %s; seed %d differs from seed %d at %d" % [
		", ".join(lines), BALANCE_SEEDS[0], BALANCE_SEEDS[1], GATE_SIZE,
	])
	return true


func _first_difference(a: PackedByteArray, b: PackedByteArray) -> int:
	if a.size() != b.size():
		return 0
	for i in a.size():
		if a[i] != b[i]:
			return i
	return -1


# --- 3. the regression witness -----------------------------------------------------------------

# Not an assertion about a number: a **record** of one, printed per seed, because the wall
# attenuation slice is going to change how much of the attention field is solid and will want to
# know what it changed from. A band here would be a band invented before the thing it measures --
# and inventing one is how this lane was first written, which is worth writing down, because the
# number it would have pinned is zero.
#
# **The baseline, measured: no cell of a generated district is solid at either size.**
# `SimAttentionField.for_map` marks a 4 m cell solid only when *every* tile inside it is solid, and
# a district's walls are one tile thick -- a house wall, the district border, a shell's perimeter,
# all of them have open floor on one side. So `wallPenaltyMetres` (18 m, the whole of the field's
# wall attenuation) currently applies to nothing at all: noise and scent propagate across the
# district as though the buildings were not there. That is the fact the wall-attenuation slice
# starts from, and it is the reason this prints rather than asserts.
#
# What it does assert is that the counter is counting, on two probe fields built for the purpose:
# a map that is solid everywhere has to come back all solid, and one that is open everywhere has to
# come back none. Without that pair, "0 of 256" is indistinguishable from a counter that has
# stopped counting, and this lane would witness a constant forever.
func _the_attention_field_says_how_much_of_the_map_is_solid(sweep: Array, out: Array) -> bool:
	var witnessed: int = 0
	var most: int = 0
	for record_value in sweep:
		var r: Dictionary = record_value as Dictionary
		# The default district only: the format is (seed, size, solid, total) and a town-centre line
		# under the same shape would be a second number wearing the first one's name.
		if String(r["district"]) != RESIDENTIAL:
			continue
		if int(r["size"]) == SHIPPED_SIZE and int(r["seed"]) != BALANCE_SEEDS[0]:
			continue
		var cells: int = int(r["cells"])
		if cells <= 0:
			push_error("seed %d at %d has an attention field of %d cells, so there is nothing to witness" % [
				int(r["seed"]), int(r["size"]), cells,
			])
			return false
		print("WORLDGEN CELLS seed=%d size=%d solid=%d/%d" % [int(r["seed"]), int(r["size"]), int(r["solid"]), cells])
		most = maxi(most, int(r["solid"]))
		witnessed += 1

	if witnessed == 0:
		# Nothing to judge, said out loud rather than passed quietly.
		push_error("WITNESS SKIPPED the sweep produced no %s record to count cells from" % RESIDENTIAL)
		return false

	# The true positive and the true negative for the count itself.
	var walled: int = _solid_cells(SimAttentionField.for_map(SimTileMap.blank_map(GATE_SIZE, GATE_SIZE, SimTileMap.Tile.Wall)))
	var open: int = _solid_cells(SimAttentionField.for_map(SimTileMap.blank_map(GATE_SIZE, GATE_SIZE)))
	var total: int = int(SimAttentionField.for_map(SimTileMap.blank_map(GATE_SIZE, GATE_SIZE)).cell_count())
	if walled != total:
		push_error("a %d-tile map of solid rock reports %d of %d cells solid -- the count is not reading the map" % [
			GATE_SIZE, walled, total,
		])
		return false
	if open != 0:
		push_error("a %d-tile map of open floor reports %d cells solid" % [GATE_SIZE, open])
		return false

	# The count, then the largest solid reading any witnessed district gave -- so the OK line states
	# the baseline it measured rather than restating the zero this lane happened to find first.
	out.append(witnessed)
	out.append(most)
	print("WITNESS OK %d solid-cell counts recorded as the wall-attenuation baseline; the count reads %d/%d on solid rock and 0 on open ground, so a district's zero is a measurement and not a broken counter" % [
		witnessed, walled, total,
	])
	return true


func _solid_cells(field: Variant) -> int:
	var n: int = 0
	for c in int(field.cell_count()):
		if bool(field.is_solid(c)):
			n += 1
	return n


# --- 4. the true negatives ---------------------------------------------------------------------

# Every expectation the sweep applies, shown refusing something. A sweep of twenty-two worlds that
# cannot fail is twenty-two times worse than no gate, because it takes twenty-two times as long to
# not find out.
func _every_expectation_the_sweep_makes_can_say_no(sweep: Array, stash: Dictionary) -> bool:
	if sweep.is_empty() or not stash.has("world"):
		push_error("the sweep left no canonical world to sabotage, so these negatives would prove nothing")
		return false

	# a. The building floor. A district whose density is 0 places nothing -- and the expectation has
	#    to reject that count, or "every seed built at least three buildings" is a sentence about a
	#    comparison that had stopped comparing.
	var empty: Dictionary = _fixture_district("district.fixture.worldgen_empty", 0.0)
	var barren: Variant = SimWorldgen.generate(BALANCE_SEEDS[0], GATE_SIZE, _tree_with(empty), String(empty["id"]))
	var none: int = (barren.buildings as Array).size()
	if none != 0:
		push_error("a district declaring density 0 still placed %d buildings" % none)
		return false
	if _buildings_ok(none):
		push_error("the sweep's building floor accepts %d buildings, which is what it exists to reject" % none)
		return false
	# And the same fixture at a density that does build proves the zero came from the density rather
	# than from a fixture the generator refuses outright.
	var built: Variant = SimWorldgen.generate(BALANCE_SEEDS[0], GATE_SIZE, _tree_with(_fixture_district("district.fixture.worldgen_dense", 0.9)), "district.fixture.worldgen_dense")
	if not _buildings_ok((built.buildings as Array).size()):
		push_error("the same fixture at density 0.9 placed %d buildings, so the density-0 result says nothing about density" % (built.buildings as Array).size())
		return false

	# b. The colony exclusion. One shambler put inside the annex by hand has to move the count by
	#    exactly one and turn the expectation false. `before` is re-measured rather than assumed to
	#    be zero: this world has run 200 ticks since the sweep judged it, and a wanderer that walked
	#    in on its own is a legal thing for it to have done. What is being tested is the counter and
	#    the expectation, not the scatter -- the scatter is the sweep's own lane, twenty-two times.
	var world: Variant = stash["world"]
	var annex: Rect2i = stash["annex"] as Rect2i
	var before: int = _wanderers_inside(world, annex)
	var planted: int = int(world.entities.spawn())
	world.components.set_component(planted, "shambler", {})
	world.components.set_component(planted, "position", {
		"x": float(annex.position.x + annex.size.x / 2) + 0.5,
		"y": float(annex.position.y + annex.size.y / 2) + 0.5,
	})
	var after: int = _wanderers_inside(world, annex)
	if after != before + 1:
		push_error("a shambler was stood in the middle of the colony at %s and the count went from %d to %d" % [
			str(annex), before, after,
		])
		return false
	if _exclusion_ok(after):
		push_error("the exclusion expectation accepts %d wanderers inside the colony" % after)
		return false

	# c. The survivability probe. A gate tile bricked over after generation, and the validator run
	#    again on the same map: the named clause has to go false, and the clauses the brick did not
	#    touch have to stay true, or the report is one verdict wearing six names.
	var map: Variant = stash["map"]
	if not bool(SimWorldgen.survivability_report(map)["ok"]):
		push_error("the canonical map is already failing survivability, so bricking its gate proves nothing")
		return false
	var gate: Vector2i = SimTileMap.gate_a(map)
	map.tiles[gate.y * int(map.w) + gate.x] = SimTileMap.Tile.Wall
	var sabotaged: Dictionary = SimWorldgen.survivability_report(map)
	if bool(sabotaged["ok"]):
		push_error("the colony's gate at %s was bricked over and the validator reported no problem" % str(gate))
		return false
	if bool(SimWorldgen.clause_of(sabotaged, "gates-open")["ok"]):
		push_error("a bricked gate tile left gates-open true: %s" % str(sabotaged["failed"]))
		return false
	if not (sabotaged["failed"] as Array).has("gates-open"):
		push_error("bricking the gate was reported as %s rather than as gates-open" % str(sabotaged["failed"]))
		return false
	for untouched in ["player-start", "stations-room", "well-open"]:
		if not bool(SimWorldgen.clause_of(sabotaged, String(untouched))["ok"]):
			push_error("bricking the gate also turned %s false, so the report is not per clause" % String(untouched))
			return false

	# d. The loot expectation, which the three above do not reach: a world that found nothing at all
	#    has to be refused. Cheap, and the only one of the four that is a predicate probe rather than
	#    a sabotage -- there is no way to unfind loot on a booted world without deleting the entities
	#    the expectation counts, which would be testing the deletion.
	if _loot_ok(0, 0):
		push_error("the loot expectation accepts a district with nothing loose and nothing to search")
		return false
	if not _loot_ok(0, 1) or not _loot_ok(1, 0):
		push_error("the loot expectation refuses a district that found something, so it is not the expectation the sweep applied")
		return false

	print("NEGATIVES OK a density-0 district places %d buildings and the floor rejects it (the same fixture at 0.9 places %d), a planted shambler moves the colony count %d->%d and the exclusion rejects it, a bricked gate at %s fails gates-open alone, and an empty district is refused loot" % [
		none, (built.buildings as Array).size(), before, after, str(gate),
	])
	return true


# A district type built here rather than shipped, so a negative can change one field and watch the
# world change. It declares no lootProfile: what is under test is the density, and a profile would
# put the generator's site pass in the way of that.
func _fixture_district(id: String, density: float) -> Dictionary:
	return {
		"id": id,
		"name": "fixture",
		"type": "fixture",
		"streets": {"blockMin": 24, "blockMax": 40, "streetWidth": 6},
		"connectionPoints": {"north": 1, "south": 1, "east": 1, "west": 1},
		"density": density,
		"pool": [{"tag": "residential", "weight": 10}, {"tag": "shed", "weight": 4}],
	}


func _tree_with(district: Dictionary) -> Dictionary:
	var tree: Dictionary = _tree().duplicate()
	tree["districts/zz_worldgen_fixture.json"] = district
	return tree


# --- 5. the budget -----------------------------------------------------------------------------

# docs/00 pillar 6, applied to the gate itself. Boots are this file's entire cost and a lane that
# adds ten more is a lane that adds five seconds; the budget is what makes that a red build rather
# than a CI that got slower and nobody said.
func _the_gate_stayed_inside_its_own_budget(seconds: float) -> bool:
	if seconds > BUDGET_SECONDS:
		push_error("the worldgen sweep took %.1f s against a %.0f s budget -- share boots between lanes rather than cutting seeds" % [
			seconds, BUDGET_SECONDS,
		])
		return false
	if seconds <= 0.0:
		push_error("the gate measured %.1f s of its own wall time, so the budget is measuring nothing" % seconds)
		return false
	print("BUDGET OK %.1f s of a %.0f s budget" % [seconds, BUDGET_SECONDS])
	return true
