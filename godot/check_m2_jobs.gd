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
const Clock = preload("res://sim/time/clock.gd")
const SimContainers = preload("res://sim/modules/containers.gd")
const SimSightings = preload("res://sim/modules/sightings.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _astar() and ok
	ok = _focus() and ok
	ok = _jobs() and ok
	ok = _corpse_haul() and ok
	ok = _seek_wakes_rest() and ok
	ok = _water_clean_bury() and ok
	ok = _an_empty_left_by_a_drink_is_what_the_water_job_wants() and ok
	ok = _a_body_beside_the_river_fills_there_and_not_at_the_well() and ok
	ok = _succession() and ok
	ok = _the_cook_claims_its_raw_and_a_vanished_raw_cooks_nothing() and ok
	ok = _guard_is_the_night_post_and_the_day_belongs_to_the_row() and ok
	ok = _a_focus_change_keeps_the_authored_row() and ok
	ok = _a_starving_colonist_still_eats() and ok
	ok = _colonists_scavenge_near_home() and ok
	ok = _an_unreachable_target_is_planned_for_once_and_then_dropped() and ok
	if ok:
		print("M2_JOBS_OK astar focus cook haul construct doctor rest corpse seek water clean bury succession, the well is reachable from a bottle the sim emptied, a cook claims its raw, Guard is the night post, a focus change keeps the authored row, a starving colonist still eats, colonists scavenge near home, and a target nobody can route to is planned for once and then left alone")
		quit(0)
	else:
		push_error("M2_JOBS_FAIL")
		quit(1)

func _world() -> Variant:
	return SimBoot.playable(20260805, 64)["world"]

# Where the colony is comes off the booted district's anchors, not out of this file. Every
# coordinate below used to be a literal twin of `SimDirector.ANNEX` or of boot's start tile, and
# they are gone -- so these two say the same thing the sim says, and follow it if it moves.
func _start(w: Variant) -> Vector2i:
	return SimTileMap.player_start(w.tilemap)

func _annex(w: Variant) -> Rect2i:
	return SimTileMap.annex_rect(w.tilemap)

# The first stockpile tile in the annex, scanned the way the callers below need it. `outer_break`
# is the difference between "the nearest one" and "the first one on the last row that has any",
# which is what these two loops each already did.
func _first_stockpile(w: Variant, fallback: Vector2i, outer_break: bool) -> Vector2i:
	var annex: Rect2i = _annex(w)
	var drop: Vector2i = fallback
	for j in range(annex.position.y, annex.position.y + annex.size.y):
		for i in range(annex.position.x, annex.position.x + annex.size.x):
			if SimNeeds.is_stockpile_tile(w, i, j):
				drop = Vector2i(i, j)
				break
		if outer_break and drop != fallback:
			break
	return drop

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
	var from: Vector2i = _start(w)
	if from.x < 0:
		push_error("the booted district names no player start")
		return false
	var to_bed := Vector2i(floori(float((bp as Dictionary)["x"])), floori(float((bp as Dictionary)["y"])))
	var to_fire := Vector2i(floori(float((fp as Dictionary)["x"])), floori(float((fp as Dictionary)["y"])))
	var p1: Array[Vector2i] = SimPath.find(w, from, to_bed)
	var p2: Array[Vector2i] = SimPath.find(w, from, to_fire)
	var drop: Vector2i = _first_stockpile(w, Vector2i(-1, -1), true)
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
	if int(auto.get("Water", 0)) != 3 or int(auto.get("Clean", 0)) != 3 or int(auto.get("Bury", 0)) != 3:
		push_error("auto missing water/clean/bury %s" % str(auto))
		return false
	if int(auto.get("Repair", 0)) != 3:
		push_error("auto missing repair %s" % str(auto))
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

# The nearest loose item that is not already stockpiled and is not a body, by the same rule
# `SimJobs._haul_work` sorts on. A second copy of the rule rather than a call into it, so the lane
# above is comparing the job's answer against the question rather than against itself.
func _nearest_loose_item(w: Variant, sx: float, sy: float) -> int:
	var best: int = -1
	var best_d: float = 1e12
	for item in SimInventory.ground_items(w):
		var p: Variant = w.components.get_component(int(item), "position")
		if not (p is Dictionary):
			continue
		var at: Dictionary = p as Dictionary
		if SimNeeds.is_stockpile_tile(w, floori(float(at["x"])), floori(float(at["y"]))):
			continue
		if w.components.has_component(int(item), "corpse"):
			continue
		var dx: float = float(at["x"]) - sx
		var dy: float = float(at["y"]) - sy
		if dx * dx + dy * dy < best_d:
			best_d = dx * dx + dy * dy
			best = int(item)
	return best


func _jobs() -> bool:
	var w: Variant = _world()
	var mara: int = _mara(w)
	var start: Vector2i = _start(w)
	# The tile corner, exactly as the literal 46.0/45.0 pair was: these feed distance sorts, and
	# nudging them half a tile could reorder two near-equal candidates.
	var sx: float = float(start.x)
	var sy: float = float(start.y)
	# Haul, in two halves, because a booted district now has loot lying about in it: the sites are
	# drawn per seed from the district's `lootProfile` where the annex's map entry used to hand-place
	# seven rows, five of which fell outside a 64-tile map entirely -- so "the only loose item in the
	# world" is an assumption this lane can no longer make, and used to make silently.
	#
	# First half: the promise the job actually makes, judged against whatever the boot scattered --
	# the nearest loose thing that is not already on the stockpile.
	var loose: int = _nearest_loose_item(w, sx, sy)
	if loose < 0:
		push_error("the booted district left nothing loose outside the stockpile, so the haul sort judged nothing")
		return false
	var nearest: Dictionary = SimJobs._haul_work(w, sx, sy)
	if nearest.is_empty() or int(nearest.get("target", -1)) != loose:
		push_error("haul work %s did not target the nearest loose item, %d" % [str(nearest), loose])
		return false
	# Second half, and the true positive: with the boot's loot cleared away, a single new item
	# outside the annex is what the job has to find. `world.despawn` rather than
	# `entities.despawn` -- the latter leaves every component in place, so the items would still be
	# lying on the ground as far as any query is concerned.
	for lying in SimInventory.ground_items(w):
		w.despawn(int(lying))
	if _nearest_loose_item(w, sx, sy) >= 0:
		push_error("clearing the boot's loose loot left something behind")
		return false
	var item: int = SimItems.spawn_item(w, "item.scrap.metal", {"tier": "scavenged"})
	w.components.set_component(item, "position", {"x": 20.5, "y": 20.5})
	var haul: Dictionary = SimJobs._haul_work(w, sx, sy)
	if haul.is_empty() or int(haul.get("target", -1)) != item:
		push_error("haul work %s" % str(haul))
		return false
	# Cook
	var raw: int = SimItems.spawn_item(w, "item.food.raw", {"tier": "scavenged"})
	var drop: Vector2i = _first_stockpile(w, start, false)
	w.components.set_component(raw, "position", {"x": float(drop.x) + 0.5, "y": float(drop.y) + 0.5})
	var cook: Dictionary = SimJobs._cook_work(w, _mara(w))
	if cook.is_empty():
		push_error("cook work empty")
		return false
	# Construct window
	var con: Dictionary = SimJobs._construct_work(w, sx, sy)
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
	var dump: Vector2i = SimJobs._corpse_dump(w)
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

func _water_clean_bury() -> bool:
	var w: Variant = _world()
	var mara: int = _mara(w)
	var wells: Array = w.components.query(["water_source"])
	if wells.is_empty():
		push_error("no water_source station")
		return false
	var well: int = int(wells[0])
	var wp: Variant = w.components.get_component(well, "position")
	var well_tile := Vector2i(floori(float((wp as Dictionary)["x"])), floori(float((wp as Dictionary)["y"])))
	# Water: empty bottle → fill at well
	var bottle: int = SimItems.spawn_item(w, "item.water.bottle.empty", {"tier": "scavenged"})
	var start: Vector2i = _start(w)
	var drop: Vector2i = _first_stockpile(w, start, true)
	w.components.set_component(bottle, "position", {"x": float(drop.x) + 0.5, "y": float(drop.y) + 0.5})
	var water: Dictionary = SimJobs._water_work(w, mara, float(start.x), float(start.y))
	if water.is_empty() or int(water.get("target", -1)) != bottle:
		push_error("water work %s" % str(water))
		return false
	SimInventory.stow(w, mara, bottle)
	w.components.set_component(mara, "position", {"x": float(well_tile.x) + 0.5, "y": float(well_tile.y) + 0.5})
	water["ticksLeft"] = 1
	w.components.set_component(mara, "job", water)
	SimJobs._do_water(w, mara, water)
	var base: Variant = w.components.get_component(bottle, "itemBase")
	# The well fills untreated water, never clean -- boiling is a separate act (godot:m2:needs, WATER).
	if not base is Dictionary or String((base as Dictionary).get("baseId", "")) != SimNeeds.UNTREATED_ID:
		push_error("bottle not filled with untreated water: %s" % str(base))
		return false
	# Clean: dirty → wash at source (no bottle consume)
	SimNeeds.dirt(w, mara, 2)
	if String(SimNeeds.of(w, mara).get("hygiene", "")) == "clean":
		push_error("dirt failed")
		return false
	var clean: Dictionary = SimJobs._clean_work(w, mara, float(well_tile.x), float(well_tile.y))
	if clean.is_empty():
		push_error("clean work empty")
		return false
	clean["ticksLeft"] = 1
	w.components.set_component(mara, "job", clean)
	SimJobs._do_clean(w, mara, clean)
	if String(SimNeeds.of(w, mara).get("hygiene", "")) != "clean":
		push_error("clean failed")
		return false
	# Bury: corpse → dump → despawn
	var w2: Variant = _world()
	var m2: int = _mara(w2)
	SimHealth.finish_death(w2, m2)
	var start2: Vector2i = _start(w2)
	var bury: Dictionary = SimJobs._bury_work(w2, float(start2.x), float(start2.y))
	if bury.is_empty() or int(bury.get("target", -1)) != m2:
		push_error("bury work %s" % str(bury))
		return false
	w2.components.set_component(w2.player, "job", bury)
	var mp: Variant = w2.components.get_component(m2, "position")
	var ctile := Vector2i(floori(float((mp as Dictionary)["x"])), floori(float((mp as Dictionary)["y"])))
	w2.components.set_component(w2.player, "position", {"x": float(ctile.x) + 0.5, "y": float(ctile.y) + 0.5})
	SimJobs._do_bury(w2, w2.player, bury)
	if not bool(bury.get("carrying", false)):
		push_error("bury not carrying")
		return false
	var dump: Vector2i = SimJobs._corpse_dump(w2)
	w2.components.set_component(w2.player, "position", {"x": float(dump.x) + 0.5, "y": float(dump.y) + 0.5})
	bury["ticksLeft"] = 1
	w2.components.set_component(w2.player, "job", bury)
	SimJobs._do_bury(w2, w2.player, bury)
	if w2.entities.is_alive(m2) or w2.components.has_component(m2, "corpse"):
		push_error("corpse not buried")
		return false
	print("WATER CLEAN BURY OK")
	return true

func _succession() -> bool:
	var w: Variant = _world()
	var mara: int = _mara(w)
	var dead: int = int(w.player)
	SimHealth.finish_death(w, dead)
	if bool(w.runOver):
		push_error("succession set runOver")
		return false
	if int(w.player) != mara:
		push_error("wanted mara got %d" % int(w.player))
		return false
	if not w.components.has_component(mara, "controlled"):
		push_error("mara not controlled")
		return false
	if not w.components.has_component(dead, "corpse"):
		push_error("dead player not corpse")
		return false
	if w.components.has_component(dead, "controlled"):
		push_error("dead still controlled")
		return false
	var snap: Dictionary = w.snapshot()
	if int(snap.get("player", -1)) != mara:
		push_error("snapshot player %s" % str(snap.get("player", null)))
		return false
	w.restore(snap)
	if int(w.player) != mara:
		push_error("restore player %d" % int(w.player))
		return false
	# Solo player → runOver. "Solo" is every OTHER colonist dead first, not a named list -- the
	# boot colony is three now (docs/23's flag record) and a hard-coded Mara left Ellis alive,
	# so the run correctly refused to end and this lane read that correctness as a failure.
	var w2: Variant = _world()
	for ent in w2.components.query(["needs", "body"]):
		if int(ent) == int(w2.player) or w2.components.has_component(int(ent), "recruit"):
			continue
		SimHealth.finish_death(w2, int(ent))
	if bool(w2.runOver):
		push_error("the run ended while the player still lived")
		return false
	SimHealth.finish_death(w2, w2.player)
	if not bool(w2.runOver):
		push_error("solo death no runOver")
		return false
	print("SUCCESSION OK mara handoff snap solo")
	return true


# The dead-socket lane for the well. `_water_work` has always hunted item.water.bottle.empty, and
# until `empties` landed nothing in shipped play ever produced one -- every empty the Water job was
# ever tested with was spawned by hand (the lane above). Here Mara drinks a real bottle and the
# job wants what she is left holding.
func _an_empty_left_by_a_drink_is_what_the_water_job_wants() -> bool:
	var w: Variant = _world()
	var mara: int = _mara(w)
	if mara < 0:
		push_error("WELL: no Mara")
		return false
	if w.components.query(["water_source"]).is_empty():
		print("WELL SKIPPED the booted district stands no water_source, so there is nothing to judge")
		return true
	var start: Vector2i = _start(w)
	var before: Dictionary = {}
	for e in w.components.query(["itemBase"]):
		var b: Variant = w.components.get_component(int(e), "itemBase")
		if b is Dictionary and String((b as Dictionary).get("baseId", "")) == "item.water.bottle.empty":
			before[int(e)] = true
	var bottle: int = SimItems.spawn_item(w, "item.water.bottle", {"tier": "scavenged"})
	if not SimInventory.stow(w, mara, bottle):
		push_error("WELL: could not stow a bottle on Mara")
		return false
	if not SimNeeds.drink(w, mara):
		push_error("WELL: Mara could not drink the bottle")
		return false
	var empties: Array[int] = []
	for e in w.components.query(["itemBase"]):
		var b: Variant = w.components.get_component(int(e), "itemBase")
		if b is Dictionary and String((b as Dictionary).get("baseId", "")) == "item.water.bottle.empty" and not before.has(int(e)):
			empties.append(int(e))
	if empties.size() != 1 or not SimInventory.owns(w, mara, empties[0]):
		push_error("WELL: the drink left %d new empties, or Mara does not hold it" % empties.size())
		return false
	var water: Dictionary = SimJobs._water_work(w, mara, float(start.x), float(start.y))
	if water.is_empty() or int(water.get("target", -1)) != empties[0]:
		push_error("WELL: the water job wants %s, not the bottle Mara just emptied (%d)" % [str(water), empties[0]])
		return false
	print("WELL OK a bottle Mara drank became the empty the Water job wants -- the first empty the sim itself has ever produced")
	return true


# Cook claims its ingredient. docs/23's defect: nothing marked the raw as spoken for and the
# completion never re-checked, so two cooks on one raw made two meals -- or one meal from nothing,
# because the cooked spawn was unconditional. Six claims, each with its negative beside it:
#   two cooks, one raw   -> the first claims it and the second finds no work; a second raw and the
#                           second cook finds *that* one
#   completion           -> exactly one meal, the raw gone, the claim gone, one job.completed
#   a vanished raw       -> no meal, no job.completed, the job dropped; the intact control cooks one
#   _stop                -> releases the claim, and the next cook can take it
#   the holder dies      -> the stale claim heals on sight; a living holder's does not
func _the_cook_claims_its_raw_and_a_vanished_raw_cooks_nothing() -> bool:
	var w: Variant = _world()
	var mara: int = _mara(w)
	var ellis: int = _ellis(w)
	if mara < 0 or ellis < 0:
		push_error("COOK CLAIM: the booted colony has no Mara or no Ellis, so nothing was judged")
		return false
	if w.components.query(["campfire"]).is_empty():
		push_error("COOK CLAIM: no campfire, so Cook has no work to claim")
		return false
	# The booted pile is not empty, and since the transform slice it is *content* that decides what
	# can be cooked rather than one hardcoded id -- so the pile can hold a cookable that is not this
	# lane's fixture, and does: the shipped suburb's stockpile rolls a canning jar. Cleared first,
	# so "Ellis was handed nothing" stays a claim about Mara's claim rather than a claim about what
	# the loot roll happened to drop.
	_clear_cookables(w)
	var raw: int = _drop_raw(w)
	var job_m: Dictionary = SimJobs._cook_work(w, mara)
	if job_m.is_empty() or int(job_m.get("target", -1)) != raw:
		push_error("COOK CLAIM: Mara's cook work was %s" % str(job_m))
		return false
	w.components.set_component(mara, "job", job_m)
	var r: Variant = w.components.get_component(raw, "reserved")
	if not (r is Dictionary) or int((r as Dictionary).get("by", -1)) != mara:
		push_error("COOK CLAIM: the raw carries no claim in Mara's name: %s" % str(r))
		return false
	var job_e: Dictionary = SimJobs._cook_work(w, ellis)
	if not job_e.is_empty():
		push_error("COOK CLAIM: Ellis was handed the raw Mara had already claimed: %s" % str(job_e))
		return false
	var raw2: int = _drop_raw(w)
	job_e = SimJobs._cook_work(w, ellis)
	if job_e.is_empty() or int(job_e.get("target", -1)) != raw2:
		push_error("COOK CLAIM: with a second raw on the pile Ellis got %s" % str(job_e))
		return false
	w.components.set_component(ellis, "job", job_e)

	# Completion: one meal, the raw gone, the claim gone, one completion.
	var completed: Array = []
	w.events.subscribe({"id": "gate.cook.done", "type": "job.completed", "handler": func(e: Dictionary) -> void:
		if String(e.get("kind", "")) == "Cook":
			completed.append(e)
	})
	var before: int = _count_base(w, "item.food.cooked")
	_stand_at_fire(w, mara)
	job_m["ticksLeft"] = 1
	SimJobs._do_cook(w, mara, job_m)
	w.events.drain()
	if _count_base(w, "item.food.cooked") != before + 1:
		push_error("COOK CLAIM: a completed cook made %d meals, not one" % (_count_base(w, "item.food.cooked") - before))
		return false
	if w.components.has_component(raw, "itemBase") or w.components.has_component(raw, "reserved"):
		push_error("COOK CLAIM: the cooked raw is still there, or still claimed")
		return false
	if w.components.has_component(mara, "job") or completed.size() != 1:
		push_error("COOK CLAIM: after cooking Mara still has a job, or job.completed fired %d times" % completed.size())
		return false

	# The vanished raw: Ellis's ingredient leaves the world before the pot is done. No meal, no
	# completion, the job dropped -- the fire goes back to idle.
	completed.clear()
	before = _count_base(w, "item.food.cooked")
	w.despawn(raw2)
	_stand_at_fire(w, ellis)
	job_e["ticksLeft"] = 1
	SimJobs._do_cook(w, ellis, job_e)
	w.events.drain()
	if _count_base(w, "item.food.cooked") != before:
		push_error("COOK CLAIM: a raw that vanished still cooked %d meals" % (_count_base(w, "item.food.cooked") - before))
		return false
	if w.components.has_component(ellis, "job") or not completed.is_empty():
		push_error("COOK CLAIM: a cook whose raw vanished kept the job (%s) or completed it (%d)" % [str(w.components.get_component(ellis, "job")), completed.size()])
		return false

	# Release on _stop, and a stale claim healing when its holder dies -- while a live one holds.
	var w2: Variant = _world()
	var m2: int = _mara(w2)
	var e2: int = _ellis(w2)
	_clear_cookables(w2)
	var raw3: int = _drop_raw(w2)
	var jm: Dictionary = SimJobs._cook_work(w2, m2)
	w2.components.set_component(m2, "job", jm)
	if not SimJobs._cook_work(w2, e2).is_empty():
		push_error("COOK CLAIM: a live claim by a living Mara was healed away")
		return false
	SimJobs._stop(w2, m2)
	if w2.components.has_component(raw3, "reserved"):
		push_error("COOK CLAIM: _stop left Mara's claim on the raw")
		return false
	var je: Dictionary = SimJobs._cook_work(w2, e2)
	if je.is_empty() or int(je.get("target", -1)) != raw3:
		push_error("COOK CLAIM: after Mara stopped, Ellis could not take the raw: %s" % str(je))
		return false
	w2.components.set_component(e2, "job", je)
	SimHealth.finish_death(w2, e2)
	w2.events.drain()
	var jm2: Dictionary = SimJobs._cook_work(w2, m2)
	if jm2.is_empty() or int(jm2.get("target", -1)) != raw3:
		push_error("COOK CLAIM: a dead cook's claim still blocks the raw: %s" % str(jm2))
		return false
	print("COOK CLAIM OK one raw one cook, a second raw a second cook, one meal per completion, a vanished raw cooks nothing, _stop releases, a dead cook's claim heals and a live one holds")
	return true


func _ellis(w: Variant) -> int:
	for e in w.components.query(["identity"]):
		var ident: Variant = w.components.get_component(int(e), "identity")
		if ident is Dictionary and String((ident as Dictionary).get("id", "")) == "survivor.unique.ellis":
			return int(e)
	return -1


# Take everything cookable off the pile, by removing the position that puts it there. Nothing is
# despawned: `_count_base` walks every itemBase in the world, so a despawn would leave the count
# untouched anyway (components outlive a despawn) and a moved item is the honest way to say "not on
# the pile".
func _clear_cookables(w: Variant) -> void:
	for item in SimNeeds.stockpile_items(w):
		if not SimJobs.cooks_into(w, int(item)).is_empty():
			w.components.remove(int(item), "position")


func _drop_raw(w: Variant) -> int:
	var raw: int = SimItems.spawn_item(w, "item.food.raw", {"tier": "scavenged"})
	var drop: Vector2i = _first_stockpile(w, _start(w), true)
	w.components.set_component(raw, "position", {"x": float(drop.x) + 0.5, "y": float(drop.y) + 0.5})
	return raw


func _count_base(w: Variant, base_id: String) -> int:
	var n: int = 0
	for item in w.components.query(["itemBase"]):
		var b: Variant = w.components.get_component(int(item), "itemBase")
		if b is Dictionary and String((b as Dictionary).get("baseId", "")) == base_id:
			n += 1
	return n


func _stand_at_fire(w: Variant, ent: int) -> void:
	var fires: Array[int] = w.components.query(["campfire"])
	var fp: Variant = w.components.get_component(fires[0], "position")
	w.components.set_component(ent, "position", {"x": float((fp as Dictionary)["x"]), "y": float((fp as Dictionary)["y"])})


# --- Guard is the dusk-to-dawn post (the owner's 2026-09-06 call) ---------------------------
#
# Before this, `_work_for` handed out the post at any hour and the Guard arm never completed, so
# Ellis (Guard 1 in his content) stood the gate from tick one for the whole run and the boot
# colony never hauled, cooked or built. Now: by day the post is not on offer and the row's next
# column gets him; at dusk the post calls him off a job that has not begun a channel; at dawn
# the watch completes -- the first `job.completed{Guard}` there has ever been -- and the skill web
# reads it. The lane follows one booted Ellis through a day, a dusk, a night and a dawn.
func _guard_is_the_night_post_and_the_day_belongs_to_the_row() -> bool:
	var w: Variant = _world()
	var ellis: int = _ellis(w)
	if ellis < 0:
		push_error("guard post: no Ellis in the playable boot")
		return false
	var post: Vector2i = SimTileMap.gate_a(w.tilemap)
	if post.x < 0 or post.y < 0:
		push_error("guard post: the playable boot names no gate, so there is no post to judge")
		return false
	if Clock.phase_of(int(w.tick)) != Clock.Phase.Day:
		push_error("guard post: the boot is not in daylight (phase %d); the day half judges nothing" % Clock.phase_of(int(w.tick)))
		return false
	# This lane judges the router, not survival: a booted district scatters twenty shamblers, and
	# an NPC hauling across it by day and walking to the gate at dusk can be grabbed and killed
	# on the way (measured: Ellis lost his position at the map's north edge on the first run).
	# `world.despawn`, not `entities.despawn`, so the components go with the bodies.
	var cleared: int = 0
	for z in w.components.query(["shambler"]):
		w.despawn(int(z))
		cleared += 1
	if cleared == 0:
		push_error("guard post: the booted district stood no shamblers, which is not the district this lane was written against")
		return false
	# The true negative first, and directly: by day there is no Guard job to hand out.
	if not SimJobs._work_for(w, ellis, "Guard").is_empty():
		push_error("guard post: Guard was on offer by day")
		return false
	# By day the row works. Ellis's row is Guard 1, Haul 2, Construct 3 ...; Guard refuses, so
	# Haul (the booted district scatters loot) is what he takes, and never Guard.
	var day_kinds: Dictionary = {}
	for _i in 2000:
		w.step()
		var job: Variant = w.components.get_component(ellis, "job")
		if job is Dictionary:
			day_kinds[String((job as Dictionary).get("kind", ""))] = true
	if day_kinds.has("Guard"):
		push_error("guard post: Ellis took Guard by day (%s)" % str(day_kinds.keys()))
		return false
	if day_kinds.is_empty():
		push_error("guard post: Ellis took no work by day; the day half judged nothing")
		return false
	# Dusk calls him to the post, and he walks to it.
	w.tick = Clock.tick_on_day(1, Clock.DAY_ENDS)
	var called: bool = false
	for _i in 3000:
		w.step()
		var job: Variant = w.components.get_component(ellis, "job")
		if job is Dictionary and String((job as Dictionary).get("kind", "")) == "Guard":
			called = true
			break
	if not called:
		push_error("guard post: dusk never called Ellis to the post")
		return false
	var at_post: bool = false
	for _i in 6000:
		w.step()
		if SimJobs._at(w, ellis, post, SimJobs.REACH):
			at_post = true
			break
	if not at_post:
		push_error("guard post: Ellis never reached the gate")
		return false
	# Dawn completes the watch, and the skill web reads it: an Endurance point. Manual so the
	# point banks rather than being spent on `end.legs` (cost 1) the same tick it lands.
	SimJobs.set_focus(w, ellis, "Manual", "player")
	var web: Dictionary = w.components.get_component(ellis, "skillWeb") as Dictionary
	var before: int = int((web.get("points", {}) as Dictionary).get("Endurance", 0))
	var done: Array = []
	w.events.subscribe({"id": "check.guard-done", "type": "job.completed", "handler": func(e: Dictionary) -> void:
		if String(e.get("kind", "")) == "Guard" and int(e.get("entity", -1)) == ellis:
			done.append(int(e.get("entity", -1)))
	})
	w.tick = Clock.tick_on_day(2, Clock.DAY_BEGINS)
	for _i in 5:
		w.step()
	if done.is_empty():
		push_error("guard post: dawn did not complete the watch")
		return false
	web = w.components.get_component(ellis, "skillWeb") as Dictionary
	var after: int = int((web.get("points", {}) as Dictionary).get("Endurance", 0))
	if after != before + 1:
		push_error("guard post: Endurance read %d before the watch and %d after; the completion reached nobody" % [before, after])
		return false
	# And the day belongs to the row again.
	var repicked: bool = false
	for _i in 2000:
		w.step()
		var job: Variant = w.components.get_component(ellis, "job")
		if job is Dictionary and String((job as Dictionary).get("kind", "")) != "Guard":
			repicked = true
			break
	if not repicked:
		push_error("guard post: Ellis took no day work after the watch")
		return false
	# A district with no gate anchor has no post, dusk or not.
	w.tick = Clock.tick_on_day(2, Clock.DAY_ENDS)
	var anchors: Dictionary = w.tilemap.anchors
	var gate_anchor: Variant = anchors.get("gate_a")
	anchors.erase("gate_a")
	var offered: bool = not SimJobs._work_for(w, ellis, "Guard").is_empty()
	anchors["gate_a"] = gate_anchor
	if offered:
		push_error("guard post: a district with no gate handed out a post")
		return false
	print("GUARD POST OK by day the row (%s), at dusk the post, at dawn job.completed and Endurance %d -> %d, no gate no post" % [", ".join(PackedStringArray(day_kinds.keys())), before, after])
	return true


# A focus change used to replace the whole row with the preset, so one click on Ellis's focus
# word destroyed the row his content wrote. Now the preset wins where it speaks and the authored
# row survives where it is silent; Manual is the authored row again; a generated survivor, who
# has no authored row, gets exactly the preset -- the true negative that the overlay invents
# nothing.
func _a_focus_change_keeps_the_authored_row() -> bool:
	var w: Variant = _world()
	var ellis: int = _ellis(w)
	var jp: Dictionary = w.components.get_component(ellis, "jobPriorities") as Dictionary
	var authored: Variant = jp.get("authored", null)
	if not authored is Dictionary or int((authored as Dictionary).get("Guard", 0)) != 1 or int((authored as Dictionary).get("Haul", 0)) != 2:
		push_error("authored: Ellis's content row was not kept (%s)" % str(authored))
		return false
	SimJobs.set_focus(w, ellis, "Medic", "player")
	var cols: Dictionary = (w.components.get_component(ellis, "jobPriorities") as Dictionary)["cols"] as Dictionary
	if int(cols.get("Doctor", 0)) != 1 or int(cols.get("Guard", 0)) != 2:
		push_error("authored: the Medic preset did not win where it speaks (%s)" % str(cols))
		return false
	if int(cols.get("Haul", 0)) != 2 or int(cols.get("Construct", 0)) != 3:
		push_error("authored: the authored row did not survive where the preset is silent (%s)" % str(cols))
		return false
	if cols == SimJobs.preset("Medic"):
		push_error("authored: Ellis under Medic reads as the bare preset; the overlay is not being read")
		return false
	SimJobs.set_focus(w, ellis, "Manual", "player")
	cols = (w.components.get_component(ellis, "jobPriorities") as Dictionary)["cols"] as Dictionary
	for c in SimJobs.COLUMNS:
		if int(cols.get(c, 0)) != int((authored as Dictionary).get(c, 0)):
			push_error("authored: Manual did not restore %s (%d vs %d)" % [c, int(cols.get(c, 0)), int((authored as Dictionary).get(c, 0))])
			return false
	# A survivor with no authored row: the preset, exactly.
	var fresh: int = w.entities.spawn()
	SimJobs.attach(w, fresh, "Auto")
	if (w.components.get_component(fresh, "jobPriorities") as Dictionary).has("authored"):
		push_error("authored: a generated row grew an authored copy")
		return false
	SimJobs.set_focus(w, fresh, "Medic", "player")
	var fresh_cols: Dictionary = (w.components.get_component(fresh, "jobPriorities") as Dictionary)["cols"] as Dictionary
	if fresh_cols != SimJobs.preset("Medic"):
		push_error("authored: a generated survivor under Medic is not the bare preset (%s)" % str(fresh_cols))
		return false
	print("AUTHORED OK preset over authored, authored fills the gaps, Manual restores, a generated row is the bare preset")
	return true


# --- a starving colonist still eats (the crisis dead-end, closed 2026-09-06) ------------------
#
# `_tick_one` used to `_stop` and return for a `starving` or `dehydrating` survivor before the
# need seek ran, and `work_mul` is 0 in a crisis so `_walk` could not have moved them anyway: a
# colonist at zero hunger died on the starvation clock beside a full pantry. Now the seek runs
# and the walk goes at `walk_mul`'s half pace. Both halves, each with its negative: food on the
# stockpile is reached and eaten (and nothing carried, so the walk is the thing under test);
# no food anywhere still ends on the clock -- the fix makes no food out of nothing. The same
# pair for thirst against an untreated bottle with no fire in the district, which is drunk raw.
func _a_starving_colonist_still_eats() -> bool:
	var w: Variant = _world()
	var ellis: int = _ellis(w)
	if ellis < 0:
		push_error("crisis: no Ellis")
		return false
	for z in w.components.query(["shambler"]):
		w.despawn(int(z))
	_strip_edibles(w, ellis)
	# The tin below has to be the only edible thing in the district, or the survivor eats whatever
	# the tables happened to scatter nearer and never reads as starving at all.
	var cleared: int = _strip_every_edible_in_the_world(w)
	if cleared <= 0:
		push_error("crisis: the district held no edibles to clear, so the planted tin proves nothing")
		return false
	var stock: Vector2i = _first_stockpile(w, _start(w), true)
	var can: int = SimItems.spawn_item(w, "item.food.canned", {"tier": "scavenged"})
	w.components.set_component(can, "position", {"x": float(stock.x) + 0.5, "y": float(stock.y) + 0.5})
	var killed: Array = []
	w.events.subscribe({"id": "check.crisis-killed", "type": "entity.killed", "handler": func(e: Dictionary) -> void:
		if int(e.get("entity", -1)) == ellis:
			killed.append(String(e.get("need", "")))
	})
	var n: Dictionary = SimNeeds.of(w, ellis)
	n["hunger"] = 0.0
	w.step()
	if String(SimNeeds.of(w, ellis).get("crisis", "")) != "starving":
		push_error("crisis: hunger 0 did not read as starving (%s)" % str(SimNeeds.of(w, ellis).get("crisis", "")))
		return false
	if SimNeeds.walk_mul(w, ellis) <= 0.0 or SimNeeds.work_mul(w, ellis) != 0.0:
		push_error("crisis: walk_mul %.2f / work_mul %.2f -- a crisis should walk and not work" % [SimNeeds.walk_mul(w, ellis), SimNeeds.work_mul(w, ellis)])
		return false
	var fed_at: int = -1
	for i in 6000:
		w.step()
		if float(SimNeeds.of(w, ellis).get("hunger", 0.0)) > 0.0:
			fed_at = i
			break
	if fed_at < 0:
		push_error("crisis: a starving Ellis never reached the can on the stockpile")
		return false
	if String(SimNeeds.of(w, ellis).get("crisis", "")) != "none" or not killed.is_empty():
		push_error("crisis: fed but still %s / killed %s" % [str(SimNeeds.of(w, ellis).get("crisis", "")), str(killed)])
		return false
	# The negative: nothing to eat anywhere, and the clock still runs to its end.
	_strip_edibles(w, ellis)
	for lying in SimInventory.ground_items(w):
		var b: Variant = SimItems.item_base_of(w, int(lying))
		if b is Dictionary and (b as Dictionary).has("food"):
			w.despawn(int(lying))
	SimNeeds.of(w, ellis)["hunger"] = 0.0
	w.step()
	# The clock, jumped to its last forty ticks rather than stepped through a whole day (the
	# fire lane's trick, from the other end: a back-dated stamp on day 1 goes negative and the
	# clock refuses one). What is judged is that the clock still ends, not how long it is.
	var starve_ticks: int = int(SimNeeds.STARVE_DAYS * float(Clock.DAY_TICKS))
	w.tick = int(SimNeeds.of(w, ellis).get("starvingSinceTick", 0)) + starve_ticks - 40
	for _i in 80:
		w.step()
		if not killed.is_empty():
			break
	if killed.is_empty() or killed[0] != "hunger":
		push_error("crisis: with no food anywhere Ellis did not starve on the clock (%s)" % str(killed))
		return false
	# Thirst, against an untreated bottle and no fire: drunk raw.
	var w2: Variant = _world()
	var e2: int = _ellis(w2)
	for z in w2.components.query(["shambler"]):
		w2.despawn(int(z))
	for f in w2.components.query(["campfire"]):
		w2.despawn(int(f))
	_strip_edibles(w2, e2)
	var stock2: Vector2i = _first_stockpile(w2, _start(w2), true)
	var raw: int = SimItems.spawn_item(w2, SimNeeds.UNTREATED_ID, {"tier": "scavenged"})
	w2.components.set_component(raw, "position", {"x": float(stock2.x) + 0.5, "y": float(stock2.y) + 0.5})
	SimNeeds.of(w2, e2)["thirst"] = 0.0
	w2.step()
	if String(SimNeeds.of(w2, e2).get("crisis", "")) != "dehydrating":
		push_error("crisis: thirst 0 did not read as dehydrating")
		return false
	var drank_at: int = -1
	for i in 6000:
		w2.step()
		if float(SimNeeds.of(w2, e2).get("thirst", 0.0)) > 0.0:
			drank_at = i
			break
	if drank_at < 0:
		push_error("crisis: a dehydrating Ellis with only an untreated bottle and no fire never drank")
		return false
	print("CRISIS OK a starving Ellis walked to the stockpile and ate at tick %d (walk_mul %.2f, work_mul 0); with no food anywhere he starved on the clock (%s); a dehydrating Ellis drank the untreated bottle raw at tick %d with no fire in the district" % [fed_at, SimNeeds.CRISIS_WALK_MUL, str(killed), drank_at])
	return true


# Nothing edible on the body: every carried food or drink goes, so a seek has to walk.
func _strip_edibles(w: Variant, ent: int) -> void:
	for item in SimInventory.carried_items(w, ent):
		var base: Variant = SimItems.item_base_of(w, int(item))
		if base is Dictionary and ((base as Dictionary).has("food") or (base as Dictionary).has("drink")):
			w.despawn(int(item))


# Every edible in the district, not just the ones in one pack. The crisis lane plants a single tin
# at the stockpile and then asserts a survivor reads as `starving` before walking to it -- which is
# only true if that tin is the *only* thing they could eat. It was, for as long as the district
# happened to scatter no food within a tick's reach of the colony; the alpha-roster arc added twenty
# foods to the tables and the very first step fed Ellis a drum of porridge oats instead, so his
# hunger came back 38.000 and the crisis never latched. The lane's subject is the crisis and the
# walk, not the district's pantry, so the fixture now says what it always meant.
#
# `world.despawn` leaves components in place (CLAUDE.md's trap: despawn does not remove components,
# and `query` does not check alive), and every reader that finds food -- the eat verb, the Haul and
# Scavenge columns -- finds it by `itemBase` or by `position`. So both come off, or the thing is
# still on the menu after it is gone.
func _strip_every_edible_in_the_world(w: Variant) -> int:
	var gone: int = 0
	for e in w.components.query(["itemBase"]):
		var base: Variant = SimItems.item_base_of(w, int(e))
		if not (base is Dictionary):
			continue
		if not ((base as Dictionary).has("food") or (base as Dictionary).has("drink")):
			continue
		w.components.remove(int(e), "position")
		w.components.remove(int(e), "itemBase")
		w.despawn(int(e))
		gone += 1
	return gone


# --- colonists scavenge near home (the owner's decision 10, 2026-09-06) ------------------------
#
# Sixty to seventy percent of the district's food sits in containers and the only producer of a
# search was the player's E. Now a survivor remembers the containers they have *seen* (sightings,
# by `detail`), the Scavenge column walks to the nearest remembered one near home and opens it
# through `SimContainers.search`, and Haul carries the yield in. Negatives: a box outside the
# home radius is not handed out; a box nobody has seen is not; a box another colonist has
# claimed is not; a row with Scavenge 0 never scavenges. The dead-socket assertion is the last
# one: the yield reaches the stockpile.
func _colonists_scavenge_near_home() -> bool:
	var w: Variant = _world()
	var ellis: int = _ellis(w)
	var mara: int = _mara(w)
	if ellis < 0 or mara < 0:
		push_error("scavenge: no Ellis or Mara")
		return false
	for z in w.components.query(["shambler"]):
		w.despawn(int(z))
	# Every container the boot stood is forgotten and emptied, so the one box below is the only
	# thing the job could ever find.
	for box in w.components.query(["searchable"]):
		(w.components.get_component(int(box), "searchable") as Dictionary)["searched"] = true
	var home: Vector2 = SimJobs._home_centre(w)
	# A near box: an open outdoor tile a few tiles from home.
	var near_at: Vector2i = Vector2i(-1, -1)
	for r in range(4, 12):
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				var t := Vector2i(int(home.x) + dx, int(home.y) + dy)
				if t.x > 0 and t.y > 0 and t.x < int(w.tilemap.w) - 1 and t.y < int(w.tilemap.h) - 1 and not w.is_blocked_tile(t.x, t.y) and not SimNeeds.is_stockpile_tile(w, t.x, t.y):
					near_at = t
					break
			if near_at.x >= 0:
				break
		if near_at.x >= 0:
			break
	if near_at.x < 0:
		push_error("scavenge: no open tile near home to stand a box on")
		return false
	var near: int = SimContainers.make_container(w, float(near_at.x) + 0.5, float(near_at.y) + 0.5, "cupboard", "residential")
	# Ellis stands on an open tile two or three tiles from it, facing it, so the next observe sees
	# it -- and so the walk starts from a tile a path can leave (the first draft stood him two
	# tiles west without asking, and a wall there left him standing still for 3,000 ticks).
	var stand: Vector2i = Vector2i(-1, -1)
	for d in [Vector2i(-2, 0), Vector2i(2, 0), Vector2i(0, -2), Vector2i(0, 2), Vector2i(-3, 0), Vector2i(3, 0), Vector2i(0, -3), Vector2i(0, 3)]:
		var t2: Vector2i = near_at + d
		if not w.is_blocked_tile(t2.x, t2.y):
			stand = t2
			break
	if stand.x < 0:
		push_error("scavenge: no open tile within three of the box to stand Ellis on")
		return false
	var ex: float = float(stand.x) + 0.5
	var ey: float = float(stand.y) + 0.5
	w.components.set_component(ellis, "position", {"x": ex, "y": ey})
	w.components.set_component(ellis, "facing", {"radians": atan2(float(near_at.y) - float(stand.y), float(near_at.x) - float(stand.x))})
	SimJobs._stop(w, ellis)
	w.components.set_component(ellis, "jobPriorities", {"focus": "Custom", "cols": {"Scavenge": 0}})
	w.step()
	var known: Array = SimSightings.known_containers(w, ellis)
	var remembered: bool = false
	for row in known:
		if int((row as Dictionary)["e"]) == near:
			remembered = true
	if not remembered:
		push_error("scavenge: a box two tiles in front of Ellis was not remembered (%s)" % str(known))
		return false
	# Scavenge 0: never, even remembered.
	if not SimJobs._work_for(w, ellis, "Scavenge").is_empty() and false:
		pass
	# Cleared first, because the assertion below is about what `_pick` hands out and the step
	# above runs the whole jobs tick: since colonists wear what they find, that step can leave a
	# Dress walk on Ellis, which is not a work column at all and which `_pick` never assigned.
	# Reading a job `_pick` did not set would blame the wrong function -- the same class of
	# mistake as a textual gate reading the wrong `match` arm.
	SimJobs._stop(w, ellis)
	SimJobs._pick(w, ellis)
	if w.components.get_component(ellis, "job") is Dictionary:
		push_error("scavenge: a row with Scavenge 0 took a job (%s)" % str(w.components.get_component(ellis, "job")))
		return false
	# A box outside the home radius, remembered by hand, is not handed out.
	var far: int = SimContainers.make_container(w, home.x + SimJobs.HOME_RADIUS_TILES + 5.0, home.y, "cupboard", "residential")
	known.append({"e": far, "x": home.x + SimJobs.HOME_RADIUS_TILES + 5.0, "y": home.y})
	# A box nobody has seen: stood, never remembered.
	var unseen: int = SimContainers.make_container(w, float(near_at.x) + 0.5, float(near_at.y) + 1.5, "cupboard", "residential")
	# Mara's claim on the near box keeps it from Ellis.
	w.components.set_component(near, "reserved", {"by": mara, "job": "Scavenge"})
	w.components.set_component(mara, "job", {"kind": "Scavenge", "target": near, "tx": near_at.x, "ty": near_at.y, "ticksLeft": 0, "path": [], "pathGen": -1})
	w.components.set_component(ellis, "jobPriorities", {"focus": "Custom", "cols": {"Scavenge": 1, "Haul": 2}})
	var while_claimed: Dictionary = SimJobs._scavenge_work(w, ellis, ex, ey)
	if not while_claimed.is_empty():
		push_error("scavenge: Ellis was handed a box Mara had claimed, or the far or unseen one (%s)" % str(while_claimed))
		return false
	w.components.remove(mara, "job")
	w.components.remove(near, "reserved")
	# The unseen box has made its point (never remembered, never offered); it goes before the
	# walk, because a box one tile from the near one is *seen* the moment Ellis arrives there and
	# is then, rightly, scavenged -- which the first run of this lane reported as a failure.
	if not SimSightings.known_containers(w, ellis).filter(func(r): return int((r as Dictionary)["e"]) == unseen).is_empty():
		push_error("scavenge: a box nobody looked at was remembered")
		return false
	w.despawn(unseen)
	# Now: the near box, and only the near box.
	var offered: Dictionary = SimJobs._scavenge_work(w, ellis, ex, ey)
	if int(offered.get("target", -1)) != near:
		push_error("scavenge: expected the near box %d, got %s" % [near, str(offered)])
		return false
	w.components.remove(near, "reserved")
	var searched: Array = []
	w.events.subscribe({"id": "check.scavenge", "type": "container.searched", "handler": func(e: Dictionary) -> void:
		searched.append({"entity": int(e.get("entity", -1)), "actor": int(e.get("actor", -1)), "yielded": int(e.get("yielded", 0))})
	})
	var stock_before: int = SimNeeds.stockpile_items(w).size()
	for _i in 3000:
		w.step()
		if not searched.is_empty():
			break
	if searched.is_empty() or int((searched[0] as Dictionary)["actor"]) != ellis or int((searched[0] as Dictionary)["entity"]) != near:
		push_error("scavenge: Ellis never opened the near box (%s); job=%s pos=%s box=%s" % [str(searched), str(w.components.get_component(ellis, "job")), str(w.components.get_component(ellis, "position")), str(near_at)])
		return false
	var yielded: int = int((searched[0] as Dictionary)["yielded"])
	# The far box stays shut for a quarter day.
	var hauled: bool = false
	for _i in Clock.DAY_TICKS / 4:
		w.step()
		if SimNeeds.stockpile_items(w).size() > stock_before:
			hauled = true
			break
	if bool((w.components.get_component(far, "searchable") as Dictionary).get("searched", false)):
		push_error("scavenge: the far box was searched")
		return false
	if yielded == 0:
		print("SCAVENGE OK Ellis remembered a box he saw, refused it while Mara held the claim, ignored a far one and an unseen one, and opened it at home -- but the table yielded nothing this roll, so the haul half judged nothing")
		return true
	if not hauled:
		push_error("scavenge: the box yielded %d and nothing reached the stockpile in a quarter day" % yielded)
		return false
	print("SCAVENGE OK Ellis remembered a box he saw, was refused it under Mara's claim, never offered a far or an unseen one, refused it at Scavenge 0, opened it (yield %d) and the yield was hauled to the stockpile" % yielded)
	return true


# RIVER: the dead-socket lane for the river as a second water source.
#
# `SimBoot.place_river_sources` stands `water_source` entities on a district's banks, and the claim
# that matters is not that they exist -- it is that the thirst loop *reaches* them. So this asks
# `SimNeeds.nearest_water_source`, the one function the Water job routes through, from two places:
# beside the river it must answer the river, and beside the well it must still answer the well.
# Without the second half the lane would pass on a colony that had simply lost its well.
#
# It also pins the two things that make this a reuse rather than a new mechanic: the river's
# bottle is `untreated` like the well's, and the boil rung still turns it clean.
func _a_body_beside_the_river_fills_there_and_not_at_the_well() -> bool:
	# The forest is the shipped district that declares water; the gate's usual 64-tile suburb has
	# none, so this lane boots its own world rather than pretending the default one has a river.
	var w: Variant = SimBoot.playable(20260805, 128, "district.forest_edge")["world"]
	var map: Variant = w.tilemap
	var sources: Array = w.components.query(["water_source", "position"])
	if sources.size() < 2:
		push_error("RIVER: the forest booted %d water sources; the well plus the river's should be more than one" % sources.size())
		return false

	var well: Vector2i = SimTileMap.well_tile(map)
	if well.x < 0:
		push_error("RIVER: the booted forest has no well anchor, so there is nothing to out-rank")
		return false

	# A bank tile far from the well: the river is what a body standing here should be sent to.
	var bank := Vector2i(-1, -1)
	var mw: int = int(map.w)
	for ty in int(map.h):
		for tx in mw:
			if int(map.surfaces[ty * mw + tx]) != SimTileMap.SURFACE_WATER:
				continue
			if SimTileMap.is_solid(map, tx, ty):
				continue
			if absi(tx - well.x) + absi(ty - well.y) < 30:
				continue
			bank = Vector2i(tx, ty)
			break
		if bank.x >= 0:
			break
	if bank.x < 0:
		push_error("RIVER: the forest carries no bank tile 30 away from its well, so this lane judged nothing")
		return false

	var near_river: int = SimNeeds.nearest_water_source(w, float(bank.x) + 0.5, float(bank.y) + 0.5)
	var near_well: int = SimNeeds.nearest_water_source(w, float(well.x) + 0.5, float(well.y) + 0.5)
	if near_river < 0 or near_well < 0:
		push_error("RIVER: nearest_water_source answered nothing from the bank (%d) or the well (%d)" % [near_river, near_well])
		return false
	if near_river == near_well:
		push_error("RIVER: a body on the bank at %s and one at the well %s are sent to the same source; the river is standing there unread" % [str(bank), str(well)])
		return false
	var rp: Dictionary = w.components.get_component(near_river, "position") as Dictionary
	var river_d: float = absf(float(rp["x"]) - float(bank.x)) + absf(float(rp["y"]) - float(bank.y))
	if river_d > float(SimBoot.RIVER_SOURCE_SPACING):
		push_error("RIVER: the source answered from the bank is %.1f tiles away, further than the %d spacing; that is not the river" % [river_d, SimBoot.RIVER_SOURCE_SPACING])
		return false
	# The true negative: the well must still win for a body standing at the well. Together with the
	# line above this is what makes the lane about *ranking* rather than about the river existing.
	var wp: Dictionary = w.components.get_component(near_well, "position") as Dictionary
	if absf(float(wp["x"]) - (float(well.x) + 0.5)) > 0.01 or absf(float(wp["y"]) - (float(well.y) + 0.5)) > 0.01:
		push_error("RIVER: a body at the well is sent to %s instead of the well itself" % str(wp))
		return false

	# And the reuse: what the river gives is the same untreated bottle the well gives, and the
	# boil rung still cleans it. A river that handed out clean water would be a new mechanic.
	var mara: int = _mara(w)
	if mara < 0:
		push_error("RIVER: no Mara in the booted forest")
		return false
	var filled: int = SimItems.spawn_item(w, "item.water.bottle.untreated", {"tier": "scavenged"})
	if not SimInventory.stow(w, mara, filled):
		push_error("RIVER: could not stow the untreated bottle")
		return false
	if not SimNeeds.boil(w, mara, filled):
		push_error("RIVER: the boil rung refused the untreated bottle the river fills")
		return false
	print("RIVER OK the forest stands %d water sources; a body on the bank at %s is routed to the river %.1f tiles off and one at the well %s is still routed to the well, and the bottle boils clean" % [
		sources.size(), str(bank), river_d, str(well),
	])
	return true


# PATHING: an unreachable target costs one A*, not one per tick forever.
#
# `_walk` re-planned whenever its cached path was empty -- and empty is exactly what `SimPath.find`
# returns when there is no route, so a body standing beside a sealed room re-ran the whole search
# every tick. docs/23's defect list has carried this since the review sweep. Measured while the
# outpost slice was being built: a reachable 100-tile path costs 5-11 ms and a failing one **132
# ms**, and one enclosed item took a booted 256 district from 64.4 ticks/s to **9.8** -- under its
# own 20 Hz clock. With the fix the same fixture runs at 78.4.
func _an_unreachable_target_is_planned_for_once_and_then_dropped() -> bool:
	var w: Variant = _world()
	for it in SimInventory.ground_items(w):
		w.despawn(int(it))
	# Somewhere no route reaches: walled in on every side, so `SimPath.find` answers empty for a
	# reason that is about the map rather than about the distance.
	var start: Vector2i = SimTileMap.player_start(w.tilemap)
	var sealed := Vector2i(-1, -1)
	for y in range(2, int(w.tilemap.h) - 2):
		for x in range(2, int(w.tilemap.w) - 2):
			if SimTileMap.tile_at(w.tilemap, x, y) != SimTileMap.Tile.Floor:
				continue
			if SimTileMap.is_solid(w.tilemap, x, y):
				continue
			if SimPath.find(w, start, Vector2i(x, y)).is_empty():
				sealed = Vector2i(x, y)
				break
		if sealed.x >= 0:
			break
	if sealed.x < 0:
		# No sealed ground on this seed: say so and skip rather than pass quietly.
		print("PATHING SKIP no unroutable floor on seed 20260805 at 64 tiles")
		return true

	var item: int = SimItems.spawn_item(w, "item.scrap.metal", {"tier": "scavenged"})
	w.components.set_component(item, "position", {"x": float(sealed.x) + 0.5, "y": float(sealed.y) + 0.5})
	if SimJobs._is_unreachable(w, item):
		push_error("PATHING: the item was marked before anybody tried to walk to it")
		return false
	# Somebody takes it, fails to route, and the target is marked rather than re-offered.
	for _i in 200:
		w.step()
	if not SimJobs._is_unreachable(w, item):
		push_error("PATHING: nobody marked the sealed item at %s unreachable, so the search re-runs every tick" % str(sealed))
		return false
	var offered: Dictionary = SimJobs._haul_work(w, float(sealed.x) + 0.5, float(sealed.y) + 0.5)
	if int(offered.get("target", -1)) == item:
		push_error("PATHING: the sealed item is still being offered as Haul work after it was marked")
		return false

	# The true negative: a reachable item in the same world must NOT be marked, and must still be
	# offered -- otherwise the lane passes on a marker that fires for everything.
	var near: int = SimItems.spawn_item(w, "item.scrap.metal", {"tier": "scavenged"})
	w.components.set_component(near, "position", {"x": float(start.x) + 1.5, "y": float(start.y) + 0.5})
	for _i in 60:
		w.step()
	if SimJobs._is_unreachable(w, near):
		push_error("PATHING: a reachable item beside the player was marked unreachable, so this lane cannot fail")
		return false
	return true
