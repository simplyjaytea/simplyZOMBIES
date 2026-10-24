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
#              not a stockpile tile. The drop point is a free annex tile, and the emptiest one.
#   MARK    -- `stockpile.mark` reaches the zone through the input phase: a marked 3x3 outdoors
#              becomes nine stockpile tiles, an `off` takes one back out, and the mark publishes
#              `stockpile.changed` (a subscriber here, so the event has a reader). The negatives:
#              a wall, deep water, a door and an unexplored tile are each refused, and a rectangle
#              past MAX_TILES changes nothing.
#   WALLED  -- a marked tile that is walled over stops reading as a stockpile tile, and reads again
#              once it is open. Both directions.
#   READERS -- with the annex unmarked and a 2x2 marked outside it, the readers follow the zone:
#              `is_stockpile_tile`, `stockpile_items`, the drop point and the orders' haul test. The
#              bed test does not: `_free_indoor` still answers an annex floor tile.
#   SPREAD  -- six items dropped one after another from one spot land on six tiles of a 3x3 pile,
#              the emptiest each time. Sabotage: the first free tile stacks them, and this turns red.
#   PATCH   -- a pile marked well clear of the annex is its own patch. From beside it the drop is on
#              the pile; from home it is at home. Stands in for a camp's stash: the drop reads
#              positions, not camps.
#   WALK    -- a colonist's Haul picks an item up beside an outdoor pile and stocks it on that pile,
#              by the ordinary Haul job.
#   COOK    -- a meal lands on the stockpile tile nearest the fire it was cooked at, not the cook's
#              feet, even when the cook stands at the pile.
#   RAIDER  -- a raider's looter finds a marked outdoor pile: `_is_stores` and `_loot_goal` read the
#              zone, so an outdoor pile is looted as the annex is.
#   TAKE    -- the stockpile window's commands, by the sim's own rules (slice S4). Standing in a
#              patch with the window open, a tin in view is taken into the pockets; a tin on the
#              same patch behind a wall, a tin off the zone, and any take with the window shut are
#              refused, and each stays where it lay. A carried tin is put back onto a tile of the
#              patch in view; off the zone the window shuts and a put is refused. E opens the window
#              where the item it would pick up lies on the pile, and the bar's words say so; off the
#              pile E still picks the item up. Sabotage: dropping the sight test from `in_sight`
#              lists the walled tin and turns TAKE red.
#   SAVE    -- the zone round-trips a save. A save with no zone record (every save from before this
#              slice) loads with the default zone.
#
# Every lane carries its true negative. The sabotage that proves the lanes are not vacuous: making
# `has_tile` ignore the record turns MARK and READERS red; making `markable` accept a wall turns
# MARK's wall negative red; putting the first free tile back into `drop_tile` turns SPREAD red.

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
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimRaiders = preload("res://sim/modules/raiders.gd")
const SimContext = preload("res://sim/context.gd")

const SEED: int = 20260805
const MAP: int = 64
const COMPONENT: String = "stockpile"
const RAW_FOOD: String = "item.food.raw"
const CANNED: String = "item.food.canned"
# A carried item walks at most this many ticks before the lane calls it stuck.
const HAUL_TICKS: int = 400

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
	ok = _six_items_spread_over_the_pile_emptiest_first() and ok
	ok = _a_pile_apart_from_home_is_its_own_patch() and ok
	ok = _a_haul_walks_onto_an_outdoor_pile() and ok
	ok = _a_meal_lands_at_the_fire_not_at_the_cooks_feet() and ok
	ok = _a_raider_loots_an_outdoor_pile() and ok
	ok = _the_window_takes_and_puts_by_the_sims_rules() and ok
	var skip_note: String = ""
	if not _skipped.is_empty():
		skip_note = " SKIPPED(no data): " + ", ".join(_skipped)
	if ok:
		print("M2_STOCKPILE_OK default mark walled readers save spread patch walk cook raider take%s" % skip_note)
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
# With `gap`, the square also keeps `gap` tiles clear of the annex, so it is its own patch.
func _markable_block(w: Variant, size: int, gap: int = 0) -> Vector2i:
	var annex: Rect2i = _annex(w).grow(gap)
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
	var drop: Vector2i = SimJobs._stock_drop(w, _centre(expected[0]))
	if not expected.has(drop) or not _free(w, drop):
		push_error("DEFAULT: the drop point %s is not a free annex tile" % str(drop))
		return false
	for t in expected:
		if _free(w, t) and _load(w, t) < _load(w, drop):
			push_error("DEFAULT: the drop point %s holds %d items, but free annex tile %s holds %d" % [str(drop), _load(w, drop), str(t), _load(w, t)])
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
	var drop: Vector2i = SimJobs._stock_drop(w, _centre(block))
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


