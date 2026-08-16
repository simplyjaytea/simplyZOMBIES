extends SceneTree
# A* to bed / Campfire / Stockpile; Cook/Haul/Construct/Doctor/Rest; Auto Focus.

const SimBoot = preload("res://sim/boot.gd")
const SimPath = preload("res://sim/path.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _astar() and ok
	ok = _focus() and ok
	ok = _jobs() and ok
	if ok:
		print("M2_JOBS_OK astar focus cook haul construct doctor rest")
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
