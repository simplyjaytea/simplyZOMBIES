extends SceneTree
# "Trees stand up" (docs/30's Dungeon Settlers look, decisions 9-10) and, since 2026-09-26,
# "Trees, the bed and the heaps" and "Nature extras" (docs/23's outpost group). A tree is a
# picture that stands in the entity sort, not a canopy over the tiles -- one tall feet-anchored
# picture per Tree tile, hung on the trunk's south-edge centre, y-sorted with the bodies and
# fading (never the body) while a Focal ground point falls inside it. The pictures are the outpost
# pack's pine, broadleaf and dead tree (authored.json, kind `tree`), whose canopies are wider than
# the trunk's tile -- the amendment to "one tile wide" docs/30's "The outpost pack, adopted"
# makes, and the reason the fade is the only answer to a hidden body. This gate holds the whole
# path against a hand-built fixture both ways, then proves the draw loop actually reaches every
# rule -- and holds the nature dressing, bushes and reeds and rocks and stumps and logs over
# open floor, to the standing rule that dressing is never sim state.
#
# Twelve lanes, every assertion with a true positive and a true negative, because a gate that
# cannot fail is worse than no gate:
#
#   KEYS         `trees.tall` names exactly the authored keys of kind `tree`, every one resolves
#                art at the canvas authored.json declares (`canvas_of`/`anchor_of` agree, Feet),
#                at least one canopy is wider than a tile, and tree_key covers all of them over a
#                scan -- refused for a fabricated key, an empty block, an empty list.
#   SORT         a hand list sorts body/tree/body by depth, exactly as _draw_entities' own
#                comparator does -- refused for a tree appended after the sort and for a sort on x.
#   RECT         body_rect on each tree's own canvas stands on the feet line at every zoom
#                rung, at that canvas's own width and height -- refused for a square canvas,
#                which centres instead.
#   ALPHA        tree_alpha fades only for a body point inside the tree's rect, never outside,
#                never for an empty list, and TREE_FADE_ALPHA itself sits strictly in (0, 1).
#   TILES        tree_tiles answers exactly the seen Tree tiles inside bounds against a hand map
#                -- a seen Floor tile, an unseen tree, a null observer and an out-of-bounds rect
#                all answer nothing; a seen-everything observer answers every tree.
#   FALLBACK     the draw loop actually reaches every rule above, in the order the plan named,
#                with the procedural fallback still standing beside it -- the needle scanner
#                proven on a fabricated body first, check_topdown.gd's convention.
#   SIM UNMOVED  Tile.Tree's opacity and solidity are untouched by this slice, and the pick stays a
#                pure hash: dressing.gd reaches for no RNG.
#   PLAYED       the shipped suburb: every Tree tile the loop would draw is a real Tree tile,
#                seen, and resolves a texture; a see-everything observer accounts for every one.
#   TIERS        the decoded pixels of the pictures, at a named alpha threshold, stand inside the
#                pack's tier -- box, sole row, tip, side margin, foot, pairwise distinct --
#                refused for a fully opaque canvas and for one lifted off the sole line.
#   NATURE       the nature list: every entry's key is an authored `prop` that resolves, its
#                surfaces are real, its rarity is at least two; the pick lands only on open outdoor
#                floor of the right surface with open floor either side, `beside` water needs a
#                water neighbour, and the seed and the tile reach the hash -- each refused on a
#                fabricated map; the roll is `hash_at`'s own number (the fast path's copy of the
#                arithmetic is held to a reference built from hash_at on every tile); nature_tiles
#                is a subset of seen; the chunk cache answers exactly what the uncached pick does,
#                serves what it holds and is emptied by everything its picks were made against;
#                the draw pass is reached in the order the plan named, and the shipped suburb
#                dresses at least two kinds.
#   SHIPPED      the nature dressing on the maps the game ships, judged where the fabricated maps
#                above cannot: reeds are placed on `district.forest_edge` (the one shipped district
#                that declares water, and a cell of `region.main_area`), every one beside a water
#                surface, and on the residential suburb never; the same forest with its water
#                turned to grass takes no reeds; and no shipped entry lies on paved ground or in
#                water -- each refused on a fabrication (a region that does not name the
#                district, an entry on a road, a dried forest). It is the lane that goes red when
#                content drops `beside` or dresses a road.
#   INERT        dressing is never sim state: nothing under godot/sim/ reads the presentation
#                layer or names a dressing key; a whole-district pick leaves the map's tiles,
#                surfaces, indoors and overlays byte-for-byte as they were; no picked tile is
#                solid, blocked or opaque; and no component of a booted world names a picture --
#                each detector proved on a fabrication (a picker that mutates the map, a component
#                carrying a picture key) before it is trusted on the real one.
#
# KEYS, TIERS, NATURE and PLAYED are the lanes that decode or resolve the pack pictures (the PNGs
# `tools/sprites/build.py` reproduces from `godot/art/simplyzombies/`); everything else is pure
# geometry, or textual against main.gd, and would stay green with the art deleted -- which is why
# KEYS names a missing file rather than skipping it.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimSurface = preload("res://sim/map/surface.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimWorldgen = preload("res://sim/map/worldgen.gd")
const World = preload("res://sim/world.gd")
const ContentLoader = preload("res://platform/content_loader.gd")
const Appearance = preload("res://presentation/appearance.gd")
const Dressing = preload("res://presentation/dressing.gd")
const TopDownProjection = preload("res://presentation/projection.gd")
const CameraUtil = preload("res://presentation/camera.gd")

const MAIN_GD: String = "res://presentation/main.gd"
const DRESSING_GD: String = "res://presentation/dressing.gd"
const AUTHORED_PATH: String = "res://assets/sprites/authored.json"
const SIM_DIR: String = "res://sim"
const CANON_SEED: int = 20260805
const GATE_SIZE: int = 64
const BUDGET_SECONDS: float = 60.0

# The alpha at which a pack pixel counts as drawn, as a byte -- authored.json's own ALPHA_SOLID and
# the pickup doc's named threshold. The pack leaves alpha <= 6 specks in some pictures, and a box
# taken at "alpha above zero" would be the whole canvas and an envelope that could never fail.
const ALPHA_SOLID: int = 128

var _stash: Dictionary = {}


# The whole interface tree_tiles asks an observer for: has_tile(tx, ty). A plain Dictionary of
# tiles rather than the real shadowcast index -- check_light_look.gd and check_roof_look.gd's
# FakeSeen convention, reused here for the same reason: a fixture that stands in for
# SimVisibility without booting one.
class FakeSeen extends RefCounted:
	var tiles: Dictionary = {}

	func has_tile(tx: int, ty: int) -> bool:
		return tiles.has(Vector2i(tx, ty))


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var started: int = Time.get_ticks_msec()
	var ok: bool = true
	ok = _the_keys_resolve_and_can_say_no() and ok
	ok = _the_sort_places_the_tree_by_depth() and ok
	ok = _the_rect_stands_on_its_feet_at_every_rung() and ok
	ok = _the_alpha_fades_only_the_tree() and ok
	ok = _the_tiles_lane_answers_only_seen_trees() and ok
	ok = _the_fallback_and_the_reach_hold_together() and ok
	ok = _the_sim_stayed_unmoved_and_the_pick_stays_a_hash() and ok
	ok = _the_shipped_suburb_stands_its_trees() and ok
	ok = _the_pictures_stand_inside_their_tier() and ok
	ok = _the_nature_dressing_lies_where_it_should() and ok
	ok = _the_shipped_maps_take_the_nature_they_should() and ok
	ok = _dressing_is_never_sim_state() and ok

	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	if seconds > BUDGET_SECONDS:
		push_error("check_trees ran %.1f s against a %.0f s budget" % [seconds, BUDGET_SECONDS])
		ok = false

	if ok:
		print(
			(
				"TREES_OK %d tree keys resolve at their authored canvases (widest canopy %d px, a tile is %d); the depth sort places body/tree/body; body_rect stands on the feet line at %d rungs; TREE_FADE_ALPHA %.2f fades only a point inside; TILES answered %d/%d seen trees on the hand map; the draw loop reaches every helper in order; Tile.Tree's opacity/solidity are unmoved and the pick stays a hash; suburb@%d stood %d of %d Tree tiles as drawable; the pictures stand inside their tier at alpha %d; NATURE dressed %d tiles of the suburb with %d kinds, all on open floor; SHIPPED placed %d reeds on forest_edge@%d, each beside water, none on the suburb or on the same map dried out; INERT: the map is byte-for-byte unmoved by a whole-district pick and no sim file or component names a picture; %.1f s of a %.0f s budget"
				% [
					int(_stash.get("tree_keys", 0)),
					int(_stash.get("widest", 0)),
					int(CameraUtil.ART_NATIVE),
					int(CameraUtil.ZOOM_STEPS.size()),
					Dressing.TREE_FADE_ALPHA,
					int(_stash.get("tiles_seen", 0)),
					int(_stash.get("tiles_total", 0)),
					GATE_SIZE,
					int(_stash.get("tree_seen", 0)),
					int(_stash.get("tree_total", 0)),
					ALPHA_SOLID,
					int(_stash.get("nature_tiles", 0)),
					int(_stash.get("nature_kinds", 0)),
					int(_stash.get("reeds", 0)),
					GATE_SIZE,
					seconds,
					BUDGET_SECONDS,
				]
			)
		)
		quit(0)
	else:
		push_error("TREES_FAIL")
		quit(1)


# --- fixtures ------------------------------------------------------------------------------


# A world with a full content tree and no district -- check_roof_look.gd's `_fixture()` shape --
# for resolving the dressing block without booting anything.
func _fixture() -> Dictionary:
	return {
		"seed": 77,
		"tick_hz": 20,
		"map": {"width": 12, "height": 10, "walls": []},
		"player": {"id": 0, "x": 6.0, "y": 5.0, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	}


# An 8x8 hand map with two Tree tiles, Floor everywhere else -- the TILES and PLAYED lanes'
# common ground for what a hand-built map with trees on it looks like.
func _tree_map() -> Variant:
	var map: Variant = SimTileMap.blank_map(8, 8)
	var w: int = int(map.w)
	map.tiles[2 * w + 2] = SimTileMap.Tile.Tree
	map.tiles[5 * w + 5] = SimTileMap.Tile.Tree
	return map


func _seen_of(coords: Array) -> FakeSeen:
	var s := FakeSeen.new()
	for c in coords:
		s.tiles[c] = true
	return s


# authored.json's `keys`, or {} when it will not parse. The declaration is the one place a tree's
# canvas and kind are written; Appearance.canvas_of reads the same file, and this reads it as text
# so a canvas_of that stopped agreeing with it would be seen.
func _authored_entries() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AUTHORED_PATH))
	if not (parsed is Dictionary):
		return {}
	var keys: Variant = (parsed as Dictionary).get("keys")
	return keys as Dictionary if keys is Dictionary else {}


