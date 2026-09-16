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
# What they **do**, which is the piece after the camp and the last of the arc:
#
#   They mill inside `CAMP_RADIUS` of their own building through `SimWalk.step` -- the stepper the
#   raiders and the strangers already share -- and they walk home at dusk. They fight through
#   `npc_combat`, which now takes a third intake by faction name; see `_combatants` there for why
#   that and not a widened `needs` query. One of them wears the strangers slice's
#   `recruit {waiting, stranger: true}` tag, so the E rung recruits them with no second acceptance
#   path. And a camp whose last member dies publishes `settlement.fell`, which this module then
#   reads to retire the camp -- the chronicle was considered for that and refused, because the
#   colony has no way to know (see `_watch_camps`).
#
# What they still do **not** do: forage, build, trade, or answer the colony in any way. A camp is
# people living their own day next to yours.
#
# Siting reads the layout and only the layout (docs/30, "Site the colony on the layout, never on
# the finished map" -- the rule that generalises): `SimWorldgen.far_buildings`, the `map.dormant`
# manifest and `indoor_tiles_of` ask `map.buildings`, `map.tiles`, `map.indoors` and `map.dormant`
# and nothing about vehicles, loot, rubble or props, so switching the dressing off cannot move
# the camp.

const Clock = preload("res://sim/time/clock.gd")
const SimAllegianceRes = preload("res://sim/modules/allegiance.gd")
const SimAptitudesRes = preload("res://sim/modules/aptitudes.gd")
const SimAttentionRes = preload("res://sim/modules/attention_emitter.gd")
const SimDirectorRes = preload("res://sim/modules/director.gd")
const SimHealthRes = preload("res://sim/modules/health.gd")
const SimInventoryRes = preload("res://sim/modules/inventory.gd")
const SimItemsRes = preload("res://sim/modules/items.gd")
const SimPathRes = preload("res://sim/path.gd")
const SimPeopleRes = preload("res://sim/modules/people.gd")
const SimStancesRes = preload("res://sim/stances.gd")
const SimSurvivorsRes = preload("res://sim/modules/survivors.gd")
const SimWalkRes = preload("res://sim/walk.gd")
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

# --- what they do, and the numbers it takes ----------------------------------------------------

## The leash, in metres from the camp's own centre. It is a **guarantee** rather than a target: a
## mill goal is drawn inside it *and* the plan that reaches the goal is thrown away unless every
## waypoint is inside it too (`_plan`), so a body moving between two waypoints inside a disc is
## inside the disc for the whole segment. That is what lets `check_m2_settlers.gd`'s STAYS lane
## assert the radius outright rather than the radius plus a tolerance -- a grid path around a wall
## can bulge well outside a circle both of its endpoints sit in, and a lane written against the
## goal alone would have had to forgive exactly that bulge, which is a lane that cannot fail.
##
## Ten metres because the camp is a house and this is its yard: far enough that three people are
## visibly living there rather than standing in one room, near enough that the whole group is one
## thing a player walks up to. It is deliberately well inside `SimNpcCombat.ENGAGE_METRES`, so a
## settler never mills out of the envelope its own combat intake works in.
const CAMP_RADIUS: float = 10.0

## Walking pace, metres per second. Slower than the stranger's 1.2, which is somebody crossing a
## district to reach you: this is pottering about at home.
const SPEED: float = 0.9

## How long they stand between walks, in ticks -- the shambler's wander shape and its numbers
## (`ticksToTurn`, `int_range(20, 120)`), because that is the cadence this district already reads
## as "a body with nowhere in particular to be" and a second answer to it would be a second
## answer.
const PAUSE_MIN_TICKS: int = 20
const PAUSE_MAX_TICKS: int = 120

## Candidate tiles drawn per turn, and **always all of them**: the loop keeps the first legal draw
## and spends the rest anyway, so a turn costs the stream the same whatever the district is built
## like. A retry loop that stopped early would make the cost of milling a function of how much
## masonry is inside the leash, and two districts would stop being comparable.
const MILL_TRIES: int = 4