func _centre(t: Vector2i) -> Vector2:
	return Vector2(float(t.x) + 0.5, float(t.y) + 0.5)


# A free zone tile's bed and campfire test, as `_stock_drop` applies it.
func _free(w: Variant, t: Vector2i) -> bool:
	return SimJobs._bed_at(w, t.x, t.y) < 0 and SimJobs._campfire_at(w, t.x, t.y) < 0


# How many loose items lie on a tile.
func _load(w: Variant, t: Vector2i) -> int:
	var n: int = 0
	for item in SimInventory.ground_items(w):
		var p: Variant = w.components.get_component(item, "position")
		if p is Dictionary and floori(float((p as Dictionary)["x"])) == t.x and floori(float((p as Dictionary)["y"])) == t.y:
			n += 1
	return n


func _colonist(w: Variant) -> int:
	for ent in w.components.query(["identity"]):
		var ident: Variant = w.components.get_component(int(ent), "identity")
		if ident is Dictionary and String((ident as Dictionary).get("id", "")) == "survivor.unique.mara":
			return int(ent)
	return -1


# A spot on the pile, the item dropped there, and the tile it landed on.
func _put_on(w: Variant, t: Vector2i, id: String) -> int:
	var item: int = SimItems.spawn_item(w, id, {"tier": "scavenged"})
	w.components.set_component(item, "position", {"x": float(t.x) + 0.5, "y": float(t.y) + 0.5})
	return item


# SPREAD. Six items dropped one after another from one spot land on six tiles of a 3x3 pile outside
# the annex, the emptiest tile each time. The old answer, the first free tile, stacks all six.
func _six_items_spread_over_the_pile_emptiest_first() -> bool:
	var w: Variant = _world()
	var block: Vector2i = _markable_block(w, 3, 6)
	if block.x < 0:
		push_error("SPREAD: no explored 3x3 of open ground clear of the annex on this map")
		return false
	_mark(w, block.x, block.y, block.x + 2, block.y + 2, true)
	var from: Vector2 = _centre(Vector2i(block.x + 1, block.y + 1))
	var landed: Array[Vector2i] = []
	for _i in 6:
		var drop: Vector2i = SimJobs._stock_drop(w, from)
		if drop.x < block.x or drop.x > block.x + 2 or drop.y < block.y or drop.y > block.y + 2:
			push_error("SPREAD: the drop %s is off the pile at %s" % [str(drop), str(block)])
			return false
		if landed.has(drop):
			push_error("SPREAD: a second item stacked on %s after %d had landed" % [str(drop), landed.size()])
			return false
		landed.append(drop)
		_put_on(w, drop, CANNED)
	print("SPREAD OK six items landed on six tiles of the 3x3 pile at %s" % str(block))
	return true


