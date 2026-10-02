extends RefCounted
# Began as a port of src/render/palette.ts — colours the district is. Not a theme. The ground and
# built-mass entries have since **diverged from the frozen palette.ts** on purpose, and this table
# is the second regrade: docs/30's Dungeon Settlers decision fixes the mood as **warm dark
# fantasy** — a cool near-black dark wrapped around a warm-lit district, timber browns for built
# mass, and saturated fire and lamplight as the only loud things on screen. It supersedes the
# muted-overcast grade that preceded it.
#
# The difference is what holds the mood. Overcast was held by *mutedness* — one ceiling on
# saturation, which produced a street where nothing was colourful and therefore nothing was warm
# either. This grade is held by **warmth and value**: every district surface is warmer than it is
# cool (r - b), everything the district sits *in* is the other way round (b - r), and the read
# comes from value separation rather than from a hue nobody is allowed. Saturation still has a
# ceiling on the ground, because a bright green lawn is not this world; it is no longer the thing
# doing the work.
#
# **The ground is the exception, since 2026-09-27.** docs/30's "The whole outpost pack" (the
# owner's answer, 2026-09-25: "the ground takes the pack's own grade") moved the eight ground
# entries -- floor, dirt, grass, undergrowth, rubble, water, sidewalk, indoorFloor -- off this
# grade and onto the outpost pack's terrain tiles' own measured means, which are brighter and more
# saturated than anything above allows (dirt and grass past S 0.50, paved a neutral asphalt).
# Those eight are pinned as hex literals by the ground lanes (check_road_look.gd's PALETTE and
# TEXTURE, check_topdown.gd's GROUND, check_water.gd's PACK) with the warm-dark table they replaced
# as the case each refuses; the warm-dark table itself survives as GENERATOR_GROUNDS below, the
# grounds the still-generated art was authored against, for the guards that judge that art.
#
# Enforced by properties, not by anybody's memory. Four lanes hold this table:
#   * check_road_look.gd's PALETTE lane — the warm family (r - b >= 0.02 over every kerb, wall,
#     paint, prop and memory tint) and the cool family (b - r >= 0.02 over background, night and
#     the glass), the pack's measured ground table pinned exactly, paved's value band, the road
#     family's ordering, and the pairwise distinctness of the six surfaces;
#   * check_weather.gd's ACCENT lane — the glass and its rim, the ground items, the screen's own
#     marks, and the lamp pools held both warm (r - b) and thin (alpha);
#   * check_topdown.gd's WALL lane — every generated wall face measured in luminance against
#     every ground in GENERATOR_GROUNDS it was authored beside, interiors and doorway included.
# (check_appearance.gd's GREY lane was the fourth until the colonist rig retired, 2026-09-26.)
# So tune by screenshot inside those bounds, and never by reverting to palette.ts, which stays
# frozen with its oracle.

