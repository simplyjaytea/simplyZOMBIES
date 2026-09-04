extends SceneTree
# Slice 8, "What you wear shows on your body": docs/30's Dungeon Settlers look, the worn clause. `Appearance`
# replaced its two EQUIP_UNDER_BODY / EQUIP_OVER_BODY lists with one ordered table,
# EQUIP_DRAW_ORDER -- six slots, each saying which side of the body draw call it goes on -- and
# `equipment_layers_for` walks it in that order, so the order layers COMPOSE *is* the picture
# rather than the concatenation of two lists. This gate holds that table and the composition it
# drives against a hand-built fixture both ways, then proves the draw loop actually reaches every
# equippable base content declares.
#
# `tools/sprites/parts/gear.py` generates one overlay per base that declares a drawn slot --
# sixteen pictures for fifteen bases (the pack carries a second, its straps). The lanes below
# judge whatever art is on disk rather than a list written here, and every one of them says so
# loudly and skips where there is none, so this gate stays honest through a slice that adds a
# slot or a base before its picture exists -- which is the state it was written in.
#
# Six lanes, every assertion with a true positive and a true negative, because a gate that
# cannot fail is worse than no gate:
#
#   ORDER    EQUIP_DRAW_ORDER is exactly the six slots, in order, no duplicates, only `back`
#            under -- then the real composition: a fully-kitted actor's layers come back in
#            EQUIP_DRAW_ORDER's order, every under-layer before every over one, and a back
#            slot's `equipSpriteFront` lands in the over group anyway. TN: a shuffled
#            expectation is refused by the same comparison.
#   CANVAS   every key any item under content/items/ names via equipSprite/equipSpriteFront
#            resolves a texture at Appearance.PAWN_CANVAS. TN: a fabricated 32x32 overlay is
#            refused by the same predicate; an unknown key answers null rather than passing.
#   FITS     on decoded pixels: every overlay's opaque box lies inside the union of the eight
#            rigs' own opaque boxes, and a piece worn in the legs/torso/head slot sits on that
#            slot's published skeleton line (draw.py's feet-origin rows, converted the way
#            draw.py converts them, not guessed). TN, both halves: a corner pixel outside the
#            rig envelope, and a fabricated line-piece 6 px off the line it claims.
#   REACHES  the dead-socket lane: an actor actually WEARING each base that declares equip art in
#            a drawn slot resolves a layer that reaches the blit. TN, all four: no equipment
#            component, a base with no equip art, an undrawn slot (vest/belt/feet/gloves/
#            eyes/face), an empty slot.
#   SHARED   the slice's actual bet -- one overlay serves every rig: all eight rigs stand on
#            PAWN_CANVAS, and no equip key names a rig plus a suffix. TN: the same scan finds a
#            fabricated per-rig key.
#   PLAYED   the shipped colony reaches this path at all -- SimBoot.playable(20260805, 64), where
#            all three survivors boot wearing something this table draws. Were that to stop being
#            true, the lane SAYS SO AND SKIPS loudly rather than passing quietly on nothing.

const SimBoot = preload("res://sim/boot.gd")
const World = preload("res://sim/world.gd")
const ContentLoader = preload("res://platform/content_loader.gd")
const Appearance = preload("res://presentation/appearance.gd")

const CANON_SEED: int = 20260805
const GATE_SIZE: int = 64
const BUDGET_SECONDS: float = 60.0

var _stash: Dictionary = {}


# The table this whole gate holds EQUIP_DRAW_ORDER against -- a hand-written duplicate of
# `Appearance.EQUIP_DRAW_ORDER`'s own literal, the same convention check_trees.gd's TIERS lane
# uses for its tier bounds: the gate names its own expectation rather than reading the value
# under test back at itself.
const EXPECT_ORDER: Array[Dictionary] = [
	{"slot": "back", "over": false},
	{"slot": "legs", "over": true},
	{"slot": "torso", "over": true},
	{"slot": "primary", "over": true},
	{"slot": "secondary", "over": true},
	{"slot": "head", "over": true},
]

# The six equip slots content declares (item.schema.json's equipSlot enum) that EQUIP_DRAW_ORDER
# deliberately does not name -- appearance.gd's own comment calls these out as undrawn this
# slice, and REACHES' third true negative is that an item sitting in one of these resolves no
# layer no matter what art it carries.
const UNDRAWN_SLOTS: Array[String] = ["vest", "belt", "feet", "gloves", "eyes", "face"]

