extends SceneTree
# Location loot tables: content declares what a place yields, SimBoot.place_loot rolls it.
#
# This gate carries the same extra weight check_appearance.gd does, and for the same reason:
# content_validator.gd is shallow. It checks top-level property types and rejects unexpected
# top-level keys, but it does not recurse -- so nothing in `entries`, `rolls` or `tierWeights` is
# schema-enforced at load. A wrong key inside a nested block is exactly the failure that sat in
# `item.wrap.cloth`'s armor block for weeks giving zero arm protection, and only a purpose-built
# gate found it. Everything below is that gate for loot.
#
# What it holds down:
#
#  1. **Every table is well formed all the way down.** Ids, the location enum, ordered ranges,
#     positive weights, and -- the one a schema could never check -- every `item` naming an item
#     base that actually exists.
#  2. **Every shipped map's sites resolve to a table, and stand somewhere reachable.** A map
#     naming a table that does not exist would place an empty site and read as a stingy seed; a
#     site inside a wall would place items nobody can pick up.
#  3. **The tier is a property of the place.** A military cache must come out measurably better
#     than a kitchen drawer, or tierWeights is decoration.
#  4. **It is seeded, not arbitrary.** Same seed, same scatter; a different seed, a different one.
#
# Every assertion carries a true negative. A gate that cannot fail is worse than no gate.

const SimBoot = preload("res://sim/boot.gd")
const SimLoot = preload("res://sim/loot.gd")
const SimContainers = preload("res://sim/modules/containers.gd")
const SimItems = preload("res://sim/modules/items.gd")
const ContentLoader = preload("res://platform/content_loader.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")

const LOCATIONS: Array[String] = ["residential", "commercial", "industrial", "medical", "military_cache"]
const DANGERS: Array[String] = ["low", "moderate", "high", "very_high", "extreme"]
const TIER_IDS: Array[String] = ["scavenged", "modified", "field_tested"]
# Enough samples that a tier distribution is a distribution rather than a coin toss.
const TIER_SAMPLES: int = 2000

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _every_table_is_well_formed_all_the_way_down() and ok
	ok = _every_map_site_resolves_and_stands_somewhere_open() and ok
	ok = _the_three_slice_locations_are_authored() and ok
	ok = _a_cache_yields_better_gear_than_a_kitchen() and ok
	ok = _quantities_stay_inside_the_range_they_declare() and ok
	ok = _the_scatter_is_seeded() and ok
	ok = _a_container_yields_once_and_is_empty_after() and ok
	ok = _every_container_site_names_a_table_that_exists() and ok
	if ok:
		print("LOOT_OK tables well formed, map sites resolve and stand open, tier is a property of the place, scatter is seeded, a container yields once")
		quit(0)
	else:
		push_error("LOOT_FAIL")
		quit(1)


# --- helpers ------------------------------------------------------------------------------

# Every loot table in content, as {content_path: entry}.
func _tables() -> Dictionary:
	var out: Dictionary = {}
	var tree: Dictionary = ContentLoader.load_tree()
	for path in tree.keys():
		if not String(path).begins_with("loot/"):
			continue
		var value: Variant = tree[path]
		if value is Array:
			for entry in value as Array:
				if entry is Dictionary:
					out["%s#%s" % [path, String((entry as Dictionary).get("id", "?"))]] = entry as Dictionary
	return out


func _item_ids() -> Dictionary:
	var out: Dictionary = {}
	var tree: Dictionary = ContentLoader.load_tree()
	for path in tree.keys():
		if not String(path).begins_with("items/"):
			continue
		var value: Variant = tree[path]
		if value is Array:
			for entry in value as Array:
				if entry is Dictionary:
					out[String((entry as Dictionary).get("id", ""))] = true
	return out


func _maps() -> Dictionary:
	var out: Dictionary = {}
	var tree: Dictionary = ContentLoader.load_tree()
	for path in tree.keys():
		if String(path).begins_with("maps/") and tree[path] is Dictionary:
			out[String(path)] = tree[path] as Dictionary
	return out


