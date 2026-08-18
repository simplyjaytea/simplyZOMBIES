extends SceneTree
# Contact: the grab -> struggle -> bite loop, and the fact that a zombie can hurt you at all.
#
# Guards Part B of the "Make harm real" slice. Before this, `grab.started` and `bite.landed`
# had five subscribers between them (melee.gd, ranged.gd, fortify.gd, needs.gd, infection.gd)
# and **zero publishers** anywhere in godot/sim/ -- shambler.gd:5 said the sub-systems were
# omitted "when combat R3 lands" and they never landed. The `grabbed` component was read in
# five places and written in none, so `F`-as-struggle was a legend line that could not fire
# and no zombie could produce a wound. Everything downstream of a bite -- the located wound,
# the presentation lie, armour reducing transmission, the paperdoll's wound ring -- was
# unreachable in normal play.
#
# This gate is the mechanical proof that contact now closes into a hold, that a hold bites on
# a cadence, and that a survivor can buy their way out of it with stamina. Every assertion
# carries a true negative beside its positive, per CLAUDE.md: a gate that cannot fail is worse
# than no gate.
#
# If this goes red: re-read Part B of the plan before loosening an assertion. In particular the
# escape assertion deliberately runs many seeds and demands **both** outcomes appear -- a run
# that only ever escapes, or only ever fails, is not evidence that a contest is happening, and
# CLAUDE.md records a four-seed harness that proved exactly one.

