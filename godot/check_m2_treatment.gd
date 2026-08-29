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
#  1. **Pressure is worth nothing *now* until it is finished, and worth something *later* from
#     the first tick.** Suppressing a bleed while a hand is on it and clotting it for good are
#     different outcomes, and the difference is still the whole decision the verb exists to pose:
#     `_a_partial_hold_clots_nothing_and_banks_everything` is what fails if a released hold ever
#     stops the bleeding by itself. What that assertion no longer claims is that the time is
#     *lost* -- treatment.gd's R8 banks it on the wound, on a measurement (docs/30), and the
#     second half of the same assertion is what fails if the bank ever goes missing.
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
const SimClock = preload("res://sim/time/clock.gd")
const SimStances = preload("res://sim/stances.gd")
const ContentLoader = preload("res://platform/content_loader.gd")

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
	ok = _a_partial_hold_clots_nothing_and_banks_everything() and ok
	ok = _a_completed_hold_clots_the_wound_for_good() and ok
	ok = _a_bandage_survives_the_interrupt_a_hold_does_not() and ok
	ok = _bandaging_spends_exactly_one_dressing() and ok
	ok = _the_best_tier_carried_is_the_one_that_gets_used() and ok
	ok = _both_interrupts_break_a_channel() and ok
	ok = _treatment_pins_both_parties() and ok
	ok = _a_patient_moved_out_of_reach_loses_the_dressing() and ok
	ok = _a_channel_refuses_what_it_cannot_do() and ok
	ok = _the_five_verbs_answer_in_their_own_words() and ok
	ok = _a_put_down_actually_puts_them_down() and ok
	ok = _one_key_picks_the_wound_and_the_verb() and ok
	ok = _a_survivor_who_is_not_the_player_presses_on_it_themselves() and ok
	ok = _a_held_survivor_may_press_on_their_own_wound() and ok
	ok = _the_context_key_picks_the_one_verb_a_hold_allows() and ok
	ok = _the_view_says_the_dressing_as_a_word() and ok
	ok = _the_hud_speaks_only_when_there_is_blood() and ok
	ok = _cleaning_is_the_missing_sepsis_factor() and ok
	ok = _the_supply_carried_is_the_one_that_gets_used() and ok
	ok = _closing_speeds_the_knitting_and_holds_it_shut() and ok
	ok = _you_close_what_you_have_already_stopped() and ok
	ok = _dressing_a_dirty_wound_is_allowed_and_still_costs() and ok
	ok = _the_new_verbs_spend_exactly_one_supply() and ok
	ok = _a_hold_still_allows_exactly_one_channel() and ok
	ok = _one_key_walks_the_whole_ladder() and ok
	ok = _a_survivor_who_is_not_the_player_cleans_their_own_wound() and ok
	ok = _a_reopened_wound_is_dirty_again() and ok
	ok = _the_new_supplies_are_findable() and ok
	ok = _deterministic_replay() and ok
	if ok:
		print("M2_TREATMENT_OK pressure is a commitment, a bandage is durable, the ladder cleans and closes, the infection verbs are reachable")
		quit(0)
	else:
		push_error("M2_TREATMENT_FAIL")
		quit(1)


# --- fixture ----------------------------------------------------------------------------

# Same bare-world shape check_m2_wounds.gd uses, and for the same reason: this gate needs no
# kernel. (It used to also be dodging SimBoot's static attention-world; that is fixed -- the
# handlers capture their own world now -- and check_m2_contact.gd's fixture note has the detail.)
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



# docs/06 response #5 sells exactly one product -- "certainty, immediately, cheaply" -- and for
# as long as `put_down` existed it delivered none of it. It published `survivor.putDown` and
# `entity.killed`, returned `{ok: true}`, and **nothing reaps on that bus**: `finish_death` is
# called by health.gd's own reaper off its local `killed` list, by wounds.gd's bled-out reaper,
# and by needs.gd -- never by a subscription. The survivor walked away from their own mercy kill,
# still bleeding and still on course to turn. The assertion that used to stand here watched the
# two events go out and stopped there, which is CLAUDE.md's dead-socket pattern exactly: the
# helper was right, and no consumer read it.
#
# Three ways for this to fail, so it cannot pass by accident:
#   positive   a put-down body is a corpse on the next step
#   negative   the same transmitted body reaped by the ordinary path **does** turn, so what
#              suppresses the turn is the put-down and not a blanket "nothing turns any more"
#   control    a body nobody put down is untouched -- alive, no corpse
func _a_put_down_actually_puts_them_down() -> bool:
	var w: Variant = _world()
	var them: int = _bystander(w, 9.5, 16.5)
	w.components.set_component(them, "identity", {"id": "survivor.gate", "name": "Ada"})
	_transmitted(w, them)
	var zeds_before: int = int(w.components.count("shambler"))
	SimInfection.put_down(w, them)
	w.step()
	if not w.components.has_component(them, "corpse"):
		push_error("put_down left the body standing: no corpse, alive=%s" % str(bool(w.entities.call("is_alive", them))))
		return false
	if int(w.components.count("shambler")) != zeds_before:
		push_error("a put-down survivor turned anyway: shamblers %d -> %d" % [zeds_before, int(w.components.count("shambler"))])
		return false

	# Negative: identical body, identical exposure, reaped the ordinary way. This one must turn.
	var w2: Variant = _world()
	var other: int = _bystander(w2, 9.5, 16.5)
	w2.components.set_component(other, "identity", {"id": "survivor.gate", "name": "Ada"})
	_transmitted(w2, other)
	var before2: int = int(w2.components.count("shambler"))
	SimHealth.finish_death(w2, other)
	w2.step()
	if int(w2.components.count("shambler")) <= before2:
		push_error("the control did not turn, so the put-down proves nothing: shamblers %d -> %d" % [before2, int(w2.components.count("shambler"))])
		return false

	# Control: nobody put this one down, so nothing may have happened to them.
	var w3: Variant = _world()
	var untouched: int = _bystander(w3, 9.5, 16.5)
	w3.components.set_component(untouched, "identity", {"id": "survivor.gate", "name": "Ada"})
	_transmitted(w3, untouched)
	w3.step()
	if w3.components.has_component(untouched, "corpse") or not bool(w3.entities.call("is_alive", untouched)):
		push_error("a survivor nobody touched became a corpse")
		return false
	print("PUT-DOWN OK corpse on the step, no turn, and the ordinary death still turns")
	return true


