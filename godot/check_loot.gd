extends SceneTree
# Location loot tables and the sites that place them: content declares what a place yields *and*
# where the places are, the generator draws the sites per seed, SimBoot.place_loot rolls them.
#
# This gate carries the same extra weight check_appearance.gd does, and for the same reason:
# content_validator.gd is shallow. It checks top-level property types and rejects unexpected
# top-level keys, but it does not recurse -- so nothing in `entries`, `rolls`, `tierWeights` or a
# district's `lootProfile` is schema-enforced at load. A wrong key inside a nested block is exactly
# the failure that sat in `item.wrap.cloth`'s armor block for weeks giving zero arm protection, and
# only a purpose-built gate found it. Everything below is that gate for loot.
#
# What it holds down:
#
#  1. **Every table is well formed all the way down.** Ids, the location enum, ordered ranges,
#     positive weights, and -- the one a schema could never check -- every `item` naming an item
#     base that actually exists.
#  2. **Every district's loot profile is well formed all the way down, and reaches real things.**
#     A table nobody authored, a building tag no template carries, a container share with no
#     container names behind it: each is a site that never places or places nothing.
#  3. **Every site a shipped district generates resolves to a table and stands somewhere open.**
#     Walked off the *booted district's* `map.sites` per shipped district type, not off a map JSON:
#     the sites are drawn per seed now, so the manifest is the only place the truth lives.
#  4. **Interiors are where the loot is.** docs/24: "interiors are where the game happens". Every
#     indoor site stands inside a building the placer actually put down, holding a table that
#     district's profile allows for that building's tags -- a shop does not hold a bedside table --
#     and the handful of outdoor sites stand on open ground.
#  5. **Every authored location is reachable in play.** Each is placed by at least one shipped
#     district's canonical boot: commercial by the town centre, the military cache by the suburb.
#  6. **The counts are the profile's.** Site counts per table sit inside the bounds the district's
#     own profile declares, at the gate size and the shipped size both.
#  7. **The sites are a function of the seed.** Same seed, same sites; a different seed, different
#     ones; and the dressing passes cannot move one, because sites are layout.
#  8. **A template carries its own loot.** The civic annex's two authored rows land at their
#     absolute tiles, and a building template with a `loot` block stamps its site the same way.
#  9. **The tier is a property of the place.** A military cache must come out measurably better
#     than a kitchen drawer, or tierWeights is decoration.
# 10. **A container is rolled once.** Site depletion is that it is searched once, forever.
#
# Every assertion carries a true negative. A gate that cannot fail is worse than no gate.

