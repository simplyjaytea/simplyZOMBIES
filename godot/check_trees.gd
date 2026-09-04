extends SceneTree
# Slice 7, "Trees stand up": docs/30's Dungeon Settlers look, decisions 9-10. A tree is a picture
# that stands in the entity sort, not a canopy over the tiles -- one tall feet-anchored picture
# per Tree tile, hung on the trunk's south-edge centre, y-sorted with the bodies and fading (never
# the body) while a Focal ground point falls inside it. This gate holds the whole path against a
# hand-built fixture both ways, then proves the draw loop actually reaches every rule.
#
# Nine lanes, every assertion with a true positive and a true negative, because a gate that
# cannot fail is worse than no gate:
#
#   KEYS         the three tree keys, through the dressing block: trees.tall == TREE_KEYS, every
#                key resolves art at TREE_CANVAS, canvas_of/anchor_of agree, tree_key covers all
#                three over a scan -- refused for a fabricated key, an empty block, an empty list.
#   SORT         a hand list sorts body/tree/body by depth, exactly as _draw_entities' own
#                comparator does -- refused for a tree appended after the sort and for a sort on x.
#   RECT         body_rect on the tree canvas stands on the feet line at all four zoom rungs --
#                refused for a square canvas, which centres instead.
#   ALPHA        tree_alpha fades only for a body point inside the tree's rect, never outside,
#                never for an empty list, and TREE_FADE_ALPHA itself sits strictly in (0, 1).
#   TILES        tree_tiles answers exactly the seen Tree tiles inside bounds against a hand map
#                -- a seen Floor tile, an unseen tree, a null observer and an out-of-bounds rect
#                all answer nothing; a seen-everything observer answers every tree.
#   FALLBACK     the draw loop actually reaches every rule above, in the order the plan named,
#                with the procedural fallback still standing beside it -- the needle scanner
#                proven on a fabricated body first, check_topdown.gd's convention.
#   SIM UNMOVED  Tile.Tree's opacity and solidity are untouched by this slice, and the pick stays
#                a pure hash: dressing.gd reaches for no RNG.
#   PLAYED       the shipped suburb: every Tree tile the loop would draw is a real Tree tile,
#                seen, and resolves a texture; a see-everything observer accounts for every one.
#   TIERS        the decoded pixels of the three pictures stand inside the tier the sprites
#                README quotes -- box, sole row, tip, side margin, foot, pairwise distinct --
#                refused for a fully opaque canvas and for one lifted off the sole line.
#
# KEYS, TIERS and PLAYED are the lanes that decode the three tree PNGs (tools/sprites/parts/trees.py);
# everything else is pure geometry, or textual against main.gd, and would stay green with the art
# deleted -- which is why KEYS names a missing file rather than skipping it.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimBoot = preload("res://sim/boot.gd")
const World = preload("res://sim/world.gd")
const ContentLoader = preload("res://platform/content_loader.gd")
const Appearance = preload("res://presentation/appearance.gd")
const Dressing = preload("res://presentation/dressing.gd")
const TopDownProjection = preload("res://presentation/projection.gd")
const CameraUtil = preload("res://presentation/camera.gd")

