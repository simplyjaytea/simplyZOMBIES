extends SceneTree
# Armour that stops damage -- the owner's decision of 2026-09-12.
#
# What this slice fixed, stated plainly because it is hard to believe: **an `armor` block reduced
# no combat damage anywhere in the sim.** Coverage was read by `SimInfection.armor_coverage_of`
# and spent on exactly two things -- bite and scratch *transmission*, and a heat penalty in
# `SimNeeds` -- so a riot vest made a survivor less likely to be **infected** and did nothing
# whatever about being **hit**. Twelve shipped garments, a coverage number on every one of them,
# and the number never once met a blow. That is the dead-socket shape this milestone keeps paying
# for, and it was sitting in the middle of the combat loop.
#
# The reader is `SimHealth.armor_damage_factor`, applied in `damage_part` -- the one closure in
# the sim that moves integrity, and the funnel every damage path in the game arrives at. PATHS
# below is the lane that says so, and it is the lane that matters: a gate proving the factor
# returns the right number proves nothing at all about whether anything multiplies by it.
#
# **The curve is not a new number and that is the point.** `SimWounds.severity_for` softened wound
# escalation by exactly `1 - 0.5 * coverage` from the day wounds landed, because escalation was
# the only thing coverage could be made to touch. This slice moved that same curve one step
# upstream onto the integrity itself and deleted the copy downstream, so the bands a covered part
# lands in are the bands it landed in before -- arrived at once instead of twice. BANDS is that
# claim, and `check_m2_wounds.gd`'s own ARMOR lane still prints the identical `bare=2 armored=1`
# it printed before the slice, which is the strongest form of it.
#
# Every lane measures an outcome -- integrity actually removed from a body by a real event on the
# real bus -- rather than reading back the number the code just computed. A dictionary that says a
# vest is good is a dictionary comparing itself.