const COLOURS: Dictionary = {
	# The ground: the outpost pack's own measured means since 2026-09-27 (docs/23, "The ground is
	# the pack's"), each the integer-rounded mean of its atlas row's two cells -- the pack's two
	# asphalts, two dirts, two grasses, the grass under all four of its fringes, the rubble with and
	# without its debris, and its one water. Measured off `ground_atlas.png` with integer
	# arithmetic, never a float sum; the warm-dark values these replaced are GENERATOR_GROUNDS.
	"floor": Color("#474646"),
	"dirt": Color("#896840"),
	"grass": Color("#485127"),
	"undergrowth": Color("#404820"),
	"rubble": Color("#595149"),
	# The sixth ground: the pack's "still teal water". Water reads as water -- the owner's call of
	# 2026-09-09, which made it the one cool ground -- and since the pack's grade it is the pack's
	# own teal rather than a slate held under the old 0.30 saturation cap (S 0.581 now; the cap
	# went with the grade, which closes HANDOFF's water-saturation question). check_road_look.gd's
	# COOL_SURFACES still judges it cool (b - r = 0.196) and check_water.gd's PACK lane pins it.
	#
	# This is the ford -- the wadeable ground `SimSurface.Surface.Water` names. Deep water is the
	# `Tile.Water` tile and draws this darkened by `WATER_DEEP_SHADE`, the way a wall draws a face
	# lifted out of its cap rather than carrying a second authored colour.
	"water": Color("#244e56"),
	"tree": Color("#3f4a33"),
	# Timber and daub, not the concrete tower block the overcast table painted. Built mass is the
	# warmest large area in the district, which is what makes a shell read as *somebody's* wall
	# rather than as an unlit patch of street; check_topdown.gd's wall lane measures the faces
	# lifted out of this colour against every floor that can touch them.
	"wall": Color("#6b5a45"),
	# A shut door: the wall's timber a shade warmer and darker, so a closed doorway reads as
	# part of the mass with a plank in it rather than as a gap. The open state draws the
	# threshold boards and the door face the doorway always drew; this is the closed one.
	"door": Color("#5c4a36"),
	# Glass reflects a sky, so it is the one cool thing on a warm street — the entry that says
	# what the mood is by being the exception to it. The rim is the sash around it, darker than
	# the pane the renderer lightens out of the glass colour, because a rim the pane's own value
	# is invisible (check_weather.gd's separation bound is the arithmetic).
	"window": Color("#6b8794"),
	"windowRim": Color("#5f7480"),
	"screen": Color("#454a37"),
	"low": Color("#524d47"),
	"player": Color("#e8d7a0"),
	"survivor": Color("#b9a97f"),
	# The floor under a raider archetype that declares no appearance. Content overrides it -- both
	# shipped archetypes do, with the *same* colour, because which raider is carrying the gun is
	# not something a look across a street is supposed to tell you.
	"raider": Color("#a2705a"),
	"wanderer": Color("#6f8f6a"),
	"glimpse": Color("#525a44"),
	# Findable but no longer a gold coin on wet asphalt: check_weather.gd holds this from both
	# sides — under its saturation and value ceilings, and still clearing the brightest ground
	# tint by a named margin, so a future tune cannot sink an item into the pavement.
	"groundItem": Color("#a89a70"),
	"groundItemEdge": Color("#4a3f22"),
	"outline": Color("#8b93a0"),
	# Inside a building, and the tile you step through to get there. `indoors` is a third array
	# over the same grid (docs/24's ground layer is the second), so an interior is not a tile type
	# and not a branch on one: the floor keeps the surface it stands on and is pulled towards this
	# warm board colour by INDOOR_MIX, which is what makes a shell read as a room from outside it.
	# The threshold is the door tile the generator recorded in map.buildings[].doors -- a walkable
	# Floor in a wall run, invisible until it was drawn as worn boards between two jambs.
	# The pack's wood plank floor's own mean since 2026-09-27, like the grounds above.
	"indoorFloor": Color("#6d4f36"),
	"threshold": Color("#6f5a44"),
	# The floor under a prop whose content declares no tint. Every shipped prop declares one
	# (prop.schema.json makes tint required), so this is the colour of a content mistake --
	# deliberately drab and deliberately visible, never a thing to rely on.
	"prop": Color("#6a5c4c"),
	"memory": Color("#454a38"),
	# What a tile, a tree or a parked car is pulled towards once it has left the current cone but
	# not the observer's memory of it -- the remembered map (docs/23, "The remembered map,
	# dimmed"). A muted, slightly cooler cousin of `memory`'s own dot rather than the same key
	# reused, so the two can move independently: one is a mark on the ground, this is a filter
	# over everything the street still remembers looking like.
	"rememberedTint": Color("#393d30"),
	# The roof a known building draws over the interior the survivor cannot see, when the
	# building's look names a material nobody has drawn yet -- the supported fallback, one warm
	# dark slab. A material with art draws its own sheet (dressing/street.json's `roofs`). The
	# tar sheet's own mid (tools/sprites/palette.py's `roof_tar`), so the fallback and the art
	# agree: dark, below every floor by 0.08 in luma (paved is the nearest, 0.107 away), where
	# the first pick #4e4740 sat 0.005 from undergrowth and read as ground seen from above.
	"roof": Color("#2c2722"),
	# The cool near-black the warm district sits in. Not a neutral dark and not a cheaper black:
	# these two are the *only* large areas allowed to go cold, and check_road_look.gd's cool family
	# pins them there, which is what makes a lit street read as lit rather than as merely brighter.
	"background": Color("#15141f"),
	"night": Color("#090820"),
	# The road dressing (presentation/road_paint.gd): worn lane paint, translucent so the asphalt
	# shows through; the kerb line where pavement meets ground; the sidewalk slab that replaces
	# the outermost rows of a wide street. check_road_look.gd's palette lane holds their ordering
	# — paint brightest of the road family, sidewalk over asphalt over background.
	"roadPaint": Color("#a99a7c8c"),
	"kerb": Color("#6b645b"),
	# The pack's two worn concretes' mean since 2026-09-27, like the grounds above.
	"sidewalk": Color("#999793"),
	# The screen's own marks, as opposed to the district's: the line a shape with no front uses
	# to say where it is looking, the aim cone's sway readout, and the rain. All three were
	# near-white literals inside the draw loop and read as the brightest things in the district;
	# they are keys now so check_weather.gd's property bounds can hold them quiet and a revert to
	# the bright grade is caught rather than noticed. The first two carry a little of the warm
	# grade so a mark does not read as a cold cutout over a warm street; the rain keeps its cool
	# cast, because rain is weather and weather belongs to the sky, not to the district. Eight-digit
	# hex is RGBA — the alpha is part of the colour, because these are washes over the world, not
	# fills of it.
	"facing": Color("#cfccc08c"),
	"aimCone": Color("#c9c2b04d"),
	"rain": Color("#c2c9cf21"),
	# The weather-look slice's two keys (docs/16, docs/30 "The sky has kinds"). `snow` is rain's
	# cool cast a shade paler and thinner-saturated -- a flake reads as a dot, not a streak, so it
	# earns less colour to carry -- at rain's own alpha, since both are the sky drawn over the
	# world rather than a fill of it. `lightning` is the screen flash a strike buys instead of a
	# sim light pulse (docs/adr/0016, "considered and not taken"): near-white but capped under the
	# mark band's own value ceiling, so even a flash stays inside the mood rather than blowing out
	# to the reference's raw white, at a low alpha so it reads as a beat, not a wipe.
	"snow": Color("#c8cdd621"),
	"lightning": Color("#d8d8cf59"),
	# Fog's veil, the seventh kind (docs/16). What fog *does* is the sim's -- `sightMul` shrinks
	# every observer's range, so the district edge closes in because nothing out there is seen any
	# more -- and this key is only what that closing looks like: snow's own cool cast at a weight
	# the streaks never earn, because a veil stands up for a whole span rather than crossing the
	# frame. Still the sky drawn over the world and not a fill of it, and capped under the flash's
	# alpha so a beat stays the loudest thing the sky does; the night wash is the night's own and
	# stacks over this rather than being folded into it.
	"fog": Color("#c8cdd64d"),
}

