extends SceneTree
# Medical quality tiers -- docs/05-health-injury.md, and the owner's decisions of 2026-09-12.
#
# Three supplies were welded to one base id each: `ANTIBIOTICS_ID` in infection.gd, `PAINKILLERS_ID`
# in wounds.gd, and `item.bandage.cloth` written three times inside jobs.gd's colonist doctor. A
# second antibiotic was a code change. Meanwhile `bandageTier`, `cleanTier` and `closeKind` had
# solved exactly this three times over, so the fix is their shape rather than a new one: a flat
# scalar under an enum, ranked best-first by a code-owned order, picked by one shared scan.
#
# The lane that matters most is PINNED. Everything else here is new behaviour, but the retrofit --
# `item.antibiotics.course` becoming `clinical` and `item.painkillers.blister` becoming `mild` --
# has to reproduce the old numbers *exactly*, or this slice is not a new mechanism, it is a silent
# rebalance of every treatment in the game wearing one. Slice 1's DEFAULT lane pinned a pistol at
# noise 180 and damage 18 for the same reason and is the precedent.
#
# Every lane carries a true negative, and every behavioural lane measures the *effect* rather than
# the table that produced it -- a dictionary that says a grade is better is a dictionary comparing
# itself. A gate that cannot fail is worse than no gate.

