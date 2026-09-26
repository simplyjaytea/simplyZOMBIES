extends SceneTree
# The appearance pipeline: content declares how a thing looks, presentation resolves it.
#
# This gate carries more weight than usual because content_validator.gd is shallow -- it
# checks top-level property types and rejects unexpected top-level keys, but does not recurse
# into nested objects. So `appearance`'s inner shape is *not* schema-enforced at load; a typo
# in `sprite` or a malformed `tint` would sail through godot:validate and show up as a thing
# that silently renders wrong. Everything below is the enforcement.

const World = preload("res://sim/world.gd")
const ContentLoader = preload("res://platform/content_loader.gd")
const Appearance = preload("res://presentation/appearance.gd")
const CameraUtil = preload("res://presentation/camera.gd")
const Palette = preload("res://presentation/palette.gd")
const ItemGlyph = preload("res://presentation/item_glyph.gd")
const SimCondition = preload("res://sim/condition.gd")

const SPRITE_DIR: String = "res://assets/sprites"
const HEX := "^#[0-9a-f]{6}$"
const KEY := "^[a-z0-9_.]+$"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _declared_appearances_are_well_formed() and ok
	ok = _sprite_keys_resolve() and ok
	ok = _every_canvas_is_native() and ok
	ok = _procedural_fallback_still_works() and ok
	ok = _the_player_has_a_body() and ok
	ok = _the_roster_resolves_bodies() and ok
	ok = _colonists_wear_the_pack_body_tinted() and ok
	ok = _art_is_not_modulated_by_a_role_colour() and ok
	ok = _equipped_gear_layers_resolve() and ok
	ok = _props_look_like_something() and ok
	ok = _items_look_like_something() and ok
	ok = _item_pictures_are_real_and_drawn() and ok
	ok = _the_body_chart_is_ten_parts_in_three_poses() and ok
	if ok:
		print("APPEARANCE_OK schema keys resolve, fallback intact, the player has a body, the roster resolves shared and distinct rigs, colonists wear the pack body with six tints, items resolve art or a class glyph, the pack's item pictures are declared, gated and drawn on the floor and the bag plate, the body chart is ten parts in three poses")
		quit(0)
	else:
		push_error("APPEARANCE_FAIL")
		quit(1)

