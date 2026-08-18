extends SceneTree
# Hands that stop the bleeding: pressure, bandaging, and the command path to the five
# infection responses.
#
# Guards Slice 2 Part B. Part A gave a wound a bleed clock that could kill and gave the
# player nothing to do about it; the five infection verbs in infection.gd had the mirror
# problem -- written, window-guarded, correct, and reachable by no command, key or button.
#
# What this gate is really holding down:
#
#  1. **Pressure is worth nothing until it is finished.** Suppressing a bleed while a hand is
#     on it and clotting it for good are different outcomes, and the difference is the whole
#     decision the verb exists to pose. `_a_hold_broken_early_buys_nothing` is the assertion
#     that fails if a partial hold ever starts banking progress.
#
#  2. **Assert the effect, never the mechanism** (docs/30-decisions.md:513-524, and
#     check_m2_wounds.gd's header for the long version). Every claim here is measured on
#     blood actually lost, ground actually covered, or stack counts actually spent -- never
#     on a component field being the value the code just wrote into it.
#
#  3. **The infection verbs are routed, not reimplemented.** `_the_five_verbs_answer_in_their_own_words`
#     asserts the refusal reasons come back verbatim from SimInfection. If a window check
#     ever gets copied into treatment.gd, the two will drift and this is what catches it.
#
# Every assertion carries a true negative beside its positive. A gate that cannot fail is
# worse than no gate.

