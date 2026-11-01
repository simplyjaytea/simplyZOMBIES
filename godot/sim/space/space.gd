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
#             `chest_of` is the point on that cylinder an NPC looks at when it turns to a body.
#   segment_clear   whether a segment between two points passes every band that stops a purpose.
#   sight_clear     the vertical half of sight: the same walk, counting only the partial-height tiles
#             (SIGHT_PARTIAL) the standing 2D cast cannot judge. `SimVisibility.detail` and
#             `detail_body` ask it (docs/40, "Perception").
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
# The chest, in thousandths of a cylinder's height: one of the two points a blow may arrive at
# (below), and where an NPC looks when it turns to a body (`chest_of`, the aim's pitch in
# `npc_combat._face_at`, docs/40 slice 3).
const CHEST_PERMILLE: int = 750
# Where on the target's axis a blow may arrive, in thousandths of its cylinder height: the
# mid-height docs/40 names, and the chest. A reach clears if either point does. The second point is
# what makes docs/40's own claim true: a standing survivor's shoulder (1220) to a zombie's
# mid-height (825) dips under a window's 1000 mm sill before it reaches the far side of the tile, so
# with mid-height alone no swing through a window could ever land. The chest (1237 on a zombie) is
# level with the shoulder and passes the aperture; a crouched shoulder (550) still meets the sill.
# docs/30, "The reach arrives at the chest as well as the middle".
const REACH_TARGET_PERMILLE: Array[int] = [500, CHEST_PERMILLE]

# One tile in millimetres, the unit the segment walk is decided in.
const TILE_MM: int = SimTileMap.TILE_METRES * 1000


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


## The chest height of a body in millimetres: CHEST_PERMILLE of its cylinder. An entity of -1 is a
## place rather than a body, and reads as a standing survivor's chest.
static func chest_of(world: Variant, entity: int) -> int:
	var height: int = int(body_of(world, entity)["height"]) if entity >= 0 else int(SURVIVOR_HEIGHT_MM["walk"])
	@warning_ignore("integer_division")
	return height * CHEST_PERMILLE / 1000


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
## Both points are taken to the nearest millimetre, and from there every decision is made in integers:
## the 2D segment is walked tile by tile (the Amanatides-Woo traversal), each tile edge it crosses is a
## rational t = n/d along it, and which edge comes first, whether two come at once (a corner), and
## whether a band is in the way are all decided by cross-multiplying those integers. No float
## comparison decides a boundary (docs/37), so a segment and the same segment written backwards or
## reflected walk the same tiles. A band stops the segment when its heights and the segment's heights
## inside the tile overlap strictly: touching a band's top or bottom face is passing it, so a line
## level with a 1000 mm sill clears it.
##
## The two tiles holding the endpoints are where the bodies stand, and a body is not obstructed by
## the ground it is standing on: they are skipped unless they stop movement (a point inside a wall is
## inside the wall). That is the shadowcast's own convention, where the observer's tile and the
## tile seen are both visible.
##
## Where the segment passes exactly through a tile corner, both tiles beside the corner are tested
## at that one height, so a line cannot slip between two walls that meet diagonally. The traversal
## runs from the lesser endpoint to the greater, so swapping `a` and `b` is the same walk.
static func segment_clear(map: Variant, a: Dictionary, b: Dictionary, purpose: int) -> bool:
	if purpose & (SIGHT | SHOT | REACH) == 0:
		push_error("SimSpace.segment_clear: purpose %d is not SIGHT, SHOT or REACH" % purpose)
		return false
	return _walk(map, a, b, purpose, false)


