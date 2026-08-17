extends SceneTree
# M2 lethality: progression determinism, armor reduces transmission, amputation window, turning
const World = preload("res://sim/world.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _progression_determinism() and ok
	ok = _armor_reduces_transmission() and ok
	ok = _amputation_window() and ok
	ok = _turning_and_noise() and ok
	ok = _diagnosis_never_leaks() and ok
	if ok:
		print("M2_LETHALITY_OK progression amputation turning diagnosis")
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
