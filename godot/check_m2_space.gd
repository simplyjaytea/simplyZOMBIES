extends SceneTree
# The segment gate (docs/40, slice 2: "The segment, and melee stops going through walls").
# `SimSpace.segment_clear` is the one answer to "is anything in the way" with a height, and the three
# blows the sim resolves -- a survivor's swing (`SimMelee._resolve_strike`), a zombie's claw and grab
# (`SimShambler._clear_contact`) and a colonist's walk to the fight (`SimNpcCombat.can_strike`) --
# all ask it through `SimSpace.reach_clear`. Printed as M2_SPACE_OK or M2_SPACE_FAIL.
#
# Lanes, each with a true positive and a true negative:
#   PAIRS     a segment across one tile, for every case docs/40 names (wall, window, sill, lintel,
#             board stages, closed and open door, doorway lintel, Low, screen, fence, tree, water),
#             each answered for SIGHT, SHOT and REACH, and each paired with the height or tile that
#             flips it. A sloped segment that dips under a sill is refused and one that stays above
#             it is not.
#   ENDS      a body is not obstructed by the open tile it stands in (a point in a Low tile reaches
#             out), but the same Low tile between two points is in the way, and a point inside a
#             wall is inside the wall.
#   CORNER    a segment through the exact corner where two walls meet diagonally is refused; the same
#             segment with the walls gone is clear.
#   MIRROR    over a seeded map of every class and overlay, each segment gives the same answer
#             asked twice, asked backwards, and asked of the map and segment reflected left to
#             right. Both answers occur, so the lane is not judging one kind.
#   SWING     the live swing: a survivor 1.70 m from a zombie with a one-metre wall between does not
#             land (it did before this slice); the same swing through an open window, an open
#             doorway and open ground lands; crouched, the window's sill refuses it; and a blocked
#             nearer body is passed over for a clear farther one.
#   READS     each of the three callers refuses where only `segment_clear` can: a Low tile, which
#             `world.is_blocked_tile` reports open, between a crouched body and its mark. The
#             swing (`_resolve_strike`), the claw and grab (`_clear_contact`, through the live
#             shambler loop) and the attack walk (`can_strike`) each refuse crouched and land
#             standing, and each lands crouched with the Low tile replaced by floor.

