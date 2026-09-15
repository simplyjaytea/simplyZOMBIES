class_name SimSettlers
extends RefCounted

# A small group of survivors living somewhere else in the district: not the colony, not hostile
# to it. The third faction has had a seam since the allegiance slice and no bodies at all; this
# is the bodies.
#
# What a settler *is*, exactly, and why each half:
#
#   A raider's faction handling with a survivor's identity. `SimRaiders.spawn` is the precedent
#   for a non-colony human body -- a `body`, stamina, an inventory, an attention emitter,
#   aptitudes, eyes, sightings and a `lootKit` -- and `SimSurvivors.spawn_unique` is the
#   precedent for a named person. A settler takes the first list wholesale and adds the one
#   thing a raider is deliberately denied: an `identity`, so `SimSurvivors.person_clause` has
#   somebody to describe and the camp is people rather than a spawn count.
#
#   And **no `needs`, no `jobPriorities`**, which is not an omission but the whole of how the
#   camp stays out of the colony's books. Three readers, each checked rather than assumed:
#   `check_m2_balance.gd`'s `_survivors_alive` counts `needs` + `body`, so a settler cannot
#   raise the colonist count; `jobs.gd` queries `jobPriorities` + `identity`, so the scheduler
#   and the work panel never see one; and `npc_combat.gd`'s intake is `needs` or `raider`, so a
#   settler does not swing at anything.
#
#   Succession is the fourth, and it is the allegiance slice's `is_colony` rather than anything
#   here: a settler carries an `identity` and would otherwise have been a perfectly good heir
#   standing 0.5 m from a dying player. `check_m2_settlers.gd`'s NO-HEIR lane asserts the real
#   bodies against that filter, which the allegiance gate could only do with hand-built ones.
#
# What this slice deliberately does **not** build: any behaviour at all. Nothing mills, nothing
# returns at dusk, nothing fights back, nothing can be recruited. A camp today is bodies standing
# in a building -- they breathe into the attention field, a shambler will come for them because
# `SimAllegiance.is_person` reads their `identity`, and they will not raise a hand. That is
# docs/23's next piece and it is not smuggled in here.
#
# Siting reads the layout and only the layout (docs/30, "Site the colony on the layout, never on
# the finished map" -- the rule that generalises): `SimWorldgen.far_buildings`, the `map.dormant`
# manifest and `indoor_tiles_of` ask `map.buildings`, `map.tiles`, `map.indoors` and `map.dormant`
# and nothing about vehicles, loot, rubble or props, so switching the dressing off cannot move
# the camp.

const SimAllegianceRes = preload("res://sim/modules/allegiance.gd")
const SimAptitudesRes = preload("res://sim/modules/aptitudes.gd")
const SimAttentionRes = preload("res://sim/modules/attention_emitter.gd")
const SimDirectorRes = preload("res://sim/modules/director.gd")
const SimHealthRes = preload("res://sim/modules/health.gd")
const SimInventoryRes = preload("res://sim/modules/inventory.gd")
const SimItemsRes = preload("res://sim/modules/items.gd")
const SimPeopleRes = preload("res://sim/modules/people.gd")
const SimStancesRes = preload("res://sim/stances.gd")
const SimSurvivorsRes = preload("res://sim/modules/survivors.gd")
const SimWorldgenRes = preload("res://sim/map/worldgen.gd")

# The generator block, found by id the way the survivor and raider pools are. `content/colony/`
# has no schema and no validator type (`platform/content_validator.gd` does not list it) and the
# frozen TypeScript oracle's CONTENT_TYPES never reaches it either, so `check_m2_settlers.gd`'s
# CONTENT lane is the only thing in the tree that will ever judge this file's shape.
const POOL_ID: String = "colony.generator.settlers"

# Two streams, split the way `SimPeople.roll` requires and every other caller of it already does
# (`recruits`/`recruitLook`, `raiderRoll`/`raiderLook`): the identity draw on one, the age and the
# visual look on a second, so a later draw threaded into either never lands a third on a different
# byte. The site is drawn on `SETTLERS` too -- before any body -- so the camp's address is a
# function of the map and the seed and not of how many people ended up in it.
const STREAM: String = "settlers"
const LOOK_STREAM: String = "settlersLook"

