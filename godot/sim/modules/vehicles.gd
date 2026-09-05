class_name SimVehicles
extends RefCounted
# The parked cars, driven. Every `map.vehicles` record the layout wrote becomes an entity at boot
# (`spawn_from_manifest`), and from then on the entity is the truth and the record is its shadow:
# `sync_map` rewrites the Tile.Low under the footprint and the manifest record beside it whenever
# the car moves, so every reader that already asks the record -- the tile branch, the loot host,
# the pictures -- keeps asking it and never learns the car can move. A save carries the entity
# (components round-trip, the map does not), and `world.restore` re-syncs the shadow from it, the
# same way `SimFortify.sync_map` puts boards back on windows.
#
# What a car is here, in the sim's terms:
#
#   * a `vehicle` component -- {class, w, l, heading, speed, driver, intent, home}. `w` and `l`
#     are the content footprint (breadth across, length along); `heading` is one of n/s/e/w,
#     because nobody rotates (docs/30, the Dungeon Settlers look) and a car has exactly two
#     pictures; `speed` is metres a second along the heading, never negative -- a car that wants
#     to go the other way brakes to a stop and then turns round; `driver` is the entity at the
#     wheel or NO_DRIVER; `intent` is the last move command the driver gave, kept until replaced,
#     exactly as a body's velocity is; `home` is the corner the layout parked it on, which is what
#     the paint hashes on so a car keeps its colour when it leaves the kerb.
#   * `position` at the footprint's centre, `velocity` for the attention emitter and for
#     `Appearance.moving`, `facing` in radians for whoever reads it.
#   * an `attention_emitter` whose walking and sprinting are both the engine's noise and whose
#     ambient is the idle -- set on mount, cleared on dismount -- so the one emit-movement system
#     that already reads every footstep reads the engine too. Scent 0: a car has no smell it
#     leaves behind, and a trail would be a second channel nothing here earns.
#
# The driver is a body with a `mounted` component. Its position is pinned to the car every tick
# (movement, after the car has moved, before the kernel refreshes vision at 100), its velocity is
# pinned to zero so it emits no footsteps of its own, and `SimShambler._gather_survivors` leaves
# it off the menu: a body inside a car cannot be swiped or grabbed. What it can still do -- swing,
# fire, crouch -- is nothing this module refuses, and docs/23 says so.
#
# Steering is four headings and a `move` intent. The dominant axis of the intent names the wanted
# heading: the same heading accelerates, the opposite one brakes and then turns the car round in
# place (a 180 changes no tile), a perpendicular one brakes to a stop and then tries to turn the
# footprint about its centre, which is refused -- silently, the car just does not turn -- when the
# turned footprint would cover something. No intent coasts to a stop. Collision is the leading
# edge: every across-tile of the footprint is probed one step ahead, and a car that would enter
# a solid tile, an indoor tile, another car, or a heap (a Low tile no record covers) stops flush
# against it. Bodies are not probed: a parked car is walk-through cover today and a moving one
# stays walk-through, so nothing is run over -- named in docs/23 rather than half-built here.
#
# Determinism: no RNG anywhere in this file. Every decision is a function of the commands and the
# map, and a replay of the same commands drives the same car to the same tile.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimAttention = preload("res://sim/modules/attention_emitter.gd")
const SimPath = preload("res://sim/path.gd")
const SimWorldgen = preload("res://sim/map/worldgen.gd")

const NO_DRIVER: int = -1
# How close a body has to be to the footprint's edge to get in. Fortify's REACH, the same arm.
const REACH: float = 1.5
const TICK_SECONDS: float = 0.05
# A hair inside the footprint's edges, so a car whose edge sits exactly on a tile boundary covers
# the tiles it stands on and not the neighbour it merely touches.
const EPS: float = 0.001
const HEADINGS: Dictionary = {
	"n": Vector2(0.0, -1.0),
	"s": Vector2(0.0, 1.0),
	"e": Vector2(1.0, 0.0),
	"w": Vector2(-1.0, 0.0),
}
const OPPOSITE: Dictionary = {"n": "s", "s": "n", "e": "w", "w": "e"}
const TOGGLE: String = "vehicle.toggle"
# Coasting with no intent loses speed at this fraction of the class's braking. Engine braking,
# not a handbrake: a car you take your foot off rolls on for a while.
const COAST_FRACTION: float = 0.5