const World = preload("res://sim/world.gd")
const SimSpace = preload("res://sim/space/space.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimNpcCombat = preload("res://sim/modules/npc_combat.gd")
const SimCombat = preload("res://sim/combat.gd")
const SimStances = preload("res://sim/stances.gd")

const T: int = SimTileMap.Tile.Floor
const PURPOSES: Array = [["SIGHT", SimSpace.SIGHT], ["SHOT", SimSpace.SHOT], ["REACH", SimSpace.REACH]]
# The swing geometry docs/40 names: two bodies pressed to either face of a one-metre tile, 1.70 m
# apart, inside a bat's 1.75 m (1.4 plus MELEE_REACH_FUDGE).
const SWING_FROM_X: float = 15.65
const SWING_TO_X: float = 17.35
const ROW_Y: float = 16.5
const COLUMN_X: int = 16

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = _pairs()
	ok = _ends() and ok
	ok = _corner() and ok
	ok = _mirror() and ok
	ok = _swing() and ok
	ok = _reads() and ok
	if ok:
		print("M2_SPACE_OK every wall, window, sill, lintel, board, door, Low, screen and fence case answers each purpose and flips with its pair; a swing through a wall is refused and through a window lands; mirrored segments agree; the swing, the claw and the attack walk each read segment_clear")
		quit(0)
		return
	for failure in _failures:
		push_error("M2_SPACE_FAIL " + failure)
	quit(1)


func _fail(lane: String, message: String) -> bool:
	_failures.append(lane + ": " + message)
	return false


# --- fixtures --------------------------------------------------------------------------------

# A 3x3 map, open but for the tile under test at (1, 1); the segment runs along y = 1.5.
func _one_tile(tile: int, overlay: Variant) -> Variant:
	var map: Variant = SimTileMap.blank_map(3, 3)
	map.tiles[1 * 3 + 1] = tile
	if overlay != null:
		map.overlays[1 * 3 + 1] = overlay
	return map


func _pt(x: float, y: float, h: int) -> Dictionary:
	return {"x": x, "y": y, "h": h}


# A fixture world on a real tile map: open ground, with `tile` (and `overlay`) down column 16 on
# rows 15 to 17, so the row the bodies stand on crosses exactly one of them.
func _column_world(seed_val: int, stance: int, tile: int, overlay: Variant = null) -> Variant:
	var fixture: Dictionary = {
		"seed": seed_val,
		"tick_hz": 20,
		"map": {"width": 32, "height": 32, "walls": []},
		"player": {"id": 0, "x": SWING_FROM_X, "y": ROW_Y, "stance": stance},
		"rng_probe": {"stream": "test", "samples": 0},
	}
	var w: Variant = World.new(fixture)
	var map: Variant = SimTileMap.blank_map(32, 32)
	for ty in [15, 16, 17]:
		map.tiles[int(ty) * 32 + COLUMN_X] = tile
		if overlay != null:
			map.overlays[int(ty) * 32 + COLUMN_X] = overlay
	w.adopt_map(map)
	SimHealth.register_module(w)
	SimHealth.make_survivor_body(w, w.player)
	SimHealth.make_stamina(w, w.player, 100)
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	return w


# A zombie that only stands there: a body, a position, and `zombieType` so SimSpace reads a
# zombie's cylinder. No AI is registered for it.
func _zombie(w: Variant, x: float, y: float) -> int:
	var ent: int = int(w.entities.spawn())
	w.components.set_component(ent, "position", {"x": x, "y": y})
	w.components.set_component(ent, "velocity", {"dx": 0.0, "dy": 0.0})
	w.components.set_component(ent, "body", SimCombat.ZOMBIE_BODY.duplicate())
	w.components.set_component(ent, "zombieType", {"id": "zombie.shambler"})
	return ent


# --- PAIRS -----------------------------------------------------------------------------------

func _pairs() -> bool:
	var lane: String = "PAIRS"
	var board: Callable = func(stage: int) -> Dictionary: return {"kind": "board", "stage": stage}
	var shut: Dictionary = {"kind": "door", "open": false, "stage": 0}
	var ajar: Dictionary = {"kind": "door", "open": true, "stage": 0}
	# [label, tile, overlay, h from, h to, sight clear, shot clear, reach clear]. Listed in pairs: the
	# row after each refusal is the height or tile that turns it clear, or the other way round.
	var cases: Array = [
		["wall at chest height", SimTileMap.Tile.Wall, null, 1300, 1300, false, false, false],
		["over the wall's top", SimTileMap.Tile.Wall, null, 2600, 2600, true, true, true],
		["open floor", T, null, 1300, 1300, true, true, true],
		["through a window's aperture", SimTileMap.Tile.Window, null, 1300, 1300, true, true, true],
		["into a window's sill", SimTileMap.Tile.Window, null, 900, 900, false, false, false],
		["a crouched eye under the sill", SimTileMap.Tile.Window, null, 950, 950, false, false, false],
		["level with the sill's top", SimTileMap.Tile.Window, null, 1000, 1000, true, true, true],
		["into a window's lintel", SimTileMap.Tile.Window, null, 2200, 2200, false, false, false],
		["just under the window's lintel", SimTileMap.Tile.Window, null, 2050, 2050, true, true, true],
		["sloping under the sill inside the tile", SimTileMap.Tile.Window, null, 1500, 500, false, false, false],
		["sloping but above the sill", SimTileMap.Tile.Window, null, 1500, 1100, true, true, true],
		["a full board", SimTileMap.Tile.Window, board.call(0), 1300, 1300, false, false, false],
		["a board at stage 2", SimTileMap.Tile.Window, board.call(2), 1300, 1300, false, false, false],
		["above a stage-3 board", SimTileMap.Tile.Window, board.call(3), 1300, 1300, true, true, true],
		["into a stage-3 board", SimTileMap.Tile.Window, board.call(3), 1000, 1000, false, false, false],
		["a stage-3 board's top band stops movement only", SimTileMap.Tile.Window, board.call(3), 2300, 2300, true, true, true],
		["a closed door", SimTileMap.Tile.Door, shut, 1300, 1300, false, false, false],
		["an open door", SimTileMap.Tile.Door, ajar, 1300, 1300, true, true, true],
		["a doorway with no door", SimTileMap.Tile.Door, null, 1300, 1300, true, true, true],
		["into an open door's lintel", SimTileMap.Tile.Door, ajar, 2300, 2300, false, false, false],
		["under an open door's lintel", SimTileMap.Tile.Door, ajar, 2100, 2100, true, true, true],
		["over a Low tile", SimTileMap.Tile.Low, null, 1200, 1200, true, true, true],
		["into a Low tile", SimTileMap.Tile.Low, null, 1000, 1000, false, false, false],
		["a screen stops an eye and a round, not a hand", SimTileMap.Tile.Screen, null, 1300, 1300, false, false, true],
		["a wire fence stops a hand, not an eye or a round", T, {"kind": "fence"}, 1300, 1300, true, true, false],
		["over the wire fence", T, {"kind": "fence"}, 2100, 2100, true, true, true],
		["a tree", SimTileMap.Tile.Tree, null, 1300, 1300, false, false, false],
		["across deep water", SimTileMap.Tile.Water, null, 300, 300, true, true, true],
		["a scrap barricade", T, {"kind": "scrap"}, 1300, 1300, false, false, false],
		["a timber wall", T, {"kind": "timber"}, 1300, 1300, false, false, false],
		["a stone wall", T, {"kind": "stone"}, 1300, 1300, false, false, false],
		# The geometry the reach's second target point exists for: a standing shoulder to a zombie's
		# mid-height dips under the sill before the far face; to its chest it does not.
		["a shoulder to a zombie's mid-height, through a window", SimTileMap.Tile.Window, null, 1220, 825, false, false, false],
		["a shoulder to a zombie's chest, through a window", SimTileMap.Tile.Window, null, 1220, 1237, true, true, true],
	]
	var ok: bool = true
	var clear_seen: Dictionary = {}
	var refused_seen: Dictionary = {}
	for c in cases:
		var row: Array = c as Array
		var map: Variant = _one_tile(int(row[1]), row[2])
		var a: Dictionary = _pt(0.5, 1.5, int(row[3]))
		var b: Dictionary = _pt(2.5, 1.5, int(row[4]))
		for i in PURPOSES.size():
			var name: String = String((PURPOSES[i] as Array)[0])
			var purpose: int = int((PURPOSES[i] as Array)[1])
			var want: bool = bool(row[5 + i])
			var got: bool = SimSpace.segment_clear(map, a, b, purpose)
			if got != want:
				ok = _fail(lane, "%s: %s answered %s, wants %s" % [String(row[0]), name, "clear" if got else "refused", "clear" if want else "refused"])
			if got:
				clear_seen[name] = true
			else:
				refused_seen[name] = true
	for p in PURPOSES:
		var name2: String = String((p as Array)[0])
		if not clear_seen.has(name2) or not refused_seen.has(name2):
			ok = _fail(lane, "%s never saw both answers, so this lane judges one kind" % name2)
	if ok:
		print("  PAIRS %d cases x 3 purposes, each paired with the height or tile that flips it" % cases.size())
	return ok


# --- ENDS ------------------------------------------------------------------------------------

func _ends() -> bool:
	var lane: String = "ENDS"
	var ok: bool = true
	var map: Variant = SimTileMap.blank_map(6, 3)
	map.tiles[1 * 6 + 1] = SimTileMap.Tile.Low
	map.tiles[1 * 6 + 4] = SimTileMap.Tile.Wall
	# Standing in the Low tile and reaching out at knee height: the tile you stand in is not in the way.
	if not SimSpace.segment_clear(map, _pt(1.5, 1.5, 500), _pt(3.5, 1.5, 500), SimSpace.REACH):
		ok = _fail(lane, "a point standing in a Low tile was obstructed by its own tile")
	# The same Low tile between the two points is.
	if SimSpace.segment_clear(map, _pt(0.5, 1.5, 500), _pt(2.5, 1.5, 500), SimSpace.REACH):
		ok = _fail(lane, "a Low tile between two points at 500 mm did not obstruct them")
	# A point inside a wall is inside the wall: a solid endpoint tile still counts.
	if SimSpace.segment_clear(map, _pt(3.5, 1.5, 1300), _pt(4.5, 1.5, 1300), SimSpace.REACH):
		ok = _fail(lane, "a point inside a wall tile was reachable")
	if not SimSpace.segment_clear(map, _pt(2.5, 1.5, 1300), _pt(3.5, 1.5, 1300), SimSpace.REACH):
		ok = _fail(lane, "two points on open floor beside the wall were refused")
	if ok:
		print("  ENDS a body's own open tile is not in its way; the same tile between two points is, and a wall endpoint is")
	return ok


# --- CORNER ----------------------------------------------------------------------------------

func _corner() -> bool:
	var lane: String = "CORNER"
	var ok: bool = true
	var open: Variant = SimTileMap.blank_map(4, 4)
	var checker: Variant = SimTileMap.blank_map(4, 4)
	checker.tiles[1 * 4 + 2] = SimTileMap.Tile.Wall
	checker.tiles[2 * 4 + 1] = SimTileMap.Tile.Wall
	var a: Dictionary = _pt(1.5, 1.5, 1300)
	var b: Dictionary = _pt(2.5, 2.5, 1300)
	for p in PURPOSES:
		var purpose: int = int((p as Array)[1])
		if SimSpace.segment_clear(checker, a, b, purpose) or SimSpace.segment_clear(checker, b, a, purpose):
			ok = _fail(lane, "%s slipped through the corner where two walls meet diagonally" % String((p as Array)[0]))
		if not SimSpace.segment_clear(open, a, b, purpose):
			ok = _fail(lane, "%s was refused through an open corner" % String((p as Array)[0]))
	if ok:
		print("  CORNER the diagonal crack between two walls is closed; the open corner is clear")
	return ok


# --- MIRROR ----------------------------------------------------------------------------------

func _mirror() -> bool:
	var lane: String = "MIRROR"
	var size: int = 24
	var rng := RandomNumberGenerator.new()
	rng.seed = 4040
	var classes: Array = [T, T, T, T, SimTileMap.Tile.Wall, SimTileMap.Tile.Window, SimTileMap.Tile.Screen, SimTileMap.Tile.Low, SimTileMap.Tile.Tree, SimTileMap.Tile.Door, SimTileMap.Tile.Water]
	var overlays: Array = [{"kind": "board", "stage": 0}, {"kind": "board", "stage": 3}, {"kind": "door", "open": true, "stage": 0}, {"kind": "door", "open": false, "stage": 0}, {"kind": "fence"}, {"kind": "scrap"}]
	var map: Variant = SimTileMap.blank_map(size, size)
	var flipped: Variant = SimTileMap.blank_map(size, size)
	for ty in size:
		for tx in size:
			var tile: int = int(classes[rng.randi_range(0, classes.size() - 1)])
			var over: Variant = null
			if rng.randi_range(0, 9) == 0:
				over = overlays[rng.randi_range(0, overlays.size() - 1)]
			map.tiles[ty * size + tx] = tile
			flipped.tiles[ty * size + (size - 1 - tx)] = tile
			if over != null:
				map.overlays[ty * size + tx] = over
				flipped.overlays[ty * size + (size - 1 - tx)] = over
	var ok: bool = true
	var clear: int = 0
	var refused: int = 0
	for i in 600:
		# Sixteenths offset by a thirty-second: never on a tile edge, often exactly through a corner.
		var a: Dictionary = _pt(float(rng.randi_range(0, size * 16 - 1)) / 16.0 + 1.0 / 32.0, float(rng.randi_range(0, size * 16 - 1)) / 16.0 + 1.0 / 32.0, rng.randi_range(0, 2600))
		var b: Dictionary = _pt(float(a["x"]) + float(rng.randi_range(-64, 64)) / 16.0, float(a["y"]) + float(rng.randi_range(-64, 64)) / 16.0, rng.randi_range(0, 2600))
		b["x"] = clampf(float(b["x"]), 1.0 / 32.0, float(size) - 1.0 / 32.0)
		b["y"] = clampf(float(b["y"]), 1.0 / 32.0, float(size) - 1.0 / 32.0)
		var ma: Dictionary = _pt(float(size) - float(a["x"]), float(a["y"]), int(a["h"]))
		var mb: Dictionary = _pt(float(size) - float(b["x"]), float(b["y"]), int(b["h"]))
		for p in PURPOSES:
			var purpose: int = int((p as Array)[1])
			var first: bool = SimSpace.segment_clear(map, a, b, purpose)
			if SimSpace.segment_clear(map, a, b, purpose) != first:
				ok = _fail(lane, "segment %d (%s) answered differently asked twice" % [i, String((p as Array)[0])])
			if SimSpace.segment_clear(map, b, a, purpose) != first:
				ok = _fail(lane, "segment %d (%s) from %s to %s answered differently backwards" % [i, String((p as Array)[0]), str(a), str(b)])
			if SimSpace.segment_clear(flipped, ma, mb, purpose) != first:
				ok = _fail(lane, "segment %d (%s) from %s to %s answered differently reflected" % [i, String((p as Array)[0]), str(a), str(b)])
			if first:
				clear += 1
			else:
				refused += 1
	if clear == 0 or refused == 0:
		ok = _fail(lane, "%d clear and %d refused: the lane saw only one answer" % [clear, refused])
	if ok:
		print("  MIRROR 600 segments x 3 purposes agree twice, backwards and reflected (%d clear, %d refused)" % [clear, refused])
	return ok


# --- SWING -----------------------------------------------------------------------------------

# How many of the player's swings connect, and with whom, over one swing's wind-up and recovery.
func _swing_hits(w: Variant) -> Array:
	SimMelee.register_module(w)
	SimMelee.make_melee_armed(w, w.player)
	var hits: Array = []
	w.events.subscribe({"id": "gate.space-hits", "type": "attack.connected", "handler": func(e: Dictionary) -> void:
		if int(e.get("attacker", -1)) == int(w.player):
			hits.append(int(e["target"]))
	})
	w.commands.push({"type": "swing"})
	for i in 60:
		w.step()
	return hits


func _swing() -> bool:
	var lane: String = "SWING"
	var ok: bool = true
	var gap: float = SWING_TO_X - SWING_FROM_X
	var reach: float = 1.4 + SimMelee.MELEE_REACH_FUDGE
	if gap > reach:
		return _fail(lane, "the bodies are %.2f m apart, past the bat's %.2f m: this lane would be measuring reach" % [gap, reach])
	var rows: Array = [
		["a wall between", SimTileMap.Tile.Wall, null, SimStances.Stance.Walk, 0],
		["an open window between", SimTileMap.Tile.Window, null, SimStances.Stance.Walk, 1],
		["an open doorway between", SimTileMap.Tile.Door, null, SimStances.Stance.Walk, 1],
		["an open door between", SimTileMap.Tile.Door, {"kind": "door", "open": true, "stage": 0}, SimStances.Stance.Walk, 1],
		["a closed door between", SimTileMap.Tile.Door, {"kind": "door", "open": false, "stage": 0}, SimStances.Stance.Walk, 0],
		["open ground", T, null, SimStances.Stance.Walk, 1],
		["an open window, crouched under its sill", SimTileMap.Tile.Window, null, SimStances.Stance.Crouch, 0],
		["open ground, crouched", T, null, SimStances.Stance.Crouch, 1],
	]
	for r in rows:
		var row: Array = r as Array
		var w: Variant = _column_world(7100, int(row[3]), int(row[1]), row[2])
		var zed: int = _zombie(w, SWING_TO_X, ROW_Y)
		var hits: Array = _swing_hits(w)
		var want: int = int(row[4])
		if hits.size() != want or (want == 1 and int(hits[0]) != zed):
			ok = _fail(lane, "%s: the swing connected %d times (%s), wants %d" % [String(row[0]), hits.size(), str(hits), want])
	# Nearest-first counts only a body the blow can arrive at. A is nearer, with the wall's corner
	# between; B is a hair farther, in the clear. With the wall the swing finds B; without it, A.
	for walled in [true, false]:
		var w2: Variant = _column_world(7101, SimStances.Stance.Walk, T)
		if walled:
			w2.tilemap.tiles[16 * 32 + COLUMN_X] = SimTileMap.Tile.Wall
			w2.adopt_map(w2.tilemap)
		(w2.components.get_component(w2.player, "position") as Dictionary)["y"] = 17.2
		var near: int = _zombie(w2, 17.2, 16.5)
		var far: int = _zombie(w2, 17.3, 17.65)
		var hits2: Array = _swing_hits(w2)
		var want2: int = far if walled else near
		if hits2.size() != 1 or int(hits2[0]) != want2:
			ok = _fail(lane, "nearest-first %s: the swing hit %s, wants only %d" % ["with the wall" if walled else "without the wall", str(hits2), want2])
	if ok:
		print("  SWING through a wall refused, through a window, doorway and open door landed, crouched under the sill refused; a blocked nearer body is passed over")
	return ok


# --- READS -----------------------------------------------------------------------------------

func _reads() -> bool:
	var ok: bool = _reads_swing()
	ok = _reads_contact() and ok
	ok = _reads_can_strike() and ok
	return ok


# A Low tile is open ground to the old solidity test; only the height profile puts it in the way.
func _low_is_open_to_solidity(lane: String, w: Variant, tx: int, ty: int) -> bool:
	if w.is_blocked_tile(tx, ty):
		return _fail(lane, "the Low tile reads as blocked to world.is_blocked_tile, so this lane cannot prove the refusal is segment_clear's")
	return true


func _reads_swing() -> bool:
	var lane: String = "READS _resolve_strike"
	var ok: bool = true
	var rows: Array = [
		["crouched behind a Low tile", SimTileMap.Tile.Low, SimStances.Stance.Crouch, 0],
		["standing behind a Low tile", SimTileMap.Tile.Low, SimStances.Stance.Walk, 1],
		["crouched on open ground", T, SimStances.Stance.Crouch, 1],
	]
	for r in rows:
		var row: Array = r as Array
		var w: Variant = _column_world(7200, int(row[2]), int(row[1]))
		if int(row[1]) == SimTileMap.Tile.Low and not _low_is_open_to_solidity(lane, w, COLUMN_X, 16):
			return false
		_zombie(w, SWING_TO_X, ROW_Y)
		var hits: Array = _swing_hits(w)
		if hits.size() != int(row[3]):
			ok = _fail(lane, "%s: the swing connected %d times, wants %d" % [String(row[0]), hits.size(), int(row[3])])
	if ok:
		print("  READS _resolve_strike refuses a crouched swing over a Low tile solidity calls open, and lands standing")
	return ok


# The live shambler loop: a pursuing shambler that cannot move, diagonally across a Low tile's corner
# from the player, 0.99 m off. Contact is a swipe or a grab, whichever the loop reaches first; both go
# through `_clear_contact`. Crouched, the line to the player's middle and chest runs under the Low
# tile's top; standing, the line to the chest clears it.
func _contact(seed_val: int, stance: int, tile: int) -> Dictionary:
	var w: Variant = _column_world(seed_val, stance, T)
	w.tilemap.tiles[16 * 32 + COLUMN_X] = tile
	w.adopt_map(w.tilemap)
	var pos: Dictionary = w.components.get_component(w.player, "position") as Dictionary
	pos["x"] = 15.85
	pos["y"] = 16.5
	SimShambler.register_module(w, null)
	var zed: int = int(w.entities.spawn())
	w.components.set_component(zed, "position", {"x": 16.5, "y": 17.25})
	w.components.set_component(zed, "velocity", {"dx": 0.0, "dy": 0.0})
	w.components.set_component(zed, "facing", {"radians": 0.0})
	w.components.set_component(zed, "body", SimCombat.ZOMBIE_BODY.duplicate())
	w.components.set_component(zed, "zombieType", {"id": "zombie.shambler", "tint": ""})
	SimShambler.make_shambler(w, zed, w.rng.stream("shambler"))
	var sd: Dictionary = w.components.get_component(zed, "shambler") as Dictionary
	sd["seekSpeed"] = 0.0
	sd["wanderSpeed"] = 0.0
	sd["millSpeed"] = 0.0
	sd["state"] = SimShambler.ShamblerState["Pursue"]
	var contacts: Array = []
	w.events.subscribe({"id": "gate.space-claw", "type": "attack.connected", "handler": func(e: Dictionary) -> void:
		if int(e.get("attacker", -1)) == zed:
			contacts.append("swipe")
	})
	w.events.subscribe({"id": "gate.space-grab", "type": "grab.started", "handler": func(e: Dictionary) -> void:
		if int(e.get("source", -1)) == zed:
			contacts.append("grab")
	})
	for i in 120:
		w.step()
	return {"world": w, "contacts": contacts, "pursuing": int(sd["state"]) == SimShambler.ShamblerState["Pursue"]}


func _reads_contact() -> bool:
	var lane: String = "READS _clear_contact"
	var ok: bool = true
	var crouched: Dictionary = _contact(7300, SimStances.Stance.Crouch, SimTileMap.Tile.Low)
	if not _low_is_open_to_solidity(lane, crouched["world"], COLUMN_X, 16):
		return false
	if not bool(crouched["pursuing"]):
		ok = _fail(lane, "the crouched negative's shambler stopped pursuing, so 'no contact' would be measuring the state machine")
	if not (crouched["contacts"] as Array).is_empty():
		ok = _fail(lane, "a shambler reached a crouched survivor across a Low tile's corner: %s" % str(crouched["contacts"]))
	var standing: Dictionary = _contact(7300, SimStances.Stance.Walk, SimTileMap.Tile.Low)
	if (standing["contacts"] as Array).is_empty():
		ok = _fail(lane, "a shambler never reached a standing survivor across the Low tile's corner")
	var open: Dictionary = _contact(7300, SimStances.Stance.Crouch, T)
	if (open["contacts"] as Array).is_empty():
		ok = _fail(lane, "a shambler never reached a crouched survivor with the Low tile gone, so the crouched refusal proves nothing")
	if ok:
		print("  READS _clear_contact (live swipe and grab) refuses a crouched survivor across a Low corner, reaches a standing one (%s) and a crouched one in the open (%s)" % [str(standing["contacts"]), str(open["contacts"])])
	return ok


func _reads_can_strike() -> bool:
	var lane: String = "READS can_strike"
	var ok: bool = true
	var rows: Array = [
		["crouched behind a Low tile", SimTileMap.Tile.Low, SimStances.Stance.Crouch, false],
		["standing behind a Low tile", SimTileMap.Tile.Low, SimStances.Stance.Walk, true],
		["crouched on open ground", T, SimStances.Stance.Crouch, true],
		["standing with a wall between", SimTileMap.Tile.Wall, SimStances.Stance.Walk, false],
		["standing through an open window", SimTileMap.Tile.Window, SimStances.Stance.Walk, true],
	]
	for r in rows:
		var row: Array = r as Array
		var w: Variant = _column_world(7400, SimStances.Stance.Walk, int(row[1]))
		if int(row[1]) == SimTileMap.Tile.Low and not _low_is_open_to_solidity(lane, w, COLUMN_X, 16):
			return false
		var npc: int = int(w.entities.spawn())
		w.components.set_component(npc, "position", {"x": SWING_FROM_X, "y": ROW_Y})
		w.components.set_component(npc, "facing", {"radians": 0.0})
		w.components.set_component(npc, "posture", SimStances.make_posture(int(row[2])))
		SimHealth.make_survivor_body(w, npc)
		SimMelee.make_melee_armed(w, npc)
		var zed: int = _zombie(w, SWING_TO_X, ROW_Y)
		var got: bool = SimNpcCombat.can_strike(w, npc, zed)
		if got != bool(row[3]):
			ok = _fail(lane, "%s: can_strike said %s, wants %s" % [String(row[0]), str(got), str(bool(row[3]))])
	if ok:
		print("  READS can_strike refuses a crouched blow over a Low tile and through a wall, and allows it standing, through a window and in the open")
	return ok