# PATCH. A pile marked clear of the annex is its own patch. From beside it a drop goes on the pile,
# and from home a drop goes at home. A camp's stash is this rule with a camp by the pile; the drop
# reads positions, not camps, so the lane needs no camp to stand.
func _a_pile_apart_from_home_is_its_own_patch() -> bool:
	var w: Variant = _world()
	var block: Vector2i = _markable_block(w, 2, 6)
	if block.x < 0:
		push_error("PATCH: no explored 2x2 of open ground clear of the annex on this map")
		return false
	_mark(w, block.x, block.y, block.x + 1, block.y + 1, true)
	var pile_tiles: Array = []
	for patch in SimStockpile.patches(w):
		if (patch as Array).has(block):
			pile_tiles = patch as Array
	if pile_tiles.size() != 4:
		push_error("PATCH: the 2x2 is not a patch of its own (%d tiles)" % pile_tiles.size())
		return false
	var home: Array[Vector2i] = _annex_floor(w)
	if home.is_empty():
		push_error("PATCH: the annex has no indoor floor to judge home with")
		return false
	var from_camp: Vector2i = SimJobs._stock_drop(w, _centre(block))
	var from_home: Vector2i = SimJobs._stock_drop(w, _centre(home[0]))
	if not (pile_tiles.has(from_camp)):
		push_error("PATCH: an item dropped beside the pile went to %s, not onto it" % str(from_camp))
		return false
	if not SimNeeds.is_annex_floor(w, from_home.x, from_home.y):
		push_error("PATCH: an item dropped at home went to %s, not into the annex" % str(from_home))
		return false
	print("PATCH OK the pile is its own patch: beside it the drop is %s, at home %s" % [str(from_camp), str(from_home)])
	return true


# WALK. A colonist's Haul picks an item up beside an outdoor pile and carries it onto the pile by the
# ordinary Haul job. The job is set the way the orders gate sets one, and the world is stepped until
# it ends. Sabotage: a drop that is not on the pile leaves the item off it, and this turns red.
func _a_haul_walks_onto_an_outdoor_pile() -> bool:
	var w: Variant = _world()
	var mara: int = _colonist(w)
	var block: Vector2i = _markable_block(w, 2, 6)
	if mara < 0:
		push_error("WALK: the booted colony has no Mara to carry anything")
		return false
	if block.x < 0:
		push_error("WALK: no explored 2x2 of open ground clear of the annex on this map")
		return false
	_mark(w, block.x, block.y, block.x + 1, block.y + 1, true)
	var beside := Vector2i(-1, -1)
	for t in [Vector2i(block.x - 1, block.y), Vector2i(block.x + 2, block.y), Vector2i(block.x, block.y - 1), Vector2i(block.x, block.y + 2)]:
		if _is_outdoor_floor_outside_annex(w, t.x, t.y) and not SimStockpile.has_tile(w, t.x, t.y):
			beside = t
			break
	if beside.x < 0:
		push_error("WALK: no open ground beside the pile to pick the item up from")
		return false
	var item: int = _put_on(w, beside, CANNED)
	w.components.set_component(mara, "position", {"x": float(beside.x) + 0.5, "y": float(beside.y) + 0.5})
	w.components.set_component(item, "reserved", {"by": mara, "job": "Haul"})
	w.components.set_component(mara, "job", {"kind": "Haul", "target": item, "ticksLeft": 0, "path": [], "pathGen": -1})
	var ticks: int = 0
	while w.components.get_component(mara, "job") is Dictionary and ticks < HAUL_TICKS:
		w.step()
		ticks += 1
	var p: Variant = w.components.get_component(item, "position")
	var landed := Vector2i(-1, -1)
	if p is Dictionary:
		landed = Vector2i(floori(float((p as Dictionary)["x"])), floori(float((p as Dictionary)["y"])))
	var on_pile: bool = landed.x >= block.x and landed.x <= block.x + 1 and landed.y >= block.y and landed.y <= block.y + 1
	if not on_pile or not SimStockpile.has_tile(w, landed.x, landed.y):
		push_error("WALK: the item lies at %s after %d ticks, not on the pile at %s (job still set: %s)" % [str(landed), ticks, str(block), str(w.components.get_component(mara, "job") is Dictionary)])
		return false
	print("WALK OK the Haul carried an item from beside the pile onto it at %s in %d ticks" % [str(landed), ticks])
	return true