# One transmitted exposure on PART, in the shape SimInfection writes.
func _transmitted(w: Variant, entity: int) -> void:
	w.components.set_component(entity, "zombieInfection", {"exposures": [{
		"source": -1,
		"bodyPart": PART,
		"exposedAtTick": int(w.tick),
		"transmitted": true,
		"stage": SimInfection.Stage.Latent,
		"stageEnteredAtTick": int(w.tick),
		"cauterized": false,
		"amputated": false,
	}]})


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
func _a_partial_hold_clots_nothing_and_banks_everything() -> bool:
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

	# R8, and the effect rather than the field: the next press on this part must be short, and it
	# must finish. `full - 1` was already served, so what is left is one tick, floored -- and one
	# tick later the wound is clotted for good, which is the only observable that matters.
	var resumed: Dictionary = SimTreatment.begin(w, w.player, w.player, PART, "pressure")
	if not bool(resumed.get("ok", false)):
		push_error("a press could not be resumed on the banked wound: %s" % str(resumed.get("reason", "")))
		return false
	var remaining: int = int(resumed.get("ticks", 0))
	if remaining > 2:
		push_error("the resumed press asked for %d of %d ticks -- %d were already served and banked" % [remaining, full, full - 1])
		return false
	_run_ticks(w, remaining)
	var banked_end: float = _blood(w, w.player)
	_run_ticks(w, 200)
	if _blood(w, w.player) != banked_end:
		push_error("the resumed press did not clot: %.4f -> %.4f over 200 ticks after it finished" % [banked_end, _blood(w, w.player)])
		return false

	# The true negative, and the one that stops R8 from making pressure free: the same wound, the
	# same released hold, but ended by a stagger. R3 keeps nothing, so the next press pays in full.
	var lost: Variant = _world()
	_deep_wound(lost, lost.player)
	SimTreatment.begin(lost, lost.player, lost.player, PART, "pressure")
	# Two short, not one: events.publish only queues and handlers run at drain, at the END of
	# world.step(), by which point treatment.channel has already ticked. A stagger arriving on the
	# tick a hold completes is genuinely too late to stop it -- the same reason the DURABILITY
	# assertion below counts the same way.
	_run_ticks(lost, full - 2)
	lost.events.publish({"type": "entity.staggered", "entity": lost.player})
	lost.step()
	if lost.components.has_component(lost.player, "treatment"):
		push_error("the stagger control did not end its channel, so it is not a control")
		return false
	var from_cold: Dictionary = SimTreatment.begin(lost, lost.player, lost.player, PART, "pressure")
	if int(from_cold.get("ticks", 0)) != full:
		push_error("a press ended by a stagger banked %d ticks -- R3 keeps nothing" % (full - int(from_cold.get("ticks", 0))))
		return false
	print("ABORTED HOLD OK released at %d/%d, still bleeding, %.4f -> %.4f over 200 more ticks; the resumed press asked %d ticks and clotted, and the stagger control paid the full %d" % [
		full - 1, full, before, after, remaining, int(from_cold.get("ticks", 0)),
	])
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


# The three subscriptions no longer say the same thing, and this is where that is held down.
#
# A stagger still cancels everything (R3) -- being knocked off your feet takes your own hand off
# your own arm. A grab cancels everything it touches *except* the victim's own self-pressure (R2),
# because a second set of hands closing on somebody does not physically peel their palm off their
# own wound. An escape (R5) is the exact mirror: it cancels the victim's own self-pressure and
# *only* that, so the break-away is a run rather than a pause. So each grab half needs both signs
# to mean anything -- a dressing somebody else was holding on the newly grabbed patient comes apart
# and the patient's own press does not; the patient's own press ends when they tear free and the
# dressing somebody else is holding on them does not.
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

	# R5, and the half of it that is about aim rather than about escaping. The `grab.broken`
	# subscription ends the *victim's own* hand on their own wound so the break-away can move them;
	# it is not "an escape cancels every channel in the area". Somebody kneeling beside a patient
	# who has just torn free is holding a dressing that is more viable than it was a tick ago --
	# the patient has stopped being dragged -- so the escape must not cost the treater their work.
	var freed: Variant = _world()
	var torn: int = _bystander(freed, 9.0, 16.5)
	_deep_wound(freed, torn)
	_hold(freed, torn)
	var aid: Dictionary = SimTreatment.begin(freed, freed.player, torn, PART, "pressure")
	if not bool(aid.get("ok", false)):
		push_error("a free treater could not press on a held patient in reach: %s" % str(aid))
		return false
	_run_ticks(freed, 20)
	freed.components.remove(torn, "grabbed")
	freed.events.publish({"type": "grab.broken", "victim": torn, "by": torn, "cause": "struggle"})
	freed.step()
	if not freed.components.has_component(freed.player, "treatment"):
		push_error("a patient tearing free cost the treater their press -- the escape interrupt is not aimed at the victim's own hand")
		return false
	if not freed.components.has_component(torn, "treated"):
		push_error("the freed patient stopped being marked treated while the channel ran on")
		return false

	# Still genuinely unrelated: nothing subscribes `noise.emitted` to a channel, and it is the
	# only event here that neither of the two grab subscriptions nor the stagger one reads.
	var quiet: Variant = _world()
	_deep_wound(quiet, quiet.player)
	SimTreatment.begin(quiet, quiet.player, quiet.player, PART, "pressure")
	_run_ticks(quiet, 20)
	quiet.events.publish({"type": "noise.emitted", "x": 8.5, "y": 16.5, "magnitude": 40.0, "source": -1})
	quiet.step()
	if not quiet.components.has_component(quiet.player, "treatment"):
		push_error("an unrelated event cancelled the channel, so the interrupts above prove nothing")
		return false
	print("INTERRUPTS OK stagger breaks it, a grab breaks somebody else's dressing but not the victim's own press, an escape breaks the victim's own press but not somebody else's hands on them, an unrelated event breaks none of it")
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


