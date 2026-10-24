extends RefCounted
# How the night reads, derived from the one number the simulation already keeps.
#
# docs/30 ("what light made structural", the clause on the overlay): the screen may draw a lit
# region **only where the survivor can see it**, and the night wash derives from `sightMetres`
# rather than from raw ambient. Both halves are here, as pure statics, so the gate can drive them
# headlessly against a booted world -- there is no state in this file at all, which is also why
# there is no `static var` for two gate worlds to share.
#
# The rule, in one sentence: standing in a lit pool lifts the dark *because the range genuinely
# grew*, not because the renderer decided to draw light. One number, two consumers -- the wash
# alpha and the survivor's sight -- rather than two answers to one question.

const Clock = preload("res://sim/time/clock.gd")
const SimLight = preload("res://sim/vision/light.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const Items = preload("res://sim/modules/items.gd")
const SimSightings = preload("res://sim/modules/sightings.gd")
const LightModule = preload("res://sim/modules/light.gd")
const Appearance = preload("res://presentation/appearance.gd")
const FxLook = preload("res://presentation/fx_look.gd")
const CameraUtil = preload("res://presentation/camera.gd")
const Palette = preload("res://presentation/palette.gd")

# Metres of remaining reach that split a pool's near half from its far half. Straight off the
# frozen renderer's LIGHT_OVERLAY_SPLIT: the near half of a lamp's pool is where a body is worth
# looking at and the far half is where one is a shape.
const POOL_SPLIT_METRES: float = 3.0
const DEFAULT_SOURCE_TINT: Color = Palette.LIGHT_POOL_RGB

# The light map (plan item A10, presentation/light_map.gd and night_light.gdshader). How many
# sources one frame can carry: the shader holds one bit per source per tile in three bytes. More
# than this in view is not an error; the dimmest are left out, which can only make the screen
# darker than the sim, never lighter.
const MAX_LIGHTS: int = 24
# How far a flame's reach dips when it flickers, as a fraction of its reach. Only ever down: a
# flicker that reached past the sim's own cast would draw light where the sim has none.
const FLAME_FLICKER: float = 0.03
# How lit the survivor's own disc of night is at least (night_light.gdshader's `eye_floor`): their
# body and the ground at their feet, which the sim already says they see, stay readable.
const EYE_FLOOR: float = 0.55
# The view that shows a body from behind, whose beam starts on the ground under it (`hand_metres`).
const BACK_VIEW: String = "n"
# The widest that disc is drawn, in metres, however far the survivor sees: in a lit room they see
# the whole room, and the room is the pools' to light; the disc is only the ground at their feet.
const EYE_DISC_MAX_M: float = 3.5
# How many flat rings a pool is drawn in (night_light.gdshader's `pool_levels`), each one's edge an
# ordered dither into the next: pixel-art light, not an airbrushed gradient.
const POOL_LEVELS: int = 5
# The brightest a source's pool gets, as a fraction of daylight, by how far the sim says it reaches:
# CAP_AT_ZERO + metres / CAP_METRES, held between CAP_MIN and CAP_MAX. A campfire (20 m) out-shines
# a storm lantern (16 m), so where two pools overlap the brighter one shows as its own level rather
# than both clipping to one; a candle is a dim glow and a worklight nearly daylight.
const CAP_AT_ZERO: float = 0.35
const CAP_METRES: float = 40.0
const CAP_MIN: float = 0.45
const CAP_MAX: float = 0.95
# How much of the night's colour is left in full dark at midnight (night_light.gdshader's
# `night_floor`): the floor outside every light is near black, a channel never above 8 of 255
# on a white tile, with only a little blue in it.
const NIGHT_FLOOR: float = 0.24


# The raw ambient fraction for this world's tick -- daylight 1.0, deep night NIGHT_AMBIENT.
#
# Exposed rather than inlined because the callers need exactly this number and no other: the
# fallback below, the light map's sky (and its refusal to draw any night at all at noon), and the
# O channel's refusal to paint pools then.
static func ambient_of(world: Variant) -> float:
	return Clock.ambient_light_at(_tick_of(world))


# How lit the observer is, as a fraction of what their own eyes could do in full daylight.
#
# Clamped to 1 because `sight_metres` already caps at the observer's own range -- a floodlight
# cannot give better than daylight vision -- so this is a fraction and never a multiplier.
#
# Falls back to raw ambient when there is nobody to ask: a world booted without a player, or the
# parity/headless boot where the body carries no `observer`. That is the frozen renderer's
# `eyes === null` branch, and it is what the wash always was before light existed. Since the light
# map it is what sizes the survivor's own disc of night (`eye_disc_metres`).
static func local_light_fraction(world: Variant, eyes: int) -> float:
	var ambient: float = ambient_of(world)
	if world == null or eyes < 0 or world.components == null:
		return ambient
	var obs: Variant = world.components.get_component(eyes, "observer")
	var pos: Variant = world.components.get_component(eyes, "position")
	if not (obs is Dictionary) or not (pos is Dictionary):
		return ambient
	var full: float = float((obs as Dictionary).get("range_metres", 0.0))
	if not (full > 0.0):
		return ambient
	var metres: float = SimLight.sight_metres(world, obs as Dictionary, float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]))
	return clampf(metres / full, 0.0, 1.0)


