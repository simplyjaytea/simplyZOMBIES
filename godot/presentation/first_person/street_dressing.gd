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
# Pole rules (follow-up to t1x's VERDICT): poles at least POLE_MIN_SPACING_M apart, a span at least WIRE_MIN_SPAN_M long,
# and three parallel wires per pair (a to a, b to b, c to c) across a crossarm set at POLE_YAW_RAD (across the run).
const POLE_MIN_SPACING_M: float = 25.0
const WIRE_MIN_SPAN_M: float = 10.0
const POLE_YAW_RAD: float = PI * 0.5
const WIRE_KEYS: Array = ["wire_a", "wire_b", "wire_c"]
# Plants (gate): true drops the spacing rule; true drops the building-crossing rule.
const PLANT_NO_POLE_SPACING: bool = false
const PLANT_NO_WIRE_BUILDING_CHECK: bool = false
const SALT_POLE: int = 504
const WIRE_SEGMENTS: int = 8
const PROP_CAP: int = 400
# One prop per this many eligible tiles, on average: the density the owner card sets.
const DENSITY_MOD: int = 6

const PLACEMENTS: Array = ["kerb", "wall", "run", "door_head"]
# Sim sides in the order a tile looks for its wall and its floor: north, east, south, west.
const SIDES: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

const SALT_PICK: int = 501
const SALT_CHOICE: int = 502
# The rank a placement takes when the eligible set outnumbers PROP_CAP.
const SALT_RANK: int = 503
# Plant (gate): true restores the old low-bit choice (hash % count); the choice gate must go red.
const CHOICE_LOW_BITS: bool = false
# true: keep the lowest-ranked PROP_CAP placements. false: the row-major cut (the gate's plant only).
const CAP_BY_RANK: bool = true


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


# Every prop on a map for this seed, in row-major tile order. Each placement is a dictionary:
# {id, placement, tx, ty, tile_key, pos (Godot metres, base on the floor or at the hem), yaw, size, hem, proud,
#  anchors (local Vector3 by name)}. Empty for a null map or no entries.
#
# Past PROP_CAP eligible placements, WHICH props are kept is chosen by hash rank, not by the first rows: each
# eligible tile has a rank from Dressing.hash_at with SALT_RANK, ties broken by tile index, and the lowest
# PROP_CAP ranks are kept. The kept set is emitted in row-major order, so the digest is stable. A plain row-major
# cut would leave the south of a large district bare; CAP_BY_RANK false is that cut, kept only as the plant the
# gate proves itself against.
static func placements(map: Variant, seed_val: int, entries: Array, mix: Dictionary = {}) -> Array:
	var out: Array = []
	if map == null or entries.is_empty():
		return out
	var by_kind: Dictionary = {}
	for kind in PLACEMENTS:
		by_kind[kind] = []
	for entry in entries:
		(by_kind[String((entry as Dictionary)["placement"])] as Array).append(entry)
	var vehicle_tiles: Dictionary = _vehicle_tiles(map)
	var w: int = int(map.w)
	var all: Array = []
	for ty in range(int(map.h)):
		for tx in range(int(map.w)):
			if vehicle_tiles.has(Vector2i(tx, ty)):
				continue
			var p: Dictionary = _place_on_tile(map, seed_val, tx, ty, by_kind, mix)
			if not p.is_empty():
				all.append(p)
	# Per-id caps, decided in hash-rank order so a capped kind spreads over the district, not the top rows.
	if _has_caps(mix):
		var by_rank: Array = all.duplicate()
		by_rank.sort_custom(func(a, b): return _rank_before(a as Dictionary, b as Dictionary, seed_val, w))
		var counts: Dictionary = {}
		var capped: Array = []
		for p in by_rank:
			var id: String = String((p as Dictionary)["id"])
			var cap: int = _cap_of(mix, id)
			if cap >= 0 and int(counts.get(id, 0)) >= cap:
				continue
			counts[id] = int(counts.get(id, 0)) + 1
			capped.append(p)
		all = capped
	all = _pole_pass(all, seed_val, w)
	if all.size() <= PROP_CAP:
		all.sort_custom(func(a, b): return _tile_index(a as Dictionary, w) < _tile_index(b as Dictionary, w))
		return all
	if not CAP_BY_RANK:
		return all.slice(0, PROP_CAP)
	# Past PROP_CAP: priority placements (the poles that carry the wires) are kept first, then by hash rank.
	var ranked: Array = all.duplicate()
	ranked.sort_custom(func(a, b): return _keeps_before(a as Dictionary, b as Dictionary, seed_val, w, mix))
	var kept: Array = ranked.slice(0, PROP_CAP)
	kept.sort_custom(func(a, b): return _tile_index(a as Dictionary, w) < _tile_index(b as Dictionary, w))
	return kept


