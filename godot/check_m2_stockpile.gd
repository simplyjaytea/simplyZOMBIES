extends SceneTree
# The stockpile as tiles -- docs/12's "Stockpiles are physical and lootable", slice S1 of the
# 2026-10-24 stockpile plan. Until this slice the stockpile was one test with no record behind it
# (indoors, a floor, inside the annex). Now it is a zone the player can mark, with the annex floor as
# its default, and every reader asks the zone.
#
# What the gate holds the sim to, and why each lane exists:
#
#   DEFAULT -- on a booted colony the zone is exactly the annex's indoor floor, and no record exists
#              until somebody changes it. The negative: an open outdoor floor outside the annex is
#              not a stockpile tile. The drop point is the first annex tile with no bed or campfire.
#   MARK    -- `stockpile.mark` reaches the zone through the input phase: a marked 3x3 outdoors
#              becomes nine stockpile tiles, an `off` takes one back out, and the mark publishes
#              `stockpile.changed` (a subscriber here, so the event has a reader). The negatives:
#              a wall, deep water, a door and an unexplored tile are each refused, and a rectangle
#              past MAX_TILES changes nothing.
#   WALLED  -- a marked tile that is walled over stops reading as a stockpile tile, and reads again
#              once it is open. Both directions.
#   READERS -- with the annex unmarked and a 2x2 marked outside it, the readers follow the zone:
#              `is_stockpile_tile`, `stockpile_items`, the drop point and the orders' haul test. The
#              bed test does not: `_free_indoor` still answers an annex floor tile. The raider looter
#              (`raiders.gd`'s `_is_stores`) is not in this lane; it also asks `SimHome.rect`, which
#              is the annex, so an outdoor pile is not one it loots (stated in the PR, not hidden).
#   SAVE    -- the zone round-trips a save. A save with no zone record (every save from before this
#              slice) loads with the default zone.
#   PREVIEW -- slice S2's read model: `SimStockpile.preview` is what the screen's drag draws, so it
#              has to be what `mark` does. On a fresh world it creates no record (it only asks);
#              `markable_in` answers `markable` tile for tile, an unexplored tile included; an `on`
#              previews exactly the tiles the mark then adds, an `off` exactly the ones it takes
#              back, and a rectangle that would take the zone past MAX_TILES previews refused and
#              its mark changes nothing, where a small one beside it is not refused.
#
# Every lane carries its true negative. The sabotage that proves the lanes are not vacuous: making
# `has_tile` ignore the record turns MARK and READERS red; making `markable` accept a wall turns
# MARK's wall negative red.

