extends SceneTree
const World = preload("res://sim/world.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
func _init() -> void: call_deferred("_run")
func _run() -> void:
	var f: Dictionary = {"seed": 7777, "tick_hz": 20, "map": {"width": 8, "height": 8, "walls": []}, "player": {"id": 0, "x": 4.0, "y": 4.0, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	var w: Variant = World.new(f)
	w.components.set_component(w.player, "position", {"x": 4.0, "y": 4.0})
	w.components.set_component(w.player, "zombieInfection", {"exposures": [{"source": 1, "bodyPart": "torso", "exposedAtTick": 0, "transmitted": true, "stage": SimInfection.Stage.Latent, "stageEnteredAtTick": 0, "cauterized": false, "amputated": false}]})
	SimInfection.register_module(w)
	for i in 100: w.step()
	var snap: Dictionary = w.snapshot()
	var txt: String = w.serialize()
	var f2: Dictionary = {"seed": 7777, "tick_hz": 20, "map": {"width": 8, "height": 8, "walls": []}, "player": {"id": 0, "x": 4.0, "y": 4.0, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	var w2: Variant = World.new(f2)
	w2.restore(snap)
	if w2.serialize() != txt:
		push_error("M2 save fingerprint mismatch")
		quit(1)
		return
	# antibioticsCourses survives
	w.components.set_component(w.player, "zombieInfection", {"exposures": [{"source": 1, "bodyPart": "arms", "exposedAtTick": 0, "transmitted": true, "stage": SimInfection.Stage.Onset, "stageEnteredAtTick": 0, "cauterized": false, "amputated": false}], "antibioticsCourses": [{"atTick": 10, "stage": 1, "clears": false, "doseCount": 6}]})
	var snap2: Dictionary = w.snapshot()
	var w3: Variant = World.new(f2)
	w3.restore(snap2)
	var st: Variant = w3.components.get_component(w3.player, "zombieInfection")
	if st == null or not (st as Dictionary).has("antibioticsCourses"):
		push_error("antibioticsCourses lost on restore")
		quit(1)
		return
	print("M2_SAVE_ROUNDTRIP_OK")
	quit(0)