static func register_module(world: Variant) -> void:
	# Input order 4: after world's apply-commands (0) has written the driver's velocity from the
	# move command -- so the pin below zeroes what it wrote rather than racing it -- and before
	# fortify's intake at 5, whose E ladder (SimFortify._use_context) is how the player gets in
	# and out: from the wheel E dismounts, from the kerb it mounts after the loot and the people
	# beside the car (the owner's 2026-09-05 decision, docs/30 "Driving"). TOGGLE stays a command
	# of its own for gates and replays; nothing in presentation pushes it.
	world.systems.register("vehicle.intake", "input", 4, func(w: Variant) -> void:
		_intake(w)
	)
	# Movement order 1: world's integrate at 0 has skipped every vehicle (world.gd says so), the
	# kernel refreshes light at 75 and vision at 100 -- so the driver's pinned position is where
	# the car now is by the time anybody looks out of it.
	world.systems.register("vehicle.drive", "movement", 1, func(w: Variant) -> void:
		_drive(w)
	)


# --- content ------------------------------------------------------------------------------------

# The class entry for a content id, or {} when the world declares no such class.
static func class_of(world: Variant, id: String) -> Dictionary:
	if world == null or not (world.content is Dictionary) or id.is_empty():
		return {}
	# The tree is keyed by content path ("vehicles/sedan.json"), and the worldgen pass already
	# knows how to read the vehicle entries out of it; one reader, not two that could disagree.
	for entry in SimWorldgen.vehicles_of(world.content as Dictionary):
		if String((entry as Dictionary).get("id", "")) == id:
			return entry as Dictionary
	return {}


# The five numbers a class drives on -- {speed, accel, brake, noise, idle} -- or {} when the class
# declares no usable `drive` block. Judged whole rather than defaulted a key at a time: the
# validator does not recurse, so a class missing `brake` would otherwise drive on a silent guess,
# and a car that never stops is exactly the wrong number nothing reports. A class with no drive
# block cannot be mounted, and `mount_problem` says so.
static func drive_of(entry: Dictionary) -> Dictionary:
	var block: Variant = entry.get("drive")
	if not (block is Dictionary):
		return {}
	var d: Dictionary = block as Dictionary
	var out: Dictionary = {}
	for key in ["speed", "accel", "brake", "noise", "idle"]:
		var v: Variant = d.get(key)
		if not (v is float or v is int):
			return {}
		var f: float = float(v)
		if f < 0.0 or (key != "idle" and f <= 0.0):
			return {}
		out[key] = f
	return out


# --- spawning and the map shadow ---------------------------------------------------------------

# One entity per manifest record. Called by SimBoot.playable after the map is adopted; a record
# whose class the content does not declare, or declares without a footprint, is left as it is --
# a parked picture nobody can drive -- and reported, because the generator wrote it from a class
# it found and this should never happen on a coherent tree.
static func spawn_from_manifest(world: Variant, map: Variant) -> Array[int]:
	var spawned: Array[int] = []
	if map == null:
		return spawned
	var records: Variant = map.get("vehicles")
	if not (records is Array):
		return spawned
	for rec in records as Array:
		if not (rec is Dictionary):
			continue
		var r: Dictionary = rec as Dictionary
		if r.has("entity"):
			continue
		var entry: Dictionary = class_of(world, String(r.get("class", "")))
		var foot: Dictionary = entry.get("footprint", {}) as Dictionary
		var breadth: int = int(foot.get("w", 0))
		var length: int = int(foot.get("l", 0))
		if breadth < 1 or length < 1:
			push_error("vehicles: record %s names %s, which declares no footprint; it stays a picture" % [str(r), String(r.get("class", ""))])
			continue
		var facing: String = String(r.get("facing", "n"))
		if not HEADINGS.has(facing):
			facing = "n"
		var x: int = int(r.get("x", 0))
		var y: int = int(r.get("y", 0))
		var w: int = int(r.get("w", 0))
		var h: int = int(r.get("h", 0))
		var entity: int = int(world.entities.spawn())
		world.components.set_component(entity, "vehicle", {
			"class": String(r.get("class", "")),
			"w": breadth,
			"l": length,
			"heading": facing,
			"speed": 0.0,
			"driver": NO_DRIVER,
			"intent": {"dx": 0.0, "dy": 0.0},
			"home": {"x": x, "y": y},
		})
		world.components.set_component(entity, "position", {"x": float(x) + float(w) / 2.0, "y": float(y) + float(h) / 2.0})
		var dir: Vector2 = HEADINGS[facing] as Vector2
		world.components.set_component(entity, "facing", {"radians": atan2(dir.y, dir.x)})
		# No `velocity` and no `attention_emitter` while parked: those are the engine, and they
		# arrive with the driver (`mount`) and leave with them (`dismount`). A parked car is then
		# outside every per-tick query that walks velocities -- world's integrate, the emitter's
		# footsteps, this module's own drive loop -- which is what keeps a hundred parked cars at
		# 256 from costing a tick anything. Measured at 128 with 33 cars: 0.35 ms a tick with the
		# components on every parked car, none with them off.
		# Claimed, so the sync below replaces this record with the entity's shadow rather than
		# keeping it beside one -- the first probe stood sixty-six records over thirty-three cars.
		r["entity"] = entity
		spawned.append(entity)
	if not spawned.is_empty():
		sync_map(world)
	return spawned