# The authored keys of one kind, sorted -- so a message never depends on dictionary order.
func _authored_keys_of_kind(kind: String) -> Array[String]:
	var out: Array[String] = []
	var entries: Dictionary = _authored_entries()
	for key in entries.keys():
		var entry: Variant = entries[key]
		if entry is Dictionary and String((entry as Dictionary).get("kind", "")) == kind:
			out.append(String(key))
	out.sort()
	return out


# Whether a canopy this many pixels across is wider than the trunk's own tile -- the amendment to
# "one tile wide" (docs/30, "The outpost pack, adopted") stated as a predicate, so the lane that
# holds it has a negative to refuse.
func _wider_than_a_tile(width_px: int) -> bool:
	return width_px > int(CameraUtil.ART_NATIVE)


# --- lane 1: KEYS ----------------------------------------------------------------------------


func _the_keys_resolve_and_can_say_no() -> bool:
	Appearance.forget()
	var world: Variant = World.new(_fixture())
	var block: Dictionary = Dressing.block_of(world)
	if block.is_empty():
		push_error("dressing.street resolves no block; KEYS has nothing to judge")
		return false
	var trees: Variant = block.get("trees")
	if not (trees is Dictionary):
		push_error("dressing.street declares no trees block")
		return false
	var tall: Variant = (trees as Dictionary).get("tall")
	if not (tall is Array):
		push_error("trees.tall is not an array")
		return false
	var listed: Array = tall as Array
	var authored: Array[String] = _authored_keys_of_kind("tree")
	if authored.is_empty():
		push_error("authored.json declares no key of kind tree; KEYS has nothing to judge")
		return false
	if listed.size() != authored.size():
		push_error("trees.tall lists %d keys, authored.json declares %d of kind tree" % [listed.size(), authored.size()])
		return false
	for want_key in authored:
		if not listed.has(want_key):
			push_error("authored.json declares tree '%s' and trees.tall does not name it: art nothing draws" % want_key)
			return false
	for got_key in listed:
		if not authored.has(String(got_key)):
			push_error("trees.tall names '%s', which authored.json does not declare as a tree" % got_key)
			return false

	var widest: int = 0
	for key in authored:
		var tex: Variant = Appearance.resolve(key)
		if tex == null:
			push_error("tree key '%s' resolves no picture" % key)
			return false
		var size: Vector2i = Vector2i((tex as Texture2D).get_size())
		if Appearance.canvas_of(key) != size:
			push_error("canvas_of('%s') is %s, the picture is %s" % [key, str(Appearance.canvas_of(key)), str(size)])
			return false
		if Appearance.anchor_of(size) != Appearance.Anchor.Feet:
			push_error("anchor_of(%s) is not Feet; a tree stands on its trunk tile, it is not centred on it" % str(size))
			return false
		widest = maxi(widest, size.x)

	# The amendment, exercised: at least one canopy is wider than its trunk's tile. A tree set that
	# was all one tile wide would have made the fade rule the answer to a question nobody asked.
	if not _wider_than_a_tile(widest):
		push_error("no tree is wider than a tile (the widest is %d px); the canopy amendment is exercised by nothing" % widest)
		return false
	if _wider_than_a_tile(int(CameraUtil.ART_NATIVE)):
		push_error("a canopy exactly one tile wide was judged wider than a tile; the amendment predicate cannot say no")
		return false

	# tree_key covers every key over a 16x16 scan of one seed.
	var counts: Dictionary = {}
	for key2 in authored:
		counts[key2] = 0
	for ty in 16:
		for tx in 16:
			var picked: String = Dressing.tree_key(block, CANON_SEED, tx, ty)
			if not counts.has(picked):
				push_error("tree_key(%d,%d) answered '%s', not one of %s" % [tx, ty, picked, str(authored)])
				return false
			counts[picked] = int(counts[picked]) + 1
	for key3 in authored:
		if int(counts[key3]) == 0:
			push_error("tree_key never picked '%s' over a 16x16 scan; the variation is dead" % key3)
			return false

	# True negatives, through the same resolvers the real block passes through.
	var fabricated: Dictionary = {"trees": {"tall": ["tree_no_such"]}}
	var bad_key: String = Dressing.tree_key(fabricated, CANON_SEED, 0, 0)
	if bad_key.is_empty() or Appearance.resolve(bad_key) != null:
		push_error("a fabricated block naming 'tree_no_such' did not answer a key that resolves null")
		return false
	if not Dressing.tree_key({}, CANON_SEED, 0, 0).is_empty():
		push_error("an empty block answered a tree key")
		return false
	if not Dressing.tree_key({"trees": {"tall": []}}, CANON_SEED, 0, 0).is_empty():
		push_error("a block with an empty tall list answered a tree key")
		return false
	var native: int = int(CameraUtil.ART_NATIVE)
	if Appearance.canvas_of("tree_no_such") != Vector2i(native, native):
		push_error("canvas_of on an unknown key is not the tile square %s" % str(Vector2i(native, native)))
		return false

	_stash["tree_keys"] = authored.size()
	_stash["widest"] = widest
	print("KEYS OK trees.tall == the %d authored tree keys; every key resolves at the canvas authored.json declares with canvas_of/anchor_of (Feet) agreeing; the widest canopy is %d px against a %d px tile; tree_key covered every key over a 16x16 scan %s; a fabricated key, an empty block and an empty tall list all answer nothing" % [authored.size(), widest, native, str(counts)])
	return true


# --- lane 2: SORT ----------------------------------------------------------------------------


func _kinds_of(items: Array) -> Array:
	var out: Array = []
	for it in items:
		out.append(String((it as Dictionary)["kind"]))
	return out


func _the_sort_places_the_tree_by_depth() -> bool:
	var tree_depth: float = TopDownProjection.depth_of(3.5, 11.0)
	if tree_depth != 11.0:
		push_error("depth_of(3.5, 11.0) is %.2f, not 11.0 -- depth is the world y" % tree_depth)
		return false

	var body_a: Dictionary = {"kind": "body", "x": 5.0, "d": 9.2}
	var tree: Dictionary = {"kind": "tree", "x": 3.5, "d": tree_depth}
	var body_b: Dictionary = {"kind": "body", "x": 4.0, "d": 11.4}

	var items: Array[Dictionary] = [body_a, tree, body_b]
	items.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))
	var order: Array = _kinds_of(items)
	if order != ["body", "tree", "body"]:
		push_error("sorted order is %s, want [body, tree, body]" % str(order))
		return false
	if float(items[0]["d"]) != 9.2 or float(items[2]["d"]) != 11.4:
		push_error("sorted d values at the ends are %.2f, %.2f -- the middle element is not the tree" % [float(items[0]["d"]), float(items[2]["d"])])
		return false

	# TN: appending the tree AFTER sorting leaves it out of order.
	var late: Array[Dictionary] = [body_a, body_b]
	late.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))
	late.append(tree)
	if float(late[0]["d"]) < float(late[1]["d"]) and float(late[1]["d"]) < float(late[2]["d"]):
		push_error("appending the tree after the sort still produced ascending depth; the sort-then-append negative is dead")
		return false

	# TN: a comparator on x gives a different order on this same list.
	var by_x: Array[Dictionary] = [body_a, tree, body_b]
	by_x.sort_custom(func(a, b): return float(a["x"]) < float(b["x"]))
	if _kinds_of(by_x) == order:
		push_error("sorting by x produced the same order as sorting by depth; the x-sort negative cannot say no")
		return false

	print("SORT OK depth_of(3.5, 11.0) == 11.0; body(9.2)/tree(11.0)/body(11.4) sort to body-tree-body; appending after the sort and sorting on x both produce a different order")
	return true


# --- lane 3: RECT ----------------------------------------------------------------------------


func _the_rect_stands_on_its_feet_at_every_rung() -> bool:
	var sx: float = 100.0
	var sy: float = 200.0
	var keys: Array[String] = _authored_keys_of_kind("tree")
	if keys.is_empty():
		push_error("no authored tree; RECT has nothing to judge")
		return false
	for key in keys:
		var tex: Variant = Appearance.resolve(key)
		if tex == null:
			push_error("tree key '%s' resolves no picture; RECT has nothing to judge" % key)
			return false
		var canvas: Vector2 = (tex as Texture2D).get_size()
		for zoom in CameraUtil.ZOOM_STEPS:
			var scale: float = Appearance.blit_scale(zoom)
			var rect: Rect2 = Appearance.body_rect(sx, sy, canvas * scale, 1.0)
			var want_bottom: float = sy + Appearance.FOOT_DROP_PX
			var got_bottom: float = rect.position.y + rect.size.y
			if got_bottom != want_bottom:
				push_error("%s at zoom %.0f: bottom is %.2f, want %.2f (sy + FOOT_DROP_PX)" % [key, zoom, got_bottom, want_bottom])
				return false
			if rect.size.x != canvas.x * scale:
				push_error("%s at zoom %.0f: width is %.2f, want %.2f" % [key, zoom, rect.size.x, canvas.x * scale])
				return false
			if rect.size.y != canvas.y * scale:
				push_error("%s at zoom %.0f: height is %.2f, want %.2f" % [key, zoom, rect.size.y, canvas.y * scale])
				return false
			var want_left: float = roundf(sx - rect.size.x / 2.0)
			if rect.position.x != want_left:
				push_error("%s at zoom %.0f: left is %.2f, want round(sx - width/2) = %.2f" % [key, zoom, rect.position.x, want_left])
				return false

	# TN: a square canvas centres on the point instead of standing on it.
	var square: Rect2 = Appearance.body_rect(sx, sy, Vector2(64, 64), 1.0)
	if square.position.y + square.size.y == sy + Appearance.FOOT_DROP_PX:
		push_error("a square canvas's bottom landed on the feet line; the centred negative is dead")
		return false

	print("RECT OK %d trees: bottom == sy + %.1f, width and height the picture's own times the scale, left == round(sx - width/2) at all %d zoom rungs; a square canvas centres instead" % [keys.size(), Appearance.FOOT_DROP_PX, CameraUtil.ZOOM_STEPS.size()])
	return true