## How close something hostile comes before they stop walking and let `npc_combat` have the tick.
## Inside its `ENGAGE_METRES` (20 m, a pacing number for spending a shot) and well outside any
## melee reach, so a settler stands its ground before anything can touch it and never freezes over
## something on the far side of the district.
##
## Distance only, with no sightline: what it gates is *standing still*, not shooting. Somebody who
## hears a thing through a wall and stops what they are doing is not somebody who knows where it
## is, and the turn-and-swing that follows is `npc_combat`'s, which asks `SimRanged.can_target`
## for itself.
const ALARM_METRES: float = 8.0

## Close enough to be home. `SimWalk.step`'s own arrival test is 0.2 m on the last waypoint; this
## is the coarser question "are they back", asked of the tile they sleep on.
const HOME_METRES: float = 1.0

## Where the milling is drawn. Its own named stream (CLAUDE.md): the camp's *placement* is drawn on
## `settlers` at boot, and threading the walk into that stream would make where a camp is a
## function of how long the campaign has run.
const MILL_STREAM: String = "settlersMill"


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
		var body: int = spawn_settler(world, float(tile.x) + 0.5, float(tile.y) + 0.5, rolled, kit, rng)
		mark_settler(world, body, _centre_of(building), tile)
		members.append(body)
	# One of them will come with you, and it is the first body the camp rolled rather than a draw
	# of its own. Deliberately: another draw on this stream would change nothing anybody can see
	# -- the site and the people are already down by here -- and would move what every later save
	# of the `settlers` stream says, which is a real cost for a decision that is not worth
	# randomness. *Which* person is willing still differs per seed, because the first roll does.
	if not members.is_empty():
		mark_willing(world, int(members[0]))
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
		# Into the hand it belongs to before the pack, which is `SimSurvivors._hold_it`'s rule and
		# `SimRaiders`' reason for reusing it: **a knife in a satchel raises no `meleeWeapon`**,
		# and `npc_combat._melee_reach` reads that component and not the pack. Until this line the
		# camp's kit went straight to `stow`, so the whole group stood in a building holding their
		# knives in their bags -- the combat intake below would have found them, faced the
		# shambler and had nothing to swing. It costs no draw, so the camp's stream is untouched.
		if SimSurvivorsRes._hold_it(world, ent, item):
			continue
		if not SimInventoryRes.stow(world, ent, item):
			world.components.set_component(item, "position", {"x": x, "y": y})
	return ent


# The camp's own centre, as a tile: the middle of the building the settlement names. Everything
# about the leash is measured from here rather than from where anybody was spawned, so three
# people who mill in three directions are still one camp.
static func _centre_of(building: Dictionary) -> Vector2i:
	return Vector2i(
		int(building.get("x", 0)) + int(building.get("w", 1)) / 2,
		int(building.get("y", 0)) + int(building.get("h", 1)) / 2,
	)


## Gives an already-spawned settler its day: where the camp is, where their own spot in it is, and
## the walk record `SimWalk.step` owns. Split out from `spawn_camp` the way `SimStrangers.mark` is
## split out from `place`, so a gate can stand one in a building it chose and get exactly the body
## the boot would have produced.
static func mark_settler(world: Variant, ent: int, camp: Vector2i, home: Vector2i) -> int:
	if ent < 0:
		return ent
	# **No `state` field, and its absence is deliberate.** The stranger's component carries one
	# because Hiding/Approaching is a latch nothing else can re-derive. A settler's is a pure
	# function of the clock, asked fresh every tick -- so a stored copy would be a second answer
	# with no reader, which is the socket this milestone keeps finding.
	world.components.set_component(ent, "settler", {
		"campX": camp.x,
		"campY": camp.y,
		# Where they sleep. A tile, not a body id: the bed is not a component here, and a settler
		# who walks home walks to a place rather than to a thing that could be despawned.
		"homeX": home.x,
		"homeY": home.y,
		"goalX": -1,
		"goalY": -1,
		# An Array of `{x, y}` records and a generation stamp, which is what `SimWalk.step` owns.
		# Never a PackedVector2Array and never keyed by anything: components round-trip through
		# JSON (CLAUDE.md's trap list, both halves).
		"path": [],
		"pathGen": -1,
		"ticksToTurn": 0,
	})
	return ent


