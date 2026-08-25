extends SceneTree
# Building templates as content: the annex becomes the first one.
#
# docs/24's "authored templates, procedurally assembled" starts here. `SimTemplates.stamp` is
# `apply_patch` with the origin handed in rather than read out of the entry, plus the thing a blit
# could never do: carrying the template's own relative anchors onto the map, so where the colony
# stands becomes data instead of `SimDirector.ANNEX` / `SimFortify.GATE_A` / the literal (46, 45).
#
# What this holds down:
#
#  1. **A template is well formed all the way down.** content_validator.gd is shallow -- it checks
#     top-level property types and rejects unexpected top-level keys, and does not recurse. So
#     nothing inside `doors`, `anchors` or the three arrays is schema-enforced at load, and none of
#     "the shell is closed", "the door is on the perimeter", "indoors stops at the walls" or "every
#     room is reachable from a door" is expressible in a schema at all. The checks below are that
#     enforcement, and they run twice: over inline fixtures, which can be broken on purpose, and
#     over **every shipped `content/buildings/` entry**, which the placer now draws from.
#  1b. **And the pool is reachable.** Every shipped template's tags appear in some district's pool,
#     and every shipped template is actually placed by one of the two live districts on the
#     canonical seed. A footprint nobody can roll is the dead-socket pattern in content form --
#     `check_m2_attach.gd`'s "is this findable in any loot table" is the same lane for items.
#  2. **The migration lock.** The new stamp must lay the civic annex byte-for-byte where the old
#     blit did, on the canonical seed, at both the gate size and the shipped size. This is what
#     lets the old path be deleted in a later slice without re-measuring every band pinned to the
#     shipped layout.
#  3. **The anchors are written, absolute, and correct.** Every anchor lands at the sited annex's
#     origin plus the template's own relative point -- checked against where the generator actually
#     put the colony rather than against a constant, because there is no constant any more: the
#     annex is sited per seed inside `SimWorldgen.generate` and `SimBoot.ANNEX_ORIGIN` is gone.
#     The canonical seed's site is pinned as a *measurement* so drift is still caught.
#  4. **Something reads them.** `SimBoot.colony_start` is the anchor's first live reader; the map
#     the player actually boots onto has to place them at the anchor tile, and the reader has to
#     follow the anchor when the anchor moves. A mechanism nothing reads is the defect this
#     milestone has now paid for nine times.
#
# Every assertion carries a true negative. A gate that cannot fail is worse than no gate.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimTemplates = preload("res://sim/map/templates.gd")
const SimWorldgen = preload("res://sim/map/worldgen.gd")
const SimBoot = preload("res://sim/boot.gd")
const ContentLoader = preload("res://platform/content_loader.gd")

const SEED: int = 20260805
const GATE_SIZE: int = 64
const SHIPPED_SIZE: int = 256
# The migration lock's origin, and nothing else's: it is where the retired blit put the annex, so
# it is the origin both paths are asked to lay identical bytes at. It is deliberately NOT where the
# generator sites the colony -- (38, 38) is outside the legal band at 64 -- which is what keeps
# `_blit_confined` in check_m2_district.gd honest as well.
const ORIGIN: Vector2i = Vector2i(38, 38)

# Where the generator sites the colony on the canonical seed. **Measured, not chosen**: run once and
# written down, so a change to the scorer, the margin or the street pass has to come here and say so
# rather than moving the shipped layout in silence. Everything else about the anchors is asserted
# against `annex_rect(map)` plus the template's own relative points, which is the identity that
# holds on every seed.
const SITED_64 := Rect2i(21, 13, 26, 26)
const SITED_256 := Rect2i(108, 107, 26, 26)
# Derived from SITED_64 and the template's relative anchors -- gate_a (12, 19), gate_b (13, 19),
# player_start (8, 7), well (13, 21) -- and written out so a wrong one reads as a wrong tile rather
# than as arithmetic that agrees with itself.
const WANT_GATE_A: Vector2i = Vector2i(33, 32)
const WANT_GATE_B: Vector2i = Vector2i(34, 32)
const WANT_START: Vector2i = Vector2i(29, 20)
const WANT_WELL: Vector2i = Vector2i(34, 34)
# The literal `SimBoot.colony_start` falls back to when a map carries no anchors at all.
const FALLBACK_START: Vector2i = Vector2i(46, 45)
# Too small to hold the annex and its clear ring, so the generator sites no colony: this is what an
# anchorless district is now, and the two isolation boots in check_m2_district.gd run at it.
const ANCHORLESS_SIZE: int = 32


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _a_sound_template_passes_every_structural_check_and_a_broken_one_does_not() and ok
	ok = _every_shipped_template_is_sound_and_reachable() and ok
	ok = _the_stamp_lays_the_annex_exactly_where_the_blit_did() and ok
	ok = _the_stamp_writes_the_anchors_the_constants_name() and ok
	ok = _boot_reads_the_start_anchor_rather_than_the_literal() and ok
	if ok:
		print("BUILDINGS_OK shipped pool and fixtures judged structurally, every template placeable, stamp byte-identical to the blit at 64 and 256, anchors written absolute, boot reads them")
		quit(0)
	else:
		push_error("BUILDINGS_FAIL")
		quit(1)


