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

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# Grabs ship off by default (SimShambler.GRABS_ENABLED) until wounds have a recovery clock --
	# see that constant for the arithmetic that put them behind a flag. Switched on here for the
	# whole gate, so every assertion below exercises the real loop rather than the shipped
	# default. When the default flips this line becomes a no-op and nothing here changes.
	SimShambler.GRABS_ENABLED = true
	var ok: bool = true
	ok = _grab_forms_in_reach_but_not_at_distance() and ok
	ok = _a_wall_between_blocks_the_grab() and ok
	ok = _a_hold_bites_on_cadence_and_only_its_victim() and ok
	ok = _every_bite_records_one_located_wound() and ok
	ok = _struggling_frees_sometimes_and_never_while_spent() and ok
	ok = _release_arms_the_regrab_cooldown() and ok
	ok = _a_held_survivor_cannot_swing_or_fire() and ok
	ok = _deterministic_replay() and ok
	ok = _the_flag_actually_gates_acquisition() and ok
	if ok:
		print("M2_CONTACT_OK grabs form, bite on cadence, wounds land, struggle is a contest")
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


# Spawned by hand rather than through SimRoster.spawn_zombie, which wants a loaded content
# registry. make_shambler falls back to DEFAULT_GRAB_STRENGTH and canGrab=true with no content
# entry (shambler.gd:105 _grab_of), which is exactly the default this gate wants to exercise.
func _spawn_shambler(w: Variant, x: float, y: float) -> int:
	var ent: int = int(w.entities.spawn())
	w.components.set_component(ent, "position", {"x": x, "y": y})
	w.components.set_component(ent, "velocity", {"dx": 0.0, "dy": 0.0})
	w.components.set_component(ent, "facing", {"radians": 0.0})
	w.components.set_component(ent, "body", SimCombat.ZOMBIE_BODY.duplicate())
	SimShambler.make_shambler(w, ent, w.rng.stream("shambler"))
	return ent


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
