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
const ItemPicture = preload("res://ui/item_picture.gd")
const SimCondition = preload("res://sim/condition.gd")
const SimContainers = preload("res://sim/modules/containers.gd")
const SimLight = preload("res://sim/modules/light.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")

const SPRITE_DIR: String = "res://assets/sprites"
const HEX := "^#[0-9a-f]{6}$"
const KEY := "^[a-z0-9_.]+$"

# The whole interface `Appearance.standing_props` asks an observer for: has_tile(tx, ty). A plain
# dictionary of tiles standing in for SimVisibility, the FakeSeen convention check_trees.gd uses.
class FakeSeen extends RefCounted:
	var tiles: Dictionary = {}

	func has_tile(tx: int, ty: int) -> bool:
		return tiles.has(Vector2i(tx, ty))


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
	ok = _container_kinds_follow_the_loot_table() and ok
	ok = _standing_props_come_from_the_pack() and ok
	ok = _items_look_like_something() and ok
	ok = _item_pictures_are_real_and_drawn() and ok
	ok = _the_body_chart_is_ten_parts_in_three_poses() and ok
	if ok:
		print("APPEARANCE_OK schema keys resolve, fallback intact, the player has a body, the roster resolves shared and distinct rigs, colonists wear the pack body with six tints, containers draw the kind their loot table names, the barricade and the work lamp are the pack's standing pictures, items resolve art or a class glyph, the pack's item pictures are declared, gated and drawn on the floor and the bag plate, the body chart is ten parts in three poses")
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
# item's `appearance` -- equipSprite and all -- was invisible to the shape and
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
# validator cannot see (it checks top-level types only). `variants` is legal for vehicles and
# zombies only. A vehicle's {id, ns, ew} shape is check_wrecks.gd's DRESSING lane; a zombie's
# {sprite, corpseSprites} pair is checked here. `corpseSprites` lives on a zombie or the player
# body (the shared human fallback), never on an item, prop or vehicle.
func _appearance_key_ok(k: String, path: String) -> bool:
	if ["sprite", "tint", "features", "portrait", "equipSprite", "shape", "size"].has(k):
		return true
	# `equipSpriteFront`, `attachmentSprite` and `partAnchors` were legal on an item until
	# 2026-09-26: a face-on back item's front strap, a fitted part's picture and the host weapon's
	# anchors for it. All three drew face-on pictures that "Pack gear on the body" retired (docs/30,
	# "The whole outpost pack"), so all three are refused now, everywhere -- a key nothing reads.
	# The effect fields ("The shot is seen", 2026-09-26) are each legal on the one kind that fires,
	# bleeds or burns them: a weapon's flash and casing on an item, a body's blood on a zombie, a
	# raider, the player, a survivor or a colony look, a fire's flame on a prop. Anywhere else one
	# would name a sheet nothing plays -- presentation/fx_look.gd reads each from its own kind only.
	if EFFECT_KINDS.has(k):
		for prefix in EFFECT_KINDS[k] as Array:
			if path.begins_with(String(prefix)):
				return true
		return false
	if k == "corpseSprites":
		return path.begins_with("zombies/") or path.begins_with("players/")
	return k == "variants" and (path.begins_with("vehicles/") or path.begins_with("zombies/"))


const EFFECT_KINDS: Dictionary = {
	"fireFx": ["items/"],
	"casingFx": ["items/"],
	"hitFx": ["zombies/", "raiders/", "players/", "survivors/", "colony/looks"],
	"flameFx": ["props/"],
}


# The shape the schemas document but the validator cannot reach.
func _declared_appearances_are_well_formed() -> bool:
	var hex := RegEx.new(); hex.compile(HEX)
	var key := RegEx.new(); key.compile(KEY)
	# The two variant shapes have real readers; no other kind accepts the exception.
	for allowed in ["vehicles/sedan.json#vehicle.sedan", "zombies/shambler.json#zombie.shambler"]:
		if not _appearance_key_ok("variants", allowed):
			push_error("the appearance allowlist refuses 'variants' on %s" % allowed)
			return false
	for denied in ["players/player.json#player.body", "items/ranged.json#item.pistol.service", "props/stations.json#prop.campfire", "raiders/scav.json#raider.scav", "survivors/uniques/mara.json#survivor.unique.mara", "colony/looks.json#colony.look.01"]:
		if _appearance_key_ok("variants", denied):
			push_error("the appearance allowlist accepts 'variants' outside vehicles and zombies: %s" % denied)
			return false
	for allowed in ["players/player.json#player.body", "zombies/shambler.json#zombie.shambler"]:
		if not _appearance_key_ok("corpseSprites", allowed):
			push_error("the appearance allowlist refuses 'corpseSprites' on %s" % allowed)
			return false
	for denied in ["vehicles/sedan.json#vehicle.sedan", "items/clothing.json#item.jacket", "props/stations.json#prop.bed", "raiders/scav.json#raider.scav", "survivors/uniques/mara.json#survivor.unique.mara", "colony/looks.json#colony.look.01"]:
		if _appearance_key_ok("corpseSprites", denied):
			push_error("the appearance allowlist accepts 'corpseSprites' outside players and zombies: %s" % denied)
			return false
	for path in ["vehicles/sedan.json#vehicle.sedan", "zombies/shambler.json#zombie.shambler"]:
		if _appearance_key_ok("sprrite", path):
			push_error("the appearance allowlist accepts a misspelled key on %s; the exception widened the whole list" % path)
			return false
	if not _nested_body_shapes_reject_bad_data():
		return false
	# The three retired keys are refused on the one kind that used to carry them, and the one that
	# stayed is still accepted there -- so the refusal is the retirement, not a broken list.
	for retired in ["equipSpriteFront", "attachmentSprite", "partAnchors"]:
		if _appearance_key_ok(retired, "items/ranged.json#item.pistol.service"):
			push_error("the appearance allowlist still accepts the retired '%s' on an item; it draws nothing since 2026-09-26" % retired)
			return false
	if not _appearance_key_ok("equipSprite", "items/ranged.json#item.pistol.service"):
		push_error("the appearance allowlist refuses 'equipSprite' on an item, which is where a held weapon is named")
		return false
	# Each effect field on its own kind, and refused on another.
	for pair in [["fireFx", "items/ranged.json#item.pistol.service", "zombies/shambler.json#zombie.shambler"],
			["hitFx", "zombies/shambler.json#zombie.shambler", "items/ranged.json#item.pistol.service"],
			["flameFx", "props/stations.json#prop.campfire.lit", "players/player.json#player.body"]]:
		if not _appearance_key_ok(String(pair[0]), String(pair[1])) or _appearance_key_ok(String(pair[0]), String(pair[2])):
			push_error("the appearance allowlist does not hold '%s' to %s alone (refused there, or accepted on %s)" % pair)
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
		for prop in ["equipSprite", "fireFx", "casingFx", "hitFx", "flameFx"]:
			if block.has(prop):
				var es: Variant = block[prop]
				if not (es is String) or key.search(String(es)) == null:
					push_error("%s: appearance.%s '%s' is not a registry key (a key, not a path)" % [path, prop, str(es)])
					return false
		if block.has("corpseSprites"):
			var corpse_problem: String = _corpse_sprites_complaint(block["corpseSprites"])
			if not corpse_problem.is_empty():
				push_error("%s: appearance.corpseSprites %s" % [path, corpse_problem])
				return false
		if block.has("variants") and String(path).begins_with("zombies/"):
			var variant_problem: String = _zombie_variants_complaint(block["variants"])
			if not variant_problem.is_empty():
				push_error("%s: appearance.variants %s" % [path, variant_problem])
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
			if not (sz is float or sz is int) or float(sz) < 0.1 or float(sz) > Appearance.PROP_SIZE_MAX:
				push_error("%s: appearance.size '%s' is not a tile fraction in [0.1, %.1f]" % [path, str(sz), Appearance.PROP_SIZE_MAX])
				return false
	print("SHAPE OK %d blocks" % blocks.size())
	return true

