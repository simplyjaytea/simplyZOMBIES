class_name SimSpace
extends RefCounted
# The first-person spatial authority, docs/40. Slice 1 ("The profile, drawn") gave it the table and
# the bodies; slice 2 ("The segment") gave it the first question the sim asks of them. Pure and
# static: no state and no RNG. It owns:
#
#   PROFILE   for each tile class, overlay kind and stage, the height bands the tile occupies, in
#             integer millimetres over a full-tile footprint. Each band names the purposes it stops
#             (movement, sight, shot, reach). The presentation builds its geometry from this table
#             and from nothing else, so what the screen draws is what the sim will trace.
#   body_of / eye_of   the cylinder a body occupies and the eye height it looks from, read from the
#             stance (survivors) or the zombie's state (zombies). Millimetres, as integers.
#   segment_clear   whether a segment between two points passes every band that stops a purpose.
#   reach_clear     the reach question in bodies: a blow from the attacker's shoulder to the target.
#             `SimMelee._resolve_strike`, `SimShambler._clear_contact` and `SimNpcCombat.can_strike`
#             all ask it, so a survivor's swing, a zombie's claw and a colonist's walk to the fight
#             have one answer about what is in the way (docs/40, "Melee reach").
#
# Sim x/y are metres on the ground; height is millimetres above the floor at 0. A tile that is solid
# for movement is a full-footprint band from 0 upward, and movement itself stays in
# `SimTileMap.is_solid` until a later slice says otherwise (docs/40, "The one authority").
#
# Where docs/40's table is read as a starting point, the reading is recorded in
# docs/planning/first-person-profile-report.md. The one that matters on screen: a stage-3 board's top
# band (2100-2550) stops movement only, because the table's sight column for that row passes sight
# above 1100.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimStances = preload("res://sim/stances.gd")
const SimHealth = preload("res://sim/modules/health.gd")

# The purposes a band can stop. Movement is the body's footprint; the other three are the ray and
# the eye, and they are different properties (docs/28): a screen stops sight and a shot and passes a
# reach, a wire fence passes sight and a shot and stops a reach.
const MOVE: int = 1
const SIGHT: int = 2
const SHOT: int = 4
const REACH: int = 8
const ALL_STOPS: int = 15

# The cylinder radius for a body, the radius the foundation draws (docs/40, "Body volumes").
const HIT_RADIUS_MM: int = 300

# key -> Array of bands, each band [from_mm, to_mm, stops]. The keys are:
#   floor, water, wall, window, screen, low, tree, door.open (a doorway, or an open door's lintel),
#   door.closed, board:0 .. board:3, scrap, timber, stone, fence.
# A tile with an overlay takes the overlay's key (overlays win over the tile class, which is how
# `SimTileMap.is_solid` and `opacity_at` read them too); a tile without one takes its class's key.
const PROFILE: Dictionary = {
	"floor": [],
	# Deep water blocks movement and nothing above the floor: its surface is drawn below 0.
	"water": [],
	"wall": [[0, 2550, ALL_STOPS]],
	# A window: a sill and a lintel with an open aperture between, which is what passes sight, a shot
	# and a reach (docs/40's table: through 1000-2100).
	"window": [[0, 1000, ALL_STOPS], [2100, 2550, ALL_STOPS]],
	# A screen (curtain, foliage) is walkable, opaque to sight, and does not stop a reach.
	"screen": [[0, 2550, SIGHT | SHOT]],
	# Low: a car, a low wall, rubble. Its top is 1100, above a crouched eye and below a standing one.
	"low": [[0, 1100, SIGHT | SHOT | REACH]],
	"tree": [[0, 2550, ALL_STOPS]],
	# An open door (or a doorway with no door): only the lintel above 2200 is solid, and it stops sight,
	# a shot and a reach but not movement.
	"door.open": [[2200, 2550, SIGHT | SHOT | REACH]],
	"door.closed": [[0, 2550, ALL_STOPS]],
	"board:0": [[0, 2550, ALL_STOPS]],
	"board:1": [[0, 2550, ALL_STOPS]],
	"board:2": [[0, 2550, ALL_STOPS]],
	# Stage 3 is the one the sim reads as Opacity.Low today: sill-height boards, open above 1100.
	"board:3": [[0, 1100, ALL_STOPS], [2100, 2550, MOVE]],
	"scrap": [[0, 2550, ALL_STOPS]],
	"timber": [[0, 2550, ALL_STOPS]],
	"stone": [[0, 2550, ALL_STOPS]],
	# A wire fence: stops movement and a reach, and passes sight and a shot.
	"fence": [[0, 2000, MOVE | REACH]],
}

