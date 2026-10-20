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
# Thirteen lanes, every assertion with a true positive and a true negative, because a gate that
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
#   FURNISH      the furnishings ("Furnishings and container kinds"): a table, a chair, a shelf and a
#                medical cabinet indoors, a dumpster, a barrier, a cone and a post outside. The eight
#                pictures are each an authored prop that resolves, named by the block, with the
#                workbench and the three props taller than a tile refused by name; the pick lands on
#                the right side of the wall (`where`), on the right surface, with the same kind of
#                floor either side, never in a doorway, never beside a door, never on a wall, door,
#                tree, heap or water tile and `beside: wall` only against one -- each refused on a
#                fabricated map; the roll is hash_at's own number on its own salt; furnishing_tiles
#                is a subset of seen (nothing draws through a wall), the chunk cache answers what
#                the uncached pick does; a tile a real prop stands on is skipped; the draw pass is
#                reached in the order the plan named; and each of the eight kinds is placed on a
#                shipped district, none in a doorway.
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
const RoadPaint = preload("res://presentation/road_paint.gd")

const MAIN_GD: String = "res://presentation/main.gd"
const DRESSING_GD: String = "res://presentation/dressing.gd"
const AUTHORED_PATH: String = "res://assets/sprites/authored.json"
const SIM_DIR: String = "res://sim"
const CANON_SEED: int = 20260805