# These mirror the nested schemas, including bounds and duplicate corpse keys. They return a
# complaint rather than logging so the exact same predicate can judge deliberately broken data.
func _corpse_sprites_complaint(raw: Variant) -> String:
	if not (raw is Array):
		return "must be an array"
	var poses: Array = raw as Array
	if poses.is_empty() or poses.size() > 8:
		return "must contain between 1 and 8 keys"
	var pattern := RegEx.new(); pattern.compile("^corpse_[a-z0-9_]+$")
	var seen: Dictionary = {}
	for pose in poses:
		if not (pose is String) or pattern.search(String(pose)) == null:
			return "contains a non-corpse registry key"
		if seen.has(pose):
			return "contains a duplicate key"
		seen[pose] = true
	return ""


func _zombie_variants_complaint(raw: Variant) -> String:
	if not (raw is Array):
		return "must be an array"
	var variants: Array = raw as Array
	if variants.is_empty() or variants.size() > 16:
		return "must contain between 1 and 16 records"
	var pattern := RegEx.new(); pattern.compile("^body_[a-z0-9_]+$")
	for entry in variants:
		if not (entry is Dictionary):
			return "contains a non-object record"
		var variant: Dictionary = entry as Dictionary
		if not variant.has("sprite") or not variant.has("corpseSprites") or variant.size() != 2:
			return "each record must contain only sprite and corpseSprites"
		if not (variant["sprite"] is String) or pattern.search(String(variant["sprite"])) == null:
			return "contains a non-body sprite key"
		var corpse_problem: String = _corpse_sprites_complaint(variant["corpseSprites"])
		if not corpse_problem.is_empty():
			return "corpseSprites " + corpse_problem
	return ""


func _nested_body_shapes_reject_bad_data() -> bool:
	var poses: Array = ["corpse_probe_supine", "corpse_probe_prone"]
	var variant: Dictionary = {"sprite": "body_probe", "corpseSprites": poses}
	if not _corpse_sprites_complaint(poses).is_empty() or not _zombie_variants_complaint([variant]).is_empty():
		push_error("the body shape predicates refuse valid registry keys")
		return false
	var too_many_poses: Array = []
	for i in 9:
		too_many_poses.append("corpse_probe_%d" % i)
	for bad in [null, {}, "corpse_probe", [], [1], ["body_probe"], ["corpse_bad/path"], ["corpse_probe", "corpse_probe"], too_many_poses]:
		if _corpse_sprites_complaint(bad).is_empty():
			push_error("the corpse shape predicate accepts malformed data: %s" % str(bad))
			return false
	var too_many_variants: Array = []
	for i in 17:
		too_many_variants.append(variant)
	for bad in [null, {}, [], ["body_probe"], [{}], [{"sprite": "body_probe"}], [{"corpseSprites": poses}], [{"sprite": "body_probe", "corpseSprites": poses, "tint": "#ffffff"}], [{"sprite": 1, "corpseSprites": poses}], [{"sprite": "item_probe", "corpseSprites": poses}], [{"sprite": "body_probe", "corpseSprites": []}], too_many_variants]:
		if _zombie_variants_complaint(bad).is_empty():
			push_error("the zombie variant predicate accepts malformed data: %s" % str(bad))
			return false
	if _zombie_variants_complaint([{"id": "probe", "ns": "vehicle_probe_ns", "ew": "vehicle_probe_ew"}]).is_empty():
		push_error("a vehicle variant passed the zombie shape predicate")
		return false
	# A nested declaration must reach KEYS as well as SHAPE: otherwise a correctly spelled key
	# naming absent art would be invisible to the old top-level-only resolution loop.
	var body: Dictionary = {"sprite": "body_probe", "corpseSprites": poses, "variants": [variant]}
	var expected: Dictionary = {
		"sprite": "body_probe", "corpseSprites[0]": poses[0], "corpseSprites[1]": poses[1],
		"variants[0].sprite": "body_probe", "variants[0].corpseSprites[0]": poses[0],
		"variants[0].corpseSprites[1]": poses[1],
	}
	if _declared_sprite_keys(body, true) != expected:
		push_error("the sprite-key walk dropped a living or corpse variant declaration")
		return false
	if _declared_sprite_keys(body, false).has("variants[0].sprite") or not _declared_sprite_keys({}, true).is_empty():
		push_error("the sprite-key walk invents nested zombie keys outside a zombie or on an empty block")
		return false
	return true


# Flatten only sprite-bearing fields, retaining their full content path for useful failures.
# Vehicle variants use another shape, resolved by check_wrecks rather than guessed at here.
func _declared_sprite_keys(block: Dictionary, zombie: bool) -> Dictionary:
	var keys: Dictionary = {}
	for prop in ["sprite", "equipSprite"]:
		if block.has(prop):
			keys[prop] = block[prop]
	var poses: Variant = block.get("corpseSprites", [])
	if poses is Array:
		for i in (poses as Array).size():
			keys["corpseSprites[%d]" % i] = (poses as Array)[i]
	var variants: Variant = block.get("variants", [])
	if zombie and variants is Array:
		for i in (variants as Array).size():
			var variant: Variant = (variants as Array)[i]
			if not (variant is Dictionary):
				continue
			var nested: Dictionary = _declared_sprite_keys(variant as Dictionary, false)
			for prop in nested.keys():
				keys["variants[%d].%s" % [i, prop]] = nested[prop]
	return keys


# A key naming a file that does not exist must fail the build, not draw nothing.
func _sprite_keys_resolve() -> bool:
	var native: int = int(CameraUtil.ART_NATIVE)
	var resolved: int = 0
	var blocks: Dictionary = _all_blocks()
	for path in blocks.keys():
		var block: Dictionary = blocks[path]
		var declared: Dictionary = _declared_sprite_keys(block, String(path).begins_with("zombies/"))
		for prop in declared.keys():
			var k: String = String(declared[prop])
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
	# Each special kind now has its own body. Per-body variance tints arrive on the draw item
	# (check_m2_variance.gd READER), separate from the untinted authored pictures judged here.
	{"id": "zombie.stalker", "kind": "zombie", "probe": {"ztype": "zombie.stalker"}, "tinted": false},
	{"id": "zombie.runner", "kind": "zombie", "probe": {"ztype": "zombie.runner"}, "tinted": false},
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
const ROSTER_SHARED: Array = [
	[
		"player.body", "survivor.unique.mara", "survivor.unique.ellis",
		"colony.look.01", "colony.look.02", "colony.look.03", "colony.look.04", "colony.look.05", "colony.look.06",
		"raider.scav", "raider.gunhand", "raider.looter", "raider.lookout",
		"raider.look.01", "raider.look.02", "raider.look.03", "raider.look.04",
	],
]