## Marks one settler as the one who will come with you. It is the strangers slice's tag and
## nothing new: `recruit {waiting: true, stranger: true}` is what `SimRecruits.waiting_in_reach`
## finds and what `SimFortify`'s E rung then hands to `accept`, so there is exactly one acceptance
## path in the tree and exactly one hidden-bite roll on it.
##
## The `stranger` **flag** and not the `stranger` **component**, and the difference is the whole
## of why this is three lines rather than a behaviour. The flag is what `recruits.gd` narrows its
## gate beat and its dawn leave on, so a willing settler neither cancels the day-8 beat nor is
## despawned at dawn for standing somewhere that is not the gate. The component is what
## `SimStrangers._tick_behaviour` steers and what `live_count` counts -- and a settler carrying it
## would have two systems writing one velocity and would give up after `STRANGER_DAYS` by walking
## to the colony's gate to be despawned, which is a person leaving their own camp to vanish.
##
## Nothing tells the player any of this. There is no line, no marker and no field anybody can see:
## what you learn about the camp is what you learn by walking out to it and pressing E on
## somebody, which is clause 4 (information is scarce) exactly as the strangers slice left it.
static func mark_willing(world: Variant, ent: int) -> int:
	if ent < 0:
		return ent
	world.components.set_component(ent, "recruit", {"waiting": true, "stranger": true})
	return ent


# Every living settler, **by faction**, which is a different question from the `settler`
# component below and stays a different question on purpose. This one asks "which side is that
# body on", and its answer stops being yes the instant somebody is recruited -- which is exactly
# what `_one` reads to hand a new colonist over to `jobs.gd` and stop steering them. The component
# is the day-to-day record (the walk, the leash, where home is) and would be a liar as a faction
# marker, because a body keeps its components for a tick after it changes sides.
#
# Sorted, because `components.query` sorts and anything derived from an unsorted scan would not
# survive a save.
#
# Read by `check_m2_settlers.gd`'s BODIES, LEDGER, NO-HEIR, PROSE and RECRUIT lanes -- the
# district's living settlers by faction and the `settlement.members` list the camp wrote are two
# independent answers to "who is in the camp", and BODIES asserts they agree.
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


# --- the day -----------------------------------------------------------------------------------

static func register_module(world: Variant) -> void:
	# "ai"/0, beside `raiders.approach` and `shambler.think`: this decides a velocity and
	# `movement.integrate` (movement/0) spends it on the same tick. It also runs before
	# `npc.combat` at combat/-5, which is what lets that module turn a settler to face a threat
	# without the walk overwriting the facing on the same tick.
	world.systems.register("settlers.day", "ai", 0, func(w: Variant) -> void:
		if bool(w.runOver) if "runOver" in w else false:
			return
		# Two guards and not one, and the difference is a bug this slice wrote and caught before
		# it shipped. Both are asked of `count` rather than `query`, which sorts: a district with
		# no camp pays two integer comparisons a tick and nothing else, and at 64 tiles most seeds
		# have no camp.
		#
		# The camp watch may **not** hang off the body count. A settler who is bitten, dies and
		# turns is despawned by `SimRecruits._turn_with_kit`, and `world.despawn` takes every
		# component with it -- so a camp wiped by *turning* ends with zero `settler` components,
		# and a single `count("settler") < 1: return` would have meant the one camp that was
		# actually overrun was the one camp that never said so.
		if int(w.components.count("settler")) > 0:
			# The threat scan, hoisted out of the per-settler loop. `SimAllegiance.enemies_of`
			# scans and sorts every body in the district; three of those a tick for ten days is a
			# cost the balance tier would feel, and every settler in one camp gets the same
			# answer anyway.
			var threats: Array = _threats(w)
			for e in w.components.query(["settler", "position", "velocity"]):
				_one(w, int(e), threats)
		if int(w.components.count("settlement")) > 0:
			_watch_camps(w)
	)

	# The camp's own retirement, and the reader `settlement.fell` has. Written as a subscription
	# rather than as two lines inside `_watch_camps` for a reason worth stating: the event is the
	# fact, and a flag set behind the bus's back is a second copy of it that can disagree.
	# Anything that later wants to know a camp is gone subscribes here beside this and reads the
	# same fact at the same moment.
	world.events.subscribe({"type": "settlement.fell", "id": "settlers.retire", "handler": func(ev: Dictionary) -> void:
		var s: Variant = world.components.get_component(int(ev.get("entity", -1)), "settlement")
		if s is Dictionary:
			(s as Dictionary)["fell"] = true
	})


