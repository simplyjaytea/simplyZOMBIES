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

# Metres of remaining reach that split a pool's near half from its far half. Straight off the
# frozen renderer's LIGHT_OVERLAY_SPLIT: the near half of a lamp's pool is where a body is worth
# looking at and the far half is where one is a shape.
const POOL_SPLIT_METRES: float = 3.0


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
	if world == null or eyes < 0 or world.light == null or world.vision == null:
		return {"near": near, "far": far}
	var seen: Variant = world.vision.tiles_for(eyes)
	if seen == null:
		return {"near": near, "far": far}
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
	return {"near": near, "far": far}


static func _tick_of(world: Variant) -> int:
	if world == null:
		return 0
	if world is Dictionary:
		return int((world as Dictionary).get("tick", 0))
	return int(world.tick)