# How many, when the content declares nothing. Three, matching the colony's own boot size, so the
# group reads as people living the way you are rather than as a rival power.
#
# **This number was moved to two and then moved back, and the round trip is worth recording.** At
# three the district went over its own zombie budget on seed 31337 -- `check_m2_balance.gd`'s
# `over_cap` invariant red for 76 ticks, and a throwaway driver put the arithmetic on it:
# `peak=33 cap=32 boot_zeds=23 placed=6 turned=4`. A settler who is bitten, dies and turns is a
# body `SimDirector.LIVE_CAP` never placed and cannot refuse, so cutting the count to two fixed
# the number. It was fixing a symptom. The *cause* was the third filter in `site` below: the camp
# was being put down in a house the generator had already put a body to sleep in, `check_m2_dormant`
# went red for the same reason a lane later, and once the camp stopped sharing a house its people
# stopped dying -- `turned` drops to 0 on that seed and the peaks read 27 / 27 / 28 / 30 against a
# cap of 32 at **three** settlers. So three came back. What has **not** been fixed, and is not
# this slice's to fix: nothing anywhere reconciles a turned body against the director's budget,
# so a colony that loses several people to infection in one night can still push the district over
# its own cap. Two slices in a row have now paid for that.
const DEFAULT_COUNT: int = 3

# How far from home, when the content declares nothing -- and this is `SimDirector.GATE_EXCLUSION`
# by name rather than a second number, for the reason `SimWorldgen.far_buildings`' own comment
# gives: "a second copy of 'far from home' is a second answer". The plan's first cut was 96 m and
# it was measured before it was taken; see docs/30, "The settlers' camp", for the measurement and
# the argument.
const DEFAULT_MIN_METRES: float = SimDirectorRes.GATE_EXCLUSION

# The rows a settler's pack falls back to when the content declares no kit at all. Deliberately
# the humblest things in the tree: a settler who cannot fight yet is not made more interesting by
# a rifle, and this is a floor under the spawner rather than the authored kit.
const FALLBACK_KIT: Array = ["item.bandage.cloth"]


# The generator block, or the empty Dictionary. An unknown id is survivable rather than fatal --
# the same rule `SimRaiders.roll_person` follows -- so a content tree with no settlers block in it
# boots a camp of three people with a bandage each instead of crashing a campaign. The gate is
# what refuses that, not the sim.
static func pool(world: Variant) -> Dictionary:
	return SimPeopleRes.pool(world, POOL_ID)


static func count_of(block: Dictionary) -> int:
	return maxi(0, int(block.get("count", DEFAULT_COUNT)))


static func min_metres_of(block: Dictionary) -> float:
	return maxf(0.0, float(block.get("minMetres", DEFAULT_MIN_METRES)))


static func kit_of(block: Dictionary) -> Array:
	var kit: Variant = block.get("kit", null)
	if kit is Array:
		return (kit as Array).duplicate(true)
	return FALLBACK_KIT.duplicate(true)


# The building indices `map.dormant` already has a body asleep in. The manifest is layout -- the
# generator writes it in the same pass that places the buildings, before any entity exists -- so
# reading it here keeps the siting inside docs/30's "reads the layout, and only the layout".
static func _buildings_with_a_sleeper(map: Variant) -> Dictionary:
	var out: Dictionary = {}
	var records: Variant = map.get("dormant")
	if not (records is Array):
		return out
	for rec in records as Array:
		if rec is Dictionary and (rec as Dictionary).has("building"):
			out[int((rec as Dictionary)["building"])] = true
	return out


