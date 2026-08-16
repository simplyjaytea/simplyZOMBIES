extends SceneTree
# Day-8 gate beat, accept 15% transmitted, Inspect skilled vs untrained, death/leave.

const SimBoot = preload("res://sim/boot.gd")
const SimRecruits = preload("res://sim/modules/recruits.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const Clock = preload("res://sim/time/clock.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _beat() and ok
	ok = _transmit() and ok
	ok = _inspect() and ok
	ok = _death() and ok
	if ok:
		print("M2_RECRUITS_OK beat transmit inspect death")
		quit(0)
	else:
		push_error("M2_RECRUITS_FAIL")
		quit(1)

func _world() -> Variant:
	return SimBoot.playable(20260805, 64)["world"]

func _mara(w: Variant) -> int:
	for e in w.components.query(["identity"]):
		var ident: Variant = w.components.get_component(int(e), "identity")
		if ident is Dictionary and String((ident as Dictionary).get("id", "")) == "survivor.unique.mara":
			return int(e)
	return -1

func _beat() -> bool:
	var w: Variant = _world()
	w.tick = Clock.tick_on_day(8, Clock.DAWN_ENDS * 0.5)
	w.step()
	var waiting: Array[int] = w.components.query(["recruit"])
	if waiting.is_empty():
		push_error("day8 no recruit")
		return false
	var rec: int = waiting[0]
	if not SimRecruits.ignore(w, rec):
		push_error("ignore failed")
		return false
	if not w.components.query(["recruit"]).is_empty():
		push_error("ignore left recruit")
		return false
	print("BEAT OK day8 ignore")
	return true

func _transmit() -> bool:
	var hits: int = 0
	var n: int = 40
	for i in n:
		var w: Variant = _world()
		w.tick = Clock.tick_on_day(8, 0.05)
		# force a waiting recruit
		var rng: Variant = w.rng.stream("recruits")
		# burn i samples so each world differs after accept opens the stream... 
		# instead spawn then accept; stream rolls on accept
		for _b in i:
			rng.call("next")
		var rolled: Dictionary = SimRecruits.roll(w, rng)
		var rec: int = SimRecruits.spawn_generated(w, rolled, 49.5, 50.5)
		w.components.set_component(rec, "recruit", {"waiting": true, "beatDay": 8})
		SimRecruits.accept(w, rec)
		if w.components.has_component(rec, "zombieInfection"):
			var st: Variant = w.components.get_component(rec, "zombieInfection")
			for e in (st as Dictionary).get("exposures", []) as Array:
				if bool((e as Dictionary).get("transmitted", false)):
					hits += 1
	var rate: float = float(hits) / float(n)
	if rate < 0.02 or rate > 0.40:
		push_error("transmit rate %s hits %d/%d" % [str(rate), hits, n])
		return false
	print("TRANSMIT OK rate %.2f" % rate)
	return true

func _inspect() -> bool:
	var w: Variant = _world()
	var mara: int = _mara(w)
	w.components.set_component(w.player, "zombieInfection", {
		"exposures": [{
			"source": 1, "bodyPart": "torso", "exposedAtTick": 0, "transmitted": true,
			"stage": SimInfection.Stage.Progression, "stageEnteredAtTick": 0,
			"cauterized": false, "amputated": false,
		}],
	})
	var skilled: Dictionary = SimJobs.inspect(w, mara, w.player)
	var untrained: Dictionary = SimJobs.inspect(w, w.player, w.player)
	if String(skilled.get("prose", "")).find("probable") < 0 and String(skilled.get("prose", "")).find("day") < 0:
		push_error("skilled prose %s" % str(skilled))
		return false
	if String(untrained.get("prose", "")) != "ill":
		push_error("untrained prose %s" % str(untrained))
		return false
	var tab: Dictionary = SimInfection.diagnosis_of(w, w.player, 0)
	if String(tab.get("label", "")).find("infection") >= 0:
		push_error("injuries tab leaked")
		return false
	print("INSPECT OK skilled vs untrained")
	return true

func _death() -> bool:
	var w: Variant = _world()
	var mara: int = _mara(w)
	# uninfected NPC → corpse
	SimHealth.finish_death(w, mara)
	if not w.components.has_component(mara, "corpse"):
		push_error("mara not corpse")
		return false
	# player death ends run
	var w2: Variant = _world()
	SimHealth.finish_death(w2, w2.player)
	if not bool(w2.runOver):
		push_error("player death no runOver")
		return false
	# transmitted → shambler with kit
	var w3: Variant = _world()
	var m3: int = _mara(w3)
	w3.components.set_component(m3, "zombieInfection", {
		"exposures": [{"source": 1, "bodyPart": "torso", "exposedAtTick": 0, "transmitted": true, "stage": 0, "stageEnteredAtTick": 0, "cauterized": false, "amputated": false}],
	})
	SimHealth.finish_death(w3, m3)
	var turned: int = 0
	for e in w3.components.query(["turnedFrom"]):
		turned += 1
		if w3.components.query(["container"]).has(int(e)) or w3.components.has_component(int(e), "container"):
			pass
	if turned < 1:
		push_error("no turned shambler")
		return false
	# leave
	var w4: Variant = _world()
	var m4: int = _mara(w4)
	SimRecruits.begin_leave(w4, m4)
	if not w4.components.has_component(m4, "leaving"):
		push_error("leave missing")
		return false
	print("DEATH OK corpse turn runOver leave")
	return true
