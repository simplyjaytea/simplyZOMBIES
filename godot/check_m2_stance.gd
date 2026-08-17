extends SceneTree
# The stance ladder, made sim-owned. Guards Part A of the "Make harm real" slice
# (.hermes/plans/2026-08-17_065300-vertical-slice-design.md Phase 0): before this, world.gd
# built posture as a bare `{"current": n}`, `_apply_commands` matched only move/wait/shout so
# the `{"type":"stance"}` command main.gd pushed was recorded and never consumed, and nothing
# ever advanced `current` toward `target`. Every rung had walk's speed, walk's noise, and
# walk's swing/aim gates. This gate is the mechanical proof that a stance request now actually
# takes SimStances.STANCE_CHANGE_TICKS to land, costs stamina on the upper rungs, and is
# gated by an empty tank -- exercising SimStances (godot/sim/stances.gd), the
# player.advance-posture system it drives (godot/sim/world.gd), and the two stamina bugs in
# health.gd that a stance drain would otherwise be silently swallowed by.
#
# If this goes red: re-read Part A of the plan above before loosening an assertion. The
# regeneration assertion in particular is not a nice-to-have -- it is the true-positive proof
# that health.gd's stamina pool is a float, not an int truncating every regen tick to zero.

const World = preload("res://sim/world.gd")
const SimStances = preload("res://sim/stances.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimAttention = preload("res://sim/modules/attention_emitter.gd")
const SimCombat = preload("res://sim/combat.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _stance_change_takes_time() and ok
	ok = _sprint_drains_stamina_walk_does_not() and ok
	ok = _stamina_regenerates() and ok
	ok = _zero_stamina_refuses_sprint_full_grants_it() and ok
	ok = _sprint_demotes_when_stamina_hits_zero() and ok
	ok = _sprint_louder_than_crouch_same_distance() and ok
	ok = _deterministic_replay() and ok
	if ok:
		print("M2_STANCE_OK ladder sim-owned, stamina drains and regenerates, zero-stamina gated")
		quit(0)
	else:
		push_error("M2_STANCE_FAIL")
		quit(1)


# A bare fixture world -- no modules registered beyond what World._init wires in itself
# (player.apply-commands, player.advance-posture, movement.integrate). Callers register
# whatever module their assertion actually needs, so a test that only cares about the
# transition timer is not silently depending on health.gd behaving correctly too.
func _bare_world(stance: int, seed_val: int = 777, px: float = 24.0, py: float = 24.0, map_size: int = 48) -> Variant:
	var fixture: Dictionary = {
		"seed": seed_val,
		"tick_hz": 20,
		"map": {"width": map_size, "height": map_size, "walls": []},
		"player": {"id": 0, "x": px, "y": py, "stance": stance},
		"rng_probe": {"stream": "test", "samples": 0},
	}
	return World.new(fixture)


func _posture_of(w: Variant) -> Dictionary:
	return w.components.get_component(w.player, "posture") as Dictionary


func _stamina_of(w: Variant) -> Dictionary:
	return w.components.get_component(w.player, "stamina") as Dictionary


# A queued stance command moves `current` to the target only after
# SimStances.STANCE_CHANGE_TICKS ticks -- not sooner (checked one tick early) and not never
# (an un-commanded world is the negative control, so this cannot pass on a module that simply
# always reports Walk).
#
# Note this is a *flat* delay, not one scaled by how many rungs the request crosses:
# request_stance() (stances.gd) always arms STANCE_CHANGE_TICKS, never the distance-scaled
# stance_change_ticks(from, to) helper -- that helper has zero callers anywhere in godot/, this
# gate included. Confirmed by grep before writing this assertion against it instead.
func _stance_change_takes_time() -> bool:
	var w: Variant = _bare_world(SimStances.Stance.Walk)
	var ticks: int = SimStances.STANCE_CHANGE_TICKS
	w.commands.push({"type": "stance", "stance": SimStances.Stance.Sprint})
	for _i in ticks - 1:
		w.step()
	var mid: Dictionary = _posture_of(w)
	if int(mid["current"]) != SimStances.Stance.Walk:
		push_error("stance completed early: current=%d after %d/%d ticks" % [int(mid["current"]), ticks - 1, ticks])
		return false
	w.step()
	var done: Dictionary = _posture_of(w)
	if int(done["current"]) != SimStances.Stance.Sprint:
		push_error("stance never completed: current=%d after %d ticks" % [int(done["current"]), ticks])
		return false

	# Negative control: nothing was ever commanded, so nothing should move.
	var idle: Variant = _bare_world(SimStances.Stance.Walk)
	for _i in ticks:
		idle.step()
	var idle_posture: Dictionary = _posture_of(idle)
	if int(idle_posture["current"]) != SimStances.Stance.Walk:
		push_error("un-commanded posture drifted to %d over %d idle ticks" % [int(idle_posture["current"]), ticks])
		return false
	print("TRANSITION OK %d ticks: still walk at %d, sprint at %d, un-commanded stayed walk" % [ticks, ticks - 1, ticks])
	return true


# The other half of Part A's stamina fix: Crawl/Jog/Sprint cost something every tick they hold
# (SimStances.drain_per_tick), Walk/Crouch cost nothing. Both worlds run the same span so the
# comparison is apples to apples.
func _sprint_drains_stamina_walk_does_not() -> bool:
	var ticks: int = 40
	var sprinting: Variant = _bare_world(SimStances.Stance.Sprint)
	SimHealth.register_module(sprinting)
	SimHealth.make_stamina(sprinting, sprinting.player)
	var before_s: float = float(_stamina_of(sprinting)["current"])
	for _i in ticks:
		sprinting.step()
	var after_s: float = float(_stamina_of(sprinting)["current"])

	var walking: Variant = _bare_world(SimStances.Stance.Walk)
	SimHealth.register_module(walking)
	SimHealth.make_stamina(walking, walking.player)
	var before_w: float = float(_stamina_of(walking)["current"])
	for _i in ticks:
		walking.step()
	var after_w: float = float(_stamina_of(walking)["current"])

	if after_s >= before_s:
		push_error("sprint stamina did not drop over %d ticks: %.3f -> %.3f" % [ticks, before_s, after_s])
		return false
	if not is_equal_approx(after_w, before_w):
		push_error("walk stamina moved with no exertion over %d ticks: %.3f -> %.3f" % [ticks, before_w, after_w])
		return false
	print("DRAIN OK over %d ticks: sprint %.3f->%.3f, walk %.3f->%.3f" % [ticks, before_s, after_s, before_w, after_w])
	return true


# This is the true-positive proof for the truncation bug health.gd carried on main:
# `st["current"] = mini(int(st["max"]), int(float(st["current"]) + 0.6))` on an int pool never
# moves, because int(94 + 0.6) is 94. Spend some, idle past STAMINA_RECOVERY_DELAY_TICKS, and
# the pool must actually rise.
func _stamina_regenerates() -> bool:
	var w: Variant = _bare_world(SimStances.Stance.Walk)
	SimHealth.register_module(w)
	SimHealth.make_stamina(w, w.player)
	var spent: float = 6.0
	w.events.publish({"type": "stamina.spent", "entity": int(w.player), "amount": spent})
	w.step()
	var after_spend: float = float(_stamina_of(w)["current"])
	if not is_equal_approx(after_spend, 100.0 - spent):
		push_error("spend did not land: expected %.1f got %.3f" % [100.0 - spent, after_spend])
		return false
	# Walk drains nothing, so every further tick is either counting down
	# ticksUntilRecovery or regenerating -- run comfortably past the delay.
	var idle_ticks: int = int(SimCombat.STAMINA_RECOVERY_DELAY_TICKS) + 10
	for _i in idle_ticks:
		w.step()
	var after_idle: float = float(_stamina_of(w)["current"])
	if after_idle <= after_spend:
		push_error("stamina did not regenerate: %.3f -> %.3f over %d idle ticks (the int-truncation bug)" % [after_spend, after_idle, idle_ticks])
		return false
	print("REGEN OK %.3f -> %.3f -> %.3f over %d idle ticks" % [100.0, after_spend, after_idle, idle_ticks])
	return true


# A "stance" command to Sprint is refused outright while the tank is empty -- and granted the
# moment it is not. Walking and melee stay reachable either way; only the request to *enter*
# Sprint is gated.
func _zero_stamina_refuses_sprint_full_grants_it() -> bool:
	var empty: Variant = _bare_world(SimStances.Stance.Walk)
	SimHealth.register_module(empty)
	SimHealth.make_stamina(empty, empty.player)
	_stamina_of(empty)["current"] = 0.0
	empty.commands.push({"type": "stance", "stance": SimStances.Stance.Sprint})
	empty.step()
	var empty_posture: Dictionary = _posture_of(empty)
	if int(empty_posture["target"]) == SimStances.Stance.Sprint:
		push_error("zero-stamina sprint request was granted: target=%d" % int(empty_posture["target"]))
		return false

	var full: Variant = _bare_world(SimStances.Stance.Walk)
	SimHealth.register_module(full)
	SimHealth.make_stamina(full, full.player)
	full.commands.push({"type": "stance", "stance": SimStances.Stance.Sprint})
	full.step()
	var full_posture: Dictionary = _posture_of(full)
	if int(full_posture["target"]) != SimStances.Stance.Sprint:
		push_error("full-stamina sprint request was refused: target=%d" % int(full_posture["target"]))
		return false
	print("ZERO STAMINA OK refused at 0 (target stayed %d), granted at full (target %d)" % [int(empty_posture["target"]), int(full_posture["target"])])
	return true


# The other zero-stamina gate: a survivor already sprinting when the tank empties mid-run gets
# knocked down to Jog rather than left sprinting for free. Full stamina is the negative control.
func _sprint_demotes_when_stamina_hits_zero() -> bool:
	var w: Variant = _bare_world(SimStances.Stance.Sprint)
	SimHealth.register_module(w)
	SimHealth.make_stamina(w, w.player)
	_stamina_of(w)["current"] = 0.0
	w.step()
	var posture: Dictionary = _posture_of(w)
	if int(posture["current"]) != SimStances.Stance.Jog:
		push_error("sprint at zero stamina did not demote: current=%d" % int(posture["current"]))
		return false
	if int(posture["target"]) != SimStances.Stance.Jog:
		push_error("demotion left a stale sprint target: target=%d" % int(posture["target"]))
		return false

	var full: Variant = _bare_world(SimStances.Stance.Sprint)
	SimHealth.register_module(full)
	SimHealth.make_stamina(full, full.player)
	full.step()
	var full_posture: Dictionary = _posture_of(full)
	if int(full_posture["current"]) != SimStances.Stance.Sprint:
		push_error("full-stamina sprint demoted with no cause: current=%d" % int(full_posture["current"]))
		return false
	print("DEMOTION OK empty tank -> jog(%d), full tank stays sprint(%d)" % [int(posture["current"]), int(full_posture["current"])])
	return true


# attention_emitter.gd already read SimStances.NOISE off posture.current before this slice --
# it just never saw current move. This is the "free payoff" the plan calls out: sprinting
# becomes loud for the first time, and this is the proof.
func _sprint_louder_than_crouch_same_distance() -> bool:
	var distance: float = 8.0
	var sprint_noise: float = _drive_and_sum_noise(SimStances.Stance.Sprint, distance)
	var crouch_noise: float = _drive_and_sum_noise(SimStances.Stance.Crouch, distance)
	if sprint_noise <= crouch_noise:
		push_error("sprint (%.2f) did not out-noise crouch (%.2f) over the same %.1fm" % [sprint_noise, crouch_noise, distance])
		return false
	print("NOISE OK sprint=%.2f crouch=%.2f over the same %.1fm" % [sprint_noise, crouch_noise, distance])
	return true


func _drive_and_sum_noise(stance: int, distance: float) -> float:
	var w: Variant = _bare_world(stance, 555, 24.0, 24.0, 48)
	var map: Variant = SimTileMap.blank_map(48, 48)
	SimBoot.attach_kernel(w, map)
	SimAttention.register_module(w, map)
	SimAttention.make_emitter(w, w.player)
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	w.commands.push({"type": "move", "dx": 1.0, "dy": 0.0})
	var start: Dictionary = w.components.get_component(w.player, "position") as Dictionary
	var last_x: float = float(start["x"])
	var last_y: float = float(start["y"])
	var traveled: float = 0.0
	var noise: float = 0.0
	var guard: int = 0
	while traveled < distance and guard < 20000:
		guard += 1
		w.step()
		var pos: Dictionary = w.components.get_component(w.player, "position") as Dictionary
		var nx: float = float(pos["x"])
		var ny: float = float(pos["y"])
		traveled += sqrt((nx - last_x) ** 2.0 + (ny - last_y) ** 2.0)
		last_x = nx
		last_y = ny
		for e in w.events.drained:
			var ev: Dictionary = e as Dictionary
			if String(ev.get("type", "")) == "noise.emitted" and int(ev.get("source", -1)) == int(w.player):
				noise += float(ev["magnitude"])
	return noise


# Two identical seeded command logs must serialize byte-identical; a log with the stance
# command landing on a different tick must not. This is what keeps a stance change safe to put
# in a replay log or a save/load round-trip.
func _deterministic_replay() -> bool:
	var seed_val: int = 4242
	# Chosen so the two logs are still observably different at the point of comparison: the
	# transition is a flat STANCE_CHANGE_TICKS (4), so a command at tick 2 has long finished by
	# tick 8 (current=Sprint) while a command at tick 7 has not (still mid-transition) -- if
	# both had time to converge on the same final rung before `ticks` ran out, this assertion
	# would pass on a build that dropped the tick entirely from the save, which is exactly the
	# false pass CLAUDE.md's "true positive and true negative" rule warns about.
	var ticks: int = 8
	var log_a: Dictionary = {2: [{"type": "stance", "stance": SimStances.Stance.Sprint}]}
	var w1: Variant = _bare_world(SimStances.Stance.Walk, seed_val)
	_drive(w1, log_a, ticks)
	var w2: Variant = _bare_world(SimStances.Stance.Walk, seed_val)
	_drive(w2, log_a, ticks)
	if w1.serialize() != w2.serialize():
		push_error("identical seeded command logs diverged")
		return false

	var log_b: Dictionary = {7: [{"type": "stance", "stance": SimStances.Stance.Sprint}]}
	var w3: Variant = _bare_world(SimStances.Stance.Walk, seed_val)
	_drive(w3, log_b, ticks)
	if w1.serialize() == w3.serialize():
		push_error("moving the stance command to a different tick produced an identical serialization")
		return false
	print("DETERMINISM OK identical logs match (%d chars), shifted stance command diverges" % w1.serialize().length())
	return true


func _drive(w: Variant, commands_by_tick: Dictionary, ticks: int) -> void:
	for t in range(1, ticks + 1):
		for cmd in commands_by_tick.get(t, []) as Array:
			w.commands.push(cmd as Dictionary)
		w.step()
