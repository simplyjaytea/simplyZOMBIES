class_name SimStockpile
extends RefCounted
# The stockpile as tiles in the sim -- docs/12's "Stockpiles are physical and lootable", first
# slice. Until now "the stockpile" was one test with no record behind it: indoors, a floor, inside
# the annex. This module keeps the same answer as the default and lets the player change it.
#
# The zone is a record on the player entity, `stockpile: {"tiles": {"tx,ty": true}}`, keyed by the
# String "tx,ty" because a component never holds a Dictionary keyed by an int (JSON hands the keys
# back as Strings). The record is created the first time anything changes the zone, seeded from the
# default, so until then the zone IS the default and no entity, save key or boot step exists for it.
# A save from before this slice has no record and reads as the default, with no version bump. The
# record sits on the player rather than a new entity so no entity id after it moves.
#
# A zone tile answers `has_tile` only while the map leaves it open: a tile walled over after it was
# marked is not a stockpile tile, and reads again once it is opened. The default zone answers the
# same way, which changes nothing for the annex, where nothing is solid on a floor.
#
# `SimNeeds.is_stockpile_tile` is the one caller-facing predicate and it now asks here. Beds do not
# follow the zone: `SimNeeds.is_annex_floor` still answers where a bed goes, and it delegates to
# `is_annex_floor` below. This file preloads nothing that reaches back to `needs.gd`, so `needs.gd`
# can preload this one without a cycle.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimSurface = preload("res://sim/map/surface.gd")
const SimSightings = preload("res://sim/modules/sightings.gd")

const COMMAND: String = "stockpile.mark"
const COMPONENT: String = "stockpile"
# The most tiles a zone may hold, and the most a single `on` rectangle may cover. Both bound every
# scan of the zone (the Haul search, the drop point, the window that lists it). A mark that would
# pass the cap is refused whole, never applied in part.
const MAX_TILES: int = 1000


static func register_module(world: Variant) -> void:
	# Input order 16: after orders' intake at 15, so a mark issued this tick is in force from the
	# `jobs.ai` pass of the same tick, as an order is.
	world.systems.register("stockpile.intake", "input", 16, func(w: Variant) -> void:
		for cmd in w.commands.current as Array:
			var c: Dictionary = cmd as Dictionary
			if String(c.get("type", "")) == COMMAND:
				mark(w, c)
	)
	register_window(world)


## The annex's indoor floor: the default zone, and nothing else. Beds are placed here and only here.
static func is_annex_floor(world: Variant, tx: int, ty: int) -> bool:
	if world.tilemap == null:
		return false
	if not SimTileMap.is_indoors(world.tilemap, tx, ty):
		return false
	if SimTileMap.tile_at(world.tilemap, tx, ty) != SimTileMap.Tile.Floor:
		return false
	# Where the annex is comes off the map now rather than out of `SimDirector.ANNEX`. An unstamped
	# district reports the empty rect, which has no points -- so it has no stockpile, rather than
	# one at somebody else's coordinates.
	var annex: Rect2i = SimTileMap.annex_rect(world.tilemap)
	if annex.size.x <= 0 or annex.size.y <= 0:
		return false
	return annex.has_point(Vector2i(tx, ty))


## Is (tx, ty) a stockpile tile right now: in the zone and open ground.
static func has_tile(world: Variant, tx: int, ty: int) -> bool:
	if world.tilemap == null:
		return false
	var rec: Variant = _record(world)
	if rec == null:
		if not is_annex_floor(world, tx, ty):
			return false
	elif not (rec as Dictionary)["tiles"].has(_key(tx, ty)):
		return false
	return not SimTileMap.is_solid(world.tilemap, tx, ty)


