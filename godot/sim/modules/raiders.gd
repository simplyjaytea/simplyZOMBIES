class_name SimRaiders
extends RefCounted

# A hostile band of *people*, walking in from the edge of the district towards your gate.
#
# The point of the slice is that almost none of this file is new mechanism. A raider is a human
# body with a weapon in its hand and `allegiance.faction = "raiders"` on it, and everything that
# then happens to them is the machinery the colony already had:
#
#   * `melee.gd` / `ranged.gd` resolve against whatever body is in the cone and have never asked
#     who it belongs to, so a raider swinging at a colonist and a colonist swinging at a raider
#     are the same code path that was already there.
#   * `npc_combat.gd` is the intake for both sides. It picks a target through
#     `SimAllegiance.enemies_of` now instead of a hardcoded shambler query, which is the only
#     change hostility actually required.
#   * `wounds.gd`, `health.gd` and `treatment.gd` apply because a raider carries the same
#     `body` + `injuries` a survivor does -- they bleed, they can be bandaged, they die.
#   * `shambler.gd` chases them because `SimAllegiance.is_person` says a raider is prey, and the
#     attention field already carries them because they emit the same noise and scent a
#     colonist does.
#
# What *is* new is exactly two things: an archetype declared as content, and a walk towards the
# gate. Deliberately nothing else -- no dialogue, no faction standing. docs/18's factions are
# Milestone 3 and this must not pre-empt them.
#
# Since the roles slice a band also has something to *want*. An archetype declares a `role` from a
# closed enum and `_approach` matches on it: a `fighter` is the walk above, unchanged; a `lookout`
# halts LOOKOUT_METRES short and turns the band for home at the first loss; a `looter` walks at the
# colony's stores instead of its gate, takes LOOT_TAKE things off the floor and leaves with them.
# That is docs/18's "target stores first, people second, and will withdraw once loaded" -- still
# not a faction, still no dialogue, and no standing.
#
# Since the crossing slice a band also has somewhere else to be. The director's dawn draw can send
# one *through* the district instead of at it: an objective, a far edge, and a fight only with what
# walks into `HALT_METRES` of its line. Two fields on the component carry all of it and every other
# line in this file is shared with the raid -- see the block at `OBJECTIVE_SITE` below.
#
# Since the individuals slice each body is also a *person*: `raider.person` carries the name, age,
# features, look and backstory `SimPeople.roll` drew, the archetype's aptitudes may be declared as
# ranges and its kit rows may carry odds, so two scavengers are two men rather than one man twice.
# It is a record on the `raider` component and never an `identity` component -- see the note where
# it is written, below.
#
# What a raider is kept out of, on purpose, and how: no `needs` component, so needs.gd never
# ticks them, `jobs.gd` never routes them (it queries `jobPriorities` + `identity`, and they
# have neither), the stockpile never counts them, `recruits.gd` never converts them, and -- the
# one that would have been silent and wrong -- `check_m2_balance.gd`'s `_survivors_alive` counts
# `needs` + `body`, so a raid could otherwise have *raised* the colony's survivor count.
#
# The one colonist component a raider *does* carry, since the owner's 2026-09-14 decision that
# there is one skill web for everybody (docs/30, "One web, and the captives"): `skillWeb`. The
# archetype's `skills` are granted at spawn by `SimSkills.endow`, so a gunhand's steadier breath
# reads through the same `ranged_accuracy` resolve a colonist's does and the band is harder in the
# way the content says -- and when one is captured, the web they arrived with is the web they
# keep. It is safe on the ledger above because nothing that counts, feeds, employs or promotes
# reads `skillWeb` alone: `_drift_all` queries it *with* `jobPriorities`, the web gate's FOCUS
# lane queries it with `identity`, and the harness counts `needs` + `body`. Raiders earn like
# anybody else (a shambler put down pays Melee or Ranged), and with no focus row they spend
# along the Auto path; the alternative was a `raider` read inside skills.gd, which is the special
# case the decision exists to remove.

const SimAllegianceRes = preload("res://sim/modules/allegiance.gd")
const SimAptitudesRes = preload("res://sim/modules/aptitudes.gd")
const SimAttentionRes = preload("res://sim/modules/attention_emitter.gd")
const SimHealthRes = preload("res://sim/modules/health.gd")
const SimHomeRes = preload("res://sim/home.gd")
const SimInventoryRes = preload("res://sim/modules/inventory.gd")
const SimItemsRes = preload("res://sim/modules/items.gd")
const SimNeedsRes = preload("res://sim/modules/needs.gd")
const SimPeopleRes = preload("res://sim/modules/people.gd")
const SimSightingsRes = preload("res://sim/modules/sightings.gd")
const SimSkillsRes = preload("res://sim/modules/skills.gd")
const SimStancesRes = preload("res://sim/stances.gd")
const SimVisibilityRes = preload("res://sim/vision/visibility.gd")
const SimWalkRes = preload("res://sim/walk.gd")

# Content lives in `godot/content/raiders/`, one entry per file, against
# `content/schemas/raider.schema.json`. Its own directory rather than a tagged survivor entry,
# for three reasons that each cost something otherwise: the survivor schema forbids unknown
# top-level keys and the validator enforces `aptitudes` summing to 15 on that type; the frozen
# TypeScript oracle reads a *fixed* list of content directories (`CONTENT_TYPES`), so a new
# directory is invisible to it and a new key under `survivors/` would not be; and
# `SimSurvivors.list_uniques` boots everything under `survivors/` whose id starts with
# `survivor.unique.`, which is not a list a raider belongs on. `content/loot/` is the precedent
# for a Godot-only content type, down to registering the id in `content_validator.gd`.
const CONTENT_TYPE: String = "raider"

# Who the body is, as opposed to which archetype it came off. The generator block lives in
# `content/colony/raider_looks.json` and is found by id, exactly the way the survivors' block is
# (`SimPeople.pool`) -- `content/colony/` has no schema and no validator type, so the id is the
# only handle and `check_m2_raiders.gd` is the only thing that checks its shape.
const PEOPLE_POOL_ID: String = "colony.generator.raiders"

