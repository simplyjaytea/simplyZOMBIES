extends SceneTree
# The walls keep out what is outside them, not what is already in -- docs/30 and the trace in the
# project's planning folder (trace-dayone.md), where a builder stood 1.9 m from a zombie for 12,000
# ticks inside the house and died to a zombie that had got in.
#
# `jobs.gd`'s `_outside_in_danger` answered "safe" for every colonist inside the walls box, and for
# every colonist anywhere in the annex lot unless the errand's own tile was outside the walls. It
# never looked at the zombies inside. The rule is now: inside the walls, a shambler inside the walls
# within DANGER_METRES breaks the errand off; in the yard, the lot counts as home only while no
# zombie stands in it.
#
# Four lanes, each with its own true negative:
#   WALLS-IN   -- a hauling colonist inside the house, a zombie inside three metres off: walks home.
#   WALLS-OUT  -- the same colonist, the zombie outside the north wall, five and a half metres off:
#                 keeps working. A wall keeps out what is outside it, so this is the true negative.
#   YARD-IN    -- a colonist in the yard with a zombie in the lot three metres off: walks home.
#   YARD-OUT   -- the same colonist, the zombie just outside the lot two metres off, none in the lot:
#                 keeps working, because the lot is home while no zombie is in it.
#
# Every lane asserts its own fixture first (the spot and the zombie are on the tiles the lane says
# they are), so a lane that cannot find its tiles fails loudly rather than passing quietly.