## The zone's tiles, row-major (`ty` then `tx`), each one `has_tile` answers for right now. The
## drop point and every other ordered reader take their order from here.
static func tiles(world: Variant) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if world.tilemap == null:
		return out
	var rec: Variant = _record(world)
	if rec == null:
		var annex: Rect2i = SimTileMap.annex_rect(world.tilemap)
		for j in range(annex.position.y, annex.position.y + annex.size.y):
			for i in range(annex.position.x, annex.position.x + annex.size.x):
				if has_tile(world, i, j):
					out.append(Vector2i(i, j))
		return out
	# The Haul drop asks this every tick a hauler walks with an item, so it is kept cheap: each key
	# is parsed once, the solid test is asked directly (the key is in the zone by construction, the
	# rest of `has_tile`), and the row-major order is a native sort of `ty * w + tx`. Same answer as
	# `has_tile` over the keys sorted by (ty, tx); godot:m2:stockpile's WALLED lane holds it to that.
	var map: Variant = world.tilemap
	var w: int = int(map.w)
	var order := PackedInt32Array()
	for key in (rec as Dictionary)["tiles"].keys():
		var k: String = String(key)
		var comma: int = k.find(",")
		var tx: int = k.substr(0, comma).to_int()
		var ty: int = k.substr(comma + 1).to_int()
		if not SimTileMap.is_solid(map, tx, ty):
			order.append(ty * w + tx)
	order.sort()
	out.resize(order.size())
	for i in order.size():
		out[i] = Vector2i(order[i] % w, order[i] / w)
	return out


## A number that changes whenever `tiles` could answer differently: the zone record, whose record it
## is, and the map's generation (a tile walled over or opened bumps it). For a reader that keeps the zone between
## frames -- the overlay asks every frame, and walks the zone only when this moves.
static func signature(world: Variant) -> int:
	var rec: Variant = _record(world)
	return hash([int(world.map_generation), int(world.player), (rec as Dictionary)["tiles"] if rec is Dictionary else null])


static func count(world: Variant) -> int:
	return tiles(world).size()


## Whether the zone has any tile at all right now -- the question "is there anywhere to haul to",
## asked by the Haul search for every idle colonist every tick, so it stops at the first live tile:
## the default zone answers at its first floor tile, a marked zone at its first open key. Only a
## zone of nothing but walled-over tiles walks the whole record.
static func has_any_tile(world: Variant) -> bool:
	if world.tilemap == null:
		return false
	var rec: Variant = _record(world)
	if rec == null:
		var annex: Rect2i = SimTileMap.annex_rect(world.tilemap)
		for j in range(annex.position.y, annex.position.y + annex.size.y):
			for i in range(annex.position.x, annex.position.x + annex.size.x):
				if has_tile(world, i, j):
					return true
		return false
	var map: Variant = world.tilemap
	for key in (rec as Dictionary)["tiles"].keys():
		var t: Vector2i = _parse(String(key))
		if not SimTileMap.is_solid(map, t.x, t.y):
			return true
	return false


## The zone's patches: groups of zone tiles that touch edge to edge, each row-major. A pile marked at
## a camp is its own patch however far it is from the annex. Patches come out in the row-major order
## of their first tile, so the list has one order whatever the record's keys were.
static func patches(world: Variant) -> Array:
	var zone: Array[Vector2i] = tiles(world)
	# Keyed by the tile itself: a String key per tile and per neighbour was most of this walk's cost.
	var member: Dictionary = {}
	for t in zone:
		member[t] = true
	var w: int = int(world.tilemap.w)
	var seen: Dictionary = {}
	var out: Array = []
	for t in zone:
		if seen.has(t):
			continue
		var order := PackedInt32Array()
		var pending: Array[Vector2i] = [t]
		seen[t] = true
		while not pending.is_empty():
			var c: Vector2i = pending.pop_back()
			order.append(c.y * w + c.x)
			for n: Vector2i in [Vector2i(c.x + 1, c.y), Vector2i(c.x - 1, c.y), Vector2i(c.x, c.y + 1), Vector2i(c.x, c.y - 1)]:
				if member.has(n) and not seen.has(n):
					seen[n] = true
					pending.append(n)
		# Row-major is `y * w + x` ascending, so a native sort of that number is `_row_major`.
		order.sort()
		var group: Array[Vector2i] = []
		group.resize(order.size())
		for i in order.size():
			group[i] = Vector2i(order[i] % w, order[i] / w)
		out.append(group)
	return out