func _fixture() -> Dictionary:
	return {"seed": 77, "tick_hz": 20, "map": {"width": 12, "height": 10, "walls": []}, "player": {"id": 0, "x": 6.0, "y": 5.0, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}

# Every appearance block anywhere in content, as {"path#id": block}.
#
# Array-topped files are walked as well as object-topped ones. They were not until this slice, and
# the omission was not cosmetic: every item file and the new props file is a JSON array, so every
# item's `appearance` -- equipSprite, equipSpriteFront and all -- was invisible to the shape and
# key assertions below, which is a gate that could not fail for most of the content it names.
# Keyed by path *and* id because one array file holds many entries and "which one" is the first
# thing a failure needs to say.
func _all_blocks() -> Dictionary:
	var out: Dictionary = {}
	var tree: Dictionary = ContentLoader.load_tree()
	for path in tree.keys():
		if String(path).begins_with("schemas/"):
			continue
		var raw: Variant = tree[path]
		var entries: Array = raw as Array if raw is Array else [raw]
		for entry_v in entries:
			if not (entry_v is Dictionary):
				continue
			var entry: Dictionary = entry_v as Dictionary
			var block: Variant = entry.get("appearance")
			if block is Dictionary:
				out["%s#%s" % [String(path), String(entry.get("id", "?"))]] = block as Dictionary
	return out

# Whether one key is legal inside one entry's `appearance` block. One predicate, so the loop below
# and the negatives that prove it cannot drift apart.
#
# Every kind shares one vocabulary, and this list is what catches a nested typo the content
# validator cannot see (it checks top-level types only). A vehicle is the single exception: its
# picture set is one three-quarter view per axis rather than a single `sprite`, so `variants` is
# legal there and refused everywhere else. Its inner shape -- {id, ns, ew}, each key resolving at
# its own canvas -- is check_wrecks.gd's DRESSING lane, not this one.
func _appearance_key_ok(k: String, path: String) -> bool:
	if ["sprite", "tint", "features", "portrait", "equipSprite", "equipSpriteFront", "shape", "size"].has(k):
		return true
	# The gunsmithing pair, and the only overlay family that does not share the hand anchor: a
	# part declares the picture drawn when it is fitted, and its *host* declares where each of its
	# slots sits so one picture can serve a pistol and a rifle. Items only -- an anchor on a
	# zombie would be a key nothing reads.
	if ["attachmentSprite", "partAnchors"].has(k):
		return path.begins_with("items/")
	return k == "variants" and path.begins_with("vehicles/")


# The shape the schemas document but the validator cannot reach.
func _declared_appearances_are_well_formed() -> bool:
	var hex := RegEx.new(); hex.compile(HEX)
	var key := RegEx.new(); key.compile(KEY)
	# Prove the predicate before trusting it: it has to refuse `variants` on a kind that is not a
	# vehicle, or the exception below is a hole rather than an exception. A shared allowlist that
	# accepted `variants` everywhere would make it legal on a zombie, where it would resolve
	# nothing and report nothing -- exactly the nested-key trap this lane exists to catch.
	if _appearance_key_ok("variants", "zombies/walker.json#zombie.walker"):
		push_error("the appearance allowlist accepts 'variants' outside content/vehicles/; the vehicle exception is a hole")
		return false
	if not _appearance_key_ok("variants", "vehicles/sedan.json#vehicle.sedan"):
		push_error("the appearance allowlist refuses 'variants' on a vehicle, which is where the per-axis picture set lives")
		return false
	if _appearance_key_ok("sprrite", "vehicles/sedan.json#vehicle.sedan"):
		push_error("the appearance allowlist accepts a misspelled key on a vehicle; the exception widened the whole list")
		return false
	# The gunsmithing keys are items-only for the same reason `variants` is vehicles-only: an
	# exception that widened the whole list would let a misspelling through everywhere.
	if _appearance_key_ok("attachmentSprite", "zombies/walker.json#zombie.walker"):
		push_error("the appearance allowlist accepts 'attachmentSprite' outside content/items/; the exception is a hole")
		return false
	if not _appearance_key_ok("partAnchors", "items/ranged.json#item.pistol.service"):
		push_error("the appearance allowlist refuses 'partAnchors' on an item, which is where a weapon says where its slots are")
		return false
	if _appearance_key_ok("attachmentSprrite", "items/attachments.json#item.attach.suppressor"):
		push_error("the appearance allowlist accepts a misspelled key on an item; the exception widened the whole list")
		return false
	var blocks: Dictionary = _all_blocks()
	for path in blocks.keys():
		var block: Dictionary = blocks[path]
		for k in block.keys():
			if not _appearance_key_ok(String(k), String(path)):
				push_error("%s: appearance has unknown key '%s'" % [path, k])
				return false
		if block.has("tint"):
			var t: Variant = block["tint"]
			if not (t is String) or hex.search(String(t)) == null:
				push_error("%s: appearance.tint '%s' is not #rrggbb lowercase" % [path, str(t)])
				return false
		if block.has("sprite"):
			var s: Variant = block["sprite"]
			if not (s is String) or key.search(String(s)) == null:
				push_error("%s: appearance.sprite '%s' is not a registry key (a key, not a path)" % [path, str(s)])
				return false
		for prop in ["equipSprite", "equipSpriteFront"]:
			if block.has(prop):
				var es: Variant = block[prop]
				if not (es is String) or key.search(String(es)) == null:
					push_error("%s: appearance.%s '%s' is not a registry key (a key, not a path)" % [path, prop, str(es)])
					return false
		# A prop's footprint. `shape` must be a primitive the renderer owns -- content naming a
		# shape nothing draws would fall back to a box and look like a decision somebody made --
		# and `size` is a fraction of a tile, so a 6 there is a prop the size of a house.
		if block.has("shape"):
			var sh: Variant = block["shape"]
			if not (sh is String) or not Appearance.PROP_SHAPES.has(String(sh)):
				push_error("%s: appearance.shape '%s' is not one of %s" % [path, str(sh), str(Appearance.PROP_SHAPES)])
				return false
		if block.has("size"):
			var sz: Variant = block["size"]
			if not (sz is float or sz is int) or float(sz) < 0.1 or float(sz) > 1.0:
				push_error("%s: appearance.size '%s' is not a tile fraction in [0.1, 1.0]" % [path, str(sz)])
				return false
	print("SHAPE OK %d blocks" % blocks.size())
	return true

# A key naming a file that does not exist must fail the build, not draw nothing.
func _sprite_keys_resolve() -> bool:
	var native: int = int(CameraUtil.ART_NATIVE)
	var resolved: int = 0
	var blocks: Dictionary = _all_blocks()
	for path in blocks.keys():
		var block: Dictionary = blocks[path]
		for prop in ["sprite", "equipSprite", "equipSpriteFront"]:
			if not block.has(prop):
				continue
			var k: String = String(block[prop])
			var tex: Variant = Appearance.resolve(k)
			if tex == null:
				push_error("%s: appearance.%s '%s' has no file at %s/%s.png" % [path, prop, k, SPRITE_DIR, k])
				return false
			# The canvas table: a tile for props and tile art, the pawn shape for bodies and
			# gear, the atlas (assets/sprites/README.md), every size read off camera.gd rather
			# than carried here -- the 64 -> 32 move of 2026-09-02 is what a second copy of the
			# number would have drifted from. A body left on the old square would stand half a
			# tile short of its shadow without ever erroring, so the shape is a build failure,
			# not a footnote.
			var size: Vector2 = (tex as Texture2D).get_size()
			var want_size: Vector2i = Appearance.canvas_of(k)
			if Vector2i(size) != want_size:
				push_error("%s: appearance.%s '%s' is %dx%d, its canvas is %dx%d (Appearance.canvas_of; %d is CameraUtil.ART_NATIVE)" % [path, prop, k, int(size.x), int(size.y), want_size.x, want_size.y, native])
				return false
			resolved += 1
	# The canvas assertion must have judged real files, or it proves nothing.
	if resolved == 0:
		push_error("no sprite keys resolved -- the canvas assertion had nothing to judge")
		return false
	print("KEYS OK %d resolved on the %dx%d canvas" % [resolved, native, native])
	return true

# Every file in the directory, referenced or not: an unreferenced stray is one content edit away
# from drawing, and nothing above would have judged it. Raw Image.load, same as appearance.gd's
# headless fallback. (It used to also cover the item blocks _all_blocks could not see, which it no
# longer has to -- array-topped files are walked now -- but a stray file still has no entry.)
func _every_canvas_is_native() -> bool:
	var native: int = int(CameraUtil.ART_NATIVE)
	var atlases: int = 0
	var dir := DirAccess.open(SPRITE_DIR)
	if dir == null:
		push_error("cannot open %s" % SPRITE_DIR)
		return false
	var judged: int = 0
	for f in dir.get_files():
		if not String(f).ends_with(".png"):
			continue
		var img := Image.new()
		if img.load("%s/%s" % [SPRITE_DIR, f]) != OK:
			push_error("%s/%s does not load as an image" % [SPRITE_DIR, f])
			return false
		# The canvas table, not the tile: an atlas is a table of tiles and its size is an entry
		# in Appearance.canvas_of, the one place a second shape is allowed to be named.
		var want_size: Vector2i = Appearance.canvas_of(String(f).trim_suffix(".png"))
		if img.get_width() != want_size.x or img.get_height() != want_size.y:
			push_error("%s/%s is %dx%d, its canvas is %dx%d (Appearance.canvas_of; %d is CameraUtil.ART_NATIVE; assets/sprites/README.md)" % [SPRITE_DIR, f, img.get_width(), img.get_height(), want_size.x, want_size.y, native])
			return false
		if want_size != Vector2i(native, native):
			atlases += 1
		judged += 1
	if judged == 0:
		push_error("no PNGs in %s -- the canvas assertion had nothing to judge" % SPRITE_DIR)
		return false
	# The table must have been read for real: the atlas and the pawns are the shapes it exists
	# for, and a lane that only ever saw tiles would pass a table nobody consults.
	if atlases == 0:
		push_error("no file in %s is on a non-tile canvas -- Appearance.canvas_of was never exercised" % SPRITE_DIR)
		return false
	if Appearance.canvas_of("no_such_key") != Vector2i(native, native):
		push_error("canvas_of does not default an unknown key to the %dx%d tile" % [native, native])
		return false
	print("CANVAS OK %d files, %d of them on a non-tile canvas (the atlas, the pawns, the gear), every one at its Appearance.canvas_of size (tile %dx%d)" % [judged, atlases, native, native])
	return true

# The fallback is the supported path, not a stopgap: with no content at all, every role still
# yields a drawable tint and radius and an explicitly null texture.
#
# The empty content tree is what makes this lane mean something now that the player resolves art
# like everybody else. It used to probe all four roles against the *real* tree, which worked only
# because none of the four resolved anything -- the moment `player.body` shipped, the same
# assertion would have started failing for the right behaviour, which is a gate reading its own
# subject as a regression. So the roles are probed with `content_tree: {}` (nothing to resolve, by
# construction) and the real tree keeps the three roles that legitimately declare no look.
func _procedural_fallback_still_works() -> bool:
	# Between the two worlds, because Appearance._cache is a `static var` and therefore shared
	# between every world one gate process boots (CLAUDE.md's static-var trap).
	Appearance.forget()
	var fixture: Dictionary = _fixture()
	fixture["content_tree"] = {}
	var bare: Variant = World.new(fixture)
	for role in [{"player": true}, {"unique": true}, {"bait": true}, {}]:
		var look: Dictionary = Appearance.for_entity(bare, role as Dictionary)
		if look["texture"] != null:
			push_error("role %s resolved a texture out of an empty content tree; the look is in code, not in content" % str(role))
			return false
		if not (look["tint"] is Color):
			push_error("role %s produced no tint" % str(role))
			return false
		if float(look["radius"]) <= 0.0:
			push_error("role %s produced a non-positive radius" % str(role))
			return false
	Appearance.forget()
	var w: Variant = World.new(_fixture())
	# The roles that declare no look in the shipped tree either. The player is deliberately not
	# among them any more -- `_the_player_has_a_body` owns that case in both directions.
	for role2 in [{"unique": true}, {"bait": true}, {}]:
		var real: Dictionary = Appearance.for_entity(w, role2 as Dictionary)
		if real["texture"] != null:
			push_error("role %s resolved a texture with no sprite declared" % str(role2))
			return false
		if not (real["tint"] is Color) or float(real["radius"]) <= 0.0:
			push_error("role %s produced no drawable shape" % str(role2))
			return false
	# An unknown zombie type must degrade to the role colour rather than erroring.
	var unknown: Dictionary = Appearance.for_entity(w, {"ztype": "zombie.does_not_exist"})
	if (unknown["tint"] as Color) != Palette.COLOURS["wanderer"]:
		push_error("an unknown zombie type should fall back to the wanderer colour")
		return false
	print("FALLBACK OK 4 roles on an empty tree, 3 on the shipped one")
	return true


# The player has art, and it comes from content.
#
# The style fixtures turned up that the shipped game had no player sprite at all: every other body
# hands `for_entity` a content id (a zombie its type, a unique survivor its identity or rolled
# look, a raider its archetype) and the player carried none, so the resolver had nothing to look
# up and the protagonist drew as a disc. `Appearance.PLAYER_LOOK_ID` is the floor that fixes it,
# and this lane is what stops the fix from quietly becoming a hardcoded texture in presentation.
#
# True positive: the shipped tree resolves the rig, unstained, at the player's radius.
# True negative: the same probe against a tree with players/ erased must resolve *nothing* and
# fall back to the role colour -- which is red if anybody ever reaches for the file directly.
func _the_player_has_a_body() -> bool:
	Appearance.forget()
	var w: Variant = World.new(_fixture())
	var look: Dictionary = Appearance.for_entity(w, {"player": true})
	if look["texture"] == null:
		push_error("the player resolved no texture; %s declares appearance.sprite and nothing read it" % Appearance.PLAYER_LOOK_ID)
		return false
	if (look["tint"] as Color) != Color.WHITE:
		push_error("the player's art declares no tint and must draw white, got %s" % str(look["tint"]))
		return false
	if float(look["radius"]) != 14.0:
		push_error("the player draws at radius %f; the shadow and the fallback disc are sized off it" % float(look["radius"]))
		return false
	var block: Dictionary = Appearance.of_content(w, "player", Appearance.PLAYER_LOOK_ID)
	if not block.has("sprite"):
		push_error("%s declares no appearance.sprite; the player's look belongs in content, not in the draw loop" % Appearance.PLAYER_LOOK_ID)
		return false

	# The true negative. Same world shape, same probe, one directory removed. The drop is
	# counted rather than assumed: a tree that dropped nothing would satisfy every assertion
	# below by accident, which is a true negative that cannot fail.
	Appearance.forget()
	var stripped: Dictionary = ContentLoader.load_tree()
	var dropped: int = 0
	for path in stripped.keys():
		if String(path).begins_with("players/"):
			stripped.erase(path)
			dropped += 1
	if dropped == 0:
		push_error("no content under players/ to drop -- the true negative had nothing to remove")
		return false
	var fixture: Dictionary = _fixture()
	fixture["content_tree"] = stripped
	var bare: Variant = World.new(fixture)
	var fallback: Dictionary = Appearance.for_entity(bare, {"player": true})
	if fallback["texture"] != null:
		push_error("with content/players/ erased the player still resolved a texture: the sprite key is in presentation, not in content")
		return false
	if (fallback["tint"] as Color) != Palette.COLOURS["player"]:
		push_error("with no content the player must fall back to the player role colour, got %s" % str(fallback["tint"]))
		return false
	print("PLAYER OK %s resolves '%s' white at r14, and degrades to the role colour without its %d content file(s)" % [Appearance.PLAYER_LOOK_ID, String(block["sprite"]), dropped])
	return true


# The whole roster, one row per body the game can stand in a district. `probe` is the
# role-flag Dictionary _draw_entities builds; `kind` feeds of_content. This lane replaced
# `_tints_come_from_content_not_code` in the commit that moved the screamer's and bloater's
# colours out of content tints and into the sprite ramps: the pinned hexes retired with the
# tints they pinned, and the guarantee underneath -- a colour can never move back into the
# draw loop -- survives below as the stripped-tree negative over every family at once.
#
# A colony.look id routes through kind "survivor" inside for_entity and resolves anyway,
# because _content_entry ignores `kind` for a Dictionary tree (world.content always is one;
# `c is Object` is false for it). Noted, not "fixed": the lookup is by id, the ids do not
# collide, and a fix in passing is how a resolver grows a second code path.
const ROSTER: Array[Dictionary] = [
	{"id": "player.body", "kind": "player", "probe": {"player": true}, "tinted": false},
	{"id": "survivor.unique.mara", "kind": "survivor", "probe": {"unique": true, "cid": "survivor.unique.mara"}, "tinted": false},
	{"id": "survivor.unique.ellis", "kind": "survivor", "probe": {"unique": true, "cid": "survivor.unique.ellis"}, "tinted": false},
	{"id": "colony.look.01", "kind": "survivor", "probe": {"unique": true, "cid": "colony.look.01"}, "tinted": true},
	{"id": "colony.look.02", "kind": "survivor", "probe": {"unique": true, "cid": "colony.look.02"}, "tinted": true},
	{"id": "colony.look.03", "kind": "survivor", "probe": {"unique": true, "cid": "colony.look.03"}, "tinted": true},
	{"id": "colony.look.04", "kind": "survivor", "probe": {"unique": true, "cid": "colony.look.04"}, "tinted": true},
	{"id": "colony.look.05", "kind": "survivor", "probe": {"unique": true, "cid": "colony.look.05"}, "tinted": true},
	{"id": "colony.look.06", "kind": "survivor", "probe": {"unique": true, "cid": "colony.look.06"}, "tinted": true},
	{"id": "zombie.shambler", "kind": "zombie", "probe": {"ztype": "zombie.shambler"}, "tinted": false},
	{"id": "zombie.screamer", "kind": "zombie", "probe": {"ztype": "zombie.screamer"}, "tinted": false},
	{"id": "zombie.bloater", "kind": "zombie", "probe": {"ztype": "zombie.bloater"}, "tinted": false},
	# The two wave kinds the stalker-and-runner slice added. They declare the shambler's own
	# sprite key and no block tint, so they resolve its texture and draw white here -- which is
	# exactly the gap docs/23's "a silhouette per kind" follow-up piece names. What tells one
	# from another on the ground today is the per-body colour rolled from each kind's own
	# `variance.tints` palette, which arrives on the draw item rather than in the block
	# (check_m2_variance.gd READER), and is therefore invisible to this lane by construction.
	{"id": "zombie.stalker", "kind": "zombie", "probe": {"ztype": "zombie.stalker"}, "tinted": false},
	{"id": "zombie.runner", "kind": "zombie", "probe": {"ztype": "zombie.runner"}, "tinted": false},
	# And the two the armoured-and-heavy slice added, on the same terms and for the same reason.
	# The armoured one is the awkward entry to leave here and that is exactly why it is written
	# down: it is *wearing a vest and a helmet* the sim resolves and the paperdoll draws
	# (check_worn.gd's REACHES lane walks equipped bases wherever they are worn), but the body
	# under the gear is still the shambler's rig at the shambler's white, so the silhouette a
	# player reads across a street is the shambler's silhouette. The heavy is worse off still --
	# docs/14 calls it enormous and it draws at exactly one tile like everything else.
	{"id": "zombie.armored", "kind": "zombie", "probe": {"ztype": "zombie.armored"}, "tinted": false},
	{"id": "zombie.heavy", "kind": "zombie", "probe": {"ztype": "zombie.heavy"}, "tinted": false},
	{"id": "raider.scav", "kind": "raider", "probe": {"raider": true, "cid": "raider.scav"}, "tinted": true},
	{"id": "raider.gunhand", "kind": "raider", "probe": {"raider": true, "cid": "raider.gunhand"}, "tinted": true},
	# The two role archetypes (the roles slice). Same body as the other two, and that is the
	# information rule rather than a shortcut: a picture that said "this one came for your pantry"
	# would answer, from across a street, the question a raid is supposed to make you guess at.
	{"id": "raider.looter", "kind": "raider", "probe": {"raider": true, "cid": "raider.looter"}, "tinted": true},
	{"id": "raider.lookout", "kind": "raider", "probe": {"raider": true, "cid": "raider.lookout"}, "tinted": true},
	# The four rolled raider looks (the individuals slice). Since "The bodies turn and walk"
	# (2026-09-26) every raider, archetype and look alike, wears the one pack survivor body under
	# ONE raider tint (docs/30, "The whole outpost pack": with one shared rig a raider would
	# otherwise be one of your own at a glance), so `tinted: true` on all eight, and the tint is
	# the same hex on every one -- check_m2_raiders.gd's LOOKS lane is where "one tint, never two"
	# is asserted, because two tints would tell the archetypes apart.
	{"id": "raider.look.01", "kind": "raider", "probe": {"raider": true, "cid": "raider.look.01"}, "tinted": true},
	{"id": "raider.look.02", "kind": "raider", "probe": {"raider": true, "cid": "raider.look.02"}, "tinted": true},
	{"id": "raider.look.03", "kind": "raider", "probe": {"raider": true, "cid": "raider.look.03"}, "tinted": true},
	{"id": "raider.look.04", "kind": "raider", "probe": {"raider": true, "cid": "raider.look.04"}, "tinted": true},
]

# zombie.base spawns nowhere and gets no art -- it is the `extends` parent the wave types
# inherit stats (never looks) from, and the roadmap record says so.
const ROSTER_EXEMPT: Array[String] = ["zombie.base"]

# Where roster ids live. colony/ also holds the two generators and the skill web, which are not
# bodies, so the colony entry names the one file rather than the directory -- and `looks.json` is
# that one file for the raiders' rolled looks as well as the colonists', because a look entry is
# an id with an appearance block wherever it is worn and a second home for the same shape is how
# a roster grows a body nothing judges.
const ROSTER_DIRS: Array[String] = ["players/", "zombies/", "survivors/uniques/", "raiders/", "colony/looks.json"]

# Ids that deliberately resolve one shared texture. Since "The bodies turn and walk" (2026-09-26)
# every human is one: the player, Mara, Ellis, the six colonists (the tint is their identity) and
# every raider archetype *and every rolled raider look* stand on the outpost pack's one survivor
# body (docs/30, "The outpost pack, adopted", decision 2 -- "a colony of identical pack survivors
# is the shipped shape ... not a bug"). Which raider carries the gun is still not something a look
# across a street may answer, and the raider tint is shared for that reason
# (check_m2_raiders.gd asserts the same thing from the content side).
#
# The third group is the one that is a **gap rather than a decision**, and it is here so the gap
# is written down where a reader will meet it: the stalker, the runner, the armoured and the
# heavy all wear the shambler's rig because a new sprite key is `sprites:check` work (Pillow, a
# byte comparison of generated art) that the slices adding them deliberately did not take.
# docs/23's what's-left names the one follow-up piece, "a silhouette per kind", and all four are
# on it. Until it lands, this line is the honest statement that four kinds with different senses,
# different speeds and -- since the armoured one -- different armour are one picture.
const ROSTER_SHARED: Array = [
	[
		"player.body", "survivor.unique.mara", "survivor.unique.ellis",
		"colony.look.01", "colony.look.02", "colony.look.03", "colony.look.04", "colony.look.05", "colony.look.06",
		"raider.scav", "raider.gunhand", "raider.looter", "raider.lookout",
		"raider.look.01", "raider.look.02", "raider.look.03", "raider.look.04",
	],
	["zombie.shambler", "zombie.stalker", "zombie.runner", "zombie.armored", "zombie.heavy"],
]

# One id per distinct picture; every pair must resolve different textures. Four since the pack
# took the humans and the shambler: the pack survivor, the pack shambler, and the two generated
# rigs the pack does not supply.
const ROSTER_DISTINCT: Array[String] = [
	"player.body", "zombie.shambler", "zombie.screamer", "zombie.bloater",
]


# Every body resolves its art through the resolver the draw loop asks, tinted exactly as content
# declared: white for art with no tint, the declared tint for a colonist or a raider. The
# sharing and distinctness assertions work by texture *identity* -- Appearance._cache holds
# one Texture2D per key, so `==` says whether two ids reached one file.
func _the_roster_resolves_bodies() -> bool:
	Appearance.forget()
	var w: Variant = World.new(_fixture())
	var textures: Dictionary = {}
	for row in ROSTER:
		var id: String = String(row["id"])
		var look: Dictionary = Appearance.for_entity(w, (row["probe"] as Dictionary).duplicate())
		if look["texture"] == null:
			push_error("%s resolves no texture; its content declares a sprite key and nothing read it" % id)
			return false
		textures[id] = look["texture"]
		if bool(row["tinted"]):
			var block: Dictionary = Appearance.of_content(w, String(row["kind"]), id)
			if not block.has("tint"):
				push_error("%s declares no tint beside its sprite; on one shared body the tint is the only thing telling it apart" % id)
				return false
			if (look["tint"] as Color) != Color(String(block["tint"])):
				push_error("%s: for_entity did not hand the looks.json tint to the modulate, got %s" % [id, str(look["tint"])])
				return false
		elif (look["tint"] as Color) != Color.WHITE:
			push_error("%s has art with no declared tint and must draw white, got %s" % [id, str(look["tint"])])
			return false
	for group in ROSTER_SHARED:
		for id2 in group as Array:
			if textures[String(id2)] != textures[String((group as Array)[0])]:
				push_error("%s resolves a different texture from %s -- these ids share one body on purpose" % [String(id2), String((group as Array)[0])])
				return false
	for i in ROSTER_DISTINCT.size():
		for j in range(i + 1, ROSTER_DISTINCT.size()):
			if textures[ROSTER_DISTINCT[i]] == textures[ROSTER_DISTINCT[j]]:
				push_error("%s and %s resolve one texture -- two bodies you cannot tell apart" % [ROSTER_DISTINCT[i], ROSTER_DISTINCT[j]])
				return false

	# Completeness: a body added to content joins ROSTER or is exempted with its reason,
	# never slips past unjudged.
	var tree: Dictionary = ContentLoader.load_tree()
	var known: Dictionary = {}
	for row2 in ROSTER:
		known[String(row2["id"])] = true
	var walked: int = 0
	for path in tree.keys():
		var in_scope: bool = false
		for prefix in ROSTER_DIRS:
			if String(path).begins_with(prefix):
				in_scope = true
				break
		if not in_scope:
			continue
		var raw: Variant = tree[path]
		var entries: Array = raw as Array if raw is Array else [raw]
		for entry_v in entries:
			if not (entry_v is Dictionary):
				continue
			var walked_id: String = String((entry_v as Dictionary).get("id", ""))
			if walked_id.is_empty():
				continue
			walked += 1
			if not known.has(walked_id) and not ROSTER_EXEMPT.has(walked_id):
				push_error("%s joined the roster and nothing judged its art -- add it to ROSTER, or to ROSTER_EXEMPT with the reason" % walked_id)
				return false
	if walked == 0:
		push_error("the roster walk found no ids -- the completeness assertion had nothing to judge")
		return false

	# The true negative, one family at a time: with its content dropped, each probe must
	# resolve nothing and fall back to its role colour -- red the moment a sprite key or a
	# colour moves into presentation. The drops are counted, because a tree that dropped
	# nothing would pass every assertion below by accident.
	Appearance.forget()
	var stripped: Dictionary = ContentLoader.load_tree()
	var dropped: int = 0
	for path2 in stripped.keys():
		var p: String = String(path2)
		if p.begins_with("players/") or p == "survivors/uniques/mara.json" or p == "colony/looks.json" \
				or p == "raiders/scav.json" or p == "zombies/screamer.json":
			stripped.erase(path2)
			dropped += 1
	if dropped < 5:
		push_error("only %d of the 5 named roster files dropped -- the true negative had less to remove than it promises" % dropped)
		return false
	var fixture: Dictionary = _fixture()
	fixture["content_tree"] = stripped
	var bare: Variant = World.new(fixture)
	var fallbacks: Array[Dictionary] = [
		{"probe": {"player": true}, "role": "player", "label": "the player"},
		{"probe": {"unique": true, "cid": "survivor.unique.mara"}, "role": "survivor", "label": "mara"},
		{"probe": {"unique": true, "cid": "colony.look.01"}, "role": "survivor", "label": "a colonist"},
		{"probe": {"raider": true, "cid": "raider.scav"}, "role": "raider", "label": "a raider"},
		{"probe": {"ztype": "zombie.screamer"}, "role": "wanderer", "label": "a screamer"},
	]
	for c in fallbacks:
		var fb: Dictionary = Appearance.for_entity(bare, (c["probe"] as Dictionary))
		if fb["texture"] != null:
			push_error("with its content dropped %s still resolved a texture: the sprite key lives in presentation, not in content" % String(c["label"]))
			return false
		if (fb["tint"] as Color) != Palette.COLOURS[String(c["role"])]:
			push_error("with no content %s must fall back to the %s role colour, got %s" % [String(c["label"]), String(c["role"]), str(fb["tint"])])
			return false
	Appearance.forget()
	print("ROSTER OK %d bodies resolve, %d shared groups, %d distinct pictures, %d ids walked, 5 fallbacks refused without content" % [ROSTER.size(), ROSTER_SHARED.size(), ROSTER_DISTINCT.size(), walked])
	return true


# The generated colonists wear the one pack body, and the looks.json tint is who they are.
#
# This lane was GREY until "The bodies turn and walk" (2026-09-26): the colonist rig was drawn
# achromatic so the tint supplied all of its colour, and the lane held that pairing and a
# composed-luminance guard -- median grey x tint luma, against the brightest ground -- that only
# an achromatic rig makes computable. The rig was deleted with the other five human bodies when
# every human moved onto the outpost pack's survivor, which is drawn in colour; a tint now
# multiplies a coloured picture, so neither the achromatic bound nor the grey-times-tint
# arithmetic has a subject any more. That is the colour half docs/30 ("The outpost pack,
# adopted") says does not carry over to pack art -- the pack reads by its own outline, and its
# untinted survivor already sits below this palette's street luma, so a luma guard here would be
# red on the art itself. Contrast against the ground is re-pinned by "The ground is the pack's"
# (docs/23), the slice that regrades the ground to the pack's own table. What survives here is
# the half that still has a subject: each colony look pairs the shared human body with a tint,
# and the six tints are six different people.
func _tints_differ(tints: Array[String]) -> bool:
	var seen: Dictionary = {}
	for t in tints:
		if seen.has(t):
			return false
		seen[t] = true
	return true


func _colonists_wear_the_pack_body_tinted() -> bool:
	Appearance.forget()
	var w: Variant = World.new(_fixture())
	var hex := RegEx.new()
	hex.compile(HEX)
	# The body every human wears is whatever the player's own look names -- read, never copied,
	# so this lane follows the body rather than remembering a key.
	var body: String = String(Appearance.of_content(w, "player", Appearance.PLAYER_LOOK_ID).get("sprite", ""))
	if body.is_empty() or not Appearance.turns(body):
		push_error("%s names '%s', which is not a body that turns; the colonists have no shared pack body to be judged against" % [Appearance.PLAYER_LOOK_ID, body])
		return false
	var tints: Array[String] = []
	for n in range(1, 7):
		var id: String = "colony.look.%02d" % n
		var block: Dictionary = Appearance.of_content(w, "survivor", id)
		if String(block.get("sprite", "")) != body:
			push_error("%s draws '%s', not the shared human body '%s'" % [id, String(block.get("sprite", "")), body])
			return false
		var t: Variant = block.get("tint")
		if not (t is String) or hex.search(String(t)) == null:
			push_error("%s tint '%s' is not #rrggbb lowercase; without it six colonists are one person" % [id, str(t)])
			return false
		tints.append(String(t))
	if not _tints_differ(tints):
		push_error("two colony looks declare the same tint %s; the tint is the whole of a colonist's identity" % str(tints))
		return false
	# True negatives, through the same predicate and the same pairing test the shipped data passed.
	var twice: Array[String] = tints.duplicate()
	twice[1] = twice[0]
	if _tints_differ(twice):
		push_error("a tint list with one colour twice passed; the distinctness predicate reads nothing")
		return false
	if Appearance.turns("zombie_screamer") or not Appearance.turns(body):
		push_error("turns() cannot tell the pack body from a face-on rig; the pairing above proves nothing")
		return false
	Appearance.forget()
	print("COLONISTS OK 6 colony looks wear '%s' with 6 different tints %s; a repeated tint is refused (the achromatic rig and its grey-times-tint ground guard retired with the rig)" % [body, str(tints)])
	return true

# A role colour stands in for missing art; it must not filter art that exists. Drawn as a
# modulate it multiplies every pixel of a sprite -- so a survivor sprite with no declared
# tint would arrive stained the tan survivor colour rather than looking like what was drawn.
func _art_is_not_modulated_by_a_role_colour() -> bool:
	var role: Color = Palette.COLOURS["survivor"]
	var declared: Color = Color("#d95947")
	# Sprite present, content said nothing about colour -> draw the art as drawn.
	if Appearance.modulate_for(true, false, role) != Color.WHITE:
		push_error("a sprite with no declared tint must draw white, not the %s role colour" % role)
		return false
	# Sprite present and content asked for a tint -> honour it.
	if Appearance.modulate_for(true, true, declared) != declared:
		push_error("a declared tint must still modulate a sprite")
		return false
	# No sprite -> the role colour is exactly what the procedural shape needs.
	if Appearance.modulate_for(false, false, role) != role:
		push_error("with no sprite the role colour must survive for the procedural shape")
		return false
	print("MODULATE OK")
	return true

# The base the EQUIP lane leans on for "an equipped item with no art draws nothing". It is
# deliberately one the renderer does not draw a slot for either, so no art slice will hand it a
# picture in passing; the lane re-checks that it still declares none before trusting it.
const NO_ART_BASE: String = "item.glasses.safety"


# Equipped-gear layers: a rendered slot holding an item with equipSprite must actually resolve
# a texture (the true positives item.bat.aluminium and item.duffel.canvas exist for, one over-body
# and one under -- the duffel since the hiking pack took the outpost pack's four-view backpack,
# whose per-view layering check_worn.gd's TURNS lane owns); an item with no equipSprite (NO_ART_BASE, whose art-lessness the lane
# verifies first), an item in a slot the renderer does not draw, and
# an entity with no equipment component at all (every zombie) must all fall out silently rather
# than erroring -- each is its own assertion so a regression in any one path fails here instead
# of drawing nothing, or the wrong thing, on screen.
func _equipped_gear_layers_resolve() -> bool:
	Appearance.forget()
	var w: Variant = World.new(_fixture())
	var actor: int = int(w.entities.spawn())
	var bat: int = int(w.entities.spawn())
	var pack: int = int(w.entities.spawn())
	var bare: int = int(w.entities.spawn())
	w.components.set_component(bat, "itemBase", {"baseId": "item.bat.aluminium"})
	w.components.set_component(pack, "itemBase", {"baseId": "item.duffel.canvas"})
	w.components.set_component(bare, "itemBase", {"baseId": NO_ART_BASE})

	w.components.set_component(actor, "equipment", {"slots": {"primary": bat}})
	var layers: Array[Dictionary] = Appearance.equipment_layers_for(w, actor)
	if layers.size() != 1 or layers[0].get("texture") == null or not bool(layers[0].get("over", false)):
		push_error("primary slot holding item.bat.aluminium should yield one over-body layer with a texture, got %s" % str(layers))
		return false

	# item.duffel.canvas declares both equipSprite (the bag, under) and equipSpriteFront (the
	# strap crossing the chest, always over regardless of the back slot's own default) -- one
	# equipped item, two layers, split correctly.
	w.components.set_component(actor, "equipment", {"slots": {"back": pack}})
	layers = Appearance.equipment_layers_for(w, actor)
	if layers.size() != 2 or layers[0].get("texture") == null or bool(layers[0].get("over", true)) \
			or layers[1].get("texture") == null or not bool(layers[1].get("over", false)):
		push_error("back slot holding item.duffel.canvas should yield an under-body bag layer then an over-body strap layer, got %s" % str(layers))
		return false

	# Both a worn bag and a held weapon at once: three layers, correctly ordered under-then-over,
	# not one clobbering another.
	w.components.set_component(actor, "equipment", {"slots": {"back": pack, "primary": bat}})
	layers = Appearance.equipment_layers_for(w, actor)
	if layers.size() != 3 or bool(layers[0].get("over", true)) or not bool(layers[1].get("over", false)) \
			or not bool(layers[2].get("over", false)):
		push_error("back+primary together should yield three layers (bag under, strap over, bat over), got %s" % str(layers))
		return false

	# The no-art negative checks its own subject first. It used to name a real weapon, and the
	# worn-look slice gave that weapon art -- which did not fail anything, it just quietly
	# stopped asserting, because an item with art in a drawn slot yields a layer for the
	# *right* reason. A negative whose subject can be taken away silently is the dead-socket
	# family; this one says so instead.
	var bare_entry: Dictionary = Appearance.entry_of(w, "item", NO_ART_BASE)
	if bare_entry.is_empty():
		push_error("%s is not in content; the no-art negative has no subject" % NO_ART_BASE)
		return false
	var bare_look: Variant = bare_entry.get("appearance")
	if bare_look is Dictionary and (bare_look as Dictionary).has("equipSprite"):
		push_error("%s now declares an equipSprite, so it can no longer serve as the no-art negative -- point NO_ART_BASE at a base that declares none" % NO_ART_BASE)
		return false

	w.components.set_component(actor, "equipment", {"slots": {"primary": bare}})
	if not Appearance.equipment_layers_for(w, actor).is_empty():
		push_error("%s declares no equipSprite; equipping it should yield no layer" % NO_ART_BASE)
		return false

	w.components.set_component(actor, "equipment", {"slots": {"belt": bat}})
	if not Appearance.equipment_layers_for(w, actor).is_empty():
		push_error("belt is not a rendered slot; an item there should yield no layer regardless of its equipSprite")
		return false

	if not Appearance.equipment_layers_for(w, bat).is_empty():
		push_error("an entity with no equipment component (every zombie) should yield no layers")
		return false

	print("EQUIP OK")
	return true


# Whether a prop's content says enough for it to be drawn at all: art, or a colour to draw the
# footprint in. This is the rule prop.schema.json's `anyOf` writes down and **nothing else
# enforces** -- the Godot validator never recurses into `appearance`, and the frozen oracle loads
# schemas only for its own six content types, of which `prop` is not one. Named as a function so
# the fabricated negatives below refuse through exactly the predicate the shipped props pass.
#
# Deliberately *not* asked through `modulate_for`: that helper answers what colour multiplies a
# drawn thing and has its own lane above, and teaching it about props would make one rule two.
func _prop_is_drawable(block: Dictionary, look: Dictionary) -> bool:
	return look.get("texture") != null or block.has("tint")


# What makes this prop's look different from another's -- the art it draws, or the colour it
# draws in. Two props that answer the same string are two props you cannot tell apart.
func _prop_look_identity(block: Dictionary, look: Dictionary) -> String:
	if look.get("texture") != null:
		return "sprite:%s" % String(block.get("sprite", "?"))
	return "tint:%s" % str(look.get("tint"))


# The opaque bounding box of a texture, longest side in pixels. Zero for art that is entirely
# transparent, which is its own failure.
func _footprint_px(texture: Variant) -> int:
	var image: Image = (texture as Texture2D).get_image()
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
		return 0
	return maxi(max_x - min_x + 1, max_y - min_y + 1)


# How far the art may sit from the footprint its content declares, in pixels of an ART_NATIVE
# tile. Wide enough that a bumper or a flame tongue is not a build failure, narrow enough that a
# bed drawn at a crate's size is. Halved with the tile (8 at 64, 4 at 32): it is a fraction of
# the picture, not a number of screen pixels.
const FOOTPRINT_SLACK_PX: int = 4

# Every prop id the renderer can ask for has an entry in content, and that entry says enough to
# draw: art, or a tint, and now that the props have art it is art for every one of them.
#
# The lane changed shape with the sprites. It used to require `tint` outright, which is exactly
# what could not survive the art: a tint declared beside a sprite is multiplied over every pixel
# of it (`modulate_for`), so "every prop declares a tint" and "props draw as they were painted"
# cannot both hold. What survives is the *guarantee* underneath the old assertion -- every prop
# draws as something, and no two of them draw as the same thing -- restated over the look rather
# than over one field of it. Distinctness is over the resolved look; for the two state pairs it
# is additionally over the decoded pixels, because two files with different names and identical
# contents would satisfy every assertion about keys.
func _props_look_like_something() -> bool:
	Appearance.forget()
	var w: Variant = World.new(_fixture())
	var ids: Array[String] = []
	for kind in Appearance.PROP_KINDS:
		ids.append(String(kind["id"]))
		if not String(kind["flag_id"]).is_empty():
			ids.append(String(kind["flag_id"]))
	if ids.is_empty():
		push_error("PROP_KINDS is empty -- this lane had nothing to judge")
		return false
	var identities: Array[String] = []
	var textured: int = 0
	for id in ids:
		var block: Dictionary = Appearance.of_content(w, "prop", id)
		var look: Dictionary = Appearance.prop_of(w, id)
		if not _prop_is_drawable(block, look):
			push_error("%s declares neither appearance.sprite that resolves nor appearance.tint; a prop with neither is an invisible thing standing in the district" % id)
			return false
		if block.has("sprite"):
			# Art is drawn as it was painted. A tint beside a sprite is a stain on it, so the
			# schema's anyOf is satisfied by the sprite and the tint is absent -- and if one
			# were added by accident, the look would stop being white and this would say so.
			if look["texture"] == null:
				push_error("%s declares appearance.sprite '%s' and resolved no texture" % [id, String(block["sprite"])])
				return false
			if (look["tint"] as Color) != Color.WHITE:
				push_error("%s has art and must draw it unstained; got tint %s" % [id, str(look["tint"])])
				return false
			# The footprint the content declares is the footprint the art was authored to. This
			# is what keeps `size` from becoming decoration the moment a prop has a sprite: the
			# procedural path stops reading it, so the gate starts.
			var want: int = int(round(float(look["size"]) * CameraUtil.ART_NATIVE))
			var got: int = _footprint_px(look["texture"])
			if absi(got - want) > FOOTPRINT_SLACK_PX:
				push_error("%s declares size %.2f (%d px of a tile) and its art measures %d px across; the number in content is what the picture was authored to" % [id, float(look["size"]), want, got])
				return false
			textured += 1
		elif (look["tint"] as Color) != Color(String(block["tint"])):
			push_error("%s: prop_of did not use the content tint" % id)
			return false
		if not Appearance.PROP_SHAPES.has(String(look["shape"])):
			push_error("%s resolved shape '%s', which the renderer does not draw" % [id, look["shape"]])
			return false
		if float(look["size"]) < 0.1 or float(look["size"]) > 1.0:
			push_error("%s resolved size %f, outside one tile" % [id, float(look["size"])])
			return false
		# Two states of one prop that look identical are one state: a searched cupboard and an
		# unsearched one, a lit fire and a cold one, have to be distinguishable on sight.
		var identity: String = _prop_look_identity(block, look)
		if identities.has(identity):
			push_error("%s resolves the same look (%s) as another prop -- two props you cannot tell apart" % [id, identity])
			return false
		identities.append(identity)
	if textured == 0:
		push_error("not one prop resolved art -- the unstained and footprint assertions had nothing to judge")
		return false

	# The state pairs, compared as pictures rather than as key names: two files called different
	# things and holding identical pixels would pass every assertion above and still ship a
	# searched cupboard that looks unsearched.
	for pair in [["prop.container", "prop.container.searched"], ["prop.campfire", "prop.campfire.lit"]]:
		var a: Dictionary = Appearance.prop_of(w, String((pair as Array)[0]))
		var b: Dictionary = Appearance.prop_of(w, String((pair as Array)[1]))
		if a["texture"] == null or b["texture"] == null:
			continue
		if (a["texture"] as Texture2D).get_image().get_data() == (b["texture"] as Texture2D).get_image().get_data():
			push_error("%s and %s are the same picture; the state is not readable on sight" % [(pair as Array)[0], (pair as Array)[1]])
			return false

	# The true negatives, each through the predicate the shipped props just passed.
	if _prop_is_drawable({"shape": "box", "size": 0.5}, {"texture": null, "tint": Palette.COLOURS["prop"]}):
		push_error("a prop block with neither a sprite nor a tint was judged drawable; the anyOf has no enforcement anywhere")
		return false
	if not _prop_is_drawable({"tint": "#112233"}, {"texture": null, "tint": Color("#112233")}):
		push_error("a tint-only prop block was judged undrawable; the procedural footprint is a supported path")
		return false
	var stand_in: Variant = Appearance.resolve("prop_bed")
	if _prop_look_identity({"sprite": "prop_bed"}, {"texture": stand_in}) \
			!= _prop_look_identity({"sprite": "prop_bed"}, {"texture": stand_in}):
		push_error("two prop entries naming one sprite resolved different identities; the distinctness check above cannot catch a duplicated key")
		return false
	if _prop_look_identity({"sprite": "prop_bed"}, {"texture": stand_in}) \
			== _prop_look_identity({"sprite": "prop_well"}, {"texture": stand_in}):
		push_error("two prop entries naming different sprites resolved one identity; the distinctness check reads nothing")
		return false

	var unknown: Dictionary = Appearance.prop_of(w, "prop.does_not_exist")
	if (unknown["tint"] as Color) != Palette.COLOURS["prop"]:
		push_error("an unauthored prop id should fall back to the drab prop colour, got %s" % str(unknown["tint"]))
		return false
	if String(unknown["shape"]) != Appearance.PROP_SHAPE_DEFAULT or unknown["texture"] != null:
		push_error("an unauthored prop id should still be drawable as the default shape with no texture")
		return false
	print("PROPS OK %d ids, %d with art drawn unstained at their declared footprint, distinct looks, both state pairs different pictures, unknown id degrades" % [ids.size(), textured])
	return true


# --- ITEMS --------------------------------------------------------------------------------

# `item.appearance.sprite` was declared in the schema and read by nothing: docs/23 named it the
# twelfth dead socket of the milestone, and a dropped fire axe drew the same ten-pixel square as a
# dropped bandage. `Appearance.item_look` is the reader, and this lane holds down what it must do:
# resolve declared art, fall back to a shape chosen by the item's **class**, and never branch on an
# id -- which is the rule the whole appearance block exists to enforce.
func _items_look_like_something() -> bool:
	var w: Variant = World.new({"seed": 4242, "tick_hz": 20, "map": {"width": 8, "height": 8, "walls": []}, "player": {"id": 0, "x": 1.5, "y": 1.5, "stance": 2}})

	# True positive: a base that declares a key with a file behind it resolves a texture. No
	# shipped item declares one yet, so the assertion is made against a fabricated entry rather
	# than skipped -- otherwise the resolving half of this function is judged by nothing until the
	# art slice lands, which is exactly how a socket stays dead.
	var borrowed: String = ""
	for key in ["prop_container", "prop_campfire", "prop_bed"]:
		if Appearance.resolve(key) != null:
			borrowed = key
			break
	if borrowed.is_empty():
		push_error("no committed sprite to borrow, so the resolving half of item_look cannot be judged")
		return false
	var tree: Dictionary = w.content as Dictionary
	tree["items/_gate_fixture.json"] = [
		{"id": "item.gate.painted", "name": "Painted Thing", "class": "tool", "size": {"w": 1, "h": 1}, "massKg": 0.1,
			"appearance": {"sprite": borrowed, "tint": "#8a9a5b"}},
		{"id": "item.gate.bare", "name": "Bare Thing", "class": "weapon.melee", "size": {"w": 1, "h": 1}, "massKg": 0.1},
	]
	w.content_resolved = {}

	var painted: Dictionary = Appearance.item_look(w, "item.gate.painted")
	if painted["texture"] == null:
		push_error("a base declaring sprite \"%s\" resolved no texture; appearance.sprite is still read by nothing" % borrowed)
		return false
	if not bool(painted["declaredTint"]) or (painted["tint"] as Color) != Color("#8a9a5b"):
		push_error("a declared item tint did not reach the look: %s" % str(painted["tint"]))
		return false

	# True negative: no art, so a glyph and the ground-item role colour. "Role colours are the
	# floor" is the same rule every other fallback in this file follows.
	var bare: Dictionary = Appearance.item_look(w, "item.gate.bare")
	if bare["texture"] != null:
		push_error("a base declaring no sprite resolved a texture anyway")
		return false
	if bool(bare["declaredTint"]) or (bare["tint"] as Color) != Palette.COLOURS["groundItem"]:
		push_error("a base with no tint should fall back to the ground-item colour, got %s" % str(bare["tint"]))
		return false

	# The glyph is chosen by class, and different classes are different shapes -- one shape for
	# everything would satisfy "has a glyph" and tell the player nothing.
	var seen: Dictionary = {}
	for pair in [["weapon.melee", "a bat"], ["weapon.ranged", "a pistol"], ["container", "a pack"],
			["consumable", "a tin"], ["material", "scrap"], ["armor", "a vest"], ["tool", "a lamp"],
			["attachment", "a scope"]]:
		var shape: int = ItemGlyph.shape_for(String((pair as Array)[0]))
		seen[shape] = String((pair as Array)[1])
	if seen.size() < 6:
		push_error("eight item classes resolved only %d distinct glyphs" % seen.size())
		return false
	if ItemGlyph.shape_for("not_a_class_anybody_wrote") != ItemGlyph.DEFAULT:
		push_error("an unknown item class did not fall back to the default glyph")
		return false

	# Every shipped base resolves a look, and every shipped class is one this table knows about.
	var bases: int = 0
	var classes: Dictionary = {}
	for path in (w.content as Dictionary).keys():
		if not String(path).begins_with("items/") or String(path).find("_gate_fixture") >= 0:
			continue
		for entry in (w.content as Dictionary)[path] as Array:
			var d: Dictionary = entry as Dictionary
			var look: Dictionary = Appearance.item_look(w, String(d.get("id", "")))
			if not look.has("glyph"):
				push_error("%s resolved no look at all" % String(d.get("id", "")))
				return false
			classes[String(d.get("class", ""))] = true
			bases += 1
	for cls in classes.keys():
		if not ItemGlyph.BY_CLASS.has(String(cls)):
			push_error("shipped class \"%s\" has no glyph of its own and draws the default" % String(cls))
			return false

	# The dead-socket half, and the point of the lane: the two places that draw an item both call
	# this, and the fixed square the ground loop used is gone. Textual, because "something reads
	# it" is what a dead socket is about and a resolver nobody calls resolves correctly forever.
	var main_src: String = FileAccess.get_file_as_string("res://presentation/main.gd")
	if main_src.find("Appearance.item_look") < 0:
		push_error("the ground-item loop does not call Appearance.item_look")
		return false
	if main_src.find("Rect2(float(sc[\"sx\"]) - 5.0") >= 0:
		push_error("the ground-item loop still draws the fixed ten-pixel square")
		return false
	if FileAccess.get_file_as_string("res://ui/bag_grid.gd").find("Appearance.item_look") < 0:
		push_error("the inventory grid does not call Appearance.item_look, so a bag and the floor can disagree about a thing")
		return false
	print("ITEMS OK %d bases resolve a look, %d classes have %d distinct glyphs, declared art and tint win, and the ground and the grid both read it" % [bases, classes.size(), seen.size()])
	return true


# --- ITEM PICTURES ------------------------------------------------------------------------

# The outpost pack's inventory icons became `appearance.sprite` for the bases they depict
# (docs/23, "A picture per item base"). ITEMS above proves the reader; this lane proves the four
# things a picture per base could get wrong, each with a true positive and a true negative:
# every declared item sprite is a real authored icon, a picture never carries a tint that would
# modulate it, two grades of one thing draw one picture (a picture must not say what the name
# has not), and the floor and the bag plate both *draw* what `item_look` resolved.

# Source text with every `#` comment removed, quote-aware: a needle a comment can satisfy cannot
# fail (CLAUDE.md's READ_KEYS note), and `main.gd` carries `Color("#rrggbb")` literals a bare split
# on `#` would cut in half.
func _without_comments(text: String) -> String:
	var out: Array[String] = []
	for line in text.split("\n"):
		var l: String = String(line)
		var quote: String = ""
		var cut: int = -1
		for i in range(l.length()):
			var c: String = l[i]
			if quote != "":
				if c == "\\":
					continue
				if c == quote and (i == 0 or l[i - 1] != "\\"):
					quote = ""
			elif c == "\"" or c == "'":
				quote = c
			elif c == "#":
				cut = i
				break
		out.append(l if cut < 0 else l.substr(0, cut))
	return "\n".join(out)


# The text of one function: its signature line and everything indented after it.
func _function_text(code: String, signature_prefix: String) -> String:
	var lines: PackedStringArray = code.split("\n")
	var start: int = -1
	for i in range(lines.size()):
		if String(lines[i]).begins_with(signature_prefix):
			start = i
			break
	if start < 0:
		return ""
	var body: Array[String] = [String(lines[start])]
	for i in range(start + 1, lines.size()):
		var line: String = String(lines[i])
		if line.strip_edges() != "" and not line.begins_with("\t") and not line.begins_with(" "):
			break
		body.append(line)
	return "\n".join(body)


# Whether `needles` appear in `code` in that order once comments are gone. One predicate for the
# real functions and the fabrications that prove it.
func _appears_in_order(code: String, needles: Array) -> bool:
	var at: int = 0
	var bare: String = _without_comments(code)
	for needle in needles:
		var found: int = bare.find(String(needle), at)
		if found < 0:
			return false
		at = found + String(needle).length()
	return true


# The floor keeps a picture at a whole fraction of the world's pixel: one predicate over a size and
# a zoom so the ladder and a fabricated 0.34-of-a-tile draw are judged by the same code.
func _is_whole_ratio(px: float, native: float) -> bool:
	if px <= 0.0:
		return false
	var down: float = native / px
	var up: float = px / native
	return is_equal_approx(down, roundf(down)) or is_equal_approx(up, roundf(up))


func _the_floor_and_the_bag_draw_the_picture() -> bool:
	var floor_needles: Array = ["Appearance.item_look(", "look[\"texture\"]", "Appearance.item_icon_px(", "draw_texture_rect("]
	var bag_needles: Array = ["Appearance.item_look(", "look[\"texture\"]", "draw_texture_rect("]
	var main_src: String = FileAccess.get_file_as_string("res://presentation/main.gd")
	var bag_src: String = FileAccess.get_file_as_string("res://ui/bag_grid.gd")
	var floor_fn: String = _function_text(main_src, "func _draw_entities(")
	var bag_fn: String = _function_text(bag_src, "static func draw_item(")
	if floor_fn.is_empty() or bag_fn.is_empty():
		push_error("PICTURES: could not find _draw_entities in main.gd or draw_item in bag_grid.gd; the draw assertion is reading the wrong place")
		return false

	# True negatives first, on fabricated bodies, so the scanner is shown to fail before it is
	# trusted on real code. The control is a body shaped like the real one.
	var control: String = "var look = Appearance.item_look(world, id)\nvar art = look[\"texture\"]\nvar px = Appearance.item_icon_px(z)\ndraw_texture_rect(art, r, false, c)\n"
	if not _appears_in_order(control, floor_needles):
		push_error("PICTURES: the draw scanner refused a body that draws the picture; it would refuse the real ones")
		return false
	var fabrications: Array = [
		["a draw call that is only a comment", "var look = Appearance.item_look(world, id)\nvar art = look[\"texture\"]\nvar px = Appearance.item_icon_px(z)\n# draw_texture_rect(art, r, false, c)\n"],
		["a look that never reaches a texture draw", "var look = Appearance.item_look(world, id)\nvar px = Appearance.item_icon_px(z)\nItemGlyph.draw_glyph(self, r, 0, c)\n"],
		["a draw before the look it should have drawn", "draw_texture_rect(art, r, false, c)\nvar look = Appearance.item_look(world, id)\nvar art = look[\"texture\"]\nvar px = Appearance.item_icon_px(z)\n"],
		["a floor draw that never sizes the picture", "var look = Appearance.item_look(world, id)\nvar art = look[\"texture\"]\ndraw_texture_rect(art, glyph_rect, false, c)\n"],
	]
	for row in fabrications:
		if _appears_in_order(String((row as Array)[1]), floor_needles):
			push_error("PICTURES: the draw scanner accepted %s; it proves nothing" % String((row as Array)[0]))
			return false

	if not _appears_in_order(floor_fn, floor_needles):
		push_error("PICTURES: the ground-item loop does not pass an `item_look` texture to draw_texture_rect at Appearance.item_icon_px; a declared item sprite would resolve and never reach the floor")
		return false
	if not _appears_in_order(bag_fn, bag_needles):
		push_error("PICTURES: the bag plate does not pass an `item_look` texture to draw_texture_rect; a declared item sprite would resolve and never reach a bag")
		return false

	# The floor's size rule: a whole ratio to the art at every rung of the zoom ladder, and the
	# old third-of-a-tile draw (21.76 px at zoom 64) is the case it refuses.
	for zoom in CameraUtil.ZOOM_STEPS:
		var px: float = Appearance.item_icon_px(float(zoom))
		if not is_equal_approx(px, float(zoom) * Appearance.ITEM_ICON_FLOOR_SCALE) or not _is_whole_ratio(px, CameraUtil.ART_NATIVE):
			push_error("PICTURES: an item picture at zoom %s is %s px; that is not a whole ratio of the %d px art" % [str(zoom), str(px), int(CameraUtil.ART_NATIVE)])
			return false
	if _is_whole_ratio(64.0 * 0.34, CameraUtil.ART_NATIVE):
		push_error("PICTURES: the whole-ratio predicate accepted a third of a tile; it proves nothing")
		return false
	return true


func _item_pictures_are_real_and_drawn() -> bool:
	var w: Variant = World.new({"seed": 4243, "tick_hz": 20, "map": {"width": 8, "height": 8, "walls": []}, "player": {"id": 0, "x": 1.5, "y": 1.5, "stance": 2}})
	var native: int = int(CameraUtil.ART_NATIVE)
	var authored: Dictionary = Appearance.authored_canvases()
	var pictured: int = 0
	var fallback: int = 0
	var keys: Dictionary = {}
	var by_id: Dictionary = {}
	for path in (w.content as Dictionary).keys():
		if not String(path).begins_with("items/"):
			continue
		for entry in (w.content as Dictionary)[path] as Array:
			var d: Dictionary = entry as Dictionary
			var id: String = String(d.get("id", ""))
			var block: Dictionary = d.get("appearance", {}) as Dictionary
			var look: Dictionary = Appearance.item_look(w, id)
			by_id[id] = String(block.get("sprite", ""))
			if block.has("sprite"):
				var key: String = String(block["sprite"])
				if look["texture"] == null:
					push_error("PICTURES: %s declares sprite '%s' and item_look resolved no texture" % [id, key])
					return false
				if Vector2i((look["texture"] as Texture2D).get_size()) != Vector2i(native, native):
					push_error("PICTURES: %s's picture '%s' is not the %dx%d icon canvas" % [id, key, native, native])
					return false
				if not authored.has(key):
					push_error("PICTURES: %s declares sprite '%s', which authored.json does not declare; a picture must be the pack's, sourced and gated" % [id, key])
					return false
				if bool(look["declaredTint"]):
					push_error("PICTURES: %s declares a tint beside sprite '%s'; the tint would modulate the pack's art" % [id, key])
					return false
				keys[key] = true
				pictured += 1
			else:
				if look["texture"] != null:
					push_error("PICTURES: %s declares no sprite and item_look resolved a texture anyway" % id)
					return false
				fallback += 1
	if pictured == 0 or fallback == 0:
		push_error("PICTURES: %d bases have a picture and %d fall back; the lane needs both to judge either" % [pictured, fallback])
		return false

	# A picture must not say what the name has not: the grades of one medicine, and clean and
	# untreated water, draw one picture. One predicate over two ids; the fabrications prove it can
	# say no, so "they share a key" is not a comparison that always passes.
	var tree: Dictionary = w.content as Dictionary
	tree["items/_gate_pictures.json"] = [
		{"id": "item.gate.twin_a", "name": "Twin A", "class": "consumable", "size": {"w": 1, "h": 1}, "massKg": 0.1, "appearance": {"sprite": "item_antibiotics"}},
		{"id": "item.gate.twin_b", "name": "Twin B", "class": "consumable", "size": {"w": 1, "h": 1}, "massKg": 0.1, "appearance": {"sprite": "item_antibiotics"}},
		{"id": "item.gate.other", "name": "Other", "class": "consumable", "size": {"w": 1, "h": 1}, "massKg": 0.1, "appearance": {"sprite": "item_painkillers"}},
	]
	w.content_resolved = {}
	if not _draw_one_picture(w, ["item.gate.twin_a", "item.gate.twin_b"]):
		push_error("PICTURES: two bases declaring one key were judged to draw different pictures")
		return false
	if _draw_one_picture(w, ["item.gate.twin_a", "item.gate.other"]):
		push_error("PICTURES: two bases declaring different keys were judged to draw one picture; the grade check proves nothing")
		return false
	for family in [
		["item.antibiotics.course", "item.antibiotics.veterinary", "item.antibiotics.expired"],
		["item.water.bottle", "item.water.bottle.untreated"],
	]:
		for id in family as Array:
			if not by_id.has(String(id)) or String(by_id[String(id)]).is_empty():
				push_error("PICTURES: %s is in a grade family that must draw one picture and declares none" % String(id))
				return false
		if not _draw_one_picture(w, family as Array):
			push_error("PICTURES: %s draw different pictures; a picture must not say what the name has not" % str(family))
			return false

	if not _the_floor_and_the_bag_draw_the_picture():
		return false
	print("PICTURES OK %d of %d bases draw one of the pack's %d icons and %d fall back to their class's glyph; every declared item sprite resolves at %dx%d, is an authored key and carries no tint; the antibiotic grades and the two waters draw one picture; the floor and the bag plate both draw what item_look resolved, and a comment, a missing draw, a misordered draw and an unsized floor draw are each refused" % [pictured, pictured + fallback, keys.size(), fallback, native, native])
	return true


func _draw_one_picture(w: Variant, ids: Array) -> bool:
	var first: Variant = null
	for id in ids:
		var tex: Variant = Appearance.item_look(w, String(id))["texture"]
		if tex == null:
			return false
		if first == null:
			first = tex
		elif tex != first:
			return false
	return true


# --- CHART --------------------------------------------------------------------------------

# The inventory sheet's body chart: ten parts by three poses, each its own picture, stacked at one
# rect and tinted by the sim's four states. It replaced a figure drawn live out of tapered
# capsules, which the owner judged "too alien" (docs/30, "The inventory sheet").
#
# Four things have to hold, and every one of them is a way the chart could be quietly wrong:
# every part of every pose has a picture (a missing one is a hole in a body, and nothing else
# would say so); the pictures are **masks**, near-white, because the tint is a multiply and a
# dark mask would come out black whatever the state; the poses are actually different pictures
# rather than one drawn three times; and something draws them.
const CHART_MASK_FLOOR: float = 0.80


func _the_body_chart_is_ten_parts_in_three_poses() -> bool:
	var missing: Array[String] = []
	var wrong_size: Array[String] = []
	var too_dark: Array[String] = []
	var rects: Dictionary = {}
	var digests: Dictionary = {}
	for pose in Appearance.CHART_POSES:
		for part in SimCondition.PART_ORDER:
			var key: String = Appearance.chart_key(String(part), String(pose))
			var texture: Texture2D = Appearance.resolve(key)
			if texture == null:
				missing.append(key)
				continue
			var image: Image = texture.get_image()
			if image.get_width() != Appearance.CHART_CANVAS.x or image.get_height() != Appearance.CHART_CANVAS.y:
				wrong_size.append("%s is %dx%d" % [key, image.get_width(), image.get_height()])
				continue
			var used: Rect2i = image.get_used_rect()
			if used.size.x <= 0 or used.size.y <= 0:
				missing.append("%s (drawn nothing)" % key)
				continue
			rects[key] = used
			# The mask rule. A part whose brightest pixel is dark cannot be tinted: the draw is a
			# multiply, so its lightest possible result is already darker than the state colour.
			var brightest: float = 0.0
			for y in range(used.position.y, used.position.y + used.size.y):
				for x in range(used.position.x, used.position.x + used.size.x):
					var px: Color = image.get_pixel(x, y)
					if px.a > 0.5:
						brightest = maxf(brightest, maxf(px.r, maxf(px.g, px.b)))
			if brightest < CHART_MASK_FLOOR:
				too_dark.append("%s peaks at %.2f" % [key, brightest])
			# The raw bytes, compared as bytes. Hashing them through
			# `get_data().get_string_from_ascii()` -- the obvious spelling -- reads an RGBA buffer
			# as a C string and stops at the first zero, which every transparent pixel is: every
			# key digested to the empty string and the comparison below fired on nothing. A gate
			# that cannot pass is as bad as one that cannot fail.
			digests[key] = image.get_data()
	if not missing.is_empty():
		push_error("%d chart parts have no picture: %s" % [missing.size(), ", ".join(missing)])
		return false
	if not wrong_size.is_empty():
		push_error("chart parts off the %dx%d canvas: %s" % [Appearance.CHART_CANVAS.x, Appearance.CHART_CANVAS.y, ", ".join(wrong_size)])
		return false
	if not too_dark.is_empty():
		push_error("chart parts too dark to tint (a multiply cannot brighten): %s" % ", ".join(too_dark))
		return false

	# The pose has to be worth having: two poses drawn the same are one pose stored twice. Judged
	# per *pose pair* rather than per part, because some parts legitimately hold still -- your feet
	# stay planted when you crouch, and seen from directly above (which is this game's camera) a
	# crawling trunk is the same shape as a standing one. What is refused is a pose that barely
	# moves: fewer than half the parts different means the two are the same picture with a detail
	# changed.
	var pose_pairs: Array = [["stand", "crouch"], ["stand", "prone"], ["crouch", "prone"]]
	for pair in pose_pairs:
		var a: String = String((pair as Array)[0])
		var b: String = String((pair as Array)[1])
		var moved: int = 0
		for part in SimCondition.PART_ORDER:
			var pa: PackedByteArray = digests.get(Appearance.chart_key(String(part), a), PackedByteArray()) as PackedByteArray
			var pb: PackedByteArray = digests.get(Appearance.chart_key(String(part), b), PackedByteArray()) as PackedByteArray
			if pa.is_empty() or pb.is_empty():
				push_error("%s or %s of %s decoded to no bytes, so this comparison is judging nothing" % [a, b, String(part)])
				return false
			if pa != pb:
				moved += 1
		if moved * 2 < SimCondition.PART_ORDER.size():
			push_error("only %d of %d parts differ between %s and %s -- they are one pose stored twice" % [moved, SimCondition.PART_ORDER.size(), a, b])
			return false

	# And no part may be the same picture in *all three*, which would be a part the pose never
	# reaches at all -- ten files of it where one would do.
	var same: Array[String] = []
	for part in SimCondition.PART_ORDER:
		var stand: PackedByteArray = digests.get(Appearance.chart_key(String(part), "stand"), PackedByteArray()) as PackedByteArray
		var crouch: PackedByteArray = digests.get(Appearance.chart_key(String(part), "crouch"), PackedByteArray()) as PackedByteArray
		var prone: PackedByteArray = digests.get(Appearance.chart_key(String(part), "prone"), PackedByteArray()) as PackedByteArray
		if stand.is_empty() or crouch.is_empty() or prone.is_empty():
			push_error("a pose of %s decoded to no bytes, so this comparison is judging nothing" % String(part))
			return false
		if stand == crouch and stand == prone:
			same.append(String(part))
	if not same.is_empty():
		push_error("%d parts are one picture in all three poses: %s" % [same.size(), ", ".join(same)])
		return false

	# And the parts have to be different *parts*: a left arm and a right arm that occupy the same
	# rect are one picture drawn twice, and a wound mark would land in the wrong place for one of
	# them for ever.
	var left: Rect2i = rects[Appearance.chart_key("arm_left", "stand")] as Rect2i
	var right: Rect2i = rects[Appearance.chart_key("arm_right", "stand")] as Rect2i
	if left.position.x == right.position.x:
		push_error("the left and right arms start at the same column, so the chart has no sides")
		return false
	var head: Rect2i = rects[Appearance.chart_key("head", "stand")] as Rect2i
	var foot: Rect2i = rects[Appearance.chart_key("foot_left", "stand")] as Rect2i
	if head.position.y >= foot.position.y:
		push_error("the head is not above the feet on the chart canvas")
		return false

	# `chart_rect` is what the wound marks hang on, and it must agree with the picture rather than
	# with a table -- the whole reason it is read off the image.
	var reported: Rect2 = Appearance.chart_rect(Appearance.chart_key("head", "stand"))
	if not Rect2(head).is_equal_approx(reported):
		push_error("chart_rect reported %s for the head where the picture uses %s" % [str(reported), str(Rect2(head))])
		return false
	if not Appearance.chart_rect("chart_no_such_part_stand").size.is_equal_approx(Vector2(Appearance.CHART_CANVAS)):
		push_error("chart_rect on an unknown key should fall back to the whole canvas")
		return false

	# The dead-socket half: something draws them, tints them by state, and the capsule figure this
	# replaced is gone rather than left beside it.
	var doll: String = FileAccess.get_file_as_string("res://ui/paperdoll.gd")
	for needed in ["Appearance.chart_key", "Appearance.resolve", "draw_texture_rect", "CONDITION_TINTS", "chart_rect"]:
		if doll.find(needed) < 0:
			push_error("ui/paperdoll.gd never mentions %s, so the chart is drawn by nothing or tinted by nothing" % needed)
			return false
	for gone in ["_tapered", "draw_colored_polygon", "const P: Dictionary"]:
		if doll.find(gone) >= 0:
			push_error("ui/paperdoll.gd still carries the drawn figure's %s beside the chart" % gone)
			return false
	print("CHART OK %d parts x %d poses on the %dx%d canvas, every one a mask above %.2f, no two poses the same picture, sides distinct, and ui/paperdoll.gd draws and tints them" % [SimCondition.PART_ORDER.size(), Appearance.CHART_POSES.size(), Appearance.CHART_CANVAS.x, Appearance.CHART_CANVAS.y, CHART_MASK_FLOOR])
	return true