# How far from the survivor's feet the light map draws the disc of ground they make out by
# themselves (night_light.gdshader's `eye_reach`): their own sight at their feet, in metres, held
# under EYE_DISC_MAX_M. By night with no light it is the sky's share of their range -- the sim's
# own radius of seen tiles, so the disc is round inside it rather than cut by it. 0 with nobody to
# ask, and then no disc is drawn.
static func eye_disc_metres(world: Variant, eyes: int) -> float:
	if world == null or eyes < 0 or world.components == null:
		return 0.0
	var obs: Variant = world.components.get_component(eyes, "observer")
	if not (obs is Dictionary):
		return 0.0
	var full: float = float((obs as Dictionary).get("range_metres", 0.0))
	if not (full > 0.0):
		return 0.0
	return clampf(local_light_fraction(world, eyes) * full, 0.0, EYE_DISC_MAX_M)


# The brightest a source's pool is drawn (night_light.gdshader's light_tint.w): CAP_AT_ZERO plus
# a share for every metre the sim says it reaches, between CAP_MIN and CAP_MAX. Monotonic, so a
# stronger light is never drawn dimmer than a weaker one.
static func source_cap(magnitude: float) -> float:
	return clampf(CAP_AT_ZERO + maxf(0.0, magnitude) / CAP_METRES, CAP_MIN, CAP_MAX)