## Where a hauled item goes down, from `from`. The nearest patch with a free zone tile takes it, and
## inside that patch the free tile with the fewest items on it wins, ties to the nearest to `from`,
## ties again to row-major order. `lying` holds the tile of every loose item, one entry each, and
## `free` says whether a tile can take an item at all (no bed, no campfire). The zone is never full:
## a tile's count only rises as it fills, so nothing is refused for room. (-1, -1) when no zone tile
## is free.
static func drop_tile(world: Variant, from: Vector2, lying: Array[Vector2i], free: Callable) -> Vector2i:
	var load: Dictionary = {}
	for t in lying:
		load[t] = int(load.get(t, 0)) + 1
	var ranked: Array = []
	for p in patches(world):
		ranked.append({"d": _patch_distance(p, from), "patch": p, "i": ranked.size()})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["d"] < b["d"] or (a["d"] == b["d"] and a["i"] < b["i"])
	)
	for entry in ranked:
		var best := Vector2i(-1, -1)
		var best_load: int = 0
		var best_d: float = INF
		for t in entry["patch"]:
			if not free.call(t.x, t.y):
				continue
			var n: int = int(load.get(t, 0))
			var d: float = _centre_distance(from, t)
			if best.x < 0 or n < best_load or (n == best_load and d < best_d):
				best = t
				best_load = n
				best_d = d
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


## May the player mark this tile: open, dry, a floor, a door left out, and ground the player has seen.
## Indoors and out are both allowed. An unexplored tile is refused, because a player cannot mark
## ground they have never seen.
static func markable(world: Variant, tx: int, ty: int) -> bool:
	return markable_in(world, SimSightings.explored_view(world, world.player), tx, ty)


## `markable` with the player's explored set already decoded (`SimSightings.explored_view`), for a
## caller that asks about many tiles at once -- the drag preview asks about a whole rectangle every
## frame, and decoding the bitset once per tile would be most of its cost. Same answer, same order of
## tests; `markable` is this with the view fetched for one tile.
static func markable_in(world: Variant, explored: Variant, tx: int, ty: int) -> bool:
	if world.tilemap == null:
		return false
	var map: Variant = world.tilemap
	if tx < 0 or ty < 0 or tx >= map.w or ty >= map.h:
		return false
	if SimTileMap.tile_at(map, tx, ty) != SimTileMap.Tile.Floor:
		return false
	if SimTileMap.is_solid(map, tx, ty):
		return false
	if SimSurface.surface_at(map, tx, ty) == SimSurface.Surface.Water:
		return false
	var ov: Variant = SimTileMap.overlay_at(map, tx, ty)
	if ov is Dictionary and String((ov as Dictionary).get("kind", "")) == "door":
		return false
	return explored != null and bool((explored as Object).call("has_tile", tx, ty))


## What `stockpile.mark` would change, without changing it: {"tiles": the tiles it would add (`on`)
## or take back (`off`), row-major; "refused": true when an `on` would be refused whole}. `mark`
## below applies exactly this answer, so the screen's drag preview and the command cannot disagree
## about a tile: what the preview draws is what the release changes, and a refused rectangle draws
## nothing because it changes nothing.
static func preview(world: Variant, cmd: Dictionary) -> Dictionary:
	var x0: int = mini(int(cmd.get("x0", 0)), int(cmd.get("x1", 0)))
	var x1: int = maxi(int(cmd.get("x0", 0)), int(cmd.get("x1", 0)))
	var y0: int = mini(int(cmd.get("y0", 0)), int(cmd.get("y1", 0)))
	var y1: int = maxi(int(cmd.get("y0", 0)), int(cmd.get("y1", 0)))
	var out: Array[Vector2i] = []
	if world.tilemap == null:
		return {"tiles": out, "refused": false}
	var on: bool = bool(cmd.get("on", true))
	if on and (x1 - x0 + 1) * (y1 - y0 + 1) > MAX_TILES:
		return {"tiles": out, "refused": true}
	var rec: Variant = _record(world)
	if on:
		var have: Dictionary = (rec as Dictionary)["tiles"] if rec is Dictionary else _default_keys(world)
		var explored: Variant = SimSightings.explored_view(world, world.player)
		for ty in range(y0, y1 + 1):
			for tx in range(x0, x1 + 1):
				if not have.has(_key(tx, ty)) and markable_in(world, explored, tx, ty):
					out.append(Vector2i(tx, ty))
		if have.size() + out.size() > MAX_TILES:
			return {"tiles": [] as Array[Vector2i], "refused": true}
		return {"tiles": out, "refused": false}
	var keys: Array = (rec as Dictionary)["tiles"].keys() if rec is Dictionary else _default_keys(world).keys()
	for key in keys:
		var t: Vector2i = _parse(String(key))
		if t.x >= x0 and t.x <= x1 and t.y >= y0 and t.y <= y1:
			out.append(t)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return {"tiles": out, "refused": false}


