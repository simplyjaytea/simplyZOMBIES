class_name SimJobs
extends RefCounted

# Work grid + Need seek (0003, 0011). Need seek beats Jobs. A* is survivor-only.
# ponytail: one job dict per NPC; stub columns store a number and do nothing.

const SimPath = preload("res://sim/path.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimTreatment = preload("res://sim/modules/treatment.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimHomeRes = preload("res://sim/home.gd")
const SimCombat = preload("res://sim/combat.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const SimWeather = preload("res://sim/modules/weather.gd")
const Clock = preload("res://sim/time/clock.gd")
const SimContainers = preload("res://sim/modules/containers.gd")
const SimSightings = preload("res://sim/modules/sightings.gd")

const COLUMNS: Array[String] = [
	"Firefight", "Patient", "Doctor", "Rest", "Cook", "Hunt", "Construct", "Repair",
	"Haul", "Scavenge", "Farm", "Water", "Craft", "Modify", "Butcher", "Clean", "Guard", "Bury",
]
const CONSUMERS: Array[String] = ["Haul", "Scavenge", "Construct", "Cook", "Doctor", "Rest", "Patient", "Guard", "Water", "Clean", "Bury", "Repair"]
# How far from home a colonist works the ground: Haul and Scavenge reach only this far from the
# annex's centre, in tiles. The whole of a 64-tile map, the neighbourhood of a 256 one -- the
# far district stays the player's run (docs/02), and it is also where the boot's wanderers are:
# the Guard slice measured Ellis grabbed sixteen times in a day hauling the nearest loose item
# from the far edge. The owner's decision 10, 2026-09-06; the number is a first cut.
#
# Since the outpost slice it is a radius around **each place the colony lives**, not one disc around
# home: `_near_home` asks `SimHome.near_any`. That is what makes an outpost worth building --
# docs/12's expanding radius says the good ground moves away from you over a run, and this constant
# is where that bites. The number did not change; what changed is how many circles it draws.
const HOME_RADIUS_TILES: float = 40.0
const COOK_TICKS: int = 2400
const INSPECT_TICKS: int = 300
const WATER_TICKS: int = 40
const CLEAN_TICKS: int = 40
const BURY_TICKS: int = 40
const REPAIR_TICKS: int = 80
const REACH: float = 1.5
const EMPTY_BOTTLE: String = "item.water.bottle.empty"


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
			d["Scavenge"] = 2
			d["Construct"] = 2
			d["Cook"] = 3
			d["Rest"] = 2
			d["Doctor"] = 4
			d["Water"] = 2
			d["Clean"] = 3
			d["Bury"] = 2
			d["Repair"] = 2
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
			for c in ["Haul", "Scavenge", "Construct", "Cook", "Doctor", "Rest", "Water", "Clean", "Bury", "Repair"]:
				d[c] = 3
			if injured:
				d["Patient"] = 3
	return d


static func attach(world: Variant, entity: int, focus: String = "Auto", row: Dictionary = {}) -> void:
	var r: Dictionary = row if not row.is_empty() else preset(focus, _injured(world, entity))
	for c in COLUMNS:
		if not r.has(c):
			r[c] = 0
	var jp: Dictionary = {"focus": focus, "cols": r}
	# An authored row (a unique's content) is kept beside the live one, because a focus change
	# used to replace the whole row with a preset and one click on Ellis's focus word destroyed
	# the `Guard 1` his content wrote. `set_focus` overlays the preset on this and Manual restores
	# it; a generated survivor has none and gets exactly the preset, as before.
	if not row.is_empty():
		jp["authored"] = r.duplicate()
	world.components.set_component(entity, "jobPriorities", jp)


# `by` is provenance, not flavour: "player" when a person chose this focus, "auto" when the sim
# did. `SimSkills`'s daily drift refuses to move anybody whose focus reads "player", which is
# docs/07's "never touch anything you've manually locked" made mechanical. A component minted
# before the field existed reads as "auto", which is what it was.
static func set_focus(world: Variant, entity: int, focus: String, by: String = "auto") -> void:
	var jp: Variant = world.components.get_component(entity, "jobPriorities")
	var injured: bool = _injured(world, entity)
	var authored: Dictionary = {}
	if jp is Dictionary and (jp as Dictionary).get("authored", null) is Dictionary:
		authored = (jp as Dictionary)["authored"] as Dictionary
	if focus == "Manual" and jp is Dictionary:
		(jp as Dictionary)["focus"] = "Manual"
		(jp as Dictionary)["focusSetBy"] = by
		# Manual on a survivor whose content wrote a row is that row again, byte for byte.
		if not authored.is_empty():
			(jp as Dictionary)["cols"] = authored.duplicate()
		world.events.publish({"type": "job.focus_changed", "entity": entity, "focus": "Manual"})
		return
	var row: Dictionary = preset(focus, injured)
	# The preset wins where it speaks; the authored row survives where the preset is silent.
	for c in COLUMNS:
		if int(row.get(c, 0)) == 0 and int(authored.get(c, 0)) > 0:
			row[c] = int(authored[c])
	var next: Dictionary = {"focus": focus, "cols": row, "focusSetBy": by}
	if not authored.is_empty():
		next["authored"] = authored
	world.components.set_component(entity, "jobPriorities", next)
	world.events.publish({"type": "job.focus_changed", "entity": entity, "focus": focus})


static func set_priority(world: Variant, entity: int, column: String, value: int) -> void:
	var jp: Variant = world.components.get_component(entity, "jobPriorities")
	if not jp is Dictionary:
		attach(world, entity, "Manual")
		jp = world.components.get_component(entity, "jobPriorities")
	(jp as Dictionary)["focus"] = "Manual"
	# Hand-editing a cell of the grid *is* a person's choice, so it carries the same provenance
	# the `job.focus` command does. Without this line the forced flip to Manual left `focusSetBy`
	# reading "auto", and the daily drift -- which asks provenance, not the focus name -- was free
	# to move a survivor off a row the player had just set by hand.
	(jp as Dictionary)["focusSetBy"] = "player"
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
					# The one path a person's own choice arrives on, so it is the one place
					# that stamps "player" on it -- with one exception, and it is the whole
					# reason the choice is Focus rather than a second toggle beside it.
					# Choosing **Auto** is a handback: the player is saying "you decide",
					# which is the opposite of a lock. Stamped "player" it would be a lock,
					# and a survivor put back on Auto would be frozen out of drift for the
					# rest of the run with nothing on screen to say so -- an irreversible
					# choice made by clicking the word that means "not my problem".
					var picked: String = String(c.get("focus", "Auto"))
					set_focus(w, int(c.get("entity", -1)), picked, "auto" if picked == "Auto" else "player")
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
	# A hunger or thirst crisis is not a stop: the seek below ranks an empty pool first and the
	# survivor walks (at `SimNeeds.walk_mul`'s half pace) to whatever will end it. This used to
	# `_stop` and return here, so a colonist at zero hunger died on the starvation clock beside a
	# full pantry -- the crisis dead-end, closed 2026-09-06 (the playable state).
	if String(n.get("crisis", "none")) == "passed_out":
		return
	var seek: String = SimNeeds.seek_kind(world, ent)
	var job: Variant = world.components.get_component(ent, "job")
	if seek != "":
		var hard: bool = false
		if SimNeeds.POOLS.has(seek):
			hard = float(n.get(seek, 100.0)) <= 0.0
		elif seek == "temperature":
			# Both ends of the ladder now: heatstroke drops the tool the same way freezing does.
			var t: String = String(n.get("temperature", ""))
			hard = t == "extremely_cold" or t == "extremely_hot"
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
	# Refusing assigned jobs, checked here rather than in _pick and for a measured reason: a
	# survivor who has settled into a standing job never picks again. Guard and Rest have
	# ticksLeft 0 and no completion, so an NPC that took Guard on tick one held it for the whole
	# run -- gating the refusal on _pick made it fire exactly never in a booted colony. Placed
	# after the seek branch above, so a sulking survivor still eats, drinks and sleeps: this is a
	# refusal to *work*, not a refusal to live.
	if _sulking(world, ent):
		return
	# Dusk calls a survivor with Guard on their row to the post. Only a job that has not begun
	# a channel (ticksLeft 0: a walk, a Rest, a Patient) is dropped for it -- the soft-seek rule
	# above already draws that line -- and only where Guard outranks the job in the row's own
	# order, so Mara (Doctor 1, Guard 2) finishes doctoring before she stands the gate.
	if job is Dictionary and _post_calls(world, ent, job as Dictionary):
		_stop(world, ent)
		job = null
	# Empty hands come before any work: an unarmed colonist re-arms from their pack at once, or
	# walks to the nearest working weapon on the ground near home (the stockpile's included --
	# a stocked item lies on its tile). A channel already begun finishes first; a Rearm walk is
	# never dropped for another Rearm. Armed never swaps.
	if _unarmed(world, ent) and (not job is Dictionary or (String((job as Dictionary).get("kind", "")) != "Rearm" and int((job as Dictionary).get("ticksLeft", 0)) == 0)):
		var rearm: Dictionary = _rearm_job(world, ent)
		if not rearm.is_empty():
			if job is Dictionary:
				_stop(world, ent)
			world.components.set_component(ent, "job", rearm)
			job = rearm
	if job is Dictionary:
		# A storm sends everybody in: a job already under way outdoors is dropped here rather
		# than inside _advance_job, so the walk-to-it path and the work at it both stop on the
		# same tick and the claim is released the way any abandoned job's is.
		if _refused_outdoors(world, ent, job as Dictionary):
			_stop(world, ent)
			return
		# The watch ends at dawn wherever the guard stands -- on the post or still walking to
		# it -- and completes (`job.completed`, the Endurance point). Here rather than in the
		# Guard arm alone, because `_advance_job` walks a job to its tile before its arm runs,
		# and since the post moved inside the gate (the doors slice) a guard called late can
		# still be a step short of it when the sky lightens.
		if String((job as Dictionary).get("kind", "")) == "Guard" and not _watch_hours(world):
			_stop(world, ent, "Guard")
			return
		_advance_job(world, ent, job as Dictionary)
		return
	_pick(world, ent)


# Is this job outdoors under a sky that refuses outdoor work? Storm is the only kind that says
# `outdoorWork: false` today (docs/adr/0016), and this is the whole of what that means.
#
# Guard is exempt on purpose: standing the gate through a storm is watch, not work, and the one
# thing a colony most needs done on the night it cannot hear anything coming. Rest is exempt for
# the same reason it is not in the ranked list of things weather can veto -- a bed is indoors and
# sleeping is not labour. Need-seek never reaches here at all: it returns above, so a survivor
# still walks out to the well when they are dehydrating. This is a refusal to *work* in the rain,
# not a refusal to live in it -- the same distinction `_sulking` draws directly above.
#
# The tile is `_job_tile`'s, and where that answers (-1, -1) -- Haul, Cook, Doctor and Rest name
# an entity, not a tile, and the entity may be stowed in somebody's pack -- the target's own
# position stands in. No tile at all means nothing to judge, so the job is allowed: refusing on a
# tile we could not resolve would idle a colony for a reason nothing reports.
static func _refused_outdoors(world: Variant, _ent: int, job: Dictionary) -> bool:
	if SimWeather.outdoor_work_allowed(world):
		return false
	if world.tilemap == null:
		return false
	var kind: String = String(job.get("kind", ""))
	if kind == "Guard" or kind == "Rest":
		return false
	var tile: Vector2i = _job_tile(world, job)
	if tile.x < 0 or tile.y < 0:
		tile = _entity_tile(world, int(job.get("target", -1)))
	if tile.x < 0 or tile.y < 0:
		return false
	return not SimTileMap.is_indoors(world.tilemap, tile.x, tile.y)


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
		if _refused_outdoors(world, ent, target):
			continue
		world.components.set_component(ent, "job", target)
		if kind == "Haul" or kind == "Construct":
			var n: Dictionary = SimNeeds.of(world, ent)
			n["dirtyWake"] = true
		return


# Is it the watch's hour, and does this survivor's row put Guard ahead of the job in hand?
static func _post_calls(world: Variant, ent: int, job: Dictionary) -> bool:
	if not _watch_hours(world):
		return false
	var kind: String = String(job.get("kind", ""))
	if kind == "Guard" or int(job.get("ticksLeft", 0)) > 0:
		return false
	var jp: Variant = world.components.get_component(ent, "jobPriorities")
	if not jp is Dictionary:
		return false
	var cols: Dictionary = (jp as Dictionary).get("cols", {}) as Dictionary
	var guard_p: int = int(cols.get("Guard", 0))
	if guard_p <= 0:
		return false
	var kind_p: int = int(cols.get(kind, 0))
	if kind_p <= 0:
		return true
	# The same order `_pick` sorts by: priority, then the name.
	return guard_p < kind_p or (guard_p == kind_p and "Guard" < kind)


# Guard is a dusk-to-dawn post (the owner's 2026-09-06 call): the day belongs to the rest of the
# row. Before this the post was handed out at any hour and never completed, so Ellis (Guard 1)
# stood the gate from tick one for the whole run and nothing in the boot colony was ever hauled,
# cooked or built.
static func _watch_hours(world: Variant) -> bool:
	var phase: int = Clock.phase_of(int(world.tick))
	return phase == Clock.Phase.Dusk or phase == Clock.Phase.Night


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
		"Scavenge":
			return _scavenge_work(world, ent, x, y)
		"Construct":
			return _construct_work(world, x, y)
		"Cook":
			return _cook_work(world, ent)
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
			# The post is the map's gate, not a constant. A district with no gate anchor has
			# nothing to stand on, so there is no Guard job to hand out -- and by day there is
			# no watch to keep, so the row's next column gets the survivor instead.
			if not _watch_hours(world):
				return {}
			var post: Vector2i = _post_tile(world)
			if post.x < 0 or post.y < 0:
				return {}
			return {"kind": "Guard", "tx": post.x, "ty": post.y, "ticksLeft": 0, "path": [], "pathGen": -1}
		"Water":
			return _water_work(world, ent, x, y)
		"Clean":
			return _clean_work(world, ent, x, y)
		"Bury":
			return _bury_work(world, x, y)
		"Repair":
			return _repair_work(world, ent, x, y)
	return {}


static func _water_work(world: Variant, ent: int, x: float, y: float) -> Dictionary:
	var bottle: int = _empty_bottle_for(world, ent)
	if bottle < 0:
		return {}
	var well: int = SimNeeds.nearest_water_source(world, x, y)
	if well < 0:
		return {}
	return {"kind": "Water", "target": bottle, "well": well, "ticksLeft": WATER_TICKS, "path": [], "pathGen": -1}


static func _clean_work(world: Variant, ent: int, x: float, y: float) -> Dictionary:
	var n: Dictionary = SimNeeds.of(world, ent)
	if String(n.get("hygiene", "clean")) == "clean":
		return {}
	var well: int = SimNeeds.nearest_water_source(world, x, y)
	if well < 0:
		return {}
	return {"kind": "Clean", "well": well, "ticksLeft": CLEAN_TICKS, "path": [], "pathGen": -1}


static func _bury_work(world: Variant, x: float, y: float) -> Dictionary:
	var dump: Vector2i = _corpse_dump(world)
	if dump.x < 0:
		return {}
	var best: int = -1
	var best_d: float = 1e12
	for c in world.components.query(["corpse", "position"]):
		var p: Variant = world.components.get_component(int(c), "position")
		if not p is Dictionary:
			continue
		var cx: int = floori(float((p as Dictionary)["x"]))
		var cy: int = floori(float((p as Dictionary)["y"]))
		if cx == dump.x and cy == dump.y:
			# Already at dump — bury in place.
			return {"kind": "Bury", "target": int(c), "carrying": false, "ticksLeft": BURY_TICKS, "path": [], "pathGen": -1}
		var dx: float = float((p as Dictionary)["x"]) - x
		var dy: float = float((p as Dictionary)["y"]) - y
		var d: float = dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = int(c)
	if best < 0:
		return {}
	return {"kind": "Bury", "target": best, "carrying": false, "ticksLeft": BURY_TICKS, "path": [], "pathGen": -1}


static func _repair_work(world: Variant, ent: int, x: float, y: float) -> Dictionary:
	var item: int = _worn_item_for(world, ent)
	if item < 0:
		return {}
	if _material_for(world, ent, SimFortify.recipe_kind("repair")) < 0:
		return {}
	var fires: Array[int] = world.components.query(["campfire"])
	if fires.is_empty():
		return {}
	return {"kind": "Repair", "target": item, "fire": fires[0], "ticksLeft": REPAIR_TICKS, "path": [], "pathGen": -1}


static func _worn_item_for(world: Variant, ent: int) -> int:
	for item in SimInventory.carried_items(world, ent):
		if _needs_repair(world, item):
			return item
	for item2 in SimNeeds.stockpile_items(world):
		if _needs_repair(world, item2):
			return item2
	return -1


static func _needs_repair(world: Variant, item: int) -> bool:
	var c: Variant = world.components.get_component(item, "condition")
	if not c is Dictionary:
		return false
	var cur: float = float((c as Dictionary).get("current", 1.0))
	var ceil: float = float((c as Dictionary).get("ceiling", 1.0))
	return cur < ceil


## The nearest unit of a build material this body can reach -- their own pockets first, then the
## stockpile. Repair is the one recipe that is not a SimFortify channel, and it used to carry its
## own copy of the `item.scrap.metal` weld; its substance now comes out of SimFortify.RECIPES like
## every other recipe's, so there is one place a recipe's material is written down. An empty or
## unknown kind matches nothing rather than matching everything, because `material_of` answers ""
## for an ordinary item and "" == "" would otherwise repair a gun with a tin of beans.
static func _material_for(world: Variant, ent: int, kind: String) -> int:
	if not SimFortify.MATERIAL_KINDS.has(kind):
		return -1
	for item in SimInventory.carried_items(world, ent):
		if SimFortify.material_of(world, int(item)) == kind:
			return int(item)
	for item2 in SimNeeds.stockpile_items(world):
		if SimFortify.material_of(world, int(item2)) == kind:
			return int(item2)
	return -1


static func _empty_bottle_for(world: Variant, ent: int) -> int:
	for item in SimInventory.carried_items(world, ent):
		var b: Variant = world.components.get_component(item, "itemBase")
		if b is Dictionary and String((b as Dictionary).get("baseId", "")) == EMPTY_BOTTLE:
			return item
	for item2 in SimNeeds.stockpile_items(world):
		var b2: Variant = world.components.get_component(item2, "itemBase")
		if b2 is Dictionary and String((b2 as Dictionary).get("baseId", "")) == EMPTY_BOTTLE:
			return item2
	return -1


static func _anyone_buries(world: Variant) -> bool:
	for e in world.components.query(["jobPriorities", "identity"]):
		if world.components.has_component(int(e), "controlled"):
			continue
		if int(e) == int(world.player):
			continue
		var jp: Variant = world.components.get_component(int(e), "jobPriorities")
		if not jp is Dictionary:
			continue
		if int(((jp as Dictionary).get("cols", {}) as Dictionary).get("Bury", 0)) > 0:
			return true
	return false


# Where home is. The ladder -- camp, then the annex's centre, then the player's start where a map
# has no annex -- moved wholesale into `SimHome.centre` when the camp slice made home relocatable.
#
# **Its one caller is `_near_home`**, and the comment that used to stand here said otherwise: it
# claimed `_post_tile`, `_corpse_dump` and `_stock_drop` hung off this too, "all for one edit". They
# did not -- all three read `SimTileMap` directly -- so the camp slice moved the Haul/Scavenge/Rearm
# radius and nothing else, while three sentences in the record said it had moved four things. The
# post and the dump follow home now (see `_post_tile` and `_corpse_dump`); `_stock_drop` still does
# not, on purpose, because the stockpile is the annex's *indoor floor* and a camp has no roof.
static func _home_centre(world: Variant) -> Vector2:
	return SimHomeRes.centre(world)


# Home's radius, **or any standing camp's**. The name is still `_near_home` because that is what its
# three callers are asking -- "will a colonist work this ground" -- and the answer became "yes, if it
# is near anywhere we live" when outposts started to mean something. `SimHome.near_any` owns the rule.
static func _near_home(world: Variant, x: float, y: float) -> bool:
	return SimHomeRes.near_any(world, x, y, HOME_RADIUS_TILES)


# The nearest container this survivor remembers seeing, unsearched, near home and not already
# another colonist's claim. The claim is the Cook's `reserved` seam, so two scavengers never
# walk to one cupboard. The job carries the box's tile, so `_job_tile` walks to it.
static func _scavenge_work(world: Variant, ent: int, x: float, y: float) -> Dictionary:
	var best: int = -1
	var best_d: float = 1e12
	var best_at: Vector2i = Vector2i(-1, -1)
	for row in SimSightings.known_containers(world, ent):
		var box: int = int((row as Dictionary).get("e", -1))
		var s: Variant = world.components.get_component(box, "searchable")
		if not s is Dictionary or bool((s as Dictionary).get("searched", false)):
			continue
		var p: Variant = world.components.get_component(box, "position")
		if not p is Dictionary:
			continue
		var bx: float = float((p as Dictionary)["x"])
		var by: float = float((p as Dictionary)["y"])
		if not _near_home(world, bx, by):
			continue
		if _is_unreachable(world, int(box)):
			continue
		if _claim_live(world, box):
			continue
		var dx: float = bx - x
		var dy: float = by - y
		var d: float = dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = box
			best_at = Vector2i(floori(bx), floori(by))
	if best < 0:
		return {}
	world.components.set_component(best, "reserved", {"by": ent, "job": "Scavenge"})
	return {"kind": "Scavenge", "target": best, "tx": best_at.x, "ty": best_at.y, "ticksLeft": 0, "path": [], "pathGen": -1}


# At the box: open it through the module, the way a job eats through `SimNeeds.eat` -- commands
# are the player's channel, not the sim's. The yield lands on the ground beside the box and Haul
# carries it home. A box somebody else emptied on the way completes nothing.
static func _do_scavenge(world: Variant, ent: int, job: Dictionary) -> void:
	var box: int = int(job.get("target", -1))
	var result: Dictionary = SimContainers.search(world, ent, box)
	if bool(result.get("ok", false)):
		_stop(world, ent, "Scavenge")
	else:
		_stop(world, ent)


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
		if not _near_home(world, float((p as Dictionary)["x"]), float((p as Dictionary)["y"])):
			continue
		if _is_unreachable(world, int(item)):
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
		# Corpse haul-to-dump only when nobody has Bury enabled (ADR 0013 overflow).
		if _anyone_buries(world):
			return {}
		var dump: Vector2i = _corpse_dump(world)
		if dump.x < 0:
			return {}
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
	# Hoisted at loop entry: this walks the whole annex footprint, and the rect is a lookup on the
	# map now rather than a constant.
	var annex: Rect2i = SimTileMap.annex_rect(world.tilemap)
	if annex.size.x <= 0 or annex.size.y <= 0:
		return {}
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: float = 1e12
	for j in range(annex.position.y, annex.position.y + annex.size.y):
		for i in range(annex.position.x, annex.position.x + annex.size.x):
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
	var annex: Rect2i = SimTileMap.annex_rect(world.tilemap)
	if annex.size.x <= 0 or annex.size.y <= 0:
		return Vector2i(-1, -1)
	for j in range(annex.position.y, annex.position.y + annex.size.y):
		for i in range(annex.position.x, annex.position.x + annex.size.x):
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


# Cook claims its ingredient. Before this, nothing marked the raw item as spoken for and the
# completion did not re-check, so two cooks assigned in one tick both targeted the same raw and,
# 2400 ticks later, the first despawned it and the second cooked a meal out of nothing -- the
# `_do_cook` spawn was unconditional (docs/23's defect list, "Cook has no claim on its
# ingredient"). The claim is a `reserved` component on the item, live only while its holder still
# holds this very job; `_stock_base` skips a live claim and erases a stale one, `_stop` releases it,
# and `_do_cook` cooks nothing when the raw is gone or is somebody else's.
static func _cook_work(world: Variant, ent: int) -> Dictionary:
	var raw: int = _stock_base(world, "item.food.raw")
	if raw < 0:
		return {}
	var fires: Array[int] = world.components.query(["campfire"])
	if fires.is_empty():
		return {}
	world.components.set_component(raw, "reserved", {"by": ent, "job": "Cook"})
	return {"kind": "Cook", "target": raw, "fire": fires[0], "ticksLeft": COOK_TICKS, "path": [], "pathGen": -1, "stage": "goto"}


# Is this item's claim still held? Live means the holder is alive to the job system and carries a
# job of the claimed kind targeting this item. Anything else -- the holder died (`_make_corpse`
# removes `job` directly), was re-assigned, or finished -- is stale, and a stale claim is erased on
# sight rather than left to block the pantry forever.
static func _claim_live(world: Variant, item: int) -> bool:
	var r: Variant = world.components.get_component(item, "reserved")
	if not (r is Dictionary):
		return false
	var by: int = int((r as Dictionary).get("by", -1))
	var job: Variant = world.components.get_component(by, "job")
	if job is Dictionary and String((job as Dictionary).get("kind", "")) == String((r as Dictionary).get("job", "")) and int((job as Dictionary).get("target", -1)) == item:
		return true
	world.components.remove(item, "reserved")
	return false


# Release the claim `ent` holds on its job's target, if the target carries one in ent's name.
static func _release_claim(world: Variant, ent: int, job: Dictionary) -> void:
	var target: int = int(job.get("target", -1))
	if target < 0:
		return
	var r: Variant = world.components.get_component(target, "reserved")
	if r is Dictionary and int((r as Dictionary).get("by", -1)) == ent:
		world.components.remove(target, "reserved")


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
			if _claim_live(world, int(item)):
				continue
			return item
	return -1


# --- mood consequences (docs/04) -----------------------------------------------------------
#
# "Low mood does not produce a rage meltdown. It produces: slower work, more mistakes ...
# refusing assigned jobs." Three of the four consequences land here; the fourth (arguments) is in
# needs.gd, because it is about mood rather than about work.
#
# Bands come from SimNeeds.mood_band, which is the one place a mood number becomes a word. Nothing
# in this file compares against a mood threshold of its own.

# A miserable worker loses one tick of progress in this many; a low one, one in LOW_SLOW_EVERY.
# Deliberately a skipped tick on a schedule rather than a fractional multiplier: `ticksLeft` is an
# integer countdown in seven places and a 0.75x multiplier on an integer is a rounding argument
# waiting to happen. Keyed off world.tick so it is deterministic and needs no RNG at all -- the
# mistake below is the part that is a gamble, and it should be the only part.
const LOW_SLOW_EVERY: int = 4
const MISERABLE_SLOW_EVERY: int = 2

# A mistake costs back this many ticks of progress, once in MISTAKE_ONE_IN chances, rolled only
# for a miserable worker. Capped at the job's own starting length by the countdown itself: a job
# cannot regress past where it began because `left` is only ever written from here.
const MISTAKE_TICKS: int = 20
const MISTAKE_ONE_IN: int = 200

# Refusing assigned jobs. A priority threshold was the obvious shape and is the wrong one: the
# Auto preset ranks every column at 3, so any threshold either refuses nothing or refuses
# everything, and a survivor who downs tools entirely is exactly the meltdown docs/04 rules out
# ("nobody snaps ... the failure mode is a slow, sour decline").
#
# So a refusal is a *sulk*: a miserable survivor declines to pick up work, one time in
# REFUSE_ONE_IN, and then does nothing for REFUSE_SULK_TICKS before trying again. Work still gets
# done; it gets done later and less predictably, which is what a demoralised colony looks like.
# Bounded by construction -- the sulk expires on its own, so no mood value can leave somebody idle
# forever.
const REFUSE_ONE_IN: int = 12
const REFUSE_SULK_TICKS: int = 300

const MOOD_STREAM: String = "mood"


# Whether this survivor is currently declining to work, and whether they start doing so now.
static func _sulking(world: Variant, ent: int) -> bool:
	var n: Dictionary = SimNeeds.of(world, ent)
	var until: int = int(n.get("refusedUntilTick", -1))
	if int(world.tick) < until:
		return true
	var band: String = SimNeeds.mood_band(world, ent)
	if band != "miserable" and band != "breaking":
		return false
	var rng: Variant = world.rng.stream(MOOD_STREAM)
	if int(rng.call("int_range", 1, REFUSE_ONE_IN)) != 1:
		return false
	n["refusedUntilTick"] = int(world.tick) + REFUSE_SULK_TICKS
	# The assignment goes with it. Dropping a half-finished job loses its progress, which is the
	# cost of a demoralised colony and is the difference between "refused" and "paused".
	if world.components.has_component(ent, "job"):
		_stop(world, ent)
	world.events.publish({"type": "job.refused", "entity": ent, "reason": "mood", "ticks": REFUSE_SULK_TICKS})
	return true


# The one place a job's countdown advances. It was seven copies of the same two lines, which is
# six chances for a work-speed consequence to apply to most jobs and quietly miss one -- the same
# shape as the shambler speed reads. Returns the new `ticksLeft`, already written to the job.
static func _progress(world: Variant, ent: int, job: Dictionary) -> int:
	var left: int = int(job.get("ticksLeft", 0))
	var band: String = SimNeeds.mood_band(world, ent)

	# Slower work. A skipped tick, not a slower one: the job simply does not advance this tick.
	var every: int = 0
	if band == "low":
		every = LOW_SLOW_EVERY
	elif band == "miserable" or band == "breaking":
		every = MISERABLE_SLOW_EVERY
	if every > 0 and int(world.tick) % every == 0:
		job["ticksLeft"] = left
		return left

	left -= 1

	# More mistakes. Progress goes backwards, and it says so, because a job that silently takes
	# longer is indistinguishable from a job that is slow.
	if (band == "miserable" or band == "breaking") and left > 0:
		var rng: Variant = world.rng.stream(MOOD_STREAM)
		if int(rng.call("int_range", 1, MISTAKE_ONE_IN)) == 1:
			left += MISTAKE_TICKS
			world.events.publish({"type": "job.mistake", "entity": ent, "kind": String(job.get("kind", "")), "ticks": MISTAKE_TICKS})

	job["ticksLeft"] = left
	return left


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
		"Rearm":
			_do_rearm(world, ent, job)
		"Scavenge":
			_do_scavenge(world, ent, job)
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
					_stop(world, ent, "Rest")
				else:
					_stop(world, ent, "Rest")
				return
			var bed: int = int(job.get("target", -1))
			if not world.components.has_component(ent, "sleeping"):
				SimNeeds.start_sleep(world, ent, bed)
		"Patient":
			pass
		"Guard":
			# The watch ends at dawn, and that is the first time Guard has ever completed --
			# `job.completed` reaches the skill web (an Endurance point, docs/08's hard nights).
			if not _watch_hours(world):
				_stop(world, ent, "Guard")
		"Water":
			_do_water(world, ent, job)
		"Clean":
			_do_clean(world, ent, job)
		"Bury":
			_do_bury(world, ent, job)
		"Repair":
			_do_repair(world, ent, job)
		_:
			_stop(world, ent)


static func _job_tile(world: Variant, job: Dictionary) -> Vector2i:
	if job.has("tx"):
		return Vector2i(int(job["tx"]), int(job["ty"]))
	var kind: String = String(job.get("kind", ""))
	if kind == "Bury" and bool(job.get("carrying", false)):
		# Absent gate, absent dump: `_corpse_dump` answers (-1, -1), which is this function's own
		# "no tile" value already.
		return _corpse_dump(world)
	if kind in ["Water", "Clean"]:
		if kind == "Water":
			var bottle: int = int(job.get("target", -1))
			# Actor is set in _do_water; until then infer from job holder via target ownership below.
			if bottle >= 0 and world.components.has_component(bottle, "position"):
				var bp: Variant = world.components.get_component(bottle, "position")
				if bp is Dictionary:
					return Vector2i(floori(float((bp as Dictionary)["x"])), floori(float((bp as Dictionary)["y"])))
		var well: int = int(job.get("well", -1))
		if well >= 0:
			var wp: Variant = world.components.get_component(well, "position")
			if wp is Dictionary:
				return Vector2i(floori(float((wp as Dictionary)["x"])), floori(float((wp as Dictionary)["y"])))
	if kind == "Repair":
		var target: int = int(job.get("target", -1))
		if target >= 0 and world.components.has_component(target, "position"):
			var ip: Variant = world.components.get_component(target, "position")
			if ip is Dictionary:
				return Vector2i(floori(float((ip as Dictionary)["x"])), floori(float((ip as Dictionary)["y"])))
		var fire: int = int(job.get("fire", -1))
		var fp: Variant = world.components.get_component(fire, "position")
		if fp is Dictionary:
			return Vector2i(floori(float((fp as Dictionary)["x"])), floori(float((fp as Dictionary)["y"])))
	var t: int = int(job.get("target", -1))
	if job.has("fire") and String(job.get("stage", "")) != "goto-item":
		t = int(job.get("fire", t))
	if t < 0:
		return Vector2i(-1, -1)
	var p: Variant = world.components.get_component(t, "position")
	if not p is Dictionary:
		return Vector2i(-1, -1)
	return Vector2i(floori(float((p as Dictionary)["x"])), floori(float((p as Dictionary)["y"])))


static func _do_water(world: Variant, ent: int, job: Dictionary) -> void:
	var bottle: int = int(job.get("target", -1))
	var well: int = int(job.get("well", -1))
	if bottle < 0 or well < 0:
		_stop(world, ent)
		return
	# Pick up empty bottle from stockpile/ground if needed.
	if not SimInventory.owns(world, ent, bottle):
		if world.components.has_component(bottle, "position"):
			world.components.remove(bottle, "position")
		if not SimInventory.stow(world, ent, bottle):
			_stop(world, ent)
			return
		return
	var well_tile: Vector2i = _entity_tile(world, well)
	if well_tile.x < 0 or not _at(world, ent, well_tile, REACH):
		_walk(world, ent, job, well_tile)
		return
	var left: int = _progress(world, ent, job)
	if left > 0:
		return
	# The well fills a bottle with untreated water; boiling it is a separate act at a lit fire.
	SimNeeds.fill_bottle(world, bottle)
	world.events.publish({"type": "job.water_filled", "entity": ent, "item": bottle})
	_stop(world, ent, "Water")


static func _do_clean(world: Variant, ent: int, job: Dictionary) -> void:
	var well: int = int(job.get("well", -1))
	if well < 0:
		_stop(world, ent)
		return
	var well_tile: Vector2i = _entity_tile(world, well)
	if well_tile.x < 0 or not _at(world, ent, well_tile, REACH):
		_walk(world, ent, job, well_tile)
		return
	var left: int = _progress(world, ent, job)
	if left > 0:
		return
	SimNeeds.wash_at_source(world, ent)
	world.events.publish({"type": "job.cleaned", "entity": ent})
	_stop(world, ent, "Clean")


static func _do_bury(world: Variant, ent: int, job: Dictionary) -> void:
	var corpse: int = int(job.get("target", -1))
	if corpse < 0:
		_stop(world, ent)
		return
	var dump: Vector2i = _corpse_dump(world)
	if dump.x < 0:
		_stop(world, ent)
		return
	if not bool(job.get("carrying", false)):
		if world.components.has_component(corpse, "position"):
			var cp: Variant = world.components.get_component(corpse, "position")
			var ct := Vector2i(floori(float((cp as Dictionary)["x"])), floori(float((cp as Dictionary)["y"])))
			if not _at(world, ent, ct, REACH):
				_walk(world, ent, job, ct)
				return
			world.components.remove(corpse, "position")
		job["carrying"] = true
		SimNeeds.dirt(world, ent, 1)
		return
	if not _at(world, ent, dump, REACH):
		_walk(world, ent, job, dump)
		return
	var left: int = _progress(world, ent, job)
	if left > 0:
		return
	world.despawn(corpse)
	world.events.publish({"type": "job.buried", "entity": ent, "corpse": corpse})
	_stop(world, ent, "Bury")


static func _do_repair(world: Variant, ent: int, job: Dictionary) -> void:
	var item: int = int(job.get("target", -1))
	var fire: int = int(job.get("fire", -1))
	if item < 0 or fire < 0:
		_stop(world, ent)
		return
	if not SimInventory.owns(world, ent, item) and world.components.has_component(item, "position"):
		world.components.remove(item, "position")
		if not SimInventory.stow(world, ent, item):
			_stop(world, ent)
			return
		return
	var scrap: int = _material_for(world, ent, SimFortify.recipe_kind("repair"))
	if scrap < 0:
		_stop(world, ent)
		return
	if not SimInventory.owns(world, ent, scrap) and world.components.has_component(scrap, "position"):
		world.components.remove(scrap, "position")
		if not SimInventory.stow(world, ent, scrap):
			_stop(world, ent)
			return
		return
	var fire_tile: Vector2i = _entity_tile(world, fire)
	if fire_tile.x < 0 or not _at(world, ent, fire_tile, REACH):
		_walk(world, ent, job, fire_tile)
		return
	var left: int = _progress(world, ent, job)
	if left > 0:
		return
	if not _consume_owned(world, scrap):
		_stop(world, ent)
		return
	if not SimItems.repair_item(world, item):
		_stop(world, ent)
		return
	world.events.publish({"type": "job.repaired", "entity": ent, "item": item})
	_stop(world, ent, "Repair")


static func _consume_owned(world: Variant, item: int) -> bool:
	var stack: Variant = world.components.get_component(item, "stack")
	if stack is Dictionary and int((stack as Dictionary).get("count", 1)) > 1:
		(stack as Dictionary)["count"] = int((stack as Dictionary)["count"]) - 1
		return true
	SimInventory.remove_from_container(world, item)
	world.despawn(item)
	return true


# --- re-arm ----------------------------------------------------------------------------------
#
# The playable-state group's eleventh piece. Before this the only `equip` a colonist ever got
# was their kit at spawn: a weapon that wore out was gone (items.gd) and the body was unarmed
# for the rest of the run. `check_m2_npc_combat.gd` REARM.

static func _unarmed(world: Variant, ent: int) -> bool:
	return not world.components.has_component(ent, "meleeWeapon") and not world.components.has_component(ent, "rangedWeapon")


# A weapon is anything the hands take (`equipSlot` primary); working means its condition is
# above zero, or it carries none.
static func _is_working_weapon(world: Variant, item: int) -> bool:
	var slot: Variant = SimInventory.equip_slot_for(world, item)
	if slot == null or String(slot) != "primary":
		return false
	var c: Variant = world.components.get_component(item, "condition")
	if c is Dictionary and float((c as Dictionary).get("current", 1.0)) <= 0.0:
		return false
	return true


# The pack first (equipped at once, no job); else the nearest working weapon lying near home
# -- on the ground or on the stockpile's tiles, both of which are items with a position and no
# container -- as a Rearm walk. Empty when there is nothing to re-arm with.
static func _rearm_job(world: Variant, ent: int) -> Dictionary:
	for carried in SimInventory.carried_items(world, ent):
		if _is_working_weapon(world, int(carried)) and SimInventory.equip(world, ent, int(carried)):
			return {}
	var here: Variant = world.components.get_component(ent, "position")
	if not here is Dictionary:
		return {}
	var hx: float = float((here as Dictionary)["x"])
	var hy: float = float((here as Dictionary)["y"])
	var best: int = -1
	var best_d: float = INF
	for item in SimInventory.ground_items(world):
		if not _is_working_weapon(world, int(item)):
			continue
		if world.components.has_component(int(item), "reserved"):
			continue
		var p: Dictionary = world.components.get_component(int(item), "position") as Dictionary
		var ix: float = float(p["x"])
		var iy: float = float(p["y"])
		if not _near_home(world, ix, iy):
			continue
		if _is_unreachable(world, int(item)):
			continue
		var d: float = (ix - hx) * (ix - hx) + (iy - hy) * (iy - hy)
		if d < best_d:
			best_d = d
			best = int(item)
	if best < 0:
		return {}
	return {"kind": "Rearm", "target": best, "ticksLeft": 0, "path": [], "pathGen": -1}


static func _do_rearm(world: Variant, ent: int, job: Dictionary) -> void:
	var item: int = int(job.get("target", -1))
	if item < 0 or not world.components.has_component(item, "position") or not _is_working_weapon(world, item):
		_stop(world, ent)
		return
	var tile: Vector2i = _entity_tile(world, item)
	if not _at(world, ent, tile, REACH):
		_walk(world, ent, job, tile)
		return
	SimInventory.equip(world, ent, item)
	_stop(world, ent, "Rearm")


static func _entity_tile(world: Variant, ent: int) -> Vector2i:
	var p: Variant = world.components.get_component(ent, "position")
	if not p is Dictionary:
		return Vector2i(-1, -1)
	return Vector2i(floori(float((p as Dictionary)["x"])), floori(float((p as Dictionary)["y"])))


static func _do_haul(world: Variant, ent: int, job: Dictionary) -> void:
	var item: int = int(job.get("target", -1))
	if bool(job.get("carrying", false)):
		# Corpses skip the Stockpile — ADR 0010: outdoor dump only (avoids stockpile↔dump oscillation).
		if bool(job.get("corpse", false)):
			var dump: Vector2i = _corpse_dump(world)
			if dump.x < 0:
				_stop(world, ent)
				return
			if not _at(world, ent, dump, REACH):
				_walk(world, ent, job, dump)
				return
			world.components.set_component(item, "position", {"x": float(dump.x) + 0.5, "y": float(dump.y) + 0.5})
			SimNeeds.dirt(world, ent, 1)
			_stop(world, ent, "Haul")
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
		_stop(world, ent, "Haul")
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


# The watch stands on the annex side of the gate, not in it: the gate is a door since the doors
# slice, and a body in the doorway is a door that never shuts. The neighbour of `gate_a` inside
# the annex rect that is open floor by class; the gate itself where the map has no annex.
static func _post_tile(world: Variant) -> Vector2i:
	# Home's gate, not the map's: a colony that has moved to a camp posts its night watch at the
	# camp. This read was missed by the camp slice while its record claimed it had been made -- the
	# watch stood at an annex nobody lived in any more.
	var gate: Vector2i = SimHomeRes.gate_a(world)
	if gate.x < 0 or gate.y < 0:
		return gate
	var annex: Rect2i = SimHomeRes.rect(world)
	if annex.size.x <= 0:
		return gate
	for step in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var t: Vector2i = gate + (step as Vector2i)
		if not annex.has_point(t):
			continue
		if SimTileMap.SOLID[SimTileMap.tile_at(world.tilemap, t.x, t.y)]:
			continue
		return t
	return gate


# Two tiles south of the gate (ADR 0010), measured from where the map says the gate is. Returns
# the absent sentinel on a district with no gate anchor, and every caller checks it -- there is no
# outdoor dump when there is no gate to put one south of.
static func _corpse_dump(world: Variant) -> Vector2i:
	# Home's gate, for the same reason as the watch one function up: a colony living at a camp does
	# not carry its dead back to the annex it left.
	var gate: Vector2i = SimHomeRes.gate_a(world)
	if gate.x < 0 or gate.y < 0:
		return Vector2i(-1, -1)
	return Vector2i(gate.x, gate.y + 2)


# The stamped annex, and **deliberately not `SimHome.rect`** -- the one home reader that does not
# follow a camp. `SimNeeds.is_stockpile_tile` is "indoors, floor, inside the annex", and a camp has
# no roof to be indoors under, so a camp-relative drop point would be a stockpile the weather rains
# into. Giving a camp a real one is the "evolve a camp" work in docs/23's what's left. Until then a
# far outpost extends what colonists *collect* and not where they *put it*, which is the trade the
# reach slice measured rather than hid.
static func _stock_drop(world: Variant) -> Vector2i:
	var annex: Rect2i = SimTileMap.annex_rect(world.tilemap)
	if annex.size.x <= 0 or annex.size.y <= 0:
		return Vector2i(-1, -1)
	for j in range(annex.position.y, annex.position.y + annex.size.y):
		for i in range(annex.position.x, annex.position.x + annex.size.x):
			if SimNeeds.is_stockpile_tile(world, i, j) and _bed_at(world, i, j) < 0 and _campfire_at(world, i, j) < 0:
				return Vector2i(i, j)
	return Vector2i(-1, -1)


static func _do_construct(world: Variant, ent: int, job: Dictionary) -> void:
	var left: int = _progress(world, ent, job)
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
	_stop(world, ent, "Construct")


static func _do_cook(world: Variant, ent: int, job: Dictionary) -> void:
	var fire: int = int(job.get("fire", -1))
	SimNeeds.set_lit(world, fire, true, true)
	var left: int = _progress(world, ent, job)
	if left > 0:
		return
	var raw: int = int(job.get("target", -1))
	# Re-validated at completion: the raw is still there and still this cook's. A raw that was
	# eaten, hauled off or cooked by somebody else cooks nothing -- no meal, no `job.completed`,
	# no Survival point -- and the fire goes back to idle exactly as it would after a real meal.
	var r: Variant = world.components.get_component(raw, "reserved")
	var mine: bool = r is Dictionary and int((r as Dictionary).get("by", -1)) == ent
	if not world.components.has_component(raw, "itemBase") or not mine:
		SimNeeds.set_lit(world, fire, true, false)
		_stop(world, ent)
		return
	world.components.remove(raw, "position")
	world.despawn(raw)
	var cooked: int = SimItems.spawn_item(world, "item.food.cooked", {"tier": "scavenged"})
	SimNeeds.mark_spoilage(world, cooked, "item.food.cooked")
	var drop: Vector2i = _stock_drop(world)
	if drop.x >= 0:
		world.components.set_component(cooked, "position", {"x": float(drop.x) + 0.5, "y": float(drop.y) + 0.5})
	SimNeeds.set_lit(world, fire, true, false)
	_stop(world, ent, "Cook")


static func _do_doctor(world: Variant, ent: int, job: Dictionary) -> void:
	var left: int = _progress(world, ent, job)
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
	_stop(world, ent, "Doctor")


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


# The NPC Doctor job's hands. It fetches its own supply and then calls the same effect leaf
# the player's treatment channel calls -- melee.gd:133-136 already makes the argument about
# two intakes with independently written effects, and this one had drifted exactly that way:
# it healed the torso and only the torso, ignoring `injuries.wounds` entirely, so a Doctor
# could spend a full job on a survivor whose only problem was a ruined arm and change nothing.
static func _treat(world: Variant, ent: int, target: int) -> void:
	# With a dressing, the wound gets dressed; without one, the Doctor still stops the bleed
	# with their hands and it goes down as no dressing. The old version healed the same amount
	# either way, which made the bandage decorative.
	var tier: String = "cloth" if _fetch_bandage(world, ent) else "none"
	var mul: float = SimNeeds.treat_sepsis_mul(world, ent)
	world.events.publish({"type": "sepsis.checked", "entity": target, "mul": mul, "kind": "treat", "treater": ent})
	SimWounds.dress_worst(world, ent, target, tier)


# Pull one bandage out of the stockpile into the treater's hands if they are not carrying one.
#
# The old version despawned the item when `stow` failed and then healed anyway -- a bandage
# destroyed, never consumed, and the treatment free. Now the item goes back where it came from
# if it cannot be carried, and the caller finds out nothing was fetched.
# The colonist's dressing, ranked by `bandageTier` exactly as the player's is. This named
# `item.bandage.cloth` in three places, which meant a doctor holding a sterile dressing would walk
# to the stockpile to fetch a rag, and a doctor holding only sterile dressings would report having
# no bandage at all. The player's path has ranked by tier since treatment landed; this was the one
# reader that never caught up, and the two paths disagreeing about what counts as a bandage is the
# same defect as the two validators disagreeing about what counts as content.
static func _fetch_bandage(world: Variant, ent: int) -> bool:
	var carried: Dictionary = SimInventory.best_by_content_key(
		world, ent, SimTreatment.TIER_KEY, SimTreatment.TIER_ORDER, "tier")
	if not carried.is_empty() and SimNeeds.consume_base(world, ent, String(carried.get("baseId", ""))):
		return true
	# Nothing in the pack: take the best dressing off the stockpile floor, by the same ranking
	# rather than by the first one the scan happens to reach.
	var best_rank: int = SimTreatment.TIER_ORDER.size()
	var chosen: int = -1
	var chosen_id: String = ""
	for item in SimNeeds.stockpile_items(world):
		var base: Variant = SimItems.item_base_of(world, int(item))
		if not (base is Dictionary):
			continue
		var rank: int = SimTreatment.TIER_ORDER.find(String((base as Dictionary).get(SimTreatment.TIER_KEY, "")))
		if rank < 0 or rank >= best_rank:
			continue
		best_rank = rank
		chosen = int(item)
		chosen_id = String((base as Dictionary).get("id", ""))
	if chosen < 0 or chosen_id == "":
		return false
	var pos: Variant = world.components.get_component(chosen, "position")
	world.components.remove(chosen, "position")
	if SimInventory.stow(world, ent, chosen):
		return SimNeeds.consume_base(world, ent, chosen_id)
	# Could not be carried: put it back on the floor rather than destroying it.
	if pos is Dictionary:
		world.components.set_component(chosen, "position", pos)
	return false


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
			var bottle: int = _carry_base(world, ent, SimNeeds.WATER_ID)
			if bottle < 0:
				bottle = _stock_base(world, SimNeeds.WATER_ID)
			if bottle < 0:
				# Nothing clean anywhere. A wash waits; a drink has two more rungs -- boil what the
				# well gave, or, thirsty enough, drink it as it comes.
				if kind == "thirst":
					_seek_untreated(world, ent, x, y)
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
		"relief":
			# The NPC half of the bathroom need. Without this the whole thing would be a mechanism
			# only the player can reach -- a tenth dead socket, and the one every colonist would
			# hit twice a day. Same shape as the rest of this function: walk there, then act.
			var latrine: int = SimNeeds.nearest_latrine(world, x, y)
			if latrine < 0:
				# No latrine anywhere. Nothing to walk to and nothing to refuse -- the pool runs
				# down and `_soil` takes it from here.
				return
			var lp: Variant = world.components.get_component(latrine, "position")
			if lp is Dictionary:
				var lt := Vector2i(floori(float((lp as Dictionary)["x"])), floori(float((lp as Dictionary)["y"])))
				if not _at(world, ent, lt, SimNeeds.LATRINE_REACH):
					var sj4: Dictionary = {"kind": "Seek", "target": latrine, "path": [], "pathGen": -1}
					_walk(world, ent, sj4, lt)
					world.components.set_component(ent, "job", sj4)
					return
			SimNeeds.relieve_at(world, ent, latrine)
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
			# A hot body seeks a roof, never a fire (docs/adr/0016: the heat wave is the first
			# thing that can set the hot bands, and the fire walk below was written for the
			# cold). Indoors is the relief needs.gd hands out -- a body under a roof reads
			# comfortable by day -- so the nearest indoor floor is the target, and a body already
			# under one stands where it is.
			if String(n.get("temperature", "")).ends_with("hot"):
				var roof: Vector2i = _nearest_roof(world, x, y)
				# Walked until the body's *own* tile is the roofed one -- `_nearest_roof` returns
				# that tile once it is. This used to be `not _at(roof, REACH)`, and REACH 1.5
				# reaches a tile from the doorstep outside it: a body one tile short of the door
				# read "arrived", was handed no job, and stood there hot until the sky changed.
				# The eyes slice found it -- twenty boot shamblers had been bending every route
				# the weather gate's SEEK lane walked (a body's tile blocks A*), and with them
				# gone the straight walk ended on the doorstep.
				if roof.x >= 0 and roof != Vector2i(floori(x), floori(y)):
					var sj5: Dictionary = {"kind": "Seek", "target": -1, "path": [], "pathGen": -1}
					_walk(world, ent, sj5, roof)
					world.components.set_component(ent, "job", sj5)
				return
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
const ROOF_SEARCH: int = 32
const ROOF_PATH_TRIES: int = 12


# The nearest indoor, walkable, *reachable* tile in rings out from (x, y), or (-1, -1) when the
# map has none within ROOF_SEARCH -- the shape of SimTileMap.find_open_tile with the roof asked
# of each tile, and a path asked of the first few: the nearest roofed floor is as often as not a
# sealed room's, and a body that targets it stands outside the wall re-targeting it forever.
static func _nearest_roof(world: Variant, x: float, y: float) -> Vector2i:
	var map: Variant = world.tilemap
	if map == null:
		return Vector2i(-1, -1)
	var sx: int = floori(x)
	var sy: int = floori(y)
	if SimTileMap.is_indoors(map, sx, sy) and not SimTileMap.is_solid(map, sx, sy):
		return Vector2i(sx, sy)
	var tried: int = 0
	# The ring's own perimeter, walked edge by edge: 8r tiles a ring rather than the (2r+1)^2
	# square it sits in, which is what a "skip unless on the ring" filter cost (~48,000 probes
	# for a body with no roof in reach, every tick it was hot).
	for radius in range(1, ROOF_SEARCH + 1):
		for i in range(-radius, radius + 1):
			var edge: Array[Vector2i] = [Vector2i(sx + i, sy - radius), Vector2i(sx + i, sy + radius)]
			if absi(i) < radius:
				edge.append(Vector2i(sx - radius, sy + i))
				edge.append(Vector2i(sx + radius, sy + i))
			for cand in edge:
				if cand.x <= 0 or cand.y <= 0 or cand.x >= int(map.w) - 1 or cand.y >= int(map.h) - 1:
					continue
				if not SimTileMap.is_indoors(map, cand.x, cand.y) or SimTileMap.is_solid(map, cand.x, cand.y):
					continue
				if not SimPath.find(world, Vector2i(sx, sy), cand).is_empty():
					return cand
				tried += 1
				if tried >= ROOF_PATH_TRIES:
					return Vector2i(-1, -1)
	return Vector2i(-1, -1)
	return Vector2i(-1, -1)


# The back half of the thirst seek, when there is no clean water in the colony. docs/04: "untreated
# water carries illness" -- so a survivor with an untreated bottle and a campfire walks to the
# fire, lights it if it is out (the same call the Cook job makes, and the same attention cost),
# boils the bottle and drinks it clean. With no fire at all, they drink it as it comes -- but only
# once thirst is below SOFT, because a roll on the illness stream is a price worth paying when the
# alternative is the dehydration clock, and not before. Between SEEK_START and SOFT with no fire
# they wait, which is what the pool running down looks like from the outside.
#
# The `dehydrating` crisis reaches here too, since 2026-09-06: `_tick_one` no longer stops a
# survivor in crisis before the seek runs, so an empty pool is the hardest pressure and the
# survivor walks to the untreated bottle, and to the fire, at half pace.
static func _seek_untreated(world: Variant, ent: int, x: float, y: float) -> void:
	var raw: int = _carry_base(world, ent, SimNeeds.UNTREATED_ID)
	if raw < 0:
		raw = _stock_base(world, SimNeeds.UNTREATED_ID)
	if raw < 0:
		return
	if not SimInventory.owns(world, ent, raw):
		var rp: Variant = world.components.get_component(raw, "position")
		if rp is Dictionary:
			var rt := Vector2i(floori(float((rp as Dictionary)["x"])), floori(float((rp as Dictionary)["y"])))
			if not _at(world, ent, rt, REACH):
				var sj: Dictionary = {"kind": "Seek", "target": raw, "path": [], "pathGen": -1}
				_walk(world, ent, sj, rt)
				world.components.set_component(ent, "job", sj)
				return
			world.components.remove(raw, "position")
			if not SimInventory.stow(world, ent, raw):
				return
	var fire: int = SimNeeds.nearest_campfire(world, x, y, false)
	if fire >= 0:
		var fp: Variant = world.components.get_component(fire, "position")
		if fp is Dictionary:
			var ft := Vector2i(floori(float((fp as Dictionary)["x"])), floori(float((fp as Dictionary)["y"])))
			if not _at(world, ent, ft, CAMPFIRE_STAND):
				var sj2: Dictionary = {"kind": "Seek", "target": fire, "path": [], "pathGen": -1}
				_walk(world, ent, sj2, ft)
				world.components.set_component(ent, "job", sj2)
				return
		var cf: Variant = world.components.get_component(fire, "campfire")
		if cf is Dictionary and not bool((cf as Dictionary).get("lit", false)):
			SimNeeds.set_lit(world, fire, true)
		if bool(SimNeeds.boil(world, ent, fire).get("ok", false)):
			SimNeeds.drink(world, ent)
		return
	if SimNeeds.pressure(float(SimNeeds.of(world, ent).get("thirst", 100.0))) in ["soft", "hard"]:
		SimNeeds.drink_untreated(world, ent)


static func _food_for(world: Variant, ent: int) -> int:
	for item in SimInventory.carried_items(world, ent):
		var b: Variant = world.components.get_component(item, "itemBase")
		if b is Dictionary and SimNeeds.is_food(world, String((b as Dictionary).get("baseId", ""))):
			return item
	for item2 in SimNeeds.stockpile_items(world):
		var b2: Variant = world.components.get_component(item2, "itemBase")
		if b2 is Dictionary and SimNeeds.is_food(world, String((b2 as Dictionary).get("baseId", ""))):
			return item2
	return -1


static func _carry_base(world: Variant, ent: int, base_id: String) -> int:
	for item in SimInventory.carried_items(world, ent):
		var b: Variant = world.components.get_component(item, "itemBase")
		if b is Dictionary and String((b as Dictionary).get("baseId", "")) == base_id:
			return item
	return -1


# "Nobody could route to this, as of this map generation."
#
# Shaped like `reserved` -- a component on the target, read by the work-finders -- rather than a
# blocklist on the world, so it round-trips through a save for free and disappears with the entity.
# It is keyed by `mapGeneration` rather than by tick because that is the thing that can make a route
# appear: a door opened, a barricade broken, a car moved. A stale mark simply stops applying.
static func _mark_unreachable(world: Variant, job: Dictionary, gen: int) -> void:
	var target: int = int(job.get("target", -1))
	if target < 0 or not world.entities.is_alive(target):
		return
	world.components.set_component(target, "unreachable", {"gen": gen})


static func _is_unreachable(world: Variant, target: int) -> bool:
	var mark: Variant = world.components.get_component(target, "unreachable")
	if not (mark is Dictionary):
		return false
	if int((mark as Dictionary).get("gen", -1)) != int(world.mapGeneration):
		# The map moved, so the mark is out of date: clear it and let somebody try again.
		world.components.remove(target, "unreachable")
		return false
	return true


static func _walk(world: Variant, ent: int, job: Dictionary, dest: Vector2i) -> void:
	var pos: Variant = world.components.get_component(ent, "position")
	if not pos is Dictionary:
		return
	var here := Vector2i(floori(float((pos as Dictionary)["x"])), floori(float((pos as Dictionary)["y"])))
	var gen: int = int(world.mapGeneration)
	var path: Array = job.get("path", []) as Array
	# **Plan once per map generation, even when the plan fails.**
	#
	# This condition used to read `pathGen != gen or path.is_empty()`, and an empty path is exactly
	# what `SimPath.find` returns when there is no route -- so an unreachable destination re-ran the
	# whole A* on the next tick, and every tick after, forever. docs/23's defect list has carried
	# that as "an unreachable destination costs a full A* every tick" since the review sweep; this is
	# the line it was talking about. Measured on this container: a reachable 100-tile path costs
	# 5-11 ms and a failing one **132 ms**, so a single colonist standing next to one enclosed item
	# took a booted district from 62.8 ticks/s to 9.8 -- under its own 20 Hz clock.
	#
	# `pathFailGen` is what separates "empty because there is no route" from "empty because the last
	# step was just consumed"; without it, refusing to re-plan on an empty path would strand a body
	# knocked off its route. Both clear when the map generation moves, which is what a door opening
	# or a barricade falling already bumps.
	var failed_gen: int = int(job.get("pathFailGen", -1))
	if int(job.get("pathGen", -1)) != gen or (path.is_empty() and failed_gen != gen):
		var found: Array[Vector2i] = SimPath.find(world, here, dest)
		path.clear()
		# Dict steps so snapshot/fingerprint never sees Vector2i (export smoke).
		for s in found:
			path.append({"x": s.x, "y": s.y})
		job["path"] = path
		job["pathGen"] = gen
		if found.is_empty():
			job["pathFailGen"] = gen
			# And the target is not somewhere anyone can get to right now, so stop offering it.
			# Without this the body drops the job, `_pick` hands back the same nearest candidate on
			# the next tick, and the thrash is the same burn one indirection further out.
			_mark_unreachable(world, job, gen)
			_stop(world, ent)
			return
	if path.is_empty():
		_still(world, ent)
		return
	var step: Variant = path[0]
	var nx: int = 0
	var ny: int = 0
	if step is Dictionary:
		nx = int((step as Dictionary).get("x", 0))
		ny = int((step as Dictionary).get("y", 0))
	elif typeof(step) == TYPE_VECTOR2I:
		var v: Vector2i = step as Vector2i
		nx = v.x
		ny = v.y
	else:
		_still(world, ent)
		return
	var tx: float = float(nx) + 0.5
	var ty: float = float(ny) + 0.5
	var dx: float = tx - float((pos as Dictionary)["x"])
	var dy: float = ty - float((pos as Dictionary)["y"])
	if dx * dx + dy * dy < 0.04:
		path.remove_at(0)
		job["path"] = path
		if path.is_empty():
			_still(world, ent)
		return
	# The step through a closed door opens it (unlatched, so it swings shut behind): the
	# planner routed through it on that promise. The open bumps the map generation, so the
	# path is re-planned next tick through the doorway it now is.
	if SimTileMap.tile_at(world.tilemap, nx, ny) == SimTileMap.Tile.Door and world.is_blocked_tile(nx, ny):
		SimFortify.open_door(world, nx, ny)
	var len: float = sqrt(dx * dx + dy * dy)
	var speed: float = 2.1 * SimNeeds.walk_mul(world, ent)
	# The modifier store's move_speed, the same read the player's `move` command makes
	# (world.gd's movement phase). It was never read here: the limp, encumbrance and blood loss
	# slowed the player and never Mara or Ellis, and a weather that slows the living would have
	# slowed one body of three (docs/23's defect list, closed by the weather spine).
	if world.modifiers != null and (world.modifiers as Object).has_method("resolve"):
		speed *= float(world.modifiers.call("resolve", "move_speed", ent))
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


static func _stop(world: Variant, ent: int, completed: String = "") -> void:
	if completed != "":
		world.events.publish({"type": "job.completed", "entity": ent, "kind": completed})
	if world.components.has_component(ent, "sleeping"):
		SimNeeds.wake(world, ent)
	var job: Variant = world.components.get_component(ent, "job")
	if job is Dictionary:
		_release_claim(world, ent, job as Dictionary)
	world.components.remove(ent, "job")
	_still(world, ent)


# Does this survivor want a Doctor? Compared as *states*, never as raw integrity.
#
# This used to test `integrity < 30` across parts that do not share a scale, so a perfectly
# healthy head (max 15) and every hand (max 10) were permanently "injured" -- meaning
# effectively every survivor was always a Doctor-job candidate, which is not a threshold at
# all. SimHealth.part_state is the one canonical normaliser; CLAUDE.md records this exact
# trap. It also walked six parts out of ten, so a ruined hand or foot was invisible to it.
static func _injured(world: Variant, ent: int) -> bool:
	var inj: Variant = world.components.get_component(ent, "injuries")
	if inj is Dictionary and not ((inj as Dictionary).get("wounds", []) as Array).is_empty():
		return true
	var body: Variant = world.components.get_component(ent, "body")
	if body is Dictionary:
		for p in SimCombat.SURVIVOR_BODY_PARTS:
			var st: Variant = SimHealth.part_state(body as Dictionary, String(p))
			if st != null and int(st) >= SimHealth.PartState.BadlyHurt:
				return true
	return false