# --- lane 4: ALPHA ---------------------------------------------------------------------------


func _the_alpha_fades_only_the_tree() -> bool:
	var rect := Rect2(100, 0, 64, 192)
	var a_inside: float = Dressing.tree_alpha(rect, [Vector2(120, 100)])
	if a_inside != Dressing.TREE_FADE_ALPHA:
		push_error("a point inside the tree's rect answered %.3f, not TREE_FADE_ALPHA %.3f" % [a_inside, Dressing.TREE_FADE_ALPHA])
		return false

	for outside in [Vector2(165, 100), Vector2(120, 193)]:
		var a_outside: float = Dressing.tree_alpha(rect, [outside])
		if a_outside != 1.0:
			push_error("a point just outside %s answered %.3f, not 1.0" % [str(outside), a_outside])
			return false

	var a_empty: float = Dressing.tree_alpha(rect, [])
	if a_empty != 1.0:
		push_error("an empty body-points list answered %.3f, not 1.0" % a_empty)
		return false

	if a_inside <= 0.0 or a_inside > 1.0 or a_empty <= 0.0 or a_empty > 1.0:
		push_error("an alpha answer fell outside (0, 1]")
		return false
	if Dressing.TREE_FADE_ALPHA <= 0.0 or Dressing.TREE_FADE_ALPHA >= 1.0:
		push_error("TREE_FADE_ALPHA %.3f is not strictly between 0 and 1" % Dressing.TREE_FADE_ALPHA)
		return false

	print("ALPHA OK a point inside the tree's rect answers TREE_FADE_ALPHA %.2f, points just outside and an empty list answer 1.0, both in (0, 1]" % Dressing.TREE_FADE_ALPHA)
	return true


# --- lane 5: TILES ---------------------------------------------------------------------------


func _the_tiles_lane_answers_only_seen_trees() -> bool:
	var map: Variant = _tree_map()
	var whole: Dictionary = {"minX": 0.0, "minY": 0.0, "maxX": 7.0, "maxY": 7.0}

	var seen_one: FakeSeen = _seen_of([Vector2i(2, 2)])
	var got1: Array[Vector2i] = Dressing.tree_tiles(map, seen_one, whole)
	if got1.size() != 1 or got1[0] != Vector2i(2, 2):
		push_error("seeing only (2,2) answered %s, want [(2,2)]" % str(got1))
		return false

	var seen_floor: FakeSeen = _seen_of([Vector2i(0, 0)])
	var got2: Array[Vector2i] = Dressing.tree_tiles(map, seen_floor, whole)
	if not got2.is_empty():
		push_error("a seen Floor tile answered %s, want []" % str(got2))
		return false

	var got3: Array[Vector2i] = Dressing.tree_tiles(map, null, whole)
	if not got3.is_empty():
		push_error("seen == null answered %s, want []" % str(got3))
		return false

	# Bounds excluding (5,5) while it is seen: only the in-bounds tree comes back.
	var seen_both: FakeSeen = _seen_of([Vector2i(2, 2), Vector2i(5, 5)])
	var narrow: Dictionary = {"minX": 0.0, "minY": 0.0, "maxX": 3.0, "maxY": 3.0}
	var got4: Array[Vector2i] = Dressing.tree_tiles(map, seen_both, narrow)
	if got4.size() != 1 or got4[0] != Vector2i(2, 2):
		push_error("bounds excluding a seen (5,5) answered %s, want [(2,2)]" % str(got4))
		return false

	var seen_all := FakeSeen.new()
	for ty in 8:
		for tx in 8:
			seen_all.tiles[Vector2i(tx, ty)] = true
	var got5: Array[Vector2i] = Dressing.tree_tiles(map, seen_all, whole)
	if got5.size() != 2 or not got5.has(Vector2i(2, 2)) or not got5.has(Vector2i(5, 5)):
		push_error("a seen-everything set answered %s, want exactly both trees and no Floor tile" % str(got5))
		return false

	var oob: Dictionary = {"minX": 100.0, "minY": 100.0, "maxX": 108.0, "maxY": 108.0}
	var got6: Array[Vector2i] = Dressing.tree_tiles(map, seen_all, oob)
	if not got6.is_empty():
		push_error("an out-of-bounds bounds rect answered %s, want []" % str(got6))
		return false

	_stash["tiles_total"] = 2
	_stash["tiles_seen"] = got5.size()
	print("TILES OK seen (2,2) -> [(2,2)]; a seen Floor tile, seen == null and an out-of-bounds rect all -> []; bounds excluding a seen tree drops it; a seen-everything set -> exactly both trees")
	return true


# --- lane 6: FALLBACK --------------------------------------------------------------------------


# The first needle missing from `body`, or "" when all are present. Proved on a fabricated body
# below before it is trusted on the real one -- check_topdown.gd's / check_roof_look.gd's
# convention: a scanner that answers "" for everything is a gate that cannot fail.
func _missing_needle(body: String, needles: Array) -> String:
	for n in needles:
		if not body.contains(String(n)):
			return String(n)
	return ""


func _the_fallback_and_the_reach_hold_together() -> bool:
	var proof: String = _missing_needle("no keywords appear anywhere in this line", ["TOTALLY_ABSENT_TOKEN"])
	if proof.is_empty():
		push_error("the needle scanner found nothing missing in a fixture missing everything; it cannot say no")
		return false

	var district: String = _function_body(MAIN_GD, "_draw_district")
	if district.is_empty():
		push_error("could not read _draw_district out of %s -- FALLBACK had nothing to judge" % MAIN_GD)
		return false
	var m1: String = _missing_needle(district, ["Dressing.tree_key(", "draw_circle(centre, zoom * 0.42"])
	if not m1.is_empty():
		push_error("_draw_district does not contain %s" % m1)
		return false

	var entities: String = _function_body(MAIN_GD, "_draw_entities")
	if entities.is_empty():
		push_error("could not read _draw_entities out of %s" % MAIN_GD)
		return false
	var needles: Array = [
		"Dressing.tree_tiles(", "Dressing.tree_key(", "\"kind\": \"tree\"", "TopDownProjection.depth_of(", "_blit_tree(",
	]
	var m2: String = _missing_needle(entities, needles)
	if not m2.is_empty():
		push_error("_draw_entities does not contain %s" % m2)
		return false

	var at_blit: int = entities.find("_blit_tree(")
	if not entities.substr(at_blit).contains("continue"):
		push_error("_draw_entities calls _blit_tree with no continue after it; a tree would fall into the body branch")
		return false

	var at_kind: int = entities.find("\"kind\": \"tree\"")
	var at_sort: int = entities.find("items.sort_custom(")
	if at_kind < 0 or at_sort < 0 or not (at_kind < at_sort):
		push_error("\"kind\": \"tree\" (%d) is not appended before items.sort_custom( (%d)" % [at_kind, at_sort])
		return false

	if entities.count("draw_set_transform(") != 0:
		push_error("_draw_entities holds %d draw_set_transform( calls; the entity loop must hold none" % entities.count("draw_set_transform("))
		return false

	var blit_tree: String = _function_body(MAIN_GD, "_blit_tree")
	if blit_tree.is_empty():
		push_error("could not read _blit_tree out of %s" % MAIN_GD)
		return false
	var m3: String = _missing_needle(blit_tree, ["Appearance.body_rect(", "Dressing.tree_alpha(", "draw_texture_rect("])
	if not m3.is_empty():
		push_error("_blit_tree does not contain %s" % m3)
		return false
	if blit_tree.contains("body_flip("):
		push_error("_blit_tree calls body_flip(; a tree never flips (docs/30)")
		return false

	print("FALLBACK OK _draw_district keeps the disc fallback gated by tree_key; _draw_entities gathers/sorts/blits the tree with a continue after it, appended before the sort; _blit_tree reaches body_rect/tree_alpha/draw_texture_rect, never body_flip; zero transforms in the entity loop")
	return true


# --- lane 7: SIM UNMOVED -----------------------------------------------------------------------


func _the_sim_stayed_unmoved_and_the_pick_stays_a_hash() -> bool:
	if int(SimTileMap.OPACITY[SimTileMap.Tile.Tree]) != SimTileMap.Opacity.Opaque:
		push_error("SimTileMap.OPACITY[Tile.Tree] is not Opaque; a drawn tree must not stop blocking sight")
		return false
	if not bool(SimTileMap.SOLID[SimTileMap.Tile.Tree]):
		push_error("SimTileMap.SOLID[Tile.Tree] is not true; a drawn tree must not stop blocking movement")
		return false

	var code: String = _code_of(DRESSING_GD)
	if code.is_empty():
		push_error("could not read %s -- the no-RNG assertion had nothing to judge" % DRESSING_GD)
		return false
	for forbidden in ["RandomNumberGenerator", "randi", "randf", "rng"]:
		if code.contains(forbidden):
			push_error("%s contains '%s'; the tree pick must be a pure hash, never a sim or presentation stream" % [DRESSING_GD, forbidden])
			return false

	print("SIM UNMOVED OK Tile.Tree stays Opaque and Solid, unmoved by this slice; %s reaches for no RNG in its code" % DRESSING_GD)
	return true


# --- lane 8: PLAYED --------------------------------------------------------------------------