# The light map's texels for the tiles in `view` (tile coordinates, clamped to the map by the
# caller): four bytes a tile. R is 255 where the survivor sees the tile, 128 where they only remember
# it (their explored map), 0 for the void no layer draws. G, B and A are one bit per
# source, bits 0-23 in `sources` order, set where that source's own shadowcast reaches the tile
# **and** the survivor sees it -- lit ∩ seen, the rule `lit_pool_tiles` holds, as bits a shader can
# read. A tile the survivor does not see is four zero bytes whatever lights it, so nothing a wall
# hides can come out the far side of the shader.
#
# A beam's bits are the sim's own wedge, tile for tile: `world.light.lights_tile` (sim/vision/light.gd)
# decides them -- its cast, inside the half-angle of its carrier's facing or within the spill at its
# feet -- so the screen draws a torch's light on exactly the tiles the sim says it lands on, and none
# behind the holder. A round light's bits are its cast, which is the same answer `lights_tile` gives
# a source with no beam, asked directly so the common case does not pay a second lookup per tile.
#
# `sources` is the light index's sources that reach a seen tile in view, brightest first and at
# most MAX_LIGHTS; `lights` is each one's origin, reach, tint and flicker, in the same order.
# With no observer at all every tile reads seen and no source is listed -- the wash's ambient
# fallback, unchanged.
static func light_texels(world: Variant, eyes: int, view: Rect2i) -> Dictionary:
	var w: int = maxi(0, view.size.x)
	var h: int = maxi(0, view.size.y)
	var bytes := PackedByteArray()
	bytes.resize(w * h * 4)
	var sources: Array[int] = []
	var lights: Array[Dictionary] = []
	var out: Dictionary = {"bytes": bytes, "sources": sources, "lights": lights, "seen": 0, "lit": 0}
	if w == 0 or h == 0 or world == null:
		return out
	var seen: Variant = null
	if eyes >= 0 and world.vision != null:
		seen = world.vision.tiles_for(eyes)
	if seen == null:
		for i in range(w * h):
			bytes[i * 4] = 255
		out["seen"] = w * h
		return out
	var explored: Variant = SimSightings.explored_view(world, eyes)
	var opaque_faces: bool = world.tilemap != null
	# The candidates: every source whose reach could touch the view, brightest first (ties by id,
	# so the order never depends on a Dictionary's), and each one's cast resolved once.
	var candidates: Array = []
	if world.light != null:
		for source in world.light.sources_list():
			var id: int = int(source)
			var origin: Variant = world.light.source_at(id)
			var cast: Variant = world.light.tiles_for(id)
			if not origin is Dictionary or cast == null:
				continue
			var reach: float = float((origin as Dictionary)["magnitude"])
			var ox: float = float((origin as Dictionary)["x"])
			var oy: float = float((origin as Dictionary)["y"])
			if ox + reach < float(view.position.x) or ox - reach > float(view.end.x) or oy + reach < float(view.position.y) or oy - reach > float(view.end.y):
				continue
			var beamed: bool = float((origin as Dictionary).get("beam", 0.0)) > 0.0
			candidates.append({"id": id, "x": ox, "y": oy, "magnitude": reach, "cast": cast, "beamed": beamed, "bit": -1})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["magnitude"]) != float(b["magnitude"]):
			return float(a["magnitude"]) > float(b["magnitude"])
		return int(a["id"]) < int(b["id"]))
	if candidates.size() > MAX_LIGHTS:
		candidates.resize(MAX_LIGHTS)
	for i in candidates.size():
		(candidates[i] as Dictionary)["bit"] = i
	var seen_count: int = 0
	var lit_count: int = 0
	var used: int = 0
	for ty in range(view.position.y, view.end.y):
		for tx in range(view.position.x, view.end.x):
			var at: int = ((ty - view.position.y) * w + (tx - view.position.x)) * 4
			if not bool((seen as Object).call("has_tile", tx, ty)):
				if explored != null and bool((explored as Object).call("has_tile", tx, ty)):
					bytes[at] = 128
				continue
			bytes[at] = 255
			seen_count += 1
			var mask: int = 0
			for c in candidates:
				var cd: Dictionary = c as Dictionary
				if absf(float(tx) + 0.5 - float(cd["x"])) > float(cd["magnitude"]) + 1.0 or absf(float(ty) + 0.5 - float(cd["y"])) > float(cd["magnitude"]) + 1.0:
					continue
				if _lands(world, cd, tx, ty):
					mask |= 1 << int(cd["bit"])
			if mask != 0 and opaque_faces and _opaque(world.tilemap, tx, ty):
				mask = _face_lit(world, candidates, mask, tx, ty)
			if mask != 0:
				lit_count += 1
				used |= mask
				bytes[at + 1] = mask & 0xff
				bytes[at + 2] = (mask >> 8) & 0xff
				bytes[at + 3] = (mask >> 16) & 0xff
	# Only the sources that reached a seen tile are handed on; the bits keep their slots, so a
	# source that lit nothing leaves a hole the shader skips rather than a renumbering.
	for c in candidates:
		var cd: Dictionary = c as Dictionary
		var id: int = int(cd["id"])
		sources.append(id)
		var lit_any: bool = (used >> int(cd["bit"])) & 1 == 1
		lights.append({"entity": id, "x": float(cd["x"]), "y": float(cd["y"]), "magnitude": float(cd["magnitude"]) if lit_any else 0.0, "tint": source_tint(world, id), "flicker": source_flicker(world, id), "beam": source_beam(world, id), "facing": _facing_of(world, id)})
	out["seen"] = seen_count
	out["lit"] = lit_count
	return out


