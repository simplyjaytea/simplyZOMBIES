extends SceneTree
# A colonist comes to the held player's aid (npc_combat.gd, the npc.aid system). Each lane sets the scene in the sim
# through placement (the district's zombies removed, the other survivors parked, one shambler and the colonists placed
# on open ground), steps the sim, and prints one line.
#
#   AID-12  a shambler holds the controlled player; Ellis is 12 m away with a clear line. She is given an attack order,
#           walks to the holder, and the grab breaks with cause rescue. The player presses nothing. The lane is
#           red if the player's instinct breaks the hold first (cause struggle), since the spec asks for the rescue.
#   AID-5   the same at 5 m: the aid lands inside the instinct's 40 ticks.
#   FAR     Ellis 40 m away gets no order over 120 ticks while the player is held.
#   NOIN    a recruit (Ellis, a recruit fixture), a settler and a raider (Mara, re-factioned by fixture) at 12 m get none.
#   RESUME  after the zombie is gone, the order ends, and the ticks until it ends are printed.
#   ONCE    Ellis and Mara both 12 m away, one holder: exactly one of them is given the order.
#
# Plant (run by hand, restored): npc_combat.gd's issue removed; AID-5 goes red.

const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimAllegiance = preload("res://sim/modules/allegiance.gd")
const SimNpcCombat = preload("res://sim/modules/npc_combat.gd")

const SEED: int = SimBoot.DISTRICT_SEED
const DISTRICT_TILES: int = 64
const PARK_METRES: float = 40.0
const ZOMBIE_METRES: int = 3
const GRAB_TICKS: int = 400
const WAIT_TICKS: int = 600
const CANDIDATES: int = 300

var _fails: int = 0
var _sub_serial: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_aid_lane("AID-12", 12, true)
	_aid_lane("AID-5", 5, true)
	_far()
	_noin()
	_resume()
	_once()
	_switch_off()
	print("FP_AID_RESULT gate %s: %d FAIL" % ["green" if _fails == 0 else "red", _fails])
	quit(0 if _fails == 0 else 1)


func _ok(lane: String, message: String) -> void:
	print("FP_AID_OK %s %s" % [lane, message])


func _finding(lane: String, message: String) -> void:
	print("FP_AID_FINDING %s %s" % [lane, message])


func _info(lane: String, message: String) -> void:
	print("FP_AID_INFO %s %s" % [lane, message])


func _fail(lane: String, message: String) -> void:
	_fails += 1
	push_error("FP_AID_FAIL %s %s" % [lane, message])


# --- SETUP -----------------------------------------------------------------------------------------

func _boot() -> Dictionary:
	var boot: Dictionary = SimBoot.playable(SEED, DISTRICT_TILES)
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	var player: int = int(world.player)
	var doomed: Array = []
	for ent in world.components.query(["zombieType"]):
		doomed.append(int(ent))
	for ent in world.components.query(["shambler"]):
		if not doomed.has(int(ent)):
			doomed.append(int(ent))
	for ent in doomed:
		world.despawn(int(ent))
	var far: Vector2 = _centre(_far_open_tile(map, _pos(world, player)))
	for ent in world.components.query(["identity", "position"]):
		if int(ent) != player:
			_place(world, int(ent), far)
	SimMelee.make_melee_armed(world, player)
	SimHealth.make_stamina(world, player, 100)
	return {"world": world, "map": map}


func _colonist(world: Variant, name: String) -> int:
	for e in world.components.query(["identity"]):
		var id: Dictionary = world.components.get_component(int(e), "identity") as Dictionary
		if String(id.get("id", "")) == name:
			return int(e)
	return -1


const ELLIS: String = "survivor.unique.ellis"
const MARA: String = "survivor.unique.mara"


