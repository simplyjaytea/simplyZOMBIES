extends SceneTree
# The allegiance seam: a third side.
#
# `SimAllegiance` answers "is that one my enemy" for the whole tree, and until this slice it
# answered with `!=` -- two factions, so anybody who was not you was your enemy. The settlers need
# a side that is neither the colony nor hostile to it, and the difference between `!=` and a
# relations table is the whole of the change. Nothing spawns a settler yet, deliberately: the seam
# lands first and the camp stands on it afterwards, which means this gate is the only thing in the
# tree that exercises the third value at all.
#
# That is exactly the condition under which a gate quietly stops proving anything, so every lane
# here carries its true negative in the same fixture as its positive:
#
#   PEACE    a settler and a colonist, armed, in reach for 900 ticks, draw no blood -- and the
#            same pair with that one field flipped to `raiders` draws it. Without the second half
#            this lane passes against any two bodies that happen never to fight, which is what
#            "a gate that cannot fail" means in practice.
#   WAR      a settler and a raider do fight, through the shipped spawner and the colony's own
#            combat intake; the same two bodies both declared settlers do not.
#   PREY     a zombie still chases a settler -- the short circuit is before the table, and
#            `is_person` never asked about sides -- and does not chase the same body with its
#            person marker removed.
#   NO-HEIR  the player dies with a settler standing nearer than any colonist and the colony
#            inherits; give that same nearer body the colony's own allegiance and it inherits.
#   SYMMETRY the table agrees in both directions for every ordered pair, and the checker that
#            says so is shown failing against a deliberately one-way lookup.
#   SCHEMA   the raider schema's `$defs/faction` enum, which the shallow Godot validator does not
#            reach at all (it does not resolve `$ref`) and the frozen oracle never reads, judged
#            against the code's own constants and against every shipped archetype.
const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimAllegiance = preload("res://sim/modules/allegiance.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimNpcCombat = preload("res://sim/modules/npc_combat.gd")
const SimRaiders = preload("res://sim/modules/raiders.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimRecruits = preload("res://sim/modules/recruits.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const Clock = preload("res://sim/time/clock.gd")

const SEED: int = 20260915
# check_m2_raiders.gd's ARENA_TICKS, by name and by value: PEACE's negative is the duel that
# gate's BLOOD lane runs to a kill, so a truce measured over a shorter window would be a weaker
# claim than the fight it is contrasted with. One number in two places and this comment is the
# link, since a gate may not preload another gate.
const ARENA_TICKS: int = 900

const SCHEMA_PATH: String = "res://content/schemas/raider.schema.json"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _a_settler_and_a_colonist_keep_the_peace() and ok
	ok = _a_settler_and_a_raider_fight() and ok
	ok = _a_zombie_still_chases_a_settler() and ok
	ok = _a_settler_is_not_an_heir() and ok
	ok = _the_table_reads_the_same_both_ways() and ok
	ok = _the_schema_and_the_code_agree() and ok
	if ok:
		print("M2_ALLEGIANCE_OK peace war prey no-heir symmetry schema")
		quit(0)
	else:
		push_error("M2_ALLEGIANCE_FAIL")
		quit(1)


# --- PEACE ------------------------------------------------------------------------------------

# Two people, both with knives, 1.2 m apart, for 900 ticks, with the colony's own combat intake
# driving both of them. Exactly one field differs between the two runs: `allegiance.faction` on
# the second body. Neither body carries a `raider` component, on purpose -- if hostility were ever
# re-rooted on that component instead of on the declared faction, the truce here would still hold
# and the war would not, and the pair of them together is what says the table is the reader.
func _a_settler_and_a_colonist_keep_the_peace() -> bool:
	var truce: Dictionary = _duel(SimAllegiance.SETTLERS)
	if int(truce["hits"]) != 0:
		push_error("PEACE: a settler and a colonist traded %d blows in %d ticks -- the relations table is not being consulted" % [int(truce["hits"]), ARENA_TICKS])
		return false
	if int(truce["wounds"]) != 0:
		push_error("PEACE: no blow was recorded and %d wound(s) opened anyway -- the lane is counting the wrong thing" % int(truce["wounds"]))
		return false
	# The negative, in the same fixture: one string, and blood.
	var war: Dictionary = _duel(SimAllegiance.RAIDERS)
	if int(war["hits"]) < 1:
		push_error("PEACE: the same two bodies with the second declared `%s` never traded a blow either -- the truce above proves nothing" % SimAllegiance.RAIDERS)
		return false
	if int(war["wounds"]) < 1:
		push_error("PEACE: %d blows landed between declared enemies and opened no wound" % int(war["hits"]))
		return false
	print("PEACE OK settler/colonist %d hits %d wounds over %d ticks; the same pair declared raiders %d hits %d wounds" % [
		int(truce["hits"]), int(truce["wounds"]), ARENA_TICKS, int(war["hits"]), int(war["wounds"]),
	])
	return true


# One colonist and one other person, both hand-built and identically armed. `faction` is the only
# thing that varies. A Dictionary carries the counters rather than captured ints, because a
# GDScript lambda captures a primitive by value and an accumulator written inside an event handler
# would read back unchanged.
func _duel(faction: String) -> Dictionary:
	var w: Variant = _arena()
	SimWounds.register_module(w)
	var colonist: int = _person(w, 10.0, 10.0, SimAllegiance.COLONY, "survivor.test")
	var other: int = _person(w, 11.2, 10.0, faction, "survivor.other")
	SimInventory.equip(w, colonist, SimItems.spawn_item(w, "item.knife.kitchen", {"tier": "scavenged"}))
	SimInventory.equip(w, other, SimItems.spawn_item(w, "item.knife.kitchen", {"tier": "scavenged"}))
	w.events.drain()
	var out: Dictionary = {"hits": 0, "wounds": 0}
	for _t in ARENA_TICKS:
		w.step()
		# Sampled every tick and kept at its maximum: a body that dies takes its `injuries`
		# component with it, and a count taken at the end would read zero for whoever lost.
		out["wounds"] = maxi(int(out["wounds"]), _wound_count(w, colonist) + _wound_count(w, other))
		for e in w.events.drained:
			var ev: Dictionary = e as Dictionary
			if String(ev.get("type", "")) != "attack.connected":
				continue
			var att: int = int(ev.get("attacker", -1))
			if att == colonist or att == other:
				out["hits"] = int(out["hits"]) + 1
	return out


# --- WAR --------------------------------------------------------------------------------------

# The other row of the table, and through the shipped spawner rather than a hand-built body:
# `SimRaiders.spawn` writes the archetype's declared allegiance, and a settler standing in front
# of a raider is a fight neither side had before this slice. The negative declares the raider a
# settler too -- same bodies, same kit, same ground, one side between them -- and the fight stops.
func _a_settler_and_a_raider_fight() -> bool:
	var war: Dictionary = _band_duel(SimAllegiance.RAIDERS)
	if int(war["settler_hits"]) < 1:
		push_error("WAR: the settler never struck the raider in %d ticks" % ARENA_TICKS)
		return false
	if int(war["raider_hits"]) < 1:
		push_error("WAR: the raider never struck the settler in %d ticks" % ARENA_TICKS)
		return false
	if int(war["wounds"]) < 1:
		push_error("WAR: %d blows landed and left no wound" % [int(war["settler_hits"]) + int(war["raider_hits"])])
		return false
	var truce: Dictionary = _band_duel(SimAllegiance.SETTLERS)
	if int(truce["settler_hits"]) != 0 or int(truce["raider_hits"]) != 0:
		push_error("WAR: two bodies both declared `%s` traded %d/%d blows -- hostility is not reading the table" % [
			SimAllegiance.SETTLERS, int(truce["settler_hits"]), int(truce["raider_hits"]),
		])
		return false
	print("WAR OK settler %d hits, raider %d hits, %d wounds; both declared settlers %d/%d" % [
		int(war["settler_hits"]), int(war["raider_hits"]), int(war["wounds"]),
		int(truce["settler_hits"]), int(truce["raider_hits"]),
	])
	return true


# Two bodies from the raider spawner, 1.2 m apart. The first is declared a settler; the second
# takes whatever `faction` says. Both are combat intakes through the `raider` component they
# carry, which is what keeps the arena about the table rather than about the roster.
func _band_duel(faction: String) -> Dictionary:
	var w: Variant = _arena()
	SimWounds.register_module(w)
	var settler: int = SimRaiders.spawn(w, 10.0, 10.0, "raider.scav")
	var raider: int = SimRaiders.spawn(w, 11.2, 10.0, "raider.scav")
	SimAllegiance.attach(w, settler, SimAllegiance.SETTLERS)
	SimAllegiance.attach(w, raider, faction)
	w.events.drain()
	var out: Dictionary = {"settler_hits": 0, "raider_hits": 0, "wounds": 0}
	for _t in ARENA_TICKS:
		w.step()
		out["wounds"] = maxi(int(out["wounds"]), _wound_count(w, settler) + _wound_count(w, raider))
		for e in w.events.drained:
			var ev: Dictionary = e as Dictionary
			if String(ev.get("type", "")) != "attack.connected":
				continue
			var att: int = int(ev.get("attacker", -1))
			if att == settler:
				out["settler_hits"] = int(out["settler_hits"]) + 1
			elif att == raider:
				out["raider_hits"] = int(out["raider_hits"]) + 1
	return out


# --- PREY -------------------------------------------------------------------------------------

# A settler is a *person*, and the zombie short circuit is the reason that sentence needs no
# clause about sides: `hostile` answers true before the table is ever consulted, and `is_person`
# has never asked about allegiance at all. Both halves are measured rather than asserted -- the
# shambler has to enter Pursue, cross the ground and land a claw.
#
# The negative removes the `identity` from an otherwise identical body: same position, same flesh,
# same declared faction, no marker that says person. A shambler that still pursued it would mean
# prey is decided by something else; one that pursued neither would mean the positive proved
# nothing.
func _a_zombie_still_chases_a_settler() -> bool:
	var chased: Dictionary = _prey_arena(true)
	if not bool(chased["pursued"]):
		push_error("PREY: no shambler entered Pursue against a settler 1.5 m away in %d ticks" % ARENA_TICKS)
		return false
	if float(chased["closed"]) < 0.4:
		push_error("PREY: the shambler noticed the settler but closed only %.2f m" % float(chased["closed"]))
		return false
	if int(chased["claws"]) < 1:
		push_error("PREY: the shambler pursued the settler and never laid a claw on them")
		return false
	var ignored: Dictionary = _prey_arena(false)
	if bool(ignored["pursued"]):
		push_error("PREY: a shambler pursued a settler-faction body with no person marker -- prey is not being decided by is_person")
		return false
	if int(ignored["claws"]) != 0:
		push_error("PREY: a shambler clawed %d times at a body it was not pursuing" % int(ignored["claws"]))
		return false
	print("PREY OK the settler was pursued, closed %.2f m and took %d claws; the unmarked body neither" % [
		float(chased["closed"]), int(chased["claws"]),
	])
	return true


func _prey_arena(marked: bool) -> Dictionary:
	# GRABS_ENABLED off for the arena and the previous value restored: the flag is a static shared
	# by every world one gate process boots, and a live grab pins both bodies at arm's length, so
	# "closed the distance" would read the pin rather than the pursuit.
	var flag_was: bool = SimShambler.GRABS_ENABLED
	SimShambler.GRABS_ENABLED = false
	var w: Variant = _arena()
	SimShambler.register_module(w, SimTileMap.blank_map(32, 32))
	# Unarmed on purpose: an armed body keeps the shambler staggered and the claw never finishes
	# its wind-up, which check_m2_raiders.gd's PREY lane measured the expensive way.
	var settler: int = _person(w, 16.0, 16.0, SimAllegiance.SETTLERS, "survivor.settler")
	if not marked:
		w.components.remove(settler, "identity")
	var z: int = SimRoster.spawn_zombie(w, 17.5, 16.0, SimRoster.TYPE_SHAMBLER, w.rng.stream("shambler"))
	w.events.drain()
	var start: float = _distance(w, z, settler)
	var pursued: bool = false
	var closest: float = start
	var claws: Dictionary = {"n": 0}
	for _t in ARENA_TICKS:
		w.step()
		var sd: Variant = w.components.get_component(z, "shambler")
		if sd is Dictionary and int((sd as Dictionary)["state"]) == SimShambler.ShamblerState["Pursue"]:
			pursued = true
		for e in w.events.drained:
			var ev: Dictionary = e as Dictionary
			if String(ev.get("type", "")) == "attack.connected" and int(ev.get("attacker", -1)) == z:
				claws["n"] = int(claws["n"]) + 1
		var body: Variant = w.components.get_component(settler, "body")
		if not (body is Dictionary) or not SimHealth.is_alive(body as Dictionary):
			# The fight is over. Measuring past it would fold a corpse's stillness into the ground
			# the shambler covered while it was alive.
			break
		closest = minf(closest, _distance(w, z, settler))
	SimShambler.GRABS_ENABLED = flag_was
	return {"pursued": pursued, "closed": start - closest, "claws": int(claws["n"])}


# --- NO HEIR ----------------------------------------------------------------------------------

# Succession is where "a person" and "one of ours" stopped being the same question. The scan used
# to take an `identity` as proof of colony membership, and a settler carries one -- so the player
# dying at a stranger's fence would have woken up in the stranger's body, which is the most
# player-visible thing this seam prevents.
#
# The negative is the same body at the same distance with one field changed: give that nearer
# person the colony's own allegiance and they inherit. Without it the lane would pass against a
# scan that had started preferring whoever was furthest away, or refusing everybody.
func _a_settler_is_not_an_heir() -> bool:
	var w: Variant = _arena()
	# Not Mara: `_succession_pick` short circuits to her by id, and a lane that let it do so would
	# be measuring the short circuit rather than the filter.
	var colonist: int = _person(w, 30.0, 12.0, SimAllegiance.COLONY, "survivor.unique.ellis")
	var settler: int = _person(w, 12.5, 12.0, SimAllegiance.SETTLERS, "survivor.settler")
	w.events.drain()
	var dying: int = int(w.player)
	w.components.set_component(dying, "position", {"x": 12.0, "y": 12.0})
	var heir: int = SimRecruits._succession_pick(w, dying)
	if heir == settler:
		push_error("NO-HEIR: the player's body went to the settler standing 0.5 m away instead of the colonist across the district")
		return false
	if heir != colonist:
		push_error("NO-HEIR: the body went to %d, which is neither the settler (%d) nor the colonist (%d)" % [heir, settler, colonist])
		return false
	# And the settler was a candidate in every other respect: an identity, needs, a living body,
	# nearer than the heir. One field kept them out, and putting it back puts them in.
	SimAllegiance.attach(w, settler, SimAllegiance.COLONY)
	if SimRecruits._succession_pick(w, dying) != settler:
		push_error("NO-HEIR: the same body declared `%s` still did not inherit -- the scan refuses it for something other than its allegiance, so the refusal above proves nothing" % SimAllegiance.COLONY)
		return false
	print("NO-HEIR OK the far colonist inherited over a settler at 0.5 m, and the same body declared colony inherited")
	return true


# --- SYMMETRY ---------------------------------------------------------------------------------

# A symmetric table that can silently become asymmetric is a bug waiting to happen, so the table
# is not really a table: `factions_hostile` tries each declared pair both ways round, which makes
# the symmetry a property of the lookup rather than of the data. This lane asserts it anyway, over
# every ordered pair of every declared faction, and then proves the assertion can fail by running
# the identical walk against a deliberately one-way lookup.
#
# Two more things it refuses, both of which would make that walk vacuous: a table where nothing is
# hostile (peace everywhere passes a symmetry check perfectly) and one where everything is (so
# does war everywhere). And the entity-level `hostile` has to give the string-level table's answer
# in both directions, or the readers are not reading it.
func _the_table_reads_the_same_both_ways() -> bool:
	var factions: Array[String] = SimAllegiance.FACTIONS
	if factions.size() < 3:
		push_error("SYMMETRY: only %d faction(s) declared -- the third side did not land" % factions.size())
		return false
	if not factions.has(SimAllegiance.SETTLERS):
		push_error("SYMMETRY: `%s` is not in FACTIONS, so nothing walks it" % SimAllegiance.SETTLERS)
		return false
	for pair in SimAllegiance.HOSTILE_PAIRS:
		for side in pair as Array:
			if not factions.has(String(side)):
				push_error("SYMMETRY: HOSTILE_PAIRS names `%s`, which is not a declared faction" % String(side))
				return false
	var table: Callable = func(a: String, b: String) -> bool: return SimAllegiance.factions_hostile(a, b)
	var asym: Array[String] = _asymmetric_pairs(table)
	if not asym.is_empty():
		push_error("SYMMETRY: the table disagrees with itself on %s" % str(asym))
		return false
	# Not vacuous: at least one ordered pair at war and at least one at peace.
	var wars: int = 0
	var peaces: int = 0
	for a in factions:
		for b in factions:
			if String(a) == String(b):
				continue
			if SimAllegiance.factions_hostile(String(a), String(b)):
				wars += 1
			else:
				peaces += 1
	if wars == 0 or peaces == 0:
		push_error("SYMMETRY: %d hostile and %d peaceful ordered pairs -- a table that is all one thing is symmetric for free" % [wars, peaces])
		return false
	# The three rows the settlers actually depend on, named rather than counted.
	if not SimAllegiance.factions_hostile(SimAllegiance.RAIDERS, SimAllegiance.SETTLERS):
		push_error("SYMMETRY: raiders are at peace with settlers")
		return false
	if not SimAllegiance.factions_hostile(SimAllegiance.RAIDERS, SimAllegiance.COLONY):
		push_error("SYMMETRY: raiders are at peace with the colony")
		return false
	if SimAllegiance.factions_hostile(SimAllegiance.COLONY, SimAllegiance.SETTLERS):
		push_error("SYMMETRY: the colony is at war with the settlers")
		return false
	# The negative for the walk itself: the same function, against a lookup that answers one way
	# round only. If `_asymmetric_pairs` were incapable of reporting anything, the walk above would
	# have been a comment.
	var one_way: Callable = func(a: String, b: String) -> bool: return a == SimAllegiance.COLONY and b == SimAllegiance.SETTLERS
	if _asymmetric_pairs(one_way).is_empty():
		push_error("SYMMETRY: a deliberately one-way lookup was reported symmetric -- the walk cannot fail")
		return false
	# And the reader: `hostile` on two real bodies has to give the table's answer, both ways round.
	var w: Variant = _arena()
	var bodies: Dictionary = {}
	var i: int = 0
	for f in factions:
		bodies[String(f)] = _person(w, 4.0 + float(i) * 2.0, 4.0, String(f), "survivor.sym%d" % i)
		i += 1
	w.events.drain()
	for a in factions:
		for b in factions:
			var ea: int = int(bodies[String(a)])
			var eb: int = int(bodies[String(b)])
			var expected: bool = false if ea == eb else SimAllegiance.factions_hostile(String(a), String(b))
			var got: bool = SimAllegiance.hostile(w, ea, eb)
			if got != expected:
				push_error("SYMMETRY: hostile(%s, %s) is %s, the table says %s" % [String(a), String(b), str(got), str(expected)])
				return false
	print("SYMMETRY OK %d factions, %d ordered pairs at war and %d at peace, table and bodies agreeing both ways; a one-way lookup was caught" % [
		factions.size(), wars, peaces,
	])
	return true


# Every ordered pair the lookup answers differently from its mirror. It takes the lookup as a
# Callable so the same walk can be pointed at the shipped table and at a fabricated one-way one.
func _asymmetric_pairs(lookup: Callable) -> Array[String]:
	var out: Array[String] = []
	for a in SimAllegiance.FACTIONS:
		for b in SimAllegiance.FACTIONS:
			if bool(lookup.call(String(a), String(b))) != bool(lookup.call(String(b), String(a))):
				out.append("%s/%s" % [String(a), String(b)])
	return out


# --- SCHEMA -----------------------------------------------------------------------------------

# `raider.schema.json` declares which factions an archetype may name, and since this slice it
# declares it once, in `$defs/faction`. The shallow Godot validator does not resolve `$ref` -- it
# reads a top-level `type`, `enum` and `pattern` and nothing else -- and the frozen TypeScript
# oracle does not read `content/raiders/` at all, so without this lane the definition would be a
# comment. It is the dead-socket rule applied to a schema: the definition gets a reader.
func _the_schema_and_the_code_agree() -> bool:
	var f: FileAccess = FileAccess.open(SCHEMA_PATH, FileAccess.READ)
	if f == null:
		push_error("SCHEMA: cannot open %s" % SCHEMA_PATH)
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		push_error("SCHEMA: %s is not an object" % SCHEMA_PATH)
		return false
	var schema: Dictionary = parsed as Dictionary
	var props: Variant = schema.get("properties", {})
	var prop: Variant = (props as Dictionary).get("allegiance", {}) if props is Dictionary else {}
	if not (prop is Dictionary) or String((prop as Dictionary).get("$ref", "")) != "#/$defs/faction":
		push_error("SCHEMA: `allegiance` does not point at #/$defs/faction, so there are two definitions of a faction again")
		return false
	var defs: Variant = schema.get("$defs", {})
	var faction_def: Variant = (defs as Dictionary).get("faction", null) if defs is Dictionary else null
	if not (faction_def is Dictionary):
		push_error("SCHEMA: $defs/faction is missing, and `allegiance` points at it")
		return false
	var allowed: Array = (faction_def as Dictionary).get("enum", []) as Array
	if allowed.size() != 2 or not allowed.has(SimAllegiance.RAIDERS) or not allowed.has(SimAllegiance.SETTLERS):
		push_error("SCHEMA: $defs/faction allows %s, not exactly [%s, %s]" % [str(allowed), SimAllegiance.RAIDERS, SimAllegiance.SETTLERS])
		return false
	for value in allowed:
		if not SimAllegiance.FACTIONS.has(String(value)):
			push_error("SCHEMA: the schema allows `%s`, which the code does not declare as a faction" % String(value))
			return false
	# Every shipped entry, judged against that list rather than against a constant written here.
	var w: Variant = World.new(_fixture())
	var seen: int = 0
	for entry in SimRaiders.types(w):
		var declared: String = String((entry as Dictionary).get("allegiance", ""))
		if not allowed.has(declared):
			push_error("SCHEMA: %s declares `%s`, which is not in the schema's enum" % [String((entry as Dictionary).get("id", "?")), declared])
			return false
		seen += 1
	if seen < 1:
		push_error("SCHEMA: no raider archetypes loaded, so the sweep above judged nothing")
		return false
	# The negative for that sweep: the same membership test over values nobody may declare. The
	# colony is the one that matters -- an archetype claiming it would be a colonist spawned
	# outside the roster, with no needs and no place on the ledger -- and an invented side proves
	# the test is not simply answering true.
	for bad in [SimAllegiance.COLONY, "cannibals", ""]:
		if allowed.has(String(bad)):
			push_error("SCHEMA: an archetype declaring `%s` would be accepted by the enum" % String(bad))
			return false
	print("SCHEMA OK $defs/faction allows [%s], both of them declared factions, %d shipped archetype(s) inside it; the colony and an invented side refused" % [
		String(", ").join(PackedStringArray(allowed)), seen,
	])
	return true


# --- fixtures ---------------------------------------------------------------------------------

func _fixture() -> Dictionary:
	return {
		"seed": SEED,
		"tick_hz": 20,
		"map": {"width": 32, "height": 32, "walls": []},
		"player": {"id": 0, "x": 2.0, "y": 2.0, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	}


# check_m2_raiders.gd's arena: the combat modules over a blank map, with no district and no
# anchors, so a lane measures the fight rather than the layout.
func _arena() -> Variant:
	var w: Variant = World.new(_fixture())
	w.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	SimBoot.attach_kernel(w, SimTileMap.blank_map(32, 32))
	SimHealth.register_module(w)
	SimMelee.register_module(w)
	SimRanged.register_module(w)
	SimInventory.register_module(w)
	SimItems.register_module(w)
	SimNpcCombat.register_module(w)
	return w


# One person on a declared side: needs, an identity, a body, a facing, no `controlled`. This is
# what a settler will be when the camp lands -- a colonist-shaped body whose `allegiance.faction`
# says otherwise -- and it is built here rather than spawned from content on purpose, because
# nothing in the shipped tree makes a settler yet and this slice is not the one that changes that.
func _person(w: Variant, x: float, y: float, faction: String, id: String) -> int:
	var ent: int = int(w.entities.spawn())
	w.components.set_component(ent, "position", {"x": x, "y": y})
	w.components.set_component(ent, "velocity", {"dx": 0.0, "dy": 0.0})
	w.components.set_component(ent, "facing", {"radians": 0.0})
	w.components.set_component(ent, "identity", {"id": id, "name": id, "traits": []})
	SimAllegiance.attach(w, ent, faction)
	SimHealth.make_survivor_body(w, ent)
	SimHealth.make_stamina(w, ent)
	SimInventory.make_inventory(w, ent)
	SimNeeds.attach(w, ent)
	return ent


func _wound_count(world: Variant, ent: int) -> int:
	var inj: Variant = world.components.get_component(ent, "injuries")
	if not (inj is Dictionary):
		return 0
	return ((inj as Dictionary).get("wounds", []) as Array).size()


func _distance(world: Variant, a: int, b: int) -> float:
	var pa: Variant = world.components.get_component(a, "position")
	var pb: Variant = world.components.get_component(b, "position")
	if not (pa is Dictionary) or not (pb is Dictionary):
		return 1e12
	var dx: float = float((pb as Dictionary)["x"]) - float((pa as Dictionary)["x"])
	var dy: float = float((pb as Dictionary)["y"]) - float((pa as Dictionary)["y"])
	return sqrt(dx * dx + dy * dy)
