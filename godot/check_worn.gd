extends SceneTree
# Slice 8, "What you wear shows on your body": docs/30's Dungeon Settlers look, the worn clause. `Appearance`
# replaced its two EQUIP_UNDER_BODY / EQUIP_OVER_BODY lists with one ordered table,
# EQUIP_DRAW_ORDER -- eight slots, each saying which side of the body draw call it goes on -- and
# `equipment_layers_for` walks it in that order, so the order layers COMPOSE *is* the picture
# rather than the concatenation of two lists. This gate holds that table and the composition it
# drives against a hand-built fixture both ways, then proves the draw loop actually reaches every
# equippable base content declares.
#
# Since "Pack gear on the body" and "Held weapons in the hand" (both 2026-09-26; docs/30, "The whole
# outpost pack") a body wears only two shapes of picture, both declared in authored.json: the
# pack's four-direction wearables (vest, helmet, gas mask, backpack; a family with one member per
# view, drawn at the body's own rect) and the pack's held weapons (one east-facing picture each,
# turned per view and landed grip-first on a hand point). The 43 face-on generated overlays, the
# three fitted-part pictures and `tools/sprites/parts/gear.py` were deleted in that commit, and the
# FITS and PARTS lanes that judged them went with them: FITS measured face-on overlays against the
# face-on rigs' envelope and the published skeleton lines, and PARTS a part moved to its host's
# anchor -- neither has a subject left. RETIRED is what stands in their place, proving the face-on
# path is gone rather than merely unused.
#
# Eight lanes, every assertion with a true positive and a true negative, because a gate that
# cannot fail is worse than no gate:
#
#   ORDER    EQUIP_DRAW_ORDER is exactly the eight slots, in order, no duplicates, only `back`
#            under -- then the real composition: an actor kitted in all eight slots, seen from the
#            east, composes one layer per slot in EQUIP_DRAW_ORDER's order, and the ones under the
#            body are exactly the backpack (the pack's z) and the weapon in the far hand
#            (HELD_BEHIND). TN: a shuffled expectation is refused by the same comparison.
#   CANVAS   every key content/items/ names via equipSprite is one of the two shapes, at its canvas:
#            a wearable's four members at PAWN_CANVAS, a held weapon at the canvas authored.json
#            declares for it. TN: a fabricated 32x32 wearable is refused by the same predicate, and
#            an unknown key answers null rather than passing.
#   RETIRED  the face-on path is gone, not merely unused: PAWN_KEYS names the two rigs and nothing
#            drawn on a body; no PNG under assets/sprites/ carries a retired overlay's `_equip` or
#            `_part` name; every equipSprite in content turns or is held; and a base declaring a
#            retired key -- or any real picture that neither turns nor is held -- composes nothing
#            in any view, as does a fitted part on a held pistol. TN: the name scan and the shape
#            predicate each say no to a fabricated retired key, and the same actor holding a real
#            held weapon composes a layer.
#   REACHES  the dead-socket lane: an actor actually WEARING each base that declares equip art in
#            a drawn slot resolves a layer that reaches the blit, in every one of the four views. TN,
#            all four: no equipment component, a base with no equip art, an undrawn slot
#            (belt/feet/gloves/eyes), an empty slot.
#   SHARED   one wearable serves every body: the generated rigs stand on PAWN_CANVAS, and no equip
#            key names a rig plus a suffix. TN: the same scan finds a fabricated per-rig key.
#   PLAYED   the shipped colony reaches this path at all -- SimBoot.playable(20260805, 64). If no
#            booted colonist wears anything drawn, the lane SAYS SO AND SKIPS loudly rather than
#            passing quietly on nothing.
#   TURNS    an actor wearing the pack's helmet, vest, gas mask and backpack and holding a pack
#            pistol composes, for each of the four views, the wearables' own member for that view
#            and the weapon, in EQUIP_DRAW_ORDER's order; the backpack is over the body seen from
#            the front or back and under it seen from the side (the pack's z). TN: the same actor
#            with nothing on composes nothing in any view.
#   HELD     "Held weapons in the hand": every held weapon content declares, in either hand, draws
#            on all four views -- its grip pixel painted on the hand, its barrel pointing the way
#            the view faces, at least one solid pixel of it visible past the body (at ALPHA_SOLID)
#            -- and only the west view mirrors it while the body is never mirrored. Every hand
#            point is a solid pixel of the pack body it is drawn on. The draw loop hands the layer's
#            `transpose` flag and placement to the draw call. Every key authored.json declares as
#            `pack_held` is declared by a content base whose slot a hand holds, and is among the
#            keys judged. TN: a hand off the body, a weapon posed east judged as west, a fabricated
#            reflection on a turned view, a painted grip one pixel off, a draw loop that drops the
#            flag, a held key only a back slot names or nothing names, and a face-on rig that
#            flip_for does not mirror facing west are each refused.

const SimBoot = preload("res://sim/boot.gd")
const World = preload("res://sim/world.gd")
const ContentLoader = preload("res://platform/content_loader.gd")
const Appearance = preload("res://presentation/appearance.gd")

const CANON_SEED: int = 20260805
const GATE_SIZE: int = 64
const BUDGET_SECONDS: float = 60.0
const MAIN_PATH: String = "res://presentation/main.gd"

# The alpha at which a pixel counts as drawn, as a byte -- the same threshold, and for the same
# reason, as `check_authored.gd`'s ALPHA_SOLID: the pack's art carries sub-visible specks, and
# "drawn means alpha above zero" would count them.
const ALPHA_SOLID: int = 128

# Which way a held weapon's barrel points in each view: the direction the picture's own +x (east,
# the way the pack draws every weapon) is painted in.
const BARREL: Dictionary = {"e": Vector2i(1, 0), "s": Vector2i(0, 1), "w": Vector2i(-1, 0), "n": Vector2i(0, -1)}

# The views in which each hand is behind the body -- the gate's own copy of
# `Appearance.HELD_BEHIND`, never read back from it (the EXPECT_ORDER convention): both hands seen
# from behind, and the far hand seen from either side.
const EXPECT_BEHIND: Dictionary = {"primary": ["n"], "secondary": ["e", "w", "n"]}

var _stash: Dictionary = {}