const SimBoot = preload("res://sim/boot.gd")
const SimStockpile = preload("res://sim/modules/stockpile.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimOrders = preload("res://sim/modules/orders.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimSurface = preload("res://sim/map/surface.gd")
const SimSave = preload("res://sim/save.gd")
const SimSightings = preload("res://sim/modules/sightings.gd")

const SEED: int = 20260805
const MAP: int = 64
const COMPONENT: String = "stockpile"

var _skipped: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _the_default_zone_is_the_annex_floor() and ok
	ok = _mark_reaches_the_zone_and_refuses_the_bad_tiles() and ok
	ok = _a_walled_tile_leaves_the_zone_and_returns() and ok
	ok = _the_readers_follow_the_zone_but_beds_do_not() and ok
	ok = _the_zone_survives_a_save_and_an_old_save_reads_the_default() and ok
	ok = _the_preview_is_what_the_mark_does() and ok
	var skip_note: String = ""
	if not _skipped.is_empty():
		skip_note = " SKIPPED(no data): " + ", ".join(_skipped)
	if ok:
		print("M2_STOCKPILE_OK default mark walled readers save preview%s" % skip_note)
		quit(0)
	else:
		push_error("M2_STOCKPILE_FAIL")
		quit(1)


# A booted district, a few ticks in, with the player having seen the whole map. The bitset is LSB
# first, bit `ty * w + tx`, and every bit set is the same as having walked everywhere; a lane that
# needs an unexplored tile clears one bit itself.
func _world() -> Variant:
	var w: Variant = SimBoot.playable(SEED, MAP)["world"]
	_explore_all(w)
	for _i in 3:
		w.step()
	return w


func _explore_all(w: Variant) -> void:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(int((w.tilemap.w * w.tilemap.h + 7) / 8))
	bytes.fill(255)
	w.components.set_component(w.player, "explored", {"w": int(w.tilemap.w), "h": int(w.tilemap.h), "bits": Marshalls.raw_to_base64(bytes)})


func _forget(w: Variant, tx: int, ty: int) -> void:
	var explored: Dictionary = (w.components.get_component(w.player, "explored") as Dictionary).duplicate()
	var bytes: PackedByteArray = Marshalls.base64_to_raw(String(explored["bits"]))
	var bit: int = ty * int(w.tilemap.w) + tx
	bytes[bit / 8] = bytes[bit / 8] & ~(1 << (bit % 8))
	explored["bits"] = Marshalls.raw_to_base64(bytes)
	w.components.set_component(w.player, "explored", explored)


func _annex(w: Variant) -> Rect2i:
	return SimTileMap.annex_rect(w.tilemap)


# The annex's indoor floor, row-major, the way the default zone is meant to read.
func _annex_floor(w: Variant) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var annex: Rect2i = _annex(w)
	for j in range(annex.position.y, annex.position.y + annex.size.y):
		for i in range(annex.position.x, annex.position.x + annex.size.x):
			if SimNeeds.is_annex_floor(w, i, j):
				out.append(Vector2i(i, j))
	return out


func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true


func _mark(w: Variant, x0: int, y0: int, x1: int, y1: int, on: bool) -> void:
	w.commands.push({"type": SimStockpile.COMMAND, "x0": x0, "y0": y0, "x1": x1, "y1": y1, "on": on})
	w.step()


# The top-left corner of the first `size` square of markable ground outside the annex, or (-1, -1).
func _markable_block(w: Variant, size: int) -> Vector2i:
	var annex: Rect2i = _annex(w)
	for ty in range(0, int(w.tilemap.h) - size):
		for tx in range(0, int(w.tilemap.w) - size):
			var ok: bool = true
			for j in size:
				for i in size:
					var x: int = tx + i
					var y: int = ty + j
					if annex.has_point(Vector2i(x, y)) or not SimStockpile.markable(w, x, y):
						ok = false
			if ok:
				return Vector2i(tx, ty)
	return Vector2i(-1, -1)


# The first tile the predicate accepts, or (-1, -1). Scans the whole map, so a lane that needs a
# kind of tile the map does not have says so instead of passing.
func _find(w: Variant, pred: Callable) -> Vector2i:
	for ty in range(0, int(w.tilemap.h)):
		for tx in range(0, int(w.tilemap.w)):
			if pred.call(tx, ty):
				return Vector2i(tx, ty)
	return Vector2i(-1, -1)


func _is_outdoor_floor_outside_annex(w: Variant, tx: int, ty: int) -> bool:
	return SimTileMap.tile_at(w.tilemap, tx, ty) == SimTileMap.Tile.Floor \
		and not SimTileMap.is_solid(w.tilemap, tx, ty) \
		and not SimTileMap.is_indoors(w.tilemap, tx, ty) \
		and not _annex(w).has_point(Vector2i(tx, ty))


# DEFAULT. Nothing is recorded until somebody changes the zone, and the zone is the annex floor.
func _the_default_zone_is_the_annex_floor() -> bool:
	var w: Variant = _world()
	if w.components.get_component(w.player, COMPONENT) != null:
		push_error("DEFAULT: a booted colony carries a stockpile record before anybody marked anything")
		return false
	var expected: Array[Vector2i] = _annex_floor(w)
	if expected.is_empty():
		push_error("DEFAULT: the playable annex has no indoor floor, so there is nothing to judge")
		return false
	if not _same(SimStockpile.tiles(w), expected):
		push_error("DEFAULT: the zone is not the annex's indoor floor (zone %d tiles, annex %d)" % [SimStockpile.count(w), expected.size()])
		return false
	var outside: Vector2i = _find(w, func(tx: int, ty: int) -> bool: return _is_outdoor_floor_outside_annex(w, tx, ty))
	if outside.x < 0:
		push_error("DEFAULT: the map has no open outdoor floor outside the annex to judge the negative with")
		return false
	if SimNeeds.is_stockpile_tile(w, outside.x, outside.y):
		push_error("DEFAULT: an open outdoor floor tile outside the annex reads as stockpile")
		return false
	var drop: Vector2i = SimJobs._stock_drop(w)
	var first_free: Vector2i = Vector2i(-1, -1)
	for t in expected:
		if SimJobs._bed_at(w, t.x, t.y) < 0 and SimJobs._campfire_at(w, t.x, t.y) < 0:
			first_free = t
			break
	if drop != first_free:
		push_error("DEFAULT: the drop point %s is not the first free annex tile %s" % [str(drop), str(first_free)])
		return false
	print("DEFAULT OK the zone is the annex floor (%d tiles), no record until a change, drop at %s" % [expected.size(), str(drop)])
	return true


# MARK. The command goes through the input phase; the event has a reader here.
func _mark_reaches_the_zone_and_refuses_the_bad_tiles() -> bool:
	var w: Variant = _world()
	var heard: Array[Dictionary] = []
	w.events.subscribe({"id": "gate.stockpile-changed", "type": "stockpile.changed", "handler": func(event: Dictionary) -> void:
		heard.append(event)
	})
	var block: Vector2i = _markable_block(w, 3)
	if block.x < 0:
		push_error("MARK: no explored 3x3 of open ground outside the annex on this map")
		return false
	var before: int = SimStockpile.count(w)
	_mark(w, block.x, block.y, block.x + 2, block.y + 2, true)
	if SimStockpile.count(w) != before + 9:
		push_error("MARK: a marked 3x3 added %d tiles, not 9" % (SimStockpile.count(w) - before))
		return false
	for j in 3:
		for i in 3:
			if not SimStockpile.has_tile(w, block.x + i, block.y + j):
				push_error("MARK: the marked 3x3 does not read as stockpile at (%d, %d)" % [block.x + i, block.y + j])
				return false
	var center: Vector2i = block + Vector2i(1, 1)
	_mark(w, center.x, center.y, center.x, center.y, false)
	if SimStockpile.has_tile(w, center.x, center.y) or not SimStockpile.has_tile(w, block.x, block.y):
		push_error("MARK: an off on the centre did not take only the centre back out")
		return false
	# Negatives: each kind of tile the rules refuse, found on the map or named as missing.
	var wall: Vector2i = _find(w, func(tx: int, ty: int) -> bool: return SimTileMap.tile_at(w.tilemap, tx, ty) == SimTileMap.Tile.Wall and _seen(w, tx, ty))
	if wall.x < 0:
		_skipped.append("MARK wall")
	else:
		_mark(w, wall.x, wall.y, wall.x, wall.y, true)
		if SimStockpile.markable(w, wall.x, wall.y) or SimStockpile.has_tile(w, wall.x, wall.y):
			push_error("MARK: a wall was marked")
			return false
	var water: Vector2i = _find(w, func(tx: int, ty: int) -> bool: return SimSurface.surface_at(w.tilemap, tx, ty) == SimSurface.Surface.Water and SimTileMap.tile_at(w.tilemap, tx, ty) == SimTileMap.Tile.Floor and _seen(w, tx, ty))
	if water.x < 0:
		_skipped.append("MARK ford")
	else:
		_mark(w, water.x, water.y, water.x, water.y, true)
		if SimStockpile.has_tile(w, water.x, water.y):
			push_error("MARK: a ford tile was marked")
			return false
	var door: Vector2i = _find(w, func(tx: int, ty: int) -> bool: return _is_door(w, tx, ty) and _seen(w, tx, ty))
	if door.x < 0:
		_skipped.append("MARK door")
	else:
		_mark(w, door.x, door.y, door.x, door.y, true)
		if SimStockpile.markable(w, door.x, door.y) or SimStockpile.has_tile(w, door.x, door.y):
			push_error("MARK: a door was marked")
			return false
	var unseen: Vector2i = _find(w, func(tx: int, ty: int) -> bool: return _is_outdoor_floor_outside_annex(w, tx, ty) and not SimStockpile.has_tile(w, tx, ty))
	if unseen.x < 0:
		_skipped.append("MARK unexplored")
	else:
		_forget(w, unseen.x, unseen.y)
		if SimSightings.knows_tile(w, w.player, unseen.x, unseen.y):
			push_error("MARK: the unexplored negative could not be made unexplored")
			return false
		_mark(w, unseen.x, unseen.y, unseen.x, unseen.y, true)
		if SimStockpile.has_tile(w, unseen.x, unseen.y):
			push_error("MARK: a tile the player has never seen was marked")
			return false
	# A rectangle of 441 tiles is past MAX_TILES and is refused whole: nothing changes.
	var size_before: int = SimStockpile.count(w)
	_mark(w, block.x, block.y, block.x + 20, block.y + 20, true)
	if SimStockpile.count(w) != size_before:
		push_error("MARK: a rectangle past MAX_TILES changed the zone")
		return false
	if heard.size() != 2:
		push_error("MARK: stockpile.changed fired %d times for two accepted marks" % heard.size())
		return false
	print("MARK OK 3x3 in and out, %d tiles, refusals held, changed fired twice" % SimStockpile.count(w))
	return true


func _seen(w: Variant, tx: int, ty: int) -> bool:
	return SimSightings.knows_tile(w, w.player, tx, ty)


func _is_door(w: Variant, tx: int, ty: int) -> bool:
	if SimTileMap.tile_at(w.tilemap, tx, ty) == SimTileMap.Tile.Door:
		return true
	var ov: Variant = SimTileMap.overlay_at(w.tilemap, tx, ty)
	return ov is Dictionary and String((ov as Dictionary).get("kind", "")) == "door"


# WALLED. A marked tile walled over leaves the zone; opened again, it returns.
func _a_walled_tile_leaves_the_zone_and_returns() -> bool:
	var w: Variant = _world()
	var block: Vector2i = _markable_block(w, 2)
	if block.x < 0:
		push_error("WALLED: no explored 2x2 of open ground outside the annex on this map")
		return false
	_mark(w, block.x, block.y, block.x + 1, block.y + 1, true)
	var idx: int = block.y * int(w.tilemap.w) + block.x
	var floor_tile: int = int(w.tilemap.tiles[idx])
	if not SimStockpile.has_tile(w, block.x, block.y):
		push_error("WALLED: the marked tile is not stockpile before anything walls it")
		return false
	w.tilemap.tiles[idx] = SimTileMap.Tile.Wall
	if SimStockpile.has_tile(w, block.x, block.y):
		push_error("WALLED: a walled-over stockpile tile still reads as stockpile")
		return false
	w.tilemap.tiles[idx] = floor_tile
	if not SimStockpile.has_tile(w, block.x, block.y):
		push_error("WALLED: the tile did not come back into the zone once it was open again")
		return false
	print("WALLED OK a walled stockpile tile leaves the zone and returns when open")
	return true


# READERS. The zone is the only thing these readers ask, with the annex unmarked.
func _the_readers_follow_the_zone_but_beds_do_not() -> bool:
	var w: Variant = _world()
	var annex: Rect2i = _annex(w)
	_mark(w, annex.position.x, annex.position.y, annex.position.x + annex.size.x - 1, annex.position.y + annex.size.y - 1, false)
	if not SimStockpile.tiles(w).is_empty() and not _same(SimStockpile.tiles(w).filter(func(t: Vector2i) -> bool: return annex.has_point(t)), []):
		push_error("READERS: an off over the whole annex left annex tiles in the zone")
		return false
	var block: Vector2i = _markable_block(w, 2)
	if block.x < 0:
		push_error("READERS: no explored 2x2 of open ground outside the annex on this map")
		return false
	_mark(w, block.x, block.y, block.x + 1, block.y + 1, true)
	var annex_tile: Vector2i = _annex_floor(w)[0] if not _annex_floor(w).is_empty() else Vector2i(-1, -1)
	if annex_tile.x < 0:
		push_error("READERS: the annex has no indoor floor to judge the negative with")
		return false
	if SimNeeds.is_stockpile_tile(w, annex_tile.x, annex_tile.y):
		push_error("READERS: the unmarked annex floor still reads as stockpile")
		return false
	if not SimNeeds.is_stockpile_tile(w, block.x, block.y):
		push_error("READERS: the marked 2x2 does not read as stockpile")
		return false
	var drop: Vector2i = SimJobs._stock_drop(w)
	if not (drop.x >= block.x and drop.x <= block.x + 1 and drop.y >= block.y and drop.y <= block.y + 1):
		push_error("READERS: the drop point %s is not on the marked 2x2 at %s" % [str(drop), str(block)])
		return false
	var on_block: int = SimItems.spawn_item(w, "item.food.canned", {"tier": "scavenged"})
	w.components.set_component(on_block, "position", {"x": float(block.x) + 0.5, "y": float(block.y) + 0.5})
	var on_annex: int = SimItems.spawn_item(w, "item.food.canned", {"tier": "scavenged"})
	w.components.set_component(on_annex, "position", {"x": float(annex_tile.x) + 0.5, "y": float(annex_tile.y) + 0.5})
	var stocked: Array[int] = SimNeeds.stockpile_items(w)
	if not stocked.has(on_block) or stocked.has(on_annex):
		push_error("READERS: stockpile_items does not list the 2x2 pile and not the unmarked annex floor")
		return false
	if SimOrders._haulable(w, w.player, on_block) or not SimOrders._haulable(w, w.player, on_annex):
		push_error("READERS: an order's haul test ignores the zone")
		return false
	var bed_tile: Vector2i = SimJobs._free_indoor(w)
	if bed_tile.x < 0 or not SimNeeds.is_annex_floor(w, bed_tile.x, bed_tile.y):
		push_error("READERS: a bed no longer goes on the annex floor once the zone moved")
		return false
	print("READERS OK the 2x2 is the stockpile, the annex is not, the drop and the orders follow, a bed stays on the annex")
	return true


# SAVE. A marked zone survives a save; a save with no record loads as the default.
func _the_zone_survives_a_save_and_an_old_save_reads_the_default() -> bool:
	var w: Variant = _world()
	var block: Vector2i = _markable_block(w, 2)
	if block.x < 0:
		push_error("SAVE: no explored 2x2 of open ground outside the annex on this map")
		return false
	_mark(w, block.x, block.y, block.x + 1, block.y + 1, true)
	var expected_count: int = SimStockpile.count(w)
	var back: Variant = _restored(w)
	if not SimStockpile.has_tile(back, block.x, block.y) or SimStockpile.count(back) != expected_count:
		push_error("SAVE: the marked zone did not come back out of a save (%d tiles, expected %d)" % [SimStockpile.count(back), expected_count])
		return false
	# An old save: the same world with the record taken out, which is what a save from before this
	# slice holds. It must read as the annex floor, with no error.
	w.components.remove_component(w.player, COMPONENT)
	var old: Variant = _restored(w)
	if not _same(SimStockpile.tiles(old), _annex_floor(old)):
		push_error("SAVE: a save with no zone record did not load as the default zone")
		return false
	print("SAVE OK the marked zone round-trips, and a save with no record reads the annex floor")
	return true


# A fresh world restored from `w`'s save, through the same encode and decode a real save takes.
func _restored(w: Variant) -> Variant:
	var text: String = SimSave.encode_save(SimSave.create_save(w))
	var decoded: Dictionary = SimSave.decode_save_or_throw(text)
	var back: Variant = _world()
	back.restore(decoded["snapshot"] as Dictionary)
	return back


func _the_preview_is_what_the_mark_does() -> bool:
	var w: Variant = _world()
	var at: Vector2i = _markable_block(w, 3)
	if at.x < 0:
		_skipped.append("PREVIEW")
		print("PREVIEW SKIP no 3x3 of markable ground outside the annex")
		return true
	var hole := Vector2i(at.x + 1, at.y + 1)
	_forget(w, hole.x, hole.y)
	var on_cmd: Dictionary = {"type": SimStockpile.COMMAND, "x0": at.x, "y0": at.y, "x1": at.x + 2, "y1": at.y + 2, "on": true}
	var before: Array[Vector2i] = SimStockpile.tiles(w)
	var pv: Dictionary = SimStockpile.preview(w, on_cmd)
	if w.components.has_component(w.player, COMPONENT):
		push_error("PREVIEW: asking what a mark would do wrote a zone record")
		return false
	var explored: Variant = SimSightings.explored_view(w, w.player)
	for j in range(at.y, at.y + 3):
		for i in range(at.x, at.x + 3):
			if SimStockpile.markable_in(w, explored, i, j) != SimStockpile.markable(w, i, j):
				push_error("PREVIEW: markable_in and markable disagree at (%d, %d)" % [i, j])
				return false
	if SimStockpile.markable(w, hole.x, hole.y):
		push_error("PREVIEW: the forgotten tile is still markable, so the agreement above proves nothing")
		return false
	var want: Array[Vector2i] = []
	for j in range(at.y, at.y + 3):
		for i in range(at.x, at.x + 3):
			if Vector2i(i, j) != hole:
				want.append(Vector2i(i, j))
	if bool(pv["refused"]) or not _same(pv["tiles"] as Array, want):
		push_error("PREVIEW: an on over the 3x3 previews %s (refused %s), not its eight explored tiles" % [str(pv["tiles"]), str(pv["refused"])])
		return false
	# The signature main.gd keeps the zone by: still while nothing changes, moved by a mark.
	var sig0: int = SimStockpile.signature(w)
	if SimStockpile.signature(w) != sig0:
		push_error("PREVIEW: the zone's signature moved with nothing changed")
		return false
	_mark(w, at.x, at.y, at.x + 2, at.y + 2, true)
	var after: Array[Vector2i] = SimStockpile.tiles(w)
	if SimStockpile.signature(w) == sig0:
		push_error("PREVIEW: a mark that added %d tiles left the zone's signature where it was, so a reader keeping the zone by it never sees the change" % after.size())
		return false
	var gained: Array[Vector2i] = after.filter(func(t: Vector2i) -> bool: return not before.has(t))
	if not _same(gained, want):
		push_error("PREVIEW: the mark added %s where the preview said %s" % [str(gained), str(want)])
		return false
	var off_cmd: Dictionary = on_cmd.duplicate()
	off_cmd["on"] = false
	var pv_off: Dictionary = SimStockpile.preview(w, off_cmd)
	_mark(w, at.x, at.y, at.x + 2, at.y + 2, false)
	var lost: Array[Vector2i] = after.filter(func(t: Vector2i) -> bool: return not SimStockpile.tiles(w).has(t))
	if bool(pv_off["refused"]) or not _same(pv_off["tiles"] as Array, lost) or lost.size() != want.size():
		push_error("PREVIEW: an off previews %s and the mark took back %s" % [str(pv_off["tiles"]), str(lost)])
		return false
	# Past the cap: the default zone plus a big outdoor rectangle. Refused whole, and so is the mark.
	var big: Dictionary = {}
	for ty in range(0, int(w.tilemap.h) - 20, 4):
		for tx in range(0, int(w.tilemap.w) - 20, 4):
			var c: Dictionary = {"type": SimStockpile.COMMAND, "x0": tx, "y0": ty, "x1": tx + 19, "y1": ty + 19, "on": true}
			if bool(SimStockpile.preview(w, c)["refused"]):
				big = c
				break
		if not big.is_empty():
			break
	if big.is_empty():
		_skipped.append("PREVIEW cap")
		print("PREVIEW SKIP no rectangle on this map has enough markable ground to pass MAX_TILES")
		return true
	if not (SimStockpile.preview(w, big)["tiles"] as Array).is_empty():
		push_error("PREVIEW: a refused preview still lists tiles")
		return false
	var held: Array[Vector2i] = SimStockpile.tiles(w)
	var sig_held: int = SimStockpile.signature(w)
	_mark(w, int(big["x0"]), int(big["y0"]), int(big["x1"]), int(big["y1"]), true)
	if not _same(SimStockpile.tiles(w), held):
		push_error("PREVIEW: the mark the preview refused changed the zone")
		return false
	if SimStockpile.signature(w) != sig_held:
		push_error("PREVIEW: a refused mark moved the zone's signature")
		return false
	var small: Dictionary = on_cmd.duplicate()
	small["x1"] = at.x
	small["y1"] = at.y
	if bool(SimStockpile.preview(w, small)["refused"]):
		push_error("PREVIEW: a one-tile mark is refused too, so the cap's refusal proves nothing")
		return false
	print("PREVIEW OK asking writes no record, markable_in is markable, an on and an off preview exactly what the mark changes, the signature moves with a mark and holds otherwise, and a rectangle past the cap previews refused and changes nothing")
	return true