# --- the back half of the ladder: clean, then close ------------------------------------------
#
# Every row below measures an outcome -- how often a wound actually goes septic over a fixed run of
# seeded rolls, how many earned ticks a wound needs before `wound.closed` fires, how much blood a
# sprint costs, how many units come off a stack. None of them asserts that a field the code just
# wrote holds the value the code just wrote, which is the rule the header states and the reason the
# first version of the sepsis roll could be gated, correct, and read by nothing.

# --- ladder fixtures ---------------------------------------------------------------------------

# A deep wound somebody has already stopped: not bleeding, no dressing. That is the state the two
# new rungs are aimed at, and it is what pressure leaves behind.
func _stopped_wound(w: Variant, entity: int, part: String = PART) -> Dictionary:
	var wd: Dictionary = _deep_wound(w, entity, part)
	wd["bleeding"] = false
	return wd


func _medicine(w: Variant, entity: int, points: int) -> void:
	w.components.set_component(entity, "skillWeb", {"points": {"Medicine": points}, "nodes": []})


func _sprint(w: Variant, entity: int) -> void:
	w.components.set_component(entity, "posture", {"current": SimStances.Stance.Sprint, "target": SimStances.Stance.Sprint, "ticks_left": 0})


# One dusk's worth of rolls, paired. `n` identical deep wounds on one body, each decorated by the
# caller, rolled once through the real `roll_sepsis` on the real named `sepsis` stream. Two calls
# with the same seed draw the same `n` uniforms in the same order, so the difference between two
# counts is the multiplier under test and nothing else -- which is what makes a comparison of two
# incidences honest rather than two independent samples that happen to differ.
func _septic_count(seed_val: int, n: int, decorate: Callable) -> int:
	var w: Variant = _world(seed_val)
	for _i in n:
		decorate.call(_deep_wound(w, w.player))
	return int(SimWounds.roll_sepsis(w, w.player, 1.0, 0))


const ROLLS: int = 240
const ROLL_SEED: int = 5150


# Row 1. docs/05 drives the sepsis chance from five things and `sepsis_chance` applied four of
# them: "whether it was cleaned" was named in that function's own comment and had no term. This is
# the term, measured as incidence rather than as a returned number.
#
# Three signs, because "cleaned is lower" alone would pass on a clean that made a wound sterile:
#   positive  a cleaned wound goes septic materially less often than an identical uncleaned one
#   negative  the uncleaned control goes septic at all, so the comparison has something to be
#             lower than
#   bound     the cleaned run still goes septic sometimes -- a good clean never makes a wound safe,
#             the same rule SEPSIS_MIN_MUL states for a good medic
#
# The fourth assertion is the calibration this slice promised: an uncleaned wound's chance is
# *bit-identical* to the pre-change expression, so nothing about an uninvested survivor moved.
func _cleaning_is_the_missing_sepsis_factor() -> bool:
	var dirty: int = _septic_count(ROLL_SEED, ROLLS, func(_wd: Dictionary) -> void:
		pass
	)
	var cleaned: int = _septic_count(ROLL_SEED, ROLLS, func(wd: Dictionary) -> void:
		wd["cleaned"] = true
		wd["cleanTier"] = "antiseptic"
	)
	if dirty <= 0:
		push_error("the uncleaned control never went septic over %d rolls, so the clean discount proves nothing" % ROLLS)
		return false
	if cleaned >= dirty:
		push_error("cleaning bought nothing: %d septic cleaned vs %d uncleaned over %d rolls" % [cleaned, dirty, ROLLS])
		return false
	if float(cleaned) > 0.75 * float(dirty):
		push_error("cleaning bought almost nothing: %d vs %d over %d rolls" % [cleaned, dirty, ROLLS])
		return false
	if cleaned <= 0:
		push_error("a cleaned wound never went septic over %d rolls -- a good clean must not make a wound safe" % ROLLS)
		return false

	# The uninvested path, unchanged. Recomputed here from the three multipliers that existed
	# before this slice, so a clean term that leaked onto uncleaned wounds fails right here.
	var probe: Variant = _world()
	var wd2: Dictionary = _deep_wound(probe, probe.player)
	var was: float = float(SimWounds.SEPSIS_BASE_BY_SEVERITY[SimWounds.Severity.DeepWound]) \
		* 0.9 \
		* float(SimWounds.SEPSIS_BANDAGE_MUL["none"]) \
		* maxf(SimWounds.SEPSIS_MIN_MUL, 1.0 - 1.0 * SimWounds.SEPSIS_SKILL_RELIEF)
	var now: float = SimWounds.sepsis_chance(wd2, 0.9, 1)
	if absf(now - was) > 0.0000001:
		push_error("an uncleaned wound is no longer priced the way it was: %.7f vs %.7f" % [now, was])
		return false
	print("CLEAN SEPSIS OK %d/%d septic uncleaned vs %d/%d cleaned, neither zero; an uncleaned wound still prices %.6f" % [dirty, ROLLS, cleaned, ROLLS, now])
	return true