# The engine: a velocity to integrate and an emitter for the one system that already hears every
# footstep. `walking` and `sprinting` are both the engine under way (the emitter picks by speed,
# and a car is never quiet at either), `ambient` the idle, scent nothing.
static func _start_engine(world: Variant, entity: int, drive: Dictionary) -> void:
	world.components.set_component(entity, "velocity", {"dx": 0.0, "dy": 0.0})
	var noise: float = float(drive.get("noise", 0.0))
	SimAttention.make_emitter(world, entity, {"walking": noise, "sprinting": noise, "ambient": float(drive.get("idle", 0.0)), "scent": 0.0})


static func _stop_engine(world: Variant, entity: int) -> void:
	world.components.remove(entity, "velocity")
	world.components.remove(entity, "attention_emitter")


# Rebuilds the map's shadow of every vehicle entity: the Tile.Low under each footprint and the
# `map.vehicles` record beside it. Records that name an entity are replaced wholesale; records
# that name none (a manifest nobody spawned from -- a gate booting `bare`, a fixture) are kept as
# they are, so a map with parked pictures and no module still draws them. Called at spawn, after
# a restore, and by `_drive` whenever a footprint's tiles change.
static func sync_map(world: Variant) -> void:
	var map: Variant = world.tilemap
	if map == null:
		return
	var records: Variant = map.get("vehicles")
	if not (records is Array):
		return
	var kept: Array = []
	for rec in records as Array:
		if not (rec is Dictionary):
			continue
		var r: Dictionary = rec as Dictionary
		if r.has("entity"):
			_clear_tiles(map, _rect_of_record(r))
		else:
			kept.append(r)
	for entity in world.components.query(["vehicle", "position"]):
		var v: Dictionary = world.components.get_component(int(entity), "vehicle") as Dictionary
		var pos: Dictionary = world.components.get_component(int(entity), "position") as Dictionary
		var rect: Rect2i = footprint(v, pos)
		_write_tiles(map, rect)
		kept.append(_record_for(int(entity), v, pos, rect))
	map.vehicles = kept
	map.vehicle_generation = int(map.vehicle_generation) + 1
	world.invalidateMap()


static func _record_for(entity: int, v: Dictionary, pos: Dictionary, rect: Rect2i) -> Dictionary:
	var heading: String = String(v.get("heading", "n"))
	var home: Dictionary = v.get("home", {}) as Dictionary
	var gp: Vector2 = ground_point(v, pos)
	return {
		"x": rect.position.x, "y": rect.position.y,
		"w": rect.size.x, "h": rect.size.y,
		"axis": axis_of(heading),
		"class": String(v.get("class", "")),
		"facing": heading,
		"entity": entity,
		# The corner the layout parked it on, which is what the paint hashes on: a car that
		# drives off keeps its colour, and two cars never share a home.
		"hx": int(home.get("x", rect.position.x)),
		"hy": int(home.get("y", rect.position.y)),
		# Where the picture stands this tick, in metres -- the live centre of the south edge,
		# so a moving car draws where it is rather than snapping tile to tile.
		"gx": gp.x,
		"gy": gp.y,
	}


static func _rect_of_record(r: Dictionary) -> Rect2i:
	return Rect2i(int(r.get("x", 0)), int(r.get("y", 0)), int(r.get("w", 0)), int(r.get("h", 0)))