# --- fixtures ------------------------------------------------------------------------------

# An 8x6 shell: walled perimeter, one door on the south wall, indoors stopping at the walls, and
# two anchors standing on open tiles. Inline rather than shipped, because nothing places a
# building pool yet.
func _sound_fixture() -> Dictionary:
	var w: int = 8
	var h: int = 6
	var tiles: Array = []
	var surfaces: Array = []
	var indoors: Array = []
	for y in h:
		for x in w:
			var edge: bool = x == 0 or y == 0 or x == w - 1 or y == h - 1
			tiles.append(SimTileMap.Tile.Wall if edge else SimTileMap.Tile.Floor)
			surfaces.append(SimTileMap.SURFACE_PAVED)
			indoors.append(0 if edge else 1)
	tiles[5 * w + 3] = SimTileMap.Tile.Floor
	return {
		"id": "building.fixture.sound",
		"name": "eight by six with a south door",
		"size": {"w": w, "h": h},
		"tiles": tiles,
		"surfaces": surfaces,
		"indoors": indoors,
		"doors": [{"x": 3, "y": 5}],
		"tags": ["fixture"],
		"weight": 1,
		"anchors": {"player_start": {"x": 3, "y": 3}, "gate_a": {"x": 3, "y": 5}},
	}


# --- structural checks ---------------------------------------------------------------------