# Every living body a settler would fight, as positions. `SimAllegiance.hostile`'s two answers
# written out in one pass: a zombie is everybody's enemy before the factions are consulted (it
# carries no allegiance component at all, so asking `faction_of` would call it a colonist), and a
# human is one when the table says so -- which today is the raiders and nobody else.
static func _threats(world: Variant) -> Array:
	var out: Array = []
	for e in world.components.query(["body", "position"]):
		var ent: int = int(e)
		if world.components.has_component(ent, "corpse"):
			continue
		if not world.components.has_component(ent, "shambler"):
			if not SimAllegianceRes.factions_hostile(SimAllegianceRes.faction_of(world, ent), SimAllegianceRes.SETTLERS):
				continue
		var body: Variant = world.components.get_component(ent, "body")
		if not (body is Dictionary) or not SimHealthRes.is_alive(body as Dictionary):
			continue
		var p: Variant = world.components.get_component(ent, "position")
		if p is Dictionary:
			out.append(Vector2(float((p as Dictionary)["x"]), float((p as Dictionary)["y"])))
	return out


static func _one(world: Variant, ent: int, threats: Array) -> void:
	var sd: Variant = world.components.get_component(ent, "settler")
	if not (sd is Dictionary):
		return
	var s: Dictionary = sd as Dictionary
	# Recruited. `SimRecruits.accept` moved them to the colony's own faction, `jobs.gd` owns this
	# body from the next tick, and the `settler` component has to go with it or this module would
	# keep steering a colonist -- two systems writing one velocity, which is the shape of every AI
	# bug worth having. `SimStrangers._one`'s rule, asked of the faction rather than of the
	# `recruit` tag, because a settler wears that tag from boot.
	if SimAllegianceRes.faction_of(world, ent) != SimAllegianceRes.SETTLERS:
		world.components.remove(ent, "settler")
		return
	var vel: Variant = world.components.get_component(ent, "velocity")
	if not (vel is Dictionary):
		return
	var v: Dictionary = vel as Dictionary
	var body: Variant = world.components.get_component(ent, "body")
	if not (body is Dictionary) or not SimHealthRes.is_alive(body as Dictionary) or world.components.has_component(ent, "corpse"):
		SimWalkRes.halt(v)
		return
	# Held. `shambler.pin` zeroes this velocity at movement/-1 anyway; leaving the path alone here
	# means somebody pulled out of a grab resumes the walk they were on rather than starting over.
	if world.components.has_component(ent, "grabbed"):
		return
	var here: Variant = world.components.get_component(ent, "position")
	if not (here is Dictionary):
		return
	var at := Vector2(float((here as Dictionary)["x"]), float((here as Dictionary)["y"]))
	# Something is coming. Stop walking and let `npc.combat` have the tick: it swings, shoots and
	# pulls people out of grabs from where a body is standing, and a post that walks off mid-swing
	# is not a post. The willing one never gets that far -- `npc_combat._engages` refuses a
	# `recruit` -- so they stand still while the others fight, which is what somebody who has not
	# thrown in with anybody yet does.
	if _within_any(at, threats, ALARM_METRES):
		s["path"] = []
		s["pathGen"] = -1
		SimWalkRes.halt(v)
		return
	var phase: int = int(Clock.phase_of(int(world.tick)))
	if phase == Clock.Phase.Dusk or phase == Clock.Phase.Night:
		_go_home(world, ent, s, v, at)
		return
	_mill(world, ent, s, v)


