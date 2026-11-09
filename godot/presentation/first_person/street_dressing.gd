extends RefCounted
# The first-person street dressing placer: pictures of tiles the sim already has. A vending machine on a
# wall-side tile, a guard rail on the edge of a Low run, a noren hung over an open door. Nothing here is sim
# state: no component, tile, overlay, event or save key is written, and nothing under `godot/sim/` reads this
# file, so a prop is never cover, never a blocker and never a sightline. The picture follows the sim's own
# tile class; the sim keeps its open floor.
#
# Load-bearing properties, as `dressing.gd` holds them:
#   * No RNG. Every choice is `Dressing.hash_at` of the map seed and the tile, with its own salt, so the same
#     seed and map give the same props at the same places on every boot.
#   * Pure statics, no static state. The view resolves the manifest once and passes the entries in.
#
# The rules (the owner's defaults, 2026-11-09):
#   * Tall props (taller than LOW_BAND_M, the sim's Low band) stand flush to a wall, never on a Low tile, never
#     on open floor. Low props stand on Low tiles, or flush to a wall.
#   * `wall` pieces hang on a wall face, proud by at most WALL_PROUD_MAX_M, on a tile whose neighbour is a Wall
#     tile (a Wall tile never opens; a Door tile does).
#   * `run` pieces (guard rail) sit on the edge of a Low tile that has open floor beside it, one piece a tile.
#   * `door_head` (noren) hangs over an open door tile, hem at or above HEM_MIN_M.
#   * Wire spans join consecutive poles on one row or column, at most WIRE_MAX_SPAN_M apart, sagging WIRE_SAG_M.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimSpace = preload("res://sim/space/space.gd")
const Dressing = preload("res://presentation/dressing.gd")

const LOW_BAND_M: float = 1.1
const HEM_MIN_M: float = 1.80
const WALL_PROUD_MAX_M: float = 0.10
const WIRE_SAG_M: float = 0.4
const WIRE_MAX_SPAN_M: float = 40.0
const WIRE_SEGMENTS: int = 8
const PROP_CAP: int = 400
# One prop per this many eligible tiles, on average: the density the owner card sets.
const DENSITY_MOD: int = 6

const PLACEMENTS: Array = ["kerb", "wall", "run", "door_head"]
# Sim sides in the order a tile looks for its wall and its floor: north, east, south, west.
const SIDES: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

const SALT_PICK: int = 501
const SALT_CHOICE: int = 502


