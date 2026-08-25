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
#     "the shell is closed", "the door is on the perimeter" or "indoors stops at the walls" is
#     expressible in a schema at all. The checks below are that enforcement, run against inline
#     fixtures: **no `content/buildings/` entry ships yet.** The pool and the placer that reads it
#     arrive in the "district types as data" slice, and content nothing reads is the dead-socket
#     pattern in content form -- so this lane judges fixtures until there is a pool to walk.
#  2. **The migration lock.** The new stamp must lay the civic annex byte-for-byte where the old
#     blit did, on the canonical seed, at both the gate size and the shipped size. This is what
#     lets the old path be deleted in a later slice without re-measuring every band pinned to the
#     shipped layout.
#  3. **The anchors are written, absolute, and correct.** The four points the constants name, plus
#     the annex rect, land where the constants say -- which is what makes deleting the constants a
#     later slice's edit rather than a re-balance.
#  4. **Something reads them.** `SimBoot.colony_start` is the anchor's first live reader; the map
#     the player actually boots onto has to place them at the anchor tile, and the reader has to
#     follow the anchor when the anchor moves. A mechanism nothing reads is the defect this
#     milestone has now paid for nine times.
#
# Every assertion carries a true negative. A gate that cannot fail is worse than no gate.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimTemplates = preload("res://sim/map/templates.gd")
const SimBoot = preload("res://sim/boot.gd")
const ContentLoader = preload("res://platform/content_loader.gd")

const SEED: int = 20260805
const GATE_SIZE: int = 64
const SHIPPED_SIZE: int = 256
const ORIGIN: Vector2i = Vector2i(38, 38)

# The coordinate identities the shipped constants assert, restated here as the target the stamped
# anchors have to hit. check_m2_district.gd pins the gate tiles the same way.
const WANT_GATE_A: Vector2i = Vector2i(50, 57)
const WANT_GATE_B: Vector2i = Vector2i(51, 57)
const WANT_START: Vector2i = Vector2i(46, 45)
const WANT_WELL: Vector2i = Vector2i(51, 59)
const WANT_ANNEX := Rect2i(38, 38, 26, 26)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _a_sound_template_passes_every_structural_check_and_a_broken_one_does_not() and ok
	ok = _the_stamp_lays_the_annex_exactly_where_the_blit_did() and ok
	ok = _the_stamp_writes_the_anchors_the_constants_name() and ok
	ok = _boot_reads_the_start_anchor_rather_than_the_literal() and ok
	if ok:
		print("BUILDINGS_OK fixtures judged structurally, stamp byte-identical to the blit at 64 and 256, anchors written absolute, boot reads them")
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

	var cases: Array[Dictionary] = [
		{"name": "a short tiles array", "template": short, "says": "tiles: length"},
		{"name": "a door in the middle of the room", "template": inside, "says": "is not on the perimeter"},
		{"name": "indoors leaking past the wall", "template": leaking, "says": "flagged indoors outside the shell"},
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


# --- the migration lock ---------------------------------------------------------------------

func _annex_patch() -> Variant:
	return SimTileMap.load_patch_from_content(ContentLoader.load_tree(), SimBoot.PATCH_ID)


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
		push_error("no %s in content, so this lock is asserting nothing" % SimBoot.PATCH_ID)
		return false

	for size in [GATE_SIZE, SHIPPED_SIZE]:
		var blitted: Variant = SimTileMap.generate_district(SEED, int(size))
		SimTileMap.apply_patch(blitted, patch as Dictionary)
		var stamped: Variant = SimTileMap.generate_district(SEED, int(size))
		var landed: Dictionary = SimTemplates.stamp(stamped, patch as Dictionary, ORIGIN.x, ORIGIN.y)
		var rect: Dictionary = landed["rect"] as Dictionary
		if int(rect["x"]) != ORIGIN.x or int(rect["y"]) != ORIGIN.y or int(rect["w"]) != WANT_ANNEX.size.x or int(rect["h"]) != WANT_ANNEX.size.y:
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

	var want: Dictionary = {
		"gate_a": WANT_GATE_A,
		"gate_b": WANT_GATE_B,
		"player_start": WANT_START,
		"well": WANT_WELL,
	}
	var got: Dictionary = {
		"gate_a": SimTileMap.gate_a(map),
		"gate_b": SimTileMap.gate_b(map),
		"player_start": SimTileMap.player_start(map),
		"well": SimTileMap.well_tile(map),
	}
	for key in want.keys():
		var here: Vector2i = got[key] as Vector2i
		if here != (want[key] as Vector2i):
			push_error("anchor %s landed at %s, not %s" % [String(key), str(here), str(want[key])])
			return false
		if here.x < 0 or here.y < 0 or here.x >= int(map.w) or here.y >= int(map.h):
			push_error("anchor %s at %s is off the map" % [String(key), str(here)])
			return false
	if SimTileMap.annex_rect(map) != WANT_ANNEX:
		push_error("the annex rect came back as %s, not %s" % [str(SimTileMap.annex_rect(map)), str(WANT_ANNEX)])
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
	# not rename where the colony is, and a bare map must report absence rather than a coordinate.
	var anonymous: Dictionary = (_annex_patch() as Dictionary).duplicate(true)
	anonymous.erase("anchors")
	var plain: Variant = SimTileMap.generate_district(SEED, GATE_SIZE)
	var wrote: Dictionary = SimTemplates.stamp(plain, anonymous, ORIGIN.x, ORIGIN.y)["anchors"] as Dictionary
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

	print("ANCHORS OK gate_a %s, gate_b %s, start %s, well %s, annex %s, all in bounds; an anchorless template writes none" % [
		str(WANT_GATE_A), str(WANT_GATE_B), str(WANT_START), str(WANT_WELL), str(WANT_ANNEX),
	])
	return true


# --- the reader lane --------------------------------------------------------------------------

# The dead-socket rule: anchors that nothing reads would be the tenth. `SimBoot.colony_start` is
# the first reader, and this asserts both halves -- the booted player stands on the anchor tile,
# and the reader follows the anchor when the anchor moves rather than answering (46, 45) from
# memory.
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

	# And the fallback is reachable rather than theoretical: a district nobody stamped has no
	# anchor, so the reader returns the literal that is still there for exactly that case.
	var unstamped: Variant = SimTileMap.generate_district(SEED, GATE_SIZE)
	if SimTileMap.player_start(unstamped) != Vector2i(-1, -1):
		push_error("an unstamped district reported a start anchor")
		return false
	if SimBoot.colony_start(unstamped) != WANT_START:
		push_error("the fallback answered %s instead of %s" % [str(SimBoot.colony_start(unstamped)), str(WANT_START)])
		return false

	print("READER OK the player boots onto the anchor at %s, the reader follows it to %s when the template moves, and falls back to %s on an unstamped district" % [
		str(stood), str(want_moved), str(WANT_START),
	])
	return true