# COOK. A meal lands on the stockpile tile nearest the fire it was cooked at. The cook stands by a pile
# clear of the annex, so the cook's own feet would give a different tile, and the lane checks that it does.
func _a_meal_lands_at_the_fire_not_at_the_cooks_feet() -> bool:
	var w: Variant = _world()
	var mara: int = _colonist(w)
	var fires: Array[int] = w.components.query(["campfire"])
	var block: Vector2i = _markable_block(w, 2, 6)
	if mara < 0 or fires.is_empty() or block.x < 0:
		push_error("COOK: needs Mara, a campfire and a pile clear of the annex; the booted map did not give them all")
		return false
	_mark(w, block.x, block.y, block.x + 1, block.y + 1, true)
	var fire_at: Vector2i = _tile_of(w, fires[0])
	var home: Array[Vector2i] = _annex_floor(w)
	var raw_tile := Vector2i(-1, -1)
	for t in home:
		if _free(w, t):
			raw_tile = t
			break
	if raw_tile.x < 0:
		push_error("COOK: the annex has no free tile for the raw ingredient")
		return false
	var raw: int = _put_on(w, raw_tile, RAW_FOOD)
	var into: String = SimJobs.cooks_into(w, raw)
	var meals_before: Array[int] = _items_based_on(w, into)
	w.components.set_component(raw, "reserved", {"by": mara, "job": "Cook"})
	w.components.set_component(mara, "position", {"x": float(block.x) + 0.5, "y": float(block.y) + 0.5})
	var job: Dictionary = {"kind": "Cook", "target": raw, "fire": fires[0], "ticksLeft": 1, "path": [], "pathGen": -1}
	w.components.set_component(mara, "job", job)
	SimJobs._do_cook(w, mara, job)
	var meal := -1
	for m in _items_based_on(w, into):
		if not meals_before.has(m):
			meal = m
	if meal < 0:
		push_error("COOK: cooking the raw made no '%s' to place" % into)
		return false
	var landed: Vector2i = _tile_of(w, meal)
	# The meal's own tile would count against its drop, so take it out for the expectation.
	w.components.remove_component(meal, "position")
	var expected: Vector2i = SimJobs._stock_drop(w, _centre(fire_at))
	var from_feet: Vector2i = SimJobs._stock_drop(w, _centre(block))
	if from_feet == expected:
		push_error("COOK: the fire and the cook's feet give the same drop %s, so the lane cannot tell them apart" % str(expected))
		return false
	if landed != expected or not SimNeeds.is_stockpile_tile(w, landed.x, landed.y):
		push_error("COOK: the meal landed at %s, not the stockpile tile nearest the fire, %s" % [str(landed), str(expected)])
		return false
	print("COOK OK the meal landed at %s, nearest the fire at %s, not the cook's feet at %s" % [str(landed), str(fire_at), str(block)])
	return true


# RAIDER. A raider's looter reads the zone: an item on a marked outdoor pile is stores, an item off the
# zone is not, and a looter standing by the pile heads for it.
func _a_raider_loots_an_outdoor_pile() -> bool:
	var w: Variant = _world()
	var mara: int = _colonist(w)
	var block: Vector2i = _markable_block(w, 2, 6)
	if mara < 0 or block.x < 0:
		push_error("RAIDER: needs Mara and a pile clear of the annex on this map")
		return false
	_mark(w, block.x, block.y, block.x + 1, block.y + 1, true)
	var on_pile: int = _put_on(w, block, CANNED)
	var off := _find(w, func(tx: int, ty: int) -> bool: return _is_outdoor_floor_outside_annex(w, tx, ty) and not SimStockpile.has_tile(w, tx, ty) and Vector2i(tx, ty) != block)
	if off.x < 0:
		push_error("RAIDER: no open outdoor ground off the zone to judge the negative with")
		return false
	var off_item: int = _put_on(w, off, CANNED)
	if not SimRaiders._is_stores(w, on_pile):
		push_error("RAIDER: an item on the marked outdoor pile is not stores to a looter")
		return false
	if SimRaiders._is_stores(w, off_item):
		push_error("RAIDER: an item off the zone reads as stores")
		return false
	w.components.set_component(mara, "position", {"x": float(block.x) + 0.5, "y": float(block.y) + 0.5})
	var goal: Vector2i = SimRaiders._loot_goal(w, mara)
	if not (goal.x >= block.x and goal.x <= block.x + 1 and goal.y >= block.y and goal.y <= block.y + 1):
		push_error("RAIDER: a looter beside the pile heads for %s, not the pile at %s" % [str(goal), str(block)])
		return false
	print("RAIDER OK a looter beside the outdoor pile heads for %s and an item off the zone is not stores" % str(goal))
	return true