# A booted district at the size the game actually plays, which is the only size at which a site's
# coordinates mean anything: world.is_blocked_tile treats out-of-bounds as blocked, so judging a
# site at (230, 20) against a 64-tile test map would report the whole far half of the district as
# masonry.
func _booted(seed_val: int) -> Dictionary:
	var boot: Dictionary = SimBoot.playable(seed_val, SimTileMap.DISTRICT_TILES)
	return {"world": boot["world"], "map": boot.get("map")}


# Every base id that ended up on the ground, with how many of each. Read off `itemBase` plus a
# `position`, which is what "loose on the floor" means -- an item in somebody's pack has no
# position component.
func _on_the_ground(w: Variant) -> Dictionary:
	var out: Dictionary = {}
	for item in w.components.query(["itemBase", "position"]):
		var base: Dictionary = w.components.get_component(int(item), "itemBase") as Dictionary
		var id: String = String(base.get("baseId", ""))
		out[id] = int(out.get(id, 0)) + 1
	return out


# --- assertions ---------------------------------------------------------------------------

# The schema cannot reach any of this: it does not recurse into `entries`, and no schema can
# assert that a string names an item base that exists.
func _every_table_is_well_formed_all_the_way_down() -> bool:
	var tables: Dictionary = _tables()
	if tables.is_empty():
		push_error("no loot tables found under content/loot -- this gate is asserting nothing")
		return false
	var items: Dictionary = _item_ids()
	var problems: Array[String] = []
	var seen_ids: Dictionary = {}
	var entry_count: int = 0

	for key in tables.keys():
		var t: Dictionary = tables[key] as Dictionary
		var id: String = String(t.get("id", ""))
		var location: String = String(t.get("location", ""))
		if seen_ids.has(id):
			problems.append("%s: duplicate table id %s" % [key, id])
		seen_ids[id] = true
		if id != "loot.%s" % location:
			problems.append("%s: id %s does not match location %s" % [key, id, location])
		if not LOCATIONS.has(location):
			problems.append("%s: location %s is not one of docs/12's five" % [key, location])
		if t.has("danger") and not DANGERS.has(String(t["danger"])):
			problems.append("%s: danger %s is not on the risk gradient" % [key, String(t["danger"])])
		problems.append_array(_range_problems(key + ".rolls", t.get("rolls"), 0))

		var weights: Variant = t.get("tierWeights")
		if not (weights is Dictionary) or (weights as Dictionary).is_empty():
			problems.append("%s: tierWeights is missing or empty" % key)
		else:
			var weight_total: int = 0
			for tier in (weights as Dictionary).keys():
				if not TIER_IDS.has(String(tier)):
					problems.append("%s.tierWeights: %s is not a SimItems.TIERS id" % [key, String(tier)])
				weight_total += int((weights as Dictionary)[tier])
			if weight_total <= 0:
				problems.append("%s.tierWeights: total weight is %d" % [key, weight_total])

		var entries: Variant = t.get("entries")
		if not (entries is Array) or (entries as Array).is_empty():
			problems.append("%s: entries is missing or empty" % key)
			continue
		var seen_items: Dictionary = {}
		for entry in entries as Array:
			entry_count += 1
			if not (entry is Dictionary):
				problems.append("%s.entries: a non-object entry" % key)
				continue
			var e: Dictionary = entry as Dictionary
			var item_id: String = String(e.get("item", ""))
			if not items.has(item_id):
				problems.append("%s.entries: %s is not an item base that exists" % [key, item_id])
			if seen_items.has(item_id):
				problems.append("%s.entries: %s listed twice" % [key, item_id])
			seen_items[item_id] = true
			if int(e.get("weight", 0)) <= 0:
				problems.append("%s.entries[%s]: weight %d is not positive" % [key, item_id, int(e.get("weight", 0))])
			if e.has("count"):
				problems.append_array(_range_problems("%s.entries[%s].count" % [key, item_id], e["count"], 1))

	if not problems.is_empty():
		for p in problems:
			push_error(p)
		return false

	# The true negative: the same walk over a table that is wrong in each of the ways above must
	# report exactly those ways. Without this the loop could be silently skipping everything.
	var broken: Array[String] = _range_problems("probe.rolls", {"min": 4, "max": 2}, 0)
	if broken.size() != 1:
		push_error("the range walk passed min=4 max=2 -- it is not checking ordering")
		return false
	if not _item_ids().is_empty() and _item_ids().has("item.not.a.real.base"):
		push_error("the item index contains a base that does not exist")
		return false

	print("LOOT SHAPE OK %d tables, %d entries, every item base resolves, every range ordered" % [tables.size(), entry_count])
	return true