# One id per distinct picture; every pair must resolve different textures. Each special zombie
# has a separate family now; the ordinary shambler's three cosmetic variants are checked by
# check_zombie_art, while the default member joins this cross-roster comparison.
const ROSTER_DISTINCT: Array[String] = [
	"player.body", "zombie.shambler", "zombie.screamer", "zombie.bloater",
	"zombie.stalker", "zombie.runner", "zombie.armored", "zombie.heavy",
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
# red on the art itself. "The ground is the pack's" (docs/23, 2026-09-27) was named here as the
# slice that would re-pin that contrast, and it did not re-pin a luma bound: the ground is the
# pack's own table now, the body is the pack's own survivor, and the pack reads a body off its
# ground by its near-black outline rather than by a luma gap -- the "geometry gated, colour not"
# rule docs/30's "The outpost pack, adopted" set for pack art, applied to the pair. What survives here is
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
# a texture (the true positives item.knife.kitchen and item.pack.hiking exist for: a pack held
# weapon, over the body seen from the front, and a pack backpack, over seen from the front and under
# seen from the side -- per-view layering in full is check_worn.gd's TURNS and HELD lanes); an item
# with no equipSprite (NO_ART_BASE, whose art-lessness the lane verifies first), an item in a slot
# the renderer does not draw, and an entity with no equipment component at all (every zombie) must
# all fall out silently rather than erroring -- each is its own assertion so a regression in any
# one path fails here instead of drawing nothing, or the wrong thing, on screen. (The bat and the
# duffel stood here until 2026-09-26; their face-on pictures were retired with "Pack gear on the
# body", so they now draw nothing and are the wrong subjects for a true positive.)
func _equipped_gear_layers_resolve() -> bool:
	Appearance.forget()
	var w: Variant = World.new(_fixture())
	var actor: int = int(w.entities.spawn())
	var bat: int = int(w.entities.spawn())
	var pack: int = int(w.entities.spawn())
	var bare: int = int(w.entities.spawn())
	w.components.set_component(bat, "itemBase", {"baseId": "item.knife.kitchen"})
	w.components.set_component(pack, "itemBase", {"baseId": "item.pack.hiking"})
	w.components.set_component(bare, "itemBase", {"baseId": NO_ART_BASE})

	w.components.set_component(actor, "equipment", {"slots": {"primary": bat}})
	var layers: Array[Dictionary] = Appearance.equipment_layers_for(w, actor)
	if layers.size() != 1 or layers[0].get("texture") == null or not bool(layers[0].get("over", false)):
		push_error("primary slot holding item.knife.kitchen should yield one over-body layer with a texture, got %s" % str(layers))
		return false

	# item.pack.hiking wears the pack's backpack: over the body seen from the front, under it seen
	# from the side -- one equipped item, its side decided per view.
	w.components.set_component(actor, "equipment", {"slots": {"back": pack}})
	layers = Appearance.equipment_layers_for(w, actor)
	var side: Array[Dictionary] = Appearance.equipment_layers_for(w, actor, "e")
	if layers.size() != 1 or layers[0].get("texture") == null or not bool(layers[0].get("over", false)) \
			or side.size() != 1 or side[0].get("texture") == null or bool(side[0].get("over", true)):
		push_error("back slot holding item.pack.hiking should yield one layer over seen from the front and under seen from the east, got %s and %s" % [str(layers), str(side)])
		return false

	# Both a worn pack and a held weapon at once, seen from the east: two layers, the pack under
	# and the knife over, not one clobbering another.
	w.components.set_component(actor, "equipment", {"slots": {"back": pack, "primary": bat}})
	layers = Appearance.equipment_layers_for(w, actor, "e")
	if layers.size() != 2 or bool(layers[0].get("over", true)) or not bool(layers[1].get("over", false)):
		push_error("back+primary together seen from the east should yield two layers (pack under, knife over), got %s" % str(layers))
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
		if kind.has("lit_id"):
			ids.append(String(kind["lit_id"]))
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
		if float(look["size"]) < 0.1 or float(look["size"]) > Appearance.PROP_SIZE_MAX:
			push_error("%s resolved size %f, outside [0.1, %.1f] tiles" % [id, float(look["size"]), Appearance.PROP_SIZE_MAX])
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
	for pair in [["prop.container", "prop.container.searched"], ["prop.campfire", "prop.campfire.lit"], ["prop.lamp", "prop.lamp.dark"]]:
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
	# Where a prop's picture goes. A tile-square canvas (the crate, the fire, the well, the latrine)
	# is centred on the point, the rect it has always had; the pack's bed is 48x30, cropped to its
	# anchor row, so it hangs by `Appearance.hang_rect` with its last row on the tile's south edge
	# and is wider than the tile it lies on. hang_rect is judged on the bed's own picture at every
	# zoom rung, and refused for the rect a body would take, which drops FOOT_DROP_PX below it.
	var bed_look: Dictionary = Appearance.prop_of(w, "prop.bed")
	var bed_tex: Variant = bed_look["texture"]
	if bed_tex == null:
		push_error("prop.bed resolved no texture; the hang assertions had nothing to judge")
		return false
	var bed_px: Vector2i = Vector2i((bed_tex as Texture2D).get_size())
	if Appearance.anchor_of(bed_px) != Appearance.Anchor.Feet or bed_px.x <= int(CameraUtil.ART_NATIVE):
		push_error("the bed is %s; the pack's bed is wider than a tile and not square, so it hangs and does not centre" % str(bed_px))
		return false
	for zoom in CameraUtil.ZOOM_STEPS:
		var scale: float = Appearance.blit_scale(zoom)
		var size: Vector2 = Vector2(bed_px) * scale
		var hung: Rect2 = Appearance.hang_rect(200.0, 300.0, size)
		if hung.position.y + hung.size.y != 300.0:
			push_error("zoom %.0f: a hung prop's last row is at %.2f, want the tile's south edge 300.0" % [zoom, hung.position.y + hung.size.y])
			return false
		if hung.size != size or absf(hung.position.x + hung.size.x / 2.0 - 200.0) > 0.5:
			push_error("zoom %.0f: a hung prop is %s at x %.2f, want %s centred on 200.0" % [zoom, str(hung.size), hung.position.x, str(size)])
			return false
		var stood: Rect2 = Appearance.body_rect(200.0, 300.0, size, 1.0)
		if stood.position.y + stood.size.y == 300.0:
			push_error("zoom %.0f: body_rect and hang_rect agree on the bottom; the FOOT_DROP_PX negative is dead" % zoom)
			return false
	for square_id in ["prop.container", "prop.campfire", "prop.well", "prop.latrine"]:
		var sq: Variant = Appearance.prop_of(w, square_id)["texture"]
		if sq == null or Appearance.anchor_of(Vector2i((sq as Texture2D).get_size())) != Appearance.Anchor.Centre:
			push_error("%s is not a tile-square picture; _draw_prop would hang it instead of centring it" % square_id)
			return false

	print("PROPS OK %d ids, %d with art drawn unstained at their declared footprint (up to %.1f tiles across, the bed's), distinct looks, both state pairs different pictures, the bed hangs on the tile's south edge at every zoom rung and the square props centre, unknown id degrades" % [ids.size(), textured, Appearance.PROP_SIZE_MAX])
	return true


# --- CONTAINERS ---------------------------------------------------------------------------

# What each shipped loot table's containers draw as -- docs/23, "Furnishings and container kinds":
# the pack's wood crate for a house or a shop, its metal footlocker for a workshop or a cache, its
# medical box for a clinic. Written out here, not read back off content, so a `tables` map that lost
# an entry or gained a wrong one is seen; and so a loot table nobody has chosen a picture for is a
# red lane rather than a quiet wood crate. Two tables share the metal footlocker on purpose: the
# picture names a *kind* of container, and only the medical box names a single table (docs/01
# clause 4 -- a seen container looking like what it is is fair; a picture of a rare table alone is
# not, and the industrial and military tables are not told apart by it).
const CONTAINER_BASE_ID: String = "prop.container"
const CONTAINER_EXPECTED: Dictionary = {
	"residential": "prop.container",
	"commercial": "prop.container",
	"medical": "prop.container.medical",
	"industrial": "prop.container.metal",
	"military_cache": "prop.container.metal",
}
const LOOT_TABLES_PATH: String = "res://content/loot/tables.json"
const STATIONS_PATH: String = "res://content/props/stations.json"
const APPEARANCE_GD: String = "res://presentation/appearance.gd"
const MAIN_GD: String = "res://presentation/main.gd"


# One function's source out of a file: from its `func <name>(` line (static or not) to the next
# top-level declaration, comments taken out so a needle cannot be satisfied by prose.
func _function_source(path: String, name: String) -> String:
	var out: String = ""
	var inside: bool = false
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var text: String = String(line)
		if text.begins_with("func %s(" % name) or text.begins_with("static func %s(" % name):
			inside = true
			continue
		if inside and (text.begins_with("func ") or text.begins_with("static func ") or text.begins_with("const ") or text.begins_with("var ")):
			break
		if inside:
			var at: int = text.find("#")
			out += (text if at < 0 else text.substr(0, at)) + "\n"
	return out


# The first thing a picture-choosing function may not read, or "": what a box holds, its `items`, its
# `container` grid, the container module, or its kind word -- the sim's prose, never a picture's key.
func _reads_contents(source: String) -> String:
	for forbidden in ["contents_of(", "\"items\"", "get_component(entity, \"container\")", "get_component(entity, \"searchable\")", "SimContainers", "\"kind\""]:
		if source.contains(String(forbidden)):
			return String(forbidden)
	return ""


# The first needle a source lacks, or "".
func _lacks(source: String, needles: Array) -> String:
	for needle in needles:
		if not source.contains(String(needle)):
			return String(needle)
	return ""


# The `prop.container.*` ids in a list of content entries that no rule reaches: not the base, not a
# table's mapped id and not the searched pair of either. A picture for a container nothing ever draws
# is the dead-socket shape this milestone has paid for a dozen times.
func _unreachable_container_ids(ids: Array, tables: Dictionary) -> Array[String]:
	var reachable: Dictionary = {CONTAINER_BASE_ID: true, CONTAINER_BASE_ID + Appearance.PROP_SEARCHED_SUFFIX: true}
	for mapped in tables.values():
		reachable[String(mapped)] = true
		reachable[String(mapped) + Appearance.PROP_SEARCHED_SUFFIX] = true
	var out: Array[String] = []
	for id in ids:
		if String(id).begins_with(CONTAINER_BASE_ID) and not reachable.has(String(id)):
			out.append(String(id))
	return out


func _container_kinds_follow_the_loot_table() -> bool:
	Appearance.forget()
	var w: Variant = World.new(_fixture())
	var base: Dictionary = Appearance.entry_of(w, "prop", CONTAINER_BASE_ID)
	var tables: Variant = base.get("tables")
	if not (tables is Dictionary) or (tables as Dictionary).is_empty():
		push_error("CONTAINERS: prop.container declares no `tables` map; container kinds are keyed by nothing")
		return false

	# --- the rule, table by table ------------------------------------------------------------
	var shipped: Array[String] = []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOOT_TABLES_PATH))
	if not (parsed is Array):
		push_error("CONTAINERS: %s does not parse as a list of loot tables" % LOOT_TABLES_PATH)
		return false
	for entry in parsed as Array:
		var id: String = String((entry as Dictionary).get("id", ""))
		if id.begins_with("loot."):
			shipped.append(id.trim_prefix("loot."))
	shipped.sort()
	var expected_tables: Array = CONTAINER_EXPECTED.keys()
	expected_tables.sort()
	if shipped != expected_tables:
		push_error("CONTAINERS: the loot tables are %s and the lane names a picture for %s; a table nobody chose a container for draws the wood crate by accident" % [str(shipped), str(expected_tables)])
		return false
	for table in CONTAINER_EXPECTED.keys():
		var got_id: String = Appearance.table_prop_id(w, CONTAINER_BASE_ID, String(table))
		if got_id != String(CONTAINER_EXPECTED[table]):
			push_error("CONTAINERS: a '%s' container draws as %s, want %s" % [String(table), got_id, String(CONTAINER_EXPECTED[table])])
			return false
	# TN, each through the same function: an unknown table, an empty one, a differently cased one and
	# a prop that declares no map all answer the id they were handed.
	for stranger in ["nonsense", "", "Medical", "medical ", "loot.medical"]:
		if Appearance.table_prop_id(w, CONTAINER_BASE_ID, String(stranger)) != CONTAINER_BASE_ID:
			push_error("CONTAINERS: the table '%s' is not one and drew as %s, want the wood crate" % [String(stranger), Appearance.table_prop_id(w, CONTAINER_BASE_ID, String(stranger))])
			return false
	if Appearance.table_prop_id(w, "prop.well", "medical") != "prop.well":
		push_error("CONTAINERS: a prop with no `tables` map was re-keyed by a table")
		return false
	if Appearance.table_prop_id(null, CONTAINER_BASE_ID, "medical") != CONTAINER_BASE_ID:
		push_error("CONTAINERS: a world with no content answered a mapped id; it has nothing to map")
		return false
	# Every mapped id has both states, and the pictures are six different ones.
	var seen_pixels: Dictionary = {}
	for family in [CONTAINER_BASE_ID, "prop.container.metal", "prop.container.medical"]:
		for state in ["", Appearance.PROP_SEARCHED_SUFFIX]:
			var look_id: String = String(family) + String(state)
			var look: Dictionary = Appearance.prop_of(w, look_id)
			if look["texture"] == null:
				push_error("CONTAINERS: %s resolves no picture; a container of that kind would be invisible or the wrong one" % look_id)
				return false
			# The same footprint and stain rules the PROPS lane holds every other prop to: art drawn as
			# painted, at the size its content says it was authored to, on a tile-square canvas that
			# centres (the crate's own rect, so a mapped container moves nothing).
			if (look["tint"] as Color) != Color.WHITE:
				push_error("CONTAINERS: %s has art and must draw it unstained; got tint %s" % [look_id, str(look["tint"])])
				return false
			var want_px: int = int(round(float(look["size"]) * CameraUtil.ART_NATIVE))
			var got_px: int = _footprint_px(look["texture"])
			if absi(got_px - want_px) > FOOTPRINT_SLACK_PX:
				push_error("CONTAINERS: %s declares size %.2f (%d px of a tile) and its art measures %d px across" % [look_id, float(look["size"]), want_px, got_px])
				return false
			if Appearance.anchor_of(Vector2i((look["texture"] as Texture2D).get_size())) != Appearance.Anchor.Centre:
				push_error("CONTAINERS: %s is not a tile-square picture; _draw_prop would hang it instead of centring it" % look_id)
				return false
			var bytes: PackedByteArray = (look["texture"] as Texture2D).get_image().get_data()
			if seen_pixels.has(bytes):
				push_error("CONTAINERS: %s draws the same pixels as %s; two kinds or two states you cannot tell apart" % [look_id, String(seen_pixels[bytes])])
				return false
			seen_pixels[bytes] = look_id
	# The dead-socket half: nothing in the stations file is a container picture no rule reaches.
	var stations: Variant = JSON.parse_string(FileAccess.get_file_as_string(STATIONS_PATH))
	var listed: Array = []
	for entry2 in stations as Array:
		listed.append(String((entry2 as Dictionary).get("id", "")))
	var stray: Array[String] = _unreachable_container_ids(listed, tables as Dictionary)
	if not stray.is_empty():
		push_error("CONTAINERS: %s declares a container picture no table reaches: %s" % [STATIONS_PATH, str(stray)])
		return false
	if _unreachable_container_ids(["prop.container.brass"], tables as Dictionary).size() != 1 or not _unreachable_container_ids(["prop.container.metal.searched", "prop.bed"], tables as Dictionary).is_empty():
		push_error("CONTAINERS: the unreachable-id scanner passed a picture no table reaches, or refused a reachable one")
		return false

	# --- the real entity path ----------------------------------------------------------------
	var seen_kinds: Dictionary = {}
	for table2 in CONTAINER_EXPECTED.keys():
		var box: int = SimContainers.make_container(w, 3.5, 3.5, "cupboard", String(table2))
		var closed: Dictionary = Appearance.prop_look(w, box)
		if String(closed["id"]) != String(CONTAINER_EXPECTED[table2]):
			push_error("CONTAINERS: a '%s' container drew as %s off the entity path, want %s" % [String(table2), String(closed["id"]), String(CONTAINER_EXPECTED[table2])])
			return false
		(w.components.get_component(box, "searchable") as Dictionary)["searched"] = true
		var opened: Dictionary = Appearance.prop_look(w, box)
		if String(opened["id"]) != String(CONTAINER_EXPECTED[table2]) + Appearance.PROP_SEARCHED_SUFFIX:
			push_error("CONTAINERS: a searched '%s' container drew as %s, want the searched picture of its own kind" % [String(table2), String(opened["id"])])
			return false
		seen_kinds[String(closed["id"])] = true
	if seen_kinds.size() != 3:
		push_error("CONTAINERS: the five tables drew as %s; want the crate, the footlocker and the medical box" % str(seen_kinds.keys()))
		return false
	# The kind word is the sim's prose and is never read: a cupboard, a wardrobe and a car boot
	# stocked from one table are one picture. An unknown table draws the crate, off the entity path too.
	var by_kind: Dictionary = {}
	for kind_word in ["cupboard", "wardrobe", "car boot", "supply locker", "ammo crate"]:
		var b2: int = SimContainers.make_container(w, 4.5, 4.5, String(kind_word), "medical")
		by_kind[String(Appearance.prop_look(w, b2)["id"])] = true
	if by_kind.keys() != ["prop.container.medical"]:
		push_error("CONTAINERS: five kind words stocked from the medical table drew as %s; the picture is the table's and not the word's" % str(by_kind.keys()))
		return false
	var odd: int = SimContainers.make_container(w, 5.5, 5.5, "cupboard", "no_such_table")
	if String(Appearance.prop_look(w, odd)["id"]) != CONTAINER_BASE_ID:
		push_error("CONTAINERS: a container stocked from an unknown table drew as %s, want the wood crate" % String(Appearance.prop_look(w, odd)["id"]))
		return false

	# --- clause 4: what the picture may not say ------------------------------------------------
	# The state is `searched`, the flag the sim writes once and the renderer already showed on every
	# seen tile -- a colonist's search out of sight included, which is a box you can see standing open
	# and no new fact. What is *in* a box is not read: a full unsearched box and an empty one are one
	# picture, and there is no open-with-supplies picture -- a searched box with something still in it
	# draws as a searched one, because that state would need `contents_of` at a distance.
	var full: int = SimContainers.make_container(w, 6.5, 6.5, "cupboard", "military_cache")
	var empty: int = SimContainers.make_container(w, 7.5, 6.5, "cupboard", "military_cache")
	var stuff: int = int(w.entities.spawn())
	w.components.set_component(stuff, "stored", {"container": full, "x": 0, "y": 0, "rotated": false})
	(w.components.get_component(full, "container") as Dictionary)["items"] = [{"item": stuff, "x": 0, "y": 0, "rotated": false}]
	if SimContainers.contents_of(w, full).is_empty():
		push_error("CONTAINERS: the fixture put nothing in the box; the contents assertion below judges nothing")
		return false
	if String(Appearance.prop_look(w, full)["id"]) != String(Appearance.prop_look(w, empty)["id"]):
		push_error("CONTAINERS: a box with something in it draws differently from an empty one before it is opened; the picture would tell what is inside")
		return false
	(w.components.get_component(full, "searchable") as Dictionary)["searched"] = true
	(w.components.get_component(empty, "searchable") as Dictionary)["searched"] = true
	if String(Appearance.prop_look(w, full)["id"]) != String(Appearance.prop_look(w, empty)["id"]):
		push_error("CONTAINERS: a searched box with something still in it draws differently from an emptied one; that is the open-with-supplies state, which needs the contents at a distance")
		return false
	var look_source: String = _function_source(APPEARANCE_GD, "prop_look") + _function_source(APPEARANCE_GD, "table_prop_id")
	if look_source.strip_edges().is_empty():
		push_error("CONTAINERS: could not read prop_look and table_prop_id out of %s" % APPEARANCE_GD)
		return false
	var read: String = _reads_contents(look_source)
	if not read.is_empty():
		push_error("CONTAINERS: prop_look reads %s; a container's picture may say its table and whether it was searched, and nothing it holds" % read)
		return false
	for fabricated in ["var n = contents_of(world, entity)", "var held = (comp as Dictionary).get(\"items\", [])", "var box = world.components.get_component(entity, \"container\")", "var k = String((comp as Dictionary).get(\"kind\", \"\"))"]:
		if _reads_contents(String(fabricated)).is_empty():
			push_error("CONTAINERS: the contents scanner passed a body that reads what a box holds (%s); it cannot say no" % String(fabricated))
			return false

	# --- seen tiles only ---------------------------------------------------------------------------
	# A container draws only where the prop pass already draws: through the observer's own seen set,
	# never through a wall. The draw pass cannot run headless, so the guard is read as source, in its
	# place -- before the look is resolved -- and the scanner is shown a body without it first.
	var draw_props: String = _function_source(MAIN_GD, "_draw_props")
	var guard: String = "seen != null and not (seen as Object).call(\"has_tile\", floori(x), floori(y))"
	if draw_props.is_empty() or not draw_props.contains(guard):
		push_error("CONTAINERS: _draw_props no longer skips a prop on a tile the observer cannot see; a container would draw through a wall")
		return false
	if draw_props.find(guard) > draw_props.find("Appearance.prop_look(world, e)"):
		push_error("CONTAINERS: _draw_props resolves a prop's look before it asks whether the tile is seen")
		return false
	var unguarded: String = "var look = Appearance.prop_look(world, e)\nseen = null\n_draw_prop(look, x, y, zoom)"
	if unguarded.contains(guard):
		push_error("CONTAINERS: the seen-tile scanner accepted a body with no guard; it cannot say no")
		return false
	if not draw_props.contains("Appearance.PROP_KINDS") or not draw_props.contains("_draw_prop(look, x, y, zoom)"):
		push_error("CONTAINERS: _draw_props does not walk PROP_KINDS into _draw_prop; a container's look is read by nothing")
		return false

	print("CONTAINERS OK %d loot tables each name a container kind (%s) and a table nobody named, an empty one and a prop with no map draw the id they were handed; six pictures, three kinds by two states, pairwise different pixels; the entity path draws the table's kind, its searched pair, the same picture for five kind words and the wood crate for an unknown table; a box with something in it draws as an empty one, unopened or searched (no open-with-supplies state, prop_look reads no contents); no container picture in the stations file is unreached; _draw_props still guards every prop on the observer's seen set" % [CONTAINER_EXPECTED.size(), str(CONTAINER_EXPECTED)])
	return true