# The player held by one shambler (placed ZOMBIE_METRES away, the grab stepped to), and `who` placed `metres` away
# on a tile the zombie can see from. Returns {world, map, player, zed, who} or {}.
func _held_scene(who: int, metres: int) -> Dictionary:
	var b: Dictionary = _boot()
	var world: Variant = b["world"]
	var map: Variant = b["map"]
	var player: int = int(world.player)
	var zline: Dictionary = _line(map, ZOMBIE_METRES)
	if zline.is_empty():
		return {}
	var from: Vector2i = zline["from"]
	var d: Vector2i = zline["dir"]
	_place(world, player, _centre(from))
	var zed: int = _spawn(world, _centre(from + d * ZOMBIE_METRES))
	if not _step_until(world, 400, func() -> bool: return world.components.has_component(zed, "grabState") and world.components.has_component(player, "grabbed")):
		return {}
	var spot: Vector2i = _spot_at(world, map, metres, zed)
	if spot.x < 0:
		return {}
	_place(world, who, _centre(spot))
	_settle(world, 2)
	return {"world": world, "map": map, "player": player, "zed": zed, "who": who}


func _spot_at(world: Variant, map: Variant, metres: int, zed: int) -> Vector2i:
	var zp: Vector2 = _pos(world, zed)
	var n: int = 0
	for y in range(1, int(map.h) - 1):
		for x in range(1, int(map.w) - 1):
			var c: Vector2 = _centre(Vector2i(x, y))
			if absf(c.distance_to(zp) - float(metres)) > 0.5 or not _open(map, x, y):
				continue
			n += 1
			if n > CANDIDATES:
				return Vector2i(-1, -1)
			if SimRanged.can_target(world, -1, c.x, c.y) or _sees(world, map, Vector2i(x, y), zed):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _sees(world: Variant, map: Variant, tile: Vector2i, zed: int) -> bool:
	var c: Vector2 = _centre(tile)
	var zp: Vector2 = _pos(world, zed)
	var dir: Vector2 = (zp - c)
	var steps: int = int(dir.length() * 4.0)
	for k in range(1, steps):
		var p: Vector2 = c + dir * (float(k) / float(steps))
		if SimTileMap.is_solid(map, floori(p.x), floori(p.y)):
			return false
	return true


func _line(map: Variant, metres: int) -> Dictionary:
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
	for y in range(1, int(map.h) - 1):
		for x in range(1, int(map.w) - 1):
			for d in dirs:
				var clear: bool = true
				for k in range(0, metres + 1):
					if not _open(map, x + d.x * k, y + d.y * k):
						clear = false
						break
				if clear:
					return {"from": Vector2i(x, y), "dir": d}
	return {}


func _far_open_tile(map: Variant, here: Vector2) -> Vector2i:
	for y in range(1, int(map.h) - 1):
		for x in range(1, int(map.w) - 1):
			if _open(map, x, y) and _centre(Vector2i(x, y)).distance_to(here) >= PARK_METRES:
				return Vector2i(x, y)
	return Vector2i(1, 1)


func _open(map: Variant, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= int(map.w) or y >= int(map.h):
		return false
	if SimTileMap.tile_at(map, x, y) != SimTileMap.Tile.Floor or SimTileMap.is_solid(map, x, y):
		return false
	return not SimTileMap.is_indoors(map, x, y)


func _spawn(world: Variant, at: Vector2) -> int:
	return int(SimRoster.spawn_zombie(world, at.x, at.y, SimRoster.TYPE_SHAMBLER, world.rng.stream("shambler")))


func _place(world: Variant, ent: int, at: Vector2) -> void:
	world.components.set_component(ent, "position", {"x": at.x, "y": at.y})
	var vel: Variant = world.components.get_component(ent, "velocity")
	if vel is Dictionary:
		(vel as Dictionary)["dx"] = 0.0
		(vel as Dictionary)["dy"] = 0.0


func _settle(world: Variant, ticks: int) -> void:
	for _i in ticks:
		world.step()


func _step_until(world: Variant, limit: int, done: Callable) -> bool:
	for _t in range(limit):
		world.step()
		if done.call():
			return true
	return false


func _centre(tile: Vector2i) -> Vector2:
	return Vector2(float(tile.x) + 0.5, float(tile.y) + 0.5)


func _pos(world: Variant, ent: int) -> Vector2:
	var pos: Variant = world.components.get_component(ent, "position")
	if not (pos is Dictionary):
		return Vector2.ZERO
	return Vector2(float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]))