# The body volumes, from docs/40's body table: eye and cylinder height in millimetres.
const SURVIVOR_EYE_MM: Dictionary = {"walk": 1620, "crouch": 950, "crawl": 300}
const SURVIVOR_HEIGHT_MM: Dictionary = {"walk": 1750, "crouch": 1150, "crawl": 450}
const ZOMBIE_EYE_MM: int = 1450
const ZOMBIE_HEIGHT_MM: int = 1650
const CRAWLER_EYE_MM: int = 300
const CRAWLER_HEIGHT_MM: int = 450

# A blow starts at the attacker's shoulder, this far below its eye (docs/40, "Melee reach").
const SHOULDER_DROP_MM: int = 400
# Where on the target's axis a blow may arrive, in thousandths of its cylinder height: the
# mid-height docs/40 names, and the chest. A reach clears if either point does. The second point is
# what makes docs/40's own claim true: a standing survivor's shoulder (1220) to a zombie's
# mid-height (825) dips under a window's 1000 mm sill before it reaches the far side of the tile, so
# with mid-height alone no swing through a window could ever land. The chest (1237 on a zombie) is
# level with the shoulder and passes the aperture; a crouched shoulder (550) still meets the sill.
# docs/30, "The reach arrives at the chest as well as the middle".
const REACH_TARGET_PERMILLE: Array[int] = [500, 750]


## The profile key of a tile: the overlay's key when it has one, otherwise the tile class's.
static func profile_key(map: Variant, tx: int, ty: int) -> String:
	var ov: Variant = SimTileMap.overlay_at(map, tx, ty)
	if ov is Dictionary:
		var over: Dictionary = ov as Dictionary
		var kind: String = String(over.get("kind", ""))
		if kind == "board":
			return "board:%d" % clampi(int(over.get("stage", 0)), 0, 3)
		if kind == "door":
			return "door.open" if bool(over.get("open", false)) else "door.closed"
		if kind == "scrap" or kind == "timber" or kind == "stone" or kind == "fence":
			return kind
	match SimTileMap.tile_at(map, tx, ty):
		SimTileMap.Tile.Wall:
			return "wall"
		SimTileMap.Tile.Window:
			return "window"
		SimTileMap.Tile.Screen:
			return "screen"
		SimTileMap.Tile.Low:
			return "low"
		SimTileMap.Tile.Tree:
			return "tree"
		SimTileMap.Tile.Door:
			# A Door tile with no overlay is an open doorway (docs/37, the door's class note).
			return "door.open"
		SimTileMap.Tile.Water:
			return "water"
	return "floor"


## The bands of a profile key, each [from_mm, to_mm, stops]. An unknown key has no bands.
static func bands(key: String) -> Array:
	var found: Variant = PROFILE.get(key, [])
	return found as Array if found is Array else []


## The vertical cylinder a body occupies: {"radius": mm, "height": mm}. A survivor's height follows
## its stance rung; a zombie's follows whether its legs still work (docs/14's crawler).
static func body_of(world: Variant, entity: int) -> Dictionary:
	return {"radius": HIT_RADIUS_MM, "height": int(_volume(world, entity)["height"])}


## The eye height of a body in millimetres, from its stance or its zombie state.
static func eye_of(world: Variant, entity: int) -> int:
	return int(_volume(world, entity)["eye"])