# --- STANDING -----------------------------------------------------------------------------

# "Props for things that exist" (docs/23): the pack's barricade and work lamp are the pictures of
# things the sim already had -- the scrap barricade, and a floodlight planted in the yard -- and they
# are taller than a tile, so they stand in the entity sort. A picture swap and nothing else: no new
# mechanic, no sim file touched. The pack's stove is not here (docs/23 says why).

# The one rule that keeps a swapped picture from being a second picture: the key a prop declares is
# an authored `standing` key, so a generator key, a flat prop's key or a name nobody authored is
# refused. One predicate for the shipped props and for the fabrications that prove it.
func _standing_key_complaint(key: String, authored: Dictionary) -> String:
	if not authored.has(key):
		return "names '%s', which authored.json does not declare -- a generated or retired picture" % key
	var kind: String = String((authored[key] as Dictionary).get("kind", ""))
	if kind != "standing":
		return "names '%s', an authored key of kind `%s`, not `standing`" % [key, kind]
	return ""


func _standing_props_come_from_the_pack() -> bool:
	Appearance.forget()
	var w: Variant = World.new(_fixture())
	var authored: Dictionary = {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sprites/authored.json"))
	if parsed is Dictionary and (parsed as Dictionary).get("keys") is Dictionary:
		authored = (parsed as Dictionary)["keys"] as Dictionary
	var ids: Array[String] = ["prop.barricade", "prop.lamp", "prop.lamp.dark"]

	# --- the pictures are the pack's, and stand ---------------------------------------------------
	for id in ids:
		var block: Dictionary = Appearance.of_content(w, "prop", id)
		var why: String = _standing_key_complaint(String(block.get("sprite", "")), authored)
		if not why.is_empty():
			push_error("STANDING: %s %s" % [id, why])
			return false
		var look: Dictionary = Appearance.prop_of(w, id)
		if look["texture"] == null or not bool(look["standing"]) or String(look["sprite"]) != String(block["sprite"]):
			push_error("STANDING: %s resolved no standing picture (%s)" % [id, str(look)])
			return false
	# TN, through the same predicate: a generated key that never existed, the wood crate's key, the
	# bed's, and an empty key are each refused.
	for retired in ["prop_barricade_scrap", "barricade_scrap", "prop_container", "prop_bed", ""]:
		if _standing_key_complaint(String(retired), authored).is_empty():
			push_error("STANDING: the key predicate accepted '%s'; a retired or flat picture could be swapped back in" % String(retired))
			return false
	# A flat picture is not a standing one, and a standing one is not flat: the bed and every
	# container lie flat, and the entity sort is where the barricade and the lamp stand.
	for flat in ["prop.bed", "prop.container", "prop.campfire", "prop.well", "prop.latrine"]:
		if bool(Appearance.prop_of(w, flat)["standing"]):
			push_error("STANDING: %s is drawn standing; a flat picture would leave the entity sort's depth order" % flat)
			return false

	# --- the entity path: the sim's own things ---------------------------------------------------
	var wall: int = int(w.entities.spawn())
	w.components.set_component(wall, "position", {"x": 4.5, "y": 3.5})
	w.components.set_component(wall, "scrapBarricade", {})
	if String(Appearance.prop_look(w, wall).get("id", "")) != "prop.barricade":
		push_error("STANDING: the scrap barricade drew as %s" % str(Appearance.prop_look(w, wall).get("id", "")))
		return false
	# The lamp is the sim's own lit fact, read off the component the burn clock writes: lit while it
	# lights the yard, dark once the fuel is out -- driven by the real burn tick, not a set flag.
	var lamp: int = int(w.entities.spawn())
	w.components.set_component(lamp, "position", {"x": 6.5, "y": 3.5})
	w.components.set_component(lamp, "itemBase", {"baseId": "item.floodlight.rigged"})
	w.components.set_component(lamp, "placedLight", {"baseId": "item.floodlight.rigged", "tx": 6, "ty": 3})
	if String(Appearance.prop_look(w, lamp).get("id", "")) != "prop.lamp.dark":
		push_error("STANDING: a planted floodlight that lights nothing drew as %s, want the dark lamp" % str(Appearance.prop_look(w, lamp).get("id", "")))
		return false
	SimLight.make_light_source(w, lamp, 90.0)
	if String(Appearance.prop_look(w, lamp).get("id", "")) != "prop.lamp":
		push_error("STANDING: a burning planted floodlight drew as %s, want the lit lamp" % str(Appearance.prop_look(w, lamp).get("id", "")))
		return false
	w.components.set_component(lamp, "lightFuel", {"ticksLeft": 1})
	SimLight._tick_burn(w)
	if w.components.has_component(lamp, "light_source") or String(Appearance.prop_look(w, lamp).get("id", "")) != "prop.lamp.dark":
		push_error("STANDING: a floodlight whose fuel ran out on the sim's burn tick still draws lit (%s)" % str(Appearance.prop_look(w, lamp).get("id", "")))
		return false
	# What lights it is not the picture's business: the lamp's fuel is read for no number, and the
	# picture is one of two.
	var picture_source: String = _function_source(APPEARANCE_GD, "prop_look")
	for forbidden in ["lightFuel", "ticksLeft", "fuel_left", "SimLight"]:
		if picture_source.contains(forbidden):
			push_error("STANDING: prop_look reads %s; a lamp's picture is lit or dark and never how long it will burn" % forbidden)
			return false
	if not picture_source.contains("lit_component"):
		push_error("STANDING: prop_look never reads a kind's `lit_component`; the lamp's lit picture is unreachable")
		return false
	# Placed things are still the sim's entities: prop_tiles names both (a furnishing steps aside).
	var taken: Dictionary = Appearance.prop_tiles(w)
	if not taken.has(Vector2i(4, 3)) or not taken.has(Vector2i(6, 3)):
		push_error("STANDING: prop_tiles missed the barricade or the lamp; a chair could stand under either")
		return false

	# --- which ones, on which tiles: the pure rule, judged headless ------------------------------------
	var everything := FakeSeen.new()
	for ty in 12:
		for tx in 12:
			everything.tiles[Vector2i(tx, ty)] = true
	var whole: Dictionary = {"minX": 0.0, "minY": 0.0, "maxX": 12.0, "maxY": 12.0}
	var rows: Array[Dictionary] = Appearance.standing_props(w, everything, whole)
	var by_entity: Dictionary = {}
	for row in rows:
		by_entity[int(row["e"])] = row
	if rows.size() != 2 or not by_entity.has(wall) or not by_entity.has(lamp):
		push_error("STANDING: standing_props answered %s over a world with a barricade and a dark lamp, want exactly those two" % str(rows))
		return false
	# It stands on its tile's south-edge centre, the tree's rule, and names its own picture.
	var wall_row: Dictionary = by_entity[wall] as Dictionary
	if float(wall_row["gx"]) != 4.5 or float(wall_row["gy"]) != 4.0 or String(wall_row["key"]) != "prop_barricade":
		push_error("STANDING: the barricade at (4.5, 3.5) stands at %s, want its tile's south-edge centre (4.5, 4.0) with prop_barricade" % str(wall_row))
		return false
	if String((by_entity[lamp] as Dictionary)["key"]) != "prop_lamp_dark":
		push_error("STANDING: the dark lamp names %s, want prop_lamp_dark" % String((by_entity[lamp] as Dictionary)["key"]))
		return false
	SimLight.make_light_source(w, lamp, 90.0)
	for row2 in Appearance.standing_props(w, everything, whole):
		if int(row2["e"]) == lamp and String(row2["key"]) != "prop_lamp":
			push_error("STANDING: the burning lamp names %s, want prop_lamp" % String(row2["key"]))
			return false
	# TN, each taking one thing away: nobody sees nothing; an unseen tile answers nothing (through a
	# wall); a tile outside the bounds answers nothing; a despawned prop answers nothing; a flat prop
	# is not a standing one; and an entity is answered once however many kinds it matches.
	if not Appearance.standing_props(w, null, whole).is_empty():
		push_error("STANDING: seen == null answered standing props; nobody sees no lamps")
		return false
	if not Appearance.standing_props(w, FakeSeen.new(), whole).is_empty():
		push_error("STANDING: an empty seen set answered standing props; a lamp would draw through a wall")
		return false
	var only_wall := FakeSeen.new()
	only_wall.tiles[Vector2i(4, 3)] = true
	var one: Array[Dictionary] = Appearance.standing_props(w, only_wall, whole)
	if one.size() != 1 or int(one[0]["e"]) != wall:
		push_error("STANDING: seeing only the barricade's tile answered %s, want just the barricade" % str(one))
		return false
	if not Appearance.standing_props(w, everything, {"minX": 8.0, "minY": 8.0, "maxX": 12.0, "maxY": 12.0}).is_empty():
		push_error("STANDING: bounds excluding both props still answered them")
		return false
	var bed_e: int = int(w.entities.spawn())
	w.components.set_component(bed_e, "position", {"x": 2.5, "y": 2.5})
	w.components.set_component(bed_e, "bed", {})
	for row3 in Appearance.standing_props(w, everything, whole):
		if int(row3["e"]) == bed_e:
			push_error("STANDING: the bed, a flat picture, was answered as standing")
			return false
	var remembered := FakeSeen.new()
	if not Appearance.standing_props(w, remembered, whole).is_empty():
		push_error("STANDING: a set with no live tiles answered standing props; the remembered map must not feed them")
		return false
	# entities.despawn and not world.despawn: the world's clears the components as well, which would
	# make the test pass without the alive check; the entity store's leaves them, the trap CLAUDE.md names.
	w.entities.despawn(wall)
	if not w.components.has_component(wall, "scrapBarricade"):
		push_error("STANDING: the fixture despawn removed the component; the alive assertion below would judge nothing")
		return false
	for row4 in Appearance.standing_props(w, everything, whole):
		if int(row4["e"]) == wall:
			push_error("STANDING: a despawned barricade is still answered; components.query does not check alive and this must")
			return false
	# The tile branch's question, on a real tilemap: a scrap overlay is a barricade, a board or a
	# bare wall or no overlay is not.
	var map: Variant = SimTileMap.blank_map(12, 12)
	w.tilemap = map
	map.overlays[3 * 12 + 4] = {"kind": "scrap"}
	map.overlays[3 * 12 + 5] = {"kind": "board", "stage": 0}
	if not Appearance.scrap_stands_at(w, 4, 3):
		push_error("STANDING: a scrap overlay is not a standing barricade")
		return false
	if Appearance.scrap_stands_at(w, 5, 3) or Appearance.scrap_stands_at(w, 6, 3) or Appearance.scrap_stands_at(w, -1, 3) or Appearance.scrap_stands_at(null, 4, 3):
		push_error("STANDING: a board, a bare tile, an off-map tile or a null world answered as the barricade")
		return false

	# --- where they are drawn ----------------------------------------------------------------------
	# The draw pass cannot run headless, so it is read as source, in its place, with the needle
	# scanner shown a body without each guard first.
	var standing: String = _function_source(MAIN_GD, "_standing_props")
	var missing: String = _lacks(standing, ["Appearance.standing_props(world, seen, TopDownProjection.visible_bounds(camera, 2.0))", "TopDownProjection.world_to_screen(camera, float(row[\"gx\"]), float(row[\"gy\"]))", "TopDownProjection.depth_of(", "\"kind\": \"standing\""])
	if not missing.is_empty():
		push_error("STANDING: _standing_props does not contain %s" % missing)
		return false
	if standing.contains("explored") or standing.contains("SimSightings") or standing.contains("remembered") or standing.contains("world.components"):
		push_error("STANDING: _standing_props reads the remembered map or the components itself; the rule is Appearance.standing_props' and it is the live seen set")
		return false
	if _lacks("var x = Appearance.standing_props(world, null, b)", ["Appearance.standing_props(world, seen, TopDownProjection.visible_bounds(camera, 2.0))"]).is_empty():
		push_error("STANDING: the standing scanner passed a body that hands the pass no observer; it cannot say no")
		return false
	var entities: String = _function_source(MAIN_GD, "_draw_entities")
	var at_gather: int = entities.find("items.append_array(_standing_props(seen))")
	var at_sort: int = entities.find("items.sort_custom(")
	var at_blit: int = entities.find("_blit_standing(it, px_scale)")
	if at_gather < 0 or at_sort < 0 or at_blit < 0 or not (at_gather < at_sort and at_sort < at_blit):
		push_error("STANDING: _draw_entities does not gather the standing props before the sort and blit them after it (gather %d, sort %d, blit %d)" % [at_gather, at_sort, at_blit])
		return false
	if _lacks(_function_source(MAIN_GD, "_blit_standing"), ["Appearance.body_rect(float(it[\"sx\"]), float(it[\"sy\"]), texture.get_size() * px_scale, 1.0)", "draw_texture_rect("]) != "":
		push_error("STANDING: _blit_standing does not stand its picture on the feet line")
		return false
	if _function_source(MAIN_GD, "_blit_standing").contains("draw_set_transform("):
		push_error("STANDING: _blit_standing sets a transform")
		return false
	var flat_pass: String = _function_source(MAIN_GD, "_draw_props")
	var at_skip: int = flat_pass.find("bool(look.get(\"standing\", false))")
	var at_flat: int = flat_pass.find("_draw_prop(look, x, y, zoom)")
	if at_skip < 0 or at_flat < 0 or at_skip > at_flat:
		push_error("STANDING: _draw_props does not skip a standing picture before it draws flat; a lamp would draw twice, once under the bodies")
		return false
	# The barricade's tile: the floor under it draws only for a tile seen now, and the slab stays for
	# a remembered one and for a barricade with no art.
	var district: String = _function_source(MAIN_GD, "_draw_district")
	var missing_district: String = _lacks(district, ["if live and _scrap_stands_at(tx, ty):", "_draw_barricade_floor(rect, ground, tx, ty)", "_draw_solid_tile(rect, col, tx, ty)"])
	if not missing_district.is_empty():
		push_error("STANDING: _draw_district does not contain %s; the barricade's slab may not swap for the floor on a live tile only" % missing_district)
		return false
	# TN: the same needles over a fabrication that always draws the floor, never the slab.
	if _lacks("if true:\n\t_draw_barricade_floor(\nelse:\n\t_draw_solid_tile(rect, col, tx, ty)", ["if live and _scrap_stands_at(tx, ty):"]).is_empty():
		push_error("STANDING: the district needle scanner accepted a body with no live guard; it cannot say no")
		return false
	if not _function_source(MAIN_GD, "_draw_barricade_floor").contains("_draw_floor_tile("):
		push_error("STANDING: _draw_barricade_floor does not draw a floor tile")
		return false
	if not _function_source(MAIN_GD, "_scrap_stands_at").contains("return Appearance.scrap_stands_at(world, tx, ty)"):
		push_error("STANDING: _scrap_stands_at is not the rule the lane judged (Appearance.scrap_stands_at)")
		return false

	print("STANDING OK barricade, lit lamp and dark lamp each declare an authored `standing` key (a generated name, the crate's key, the bed's and an empty one are refused) that resolves a picture taller than a tile; the bed, the containers, the fire, the well and the latrine stay flat; the scrap barricade draws as itself, a planted floodlight draws dark until it burns, lit while it does, and dark again on the sim's own burn tick, with no fuel read; prop_tiles names both; standing_props answers each on its tile's south-edge centre and only for the live seen set, inside the bounds, alive and standing (nobody, an empty set, one tile, the bounds, a bed and a despawned barricade all refused), scrap_stands_at says yes to a scrap overlay and no to a board, a bare tile, the map's edge and no world; the entity pass gathers before the sort and blits after it, _draw_props skips a standing picture before it draws flat, and the tile branch swaps the slab for the floor on live tiles only")
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
	var bag_needles: Array = ["Appearance.item_look(", "ItemPicture.draw("]
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
		push_error("PICTURES: the bag plate does not hand an `item_look` to ItemPicture.draw; a declared item sprite would resolve and never reach a bag")
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


# The quick strip and the inspect pane draw the picture the bag plate and the floor draw
# (docs/23, "Item pictures in the quick strip / inspect pane"). Three things could go wrong, each
# with a true positive and a true negative: a screen could stop calling the shared draw, the shared
# draw could stop reaching a texture (or lose the glyph a base without a picture wears), and the
# inventory sheet could stop handing the strip and the pane the world they resolve a picture
# against. The bag plate rides the same predicates, so all three screens are held to one rule.
func _the_strip_and_the_inspector_draw_the_picture() -> bool:
	var caller_needles: Array = ["Appearance.item_look(", "ItemPicture.draw("]
	var draw_needles: Array = ["look[\"texture\"]", "draw_texture_rect(", "ItemGlyph.draw_glyph("]
	var callers: Array = [
		["the quick strip", "res://ui/quick_strip.gd", "static func draw_strip("],
		["the inspect pane", "res://ui/inspect_pane.gd", "static func draw_pane("],
		["the bag plate", "res://ui/bag_grid.gd", "static func draw_item("],
	]

	# True negatives first, on fabricated bodies, so the scanners are shown to fail before they are
	# trusted on real code.
	var caller_control: String = "var look = Appearance.item_look(world, base)\nItemPicture.draw(ci, box, look, a)\n"
	var draw_control: String = "var art = look[\"texture\"]\nci.draw_texture_rect(art, r, false, c)\nItemGlyph.draw_glyph(ci, box, 0, c)\n"
	if not _appears_in_order(caller_control, caller_needles) or not _appears_in_order(draw_control, draw_needles):
		push_error("PICTURES: a scanner refused a body shaped like the real one; it would refuse the real ones")
		return false
	var refused: Array = [
		["a draw that is only a comment", caller_needles, "var look = Appearance.item_look(world, base)\n# ItemPicture.draw(ci, box, look, a)\n"],
		["a look that is never drawn", caller_needles, "var look = Appearance.item_look(world, base)\nItemGlyph.draw_glyph(ci, box, 0, c)\n"],
		["a draw made before the look", caller_needles, "ItemPicture.draw(ci, box, look, a)\nvar look = Appearance.item_look(world, base)\n"],
		["a shared draw whose texture draw is only a comment", draw_needles, "var art = look[\"texture\"]\n# ci.draw_texture_rect(art, r, false, c)\nItemGlyph.draw_glyph(ci, box, 0, c)\n"],
		["a shared draw with no glyph for a base with no picture", draw_needles, "var art = look[\"texture\"]\nci.draw_texture_rect(art, r, false, c)\n"],
	]
	for row in refused:
		if _appears_in_order(String((row as Array)[2]), (row as Array)[1] as Array):
			push_error("PICTURES: a scanner accepted %s; it proves nothing" % String((row as Array)[0]))
			return false

	for c in callers:
		var src: String = FileAccess.get_file_as_string(String((c as Array)[1]))
		var fn: String = _function_text(src, String((c as Array)[2]))
		if fn.is_empty():
			push_error("PICTURES: could not find %s in %s; the draw assertion is reading the wrong place" % [String((c as Array)[2]), String((c as Array)[1])])
			return false
		if not _appears_in_order(fn, caller_needles):
			push_error("PICTURES: %s does not hand an `Appearance.item_look` to ItemPicture.draw; an item's picture would resolve and never reach it" % String((c as Array)[0]))
			return false
	var shared: String = _function_text(FileAccess.get_file_as_string("res://ui/item_picture.gd"), "static func draw(")
	if not _appears_in_order(shared, draw_needles):
		push_error("PICTURES: ItemPicture.draw does not reach a texture draw and then a glyph fallback; a declared sprite or a base with none would draw nothing")
		return false

	# The calls in the inventory sheet hand the screens the world they resolve a picture against.
	var sheet: String = _without_comments(FileAccess.get_file_as_string("res://ui/inventory_panel.gd"))
	var calls: Array[String] = ["QuickStrip.draw_strip(", "InspectPane.draw_pane("]
	var seen_calls: int = 0
	for line in sheet.split("\n"):
		for call in calls:
			if String(line).contains(call):
				seen_calls += 1
				if not String(line).strip_edges().ends_with("_world)"):
					push_error("PICTURES: inventory_panel.gd calls %s without the world, so nothing can be resolved to a picture: %s" % [call, String(line).strip_edges()])
					return false
	if seen_calls < 3:
		push_error("PICTURES: inventory_panel.gd has %d calls into the strip and the pane; the lane expected the strip twice and the pane once" % seen_calls)
		return false
	if "QuickStrip.draw_strip(self, r, rows, 1.0)".ends_with("_world)"):
		push_error("PICTURES: the world-argument predicate accepted a call with no world; it proves nothing")
		return false

	# What the two screens resolve, against a real world: an item's base comes back from the item
	# entity alone (the strip's rows and the inspect view carry no base id, and none may carry a
	# digit), a pictured base draws its icon and one without draws its glyph, and a thing that is
	# not an item resolves to nothing rather than to somebody else's picture.
	var w: Variant = World.new({"seed": 4244, "tick_hz": 20, "map": {"width": 8, "height": 8, "walls": []}, "player": {"id": 0, "x": 1.5, "y": 1.5, "stance": 2}})
	var pictured_id: String = "item.antibiotics.course"
	var plain_id: String = ""
	for path in (w.content as Dictionary).keys():
		if not String(path).begins_with("items/"):
			continue
		for entry in (w.content as Dictionary)[path] as Array:
			var d: Dictionary = entry as Dictionary
			if plain_id.is_empty() and not (d.get("appearance", {}) as Dictionary).has("sprite"):
				plain_id = String(d.get("id", ""))
	var with_picture: int = w.entities.spawn()
	w.components.set_component(with_picture, "itemBase", {"baseId": pictured_id})
	var without: int = w.entities.spawn()
	w.components.set_component(without, "itemBase", {"baseId": plain_id})
	var not_an_item: int = w.entities.spawn()
	if ItemPicture.base_of(w, with_picture) != pictured_id or ItemPicture.base_of(w, without) != plain_id:
		push_error("PICTURES: ItemPicture.base_of did not return the base an item entity carries")
		return false
	if not ItemPicture.base_of(w, not_an_item).is_empty() or not ItemPicture.base_of(w, -1).is_empty() or not ItemPicture.base_of(null, with_picture).is_empty():
		push_error("PICTURES: ItemPicture.base_of resolved a base for something that is not an item")
		return false
	if Appearance.item_look(w, ItemPicture.base_of(w, with_picture))["texture"] == null:
		push_error("PICTURES: the strip's item %s resolves no picture, though it declares one" % pictured_id)
		return false
	var plain: Dictionary = Appearance.item_look(w, ItemPicture.base_of(w, without))
	if plain_id.is_empty() or plain["texture"] != null:
		push_error("PICTURES: the strip's item '%s', which declares no picture, resolved one or nothing at all" % plain_id)
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
	if not _the_strip_and_the_inspector_draw_the_picture():
		return false
	print("PICTURES OK %d of %d bases draw one of the pack's %d icons and %d fall back to their class's glyph; every declared item sprite resolves at %dx%d, is an authored key and carries no tint; the antibiotic grades and the two waters draw one picture; the floor and the bag plate both draw what item_look resolved, and a comment, a missing draw, a misordered draw and an unsized floor draw are each refused; the bag plate, the quick strip and the inspect pane draw it through one ItemPicture.draw, the sheet hands the last two its world, and a pictured base draws its icon on the strip while one without falls back to its class's glyph" % [pictured, pictured + fallback, keys.size(), fallback, native, native])
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
