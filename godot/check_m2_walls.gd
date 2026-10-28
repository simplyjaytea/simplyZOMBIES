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
# Three more, for the Doctor's leash and the far-side Retreat (docs/23, "Balance after the alpha"):
#   LEASH      -- a Doctor on the walk to a patient out past the errand radius, or with a zombie 8 m
#                 from the patient, lets the job go; the same walk to a patient ten tiles out with
#                 nothing near keeps it. Each drop is red with DOCTOR_LEASH off, and the zombie drop
#                 is red with BREAK_OFF_FROM_DANGER pinned off, the flag the pick asks it under.
#   FAR-SIDE   -- a colonist inside the walls with a zombie inside three metres off: the Retreat aims
#                 at the interior tile farthest from it, and the colonist walks until the distance
#                 has opened. Red with RETREAT_FAR_SIDE off (it aims at home). A zombie outside the
#                 walls keeps the Retreat at home.
#   NO-STAND   -- a colonist holding a Retreat when a zombie comes inside the walls within three
#                 metres re-plans at once, and not again inside RETREAT_REPLAN_TICKS; a zombie outside
#                 the walls at the same distance ends no hold.
#
# Every lane asserts its own fixture first (the spot and the zombie are on the tiles the lane says
# they are), so a lane that cannot find its tiles fails loudly rather than passing quietly.

