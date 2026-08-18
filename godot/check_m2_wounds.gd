extends SceneTree
# Wounds that bleed: severity, the blood-loss clock, and the impairment it causes.
#
# Guards Slice 2 Part A. Before this, `injuries.wounds` was an append-only list of records
# with no mechanical consequence anywhere except `bloater.gd:85`, which only asked whether
# one existed. condition.gd:59 said so in its own comment. A wound cost nothing, healed
# nothing, and impaired nothing.
#
# Two things this gate exists to hold down, both of them traps CLAUDE.md records by name:
#
#  1. **Severity is a fraction of the struck part, never raw damage.** A healthy head is 15,
#     a hand 10, a torso 40, so ten damage is a quarter of a torso and the whole of a hand.
#     `_severity_reads_the_part_not_the_number` drives identical damage into two parts and
#     demands two different bands. If that assertion ever goes green by accident, severity
#     has started reading the number again.
#
#  2. **Assert the effect, never the mechanism.** docs/30-decisions.md:513-524 records
#     `move_speed` sitting with no reader for months while `inventory.test.ts` passed the
#     whole time, because it asserted `resolve("move_speed")` came back lower rather than
#     asserting anything actually moved. So every impairment assertion here integrates
#     positions over N ticks and compares ground covered. None of them calls resolve().
#     `check_m2_stats.gd:93 _dex_speeds_walk` is the in-repo example being followed.
#
# Every assertion carries a true negative beside its positive. A gate that cannot fail is
# worse than no gate.
#
# If this goes red: read the assertion's evidence line before loosening it. The bleed rates
# and severity bands live in sim/modules/wounds.gd and are the thing to change if balance is
# wrong -- not the bands this gate asserts, which are the contract.

