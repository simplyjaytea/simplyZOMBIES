extends RefCounted
# What a thing looks like, resolved from content rather than decided in the draw loop.
#
# docs/20-ecs-and-content.md: adding a type should be "a JSON entry with zero code".
# Appearance was the last axis where that was untrue -- _draw_entities used to carry
#   if ztype == "zombie.screamer": col = Color(0.85, 0.35, 0.28)
# so a new zombie type needed a presentation edit to look like anything. Those colours now
# live in zombies/*.json as `appearance.tint`.
#
# Presentation-only, per ui/README.md's boundary: sim/ must never import this. It reads
# world.content, which is the same tree the sim modules read.
#
# Sprites are optional and currently absent. `resolve` returns null for a key with no file,
# and every caller falls back to the procedural shapes that ship today -- the fallback is a
# supported path, not a temporary one, and check_appearance.gd asserts it stays that way.

const Palette = preload("res://presentation/palette.gd")

const SPRITE_DIR: String = "res://assets/sprites"

# Equipment slots the renderer draws on a body. A slot with no anchor point defined here
# stays declarable in content (item.schema.json) but is silently not drawn -- extending this
# list is a renderer change, not a content one, because a new slot needs a decision about
# whether it draws under or over the body.
const EQUIP_UNDER_BODY: Array[String] = ["back"]
const EQUIP_OVER_BODY: Array[String] = ["primary", "secondary"]

# key -> Texture2D, or null when the key has no file. Cached either way: a miss is the
# common case and re-probing the filesystem every frame would cost more than the sprites.
static var _cache: Dictionary = {}


# Both lookups matter, and neither is sufficient alone.
#
# A PNG dropped into the project is not a Resource until Godot imports it -- ResourceLoader
# cannot see it, so an artist adding art would get nothing until an editor round-trip, and
# headless CI would never see a new sprite at all. Loading the raw file fixes that.
#
# But an exported build ships imported resources, and the raw .png is not in the .pck unless
# it matches an export filter -- so the raw path fails there and ResourceLoader is the one
# that works. Trying imported first, then raw, covers dev, CI, and export.
static func resolve(key: String) -> Texture2D:
	if key.is_empty():
		return null
	if _cache.has(key):
		return _cache[key] as Texture2D
	var path: String = "%s/%s.png" % [SPRITE_DIR, key]
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Texture2D:
			texture = res as Texture2D
	if texture == null and FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(path) == OK:
			texture = ImageTexture.create_from_image(img)
	_cache[key] = texture
	return texture


# Clears the texture cache. For gates that probe resolution with and without files present.
static func forget() -> void:
	_cache.clear()


# The appearance block for a content id, or {} when the type declares none.
# Content `extends` is deliberately not merged here: nothing else in the codebase resolves
# inheritance at runtime (content_validator.gd only checks it exists and does not cycle), so
# a type inherits nothing and declares its own look, same as its locomotion or body.
static func of_content(world: Variant, kind: String, id: String) -> Dictionary:
	var entry: Variant = _content_entry(world, kind, id)
	if not (entry is Dictionary):
		return {}
	var block: Variant = (entry as Dictionary).get("appearance")
	return block as Dictionary if block is Dictionary else {}


