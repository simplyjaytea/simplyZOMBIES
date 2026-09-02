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
	ok = _colonists_are_tinted_grey() and ok
	ok = _art_is_not_modulated_by_a_role_colour() and ok
	ok = _equipped_gear_layers_resolve() and ok
	ok = _props_look_like_something() and ok
	if ok:
		print("APPEARANCE_OK schema keys resolve, fallback intact, the player has a body, the roster resolves shared and distinct rigs, colonists compose grey x tint over the ground")
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

# The shape the schemas document but the validator cannot reach.
func _declared_appearances_are_well_formed() -> bool:
	var allowed: Array[String] = ["sprite", "tint", "features", "portrait", "equipSprite", "equipSpriteFront", "shape", "size"]
	var hex := RegEx.new(); hex.compile(HEX)
	var key := RegEx.new(); key.compile(KEY)
	var blocks: Dictionary = _all_blocks()
	for path in blocks.keys():
		var block: Dictionary = blocks[path]
		for k in block.keys():
			if not allowed.has(String(k)):
				push_error("%s: appearance has unknown key '%s'; allowed %s" % [path, k, allowed])
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
			# One canvas: ART_NATIVE square, centre-anchored (assets/sprites/README.md), and the
			# size is read off camera.gd rather than carried here -- the 64 -> 32 move of
			# 2026-09-02 is what a second copy of the number would have drifted from. A stray
			# sprite authored to the dead 64x96 feet-anchored convention would float half a
			# tile high without ever erroring, so the shape is a build failure, not a footnote.
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
	# The table must have been read for real: the atlas is the shape it exists for, and a lane
	# that only ever saw tiles would pass a table nobody consults.
	if atlases == 0:
		push_error("no file in %s is on a non-tile canvas -- Appearance.canvas_of was never exercised" % SPRITE_DIR)
		return false
	if Appearance.canvas_of("no_such_key") != Vector2i(native, native):
		push_error("canvas_of does not default an unknown key to the %dx%d tile" % [native, native])
		return false
	print("CANVAS OK %d files, %d of them on a table canvas, every one at its Appearance.canvas_of size (tile %dx%d)" % [judged, atlases, native, native])
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
	{"id": "player.body", "kind": "player", "probe": {"player": true}, "colonist": false},
	{"id": "survivor.unique.mara", "kind": "survivor", "probe": {"unique": true, "cid": "survivor.unique.mara"}, "colonist": false},
	{"id": "survivor.unique.ellis", "kind": "survivor", "probe": {"unique": true, "cid": "survivor.unique.ellis"}, "colonist": false},
	{"id": "colony.look.01", "kind": "survivor", "probe": {"unique": true, "cid": "colony.look.01"}, "colonist": true},
	{"id": "colony.look.02", "kind": "survivor", "probe": {"unique": true, "cid": "colony.look.02"}, "colonist": true},
	{"id": "colony.look.03", "kind": "survivor", "probe": {"unique": true, "cid": "colony.look.03"}, "colonist": true},
	{"id": "colony.look.04", "kind": "survivor", "probe": {"unique": true, "cid": "colony.look.04"}, "colonist": true},
	{"id": "colony.look.05", "kind": "survivor", "probe": {"unique": true, "cid": "colony.look.05"}, "colonist": true},
	{"id": "colony.look.06", "kind": "survivor", "probe": {"unique": true, "cid": "colony.look.06"}, "colonist": true},
	{"id": "zombie.shambler", "kind": "zombie", "probe": {"ztype": "zombie.shambler"}, "colonist": false},
	{"id": "zombie.screamer", "kind": "zombie", "probe": {"ztype": "zombie.screamer"}, "colonist": false},
	{"id": "zombie.bloater", "kind": "zombie", "probe": {"ztype": "zombie.bloater"}, "colonist": false},
	{"id": "raider.scav", "kind": "raider", "probe": {"raider": true, "cid": "raider.scav"}, "colonist": false},
	{"id": "raider.gunhand", "kind": "raider", "probe": {"raider": true, "cid": "raider.gunhand"}, "colonist": false},
]

# zombie.base spawns nowhere and gets no art -- it is the `extends` parent the wave types
# inherit stats (never looks) from, and the roadmap record says so.
const ROSTER_EXEMPT: Array[String] = ["zombie.base"]

# Where roster ids live. colony/ also holds the generator and the skill web, which are not
# bodies, so the colony entry names the one file rather than the directory.
const ROSTER_DIRS: Array[String] = ["players/", "zombies/", "survivors/uniques/", "raiders/", "colony/looks.json"]

# Ids that deliberately resolve one shared texture: six colonists are one rig (the tint is
# the identity), and every raider archetype is one body (which raider carries the gun is not
# something a look across a street may answer -- check_m2_raiders.gd asserts the same thing
# from the content side).
const ROSTER_SHARED: Array = [
	["colony.look.01", "colony.look.02", "colony.look.03", "colony.look.04", "colony.look.05", "colony.look.06"],
	["raider.scav", "raider.gunhand"],
]