static func _volume(world: Variant, entity: int) -> Dictionary:
	var components: Variant = world.components
	if components.has_component(entity, "zombieType"):
		var body: Variant = components.get_component(entity, "body")
		if body is Dictionary and SimHealth.is_crawling(body as Dictionary):
			return {"eye": CRAWLER_EYE_MM, "height": CRAWLER_HEIGHT_MM}
		return {"eye": ZOMBIE_EYE_MM, "height": ZOMBIE_HEIGHT_MM}
	var stance: int = SimStances.stance_of(components, entity)
	var rung: String = "crawl"
	if stance == SimStances.Stance.Crouch:
		rung = "crouch"
	elif stance != SimStances.Stance.Crawl:
		rung = "walk"
	return {"eye": int(SURVIVOR_EYE_MM[rung]), "height": int(SURVIVOR_HEIGHT_MM[rung])}


## The map a world's spatial questions read: its tile map when it has adopted one, and otherwise the
## world itself, whose `map_cells` wall list is all the geometry an R1 fixture world has. A wall-list
## cell reads as a full-height wall and every other cell as open floor (`_key_at`).
static func map_of(world: Variant) -> Variant:
	var tilemap: Variant = world.tilemap
	return tilemap if tilemap != null else world


## Whether the segment from `a` to `b` passes every band that stops `purpose` (SIGHT, SHOT or REACH).
## Each point is {"x": metres, "y": metres, "h": millimetres above the floor}. `map` is a SimTileMap,
## or a world without one (see `map_of`).
##
## The 2D segment is walked tile by tile in integer steps (the Amanatides-Woo traversal), and inside
## each tile it crosses the segment's height runs between its two crossing heights, one
## interpolation per tile. A band stops the segment when the two overlap strictly: touching a band's
## top or bottom face is passing it, so a line level with a 1000 mm sill clears it.
##
## The two tiles holding the endpoints are where the bodies stand, and a body is not obstructed by
## the ground it is standing on: they are skipped unless they stop movement (a point inside a wall is
## inside the wall). That is the shadowcast's own convention, where the observer's tile and the
## tile seen are both visible.
##
## Where the segment passes exactly through a tile corner, both tiles beside the corner are tested
## at that one height, so a line cannot slip between two walls that meet diagonally. The traversal
## always runs from the lesser endpoint to the greater, so swapping `a` and `b` gives the same
## answer by construction rather than by luck.
static func segment_clear(map: Variant, a: Dictionary, b: Dictionary, purpose: int) -> bool:
	if purpose & (SIGHT | SHOT | REACH) == 0:
		push_error("SimSpace.segment_clear: purpose %d is not SIGHT, SHOT or REACH" % purpose)
		return false
	var p: Dictionary = a
	var q: Dictionary = b
	if _after(a, b):
		p = b
		q = a
	var ax: float = float(p["x"])
	var ay: float = float(p["y"])
	var ah: float = float(int(p.get("h", 0)))
	var bx: float = float(q["x"])
	var by: float = float(q["y"])
	var rise: float = float(int(q.get("h", 0))) - ah
	var tx: int = floori(ax)
	var ty: int = floori(ay)
	var sx: int = tx
	var sy: int = ty
	var ex: int = floori(bx)
	var ey: int = floori(by)
	var dx: float = bx - ax
	var dy: float = by - ay
	var step_x: int = 1 if dx > 0.0 else (-1 if dx < 0.0 else 0)
	var step_y: int = 1 if dy > 0.0 else (-1 if dy < 0.0 else 0)
	var t_max_x: float = INF
	var t_max_y: float = INF
	var t_delta_x: float = INF
	var t_delta_y: float = INF
	if step_x != 0:
		t_max_x = (float(tx + 1 if step_x > 0 else tx) - ax) / dx
		t_delta_x = 1.0 / absf(dx)
	if step_y != 0:
		t_max_y = (float(ty + 1 if step_y > 0 else ty) - ay) / dy
		t_delta_y = 1.0 / absf(dy)
	var t_in: float = 0.0
	# A segment crosses at most one tile per unit step on each axis; the bound only guards against a
	# traversal that float error has walked past its end.
	var guard: int = absi(ex - tx) + absi(ey - ty) + 2
	while guard > 0:
		guard -= 1
		var at_end: bool = tx == ex and ty == ey
		var t_out: float = 1.0 if at_end else minf(minf(t_max_x, t_max_y), 1.0)
		if _tile_stops(map, tx, ty, purpose, ah + rise * t_in, ah + rise * t_out, sx, sy, ex, ey):
			return false
		if at_end or t_out >= 1.0:
			return true
		if t_max_x < t_max_y:
			tx += step_x
			t_in = t_max_x
			t_max_x += t_delta_x
		elif t_max_y < t_max_x:
			ty += step_y
			t_in = t_max_y
			t_max_y += t_delta_y
		else:
			# Exactly through a corner: the two tiles beside it are touched at one height.
			var h_corner: float = ah + rise * t_max_x
			if _tile_stops(map, tx + step_x, ty, purpose, h_corner, h_corner, sx, sy, ex, ey):
				return false
			if _tile_stops(map, tx, ty + step_y, purpose, h_corner, h_corner, sx, sy, ex, ey):
				return false
			tx += step_x
			ty += step_y
			t_in = t_max_x
			t_max_x += t_delta_x
			t_max_y += t_delta_y
	return true


