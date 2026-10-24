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
#              once it is open. Both directions. At each step the zone query (`SimStockpile.tiles`,
#              kept cheap for the Haul drop) answers exactly `has_tile` over the record, row-major.
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
#   PREVIEW -- slice S2's read model: `SimStockpile.preview` is what the screen's drag draws, so it
#              has to be what `mark` does. On a fresh world it creates no record (it only asks);
#              `markable_in` answers `markable` tile for tile, an unexplored tile included; an `on`
#              previews exactly the tiles the mark then adds, an `off` exactly the ones it takes
#              back, and a rectangle that would take the zone past MAX_TILES previews refused and
#              its mark changes nothing, where a small one beside it is not refused.
#   SUMMARY -- slice S5's read model (`godot/sim/stockpile_read.gd`), which the Colony screen draws:
#              a stack of three tins and a stack of two read food "some", the stack counted as its
#              count, named most numerous first; a bandage reads medicine "one"; every other group
#              "none". The negative: a tin outside the stockpile is not counted, so an emptied
#              pile reads food "none" with it lying there. The amount ladder is held at each edge,
#              and every group is one some content item falls in, so no group is a word nothing
#              can fill.
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
	ok = _the_preview_is_what_the_mark_does() and ok
	ok = _six_items_spread_over_the_pile_emptiest_first() and ok
	ok = _a_pile_apart_from_home_is_its_own_patch() and ok
	ok = _a_haul_walks_onto_an_outdoor_pile() and ok
	ok = _a_meal_lands_at_the_fire_not_at_the_cooks_feet() and ok
	ok = _a_raider_loots_an_outdoor_pile() and ok
	ok = _the_summary_reads_the_pile_in_words() and ok
	ok = _the_window_takes_and_puts_by_the_sims_rules() and ok
	var skip_note: String = ""
	if not _skipped.is_empty():
		skip_note = " SKIPPED(no data): " + ", ".join(_skipped)
	if ok:
		print("M2_STOCKPILE_OK default mark walled readers save preview spread patch walk cook raider summary take%s" % skip_note)
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
	# A square one tile wider than MAX_TILES allows is past it and is refused whole: nothing changes.
	var side: int = ceili(sqrt(float(SimStockpile.MAX_TILES + 1)))
	var size_before: int = SimStockpile.count(w)
	_mark(w, block.x, block.y, block.x + side - 1, block.y + side - 1, true)
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
	if not _tiles_match(w, "with the patch marked"):
		return false
	w.tilemap.tiles[idx] = SimTileMap.Tile.Wall
	if SimStockpile.has_tile(w, block.x, block.y):
		push_error("WALLED: a walled-over stockpile tile still reads as stockpile")
		return false
	if not _tiles_match(w, "with a tile walled over") or SimStockpile.tiles(w).has(block):
		push_error("WALLED: the zone query still lists the walled tile")
		return false
	w.tilemap.tiles[idx] = floor_tile
	if not SimStockpile.has_tile(w, block.x, block.y):
		push_error("WALLED: the tile did not come back into the zone once it was open again")
		return false
	if not _tiles_match(w, "with the tile open again") or not SimStockpile.tiles(w).has(block):
		push_error("WALLED: the zone query did not list the reopened tile")
		return false
	print("WALLED OK a walled stockpile tile leaves the zone and returns when open, and the zone query is has_tile over the record in row-major order each time")
	return true


# The zone query as it was written first: `has_tile` over every key, sorted by (ty, tx). The fast
# `SimStockpile.tiles` must answer exactly this.
func _slow_tiles(w: Variant) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var rec: Variant = w.components.get_component(w.player, SimStockpile.COMPONENT)
	if not rec is Dictionary:
		return SimStockpile.tiles(w)
	for key in (rec as Dictionary)["tiles"].keys():
		var parts: PackedStringArray = String(key).split(",")
		var t := Vector2i(int(parts[0]), int(parts[1]))
		if SimStockpile.has_tile(w, t.x, t.y):
			out.append(t)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return out


