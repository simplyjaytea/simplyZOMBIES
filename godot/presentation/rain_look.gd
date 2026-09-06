extends RefCounted
# The sky's *look*, resolved at draw time from the tick, a hash and one content-agnostic record
# -- one screen-space streak layer, parametrised per weather kind. Whether it falls at all, and
# which kind, is the sim's (SimWeather, docs/adr/0015 and 0016): main.gd asks `SimWeather.kind`
# and `SimWeather.raining` before it asks this file for a sky, so this layer is drawn only while
# a span of rain, storm or snow is running. Within a span the sky is still a pure function of
# time and a hash, which is why nothing in here may draw from an RNG stream -- a stream would
# either sit on the sim registry (a draw the layout has to account for) or reseed per boot (a sky
# that differs between saves of the same moment). road_paint.gd's ground variation follows the
# identical rule, with the identical two primes.
#
# Pure statics only, and deliberately no static state of any kind: state here would be shared
# between the two worlds a gate boots in one process (the trap CLAUDE.md records for the
# kernel), and a streak layer has nothing worth remembering anyway -- every frame is derived
# whole from `t` and the `look` record `look_of` hands back for the kind on screen.
#
# Within a span it never stops. Each kind's own `intensityMin` keeps the swell off zero because
# the onset and the end of a span are the sim's events, not this layer's; what varies here is how
# hard it comes down, over a slow swell with a faster flutter inside it.

# `rain`'s own numbers, the ones the sky has always drawn -- kept as named constants (rather than
# folded straight into LOOKS) because they are still the ones the file's comments and this
# constant's own callers (LOOKS["rain"] and LOOKS["storm"], which shares all but two of them)
# read by name.
const STREAK_COUNT: int = 140 # check_weather.gd bounds this at 256
const FALL_PX_PER_TICK: float = 9.0
const SLANT: float = 0.22 # px of x drift per px of fall; the lean that says wind without simulating any
const INTENSITY_MIN: float = 0.4
const PERIOD_TICKS: int = 1800 # one slow swell ~= 90 s at 1x speed
const STREAK_LEN_MIN: float = 9.0
const STREAK_LEN_SPAN: float = 11.0
# Sky overscan above and below the viewport, so a streak enters and leaves off-screen instead
# of popping into existence at the top edge.
const WRAP_MARGIN: float = 32.0

# One record a kind: how fast it falls, how hard it leans, how long a streak reads, the swell's
# floor, how many streaks and which Palette key paints them. `storm` is `rain` louder (docs/16:
# rain's loud sibling) -- the same fall, lean and length, a higher floor so it is never a lull,
# and half again as many streaks. `snow` is its own shape entirely: falls a third as fast with
# more lean (a flake drifts further than it falls), and short enough (2-4 px) that a streak reads
# as a dot rather than a line, on its own cool `snow` key rather than rain's. The owner's calls,
# 2026-09-06.
const LOOKS: Dictionary = {
	"rain": {
		"fall": FALL_PX_PER_TICK,
		"slant": SLANT,
		"lenMin": STREAK_LEN_MIN,
		"lenSpan": STREAK_LEN_SPAN,
		"intensityMin": INTENSITY_MIN,
		"count": STREAK_COUNT,
		"colour": "rain",
	},
	"storm": {
		"fall": FALL_PX_PER_TICK,
		"slant": SLANT,
		"lenMin": STREAK_LEN_MIN,
		"lenSpan": STREAK_LEN_SPAN,
		"intensityMin": 0.8,
		"count": 200,
		"colour": "rain",
	},
	"snow": {
		"fall": 2.0,
		"slant": 0.35,
		"lenMin": 2.0,
		"lenSpan": 2.0,
		"intensityMin": 0.5,
		"count": STREAK_COUNT,
		"colour": "snow",
	},
}


# The record for a kind, or `rain`'s when the kind names nothing here -- a graceful default
# rather than a crash, the same shape `Appearance.ground_colour`'s null-map fallback takes.
static func look_of(kind: String) -> Dictionary:
	return LOOKS[kind] if LOOKS.has(kind) else LOOKS["rain"]

# Hash salts, distinct and far apart on purpose: XOR with a constant is a bijection, so three
# salts a few integers apart would give three visibly correlated streams off one `i * PRIME`.
const COL_SALT: int = 1
const LEN_SALT: int = 8191
const PHASE_SALT: int = 65537
const SWELL_SALT: int = 4099
const FLUTTER_SALT: int = 65521
# Lattice points of the flutter octave per PERIOD_TICKS; the swell uses one.
const FLUTTER_CELLS: int = 7


# The two spatial-hash primes road_paint.gd varies the ground with, masked non-negative so a
# negative lattice index (the swell's `i + 1` never is, but the maths should not care) cannot
# flip the modulo's sign.
static func _hash(a: int, b: int) -> int:
	return ((a * 73856093) ^ (b * 19349663)) & 0x7fffffff