# The manifest entries, or [] when the file is missing or unreadable: an absent manifest draws nothing. Accepts a
# bare list of models, or a dictionary with a `models` list. An entry without a usable id, placement or size is
# skipped, so one bad entry cannot take the others down.
static func load_manifest(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var models: Variant = parsed
	if parsed is Dictionary:
		models = (parsed as Dictionary).get("models", [])
	if not (models is Array):
		return []
	var out: Array = []
	for entry in (models as Array):
		if entry is Dictionary and _entry_ok(entry as Dictionary):
			out.append(entry)
	return out


static func size_of(entry: Dictionary) -> Vector3:
	var s: Array = entry.get("size", []) as Array
	return Vector3(float(s[0]), float(s[1]), float(s[2]))


static func _entry_ok(entry: Dictionary) -> bool:
	if String(entry.get("id", "")) == "":
		return false
	if not PLACEMENTS.has(String(entry.get("placement", ""))):
		return false
	var s: Variant = entry.get("size")
	if not (s is Array) or (s as Array).size() != 3:
		return false
	for v in (s as Array):
		if not (v is float or v is int) or float(v) <= 0.0:
			return false
	return true


# Every prop on a map for this seed, in row-major tile order, capped at PROP_CAP. Each placement is a dictionary:
# {id, placement, tx, ty, tile_key, pos (Godot metres, base on the floor or at the hem), yaw, size, hem, proud,
#  anchors (local Vector3 by name)}. Empty for a null map or no entries.
static func placements(map: Variant, seed_val: int, entries: Array) -> Array:
	var out: Array = []
	if map == null or entries.is_empty():
		return out
	var by_kind: Dictionary = {}
	for kind in PLACEMENTS:
		by_kind[kind] = []
	for entry in entries:
		(by_kind[String((entry as Dictionary)["placement"])] as Array).append(entry)
	var vehicle_tiles: Dictionary = _vehicle_tiles(map)
	for ty in range(int(map.h)):
		for tx in range(int(map.w)):
			if out.size() >= PROP_CAP:
				return out
			if vehicle_tiles.has(Vector2i(tx, ty)):
				continue
			var p: Dictionary = _place_on_tile(map, seed_val, tx, ty, by_kind)
			if not p.is_empty():
				out.append(p)
	return out


static func _vehicle_tiles(map: Variant) -> Dictionary:
	var out: Dictionary = {}
	var records: Variant = map.get("vehicles")
	if not (records is Array):
		return out
	for rec in (records as Array):
		if not (rec is Dictionary):
			continue
		var r: Dictionary = rec as Dictionary
		var x0: int = int(r.get("x", 0))
		var y0: int = int(r.get("y", 0))
		for dy in range(int(r.get("h", 1))):
			for dx in range(int(r.get("w", 1))):
				out[Vector2i(x0 + dx, y0 + dy)] = true
	return out


# The wall sides of a tile, as sim offsets, in SIDES order.
static func wall_sides(map: Variant, tx: int, ty: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in SIDES:
		if int(SimTileMap.tile_at(map, tx + d.x, ty + d.y)) == SimTileMap.Tile.Wall:
			out.append(d)
	return out


static func _floor_side(map: Variant, tx: int, ty: int) -> Vector2i:
	for d in SIDES:
		if SimSpace.profile_key(map, tx + d.x, ty + d.y) == "floor":
			return d
	return Vector2i.ZERO


static func _place_on_tile(map: Variant, seed_val: int, tx: int, ty: int, by_kind: Dictionary) -> Dictionary:
	var key: String = SimSpace.profile_key(map, tx, ty)
	if key != "floor" and key != "low" and key != "door.open":
		return {}
	if Dressing.hash_at(seed_val, tx, ty, SALT_PICK) % DENSITY_MOD != 0:
		return {}
	var walls: Array[Vector2i] = wall_sides(map, tx, ty)
	var candidates: Array = []
	if key == "floor" and not walls.is_empty():
		# A wall side takes a flush kerb prop (tall or low) or a wall-hung piece.
		for kind in ["kerb", "wall"]:
			for e in (by_kind[kind] as Array):
				candidates.append(e)
	elif key == "low":
		for e in (by_kind["kerb"] as Array):
			if size_of(e as Dictionary).y <= LOW_BAND_M:
				candidates.append(e)
		if _floor_side(map, tx, ty) != Vector2i.ZERO:
			for e in (by_kind["run"] as Array):
				candidates.append(e)
	elif key == "door.open":
		for e in (by_kind["door_head"] as Array):
			candidates.append(e)
	if candidates.is_empty():
		return {}
	var pick: int = Dressing.variant_index(seed_val, tx, ty, SALT_CHOICE, candidates.size())
	var entry2: Dictionary = candidates[pick] as Dictionary
	return _pose(map, entry2, tx, ty, key, walls)


# The world pose of one entry on one tile. Pure geometry; the sim is not consulted for anything but the tile.
static func _pose(map: Variant, entry: Dictionary, tx: int, ty: int, key: String, walls: Array[Vector2i]) -> Dictionary:
	var size: Vector3 = size_of(entry)
	var placement: String = String(entry["placement"])
	var centre: Vector3 = Vector3(float(tx) + 0.5, 0.0, float(ty) + 0.5)
	var yaw: float = 0.0
	var proud: float = 0.0
	var hem: float = 0.0
	var base_y: float = 0.0
	if placement == "run":
		var f: Vector2i = _floor_side(map, tx, ty)
		var edge: Vector3 = centre + Vector3(float(f.x) * 0.5, 0.0, float(f.y) * 0.5)
		centre = edge
		yaw = 0.0 if f.y != 0 else PI * 0.5
	elif placement == "door_head":
		base_y = HEM_MIN_M
		hem = base_y
		yaw = 0.0 if _has_side(walls, Vector2i(1, 0)) or _has_side(walls, Vector2i(-1, 0)) else PI * 0.5
	elif placement == "wall":
		var d: Vector2i = walls[0]
		proud = minf(WALL_PROUD_MAX_M, size.z * 0.5)
		var edge2: Vector3 = centre + Vector3(float(d.x) * 0.5, 0.0, float(d.y) * 0.5)
		centre = edge2 + Vector3(float(d.x), 0.0, float(d.y)) * ((size.z - 2.0 * proud) * 0.5)
		yaw = atan2(-float(d.x), -float(d.y))
	elif not walls.is_empty() and key == "floor":
		var d2: Vector2i = walls[0]
		centre = centre + Vector3(float(d2.x), 0.0, float(d2.y)) * (0.5 - size.z * 0.5)
		yaw = atan2(-float(d2.x), -float(d2.y))
	return {
		"id": String(entry["id"]),
		"placement": placement,
		"tx": tx,
		"ty": ty,
		"tile_key": key,
		"pos": Vector3(centre.x, base_y, centre.z),
		"yaw": yaw,
		"size": size,
		"hem": hem,
		"proud": proud,
		"anchors": _anchors_of(entry),
	}


static func _has_side(walls: Array[Vector2i], side: Vector2i) -> bool:
	return walls.has(side)


static func _anchors_of(entry: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var anchors: Variant = entry.get("anchors", {})
	if not (anchors is Dictionary):
		return out
	for name in (anchors as Dictionary).keys():
		var v: Variant = (anchors as Dictionary)[name]
		if v is Array and (v as Array).size() == 3:
			out[String(name)] = Vector3(float(v[0]), float(v[1]), float(v[2]))
	return out


# A world point of a local anchor on a placed prop: the prop's yaw, then its position.
static func anchor_world(p: Dictionary, name: String) -> Vector3:
	var anchors: Dictionary = p["anchors"] as Dictionary
	if not anchors.has(name):
		return Vector3.ZERO
	var local: Vector3 = anchors[name] as Vector3
	return (Basis(Vector3.UP, float(p["yaw"])) * local) + (p["pos"] as Vector3)


# Wire spans: consecutive poles on one row (same tile y) or one column (same tile x), at most WIRE_MAX_SPAN_M
# apart, drawn from one pole's wire_a to the next pole's wire_b, sagging WIRE_SAG_M at the middle. A pole with no
# neighbour in range has none. Each span is {a, b, points}.
static func wire_spans(poles_all: Array) -> Array:
	var poles: Array = []
	for p in poles_all:
		var d: Dictionary = p as Dictionary
		if (d["anchors"] as Dictionary).has("wire_a") and (d["anchors"] as Dictionary).has("wire_b"):
			poles.append(d)
	var out: Array = []
	for axis in [0, 1]:
		var groups: Dictionary = {}
		for p in poles:
			var key: int = int((p as Dictionary)["ty"]) if axis == 0 else int((p as Dictionary)["tx"])
			if not groups.has(key):
				groups[key] = []
			(groups[key] as Array).append(p)
		for key in groups.keys():
			var line: Array = groups[key] as Array
			line.sort_custom(func(a, b): return _along(a as Dictionary, axis) < _along(b as Dictionary, axis))
			for i in range(line.size() - 1):
				var pa: Dictionary = line[i] as Dictionary
				var pb: Dictionary = line[i + 1] as Dictionary
				var a: Vector3 = anchor_world(pa, "wire_a")
				var b: Vector3 = anchor_world(pb, "wire_b")
				if a.distance_to(b) > WIRE_MAX_SPAN_M:
					continue
				out.append({"a": a, "b": b, "points": _catenary(a, b)})
	return out


static func _along(p: Dictionary, axis: int) -> float:
	return float(int(p["tx"])) if axis == 1 else float(int(p["ty"]))


static func _catenary(a: Vector3, b: Vector3) -> PackedVector3Array:
	var pts: PackedVector3Array = PackedVector3Array()
	for i in range(WIRE_SEGMENTS + 1):
		var t: float = float(i) / float(WIRE_SEGMENTS)
		var p: Vector3 = a.lerp(b, t)
		p.y -= WIRE_SAG_M * 4.0 * t * (1.0 - t)
		pts.append(p)
	return pts


# The rule check, from the map alone: a list of failure strings, empty when every placement stands where its
# rule allows. Used by the gate on the placer's output and on a planted bad placement.
static func validate(map: Variant, placed: Array) -> Array:
	var fails: Array = []
	if placed.size() > PROP_CAP:
		fails.append("%d props, over the cap of %d" % [placed.size(), PROP_CAP])
	for p in placed:
		var d: Dictionary = p as Dictionary
		var tx: int = int(d["tx"])
		var ty: int = int(d["ty"])
		var id: String = String(d["id"])
		var size: Vector3 = d["size"] as Vector3
		var key: String = SimSpace.profile_key(map, tx, ty)
		var walls: Array[Vector2i] = wall_sides(map, tx, ty)
		var tall: bool = size.y > LOW_BAND_M
		var placement: String = String(d["placement"])
		if tall and key == "low":
			fails.append("%s (%d,%d): a tall prop on a Low tile" % [id, tx, ty])
		match placement:
			"kerb":
				if tall and not (key == "floor" and not walls.is_empty()):
					fails.append("%s (%d,%d): a tall prop not flush to a wall on %s" % [id, tx, ty, key])
				elif not tall and not (key == "low" or (key == "floor" and not walls.is_empty())):
					fails.append("%s (%d,%d): a low prop on %s, not a Low tile or a wall" % [id, tx, ty, key])
			"wall":
				if not (key == "floor" and not walls.is_empty()):
					fails.append("%s (%d,%d): a wall piece not on a wall-side tile" % [id, tx, ty])
				if float(d["proud"]) > WALL_PROUD_MAX_M + 0.0001:
					fails.append("%s (%d,%d): proud %.3f m, over %.2f m" % [id, tx, ty, float(d["proud"]), WALL_PROUD_MAX_M])
			"run":
				if key != "low" or _floor_side(map, tx, ty) == Vector2i.ZERO:
					fails.append("%s (%d,%d): a run piece not on a Low edge beside open floor" % [id, tx, ty])
			"door_head":
				if key != "door.open":
					fails.append("%s (%d,%d): a noren not over an open door, on %s" % [id, tx, ty, key])
				if float(d["hem"]) < HEM_MIN_M - 0.0001:
					fails.append("%s (%d,%d): hem %.3f m, under %.2f m" % [id, tx, ty, float(d["hem"]), HEM_MIN_M])
			_:
				fails.append("%s (%d,%d): unknown placement %s" % [id, tx, ty, placement])
	return fails


# A stable text of every placement, for the gate's hash and for determinism checks.
static func digest_text(placed: Array) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for p in placed:
		var d: Dictionary = p as Dictionary
		var pos: Vector3 = d["pos"] as Vector3
		lines.append("%s %s %d %d %.4f %.4f %.4f %.4f" % [String(d["id"]), String(d["placement"]), int(d["tx"]), int(d["ty"]),
			pos.x, pos.y, pos.z, float(d["yaw"])])
	return "\n".join(lines)