# One id per distinct picture; every pair must resolve different textures.
const ROSTER_DISTINCT: Array[String] = [
	"player.body", "survivor.unique.mara", "survivor.unique.ellis", "colony.look.01",
	"zombie.shambler", "zombie.screamer", "zombie.bloater", "raider.scav",
]


# Every body resolves generated art through the resolver the draw loop asks, tinted exactly
# as content declared: white for art with no tint, the looks.json tint for a colonist. The
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
		if bool(row["colonist"]):
			var block: Dictionary = Appearance.of_content(w, String(row["kind"]), id)
			if not block.has("tint"):
				push_error("%s declares no tint beside its sprite; six colonists with no tints are six identical grey people" % id)
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


func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


# On sRGB byte values, because that is what the achromatic bound is about: the outline
# #161614 is (22, 22, 20), channel delta exactly 2, and it must stay inside the bound after
# the shade pass multiplies it -- which is why _figure in the sprite package outlines last.
func _is_achromatic(c: Color) -> bool:
	var r: int = int(round(c.r * 255.0))
	var g: int = int(round(c.g * 255.0))
	var b: int = int(round(c.b * 255.0))
	return maxi(absi(r - g), absi(g - b)) <= 2


# Whether a grey of this luminance, multiplied by this tint, still reads against the
# brightest ground the district can draw. The threshold reads the real palette, never a
# copied number. This models the modulate as a per-channel multiply on sRGB values with
# Rec. 709 luma and no linearisation -- which is what Godot's 2D Compatibility path does
# and what tools/sprites/palette.py::luma already assumes. A model of the renderer, not a
# rendering; if the renderer ever changes, this is the line to revisit.
const GREY_CLEARANCE: float = 0.06

func _composed_clears(median_grey: float, tint: Color) -> bool:
	var brightest: float = 0.0
	for i in Palette.SURFACE_TINTS.size():
		brightest = maxf(brightest, _luma(Palette.SURFACE_TINTS[i]))
	return median_grey * _luma(tint) >= brightest + GREY_CLEARANCE


# The colonist rig is achromatic and the looks.json tint supplies all the colour -- the one
# legitimate grayscale-to-tint case on the roster. Because the rig is achromatic
# (r == g == b), the modulate product's luma is exactly grey x luma(tint), which is what
# makes the ground-contrast guard computable here at all: palette.py's import-time guard
# cannot see the composition, so this lane is its other half and GROUND_FACING's comment
# names it. check_m2_recruits.gd independently pins that every rolled look declares a tint;
# this lane pins the pairing and the arithmetic.
func _colonists_are_tinted_grey() -> bool:
	Appearance.forget()
	var w: Variant = World.new(_fixture())
	var hex := RegEx.new()
	hex.compile(HEX)
	var tints: Array[Color] = []
	for n in range(1, 7):
		var id: String = "colony.look.%02d" % n
		var block: Dictionary = Appearance.of_content(w, "survivor", id)
		if String(block.get("sprite", "")) != "survivor_colonist":
			push_error("%s does not declare sprite 'survivor_colonist'; the composition needs both halves" % id)
			return false
		var t: Variant = block.get("tint")
		if not (t is String) or hex.search(String(t)) == null:
			push_error("%s tint '%s' is not #rrggbb lowercase" % [id, str(t)])
			return false
		tints.append(Color(String(t)))
	if tints.size() != 6:
		push_error("expected 6 colony looks, judged %d" % tints.size())
		return false

	var tex: Variant = Appearance.resolve("survivor_colonist")
	if tex == null:
		push_error("survivor_colonist resolved no texture")
		return false
	var img: Image = (tex as Texture2D).get_image()
	var lumas: Array[float] = []
	var worst_delta: int = 0
	var worst_at: Vector2i = Vector2i(-1, -1)
	for y in img.get_height():
		for x in img.get_width():
			var px: Color = img.get_pixel(x, y)
			if px.a <= 0.0:
				continue
			if not _is_achromatic(px):
				push_error("survivor_colonist pixel (%d,%d) is not achromatic: %s -- a coloured pixel here fights the tint instead of carrying it" % [x, y, str(px)])
				return false
			var delta: int = maxi(absi(int(round(px.r * 255.0)) - int(round(px.g * 255.0))), absi(int(round(px.g * 255.0)) - int(round(px.b * 255.0))))
			if delta > worst_delta:
				worst_delta = delta
				worst_at = Vector2i(x, y)
			lumas.append(_luma(px))
	if lumas.is_empty():
		push_error("survivor_colonist has no opaque pixels -- the achromatic assertion had nothing to judge")
		return false
	lumas.sort()
	var median: float = lumas[lumas.size() / 2]
	var brightest: float = 0.0
	for i in Palette.SURFACE_TINTS.size():
		brightest = maxf(brightest, _luma(Palette.SURFACE_TINTS[i]))
	var tightest: float = 1.0
	for tint in tints:
		if not _composed_clears(median, tint):
			push_error("median grey %.4f x tint %s luma %.4f = %.4f, under the ground threshold %.4f -- that colonist is a silhouette on undergrowth" % [median, str(tint), _luma(tint), median * _luma(tint), brightest + GREY_CLEARANCE])
			return false
		tightest = minf(tightest, median * _luma(tint) - (brightest + GREY_CLEARANCE))

	# True negatives, through the same predicates the shipped data just passed. The brown is
	# colony.look.03's retired tint: the regrade exists because the composition failed on it.
	if _composed_clears(median, Color("#5c4632")):
		push_error("the retired #5c4632 clears the composed-luminance guard; the predicate reads nothing")
		return false
	if _is_achromatic(Color(0.6, 0.5, 0.4)):
		push_error("_is_achromatic accepted a colour 25 bytes off grey; the bound reads nothing")
		return false
	# And on real data: Mara's rig is painted in colour, so if every one of her opaque pixels
	# passes the achromatic bound, the bound is not measuring what it claims to.
	var mara_tex: Variant = Appearance.resolve("survivor_mara")
	if mara_tex == null:
		push_error("survivor_mara resolved no texture for the achromatic negative")
		return false
	var mara_img: Image = (mara_tex as Texture2D).get_image()
	var coloured: int = 0
	for y2 in mara_img.get_height():
		for x2 in mara_img.get_width():
			var px2: Color = mara_img.get_pixel(x2, y2)
			if px2.a > 0.0 and not _is_achromatic(px2):
				coloured += 1
	if coloured == 0:
		push_error("every opaque pixel of survivor_mara passed the achromatic bound; a check Mara's art satisfies reads nothing")
		return false
	Appearance.forget()
	print("GREY OK %d opaque px, worst delta %d at %s, median %.4f, threshold %.4f, tightest margin +%.3f, retired brown refused, %d coloured px on mara" % [lumas.size(), worst_delta, str(worst_at), median, brightest + GREY_CLEARANCE, tightest, coloured])
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