# Which building the camp is in, as an **index into `map.buildings`**, or -1 when the district has
# nowhere that qualifies. An index rather than the record, for `far_buildings`' own reason:
# `Array.find()` on Dictionaries matches by value, so a caller handed one of two value-identical
# house records back could not ask the map which it was holding (CLAUDE.md's erase/find trap).
#
# Three filters, and the third was found by a gate rather than reasoned out in advance:
#
#   * **far enough from home** -- `far_buildings`, the one answer to that question in the tree.
#   * **somewhere to stand** -- a building with no open indoor floor is skipped rather than
#     chosen-and-abandoned, so the answer is always a building somebody can actually stand in.
#   * **nobody already asleep in it.** The dormant pass draws from the *same* `far_buildings` list
#     at the *same* `GATE_EXCLUSION`, so the two passes compete for one set of houses, and a camp
#     put down on top of a sleeping body is a group of people breathing beside something that
#     wakes on scent. That is not a theory: `check_m2_dormant.gd`'s ASLEEP lane boots seed 31337
#     at 64 and requires every sleeper to still be asleep 200 ticks later, and it went **red** the
#     first time the camp was allowed to share a house -- "body 46 woke on its own after 200 ticks
#     with nothing near it". The other gate was right and this one was wrong, so the siting moved,
#     not the assertion. It also reads as the rule people would actually follow: you do not make
#     camp in the room with the body in it.
static func site(map: Variant, min_metres: float, rng: Variant) -> int:
	if map == null:
		return -1
	var far: Array[int] = SimWorldgenRes.far_buildings(map, min_metres)
	var asleep: Dictionary = _buildings_with_a_sleeper(map)
	var usable: Array[int] = []
	for index in far:
		if asleep.has(int(index)):
			continue
		var building: Dictionary = (map.buildings as Array)[index] as Dictionary
		if SimWorldgenRes.indoor_tiles_of(map, building).is_empty():
			continue
		usable.append(index)
	if usable.is_empty():
		return -1
	return int(usable[int(rng.call("int_range", 0, usable.size() - 1))])


# The camp, at boot. Returns the settlement entity, or -1 when this district has nowhere for one.
#
# Drawn in one order, always: the site first, then one `SimPeople.roll` per member, then the kit
# rows. A district with no qualifying building costs **no draws at all** -- the early return is
# before the stream is ever asked for -- which is the rule `SimWorldgen._dormant` follows for the
# same reason: a map that legally holds nobody must generate exactly the campaign it always did.
static func spawn_camp(world: Variant, map: Variant) -> int:
	if world == null or map == null:
		return -1
	var block: Dictionary = pool(world)
	var wanted: int = count_of(block)
	if wanted < 1:
		return -1
	var rng: Variant = world.rng.stream(STREAM)
	var look_rng: Variant = world.rng.stream(LOOK_STREAM)
	var index: int = site(map, min_metres_of(block), rng)
	if index < 0:
		return -1
	var building: Dictionary = (map.buildings as Array)[index] as Dictionary
	var floors: Array = SimWorldgenRes.indoor_tiles_of(map, building)
	var kit: Array = kit_of(block)
	# An Array of ids, never a Dictionary keyed by one: components round-trip through JSON and
	# JSON has no integer keys, so `{entity: record}` comes back with String keys and the first
	# lookup after a load misses silently (CLAUDE.md's save trap; `sightings.gd` is the
	# precedent). The ids come back as floats, which is why every reader here takes `int()`.
	var members: Array = []
	var ent: int = int(world.entities.spawn())
	for _member in wanted:
		# One draw a body, exactly, whatever the floor plan is -- so how much randomness a camp
		# costs is a function of its declared count and nothing else, and a building template
		# edited to hold one more room cannot shift the stream under everything spawned
		# afterwards. Two members may land on the same tile and that is deliberate rather than
		# tolerated: bodies overlap freely everywhere else in this sim, and walking the pick
		# forward to a free tile (`SimWorldgen._take_tile`'s rule, which the dormant bodies need
		# because a corpse per tile is what makes a house feel occupied) would make the camp's
		# size a function of how many rooms the generator happened to give it.
		var tile: Vector2i = floors[int(rng.call("int_range", 0, floors.size() - 1))] as Vector2i
		var rolled: Dictionary = SimPeopleRes.roll(rng, look_rng, SimPeopleRes.pool(world, SimPeopleRes.SURVIVORS_POOL_ID))
		members.append(spawn_settler(world, float(tile.x) + 0.5, float(tile.y) + 0.5, rolled, kit, rng))
	world.components.set_component(ent, "settlement", {
		"x": int(building.get("x", 0)),
		"y": int(building.get("y", 0)),
		"w": int(building.get("w", 0)),
		"h": int(building.get("h", 0)),
		"building": index,
		"members": members,
	})
	return ent