# Everything the schema cannot reach. Returns the problems by name, so the broken fixtures below
# can assert *which* failure they provoked rather than merely that something failed.
func _structural_problems(t: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var size: Variant = t.get("size")
	if not (size is Dictionary):
		out.append("size: missing")
		return out
	var w: int = int((size as Dictionary).get("w", 0))
	var h: int = int((size as Dictionary).get("h", 0))
	if w < 3 or h < 3:
		out.append("size: %dx%d is smaller than a shell with an interior" % [w, h])
		return out

	var arrays: Dictionary = {"tiles": 5, "surfaces": 4, "indoors": 1}
	for field in arrays.keys():
		var arr: Variant = t.get(String(field))
		if not (arr is Array):
			out.append("%s: missing" % String(field))
			continue
		var a: Array = arr as Array
		if a.size() != w * h:
			out.append("%s: length %d != w*h %d" % [String(field), a.size(), w * h])
			continue
		var top: int = int(arrays[field])
		for i in a.size():
			var v: int = int(a[i])
			if v < 0 or v > top:
				out.append("%s[%d]: %d is outside 0..%d" % [String(field), i, v, top])
	if not out.is_empty():
		return out

	var tiles: Array = t["tiles"] as Array
	var indoors: Array = t["indoors"] as Array
	var doors: Variant = t.get("doors")
	if not (doors is Array) or (doors as Array).is_empty():
		out.append("doors: a sealed footprint is a wall, not a building")
		return out

	var is_door: Dictionary = {}
	for entry in doors as Array:
		if not (entry is Dictionary):
			out.append("doors: a non-object entry")
			continue
		var d: Dictionary = entry as Dictionary
		var dx: int = int(d.get("x", -1))
		var dy: int = int(d.get("y", -1))
		if dx < 0 or dy < 0 or dx >= w or dy >= h:
			out.append("doors: (%d, %d) is outside the footprint" % [dx, dy])
			continue
		if not (dx == 0 or dy == 0 or dx == w - 1 or dy == h - 1):
			out.append("doors: (%d, %d) is not on the perimeter" % [dx, dy])
			continue
		if SimTileMap.SOLID[int(tiles[dy * w + dx])]:
			out.append("doors: (%d, %d) is tile %d, which nobody can walk through" % [dx, dy, int(tiles[dy * w + dx])])
			continue
		is_door["%d,%d" % [dx, dy]] = true

	for y in h:
		for x in w:
			var edge: bool = x == 0 or y == 0 or x == w - 1 or y == h - 1
			var idx: int = y * w + x
			if edge:
				if not is_door.has("%d,%d" % [x, y]) and not SimTileMap.SOLID[int(tiles[idx])]:
					out.append("perimeter: (%d, %d) is open but is not a door" % [x, y])
				if int(indoors[idx]) != 0:
					out.append("indoors: (%d, %d) is flagged indoors outside the shell" % [x, y])
			else:
				if int(indoors[idx]) != 1:
					out.append("indoors: interior (%d, %d) is not flagged indoors" % [x, y])

	# Every room reachable from a door, which is the sandbox goal at template scale: a partition
	# with no doorway in it is a sealed room, and a door that opens onto a partition wall is a
	# door onto nothing. Neither is expressible in a schema, and both look fine tile by tile.
	var inside: Array[int] = []
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if not SimTileMap.SOLID[int(tiles[y * w + x])]:
				inside.append(y * w + x)
	if inside.is_empty():
		out.append("interior: no walkable tile inside the shell")
		return out
	var seen: Dictionary = {int(inside[0]): true}
	var queue: Array[int] = [int(inside[0])]
	while not queue.is_empty():
		var at: int = int(queue.pop_back())
		for step in [1, -1, w, -w]:
			var next: int = at + int(step)
			var nx: int = next % w
			var ny: int = next / w
			if nx < 1 or ny < 1 or nx >= w - 1 or ny >= h - 1:
				continue
			if absi(nx - (at % w)) + absi(ny - (at / w)) != 1:
				continue
			if seen.has(next) or SimTileMap.SOLID[int(tiles[next])]:
				continue
			seen[next] = true
			queue.append(next)
	if seen.size() != inside.size():
		out.append("interior: %d of %d walkable tiles are sealed off from the rest" % [inside.size() - seen.size(), inside.size()])
	for key in is_door.keys():
		var parts: PackedStringArray = String(key).split(",")
		var dx2: int = int(parts[0])
		var dy2: int = int(parts[1])
		var opens: bool = false
		for step2 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx2: int = dx2 + (step2 as Vector2i).x
			var ny2: int = dy2 + (step2 as Vector2i).y
			if nx2 < 0 or ny2 < 0 or nx2 >= w or ny2 >= h:
				continue
			if seen.has(ny2 * w + nx2):
				opens = true
		if not opens:
			out.append("doors: (%d, %d) opens onto no interior tile" % [dx2, dy2])

	var anchors: Variant = t.get("anchors")
	if anchors is Dictionary:
		for key in (anchors as Dictionary).keys():
			var point: Variant = (anchors as Dictionary)[key]
			if not (point is Dictionary):
				out.append("anchors.%s: not a point" % String(key))
				continue
			var ax: int = int((point as Dictionary).get("x", -1))
			var ay: int = int((point as Dictionary).get("y", -1))
			if ax < 0 or ay < 0 or ax >= w or ay >= h:
				out.append("anchors.%s: (%d, %d) is outside the footprint" % [String(key), ax, ay])
				continue
			if SimTileMap.SOLID[int(tiles[ay * w + ax])]:
				out.append("anchors.%s: (%d, %d) stands in tile %d, which is solid" % [String(key), ax, ay, int(tiles[ay * w + ax])])
	return out


func _a_sound_template_passes_every_structural_check_and_a_broken_one_does_not() -> bool:
	var sound: Dictionary = _sound_fixture()
	var clean: Array[String] = _structural_problems(sound)
	if not clean.is_empty():
		for p in clean:
			push_error("the sound fixture was rejected: %s" % p)
		return false

	# The true negatives, one per family of failure, each derived from the sound fixture so the
	# only difference is the break itself.
	var short: Dictionary = sound.duplicate(true)
	var trimmed: Array = (short["tiles"] as Array).duplicate()
	trimmed.resize(trimmed.size() - 1)
	short["tiles"] = trimmed

	var inside: Dictionary = sound.duplicate(true)
	var sealed: Array = (inside["tiles"] as Array).duplicate()
	sealed[5 * 8 + 3] = SimTileMap.Tile.Wall
	inside["tiles"] = sealed
	inside["doors"] = [{"x": 3, "y": 3}]
	(inside["anchors"] as Dictionary).erase("gate_a")

	var leaking: Dictionary = sound.duplicate(true)
	var flags: Array = (leaking["indoors"] as Array).duplicate()
	flags[0] = 1
	leaking["indoors"] = flags

	# A partition straight across the shell, with no doorway in it: two rooms, one of them
	# unreachable from the only door. The failure the pool's own interiors have to avoid.
	var sealed_room: Dictionary = sound.duplicate(true)
	var partition: Array = (sealed_room["tiles"] as Array).duplicate()
	for x in range(1, 7):
		partition[3 * 8 + x] = SimTileMap.Tile.Wall
	sealed_room["tiles"] = partition

	var cases: Array[Dictionary] = [
		{"name": "a short tiles array", "template": short, "says": "tiles: length"},
		{"name": "a door in the middle of the room", "template": inside, "says": "is not on the perimeter"},
		{"name": "indoors leaking past the wall", "template": leaking, "says": "flagged indoors outside the shell"},
		{"name": "a partition with no doorway", "template": sealed_room, "says": "sealed off from the rest"},
	]
	for c in cases:
		var problems: Array[String] = _structural_problems(c["template"] as Dictionary)
		var matched: bool = false
		for p in problems:
			if p.find(String(c["says"])) >= 0:
				matched = true
		if not matched:
			push_error("%s was not reported as \"%s\": %s" % [String(c["name"]), String(c["says"]), str(problems)])
			return false

	print("TEMPLATE SHAPE OK a sound 8x6 fixture is clean, and %d broken ones each report their own failure" % cases.size())
	return true


# --- the shipped pool -------------------------------------------------------------------------

# The lane that used to say "no `content/buildings/` entry ships yet". They ship now, with the
# placer that draws them, so this walks them: the same structural checks the fixtures get, then
# the two questions a schema cannot ask -- is every tag in some district's pool, and does either
# live district actually put every one of these on the ground.
func _every_shipped_template_is_sound_and_reachable() -> bool:
	var tree: Dictionary = ContentLoader.load_tree()
	var templates: Array = SimWorldgen.templates_of(tree)
	if templates.size() < 8:
		push_error("only %d building templates ship -- the pool is too thin to judge" % templates.size())
		return false

	var problems: Array[String] = []
	var by_id: Dictionary = {}
	for t in templates:
		var entry: Dictionary = t as Dictionary
		var id: String = String(entry.get("id", ""))
		if by_id.has(id):
			problems.append("%s: shipped twice" % id)
		by_id[id] = true
		for p in _structural_problems(entry):
			problems.append("%s: %s" % [id, p])
	if not problems.is_empty():
		for p in problems:
			push_error(p)
		return false

	# Findability, half one: a tag no district pool names is a template nothing can draw.
	var pooled: Dictionary = {}
	var districts: Array[String] = []
	for path in tree.keys():
		if not String(path).begins_with("districts/"):
			continue
		var district: Dictionary = tree[path] as Dictionary
		districts.append(String(district.get("id", "")))
		for entry in district.get("pool", []) as Array:
			pooled[String((entry as Dictionary).get("tag", ""))] = true
	if districts.is_empty():
		push_error("no district ships, so no pool can name these tags")
		return false
	var orphans: Array[String] = []
	for t in templates:
		var named: bool = false
		for tag in (t as Dictionary).get("tags", []) as Array:
			if pooled.has(String(tag)):
				named = true
		if not named:
			orphans.append(String((t as Dictionary).get("id", "")))
	if not orphans.is_empty():
		push_error("shipped but in no district's pool, so unplaceable: %s" % str(orphans))
		return false

	# Findability, half two, and the half that can actually fail: the pool is only real if the
	# placer reaches it. Both live districts at the shipped size, one seed, and every template has
	# to turn up somewhere. A footprint that fits no lot the generator makes would pass every
	# check above and never once be built.
	var seen: Dictionary = {}
	districts.sort()
	for id in districts:
		var map: Variant = SimWorldgen.generate(SEED, SHIPPED_SIZE, tree, String(id))
		for record in map.buildings as Array:
			seen[String((record as Dictionary)["id"])] = int(seen.get(String((record as Dictionary)["id"]), 0)) + 1
	var never: Array[String] = []
	for t in templates:
		if not seen.has(String((t as Dictionary).get("id", ""))):
			never.append(String((t as Dictionary).get("id", "")))
	if not never.is_empty():
		push_error("never placed by any live district at %d on seed %d, so the entry is decoration: %s" % [SHIPPED_SIZE, SEED, str(never)])
		return false

	print("SHIPPED POOL OK %d templates, all structurally sound, every tag pooled, every one placed across %s" % [
		templates.size(), str(districts),
	])
	return true


# --- the migration lock ---------------------------------------------------------------------

func _annex_patch() -> Variant:
	return SimTileMap.load_patch_from_content(ContentLoader.load_tree(), SimWorldgen.ANNEX_PATCH_ID)


func _first_difference(a: PackedByteArray, b: PackedByteArray) -> int:
	if a.size() != b.size():
		return 0
	for i in a.size():
		if a[i] != b[i]:
			return i
	return -1


# The whole point of the slice: the stamp is the blit, at the same origin, to the byte. Until this
# holds, deleting `apply_patch` would move the shipped layout and silently invalidate every band
# measured against it.
func _the_stamp_lays_the_annex_exactly_where_the_blit_did() -> bool:
	var patch: Variant = _annex_patch()
	if not (patch is Dictionary):
		push_error("no %s in content, so this lock is asserting nothing" % SimWorldgen.ANNEX_PATCH_ID)
		return false

	for size in [GATE_SIZE, SHIPPED_SIZE]:
		var blitted: Variant = SimTileMap.generate_district(SEED, int(size))
		SimTileMap.apply_patch(blitted, patch as Dictionary)
		var stamped: Variant = SimTileMap.generate_district(SEED, int(size))
		var landed: Dictionary = SimTemplates.stamp(stamped, patch as Dictionary, ORIGIN.x, ORIGIN.y)
		var rect: Dictionary = landed["rect"] as Dictionary
		if int(rect["x"]) != ORIGIN.x or int(rect["y"]) != ORIGIN.y or int(rect["w"]) != SITED_64.size.x or int(rect["h"]) != SITED_64.size.y:
			push_error("the stamp reported landing at %s" % str(rect))
			return false
		for field in ["tiles", "surfaces", "indoors"]:
			var before: PackedByteArray = blitted.get(String(field)) as PackedByteArray
			var after: PackedByteArray = stamped.get(String(field)) as PackedByteArray
			var at: int = _first_difference(before, after)
			if at >= 0:
				push_error("at size %d the stamped %s differs from the blitted one at index %d (%d vs %d)" % [
					int(size), String(field), at, int(before[at]), int(after[at]),
				])
				return false

	# The true negative, and the reason this lock can fail: the same comparison against the same
	# template stamped one tile east must find a difference. Without it, an equality that had
	# stopped comparing anything would read as a pass.
	var blitted_64: Variant = SimTileMap.generate_district(SEED, GATE_SIZE)
	SimTileMap.apply_patch(blitted_64, patch as Dictionary)
	var shifted: Variant = SimTileMap.generate_district(SEED, GATE_SIZE)
	SimTemplates.stamp(shifted, patch as Dictionary, ORIGIN.x + 1, ORIGIN.y)
	if _first_difference(blitted_64.tiles as PackedByteArray, shifted.tiles as PackedByteArray) < 0:
		push_error("the annex stamped one tile east produced identical tiles -- the comparison is not comparing")
		return false

	print("MIGRATION LOCK OK stamp == blit across tiles, surfaces and indoors at %d and %d; one tile east differs" % [GATE_SIZE, SHIPPED_SIZE])
	return true


# --- the anchors -----------------------------------------------------------------------------

func _the_stamp_writes_the_anchors_the_constants_name() -> bool:
	var boot: Dictionary = SimBoot.bare(SEED, GATE_SIZE)
	var map: Variant = boot["map"]
	if not (map.anchors is Dictionary) or (map.anchors as Dictionary).is_empty():
		push_error("a booted district carries no anchors at all")
		return false

	# The identity that holds on every seed: each anchor is the sited annex's own corner plus the
	# template's relative point. Asserted before the canonical pin below, because this is the thing
	# that has to be true and the pin is only how drift gets noticed.
	var sited: Rect2i = SimTileMap.annex_rect(map)
	var relative: Dictionary = (_annex_patch() as Dictionary)["anchors"] as Dictionary
	var got: Dictionary = {
		"gate_a": SimTileMap.gate_a(map),
		"gate_b": SimTileMap.gate_b(map),
		"player_start": SimTileMap.player_start(map),
		"well": SimTileMap.well_tile(map),
	}
	for key in ["gate_a", "gate_b", "player_start", "well"]:
		var point: Dictionary = relative[String(key)] as Dictionary
		var here: Vector2i = got[String(key)] as Vector2i
		var want_here := Vector2i(sited.position.x + int(point["x"]), sited.position.y + int(point["y"]))
		if here != want_here:
			push_error("anchor %s landed at %s; the annex is sited at %s and the template puts it at %s, so %s" % [
				String(key), str(here), str(sited.position), str(point), str(want_here),
			])
			return false
		if here.x < 0 or here.y < 0 or here.x >= int(map.w) or here.y >= int(map.h):
			push_error("anchor %s at %s is off the map" % [String(key), str(here)])
			return false
		if not sited.has_point(here):
			push_error("anchor %s at %s is outside the annex it belongs to, %s" % [String(key), str(here), str(sited)])
			return false

	# The measurement. Where seed 20260805 puts the colony is a fact about the generator, and every
	# band in this repo that boots that seed is measured on this layout -- so it is written down,
	# and moving it is an edit here.
	if sited != SITED_64:
		push_error("seed %d sites the annex at %s, and the measured canonical site is %s" % [SEED, str(sited), str(SITED_64)])
		return false
	var want: Dictionary = {
		"gate_a": WANT_GATE_A,
		"gate_b": WANT_GATE_B,
		"player_start": WANT_START,
		"well": WANT_WELL,
	}
	for key2 in want.keys():
		if (got[key2] as Vector2i) != (want[key2] as Vector2i):
			push_error("anchor %s landed at %s, and the measured canonical tile is %s" % [String(key2), str(got[key2]), str(want[key2])])
			return false
	var shipped: Rect2i = SimTileMap.annex_rect(SimBoot.bare(SEED, SHIPPED_SIZE)["map"])
	if shipped != SITED_256:
		push_error("seed %d at %d sites the annex at %s, and the measured canonical site is %s" % [SEED, SHIPPED_SIZE, str(shipped), str(SITED_256)])
		return false
	# Standing room, not just coordinates: a start or a well inside masonry is a start nobody can
	# stand on and a well nobody can draw from.
	for key in ["player_start", "well"]:
		var tile: Vector2i = got[key] as Vector2i
		if SimTileMap.is_solid(map, tile.x, tile.y):
			push_error("anchor %s at %s stands in something solid" % [String(key), str(tile)])
			return false

	# What the stamp hands back is what it wrote, so a placer that chose the origin never has to
	# recompute the anchors it just caused.
	var fresh: Variant = SimTileMap.generate_district(SEED, GATE_SIZE)
	var reported: Dictionary = SimTemplates.stamp(fresh, _annex_patch() as Dictionary, ORIGIN.x, ORIGIN.y)["anchors"] as Dictionary
	for key in reported.keys():
		if str(reported[key]) != str((fresh.anchors as Dictionary).get(key)):
			push_error("the stamp reported %s for %s but the map carries %s" % [str(reported[key]), String(key), str((fresh.anchors as Dictionary).get(key))])
			return false
	if not reported.has("annex") or reported.size() != (fresh.anchors as Dictionary).size():
		push_error("the stamp reported %d anchors (%s) against the map's %d" % [reported.size(), str(reported.keys()), (fresh.anchors as Dictionary).size()])
		return false

	# The true negative: a template with no anchors block claims nothing. An ordinary house must
	# not rename where the colony is, and a map with no colony on it must report absence rather than
	# a coordinate. The base map is ANCHORLESS_SIZE rather than the gate size because the generator
	# sites a colony on anything big enough to hold one -- at 64 the map arrives with anchors
	# already on it, and stamping an anonymous template over that would prove nothing.
	var anonymous: Dictionary = (_annex_patch() as Dictionary).duplicate(true)
	anonymous.erase("anchors")
	var plain: Variant = SimTileMap.generate_district(SEED, ANCHORLESS_SIZE)
	if not (plain.anchors as Dictionary).is_empty():
		push_error("a district at %d, too small to site the annex, still carries %s" % [ANCHORLESS_SIZE, str(plain.anchors)])
		return false
	var wrote: Dictionary = SimTemplates.stamp(plain, anonymous, 2, 2)["anchors"] as Dictionary
	if not wrote.is_empty():
		push_error("a template with no anchors block still wrote %s" % str(wrote))
		return false
	if not (plain.anchors as Dictionary).is_empty():
		push_error("a map stamped with an anchorless template carries %s" % str(plain.anchors))
		return false
	var blank: Variant = SimTileMap.blank_map(16, 16)
	for probe in [plain, blank]:
		if SimTileMap.gate_a(probe) != Vector2i(-1, -1) or SimTileMap.player_start(probe) != Vector2i(-1, -1):
			push_error("an anchorless map answered with a coordinate instead of the absent sentinel")
			return false
		if SimTileMap.annex_rect(probe) != Rect2i(0, 0, 0, 0):
			push_error("an anchorless map claimed an annex rect of %s" % str(SimTileMap.annex_rect(probe)))
			return false

	print("ANCHORS OK the sited annex %s carries gate_a %s, gate_b %s, start %s, well %s -- each its own corner plus the template's relative point, and %s at %d; an anchorless template writes none" % [
		str(SITED_64), str(WANT_GATE_A), str(WANT_GATE_B), str(WANT_START), str(WANT_WELL), str(SITED_256), SHIPPED_SIZE,
	])
	return true


# --- the reader lane --------------------------------------------------------------------------

# The dead-socket rule: anchors that nothing reads would be the tenth. `SimBoot.colony_start` is
# the first reader, and this asserts both halves -- the booted player stands on the anchor tile,
# and the reader follows the anchor when the anchor moves rather than answering a literal from
# memory. That second half is not hypothetical any more: the anchor moves per seed now, so the
# reader following it is what the game does every boot rather than what a fixture arranges.
func _boot_reads_the_start_anchor_rather_than_the_literal() -> bool:
	var boot: Dictionary = SimBoot.playable(SEED, GATE_SIZE)
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	var at: Dictionary = world.components.get_component(world.player, "position") as Dictionary
	var stood: Vector2i = Vector2i(floori(float(at["x"])), floori(float(at["y"])))
	var anchor: Vector2i = SimTileMap.player_start(map)
	if stood != anchor:
		push_error("the player booted onto %s while the start anchor is at %s" % [str(stood), str(anchor)])
		return false
	if stood != WANT_START:
		push_error("the player booted onto %s, not the canonical %s" % [str(stood), str(WANT_START)])
		return false

	# The anchor moves and the reader moves with it. This is the half that separates "reads the
	# anchor" from "returns the same literal the anchor happens to equal".
	var patch: Variant = _annex_patch()
	var elsewhere := Vector2i(20, 20)
	var moved: Variant = SimTileMap.generate_district(SEED, GATE_SIZE)
	SimTemplates.stamp(moved, patch as Dictionary, elsewhere.x, elsewhere.y)
	var relative: Dictionary = ((patch as Dictionary)["anchors"] as Dictionary)["player_start"] as Dictionary
	var want_moved := Vector2i(elsewhere.x + int(relative["x"]), elsewhere.y + int(relative["y"]))
	if SimTileMap.player_start(moved) != want_moved:
		push_error("stamped at %s the start anchor read %s, not %s" % [str(elsewhere), str(SimTileMap.player_start(moved)), str(want_moved)])
		return false
	if SimBoot.colony_start(moved) != want_moved:
		push_error("the reader answered %s for a colony anchored at %s" % [str(SimBoot.colony_start(moved)), str(want_moved)])
		return false

	# And the fallback is reachable rather than theoretical: a district too small to site the annex
	# carries no anchor, so the reader returns the literal that is still there for exactly that case.
	# This is the shape the two isolation boots run at.
	var unsited: Variant = SimTileMap.generate_district(SEED, ANCHORLESS_SIZE)
	if SimTileMap.player_start(unsited) != Vector2i(-1, -1):
		push_error("a district at %d, too small for a colony, reported a start anchor" % ANCHORLESS_SIZE)
		return false
	if SimBoot.colony_start(unsited) != FALLBACK_START:
		push_error("the fallback answered %s instead of %s" % [str(SimBoot.colony_start(unsited)), str(FALLBACK_START)])
		return false

	print("READER OK the player boots onto the anchor at %s, the reader follows it to %s when the template moves, and falls back to %s on a district too small to site one" % [
		str(stood), str(want_moved), str(FALLBACK_START),
	])
	return true
