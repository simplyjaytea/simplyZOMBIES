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
static func wash_alpha(world: Variant, eyes: int, night_wash: float) -> float:
	var light: float = local_light_fraction(world, eyes)
	if light >= 1.0:
		return 0.0
	return (1.0 - light) * night_wash


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