# Row 2. The supply is content, the pick is the rank, and the thing that comes off the stack is the
# thing the wound got. Measured on the stack that was actually spent and on the incidence the grade
# actually buys -- not on the tier string the channel wrote.
func _the_supply_carried_is_the_one_that_gets_used() -> bool:
	# A water bottle does not stack (no `stack` key on its base), so the honest probe for it is
	# whether the bottle is still in the pack at all rather than a stack count, which would read 1
	# forever and assert nothing.
	var rich: Variant = _world()
	_deep_wound(rich, rich.player)
	var water: int = _give(rich, rich.player, "item.water.bottle", 1)
	var anti: int = _give(rich, rich.player, "item.antiseptic.bottle", 3)
	SimTreatment.begin(rich, rich.player, rich.player, PART, "clean")
	_run_ticks(rich, int(SimWounds.CLEAN_TICKS[SimWounds.Severity.DeepWound]))
	if _stack_count(rich, anti) != 2:
		push_error("carrying both, the clean took %d antiseptic off a stack of 3" % (3 - _stack_count(rich, anti)))
		return false
	if not SimInventory.owns(rich, rich.player, water):
		push_error("carrying both, the clean drank the water bottle instead of opening the antiseptic")
		return false

	var poor: Variant = _world()
	_deep_wound(poor, poor.player)
	var only: int = _give(poor, poor.player, "item.water.bottle", 1)
	SimTreatment.begin(poor, poor.player, poor.player, PART, "clean")
	_run_ticks(poor, int(SimWounds.CLEAN_TICKS[SimWounds.Severity.DeepWound]))
	if SimInventory.owns(poor, poor.player, only):
		push_error("carrying only water, the clean completed without spending the bottle")
		return false

	# And the grades are ordered by what they cost you, over the same seeded rolls as row 1.
	var by_water: int = _septic_count(ROLL_SEED, ROLLS, func(wd: Dictionary) -> void:
		wd["cleaned"] = true
		wd["cleanTier"] = "water"
	)
	var by_anti: int = _septic_count(ROLL_SEED, ROLLS, func(wd: Dictionary) -> void:
		wd["cleaned"] = true
		wd["cleanTier"] = "antiseptic"
	)
	if by_water <= by_anti:
		push_error("rinsing with drinking water was no worse than antiseptic: %d vs %d septic over %d rolls" % [by_water, by_anti, ROLLS])
		return false

	var empty: Variant = _world()
	_deep_wound(empty, empty.player)
	var refused: Dictionary = SimTreatment.begin(empty, empty.player, empty.player, PART, "clean")
	if bool(refused.get("ok", false)) or String(refused.get("reason", "")) != "no-supply":
		push_error("cleaning with nothing carried returned %s" % str(refused))
		return false
	print("CLEAN SUPPLY OK antiseptic spent over the water it was carried beside, water spent when it is all there is (%d vs %d septic), empty-handed refused '%s'" % [by_water, by_anti, refused.get("reason", "")])
	return true


# Row 3. The two things a suture buys, both measured as outcomes: the wound reaches `wound.closed`
# in fewer earned ticks, and it does not tear open under the sprint that tears an identical
# unsutured one apart.
#
# The sprint half deliberately reuses check_m2_recovery's OVERWORK fixture shape -- same posture
# component, same fresh deep wound -- so the two gates cannot drift about what "reopens" means.
func _closing_speeds_the_knitting_and_holds_it_shut() -> bool:
	var budget: int = int(SimWounds.RECOVERY_DAYS[SimWounds.Severity.DeepWound]) * SimClock.DAY_TICKS

	# Ten earned ticks short of done, so a whole 16-day recovery does not have to be simulated to
	# measure the rate. Sutured, the wound earns two a tick and is closed after five.
	var sewn: Variant = _world()
	var closed_at: Array[int] = []
	sewn.events.subscribe({"id": "gate.closed", "type": "wound.closed", "handler": func(_e: Dictionary) -> void:
		closed_at.append(int(sewn.tick))
	})
	var a: Dictionary = _stopped_wound(sewn, sewn.player)
	a["healedTicks"] = budget - 10
	a["closed"] = true
	_run_ticks(sewn, 5)
	if closed_at.is_empty():
		push_error("a sutured wound five earned ticks from done did not close")
		return false

	var raw: Variant = _world()
	var raw_closed: Array[int] = []
	raw.events.subscribe({"id": "gate.closed2", "type": "wound.closed", "handler": func(_e: Dictionary) -> void:
		raw_closed.append(int(raw.tick))
	})
	var b: Dictionary = _stopped_wound(raw, raw.player)
	b["healedTicks"] = budget - 10
	_run_ticks(raw, 5)
	if not raw_closed.is_empty():
		push_error("an unsutured wound closed in the same five ticks, so the suture bought no speed")
		return false
	# ...and the unsutured control is not simply stuck: it closes on the schedule it always had,
	# ten earned ticks, which is the calibration claim that nothing about the uninvested path moved.
	_run_ticks(raw, 5)
	if raw_closed.is_empty():
		push_error("an unsutured wound did not close after its full ten earned ticks -- the ordinary rate changed")
		return false
	if int(b.get("healedTicks", 0)) != budget:
		push_error("an unsutured wound earned %d ticks over ten, not ten" % (int(b.get("healedTicks", 0)) - (budget - 10)))
		return false

	# The sprint. A fresh sutured deep wound holds; the identical unsutured one tears open and pays
	# for it in blood, which is the effect rather than the flag.
	var held: Variant = _world()
	_stopped_wound(held, held.player)["closed"] = true
	_sprint(held, held.player)
	_run_ticks(held, 200)
	var kept: float = _blood(held, held.player)

	var tears: Variant = _world()
	_stopped_wound(tears, tears.player)
	_sprint(tears, tears.player)
	_run_ticks(tears, 200)
	var lost: float = _blood(tears, tears.player)
	if kept > 0.0:
		push_error("a sutured wound tore open on a sprint: %.4f lost" % kept)
		return false
	if lost <= 0.0:
		push_error("the unsutured control did not reopen on a sprint, so the suture proves nothing")
		return false
	print("CLOSE OK sutured closed in 5 earned ticks against 10, and held under a sprint (%.4f lost) the unsutured one did not (%.4f)" % [kept, lost])
	return true