const World = preload("res://sim/world.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimCombat = preload("res://sim/combat.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const SimStances = preload("res://sim/stances.gd")
const SimTreatment = preload("res://sim/modules/treatment.gd")
const SimLocomotion = preload("res://sim/locomotion.gd")
const SimRecruits = preload("res://sim/modules/recruits.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# Grabs ship off by default (SimShambler.GRABS_ENABLED) -- see that constant for the five
	# reasons, in order, and which of them are answered. Switched on here for the whole gate, so
	# every assertion below exercises the real loop rather than the shipped default. When the
	# default flips this line becomes a no-op and nothing here changes.
	SimShambler.GRABS_ENABLED = true
	var ok: bool = true
	ok = _grab_forms_in_reach_but_not_at_distance() and ok
	ok = _a_wall_between_blocks_the_grab() and ok
	ok = _a_hold_bites_on_cadence_and_only_its_victim() and ok
	ok = _every_bite_records_one_located_wound() and ok
	ok = _a_held_bite_aims_where_the_hands_are() and ok
	ok = _a_bite_scales_to_the_part_it_lands_on() and ok
	ok = _struggling_frees_sometimes_and_never_while_spent() and ok
	ok = _instinct_answers_a_grab_nobody_else_will() and ok
	ok = _somebody_else_can_pull_you_out() and ok
	ok = _every_ended_hold_says_why() and ok
	ok = _a_held_body_gets_its_breath_back() and ok
	ok = _release_arms_the_regrab_cooldown() and ok
	ok = _an_escape_opens_a_gap_the_cooldown_cannot_close() and ok
	ok = _the_dead_are_not_worth_chasing() and ok
	ok = _a_held_survivor_can_answer_their_own_bleeding() and ok
	ok = _struggling_and_pressing_are_not_the_same_hand() and ok
	ok = _a_press_outlives_the_hold_that_started_it() and ok
	ok = _first_aid_waits_until_the_running_is_done() and ok
	ok = _a_held_survivor_cannot_swing_or_fire() and ok
	ok = _deterministic_replay() and ok
	ok = _the_flag_actually_gates_acquisition() and ok
	if ok:
		print("M2_CONTACT_OK grabs form, bite on cadence, wounds land, struggle is a contest and an instinct, rescue is another and a held body gets its breath back")
		quit(0)
	else:
		push_error("M2_CONTACT_FAIL")
		quit(1)


# A bare fixture world with the two modules the loop actually needs. No SimBoot.attach_kernel:
# World._init already builds a field and map_cells from the fixture (world.gd:88), and a plain
# shambler never has an `observer`, so _lean_to_light returns before it would touch world.light.
# Staying off attach_kernel also keeps SimBoot._KERNEL_WORLD's single-world constraint out of a
# gate that builds a fresh world per assertion.
func _world(seed_val: int, walls: Array = []) -> Variant:
	var fixture: Dictionary = {
		"seed": seed_val,
		"tick_hz": 20,
		"map": {"width": 32, "height": 32, "walls": walls},
		"player": {"id": 0, "x": 16.5, "y": 16.5, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	}
	var w: Variant = World.new(fixture)
	SimHealth.register_module(w)
	SimShambler.register_module(w, null)
	SimHealth.make_survivor_body(w, w.player)
	SimHealth.make_stamina(w, w.player, 100)
	return w


# The same fixture with the wound and treatment modules attached, for the arbitration assertions
# -- the four rules where a hold and a channel meet. Kept as a second builder rather than folded
# into `_world` so that every assertion above it stays a measurement of the hold loop alone, with
# nothing else registered that could suppress a bleed or pin a body.
func _world_with_treatment(seed_val: int) -> Variant:
	var w: Variant = _world(seed_val)
	SimWounds.register_module(w)
	SimTreatment.register_module(w)
	return w


# A survivor who is not the player: `identity` is what _gather_survivors looks for, and not being
# `controlled` is what makes treatment.self-aid and the NPC struggle intake answer for them. The
# player stays where `_world` put them, 11 m away and out of every radius here.
func _spawn_npc(w: Variant, x: float, y: float) -> int:
	var ent: int = int(w.entities.spawn())
	w.components.set_component(ent, "position", {"x": x, "y": y})
	w.components.set_component(ent, "velocity", {"dx": 0.0, "dy": 0.0})
	w.components.set_component(ent, "facing", {"radians": 0.0})
	w.components.set_component(ent, "identity", {"name": "Test", "traits": []})
	SimHealth.make_survivor_body(w, ent)
	SimHealth.make_stamina(w, ent, 100)
	return ent


func _distance(w: Variant, a: int, b: int) -> float:
	var pa: Dictionary = w.components.get_component(a, "position") as Dictionary
	var pb: Dictionary = w.components.get_component(b, "position") as Dictionary
	var dx: float = float(pb["x"]) - float(pa["x"])
	var dy: float = float(pb["y"]) - float(pa["y"])
	return sqrt(dx * dx + dy * dy)


# Stops the bite clock without stopping the hold, so an assertion whose subject is a channel is
# not also measuring wounds arriving. A very large ticksUntilBite is the honest way to do it --
# nothing is disabled, the clock simply does not come due inside the window.
func _pin_the_bite_clock(w: Variant, source: int) -> void:
	var hold: Variant = w.components.get_component(source, "grabState")
	if hold is Dictionary:
		(hold as Dictionary)["ticksUntilBite"] = 1000000


func _deep_wound(w: Variant, entity: int) -> void:
	SimWounds.append_wound(w, entity, "cut", "torso", -1, 20.0)


func _blood(w: Variant, entity: int) -> float:
	var inj: Variant = w.components.get_component(entity, "injuries")
	if not (inj is Dictionary):
		return 0.0
	return float((inj as Dictionary).get("bloodLoss", 0.0))


func _still_bleeding(w: Variant, entity: int) -> bool:
	var inj: Variant = w.components.get_component(entity, "injuries")
	if not (inj is Dictionary):
		return false
	for wound in (inj as Dictionary).get("wounds", []) as Array:
		if bool((wound as Dictionary).get("bleeding", false)):
			return true
	return false


# Spawned by hand rather than through SimRoster.spawn_zombie, which wants a loaded content
# registry. make_shambler falls back to DEFAULT_GRAB_STRENGTH and canGrab=true with no content
# entry (shambler.gd:105 _grab_of), which is exactly the default this gate wants to exercise.
#
# `grip` overrides grabStrength for the assertions whose subject is a clock rather than the
# escape contest: escape_chance is power/(power+strength), so a grip of 999 makes the hold hold
# and lets a timing measurement be about timing. Whether an escape ever succeeds is
# `_struggling_frees_sometimes_and_never_while_spent`'s claim, and it uses the real default.
func _spawn_shambler(w: Variant, x: float, y: float, grip: float = -1.0) -> int:
	var ent: int = int(w.entities.spawn())
	w.components.set_component(ent, "position", {"x": x, "y": y})
	w.components.set_component(ent, "velocity", {"dx": 0.0, "dy": 0.0})
	w.components.set_component(ent, "facing", {"radians": 0.0})
	w.components.set_component(ent, "body", SimCombat.ZOMBIE_BODY.duplicate())
	SimShambler.make_shambler(w, ent, w.rng.stream("shambler"))
	if grip >= 0.0:
		(w.components.get_component(ent, "shambler") as Dictionary)["grabStrength"] = grip
	return ent


# Silences every struggle intake -- F, instinct and an NPC's -- for the assertions about what a
# hold *does* to somebody who does not get out of it. Since instinct landed, a full-stamina
# survivor tears free partway through a bite cadence, which is correct play and useless
# measurement: it would turn "a bite every REPEAT_BITE_TICKS" into "a bite, then an escape".
# Unregistering says which half of the loop is under test rather than leaving the other half to
# spoil the sample, and check_m2_harness.gd's `_nothing_personal` is the precedent.
func _no_struggling(w: Variant) -> void:
	if not w.systems.unregister("shambler.struggle-intake"):
		push_error("shambler.struggle-intake was not registered -- this gate is silencing nothing")


# A vertical wall column, inclusive of both ends -- long enough that a ray cannot slip past it.
func _column(x: int, y0: int, y1: int) -> Array:
	var out: Array = []
	for y in range(y0, y1 + 1):
		out.append({"x": x, "y": y})
	return out


func _held(w: Variant) -> bool:
	return w.components.has_component(w.player, "grabbed")


func _step_until_held(w: Variant, limit: int) -> int:
	for i in limit:
		w.step()
		if _held(w):
			return i + 1
	return -1


func _bites_in_last_tick(w: Variant) -> int:
	var n: int = 0
	for e in w.events.drained:
		if String((e as Dictionary).get("type", "")) == "bite.landed":
			n += 1
	return n


func _grab_forms_in_reach_but_not_at_distance() -> bool:
	var near: Variant = _world(4001)
	_spawn_shambler(near, 17.2, 16.5)   # 0.7 m -- inside GRAB_METRES
	var at_tick: int = _step_until_held(near, 40)
	if at_tick < 0:
		push_error("a shambler at 0.7 m never took hold within 40 ticks")
		return false

	var far: Variant = _world(4001)
	_spawn_shambler(far, 19.5, 16.5)    # 3.0 m -- outside CONTACT_METRES, never even Pursues
	for _i in 40:
		far.step()
	if _held(far):
		push_error("a shambler 3.0 m away took hold")
		return false
	print("GRAB OK held at 0.7m after %d ticks, never held at 3.0m over 40" % at_tick)
	return true


# Sightline-for-hands: a grab may cross screening foliage but never a wall or window.
#
# Note the shape of this test, because the obvious one does not work. At a 1 m reach the three
# sampled fractions necessarily land in one of the two bodies' own tiles -- there is no third
# tile strictly between them -- so "wall between two bodies about to grab" is not a geometry
# that exists. Worse, a shambler spawned standing *in* a wall simply wanders out of it and then
# grabs legitimately, which is what an earlier version of this assertion caught itself doing.
#
# So it is tested where the reach is long enough for a real third tile: directly on
# _clear_contact, and through the hold-validation path, which re-checks contact every tick out
# to RELEASE_METRES and drops a hold that loses its line.
func _a_wall_between_blocks_the_grab() -> bool:
	var walled: Variant = _world(4002, _column(19, 10, 22))
	var from: Dictionary = {"x": 17.2, "y": 16.5}
	var to: Dictionary = {"x": 20.2, "y": 16.5}
	if SimShambler._clear_contact(walled, from, to):
		push_error("_clear_contact crossed a wall column at x=19")
		return false
	var open_world: Variant = _world(4002)
	if not SimShambler._clear_contact(open_world, from, to):
		push_error("negative control failed: _clear_contact refused an unobstructed ray")
		return false

	# And in the live loop: a hold that loses its line is dropped on the next tick.
	var w: Variant = _world(4002, _column(19, 10, 22))
	var zed: int = _spawn_shambler(w, 17.2, 16.5)
	if _step_until_held(w, 40) < 0:
		push_error("no hold formed on the open side of the wall")
		return false
	var pos: Dictionary = w.components.get_component(w.player, "position") as Dictionary
	pos["x"] = 20.2
	pos["y"] = 16.5
	var zpos: Dictionary = w.components.get_component(zed, "position") as Dictionary
	zpos["x"] = 17.2
	zpos["y"] = 16.5
	w.step()
	if _held(w):
		push_error("a hold survived a wall growing across its line")
		return false

	# True negative: the same 3.0 m separation with no wall keeps the hold.
	var w2: Variant = _world(4002)
	var zed2: int = _spawn_shambler(w2, 17.2, 16.5)
	if _step_until_held(w2, 40) < 0:
		push_error("no hold formed in the unobstructed control")
		return false
	var pos2: Dictionary = w2.components.get_component(w2.player, "position") as Dictionary
	pos2["x"] = 20.2
	pos2["y"] = 16.5
	var zpos2: Dictionary = w2.components.get_component(zed2, "position") as Dictionary
	zpos2["x"] = 17.2
	zpos2["y"] = 16.5
	w2.step()
	if not _held(w2):
		push_error("a hold at 3.0 m with a clear line was dropped anyway")
		return false
	print("WALL OK ray blocked at x=19 and hold dropped; same 3.0m span held with no wall")
	return true


func _a_hold_bites_on_cadence_and_only_its_victim() -> bool:
	var w: Variant = _world(4003)
	_no_struggling(w)
	# A second survivor, well out of reach, is the negative control: identity alone puts them in
	# _gather_survivors, so if bites leaked across victims this would catch it.
	var bystander: int = int(w.entities.spawn())
	w.components.set_component(bystander, "position", {"x": 28.5, "y": 28.5})
	w.components.set_component(bystander, "identity", {"id": "survivor.test.bystander", "name": "Bystander"})
	SimHealth.make_survivor_body(w, bystander)

	_spawn_shambler(w, 17.2, 16.5)
	if _step_until_held(w, 40) < 0:
		push_error("no hold formed")
		return false

	var first_at: int = -1
	var second_at: int = -1
	var on_bystander: int = 0
	for i in (SimShambler.FIRST_BITE_TICKS + SimShambler.REPEAT_BITE_TICKS + 5):
		w.step()
		for e in w.events.drained:
			var ev: Dictionary = e as Dictionary
			if String(ev.get("type", "")) != "bite.landed":
				continue
			if int(ev.get("victim", -1)) == bystander:
				on_bystander += 1
				continue
			if first_at < 0:
				first_at = i + 1
			elif second_at < 0:
				second_at = i + 1
	if first_at < 0 or second_at < 0:
		push_error("expected two bites, got first=%d second=%d" % [first_at, second_at])
		return false
	if on_bystander != 0:
		push_error("a survivor nobody was holding took %d bites" % on_bystander)
		return false
	var gap: int = second_at - first_at
	if first_at != SimShambler.FIRST_BITE_TICKS or gap != SimShambler.REPEAT_BITE_TICKS:
		push_error("cadence off: first=%d (want %d) gap=%d (want %d)" % [first_at, SimShambler.FIRST_BITE_TICKS, gap, SimShambler.REPEAT_BITE_TICKS])
		return false
	print("BITE OK first at %d, next %d later, bystander took 0" % [first_at, gap])
	return true


func _every_bite_records_one_located_wound() -> bool:
	var w: Variant = _world(4004)
	_no_struggling(w)
	_spawn_shambler(w, 17.2, 16.5)
	if _step_until_held(w, 40) < 0:
		push_error("no hold formed")
		return false
	var bites: int = 0
	for _i in (SimShambler.FIRST_BITE_TICKS + SimShambler.REPEAT_BITE_TICKS * 2 + 5):
		w.step()
		bites += _bites_in_last_tick(w)
	var injuries: Dictionary = w.components.get_component(w.player, "injuries") as Dictionary
	var wounds: Array = injuries["wounds"] as Array
	if bites < 2 or wounds.size() != bites:
		push_error("wounds %d != bites %d" % [wounds.size(), bites])
		return false
	for wound in wounds:
		var part: String = String((wound as Dictionary).get("bodyPart", ""))
		if not SimCombat.SURVIVOR_BODY_PARTS.has(part):
			push_error("wound on a part no survivor has: '%s'" % part)
			return false
	# True negative: an untouched survivor in the same world accrues nothing.
	var clean: Variant = _world(4004)
	for _j in 60:
		clean.step()
	var clean_wounds: Array = (clean.components.get_component(clean.player, "injuries") as Dictionary)["wounds"] as Array
	if clean_wounds.size() != 0:
		push_error("an unbitten survivor recorded %d wounds" % clean_wounds.size())
		return false
	print("WOUND OK %d bites -> %d located wounds, unbitten survivor 0" % [bites, wounds.size()])
	return true


# A mouth that already has hold of you reaches different parts than a swung bat does --
# SimCombat.HELD_HIT_LOCATION_WEIGHTS against SURVIVOR_HIT_LOCATION_WEIGHTS. Rolled directly
# rather than counted off live bites on purpose: a share is a distribution claim, and a hold
# produces bites one every four seconds, so measuring it live would mean either thousands of
# simulated ticks or an assertion too loose to catch a table someone quietly widened.
#
# Both halves are here. The true positive is that the held table collapses the head share and
# puts the weight on graspable parts; the true negative is the free-hit table run through the
# identical counter, which must *fail* the same test -- otherwise the assertion is measuring
# nothing but the sample size.
const HELD_ROLLS: int = 4000
# Measured at these tables: held head 0.05 against free 0.20, held arms+hands 0.50 against free
# 0.12. The bands are wide enough that 4,000 rolls of sampling noise cannot cross them and tight
# enough that swapping the tables fails both.
const HELD_HEAD_MAX: float = 0.10
const HELD_LIMBS_MIN: float = 0.40

func _a_held_bite_aims_where_the_hands_are() -> bool:
	var w: Variant = _world(4009)
	var body: Variant = w.components.get_component(w.player, "body")

	# A table that sums short silently over-weights whichever part _roll_body_part falls through
	# to, which is the last one in SURVIVOR_BODY_PARTS -- a foot. Cheap to check, impossible to
	# spot by eye in a ten-entry dictionary.
	for table_name in ["held", "free"]:
		var table: Dictionary = SimCombat.HELD_HIT_LOCATION_WEIGHTS if table_name == "held" else SimCombat.SURVIVOR_HIT_LOCATION_WEIGHTS
		var sum: float = 0.0
		for part in SimCombat.SURVIVOR_BODY_PARTS:
			sum += float(table.get(String(part), 0.0))
		if absf(sum - 1.0) > 0.0001:
			push_error("the %s hit-location table sums to %f, not 1.0" % [table_name, sum])
			return false

	var held: Dictionary = _roll_share(w, body, SimCombat.HELD_HIT_LOCATION_WEIGHTS, "held-roll")
	var free: Dictionary = _roll_share(w, body, {}, "free-roll")
	var held_head: float = float(held.get("head", 0.0))
	var free_head: float = float(free.get("head", 0.0))
	# Limbs, not "graspable parts": the torso is 0.55 of the free-hit table all by itself, so
	# counting it would make the two tables look alike and the discriminator would be noise.
	var held_limbs: float = _share_of(held, ["arm_left", "arm_right", "hand_left", "hand_right"])
	var free_limbs: float = _share_of(free, ["arm_left", "arm_right", "hand_left", "hand_right"])
	if held_head > HELD_HEAD_MAX:
		push_error("held bites found the head %.3f of the time, ceiling is %.3f" % [held_head, HELD_HEAD_MAX])
		return false
	if held_limbs < HELD_LIMBS_MIN:
		push_error("only %.3f of held bites landed on an arm or a hand, floor is %.3f" % [held_limbs, HELD_LIMBS_MIN])
		return false
	# True negative: the free-hit table, counted the same way through the same roller, must fail
	# both of those. The day someone points the bite back at SURVIVOR_HIT_LOCATION_WEIGHTS -- or
	# copies the free numbers into the held table -- this is the line that notices.
	if free_head <= HELD_HEAD_MAX and free_limbs >= HELD_LIMBS_MIN:
		push_error("negative control failed: the free-hit table also passes the held test (head %.3f limbs %.3f), so the test measures nothing" % [free_head, free_limbs])
		return false
	print("HELD-AIM OK head %.3f held vs %.3f free, arms+hands %.3f held vs %.3f free over %d rolls" % [held_head, free_head, held_limbs, free_limbs, HELD_ROLLS])
	return true


func _roll_share(w: Variant, body: Variant, weights: Dictionary, stream: String) -> Dictionary:
	var rng: Variant = w.rng.stream(stream)
	var counts: Dictionary = {}
	for _i in HELD_ROLLS:
		var part: String = SimMelee._roll_body_part(rng, body, weights)
		counts[part] = int(counts.get(part, 0)) + 1
	var shares: Dictionary = {}
	for key in counts.keys():
		shares[key] = float(int(counts[key])) / float(HELD_ROLLS)
	return shares


func _share_of(shares: Dictionary, parts: Array) -> float:
	var sum: float = 0.0
	for part in parts:
		sum += float(shares.get(String(part), 0.0))
	return sum


# A bite takes a fraction of the part it lands on, not a flat number -- CLAUDE.md's standing trap
# is that a head is 15 and a torso 40, so one number cannot mean the same thing on both.
#
# This also pins which side of a severity band the change lands on, deliberately rather than by
# accident: an arm bite used to be 8 of 20, exactly 0.40, exactly the DeepWound boundary. Scaled
# it is 7 of 20 = 0.35, a Laceration, which is a fifth of the bleed rate. That is the intended
# side -- a bite on the forearm you got in the way is a tear you can bandage -- and if someone
# retunes BITE_DAMAGE_PART_FRACTION back up over 0.40 this says so.
func _a_bite_scales_to_the_part_it_lands_on() -> bool:
	var w: Variant = _world(4010)
	var body: Dictionary = w.components.get_component(w.player, "body") as Dictionary

	var head: float = SimShambler.bite_damage_for(body, "head")
	var torso: float = SimShambler.bite_damage_for(body, "torso")
	var arm: float = SimShambler.bite_damage_for(body, "arm_left")
	var hand: float = SimShambler.bite_damage_for(body, "hand_left")
	if head >= SimShambler.BITE_DAMAGE:
		push_error("a head bite took %.2f, the full flat BITE_DAMAGE -- the scaling is not wired" % head)
		return false
	if absf(torso - SimShambler.BITE_DAMAGE) > 0.001:
		push_error("a torso bite took %.2f, expected the flat ceiling %.2f" % [torso, SimShambler.BITE_DAMAGE])
		return false
	if hand >= arm or arm >= torso:
		push_error("bites do not order by part size: hand %.2f arm %.2f torso %.2f" % [hand, arm, torso])
		return false
	# The floor and the ceiling, over every part a survivor has: health.gd records no wound for a
	# hit that removed no integrity, so a bite that rounded to nothing would leave nothing to
	# treat, and nothing may exceed the flat ceiling either.
	for part in SimCombat.SURVIVOR_BODY_PARTS:
		var d: float = SimShambler.bite_damage_for(body, String(part))
		if d < SimShambler.BITE_DAMAGE_MIN or d > SimShambler.BITE_DAMAGE:
			push_error("a bite on %s took %.2f, outside [%.2f, %.2f]" % [String(part), d, SimShambler.BITE_DAMAGE_MIN, SimShambler.BITE_DAMAGE])
			return false
	# A part this body does not have gets the unscaled ceiling rather than zero -- a zombie body
	# passed in here must still bite for something.
	if absf(SimShambler.bite_damage_for(body, "wing") - SimShambler.BITE_DAMAGE) > 0.001:
		push_error("an unknown part did not fall back to BITE_DAMAGE")
		return false

	# The band edge, pinned on purpose, with the pre-change number as its own control.
	var scaled_severity: int = SimWounds.severity_for(w, w.player, "arm_left", arm)
	var flat_severity: int = SimWounds.severity_for(w, w.player, "arm_left", SimShambler.BITE_DAMAGE)
	if scaled_severity != SimWounds.Severity.Laceration:
		push_error("an arm bite of %.2f graded %d, expected Laceration" % [arm, scaled_severity])
		return false
	if flat_severity != SimWounds.Severity.DeepWound:
		push_error("negative control failed: the old flat 8 on an arm no longer grades DeepWound, so this band edge is not the one that moved")
		return false

	# And the live wiring: what a real hold publishes must be the scaled number for the part it
	# names, and the sample must contain a part that is *not* the torso -- otherwise every bite
	# would coincidentally equal the flat ceiling and this would pass on a stub.
	var seen: int = 0
	var off_torso: int = 0
	for s in 8:
		var live: Variant = _world(4600 + s)
		_no_struggling(live)
		_spawn_shambler(live, 17.2, 16.5)
		if _step_until_held(live, 40) < 0:
			continue
		var live_body: Dictionary = live.components.get_component(live.player, "body") as Dictionary
		for _i in (SimShambler.FIRST_BITE_TICKS + SimShambler.REPEAT_BITE_TICKS * 3 + 5):
			live.step()
			for e in live.events.drained:
				var ev: Dictionary = e as Dictionary
				if String(ev.get("type", "")) != "bite.landed":
					continue
				var part: String = String(ev.get("bodyPart", ""))
				var want: float = SimShambler.bite_damage_for(live_body, part)
				if absf(float(ev.get("damage", -1.0)) - want) > 0.001:
					push_error("a live bite on %s carried %.2f, expected %.2f" % [part, float(ev.get("damage", -1.0)), want])
					return false
				seen += 1
				if part != "torso":
					off_torso += 1
		if off_torso > 0 and seen >= 4:
			break
	if seen < 4 or off_torso == 0:
		push_error("SKIP-WORTHY: only %d live bites and %d off the torso, so the live wiring was never judged" % [seen, off_torso])
		return false
	print("BITE-SCALE OK head %.2f torso %.2f arm %.2f (Laceration, flat 8 was a DeepWound) hand %.2f; %d live bites matched, %d off-torso" % [head, torso, arm, hand, seen, off_torso])
	return true


# Escape is an opposed contest (SimAptitudes.escape_chance), not a coin flip and not a
# certainty, so a single seed proves nothing either way. Both outcomes must appear across the
# sweep or this says so and fails rather than passing on one lucky roll.
func _struggling_frees_sometimes_and_never_while_spent() -> bool:
	var freed: int = 0
	var still_held: int = 0
	var seeds: int = 16
	for s in seeds:
		var w: Variant = _world(5100 + s)
		_spawn_shambler(w, 17.2, 16.5)
		if _step_until_held(w, 40) < 0:
			continue
		w.commands.push({"type": "swing"})
		for _i in (SimShambler.STRUGGLE_TICKS + 2):
			w.step()
		if _held(w):
			still_held += 1
		else:
			freed += 1
	if freed + still_held < seeds - 2:
		push_error("only %d/%d seeds produced a hold to struggle against" % [freed + still_held, seeds])
		return false
	if freed == 0 or still_held == 0:
		push_error("struggle is not a contest: freed=%d held=%d over %d seeds -- both outcomes must occur" % [freed, still_held, seeds])
		return false

	# True negative: an empty tank cannot buy an attempt, and must not be charged for one.
	#
	# The arithmetic here is thinner than it looks, and is worth stating because it moved: since
	# stamina recovers while held (health.recover's `grabbed` exemption), the tank is no longer
	# pinned at zero for the window. It climbs at STAMINA_PER_TICK 0.6 for the STRUGGLE_TICKS + 2
	# = 18 ticks stepped below, reaching 10.8 against a STRUGGLE_STAMINA of 15.0 -- so the refusal
	# still holds, with 4.2 of margin. Lengthen this window past 25 ticks, or drop the cost, and
	# this control stops being a control.
	var spent: Variant = _world(5200)
	_spawn_shambler(spent, 17.2, 16.5)
	if _step_until_held(spent, 40) < 0:
		push_error("no hold formed for the zero-stamina control")
		return false
	var stamina: Dictionary = spent.components.get_component(spent.player, "stamina") as Dictionary
	stamina["current"] = 0.0
	spent.commands.push({"type": "swing"})
	for _k in (SimShambler.STRUGGLE_TICKS + 2):
		spent.step()
	var grabbed: Variant = spent.components.get_component(spent.player, "grabbed")
	if not (grabbed is Dictionary):
		push_error("a survivor with no stamina escaped anyway")
		return false
	if int((grabbed as Dictionary)["struggleTicks"]) != 0:
		push_error("a struggle was armed with no stamina to pay for it")
		return false
	print("STRUGGLE OK freed=%d held=%d over %d seeds; empty tank never freed, never charged" % [freed, still_held, seeds])
	return true


# Instinct: a held survivor nobody is answering for fights back on their own after
# STRUGGLE_INSTINCT_TICKS. Timed rather than merely observed, because every interesting property
# of this feature is a *when*: it must not pre-empt a player who is playing, it must not leave an
# unattended one standing still, and it must not double-spend a tankful by firing on schedule
# while an attempt the player asked for is already in flight.
#
# The hold is made unbreakable (grip 999) so that what is measured is the intake's clock and not
# the escape contest, and each attempt is counted off the `stamina.spent` the intake publishes --
# the same event that pays for it, so an attempt that cost nothing could not be counted.
const INSTINCT_WINDOW: int = 60

func _instinct_answers_a_grab_nobody_else_will() -> bool:
	var alone: Array[int] = _attempt_ticks(7001, -1)
	var played: Array[int] = _attempt_ticks(7001, 1)
	if alone.is_empty():
		push_error("an unattended held survivor never struggled in %d ticks -- instinct did not fire" % INSTINCT_WINDOW)
		return false
	if alone[0] != SimShambler.STRUGGLE_INSTINCT_TICKS:
		push_error("instinct fired on hold-tick %d, expected %d" % [alone[0], SimShambler.STRUGGLE_INSTINCT_TICKS])
		return false
	# True negative one: nothing before the delay. Stated separately from the equality above
	# because it is the half that would fail if somebody set the constant to zero to "fix" a
	# harness -- an instinct with no delay is not instinct, it is the player's key press taken away.
	for at in alone:
		if at < SimShambler.STRUGGLE_INSTINCT_TICKS:
			push_error("a struggle was armed on hold-tick %d, before the instinct delay" % at)
			return false
	# True negative two: a player who presses F gets their attempt on the tick they asked for,
	# and instinct does *not* also fire on its own schedule -- arming resets the clock, so the
	# second attempt is a delay after the first rather than at a fixed hold age.
	if played.is_empty() or played[0] != 1:
		push_error("F did not commit an escape on the tick it was pressed: %s" % str(played))
		return false
	if played.has(SimShambler.STRUGGLE_INSTINCT_TICKS):
		push_error("instinct fired at hold-tick %d anyway, on top of the player's own attempt" % SimShambler.STRUGGLE_INSTINCT_TICKS)
		return false
	if played.size() > 1 and played[1] != 1 + SimShambler.STRUGGLE_INSTINCT_TICKS:
		push_error("the attempt after a player's F landed on hold-tick %d, expected %d" % [played[1], 1 + SimShambler.STRUGGLE_INSTINCT_TICKS])
		return false
	print("INSTINCT OK unattended struggles at %s, played at %s over %d ticks" % [str(alone), str(played), INSTINCT_WINDOW])
	return true


# Hold-relative ticks on which an escape attempt was armed. `press_on` is the hold-relative tick
# to push F on, or -1 for nobody at the keyboard at all.
func _attempt_ticks(seed_val: int, press_on: int) -> Array[int]:
	var w: Variant = _world(seed_val)
	_spawn_shambler(w, 17.2, 16.5, 999.0)
	var at: Array[int] = []
	if _step_until_held(w, 40) < 0:
		push_error("no hold formed for the instinct measurement")
		return at
	for i in INSTINCT_WINDOW:
		if press_on == i + 1:
			w.commands.push({"type": "swing"})
		w.step()
		for e in w.events.drained:
			var ev: Dictionary = e as Dictionary
			if String(ev.get("type", "")) != "stamina.spent":
				continue
			if int(ev.get("entity", -1)) != int(w.player):
				continue
			if absf(float(ev.get("amount", 0.0)) - SimShambler.STRUGGLE_STAMINA) > 0.001:
				continue
			at.append(i + 1)
	if not _held(w):
		push_error("the unbreakable hold broke anyway, so these timings are of a shorter hold than they claim")
		return [] as Array[int]
	return at


# Rescue: the second exit from a hold, and the first one that does not belong to the person in it.
#
# Same shape as the struggle assertion above and for the same reason -- it is a contest, so a
# single seed proves nothing and both outcomes have to appear across the sweep. What differs is
# who is acting: the held body here is an NPC colonist, the player stands 1.5 m away on the far
# side of them, and `_no_struggling` is on, so the *only* thing in the build that can end this
# hold is the H key. That the helper does not silence this new intake is the point -- it
# unregisters `shambler.struggle-intake`, and rescue is deliberately a separate system.
const RESCUE_SEEDS: int = 16

func _somebody_else_can_pull_you_out() -> bool:
	var freed: int = 0
	var still_held: int = 0
	var by_wrong: int = 0
	var events_seen: int = 0
	var cooldown: int = -1
	for s in RESCUE_SEEDS:
		var arena: Dictionary = _rescue_world(9100 + s, 1.5)
		if int(arena["held_at"]) < 0:
			continue
		var w: Variant = arena["world"]
		var victim: int = int(arena["victim"])
		w.commands.push({"type": "rescue"})
		var broken: Array = _grab_broken_over(w, victim, SimShambler.RESCUE_TICKS + 2)
		if w.components.has_component(victim, "grabbed"):
			still_held += 1
			if not broken.is_empty():
				push_error("a still-held colonist had %d grab.broken published about them" % broken.size())
				return false
			continue
		freed += 1
		if broken.size() != 1 or String((broken[0] as Dictionary).get("cause", "")) != "rescue":
			push_error("a rescued colonist produced %s, expected exactly one grab.broken cause=rescue" % str(broken))
			return false
		events_seen += 1
		if int((broken[0] as Dictionary).get("by", -1)) != int(w.player):
			by_wrong += 1
		var sd: Dictionary = w.components.get_component(int(arena["zed"]), "shambler") as Dictionary
		cooldown = int(sd["ticksToGrab"])
		if cooldown <= 0:
			push_error("a rescue released the hold without arming the re-grab cooldown")
			return false
	if freed + still_held < RESCUE_SEEDS - 2:
		push_error("only %d/%d seeds produced a hold to rescue from" % [freed + still_held, RESCUE_SEEDS])
		return false
	if freed == 0 or still_held == 0:
		push_error("rescue is not a contest: freed=%d held=%d over %d seeds -- both outcomes must occur" % [freed, still_held, RESCUE_SEEDS])
		return false
	if by_wrong > 0:
		push_error("%d rescue events named somebody other than the rescuer in `by`" % by_wrong)
		return false

	# True negative one: an empty tank buys nothing and is charged nothing. The recovery delay is
	# armed alongside the zero deliberately -- the rescuer is *free*, so health.recover's held-body
	# exemption does not apply to them and the tank stays empty for the whole window.
	var poor: Dictionary = _rescue_world(9200, 1.5)
	if int(poor["held_at"]) < 0:
		push_error("no hold formed for the zero-stamina rescuer control")
		return false
	var pw: Variant = poor["world"]
	var tank: Dictionary = pw.components.get_component(pw.player, "stamina") as Dictionary
	tank["current"] = 0.0
	tank["ticksUntilRecovery"] = SimCombat.STAMINA_RECOVERY_DELAY_TICKS
	var charged: int = 0
	for _i in (SimShambler.RESCUE_TICKS + 2):
		pw.commands.push({"type": "rescue"})
		pw.step()
		for e in pw.events.drained:
			var ev: Dictionary = e as Dictionary
			if String(ev.get("type", "")) != "stamina.spent":
				continue
			if int(ev.get("entity", -1)) == int(pw.player) and absf(float(ev.get("amount", 0.0)) - SimShambler.RESCUE_STAMINA) < 0.001:
				charged += 1
	if not pw.components.has_component(int(poor["victim"]), "grabbed"):
		push_error("a rescuer with no stamina pulled somebody free anyway")
		return false
	if charged != 0:
		push_error("a refused rescue was charged %d times" % charged)
		return false
	if float(tank["current"]) != 0.0:
		push_error("the zero-stamina control regenerated to %.2f -- it was not measuring a refusal" % float(tank["current"]))
		return false

	# True negative two: out of reach is out of reach. 3.0 m, and an unbreakable grip so that
	# nothing else could plausibly have ended the hold within the window.
	var far: Dictionary = _rescue_world(9300, 3.0, 999.0)
	if int(far["held_at"]) < 0:
		push_error("no hold formed for the out-of-range control")
		return false
	var fw: Variant = far["world"]
	if SimShambler.try_begin_rescue(fw, fw.player, int(far["victim"])):
		push_error("try_begin_rescue accepted a victim 3.0 m away, past RESCUE_METRES %.1f" % SimShambler.RESCUE_METRES)
		return false
	for _j in (SimShambler.RESCUE_TICKS + 2):
		fw.commands.push({"type": "rescue"})
		fw.step()
	if fw.components.has_component(fw.player, "rescue"):
		push_error("a rescue was armed against somebody out of reach")
		return false
	if not fw.components.has_component(int(far["victim"]), "grabbed"):
		push_error("an out-of-range hold ended anyway, so the range control measured nothing")
		return false

	# True negative three: your own hands have to be free. Same arena, plus a second shambler on
	# the player's other side, so the would-be rescuer is held themselves.
	var busy: Dictionary = _rescue_world(9400, 1.5, 999.0)
	if int(busy["held_at"]) < 0:
		push_error("no hold formed for the held-rescuer control")
		return false
	var bw: Variant = busy["world"]
	_spawn_shambler(bw, 15.8, 16.5, 999.0)
	var grabbed_at: int = -1
	for k in 40:
		bw.step()
		if bw.components.has_component(bw.player, "grabbed"):
			grabbed_at = k + 1
			break
	if grabbed_at < 0:
		push_error("the second shambler never took the rescuer, so this control proves nothing")
		return false
	if SimShambler.try_begin_rescue(bw, bw.player, int(busy["victim"])):
		push_error("a grabbed survivor was allowed to rescue somebody else")
		return false
	print("RESCUE OK freed=%d held=%d over %d seeds, %d events named the rescuer, cooldown=%d; empty tank/3.0m/held rescuer all refused" % [
		freed, still_held, RESCUE_SEEDS, events_seen, cooldown,
	])
	return true


# A colonist in a shambler's hands with the player standing `metres` short of them. Deliberately
# an NPC in the grip rather than the player: a rescue is the thing the *colony* can do about a
# hold, and the player being the one held is what every other assertion in this file already
# measures.
func _rescue_world(seed_val: int, metres: float, grip: float = -1.0) -> Dictionary:
	var w: Variant = _world(seed_val)
	_no_struggling(w)
	var victim: int = int(w.entities.spawn())
	w.components.set_component(victim, "position", {"x": 16.5 + metres, "y": 16.5})
	w.components.set_component(victim, "velocity", {"dx": 0.0, "dy": 0.0})
	w.components.set_component(victim, "identity", {"id": "survivor.test.victim", "name": "Victim"})
	SimHealth.make_survivor_body(w, victim)
	SimHealth.make_stamina(w, victim, 100)
	# 0.7 m past the victim, so the nearest survivor to it is the victim and not the player.
	var zed: int = _spawn_shambler(w, 16.5 + metres + 0.7, 16.5, grip)
	var held_at: int = -1
	for i in 40:
		w.step()
		if w.components.has_component(victim, "grabbed"):
			held_at = i + 1
			break
	return {"world": w, "victim": victim, "zed": zed, "held_at": held_at}


func _grab_broken_over(w: Variant, victim: int, ticks: int) -> Array:
	var out: Array = []
	for _i in ticks:
		w.step()
		for e in w.events.drained:
			var ev: Dictionary = e as Dictionary
			if String(ev.get("type", "")) == "grab.broken" and int(ev.get("victim", -1)) == victim:
				out.append(ev)
	return out


# Every hold that ends says so once, and says why. This is the only channel a bus-only harness has
# for counting releases -- check_m2_balance.gd reads nothing but the event bus -- so a cause that
# quietly stopped being published would take a whole column of the balance numbers with it.
#
# All four causes that do not need a second survivor are exercised here; `rescue` is the fifth and
# belongs to the assertion above, where there is somebody to do it.
func _every_ended_hold_says_why() -> bool:
	var causes: Dictionary = {}

	# Struggle. Seeds are searched for one where the contest is actually won, the way the
	# cooldown assertion does, so this never asserts against a hold that simply never ended.
	for s in 16:
		var w: Variant = _world(6300 + s)
		_spawn_shambler(w, 17.2, 16.5)
		if _step_until_held(w, 40) < 0:
			continue
		w.commands.push({"type": "swing"})
		var broken: Array = _grab_broken_over(w, w.player, SimShambler.STRUGGLE_TICKS + 2)
		if _held(w):
			continue
		if broken.size() != 1:
			push_error("an escape published %d grab.broken events, expected exactly one" % broken.size())
			return false
		var ev: Dictionary = broken[0] as Dictionary
		if String(ev.get("cause", "")) != "struggle" or int(ev.get("by", -1)) != int(w.player):
			push_error("an escape published %s, expected cause=struggle by=%d" % [str(ev), int(w.player)])
			return false
		causes["struggle"] = true
		break
	if not causes.has("struggle"):
		push_error("SKIP-WORTHY: no seed in 16 won an escape, so cause=struggle was never judged")
		return false

	# Geometry: a wall grows across the line of an open hold. Same staging as the wall assertion.
	var g: Variant = _world(6400, _column(19, 10, 22))
	var gz: int = _spawn_shambler(g, 17.2, 16.5)
	if _step_until_held(g, 40) < 0:
		push_error("no hold formed for the geometry release")
		return false
	(g.components.get_component(g.player, "position") as Dictionary)["x"] = 20.2
	(g.components.get_component(gz, "position") as Dictionary)["x"] = 17.2
	var geo: Array = _grab_broken_over(g, g.player, 1)
	if geo.size() != 1 or String((geo[0] as Dictionary).get("cause", "")) != "geometry":
		push_error("a hold that lost its line published %s, expected one cause=geometry" % str(geo))
		return false
	causes["geometry"] = true

	# The holder dies. entity.killed is published by hand here rather than by killing the shambler
	# with a weapon: this gate builds bare worlds with no melee module, and the subscription under
	# test keys off the event, not off the body.
	var d: Variant = _world(6500)
	var dz: int = _spawn_shambler(d, 17.2, 16.5, 999.0)
	if _step_until_held(d, 40) < 0:
		push_error("no hold formed for the holder-died release")
		return false
	d.events.publish({"type": "entity.killed", "entity": dz, "killer": -1, "x": 17.2, "y": 16.5, "zombieType": ""})
	var dead: Array = _grab_broken_over(d, d.player, 1)
	if dead.size() != 1 or String((dead[0] as Dictionary).get("cause", "")) != "holder-died":
		push_error("a dead holder published %s, expected one cause=holder-died" % str(dead))
		return false
	causes["holder-died"] = true

	# And the other body. A survivor who dies in the grip is released too, or their corpse would
	# keep a shambler's hands busy for the rest of the campaign.
	var v: Variant = _world(6600)
	_spawn_shambler(v, 17.2, 16.5, 999.0)
	if _step_until_held(v, 40) < 0:
		push_error("no hold formed for the victim-died release")
		return false
	v.events.publish({"type": "entity.killed", "entity": int(v.player), "killer": -1, "x": 16.5, "y": 16.5, "zombieType": ""})
	var gone: Array = _grab_broken_over(v, v.player, 1)
	if gone.size() != 1 or String((gone[0] as Dictionary).get("cause", "")) != "victim-died":
		push_error("a dead victim published %s, expected one cause=victim-died" % str(gone))
		return false
	causes["victim-died"] = true

	# True negative: a hold nothing ends says nothing. Unbreakable grip, every struggle intake
	# silenced, two hundred ticks -- if `grab.broken` were published on anything other than a
	# victim actually becoming free, this is where it would show.
	var quiet: Variant = _world(6700)
	_no_struggling(quiet)
	_spawn_shambler(quiet, 17.2, 16.5, 999.0)
	if _step_until_held(quiet, 40) < 0:
		push_error("no hold formed for the silent control")
		return false
	var noise: Array = _grab_broken_over(quiet, quiet.player, 200)
	if not noise.is_empty():
		push_error("an unbroken hold published %d grab.broken events" % noise.size())
		return false
	if not _held(quiet):
		push_error("the unbreakable hold ended anyway, so the silent control measured nothing")
		return false
	print("BROKEN OK causes %s each published exactly once; 200 ticks of an unbroken hold published none" % str(causes.keys()))
	return true


# Stamina comes back while you are held. Both halves of that are load-bearing and both are here:
# health.recover stops skipping regen for a `grabbed` body, and world.gd stops charging that body
# the posture ladder's drain. Without the second, the first does nothing at all -- the drain
# publishes stamina.spent every tick, every stamina.spent re-arms the recovery delay, and a
# survivor grabbed mid-jog would regenerate exactly nothing forever.
const REGEN_TICKS: int = 30

func _a_held_body_gets_its_breath_back() -> bool:
	var w: Variant = _world(8100)
	_no_struggling(w)
	_spawn_shambler(w, 17.2, 16.5, 999.0)
	if _step_until_held(w, 40) < 0:
		push_error("no hold formed for the regen measurement")
		return false
	var held_drain: int = _run_empty_and_jogging(w, REGEN_TICKS)
	var held_tank: float = float((w.components.get_component(w.player, "stamina") as Dictionary)["current"])
	var want: float = float(REGEN_TICKS) * SimCombat.STAMINA_PER_TICK
	if absf(held_tank - want) > 0.001:
		push_error("a held survivor regenerated %.2f over %d ticks, expected %.2f" % [held_tank, REGEN_TICKS, want])
		return false
	if held_drain != 0:
		push_error("a pinned survivor was charged the jogging drain %d times" % held_drain)
		return false
	if not _held(w):
		push_error("the hold ended during the measurement, so this is not a held-body number")
		return false

	# True negative: the identical stamina state on a survivor nobody is holding. They are jogging,
	# so the drain fires, so the delay never lapses, so they recover nothing -- which is the rule
	# the held body is exempt from, still doing its job everywhere else.
	var free_world: Variant = _world(8101)
	var free_drain: int = _run_empty_and_jogging(free_world, REGEN_TICKS)
	var free_tank: float = float((free_world.components.get_component(free_world.player, "stamina") as Dictionary)["current"])
	if free_tank != 0.0:
		push_error("a free jogging survivor at an empty tank climbed to %.2f -- the recovery delay is not gating anything" % free_tank)
		return false
	if free_drain < REGEN_TICKS:
		push_error("a free jogging survivor was charged the drain only %d times in %d ticks" % [free_drain, REGEN_TICKS])
		return false
	print("REGEN-HELD OK held tank 0.0 -> %.1f over %d ticks with %d drains; free jogger stayed at %.1f with %d" % [
		held_tank, REGEN_TICKS, held_drain, free_tank, free_drain,
	])
	return true


# Empties the tank, arms the recovery delay, sets the player jogging, and counts the ladder's
# drain events over the window. Returns how many times the drain was actually charged.
func _run_empty_and_jogging(w: Variant, ticks: int) -> int:
	var tank: Dictionary = w.components.get_component(w.player, "stamina") as Dictionary
	tank["current"] = 0.0
	tank["ticksUntilRecovery"] = SimCombat.STAMINA_RECOVERY_DELAY_TICKS
	var posture: Dictionary = w.components.get_component(w.player, "posture") as Dictionary
	posture["current"] = SimStances.Stance.Jog
	posture["target"] = SimStances.Stance.Jog
	posture["ticks_left"] = 0
	var drain: float = SimStances.drain_per_tick(SimStances.Stance.Jog)
	var charged: int = 0
	for _i in ticks:
		w.step()
		for e in w.events.drained:
			var ev: Dictionary = e as Dictionary
			if String(ev.get("type", "")) != "stamina.spent":
				continue
			if int(ev.get("entity", -1)) == int(w.player) and absf(float(ev.get("amount", 0.0)) - drain) < 0.0001:
				charged += 1
	return charged


func _release_arms_the_regrab_cooldown() -> bool:
	# Search seeds for one where the struggle actually succeeds, so the assertion has data.
	for s in 16:
		var w: Variant = _world(6100 + s)
		var zed: int = _spawn_shambler(w, 17.2, 16.5)
		if _step_until_held(w, 40) < 0:
			continue
		w.commands.push({"type": "swing"})
		for _i in (SimShambler.STRUGGLE_TICKS + 2):
			w.step()
		if _held(w):
			continue
		var sd: Dictionary = w.components.get_component(zed, "shambler") as Dictionary
		var cooldown: int = int(sd["ticksToGrab"])
		if cooldown <= 0:
			push_error("release left no re-grab cooldown (ticksToGrab=%d)" % cooldown)
			return false
		# True negative: the very next tick must not re-take them while the cooldown runs.
		w.step()
		if _held(w):
			push_error("re-grabbed on the tick after escaping, cooldown did nothing")
			return false
		print("COOLDOWN OK ticksToGrab=%d after escape, not re-grabbed next tick" % cooldown)
		return true
	push_error("SKIP-WORTHY: no seed in 16 produced a successful escape, so the cooldown was never exercised")
	return false


# The escape has to actually get you somewhere, and for one slice it did not.
#
# Both bodies are pinned for the whole hold, so a release starts from at most GRAB_METRES. At the
# old BREAK_AWAY_SPEED of 1.6 the shambler's 1.68 seek *gained* on the escapee, so the gap shrank
# across the 20-tick re-grab cooldown and the re-grab was unconditional: the balance harness
# measured a median inter-grab window of exactly REGRAB_COOLDOWN_TICKS, and 149 holds on one
# victim in ten compressed days. The duration of BREAK_AWAY_TICKS never mattered; the difference
# of the two speeds did.
#
# So the speed relationship is pinned here as a fact, not left to be re-derived: if a locomotion
# retune ever makes a shambler faster than a fleeing survivor, this fails and says why rather than
# quietly restoring the treadmill.
#
# The negative is the load-bearing half: strip `breakAway` a tick after the same escape, leaving
# everything else identical, and the survivor is inside GRAB_METRES when the cooldown lapses and
# is re-taken. Without it this would pass on a shambler that had simply stopped chasing.
func _an_escape_opens_a_gap_the_cooldown_cannot_close() -> bool:
	var seek: float = SimLocomotion.zombie_speed(float(SimShambler.DEFAULT_LOCOMOTION["speed"]))
	if SimShambler.BREAK_AWAY_SPEED <= seek:
		push_error("BREAK_AWAY_SPEED %.2f does not outrun the %.2f seek -- a release cannot open a gap at all" % [SimShambler.BREAK_AWAY_SPEED, seek])
		return false

	var gaps: Array = []
	for keep_running in [true, false]:
		var w: Variant = _world(9200)
		_no_struggling(w)
		var npc: int = _spawn_npc(w, 24.5, 24.5)
		var zed: int = _spawn_shambler(w, 25.2, 24.5, 999.0)
		var formed: bool = false
		for _i in 40:
			w.step()
			if w.components.has_component(npc, "grabbed"):
				formed = true
				break
		if not formed:
			push_error("no hold formed on the NPC, so there is no escape to measure")
			return false
		_pin_the_bite_clock(w, zed)
		# One escape, taken by hand so the measurement does not depend on a contest roll landing.
		# This is the exact call the struggle contest makes when it wins.
		SimShambler._release_victim(w, npc, "struggle", npc)
		if not w.components.has_component(npc, "breakAway"):
			push_error("a release armed no break-away at all")
			return false
		w.step()
		if not keep_running:
			# The component *and* the velocity it wrote: shambler.pin drives the run by writing a
			# velocity every tick, and removing the component alone would leave the last one in
			# place and the survivor coasting. What this control models is the old behaviour --
			# somebody who tears free and stands exactly where they were.
			w.components.remove(npc, "breakAway")
			var vel: Dictionary = w.components.get_component(npc, "velocity") as Dictionary
			vel["dx"] = 0.0
			vel["dy"] = 0.0
		var regrabbed_at: int = -1
		var at_cooldown: float = -1.0
		for i in SimShambler.BREAK_AWAY_TICKS:
			w.step()
			if regrabbed_at < 0 and w.components.has_component(npc, "grabbed"):
				regrabbed_at = i + 1
			if i + 1 == SimShambler.REGRAB_COOLDOWN_TICKS:
				at_cooldown = _distance(w, npc, zed)
		gaps.append({"gap": _distance(w, npc, zed), "at_cooldown": at_cooldown, "regrabbed_at": regrabbed_at})

	var ran: Dictionary = gaps[0] as Dictionary
	var stood: Dictionary = gaps[1] as Dictionary
	if int(ran["regrabbed_at"]) >= 0:
		push_error("a survivor who broke away was re-taken %d ticks later, inside BREAK_AWAY_TICKS" % int(ran["regrabbed_at"]))
		return false
	if float(ran["at_cooldown"]) <= SimShambler.GRAB_METRES:
		push_error("at the %d-tick cooldown expiry the gap was %.3f m, inside GRAB_METRES %.2f" % [SimShambler.REGRAB_COOLDOWN_TICKS, float(ran["at_cooldown"]), SimShambler.GRAB_METRES])
		return false
	if float(ran["gap"]) <= SimShambler.GRAB_METRES:
		push_error("%d ticks after the escape the gap was %.3f m, inside GRAB_METRES %.2f" % [SimShambler.BREAK_AWAY_TICKS, float(ran["gap"]), SimShambler.GRAB_METRES])
		return false
	if int(stood["regrabbed_at"]) < 0:
		push_error("the survivor who stood still was never re-taken (gap %.3f m) -- the break-away above proves nothing" % float(stood["gap"]))
		return false
	print("CLEAR-AWAY OK break-away %.2f vs seek %.2f: %.3f m at the %d-tick cooldown, %.3f m at %d, no re-grab; standing still, re-grabbed after %d" % [
		SimShambler.BREAK_AWAY_SPEED, seek, float(ran["at_cooldown"]), SimShambler.REGRAB_COOLDOWN_TICKS,
		float(ran["gap"]), SimShambler.BREAK_AWAY_TICKS, int(stood["regrabbed_at"]),
	])
	return true


# `identity` survives recruits._make_corpse, and _gather_survivors looks for `identity`. So until
# the corpse skip landed, a shambler pursued and grabbed the dead: a hold on a body that cannot
# struggle, cannot be rescued and cannot die again, ending only when geometry happened to break
# it. Every hold counter in the balance harness was reading those too.
func _the_dead_are_not_worth_chasing() -> bool:
	var w: Variant = _world(9300)
	var dead: int = _spawn_npc(w, 24.5, 24.5)
	SimRecruits._make_corpse(w, dead)
	var zed: int = _spawn_shambler(w, 25.2, 24.5, 999.0)
	for _i in 60:
		w.step()
	if w.components.has_component(dead, "grabbed") or w.components.has_component(zed, "grabState"):
		push_error("a shambler took hold of a corpse 0.7 m away")
		return false

	# The same placement, the same seed, a living body: taken at once. Without this the assertion
	# would also pass on a shambler that had stopped grabbing anybody.
	var live: Variant = _world(9300)
	var alive: int = _spawn_npc(live, 24.5, 24.5)
	_spawn_shambler(live, 25.2, 24.5, 999.0)
	var held_at: int = -1
	for i in 60:
		live.step()
		if live.components.has_component(alive, "grabbed"):
			held_at = i + 1
			break
	if held_at < 0:
		push_error("a living survivor in the same placement was never grabbed either")
		return false
	print("CORPSE OK a corpse at 0.7 m was never taken over 60 ticks; a living body in the same place was, after %d" % held_at)
	return true


# R1 and R4 together, in the loop rather than in a fixture: a held survivor who is bleeding opens
# their own press, keeps it through the hold, and clots the wound while still held.
#
# The control is the player, held and bleeding in the same way. The sim does not press the T key
# for them (treatment.self-aid is scoped off `controlled` on purpose), so they bleed -- which is
# also what proves the world was bleeding at all.
func _a_held_survivor_can_answer_their_own_bleeding() -> bool:
	var w: Variant = _world_with_treatment(9400)
	_no_struggling(w)
	var npc: int = _spawn_npc(w, 24.5, 24.5)
	var zed: int = _spawn_shambler(w, 25.2, 24.5, 999.0)
	if _step_until_grabbed(w, npc, 40) < 0:
		push_error("no hold formed for the press measurement")
		return false
	_pin_the_bite_clock(w, zed)
	_deep_wound(w, npc)
	w.step()
	var t: Variant = w.components.get_component(npc, "treatment")
	if not (t is Dictionary) or String((t as Dictionary).get("verb", "")) != "pressure":
		push_error("a held bleeding survivor opened no press: %s" % str(t))
		return false
	var opened: float = _blood(w, npc)
	var full: int = int(SimWounds.PRESSURE_TICKS[SimWounds.Severity.DeepWound])
	for _i in full:
		w.step()
	if not w.components.has_component(npc, "grabbed"):
		push_error("the hold ended during the press, so this measured a free survivor")
		return false
	if _still_bleeding(w, npc):
		push_error("a %d-tick held press never clotted the wound" % full)
		return false
	if _blood(w, npc) > opened:
		push_error("blood was lost under a held press: %.4f -> %.4f" % [opened, _blood(w, npc)])
		return false

	var control: Variant = _world_with_treatment(9401)
	_no_struggling(control)
	var czed: int = _spawn_shambler(control, 17.2, 16.5, 999.0)
	if _step_until_held(control, 40) < 0:
		push_error("no hold formed on the player control")
		return false
	_pin_the_bite_clock(control, czed)
	_deep_wound(control, control.player)
	for _i in full:
		control.step()
	if control.components.has_component(control.player, "treatment"):
		push_error("the sim opened a press for the player, who has a key for it")
		return false
	if _blood(control, control.player) <= 0.0:
		push_error("the held, untended player lost no blood, so the press above proves nothing")
		return false
	print("PRESS-THROUGH OK held press clotted the wound with %.4f lost; the held control player lost %.4f" % [_blood(w, npc), _blood(control, control.player)])
	return true


# R4. Pressing is not "your action" for the hold. A survivor with a hand on their own wound goes
# on trying to get out, and the sim charges them for every attempt -- so a press must not suppress
# the struggle intake, and the struggle must not cancel the press.
#
# The negative is the same world with the tank pinned empty: _arm_struggle refuses below
# STRUGGLE_STAMINA and charges nothing, so the counter reads zero. That is what proves the count
# above is attempts rather than ticks.
func _struggling_and_pressing_are_not_the_same_hand() -> bool:
	var counts: Array = []
	for empty in [false, true]:
		var w: Variant = _world_with_treatment(9500)
		var npc: int = _spawn_npc(w, 24.5, 24.5)
		var zed: int = _spawn_shambler(w, 25.2, 24.5, 999.0)
		if _step_until_grabbed(w, npc, 40) < 0:
			push_error("no hold formed for the struggle-during-press measurement")
			return false
		_pin_the_bite_clock(w, zed)
		_deep_wound(w, npc)
		w.step()
		if not w.components.has_component(npc, "treatment"):
			push_error("no press opened, so there is nothing to struggle during")
			return false
		var spends: int = 0
		var tank: Dictionary = w.components.get_component(npc, "stamina") as Dictionary
		for _i in 200:
			if empty:
				tank["current"] = 0.0
			w.step()
			for e in w.events.drained:
				var ev: Dictionary = e as Dictionary
				if String(ev.get("type", "")) != "stamina.spent":
					continue
				if int(ev.get("entity", -1)) != npc:
					continue
				if absf(float(ev.get("amount", 0.0)) - SimShambler.STRUGGLE_STAMINA) < 0.0001:
					spends += 1
		if not w.components.has_component(npc, "treatment"):
			push_error("the press did not survive %s" % ("an empty tank" if empty else "the struggling"))
			return false
		counts.append(spends)

	if int(counts[0]) < 2:
		push_error("only %d struggle attempts were paid for during a 200-tick press -- a press is suppressing the struggle" % int(counts[0]))
		return false
	if int(counts[1]) != 0:
		push_error("a survivor with an empty tank was charged %d struggle attempts, so the count above is not measuring attempts" % int(counts[1]))
		return false
	print("STRUGGLE-DURING-PRESS OK %d attempts paid for while the press ran; %d on an empty tank, and the press survived both" % [int(counts[0]), int(counts[1])])
	return true


# R2 and R5. A press is the one channel a new hold does not take away, and the pair of rules that
# makes that worth having: tear free mid-press and treatment.pin outranks breakAway, so the
# survivor stays on the wound instead of running; get re-taken and the press is still there. The
# press therefore runs *across* grab and escape cycles, which is the whole reason a 400-tick deep
# wound is answerable at all in a district where holds arrive every few seconds.
#
# The negative is R3 in the same shape: a stagger during the same press does end it, and the wound
# is still bleeding afterwards.
func _a_press_outlives_the_hold_that_started_it() -> bool:
	var w: Variant = _world_with_treatment(9600)
	_no_struggling(w)
	var npc: int = _spawn_npc(w, 24.5, 24.5)
	var zed: int = _spawn_shambler(w, 25.2, 24.5, 999.0)
	if _step_until_grabbed(w, npc, 40) < 0:
		push_error("no hold formed for the re-grab measurement")
		return false
	_pin_the_bite_clock(w, zed)
	_deep_wound(w, npc)
	w.step()
	if not w.components.has_component(npc, "treatment"):
		push_error("no press opened on the held NPC")
		return false
	for _i in 50:
		w.step()

	SimShambler._release_victim(w, npc, "struggle", npc)
	w.step()
	if not w.components.has_component(npc, "treatment"):
		push_error("the escape cancelled the press")
		return false
	if not w.components.has_component(npc, "breakAway"):
		push_error("the escape armed no break-away, so R5 is not being exercised")
		return false
	# R5: both write the same velocity slot at movement/-1 and treatment.pin sorts last, so the
	# body under a dressing does not run. Measured as ground covered, never as a component read.
	var at: Dictionary = w.components.get_component(npc, "position") as Dictionary
	var x0: float = float(at["x"])
	var y0: float = float(at["y"])
	for _i in 10:
		w.step()
	var drifted: float = sqrt(pow(float(at["x"]) - x0, 2.0) + pow(float(at["y"]) - y0, 2.0))
	if drifted > 0.0001:
		push_error("a survivor mid-press was carried %.4f m by their own break-away" % drifted)
		return false

	var retaken: int = -1
	for i in 60:
		w.step()
		if retaken < 0 and w.components.has_component(npc, "grabbed"):
			retaken = i + 1
			_pin_the_bite_clock(w, zed)
	if retaken < 0:
		push_error("the NPC was never re-taken, so surviving a re-grab was never tested")
		return false
	if not w.components.has_component(npc, "treatment"):
		push_error("the re-grab cancelled the press that survived the escape")
		return false
	for _i in int(SimWounds.PRESSURE_TICKS[SimWounds.Severity.DeepWound]):
		w.step()
	if _still_bleeding(w, npc):
		push_error("the press ran across an escape and a re-grab and still never clotted the wound")
		return false

	var knocked: Variant = _world_with_treatment(9601)
	_no_struggling(knocked)
	var npc2: int = _spawn_npc(knocked, 24.5, 24.5)
	var zed2: int = _spawn_shambler(knocked, 25.2, 24.5, 999.0)
	if _step_until_grabbed(knocked, npc2, 40) < 0:
		push_error("no hold formed for the stagger negative")
		return false
	_pin_the_bite_clock(knocked, zed2)
	_deep_wound(knocked, npc2)
	knocked.step()
	knocked.events.publish({"type": "entity.staggered", "entity": npc2})
	knocked.step()
	if knocked.components.has_component(npc2, "treatment"):
		push_error("a stagger did not end the press, so the survivals above prove nothing")
		return false
	print("REGRAB-SPARES-PRESS OK press survived the escape (0.0000 m drifted) and the re-grab %d ticks later, and clotted; a stagger still ends it" % retaken)
	return true


# R6. A press already paid for survives an escape (R5 above); a *new* one waits until the running
# is done. Without this the survivor would open a press on the tick they tore free, treatment.pin
# would immediately outrank breakAway, and they would stand exactly where they escaped from --
# re-taken at the cooldown, which is the treadmill the break-away exists to end.
func _first_aid_waits_until_the_running_is_done() -> bool:
	var w: Variant = _world_with_treatment(9700)
	var npc: int = _spawn_npc(w, 24.5, 24.5)
	_deep_wound(w, npc)
	w.components.set_component(npc, "breakAway", {"dx": 2.1, "dy": 0.0, "ticksLeft": SimShambler.BREAK_AWAY_TICKS})
	w.step()
	if w.components.has_component(npc, "treatment"):
		push_error("first aid opened on the tick a survivor tore free")
		return false
	var started_at: int = -1
	for i in (SimShambler.BREAK_AWAY_TICKS + 4):
		w.step()
		if w.components.has_component(npc, "treatment"):
			started_at = i + 1
			break
	if started_at < 0:
		push_error("first aid never opened at all after the break-away expired")
		return false
	if w.components.has_component(npc, "breakAway"):
		push_error("the press opened while the break-away was still running")
		return false

	var control: Variant = _world_with_treatment(9700)
	var free: int = _spawn_npc(control, 24.5, 24.5)
	_deep_wound(control, free)
	control.step()
	if not control.components.has_component(free, "treatment"):
		push_error("an identical survivor with no break-away also opened nothing, so the deferral above proves nothing")
		return false
	print("BREAKAWAY-DEFER OK deferred %d ticks to the end of the break-away; the same survivor without one starts on tick 1" % started_at)
	return true


func _step_until_grabbed(w: Variant, victim: int, limit: int) -> int:
	for i in limit:
		w.step()
		if w.components.has_component(victim, "grabbed"):
			return i + 1
	return -1


func _a_held_survivor_cannot_swing_or_fire() -> bool:
	var w: Variant = _world(4007)
	SimMelee.make_melee_armed(w, w.player, {"reachMetres": 1.4, "weight": 1.0, "damage": 10, "staggerTicks": 8, "speed": 1.0, "recovery": 1.0, "stamina": 1.0})
	SimRanged.make_ranged_armed(w, w.player, {"damage": 12, "magSize": 8, "reloadTicks": 24, "rangeMetres": 20.0})

	# Free: both are permitted. This is the true positive the refusals are measured against.
	if not SimMelee.try_begin_swing(w, w.player):
		push_error("an unheld, armed survivor could not swing")
		return false
	(w.components.get_component(w.player, "swing") as Dictionary)["state"] = 0
	if not SimRanged.try_begin_fire(w, w.player):
		push_error("an unheld, armed survivor could not fire")
		return false
	(w.components.get_component(w.player, "rangedWeapon") as Dictionary)["state"] = 0

	_spawn_shambler(w, 17.2, 16.5)
	if _step_until_held(w, 40) < 0:
		push_error("no hold formed")
		return false
	(w.components.get_component(w.player, "swing") as Dictionary)["state"] = 0
	(w.components.get_component(w.player, "rangedWeapon") as Dictionary)["state"] = 0
	if SimMelee.try_begin_swing(w, w.player):
		push_error("swung while held -- melee.gd's grabbed guard did not fire")
		return false
	if SimRanged.try_begin_fire(w, w.player):
		push_error("fired while held -- ranged.gd's grabbed guard did not fire")
		return false
	print("HELD OK swing and fire both allowed free, both refused while held")
	return true


func _deterministic_replay() -> bool:
	var a: String = _replay_run(4242)
	var b: String = _replay_run(4242)
	if a != b:
		push_error("identical seed and command log diverged")
		return false
	var c: String = _replay_run(4243)
	if a == c:
		push_error("a different seed produced an identical world -- this assertion cannot fail")
		return false
	print("DETERMINISM OK identical runs match (%d chars), a different seed diverges" % a.length())
	return true


# The flag is only honest if it is load-bearing. With it off no hold forms at all; with it on the
# identical world takes one. This is also the assertion that will notice the day someone flips the
# default -- it turns the flag from a comment into a fact.
func _the_flag_actually_gates_acquisition() -> bool:
	SimShambler.GRABS_ENABLED = false
	var off: Variant = _world(4008)
	_spawn_shambler(off, 17.2, 16.5)
	for _i in 40:
		off.step()
	var held_off: bool = _held(off)
	SimShambler.GRABS_ENABLED = true
	var on: Variant = _world(4008)
	_spawn_shambler(on, 17.2, 16.5)
	var at_tick: int = _step_until_held(on, 40)
	if held_off:
		push_error("a hold formed with GRABS_ENABLED off")
		return false
	if at_tick < 0:
		push_error("no hold formed with GRABS_ENABLED on -- the flag is not the only thing gating this")
		return false
	print("FLAG OK off: no hold in 40 ticks; on: held after %d" % at_tick)
	return true


func _replay_run(seed_val: int) -> String:
	var w: Variant = _world(seed_val)
	_spawn_shambler(w, 17.2, 16.5)
	for i in 80:
		if i == 45:
			w.commands.push({"type": "swing"})
		w.step()
	return String(w.serialize())