const SimBoot = preload("res://sim/boot.gd")
const SimLoot = preload("res://sim/loot.gd")
const SimContainers = preload("res://sim/modules/containers.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const ContentLoader = preload("res://platform/content_loader.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimWorldgen = preload("res://sim/map/worldgen.gd")
const SimTemplates = preload("res://sim/map/templates.gd")

const LOCATIONS: Array[String] = ["residential", "commercial", "industrial", "medical", "military_cache"]
const DANGERS: Array[String] = ["low", "moderate", "high", "very_high", "extreme"]
# What an outdoor perDistrict site may declare it stands on, kept in step with district.schema.json
# by hand the way LOCATIONS is. One value today: a car out of `map.vehicles`.
const HOSTS: Array[String] = ["vehicle"]
# The tier ids a table's `tierWeights` may name. This was a literal copy of SimItems.TIERS, and it
# went stale the moment docs/10's fourth tier landed: it still refused `named` -- correctly, as it
# happens -- while its own message called it "not a SimItems.TIERS id", which by then was false.
#
# Derived now, and derived from the *rollable* tiers rather than from all of them, because those are
# two different questions. A tierWeights entry means "roll an ordinary base at this tier", and the
# named tier is hand-authored: naming it in a table would produce a Named Steel Pipe, an item at a
# tier that permits no affixes and carries no authored ones -- a strictly worse scavenged. The six
# named items reach the world as `entries` in loot.military_cache instead.
static func _tier_ids() -> Array[String]:
	var out: Array[String] = []
	for t in SimItems.rollable_tiers():
		out.append(String((t as Dictionary)["id"]))
	return out
# Enough samples that a tier distribution is a distribution rather than a coin toss.
const TIER_SAMPLES: int = 2000

const CANON_SEED: int = 20260805
const GATE_SIZE: int = 64
# Interiors dominate, and the odd car boot is the exception that says so. Measured on the canonical
# seed at 256: 67 of 69 sites indoors in the suburb, 171 of 174 in the town centre.
const INDOOR_SHARE_MIN: float = 0.9

var _tree_cache: Dictionary = {}
var _boot_cache: Dictionary = {}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _every_table_is_well_formed_all_the_way_down() and ok
	ok = _every_district_profile_is_well_formed_and_reaches_real_things() and ok
	ok = _every_generated_site_resolves_and_stands_somewhere_open() and ok
	ok = _the_loot_is_indoors_and_in_the_kind_of_building_that_holds_it() and ok
	ok = _every_authored_location_is_placed_by_a_shipped_district() and ok
	ok = _site_counts_stay_inside_the_bounds_the_profile_declares() and ok
	ok = _the_sites_are_a_function_of_the_seed() and ok
	ok = _a_template_carries_its_own_loot() and ok
	ok = _a_cache_yields_better_gear_than_a_kitchen() and ok
	ok = _quantities_stay_inside_the_range_they_declare() and ok
	ok = _the_scatter_is_seeded() and ok
	ok = _a_container_yields_once_and_is_empty_after() and ok
	ok = _only_somebody_standing_at_it_can_take_from_it() and ok
	ok = _take_all_takes_what_fits_and_leaves_the_rest() and ok
	ok = _an_npc_still_empties_it_onto_the_floor() and ok
	ok = _opening_draws_exactly_what_scattering_drew() and ok
	ok = _the_prose_has_three_states_and_no_digits() and ok
	ok = _every_kind_a_district_names_has_a_grid() and ok
	ok = _every_container_site_stands_in_the_booted_district() and ok
	if ok:
		print("LOOT_OK tables and profiles well formed, generated sites resolve and stand open indoors, every location placed, counts inside their bounds, sites seeded and dressing-proof, templates carry their own, tier is a property of the place, a container is a grid that yields once, only to somebody standing at it")
		quit(0)
	else:
		push_error("LOOT_FAIL")
		quit(1)


# --- helpers ------------------------------------------------------------------------------

# One directory walk for the whole gate: `load_tree` reads every JSON under content/, and this file
# used to call it once per helper call, several of them inside loops.
func _tree() -> Dictionary:
	if _tree_cache.is_empty():
		_tree_cache = ContentLoader.load_tree()
	return _tree_cache


# Every loot table in content, as {content_path: entry}.
func _tables() -> Dictionary:
	var out: Dictionary = {}
	for path in _tree().keys():
		if not String(path).begins_with("loot/"):
			continue
		var value: Variant = _tree()[path]
		if value is Array:
			for entry in value as Array:
				if entry is Dictionary:
					out["%s#%s" % [path, String((entry as Dictionary).get("id", "?"))]] = entry as Dictionary
	return out


# The authored locations, as a set: {"residential": true, ...}.
func _authored_locations() -> Dictionary:
	var out: Dictionary = {}
	for key in _tables().keys():
		out[String((_tables()[key] as Dictionary).get("location", ""))] = true
	return out


func _item_ids() -> Dictionary:
	var out: Dictionary = {}
	for path in _tree().keys():
		if not String(path).begins_with("items/"):
			continue
		var value: Variant = _tree()[path]
		if value is Array:
			for entry in value as Array:
				if entry is Dictionary:
					out[String((entry as Dictionary).get("id", ""))] = true
	return out


# The shipped district types, by id, in a fixed order.
func _districts() -> Array[String]:
	var out: Array[String] = []
	for path in _tree().keys():
		if not String(path).begins_with("districts/"):
			continue
		var entry: Variant = _tree()[path]
		if entry is Dictionary:
			out.append(String((entry as Dictionary).get("id", "")))
	out.sort()
	return out


# Every building tag any shipped template carries, and the tags of one template by id.
func _shipped_tags() -> Dictionary:
	var out: Dictionary = {}
	for t in SimWorldgen.templates_of(_tree()):
		for tag in (t as Dictionary).get("tags", []) as Array:
			out[String(tag)] = true
	return out


func _tags_by_id() -> Dictionary:
	var out: Dictionary = {}
	for t in SimWorldgen.templates_of(_tree()):
		out[String((t as Dictionary).get("id", ""))] = (t as Dictionary).get("tags", []) as Array
	return out


# A booted district at the size the game actually plays, one per district type, reused across every
# lane that reads a manifest. Two boots of 256, not eight: generation is ~200 ms and the boot that
# follows it places every site the district holds.
func _district_boot(district_id: String) -> Dictionary:
	if not _boot_cache.has(district_id):
		_boot_cache[district_id] = SimBoot.playable(CANON_SEED, SimTileMap.DISTRICT_TILES, district_id)
	return _boot_cache[district_id] as Dictionary


# A booted district at the shipped size for one seed. Used by the lanes that need a world to roll
# in rather than a manifest to read, which is why they take a seed rather than a district.
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
				if not _tier_ids().has(String(tier)):
					problems.append("%s.tierWeights: %s is not a tier a table may roll (%s)" % [key, String(tier), str(_tier_ids())])
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


# --- 2. the district's loot profile ---------------------------------------------------------

# `lootProfile` is where a district says what it holds, and the validator reaches exactly one level
# of it (that it is an object). Everything below that is here: the tables named must be authored,
# the building tags named must be tags a shipped template actually carries, a container share with
# no names behind it is a share of nothing, and a container's name reaches the player's HUD -- so a
# digit in one would walk straight through godot:check:hud's ban, which only reads the screen.
func _profile_problems(label: String, district: Dictionary, authored_override: Variant = null) -> Array[String]:
	var out: Array[String] = []
	var profile: Variant = district.get("lootProfile")
	if not (profile is Dictionary):
		out.append("%s: no lootProfile, so this district generates no loot at all" % label)
		return out
	var p: Dictionary = profile as Dictionary
	for key in p.keys():
		if String(key) != "perBuilding" and String(key) != "perDistrict":
			out.append("%s.lootProfile: unexpected key %s" % [label, String(key)])
	if not p.has("perBuilding") and not p.has("perDistrict"):
		out.append("%s.lootProfile: neither perBuilding nor perDistrict, so it declares nothing" % label)

	# Normally the shipped tables. The override exists for one negative below: every one of
	# docs/12's five locations is authored now that the yard slice filled `industrial`, so the
	# "no content entry" branch below can no longer be reached through the enum. It guards against
	# a shipped table being *deleted* while a profile still names it, which is a real thing to
	# guard, so it is proved against a set with one missing rather than left as code nothing reaches.
	var authored: Dictionary = (authored_override as Dictionary) if authored_override is Dictionary else _authored_locations()
	var tags: Dictionary = _shipped_tags()
	for group in ["perBuilding", "perDistrict"]:
		var rows: Variant = p.get(String(group))
		if rows == null:
			continue
		if not (rows is Array) or (rows as Array).is_empty():
			out.append("%s.lootProfile.%s: present but not a non-empty array" % [label, String(group)])
			continue
		for row_v in rows as Array:
			if not (row_v is Dictionary):
				out.append("%s.lootProfile.%s: a non-object entry" % [label, String(group)])
				continue
			var row: Dictionary = row_v as Dictionary
			var where: String = "%s.lootProfile.%s[%s]" % [label, String(group), String(row.get("table", "?"))]
			var table: String = String(row.get("table", ""))
			if not LOCATIONS.has(table):
				out.append("%s: table %s is not one of docs/12's five" % [where, table])
			elif not authored.has(table):
				out.append("%s: table %s has no content entry, so every site of it would place nothing" % [where, table])
			var wanted: Variant = row.get("tags")
			var outdoors: bool = bool(row.get("outdoors", false))
			if String(group) == "perBuilding" or not outdoors:
				if not (wanted is Array) or (wanted as Array).is_empty():
					out.append("%s: no tags, so no building qualifies and the sites have nowhere to go" % where)
				else:
					for tag in wanted as Array:
						if not tags.has(String(tag)):
							out.append("%s: tag %s is on no shipped building template" % [where, String(tag)])
			if String(group) == "perBuilding":
				out.append_array(_range_problems("%s.sites" % where, row.get("sites"), 0))
				if row.get("sites") is Dictionary and int((row["sites"] as Dictionary).get("max", 0)) <= 0:
					out.append("%s.sites: max is 0, so this entry places nothing" % where)
				if row.has("count"):
					out.append("%s: count belongs to perDistrict, not perBuilding" % where)
			else:
				if not row.has("count"):
					out.append("%s: no count" % where)
				elif int(row.get("count", 0)) <= 0:
					out.append("%s: count %d places nothing" % [where, int(row.get("count", 0))])
				if row.has("sites"):
					out.append("%s: sites belongs to perBuilding, not perDistrict" % where)
			# `host` says what an outdoor site stands *on*. Only one value exists (a car from
			# `map.vehicles`), it is only meaningful outdoors, and it is perDistrict's alone --
			# a perBuilding site stands on the floor of the building it was drawn for.
			if row.has("host"):
				var host: String = String(row.get("host", ""))
				if not HOSTS.has(host):
					out.append("%s: host %s is not one of %s" % [where, host, str(HOSTS)])
				if String(group) == "perBuilding":
					out.append("%s: host belongs to perDistrict, not perBuilding" % where)
				elif not outdoors:
					out.append("%s: host %s on a site that is not outdoors, which stands inside a building instead" % [where, host])
			var share: float = float(row.get("containerShare", 0.0))
			if share < 0.0 or share > 1.0:
				out.append("%s: containerShare %.2f is outside 0..1" % [where, share])
			var kinds: Variant = row.get("containers")
			if share > 0.0 and (not (kinds is Array) or (kinds as Array).is_empty()):
				out.append("%s: containerShare %.2f with no container names behind it" % [where, share])
			if kinds is Array:
				for kind in kinds as Array:
					var spoken: String = String(kind)
					if spoken.strip_edges().is_empty():
						out.append("%s: an empty container name" % where)
					for ch in spoken:
						if ch >= "0" and ch <= "9":
							out.append("%s: container name \"%s\" carries a digit, and SimContainers.hud_clause puts it on the player's HUD" % [where, spoken])
							break
	return out


func _every_district_profile_is_well_formed_and_reaches_real_things() -> bool:
	var ids: Array[String] = _districts()
	if ids.is_empty():
		push_error("no district ships, so there is no loot profile to judge")
		return false
	var problems: Array[String] = []
	var counted: int = 0
	for id in ids:
		var district: Dictionary = SimWorldgen.district_of(_tree(), String(id))
		problems.append_array(_profile_problems(String(id), district))
		var profile: Variant = district.get("lootProfile")
		if profile is Dictionary:
			counted += ((profile as Dictionary).get("perBuilding", []) as Array).size()
			counted += ((profile as Dictionary).get("perDistrict", []) as Array).size()
	if not problems.is_empty():
		for p in problems:
			push_error(p)
		return false

	# The true negative: a profile broken in each of the ways above must report each of them. The
	# families are separate rows so one report cannot stand in for another.
	var broken: Dictionary = {"lootProfile": {
		"perBuilding": [
			# "quarry" is a table nobody wrote, and it has to be a name off the enum entirely now:
			# `industrial` stood here until the yard slice authored it, and a negative that leans on
			# a slot being empty stops being a negative the day somebody fills it.
			{"table": "quarry", "tags": ["residential"], "sites": {"min": 1, "max": 2}},
			{"table": "residential", "tags": ["marina"], "sites": {"min": 2, "max": 1}},
			{"table": "commercial", "tags": ["commercial"], "sites": {"min": 1, "max": 1}, "containerShare": 0.5, "containers": []},
			{"table": "residential", "tags": ["residential"], "sites": {"min": 1, "max": 1}, "host": "vehicle"},
		],
		"perDistrict": [
			{"table": "medical", "count": 0, "tags": ["civic"]},
			{"table": "medical", "count": 1, "tags": ["civic"], "containerShare": 1.0, "containers": ["locker 3"]},
			{"table": "residential", "count": 1, "outdoors": true, "host": "hovercraft"},
			{"table": "residential", "count": 1, "tags": ["residential"], "host": "vehicle"},
		],
	}}
	var said: Array[String] = _profile_problems("probe", broken)
	var wanted: Array[String] = [
		"is not one of docs/12's five",
		"is on no shipped building template",
		"max 1 is below min 2",
		"with no container names behind it",
		"places nothing",
		"carries a digit",
		"host hovercraft is not one of",
		"on a site that is not outdoors",
		"host belongs to perDistrict, not perBuilding",
	]
	for phrase in wanted:
		var matched: bool = false
		for p in said:
			if p.find(String(phrase)) >= 0:
				matched = true
		if not matched:
			push_error("a profile broken with \"%s\" was not reported: %s" % [String(phrase), str(said)])
			return false
	if _profile_problems("probe", {}).is_empty():
		push_error("a district with no lootProfile at all was passed as clean")
		return false

	# The deleted-table branch, proved on the shipped yard against an authored set with
	# `industrial` taken out of it -- which is exactly what deleting `loot.industrial` while the
	# yard still names it would look like. Without this the branch would be code nothing reaches,
	# which is the shape this milestone has paid for twelve times.
	var missing: Dictionary = _authored_locations()
	missing.erase("industrial")
	# `SimWorldgen.district_of` is the one lookup by id, and using it here rather than a second
	# copy of the walk is the point: if the yard's entry ever moves, this follows it.
	var yard: Dictionary = SimWorldgen.district_of(_tree(), "district.industrial_park")
	if yard.is_empty():
		push_error("no district.industrial_park to judge, so the deleted-table negative proves nothing")
		return false
	var deleted: Array[String] = _profile_problems("yard", yard, missing)
	var found_deleted: bool = false
	for d in deleted:
		if d.find("has no content entry") >= 0:
			found_deleted = true
	if not found_deleted:
		push_error("a profile naming a table whose content entry was deleted was not reported: %s" % str(deleted))
		return false
	var clean: Array[String] = _profile_problems("yard", yard)
	if not clean.is_empty():
		push_error("the shipped yard profile is not clean against the real tables: %s" % str(clean))
		return false

	print("PROFILE OK %d district types, %d profile entries, every table authored, every tag on a shipped template, container names digit-free; %d families of breakage each reported" % [
		ids.size(), counted, wanted.size(),
	])
	return true


# --- 3. the generated sites ------------------------------------------------------------------

# The problems with a list of `map.sites` records, judged against the authored tables and whatever
# says a tile is blocked. Takes the blocking test as a Callable so the same walk can judge a booted
# world's own view of its map (the strongest question: can somebody standing there pick it up) and
# a bare generated fixture that has no world at all.
func _site_problems(label: String, sites: Array, blocked: Callable) -> Array[String]:
	var out: Array[String] = []
	var authored: Dictionary = _authored_locations()
	for site in sites:
		if not (site is Dictionary):
			out.append("%s: a non-object site record" % label)
			continue
		var s: Dictionary = site as Dictionary
		for field in ["x", "y", "table"]:
			if not s.has(field):
				out.append("%s: a site record with no %s" % [label, String(field)])
		if not s.has("x") or not s.has("y") or not s.has("table"):
			continue
		var location: String = String(s["table"])
		if not authored.has(location):
			out.append("%s: site at (%d, %d) names table %s, which no content entry declares" % [
				label, int(s["x"]), int(s["y"]), location,
			])
		if bool(blocked.call(int(s["x"]), int(s["y"]))):
			out.append("%s: site at (%d, %d) stands inside a wall" % [label, int(s["x"]), int(s["y"])])
		if s.has("container") and String(s["container"]).strip_edges().is_empty():
			out.append("%s: site at (%d, %d) carries an empty container name" % [label, int(s["x"]), int(s["y"])])
	return out


func _every_generated_site_resolves_and_stands_somewhere_open() -> bool:
	var total: int = 0
	var per_type: Array[String] = []
	for id in _districts():
		var boot: Dictionary = _district_boot(String(id))
		var w: Variant = boot["world"]
		var map: Variant = boot["map"]
		var sites: Array = map.sites as Array
		if sites.is_empty():
			push_error("%s generated no loot sites at all, so nothing here was judged" % String(id))
			return false
		var problems: Array[String] = _site_problems(String(id), sites, func(x: int, y: int) -> bool:
			return bool(w.is_blocked_tile(x, y))
		)
		if not problems.is_empty():
			for p in problems:
				push_error(p)
			return false
		total += sites.size()
		per_type.append("%s %d" % [String(id), sites.size()])

	# The true negatives, both on the walk that just passed: a record forced onto a wall must fail
	# the standing check, and one naming a table nobody wrote must fail resolution. Without them a
	# walk that had stopped judging would report every district clean.
	var probe: Dictionary = _district_boot(SimWorldgen.DEFAULT_DISTRICT)
	var pw: Variant = probe["world"]
	var blocked_at: Callable = func(x: int, y: int) -> bool:
		return bool(pw.is_blocked_tile(x, y))
	var wall: Vector2i = _some_blocked_tile(pw)
	if wall.x < 0:
		push_error("no tile in the booted district is blocked, so the siting check cannot fail")
		return false
	var forced: Array = [{"x": wall.x, "y": wall.y, "table": "residential"}]
	if _site_problems("probe", forced, blocked_at).size() != 1:
		push_error("a site forced onto the wall at %s was not reported" % str(wall))
		return false
	var unwritten: Array = [{"x": int(SimTileMap.player_start(probe["map"]).x), "y": int(SimTileMap.player_start(probe["map"]).y), "table": "marina"}]
	if _site_problems("probe", unwritten, blocked_at).size() != 1:
		push_error("a site naming the unwritten table \"marina\" was not reported")
		return false

	# And the same walk over a district whose *profile* names a table nobody wrote: the pass places
	# the sites the content asked for, and this gate is what refuses them. The name has to be one
	# off the enum now -- `industrial` was the last empty slot and the yard slice filled it, so all
	# five locations are authored and none of them can play the unwritten one any more.
	var fixture: Dictionary = _fixture_district("district.fixture.unwritten", {
		"perBuilding": [{"table": "quarry", "tags": ["residential", "shed"], "sites": {"min": 1, "max": 1}}],
	})
	var bad_map: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, _tree_with(fixture), String(fixture["id"]))
	var bad_sites: Array = _profile_sites(bad_map)
	if bad_sites.is_empty():
		push_error("the unwritten-table fixture district placed no sites, so the negative proves nothing")
		return false
	if _site_problems("fixture", bad_sites, func(x: int, y: int) -> bool:
		return SimTileMap.is_solid(bad_map, x, y)
	).size() != bad_sites.size():
		push_error("%d sites of an unauthored table were not all reported" % bad_sites.size())
		return false

	print("SITES OK %d generated sites across %d district types (%s), every table resolves and every tile is open; a walled site, an unwritten table and %d sites of an unauthored one are each rejected" % [
		total, _districts().size(), ", ".join(per_type), bad_sites.size(),
	])
	return true