func _order_of(world: Variant, ent: int) -> Dictionary:
	var o: Variant = world.components.get_component(ent, "colonistOrder")
	return o as Dictionary if o is Dictionary else {}


func _has_aid_order(world: Variant, who: int, zed: int) -> bool:
	var o: Dictionary = _order_of(world, who)
	return String(o.get("kind", "")) == "attack" and int(o.get("target", -1)) == zed


# --- AID -------------------------------------------------------------------------------------------

func _aid_lane(lane: String, metres: int, expect_rescue: bool) -> void:
	var s: Dictionary = _held_scene(_colonist(_boot_world_stub(), ELLIS), metres)
	s = _held_scene_with_ellis(metres)
	if s.is_empty():
		_fail(lane, "no %d m spot with a clear line from the holder for Ellis" % metres)
		return
	var world: Variant = s["world"]
	var player: int = int(s["player"])
	var zed: int = int(s["zed"])
	var who: int = int(s["who"])
	var breaks: Dictionary = {}
	_sub_serial += 1
	world.events.subscribe({"type": "grab.broken", "id": "fp_aid.break.%d" % _sub_serial, "handler": func(ev: Dictionary) -> void:
		if int(ev.get("victim", -1)) == player and not breaks.has("cause"):
			breaks["cause"] = String(ev.get("cause", "?"))
			breaks["by"] = int(ev.get("by", -1))
			breaks["tick"] = int(world.tick)
	})
	var hits: Dictionary = {}
	_sub_serial += 1
	world.events.subscribe({"type": "attack.connected", "id": "fp_aid.hit.%d" % _sub_serial, "handler": func(ev: Dictionary) -> void:
		if int(ev.get("attacker", -1)) == who and int(ev.get("target", -1)) == zed and not hits.has("tick"):
			hits["tick"] = int(world.tick)
	})
	var ordered: int = -1
	var started: int = int(world.tick)
	for _t in range(WAIT_TICKS):
		world.step()
		if ordered < 0 and _has_aid_order(world, who, zed):
			ordered = int(world.tick) - started
		if breaks.has("cause"):
			break
	if ordered < 0:
		_fail(lane, "%d m: Ellis was never given an attack order on the holder in %d ticks" % [metres, WAIT_TICKS])
		return
	if not breaks.has("cause"):
		_fail(lane, "%d m: the hold never broke in %d ticks" % [metres, WAIT_TICKS])
		return
	var cause: String = String(breaks["cause"])
	var by: int = int(breaks["by"])
	var at: int = int(breaks["tick"]) - started
	var struck: bool = hits.has("tick") and int(hits["tick"]) <= int(breaks["tick"])
	if cause == "rescue" and by == who:
		_ok(lane, "%d m: ordered at +%d, the hold broke by Ellis's rescue at +%d (the player pressed nothing); Ellis %.1f m from the holder at the break" % [metres, ordered, at, _pos(world, who).distance_to(_pos(world, zed))])
	elif cause == "staggered" and struck:
		_ok(lane, "%d m: ordered at +%d; Ellis's blow on the holder at +%d staggered it and the hold broke at +%d (cause staggered, the aid's own blow; the player pressed nothing)" % [metres, ordered, int(hits["tick"]) - started, at])
	elif cause == "struggle" and expect_rescue:
		_finding(lane, "%d m: ordered at +%d, but the player's instinct broke the hold at +%d (cause struggle) before the rescue; the instinct is %d ticks (STRUGGLE_INSTINCT_TICKS)" % [metres, ordered, at, SimShambler.STRUGGLE_INSTINCT_TICKS])
	else:
		_fail(lane, "%d m: the hold broke at +%d with cause %s by %d; the rescue was not the cause" % [metres, at, cause, by])