# The mix: weights and caps per prop id, from the data file (street_dressing.json). Absent: every id weight 1, no caps.
static func load_mix(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


static func _props_of(mix: Dictionary) -> Dictionary:
	var props: Variant = mix.get("props", {})
	if props is Dictionary:
		return props as Dictionary
	return {}


static func _has_caps(mix: Dictionary) -> bool:
	for id in _props_of(mix).keys():
		if _cap_of(mix, String(id)) >= 0:
			return true
	return false


# The cap for an id, or -1 for none.
static func _cap_of(mix: Dictionary, id: String) -> int:
	var row: Variant = _props_of(mix).get(id, {})
	if row is Dictionary and (row as Dictionary).has("max_per_district"):
		return maxi(0, int((row as Dictionary)["max_per_district"]))
	return -1


# Weight in hundredths: the id's row, else the default row, else 1.0.
static func _weight_of(mix: Dictionary, id: String) -> int:
	var row: Variant = _props_of(mix).get(id, {})
	if row is Dictionary and (row as Dictionary).has("weight"):
		return maxi(0, roundi(float((row as Dictionary)["weight"]) * 100.0))
	var base: Variant = mix.get("default", {})
	if base is Dictionary and (base as Dictionary).has("weight"):
		return maxi(0, roundi(float((base as Dictionary)["weight"]) * 100.0))
	return 100


static func _priority_of(mix: Dictionary, id: String) -> bool:
	var row: Variant = _props_of(mix).get(id, {})
	return row is Dictionary and bool((row as Dictionary).get("priority", false))


# Poles: those placed wall-side on the district, taken in hash order and kept only where no other kept pole is within
# POLE_MIN_SPACING_M (greedy). A kept pole's crossarm is set across the run (POLE_YAW_RAD). Other props pass through.
static func _pole_pass(all: Array, seed_val: int, w: int) -> Array:
	var poles: Array = []
	var others: Array = []
	for p in all:
		if _is_pole(p as Dictionary):
			poles.append(p)
		else:
			others.append(p)
	poles.sort_custom(func(a, b): return _rank_before(a as Dictionary, b as Dictionary, seed_val, w))
	var kept: Array = []
	for p in poles:
		var d: Dictionary = p as Dictionary
		if not PLANT_NO_POLE_SPACING and not _pole_clear(d, kept):
			continue
		d["yaw"] = POLE_YAW_RAD
		kept.append(d)
	others.append_array(kept)
	return others


static func _is_pole(p: Dictionary) -> bool:
	var anchors: Dictionary = p.get("anchors", {}) as Dictionary
	return anchors.has("wire_a") and anchors.has("wire_b")


static func _pole_clear(p: Dictionary, kept: Array) -> bool:
	var at: Vector3 = p["pos"] as Vector3
	for q in kept:
		var other: Vector3 = (q as Dictionary)["pos"] as Vector3
		if Vector2(at.x, at.z).distance_to(Vector2(other.x, other.z)) < POLE_MIN_SPACING_M:
			return false
	return true


# True when a is kept before b past the cap: priority first, then the lower hash rank.
static func _keeps_before(a: Dictionary, b: Dictionary, seed_val: int, w: int, mix: Dictionary) -> bool:
	var pa: bool = _priority_of(mix, String(a["id"]))
	var pb: bool = _priority_of(mix, String(b["id"]))
	if pa != pb:
		return pa
	return _rank_before(a, b, seed_val, w)


# True when placement a outranks b: the lower hash rank wins, a tie goes to the earlier tile.
static func _rank_before(a: Dictionary, b: Dictionary, seed_val: int, w: int) -> bool:
	var ra: int = Dressing.hash_at(seed_val, int(a["tx"]), int(a["ty"]), SALT_RANK)
	var rb: int = Dressing.hash_at(seed_val, int(b["tx"]), int(b["ty"]), SALT_RANK)
	if ra != rb:
		return ra < rb
	return _tile_index(a, w) < _tile_index(b, w)


static func _tile_index(p: Dictionary, w: int) -> int:
	return int(p["ty"]) * w + int(p["tx"])


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


static func _place_on_tile(map: Variant, seed_val: int, tx: int, ty: int, by_kind: Dictionary, mix: Dictionary = {}) -> Dictionary:
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
			# A run piece taller than the Low band would be a tall prop on a Low tile: not a candidate here.
			for e in (by_kind["run"] as Array):
				if size_of(e as Dictionary).y <= LOW_BAND_M:
					candidates.append(e)
	elif key == "door.open":
		for e in (by_kind["door_head"] as Array):
			candidates.append(e)
	if candidates.is_empty():
		return {}
	var pick: int = choice_index(seed_val, tx, ty, candidates, mix)
	if pick < 0:
		return {}
	var entry2: Dictionary = candidates[pick] as Dictionary
	return _pose(map, entry2, tx, ty, key, walls)


# Which candidate a tile takes: the high bits of the choice hash (the low bits move with the density pick and never
# reach the odd candidates' even partners: measured, see the REPORT), weighted by the mix. -1 when none.
static func choice_index(seed_val: int, tx: int, ty: int, candidates: Array, mix: Dictionary = {}) -> int:
	if candidates.is_empty():
		return -1
	var total: int = 0
	var weights: Array = []
	for c in candidates:
		var wt: int = _weight_of(mix, String((c as Dictionary).get("id", "")))
		weights.append(wt)
		total += wt
	if total <= 0:
		return -1
	var point: int = _choice_word(seed_val, tx, ty) % total
	var acc: int = 0
	for i in range(weights.size()):
		acc += int(weights[i])
		if point < acc:
			return i
	return weights.size() - 1


# The choice over a plain count (every weight 1): the same high-bit pick, for a gate that judges all indices.
static func choice_of_count(seed_val: int, tx: int, ty: int, count: int) -> int:
	if count <= 0:
		return -1
	return _choice_word(seed_val, tx, ty) % count


# The word the choice reads: the high bits of the choice hash, or (the plant) its low bits.
static func _choice_word(seed_val: int, tx: int, ty: int) -> int:
	var h: int = Dressing.hash_at(seed_val, tx, ty, SALT_CHOICE)
	return h if CHOICE_LOW_BITS else (h >> 16)


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
		"glb": String(entry.get("glb", "")),
		"origin": String(entry.get("origin", "floor_centre")),
		"wall_dir": Vector2(float(walls[0].x), float(walls[0].y)) if not walls.is_empty() else Vector2.ZERO,
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
# Spans join consecutive poles on one row (same tile y), three matched wires per pair: a to a, b to b, c to c. A pair
# farther than WIRE_MAX_SPAN_M or nearer than WIRE_MIN_SPAN_M draws none; a span over a Wall tile of `map` is dropped.
static func wire_spans(poles_all: Array, map: Variant = null) -> Array:
	var poles: Array = []
	for p in poles_all:
		if _is_pole(p as Dictionary):
			poles.append(p)
	var out: Array = []
	var groups: Dictionary = {}
	for p in poles:
		var key: int = int((p as Dictionary)["ty"])
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(p)
	for key in groups.keys():
		var line: Array = groups[key] as Array
		line.sort_custom(func(a, b): return _along(a as Dictionary, 1) < _along(b as Dictionary, 1))
		for i in range(line.size() - 1):
			var pa: Dictionary = line[i] as Dictionary
			var pb: Dictionary = line[i + 1] as Dictionary
			var gap: float = anchor_world(pa, "wire_a").distance_to(anchor_world(pb, "wire_b"))
			if gap > WIRE_MAX_SPAN_M or gap < WIRE_MIN_SPAN_M:
				continue
			for k in WIRE_KEYS:
				var a: Vector3 = anchor_world(pa, k)
				var b: Vector3 = anchor_world(pb, k)
				if map != null and not PLANT_NO_WIRE_BUILDING_CHECK and _crosses_wall(map, a, b):
					continue
				out.append({"a": a, "b": b, "points": _catenary(a, b), "key": k})
	return out


# True when the segment a to b (Godot x and z are the sim's x and y) passes over a Wall tile of the map.
static func _crosses_wall(map: Variant, a: Vector3, b: Vector3) -> bool:
	for i in range(WIRE_SEGMENTS + 1):
		var t: float = float(i) / float(WIRE_SEGMENTS)
		var p: Vector3 = a.lerp(b, t)
		if int(SimTileMap.tile_at(map, int(floor(p.x)), int(floor(p.z)))) == SimTileMap.Tile.Wall:
			return true
	return false


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
