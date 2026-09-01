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
	ok = _every_canvas_is_64() and ok
	ok = _procedural_fallback_still_works() and ok
	ok = _the_player_has_a_body() and ok
	ok = _tints_come_from_content_not_code() and ok
	ok = _art_is_not_modulated_by_a_role_colour() and ok
	ok = _equipped_gear_layers_resolve() and ok
	ok = _props_look_like_something() and ok
	if ok:
		print("APPEARANCE_OK schema keys resolve, fallback intact, the player has a body, tints from content")
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
			# One canvas: 64x64 centre-anchored (assets/sprites/README.md). A stray sprite
			# authored to the dead 64x96 feet-anchored convention would float half a tile
			# high without ever erroring, so the shape is a build failure, not a footnote.
			var size: Vector2 = (tex as Texture2D).get_size()
			if size != Vector2(64, 64):
				push_error("%s: appearance.%s '%s' is %dx%d, the canvas is 64x64" % [path, prop, k, int(size.x), int(size.y)])
				return false
			resolved += 1
	# The canvas assertion must have judged real files, or it proves nothing.
	if resolved == 0:
		push_error("no sprite keys resolved -- the canvas assertion had nothing to judge")
		return false
	print("KEYS OK %d resolved on the 64x64 canvas" % resolved)
	return true

# Every file in the directory, referenced or not: an unreferenced stray is one content edit away
# from drawing, and nothing above would have judged it. Raw Image.load, same as appearance.gd's
# headless fallback. (It used to also cover the item blocks _all_blocks could not see, which it no
# longer has to -- array-topped files are walked now -- but a stray file still has no entry.)
func _every_canvas_is_64() -> bool:
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
		if img.get_width() != 64 or img.get_height() != 64:
			push_error("%s/%s is %dx%d, the canvas is 64x64 (assets/sprites/README.md)" % [SPRITE_DIR, f, img.get_width(), img.get_height()])
			return false
		judged += 1
	if judged == 0:
		push_error("no PNGs in %s -- the canvas assertion had nothing to judge" % SPRITE_DIR)
		return false
	print("CANVAS OK %d files at 64x64" % judged)
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


# Guards the migration: these two colours used to be literals in _draw_entities. If someone
# moves them back into code, the content block disappears and this fails.
func _tints_come_from_content_not_code() -> bool:
	var w: Variant = World.new(_fixture())
	var expected: Dictionary = {"zombie.screamer": "#d95947", "zombie.bloater": "#6b8c47"}
	for id in expected.keys():
		var block: Dictionary = Appearance.of_content(w, "zombie", String(id))
		if not block.has("tint"):
			push_error("%s declares no appearance.tint; its colour belongs in content, not in the draw loop" % id)
			return false
		var got: Color = Color(String(block["tint"]))
		if got != Color(String(expected[id])):
			push_error("%s tint %s != expected %s" % [id, block["tint"], expected[id]])
			return false
		var look: Dictionary = Appearance.for_entity(w, {"ztype": String(id)})
		if (look["tint"] as Color) != got:
			push_error("%s: for_entity did not use the content tint" % id)
			return false
	# The shambler is the one type with real art on disk and no declared tint: it must
	# resolve its texture and pass through white, unstained by the wanderer role colour.
	# (The declares-nothing fallback keeps its own true positive above, via the unknown type.)
	var shambler: Dictionary = Appearance.for_entity(w, {"ztype": "zombie.shambler"})
	if shambler["texture"] == null:
		push_error("zombie.shambler declares appearance.sprite but resolved no texture")
		return false
	if (shambler["tint"] as Color) != Color.WHITE:
		push_error("zombie.shambler's art declares no tint and must draw white, got %s" % str(shambler["tint"]))
		return false
	# Mara exercises the survivor cid path the same way: real art, no tint, drawn as painted.
	var mara: Dictionary = Appearance.for_entity(w, {"unique": true, "cid": "survivor.unique.mara"})
	if mara["texture"] == null:
		push_error("survivor.unique.mara declares appearance.sprite but resolved no texture")
		return false
	if (mara["tint"] as Color) != Color.WHITE:
		push_error("survivor.unique.mara's art declares no tint and must draw white, got %s" % str(mara["tint"]))
		return false
	print("TINTS OK")
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


# Every prop id the renderer can ask for has an entry in content, and that entry says enough to
# draw. The true positive is the six shipped ids resolving distinct, well-formed looks; the true
# negative is an id nobody authored, which must degrade to the drab fallback rather than resolving
# a tint that looks deliberate -- and must *not* be mistaken for a real entry, which is what the
# "declares a tint" assertion below would catch if a prop entry were ever deleted.
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
	var tints: Array[Color] = []
	for id in ids:
		var block: Dictionary = Appearance.of_content(w, "prop", id)
		if not block.has("tint"):
			push_error("%s declares no appearance.tint; a prop with no art and no tint is an invisible thing standing in the district" % id)
			return false
		var look: Dictionary = Appearance.prop_of(w, id)
		if (look["tint"] as Color) != Color(String(block["tint"])):
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
		if tints.has(look["tint"] as Color):
			push_error("%s reuses tint %s -- two props you cannot tell apart" % [id, str(look["tint"])])
			return false
		tints.append(look["tint"] as Color)
	var unknown: Dictionary = Appearance.prop_of(w, "prop.does_not_exist")
	if (unknown["tint"] as Color) != Palette.COLOURS["prop"]:
		push_error("an unauthored prop id should fall back to the drab prop colour, got %s" % str(unknown["tint"]))
		return false
	if String(unknown["shape"]) != Appearance.PROP_SHAPE_DEFAULT or unknown["texture"] != null:
		push_error("an unauthored prop id should still be drawable as the default shape with no texture")
		return false
	print("PROPS OK %d ids, distinct tints, unknown id degrades" % ids.size())
	return true