func _the_shipped_suburb_stands_its_trees() -> bool:
	Appearance.forget()
	var boot: Dictionary = SimBoot.playable(CANON_SEED, GATE_SIZE)
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	world.vision.refresh(world, map)
	var seen: Variant = world.vision.tiles_for(int(world.player))
	if seen == null:
		push_error("the player's vision has not refreshed; PLAYED has nothing to judge")
		return false

	var w: int = int(map.w)
	var h: int = int(map.h)
	var bounds: Dictionary = {"minX": 0.0, "minY": 0.0, "maxX": float(w), "maxY": float(h)}

	var tree_total: int = 0
	for ty in h:
		for tx in w:
			if int(SimTileMap.tile_at(map, tx, ty)) == SimTileMap.Tile.Tree:
				tree_total += 1
	if tree_total == 0:
		push_error("the shipped suburb at %d placed no Tree tile; PLAYED has nothing to judge" % GATE_SIZE)
		return false

	var dress: Dictionary = Dressing.block_of(world)
	var got: Array[Vector2i] = Dressing.tree_tiles(map, seen, bounds)
	for t in got:
		if int(SimTileMap.tile_at(map, t.x, t.y)) != SimTileMap.Tile.Tree:
			push_error("tree_tiles returned %s, which is not a Tree tile" % str(t))
			return false
		if not (seen as Object).call("has_tile", t.x, t.y):
			push_error("tree_tiles returned %s, which is not in the seen set" % str(t))
			return false
		var key: String = Dressing.tree_key(dress, int(world.seed), t.x, t.y)
		if key.is_empty() or Appearance.resolve(key) == null:
			push_error("tree_tiles returned %s but tree_key resolves no texture for it" % str(t))
			return false

	var seen_all := FakeSeen.new()
	for ty2 in h:
		for tx2 in w:
			seen_all.tiles[Vector2i(tx2, ty2)] = true
	var got_all: Array[Vector2i] = Dressing.tree_tiles(map, seen_all, bounds)
	if got_all.size() != tree_total:
		push_error("a see-everything set returned %d tiles, want exactly the %d Tree tiles on the map" % [got_all.size(), tree_total])
		return false

	_stash["tree_total"] = tree_total
	_stash["tree_seen"] = got.size()
	print("PLAYED OK suburb@%d seed %d: %d Tree tiles on the map, %d seen and drawable (each a Tree tile, seen, resolving a texture); a see-everything set accounts for exactly all %d" % [GATE_SIZE, CANON_SEED, tree_total, got.size(), got_all.size()])
	return true


# --- lane 9: TIERS ---------------------------------------------------------------------------


# The bounds every tree picture is authored to, and the one place they are a rule rather than a
# sentence: assets/sprites/README.md quotes this lane. Measured off the outpost pack's pine,
# broadleaf and dead tree at ALPHA_SOLID on 2026-09-26, cropped to the pack's anchor row:
#
#   tree        canvas    box      tip row   clear (l/r)   foot
#   pine        64 x 94   45 x 88      6       9 / 10        4
#   broadleaf   80 x 94   66 x 86      8       7 / 7         4
#   dead tree   64 x 94   46 x 82     12       9 / 9         2
#
# The generated conifers these replaced were held to 20-26 wide and three clear pixels either side
# because a canopy wider than its trunk would hide the bodies beside it; docs/30's amendment lets
# the canopy be wider and answers the hidden body with the fade instead, so WIDTH_MAX is now the
# bound that keeps a canopy from becoming a wall (two tiles and a bit) and the side margin is the
# pack's own clearance to the canvas edge, not a hiding rule.
const SIDE_CLEAR_PX: int = 6
const WIDTH_MIN: int = 40
const WIDTH_MAX: int = 70
const HEIGHT_MIN: int = 78
const HEIGHT_MAX: int = 92
const TIP_ROW_MAX: int = 14
const FOOT_MIN: int = 2
const FOOT_MAX: int = 8


# Whether a pixel is part of the picture rather than a sub-visible speck.
func _is_drawn(image: Image, x: int, y: int) -> bool:
	return roundi(image.get_pixel(x, y).a * 255.0) >= ALPHA_SOLID


# The box of drawn pixels, the sole row, and how wide the foot is on that row. {} for a picture
# with no drawn pixel at all, which _judge_tier reports as its own failure.
func _bounds_of(image: Image) -> Dictionary:
	var min_x: int = image.get_width()
	var min_y: int = image.get_height()
	var max_x: int = -1
	var max_y: int = -1
	for y in image.get_height():
		for x in image.get_width():
			if not _is_drawn(image, x, y):
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < 0:
		return {}
	var foot: int = 0
	for fx in image.get_width():
		if _is_drawn(image, fx, max_y):
			foot += 1
	return {"min_x": min_x, "max_x": max_x, "min_y": min_y, "max_y": max_y, "foot": foot}


# The same box at "alpha above zero" -- what a lane without a named threshold would measure, kept
# only so the speck negative below can show the two disagree.
func _bounds_at_any_alpha(image: Image) -> Dictionary:
	var min_x: int = image.get_width()
	var min_y: int = image.get_height()
	var max_x: int = -1
	var max_y: int = -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a <= 0.0:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < 0:
		return {}
	return {"min_x": min_x, "max_x": max_x, "min_y": min_y, "max_y": max_y, "foot": 1}


# Why this picture is outside the tier, or "" when it stands inside it. One predicate, so the
# fabricated negatives below are refused by exactly the rule the real pictures pass. `canvas` is
# the picture's own canvas: the sole line and the side margins are relative to it.
func _judge_tier(b: Dictionary, canvas: Vector2i) -> String:
	if b.is_empty():
		return "is entirely transparent"
	var w: int = int(b["max_x"]) - int(b["min_x"]) + 1
	var h: int = int(b["max_y"]) - int(b["min_y"]) + 1
	if w < WIDTH_MIN or w > WIDTH_MAX:
		return "is %d px wide, outside [%d, %d]" % [w, WIDTH_MIN, WIDTH_MAX]
	if h < HEIGHT_MIN or h > HEIGHT_MAX:
		return "is %d px tall, outside [%d, %d]" % [h, HEIGHT_MIN, HEIGHT_MAX]
	if int(b["max_y"]) != canvas.y - 1:
		return "stands on row %d, not the sole line %d" % [int(b["max_y"]), canvas.y - 1]
	if int(b["min_y"]) > TIP_ROW_MAX:
		return "tips at row %d, below the top %d rows" % [int(b["min_y"]), TIP_ROW_MAX + 1]
	if int(b["min_x"]) < SIDE_CLEAR_PX or int(b["max_x"]) > canvas.x - 1 - SIDE_CLEAR_PX:
		return "reaches x [%d, %d], inside the %d px side margin" % [int(b["min_x"]), int(b["max_x"]), SIDE_CLEAR_PX]
	if int(b["foot"]) < FOOT_MIN or int(b["foot"]) > FOOT_MAX:
		return "stands on a %d px foot, outside [%d, %d]" % [int(b["foot"]), FOOT_MIN, FOOT_MAX]
	return ""


func _the_pictures_stand_inside_their_tier() -> bool:
	Appearance.forget()
	var keys: Array[String] = _authored_keys_of_kind("tree")
	if keys.is_empty():
		push_error("no authored tree; TIERS has nothing to judge")
		return false
	var boxes: Array = []
	var datas: Array = []
	var sample: Image = null
	for key in keys:
		var tex: Variant = Appearance.resolve(key)
		if tex == null:
			push_error("tree key '%s' resolves no picture; TIERS has nothing to judge" % key)
			return false
		var img: Image = (tex as Texture2D).get_image()
		var b: Dictionary = _bounds_of(img)
		var why: String = _judge_tier(b, Vector2i(img.get_width(), img.get_height()))
		if not why.is_empty():
			push_error("%s %s" % [key, why])
			return false
		boxes.append("%s %dx%d" % [key, int(b["max_x"]) - int(b["min_x"]) + 1, int(b["max_y"]) - int(b["min_y"]) + 1])
		var data: PackedByteArray = img.get_data()
		for other in datas:
			if (other as PackedByteArray) == data:
				push_error("two tree pictures are pixel-identical; the variation is dead")
				return false
		datas.append(data)
		if sample == null:
			sample = img

	# TN, through the same predicate: a canvas filled edge to edge is too wide and too tall, and a
	# picture hanging above the sole line does not stand on it.
	var w: int = 64
	var h: int = 94
	var canvas := Vector2i(w, h)
	var solid: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	solid.fill(Color(0.0, 0.0, 0.0, 1.0))
	if _judge_tier(_bounds_of(solid), canvas).is_empty():
		push_error("a fully opaque canvas passed the tier bounds; TIERS cannot say no")
		return false
	var floating: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	floating.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in range(2, 90):
		for x in range(SIDE_CLEAR_PX, w - SIDE_CLEAR_PX):
			floating.set_pixel(x, y, Color(0.0, 0.0, 0.0, 1.0))
	if _judge_tier(_bounds_of(floating), canvas).is_empty():
		push_error("a picture hanging above the sole line passed the tier bounds; TIERS cannot say no")
		return false

	# TN and control for the named threshold: a real tree with one alpha-6 speck in the canvas's
	# top-left corner. At ALPHA_SOLID the speck is not a pixel and the tree still stands inside the
	# tier; at "alpha above zero" the same picture's box swallows the corner and it is refused --
	# which is the pickup doc's whole argument for naming the threshold.
	var specked: Image = sample.duplicate()
	specked.set_pixel(0, 0, Color(0.0, 0.0, 0.0, 6.0 / 255.0))
	if not _judge_tier(_bounds_of(specked), Vector2i(specked.get_width(), specked.get_height())).is_empty():
		push_error("a tree with an alpha-6 speck in its corner was refused at ALPHA_SOLID; the threshold does not accept a speck")
		return false
	if _judge_tier(_bounds_at_any_alpha(specked), Vector2i(specked.get_width(), specked.get_height())).is_empty():
		push_error("the speck did not move the box at alpha above zero; the threshold's negative is dead")
		return false
	var solid_corner: Image = sample.duplicate()
	solid_corner.set_pixel(0, 0, Color(0.0, 0.0, 0.0, 1.0))
	if _judge_tier(_bounds_of(solid_corner), Vector2i(solid_corner.get_width(), solid_corner.get_height())).is_empty():
		push_error("a real pixel in the corner passed the tier bounds; the threshold refuses nothing")
		return false

	print("TIERS OK %d pictures %s at ALPHA_SOLID %d: all standing on their last row, tips within the top %d rows, %d clear px either side, feet in [%d, %d], widths in [%d, %d], pairwise distinct; a fully opaque canvas and one hanging above the sole line are both refused, and a corner speck is accepted where a real corner pixel is refused" % [keys.size(), str(boxes), ALPHA_SOLID, TIP_ROW_MAX + 1, SIDE_CLEAR_PX, FOOT_MIN, FOOT_MAX, WIDTH_MIN, WIDTH_MAX])
	return true