const SimBoot = preload("res://sim/boot.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimRoster = preload("res://sim/modules/roster.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var was: bool = SimJobs.BREAK_OFF_FROM_DANGER
	var ok: bool = true
	ok = _walls_in() and ok
	ok = _walls_out() and ok
	ok = _yard_in() and ok
	ok = _yard_out() and ok
	ok = _retreat_walk_bound() and ok
	ok = _retreat_walk_before_bound() and ok
	ok = _construct_resume_refused() and ok
	ok = _construct_resume_plain() and ok
	ok = _construct_resume_clear() and ok
	SimJobs.BREAK_OFF_FROM_DANGER = was
	if ok:
		print("M2_WALLS_OK a zombie inside the walls 3 m off breaks a hauling colonist's errand off, a zombie outside the walls 5.5 m off does not, a zombie in the yard breaks off a colonist there, and a yard with no zombie in the lot does not; a Retreat whose walk home runs past its bound is re-planned inside in a bounded number of ticks, and before the bound it is left alone; a colonist shaken by a Retreat does not resume Construct at a window with a zombie within 10 m, resumes at one without, and the shake clears when it does")
		quit(0)
	else:
		push_error("M2_WALLS_FAIL")
		quit(1)

# A walk home that has run past RETREAT_WALK_TICKS is re-planned to the nearest tile inside the
# walls. The fixture is a colonist in the north yard with a stale route that leads east, away from
# the house, for eighty tiles: the old walk follows it and never reaches a door in the bound.
func _retreat_walk_bound() -> bool:
	var w: Variant = _world()
	var annex: Rect2i = SimTileMap.annex_rect(w.tilemap)
	var yard: Vector2i = Vector2i(SimTileMap.player_start(w.tilemap).x, annex.position.y + 1)
	var ellis: int = _walk_fixture(w, yard, SimJobs.RETREAT_WALK_TICKS + 1)
	if ellis < 0:
		return false
	for i in range(600):
		SimJobs._tick_one(w, ellis)
		_move(w, ellis)
		var pos: Dictionary = w.components.get_component(ellis, "position") as Dictionary
		if _inside(w, annex, Vector2i(floori(float(pos["x"])), floori(float(pos["y"])))):
			return true
	push_error("RETREAT: a walk home past its %d-tick bound was not re-planned inside within 600 ticks (%s)" % [SimJobs.RETREAT_WALK_TICKS, str(w.components.get_component(ellis, "job"))])
	return false


# Before the bound the same stale route is followed: the job keeps its home tile and is not
# re-planned, so the bound is the only thing that changes a walk home.
func _retreat_walk_before_bound() -> bool:
	var w: Variant = _world()
	var annex: Rect2i = SimTileMap.annex_rect(w.tilemap)
	var yard: Vector2i = Vector2i(SimTileMap.player_start(w.tilemap).x, annex.position.y + 1)
	var ellis: int = _walk_fixture(w, yard, 0)
	if ellis < 0:
		return false
	var home: Vector2i = Vector2i(int(SimJobs._home_centre(w).x), int(SimJobs._home_centre(w).y))
	for i in range(50):
		SimJobs._tick_one(w, ellis)
	var job: Dictionary = w.components.get_component(ellis, "job") as Dictionary
	if String(job.get("kind", "")) != "Retreat" or int(job.get("tx", -1)) != home.x or bool(job.get("rerouted", false)):
		push_error("RETREAT: a walk home inside its bound was re-planned (%s), so the bound is not what decides it" % str(job))
		return false
	return true


# A Retreat job on Ellis at `spot`, a stale eighty-tile route to the east, and the walk counter set.
func _walk_fixture(w: Variant, spot: Vector2i, walked: int) -> int:
	for z in w.components.query(["shambler"]):
		w.despawn(int(z))
	var ellis: int = _ellis(w)
	if ellis < 0:
		push_error("RETREAT: no Ellis in the booted district, so the lane judges nothing")
		return -1
	var home: Vector2 = SimJobs._home_centre(w)
	var route: Array = []
	for step in range(80):
		route.append({"x": spot.x + step + 1, "y": spot.y})
	w.components.set_component(ellis, "position", {"x": float(spot.x) + 0.5, "y": float(spot.y) + 0.5})
	w.components.set_component(ellis, "job", {"kind": "Retreat", "tx": int(home.x), "ty": int(home.y), "ticksLeft": 0, "path": route, "pathGen": int(w.mapGeneration), "walked": walked, "was": ""})
	return ellis


# A colonist shaken by a Retreat does not take a window with a zombie 3 m off it: `_construct_work`
# offers no window at all, or another one, never that one.
func _construct_resume_refused() -> bool:
	var w: Variant = _world()
	var win: Vector2i = _first_window(w)
	if win.x < 0:
		push_error("CONSTRUCT-RESUME: no window in the annex, so the lane judges nothing")
		return false
	var ellis: int = _ellis(w)
	for z in w.components.query(["shambler"]):
		w.despawn(int(z))
	var at: Vector2 = Vector2(float(win.x) + 0.5, float(win.y) + 1.5)
	w.components.set_component(ellis, "position", {"x": at.x, "y": at.y})
	w.components.set_component(ellis, "shaken", {"tick": int(w.tick)})
	SimRoster.spawn_zombie(w, float(win.x) + 3.5, float(win.y) + 0.5, SimRoster.TYPE_SHAMBLER, w.rng.stream("shambler"))
	var got: Dictionary = SimJobs._construct_work(w, at.x, at.y, ellis)
	if got.is_empty():
		if not w.components.has_component(ellis, "shaken"):
			push_error("CONSTRUCT-RESUME: the shake cleared though no window was taken")
			return false
		return true
	var tx: int = int(got.get("tx", -1))
	var ty: int = int(got.get("ty", -1))
	if SimJobs._danger_at(w, float(tx) + 0.5, float(ty) + 0.5, SimJobs.DANGER_TARGET_METRES):
		push_error("CONSTRUCT-RESUME: a shaken colonist took a window with a zombie within %.0f m of it" % SimJobs.DANGER_TARGET_METRES)
		return false
	return true


# Not shaken: the same window with the same zombie is taken, as before the rule.
func _construct_resume_plain() -> bool:
	var w: Variant = _world()
	var win: Vector2i = _first_window(w)
	var ellis: int = _ellis(w)
	for z in w.components.query(["shambler"]):
		w.despawn(int(z))
	var at: Vector2 = Vector2(float(win.x) + 0.5, float(win.y) + 1.5)
	w.components.set_component(ellis, "position", {"x": at.x, "y": at.y})
	w.components.remove(ellis, "shaken")
	SimRoster.spawn_zombie(w, float(win.x) + 3.5, float(win.y) + 0.5, SimRoster.TYPE_SHAMBLER, w.rng.stream("shambler"))
	var got: Dictionary = SimJobs._construct_work(w, at.x, at.y, ellis)
	if int(got.get("tx", -1)) != win.x or int(got.get("ty", -1)) != win.y:
		push_error("CONSTRUCT-RESUME: an unshaken colonist was refused the window (%s)" % str(got))
		return false
	return true


# Shaken, with no zombie near the window: the window is taken, and the shake clears.
func _construct_resume_clear() -> bool:
	var w: Variant = _world()
	var win: Vector2i = _first_window(w)
	var ellis: int = _ellis(w)
	for z in w.components.query(["shambler"]):
		w.despawn(int(z))
	var at: Vector2 = Vector2(float(win.x) + 0.5, float(win.y) + 1.5)
	w.components.set_component(ellis, "position", {"x": at.x, "y": at.y})
	w.components.set_component(ellis, "shaken", {"tick": int(w.tick)})
	var got: Dictionary = SimJobs._construct_work(w, at.x, at.y, ellis)
	if int(got.get("tx", -1)) != win.x or int(got.get("ty", -1)) != win.y:
		push_error("CONSTRUCT-RESUME: a shaken colonist with no zombie near the window was refused it (%s)" % str(got))
		return false
	if w.components.has_component(ellis, "shaken"):
		push_error("CONSTRUCT-RESUME: the shake did not clear when a window was taken")
		return false
	return true


func _first_window(w: Variant) -> Vector2i:
	var annex: Rect2i = SimTileMap.annex_rect(w.tilemap)
	for j in range(annex.position.y, annex.position.y + annex.size.y):
		for i in range(annex.position.x, annex.position.x + annex.size.x):
			if SimTileMap.tile_at(w.tilemap, i, j) == SimTileMap.Tile.Window:
				return Vector2i(i, j)
	return Vector2i(-1, -1)


func _walls_in() -> bool:
	var w: Variant = _world()
	var annex: Rect2i = SimTileMap.annex_rect(w.tilemap)
	var spot: Vector2i = SimTileMap.player_start(w.tilemap)
	var inside: Vector2 = Vector2(float(spot.x) + 3.5, float(spot.y) + 0.5)
	if not _inside(w, annex, spot) or not _inside(w, annex, Vector2i(int(inside.x), int(inside.y))):
		push_error("WALLS-IN: the start tile and the tile three metres east are not both inside the walls, so the lane judges nothing")
		return false
	var got: String = _haul(w, spot, inside)
	if got != "Retreat":
		push_error("WALLS-IN: a zombie inside the walls 3 m off left a hauling colonist on %s, want Retreat" % got)
		return false
	return true

func _walls_out() -> bool:
	var w: Variant = _world()
	var annex: Rect2i = SimTileMap.annex_rect(w.tilemap)
	var spot: Vector2i = SimTileMap.player_start(w.tilemap)
	var outside: Vector2 = Vector2(float(spot.x) + 0.5, float(annex.position.y) + 1.5)
	if not _inside(w, annex, spot) or _inside(w, annex, Vector2i(int(outside.x), int(outside.y))) or not annex.has_point(Vector2i(int(outside.x), int(outside.y))):
		push_error("WALLS-OUT: the start tile is not inside the walls or the yard tile above the north wall is not in the yard, so the lane judges nothing")
		return false
	var got: String = _haul(w, spot, outside)
	if got != "Haul":
		push_error("WALLS-OUT: a zombie outside the walls 5.5 m off broke a colonist inside them off (%s), want Haul" % got)
		return false
	return true

func _yard_in() -> bool:
	var w: Variant = _world()
	var annex: Rect2i = SimTileMap.annex_rect(w.tilemap)
	var yard: Vector2i = Vector2i(SimTileMap.player_start(w.tilemap).x, annex.position.y + 1)
	var lot: Vector2 = Vector2(float(yard.x) + 3.5, float(yard.y) + 0.5)
	if _inside(w, annex, yard) or not annex.has_point(yard) or not annex.has_point(Vector2i(int(lot.x), int(lot.y))):
		push_error("YARD-IN: the yard tile or the lot tile three metres east is not where the lane needs it, so the lane judges nothing")
		return false
	var got: String = _haul(w, yard, lot)
	if got != "Retreat":
		push_error("YARD-IN: a zombie in the lot 3 m off left a colonist in the yard on %s, want Retreat" % got)
		return false
	return true

func _yard_out() -> bool:
	var w: Variant = _world()
	var annex: Rect2i = SimTileMap.annex_rect(w.tilemap)
	var yard: Vector2i = Vector2i(SimTileMap.player_start(w.tilemap).x, annex.position.y + 1)
	var beyond: Vector2 = Vector2(float(yard.x) + 0.5, float(annex.position.y) - 1.5)
	if _inside(w, annex, yard) or annex.has_point(Vector2i(int(beyond.x), int(beyond.y))):
		push_error("YARD-OUT: the yard tile or the tile beyond the lot is not where the lane needs it, so the lane judges nothing")
		return false
	var got: String = _haul(w, yard, beyond)
	if got != "Haul":
		push_error("YARD-OUT: a zombie outside the lot with none in it left a colonist in the yard on %s, want Haul" % got)
		return false
	return true

# One tick of Ellis on Haul at `spot`, one shambler at `zombie`, the lot otherwise empty of them.
# The job kind he ends the tick with.
func _haul(w: Variant, spot: Vector2i, zombie: Vector2) -> String:
	SimJobs.BREAK_OFF_FROM_DANGER = true
	for z in w.components.query(["shambler"]):
		w.despawn(int(z))
	var ellis: int = _ellis(w)
	if ellis < 0:
		push_error("WALLS: no Ellis in the booted district, so the lane judges nothing")
		return "no fixture"
	var item: int = SimItems.spawn_item(w, "item.scrap.metal", {"tier": "scavenged"})
	w.components.set_component(item, "position", {"x": float(spot.x) + 0.5, "y": float(spot.y) + 6.5})
	w.components.set_component(ellis, "position", {"x": float(spot.x) + 0.5, "y": float(spot.y) + 0.5})
	w.components.set_component(ellis, "job", {"kind": "Haul", "target": item, "tx": spot.x, "ty": spot.y + 6, "ticksLeft": 0, "path": [], "pathGen": -1})
	SimRoster.spawn_zombie(w, zombie.x, zombie.y, SimRoster.TYPE_SHAMBLER, w.rng.stream("shambler"))
	SimJobs._tick_one(w, ellis)
	var job: Variant = w.components.get_component(ellis, "job")
	return String((job as Dictionary).get("kind", "")) if job is Dictionary else "none"

# The world step is not run here, so a body's velocity (set by the job's walk) is integrated by hand
# over one tick, at 20 ticks a second.
func _move(w: Variant, ent: int) -> void:
	var pos: Dictionary = w.components.get_component(ent, "position") as Dictionary
	var vel: Variant = w.components.get_component(ent, "velocity")
	if not vel is Dictionary:
		return
	pos["x"] = float(pos["x"]) + float((vel as Dictionary)["dx"]) * 0.05
	pos["y"] = float(pos["y"]) + float((vel as Dictionary)["dy"]) * 0.05
	w.components.set_component(ent, "position", pos)


func _inside(w: Variant, annex: Rect2i, tile: Vector2i) -> bool:
	return SimJobs._inside_walls(w.tilemap, annex, tile.x, tile.y)

func _world() -> Variant:
	return SimBoot.playable(20260805, 64)["world"]

func _ellis(w: Variant) -> int:
	for e in w.components.query(["identity"]):
		var ident: Variant = w.components.get_component(int(e), "identity")
		if ident is Dictionary and String((ident as Dictionary).get("id", "")) == "survivor.unique.ellis":
			return int(e)
	return -1