# Two streams, and neither of them is `"raid"`. The director draws the night, the side, the band
# size and each member's archetype off `"raid"` (SimDirector.RAID_STREAM); every measured band in
# the record depends on that byte sequence, and a new draw threaded into it would move every
# campaign's raids. So who a raider *is* is drawn here instead: `raiderRoll` carries the person
# (name, story, features) and then the kit and the aptitude jitter, `raiderLook` the age and the
# look -- that split is `SimPeople.roll`'s own and is not ours to reorder, since
# `check_m2_people.gd` pins the survivor roll's bytes through the same function.
# `check_m2_raiders.gd`'s STREAMS lane holds `"raid"`'s state after `_emit_band` against a
# literal taken from the pre-individuals code.
const ROLL_STREAM: String = "raiderRoll"
const LOOK_STREAM: String = "raiderLook"

# How fast a raider walks in, in metres per second, when their entry declares nothing. Between a
# shambler's 0.8 and a colonist hurrying to a job (jobs.gd's 2.1): a band on its way somewhere,
# not a charge.
const DEFAULT_SPEED: float = 1.5

# How close an enemy comes before a raider stops walking and starts fighting. A swing has a
# wind-up, so a raider who kept walking would cross a defender's reach and be past them before
# the blow landed -- measured as "0 connects" the first time this ran without it. Just outside
# the longest melee reach in the content tree (the spear's 2.4 m) so a raider carrying anything
# halts at a distance its own weapon can work at, and `npc_combat.gd` -- which never sets a
# velocity, by design -- does the rest.
const HALT_METRES: float = 2.6
# A band that has nothing to fight goes home (the playable-state group's eleventh piece): at
# its objective with no enemy in HALT_METRES for WITHDRAW_AFTER_TICKS it walks back to where it
# came in and leaves, and a band cut below half the size it arrived at leaves at once. Before
# this a surviving band stood at the gate for the rest of the run. `raid.withdrew` per body;
# `check_m2_raiders.gd` WITHDRAW.
const WITHDRAW_AFTER_TICKS: int = 6000

# What the approach walks at. Read off the map rather than computed: `gate_a` is where a colony
# is entered from, and the annex centre is the honest fallback for a district nobody stamped.
const ARRIVE_METRES: float = 1.2

# What a band member came to do. docs/18's raids are "a business": they "target stores first,
# people second, and will withdraw once loaded" and "retreat when losses outweigh the haul". Until
# this every raider did the one thing -- walk at the gate and fight until the clock ran out -- so
# the business half of that sentence was a design note with no reader.
#
# A role is a **closed enum**, declared per archetype and never a free string. The schema's own
# `role` enum is the first lock (the shallow validator does check a top-level enum), `spawn`'s
# refusal below is the second, and `check_m2_raiders.gd` ROLE-READ is the third -- because the
# quiet failure this has to be impossible is an archetype declaring `quartermaster` and getting a
# fighter, which is the dead socket in its most expensive shape: content that reads as shipped
# behaviour and is not.
const ROLE_FIGHTER: String = "fighter"
const ROLE_LOOKOUT: String = "lookout"
const ROLE_LOOTER: String = "looter"
const ROLES: Array[String] = [ROLE_FIGHTER, ROLE_LOOKOUT, ROLE_LOOTER]

# Where a lookout stops. A watcher on the treeline (docs/18's own announcement of a raid) rather
# than a body in the fight: far enough outside the longest reach in the tree that no halt, no
# wall-following detour and no arrival tolerance could produce it by accident, and close enough
# that they are still standing in the district with everything that implies -- a zombie sees them,
# the colony can shoot at them, and they emit the same noise and scent anyone else does.
const LOOKOUT_METRES: float = 12.0

# How much a looter carries away. The plan's first cut, and the owner's to move: three things off
# the floor of your stores. Not three *stacks* and not a pack's worth -- three item entities, which
# on a stockpile of tins and bottles is a night's meals rather than a pantry.
const LOOT_TAKE: int = 3

# --- a band passing through --------------------------------------------------------------------
#
# The other thing a band can be, since the crossing slice: not coming for you. `SimDirector`'s
# dawn draw (`_draw_roam`) stamps an objective and an exit on the bodies it places, and those two
# fields are the whole difference between a raid and a crossing in this file. Everything else --
# the walk, the halt, the fight, the withdrawal clock, `raid.withdrew` -- is reused exactly as it
# stands, which is the point: a crossing is an Encounter built out of a raid's machinery, not a
# second kind of raider with its own code path.
#
# What the two fields do, in one place, because they are read four lines apart in four different
# methods below:
#
#   * `objective` `{kind: "site", x, y}` replaces the gate as the thing `_objective` walks at, and
#     replaces the colony's stores as the thing a looter reads (`_worth_taking`).
#   * `exitX`/`exitY` replaces the entry tile as the thing a withdrawal walks back to
#     (`_leave_tile`), so a band that is done keeps going instead of turning round.
#
# **No `SAVE_VERSION` bump**, and the rule is `kernel/serialize.gd`'s own: a bump is for a save
# whose restored world would be quietly *wrong*. A v31 save has no crossings in it -- the draw did
# not exist -- so every raider in one is a raid band, and a raid band is exactly what these
# defaults describe: no objective, no exit, walk at the gate, leave the way you came. The keys
# being absent restores the right behaviour rather than a plausible wrong one. `camp.gd` states
# the same rule for the case one step further out.
const OBJECTIVE_SITE: String = "site"

# How far from a site's own tile a thing still counts as lying *at* that site. `SimBoot.place_loot`
# scatters a table along a row at `SimLoot.SPREAD_METRES` (0.4 m) a step, so a table of eight is
# about three metres wide; four covers it with room for a body standing at the end of the row, and
# `SimInventory.PICKUP_REACH` (1.5 m) is the real limit on what a looter can actually reach anyway.
# It exists so the predicate is about the *place* rather than about arm's length: a crossing looter
# takes what is at the pharmacy, not whatever it happens to walk past on the way.
const SITE_REACH: float = 4.0


static func content_entry(world: Variant, id: String) -> Variant:
	if world == null or world.content == null:
		return null
	var c: Variant = world.content
	if c is Object and (c as Object).has_method("get"):
		return (c as Object).call("get", CONTENT_TYPE, id)
	if not (c is Dictionary):
		return null
	for path in (c as Dictionary).keys():
		if not String(path).begins_with("raiders/"):
			continue
		var raw: Variant = (c as Dictionary)[path]
		var entries: Array = raw as Array if raw is Array else [raw]
		for entry in entries:
			if entry is Dictionary and String((entry as Dictionary).get("id", "")) == id:
				return entry
	return null