# --- lane 10: NATURE -------------------------------------------------------------------------


# The most a dressing picture may cover: one tile tall, and no wider than the log (the widest the
# pack draws, 48). Anything taller would stand in front of what is north of it and want the
# entity sort; anything wider would overhang a neighbour the pick never checked.
const NATURE_MAX_W: int = 48
const NATURE_MAX_H: int = 32


# A W x H all-grass Floor map: the ground the nature pick has to say yes on before each fabricated
# negative takes one thing away.
func _grass_map(w: int, h: int) -> Variant:
	var map: Variant = SimTileMap.blank_map(w, h)
	for i in w * h:
		map.surfaces[i] = SimSurface.Surface.Grass
	return map


# How many of `count` seeds pick anything at this tile from this block: the roll is real when it
# is neither always nor never.
func _picks_over_seeds(block: Dictionary, map: Variant, tx: int, ty: int, count: int) -> int:
	var hits: int = 0
	for seed_val in count:
		if not Dressing.nature_key(block, map, seed_val, tx, ty).is_empty():
			hits += 1
	return hits


# A list of picks as a sorted list of "tx,ty,key" strings, so two lists compare by what they hold
# and not by the order they were walked in.
func _pick_set(picks: Array[Dictionary]) -> Array:
	var out: Array = []
	for pick in picks:
		out.append("%d,%d,%s" % [int(pick["tx"]), int(pick["ty"]), String(pick["key"])])
	out.sort()
	return out


func _bush_block(rarity: int = 2) -> Dictionary:
	return {"nature": [{"key": "nature_bush", "surfaces": ["grass"], "rarity": rarity}]}


# The position of `first` and `second` in `body`, and whether the first comes before the second.
# Proved on a fabricated body below before it is trusted on the real one.
func _comes_before(body: String, first: String, second: String) -> bool:
	var a: int = body.find(first)
	var b: int = body.find(second)
	return a >= 0 and b >= 0 and a < b