# Equipped-gear layers: a rendered slot holding an item with equipSprite must actually resolve
# a texture (the true positives item.bat.aluminium and item.pack.hiking exist for, one over-body
# and one under); an item with no equipSprite, an item in a slot the renderer does not draw, and
# an entity with no equipment component at all (every zombie) must all fall out silently rather
# than erroring -- each is its own assertion so a regression in any one path fails here instead
# of drawing nothing, or the wrong thing, on screen.
func _equipped_gear_layers_resolve() -> bool:
	Appearance.forget()
	var w: Variant = World.new(_fixture())
	var actor: int = int(w.entities.spawn())
	var bat: int = int(w.entities.spawn())
	var pack: int = int(w.entities.spawn())
	var knife: int = int(w.entities.spawn())
	w.components.set_component(bat, "itemBase", {"baseId": "item.bat.aluminium"})
	w.components.set_component(pack, "itemBase", {"baseId": "item.pack.hiking"})
	w.components.set_component(knife, "itemBase", {"baseId": "item.knife.kitchen"})

	w.components.set_component(actor, "equipment", {"slots": {"primary": bat}})
	var layers: Array[Dictionary] = Appearance.equipment_layers_for(w, actor)
	if layers.size() != 1 or layers[0].get("texture") == null or not bool(layers[0].get("over", false)):
		push_error("primary slot holding item.bat.aluminium should yield one over-body layer with a texture, got %s" % str(layers))
		return false

	# item.pack.hiking declares both equipSprite (the pack body, under) and equipSpriteFront
	# (the straps crossing the chest, always over regardless of the back slot's own default) --
	# one equipped item, two layers, split correctly.
	w.components.set_component(actor, "equipment", {"slots": {"back": pack}})
	layers = Appearance.equipment_layers_for(w, actor)
	if layers.size() != 2 or layers[0].get("texture") == null or bool(layers[0].get("over", true)) \
			or layers[1].get("texture") == null or not bool(layers[1].get("over", false)):
		push_error("back slot holding item.pack.hiking should yield an under-body pack layer then an over-body strap layer, got %s" % str(layers))
		return false

	# Both a worn pack and a held weapon at once is the actual shipped case: three layers,
	# correctly ordered under-then-over, not one clobbering another.
	w.components.set_component(actor, "equipment", {"slots": {"back": pack, "primary": bat}})
	layers = Appearance.equipment_layers_for(w, actor)
	if layers.size() != 3 or bool(layers[0].get("over", true)) or not bool(layers[1].get("over", false)) \
			or not bool(layers[2].get("over", false)):
		push_error("back+primary together should yield three layers (pack under, pack straps over, bat over), got %s" % str(layers))
		return false

	w.components.set_component(actor, "equipment", {"slots": {"primary": knife}})
	if not Appearance.equipment_layers_for(w, actor).is_empty():
		push_error("item.knife.kitchen declares no equipSprite; equipping it should yield no layer")
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