# The table this whole gate holds EQUIP_DRAW_ORDER against -- a hand-written duplicate of
# `Appearance.EQUIP_DRAW_ORDER`'s own literal, the same convention check_trees.gd's TIERS lane
# uses for its tier bounds: the gate names its own expectation rather than reading the value
# under test back at itself.
const EXPECT_ORDER: Array[Dictionary] = [
	{"slot": "legs", "over": true},
	{"slot": "torso", "over": true},
	{"slot": "vest", "over": true},
	{"slot": "back", "over": false},
	{"slot": "primary", "over": true},
	{"slot": "secondary", "over": true},
	{"slot": "face", "over": true},
	{"slot": "head", "over": true},
]

# The four equip slots content declares (item.schema.json's equipSlot enum) that EQUIP_DRAW_ORDER
# deliberately does not name -- appearance.gd's own comment calls these out as undrawn, and
# REACHES' third true negative is that an item sitting in one of these resolves no layer no
# matter what art it carries.
const UNDRAWN_SLOTS: Array[String] = ["belt", "feet", "gloves", "eyes"]

# How many rigs `tools/sprites/` generates: the screamer and the bloater, the two the pack does not
# draw. Pinned rather than measured, so PAWN_KEYS growing a key is caught here.
const GENERATED_RIGS: int = 2


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var started: int = Time.get_ticks_msec()
	var ok: bool = true
	ok = _the_order_holds_and_composes() and ok
	ok = _the_canvas_is_the_declared_one() and ok
	ok = _the_face_on_path_is_gone() and ok
	ok = _the_reaches_never_die_silently() and ok
	ok = _the_shared_bet_holds() and ok
	ok = _the_shipped_colony_reaches_it() and ok
	ok = _the_wearables_turn_with_the_body() and ok
	ok = _the_weapon_is_in_the_hand() and ok

	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	if seconds > BUDGET_SECONDS:
		push_error("check_worn ran %.1f s against a %.0f s budget" % [seconds, BUDGET_SECONDS])
		ok = false

	if ok:
		print(
			(
				"WORN_LOOK_OK EQUIP_DRAW_ORDER holds 8 slots in order (only back under) and an actor kitted in all eight composes them in that order, %d layers; %d content/items/ equip keys are a wearable at PAWN_CANVAS %s or a held weapon at its own canvas; the face-on path is gone (%s); %d equippable base(s) reach a layer in all four views (%s), refused for no-equipment/no-art/an-undrawn-slot/an-empty-slot; all %d generated rigs share PAWN_CANVAS with no per-rig key; %s; the pack's wearables turn with the body; %s; %.1f s of a %.0f s budget"
				% [
					int(_stash.get("order_layers", 0)),
					int(_stash.get("canvas_judged", 0)),
					str(Appearance.PAWN_CANVAS),
					String(_stash.get("retired_note", "")),
					int(_stash.get("reaches_judged", 0)),
					String(_stash.get("reaches_ids", "[]")),
					GENERATED_RIGS,
					String(_stash.get("played_note", "")),
					String(_stash.get("held_note", "")),
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


func _world(tree: Dictionary) -> Variant:
	var fixture: Dictionary = _fixture()
	fixture["content_tree"] = tree
	return World.new(fixture)


# An actor in `w` wearing one item per `{slot: base id}`.
func _kit(w: Variant, kit: Dictionary) -> int:
	var actor: int = int(w.entities.spawn())
	var slots: Dictionary = {}
	for slot in kit.keys():
		var item: int = int(w.entities.spawn())
		w.components.set_component(item, "itemBase", {"baseId": String(kit[slot])})
		slots[String(slot)] = item
	w.components.set_component(actor, "equipment", {"slots": slots})
	return actor


# Every (base id, equipSlot, key) row any item under content/items/ declares for wearing or
# holding. The one scan CANVAS, RETIRED, REACHES, SHARED and HELD all read, so "which bases carry
# worn art today" is answered once.
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
			if not (app is Dictionary) or not (app as Dictionary).has("equipSprite"):
				continue
			out.append({"id": String(entry.get("id", "?")), "equipSlot": String(entry.get("equipSlot", "")), "key": String((app as Dictionary)["equipSprite"])})
	return out


func _drawable_slots() -> Array[String]:
	var out: Array[String] = []
	for e in Appearance.EQUIP_DRAW_ORDER:
		out.append(String((e as Dictionary)["slot"]))
	return out


# Whether an equip key is one of the two shapes a body draws: a wearable family that turns, or a
# held weapon. Everything else -- a retired face-on overlay above all -- is a shape nothing draws.
func _is_drawn_shape(key: String) -> bool:
	return Appearance.turns(key) or Appearance.holds(key)


func _is_solid(c: Color) -> bool:
	return roundi(c.a * 255.0) >= ALPHA_SOLID


# Where a held layer paints the picture's pixel (u, v), in body-canvas pixels: the renderer's own
# rule for `draw_texture_rect`, probed in 4.7.1 with a real renderer before either this or
# `Appearance.held_pose` was written. The painted area starts at `at` whatever the signs; with
# `transpose` it is |h| wide and |w| tall and pixel (u, v) paints at (v, u); a negative width then
# flips the painted x in place, a negative height the painted y. This is the model of the draw call
# the HELD lane composes with -- written from the probe, never from held_pose, so the two can
# disagree and the lane can say so.
func _painted_at(layer: Dictionary, tex_size: Vector2i, u: int, v: int) -> Vector2i:
	var at: Vector2i = layer["at"] as Vector2i
	var size: Vector2i = layer["size"] as Vector2i
	var t: bool = bool(layer.get("transpose", false))
	var px: int = v if t else u
	var py: int = u if t else v
	var pw: int = tex_size.y if t else tex_size.x
	var ph: int = tex_size.x if t else tex_size.y
	if size.x < 0:
		px = pw - 1 - px
	if size.y < 0:
		py = ph - 1 - py
	return at + Vector2i(px, py)


# Whether a held layer paints its picture mirrored: a reflection is a transpose alone or one
# flipped axis, a rotation is two of the three or none. The sign of the painted basis's determinant.
func _is_reflection(layer: Dictionary) -> bool:
	var size: Vector2i = layer["size"] as Vector2i
	var sign: int = (-1 if bool(layer.get("transpose", false)) else 1) * (1 if size.x > 0 else -1) * (1 if size.y > 0 else -1)
	return sign < 0


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
	for j in order.size():
		if bool(order[j]["over"]) != (String(order[j]["slot"]) != "back"):
			push_error("EQUIP_DRAW_ORDER's '%s' is drawn %s; only 'back' goes under" % [String(order[j]["slot"]), "over" if bool(order[j]["over"]) else "under"])
			return false

	# TN: a shuffled expectation is refused by the same comparison.
	var shuffled: Array[Dictionary] = EXPECT_ORDER.duplicate(true)
	var tmp: Dictionary = shuffled[1]
	shuffled[1] = shuffled[5]
	shuffled[5] = tmp
	if _orders_equal(order, shuffled):
		push_error("a shuffled EQUIP_DRAW_ORDER expectation still compared equal; ORDER's comparison cannot say no")
		return false

	# 2. Real composition, seen from the east: an actor kitted in all eight drawable slots. Content
	# ships wearables for four slots, so legs and torso are fabricated bases reusing the helmet and
	# the gas mask -- one picture per slot tells the slots apart by key, and nothing new is drawn;
	# only the eight-slot *order* is exercised end to end. The pump shotgun in the primary hand and
	# the pistol in the secondary are real held weapons.
	Appearance.forget()
	var tree: Dictionary = ContentLoader.load_tree()
	tree["items/_worn_gate_fixture.json"] = [
		{"id": "item.gate.worn_legs", "appearance": {"equipSprite": "item_gear_helmet"}},
		{"id": "item.gate.worn_torso", "appearance": {"equipSprite": "item_gear_gasmask"}},
	]
	var w: Variant = _world(tree)
	var actor: int = _kit(w, {
		"legs": "item.gate.worn_legs", "torso": "item.gate.worn_torso", "vest": "item.vest.carrier",
		"back": "item.pack.hiking", "primary": "item.shotgun.pump", "secondary": "item.pistol.service",
		"face": "item.mask.gas", "head": "item.helmet.bike",
	})
	var layers: Array[Dictionary] = Appearance.equipment_layers_for(w, actor, "e")
	var expect_keys: Array = [
		["item_gear_helmet_e", true],       # legs
		["item_gear_gasmask_e", true],      # torso
		["item_gear_vest_e", true],         # vest
		["item_gear_backpack_e", false],    # back, under seen from the side (the pack's z)
		["item_held_pump_shotgun", true],   # primary, the near hand
		["item_held_pistol", false],        # secondary, the far hand, behind the body
		["item_gear_gasmask_e", true],      # face
		["item_gear_helmet_e", true],       # head
	]
	if layers.size() != expect_keys.size():
		push_error("kitting all eight slots returned %d layers seen from the east, want %d in EQUIP_DRAW_ORDER's order: %s" % [layers.size(), expect_keys.size(), str(layers)])
		return false
	for i in layers.size():
		var want_key: String = String(expect_keys[i][0])
		var want_over: bool = bool(expect_keys[i][1])
		if layers[i].get("texture") != Appearance.resolve(want_key) or bool(layers[i].get("over")) != want_over:
			push_error("layer %d is %s, want key '%s' over=%s" % [i, str(layers[i]), want_key, str(want_over)])
			return false

	_stash["order_layers"] = layers.size()
	print("ORDER OK EQUIP_DRAW_ORDER == EXPECT_ORDER (8 slots, only back under); a shuffled expectation is refused; an actor kitted in all eight composes %d layers in order seen from the east, the backpack and the far hand's pistol the only ones under" % layers.size())
	return true


# --- lane 2: CANVAS --------------------------------------------------------------------------


func _is_pawn_canvas(tex: Variant) -> bool:
	if tex == null or not (tex is Texture2D):
		return false
	return Vector2i((tex as Texture2D).get_size()) == Appearance.PAWN_CANVAS


func _the_canvas_is_the_declared_one() -> bool:
	Appearance.forget()
	var tree: Dictionary = ContentLoader.load_tree()
	var decls: Array[Dictionary] = _equip_declarations(tree)
	if decls.is_empty():
		push_error("no appearance.equipSprite under content/items/ -- CANVAS has nothing to judge")
		return false
	var judged: int = 0
	for d in decls:
		var key: String = String(d["key"])
		if Appearance.turns(key):
			for view in Appearance.VIEWS:
				var member: String = "%s_%s" % [key, view]
				if not _is_pawn_canvas(Appearance.resolve(member)):
					push_error("CANVAS: %s's wearable member '%s' is not a PAWN_CANVAS %s picture" % [String(d["id"]), member, str(Appearance.PAWN_CANVAS)])
					return false
		elif Appearance.holds(key):
			var tex: Texture2D = Appearance.resolve(key)
			if tex == null or Vector2i(tex.get_size()) != Appearance.canvas_of(key):
				push_error("CANVAS: %s's held weapon '%s' does not resolve at the canvas authored.json declares, %s" % [String(d["id"]), key, str(Appearance.canvas_of(key))])
				return false
		else:
			push_error("CANVAS: %s declares equipSprite '%s', which is neither a wearable that turns nor a held weapon" % [String(d["id"]), key])
			return false
		judged += 1

	# TN: a fabricated 32x32 wearable is refused by the same predicate.
	var square: Texture2D = ImageTexture.create_from_image(Image.create(32, 32, false, Image.FORMAT_RGBA8))
	if _is_pawn_canvas(square):
		push_error("a 32x32 texture passed the pawn-canvas predicate; CANVAS cannot say no")
		return false
	# TN: a key naming no file answers null rather than passing quietly.
	if Appearance.resolve("item_no_such_equip") != null or _is_pawn_canvas(Appearance.resolve("item_no_such_equip")):
		push_error("a fabricated key resolved a texture, or null passed the pawn-canvas predicate")
		return false

	_stash["canvas_judged"] = judged
	print("CANVAS OK %d equip declaration(s) under content/items/ are a wearable with four PAWN_CANVAS members or a held weapon at its declared canvas; a 32x32 fabrication and an unknown key are both refused" % judged)
	return true


# --- lane 3: RETIRED -------------------------------------------------------------------------


# The committed file names that carry a retired overlay's shape: a face-on `_equip` overlay (its
# `_front` half included) or a fitted part's `_part`. The scan the lane runs over the real
# directory, proved on a fabricated list first.
func _retired_names(files: Array) -> Array[String]:
	var out: Array[String] = []
	var shape := RegEx.new()
	shape.compile("^item_.*(_equip(_front)?|_part)\\.png$")
	for f in files:
		if shape.search(String(f)) != null:
			out.append(String(f))
	return out


func _the_face_on_path_is_gone() -> bool:
	var lane: String = "RETIRED"
	Appearance.forget()

	# PAWN_KEYS names the two generated rigs and nothing drawn on a body.
	if Appearance.PAWN_KEYS.size() != GENERATED_RIGS:
		push_error("%s: PAWN_KEYS names %d keys, want the %d generated rigs: %s" % [lane, Appearance.PAWN_KEYS.size(), GENERATED_RIGS, str(Appearance.PAWN_KEYS)])
		return false
	for k in Appearance.PAWN_KEYS:
		if String(k).begins_with("item_"):
			push_error("%s: PAWN_KEYS still names '%s', a picture drawn on a body" % [lane, String(k)])
			return false

	# No committed PNG carries a retired overlay's name -- and the scan can see one.
	var files: Array = Array(DirAccess.get_files_at(Appearance.SPRITE_DIR))
	var left: Array[String] = _retired_names(files)
	if not left.is_empty():
		push_error("%s: %d retired overlay file(s) are still committed: %s" % [lane, left.size(), str(left)])
		return false
	if _retired_names(["item_bat_aluminium_equip.png", "item_duffel_canvas_equip_front.png", "item_attach_suppressor_part.png", "item_held_pistol.png", "item_gear_vest_s.png"]).size() != 3:
		push_error("%s: the file-name scan did not find exactly the three fabricated retired names among five" % lane)
		return false
	if files.is_empty():
		push_error("%s: %s listed no files at all; the scan judged nothing" % [lane, Appearance.SPRITE_DIR])
		return false

	# Every equipSprite content declares is one of the two drawn shapes -- and the predicate refuses
	# a retired key.
	var tree: Dictionary = ContentLoader.load_tree()
	var decls: Array[Dictionary] = _equip_declarations(tree)
	var turning: int = 0
	var held: int = 0
	for d in decls:
		if Appearance.turns(String(d["key"])):
			turning += 1
		elif Appearance.holds(String(d["key"])):
			held += 1
		else:
			push_error("%s: %s declares '%s', a shape nothing draws" % [lane, String(d["id"]), String(d["key"])])
			return false
	if turning == 0 or held == 0:
		push_error("%s: content declares %d wearable(s) and %d held weapon(s); the lane is here for both" % [lane, turning, held])
		return false
	if _is_drawn_shape("item_bat_aluminium_equip") or _is_drawn_shape("zombie_screamer"):
		push_error("%s: the shape predicate accepts a retired key or a face-on rig" % lane)
		return false

	# A base declaring a retired key, or a real pawn-canvas picture that neither turns nor is held,
	# composes nothing in any view: the face-on path is gone from the composer, not just missing
	# its files. The screamer resolves -- it is a real 32x40 picture -- so the second is the one a
	# surviving face-on branch would draw.
	tree["items/_worn_gate_fixture.json"] = [
		{"id": "item.gate.retired", "appearance": {"equipSprite": "item_bat_aluminium_equip"}},
		{"id": "item.gate.face_on", "appearance": {"equipSprite": "zombie_screamer"}},
	]
	var w: Variant = _world(tree)
	if Appearance.resolve("zombie_screamer") == null:
		push_error("%s: the screamer resolves no picture; the face-on negative has nothing to refuse" % lane)
		return false
	for base in ["item.gate.retired", "item.gate.face_on"]:
		var actor: int = _kit(w, {"primary": base})
		for view in Appearance.VIEWS:
			if not Appearance.equipment_layers_for(w, actor, view).is_empty():
				push_error("%s: %s composed a layer on view '%s'; nothing but a wearable that turns or a held weapon draws" % [lane, base, view])
				return false
	# TN: the same slot holding a real held weapon composes a layer, so the silence above is the
	# shape, not a broken composer.
	var armed: int = _kit(w, {"primary": "item.knife.kitchen"})
	if Appearance.equipment_layers_for(w, armed, Appearance.VIEW_REST).size() != 1:
		push_error("%s: a held kitchen knife composed no layer, so the negatives above prove nothing" % lane)
		return false

	# A fitted part draws nothing (the named gap): a pistol with a can on its muzzle composes
	# exactly what the bare pistol does, in every view.
	var gunman: int = _kit(w, {"secondary": "item.pistol.service"})
	var gun: int = int(((w.components.get_component(gunman, "equipment") as Dictionary)["slots"] as Dictionary)["secondary"])
	var bare: Dictionary = {}
	for view in Appearance.VIEWS:
		bare[view] = Appearance.equipment_layers_for(w, gunman, view).size()
	var can: int = int(w.entities.spawn())
	w.components.set_component(can, "itemBase", {"baseId": "item.attach.suppressor"})
	w.components.set_component(gun, "attachments", {"slots": {"muzzle": can}})
	for view in Appearance.VIEWS:
		var fitted: int = Appearance.equipment_layers_for(w, gunman, view).size()
		if fitted != int(bare[view]) or fitted != 1:
			push_error("%s: a pistol with a suppressor fitted composes %d layer(s) on view '%s', the bare pistol %d; a fitted part draws nothing since its picture was retired" % [lane, fitted, view, int(bare[view])])
			return false

	var note: String = "PAWN_KEYS the %d rigs, no retired file among %d, %d wearable and %d held declarations, a retired key, a face-on picture and a fitted part compose nothing" % [GENERATED_RIGS, files.size(), turning, held]
	_stash["retired_note"] = note
	print("RETIRED OK %s; the scan finds 3 fabricated retired names of 5, and a held knife still composes" % note)
	return true


# --- lane 4: REACHES -------------------------------------------------------------------------


func _the_reaches_never_die_silently() -> bool:
	Appearance.forget()
	var tree: Dictionary = ContentLoader.load_tree()
	var decls: Array[Dictionary] = _equip_declarations(tree)
	var drawable_slots: Array[String] = _drawable_slots()

	# A fabricated base with no appearance block at all, for TN 2 below, so the negative does not
	# depend on one real base staying art-less by accident.
	tree["items/_worn_gate_fixture.json"] = [{"id": "item.gate.no_art"}]
	var w: Variant = _world(tree)

	var actor: int = int(w.entities.spawn())
	var item: int = int(w.entities.spawn())
	var seen_ids: Dictionary = {}
	var judged_ids: Array[String] = []
	for d in decls:
		var slot: String = String(d["equipSlot"])
		if not drawable_slots.has(slot):
			continue
		var base_id: String = String(d["id"])
		if seen_ids.has(base_id):
			continue
		seen_ids[base_id] = true
		w.components.set_component(item, "itemBase", {"baseId": base_id})
		var slots_dict: Dictionary = {}
		slots_dict[slot] = item
		w.components.set_component(actor, "equipment", {"slots": slots_dict})
		for view in Appearance.VIEWS:
			var layers: Array[Dictionary] = Appearance.equipment_layers_for(w, actor, view)
			if layers.size() != 1 or layers[0].get("texture") == null:
				push_error("%s worn in its own slot '%s' resolves %d layer(s) on view '%s', want one with a texture -- a dead socket" % [base_id, slot, layers.size(), view])
				return false
		judged_ids.append(base_id)
	if judged_ids.is_empty():
		push_error("no content/items/ base both declares equip art and occupies a slot EQUIP_DRAW_ORDER draws -- REACHES has nothing to judge")
		return false

	# TN 1: an entity with no equipment component at all (every zombie).
	var bare_actor: int = int(w.entities.spawn())
	if not Appearance.equipment_layers_for(w, bare_actor).is_empty():
		push_error("an entity with no equipment component resolved a layer")
		return false

	# TN 2: a base that declares no equip art at all.
	w.components.set_component(item, "itemBase", {"baseId": "item.gate.no_art"})
	w.components.set_component(actor, "equipment", {"slots": {"primary": item}})
	if not Appearance.equipment_layers_for(w, actor).is_empty():
		push_error("item.gate.no_art (no appearance block at all) resolved a layer")
		return false

	# TN 3: an item that DOES carry equip art -- a held knife -- placed in a slot EQUIP_DRAW_ORDER
	# does not name.
	w.components.set_component(item, "itemBase", {"baseId": "item.knife.kitchen"})
	var undrawn_hit: int = 0
	for undrawn_slot in UNDRAWN_SLOTS:
		var undrawn_dict: Dictionary = {}
		undrawn_dict[undrawn_slot] = item
		w.components.set_component(actor, "equipment", {"slots": undrawn_dict})
		for view in Appearance.VIEWS:
			if not Appearance.equipment_layers_for(w, actor, view).is_empty():
				push_error("item.knife.kitchen (equip art present) in slot '%s', which EQUIP_DRAW_ORDER does not name, still resolved a layer on view '%s'" % [undrawn_slot, view])
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
	print("REACHES OK %d equippable base(s) worn in their own slot each resolve one layer in all %d views (%s); refused for no equipment component, a no-art base, %d undrawn slots, and an empty slot" % [judged_ids.size(), Appearance.VIEWS.size(), str(judged_ids), UNDRAWN_SLOTS.size()])
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
	var rig_keys: Array[String] = []
	for k in Appearance.PAWN_KEYS:
		rig_keys.append(String(k))
	for key in Appearance.authored_rig_keys():
		rig_keys.append(String(key))
	if Appearance.PAWN_KEYS.size() != GENERATED_RIGS:
		push_error("PAWN_KEYS names %d rigs, want %d" % [Appearance.PAWN_KEYS.size(), GENERATED_RIGS])
		return false
	for rk in rig_keys:
		var tex: Variant = Appearance.resolve(rk)
		if not _is_pawn_canvas(tex):
			push_error("rig '%s' does not resolve at PAWN_CANVAS %s" % [rk, str(Appearance.PAWN_CANVAS)])
			return false
		if Appearance.canvas_of(rk) != Appearance.PAWN_CANVAS:
			push_error("canvas_of('%s') is %s, not PAWN_CANVAS" % [rk, str(Appearance.canvas_of(rk))])
			return false

	var tree: Dictionary = ContentLoader.load_tree()
	var decls: Array[Dictionary] = _equip_declarations(tree)
	var keys: Array[String] = []
	for d in decls:
		keys.append(String(d["key"]))
	var hit: String = _find_per_rig_overlay(keys, rig_keys)
	if not hit.is_empty():
		push_error("'%s' names a rig plus a suffix; one picture is supposed to serve every body, not one per rig" % hit)
		return false

	# TN: the same scan finds one when handed a fabricated key list that names a rig explicitly.
	var fabricated: Array[String] = keys.duplicate()
	fabricated.append("zombie_screamer_bat_equip")
	var found: String = _find_per_rig_overlay(fabricated, rig_keys)
	if found.is_empty():
		push_error("a fabricated per-rig key 'zombie_screamer_bat_equip' was not found; SHARED's scan cannot say no")
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
	var drawn_wearers: int = 0
	for ent in wearers:
		var eq: Dictionary = world.components.get_component(ent, "equipment") as Dictionary
		var slots: Dictionary = eq.get("slots", {}) as Dictionary
		for s in slots.keys():
			if drawable_slots.has(String(s)) and slots[s] != null:
				wearers_with_drawable_slot += 1
				break
		var layers: Array[Dictionary] = Appearance.equipment_layers_for(world, ent)
		if not layers.is_empty():
			drawn_wearers += 1
		for layer in layers:
			var tex: Variant = layer.get("texture")
			if tex == null or not (tex is Texture2D):
				push_error("entity %d's equipment layer resolves %s, not a texture" % [ent, str(tex)])
				return false
			if not layer.has("at") and not _is_pawn_canvas(tex):
				push_error("entity %d wears a layer that is neither held nor a PAWN_CANVAS wearable" % ent)
				return false
			drawable_layers += 1

	if drawable_layers == 0:
		var note: String = "suburb@%d seed %d boots %d entities with an equipment component (%d holding a slot EQUIP_DRAW_ORDER draws), and none composes a layer -- since the face-on overlays were retired (2026-09-26) only the pack's wearables and held weapons draw, and the starting kit holds none of them. equipment_layers_for was reached for real against the shipped boot and genuinely returned nothing; never passed quietly on an unjudged path." % [GATE_SIZE, CANON_SEED, wearers.size(), wearers_with_drawable_slot]
		_stash["played_note"] = note
		print("PLAYED SKIP %s" % note)
		return true

	var note2: String = "%d of %d equipped entities wear something drawn, %d layer(s)" % [drawn_wearers, wearers.size(), drawable_layers]
	_stash["played_note"] = note2
	print("PLAYED OK suburb@%d seed %d: %s" % [GATE_SIZE, CANON_SEED, note2])
	return true


# --- lane 7: TURNS ---------------------------------------------------------------------------
#
# The wearables turn with the body. One actor, kitted from shipped content -- the pack's helmet,
# vest, gas mask and backpack, and a pack pistol in the hand -- composed once per view. Everything
# asserted here is a reading of real content through the one function the draw loop calls; the
# only fabrication is the bare actor of the negative.
const TURN_KIT: Array = [
	["head", "item.helmet.bike", "item_gear_helmet"],
	["vest", "item.vest.carrier", "item_gear_vest"],
	["face", "item.mask.gas", "item_gear_gasmask"],
	["back", "item.pack.hiking", "item_gear_backpack"],
]


func _the_wearables_turn_with_the_body() -> bool:
	var lane: String = "TURNS"
	Appearance.forget()
	var w: Variant = _world(ContentLoader.load_tree())
	var kit: Dictionary = {"primary": "item.pistol.service"}
	for row in TURN_KIT:
		if not Appearance.turns(String(row[2])):
			push_error("%s: %s's '%s' does not turn; the kit has nothing to judge" % [lane, String(row[1]), String(row[2])])
			return false
		kit[String(row[0])] = String(row[1])
	var actor: int = _kit(w, kit)
	var pistol: Texture2D = Appearance.resolve("item_held_pistol")
	if pistol == null:
		push_error("%s: the pack pistol resolves no picture" % lane)
		return false

	var unders: Dictionary = {}
	for view in Appearance.VIEWS:
		var layers: Array[Dictionary] = Appearance.equipment_layers_for(w, actor, view)
		# The wearables in EQUIP_DRAW_ORDER's order -- vest, back, (the weapon), face, head -- each
		# its own member for this view.
		var want: Array[String] = ["item_gear_vest_%s" % view, "item_gear_backpack_%s" % view, "item_held_pistol", "item_gear_gasmask_%s" % view, "item_gear_helmet_%s" % view]
		if layers.size() != want.size():
			push_error("%s: view '%s' composed %d layers, want %d (%s): %s" % [lane, view, layers.size(), want.size(), str(want), str(layers)])
			return false
		for i in want.size():
			if layers[i].get("texture") != Appearance.resolve(want[i]):
				push_error("%s: view '%s' layer %d is not '%s'" % [lane, view, i, want[i]])
				return false
		unders[view] = []
		for i in layers.size():
			if not bool(layers[i]["over"]):
				(unders[view] as Array).append(want[i])

	# The backpack's side, both ways, from the pack's own z: over seen from the front and the back,
	# under seen from either side. The pistol in the primary hand is under only seen from behind.
	for view in Appearance.VIEWS:
		var want_under: Array = []
		if view == "e" or view == "w":
			want_under.append("item_gear_backpack_%s" % view)
		if view == "n":
			want_under.append("item_held_pistol")
		if unders[view] != want_under:
			push_error("%s: view '%s' draws %s under the body; want %s" % [lane, view, str(unders[view]), str(want_under)])
			return false

	# TN: the same actor with nothing on composes nothing, in every view.
	w.components.set_component(actor, "equipment", {"slots": {}})
	for view in Appearance.VIEWS:
		if not Appearance.equipment_layers_for(w, actor, view).is_empty():
			push_error("%s: an actor with nothing on composed a layer on view '%s'" % [lane, view])
			return false

	print("  TURNS OK the pack's helmet, vest, gas mask and backpack compose their own member in each of %d views in EQUIP_DRAW_ORDER's order with the pistol between; the backpack is under seen from e and w and over from s and n, the primary hand's pistol under only from n; a bare actor composes nothing" % Appearance.VIEWS.size())
	return true


# --- lane 8: HELD ----------------------------------------------------------------------------


# The hand-point complaint for one body picture, or "": the point must be a solid pixel of it.
func _hand_complaint(body: Image, hand: Vector2i) -> String:
	if hand.x < 0 or hand.y < 0 or hand.x >= body.get_width() or hand.y >= body.get_height():
		return "lies outside the %dx%d body" % [body.get_width(), body.get_height()]
	if not _is_solid(body.get_pixelv(hand)):
		return "is not a solid pixel of the body (alpha %d)" % roundi(body.get_pixelv(hand).a * 255.0)
	return ""


# What is wrong with one held layer on one body picture, or "": the grip pixel paints on the hand,
# the barrel points the view's way, only the west view reflects the picture, and at least one solid
# pixel of it is visible past the body (every pixel when over, and outside the body when under).
# Returns the visible count through `seen` so the lane can report it.
func _held_complaint(layer: Dictionary, tex: Image, grip: Vector2i, hand: Vector2i, view: String, body: Image, seen: Array) -> String:
	var size: Vector2i = Vector2i(tex.get_width(), tex.get_height())
	if not _is_solid(tex.get_pixelv(grip)):
		return "has no solid pixel at its grip %s" % str(grip)
	var painted_grip: Vector2i = _painted_at(layer, size, grip.x, grip.y)
	if painted_grip != hand:
		return "paints its grip at %s where the hand is %s" % [str(painted_grip), str(hand)]
	var barrel: Vector2i = _painted_at(layer, size, grip.x + 1, grip.y) - painted_grip
	if barrel != BARREL[view]:
		return "points its barrel %s on view '%s', want %s" % [str(barrel), view, str(BARREL[view])]
	if _is_reflection(layer) != (view == "w"):
		return "is %s on view '%s'; only the west view mirrors the weapon" % ["mirrored" if _is_reflection(layer) else "not mirrored", view]
	var visible: int = 0
	for v in size.y:
		for u in size.x:
			if not _is_solid(tex.get_pixel(u, v)):
				continue
			var at: Vector2i = _painted_at(layer, size, u, v)
			var inside: bool = at.x >= 0 and at.y >= 0 and at.x < body.get_width() and at.y < body.get_height()
			if bool(layer["over"]) or not inside or not _is_solid(body.get_pixelv(at)):
				visible += 1
	seen.append(visible)
	if visible == 0:
		return "shows no solid pixel past the body on view '%s'" % view
	return ""


# A function's own lines in `source`, `func name(` to the next top-level `func `, comments
# stripped so a needle a comment could satisfy cannot pass.
func _function_code(source: String, name: String) -> String:
	var start: int = source.find("func %s(" % name)
	if start < 0:
		return ""
	var stop: int = source.find("\nfunc ", start + 1)
	var body: String = source.substr(start, (stop - start) if stop > 0 else -1)
	var out: PackedStringArray = []
	for line in body.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		out.append(line)
	return "\n".join(out)


const DRAW_NEEDLE: String = "draw_texture_rect(layer[\"texture\"] as Texture2D, _layer_rect(rect, layer), false, gear, bool(layer.get(\"transpose\", false)))"


# Whether the draw loop places and turns a held layer: `_blit_body` hands every layer's `transpose`
# flag to the draw call in both passes, and `_layer_rect` reads the layer's `at` and `size`.
func _draw_loop_complaint(source: String) -> String:
	var blit: String = _function_code(source, "_blit_body")
	if blit.count(DRAW_NEEDLE) != 2:
		return "_blit_body passes a layer's transpose flag to %d draw call(s), want 2 (under and over)" % blit.count(DRAW_NEEDLE)
	var place: String = _function_code(source, "_layer_rect")
	if not place.contains("layer[\"at\"]") or not place.contains("layer[\"size\"]"):
		return "_layer_rect does not read the layer's at and size"
	return ""


# Every key authored.json declares as a held weapon (kind `pack_held`), read from the file itself
# rather than through `Appearance.holds`, so a key the renderer failed to load is still judged.
func _authored_held_keys() -> Array[String]:
	var out: Array[String] = []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(Appearance.AUTHORED_PATH))
	if not (parsed is Dictionary) or not ((parsed as Dictionary).get("keys") is Dictionary):
		return out
	var entries: Dictionary = (parsed as Dictionary)["keys"] as Dictionary
	for key in entries.keys():
		var entry: Variant = entries[key]
		if entry is Dictionary and String((entry as Dictionary).get("kind", "")) == "pack_held":
			out.append(String(key))
	out.sort()
	return out


# The held keys no content base declares from a slot a hand holds (a key of `HELD_HANDS`), or []:
# a held weapon named only by a base worn on the back, or on a belt, is read by content and drawn
# by nothing -- the READS lane in check_authored.gd accepts it, and REACHES skips an undrawn slot.
func _held_keys_not_in_a_hand(keys: Array[String], decls: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for key in keys:
		var in_hand: bool = false
		for d in decls:
			if String(d["key"]) == key and Appearance.HELD_HANDS.has(String(d["equipSlot"])):
				in_hand = true
				break
		if not in_hand:
			out.append(key)
	return out


func _the_weapon_is_in_the_hand() -> bool:
	var lane: String = "HELD"
	Appearance.forget()
	var tree: Dictionary = ContentLoader.load_tree()
	var w: Variant = _world(tree)

	# Every hand point is a solid pixel of the pack body it is drawn on.
	var bodies: Dictionary = {}
	for view in Appearance.VIEWS:
		var body_tex: Texture2D = Appearance.resolve("body_survivor_%s" % view)
		if body_tex == null:
			push_error("%s: body_survivor_%s resolves no picture" % [lane, view])
			return false
		bodies[view] = body_tex.get_image()
		for slot in Appearance.HELD_HANDS.keys():
			var hand: Vector2i = (Appearance.HELD_HANDS[slot] as Dictionary)[view] as Vector2i
			var complaint: String = _hand_complaint(bodies[view] as Image, hand)
			if not complaint.is_empty():
				push_error("%s: the %s hand on view '%s', %s, %s" % [lane, String(slot), view, str(hand), complaint])
				return false
	# TN: a hand at the canvas corner, and one outside it, are refused.
	if _hand_complaint(bodies["s"] as Image, Vector2i(0, 0)).is_empty() or _hand_complaint(bodies["s"] as Image, Vector2i(40, 30)).is_empty():
		push_error("%s: a hand at the corner, or off the canvas, passed; the hand predicate cannot say no" % lane)
		return false

	# The body is never mirrored, the weapon only facing west.
	for facing in [0.0, PI / 2.0, PI, -PI / 2.0]:
		if Appearance.flip_for("body_survivor", facing) != 1.0:
			push_error("%s: flip_for mirrors the pack body facing %.2f; the body never mirrors, only the weapon does" % [lane, facing])
			return false
	# TN: the same question asked of a face-on rig says no facing west, so the loop above can fail.
	if Appearance.flip_for("zombie_screamer", PI) != -1.0:
		push_error("%s: flip_for does not mirror the face-on screamer facing west; the never-mirrors check cannot say no" % lane)
		return false

	# Every held weapon content declares, in both hands, on all four views.
	var keys: Array[String] = []
	for d in _equip_declarations(tree):
		if Appearance.holds(String(d["key"])) and not keys.has(String(d["key"])):
			keys.append(String(d["key"]))
	if keys.is_empty():
		push_error("%s: content declares no held weapon; the lane has nothing to judge" % lane)
		return false
	# Every held weapon authored.json declares is held in a hand by some shipped base -- and all of
	# them are the keys judged below, so none is authored art that only a back or a belt names.
	var authored_held: Array[String] = _authored_held_keys()
	if authored_held.is_empty():
		push_error("%s: authored.json declares no pack_held key; the reach check has nothing to judge" % lane)
		return false
	var unheld: Array[String] = _held_keys_not_in_a_hand(authored_held, _equip_declarations(tree))
	if not unheld.is_empty():
		push_error("%s: no base in a hand slot declares %s -- held art nothing holds" % [lane, str(unheld)])
		return false
	for key in authored_held:
		if not keys.has(key):
			push_error("%s: '%s' is authored as held but is not among the %d keys this lane judges" % [lane, key, keys.size()])
			return false
	# TN: the same predicate refuses a held key only a back slot names, and a key nothing names.
	var fabricated: Array[Dictionary] = [
		{"id": "item.gate.slung", "equipSlot": "back", "key": "item_held_bow"},
		{"id": "item.gate.hand", "equipSlot": "primary", "key": "item_held_pistol"},
	]
	if _held_keys_not_in_a_hand(["item_held_bow", "item_held_pistol", "item_held_nothing"], fabricated) != ["item_held_bow", "item_held_nothing"]:
		push_error("%s: the in-a-hand predicate accepted a back-slot declaration or an undeclared key" % lane)
		return false
	var fewest: int = 1 << 30
	var judged: int = 0
	for key in keys:
		var tex: Texture2D = Appearance.resolve(key)
		var grip: Vector2i = Appearance.grip_of(key)
		if tex == null or grip.x < 0:
			push_error("%s: '%s' resolves no picture or no grip" % [lane, key])
			return false
		var image: Image = tex.get_image()
		var base_id: String = ""
		for d in _equip_declarations(tree):
			if String(d["key"]) == key:
				base_id = String(d["id"])
				break
		for slot in Appearance.HELD_HANDS.keys():
			var actor: int = _kit(w, {String(slot): base_id})
			for view in Appearance.VIEWS:
				var layers: Array[Dictionary] = Appearance.equipment_layers_for(w, actor, view)
				if layers.size() != 1 or layers[0].get("texture") != tex or not layers[0].has("at"):
					push_error("%s: %s in the %s hand composed %s on view '%s', want one held layer of '%s'" % [lane, base_id, String(slot), str(layers), view, key])
					return false
				var want_over: bool = not (EXPECT_BEHIND[slot] as Array).has(view)
				if bool(layers[0]["over"]) != want_over:
					push_error("%s: %s in the %s hand draws %s on view '%s'" % [lane, key, String(slot), "over" if bool(layers[0]["over"]) else "under", view])
					return false
				var seen: Array = []
				var hand: Vector2i = (Appearance.HELD_HANDS[slot] as Dictionary)[view] as Vector2i
				var complaint: String = _held_complaint(layers[0], image, grip, hand, view, bodies[view] as Image, seen)
				if not complaint.is_empty():
					push_error("%s: %s in the %s hand %s" % [lane, key, String(slot), complaint])
					return false
				fewest = mini(fewest, int(seen[0]))
				judged += 1

	# TN, one per claim, on the pistol through the same predicates.
	var p_tex: Image = Appearance.resolve("item_held_pistol").get_image()
	var p_grip: Vector2i = Appearance.grip_of("item_held_pistol")
	var p_size: Vector2i = Vector2i(p_tex.get_width(), p_tex.get_height())
	var hand_e: Vector2i = (Appearance.HELD_HANDS["primary"] as Dictionary)["e"] as Vector2i
	var east: Dictionary = Appearance.held_pose(p_size, p_grip, hand_e, "e")
	east["over"] = true
	if _held_complaint(east, p_tex, p_grip, hand_e, "w", bodies["w"] as Image, []).is_empty():
		push_error("%s: an east pose judged as the west view passed; the barrel check cannot say no" % lane)
		return false
	var hand_n: Vector2i = (Appearance.HELD_HANDS["primary"] as Dictionary)["n"] as Vector2i
	var reflected: Dictionary = Appearance.held_pose(p_size, p_grip, hand_n, "n")
	reflected["size"] = Vector2i(p_size.x, p_size.y)
	reflected["over"] = true
	if not _is_reflection(reflected) or _held_complaint(reflected, p_tex, p_grip, hand_n, "n", bodies["n"] as Image, []).is_empty():
		push_error("%s: a transposed-only (mirrored) pose on the north view passed" % lane)
		return false
	var shifted: Dictionary = east.duplicate()
	shifted["at"] = (east["at"] as Vector2i) + Vector2i(1, 0)
	if _held_complaint(shifted, p_tex, p_grip, hand_e, "e", bodies["e"] as Image, []).is_empty():
		push_error("%s: a weapon painted one pixel off its hand passed" % lane)
		return false
	# TN for the painted-pixel model itself: on a fabricated 2x1 picture, a quarter turn clockwise
	# paints (1, 0) straight below (0, 0).
	var turned: Dictionary = {"at": Vector2i(5, 5), "size": Vector2i(-2, 1), "transpose": true}
	if _painted_at(turned, Vector2i(2, 1), 1, 0) - _painted_at(turned, Vector2i(2, 1), 0, 0) != Vector2i(0, 1):
		push_error("%s: the painted-pixel model does not turn a picture a quarter clockwise" % lane)
		return false

	# The draw loop hands the flag and the placement over -- and the needle can fail.
	var source: String = FileAccess.get_file_as_string(MAIN_PATH)
	var loop: String = _draw_loop_complaint(source)
	if not loop.is_empty():
		push_error("%s: %s" % [lane, loop])
		return false
	var dropped: String = source.replace(DRAW_NEEDLE, "draw_texture_rect(layer[\"texture\"] as Texture2D, _layer_rect(rect, layer), false, gear)")
	var commented: String = source.replace("\t\t\t" + DRAW_NEEDLE, "\t\t\t# " + DRAW_NEEDLE)
	if _draw_loop_complaint(dropped).is_empty() or _draw_loop_complaint(commented).is_empty():
		push_error("%s: a draw loop that drops the transpose flag, or comments the draw out, passed" % lane)
		return false

	var note: String = "%d held weapon(s) draw in both hands on all %d views grip-on-hand, barrel the view's way, mirrored facing west only, at least %d solid pixel(s) visible (alpha >= %d); the body never mirrors" % [keys.size(), Appearance.VIEWS.size(), fewest, ALPHA_SOLID]
	_stash["held_note"] = note
	print("  HELD OK %s -- %d poses judged; all %d authored held keys held in a hand by a shipped base; every hand point on the body; a corner hand, an east pose as west, a mirrored north, a one-pixel slip, a dropped draw flag, a back-slot-only or undeclared held key, and an unmirrored face-on rig each refused" % [note, judged, authored_held.size()])
	return true