# Home at dusk. The same stepper over a plan vetted by the same leash: a settler is always inside
# `CAMP_RADIUS` when this starts, so the way home is a route between two points inside the disc,
# and `_plan` refusing it means the only route out of the yard leaves the yard -- in which case
# they stand where they are rather than take it, and try again next tick.
static func _go_home(world: Variant, ent: int, s: Dictionary, v: Dictionary, at: Vector2) -> void:
	var home := Vector2i(int(s.get("homeX", -1)), int(s.get("homeY", -1)))
	if home.x < 0 or home.y < 0:
		SimWalkRes.halt(v)
		return
	if at.distance_to(Vector2(float(home.x) + 0.5, float(home.y) + 0.5)) <= HOME_METRES:
		# In for the night. No path, no draws, no velocity: a camp asleep costs a query.
		s["path"] = []
		s["pathGen"] = -1
		s["goalX"] = -1
		s["goalY"] = -1
		SimWalkRes.halt(v)
		return
	if int(s.get("goalX", -1)) != home.x or int(s.get("goalY", -1)) != home.y or not _fresh(world, s):
		s["goalX"] = home.x
		s["goalY"] = home.y
		if not _plan(world, ent, s, home):
			SimWalkRes.halt(v)
			return
	SimWalkRes.step(world, ent, s, home, SPEED)


# Milling: stand a while, walk somewhere else in the yard, stand again. The shambler's wander
# shape -- an angle and a countdown -- expressed through the shared stepper rather than as a
# second walker, so a settler rounds a corner and opens a door the way a raider and a stranger do.
static func _mill(world: Variant, ent: int, s: Dictionary, v: Dictionary) -> void:
	if _fresh(world, s) and not (s.get("path", []) as Array).is_empty():
		SimWalkRes.step(world, ent, s, Vector2i(int(s.get("goalX", -1)), int(s.get("goalY", -1))), SPEED)
		return
	# Standing: the path is empty because they arrived, or the map moved under the plan.
	SimWalkRes.halt(v)
	if int(s.get("ticksToTurn", 0)) > 0:
		s["ticksToTurn"] = int(s["ticksToTurn"]) - 1
		return
	var rng: Variant = world.rng.stream(MILL_STREAM)
	s["ticksToTurn"] = int(rng.call("int_range", PAUSE_MIN_TICKS, PAUSE_MAX_TICKS))
	var goal: Vector2i = _draw_goal(world, s, rng)
	if goal.x < 0:
		return
	if not _plan(world, ent, s, goal):
		return
	s["goalX"] = goal.x
	s["goalY"] = goal.y


# Somewhere in the yard to stand, or (-1, -1). An angle and a radius rather than a box with the
# corners thrown away, so every draw is inside the disc by construction and the leash only ever
# has to refuse masonry.
static func _draw_goal(world: Variant, s: Dictionary, rng: Variant) -> Vector2i:
	var cx: float = float(int(s.get("campX", 0))) + 0.5
	var cy: float = float(int(s.get("campY", 0))) + 0.5
	var found := Vector2i(-1, -1)
	for _try in MILL_TRIES:
		# Every draw is spent whatever the first one landed on. See MILL_TRIES.
		var angle: float = float(rng.call("float_range", 0.0, PI * 2.0))
		var radius: float = float(rng.call("float_range", 0.0, CAMP_RADIUS))
		if found.x >= 0:
			continue
		var tile := Vector2i(floori(cx + cos(angle) * radius), floori(cy + sin(angle) * radius))
		if not SimPathRes.walkable(world, tile.x, tile.y):
			continue
		found = tile
	return found


