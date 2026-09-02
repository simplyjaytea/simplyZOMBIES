extends RefCounted
# The road dressing, resolved at draw time from the street manifest the generator carved
# (`map.streets`) -- lane paint, sidewalks and kerbs as *paint over the ground*, never tiles.
# The sim knows nothing here exists: a street is Floor + SURFACE_PAVED to every mechanism that
# walks, hears or draws speed off it, and this file only decides what the pavement looks like.
# That is why it lives in presentation/ and why nothing in it may draw from an RNG stream --
# the picture must be a pure function of the map, identical on every boot of the same seed,
# without spending a draw the sim would have to account for.
#
# Pure statics only, and deliberately **no static state**: a `static var` cache here would be
# shared between the two worlds a gate boots in one process (the trap CLAUDE.md records for the
# kernel), so the mask is cached by the drawing node instead (`main.gd`'s `_thresholds`
# precedent) and this file stays a resolver.
#
# The mask is a byte per tile:
#   MASK_NONE     -- not street pavement; draw nothing extra.
#   MASK_ASPHALT  -- in a street span and still paved; kerbs may edge it.
#   MASK_SIDEWALK -- the outermost row each side of a wide street; drawn as its own slab colour.
#   MASK_DASH     -- the carriageway's centre row, alternating lane-paint tiles -- painted only
#                    where a centre row exists (see `dash_row`).
#
# "Still paved" is load-bearing: the annex stamp and the terrain pass legitimately overwrite
# parts of a span (a lawn grown to the kerb, a colony wall across the old road), and worn-through
# wins -- the mask goes quiet wherever the pavement is gone rather than painting markings on
# grass. Junctions -- tiles covered by an x-span and a y-span at once -- carry plain asphalt with
# markings suppressed, which is how a crossing reads worn instead of gridded. Sidewalks want a
# span at least SIDEWALK_MIN_WIDTH wide and dashes at least DASH_MIN_WIDTH *and a carriageway
# with a middle row*, so the shipped width-3 town-centre streets (and the suburb's width-2
# miniature alleys) get kerbs only -- an authored floor, asserted by check_road_look.gd, not
# an accident of the data.

const SimSurface = preload("res://sim/map/surface.gd")

const MASK_NONE: int = 0
const MASK_ASPHALT: int = 1
const MASK_SIDEWALK: int = 2
const MASK_DASH: int = 3

const SIDEWALK_MIN_WIDTH: int = 5
const DASH_MIN_WIDTH: int = 4

# Kerb edge bits, one per side of a tile.
const EDGE_N: int = 1
const EDGE_E: int = 2
const EDGE_S: int = 4
const EDGE_W: int = 8

# How far the per-tile ground variation may push a channel, in colour value. Small on purpose:
# it exists to break the flat fill up close, not to be a second palette.
const VARIATION_MAX: float = 0.025


# The row a centre line may be painted on, or -1 when the carriageway has no centre. The
# carriageway is the span minus its sidewalks (one row each side once the span is wide enough to
# carry them), and a run of rows has a middle row only when it is an odd count. The shipped
# suburb was width 6 until the roads slice: with sidewalks that is a four-row carriageway, and
# `at + width / 2` put the line on row 3 of 1..4 -- two lanes one side, one the other, which is
# the asymmetry the owner saw. Refusing to paint is the honest answer for an even carriageway:
# there is no row to paint on, and shifting the paint half a tile draws a line centred on
# nothing. check_road_look.gd's CENTRE lane holds both halves -- 7 paints at at+3, 6 paints not.
static func dash_row(at: int, width: int) -> int:
	if width < DASH_MIN_WIDTH:
		return -1
	var inset: int = 1 if width >= SIDEWALK_MIN_WIDTH else 0
	var lanes: int = width - 2 * inset
	if lanes % 2 == 0:
		return -1
	return at + inset + lanes / 2