## `stockpile.mark {x0, y0, x1, y1, on}`: an inclusive rectangle. `on` adds every markable tile in it,
## and a rectangle larger than MAX_TILES is refused whole, as is an `on` that would take the zone past
## MAX_TILES. `off` takes back every zone tile inside it, markable or not; it scans the zone rather
## than the rectangle, so a rectangle of any size is safe to clear. What changes is `preview`'s answer.
static func mark(world: Variant, cmd: Dictionary) -> void:
	if world.tilemap == null:
		return
	var change: Dictionary = preview(world, cmd)
	var tiles_changed: Array = change["tiles"] as Array
	if bool(change["refused"]) or tiles_changed.is_empty():
		return
	var on: bool = bool(cmd.get("on", true))
	var set_tiles: Dictionary = _ensure(world)["tiles"]
	for t in tiles_changed:
		var key: String = _key((t as Vector2i).x, (t as Vector2i).y)
		if on:
			set_tiles[key] = true
		else:
			set_tiles.erase(key)
	world.events.publish({"type": "stockpile.changed", "added": tiles_changed.size() if on else 0, "removed": 0 if on else tiles_changed.size()})


# The record, or null while the zone is still the default.
static func _record(world: Variant) -> Variant:
	if world.player < 0 or not world.entities.is_alive(world.player):
		return null
	var comp: Variant = world.components.get_component(world.player, COMPONENT)
	return comp if comp is Dictionary else null


# The record, created from the default zone when there is none yet.
static func _ensure(world: Variant) -> Dictionary:
	var rec: Variant = _record(world)
	if rec is Dictionary:
		return rec as Dictionary
	var tiles_seed: Dictionary = {}
	for t in _default_tiles(world):
		tiles_seed[_key(t.x, t.y)] = true
	var fresh: Dictionary = {"tiles": tiles_seed}
	world.components.set_component(world.player, COMPONENT, fresh)
	return fresh


static func _default_tiles(world: Variant) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var annex: Rect2i = SimTileMap.annex_rect(world.tilemap)
	for j in range(annex.position.y, annex.position.y + annex.size.y):
		for i in range(annex.position.x, annex.position.x + annex.size.x):
			if is_annex_floor(world, i, j):
				out.append(Vector2i(i, j))
	return out


# The default zone as the record would hold it, for `preview` to ask about before any record exists.
static func _default_keys(world: Variant) -> Dictionary:
	var out: Dictionary = {}
	for t in _default_tiles(world):
		out[_key(t.x, t.y)] = true
	return out


static func _key(tx: int, ty: int) -> String:
	return "%d,%d" % [tx, ty]


static func _parse(key: String) -> Vector2i:
	var parts: PackedStringArray = key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))


static func _row_major(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)


static func _centre_distance(from: Vector2, t: Vector2i) -> float:
	return from.distance_squared_to(Vector2(float(t.x) + 0.5, float(t.y) + 0.5))


static func _patch_distance(patch: Array, from: Vector2) -> float:
	var best: float = INF
	for t in patch:
		best = minf(best, _centre_distance(from, t))
	return best