func _the_nature_dressing_lies_where_it_should() -> bool:
	Appearance.forget()
	var world: Variant = World.new(_fixture())
	var block: Dictionary = Dressing.block_of(world)
	var entries: Variant = block.get("nature")
	if not (entries is Array) or (entries as Array).is_empty():
		push_error("dressing.street declares no `nature` list; NATURE has nothing to judge")
		return false

	# --- what the content says --------------------------------------------------------------
	var props: Array[String] = _authored_keys_of_kind("prop")
	var named: Dictionary = {}
	for raw in entries as Array:
		if not (raw is Dictionary):
			push_error("a nature entry is not an object: %s" % str(raw))
			return false
		var entry: Dictionary = raw as Dictionary
		var key: String = String(entry.get("key", ""))
		if not props.has(key):
			push_error("nature entry names '%s', which authored.json does not declare as a prop" % key)
			return false
		var tex: Variant = Appearance.resolve(key)
		if tex == null:
			push_error("nature key '%s' resolves no picture" % key)
			return false
		var size: Vector2i = Vector2i((tex as Texture2D).get_size())
		if size != Appearance.canvas_of(key):
			push_error("canvas_of('%s') is %s, the picture is %s" % [key, str(Appearance.canvas_of(key)), str(size)])
			return false
		if size.x > NATURE_MAX_W or size.y > NATURE_MAX_H:
			push_error("nature key '%s' is %s, over the %d x %d a flat picture may cover" % [key, str(size), NATURE_MAX_W, NATURE_MAX_H])
			return false
		if int(entry.get("rarity", 0)) < 2:
			push_error("nature entry '%s' has rarity %s; under two it would land on every tile" % [key, str(entry.get("rarity"))])
			return false
		var surfaces: Variant = entry.get("surfaces")
		if not (surfaces is Array) or (surfaces as Array).is_empty():
			push_error("nature entry '%s' names no surface" % key)
			return false
		for surface_name in surfaces as Array:
			if Dressing.surface_named(String(surface_name)) < 0:
				push_error("nature entry '%s' names surface '%s', which SimSurface does not have" % [key, surface_name])
				return false
		var beside: String = String(entry.get("beside", ""))
		if not beside.is_empty() and beside != Dressing.NATURE_BESIDE_WATER:
			push_error("nature entry '%s' is beside '%s', which the pick does not know" % [key, beside])
			return false
		named[key] = true
	# The dead-socket half: every authored nature_* picture is named by some entry.
	for prop_key in props:
		if prop_key.begins_with("nature_") and not named.has(prop_key):
			push_error("authored.json declares '%s' and no nature entry names it: art nothing draws" % prop_key)
			return false
	if Dressing.surface_named("marble") != -1 or Dressing.surface_named("grass") != int(SimSurface.Surface.Grass):
		push_error("surface_named does not tell a real surface from a fabricated one")
		return false

	# --- the pick, on a hand map, both ways --------------------------------------------------
	var w: int = 12
	var h: int = 6
	var grass: Variant = _grass_map(w, h)
	var bush: Dictionary = _bush_block()
	var yes: int = _picks_over_seeds(bush, grass, 5, 2, 32)
	if yes == 0 or yes == 32:
		push_error("a rarity-2 bush on open grass picked %d of 32 seeds; the roll is not a roll" % yes)
		return false
	# The same seed and tile answer the same way twice.
	for seed_val in 8:
		if Dressing.nature_key(bush, grass, seed_val, 5, 2) != Dressing.nature_key(bush, grass, seed_val, 5, 2):
			push_error("the nature pick answered differently twice for one seed and tile; it is not a pure hash")
			return false
	# The tile reaches the hash: two tiles do not agree over every seed.
	var differ: int = 0
	for seed_val in 32:
		if Dressing.nature_key(bush, grass, seed_val, 3, 1).is_empty() != Dressing.nature_key(bush, grass, seed_val, 8, 4).is_empty():
			differ += 1
	if differ == 0:
		push_error("two tiles picked identically over 32 seeds; the tile is not reaching the hash")
		return false

	# Each negative takes one thing away from the ground the positive stood on.
	var paved: Variant = _grass_map(w, h)
	paved.surfaces[2 * w + 5] = SimSurface.Surface.Paved
	if _picks_over_seeds(bush, paved, 5, 2, 32) != 0:
		push_error("a bush picked a paved tile; the surface list is not read")
		return false
	for taken in [
		{"name": "a wall to the east", "idx": 2 * w + 6, "tile": SimTileMap.Tile.Wall},
		{"name": "a wall to the west", "idx": 2 * w + 4, "tile": SimTileMap.Tile.Wall},
		{"name": "a door to the east", "idx": 2 * w + 6, "tile": SimTileMap.Tile.Door},
		{"name": "itself a tree", "idx": 2 * w + 5, "tile": SimTileMap.Tile.Tree},
		{"name": "itself a heap", "idx": 2 * w + 5, "tile": SimTileMap.Tile.Low},
		{"name": "itself deep water", "idx": 2 * w + 5, "tile": SimTileMap.Tile.Water},
	]:
		var blocked: Variant = _grass_map(w, h)
		blocked.tiles[int((taken as Dictionary)["idx"])] = int((taken as Dictionary)["tile"])
		if _picks_over_seeds(bush, blocked, 5, 2, 32) != 0:
			push_error("a bush picked a tile with %s; the open-floor rule is not read" % String((taken as Dictionary)["name"]))
			return false
	var indoors: Variant = _grass_map(w, h)
	indoors.indoors[2 * w + 5] = 1
	if _picks_over_seeds(bush, indoors, 5, 2, 32) != 0:
		push_error("a bush picked an indoor tile")
		return false
	var indoor_neighbour: Variant = _grass_map(w, h)
	indoor_neighbour.indoors[2 * w + 6] = 1
	if _picks_over_seeds(bush, indoor_neighbour, 5, 2, 32) != 0:
		push_error("a bush picked a tile whose east neighbour is indoors; a wide picture would overhang the room")
		return false
	# The edge of the map is not open floor either.
	if _picks_over_seeds(bush, grass, 0, 2, 32) != 0 or _picks_over_seeds(bush, grass, w - 1, 2, 32) != 0:
		push_error("a bush picked a tile on the map's edge, whose neighbour is off the map")
		return false

	# Reeds grow beside water and nowhere else.
	var reeds: Dictionary = {"nature": [{"key": "nature_reeds", "surfaces": ["grass"], "rarity": 2, "beside": "water"}]}
	var shore: Variant = _grass_map(w, h)
	shore.tiles[3 * w + 5] = SimTileMap.Tile.Water
	shore.surfaces[3 * w + 5] = SimSurface.Surface.Water
	var beside_hits: int = _picks_over_seeds(reeds, shore, 5, 2, 32)
	if beside_hits == 0:
		push_error("reeds never grew beside deep water over 32 seeds; the beside clause is dead")
		return false
	if _picks_over_seeds(reeds, grass, 5, 2, 32) != 0:
		push_error("reeds grew on a tile with no water beside it")
		return false
	var ford: Variant = _grass_map(w, h)
	ford.surfaces[3 * w + 5] = SimSurface.Surface.Water
	if _picks_over_seeds(reeds, ford, 5, 2, 32) == 0:
		push_error("reeds never grew beside a ford (a Floor tile on the water surface); the ford is water too")
		return false

	# An entry that misses its ground lets the next entry try: the first hit wins, not the first entry.
	var ordered: Dictionary = {"nature": [
		{"key": "nature_rock", "surfaces": ["dirt"], "rarity": 2},
		{"key": "nature_bush", "surfaces": ["grass"], "rarity": 2},
	]}
	var got_rock: bool = false
	var got_bush: bool = false
	for seed_val in 64:
		var picked: String = Dressing.nature_key(ordered, grass, seed_val, 5, 2)
		got_rock = got_rock or picked == "nature_rock"
		got_bush = got_bush or picked == "nature_bush"
	if got_rock or not got_bush:
		push_error("over grass the dirt-only rock picked=%s and the grass bush picked=%s; an entry that misses its ground must fall through to the next" % [str(got_rock), str(got_bush)])
		return false

	# Malformed and absent: nothing, never a default.
	for bad in [
		{}, {"nature": []}, {"nature": "grass"}, {"nature": [5]},
		{"nature": [{"key": "", "surfaces": ["grass"], "rarity": 2}]},
		{"nature": [{"key": "nature_bush", "surfaces": ["grass"], "rarity": 1}]},
		{"nature": [{"key": "nature_bush", "surfaces": ["grass"], "rarity": 0}]},
		{"nature": [{"key": "nature_bush", "surfaces": [], "rarity": 2}]},
		{"nature": [{"key": "nature_bush", "surfaces": ["marble"], "rarity": 2}]},
		{"nature": [{"key": "nature_bush", "surfaces": ["grass"], "rarity": 2, "beside": "lava"}]},
	]:
		if _picks_over_seeds(bad as Dictionary, grass, 5, 2, 32) != 0:
			push_error("a malformed or empty block picked something: %s" % str(bad))
			return false

	# --- nature_tiles: a subset of seen, inside bounds ---------------------------------------
	var whole: Dictionary = {"minX": 0.0, "minY": 0.0, "maxX": float(w), "maxY": float(h)}
	var seen_all := FakeSeen.new()
	var expected: int = 0
	for ty in h:
		for tx in w:
			seen_all.tiles[Vector2i(tx, ty)] = true
			if not Dressing.nature_key(bush, grass, 3, tx, ty).is_empty():
				expected += 1
	var everything: Array[Dictionary] = Dressing.nature_tiles(bush, grass, seen_all, 3, whole)
	if everything.size() != expected or expected == 0:
		push_error("a see-everything set answered %d tiles, want exactly the %d the pick lands on" % [everything.size(), expected])
		return false
	for pick in everything:
		if String(pick["key"]) != "nature_bush" or Dressing.nature_key(bush, grass, 3, int(pick["tx"]), int(pick["ty"])) != "nature_bush":
			push_error("nature_tiles answered %s, which the pick does not agree with" % str(pick))
			return false
	if not Dressing.nature_tiles(bush, grass, null, 3, whole).is_empty():
		push_error("seen == null answered nature tiles; nobody sees no bushes")
		return false
	var only_one: FakeSeen = _seen_of([Vector2i(int(everything[0]["tx"]), int(everything[0]["ty"]))])
	var one: Array[Dictionary] = Dressing.nature_tiles(bush, grass, only_one, 3, whole)
	if one.size() != 1 or int(one[0]["tx"]) != int(everything[0]["tx"]):
		push_error("seeing one picked tile answered %s, want exactly it" % str(one))
		return false
	var unseen := FakeSeen.new()
	if not Dressing.nature_tiles(bush, grass, unseen, 3, whole).is_empty():
		push_error("an empty seen set answered nature tiles; a picture would draw where nobody can see")
		return false
	var narrow: Dictionary = {"minX": 0.0, "minY": 0.0, "maxX": 2.0, "maxY": 2.0}
	for pick2 in Dressing.nature_tiles(bush, grass, seen_all, 3, narrow):
		if int(pick2["tx"]) > 2 or int(pick2["ty"]) > 2:
			push_error("bounds excluding a tile still answered it: %s" % str(pick2))
			return false

	# --- the roll is hash_at's number ---------------------------------------------------------
	# The fast path writes hash_at's arithmetic out with the salt pre-multiplied. The reference
	# below is built from hash_at itself and compared on every tile of an all-grass map, for three
	# rarities (odd, even and a large one) and eight seeds; the two edge columns are never open
	# floor with both neighbours, so they answer nothing in both.
	var rolls: int = 0
	for rarity in [2, 3, 7, 30]:
		var block_r: Dictionary = _bush_block(int(rarity))
		for seed_val in 8:
			for ty in h:
				for tx in w:
					var want: String = ""
					if tx > 0 and tx < w - 1 and (Dressing.hash_at(seed_val, tx, ty, Dressing.SALT_NATURE) >> 8) % int(rarity) == 0:
						want = "nature_bush"
					if Dressing.nature_key(block_r, grass, seed_val, tx, ty) != want:
						push_error("rarity %d seed %d tile (%d,%d): nature_key answered '%s', the hash_at reference '%s'; the fast path's copy of the roll has drifted" % [int(rarity), seed_val, tx, ty, Dressing.nature_key(block_r, grass, seed_val, tx, ty), want])
						return false
					if not want.is_empty():
						rolls += 1
	if rolls == 0:
		push_error("no tile rolled in the reference comparison; it judged nothing")
		return false
	# TN: the comparison can say no -- the same reference against a different salt disagrees.
	var disagreed: bool = false
	for tx2 in range(1, w - 1):
		var mine: bool = Dressing.nature_key(bush, grass, 5, tx2, 2) == "nature_bush"
		var theirs: bool = (Dressing.hash_at(5, tx2, 2, Dressing.SALT_NATURE + 1) >> 8) % 2 == 0
		if mine != theirs:
			disagreed = true
	if not disagreed:
		push_error("a reference built on the wrong salt agreed with nature_key on every tile; the reference comparison cannot say no")
		return false

	# --- the chunk cache ----------------------------------------------------------------------
	# It answers what the uncached pick answers, over three observers and three windows on a map
	# wider than a chunk; serves what it holds (a poisoned chunk is drawn, so the cache is read and
	# not recomputed); and a cache emptied answers the same again.
	var big_w: int = Dressing.NATURE_CHUNK * 3 + 5
	var big_h: int = Dressing.NATURE_CHUNK * 2 + 3
	var big: Variant = _grass_map(big_w, big_h)
	big.tiles[7 * big_w + 20] = SimTileMap.Tile.Wall
	var big_seen := FakeSeen.new()
	var half_seen := FakeSeen.new()
	for ty3 in big_h:
		for tx3 in big_w:
			big_seen.tiles[Vector2i(tx3, ty3)] = true
			if (tx3 + ty3) % 2 == 0:
				half_seen.tiles[Vector2i(tx3, ty3)] = true
	var windows: Array = [
		{"minX": 0.0, "minY": 0.0, "maxX": float(big_w), "maxY": float(big_h)},
		{"minX": 10.5, "minY": 3.2, "maxX": 37.0, "maxY": 20.9},
		{"minX": -4.0, "minY": -4.0, "maxX": 5.0, "maxY": 5.0},
		{"minX": 60.0, "minY": 30.0, "maxX": 90.0, "maxY": 40.0},
	]
	var cache_compared: int = 0
	for observer in [big_seen, half_seen, FakeSeen.new(), null]:
		var shared: Dictionary = {}
		for window in windows:
			var plain: Array[Dictionary] = Dressing.nature_tiles(bush, big, observer, 11, window as Dictionary)
			var cached: Array[Dictionary] = Dressing.nature_tiles_cached(bush, big, observer, 11, window as Dictionary, shared)
			if _pick_set(plain) != _pick_set(cached):
				push_error("the cached picks differ from the uncached ones over window %s: %d against %d" % [str(window), cached.size(), plain.size()])
				return false
			cache_compared += plain.size()
	if cache_compared == 0:
		push_error("the cache comparison judged no pick at all")
		return false
	var poisoned: Dictionary = {0: [{"tx": 1, "ty": 1, "key": "nature_rock"}]}
	var served: Array[Dictionary] = Dressing.nature_tiles_cached(bush, big, big_seen, 11, {"minX": 0.0, "minY": 0.0, "maxX": 3.0, "maxY": 3.0}, poisoned)
	if served.size() != 1 or String(served[0]["key"]) != "nature_rock":
		push_error("a poisoned chunk was not served (%s); the cache is recomputing what it holds" % str(served))
		return false
	if Dressing.nature_tiles_cached(bush, big, big_seen, 11, {"minX": 0.0, "minY": 0.0, "maxX": 3.0, "maxY": 3.0}, {}).size() == 1 and String(Dressing.nature_tiles_cached(bush, big, big_seen, 11, {"minX": 0.0, "minY": 0.0, "maxX": 3.0, "maxY": 3.0}, {})[0]["key"]) == "nature_rock":
		push_error("an emptied cache still answered the poisoned pick; the cache is a static")
		return false

	# --- the draw pass is reached, in its place ----------------------------------------------
	if not _comes_before("_draw_nature(\n_draw_props()", "_draw_nature(", "_draw_props()"):
		push_error("the order scanner refused a fabricated body that draws the dressing first; it cannot say yes")
		return false
	if _comes_before("_draw_props()\n_draw_nature(", "_draw_nature(", "_draw_props()"):
		push_error("the order scanner passed a fabricated body that draws the props first; it cannot say no")
		return false
	var district: String = _function_body(MAIN_GD, "_draw_district")
	if not _comes_before(district, "_draw_roofs(", "_draw_nature(") or not _comes_before(district, "_draw_nature(", "_draw_props()"):
		push_error("_draw_district does not call _draw_nature( after _draw_roofs( and before _draw_props(); the dressing would draw over the props or not at all")
		return false
	var draw_nature: String = _function_body(MAIN_GD, "_draw_nature")
	if draw_nature.is_empty():
		push_error("could not read _draw_nature out of %s" % MAIN_GD)
		return false
	var m: String = _missing_needle(draw_nature, ["Dressing.nature_tiles_cached(", "_nature_cache_for()", "Appearance.hang_rect(", "Appearance.resolve("])
	if not m.is_empty():
		push_error("_draw_nature does not contain %s" % m)
		return false
	# The cache is emptied by everything its picks were made against. The scanner is shown a body
	# that forgets the vehicle generation before it is trusted on the real one.
	var cache_body: String = _function_body(MAIN_GD, "_nature_cache_for")
	var cache_needles: Array = ["int(map.vehicle_generation)", "is_same(map, _nature_cache_map)", "gen == _nature_cache_gen", "int(world.seed) == _nature_cache_seed", "is_same(world.content, _nature_cache_content)", "_nature_cache = {}"]
	var forgetful: String = "int(map.vehicle_generation)\nis_same(map, _nature_cache_map) and int(world.seed) == _nature_cache_seed and is_same(world.content, _nature_cache_content)\n_nature_cache = {}"
	if _missing_needle(forgetful, cache_needles) != "gen == _nature_cache_gen":
		push_error("the cache scanner did not name the missing generation comparison in a body that forgets it; it cannot say no")
		return false
	var missing_cache: String = _missing_needle(cache_body, cache_needles)
	if not missing_cache.is_empty():
		push_error("_nature_cache_for does not contain %s; a picture could outlive what it was picked against" % missing_cache)
		return false
	if draw_nature.contains("draw_set_transform(") or draw_nature.contains("world.components") or draw_nature.contains("set_component("):
		push_error("_draw_nature sets a transform or touches a component; dressing is a picture and nothing else")
		return false

	# --- the shipped suburb ------------------------------------------------------------------
	var boot: Dictionary = SimBoot.playable(CANON_SEED, GATE_SIZE)
	var sworld: Variant = boot["world"]
	var smap: Variant = boot["map"]
	var sblock: Dictionary = Dressing.block_of(sworld)
	var sw: int = int(smap.w)
	var sh: int = int(smap.h)
	var everyone := FakeSeen.new()
	for ty2 in sh:
		for tx2 in sw:
			everyone.tiles[Vector2i(tx2, ty2)] = true
	var picks: Array[Dictionary] = Dressing.nature_tiles(sblock, smap, everyone, int(sworld.seed), {"minX": 0.0, "minY": 0.0, "maxX": float(sw), "maxY": float(sh)})
	if picks.is_empty():
		push_error("the shipped suburb at %d took no nature picture at all; NATURE has nothing to judge on it" % GATE_SIZE)
		return false
	var kinds: Dictionary = {}
	for pick3 in picks:
		var tx3: int = int(pick3["tx"])
		var ty3: int = int(pick3["ty"])
		if int(SimTileMap.tile_at(smap, tx3, ty3)) != SimTileMap.Tile.Floor or SimTileMap.is_indoors(smap, tx3, ty3):
			push_error("a nature picture landed on (%d,%d), which is not open outdoor floor" % [tx3, ty3])
			return false
		if Appearance.resolve(String(pick3["key"])) == null:
			push_error("a nature picture at (%d,%d) names '%s', which resolves no texture" % [tx3, ty3, String(pick3["key"])])
			return false
		kinds[String(pick3["key"])] = int(kinds.get(String(pick3["key"]), 0)) + 1
	if kinds.size() < 2:
		push_error("the shipped suburb took only %s; the variation is dead" % str(kinds))
		return false
	sworld.vision.refresh(sworld, smap)
	var seen_only: Variant = sworld.vision.tiles_for(int(sworld.player))
	if seen_only == null:
		push_error("the player's vision has not refreshed; NATURE has nothing to judge the seen subset on")
		return false
	for pick4 in Dressing.nature_tiles(sblock, smap, seen_only, int(sworld.seed), {"minX": 0.0, "minY": 0.0, "maxX": float(sw), "maxY": float(sh)}):
		if not (seen_only as Object).call("has_tile", int(pick4["tx"]), int(pick4["ty"])):
			push_error("nature_tiles answered (%d,%d), which the observer cannot see" % [int(pick4["tx"]), int(pick4["ty"])])
			return false

	var suburb_cache: Dictionary = {}
	var whole_suburb: Dictionary = {"minX": 0.0, "minY": 0.0, "maxX": float(sw), "maxY": float(sh)}
	if _pick_set(Dressing.nature_tiles_cached(sblock, smap, everyone, int(sworld.seed), whole_suburb, suburb_cache)) != _pick_set(picks):
		push_error("the cached picks over the shipped suburb differ from the uncached ones")
		return false

	_stash["nature_tiles"] = picks.size()
	_stash["nature_kinds"] = kinds.size()
	print("NATURE OK %d entries (every key an authored prop that resolves at most %dx%d, every surface real, every rarity >= 2); the roll picks %d of 32 seeds on open grass and none on paved, walled, indoor, door-flanked, tree, heap, deep-water or edge tiles; reeds need water beside them and take a ford as water; an entry that misses its ground falls through; malformed blocks pick nothing; the roll is hash_at's own number on %d rolled tiles over four rarities and eight seeds; nature_tiles is a subset of seen and of bounds; the chunk cache answers the uncached picks over four windows and four observers (%d picks), serves a poisoned chunk and forgets it when emptied, and _nature_cache_for is emptied by the vehicle generation, the seed and the content; _draw_nature follows _draw_roofs and precedes _draw_props; suburb@%d takes %d pictures in %d kinds %s, cached and uncached alike" % [(entries as Array).size(), NATURE_MAX_W, NATURE_MAX_H, yes, rolls, cache_compared, GATE_SIZE, picks.size(), kinds.size(), str(kinds)])
	return true


