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
const LightModule = preload("res://sim/modules/light.gd")
const Appearance = preload("res://presentation/appearance.gd")
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
# The curve a fraction of daylight sight is shown through: 1 - (1 - f)^LIGHT_CURVE. 0 stays 0 and 1
# stays 1; the dim end is lifted, so a campfire, which lends at most 20 of a survivor's 48 metres,
# reads as a pool of light and not as a slightly less dark patch. Monotonic, so the brighter of
# two pixels is always the one where the sim sees further.
const LIGHT_CURVE: float = 3.0
# How far a flame's reach dips when it flickers, as a fraction of its reach. Only ever down: a
# flicker that reached past the sim's own cast would draw light where the sim has none.
const FLAME_FLICKER: float = 0.03
# How lit the survivor's own disc of night is at least (night_light.gdshader's `eye_floor`): their
# body and the ground at their feet, which the sim already says they see, stay readable.
const EYE_FLOOR: float = 0.3


# The raw ambient fraction for this world's tick -- daylight 1.0, deep night NIGHT_AMBIENT.
#
# Exposed rather than inlined because two callers need exactly this number and no other: the
# fallback below, and the draw loop's refusal to paint pools at noon. It is emphatically *not*
# what the wash is computed from any more; `local_light_fraction` is.
static func ambient_of(world: Variant) -> float:
	return Clock.ambient_light_at(_tick_of(world))


# How lit the observer is, as a fraction of what their own eyes could do in full daylight.
#
# Clamped to 1 because `sight_metres` already caps at the observer's own range -- a floodlight
# cannot give better than daylight vision -- so this is a fraction and never a multiplier.
#
# Falls back to raw ambient when there is nobody to ask: a world booted without a player, or the
# parity/headless boot where the body carries no `observer`. That is the frozen renderer's
# `eyes === null` branch, and it is what the wash always was before light existed.
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


# The night wash's alpha, and the daylight early-out that goes with it. `night_wash` is passed in
# rather than owned here because it is a look constant of the screen that draws it (main.gd's
# NIGHT_WASH), while the fraction it scales is a fact about the survivor.
#
# Since the light map (A10) the night is no longer one flat fill: this is the darkness the shader
# lays on the survivor's own tile, before its dither, and `shown` is the curve both share.
static func wash_alpha(world: Variant, eyes: int, night_wash: float) -> float:
	var light: float = local_light_fraction(world, eyes)
	if light >= 1.0:
		return 0.0
	return (1.0 - shown_at_eye(ambient_of(world), light)) * night_wash


# How lit the survivor's own tile is shown, before the pool's core: the sky as it is, never less
# than EYE_FLOOR around the survivor's own feet, and a source's light through the curve where it
# out-reaches the sky. night_light.gdshader's `sky_here` and `lift` at distance zero.
static func shown_at_eye(ambient: float, fraction: float) -> float:
	var sky: float = maxf(ambient, EYE_FLOOR)
	if fraction > ambient:
		return maxf(sky, shown(fraction))
	return sky


# The fraction of daylight sight as the screen shows it: night_light.gdshader's `shown`, the same
# formula, so the gate can hold the two to one curve.
static func shown(fraction: float) -> float:
	return 1.0 - pow(1.0 - clampf(fraction, 0.0, 1.0), LIGHT_CURVE)


# The fraction of daylight sight at a point, for the survivor `eyes`: their own sight rule
# (SimLight.sight_metres) asked at (x, y) instead of at their feet, over their daylight range --
# what the light map shows there before the shader measures distance to the pixel rather than to
# the point. Where the survivor does not see the tile, no source counts and only the sky is left,
# which is the light map's no-leak rule as a number. At the survivor's own position this is
# `local_light_fraction` exactly.
static func light_fraction_at(world: Variant, eyes: int, x: float, y: float) -> float:
	var ambient: float = ambient_of(world)
	if world == null or eyes < 0 or world.components == null:
		return ambient
	var obs: Variant = world.components.get_component(eyes, "observer")
	if not (obs is Dictionary):
		return ambient
	var full: float = float((obs as Dictionary).get("range_metres", 0.0))
	if not (full > 0.0):
		return ambient
	var seen: Variant = world.vision.tiles_for(eyes) if world.vision != null else null
	if seen == null or not bool((seen as Object).call("has_tile", floori(x), floori(y))):
		return ambient
	return clampf(SimLight.sight_metres(world, obs as Dictionary, x, y) / full, 0.0, 1.0)


# The light map's texels for the tiles in `view` (tile coordinates, clamped to the map by the
# caller): four bytes a tile. R is 255 where the survivor sees the tile. G, B and A are one bit per
# source, bits 0-23 in `sources` order, set where that source's own shadowcast reaches the tile
# **and** the survivor sees it -- lit ∩ seen, the rule `lit_pool_tiles` holds, as bits a shader can
# read. A tile the survivor does not see is four zero bytes whatever lights it, so nothing a wall
# hides can come out the far side of the shader.
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
			candidates.append({"id": id, "x": ox, "y": oy, "magnitude": reach, "cast": cast, "bit": -1})
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
			if not bool((seen as Object).call("has_tile", tx, ty)):
				continue
			var at: int = ((ty - view.position.y) * w + (tx - view.position.x)) * 4
			bytes[at] = 255
			seen_count += 1
			var mask: int = 0
			for c in candidates:
				var cd: Dictionary = c as Dictionary
				if absf(float(tx) + 0.5 - float(cd["x"])) > float(cd["magnitude"]) + 1.0 or absf(float(ty) + 0.5 - float(cd["y"])) > float(cd["magnitude"]) + 1.0:
					continue
				if bool((cd["cast"] as Object).call("has_tile", tx, ty)):
					mask |= 1 << int(cd["bit"])
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
# content `beam` of the light a body carries, pointed where that body faces. Only a carried light
# has a facing to point along, so a lamp planted in the yard is round whatever its content says.
# Presentation only -- the sim lights the whole cast either way, and outside the beam the light map
# draws it as the halo, which is less light than the sim's, never more.
static func source_beam(world: Variant, source: int) -> float:
	if world == null or world.components == null or source < 0:
		return 0.0
	if not world.components.has_component(source, "equipment") or not world.components.has_component(source, "facing"):
		return 0.0
	var light: Variant = _source_light_block(world, source)
	if not light is Dictionary:
		return 0.0
	var beam: Variant = (light as Dictionary).get("beam")
	if not (beam is float or beam is int) or not (float(beam) > 0.0):
		return 0.0
	return deg_to_rad(minf(90.0, float(beam)))


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


static func _facing_of(world: Variant, entity: int) -> float:
	var facing: Variant = world.components.get_component(entity, "facing")
	return float((facing as Dictionary).get("radians", 0.0)) if facing is Dictionary else 0.0