# Has the plan in `rec` been made against the map as it stands? `SimWalk.step` asks the same
# question to decide whether to re-plan; this module asks it first, because a re-plan *inside* the
# stepper is one nothing here got to vet against the leash.
static func _fresh(world: Variant, rec: Dictionary) -> bool:
	return int(rec.get("pathGen", -1)) == int(world.mapGeneration)


# Plans the route and keeps it only if the whole of it stays inside the leash. Writes exactly what
# `SimWalk.step` owns -- `path` as an Array of `{x, y}` records and `pathGen` -- so the stepper
# follows this plan rather than making one of its own.
#
# This is what makes `CAMP_RADIUS` a guarantee rather than an intention: a grid path between two
# points inside a circle can bulge outside it to get round a wall, and a body walking the straight
# segment between two waypoints that are both inside a circle never leaves it.
static func _plan(world: Variant, ent: int, rec: Dictionary, goal: Vector2i) -> bool:
	var pos: Variant = world.components.get_component(ent, "position")
	if not (pos is Dictionary):
		return false
	var here := Vector2i(floori(float((pos as Dictionary)["x"])), floori(float((pos as Dictionary)["y"])))
	var found: Array[Vector2i] = SimPathRes.find(world, here, goal)
	if found.is_empty():
		return false
	var centre := Vector2(float(int(rec.get("campX", 0))) + 0.5, float(int(rec.get("campY", 0))) + 0.5)
	# A plain Array, never a Packed one: a packed array mutated through a Dictionary appends to a
	# copy and silently does nothing (CLAUDE.md's first trap).
	var path: Array = []
	for step in found:
		if centre.distance_to(Vector2(float(step.x) + 0.5, float(step.y) + 0.5)) > CAMP_RADIUS:
			return false
		path.append({"x": step.x, "y": step.y})
	rec["path"] = path
	rec["pathGen"] = int(world.mapGeneration)
	return true


static func _within_any(at: Vector2, points: Array, metres: float) -> bool:
	var limit_sq: float = metres * metres
	for p in points:
		if at.distance_squared_to(p as Vector2) <= limit_sq:
			return true
	return false


# A camp whose last member has died says so, once.
#
# **What reads it, and what deliberately does not.** The reader is this module's own retirement of
# the camp (the subscription in `register_module`), which is what stops the scan below finding the
# same empty camp on every remaining tick of the campaign. The chronicle was the obvious second
# reader and is refused: it is "what happened to the colony, as the screen can say it", and a camp
# two hundred metres away being overrun is not something anybody in the colony saw. A line about it
# would hand the player a fact nobody has -- clause 4, and the same refusal `SimStrangers._give_up`
# already makes over a stranger who walks away. What tells you the camp fell is walking out there.
#
# "The last member dies" is meant literally. A member who was *recruited* is alive and walking
# around your colony, so a camp does not fall because you saved somebody out of it. A member who
# died and turned was despawned by `_turn_with_kit` and the shambler standing there is a different
# entity, so nothing of theirs is found and they read as gone -- which is what they are.
static func _watch_camps(world: Variant) -> void:
	for e in world.components.query(["settlement"]):
		var ent: int = int(e)
		var sd: Variant = world.components.get_component(ent, "settlement")
		if not (sd is Dictionary):
			continue
		var s: Dictionary = sd as Dictionary
		if bool(s.get("fell", false)):
			continue
		var members: Array = s.get("members", []) as Array
		if members.is_empty():
			continue
		var standing: int = 0
		for m in members:
			# The ids come back from a save as floats, which is why this takes `int()`.
			var member: int = int(m)
			if world.components.has_component(member, "corpse"):
				continue
			var body: Variant = world.components.get_component(member, "body")
			if body is Dictionary and SimHealthRes.is_alive(body as Dictionary):
				standing += 1
		if standing > 0:
			continue
		# `entity` and nothing else: a payload carries what a reader reads, and the one reader
		# resolves the settlement from the id. A rect on the event would be a second copy of a
		# component the handler already has in its hand.
		world.events.publish({"type": "settlement.fell", "entity": ent})