# --- taking from the stockpile (slice S4) ---------------------------------------------------------
#
# The loot window, fed the stockpile instead of a cupboard: the player standing in a patch of the
# zone sees what lies on it and takes or puts things away with the window's drag and ctrl-click. The
# stockpile is items on tiles, not a grid, so there is no container entity behind the window: the
# view lays the items out into a grid for the screen, and the four commands below say what the sim
# accepts. A drag between the two grids never becomes an `item.move` on a stockpile item; the window
# sends `stockpile.take` and `stockpile.put`, and this module decides.
#
# What the window lists is card 3's default (the 2026-10-24 plan, section 11): every loose item on
# the patch the actor stands on that the actor sees right now. An item round a corner of a big patch,
# or behind a wall, is not listed and cannot be taken, because information stays scarce. Nearest
# first, so a patch with more on it than the window holds shows what is beside you, and walking
# across the pile shows the rest.
#
# The window is open while the actor carries `OPEN_COMPONENT`, which E (`SimFortify._use_context`),
# the right-click row and `stockpile.open` set, and which is taken off when the actor steps off the
# zone, opens a cupboard, or sends `stockpile.close`. A save from before this slice has no such
# component and loads with the window shut; nothing needs a version bump.

## The window's container id: no entity has it. The screen reads it to know a grid is the stockpile.
const STORES: int = -100
const OPEN_COMPONENT: String = "stockpileOpen"
const LABEL: String = "the stockpile"
const OPEN_COMMAND: String = "stockpile.open"
const CLOSE_COMMAND: String = "stockpile.close"
const TAKE_COMMAND: String = "stockpile.take"
const PUT_COMMAND: String = "stockpile.put"
## What E and the right-click menu call opening the window.
const OPEN_WORDS: String = "go through the stockpile"
## The grid the view lays out into when the caller names none.
const VIEW_COLS: int = 8
const VIEW_ROWS: int = 4


## Input order 17, after `stockpile.intake` at 16, and after containers (9) and inventory (10): a
## cupboard opened this tick has its `opening` by now, and shuts the window here.
static func register_window(world: Variant) -> void:
	world.systems.register("stockpile.window", "input", 17, func(w: Variant) -> void:
		for cmd in w.commands.current as Array:
			var c: Dictionary = cmd as Dictionary
			var kind: String = String(c.get("type", ""))
			if kind != OPEN_COMMAND and kind != CLOSE_COMMAND and kind != TAKE_COMMAND and kind != PUT_COMMAND:
				continue
			# A refusal changes nothing and says nothing: the window drew only what the sim lists and
			# asked only what `can_place` allows, so a refusal is a mis-drag or a stale frame.
			for actor in w.components.query(["controlled", "position"]):
				match kind:
					OPEN_COMMAND:
						open(w, int(actor))
					CLOSE_COMMAND:
						close(w, int(actor))
					TAKE_COMMAND:
						if bool(c.get("all", false)):
							take_all(w, int(actor))
						else:
							take(w, int(actor), int(c.get("item", -1)), c)
					PUT_COMMAND:
						put(w, int(actor), int(c.get("item", -1)))
		# The window follows the body: off the zone, or with a cupboard open, it is shut.
		for actor2 in w.components.query([OPEN_COMPONENT]):
			if not standing_on(w, int(actor2)) or w.components.has_component(int(actor2), "opening"):
				close(w, int(actor2))
	)


## The tile under `actor`, or (-1, -1) with no position.
static func tile_of(world: Variant, actor: int) -> Vector2i:
	var p: Variant = world.components.get_component(actor, "position")
	if not (p is Dictionary):
		return Vector2i(-1, -1)
	return Vector2i(floori(float((p as Dictionary)["x"])), floori(float((p as Dictionary)["y"])))


## Whether `actor` stands on a stockpile tile.
static func standing_on(world: Variant, actor: int) -> bool:
	var t: Vector2i = tile_of(world, actor)
	return t.x >= 0 and has_tile(world, t.x, t.y)


## The patch `actor` stands in, as a set of "tx,ty" keys; empty off the zone. Read from the zone's
## patches, which are worked out once per zone and map (`_patch_index`), not once per ask: the window
## asks every tick it is open, and walking the default zone tile by tile is milliseconds.
static func patch_under(world: Variant, actor: int) -> Dictionary:
	var start: Vector2i = tile_of(world, actor)
	if start.x < 0:
		return {}
	var index: Dictionary = _patch_index(world)
	var which: Variant = (index["of"] as Dictionary).get(_key(start.x, start.y))
	if which == null:
		return {}
	return (index["sets"] as Array)[int(which)] as Dictionary


