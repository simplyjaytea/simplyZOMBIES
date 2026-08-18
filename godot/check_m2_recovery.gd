extends SceneTree
# Recovery: wounds that close, integrity that climbs back, and the one thing that never does.
#
# Guards Slice 3. Until this, **nothing in the simulation raised a body part's integrity
# except `jobs.gd._treat`, which healed the torso and only the torso.** Head, arms, hands,
# legs and feet fell monotonically for the life of a survivor. That is the single fact that
# kept `SimShambler.GRABS_ENABLED` switched off through three slices: grabs are the first
# repeating damage source ever aimed at survivors, and without recovery they are not *hard*,
# they are *cumulative*.
#
# What this gate is holding down:
#
#  1. **Recovery is earned, not elapsed.** A wound's clock only advances on ticks the
#     survivor was fed and not exerting. A run spent starving and sprinting heals nothing no
#     matter how many days pass, and `_recovery_is_earned_not_elapsed` is the pair that fails
#     if the gate ever becomes a wall-clock timer.
#
#  2. **Zero is permanent.** A part reduced to nothing does not come back, which is what
#     makes docs/05's "one-armed survivor" a real outcome and what stops an amputation
#     growing back overnight. Two assertions, because the amputation path reaches zero by a
#     different route than damage does.
#
#  3. **Assert the effect, never the mechanism** (docs/30:513-524). Every claim here is
#     measured on integrity that actually moved or a wound that actually left the list.
#
# Every assertion carries a true negative beside its positive.