func _tiles_match(w: Variant, when: String) -> bool:
	var fast: Array[Vector2i] = SimStockpile.tiles(w)
	var slow: Array[Vector2i] = _slow_tiles(w)
	if fast != slow or fast.is_empty():
		push_error("WALLED: %s the zone query answers %d tiles where has_tile over the record answers %d, or in another order" % [when, fast.size(), slow.size()])
		return false
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
	# The widest square one `on` may cover, so the refusal below is the zone's cap, not the area's.
	var reach: int = floori(sqrt(float(SimStockpile.MAX_TILES)))
	for ty in range(0, int(w.tilemap.h) - reach, 4):
		for tx in range(0, int(w.tilemap.w) - reach, 4):
			var c: Dictionary = {"type": SimStockpile.COMMAND, "x0": tx, "y0": ty, "x1": tx + reach - 1, "y1": ty + reach - 1, "on": true}
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
	# `patches` is served from the index the window reads (`patch_under`), so the two cannot
	# disagree, and the index follows the zone and the map: a tile marked beside the pile joins its
	# patch, and a wall across the pile splits it. Each answer is the fresh walk's.
	var n_before: int = SimStockpile.patches(w).size()
	_mark(w, block.x + 2, block.y, block.x + 2, block.y, true)
	var grown: Array = []
	for patch2 in SimStockpile.patches(w):
		if (patch2 as Array).has(block):
			grown = patch2 as Array
	if grown.size() != 5 or SimStockpile.patches(w).size() != n_before or not _same(SimStockpile.patches(w), SimStockpile._walk_patches(w)):
		push_error("PATCH: a tile marked beside the pile did not join its patch in the kept index (%d tiles, %d patches)" % [grown.size(), SimStockpile.patches(w).size()])
		return false
	w.components.set_component(w.player, "position", {"x": float(block.x) + 0.5, "y": float(block.y) + 0.5})
	if SimStockpile.patch_under(w, w.player).size() != 5 or not SimStockpile.patch_under(w, w.player).has(Vector2i(block.x + 2, block.y)):
		push_error("PATCH: the patch under the player is not the grown pile, keyed by the tile: %s" % str(SimStockpile.patch_under(w, w.player).keys()))
		return false
	w.tilemap.tiles[block.y * int(w.tilemap.w) + block.x + 1] = SimTileMap.Tile.Wall
	w.invalidate_tiles(Rect2i(block.x + 1, block.y, 1, 1))
	if SimStockpile.patches(w).size() != n_before + 1 or not _same(SimStockpile.patches(w), SimStockpile._walk_patches(w)):
		push_error("PATCH: a wall across the pile did not split the kept index (%d patches, expected %d)" % [SimStockpile.patches(w).size(), n_before + 1])
		return false
	print("PATCH OK the pile is its own patch: beside it the drop is %s, at home %s; the kept index grows with a mark and splits at a wall" % [str(from_camp), str(from_home)])
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


