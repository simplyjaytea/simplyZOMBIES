extends SceneTree
# The mask that filters -- docs/12, docs/14, and the owner's decision of 2026-09-12.
#
# What this slice fixed: a bloater's cloud rolled every survivor in reach on flat proximity and
# never once looked at what they had on, so `item.mask.cloth` was worth exactly a bike helmet
# against a plume -- and so were the three glove bases. Their `armor` block had a reader (bite and
# scratch transmission, through `SimInfection.armor_coverage_of`) and their face-of-the-thing had
# none. A `filter` scalar, 0..1, composed by **max across worn items** the way coverage already
# composes, multiplied into the contamination roll as (1 - filter).
#
# The lane that matters is CLOUD, and it is built the way check_m2_medicine.gd's CLEAR lane is,
# because the thing under test is a coin flip and a gate may not be a coin flip: **paired worlds on
# one seed**. Both worlds derive the same `contamination` stream from the same master seed and
# `record_extra_exposure` spends exactly one number from it whatever the chance is, so the filtered
# survivor and the bare one are handed the identical draw and the only difference between their
# outcomes is the multiplier. That buys two assertions a sample of two independent runs could never
# buy: **monotonicity** -- a masked survivor is never contaminated where a bare one walks away --
# and **decidedness** -- there is at least one seed where the mask alone is the difference. Without
# the second, a filter of 0.0 on everything would pass this gate green.
#
# Every lane carries a true negative, and every behavioural lane measures an *outcome* -- how often
# a survivor standing in a real cloud is actually contaminated -- rather than reading back the
# number the code just wrote. A dictionary that says a mask is good is a dictionary comparing
# itself.
#
# One note on the neighbouring defect. docs/23 lists "`bloater` contamination fires once per
# survivor, ever"; the code has since moved to a per-cloud `contaminationRolls` array and a probe
# says it now rolls again for a second cloud. This gate takes no position either way: **every lane
# below blooms exactly one cloud over one survivor in a world of its own**, so neither reading of
# that defect can change a single number here.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const SimBloater = preload("res://sim/modules/bloater.gd")
const Clock = preload("res://sim/time/clock.gd")

# Fixtures, not welds. The sim names none of these: it asks content for a number. A gate still has
# to hold something concrete, and these are the rungs the slice shipped -- the cheap mask that is
# better than nothing, the rubber one that is most of the way there, and a glove, which is on the
# list because MAX has to be shown two pieces in two different slots.
const MASK_CLOTH: String = "item.mask.cloth"
const MASK_GAS: String = "item.mask.gas"
const RESPIRATOR: String = "item.respirator.halfmask"
const GLOVES_CHEM: String = "item.gloves.chemical"
const BARE_HELMET: String = "item.helmet.bike"

const PART: String = "arm_left"
const BLOATER_TYPE: String = "zombie.bloater"
const CLOUD_TICKS: int = 40

# Paired seeds. Fixed lists rather than a range so the count and the arithmetic in the printed line
# are the same thing the assertions judged, and so a seed that turns out to decide nothing can be
# read off the source rather than guessed at.
const CLOUD_SEEDS: Array[int] = [
	7101, 7102, 7103, 7104, 7105, 7106, 7107, 7108, 7109, 7110,
	7111, 7112, 7113, 7114, 7115, 7116, 7117, 7118, 7119, 7120,
	7121, 7122, 7123, 7124, 7125, 7126, 7127, 7128, 7129, 7130,
	7131, 7132, 7133, 7134, 7135, 7136, 7137, 7138, 7139, 7140,
]
# A cloth mask moves the chance from 0.40 to 0.32, so the seeds it alone decides are one in twelve
# and the lane needs a longer run than CLOUD to have any. This is the whole cost of the gate:
# 2 x 120 worlds, about eight seconds.
const CLOTH_FIRST: int = 7200
const CLOTH_COUNT: int = 120
const PINNED_COUNT: int = 40
const PINNED_FIRST: int = 7500


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _content_declares_a_filter_that_can_be_worn_and_found() and ok
	ok = _every_filter_declared_is_one_the_reader_sees() and ok
	ok = _filters_compose_by_max_not_sum() and ok
	ok = _a_dead_bloater_books_a_contamination_on_whoever_is_standing_there() and ok
	ok = _a_respirator_is_contaminated_less_often_on_the_same_seed() and ok
	ok = _a_cloth_mask_helps_and_is_not_safe() and ok
	ok = _a_bare_survivor_is_priced_exactly_as_before() and ok
	if ok:
		print("M2_FILTER_OK content worn max bloom cloud notsafe pinned")
		quit(0)
	else:
		push_error("M2_FILTER_FAIL")
		quit(1)