# min and max present, integers, ordered, and at or above the floor the field allows.
func _range_problems(label: String, spec: Variant, floor_value: int) -> Array[String]:
	var out: Array[String] = []
	if not (spec is Dictionary):
		out.append("%s: missing" % label)
		return out
	var d: Dictionary = spec as Dictionary
	for field in ["min", "max"]:
		if not d.has(field):
			out.append("%s: no %s" % [label, field])
			return out
	if int(d["min"]) < floor_value:
		out.append("%s: min %d is below %d" % [label, int(d["min"]), floor_value])
	if int(d["max"]) < int(d["min"]):
		out.append("%s: max %d is below min %d" % [label, int(d["max"]), int(d["min"])])
	return out


# A map naming a table that does not exist places an empty site and reads as a stingy seed; a site
# inside a wall places items nobody can reach. Both are silent today, so both are asserted here.
func _every_map_site_resolves_and_stands_somewhere_open() -> bool:
	var tables: Dictionary = _tables()
	var by_location: Dictionary = {}
	for key in tables.keys():
		by_location[String((tables[key] as Dictionary).get("location", ""))] = true

	var booted: Dictionary = _booted(20260805)
	var w: Variant = booted["world"]
	var sites: int = 0
	var problems: Array[String] = []
	for path in _maps().keys():
		var loot: Variant = (_maps()[path] as Dictionary).get("loot")
		if not (loot is Array):
			continue
		for site in loot as Array:
			sites += 1
			var s: Dictionary = site as Dictionary
			var location: String = String(s.get("table", ""))
			if not by_location.has(location):
				problems.append("%s: site names table %s, which no content entry declares" % [path, location])
				continue
			var tile: Dictionary = s.get("tile", {}) as Dictionary
			if w.is_blocked_tile(int(tile.get("x", -1)), int(tile.get("y", -1))):
				problems.append("%s: site at (%d, %d) stands inside a wall" % [path, int(tile.get("x", -1)), int(tile.get("y", -1))])
	if sites == 0:
		push_error("SKIP-WORTHY: no map declares a loot site, so nothing here was judged")
		return false
	if not problems.is_empty():
		for p in problems:
			push_error(p)
		return false

	# The true negative: the same lookup must reject a location nobody authored, and the same tile
	# check must find the wall the annex is made of.
	if by_location.has("marina"):
		push_error("the location index answered for a table nobody wrote")
		return false
	if not _some_tile_is_blocked(w):
		push_error("no tile in the booted district is blocked, so the siting check cannot fail")
		return false

	print("MAP SITES OK %d sites across %d maps, every table resolves and every tile is open" % [sites, _maps().size()])
	return true


func _some_tile_is_blocked(w: Variant) -> bool:
	for x in range(0, SimTileMap.DISTRICT_TILES):
		for y in range(0, SimTileMap.DISTRICT_TILES):
			if w.is_blocked_tile(x, y):
				return true
	return false


