extends SceneTree
# M2 lethality: progression determinism, armor reduces transmission, amputation window, turning
const World = preload("res://sim/world.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const Clock = preload("res://sim/time/clock.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _progression_determinism() and ok
	ok = _armor_reduces_transmission() and ok
	ok = _amputation_window() and ok
	ok = _turning_and_noise() and ok
	ok = _diagnosis_never_leaks() and ok
	ok = _a_ruined_torso_slows_the_dead() and ok
	ok = _a_torso_hit_may_put_the_dead_down() and ok
	ok = _the_head_stays_the_only_kill() and ok
	if ok:
		print("M2_LETHALITY_OK progression amputation turning diagnosis, and body damage slows and staggers the dead while the head stays the only kill")
		quit(0)
	else:
		push_error("M2_LETHALITY_FAIL")
		quit(1)

# The file comment has claimed "armor reduces transmission" since before the sided-limb
# split, but nothing here actually exercised it -- which is how item.vest.scrap's `armor`
# block kept the pre-split key ("arms") through that whole migration. `_armor_coverage()`
# looks up the exact bodyPart string a bite lands on, "arm_left" is not "arms", and a vest
# meant to blunt an arm bite was silently doing nothing on either arm. Caught while starting
# the paperdoll revamp, fixed in content, and now actually gated.
func _armor_reduces_transmission() -> bool:
	var trials: int = 500
	var unarmored: int = _bite_trials(trials, false)
	var armored: int = _bite_trials(trials, true)
	# -1 is _bite_trials' "I could not set the trial up" sentinel, and it satisfied **both**
	# comparisons below -- -1 is not >= 500, and -1.0 is not > 425.0 -- so an equip failure
	# printed `ARMOR OK armored=-1` and the gate exited 0. A sentinel that passes every
	# assertion it flows into is a gate that cannot fail; check it before comparing it.
	if armored < 0 or unarmored < 0:
		push_error("a bite trial could not be set up (armored=%d unarmored=%d); the comparisons below would have passed on the sentinel" % [armored, unarmored])
		return false
	if armored >= unarmored:
		push_error("armor did not reduce transmission: armored=%d unarmored=%d of %d" % [armored, unarmored, trials])
		return false
	# item.vest.scrap covers arm_left at 0.3 -- not an exact statistical target (that would be
	# flaky), just a check that the coverage is actually reaching the roll rather than being a
	# silent no-op from a stale key.
	if float(armored) > float(unarmored) * 0.85:
		push_error("armor coverage too weak to be real: armored=%d unarmored=%d of %d" % [armored, unarmored, trials])
		return false
	print("ARMOR OK armored=%d unarmored=%d of %d bites to arm_left" % [armored, unarmored, trials])
	return true

func _bite_trials(trials: int, armored: bool) -> int:
	var f: Dictionary = {"seed": 6001, "tick_hz": 20, "map": {"width": 8, "height": 8, "walls": []}, "player": {"id": 0, "x": 4.0, "y": 4.0, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	var w: Variant = World.new(f)
	SimInfection.register_module(w)
	if armored:
		var vest: int = SimItems.spawn_item(w, "item.vest.scrap", {"tier": "scavenged"})
		if not SimInventory.equip(w, w.player, vest, "vest"):
			push_error("could not equip item.vest.scrap for the armor trial")
			return -1
	var transmitted: int = 0
	for i in trials:
		w.events.publish({"type": "bite.landed", "victim": w.player, "source": 99, "bodyPart": "arm_left", "damage": 1.0})
		w.events.drain()
		var state: Variant = w.components.get_component(w.player, "zombieInfection")
		var exposures: Array = (state as Dictionary)["exposures"] as Array
		if bool((exposures[exposures.size() - 1] as Dictionary).get("transmitted", false)):
			transmitted += 1
	return transmitted

func _progression_determinism() -> bool:
	# Same seed, same bite at same tick -> same stage at tick N
	var f: Dictionary = {"seed": 4242, "tick_hz": 20, "map": {"width": 12, "height": 10, "walls": []}, "player": {"id": 0, "x": 6.0, "y": 5.0, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	# We inject bites by advancing tick to known transmitted case via seed search is flaky,
	# so instead we force transmitted exposure then verify deterministic advancement
	var w: Variant = World.new(f)
	var w2: Variant = World.new(f)
	for wv in [w, w2]:
		# add a body and infection state directly — progression is tick physics, not plumbing
		var e: int = wv.player
		wv.components.set_component(e, "position", {"x": 6.0, "y": 5.0})
		wv.components.set_component(e, "zombieInfection", {"exposures": [{"source": 99, "bodyPart": "arm_left", "exposedAtTick": 0, "transmitted": true, "stage": SimInfection.Stage.Latent, "stageEnteredAtTick": 0, "cauterized": false, "amputated": false}]})
		SimInfection.register_module(wv)
	for i in SimInfection.LATENT_TICKS:
		w.step()
		w2.step()
	var st1: Dictionary = w.components.get_component(w.player, "zombieInfection") as Dictionary
	var st2: Dictionary = w2.components.get_component(w2.player, "zombieInfection") as Dictionary
	var s1: int = int(((st1["exposures"] as Array)[0] as Dictionary).get("stage", -1))
	var s2: int = int(((st2["exposures"] as Array)[0] as Dictionary).get("stage", -1))
	if s1 != s2 or s1 != SimInfection.Stage.Onset:
		push_error("progression determinism fail s1=%d s2=%d exp Onset" % [s1, s2])
		return false
	# not transmitted -> never advances
	var f3: Dictionary = {"seed": 4243, "tick_hz": 20, "map": {"width": 8, "height": 8, "walls": []}, "player": {"id": 0, "x": 4.0, "y": 4.0, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	var w3: Variant = World.new(f3)
	w3.components.set_component(w3.player, "position", {"x": 4.0, "y": 4.0})
	w3.components.set_component(w3.player, "zombieInfection", {"exposures": [{"source": 1, "bodyPart": "torso", "exposedAtTick": 0, "transmitted": false, "stage": SimInfection.Stage.Latent, "stageEnteredAtTick": 0, "cauterized": false, "amputated": false}]})
	SimInfection.register_module(w3)
	for i in SimInfection.LATENT_TICKS + SimInfection.PROGRESSION_TICKS:
		w3.step()
	var st3: Dictionary = w3.components.get_component(w3.player, "zombieInfection") as Dictionary
	var s3: int = int(((st3["exposures"] as Array)[0] as Dictionary).get("stage", -1))
	if s3 != SimInfection.Stage.Latent:
		push_error("false progression for non-transmitted s3=%d" % s3)
		return false
	print("PROGRESSION OK s=%d" % s1)
	return true

func _amputation_window() -> bool:
	var f: Dictionary = {"seed": 5001, "tick_hz": 20, "map": {"width": 8, "height": 8, "walls": []}, "player": {"id": 0, "x": 4.0, "y": 4.0, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	var w: Variant = World.new(f)
	w.components.set_component(w.player, "body", {"head": 10, "torso": 20, "arm_left": 10, "arm_right": 10, "hand_left": 10, "hand_right": 10, "leg_left": 10, "leg_right": 10, "foot_left": 10, "foot_right": 10})
	w.components.set_component(w.player, "zombieInfection", {"exposures": [{"source": 1, "bodyPart": "arm_left", "exposedAtTick": 0, "transmitted": true, "stage": SimInfection.Stage.Latent, "stageEnteredAtTick": 0, "cauterized": false, "amputated": false}]})
	SimInfection.register_module(w)
	var r1: Dictionary = SimInfection.amputate(w, w.player, "arm_left")
	if not bool(r1.get("ok", false)):
		push_error("amputate latent should succeed %s" % str(r1))
		return false
	# amputated exposure must not progress even past its window
	for i in SimInfection.LATENT_TICKS + SimInfection.PROGRESSION_TICKS:
		w.step()
	var st: Dictionary = w.components.get_component(w.player, "zombieInfection") as Dictionary
	var exp: Dictionary = (st["exposures"] as Array)[0] as Dictionary
	if not bool(exp.get("amputated", false)):
		push_error("amputated flag lost")
		return false
	if int(exp.get("stage", -1)) != SimInfection.Stage.Latent:
		push_error("amputated progressed stage=%d" % int(exp.get("stage", -1)))
		return false
	# not-limb rejected
	var r3: Dictionary = SimInfection.amputate(w, w.player, "head")
	if bool(r3.get("ok", true)):
		push_error("amputate head should fail")
		return false
	# too-late: progression stage
	var f2: Dictionary = {"seed": 5002, "tick_hz": 20, "map": {"width": 8, "height": 8, "walls": []}, "player": {"id": 0, "x": 4.0, "y": 4.0, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	var w2: Variant = World.new(f2)
	w2.components.set_component(w2.player, "body", {"head": 10, "torso": 20, "arm_left": 10, "arm_right": 10, "hand_left": 10, "hand_right": 10, "leg_left": 10, "leg_right": 10, "foot_left": 10, "foot_right": 10})
	w2.components.set_component(w2.player, "zombieInfection", {"exposures": [{"source": 1, "bodyPart": "leg_left", "exposedAtTick": 0, "transmitted": true, "stage": SimInfection.Stage.Progression, "stageEnteredAtTick": 0, "cauterized": false, "amputated": false}]})
	SimInfection.register_module(w2)
	var r2: Dictionary = SimInfection.amputate(w2, w2.player, "leg_left")
	if bool(r2.get("ok", true)):
		push_error("amputate progression should be too-late %s" % str(r2))
		return false
	print("AMPUTATION OK")
	return true

func _turning_and_noise() -> bool:
	var f: Dictionary = {"seed": 5100, "tick_hz": 20, "map": {"width": 8, "height": 8, "walls": []}, "player": {"id": 0, "x": 1.0, "y": 1.0, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	var w: Variant = World.new(f)
	w.components.set_component(w.player, "position", {"x": 3.0, "y": 3.0})
	w.components.set_component(w.player, "zombieInfection", {"exposures": [{"source": 1, "bodyPart": "torso", "exposedAtTick": 0, "transmitted": true, "stage": SimInfection.Stage.Critical, "stageEnteredAtTick": 0, "cauterized": false, "amputated": false}]})
	SimInfection.register_module(w)
	for i in SimInfection.CRITICAL_TICKS:
		w.step()
	var st_v: Variant = w.components.get_component(w.player, "zombieInfection")
	if st_v is Dictionary:
		var s: int = int((((st_v as Dictionary)["exposures"] as Array)[0] as Dictionary).get("stage", -1))
		if s != SimInfection.Stage.Turned:
			push_error("turning did not reach Turned s=%d" % s)
			return false
	else:
		var had_stage_turned: bool = false
		for e2 in w.events.drained as Array:
			var ed2: Dictionary = e2 as Dictionary
			if String(ed2.get("type", "")) == "infection.staged" and int(ed2.get("to", -1)) == SimInfection.Stage.Turned:
				had_stage_turned = true
		if not had_stage_turned:
			push_error("turning despawned without staged Turned event")
			return false
	var had_turned: bool = false
	var had_noise: bool = false
	for e in w.events.drained as Array:
		var ed: Dictionary = e as Dictionary
		if String(ed.get("type", "")) == "survivor.turned":
			had_turned = true
		if String(ed.get("type", "")) == "noise.emitted" and int(ed.get("magnitude", 0)) == SimInfection.QUARANTINE_NOISE_MAG:
			had_noise = true
	if not had_turned:
		push_error("missing survivor.turned")
		return false
	if not had_noise:
		push_error("missing turning noise")
		return false
	var shamblers: int = 0
	for ent in w.components.query(["shambler"]):
		shamblers += 1
	if shamblers != 1:
		push_error("turning should spawn 1 shambler, got %d" % shamblers)
		return false
	if w.entities.call("is_alive", w.player):
		push_error("turned survivor should be despawned")
		return false
	print("TURNING OK shambler=1")
	return true

func _diagnosis_never_leaks() -> bool:
	var f: Dictionary = {"seed": 5200, "tick_hz": 20, "map": {"width": 8, "height": 8, "walls": []}, "player": {"id": 0, "x": 4.0, "y": 4.0, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	var w: Variant = World.new(f)
	w.components.set_component(w.player, "zombieInfection", {"exposures": [{"source": 1, "bodyPart": "arm_left", "exposedAtTick": 0, "transmitted": true, "stage": SimInfection.Stage.Progression, "stageEnteredAtTick": 0, "cauterized": false, "amputated": false}]})
	SimInfection.register_module(w)
	for skill in [0, 1, 2, 3]:
		var d: Dictionary = SimInfection.diagnosis_of(w, w.player, skill)
		if d.has("transmitted"):
			# diagnosis_of returns a transmitted:false placeholder for no-state only; with exposures it must not leak
			# our contract: when exposures exist, returned dict must not contain transmitted=true or expose private field
			if bool(d.get("transmitted", false)) == true:
				push_error("diagnosis leaked transmitted true at skill %d" % skill)
				return false
			# even false is a leak if callers start branching on it — for exposures we expect no transmitted key
			# but we allow omission: assert key missing
			if d.has("transmitted"):
				push_error("diagnosis should not return transmitted key at skill %d" % skill)
				return false
		if not d.has("label"):
			push_error("diagnosis missing label")
			return false
	print("DIAGNOSIS OK")
	return true


# --- The playable state, slice 8: body damage slows and staggers the dead ---------------------

# A 24x24 daylight world with the kernel and the shambler module, a shambler at the west and
# the player standing at the east, and a noise re-emitted at the player every tick so the
# shambler Seeks toward it at seek speed for as long as the lane runs.
func _seeking_world(seed_val: int, type_id: String = "zombie.shambler") -> Dictionary:
	var f: Dictionary = {"seed": seed_val, "tick_hz": 20, "map": {"width": 24, "height": 24, "walls": []}, "player": {"id": 0, "x": 22.5, "y": 12.5, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	var w: Variant = World.new(f)
	w.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	var map: Variant = SimTileMap.blank_map(24, 24)
	SimBoot.attach_kernel(w, map)
	SimHealth.register_module(w)
	SimShambler.register_module(w, map)
	w.components.set_component(w.player, "position", {"x": 22.5, "y": 12.5})
	var z: int = SimRoster.spawn_zombie(w, 2.5, 12.5, type_id, w.rng.stream("shambler"))
	w.components.set_component(z, "facing", {"radians": 0.0})
	return {"world": w, "zed": z}


func _covered(fx: Dictionary, ticks: int) -> float:
	var w: Variant = fx["world"]
	var z: int = int(fx["zed"])
	var start: Dictionary = (w.components.get_component(z, "position") as Dictionary).duplicate()
	for i in ticks:
		w.field.emit_noise(22.5, 12.5, 60.0)
		w.step()
	var end: Dictionary = w.components.get_component(z, "position") as Dictionary
	return sqrt(pow(float(end["x"]) - float(start["x"]), 2.0) + pow(float(end["y"]) - float(start["y"]), 2.0))


# TORSO-SLOW: the torso factor on every speed. A BadlyHurt torso (20 of 60) covers ~0.65 of
# what an Unhurt one covers in 200 ticks of seeking; an Unusable one ~0.5; and it compounds
# with the cripple. A screamer's authored torso of 40 is judged as whole -- `bodyMax` -- so
# its untouched body covers exactly what the factor 1.0 says.
func _a_ruined_torso_slows_the_dead() -> bool:
	var whole: Dictionary = _seeking_world(81)
	var d_whole: float = _covered(whole, 200)
	var badly: Dictionary = _seeking_world(81)
	(badly["world"].components.get_component(int(badly["zed"]), "body") as Dictionary)["torso"] = 20
	var d_badly: float = _covered(badly, 200)
	var gone: Dictionary = _seeking_world(81)
	(gone["world"].components.get_component(int(gone["zed"]), "body") as Dictionary)["torso"] = 0
	var d_gone: float = _covered(gone, 200)
	var both: Dictionary = _seeking_world(81)
	(both["world"].components.get_component(int(both["zed"]), "body") as Dictionary)["torso"] = 0
	(both["world"].components.get_component(int(both["zed"]), "body") as Dictionary)["legs"] = 0
	var d_both: float = _covered(both, 200)
	if d_whole < 5.0:
		push_error("TORSO-SLOW: the whole shambler covered only %.2f m in 200 ticks -- it is not seeking, so there is nothing to compare" % d_whole)
		return false
	if absf(d_badly / d_whole - 0.65) > 0.05:
		push_error("TORSO-SLOW: a BadlyHurt torso covered %.2f of the whole body's distance, wanted ~0.65 (%.2f vs %.2f m)" % [d_badly / d_whole, d_badly, d_whole])
		return false
	if absf(d_gone / d_whole - 0.5) > 0.05:
		push_error("TORSO-SLOW: an Unusable torso covered %.2f of the whole body's distance, wanted ~0.5" % (d_gone / d_whole))
		return false
	if d_both >= d_gone * 0.6:
		push_error("TORSO-SLOW: a ruined torso on ruined legs (%.2f m) should be slower than the torso alone (%.2f m) -- the factors do not compound" % [d_both, d_gone])
		return false
	var screamer: Dictionary = _seeking_world(81, "zombie.screamer")
	var sz: int = int(screamer["zed"])
	var st: Variant = SimHealth.part_state_of(screamer["world"], sz, "torso")
	if st == null or int(st) != SimHealth.PartState.Unhurt:
		push_error("TORSO-SLOW: an untouched screamer's torso (40 of its own 40) reads state %s, not Unhurt -- bodyMax is not read" % str(st))
		return false
	var table: Variant = SimHealth.part_state(screamer["world"].components.get_component(sz, "body") as Dictionary, "torso")
	if table == null or int(table) == SimHealth.PartState.Unhurt:
		push_error("TORSO-SLOW: the shared table would also have read the screamer's torso as Unhurt, so the bodyMax half is untested here")
		return false
	print("TORSO-SLOW OK in 200 ticks whole %.1f m, BadlyHurt %.1f (x%.2f), Unusable %.1f (x%.2f), torso and legs both %.1f; a screamer's 40 is Unhurt by its own maxima where the table says %s" % [d_whole, d_badly, d_badly / d_whole, d_gone, d_gone / d_whole, d_both, str(table)])
	return true


# TORSO-STAGGER: 200 torso hits on a BadlyHurt shambler put it down (a 20-tick stagger,
# `TORSO_STAGGER_TICKS`) about 60 % of the time and never on an Unhurt one; head hits draw
# nothing from the `bodyStagger` stream. The zero-damage hit keeps the state where the lane
# put it, which is the point: the roll is by the state, not the blow. Counted over the two
# steps after each hit: a publish from inside a drain handler lands in that same drain.
func _a_torso_hit_may_put_the_dead_down() -> bool:
	var counts: Dictionary = {}
	for torso in [20, 60]:
		var fx: Dictionary = _seeking_world(83)
		var w: Variant = fx["world"]
		var z: int = int(fx["zed"])
		(w.components.get_component(z, "body") as Dictionary)["torso"] = torso
		var staggers: int = 0
		for i in 200:
			w.events.publish({"type": "attack.connected", "attacker": w.player, "target": z, "bodyPart": "torso", "damage": 0.0})
			for _s in 2:
				w.step()
				for e in w.events.drained:
					if String((e as Dictionary).get("type", "")) == "entity.staggered" and int((e as Dictionary).get("entity", -1)) == z and int((e as Dictionary).get("ticks", 0)) == SimHealth.TORSO_STAGGER_TICKS:
						staggers += 1
		counts[torso] = staggers
	if int(counts[20]) < 80:
		push_error("TORSO-STAGGER: %d of 200 torso hits on a BadlyHurt shambler staggered it, floor is 80" % int(counts[20]))
		return false
	if int(counts[60]) != 0:
		push_error("TORSO-STAGGER: %d torso hits on an Unhurt shambler staggered it" % int(counts[60]))
		return false
	var fx2: Dictionary = _seeking_world(83)
	var w2: Variant = fx2["world"]
	var z2: int = int(fx2["zed"])
	(w2.components.get_component(z2, "body") as Dictionary)["torso"] = 20
	var stream: Variant = w2.rng.stream(SimHealth.TORSO_STAGGER_STREAM)
	var before: int = int(stream.call("save"))
	for i in 50:
		w2.events.publish({"type": "attack.connected", "attacker": w2.player, "target": z2, "bodyPart": "head", "damage": 0.0})
		w2.step()
	if int(stream.call("save")) != before:
		push_error("TORSO-STAGGER: head hits drew from the bodyStagger stream")
		return false
	w2.events.publish({"type": "attack.connected", "attacker": w2.player, "target": z2, "bodyPart": "torso", "damage": 0.0})
	w2.step()
	if int(stream.call("save")) == before:
		push_error("TORSO-STAGGER: a torso hit on a BadlyHurt shambler drew nothing from the stream")
		return false
	print("TORSO-STAGGER OK BadlyHurt %d of 200, Unhurt %d of 200; head hits leave the stream untouched and a torso hit draws" % [int(counts[20]), int(counts[60])])
	return true


# HEAD-ONLY: a torso taken to 0 kills nobody -- the body is alive, no `entity.killed` -- and
# a head taken to 0 does. The negative half is the whole slice's constraint.
func _the_head_stays_the_only_kill() -> bool:
	var fx: Dictionary = _seeking_world(89)
	var w: Variant = fx["world"]
	var z: int = int(fx["zed"])
	var killed: Array = []
	w.events.subscribe({"id": "gate.head-only", "type": "entity.killed", "handler": func(e: Dictionary) -> void:
		killed.append(int(e.get("entity", -1)))
	})
	w.events.publish({"type": "attack.connected", "attacker": w.player, "target": z, "bodyPart": "torso", "damage": 500.0})
	w.step()
	var body: Dictionary = w.components.get_component(z, "body") as Dictionary
	if int(body["torso"]) != 0 or not SimHealth.is_alive(body) or killed.has(z):
		push_error("HEAD-ONLY: a torso at %d killed the shambler (alive=%s, killed=%s)" % [int(body["torso"]), str(SimHealth.is_alive(body)), str(killed)])
		return false
	var slow: float = SimShambler._speed_of(w, z, w.components.get_component(z, "shambler") as Dictionary, "seekSpeed")
	var whole: float = float((w.components.get_component(z, "shambler") as Dictionary)["seekSpeed"])
	if absf(slow / whole - 0.5) > 0.001:
		push_error("HEAD-ONLY: an Unusable torso reads x%.3f, not x0.5" % (slow / whole))
		return false
	w.events.publish({"type": "attack.connected", "attacker": w.player, "target": z, "bodyPart": "head", "damage": 500.0})
	w.step()
	if not killed.has(z):
		push_error("HEAD-ONLY: a head at 0 did not kill")
		return false
	print("HEAD-ONLY OK torso 0 leaves the body alive at half speed; head 0 kills")
	return true