# The zone's patches as {sig, of: {"tx,ty": patch}, sets: [{"tx,ty": true}]}, kept on the world (as
# metadata, never saved and never shared between two worlds) for as long as the zone record and the
# map generation are what they were. Every answer is the one `patches` gives; this only keeps it.
const _PATCH_META: StringName = &"stockpile_patch_index"


static func _patch_index(world: Variant) -> Dictionary:
	var rec: Variant = _record(world)
	var sig: int = hash([int(world.map_generation), (rec as Dictionary)["tiles"] if rec is Dictionary else null])
	var kept: Variant = (world as Object).get_meta(_PATCH_META, null)
	if kept is Dictionary and int((kept as Dictionary)["sig"]) == sig:
		return kept as Dictionary
	var of: Dictionary = {}
	var sets: Array = []
	for group in patches(world):
		var members: Dictionary = {}
		for t in group:
			members[_key((t as Vector2i).x, (t as Vector2i).y)] = true
			of[_key((t as Vector2i).x, (t as Vector2i).y)] = sets.size()
		sets.append(members)
	var built: Dictionary = {"sig": sig, "of": of, "sets": sets}
	(world as Object).set_meta(_PATCH_META, built)
	return built


## Whether the window is open for `actor` right now: the component, and still standing on the zone.
static func is_open(world: Variant, actor: int) -> bool:
	return world.components.has_component(actor, OPEN_COMPONENT) and standing_on(world, actor)


## Open the window. Refused off the zone. A cupboard the actor had open is shut: one window at a time.
static func open(world: Variant, actor: int) -> Dictionary:
	if not standing_on(world, actor):
		return {"ok": false, "reason": "off-the-stockpile"}
	if world.components.has_component(actor, "opening"):
		world.components.remove(actor, "opening")
	world.components.set_component(actor, OPEN_COMPONENT, {"open": true})
	return {"ok": true}


static func close(world: Variant, actor: int) -> void:
	world.components.remove(actor, OPEN_COMPONENT)


## What E would open here: the actor stands on the zone, no cupboard is in reach (a cupboard wins),
## and the loose item E would otherwise pick up lies on the zone. That last condition keeps E's
## ladder as it was everywhere else -- a door, a bed or a fire beside an empty pile still takes E.
static func e_opens(world: Variant, actor: int, nearest_item: Variant, box_in_reach: bool) -> bool:
	if box_in_reach or nearest_item == null or not standing_on(world, actor):
		return false
	var t: Vector2i = tile_of(world, int(nearest_item))
	return t.x >= 0 and has_tile(world, t.x, t.y)


## Whether `actor` sees the spot from where they stand: walls and range (`line_of_sight`), or a lit
## spot past the dark's reach (`detail`, which also knows lit targets). Not the facing arc: the body
## faces the pointer, and the pointer is on the window, so an arc would change the list as the mouse
## moved across it. A thing behind a wall or round a corner is still not seen.
static func in_view(world: Variant, actor: int, x: float, y: float) -> bool:
	if world.vision == null:
		return false
	return bool(world.vision.line_of_sight(actor, x, y)) or int(world.vision.detail(actor, x, y)) > 0


## The items the window lists for `actor`: loose, not a corpse, on the actor's patch, and in view
## from where they stand (`in_view`). Nearest first, ties by id. Empty off the zone.
static func in_sight(world: Variant, actor: int) -> Array[int]:
	var out: Array[int] = []
	if world.vision == null:
		return out
	var patch: Dictionary = patch_under(world, actor)
	if patch.is_empty():
		return out
	var here: Variant = world.components.get_component(actor, "position")
	var hx: float = float((here as Dictionary)["x"])
	var hy: float = float((here as Dictionary)["y"])
	var ranked: Array = []
	for item in world.components.query(["position", "itemBase"]):
		var id: int = int(item)
		if world.components.has_component(id, "stored") or world.components.has_component(id, "corpse"):
			continue
		var p: Dictionary = world.components.get_component(id, "position") as Dictionary
		var px: float = float(p["x"])
		var py: float = float(p["y"])
		if not patch.has(_key(floori(px), floori(py))):
			continue
		if not in_view(world, actor, px, py):
			continue
		ranked.append({"id": id, "d": (px - hx) * (px - hx) + (py - hy) * (py - hy)})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["d"] < b["d"] or (a["d"] == b["d"] and a["id"] < b["id"])
	)
	for r in ranked:
		out.append(int(r["id"]))
	return out