# Row 4. What `close` refuses and why. Each refusal beside the case that grants it, because a verb
# that refuses everything would satisfy the refusals on its own.
func _you_close_what_you_have_already_stopped() -> bool:
	# Granted: stopped wound, kit carried, a medic's hands.
	var ready: Variant = _world()
	_stopped_wound(ready, ready.player)
	_medicine(ready, ready.player, SimWounds.CLOSE_MEDICINE_FLOOR)
	_give(ready, ready.player, "item.suture.kit", 2)
	var granted: Dictionary = SimTreatment.begin(ready, ready.player, ready.player, PART, "close")
	if not bool(granted.get("ok", false)) or int(granted.get("ticks", 0)) != int(SimWounds.CLOSE_TICKS[SimWounds.Severity.DeepWound]):
		push_error("a stopped deep wound at the Medicine floor was refused a suture: %s" % str(granted))
		return false

	# Still bleeding: refused, and in its own word rather than "not-bleeding", which would be the
	# opposite complaint and point the player at the wrong verb.
	var wet: Variant = _world()
	_deep_wound(wet, wet.player)
	_medicine(wet, wet.player, SimWounds.CLOSE_MEDICINE_FLOOR)
	_give(wet, wet.player, "item.suture.kit", 2)
	var bleeding: Dictionary = SimTreatment.begin(wet, wet.player, wet.player, PART, "close")
	if bool(bleeding.get("ok", false)) or String(bleeding.get("reason", "")) != "still-bleeding":
		push_error("closing a bleeding wound returned %s" % str(bleeding))
		return false

	# Unskilled: a deep wound needs a medic. Same fixture, Medicine 0.
	var novice: Variant = _world()
	_stopped_wound(novice, novice.player)
	_medicine(novice, novice.player, 0)
	_give(novice, novice.player, "item.suture.kit", 2)
	var unskilled: Dictionary = SimTreatment.begin(novice, novice.player, novice.player, PART, "close")
	if bool(unskilled.get("ok", false)) or String(unskilled.get("reason", "")) != "unskilled":
		push_error("a deep wound at Medicine 0 returned %s, expected 'unskilled'" % str(unskilled))
		return false

	# And the floor is deep-wound-only: the same novice may close a laceration. Without this the
	# "unskilled" row above would pass on a flat skill wall over the whole verb.
	var lesser: Variant = _world()
	var small: Dictionary = SimWounds.append_wound(lesser, lesser.player, "cut", PART, -1, 8.0)
	small["bleeding"] = false
	_medicine(lesser, lesser.player, 0)
	_give(lesser, lesser.player, "item.suture.kit", 2)
	if int(small.get("severity", -1)) != SimWounds.Severity.Laceration:
		push_error("the fixture's lesser wound came out severity %d, not a laceration" % int(small.get("severity", -1)))
		return false
	var minor: Dictionary = SimTreatment.begin(lesser, lesser.player, lesser.player, PART, "close")
	if not bool(minor.get("ok", false)):
		push_error("a novice was refused a laceration: %s -- the Medicine floor is not deep-wound-only" % str(minor))
		return false
	print("CLOSE REFUSALS OK stopped+skilled granted (%d ticks), bleeding refused 'still-bleeding', deep at Medicine 0 refused 'unskilled', a laceration still granted" % int(granted.get("ticks", 0)))
	return true