# (Two deletion batches live in this file's history rather than its text. `COLOUR_HEX`,
# fourteen string copies of the table above "for serialization, comparison": zero readers ever
# existed — the tenth dead code socket of the milestone, closed by removal. Then the weather
# slice's batch, the eleventh: three RGB string triplets, a three-entry shade table and a hex
# copy of the condition tints, every one read by nothing since the frozen renderer stayed
# behind with the oracle. The condition tints themselves are alive — the inventory panel and
# the paperdoll read them — and check_weather.gd asserts they survived the batch, so the next
# sweep cannot mistake the live table for the dead copies.)

# The ground layer, indexed by SimSurface.Surface (Paved 0 .. Rubble 4). docs/24's second
# array over the same grid: what is *under* a tile, as opposed to what is *in* it. Paved is
# the floor colour and not a shade of its own -- the street is what the district already
# looked like, so drawing the ground changed nothing about a paved tile, and check_topdown.gd
# asserts that identity rather than trusting it.
#
# Undergrowth gets a colour of its own rather than borrowing the screen tile's: they coincide
# often (docs/24 puts undergrowth under every screening tile) but they are different layers,
# and a green a shade denser than grass is what says "this is the slow way" on sight.
#
# tools/sprites/palette.py held a HARD COPY of these six as `SURFACE_TINTS` for its import-time
# ground guards until 2026-09-27. Those guards judge *generated* art, and since the pack's ground
# they judge it against GENERATOR_GROUNDS below -- the table that art was authored against --
# which is the copy palette.py now carries.
const SURFACE_TINTS: Array[Color] = [
	COLOURS["floor"], # Paved
	COLOURS["dirt"],
	COLOURS["grass"],
	COLOURS["undergrowth"],
	COLOURS["rubble"],
	COLOURS["water"],
]

