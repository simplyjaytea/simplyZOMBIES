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
	SimJobs.BREAK_OFF_FROM_DANGER = was
	if ok:
		print("M2_WALLS_OK a zombie inside the walls 3 m off breaks a hauling colonist's errand off, a zombie outside the walls 5.5 m off does not, a zombie in the yard breaks off a colonist there, and a yard with no zombie in the lot does not")
		quit(0)
	else:
		push_error("M2_WALLS_FAIL")
		quit(1)

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