## What the loot window draws: the shape `SimContainers.open_view` hands it, `{container, label, w, h,
## items}`, with `container` STORES and `label` "the stockpile", plus `more` -- true when something
## seen on the patch did not fit the grid, so the window can say so in words. `{}` while the window
## is shut. The nearest items go in, laid out first-fit into `cols` x `rows`, biggest first; the layout
## is the screen's, and the sim never reads it back (a take names an item, not a cell). The list is in
## the nearest-first order whatever the layout, so the window and "take all" agree on order.
static func stores_view(world: Variant, actor: int, cols: int = VIEW_COLS, rows: int = VIEW_ROWS) -> Dictionary:
	if not is_open(world, actor):
		return {}
	var SimInventory: GDScript = load("res://sim/modules/inventory.gd") as GDScript
	var SimItems: GDScript = load("res://sim/modules/items.gd") as GDScript
	var w: int = maxi(1, cols)
	var h: int = maxi(1, rows)
	var used: Array[bool] = []
	used.resize(w * h)
	used.fill(false)
	# Which things: the nearest, in order, while their cells still fit the grid. How they go in: the
	# biggest first, so a pack or a rifle is not shut out by tins scattered over the rows it needed;
	# then anything left, nearest first, into the gaps. What still does not go in is `more`.
	var seen: Array[int] = in_sight(world, actor)
	var sizes: Dictionary = {}
	var chosen: Array = []
	var area: int = 0
	for item in seen:
		var size: Dictionary = SimItems.call("size_of_item", world, item) as Dictionary
		sizes[item] = size
		var cells: int = int(size.get("w", 1)) * int(size.get("h", 1))
		if area + cells > w * h:
			break
		area += cells
		chosen.append({"item": item, "cells": cells, "i": chosen.size()})
	chosen.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["cells"] > b["cells"] or (a["cells"] == b["cells"] and a["i"] < b["i"])
	)
	var placed: Dictionary = {}
	var free_cells: int = w * h
	for c in chosen:
		var it: int = int(c["item"])
		var spot: Variant = _first_fit(used, w, h, int((sizes[it] as Dictionary).get("w", 1)), int((sizes[it] as Dictionary).get("h", 1)))
		if spot != null:
			placed[it] = spot
			free_cells -= int(c["cells"])
	# The gaps, while there are any: a full grid asks nothing more of the rest of the pile.
	for item2 in seen:
		if free_cells <= 0:
			break
		if placed.has(item2):
			continue
		var size2: Dictionary = sizes[item2] if sizes.has(item2) else SimItems.call("size_of_item", world, item2) as Dictionary
		var cells2: int = int(size2.get("w", 1)) * int(size2.get("h", 1))
		if cells2 > free_cells:
			continue
		var spot2: Variant = _first_fit(used, w, h, int(size2.get("w", 1)), int(size2.get("h", 1)))
		if spot2 != null:
			placed[item2] = spot2
			free_cells -= cells2
	var items: Array = []
	var more: bool = false
	for item3 in seen:
		if placed.has(item3):
			items.append(SimInventory.call("view_of", world, item3, placed[item3]))
		else:
			more = true
	return {"container": STORES, "label": LABEL, "w": w, "h": h, "items": items, "more": more}


# The first free cell, row by row, where a w x h footprint fits, unturned and then turned; marks the
# cells it takes. {x, y, rotated}, or null.
static func _first_fit(used: Array[bool], cols: int, rows: int, iw: int, ih: int) -> Variant:
	for turned in [false, true]:
		var fw: int = ih if turned else iw
		var fh: int = iw if turned else ih
		if fw > cols or fh > rows:
			continue
		for y in rows - fh + 1:
			for x in cols - fw + 1:
				var free: bool = true
				for j in fh:
					for i in fw:
						if used[(y + j) * cols + x + i]:
							free = false
							break
					if not free:
						break
				if not free:
					continue
				for j2 in fh:
					for i2 in fw:
						used[(y + j2) * cols + x + i2] = true
				return {"x": x, "y": y, "rotated": turned}
	return null


