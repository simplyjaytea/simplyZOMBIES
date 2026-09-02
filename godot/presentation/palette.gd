extends RefCounted
# Began as a port of src/render/palette.ts — colours the district is. Not a theme. The ground
# and built-mass entries have since **diverged from the frozen palette.ts** on purpose: docs/30's
# art decision ("The art style: B, picked from a reference") fixes the mood as muted, overcast,
# desaturated urban decay, and the near-black grounds the oracle shipped read as a cave, not an
# overcast street. The regrade is held by properties rather than by anybody's memory —
# check_road_look.gd's palette lane pins the ground and road bounds, check_weather.gd's accent
# lane pins the glass, the ground items and the screen's own marks, and both prove the old
# tables fail them — so tune by screenshot inside those bounds, and never by reverting to
# palette.ts, which stays frozen with its oracle.

const COLOURS: Dictionary = {
	"floor": Color("#3f4143"),
	"dirt": Color("#524e40"),
	"grass": Color("#4e5442"),
	"undergrowth": Color("#46503d"),
	"rubble": Color("#4a4644"),
	"tree": Color("#3d4a38"),
	"wall": Color("#55575c"),
	# An overcast pane, not a lit aquarium — the last of the oracle's bright accents to go in
	# the weather slice's regrade. The rim is the sash around it, darker than the pane the
	# renderer lightens out of the glass colour, because a rim the pane's own value is invisible
	# (check_weather.gd's separation bound is the arithmetic).
	"window": Color("#6b8794"),
	"windowRim": Color("#5f7480"),
	"screen": Color("#3f4a3b"),
	"low": Color("#484a4d"),
	"player": Color("#e8d7a0"),
	"survivor": Color("#b9a97f"),
	# The floor under a raider archetype that declares no appearance. Content overrides it -- both
	# shipped archetypes do, with the *same* colour, because which raider is carrying the gun is
	# not something a look across a street is supposed to tell you.
	"raider": Color("#a2705a"),
	"wanderer": Color("#6f8f6a"),
	"glimpse": Color("#4a5a48"),
	# Findable but no longer a gold coin on wet asphalt: check_weather.gd holds this from both
	# sides — muted under its value ceiling, and still clearing the brightest ground tint by a
	# named margin, so a future tune cannot sink an item into the pavement.
	"groundItem": Color("#a89a70"),
	"groundItemEdge": Color("#4a3f22"),
	"outline": Color("#8b93a0"),
	# Inside a building, and the tile you step through to get there. `indoors` is a third array
	# over the same grid (docs/24's ground layer is the second), so an interior is not a tile type
	# and not a branch on one: the floor keeps the surface it stands on and is pulled towards this
	# warm board colour by INDOOR_MIX, which is what makes a shell read as a room from outside it.
	# The threshold is the door tile the generator recorded in map.buildings[].doors -- a walkable
	# Floor in a wall run, invisible until it was drawn as worn boards between two jambs.
	"indoorFloor": Color("#5a4c3c"),
	"threshold": Color("#6a5844"),
	# The floor under a prop whose content declares no tint. Every shipped prop declares one
	# (prop.schema.json makes tint required), so this is the colour of a content mistake --
	# deliberately drab and deliberately visible, never a thing to rely on.
	"prop": Color("#5a5148"),
	"memory": Color("#3d4a3c"),
	"background": Color("#1b1c1e"),
	"night": Color("#060a1a"),
	# The road dressing (presentation/road_paint.gd): worn lane paint, translucent so the asphalt
	# shows through; the kerb line where pavement meets ground; the sidewalk slab that replaces
	# the outermost rows of a wide street. check_road_look.gd's palette lane holds their ordering
	# — paint brightest of the road family, sidewalk over asphalt over background.
	"roadPaint": Color("#8e8d848c"),
	"kerb": Color("#6d6f6e"),
	"sidewalk": Color("#5c5e60"),
	# The screen's own marks, as opposed to the district's: the line a shape with no front uses
	# to say where it is looking, the aim cone's sway readout, and the rain. All three were
	# near-white literals inside the draw loop and read as the brightest things on an overcast
	# street; they are keys now so check_weather.gd's property bounds can hold them muted and a
	# revert to the bright grade is caught rather than noticed. Eight-digit hex is RGBA — the
	# alpha is part of the colour, because these are washes over the world, not fills of it.
	"facing": Color("#cfccc08c"),
	"aimCone": Color("#b9c2c94d"),
	"rain": Color("#c2c9cf21"),
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
const SURFACE_TINTS: Array[Color] = [
	COLOURS["floor"], # Paved
	COLOURS["dirt"],
	COLOURS["grass"],
	COLOURS["undergrowth"],
	COLOURS["rubble"],
]

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
# WALL_FACE_DIM went 0.04 -> 0.07 with the overcast regrade: the grounds all rose (a threshold
# tile mixes to 0.329 luma where the old table's brightest ground sat far lower), and the shaded
# face has to clear the brightest of them by check_topdown's FACE_DIM_MARGIN or a wall's south
# and east edges vanish into a doorway. A value retune under that lane's arbitration, not an
# assertion change.
# The zoom at and above which a floor tile draws its atlas cell (Appearance.ground_cell) rather
# than its flat tint. At 16 px a tile the texture is noise, so the flat tint stays the look
# there; a member of CameraUtil.ZOOM_STEPS on purpose, and check_road_look.gd asserts it.
const GROUND_TEXTURE_MIN_ZOOM: float = 32.0

const WALL_CAP_DARKEN: float = 0.28
const WALL_FACE_LIT: float = 0.16
const WALL_FACE_DIM: float = 0.07
const WALL_FACE_SHARE: float = 0.17

# The warm tint a lit pool is painted with, in two alphas split at POOL_SPLIT_METRES of remaining
# reach -- rgb(255, 214, 140), the frozen renderer's light overlay, unchanged. **One** warm tint
# for every source this slice: a candle, a campfire and a floodlight all paint the same colour and
# differ only in how far the pool reaches. Per-source tint from content (`light: {tint}` beside
# `light: {magnitude}`) is the named follow-up in docs/23 -- it is a content axis, not a branch to
# grow in the draw loop, so it waits for the content shape rather than for an `if id ==` here.
const LIGHT_POOL_NEAR: Color = Color(1.0, 214.0 / 255.0, 140.0 / 255.0, 0.20)
const LIGHT_POOL_FAR: Color = Color(1.0, 214.0 / 255.0, 140.0 / 255.0, 0.09)
# The same two tints for the O-key light channel, which is a developer overlay rather than the
# look: it is being read as a diagram, so it is loud enough to see against a sunlit street.
const LIGHT_POOL_NEAR_OVERLAY: Color = Color(1.0, 214.0 / 255.0, 140.0 / 255.0, 0.45)
const LIGHT_POOL_FAR_OVERLAY: Color = Color(1.0, 214.0 / 255.0, 140.0 / 255.0, 0.22)

# The aim cone is drawn twice from one colour: the arc at the key's own alpha (it is the
# readout) and the two edge rays a shade quieter (they only say where it stops). A second key
# for "the same colour, dimmer" would be two values to keep in step; a factor is one, and
# check_weather.gd pins it strictly between 0 and 1 — a derived copy must be dimmer than its
# source, and never dead. The WALL_FACE_* constants above are the precedent for a look scalar
# living here.
const AIM_EDGE_DIM: float = 0.7

# Four tints indexed by PartState (Unhurt 0..Unusable 3), read by the inventory panel and the
# paperdoll.
const CONDITION_TINTS: Array[Color] = [
	Color("#c9c4b8"), # Unhurt — bare line
	Color("#d9a253"), # Hurt
	Color("#c9564a"), # Badly hurt
	Color("#4a3b3a"), # Unusable
]
