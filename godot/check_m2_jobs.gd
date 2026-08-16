extends SceneTree
# A* to bed / Campfire / Stockpile; Cook/Haul/Construct/Doctor/Rest; Auto Focus.

const SimBoot = preload("res://sim/boot.gd")
const SimPath = preload("res://sim/path.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _astar() and ok
	ok = _focus() and ok
	ok = _jobs() and ok
	ok = _corpse_haul() and ok
	ok = _seek_wakes_rest() and ok
	if ok:
		print("M2_JOBS_OK astar focus cook haul construct doctor rest corpse seek")
		quit(0)
	else:
		push_error("M2_JOBS_FAIL")
		quit(1)

func _world() -> Variant:
	return SimBoot.playable(20260805, 64)["world"]

func _mara(w: Variant) -> int:
	for e in w.components.query(["identity"]):
		var ident: Variant = w.components.get_component(int(e), "identity")
		if ident is Dictionary and String((ident as Dictionary).get("id", "")) == "survivor.unique.mara":
			return int(e)
	return -1

func _astar() -> bool:
	var w: Variant = _world()
	var beds: Array[int] = w.components.query(["bed"])
	var fires: Array[int] = w.components.query(["campfire"])
	if beds.is_empty() or fires.is_empty():
		push_error("stations missing")
		return false
	var bp: Variant = w.components.get_component(beds[0], "position")
	var fp: Variant = w.components.get_component(fires[0], "position")
	var from := Vector2i(46, 45)
	var to_bed := Vector2i(floori(float((bp as Dictionary)["x"])), floori(float((bp as Dictionary)["y"])))
	var to_fire := Vector2i(floori(float((fp as Dictionary)["x"])), floori(float((fp as Dictionary)["y"])))
	var p1: Array[Vector2i] = SimPath.find(w, from, to_bed)
	var p2: Array[Vector2i] = SimPath.find(w, from, to_fire)
	var drop: Vector2i = Vector2i(-1, -1)
	for j in range(40, 60):
		for i in range(40, 62):
			if SimNeeds.is_stockpile_tile(w, i, j):
				drop = Vector2i(i, j)
				break
		if drop.x >= 0:
			break
	var p3: Array[Vector2i] = SimPath.find(w, from, drop)
	if p1.is_empty() and from != to_bed:
		push_error("no path to bed")
		return false
	if p2.is_empty() and from != to_fire:
		push_error("no path to campfire")
		return false
	if drop.x >= 0 and p3.is_empty() and from != drop:
		push_error("no path to stockpile")
		return false
	if SimPath.find(w, from, Vector2i(0, 0)).size() > 0 and w.is_blocked_tile(0, 0):
		push_error("path through wall")
		return false
	print("ASTAR OK bed fire stockpile")
	return true

func _focus() -> bool:
	var auto: Dictionary = SimJobs.preset("Auto")
	if int(auto.get("Haul", 0)) != 3 or int(auto.get("Guard", 0)) != 0:
		push_error("auto %s" % str(auto))
		return false
	var medic: Dictionary = SimJobs.preset("Medic")
	if int(medic.get("Doctor", 0)) != 1 or int(medic.get("Guard", 0)) != 2:
		push_error("medic %s" % str(medic))
		return false
	var w: Variant = _world()
	var mara: int = _mara(w)
	var view: Array[Dictionary] = SimJobs.work_view(w)
	if view.is_empty():
		push_error("work view empty")
		return false
	for row in view:
		if int(row.get("entity", -1)) == int(w.player):
			push_error("player on work grid")
			return false
	var jp: Variant = w.components.get_component(mara, "jobPriorities")
	if not jp is Dictionary or String((jp as Dictionary).get("focus", "")) != "Medic":
		push_error("mara focus %s" % str(jp))
		return false
	print("FOCUS OK auto medic grid")
	return true

func _jobs() -> bool:
	var w: Variant = _world()
	var mara: int = _mara(w)
	# Haul: item outside annex
	var item: int = SimItems.spawn_item(w, "item.scrap.metal", {"tier": "scavenged"})
	w.components.set_component(item, "position", {"x": 20.5, "y": 20.5})
	var haul: Dictionary = SimJobs._haul_work(w, 46.0, 45.0)
	if haul.is_empty() or int(haul.get("target", -1)) != item:
		push_error("haul work %s" % str(haul))
		return false
	# Cook
	var raw: int = SimItems.spawn_item(w, "item.food.raw", {"tier": "scavenged"})
	var drop: Vector2i = Vector2i(46, 45)
	for j in range(40, 60):
		for i in range(40, 62):
			if SimNeeds.is_stockpile_tile(w, i, j):
				drop = Vector2i(i, j)
				break
	w.components.set_component(raw, "position", {"x": float(drop.x) + 0.5, "y": float(drop.y) + 0.5})
	var cook: Dictionary = SimJobs._cook_work(w)
	if cook.is_empty():
		push_error("cook work empty")
		return false
	# Construct window
	var con: Dictionary = SimJobs._construct_work(w, 46.0, 45.0)
	if con.is_empty() or String(con.get("verb", "")) != "window":
		push_error("construct %s" % str(con))
		return false
	# Rest
	var rest: Dictionary = SimJobs._work_for(w, mara, "Rest")
	if rest.is_empty():
		push_error("rest work empty")
		return false
	# Doctor: injure mara
	var inj: Variant = w.components.get_component(mara, "injuries")
	if inj is Dictionary:
		((inj as Dictionary)["wounds"] as Array).append({"kind": "scratch", "bodyPart": "torso"})
	var doc: Dictionary = SimJobs._doctor_work(w, mara)
	if doc.is_empty():
		push_error("doctor work empty")
		return false
	SimJobs.inspect(w, mara, mara)
	var ins: Variant = w.components.get_component(mara, "inspect")
	if not ins is Dictionary:
		push_error("inspect missing")
		return false
	print("JOBS OK haul cook construct rest doctor")
	return true

func _corpse_haul() -> bool:
	var w: Variant = _world()
	var mara: int = _mara(w)
	SimHealth.finish_death(w, mara)
	if not w.components.has_component(mara, "corpse"):
		push_error("corpse missing")
		return false
	var mp: Variant = w.components.get_component(mara, "position")
	if not mp is Dictionary:
		push_error("corpse lost position")
		return false
	var job: Dictionary = {
		"kind": "Haul", "target": mara, "corpse": true, "ticksLeft": 0, "path": [], "pathGen": -1,
	}
	w.components.set_component(w.player, "job", job)
	var ctile := Vector2i(floori(float((mp as Dictionary)["x"])), floori(float((mp as Dictionary)["y"])))
	w.components.set_component(w.player, "position", {"x": float(ctile.x) + 0.5, "y": float(ctile.y) + 0.5})
	SimJobs._do_haul(w, w.player, job)
	if not bool(job.get("carrying", false)):
		push_error("corpse not carrying")
		return false
	if w.components.has_component(mara, "position"):
		push_error("corpse position still set while carrying")
		return false
	# Carrying branch must walk to dump, not stockpile. Place at dump and finish.
	var dump: Vector2i = SimJobs._corpse_dump()
	w.components.set_component(w.player, "position", {"x": float(dump.x) + 0.5, "y": float(dump.y) + 0.5})
	w.components.set_component(w.player, "job", job)
	SimJobs._advance_job(w, w.player, job)
	if w.components.has_component(w.player, "job"):
		push_error("corpse haul never finished at dump")
		return false
	var placed: Variant = w.components.get_component(mara, "position")
	if not placed is Dictionary:
		push_error("corpse not placed at dump")
		return false
	var dx: int = floori(float((placed as Dictionary)["x"]))
	var dy: int = floori(float((placed as Dictionary)["y"]))
	if dx != dump.x or dy != dump.y:
		push_error("corpse at %d,%d want dump %d,%d" % [dx, dy, dump.x, dump.y])
		return false
	# From a stockpile tile while carrying, next advance must leave for dump — not drop as stock.
	var w2: Variant = _world()
	var m2: int = _mara(w2)
	SimHealth.finish_death(w2, m2)
	var job2: Dictionary = {
		"kind": "Haul", "target": m2, "corpse": true, "carrying": true, "ticksLeft": 0, "path": [], "pathGen": -1,
	}
	w2.components.remove(m2, "position")
	var stock: Vector2i = SimJobs._stock_drop(w2)
	if stock.x < 0:
		push_error("no stockpile")
		return false
	w2.components.set_component(w2.player, "position", {"x": float(stock.x) + 0.5, "y": float(stock.y) + 0.5})
	w2.components.set_component(w2.player, "job", job2)
	SimJobs._advance_job(w2, w2.player, job2)
	w2.components.set_component(w2.player, "job", job2)
	if not bool(job2.get("carrying", false)):
		push_error("corpse haul dropped at stockpile")
		return false
	if w2.components.has_component(m2, "position"):
		push_error("corpse placed at stockpile")
		return false
	print("CORPSE HAUL OK dump")
	return true

func _seek_wakes_rest() -> bool:
	var w: Variant = _world()
	var mara: int = _mara(w)
	var beds: Array = w.components.query(["bed"])
	var bed: int = beds[0]
	var bp: Variant = w.components.get_component(bed, "position")
	w.components.set_component(mara, "position", {
		"x": float((bp as Dictionary)["x"]), "y": float((bp as Dictionary)["y"]),
	})
	w.components.set_component(mara, "job", {"kind": "Rest", "target": bed, "ticksLeft": 0, "path": [], "pathGen": -1})
	SimNeeds.start_sleep(w, mara, bed)
	if not w.components.has_component(mara, "sleeping"):
		push_error("not sleeping")
		return false
	# Soft hunger seek — Need seek must clear Rest and wake.
	var n: Dictionary = SimNeeds.of(w, mara)
	n["hunger"] = 35.0
	var food: int = SimItems.spawn_item(w, "item.food.canned", {"tier": "scavenged"})
	SimInventory.stow(w, mara, food)
	SimJobs._tick_one(w, mara)
	if w.components.has_component(mara, "sleeping"):
		push_error("still sleeping after seek")
		return false
	var job: Variant = w.components.get_component(mara, "job")
	if job is Dictionary and String((job as Dictionary).get("kind", "")) == "Rest":
		push_error("rest job survived seek")
		return false
	# Rest finishes at rest >= 80 so Auto does not sleep forever.
	w.components.set_component(mara, "job", {"kind": "Rest", "target": bed, "ticksLeft": 0, "path": [], "pathGen": -1})
	SimNeeds.start_sleep(w, mara, bed)
	n = SimNeeds.of(w, mara)
	n["hunger"] = 100.0
	n["rest"] = 80.0
	SimJobs._tick_one(w, mara)
	if w.components.has_component(mara, "job"):
		push_error("rest did not finish at 80")
		return false
	if w.components.has_component(mara, "sleeping"):
		push_error("still sleeping after rest done")
		return false
	print("SEEK WAKE OK rest clears")
	return true