# The warm-dark ground table the generated art was authored against: the eight ground entries
# above as they stood from the Dungeon Settlers regrade (2026-09-03) and the water entry
# (2026-09-09) until the pack's ground replaced them (2026-09-27). Nothing draws these colours any
# more. They are the grounds the guards that judge still-generated art *against* the ground go on
# reading, by the owner's answer of 2026-09-27 (relayed by the coordinator): regrading that art to
# the pack's brighter ground is the job of the slice that replaces the art, not the ground's. Each
# reader is named, and each retires with the art it judges:
#   * check_topdown.gd's WALL lane -- the procedural wall's cap and faces (the walls slice);
#   * check_weather.gd's ACCENT lane's groundItem floor -- the ground item's flat fallback colour;
#   * check_roof_look.gd's MOOD lane -- the generated wall and roof pictures (the walls slice);
#   * tools/sprites/palette.py's import-time guards, which hold a HARD COPY of this table as
#     `GENERATOR_GROUNDS` (the pawn, tree, car and wall ramps; the slices that retire each).
# docs/23's record for "The ground is the pack's" carries the measured shortfall of each against
# the pack's table, which is the number a later slice needs.
const GENERATOR_GROUNDS: Dictionary = {
	"floor": Color("#474240"),
	"dirt": Color("#584e40"),
	"grass": Color("#4f5440"),
	"undergrowth": Color("#414a37"),
	"rubble": Color("#4e4a46"),
	"water": Color("#424f5c"),
	"sidewalk": Color("#5e5852"),
	"indoorFloor": Color("#6a5540"),
}
# The six surfaces of GENERATOR_GROUNDS in `SimSurface.Surface` order, the shape SURFACE_TINTS has,
# for the guards that iterate surfaces.
const GENERATOR_SURFACES: Array[Color] = [
	GENERATOR_GROUNDS["floor"],
	GENERATOR_GROUNDS["dirt"],
	GENERATOR_GROUNDS["grass"],
	GENERATOR_GROUNDS["undergrowth"],
	GENERATOR_GROUNDS["rubble"],
	GENERATOR_GROUNDS["water"],
]

# How much darker deep water is than the ford beside it. Deep water is `Tile.Water`; the ford is
# an ordinary Floor on the same surface, so the two must read apart at a glance or a river has no
# visible channel and the player cannot see where it is crossable. Derived rather than authored
# for the reason the wall's face is: one colour to regrade, not two that can drift apart.
#
# Bounded from both ends, which is why it is a named constant rather than a number in the draw
# loop. The background is #15141f at 0.122, so a channel much below 0.19 reads as a hole in the
# map rather than as water. Against the pack's teal ford (value 0.337, 2026-09-27) 0.42 puts the
# channel at **0.196**, a gap of 0.141 -- the old slate ford sat at 0.361 and its channel at 0.209.
#
# Raised from 0.30 (channel 0.253) on the owner's call that shallow and deep must be discernible.
# The value alone is not what does it -- `WATER_SHORE_*` below is -- but the two together are.
const WATER_DEEP_SHADE: float = 0.42