# Every archetype in the tree, sorted by id so a band's composition is a function of the seed
# rather than of directory iteration order.
static func types(world: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world == null or world.content == null or not (world.content is Dictionary):
		return out
	for path in (world.content as Dictionary).keys():
		if not String(path).begins_with("raiders/"):
			continue
		var raw: Variant = (world.content as Dictionary)[path]
		var entries: Array = raw as Array if raw is Array else [raw]
		for entry in entries:
			if entry is Dictionary and String((entry as Dictionary).get("id", "")).begins_with("raider."):
				out.append(entry as Dictionary)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("id", "")) < String(b.get("id", "")))
	return out


# One weighted draw from the archetype pool. Same shape as `SimRoster.pick_type`: weights are
# relative and a type that declares none counts as 1, so adding an archetype is a JSON file.
static func pick_type(world: Variant, rng: Variant) -> String:
	var pool: Array[Dictionary] = types(world)
	if pool.is_empty():
		return ""
	var total: int = 0
	for entry in pool:
		total += maxi(1, int(entry.get("weight", 1)))
	var roll: int = int(rng.call("int_range", 0, total - 1))
	for entry in pool:
		roll -= maxi(1, int(entry.get("weight", 1)))
		if roll < 0:
			return String(entry.get("id", ""))
	return String(pool[pool.size() - 1].get("id", ""))


static func is_raider(world: Variant, entity: int) -> bool:
	return world.components.has_component(entity, "raider")


# How many raiders are standing in the district. Counted off the component rather than off a
# tally the director keeps, because a tally has to be decremented and `entity.killed` fires more
# than once for the same individual (CLAUDE.md's standing trap) -- so a tally would drift down.
# `world.despawn` removes every component, which is what makes this honest; see `handle_death`
# in recruits.gd, where a dead raider goes.
static func live_count(world: Variant) -> int:
	return world.components.count("raider")


static func spawn(world: Variant, x: float, y: float, type_id: String) -> int:
	var entry: Variant = content_entry(world, type_id)
	if not (entry is Dictionary):
		return -1
	var e: Dictionary = entry as Dictionary
	# The role, refused before a single draw is spent. Two reasons for the order rather than one:
	# a refused spawn must leave `raiderRoll` and `raiderLook` exactly where it found them, or a
	# malformed archetype would reshuffle every body drawn after it; and an archetype nothing
	# implements must not become a fighter by default, which is the whole point of the enum.
	# `-1` is what `_emit_band` already handles -- it counts what it placed -- so a band short one
	# body is the visible consequence, and a content tree that reaches here has been past the
	# schema's enum first.
	var role: String = String(e.get("role", ROLE_FIGHTER))
	if not ROLES.has(role):
		push_error("raider archetype %s declares role '%s', which nothing implements -- %s" % [String(e.get("id", type_id)), role, str(ROLES)])
		return -1
	# Drawn before the body exists, so the two streams are spent in one place and in one order
	# however the caller got here -- the director's band, a fixture, a gate.
	var roll_rng: Variant = world.rng.stream(ROLL_STREAM)
	var look_rng: Variant = world.rng.stream(LOOK_STREAM)
	var person: Dictionary = roll_person(world, roll_rng, look_rng)
	var ent: int = int(world.entities.spawn())
	world.components.set_component(ent, "position", {"x": x, "y": y})
	world.components.set_component(ent, "velocity", {"dx": 0.0, "dy": 0.0})
	world.components.set_component(ent, "facing", {"radians": 0.0})
	world.components.set_component(ent, "posture", SimStancesRes.make_posture(SimStancesRes.Stance.Walk))
	# A plain Array for the path and dictionary steps inside it, not Vector2i: components round
	# trip through JSON on every save and JSON has neither. jobs.gd's `_walk` is the precedent
	# and this mirrors it deliberately rather than inventing a second path representation.
	world.components.set_component(ent, "raider", {
		"id": String(e.get("id", type_id)),
		# Who this one is: `{name, age, features, look, backstoryId}` and deliberately **not** an
		# `identity` component (the owner's call, 2026-09-14). Five things read `identity` and one
		# of them is succession -- `SimRecruits._succession_pick` takes the nearest body carrying
		# `needs` or `identity` -- so an identity here would make the band at your gate a queue of
		# heirs to your own body. The trait list `SimPeople.roll` also returns is dropped: nothing
		# reads a raider's trait, and a field nothing reads is the mistake this milestone has paid
		# for eleven times. `check_m2_raiders.gd` NO-IDENTITY.
		"person": person,
		# What they came to do, stamped on the body rather than looked up per tick: `_approach`
		# asks this every tick for every raider, and it travels through a save with the rest of
		# the component so a band restored mid-raid is still the band that set out.
		"role": role,
		# How many things off your floor this body is carrying. A looter's counter and nobody
		# else's; it rides out of the district on `raid.withdrew` so a harness can see stores
		# leaving without counting entities that no longer exist.
		"looted": 0,
		"path": [],
		"pathGen": -1,
		"goalX": -1,
		"goalY": -1,
		# The band: `raidId` groups the bodies one night sent and `bandSize` is how many, both
		# stamped by the director's `_emit_band` (0 for a body a fixture spawned alone, which
		# then never withdraws for strength). Where it came in, when it arrived, and whether
		# it is on its way out.
		"raidId": 0,
		"bandSize": 0,
		"entryX": floori(x),
		"entryY": floori(y),
		"arrivedAtTick": -1,
		"withdrawing": false,
		# Empty and (-1, -1) is a raid: walk at the colony, leave the way you came. A crossing is
		# what `stamp_crossing` writes over them, and nothing else ever does -- a body a fixture
		# spawned alone is a raider at the gate, exactly as it was before this slice.
		"objective": {},
		"exitX": -1,
		"exitY": -1,
	})
	# The declared allegiance, not a constant: this field is what `SimAllegiance.hostile` reads,
	# and the gate proves it by flipping it to "colony" and watching the colony stop shooting.
	SimAllegianceRes.attach(world, ent, String(e.get("allegiance", SimAllegianceRes.RAIDERS)))
	SimHealthRes.make_survivor_body(world, ent)
	SimHealthRes.make_stamina(world, ent)
	SimInventoryRes.make_inventory(world, ent)
	# The same emitter a colonist has, which is the whole of "zombies treat raiders as prey" on
	# the attention side: footsteps into the noise field, body scent into the scent field, both
	# read by the shambler gradient with nothing about raiders in it.
	SimAttentionRes.make_emitter(world, ent)
	SimAptitudesRes.apply(world, ent, roll_aptitudes(e.get("aptitudes", {}), roll_rng))
	# The web, and what this archetype arrives already knowing on it. `attach` first (an empty
	# web, every region at zero), then the authored nodes granted outright -- see the header on
	# why a raider carries this one colonist component and why it is nodes rather than points.
	SimSkillsRes.attach(world, ent)
	var authored: Variant = e.get("skills", [])
	if authored is Array:
		SimSkillsRes.endow(world, ent, authored as Array)
	# Eyes, so `SimRanged.can_target` refuses a raider a shot through a wall the same way it
	# refuses a colonist one -- without an observer that check returns true and a raider would
	# be the one body in the district that could shoot through masonry.
	if not world.components.has_component(ent, "observer"):
		world.components.set_component(ent, "observer", SimVisibilityRes.daylight_eyes())
	SimSightingsRes.attach(world, ent)
	# `lootKit` is what `recruits._drop_kit` looks for: it is why a dead raider leaves their
	# weapon on the ground instead of taking it out of the world.
	world.components.set_component(ent, "lootKit", {})
	var kit: Variant = e.get("kit", [])
	if kit is Array:
		for row in kit as Array:
			# A kit row is a bare id, or `{item, count, chance}` where the quantity or the odds
			# matter. Ammunition forced the count: `spawn_item` defaults a stack to one, so a
			# gunhand declared as a bare "item.ammo.9mm" arrived with a single round and spent the
			# raid reloading. Telling one body of a band from another forced the chance.
			var item_id: String = ""
			var count: int = 1
			if row is Dictionary:
				item_id = String((row as Dictionary).get("item", ""))
				count = maxi(1, int((row as Dictionary).get("count", 1)))
				# A row that declares a chance spends exactly one draw whatever the odds are, so
				# how much randomness a band costs is a function of the content's shape and not of
				# its numbers -- a chance edited from 0.5 to 1.0 must not move the stream under
				# every later raider. A bare row spends none, which is what keeps an archetype
				# that declares no odds byte-identical to the way it spawned before this slice.
				if (row as Dictionary).has("chance"):
					var chance: float = float((row as Dictionary)["chance"])
					if not bool(roll_rng.call("bool_chance", chance)):
						continue
			else:
				item_id = String(row)
			if item_id.is_empty():
				continue
			var item: int = SimItemsRes.spawn_item(world, item_id, {"tier": "scavenged", "count": count})
			if _hold_it(world, ent, item):
				continue
			if not SimInventoryRes.stow(world, ent, item):
				world.components.set_component(item, "position", {"x": x, "y": y})
	world.events.publish({"type": "raider.arrived", "entity": ent, "id": String(e.get("id", type_id)), "x": x, "y": y})
	return ent