const SimBoot = preload("res://sim/boot.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimPath = preload("res://sim/path.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var was: bool = SimJobs.BREAK_OFF_FROM_DANGER
	var was_leash: bool = SimJobs.DOCTOR_LEASH
	var was_far: bool = SimJobs.RETREAT_FAR_SIDE
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
	ok = _doctor_leash() and ok
	ok = _far_side() and ok
	ok = _no_stand() and ok
	SimJobs.BREAK_OFF_FROM_DANGER = was
	SimJobs.DOCTOR_LEASH = was_leash
	SimJobs.RETREAT_FAR_SIDE = was_far
	if ok:
		print("M2_WALLS_OK a zombie inside the walls 3 m off breaks a hauling colonist's errand off, a zombie outside the walls 5.5 m off does not, a zombie in the yard breaks off a colonist there, and a yard with no zombie in the lot does not; a Retreat whose walk home runs past its bound is re-planned inside in a bounded number of ticks, and before the bound it is left alone; a colonist shaken by a Retreat does not resume Construct at a window with a zombie within 10 m, resumes at one without, and the shake clears when it does; a Doctor's walk to a patient out past the errand radius or with a zombie 8 m from them is let go, and one to a patient ten tiles out with nothing near is kept; a Retreat from a zombie inside the walls aims at the far side and the colonist opens the distance, and one from a zombie outside the walls aims at home; a colonist holding a Retreat re-plans when a zombie comes inside the walls within 3 m, and not again inside RETREAT_REPLAN_TICKS")
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


# The Doctor's leash. A Doctor is given the pick for a patient ten tiles out (the pick itself, not a
# constructed job), the patient is then moved out past the errand radius, and the Doctor's walk is
# advanced one tick. With the leash the job is let go; with the leash off it is kept.
func _doctor_leash() -> bool:
	var w: Variant = _world()
	var doctor: int = _ellis(w)
	var patient: int = _named(w, "survivor.unique.mara")
	var home: Vector2i = Vector2i(floori(SimJobs._home_centre(w).x), floori(SimJobs._home_centre(w).y))
	var near: Vector2i = _open_at(w, home, 10)
	var far: Vector2i = _open_at(w, home, 30)
	if doctor < 0 or patient < 0 or near.x < 0 or far.x < 0:
		push_error("LEASH: no Doctor, no patient, or no reachable open tile 10 and 30 tiles from home, so the lane judges nothing")
		return false
	if not SimJobs._near_errand(w, float(near.x) + 0.5, float(near.y) + 0.5) or SimJobs._near_errand(w, float(far.x) + 0.5, float(far.y) + 0.5):
		push_error("LEASH: the tile ten tiles out is outside the errand radius, or the tile thirty out is inside it, so the lane judges nothing")
		return false
	_clear_zombies(w)
	w.components.remove(patient, "job")
	w.components.set_component(patient, "injuries", {"wounds": [{"part": "torso"}]})
	w.components.set_component(patient, "position", _at_tile(near))
	w.components.set_component(doctor, "position", _at_tile(home))
	var pick: Dictionary = SimJobs._doctor_work(w, doctor)
	if int(pick.get("target", -1)) != patient:
		push_error("LEASH: the Doctor picked %s, want the patient ten tiles out (%d)" % [str(pick), patient])
		return false

	SimJobs.DOCTOR_LEASH = true
	if _doctor_still_walking(w, doctor, patient, pick, far, null):
		push_error("LEASH: a Doctor walking to a patient 30 tiles out, past the errand radius, kept the job")
		return false
	SimJobs.DOCTOR_LEASH = false
	if not _doctor_still_walking(w, doctor, patient, pick, far, null):
		push_error("LEASH: with DOCTOR_LEASH off the same walk to the patient 30 tiles out was already dropped, so the switch does not decide it")
		return false
	SimJobs.DOCTOR_LEASH = true

	if _doctor_still_walking(w, doctor, patient, pick, near, Vector2(float(near.x) + 8.5, float(near.y) + 0.5)):
		push_error("LEASH: a Doctor walking to a patient with a zombie 8 m from them kept the job")
		return false
	SimJobs.DOCTOR_LEASH = false
	if not _doctor_still_walking(w, doctor, patient, pick, near, Vector2(float(near.x) + 8.5, float(near.y) + 0.5)):
		push_error("LEASH: with DOCTOR_LEASH off a Doctor walking past a zombie 8 m from the patient was dropped, so the switch does not decide it")
		return false
	SimJobs.DOCTOR_LEASH = true
	# The zombie question is the pick's, and the pick asks it only under BREAK_OFF_FROM_DANGER: with
	# that flag pinned off (the colony before the A24 pass, which `godot:m2:jobs` and `godot:m2:storm`
	# pin), the pick hands out this patient and the leash must not drop it.
	var was_danger: bool = SimJobs.BREAK_OFF_FROM_DANGER
	SimJobs.BREAK_OFF_FROM_DANGER = false
	var kept_unpinned: bool = _doctor_still_walking(w, doctor, patient, pick, near, Vector2(float(near.x) + 8.5, float(near.y) + 0.5))
	SimJobs.BREAK_OFF_FROM_DANGER = was_danger
	if not kept_unpinned:
		push_error("LEASH: with BREAK_OFF_FROM_DANGER pinned off, the leash dropped a Doctor walking to a patient with a zombie 8 m off, a patient the pick hands out under that pin")
		return false

	# True negative: the patient stays ten tiles out, nothing near, and the walk is still on after the
	# same five ticks.
	_clear_zombies(w)
	w.components.set_component(patient, "position", _at_tile(near))
	var job: Dictionary = pick.duplicate()
	w.components.set_component(doctor, "job", job)
	for i in range(5):
		var cur: Variant = w.components.get_component(doctor, "job")
		if not (cur is Dictionary) or String((cur as Dictionary).get("kind", "")) != "Doctor":
			push_error("LEASH: a Doctor walking to a patient ten tiles out with nothing near was dropped on tick %d" % i)
			return false
		SimJobs._advance_job(w, doctor, cur as Dictionary)
		_move(w, doctor)
	return true


# One tick of the Doctor's walk to `patient` with the pick in hand, the patient moved to `spot`, and a
# shambler at `zombie` when one is given. True when the Doctor still holds a Doctor job afterwards.
func _doctor_still_walking(w: Variant, doctor: int, patient: int, pick: Dictionary, spot: Vector2i, zombie: Variant) -> bool:
	_clear_zombies(w)
	w.components.set_component(patient, "position", _at_tile(spot))
	if zombie != null:
		SimRoster.spawn_zombie(w, float(zombie.x), float(zombie.y), SimRoster.TYPE_SHAMBLER, w.rng.stream("shambler"))
	var job: Dictionary = pick.duplicate()
	w.components.set_component(doctor, "job", job)
	SimJobs._advance_job(w, doctor, job)
	var now: Variant = w.components.get_component(doctor, "job")
	return now is Dictionary and String((now as Dictionary).get("kind", "")) == "Doctor"


# The far side. A colonist inside the walls, a zombie inside them three metres off (WALLS-IN's
# fixture): the Retreat aims at the interior tile farthest from the zombie, not at home, and the
# colonist walks there until the distance has opened. With the switch off it aims at home. A zombie
# outside the walls keeps the Retreat at home either way.
func _far_side() -> bool:
	var w: Variant = _world()
	var annex: Rect2i = SimTileMap.annex_rect(w.tilemap)
	var spot: Vector2i = SimTileMap.player_start(w.tilemap)
	var zed: Vector2 = Vector2(float(spot.x) + 3.5, float(spot.y) + 0.5)
	if not _inside(w, annex, spot) or not _inside(w, annex, Vector2i(int(zed.x), int(zed.y))):
		push_error("FAR-SIDE: the start tile and the tile three metres east are not both inside the walls, so the lane judges nothing")
		return false
	var ellis: int = _ellis(w)
	if ellis < 0:
		push_error("FAR-SIDE: no Ellis in the booted district, so the lane judges nothing")
		return false
	var home: Vector2i = Vector2i(floori(SimJobs._home_centre(w).x), floori(SimJobs._home_centre(w).y))
	if SimTileMap.is_solid(w.tilemap, home.x, home.y):
		push_error("FAR-SIDE: the home tile is solid, so the home target the lane compares against does not exist")
		return false

	SimJobs.RETREAT_FAR_SIDE = true
	_clear_zombies(w)
	SimRoster.spawn_zombie(w, zed.x, zed.y, SimRoster.TYPE_SHAMBLER, w.rng.stream("shambler"))
	w.components.set_component(ellis, "position", _at_tile(spot))
	if not SimJobs._walls_danger(w, ellis):
		push_error("FAR-SIDE: the colonist and the zombie are not in the walls within 6 m of each other, so the lane judges nothing")
		return false
	SimJobs._retreat(w, ellis, "Haul")
	var job: Dictionary = w.components.get_component(ellis, "job") as Dictionary
	var target := Vector2i(int(job.get("tx", -1)), int(job.get("ty", -1)))
	var zed_tile := Vector2i(int(zed.x), int(zed.y))
	if (target - zed_tile).length_squared() <= (home - zed_tile).length_squared():
		push_error("FAR-SIDE: a Retreat from a zombie inside the walls aimed at %s, no farther from it than home %s" % [str(target), str(home)])
		return false
	if not _inside(w, annex, target):
		push_error("FAR-SIDE: the far-side target %s is outside the walls" % str(target))
		return false

	var start: float = _dist(w.components.get_component(ellis, "position") as Dictionary, zed)
	for i in range(300):
		SimJobs._tick_one(w, ellis)
		_move(w, ellis)
	var end: float = _dist(w.components.get_component(ellis, "position") as Dictionary, zed)
	if end < start + 2.0:
		push_error("FAR-SIDE: after 300 ticks the colonist is %.2f m from the zombie, from %.2f m at the start: the distance did not open" % [end, start])
		return false

	# Switch off: the same colonist, the same zombie, the Retreat aims at home.
	SimJobs.RETREAT_FAR_SIDE = false
	_clear_zombies(w)
	SimRoster.spawn_zombie(w, zed.x, zed.y, SimRoster.TYPE_SHAMBLER, w.rng.stream("shambler"))
	w.components.set_component(ellis, "position", _at_tile(spot))
	SimJobs._retreat(w, ellis, "Haul")
	job = w.components.get_component(ellis, "job") as Dictionary
	if int(job.get("tx", -1)) != home.x or int(job.get("ty", -1)) != home.y:
		push_error("FAR-SIDE: with RETREAT_FAR_SIDE off the Retreat aimed at %s, want home %s" % [str(Vector2i(int(job.get("tx", -1)), int(job.get("ty", -1)))), str(home)])
		return false
	SimJobs.RETREAT_FAR_SIDE = true

	# True negative: a zombie outside the walls, the same colonist: the Retreat aims at home.
	var outside: Vector2 = Vector2(float(spot.x) + 0.5, float(annex.position.y) + 1.5)
	if _inside(w, annex, Vector2i(int(outside.x), int(outside.y))) or not annex.has_point(Vector2i(int(outside.x), int(outside.y))):
		push_error("FAR-SIDE: the tile above the north wall is not in the yard, so the outside case judges nothing")
		return false
	_clear_zombies(w)
	SimRoster.spawn_zombie(w, outside.x, outside.y, SimRoster.TYPE_SHAMBLER, w.rng.stream("shambler"))
	SimJobs._retreat(w, ellis, "Haul")
	job = w.components.get_component(ellis, "job") as Dictionary
	if int(job.get("tx", -1)) != home.x or int(job.get("ty", -1)) != home.y:
		push_error("FAR-SIDE: a Retreat from a zombie outside the walls aimed at %s, want home %s" % [str(Vector2i(int(job.get("tx", -1)), int(job.get("ty", -1)))), str(home)])
		return false
	return true


# The re-plan. A colonist holding a far-side Retreat, the hold begun long before, has a zombie come
# inside the walls three metres off: the hold ends and a new walk is planned on the same tick. Inside
# the RETREAT_REPLAN_TICKS window that follows a re-plan, a zombie still inside the walls does not
# re-plan the walk again. A zombie outside the walls at the same distance ends no hold.
func _no_stand() -> bool:
	var w: Variant = _world()
	var annex: Rect2i = SimTileMap.annex_rect(w.tilemap)
	var spot: Vector2i = SimTileMap.player_start(w.tilemap)
	var zed: Vector2 = Vector2(float(spot.x) + 3.5, float(spot.y) + 0.5)
	if not _inside(w, annex, spot) or not _inside(w, annex, Vector2i(int(zed.x), int(zed.y))):
		push_error("NO-STAND: the start tile and the tile three metres east are not both inside the walls, so the lane judges nothing")
		return false
	var ellis: int = _ellis(w)
	if ellis < 0:
		push_error("NO-STAND: no Ellis in the booted district, so the lane judges nothing")
		return false
	SimJobs.RETREAT_FAR_SIDE = true
	var now: int = int(w.tick)

	# Positive: the hold has no re-plan on record, so the zombie inside the walls re-plans it now.
	_clear_zombies(w)
	SimRoster.spawn_zombie(w, zed.x, zed.y, SimRoster.TYPE_SHAMBLER, w.rng.stream("shambler"))
	w.components.set_component(ellis, "position", _at_tile(spot))
	if not SimJobs._walls_danger(w, ellis):
		push_error("NO-STAND: the colonist and the zombie inside the walls are not within 6 m, so the lane judges nothing")
		return false
	var hold: Dictionary = _hold_at(spot, now, -1)
	w.components.set_component(ellis, "job", hold)
	SimJobs._advance_job(w, ellis, hold)
	var job: Dictionary = w.components.get_component(ellis, "job") as Dictionary
	if job.has("until") or not job.has("replanAt"):
		push_error("NO-STAND: a colonist holding with a zombie 3 m off inside the walls was not re-planned (%s)" % str(job))
		return false

	# Window: a re-plan made this tick is not made again while the window runs.
	hold = _hold_at(spot, now, now)
	w.components.set_component(ellis, "job", hold)
	SimJobs._advance_job(w, ellis, hold)
	job = w.components.get_component(ellis, "job") as Dictionary
	if not job.has("until") or int(job.get("replanAt", -1)) != now:
		push_error("NO-STAND: a hold re-planned inside its RETREAT_REPLAN_TICKS window of %d (%s)" % [SimJobs.RETREAT_REPLAN_TICKS, str(job)])
		return false

	# Due: the same hold, its last re-plan a full window ago, is re-planned again.
	hold = _hold_at(spot, now, now - SimJobs.RETREAT_REPLAN_TICKS)
	w.components.set_component(ellis, "job", hold)
	SimJobs._advance_job(w, ellis, hold)
	job = w.components.get_component(ellis, "job") as Dictionary
	if job.has("until") or int(job.get("replanAt", -1)) != now:
		push_error("NO-STAND: a hold whose last re-plan was %d ticks ago was not re-planned (%s)" % [SimJobs.RETREAT_REPLAN_TICKS, str(job)])
		return false

	# True negative: the zombie stands outside the walls, the same distance, and ends no hold.
	var outside: Vector2 = Vector2(float(spot.x) + 0.5, float(annex.position.y) + 1.5)
	if _inside(w, annex, Vector2i(int(outside.x), int(outside.y))) or not annex.has_point(Vector2i(int(outside.x), int(outside.y))):
		push_error("NO-STAND: the tile above the north wall is not in the yard, so the outside case judges nothing")
		return false
	if not SimJobs._danger_at(w, float(spot.x) + 0.5, float(spot.y) + 0.5, SimJobs.DANGER_METRES):
		push_error("NO-STAND: the zombie outside the walls is not within %.0f m of the colonist, so the lane judges nothing" % SimJobs.DANGER_METRES)
		return false
	_clear_zombies(w)
	SimRoster.spawn_zombie(w, outside.x, outside.y, SimRoster.TYPE_SHAMBLER, w.rng.stream("shambler"))
	hold = _hold_at(spot, now, -1)
	w.components.set_component(ellis, "job", hold)
	SimJobs._advance_job(w, ellis, hold)
	job = w.components.get_component(ellis, "job") as Dictionary
	if not job.has("until") or job.has("replanAt"):
		push_error("NO-STAND: a zombie outside the walls ended a colonist's hold (%s)" % str(job))
		return false
	return true


# A Retreat holding at `spot`, its hold begun on `now`, and its last re-plan at `replan_at` (-1 for
# none, which leaves the key absent).
func _hold_at(spot: Vector2i, now: int, replan_at: int) -> Dictionary:
	var hold: Dictionary = {"kind": "Retreat", "tx": spot.x, "ty": spot.y, "ticksLeft": 0, "path": [], "pathGen": -1, "was": "", "until": now + SimJobs.RETREAT_HOLD_TICKS, "rerouted": true}
	if replan_at >= 0:
		hold["replanAt"] = replan_at
	return hold


# A reachable open tile `dist` tiles from `centre`, on one of the eight compass lines, or (-1, -1).
func _open_at(w: Variant, centre: Vector2i, dist: int) -> Vector2i:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var t: Vector2i = centre + d * dist
		if t.x < 0 or t.y < 0 or t.x >= w.tilemap.w or t.y >= w.tilemap.h:
			continue
		if SimTileMap.is_solid(w.tilemap, t.x, t.y):
			continue
		if SimPath.find(w, centre, t).is_empty():
			continue
		return t
	return Vector2i(-1, -1)


func _clear_zombies(w: Variant) -> void:
	for z in w.components.query(["shambler"]):
		w.despawn(int(z))


func _at_tile(t: Vector2i) -> Dictionary:
	return {"x": float(t.x) + 0.5, "y": float(t.y) + 0.5}


func _dist(pos: Dictionary, zed: Vector2) -> float:
	return Vector2(float(pos["x"]), float(pos["y"])).distance_to(zed)


func _named(w: Variant, id: String) -> int:
	for e in w.components.query(["identity"]):
		var ident: Variant = w.components.get_component(int(e), "identity")
		if ident is Dictionary and String((ident as Dictionary).get("id", "")) == id:
			return int(e)
	return -1