static func _clear_tiles(map: Variant, rect: Rect2i) -> void:
	for ty in range(rect.position.y, rect.end.y):
		for tx in range(rect.position.x, rect.end.x):
			if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
				continue
			var i: int = ty * int(map.w) + tx
			if int(map.tiles[i]) == SimTileMap.Tile.Low:
				map.tiles[i] = SimTileMap.Tile.Floor


static func _write_tiles(map: Variant, rect: Rect2i) -> void:
	for ty in range(rect.position.y, rect.end.y):
		for tx in range(rect.position.x, rect.end.x):
			if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
				continue
			map.tiles[ty * int(map.w) + tx] = SimTileMap.Tile.Low


# --- geometry ----------------------------------------------------------------------------------

static func axis_of(heading: String) -> String:
	return "ns" if heading == "n" or heading == "s" else "ew"


# The footprint's extent in tiles for a heading: (across x, across y).
static func extent_of(v: Dictionary, heading: String) -> Vector2i:
	var breadth: int = int(v.get("w", 2))
	var length: int = int(v.get("l", 5))
	if axis_of(heading) == "ns":
		return Vector2i(breadth, length)
	return Vector2i(length, breadth)


# The tiles a car covers standing at `pos` -- every tile its rectangle overlaps by more than EPS,
# so a car mid-step covers the tile it is entering as well as the one it is leaving.
static func footprint(v: Dictionary, pos: Dictionary) -> Rect2i:
	var ext: Vector2i = extent_of(v, String(v.get("heading", "n")))
	var cx: float = float(pos.get("x", 0.0))
	var cy: float = float(pos.get("y", 0.0))
	var x0: int = floori(cx - float(ext.x) / 2.0 + EPS)
	var y0: int = floori(cy - float(ext.y) / 2.0 + EPS)
	var x1: int = ceili(cx + float(ext.x) / 2.0 - EPS)
	var y1: int = ceili(cy + float(ext.y) / 2.0 - EPS)
	return Rect2i(x0, y0, maxi(1, x1 - x0), maxi(1, y1 - y0))


# Where the picture stands: the centre of the footprint's south edge, in metres.
static func ground_point(v: Dictionary, pos: Dictionary) -> Vector2:
	var ext: Vector2i = extent_of(v, String(v.get("heading", "n")))
	return Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)) + float(ext.y) / 2.0)


# Snaps one coordinate of the centre so the footprint sits on whole tiles: an even extent wants
# the centre on a tile boundary, an odd one on a tile's middle.
static func _snap(value: float, extent: int) -> float:
	var frac: float = fmod(float(extent) / 2.0, 1.0)
	return floorf(value - frac + 0.5) + frac


# The centre a car would have after turning to `heading`, snapped to the grid for that heading.
static func turned_centre(v: Dictionary, pos: Dictionary, heading: String) -> Dictionary:
	var ext: Vector2i = extent_of(v, heading)
	return {"x": _snap(float(pos.get("x", 0.0)), ext.x), "y": _snap(float(pos.get("y", 0.0)), ext.y)}


# The tiles a car would cover after turning to `heading` about its (snapped) centre. Public so
# the gate fabricates its wall on a tile this answer names rather than on one it computed twice.
static func turned_footprint(v: Dictionary, pos: Dictionary, heading: String) -> Rect2i:
	var turned: Dictionary = v.duplicate(true)
	turned["heading"] = heading
	return footprint(turned, turned_centre(v, pos, heading))


# --- what a car may drive into ----------------------------------------------------------------