# --- lane 12: SHIPPED ------------------------------------------------------------------------


const WET_DISTRICT: String = "district.forest_edge"
const DRY_DISTRICT: String = "district.residential_suburb"
const REGION_PATH: String = "res://content/regions/main_area.json"
const REEDS_KEY: String = "nature_reeds"
# Grounds a shipped nature entry may never name: a bush does not grow through a road or out of a
# channel. Open outdoor floor is everything else the schema lists.
const NATURE_FORBIDDEN_SURFACES: Array[String] = ["paved", "water"]


# Whether a region's text names a district. Text, not a parse, so a region that moves its cells
# under another key still counts; the fabrication in the lane proves it can say no.
func _region_names(text: String, district_id: String) -> bool:
	return text.contains("\"%s\"" % district_id)


# Every entry that lies on a ground it may not, as words.
func _nature_entries_on_forbidden_ground(entries: Array) -> Array[String]:
	var out: Array[String] = []
	for raw in entries:
		if not (raw is Dictionary):
			continue
		for surface in (raw as Dictionary).get("surfaces", []) as Array:
			if NATURE_FORBIDDEN_SURFACES.has(String(surface)):
				out.append("%s on %s" % [String((raw as Dictionary).get("key", "")), String(surface)])
	return out


func _reeds_in(picks: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pick in picks:
		if String(pick["key"]) == REEDS_KEY:
			out.append(pick)
	return out


func _has_water_beside(map: Variant, tx: int, ty: int) -> bool:
	for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = tx + (step as Vector2i).x
		var ny: int = ty + (step as Vector2i).y
		if nx < 0 or ny < 0 or nx >= int(map.w) or ny >= int(map.h):
			continue
		if int(map.surfaces[ny * int(map.w) + nx]) == SimTileMap.SURFACE_WATER:
			return true
	return false


func _picks_over(block: Dictionary, map: Variant) -> Array[Dictionary]:
	var everyone := FakeSeen.new()
	for ty in int(map.h):
		for tx in int(map.w):
			everyone.tiles[Vector2i(tx, ty)] = true
	return Dressing.nature_tiles(block, map, everyone, CANON_SEED, {"minX": 0.0, "minY": 0.0, "maxX": float(map.w), "maxY": float(map.h)})


func _the_shipped_maps_take_the_nature_they_should() -> bool:
	Appearance.forget()
	var block: Dictionary = Dressing.block_of(World.new(_fixture()))
	var raw_entries: Variant = block.get("nature")
	if not (raw_entries is Array) or (raw_entries as Array).is_empty():
		push_error("SHIPPED: dressing.street declares no nature list; the lane has nothing to judge")
		return false
	var entries: Array = raw_entries as Array

	# The wet district is a shipped one: the region the game boots names it. True negative on a
	# text that does not.
	var region_text: String = FileAccess.get_file_as_string(REGION_PATH)
	if not _region_names(region_text, WET_DISTRICT):
		push_error("SHIPPED: %s does not name %s; the map reeds are judged on is not one the game ships" % [REGION_PATH, WET_DISTRICT])
		return false
	if _region_names("{\"cells\": [{\"district\": \"district.town_center\"}]}", WET_DISTRICT):
		push_error("SHIPPED: the region reader found a district in a text that does not name it")
		return false

	# Content: nothing is dressed onto a road or into a channel; the scanner refuses one that is.
	var strays: Array[String] = _nature_entries_on_forbidden_ground(entries)
	if not strays.is_empty():
		push_error("SHIPPED: shipped nature entries lie on ground they may not: %s" % ", ".join(strays))
		return false
	var probe_strays: Array[String] = _nature_entries_on_forbidden_ground([{"key": "nature_bush", "surfaces": ["grass", "paved"], "rarity": 5}])
	if probe_strays != ["nature_bush on paved"]:
		push_error("SHIPPED: the forbidden-ground scanner answered %s for a bush on a road; it cannot say no" % str(probe_strays))
		return false

	var tree: Dictionary = ContentLoader.load_tree()

	# Reeds on the forest: placed, each beside water, and not the only kind there.
	var wet: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, tree, WET_DISTRICT)
	var wet_picks: Array[Dictionary] = _picks_over(block, wet)
	var reeds: Array[Dictionary] = _reeds_in(wet_picks)
	if reeds.is_empty():
		push_error("SHIPPED: %s at %d took no reeds; no shipped map places them and the reeds art is drawn by nothing" % [WET_DISTRICT, GATE_SIZE])
		return false
	if Appearance.resolve(REEDS_KEY) == null:
		push_error("SHIPPED: %s resolves no texture" % REEDS_KEY)
		return false
	for pick in reeds:
		if not _has_water_beside(wet, int(pick["tx"]), int(pick["ty"])):
			push_error("SHIPPED: reeds at (%d,%d) on %s have no water beside them" % [int(pick["tx"]), int(pick["ty"]), WET_DISTRICT])
			return false
	if reeds.size() == wet_picks.size():
		push_error("SHIPPED: every nature picture on %s is reeds; the other kinds are dead there" % WET_DISTRICT)
		return false

	# True negatives: the same forest with its water turned to grass takes no reeds and still
	# dresses, and the dry suburb takes none.
	var dried: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, tree, WET_DISTRICT)
	for i in dried.surfaces.size():
		if int(dried.surfaces[i]) == SimTileMap.SURFACE_WATER:
			dried.surfaces[i] = SimSurface.Surface.Grass
	var dried_picks: Array[Dictionary] = _picks_over(block, dried)
	if dried_picks.is_empty() or not _reeds_in(dried_picks).is_empty():
		push_error("SHIPPED: the forest with its water turned to grass took %d pictures of which %d were reeds; want some pictures and no reeds" % [dried_picks.size(), _reeds_in(dried_picks).size()])
		return false
	var dry: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, tree, DRY_DISTRICT)
	var dry_reeds: int = _reeds_in(_picks_over(block, dry)).size()
	if dry_reeds != 0:
		push_error("SHIPPED: %s took %d reeds and declares no water" % [DRY_DISTRICT, dry_reeds])
		return false

	_stash["reeds"] = reeds.size()
	print("SHIPPED OK %s@%d places %d reeds among %d nature pictures, each beside a water surface; the same map dried to grass places none of %d pictures, and %s none; the region names the district; no shipped entry lies on paved ground or in water (a bush on a road, a region without the district and a dried forest are all refused)" % [WET_DISTRICT, GATE_SIZE, reeds.size(), wet_picks.size(), dried_picks.size(), DRY_DISTRICT])
	return true