func _some_blocked_tile(w: Variant) -> Vector2i:
	for x in range(0, SimTileMap.DISTRICT_TILES):
		for y in range(0, SimTileMap.DISTRICT_TILES):
			if w.is_blocked_tile(x, y):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


# --- 4. interiors are where the loot is -------------------------------------------------------

# docs/24: "interiors are authored, never generated ... interiors are where the game happens". So
# the loot is inside buildings, and the building it is inside has to be the kind of building the
# district's profile says holds that table -- a shop does not hold a bedside table. Judged per
# site against the placement manifest, which is the only thing that knows what got built where.
func _the_loot_is_indoors_and_in_the_kind_of_building_that_holds_it() -> bool:
	var tags_by_id: Dictionary = _tags_by_id()
	var lines: Array[String] = []
	for id in _districts():
		var boot: Dictionary = _district_boot(String(id))
		var map: Variant = boot["map"]
		var district: Dictionary = SimWorldgen.district_of(_tree(), String(id))
		var allowed: Dictionary = _tables_by_tag(district)
		var annex: Rect2i = SimTileMap.annex_rect(map)
		var indoors: int = 0
		var outdoors: int = 0
		var problems: Array[String] = []
		for site in map.sites as Array:
			var s: Dictionary = site as Dictionary
			var at := Vector2i(int(s["x"]), int(s["y"]))
			if annex.has_point(at):
				# The colony's own two authored sites: they belong to the annex template rather than
				# to the district's profile, and `_a_template_carries_its_own_loot` is their lane.
				continue
			if not SimTileMap.is_indoors(map, at.x, at.y):
				outdoors += 1
				if SimTileMap.is_solid(map, at.x, at.y):
					problems.append("%s: the outdoor site at %s does not stand on open ground" % [String(id), str(at)])
				continue
			indoors += 1
			var host: Dictionary = _host_of(map, at)
			if host.is_empty():
				problems.append("%s: the indoor site at %s stands in no building the placer recorded" % [String(id), str(at)])
				continue
			var table: String = String(s["table"])
			var fits: bool = false
			for tag in tags_by_id.get(String(host.get("id", "")), []) as Array:
				if (allowed.get(String(tag), {}) as Dictionary).has(table):
					fits = true
			if not fits:
				problems.append("%s: a %s site stands in %s, whose tags are %s and whose profile allows %s" % [
					String(id), table, String(host.get("id", "")), str(tags_by_id.get(String(host.get("id", "")), [])),
					str(allowed.keys()),
				])
		if not problems.is_empty():
			for p in problems:
				push_error(p)
			return false
		var share: float = float(indoors) / float(maxi(1, indoors + outdoors))
		if share < INDOOR_SHARE_MIN:
			push_error("%s put %.1f%% of its loot indoors, floor is %.0f%%" % [String(id), 100.0 * share, 100.0 * INDOOR_SHARE_MIN])
			return false
		lines.append("%s %d indoors / %d out (%.1f%%)" % [String(id), indoors, outdoors, 100.0 * share])

	# The true negative: the same host walk must reject a table the profile does not allow in that
	# kind of building. Taken from the shipped suburb, whose commercial sites belong in commercial
	# buildings and nowhere else.
	var probe_map: Variant = _district_boot(SimWorldgen.DEFAULT_DISTRICT)["map"]
	var allowed_probe: Dictionary = _tables_by_tag(SimWorldgen.district_of(_tree(), SimWorldgen.DEFAULT_DISTRICT))
	var residential_only: Dictionary = allowed_probe.get("residential", {}) as Dictionary
	if residential_only.has("commercial") or not residential_only.has("residential"):
		push_error("the suburb's residential buildings are declared to hold %s -- the host test is not reading the profile" % str(residential_only.keys()))
		return false
	if not _host_of(probe_map, Vector2i(0, 0)).is_empty():
		push_error("the map's own corner was reported as inside a building")
		return false

	print("INDOORS OK %s; every indoor site sits in a building whose tags its table is authored for" % ", ".join(lines))
	return true


