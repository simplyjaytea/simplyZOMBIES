extends SceneTree
# Raiders: a hostile band of people at the gate.
#
# The slice's claim is that a raider is a *human enemy* built out of machinery the colony already
# had, so this gate is mostly about proving the seams hold rather than about new arithmetic. Six
# things have to be true, and each of them carries a true positive AND a true negative -- the
# convention check_ban_health_bar.gd set, and the one that matters most here: "the colony does not
# shoot at raiders" would pass perfectly against a colony that shoots at nothing, and "a raid was
# not drawn tonight" passes forever against a director that can never draw one.
#
# The dead-socket rule gets particular attention. `allegiance.faction` is the field this slice
# adds, and the cheap way to gate it -- assert `faction_of` returns "raiders" -- would prove only
# that a getter works. So BLOOD's negative control flips that one field to "colony" on a body that
# is otherwise identical and requires the fight to stop. If anything ever reads the `raider`
# component instead of the declared faction, that assertion goes red.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimAllegiance = preload("res://sim/modules/allegiance.gd")
const SimDirector = preload("res://sim/modules/director.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimNpcCombat = preload("res://sim/modules/npc_combat.gd")
const SimRaiders = preload("res://sim/modules/raiders.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const Appearance = preload("res://presentation/appearance.gd")
const Palette = preload("res://presentation/palette.gd")
const Clock = preload("res://sim/time/clock.gd")

const SEED: int = 20260805
const MAP_TILES: int = 64
# Long enough for a band placed on a district edge to cross a 64 m district at 1.5 m/s and still
# leave room for the assertion to be about the approach rather than about the last metre.
const APPROACH_TICKS: int = 1200
const ARENA_TICKS: int = 900


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _the_archetypes_are_well_formed() and ok
	ok = _a_raid_arrives_at_a_legal_edge() and ok
	ok = _grace_holds_before_the_first_raid_day() and ok
	ok = _the_band_closes_on_the_colony() and ok
	ok = _blood_is_drawn_both_ways() and ok
	ok = _zombies_treat_a_raider_as_prey() and ok
	ok = _the_seed_decides_the_band() and ok
	ok = _a_dead_raider_leaves_the_district_and_its_kit() and ok
	ok = _a_raider_is_not_on_the_colony_ledger() and ok
	if ok:
		print("M2_RAIDERS_OK archetypes draw grace approach blood prey seed death ledger")
		quit(0)
	else:
		push_error("M2_RAIDERS_FAIL")
		quit(1)


# --- content ---------------------------------------------------------------------------------

# Everything the shallow validator cannot reach. `content_validator.gd` checks top-level types,
# enums and patterns and rejects unexpected top-level keys; it does not recurse, so a kit naming
# an item that does not exist, an aptitude outside SimAptitudes' clamp, or a malformed tint would
# all load clean and fail at play time. This is the recursion.
func _the_archetypes_are_well_formed() -> bool:
	var w: Variant = World.new(_fixture())
	var pool: Array[Dictionary] = SimRaiders.types(w)
	if pool.size() < 2:
		push_error("only %d raider archetypes in the tree -- the weighted draw has nothing to choose between" % pool.size())
		return false
	var hex := RegEx.new()
	hex.compile("^#[0-9a-f]{6}$")
	var tints: Dictionary = {}
	var armed: int = 0
	for entry in pool:
		var id: String = String(entry.get("id", ""))
		if String(entry.get("allegiance", "")) != SimAllegiance.RAIDERS:
			push_error("%s declares allegiance '%s', not '%s'" % [id, str(entry.get("allegiance", "")), SimAllegiance.RAIDERS])
			return false
		var kit: Variant = entry.get("kit", [])
		if not (kit is Array) or (kit as Array).is_empty():
			push_error("%s carries no kit -- an unarmed raider is a pedestrian" % id)
			return false
		var has_weapon: bool = false
		var needs_ammo: String = ""
		var carries: Dictionary = {}
		for row in kit as Array:
			# The two shapes a kit row may take, recursed because the shallow validator cannot.
			var item_id: String = ""
			if row is Dictionary:
				var r: Dictionary = row as Dictionary
				for k in r.keys():
					if not ["item", "count"].has(String(k)):
						push_error("%s kit row has unknown key '%s'" % [id, str(k)])
						return false
				item_id = String(r.get("item", ""))
				# `is int` is the wrong test and cost a red run here: Godot's JSON parser hands
				# every number back as a float, so a schema-perfect `"count": 16` arrives as 16.0.
				# content_validator._type_ok answers "integer" the same way -- a whole number,
				# whatever type carries it.
				if r.has("count") and not _whole_at_least(r["count"], 1):
					push_error("%s kit row for %s has count %s, which is not a positive whole number" % [id, item_id, str(r["count"])])
					return false
			else:
				item_id = String(row)
			if SimItems.content_entry(w, "item", item_id) == null:
				push_error("%s kit names %s, which is not in the item registry" % [id, item_id])
				return false
			carries[item_id] = true
			var probe: int = SimItems.spawn_item(w, item_id, {"tier": "scavenged"})
			var ranged: Variant = SimItems.ranged_profile_of(w, probe)
			if SimItems.melee_profile_of(w, probe) != null or ranged != null:
				has_weapon = true
			if ranged is Dictionary and not String((ranged as Dictionary).get("ammo", "")).is_empty():
				needs_ammo = String((ranged as Dictionary)["ammo"])
		if not has_weapon:
			push_error("%s carries nothing that melee.gd or ranged.gd would recognise as a weapon" % id)
			return false
		# A weapon that eats ammunition has to arrive with some, and with more than the one round
		# `spawn_item` gives an undeclared stack -- otherwise the archetype fires once and then
		# reloads for the rest of the night, which is a raider that looks armed and is not.
		if not needs_ammo.is_empty():
			if not carries.has(needs_ammo):
				push_error("%s carries a weapon chambered for %s and none of it" % [id, needs_ammo])
				return false
			var carried: int = _carried_count(w, id, needs_ammo)
			if carried < 8:
				push_error("%s arrives with %d rounds of %s -- a magazine is 8" % [id, carried, needs_ammo])
				return false
		armed += 1
		var apt: Variant = entry.get("aptitudes", {})
		if apt is Dictionary:
			for k in ["str", "dex", "con"]:
				if not (apt as Dictionary).has(k):
					continue
				var v: int = int((apt as Dictionary)[k])
				if v < 3 or v > 8:
					push_error("%s aptitude %s=%d is outside SimAptitudes' 3..8 clamp" % [id, k, v])
					return false
		var look: Variant = entry.get("appearance", {})
		if look is Dictionary and (look as Dictionary).has("tint"):
			var t: String = String((look as Dictionary)["tint"])
			if hex.search(t) == null:
				push_error("%s appearance.tint '%s' is not #rrggbb lowercase" % [id, t])
				return false
			tints[t] = true
	# Information stays scarce: which raider is carrying the gun is not something a look across a
	# street may answer, so every archetype wears the same colour. A second tint here would be a
	# free read on the band's loadout.
	if tints.size() > 1:
		push_error("raider archetypes declare %d different tints %s -- a glance must not say which one has the gun" % [tints.size(), str(tints.keys())])
		return false

	# And the anonymity rule at a glimpse, asserted where it is decided rather than where it is
	# drawn: at Peripheral detail main.gd draws one disc of `radius` and nothing else, so a
	# raider's radius has to be a survivor's. A wanderer's would tell the player, from a shape in
	# the dark, that it is not one of theirs.
	var raider_look: Dictionary = Appearance.for_entity(w, {"raider": true, "cid": String(pool[0].get("id", ""))})
	var survivor_look: Dictionary = Appearance.for_entity(w, {"unique": true, "cid": "survivor.unique.mara"})
	var zombie_look: Dictionary = Appearance.for_entity(w, {"ztype": "zombie.shambler"})
	if float(raider_look["radius"]) != float(survivor_look["radius"]):
		push_error("a raider glimpse is %.1f px and a survivor glimpse is %.1f px -- the shapes must be indistinguishable" % [float(raider_look["radius"]), float(survivor_look["radius"])])
		return false
	if float(zombie_look["radius"]) == float(survivor_look["radius"]):
		push_error("a zombie and a survivor draw at the same radius, so the radius assertion above proves nothing")
		return false
	# The declared tint reaches the renderer, and an archetype that declares none falls back to
	# the role colour rather than to a zombie's.
	var declared: Color = Color(String((pool[0].get("appearance", {}) as Dictionary)["tint"]))
	if (raider_look["tint"] as Color) != declared:
		push_error("for_entity ignored the content tint: %s != %s" % [str(raider_look["tint"]), str(declared)])
		return false
	var undeclared: Dictionary = Appearance.for_entity(w, {"raider": true, "cid": "raider.does_not_exist"})
	if (undeclared["tint"] as Color) != Palette.COLOURS["raider"]:
		push_error("an unknown raider archetype must fall back to the raider role colour, got %s" % str(undeclared["tint"]))
		return false
	print("ARCHETYPES OK %d entries, all armed, one shared tint %s, glimpse radius %.0f == survivor" % [armed, str(tints.keys()), float(raider_look["radius"])])
	return true


# --- the draw --------------------------------------------------------------------------------

# A post-grace night sends a band, and it arrives somewhere a band is allowed to arrive: on a
# district edge, off the gates, outside GATE_EXCLUSION, and never inside the annex. Those are
# `_legal_tile`'s promises, made to zombies first; a raider walking out of the player's own
# kitchen would break the same fairness rule for the same reason.
func _a_raid_arrives_at_a_legal_edge() -> bool:
	var w: Variant = SimBoot.playable(SEED, MAP_TILES)["world"]
	var gate_a: Vector2i = SimTileMap.gate_a(w.tilemap)
	var gate_b: Vector2i = SimTileMap.gate_b(w.tilemap)
	var annex: Rect2i = SimTileMap.annex_rect(w.tilemap)
	if gate_a.x < 0 or gate_b.x < 0 or annex.size.x <= 0:
		push_error("the booted district names no gates or annex, so legality is unmeasurable")
		return false
	var raids: int = 0
	var judged: int = 0
	var sizes: Dictionary = {}
	for day in range(SimDirector.RAID_FIRST_DAY, SimDirector.RAID_FIRST_DAY + 60):
		var before: Array[int] = w.components.query(["raider"])
		var raid: Variant = _run_night(w, day)
		if not (raid is Dictionary):
			push_error("day %d passed without the director saying anything about a raid -- rule 5 is that its decisions are observable" % day)
			return false
		if String((raid as Dictionary).get("reason", "")).is_empty():
			push_error("day %d: a raid decision with no stated reason" % day)
			return false
		var arrived: Array[Vector2i] = _new_raider_tiles(w, before)
		if arrived.size() != int((raid as Dictionary)["size"]):
			push_error("day %d: the director announced a band of %d and %d arrived" % [day, int((raid as Dictionary)["size"]), arrived.size()])
			return false
		if not arrived.is_empty():
			raids += 1
			sizes[arrived.size()] = int(sizes.get(arrived.size(), 0)) + 1
			if arrived.size() < SimDirector.RAID_BAND_MIN or arrived.size() > SimDirector.RAID_BAND_MAX:
				push_error("band of %d, declared range is %d..%d" % [arrived.size(), SimDirector.RAID_BAND_MIN, SimDirector.RAID_BAND_MAX])
				return false
			for tile in arrived:
				judged += 1
				if not _legal_entry(w, tile, gate_a, gate_b, annex):
					return false
		_cull_raiders(w)
	if raids < 1:
		push_error("sixty post-grace nights and not one raid -- the draw is unreachable, so nothing above was judged")
		return false
	if judged < 1:
		push_error("no entry tile was judged, so the legality assertion is vacuous")
		return false
	print("DRAW OK %d raids over 60 nights, %d entry tiles all legal, band sizes %s" % [raids, judged, str(sizes)])
	return true


# The true negative for the schedule. Before RAID_FIRST_DAY nothing arrives, the director says
# why, and -- the half that makes this an assertion rather than a tautology -- the raid stream is
# not touched at all, so grace is a refusal rather than a silent roll.
func _grace_holds_before_the_first_raid_day() -> bool:
	var w: Variant = SimBoot.playable(SEED, MAP_TILES)["world"]
	var nights: int = 0
	for day in range(1, SimDirector.RAID_FIRST_DAY):
		var raid: Variant = _run_night(w, day)
		if not (raid is Dictionary):
			push_error("day %d said nothing about a raid" % day)
			return false
		nights += 1
		if String((raid as Dictionary)["reason"]) != "grace":
			push_error("day %d, before RAID_FIRST_DAY %d, gave reason '%s'" % [day, SimDirector.RAID_FIRST_DAY, String((raid as Dictionary)["reason"])])
			return false
		if int((raid as Dictionary)["size"]) != 0:
			push_error("day %d sent a band of %d during grace" % [day, int((raid as Dictionary)["size"])])
			return false
		if SimRaiders.live_count(w) != 0:
			push_error("day %d: %d raiders standing in the district during grace" % [day, SimRaiders.live_count(w)])
			return false
	if nights < 1:
		push_error("RAID_FIRST_DAY is %d, so grace covers no nights and this assertion judged nothing" % SimDirector.RAID_FIRST_DAY)
		return false
	if (w.rng.names as Array).has(SimDirector.RAID_STREAM):
		push_error("the '%s' stream was opened during grace -- a refused raid must not spend randomness, or the schedule moves every campaign's rolls" % SimDirector.RAID_STREAM)
		return false
	print("GRACE OK %d nights refused, reason 'grace', stream untouched" % nights)
	return true


# --- the approach ----------------------------------------------------------------------------

# A band walks at the colony. Measured as the minimum distance from any raider to the annex rect,
# which is the thing they are coming for -- and required to fall by a real margin rather than to
# merely not rise, because a raider drifting one tile would satisfy "strictly decreases".
func _the_band_closes_on_the_colony() -> bool:
	# Every seed the balance harness runs, not just the canonical one. A generated district sites
	# its own colony, so "the gate is reachable from the edge the director picked" is a claim about
	# the *generator* as much as about the walk -- and a band that spawns on a seed whose gate has
	# no route would stand at the district edge for the whole campaign with nothing reporting it.
	var closed: Array[String] = []
	for seed_value in [20260805, 404, 31337, 90210]:
		var w: Variant = SimBoot.playable(int(seed_value), MAP_TILES)["world"]
		var annex: Rect2i = SimTileMap.annex_rect(w.tilemap)
		if annex.size.x <= 0:
			push_error("seed %d booted a district with no annex to walk at" % int(seed_value))
			return false
		var band: Array[int] = _place_band(w, 3)
		if band.is_empty():
			push_error("seed %d: could not place a band on a district edge" % int(seed_value))
			return false
		var before: float = _closest_to_annex(w, band, annex)
		for _t in APPROACH_TICKS:
			w.step()
		var after: float = _closest_to_annex(w, band, annex)
		closed.append("%d: %.1f -> %.1f" % [int(seed_value), before, after])
		# 1.5 m/s over 1200 ticks (60 s) is 90 m of walking; the district is 64 m across. A tenth
		# of that is a floor no drift, no wall-following detour and no halt at the first shambler
		# could reach by accident, and it is deliberately far below what a clear run covers.
		var floor_metres: float = 9.0
		if before - after < floor_metres:
			push_error("seed %d: the band closed %.1f m in %d ticks (from %.1f to %.1f), floor is %.1f" % [
				int(seed_value), before - after, APPROACH_TICKS, before, after, floor_metres,
			])
			return false

	# The negative control: the same raiders on a map with no gate and no annex have nothing to
	# walk at, and stand still. Without this, "they moved" would pass against a module that
	# pushed every raider in a fixed direction and never looked at the colony at all.
	var w2: Variant = _arena()
	var idle: int = SimRaiders.spawn(w2, 16.0, 16.0, "raider.scav")
	if idle < 0:
		push_error("could not spawn a raider into the bare arena")
		return false
	SimRaiders.register_module(w2)
	var start: Variant = (w2.components.get_component(idle, "position") as Dictionary).duplicate()
	for _t in 400:
		w2.step()
	var now: Dictionary = w2.components.get_component(idle, "position") as Dictionary
	var drift: float = sqrt((float(now["x"]) - float(start["x"])) ** 2.0 + (float(now["y"]) - float(start["y"])) ** 2.0)
	if drift > 0.5:
		push_error("a raider on an anchorless map wandered %.2f m -- the approach is not reading the colony" % drift)
		return false
	print("APPROACH OK %d ticks, metres to the annex per seed [%s]; anchorless drift %.2f m" % [
		APPROACH_TICKS, String("; ").join(PackedStringArray(closed)), drift,
	])
	return true


# --- the fight -------------------------------------------------------------------------------

# Both directions, in one arena: a raider cuts a colonist and the colonist cuts back. Counted off
# `attack.connected` -- the channel every melee blow in the game publishes -- and de-duplicated by
# entity id where deaths are involved, because `entity.killed` fires more than once for the same
# individual (health.gd on a destroyed part, infection.gd on a put-down and again on turning).
#
# The negative control is the whole point of the lane: the identical two bodies, with the raider's
# `allegiance.faction` flipped to "colony" and *nothing else changed*, must not fight at all. That
# is what proves the declared field is what hostility reads, rather than the mere presence of a
# `raider` component.
func _blood_is_drawn_both_ways() -> bool:
	var hot: Dictionary = _duel(SimAllegiance.RAIDERS)
	if int(hot["raider_hits"]) < 1:
		push_error("the raider never connected on the colonist in %d ticks" % ARENA_TICKS)
		return false
	if int(hot["colonist_hits"]) < 1:
		push_error("the colonist never connected on the raider in %d ticks" % ARENA_TICKS)
		return false
	if int(hot["raider_wounds"]) < 1 or int(hot["colonist_wounds"]) < 1:
		push_error("blows landed but left no wounds: raider inflicted %d, colonist inflicted %d" % [int(hot["raider_wounds"]), int(hot["colonist_wounds"])])
		return false
	if int(hot["deaths"]) < 1:
		push_error("a duel to %d ticks with two armed people killed nobody -- the lane is measuring a stalemate" % ARENA_TICKS)
		return false

	var truce: Dictionary = _duel(SimAllegiance.COLONY)
	if int(truce["raider_hits"]) != 0 or int(truce["colonist_hits"]) != 0:
		push_error("two bodies on the same declared side traded %d/%d blows -- hostility is not reading allegiance.faction" % [int(truce["raider_hits"]), int(truce["colonist_hits"])])
		return false
	print("BLOOD OK raider %d hits / %d wounds, colonist %d hits / %d wounds, %d dead; same-faction truce %d/%d" % [
		int(hot["raider_hits"]), int(hot["raider_wounds"]), int(hot["colonist_hits"]), int(hot["colonist_wounds"]),
		int(hot["deaths"]), int(truce["raider_hits"]), int(truce["colonist_hits"]),
	])
	return true


# One colonist with a knife, one raider with whatever their archetype carries, 1.2 m apart, with
# the colony's own combat intake driving both sides. `faction` is the only thing that varies.
func _duel(faction: String) -> Dictionary:
	var w: Variant = _arena()
	SimWounds.register_module(w)
	var colonist: int = _colonist(w, 10.0, 10.0)
	SimInventory.equip(w, colonist, SimItems.spawn_item(w, "item.knife.kitchen", {"tier": "scavenged"}))
	var raider: int = SimRaiders.spawn(w, 11.2, 10.0, "raider.scav")
	SimAllegiance.attach(w, raider, faction)
	w.events.drain()
	var out: Dictionary = {"raider_hits": 0, "colonist_hits": 0, "raider_wounds": 0, "colonist_wounds": 0, "deaths": 0}
	# De-duplicated by entity id, in a Dictionary: `entity.killed` is published from more than one
	# place for the same individual, so counting the events would report several deaths for one
	# person -- and a Dictionary rather than a captured counter because GDScript lambdas capture
	# primitives by value, which is the trap that reads back as a number that never moved.
	var seen_dead: Dictionary = {}
	for _t in ARENA_TICKS:
		w.step()
		# Wounds are read off the `injuries` component rather than an event, because there is no
		# "a wound opened" event to read -- health.gd records the wound directly. Sampled every
		# tick and kept at its maximum, because a body that dies is despawned and its injuries go
		# with it, and a count taken at the end would read zero for whoever lost.
		out["raider_wounds"] = maxi(int(out["raider_wounds"]), _wound_count(w, colonist))
		out["colonist_wounds"] = maxi(int(out["colonist_wounds"]), _wound_count(w, raider))
		for e in w.events.drained:
			var ev: Dictionary = e as Dictionary
			match String(ev.get("type", "")):
				"attack.connected":
					if int(ev.get("attacker", -1)) == raider and int(ev.get("target", -1)) == colonist:
						out["raider_hits"] = int(out["raider_hits"]) + 1
					elif int(ev.get("attacker", -1)) == colonist and int(ev.get("target", -1)) == raider:
						out["colonist_hits"] = int(out["colonist_hits"]) + 1
				"entity.killed":
					var victim: int = int(ev.get("entity", -1))
					if seen_dead.has(victim):
						continue
					seen_dead[victim] = true
					out["deaths"] = int(out["deaths"]) + 1
	return out


# A whole number at or above `floor`, whatever type JSON handed it over as.
func _whole_at_least(v: Variant, floor_value: int) -> bool:
	if v is int:
		return int(v) >= floor_value
	if v is float:
		return float(v) == float(int(v)) and int(v) >= floor_value
	return false


# How much of `base_id` an actually-spawned raider of this archetype is holding. Asked of a real
# spawn rather than of the JSON, because what matters is what reaches the body: a count that the
# kit declares and `spawn_item` clamps away, or a stack that will not fit in the pack, would both
# read correctly here and be wrong in the district.
func _carried_count(world: Variant, type_id: String, base_id: String) -> int:
	var ent: int = SimRaiders.spawn(world, 4.0, 4.0, type_id)
	if ent < 0:
		return 0
	var n: int = 0
	for item in SimInventory.carried_items(world, ent):
		var base: Variant = world.components.get_component(int(item), "itemBase")
		if not (base is Dictionary) or String((base as Dictionary).get("baseId", "")) != base_id:
			continue
		var stack: Variant = world.components.get_component(int(item), "stack")
		n += int((stack as Dictionary).get("count", 1)) if stack is Dictionary else 1
	world.despawn(ent)
	return n


func _wound_count(world: Variant, ent: int) -> int:
	var inj: Variant = world.components.get_component(ent, "injuries")
	if not (inj is Dictionary):
		return 0
	return ((inj as Dictionary).get("wounds", []) as Array).size()


# --- prey ------------------------------------------------------------------------------------

# A zombie chases a raider, and claws them. Not "a raider is in a list" -- the shambler has to
# enter Pursue, cross the ground, and land a swipe, which is what makes `SimAllegiance.is_person`
# a read rather than a socket. The raider fighting back is the other half of the brief's clause
# and falls out of `enemies_of` on its own: a zombie is everybody's enemy.
#
# Geometry follows check_m2_swipe.gd's: 1.5 m apart, inside CONTACT_METRES, so the state machine
# reaches Pursue through its own Wander branch rather than being put there by hand.
#
# The negative control removes the `raider` component from an otherwise identical body -- same
# position, same emitter, same flesh, same machete. A shambler that still pursued it would mean
# prey is decided by something other than being a person; a shambler that pursued neither would
# mean the positive proved nothing.
# The two halves are in two arenas, and the reason is a measured one rather than a convenience.
# An armed raider keeps the shambler *staggered*: a machete carries staggerTicks 5 and the raider
# lands a blow every twelve to eighteen ticks, while SWIPE_FIRST_TICKS is twenty and a stagger
# resets it -- so the claw never finishes its wind-up. That is correct behaviour, not a bug, and
# the rule is to write the test around it rather than fudge a number until it passes. So the
# armed arena proves the raider fights the zombie back, and a second, disarmed arena proves the
# zombie eats a raider who cannot keep it off.
func _zombies_treat_a_raider_as_prey() -> bool:
	var armed: Dictionary = _prey_arena(true, true)
	if not bool(armed["pursued"]):
		push_error("no shambler entered Pursue against a raider 1.5 m away in %d ticks" % ARENA_TICKS)
		return false
	if float(armed["closed"]) < 0.8:
		push_error("the shambler noticed the raider but closed only %.2f m" % float(armed["closed"]))
		return false
	if int(armed["raider_hits"]) < 1:
		push_error("the raider never fought the shambler back -- a raider defends itself against zombies too")
		return false

	var bare: Dictionary = _prey_arena(true, false)
	if not bool(bare["pursued"]):
		push_error("no shambler pursued the disarmed raider")
		return false
	if int(bare["zombie_hits"]) < 1:
		push_error("the shambler pursued a raider who could not fight back and never laid a claw on them")
		return false

	var ignored: Dictionary = _prey_arena(false, false)
	if bool(ignored["pursued"]):
		push_error("a shambler pursued a body with no person marker on it -- prey is not being decided by is_person")
		return false
	if int(ignored["zombie_hits"]) != 0:
		push_error("a shambler clawed %d times at a body it was not pursuing" % int(ignored["zombie_hits"]))
		return false
	print("PREY OK armed: pursued, closed %.2f m, raider answered %d blows; disarmed: %d claws landed; unmarked body: no pursuit, no claws" % [
		float(armed["closed"]), int(armed["raider_hits"]), int(bare["zombie_hits"]),
	])
	return true


func _prey_arena(marked: bool, armed: bool) -> Dictionary:
	var w: Variant = _arena()
	SimShambler.register_module(w, SimTileMap.blank_map(32, 32))
	var raider: int = SimRaiders.spawn(w, 16.0, 16.0, "raider.scav")
	if not armed:
		SimInventory.unequip(w, raider, "primary")
	if not marked:
		# Everything else about this body is unchanged -- position, emitter, flesh, hands. Only
		# the marker that says "person" is gone.
		w.components.remove(raider, "raider")
	# Nobody else in the district, so the only thing a shambler could be chasing is the raider.
	var z: int = SimRoster.spawn_zombie(w, 17.5, 16.0, SimRoster.TYPE_SHAMBLER, w.rng.stream("shambler"))
	w.events.drain()
	var start: float = _distance(w, z, raider)
	var pursued: bool = false
	var closest: float = start
	var hits: Dictionary = {"zombie": 0, "raider": 0}
	for _t in ARENA_TICKS:
		w.step()
		var sd: Variant = w.components.get_component(z, "shambler")
		if sd is Dictionary and int((sd as Dictionary)["state"]) == SimShambler.ShamblerState["Pursue"]:
			pursued = true
		for e in w.events.drained:
			var ev: Dictionary = e as Dictionary
			if String(ev.get("type", "")) != "attack.connected":
				continue
			if int(ev.get("attacker", -1)) == z:
				hits["zombie"] = int(hits["zombie"]) + 1
			elif int(ev.get("attacker", -1)) == raider:
				hits["raider"] = int(hits["raider"]) + 1
		var body: Variant = w.components.get_component(z, "body")
		if not (body is Dictionary) or not SimHealth.is_alive(body as Dictionary):
			# The fight is over. Measuring past it would fold a corpse's stillness into the
			# distance the shambler covered while it was alive.
			break
		closest = minf(closest, _distance(w, z, raider))
	return {"pursued": pursued, "closed": start - closest, "zombie_hits": int(hits["zombie"]), "raider_hits": int(hits["raider"])}


# --- determinism ------------------------------------------------------------------------------

# Same seed, same band: the same tiles and the same archetypes, in the same order. And a second
# seed that does *not* produce the identical band, because "deterministic" passes for free
# against a director that always sends the same three men to the same corner.
func _the_seed_decides_the_band() -> bool:
	var a: String = _first_band(SEED)
	var b: String = _first_band(SEED)
	if a.is_empty():
		push_error("seed %d drew no raid inside the search window, so determinism was never judged" % SEED)
		return false
	if a != b:
		push_error("seed %d produced two different bands:\n  %s\n  %s" % [SEED, a, b])
		return false
	var distinct: Dictionary = {a: true}
	for other in [404, 31337, 90210]:
		var s: String = _first_band(int(other))
		if not s.is_empty():
			distinct[s] = true
	if distinct.size() < 2:
		push_error("every seed sent the identical band -- the seed is not reaching the raid draw")
		return false
	print("SEED OK repeatable within a seed, %d distinct bands across four seeds" % distinct.size())
	return true


# The first band a seed sends, as a canonical string: tile and archetype per member, sorted.
func _first_band(seed_value: int) -> String:
	var w: Variant = SimBoot.playable(seed_value, MAP_TILES)["world"]
	for day in range(SimDirector.RAID_FIRST_DAY, SimDirector.RAID_FIRST_DAY + 60):
		var before: Array[int] = w.components.query(["raider"])
		var raid: Variant = _run_night(w, day)
		if not (raid is Dictionary) or int((raid as Dictionary)["size"]) <= 0:
			continue
		var rows: Array[String] = []
		for ent in w.components.query(["raider", "position"]):
			if before.has(int(ent)):
				continue
			var pos: Dictionary = w.components.get_component(int(ent), "position") as Dictionary
			var rd: Dictionary = w.components.get_component(int(ent), "raider") as Dictionary
			rows.append("%d,%d:%s" % [floori(float(pos["x"])), floori(float(pos["y"])), String(rd.get("id", ""))])
		rows.sort()
		return String("|").join(PackedStringArray(rows)) + " from " + String((raid as Dictionary)["side"])
	return ""


# --- death ------------------------------------------------------------------------------------

# A dead raider leaves the world and leaves their weapon on the ground. Both halves matter and for
# different reasons: the kit falling is the only thing a raid leaves behind (nothing loots for the
# colony in this cut), and the body going is what keeps `RAID_LIVE_CAP` honest -- `components.query`
# does not check alive, so a raider corpse would sit in the raid budget forever.
func _a_dead_raider_leaves_the_district_and_its_kit() -> bool:
	var w: Variant = _arena()
	var raider: int = SimRaiders.spawn(w, 10.0, 10.0, "raider.scav")
	w.events.drain()
	if SimRaiders.live_count(w) != 1:
		push_error("one raider spawned and live_count says %d" % SimRaiders.live_count(w))
		return false
	var carried: Array[int] = SimInventory.carried_items(w, raider)
	if carried.is_empty():
		push_error("the raider carries nothing, so the dropped-kit assertion would be vacuous")
		return false
	var grounded_before: int = w.components.query(["itemBase", "position"]).size()
	# Destroy the head outright, which is health.gd's own lethal path, then step so `health.reap`
	# (cleanup/0) runs -- `events.publish` only queues, and handlers run at drain() at the end of
	# `world.step()`, so reading the result without stepping would see nothing.
	var body: Dictionary = w.components.get_component(raider, "body") as Dictionary
	body["head"] = 0.0
	SimHealth.finish_death(w, raider)
	w.step()
	if SimRaiders.live_count(w) != 0:
		push_error("a dead raider is still in the live count (%d) -- the raid cap would fill with corpses" % SimRaiders.live_count(w))
		return false
	if w.components.has_component(raider, "allegiance") or w.components.has_component(raider, "body"):
		push_error("the dead raider's components survived the despawn")
		return false
	var grounded_after: int = w.components.query(["itemBase", "position"]).size()
	if grounded_after <= grounded_before:
		push_error("the raider's kit did not fall: %d items on the ground before, %d after" % [grounded_before, grounded_after])
		return false
	print("DEATH OK live_count 1 -> 0, %d carried items became %d on the ground" % [carried.size(), grounded_after - grounded_before])
	return true


# --- the ledger -------------------------------------------------------------------------------

# Raiders do not eat at your table. Every one of these is a system that counts, feeds, employs or
# promotes the colony, and each is kept out by the absence of a component rather than by a special
# case somewhere -- which is exactly why it needs asserting: nothing would raise if a raider
# quietly acquired `needs` and started showing up as a survivor in the balance harness.
#
# The colonist beside them is the true positive. Without it "the raider has no needs" would pass
# against a world where nobody has needs at all.
func _a_raider_is_not_on_the_colony_ledger() -> bool:
	var w: Variant = _arena()
	var colonist: int = _colonist(w, 10.0, 10.0)
	var raider: int = SimRaiders.spawn(w, 14.0, 10.0, "raider.scav")
	w.events.drain()
	for component in ["needs", "identity", "jobPriorities", "recruit"]:
		if w.components.has_component(raider, component):
			push_error("a raider carries '%s' -- it would be counted, fed or employed as a colonist" % component)
			return false
	if not w.components.has_component(colonist, "needs"):
		push_error("the control colonist carries no 'needs', so the exclusions above prove nothing")
		return false
	# The two counts the balance harness actually reads. `_survivors_alive` is `needs` + `body`
	# minus corpses and recruits; a raid that raised it would have made every campaign report a
	# colony it did not have.
	if w.components.query(["needs", "body"]).size() != 1:
		push_error("%d bodies carry needs with a raider in the district; the colony is one person" % w.components.query(["needs", "body"]).size())
		return false
	# And they are on the other side of the fight, both ways round -- the symmetry `hostile` owes.
	if not SimAllegiance.hostile(w, colonist, raider) or not SimAllegiance.hostile(w, raider, colonist):
		push_error("colonist and raider are not mutually hostile")
		return false
	if SimAllegiance.hostile(w, colonist, colonist):
		push_error("a colonist is hostile to themselves")
		return false
	var enemies: Array[int] = SimAllegiance.enemies_of(w, colonist)
	if not enemies.has(raider):
		push_error("the raider is not in the colonist's enemy list %s" % str(enemies))
		return false
	if SimAllegiance.enemies_of(w, raider).has(raider):
		push_error("a raider is its own enemy")
		return false
	print("LEDGER OK raider carries no needs/identity/jobPriorities/recruit; colony count held at 1; hostility symmetric")
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


# The combat modules over a blank map, with no district and no anchors -- check_m2_npc_combat's
# arena, plus the raider approach where a lane needs it.
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


# A colony NPC: needs, a body, a facing, no `controlled`. check_m2_npc_combat's `_npc`, with the
# allegiance the shipped spawners now attach -- without it a raider's `enemies_of` would not
# find them, which is itself worth having written down here rather than discovered.
func _colonist(w: Variant, x: float, y: float) -> int:
	var ent: int = int(w.entities.spawn())
	w.components.set_component(ent, "position", {"x": x, "y": y})
	w.components.set_component(ent, "velocity", {"dx": 0.0, "dy": 0.0})
	w.components.set_component(ent, "facing", {"radians": 0.0})
	w.components.set_component(ent, "identity", {"id": "survivor.test", "name": "Test", "traits": []})
	SimAllegiance.attach(w, ent, SimAllegiance.COLONY)
	SimHealth.make_survivor_body(w, ent)
	SimHealth.make_stamina(w, ent)
	SimInventory.make_inventory(w, ent)
	SimNeeds.attach(w, ent)
	return ent


# --- helpers ----------------------------------------------------------------------------------

# Steps one dusk and returns the `director.raid` event it published, or null.
func _run_night(world: Variant, day: int) -> Variant:
	world.tick = Clock.tick_on_day(day, Clock.DAY_ENDS) - 1
	world.step()
	for e in world.events.drained:
		if String((e as Dictionary).get("type", "")) == "director.raid":
			return e
	return null


# Clears the band between nights. The component *and* the entity: `entities.despawn` does not
# consult `components.query`, so removing only the entity would leave every body in the raid's
# live count and every night after the second would be refused for the cap rather than drawn.
func _cull_raiders(world: Variant) -> void:
	for e in world.components.query(["raider"]):
		world.components.remove(int(e), "raider")
		world.entities.despawn(int(e))


func _new_raider_tiles(world: Variant, before: Array[int]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for e in world.components.query(["raider", "position"]):
		if before.has(int(e)):
			continue
		var pos: Variant = world.components.get_component(int(e), "position")
		if pos is Dictionary:
			out.append(Vector2i(floori(float((pos as Dictionary)["x"])), floori(float((pos as Dictionary)["y"]))))
	return out


func _legal_entry(world: Variant, tile: Vector2i, gate_a: Vector2i, gate_b: Vector2i, annex: Rect2i) -> bool:
	if annex.has_point(tile):
		push_error("a raider arrived inside the annex at %s" % str(tile))
		return false
	if tile == gate_a or tile == gate_b:
		push_error("a raider arrived standing on a gate at %s" % str(tile))
		return false
	for gate in [gate_a, gate_b]:
		var dx: float = float(tile.x) - float((gate as Vector2i).x)
		var dy: float = float(tile.y) - float((gate as Vector2i).y)
		if dx * dx + dy * dy < SimDirector.GATE_EXCLUSION * SimDirector.GATE_EXCLUSION:
			push_error("a raider arrived within %.0f m of a gate at %s" % [SimDirector.GATE_EXCLUSION, str(tile)])
			return false
	var w: int = int(world.tilemap.w)
	var h: int = int(world.tilemap.h)
	if tile.x > 2 and tile.x < w - 3 and tile.y > 2 and tile.y < h - 3:
		push_error("a raider arrived in the middle of the district at %s rather than walking in from an edge" % str(tile))
		return false
	return true


# A band on the first legal edge tile the director itself would use, so the approach lane starts
# where a drawn raid starts without having to wait for one to be drawn.
func _place_band(world: Variant, size: int) -> Array[int]:
	var sides: Array = SimDirector._edges_by_side(world)
	var out: Array[int] = []
	for side in sides:
		var pool: Array = side as Array
		if pool.size() < size:
			continue
		for i in size:
			var tile: Vector2i = pool[i]
			var ent: int = SimRaiders.spawn(world, float(tile.x) + 0.5, float(tile.y) + 0.5, "raider.scav")
			if ent >= 0:
				out.append(ent)
		return out
	return out


func _closest_to_annex(world: Variant, band: Array[int], annex: Rect2i) -> float:
	var best: float = 1e12
	for ent in band:
		var pos: Variant = world.components.get_component(int(ent), "position")
		if not (pos is Dictionary):
			continue
		var x: float = float((pos as Dictionary)["x"])
		var y: float = float((pos as Dictionary)["y"])
		var cx: float = clampf(x, float(annex.position.x), float(annex.position.x + annex.size.x))
		var cy: float = clampf(y, float(annex.position.y), float(annex.position.y + annex.size.y))
		best = minf(best, sqrt((x - cx) ** 2.0 + (y - cy) ** 2.0))
	return best


func _distance(world: Variant, a: int, b: int) -> float:
	var pa: Variant = world.components.get_component(a, "position")
	var pb: Variant = world.components.get_component(b, "position")
	if not (pa is Dictionary) or not (pb is Dictionary):
		return 1e12
	var dx: float = float((pb as Dictionary)["x"]) - float((pa as Dictionary)["x"])
	var dy: float = float((pb as Dictionary)["y"]) - float((pa as Dictionary)["y"])
	return sqrt(dx * dx + dy * dy)