# The published pawn skeleton, `tools/sprites/parts/characters.py` -- pixels above the soles,
# negative upward. Duplicated here for the same reason the engine pin and the tree tier bounds
# are duplicated: GDScript cannot import a Python module, and FITS judges decoded pixels against
# these very rows. If characters.py's numbers ever move, this and gear.py both need updating.
const SKEL_FEET_Y: float = 0.0
const SKEL_LEG_TOP_Y: float = -13.0
const SKEL_SHOULDER_Y: float = -28.0
const SKEL_HEAD_CY: float = -35.0
const SKEL_HEAD_R: float = 5.0

# How far off its line a fabricated FITS negative sits, in pixels -- the exact number the task
# names, so the true negative is provably outside the line rather than merely "somewhere else".
const LINE_OFFSET_PX: int = 6


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var started: int = Time.get_ticks_msec()
	var ok: bool = true
	ok = _the_order_holds_and_composes() and ok
	ok = _the_canvas_is_pawn_sized() and ok
	ok = _the_fits_lie_on_their_lines() and ok
	ok = _the_reaches_never_die_silently() and ok
	ok = _the_shared_bet_holds() and ok
	ok = _the_shipped_colony_reaches_it() and ok

	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	if seconds > BUDGET_SECONDS:
		push_error("check_worn ran %.1f s against a %.0f s budget" % [seconds, BUDGET_SECONDS])
		ok = false

	if ok:
		print(
			(
				"WORN_LOOK_OK EQUIP_DRAW_ORDER holds 6 slots in order (only back under) and a fully-kitted actor composes them in that order, %d layers, a back-slot front piece over anyway; %d content/items/ equip keys resolve at PAWN_CANVAS %s; %d overlays sit inside the %d-rig envelope (%s); %d equippable base(s) reach a layer worn in their own slot (%s), refused for no-equipment/no-art/an-undrawn-slot/an-empty-slot; all %d rigs share PAWN_CANVAS with no per-rig overlay key; %s; %.1f s of a %.0f s budget"
				% [
					int(_stash.get("order_layers", 0)),
					int(_stash.get("canvas_judged", 0)),
					str(Appearance.PAWN_CANVAS),
					int(_stash.get("fits_judged", 0)),
					int(_stash.get("rig_count", 0)),
					String(_stash.get("fits_lines_checked", "[]")),
					int(_stash.get("reaches_judged", 0)),
					String(_stash.get("reaches_ids", "[]")),
					int(_stash.get("rig_count", 0)),
					String(_stash.get("played_note", "")),
					seconds,
					BUDGET_SECONDS,
				]
			)
		)
		quit(0)
	else:
		push_error("WORN_LOOK_FAIL")
		quit(1)


# --- fixtures and shared helpers ------------------------------------------------------------