# SUMMARY. The pile emptied, a tin left outside it, then two stacks of tins and a bandage on it.
func _the_summary_reads_the_pile_in_words() -> bool:
	var Read: GDScript = load("res://sim/stockpile_read.gd") as GDScript
	var w: Variant = _world()
	var pile: Array[Vector2i] = SimStockpile.tiles(w)
	var outside: Vector2i = _find(w, func(tx: int, ty: int) -> bool: return _is_outdoor_floor_outside_annex(w, tx, ty))
	if pile.size() < 2 or outside.x < 0:
		push_error("SUMMARY: no two stockpile tiles and an open floor outside them to judge with")
		return false
	# Empty the pile: an item with no position is not on the ground.
	for item in SimNeeds.stockpile_items(w):
		w.components.remove_component(item, "position")
	var stray: int = SimItems.spawn_item(w, "item.food.beans.tin", {"tier": "scavenged", "count": 3})
	w.components.set_component(stray, "position", {"x": float(outside.x) + 0.5, "y": float(outside.y) + 0.5})
	var bare: Array = Read.call("summary", w) as Array
	for row in bare:
		if String((row as Dictionary)["words"]) != "none" or not ((row as Dictionary)["names"] as Array).is_empty():
			push_error("SUMMARY: the emptied pile, a tin outside it, reads %s" % str(row))
			return false
	var placed: Array[Dictionary] = [
		{"id": "item.food.beans.tin", "count": 3},
		{"id": "item.food.fruit.tin", "count": 2},
		{"id": "item.bandage.cloth", "count": 1},
	]
	for i in placed.size():
		var item: int = SimItems.spawn_item(w, String(placed[i]["id"]), {"tier": "scavenged", "count": int(placed[i]["count"])})
		var t: Vector2i = pile[i % pile.size()]
		w.components.set_component(item, "position", {"x": float(t.x) + 0.5, "y": float(t.y) + 0.5})
	var rows: Dictionary = {}
	var order: Array[String] = []
	for row in Read.call("summary", w) as Array:
		rows[String((row as Dictionary)["group"])] = row
		order.append(String((row as Dictionary)["group"]))
	if order != (Read.get("GROUPS") as Array):
		push_error("SUMMARY: the rows stand %s, not the groups' order" % str(order))
		return false
	var food: Dictionary = rows["food"] as Dictionary
	if String(food["words"]) != "some" or (food["names"] as Array) != ["Tin of Beans", "Tin of Peaches"]:
		push_error("SUMMARY: three tins and two read food %s %s, not some, Tin of Beans then Tin of Peaches" % [String(food["words"]), str(food["names"])])
		return false
	var med: Dictionary = rows["medicine"] as Dictionary
	if String(med["words"]) != "one" or (med["names"] as Array) != ["Cloth Bandage"]:
		push_error("SUMMARY: a bandage reads medicine %s %s, not one Cloth Bandage" % [String(med["words"]), str(med["names"])])
		return false
	for g in rows.keys():
		if g != "food" and g != "medicine" and String((rows[g] as Dictionary)["words"]) != "none":
			push_error("SUMMARY: %s reads %s with nothing of it on the pile" % [String(g), String((rows[g] as Dictionary)["words"])])
			return false
	var ladder: Dictionary = {0: "none", 1: "one", 2: "a few", 4: "a few", 5: "some", 9: "some", 10: "plenty", 40: "plenty"}
	for n in ladder.keys():
		if String(Read.call("amount_word", int(n))) != String(ladder[n]):
			push_error("SUMMARY: %d reads %s, not %s" % [int(n), String(Read.call("amount_word", int(n))), String(ladder[n])])
			return false
	var filled: Dictionary = {}
	for base in SimItems.content_entries(w, "item"):
		if base is Dictionary:
			filled[String(Read.call("group_of", base as Dictionary))] = true
	for g in Read.get("GROUPS") as Array:
		if not filled.has(String(g)):
			push_error("SUMMARY: no item in the content falls in %s" % String(g))
			return false
	print("SUMMARY OK an emptied pile reads none with a tin outside it; three tins and two read food some, named most first; a bandage reads medicine one; the ladder holds at each edge; every group has content")
	return true
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
	if SimStockpile.patch_under(w, w.player).size() != 8 or not SimStockpile.patch_under(w, w.player).has(hidden):
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
	# "Take all that fits": the one tin still listed comes in (into the pockets, or merged into the
	# stack of the tin already there), the hidden and off-zone tins stay.
	_send(w, {"type": SimStockpile.TAKE_COMMAND, "all": true})
	var near_taken: bool = not _lies(w, near_tin) and (not w.entities.is_alive(near_tin) or SimInventory.owns(w, w.player, near_tin))
	if not near_taken or not _lies(w, hid_tin) or not _lies(w, off_tin):
		push_error("TAKE: take all did not take exactly the tins in view (near taken %s, hidden lies %s, off lies %s)" % [str(near_taken), str(_lies(w, hid_tin)), str(_lies(w, off_tin))])
		return false
	# Put back: onto a tile of this patch the player sees, not the hidden side.
	_send(w, {"type": SimStockpile.PUT_COMMAND, "item": here_tin})
	var back: Vector2i = _tile_of(w, here_tin)
	if not _lies(w, here_tin) or not SimStockpile.patch_under(w, w.player).has(back) or not SimStockpile.in_view(w, w.player, float(back.x) + 0.5, float(back.y) + 0.5):
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