# {tag: {table: true}} -- which tables a district's profile allows in a building carrying each tag.
func _tables_by_tag(district: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var profile: Variant = district.get("lootProfile")
	if not (profile is Dictionary):
		return out
	for group in ["perBuilding", "perDistrict"]:
		for row_v in (profile as Dictionary).get(String(group), []) as Array:
			var row: Dictionary = row_v as Dictionary
			for tag in row.get("tags", []) as Array:
				if not out.has(String(tag)):
					out[String(tag)] = {}
				(out[String(tag)] as Dictionary)[String(row.get("table", ""))] = true
	return out


# The placed building a tile falls inside, or {}.
func _host_of(map: Variant, at: Vector2i) -> Dictionary:
	for record in map.buildings as Array:
		var b: Dictionary = record as Dictionary
		if Rect2i(int(b["x"]), int(b["y"]), int(b["w"]), int(b["h"])).has_point(at):
			return b
	return {}


# --- 5. every authored location is reachable in play ------------------------------------------

# The lane that used to ask whether a location appeared in a map JSON. Sites are drawn per seed
# now, so the question is whether a shipped district's canonical boot actually places one: a table
# authored and placed by nobody is the dead-socket pattern in content form, and `commercial` sat in
# three synced enums with no table behind it for a milestone.
func _every_authored_location_is_placed_by_a_shipped_district() -> bool:
	var authored: Dictionary = _authored_locations()
	if authored.size() < 4:
		push_error("only %d location tables authored, the slice scope asks for four" % authored.size())
		return false
	var placed: Dictionary = {}
	var by_district: Dictionary = {}
	for id in _districts():
		var here: Dictionary = {}
		var manifest: Variant = _district_boot(String(id))["map"]
		for site in manifest.sites as Array:
			var table: String = String((site as Dictionary)["table"])
			placed[table] = true
			here[table] = int(here.get(table, 0)) + 1
		by_district[String(id)] = here
	var unreachable: Array[String] = []
	for location in authored.keys():
		if not placed.has(location):
			unreachable.append(String(location))
	if not unreachable.is_empty():
		push_error("authored but placed by no shipped district on the canonical seed, so unreachable in play: %s" % str(unreachable))
		return false

	# The two the district types exist to prove: the town centre is what makes commercial reachable
	# (docs/30: "town center is the type that forces the second loot table"), and the suburb is
	# where the cache is.
	for named in [["district.town_center", "commercial"], [SimWorldgen.DEFAULT_DISTRICT, "military_cache"]]:
		var id2: String = String((named as Array)[0])
		var table2: String = String((named as Array)[1])
		if int((by_district.get(id2, {}) as Dictionary).get(table2, 0)) < 1:
			push_error("%s placed no %s site: it holds %s" % [id2, table2, str((by_district.get(id2, {}) as Dictionary))])
			return false
	# The true negative: a location nobody authored must not be answered for, and the count above
	# must be reading the manifest rather than the enum.
	if authored.has("marina") or placed.has("marina"):
		push_error("a table nobody wrote was reported as authored or placed")
		return false
	if int((by_district.get("district.town_center", {}) as Dictionary).get("military_cache", 0)) != 0:
		push_error("the town centre placed a military cache, which its profile does not declare")
		return false

	print("LOCATIONS OK %d authored (%s), each placed by a shipped district: %s" % [
		authored.size(), str(authored.keys()), str(by_district),
	])
	return true


# --- 6. the counts are the profile's ----------------------------------------------------------

# Site counts per table, against the bounds the district's own profile declares: a `perBuilding`
# entry's min..max times the number of buildings that qualify for it, plus a `perDistrict` entry's
# count scaled by area. Derived here from the content and the placement manifest rather than read
# back off the generator, so a pass that ignored `sites`, or the tags, or the scaling, lands
# outside its own band.
func _site_counts_stay_inside_the_bounds_the_profile_declares() -> bool:
	var tags_by_id: Dictionary = _tags_by_id()
	var lines: Array[String] = []
	for id in _districts():
		var district: Dictionary = SimWorldgen.district_of(_tree(), String(id))
		for size in [GATE_SIZE, SimTileMap.DISTRICT_TILES]:
			# The shipped size is the district boot's own map, which is already in hand; the gate
			# size is a bare generation, which costs ~15 ms and no world.
			var map: Variant = _district_boot(String(id))["map"] if int(size) == SimTileMap.DISTRICT_TILES \
					else SimWorldgen.generate(CANON_SEED, int(size), _tree(), String(id))
			var counts: Dictionary = {}
			for site in map.sites as Array:
				var record: Dictionary = site as Dictionary
				if SimTileMap.annex_rect(map).has_point(Vector2i(int(record["x"]), int(record["y"]))):
					continue
				counts[String(record["table"])] = int(counts.get(String(record["table"]), 0)) + 1
			var bounds: Dictionary = _declared_bounds(district, map, tags_by_id, int(size))
			for table in bounds.keys():
				var band: Array = bounds[table] as Array
				var got: int = int(counts.get(String(table), 0))
				if got < int(band[0]) or got > int(band[1]):
					push_error("%s at %d placed %d %s sites, its profile declares %d..%d" % [
						String(id), int(size), got, String(table), int(band[0]), int(band[1]),
					])
					return false
			for table2 in counts.keys():
				if not bounds.has(String(table2)):
					push_error("%s at %d placed %d %s sites its profile never declares" % [
						String(id), int(size), int(counts[table2]), String(table2),
					])
					return false
			lines.append("%s at %d %s" % [String(id), int(size), str(counts)])

	# The rare tables specifically, because "scaled by area" is a decision rather than an accident:
	# the shipped suburb holds exactly one medical store and one cache at 256, and the 64-tile
	# miniature -- a sixteenth of the area -- holds neither. Pinned, so a change to the scaling has
	# to come here and say so.
	var suburb_map: Variant = _district_boot(SimWorldgen.DEFAULT_DISTRICT)["map"]
	var suburb: Dictionary = _table_counts(suburb_map.sites as Array)
	if int(suburb.get("medical", 0)) != 1 or int(suburb.get("military_cache", 0)) != 1:
		push_error("the suburb at 256 holds %d medical and %d cache sites, not one of each" % [
			int(suburb.get("medical", 0)), int(suburb.get("military_cache", 0)),
		])
		return false
	var miniature: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, _tree())
	var few: Dictionary = _table_counts(miniature.sites as Array)
	if int(few.get("medical", 0)) != 0 or int(few.get("military_cache", 0)) != 0:
		push_error("the 64-tile miniature holds %d medical and %d cache sites, and the area scaling says neither" % [
			int(few.get("medical", 0)), int(few.get("military_cache", 0)),
		])
		return false

	# The true negative: a fixture district that declares one site per qualifying building places
	# exactly one per qualifying building, and one that declares none places none. Without this,
	# bounds derived from the same content the pass read could both be wrong together.
	var one: Dictionary = _fixture_district("district.fixture.one", {
		"perBuilding": [{"table": "residential", "tags": ["shed"], "sites": {"min": 1, "max": 1}}],
	})
	var one_map: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, _tree_with(one), String(one["id"]))
	var sheds: int = 0
	for record2 in one_map.buildings as Array:
		if (tags_by_id.get(String((record2 as Dictionary)["id"]), []) as Array).has("shed"):
			sheds += 1
	if sheds < 1:
		push_error("the one-per-shed fixture district built no sheds, so the count proves nothing")
		return false
	if _profile_sites(one_map).size() != sheds:
		push_error("one site per shed over %d sheds placed %d sites" % [sheds, _profile_sites(one_map).size()])
		return false
	var none: Dictionary = _fixture_district("district.fixture.none", {
		"perBuilding": [{"table": "residential", "tags": ["civic"], "sites": {"min": 0, "max": 0}}],
	})
	var none_map: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, _tree_with(none), String(none["id"]))
	if not _profile_sites(none_map).is_empty():
		push_error("a profile declaring 0..0 sites placed %d" % _profile_sites(none_map).size())
		return false

	print("COUNTS OK %s; the suburb holds exactly one medical and one cache at 256 and neither at %d; one-per-shed places %d over %d sheds and 0..0 places none" % [
		", ".join(lines), GATE_SIZE, _profile_sites(one_map).size(), sheds,
	])
	return true