const World = preload("res://sim/world.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const SimTreatment = preload("res://sim/modules/treatment.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")

# The shipped bases these lanes put in a pack. Fixtures, not welds: the sim names none of them any
# more, and that is the whole point of the slice -- but a gate still has to hold something concrete.
const COURSE_CLINICAL: String = "item.antibiotics.course"
const COURSE_VET: String = "item.antibiotics.veterinary"
const COURSE_IMPROVISED: String = "item.antibiotics.expired"
const PAIN_MILD: String = "item.painkillers.blister"
const PAIN_OPIOID: String = "item.painkillers.opioid"
const REMEDY_FLUIDS: String = "item.salts.rehydration"
const REMEDY_FULL: String = "item.tablets.antinausea"
const DRESSING_STERILE: String = "item.gauze.sterile"
const DRESSING_DIRTY: String = "item.rag.dirty"
const WRAP: String = "item.wrap.elastic"
const SUTURE: String = "item.suture.kit"

const PART: String = "torso"
# Paired seeds for the CLEAR lane. Both grades draw from the same named stream in identically
# seeded worlds, so the same seed hands both the same roll -- which is what makes a probabilistic
# assertion deterministic here rather than flaky.
const CLEAR_SEEDS: Array[int] = [11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
	21, 22, 23, 24, 25, 26, 27, 28, 29, 30]

# Which module owns each grade, so CONTENT can walk all three the same way.
const GRADES: Array[Dictionary] = [
	{"key": "antibioticTier", "order": SimInfection.ANTIBIOTIC_ORDER, "what": "antibiotics"},
	{"key": "painTier", "order": SimWounds.PAIN_ORDER, "what": "painkillers"},
	{"key": "illnessTier", "order": SimNeeds.ILLNESS_ORDER, "what": "illness treatment"},
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _the_retrofit_reproduces_the_old_numbers() and ok
	ok = _every_grade_is_declared_and_reachable() and ok
	ok = _the_best_grade_in_the_pack_is_the_one_spent() and ok
	ok = _a_grade_sets_how_deep_and_how_long() and ok
	ok = _a_better_course_clears_more_often() and ok
	ok = _a_remedy_shortens_or_ends_a_bout() and ok
	ok = _the_colonist_reaches_for_the_best_dressing() and ok
	ok = _a_sprain_can_finally_be_wrapped() and ok
	if ok:
		print("M2_MEDICINE_OK pinned content rank dose clear illness fetch wrap")
		quit(0)
	else:
		push_error("M2_MEDICINE_FAIL")
		quit(1)


func _world(seed_val: int = 4101) -> Variant:
	var fixture: Dictionary = {
		"seed": seed_val,
		"tick_hz": 20,
		"map": {"width": 32, "height": 32, "walls": []},
		"player": {"id": 0, "x": 8.5, "y": 16.5, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	}
	var w: Variant = World.new(fixture)
	SimHealth.register_module(w)
	SimWounds.register_module(w)
	SimTreatment.register_module(w)
	SimHealth.make_survivor_body(w, w.player)
	SimHealth.make_stamina(w, w.player, 100)
	SimInventory.make_inventory(w, w.player)
	SimNeeds.attach(w, w.player)
	return w


func _give(w: Variant, id: String, count: int = 1) -> int:
	var item: int = SimItems.spawn_item(w, id, {"tier": "scavenged", "count": count})
	if not SimInventory.stow(w, w.player, item):
		push_error("the fixture '%s' would not go in a pocket" % id)
		return -1
	return item


func _entry(w: Variant, id: String) -> Dictionary:
	var e: Variant = SimItems.content_entry(w, "item", id)
	return (e as Dictionary) if e is Dictionary else {}


func _expose(w: Variant) -> void:
	w.components.set_component(w.player, "zombieInfection", {"exposures": [{
		"source": -1, "bodyPart": PART, "exposedAtTick": int(w.tick), "transmitted": true,
		"stage": SimInfection.Stage.Latent, "stageEnteredAtTick": int(w.tick),
		"cauterized": false, "amputated": false,
	}]})


# --- PINNED -----------------------------------------------------------------------------------
#
# The retrofit is additive or it is a rebalance. `clinical` must multiply by exactly 1.0 and `mild`
# must be the old 0.7 for the old 7200 ticks, and the two shipped bases must actually carry those
# grades -- a perfect table on items that declare nothing would leave both supplies unusable.
func _the_retrofit_reproduces_the_old_numbers() -> bool:
	var mild: Dictionary = SimWounds.PAIN_BY_TIER.get("mild", {}) as Dictionary
	if int(mild.get("ticks", -1)) != SimWounds.PAINKILLER_TICKS:
		push_error("PINNED: mild runs %d ticks against the pinned %d" % [int(mild.get("ticks", -1)), SimWounds.PAINKILLER_TICKS])
		return false
	if absf(float(mild.get("suppression", -1.0)) - SimWounds.PAINKILLER_SUPPRESSION) > 0.0001:
		push_error("PINNED: mild suppresses %.4f against the pinned %.4f" % [float(mild.get("suppression", -1.0)), SimWounds.PAINKILLER_SUPPRESSION])
		return false
	var clinical_mul: float = float(SimInfection.ANTIBIOTIC_CLEAR_MUL.get("clinical", -1.0))
	if absf(clinical_mul - 1.0) > 0.0001:
		push_error("PINNED: a clinical course multiplies the clear chance by %.4f, not 1.0 -- the retrofit moved the old number" % clinical_mul)
		return false
	# Every grade below the top must actually be worse, or the axis is decoration.
	for grade in ["veterinary", "improvised"]:
		if float(SimInfection.ANTIBIOTIC_CLEAR_MUL.get(grade, 1.0)) >= 1.0:
			push_error("PINNED: '%s' is no worse than clinical" % grade)
			return false
	var w: Variant = _world()
	var course: Dictionary = _entry(w, COURSE_CLINICAL)
	if String(course.get("antibioticTier", "")) != "clinical":
		push_error("PINNED: '%s' declares antibioticTier '%s' -- the shipped course was not retrofitted, so nothing in the game is clinical" % [COURSE_CLINICAL, String(course.get("antibioticTier", ""))])
		return false
	var blister: Dictionary = _entry(w, PAIN_MILD)
	if String(blister.get("painTier", "")) != "mild":
		push_error("PINNED: '%s' declares painTier '%s' -- the shipped blister was not retrofitted" % [PAIN_MILD, String(blister.get("painTier", ""))])
		return false
	print("  PINNED: clinical x%.1f, mild %.2f for %d ticks, and both shipped bases carry their rung" % [clinical_mul, SimWounds.PAINKILLER_SUPPRESSION, SimWounds.PAINKILLER_TICKS])
	return true


# --- CONTENT ----------------------------------------------------------------------------------
#
# Both directions, the way check_m2_attach.gd's CONTENT and HOSTS lanes run: every grade the code
# ranks is declared by some shipped base (a rank nothing can reach is a dead branch), and every
# value some base declares is a grade the code ranks (a grade nothing ranks is dead content). Then
# the reachability question on top -- an item in no loot table is complete, correct and unfindable.
func _every_grade_is_declared_and_reachable() -> bool:
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

	var counted: int = 0
	for spec in GRADES:
		var key: String = String(spec["key"])
		var order: Array = spec["order"] as Array
		var seen: Dictionary = {}
		for file_v in (w.content as Dictionary).values():
			if not (file_v is Array):
				continue
			for entry_v in file_v as Array:
				if not (entry_v is Dictionary):
					continue
				var e: Dictionary = entry_v as Dictionary
				var value: String = String(e.get(key, ""))
				if value == "":
					continue
				var id: String = String(e.get("id", ""))
				if not order.has(value):
					push_error("CONTENT: '%s' declares %s '%s', which %s ranks nowhere -- content that has outrun its reader" % [id, key, value, String(spec["what"])])
					return false
				if not findable.has(id):
					push_error("CONTENT: '%s' declares %s and sits in no loot table -- complete, correct and unreachable" % [id, key])
					return false
				seen[value] = true
				counted += 1
		for grade in order:
			if not seen.has(String(grade)):
				push_error("CONTENT: %s ranks '%s' and no shipped base declares it -- a rank nothing can reach" % [key, String(grade)])
				return false
	if counted < 8:
		push_error("CONTENT: only %d graded supplies in the whole roster; this lane is judging almost nothing" % counted)
		return false
	print("  CONTENT: %d graded supplies across %d tables, every rank declared and every declaration ranked" % [counted, tables])
	return true


# --- RANK -------------------------------------------------------------------------------------
#
# The assertion that something *reads* the order. A pack holding the worst and the best of a grade
# must spend the best, whichever went in first -- both orderings, because a scan that simply keeps
# the last thing it saw passes one of them by luck.
func _the_best_grade_in_the_pack_is_the_one_spent() -> bool:
	for worst_first in [true, false]:
		var w: Variant = _world(4200 + (1 if worst_first else 2))
		_expose(w)
		var ids: Array = [COURSE_IMPROVISED, COURSE_CLINICAL] if worst_first else [COURSE_CLINICAL, COURSE_IMPROVISED]
		for id in ids:
			if _give(w, String(id)) < 0:
				return false
		if not SimInfection.carries_course(w, w.player):
			push_error("RANK: a pack with two courses in it reads as carrying none")
			return false
		var res: Dictionary = SimInfection.use_antibiotics(w, w.player)
		if not bool(res.get("ok", false)):
			push_error("RANK: a dose with two courses in the pack was refused: %s" % str(res))
			return false
		var state: Dictionary = w.components.get_component(w.player, "zombieInfection") as Dictionary
		var courses: Array = state.get("antibioticsCourses", []) as Array
		if courses.is_empty():
			push_error("RANK: no course was recorded")
			return false
		var spent: String = String((courses[0] as Dictionary).get("tier", ""))
		if spent != "clinical":
			push_error("RANK: with both in the pack the dose spent '%s', not the clinical one (worst stowed first: %s)" % [spent, str(worst_first)])
			return false
	print("  RANK: the best course in the pack is the one spent, whichever order it was stowed")
	return true


# --- DOSE -------------------------------------------------------------------------------------
#
# A grade sets how much is masked and for how long, and the running dose comes off the injury
# record rather than off the pack. That second half is the true negative for the obvious wrong
# implementation: re-deriving suppression from what is carried would let an ampoule dropped into
# the pack retroactively deepen a blister already wearing off.
func _a_grade_sets_how_deep_and_how_long() -> bool:
	var mild: Variant = _world(4300)
	SimWounds.append_wound(mild, mild.player, "fracture", "arm_left", -1, 0.0, "fracture", SimWounds.Severity.DeepWound)
	mild.step()
	if _give(mild, PAIN_MILD) < 0:
		return false
	var took_mild: Dictionary = SimWounds.take_painkillers(mild, mild.player)
	if not bool(took_mild.get("ok", false)):
		push_error("DOSE: the mild blister was refused: %s" % str(took_mild))
		return false
	if int(took_mild.get("ticks", -1)) != SimWounds.PAINKILLER_TICKS:
		push_error("DOSE: mild ran %d ticks, not the pinned %d" % [int(took_mild.get("ticks", -1)), SimWounds.PAINKILLER_TICKS])
		return false
	var mild_supp: float = SimWounds.suppression_of(mild, mild.player)
	if absf(mild_supp - SimWounds.PAINKILLER_SUPPRESSION) > 0.0001:
		push_error("DOSE: mild suppressed %.4f, not the pinned %.4f" % [mild_supp, SimWounds.PAINKILLER_SUPPRESSION])
		return false
	# The pack changes and the running dose does not.
	if _give(mild, PAIN_OPIOID) < 0:
		return false
	mild.step()
	if absf(SimWounds.suppression_of(mild, mild.player) - mild_supp) > 0.0001:
		push_error("DOSE: dropping an ampoule into the pack changed a dose already running, %.4f against %.4f -- suppression is being re-derived from what is carried" % [SimWounds.suppression_of(mild, mild.player), mild_supp])
		return false

	var strong: Variant = _world(4301)
	SimWounds.append_wound(strong, strong.player, "fracture", "arm_left", -1, 0.0, "fracture", SimWounds.Severity.DeepWound)
	strong.step()
	if _give(strong, PAIN_OPIOID) < 0:
		return false
	var took_opioid: Dictionary = SimWounds.take_painkillers(strong, strong.player)
	if not bool(took_opioid.get("ok", false)):
		push_error("DOSE: the ampoule was refused: %s" % str(took_opioid))
		return false
	var opioid_supp: float = SimWounds.suppression_of(strong, strong.player)
	if opioid_supp <= mild_supp:
		push_error("DOSE: the ampoule suppressed %.4f, no more than the blister's %.4f" % [opioid_supp, mild_supp])
		return false
	if opioid_supp >= 1.0:
		push_error("DOSE: the ampoule suppressed %.4f -- a survivor who can feel nothing at all has no signal left, and the condition view has no number to warn them with" % opioid_supp)
		return false
	if int(took_opioid.get("ticks", -1)) <= SimWounds.PAINKILLER_TICKS:
		push_error("DOSE: the ampoule ran %d ticks, no longer than the blister's %d" % [int(took_opioid.get("ticks", -1)), SimWounds.PAINKILLER_TICKS])
		return false
	print("  DOSE: mild %.2f for %d, opioid %.2f for %d, and the running dose ignores the pack" % [mild_supp, SimWounds.PAINKILLER_TICKS, opioid_supp, int(took_opioid.get("ticks", -1))])
	return true


# --- CLEAR ------------------------------------------------------------------------------------
#
# The grade has to reach the roll, not just the table. Paired worlds: the same seed hands both
# grades the same draw from the same named stream, so this is a probabilistic mechanism asserted
# deterministically. Two claims -- a weak course never clears where a clinical one fails
# (monotone), and there is at least one seed where the clinical one clears and the weak one does
# not (it actually matters). Without the second, a multiplier of 1.0 everywhere would pass.
func _a_better_course_clears_more_often() -> bool:
	var clinical_clears: int = 0
	var improvised_clears: int = 0
	var decided: int = 0
	for seed_val in CLEAR_SEEDS:
		var outcome: Dictionary = {}
		for id in [COURSE_CLINICAL, COURSE_IMPROVISED]:
			var w: Variant = _world(int(seed_val))
			_expose(w)
			if _give(w, String(id)) < 0:
				return false
			var res: Dictionary = SimInfection.use_antibiotics(w, w.player)
			if not bool(res.get("ok", false)):
				push_error("CLEAR: '%s' was refused on seed %d: %s" % [String(id), int(seed_val), str(res)])
				return false
			outcome[String(id)] = bool(res.get("clears", false))
		var top: bool = bool(outcome[COURSE_CLINICAL])
		var bottom: bool = bool(outcome[COURSE_IMPROVISED])
		if top:
			clinical_clears += 1
		if bottom:
			improvised_clears += 1
		if bottom and not top:
			push_error("CLEAR: on seed %d the expired strip cleared where the clinical course did not -- the grade is not reaching the roll in the right direction" % int(seed_val))
			return false
		if top and not bottom:
			decided += 1
	if decided == 0:
		push_error("CLEAR: over %d paired seeds the two grades never once disagreed -- the multiplier reaches the table and not the roll" % CLEAR_SEEDS.size())
		return false
	if clinical_clears <= improvised_clears:
		push_error("CLEAR: clinical cleared %d of %d and improvised %d -- no better" % [clinical_clears, CLEAR_SEEDS.size(), improvised_clears])
		return false
	print("  CLEAR: over %d paired seeds clinical cleared %d, improvised %d, and %d seeds turned on the grade alone" % [CLEAR_SEEDS.size(), clinical_clears, improvised_clears, decided])
	return true


# --- ILLNESS ----------------------------------------------------------------------------------
#
# The bout `illnessChance` has been able to hand out since food shipped, and which nothing in the
# game could do anything about. `fluids` cuts what is left, `remedy` ends it, and neither is
# offered to somebody who is well -- through `can_use`, so the menu predicate and the intake are
# one function and cannot disagree.
func _a_remedy_shortens_or_ends_a_bout() -> bool:
	# Offered only when ill.
	var well: Variant = _world(4400)
	var salts_well: int = _give(well, REMEDY_FLUIDS)
	if salts_well < 0:
		return false
	if SimNeeds.can_use(well, well.player, salts_well):
		push_error("ILLNESS: a healthy survivor was offered rehydration salts")
		return false
	if SimNeeds.use_item(well, well.player, salts_well):
		push_error("ILLNESS: a healthy survivor drank the salts anyway -- can_use and the intake disagree")
		return false

	# `fluids` halves what is left.
	var ill: Variant = _world(4401)
	SimNeeds._fall_ill(ill, ill.player)
	if not SimNeeds.is_ill(ill, ill.player):
		push_error("ILLNESS: the fixture did not make anyone ill, so this lane has nothing to judge")
		return false
	var before: int = int(SimNeeds.of(ill, ill.player).get("illUntilTick", -1)) - int(ill.tick)
	var salts: int = _give(ill, REMEDY_FLUIDS)
	if salts < 0:
		return false
	if not SimNeeds.can_use(ill, ill.player, salts):
		push_error("ILLNESS: an ill survivor was not offered the salts")
		return false
	if not SimNeeds.use_item(ill, ill.player, salts):
		push_error("ILLNESS: an ill survivor could not take the salts")
		return false
	var after: int = int(SimNeeds.of(ill, ill.player).get("illUntilTick", -1)) - int(ill.tick)
	if not SimNeeds.is_ill(ill, ill.player):
		push_error("ILLNESS: rehydration salts ended the bout outright -- that is the remedy's job, not theirs")
		return false
	if after >= before:
		push_error("ILLNESS: after the salts %d ticks were left against %d before -- nothing was shortened" % [after, before])
		return false

	# `remedy` ends it, and says so exactly once.
	var cured: Variant = _world(4402)
	SimNeeds._fall_ill(cured, cured.player)
	var tablets: int = _give(cured, REMEDY_FULL)
	if tablets < 0:
		return false
	if not SimNeeds.use_item(cured, cured.player, tablets):
		push_error("ILLNESS: an ill survivor could not take the tablets")
		return false
	if SimNeeds.is_ill(cured, cured.player):
		push_error("ILLNESS: the tablets left the survivor ill")
		return false
	# `events.publish()` only queues -- handlers and `drained` come at the end of `world.step()` --
	# so the cure's own announcement lands on the first step below, not inside `use_item`. Exactly
	# one is the assertion: the cure says the bout is over, and `_tick_illness` never says it again
	# for a bout that has already been closed out from under it.
	var passed: int = 0
	for _i in 40:
		cured.step()
		for ev in cured.events.drained as Array:
			if ev is Dictionary and String((ev as Dictionary).get("type", "")) == "illness.passed":
				passed += 1
	if passed != 1:
		push_error("ILLNESS: illness.passed fired %d times for one cured bout, not once" % passed)
		return false
	print("  ILLNESS: salts cut %d ticks to %d, tablets ended it, and neither is offered to the well" % [before, after])
	return true


# --- FETCH ------------------------------------------------------------------------------------
#
# The colonist doctor's half. It named `item.bandage.cloth` three times, so a doctor holding a
# sterile dressing and no cloth one reported having no bandage at all. It ranks now, and the true
# negative is the sterile dressing being left behind for the rag.
func _the_colonist_reaches_for_the_best_dressing() -> bool:
	var w: Variant = _world(4500)
	var rag: int = _give(w, DRESSING_DIRTY)
	var gauze: int = _give(w, DRESSING_STERILE)
	if rag < 0 or gauze < 0:
		return false
	if not SimJobs._fetch_bandage(w, w.player):
		push_error("FETCH: a doctor carrying two dressings could not produce one")
		return false
	if w.components.has_component(gauze, "itemBase"):
		push_error("FETCH: the sterile dressing is still in the pack -- the rag was spent instead, so the fetch is not ranking")
		return false
	if not w.components.has_component(rag, "itemBase"):
		push_error("FETCH: the rag was spent as well as the gauze")
		return false

	# Sterile only: under the old id match this was the failure -- a full pack reading as empty.
	var sterile_only: Variant = _world(4501)
	if _give(sterile_only, DRESSING_STERILE) < 0:
		return false
	if not SimJobs._fetch_bandage(sterile_only, sterile_only.player):
		push_error("FETCH: a doctor carrying only sterile dressings reported having no bandage")
		return false

	# And the negative: an empty pack still refuses.
	var empty: Variant = _world(4502)
	if SimJobs._fetch_bandage(empty, empty.player):
		push_error("FETCH: a doctor with an empty pack produced a bandage from nowhere")
		return false
	print("  FETCH: the sterile dressing goes first, a sterile-only pack is not empty, and nothing comes from nothing")
	return true


# --- WRAP -------------------------------------------------------------------------------------
#
# `WOUND_KINDS["sprain"]` carried `closeKind: ""`, so the one injury docs/05 treats with "Rest,
# wrap" was the one injury nothing could treat. The closer matches exactly rather than ranking, so
# the true negative is a suture kit failing to close a sprain.
func _a_sprain_can_finally_be_wrapped() -> bool:
	if String((SimWounds.WOUND_KINDS.get("sprain", {}) as Dictionary).get("closeKind", "")) != "wrap":
		push_error("WRAP: a sprain still closes with nothing")
		return false
	if not SimTreatment.CLOSE_KINDS.has("wrap"):
		push_error("WRAP: `wrap` is a wound's closeKind and not a closer the treatment router accepts")
		return false

	# Laceration band rather than DeepWound: `close` puts a Medicine skill wall in front of a deep
	# wound, and a fixture that tripped over it would be testing the skill floor, not the closer.
	var w: Variant = _world(4600)
	SimWounds.append_wound(w, w.player, "sprain", "leg_left", -1, 0.0, "sprain", SimWounds.Severity.Laceration)
	w.step()
	if _give(w, WRAP) < 0:
		return false
	if not _close_offered(w, "leg_left"):
		push_error("WRAP: a sprained leg and an elastic bandage in the pack, and `close` is still not offered")
		return false

	var wrong: Variant = _world(4601)
	SimWounds.append_wound(wrong, wrong.player, "sprain", "leg_left", -1, 0.0, "sprain", SimWounds.Severity.Laceration)
	wrong.step()
	if _give(wrong, SUTURE) < 0:
		return false
	if _close_offered(wrong, "leg_left"):
		push_error("WRAP: a suture kit closed a sprain -- closers are supposed to match exactly, never rank")
		return false
	print("  WRAP: a sprain closes with a wrap and refuses a suture")
	return true


func _close_offered(w: Variant, part: String) -> bool:
	for opt_v in SimTreatment.options_for(w, w.player, w.player, part) as Array:
		var opt: Dictionary = opt_v as Dictionary
		if String(opt.get("verb", "")) == "close":
			return bool(opt.get("ok", false))
	return false