# Which of `mask`'s sources light an opaque tile's face rather than only its far side: the sim's
# shadowcast lights the first opaque tile it meets, including one met through a window -- a
# hedge or a shelf behind the glass, whose own picture is solid and reads as the wall going on.
# The screen lights an opaque tile only from a source that also lights one of its four open
# neighbours (not blocking sight and not glass), the ground its lit face looks onto. Less light than
# the sim's, never more: light passes a window onto the floor beyond, not onto masonry.
static func _face_lit(world: Variant, candidates: Array, mask: int, tx: int, ty: int) -> int:
	var open: Array[Vector2i] = []
	for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var at: Vector2i = Vector2i(tx, ty) + (n as Vector2i)
		if _open(world.tilemap, at.x, at.y):
			open.append(at)
	if open.is_empty():
		return 0
	var kept: int = 0
	for c in candidates:
		var cd: Dictionary = c as Dictionary
		var bit: int = 1 << int(cd["bit"])
		if mask & bit == 0:
			continue
		for at in open:
			if _lands(world, cd, at.x, at.y):
				kept |= bit
				break
	return kept


# Whether a candidate source's light lands on tile (tx, ty): the sim's `lights_tile` for a beam, its
# cast for a round light (the same answer, without the second lookup).
static func _lands(world: Variant, cd: Dictionary, tx: int, ty: int) -> bool:
	if bool(cd["beamed"]):
		return bool(world.light.lights_tile(int(cd["id"]), tx, ty))
	return bool((cd["cast"] as Object).call("has_tile", tx, ty))