## The vertical half of sight (docs/40, "Perception"): whether the segment from `a` to `b` passes the
## SIGHT bands of every partial-height tile it crosses -- Low, a window, a stage-3 board, an open
## door's lintel (`SIGHT_PARTIAL`). A tile that stops sight over its whole height, or not at all, is
## the 2D layer's to answer: the standing shadowcast already decided it, tile-centre to tile-centre,
## and this walk does not decide it a second time by a different rule. So `sight_clear` is
## `segment_clear(..., SIGHT)` with only the partial tiles counted, and it is the same integer walk:
## a tile that is not partial is passed on one byte read, and an open street pays nothing else.
## `SimVisibility.detail` and `detail_body` ask it after their tile, range, light and arc tests pass.
static func sight_clear(map: Variant, a: Dictionary, b: Dictionary) -> bool:
	# A world with no tile map (an R1 fixture) holds full-height walls and open floor, nothing partial.
	if not map is SimTileMap:
		return true
	# The standing broadphase: a line that stays between SIGHT_OPEN_FROM_MM and SIGHT_OPEN_TO_MM over
	# its whole length cannot strictly overlap any partial tile's sight band, wherever it runs, so it
	# needs no walk. Every pair of standing bodies is such a line -- a survivor's eye at 1620 and
	# chest at 1312, a zombie's at 1450 and 1237 -- so only a crouched or crawling eye or body walks.
	var ha: int = int(a.get("h", 0))
	var hb: int = int(b.get("h", 0))
	if mini(ha, hb) >= SIGHT_OPEN_FROM_MM and maxi(ha, hb) <= SIGHT_OPEN_TO_MM:
		return true
	return _walk(map, a, b, SIGHT, true)


## The profile keys whose SIGHT bands are partial: some band stops sight, and the bands do not stop it
## over the whole height from the floor to the top of a wall. `sight_partial` derives the same set from
## PROFILE, and `check_m2_sight.gd` HEIGHT holds the two equal, so a row added to the table cannot be
## missed here.
const SIGHT_PARTIAL: Dictionary = {"window": true, "low": true, "door.open": true, "board:3": true}
## The tile classes whose own key (no overlay) is in SIGHT_PARTIAL, indexed by `SimTileMap.Tile`:
## Window, Low and Door (a Door tile with no overlay is an open doorway). An overlay outranks it.
const SIGHT_PARTIAL_CLASS: Array[bool] = [false, false, true, false, true, false, true, false]
## The height of a wall, the top of every full-height band in PROFILE.
const FULL_MM: int = 2550
## The open corridor through every partial tile at once: no SIGHT band of a SIGHT_PARTIAL key reaches
## above 1100 from below (Low and a stage-3 board top out there, a sill at 1000), and none starts below
## 2100 from above (a window's lintel; a door's at 2200). `sight_clear`'s broadphase; HEIGHT holds it
## to PROFILE band by band.
const SIGHT_OPEN_FROM_MM: int = 1100
const SIGHT_OPEN_TO_MM: int = 2100


## Whether a profile key's SIGHT bands are partial, derived from PROFILE: a SIGHT band exists, and the
## SIGHT bands do not cover the whole of 0..FULL_MM.
static func sight_partial(key: String) -> bool:
	var covered: int = 0
	var any: bool = false
	for band in bands(key):
		var bnd: Array = band as Array
		if int(bnd[2]) & SIGHT == 0:
			continue
		any = true
		if int(bnd[0]) <= 0 and int(bnd[1]) >= FULL_MM:
			covered = FULL_MM
	return any and covered < FULL_MM


## The two points a body is seen at, in millimetres: its eye (the head) and its chest. A body is seen
## if either clears (docs/40). The head point is the eye, so the head test is symmetric: A sees B's
## head exactly when B sees A's (docs/30, "A body is seen at its eye and its chest").
static func sight_points(world: Variant, entity: int) -> Array[int]:
	var volume: Dictionary = _volume(world, entity)
	var height: int = int(volume["height"])
	@warning_ignore("integer_division")
	return [int(volume["eye"]), height * CHEST_PERMILLE / 1000]