# Row 5. The shortcut stays legal, and it stays expensive. docs/30 records why: refusing to dress a
# dirty wound would turn a decision under pressure into a rule, and the wound would go on bleeding
# while the survivor went looking for antiseptic.
func _dressing_a_dirty_wound_is_allowed_and_still_costs() -> bool:
	var w: Variant = _world()
	_deep_wound(w, w.player)
	_give(w, w.player, "item.bandage.cloth", 2)
	var res: Dictionary = SimTreatment.begin(w, w.player, w.player, PART, "bandage")
	if not bool(res.get("ok", false)):
		push_error("bandaging an uncleaned wound was refused: %s" % str(res))
		return false
	_run_ticks(w, int(SimWounds.BANDAGE_TICKS[SimWounds.Severity.DeepWound]))
	var settled: float = _blood(w, w.player)
	_run_ticks(w, 200)
	if _blood(w, w.player) != settled:
		push_error("a dirty wound was dressed and went on bleeding: %.4f -> %.4f" % [settled, _blood(w, w.player)])
		return false

	var dirty_dressed: int = _septic_count(ROLL_SEED, ROLLS, func(wd: Dictionary) -> void:
		wd["bandage"] = "cloth"
	)
	var clean_dressed: int = _septic_count(ROLL_SEED, ROLLS, func(wd: Dictionary) -> void:
		wd["bandage"] = "cloth"
		wd["cleaned"] = true
		wd["cleanTier"] = "antiseptic"
	)
	if dirty_dressed <= clean_dressed:
		push_error("dressing dirty cost nothing: %d septic vs %d clean-then-dressed over %d rolls" % [dirty_dressed, clean_dressed, ROLLS])
		return false
	print("SHORTCUT OK a dirty wound may be dressed and stops bleeding, at %d septic against clean-then-dress's %d over %d rolls" % [dirty_dressed, clean_dressed, ROLLS])
	return true


# Row 6. The same contract bandaging already keeps, for both new verbs: one unit at completion,
# nothing for an interrupted channel, and a refusal rather than free work when the pack is empty.
func _the_new_verbs_spend_exactly_one_supply() -> bool:
	var clean: Variant = _world()
	_deep_wound(clean, clean.player)
	var bottles: int = _give(clean, clean.player, "item.antiseptic.bottle", 3)
	SimTreatment.begin(clean, clean.player, clean.player, PART, "clean")
	_run_ticks(clean, 50)
	clean.events.publish({"type": "entity.staggered", "entity": clean.player})
	clean.step()
	if _stack_count(clean, bottles) != 3:
		push_error("an interrupted clean spent a bottle: 3 -> %d" % _stack_count(clean, bottles))
		return false
	SimTreatment.begin(clean, clean.player, clean.player, PART, "clean")
	_run_ticks(clean, int(SimWounds.CLEAN_TICKS[SimWounds.Severity.DeepWound]))
	if _stack_count(clean, bottles) != 2:
		push_error("a completed clean spent %d bottles, expected 1" % (3 - _stack_count(clean, bottles)))
		return false

	var sew: Variant = _world()
	_stopped_wound(sew, sew.player)
	_medicine(sew, sew.player, SimWounds.CLOSE_MEDICINE_FLOOR)
	var kits: int = _give(sew, sew.player, "item.suture.kit", 2)
	SimTreatment.begin(sew, sew.player, sew.player, PART, "close")
	_run_ticks(sew, 50)
	sew.events.publish({"type": "entity.staggered", "entity": sew.player})
	sew.step()
	if _stack_count(sew, kits) != 2:
		push_error("an interrupted close spent a kit: 2 -> %d" % _stack_count(sew, kits))
		return false
	SimTreatment.begin(sew, sew.player, sew.player, PART, "close")
	_run_ticks(sew, int(SimWounds.CLOSE_TICKS[SimWounds.Severity.DeepWound]))
	if _stack_count(sew, kits) != 1:
		push_error("a completed close spent %d kits, expected 1" % (2 - _stack_count(sew, kits)))
		return false

	var bare: Variant = _world()
	_stopped_wound(bare, bare.player)
	_medicine(bare, bare.player, SimWounds.CLOSE_MEDICINE_FLOOR)
	var no_kit: Dictionary = SimTreatment.begin(bare, bare.player, bare.player, PART, "close")
	if bool(no_kit.get("ok", false)) or String(no_kit.get("reason", "")) != "no-kit":
		push_error("closing with nothing carried returned %s" % str(no_kit))
		return false
	print("LADDER SUPPLY OK clean 3->2 and close 2->1 at completion, both cost nothing interrupted, empty-handed refused '%s'" % no_kit.get("reason", ""))
	return true


# Row 7. R1 by inheritance, asserted explicitly rather than assumed. `_can_begin` derives the held
# exemption from `verb == "pressure" and actor == patient`, so every verb added after it is refused
# to a grabbed body for free -- and "for free" is exactly the kind of claim that stops being true
# without anybody noticing.
func _a_hold_still_allows_exactly_one_channel() -> bool:
	var w: Variant = _world()
	_stopped_wound(w, w.player)
	_deep_wound(w, w.player, "arm_left")
	_medicine(w, w.player, SimWounds.CLOSE_MEDICINE_FLOOR)
	_give(w, w.player, "item.antiseptic.bottle", 2)
	_give(w, w.player, "item.suture.kit", 2)
	_hold(w, w.player)
	for verb in ["clean", "close"]:
		var r: Dictionary = SimTreatment.begin(w, w.player, w.player, PART, String(verb))
		if bool(r.get("ok", false)) or String(r.get("reason", "")) != "cannot-channel":
			push_error("a held survivor was granted '%s': %s" % [verb, str(r)])
			return false
	var press: Dictionary = SimTreatment.begin(w, w.player, w.player, "arm_left", "pressure")
	if not bool(press.get("ok", false)):
		push_error("the held self-press was refused, so the two refusals above prove nothing: %s" % str(press))
		return false
	print("HELD LADDER OK clean and close both refused 'cannot-channel' while held, self-pressure still granted")
	return true