const World = preload("res://sim/world.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimCombat = preload("res://sim/combat.gd")
const SimCondition = preload("res://sim/condition.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _severity_reads_the_part_not_the_number() and ok
	ok = _armor_lowers_the_band_at_equal_damage() and ok
	ok = _a_damaging_hit_records_one_wound_and_a_harmless_one_records_none() and ok
	ok = _a_zombie_body_never_grows_an_injuries_component() and ok
	ok = _an_untreated_bleed_kills_and_a_scratch_clots() and ok
	ok = _blood_loss_slows_the_body_it_is_draining() and ok
	ok = _a_leg_wound_slows_and_an_arm_wound_does_not() and ok
	ok = _impairment_clears_when_its_cause_does() and ok
	ok = _bleeding_out_kills_exactly_once() and ok
	ok = _a_bled_out_corpse_is_never_killed_again() and ok
	ok = _the_view_says_bleeding_as_a_word() and ok
	ok = _deterministic_replay() and ok
	if ok:
		print("M2_WOUNDS_OK severity is a fraction, bleeding is a clock, impairment moves a body")
		quit(0)
	else:
		push_error("M2_WOUNDS_FAIL")
		quit(1)


# A bare fixture world with the modules the wound path needs. No SimBoot.attach_kernel, for
# the reason check_m2_contact.gd records: it keeps SimBoot._KERNEL_WORLD's single-world
# constraint out of a gate that builds a fresh world per assertion.
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


# world.step() ends with events.drain() -- publish() only *queues*. So a hit needs a tick to
# actually reach health.gd's subscriber and become a wound. Stepping here rather than in each
# caller keeps that fact in one place; it cost a confusing "0 wounds from 2 hits" first.
func _hit(w: Variant, part: String, damage: float) -> void:
	w.events.publish({"type": "attack.connected", "attacker": -1, "target": w.player, "bodyPart": part, "damage": damage})
	w.step()


func _wounds_of(w: Variant, entity: int) -> Array:
	var inj: Variant = w.components.get_component(entity, "injuries")
	if not (inj is Dictionary):
		return []
	return (inj as Dictionary).get("wounds", []) as Array


func _blood_loss(w: Variant, entity: int) -> float:
	var inj: Variant = w.components.get_component(entity, "injuries")
	if not (inj is Dictionary):
		return 0.0
	return float((inj as Dictionary).get("bloodLoss", 0.0))


func _set_blood_loss(w: Variant, entity: int, value: float) -> void:
	var inj: Dictionary = w.components.get_component(entity, "injuries") as Dictionary
	inj["bloodLoss"] = value


# Walk east under a "move" command for `ticks` and report the ground actually covered. This
# is the shape every impairment assertion below uses -- distance integrated by the real
# movement system, never a resolve() call. See the header.
func _distance_walked(w: Variant, ticks: int) -> float:
	var start: float = float((w.components.get_component(w.player, "position") as Dictionary)["x"])
	for _i in ticks:
		w.commands.push({"type": "move", "dx": 1.0, "dy": 0.0})
		w.step()
	var end_x: float = float((w.components.get_component(w.player, "position") as Dictionary)["x"])
	return end_x - start


# ---------------------------------------------------------------------------------------
# 1. The trap, asserted directly. Identical damage, two parts, two bands -- because the only
#    thing severity is allowed to read is damage / SimHealth.max_of(body, part).
func _severity_reads_the_part_not_the_number() -> bool:
	# torso max 40, hand max 10. Ten damage is a quarter of one and the whole of the other.
	var w: Variant = _world(101)
	_hit(w, "torso", 10.0)
	_hit(w, "hand_left", 10.0)
	var wounds: Array = _wounds_of(w, w.player)
	if wounds.size() != 2:
		push_error("expected 2 wounds from 2 hits, got %d" % wounds.size())
		return false
	var torso_sev: int = int((wounds[0] as Dictionary).get("severity", -1))
	var hand_sev: int = int((wounds[1] as Dictionary).get("severity", -1))
	if torso_sev >= hand_sev:
		push_error("10 damage should band lower on a torso (40) than a hand (10): torso=%d hand=%d" % [torso_sev, hand_sev])
		return false
	if torso_sev != SimWounds.Severity.Laceration:
		push_error("10/40 = 0.25 should be a Laceration, got %d" % torso_sev)
		return false
	if hand_sev != SimWounds.Severity.DeepWound:
		push_error("10/10 = 1.00 should be a DeepWound, got %d" % hand_sev)
		return false

	# The true negative for the band edges: a small hit is a scratch on a torso and still a
	# laceration on a hand. If severity ever reverts to reading raw damage, these collapse to
	# the same band and this fails.
	var w2: Variant = _world(102)
	_hit(w2, "torso", 3.0)
	_hit(w2, "hand_left", 3.0)
	var w2s: Array = _wounds_of(w2, w2.player)
	if w2s.size() != 2:
		push_error("expected 2 wounds from 2 small hits, got %d" % w2s.size())
		return false
	var t2: int = int((w2s[0] as Dictionary).get("severity", -1))
	var h2: int = int((w2s[1] as Dictionary).get("severity", -1))
	if t2 != SimWounds.Severity.Scratch or h2 != SimWounds.Severity.Laceration:
		push_error("3 damage: torso should be Scratch and hand Laceration, got torso=%d hand=%d" % [t2, h2])
		return false
	print("SEVERITY OK 10dmg torso=%d hand=%d; 3dmg torso=%d hand=%d" % [torso_sev, hand_sev, t2, h2])
	return true


# 2. Armour buys a lower band at the same damage -- docs/06's whole argument for armour is
#    that it reduces what a hit becomes, not how much it hurts.
func _armor_lowers_the_band_at_equal_damage() -> bool:
	# item.vest.scrap covers torso 0.6 and leaves foot_right at 0.0. 18 damage on a 40 torso
	# is 0.45 bare -- a DeepWound -- and lands a band lower once coverage scales it.
	var bare: Variant = _world(103)
	_hit(bare, "torso", 18.0)
	var bare_sev: int = int((_wounds_of(bare, bare.player)[0] as Dictionary).get("severity", -1))

	var armored: Variant = _world(103)
	var vest: int = SimItems.spawn_item(armored, "item.vest.scrap", {"tier": "scavenged"})
	if not SimInventory.equip(armored, armored.player, vest, "vest"):
		push_error("could not equip item.vest.scrap")
		return false
	_hit(armored, "torso", 18.0)
	var armored_sev: int = int((_wounds_of(armored, armored.player)[0] as Dictionary).get("severity", -1))

	if armored_sev >= bare_sev:
		push_error("a covered torso should band lower at equal damage: bare=%d armored=%d" % [bare_sev, armored_sev])
		return false

	# True negative: the vest does not cover a foot, so the same comparison there must find
	# no difference at all. Without this, "armour lowers everything" would pass.
	var bare_foot: Variant = _world(104)
	_hit(bare_foot, "foot_right", 4.0)
	var bf: int = int((_wounds_of(bare_foot, bare_foot.player)[0] as Dictionary).get("severity", -1))
	var armored_foot: Variant = _world(104)
	var vest2: int = SimItems.spawn_item(armored_foot, "item.vest.scrap", {"tier": "scavenged"})
	SimInventory.equip(armored_foot, armored_foot.player, vest2, "vest")
	_hit(armored_foot, "foot_right", 4.0)
	var af: int = int((_wounds_of(armored_foot, armored_foot.player)[0] as Dictionary).get("severity", -1))
	if af != bf:
		push_error("a vest covers no foot; band should be unchanged: bare=%d armored=%d" % [bf, af])
		return false
	print("ARMOR OK torso bare=%d armored=%d; uncovered foot unchanged at %d" % [bare_sev, armored_sev, bf])
	return true


# 3. One hit, one wound -- and a hit that takes nothing off leaves no record. The negative
#    matters: an intake that appends unconditionally would pass the positive alone.
func _a_damaging_hit_records_one_wound_and_a_harmless_one_records_none() -> bool:
	var w: Variant = _world(105)
	_hit(w, "arm_left", 6.0)
	if _wounds_of(w, w.player).size() != 1:
		push_error("one damaging hit should record exactly one wound, got %d" % _wounds_of(w, w.player).size())
		return false
	var wound: Dictionary = _wounds_of(w, w.player)[0] as Dictionary
	if String(wound.get("bodyPart", "")) != "arm_left":
		push_error("wound landed on '%s', expected arm_left" % wound.get("bodyPart", ""))
		return false
	if not SimCombat.SURVIVOR_BODY_PARTS.has(String(wound.get("bodyPart", ""))):
		push_error("wound part is not a canonical survivor part: %s" % wound.get("bodyPart", ""))
		return false

	var clean: Variant = _world(106)
	_hit(clean, "arm_left", 0.0)
	if _wounds_of(clean, clean.player).size() != 0:
		push_error("a zero-damage hit should record no wound, got %d" % _wounds_of(clean, clean.player).size())
		return false

	# And a part already at zero cannot be wounded again -- damage_part returns null there.
	var ruined: Variant = _world(107)
	var body: Dictionary = ruined.components.get_component(ruined.player, "body") as Dictionary
	body["hand_left"] = 0.0
	_hit(ruined, "hand_left", 5.0)
	if _wounds_of(ruined, ruined.player).size() != 0:
		push_error("a destroyed part should record no further wound, got %d" % _wounds_of(ruined, ruined.player).size())
		return false
	print("INTAKE OK 1 hit -> 1 wound on arm_left; 0 damage -> 0; ruined part -> 0")
	return true


# 4. Zombies have no injuries component and must never grow one -- their body table is a
#    different shape and every wound reader assumes a survivor.
func _a_zombie_body_never_grows_an_injuries_component() -> bool:
	var w: Variant = _world(108)
	var zed: int = w.entities.spawn()
	w.components.set_component(zed, "body", SimCombat.ZOMBIE_BODY.duplicate())
	w.components.set_component(zed, "position", {"x": 6.0, "y": 16.5})
	w.events.publish({"type": "attack.connected", "attacker": w.player, "target": zed, "bodyPart": "torso", "damage": 5.0})
	w.step()
	if w.components.get_component(zed, "injuries") != null:
		push_error("a zombie grew an injuries component from a hit")
		return false
	# True positive beside it: the same event shape on the survivor does record one, so this
	# is not passing merely because the handler is broken for everyone.
	_hit(w, "torso", 5.0)
	if _wounds_of(w, w.player).size() != 1:
		push_error("the survivor should still record a wound from the same event shape")
		return false
	print("SCOPE OK zombie has no injuries, survivor recorded 1 from the same event")
	return true


# 5. Bleeding is the acute killer docs/05 says it is -- and a scratch clots on its own.
func _an_untreated_bleed_kills_and_a_scratch_clots() -> bool:
	# Death is detected from entity.killed, not by reading bloodLoss back. The reaper runs in
	# the "cleanup" phase of the same tick that crosses the threshold, and in this fixture the
	# player has no successor, so recruits.handle_death despawns it -- by the time step()
	# returns there is no injuries component left to read and the accumulator reads 0.0.
	var deep: Variant = _world(109)
	# An Array, not an int. GDScript lambdas capture primitives BY VALUE, so `died_at = ...`
	# inside the handler would assign to the closure's own copy and the outer variable would
	# stay -1 forever -- the same family as CLAUDE.md's packed-array trap, and it cost a
	# "never bled out (peak loss 100.00)" before it was spotted. Reference types mutate.
	var deaths: Array[int] = []
	deep.events.subscribe({"id": "gate.bleed-death", "type": "entity.killed", "handler": func(event: Dictionary) -> void:
		if int(event["entity"]) == int(deep.player):
			deaths.append(int(event.get("tick", -1)))
	})
	_hit(deep, "torso", 20.0) # 0.50 of a torso -> DeepWound, the fastest bleed
	var deep_sev: int = int((_wounds_of(deep, deep.player)[0] as Dictionary).get("severity", -1))
	if deep_sev != SimWounds.Severity.DeepWound:
		push_error("20/40 = 0.50 should be a DeepWound, got %d" % deep_sev)
		return false
	var peak_loss: float = 0.0
	var died_at: int = -1
	for i in 20000:
		deep.step()
		peak_loss = maxf(peak_loss, _blood_loss(deep, deep.player))
		if not deaths.is_empty():
			died_at = i + 1
			break
	if died_at < 0:
		push_error("an untreated deep wound never bled out in 20000 ticks (peak loss %.2f)" % peak_loss)
		return false

	# The true negative: a scratch clots, and over the same span it neither kills nor comes
	# anywhere near the threshold.
	var scratch: Variant = _world(110)
	var scratch_deaths: Array[int] = []
	scratch.events.subscribe({"id": "gate.scratch-death", "type": "entity.killed", "handler": func(event: Dictionary) -> void:
		if int(event["entity"]) == int(scratch.player):
			scratch_deaths.append(1)
	})
	_hit(scratch, "torso", 3.0) # 0.075 of a torso -> Scratch
	if int((_wounds_of(scratch, scratch.player)[0] as Dictionary).get("severity", -1)) != SimWounds.Severity.Scratch:
		push_error("3/40 = 0.075 should be a Scratch")
		return false
	for _i in died_at + 1:
		scratch.step()
	if not scratch_deaths.is_empty():
		push_error("a scratch bled the survivor out in the span a deep wound needed")
		return false
	var scratch_loss: float = _blood_loss(scratch, scratch.player)
	if scratch_loss >= SimWounds.BLOOD_LOSS_FATAL:
		push_error("a scratch should clot, not bleed out: %.2f" % scratch_loss)
		return false
	if scratch_loss <= 0.0:
		push_error("a scratch should bleed a little before it clots, got %.2f" % scratch_loss)
		return false
	if bool((_wounds_of(scratch, scratch.player)[0] as Dictionary).get("bleeding", true)):
		push_error("a scratch should have stopped bleeding after %d ticks" % died_at)
		return false
	print("BLEED OK deep wound bled out at tick %d; scratch clotted at %.2f loss and lived" % [died_at, scratch_loss])
	return true


# 6. Effect, not mechanism: a draining body covers less ground.
func _blood_loss_slows_the_body_it_is_draining() -> bool:
	var healthy: Variant = _world(111)
	var d_healthy: float = _distance_walked(healthy, 40)

	var drained: Variant = _world(111)
	_set_blood_loss(drained, drained.player, SimWounds.BLOOD_LOSS_FATAL * 0.8)
	var d_drained: float = _distance_walked(drained, 40)

	if d_drained >= d_healthy:
		push_error("heavy blood loss should slow a walk: healthy=%.3f drained=%.3f" % [d_healthy, d_drained])
		return false
	# True negative: a trace of blood loss, below the first band, must change nothing at all.
	var trace: Variant = _world(111)
	_set_blood_loss(trace, trace.player, SimWounds.BLOOD_LOSS_FATAL * 0.05)
	var d_trace: float = _distance_walked(trace, 40)
	if absf(d_trace - d_healthy) > 0.0001:
		push_error("blood loss below the first band should change nothing: healthy=%.4f trace=%.4f" % [d_healthy, d_trace])
		return false
	print("BLOODLOSS OK walked healthy=%.3f trace=%.3f drained=%.3f" % [d_healthy, d_trace, d_drained])
	return true


# 7. The limb that is hurt is the limb that matters -- a leg slows a walk, an arm does not.
#    This is what per-part modifier sources buy, and it is the whole argument for not using
#    one shared source string.
func _a_leg_wound_slows_and_an_arm_wound_does_not() -> bool:
	var clean: Variant = _world(112)
	var d_clean: float = _distance_walked(clean, 40)

	var legged: Variant = _world(112)
	_hit(legged, "leg_left", 12.0) # 12/25 = 0.48 -> DeepWound
	var d_leg: float = _distance_walked(legged, 40)

	var armed: Variant = _world(112)
	_hit(armed, "arm_left", 10.0) # 10/20 = 0.50 -> DeepWound, same band, different limb
	var d_arm: float = _distance_walked(armed, 40)

	if d_leg >= d_clean:
		push_error("a deep leg wound should slow a walk: clean=%.3f leg=%.3f" % [d_clean, d_leg])
		return false
	if absf(d_arm - d_clean) > 0.0001:
		push_error("an arm wound should not slow a walk: clean=%.4f arm=%.4f" % [d_clean, d_arm])
		return false
	print("LIMB OK walked clean=%.3f leg=%.3f arm=%.3f" % [d_clean, d_leg, d_arm])
	return true


# 8. The strip-then-return bug, asserted. melee.gd:166 _apply_exhaustion removes its source
#    unconditionally *before* the neutral early-return; reversing those two is what makes a
#    penalty stick forever after its cause is gone. Prove it clears.
func _impairment_clears_when_its_cause_does() -> bool:
	var w: Variant = _world(113)
	_set_blood_loss(w, w.player, SimWounds.BLOOD_LOSS_FATAL * 0.8)
	var d_hurt: float = _distance_walked(w, 40)
	_set_blood_loss(w, w.player, 0.0)
	var d_recovered: float = _distance_walked(w, 40)
	if d_recovered <= d_hurt:
		push_error("clearing blood loss should restore the walk: hurt=%.3f recovered=%.3f" % [d_hurt, d_recovered])
		return false

	var never_hurt: Variant = _world(113)
	var d_baseline: float = _distance_walked(never_hurt, 40)
	# The recovered walk is allowed to fall short by at most ONE tick's worth, and no more.
	# That lag is real and structural, not slop: "movement" is an earlier phase than "health",
	# so the tick on which blood loss is cleared still integrates against the modifier that
	# wounds.bleed strips later in the same tick. Tolerating exactly one tick keeps the
	# assertion sharp -- a modifier that never cleared leaves d_recovered down at d_hurt,
	# which is ~50% short, not 2.5%.
	var one_tick: float = d_baseline / 40.0
	var shortfall: float = d_baseline - d_recovered
	if shortfall > one_tick * 1.01:
		push_error("a recovered body should walk within one tick of baseline: recovered=%.4f baseline=%.4f shortfall=%.4f one_tick=%.4f" % [d_recovered, d_baseline, shortfall, one_tick])
		return false
	if shortfall < 0.0:
		push_error("a recovered body outwalked one that was never hurt: recovered=%.4f baseline=%.4f" % [d_recovered, d_baseline])
		return false
	print("CLEAR OK hurt=%.3f recovered=%.3f baseline=%.3f (shortfall %.4f = %.2f ticks)" % [d_hurt, d_recovered, d_baseline, shortfall, shortfall / one_tick])
	return true


# 9. entity.killed already fires up to three times for one individual (CLAUDE.md). A new
#    death path is exactly where that gets worse, so count them.
func _bleeding_out_kills_exactly_once() -> bool:
	var w: Variant = _world(114)
	var deaths: Array[int] = []
	w.events.subscribe({"id": "gate.count-deaths", "type": "entity.killed", "handler": func(event: Dictionary) -> void:
		deaths.append(int(event["entity"]))
	})
	_hit(w, "torso", 20.0)
	_set_blood_loss(w, w.player, SimWounds.BLOOD_LOSS_FATAL - 0.5)
	for _i in 400:
		w.step()
	var mine: int = 0
	for d in deaths:
		if d == w.player:
			mine += 1
	if mine == 0:
		push_error("bleeding past the fatal threshold published no entity.killed (loss=%.2f)" % _blood_loss(w, w.player))
		return false
	if mine != 1:
		push_error("bleeding out published entity.killed %d times for one survivor" % mine)
		return false

	# True negative: a survivor short of the threshold over the same span dies not at all.
	var alive: Variant = _world(115)
	var alive_deaths: Array[int] = []
	alive.events.subscribe({"id": "gate.count-deaths", "type": "entity.killed", "handler": func(event: Dictionary) -> void:
		alive_deaths.append(int(event["entity"]))
	})
	_hit(alive, "torso", 3.0)
	for _i in 400:
		alive.step()
	if alive_deaths.has(alive.player):
		push_error("a scratch killed the survivor in 400 ticks")
		return false
	print("REAP OK bled out once (%d event), the scratched survivor lived" % mine)
	return true


# 9b. The corpse path, which the bare fixture above does NOT reach and which is where this
#     actually broke. recruits.handle_death sends a body with an `identity` through
#     _make_corpse, and _make_corpse removes needs/job/velocity and leaves `injuries` in
#     place -- so the corpse stays in the wounds.bleed query at BLOOD_LOSS_FATAL forever.
#     The per-tick `killed` guard cannot stop that, because the reaper clears it every tick.
#     Without the durable bledOut flag this assertion sees hundreds of deaths, not one.
#
#     The player in the bare fixture despawns instead (no successor -> run over), which is
#     exactly why that assertion passed while the real path was broken. Both are kept.
func _a_bled_out_corpse_is_never_killed_again() -> bool:
	var w: Variant = _world(119)
	var npc: int = w.entities.spawn()
	w.components.set_component(npc, "position", {"x": 8.0, "y": 16.5})
	w.components.set_component(npc, "identity", {"name": "Test Survivor", "unique": false})
	SimHealth.make_survivor_body(w, npc)
	var deaths: Array[int] = []
	w.events.subscribe({"id": "gate.count-corpse-deaths", "type": "entity.killed", "handler": func(event: Dictionary) -> void:
		deaths.append(int(event["entity"]))
	})
	w.events.publish({"type": "attack.connected", "attacker": -1, "target": npc, "bodyPart": "torso", "damage": 20.0})
	w.step()
	var inj: Dictionary = w.components.get_component(npc, "injuries") as Dictionary
	inj["bloodLoss"] = SimWounds.BLOOD_LOSS_FATAL - 0.5
	for _i in 600:
		w.step()

	var mine: int = 0
	for d in deaths:
		if d == npc:
			mine += 1
	# This assertion is only meaningful if the body actually took the corpse branch. If it
	# despawned instead, we are re-testing the previous assertion and must say so rather than
	# passing quietly -- CLAUDE.md: a gate with no data to judge must skip loudly.
	var became_corpse: bool = w.components.has_component(npc, "corpse")
	if not became_corpse:
		push_error("SETUP BROKEN: the NPC did not become a corpse, so the re-kill path was never exercised (deaths=%d)" % mine)
		return false
	if mine != 1:
		push_error("a bled-out corpse published entity.killed %d times over 600 ticks; expected exactly 1" % mine)
		return false
	print("CORPSE OK bled out once over 600 ticks and stayed dead (corpse=%s)" % became_corpse)
	return true


# 10. The view gains one word and no number. The ban gate owns the leak scan; this owns the
#     true positive and the true negative on the new field.
func _the_view_says_bleeding_as_a_word() -> bool:
	var w: Variant = _world(116)
	_hit(w, "leg_left", 12.0)
	var by_part: Dictionary = {}
	for entry in SimCondition.view(w, w.player)["parts"] as Array:
		by_part[String((entry as Dictionary)["part"])] = entry
	if not (by_part["leg_left"].get("bleeding") is bool):
		push_error("leg_left.bleeding is not a bool: %s" % by_part["leg_left"].get("bleeding"))
		return false
	if not bool(by_part["leg_left"].get("bleeding", false)):
		push_error("leg_left carries a bleeding wound but bleeding=false")
		return false
	if bool(by_part["arm_right"].get("bleeding", true)):
		push_error("arm_right is untouched but bleeding=true")
		return false

	# A clotted wound reads as not bleeding -- the field tracks the wound's current state,
	# not merely that a wound was once recorded here. Without this it would be `wounded`
	# under a second name.
	var clotted: Variant = _world(117)
	_hit(clotted, "foot_left", 1.0) # a scratch, which clots
	for _i in int(SimWounds.CLOT_TICKS[SimWounds.Severity.Scratch]) + 2:
		clotted.step()
	var foot: Dictionary = {}
	for entry in SimCondition.view(clotted, clotted.player)["parts"] as Array:
		if String((entry as Dictionary)["part"]) == "foot_left":
			foot = entry as Dictionary
	if bool(foot.get("bleeding", true)):
		push_error("a clotted scratch should read bleeding=false")
		return false
	if not bool(foot.get("wounded", false)):
		push_error("a clotted scratch is still a recorded wound; wounded should stay true")
		return false
	print("VIEW OK bleeding leg=true, clean arm=false, clotted foot=false but wounded=true")
	return true


# 11. Same inputs, same world. Different inputs, different world. The negative uses a
#     different damage rather than a different seed on purpose: severity is deterministic
#     from damage/max/coverage with no RNG in it, so a seed change is not guaranteed to move
#     anything here and would be a negative that cannot fail.
func _deterministic_replay() -> bool:
	var a: Variant = _world(118)
	var b: Variant = _world(118)
	for w in [a, b]:
		_hit(w, "torso", 14.0)
		_hit(w, "leg_right", 9.0)
		for _i in 300:
			w.step()
	var sa: String = String(a.serialize())
	var sb: String = String(b.serialize())
	if sa != sb:
		push_error("identical runs diverged (%d vs %d chars)" % [sa.length(), sb.length()])
		return false

	var c: Variant = _world(118)
	_hit(c, "torso", 26.0)
	_hit(c, "leg_right", 9.0)
	for _i in 300:
		c.step()
	if String(c.serialize()) == sa:
		push_error("a heavier hit produced a byte-identical world; nothing is recording severity")
		return false
	print("DETERMINISM OK identical runs match (%d chars), a heavier hit diverges" % sa.length())
	return true