static func _walk(map: Variant, a: Dictionary, b: Dictionary, purpose: int, partial_only: bool) -> bool:
	var p: Array[int] = _mm_point(a)
	var q: Array[int] = _mm_point(b)
	if _after(p, q):
		var swap: Array[int] = p
		p = q
		q = swap
	var ax: int = p[0]
	var ay: int = p[1]
	var ah: int = p[2]
	var rise: int = q[2] - ah
	var dx: int = q[0] - ax
	var dy: int = q[1] - ay
	var tx: int = _tile_of(ax)
	var ty: int = _tile_of(ay)
	var ends: Array[int] = [tx, ty, _tile_of(q[0]), _tile_of(q[1])]
	var step_x: int = signi(dx)
	var step_y: int = signi(dy)
	var den_x: int = absi(dx)
	var den_y: int = absi(dy)
	# How far along each axis, in millimetres, the next tile edge lies; it is crossed at t = num / den.
	var num_x: int = 0
	var num_y: int = 0
	if step_x > 0:
		num_x = (tx + 1) * TILE_MM - ax
	elif step_x < 0:
		num_x = ax - tx * TILE_MM
	if step_y > 0:
		num_y = (ty + 1) * TILE_MM - ay
	elif step_y < 0:
		num_y = ay - ty * TILE_MM
	var in_n: int = 0
	var in_d: int = 1
	# `sight_clear`'s walk reads the class byte of each tile it enters straight off the map's arrays,
	# and builds a key and asks the bands only where the tile is partial: an open street is a byte read
	# a tile, with no call (`_sight_partial_at` is the same answer, for the corner tiles below).
	var mw: int = 0
	var mh: int = 0
	var tiles: PackedByteArray = PackedByteArray()
	var overlays: Dictionary = {}
	if partial_only:
		mw = int(map.w)
		mh = int(map.h)
		tiles = map.tiles
		if map.overlays is Dictionary:
			overlays = map.overlays
	var has_overlays: bool = not overlays.is_empty()
	# An exact integer walk visits at most one tile per edge crossed, plus the first.
	for _i in absi(ends[2] - tx) + absi(ends[3] - ty) + 1:
		var at_end: bool = tx == ends[2] and ty == ends[3]
		# 0: the segment ends in this tile. 1: it leaves across an x edge. 2: a y edge. 3: a corner.
		var leaves: int = 0
		if not at_end:
			if step_x != 0 and step_y != 0:
				var order: int = num_x * den_y - num_y * den_x
				leaves = 1 if order < 0 else (2 if order > 0 else 3)
			elif step_x != 0:
				leaves = 1
			else:
				leaves = 2
			# An edge at or past t = 1 is beyond the segment's end, which then lies in this tile.
			if (leaves != 2 and num_x >= den_x) or (leaves == 2 and num_y >= den_y):
				leaves = 0
		var out_n: int = 1
		var out_d: int = 1
		if leaves == 1 or leaves == 3:
			out_n = num_x
			out_d = den_x
		elif leaves == 2:
			out_n = num_y
			out_d = den_y
		var ask: bool = true
		if partial_only:
			ask = false
			if tx >= 0 and ty >= 0 and tx < mw and ty < mh:
				var idx: int = ty * mw + tx
				if has_overlays and overlays.has(idx):
					ask = SIGHT_PARTIAL.has(profile_key(map, tx, ty))
				else:
					ask = SIGHT_PARTIAL_CLASS[tiles[idx]]
		if ask and _tile_stops(map, tx, ty, purpose, ah, rise, in_n, in_d, out_n, out_d, ends):
			return false
		if leaves == 0:
			return true
		if leaves == 3:
			if _tile_stops(map, tx + step_x, ty, purpose, ah, rise, out_n, out_d, out_n, out_d, ends, partial_only):
				return false
			if _tile_stops(map, tx, ty + step_y, purpose, ah, rise, out_n, out_d, out_n, out_d, ends, partial_only):
				return false
		if leaves != 2:
			tx += step_x
			num_x += TILE_MM
		if leaves != 1:
			ty += step_y
			num_y += TILE_MM
		in_n = out_n
		in_d = out_d
	# Unreachable: the integer walk always arrives at the end tile within its bound. Refuse rather than
	# pass a segment whose last tile was never tested.
	push_error("SimSpace.segment_clear: the walk from %s to %s ran out before its end tile" % [str(p), str(q)])
	return false


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