# The shoreline. A value difference alone reads as "darker water" at a glance; an *edge* reads as
# a bank, and it is the cue that says which half you can put a foot in. So every deep tile draws a
# lit rim on each side that is not also deep -- the water's own edge, not the land's, so it is one
# pass over the channel rather than a second fringe rule over every ground beside it.
#
# Lifted out of the ford's colour rather than authored, the way the wall's face is lifted out of
# its cap: one water colour to regrade, and the shore cannot drift away from the water it edges.
const WATER_SHORE_LIGHTEN: float = 0.22
# A fraction of a tile, with a one-pixel floor so it survives a zoomed-out camera -- the same
# shape `WALL_FACE_SHARE` uses, and for the same reason.
const WATER_SHORE_SHARE: float = 0.16

# How far an indoor floor is pulled from its own surface towards COLOURS["indoorFloor"]. Not 1.0
# on purpose: the surface layer still has to show through, so a shop floored on rubble and a house
# floored on paving are not the same slab, and check_topdown.gd's ground lane keeps meaning what
# it says. Not 0.0 either -- at zero this is a mix that changes nothing, which is a dead socket.
const INDOOR_MIX: float = 0.62

# How built mass is shaded from above. A wall tile is a full tile because the sim blocks a full
# tile, but a full tile of the flat wall colour was the brightest thing on the screen and made a
# one-tile wall read as a block the size of the room behind it. So the tile is filled with the
# *cap* -- the top of the wall, seen from directly above and therefore the darkest of it -- and
# only the edges that meet something walkable get a lit *face* band a fraction of a tile wide.
# The footprint is unchanged and still opaque; what shrank is the amount of it that is bright.
#
# WALL_FACE_SHARE is a fraction of the tile, so the face stays the same fraction of a wall at
# every zoom (with a two-pixel floor, or it vanishes when a tile is 16 px). It must stay well
# under 0.5: at 0.5 the four bands meet and the whole tile is face again, which is the look this
# replaced. Both faces *lighten* the wall colour, the lit one more than the shaded one: every
# boundary between built mass and floor is drawn as a line brighter than any ground the district
# can put against it, which is what keeps a blocked tile from reading as an unlit walkable one.
# check_topdown.gd's wall lane measures exactly that, against every surface tint and its indoor
# mix, rather than trusting these four numbers to have been chosen carefully.
# WALL_FACE_DIM went 0.04 -> 0.07 when the grounds first rose off the oracle's near-black, and it
# held through the warm regrade without moving: the brightest ground a wall can touch is the
# threshold blend at luma 0.339, and the shaded face clears it by 0.067 against a FACE_DIM_MARGIN
# of 0.04 (the lit face by 0.125 against 0.08). If a future regrade eats those margins the fix is
# to bring `threshold`/`indoorFloor` down, under that lane's arbitration -- never to widen the
# assertion. Those margins are measured against GENERATOR_GROUNDS since the pack's ground
# (2026-09-27): against the pack's own table the lit face clears dirt by only 0.039 and the
# shaded face sits under it, which is the walls slice's to answer with the pack's wall modules.
# The zoom at and above which a floor tile draws its atlas cell (Appearance.ground_cell) rather
# than its flat tint. At 16 px a tile the texture is noise, so the flat tint stays the look
# there; a member of CameraUtil.ZOOM_STEPS on purpose, and check_road_look.gd asserts it.
const GROUND_TEXTURE_MIN_ZOOM: float = 32.0

const WALL_CAP_DARKEN: float = 0.28
const WALL_FACE_LIT: float = 0.16
const WALL_FACE_DIM: float = 0.07
const WALL_FACE_SHARE: float = 0.17