const World = preload("res://sim/world.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimAttachments = preload("res://sim/modules/attachments.gd")
const SimCondition = preload("res://sim/condition.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimRoster = preload("res://sim/modules/roster.gd")

# Fixtures, not welds. The sim names none of these -- it asks content for a number -- but a gate
# has to hold something concrete, and these are the rungs the catalogue ships: a vest that covers
# a torso well and an arm less, a helmet, and the carrier whose whole character is that it is
# nothing without its plate.
const VEST: String = "item.vest.riot"
const SCRAP_VEST: String = "item.vest.scrap"
const HELMET: String = "item.helmet.bike"
const CARRIER: String = "item.vest.carrier"
const PLATE: String = "item.armorpart.plate.steel"
const CERAMIC: String = "item.armorpart.plate.ceramic"
const LINING: String = "item.armorpart.lining.aramid"
const POUCH: String = "item.armorpart.pocket.pouch"
const SPEAR: String = "item.spear.improvised"
const JACKET: String = "item.jacket.leather"

const TORSO: String = "torso"
const FOOT: String = "foot_right"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _the_factor_is_the_curve_and_nothing_else() and ok
	ok = _a_vest_stops_part_of_a_blow_and_an_uncovered_part_takes_all_of_it() and ok
	ok = _every_damage_path_goes_through_the_one_reader() and ok
	ok = _a_fitted_plate_stops_more_than_the_carrier_alone() and ok
	ok = _the_bands_are_where_they_were_before_the_slice() and ok
	ok = _the_screen_learns_nothing_it_could_build_a_bar_from() and ok
	ok = _a_plate_wears_as_it_stops_blows() and ok
	ok = _only_what_covered_the_blow_wears() and ok
	ok = _a_shambler_in_the_district_wears_the_plate() and ok
	if ok:
		print("M2_ARMOR_OK factor stops paths plate bands ban struck covers reached")
		quit(0)
	else:
		push_error("M2_ARMOR_FAIL")
		quit(1)


func _world(seed_val: int) -> Variant:
	var fixture: Dictionary = {
		"seed": seed_val,
		"tick_hz": 20,
		"map": {"width": 32, "height": 32, "walls": []},
		"player": {"id": 0, "x": 4.5, "y": 16.5, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	}
	var w: Variant = World.new(fixture)
	SimHealth.register_module(w)
	SimWounds.register_module(w)
	SimHealth.make_survivor_body(w, w.player)
	SimHealth.make_stamina(w, w.player, 100)
	return w


func _wear(w: Variant, base_id: String, slot: String) -> int:
	var item: int = SimItems.spawn_item(w, base_id, {"tier": "scavenged"})
	if item < 0 or not SimInventory.equip(w, w.player, item, slot):
		return -1
	return item


func _integrity(w: Variant, part: String) -> float:
	var body: Variant = w.components.get_component(w.player, "body")
	return float((body as Dictionary)[part]) if body is Dictionary else -1.0


# One blow on the bus, drained. `events.publish()` only queues -- handlers run at `drain()`, at
# the end of `world.step()` -- so a fixture that publishes and then reads without stepping sees
# nothing at all, which CLAUDE.md records as having cost somebody a while.
func _strike(w: Variant, part: String, damage: float) -> float:
	var before: float = _integrity(w, part)
	w.events.publish({"type": "attack.connected", "attacker": -1, "target": w.player, "bodyPart": part, "damage": damage})
	w.step()
	return before - _integrity(w, part)


func _bite(w: Variant, part: String, damage: float) -> float:
	var before: float = _integrity(w, part)
	w.events.publish({"type": "bite.landed", "victim": w.player, "source": -1, "bodyPart": part, "damage": damage})
	w.step()
	return before - _integrity(w, part)


# --- FACTOR -----------------------------------------------------------------------------------
# The pure predicate, asserted as a predicate: the whole curve across the whole range, including
# both ends, with no world state in the way. Cheap, and it is what makes every measured lane below
# legible -- when STOPS prints "6.00 bare, 3.75 vested" this is the line that says why.
func _the_factor_is_the_curve_and_nothing_else() -> bool:
	var lane: String = "FACTOR"
	var w: Variant = _world(9001)

	var bare: float = SimHealth.armor_damage_factor(w, w.player, TORSO)
	if not is_equal_approx(bare, 1.0):
		push_error("%s: a bare torso let through %.4f of a blow, and a bare torso is bare" % [lane, bare])
		return false

	var vest: int = _wear(w, VEST, "vest")
	if vest < 0:
		push_error("%s: the riot vest would not go on, so nothing below is testing anything" % lane)
		return false
	var cov: float = SimInfection.armor_coverage_of(w, w.player, TORSO)
	if cov <= 0.0:
		push_error("%s: a worn riot vest covers the torso %.4f -- the coverage reader is broken and the factor cannot be judged" % [lane, cov])
		return false
	var vested: float = SimHealth.armor_damage_factor(w, w.player, TORSO)
	var want: float = 1.0 - SimHealth.ARMOR_STOPS_AT_FULL_COVERAGE * cov
	if not is_equal_approx(vested, want):
		push_error("%s: coverage %.4f should let through %.4f and let through %.4f" % [lane, cov, want, vested])
		return false
	if vested >= bare:
		push_error("%s: a vested torso let through %.4f and a bare one %.4f" % [lane, vested, bare])
		return false

	# The far end of the curve, which no shipped garment reaches: total coverage still lets half a
	# blow through. Stated as an assertion rather than as a comment, because "armour is never
	# immunity" is the balance claim the constant exists to make -- the same rule check_m2_filter
	# states for a mask and check_m2_medicine for a good medic.
	var full: float = 1.0 - SimHealth.ARMOR_STOPS_AT_FULL_COVERAGE * 1.0
	if full <= 0.0 or full > 0.75:
		push_error("%s: full coverage would let through %.4f of a blow -- that is immunity, or close enough to it" % [lane, full])
		return false

	# TN: the factor has to be able to say "all of it". A part nothing covers is that case, and it
	# has to come back to exactly 1.0 on a survivor who is demonstrably wearing something.
	var uncovered: float = SimHealth.armor_damage_factor(w, w.player, FOOT)
	if not is_equal_approx(uncovered, 1.0):
		push_error("%s: a riot vest covers no foot and the foot let through %.4f" % [lane, uncovered])
		return false

	print("  FACTOR OK bare 1.0000, vested %.4f at coverage %.4f, an uncovered foot 1.0000, and full coverage still lets %.2f through" % [vested, cov, full])
	return true


# --- STOPS ------------------------------------------------------------------------------------
# The outcome. Two worlds on one seed, one blow each, identical in every respect but the vest --
# and what is compared is integrity actually removed from a body, not a factor read back.
#
# The uncovered-part half is the true negative and it is the half that would catch the worst
# possible bug here: a mitigation that ignored `bodyPart` and softened everything. A riot vest
# covers no foot, so a foot must take the whole blow while the same survivor's torso does not.
func _a_vest_stops_part_of_a_blow_and_an_uncovered_part_takes_all_of_it() -> bool:
	var lane: String = "STOPS"
	var blow: float = 6.0

	var bare_w: Variant = _world(9100)
	var bare_torso: float = _strike(bare_w, TORSO, blow)
	if not is_equal_approx(bare_torso, blow):
		push_error("%s: a bare torso lost %.4f to a blow of %.4f -- something else is already eating damage" % [lane, bare_torso, blow])
		return false

	var vest_w: Variant = _world(9100)
	if _wear(vest_w, VEST, "vest") < 0:
		push_error("%s: the riot vest would not go on" % lane)
		return false
	var vested_torso: float = _strike(vest_w, TORSO, blow)
	if vested_torso >= bare_torso:
		push_error("%s: the same blow took %.4f off a vested torso and %.4f off a bare one" % [lane, vested_torso, bare_torso])
		return false
	if vested_torso <= 0.0:
		push_error("%s: a vested torso lost nothing at all to a blow of %.4f, and armour is not immunity" % [lane, blow])
		return false

	# TN: the same vest, the same world, a part it does not cover.
	var bare_foot: float = _strike(_world(9101), FOOT, blow)
	var vest_w2: Variant = _world(9101)
	if _wear(vest_w2, VEST, "vest") < 0:
		push_error("%s: the riot vest would not go on" % lane)
		return false
	var vested_foot: float = _strike(vest_w2, FOOT, blow)
	if not is_equal_approx(vested_foot, bare_foot):
		push_error("%s: a riot vest covers no foot, and the foot lost %.4f vested against %.4f bare" % [lane, vested_foot, bare_foot])
		return false

	print("  STOPS OK a blow of %.2f took %.4f off a bare torso and %.4f off a vested one; an uncovered foot lost %.4f either way" % [blow, bare_torso, vested_torso, bare_foot])
	return true


# --- PATHS ------------------------------------------------------------------------------------
# **The lane this gate exists for.** `damage_part` is reached by two events and only two --
# `attack.connected`, which every swing, every shot and every shambler swipe publishes, and
# `bite.landed` -- so mitigation applied there covers the whole game. That is a claim about
# reachability, and the dead-socket rule says a claim about reachability has to be measured at
# the far end rather than asserted at the near one.
#
# So: drive both events, on an armoured body and a bare one, and compare what each removed. And
# then the textual half, because the behavioural half cannot see a *third* path being added later
# that writes integrity without coming through here -- `damage_part` must stay the only place in
# health.gd that assigns into a body, and the factor must be multiplied in where the blow is
# computed rather than somewhere a refactor can quietly drop it.
func _every_damage_path_goes_through_the_one_reader() -> bool:
	var lane: String = "PATHS"
	var blow: float = 6.0

	# The bite path. A bite is the reason armour existed in this codebase at all -- it has always
	# reduced transmission -- and until this slice it took the same bite out of the body either
	# way. `bite.landed` also goes through `damage_part`, so it must move now too.
	var bare_bite: float = _bite(_world(9200), TORSO, blow)
	var vest_w: Variant = _world(9200)
	if _wear(vest_w, VEST, "vest") < 0:
		push_error("%s: the riot vest would not go on" % lane)
		return false
	var vested_bite: float = _bite(vest_w, TORSO, blow)
	if vested_bite >= bare_bite:
		push_error("%s: a bite took %.4f through a vest and %.4f through nothing" % [lane, vested_bite, bare_bite])
		return false

	# A head hit through a helmet, which is the other event and a different garment and a different
	# part -- so a mitigation wired to one worn slot by accident cannot pass this lane.
	var bare_head: float = _strike(_world(9201), "head", 3.0)
	var helm_w: Variant = _world(9201)
	if _wear(helm_w, HELMET, "head") < 0:
		push_error("%s: the helmet would not go on" % lane)
		return false
	var helmed_head: float = _strike(helm_w, "head", 3.0)
	if helmed_head >= bare_head:
		push_error("%s: a head hit took %.4f through a helmet and %.4f through nothing" % [lane, helmed_head, bare_head])
		return false

	# The textual half. Follow the call rather than the line: `armor_damage_factor` has to be
	# multiplied into the damage inside `damage_part`, and `damage_part` has to be the only thing
	# in this file that writes a body part. CLAUDE.md's note about needles that stop finding their
	# reader after a refactor is why both halves are here and neither is alone.
	var code: String = FileAccess.get_file_as_string("res://sim/modules/health.gd")
	if code.is_empty():
		push_error("%s: health.gd could not be read, so the textual half is asserting nothing" % lane)
		return false
	if not code.contains("taken *= armor_damage_factor(world, target, named_part)"):
		push_error("%s: health.gd no longer multiplies the armour factor into the blow -- follow the call, do not drop the needle" % lane)
		return false
	var writes: int = code.count("b[named_part] = ")
	if writes != 1:
		push_error("%s: health.gd assigns into a body part %d times; `damage_part` must be the only one, or a second path is taking damage nothing mitigates" % [lane, writes])
		return false
	# And the copy that used to live downstream really is gone, or coverage is counted twice and
	# every vest is quietly worth twice what the content says.
	var wounds_code: String = FileAccess.get_file_as_string("res://sim/modules/wounds.gd")
	if wounds_code.is_empty():
		push_error("%s: wounds.gd could not be read" % lane)
		return false
	if wounds_code.contains("armor_coverage_of"):
		push_error("%s: wounds.gd reads coverage again -- `severity_for` gave its armour term up to `damage_part`, and two copies square it" % lane)
		return false

	print("  PATHS OK a bite took %.4f vested against %.4f bare, a head hit %.4f helmeted against %.4f bare; one writer, one multiply, and severity reads no coverage" % [vested_bite, bare_bite, helmed_head, bare_head])
	return true


# --- PLATE ------------------------------------------------------------------------------------
# The two halves of this slice, joined: an attachment slot that changes what a fight costs. A
# plate in the carrier is worth more integrity than the carrier alone, and an empty carrier is
# worth nothing -- which is `blocked_reason` reaching all the way through the fold and into the
# damage, three modules apart.
func _a_fitted_plate_stops_more_than_the_carrier_alone() -> bool:
	var lane: String = "PLATE"
	var blow: float = 8.0

	var w: Variant = _world(9300)
	var carrier: int = _wear(w, CARRIER, "vest")
	if carrier < 0:
		push_error("%s: the plate carrier would not go on" % lane)
		return false
	var fitted: int = SimAttachments.in_slot(w, carrier, "plate")
	if fitted < 0:
		push_error("%s: the carrier spawned with no plate, so this lane has nothing to take out" % lane)
		return false
	var with_plate: float = _strike(w, TORSO, blow)

	# The same carrier with the plate pulled. It is blocked now, so it is worth nothing -- the
	# torso takes the whole blow, exactly as if the survivor were in a shirt.
	var w2: Variant = _world(9300)
	var carrier2: int = _wear(w2, CARRIER, "vest")
	if carrier2 < 0:
		push_error("%s: the plate carrier would not go on" % lane)
		return false
	if not SimAttachments.detach(w2, SimAttachments.in_slot(w2, carrier2, "plate")):
		push_error("%s: the plate would not come out" % lane)
		return false
	var without_plate: float = _strike(w2, TORSO, blow)
	if with_plate >= without_plate:
		push_error("%s: a plated carrier gave up %.4f and an empty one %.4f -- the plate is buying nothing" % [lane, with_plate, without_plate])
		return false
	if not is_equal_approx(without_plate, blow):
		push_error("%s: an empty carrier is webbing and should stop nothing, and it stopped %.4f of %.4f" % [lane, blow - without_plate, blow])
		return false

	# TN, and it is the one that separates "the plate does something" from "the carrier does
	# something": a *better* plate than the one it came with has to be better still. The steel
	# plate is a bigger multiplier than the ceramic the carrier defaults, so swapping it in must
	# take another slice off the same blow.
	var w3: Variant = _world(9300)
	var carrier3: int = _wear(w3, CARRIER, "vest")
	if carrier3 < 0:
		push_error("%s: the plate carrier would not go on" % lane)
		return false
	if not SimAttachments.detach(w3, SimAttachments.in_slot(w3, carrier3, "plate")):
		push_error("%s: the default plate would not come out" % lane)
		return false
	var steel: int = SimItems.spawn_item(w3, PLATE, {"tier": "scavenged"})
	if steel < 0 or not SimAttachments.attach(w3, carrier3, steel, "plate"):
		push_error("%s: the steel plate would not go in" % lane)
		return false
	var with_steel: float = _strike(w3, TORSO, blow)
	if with_steel >= with_plate:
		push_error("%s: a steel plate gave up %.4f where the ceramic gave up %.4f, and steel is the heavier multiplier" % [lane, with_steel, with_plate])
		return false

	print("  PLATE OK a blow of %.2f took %.4f through a ceramic-plated carrier, %.4f through a steel-plated one, and all %.4f through an empty one" % [blow, with_plate, with_steel, without_plate])
	return true


# --- BANDS ------------------------------------------------------------------------------------
# The calibration claim, and the reason this slice did not need a new number. The wound a covered
# part opens has to land in the band it landed in before mitigation existed: `severity_for` used
# to soften the fraction by `1 - 0.5 * coverage` itself and now receives damage already softened
# by the identical curve, so the arithmetic is the same arithmetic done once.
#
# The fixture is `check_m2_wounds.gd`'s own ARMOR lane restated -- 18 damage to a scrap-vested
# torso -- because that lane is the one whose printed numbers are the before-picture: it said
# `bare=2 armored=1` before this slice and says `bare=2 armored=1` after it.
func _the_bands_are_where_they_were_before_the_slice() -> bool:
	var lane: String = "BANDS"

	var bare_w: Variant = _world(9400)
	_strike(bare_w, TORSO, 18.0)
	var bare_sev: int = _first_severity(bare_w)

	var vest_w: Variant = _world(9400)
	if _wear(vest_w, SCRAP_VEST, "vest") < 0:
		push_error("%s: the scrap vest would not go on" % lane)
		return false
	_strike(vest_w, TORSO, 18.0)
	var armored_sev: int = _first_severity(vest_w)

	if bare_sev < 0 or armored_sev < 0:
		push_error("%s: a hit recorded no wound (bare=%d armored=%d); the comparison below would have passed on the sentinel" % [lane, bare_sev, armored_sev])
		return false
	# The two numbers this slice promised not to move.
	if bare_sev != int(SimWounds.Severity.DeepWound):
		push_error("%s: 18 damage to a bare torso banded %d, and it banded a deep wound before the slice" % [lane, bare_sev])
		return false
	if armored_sev != int(SimWounds.Severity.Laceration):
		push_error("%s: 18 damage to a scrap-vested torso banded %d, and it banded a laceration before the slice" % [lane, armored_sev])
		return false

	# TN: the band has to still be able to move at all. An uncovered part at the same damage is
	# the case where nothing softens anything, and it must land where the bare torso landed.
	var foot_w: Variant = _world(9401)
	if _wear(foot_w, SCRAP_VEST, "vest") < 0:
		push_error("%s: the scrap vest would not go on" % lane)
		return false
	_strike(foot_w, FOOT, 4.0)
	var foot_sev: int = _first_severity(foot_w)
	var bare_foot_w: Variant = _world(9401)
	_strike(bare_foot_w, FOOT, 4.0)
	if foot_sev != _first_severity(bare_foot_w):
		push_error("%s: a vest covers no foot and banded it %d against a bare %d" % [lane, foot_sev, _first_severity(bare_foot_w)])
		return false

	print("  BANDS OK 18 to a torso bands %d bare and %d scrap-vested, exactly as it did before mitigation; an uncovered foot bands %d either way" % [bare_sev, armored_sev, foot_sev])
	return true


func _first_severity(w: Variant) -> int:
	var inj: Variant = w.components.get_component(w.player, "injuries")
	if not (inj is Dictionary):
		return -1
	var wounds: Array = (inj as Dictionary).get("wounds", []) as Array
	if wounds.is_empty():
		return -1
	return int((wounds[0] as Dictionary).get("severity", -1))


# --- BAN --------------------------------------------------------------------------------------
# The standing ban, asked of this slice specifically. Mitigation is a number the sim knows and the
# screen must not: if the condition view grew so much as a coverage fraction, a fill would become
# computable and docs/01 clause 4 would be gone. `npm run godot:ban:healthbar` is the gate that
# owns the ban; this lane is the local assertion that *this* change did not widen it, which is
# cheaper to read at the point of failure than a ban gate going red for unexplained reasons.
func _the_screen_learns_nothing_it_could_build_a_bar_from() -> bool:
	var lane: String = "BAN"
	var w: Variant = _world(9500)
	var carrier: int = _wear(w, CARRIER, "vest")
	if carrier < 0:
		push_error("%s: the plate carrier would not go on" % lane)
		return false
	_strike(w, TORSO, 9.0)

	var view: Dictionary = SimCondition.view(w, w.player)
	var parts: Array = view.get("parts", []) as Array
	if parts.is_empty():
		push_error("%s: the condition view has no parts, so this lane is asserting nothing" % lane)
		return false
	var judged: int = 0
	for row_v in parts:
		var row: Dictionary = row_v as Dictionary
		for key in row.keys():
			if not SimCondition.PART_KEYS.has(String(key)):
				push_error("%s: a part carries '%s', which is not in SimCondition.PART_KEYS -- mitigation must not put a number on the screen" % [lane, String(key)])
				return false
		# `armored` is the only thing the screen learns about armour and it is a boolean. A float
		# here would be a coverage fraction, and a coverage fraction plus a state is most of a bar.
		if not (row.get("armored") is bool):
			push_error("%s: `armored` came back as %s, and it is the field that must stay a boolean" % [lane, str(row.get("armored"))])
			return false
		judged += 1

	# The plated torso is armoured and a bare foot is not -- so the boolean is actually being
	# computed rather than being `true` everywhere, which is the failure mode
	# check_ban_health_bar.gd's own convention note was written about.
	var armoured_torso: bool = false
	var armoured_foot: bool = true
	for row_v2 in parts:
		var row2: Dictionary = row_v2 as Dictionary
		if String(row2.get("part", "")) == TORSO:
			armoured_torso = bool(row2.get("armored", false))
		if String(row2.get("part", "")) == FOOT:
			armoured_foot = bool(row2.get("armored", false))
	if not armoured_torso:
		push_error("%s: a plated carrier left the torso reading unarmoured" % lane)
		return false
	if armoured_foot:
		push_error("%s: a vest covers no foot and the foot reads armoured, so the boolean is not being computed" % lane)
		return false

	print("  BAN OK %d parts, every key in PART_KEYS, `armored` a boolean, true on a plated torso and false on a bare foot" % judged)
	return true


# --- STRUCK -----------------------------------------------------------------------------------
# The plate wears as it stops blows (docs/30, "The plate wears, 2026-10-27"). `struck` is the
# target's wear word, called from `damage_part` for every worn garment that covered the part the
# blow landed on, and it wears that garment's parts whose own `armor` names the part.
#
# The amount is exact rather than banded, because there is no roll in it: N blows to a covered
# torso take N * PART_WEAR_PER_EVENT * wearRate * condition_loss off the plate, and a gate that
# allowed slack here would let a second call per blow through. Then the reader, measured as an
# outcome: the next blow through the worn plate takes more off the body than the same blow through
# a fresh one, which is `effect_scale` reaching all the way into the damage.
func _part_condition(w: Variant, item: int) -> float:
	var c: Variant = w.components.get_component(item, "condition")
	return float((c as Dictionary).get("current", -1.0)) if c is Dictionary else -1.0


func _per_blow(w: Variant, part: int) -> float:
	var spec: Dictionary = SimAttachments.spec_of(w, part) as Dictionary
	return SimAttachments.PART_WEAR_PER_EVENT * float(spec.get("wearRate", 1.0)) * SimItems.condition_loss_of(w, part)


# A carrier with its ceramic plate, an aramid lining and a pouch: one part that covers only the
# chest, one that covers the chest and the arms, and one that covers nothing.
func _rig(w: Variant) -> Dictionary:
	var carrier: int = _wear(w, CARRIER, "vest")
	if carrier < 0:
		return {}
	var lining: int = SimItems.spawn_item(w, LINING, {"tier": "scavenged"})
	var pouch: int = SimItems.spawn_item(w, POUCH, {"tier": "scavenged"})
	if lining < 0 or pouch < 0:
		return {}
	if not SimAttachments.attach(w, carrier, lining, "lining") or not SimAttachments.attach(w, carrier, pouch, "pocket"):
		return {}
	var plate: int = SimAttachments.in_slot(w, carrier, "plate")
	if plate < 0:
		return {}
	return {"carrier": carrier, "plate": plate, "lining": lining, "pouch": pouch}


func _a_plate_wears_as_it_stops_blows() -> bool:
	var lane: String = "STRUCK"
	var blows: int = 12

	var w: Variant = _world(9600)
	var rig: Dictionary = _rig(w)
	if rig.is_empty():
		push_error("%s: the carrier, its ceramic plate, the lining and the pouch would not all go on, so nothing below is testing anything" % lane)
		return false
	var plate: int = int(rig["plate"])
	if String((SimItems.item_base_of(w, plate) as Dictionary).get("id", "")) != CERAMIC:
		push_error("%s: the carrier's plate is not the ceramic it ships with, and the rates below are its" % lane)
		return false
	var per_blow: float = _per_blow(w, plate)
	if per_blow <= 0.0:
		push_error("%s: the ceramic plate wears %.5f a blow -- it declares no `struck`, so this lane cannot be judged" % [lane, per_blow])
		return false
	var plate0: float = _part_condition(w, plate)
	var lining0: float = _part_condition(w, int(rig["lining"]))
	var pouch0: float = _part_condition(w, int(rig["pouch"]))
	var carrier0: float = _part_condition(w, int(rig["carrier"]))
	var cov0: float = SimInfection.armor_coverage_of(w, w.player, TORSO)
	if plate0 <= 0.0 or lining0 <= 0.0 or pouch0 <= 0.0 or carrier0 <= 0.0 or cov0 <= 0.0:
		push_error("%s: a fixture has no condition or no coverage (plate %.3f lining %.3f pouch %.3f carrier %.3f cov %.3f)" % [lane, plate0, lining0, pouch0, carrier0, cov0])
		return false

	# Light blows, so the torso outlives all of them: a dead body is struck by nothing.
	for i in blows:
		_strike(w, TORSO, 0.5)
	var plate_drop: float = plate0 - _part_condition(w, plate)
	var want: float = per_blow * float(blows)
	if absf(plate_drop - want) > 1e-6:
		push_error("%s: %d blows to the torso took %.6f off the plate, and %d * %.6f is %.6f" % [lane, blows, plate_drop, blows, per_blow, want])
		return false
	# The lining covers the chest too (1.05), so it wears on its own rate.
	var lining_drop: float = lining0 - _part_condition(w, int(rig["lining"]))
	var lining_want: float = _per_blow(w, int(rig["lining"])) * float(blows)
	if lining_want <= 0.0 or absf(lining_drop - lining_want) > 1e-6:
		push_error("%s: the lining covers the torso and lost %.6f to %d blows, where its rate says %.6f" % [lane, lining_drop, blows, lining_want])
		return false
	# TN: a part that declares no `struck` never wears, and neither does the garment itself.
	if not is_equal_approx(_part_condition(w, int(rig["pouch"])), pouch0):
		push_error("%s: the pouch declares no `struck` and wore from %.4f to %.4f" % [lane, pouch0, _part_condition(w, int(rig["pouch"]))])
		return false
	if not is_equal_approx(_part_condition(w, int(rig["carrier"])), carrier0):
		push_error("%s: the carrier's own condition moved from %.4f to %.4f, and nothing reads it" % [lane, carrier0, _part_condition(w, int(rig["carrier"]))])
		return false
	# Ceramic is the one that does not forgive: it wears faster than steel, and steel than aramid.
	var probe: Variant = _world(9601)
	var steel: int = SimItems.spawn_item(probe, PLATE, {"tier": "scavenged"})
	var soft: int = SimItems.spawn_item(probe, LINING, {"tier": "scavenged"})
	var steel_rate: float = _per_blow(probe, steel)
	var soft_rate: float = _per_blow(probe, soft)
	if not (per_blow > steel_rate and steel_rate > soft_rate and soft_rate > 0.0):
		push_error("%s: ceramic %.5f > steel %.5f > aramid %.5f > 0 does not hold" % [lane, per_blow, steel_rate, soft_rate])
		return false

	# The reader. Coverage fell with the plate, and the same blow now takes more off the body than
	# it does through a fresh rig on the same seed.
	var cov1: float = SimInfection.armor_coverage_of(w, w.player, TORSO)
	if cov1 >= cov0:
		push_error("%s: the plate wore %.4f and the torso's coverage went from %.4f to %.4f" % [lane, plate_drop, cov0, cov1])
		return false
	var worn_take: float = _strike(w, TORSO, 6.0)
	var fresh_w: Variant = _world(9600)
	if _rig(fresh_w).is_empty():
		push_error("%s: the fresh rig would not go on" % lane)
		return false
	var fresh_take: float = _strike(fresh_w, TORSO, 6.0)
	if worn_take <= fresh_take:
		push_error("%s: a blow of 6 took %.4f through the worn plate and %.4f through a fresh one" % [lane, worn_take, fresh_take])
		return false

	# A bite is a blow through the same closure, and it wears the plate the same step.
	var bite_w: Variant = _world(9602)
	var bite_rig: Dictionary = _rig(bite_w)
	if bite_rig.is_empty():
		push_error("%s: the bite rig would not go on" % lane)
		return false
	var bplate: int = int(bite_rig["plate"])
	var b0: float = _part_condition(bite_w, bplate)
	_bite(bite_w, TORSO, 0.5)
	if absf((b0 - _part_condition(bite_w, bplate)) - _per_blow(bite_w, bplate)) > 1e-6:
		push_error("%s: a bite to the torso took %.6f off the plate and a blow takes %.6f" % [lane, b0 - _part_condition(bite_w, bplate), _per_blow(bite_w, bplate)])
		return false

	print("  STRUCK OK %d torso blows took %.4f off the ceramic plate (%.4f each) and %.4f off the lining, the pouch and the carrier none; coverage %.4f to %.4f, a blow of 6 took %.4f worn against %.4f fresh; a bite wears it the same" % [blows, plate_drop, per_blow, lining_drop, cov0, cov1, worn_take, fresh_take])
	return true


# --- COVERS -----------------------------------------------------------------------------------
# What did not stop the blow does not pay for it. A blow to the leg wears nothing the carrier
# holds; a blow to the arm wears the lining, which covers the arm, and leaves the plate, which does
# not; a carrier with its plate pulled stops nothing, so its lining wears nothing; and the side that
# swung is never `struck` -- a vested survivor's own swing leaves their plate alone, and a weapon in
# a struck survivor's hands is not armour and is not worn by the blow. Under layers, only the garment
# with the most coverage of the part stopped the blow, and only it wears.
func _only_what_covered_the_blow_wears() -> bool:
	var lane: String = "COVERS"

	var w: Variant = _world(9700)
	var rig: Dictionary = _rig(w)
	if rig.is_empty():
		push_error("%s: the rig would not go on" % lane)
		return false
	var plate: int = int(rig["plate"])
	var lining: int = int(rig["lining"])
	var plate0: float = _part_condition(w, plate)
	var lining0: float = _part_condition(w, lining)

	_strike(w, "leg_left", 0.5)
	if not is_equal_approx(_part_condition(w, plate), plate0) or not is_equal_approx(_part_condition(w, lining), lining0):
		push_error("%s: a blow to the leg wore the vest (plate %.4f to %.4f, lining %.4f to %.4f)" % [lane, plate0, _part_condition(w, plate), lining0, _part_condition(w, lining)])
		return false

	_strike(w, "arm_left", 0.5)
	if not is_equal_approx(_part_condition(w, plate), plate0):
		push_error("%s: the plate covers only the chest and a blow to the arm wore it from %.4f to %.4f" % [lane, plate0, _part_condition(w, plate)])
		return false
	var arm_drop: float = lining0 - _part_condition(w, lining)
	if absf(arm_drop - _per_blow(w, lining)) > 1e-6:
		push_error("%s: the lining covers the arm and a blow there took %.6f off it, where its rate says %.6f" % [lane, arm_drop, _per_blow(w, lining)])
		return false

	# The empty carrier: blocked, so it covered nothing and wears nothing.
	var bw: Variant = _world(9701)
	var brig: Dictionary = _rig(bw)
	if brig.is_empty() or not SimAttachments.detach(bw, int(brig["plate"])):
		push_error("%s: the plate would not come out of the second rig" % lane)
		return false
	if SimInfection.armor_coverage_of(bw, bw.player, TORSO) > 0.0:
		push_error("%s: an empty carrier still covers the torso, so the next assertion cannot be judged" % lane)
		return false
	var bl0: float = _part_condition(bw, int(brig["lining"]))
	_strike(bw, TORSO, 0.5)
	_strike(bw, "arm_left", 0.5)
	if not is_equal_approx(_part_condition(bw, int(brig["lining"])), bl0):
		push_error("%s: an empty carrier stops nothing and its lining wore from %.4f to %.4f" % [lane, bl0, _part_condition(bw, int(brig["lining"]))])
		return false

	# The attacker's side. The vested survivor swings and connects; their plate is not struck.
	var aw: Variant = _world(9702)
	var arig: Dictionary = _rig(aw)
	if arig.is_empty():
		push_error("%s: the attacker's rig would not go on" % lane)
		return false
	var victim: int = int(aw.entities.spawn())
	SimHealth.make_survivor_body(aw, victim)
	var ap0: float = _part_condition(aw, int(arig["plate"]))
	aw.events.publish({"type": "attack.connected", "attacker": aw.player, "target": victim, "bodyPart": TORSO, "damage": 2.0})
	aw.step()
	if float((aw.components.get_component(victim, "body") as Dictionary)[TORSO]) >= 40.0:
		push_error("%s: the swing never landed on the victim, so the attacker's plate is judged on nothing" % lane)
		return false
	if not is_equal_approx(_part_condition(aw, int(arig["plate"])), ap0):
		push_error("%s: the survivor who swung wore their own plate from %.4f to %.4f" % [lane, ap0, _part_condition(aw, int(arig["plate"]))])
		return false

	# A weapon in a struck survivor's hands: its head declares `hit`, not `struck`, and the weapon
	# is not armour, so the blow leaves it alone while the plate on the same body wears.
	var hw: Variant = _world(9703)
	var hrig: Dictionary = _rig(hw)
	var spear: int = SimItems.spawn_item(hw, SPEAR, {"tier": "scavenged"})
	if hrig.is_empty() or spear < 0 or not SimInventory.equip(hw, hw.player, spear):
		push_error("%s: the spear would not go into the struck survivor's hands" % lane)
		return false
	var head: int = SimAttachments.in_slot(hw, spear, "head")
	if head < 0:
		push_error("%s: the spear has no head, so there is no weapon part to leave alone" % lane)
		return false
	var head0: float = _part_condition(hw, head)
	var hp0: float = _part_condition(hw, int(hrig["plate"]))
	_strike(hw, TORSO, 0.5)
	if not is_equal_approx(_part_condition(hw, head), head0):
		push_error("%s: a blow to the torso wore the spear's head from %.4f to %.4f" % [lane, head0, _part_condition(hw, head)])
		return false
	if is_equal_approx(_part_condition(hw, int(hrig["plate"])), hp0):
		push_error("%s: the same blow left the plate on the same body unworn, so the spear's head proves nothing" % lane)
		return false

	# Layers. A lined jacket under the carrier: the carrier covers the torso more (0.7 fitted up
	# against 0.5), the jacket covers the arms more (0.5 against 0.15), and only the garment that
	# stopped the blow wears, the way `armor_coverage_of` composes coverage (max, never sum). So a
	# torso blow wears the carrier's plate and lining and not the jacket's lining; an arm blow wears
	# the jacket's lining and not the carrier's; and with the carrier's plate pulled the carrier
	# covers nothing, so a torso blow wears the jacket's lining after all.
	var lw: Variant = _world(9704)
	var lrig: Dictionary = _rig(lw)
	var jacket: int = _wear(lw, JACKET, "torso")
	var jlining: int = SimItems.spawn_item(lw, LINING, {"tier": "scavenged"})
	if lrig.is_empty() or jacket < 0 or jlining < 0 or not SimAttachments.attach(lw, jacket, jlining, "lining"):
		push_error("%s: the lined jacket would not go on under the carrier" % lane)
		return false
	var jbase: Dictionary = SimItems.item_base_of(lw, jacket) as Dictionary
	var cbase: Dictionary = SimItems.item_base_of(lw, int(lrig["carrier"])) as Dictionary
	var jarm: Dictionary = jbase.get("armor", {}) as Dictionary
	var carm: Dictionary = cbase.get("armor", {}) as Dictionary
	if not (float(carm.get(TORSO, 0.0)) > float(jarm.get(TORSO, 0.0)) and float(jarm.get("arm_left", 0.0)) > float(carm.get("arm_left", 0.0))):
		push_error("%s: the fixture needs the carrier to cover the torso more and the jacket the arm more, and the catalogue no longer says so" % lane)
		return false
	var lplate: int = int(lrig["plate"])
	var clining: int = int(lrig["lining"])
	var lp0: float = _part_condition(lw, lplate)
	var cl0: float = _part_condition(lw, clining)
	var jl0: float = _part_condition(lw, jlining)
	_strike(lw, TORSO, 0.5)
	if absf((lp0 - _part_condition(lw, lplate)) - _per_blow(lw, lplate)) > 1e-6 or absf((cl0 - _part_condition(lw, clining)) - _per_blow(lw, clining)) > 1e-6:
		push_error("%s: a torso blow under a lined jacket wore the carrier's plate %.6f and lining %.6f, not their rates" % [lane, lp0 - _part_condition(lw, lplate), cl0 - _part_condition(lw, clining)])
		return false
	if not is_equal_approx(_part_condition(lw, jlining), jl0):
		push_error("%s: the carrier stopped the torso blow and the jacket's lining under it wore from %.4f to %.4f" % [lane, jl0, _part_condition(lw, jlining)])
		return false
	cl0 = _part_condition(lw, clining)
	_strike(lw, "arm_left", 0.5)
	if absf((jl0 - _part_condition(lw, jlining)) - _per_blow(lw, jlining)) > 1e-6:
		push_error("%s: the jacket covers the arm most and an arm blow took %.6f off its lining, where its rate says %.6f" % [lane, jl0 - _part_condition(lw, jlining), _per_blow(lw, jlining)])
		return false
	if not is_equal_approx(_part_condition(lw, clining), cl0):
		push_error("%s: the jacket stopped the arm blow and the carrier's lining wore from %.4f to %.4f" % [lane, cl0, _part_condition(lw, clining)])
		return false
	jl0 = _part_condition(lw, jlining)
	if not SimAttachments.detach(lw, lplate) or SimInfection.armor_coverage_of(lw, lw.player, TORSO) <= 0.0:
		push_error("%s: the plate would not come out of the layered carrier, or the jacket under it covers no torso" % lane)
		return false
	cl0 = _part_condition(lw, clining)
	_strike(lw, TORSO, 0.5)
	if absf((jl0 - _part_condition(lw, jlining)) - _per_blow(lw, jlining)) > 1e-6:
		push_error("%s: with the carrier's plate pulled the jacket stops the torso blow, and its lining took %.6f, where its rate says %.6f" % [lane, jl0 - _part_condition(lw, jlining), _per_blow(lw, jlining)])
		return false
	if not is_equal_approx(_part_condition(lw, clining), cl0):
		push_error("%s: the emptied carrier stops nothing and its lining still wore from %.4f to %.4f" % [lane, cl0, _part_condition(lw, clining)])
		return false

	print("  COVERS OK a leg blow wore nothing; an arm blow wore the lining %.4f and not the plate; an empty carrier's lining stayed %.4f; the swinger's plate and the struck survivor's spear head stayed whole; under layers only the garment that stopped the blow wore" % [arm_drop, bl0])
	return true


# --- REACHED ----------------------------------------------------------------------------------
# The dead-socket lane. The shipped district, booted the way the game boots it, with a shambler
# beside a vested player held on the spot, and nothing else driven by hand but the tick: every blow that lands on the
# player's torso -- a swipe, or a bite once a grab takes hold -- must have worn the plate by exactly
# its share. If `damage_part` stopped calling the wear, or the wear stopped reaching the plate, the
# plate would still read full here with torso blows on the record.
func _a_shambler_in_the_district_wears_the_plate() -> bool:
	var lane: String = "REACHED"
	var w: Variant = SimBoot.playable(20260805, 64)["world"]
	var carrier: int = SimItems.spawn_item(w, CARRIER, {"tier": "scavenged"})
	if carrier < 0 or not SimInventory.equip(w, w.player, carrier, "vest"):
		push_error("%s: the carrier would not go on the player in the playable boot" % lane)
		return false
	var plate: int = SimAttachments.in_slot(w, carrier, "plate")
	if plate < 0:
		push_error("%s: the carrier came with no plate" % lane)
		return false
	var per_blow: float = _per_blow(w, plate)
	var plate0: float = _part_condition(w, plate)
	var pos: Dictionary = w.components.get_component(w.player, "position") as Dictionary
	var z: int = SimRoster.spawn_zombie(w, float(pos["x"]) - 0.8, float(pos["y"]), SimRoster.TYPE_SHAMBLER, w.rng.stream("shambler"))
	if z < 0:
		push_error("%s: no shambler would spawn beside the player" % lane)
		return false
	var torso_blows: Array = []
	for type in ["attack.connected", "bite.landed"]:
		var t: String = String(type)
		w.events.subscribe({"id": "gate.struck-%s" % t, "type": t, "order": -100, "handler": func(e: Dictionary) -> void:
			var who: int = int(e.get("target", e.get("victim", -1)))
			if who != int(w.player) or String(e.get("bodyPart", "")) != TORSO:
				return
			var body: Variant = w.components.get_component(w.player, "body")
			if body is Dictionary and SimHealth.is_alive(body as Dictionary) and float((body as Dictionary)[TORSO]) > 0.0:
				torso_blows.append(t)
		})
	# The player is held on the spot: left alone the boot walks them off on their own business, and
	# a lane about what a blow wears needs the blow to land. Nothing else is touched by hand.
	var px: float = float(pos["x"])
	var py: float = float(pos["y"])
	for i in 1200:
		w.step()
		var here: Dictionary = w.components.get_component(w.player, "position") as Dictionary
		here["x"] = px
		here["y"] = py
		if torso_blows.size() >= 2:
			break
	if torso_blows.is_empty():
		push_error("%s: 1200 ticks beside a shambler and no blow landed on the player's torso, so the plate is judged on nothing" % lane)
		return false
	var drop: float = plate0 - _part_condition(w, plate)
	var want: float = per_blow * float(torso_blows.size())
	if drop <= 0.0:
		push_error("%s: %d blows landed on the vested torso through the tick loop and the plate did not wear -- `struck` is a dead socket" % [lane, torso_blows.size()])
		return false
	if absf(drop - want) > 1e-6:
		push_error("%s: %d torso blows (%s) took %.6f off the plate, and their share is %.6f" % [lane, torso_blows.size(), str(torso_blows), drop, want])
		return false
	print("  REACHED OK in the playable district a shambler landed %d torso blows (%s) on the vested player and the plate wore %.4f, exactly its share" % [torso_blows.size(), str(torso_blows), drop])
	return true