# Every picture the fabricated blocks name, at its authored canvas (the shipped suburb's `sizes`).
const FABRICATED_SIZES: Dictionary = {
	"nature_bush": [32, 30], "nature_reeds": [24, 30], "nature_rock": [32, 22], "nature_stump": [24, 22], "nature_log": [48, 22],
	"prop_table": [40, 30], "prop_chair": [24, 30], "prop_shelf": [40, 30], "prop_medical_cabinet": [24, 30], "prop_fridge": [24, 38],
	"prop_dumpster": [48, 30], "prop_concrete_barrier": [48, 22], "prop_traffic_cone": [16, 22], "prop_fence_post": [16, 30],
	"prop_road_sign": [24, 38], "prop_streetlamp": [24, 62], "prop_barrel": [24, 30], "prop_pallet_stack": [32, 30], "prop_trash_bags": [32, 22],
}
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
	ok = _the_furnishings_stand_where_they_should() and ok
	ok = _the_roll_does_not_lattice() and ok
	ok = _the_clearing_holds() and ok
	ok = _the_placement_is_read() and ok
	ok = _the_occupancy_holds() and ok
	ok = _the_room_sets_and_the_edges_hold() and ok
	ok = _the_rooms_and_the_street_keep_their_measure() and ok
	ok = _the_second_review_holds() and ok
	ok = _the_old_street_stands() and ok
	ok = _the_rooms_stay_walkable() and ok
	ok = _the_tables_keep_a_chair() and ok
	ok = _the_stock_stays_in_storage() and ok
	ok = _the_litter_takes_its_shapes() and ok
	ok = _dressing_is_never_sim_state() and ok

	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	if seconds > BUDGET_SECONDS:
		push_error("check_trees ran %.1f s against a %.0f s budget" % [seconds, BUDGET_SECONDS])
		ok = false

	if ok:
		print(
			(
				"TREES_OK %d tree keys resolve at their authored canvases (widest canopy %d px, a tile is %d); the depth sort places body/tree/body; body_rect stands on the feet line at %d rungs; TREE_FADE_ALPHA %.2f fades only a point inside; TILES answered %d/%d seen trees on the hand map; the draw loop reaches every helper in order; Tile.Tree's opacity/solidity are unmoved and the pick stays a hash; suburb@%d stood %d of %d Tree tiles as drawable; the pictures stand inside their tier at alpha %d; NATURE dressed %d tiles of the suburb with %d kinds, all on open floor; SHIPPED placed %d reeds on forest_edge@%d, each beside water, none on the suburb or on the same map dried out; FURNISH placed %d furnishings of %d kinds over the shipped districts, indoors and out, none in a doorway; INERT: the map is byte-for-byte unmoved by a whole-district pick and no sim file or component names a picture; %.1f s of a %.0f s budget"
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
					int(_stash.get("furnish_picks", 0)),
					int(_stash.get("furnish_kinds", 0)),
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


# A picks list out of a Dictionary value (an untyped Array) as the typed list _pick_set takes.
func _as_picks(list: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pick in list:
		out.append(pick as Dictionary)
	return out


func _bush_block(rarity: int = 2) -> Dictionary:
	return {"sizes": FABRICATED_SIZES, "nature": [{"key": "nature_bush", "surfaces": ["grass"], "rarity": rarity}]}


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
	var reeds: Dictionary = {"sizes": FABRICATED_SIZES, "nature": [{"key": "nature_reeds", "surfaces": ["grass"], "rarity": 2, "beside": "water"}]}
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
	var ordered: Dictionary = {"sizes": FABRICATED_SIZES, "nature": [
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
		{}, {"sizes": FABRICATED_SIZES, "nature": []}, {"nature": "grass"}, {"sizes": FABRICATED_SIZES, "nature": [5]},
		{"sizes": FABRICATED_SIZES, "nature": [{"key": "", "surfaces": ["grass"], "rarity": 2}]},
		{"sizes": FABRICATED_SIZES, "nature": [{"key": "nature_bush", "surfaces": ["grass"], "rarity": 1}]},
		{"sizes": FABRICATED_SIZES, "nature": [{"key": "nature_bush", "surfaces": ["grass"], "rarity": 0}]},
		{"sizes": FABRICATED_SIZES, "nature": [{"key": "nature_bush", "surfaces": [], "rarity": 2}]},
		{"sizes": FABRICATED_SIZES, "nature": [{"key": "nature_bush", "surfaces": ["marble"], "rarity": 2}]},
		{"sizes": FABRICATED_SIZES, "nature": [{"key": "nature_bush", "surfaces": ["grass"], "rarity": 2, "beside": "lava"}]},
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
					# The roll itself is compared raw (`_nature_pick`); the kept answer is that roll or nothing,
					# because the overlap rule drops a bush that meets a neighbour's on this dense map.
					var raw_bush: String = Dressing._nature_pick(Dressing._nature_entries(block_r), grass, seed_val * Dressing._HASH_SEED, tx, ty)
					var kept_bush: String = Dressing.nature_key(block_r, grass, seed_val, tx, ty)
					if raw_bush != want or (not kept_bush.is_empty() and kept_bush != want):
						push_error("rarity %d seed %d tile (%d,%d): the raw roll answered '%s' and the kept pick '%s', the hash_at reference '%s'; the fast path's copy of the roll has drifted" % [int(rarity), seed_val, tx, ty, raw_bush, kept_bush, want])
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
	# The flat dressing is baked into the DECOR layer, so the frame draws none of it: _draw_world
	# brings the layers up to date and then draws the props fresh over them, and the bake's layer
	# match reaches _draw_decor, which draws the nature pictures before the flat furnishings.
	var district: String = _function_body(MAIN_GD, "_draw_world")
	if district.contains("_draw_nature(") or district.contains("_draw_furnishings("):
		push_error("_draw_world still draws the nature or the furnishings per frame; they are baked into DECOR")
		return false
	if not _comes_before(district, "_layers.call(\"frame\"", "_draw_props()"):
		push_error("_draw_world does not bring the baked layers up to date before _draw_props(); the props would draw under the bake")
		return false
	if _comes_before("_draw_props()\n_layers.call(\"frame\"", "_layers.call(\"frame\"", "_draw_props()"):
		push_error("the order scanner passed a fabricated body that draws the props before the layers; it cannot say no")
		return false
	var bake_layer: String = _function_body(MAIN_GD, "_bake_layer")
	if _missing_needle(bake_layer, ["WorldLayersRes.Layer.DECOR:", "_draw_decor(region)"]) != "":
		push_error("_bake_layer does not bake the DECOR layer through _draw_decor(region)")
		return false
	var draw_decor: String = _function_body(MAIN_GD, "_draw_decor")
	if draw_decor.is_empty():
		push_error("could not read _draw_decor out of %s" % MAIN_GD)
		return false
	var m: String = _missing_needle(draw_decor, ["Dressing.decor_picks(", "\"nature\"", "\"furnishings\"", "_placed_rect(", "Appearance.resolve(", "_pen.draw_texture_rect("])
	if not m.is_empty():
		push_error("_draw_decor does not contain %s" % m)
		return false
	if not _comes_before(draw_decor, "\"nature\"", "\"furnishings\""):
		push_error("_draw_decor draws the furnishings before the nature pictures")
		return false
	if draw_decor.contains("draw_set_transform(") or draw_decor.contains("world.components") or draw_decor.contains("set_component("):
		push_error("_draw_decor sets a transform or touches a component; dressing is a picture and nothing else")
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

	# The baked picks are the per-tile picks the lanes above checked. The whole suburb as one bake
	# region answers the same nature pictures tile for tile, and the same flat furnishings with the
	# standing ones left to the entity sort (the DECOR layer, world_layers.gd).
	var baked: Dictionary = Dressing.decor_picks(sblock, smap, int(sworld.seed), Rect2i(0, 0, sw, sh))
	if _pick_set(_as_picks(baked["nature"])) != _pick_set(picks):
		push_error("decor_picks answers different nature pictures over the shipped suburb than nature_tiles does; the bake would draw what the frame never did")
		return false
	var flat_furnishings: Array[Dictionary] = []
	for pick5 in Dressing.furnishing_tiles(sblock, smap, everyone, int(sworld.seed), whole_suburb):
		if not Dressing.furnishing_is_standing(sblock, String(pick5["key"])):
			flat_furnishings.append(pick5)
	if _pick_set(_as_picks(baked["furnishings"])) != _pick_set(flat_furnishings):
		push_error("decor_picks answers different flat furnishings over the shipped suburb than furnishing_tiles does; the bake would draw what the frame never did")
		return false

	_stash["nature_tiles"] = picks.size()
	_stash["nature_kinds"] = kinds.size()
	print("NATURE OK %d entries (every key an authored prop that resolves at most %dx%d, every surface real, every rarity >= 2); the roll picks %d of 32 seeds on open grass and none on paved, walled, indoor, door-flanked, tree, heap, deep-water or edge tiles; reeds need water beside them and take a ford as water; an entry that misses its ground falls through; malformed blocks pick nothing; the roll is hash_at's own number on %d rolled tiles over four rarities and eight seeds; nature_tiles is a subset of seen and of bounds; the chunk cache answers the uncached picks over four windows and four observers (%d picks), serves a poisoned chunk and forgets it when emptied, and decor_picks answers the suburb tile for tile as nature_tiles and furnishing_tiles do; _draw_decor is the DECOR layer and draws nature before furnishings; suburb@%d takes %d pictures in %d kinds %s, cached and uncached alike" % [(entries as Array).size(), NATURE_MAX_W, NATURE_MAX_H, yes, rolls, cache_compared, GATE_SIZE, picks.size(), kinds.size(), str(kinds)])
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


# --- lane 13: FURNISH ------------------------------------------------------------------------


# The furnishing pictures dressing.street must name: the outpost pack's props that stand inside a
# tile (docs/23, "Furnishings and container kinds"). Listed here by name and not read back off the
# block, because a block that lost one would then agree with itself. The workbench is not among
# them (the game has a real bench and a picture of one that does nothing would be a lie) and neither
# are the fridge, the road sign and the streetlamp, which are taller than a tile.
# The barrel, the pallet stack and the rubbish bags are scenery: none is a container, so none is
# searchable and none is a sim object, and none is drawn as one (the crates, footlockers and medical
# boxes are the container kinds, and stay out of the dressing).
const FURNISH_KEYS: Array[String] = ["prop_barrel", "prop_chair", "prop_concrete_barrier", "prop_dumpster", "prop_fence_post", "prop_medical_cabinet", "prop_pallet_stack", "prop_shelf", "prop_table", "prop_trash_bags", "prop_traffic_cone"]
const FURNISH_STANDING_KEYS: Array[String] = ["prop_fridge", "prop_road_sign", "prop_streetlamp"]
# The districts the game ships, judged for the kinds each takes.
const FURNISH_DISTRICTS: Array[String] = ["district.residential_suburb", "district.town_center", "district.industrial_park", "district.forest_edge"]


# A W x H all-Floor map, every tile indoors or none of them, on paved ground: the ground a
# furnishing pick has to say yes on before each fabricated negative takes one thing away.
func _room_map(w: int, h: int, indoors: bool) -> Variant:
	var map: Variant = SimTileMap.blank_map(w, h)
	for i in w * h:
		map.indoors[i] = 1 if indoors else 0
	return map


func _furnish_block(where: String, rarity: int = 2, surface: String = "paved", beside: String = "") -> Dictionary:
	var entry: Dictionary = {"key": "prop_table", "where": where, "surfaces": [surface], "rarity": rarity}
	if not beside.is_empty():
		entry["beside"] = beside
	return {"sizes": FABRICATED_SIZES, "furnishings": [entry]}


func _furnishing_size_fits(key: String, size: Vector2i, standing: bool) -> bool:
	if standing:
		return FURNISH_STANDING_KEYS.has(key) and size.y > NATURE_MAX_H and size.y <= 64 and size.x <= NATURE_MAX_W
	return size.x <= NATURE_MAX_W and size.y <= NATURE_MAX_H


func _furnish_hits(block: Dictionary, map: Variant, tx: int, ty: int, count: int) -> int:
	var hits: int = 0
	for seed_val in count:
		if not Dressing.furnishing_key(block, map, seed_val, tx, ty).is_empty():
			hits += 1
	return hits


func _furnishings_of(block: Dictionary, map: Variant, seed_val: int) -> Array[Dictionary]:
	var everyone := FakeSeen.new()
	for ty in int(map.h):
		for tx in int(map.w):
			everyone.tiles[Vector2i(tx, ty)] = true
	return Dressing.furnishing_tiles(block, map, everyone, seed_val, {"minX": 0.0, "minY": 0.0, "maxX": float(map.w), "maxY": float(map.h)})


func _the_furnishings_stand_where_they_should() -> bool:
	Appearance.forget()
	var world: Variant = World.new(_fixture())
	var block: Dictionary = Dressing.block_of(world)
	var entries: Variant = block.get("furnishings")
	if not (entries is Array) or (entries as Array).is_empty():
		push_error("dressing.street declares no `furnishings` list; FURNISH has nothing to judge")
		return false

	# --- what the content says ---------------------------------------------------------------
	var named: Dictionary = {}
	var where_of: Dictionary = {}
	for raw in entries as Array:
		if not (raw is Dictionary):
			push_error("a furnishing entry is not an object: %s" % str(raw))
			return false
		var entry: Dictionary = raw as Dictionary
		var key: String = String(entry.get("key", ""))
		var standing: bool = bool(entry.get("standing", false))
		var expected_kind: String = "standing" if standing else "prop"
		if not _authored_keys_of_kind(expected_kind).has(key):
			push_error("furnishing entry names '%s' as kind '%s', but authored.json declares no such kind" % [key, expected_kind])
			return false
		var tex: Variant = Appearance.resolve(key)
		if tex == null:
			push_error("furnishing key '%s' resolves no picture" % key)
			return false
		var size: Vector2i = Vector2i((tex as Texture2D).get_size())
		if size != Appearance.canvas_of(key):
			push_error("canvas_of('%s') is %s, the picture is %s" % [key, str(Appearance.canvas_of(key)), str(size)])
			return false
		if not _furnishing_size_fits(key, size, standing):
			push_error("furnishing key '%s' is %s and standing=%s; short props keep the %dx%d flat limit, and only the three named tall props may stand in the sort to 64 px high" % [key, str(size), str(standing), NATURE_MAX_W, NATURE_MAX_H])
			return false
		if int(entry.get("rarity", 0)) < 2:
			push_error("furnishing entry '%s' has rarity %s; under two it would land on every tile" % [key, str(entry.get("rarity"))])
			return false
		var where: String = String(entry.get("where", ""))
		if where != Dressing.FURNISH_INDOORS and where != Dressing.FURNISH_OUTDOORS:
			push_error("furnishing entry '%s' is where '%s', which the pick does not know" % [key, where])
			return false
		var surfaces: Variant = entry.get("surfaces")
		if not (surfaces is Array) or (surfaces as Array).is_empty():
			push_error("furnishing entry '%s' names no surface" % key)
			return false
		for surface_name in surfaces as Array:
			if Dressing.surface_named(String(surface_name)) < 0:
				push_error("furnishing entry '%s' names surface '%s', which SimSurface does not have" % [key, surface_name])
				return false
		var beside: String = String(entry.get("beside", ""))
		if Dressing._beside_code(beside) < 0:
			push_error("furnishing entry '%s' is beside '%s', which the pick does not know" % [key, beside])
			return false
		var group: String = String(entry.get("group", ""))
		if Dressing._group_code(group) < 0:
			push_error("furnishing entry '%s' is in group '%s', which the pick does not know" % [key, group])
			return false
		named[key] = true
		# A key may have an entry on each side of the walls (the barrel is street junk and a room's
		# stores), so a picture is judged against every side its key's entries name.
		if not where_of.has(key):
			where_of[key] = {}
		(where_of[key] as Dictionary)[where] = true
	# The dead-socket half, both directions: every furnishing the pack ships that fits a tile is
	# named, and nothing else is -- the workbench and the three tall props are refused by name.
	for want in FURNISH_KEYS:
		if not named.has(want):
			push_error("dressing.street names no furnishing '%s'; the pack's picture is art nothing draws" % want)
			return false
	for want_standing in FURNISH_STANDING_KEYS:
		if not named.has(want_standing) or not Dressing.furnishing_is_standing(block, want_standing):
			push_error("dressing.street does not explicitly route tall furnishing '%s' into the entity sort" % want_standing)
			return false
	for got in named.keys():
		if not FURNISH_KEYS.has(String(got)) and not FURNISH_STANDING_KEYS.has(String(got)):
			push_error("dressing.street furnishes '%s', which is not one of the eleven flat or three explicitly standing furnishings" % String(got))
			return false
	if FURNISH_KEYS.has("prop_workbench") or FURNISH_KEYS.has("prop_fridge") or FURNISH_KEYS.has("prop_streetlamp") or FURNISH_KEYS.has("prop_road_sign"):
		push_error("FURNISH_KEYS treats a standing prop or real bench as a flat furnishing")
		return false
	if not _furnishing_size_fits("prop_table", Vector2i(40, 32), false) or _furnishing_size_fits("prop_fridge", Vector2i(24, 38), false) or not _furnishing_size_fits("prop_fridge", Vector2i(24, 38), true) or _furnishing_size_fits("prop_table", Vector2i(40, 32), true) or _furnishing_size_fits("prop_streetlamp", Vector2i(24, 65), true):
		push_error("FURNISH size predicate did not preserve the flat ceiling, require explicit tall routing, or cap standing art at 64 px")
		return false
	# The existing limit still refuses a tall entry unless it opts into the standing route, and
	# the flag cannot be used to smuggle a short ordinary prop into the entity sort.
	var tall_unflagged: Dictionary = {"sizes": FABRICATED_SIZES, "furnishings": [{"key": "prop_fridge", "where": "indoors", "surfaces": ["paved"], "rarity": 2}]}
	var tall_flagged: Dictionary = {"sizes": FABRICATED_SIZES, "furnishings": [{"key": "prop_fridge", "where": "indoors", "surfaces": ["paved"], "rarity": 2, "standing": true}]}
	if Dressing.furnishing_is_standing(tall_unflagged, "prop_fridge") or not Dressing.furnishing_is_standing(tall_flagged, "prop_fridge") or Dressing.furnishing_is_standing(tall_flagged, "prop_table"):
		push_error("the optional standing flag does not default false or resolve only for the named key")
		return false

	# --- the pick, on hand maps, both ways -----------------------------------------------------
	var w: int = 12
	var h: int = 6
	var room: Variant = _room_map(w, h, true)
	var indoor_table: Dictionary = _furnish_block("indoors")
	var yes: int = _furnish_hits(indoor_table, room, 5, 2, 32)
	if yes == 0 or yes == 32:
		push_error("a rarity-2 indoor table on open indoor floor picked %d of 32 seeds; the roll is not a roll" % yes)
		return false
	for seed_val in 8:
		if Dressing.furnishing_key(indoor_table, room, seed_val, 5, 2) != Dressing.furnishing_key(indoor_table, room, seed_val, 5, 2):
			push_error("the furnishing pick answered differently twice for one seed and tile; it is not a pure hash")
			return false
	var differ: int = 0
	for seed_val in 32:
		if Dressing.furnishing_key(indoor_table, room, seed_val, 3, 1).is_empty() != Dressing.furnishing_key(indoor_table, room, seed_val, 8, 4).is_empty():
			differ += 1
	if differ == 0:
		push_error("two tiles picked identically over 32 seeds; the tile is not reaching the hash")
		return false
	# `where` is read both ways: the indoor entry picks nothing outdoors, the outdoor entry nothing
	# indoors, and each picks on its own ground.
	var yard: Variant = _room_map(w, h, false)
	var outdoor_table: Dictionary = _furnish_block("outdoors")
	if _furnish_hits(indoor_table, yard, 5, 2, 32) != 0:
		push_error("an indoor furnishing picked an outdoor tile; `where` is not read")
		return false
	if _furnish_hits(outdoor_table, room, 5, 2, 32) != 0:
		push_error("an outdoor furnishing picked an indoor tile; `where` is not read")
		return false
	# The tile's own side is read, not only its neighbours': a one-tile gap outdoors between two
	# indoor tiles takes no indoor furnishing, and an indoor tile between two outdoor ones takes no
	# outdoor one.
	var gap: Variant = _room_map(w, h, true)
	gap.indoors[2 * w + 5] = 0
	if _furnish_hits(indoor_table, gap, 5, 2, 32) != 0:
		push_error("an indoor furnishing picked an outdoor tile between two indoor ones; the tile's own side is not read")
		return false
	var nook: Variant = _room_map(w, h, false)
	nook.indoors[2 * w + 5] = 1
	if _furnish_hits(outdoor_table, nook, 5, 2, 32) != 0:
		push_error("an outdoor furnishing picked an indoor tile between two outdoor ones; the tile's own side is not read")
		return false
	var yard_yes: int = _furnish_hits(outdoor_table, yard, 5, 2, 32)
	if yard_yes == 0 or yard_yes == 32:
		push_error("a rarity-2 outdoor furnishing on an open yard picked %d of 32 seeds; the outdoor roll is not a roll" % yard_yes)
		return false
	# Each negative takes one thing away from the ground the positive stood on.
	var grassy: Variant = _room_map(w, h, true)
	grassy.surfaces[2 * w + 5] = SimSurface.Surface.Grass
	if _furnish_hits(indoor_table, grassy, 5, 2, 32) != 0:
		push_error("a paved-only furnishing picked a grass tile; the surface list is not read")
		return false
	# The footprint rule judges the tiles a picture's own rect reaches, so the side negatives use a
	# fabricated table two tiles wide, which reaches both side neighbours at every offset it can take.
	var wide_table: Dictionary = _furnish_block("indoors")
	wide_table["sizes"] = FABRICATED_SIZES.duplicate()
	wide_table["sizes"]["prop_table"] = [64, 30]
	if _furnish_hits(wide_table, room, 5, 2, 32) == 0:
		push_error("a two-tile table never picked open indoor floor; the side negatives below would judge nothing")
		return false
	for taken in [
		{"name": "a wall to the east", "idx": 2 * w + 6, "tile": SimTileMap.Tile.Wall},
		{"name": "a wall to the west", "idx": 2 * w + 4, "tile": SimTileMap.Tile.Wall},
		{"name": "a door to the east", "idx": 2 * w + 6, "tile": SimTileMap.Tile.Door},
		{"name": "a door to the north", "idx": 1 * w + 5, "tile": SimTileMap.Tile.Door},
		{"name": "a door to the south", "idx": 3 * w + 5, "tile": SimTileMap.Tile.Door},
		{"name": "itself a wall", "idx": 2 * w + 5, "tile": SimTileMap.Tile.Wall},
		{"name": "itself a door", "idx": 2 * w + 5, "tile": SimTileMap.Tile.Door},
		{"name": "itself a tree", "idx": 2 * w + 5, "tile": SimTileMap.Tile.Tree},
		{"name": "itself a heap", "idx": 2 * w + 5, "tile": SimTileMap.Tile.Low},
		{"name": "itself deep water", "idx": 2 * w + 5, "tile": SimTileMap.Tile.Water},
	]:
		var blocked: Variant = _room_map(w, h, true)
		blocked.tiles[int((taken as Dictionary)["idx"])] = int((taken as Dictionary)["tile"])
		if _furnish_hits(wide_table, blocked, 5, 2, 32) != 0:
			push_error("a furnishing picked a tile with %s; the open-floor rule is not read" % String((taken as Dictionary)["name"]))
			return false
	var threshold: Variant = _room_map(w, h, true)
	threshold.indoors[2 * w + 6] = 0
	if _furnish_hits(wide_table, threshold, 5, 2, 32) != 0:
		push_error("an indoor furnishing picked the tile beside the way out; it would overhang the doorway")
		return false
	if _furnish_hits(wide_table, room, 0, 2, 32) != 0 or _furnish_hits(wide_table, room, w - 1, 2, 32) != 0:
		push_error("a furnishing picked a tile on the map's edge, whose neighbour is off the map")
		return false
	# The footprint is the picture's own rect at its own offset: a 40-pixel table beside a wall to the
	# east stands there only where its offset keeps it off the wall, and at such an offset it does.
	var east_wall: Variant = _room_map(w, h, true)
	east_wall.tiles[2 * w + 6] = SimTileMap.Tile.Wall
	var fits_east: int = 0
	var reaches_east: int = 0
	var t_entry: Array = Dressing._furnishing_entries(indoor_table)[0]
	for seed_val in 64:
		var off: Vector2i = Dressing._offsets_for(t_entry, seed_val * Dressing._HASH_SEED, 5, 2)
		var reaches: bool = Dressing._art_rect(t_entry[Dressing.FE_EXTENT], off.x, off.y).end.x > Dressing.ART_PER_TILE
		var picked_east: bool = not Dressing.furnishing_key(indoor_table, east_wall, seed_val, 5, 2).is_empty()
		if picked_east and reaches:
			push_error("seed %d: a table whose rect reaches the wall to the east stood beside it; the footprint is not read" % seed_val)
			return false
		if picked_east:
			fits_east += 1
		if reaches:
			reaches_east += 1
	if fits_east == 0 or reaches_east == 0:
		push_error("over 64 seeds a table beside an east wall stood %d times and reached it at %d offsets; the footprint rule judged nothing" % [fits_east, reaches_east])
		return false
	# A door two tiles away is not a door beside it: the same map still picks on the tile.
	var far_door: Variant = _room_map(w, h, true)
	far_door.tiles[0 * w + 5] = SimTileMap.Tile.Door
	if _furnish_hits(indoor_table, far_door, 5, 2, 32) == 0:
		push_error("a door two tiles north stopped a furnishing; the door rule reaches further than the adjoining tile")
		return false

	# `beside: wall` stands against a wall and nowhere else.
	var shelf: Dictionary = _furnish_block("indoors", 2, "paved", Dressing.FURNISH_BESIDE_WALL)
	if _furnish_hits(shelf, room, 5, 2, 32) != 0:
		push_error("a shelf stood in the middle of an open room with no wall beside it")
		return false
	for wall_at in [{"name": "north", "idx": 1 * w + 5}, {"name": "south", "idx": 3 * w + 5}]:
		var walled: Variant = _room_map(w, h, true)
		walled.tiles[int((wall_at as Dictionary)["idx"])] = SimTileMap.Tile.Wall
		if _furnish_hits(shelf, walled, 5, 2, 32) == 0:
			push_error("a shelf never stood with a wall to the %s over 32 seeds; the wall clause is dead" % String((wall_at as Dictionary)["name"]))
			return false

	# An entry that misses its ground lets the next entry try: the first hit wins, not the first entry.
	var ordered: Dictionary = {"sizes": FABRICATED_SIZES, "furnishings": [
		{"key": "prop_fence_post", "where": "indoors", "surfaces": ["grass"], "rarity": 2},
		{"key": "prop_chair", "where": "indoors", "surfaces": ["paved"], "rarity": 2},
	]}
	var got_post: bool = false
	var got_chair: bool = false
	for seed_val in 64:
		var picked: String = Dressing.furnishing_key(ordered, room, seed_val, 5, 2)
		got_post = got_post or picked == "prop_fence_post"
		got_chair = got_chair or picked == "prop_chair"
	if got_post or not got_chair:
		push_error("over paved floor the grass-only post picked=%s and the chair picked=%s; an entry that misses its ground must fall through to the next" % [str(got_post), str(got_chair)])
		return false

	# Malformed and absent: nothing, never a default.
	for bad in [
		{}, {"sizes": FABRICATED_SIZES, "furnishings": []}, {"furnishings": "table"}, {"sizes": FABRICATED_SIZES, "furnishings": [5]},
		{"sizes": FABRICATED_SIZES, "furnishings": [{"key": "", "where": "indoors", "surfaces": ["paved"], "rarity": 2}]},
		{"sizes": FABRICATED_SIZES, "furnishings": [{"key": "prop_table", "where": "indoors", "surfaces": ["paved"], "rarity": 1}]},
		{"sizes": FABRICATED_SIZES, "furnishings": [{"key": "prop_table", "where": "indoors", "surfaces": ["paved"], "rarity": 0}]},
		{"sizes": FABRICATED_SIZES, "furnishings": [{"key": "prop_table", "where": "indoors", "surfaces": [], "rarity": 2}]},
		{"sizes": FABRICATED_SIZES, "furnishings": [{"key": "prop_table", "where": "indoors", "surfaces": ["marble"], "rarity": 2}]},
		{"sizes": FABRICATED_SIZES, "furnishings": [{"key": "prop_table", "where": "attic", "surfaces": ["paved"], "rarity": 2}]},
		{"sizes": FABRICATED_SIZES, "furnishings": [{"key": "prop_table", "surfaces": ["paved"], "rarity": 2}]},
		{"sizes": FABRICATED_SIZES, "furnishings": [{"key": "prop_table", "where": "indoors", "surfaces": ["paved"], "rarity": 2, "beside": "lava"}]},
	]:
		if _furnish_hits(bad as Dictionary, room, 5, 2, 32) != 0:
			push_error("a malformed or empty furnishings block picked something: %s" % str(bad))
			return false
	# Nature and furnishings are two lists: a nature entry never furnishes and a furnishing never
	# lies on the nature pick.
	if _furnish_hits({"sizes": FABRICATED_SIZES, "nature": [{"key": "nature_bush", "surfaces": ["paved"], "rarity": 2}]}, room, 5, 2, 32) != 0:
		push_error("a nature entry furnished a tile; the two lists share a reader")
		return false
	if _picks_over_seeds(indoor_table, room, 5, 2, 32) != 0:
		push_error("the nature pick read the furnishings list; the two lists share a reader")
		return false

	# --- furnishing_tiles: a subset of seen, inside bounds ------------------------------------------
	var whole: Dictionary = {"minX": 0.0, "minY": 0.0, "maxX": float(w), "maxY": float(h)}
	var seen_all := FakeSeen.new()
	var expected: int = 0
	for ty in h:
		for tx in w:
			seen_all.tiles[Vector2i(tx, ty)] = true
			if not Dressing.furnishing_key(indoor_table, room, 3, tx, ty).is_empty():
				expected += 1
	var everything: Array[Dictionary] = Dressing.furnishing_tiles(indoor_table, room, seen_all, 3, whole)
	if everything.size() != expected or expected == 0:
		push_error("a see-everything set answered %d tiles, want exactly the %d the pick lands on" % [everything.size(), expected])
		return false
	if not Dressing.furnishing_tiles(indoor_table, room, null, 3, whole).is_empty():
		push_error("seen == null answered furnishings; nobody sees no chairs")
		return false
	var only_one: FakeSeen = _seen_of([Vector2i(int(everything[0]["tx"]), int(everything[0]["ty"]))])
	var one: Array[Dictionary] = Dressing.furnishing_tiles(indoor_table, room, only_one, 3, whole)
	if one.size() != 1 or int(one[0]["tx"]) != int(everything[0]["tx"]):
		push_error("seeing one picked tile answered %s, want exactly it" % str(one))
		return false
	if not Dressing.furnishing_tiles(indoor_table, room, FakeSeen.new(), 3, whole).is_empty():
		push_error("an empty seen set answered furnishings; a picture would draw where nobody can see -- through a wall")
		return false
	var standing_block: Dictionary = {"sizes": FABRICATED_SIZES, "furnishings": [{"key": "prop_fridge", "where": "indoors", "surfaces": ["paved"], "rarity": 2, "standing": true}]}
	var standing_plain: Array[Dictionary] = Dressing.furnishing_tiles(standing_block, room, seen_all, 3, whole)
	var standing_cached: Array[Dictionary] = Dressing.standing_furnishing_tiles_cached(standing_block, room, seen_all, 3, whole, {})
	if standing_plain.is_empty() or _pick_set(standing_plain) != _pick_set(standing_cached):
		push_error("the standing furnishing draw does not reuse the identical hash, visibility, bounds and cache pick")
		return false
	for standing_pick in standing_cached:
		if String(standing_pick["key"]) != "prop_fridge":
			push_error("the standing furnishing view returned an unrelated key: %s" % str(standing_pick))
			return false
	for pick in Dressing.furnishing_tiles(indoor_table, room, seen_all, 3, {"minX": 0.0, "minY": 0.0, "maxX": 2.0, "maxY": 2.0}):
		if int(pick["tx"]) > 2 or int(pick["ty"]) > 2:
			push_error("bounds excluding a tile still answered it: %s" % str(pick))
			return false

	# --- the roll is hash_at's number, mixed, on its own salt ----------------------------------------
	# The fast path folds the salt into its XOR and then runs `_mix`, so the reference is hash_at
	# passed through the same finaliser. Without `_mix` the low bits of hash_at fall on a lattice
	# (the first draft's grid); `_mix`'s own lane below holds that the mixed roll is not one.
	var rolls: int = 0
	for rarity in [2, 3, 7, 30]:
		var block_r: Dictionary = _furnish_block("indoors", int(rarity))
		for seed_val in 8:
			for ty in h:
				for tx in w:
					var want_pick: String = ""
					# The footprint, by hand: the table's rect at its offset, and every column it covers on the map.
					var r_entry: Array = Dressing._furnishing_entries(block_r)[0]
					var r_off: Vector2i = Dressing._offsets_for(r_entry, seed_val * Dressing._HASH_SEED, tx, ty)
					var r_left: int = 16 + r_off.x - 20
					var on_map: bool = tx + floori(float(r_left) / 32.0) >= 0 and tx + floori(float(r_left + 39) / 32.0) < w
					if on_map and Dressing._mix(Dressing.hash_at(seed_val, tx, ty, Dressing.SALT_FURNISH)) % int(rarity) == 0:
						want_pick = "prop_table"
					# The raw roll is compared (`_furnishing_raw`); the kept pick is that roll or nothing, since the
					# overlap rule drops a table that meets a neighbour's on this dense map.
					var raw_table: String = Dressing._furnishing_raw(Dressing._furnishing_entries(block_r), room, seed_val * Dressing._HASH_SEED, tx, ty, Rect2i())
					var kept_table: String = Dressing.furnishing_key(block_r, room, seed_val, tx, ty)
					if raw_table != want_pick or (not kept_table.is_empty() and kept_table != want_pick):
						push_error("rarity %d seed %d tile (%d,%d): the raw roll answered '%s' and the kept pick '%s', the hash_at reference '%s'; the fast path's copy of the roll has drifted" % [int(rarity), seed_val, tx, ty, raw_table, kept_table, want_pick])
						return false
					if not want_pick.is_empty():
						rolls += 1
	if rolls == 0:
		push_error("no tile rolled in the reference comparison; it judged nothing")
		return false
	var disagreed: bool = false
	# A rarity-2 roll reads one bit of the hash, and two neighbouring salts can share it, so the
	# wrong reference is tried on four salts and the comparison has to be shown to say no on one.
	for salt_off in [1, 2, 3, 4]:
		for seed_wrong in 8:
			for ty_wrong in h:
				for tx2 in range(1, w - 1):
					var mine: bool = Dressing.furnishing_key(indoor_table, room, seed_wrong, tx2, ty_wrong) == "prop_table"
					var theirs: bool = (Dressing.hash_at(seed_wrong, tx2, ty_wrong, Dressing.SALT_FURNISH + int(salt_off)) >> 8) % 2 == 0
					if mine != theirs:
						disagreed = true
	if not disagreed:
		push_error("a reference built on the wrong salt agreed with furnishing_key on every tile; the reference comparison cannot say no")
		return false

	# --- the chunk cache -----------------------------------------------------------------------
	var big_w: int = Dressing.NATURE_CHUNK * 3 + 5
	var big_h: int = Dressing.NATURE_CHUNK * 2 + 3
	var big: Variant = _room_map(big_w, big_h, true)
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
			var plain: Array[Dictionary] = Dressing.furnishing_tiles(indoor_table, big, observer, 11, window as Dictionary)
			var cached: Array[Dictionary] = Dressing.furnishing_tiles_cached(indoor_table, big, observer, 11, window as Dictionary, shared)
			if _pick_set(plain) != _pick_set(cached):
				push_error("the cached furnishings differ from the uncached ones over window %s: %d against %d" % [str(window), cached.size(), plain.size()])
				return false
			cache_compared += plain.size()
	if cache_compared == 0:
		push_error("the furnishing cache comparison judged no pick at all")
		return false
	var poisoned: Dictionary = {0: [{"tx": 1, "ty": 1, "key": "prop_chair"}]}
	var served: Array[Dictionary] = Dressing.furnishing_tiles_cached(indoor_table, big, big_seen, 11, {"minX": 0.0, "minY": 0.0, "maxX": 3.0, "maxY": 3.0}, poisoned)
	if served.size() != 1 or String(served[0]["key"]) != "prop_chair":
		push_error("a poisoned furnishing chunk was not served (%s); the cache is recomputing what it holds" % str(served))
		return false
	var emptied: Array[Dictionary] = Dressing.furnishing_tiles_cached(indoor_table, big, big_seen, 11, {"minX": 0.0, "minY": 0.0, "maxX": 3.0, "maxY": 3.0}, {})
	for pick2 in emptied:
		if String(pick2["key"]) == "prop_chair":
			push_error("an emptied furnishing cache still answered the poisoned pick; the cache is a static")
			return false

	# --- a real prop's tile is skipped ---------------------------------------------------------
	var scratch: Variant = World.new(_fixture())
	var bed: int = int(scratch.entities.spawn())
	scratch.components.set_component(bed, "position", {"x": 4.5, "y": 2.5})
	scratch.components.set_component(bed, "bed", {})
	if not Appearance.prop_tiles(scratch).has(Vector2i(4, 2)):
		push_error("prop_tiles missed a bed standing on (4,2); a chair would peek out from under it")
		return false
	if Appearance.prop_tiles(scratch).has(Vector2i(5, 2)) or Appearance.prop_tiles(World.new(_fixture())).size() != 0:
		push_error("prop_tiles named a tile no prop stands on; it would hide furniture for nothing")
		return false
	# entities.despawn, not world.despawn: the world's clears the components too, which would pass
	# without the alive check; the entity store's leaves them, the trap CLAUDE.md names.
	scratch.entities.despawn(bed)
	if not scratch.components.has_component(bed, "bed"):
		push_error("the fixture despawn removed the bed component; the alive assertion below would judge nothing")
		return false
	if Appearance.prop_tiles(scratch).has(Vector2i(4, 2)):
		push_error("prop_tiles named the tile of a despawned bed; components.query does not check alive and this must")
		return false

	# --- the draw pass is reached, in its place ------------------------------------------------
	# The flat furnishings are baked into the DECOR layer with the nature (the nature lane above
	# checks the order and the bake); the frame draws none of them, and a standing one is left to
	# the entity sort, which _standing_props answers below.
	var district: String = _function_body(MAIN_GD, "_draw_world")
	if district.contains("_draw_furnishings("):
		push_error("_draw_world still draws the furnishings per frame; they are baked into DECOR")
		return false
	var draw_decor: String = _function_body(MAIN_GD, "_draw_decor")
	var missing: String = _missing_needle(draw_decor, ["Dressing.decor_picks(", "\"furnishings\"", "_placed_rect(", "Appearance.resolve("])
	if not missing.is_empty():
		push_error("_draw_decor does not contain %s" % missing)
		return false
	if draw_decor.contains("draw_set_transform(") or draw_decor.contains("explored"):
		push_error("_draw_decor sets a transform or reads the remembered map; furniture is a picture on a tile the player sees and nothing else")
		return false
	# The standing rule moved with the picks: decor_picks reads the kept top and leaves a standing
	# furnishing out, and the shipped suburb checks that the baked flat list is exactly the flat picks
	# (the NATURE lane).
	var dressing_code: String = _code_of(DRESSING_GD)
	var decor_at: int = dressing_code.find("static func decor_picks(")
	var decor_body: String = dressing_code.substr(decor_at, dressing_code.find("\nstatic func", decor_at + 1) - decor_at) if decor_at >= 0 else ""
	if decor_body.is_empty() or not _comes_before(decor_body, "_kept_top(", "RANK_STANDING") or not _comes_before(decor_body, "RANK_STANDING", "(out[listing] as Array).append("):
		push_error("decor_picks does not leave the standing furnishings out before it appends a flat one")
		return false
	var standing_body: String = _function_body(MAIN_GD, "_standing_props")
	var draw_entities: String = _function_body(MAIN_GD, "_draw_entities")
	missing = _missing_needle(draw_entities, ["_standing_props(seen)", "_blit_standing(it, px_scale, focal_points)"])
	if not missing.is_empty() or not _comes_before(draw_entities, "_standing_props(seen)", "_blit_standing(it, px_scale, focal_points)"):
		push_error("_draw_entities does not append standing props and draw them in the sorted body pass: missing %s" % (missing if not missing.is_empty() else "ordered sort draw"))
		return false
	missing = _missing_needle(standing_body, ["Dressing.standing_furnishing_tiles_cached(", "_furnishing_cache_for()", "Appearance.prop_tiles(", "occupied.has(", "TopDownProjection.depth_of(", "out.append(", "fade_on_overlap"])
	if not missing.is_empty():
		push_error("_standing_props does not sort seen, unoccupied tall furnishings: missing %s" % missing)
		return false
	var standing_blit: String = _function_body(MAIN_GD, "_blit_standing")
	missing = _missing_needle(standing_blit, ["Appearance.body_rect(", "Dressing.tree_alpha(", "fade_on_overlap", "draw_texture_rect("])
	if not missing.is_empty():
		push_error("_blit_standing does not feet-anchor and fade a tall decoration on body overlap: missing %s" % missing)
		return false
	# Each accepted tall furnishing sorts between bodies on adjacent rows, and the shared fade rule
	# dims the picture only for the northern body's ground point inside its actual opaque rect.
	for key in FURNISH_STANDING_KEYS:
		var texture: Texture2D = Appearance.resolve(key)
		var gp_y: float = 6.0 * 32.0
		var rect: Rect2 = Appearance.body_rect(0.0, gp_y, Vector2(texture.get_size()), 1.0)
		var north: float = TopDownProjection.depth_of(0.5, 5.5)
		var prop_depth: float = TopDownProjection.depth_of(0.5, 6.0)
		var south: float = TopDownProjection.depth_of(0.5, 6.5)
		if not (north < prop_depth and prop_depth < south) or Dressing.tree_alpha(rect, [Vector2(0.0, 5.0 * 32.0)]) != Dressing.TREE_FADE_ALPHA or Dressing.tree_alpha(rect, [Vector2(0.0, 7.0 * 32.0)]) != 1.0:
			push_error("%s does not order body/prop/body and fade only while a body point is inside its picture" % key)
			return false
	if _missing_needle("occupied.has(x)\nseen == null", ["seen == null", "Dressing.furnishing_tiles_cached("]) != "Dressing.furnishing_tiles_cached(":
		push_error("the furnishing needle scanner did not name a missing call in a body that lacks it; it cannot say no")
		return false
	var cache_body: String = _function_body(MAIN_GD, "_furnishing_cache_for")
	var cache_needles: Array = ["int(map.vehicle_generation)", "is_same(map, _furnishing_cache_map)", "gen == _furnishing_cache_gen", "int(world.seed) == _furnishing_cache_seed", "is_same(world.content, _furnishing_cache_content)", "_furnishing_cache = {}"]
	var missing_cache: String = _missing_needle(cache_body, cache_needles)
	if not missing_cache.is_empty():
		push_error("_furnishing_cache_for does not contain %s; a picture could outlive what it was picked against" % missing_cache)
		return false

	# --- the shipped maps ---------------------------------------------------------------------
	var tree: Dictionary = ContentLoader.load_tree()
	var placed: Dictionary = {}
	var indoor_picks: int = 0
	var outdoor_picks: int = 0
	for district_id in FURNISH_DISTRICTS:
		var map: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, tree, district_id)
		for pick3 in _furnishings_of(block, map, CANON_SEED):
			var px: int = int(pick3["tx"])
			var py: int = int(pick3["ty"])
			var pkey: String = String(pick3["key"])
			placed[pkey] = int(placed.get(pkey, 0)) + 1
			var indoors: bool = SimTileMap.is_indoors(map, px, py)
			var sides: Dictionary = where_of.get(pkey, {})
			if not sides.has(Dressing.FURNISH_INDOORS if indoors else Dressing.FURNISH_OUTDOORS):
				push_error("%s: '%s' stands at (%d,%d) which is %s, its entries say %s" % [district_id, pkey, px, py, "indoors" if indoors else "outdoors", str(sides.keys())])
				return false
			if int(SimTileMap.tile_at(map, px, py)) != SimTileMap.Tile.Floor:
				push_error("%s: '%s' stands on (%d,%d), which is not a Floor tile" % [district_id, pkey, px, py])
				return false
			if Appearance.door_tiles(map).has(py * int(map.w) + px):
				push_error("%s: '%s' stands in the doorway at (%d,%d)" % [district_id, pkey, px, py])
				return false
			if indoors:
				indoor_picks += 1
			else:
				outdoor_picks += 1
	for want_key in FURNISH_KEYS + FURNISH_STANDING_KEYS:
		if not placed.has(want_key):
			push_error("no shipped district takes a '%s' at %d over %s; the pack's picture is drawn by a rule no map ever meets" % [want_key, GATE_SIZE, str(FURNISH_DISTRICTS)])
			return false
	if indoor_picks == 0 or outdoor_picks == 0:
		push_error("the shipped districts furnished %d indoor and %d outdoor tiles; both halves have to be met" % [indoor_picks, outdoor_picks])
		return false
	# TN: the doorway rule is not a rule about a map with no doors -- a fabricated door under a pick is seen.
	var boot: Dictionary = SimBoot.playable(CANON_SEED, GATE_SIZE)
	var sworld: Variant = boot["world"]
	var smap: Variant = boot["map"]
	sworld.vision.refresh(sworld, smap)
	var seen_only: Variant = sworld.vision.tiles_for(int(sworld.player))
	if seen_only == null:
		push_error("the player's vision has not refreshed; FURNISH has nothing to judge the seen subset on")
		return false
	var whole_suburb: Dictionary = {"minX": 0.0, "minY": 0.0, "maxX": float(smap.w), "maxY": float(smap.h)}
	var sblock: Dictionary = Dressing.block_of(sworld)
	for pick4 in Dressing.furnishing_tiles(sblock, smap, seen_only, int(sworld.seed), whole_suburb):
		if not (seen_only as Object).call("has_tile", int(pick4["tx"]), int(pick4["ty"])):
			push_error("furnishing_tiles answered (%d,%d), which the observer cannot see" % [int(pick4["tx"]), int(pick4["ty"])])
			return false
	var everyone := FakeSeen.new()
	for ty4 in int(smap.h):
		for tx4 in int(smap.w):
			everyone.tiles[Vector2i(tx4, ty4)] = true
	var all_picks: Array[Dictionary] = Dressing.furnishing_tiles(sblock, smap, everyone, int(sworld.seed), whole_suburb)
	var seen_picks: Array[Dictionary] = Dressing.furnishing_tiles(sblock, smap, seen_only, int(sworld.seed), whole_suburb)
	if all_picks.is_empty() or seen_picks.size() >= all_picks.size():
		push_error("the suburb's %d furnishings are all seen (%d); the seen subset judges nothing, or the observer sees through walls" % [all_picks.size(), seen_picks.size()])
		return false
	if _pick_set(Dressing.furnishing_tiles_cached(sblock, smap, everyone, int(sworld.seed), whole_suburb, {})) != _pick_set(all_picks):
		push_error("the cached furnishings over the shipped suburb differ from the uncached ones")
		return false
	# A door dropped onto a picked tile's north refuses that pick: the shipped rule is judged on a map
	# it can say no to, not only on the map it agrees with.
	var doored: Variant = SimWorldgen.generate(CANON_SEED, GATE_SIZE, tree, FURNISH_DISTRICTS[0])
	var before_doors: Array[Dictionary] = _furnishings_of(block, doored, CANON_SEED)
	# The first pick with a tile north of it on the map: a pick on the top row has no north to door.
	var victim: Dictionary = before_doors[0]
	for candidate in before_doors:
		if int(candidate["ty"]) > 0:
			victim = candidate
			break
	var above: int = (int(victim["ty"]) - 1) * int(doored.w) + int(victim["tx"])
	doored.tiles[above] = SimTileMap.Tile.Door
	for pick5 in _furnishings_of(block, doored, CANON_SEED):
		if int(pick5["tx"]) == int(victim["tx"]) and int(pick5["ty"]) == int(victim["ty"]):
			push_error("a door dropped directly north of a furnishing left it standing; the doorway rule is judged on nothing")
			return false

	_stash["furnish_kinds"] = placed.size()
	_stash["furnish_picks"] = indoor_picks + outdoor_picks
	print("FURNISH OK %d entries; short props stay in the flat pass and the three explicitly standing furnishings exceed a tile without weakening the flat limit; the real workbench is excluded from dressing; all surfaces, hash picks, placement exclusions, cache, seen/bounds subset, inertness and shipped district placements hold (%d keys across %d districts)" % [(entries as Array).size(), placed.size(), FURNISH_DISTRICTS.size()])
	return true


# --- lane 11: INERT --------------------------------------------------------------------------


# The pictures dressing draws, by name: every authored key of kind tree or prop that is not a
# thing the sim spawned. The sim must never name one -- a sim that reads `nature_bush` has made a
# picture a fact.
func _picture_keys() -> Array[String]:
	var out: Array[String] = []
	for kind in ["tree", "prop", "standing"]:
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
	# The furnishings join the same judgement: they are dressing on the same terms, and the lane that
	# holds the nature list to it holds them to it too (docs/23, "Furnishings and container kinds").
	var furnished: Array[Dictionary] = Dressing.furnishing_tiles(block, map, everyone, int(world.seed), bounds)
	Dressing.furnishing_tiles_cached(block, map, everyone, int(world.seed), bounds, {})
	for ty2 in h:
		for tx2 in w:
			Dressing.heap_key(block, map, int(world.seed), tx2, ty2)
			Dressing.tree_key(block, int(world.seed), tx2, ty2)
			Dressing.furnishing_key(block, map, int(world.seed), tx2, ty2)
	Dressing.tree_tiles(map, everyone, bounds)
	if picks.is_empty() or furnished.is_empty():
		push_error("the pick found %d nature and %d furnishing pictures on the shipped suburb; INERT has nothing to judge" % [picks.size(), furnished.size()])
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
	var every_pick: Array[Dictionary] = []
	every_pick.append_array(picks)
	every_pick.append_array(furnished)
	for pick in every_pick:
		var px: int = int(pick["tx"])
		var py: int = int(pick["ty"])
		var tile: int = int(SimTileMap.tile_at(map, px, py))
		if bool(SimTileMap.SOLID[tile]) or SimTileMap.is_solid(map, px, py) or world.is_blocked_tile(px, py):
			push_error("a %s picture stands on (%d,%d), a tile the sim treats as solid or blocked" % [String(pick["key"]), px, py])
			return false
		if int(SimTileMap.OPACITY[tile]) == SimTileMap.Opacity.Opaque:
			push_error("a %s picture stands on (%d,%d), a tile the sim treats as opaque" % [String(pick["key"]), px, py])
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

	print("INERT OK %d sim files name no picture and read no presentation (the scanner refuses a fabricated preload and a fabricated key, and accepts a comment); a whole-district pick over %d nature and %d furnishing Floor picks left the map digest unmoved (a changed surface and a writing picker both move it); no picked tile is solid, blocked or opaque (a Tree tile is); the serialised world names none of %d picture keys (a fabricated carrier is found)" % [files.size(), picks.size(), furnished.size(), pictures.size()])
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
		if line.begins_with("func %s(" % name) or line.begins_with("static func %s(" % name):
			inside = true
			continue
		if inside and (line.begins_with("func ") or line.begins_with("static func ")):
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


# --- the placement: the clearing, the jitter, the mirror, and the roll that breaks the grid --------
# The flat pictures stop lying on a lattice (A12, the second pass). Four lanes: the roll is
# not a grid, nothing stands on the survivor's start, every picture is placed off its tile's
# centre and some mirrored, and the bake and the frame read those fields.
const CLEAR_RADIUS: int = 3
const LATTICE_WINDOW: int = 32


func _the_roll_does_not_lattice() -> bool:
	# Horizontal and vertical neighbour pairs of the rarity-2 roll over one window: about a quarter
	# of the pairs each way. The shifted hash the first draft used puts them far off in one
	# direction, and the raw hash_at puts none at all; the mixed roll must stay in the band.
	var n: int = LATTICE_WINDOW
	var expected: float = float((n - 1) * n) / 4.0
	var lo: float = expected * 0.8
	var hi: float = expected * 1.2
	var mixed_h: int = 0
	var mixed_v: int = 0
	var shifted_h: int = 0
	var shifted_v: int = 0
	for ty in n:
		for tx in n:
			var raw: int = Dressing.hash_at(3, tx, ty, Dressing.SALT_FURNISH)
			var mixed_hit: bool = Dressing._mix(raw) % 2 == 0
			var shifted_hit: bool = (raw >> 8) % 2 == 0
			if tx < n - 1:
				if mixed_hit and Dressing._mix(Dressing.hash_at(3, tx + 1, ty, Dressing.SALT_FURNISH)) % 2 == 0:
					mixed_h += 1
				if shifted_hit and ((Dressing.hash_at(3, tx + 1, ty, Dressing.SALT_FURNISH) >> 8) % 2 == 0):
					shifted_h += 1
			if ty < n - 1:
				if mixed_hit and Dressing._mix(Dressing.hash_at(3, tx, ty + 1, Dressing.SALT_FURNISH)) % 2 == 0:
					mixed_v += 1
				if shifted_hit and ((Dressing.hash_at(3, tx, ty + 1, Dressing.SALT_FURNISH) >> 8) % 2 == 0):
					shifted_v += 1
	if float(mixed_h) < lo or float(mixed_h) > hi or float(mixed_v) < lo or float(mixed_v) > hi:
		push_error("the mixed furnishing roll pairs %d horizontal and %d vertical neighbours, want each near %.0f: the picks lie on a lattice" % [mixed_h, mixed_v, expected])
		return false
	var shifted_in_band: bool = float(shifted_h) >= lo and float(shifted_h) <= hi and float(shifted_v) >= lo and float(shifted_v) <= hi
	if shifted_in_band:
		push_error("the window cannot tell the shifted roll from the mixed one (%d and %d pairs); the lattice lane has no true negative" % [shifted_h, shifted_v])
		return false
	print("LATTICE mixed roll %d horizontal and %d vertical pairs in a %dx%d window, the shifted roll %d and %d" % [mixed_h, mixed_v, n, n, shifted_h, shifted_v])
	return true


func _the_clearing_holds() -> bool:
	var boot: Dictionary = SimBoot.playable(CANON_SEED, GATE_SIZE)
	var sworld: Variant = boot["world"]
	var smap: Variant = boot["map"]
	var sblock: Dictionary = Dressing.block_of(sworld)
	var seed_val: int = int(sworld.seed)
	var w: int = int(smap.w)
	var h: int = int(smap.h)
	var start: Vector2i = SimBoot.colony_start(smap)
	var seed_term: int = seed_val * Dressing._HASH_SEED
	var entries: Array = Dressing._furnishing_entries(sblock)
	# True positive: the raw roll, with no clearing, does put furnishings inside the square. If it
	# does not, the lane has nothing to judge on this map and says so.
	var raw_inside: int = 0
	for ty in range(start.y - CLEAR_RADIUS, start.y + CLEAR_RADIUS + 1):
		for tx in range(start.x - CLEAR_RADIUS, start.x + CLEAR_RADIUS + 1):
			if tx < 0 or ty < 0 or tx >= w or ty >= h:
				continue
			if not Dressing._furnishing_raw(entries, smap, seed_term, tx, ty, Rect2i()).is_empty():
				raw_inside += 1
	if raw_inside == 0:
		print("CLEAR SKIP: the raw roll puts no furnishing within %d tiles of the start %s on this map; nothing to judge" % [CLEAR_RADIUS, str(start)])
		return true
	for pick in Dressing.decor_picks(sblock, smap, seed_val, Rect2i(0, 0, w, h))["furnishings"] as Array:
		var tx: int = int((pick as Dictionary)["tx"])
		var ty: int = int((pick as Dictionary)["ty"])
		if absi(tx - start.x) <= CLEAR_RADIUS and absi(ty - start.y) <= CLEAR_RADIUS:
			push_error("decor_picks stands a furnishing at (%d,%d), inside the %d-tile clearing round the start %s" % [tx, ty, CLEAR_RADIUS, str(start)])
			return false
	for ty in range(start.y - CLEAR_RADIUS, start.y + CLEAR_RADIUS + 1):
		for tx in range(start.x - CLEAR_RADIUS, start.x + CLEAR_RADIUS + 1):
			if tx < 0 or ty < 0 or tx >= w or ty >= h:
				continue
			if not Dressing.furnishing_key(sblock, smap, seed_val, tx, ty).is_empty():
				push_error("furnishing_key stands a furnishing at (%d,%d), inside the clearing round the start" % [tx, ty])
				return false
	print("CLEAR %d raw furnishing picks inside the %d-tile square round the start %s, none drawn; %d drawn outside it" % [raw_inside, CLEAR_RADIUS, str(start), (Dressing.decor_picks(sblock, smap, seed_val, Rect2i(0, 0, w, h))["furnishings"] as Array).size()])
	return true


func _the_placement_is_read() -> bool:
	var boot: Dictionary = SimBoot.playable(CANON_SEED, GATE_SIZE)
	var sworld: Variant = boot["world"]
	var smap: Variant = boot["map"]
	var sblock: Dictionary = Dressing.block_of(sworld)
	var seed_val: int = int(sworld.seed)
	var w: int = int(smap.w)
	var h: int = int(smap.h)
	var picks: Dictionary = Dressing.decor_picks(sblock, smap, seed_val, Rect2i(0, 0, w, h))
	var flipped: int = 0
	var straight: int = 0
	var offsets: Dictionary = {}
	var total: int = 0
	for kind in ["nature", "furnishings"]:
		for raw in picks[kind] as Array:
			var pick: Dictionary = raw as Dictionary
			total += 1
			var ox: int = int(pick["ox"])
			var oy: int = int(pick["oy"])
			# Whole art pixels, never a fraction of one: a fraction lands between the ground's own art
			# pixels at some zoom, which is the odd-pixel placement the density QA caught.
			if typeof(pick["ox"]) != TYPE_INT or typeof(pick["oy"]) != TYPE_INT:
				push_error("a picture's offset is not whole art pixels (%s, %s)" % [str(pick["ox"]), str(pick["oy"])])
				return false
			if absi(ox) > Dressing.JITTER_PX or oy > 0 or oy < -Dressing.JITTER_PX:
				push_error("a picture sits %d, %d art pixels off its tile; the jitter is ±%d across and up to %d above the south edge" % [ox, oy, Dressing.JITTER_PX, Dressing.JITTER_PX])
				return false
			if bool(pick["flip"]):
				flipped += 1
			else:
				straight += 1
			offsets[ox] = true
	if total == 0:
		push_error("the shipped suburb placed no flat pictures; the placement lane has nothing to judge")
		return false
	if flipped == 0 or straight == 0:
		push_error("every picture takes the same mirror (%d flipped, %d straight); the flip is dead" % [flipped, straight])
		return false
	if offsets.size() < 5:
		push_error("only %d distinct horizontal offsets across %d pictures; the placement is still a grid" % [offsets.size(), total])
		return false
	var main_src: String = _function_body(MAIN_GD, "_draw_decor")
	if not main_src.contains("_placed_rect(") or not main_src.contains("_mirrored(") or not main_src.contains("placed[\"flip\"]"):
		push_error("_draw_decor does not place and mirror its pictures through _placed_rect; the placement is a field nothing reads")
		return false
	var rect_src: String = _function_body(MAIN_GD, "_placed_rect")
	for needle in ["placed[\"tx\"]", "placed[\"ty\"]", "placed[\"ox\"]", "placed[\"oy\"]", "ART_PER_TILE", "floorf("]:
		if not rect_src.contains(needle):
			push_error("_placed_rect does not read %s; the placement is a field nothing reads" % needle)
			return false
	var scatter_src: String = _function_body(MAIN_GD, "_draw_scatter")
	if not scatter_src.contains("Dressing.litter_placed_in(") or not scatter_src.contains("_draw_litter("):
		push_error("_draw_scatter does not take its scrap from Dressing.litter_placed_in; the scrap's placement is a field nothing reads")
		return false
	var litter_src: String = _function_body(MAIN_GD, "_draw_litter")
	for needle in ["_placed_rect(", "placed[\"flip\"]", "_mirrored("]:
		if not litter_src.contains(needle):
			push_error("_draw_litter does not read %s; a scrap drawn without its own placement is the old grid" % needle)
			return false
	print("PLACED %d flat pictures on the shipped suburb: %d mirrored, %d straight, %d distinct horizontal offsets, every offset a whole number of art pixels" % [total, flipped, straight, offsets.size()])
	return true


# --- the occupancy: one picture to a place where two would meet. A tile's raw picture (its furnishing,
# else its nature picture) and its scrap of litter are judged against the eight tiles round them: where
# two art rects meet, the lower rank gives way (a standing furnishing over a flat one, a flat one over
# nature, anything over litter). Each part is judged twice: the raw roll must produce meetings on the
# shipped suburb (a true positive, or the rule has nothing to do and the lane says so), and the kept
# pictures must hold the rule (the true negative a broken rule would fail).
func _the_occupancy_holds() -> bool:
	var boot: Dictionary = SimBoot.playable(CANON_SEED, GATE_SIZE)
	var oworld: Variant = boot["world"]
	var omap: Variant = boot["map"]
	var oblock: Dictionary = Dressing.block_of(oworld)
	var seed_val: int = int(oworld.seed)
	var w: int = int(omap.w)
	var h: int = int(omap.h)
	if Dressing._furnishing_entries(oblock).is_empty() or Dressing._nature_entries(oblock).is_empty():
		push_error("the shipped suburb declares no furnishings or no nature; the occupancy lane has nothing to judge")
		return false
	# The sizes are content, and the overlap rule places every picture by them, so each size is checked
	# against the canvas its key declares, every picture the block names must have one, and a size that
	# disagrees with its canvas must be seen to (the true negative: a fabricated one).
	var furn: Array = Dressing._furnishing_entries(oblock)
	var nature: Array = Dressing._nature_entries(oblock)
	var sizes: Dictionary = Dressing._sizes(oblock)
	for key_v in sizes.keys():
		if Appearance.canvas_of(String(key_v)) != sizes[key_v]:
			push_error("the dressing sizes %s as %s, its authored canvas is %s; the overlap rule would place it wrong" % [String(key_v), str(sizes[key_v]), str(Appearance.canvas_of(String(key_v)))])
			return false
	for entry in furn:
		if not sizes.has(String((entry as Array)[0])):
			push_error("the furnishing %s has no size; it would draw nothing" % String((entry as Array)[0]))
			return false
	for entry in nature:
		if not sizes.has(String((entry as Array)[0])):
			push_error("the nature picture %s has no size; it would draw nothing" % String((entry as Array)[0]))
			return false
	for raw_key in oblock["litter"] as Array:
		if not sizes.has(String(raw_key)):
			push_error("the scrap %s has no size; it would draw nothing" % String(raw_key))
			return false
	if Dressing._sizes({"sizes": {"prop_table": [41, 30]}})["prop_table"] == Appearance.canvas_of("prop_table"):
		push_error("a 41-pixel table agrees with its 40-pixel canvas; the size check cannot fail")
		return false
	var occ: Dictionary = Dressing.occupancy(oblock, omap, seed_val)
	var clear: Rect2i = Dressing._clear_of(omap)
	var meets_standing_flat: int = 0
	var meets_flat_nature: int = 0
	var meets_litter: int = 0
	var kept_meets: int = 0
	var old_meets: int = 0
	var halves: int = 0
	var kept_under_higher: int = 0
	var kept_on_clear: int = 0
	var scrap_on_held: int = 0
	var paved: int = 0
	var scraps: int = 0
	var bags: int = 0
	for ty in range(h):
		for tx in range(w):
			if Dressing._paved_floor(omap, tx, ty):
				paved += 1
			var top: Dictionary = Dressing._raw_top(occ, omap, tx, ty)
			var kept: Dictionary = Dressing._kept_top(occ, omap, tx, ty)
			var scrap: Dictionary = Dressing.litter_placed_in(occ, tx, ty)
			var raw_scrap: String = Dressing._litter_raw(occ, omap, tx, ty)
			if not kept.is_empty() and String(kept["key"]) == "prop_trash_bags":
				bags += 1
			if not scrap.is_empty():
				scraps += 1
				if not top.is_empty():
					scrap_on_held += 1
			if clear.has_point(Vector2i(tx, ty)) and (not kept.is_empty() or not scrap.is_empty()):
				kept_on_clear += 1
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var nx: int = tx + dx
					var ny: int = ty + dy
					var near: Dictionary = Dressing._raw_top(occ, omap, nx, ny)
					var shift: Vector2i = Vector2i(dx, dy)
					if not top.is_empty() and not near.is_empty() and Dressing._meet(Dressing._top_rect(occ, top, tx, ty), Dressing._top_rect(occ, near, nx, ny), shift):
						if int(top["rank"]) == Dressing.RANK_STANDING and int(near["rank"]) == Dressing.RANK_FLAT:
							meets_standing_flat += 1
						elif int(top["rank"]) == Dressing.RANK_FLAT and int(near["rank"]) == Dressing.RANK_NATURE:
							meets_flat_nature += 1
					if not raw_scrap.is_empty() and not near.is_empty() and Dressing._meet(Dressing._litter_rect(occ, raw_scrap, tx, ty), Dressing._top_rect(occ, near, nx, ny), shift):
						meets_litter += 1
					# Two held tiles are the sim's own business (a car's Low tiles stand in a column);
					# the rule only answers for the pictures this file draws.
					if kept.is_empty() or int(kept["rank"]) == Dressing.RANK_HELD:
						continue
					var kept_near: Dictionary = Dressing._kept_top(occ, omap, nx, ny)
					var rect: Rect2i = Dressing._top_rect(occ, kept, tx, ty)
					# Two pieces of the old street furniture that met where main drew them still meet:
					# both stand where they stood (`kept`), which outranks the overlap rule.
					var both_old: bool = kept.has("kept") and kept_near.has("kept")
					# The two halves of one long table butt on their tops; only their canvases' clear
					# margins overlap, and the LONG check below holds the tops edge to edge.
					var one_table: bool = kept.has("pair") and kept_near.get("pair", null) == kept["pair"]
					if one_table and dx == 1 and dy == 0:
						halves += 1
						var gap: int = _table_top_gap(occ, kept, tx, kept_near, nx)
						if gap != 0:
							push_error("LONG: the long table at %s leaves %d art pixels between its halves' tops; they butt at 0" % [str(Vector2i(tx, ty)), gap])
							return false
					if not kept_near.is_empty() and not one_table and Dressing._meet(rect, Dressing._top_rect(occ, kept_near, nx, ny), shift):
						if both_old:
							old_meets += 1
						else:
							kept_meets += 1
					if not near.is_empty() and int(near["rank"]) > int(kept["rank"]) and Dressing._meet(rect, Dressing._top_rect(occ, near, nx, ny), shift) and not (kept.has("kept") and near.has("kept")):
						kept_under_higher += 1
			if not scrap.is_empty():
				var scrap_rect: Rect2i = Dressing._litter_rect(occ, String(scrap["key"]), tx, ty)
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if dx == 0 and dy == 0:
							continue
						var kept_near: Dictionary = Dressing._kept_top(occ, omap, tx + dx, ty + dy)
						if not kept_near.is_empty() and Dressing._meet(scrap_rect, Dressing._top_rect(occ, kept_near, tx + dx, ty + dy), Vector2i(dx, dy)):
							kept_meets += 1
	print("OCCUPANCY raw meetings on the suburb: %d standing over flat, %d flat over nature, %d scraps over a picture; kept pictures that meet: %d; kept under a higher raw rank: %d; old street furniture meeting old street furniture where main drew it: %d; long tables whose halves butt: %d" % [meets_standing_flat, meets_flat_nature, meets_litter, kept_meets, kept_under_higher, old_meets, halves])
	if halves == 0:
		push_error("LONG: no long table stands on the suburb; the butt is not judged")
		return false
	# TN: the old shift (four art pixels each way) leaves a gap the check sees.
	var shifted: Dictionary = {"key": "prop_table", "ox": -4, "oy": 0}
	var shifted_east: Dictionary = {"key": "prop_table", "ox": 4, "oy": 0}
	if _table_top_gap(occ, shifted, 0, shifted_east, 1) == 0:
		push_error("LONG: a pair shifted four pixels apart reads as butted; the check cannot fail")
		return false
	# The suburb's street junk is spaced along its rows and stands mostly on the paving, so flat over
	# nature can miss this one map; a grass yard rolling both on every other tile is where that rule is
	# proved, under the same kept checks.
	if meets_flat_nature == 0:
		var yard_block: Dictionary = {"sizes": FABRICATED_SIZES, "nature": [{"key": "nature_bush", "surfaces": ["grass"], "rarity": 2}], "furnishings": [{"key": "prop_dumpster", "where": "outdoors", "surfaces": ["grass"], "rarity": 2}]}
		var grass_yard: Variant = _grass_map(16, 16)
		var yocc: Dictionary = Dressing.occupancy(yard_block, grass_yard, seed_val)
		for ty in 16:
			for tx in 16:
				var ytop: Dictionary = Dressing._raw_top(yocc, grass_yard, tx, ty)
				var ykept: Dictionary = Dressing._kept_top(yocc, grass_yard, tx, ty)
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if dx == 0 and dy == 0:
							continue
						var ynear: Dictionary = Dressing._raw_top(yocc, grass_yard, tx + dx, ty + dy)
						if not ytop.is_empty() and not ynear.is_empty() and int(ytop["rank"]) == Dressing.RANK_FLAT and int(ynear["rank"]) == Dressing.RANK_NATURE and Dressing._meet(Dressing._top_rect(yocc, ytop, tx, ty), Dressing._top_rect(yocc, ynear, tx + dx, ty + dy), Vector2i(dx, dy)):
							meets_flat_nature += 1
						if ykept.is_empty():
							continue
						var yrect: Rect2i = Dressing._top_rect(yocc, ykept, tx, ty)
						var ykept_near: Dictionary = Dressing._kept_top(yocc, grass_yard, tx + dx, ty + dy)
						if not ykept_near.is_empty() and Dressing._meet(yrect, Dressing._top_rect(yocc, ykept_near, tx + dx, ty + dy), Vector2i(dx, dy)):
							kept_meets += 1
						if not ynear.is_empty() and int(ynear["rank"]) > int(ykept["rank"]) and Dressing._meet(yrect, Dressing._top_rect(yocc, ynear, tx + dx, ty + dy), Vector2i(dx, dy)):
							kept_under_higher += 1
		print("OCCUPANCY flat over nature met nowhere on the suburb; a grass yard took %d such meetings (kept that meet now %d, under a higher rank %d)" % [meets_flat_nature, kept_meets, kept_under_higher])
	if meets_standing_flat == 0 or meets_flat_nature == 0 or meets_litter == 0:
		push_error("the raw rolls never meet on this map (standing %d, flat %d, scrap %d); a rule with nothing to do is not proved" % [meets_standing_flat, meets_flat_nature, meets_litter])
		return false
	if kept_meets != 0 or kept_under_higher != 0:
		push_error("%d kept pictures meet a neighbour and %d sit under a higher raw picture; the overlap rule has a hole" % [kept_meets, kept_under_higher])
		return false
	if kept_on_clear != 0 or scrap_on_held != 0:
		push_error("%d pictures stand in the clearing and %d scraps sit on a held tile; the clearing and the held tiles are not kept" % [kept_on_clear, scrap_on_held])
		return false
	# The rate: a scrap dealt by its block's quota (LITTER_TENTHS), the street's and a room's apart,
	# kept after the overlap rule, judged as a band so a rule that starves or floods the floor fails.
	if paved == 0:
		push_error("the shipped suburb has no paved floor; the scrap rate has nothing to judge")
		return false
	var rate: float = float(scraps) / float(paved)
	print("OCCUPANCY scraps %d of %d paved floor tiles (1 in %.1f), %d trash bags on the suburb" % [scraps, paved, 1.0 / maxf(rate, 0.0001), bags])
	# The band is wide on purpose: this 64-tile suburb is mostly edge (walls, kerbs, cars), where the
	# weighted roll lands three times as often, so its rate runs above what a screen of street shows
	# (A12's measure counts about 1 in 6 on screen). The band refuses a rule that starves or floods.
	if rate < 0.10 or rate > 0.25:
		push_error("scraps sit on %.3f of the paved floor; the band is 0.10 to 0.25" % rate)
		return false
	if bags < 4:
		push_error("only %d trash bags on the suburb; the kerb and wall rule starves them" % bags)
		return false
	print("OCCUPANCY_OK %d raw meetings across the three rules, none kept; %d scraps, none on a held tile or in the clearing; %d trash bags" % [meets_standing_flat + meets_flat_nature + meets_litter, scraps, bags])
	return true


# --- lane: the room's sets, the wall runs, the street's edge and what the sim holds ---------------
# A12's placement rules, each on a hand map it can say yes on and a hand map it has to say no on,
# and each with the reader that reaches it: main.gd builds its occupancy with the world's props and
# hands it to the bake and the standing pass, and the review harness stands a shot's survivor on
# Dressing.clear_around's answer.


# A room `w` x `h` with walls all round, the floor inside it indoor and paved.
# A 40x9 walled block: a two-row corridor (rows 1 and 2) along the top, an inner wall on row 3 open
# at both ends, and a room (rows 4 to 7) below, so a stretch of the corridor joins the rest along the
# corridor or round through the room. Wide enough that the start's clearing leaves the west end
# (columns 1 to 12) to the dressing.
func _corridor_map() -> Variant:
	var map: Variant = _walled_room(40, 9)
	for tx in range(2, 38):
		map.tiles[3 * 40 + tx] = SimTileMap.Tile.Wall
	return map


func _walled_room(w: int, h: int) -> Variant:
	var map: Variant = _room_map(w, h, true)
	for ty in h:
		for tx in w:
			if tx == 0 or ty == 0 or tx == w - 1 or ty == h - 1:
				map.tiles[ty * w + tx] = SimTileMap.Tile.Wall
	return map


func _kept_keys_of(occ: Dictionary, map: Variant, key: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for ty in int(map.h):
		for tx in int(map.w):
			var kept: Dictionary = Dressing._kept_top(occ, map, tx, ty)
			if not kept.is_empty() and String(kept.get("key", "")) == key:
				out.append(Vector2i(tx, ty))
	return out


# The chairs standing directly south of a table: the pack's chair faces south, its back to the north.
func _chairs_south_of_a_table(at_tables: Array[Vector2i], at_chairs: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in at_chairs:
		if at_tables.has(c - Vector2i(0, 1)):
			out.append(c)
	return out


func _the_room_sets_and_the_edges_hold() -> bool:
	# --- tables with their chairs ---------------------------------------------------------------
	var set_block: Dictionary = {"sizes": FABRICATED_SIZES, "furnishings": [
		{"key": "prop_table", "where": "indoors", "surfaces": ["paved"], "rarity": 9, "group": "table"},
		{"key": "prop_chair", "where": "indoors", "surfaces": ["paved"], "rarity": 2, "group": "seat"},
	]}
	var hall: Variant = _walled_room(24, 18)
	var tables: int = 0
	var chairs: int = 0
	var lone_tables: int = 0
	var pairs: int = 0
	for seed_val in 4:
		var occ: Dictionary = Dressing.occupancy(set_block, hall, seed_val)
		var seed_term: int = seed_val * Dressing._HASH_SEED
		var table_entry: Array = (occ["tables"] as Array)[0]
		var seat_rarity: int = 2
		var at_tables: Array[Vector2i] = _kept_keys_of(occ, hall, "prop_table")
		var at_chairs: Array[Vector2i] = _kept_keys_of(occ, hall, "prop_chair")
		tables += at_tables.size()
		chairs += at_chairs.size()
		var anchors: Array[Vector2i] = []
		for t in at_tables:
			if Dressing._anchor_in_cell(occ, hall, table_entry, t.x, t.y) == t:
				anchors.append(t)
		for t in at_tables:
			var anchor: bool = anchors.has(t)
			var east_half: bool = anchors.has(t - Vector2i(1, 0)) and Dressing._is_pair(occ, hall, table_entry, t.x - 1, t.y)
			if not anchor and not east_half:
				push_error("seed %d: a table at %s is neither its cell's table nor the east half of a pair" % [seed_val, str(t)])
				return false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if not Dressing._floor_of(hall, t.x + dx, t.y + dy, true):
						push_error("seed %d: a table at %s has a wall within a tile; a chair would not fit round it" % [seed_val, str(t)])
						return false
					# Two tables side by side are a pair and nothing else: the west one its cell's
					# table, paired, the east one its half.
					if (dx != 0 or dy != 0) and at_tables.has(t + Vector2i(dx, dy)):
						var is_pair_east: bool = dx == 1 and dy == 0 and anchor and Dressing._is_pair(occ, hall, table_entry, t.x, t.y)
						var is_pair_west: bool = dx == -1 and dy == 0 and east_half
						if not is_pair_east and not is_pair_west:
							push_error("seed %d: two tables stand side by side at %s and %s and are not a pair; the cells should keep them apart" % [seed_val, str(t), str(t + Vector2i(dx, dy))])
							return false
			if not anchor:
				continue
			var pair: bool = Dressing._is_pair(occ, hall, table_entry, t.x, t.y)
			if pair:
				pairs += 1
				if not at_tables.has(t + Vector2i(1, 0)):
					# The overlap rule may drop a half for a neighbour; say so rather than miss it.
					print("SETS note: seed %d's pair at %s lost its east half to the overlap rule" % [seed_val, str(t)])
			# A table's own chairs are the seats its slot mask sets: one to SEATS_MAX, and a chair kept
			# at one of them.
			var seats: Array = Dressing.PAIR_SEATS if pair else Dressing.SINGLE_SEATS
			var slots: int = Dressing._seat_slots(seed_term, t.x, t.y, seat_rarity, seats.size())
			var set_seats: int = 0
			var round_it: int = 0
			for i in seats.size():
				if (slots >> i) & 1 == 1:
					set_seats += 1
					if at_chairs.has(t + ((seats[i] as Array)[0] as Vector2i)):
						round_it += 1
			if set_seats < 1 or set_seats > Dressing.SEATS_MAX:
				push_error("seed %d: the table at %s seats %d chairs; a set is one to %d" % [seed_val, str(t), set_seats, Dressing.SEATS_MAX])
				return false
			if round_it == 0:
				lone_tables += 1
		for c in at_chairs:
			var seated: bool = false
			for pair_c in [false, true]:
				var seats_c: Array = Dressing.PAIR_SEATS if pair_c else Dressing.SINGLE_SEATS
				for i in seats_c.size():
					var owner: Vector2i = c - ((seats_c[i] as Array)[0] as Vector2i)
					if anchors.has(owner) and Dressing._is_pair(occ, hall, table_entry, owner.x, owner.y) == pair_c and (Dressing._seat_slots(seed_term, owner.x, owner.y, seat_rarity, seats_c.size()) >> i) & 1 == 1:
						seated = true
			if not seated:
				push_error("seed %d: a chair at %s stands on no seat a table offers; the seat group only seats a table" % [seed_val, str(c)])
				return false
			# The pack's chair faces south, its back to the north: one directly south of a table would
			# sit with its back to it.
		var backs: Array[Vector2i] = _chairs_south_of_a_table(at_tables, at_chairs)
		if not backs.is_empty():
			push_error("seed %d: chairs at %s stand south of a table, their backs to it" % [seed_val, str(backs)])
			return false
	# The seat lists themselves never name the south side, and a seat list that did would be read: the
	# same chair check run on a fabricated south seat finds the table north of it.
	for seats_list in [Dressing.SINGLE_SEATS, Dressing.PAIR_SEATS]:
		for seat_row in seats_list as Array:
			if int((seat_row as Array)[1]) == 2 or ((seat_row as Array)[0] as Vector2i).y > 0:
				push_error("a seat list offers the south side %s; a chair there sits with its back to the table" % str(seat_row))
				return false
	var fab_tables: Array[Vector2i] = [Vector2i(5, 5)]
	var fab_chairs: Array[Vector2i] = [Vector2i(5, 4), Vector2i(5, 6)]
	if _chairs_south_of_a_table(fab_tables, fab_chairs) != [Vector2i(5, 6)]:
		push_error("the south-chair test missed a fabricated chair south of a table; it proves nothing")
		return false
	# A table the overlap rule drops for a neighbour leaves its chairs without one; most keep theirs.
	if tables < 8 or chairs < tables / 2 or lone_tables * 4 > tables or pairs == 0:
		push_error("a 22x16 hall over four seeds took %d tables (%d pairs) and %d chairs (%d tables with none); the sets are not set" % [tables, pairs, chairs, lone_tables])
		return false
	# Negative for the pair: a room three tiles wide inside has one column whose eight neighbours are
	# floor, so the tile east of any table cannot take one and no table pairs.
	var narrow: Variant = _walled_room(5, 18)
	for seed_val in 8:
		var nocc: Dictionary = Dressing.occupancy(set_block, narrow, seed_val)
		var nt: Array[Vector2i] = _kept_keys_of(nocc, narrow, "prop_table")
		for t in nt:
			if nt.has(t + Vector2i(1, 0)):
				push_error("seed %d: a table paired at %s in a room with no room east of it" % [seed_val, str(t)])
				return false
	# Negatives: a corridor two tiles wide has no tile whose eight neighbours are all floor, and a
	# seat entry with no table entry seats nobody.
	if not _kept_keys_of(Dressing.occupancy(set_block, _walled_room(24, 4), 1), _walled_room(24, 4), "prop_table").is_empty():
		push_error("a table stood in a corridor two tiles wide; the room test is not read")
		return false
	var seats_only: Dictionary = {"sizes": FABRICATED_SIZES, "furnishings": [set_block["furnishings"][1]]}
	if not _kept_keys_of(Dressing.occupancy(seats_only, hall, 1), hall, "prop_chair").is_empty():
		push_error("a seat entry with no table entry placed a chair")
		return false

	# --- shelves in runs against a north wall ----------------------------------------------------
	var run_block: Dictionary = {"sizes": FABRICATED_SIZES, "furnishings": [{"key": "prop_medical_cabinet", "where": "indoors", "surfaces": ["paved"], "rarity": 2, "beside": "wall_north"}]}
	var runs: int = 0
	var paired: int = 0
	for seed_val in 4:
		var occ2: Dictionary = Dressing.occupancy(run_block, hall, seed_val)
		var at: Array[Vector2i] = _kept_keys_of(occ2, hall, "prop_medical_cabinet")
		runs += at.size()
		for c in at:
			if not Dressing._wall_at(hall, c.x, c.y - 1):
				push_error("seed %d: a wall_north cabinet at %s has no wall north of it" % [seed_val, str(c)])
				return false
			if at.has(c + Vector2i(2, 0)):
				paired += 1
	if runs == 0 or paired == 0:
		push_error("over four seeds the north wall took %d cabinets, %d of them two tiles from the next; the run rule is not read" % [runs, paired])
		return false
	var no_north: Variant = _room_map(24, 6, true)
	for tx in 24:
		no_north.tiles[5 * 24 + tx] = SimTileMap.Tile.Wall
	if not _kept_keys_of(Dressing.occupancy(run_block, no_north, 1), no_north, "prop_medical_cabinet").is_empty():
		push_error("a wall_north cabinet stood in a room whose only wall is south of it")
		return false

	# --- the street's edge ----------------------------------------------------------------------
	var edge_block: Dictionary = {"sizes": FABRICATED_SIZES, "furnishings": [{"key": "prop_barrel", "where": "outdoors", "surfaces": ["paved"], "rarity": 2, "beside": "edge"}]}
	var yard: Variant = _room_map(16, 9, false)
	var open_hits: int = 0
	for seed_val in 8:
		open_hits += _kept_keys_of(Dressing.occupancy(edge_block, yard, seed_val), yard, "prop_barrel").size()
	for tx in 16:
		yard.tiles[tx] = SimTileMap.Tile.Wall
	var wall_hits: int = 0
	for seed_val in 8:
		for b in _kept_keys_of(Dressing.occupancy(edge_block, yard, seed_val), yard, "prop_barrel"):
			if b.y != 1:
				push_error("seed %d: an edge barrel stood at %s, more than a tile off the wall" % [seed_val, str(b)])
				return false
			wall_hits += 1
	if open_hits != 0 or wall_hits == 0:
		push_error("an edge barrel stood on %d open yard tiles and %d tiles beside a wall; the edge rule is not read" % [open_hits, wall_hits])
		return false
	# The street's sidewalk slab is an edge: read through RoadPaint's mask, and only through it. A
	# paved yard with a five-wide street across it and no wall, car or kerb anywhere: the barrels
	# stand on the street's two sidewalk rows and nowhere else.
	var paved_yard: Variant = _room_map(16, 9, false)
	paved_yard.streets = [{"axis": "y", "at": 2, "width": 5, "from": 0, "to": 15}]
	var slab_hits: int = 0
	for seed_val in 8:
		for b in _kept_keys_of(Dressing.occupancy(edge_block, paved_yard, seed_val), paved_yard, "prop_barrel"):
			if b.y != 2 and b.y != 6:
				push_error("seed %d: an edge barrel stood at %s, off the street's sidewalk rows" % [seed_val, str(b)])
				return false
			slab_hits += 1
	if slab_hits == 0:
		push_error("no edge barrel stood on a sidewalk over eight seeds; the road mask is not read")
		return false

	# --- what the sim holds -------------------------------------------------------------------
	var loose: Dictionary = {"sizes": FABRICATED_SIZES, "furnishings": [{"key": "prop_traffic_cone", "where": "indoors", "surfaces": ["paved"], "rarity": 2}], "litter": ["prop_traffic_cone"]}
	var open_room: Variant = _room_map(12, 6, true)
	var free_seed: int = -1
	for seed_val in 32:
		if not Dressing._kept_top(Dressing.occupancy(loose, open_room, seed_val), open_room, 5, 2).is_empty():
			free_seed = seed_val
			break
	if free_seed < 0:
		push_error("a rarity-2 cone never took tile (5,2) over 32 seeds; the held lane has nothing to take away")
		return false
	var held: Dictionary = Dressing.occupancy(loose, open_room, free_seed, {Vector2i(5, 2): Rect2i(0, 0, 32, 32)})
	var held_top: Dictionary = Dressing._kept_top(held, open_room, 5, 2)
	if held_top.is_empty() or int(held_top["rank"]) != Dressing.RANK_HELD or not Dressing._kept_litter(held, open_room, 5, 2).is_empty():
		push_error("a prop held on (5,2) left the tile to a picture: %s" % str(held_top))
		return false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var near: Dictionary = Dressing._kept_top(held, open_room, 5 + dx, 2 + dy)
			if (dx != 0 or dy != 0) and not near.is_empty() and Dressing._meet(Rect2i(0, 0, 32, 32), Dressing._top_rect(held, near, 5 + dx, 2 + dy), Vector2i(dx, dy)):
				push_error("a cone at (%d,%d) reaches over the held tile" % [5 + dx, 2 + dy])
				return false
	var low_room: Variant = _room_map(12, 6, true)
	low_room.tiles[2 * 12 + 5] = SimTileMap.Tile.Low
	if Dressing._held_rect(Dressing.occupancy(loose, low_room, 1), low_room, 5, 2) == null:
		push_error("a Low tile is not held; a heap or a car's tile would take a picture")
		return false

	# --- clear_around, both ways ----------------------------------------------------------------
	var cocc: Dictionary = Dressing.occupancy(loose, open_room, free_seed)
	if Dressing.clear_around(cocc, 5, 2, 1):
		push_error("clear_around said a tile holding a cone is clear")
		return false
	if not Dressing.clear_around(Dressing.occupancy({}, open_room, free_seed), 5, 2, 3):
		push_error("clear_around found a picture on an undressed map; it cannot say yes")
		return false

	# --- the renderer's two rects ---------------------------------------------------------------
	var main_script: GDScript = load(MAIN_GD) as GDScript
	var host: Object = main_script.new()
	var flipped: Rect2 = host.call("_mirrored", Rect2(10.0, 4.0, 20.0, 6.0), true)
	if flipped != Rect2(10.0, 4.0, -20.0, 6.0) or host.call("_mirrored", Rect2(10.0, 4.0, 20.0, 6.0), false) != Rect2(10.0, 4.0, 20.0, 6.0):
		push_error("_mirrored moved a flipped picture to %s; a negative width flips in place" % str(flipped))
		(host as Node).free()
		return false
	for art in [Vector2(24, 38), Vector2(25, 62)]:
		var r: Rect2 = host.call("_standing_rect", 132.0, 264.0, art, 2.0)
		# The tile's corner is (100, 200) at 64 px a tile: its centre line x 132, its south edge y 264.
		if int(r.position.x - 100.0) % 2 != 0 or int(r.position.y - 200.0) % 2 != 0 or r.end.y != 268.0:
			push_error("a standing %s picture's rect %s is off the 2 px art grid or off the two-pixel foot drop" % [str(art), str(r)])
			(host as Node).free()
			return false
	(host as Node).free()

	# --- the readers ------------------------------------------------------------------------------
	var missing: String = _missing_needle(_function_body(MAIN_GD, "_dressing_occupancy"), ["Dressing.held_props(world)", "Appearance.prop_tiles(world)"])
	if missing.is_empty():
		missing = _missing_needle(_function_body(MAIN_GD, "_draw_decor"), ["_dressing_occupancy()"])
	if missing.is_empty():
		missing = _missing_needle(_function_body(MAIN_GD, "_standing_props"), ["_dressing_occupancy()", "standing_furnishing_tiles_cached("])
	if missing.is_empty():
		missing = _missing_needle(_function_body(MAIN_GD, "_blit_standing"), ["_standing_rect("])
	if missing.is_empty():
		missing = _missing_needle(_function_body("res://review/scenes.gd", "_ring_free"), ["Dressing.clear_around("])
	if not missing.is_empty():
		push_error("a placement rule has lost its reader: %s" % missing)
		return false
	print("SETS OK %d tables (%d long pairs, none in a three-wide room) and %d chairs over four seeds in a walled hall, each table with floor round it and one to %d chairs on its north, east and west, none south of a table, none in a corridor and none from a seat entry alone; %d cabinets against the north wall (%d two tiles from the next), none against a south wall; edge barrels only beside the wall (%d) or on a sidewalk (%d) and none on an open yard; a held prop and a Low tile keep their tiles; clear_around says both; _mirrored flips in place and a standing rect sits on the art grid; main.gd and the harness read every rule" % [tables, pairs, chairs, Dressing.SEATS_MAX, runs, paired, wall_hits, slab_hits])
	return true


# --- lane: the measure the rooms and the street keep (A12, round 1 of its review) -------------
# The rules the review asked for, each with the case it refuses: the street furniture keeps the
# rolls it had before the junk joined it; the junk keeps its spacing; a room keeps one medical
# cabinet; nothing stands in front of a window; the grass verge is an edge; a scrap lies anywhere in
# its tile; a wide picture anchored beside the clearing does not reach into it.

# The salts the street's own furniture rolled under before A12 added the junk beside it: its list
# index then. Pinned, so reordering the list can never re-roll a barrier, a cone, a post, a sign or
# a lamp off the spot it stood on.
const ROAD_SALTS: Dictionary = {
	"prop_concrete_barrier": 5, "prop_traffic_cone": 6, "prop_fence_post": 7, "prop_road_sign": 9, "prop_streetlamp": 10,
}


func _kept_set(occ: Dictionary, map: Variant, keys: Array) -> Dictionary:
	var out: Dictionary = {}
	for ty in int(map.h):
		for tx in int(map.w):
			var kept: Dictionary = Dressing._kept_top(occ, map, tx, ty)
			if not kept.is_empty() and keys.has(String(kept.get("key", ""))):
				out[Vector2i(tx, ty)] = String(kept["key"])
	return out


# The kept pictures of one entry, by room: the room index to how many it holds.
func _per_room_counts(occ: Dictionary, map: Variant, key: String) -> Dictionary:
	var out: Dictionary = {}
	for at in _kept_keys_of(occ, map, key):
		var room: int = Dressing._room_of(occ, map, at.x, at.y)
		out[room] = int(out.get(room, 0)) + 1
	return out


func _the_rooms_and_the_street_keep_their_measure() -> bool:
	# --- SALT: an entry's own salt, pinned; a second entry naming it is dropped ------------------
	var salted: Dictionary = {"sizes": FABRICATED_SIZES, "furnishings": [
		{"key": "prop_traffic_cone", "where": "outdoors", "surfaces": ["paved"], "rarity": 2, "salt": 5},
		{"key": "prop_barrel", "where": "outdoors", "surfaces": ["paved"], "rarity": 2},
		{"key": "prop_pallet_stack", "where": "outdoors", "surfaces": ["paved"], "rarity": 2, "salt": 5},
		{"key": "prop_medical_cabinet", "where": "outdoors", "surfaces": ["paved"], "rarity": 2, "per_room": 1},
	]}
	var sentries: Array = Dressing._furnishing_entries(salted)
	if sentries.size() != 2 or int(sentries[0][Dressing.FE_SALT]) != (Dressing.SALT_FURNISH + 5) * Dressing._HASH_SALT or int(sentries[1][Dressing.FE_SALT]) != (Dressing.SALT_FURNISH + 1) * Dressing._HASH_SALT:
		push_error("SALT: four entries (a salt, an index, a repeated salt, a per-room piece outdoors) prepared as %d; the first two keep their salts and the last two are dropped" % sentries.size())
		return false

	# --- ROAD: the shipped street furniture rolls where it rolled, and the junk drops none of it ---
	var boot: Dictionary = SimBoot.playable(CANON_SEED, GATE_SIZE)
	var rworld: Variant = boot["world"]
	var rmap: Variant = boot["map"]
	var rblock: Dictionary = Dressing.block_of(rworld)
	var rseed: int = int(rworld.seed)
	var shipped: Array = (rblock.get("furnishings", []) as Array)
	var seen_road: Dictionary = {}
	for raw in shipped:
		var entry: Dictionary = raw as Dictionary
		var key: String = String(entry.get("key", ""))
		if ROAD_SALTS.has(key) and String(entry.get("where", "")) == "outdoors":
			seen_road[key] = true
			if not entry.has("salt") or int(entry["salt"]) != int(ROAD_SALTS[key]) or bool(entry.get("cluster", false)):
				push_error("ROAD: the street's %s rolls under salt %s (cluster %s); it rolled under %d before the junk joined it, plainly" % [key, str(entry.get("salt", "its index")), str(entry.get("cluster", false)), int(ROAD_SALTS[key])])
				return false
	if seen_road.size() != ROAD_SALTS.size():
		push_error("ROAD: the shipped block names %d of the %d street furniture keys" % [seen_road.size(), ROAD_SALTS.size()])
		return false
	var no_junk: Array = []
	for raw2 in shipped:
		if not bool((raw2 as Dictionary).get("cluster", false)):
			no_junk.append(raw2)
	var with_junk: Dictionary = _kept_set(Dressing.occupancy(rblock, rmap, rseed), rmap, ROAD_SALTS.keys())
	var without: Dictionary = _kept_set(Dressing.occupancy({"sizes": rblock.get("sizes", {}), "furnishings": no_junk, "litter": rblock.get("litter", [])}, rmap, rseed), rmap, ROAD_SALTS.keys())
	if without.is_empty():
		print("ROAD SKIP: the suburb at seed %d stands no street furniture; nothing to judge" % rseed)
	elif with_junk != without:
		push_error("ROAD: the junk moved the street furniture: %d pieces without it, %d with it" % [without.size(), with_junk.size()])
		return false
	# The comparison can say no: a set missing one piece is not the same set.
	var short_set: Dictionary = without.duplicate()
	if not short_set.is_empty():
		short_set.erase(short_set.keys()[0])
		if short_set == without:
			push_error("ROAD: a set short a piece compared equal; the comparison proves nothing")
			return false

	# --- CLUSTER: the junk stands on its row segment's one tile, and only because it is junk -------
	var yard: Variant = _room_map(30, 9, false)
	for tx in 30:
		yard.tiles[tx] = SimTileMap.Tile.Wall
	var junk: Dictionary = {"sizes": FABRICATED_SIZES, "furnishings": [{"key": "prop_barrel", "where": "outdoors", "surfaces": ["paved"], "rarity": 2, "beside": "edge", "cluster": true}]}
	var plain: Dictionary = {"sizes": FABRICATED_SIZES, "furnishings": [{"key": "prop_barrel", "where": "outdoors", "surfaces": ["paved"], "rarity": 2, "beside": "edge"}]}
	var spaced_hits: int = 0
	var unspaced_plain: int = 0
	for seed_val in 8:
		var st: int = seed_val * Dressing._HASH_SEED
		for b in _kept_keys_of(Dressing.occupancy(junk, yard, seed_val), yard, "prop_barrel"):
			if not Dressing._spaced(st, b.x, b.y):
				push_error("CLUSTER: seed %d stood a junk barrel at %s, off its row segment's one tile" % [seed_val, str(b)])
				return false
			spaced_hits += 1
		for b2 in _kept_keys_of(Dressing.occupancy(plain, yard, seed_val), yard, "prop_barrel"):
			if not Dressing._spaced(st, b2.x, b2.y):
				unspaced_plain += 1
	if spaced_hits == 0 or unspaced_plain == 0:
		push_error("CLUSTER: %d junk barrels on their segments' tiles, %d plain barrels off them; the spacing is not read or cannot fail" % [spaced_hits, unspaced_plain])
		return false

	# --- PER_ROOM: one medical cabinet a room, where the plain roll would stand several -----------
	var two_rooms: Variant = _walled_room(25, 12)
	for ty in 12:
		two_rooms.tiles[ty * 25 + 12] = SimTileMap.Tile.Wall
	var one_each: Dictionary = {"sizes": FABRICATED_SIZES, "furnishings": [{"key": "prop_medical_cabinet", "where": "indoors", "surfaces": ["paved"], "rarity": 2, "beside": "wall", "per_room": 1}]}
	var many_each: Dictionary = {"sizes": FABRICATED_SIZES, "furnishings": [{"key": "prop_medical_cabinet", "where": "indoors", "surfaces": ["paved"], "rarity": 2, "beside": "wall"}]}
	var rooms_held: int = 0
	var rooms_over: int = 0
	for seed_val in 4:
		var counts: Dictionary = _per_room_counts(Dressing.occupancy(one_each, two_rooms, seed_val), two_rooms, "prop_medical_cabinet")
		for room in counts:
			if int(counts[room]) > 1:
				push_error("PER_ROOM: seed %d stood %d medical cabinets in one room; a room keeps one" % [seed_val, int(counts[room])])
				return false
			rooms_held += 1
		var plain_counts: Dictionary = _per_room_counts(Dressing.occupancy(many_each, two_rooms, seed_val), two_rooms, "prop_medical_cabinet")
		for room2 in plain_counts:
			if int(plain_counts[room2]) > 1:
				rooms_over += 1
	if rooms_held < 6 or rooms_over == 0:
		push_error("PER_ROOM: %d rooms of eight held their one cabinet, %d rooms took several without the rule; the rule is not read or cannot fail" % [rooms_held, rooms_over])
		return false

	# --- WINDOW: no wall piece's art stands on a tile in front of a window --------------------------
	var lit: Variant = _walled_room(24, 8)
	var panes: Array[int] = [4, 5, 11, 17]
	for px in panes:
		lit.tiles[px] = SimTileMap.Tile.Window
	var shelves: Dictionary = {"sizes": FABRICATED_SIZES, "furnishings": [{"key": "prop_shelf", "where": "indoors", "surfaces": ["paved"], "rarity": 2, "beside": "wall_north"}]}
	var on_wall: int = 0
	for seed_val in 8:
		var wocc: Dictionary = Dressing.occupancy(shelves, lit, seed_val)
		for at in _kept_keys_of(wocc, lit, "prop_shelf"):
			on_wall += 1
			var rect: Rect2i = Dressing._top_rect(wocc, Dressing._kept_top(wocc, lit, at.x, at.y), at.x, at.y)
			for col in range(floori(float(rect.position.x) / 32.0), floori(float(rect.end.x - 1) / 32.0) + 1):
				if at.y == 1 and panes.has(at.x + col):
					push_error("WINDOW: seed %d's shelf at %s covers the tile in front of the window at %d" % [seed_val, str(at), at.x + col])
					return false
	# The same room with its panes walled up: the shelves stand in front of where the windows were.
	var blind: Variant = _walled_room(24, 8)
	var where_panes: int = 0
	for seed_val in 8:
		var bocc: Dictionary = Dressing.occupancy(shelves, blind, seed_val)
		for at in _kept_keys_of(bocc, blind, "prop_shelf"):
			var rect2: Rect2i = Dressing._top_rect(bocc, Dressing._kept_top(bocc, blind, at.x, at.y), at.x, at.y)
			for col2 in range(floori(float(rect2.position.x) / 32.0), floori(float(rect2.end.x - 1) / 32.0) + 1):
				if panes.has(at.x + col2):
					where_panes += 1
	if on_wall == 0 or where_panes == 0:
		push_error("WINDOW: %d shelves on the windowed wall, %d before the walled-up panes; the window rule is not read or cannot fail" % [on_wall, where_panes])
		return false

	# --- VERGE: the grass beside the paving is an edge; the grass away from it is not ---------------
	var verge_map: Variant = _room_map(20, 9, false)
	for i in 20 * 9:
		verge_map.surfaces[i] = SimSurface.Surface.Grass
	for tx in 20:
		verge_map.surfaces[4 * 20 + tx] = SimSurface.Surface.Paved
	var bags: Dictionary = {"sizes": FABRICATED_SIZES, "furnishings": [{"key": "prop_trash_bags", "where": "outdoors", "surfaces": ["grass"], "rarity": 2, "beside": "edge"}]}
	var verge_hits: int = 0
	for seed_val in 8:
		for b3 in _kept_keys_of(Dressing.occupancy(bags, verge_map, seed_val), verge_map, "prop_trash_bags"):
			if b3.y != 3 and b3.y != 5:
				push_error("VERGE: seed %d stood grass bags at %s, off the verge rows" % [seed_val, str(b3)])
				return false
			verge_hits += 1
	if verge_hits == 0:
		push_error("VERGE: no grass bags on the verge over eight seeds; the verge is not an edge")
		return false

	# --- LITTER: a scrap lies anywhere in its tile, on the art grid ---------------------------------
	var paper: Vector2i = Vector2i(11, 12)
	var top_third: int = 0
	var bottom_third: int = 0
	var left_third: int = 0
	var right_third: int = 0
	for ty in 20:
		for tx in 20:
			var off: Vector2i = Dressing._litter_offsets(CANON_SEED * Dressing._HASH_SEED, paper, tx, ty)
			var r: Rect2i = Dressing._art_rect(paper, off.x, off.y)
			if r.position.x < 0 or r.position.y < 0 or r.end.x > 32 or r.end.y > 32:
				push_error("LITTER: a scrap at %s lies at %s, out of its own tile" % [str(Vector2i(tx, ty)), str(r)])
				return false
			var cy: float = float(r.position.y) + float(r.size.y) / 2.0
			var cx: float = float(r.position.x) + float(r.size.x) / 2.0
			top_third += 1 if cy < 32.0 / 3.0 else 0
			bottom_third += 1 if cy > 32.0 - 32.0 / 3.0 else 0
			left_third += 1 if cx < 32.0 / 3.0 else 0
			right_third += 1 if cx > 32.0 - 32.0 / 3.0 else 0
	# The furniture's own range, the scrap's before: every centre in the lower part of the tile.
	var old_low: int = 0
	var ry: Vector2i = Dressing._range_y(paper.y)
	for oy in range(ry.x, ry.y + 1):
		var r_old: Rect2i = Dressing._art_rect(paper, 0, oy)
		if float(r_old.position.y) + float(r_old.size.y) / 2.0 < 32.0 / 3.0:
			old_low += 1
	if top_third == 0 or bottom_third == 0 or left_third == 0 or right_third == 0 or old_low != 0:
		push_error("LITTER: of 400 scraps %d sit high, %d low, %d left, %d right (the furniture's range puts %d high); a scrap should lie anywhere in its tile" % [top_third, bottom_third, left_third, right_third, old_low])
		return false

	# --- CLEAR: a picture wider than its tile does not reach into the clearing ------------------------
	var square := Rect2i(5, 5, 1, 1)
	if not Dressing._reaches_clear(square, Rect2i(-8, 0, 40, 30), 6, 5) or Dressing._reaches_clear(square, Rect2i(4, 0, 24, 30), 6, 5):
		push_error("CLEAR: _reaches_clear cannot tell a shelf reaching west into the clearing from a chair inside its own tile")
		return false
	var cocc: Dictionary = Dressing.occupancy(rblock, rmap, rseed)
	var clear: Rect2i = cocc["clear"]
	var reaching: int = 0
	for ty in range(clear.position.y - 2, clear.end.y + 2):
		for tx in range(clear.position.x - 2, clear.end.x + 2):
			if tx < 0 or ty < 0 or tx >= int(rmap.w) or ty >= int(rmap.h):
				continue
			var kept2: Dictionary = Dressing._kept_top(cocc, rmap, tx, ty)
			if kept2.is_empty() or int(kept2["rank"]) == Dressing.RANK_HELD:
				continue
			if Dressing._reaches_clear(clear, Dressing._top_rect(cocc, kept2, tx, ty), tx, ty):
				reaching += 1
	if reaching != 0:
		push_error("CLEAR: %d kept pictures beside the clearing reach into it" % reaching)
		return false

	# --- the readers ------------------------------------------------------------------------------
	var missing: String = _missing_needle(_function_body(DRESSING_GD, "_furnishing_raw"), ["_entry_reaches_clear(", "_room_keeps("])
	if missing.is_empty():
		missing = _missing_needle(_function_body(DRESSING_GD, "_furnishing_ground_fits"), ["_reaches_window(map, rect, tx, ty)"])
	if missing.is_empty():
		missing = _missing_needle(_function_body(DRESSING_GD, "_entry_rolls"), ["_spaced(seed_term, tx, ty)"])
	if missing.is_empty():
		missing = _missing_needle(_function_body(DRESSING_GD, "_litter_raw"), ["_block_litter("])
	if missing.is_empty():
		missing = _missing_needle(_function_body(DRESSING_GD, "_block_litter"), ["_litter_weight("])
	if not missing.is_empty():
		push_error("a round-one rule has lost its reader: %s" % missing)
		return false
	print("MEASURE_OK salts pinned and repeats dropped; the suburb's %d street furniture pieces stand where they stood with or without the junk; %d junk barrels each on its segment's tile (%d plain ones off it); %d rooms kept one cabinet (%d took several without the rule); %d shelves on a windowed wall, none in front of a pane (%d before walled-up panes); %d grass bags on the verge rows only; scraps lie anywhere in the tile (%d high, %d low); no kept picture reaches into the clearing" % [without.size(), spaced_hits, unspaced_plain, rooms_held, rooms_over, on_wall, where_panes, verge_hits, top_third, bottom_third])
	return true

# --- lane: round 2 of A12's review -------------------------------------------------------------
# Litter dealt by block on both sides of the walls, one fridge a room, a chair only beside its own
# table, a table clear of the plain picks round it, the scrap's tint and vertical flip reaching the
# draw, and the review harness weighing scraps rather than refusing them. Each with a negative.


# Whether a block's dealt count is its quota: `floor(n * 10 / LITTER_TENTHS)` or one more, the jitter
# rounding the share either way.
func _within_quota(dealt: int, floor_tiles: int) -> bool:
	var low: int = floori(float(floor_tiles * 10) / float(Dressing.LITTER_TENTHS))
	return dealt == low or dealt == low + 1


# Every whole block of a map's paved floor on one side of the walls, as `[floor tiles, dealt]`.
func _litter_blocks(occ: Dictionary, map: Variant, indoors: bool, dealt_by: Callable) -> Array:
	var shift: int = Dressing._mix(Dressing._hash_t(int(occ["seed_term"]), 0, 0, Dressing.SALT_LITTER_BLOCK_OFFSET))
	var ox: int = shift % Dressing.LITTER_BLOCK
	var oy: int = (shift >> 8) % Dressing.LITTER_BLOCK
	var out: Array = []
	for by in range(0, int(map.h) / Dressing.LITTER_BLOCK + 2):
		for bx in range(0, int(map.w) / Dressing.LITTER_BLOCK + 2):
			var n: int = 0
			var dealt: int = 0
			var whole: bool = true
			for dy in Dressing.LITTER_BLOCK:
				for dx in Dressing.LITTER_BLOCK:
					var cx: int = bx * Dressing.LITTER_BLOCK - ox + dx
					var cy: int = by * Dressing.LITTER_BLOCK - oy + dy
					if cx < 0 or cy < 0 or cx >= int(map.w) or cy >= int(map.h):
						whole = false
						continue
					if not Dressing._paved_floor(map, cx, cy) or SimTileMap.is_indoors(map, cx, cy) != indoors:
						continue
					n += 1
					if bool(dealt_by.call(cx, cy)):
						dealt += 1
			if whole and n > 0:
				out.append([n, dealt])
	return out


func _the_second_review_holds() -> bool:
	# --- BLOCKS: every block deals its quota, the street's and a room's apart --------------------
	var scrap_block: Dictionary = {"sizes": {"debris_paper": [11, 12]}, "litter": ["debris_paper"]}
	var halves: Variant = _room_map(36, 24, false)
	for ty in 24:
		for tx in range(18, 36):
			halves.indoors[ty * 36 + tx] = 1
	var blocks_judged: int = 0
	var roll_off: int = 0
	for seed_val in 4:
		var bocc: Dictionary = Dressing.occupancy(scrap_block, halves, seed_val)
		var kept_by: Callable = func(cx: int, cy: int) -> bool: return not Dressing._litter_raw(bocc, halves, cx, cy).is_empty()
		# The per-tile roll the blocks replaced, at the same rate: the band has to refuse it somewhere.
		var rolled_by: Callable = func(cx: int, cy: int) -> bool: return Dressing._mix(Dressing.hash_at(seed_val, cx, cy, Dressing.SALT_LITTER_PICK)) % Dressing.LITTER_TENTHS < 10
		for side in [false, true]:
			for row in _litter_blocks(bocc, halves, side, kept_by):
				if not _within_quota(int(row[1]), int(row[0])):
					push_error("BLOCKS: seed %d, a %s block of %d paved tiles took %d scraps; its quota is %d or one more" % [seed_val, "room" if side else "street", int(row[0]), int(row[1]), floori(float(int(row[0]) * 10) / float(Dressing.LITTER_TENTHS))])
					return false
				blocks_judged += 1
			for row2 in _litter_blocks(bocc, halves, side, rolled_by):
				if not _within_quota(int(row2[1]), int(row2[0])):
					roll_off += 1
	if blocks_judged < 16 or roll_off == 0 or _within_quota(9, 36):
		push_error("BLOCKS: %d blocks judged, %d off quota under a per-tile roll; the band cannot fail or had nothing to judge" % [blocks_judged, roll_off])
		return false

	# --- FRIDGE: the shipped fridge and cabinet are one a room ------------------------------------
	var boot: Dictionary = SimBoot.playable(CANON_SEED, GATE_SIZE)
	var rworld: Variant = boot["world"]
	var rmap: Variant = boot["map"]
	var rblock: Dictionary = Dressing.block_of(rworld)
	var rocc: Dictionary = Dressing.occupancy(rblock, rmap, int(rworld.seed))
	var one_a_room: Array = ["prop_fridge", "prop_medical_cabinet"]
	for entry in Dressing._furnishing_entries(rblock):
		if one_a_room.has(String(entry[Dressing.FE_KEY])) and int(entry[Dressing.FE_PER_ROOM]) != 1:
			push_error("FRIDGE: the shipped %s keeps %d a room; the review asked for one" % [String(entry[Dressing.FE_KEY]), int(entry[Dressing.FE_PER_ROOM])])
			return false
	var fridges: int = 0
	for key in one_a_room:
		var counts: Dictionary = _per_room_counts(rocc, rmap, String(key))
		for room in counts:
			if int(counts[room]) > 1:
				push_error("FRIDGE: room %d of the suburb holds %d of %s" % [int(room), int(counts[room]), String(key)])
				return false
			if String(key) == "prop_fridge":
				fridges += 1
	if fridges == 0:
		print("FRIDGE SKIP: the suburb stands no fridge at seed %d; the per-room count had nothing to judge (PER_ROOM holds the rule)" % int(rworld.seed))

	# --- CHAIRS: a chair stands only beside its own kept table ------------------------------------
	var set_block: Dictionary = {"sizes": FABRICATED_SIZES, "furnishings": [
		{"key": "prop_table", "where": "indoors", "surfaces": ["paved"], "rarity": 9, "group": "table"},
		{"key": "prop_chair", "where": "indoors", "surfaces": ["paved"], "rarity": 2, "group": "seat"},
	]}
	var hall: Variant = _walled_room(24, 18)
	var chairs: int = 0
	var orphaned: int = 0
	for seed_val in 4:
		var cocc: Dictionary = Dressing.occupancy(set_block, hall, seed_val)
		for ty in 18:
			for tx in 24:
				var raw: Dictionary = Dressing._raw_top(cocc, hall, tx, ty)
				if String(raw.get("key", "")) != "prop_chair":
					continue
				var faces: Vector2i = raw["table"]
				var table: Dictionary = Dressing._kept_alone(cocc, hall, faces.x, faces.y)
				var kept: Dictionary = Dressing._kept_top(cocc, hall, tx, ty)
				if table.is_empty():
					orphaned += 1
					if not kept.is_empty():
						push_error("CHAIRS: seed %d kept a chair at %s whose table at %s the overlap rule dropped" % [seed_val, str(Vector2i(tx, ty)), str(faces)])
						return false
					continue
				if kept.is_empty():
					continue
				chairs += 1
				if absi(faces.x - tx) + absi(faces.y - ty) != 1:
					push_error("CHAIRS: seed %d's chair at %s faces a table at %s, not beside it" % [seed_val, str(Vector2i(tx, ty)), str(faces)])
					return false
	if chairs == 0:
		push_error("CHAIRS: no chair kept in the hall over four seeds; the rule had nothing to judge")
		return false
	# The shipped rules seldom drop a table a chair faces, so the orphan half is also proven on a
	# fabricated drop: the same chair, its table's raw top taken away, is not kept.
	var focc: Dictionary = Dressing.occupancy(set_block, hall, 0)
	var proven: bool = false
	for ty in 18:
		for tx in 24:
			var top: Dictionary = Dressing._kept_top(focc, hall, tx, ty)
			if proven or String(top.get("key", "")) != "prop_chair":
				continue
			var at: Vector2i = top["table"]
			(focc["memo"] as Dictionary)[at.y * 24 + at.x] = {}
			if not Dressing._kept_top(focc, hall, tx, ty).is_empty():
				push_error("CHAIRS: the chair at %s stayed with its table at %s taken away" % [str(Vector2i(tx, ty)), str(at)])
				return false
			proven = true
	if not proven:
		push_error("CHAIRS: no chair in seed 0's hall to take a table from; the fabricated drop proves nothing")
		return false

	# --- NEIGHBOUR: a table stands where its eight neighbours roll no plain picture ---------------
	var with_plain: Dictionary = {"sizes": FABRICATED_SIZES, "furnishings": (set_block["furnishings"] as Array) + [
		{"key": "prop_shelf", "where": "indoors", "surfaces": ["paved"], "rarity": 2, "beside": "wall_north"},
		{"key": "prop_medical_cabinet", "where": "indoors", "surfaces": ["paved"], "rarity": 6},
	]}
	var crowded: int = 0
	var anchors: int = 0
	for seed_val in 4:
		var pocc: Dictionary = Dressing.occupancy(with_plain, hall, seed_val)
		var bare_occ: Dictionary = Dressing.occupancy(set_block, hall, seed_val)
		var table_p: Array = (pocc["tables"] as Array)[0]
		var table_b: Array = (bare_occ["tables"] as Array)[0]
		for ty in 18:
			for tx in 24:
				var with_t: bool = Dressing._anchor_in_cell(pocc, hall, table_p, tx, ty) == Vector2i(tx, ty)
				var bare_t: bool = Dressing._anchor_in_cell(bare_occ, hall, table_b, tx, ty) == Vector2i(tx, ty)
				if not with_t and not bare_t:
					continue
				var beside: bool = false
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if (dx != 0 or dy != 0) and not Dressing._furnishing_raw(pocc["furnish"], hall, int(pocc["seed_term"]), tx + dx, ty + dy, pocc["clear"], pocc["road"], pocc).is_empty():
							beside = true
				if with_t:
					anchors += 1
					if beside:
						push_error("NEIGHBOUR: seed %d stood a table at %s beside a plain pick" % [seed_val, str(Vector2i(tx, ty))])
						return false
				elif beside:
					crowded += 1
	if anchors == 0 or crowded == 0:
		push_error("NEIGHBOUR: %d tables beside the plain picks' hall, %d that stand without them where a pick would crowd them; the rule is not read or cannot fail" % [anchors, crowded])
		return false

	# --- TINT: a scrap's tint and its vertical flip reach the draw ---------------------------------
	var grey: int = 0
	var white: int = 0
	var upside: int = 0
	var upright: int = 0
	for ty in int(rmap.h):
		for tx in int(rmap.w):
			var placed: Dictionary = Dressing.litter_placed_in(rocc, tx, ty)
			if placed.is_empty():
				continue
			if (placed["tint"] as Color).is_equal_approx(Color.WHITE):
				white += 1
			else:
				grey += 1
			if bool(placed["flip_v"]):
				upside += 1
			else:
				upright += 1
	var plain_occ: Dictionary = Dressing.occupancy(scrap_block, halves, 1)
	var plain_tinted: int = 0
	for ty in 24:
		for tx in 36:
			var p2: Dictionary = Dressing.litter_placed_in(plain_occ, tx, ty)
			if not p2.is_empty() and not (p2["tint"] as Color).is_equal_approx(Color.WHITE):
				plain_tinted += 1
	if grey == 0 or white == 0 or upside == 0 or upright == 0 or plain_tinted != 0:
		push_error("TINT: %d grey and %d plain scraps, %d upside down and %d upright on the suburb, %d tinted under a block naming no tints" % [grey, white, upside, upright, plain_tinted])
		return false

	# --- the readers ------------------------------------------------------------------------------
	var missing: String = _missing_needle(_function_body(MAIN_GD, "_draw_litter"), ["placed.get(\"flip_v\"", "placed.get(\"tint\""])
	if missing.is_empty():
		missing = _missing_needle(_function_body(DRESSING_GD, "_kept_seated"), ["_kept_alone(occ, map, at.x, at.y)"])
	if missing.is_empty():
		missing = _missing_needle(_function_body(DRESSING_GD, "_anchor_fits"), ["_furnishing_raw(occ[\"furnish\"]"])
	if missing.is_empty():
		missing = _missing_needle(_function_body("res://review/scenes.gd", "_street_spot"), ["_scraps_near("])
	if missing.is_empty():
		missing = _missing_needle(_function_body("res://review/scenes.gd", "_interior_spot"), ["colony_start(", "_shot_score("])
	if not missing.is_empty():
		push_error("a round-two rule has lost its reader: %s" % missing)
		return false
	print("REVIEW2_OK %d blocks dealt their quota on both sides of the walls (%d off it under a per-tile roll); the fridge and the cabinet one a room; %d chairs each beside its own table, %d over a dropped table dropped with it (and a fabricated drop); %d tables clear of the plain picks round them (%d spots the rule refused); scraps %d grey and %d plain, %d upside down, none tinted without tints; main.gd and the harness read it" % [blocks_judged, roll_off, chairs, orphaned, anchors, crowded, grey, white, upside])
	return true


# --- OLD_STREET: main's street furniture stands where main drew it ----------------------------

# The street furniture's roll as main drew it before A12, frozen here as the reference the shipped
# roll is judged against: main's list in its own order (the salt is the index), the shifted hash and
# the old ground rule. Copied from main's dressing.gd at 9d9bc23; it must never follow dressing.gd.
const OLD_STREET: Array = [
	["prop_dumpster", 20, 4, ["paved"], true],
	["prop_concrete_barrier", 110, 5, ["paved"], false],
	["prop_traffic_cone", 90, 6, ["paved"], false],
	["prop_fence_post", 70, 7, ["grass", "dirt"], false],
	["prop_road_sign", 140, 9, ["paved"], false],
	["prop_streetlamp", 180, 10, ["paved"], false],
]
const OLD_STREET_KEYS: Array[String] = ["prop_concrete_barrier", "prop_traffic_cone", "prop_fence_post", "prop_road_sign", "prop_streetlamp"]


static func _old_floor(map: Variant, tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return false
	var idx: int = ty * int(map.w) + tx
	return int(map.tiles[idx]) == SimTileMap.Tile.Floor and int(map.indoors[idx]) == 0


static func _old_tile_is(map: Variant, tx: int, ty: int, tile: int) -> bool:
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return false
	return int(map.tiles[ty * int(map.w) + tx]) == tile


# What main's furnishing_key answered for an outdoor tile, or "".
static func _old_street_pick(map: Variant, seed_val: int, tx: int, ty: int) -> String:
	if not _old_floor(map, tx, ty):
		return ""
	var surface: int = int(map.surfaces[ty * int(map.w) + tx])
	var base: int = (tx * 73856093) ^ (ty * 19349663) ^ (seed_val * 83492791)
	for row in OLD_STREET:
		var mask: int = 0
		for name in row[3] as Array:
			mask |= 1 << Dressing.surface_named(String(name))
		if (mask >> surface) & 1 == 0:
			continue
		if (((base ^ ((300 + int(row[2])) * 2654435761)) & 0x7fffffff) >> 8) % int(row[1]) != 0:
			continue
		if not (_old_floor(map, tx - 1, ty) and _old_floor(map, tx + 1, ty)):
			continue
		if _old_tile_is(map, tx, ty - 1, SimTileMap.Tile.Door) or _old_tile_is(map, tx, ty + 1, SimTileMap.Tile.Door):
			continue
		if bool(row[4]) and not (_old_tile_is(map, tx, ty - 1, SimTileMap.Tile.Wall) or _old_tile_is(map, tx, ty + 1, SimTileMap.Tile.Wall) or _old_tile_is(map, tx - 1, ty, SimTileMap.Tile.Wall) or _old_tile_is(map, tx + 1, ty, SimTileMap.Tile.Wall)):
			continue
		return String(row[0])
	return ""


# Over a map, the tiles where main's street furniture and the kept pictures disagree: `missing`, a
# piece main drew that the block does not keep there (or keeps off main's own pixels), and `extra`, a street piece the block keeps
# where main drew none (or drew another). `held` counts main's pieces under a sim object.
static func _old_street_diff(block: Dictionary, map: Variant, seed_val: int) -> Dictionary:
	var occ: Dictionary = Dressing.occupancy(block, map, seed_val)
	var same: int = 0
	var missing: Array = []
	var extra: Array = []
	for ty in int(map.h):
		for tx in int(map.w):
			if not _old_floor(map, tx, ty):
				continue
			var was: String = _old_street_pick(map, seed_val, tx, ty)
			var top: Dictionary = Dressing._kept_top(occ, map, tx, ty)
			var now: String = String(top.get("key", ""))
			var now_street: bool = OLD_STREET_KEYS.has(now)
			if OLD_STREET_KEYS.has(was):
				# Main hung it centred on its tile's south edge, unmirrored: offsets (0, 0).
				if now == was and (int(top.get("ox", 0)) != 0 or int(top.get("oy", 0)) != 0 or bool(top.get("flip", false))):
					missing.append([Vector2i(tx, ty), was, "%s shifted (%d, %d)%s" % [now, int(top.get("ox", 0)), int(top.get("oy", 0)), " mirrored" if bool(top.get("flip", false)) else ""]])
				elif now == was:
					same += 1
				else:
					missing.append([Vector2i(tx, ty), was, now])
			elif now_street:
				extra.append([Vector2i(tx, ty), now])
	return {"same": same, "missing": missing, "extra": extra}


func _the_old_street_stands() -> bool:
	var tree: Dictionary = ContentLoader.load_tree()
	var boot: Dictionary = SimBoot.playable(CANON_SEED, GATE_SIZE)
	var block: Dictionary = Dressing.block_of(boot["world"])
	var maps: Array = [["the boot map", boot["map"], int(boot["world"].seed)]]
	for district_id in FURNISH_DISTRICTS:
		maps.append([district_id, SimWorldgen.generate(CANON_SEED, GATE_SIZE, tree, district_id), CANON_SEED])
	var same: int = 0
	for row in maps:
		var diff: Dictionary = _old_street_diff(block, row[1], int(row[2]))
		if not (diff["missing"] as Array).is_empty() or not (diff["extra"] as Array).is_empty():
			push_error("OLD_STREET: %s: main's street furniture moved: missing %s, extra %s" % [String(row[0]), str((diff["missing"] as Array).slice(0, 4)), str((diff["extra"] as Array).slice(0, 4))])
			return false
		same += int(diff["same"])
	if same < 20:
		push_error("OLD_STREET: only %d pieces of main's street furniture on the judged maps; too few to prove the roll" % same)
		return false
	# TN: the same entries rolled the shipped way (no `roll: kept`) move main's pieces.
	var plain_block: Dictionary = block.duplicate(true)
	var shadowless: Dictionary = block.duplicate(true)
	for entry in plain_block["furnishings"] as Array:
		(entry as Dictionary).erase("roll")
		(entry as Dictionary).erase("shadow")
	var kept_list: Array = []
	for entry in shadowless["furnishings"] as Array:
		if not bool((entry as Dictionary).get("shadow", false)):
			kept_list.append(entry)
	shadowless["furnishings"] = kept_list
	var moved: int = 0
	var shadow_extra: int = 0
	for row in maps:
		if moved == 0:
			var pd: Dictionary = _old_street_diff(plain_block, row[1], int(row[2]))
			moved += (pd["missing"] as Array).size() + (pd["extra"] as Array).size()
		if shadow_extra == 0:
			shadow_extra += (_old_street_diff(shadowless, row[1], int(row[2]))["extra"] as Array).size()
	if moved == 0:
		push_error("OLD_STREET: rolling the street furniture the plain way moved nothing; the lane cannot say no")
		return false
	if shadow_extra == 0:
		push_error("OLD_STREET: dropping the old wall dumpster's shadow added no street piece; the shadow is a dead socket")
		return false
	if not _function_body(DRESSING_GD, "_raw_top_uncached").contains("_kept_raw(occ, map, tx, ty)") or not _function_body(DRESSING_GD, "_beats").contains("other.has(\"kept\")") or not _function_body(DRESSING_GD, "_kept_alone").contains("top.has(\"kept\")"):
		push_error("OLD_STREET: the raw top, the overlap rule or the keep no longer read the kept roll")
		return false
	print("OLD_STREET_OK %d pieces of main's street furniture on %d maps stand where main drew them, none missing, none added; the plain roll moves %d on the first map it is tried on, and without the dumpster's shadow %d appear where main drew a dumpster" % [same, maps.size(), moved, shadow_extra])
	return true


# --- PASSAGE: every room keeps one walk round its furniture ----------------------------------

# Over a map's rooms: how many are cut (their free floor is not one four-connected walk, or a tile
# inside a doorway holds a piece), and how many free tiles were judged. A tile is taken when a kept
# standing or flat picture stands on it; scraps and the old street furniture do not count.
static func _cut_rooms(block: Dictionary, map: Variant, seed_val: int, keep: bool = true, held: Dictionary = {}, dressing_sees_held: bool = true) -> Vector2i:
	var occ: Dictionary = Dressing.occupancy(block, map, seed_val, held if dressing_sees_held else {})
	occ["keep_passages"] = keep
	var w: int = int(map.w)
	var room_seen: Dictionary = {}
	var cut: int = 0
	var judged: int = 0
	for ty in int(map.h):
		for tx in w:
			var room: int = Dressing._room_of(occ, map, tx, ty)
			if room < 0 or room_seen.has(room):
				continue
			room_seen[room] = true
			var tiles: PackedInt32Array = (occ["room_tiles"] as Array)[room]
			var in_room: Dictionary = {}
			var taken: Dictionary = {}
			var by_sim: Dictionary = {}
			var door_blocked: bool = false
			for idx in tiles:
				in_room[idx] = true
				# A sim object's tile is taken whether or not the dressing was told of it.
				if held.has(Vector2i(idx % w, floori(float(idx) / float(w)))):
					by_sim[idx] = true
					taken[idx] = true
					continue
				var top: Dictionary = Dressing._kept_top(occ, map, idx % w, floori(float(idx) / float(w)))
				if not top.is_empty() and int(top["rank"]) >= Dressing.RANK_FLAT and int(top["rank"]) != Dressing.RANK_HELD:
					taken[idx] = true
					if Dressing._by_door(map, idx % w, floori(float(idx) / float(w))):
						door_blocked = true
			judged += tiles.size() - taken.size()
			if door_blocked or _closes_a_passage(w, in_room, taken, by_sim):
				cut += 1
				continue
			var walks: int = _walk_of(w, tiles, in_room, taken)
			if walks > 1 and walks > _walk_of(w, tiles, in_room, by_sim):
				cut += 1
	return Vector2i(cut, judged)


# Whether a picture closes a passage: the free tiles on its four sides are not all joined by free
# tiles within Dressing.PASSAGE_REACH of it, so a walk that ran through its tile now has a long way
# round. A sim object's own tile is not judged. The gate's own fill, not dressing.gd's.
static func _closes_a_passage(w: int, in_room: Dictionary, taken: Dictionary, by_sim: Dictionary) -> bool:
	for idx in taken:
		if by_sim.has(idx):
			continue
		var x: int = int(idx) % w
		var box: Dictionary = {}
		var reach: int = Dressing.PASSAGE_REACH
		for dy in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var n: int = int(idx) + dy * w + dx
				if (dx != 0 or dy != 0) and x + dx >= 0 and x + dx < w and in_room.has(n) and not taken.has(n):
					box[n] = true
		var sides: Array[int] = []
		for n in [int(idx) - w, int(idx) + w, int(idx) - 1 if x > 0 else -1, int(idx) + 1 if x < w - 1 else -1]:
			if box.has(n):
				sides.append(n)
		if sides.size() < 2:
			continue
		var reached: Dictionary = {sides[0]: true}
		var queue: Array[int] = [sides[0]]
		while not queue.is_empty():
			var at: int = queue.pop_back()
			for n in [at - w, at + w, at - 1, at + 1]:
				if box.has(n) and not reached.has(n) and absi(int(n) % w - at % w) <= 1:
					reached[n] = true
					queue.append(int(n))
		for n in sides:
			if not reached.has(n):
				return true
	return false


# The gate's own flood fill (not dressing.gd's): how many walks the room's free tiles make.
static func _walk_of(w: int, tiles: PackedInt32Array, in_room: Dictionary, taken: Dictionary) -> int:
	var reached: Dictionary = {}
	var walks: int = 0
	for start in tiles:
		if taken.has(start) or reached.has(start):
			continue
		walks += 1
		reached[start] = true
		var queue: Array[int] = [start]
		while not queue.is_empty():
			var at: int = queue.pop_back()
			var x: int = at % w
			for n in [at - w, at + w, at - 1 if x > 0 else -1, at + 1 if x < w - 1 else -1]:
				if int(n) >= 0 and in_room.has(n) and not taken.has(n) and not reached.has(n):
					reached[n] = true
					queue.append(int(n))
	return walks


func _the_rooms_stay_walkable() -> bool:
	var tree: Dictionary = ContentLoader.load_tree()
	var boot: Dictionary = SimBoot.playable(CANON_SEED, GATE_SIZE)
	var block: Dictionary = Dressing.block_of(boot["world"])
	var held: Dictionary = Dressing.held_props(boot["world"])
	var maps: Array = [["the boot map", boot["map"], int(boot["world"].seed), held]]
	for district_id in FURNISH_DISTRICTS:
		maps.append([district_id, SimWorldgen.generate(CANON_SEED, GATE_SIZE, tree, district_id), CANON_SEED, {}])
	var judged: int = 0
	for row in maps:
		var got: Vector2i = _cut_rooms(block, row[1], int(row[2]), true, row[3])
		if got.x != 0:
			push_error("PASSAGE: %s has %d rooms whose free floor is cut by their furniture" % [String(row[0]), got.x])
			return false
		judged += got.y
	# TN: without the rule the same maps cut rooms, so the rule has work and the fill can say no.
	var cut_without: int = 0
	for row in maps:
		cut_without += _cut_rooms(block, row[1], int(row[2]), false, row[3]).x
		if cut_without > 0:
			break
	if cut_without == 0:
		push_error("PASSAGE: no room on the judged maps is cut even without the rule; the rule is not proved")
		return false
	# The round-3 corridor, built by hand: a two-row corridor whose west end a crate holds on one row,
	# with a way round through a room to the south, and barrels and pallets that roll on every wall
	# tile. No piece may close the corridor's other row, though the room has a way round.
	var hall: Variant = _corridor_map()
	var corridor_block: Dictionary = {"sizes": block["sizes"], "furnishings": [{"key": "prop_barrel", "where": "indoors", "surfaces": ["paved"], "rarity": 2, "beside": "wall"}]}
	# The crate stands on the first tile of the corridor's south row where a dressing not told of it
	# rolls a barrel on the tile north of it -- the case to refuse.
	var crate: Dictionary = {}
	var blind: int = 0
	for cx in range(2, 13):
		crate = {Vector2i(cx, 2): Rect2i(0, 0, Dressing.ART_PER_TILE, Dressing.ART_PER_TILE)}
		# TN: the dressing not told of the crate puts a barrel beside it and closes the corridor.
		blind = _cut_rooms(corridor_block, hall, 7, true, crate, false).x
		if blind > 0:
			break
	var shut: int = _cut_rooms(corridor_block, hall, 7, true, crate).x
	var shut_without: int = _cut_rooms(corridor_block, hall, 7, false, crate).x
	if shut != 0 or shut_without == 0 or blind == 0:
		push_error("PASSAGE: the hand-built corridor is closed %d times with the rule, %d without it and %d with the crate unseen; want 0, more and more" % [shut, shut_without, blind])
		return false
	if held.is_empty():
		push_error("PASSAGE: the boot world stands no sim object; the held tiles are not judged")
		return false
	if not _function_body(DRESSING_GD, "_kept_top").contains("_room_drops(occ, map, room)"):
		push_error("PASSAGE: _kept_top no longer asks _room_drops; the rule has lost its reader")
		return false
	print("PASSAGE_OK every room on %d maps keeps its walks and doorways clear round its furniture and the sim's own %d objects, and no piece closes a passage (%d free tiles judged); without the rule %d rooms are cut on the first map that cuts any; a hand-built corridor with a crate in one row and a way round stays open, closed %d times without the rule and %d with the crate unseen" % [maps.size(), held.size(), judged, cut_without, shut_without, blind])
	return true


# --- SEATED: no table stands in a room without a chair of its own ------------------------------

# Over a map's rooms: how many kept tables (a run of side-by-side tables counted once) have no kept
# chair facing them, and how many tables were judged. North-wall counters are not grouped tables
# (their `prio` is not 2) and are not judged.
static func _chairless_tables(block: Dictionary, map: Variant, seed_val: int, keep: bool = true) -> Vector2i:
	var occ: Dictionary = Dressing.occupancy(block, map, seed_val)
	occ["keep_passages"] = keep
	var w: int = int(map.w)
	var tables: Dictionary = {}
	var faced: Dictionary = {}
	for ty in int(map.h):
		for tx in w:
			if Dressing._room_of(occ, map, tx, ty) < 0:
				continue
			var top: Dictionary = Dressing._kept_top(occ, map, tx, ty)
			if top.is_empty():
				continue
			if int(top.get("prio", 0)) == 2:
				tables[ty * w + tx] = true
			elif top.get("table", null) != null:
				var at: Vector2i = top["table"]
				faced[at.y * w + at.x] = true
	var chairless: int = 0
	var judged: int = 0
	for idx in tables:
		if tables.has(int(idx) - 1) and int(idx) % w != 0:
			continue
		judged += 1
		var at: int = int(idx)
		var any: bool = false
		while tables.has(at):
			if faced.has(at):
				any = true
			at += 1
			if at % w == 0:
				break
		if not any:
			chairless += 1
	return Vector2i(chairless, judged)


# The art pixels between the opaque tops of a long table's halves on tiles (ax, y) and (ex, y): the
# west half's last opaque column to the east half's first, 0 when they butt, negative when they overlap.
static func _table_top_gap(occ: Dictionary, west: Dictionary, ax: int, east: Dictionary, ex: int) -> int:
	var tex: Texture2D = Appearance.resolve("prop_table")
	var used: Rect2i = tex.get_image().get_used_rect()
	var size: Vector2i = (occ["sizes"] as Dictionary)["prop_table"]
	var w_left: int = ax * Dressing.ART_PER_TILE + (Dressing.ART_PER_TILE >> 1) - (size.x >> 1) + int(west["ox"])
	var e_left: int = ex * Dressing.ART_PER_TILE + (Dressing.ART_PER_TILE >> 1) - (size.x >> 1) + int(east["ox"])
	var w_mirror: int = size.x - used.end.x if bool(west.get("flip", false)) else used.position.x
	var e_mirror: int = size.x - used.end.x if bool(east.get("flip", false)) else used.position.x
	return (e_left + e_mirror) - (w_left + w_mirror + used.size.x)


func _the_tables_keep_a_chair() -> bool:
	var tree: Dictionary = ContentLoader.load_tree()
	var boot: Dictionary = SimBoot.playable(CANON_SEED, GATE_SIZE)
	var block: Dictionary = Dressing.block_of(boot["world"])
	var maps: Array = [["the boot map", boot["map"], int(boot["world"].seed)]]
	for district_id in FURNISH_DISTRICTS:
		maps.append([district_id, SimWorldgen.generate(CANON_SEED, GATE_SIZE, tree, district_id), CANON_SEED])
	var judged: int = 0
	for row in maps:
		var got: Vector2i = _chairless_tables(block, row[1], int(row[2]))
		if got.x != 0:
			push_error("SEATED: %s keeps %d tables with no chair of their own" % [String(row[0]), got.x])
			return false
		judged += got.y
	if judged == 0:
		push_error("SEATED: no table stands on the judged maps; nothing to judge")
		return false
	# TN: without the room rules the same maps keep a table whose chairs were all refused.
	var without: int = 0
	for row in maps:
		without += _chairless_tables(block, row[1], int(row[2]), false).x
		if without > 0:
			break
	if without == 0:
		push_error("SEATED: no table is chairless even without the rule; the rule is not proved")
		return false
	if not _function_body(DRESSING_GD, "_room_drops").contains("_is_table_piece(pieces, drops"):
		push_error("SEATED: _room_drops no longer drops a chairless table; the rule has lost its reader")
		return false
	print("SEATED_OK %d tables on %d maps each keep a chair of their own; without the rule %d stand alone on the first map that has any" % [judged, maps.size(), without])
	return true


# --- STOCK: barrels and pallets stand in storage rooms; a living room keeps one of each --------

# Over a map: the most barrels (or pallets) one living room keeps, and how many storage rooms keep
# more than one.
static func _stock_by_room(block: Dictionary, map: Variant, seed_val: int) -> Vector2i:
	var occ: Dictionary = Dressing.occupancy(block, map, seed_val)
	var counts: Dictionary = {}
	for ty in int(map.h):
		for tx in int(map.w):
			var room: int = Dressing._room_of(occ, map, tx, ty)
			if room < 0:
				continue
			var key: String = String(Dressing._kept_top(occ, map, tx, ty).get("key", ""))
			if key != "prop_barrel" and key != "prop_pallet_stack":
				continue
			var at := Vector2i(room, 0 if key == "prop_barrel" else 1)
			counts[at] = int(counts.get(at, 0)) + 1
	var living_most: int = 0
	var storage_many: int = 0
	for at in counts:
		var tiles: PackedInt32Array = (occ["room_tiles"] as Array)[(at as Vector2i).x]
		var kind: int = Dressing._room_kind(occ, map, tiles[0] % int(map.w), floori(float(tiles[0]) / float(int(map.w))))
		if kind == Dressing.ROOMS_LIVING:
			living_most = maxi(living_most, int(counts[at]))
		elif int(counts[at]) > 1:
			storage_many += 1
	return Vector2i(living_most, storage_many)


func _the_stock_stays_in_storage() -> bool:
	var tree: Dictionary = ContentLoader.load_tree()
	var boot: Dictionary = SimBoot.playable(CANON_SEED, GATE_SIZE)
	var block: Dictionary = Dressing.block_of(boot["world"])
	var maps: Array = [["the boot map", boot["map"], int(boot["world"].seed)]]
	for district_id in FURNISH_DISTRICTS:
		maps.append([district_id, SimWorldgen.generate(CANON_SEED, GATE_SIZE, tree, district_id), CANON_SEED])
	var storage_many: int = 0
	for row in maps:
		var got: Vector2i = _stock_by_room(block, row[1], int(row[2]))
		if got.x > 1:
			push_error("STOCK: %s has a living room with %d barrels or pallets; a living room keeps one of each" % [String(row[0]), got.x])
			return false
		storage_many += got.y
	if storage_many == 0:
		push_error("STOCK: no storage room on the judged maps keeps more than one barrel or pallet; the storage rule has nothing to show")
		return false
	# TN: the same entries with no `rooms` and no cap put several in a living room.
	var loose: Dictionary = block.duplicate(true)
	for entry in loose["furnishings"] as Array:
		if String((entry as Dictionary).get("rooms", "")) == "living":
			(entry as Dictionary).erase("per_room")
		(entry as Dictionary).erase("rooms")
	var loose_most: int = 0
	for row in maps:
		loose_most = maxi(loose_most, _stock_by_room(loose, row[1], int(row[2])).x)
		if loose_most > 1:
			break
	if loose_most <= 1:
		push_error("STOCK: without the room rule no living room took more than one barrel or pallet; the rule is not proved")
		return false
	print("STOCK_OK living rooms keep at most one barrel and one pallet on %d maps, %d storage rooms keep several; without the rule a living room takes %d" % [maps.size(), storage_many, loose_most])
	return true


# --- SHAPES: the litter is three shapes, not one paper ---------------------------------------

static func _litter_kinds(block: Dictionary, map: Variant, seed_val: int) -> Dictionary:
	var occ: Dictionary = Dressing.occupancy(block, map, seed_val)
	var kinds: Dictionary = {}
	for ty in int(map.h):
		for tx in int(map.w):
			var key: String = Dressing._kept_litter(occ, map, tx, ty)
			if not key.is_empty():
				kinds[key] = int(kinds.get(key, 0)) + 1
	return kinds


func _the_litter_takes_its_shapes() -> bool:
	var boot: Dictionary = SimBoot.playable(CANON_SEED, GATE_SIZE)
	var block: Dictionary = Dressing.block_of(boot["world"])
	var map: Variant = boot["map"]
	var seed_val: int = int(boot["world"].seed)
	var listed: Array = block.get("litter", []) as Array
	var kinds: Dictionary = _litter_kinds(block, map, seed_val)
	for key in ["debris_paper", "debris_sheet", "debris_can"]:
		if not listed.has(key) or int(kinds.get(key, 0)) == 0:
			push_error("SHAPES: the boot map keeps no '%s' scrap (%s); the litter reads as one shape" % [key, str(kinds)])
			return false
		var tex: Texture2D = Appearance.resolve(key)
		var size: Vector2i = Vector2i(tex.get_size()) if tex != null else Vector2i.ZERO
		if size.x < 8 and size.y < 8 or Dressing._sizes(block).get(key, Vector2i.ZERO) != size:
			push_error("SHAPES: '%s' resolves at %s, which is under 8 art pixels or not its block size" % [key, str(size)])
			return false
	# TN: a block listing the paper alone keeps one shape.
	var one: Dictionary = block.duplicate(true)
	one["litter"] = ["debris_paper"]
	if _litter_kinds(one, map, seed_val).size() != 1:
		push_error("SHAPES: a block listing one scrap kept several shapes; the count cannot say no")
		return false
	print("SHAPES_OK the boot map's litter is %s" % str(kinds))
	return true