# --- lane 11: INERT --------------------------------------------------------------------------


# The pictures dressing draws, by name: every authored key of kind tree or prop that is not a
# thing the sim spawned. The sim must never name one -- a sim that reads `nature_bush` has made a
# picture a fact.
func _picture_keys() -> Array[String]:
	var out: Array[String] = []
	for kind in ["tree", "prop"]:
		for key in _authored_keys_of_kind(kind):
			out.append(key)
	return out


# Every .gd file under a res:// directory, sorted.
func _gd_files_under(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_gd_files_under(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.ends_with(".gd"):
			out.append(dir_path.path_join(file))
	out.sort()
	return out


# The comments taken out of one source text, line by line -- _code_of's rule on a string.
func _strip_comments(text: String) -> String:
	var out: String = ""
	for line in text.split("\n"):
		var at: int = String(line).find("#")
		out += (String(line) if at < 0 else String(line).substr(0, at)) + "\n"
	return out


# What in this source text ties the sim to the presentation layer or to a dressing picture: the
# first offending needle, or "". The needles are the presentation directory, the dressing
# resolver's name and every picture key.
func _sim_tie_in(code: String, pictures: Array[String]) -> String:
	for needle in ["res://presentation", "presentation/dressing", "Dressing.", "dressing.street"]:
		if code.contains(needle):
			return needle
	for key in pictures:
		if code.contains("\"%s\"" % key):
			return "\"%s\"" % key
	return ""


# A digest of everything the map holds that the sim reads: tiles, surfaces, indoors, overlays and
# the vehicle manifest. `hash` of an Array hashes its contents.
func _map_digest(map: Variant) -> int:
	return hash([map.tiles, map.surfaces, map.indoors, map.overlays, map.vehicles])


func _dressing_is_never_sim_state() -> bool:
	var pictures: Array[String] = _picture_keys()
	if pictures.is_empty():
		push_error("authored.json declares no tree or prop; INERT has nothing to judge")
		return false

	# --- 1. nothing under godot/sim/ reads presentation or names a picture ---------------------
	# The scanner is shown a source that ties the two together before it is trusted on the real
	# ones: one that answers "" for everything is a gate that cannot fail.
	if _sim_tie_in("var d = preload(\"res://presentation/dressing.gd\")", pictures).is_empty():
		push_error("the sim-tie scanner passed a source that preloads the presentation layer; it cannot say no")
		return false
	if _sim_tie_in("var look = \"%s\"" % pictures[0], pictures).is_empty():
		push_error("the sim-tie scanner passed a source that names a picture key; it cannot say no")
		return false
	if not _sim_tie_in(_strip_comments("# res://presentation is presentation's\nvar x = 1"), pictures).is_empty():
		push_error("the sim-tie scanner refused a comment; sim comments say where presentation lives and that is fine")
		return false
	var files: Array[String] = _gd_files_under(SIM_DIR)
	if files.size() < 50:
		push_error("only %d sim files were found under %s; the walk is not reaching the sim" % [files.size(), SIM_DIR])
		return false
	for path in files:
		var tied: String = _sim_tie_in(_strip_comments(FileAccess.get_file_as_string(path)), pictures)
		if not tied.is_empty():
			push_error("%s names %s; the sim must not know how anything is drawn" % [path, tied])
			return false

	# --- 2. a whole-district pick leaves the map exactly as it was -----------------------------
	var boot: Dictionary = SimBoot.playable(CANON_SEED, GATE_SIZE)
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	var before: int = _map_digest(map)
	var everyone := FakeSeen.new()
	var w: int = int(map.w)
	var h: int = int(map.h)
	for ty in h:
		for tx in w:
			everyone.tiles[Vector2i(tx, ty)] = true
	var block: Dictionary = Dressing.block_of(world)
	var bounds: Dictionary = {"minX": 0.0, "minY": 0.0, "maxX": float(w), "maxY": float(h)}
	var picks: Array[Dictionary] = Dressing.nature_tiles(block, map, everyone, int(world.seed), bounds)
	for ty2 in h:
		for tx2 in w:
			Dressing.heap_key(block, map, int(world.seed), tx2, ty2)
			Dressing.tree_key(block, int(world.seed), tx2, ty2)
	Dressing.tree_tiles(map, everyone, bounds)
	if picks.is_empty():
		push_error("the pick found nothing on the shipped suburb; INERT has nothing to judge")
		return false
	if _map_digest(map) != before:
		push_error("running the dressing picks over the district changed the map; dressing must read the map and write nothing")
		return false
	# The digest can say yes: one tile changed is a different digest, and a picker that mutates the
	# map is caught by the same comparison.
	var mutated: Variant = SimTileMap.blank_map(6, 6)
	var clean: int = _map_digest(mutated)
	mutated.surfaces[7] = SimSurface.Surface.Undergrowth
	if _map_digest(mutated) == clean:
		push_error("the map digest did not change when a surface changed; it reads nothing")
		return false
	var greedy: Variant = SimTileMap.blank_map(6, 6)
	var greedy_before: int = _map_digest(greedy)
	_a_picker_that_writes(greedy)
	if _map_digest(greedy) == greedy_before:
		push_error("a picker that wrote a tile left the digest unchanged; the unmoved-map assertion cannot say no")
		return false

	# --- 3. no picked tile is solid, blocked or opaque ---------------------------------------
	for pick in picks:
		var px: int = int(pick["tx"])
		var py: int = int(pick["ty"])
		var tile: int = int(SimTileMap.tile_at(map, px, py))
		if bool(SimTileMap.SOLID[tile]) or SimTileMap.is_solid(map, px, py) or world.is_blocked_tile(px, py):
			push_error("a nature picture stands on (%d,%d), a tile the sim treats as solid or blocked" % [px, py])
			return false
		if int(SimTileMap.OPACITY[tile]) == SimTileMap.Opacity.Opaque:
			push_error("a nature picture stands on (%d,%d), a tile the sim treats as opaque" % [px, py])
			return false
	# The same predicate refuses a real tree: a tile the sim blocks is caught.
	var tree_at: Vector2i = Vector2i(-1, -1)
	for ty3 in h:
		for tx3 in w:
			if int(SimTileMap.tile_at(map, tx3, ty3)) == SimTileMap.Tile.Tree:
				tree_at = Vector2i(tx3, ty3)
				break
		if tree_at.x >= 0:
			break
	if tree_at.x < 0:
		push_error("the shipped suburb has no Tree tile to prove the solidity predicate on")
		return false
	if not (bool(SimTileMap.SOLID[int(SimTileMap.tile_at(map, tree_at.x, tree_at.y))]) or world.is_blocked_tile(tree_at.x, tree_at.y)):
		push_error("the solidity predicate passed a Tree tile; it cannot say no")
		return false

	# --- 4. no component of a booted world names a picture ----------------------------------
	var saved: String = world.serialize()
	for key in pictures:
		if saved.contains("\"%s\"" % key):
			push_error("the booted world's serialised state names the picture %s; dressing has become sim state" % key)
			return false
	var scratch: Variant = World.new(_fixture())
	var carrier: int = int(scratch.entities.spawn())
	scratch.components.set_component(carrier, "look", {"key": pictures[0]})
	if not scratch.serialize().contains("\"%s\"" % pictures[0]):
		push_error("a component carrying a picture key did not appear in the serialised state; the detector cannot say yes")
		return false

	print("INERT OK %d sim files name no picture and read no presentation (the scanner refuses a fabricated preload and a fabricated key, and accepts a comment); a whole-district pick over %d Floor picks left the map digest unmoved (a changed surface and a writing picker both move it); no picked tile is solid, blocked or opaque (a Tree tile is); the serialised world names none of %d picture keys (a fabricated carrier is found)" % [files.size(), picks.size(), pictures.size()])
	return true


# A picker that writes to the map it was asked to read -- the fabrication the unmoved-map
# assertion has to refuse. Never called on a real map.
func _a_picker_that_writes(map: Variant) -> void:
	map.tiles[3] = SimTileMap.Tile.Wall


# --- readers -------------------------------------------------------------------------------


# The source text of one function, from its `func` line to the next top-level `func` -- the
# check_topdown.gd / check_roof_look.gd convention: a CanvasItem draw pass cannot run headless.
func _function_body(path: String, name: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var lines: PackedStringArray = f.get_as_text().split("\n")
	var out: String = ""
	var inside: bool = false
	for line in lines:
		if line.begins_with("func %s(" % name):
			inside = true
			continue
		if inside and line.begins_with("func "):
			break
		if inside:
			out += line + "\n"
	return out


# A file's source with the comments taken out -- check_wrecks.gd's convention, reused verbatim:
# the forbidden-name scan has to read *code*, and dressing.gd's own header explains the no-RNG
# rule using the word `randi` in a backtick, which a raw-text scan cannot tell from a call.
func _code_of(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var out: String = ""
	for line in f.get_as_text().split("\n"):
		var at: int = String(line).find("#")
		out += (String(line) if at < 0 else String(line).substr(0, at)) + "\n"
	return out
