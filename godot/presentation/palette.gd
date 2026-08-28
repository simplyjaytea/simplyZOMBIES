extends RefCounted
# Port of src/render/palette.ts — colours the district is. Not a theme.

const COLOURS: Dictionary = {
	"floor": Color("#1a1c1f"),
	"dirt": Color("#282219"),
	"grass": Color("#1b2a1b"),
	"undergrowth": Color("#1f3a1c"),
	"rubble": Color("#26242a"),
	"tree": Color("#2e4a2c"),
	"wall": Color("#3b4048"),
	"window": Color("#7ec8e8"),
	"screen": Color("#25382a"),
	"low": Color("#2c2e33"),
	"player": Color("#e8d7a0"),
	"survivor": Color("#b9a97f"),
	# The floor under a raider archetype that declares no appearance. Content overrides it -- both
	# shipped archetypes do, with the *same* colour, because which raider is carrying the gun is
	# not something a look across a street is supposed to tell you.
	"raider": Color("#a2705a"),
	"wanderer": Color("#6f8f6a"),
	"glimpse": Color("#4a5a48"),
	"groundItem": Color("#d8c07a"),
	"groundItemEdge": Color("#4a3f22"),
	"outline": Color("#8b93a0"),
	# Inside a building, and the tile you step through to get there. `indoors` is a third array
	# over the same grid (docs/24's ground layer is the second), so an interior is not a tile type
	# and not a branch on one: the floor keeps the surface it stands on and is pulled towards this
	# warm board colour by INDOOR_MIX, which is what makes a shell read as a room from outside it.
	# The threshold is the door tile the generator recorded in map.buildings[].doors -- a walkable
	# Floor in a wall run, invisible until it was drawn as worn boards between two jambs.
	"indoorFloor": Color("#3a3128"),
	"threshold": Color("#4d4030"),
	# The floor under a prop whose content declares no tint. Every shipped prop declares one
	# (prop.schema.json makes tint required), so this is the colour of a content mistake --
	# deliberately drab and deliberately visible, never a thing to rely on.
	"prop": Color("#5a5148"),
	"memory": Color("#3d4a3c"),
	"background": Color("#0d0e10"),
	"night": Color("#060a1a"),
}

# string versions for where Color not usable (e.g. serialization, comparison)
const COLOUR_HEX: Dictionary = {
	"floor": "#1a1c1f",
	"dirt": "#282219",
	"grass": "#1b2a1b",
	"rubble": "#26242a",
	"tree": "#2e4a2c",
	"wall": "#3b4048",
	"window": "#7ec8e8",
	"screen": "#25382a",
	"low": "#2c2e33",
	"player": "#e8d7a0",
	"survivor": "#b9a97f",
	"wanderer": "#6f8f6a",
	"groundItem": "#d8c07a",
	"outline": "#8b93a0",
}

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

const SWING_RGB: String = "232, 215, 160"
const NIGHT_RGB: String = "6, 10, 26"
const SHADOW_RGB: String = "0, 0, 0"

const SHADE: Dictionary = {
	"away": Color("00000057"), # 0.34 alpha
	"near": Color("00000029"), # 0.16
	"cap": Color("ffffff1a"), # 0.10
}

# Four tints indexed by PartState (Unhurt 0..Unusable 3). Port of CONDITION_TINTS.
const CONDITION_TINTS: Array[Color] = [
	Color("#c9c4b8"), # Unhurt — bare line
	Color("#d9a253"), # Hurt
	Color("#c9564a"), # Badly hurt
	Color("#4a3b3a"), # Unusable
]

const CONDITION_TINT_HEX: Array[String] = ["#c9c4b8", "#d9a253", "#c9564a", "#4a3b3a"]