# One settler. The order of the component writes is `SimRaiders.spawn`'s, deliberately, so the two
# non-colony bodies in the tree are assembled the same way and a reader comparing them is reading
# one shape twice.
static func spawn_settler(world: Variant, x: float, y: float, rolled: Dictionary, kit: Array, rng: Variant) -> int:
	var ent: int = int(world.entities.spawn())
	world.components.set_component(ent, "position", {"x": x, "y": y})
	world.components.set_component(ent, "velocity", {"dx": 0.0, "dy": 0.0})
	world.components.set_component(ent, "facing", {"radians": 0.0})
	world.components.set_component(ent, "posture", SimStancesRes.make_posture(SimStancesRes.Stance.Walk))
	# Named people with prose, which is the one place a settler differs from a raider. The field
	# list is `SimRecruits.spawn_generated`'s exactly, because `SimSurvivors.person_clause` reads
	# `name`, `backstoryId`, `age` and `features` and a settler with a shorter record would render
	# a thinner sentence for no reason anybody could see.
	world.components.set_component(ent, "identity", {
		"id": "survivor.settler." + String(rolled.get("name", "x")).to_lower().replace(" ", "_"),
		"name": String(rolled.get("name", "Someone")),
		"unique": false,
		"traits": (rolled.get("traits", []) as Array).duplicate(),
		"backstory": String(rolled.get("backstory", "")),
		"backstoryId": String(rolled.get("backstoryId", "")),
		"age": int(rolled.get("age", 0)),
		"look": String(rolled.get("look", "")),
		"features": (rolled.get("features", []) as Array).duplicate(),
	})
	SimAllegianceRes.attach(world, ent, SimAllegianceRes.SETTLERS)
	SimHealthRes.make_survivor_body(world, ent)
	SimHealthRes.make_stamina(world, ent)
	SimInventoryRes.make_inventory(world, ent)
	# The same emitter a colonist has: footsteps into the noise field, body scent into the scent
	# field, both read by a shambler gradient with nothing about factions in it. This is the whole
	# of "a camp is three more bodies the district can smell", and it is the reason this slice
	# owes a balance measurement at all.
	SimAttentionRes.make_emitter(world, ent)
	SimAptitudesRes.apply(world, ent, rolled.get("aptitudes", {}))
	# Deliberately NOT `SimNeeds.attach` and NOT `SimJobs.attach`. See the file header: those two
	# components are the whole of how the ledger, the scheduler and the work panel stay honest.
	SimSurvivorsRes.give_eyes(world, ent)
	world.components.set_component(ent, "lootKit", {})
	for row in kit:
		# A kit row is a bare id, or `{item, count, chance}` -- `SimRaiders.spawn`'s vocabulary,
		# and a row that declares a chance spends exactly one draw whatever the odds are, so how
		# much randomness a camp costs is a function of the content's shape and not of its
		# numbers.
		var item_id: String = ""
		var count: int = 1
		if row is Dictionary:
			item_id = String((row as Dictionary).get("item", ""))
			count = maxi(1, int((row as Dictionary).get("count", 1)))
			if (row as Dictionary).has("chance"):
				if not bool(rng.call("bool_chance", float((row as Dictionary)["chance"]))):
					continue
		else:
			item_id = String(row)
		if item_id.is_empty():
			continue
		var item: int = SimItemsRes.spawn_item(world, item_id, {"tier": "scavenged", "count": count})
		if not SimInventoryRes.stow(world, ent, item):
			world.components.set_component(item, "position", {"x": x, "y": y})
	return ent


# Every living settler, by faction rather than by a marker component -- there is no `settler`
# component and there deliberately is not going to be one, because "which side are you on" already
# has exactly one answer in this tree and a second marker would be a second answer that drifts.
# Sorted, because `components.query` sorts and anything derived from an unsorted scan would not
# survive a save.
#
# **Its only reader today is `check_m2_settlers.gd`, and that is said out loud rather than left to
# be found.** It is not a decoration on a gate: the district's living settlers by faction and the
# `settlement.members` list the camp wrote are two independent answers to "who is in the camp",
# and BODIES asserts they agree -- a settlement whose list had drifted from the bodies standing in
# it would otherwise be invisible. The behaviour slice is what gives it a reader in the sim.
static func members_of(world: Variant) -> Array[int]:
	var out: Array[int] = []
	for e in world.components.query(["identity", "body"]):
		var ent: int = int(e)
		if world.components.has_component(ent, "corpse"):
			continue
		if SimAllegianceRes.faction_of(world, ent) != SimAllegianceRes.SETTLERS:
			continue
		out.append(ent)
	return out