# The sites the *district profile* put down, which is every site except the ones the colony's own
# template carried in with it. The generator sites and stamps the annex on every district big
# enough to hold one now -- fixture districts included -- so a lane that means "what this profile
# placed" has to say so, or the annex's two authored rows turn up in every count and every fixture
# whose profile places nothing looks like a profile that placed two.
func _profile_sites(map: Variant) -> Array:
	var annex: Rect2i = SimTileMap.annex_rect(map)
	var out: Array = []
	for site in map.sites as Array:
		if annex.has_point(Vector2i(int((site as Dictionary)["x"]), int((site as Dictionary)["y"]))):
			continue
		out.append(site)
	return out


func _table_counts(sites: Array) -> Dictionary:
	var out: Dictionary = {}
	for site in sites:
		out[String((site as Dictionary)["table"])] = int(out.get(String((site as Dictionary)["table"]), 0)) + 1
	return out


# {table: [min, max]} for one district on one map, from the profile and the placement manifest.
# A perDistrict entry contributes its scaled count at both ends when it has somewhere to go, and
# nothing at the low end when it does not -- a district whose pool never rolled a civic building
# has nowhere to put the medical store, and gets fewer sites rather than one in a shed.
func _declared_bounds(district: Dictionary, map: Variant, tags_by_id: Dictionary, size: int) -> Dictionary:
	var out: Dictionary = {}
	var profile: Variant = district.get("lootProfile")
	if not (profile is Dictionary):
		return out
	for row_v in (profile as Dictionary).get("perBuilding", []) as Array:
		var row: Dictionary = row_v as Dictionary
		var hosts: int = _qualifying(map, tags_by_id, row.get("tags", []) as Array)
		var spec: Dictionary = row.get("sites", {}) as Dictionary
		_widen(out, String(row.get("table", "")), hosts * int(spec.get("min", 0)), hosts * int(spec.get("max", 0)))
	for row_v2 in (profile as Dictionary).get("perDistrict", []) as Array:
		var row2: Dictionary = row_v2 as Dictionary
		# The same arithmetic the pass documents, written out here rather than called: a bound that
		# asked the generator what it scaled to would agree with itself whatever it did.
		var full: int = SimTileMap.DISTRICT_TILES
		var count: int = int(round(float(int(row2.get("count", 0))) * float(size * size) / float(full * full)))
		var reachable: bool = bool(row2.get("outdoors", false)) or _qualifying(map, tags_by_id, row2.get("tags", []) as Array) > 0
		_widen(out, String(row2.get("table", "")), count if reachable else 0, count)
	return out


func _widen(bounds: Dictionary, table: String, lo: int, hi: int) -> void:
	var band: Array = bounds.get(table, [0, 0]) as Array
	bounds[table] = [int(band[0]) + lo, int(band[1]) + hi]


func _qualifying(map: Variant, tags_by_id: Dictionary, wanted: Array) -> int:
	var n: int = 0
	for record in map.buildings as Array:
		var tags: Array = tags_by_id.get(String((record as Dictionary)["id"]), []) as Array
		for tag in wanted:
			if tags.has(String(tag)):
				n += 1
				break
	return n


# --- 7. the sites are a function of the seed --------------------------------------------------

# Same property the layout has, and for the same reason: a campaign is reproducible from its seed.
# The dressing half is the one that would not be obvious -- sites are chosen before a tree is
# planted, and `_protected_tiles` then stops the dressing planting anything on one, so the same
# district with the dressing switched off holds the same loot in the same tiles.
func _the_sites_are_a_function_of_the_seed() -> bool:
	var first: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, _tree())
	var again: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, _tree())
	var other: Variant = SimWorldgen.generate(CANON_SEED + 1, GATE_SIZE, _tree())
	var undressed: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, _tree(), SimWorldgen.DEFAULT_DISTRICT, false)
	if (first.sites as Array).is_empty():
		push_error("the canonical seed generated no sites at %d, so nothing here was judged" % GATE_SIZE)
		return false
	var a: String = JSON.stringify(first.sites)
	if a != JSON.stringify(again.sites):
		push_error("two generations of seed %d disagreed about where the loot is" % CANON_SEED)
		return false
	if a == JSON.stringify(other.sites):
		push_error("seed %d and seed %d put the loot in identical places -- the seed is not reaching the sites pass" % [CANON_SEED, CANON_SEED + 1])
		return false
	if a != JSON.stringify(undressed.sites):
		push_error("the dressing passes moved the loot: %s with dressing, %s without" % [a, JSON.stringify(undressed.sites)])
		return false
	# And the dressing cannot bury one either, which is what `_protected_tiles` carrying the sites
	# buys: a tree on a car boot would be loot inside a solid tile.
	for site in first.sites as Array:
		var s: Dictionary = site as Dictionary
		if SimTileMap.is_solid(first, int(s["x"]), int(s["y"])):
			push_error("the dressing planted something solid on the site at (%d, %d)" % [int(s["x"]), int(s["y"])])
			return false
	print("SITE SEED OK %d sites at %d are identical across two generations, differ from seed %d, and are the same with the dressing off" % [
		(first.sites as Array).size(), GATE_SIZE, CANON_SEED + 1,
	])
	return true


# --- 8. a template carries its own loot -------------------------------------------------------

# The other half of where sites come from: a template's own `loot` rows, template-relative, turned
# absolute by `SimTemplates.stamp`. The civic annex is the shipped case -- its kitchen scatter and
# the cupboard in its store room -- and a fixture building template is what proves the *building*
# half of the mechanism is wired rather than merely declared in a schema, because no shipped
# building template carries loot (the district's profile covers those).
func _a_template_carries_its_own_loot() -> bool:
	var boot: Dictionary = _district_boot(SimWorldgen.DEFAULT_DISTRICT)
	var map: Variant = boot["map"]
	var w: Variant = boot["world"]
	var annex: Rect2i = SimTileMap.annex_rect(map)
	var patch: Variant = SimTileMap.load_patch_from_content(_tree(), SimWorldgen.ANNEX_PATCH_ID)
	if not (patch is Dictionary):
		push_error("no %s in content, so the annex's own loot cannot be judged" % SimWorldgen.ANNEX_PATCH_ID)
		return false
	var rows: Variant = (patch as Dictionary).get("loot")
	if not (rows is Array) or (rows as Array).is_empty():
		push_error("the annex template carries no loot rows, so this lane is asserting nothing")
		return false
	for row_v in rows as Array:
		var row: Dictionary = row_v as Dictionary
		var tile: Dictionary = row.get("tile", {}) as Dictionary
		var want := Vector2i(annex.position.x + int(tile.get("x", 0)), annex.position.y + int(tile.get("y", 0)))
		var found: Dictionary = {}
		for site in map.sites as Array:
			var s: Dictionary = site as Dictionary
			if Vector2i(int(s["x"]), int(s["y"])) == want:
				found = s
		if found.is_empty():
			push_error("the annex's authored site at relative %s is at no absolute tile %s on the booted map" % [str(tile), str(want)])
			return false
		if String(found["table"]) != String(row.get("table", "")):
			push_error("the annex's site at %s came through as %s, not %s" % [str(want), String(found["table"]), String(row.get("table", ""))])
			return false
		if String(row.get("container", "")) != String(found.get("container", "")):
			push_error("the annex's site at %s came through as container \"%s\", not \"%s\"" % [
				str(want), String(found.get("container", "")), String(row.get("container", "")),
			])
			return false
		if not SimTileMap.is_indoors(map, want.x, want.y) or w.is_blocked_tile(want.x, want.y):
			push_error("the annex's site at %s is not open indoor floor" % str(want))
			return false

	# The building half: a fixture template with one loot row, in a fixture district whose profile
	# places nothing of its own, so every site on the map came from the template.
	var loaded: Dictionary = _loot_bearing_template()
	var tree: Dictionary = _tree_with(_fixture_district("district.fixture.carrier", {}, [{"tag": "carrier", "weight": 1}], 1.0))
	tree["buildings/zz_carrier.json"] = loaded
	var carried: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, tree, "district.fixture.carrier")
	var placed: Array = carried.buildings as Array
	if placed.is_empty():
		push_error("the loot-bearing fixture district placed no buildings, so the mechanism proves nothing")
		return false
	# The colony's own rows are excluded: the annex is a loot-bearing template too, and it is stamped
	# on every district the generator sites one on, so counting every site on the map would count it.
	if _profile_sites(carried).size() != placed.size():
		push_error("%d loot-bearing buildings stamped %d sites" % [placed.size(), _profile_sites(carried).size()])
		return false
	var relative: Dictionary = ((loaded["loot"] as Array)[0] as Dictionary)["tile"] as Dictionary
	for record in placed:
		var b: Dictionary = record as Dictionary
		var want2 := Vector2i(int(b["x"]) + int(relative["x"]), int(b["y"]) + int(relative["y"]))
		var hit: bool = false
		for site2 in carried.sites as Array:
			var s2: Dictionary = site2 as Dictionary
			if Vector2i(int(s2["x"]), int(s2["y"])) != want2:
				continue
			hit = true
			if String(s2["table"]) != "medical" or String(s2.get("container", "")) != "medicine cabinet":
				push_error("the stamped site at %s came through as %s" % [str(want2), str(s2)])
				return false
		if not hit:
			push_error("the building stamped at (%d, %d) left no site at %s" % [int(b["x"]), int(b["y"]), str(want2)])
			return false

	# The true negative: the same template with its loot block removed stamps none, so what landed
	# above is the block rather than the stamp inventing sites for every building.
	var anonymous: Dictionary = loaded.duplicate(true)
	anonymous.erase("loot")
	var tree2: Dictionary = _tree_with(_fixture_district("district.fixture.carrier", {}, [{"tag": "carrier", "weight": 1}], 1.0))
	tree2["buildings/zz_carrier.json"] = anonymous
	var bare_map: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, tree2, "district.fixture.carrier")
	if not _profile_sites(bare_map).is_empty():
		push_error("a template with no loot block still stamped %d sites" % _profile_sites(bare_map).size())
		return false

	print("TEMPLATE LOOT OK the annex's %d authored rows stand at their absolute tiles on the booted district, and %d fixture buildings each stamped their own; a template without the block stamps none" % [
		(rows as Array).size(), placed.size(),
	])
	return true