const World = preload("res://sim/world.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const SimTreatment = preload("res://sim/modules/treatment.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimCombat = preload("res://sim/combat.gd")
const SimClock = preload("res://sim/time/clock.gd")
const SimStances = preload("res://sim/stances.gd")

# Long enough that the slowest band moves a measurable amount, short enough that a gate with
# a dozen worlds in it still finishes: a torso deep wound regains 40/(16*288000) per tick, so
# ten thousand ticks is ~0.087 -- three orders of magnitude above float noise.
const WINDOW: int = 10000
const PART: String = "torso"
const DEEP_DAMAGE: float = 20.0
const SCRATCH_DAMAGE: float = 4.0
# 10 of a 40-torso is a quarter of it -- inside Laceration's 0.15..0.40 band. The dressed /
# undressed pair below uses this rather than DEEP_DAMAGE because a deep torso wound left open
# bleeds out in 5,000 ticks, and a control that dies halfway through the window is measuring
# the reaper rather than recovery.
const LACERATION_DAMAGE: float = 10.0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _a_dressed_wound_mends_and_an_open_one_does_not() and ok
	ok = _recovery_is_earned_not_elapsed() and ok
	ok = _severity_sets_the_pace() and ok
	ok = _a_destroyed_part_never_comes_back() and ok
	ok = _an_amputated_limb_stays_amputated() and ok
	ok = _a_wound_closes_on_its_budget_and_not_before() and ok
	ok = _closing_a_wound_gives_back_what_it_was_taking() and ok
	ok = _sprinting_reopens_a_fresh_deep_wound() and ok
	ok = _a_corpse_does_not_convalesce() and ok
	ok = _one_effect_leaf_serves_both_intakes() and ok
	ok = _the_doctor_threshold_reads_states_not_numbers() and ok
	ok = _deterministic_replay() and ok
	if ok:
		print("M2_RECOVERY_OK healing is earned, zero is permanent, a fresh deep wound tears open")
		quit(0)
	else:
		push_error("M2_RECOVERY_FAIL")
		quit(1)


# --- fixture ------------------------------------------------------------------------------

func _world(seed_val: int = 7171) -> Variant:
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
	return w


# A wound plus the damage that would have caused it. append_wound records; it does not hurt
# anybody -- health.gd's damage_part does that first in real play -- so a fixture that wants
# a part to actually be able to climb back has to lower it by hand.
func _hurt(w: Variant, part: String, damage: float, dressed: bool = true) -> Dictionary:
	var body: Dictionary = w.components.get_component(w.player, "body") as Dictionary
	body[part] = maxf(1.0, float(body[part]) - damage)
	var wound: Dictionary = SimWounds.append_wound(w, w.player, "cut", part, -1, damage)
	if dressed:
		wound["bleeding"] = false
		wound["bandage"] = "cloth"
	return wound


func _integrity(w: Variant, part: String) -> float:
	return float((w.components.get_component(w.player, "body") as Dictionary)[part])


func _wounds(w: Variant) -> Array:
	var inj: Variant = w.components.get_component(w.player, "injuries")
	if not (inj is Dictionary):
		return []
	return (inj as Dictionary).get("wounds", []) as Array


func _run_ticks(w: Variant, ticks: int) -> void:
	for _i in ticks:
		w.step()


func _gained(w: Variant, part: String, ticks: int) -> float:
	var before: float = _integrity(w, part)
	_run_ticks(w, ticks)
	return _integrity(w, part) - before


# --- assertions ----------------------------------------------------------------------------

# Stopping the bleeding is what starts the clock. That is the whole reason Part B's two verbs
# matter beyond the blood-loss arithmetic, and it is asserted as ground actually regained.
func _a_dressed_wound_mends_and_an_open_one_does_not() -> bool:
	var dressed: Variant = _world()
	_hurt(dressed, PART, LACERATION_DAMAGE, true)
	var mended: float = _gained(dressed, PART, WINDOW)

	var open: Variant = _world()
	_hurt(open, PART, LACERATION_DAMAGE, false)
	var untended: float = _gained(open, PART, WINDOW)

	if mended <= 0.0:
		push_error("a dressed laceration regained %.6f over %d ticks" % [mended, WINDOW])
		return false
	if untended != 0.0:
		push_error("an open, bleeding wound regained %.6f -- an open wound must not knit" % untended)
		return false
	print("DRESSED OK dressed +%.4f, still bleeding +%.4f over %d ticks" % [mended, untended, WINDOW])
	return true


# Earned, not elapsed. Same wound, same span, three survivors: one resting and fed, one who
# just exerted, one starving. Only the first mends.
func _recovery_is_earned_not_elapsed() -> bool:
	var rested: Variant = _world()
	_hurt(rested, PART, DEEP_DAMAGE)
	var earned: float = _gained(rested, PART, WINDOW)

	var winded: Variant = _world()
	_hurt(winded, PART, DEEP_DAMAGE)
	# Exertion is re-asserted every tick, the way a survivor who keeps sprinting keeps
	# resetting it. A single stamina.spent would decay away inside the window.
	#
	# The priming step matters: events.publish() only queues, and the handler that sets
	# ticksUntilRecovery runs at the END of a step -- so the first step after the first
	# publish still sees a rested survivor and credits one tick of healing. That one tick is
	# real behaviour, not a bug (you were resting when the tick began), so it is stepped past
	# before measuring rather than tolerated inside the measurement.
	winded.events.publish({"type": "stamina.spent", "entity": winded.player, "amount": 0.01})
	winded.step()
	var before_winded: float = _integrity(winded, PART)
	for _i in WINDOW:
		winded.events.publish({"type": "stamina.spent", "entity": winded.player, "amount": 0.01})
		winded.step()
	var while_working: float = _integrity(winded, PART) - before_winded

	var starving: Variant = _world()
	_hurt(starving, PART, DEEP_DAMAGE)
	starving.components.set_component(starving.player, "needs", {"hunger": 5.0, "thirst": 100.0, "rest": 100.0})
	var while_starving: float = _gained(starving, PART, WINDOW)

	if earned <= 0.0:
		push_error("a fed, resting survivor regained %.6f" % earned)
		return false
	if while_working != 0.0:
		push_error("a survivor exerting every tick regained %.6f" % while_working)
		return false
	if while_starving != 0.0:
		push_error("a starving survivor regained %.6f" % while_starving)
		return false
	print("EARNED OK rested +%.4f, exerting +%.4f, starving +%.4f over %d ticks" % [earned, while_working, while_starving, WINDOW])
	return true


# docs/05's table is the pace, and it is one table: regen_per_tick derives from RECOVERY_DAYS
# rather than being a second set of numbers that can drift from the first.
func _severity_sets_the_pace() -> bool:
	var light: Variant = _world()
	_hurt(light, PART, SCRATCH_DAMAGE)
	var quick: float = _gained(light, PART, WINDOW)

	var heavy: Variant = _world()
	_hurt(heavy, PART, DEEP_DAMAGE)
	var slow: float = _gained(heavy, PART, WINDOW)

	var expected: float = float(SimWounds.RECOVERY_DAYS[SimWounds.Severity.DeepWound]) / float(SimWounds.RECOVERY_DAYS[SimWounds.Severity.Scratch])
	var ratio: float = quick / slow if slow > 0.0 else 0.0
	if slow <= 0.0 or quick <= 0.0:
		push_error("one of the bands did not move at all: scratch %.6f, deep %.6f" % [quick, slow])
		return false
	if absf(ratio - expected) > 0.05 * expected:
		push_error("a scratch mended %.2fx as fast as a deep wound, expected %.2fx from RECOVERY_DAYS" % [ratio, expected])
		return false
	print("PACE OK scratch +%.4f, deep +%.4f, ratio %.2f matches RECOVERY_DAYS %.2f" % [quick, slow, ratio, expected])
	return true


# Zero is a floor, not a stage. A part left with one point climbs; a part left with none is
# gone, and that is what makes permanent loss a real outcome rather than a delay.
func _a_destroyed_part_never_comes_back() -> bool:
	var w: Variant = _world()
	var body: Dictionary = w.components.get_component(w.player, "body") as Dictionary
	body["arm_left"] = 0.0
	body["arm_right"] = 1.0
	var ruined: Dictionary = SimWounds.append_wound(w, w.player, "cut", "arm_left", -1, 20.0)
	ruined["bleeding"] = false
	var barely: Dictionary = SimWounds.append_wound(w, w.player, "cut", "arm_right", -1, 20.0)
	barely["bleeding"] = false

	_run_ticks(w, WINDOW)
	var destroyed: float = float(body["arm_left"])
	var survived: float = float(body["arm_right"])
	if destroyed != 0.0:
		push_error("an arm destroyed to 0 regrew to %.6f" % destroyed)
		return false
	if survived <= 1.0:
		push_error("an arm left at 1 did not climb (%.6f), so the floor above proves nothing" % survived)
		return false
	print("PERMANENCE OK arm at 0 stayed %.4f, arm at 1 rose to %.4f" % [destroyed, survived])
	return true


# The amputation path reaches zero by its own route -- infection.gd writes the part directly
# rather than going through damage -- so it gets its own assertion rather than riding on the
# one above.
func _an_amputated_limb_stays_amputated() -> bool:
	var w: Variant = _world()
	w.components.set_component(w.player, "zombieInfection", {"exposures": [
		{"source": -1, "bodyPart": "leg_left", "exposedAtTick": int(w.tick), "transmitted": true, "stage": SimInfection.Stage.Latent, "stageEnteredAtTick": int(w.tick), "cauterized": false, "amputated": false},
	]})
	var res: Dictionary = SimInfection.amputate(w, w.player, "leg_left")
	if not bool(res.get("ok", false)):
		push_error("could not amputate a fresh exposure: %s" % str(res))
		return false
	var stump: Dictionary = SimWounds.append_wound(w, w.player, "cut", "leg_left", -1, 25.0)
	stump["bleeding"] = false
	_run_ticks(w, WINDOW)
	var leg: float = _integrity(w, "leg_left")
	if leg != 0.0:
		push_error("an amputated leg grew back to %.6f" % leg)
		return false
	# The other leg, untouched by the amputation and carrying its own dressed wound, must
	# still mend -- otherwise this passes because nothing anywhere is healing.
	var right: Dictionary = SimWounds.append_wound(w, w.player, "cut", "leg_right", -1, 20.0)
	right["bleeding"] = false
	(w.components.get_component(w.player, "body") as Dictionary)["leg_right"] = 10.0
	if _gained(w, "leg_right", WINDOW) <= 0.0:
		push_error("the intact leg did not mend either, so the amputation check proves nothing")
		return false
	print("AMPUTATION OK stump stayed %.4f while the intact leg mended" % leg)
	return true


# The wound leaves the list on its own budget. Set up one tick short and one tick over, so
# this cannot pass by closing everything or by closing nothing.
func _a_wound_closes_on_its_budget_and_not_before() -> bool:
	var budget: int = int(SimWounds.RECOVERY_DAYS[SimWounds.Severity.DeepWound]) * SimClock.DAY_TICKS

	var closes: Variant = _world()
	var a: Dictionary = _hurt(closes, PART, DEEP_DAMAGE)
	a["healedTicks"] = budget - 1
	var seen: Array[String] = []
	closes.events.subscribe({"id": "gate.closed", "type": "wound.closed", "handler": func(e: Dictionary) -> void:
		seen.append(String(e.get("bodyPart", "")))
	})
	_run_ticks(closes, 2)
	if not _wounds(closes).is_empty():
		push_error("a wound one tick from its %d-tick budget did not close" % budget)
		return false
	if not seen.has(PART):
		push_error("the wound closed but published no wound.closed: %s" % str(seen))
		return false

	var lingers: Variant = _world()
	var b: Dictionary = _hurt(lingers, PART, DEEP_DAMAGE)
	b["healedTicks"] = budget - 500
	_run_ticks(lingers, 2)
	if _wounds(lingers).size() != 1:
		push_error("a wound 500 ticks short of its budget closed early")
		return false
	print("CLOSURE OK closed at %d earned ticks, still open 500 short" % budget)
	return true


# Closing a wound is what releases its per-part impairment. Asserted as ground actually
# covered, not as a resolve() call -- docs/30:513-524 is the bug this style exists to avoid.
func _closing_a_wound_gives_back_what_it_was_taking() -> bool:
	var budget: int = int(SimWounds.RECOVERY_DAYS[SimWounds.Severity.DeepWound]) * SimClock.DAY_TICKS
	var w: Variant = _world()
	var wound: Dictionary = _hurt(w, "leg_left", 20.0)
	var hurt_distance: float = _walk(w, 100)

	wound["healedTicks"] = budget - 1
	_run_ticks(w, 2)
	if not _wounds(w).is_empty():
		push_error("the leg wound did not close")
		return false
	var healed_distance: float = _walk(w, 100)

	var clean: Variant = _world()
	var baseline: float = _walk(clean, 100)

	if hurt_distance >= baseline:
		push_error("a deep leg wound cost no ground: hurt %.4f vs baseline %.4f" % [hurt_distance, baseline])
		return false
	if absf(healed_distance - baseline) > 0.0001:
		push_error("a closed wound still slowed the leg: healed %.4f vs baseline %.4f" % [healed_distance, baseline])
		return false
	print("IMPAIRMENT OK hurt %.4f, closed %.4f, baseline %.4f" % [hurt_distance, healed_distance, baseline])
	return true


func _walk(w: Variant, ticks: int) -> float:
	var start: float = float((w.components.get_component(w.player, "position") as Dictionary)["x"])
	for _i in ticks:
		w.commands.push({"type": "move", "dx": 1.0, "dy": 0.0})
		w.step()
	return float((w.components.get_component(w.player, "position") as Dictionary)["x"]) - start


# The one decision overwork exists to pose: you are deeply wounded and something is chasing
# you. Deliberately narrow -- only a deep wound, only while fresh, only sprinting -- so the
# three negatives here are as much the specification as the positive is.
func _sprinting_reopens_a_fresh_deep_wound() -> bool:
	var budget: int = int(SimWounds.RECOVERY_DAYS[SimWounds.Severity.DeepWound]) * SimClock.DAY_TICKS

	var torn: Variant = _world()
	var deep: Dictionary = _hurt(torn, PART, DEEP_DAMAGE)
	_sprint(torn)
	_run_ticks(torn, 2)
	if not bool(deep.get("bleeding", false)):
		push_error("sprinting on a fresh deep wound did not reopen it")
		return false
	if String(deep.get("bandage", "")) != "none":
		push_error("a reopened wound kept its dressing: '%s'" % deep.get("bandage", ""))
		return false

	var walking: Variant = _world()
	var kept: Dictionary = _hurt(walking, PART, DEEP_DAMAGE)
	_run_ticks(walking, 2)
	if bool(kept.get("bleeding", true)):
		push_error("a deep wound reopened while merely walking")
		return false

	var mostly: Variant = _world()
	var old: Dictionary = _hurt(mostly, PART, DEEP_DAMAGE)
	old["healedTicks"] = budget / 2
	_sprint(mostly)
	_run_ticks(mostly, 2)
	if bool(old.get("bleeding", true)):
		push_error("a half-healed deep wound reopened -- the freshness window is not being read")
		return false

	var minor: Variant = _world()
	var scratch: Dictionary = _hurt(minor, PART, SCRATCH_DAMAGE)
	_sprint(minor)
	_run_ticks(minor, 2)
	if bool(scratch.get("bleeding", true)):
		push_error("a scratch reopened from sprinting -- only deep wounds should")
		return false
	print("OVERWORK OK fresh deep wound tears open sprinting; walking, half-healed and scratch all hold")
	return true


func _sprint(w: Variant) -> void:
	w.components.set_component(w.player, "posture", {"current": SimStances.Stance.Sprint, "target": SimStances.Stance.Sprint, "ticks_left": 0})


# recruits._make_corpse leaves `injuries` on the body it makes, which is what let a bled-out
# corpse be killed 575 times before Part A guarded it. Recovery has to carry the same guard,
# or a corpse spends the rest of the campaign quietly mending.
func _a_corpse_does_not_convalesce() -> bool:
	var w: Variant = _world()
	_hurt(w, PART, DEEP_DAMAGE)
	w.components.set_component(w.player, "corpse", {"sinceTick": int(w.tick)})
	var dead_gain: float = _gained(w, PART, WINDOW)

	var live: Variant = _world()
	_hurt(live, PART, DEEP_DAMAGE)
	var live_gain: float = _gained(live, PART, WINDOW)

	if dead_gain != 0.0:
		push_error("a corpse regained %.6f integrity" % dead_gain)
		return false
	if live_gain <= 0.0:
		push_error("the living control regained %.6f, so the corpse check proves nothing" % live_gain)
		return false
	print("CORPSE OK corpse +%.4f, living +%.4f" % [dead_gain, live_gain])
	return true


# jobs._treat and the player's channel now end in the same function. Asserted as behaviour:
# it stops the *worst* open wound, not the first one it finds, and it refuses when there is
# nothing bleeding rather than reporting success.
func _one_effect_leaf_serves_both_intakes() -> bool:
	var w: Variant = _world()
	SimWounds.append_wound(w, w.player, "cut", "head", -1, 1.0)
	var deep: Dictionary = SimWounds.append_wound(w, w.player, "cut", PART, -1, DEEP_DAMAGE)
	var res: Dictionary = SimWounds.dress_worst(w, w.player, w.player, "sterile")
	if String(res.get("bodyPart", "")) != PART:
		push_error("dress_worst treated '%s', expected the worse wound on %s" % [res.get("bodyPart", ""), PART])
		return false
	if bool(deep.get("bleeding", true)) or String(deep.get("bandage", "")) != "sterile":
		push_error("dress_worst did not dress the wound it named: %s" % str(deep))
		return false

	var clean: Variant = _world()
	SimHealth.make_survivor_body(clean, clean.player)
	var nothing: Dictionary = SimWounds.dress_worst(clean, clean.player, clean.player)
	if bool(nothing.get("ok", false)) or String(nothing.get("reason", "")) != "not-bleeding":
		push_error("dress_worst on an unwounded survivor returned %s" % str(nothing))
		return false
	print("LEAF OK worst wound dressed (%s), unwounded refused '%s'" % [res.get("bodyPart", ""), nothing.get("reason", "")])
	return true


# Reaching for a private helper on purpose: the bug it fixes is invisible from outside.
# jobs._injured compared raw integrity against a flat `< 30` across parts that do not share a
# scale, so a perfectly healthy head (max 15) and every hand (max 10) were permanently
# "injured" -- every survivor was always a Doctor candidate, which is not a threshold at all.
# It also walked six parts of ten, so a ruined hand was invisible to it.
func _the_doctor_threshold_reads_states_not_numbers() -> bool:
	var well: Variant = _world()
	if SimJobs._injured(well, well.player):
		push_error("a survivor with a full, unwounded body reads as injured -- the flat-threshold bug is back")
		return false

	var hand: Variant = _world()
	(hand.components.get_component(hand.player, "body") as Dictionary)["hand_right"] = 2.0
	if not SimJobs._injured(hand, hand.player):
		push_error("a hand at 2 of 10 does not read as injured -- hands are being skipped again")
		return false

	var head: Variant = _world()
	(head.components.get_component(head.player, "body") as Dictionary)["head"] = 14.0
	if SimJobs._injured(head, head.player):
		push_error("a head at 14 of 15 reads as injured -- raw integrity is being compared again")
		return false
	print("THRESHOLD OK full body not injured, hand at 2/10 injured, head at 14/15 not injured")
	return true


func _deterministic_replay() -> bool:
	var runs: Array[String] = []
	for offset in [0, 0, 13]:
		var w: Variant = _world(313)
		var wound: Dictionary = _hurt(w, PART, DEEP_DAMAGE)
		wound["healedTicks"] = 400
		for i in 400:
			if i == 20 + int(offset):
				w.commands.push({"type": "stance", "stance": 4})
			w.commands.push({"type": "move", "dx": 1.0, "dy": 0.0})
			w.step()
		runs.append(JSON.stringify(w.serialize()))
	if runs[0] != runs[1]:
		push_error("two identical runs serialised differently")
		return false
	if runs[0] == runs[2]:
		push_error("moving the sprint 13 ticks changed nothing, so the comparison proves nothing")
		return false
	print("DETERMINISM OK identical runs match, a 13-tick shift does not")
	return true