# Row 8. The whole ladder through the real `treat.context` command path -- the same route the T key
# takes -- because a verb the one key cannot reach is a verb the player does not have.
func _one_key_walks_the_whole_ladder() -> bool:
	var w: Variant = _world()
	_deep_wound(w, w.player)
	_medicine(w, w.player, SimWounds.CLOSE_MEDICINE_FLOOR)
	_give(w, w.player, "item.antiseptic.bottle", 2)
	_give(w, w.player, "item.suture.kit", 2)

	var rungs: Array[String] = []
	for span in [
		{"verb": "pressure", "ticks": int(SimWounds.PRESSURE_TICKS[SimWounds.Severity.DeepWound])},
		{"verb": "clean", "ticks": int(SimWounds.CLEAN_TICKS[SimWounds.Severity.DeepWound])},
		{"verb": "close", "ticks": int(SimWounds.CLOSE_TICKS[SimWounds.Severity.DeepWound])},
	]:
		w.commands.push({"type": "treat.context"})
		w.step()
		var t: Variant = w.components.get_component(w.player, "treatment")
		if not (t is Dictionary):
			push_error("the ladder stalled before '%s': the key started nothing" % (span as Dictionary)["verb"])
			return false
		rungs.append(String((t as Dictionary).get("verb", "")))
		if String((t as Dictionary).get("verb", "")) != String((span as Dictionary)["verb"]):
			push_error("the key picked '%s' where the ladder wanted '%s' (so far: %s)" % [(t as Dictionary).get("verb", ""), (span as Dictionary)["verb"], str(rungs)])
			return false
		_run_ticks(w, int((span as Dictionary)["ticks"]))

	# Rung four is rest, and it needs no verb: with nothing left to do the key does nothing at all
	# rather than opening a channel or complaining every tick.
	w.commands.push({"type": "treat.context"})
	w.step()
	if w.components.has_component(w.player, "treatment"):
		push_error("the key opened a fourth channel on a wound that is stopped, clean and sutured")
		return false

	# The missing-rung fallback: no cleaning supply, but a kit and a stopped wound. The key must
	# skip the rung it cannot pay for rather than refusing every tick.
	var partial: Variant = _world()
	_stopped_wound(partial, partial.player)
	_medicine(partial, partial.player, SimWounds.CLOSE_MEDICINE_FLOOR)
	_give(partial, partial.player, "item.suture.kit", 2)
	partial.commands.push({"type": "treat.context"})
	partial.step()
	var t2: Variant = partial.components.get_component(partial.player, "treatment")
	if not (t2 is Dictionary) or String((t2 as Dictionary).get("verb", "")) != "close":
		push_error("with no cleaning supply the key chose %s rather than falling through to close" % str(t2))
		return false
	print("LADDER KEY OK %s, then nothing; and a missing rung falls through to close" % " -> ".join(rungs))
	return true


# Row 9, the dead-socket assertion. A verb only the player can reach is a verb most of the colony
# does not have -- `treatment.self-aid` used to enter `context` only for a bleeding body, which
# would have made both new rungs player-only on the day they landed.
func _a_survivor_who_is_not_the_player_cleans_their_own_wound() -> bool:
	var w: Variant = _world()
	var npc: int = _bystander(w, 20.0, 16.5)
	SimInventory.make_inventory(w, npc)
	_give(w, npc, "item.antiseptic.bottle", 2)
	_stopped_wound(w, npc)
	w.step()
	var t: Variant = w.components.get_component(npc, "treatment")
	if not (t is Dictionary) or String((t as Dictionary).get("verb", "")) != "clean":
		push_error("an NPC with a dirty wound and antiseptic in their pack started %s" % str(t))
		return false
	# ...and it finishes and buys the discount, measured as a price rather than a flag.
	var wd: Dictionary = _wounds(w, npc)[0] as Dictionary
	var before: float = SimWounds.sepsis_chance(wd, 1.0, 0)
	_run_ticks(w, int(SimWounds.CLEAN_TICKS[SimWounds.Severity.DeepWound]))
	var after: float = SimWounds.sepsis_chance(wd, 1.0, 0)
	if after >= before:
		push_error("the NPC's own clean bought nothing: %.6f -> %.6f" % [before, after])
		return false

	# The negative: the same NPC with the same wound and an empty pack starts nothing, so the
	# positive is the supply being reachable rather than a channel that opens on anything.
	var poor: Variant = _world()
	var broke: int = _bystander(poor, 20.0, 16.5)
	SimInventory.make_inventory(poor, broke)
	_stopped_wound(poor, broke)
	poor.step()
	if poor.components.has_component(broke, "treatment"):
		push_error("an NPC with no cleaning supply opened a channel anyway")
		return false
	print("SELF-CLEAN OK npc opened its own clean unprompted, %.6f -> %.6f septic chance; an empty-handed one opened nothing" % [before, after])
	return true