# The draw instruction for one entity, given the role flags _draw_entities already computed.
# Returns {texture: Texture2D|null, tint: Color, radius: float}.
static func for_entity(world: Variant, it: Dictionary) -> Dictionary:
	var is_player: bool = bool(it.get("player", false))
	var is_unique: bool = bool(it.get("unique", false))
	var is_bait: bool = bool(it.get("bait", false))

	# Role colours are the floor: an entity with no content appearance looks exactly as it
	# did before this file existed.
	var role: String = "wanderer"
	if is_player:
		role = "player"
	elif is_unique:
		role = "survivor"
	elif is_bait:
		role = "groundItem"
	var tint: Color = Palette.COLOURS[role]
	var sprite_key: String = ""

	# Zombies carry their type id, unique survivors their identity id. Either is a content
	# id, and content is what decides how a thing looks.
	var content_id: String = String(it.get("ztype", ""))
	if content_id.is_empty():
		content_id = String(it.get("cid", ""))
	var declared_tint: bool = false
	if not content_id.is_empty():
		var kind: String = "zombie" if content_id.begins_with("zombie.") else "survivor"
		var block: Dictionary = of_content(world, kind, content_id)
		if block.has("tint"):
			tint = Color(String(block["tint"]))
			declared_tint = true
		if block.has("sprite"):
			sprite_key = String(block["sprite"])

	var texture: Texture2D = resolve(sprite_key)
	var radius: float = 14.0 if is_player else (12.0 if is_unique else 10.0)
	return {"texture": texture, "tint": modulate_for(texture != null, declared_tint, tint), "radius": radius}


# Textures for whatever this entity has equipped in a slot the renderer draws, ordered
# under-body first then over-body, each tagged with which side of the body draw call it goes
# on. A slot with nothing equipped, an item with no equipSprite, or an entity with no
# equipment component at all (zombies) all fall out silently -- equipment is optional the
# same way a sprite is.
static func equipment_layers_for(world: Variant, actor: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world == null or world.components == null:
		return out
	var eq: Variant = world.components.get_component(actor, "equipment")
	if not (eq is Dictionary):
		return out
	var slots: Dictionary = (eq as Dictionary).get("slots", {}) as Dictionary
	for group in [{"names": EQUIP_UNDER_BODY, "over": false}, {"names": EQUIP_OVER_BODY, "over": true}]:
		for slot in group["names"] as Array[String]:
			var texture: Texture2D = _equip_texture_for(world, slots.get(slot))
			if texture != null:
				out.append({"texture": texture, "over": bool(group["over"])})
	return out


# The equipSprite texture for whatever item entity occupies a slot, or null through every exit:
# no item, no itemBase component, no matching content entry, no declared equipSprite, no file.
static func _equip_texture_for(world: Variant, item: Variant) -> Texture2D:
	if item == null:
		return null
	var item_base: Variant = world.components.get_component(int(item), "itemBase")
	if not (item_base is Dictionary):
		return null
	var base_id: String = String((item_base as Dictionary).get("baseId", ""))
	if base_id.is_empty():
		return null
	var entry: Variant = _content_entry(world, "item", base_id)
	if not (entry is Dictionary):
		return null
	var block: Variant = (entry as Dictionary).get("appearance")
	if not (block is Dictionary) or not (block as Dictionary).has("equipSprite"):
		return null
	return resolve(String((block as Dictionary)["equipSprite"]))


# The rule for what colour multiplies a drawn entity, named so it can be asserted without
# needing art on disk.
#
# A role colour stands in for missing art; it must not filter art that exists. Drawn as a
# modulate it multiplies every pixel, so a sprite whose content declares no tint would arrive
# stained with e.g. the tan survivor colour instead of looking like what the artist drew.
# Art passes through white; only a tint the content actually asked for modulates it.
static func modulate_for(has_texture: bool, declared_tint: bool, colour: Color) -> Color:
	if has_texture and not declared_tint:
		return Color.WHITE
	return colour


# Content is keyed by file path, not by id, so a lookup scans. Mirrors the private
# _get_content_entry in sim/modules/{shambler,light,roster}.gd -- which is triplicated there
# already; unifying those is sim-side work and out of scope for a presentation file.
static func _content_entry(world: Variant, kind: String, id: String) -> Variant:
	if world == null or world.content == null:
		return null
	var c: Variant = world.content
	if c is Object and (c as Object).has_method("get"):
		return (c as Object).call("get", kind, id)
	if not (c is Dictionary):
		return null
	for v in (c as Dictionary).values():
		if v is Array:
			for entry in v as Array:
				if entry is Dictionary and String((entry as Dictionary).get("id", "")) == id:
					return entry
		elif v is Dictionary and String((v as Dictionary).get("id", "")) == id:
			return v
	return null