# Whether `entity` may cover this tile: off the map, solid, indoors, and any Low tile that is not
# already this car's own are all refusals. A Low tile no record covers is a heap of junk; one
# another record covers is another car.
static func tile_blocks(world: Variant, map: Variant, entity: int, tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return true
	if world.is_blocked_tile(tx, ty):
		return true
	var i: int = ty * int(map.w) + tx
	if int(map.indoors[i]) != 0:
		return true
	if int(map.tiles[i]) != SimTileMap.Tile.Low:
		return false
	return not _own_record_covers(map, entity, tx, ty)


static func _own_record_covers(map: Variant, entity: int, tx: int, ty: int) -> bool:
	var records: Variant = map.get("vehicles")
	if not (records is Array):
		return false
	for rec in records as Array:
		if not (rec is Dictionary):
			continue
		var r: Dictionary = rec as Dictionary
		if int(r.get("entity", NO_DRIVER)) != entity:
			continue
		return _rect_of_record(r).has_point(Vector2i(tx, ty))
	return false


static func _rect_clear(world: Variant, map: Variant, entity: int, rect: Rect2i) -> bool:
	for ty in range(rect.position.y, rect.end.y):
		for tx in range(rect.position.x, rect.end.x):
			if tile_blocks(world, map, entity, tx, ty):
				return false
	return true


# --- mounting ----------------------------------------------------------------------------------

# The vehicle a body could get into from where it stands, or NO_DRIVER: the nearest footprint
# whose edge is within REACH, that nobody is driving, whose class can be driven at all.
static func nearest_in_reach(world: Variant, actor: int) -> int:
	var pos: Variant = world.components.get_component(actor, "position")
	if not (pos is Dictionary):
		return NO_DRIVER
	var px: float = float((pos as Dictionary).get("x", 0.0))
	var py: float = float((pos as Dictionary).get("y", 0.0))
	var best: int = NO_DRIVER
	var best_d: float = REACH + 1.0
	for entity in world.components.query(["vehicle", "position"]):
		var v: Dictionary = world.components.get_component(int(entity), "vehicle") as Dictionary
		if int(v.get("driver", NO_DRIVER)) != NO_DRIVER:
			continue
		var d: float = _distance_to_footprint(v, world.components.get_component(int(entity), "position") as Dictionary, px, py)
		if d <= REACH and d < best_d:
			best_d = d
			best = int(entity)
	return best


static func _distance_to_footprint(v: Dictionary, pos: Dictionary, px: float, py: float) -> float:
	var ext: Vector2i = extent_of(v, String(v.get("heading", "n")))
	var cx: float = float(pos.get("x", 0.0))
	var cy: float = float(pos.get("y", 0.0))
	var dx: float = maxf(0.0, absf(px - cx) - float(ext.x) / 2.0)
	var dy: float = maxf(0.0, absf(py - cy) - float(ext.y) / 2.0)
	return sqrt(dx * dx + dy * dy)


# Why this body cannot get into this car right now, or "" when it can.
static func mount_problem(world: Variant, actor: int, entity: int) -> String:
	if world.components.has_component(actor, "mounted"):
		return "already at a wheel"
	var v: Variant = world.components.get_component(entity, "vehicle")
	if not (v is Dictionary):
		return "not a vehicle"
	if int((v as Dictionary).get("driver", NO_DRIVER)) != NO_DRIVER:
		return "somebody is driving it"
	if drive_of(class_of(world, String((v as Dictionary).get("class", "")))).is_empty():
		return "its class declares no drive block"
	for busy in ["grabbed", "treatment", "treated", "rescue", "corpse", "construct"]:
		if world.components.has_component(actor, busy):
			return "hands are not free (%s)" % busy
	var pos: Variant = world.components.get_component(actor, "position")
	if not (pos is Dictionary):
		return "no position"
	var d: float = _distance_to_footprint(v as Dictionary, world.components.get_component(entity, "position") as Dictionary, float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]))
	if d > REACH:
		return "out of reach"
	return ""


static func mount(world: Variant, actor: int, entity: int) -> bool:
	if not mount_problem(world, actor, entity).is_empty():
		return false
	var v: Dictionary = world.components.get_component(entity, "vehicle") as Dictionary
	var vpos: Dictionary = world.components.get_component(entity, "position") as Dictionary
	v["driver"] = actor
	v["intent"] = {"dx": 0.0, "dy": 0.0}
	world.components.set_component(actor, "mounted", {"vehicle": entity})
	_pin_driver(world, actor, vpos)
	_start_engine(world, entity, drive_of(class_of(world, String(v.get("class", "")))))
	world.events.publish({"type": "vehicle.mounted", "entity": entity, "driver": actor})
	return true