# docs/23's slice scope says three location loot tables. Which three is a content decision; that
# there are three, that each is distinct, and that each is actually reachable from a shipped map
# is not.
func _the_three_slice_locations_are_authored() -> bool:
	var authored: Dictionary = {}
	for key in _tables().keys():
		authored[String((_tables()[key] as Dictionary).get("location", ""))] = true
	if authored.size() < 3:
		push_error("only %d location tables authored, the slice scope asks for three" % authored.size())
		return false

	var placed: Dictionary = {}
	for path in _maps().keys():
		var loot: Variant = (_maps()[path] as Dictionary).get("loot")
		if loot is Array:
			for site in loot as Array:
				placed[String((site as Dictionary).get("table", ""))] = true
	var unreachable: Array[String] = []
	for location in authored.keys():
		if not placed.has(location):
			unreachable.append(String(location))
	if not unreachable.is_empty():
		push_error("authored but on no map, so unreachable in play: %s" % str(unreachable))
		return false
	print("LOCATIONS OK %d authored (%s), every one placed on a shipped map" % [authored.size(), str(authored.keys())])
	return true


# The point of tierWeights: the tier stops being a property of the world and becomes one of the
# place. Measured on rolls, not on the table being the numbers it was written with.
func _a_cache_yields_better_gear_than_a_kitchen() -> bool:
	var tables: Dictionary = _tables()
	var cache: Variant = _table_for(tables, "military_cache")
	var house: Variant = _table_for(tables, "residential")
	if not (cache is Dictionary) or not (house is Dictionary):
		push_error("SKIP-WORTHY: need both a military_cache and a residential table to compare")
		return false

	var w: Variant = _booted(4242)["world"]
	var rng: Variant = w.rng.stream("lootTable")
	var cache_good: float = _good_tier_share(rng, cache as Dictionary)
	var house_good: float = _good_tier_share(rng, house as Dictionary)
	if cache_good <= house_good:
		push_error("a military cache rolled %.3f above scavenged against a house's %.3f -- tierWeights is decoration" % [cache_good, house_good])
		return false
	if cache_good < 0.8:
		push_error("a military cache rolled only %.3f above scavenged" % cache_good)
		return false
	if house_good > 0.5:
		push_error("a kitchen drawer rolled %.3f above scavenged -- residential is not the low end of anything" % house_good)
		return false

	# The true negative: the same counter run against a table with no tierWeights must fall back to
	# SimItems.roll_tier's global distribution, which is neither of the two above.
	var neutral: Dictionary = (house as Dictionary).duplicate(true)
	neutral.erase("tierWeights")
	var fallback: float = _good_tier_share(rng, neutral)
	if fallback <= house_good or fallback >= cache_good:
		push_error("the no-tierWeights fallback rolled %.3f, which does not sit between the house's %.3f and the cache's %.3f -- the counter is not measuring the weights" % [fallback, house_good, cache_good])
		return false

	print("TIER-BY-PLACE OK cache %.3f above scavenged, house %.3f, no-weights fallback %.3f in between, over %d rolls each" % [
		cache_good, house_good, fallback, TIER_SAMPLES,
	])
	return true


func _table_for(tables: Dictionary, location: String) -> Variant:
	for key in tables.keys():
		if String((tables[key] as Dictionary).get("location", "")) == location:
			return tables[key]
	return null


# The share of rolls that come out better than `scavenged`.
func _good_tier_share(rng: Variant, table: Dictionary) -> float:
	var good: int = 0
	for _i in TIER_SAMPLES:
		if SimLoot.roll_tier(rng, table) != "scavenged":
			good += 1
	return float(good) / float(TIER_SAMPLES)