static func _unit(a: int, b: int) -> float:
	return float(_hash(a, b) % 1021) / 1020.0


# One octave of integer-lattice value noise, smoothstep-interpolated. `cells` is how many
# lattice points cover one PERIOD_TICKS, so the two octaves of `intensity` differ only in that
# number and their salt.
static func _octave(t: float, cells: int, salt: int) -> float:
	var u: float = t / float(PERIOD_TICKS) * float(cells)
	var i: int = floori(u)
	var f: float = u - float(i)
	var s: float = f * f * (3.0 - 2.0 * f)
	return lerpf(_unit(i, salt), _unit(i + 1, salt), s)


# How hard it is coming down, in [look.intensityMin, 1]: a slow swell over PERIOD_TICKS and a
# faster flutter inside it, mixed and lifted off the kind's own floor. The swell shape (the two
# octaves, the salts, the 0.7/0.3 mix) is one function of `t` shared by every kind; only the
# floor it is lifted off differs, which is why a storm's sky is never a lull and a snowfall never
# stops either.
static func intensity(t: float, look: Dictionary) -> float:
	var floor_v: float = float(look.get("intensityMin", INTENSITY_MIN))
	var mixed: float = clampf(
		_octave(t, 1, SWELL_SALT) * 0.7 + _octave(t, FLUTTER_CELLS, FLUTTER_SALT) * 0.3, 0.0, 1.0
	)
	return floor_v + (1.0 - floor_v) * mixed


# The alpha multiplier the sky is drawn at: never below 0.6 of the rain key's own alpha, so
# heavier rain is a thicker curtain rather than the only rain there is.
static func alpha_scale(i: float) -> float:
	return 0.6 + 0.4 * i


# The whole sky as endpoint pairs -- head, foot, head, foot -- ready for one draw_multiline.
# Endpoints are snapped to PIXEL CENTRES in here (floor + 0.5), not at the call site, and not
# to integers: a 1 px quad hung between two whole coordinates lays its edges exactly on the
# rasteriser's sample points and draws NOTHING on the Compatibility renderer -- measured on
# this container, a whole sky at alpha 0.8 left a pixel diff of zero -- while a quad centred
# on x + 0.5 covers exactly one column, crisp. A caller that forgets to snap is a caller no
# gate can catch. Non-positive dimensions or a non-positive count yield an empty array --
# graceful absence, road_paint.gd's `mask_for(null)` precedent.
static func segments(t: float, width: float, height: float, look: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count: int = int(look.get("count", STREAK_COUNT))
	if width <= 0.0 or height <= 0.0 or count <= 0:
		return out
	var fall: float = float(look.get("fall", FALL_PX_PER_TICK))
	var slant: float = float(look.get("slant", SLANT))
	var len_min: float = float(look.get("lenMin", STREAK_LEN_MIN))
	var len_span: float = float(look.get("lenSpan", STREAK_LEN_SPAN))
	out.resize(count * 2)
	var span: float = height + WRAP_MARGIN * 2.0
	for i in count:
		var col: float = _unit(i, COL_SALT) * width
		var length: float = len_min + _unit(i, LEN_SALT) * len_span
		var phase: float = _unit(i, PHASE_SALT) * span
		# The column drifts sideways at the slant rate as the streak falls, rather than deriving
		# x from y: both stay inside their own wrap by construction, and a non-wrapping streak
		# moves down by exactly the kind's own `fall` per tick, which is the property the gate
		# pins, one kind at a time.
		var y: float = fposmod(phase + t * fall, span) - WRAP_MARGIN
		var x: float = fposmod(col + t * fall * slant, width)
		out[i * 2] = Vector2(floorf(x) + 0.5, floorf(y) + 0.5)
		out[i * 2 + 1] = Vector2(floorf(x + length * slant) + 0.5, floorf(y + length) + 0.5)
	return out


# Whether rain reaches this tile. A roof is the map's own `indoors` byte -- the third array over
# the grid, the one road_paint.gd already reads -- so the cull is a fact about the district, not
# a second list the renderer keeps. Off the map, or with no map at all, the sky is open: a
# fixture, a blank_map or a world booted without terrain draws rain everywhere rather than
# nowhere, because the visible failure is rain that vanished, not rain over a tile that does not
# exist. `!= 0` rather than SimTileMap.is_indoors' `== 1`: the two agree on every byte the
# generator writes (it only ever writes 0 and 1), and reading the byte directly keeps the null
# and bounds guards in one place instead of split across two files.
static func falls_at(map: Variant, tx: int, ty: int) -> bool:
	if map == null:
		return true
	var w: int = int(map.w)
	var h: int = int(map.h)
	if tx < 0 or ty < 0 or tx >= w or ty >= h:
		return true
	return int(map.indoors[ty * w + tx]) == 0