# Out through the nearest door: the first free walkable tile in the ring around the footprint,
# nearest the driver's side of the car (west of a north-south car, north of an east-west one,
# the way the pictures are drawn) and then any other. Refused when the ring has nowhere to stand,
# which a car wedged between walls can manage; the driver stays put and nothing changes.
static func dismount(world: Variant, actor: int) -> bool:
	var m: Variant = world.components.get_component(actor, "mounted")
	if not (m is Dictionary):
		return false
	var entity: int = int((m as Dictionary).get("vehicle", NO_DRIVER))
	var v: Variant = world.components.get_component(entity, "vehicle")
	if not (v is Dictionary):
		world.components.remove(actor, "mounted")
		return false
	# Not at speed: the door opens when the car has stopped, and the HUD clause says so.
	if float((v as Dictionary).get("speed", 0.0)) > 0.0:
		return false
	var vpos: Dictionary = world.components.get_component(entity, "position") as Dictionary
	var out: Variant = exit_tile(world, v as Dictionary, vpos)
	if out == null:
		return false
	var tile: Vector2i = out as Vector2i
	(v as Dictionary)["driver"] = NO_DRIVER
	(v as Dictionary)["speed"] = 0.0
	(v as Dictionary)["intent"] = {"dx": 0.0, "dy": 0.0}
	_stop_engine(world, entity)
	world.components.remove(actor, "mounted")
	var pos: Dictionary = world.components.get_component(actor, "position") as Dictionary
	pos["x"] = float(tile.x) + 0.5
	pos["y"] = float(tile.y) + 0.5
	world.events.publish({"type": "vehicle.dismounted", "entity": entity, "driver": actor, "x": pos["x"], "y": pos["y"]})
	return true


static func exit_tile(world: Variant, v: Dictionary, vpos: Dictionary) -> Variant:
	var rect: Rect2i = footprint(v, vpos)
	var ring: Array[Vector2i] = []
	var ns: bool = axis_of(String(v.get("heading", "n"))) == "ns"
	# Driver's side first, then the far side, then the ends.
	if ns:
		for ty in range(rect.position.y, rect.end.y):
			ring.append(Vector2i(rect.position.x - 1, ty))
		for ty in range(rect.position.y, rect.end.y):
			ring.append(Vector2i(rect.end.x, ty))
		for tx in range(rect.position.x, rect.end.x):
			ring.append(Vector2i(tx, rect.position.y - 1))
			ring.append(Vector2i(tx, rect.end.y))
	else:
		for tx in range(rect.position.x, rect.end.x):
			ring.append(Vector2i(tx, rect.position.y - 1))
		for tx in range(rect.position.x, rect.end.x):
			ring.append(Vector2i(tx, rect.end.y))
		for ty in range(rect.position.y, rect.end.y):
			ring.append(Vector2i(rect.position.x - 1, ty))
			ring.append(Vector2i(rect.end.x, ty))
	for t in ring:
		if not SimPath.walkable(world, t.x, t.y):
			continue
		if SimTileMap.tile_at(world.tilemap, t.x, t.y) == SimTileMap.Tile.Low:
			continue
		if not world.body_fits_at(float(t.x) + 0.5, float(t.y) + 0.5):
			continue
		return t
	return null


static func _pin_driver(world: Variant, actor: int, vpos: Dictionary) -> void:
	var pos: Variant = world.components.get_component(actor, "position")
	if pos is Dictionary:
		(pos as Dictionary)["x"] = float(vpos.get("x", 0.0))
		(pos as Dictionary)["y"] = float(vpos.get("y", 0.0))
	var vel: Variant = world.components.get_component(actor, "velocity")
	if vel is Dictionary:
		(vel as Dictionary)["dx"] = 0.0
		(vel as Dictionary)["dy"] = 0.0


# --- the systems --------------------------------------------------------------------------------

static func _intake(w: Variant) -> void:
	var current: Array = w.commands.current as Array
	if current.is_empty():
		return
	for cmd in current:
		var c: Dictionary = cmd as Dictionary
		var kind: String = String(c.get("type", ""))
		for actor in w.components.query(["controlled", "position"]):
			match kind:
				TOGGLE:
					if w.components.has_component(int(actor), "mounted"):
						dismount(w, int(actor))
					else:
						var near: int = nearest_in_reach(w, int(actor))
						if near != NO_DRIVER:
							mount(w, int(actor), near)
				"move", "wait":
					var m: Variant = w.components.get_component(int(actor), "mounted")
					if not (m is Dictionary):
						continue
					var v: Variant = w.components.get_component(int((m as Dictionary).get("vehicle", NO_DRIVER)), "vehicle")
					if not (v is Dictionary):
						continue
					if kind == "wait":
						(v as Dictionary)["intent"] = {"dx": 0.0, "dy": 0.0}
					else:
						(v as Dictionary)["intent"] = {"dx": float(c.get("dx", 0.0)), "dy": float(c.get("dy", 0.0))}
	# The pin, every tick a command arrived: world's apply-commands wrote the driver's velocity from
	# the move, and a driver's feet do not move the car.
	for actor2 in w.components.query(["mounted", "velocity"]):
		var vel: Dictionary = w.components.get_component(int(actor2), "velocity") as Dictionary
		vel["dx"] = 0.0
		vel["dy"] = 0.0