# Row 10, the second dead-socket assertion, and the one the erase exists for. `_reopen_from_overwork`
# erases `pressedTicks` by name when a wound tears open; a cleaned flag left behind would go on
# buying a discount for work the sprint has just undone, silently, every dusk, forever.
#
# The measurement is exact rather than directional: a reopened wound must price *identically* to
# one nobody ever cleaned, over the same seeds -- and a wound that was never torn must not.
func _a_reopened_wound_is_dirty_again() -> bool:
	var reopened: int = _septic_count(ROLL_SEED, ROLLS, func(_wd: Dictionary) -> void:
		pass
	)
	var torn: Variant = _world()
	var wd: Dictionary = _stopped_wound(torn, torn.player)
	wd["cleaned"] = true
	wd["cleanTier"] = "antiseptic"
	var priced_clean: float = SimWounds.sepsis_chance(wd, 1.0, 0)
	_sprint(torn, torn.player)
	_run_ticks(torn, 2)
	if not bool(wd.get("bleeding", false)):
		push_error("the fixture's wound did not reopen, so nothing about the erase is being measured")
		return false
	var priced_torn: float = SimWounds.sepsis_chance(wd, 1.0, 0)
	var dirty: Variant = _world()
	var never: Dictionary = _deep_wound(dirty, dirty.player)
	if absf(priced_torn - SimWounds.sepsis_chance(never, 1.0, 0)) > 0.0000001:
		push_error("a reopened wound still prices %.7f against an uncleaned wound's %.7f" % [priced_torn, SimWounds.sepsis_chance(never, 1.0, 0)])
		return false
	if priced_clean >= priced_torn:
		push_error("the wound was not priced as cleaned before it tore: %.7f vs %.7f" % [priced_clean, priced_torn])
		return false

	# The control: a cleaned wound nobody sprinted on keeps its discount, over the same rolls.
	var kept: int = _septic_count(ROLL_SEED, ROLLS, func(w2: Dictionary) -> void:
		w2["cleaned"] = true
		w2["cleanTier"] = "antiseptic"
	)
	if kept >= reopened:
		push_error("a never-reopened cleaned wound went septic %d times against a dirty wound's %d -- the discount is not holding" % [kept, reopened])
		return false
	print("REOPEN ERASE OK a torn wound reprices %.6f -> %.6f, exactly an uncleaned wound; an untorn one keeps its discount (%d vs %d septic)" % [priced_clean, priced_torn, kept, reopened])
	return true


# Row 11. check_m2_attach.gd's precedent: content nobody can find is content nobody will ever hold.
# Both halves -- the loot tables list it, and SimItems actually resolves it -- because a typo in a
# loot entry is findable-looking and resolves to nothing.
func _the_new_supplies_are_findable() -> bool:
	var droppable: Dictionary = {}
	var tree: Dictionary = ContentLoader.load_tree()
	for path in tree.keys():
		if not String(path).begins_with("loot/"):
			continue
		var value: Variant = tree[path]
		if not value is Array:
			continue
		for table_v in value as Array:
			for entry_v in (table_v as Dictionary).get("entries", []) as Array:
				droppable[String((entry_v as Dictionary).get("item", ""))] = true
	if droppable.is_empty():
		push_error("no loot table entries were read, so findability is asserting nothing")
		return false

	var w: Variant = _world()
	for row in [
		{"id": "item.antiseptic.bottle", "key": "cleanTier", "value": "antiseptic"},
		{"id": "item.suture.kit", "key": "closeKind", "value": "suture"},
		{"id": "item.water.bottle", "key": "cleanTier", "value": "water"},
	]:
		var id: String = String((row as Dictionary)["id"])
		if not droppable.has(id):
			push_error("%s is in no loot table, so it cannot be found" % id)
			return false
		var base: Variant = SimItems.content_entry(w, "item", id)
		if not (base is Dictionary):
			push_error("%s is in a loot table and resolves to no item base" % id)
			return false
		if String((base as Dictionary).get(String((row as Dictionary)["key"]), "")) != String((row as Dictionary)["value"]):
			push_error("%s declares %s='%s'" % [id, (row as Dictionary)["key"], (base as Dictionary).get(String((row as Dictionary)["key"]), "")])
			return false
		# And it survives the spawn path a loot roll would take it through.
		var item: int = SimItems.spawn_item(w, id, {"tier": "scavenged", "count": 1})
		var resolved: Variant = SimItems.item_base_of(w, item)
		if not (resolved is Dictionary) or String((resolved as Dictionary).get("id", "")) != id:
			push_error("%s did not resolve through SimItems after spawning" % id)
			return false

	# The negative: an id nobody authored is neither findable nor resolvable, so the loop above is
	# testing something.
	if droppable.has("item.antiseptic.imaginary") or SimItems.content_entry(w, "item", "item.antiseptic.imaginary") is Dictionary:
		push_error("a made-up base id was found, so findability is asserting nothing")
		return false
	print("LADDER CONTENT OK antiseptic, suture kit and the water bottle's clean tier all findable and resolvable; a made-up id is neither")
	return true


# Same seed and same commands, byte-identical. The negative moves one command by a single
# tick, which must produce a different serialisation -- otherwise the comparison is
# measuring nothing.
func _deterministic_replay() -> bool:
	var runs: Array[String] = []
	for offset in [0, 0, 7]:
		var w: Variant = _world(99)
		_deep_wound(w, w.player)
		# A second wound on another part, so the two later rungs have something of their own to
		# work on while the dressing is still being argued about on the torso.
		_stopped_wound(w, w.player, "arm_left")
		_medicine(w, w.player, SimWounds.CLOSE_MEDICINE_FLOOR)
		_give(w, w.player, "item.bandage.cloth")
		_give(w, w.player, "item.antiseptic.bottle", 2)
		_give(w, w.player, "item.suture.kit", 2)
		for i in 2400:
			if i == 10 + int(offset):
				w.commands.push({"type": "treat.begin", "patient": w.player, "part": PART, "verb": "bandage"})
			if i == 900 + int(offset):
				w.commands.push({"type": "treat.begin", "patient": w.player, "part": "arm_left", "verb": "clean"})
			if i == 1600 + int(offset):
				w.commands.push({"type": "treat.begin", "patient": w.player, "part": "arm_left", "verb": "close"})
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