# A point in integer millimetres, [x, y, h]: the plane coordinates to the nearest millimetre.
static func _mm_point(point: Dictionary) -> Array[int]:
	return [roundi(float(point["x"]) * 1000.0), roundi(float(point["y"]) * 1000.0), int(point.get("h", 0))]


# The tile a millimetre coordinate lies in: floor division by the tile, in integers.
static func _tile_of(mm: int) -> int:
	@warning_ignore("integer_division")
	var tile: int = (mm - posmod(mm, TILE_MM)) / TILE_MM
	return tile


# The canonical order of two endpoints: x, then y, then height. Ties on all three are one point.
static func _after(a: Array[int], b: Array[int]) -> bool:
	if a[0] != b[0]:
		return a[0] > b[0]
	if a[1] != b[1]:
		return a[1] > b[1]
	return a[2] > b[2]


# Whether tile (tx, ty), crossed between t = n0/d0 and t = n1/d1 (denominators positive), holds a band
# that stops `purpose`. The height at t = n/d is (ah * d + rise * n) / d, so every comparison with a
# band's integer edge is made on whole numbers. The endpoint tiles, `ends` = [sx, sy, ex, ey], count
# only when they stop movement.
# `partial_only` counts only the tiles in SIGHT_PARTIAL (`sight_clear`), and passes every other tile on
# the class byte alone, before any key is built. The walk's own tile is already filtered inline.
static func _tile_stops(map: Variant, tx: int, ty: int, purpose: int, ah: int, rise: int, n0: int, d0: int, n1: int, d1: int, ends: Array[int], partial_only: bool = false) -> bool:
	if partial_only and not _sight_partial_at(map, tx, ty):
		return false
	var tile_bands: Array = bands(_key_at(map, tx, ty))
	if tile_bands.is_empty():
		return false
	if (tx == ends[0] and ty == ends[1]) or (tx == ends[2] and ty == ends[3]):
		var solid: bool = false
		for band in tile_bands:
			if int((band as Array)[2]) & MOVE != 0:
				solid = true
				break
		if not solid:
			return false
	var h0: int = ah * d0 + rise * n0
	var h1: int = ah * d1 + rise * n1
	for band in tile_bands:
		var bnd: Array = band as Array
		if int(bnd[2]) & purpose == 0:
			continue
		var bottom: int = int(bnd[0])
		var top: int = int(bnd[1])
		# Strict overlap: the lower of the two heights is under the band's top, and the higher is over
		# its bottom.
		var under_top: bool = h0 < top * d0 or h1 < top * d1
		var over_bottom: bool = h0 > bottom * d0 or h1 > bottom * d1
		if under_top and over_bottom:
			return true
	return false


# Whether the tile at (tx, ty) of a SimTileMap is partial for sight: the class byte, unless an overlay
# stands there, in which case the overlay's key decides (an overlay outranks the class). Out of bounds
# reads as a wall, which is not partial.
static func _sight_partial_at(map: Variant, tx: int, ty: int) -> bool:
	var mw: int = int(map.w)
	if tx < 0 or ty < 0 or tx >= mw or ty >= int(map.h):
		return false
	var idx: int = ty * mw + tx
	var overlays: Variant = map.overlays
	if overlays is Dictionary and not (overlays as Dictionary).is_empty() and (overlays as Dictionary).has(idx):
		return SIGHT_PARTIAL.has(profile_key(map, tx, ty))
	var tile: int = int(map.tiles[idx])
	return tile >= 0 and tile < SIGHT_PARTIAL_CLASS.size() and SIGHT_PARTIAL_CLASS[tile]


# The profile key at a tile, for either kind of map `map_of` returns.
static func _key_at(map: Variant, tx: int, ty: int) -> String:
	if map is SimTileMap:
		return profile_key(map, tx, ty)
	return "wall" if bool(map.is_blocked_tile(tx, ty)) else "floor"