const World = preload("res://sim/world.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const SimTreatment = preload("res://sim/modules/treatment.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const SimCondition = preload("res://sim/condition.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")

# torso max is 40, so 20 damage is half of it -- comfortably inside DeepWound's >= 0.40 band
# and nowhere near the 0.15 Scratch boundary, so this stays a deep wound if the bands move a
# little. A DeepWound never clots on its own (CLOT_TICKS[DeepWound] == 0), which is exactly
# the wound treatment has to answer.
const DEEP_DAMAGE: float = 20.0
const PART: String = "torso"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _pressure_suppresses_the_bleed_it_is_holding() and ok
	ok = _a_hold_broken_early_buys_nothing() and ok
	ok = _a_completed_hold_clots_the_wound_for_good() and ok
	ok = _a_bandage_survives_the_interrupt_a_hold_does_not() and ok
	ok = _bandaging_spends_exactly_one_dressing() and ok
	ok = _the_best_tier_carried_is_the_one_that_gets_used() and ok
	ok = _both_interrupts_break_a_channel() and ok
	ok = _treatment_pins_both_parties() and ok
	ok = _a_patient_moved_out_of_reach_loses_the_dressing() and ok
	ok = _a_channel_refuses_what_it_cannot_do() and ok
	ok = _the_five_verbs_answer_in_their_own_words() and ok
	ok = _one_key_picks_the_wound_and_the_verb() and ok
	ok = _a_survivor_who_is_not_the_player_presses_on_it_themselves() and ok
	ok = _a_held_survivor_may_press_on_their_own_wound() and ok
	ok = _the_context_key_picks_the_one_verb_a_hold_allows() and ok
	ok = _the_view_says_the_dressing_as_a_word() and ok
	ok = _the_hud_speaks_only_when_there_is_blood() and ok
	ok = _deterministic_replay() and ok
	if ok:
		print("M2_TREATMENT_OK pressure is a commitment, a bandage is durable, the infection verbs are reachable")
		quit(0)
	else:
		push_error("M2_TREATMENT_FAIL")
		quit(1)


# --- fixture ----------------------------------------------------------------------------

# Same bare-world shape check_m2_wounds.gd uses, and for the same reason: no
# SimBoot.attach_kernel, so SimBoot._KERNEL_WORLD's single-world constraint stays out of a
# gate that builds a fresh world per assertion.
func _world(seed_val: int = 4242) -> Variant:
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
	return w


# A second survivor beside the player, for the assertions about treating someone else.
func _bystander(w: Variant, x: float, y: float) -> int:
	var e: int = int(w.entities.spawn())
	w.components.set_component(e, "position", {"x": x, "y": y})
	w.components.set_component(e, "velocity", {"dx": 0.0, "dy": 0.0})
	SimHealth.make_survivor_body(w, e)
	return e


# A hold, in the shape SimShambler._start_grab actually writes -- all three keys, `sources` a
# plain Array. The older fixtures here left `heldTicks` out, which was harmless only for as long
# as nothing read it; shambler.struggle-intake ages that field every tick, so a fixture missing it
# is a fixture that would crash the moment this gate stood a real hold up beside the treatment.
func _hold(w: Variant, victim: int, sources: Array = []) -> void:
	w.components.set_component(victim, "grabbed", {"sources": sources.duplicate(), "struggleTicks": 0, "heldTicks": 0})


func _deep_wound(w: Variant, entity: int, part: String = PART) -> Dictionary:
	return SimWounds.append_wound(w, entity, "cut", part, -1, DEEP_DAMAGE)


func _give(w: Variant, actor: int, base_id: String, count: int = 3) -> int:
	var item: int = SimItems.spawn_item(w, base_id, {"tier": "scavenged", "count": count})
	if not SimInventory.stow(w, actor, item):
		push_error("could not stow %s" % base_id)
	return item


func _blood(w: Variant, entity: int) -> float:
	var inj: Variant = w.components.get_component(entity, "injuries")
	if not (inj is Dictionary):
		return 0.0
	return float((inj as Dictionary).get("bloodLoss", 0.0))


func _wounds(w: Variant, entity: int) -> Array:
	var inj: Variant = w.components.get_component(entity, "injuries")
	if not (inj is Dictionary):
		return []
	return (inj as Dictionary).get("wounds", []) as Array


func _run_ticks(w: Variant, ticks: int) -> void:
	for _i in ticks:
		w.step()


func _stack_count(w: Variant, item: int) -> int:
	var s: Variant = w.components.get_component(item, "stack")
	if not (s is Dictionary):
		return 1
	return int((s as Dictionary).get("count", 1))


# --- assertions ---------------------------------------------------------------------------

# Positive: with a hand on the wound, 200 ticks cost no blood at all. Negative: the identical
# world without the hold loses blood over the same span. Measured on bloodLoss, not on
# whether the component says "pressure" -- the effect, not the mechanism.
func _pressure_suppresses_the_bleed_it_is_holding() -> bool:
	var held: Variant = _world()
	_deep_wound(held, held.player)
	var res: Dictionary = SimTreatment.begin(held, held.player, held.player, PART, "pressure")
	if not bool(res.get("ok", false)):
		push_error("could not begin pressure on a fresh deep wound: %s" % str(res))
		return false
	_run_ticks(held, 200)
	var with_hold: float = _blood(held, held.player)

	var free: Variant = _world()
	_deep_wound(free, free.player)
	_run_ticks(free, 200)
	var without: float = _blood(free, free.player)

	if with_hold > 0.0:
		push_error("a held wound still bled: %.4f over 200 ticks" % with_hold)
		return false
	if without <= 0.0:
		push_error("the unheld control lost no blood in 200 ticks, so the positive proves nothing")
		return false
	print("PRESSURE SUPPRESSES OK held=%.4f unheld=%.4f over 200 ticks" % [with_hold, without])
	return true


# The decision the verb exists to pose. A hold released one tick before it completes must be
# worth exactly nothing: the wound bleeds again immediately and no progress is banked.
func _a_hold_broken_early_buys_nothing() -> bool:
	var w: Variant = _world()
	_deep_wound(w, w.player)
	var full: int = int(SimWounds.PRESSURE_TICKS[SimWounds.Severity.DeepWound])
	SimTreatment.begin(w, w.player, w.player, PART, "pressure")
	_run_ticks(w, full - 1)
	if not w.components.has_component(w.player, "treatment"):
		push_error("the hold ended early: %d of %d ticks" % [full - 1, full])
		return false
	SimTreatment.cancel(w, w.player)

	var before: float = _blood(w, w.player)
	_run_ticks(w, 200)
	var after: float = _blood(w, w.player)
	var wound: Dictionary = _wounds(w, w.player)[0] as Dictionary
	if not bool(wound.get("bleeding", false)):
		push_error("a hold released at %d/%d ticks clotted the wound anyway" % [full - 1, full])
		return false
	if after <= before:
		push_error("the wound stopped bleeding after an aborted hold: %.4f -> %.4f" % [before, after])
		return false
	print("ABORTED HOLD OK released at %d/%d, still bleeding, %.4f -> %.4f over 200 more ticks" % [full - 1, full, before, after])
	return true


# The positive half of the pair above: carried all the way, the same hold clots the wound and
# the clot outlives the channel. Blood loss is read well after the channel is gone.
func _a_completed_hold_clots_the_wound_for_good() -> bool:
	var w: Variant = _world()
	_deep_wound(w, w.player)
	var full: int = int(SimWounds.PRESSURE_TICKS[SimWounds.Severity.DeepWound])
	SimTreatment.begin(w, w.player, w.player, PART, "pressure")
	_run_ticks(w, full)
	if w.components.has_component(w.player, "treatment"):
		push_error("the channel was still running after its full %d ticks" % full)
		return false
	if w.components.has_component(w.player, "treated"):
		push_error("the patient is still marked treated after the channel completed")
		return false

	var settled: float = _blood(w, w.player)
	_run_ticks(w, 400)
	var later: float = _blood(w, w.player)
	var wound: Dictionary = _wounds(w, w.player)[0] as Dictionary
	if bool(wound.get("bleeding", true)):
		push_error("a completed %d-tick hold left the wound bleeding" % full)
		return false
	if later != settled:
		push_error("a clotted wound kept bleeding: %.4f -> %.4f over 400 ticks" % [settled, later])
		return false
	# Pressure costs no supply, so it must leave no dressing behind either.
	if String(wound.get("bandage", "x")) != "none":
		push_error("pressure invented a dressing: bandage='%s'" % wound.get("bandage", ""))
		return false
	print("COMPLETED HOLD OK clotted at %d ticks, %.4f then %.4f 400 ticks later, bandage=none" % [full, settled, later])
	return true


# The distinction between the two verbs, stated as an experiment: the same stagger, at the
# same point, ruins the hold and does not touch the finished dressing.
func _a_bandage_survives_the_interrupt_a_hold_does_not() -> bool:
	var dressed: Variant = _world()
	_deep_wound(dressed, dressed.player)
	_give(dressed, dressed.player, "item.bandage.cloth")
	var res: Dictionary = SimTreatment.begin(dressed, dressed.player, dressed.player, PART, "bandage")
	if not bool(res.get("ok", false)):
		push_error("could not begin bandaging with a cloth bandage carried: %s" % str(res))
		return false
	_run_ticks(dressed, int(SimWounds.BANDAGE_TICKS[SimWounds.Severity.DeepWound]))
	dressed.events.publish({"type": "entity.staggered", "entity": dressed.player})
	var after_stagger: float = _blood(dressed, dressed.player)
	_run_ticks(dressed, 300)
	var bandaged_wound: Dictionary = _wounds(dressed, dressed.player)[0] as Dictionary
	if bool(bandaged_wound.get("bleeding", true)):
		push_error("a completed dressing came off when the survivor was staggered")
		return false
	if _blood(dressed, dressed.player) != after_stagger:
		push_error("a dressed wound bled after a stagger: %.4f -> %.4f" % [after_stagger, _blood(dressed, dressed.player)])
		return false

	var held: Variant = _world()
	_deep_wound(held, held.player)
	SimTreatment.begin(held, held.player, held.player, PART, "pressure")
	# Two ticks short, not one. events.publish() only queues; the handler runs at the END of
	# the next step, by which point treatment.channel has already ticked. A stagger arriving
	# on the very tick a hold completes is genuinely too late to stop it, which is correct
	# behaviour and not what this assertion is about.
	_run_ticks(held, int(SimWounds.PRESSURE_TICKS[SimWounds.Severity.DeepWound]) - 2)
	held.events.publish({"type": "entity.staggered", "entity": held.player})
	held.step()
	if held.components.has_component(held.player, "treatment"):
		push_error("a stagger did not interrupt a pressure hold")
		return false
	var held_before: float = _blood(held, held.player)
	_run_ticks(held, 200)
	if _blood(held, held.player) <= held_before:
		push_error("the interrupted hold's wound did not resume bleeding")
		return false
	print("DURABILITY OK dressing survived a stagger, hold did not (%.4f -> %.4f after)" % [held_before, _blood(held, held.player)])
	return true


# Spent at completion, the way fortify._place_scrap re-validates and consumes inside
# _complete: an interrupted channel costs nothing, and a finished one costs exactly one.
func _bandaging_spends_exactly_one_dressing() -> bool:
	var w: Variant = _world()
	_deep_wound(w, w.player)
	var stack: int = _give(w, w.player, "item.bandage.cloth", 3)
	var before: int = _stack_count(w, stack)

	# Interrupted first: this must cost nothing at all.
	SimTreatment.begin(w, w.player, w.player, PART, "bandage")
	_run_ticks(w, 50)
	w.events.publish({"type": "entity.staggered", "entity": w.player})
	w.step()
	var after_abort: int = _stack_count(w, stack)
	if after_abort != before:
		push_error("an interrupted bandaging spent a dressing: %d -> %d" % [before, after_abort])
		return false

	SimTreatment.begin(w, w.player, w.player, PART, "bandage")
	_run_ticks(w, int(SimWounds.BANDAGE_TICKS[SimWounds.Severity.DeepWound]))
	var after: int = _stack_count(w, stack)
	if after != before - 1:
		push_error("a completed bandaging spent %d dressings, expected 1 (%d -> %d)" % [before - after, before, after])
		return false

	# And with nothing carried, the verb refuses in the sim's own words rather than
	# bandaging for free.
	var empty: Variant = _world()
	_deep_wound(empty, empty.player)
	var refused: Dictionary = SimTreatment.begin(empty, empty.player, empty.player, PART, "bandage")
	if bool(refused.get("ok", false)) or String(refused.get("reason", "")) != "no-bandage":
		push_error("bandaging with nothing carried returned %s" % str(refused))
		return false
	print("SUPPLY OK interrupted cost 0, completed cost 1 (%d -> %d), empty-handed refused '%s'" % [before, after, refused.get("reason", "")])
	return true


# Tier comes from content, and the actor reaches for the best thing they have. The pair here
# is the same wound treated by an actor carrying two tiers and one carrying only the worst.
func _the_best_tier_carried_is_the_one_that_gets_used() -> bool:
	var rich: Variant = _world()
	_deep_wound(rich, rich.player)
	_give(rich, rich.player, "item.rag.dirty", 2)
	_give(rich, rich.player, "item.medkit.field", 1)
	SimTreatment.begin(rich, rich.player, rich.player, PART, "bandage")
	_run_ticks(rich, int(SimWounds.BANDAGE_TICKS[SimWounds.Severity.DeepWound]))
	var best: String = String((_wounds(rich, rich.player)[0] as Dictionary).get("bandage", ""))

	var poor: Variant = _world()
	_deep_wound(poor, poor.player)
	_give(poor, poor.player, "item.rag.dirty", 2)
	SimTreatment.begin(poor, poor.player, poor.player, PART, "bandage")
	_run_ticks(poor, int(SimWounds.BANDAGE_TICKS[SimWounds.Severity.DeepWound]))
	var worst: String = String((_wounds(poor, poor.player)[0] as Dictionary).get("bandage", ""))

	if best != "sterile":
		push_error("carrying a medkit and a rag, the dressing came out '%s', expected sterile" % best)
		return false
	if worst != "dirty":
		push_error("carrying only a rag, the dressing came out '%s', expected dirty" % worst)
		return false
	print("TIER OK medkit+rag -> %s, rag only -> %s" % [best, worst])
	return true


# The two subscriptions no longer say the same thing, and this is where that is held down.
#
# A stagger still cancels everything (R3) -- being knocked off your feet takes your own hand off
# your own arm. A grab cancels everything it touches *except* the victim's own self-pressure (R2),
# because a second set of hands closing on somebody does not physically peel their palm off their
# own wound. So the grab half needs both signs to mean anything: a dressing somebody else was
# holding on the newly grabbed patient comes apart, and the patient's own press does not.
func _both_interrupts_break_a_channel() -> bool:
	# R3, unchanged: a stagger cancels a self-pressure.
	var staggered: Variant = _world()
	_deep_wound(staggered, staggered.player)
	SimTreatment.begin(staggered, staggered.player, staggered.player, PART, "pressure")
	_run_ticks(staggered, 20)
	staggered.events.publish({"type": "entity.staggered", "entity": staggered.player})
	staggered.step()
	if staggered.components.has_component(staggered.player, "treatment"):
		push_error("entity.staggered did not interrupt the channel")
		return false
	if staggered.components.has_component(staggered.player, "treated"):
		push_error("entity.staggered left the patient marked treated")
		return false

	# R2, the interrupt half: a free treater's dressing on a bystander who has just been grabbed.
	# This is the case the subscription was written for and it must keep working.
	var other: Variant = _world()
	var patient: int = _bystander(other, 9.0, 16.5)
	_deep_wound(other, patient)
	_give(other, other.player, "item.bandage.cloth")
	var dressing: Dictionary = SimTreatment.begin(other, other.player, patient, PART, "bandage")
	if not bool(dressing.get("ok", false)):
		push_error("could not begin bandaging a bystander in reach: %s" % str(dressing))
		return false
	_run_ticks(other, 20)
	_hold(other, patient)
	other.events.publish({"type": "grab.started", "victim": patient, "source": -1})
	other.step()
	if other.components.has_component(other.player, "treatment"):
		push_error("a bystander being grabbed did not cost the treater the dressing")
		return false
	if other.components.has_component(patient, "treated"):
		push_error("the grabbed patient was left marked treated")
		return false

	# R2, the exemption half: the victim's own press survives the hand closing on them, and goes
	# on to complete. Without this sign the exemption would be a claim rather than a measurement.
	var own: Variant = _world()
	_deep_wound(own, own.player)
	SimTreatment.begin(own, own.player, own.player, PART, "pressure")
	_run_ticks(own, 20)
	_hold(own, own.player)
	own.events.publish({"type": "grab.started", "victim": own.player, "source": -1})
	own.step()
	if not own.components.has_component(own.player, "treatment"):
		push_error("a grab cancelled the victim's own self-pressure")
		return false
	_run_ticks(own, int(SimWounds.PRESSURE_TICKS[SimWounds.Severity.DeepWound]))
	if bool((_wounds(own, own.player)[0] as Dictionary).get("bleeding", true)):
		push_error("a self-press that survived the grab never clotted the wound")
		return false

	var quiet: Variant = _world()
	_deep_wound(quiet, quiet.player)
	SimTreatment.begin(quiet, quiet.player, quiet.player, PART, "pressure")
	_run_ticks(quiet, 20)
	quiet.events.publish({"type": "noise.emitted", "x": 8.5, "y": 16.5, "magnitude": 40.0, "source": -1})
	quiet.step()
	if not quiet.components.has_component(quiet.player, "treatment"):
		push_error("an unrelated event cancelled the channel, so the interrupts above prove nothing")
		return false
	print("INTERRUPTS OK stagger breaks it, a grab breaks somebody else's dressing but not the victim's own press, an unrelated event does neither")
	return true


# Treating someone occupies both. Measured as ground covered under a real move command for
# the treater, and as a velocity that goes nowhere for the patient -- the patient has no
# command intake of its own, so its own velocity is the honest probe.
func _treatment_pins_both_parties() -> bool:
	var w: Variant = _world()
	var patient: int = _bystander(w, 9.0, 16.5)
	_deep_wound(w, patient)
	_give(w, w.player, "item.bandage.cloth")
	var res: Dictionary = SimTreatment.begin(w, w.player, patient, PART, "bandage")
	if not bool(res.get("ok", false)):
		push_error("could not begin treating a bystander in reach: %s" % str(res))
		return false

	var start_x: float = float((w.components.get_component(w.player, "position") as Dictionary)["x"])
	var p_start: float = float((w.components.get_component(patient, "position") as Dictionary)["x"])
	for _i in 60:
		w.commands.push({"type": "move", "dx": 1.0, "dy": 0.0})
		(w.components.get_component(patient, "velocity") as Dictionary)["dx"] = 2.0
		w.step()
	var moved: float = float((w.components.get_component(w.player, "position") as Dictionary)["x"]) - start_x
	var patient_moved: float = float((w.components.get_component(patient, "position") as Dictionary)["x"]) - p_start

	# The negative: a third survivor, with the same velocity written every tick and no
	# treatment on them, actually travels. Without this, a broken movement system would
	# satisfy both assertions above.
	var free: int = _bystander(w, 20.0, 16.5)
	var f_start: float = float((w.components.get_component(free, "position") as Dictionary)["x"])
	for _j in 60:
		(w.components.get_component(free, "velocity") as Dictionary)["dx"] = 2.0
		w.step()
	var free_moved: float = float((w.components.get_component(free, "position") as Dictionary)["x"]) - f_start

	if absf(moved) > 0.0001:
		push_error("the treater covered %.4f m while channelling" % moved)
		return false
	if absf(patient_moved) > 0.0001:
		push_error("the patient covered %.4f m while being treated" % patient_moved)
		return false
	if free_moved <= 0.5:
		push_error("the untreated control only covered %.4f m, so the pins above prove nothing" % free_moved)
		return false
	print("PIN OK treater %.4f m, patient %.4f m, untreated control %.4f m over 60 ticks" % [moved, patient_moved, free_moved])
	return true


# fortify.gd checks reach once at _start and lets you walk away from a board that finishes
# anyway. Treatment re-checks every tick, so a patient dragged out of reach loses the
# dressing rather than receiving it at a distance.
func _a_patient_moved_out_of_reach_loses_the_dressing() -> bool:
	var w: Variant = _world()
	var patient: int = _bystander(w, 9.0, 16.5)
	_deep_wound(w, patient)
	_give(w, w.player, "item.bandage.cloth")
	SimTreatment.begin(w, w.player, patient, PART, "bandage")
	_run_ticks(w, 40)
	# Something else moves the patient -- a drag, a carry, a scenario. The pin only stops the
	# patient's own velocity, not the world's.
	(w.components.get_component(patient, "position") as Dictionary)["x"] = 20.0
	w.step()
	if w.components.has_component(w.player, "treatment"):
		push_error("the channel survived the patient being moved 11 m away")
		return false
	if bool((_wounds(w, patient)[0] as Dictionary).get("bandage", "none") != "none"):
		push_error("an aborted channel dressed the wound anyway")
		return false

	var near: Variant = _world()
	var stays: int = _bystander(near, 9.0, 16.5)
	_deep_wound(near, stays)
	_give(near, near.player, "item.bandage.cloth")
	SimTreatment.begin(near, near.player, stays, PART, "bandage")
	_run_ticks(near, int(SimWounds.BANDAGE_TICKS[SimWounds.Severity.DeepWound]))
	if String((_wounds(near, stays)[0] as Dictionary).get("bandage", "none")) == "none":
		push_error("a patient who stayed in reach was never dressed, so the abort above proves nothing")
		return false
	print("REACH OK dragged patient aborted the channel, a patient who stayed was dressed")
	return true


# Every refusal reason, each with the case that grants it. The reasons are the vocabulary the
# panel shows, so a silent failure here becomes a button that does nothing.
func _a_channel_refuses_what_it_cannot_do() -> bool:
	var cases: Array = [
		{"why": "unknown-verb", "verb": "heal", "setup": ""},
		{"why": "not-bleeding", "verb": "pressure", "setup": "unwounded"},
		# R1's two halves as refusals. A held survivor may press on their own wound and nothing
		# else: the dressing needs both hands and somewhere to kneel, and anything aimed at another
		# body is out of the question with a mouth on your arm. The granted case is AID-HELD.
		{"why": "cannot-channel", "verb": "bandage", "setup": "grabbed"},
		{"why": "cannot-channel", "verb": "pressure", "setup": "grabbed-other"},
		{"why": "cannot-channel", "verb": "pressure", "setup": "sprinting"},
		{"why": "out-of-reach", "verb": "pressure", "setup": "distant"},
		{"why": "busy", "verb": "pressure", "setup": "busy"},
	]
	for entry in cases:
		var c: Dictionary = entry as Dictionary
		var w: Variant = _world()
		var patient: int = w.player
		match String(c["setup"]):
			"unwounded":
				pass
			"grabbed":
				_deep_wound(w, w.player)
				_hold(w, w.player)
			"grabbed-other":
				patient = _bystander(w, 9.0, 16.5)
				_deep_wound(w, patient)
				_hold(w, w.player)
			"sprinting":
				_deep_wound(w, w.player)
				w.components.set_component(w.player, "posture", {"current": 4, "target": 4, "ticks_left": 0})
			"distant":
				patient = _bystander(w, 24.0, 16.5)
				_deep_wound(w, patient)
			"busy":
				_deep_wound(w, w.player)
				SimTreatment.begin(w, w.player, w.player, PART, "pressure")
			_:
				_deep_wound(w, w.player)
		var res: Dictionary = SimTreatment.begin(w, w.player, patient, PART, String(c["verb"]))
		if bool(res.get("ok", false)) or String(res.get("reason", "")) != String(c["why"]):
			push_error("setup '%s' + verb '%s' returned %s, expected reason '%s'" % [c["setup"], c["verb"], str(res), c["why"]])
			return false

	# The negative for the whole table: an ordinary walking survivor with a fresh wound is
	# granted. Without it, a begin() that refused everything would pass all six rows.
	var fine: Variant = _world()
	_deep_wound(fine, fine.player)
	var granted: Dictionary = SimTreatment.begin(fine, fine.player, fine.player, PART, "pressure")
	if not bool(granted.get("ok", false)):
		push_error("a walking survivor with an open wound was refused: %s" % str(granted))
		return false
	print("REFUSALS OK %d reasons each granted by its own case, and the ordinary case still succeeds" % cases.size())
	return true


# The router asserted as a router. Each verb reaches the SimInfection function that owns it,
# and each refusal string is the one that function produced -- never one this module invented.
# If a window check is ever copied into treatment.gd, these stop agreeing.
func _the_five_verbs_answer_in_their_own_words() -> bool:
	# No exposure at all: the three verbs that need one refuse with SimInfection's word.
	var bare: Variant = _world()
	for verb in ["cauterize", "antibiotics"]:
		var direct: Dictionary = SimInfection.cauterize(bare, bare.player, PART) if verb == "cauterize" else SimInfection.use_antibiotics(bare, bare.player)
		var routed: Dictionary = SimTreatment._invoke_infection(bare, bare.player, PART, String(verb))
		if String(routed.get("reason", "")) != String(direct.get("reason", "")):
			push_error("'%s' routed reason '%s' != SimInfection's own '%s'" % [verb, routed.get("reason", ""), direct.get("reason", "")])
			return false
	var not_limb: Dictionary = SimTreatment._invoke_infection(bare, bare.player, "torso", "amputate")
	if String(not_limb.get("reason", "")) != "not-limb":
		push_error("amputating a torso returned %s, expected SimInfection's 'not-limb'" % str(not_limb))
		return false

	# The two that always succeed, and the events that prove they were reached rather than
	# merely returning ok.
	var live: Variant = _world()
	var seen: Array[String] = []
	live.events.subscribe({"id": "gate.watch", "type": "quarantined", "handler": func(_e: Dictionary) -> void:
		seen.append("quarantined")
	})
	live.events.subscribe({"id": "gate.watch2", "type": "survivor.putDown", "handler": func(_e: Dictionary) -> void:
		seen.append("putDown")
	})
	SimTreatment.respond(live, live.player, live.player, PART, "quarantine")
	SimTreatment.respond(live, live.player, live.player, PART, "put_down")
	live.step()
	if not seen.has("quarantined") or not seen.has("putDown"):
		push_error("quarantine/put_down routed but published nothing: %s" % str(seen))
		return false

	# With a real exposure, cauterize is granted -- the positive that keeps the refusals above
	# from being satisfied by a router that always fails.
	var exposed: Variant = _world()
	exposed.components.set_component(exposed.player, "zombieInfection", {"exposures": [
		{"source": -1, "bodyPart": PART, "exposedAtTick": int(exposed.tick), "transmitted": true, "stage": SimInfection.Stage.Latent, "stageEnteredAtTick": int(exposed.tick), "cauterized": false, "amputated": false},
	]})
	var burned: Dictionary = SimTreatment._invoke_infection(exposed, exposed.player, PART, "cauterize")
	if not bool(burned.get("ok", false)):
		push_error("cauterizing a fresh exposure was refused: %s" % str(burned))
		return false

	# And the surgical verbs run as channels rather than instants, per docs/06.
	var surgery: Variant = _world()
	var began: Dictionary = SimTreatment.respond(surgery, surgery.player, surgery.player, "arm_left", "amputate")
	if not bool(began.get("ok", false)) or int(began.get("ticks", 0)) != int(SimTreatment.SURGERY_TICKS["amputate"]):
		push_error("amputation did not open a %d-tick channel: %s" % [SimTreatment.SURGERY_TICKS["amputate"], str(began)])
		return false
	if not surgery.components.has_component(surgery.player, "treatment"):
		push_error("amputation returned ok but opened no channel")
		return false
	print("ROUTER OK five verbs reachable, reasons are SimInfection's own, surgery is a %d-tick channel" % SimTreatment.SURGERY_TICKS["amputate"])
	return true


# The screen's half of the contract. The tier is a word, and it is the word the sim wrote --
# check_ban_health_bar.gd holds down that it can never become a number.
func _the_view_says_the_dressing_as_a_word() -> bool:
	var w: Variant = _world()
	_deep_wound(w, w.player, "arm_left")
	_give(w, w.player, "item.bandage.cloth")
	var before: Dictionary = {}
	for entry in SimCondition.view(w, w.player)["parts"] as Array:
		before[String((entry as Dictionary)["part"])] = entry
	if String((before["arm_left"] as Dictionary).get("bandage", "x")) != "none":
		push_error("an undressed arm reported bandage='%s'" % (before["arm_left"] as Dictionary).get("bandage", ""))
		return false

	SimTreatment.begin(w, w.player, w.player, "arm_left", "bandage")
	_run_ticks(w, int(SimWounds.BANDAGE_TICKS[SimWounds.Severity.DeepWound]))
	var after: Dictionary = {}
	for entry2 in SimCondition.view(w, w.player)["parts"] as Array:
		after[String((entry2 as Dictionary)["part"])] = entry2
	var dressed: String = String((after["arm_left"] as Dictionary).get("bandage", ""))
	var untouched: String = String((after["arm_right"] as Dictionary).get("bandage", ""))
	if dressed != "cloth":
		push_error("a cloth-bandaged arm reported bandage='%s'" % dressed)
		return false
	if untouched != "none":
		push_error("the other arm, which nobody treated, reported bandage='%s'" % untouched)
		return false
	if bool((after["arm_left"] as Dictionary).get("bleeding", true)):
		push_error("a dressed arm still reports bleeding")
		return false
	print("VIEW OK arm_left none -> %s, arm_right stayed %s" % [dressed, untouched])
	return true


# The context verb, asserted through the real command path -- the same route the T key takes,
# so a broken intake fails here rather than only in play. Three claims: it picks the worst
# wound rather than the first, it reaches for a bandage when one is carried and its own hands
# when none is, and pressing it again stops what it started.
func _one_key_picks_the_wound_and_the_verb() -> bool:
	var w: Variant = _world()
	# A scratch on the head and a deep wound on the torso. Head is first in PART_ORDER, so a
	# "pick the first bleeding part" implementation would choose it and fail here.
	SimWounds.append_wound(w, w.player, "cut", "head", -1, 2.0)
	_deep_wound(w, w.player)
	_give(w, w.player, "item.bandage.cloth")
	w.commands.push({"type": "treat.context"})
	w.step()
	var t: Variant = w.components.get_component(w.player, "treatment")
	if not (t is Dictionary):
		push_error("treat.context started nothing on a bleeding survivor")
		return false
	if String((t as Dictionary).get("part", "")) != PART:
		push_error("treat.context picked '%s', expected the worse wound on %s" % [(t as Dictionary).get("part", ""), PART])
		return false
	if String((t as Dictionary).get("verb", "")) != "bandage":
		push_error("treat.context chose '%s' while carrying a bandage" % (t as Dictionary).get("verb", ""))
		return false

	# Again, and it stops. One key, two meanings.
	w.commands.push({"type": "treat.context"})
	w.step()
	if w.components.has_component(w.player, "treatment"):
		push_error("a second treat.context did not cancel the channel")
		return false

	# Empty-handed, the same key falls back to bare hands rather than refusing.
	var bare: Variant = _world()
	_deep_wound(bare, bare.player)
	bare.commands.push({"type": "treat.context"})
	bare.step()
	var t2: Variant = bare.components.get_component(bare.player, "treatment")
	if not (t2 is Dictionary) or String((t2 as Dictionary).get("verb", "")) != "pressure":
		push_error("empty-handed, treat.context chose %s" % str(t2))
		return false

	# And the negative: an unhurt survivor pressing it starts nothing at all.
	var well: Variant = _world()
	well.commands.push({"type": "treat.context"})
	well.step()
	if well.components.has_component(well.player, "treatment"):
		push_error("treat.context started a channel on a survivor with no wounds")
		return false
	print("CONTEXT OK worst wound picked, bandage preferred, bare hands as fallback, toggles off, silent when unhurt")
	return true


# A person with an open artery does not wait for a doctor. The NPC Doctor job exists, but it
# has to notice, path across the district and arrive, and a deep wound bleeds out in five
# thousand ticks -- so without this a wound is a death sentence for anyone the player is not
# personally standing beside. It routes through the same `context` the T key uses.
#
# The negative is the player: the player has a key, and a sim that pressed it for them would
# be taking a decision the whole slice exists to pose.
func _a_survivor_who_is_not_the_player_presses_on_it_themselves() -> bool:
	var w: Variant = _world()
	var npc: int = _bystander(w, 20.0, 16.5)
	_deep_wound(w, npc)
	_deep_wound(w, w.player)
	w.step()

	var t: Variant = w.components.get_component(npc, "treatment")
	if not (t is Dictionary):
		push_error("a bleeding survivor with nobody around started no first aid of their own")
		return false
	if String((t as Dictionary).get("verb", "")) != "pressure":
		push_error("an empty-handed survivor chose '%s' rather than their own hands" % (t as Dictionary).get("verb", ""))
		return false
	if w.components.has_component(w.player, "treatment"):
		push_error("the sim started first aid for the player, who has a key for it")
		return false

	# And it actually works: the bleed stops while the hold is on.
	var before: float = _blood(w, npc)
	_run_ticks(w, 200)
	if _blood(w, npc) != before:
		push_error("the autonomous hold suppressed nothing: %.4f -> %.4f" % [before, _blood(w, npc)])
		return false
	# The player, untended, is the control that proves the world was bleeding at all.
	if _blood(w, w.player) <= 0.0:
		push_error("the untended player lost no blood, so the suppression above proves nothing")
		return false
	print("SELF-AID OK npc held its own wound (%.4f lost), untended player lost %.4f" % [_blood(w, npc), _blood(w, w.player)])
	return true


# R1, granted. The whole lever: a survivor with somebody's hands on them may still put their own
# hand on their own wound, run the full 400-tick deep-wound press held throughout, and clot it.
#
# This is the assertion that would have caught the thing it is answering. Before it, a held body
# was refused first aid outright, and the balance harness measured what that cost -- two thirds of
# a held survivor's life spent bleeding with no legal answer, and both wiped seeds wiping by blood
# loss. Measured on blood, never on the component: the claim is that no blood is lost, not that a
# field says "pressure".
#
# Three negatives, because "granted" on its own would also pass if the exemption were a hole:
#   - an identical held survivor who does not press bleeds, so the world was bleeding at all;
#   - a stagger still ends it and the bleed resumes (R3 -- the exemption is not immunity);
#   - the two channels R1 does *not* open, refused while held with the same fixture.
func _a_held_survivor_may_press_on_their_own_wound() -> bool:
	var held: Variant = _world()
	_deep_wound(held, held.player)
	_hold(held, held.player)
	var full: int = int(SimWounds.PRESSURE_TICKS[SimWounds.Severity.DeepWound])
	var granted: Dictionary = SimTreatment.begin(held, held.player, held.player, PART, "pressure")
	if not bool(granted.get("ok", false)) or int(granted.get("ticks", 0)) != full:
		push_error("a held survivor was refused their own hand on their own wound: %s" % str(granted))
		return false
	_run_ticks(held, full)
	if not held.components.has_component(held.player, "grabbed"):
		push_error("the fixture lost the hold partway, so this measured a free survivor")
		return false
	if bool((_wounds(held, held.player)[0] as Dictionary).get("bleeding", true)):
		push_error("a completed held press left the wound bleeding")
		return false
	var settled: float = _blood(held, held.player)
	_run_ticks(held, 200)
	if _blood(held, held.player) > settled:
		push_error("a clotted wound kept bleeding while held: %.4f -> %.4f" % [settled, _blood(held, held.player)])
		return false

	# Negative 1: the same hold, nobody pressing.
	var untended: Variant = _world()
	_deep_wound(untended, untended.player)
	_hold(untended, untended.player)
	_run_ticks(untended, full)
	if _blood(untended, untended.player) <= 0.0:
		push_error("an untended held survivor lost no blood, so the press above proves nothing")
		return false

	# Negative 2: R3. A stagger ends a held press, and the bleed comes straight back.
	var knocked: Variant = _world()
	_deep_wound(knocked, knocked.player)
	_hold(knocked, knocked.player)
	SimTreatment.begin(knocked, knocked.player, knocked.player, PART, "pressure")
	_run_ticks(knocked, 20)
	knocked.events.publish({"type": "entity.staggered", "entity": knocked.player})
	knocked.step()
	if knocked.components.has_component(knocked.player, "treatment"):
		push_error("a stagger did not end a held press")
		return false
	var before: float = _blood(knocked, knocked.player)
	_run_ticks(knocked, 200)
	if _blood(knocked, knocked.player) <= before:
		push_error("the bleed did not resume after a staggered held press: %.4f -> %.4f" % [before, _blood(knocked, knocked.player)])
		return false

	# Negative 3: exactly one channel, not "channels while held". A dressing on your own arm and a
	# hand on somebody else's are both still refused, with the same hold in place.
	var bounded: Variant = _world()
	_deep_wound(bounded, bounded.player)
	_give(bounded, bounded.player, "item.bandage.cloth")
	var neighbour: int = _bystander(bounded, 9.0, 16.5)
	_deep_wound(bounded, neighbour)
	_hold(bounded, bounded.player)
	for refused in [
		{"patient": bounded.player, "verb": "bandage"},
		{"patient": neighbour, "verb": "pressure"},
	]:
		var r: Dictionary = SimTreatment.begin(bounded, bounded.player, int((refused as Dictionary)["patient"]), PART, String((refused as Dictionary)["verb"]))
		if bool(r.get("ok", false)):
			push_error("a held survivor was granted '%s' on %d: %s" % [(refused as Dictionary)["verb"], int((refused as Dictionary)["patient"]), str(r)])
			return false
	print("AID-HELD OK held press granted, %d ticks, clotted and %.4f lost; untended held control lost %.4f; stagger still ends it; bandage and aid-to-others still refused" % [full, _blood(held, held.player), _blood(untended, untended.player)])
	return true


# R7. `context` is the one first-aid decision procedure in this simulation, so what it picks while
# held is the whole of whether aid-while-held is reachable in play rather than only through a
# direct `begin`. A held survivor carrying a dressing must reach for their own hand, because the
# dressing is the thing R1 refuses -- picking it would refuse them every tick forever.
#
# The negative is the same survivor with the same dressing and no hold: they pick the bandage.
# Without that half this would pass on a `context` that had simply forgotten bandages exist.
func _the_context_key_picks_the_one_verb_a_hold_allows() -> bool:
	var w: Variant = _world()
	var npc: int = _bystander(w, 20.0, 16.5)
	SimInventory.make_inventory(w, npc)
	_give(w, npc, "item.bandage.cloth")
	_deep_wound(w, npc)
	_hold(w, npc)
	w.step()
	var t: Variant = w.components.get_component(npc, "treatment")
	if not (t is Dictionary):
		push_error("a held bleeding survivor carrying a dressing started no first aid at all")
		return false
	if String((t as Dictionary).get("verb", "")) != "pressure":
		push_error("a held survivor reached for '%s' rather than their own hand" % (t as Dictionary).get("verb", ""))
		return false

	var free: Variant = _world()
	var walker: int = _bystander(free, 20.0, 16.5)
	SimInventory.make_inventory(free, walker)
	_give(free, walker, "item.bandage.cloth")
	_deep_wound(free, walker)
	free.step()
	var t2: Variant = free.components.get_component(walker, "treatment")
	if not (t2 is Dictionary) or String((t2 as Dictionary).get("verb", "")) != "bandage":
		push_error("the same survivor, free and carrying the same dressing, chose %s -- the held pick above proves nothing" % str(t2))
		return false
	print("HELD-CONTEXT OK held with a cloth dressing -> pressure, free with the same dressing -> bandage")
	return true


# The HUD half of the ban: blood loss reaches the player as a sentence, and only when there
# is something to say. check_hud.gd caps an unhurt survivor at two left-hand lines, so a
# clause that spoke when nothing was wrong would break that gate rather than this one --
# which is why the silent case is asserted here, next to the code that could break it.
func _the_hud_speaks_only_when_there_is_blood() -> bool:
	var quiet: Variant = _world()
	if SimWounds.hud_clause(quiet, quiet.player) != "":
		push_error("an unhurt survivor said '%s'" % SimWounds.hud_clause(quiet, quiet.player))
		return false
	# A wound with no blood lost yet still warrants a warning -- that is the point of it.
	_deep_wound(quiet, quiet.player)
	var fresh: String = SimWounds.hud_clause(quiet, quiet.player)
	if fresh == "":
		push_error("a survivor with an open deep wound said nothing")
		return false

	var digits: RegEx = RegEx.new()
	digits.compile("[0-9]")
	var said: Array[String] = [fresh]
	var w: Variant = _world()
	_deep_wound(w, w.player)
	for target in [30.0, 60.0, 90.0]:
		(w.components.get_component(w.player, "injuries") as Dictionary)["bloodLoss"] = target
		var line: String = SimWounds.hud_clause(w, w.player)
		if line == "":
			push_error("a survivor %.0f%% of the way to bleeding out said nothing" % target)
			return false
		if digits.search(line) != null:
			push_error("the blood-loss clause carried a digit: '%s'" % line)
			return false
		said.append(line)
	# Four distinct bands, not one sentence repeated -- otherwise the clause tells the player
	# nothing as their situation gets worse.
	var seen: Dictionary = {}
	for line2 in said:
		seen[line2] = true
	if seen.size() != said.size():
		push_error("the blood-loss bands repeat themselves: %s" % str(said))
		return false
	print("HUD CLAUSE OK silent when well, %d distinct bands, no digits: %s" % [said.size(), " / ".join(said)])
	return true


# Same seed and same commands, byte-identical. The negative moves one command by a single
# tick, which must produce a different serialisation -- otherwise the comparison is
# measuring nothing.
func _deterministic_replay() -> bool:
	var runs: Array[String] = []
	for offset in [0, 0, 7]:
		var w: Variant = _world(99)
		_deep_wound(w, w.player)
		_give(w, w.player, "item.bandage.cloth")
		for i in 300:
			if i == 10 + int(offset):
				w.commands.push({"type": "treat.begin", "patient": w.player, "part": PART, "verb": "bandage"})
			w.commands.push({"type": "move", "dx": 1.0, "dy": 0.0})
			w.step()
		runs.append(JSON.stringify(w.serialize()))
	if runs[0] != runs[1]:
		push_error("two identical runs serialised differently")
		return false
	if runs[0] == runs[2]:
		push_error("moving the treat command 7 ticks changed nothing, so the comparison proves nothing")
		return false
	print("DETERMINISM OK identical runs match, a 7-tick shift does not")
	return true
