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

# Fixtures, not welds. The sim names none of these -- it asks content for a number -- but a gate
# has to hold something concrete, and these are the rungs the catalogue ships: a vest that covers
# a torso well and an arm less, a helmet, and the carrier whose whole character is that it is
# nothing without its plate.
const VEST: String = "item.vest.riot"
const SCRAP_VEST: String = "item.vest.scrap"
const HELMET: String = "item.helmet.bike"
const CARRIER: String = "item.vest.carrier"
const PLATE: String = "item.armorpart.plate.steel"

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
	if ok:
		print("M2_ARMOR_OK factor stops paths plate bands ban")
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
