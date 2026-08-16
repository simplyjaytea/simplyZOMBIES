class_name SimJobs
extends RefCounted

# Work grid + Need seek (0003, 0011). Need seek beats Jobs. A* is survivor-only.
# ponytail: one job dict per NPC; stub columns store a number and do nothing.

const SimPath = preload("res://sim/path.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const SimDirector = preload("res://sim/modules/director.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimInfection = preload("res://sim/modules/infection.gd")

const COLUMNS: Array[String] = [
	"Firefight", "Patient", "Doctor", "Rest", "Cook", "Hunt", "Construct", "Repair",
	"Haul", "Farm", "Water", "Craft", "Modify", "Butcher", "Clean", "Guard", "Bury",
]
const CONSUMERS: Array[String] = ["Haul", "Construct", "Cook", "Doctor", "Rest", "Patient", "Guard"]
const COOK_TICKS: int = 2400
const INSPECT_TICKS: int = 300
const REACH: float = 1.5


static func empty_row() -> Dictionary:
	var d: Dictionary = {}
	for c in COLUMNS:
		d[c] = 0
	return d


static func preset(focus: String, injured: bool = false) -> Dictionary:
	var d: Dictionary = empty_row()
	match focus:
		"Medic":
			d["Doctor"] = 1
			d["Guard"] = 2
			d["Rest"] = 3
		"Worker":
			d["Haul"] = 1
			d["Construct"] = 2
			d["Cook"] = 3
			d["Rest"] = 2
			d["Doctor"] = 4
		"Fighter":
			d["Rest"] = 1
			d["Haul"] = 2
			d["Construct"] = 3
		"Scout":
			d["Haul"] = 1
			d["Rest"] = 2
		"Manual":
			pass
		_:
			# Auto
			for c in ["Haul", "Construct", "Cook", "Doctor", "Rest"]:
				d[c] = 3
			if injured:
				d["Patient"] = 3
	return d


static func attach(world: Variant, entity: int, focus: String = "Auto", row: Dictionary = {}) -> void:
	var r: Dictionary = row if not row.is_empty() else preset(focus, _injured(world, entity))
	for c in COLUMNS:
		if not r.has(c):
			r[c] = 0
	world.components.set_component(entity, "jobPriorities", {"focus": focus, "cols": r})


static func set_focus(world: Variant, entity: int, focus: String) -> void:
	var jp: Variant = world.components.get_component(entity, "jobPriorities")
	var injured: bool = _injured(world, entity)
	if focus == "Manual" and jp is Dictionary:
		(jp as Dictionary)["focus"] = "Manual"
		return
	var row: Dictionary = preset(focus, injured)
	world.components.set_component(entity, "jobPriorities", {"focus": focus, "cols": row})


static func set_priority(world: Variant, entity: int, column: String, value: int) -> void:
	var jp: Variant = world.components.get_component(entity, "jobPriorities")
	if not jp is Dictionary:
		attach(world, entity, "Manual")
		jp = world.components.get_component(entity, "jobPriorities")
	(jp as Dictionary)["focus"] = "Manual"
	var cols: Dictionary = (jp as Dictionary).get("cols", empty_row()) as Dictionary
	cols[column] = clampi(value, 0, 4)
	(jp as Dictionary)["cols"] = cols


static func work_view(world: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ent in world.components.query(["jobPriorities", "identity"]):
		if world.components.has_component(int(ent), "controlled"):
			continue
		if int(ent) == int(world.player):
			continue
		var ident: Variant = world.components.get_component(int(ent), "identity")
		var jp: Dictionary = world.components.get_component(int(ent), "jobPriorities") as Dictionary
		var cols: Dictionary = jp.get("cols", empty_row()) as Dictionary
		var row: Dictionary = {
			"entity": int(ent),
			"name": String((ident as Dictionary).get("name", "?")) if ident is Dictionary else "?",
			"focus": String(jp.get("focus", "Auto")),
			"cols": cols,
		}
		out.append(row)
	return out


static func register_module(world: Variant) -> void:
	world.systems.register("jobs.ai", "ai", 0, func(w: Variant) -> void:
		_tick(w)
	)
	world.systems.register("jobs.intake", "input", 14, func(w: Variant) -> void:
		for cmd in w.commands.current as Array:
			var c: Dictionary = cmd as Dictionary
			match String(c.get("type", "")):
				"job.focus":
					set_focus(w, int(c.get("entity", -1)), String(c.get("focus", "Auto")))
				"job.priority":
					set_priority(w, int(c.get("entity", -1)), String(c.get("column", "")), int(c.get("value", 0)))
	)


static func _tick(world: Variant) -> void:
	if SimNeeds.hold_max(world):
		return
	if bool(world.runOver) if "runOver" in world else false:
		return
	for ent in world.components.query(["needs", "jobPriorities", "position"]):
		if world.components.has_component(int(ent), "controlled"):
			continue
		if int(ent) == int(world.player):
			continue
		if world.components.has_component(int(ent), "recruit"):
			continue
		if world.components.has_component(int(ent), "leaving"):
			continue
		if world.components.has_component(int(ent), "corpse"):
			continue
		_tick_one(world, int(ent))


static func _tick_one(world: Variant, ent: int) -> void:
	if world.components.has_component(ent, "grabbed"):
		return
	var n: Dictionary = SimNeeds.of(world, ent)
	if String(n.get("crisis", "none")) == "starving" or String(n.get("crisis", "none")) == "dehydrating":
		_stop(world, ent)
		return
	if String(n.get("crisis", "none")) == "passed_out":
		return
	var seek: String = SimNeeds.seek_kind(world, ent)
	var job: Variant = world.components.get_component(ent, "job")
	if seek != "":
		var hard: bool = false
		if seek == "thirst" or seek == "hunger" or seek == "rest":
			hard = float(n.get(seek, 100.0)) <= 0.0
		elif seek == "temperature":
			hard = String(n.get("temperature", "")) == "extremely_cold"
		elif seek == "hygiene":
			hard = String(n.get("hygiene", "")) == "filthy"
		# Soft/seek never interrupt mid-action (ticksLeft > 0). Rest has ticksLeft 0.
		if job is Dictionary and int((job as Dictionary).get("ticksLeft", 0)) > 0 and not hard:
			_advance_job(world, ent, job as Dictionary)
			return
		# Need seek beats Jobs: drop Rest / idle work so sleepers get up.
		if job is Dictionary:
			_stop(world, ent)
		_do_seek(world, ent, seek)
		return
	if job is Dictionary:
		_advance_job(world, ent, job as Dictionary)
		return
	_pick(world, ent)


static func _pick(world: Variant, ent: int) -> void:
	var jp: Variant = world.components.get_component(ent, "jobPriorities")
	if not jp is Dictionary:
		return
	var cols: Dictionary = (jp as Dictionary).get("cols", {}) as Dictionary
	if String((jp as Dictionary).get("focus", "")) == "Auto":
		cols = preset("Auto", _injured(world, ent))
		(jp as Dictionary)["cols"] = cols
	var ranked: Array[Dictionary] = []
	for c in CONSUMERS:
		var p: int = int(cols.get(c, 0))
		if p <= 0:
			continue
		ranked.append({"job": c, "p": p})
	ranked.sort_custom(func(a, b): return int(a["p"]) < int(b["p"]) if int(a["p"]) != int(b["p"]) else String(a["job"]) < String(b["job"]))
	for r in ranked:
		var kind: String = String(r["job"])
		if kind == "Doctor" and SimNeeds.of(world, ent).get("hygiene", "") == "filthy":
			continue
		if kind == "Cook" and SimNeeds.of(world, ent).get("hygiene", "") == "filthy":
			continue
		if kind == "Doctor" and SimNeeds.has_trait(world, ent, "squeamish") and not _sole_doctor(world, ent):
			continue
		var target: Dictionary = _work_for(world, ent, kind)
		if target.is_empty():
			continue
		world.components.set_component(ent, "job", target)
		if kind == "Haul" or kind == "Construct":
			var n: Dictionary = SimNeeds.of(world, ent)
			n["dirtyWake"] = true
		return


static func _sole_doctor(world: Variant, ent: int) -> bool:
	for other in world.components.query(["jobPriorities"]):
		if int(other) == ent:
			continue
		if world.components.has_component(int(other), "controlled"):
			continue
		var jp: Variant = world.components.get_component(int(other), "jobPriorities")
		if jp is Dictionary and int(((jp as Dictionary).get("cols", {}) as Dictionary).get("Doctor", 0)) > 0:
			return false
	return true


static func _work_for(world: Variant, ent: int, kind: String) -> Dictionary:
	var pos: Variant = world.components.get_component(ent, "position")
	if not pos is Dictionary:
		return {}
	var x: float = float((pos as Dictionary)["x"])
	var y: float = float((pos as Dictionary)["y"])
	match kind:
		"Haul":
			return _haul_work(world, x, y)
		"Construct":
			return _construct_work(world, x, y)
		"Cook":
			return _cook_work(world)
		"Doctor":
			return _doctor_work(world, ent)
		"Rest":
			var bed: int = SimNeeds.nearest_bed(world, x, y, true)
			if bed < 0:
				return {}
			return {"kind": "Rest", "target": bed, "ticksLeft": 0, "path": [], "pathGen": -1}
		"Patient":
			if not _injured(world, ent):
				return {}
			return {"kind": "Patient", "target": ent, "ticksLeft": 0, "path": [], "pathGen": -1}
		"Guard":
			return {"kind": "Guard", "tx": SimFortify.GATE_A.x, "ty": SimFortify.GATE_A.y, "ticksLeft": 0, "path": [], "pathGen": -1}
	return {}


static func _haul_work(world: Variant, x: float, y: float) -> Dictionary:
	var best: int = -1
	var best_d: float = 1e12
	for item in SimInventory.ground_items(world):
		var p: Variant = world.components.get_component(item, "position")
		if not p is Dictionary:
			continue
		var tx: int = floori(float((p as Dictionary)["x"]))
		var ty: int = floori(float((p as Dictionary)["y"]))
		if SimNeeds.is_stockpile_tile(world, tx, ty):
			continue
		if world.components.has_component(item, "corpse"):
			continue
		var dx: float = float((p as Dictionary)["x"]) - x
		var dy: float = float((p as Dictionary)["y"]) - y
		var d: float = dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = item
	if best < 0:
		var dump: Vector2i = _corpse_dump()
		for c in world.components.query(["corpse", "position"]):
			var p2: Variant = world.components.get_component(int(c), "position")
			if not p2 is Dictionary:
				continue
			var cx: int = floori(float((p2 as Dictionary)["x"]))
			var cy: int = floori(float((p2 as Dictionary)["y"]))
			# Already at the outdoor dump — leave it.
			if cx == dump.x and cy == dump.y:
				continue
			return {"kind": "Haul", "target": int(c), "corpse": true, "ticksLeft": 0, "path": [], "pathGen": -1}
		return {}
	return {"kind": "Haul", "target": best, "ticksLeft": 0, "path": [], "pathGen": -1}


static func _construct_work(world: Variant, x: float, y: float) -> Dictionary:
	if world.tilemap == null:
		return {}
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: float = 1e12
	for j in range(SimDirector.ANNEX.position.y, SimDirector.ANNEX.position.y + SimDirector.ANNEX.size.y):
		for i in range(SimDirector.ANNEX.position.x, SimDirector.ANNEX.position.x + SimDirector.ANNEX.size.x):
			if SimTileMap.tile_at(world.tilemap, i, j) != SimTileMap.Tile.Window:
				continue
			var d: float = pow(float(i) + 0.5 - x, 2.0) + pow(float(j) + 0.5 - y, 2.0)
			if d < best_d:
				best_d = d
				best = Vector2i(i, j)
	if best.x >= 0:
		return {"kind": "Construct", "verb": "window", "tx": best.x, "ty": best.y, "ticksLeft": SimFortify.CHANNEL_TICKS, "path": [], "pathGen": -1}
	# place a bed on indoor floor if extras need one
	var bodies: int = 0
	for e in world.components.query(["needs"]):
		if not world.components.has_component(int(e), "controlled"):
			bodies += 1
	bodies += 1
	var beds: int = world.components.query(["bed"]).size()
	if beds >= bodies:
		return {}
	var tile: Vector2i = _free_indoor(world)
	if tile.x < 0:
		return {}
	return {"kind": "Construct", "verb": "bed", "tx": tile.x, "ty": tile.y, "ticksLeft": SimFortify.CHANNEL_TICKS, "path": [], "pathGen": -1}


static func _free_indoor(world: Variant) -> Vector2i:
	for j in range(SimDirector.ANNEX.position.y, SimDirector.ANNEX.position.y + SimDirector.ANNEX.size.y):
		for i in range(SimDirector.ANNEX.position.x, SimDirector.ANNEX.position.x + SimDirector.ANNEX.size.x):
			if not SimNeeds.is_stockpile_tile(world, i, j):
				continue
			if _bed_at(world, i, j) >= 0:
				continue
			if _campfire_at(world, i, j) >= 0:
				continue
			return Vector2i(i, j)
	return Vector2i(-1, -1)


static func _bed_at(world: Variant, tx: int, ty: int) -> int:
	for e in world.components.query(["bed", "position"]):
		var p: Variant = world.components.get_component(int(e), "position")
		if p is Dictionary and floori(float((p as Dictionary)["x"])) == tx and floori(float((p as Dictionary)["y"])) == ty:
			return int(e)
	return -1


static func _campfire_at(world: Variant, tx: int, ty: int) -> int:
	for e in world.components.query(["campfire", "position"]):
		var p: Variant = world.components.get_component(int(e), "position")
		if p is Dictionary and floori(float((p as Dictionary)["x"])) == tx and floori(float((p as Dictionary)["y"])) == ty:
			return int(e)
	return -1


static func _cook_work(world: Variant) -> Dictionary:
	var raw: int = _stock_base(world, "item.food.raw")
	if raw < 0:
		return {}
	var fires: Array[int] = world.components.query(["campfire"])
	if fires.is_empty():
		return {}
	return {"kind": "Cook", "target": raw, "fire": fires[0], "ticksLeft": COOK_TICKS, "path": [], "pathGen": -1, "stage": "goto"}


static func _doctor_work(world: Variant, _ent: int) -> Dictionary:
	for other in world.components.query(["needs", "injuries"]):
		if world.components.has_component(int(other), "controlled") and not _injured(world, int(other)):
			continue
		if not _injured(world, int(other)):
			continue
		var job: Variant = world.components.get_component(int(other), "job")
		var idle: bool = job == null or (job is Dictionary and String((job as Dictionary).get("kind", "")) in ["Rest", "Patient", ""])
		if not idle and not world.components.has_component(int(other), "sleeping"):
			continue
		var inspect: bool = world.components.has_component(int(other), "recruit") or world.components.has_component(int(other), "zombieInfection")
		return {
			"kind": "Doctor",
			"target": int(other),
			"ticksLeft": INSPECT_TICKS if inspect else SimFortify.CHANNEL_TICKS,
			"inspect": inspect,
			"path": [],
			"pathGen": -1,
		}
	return {}


static func _stock_base(world: Variant, base_id: String) -> int:
	for item in SimNeeds.stockpile_items(world):
		var b: Variant = world.components.get_component(item, "itemBase")
		if b is Dictionary and String((b as Dictionary).get("baseId", "")) == base_id:
			return item
	return -1


static func _advance_job(world: Variant, ent: int, job: Dictionary) -> void:
	var kind: String = String(job.get("kind", ""))
	var dest: Vector2i = _job_tile(world, job)
	if dest.x >= 0 and not _at(world, ent, dest, REACH):
		_walk(world, ent, job, dest)
		return
	_still(world, ent)
	match kind:
		"Haul":
			_do_haul(world, ent, job)
		"Construct":
			_do_construct(world, ent, job)
		"Cook":
			_do_cook(world, ent, job)
		"Doctor":
			_do_doctor(world, ent, job)
		"Rest":
			# Seek continues until 80; Rest finishes there so Auto/Worker do not sleep forever.
			if float(SimNeeds.of(world, ent).get("rest", 0.0)) >= 80.0:
				if world.components.has_component(ent, "sleeping"):
					SimNeeds.wake(world, ent)
				_stop(world, ent)
				return
			var bed: int = int(job.get("target", -1))
			if not world.components.has_component(ent, "sleeping"):
				SimNeeds.start_sleep(world, ent, bed)
		"Patient":
			pass
		"Guard":
			pass
		_:
			_stop(world, ent)


static func _job_tile(world: Variant, job: Dictionary) -> Vector2i:
	if job.has("tx"):
		return Vector2i(int(job["tx"]), int(job["ty"]))
	var t: int = int(job.get("target", -1))
	if job.has("fire") and String(job.get("stage", "")) != "goto-item":
		t = int(job.get("fire", t))
	if t < 0:
		return Vector2i(-1, -1)
	var p: Variant = world.components.get_component(t, "position")
	if not p is Dictionary:
		return Vector2i(-1, -1)
	return Vector2i(floori(float((p as Dictionary)["x"])), floori(float((p as Dictionary)["y"])))


static func _do_haul(world: Variant, ent: int, job: Dictionary) -> void:
	var item: int = int(job.get("target", -1))
	if bool(job.get("carrying", false)):
		# Corpses skip the Stockpile — ADR 0010: outdoor dump only (avoids stockpile↔dump oscillation).
		if bool(job.get("corpse", false)):
			var dump: Vector2i = _corpse_dump()
			if not _at(world, ent, dump, REACH):
				_walk(world, ent, job, dump)
				return
			world.components.set_component(item, "position", {"x": float(dump.x) + 0.5, "y": float(dump.y) + 0.5})
			SimNeeds.dirt(world, ent, 1)
			_stop(world, ent)
			return
		var drop: Vector2i = _stock_drop(world)
		if drop.x < 0:
			_stop(world, ent)
			return
		if not _at(world, ent, drop, REACH):
			_walk(world, ent, job, drop)
			return
		SimInventory.drop_at_feet(world, ent, item)
		var pos: Variant = world.components.get_component(item, "position")
		if pos is Dictionary:
			(pos as Dictionary)["x"] = float(drop.x) + 0.5
			(pos as Dictionary)["y"] = float(drop.y) + 0.5
		_stop(world, ent)
		return
	if world.components.has_component(item, "corpse"):
		# Same as item Haul: lift off the map so `_job_tile` is invalid and we path to the dump.
		world.components.remove(item, "position")
		job["carrying"] = true
		SimNeeds.dirt(world, ent, 1)
		return
	if not SimInventory.stow(world, ent, item):
		world.components.remove(item, "position")
		if not SimInventory.stow(world, ent, item):
			_stop(world, ent)
			return
	world.components.remove(item, "position")
	job["carrying"] = true


static func _corpse_dump() -> Vector2i:
	return Vector2i(SimFortify.GATE_A.x, SimFortify.GATE_A.y + 2)


static func _stock_drop(world: Variant) -> Vector2i:
	for j in range(SimDirector.ANNEX.position.y, SimDirector.ANNEX.position.y + SimDirector.ANNEX.size.y):
		for i in range(SimDirector.ANNEX.position.x, SimDirector.ANNEX.position.x + SimDirector.ANNEX.size.x):
			if SimNeeds.is_stockpile_tile(world, i, j) and _bed_at(world, i, j) < 0 and _campfire_at(world, i, j) < 0:
				return Vector2i(i, j)
	return Vector2i(-1, -1)


static func _do_construct(world: Variant, ent: int, job: Dictionary) -> void:
	var left: int = int(job.get("ticksLeft", 0)) - 1
	job["ticksLeft"] = left
	var pos: Variant = world.components.get_component(ent, "position")
	if pos is Dictionary:
		world.events.publish({
			"type": "noise.emitted",
			"x": float((pos as Dictionary)["x"]),
			"y": float((pos as Dictionary)["y"]),
			"magnitude": SimFortify.CONSTRUCT_NOISE,
			"source": ent,
		})
	if left > 0:
		return
	if String(job.get("verb", "")) == "window":
		SimFortify._board_window(world, int(job.get("tx", 0)), int(job.get("ty", 0)))
	elif String(job.get("verb", "")) == "bed":
		SimNeeds.make_bed(world, float(int(job.get("tx", 0))) + 0.5, float(int(job.get("ty", 0))) + 0.5)
	_stop(world, ent)


static func _do_cook(world: Variant, ent: int, job: Dictionary) -> void:
	var fire: int = int(job.get("fire", -1))
	var cf: Variant = world.components.get_component(fire, "campfire")
	if cf is Dictionary and not bool((cf as Dictionary).get("lit", false)):
		SimNeeds.set_lit(world, fire, true, true)
	else:
		SimNeeds.set_lit(world, fire, true, true)
	var left: int = int(job.get("ticksLeft", 0)) - 1
	job["ticksLeft"] = left
	if left > 0:
		return
	var raw: int = int(job.get("target", -1))
	if world.components.has_component(raw, "itemBase"):
		world.components.remove(raw, "position")
		world.despawn(raw)
	var cooked: int = SimItems.spawn_item(world, "item.food.cooked", {"tier": "scavenged"})
	SimNeeds.mark_spoilage(world, cooked, "item.food.cooked")
	var drop: Vector2i = _stock_drop(world)
	if drop.x >= 0:
		world.components.set_component(cooked, "position", {"x": float(drop.x) + 0.5, "y": float(drop.y) + 0.5})
	SimNeeds.set_lit(world, fire, true, false)
	_stop(world, ent)


static func _do_doctor(world: Variant, ent: int, job: Dictionary) -> void:
	var left: int = int(job.get("ticksLeft", 0)) - 1
	job["ticksLeft"] = left
	if left > 0:
		return
	var target: int = int(job.get("target", -1))
	if bool(job.get("inspect", false)):
		inspect(world, ent, target)
	else:
		_treat(world, ent, target)
	if SimNeeds.has_trait(world, ent, "squeamish") and world.modifiers != null:
		world.modifiers.call("add", {"stat": "mood", "op": "add", "value": -8.0, "source": "trait.squeamish"}, ent)
	SimNeeds.dirt(world, ent, 1)
	_stop(world, ent)


static func inspect(world: Variant, examiner: int, target: int) -> Dictionary:
	var skill: int = 2 if _is_mara(world, examiner) else 0
	var d: Dictionary = SimInfection.diagnosis_of(world, target, skill)
	var prose: String = String(d.get("label", "fine"))
	if skill >= 2:
		var st: int = int(d.get("stage", -1))
		if st == SimInfection.Stage.Progression:
			prose = String(d.get("label", "ill")) + "; maybe a day"
		elif st == SimInfection.Stage.Critical:
			prose = String(d.get("label", "critical")) + "; hours"
	elif skill < 2:
		var st2: int = int(d.get("stage", -1))
		if st2 <= SimInfection.Stage.Onset:
			prose = "fine" if st2 < SimInfection.Stage.Onset else "fever"
		elif st2 == SimInfection.Stage.Progression:
			prose = "ill"
		elif st2 == SimInfection.Stage.Critical:
			prose = "critical"
	world.components.set_component(target, "inspect", {"prose": prose, "atTick": int(world.tick), "examiner": examiner, "skill": skill})
	world.events.publish({"type": "inspect.done", "entity": target, "examiner": examiner, "prose": prose})
	return {"prose": prose, "skill": skill}


static func _treat(world: Variant, ent: int, target: int) -> void:
	if not SimNeeds.consume_base(world, ent, "item.bandage.cloth"):
		for item in SimNeeds.stockpile_items(world):
			var b: Variant = world.components.get_component(item, "itemBase")
			if b is Dictionary and String((b as Dictionary).get("baseId", "")) == "item.bandage.cloth":
				world.components.remove(item, "position")
				if not SimInventory.stow(world, ent, item):
					world.despawn(item)
				else:
					SimNeeds.consume_base(world, ent, "item.bandage.cloth")
				break
	var mul: float = SimNeeds.treat_sepsis_mul(world, ent)
	world.events.publish({"type": "sepsis.checked", "entity": target, "mul": mul, "kind": "treat", "treater": ent})
	var body: Variant = world.components.get_component(target, "body")
	if body is Dictionary and int((body as Dictionary).get("torso", 0)) < 40:
		(body as Dictionary)["torso"] = mini(40, int((body as Dictionary)["torso"]) + 8)


static func _is_mara(world: Variant, ent: int) -> bool:
	var ident: Variant = world.components.get_component(ent, "identity")
	return ident is Dictionary and String((ident as Dictionary).get("id", "")) == "survivor.unique.mara"


static func _do_seek(world: Variant, ent: int, kind: String) -> void:
	if world.components.has_component(ent, "sleeping"):
		SimNeeds.wake(world, ent)
	var pos: Variant = world.components.get_component(ent, "position")
	if not pos is Dictionary:
		return
	var x: float = float((pos as Dictionary)["x"])
	var y: float = float((pos as Dictionary)["y"])
	match kind:
		"hunger":
			var food: int = _food_for(world, ent)
			if food < 0:
				return
			if SimInventory.owns(world, ent, food):
				SimNeeds.eat(world, ent, food)
				return
			var fp: Variant = world.components.get_component(food, "position")
			if fp is Dictionary:
				var tile := Vector2i(floori(float((fp as Dictionary)["x"])), floori(float((fp as Dictionary)["y"])))
				if not _at(world, ent, tile, REACH):
					var seek_job: Dictionary = {"kind": "Seek", "target": food, "path": [], "pathGen": -1}
					_walk(world, ent, seek_job, tile)
					world.components.set_component(ent, "job", seek_job)
					return
				world.components.remove(food, "position")
				if SimInventory.stow(world, ent, food):
					SimNeeds.eat(world, ent, food)
		"thirst", "hygiene":
			var bottle: int = _carry_base(world, ent, "item.water.bottle")
			if bottle < 0:
				bottle = _stock_base(world, "item.water.bottle")
			if bottle < 0:
				return
			if not SimInventory.owns(world, ent, bottle):
				var bp: Variant = world.components.get_component(bottle, "position")
				if bp is Dictionary:
					var bt := Vector2i(floori(float((bp as Dictionary)["x"])), floori(float((bp as Dictionary)["y"])))
					if not _at(world, ent, bt, REACH):
						var sj: Dictionary = {"kind": "Seek", "target": bottle, "path": [], "pathGen": -1}
						_walk(world, ent, sj, bt)
						world.components.set_component(ent, "job", sj)
						return
					world.components.remove(bottle, "position")
					SimInventory.stow(world, ent, bottle)
			if kind == "hygiene":
				SimNeeds.wash(world, ent)
			else:
				SimNeeds.drink(world, ent)
		"rest":
			var bed: int = SimNeeds.nearest_bed(world, x, y, true)
			if bed >= 0:
				var bp2: Variant = world.components.get_component(bed, "position")
				if bp2 is Dictionary:
					var tile2 := Vector2i(floori(float((bp2 as Dictionary)["x"])), floori(float((bp2 as Dictionary)["y"])))
					if not _at(world, ent, tile2, REACH):
						var sj2: Dictionary = {"kind": "Seek", "target": bed, "path": [], "pathGen": -1}
						_walk(world, ent, sj2, tile2)
						world.components.set_component(ent, "job", sj2)
						return
				SimNeeds.start_sleep(world, ent, bed)
			else:
				SimNeeds.start_sleep(world, ent, -1)
		"temperature":
			var n: Dictionary = SimNeeds.of(world, ent)
			var very: bool = String(n.get("temperature", "")) == "very_cold" or String(n.get("temperature", "")) == "extremely_cold"
			var fire: int = SimNeeds.nearest_campfire(world, x, y, not very)
			if fire < 0:
				fire = SimNeeds.nearest_campfire(world, x, y, false)
			if fire < 0:
				return
			var fp2: Variant = world.components.get_component(fire, "position")
			if fp2 is Dictionary:
				var ft := Vector2i(floori(float((fp2 as Dictionary)["x"])), floori(float((fp2 as Dictionary)["y"])))
				if not _at(world, ent, ft, CAMPFIRE_STAND):
					var sj3: Dictionary = {"kind": "Seek", "target": fire, "path": [], "pathGen": -1}
					_walk(world, ent, sj3, ft)
					world.components.set_component(ent, "job", sj3)
					return
			if very:
				var cf: Variant = world.components.get_component(fire, "campfire")
				if cf is Dictionary and not bool((cf as Dictionary).get("lit", false)):
					SimNeeds.set_lit(world, fire, true)


const CAMPFIRE_STAND: float = 4.0


static func _food_for(world: Variant, ent: int) -> int:
	for item in SimInventory.carried_items(world, ent):
		var b: Variant = world.components.get_component(item, "itemBase")
		if b is Dictionary and SimNeeds.FOOD.has(String((b as Dictionary).get("baseId", ""))):
			return item
	for item2 in SimNeeds.stockpile_items(world):
		var b2: Variant = world.components.get_component(item2, "itemBase")
		if b2 is Dictionary and SimNeeds.FOOD.has(String((b2 as Dictionary).get("baseId", ""))):
			return item2
	return -1


static func _carry_base(world: Variant, ent: int, base_id: String) -> int:
	for item in SimInventory.carried_items(world, ent):
		var b: Variant = world.components.get_component(item, "itemBase")
		if b is Dictionary and String((b as Dictionary).get("baseId", "")) == base_id:
			return item
	return -1


static func _walk(world: Variant, ent: int, job: Dictionary, dest: Vector2i) -> void:
	var pos: Variant = world.components.get_component(ent, "position")
	if not pos is Dictionary:
		return
	var here := Vector2i(floori(float((pos as Dictionary)["x"])), floori(float((pos as Dictionary)["y"])))
	var gen: int = int(world.mapGeneration)
	var path: Array = job.get("path", []) as Array
	if int(job.get("pathGen", -1)) != gen or path.is_empty():
		var found: Array[Vector2i] = SimPath.find(world, here, dest)
		path.clear()
		for s in found:
			path.append(s)
		job["path"] = path
		job["pathGen"] = gen
	if path.is_empty():
		_still(world, ent)
		return
	var nxt: Vector2i = path[0] as Vector2i
	var tx: float = float(nxt.x) + 0.5
	var ty: float = float(nxt.y) + 0.5
	var dx: float = tx - float((pos as Dictionary)["x"])
	var dy: float = ty - float((pos as Dictionary)["y"])
	if dx * dx + dy * dy < 0.04:
		path.remove_at(0)
		job["path"] = path
		if path.is_empty():
			_still(world, ent)
		return
	var len: float = sqrt(dx * dx + dy * dy)
	var speed: float = 2.1 * SimNeeds.work_mul(world, ent)
	if speed <= 0.0:
		speed = 1.0
	var vel: Variant = world.components.get_component(ent, "velocity")
	if vel is Dictionary:
		(vel as Dictionary)["dx"] = dx / len * speed
		(vel as Dictionary)["dy"] = dy / len * speed


static func _at(world: Variant, ent: int, tile: Vector2i, reach: float) -> bool:
	var pos: Variant = world.components.get_component(ent, "position")
	if not pos is Dictionary:
		return false
	var dx: float = float(tile.x) + 0.5 - float((pos as Dictionary)["x"])
	var dy: float = float(tile.y) + 0.5 - float((pos as Dictionary)["y"])
	return dx * dx + dy * dy <= reach * reach


static func _still(world: Variant, ent: int) -> void:
	var vel: Variant = world.components.get_component(ent, "velocity")
	if vel is Dictionary:
		(vel as Dictionary)["dx"] = 0.0
		(vel as Dictionary)["dy"] = 0.0


static func _stop(world: Variant, ent: int) -> void:
	if world.components.has_component(ent, "sleeping"):
		SimNeeds.wake(world, ent)
	world.components.remove(ent, "job")
	_still(world, ent)


static func _injured(world: Variant, ent: int) -> bool:
	var inj: Variant = world.components.get_component(ent, "injuries")
	if inj is Dictionary and not ((inj as Dictionary).get("wounds", []) as Array).is_empty():
		return true
	var body: Variant = world.components.get_component(ent, "body")
	if body is Dictionary:
		for p in ["head", "torso", "arms", "legs"]:
			if int((body as Dictionary).get(p, 40)) < 30:
				return true
	return false