# One person, off the shared roll. `SimPeople.roll` is the draw a recruit at the gate makes
# (docs/30, "The pause lifted"), and a raider makes the same one against its own pool -- so a
# stranger, a colonist and the man walking at your wall are generated by one function and not by
# three that drift. What is kept is the record `raider.person` carries; the traits, the aptitudes
# and the backstory kit the roll also returns are dropped on purpose: aptitudes come from the
# archetype's own range below, a raider owns no backstory kit, and nothing anywhere reads a
# raider's trait.
#
# An empty pool is survivable rather than fatal: `SimPeople.roll` falls back to one of everything,
# so a content tree with no raider generator in it spawns a band of people all called Sam Doe
# instead of crashing a campaign at the gate. The gate is what refuses that, not the sim.
static func roll_person(world: Variant, roll_rng: Variant, look_rng: Variant) -> Dictionary:
	var rolled: Dictionary = SimPeopleRes.roll(roll_rng, look_rng, SimPeopleRes.pool(world, PEOPLE_POOL_ID))
	return {
		"name": String(rolled.get("name", "")),
		"age": int(rolled.get("age", 0)),
		"features": (rolled.get("features", []) as Array).duplicate(),
		"look": String(rolled.get("look", "")),
		"backstoryId": String(rolled.get("backstoryId", "")),
	}