## `stockpile.take {item}`: the ordinary pickup -- stow it, else wear it -- of an item the window
## lists, with the patch in place of the 1.5 m reach. With `container`, `x`, `y`, `rotated` it goes
## to that cell of a bag the actor carries, or nowhere. Refused, the item stays where it lay.
static func take(world: Variant, actor: int, item: int, cell: Dictionary = {}) -> Dictionary:
	if not is_open(world, actor):
		return {"ok": false, "reason": "not-open"}
	if item < 0 or not in_sight(world, actor).has(item):
		return {"ok": false, "reason": "not-in-sight"}
	var SimInventory: GDScript = load("res://sim/modules/inventory.gd") as GDScript
	var pos: Dictionary = (world.components.get_component(item, "position") as Dictionary).duplicate()
	if cell.has("container"):
		var box: int = int(cell["container"])
		if not (SimInventory.call("reachable_containers", world, actor) as Array).has(box):
			return {"ok": false, "reason": "not-carried"}
		var placed: Dictionary = SimInventory.call("place_at", world, item, box, int(cell.get("x", 0)), int(cell.get("y", 0)), bool(cell.get("rotated", false))) as Dictionary
		if not bool(placed.get("ok", false)):
			return {"ok": false, "reason": String(placed.get("reason", "does-not-fit"))}
	else:
		world.components.remove(item, "position")
		if not bool(SimInventory.call("stow", world, actor, item)) and not bool(SimInventory.call("equip", world, actor, item)):
			world.components.set_component(item, "position", pos)
			return {"ok": false, "reason": "no-room"}
	# A cook's claim on a raw, or a hauler's, goes with the item: the player has it now, and a claim
	# left behind would let the job finish on a thing in the player's pocket.
	world.components.remove(item, "reserved")
	world.events.publish({"type": "item.pickedUp", "entity": actor, "item": item})
	return {"ok": true}


## "take all that fits": every listed item, in the window's order, that stows. Returns how many moved.
static func take_all(world: Variant, actor: int) -> int:
	var moved: int = 0
	if not is_open(world, actor):
		return moved
	for item in in_sight(world, actor):
		if bool(take(world, actor, item).get("ok", false)):
			moved += 1
	return moved


## `stockpile.put {item}`: something the actor carries goes down on the actor's patch, on the tile
## S3's rule picks from where the actor stands (`drop_tile`: the emptiest, then the nearest), kept to
## the tiles of this patch the actor sees.
static func put(world: Variant, actor: int, item: int) -> Dictionary:
	if not is_open(world, actor):
		return {"ok": false, "reason": "not-open"}
	var SimInventory: GDScript = load("res://sim/modules/inventory.gd") as GDScript
	if item < 0 or not bool(SimInventory.call("owns", world, actor, item)):
		return {"ok": false, "reason": "not-carried"}
	var patch: Dictionary = patch_under(world, actor)
	var taken: Dictionary = {}
	for kind in ["bed", "campfire"]:
		for e in world.components.query([kind, "position"]):
			taken[_key(tile_of(world, int(e)).x, tile_of(world, int(e)).y)] = true
	var lying: Array[Vector2i] = []
	for g in world.components.query(["position", "itemBase"]):
		if not world.components.has_component(int(g), "stored"):
			lying.append(tile_of(world, int(g)))
	# Inside the patch, and on a tile the actor can see: put away, the thing stays in the window
	# rather than landing on the emptiest tile across a big pile, out of sight and so off the list.
	# The tile underfoot is always seen, so a free patch always has somewhere.
	var here: Vector2i = tile_of(world, actor)
	var drop: Vector2i = drop_tile(world, Vector2(float(here.x) + 0.5, float(here.y) + 0.5), lying, func(tx: int, ty: int) -> bool:
		return patch.has(_key(tx, ty)) and not taken.has(_key(tx, ty)) and in_view(world, actor, float(tx) + 0.5, float(ty) + 0.5)
	)
	if drop.x < 0:
		return {"ok": false, "reason": "no-free-tile"}
	SimInventory.call("drop_at_feet", world, actor, item)
	world.components.set_component(item, "position", {"x": float(drop.x) + 0.5, "y": float(drop.y) + 0.5})
	return {"ok": true}