# A district type built here rather than shipped, so a lane can change one field and watch the
# world change. Shipping it would be content nothing plays.
func _fixture_district(id: String, profile: Dictionary, pool: Array = [{"tag": "residential", "weight": 6}, {"tag": "shed", "weight": 4}, {"tag": "civic", "weight": 2}], density: float = 0.6) -> Dictionary:
	var out: Dictionary = {
		"id": id,
		"name": "fixture",
		"type": "fixture",
		"streets": {"blockMin": 24, "blockMax": 40, "streetWidth": 6},
		"connectionPoints": {"north": 1, "south": 1, "east": 1, "west": 1},
		"density": density,
		"pool": pool,
	}
	if not profile.is_empty():
		out["lootProfile"] = profile
	return out


func _tree_with(district: Dictionary) -> Dictionary:
	var tree: Dictionary = _tree().duplicate()
	tree["districts/zz_fixture.json"] = district
	return tree


# A sound 9x7 shell with a south door, carrying one loot row two tiles inside its own corner. No
# shipped building template has a `loot` block -- the district profile covers the pool -- so this
# is what keeps the mechanism from being a schema field nothing exercises.
func _loot_bearing_template() -> Dictionary:
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
	tiles[6 * w + 4] = SimTileMap.Tile.Floor
	return {
		"id": "building.fixture.carrier",
		"name": "nine by seven with a cabinet in it",
		"size": {"w": w, "h": h},
		"tiles": tiles,
		"surfaces": surfaces,
		"indoors": indoors,
		"doors": [{"x": 4, "y": 6}],
		"tags": ["carrier"],
		"weight": 1,
		"loot": [{"tile": {"x": 2, "y": 2}, "table": "medical", "container": "medicine cabinet"}],
	}


# --- 9. the tier is a property of the place ---------------------------------------------------

# Measured on rolls, not on the table being the numbers it was written with.
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


# Seeded, not arbitrary: the same seed scatters the same district, and a different one does not.
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
# second open must yield nothing, forever -- and the prose must say which of the three nothings it
# is, because "there is nothing here", "you emptied this" and "there is still something in it"
# mean completely different things to somebody deciding whether a building is worth the walk.
#
# Since 2026-09-08 a container is also a **grid**: the same `container {w, h, items}` component a
# pack carries, so taking something out of a cupboard is an ordinary `item.move`. That is what
# most of this lane is about -- the roll lands in cells rather than on the floor, a move touching
# it is refused unless somebody is standing at it with it open, and the NPC path still tips
# everything out where the Haul job looks.
func _a_container_yields_once_and_is_empty_after() -> bool:
	var w: Variant = _booted(7788)["world"]
	var actor: int = int(w.player)
	var at: Dictionary = w.components.get_component(actor, "position") as Dictionary

	# Nothing in reach yet: the refusal must name that, not "already-searched".
	var empty_handed: Dictionary = SimContainers.open_nearest(w, actor)
	if bool(empty_handed.get("ok", false)) or String(empty_handed.get("reason", "")) != "nothing-here":
		push_error("with no container in reach the refusal was %s" % str(empty_handed))
		return false

	var box: int = SimContainers.make_container(w, float(at["x"]) + 0.5, float(at["y"]), "cupboard", "residential")
	# The grid comes from content, not from a constant in the module.
	var grid: Variant = w.components.get_component(box, "container")
	if not (grid is Dictionary):
		push_error("a container was stood with no grid in it")
		return false
	var want: Dictionary = SimContainers.grid_for_kind(w, "cupboard")
	if int((grid as Dictionary)["w"]) != int(want["w"]) or int((grid as Dictionary)["h"]) != int(want["h"]):
		push_error("a cupboard opened at %dx%d rather than the %dx%d its content declares" % [int((grid as Dictionary)["w"]), int((grid as Dictionary)["h"]), int(want["w"]), int(want["h"])])
		return false
	if not SimContainers.contents_of(w, box).is_empty():
		push_error("a container held something before anybody opened it; the roll is supposed to happen on the first open")
		return false

	var floor_before: int = _ground_count(w)
	var first: Dictionary = SimContainers.open_nearest(w, actor)
	if not bool(first.get("ok", false)):
		push_error("a container in reach refused the first open: %s" % str(first))
		return false
	var held: Array = SimContainers.contents_of(w, box)
	if held.is_empty():
		push_error("an opened container yielded nothing into its grid")
		return false
	# Into the cells, not onto the floor. A cupboard is six by four, so a residential roll fits.
	if _ground_count(w) != floor_before:
		push_error("opening a container put %d items on the floor; they belong in its grid" % [_ground_count(w) - floor_before])
		return false

	# Depletion, and the whole point: a second open adds nothing and `searched` stays set.
	var count_before: int = held.size()
	var second: Dictionary = SimContainers.open(w, actor, box)
	if not bool(second.get("ok", false)):
		push_error("a half-full container refused a second open: %s" % str(second))
		return false
	if SimContainers.contents_of(w, box).size() != count_before:
		push_error("a second open rolled the table again: %d -> %d" % [count_before, SimContainers.contents_of(w, box).size()])
		return false

	# Reach is real, and it is the true negative for the yield above: an identical container three
	# metres away refuses, so the first open proves proximity rather than existence.
	var far: int = SimContainers.make_container(w, float(at["x"]) + 3.0, float(at["y"]), "cupboard", "residential")
	var reached: Dictionary = SimContainers.open(w, actor, far)
	if bool(reached.get("ok", false)) or String(reached.get("reason", "")) != "out-of-reach":
		push_error("a container 3.0 m away was openable: %s" % str(reached))
		return false

	print("CONTAINER OK a cupboard stands at its content grid, rolls %d items into cells on the first open and none onto the floor, adds nothing on the second, and refuses at 3.0 m" % count_before)
	return true


