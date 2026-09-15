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
const SimChronicle = preload("res://sim/modules/chronicle.gd")
const SimDirector = preload("res://sim/modules/director.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimNpcCombat = preload("res://sim/modules/npc_combat.gd")
const SimPeople = preload("res://sim/modules/people.gd")
const SimRaiders = preload("res://sim/modules/raiders.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimRecruits = preload("res://sim/modules/recruits.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const Appearance = preload("res://presentation/appearance.gd")
const Palette = preload("res://presentation/palette.gd")
const Clock = preload("res://sim/time/clock.gd")
const ContentLoader = preload("res://platform/content_loader.gd")

const SEED: int = 20260805
const MAP_TILES: int = 64
# Long enough for a band placed on a district edge to cross a 64 m district at 1.5 m/s and still
# leave room for the assertion to be about the approach rather than about the last metre.
const APPROACH_TICKS: int = 1200
const ARENA_TICKS: int = 900

# How far above the brightest ground a body's composed luma has to sit to still read as a body.
# check_appearance.gd's GREY_CLEARANCE, by name and by value: the colonist rig is held to exactly
# this over the same six surface tints, and a raider wearing a wash is that question asked of a
# rig that is not achromatic. One number in two places rather than two numbers -- the comment is
# the link, since a gate may not preload another gate.
const GROUND_CLEARANCE: float = 0.06

# The `"raid"` stream's state after `_emit_band` places a band of four, measured on the
# pre-individuals tree with a throwaway driver on 2026-09-15 and pinned here. Two seeds, because
# one pin that happened to be the state of an untouched stream would say nothing about a second.
const RAID_PINS: Array[Dictionary] = [
	{"seed": 20260805, "after": 1359491022},
	{"seed": 404, "after": 1660534035},
]


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
	ok = _a_band_that_has_lost_withdraws() and ok
	ok = _the_person_pool_is_well_formed() and ok
	ok = _every_look_is_one_body_and_clears_the_street() and ok
	ok = _a_band_of_four_are_four_people() and ok
	ok = _a_raider_is_never_the_heir() and ok
	ok = _the_rolled_look_reaches_the_renderer() and ok
	ok = _a_look_carries_no_tell() and ok
	ok = _the_raid_stream_has_not_moved() and ok
	ok = _a_person_survives_a_save() and ok
	ok = _a_dead_raider_is_named_once() and ok
	if ok:
		print("M2_RAIDERS_OK archetypes draw grace approach blood prey seed death ledger withdraw pool looks distinct no-identity look-reader no-tell streams save chronicle")
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
	var looks: Dictionary = {}
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
		var armed_certain: bool = false
		var needs_ammo: String = ""
		var carries: Dictionary = {}
		for row in kit as Array:
			# The two shapes a kit row may take, recursed because the shallow validator cannot.
			var item_id: String = ""
			var certain: bool = true
			if row is Dictionary:
				var r: Dictionary = row as Dictionary
				for k in r.keys():
					if not ["item", "count", "chance"].has(String(k)):
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
				# The third shape, and the only one that can leave a raider without something: odds.
				if r.has("chance"):
					var chance: float = float(r["chance"])
					if chance <= 0.0 or chance > 1.0:
						push_error("%s kit row for %s declares chance %s, outside (0, 1] -- a row that can never arrive is a row nobody wrote" % [id, item_id, str(r["chance"])])
						return false
					certain = chance >= 1.0
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
				# One weapon has to be *certain*. A second one behind odds is a raider who
				# sometimes has a knife as well, which is the point of the odds; but an archetype
				# whose every armed row could roll away would walk pedestrians at your gate on
				# some seeds and raiders on others, and nothing else here would notice --
				# `has_weapon` only asks whether the archetype declares one at all.
				if certain:
					armed_certain = true
			if ranged is Dictionary and not String((ranged as Dictionary).get("ammo", "")).is_empty():
				needs_ammo = String((ranged as Dictionary)["ammo"])
		if not has_weapon:
			push_error("%s carries nothing that melee.gd or ranged.gd would recognise as a weapon" % id)
			return false
		if not armed_certain:
			push_error("%s declares weapons and every one of them is behind a chance -- an archetype's arms may not roll away" % id)
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
		# Aptitudes take two shapes since the individuals slice -- one number every body of the
		# archetype shares, or a two-element [min, max] rolled per body -- and both sit inside a
		# block the shallow validator does not open. `int([5, 7])` is not a cast GDScript makes
		# quietly either: it raises, so a range shipped without this arm would take the gate down
		# with a stack trace instead of a sentence.
		var apt: Variant = entry.get("aptitudes", {})
		if apt is Dictionary:
			for k in ["str", "dex", "con"]:
				if not (apt as Dictionary).has(k):
					continue
				var raw: Variant = (apt as Dictionary)[k]
				var bounds: Array = raw as Array if raw is Array else [raw, raw]
				if bounds.size() != 2:
					push_error("%s aptitude %s is %s -- a range is exactly [min, max]" % [id, k, str(raw)])
					return false
				if int(bounds[0]) > int(bounds[1]):
					push_error("%s aptitude %s range %s runs backwards" % [id, k, str(raw)])
					return false
				for bound in bounds:
					if not _whole_at_least(bound, 3) or int(bound) > 8:
						push_error("%s aptitude %s=%s is outside SimAptitudes\' 3..8 clamp" % [id, k, str(bound)])
						return false
		var look: Variant = entry.get("appearance", {})
		if not (look is Dictionary) or not (look as Dictionary).has("sprite"):
			push_error("%s declares no appearance.sprite -- the one shared body is the anonymity mechanism, not a nicety" % id)
			return false
		looks[String((look as Dictionary)["sprite"])] = true
		# The hex shape survives conditionally: no archetype declares a tint today (the shared
		# art draws unstained), but one that ever returns must still be well-formed rather than
		# a play-time surprise the shallow validator waves through.
		if (look as Dictionary).has("tint"):
			var t: String = String((look as Dictionary)["tint"])
			if hex.search(t) == null:
				push_error("%s appearance.tint '%s' is not #rrggbb lowercase" % [id, t])
				return false
	# Information stays scarce: which raider is carrying the gun is not something a look across a
	# street may answer, so every archetype wears the same body. A second sprite here would be a
	# free read on the band's loadout. The zero check is not paranoia -- the tint version of this
	# lane passed quietly on an empty set, which is the gate-that-cannot-fail hole.
	if looks.size() == 0:
		push_error("no archetype declared a look -- the shared-body assertion had nothing to judge")
		return false
	if looks.size() > 1:
		push_error("raider archetypes declare %d different bodies %s -- a glance must not say which one has the gun" % [looks.size(), str(looks.keys())])
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
	# The declared body reaches the renderer: the art resolves, draws unstained (no tint
	# declared, so `modulate_for` answers white), and every archetype hands back the *same*
	# Texture2D -- Appearance._cache holds one object per key, so `==` here is identity, and
	# the sharing property is asserted at the resolver rather than assumed from the JSON.
	if raider_look["texture"] == null:
		push_error("%s declares appearance.sprite and resolved no texture" % String(pool[0].get("id", "")))
		return false
	if (raider_look["tint"] as Color) != Color.WHITE:
		push_error("the shared raider body declares no tint and must draw white, got %s" % str(raider_look["tint"]))
		return false
	for other in pool:
		var other_look: Dictionary = Appearance.for_entity(w, {"raider": true, "cid": String((other as Dictionary).get("id", ""))})
		if other_look["texture"] != raider_look["texture"]:
			push_error("%s resolves a different texture from %s -- two bodies a glance can tell apart" % [String((other as Dictionary).get("id", "")), String(pool[0].get("id", ""))])
			return false
	var undeclared: Dictionary = Appearance.for_entity(w, {"raider": true, "cid": "raider.does_not_exist"})
	if (undeclared["tint"] as Color) != Palette.COLOURS["raider"]:
		push_error("an unknown raider archetype must fall back to the raider role colour, got %s" % str(undeclared["tint"]))
		return false
	print("ARCHETYPES OK %d entries, all armed, one shared body %s drawn unstained, glimpse radius %.0f == survivor" % [armed, str(looks.keys()), float(raider_look["radius"])])
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
		# The boot shamblers go before the band walks. This lane judges the *route* -- that the
		# gate the director picked is reachable from the edge -- and since every zombie has eyes
		# (the playable-state group's fifth piece) a wanderer sees a band at 12 m and closes on
		# it, and the band halts to fight at HALT_METRES; on seed 90210 that engagement began
		# within a few metres of the edge and the band "closed" 2.5 m in 1200 ticks. The fight is
		# PREY's assertion below, with its own arena. `world.despawn`, not `entities.despawn`.
		for zed in w.components.query(["shambler"]):
			w.despawn(int(zed))
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
	# This arena isolates pursuit and the claw -- `is_person` deciding prey, ground covered,
	# swipes landing. With GRABS_ENABLED shipping true (docs/23's flag record) a live grab pins
	# both bodies at arm's length, so "closed the distance" would read the pin rather than the
	# pursuit. The grab loop is switched off for the arena and the previous value restored --
	# the flag is a static shared by every world one gate process boots, and the grab loop has
	# its own gate (check_m2_contact.gd).
	var flag_was: bool = SimShambler.GRABS_ENABLED
	SimShambler.GRABS_ENABLED = false
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
	SimShambler.GRABS_ENABLED = flag_was
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
	return _arena_with({})


# The same arena over a content tree the caller has edited -- DISTINCT's negative boots the
# archetypes with their odds made certain and their ranges collapsed. An empty tree means "the
# shipped one", since `World` loads it itself when the fixture names none.
func _arena_with(tree: Dictionary) -> Variant:
	var fixture: Dictionary = _fixture()
	if not tree.is_empty():
		fixture["content_tree"] = tree
	var w: Variant = World.new(fixture)
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


# --- The playable state, slice 11: withdrawal --------------------------------------------------

# A band at its objective with nobody to fight leaves after WITHDRAW_AFTER_TICKS, walking back
# to where it came in, and is gone (`raid.withdrew`, one a body); a band with a colonist in
# reach stays; a band of four with three dead leaves at once.
func _a_band_that_has_lost_withdraws() -> bool:
	# An arena with a gate to walk at: the anchors are what `_objective` reads.
	var results: Dictionary = {}
	for case in ["alone", "engaged"]:
		var w: Variant = _arena()
		SimRaiders.register_module(w)
		w.tilemap.anchors = {"gate_a": {"x": 16, "y": 20}, "gate_b": {"x": 17, "y": 20}, "annex": {"x": 12, "y": 20, "w": 8, "h": 8}}
		var band: Array = []
		for i in 3:
			band.append(SimRaiders.spawn(w, 14.5 + float(i), 3.5, "raider.scav"))
		SimRaiders.stamp_band(w, band, 7)
		if case == "engaged":
			# A colonist standing at the gate, in reach and alive: something to fight.
			var colonist: int = int(w.entities.spawn())
			w.components.set_component(colonist, "position", {"x": 16.5, "y": 21.5})
			w.components.set_component(colonist, "velocity", {"dx": 0.0, "dy": 0.0})
			w.components.set_component(colonist, "facing", {"radians": 0.0})
			w.components.set_component(colonist, "identity", {"id": "survivor.test", "name": "Test", "traits": []})
			SimAllegiance.attach(w, colonist, SimAllegiance.COLONY)
			SimHealth.make_survivor_body(w, colonist)
		var withdrew: Array = []
		w.events.subscribe({"id": "check.withdrew-" + case, "type": "raid.withdrew", "handler": func(e: Dictionary) -> void:
			withdrew.append(int(e.get("entity", -1)))
		})
		var arrived_at: int = -1
		var gone_at: int = -1
		for t in SimRaiders.WITHDRAW_AFTER_TICKS + 2500:
			w.step()
			if arrived_at < 0 and int((w.components.get_component(int(band[0]), "raider") as Dictionary).get("arrivedAtTick", -1)) >= 0:
				arrived_at = t
			if SimRaiders.live_count(w) == 0:
				gone_at = t
				break
		results[case] = {"arrived": arrived_at, "gone": gone_at, "withdrew": withdrew.size(), "live": SimRaiders.live_count(w)}
	var alone: Dictionary = results["alone"]
	var engaged: Dictionary = results["engaged"]
	if int(alone["arrived"]) < 0:
		push_error("WITHDRAW: the band never arrived at the gate (%s)" % str(alone))
		return false
	if int(alone["gone"]) < 0 or int(alone["withdrew"]) != 3:
		push_error("WITHDRAW: a band with nobody to fight did not leave (%s)" % str(alone))
		return false
	if int(alone["gone"]) < int(alone["arrived"]) + SimRaiders.WITHDRAW_AFTER_TICKS:
		push_error("WITHDRAW: the band left %d ticks after arriving, before the %d-tick clock" % [int(alone["gone"]) - int(alone["arrived"]), SimRaiders.WITHDRAW_AFTER_TICKS])
		return false
	if int(engaged["live"]) != 3 or int(engaged["withdrew"]) != 0:
		push_error("WITHDRAW: a band with a colonist in reach left (%s)" % str(engaged))
		return false
	# Half strength: four, three dead, the last one goes at once.
	var w2: Variant = _arena()
	SimRaiders.register_module(w2)
	w2.tilemap.anchors = {"gate_a": {"x": 16, "y": 20}, "gate_b": {"x": 17, "y": 20}, "annex": {"x": 12, "y": 20, "w": 8, "h": 8}}
	var four: Array = []
	for i in 4:
		four.append(SimRaiders.spawn(w2, 13.5 + float(i), 3.5, "raider.scav"))
	SimRaiders.stamp_band(w2, four, 9)
	for _t in 50:
		w2.step()
	for i in 3:
		(w2.components.get_component(int(four[i]), "body") as Dictionary)["head"] = 0.0
		SimHealth.finish_death(w2, int(four[i]))
	var left: Array = []
	w2.events.subscribe({"id": "check.withdrew-half", "type": "raid.withdrew", "handler": func(e: Dictionary) -> void:
		left.append(int(e.get("entity", -1)))
	})
	var gone2: int = -1
	for t in 600:
		w2.step()
		if SimRaiders.live_count(w2) == 0:
			gone2 = t
			break
	if gone2 < 0 or left.size() != 1 or int(left[0]) != int(four[3]):
		push_error("WITHDRAW: the last of four did not leave at once when three fell (gone=%d left=%s)" % [gone2, str(left)])
		return false
	print("WITHDRAW OK a band alone at the gate arrived at tick %d and was gone at %d (3 withdrew); with a colonist in reach it stayed; the last of four left within %d ticks of the other three falling" % [int(alone["arrived"]), int(alone["gone"]), gone2])
	return true


# --- who they are ------------------------------------------------------------------------------

# POOL: the generator block behind `raider.person`, and every field of that record having
# somewhere to come from. `content/colony/` has no schema and no validator type on purpose
# (content_validator.gd's UNSCHEMA_EXEMPT), so nothing but this lane ever looks at its shape --
# the same argument the archetype lane above makes about nested blocks, one directory further out.
func _the_person_pool_is_well_formed() -> bool:
	var w: Variant = World.new(_fixture())
	var pool: Dictionary = SimPeople.pool(w, SimRaiders.PEOPLE_POOL_ID)
	if pool.is_empty():
		push_error("POOL: no generator block carries id '%s' -- SimPeople.roll would fall back to one of everything and a band would be four men called Sam Doe" % SimRaiders.PEOPLE_POOL_ID)
		return false
	for key in ["given", "surnames", "features", "looks", "ageBands", "backstories"]:
		var v: Variant = pool.get(key, null)
		if not (v is Array) or (v as Array).is_empty():
			push_error("POOL: the raider generator declares no %s" % key)
			return false
	# A band of four has to be able to *be* four people. With a pool smaller than this the
	# DISTINCT lane below would be measuring the pool rather than the roll.
	if (pool["given"] as Array).size() < 8 or (pool["surnames"] as Array).size() < 8:
		push_error("POOL: %d given names x %d surnames is too small a pool for a band of four to differ by" % [(pool["given"] as Array).size(), (pool["surnames"] as Array).size()])
		return false
	# The dead-socket question, asked of content: `age` reaches the player only as an age band's
	# prose and `backstoryId` only as a backstory's line, so a band with no prose or a story with
	# no line is a field of the record nothing can ever say out loud.
	for band in pool["ageBands"] as Array:
		if not (band is Dictionary):
			push_error("POOL: an age band is not an object: %s" % str(band))
			return false
		var b: Dictionary = band as Dictionary
		if String(b.get("prose", "")).is_empty():
			push_error("POOL: age band '%s' carries no prose, so a raider's age would reach nobody" % String(b.get("id", "?")))
			return false
		if int(b.get("min", 0)) <= 0 or int(b.get("max", 0)) < int(b.get("min", 0)):
			push_error("POOL: age band '%s' has no usable range (%s..%s)" % [String(b.get("id", "?")), str(b.get("min")), str(b.get("max"))])
			return false
	for story in pool["backstories"] as Array:
		if not (story is Dictionary):
			push_error("POOL: a backstory is not an object: %s" % str(story))
			return false
		var st: Dictionary = story as Dictionary
		if String(st.get("id", "")).is_empty() or String(st.get("line", "")).is_empty():
			push_error("POOL: backstory %s has no id or no line, so `backstoryId` would read as nothing" % str(st))
			return false
	# The scan's own true negative: `pool` finds a block by id and nothing else, so an id nothing
	# declares must come back empty rather than as the first block that happens to have one.
	if not SimPeople.pool(w, "colony.generator.nobody").is_empty():
		push_error("POOL: an id nothing declares came back with a block -- the scan is not matching on the id")
		return false
	# And the prose it all feeds: a clause built from a fabricated record says the name, the
	# story, the age in words and the features, and carries no digit. A record with no name says
	# nothing at all, which is what keeps a nameless body out of the chronicle.
	var first_story: Dictionary = (pool["backstories"] as Array)[0] as Dictionary
	var first_band: Dictionary = (pool["ageBands"] as Array)[0] as Dictionary
	var probe: Dictionary = {
		"name": "Ada Kovac",
		"age": int(first_band.get("min", 20)),
		"features": ["a split lip"],
		"look": "",
		"backstoryId": String(first_story.get("id", "")),
	}
	var clause: String = SimRaiders.person_clause(w, probe)
	for needle in ["Ada Kovac", String(first_story.get("line", "")), String(first_band.get("prose", "")), "a split lip"]:
		if clause.find(String(needle)) < 0:
			push_error("POOL: the clause '%s' does not carry '%s' -- that field of the record reaches nobody" % [clause, String(needle)])
			return false
	if not _digits(clause).is_empty():
		push_error("POOL: the clause '%s' carries the digits '%s', and the chronicle it feeds is on the HUD" % [clause, _digits(clause)])
		return false
	probe["name"] = ""
	if not SimRaiders.person_clause(w, probe).is_empty():
		push_error("POOL: a record with no name still composed a clause")
		return false
	print("POOL OK %d x %d names, %d features, %d looks, %d age bands all with prose, %d backstories all with a line; clause '%s'" % [
		(pool["given"] as Array).size(), (pool["surnames"] as Array).size(), (pool["features"] as Array).size(),
		(pool["looks"] as Array).size(), (pool["ageBands"] as Array).size(), (pool["backstories"] as Array).size(), clause,
	])
	return true


# LOOKS: the ids the pool names are real look entries and every one of them wears the one shared
# raider body -- and the second half of the lane is the measurement that says why none of them
# carries a wash, which is the half a reader will otherwise ask about.
#
# `raider_drab` is at the floor of the palette's ground-contrast guard already: tools/sprites'
# palette.py calls it "as dark as the drab can go and still read as a body rather than a hole in
# the street". A tint is a multiply, so a look could only darken it, and the composed median of
# this rig sits a few thousandths above the street as it is. So the per-body variation a raider
# actually shows is what they are *wearing* -- the kit rows with odds on them, which draw on the
# pawn -- and the look id stays the hook a per-body picture attaches to when the art exists. The
# numbers below are what makes that a measurement rather than an opinion; they are printed, so
# the day the rig is re-authored lighter the headroom is on the line where it is decided.
func _every_look_is_one_body_and_clears_the_street() -> bool:
	var w: Variant = World.new(_fixture())
	var pool: Dictionary = SimPeople.pool(w, SimRaiders.PEOPLE_POOL_ID)
	var looks: Array = pool.get("looks", []) as Array
	if looks.size() < 2:
		push_error("LOOKS: %d look in the pool -- a look that cannot vary is a field nothing reads" % looks.size())
		return false
	var types: Array[Dictionary] = SimRaiders.types(w)
	if types.is_empty():
		push_error("LOOKS: no archetypes, so there is no shared body to compare against")
		return false
	var shared_sprite: String = String((types[0].get("appearance", {}) as Dictionary).get("sprite", ""))
	var body: Texture2D = Appearance.resolve(shared_sprite)
	if body == null:
		push_error("LOOKS: the shared body '%s' resolved no texture" % shared_sprite)
		return false
	var img: Image = body.get_image()
	var plain: float = _median_composed_luma(img, Color.WHITE)
	var floor_luma: float = _brightest_surface() + GROUND_CLEARANCE
	for look_v in looks:
		var look_id: String = String(look_v)
		var block: Dictionary = Appearance.of_content(w, "raider", look_id)
		if block.is_empty():
			push_error("LOOKS: the pool names '%s' and no content entry carries that id" % look_id)
			return false
		if String(block.get("sprite", "")) != shared_sprite:
			push_error("LOOKS: '%s' draws '%s' where the archetypes draw '%s' -- a per-look body is the same free read on the band a per-archetype one would be" % [look_id, String(block.get("sprite", "")), shared_sprite])
			return false
		# No tint, and that is the finding rather than an omission: see the arithmetic below.
		if block.has("tint"):
			var composed: float = _median_composed_luma(img, Color(String(block["tint"])))
			if composed < floor_luma:
				push_error("LOOKS: '%s' composes to median luma %.4f, under the street's %.4f -- that raider is a hole in the road" % [look_id, composed, floor_luma])
				return false
		# The renderer hands the look over: the shared texture, drawn unstained. Texture identity,
		# because Appearance._cache holds one object per key.
		var drawn: Dictionary = Appearance.for_entity(w, {"raider": true, "cid": look_id})
		if drawn["texture"] != Appearance.resolve(shared_sprite):
			push_error("LOOKS: '%s' resolved a different texture from the shared body" % look_id)
			return false
		if (drawn["tint"] as Color) != Color.WHITE and not block.has("tint"):
			push_error("LOOKS: '%s' declares no tint and did not draw white, got %s" % [look_id, str(drawn["tint"])])
			return false
	# Why there is no wash, in numbers: the rig's own composed median against the street, and the
	# lightest wash that would still clear it. A tint darker than that factor sinks the body, and
	# the four hexes it leaves room for are within a per-cent of white -- a look nobody could see.
	var headroom: float = plain - floor_luma
	if headroom < 0.0:
		push_error("LOOKS: the untinted body composes to %.4f, already under the street's %.4f -- that is an art regression, not a look question" % [plain, floor_luma])
		return false
	# The two true negatives. An id nothing declares resolves nothing (so the lookups above are
	# lookups), and the ground predicate can fail -- colony.look.03's retired brown is the tint the
	# colonist composition was regraded away from, and it sinks this body too.
	if not Appearance.of_content(w, "raider", "raider.look.does_not_exist").is_empty():
		push_error("LOOKS: an undeclared look id came back with an appearance block")
		return false
	if _median_composed_luma(img, Color("#5c4632")) >= floor_luma:
		push_error("LOOKS: the retired #5c4632 clears the street threshold, so the ground arithmetic above reads nothing")
		return false
	print("LOOKS OK %d ids, one body '%s' drawn unstained; composed median %.4f over a street floor of %.4f leaves %.4f, so the lightest wash this rig could wear is a factor of %.3f -- no tint ships" % [
		looks.size(), shared_sprite, plain, floor_luma, headroom, floor_luma / plain,
	])
	return true


# DISTINCT: a band of four is four people. Names differ, kits differ, aptitudes differ -- and the
# true negative is the same four bodies drawn from a tree whose odds are all certain and whose
# aptitude ranges are collapsed, which is the archetype as it shipped before this slice: one man,
# four times. The names still differ there, which is what says the negative collapsed the two
# things it meant to and not the whole roll.
func _a_band_of_four_are_four_people() -> bool:
	var varied: Dictionary = _band_signatures(_arena(), 4)
	if int(varied["names"]) < 2:
		push_error("DISTINCT: four raiders drew %d name(s) -- %s" % [int(varied["names"]), str(varied["nameList"])])
		return false
	if int(varied["kits"]) < 2:
		push_error("DISTINCT: four raiders carry %d distinct kit(s) at the shipped odds -- %s" % [int(varied["kits"]), str(varied["kitList"])])
		return false
	if int(varied["apts"]) < 2:
		push_error("DISTINCT: four raiders rolled %d distinct aptitude set(s) -- %s" % [int(varied["apts"]), str(varied["aptList"])])
		return false
	var flat: Dictionary = _band_signatures(_arena_with(_flat_tree()), 4)
	if int(flat["kits"]) != 1:
		push_error("DISTINCT: with every kit chance at 1.0 the four kits still differed (%s) -- the odds are not what varies them" % str(flat["kitList"]))
		return false
	if int(flat["apts"]) != 1:
		push_error("DISTINCT: with every aptitude range collapsed the four bodies still differed (%s) -- the range is not what varies them" % str(flat["aptList"]))
		return false
	if int(flat["names"]) < 2:
		push_error("DISTINCT: the collapsed tree also stopped the names varying, so it collapsed more than the two things it meant to")
		return false
	print("DISTINCT OK four scavengers: %d names, %d kits, %d aptitude sets; with odds certain and ranges collapsed, %d kit, %d aptitude set, %d names" % [
		int(varied["names"]), int(varied["kits"]), int(varied["apts"]), int(flat["kits"]), int(flat["apts"]), int(flat["names"]),
	])
	return true


# NO IDENTITY, and it is the one that matters. `identity` is read by five things -- the draw
# loop's "is this a survivor", `SimJobs.work_view`, `SimAllegiance.is_person`, the director's
# unique-death lull and `SimRecruits._succession_pick` -- and the last of those hands the player's
# body to the nearest candidate when they die. A raider carrying an identity would be an heir
# standing at your wall, which is why the owner's 2026-09-14 call is a `person` record instead.
#
# The negative is what makes this an assertion rather than a coincidence: give the same raider an
# identity and the same scan *does* pick them. So the exclusion is the absence of the component,
# not a special case somewhere that could quietly stop being true.
func _a_raider_is_never_the_heir() -> bool:
	var w: Variant = _arena()
	var band: Array[int] = []
	for i in 4:
		band.append(SimRaiders.spawn(w, 12.0 + float(i), 12.0, "raider.scav"))
	w.events.drain()
	for ent in band:
		if w.components.has_component(int(ent), "identity"):
			push_error("NO-IDENTITY: a spawned raider carries an `identity` component")
			return false
		if String(_person_of(w, int(ent)).get("name", "")).is_empty():
			push_error("NO-IDENTITY: a spawned raider carries no person record either, so the band is anonymous rather than not-a-colonist")
			return false
	# Mara further away than the band, the player dying where the raiders are standing.
	var mara: int = _named_colonist(w, "survivor.unique.mara", "Mara", 30.0, 12.0)
	var dying: int = int(w.player)
	w.components.set_component(dying, "position", {"x": 12.0, "y": 12.0})
	var heir: int = SimRecruits._succession_pick(w, dying)
	if heir != mara:
		push_error("NO-IDENTITY: the player died among four raiders and the body went to %d, not to Mara (%d)" % [heir, mara])
		return false
	# The same shape without Mara's short circuit: the colonist across the district inherits over
	# the raider standing on the corpse -- and then, with an identity on that raider, does not.
	var w2: Variant = _arena()
	var ellis: int = _named_colonist(w2, "survivor.unique.ellis", "Ellis", 30.0, 12.0)
	var near: int = SimRaiders.spawn(w2, 12.5, 12.0, "raider.scav")
	w2.events.drain()
	var dying2: int = int(w2.player)
	w2.components.set_component(dying2, "position", {"x": 12.0, "y": 12.0})
	if SimRecruits._succession_pick(w2, dying2) != ellis:
		push_error("NO-IDENTITY: the far colonist did not inherit with a raider standing nearer")
		return false
	w2.components.set_component(near, "identity", {"id": "survivor.sabotage", "name": "Sabotage", "traits": []})
	if SimRecruits._succession_pick(w2, dying2) != near:
		push_error("NO-IDENTITY: a raider *with* an identity was still not picked -- the scan does not read `identity`, so the absence of one proves nothing")
		return false
	print("NO-IDENTITY OK no band member carries `identity`, all four carry a person; Mara inherits over four raiders, Ellis over one, and only the sabotaged raider inherits")
	return true


# LOOK READER: the rolled look reaches the renderer as a pass-through, and the draw loop is where
# that has to be asserted -- `for_entity` answering correctly proves nothing if `main.gd` never
# hands it the person's look. Textual, over the raider arm alone: the colonist arm a few lines
# above reads `identity.look` in the same words, so a needle over the whole function would be
# satisfied by the wrong reader (CLAUDE.md on needles that survive a refactor).
func _the_rolled_look_reaches_the_renderer() -> bool:
	var w: Variant = _arena()
	var ent: int = SimRaiders.spawn(w, 10.0, 10.0, "raider.scav")
	w.events.drain()
	var person: Dictionary = _person_of(w, ent)
	var look_id: String = String(person.get("look", ""))
	if look_id.is_empty():
		push_error("LOOK-READER: a spawned raider rolled no look")
		return false
	# The look id resolves a body of its own, and an id the pool does not declare does not: that
	# difference is the whole of "the renderer reads it", and it holds whether or not a look ever
	# declares a tint (LOOKS explains why none does today).
	var with_look: Dictionary = Appearance.for_entity(w, {"raider": true, "cid": look_id})
	if with_look["texture"] == null:
		push_error("LOOK-READER: the rolled look '%s' resolved no texture" % look_id)
		return false
	var unknown: Dictionary = Appearance.for_entity(w, {"raider": true, "cid": "raider.look.nobody_declares_this"})
	if unknown["texture"] != null or (unknown["tint"] as Color) != Palette.COLOURS["raider"]:
		push_error("LOOK-READER: an undeclared look still resolved a body, so resolving one proves nothing")
		return false
	# A raider with no rolled look falls back to its archetype, and the two draw the same body --
	# both halves, or "the look is read" would pass against a renderer that had stopped reading
	# the archetype at all, and "one body" would stop being true the moment art per look lands
	# without this lane noticing.
	var without: Dictionary = Appearance.for_entity(w, {"raider": true, "cid": "raider.scav"})
	if (without["tint"] as Color) != Color.WHITE:
		push_error("LOOK-READER: a raider with no rolled look must draw its archetype's own body unstained, got %s" % str(without["tint"]))
		return false
	if with_look["texture"] != without["texture"]:
		push_error("LOOK-READER: the look and the archetype resolved different textures")
		return false
	var arm: String = _raider_arm()
	if arm.is_empty():
		push_error("LOOK-READER: could not isolate the `elif is_raider:` arm of main.gd's _draw_entities -- reading the wrong file or the wrong function")
		return false
	for needle in ["\"person\"", "\"look\"", "\"id\""]:
		if arm.find(String(needle)) < 0:
			push_error("LOOK-READER: the draw loop's raider arm does not mention %s, so the rolled look is a field nothing reads:\n%s" % [String(needle), arm])
			return false
	# The ban, over the code of the arm and never its prose: the comment above it *says* the words
	# "if id ==" on purpose, and a needle a comment can satisfy -- or fail -- is the needle that
	# turned two gates red against correct code this milestone.
	var code: String = _without_comments(arm)
	if code.find("if id ==") >= 0 or code.find("== \"raider.") >= 0:
		push_error("LOOK-READER: the draw loop's raider arm branches on a content id -- the very thing appearance.gd exists to prevent:\n%s" % code)
		return false
	if code.find("get(\"person\"") < 0:
		push_error("LOOK-READER: the raider arm's *code* never reads `person`, only its comment does:\n%s" % code)
		return false
	print("LOOK-READER OK '%s' resolves a body where an undeclared id resolves none, an unrolled raider falls back to the archetype, and the draw loop's raider arm hands over the person's look" % look_id)
	return true


# NO TELL: what a raider looks like may say *who* they are and never *what they carry*. Two
# halves, because two things can carry a tell. The look pool is drawn on its own stream with no
# idea which archetype asked, so both archetypes must be able to wear the same look; and the worn
# kit -- which, unlike a look, is visible on the pawn today -- must be declared identically by
# every archetype, odds included. Either one partitioned would let a glance across a street
# answer "is that the one with the gun", which is the certainty docs/01 clause 4 refuses.
func _a_look_carries_no_tell() -> bool:
	var w: Variant = _arena()
	var seen: Dictionary = {"raider.scav": {}, "raider.gunhand": {}}
	for i in 16:
		for type_id in ["raider.scav", "raider.gunhand"]:
			var ent: int = SimRaiders.spawn(w, 8.0 + float(i % 8), 8.0, String(type_id))
			if ent < 0:
				push_error("NO-TELL: %s failed to spawn" % String(type_id))
				return false
			(seen[type_id] as Dictionary)[String(_person_of(w, ent).get("look", ""))] = true
		w.events.drain()
	var scav: Dictionary = seen["raider.scav"] as Dictionary
	var gun: Dictionary = seen["raider.gunhand"] as Dictionary
	if scav.size() < 2 or gun.size() < 2:
		push_error("NO-TELL: the archetypes drew %d and %d distinct looks -- with a single look each, sharing one would prove nothing" % [scav.size(), gun.size()])
		return false
	if not _overlaps(scav, gun):
		push_error("NO-TELL: no look was worn by both archetypes (%s vs %s) -- the pool is partitioned and a glance says who has the gun" % [str(scav.keys()), str(gun.keys())])
		return false
	# The predicate's own true negative, on fabricated sets: a partition must fail the same test
	# the real draw just passed.
	if _overlaps({"a": true, "b": true}, {"c": true, "d": true}):
		push_error("NO-TELL: the overlap predicate accepted two disjoint sets, so it reads nothing")
		return false
	# And structurally: the pool belongs to the generator, never to an archetype. An archetype
	# that declared looks of its own would partition it at the source.
	for entry in SimRaiders.types(w):
		if entry.has("looks") or entry.has("person"):
			push_error("NO-TELL: archetype %s declares looks of its own -- the pool must be archetype-blind" % String(entry.get("id", "?")))
			return false
	# The other half, and the one with teeth while the looks all resolve one body: what a raider
	# is *wearing* is what a glance can actually tell apart, because worn gear draws on the pawn.
	# So the worn rows -- everything with an equip slot that is not a hand -- must be identical
	# across the archetypes, odds included. What they are *holding* is the archetype and is
	# visible by design: you can see what a man is carrying. Wearing is who; holding is what.
	var worn_by: Dictionary = {}
	for entry in SimRaiders.types(w):
		worn_by[String(entry.get("id", "?"))] = _worn_rows(w, entry)
	var ids: Array = worn_by.keys()
	ids.sort()
	if ids.size() < 2:
		push_error("NO-TELL: one archetype, so the worn-gear comparison judged nothing")
		return false
	var first: Dictionary = worn_by[ids[0]] as Dictionary
	if first.is_empty():
		push_error("NO-TELL: no archetype declares anything worn, so the comparison below is vacuous")
		return false
	for i in range(1, ids.size()):
		var other: Dictionary = worn_by[ids[i]] as Dictionary
		if JSON.stringify(other) != JSON.stringify(first):
			push_error("NO-TELL: %s wears %s and %s wears %s -- a cap only one archetype can be wearing answers 'which one has the gun'" % [String(ids[0]), JSON.stringify(first), String(ids[i]), JSON.stringify(other)])
			return false
	# The comparison can fail: two maps that differ by one row must not compare equal.
	var sabotage: Dictionary = (first as Dictionary).duplicate()
	sabotage["item.sabotage"] = 0.5
	if JSON.stringify(sabotage) == JSON.stringify(first):
		push_error("NO-TELL: the worn-gear comparison accepted an extra row, so it reads nothing")
		return false
	print("NO-TELL OK scav drew %s, gunhand drew %s, %d shared; both wear %s at the same odds" % [str(scav.keys()), str(gun.keys()), _shared_count(scav, gun), JSON.stringify(first)])
	return true


# STREAMS: the `"raid"` stream has not moved. The director draws the night, the side, the entry
# tile and every member's archetype off it; `check_m2_balance.gd`'s measured bands and every raid
# number in docs/23's record are a function of that byte sequence, and a person rolled on it would
# have shifted all of them. The pins below are the stream's state after `_emit_band` places four,
# taken with a throwaway driver on the pre-individuals tree.
func _the_raid_stream_has_not_moved() -> bool:
	for row in RAID_PINS:
		var pin: Dictionary = row as Dictionary
		var seed_value: int = int(pin["seed"])
		var w: Variant = SimBoot.playable(seed_value, MAP_TILES)["world"]
		var rng: Variant = w.rng.stream(SimDirector.RAID_STREAM)
		var placed: Dictionary = SimDirector._emit_band(w, 4, rng)
		if int(placed["placed"]) != 4:
			push_error("STREAMS: seed %d placed %d of 4, so the draws the pin covers were not all made" % [seed_value, int(placed["placed"])])
			return false
		var state: int = int(rng.call("save"))
		if state != int(pin["after"]):
			push_error("STREAMS: seed %d left the '%s' stream at %d, not the pre-individuals %d -- something new is drawing off the director's raid stream" % [seed_value, SimDirector.RAID_STREAM, state, int(pin["after"])])
			return false
		# The pin can fail: one more draw off the same stream moves it.
		rng.call("int_range", 0, 99)
		if int(rng.call("save")) == int(pin["after"]):
			push_error("STREAMS: an extra draw left the stream where it was, so the pin reads nothing")
			return false
	print("STREAMS OK '%s' state after a band of four is unmoved on %d seeds" % [SimDirector.RAID_STREAM, RAID_PINS.size()])
	return true


# SAVE: the person record round-trips. It is a Dictionary of words on a component, so it travels
# the way everything else does -- but it is new keys on an existing component, which is a
# `SAVE_VERSION` bump (kernel/serialize.gd v30) and worth proving rather than assuming. Both
# halves: the text a save would actually write, and the world a load rebuilds from it.
func _a_person_survives_a_save() -> bool:
	var w: Variant = _arena()
	var ent: int = SimRaiders.spawn(w, 10.0, 10.0, "raider.gunhand")
	var other: int = SimRaiders.spawn(w, 11.0, 10.0, "raider.gunhand")
	w.events.drain()
	var before: Dictionary = _person_of(w, ent)
	if String(before.get("name", "")).is_empty():
		push_error("SAVE: the raider carries no person record, so the round trip judges nothing")
		return false
	var text: String = JSON.stringify(w.snapshot())
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("SAVE: the snapshot did not survive JSON at all")
		return false
	var w2: Variant = _arena()
	w2.restore(parsed as Dictionary)
	var after: Dictionary = _person_of(w2, ent)
	for key in ["name", "look", "backstoryId"]:
		if String(after.get(key, "")) != String(before.get(key, "")):
			push_error("SAVE: `%s` came back as '%s', was '%s'" % [key, String(after.get(key, "")), String(before.get(key, ""))])
			return false
	if int(after.get("age", -1)) != int(before.get("age", -2)):
		push_error("SAVE: `age` came back as %s, was %s" % [str(after.get("age")), str(before.get("age"))])
		return false
	if _joined(after.get("features", [])) != _joined(before.get("features", [])):
		push_error("SAVE: `features` came back as %s, were %s" % [str(after.get("features")), str(before.get("features"))])
		return false
	# The comparison is not vacuous: the other body of the same archetype is a different person,
	# and it came back as *that* one rather than as a copy of the first.
	var other_after: Dictionary = _person_of(w2, other)
	if String(other_after.get("name", "")) == String(after.get("name", "")):
		push_error("SAVE: both raiders came back with one name, so the comparison above would pass against any record at all")
		return false
	if String(other_after.get("name", "")) != String(_person_of(w, other).get("name", "")):
		push_error("SAVE: the second raider's record did not survive")
		return false
	print("SAVE OK '%s' (%s, %s) round-tripped through JSON and a restore, beside a second body that stayed itself" % [String(after["name"]), String(after["backstoryId"]), String(after["look"])])
	return true


# CHRONICLE: the one place a raider's name reaches the player, and only once they are dead. The
# record is read off the `raider.killed` event because `handle_death` despawns the body before any
# handler drains (CLAUDE.md: publish only queues), which is also why the event carries the record
# instead of the handler looking it up.
func _a_dead_raider_is_named_once() -> bool:
	var w: Variant = _arena()
	SimChronicle.register_module(w)
	var ent: int = SimRaiders.spawn(w, 10.0, 10.0, "raider.scav")
	w.events.drain()
	var person: Dictionary = _person_of(w, ent)
	var name: String = String(person.get("name", ""))
	w.tick = 1000
	w.step()
	if not SimChronicle.lines(w).is_empty():
		push_error("CHRONICLE: a raider standing at the wall put a line on the screen -- a band is anonymous until it is dead")
		return false
	var body: Dictionary = w.components.get_component(ent, "body") as Dictionary
	body["head"] = 0.0
	SimHealth.finish_death(w, ent)
	w.step()
	var lines: Array[String] = SimChronicle.lines(w)
	if lines.size() != 1:
		push_error("CHRONICLE: one dead raider wrote %d line(s): %s" % [lines.size(), str(lines)])
		return false
	if String(lines[0]).find(name) < 0:
		push_error("CHRONICLE: '%s' does not name the dead raider '%s'" % [String(lines[0]), name])
		return false
	if String(lines[0]).find("One of the raiders") < 0:
		push_error("CHRONICLE: '%s' reads like a colonist's line -- the two must not be confusable" % String(lines[0]))
		return false
	if not _digits(String(lines[0])).is_empty():
		push_error("CHRONICLE: '%s' carries digits and the chronicle is on the HUD" % String(lines[0]))
		return false
	# Twice published is once written, the rule `entity.killed` needed first.
	w.events.publish({"type": "raider.killed", "entity": ent, "id": "raider.scav", "person": person})
	w.step()
	if SimChronicle.lines(w).size() != 1:
		push_error("CHRONICLE: a second `raider.killed` for one body wrote a second line: %s" % str(SimChronicle.lines(w)))
		return false
	# And a body with no record says nothing rather than "One of the raiders was .".
	w.events.publish({"type": "raider.killed", "entity": ent + 500, "id": "raider.scav", "person": {}})
	w.step()
	if SimChronicle.lines(w).size() != 1:
		push_error("CHRONICLE: a nameless raider wrote a line: %s" % str(SimChronicle.lines(w)))
		return false
	print("CHRONICLE OK '%s', written once, digit-free; nothing said while they were alive" % String(lines[0]))
	return true


# --- fixtures and helpers for the individuals lanes --------------------------------------------

# `_colonist`, with an identity id the succession scan actually looks for.
func _named_colonist(w: Variant, id: String, name: String, x: float, y: float) -> int:
	var ent: int = _colonist(w, x, y)
	w.components.set_component(ent, "identity", {"id": id, "name": name, "traits": []})
	return ent


# Spawns `n` scavengers into a world and reports how much they differ: distinct names, distinct
# kits (the sorted item bases they carry, counts included) and distinct aptitude triples.
func _band_signatures(w: Variant, n: int) -> Dictionary:
	var names: Dictionary = {}
	var kits: Dictionary = {}
	var apts: Dictionary = {}
	for i in n:
		var ent: int = SimRaiders.spawn(w, 10.0 + float(i), 10.0, "raider.scav")
		if ent < 0:
			continue
		names[String(_person_of(w, ent).get("name", ""))] = true
		kits[_kit_signature(w, ent)] = true
		apts[JSON.stringify(w.components.get_component(ent, "aptitudes"))] = true
	w.events.drain()
	return {
		"names": names.size(), "kits": kits.size(), "apts": apts.size(),
		"nameList": names.keys(), "kitList": kits.keys(), "aptList": apts.keys(),
	}


func _kit_signature(w: Variant, ent: int) -> String:
	var rows: Array[String] = []
	for item in SimInventory.carried_items(w, ent):
		var base: Variant = w.components.get_component(int(item), "itemBase")
		var stack: Variant = w.components.get_component(int(item), "stack")
		var count: int = int((stack as Dictionary).get("count", 1)) if stack is Dictionary else 1
		rows.append("%s x%d" % [String((base as Dictionary).get("baseId", "?")) if base is Dictionary else "?", count])
	rows.sort()
	return String(",").join(PackedStringArray(rows))


# The shipped content tree with every kit chance certain and every aptitude range collapsed to its
# floor: the archetypes exactly as they were before this slice, for DISTINCT's negative.
func _flat_tree() -> Dictionary:
	var tree: Dictionary = ContentLoader.load_tree()
	for path in tree.keys():
		if not String(path).begins_with("raiders/"):
			continue
		var raw: Variant = tree[path]
		var entries: Array = raw as Array if raw is Array else [raw]
		for entry in entries:
			if not (entry is Dictionary):
				continue
			var e: Dictionary = entry as Dictionary
			for row in e.get("kit", []) as Array:
				if row is Dictionary and (row as Dictionary).has("chance"):
					(row as Dictionary)["chance"] = 1.0
			var apt: Variant = e.get("aptitudes", {})
			if apt is Dictionary:
				for k in (apt as Dictionary).keys():
					var v: Variant = (apt as Dictionary)[k]
					if v is Array and (v as Array).size() == 2:
						(apt as Dictionary)[k] = int((v as Array)[0])
	return tree


# The raider arm of main.gd's entity pass, isolated from the colonist arm above it: from the
# `elif is_raider:` label to the `items.append(` that closes the collection loop.
func _raider_arm() -> String:
	var f: FileAccess = FileAccess.open("res://presentation/main.gd", FileAccess.READ)
	if f == null:
		return ""
	var text: String = f.get_as_text()
	var head: int = text.find("func _draw_entities(")
	if head < 0:
		return ""
	var arm: int = text.find("elif is_raider:", head)
	if arm < 0:
		return ""
	var tail: int = text.find("items.append(", arm)
	if tail < 0:
		return ""
	return text.substr(arm, tail - arm)


# The rows of a kit that draw *on* the body rather than in a hand: item id -> the odds it arrives
# with, `1.0` for a row that always does. A weapon is excluded by its slot, which is what lets the
# archetypes differ in arms and not in dress.
func _worn_rows(w: Variant, entry: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for row in entry.get("kit", []) as Array:
		var item_id: String = String((row as Dictionary).get("item", "")) if row is Dictionary else String(row)
		if item_id.is_empty():
			continue
		var base: Variant = SimItems.content_entry(w, "item", item_id)
		if not (base is Dictionary):
			continue
		var slot: String = String((base as Dictionary).get("equipSlot", ""))
		if slot.is_empty() or slot == "primary" or slot == "secondary":
			continue
		out[item_id] = float((row as Dictionary).get("chance", 1.0)) if row is Dictionary else 1.0
	return out


# The code of a scanned block, with every comment line dropped. A textual needle must be shown
# what it is reading (CLAUDE.md's `_low_arms` precedent), and prose that quotes the very pattern
# it forbids is the cheapest way to fool one.
func _without_comments(block: String) -> String:
	var out: Array[String] = []
	for line in block.split("\n"):
		if String(line).strip_edges().begins_with("#"):
			continue
		out.append(String(line))
	return "\n".join(out)


# The person record off a live body. A gate-side reader on purpose: the two things that ship and
# read this record -- the draw loop's `cid` and `handle_death`'s published event -- both already
# hold the `raider` component when they want it, so an accessor in `raiders.gd` would have been a
# public function only a gate ever called, which is the shape of half the dead sockets this
# milestone has had to name.
func _person_of(w: Variant, entity: int) -> Dictionary:
	var rd: Variant = w.components.get_component(entity, "raider")
	if not (rd is Dictionary):
		return {}
	var person: Variant = (rd as Dictionary).get("person", {})
	return person as Dictionary if person is Dictionary else {}


func _overlaps(a: Dictionary, b: Dictionary) -> bool:
	for k in a.keys():
		if b.has(k):
			return true
	return false


func _shared_count(a: Dictionary, b: Dictionary) -> int:
	var n: int = 0
	for k in a.keys():
		if b.has(k):
			n += 1
	return n


func _joined(v: Variant) -> String:
	if not (v is Array):
		return ""
	var out: Array[String] = []
	for x in v as Array:
		out.append(String(x))
	return String("|").join(PackedStringArray(out))


func _digits(s: String) -> String:
	var out: String = ""
	for i in s.length():
		if s[i] >= "0" and s[i] <= "9":
			out += s[i]
	return out


# The median luma of the body's opaque pixels once `tint` has multiplied them -- the composition
# the screen actually draws, rather than the ramp in isolation.
func _median_composed_luma(img: Image, tint: Color) -> float:
	var lumas: Array[float] = []
	for y in img.get_height():
		for x in img.get_width():
			var px: Color = img.get_pixel(x, y)
			if px.a <= 0.0:
				continue
			lumas.append(0.2126 * px.r * tint.r + 0.7152 * px.g * tint.g + 0.0722 * px.b * tint.b)
	if lumas.is_empty():
		return 0.0
	lumas.sort()
	return lumas[lumas.size() / 2]


func _brightest_surface() -> float:
	var best: float = 0.0
	for i in Palette.SURFACE_TINTS.size():
		var c: Color = Palette.SURFACE_TINTS[i]
		best = maxf(best, 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b)
	return best