# The archetype's aptitudes, with the ones declared as a range rolled per body. A bare number is
# left exactly as it was, so an archetype that declares none of this spawns the way it always did.
#
# The keys are walked in a fixed order rather than in `declared.keys()` order, because the draw
# order *is* the determinism: JSON hands Godot its keys in file order, so a content edit that
# reordered `dex` and `con` inside the block would silently reshuffle every band after it.
static func roll_aptitudes(declared: Variant, rng: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (declared is Dictionary):
		return out
	var d: Dictionary = declared as Dictionary
	for key in ["str", "dex", "con"]:
		if not d.has(key):
			continue
		var v: Variant = d[key]
		if v is Array and (v as Array).size() == 2:
			var lo: int = int((v as Array)[0])
			var hi: int = int((v as Array)[1])
			out[key] = int(rng.call("int_range", mini(lo, hi), maxi(lo, hi)))
		else:
			out[key] = int(v)
	return out


# One prose sentence naming who a dead raider was: `SimSurvivors.person_clause`'s shape, against
# the raiders' pool instead of the colony's. It takes the record rather than an entity, because
# the only thing that reads it is the chronicle and by the time that drains the body has been
# despawned (`SimRecruits.handle_death` publishes `raider.killed` with the record on it, *before*
# the despawn, for exactly this reason).
#
# This is what every field of `raider.person` is for. The name is the point; the story line and
# the age band's prose are looked up in content at read time, so editing a line changes what an
# existing save says without a migration; and the features are what a look at the body shows.
# Digit-free -- the age is a band's words, never the number -- because the chronicle is on the
# HUD and `check_hud.gd` allows no digit there but the day counter.
static func person_clause(world: Variant, person: Dictionary) -> String:
	var name: String = String(person.get("name", ""))
	if name.is_empty():
		return ""
	var pool: Dictionary = SimPeopleRes.pool(world, PEOPLE_POOL_ID)
	var parts: Array[String] = [name]
	var story: String = _story_line(pool, String(person.get("backstoryId", "")))
	if story != "":
		parts.append(story)
	var age_prose: String = _age_prose(pool, int(person.get("age", 0)))
	if age_prose != "":
		parts.append(age_prose)
	var clause: String = ", ".join(parts)
	var feats: Array = person.get("features", []) as Array if person.get("features", []) is Array else []
	if not feats.is_empty():
		var words: Array[String] = []
		for f in feats:
			words.append(String(f))
		clause += "; " + ", ".join(words)
	return clause


static func _story_line(pool: Dictionary, backstory_id: String) -> String:
	if backstory_id.is_empty():
		return ""
	for story in pool.get("backstories", []) as Array:
		if story is Dictionary and String((story as Dictionary).get("id", "")) == backstory_id:
			return String((story as Dictionary).get("line", ""))
	return ""


static func _age_prose(pool: Dictionary, age: int) -> String:
	if age <= 0:
		return ""
	for band in pool.get("ageBands", []) as Array:
		if not (band is Dictionary):
			continue
		if age >= int((band as Dictionary).get("min", 0)) and age <= int((band as Dictionary).get("max", 999)):
			return String((band as Dictionary).get("prose", ""))
	return ""


# Kit into the hand it belongs to rather than the pack. `SimSurvivors._hold_it`'s rule and its
# reasoning: a weapon in a satchel raises no `meleeWeapon`, so a raider carrying a machete in
# their bag would arrive unable to fight and the whole raid would be a walk.
static func _hold_it(world: Variant, ent: int, item: int) -> bool:
	var slot: Variant = SimInventoryRes.equip_slot_for(world, item)
	if slot == null:
		return false
	var eq: Variant = world.components.get_component(ent, "equipment")
	if eq is Dictionary and ((eq as Dictionary).get("slots", {}) as Dictionary).has(String(slot)):
		return false
	return SimInventoryRes.equip(world, ent, item)


static func register_module(world: Variant) -> void:
	# "ai"/0, beside `jobs.ai` and `shambler.think`: this decides a velocity, and
	# `movement.integrate` (movement/0) spends it on the same tick.
	world.systems.register("raiders.approach", "ai", 0, func(w: Variant) -> void:
		if bool(w.runOver) if "runOver" in w else false:
			return
		for ent in w.components.query(["raider", "position", "velocity"]):
			_approach(w, int(ent))
	)


static func _approach(world: Variant, ent: int) -> void:
	var vel: Variant = world.components.get_component(ent, "velocity")
	if not (vel is Dictionary):
		return
	var body: Variant = world.components.get_component(ent, "body")
	if not (body is Dictionary) or not SimHealthRes.is_alive(body as Dictionary):
		_still(vel as Dictionary)
		return
	var raider: Variant = world.components.get_component(ent, "raider")
	if not (raider is Dictionary):
		return
	var r: Dictionary = raider as Dictionary
	var role: String = String(r.get("role", ROLE_FIGHTER))
	# On the way out: a raid back to the tile it came in on, a crossing on to the far edge, then
	# gone either way. Nothing stops a withdrawal.
	if bool(r.get("withdrawing", false)):
		var out: Vector2i = _leave_tile(r)
		var pos: Variant = world.components.get_component(ent, "position")
		if out.x < 0 or not (pos is Dictionary) or _at_tile(pos as Dictionary, out, 1.5) or (r.get("path", []) as Array).is_empty() and int(r.get("pathGen", -1)) == int(world.mapGeneration):
			_leave(world, ent, r)
			return
		_walk(world, ent, r, out)
		return
	# Cut below half its number, the band leaves at once.
	if int(r.get("bandSize", 0)) > 0 and _band_live(world, int(r.get("raidId", 0))) * 2 < int(r.get("bandSize", 0)):
		_begin_withdrawal(r)
		_still(vel as Dictionary)
		return
	# The lookout's job, and the only thing about a raid that one body decides for everybody: at
	# the *first* loss it turns the band for home, rather than at the half strength the clause
	# above waits for. docs/18's "retreat when losses outweigh the haul" -- a band that brought a
	# watcher retreats on a business's arithmetic rather than on a horde's.
	if role == ROLE_LOOKOUT and int(r.get("bandSize", 0)) > 0 and _band_live(world, int(r.get("raidId", 0))) < int(r.get("bandSize", 0)):
		_turn_band_home(world, int(r.get("raidId", 0)))
		_still(vel as Dictionary)
		return
	# The looter's business, done at the stores, and it is asked BEFORE the halt below on purpose:
	# docs/18's raiders "target stores first, people second". `_loot_step` answers true only when
	# there is something of the colony's inside arm's reach or the arms are already full, so this
	# is narrow -- a looter standing on your pantry with a defender closing takes the tin and then
	# goes, and a looter anywhere else falls through and fights like anybody else. It costs it
	# nothing defensively either: `npc_combat.gd` swings from where a body is standing and never
	# reads a velocity, so a looter with its hand in your stores is still hitting back.
	#
	# The reason the order matters, and it is measured rather than assumed: the stockpile is where
	# the colonists are, so a looter that does reach the shelf is inside somebody's reach before it
	# is inside the tins' -- with the halt asked first it would stand there and fight over the
	# pantry without ever touching it. What four forced raids on day 8 also measured is that the
	# band is met 5 to 13 m short of the stores anyway, so no campaign has yet exercised either
	# order; docs/23's record says so rather than claiming this bought something.
	if role == ROLE_LOOTER and _loot_step(world, ent, r):
		_still(vel as Dictionary)
		return
	# Stand and fight. `npc_combat.gd` never sets a velocity -- engaging is something you do from
	# where you are standing -- so the halt has to come from here, and it is the difference
	# between a band that fights the colony and a band that walks through it. Every role ends up
	# here: a looter with nothing in reach is a man in a fight like the rest of them.
	if _enemy_within(world, ent, HALT_METRES):
		_still(vel as Dictionary)
		return
	var goal: Vector2i = _objective(world, r, role, ent)
	if goal.x < 0 or goal.y < 0:
		_still(vel as Dictionary)
		return
	# A lookout stops short of the objective and watches it. Not `_walk` with a shorter path: it
	# never plans the last LOOKOUT_METRES at all, which is what makes "does not close" a property
	# of the approach rather than of where a tick happened to end.
	#
	# **Not while crossing**, and this is the half of the roles question the crossing slice had to
	# answer. `LOOKOUT_METRES` is a watcher on the treeline *outside your gate* -- it is a distance
	# from a colony, and a band that is not coming for a colony has nothing to stand off from. A
	# lookout halting twelve metres short of a cupboard is the clause read literally and meant
	# nowhere. What does travel is the other half of the same role, six branches up: the first man
	# down still turns the whole band for the exit, because that is a fact about the band's
	# arithmetic rather than about the colony, and it is exactly docs/18's "retreat when losses
	# outweigh the haul" applied to a crossing. So a lookout in a passing band walks with it and
	# decides when it breaks off.
	if role == ROLE_LOOKOUT and not is_crossing(r) and _within_metres(world, ent, goal, LOOKOUT_METRES):
		_still(vel as Dictionary)
		_arrival_clock(world, r)
		return
	_walk(world, ent, r, goal)
	# At the objective with nobody to fight: the clock runs, and when it is out the band goes.
	if (r.get("path", []) as Array).is_empty():
		_arrival_clock(world, r)
	else:
		r["arrivedAtTick"] = -1


# The one withdrawal clock, shared by every role: WITHDRAW_AFTER_TICKS standing at whatever this
# body came to stand at. A looter that found an empty stockpile and a lookout that reached its
# watching distance both run it, which is why a band that takes nothing leaves exactly when a band
# of fighters would have.
static func _arrival_clock(world: Variant, r: Dictionary) -> void:
	if int(r.get("arrivedAtTick", -1)) < 0:
		r["arrivedAtTick"] = int(world.tick)
	elif int(world.tick) - int(r.get("arrivedAtTick", -1)) >= WITHDRAW_AFTER_TICKS:
		_begin_withdrawal(r)


# Out of the district, with everything in their hands and their pack. Announced before the body
# goes, because afterwards nothing can tell what left: `raid.withdrew` carries the haul the way
# `raider.killed` carries the person, and for the same reason -- handlers drain at the end of the
# step, by which time the component is gone.
#
# The items are despawned rather than left behind, and that is the half that makes a looter a
# *cost*. An item whose `stored` points at a despawned body is in nobody's hands and on no floor:
# it would neither come back nor be gone, which is the quietly-not-what-you-stored family this
# file already has two entries in. What a raid took is gone; what it dropped, it dropped when
# somebody killed it (`SimRecruits._drop_kit`).
static func _leave(world: Variant, ent: int, r: Dictionary) -> void:
	# One added field, and it has a reader: `check_m2_balance.gd`'s run line prints `looted` so a
	# campaign can show stores walking out. A count of everything carried was on this event for an
	# hour and came back off it -- nothing read it, and a field nothing reads is the mistake this
	# milestone has paid for eleven times.
	world.events.publish({
		"type": "raid.withdrew",
		"entity": ent,
		"raidId": int(r.get("raidId", 0)),
		"looted": int(r.get("looted", 0)),
	})
	for item in SimInventoryRes.carried_items(world, ent):
		world.despawn(int(item))
	world.despawn(ent)


# Every body of one raid turns for home. Written onto the components rather than published as an
# event, because `events.publish` only queues and handlers run at `drain()` at the end of the step
# -- a band told to leave by an event would take one more step towards the colony first, and on
# the tick a lookout sees the first man fall that step is a blow landing.
static func _turn_band_home(world: Variant, raid_id: int) -> void:
	for other in world.components.query(["raider"]):
		var o: Variant = world.components.get_component(int(other), "raider")
		if o is Dictionary and int((o as Dictionary).get("raidId", 0)) == raid_id:
			_begin_withdrawal(o as Dictionary)


# Is this body within `metres` of the centre of `tile`?
static func _within_metres(world: Variant, ent: int, tile: Vector2i, metres: float) -> bool:
	var pos: Variant = world.components.get_component(ent, "position")
	if not (pos is Dictionary):
		return false
	return _at_tile(pos as Dictionary, tile, metres)


# What a looter does when it is standing where it was going. Three answers: it is loaded and goes;
# something of yours is in reach and it takes it; or there is not, and it hands the tick back to
# the walk above.
#
# `SimInventory.nearest_ground_item` and `pick_up_nearest` do the moving -- the same pair a
# colonist picks a dropped weapon up with, reach limit (`PICKUP_REACH`) included. Nothing here
# writes a `position` or a `stored` by hand; what this adds is the question of *whose* item it is,
# which is the stockpile predicate the colony's own hauling already reads.
static func _loot_step(world: Variant, ent: int, r: Dictionary) -> bool:
	if int(r.get("looted", 0)) >= LOOT_TAKE:
		_begin_withdrawal(r)
		return true
	var near: Variant = SimInventoryRes.nearest_ground_item(world, ent)
	if near == null or not _worth_taking(world, r, int(near)):
		return false
	if not SimInventoryRes.pick_up_nearest(world, ent):
		# Nothing left to put it in. Loaded is loaded, whether the number says three or one -- the
		# alternative is a body standing on your pantry failing the same pick-up forever.
		_begin_withdrawal(r)
		return true
	r["looted"] = int(r.get("looted", 0)) + 1
	world.events.publish({"type": "raid.looted", "entity": ent, "raidId": int(r.get("raidId", 0)), "item": int(near)})
	if int(r.get("looted", 0)) >= LOOT_TAKE:
		_begin_withdrawal(r)
		return true
	# Re-plan onto the next thing worth taking. The cache is cleared rather than recomputed every
	# tick on purpose: the scan in `_loot_goal` walks the stores, and a looter pays for it once an
	# armful rather than once a tick.
	r["goalX"] = -1
	r["goalY"] = -1
	r["path"] = []
	r["pathGen"] = -1
	return true


# Whose things are worth taking, which is a different question for a band at your gate and a band
# passing through -- and it is the other half of the roles question the crossing slice had to
# answer.
#
# A raid's looter takes the colony's stores; that is docs/18's "target stores first" and it stays
# exactly as it was. A crossing's looter takes what is lying **at the site it crossed for**, and
# never goes near your pantry: it is not coming for you, and a looter that walked past its own
# objective to rob a colony it was not visiting would turn the whole lever into a raid with extra
# steps. Read the other way round, the role is what makes the objective pay: a band that crossed a
# district for a pharmacy and took nothing out of it is the contradiction, not this.
#
# What it costs the player is real and is the point: the armful leaves the district on
# `raid.withdrew` with the body carrying it, so a site the colony had not reached yet is a site
# that is now three things poorer. docs/12's scavenging squeeze, arriving as somebody else rather
# than as a timer.
static func _worth_taking(world: Variant, r: Dictionary, item: int) -> bool:
	if is_crossing(r):
		return _at_objective(world, r, item)
	return _is_stores(world, item)


# Is this item lying at the place the band crossed for? Measured from the site's own tile rather
# than from the body, so "at the site" is a fact about the place and not about where a looter
# happens to be standing when it asks.
static func _at_objective(world: Variant, r: Dictionary, item: int) -> bool:
	var o: Variant = r.get("objective", {})
	if not (o is Dictionary):
		return false
	var site := Vector2i(int((o as Dictionary).get("x", -1)), int((o as Dictionary).get("y", -1)))
	if site.x < 0 or site.y < 0:
		return false
	var pos: Variant = world.components.get_component(item, "position")
	if not (pos is Dictionary):
		return false
	return _at_tile(pos as Dictionary, site, SITE_REACH)


# Is this item lying on the colony's stores? `SimNeeds.is_stockpile_tile` is the colony's own
# answer to that -- indoors, a floor, inside the annex -- and asking it here rather than writing a
# second one is what stops a raider and a hauler disagreeing about where the pantry is.
# `SimHome.rect` is the other half: home is where the colony *is*, so a camp's footprint with no
# annex floor in it honestly has no stores and a looter there falls back to the gate.
static func _is_stores(world: Variant, item: int) -> bool:
	var pos: Variant = world.components.get_component(item, "position")
	if not (pos is Dictionary):
		return false
	var tile := Vector2i(floori(float((pos as Dictionary)["x"])), floori(float((pos as Dictionary)["y"])))
	if not SimHomeRes.rect(world).has_point(tile):
		return false
	return SimNeedsRes.is_stockpile_tile(world, tile.x, tile.y)


static func _begin_withdrawal(r: Dictionary) -> void:
	r["withdrawing"] = true
	r["path"] = []
	r["pathGen"] = -1


static func _band_live(world: Variant, raid_id: int) -> int:
	var n: int = 0
	for other in world.components.query(["raider"]):
		var o: Variant = world.components.get_component(int(other), "raider")
		if o is Dictionary and int((o as Dictionary).get("raidId", 0)) == raid_id:
			n += 1
	return n


static func _at_tile(pos: Dictionary, tile: Vector2i, reach: float) -> bool:
	var dx: float = float(tile.x) + 0.5 - float(pos["x"])
	var dy: float = float(tile.y) + 0.5 - float(pos["y"])
	return dx * dx + dy * dy <= reach * reach


# The director stamps the band on the bodies it placed.
static func stamp_band(world: Variant, members: Array, raid_id: int) -> void:
	for ent in members:
		var r: Variant = world.components.get_component(int(ent), "raider")
		if r is Dictionary:
			(r as Dictionary)["raidId"] = raid_id
			(r as Dictionary)["bandSize"] = members.size()


# And, for a band that is only passing through, where it is going and where it leaves. Called by
# `SimDirector._emit_band` immediately after `stamp_band` and by nothing else, so a band is a raid
# unless the dawn draw said otherwise.
#
# The cached goal and the path are cleared with it, which is not housekeeping: `spawn` may already
# have been followed by a tick of walking in a fixture, and a body carrying a path towards the gate
# would finish walking to the gate before noticing it was somewhere else. `_begin_withdrawal`
# clears the same three for the same reason.
#
# An `exit_tile` of (-1, -1) is allowed and means "leave the way you came" -- see `SimDirector`'s
# `_far_edge`, which returns it for a district with only one usable edge.
static func stamp_crossing(world: Variant, members: Array, site: Vector2i, exit_tile: Vector2i) -> void:
	for ent in members:
		var r: Variant = world.components.get_component(int(ent), "raider")
		if not (r is Dictionary):
			continue
		var rec: Dictionary = r as Dictionary
		rec["objective"] = {"kind": OBJECTIVE_SITE, "x": site.x, "y": site.y}
		rec["exitX"] = exit_tile.x
		rec["exitY"] = exit_tile.y
		rec["goalX"] = -1
		rec["goalY"] = -1
		rec["path"] = []
		rec["pathGen"] = -1


## Is this body crossing the district rather than coming for the colony?
##
## The `kind` is asked rather than assumed, so the record is a closed shape from the day it lands:
## an objective naming something nothing implements reads as no objective at all and the band is a
## raid, which is the loud-by-omission answer rather than a body walking at (0, 0).
static func is_crossing(r: Dictionary) -> bool:
	var o: Variant = r.get("objective", {})
	return o is Dictionary and String((o as Dictionary).get("kind", "")) == OBJECTIVE_SITE


# Where a band goes when it is done with whatever it came to do. A raid walks back to the tile it
# came in on; a crossing keeps going and leaves by the far edge the director stamped on it. One
# field decides which, and everything underneath -- the path, the arrival test, `_leave` and the
# `raid.withdrew` it publishes -- is the same machinery for both.
static func _leave_tile(r: Dictionary) -> Vector2i:
	var ex: int = int(r.get("exitX", -1))
	var ey: int = int(r.get("exitY", -1))
	if ex >= 0 and ey >= 0:
		return Vector2i(ex, ey)
	return Vector2i(int(r.get("entryX", -1)), int(r.get("entryY", -1)))


# Where the band is going. The gate, because that is how a colony is entered; the centre when a
# district carries no gate anchor; nothing at all when it carries no colony either, which is what an
# unstamped fixture map honestly is. That ladder now lives in `SimHome.approach` -- this was the one
# place in the whole sim that targeted home *explicitly* (the director never does: it places at the
# map edge and lets the field pull), so it is the one place a camp has to be understood.
#
# Still cached on the component, so home is read once per raider rather than once per tick. The
# cache is also what makes a camp established mid-raid not teleport a band that is already walking:
# the raiders who set out for the annex finish walking to the annex, which is the honest behaviour
# for people who cannot see that you have moved.
# Both added arguments are trailing and defaulted, which is not a style choice: `check_m2_camp.gd`'s
# READS lane calls `_objective(world, {})` with a fresh record and no body at all, to ask whether
# the raiders read `SimHome` -- so the two-argument contract has a caller outside this file and
# stays exactly as it was. Without an entity a looter has no "nearest" to measure from and falls
# through to the shared answer, which is what that lane is asking about.
static func _objective(world: Variant, r: Dictionary, role: String = ROLE_FIGHTER, ent: int = -1) -> Vector2i:
	var cached := Vector2i(int(r.get("goalX", -1)), int(r.get("goalY", -1)))
	if cached.x >= 0 and cached.y >= 0:
		return cached
	if world.tilemap == null:
		return Vector2i(-1, -1)
	# A band that is only passing through walks at the place it came for, whatever its role. This
	# is asked before the role ladder rather than folded into it because it is a different
	# question: the role says what a body wants *when it gets where it is going*, and the crossing
	# says where that is. A looter crossing still loots -- at the site, see `_worth_taking` -- and
	# a lookout crossing still turns the band at the first loss; neither of them is walking at your
	# gate, and neither of them is asked to.
	if is_crossing(r):
		var o: Dictionary = r["objective"] as Dictionary
		var site := Vector2i(int(o.get("x", -1)), int(o.get("y", -1)))
		if site.x >= 0 and site.y >= 0:
			r["goalX"] = site.x
			r["goalY"] = site.y
			return site
	# A looter is walking at your stores rather than at your gate, which is the whole of docs/18's
	# "target stores first, people second". A district with no stores in it -- no annex, a camp, an
	# unstamped fixture -- gives a looter the same answer it gives everybody else, so a looter
	# where there is nothing to take is a fighter rather than a body standing still.
	var goal: Vector2i = Vector2i(-1, -1)
	if role == ROLE_LOOTER:
		goal = _loot_goal(world, ent)
	if goal.x < 0 or goal.y < 0:
		goal = SimHomeRes.approach(world)
	if goal.x < 0 or goal.y < 0:
		return Vector2i(-1, -1)
	r["goalX"] = goal.x
	r["goalY"] = goal.y
	return goal


# Where the stores are worth walking to: the tile of the nearest thing of yours lying on them, and
# failing that the nearest stores tile at all -- which is a looter arriving at an empty pantry,
# standing there, and going home on the same clock a fighter goes home on.
#
# Scanned rather than kept: `SimNeeds.stockpile_items` is the colony's own list of what is lying on
# its floor, and the rect underneath the fallback is `SimHome.rect`. A looter pays for this once
# when it sets out and once per armful (`_loot_step` clears the cached goal), never once a tick.
static func _loot_goal(world: Variant, ent: int) -> Vector2i:
	var here: Variant = world.components.get_component(ent, "position")
	if not (here is Dictionary):
		return Vector2i(-1, -1)
	var from := Vector2(float((here as Dictionary)["x"]), float((here as Dictionary)["y"]))
	var rect: Rect2i = SimHomeRes.rect(world)
	if rect.size.x <= 0 or rect.size.y <= 0:
		return Vector2i(-1, -1)
	var best := Vector2i(-1, -1)
	var best_d: float = 1e12
	for item in SimNeedsRes.stockpile_items(world):
		var p: Variant = world.components.get_component(int(item), "position")
		if not (p is Dictionary):
			continue
		var tile := Vector2i(floori(float((p as Dictionary)["x"])), floori(float((p as Dictionary)["y"])))
		if not rect.has_point(tile):
			continue
		var d: float = from.distance_squared_to(Vector2(float(tile.x) + 0.5, float(tile.y) + 0.5))
		if d < best_d:
			best_d = d
			best = tile
	if best.x >= 0:
		return best
	for ty in range(rect.position.y, rect.position.y + rect.size.y):
		for tx in range(rect.position.x, rect.position.x + rect.size.x):
			if not SimNeedsRes.is_stockpile_tile(world, tx, ty):
				continue
			var d2: float = from.distance_squared_to(Vector2(float(tx) + 0.5, float(ty) + 0.5))
			if d2 < best_d:
				best_d = d2
				best = Vector2i(tx, ty)
	return best


# The nearest enemy body inside `metres`, asked of `SimAllegiance.enemies_of` so the halt and
# `npc_combat._nearest_threat` cannot disagree about who counts as one.
static func _enemy_within(world: Variant, ent: int, metres: float) -> bool:
	var here: Variant = world.components.get_component(ent, "position")
	if not (here is Dictionary):
		return false
	var hx: float = float((here as Dictionary)["x"])
	var hy: float = float((here as Dictionary)["y"])
	var limit_sq: float = metres * metres
	for other in SimAllegianceRes.enemies_of(world, ent):
		var body: Variant = world.components.get_component(int(other), "body")
		if not (body is Dictionary) or not SimHealthRes.is_alive(body as Dictionary):
			continue
		var there: Variant = world.components.get_component(int(other), "position")
		if not (there is Dictionary):
			continue
		var dx: float = float((there as Dictionary)["x"]) - hx
		var dy: float = float((there as Dictionary)["y"]) - hy
		if dx * dx + dy * dy <= limit_sq:
			return true
	return false


# Grid A* towards the goal, re-planned when the map generation moves under it. The body of this
# lives in `SimWalk.step` since the stranger slice: raiders were the second thing in the district
# that walked somewhere on purpose, a stranger in a house is the third, and a second copy of the
# stepper is two answers to one question. This is the raider's call of it -- the `raider`
# component is the record, and the speed is the archetype's through `move_speed`.
static func _walk(world: Variant, ent: int, r: Dictionary, goal: Vector2i) -> void:
	SimWalkRes.step(world, ent, r, goal, _speed_of(world, ent, r))


static func _speed_of(world: Variant, ent: int, r: Dictionary) -> float:
	var entry: Variant = content_entry(world, String(r.get("id", "")))
	var base: float = DEFAULT_SPEED
	if entry is Dictionary:
		base = float((entry as Dictionary).get("speed", DEFAULT_SPEED))
	if world.modifiers != null and (world.modifiers as Object).has_method("resolve"):
		base *= float(world.modifiers.call("resolve", "move_speed", ent))
	return maxf(base, 0.1)


static func _still(vel: Dictionary) -> void:
	SimWalkRes.halt(vel)