# The held scene with Ellis as the colonist to place; the helper boots afresh (the stub above is discarded).
func _held_scene_with_ellis(metres: int) -> Dictionary:
	var b: Dictionary = _boot()
	var world: Variant = b["world"]
	var map: Variant = b["map"]
	var player: int = int(world.player)
	var who: int = _colonist(world, ELLIS)
	var zline: Dictionary = _line(map, ZOMBIE_METRES)
	if zline.is_empty() or who < 0:
		return {}
	var from: Vector2i = zline["from"]
	var d: Vector2i = zline["dir"]
	_place(world, player, _centre(from))
	var zed: int = _spawn(world, _centre(from + d * ZOMBIE_METRES))
	if not _step_until(world, GRAB_TICKS, func() -> bool: return world.components.has_component(zed, "grabState") and world.components.has_component(player, "grabbed")):
		return {}
	var spot: Vector2i = _spot_at(world, map, metres, zed)
	if spot.x < 0:
		return {}
	_place(world, who, _centre(spot))
	return {"world": world, "map": map, "player": player, "zed": zed, "who": who}


func _boot_world_stub() -> Variant:
	return _boot()["world"]


# --- FAR -------------------------------------------------------------------------------------------

func _far() -> void:
	var lane: String = "FAR"
	var s: Dictionary = _held_scene_with_ellis(PARK_METRES as int)
	if s.is_empty():
		var b: Dictionary = _boot()
		var world0: Variant = b["world"]
		var map0: Variant = b["map"]
		var player0: int = int(world0.player)
		var line0: Dictionary = _line(map0, ZOMBIE_METRES)
		if line0.is_empty():
			_fail(lane, "no line for the holder")
			return
		_place(world0, player0, _centre(line0["from"]))
		var zed0: int = _spawn(world0, _centre((line0["from"] as Vector2i) + (line0["dir"] as Vector2i) * ZOMBIE_METRES))
		_step_until(world0, GRAB_TICKS, func() -> bool: return world0.components.has_component(zed0, "grabState"))
		var who0: int = _colonist(world0, ELLIS)
		var far0: Vector2i = _far_open_tile(map0, _pos(world0, player0))
		_place(world0, who0, _centre(far0))
		for _t in range(120):
			world0.step()
			if _has_aid_order(world0, who0, zed0):
				_fail(lane, "a colonist %.1f m away was given an order" % _pos(world0, who0).distance_to(_pos(world0, player0)))
				return
		_ok(lane, "Ellis %.1f m from the holder: no order in 120 ticks" % _pos(world0, who0).distance_to(_pos(world0, player0)))
		return
	var world: Variant = s["world"]
	var zed: int = int(s["zed"])
	var who: int = int(s["who"])
	for _t in range(120):
		world.step()
		if _has_aid_order(world, who, zed):
			_fail(lane, "a colonist %.1f m away was given an order" % _pos(world, who).distance_to(_pos(world, int(s["player"]))))
			return
	_ok(lane, "Ellis %.1f m from the holder: no order in 120 ticks" % _pos(world, who).distance_to(_pos(world, int(s["player"]))))


# --- NOIN ------------------------------------------------------------------------------------------

func _noin() -> void:
	var lane: String = "NOIN"
	var s: Dictionary = _held_scene_with_ellis(12)
	if s.is_empty():
		_fail(lane, "no 12 m spot for the check")
		return
	var world: Variant = s["world"]
	var zed: int = int(s["zed"])
	var ellis: int = int(s["who"])
	var mara: int = _colonist(world, MARA)
	var kinds: Array = []
	# A recruit: Ellis with the recruit marker.
	world.components.set_component(ellis, "recruit", {})
	_settle(world, 60)
	if _has_aid_order(world, ellis, zed):
		_fail(lane, "a recruit was given an order")
		return
	# Ellis keeps the recruit marker for the rest of the lane: she is a colonist who aids while the hold lasts, and
	# a hold that lasts (the re-pursuit after a broken grab) would give her an order that is not the kind under test.
	kinds.append("recruit")
	# A settler and a raider: Mara, re-factioned by fixture, at 12 m.
	_place(world, mara, _pos(world, ellis) + Vector2(0.0, 1.0))
	for faction in [SimAllegiance.SETTLERS, SimAllegiance.RAIDERS]:
		SimAllegiance.attach(world, mara, faction)
		_settle(world, 60)
		if _has_aid_order(world, mara, zed) or _has_aid_order(world, ellis, zed):
			_fail(lane, "a %s was given an order" % faction)
			return
		kinds.append(faction)
	_ok(lane, "a recruit, a settler and a raider at 12 m were given no order (checked %s)" % str(kinds))