const MAIN_GD: String = "res://presentation/main.gd"
const DRESSING_GD: String = "res://presentation/dressing.gd"
const CANON_SEED: int = 20260805
const GATE_SIZE: int = 64
const BUDGET_SECONDS: float = 60.0

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

	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	if seconds > BUDGET_SECONDS:
		push_error("check_trees ran %.1f s against a %.0f s budget" % [seconds, BUDGET_SECONDS])
		ok = false

	if ok:
		print(
			(
				"TREES_OK %d tree keys resolve at %s; the depth sort places body/tree/body; body_rect stands on the feet line at %d rungs; TREE_FADE_ALPHA %.2f fades only a point inside; TILES answered %d/%d seen trees on the hand map; the draw loop reaches every helper in order; Tile.Tree's opacity/solidity are unmoved and the pick stays a hash; suburb@%d stood %d of %d Tree tiles as drawable; the three pictures stand inside their tier; %.1f s of a %.0f s budget"
				% [
					Appearance.TREE_KEYS.size(),
					str(Appearance.TREE_CANVAS),
					int(CameraUtil.ZOOM_STEPS.size()),
					Dressing.TREE_FADE_ALPHA,
					int(_stash.get("tiles_seen", 0)),
					int(_stash.get("tiles_total", 0)),
					GATE_SIZE,
					int(_stash.get("tree_seen", 0)),
					int(_stash.get("tree_total", 0)),
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
	if listed.size() != Appearance.TREE_KEYS.size():
		push_error("trees.tall lists %d keys, Appearance.TREE_KEYS names %d" % [listed.size(), Appearance.TREE_KEYS.size()])
		return false
	for want_key in Appearance.TREE_KEYS:
		if not listed.has(want_key):
			push_error("Appearance.TREE_KEYS names '%s' but trees.tall does not" % want_key)
			return false
	for got_key in listed:
		if not Appearance.TREE_KEYS.has(String(got_key)):
			push_error("trees.tall names '%s', which Appearance.TREE_KEYS does not" % got_key)
			return false

	for key in Appearance.TREE_KEYS:
		var tex: Variant = Appearance.resolve(key)
		if tex == null:
			push_error("tree key '%s' resolves no picture" % key)
			return false
		if Vector2i((tex as Texture2D).get_size()) != Appearance.TREE_CANVAS:
			push_error("tree key '%s' is %s, not TREE_CANVAS %s" % [key, str((tex as Texture2D).get_size()), str(Appearance.TREE_CANVAS)])
			return false
		if Appearance.canvas_of(key) != Appearance.TREE_CANVAS:
			push_error("canvas_of('%s') is %s, not TREE_CANVAS" % [key, str(Appearance.canvas_of(key))])
			return false

	if Appearance.anchor_of(Appearance.TREE_CANVAS) != Appearance.Anchor.Feet:
		push_error("anchor_of(TREE_CANVAS) is not Feet; a 32x96 canvas is not square")
		return false

	# tree_key covers all three keys over a 16x16 scan of one seed.
	var counts: Dictionary = {}
	for key2 in Appearance.TREE_KEYS:
		counts[key2] = 0
	for ty in 16:
		for tx in 16:
			var picked: String = Dressing.tree_key(block, CANON_SEED, tx, ty)
			if not counts.has(picked):
				push_error("tree_key(%d,%d) answered '%s', not one of %s" % [tx, ty, picked, str(Appearance.TREE_KEYS)])
				return false
			counts[picked] = int(counts[picked]) + 1
	for key3 in Appearance.TREE_KEYS:
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

	print("KEYS OK trees.tall == Appearance.TREE_KEYS (%d keys); every key resolves at TREE_CANVAS %s with canvas_of/anchor_of (Feet) agreeing; tree_key covered all 3 over a 16x16 scan %s; a fabricated key, an empty block and an empty tall list all answer nothing" % [listed.size(), str(Appearance.TREE_CANVAS), str(counts)])
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
	for zoom in CameraUtil.ZOOM_STEPS:
		var scale: float = Appearance.blit_scale(zoom)
		var size: Vector2 = Vector2(Appearance.TREE_CANVAS) * scale
		var rect: Rect2 = Appearance.body_rect(sx, sy, size, 1.0)
		var want_bottom: float = sy + Appearance.FOOT_DROP_PX
		var got_bottom: float = rect.position.y + rect.size.y
		if got_bottom != want_bottom:
			push_error("zoom %.0f: bottom is %.2f, want %.2f (sy + FOOT_DROP_PX)" % [zoom, got_bottom, want_bottom])
			return false
		if rect.size.x != 32.0 * scale:
			push_error("zoom %.0f: width is %.2f, want %.2f" % [zoom, rect.size.x, 32.0 * scale])
			return false
		if rect.size.y != 96.0 * scale:
			push_error("zoom %.0f: height is %.2f, want %.2f" % [zoom, rect.size.y, 96.0 * scale])
			return false
		var want_left: float = roundf(sx - rect.size.x / 2.0)
		if rect.position.x != want_left:
			push_error("zoom %.0f: left is %.2f, want round(sx - width/2) = %.2f" % [zoom, rect.position.x, want_left])
			return false

	# TN: a square canvas centres on the point instead of standing on it.
	var square: Rect2 = Appearance.body_rect(sx, sy, Vector2(64, 64), 1.0)
	if square.position.y + square.size.y == sy + Appearance.FOOT_DROP_PX:
		push_error("a square canvas's bottom landed on the feet line; the centred negative is dead")
		return false

	print("RECT OK bottom == sy + %.1f, width 32*scale, height 96*scale, left == round(sx - width/2) at all %d zoom rungs; a square canvas centres instead" % [Appearance.FOOT_DROP_PX, CameraUtil.ZOOM_STEPS.size()])
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
# sentence: assets/sprites/README.md quotes this lane, and slice 9's stands author against it.
const SIDE_CLEAR_PX: int = 3
const WIDTH_MIN: int = 20
const WIDTH_MAX: int = 26
const HEIGHT_MIN: int = 84
const HEIGHT_MAX: int = 92
const TIP_ROW_MAX: int = 11
const FOOT_MIN: int = 5
const FOOT_MAX: int = 9


# The opaque box of one picture, its sole row, and how wide the foot is on that row. {} for a
# picture with no opaque pixel at all, which _judge_tier reports as its own failure.
func _bounds_of(image: Image) -> Dictionary:
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
	var foot: int = 0
	for fx in image.get_width():
		if image.get_pixel(fx, max_y).a > 0.0:
			foot += 1
	return {"min_x": min_x, "max_x": max_x, "min_y": min_y, "max_y": max_y, "foot": foot}


# Why this picture is outside the tier, or "" when it stands inside it. One predicate, so the
# fabricated negatives below are refused by exactly the rule the real pictures pass.
func _judge_tier(b: Dictionary) -> String:
	if b.is_empty():
		return "is entirely transparent"
	var w: int = int(b["max_x"]) - int(b["min_x"]) + 1
	var h: int = int(b["max_y"]) - int(b["min_y"]) + 1
	if w < WIDTH_MIN or w > WIDTH_MAX:
		return "is %d px wide, outside [%d, %d]" % [w, WIDTH_MIN, WIDTH_MAX]
	if h < HEIGHT_MIN or h > HEIGHT_MAX:
		return "is %d px tall, outside [%d, %d]" % [h, HEIGHT_MIN, HEIGHT_MAX]
	if int(b["max_y"]) != int(Appearance.TREE_CANVAS.y) - 1:
		return "stands on row %d, not the sole line %d" % [int(b["max_y"]), int(Appearance.TREE_CANVAS.y) - 1]
	if int(b["min_y"]) > TIP_ROW_MAX:
		return "tips at row %d, below the top %d rows" % [int(b["min_y"]), TIP_ROW_MAX + 1]
	if int(b["min_x"]) < SIDE_CLEAR_PX or int(b["max_x"]) > int(Appearance.TREE_CANVAS.x) - 1 - SIDE_CLEAR_PX:
		return "reaches x [%d, %d], inside the %d px side margin" % [int(b["min_x"]), int(b["max_x"]), SIDE_CLEAR_PX]
	if int(b["foot"]) < FOOT_MIN or int(b["foot"]) > FOOT_MAX:
		return "stands on a %d px foot, outside [%d, %d]" % [int(b["foot"]), FOOT_MIN, FOOT_MAX]
	return ""


func _the_pictures_stand_inside_their_tier() -> bool:
	Appearance.forget()
	var boxes: Array = []
	var datas: Array = []
	for key in Appearance.TREE_KEYS:
		var tex: Variant = Appearance.resolve(key)
		if tex == null:
			push_error("tree key '%s' resolves no picture; TIERS has nothing to judge" % key)
			return false
		var img: Image = (tex as Texture2D).get_image()
		var b: Dictionary = _bounds_of(img)
		var why: String = _judge_tier(b)
		if not why.is_empty():
			push_error("%s %s" % [key, why])
			return false
		boxes.append("%dx%d" % [int(b["max_x"]) - int(b["min_x"]) + 1, int(b["max_y"]) - int(b["min_y"]) + 1])
		var data: PackedByteArray = img.get_data()
		for other in datas:
			if (other as PackedByteArray) == data:
				push_error("two tree pictures are pixel-identical; the variation is dead")
				return false
		datas.append(data)

	# TN, through the same predicate: a canvas filled edge to edge is too wide, and a picture
	# hanging above the sole line does not stand on it.
	var w: int = int(Appearance.TREE_CANVAS.x)
	var h: int = int(Appearance.TREE_CANVAS.y)
	var solid: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	solid.fill(Color(0.0, 0.0, 0.0, 1.0))
	if _judge_tier(_bounds_of(solid)).is_empty():
		push_error("a fully opaque canvas passed the tier bounds; TIERS cannot say no")
		return false
	var floating: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	floating.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in range(2, 90):
		for x in range(SIDE_CLEAR_PX, w - SIDE_CLEAR_PX):
			floating.set_pixel(x, y, Color(0.0, 0.0, 0.0, 1.0))
	if _judge_tier(_bounds_of(floating)).is_empty():
		push_error("a picture hanging above the sole line passed the tier bounds; TIERS cannot say no")
		return false

	print("TIERS OK %d pictures at %s: boxes %s, all standing on row %d, tips within the top %d rows, %d clear px either side, feet in [%d, %d], pairwise distinct; a fully opaque canvas and one hanging above the sole line are both refused" % [Appearance.TREE_KEYS.size(), str(Appearance.TREE_CANVAS), str(boxes), h - 1, TIP_ROW_MAX + 1, SIDE_CLEAR_PX, FOOT_MIN, FOOT_MAX])
	return true


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