# Ground a lit face can look onto: anything that does not block sight except the glass of a
# window, which is the very thing the light came through. Deep water, a counter or a fence counts:
# light lands on them, so a face beside them may be lit from there.
static func _open(map: Variant, tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return false
	return not _opaque(map, tx, ty) and int(map.tiles[ty * int(map.w) + tx]) != SimTileMap.Tile.Window


# Whether a tile blocks a standing survivor's sight. The bare tile class answers it from
# SimTileMap's own table; a tile with an overlay (a door, a board, scrap) asks the sim's own
# predicate, so the two never disagree. This runs once per lit seen tile every night frame, which
# is why the common case does not take a static call through the overlay table.
static func _opaque(map: Variant, tx: int, ty: int) -> bool:
	var at: int = ty * int(map.w) + tx
	if (map.overlays as Dictionary).has(at):
		return SimTileMap.blocks_sight(map, tx, ty)
	return SimTileMap.OPACITY[int(map.tiles[at])] == SimTileMap.Opacity.Opaque


# The tiles a warm pool is painted on: **lit ∩ seen**, split into near and far by remaining reach.
# Returns `{"near": Array[Vector2i], "far": Array[Vector2i]}`, both empty when there is nothing to
# draw or nobody to draw it for.
#
# Lit alone is a fact about the world; lit *and* seen is a fact about the survivor, and the
# survivor is who the screen is for. A pool thirty metres away with no sightline to it would be
# painted bright and be invisible -- the screen asserting what the simulation denies -- so the
# seen test is not an optimisation and may not be dropped for one.
#
# The seen test is `vision.tiles_for(eyes).has_tile`, deliberately the *same* question
# `_draw_district` asks before it draws the floor: a pool is a tint on a tile, so it appears
# exactly where that tile appears and never on background. (The frozen renderer additionally
# narrowed by `detail`, the facing cone; the top-down district draw does not, and a pool that
# blinked out of a floor still drawn would be the two layers disagreeing about one tile.)
#
# Bounds come from the caller's viewport (`TopDownProjection.visible_bounds`) and are clamped to
# the map here: a floodlight's window is ninety tiles a side, and walking that whole square every
# frame would put the overlay in the frame budget rather than in the frame.
static func lit_pool_tiles(world: Variant, eyes: int, bounds: Dictionary) -> Dictionary:
	var near: Array[Vector2i] = []
	var far: Array[Vector2i] = []
	var coloured: Dictionary = {}
	if world == null or eyes < 0 or world.light == null or world.vision == null:
		return {"near": near, "far": far, "coloured": coloured}
	var seen: Variant = world.vision.tiles_for(eyes)
	if seen == null:
		return {"near": near, "far": far, "coloured": coloured}
	# Resolve once per source per draw. This is important for a carried lamp: walking every
	# tile must not rescan every survivor's inventory and attachment tree.
	var source_meta: Dictionary = {}
	var source_order: Array = []
	for source in world.light.sources_list():
		var source_id: int = int(source)
		var origin: Variant = world.light.source_at(source_id)
		var cast: Variant = world.light.tiles_for(source_id)
		if not origin is Dictionary or cast == null:
			continue
		source_meta[source_id] = {"origin": origin, "tiles": cast, "tint": source_tint(world, source_id)}
		source_order.append(source_id)
	var min_x: int = maxi(0, floori(float(bounds.get("minX", 0.0))))
	var max_x: int = mini(int(world.map_width) - 1, ceili(float(bounds.get("maxX", 0.0))))
	var min_y: int = maxi(0, floori(float(bounds.get("minY", 0.0))))
	var max_y: int = mini(int(world.map_height) - 1, ceili(float(bounds.get("maxY", 0.0))))
	for ty in range(min_y, max_y + 1):
		for tx in range(min_x, max_x + 1):
			if not (seen as Object).call("has_tile", tx, ty):
				continue
			# Tile centres, so this asks the light index the same question a body standing there
			# would ask it.
			var lit: float = float(world.light.lit_metres(float(tx) + 0.5, float(ty) + 0.5))
			if lit <= 0.0:
				continue
			if lit >= POOL_SPLIT_METRES:
				near.append(Vector2i(tx, ty))
			else:
				far.append(Vector2i(tx, ty))
			var winner: int = _winning_source(source_meta, source_order, float(tx) + 0.5, float(ty) + 0.5)
			var winner_meta: Dictionary = source_meta.get(winner, {})
			var tint: Color = winner_meta.get("tint", DEFAULT_SOURCE_TINT) as Color
			var near_pool: bool = lit >= POOL_SPLIT_METRES
			var key: String = "%s:%s" % [tint.to_html(false), "near" if near_pool else "far"]
			if not coloured.has(key):
				coloured[key] = {"tint": tint, "near": near_pool, "tiles": [] as Array[Vector2i]}
			(coloured[key]["tiles"] as Array).append(Vector2i(tx, ty))
	return {"near": near, "far": far, "coloured": coloured}


# The winner uses the exact strict-greater comparison and source iteration order used by
# SimLight.lit_metres, so equal remaining reaches keep the first source and light is never summed.
static func _winning_source(source_meta: Dictionary, source_order: Array, x: float, y: float) -> int:
	var best: float = 0.0
	var winner: int = -1
	var tx: int = floori(x / float(SimTileMap.TILE_METRES))
	var ty: int = floori(y / float(SimTileMap.TILE_METRES))
	for source in source_order:
		var meta: Dictionary = source_meta[int(source)] as Dictionary
		var cast: Variant = meta["tiles"]
		if not (cast as Object).call("has_tile", tx, ty):
			continue
		var origin: Dictionary = meta["origin"] as Dictionary
		var dx: float = x - float(origin["x"])
		var dy: float = y - float(origin["y"])
		var rem: float = float(origin["magnitude"]) - sqrt(pow(dx, 2.0) + pow(dy, 2.0))
		if rem > best:
			best = rem
			winner = int(source)
	return winner


# Read the active source's current content, not an id-specific drawing branch. Unknown and
# absent metadata deliberately fall back to the legacy amber pool.
static func source_tint(world: Variant, source: int) -> Color:
	if world == null or world.components == null or source < 0:
		return DEFAULT_SOURCE_TINT
	var tint_value: Variant = null
	if world.components.has_component(source, "placedLight"):
		var planted: Variant = world.components.get_component(source, "placedLight")
		var planted_id: String = String((planted as Dictionary).get("baseId", "")) if planted is Dictionary else ""
		var planted_base: Dictionary = Items.content_entry(world, "item", planted_id) if not planted_id.is_empty() else {}
		tint_value = _light_tint(planted_base.get("light"))
	elif world.components.has_component(source, "itemBase"):
		var item: Variant = Items.item_base_of(world, source)
		if item is Dictionary:
			tint_value = _light_tint((item as Dictionary).get("light"))
	elif world.components.has_component(source, "campfire"):
		var look: Dictionary = Appearance.prop_look(world, source)
		var appearance: Dictionary = Appearance.of_content(world, "prop", String(look.get("id", "")))
		tint_value = _light_tint(appearance.get("light"))
	elif world.components.has_component(source, "equipment"):
		var carried: Dictionary = LightModule.brightest_carried(world, source)
		var carried_mag: float = float(carried.get("magnitude", 0.0))
		var ranged: Variant = world.components.get_component(source, "rangedWeapon")
		# A live shot owns its flash even on an exact magnitude tie (ranged.fire stores
		# max(flash, carried) and the counter is the only fact that distinguishes the flash).
		if ranged is Dictionary and int((ranged as Dictionary).get("flashTicks", 0)) > 0 and float((ranged as Dictionary).get("flash", 0.0)) >= carried_mag:
			return DEFAULT_SOURCE_TINT
		var carried_item: int = int(carried.get("item", -1))
		if carried_item >= 0:
			var base: Variant = Items.item_base_of(world, carried_item)
			if base is Dictionary:
				tint_value = _light_tint((base as Dictionary).get("light"))
	return _parse_tint(tint_value)


static func _light_tint(light: Variant) -> Variant:
	return (light as Dictionary).get("tint") if light is Dictionary else null


static func _parse_tint(value: Variant) -> Color:
	if not value is String:
		return DEFAULT_SOURCE_TINT
	var raw: String = String(value)
	if tint_declaration_is_valid(raw) and raw.begins_with("#"):
		return Color(raw)
	return DEFAULT_SOURCE_TINT


static func tint_declaration_is_valid(value: Variant) -> bool:
	if not value is String:
		return false
	var raw: String = String(value)
	if raw.length() != 7 or not raw.begins_with("#"):
		return false
	for index in range(1, raw.length()):
		var code: int = raw.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true


# Source hue replaces only the old amber hue. Near/far pool strength (including the developer
# overlay) remains the palette's existing alpha, so this art pass cannot brighten a cast.
static func pool_colour(tint: Color, near: bool, overlay: bool = false) -> Color:
	var legacy: Color = Palette.LIGHT_POOL_NEAR_OVERLAY if near and overlay else Palette.LIGHT_POOL_FAR_OVERLAY if overlay else Palette.LIGHT_POOL_NEAR if near else Palette.LIGHT_POOL_FAR
	return Color(tint.r, tint.g, tint.b, legacy.a)


static func _tick_of(world: Variant) -> int:
	if world == null:
		return 0
	if world is Dictionary:
		return int((world as Dictionary).get("tick", 0))
	return int(world.tick)


# How much a source flickers: a flame does, a bulb does not. A campfire is a flame; a lamp or a
# torch is one when its content burns oil or burns nothing it can be fed (a candle, a flare), and
# steady when it runs on a cell or gas. A shot's flash is a moment, not a flame. Read off the same
# content `source_tint` reads, never off an id.
static func source_flicker(world: Variant, source: int) -> float:
	if world == null or world.components == null or source < 0:
		return 0.0
	if world.components.has_component(source, "campfire"):
		return FLAME_FLICKER
	var light: Variant = _source_light_block(world, source)
	if not light is Dictionary:
		return 0.0
	var feed: String = String((light as Dictionary).get("feed", ""))
	return FLAME_FLICKER if feed.is_empty() or feed == "oil" else 0.0


# The half-angle, in radians, of the beam a source's pool is drawn as, or 0 for a round pool: the
# sim's own -- the `beam` the light index keeps for the source (sim/modules/light.gd writes it from
# the brightest carried light's content, and sim/vision/light.gd keeps it only while its carrier has
# a facing to point it along). The screen reads it rather than the content, so the wedge it draws
# and the tiles `lights_tile` lights are one answer.
static func source_beam(world: Variant, source: int) -> float:
	var at: Variant = _sim_source(world, source)
	return float((at as Dictionary).get("beam", 0.0)) if at is Dictionary else 0.0


# The content `light` block behind a source: a planted lamp's base, a loose item's own base, or the
# brightest light a body carries -- null for a campfire (a prop, with no item behind it) and for a
# shot's flash, which out-shines whatever the shooter carries for its few ticks and is neither a
# flame nor a beam.
static func _source_light_block(world: Variant, source: int) -> Variant:
	if world.components.has_component(source, "placedLight"):
		var planted: Variant = world.components.get_component(source, "placedLight")
		var planted_id: String = String((planted as Dictionary).get("baseId", "")) if planted is Dictionary else ""
		var planted_base: Dictionary = Items.content_entry(world, "item", planted_id) if not planted_id.is_empty() else {}
		return planted_base.get("light")
	if world.components.has_component(source, "itemBase"):
		var item: Variant = Items.item_base_of(world, source)
		return (item as Dictionary).get("light") if item is Dictionary else null
	if world.components.has_component(source, "equipment"):
		var carried: Dictionary = LightModule.brightest_carried(world, source)
		var ranged: Variant = world.components.get_component(source, "rangedWeapon")
		if ranged is Dictionary and int((ranged as Dictionary).get("flashTicks", 0)) > 0 and float((ranged as Dictionary).get("flash", 0.0)) >= float(carried.get("magnitude", 0.0)):
			return null
		var carried_item: int = int(carried.get("item", -1))
		if carried_item >= 0:
			var base: Variant = Items.item_base_of(world, carried_item)
			if base is Dictionary:
				return (base as Dictionary).get("light")
	return null


# The way a source's beam points: the carrier's facing as the light index read it this tick, the
# facing `lights_tile` cut the wedge along, so the drawn wedge and the lit tiles turn together.
static func _facing_of(world: Variant, entity: int) -> float:
	var at: Variant = _sim_source(world, entity)
	return float((at as Dictionary).get("facing", 0.0)) if at is Dictionary else 0.0


static func _sim_source(world: Variant, source: int) -> Variant:
	if world == null or source < 0 or world.light == null:
		return null
	return world.light.source_at(source)


# Where a beam leaves its carrier's body, in metres from the body's ground point, as the screen
# draws it: the hand that holds the light (Appearance's HELD_HANDS, or the frame's own hand when the
# body was drawn on a walk frame that moves it) mapped off the feet-anchored pawn canvas, so the
# light starts where the torch is held and not at the soles -- except seen from behind, where it
# starts at the hand's side on the ground under the body. A light in no hand -- a headlamp, a
# clip light on the glasses -- has no socket, and its beam starts at the ground point (zero).
#
# `member` is the body frame the carrier was last drawn on (FxLook's drawn_frames, "" for none),
# whose view is the one the hand is read for; with no frame, the view the facing shows. `zoom` is
# screen pixels a tile, which only the soles' drop below the ground point depends on.
static func hand_metres(world: Variant, source: int, facing: float, member: String, zoom: float) -> Vector2:
	var slot: String = _hand_slot(world, source)
	if slot.is_empty():
		return Vector2.ZERO
	var view: String = Appearance.view_of(facing)
	for v in Appearance.VIEWS:
		if not member.is_empty() and FxLook.member_in_view(member, v):
			view = v
			break
	var hand: Vector2i = Appearance.frame_hand(member if FxLook.member_in_view(member, view) else "", slot, view)
	if hand.x < 0:
		return Vector2.ZERO
	var art: float = CameraUtil.ART_NATIVE
	var canvas := Vector2(Appearance.PAWN_CANVAS)
	var drop: float = Appearance.FOOT_DROP_PX / zoom if zoom > 0.0 else 0.0
	var x: float = (float(hand.x) + 0.5 - canvas.x / 2.0) / art
	# Seen from behind, the hand is in front of the body and the beam runs up the screen through it,
	# so a beam from the hand's height shows first above the head and reads as a headlamp. It starts
	# at the hand's side on the ground under the body instead (art review, round 1).
	if view == BACK_VIEW:
		return Vector2(x, 0.0)
	return Vector2(x, (float(hand.y) + 0.5 - canvas.y) / art + drop)


# The hand slot ("primary" or "secondary") holding the light a body throws: the slot whose item is
# the lit one, or carries it fitted (a weapon light under a barrel). "" when the light is in no hand.
static func _hand_slot(world: Variant, source: int) -> String:
	if world == null or world.components == null or source < 0:
		return ""
	var eq: Variant = world.components.get_component(source, "equipment")
	if not eq is Dictionary:
		return ""
	var slots: Variant = (eq as Dictionary).get("slots")
	if not slots is Dictionary:
		return ""
	var lit: int = int(LightModule.brightest_carried(world, source).get("item", -1))
	if lit < 0:
		return ""
	for slot in Appearance.HELD_HANDS.keys():
		var there: Variant = (slots as Dictionary).get(slot)
		if there == null:
			continue
		if int(there) == lit or int(LightModule.brightest_of(world, int(there)).get("item", -1)) == lit:
			return String(slot)
	return ""