# The heading an intent asks for, or "" for no intent. Dominant axis; a tie goes to the current
# heading if it is one of the two, so a diagonal keeps the car straight rather than wobbling.
static func wanted_heading(intent: Dictionary, current: String) -> String:
	var dx: float = float(intent.get("dx", 0.0))
	var dy: float = float(intent.get("dy", 0.0))
	if dx == 0.0 and dy == 0.0:
		return ""
	if absf(dx) == absf(dy):
		var hx: String = "e" if dx > 0.0 else "w"
		var hy: String = "s" if dy > 0.0 else "n"
		if current == hx or current == hy:
			return current
		return hy
	if absf(dx) > absf(dy):
		return "e" if dx > 0.0 else "w"
	return "s" if dy > 0.0 else "n"


static func _drive(w: Variant) -> void:
	var map: Variant = w.tilemap
	if map == null:
		return
	for entity in w.components.query(["vehicle", "position", "velocity"]):
		var e: int = int(entity)
		var v: Dictionary = w.components.get_component(e, "vehicle") as Dictionary
		var pos: Dictionary = w.components.get_component(e, "position") as Dictionary
		var vel: Dictionary = w.components.get_component(e, "velocity") as Dictionary
		var driver: int = int(v.get("driver", NO_DRIVER))
		if driver != NO_DRIVER:
			var m: Variant = w.components.get_component(driver, "mounted")
			# A driver who is no longer a driver -- despawned, dead at the wheel, or a component
			# somebody else removed -- releases the car; a corpse is not driving anywhere.
			if not (m is Dictionary) or int((m as Dictionary).get("vehicle", NO_DRIVER)) != e or w.components.has_component(driver, "corpse"):
				if m is Dictionary and int((m as Dictionary).get("vehicle", NO_DRIVER)) == e:
					w.components.remove(driver, "mounted")
				v["driver"] = NO_DRIVER
				v["intent"] = {"dx": 0.0, "dy": 0.0}
				v["speed"] = 0.0
				_stop_engine(w, e)
				continue
		var speed: float = float(v.get("speed", 0.0))
		var heading: String = String(v.get("heading", "n"))
		var moved: bool = false
		# Only a car with a driver has a velocity, so only a car with a driver is in this loop --
		# and only then is the class looked up. Looking it up for every parked car every tick was
		# measured at 1.9 ms a tick at 128 (`SimWorldgen.vehicles_of` sorts the whole content
		# tree's keys to answer), which is why a parked car has no engine components at all.
		if driver == NO_DRIVER:
			_stop_engine(w, e)
			continue
		else:
			var drive: Dictionary = drive_of(class_of(w, String(v.get("class", ""))))
			if drive.is_empty():
				speed = 0.0
			else:
				var brake: float = float(drive["brake"]) * TICK_SECONDS
				var want: String = wanted_heading(v.get("intent", {}) as Dictionary, heading)
				if want.is_empty():
					speed = maxf(0.0, speed - brake * COAST_FRACTION)
				elif want == heading:
					var cap: float = float(drive["speed"]) * w.surface_speed_at(float(pos["x"]), float(pos["y"]))
					speed += float(drive["accel"]) * TICK_SECONDS
					# Over the cap -- a paved car rolling onto grass -- sheds speed at the brake
					# rather than snapping down to it.
					if speed > cap:
						speed = maxf(cap, speed - brake - float(drive["accel"]) * TICK_SECONDS)
				else:
					speed = maxf(0.0, speed - brake)
					if speed == 0.0:
						if want == String(OPPOSITE[heading]):
							# Turning round in place covers the same tiles; the record's facing and
							# the picture's flip follow the heading through sync below.
							heading = want
							moved = true
						else:
							var centre: Dictionary = turned_centre(v, pos, want)
							if _rect_clear(w, map, e, turned_footprint(v, pos, want)):
								heading = want
								pos["x"] = float(centre["x"])
								pos["y"] = float(centre["y"])
								moved = true
			v["heading"] = heading
			if speed > 0.0:
				var dir: Vector2 = HEADINGS[heading] as Vector2
				var ext: Vector2i = extent_of(v, heading)
				var along_axis_x: bool = dir.x != 0.0
				var sign: float = dir.x if along_axis_x else dir.y
				var half: float = float(ext.x if along_axis_x else ext.y) / 2.0
				var along: float = float(pos["x"] if along_axis_x else pos["y"])
				var step: float = speed * TICK_SECONDS
				var front: float = along + sign * half
				var probe: float = front + sign * (step + EPS)
				var probe_tile: int = floori(probe)
				var rect: Rect2i = footprint(v, pos)
				var blocked: bool = false
				if along_axis_x:
					for ty in range(rect.position.y, rect.end.y):
						if tile_blocks(w, map, e, probe_tile, ty):
							blocked = true
							break
				else:
					for tx in range(rect.position.x, rect.end.x):
						if tile_blocks(w, map, e, tx, probe_tile):
							blocked = true
							break
				if blocked:
					# Flush against the tile it cannot enter, and stopped.
					var boundary: float = float(probe_tile) if sign > 0.0 else float(probe_tile + 1)
					along = boundary - sign * half
					speed = 0.0
				else:
					along += sign * step
				if along_axis_x:
					pos["x"] = along
				else:
					pos["y"] = along
				moved = true
		v["speed"] = speed
		var dir2: Vector2 = HEADINGS[heading] as Vector2
		vel["dx"] = dir2.x * speed
		vel["dy"] = dir2.y * speed
		var facing: Variant = w.components.get_component(e, "facing")
		if facing is Dictionary:
			(facing as Dictionary)["radians"] = atan2(dir2.y, dir2.x)
		if moved:
			_sync_one(w, map, e, v, pos)
		if driver != NO_DRIVER:
			_pin_driver(w, driver, pos)