# Moving what is in it, and the guard that had to come with the grid. `item.move` has never known
# who was moving the item -- safe while every reachable container was on the actor's own body, and
# a hole the moment one of them is across the room.
func _only_somebody_standing_at_it_can_take_from_it() -> bool:
	var w: Variant = _booted(7789)["world"]
	var actor: int = int(w.player)
	var at: Dictionary = w.components.get_component(actor, "position") as Dictionary
	var box: int = SimContainers.make_container(w, float(at["x"]) + 0.5, float(at["y"]), "cupboard", "residential")
	if not bool(SimContainers.open(w, actor, box).get("ok", false)):
		push_error("the fixture container would not open")
		return false
	var inside: Array = SimContainers.contents_of(w, box)
	if inside.is_empty():
		push_error("the fixture container is empty")
		return false
	# The destination cells below are literals, so this fixture needs an item that fits in one.
	# Which item a cupboard rolls first is a property of the residential table and moves whenever
	# content does -- it started rolling a 1x3 haft the day weapons came apart into parts -- and
	# this lane is about who may take from an open box, not about grid geometry.
	var item: int = -1
	for candidate in inside:
		var base: Variant = SimItems.item_base_of(w, int(candidate))
		if not base is Dictionary:
			continue
		var size: Dictionary = SimItems.base_size(base as Dictionary)
		if int(size.get("w", 1)) == 1 and int(size.get("h", 1)) == 1:
			item = int(candidate)
			break
	if item < 0:
		push_error("the fixture cupboard rolled nothing that fits a single cell, so this lane cannot run")
		return false

	# Where it was sitting, so it can be put back exactly there. Its own cell is free by
	# definition; cell (0, 0) belongs to whatever the table rolled first.
	var home: Dictionary = (w.components.get_component(item, "stored") as Dictionary).duplicate()

	# True positive: the actor standing at it, with it open, may take from it through the ordinary
	# command the screen pushes.
	w.commands.push({"type": "item.move", "item": item, "container": actor, "x": 0, "y": 0, "rotated": false})
	w.step()
	if not SimInventory.owns(w, actor, item):
		push_error("somebody standing at an open cupboard could not take something out of it")
		return false

	# True negative, one: put it back, close the box, and the same command does nothing.
	w.commands.push({"type": "item.move", "item": item, "container": box, "x": int(home.get("x", 0)), "y": int(home.get("y", 0)), "rotated": bool(home.get("rotated", false))})
	w.step()
	if SimInventory.owns(w, actor, item):
		push_error("the fixture could not put the item back in the cupboard")
		return false
	SimContainers.close(w, actor)
	w.commands.push({"type": "item.move", "item": item, "container": actor, "x": 1, "y": 0, "rotated": false})
	w.step()
	if SimInventory.owns(w, actor, item):
		push_error("a cupboard nobody has open handed its contents over anyway")
		return false

	# True negative, two: open it, then walk away. `opened_by` closes a box that has gone out of
	# reach, so the move is refused for distance rather than for the flag.
	if not bool(SimContainers.open(w, actor, box).get("ok", false)):
		push_error("the container would not re-open")
		return false
	var pos: Dictionary = w.components.get_component(actor, "position") as Dictionary
	pos["x"] = float(pos["x"]) + 6.0
	w.commands.push({"type": "item.move", "item": item, "container": actor, "x": 1, "y": 0, "rotated": false})
	w.step()
	if SimInventory.owns(w, actor, item):
		push_error("a cupboard six metres away handed its contents over")
		return false
	if SimContainers.opened_by(w, actor) >= 0:
		push_error("walking away from a cupboard left it open")
		return false

	# And a move between two things on the actor's own body is nobody's business but the grid's --
	# the guard must not have broken ordinary inventory handling.
	pos["x"] = float(pos["x"]) - 6.0
	SimContainers.open(w, actor, box)
	w.commands.push({"type": "item.move", "item": item, "container": actor, "x": 0, "y": 0, "rotated": false})
	w.step()
	var pocket: Variant = w.components.get_component(item, "stored")
	if not (pocket is Dictionary) or int((pocket as Dictionary)["container"]) != actor:
		push_error("the item did not come back to the pockets")
		return false
	w.commands.push({"type": "item.move", "item": item, "container": actor, "x": 2, "y": 1, "rotated": false})
	w.step()
	var moved: Dictionary = w.components.get_component(item, "stored") as Dictionary
	if int(moved.get("x", -1)) != 2 or int(moved.get("y", -1)) != 1:
		push_error("a move inside the actor's own pockets was refused by the world-container guard")
		return false

	print("TRANSFER OK standing at an open cupboard takes from it; closed, six metres away, and a pocket-to-pocket move each behave as they should")
	return true


# "Take all that fits" is the word on the transfer window, and *that fits* is the honest half: the
# grid already tells you the axe will not go in, so the verb must not quietly leave you carrying
# it anyway.
func _take_all_takes_what_fits_and_leaves_the_rest() -> bool:
	var w: Variant = _booted(7790)["world"]
	var actor: int = int(w.player)
	var at: Dictionary = w.components.get_component(actor, "position") as Dictionary
	var box: int = SimContainers.make_container(w, float(at["x"]) + 0.5, float(at["y"]), "cupboard", "residential")
	SimContainers.open(w, actor, box)
	# Empty it first, then fill it with things that cannot stack and cannot both fit: pockets are
	# four by two, and a fire axe is two by four. Exactly one axe goes in a pair of pockets.
	#
	# The obvious fixture -- a pile of tins -- proves nothing, because `stow` merges stacks before
	# it looks for space and eleven tins collapse into four cells. That version of this lane went
	# red saying "take all emptied a box of 11 into eight pocket cells", which was the assertion
	# being wrong rather than the verb.
	for existing in SimContainers.contents_of(w, box).duplicate():
		SimInventory.remove_from_container(w, int(existing))
		w.despawn(int(existing))
	for _i in range(3):
		var axe: int = SimItems.spawn_item(w, "item.axe.fire", {"tier": "scavenged"})
		SimInventory.store_anywhere(w, axe, box)
	var in_box: int = SimContainers.contents_of(w, box).size()
	if in_box != 3:
		push_error("the fixture box holds %d axes rather than three" % in_box)
		return false

	w.commands.push({"type": "container.takeAll"})
	w.step()
	var left: int = SimContainers.contents_of(w, box).size()
	var carried: int = SimInventory.carried_items(w, actor).size()
	if carried == 0:
		push_error("take all took nothing")
		return false
	if left == 0:
		push_error("take all put three fire axes into eight pocket cells; *that fits* is half the verb")
		return false
	if left >= in_box:
		push_error("take all moved nothing out of the box: %d -> %d" % [in_box, left])
		return false
	# And the honest half of the honest half: what stayed behind is still there to come back for.
	for item in SimContainers.contents_of(w, box):
		if w.components.get_component(int(item), "position") is Dictionary:
			push_error("something take all left behind ended up on the floor rather than in the box")
			return false
	print("TAKE ALL OK %d fire axes in the box became %d carried and %d left in it, none on the floor" % [in_box, carried, left])
	return true


# The NPC path, unchanged in what it does and rebuilt in how it does it: `search` opens the box
# and tips every cell onto the floor beside it, because that is where `jobs._haul_work` has always
# looked and a colonist who scavenged into a grid nobody carries home would be a silent regression
# in the colony's food supply.
func _an_npc_still_empties_it_onto_the_floor() -> bool:
	var w: Variant = _booted(7791)["world"]
	var actor: int = int(w.player)
	var at: Dictionary = w.components.get_component(actor, "position") as Dictionary
	var box: int = SimContainers.make_container(w, float(at["x"]) + 0.5, float(at["y"]), "cupboard", "residential")
	var floor_before: int = _ground_count(w)
	var searched: Dictionary = SimContainers.search(w, actor, box)
	if not bool(searched.get("ok", false)):
		push_error("search refused: %s" % str(searched))
		return false
	if not SimContainers.contents_of(w, box).is_empty():
		push_error("search left %d things in the grid" % SimContainers.contents_of(w, box).size())
		return false
	var spilt: int = _ground_count(w) - floor_before
	if spilt <= 0:
		push_error("search put nothing on the floor, so Haul has nothing to carry home")
		return false
	if int(searched.get("yielded", 0)) != spilt:
		push_error("search reported %d yielded and %d appeared on the floor" % [int(searched.get("yielded", 0)), spilt])
		return false
	if SimContainers.opened_by(w, actor) >= 0:
		push_error("search left the box open behind the searcher")
		return false
	# And a searched, emptied box is off the E ladder rather than swallowing the key.
	if SimContainers.nearest(w, actor, false, SimContainers.Want.Openable) >= 0:
		push_error("an emptied container is still offered as openable")
		return false
	print("NPC OK search tipped %d onto the floor, left the grid empty and the box closed, and an emptied box leaves the ladder" % spilt)
	return true


# The proof that moving the roll from boot-time to open-time moved nothing else. Two worlds on one
# seed: in the first the table is scattered the way a plain site is at boot, in the second the same
# table is opened out of a container. The yield -- base ids and counts, in order -- has to match,
# because `scatter` is `roll` plus the position writes and nothing more.
#
# This is what keeps a balance claim off this slice: if the draw order had moved, four seeds of the
# harness would say so at 4.5 minutes a run; this says it in a second.
func _opening_draws_exactly_what_scattering_drew() -> bool:
	var a: Variant = _booted(4404)["world"]
	var b: Variant = _booted(4404)["world"]
	var table: Variant = SimLoot.table_for(a, "residential")
	if not (table is Dictionary):
		push_error("no residential table to compare with")
		return false

	var scattered: Array = SimLoot.scatter(a, table as Dictionary, SimLoot.stream(a), 4.5, 4.5)
	var actor: int = int(b.player)
	var at: Dictionary = b.components.get_component(actor, "position") as Dictionary
	var box: int = SimContainers.make_container(b, float(at["x"]) + 0.5, float(at["y"]), "cupboard", "residential")
	SimContainers.open(b, actor, box)
	var opened: Array = SimContainers.contents_of(b, box)

	if scattered.size() != opened.size():
		push_error("the same seed scattered %d and opened %d" % [scattered.size(), opened.size()])
		return false
	if scattered.is_empty():
		push_error("the comparison drew nothing, so it is judging nothing")
		return false
	for i in scattered.size():
		var left: String = _describe(a, int(scattered[i]))
		var right: String = _describe(b, int(opened[i]))
		if left != right:
			push_error("draw %d: scattering gave %s and opening gave %s" % [i, left, right])
			return false
	print("STREAM OK the same seed draws the same %d things whether the table is scattered at boot or opened out of a cupboard" % scattered.size())
	return true