func _tile_of(w: Variant, item: int) -> Vector2i:
	var p: Variant = w.components.get_component(item, "position")
	if not (p is Dictionary):
		return Vector2i(-1, -1)
	return Vector2i(floori(float((p as Dictionary)["x"])), floori(float((p as Dictionary)["y"])))


func _items_based_on(w: Variant, base: String) -> Array[int]:
	var out: Array[int] = []
	for item in w.components.query(["itemBase"]):
		var b: Variant = w.components.get_component(int(item), "itemBase")
		if b is Dictionary and String((b as Dictionary).get("baseId", "")) == base:
			out.append(int(item))
	return out


# TAKE. The window's four commands, each accepted and refused by the sim's own rules. A 3x3 pile
# outdoors, the player on its west middle tile, a wall dropped on its centre: the east middle tile is
# on the same patch (round the wall by the top and bottom rows) and out of sight behind the wall.
func _the_window_takes_and_puts_by_the_sims_rules() -> bool:
	var w: Variant = _world()
	var block: Vector2i = _markable_block(w, 3, 6)
	if block.x < 0:
		push_error("TAKE: no explored 3x3 of open ground clear of the annex on this map")
		return false
	_mark(w, block.x, block.y, block.x + 2, block.y + 2, true)
	var stand := Vector2i(block.x, block.y + 1)
	var wall := Vector2i(block.x + 1, block.y + 1)
	var hidden := Vector2i(block.x + 2, block.y + 1)
	var corner := Vector2i(block.x + 1, block.y)
	var off := Vector2i(block.x - 1, block.y + 1)
	if not SimStockpile.markable(w, off.x, off.y) or SimStockpile.has_tile(w, off.x, off.y):
		push_error("TAKE: the tile west of the pile at %s is not open ground off the zone" % str(off))
		return false
	w.tilemap.tiles[wall.y * int(w.tilemap.w) + wall.x] = SimTileMap.Tile.Wall
	w.map_generation = int(w.map_generation) + 1
	_stand(w, stand)
	var here_tin: int = _put_on(w, stand, CANNED)
	var hid_tin: int = _put_on(w, hidden, CANNED)
	var near_tin: int = _put_on(w, corner, CANNED)
	var off_tin: int = _put_on(w, off, CANNED)
	w.step()
	if SimStockpile.patch_under(w, w.player).size() != 8 or not SimStockpile.patch_under(w, w.player).has("%d,%d" % [hidden.x, hidden.y]):
		push_error("TAKE: the walled pile is not one patch of eight round the wall: %s" % str(SimStockpile.patch_under(w, w.player).keys()))
		return false
	# Shut, the window takes nothing, and lists nothing.
	_send(w, {"type": SimStockpile.TAKE_COMMAND, "item": here_tin})
	if not _lies(w, here_tin) or not SimStockpile.stores_view(w, w.player).is_empty():
		push_error("TAKE: a take with the window shut moved the tin, or the shut window lists something")
		return false
	# E, standing on the pile with a tin of it in reach: the window, not the pick-up. The bar says so.
	if SimContext.reach_words(w, w.player) != SimStockpile.OPEN_WORDS:
		push_error("TAKE: the bar's E words on the pile are %s" % SimContext.reach_words(w, w.player))
		return false
	_send(w, {"type": "use.context"})
	if not SimStockpile.is_open(w, w.player) or not _lies(w, here_tin) or not _lies(w, near_tin):
		push_error("TAKE: E on the pile did not open the window, or picked a tin up instead")
		return false
	var listed: Array[int] = SimStockpile.in_sight(w, w.player)
	if not listed.has(here_tin) or not listed.has(near_tin):
		push_error("TAKE: the tins in view are not listed: %s" % str(listed))
		return false
	if listed.has(hid_tin):
		push_error("TAKE: the tin behind the wall is listed")
		return false
	if listed.has(off_tin):
		push_error("TAKE: the tin off the zone is listed")
		return false
	var view: Dictionary = SimStockpile.stores_view(w, w.player)
	if int(view.get("container", 0)) != SimStockpile.STORES or String(view.get("label", "")) != "the stockpile" or (view.get("items", []) as Array).size() != listed.size():
		push_error("TAKE: the window's view is not the listed tins under the stockpile's name: %s" % str(view))
		return false
	_send(w, {"type": SimStockpile.TAKE_COMMAND, "item": hid_tin})
	_send(w, {"type": SimStockpile.TAKE_COMMAND, "item": off_tin})
	if not _lies(w, hid_tin) or not _lies(w, off_tin):
		push_error("TAKE: a tin out of sight, or off the zone, was taken")
		return false
	_send(w, {"type": SimStockpile.TAKE_COMMAND, "item": here_tin})
	if _lies(w, here_tin) or not SimInventory.owns(w, w.player, here_tin):
		push_error("TAKE: the tin in view was not taken into the pockets")
		return false
	# Put back: onto a tile of this patch the player sees, not the hidden side.
	_send(w, {"type": SimStockpile.PUT_COMMAND, "item": here_tin})
	var back: Vector2i = _tile_of(w, here_tin)
	if not _lies(w, here_tin) or not SimStockpile.patch_under(w, w.player).has("%d,%d" % [back.x, back.y]) or not SimStockpile.in_view(w, w.player, float(back.x) + 0.5, float(back.y) + 0.5):
		push_error("TAKE: the put tin is at %s, not on a tile of the patch in view" % str(back))
		return false
	# Off the zone the window shuts, and a put is refused: the tin stays in the pockets.
	_send(w, {"type": SimStockpile.TAKE_COMMAND, "item": here_tin})
	_stand(w, off)
	w.step()
	if SimStockpile.is_open(w, w.player) or w.components.has_component(w.player, SimStockpile.OPEN_COMPONENT):
		push_error("TAKE: the window stayed open off the zone")
		return false
	_send(w, {"type": SimStockpile.PUT_COMMAND, "item": here_tin})
	if _lies(w, here_tin):
		push_error("TAKE: a put off the zone put the tin down")
		return false
	# E off the pile, with the off-zone tin at the player's feet, is still the pick-up.
	if SimContext.reach_words(w, w.player).find("pick up") != 0:
		push_error("TAKE: the bar's E words off the pile are %s" % SimContext.reach_words(w, w.player))
		return false
	_send(w, {"type": "use.context"})
	if _lies(w, off_tin) or w.components.has_component(w.player, SimStockpile.OPEN_COMPONENT):
		push_error("TAKE: E off the pile did not pick the tin up, or opened the window")
		return false
	print("TAKE OK the window takes a tin in view and puts it back in view; out of sight, off the zone, shut or off the pile it refuses; E opens it on the pile and picks up off it")
	return true


# The player's sight lands whole a tick after a move (`SimVisibility.STAGGER_PLAYER_CAST`), so a lane
# that moves the player gives it that tick before asking what is in view.
func _stand(w: Variant, t: Vector2i) -> void:
	w.components.set_component(w.player, "position", {"x": float(t.x) + 0.5, "y": float(t.y) + 0.5})
	w.step()


func _send(w: Variant, cmd: Dictionary) -> void:
	w.commands.push(cmd)
	w.step()


# Whether the item lies loose on the ground.
func _lies(w: Variant, item: int) -> bool:
	return w.components.has_component(item, "position") and not w.components.has_component(item, "stored")