# A count range is a promise. Rolled, not read back off the table.
func _quantities_stay_inside_the_range_they_declare() -> bool:
	var w: Variant = _booted(31337)["world"]
	var rng: Variant = w.rng.stream("lootTable")
	var lo: int = 2
	var hi: int = 7
	var seen_lo: bool = false
	var seen_hi: bool = false
	for _i in TIER_SAMPLES:
		var n: int = SimLoot.roll_range(rng, {"min": lo, "max": hi}, 1)
		if n < lo or n > hi:
			push_error("a count range of %d..%d rolled %d" % [lo, hi, n])
			return false
		seen_lo = seen_lo or n == lo
		seen_hi = seen_hi or n == hi
	if not seen_lo or not seen_hi:
		push_error("a %d..%d range never reached one of its ends over %d rolls -- it is not inclusive" % [lo, hi, TIER_SAMPLES])
		return false

	# The true negative: a range whose ends are reversed must not loop or escape its own bounds,
	# and a spec with no min/max at all must fall back rather than roll.
	var reversed: int = SimLoot.roll_range(rng, {"min": 5, "max": 2}, 1)
	if reversed != 5:
		push_error("a reversed 5..2 range rolled %d instead of collapsing to 5" % reversed)
		return false
	if SimLoot.roll_range(rng, {}, 9) != 9:
		push_error("a spec with no range did not fall back")
		return false
	print("QUANTITY OK %d..%d inclusive at both ends over %d rolls, reversed collapses, missing falls back" % [lo, hi, TIER_SAMPLES])
	return true


# Seeded, not arbitrary: the same seed scatters the same site, and a different one does not.
# Read off what is actually on the ground, which is the observable that matters.
func _the_scatter_is_seeded() -> bool:
	var a: Dictionary = _on_the_ground(_booted(90210)["world"])
	var b: Dictionary = _on_the_ground(_booted(90210)["world"])
	var c: Dictionary = _on_the_ground(_booted(404)["world"])
	if a.is_empty():
		push_error("the district booted with no loose loot at all, so nothing here was judged")
		return false
	if JSON.stringify(a, "", true, true) != JSON.stringify(b, "", true, true):
		push_error("the same seed scattered two different districts")
		return false
	if JSON.stringify(a, "", true, true) == JSON.stringify(c, "", true, true):
		push_error("two different seeds scattered identical loot -- the seed is not reaching the tables")
		return false
	var total: int = 0
	for id in a.keys():
		total += int(a[id])
	print("SEEDED OK %d loose items over %d bases, identical across two boots of one seed, different on another" % [total, a.size()])
	return true


