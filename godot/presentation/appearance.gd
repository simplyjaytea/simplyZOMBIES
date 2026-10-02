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
# Sprites are optional: `resolve` returns null for a key with no file, and every caller falls
# back to the procedural shapes -- the fallback is a supported path, not a temporary one, and
# check_appearance.gd asserts it stays that way. Every shipped body, prop and street key has
# art today, authored on the ART_NATIVE (32 px) centre-anchored canvas camera.gd names.

const Palette = preload("res://presentation/palette.gd")
const ItemGlyph = preload("res://presentation/item_glyph.gd")
const CameraUtil = preload("res://presentation/camera.gd")
const SimSurface = preload("res://sim/map/surface.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimClock = preload("res://sim/time/clock.gd")

const SPRITE_DIR: String = "res://assets/sprites"

# The content id the player's own body resolves its look from.
#
# Every other body on screen carries an id already: a zombie hands over its type id, a unique
# survivor its identity (or rolled `look`) id, a raider its archetype id. The player carries none
# of the three, so `for_entity` had nothing to look up and the shipped game had no player art at
# all -- which is what the style fixtures turned up. This constant is the one place the id is
# named, so `main.gd` still contains no `if id == ...` (the same rule PROP_KINDS follows).
#
# It lives under content/players/, not content/survivors/: survivor.schema.json pins ids to
# ^survivor\.unique\. and `SimSurvivors.list_uniques` boots everything in that directory, so an
# entry there would both fail the frozen oracle's Ajv and spawn a phantom colonist.
const PLAYER_LOOK_ID: String = "player.body"

# The pawn canvas: one ART_NATIVE tile wide and one and a quarter tall, anchored on the feet
# (assets/sprites/README.md). The squat proportion the owner picked on 2026-09-08 (docs/30,
# "Overcast or torchlight"): a person about 0.7 of a tile wide and *one tile* tall, the RimWorld
# and Zero Sievert read, with three or more pixels of side margin so the flip never clips and ten
# rows of headroom for a helmet or a spear tip. Its blit height is 1.25 x zoom, an integer on
# every rung of the ladder (20/40/80/160). The 32x48 canvas of 2026-09-03 held a 1.3-tile figure;
# it was superseded, not resized -- every rig was re-authored on a shorter published skeleton.
# The two generated bodies the outpost pack does not supply are authored on it (PAWN_KEYS);
# tools/sprites/build.py carries the mirror list, because Python cannot read GDScript. The outpost
# pack's four-direction bodies and wearables stand on it too, cropped from the pack's 32x48 on its
# own anchor row, but they are declared in authored.json rather than named here -- one key, one
# tier. Since "The bodies turn and walk" (2026-09-26) the generated rigs are the screamer and the
# bloater only, and since "Pack gear on the body" the same day nothing else generated is drawn on a
# body either: the 43 face-on equip overlays and the three fitted-part pictures were deleted with
# their generator (docs/30, "The whole outpost pack").
const PAWN_CANVAS: Vector2i = Vector2i(int(CameraUtil.ART_NATIVE), int(CameraUtil.ART_NATIVE) * 5 / 4)
const PAWN_KEYS: Array[String] = ["zombie_screamer", "zombie_bloater"]

# Where a picture hangs on its entity's ground point. A square canvas is a tile-sized thing seen
# from above and centres on the point; anything else is a standing picture and stands on it --
# derived from the shape rather than from a second list of keys, so the tree and vehicle sheets
# the later slices add are feet-anchored by construction (a second list is the dead-socket
# family: one entry forgotten and a picture floats half a tile high without ever erroring).
enum Anchor { Centre = 0, Feet = 1 }

# How far below the ground point the soles stand, in screen pixels: the contact shadow's own
# offset, which main.gd draws at exactly this drop, so the shadow line and the sole line are one
# number and cannot drift apart. A screen-pixel constant on purpose, like the facing line's +12:
# a readout of the interface, not a length in the world.
const FOOT_DROP_PX: float = 3.0

# Equipment slots the renderer draws on a body, in the one order they compose, each saying
# which side of the body draw call it goes on. One table rather than an under list and an over
# list: the order layers compose in *is* the picture, and two lists could only express it by
# their concatenation, which put every over-body slot after every under-body one whether or not
# that was the intent. A slot absent from this table stays declarable in content
# (item.schema.json) but is silently not drawn -- extending it is a renderer change, not a
# content one, because a new slot needs a decision about where in this order it sits.
#
# Only `back` goes under: a pack hangs behind the body. Clothing covers the body it is worn on,
# and a held weapon is in front of the hand holding it, so everything else is over. `vest` and
# `face` joined on 2026-09-26 with the outpost pack's four-direction vest and gas mask ("The
# bodies turn and walk"), and where they sit is the pack's own answer rather than a guess: its
# manifest layers vest 2, backpack 3, gas mask 4 and helmet 5 over the body at 0, so `vest` comes
# before `back` and `face` before `head`. An under-body layer draws in the under pass wherever its
# slot sits here. `belt`, `feet`, `gloves` and `eyes` are equippable in content and still
# deliberately not here; an `appearance.equipSprite` on one of those four is a socket nothing
# reads, which is why content declares none.
#
# Since "Pack gear on the body" (2026-09-26) every picture drawn here says which side of the body
# it is on in each view, and `over` is the slot's side where the picture does not: a wearable
# family's per-view `z` decides for it (`layer_over`, which falls back to `over` for a view its
# `z` does not list), and a held weapon goes over only when both this slot and the hand holding
# it in that view say so (`HELD_BEHIND`) -- the far hand, or a body seen from behind, hides it.
const EQUIP_DRAW_ORDER: Array[Dictionary] = [
	{"slot": "legs", "over": true},
	{"slot": "torso", "over": true},
	{"slot": "vest", "over": true},
	{"slot": "back", "over": false},
	{"slot": "primary", "over": true},
	{"slot": "secondary", "over": true},
	{"slot": "face", "over": true},
	{"slot": "head", "over": true},
]

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
	# A family that turns is one declaration and many pictures, and the key content names is the
	# family's. Asked for as one picture it answers the one a body at rest shows, facing south and
	# standing still; `frame_key` below is how the draw loop asks for any other.
	if texture == null and turns(key):
		texture = resolve("%s_%s" % [key, VIEW_REST])
	_cache[key] = texture
	return texture


# Clears the texture cache. For gates that probe resolution with and without files present.
static func forget() -> void:
	_cache.clear()
	# The authored declaration goes with the textures: a gate that swaps the file on disk and
	# then asks `canvas_of` again would otherwise get the answer from before the swap, which is
	# the whole failure mode a cache invalidation exists to prevent.
	_authored.clear()
	_authored_rigs.clear()
	_families.clear()
	_held.clear()
	_muzzles.clear()
	_sheets.clear()
	_authored_read = false


# What the ground under a tile looks like: docs/24's surface layer, resolved to a flat tint.
#
# The map carries two independent arrays over one grid -- what is *in* a tile (the occluder
# classes, docs/28) and what is *under* it (this) -- so the ground is never a tile type and
# never a branch on one. `_draw_district` fills with this and then draws whatever the tile
# itself is on top; a tree stands on grass and rubble lies on tarmac because the two layers
# are asked separately.
#
# Out of bounds resolves to Paved, because SimSurface.surface_at says so -- the edge of the
# map reads as street rather than as a hole, which is the same answer the sim gives a body
# walking off the edge.
static func ground_colour(map: Variant, tx: int, ty: int) -> Color:
	if map == null:
		return Palette.COLOURS["floor"]
	var surface: int = int(SimSurface.surface_at(map, tx, ty))
	if surface < 0 or surface >= Palette.SURFACE_TINTS.size():
		return Palette.COLOURS["floor"]
	return Palette.SURFACE_TINTS[surface]


# Snow lying on the ground: the weather-look slice's regrade, docs/16 and the owner's
# 2026-09-06 "snow that lies as well as falls". `cover` is `SimWeather.snow_cover`'s own
# fraction (already clamped [0,1]) times `Palette.SNOW_COVER_MAX`, so the surface tint still
# shows through a drift. A `Color.lerp` at weight 0.0 returns its receiver unchanged, which is
# why cover 0.0 is byte-identical to today's ground -- check_topdown.gd's GROUND lane pins that
# identity and check_weather.gd's COVER lane proves it here, on this pure function, rather than
# on the caller only a running CanvasItem can exercise. The caller decides indoors -- this
# function does not read the map at all -- the same split `indoor_floor` below leaves to its own
# caller.
static func ground_with_snow(ground: Color, cover: float) -> Color:
	return ground.lerp(Palette.COLOURS["snow"], clampf(cover, 0.0, 1.0) * Palette.SNOW_COVER_MAX)


# What a floor tile looks like once it is known to be inside a building.
#
# `indoors` is a third array over the same grid -- docs/24's surface layer is the second -- so an
# interior is no more a tile type than the ground is. The floor keeps the surface it stands on and
# is pulled towards the board colour by INDOOR_MIX: a shop floored on rubble and a house floored
# on paving stay different floors, while both read as inside from across the street. Out of bounds
# and a null map both answer "outdoors", which is what `SimTileMap.is_indoors` says too.
static func indoor_floor(map: Variant, tx: int, ty: int, col: Color) -> Color:
	if map == null or not SimTileMap.is_indoors(map, tx, ty):
		return col
	return col.lerp(Palette.COLOURS["indoorFloor"], Palette.INDOOR_MIX)


# --- the ground atlas ------------------------------------------------------------------------
#
# One atlas for every floor: GROUND_VARIANTS cells across and one row per ground the renderer
# knows -- rows 0..5 mirror SimSurface.Surface, then the two substitutions the draw loop makes,
# the sidewalk paint and the indoor boards. Since "The ground is the pack's" (docs/23, 2026-09-27)
# every cell is a whole picture from the outpost pack, laid out by `authored.json`'s `cells`
# source and reproduced by `sprites:check`: asphalt, dirt, grass, rubble, water, concrete and
# the wood floor, with undergrowth the grass tile under all four of the pack's grass fringes and
# the second rubble cell the rubble tile under its debris overlay. The palette row tints are the
# pack's own measured means (`Palette.SURFACE_TINTS`, docs/30 "The whole outpost pack": the ground
# takes the pack's own grade), so the blit's modulate -- `flat / row tint` -- is the identity on
# a plain outdoor tile and the pack draws as it was painted. The indoor mix, the sidewalk
# substitution and the position-hash variation still survive as tints over the picture, which is
# what keeps the flat fallback (zoomed out, or no atlas) the same colour as the picture it stands
# in for. Which cell a tile draws is a hash the drawing node takes through Dressing
# (SALT_GROUND); this file cannot preload dressing.gd, which preloads it.
const GROUND_ATLAS_KEY: String = "ground_atlas"
# Two, because the pack paints two of each ground it has two of (asphalt, dirt, grass, concrete)
# and one of the rest. Rubble's second cell is the tile under the pack's debris overlay; water and
# the boards repeat their one picture, which `check_road_look.gd`'s TEXTURE lane names rather
# than refuses (ONE_PICTURE_ROWS). The generated atlas carried four until 2026-09-27.
const GROUND_VARIANTS: int = 2
# The first six rows are `SimSurface.Surface` verbatim, because `ground_row_for` below returns a
# surface int *as* a row and that identity is the whole reason this atlas is cheap. So the two
# painted substitutions have to sit **after** the last surface, and adding a surface moves them:
# water arriving as Surface 5 pushed Sidewalk to 6 and Boards to 7. Before that move a water tile
# drew the sidewalk row and `ground_row_tint` handed back the sidewalk paint -- a river paved,
# silently, with every gate green. If a seventh surface is ever added, these two move again.
enum GroundRow { Paved = 0, Dirt = 1, Grass = 2, Undergrowth = 3, Rubble = 4, Water = 5, Sidewalk = 6, Boards = 7 }
const GROUND_ROWS: int = 8
# The edge cells: four more columns to the right of the variants, one fringe per side of a tile.
# In the atlas rather than on a sheet of their own because the edge is blitted right after the
# floor it lies on, and a second texture between two floor blits breaks the batch on every
# boundary tile (measured in the edges slice; docs/23). EdgeShape's order is the column order, N
# first. The pack paints a fringe for grass alone, one per side and none for a corner, so only
# the FRINGE_ROWS carry edge cells -- the pack's four grass fringes, on both green rows -- and
# every other row's four are transparent and never answered by `edge_shapes`. The generated atlas
# carried a fringe per row and per outer corner, eight a row, until 2026-09-27.
enum EdgeShape { N = 0, E = 1, S = 2, W = 3 }
const EDGE_SHAPES: int = 4
const FRINGE_ROWS: Array[int] = [GroundRow.Grass, GroundRow.Undergrowth]
# What a tile with no ground reads as in the per-map row cache (a wall, a window, a screen, a
# tree): it takes no edge and gives none, so a floor beside a wall keeps its own colour to the
# wall's foot, where the wall's own picture is the edge.
const ROW_NONE: int = 255
# The trees are the outpost pack's since 2026-09-26 (docs/23, "Trees, the bed and the heaps"), so
# they have no canvas rule here: each is an authored key of kind `tree`, cropped to the pack's
# anchor row, and `canvas_of` answers its own declared size. A canopy is no longer one tile wide
# (docs/30, "The outpost pack, adopted", amends "one tile wide"), which is why there is no single
# tree canvas to name -- the pine and the dead tree are 64 across, the broadleaf 80. `Dressing`'s
# `trees.tall` list is the one place a tree key is named.

# The vehicles: one three-quarter picture per class x variant x axis (docs/30, the Dungeon
# Settlers look, decision 11). A car seen from the side is a different picture, not a rotation,
# so a variant has two keys and no per-tile segments; the picture stands feet-anchored on its
# footprint's south-edge centre and y-sorts with the bodies, exactly as a tree does.
#
# The canvas is derived rather than tabled, because a class has a length and slice 11's van and
# truck have different ones: it is the footprint plus one tile of roofline north, which is the
# room a three-quarter picture needs to lean up-canvas from the base it stands on. An unknown
# class, variant or axis answers ZERO, which falls through to the tile canvas below and is what
# refuses a fabricated file at check_appearance.gd's canvas lane.
const VEHICLE_PREFIX: String = "vehicle_"
const VEHICLE_ROOFLINE_TILES: int = 1
# The light classes stand one tile across: a bicycle, an e-bike and an e-scooter are 1x2, a
# kick scooter and a skateboard 1x1, so their pictures are 32x96 / 64x64 and 32x64 / 32x64.
const VEHICLE_FOOTPRINTS: Dictionary = {
	"sedan": Vector2i(2, 5), "van": Vector2i(2, 6), "truck": Vector2i(2, 7),
	"bicycle": Vector2i(1, 2), "ebike": Vector2i(1, 2), "escooter": Vector2i(1, 2),
	"kickscooter": Vector2i(1, 1), "skateboard": Vector2i(1, 1),
}
const VEHICLE_VARIANTS: Array[String] = ["pale", "green", "burnt"]
const AXIS_NS: String = "ns"
const AXIS_EW: String = "ew"
# The classes whose east-west picture is the outpost pack's rather than the generator's (docs/23,
# "The cars are the pack's, east-west"): authored keys in `authored.json`, placed by
# `canvas_of`'s authored tier at the pack's own canvas, standing on content's `lEw` footprint.
# `vehicle_canvas` answers ZERO for their generated east-west keys, which no longer exist, so a
# rule cannot quietly place a picture that retired -- mirrored by tools/sprites/parts/vehicles.py's
# PACK_EW under the same two-copies arrangement as VEHICLE_FOOTPRINTS, whose three car rows are
# now the north-south footprints alone.
const VEHICLE_PACK_EW: Array[String] = ["sedan", "van", "truck"]


# The canvas `key` is authored on when it names a shipped vehicle picture, ZERO otherwise.
static func vehicle_canvas(key: String) -> Vector2i:
	if not key.begins_with(VEHICLE_PREFIX):
		return Vector2i.ZERO
	var parts: PackedStringArray = key.substr(VEHICLE_PREFIX.length()).split("_")
	if parts.size() != 3:
		return Vector2i.ZERO
	if not VEHICLE_FOOTPRINTS.has(parts[0]) or not VEHICLE_VARIANTS.has(parts[1]):
		return Vector2i.ZERO
	var foot: Vector2i = VEHICLE_FOOTPRINTS[parts[0]] as Vector2i
	var n: int = int(CameraUtil.ART_NATIVE)
	if parts[2] == AXIS_NS:
		return Vector2i(foot.x * n, (foot.y + VEHICLE_ROOFLINE_TILES) * n)
	if parts[2] == AXIS_EW and not VEHICLE_PACK_EW.has(parts[0]):
		return Vector2i(foot.y * n, (foot.x + VEHICLE_ROOFLINE_TILES) * n)
	return Vector2i.ZERO


# Which way a vehicle picture is shown for a parked facing. The east-west picture is authored
# nose-east, so a west-facing car is the same picture in a negative-width rect -- the pawn's own
# flip, and the one place a manifest record's `facing` reaches the art. On the north-south axis
# both facings draw the one nose-north picture: decision 11 buys two keys a variant, and a car
# seen from behind and one seen from the front are the picture it does not buy. Recorded rather
# than hidden -- docs/23 names it as what a later slice would close.
static func vehicle_flip(facing: String) -> float:
	if facing == "w":
		return -1.0
	return 1.0


# The tallest picture any class stands, in tiles: the longest footprint plus the roofline tile,
# which is how far below the visible box a record's south edge can be while its picture is still
# on screen. main.gd's entity pass widens its search box by this, so the margin follows the
# footprint table instead of remembering one class -- a margin sized for a five-tile sedan would
# have popped an eight-tile truck out at the bottom of the screen with its cab still showing.
static func vehicle_reach_tiles() -> int:
	var longest: int = 0
	for foot in VEHICLE_FOOTPRINTS.values():
		longest = maxi(longest, maxi((foot as Vector2i).x, (foot as Vector2i).y))
	return longest + VEHICLE_ROOFLINE_TILES


# The canvas a registry key is authored on. Everything is one ART_NATIVE tile except the atlases,
# which are a table of them -- and this is the one table, read by check_appearance.gd's canvas
# lanes and mirrored by tools/sprites/build.py's `canvas_of`, so a second shape is a one-line
# entry here and there rather than a new exception in a gate.
# The inventory sheet's body chart: one figure wide, five tiles tall, feet-anchored like a pawn
# and never drawn in the world. A HARD COPY of `tools/sprites/parts/paperdoll.py`'s CHART_W/H,
# under the two-copies arrangement `SIZE` and the pawn canvas already live under -- Python cannot
# read GDScript, and `check_appearance.gd` measures every committed PNG against this copy.
const CHART_CANVAS: Vector2i = Vector2i(64, 160)
const CHART_POSES: Array[String] = ["stand", "crouch", "prone"]


# The registry key one body part wears in one pose. Mirrors `paperdoll.key_for`; the one place
# either side spells it, so a rename is two edits and a gate rather than thirty.
static func chart_key(part: String, pose: String) -> String:
	return "chart_%s_%s" % [part, pose]


# Where the opaque pixels of one chart part actually are, as a Rect2 in canvas coordinates -- what
# the wound and infection marks are hung on. Read off the picture rather than published as a table
# of anchors: a table would be a third copy of the skeleton and would drift the first time a limb
# moved. Cached, because it decodes an image.
static var _chart_rects: Dictionary = {}
static func chart_rect(key: String) -> Rect2:
	if _chart_rects.has(key):
		return _chart_rects[key] as Rect2
	var out := Rect2(Vector2.ZERO, Vector2(CHART_CANVAS))
	var texture: Texture2D = resolve(key)
	if texture != null:
		var image: Image = texture.get_image()
		if image != null:
			var used: Rect2i = image.get_used_rect()
			if used.size.x > 0 and used.size.y > 0:
				out = Rect2(used)
	_chart_rects[key] = out
	return out


# The authored tier's declaration, read once and kept. `assets/sprites/authored.json` is the one
# file this and `tools/sprites/build.py` share -- art the generator did not draw, commissioned to
# this project's own spec (docs/30, "Art we did not generate", 2026-09-09). Declaring a key is
# what makes it an exception to `sprites:check` rather than a file nobody can account for.
#
# The cache is a static and that is safe here for the reason CLAUDE.md's trap is careful about:
# it holds no per-world state. It is a read-only picture of a file on disk, identical in every
# world a gate boots, and `forget()` drops it with the texture cache so a gate can reload it.
const AUTHORED_PATH: String = "res://assets/sprites/authored.json"
static var _authored: Dictionary = {}
static var _authored_rigs: Array[String] = []
# `{family key: {"members": Array[String], "fps": int, "z": Dictionary}}` -- every family, kept
# whole, because the draw loop asks a family for one member by name (`frame_key`) and an overlay
# family which side of the body it goes on in one view (`layer_over`).
static var _families: Dictionary = {}
# `{held key: Vector2i}` -- every authored key of kind `pack_held`, and the pixel of its picture
# that lands on the hand: authored.json's copy of the pack manifest's `grip`, floored to the
# pixel it falls in.
static var _held: Dictionary = {}
# `{held key: Vector2i}` -- the pixel of a held picture the round leaves from: authored.json's copy
# of the pack manifest's `muzzle`, floored like the grip. What a muzzle flash is drawn from ("The
# shot is seen", 2026-09-26); `check_authored.gd`'s HELD lane holds the copy to the manifest.
static var _muzzles: Dictionary = {}
# `{sheet key: {frames, fps, loop, anchor, canvas}}` -- every authored family of kind `sheet`: one
# of the outpost pack's four-frame effect sheets, its frames the members `<key>_0`, `<key>_1`, ...
# in order, and its `fps`, `loop` and `anchor` authored.json's copies of the pack manifest's own
# (`godot:check:fx`'s RATE lane holds each copy to the manifest; the renderer never loads the
# pack's manifest or its `.tres`).
static var _sheets: Dictionary = {}
static var _authored_read: bool = false


# `{key: Vector2i}` for every declared authored key. An absent or malformed file is an empty
# tier, never a crash: a project with no commissioned art yet has nothing to declare, and the
# gate -- not the renderer -- is where a malformed declaration is supposed to be loud.
#
# The canvas is the only field the RENDERER reads, and deliberately: `reads` is a thing the gate
# judges, not a thing the renderer draws with, and a helper here returning it would be a function
# nothing calls. `kind` used to be in that sentence too, and stopped being on 2026-09-11, when the
# first commissioned body landed: three gates need "which authored keys are bodies" -- the FLIP
# lane iterates them, `_rig_keys()` counts them, and the FITS envelope is their union -- and one
# parse with three readers beats the same parse copied into three gates. `authored_rig_keys()`
# below is that reader, and `check_authored.gd` still parses the file itself for both fields, so
# the cross-check this comment was written for holds on `kind` exactly as it does on the canvas:
# two readers that must produce the same answer, rather than one reader with an unused accessor.
static func _read_authored() -> void:
	if _authored_read:
		return
	_authored_read = true
	_authored = {}
	_authored_rigs = []
	_families = {}
	_held = {}
	_muzzles = {}
	_sheets = {}
	if not FileAccess.file_exists(AUTHORED_PATH):
		return
	var text: String = FileAccess.get_file_as_string(AUTHORED_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return
	var keys: Variant = (parsed as Dictionary).get("keys")
	if not (keys is Dictionary):
		return
	for key in (keys as Dictionary).keys():
		var entry: Variant = (keys as Dictionary)[key]
		if not (entry is Dictionary):
			continue
		var canvas: Variant = (entry as Dictionary).get("canvas")
		if not (canvas is Array and (canvas as Array).size() == 2):
			continue
		var shape: Vector2i = Vector2i(int((canvas as Array)[0]), int((canvas as Array)[1]))
		_authored[String(key)] = shape
		if String((entry as Dictionary).get("kind", "")) == "rig":
			_authored_rigs.append(String(key))
		var grip: Variant = (entry as Dictionary).get("grip")
		if String((entry as Dictionary).get("kind", "")) == "pack_held" and grip is Array and (grip as Array).size() == 2:
			_held[String(key)] = Vector2i(floori(float((grip as Array)[0])), floori(float((grip as Array)[1])))
			var muzzle: Variant = (entry as Dictionary).get("muzzle")
			if muzzle is Array and (muzzle as Array).size() == 2:
				_muzzles[String(key)] = Vector2i(floori(float((muzzle as Array)[0])), floori(float((muzzle as Array)[1])))
		# A family: `members` names several keys that each draw from their own file at the
		# family's own canvas (docs/30, "The outpost pack, adopted"). The family key itself is
		# never a file -- `canvas_of(family_key)` still answers, from the assignment above, but
		# nothing resolves a texture for it -- so every member gets the same shape here and none
		# of them join `_authored_rigs`: a member is not itself declared `kind: "rig"`, and the
		# family key that is stays the one thing three gates iterate.
		var members: Variant = (entry as Dictionary).get("members")
		if members is Dictionary:
			var names: Array[String] = []
			for member_key in (members as Dictionary).keys():
				_authored[String(member_key)] = shape
				names.append(String(member_key))
			var z: Variant = (entry as Dictionary).get("z", {})
			_families[String(key)] = {
				"members": names,
				"fps": int((entry as Dictionary).get("fps", 0)),
				"z": z if z is Dictionary else {},
			}
			if String((entry as Dictionary).get("kind", "")) == "sheet":
				var frames: Array[String] = []
				while names.has("%s_%d" % [String(key), frames.size()]):
					frames.append("%s_%d" % [String(key), frames.size()])
				var anchor: Variant = (entry as Dictionary).get("anchor", [])
				var at := Vector2i(shape.x / 2, shape.y / 2)
				if anchor is Array and (anchor as Array).size() == 2:
					at = Vector2i(int((anchor as Array)[0]), int((anchor as Array)[1]))
				_sheets[String(key)] = {
					"frames": frames,
					"fps": int((entry as Dictionary).get("fps", 0)),
					"loop": bool((entry as Dictionary).get("loop", false)),
					"anchor": at,
					"canvas": shape,
				}
	_authored_rigs.sort()


static func authored_canvases() -> Dictionary:
	_read_authored()
	return _authored


# Every declared authored key of kind `rig` -- a commissioned body, on the pawn skeleton, that
# `PAWN_KEYS` deliberately does not name because one key belongs to one tier. Sorted, so a caller
# iterating it gets the same order every run and a gate's message does not depend on dictionary
# order. Empty until the first commissioned body, which is what makes the three gates that read it
# say so and skip rather than pass quietly on nothing.
static func authored_rig_keys() -> Array[String]:
	_read_authored()
	return _authored_rigs.duplicate()


static func canvas_of(key: String) -> Vector2i:
	# The authored tier first, and deliberately: a declaration is an explicit statement about one
	# key, and the rules below it are inference from a name. An explicit statement wins, which is
	# also what makes a declared key that collides with a rule a thing the gate can see.
	var declared: Dictionary = authored_canvases()
	if declared.has(key):
		return declared[key] as Vector2i
	if key.begins_with("chart_"):
		return CHART_CANVAS
	var n: int = int(CameraUtil.ART_NATIVE)
	# The ground atlas was placed by a rule here until 2026-09-27; it is authored now, and the
	# declaration above answers its canvas (192x256: two variants and four fringes across, eight
	# rows down).
	if PAWN_KEYS.has(key):
		return PAWN_CANVAS
	var vehicle: Vector2i = vehicle_canvas(key)
	if vehicle != Vector2i.ZERO:
		return vehicle
	return Vector2i(n, n)


static func anchor_of(size: Vector2i) -> int:
	if size.x == size.y:
		return Anchor.Centre
	return Anchor.Feet


static func ground_atlas() -> Texture2D:
	return resolve(GROUND_ATLAS_KEY)


# The tint a row was authored around: the surface tint for the five surfaces, the two paints for
# the two substitutions. What `ground_modulate` divides by.
static func ground_row_tint(row: int) -> Color:
	match row:
		GroundRow.Sidewalk:
			return Palette.COLOURS["sidewalk"]
		GroundRow.Boards:
			return Palette.COLOURS["indoorFloor"]
		_:
			if row >= 0 and row < Palette.SURFACE_TINTS.size():
				return Palette.SURFACE_TINTS[row]
			return Palette.COLOURS["floor"]


# Which row a floor tile draws: boards indoors, the sidewalk paint where the road mask says so,
# else the surface under it. Out of bounds reads Paved, as ground_colour does.
static func ground_row_for(map: Variant, tx: int, ty: int, sidewalk: bool) -> int:
	if map != null and SimTileMap.is_indoors(map, tx, ty):
		return GroundRow.Boards
	if sidewalk:
		return GroundRow.Sidewalk
	if map == null:
		return GroundRow.Paved
	var surface: int = int(SimSurface.surface_at(map, tx, ty))
	if surface < 0 or surface >= Palette.SURFACE_TINTS.size():
		return GroundRow.Paved
	return surface


# The atlas region of one cell. Pure: a row out of range clamps and a variant wraps, so a caller
# can never ask for pixels outside the picture.
static func ground_cell(row: int, variant: int) -> Rect2:
	var n: float = CameraUtil.ART_NATIVE
	var r: int = clampi(row, 0, GROUND_ROWS - 1)
	var v: int = posmod(variant, GROUND_VARIANTS)
	return Rect2(float(v) * n, float(r) * n, n, n)


# --- the ground edges ------------------------------------------------------------------------
#
# docs/30's edges clause: between two grounds the darker draws the edge, once, onto the lighter
# tile. The rule is pure over a tile's row and its four side neighbours' rows, read off main.gd's
# per-map row cache, and answers which edge cells the *lighter* tile blits over its own floor:
# for each darker side neighbour that has a fringe to draw (FRINGE_ROWS), that neighbour's row in
# the shape of the side it lies on. So every boundary is drawn at most once, by the lighter side.
# Darker by Rec. 709 luma of the row tint, so the order follows the palette rather than a second
# table. Since the pack's ground (2026-09-27) only the two green rows have a fringe and the pack
# paints no corner, so a boundary whose darker side is not green -- asphalt beside grass, say --
# is a clean seam, and a diagonal neighbour draws nothing; the neighbour list is still eight long
# so the caller's row cache stays one shape, and the diagonals are simply not read.

# Rec. 709 luma of a row's tint, the one ordering the edge rule reads.
static func row_luma(row: int) -> float:
	var c: Color = ground_row_tint(row)
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


# Whether `other` draws its edge onto a tile of `centre`: a different ground, and darker; on
# equal luma the lower row index wins, so the answer is total and never both ways.
static func _edge_wins(other: int, centre: int) -> bool:
	if other == centre or other == ROW_NONE or centre == ROW_NONE:
		return false
	var lo: float = row_luma(other)
	var lc: float = row_luma(centre)
	if absf(lo - lc) < 0.000001:
		return other < centre
	return lo < lc


# The edge cells a tile of row `centre` draws, given its eight neighbours' rows in the fixed
# order N E S W NE SE SW NW (ROW_NONE for a neighbour with no ground, or off the map). Each
# answer is (row, EdgeShape), sides only.
static func edge_shapes(centre: int, neighbours: PackedInt32Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if neighbours.size() != 8 or centre == ROW_NONE:
		return out
	for side in EDGE_SHAPES:
		var other: int = neighbours[side]
		if FRINGE_ROWS.has(other) and _edge_wins(other, centre):
			out.append(Vector2i(other, side))
	return out


# The atlas region of one edge cell: the shape's column past the variants, on the row. Pure and
# clamped like ground_cell, so no caller can ask for pixels outside the picture.
static func edge_cell(row: int, shape: int) -> Rect2:
	var n: float = CameraUtil.ART_NATIVE
	var r: int = clampi(row, 0, GROUND_ROWS - 1)
	var sh: int = clampi(shape, 0, EDGE_SHAPES - 1)
	return Rect2(float(GROUND_VARIANTS + sh) * n, float(r) * n, n, n)


# `flat / base` per channel: a cell whose pixels average `base` draws averaging `flat`. Identity
# when the flat colour is the row's own tint.
static func ground_modulate(flat: Color, base: Color) -> Color:
	return Color(_ratio(flat.r, base.r), _ratio(flat.g, base.g), _ratio(flat.b, base.b), flat.a)


static func _ratio(a: float, b: float) -> float:
	if b <= 0.0001:
		return 1.0
	return clampf(a / b, 0.0, 4.0)


# The doorways on a map, as {tile index: true}.
#
# Read off the generator's own manifest (`map.buildings[i].doors`, absolute tiles) rather than off
# the tile array, because a door *is* a Floor tile in a wall run and nothing in the tiles tells it
# from the street. Pure and uncached on purpose: the cache belongs to whoever is drawing, keyed on
# the map it came from, because a static cache is shared between the two worlds a gate boots.
static func door_tiles(map: Variant) -> Dictionary:
	var out: Dictionary = {}
	if map == null:
		return out
	for record in map.buildings as Array:
		if not (record is Dictionary):
			continue
		var doors: Variant = (record as Dictionary).get("doors", [])
		if not (doors is Array):
			continue
		for door in doors as Array:
			if not (door is Dictionary):
				continue
			var dx: int = int((door as Dictionary).get("x", -1))
			var dy: int = int((door as Dictionary).get("y", -1))
			if dx < 0 or dy < 0 or dx >= int(map.w) or dy >= int(map.h):
				continue
			out[dy * int(map.w) + dx] = true
	return out


# A whole content entry, or {} when nothing carries that id.
#
# `of_content` below answers with the `appearance` sub-block, which is the right answer for
# everything that draws as a body or a footprint. The map dressing (presentation/dressing.gd) is
# not one of those: its content entry *is* the look -- keys per wreck segment, per debris
# family -- with no pawn for an `appearance` block to hang off. So it asks for the entry, through
# the one content lookup this file already owns, rather than growing a second one beside it.
static func entry_of(world: Variant, kind: String, id: String) -> Dictionary:
	var entry: Variant = _content_entry(world, kind, id)
	return entry as Dictionary if entry is Dictionary else {}


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


# What one item base looks like: {texture, tint, glyph}.
#
# This is the reader `item.appearance.sprite` never had. The key has been in the schema since the
# appearance pipeline landed and nothing resolved it, so a dropped fire axe and a dropped bandage
# were the same ten-pixel square -- docs/23 named it the twelfth dead socket of the milestone.
#
# The three answers, in order: a declared `sprite` that resolves to a file wins; a declared `tint`
# colours whatever is drawn; and with no art at all the item draws its **class's** glyph in the
# ground-item role colour, which is the same "role colours are the floor" rule every other
# fallback here follows. Never a branch on an id -- that is what this whole file replaced.
static func item_look(world: Variant, base_id: String) -> Dictionary:
	var block: Dictionary = of_content(world, "item", base_id)
	var texture: Texture2D = resolve(String(block.get("sprite", "")))
	var declared: bool = block.has("tint")
	var tint: Color = Color(String(block.get("tint", "#ffffff"))) if declared else Palette.COLOURS["groundItem"]
	var entry: Dictionary = entry_of(world, "item", base_id)
	var glyph: int = ItemGlyph.shape_for(String(entry.get("class", "")))
	return {"texture": texture, "tint": tint, "glyph": glyph, "declaredTint": declared}


# The draw instruction for one entity, given the role flags _draw_entities already computed.
# Returns {texture: Texture2D|null, tint: Color, radius: float}.
static func for_entity(world: Variant, it: Dictionary) -> Dictionary:
	var is_player: bool = bool(it.get("player", false))
	var is_unique: bool = bool(it.get("unique", false))
	var is_bait: bool = bool(it.get("bait", false))
	var is_raider: bool = bool(it.get("raider", false))

	# Role colours are the floor: an entity with no content appearance looks exactly as it
	# did before this file existed.
	var role: String = "wanderer"
	if is_player:
		role = "player"
	elif is_unique:
		role = "survivor"
	elif is_raider:
		role = "raider"
	elif is_bait:
		role = "groundItem"
	var tint: Color = Palette.COLOURS[role]
	var sprite_key: String = ""

	# Zombies carry their type id, unique survivors their identity id, raiders their archetype
	# id. All three are content ids, and content is what decides how a thing looks.
	var content_id: String = _content_id_for_item(it)
	var declared_tint: bool = false
	if not content_id.is_empty():
		var block: Dictionary = body_variant(body_block_for(world, content_id), int(it.get("id", 0)))
		if block.has("tint"):
			tint = Color(String(block["tint"]))
			declared_tint = true
		if block.has("sprite"):
			sprite_key = String(block["sprite"])

	# One body's own colour, rolled at spawn from its type's `variance.tints` and carried here on
	# the draw item (main.gd reads it off `zombieType`). Last, so it wins over the kind's shared
	# tint: the block says what a shambler looks like and this says what *this* shambler looks
	# like. Still content -- the hexes live in content/zombies/, this only prefers one of them --
	# and empty for every body whose kind declares no palette, which falls through to the block
	# above exactly as it did before any of this existed.
	var rolled: String = String(it.get("tint", ""))
	if not rolled.is_empty():
		tint = Color(rolled)
		declared_tint = true

	var texture: Texture2D = resolve(sprite_key)
	# A raider is drawn at a survivor's radius, deliberately. At Peripheral detail main.gd draws
	# one anonymous disc of exactly this size and nothing else -- no sprite, no gear, no facing --
	# so a shape moving in the dark has to be as ambiguous as the contract says it is. Give
	# raiders the wanderer's smaller radius and the glimpse would quietly tell the player "that
	# one is not one of yours", which is the certainty docs/01 clause 4 refuses them.
	var radius: float = 14.0 if is_player else (12.0 if (is_unique or is_raider) else 10.0)
	# `sprite` is the key the texture came from, handed on so the draw loop can ask a family that
	# turns for the picture of one view and one step (`body_texture`); `texture` is the rest view.
	return {"texture": texture, "tint": modulate_for(texture != null, declared_tint, tint), "radius": radius, "sprite": sprite_key}


# A cosmetic variant belongs to its content type, not to the spawn mix. Stable entity ids
# (including their generation) select a look without spending a simulation RNG draw. The same
# original id travels with a visual remain, so dying and saving cannot change a body's clothes.
static func body_variant(block: Dictionary, entity: int) -> Dictionary:
	var variants: Variant = block.get("variants", [])
	if not (variants is Array) or (variants as Array).is_empty():
		return block
	var chosen: Variant = (variants as Array)[posmod(entity, (variants as Array).size())]
	if not (chosen is Dictionary):
		return block
	var out: Dictionary = block.duplicate(true)
	out.merge(chosen as Dictionary, true)
	return out


static func _content_id_for_item(it: Dictionary) -> String:
	var content_id: String = String(it.get("ztype", ""))
	if content_id.is_empty():
		content_id = String(it.get("cid", ""))
	if content_id.is_empty() and bool(it.get("player", false)):
		content_id = PLAYER_LOOK_ID
	return content_id


# Settled corpses are separate pictures, never an upright idle frame rotated onto the floor.
# Humans share the player's four fallen poses until their content supplies its own; a zombie
# with no corpse art supplies no picture rather than borrowing an unrelated human silhouette.
static func corpse_look(world: Variant, it: Dictionary) -> Dictionary:
	var entity: int = int(it.get("id", 0))
	var block: Dictionary = body_variant(body_block_for(world, _content_id_for_item(it)), entity)
	var poses: Variant = block.get("corpseSprites", [])
	if (not (poses is Array) or (poses as Array).is_empty()) and String(it.get("ztype", "")).is_empty():
		poses = body_block_for(world, PLAYER_LOOK_ID).get("corpseSprites", [])
	var key: String = ""
	if poses is Array and not (poses as Array).is_empty():
		key = String((poses as Array)[posmod(entity / 3, (poses as Array).size())])
	var look: Dictionary = for_entity(world, it)
	look["sprite"] = key
	var texture: Texture2D = resolve(key)
	look["texture"] = texture
	# A human fallback can have corpse art without a living content id (a former player after
	# succession). Resolve modulation against the settled picture, not the missing upright one.
	if texture != null and not block.has("tint") and String(it.get("tint", "")).is_empty():
		look["tint"] = Color.WHITE
	look["corpse"] = true
	return look


# A prone canvas is wider than it is tall and anchored at its ground centre. Shape-based
# standing anchors would put a 48x40 corpse almost a tile north of the place the body fell.
static func corpse_rect(sx: float, sy: float, size: Vector2) -> Rect2:
	return Rect2(Vector2(roundf(sx - size.x / 2.0), roundf(sy - size.y / 2.0)), size)


# Picking uses the same content-selected canvas as the live renderer; the heavy occupies a
# 40x48 picture and must be clickable across that picture rather than the old 32x40 default.
static func body_canvas_for(world: Variant, entity: int) -> Vector2i:
	var block: Dictionary = body_variant(body_block_for(world, body_look_id(world, entity)), entity)
	var key: String = String(block.get("sprite", ""))
	return canvas_of(key) if not key.is_empty() else PAWN_CANVAS


# Where a picture lying flat on a tile goes: its last row on the tile's south edge, centred on the
# tile's centre line, rounded so a 1:1 sprite never lands on a half pixel. `centre_x` is the tile
# centre's screen x and `south_y` the tile's south edge's screen y; `size` is the texture's screen
# size (`texture.get_size() * blit_scale`). The bed, a heap on a Low tile and the nature dressing
# (a bush, a stump, a log) all hang this way, and every one is authored cropped to the pack's
# anchor row so that the last row *is* the ground line (`godot:check:authored`'s PICTURE lane).
#
# Not `body_rect`, on purpose: a body stands on its point with FOOT_DROP_PX of contact shadow
# below it, which for a thing that fills its own tile would poke three pixels into the tile to the
# south -- and that tile is drawn after this one, so the overdraw would eat them. A flat picture
# has no shadow line to stand on; it sits inside its tile.
static func hang_rect(centre_x: float, south_y: float, size: Vector2) -> Rect2:
	return Rect2(roundf(centre_x - size.x / 2.0), roundf(south_y - size.y), size.x, size.y)


# The appearance block of a body's content id, whatever kind of content carries it: a zombie type,
# a raider archetype, the player's look, or -- the default -- a survivor or one of the colony's
# looks. `for_entity` and the effects (`body_look_id` below) both ask it, so the two cannot
# disagree about which entry a body's look lives in.
static func body_block_for(world: Variant, content_id: String) -> Dictionary:
	if content_id.is_empty():
		return {}
	var kind: String = "survivor"
	if content_id.begins_with("zombie."):
		kind = "zombie"
	elif content_id.begins_with("raider."):
		kind = "raider"
	elif content_id.begins_with("player."):
		kind = "player"
	return of_content(world, kind, content_id)


# The content id one live body's look is read from, off its components -- the id
# `presentation/main.gd`'s `_draw_entities` hands `for_entity` as `ztype` or `cid`, in the same
# precedence: a zombie's type, a person's rolled look before their identity, a raider's rolled look
# before their archetype, and `PLAYER_LOOK_ID` for a player with none of those. A COPY of that
# loop's reads rather than a call from it, because that loop's reads are needles other gates hold
# (`check_m2_variance`'s READER, `check_m2_raiders`' person and look); `godot:check:fx`'s KINDS
# lane builds every kind of body and proves this copy finds each one's block, so the two cannot drift
# apart without a red build.
static func body_look_id(world: Variant, entity: int) -> String:
	if world == null or world.components == null:
		return ""
	var zt: Variant = world.components.get_component(entity, "zombieType")
	if zt is Dictionary and not String((zt as Dictionary).get("id", "")).is_empty():
		return String((zt as Dictionary)["id"])
	var ident: Variant = world.components.get_component(entity, "identity")
	if ident is Dictionary:
		var look: String = String((ident as Dictionary).get("look", ""))
		if look.is_empty():
			look = String((ident as Dictionary).get("id", ""))
		if not look.is_empty():
			return look
	var rd: Variant = world.components.get_component(entity, "raider")
	if rd is Dictionary:
		var person: Variant = (rd as Dictionary).get("person", {})
		var rolled: String = String((person as Dictionary).get("look", "")) if person is Dictionary else ""
		if rolled.is_empty():
			rolled = String((rd as Dictionary).get("id", ""))
		if not rolled.is_empty():
			return rolled
	if entity == int(world.player):
		return PLAYER_LOOK_ID
	return ""


# How many screen pixels one art pixel covers at this zoom. The sprites are authored against
# an ART_NATIVE px tile (32, CameraUtil); every other zoom step is a power-of-two multiple of
# it, so the factor is exact and nearest-neighbour stays clean. The resolver above is
# deliberately zoom-innocent -- `for_entity` answers *what* a body looks like, this answers
# *how big*, and keeping them apart is what lets a gate probe either without a camera.
# A zero zoom answers zero: a degenerate camera draws nothing rather than dividing wrong.
static func blit_scale(zoom: float) -> float:
	return zoom / CameraUtil.ART_NATIVE


# The screen side of one item picture lying on the floor at this zoom. The pack's inventory icons
# are 32x32 (docs/30, "The outpost pack, adopted"), so drawing one at the world's own pixel would
# fill a whole tile with a pistol; half of it is half a tile, and `blit_scale` keeps it a power of
# two at every rung of the ladder so nearest-neighbour drops whole rows. A bag plate is a different
# question (`ui/bag_grid.gd` picks the largest whole multiple of the art that fits) and a base with
# no picture draws its glyph at a third of a tile as it always did.
const ITEM_ICON_FLOOR_SCALE: float = 0.5


static func item_icon_px(zoom: float) -> float:
	return CameraUtil.ART_NATIVE * blit_scale(zoom) * ITEM_ICON_FLOOR_SCALE


# Whether a body is moving, read off its velocity component -- the peripheral-glimpse test.
#
# A missing component is *motionless, not unknown*: SimRecruits' corpse-making removes
# `velocity` outright, so `null` here is exactly the dead. The old inline test in
# _draw_entities read that backwards -- it culled only entities that HAD a velocity of zero,
# so a corpse (no component at all) was glimpsed forever as a body standing in the dark.
# The keys are `dx`/`dy` and never `x`/`y` (CLAUDE.md's velocity trap); check_topdown.gd
# feeds this `{"x": 1.0}` and requires false, which is that trap made mechanical.
static func moving(vel: Variant) -> bool:
	if not (vel is Dictionary):
		return false
	var d: Dictionary = vel as Dictionary
	return float(d.get("dx", 0.0)) != 0.0 or float(d.get("dy", 0.0)) != 0.0


# The screen rect a body's picture is drawn into, given its ground point, its blit size and
# which way it faces. Pure, so check_topdown.gd's flip lane can hold it to exact numbers at
# every rung of the ladder without a draw pass.
#
# A feet-anchored picture (anchor_of: anything not square) stands with its bottom row on the
# contact-shadow line, sy + FOOT_DROP_PX; a centred one hangs symmetrically around the point,
# which is the rect every tile-square picture has always been drawn into. Rounded so a 1:1 pixel
# sprite never lands on a half-pixel as the camera follows the player.
#
# `flip` is body_flip's answer: -1.0 mirrors the picture by handing the renderer a NEGATIVE
# WIDTH, never a transform. Probed in 4.7.1 before this was written: draw_texture_rect with a
# negative-width rect draws the texture mirrored at position .. position + |width|, so the
# flipped rect keeps the same left edge as the unflipped one and the body stays on its point.
# Nobody rotates, the player included (docs/30, the Dungeon Settlers look) -- the draw loop holds
# zero transforms and the flip lane counts them.
static func body_rect(sx: float, sy: float, size: Vector2, flip: float) -> Rect2:
	var left: float = roundf(sx - size.x / 2.0)
	var top: float = roundf(sy - size.y / 2.0)
	if anchor_of(Vector2i(size)) == Anchor.Feet:
		top = roundf(sy + FOOT_DROP_PX - size.y)
	return Rect2(left, top, size.x * flip, size.y)


# Which way a face-on picture is shown for a heading: mirrored (-1.0) when the body looks west
# of straight up or down, as painted (+1.0) otherwise -- north, south and east all draw the one
# picture. A flip is a two-state readout of a continuous heading, which is why the indicator
# line draws for every body: the picture can never say more than "east or west", and the line
# carries the exact facing. Since "The bodies turn and walk" (2026-09-26) only the face-on
# generated rigs -- the screamer and the bloater -- are asked this; a body that turns draws its own
# west view and never flips (`flip_for`, below). The peripheral-anonymity
# clause is unharmed because a glimpsed body never reaches the blit -- it draws as the anonymous
# disc and the loop moves on before facing is read.
static func body_flip(facing: float) -> float:
	if cos(facing) < 0.0:
		return -1.0
	return 1.0


# --- the bodies that turn ---------------------------------------------------------------------
#
# "The bodies turn and walk" (docs/23, 2026-09-26; docs/30, "The outpost pack, adopted", decision
# 1): every human draws on the outpost pack's survivor and the shambler on the pack's shambler,
# four views and a four-frame walk each way, and the pack's vest, helmet, gas mask and backpack
# are four views each. A body that turns is never mirrored -- the pack draws its own west view --
# so `body_flip` above is left to the two generated rigs that still face the camera, the screamer
# and the bloater. Which pictures a family has is authored.json's to say, by the member names its
# note fixes; nothing here knows the word "survivor".

# The four views in the order a quarter turn walks them on a y-down screen: east at 0, south at a
# quarter turn, west at a half, north at three quarters.
const VIEWS: Array[String] = ["e", "s", "w", "n"]
# The view a body at rest shows when nothing says otherwise, and the one face-on art belongs to.
const VIEW_REST: String = "s"


# Which of the four views a heading shows: the nearest quarter turn. A heading exactly on a
# diagonal rounds away from zero (GDScript's `roundi`), so south-east shows south and north-east
# shows north -- a rule, stated, rather than whatever float noise decided.
static func view_of(facing: float) -> String:
	return VIEWS[posmod(roundi(facing / (PI / 2.0)), VIEWS.size())]


# Whether `key` is a family with a picture for every view: a body or a wearable that turns.
static func turns(key: String) -> bool:
	if key.is_empty():
		return false
	_read_authored()
	if not _families.has(key):
		return false
	var members: Array = (_families[key] as Dictionary)["members"] as Array
	for view in VIEWS:
		if not members.has("%s_%s" % [key, view]):
			return false
	return true


# How many walk frames a turning family draws each way: the run `<key>_walk_s_0`, `_1`, ...
# counted from zero until one is missing. Zero for a family that only stands (every wearable).
static func walk_frames(key: String) -> int:
	if not turns(key):
		return 0
	var members: Array = (_families[key] as Dictionary)["members"] as Array
	var n: int = 0
	while members.has("%s_walk_%s_%d" % [key, VIEW_REST, n]):
		n += 1
	return n


# The walk's frame rate: authored.json's copy of the pack manifest's `fps.walk`.
static func walk_fps(key: String) -> int:
	_read_authored()
	if not _families.has(key):
		return 0
	return int((_families[key] as Dictionary)["fps"])


# Which walk frame a body shows on `tick`: the pack's frame rate against the sim's own clock, in
# integers, so every machine draws the same frame on the same tick. `phase` staggers one body from
# the next (the draw loop hands over the entity id) so a crowd does not step in lockstep. A zero
# rate or no frames answers frame 0 -- a body with no walk stands; it never divides by zero.
static func walk_frame(tick: int, fps: int, frames: int, phase: int) -> int:
	if fps <= 0 or frames <= 0:
		return 0
	return posmod(tick * fps / SimClock.TICK_HZ + phase, frames)


# The one picture a body draws: the member of its family for this view, walking or standing, or
# the key itself for anything that does not turn (the generated screamer and bloater).
static func frame_key(key: String, view: String, moving_now: bool, tick: int, phase: int) -> String:
	if not turns(key):
		return key
	if moving_now:
		var frames: int = walk_frames(key)
		var fps: int = walk_fps(key)
		if frames > 0 and fps > 0:
			return "%s_walk_%s_%d" % [key, view, walk_frame(tick, fps, frames, phase)]
	return "%s_%s" % [key, view]


# The view one body shows. A body with a `facing` component shows its heading, which the sim
# arbitrates (the aim command, then movement). A body with none -- every zombie -- shows the way
# it is walking, read off the same velocity `moving` reads, and the rest view when it stands. A
# body that does not turn always shows the rest view: face-on art has only the one.
static func body_view(key: String, facing_v: Variant, vel: Variant) -> String:
	if not turns(key):
		return VIEW_REST
	if facing_v is Dictionary:
		return view_of(float((facing_v as Dictionary).get("radians", 0.0)))
	if moving(vel):
		var d: Dictionary = vel as Dictionary
		return view_of(atan2(float(d.get("dy", 0.0)), float(d.get("dx", 0.0))))
	return VIEW_REST


# The picture for a body this frame, from the look `for_entity` answered: its family's member for
# this view and step, or the look's own texture when the key does not turn.
static func body_texture(look: Dictionary, view: String, moving_now: bool, tick: int, phase: int) -> Texture2D:
	var key: String = String(look.get("sprite", ""))
	var frame: String = frame_key(key, view, moving_now, tick, phase)
	if frame != key:
		var texture: Texture2D = resolve(frame)
		if texture != null:
			return texture
	return look.get("texture") as Texture2D


# The flip for a body: one that turns is never mirrored (the pack draws the west view), and a
# face-on one flips the way it always has.
static func flip_for(key: String, facing: float) -> float:
	if turns(key):
		return 1.0
	return body_flip(facing)


# Whether an overlay family's picture for `view` goes over the body: the pack manifest's own
# `z_by_direction`, copied into authored.json as `z`, and below zero is behind -- the backpack seen
# from the side. A key that is no family, or a view its `z` does not list, takes `fallback`: the
# slot's own side from EQUIP_DRAW_ORDER.
static func layer_over(key: String, view: String, fallback: bool = true) -> bool:
	_read_authored()
	if not _families.has(key):
		return fallback
	var z: Dictionary = (_families[key] as Dictionary)["z"] as Dictionary
	if not z.has(view):
		return fallback
	return int(z[view]) >= 0


# --- the weapon in the hand -------------------------------------------------------------------
#
# "Held weapons in the hand" (docs/23, 2026-09-26; docs/30, "The whole outpost pack"): the pack's
# held weapons are one picture each, drawn facing east at their own canvas with a grip point, and
# a four-direction body holds one at a hand point per view. The picture is turned to the view by
# the draw call's own flags rather than by a transform (the entity loop holds none; check_topdown's
# flip lane counts them): east as painted, south and north a quarter turn either way through
# `draw_texture_rect`'s `transpose`, and west the east picture mirrored, so the weapon stays upright
# the way the pack's own preview holds it. The body never mirrors (`flip_for`); only the weapon
# does, and only facing west. Everything here is in body-canvas pixels, top-left origin, on the
# pack survivor's 32x40 crop.

# Where each hand is, per view: the pixel of the body the grip lands on, measured off the pack
# survivor's idle views (the lightest skin pixel at the end of each arm). The primary is the weapon
# hand -- the figure's right hand seen from the front and the back, and the near, visible hand seen
# from either side; the secondary is the other one. `check_worn.gd`'s HELD lane holds every point
# to a solid pixel of the body it is drawn on, so a point that drifts off the arm goes red. The
# walk frames swing the arms and the hand points stay the idle ones -- the same fit-to-idle the
# pack's own wearables have, named in docs/23's record rather than hidden.
const HELD_HANDS: Dictionary = {
	"primary": {"e": Vector2i(18, 31), "s": Vector2i(9, 30), "w": Vector2i(14, 31), "n": Vector2i(23, 30)},
	"secondary": {"e": Vector2i(11, 30), "s": Vector2i(22, 30), "w": Vector2i(21, 30), "n": Vector2i(9, 30)},
}
# The views in which a hand is behind the body, so what it holds draws under it: both hands seen
# from behind, and the far hand seen from either side.
const HELD_BEHIND: Dictionary = {
	"primary": ["n"],
	"secondary": ["e", "w", "n"],
}


# Whether `key` is a held weapon: an authored key of kind `pack_held` with a grip.
static func holds(key: String) -> bool:
	if key.is_empty():
		return false
	_read_authored()
	return _held.has(key)


# The pixel of a held picture that lands on the hand, or (-1, -1) for a key that is not held.
static func grip_of(key: String) -> Vector2i:
	_read_authored()
	return _held.get(key, Vector2i(-1, -1)) as Vector2i


# The pixel of a held picture the round leaves from, or (-1, -1) for a key that is not held or
# declares no muzzle.
static func muzzle_of(key: String) -> Vector2i:
	_read_authored()
	return _muzzles.get(key, Vector2i(-1, -1)) as Vector2i


# Where pixel `p` of a picture `size` px lands, in body-canvas pixels, once `held_pose` has placed
# it for `view` -- the same four mappings that function's comment lists, applied to one point. The
# muzzle flash asks it where a held weapon's muzzle is ("The shot is seen").
static func held_point(pose: Dictionary, size: Vector2i, p: Vector2i, view: String) -> Vector2i:
	var at: Vector2i = pose["at"] as Vector2i
	match view:
		"w":
			return at + Vector2i(size.x - 1 - p.x, p.y)
		"s":
			return at + Vector2i(size.y - 1 - p.y, p.x)
		"n":
			return at + Vector2i(p.y, size.x - 1 - p.x)
	return at + p


# One of the pack's effect sheets as the renderer plays it -- {frames, fps, loop, anchor, canvas}
# -- or {} for a key that is not an authored `sheet` family.
static func sheet_of(key: String) -> Dictionary:
	if key.is_empty():
		return {}
	_read_authored()
	return _sheets.get(key, {}) as Dictionary


# Every authored sheet key, sorted: what `godot:check:fx`'s READS lane walks.
static func sheet_keys() -> Array[String]:
	_read_authored()
	var out: Array[String] = []
	for key in _sheets.keys():
		out.append(String(key))
	out.sort()
	return out


# How a held picture `size` px, gripped at `grip`, is drawn so the grip pixel lands on `hand` in
# `view`: `at` is the top-left of the painted area, `size` the rect draw_texture_rect is handed,
# in the picture's own orientation (Godot swaps it when `transpose` is set) and signed -- a negative
# width mirrors the painted x, a negative height its y -- and `transpose` the flag. Probed in 4.7.1
# with a real renderer before it was written: a transposed rect paints |h| wide and |w| tall from
# its position, pixel (u, v) at (v, u), and each sign flips the painted axis in place.
#   e  as painted                (u, v) -> (u, v)
#   w  mirrored                  (u, v) -> (w-1-u, v)
#   s  a quarter turn clockwise  (u, v) -> (h-1-v, u)     barrel down, towards the camera
#   n  a quarter turn back       (u, v) -> (v, w-1-u)     barrel up, away from it
static func held_pose(size: Vector2i, grip: Vector2i, hand: Vector2i, view: String) -> Dictionary:
	var w: int = size.x
	var h: int = size.y
	match view:
		"w":
			return {"at": Vector2i(hand.x - (w - 1 - grip.x), hand.y - grip.y), "size": Vector2i(-w, h), "transpose": false}
		"s":
			return {"at": Vector2i(hand.x - (h - 1 - grip.y), hand.y - grip.x), "size": Vector2i(-w, h), "transpose": true}
		"n":
			return {"at": Vector2i(hand.x - grip.y, hand.y - (w - 1 - grip.x)), "size": Vector2i(w, -h), "transpose": true}
	return {"at": Vector2i(hand.x - grip.x, hand.y - grip.y), "size": Vector2i(w, h), "transpose": false}


# The layer a held weapon draws in `slot` for `view`, or {} when the key is not held or the slot has
# no hand. Its side is the hand's (`HELD_BEHIND`); EQUIP_DRAW_ORDER's own `over` is folded in by
# the caller.
static func held_layer(key: String, slot: String, view: String) -> Dictionary:
	if not holds(key) or not HELD_HANDS.has(slot):
		return {}
	var hands: Dictionary = HELD_HANDS[slot] as Dictionary
	if not hands.has(view):
		return {}
	var texture: Texture2D = resolve(key)
	if texture == null:
		return {}
	var pose: Dictionary = held_pose(Vector2i(texture.get_size()), grip_of(key), hands[view] as Vector2i, view)
	pose["texture"] = texture
	pose["over"] = not (HELD_BEHIND.get(slot, []) as Array).has(view)
	return pose


# The props that stand in a district, as component -> content id.
#
# A prop is an entity that is neither a body nor a carried item: a container, a bed, a campfire,
# the well. The sim spawns all four (SimContainers.make_container, SimNeeds.make_bed /
# make_campfire / make_water_source) and knows nothing about how they look; this is the whole of
# the mapping, and content/props/*.json is the whole of the look. Adding a fifth prop is an entry
# here plus an entry there -- and check_topdown.gd's PROPS lane boots a real district and fails if
# anything standing in it resolves nothing, so a fifth prop that skips this table is caught rather
# than silently invisible, which is the state all four of these were in until this slice.
#
# `flag` is the one boolean whose value changes the picture; a prop without one leaves it empty.
# Two content ids rather than one entry with two tints, so the resolver stays a lookup.
const PROP_KINDS: Array[Dictionary] = [
	{"component": "searchable", "id": "prop.container", "flag": "searched", "flag_id": "prop.container.searched", "table_field": "table"},
	{"component": "campfire", "id": "prop.campfire", "flag": "lit", "flag_id": "prop.campfire.lit"},
	{"component": "bed", "id": "prop.bed", "flag": "", "flag_id": ""},
	{"component": "water_source", "id": "prop.well", "flag": "", "flag_id": ""},
	{"component": "latrine", "id": "prop.latrine", "flag": "", "flag_id": ""},
	# The picture belongs to the existing gunsmith bench entity created by SimGunsmith.build.
	{"component": "workbench", "id": "prop.workbench", "flag": "", "flag_id": ""},
	# The two things the sim already had and nothing drew as an object (docs/23, "Props for things
	# that exist"): the scrap barricade, and a floodlight planted in the yard. Both are pictures the
	# outpost pack's utility group supplies taller than a tile, so they stand in the entity sort
	# (`standing` below) instead of lying flat with the rest.
	{"component": "scrapBarricade", "id": "prop.barricade", "flag": "", "flag_id": ""},
	# `lit_component`, on the one kind that has it, names a component whose *presence* is the lit
	# state: the sim adds `light_source` to a lamp that is burning and removes it when the fuel is
	# out (SimLight._tick_burn), so a lamp draws lit exactly while it lights the yard.
	{"component": "placedLight", "id": "prop.lamp.dark", "flag": "", "flag_id": "", "lit_component": "light_source", "lit_id": "prop.lamp"},
]

# `table_field`, on the one kind that has it, names the field of the prop's component that holds
# the loot table it was stocked from, and the prop's own content entry then says which id each table
# draws as (`tables`, prop.schema.json): the outpost pack's container kinds, keyed by loot table
# (docs/23, "Furnishings and container kinds"). The state suffix is the flag's, appended to
# whichever id the table chose, so a metal container's searched look is `prop.container.metal.searched`.
const PROP_SEARCHED_SUFFIX: String = ".searched"

# The ground-footprint primitives a prop may ask for. Geometry, not identity -- `box` is a crate
# or a cupboard or anything else square. main.gd's _draw_prop is the one place that draws them and
# check_topdown.gd asserts every name here appears there, so a shape content can name but nothing
# can draw fails the build instead of drawing nothing.
const PROP_SHAPES: Array[String] = ["box", "slab", "disc", "ring"]
const PROP_SHAPE_DEFAULT: String = "box"
const PROP_SIZE: float = 0.6
# The largest footprint a prop may declare, in tiles across. One until the outpost pack's bed, which
# is a tile and a third wide (docs/23, "Trees, the bed and the heaps").
const PROP_SIZE_MAX: float = 1.5


# What one entity looks like standing on the ground, or {} when it is not a prop at all.
# Returns {id, texture, tint, shape, size} -- the same {texture, tint} pair for_entity returns,
# plus the two keys a footprint needs. Fallbacks are the supported path here as everywhere: an
# unknown id, or content that declares only a tint, still yields something drawable.
static func prop_look(world: Variant, entity: int) -> Dictionary:
	if world == null or world.components == null:
		return {}
	for kind in PROP_KINDS:
		var comp: Variant = world.components.get_component(entity, String(kind["component"]))
		if not (comp is Dictionary):
			continue
		var id: String = String(kind["id"])
		var flag: String = String(kind["flag"])
		var flagged: bool = not flag.is_empty() and bool((comp as Dictionary).get(flag, false))
		if kind.has("table_field"):
			# The picture is the table's; the state is still the flag's, and only the flag's -- what
			# a container looks like before it is opened says nothing the table does not.
			id = table_prop_id(world, id, String((comp as Dictionary).get(String(kind["table_field"]), "")))
			if flagged:
				id += PROP_SEARCHED_SUFFIX
		elif flagged:
			id = String(kind["flag_id"])
		elif kind.has("lit_component") and world.components.has_component(entity, String(kind["lit_component"])):
			id = String(kind["lit_id"])
		return prop_of(world, id)
	return {}


# Every tile a standing prop occupies, as `{Vector2i: true}`: the tiles the furnishing dressing
# steps aside from, so a chair never peeks out from under a container or a bed. Read off the same
# component queries `main.gd`'s `_draw_props` walks, and never off `alive` alone -- components.query
# does not check it (CLAUDE.md), so a despawned prop is skipped here as it is there.
static func prop_tiles(world: Variant) -> Dictionary:
	var out: Dictionary = {}
	if world == null or world.components == null:
		return out
	for kind in PROP_KINDS:
		for ent in world.components.query([String(kind["component"]), "position"]):
			if world.entities != null and not world.entities.is_alive(int(ent)):
				continue
			var p: Variant = world.components.get_component(int(ent), "position")
			if p is Dictionary:
				out[Vector2i(floori(float((p as Dictionary)["x"])), floori(float((p as Dictionary)["y"])))] = true
	return out


# Whether the tile holds the scrap barricade *and* the pack's picture for it resolves: the tile branch
# then draws the floor under it and leaves the barricade to the entity sort. False for any other
# wall and for a barricade with no art, which keep the procedural slab -- the supported fallback.
static func scrap_stands_at(world: Variant, tx: int, ty: int) -> bool:
	if world == null or world.tilemap == null:
		return false
	var ov: Variant = SimTileMap.overlay_at(world.tilemap, tx, ty)
	if not (ov is Dictionary) or String((ov as Dictionary).get("kind", "")) != "scrap":
		return false
	return prop_of(world, "prop.barricade")["texture"] != null


# The props whose picture is taller than a tile, as `{e, gx, gy, key}`: the entity, the world point
# each stands on -- the south-edge centre of its tile, so a body north of it sorts behind it and one
# south sorts in front, a tree's rule -- and the registry key to draw. `seen` is the observer's tile
# set (SimVisibility.tiles_for) or null for nobody, and nobody sees no lamps: the *live* set only,
# never the remembered map, so a lamp's lit state and a barricade's standing are things seen now and
# not a memory that updates behind the observer's back. `bounds` is the visible AABB in tiles.
# components.query does not check alive (CLAUDE.md), so a despawned prop is skipped here; a prop
# with a flat picture is `main.gd`'s `_draw_props`', and each entity is answered once.
static func standing_props(world: Variant, seen: Variant, bounds: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if seen == null or world == null or world.components == null:
		return out
	var drawn: Dictionary = {}
	for kind in PROP_KINDS:
		for ent in world.components.query([String(kind["component"]), "position"]):
			var e: int = int(ent)
			if drawn.has(e) or (world.entities != null and not world.entities.is_alive(e)):
				continue
			var p: Variant = world.components.get_component(e, "position")
			if not (p is Dictionary):
				continue
			var x: float = float((p as Dictionary)["x"])
			var y: float = float((p as Dictionary)["y"])
			if x < float(bounds["minX"]) or x > float(bounds["maxX"]) or y < float(bounds["minY"]) or y > float(bounds["maxY"]):
				continue
			if not (seen as Object).call("has_tile", floori(x), floori(y)):
				continue
			var look: Dictionary = prop_look(world, e)
			if look.is_empty() or not bool(look.get("standing", false)):
				continue
			drawn[e] = true
			out.append({"e": e, "gx": float(floori(x)) + 0.5, "gy": float(floori(y)) + 1.0, "key": String(look["sprite"])})
	return out


# The content id a container stocked from `table` draws as: the base prop's `tables` map names it,
# and a table the map does not name -- an empty string, a table nobody has drawn, a fabricated one --
# answers the base id itself, so an unknown table is the wood crate and never an invisible thing.
static func table_prop_id(world: Variant, base_id: String, table: String) -> String:
	if table.is_empty():
		return base_id
	var tables: Variant = entry_of(world, "prop", base_id).get("tables")
	if not (tables is Dictionary):
		return base_id
	var mapped: String = String((tables as Dictionary).get(table, ""))
	return mapped if not mapped.is_empty() else base_id


# The look for one prop content id, resolved the same way an entity's is: content decides, the
# role colour is the floor, art passes through white unless content asked for a tint.
static func prop_of(world: Variant, id: String) -> Dictionary:
	var block: Dictionary = of_content(world, "prop", id)
	var tint: Color = Palette.COLOURS["prop"]
	var declared_tint: bool = false
	if block.has("tint"):
		tint = Color(String(block["tint"]))
		declared_tint = true
	var texture: Texture2D = resolve(String(block.get("sprite", "")))
	var shape: String = String(block.get("shape", PROP_SHAPE_DEFAULT))
	if not PROP_SHAPES.has(shape):
		shape = PROP_SHAPE_DEFAULT
	var size: float = clampf(float(block.get("size", PROP_SIZE)), 0.1, PROP_SIZE_MAX)
	return {
		"id": id,
		"texture": texture,
		"tint": modulate_for(texture != null, declared_tint, tint),
		"shape": shape,
		"size": size,
		# The registry key the picture came from, so the entity sort can resolve it by name, and
		# whether it *stands*: a picture taller than a tile would stand in front of what is north of
		# it if it lay flat under the bodies, so it joins the sort at its south edge, the way a tree
		# does. The bed (30 rows) and every container lie flat; the pack's barricade and work lamp
		# stand.
		"sprite": String(block.get("sprite", "")),
		"standing": texture != null and texture.get_size().y > int(CameraUtil.ART_NATIVE),
		# The looping sheet drawn over the prop -- the lit campfire's flame ("The shot is seen");
		# empty for every prop that declares none, which draws nothing more than it did.
		"flameFx": String(block.get("flameFx", "")),
	}


# Each worn piece, in EQUIP_DRAW_ORDER, for a body showing `view`. A wearable family that turns --
# the pack's vest, helmet, gas mask and backpack -- draws its member for that view, at the body's
# own rect, over or under by the pack's own per-view layering (`layer_over`). A held weapon -- the
# pack's `item_held_*` -- draws at its hand for that view (`held_layer`), and its layer carries
# `at`, `size` and `transpose` so the draw loop can place and turn it. Nothing else draws: since
# "Pack gear on the body" (2026-09-26) there is no face-on overlay left to draw, and a key of any
# other shape -- the retired `_equip` overlays among them -- composes nothing, in every view. That
# is the gap the owner accepted (docs/30, "The whole outpost pack"): a jacket, a cap, trousers or
# the duffel worn shows nothing on the body until four-sided art exists, and the inventory and the
# inspect pane still say it is worn.
static func equipment_layers_for(world: Variant, actor: int, view: String = VIEW_REST) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world == null or world.components == null:
		return out
	var eq: Variant = world.components.get_component(actor, "equipment")
	if not (eq is Dictionary):
		return out
	var slots: Dictionary = (eq as Dictionary).get("slots", {}) as Dictionary
	for entry in EQUIP_DRAW_ORDER:
		var slot: String = String(entry["slot"])
		var block: Variant = _equip_block_for(world, slots.get(slot))
		if not (block is Dictionary):
			continue
		var key: String = String((block as Dictionary).get("equipSprite", ""))
		if turns(key):
			var turned: Texture2D = resolve("%s_%s" % [key, view])
			if turned != null:
				out.append({"texture": turned, "over": layer_over(key, view, bool(entry["over"]))})
		elif holds(key):
			var held: Dictionary = held_layer(key, slot, view)
			if not held.is_empty():
				held["over"] = bool(held["over"]) and bool(entry["over"])
				out.append(held)
	return out


# The appearance block for whatever item base occupies a slot, or null through every exit: no
# item, no itemBase component, no matching content entry, no declared appearance at all.
static func _equip_block_for(world: Variant, item: Variant) -> Variant:
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
	return block if block is Dictionary else null


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