# The warm tint a lit pool is painted with, in two alphas split at POOL_SPLIT_METRES of remaining
# reach -- rgb(255, 204, 122), a step deeper and a step stronger than the frozen renderer's
# rgb(255, 214, 140). The warm-dark-fantasy grade puts a cool near-black around the district, so
# lamplight is now the thing that says where the district *is* rather than a nicety on top of it:
# check_weather.gd's accent lane pins the pools warm at r - b >= 0.35 (these clear it at 0.52) and
# still thin at alpha <= 0.25, so a pool stays a wash over the world and never a fill of it.
# This warm RGB remains the fallback for an absent or unrecognized content tint. Source-specific
# RGB comes from the source's content; only near/far alpha remains a renderer look choice.
const LIGHT_POOL_RGB: Color = Color(1.0, 0.80, 0.48)
const LIGHT_POOL_NEAR: Color = Color(LIGHT_POOL_RGB.r, LIGHT_POOL_RGB.g, LIGHT_POOL_RGB.b, 0.24)
const LIGHT_POOL_FAR: Color = Color(LIGHT_POOL_RGB.r, LIGHT_POOL_RGB.g, LIGHT_POOL_RGB.b, 0.11)
# The same two tints for the O-key light channel, which is a developer overlay rather than the
# look: it is being read as a diagram, so it is loud enough to see against a sunlit street.
const LIGHT_POOL_NEAR_OVERLAY: Color = Color(LIGHT_POOL_RGB.r, LIGHT_POOL_RGB.g, LIGHT_POOL_RGB.b, 0.45)
const LIGHT_POOL_FAR_OVERLAY: Color = Color(LIGHT_POOL_RGB.r, LIGHT_POOL_RGB.g, LIGHT_POOL_RGB.b, 0.22)

# The aim cone is drawn twice from one colour: the arc at the key's own alpha (it is the
# readout) and the two edge rays a shade quieter (they only say where it stops). A second key
# for "the same colour, dimmer" would be two values to keep in step; a factor is one, and
# check_weather.gd pins it strictly between 0 and 1 — a derived copy must be dimmer than its
# source, and never dead. The WALL_FACE_* constants above are the precedent for a look scalar
# living here.
const AIM_EDGE_DIM: float = 0.7

# How far a fully covered outdoor tile is pulled towards `snow` (SimWeather.snow_cover is already
# [0,1], so the ground read multiplies the two): not 1.0, so the surface tint still shows through
# a drift the way `INDOOR_MIX` leaves the surface showing through a board floor, and not 0.0 --
# a cover that changes nothing is a dead socket. The owner's call, 2026-09-06.
const SNOW_COVER_MAX: float = 0.55

# How far a remembered tile, tree or vehicle is pulled towards `rememberedTint`, and how much
# darker the result is besides: one function (`remembered`, below), so the whole memory look tunes
# by two numbers rather than one authored colour per material. Not 1.0 -- the surface still has to
# read as itself, the way `INDOOR_MIX` leaves a floor's own surface showing through its board mix
# -- and not 0.0, which would be the memory look's own dead socket.
const REMEMBERED_MIX: float = 0.45
const REMEMBERED_DARKEN: float = 0.30


# A colour as the remembered map draws it: pulled towards `rememberedTint` and darkened, alpha
# untouched (Color.darkened leaves it alone) so this works equally on an opaque tile fill and on a
# translucent modulate for a tree or a parked car's texture. One function for every arm the tile
# loop's `match` picks a colour with, so a remembered street is a filter over the same picture
# rather than a second one authored per material.
static func remembered(col: Color) -> Color:
	var target: Color = COLOURS["rememberedTint"] as Color
	var mixed := Color(
		lerpf(col.r, target.r, REMEMBERED_MIX),
		lerpf(col.g, target.g, REMEMBERED_MIX),
		lerpf(col.b, target.b, REMEMBERED_MIX),
		col.a,
	)
	return mixed.darkened(REMEMBERED_DARKEN)


# Four tints indexed by PartState (Unhurt 0..Unusable 3), read by the inventory panel and the
# paperdoll.
const CONDITION_TINTS: Array[Color] = [
	Color("#c9c4b8"), # Unhurt — bare line
	Color("#d9a253"), # Hurt
	Color("#c9564a"), # Badly hurt
	Color("#4a3b3a"), # Unusable
]