# --- fixtures ---------------------------------------------------------------------------------

# A survivor with an open bite. The open wound is not decoration: `SimBloater._has_open_wound` is
# what a plume gets in through, so a world without one measures nothing at all -- which is why
# BLOOM asserts the bare control is contaminated before any lane compares anything to it.
func _world(seed_val: int = 7001, bitten: bool = true) -> Variant:
	var fixture: Dictionary = {
		"seed": seed_val,
		"tick_hz": 20,
		"map": {"width": 24, "height": 24, "walls": []},
		"player": {"id": 0, "x": 8.5, "y": 12.5, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	}
	var w: Variant = World.new(fixture)
	w.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	SimBoot.attach_kernel(w, SimTileMap.blank_map(24, 24))
	SimHealth.register_module(w)
	SimInventory.register_module(w)
	SimItems.register_module(w)
	SimBloater.register_module(w)
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	SimHealth.make_survivor_body(w, w.player)
	SimInventory.make_inventory(w, w.player)
	if bitten:
		SimWounds.append_wound(w, w.player, "bite", PART, -1, 4.0)
	return w


func _wear(w: Variant, id: String) -> bool:
	var item: int = SimItems.spawn_item(w, id, {"tier": "scavenged"})
	if not SimInventory.equip(w, w.player, item):
		push_error("the fixture '%s' would not go on" % id)
		return false
	return true


# A cloud where the survivor is standing, written the way `bloater.bloom` writes one. BLOOM proves
# this fixture is the same thing the real handler produces; the measuring lanes use it because
# 400 worlds is cheaper without a corpse in each of them.
func _cloud(w: Variant) -> int:
	var flag: int = int(w.entities.spawn())
	w.components.set_component(flag, "position", {"x": 8.5, "y": 12.5})
	w.components.set_component(flag, "contamination", {
		"radius": SimBloater.FLAG_RADIUS,
		"expiresAtTick": int(w.tick) + CLOUD_TICKS,
		"source": 4242,
	})
	return flag


func _exposures(w: Variant) -> Array:
	var state: Variant = w.components.get_component(w.player, "zombieInfection")
	if not (state is Dictionary):
		return []
	var out: Array = []
	for e in (state as Dictionary).get("exposures", []) as Array:
		if String((e as Dictionary).get("vector", "")) == "contamination":
			out.append(e)
	return out


func _contaminated(w: Variant) -> bool:
	for e in _exposures(w):
		if bool((e as Dictionary).get("transmitted", false)):
			return true
	return false


# One cloud, one survivor, one roll. Returns whether it got in.
func _stand_in_a_cloud(seed_val: int, wearing: String) -> bool:
	var w: Variant = _world(seed_val)
	if wearing != "" and not _wear(w, wearing):
		return false
	_cloud(w)
	w.step()
	return _contaminated(w)


# --- the two predicates, so the true negatives can be fed the same ones -----------------------

# A filter has to be a number strictly inside the open interval. Zero is absence written out loud
# and 1.0 is an immunity: a cloud a survivor cannot be hurt by is not a cloud, which is the rule
# SEPSIS_MIN_MUL states for a good medic and MAX_COVERAGE does not state for armour only because
# no shipped piece is close.
func _filter_value_ok(entry: Dictionary) -> bool:
	if not entry.has("filter"):
		return false
	var v: Variant = entry["filter"]
	if not (v is float or v is int):
		return false
	var f: float = float(v)
	return f > 0.0 and f < 1.0


# And it has to be on something a survivor can put on, because `SimInfection.filter_of` reads
# `equipped_items` and nothing else. A filter on a base with no equip slot is a number in a file.
func _wearable(entry: Dictionary) -> bool:
	var slot: String = String(entry.get("equipSlot", ""))
	return slot != "" and SimInventory.EQUIP_SLOTS.has(slot)


# --- CONTENT ----------------------------------------------------------------------------------

func _content_declares_a_filter_that_can_be_worn_and_found() -> bool:
	var w: Variant = _world()
	var findable: Dictionary = {}
	var tables: int = 0
	for file_v in (w.content as Dictionary).values():
		if not (file_v is Array):
			continue
		for entry_v in file_v as Array:
			if not (entry_v is Dictionary):
				continue
			var t: Dictionary = entry_v as Dictionary
			if not String(t.get("id", "")).begins_with("loot."):
				continue
			tables += 1
			for row_v in t.get("entries", []) as Array:
				findable[String((row_v as Dictionary).get("item", ""))] = true
	if tables == 0:
		push_error("CONTENT: no loot tables loaded, so the reachability half has nothing to judge")
		return false

	var declared: int = 0
	var best: float = 0.0
	var worst: float = 1.0
	for entry_v in SimItems.content_entries(w, "item"):
		var e: Dictionary = entry_v as Dictionary
		if not e.has("filter"):
			continue
		var id: String = String(e.get("id", ""))
		if not _filter_value_ok(e):
			push_error("CONTENT: '%s' declares filter %s -- a filter is a number above zero and under one, or it is absence and immunity written out" % [id, str(e["filter"])])
			return false
		if not _wearable(e):
			push_error("CONTENT: '%s' declares a filter and no equip slot the sim has -- filter_of reads what is worn, so this is a number nothing can ever see" % id)
			return false
		if not findable.has(id):
			push_error("CONTENT: '%s' declares a filter and sits in no loot table -- complete, correct and unreachable" % id)
			return false
		declared += 1
		best = maxf(best, float(e["filter"]))
		worst = minf(worst, float(e["filter"]))
	if declared < 10:
		push_error("CONTENT: only %d bases in the whole roster declare a filter; this lane is judging almost nothing" % declared)
		return false
	if best < 0.8:
		push_error("CONTENT: the best filter anyone can find is %.2f -- there is nothing in the world worth walking into a medical site for" % best)
		return false

	# The true negatives: both predicates have to be able to say no, and they are shown the three
	# shapes that would matter -- an immunity, a bare number, and a filter on something nobody can
	# put on. Fabricated, because no shipped base is allowed to be any of them.
	for bad in [{"filter": 1.0}, {"filter": 0.0}, {"filter": -0.2}, {"filter": "0.4"}, {}]:
		if _filter_value_ok(bad as Dictionary):
			push_error("CONTENT: the value predicate accepted %s" % str(bad))
			return false
	if not _filter_value_ok({"filter": 0.5}):
		push_error("CONTENT: the value predicate refuses an ordinary filter, so it refuses everything")
		return false
	if _wearable({"filter": 0.5, "class": "consumable"}) or _wearable({"equipSlot": "monocle"}):
		push_error("CONTENT: the wearable predicate accepted a filter nobody can put on")
		return false
	if not _wearable({"equipSlot": "face"}):
		push_error("CONTENT: the wearable predicate refuses the face slot, so it refuses everything")
		return false
	if findable.has("item.filter.imaginary"):
		push_error("CONTENT: the table scan found an id that does not exist")
		return false
	print("  CONTENT: %d filters across %d tables, every one wearable and findable, best %.2f worst %.2f, nothing at zero and nothing immune" % [declared, tables, best, worst])
	return true


# --- WORN -------------------------------------------------------------------------------------
#
# The other direction of the dead-socket rule: not "is the reader reached" (CLOUD answers that)
# but "does the reader reach every declaration". Each shipped base is put on a bare survivor in a
# world of its own and `filter_of` has to hand back exactly the number content authored -- which is
# what catches a filter parked in a slot `equipped_items` does not return, the failure that made
# `move_speed` a no-op for every NPC in the game.
func _every_filter_declared_is_one_the_reader_sees() -> bool:
	var probe: Variant = _world()
	var rows: Array = []
	for entry_v in SimItems.content_entries(probe, "item"):
		var e: Dictionary = entry_v as Dictionary
		if e.has("filter"):
			rows.append({"id": String(e.get("id", "")), "filter": float(e["filter"]), "slot": String(e.get("equipSlot", ""))})
	if rows.is_empty():
		push_error("WORN: no base declares a filter, so this lane has nothing to judge")
		return false
	var slots: Dictionary = {}
	for row_v in rows:
		var row: Dictionary = row_v as Dictionary
		var w: Variant = _world()
		if SimInfection.filter_of(w, w.player) != 0.0:
			push_error("WORN: a survivor wearing nothing reports a filter")
			return false
		if not _wear(w, String(row["id"])):
			return false
		var got: float = SimInfection.filter_of(w, w.player)
		if absf(got - float(row["filter"])) > 0.0001:
			push_error("WORN: '%s' declares %.3f and the reader sees %.3f -- a filter in a slot nothing walks" % [String(row["id"]), float(row["filter"]), got])
			return false
		slots[String(row["slot"])] = true

	# A mask in the pack is not a mask on the face. The true negative that separates "worn" from
	# "carried", and the one an implementation built on `carried_items` would fail.
	var pocket: Variant = _world()
	var stowed: int = SimItems.spawn_item(pocket, MASK_GAS, {"tier": "scavenged"})
	if not SimInventory.stow(pocket, pocket.player, stowed):
		push_error("WORN: the fixture mask would not go in a pocket")
		return false
	if SimInfection.filter_of(pocket, pocket.player) != 0.0:
		push_error("WORN: a mask carried in the pack filters a cloud from inside the pack")
		return false

	# And a piece of gear with no filter must not acquire one by being armour.
	var helmet: Variant = _world()
	if not _wear(helmet, BARE_HELMET):
		return false
	if SimInfection.filter_of(helmet, helmet.player) != 0.0:
		push_error("WORN: '%s' declares no filter and reads %.3f -- armour is leaking into the filter" % [BARE_HELMET, SimInfection.filter_of(helmet, helmet.player)])
		return false
	print("  WORN: all %d declared filters reach the reader across %d slots; a stowed mask and a bare helmet each read zero" % [rows.size(), slots.size()])
	return true


# --- MAX --------------------------------------------------------------------------------------
#
# Best worn wins -- the owner's words, and the same composition `armor_coverage_of` uses. Two
# pieces in two different slots, stowed in both orders because a scan that simply keeps the last
# thing it saw passes one ordering by luck. A sum is the exploit this pins out: it would make a
# wardrobe an immunity, which CONTENT has just refused any single item from being.
func _filters_compose_by_max_not_sum() -> bool:
	var alone: float = 0.0
	var lesser: float = 0.0
	for best_first in [true, false]:
		var w: Variant = _world()
		var ids: Array = [RESPIRATOR, GLOVES_CHEM] if best_first else [GLOVES_CHEM, RESPIRATOR]
		for id in ids:
			if not _wear(w, String(id)):
				return false
		var solo: Variant = _world()
		if not _wear(solo, RESPIRATOR):
			return false
		alone = SimInfection.filter_of(solo, solo.player)
		var glove: Variant = _world()
		if not _wear(glove, GLOVES_CHEM):
			return false
		lesser = SimInfection.filter_of(glove, glove.player)
		var both: float = SimInfection.filter_of(w, w.player)
		if absf(both - alone) > 0.0001:
			push_error("MAX: respirator %.3f and gloves %.3f compose to %.3f (best stowed first: %s) -- expected the max" % [alone, lesser, both, str(best_first)])
			return false
	# The assertion has to be able to tell a max from a sum, or it is asserting nothing.
	if absf((alone + lesser) - alone) <= 0.0001:
		push_error("MAX: the second piece filters nothing, so max and sum are the same number and this lane cannot fail")
		return false
	if lesser >= alone:
		push_error("MAX: the gloves filter %.3f against the respirator's %.3f, so 'best wins' is not being tested" % [lesser, alone])
		return false
	# Taking the better one off drops to the lesser, rather than to zero or staying put.
	var strip: Variant = _world()
	if not _wear(strip, RESPIRATOR) or not _wear(strip, GLOVES_CHEM):
		return false
	SimInventory.unequip(strip, strip.player, "face")
	var after: float = SimInfection.filter_of(strip, strip.player)
	if absf(after - lesser) > 0.0001:
		push_error("MAX: with the respirator off the survivor reads %.3f, not the gloves' %.3f" % [after, lesser])
		return false
	print("  MAX: %.2f over %.2f composes to %.2f either way, not %.2f; taking the better one off falls back to the lesser" % [alone, lesser, alone, alone + lesser])
	return true


# --- BLOOM ------------------------------------------------------------------------------------
#
# The whole chain once, through the real handler rather than the fixture: a bloater dies, a cloud
# stands where it fell, and the survivor standing in it has a contamination booked against them.
# This is what earns the right to use `_cloud` in the four hundred worlds below -- and it is the
# true negative for every one of them, because a survivor with no open wound in the same cloud on
# the same seed must come out with nothing at all.
func _a_dead_bloater_books_a_contamination_on_whoever_is_standing_there() -> bool:
	var w: Variant = _world(7009)
	var z: int = int(w.entities.spawn())
	w.components.set_component(z, "position", {"x": 8.5, "y": 12.5})
	w.events.publish({"type": "entity.killed", "entity": z, "zombieType": BLOATER_TYPE, "x": 8.5, "y": 12.5})
	# publish() only queues; the bloom handler runs at drain, at the end of this step. The
	# contamination system is registered in the same step's `infection` phase, so it cannot see a
	# cloud that does not exist yet -- the roll is the step after.
	w.step()
	var clouds: int = 0
	for e in w.components.query(["contamination", "position"]):
		clouds += 1
		var c: Dictionary = w.components.get_component(int(e), "contamination") as Dictionary
		if absf(float(c.get("radius", 0.0)) - SimBloater.FLAG_RADIUS) > 0.0001:
			push_error("BLOOM: the cloud the handler wrote has radius %.2f against the fixture's %.2f -- the measuring lanes are standing in something else" % [float(c.get("radius", 0.0)), SimBloater.FLAG_RADIUS])
			return false
	if clouds != 1:
		push_error("BLOOM: a dead bloater left %d clouds" % clouds)
		return false
	if not _exposures(w).is_empty():
		push_error("BLOOM: the cloud rolled inside the step that spawned it")
		return false
	w.step()
	var booked: Array = _exposures(w)
	if booked.size() != 1:
		push_error("BLOOM: standing in a bloater's cloud booked %d contaminations" % booked.size())
		return false
	if String((booked[0] as Dictionary).get("bodyPart", "")) != "torso":
		push_error("BLOOM: the contamination was booked on '%s'" % String((booked[0] as Dictionary).get("bodyPart", "")))
		return false

	# The true negative: no open wound, nothing to get into.
	var whole: Variant = _world(7009, false)
	whole.events.publish({"type": "entity.killed", "entity": int(whole.entities.spawn()), "zombieType": BLOATER_TYPE, "x": 8.5, "y": 12.5})
	whole.step()
	whole.step()
	if not _exposures(whole).is_empty():
		push_error("BLOOM: an unwounded survivor in the same cloud was contaminated anyway")
		return false
	print("  BLOOM: a dead bloater leaves one cloud, it rolls the tick after, it books on the torso, and an unbitten survivor in the same cloud is untouched")
	return true


# --- CLOUD ------------------------------------------------------------------------------------
#
# The load-bearing lane. See the header for why it is paired rather than sampled.
func _a_respirator_is_contaminated_less_often_on_the_same_seed() -> bool:
	var bare_hits: int = 0
	var masked_hits: int = 0
	var decided: int = 0
	for seed_val in CLOUD_SEEDS:
		var bare: bool = _stand_in_a_cloud(int(seed_val), "")
		var masked: bool = _stand_in_a_cloud(int(seed_val), MASK_GAS)
		if bare:
			bare_hits += 1
		if masked:
			masked_hits += 1
		if masked and not bare:
			push_error("CLOUD: on seed %d the survivor in a gas mask was contaminated where the bare one walked away -- the filter is reaching the roll backwards" % int(seed_val))
			return false
		if bare and not masked:
			decided += 1
	if bare_hits == 0:
		push_error("CLOUD: over %d seeds the bare control was never contaminated, so the mask has nothing to be better than" % CLOUD_SEEDS.size())
		return false
	if decided == 0:
		push_error("CLOUD: over %d paired seeds the mask never once changed the outcome -- the scalar reaches the content and not the roll" % CLOUD_SEEDS.size())
		return false
	if masked_hits >= bare_hits:
		push_error("CLOUD: a gas mask was contaminated %d times of %d against a bare head's %d -- no better" % [masked_hits, CLOUD_SEEDS.size(), bare_hits])
		return false
	print("  CLOUD: over %d paired seeds a bare head took %d, a gas mask %d, and %d seeds turned on the mask alone" % [CLOUD_SEEDS.size(), bare_hits, masked_hits, decided])
	return true


# --- NOTSAFE ----------------------------------------------------------------------------------
#
# The other half of the owner's brief, and the half a ladder of numbers usually gets wrong: the
# cheap mask has to be *genuinely* better than nothing and *genuinely* not safe. Three signs, the
# same three check_m2_medicine's CLEAR lane takes -- it helps, the control has something to be
# helped from, and it still lets the plume through often enough to be frightened of. A longer run
# than CLOUD because a cloth mask decides one seed in twelve rather than two in five.
func _a_cloth_mask_helps_and_is_not_safe() -> bool:
	var bare_hits: int = 0
	var cloth_hits: int = 0
	var decided: int = 0
	for i in CLOTH_COUNT:
		var seed_val: int = CLOTH_FIRST + i
		var bare: bool = _stand_in_a_cloud(seed_val, "")
		var cloth: bool = _stand_in_a_cloud(seed_val, MASK_CLOTH)
		if bare:
			bare_hits += 1
		if cloth:
			cloth_hits += 1
		if cloth and not bare:
			push_error("NOTSAFE: on seed %d the cloth mask was contaminated where a bare head was not" % seed_val)
			return false
		if bare and not cloth:
			decided += 1
	if bare_hits == 0:
		push_error("NOTSAFE: the bare control was never contaminated over %d seeds" % CLOTH_COUNT)
		return false
	if decided == 0 or cloth_hits >= bare_hits:
		push_error("NOTSAFE: a cloth mask took %d of %d against a bare head's %d, deciding %d seeds -- it buys nothing" % [cloth_hits, CLOTH_COUNT, bare_hits, decided])
		return false
	if cloth_hits == 0:
		push_error("NOTSAFE: a cloth mask was never once contaminated over %d seeds -- the cheapest mask in the game must not make a plume safe" % CLOTH_COUNT)
		return false
	if float(cloth_hits) < 0.5 * float(bare_hits):
		push_error("NOTSAFE: a cloth mask halved the plume (%d against %d) -- that is a respirator's job and there would be no reason to look for one" % [cloth_hits, bare_hits])
		return false
	print("  NOTSAFE: over %d paired seeds a bare head took %d and a rag over the mouth %d, deciding %d -- better, and nowhere near safe" % [CLOTH_COUNT, bare_hits, cloth_hits, decided])
	return true


# --- PINNED -----------------------------------------------------------------------------------
#
# The retrofit is additive or it is a silent rebalance of every cloud in the game. A survivor
# wearing nothing must be rolled at exactly `EXTRA_CHANCE`, and the honest way to say that is not
# to read the constant back -- it is to run the roll the old way, on the same seed, off the same
# named stream, and demand the same answer every time. Slice 1's DEFAULT lane and slice 2's PINNED
# lane are the precedent.
func _a_bare_survivor_is_priced_exactly_as_before() -> bool:
	var agreed: int = 0
	var hits: int = 0
	for i in PINNED_COUNT:
		var seed_val: int = PINNED_FIRST + i
		var through_the_cloud: bool = _stand_in_a_cloud(seed_val, "")
		# The control: the same world, the same first draw off the `contamination` stream, and the
		# unmultiplied chance the module carried before a filter existed.
		var control: Variant = _world(seed_val)
		var res: Dictionary = SimInfection.record_extra_exposure(control, control.player, 4242, control.rng.stream(SimBloater.STREAM), SimBloater.EXTRA_CHANCE)
		if through_the_cloud != bool(res.get("transmitted", false)):
			push_error("PINNED: on seed %d the shipped cloud said %s where a flat %.2f said %s -- a filter term is reaching a survivor wearing nothing" % [seed_val, str(through_the_cloud), SimBloater.EXTRA_CHANCE, str(bool(res.get("transmitted", false)))])
			return false
		agreed += 1
		if through_the_cloud:
			hits += 1
	# The control has to be capable of disagreeing, or "they agreed" is a statement about nothing.
	if hits == 0 or hits == PINNED_COUNT:
		push_error("PINNED: the control came out %s on all %d seeds, so agreement proves nothing" % ["transmitted" if hits > 0 else "clear", PINNED_COUNT])
		return false
	# And the comparison has to be able to fire. The same control at half the chance must disagree
	# with the shipped cloud somewhere, or this lane would pass against any chance at all.
	var disagreements: int = 0
	for i2 in PINNED_COUNT:
		var seed2: int = PINNED_FIRST + i2
		var halved: Variant = _world(seed2)
		var res2: Dictionary = SimInfection.record_extra_exposure(halved, halved.player, 4242, halved.rng.stream(SimBloater.STREAM), SimBloater.EXTRA_CHANCE * 0.5)
		if _stand_in_a_cloud(seed2, "") != bool(res2.get("transmitted", false)):
			disagreements += 1
	if disagreements == 0:
		push_error("PINNED: halving the chance changed nothing on any of %d seeds, so this lane cannot tell one chance from another" % PINNED_COUNT)
		return false
	print("  PINNED: over %d seeds a bare survivor is rolled at exactly %.2f, agreeing with the pre-filter expression every time (%d transmitted); half that chance disagrees on %d" % [agreed, SimBloater.EXTRA_CHANCE, hits, disagreements])
	return true
