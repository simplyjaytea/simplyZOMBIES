extends RefCounted
# Port of src/render/palette.ts — colours the district is. Not a theme.

const COLOURS: Dictionary = {
	"floor": Color("#1a1c1f"),
	"dirt": Color("#282219"),
	"grass": Color("#1b2a1b"),
	"rubble": Color("#26242a"),
	"tree": Color("#2e4a2c"),
	"wall": Color("#3b4048"),
	"window": Color("#7ec8e8"),
	"screen": Color("#25382a"),
	"low": Color("#2c2e33"),
	"player": Color("#e8d7a0"),
	"survivor": Color("#b9a97f"),
	"wanderer": Color("#6f8f6a"),
	"glimpse": Color("#4a5a48"),
	"groundItem": Color("#d8c07a"),
	"groundItemEdge": Color("#4a3f22"),
	"outline": Color("#8b93a0"),
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