func _describe(w: Variant, item: int) -> String:
	var base: Variant = w.components.get_component(item, "itemBase")
	var stack: Variant = w.components.get_component(item, "stack")
	var tier: Variant = w.components.get_component(item, "itemTier")
	return "%s x%d (%s)" % [
		String((base as Dictionary).get("baseId", "?")) if base is Dictionary else "?",
		int((stack as Dictionary).get("count", 1)) if stack is Dictionary else 1,
		String((tier as Dictionary).get("id", "?")) if tier is Dictionary else "?",
	]


# The three states, and the reason there are three now. A box you opened and did not empty is not
# a box you finished, and until it had a grid the screen had no way to say so.
func _the_prose_has_three_states_and_no_digits() -> bool:
	var w: Variant = _booted(7792)["world"]
	var actor: int = int(w.player)
	var at: Dictionary = w.components.get_component(actor, "position") as Dictionary

	# A body standing near nothing hears nothing. Its own body rather than the container's,
	# because a container stands at its own position and would always find itself in reach.
	var bystander: int = int(w.entities.spawn())
	w.components.set_component(bystander, "position", {"x": 5.5, "y": 5.5})
	if SimContainers.hud_clause(w, bystander) != "":
		push_error("the HUD clause spoke to somebody standing near no container at all")
		return false

	var box: int = SimContainers.make_container(w, float(at["x"]) + 0.5, float(at["y"]), "cupboard", "residential")
	var unopened: String = SimContainers.hud_clause(w, actor)
	SimContainers.open(w, actor, box)
	var half: String = SimContainers.hud_clause(w, actor)
	SimContainers.take_all(w, actor)
	# Anything that would not fit is still in there, so empty it the rest of the way by hand.
	for item in SimContainers.contents_of(w, box).duplicate():
		SimInventory.remove_from_container(w, int(item))
		w.despawn(int(item))
	var done: String = SimContainers.hud_clause(w, actor)

	if unopened.find("worth going through") < 0:
		push_error("an unopened cupboard said \"%s\"" % unopened)
		return false
	if half.find("still something") < 0:
		push_error("a half-full cupboard said \"%s\"" % half)
		return false
	if done.find("already been through") < 0:
		push_error("an emptied cupboard said \"%s\"" % done)
		return false
	if unopened == half or half == done:
		push_error("two of the three states read the same")
		return false
	for line in [unopened, half, done]:
		for ch in line:
			if ch >= "0" and ch <= "9":
				push_error("a container clause carries a digit: \"%s\"" % line)
				return false
	print("PROSE OK three states, each different and digit-free: \"%s\" / \"%s\" / \"%s\"" % [unopened, half, done])
	return true


# Every kind a shipped district or template can name has a size of its own, and a kind nobody has
# sized still opens. The first half is the findability rule `check_m2_gear` applies to items: a
# container the generator can stand and nobody has authored is content that plays wrong rather
# than content that fails loudly.
func _every_kind_a_district_names_has_a_grid() -> bool:
	var sized: Dictionary = {}
	for path in _tree().keys():
		if not String(path).begins_with("containers/"):
			continue
		for entry in _tree()[path] as Array:
			var d: Dictionary = entry as Dictionary
			var kind: String = String(d.get("kind", ""))
			if sized.has(kind):
				push_error("two container entries both name the kind \"%s\"" % kind)
				return false
			sized[kind] = true
	if sized.is_empty():
		push_error("no container sizes in content at all")
		return false

	var named: Dictionary = {}
	for path in _tree().keys():
		var value: Variant = _tree()[path]
		var entries: Array = value as Array if value is Array else [value]
		for entry in entries:
			if entry is Dictionary:
				_collect_container_kinds(entry as Dictionary, named)
	var missing: Array[String] = []
	for kind in named.keys():
		if not sized.has(String(kind)):
			missing.append(String(kind))
	if not missing.is_empty():
		push_error("%d container kinds a district or template names have no size: %s" % [missing.size(), ", ".join(missing)])
		return false

	# And the fallback, which is what keeps naming a new one cheap.
	var w: Variant = _booted(7793)["world"]
	var default_grid: Dictionary = SimContainers.grid_for_kind(w, "a kind nobody has ever written")
	if int(default_grid["w"]) < 1 or int(default_grid["h"]) < 1:
		push_error("an unsized kind resolved a grid of %s" % str(default_grid))
		return false
	if default_grid == SimContainers.grid_for_kind(w, "cupboard"):
		push_error("an unsized kind resolved the same grid as a cupboard, so the content is judging nothing")
		return false
	print("SIZES OK %d kinds sized in content, all %d a district or template names among them, and an unsized kind opens at %dx%d" % [sized.size(), named.size(), int(default_grid["w"]), int(default_grid["h"])])
	return true


# Container kinds live in two shapes: a district profile's `containers` list and a building
# template's `container` string. Walked rather than hard-coded so a third shape shows up as a
# missing size rather than as silence.
func _collect_container_kinds(entry: Dictionary, out: Dictionary) -> void:
	for key in entry.keys():
		var value: Variant = entry[key]
		if String(key) == "containers" and value is Array:
			for kind in value as Array:
				out[String(kind)] = true
		elif String(key) == "container" and value is String:
			out[String(value)] = true
		elif value is Dictionary:
			_collect_container_kinds(value as Dictionary, out)
		elif value is Array:
			for row in value as Array:
				if row is Dictionary:
					_collect_container_kinds(row as Dictionary, out)


# The census, and the reason it is not the site walk again: a booted district must actually STAND
# the containers its manifest declares, and stand exactly as many. A `container` key that
# place_loot ignored would scatter them instead and pass every assertion above -- and a container
# naming a table nobody wrote would empty itself for nothing, which is the worst outcome, because
# the site is spent and the player got zero.
func _every_container_site_stands_in_the_booted_district() -> bool:
	var authored: Dictionary = _authored_locations()
	var lines: Array[String] = []
	var kinds: Dictionary = {}
	for id in _districts():
		var boot: Dictionary = _district_boot(String(id))
		var w: Variant = boot["world"]
		var declared: int = 0
		var manifest: Variant = boot["map"]
		for site in manifest.sites as Array:
			var s: Dictionary = site as Dictionary
			if not s.has("container"):
				continue
			declared += 1
			kinds[String(s["container"])] = true
			if not authored.has(String(s["table"])):
				push_error("%s: container \"%s\" names table %s, which no content entry declares" % [
					String(id), String(s["container"]), String(s["table"]),
				])
				return false
		if declared == 0:
			push_error("SKIP-WORTHY: %s declares no container, so nothing here was judged" % String(id))
			return false
		var standing: int = w.components.query(["searchable", "position"]).size()
		if standing != declared:
			push_error("%s: %d container sites declared but %d standing in a booted district" % [String(id), declared, standing])
			return false
		# Every one of them on its own tile, holding its own table: the census could otherwise be
		# two numbers that happen to agree.
		var by_tile: Dictionary = {}
		for ent in w.components.query(["searchable", "position"]):
			var p: Dictionary = w.components.get_component(int(ent), "position") as Dictionary
			by_tile["%d,%d" % [floori(float(p["x"])), floori(float(p["y"]))]] = w.components.get_component(int(ent), "searchable")
		for site2 in manifest.sites as Array:
			var s2: Dictionary = site2 as Dictionary
			if not s2.has("container"):
				continue
			var key: String = "%d,%d" % [int(s2["x"]), int(s2["y"])]
			var state: Variant = by_tile.get(key)
			if not (state is Dictionary):
				push_error("%s: nothing stands on the container site at %s" % [String(id), key])
				return false
			if String((state as Dictionary).get("kind", "")) != String(s2["container"]) or String((state as Dictionary).get("table", "")) != String(s2["table"]):
				push_error("%s: the container at %s stands as %s, not %s" % [String(id), key, str(state), str(s2)])
				return false
		lines.append("%s %d" % [String(id), declared])

	# The true negative: a scattered site must NOT stand anything, or the census above would be
	# counting every site rather than the containers.
	var scattered: int = 0
	var census_map: Variant = _district_boot(SimWorldgen.DEFAULT_DISTRICT)["map"]
	for site3 in census_map.sites as Array:
		if not (site3 as Dictionary).has("container"):
			scattered += 1
	if scattered == 0:
		push_error("every site in the suburb is a container, so the census cannot tell the two apart")
		return false

	print("CONTAINER SITES OK %s declared and the same number standing, each on its own tile holding its own table (%s); %d scattered sites stand nothing" % [
		", ".join(lines), str(kinds.keys()), scattered,
	])
	return true


func _ground_count(w: Variant) -> int:
	return w.components.query(["itemBase", "position"]).size()