# The shadow of one car after it moved: the record's ground point every time, the tiles and the
# record's rectangle only when the footprint's tiles actually changed -- a car crossing a tile
# rewrites a dozen tiles and bumps the map generation, and a car mid-tile rewrites nothing.
static func _sync_one(w: Variant, map: Variant, entity: int, v: Dictionary, pos: Dictionary) -> void:
	var records: Variant = map.get("vehicles")
	if not (records is Array):
		sync_map(w)
		return
	var rect: Rect2i = footprint(v, pos)
	for i in (records as Array).size():
		var rec: Variant = (records as Array)[i]
		if not (rec is Dictionary):
			continue
		var r: Dictionary = rec as Dictionary
		if int(r.get("entity", NO_DRIVER)) != entity:
			continue
		var old: Rect2i = _rect_of_record(r)
		var fresh: Dictionary = _record_for(entity, v, pos, rect)
		if old == rect and String(r.get("facing", "")) == String(fresh["facing"]):
			r["gx"] = fresh["gx"]
			r["gy"] = fresh["gy"]
			return
		_clear_tiles(map, old)
		_write_tiles(map, rect)
		(records as Array)[i] = fresh
		map.vehicle_generation = int(map.vehicle_generation) + 1
		w.invalidateMap()
		return
	# No record for this entity yet -- a car spawned by hand -- so build the whole shadow.
	sync_map(w)


# --- read models --------------------------------------------------------------------------------

# One prose line for the HUD about the car beside you or under you, or "" when there is neither.
# Words only (the HUD gate allows no digits): the class's own name and the key.
static func hud_clause(world: Variant, actor: int) -> String:
	var m: Variant = world.components.get_component(actor, "mounted")
	if m is Dictionary:
		var v: Variant = world.components.get_component(int((m as Dictionary).get("vehicle", NO_DRIVER)), "vehicle")
		if v is Dictionary:
			var name: String = String(class_of(world, String((v as Dictionary).get("class", ""))).get("name", "car")).to_lower()
			if float((v as Dictionary).get("speed", 0.0)) > 0.0:
				return "driving the %s; E to get out once it stops" % name
			return "at the wheel of the %s, engine running; E to get out" % name
		return ""
	var near: int = nearest_in_reach(world, actor)
	if near == NO_DRIVER:
		return ""
	var nv: Dictionary = world.components.get_component(near, "vehicle") as Dictionary
	var near_name: String = String(class_of(world, String(nv.get("class", ""))).get("name", "car")).to_lower()
	return "a %s beside you; E to get in" % near_name