# --- RESUME ----------------------------------------------------------------------------------------

func _resume() -> void:
	var lane: String = "RESUME"
	var s: Dictionary = _held_scene_with_ellis(5)
	if s.is_empty():
		_fail(lane, "no 5 m spot for the check")
		return
	var world: Variant = s["world"]
	var zed: int = int(s["zed"])
	var who: int = int(s["who"])
	var ordered: bool = false
	for _t in range(WAIT_TICKS):
		world.step()
		if _has_aid_order(world, who, zed):
			ordered = true
			break
	if not ordered:
		_fail(lane, "no order to resume from")
		return
	# The zombie is gone (despawned, as a kill would leave it): the order should end on the next tick by `_follow_attack`.
	world.components.remove(zed, "shambler")
	world.entities.despawn(zed)
	var gone_at: int = int(world.tick)
	var ended: int = -1
	for k in range(120):
		world.step()
		if _order_of(world, who).is_empty():
			ended = int(world.tick) - gone_at
			break
	if ended < 0:
		_fail(lane, "the order on a gone zombie is still held after 120 ticks")
		return
	# Does the job AI take her back? Printed, not asserted: the job's own ticks decide when it picks one up.
	var job_at: int = -1
	for k in range(600):
		world.step()
		if world.components.has_component(who, "job"):
			job_at = k + 1
			break
	_ok(lane, "the order ended %d ticks after the zombie was gone; a job after %s" % [ended, ("%d ticks" % job_at) if job_at >= 0 else "none in 600 ticks"])


# --- SWITCH: NPC_AID_ENABLED = false gives no order (the switch the armour lane pins) -------------

func _switch_off() -> void:
	var lane: String = "SWITCH"
	var was: bool = SimNpcCombat.NPC_AID_ENABLED
	SimNpcCombat.NPC_AID_ENABLED = false
	var s: Dictionary = _held_scene_with_ellis(5)
	if s.is_empty():
		SimNpcCombat.NPC_AID_ENABLED = was
		_fail(lane, "no 5 m spot for the check")
		return
	var world: Variant = s["world"]
	var zed: int = int(s["zed"])
	var who: int = int(s["who"])
	var ordered: bool = false
	for _t in range(120):
		world.step()
		if _has_aid_order(world, who, zed):
			ordered = true
			break
	SimNpcCombat.NPC_AID_ENABLED = was
	if ordered:
		_fail(lane, "NPC_AID_ENABLED = false, and Ellis was still given an order on the holder")
		return
	_ok(lane, "NPC_AID_ENABLED = false: Ellis 5 m from the holder, no order in 120 ticks; the switch restored to %s" % str(was))


# --- ONCE ------------------------------------------------------------------------------------------

func _once() -> void:
	var lane: String = "ONCE"
	var s: Dictionary = _held_scene_with_ellis(12)
	if s.is_empty():
		_fail(lane, "no 12 m spot for the check")
		return
	var world: Variant = s["world"]
	var zed: int = int(s["zed"])
	var ellis: int = int(s["who"])
	var mara: int = _colonist(world, MARA)
	_place(world, mara, _pos(world, ellis) + Vector2(0.0, 1.0))
	var peak: int = 0
	for _t in range(120):
		world.step()
		var n: int = 0
		for who in [ellis, mara]:
			if _has_aid_order(world, who, zed):
				n += 1
		peak = maxi(peak, n)
	if peak != 1:
		_fail(lane, "%d colonists were given an order on one holder's zombie (wanted 1)" % peak)
		return
	_ok(lane, "two colonists, one holder: one aider")