# One byte per tile, resolved from the manifest. A map with no manifest -- a fixture, a
# `blank_map`, an old save's regenerated ground before the streets pass ran -- yields an all-zero
# mask and the street simply draws unpainted, which is what graceful absence means here.
static func mask_for(map: Variant) -> PackedByteArray:
	var out := PackedByteArray()
	if map == null:
		return out
	var w: int = int(map.w)
	var h: int = int(map.h)
	out.resize(w * h)
	var spans: Array = map.streets as Array
	if spans.is_empty():
		return out

	# First pass: how many spans cover each tile, so a junction can be told from a lane. Capped
	# at 2 because "more than one" is the whole question.
	var cover := PackedByteArray()
	cover.resize(w * h)
	for span_value in spans:
		var span: Dictionary = span_value as Dictionary
		for along in range(int(span["from"]), int(span["to"]) + 1):
			for off in int(span["width"]):
				var tx: int = int(span["at"]) + off if String(span["axis"]) == "x" else along
				var ty: int = along if String(span["axis"]) == "x" else int(span["at"]) + off
				if tx < 0 or ty < 0 or tx >= w or ty >= h:
					continue
				var idx: int = ty * w + tx
				if cover[idx] < 2:
					cover[idx] = cover[idx] + 1

	# Second pass: assign. Order-independent by construction -- a tile in two spans is forced to
	# plain asphalt whichever span writes it, and a tile in one span is written by that span alone.
	for span_value2 in spans:
		var span2: Dictionary = span_value2 as Dictionary
		var at: int = int(span2["at"])
		var width: int = int(span2["width"])
		var vertical: bool = String(span2["axis"]) == "x"
		var centre: int = dash_row(at, width)
		for along in range(int(span2["from"]), int(span2["to"]) + 1):
			for off in width:
				var tx: int = at + off if vertical else along
				var ty: int = along if vertical else at + off
				if tx < 0 or ty < 0 or tx >= w or ty >= h:
					continue
				var idx: int = ty * w + tx
				# Worn-through wins: paint only what is still outdoor pavement.
				if int(map.surfaces[idx]) != SimSurface.Surface.Paved:
					continue
				if int(map.indoors[idx]) == 1:
					continue
				if cover[idx] > 1:
					out[idx] = MASK_ASPHALT
					continue
				var value: int = MASK_ASPHALT
				if width >= SIDEWALK_MIN_WIDTH and (off == 0 or off == width - 1):
					value = MASK_SIDEWALK
				elif centre >= 0 and at + off == centre and (tx + ty) % 2 == 0:
					value = MASK_DASH
				out[idx] = value
	return out


# Which sides of a masked tile meet non-paved outdoor ground -- the kerb line, as an edge
# bitmask. Read per drawn tile rather than stored, the way _draw_solid_tile reads its exposed
# edges: a kerb is a fact about what stands beside the pavement *now*. A neighbour that is still
# pavement (in a span or not -- a driveway, a wall opening's run) continues the slab and gets no
# kerb; an indoor neighbour is a building edge, which is the wall's line to draw, not ours.
static func kerb_edges(map: Variant, mask: PackedByteArray, tx: int, ty: int) -> int:
	if map == null:
		return 0
	var w: int = int(map.w)
	var h: int = int(map.h)
	if tx < 0 or ty < 0 or tx >= w or ty >= h:
		return 0
	var idx: int = ty * w + tx
	if idx >= mask.size() or mask[idx] == MASK_NONE:
		return 0
	var out: int = 0
	for step in [[0, -1, EDGE_N], [1, 0, EDGE_E], [0, 1, EDGE_S], [-1, 0, EDGE_W]]:
		var nx: int = tx + int((step as Array)[0])
		var ny: int = ty + int((step as Array)[1])
		if nx < 0 or ny < 0 or nx >= w or ny >= h:
			continue
		var n: int = ny * w + nx
		if int(map.indoors[n]) == 1:
			continue
		if int(map.surfaces[n]) == SimSurface.Surface.Paved:
			continue
		out |= int((step as Array)[2])
	return out


# The per-tile ground variation: a small value offset from a position hash, the two spatial-hash
# primes, folded into [-VARIATION_MAX, +VARIATION_MAX]. **Deliberately no RNG stream**: a stream
# would either sit on the sim registry (a draw the layout has to account for) or reseed per boot
# (a district whose ground shimmers between saves). A pure hash of the tile position is
# deterministic across boots, saves and gate worlds by construction, which is the property
# check_road_look.gd's variation lane pins.
static func vary(tx: int, ty: int) -> float:
	var bits: int = ((tx * 73856093) ^ (ty * 19349663)) & 0x7fffffff
	var unit: float = float(bits % 1021) / 1020.0
	return (unit * 2.0 - 1.0) * VARIATION_MAX
