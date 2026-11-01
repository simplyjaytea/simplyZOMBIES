class_name SimSpace
extends RefCounted
# The first-person spatial authority, slice 1 of docs/40 ("The profile, drawn"). Pure and static: no
# state, no RNG, and nothing in the sim calls it yet (slice 2 starts that). It owns two things:
#
#   PROFILE   for each tile class, overlay kind and stage, the height bands the tile occupies, in
#             integer millimetres over a full-tile footprint. Each band names the purposes it stops
#             (movement, sight, shot, reach). The presentation builds its geometry from this table
#             and from nothing else, so what the screen draws is what the sim will trace.
#   body_of / eye_of   the cylinder a body occupies and the eye height it looks from, read from the
#             stance (survivors) or the zombie's state (zombies). Millimetres, as integers.
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