## Whether a blow from `attacker` standing at `from` arrives at `target` standing at `to`: the segment
## from the attacker's shoulder (its eye less SHOULDER_DROP_MM) to the target's mid-height or its
## chest (REACH_TARGET_PERMILLE) passes every band that stops a reach. Distance and arc are the
## caller's; this answers only what is in the way. An entity of -1 is a body the caller cannot name
## (a bare position): a zombie's shoulder, and a standing survivor's height.
static func reach_clear(world: Variant, from: Dictionary, to: Dictionary, attacker: int = -1, target: int = -1) -> bool:
	var map: Variant = map_of(world)
	var eye: int = eye_of(world, attacker) if attacker >= 0 else ZOMBIE_EYE_MM
	var a: Dictionary = {"x": float(from["x"]), "y": float(from["y"]), "h": maxi(0, eye - SHOULDER_DROP_MM)}
	var height: int = int(body_of(world, target)["height"]) if target >= 0 else int(SURVIVOR_HEIGHT_MM["walk"])
	for permille in REACH_TARGET_PERMILLE:
		@warning_ignore("integer_division")
		var h: int = height * int(permille) / 1000
		if segment_clear(map, a, {"x": float(to["x"]), "y": float(to["y"]), "h": h}, REACH):
			return true
	return false


# The canonical order of two endpoints: x, then y, then height. Ties on all three are one point.
static func _after(a: Dictionary, b: Dictionary) -> bool:
	if float(a["x"]) != float(b["x"]):
		return float(a["x"]) > float(b["x"])
	if float(a["y"]) != float(b["y"]):
		return float(a["y"]) > float(b["y"])
	return int(a.get("h", 0)) > int(b.get("h", 0))


# Whether tile (tx, ty), crossed between heights h0 and h1, holds a band that stops `purpose`. The
# endpoint tiles (sx, sy) and (ex, ey) count only when they stop movement.
static func _tile_stops(map: Variant, tx: int, ty: int, purpose: int, h0: float, h1: float, sx: int, sy: int, ex: int, ey: int) -> bool:
	var tile_bands: Array = bands(_key_at(map, tx, ty))
	if tile_bands.is_empty():
		return false
	if (tx == sx and ty == sy) or (tx == ex and ty == ey):
		var solid: bool = false
		for band in tile_bands:
			if int((band as Array)[2]) & MOVE != 0:
				solid = true
				break
		if not solid:
			return false
	var lo: float = minf(h0, h1)
	var hi: float = maxf(h0, h1)
	for band in tile_bands:
		var bnd: Array = band as Array
		if int(bnd[2]) & purpose == 0:
			continue
		if lo < float(int(bnd[1])) and hi > float(int(bnd[0])):
			return true
	return false


# The profile key at a tile, for either kind of map `map_of` returns.
static func _key_at(map: Variant, tx: int, ty: int) -> String:
	if map is SimTileMap:
		return profile_key(map, tx, ty)
	return "wall" if bool(map.is_blocked_tile(tx, ty)) else "floor"