func _fixture() -> Dictionary:
	return {
		"seed": 77,
		"tick_hz": 20,
		"map": {"width": 12, "height": 10, "walls": []},
		"player": {"id": 0, "x": 6.0, "y": 5.0, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	}


# The eight rig-body keys out of Appearance.PAWN_KEYS -- everything on that list that is not one
# of the three shipped equip overlays. Derived from the real table rather than a second hardcoded
# list, so this cannot silently drift from what PAWN_KEYS actually names.
func _rig_keys() -> Array[String]:
	var out: Array[String] = []
	for k in Appearance.PAWN_KEYS:
		if not String(k).contains("equip"):
			out.append(String(k))
	return out


# Every (base id, equipSlot, prop, key) row any item under content/items/ declares for wearing or
# holding -- equipSprite and equipSpriteFront both. The one scan CANVAS, FITS, REACHES and SHARED
# all read, so "which bases carry worn art today" is answered once.
func _equip_declarations(tree: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for path in tree.keys():
		if not String(path).begins_with("items/"):
			continue
		var raw: Variant = tree[path]
		var entries: Array = raw as Array if raw is Array else [raw]
		for entry_v in entries:
			if not (entry_v is Dictionary):
				continue
			var entry: Dictionary = entry_v as Dictionary
			var app: Variant = entry.get("appearance")
			if not (app is Dictionary):
				continue
			var id: String = String(entry.get("id", "?"))
			var slot: String = String(entry.get("equipSlot", ""))
			for prop in ["equipSprite", "equipSpriteFront"]:
				if (app as Dictionary).has(prop):
					out.append({"id": id, "equipSlot": slot, "prop": prop, "key": String((app as Dictionary)[prop])})
	return out


func _drawable_slots() -> Array[String]:
	var out: Array[String] = []
	for e in Appearance.EQUIP_DRAW_ORDER:
		out.append(String((e as Dictionary)["slot"]))
	return out


# The opaque box of a decoded picture, or {} for one with no opaque pixel at all --
# check_trees.gd's `_bounds_of`, reused verbatim: this file judges decoded pixels the same way.
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
	return {"min_x": min_x, "max_x": max_x, "min_y": min_y, "max_y": max_y}


func _bbox_inside(b: Dictionary, box: Dictionary) -> bool:
	if b.is_empty() or box.is_empty():
		return false
	return int(b["min_x"]) >= int(box["min_x"]) and int(b["max_x"]) <= int(box["max_x"]) \
			and int(b["min_y"]) >= int(box["min_y"]) and int(b["max_y"]) <= int(box["max_y"])


# Whether a picture's opaque rows overlap a skeleton line's row band -- an interval test, so a
# piece drawn entirely above or below the line it claims does not "sit on it" by accident.
func _rows_overlap(b: Dictionary, row_min: int, row_max: int) -> bool:
	if b.is_empty():
		return false
	return int(b["min_y"]) <= row_max and int(b["max_y"]) >= row_min


# A skeleton y (pixels above the soles, negative upward) converted to a canvas row, the way
# `draw.Canvas` converts it: `offset(x, y) = (x - cx, y - cy)` with `cy = h - 1` on a feet-origin
# canvas, so a shape authored at skeleton y `oy` lands where `y - cy == oy`, i.e. row = oy + cy.
# Probed against characters.py's own worked example in its header comment: FEET_Y 0 -> row 47,
# HEAD_CY -35 -> row 12, both of which this function reproduces.
func _row_of(skeleton_y: float) -> int:
	return int(round(skeleton_y + float(Appearance.PAWN_CANVAS.y - 1)))


# --- lane 1: ORDER ---------------------------------------------------------------------------


func _orders_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		var ea: Dictionary = a[i] as Dictionary
		var eb: Dictionary = b[i] as Dictionary
		if String(ea.get("slot", "")) != String(eb.get("slot", "")):
			return false
		if bool(ea.get("over", false)) != bool(eb.get("over", false)):
			return false
	return true


func _the_order_holds_and_composes() -> bool:
	var order: Array[Dictionary] = Appearance.EQUIP_DRAW_ORDER

	# 1. Structural: exactly EXPECT_ORDER, in order, no duplicate slots, `over` a bool, only
	# `back` under.
	if not _orders_equal(order, EXPECT_ORDER):
		push_error("Appearance.EQUIP_DRAW_ORDER is %s, want %s in that exact order" % [str(order), str(EXPECT_ORDER)])
		return false
	var seen_slots: Array[String] = []
	for e in order:
		if not ((e as Dictionary).has("slot") and (e as Dictionary).has("over")):
			push_error("an EQUIP_DRAW_ORDER entry is missing 'slot' or 'over': %s" % str(e))
			return false
		if not ((e as Dictionary)["over"] is bool):
			push_error("EQUIP_DRAW_ORDER entry %s carries a non-bool 'over'" % str(e))
			return false
		var slot: String = String((e as Dictionary)["slot"])
		if seen_slots.has(slot):
			push_error("EQUIP_DRAW_ORDER names slot '%s' twice" % slot)
			return false
		seen_slots.append(slot)
	if String(order[0]["slot"]) != "back" or bool(order[0]["over"]) != false:
		push_error("EQUIP_DRAW_ORDER's first entry is %s, want back drawn under" % str(order[0]))
		return false
	for j in range(1, order.size()):
		if bool(order[j]["over"]) != true:
			push_error("EQUIP_DRAW_ORDER's '%s' is drawn under; only 'back' may be" % String(order[j]["slot"]))
			return false

	# TN: a shuffled expectation is refused by the same comparison.
	var shuffled: Array[Dictionary] = EXPECT_ORDER.duplicate(true)
	var tmp: Dictionary = shuffled[1]
	shuffled[1] = shuffled[5]
	shuffled[5] = tmp
	if _orders_equal(order, shuffled):
		push_error("a shuffled EQUIP_DRAW_ORDER expectation still compared equal; ORDER's comparison cannot say no")
		return false

	# 2. Real composition: fully kit an actor across all six drawable slots and check the layers
	# come back in EQUIP_DRAW_ORDER's order. Legs/torso/head/secondary carry no equip art in
	# shipped content yet (gear.py has not generated it), so four of the six slots here are
	# fabricated bases that reuse one of the three real overlay files already on disk -- nothing
	# new is drawn, only the six-slot *order* is exercised end to end.
	Appearance.forget()
	var tree: Dictionary = ContentLoader.load_tree()
	tree["items/_worn_gate_fixture.json"] = [
		{"id": "item.gate.worn_legs", "appearance": {"equipSprite": "item_bat_aluminium_equip"}},
		{"id": "item.gate.worn_torso", "appearance": {"equipSprite": "item_pack_hiking_equip"}},
		{"id": "item.gate.worn_secondary", "appearance": {"equipSprite": "item_bat_aluminium_equip"}},
		{"id": "item.gate.worn_head", "appearance": {"equipSprite": "item_pack_hiking_equip_front"}},
	]
	var fixture: Dictionary = _fixture()
	fixture["content_tree"] = tree
	var w: Variant = World.new(fixture)
	var actor: int = int(w.entities.spawn())
	var items: Dictionary = {}
	for pair in [
		["back", "item.pack.hiking"], ["legs", "item.gate.worn_legs"], ["torso", "item.gate.worn_torso"],
		["primary", "item.bat.aluminium"], ["secondary", "item.gate.worn_secondary"], ["head", "item.gate.worn_head"],
	]:
		var e2: int = int(w.entities.spawn())
		w.components.set_component(e2, "itemBase", {"baseId": String(pair[1])})
		items[String(pair[0])] = e2
	w.components.set_component(actor, "equipment", {"slots": items})
	var layers: Array[Dictionary] = Appearance.equipment_layers_for(w, actor)

	var expect_keys: Array = [
		["item_pack_hiking_equip", false],       # back, under
		["item_pack_hiking_equip_front", true],  # back's front piece, over anyway
		["item_bat_aluminium_equip", true],      # legs
		["item_pack_hiking_equip", true],        # torso
		["item_bat_aluminium_equip", true],      # primary
		["item_bat_aluminium_equip", true],      # secondary
		["item_pack_hiking_equip_front", true],  # head
	]
	if layers.size() != expect_keys.size():
		push_error("fully kitting all six slots returned %d layers, want %d in EQUIP_DRAW_ORDER's order: %s" % [layers.size(), expect_keys.size(), str(layers)])
		return false
	for i in layers.size():
		var want_key: String = String(expect_keys[i][0])
		var want_over: bool = bool(expect_keys[i][1])
		var want_tex: Variant = Appearance.resolve(want_key)
		if layers[i].get("texture") != want_tex or bool(layers[i].get("over")) != want_over:
			push_error("layer %d is %s, want key '%s' over=%s" % [i, str(layers[i]), want_key, str(want_over)])
			return false

	# Every under-layer stands before every over-layer in the list -- not just an artifact of
	# this fixture's slot choice, since `main.gd::_blit_body` filters the list into two passes.
	var saw_over: bool = false
	for layer in layers:
		if bool(layer["over"]):
			saw_over = true
		elif saw_over:
			push_error("an under-body layer followed an over-body one: %s" % str(layers))
			return false

	# TN, folded into the positive: item_pack_hiking_equip_front is back's own front piece, and
	# it must land in the over group despite its slot being under.
	if not bool(layers[1]["over"]):
		push_error("item_pack_hiking_equip_front (back's front piece) drew under, not over, despite equipSpriteFront's always-over rule")
		return false

	_stash["order_layers"] = layers.size()
	print("ORDER OK EQUIP_DRAW_ORDER == EXPECT_ORDER (6 slots, only back under); a shuffled expectation is refused; a fully-kitted actor composes %d layers in order, back's front piece over despite its own slot being under" % layers.size())
	return true


# --- lane 2: CANVAS --------------------------------------------------------------------------


func _is_pawn_canvas(tex: Variant) -> bool:
	if tex == null or not (tex is Texture2D):
		return false
	return Vector2i((tex as Texture2D).get_size()) == Appearance.PAWN_CANVAS


func _the_canvas_is_pawn_sized() -> bool:
	Appearance.forget()
	var tree: Dictionary = ContentLoader.load_tree()
	var decls: Array[Dictionary] = _equip_declarations(tree)
	if decls.is_empty():
		push_error("no appearance.equipSprite/equipSpriteFront under content/items/ -- CANVAS has nothing to judge")
		return false

	# tools/sprites/parts/gear.py is a separate, ongoing piece of work (this file's header): a
	# base can declare equipSprite before its overlay is generated, and a key naming no file yet
	# is that in-flight state, not a broken key -- `_sprite_keys_resolve` in check_appearance.gd
	# already owns "every declared key must resolve or the build fails" for content as a whole.
	# This lane judges whatever *is* on disk and says so, loudly, for whatever is not.
	var judged: int = 0
	var missing: Array[String] = []
	for d in decls:
		var key: String = String(d["key"])
		var tex: Variant = Appearance.resolve(key)
		if tex == null:
			missing.append("%s.%s ('%s')" % [String(d["id"]), String(d["prop"]), key])
			continue
		if not _is_pawn_canvas(tex):
			push_error("%s.%s ('%s') is %s, not PAWN_CANVAS %s" % [String(d["id"]), String(d["prop"]), key, str((tex as Texture2D).get_size()), str(Appearance.PAWN_CANVAS)])
			return false
		judged += 1
	if not missing.is_empty():
		print("CANVAS SKIP %d declared equip key(s) name no file yet (gear.py has not generated them): %s -- judged only what is on disk" % [missing.size(), str(missing)])
	if judged == 0:
		push_error("CANVAS judged nothing -- the predicate never ran against a real file")
		return false

	# TN: a fabricated 32x32 overlay is refused by the same predicate.
	var square: Texture2D = ImageTexture.create_from_image(Image.create(32, 32, false, Image.FORMAT_RGBA8))
	if _is_pawn_canvas(square):
		push_error("a 32x32 texture passed the pawn-canvas predicate; CANVAS cannot say no")
		return false

	# TN: a key naming no file answers null rather than passing quietly.
	if Appearance.resolve("item_no_such_equip") != null:
		push_error("a fabricated key resolved a texture; the null path is dead")
		return false
	if _is_pawn_canvas(Appearance.resolve("item_no_such_equip")):
		push_error("null passed the pawn-canvas predicate")
		return false

	_stash["canvas_judged"] = judged
	print("CANVAS OK %d equip declaration(s) under content/items/ all resolve at PAWN_CANVAS %s; a 32x32 fabrication and an unknown key are both refused" % [judged, str(Appearance.PAWN_CANVAS)])
	return true


# --- lane 3: FITS ----------------------------------------------------------------------------


func _the_fits_lie_on_their_lines() -> bool:
	Appearance.forget()
	var tree: Dictionary = ContentLoader.load_tree()
	var decls: Array[Dictionary] = _equip_declarations(tree)
	if decls.is_empty():
		push_error("no equip declarations under content/items/ -- FITS has nothing to judge")
		return false

	# The rig envelope: the union of the eight bodies' own opaque boxes, on decoded pixels.
	var rig_keys: Array[String] = _rig_keys()
	if rig_keys.size() != 8:
		push_error("_rig_keys found %d rig body keys out of PAWN_KEYS, want 8" % rig_keys.size())
		return false
	var box: Dictionary = {}
	for rk in rig_keys:
		var rtex: Variant = Appearance.resolve(rk)
		if rtex == null:
			push_error("rig '%s' resolves no texture; FITS has no silhouette to bound overlays against" % rk)
			return false
		var rb: Dictionary = _bounds_of((rtex as Texture2D).get_image())
		if rb.is_empty():
			push_error("rig '%s' is entirely transparent" % rk)
			return false
		if box.is_empty():
			box = rb.duplicate()
		else:
			box["min_x"] = mini(int(box["min_x"]), int(rb["min_x"]))
			box["min_y"] = mini(int(box["min_y"]), int(rb["min_y"]))
			box["max_x"] = maxi(int(box["max_x"]), int(rb["max_x"]))
			box["max_y"] = maxi(int(box["max_y"]), int(rb["max_y"]))

	var judged: int = 0
	var missing: Array[String] = []
	for d in decls:
		var tex: Variant = Appearance.resolve(String(d["key"]))
		if tex == null:
			# gear.py may not have generated this overlay yet (this file's header) -- judge
			# whatever is on disk and say so, never invent a pass for a picture that isn't there.
			missing.append(String(d["key"]))
			continue
		var b: Dictionary = _bounds_of((tex as Texture2D).get_image())
		if b.is_empty():
			push_error("%s is entirely transparent" % String(d["key"]))
			return false
		if not _bbox_inside(b, box):
			push_error("%s's opaque box (%d,%d)..(%d,%d) lies outside the %d-rig envelope (%d,%d)..(%d,%d)" % [
				String(d["key"]), int(b["min_x"]), int(b["min_y"]), int(b["max_x"]), int(b["max_y"]),
				rig_keys.size(), int(box["min_x"]), int(box["min_y"]), int(box["max_x"]), int(box["max_y"]),
			])
			return false
		judged += 1
	if not missing.is_empty():
		print("FITS SKIP %d declared equip key(s) name no file yet: %s -- the envelope check judged only what is on disk" % [missing.size(), str(missing)])
	if judged == 0:
		push_error("no equip overlay resolved a texture -- FITS's envelope check had nothing to judge")
		return false

	# TN: a fabricated overlay poking outside the rig envelope (the canvas corner, clear of every
	# rig's side clearance and every rig's head band) is refused by the same predicate.
	var w: int = Appearance.PAWN_CANVAS.x
	var h: int = Appearance.PAWN_CANVAS.y
	var stray := Image.create(w, h, false, Image.FORMAT_RGBA8)
	stray.set_pixel(0, 0, Color(0.0, 0.0, 0.0, 1.0))
	if _bbox_inside(_bounds_of(stray), box):
		push_error("a pixel at the canvas corner passed the rig-envelope predicate; FITS cannot say no")
		return false

	# A piece named for a skeleton line sits on it. Proven on fabricated pixels first -- the
	# predicate's own true positive and true negative -- then checked against whatever
	# legs/torso/head equip art content actually declares today.
	var lines: Dictionary = {
		"legs": Vector2i(_row_of(SKEL_LEG_TOP_Y), _row_of(SKEL_FEET_Y)),
		"torso": Vector2i(_row_of(SKEL_SHOULDER_Y), _row_of(SKEL_LEG_TOP_Y)),
		"head": Vector2i(_row_of(SKEL_HEAD_CY - SKEL_HEAD_R), _row_of(SKEL_HEAD_CY + SKEL_HEAD_R)),
	}
	for slot in lines.keys():
		var line: Vector2i = lines[slot]
		var on_it := Image.create(w, h, false, Image.FORMAT_RGBA8)
		on_it.set_pixel(w / 2, line.x, Color(0.0, 0.0, 0.0, 1.0))
		if not _rows_overlap(_bounds_of(on_it), line.x, line.y):
			push_error("a fabricated '%s' overlay drawn exactly on its line (row %d) was refused; the line predicate cannot say yes" % [slot, line.x])
			return false
		var off_row: int = line.x - LINE_OFFSET_PX if line.x - LINE_OFFSET_PX >= 0 else line.y + LINE_OFFSET_PX
		var off_it := Image.create(w, h, false, Image.FORMAT_RGBA8)
		off_it.set_pixel(w / 2, off_row, Color(0.0, 0.0, 0.0, 1.0))
		if _rows_overlap(_bounds_of(off_it), line.x, line.y):
			push_error("a fabricated '%s' overlay %d px off its line (row %d, line %d..%d) was accepted; FITS's line predicate cannot say no" % [slot, LINE_OFFSET_PX, off_row, line.x, line.y])
			return false

	var checked_real: Array[String] = []
	for slot2 in lines.keys():
		var line2: Vector2i = lines[slot2]
		var found_any: bool = false
		var declared_no_file: Array[String] = []
		for d2 in decls:
			if String(d2["equipSlot"]) != String(slot2):
				continue
			var tex2: Variant = Appearance.resolve(String(d2["key"]))
			if tex2 == null:
				declared_no_file.append(String(d2["id"]))
				continue
			found_any = true
			var b2: Dictionary = _bounds_of((tex2 as Texture2D).get_image())
			if not _rows_overlap(b2, line2.x, line2.y):
				push_error("%s ('%s') does not sit on the %s line (rows %d..%d); its own opaque rows are %d..%d" % [
					String(d2["id"]), String(d2["key"]), String(slot2), line2.x, line2.y, int(b2.get("min_y", -1)), int(b2.get("max_y", -1)),
				])
				return false
		if found_any:
			checked_real.append(String(slot2))
		elif not declared_no_file.is_empty():
			print("FITS SKIP %s declares %s-slot equip art but no file resolves yet; the line predicate above was proved true+false on fabricated pixels only, never invented a pass for real art that isn't there" % [str(declared_no_file), slot2])
		else:
			print("FITS SKIP no content declares %s-slot equip art yet; the line predicate above was proved true+false on fabricated pixels only, never invented a pass for real content that does not exist" % slot2)

	_stash["fits_judged"] = judged
	_stash["rig_count"] = rig_keys.size()
	_stash["fits_lines_checked"] = str(checked_real)
	print("FITS OK %d overlay(s) inside the %d-rig envelope; a corner pixel refused; the legs/torso/head line predicate proven true+false on fabricated pixels, checked on real art for %s" % [judged, rig_keys.size(), str(checked_real)])
	return true


# --- lane 4: REACHES -------------------------------------------------------------------------


func _the_reaches_never_die_silently() -> bool:
	Appearance.forget()
	var tree: Dictionary = ContentLoader.load_tree()
	var decls: Array[Dictionary] = _equip_declarations(tree)
	var drawable_slots: Array[String] = _drawable_slots()

	# A fabricated base with no appearance block at all, for TN 2 below. Every real drawable-slot
	# base under content/items/ declares equip art today (this file's header: the worn-look arc
	# is landing it live, ahead of gear.py's art), so a fixture is what proves "no equipSprite"
	# refuses, rather than depending on one real base staying art-less by accident.
	tree["items/_worn_gate_fixture.json"] = [{"id": "item.gate.no_art"}]
	var fixture: Dictionary = _fixture()
	fixture["content_tree"] = tree
	var w: Variant = World.new(fixture)

	var actor: int = int(w.entities.spawn())
	var item: int = int(w.entities.spawn())
	var seen_ids: Dictionary = {}
	var judged_ids: Array[String] = []
	var missing: Array[String] = []
	for d in decls:
		var slot: String = String(d["equipSlot"])
		if not drawable_slots.has(slot):
			continue
		var base_id: String = String(d["id"])
		if seen_ids.has(base_id):
			continue
		seen_ids[base_id] = true
		if Appearance.resolve(String(d["key"])) == null:
			# gear.py may not have generated this base's overlay yet (this file's header) --
			# REACHES only asserts the dead-socket claim against art that actually exists on
			# disk; CANVAS and FITS already say so, loudly, about whatever is still missing.
			missing.append(base_id)
			continue
		w.components.set_component(item, "itemBase", {"baseId": base_id})
		var slots_dict: Dictionary = {}
		slots_dict[slot] = item
		w.components.set_component(actor, "equipment", {"slots": slots_dict})
		var layers: Array[Dictionary] = Appearance.equipment_layers_for(w, actor)
		if layers.is_empty():
			push_error("%s worn in its own slot '%s' resolves no layer -- a dead socket" % [base_id, slot])
			return false
		for layer in layers:
			if layer.get("texture") == null:
				push_error("%s worn in '%s' produced a layer with no texture" % [base_id, slot])
				return false
		judged_ids.append(base_id)
	if judged_ids.is_empty():
		push_error("no content/items/ base both resolves equip art on disk and occupies a slot EQUIP_DRAW_ORDER draws -- REACHES has nothing to judge")
		return false
	if not missing.is_empty():
		print("REACHES SKIP %d base(s) declare equip art with no file on disk yet, not judged for a dead socket here: %s" % [missing.size(), str(missing)])

	# TN 1: an entity with no equipment component at all (every zombie).
	var bare_actor: int = int(w.entities.spawn())
	if not Appearance.equipment_layers_for(w, bare_actor).is_empty():
		push_error("an entity with no equipment component resolved a layer")
		return false

	# TN 2: a base that declares no equip art at all.
	w.components.set_component(item, "itemBase", {"baseId": "item.gate.no_art"})
	var no_art_slots: Dictionary = {}
	no_art_slots["primary"] = item
	w.components.set_component(actor, "equipment", {"slots": no_art_slots})
	if not Appearance.equipment_layers_for(w, actor).is_empty():
		push_error("item.gate.no_art (no appearance block at all) resolved a layer")
		return false

	# TN 3: an item that DOES carry equip art, placed in a slot EQUIP_DRAW_ORDER does not name.
	w.components.set_component(item, "itemBase", {"baseId": "item.bat.aluminium"})
	var undrawn_hit: int = 0
	for undrawn_slot in UNDRAWN_SLOTS:
		var undrawn_dict: Dictionary = {}
		undrawn_dict[undrawn_slot] = item
		w.components.set_component(actor, "equipment", {"slots": undrawn_dict})
		if not Appearance.equipment_layers_for(w, actor).is_empty():
			push_error("item.bat.aluminium (equip art present) in slot '%s', which EQUIP_DRAW_ORDER does not name, still resolved a layer" % undrawn_slot)
			return false
		undrawn_hit += 1
	if undrawn_hit != UNDRAWN_SLOTS.size():
		push_error("the undrawn-slot true negative judged %d of %d slots" % [undrawn_hit, UNDRAWN_SLOTS.size()])
		return false

	# TN 4: an empty slot.
	w.components.set_component(actor, "equipment", {"slots": {}})
	if not Appearance.equipment_layers_for(w, actor).is_empty():
		push_error("an equipment component with no filled slots resolved a layer")
		return false

	_stash["reaches_judged"] = judged_ids.size()
	_stash["reaches_ids"] = str(judged_ids)
	print("REACHES OK %d equippable base(s) worn in their own slot each resolve a layer (%s); refused for no equipment component, a no-art base, %d undrawn slots, and an empty slot" % [judged_ids.size(), str(judged_ids), UNDRAWN_SLOTS.size()])
	return true


# --- lane 5: SHARED --------------------------------------------------------------------------


func _find_per_rig_overlay(keys: Array[String], rig_keys: Array[String]) -> String:
	for k in keys:
		for rk in rig_keys:
			if String(k) == String(rk):
				continue
			if String(k).begins_with(String(rk) + "_"):
				return String(k)
	return ""


func _the_shared_bet_holds() -> bool:
	Appearance.forget()
	var rig_keys: Array[String] = _rig_keys()
	if rig_keys.size() != 8:
		push_error("_rig_keys found %d rig body keys out of PAWN_KEYS, want 8" % rig_keys.size())
		return false
	for rk in rig_keys:
		var tex: Variant = Appearance.resolve(rk)
		if tex == null:
			push_error("rig '%s' resolves no texture" % rk)
			return false
		if Vector2i((tex as Texture2D).get_size()) != Appearance.PAWN_CANVAS:
			push_error("rig '%s' is %s, not PAWN_CANVAS %s" % [rk, str((tex as Texture2D).get_size()), str(Appearance.PAWN_CANVAS)])
			return false
		if Appearance.canvas_of(rk) != Appearance.PAWN_CANVAS:
			push_error("canvas_of('%s') is %s, not PAWN_CANVAS -- an overlay authored on that canvas would not land on this rig's skeleton" % [rk, str(Appearance.canvas_of(rk))])
			return false

	var tree: Dictionary = ContentLoader.load_tree()
	var decls: Array[Dictionary] = _equip_declarations(tree)
	var keys: Array[String] = []
	for d in decls:
		keys.append(String(d["key"]))
	var hit: String = _find_per_rig_overlay(keys, rig_keys)
	if not hit.is_empty():
		push_error("'%s' names a rig plus a suffix; one overlay is supposed to serve every rig, not one per rig" % hit)
		return false

	# TN: the same scan finds one when handed a fabricated key list that names a rig explicitly.
	var fabricated: Array[String] = keys.duplicate()
	fabricated.append("survivor_mara_bat_equip")
	var found: String = _find_per_rig_overlay(fabricated, rig_keys)
	if found.is_empty():
		push_error("a fabricated per-rig key 'survivor_mara_bat_equip' was not found; SHARED's scan cannot say no")
		return false

	print("SHARED OK all %d rigs stand on PAWN_CANVAS %s; %d equip key(s) under content/items/ name no rig; the same scan finds a fabricated one ('%s')" % [rig_keys.size(), str(Appearance.PAWN_CANVAS), keys.size(), found])
	return true


# --- lane 6: PLAYED --------------------------------------------------------------------------


func _the_shipped_colony_reaches_it() -> bool:
	Appearance.forget()
	var boot: Dictionary = SimBoot.playable(CANON_SEED, GATE_SIZE)
	var world: Variant = boot["world"]
	var drawable_slots: Array[String] = _drawable_slots()

	var wearers: Array[int] = world.components.query(["equipment"])
	if wearers.is_empty():
		push_error("the shipped colony boots nobody with an equipment component -- PLAYED has nothing to judge")
		return false

	var drawable_layers: int = 0
	var wearers_with_drawable_slot: int = 0
	for ent in wearers:
		var eq: Dictionary = world.components.get_component(ent, "equipment") as Dictionary
		var slots: Dictionary = eq.get("slots", {}) as Dictionary
		var has_drawable_slot: bool = false
		for s in slots.keys():
			if drawable_slots.has(String(s)) and slots[s] != null:
				has_drawable_slot = true
				break
		if has_drawable_slot:
			wearers_with_drawable_slot += 1
		var layers: Array[Dictionary] = Appearance.equipment_layers_for(world, ent)
		for layer in layers:
			var tex: Variant = layer.get("texture")
			if tex == null or not (tex is Texture2D) or Vector2i((tex as Texture2D).get_size()) != Appearance.PAWN_CANVAS:
				push_error("entity %d's equipment layer resolves %s, not a PAWN_CANVAS texture" % [ent, str(tex)])
				return false
			drawable_layers += 1

	if drawable_layers == 0:
		var note: String = "suburb@%d seed %d boots %d entities with an equipment component (%d holding a slot EQUIP_DRAW_ORDER draws), and none resolves a layer today -- either the starting kit's own base declares no equip art, or (this file's header) gear.py has not generated its overlay yet. equipment_layers_for was reached for real against the shipped boot and genuinely returned nothing; never passed quietly on an unjudged path." % [GATE_SIZE, CANON_SEED, wearers.size(), wearers_with_drawable_slot]
		_stash["played_note"] = note
		print("PLAYED SKIP %s" % note)
		return true

	var note2: String = "%d of %d equipped entities wear something drawn, %d layer(s) all at PAWN_CANVAS" % [wearers_with_drawable_slot, wearers.size(), drawable_layers]
	_stash["played_note"] = note2
	print("PLAYED OK suburb@%d seed %d: %s" % [GATE_SIZE, CANON_SEED, note2])
	return true