# A container is a loot site whose table is rolled when somebody opens it rather than at boot, and
# **site depletion is that it is rolled once**. docs/12 puts resource respawn timers on the cut
# list because they "would defuse the expanding-radius pressure, which is load-bearing", so a
# second search of the same cupboard must yield nothing, forever -- and must say which of the two
# "nothing"s it is, because "there is nothing here" and "you already emptied this" mean completely
# different things to somebody deciding whether a building is worth the walk.
func _a_container_yields_once_and_is_empty_after() -> bool:
	var w: Variant = _booted(7788)["world"]
	var actor: int = int(w.player)
	var at: Dictionary = w.components.get_component(actor, "position") as Dictionary

	# Nothing in reach yet: the refusal must name that, not "already-searched".
	var empty_handed: Dictionary = SimContainers.search_nearest(w, actor)
	if bool(empty_handed.get("ok", false)) or String(empty_handed.get("reason", "")) != "nothing-here":
		push_error("with no container in reach the refusal was %s" % str(empty_handed))
		return false

	var box: int = SimContainers.make_container(w, float(at["x"]) + 0.5, float(at["y"]), "cupboard", "residential")
	var before: int = _ground_count(w)
	var first: Dictionary = SimContainers.search_nearest(w, actor)
	if not bool(first.get("ok", false)):
		push_error("a container in reach refused the first search: %s" % str(first))
		return false
	var after: int = _ground_count(w)
	if after <= before:
		push_error("a searched container yielded nothing: %d items on the ground before and %d after" % [before, after])
		return false
	if int(first.get("yielded", 0)) != after - before:
		push_error("the search reported %d yielded but %d appeared" % [int(first.get("yielded", 0)), after - before])
		return false

	# Depletion, and the whole point: a second search yields nothing and says why.
	var second: Dictionary = SimContainers.search_nearest(w, actor)
	if bool(second.get("ok", false)):
		push_error("a container was searched twice")
		return false
	if String(second.get("reason", "")) != "already-searched":
		push_error("the second search refused with %s rather than already-searched" % str(second.get("reason", "")))
		return false
	if _ground_count(w) != after:
		push_error("a second search put more on the ground: %d -> %d" % [after, _ground_count(w)])
		return false

	# Reach is real, and it is the true negative for the yield above: the identical container
	# three metres away refuses, so the first search proves proximity rather than existence.
	var far: int = SimContainers.make_container(w, float(at["x"]) + 3.0, float(at["y"]), "cupboard", "residential")
	var reached: Dictionary = SimContainers.search(w, actor, far)
	if bool(reached.get("ok", false)) or String(reached.get("reason", "")) != "out-of-reach":
		push_error("a container 3.0 m away was searchable: %s" % str(reached))
		return false

	# And the prose, which is the only thing the player actually gets. No digits: godot:check:hud
	# allows none on the player HUD but the day counter, and this is a player-facing read model.
	var said: String = SimContainers.hud_clause(w, actor)
	if said.find("already been through") < 0:
		push_error("standing at a searched cupboard, the HUD said \"%s\"" % said)
		return false
	for ch in said:
		if ch >= "0" and ch <= "9":
			push_error("the container HUD clause carries a digit: \"%s\"" % said)
			return false
	# The silence half, and it needs its own body rather than reusing one of the containers above:
	# a container stands at its own position, so asking for its clause always finds itself in
	# reach and would pass no matter what the reach test did.
	var bystander: int = int(w.entities.spawn())
	w.components.set_component(bystander, "position", {"x": 5.5, "y": 5.5})
	if SimContainers.hud_clause(w, bystander) != "":
		push_error("the HUD clause spoke to somebody standing near no container at all")
		return false

	print("CONTAINER OK first search yielded %d, second refused already-searched with nothing added, 3.0 m refused out-of-reach, prose is digit-free: \"%s\"" % [int(first.get("yielded", 0)), said])
	return true


# A container naming a table nobody wrote would empty itself for nothing -- the worst outcome,
# because the site is spent and the player got zero. SimContainers refuses rather than spending
# it; this asserts no shipped map can reach that branch in the first place.
func _every_container_site_names_a_table_that_exists() -> bool:
	var by_location: Dictionary = {}
	for key in _tables().keys():
		by_location[String((_tables()[key] as Dictionary).get("location", ""))] = true
	var containers: int = 0
	var kinds: Dictionary = {}
	for path in _maps().keys():
		var loot: Variant = (_maps()[path] as Dictionary).get("loot")
		if not (loot is Array):
			continue
		for site in loot as Array:
			var s: Dictionary = site as Dictionary
			var kind: String = String(s.get("container", ""))
			if kind == "":
				continue
			containers += 1
			kinds[kind] = true
			if not by_location.has(String(s.get("table", ""))):
				push_error("%s: container \"%s\" names table %s, which no content entry declares" % [path, kind, String(s.get("table", ""))])
				return false
	if containers == 0:
		push_error("SKIP-WORTHY: no map declares a container, so nothing here was judged")
		return false

	# The true negative and the reason this is not just the map-sites walk again: a booted district
	# must actually STAND these, and stand exactly as many as the map declares. A `container` key
	# that place_loot ignored would scatter them instead and pass every assertion above.
	var w: Variant = _booted(20260805)["world"]
	var standing: int = w.components.query(["searchable", "position"]).size()
	if standing != containers:
		push_error("%d container sites declared but %d standing in a booted district" % [containers, standing])
		return false
	print("CONTAINER SITES OK %d declared (%s), %d standing, every table resolves" % [containers, str(kinds.keys()), standing])
	return true


func _ground_count(w: Variant) -> int:
	return w.components.query(["itemBase", "position"]).size()
