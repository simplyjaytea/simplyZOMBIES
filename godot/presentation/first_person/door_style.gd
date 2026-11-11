extends RefCounted
# Per-template door and window dressing for the first-person district (docs/41, presentation only).
# A manifested building's door shows its leaf and frame here, and its window its casing. These are
# extra boxes drawn on the tile's face. The band boxes `district_view.gd` draws for a door or a window
# are untouched: they stay the collision and ray truth (docs/40, `SimSpace.PROFILE`), and an open
# door's lintel (2200..2550 mm) and a closed door's full box stay where the sim put them.
#
# The table is keyed by the manifest slug (the GLB's file name, e.g. `bungalow_flat`) with a `default`
# row for a door that no manifested building owns. Each row's `wall` is the reference albedo of the
# wall family the manifest names: the atlas cell's mean colour for that family's first style, times
# the first variation tint. `leaf` and `frame` are set against it: the leaf differs in luminance by
# about 0.28, the frame by about 0.14, darker for a light wall and lighter for a dark one. `leaf`
# must differ from `wall` by at least `LUMA_MIN` (`godot:check:fp_geometry`, DOORSTYLE lane).
#
# Every box is a pure function of (slug, tile, face, door state). Nothing here draws from an RNG or a
# tick. A door's leaf is 0.90 m wide and the frame's jambs stand inside that width; an open leaf lies
# along the inner jamb inside the tile. Window casing is on each face that meets open ground.

const DOOR_TOP: float = 2.20
const LINTEL_TOP: float = 2.40
const DOOR_WIDTH: float = 0.90
const LEAF_PROUD: float = 0.024
const FRAME_PROUD: float = 0.03
const OPEN_LEAF_WIDTH: float = 0.03
const WINDOW_SILL: float = 1.00
const WINDOW_TOP: float = 2.10
const SILL_DEPTH: float = 0.08
const SILL_HEIGHT: float = 0.06
const CASING_LINTEL: float = 0.10
const GLASS_LOW: float = 1.20
const GLASS_HIGH: float = 1.90
const LUMA_MIN: float = 0.2
const DEFAULT_KEY: String = "default"
const GLASS: Color = Color(0.52, 0.62, 0.66)

# Table of rows: {wall, leaf, frame: Color, frame_w: m (0.06..0.12), glazed: upper glass panel on a door}.
const TABLE: Dictionary = {
	"arcade_retail": {"wall": Color(0.501, 0.476, 0.416), "leaf": Color(0.768, 0.757, 0.729), "frame": Color(0.635, 0.616, 0.572), "frame_w": 0.10, "glazed": true},
	"bungalow_flat": {"wall": Color(0.531, 0.502, 0.437), "leaf": Color(0.236, 0.223, 0.194), "frame": Color(0.383, 0.362, 0.315), "frame_w": 0.07, "glazed": false},
	"cabin_long": {"wall": Color(0.531, 0.502, 0.437), "leaf": Color(0.236, 0.223, 0.194), "frame": Color(0.383, 0.362, 0.315), "frame_w": 0.07, "glazed": false},
	"cabin_small": {"wall": Color(0.531, 0.502, 0.437), "leaf": Color(0.236, 0.223, 0.194), "frame": Color(0.383, 0.362, 0.315), "frame_w": 0.07, "glazed": false},
	"clinic_storefront": {"wall": Color(0.531, 0.502, 0.437), "leaf": Color(0.236, 0.223, 0.194), "frame": Color(0.383, 0.362, 0.315), "frame_w": 0.10, "glazed": true},
	"gatehouse_yard": {"wall": Color(0.531, 0.502, 0.437), "leaf": Color(0.236, 0.223, 0.194), "frame": Color(0.383, 0.362, 0.315), "frame_w": 0.06, "glazed": false},
	"hall_civic": {"wall": Color(0.746, 0.715, 0.631), "leaf": Color(0.454, 0.435, 0.384), "frame": Color(0.6, 0.575, 0.508), "frame_w": 0.10, "glazed": false},
	"house_corner": {"wall": Color(0.531, 0.502, 0.437), "leaf": Color(0.236, 0.223, 0.194), "frame": Color(0.383, 0.362, 0.315), "frame_w": 0.07, "glazed": false},
	"house_gable": {"wall": Color(0.501, 0.476, 0.416), "leaf": Color(0.768, 0.757, 0.729), "frame": Color(0.635, 0.616, 0.572), "frame_w": 0.07, "glazed": false},
	"house_large": {"wall": Color(0.746, 0.715, 0.631), "leaf": Color(0.454, 0.435, 0.384), "frame": Color(0.6, 0.575, 0.508), "frame_w": 0.07, "glazed": false},
	"house_narrow": {"wall": Color(0.531, 0.502, 0.437), "leaf": Color(0.236, 0.223, 0.194), "frame": Color(0.383, 0.362, 0.315), "frame_w": 0.07, "glazed": false},
	"house_small": {"wall": Color(0.531, 0.502, 0.437), "leaf": Color(0.236, 0.223, 0.194), "frame": Color(0.383, 0.362, 0.315), "frame_w": 0.07, "glazed": false},
	"kiosk_corner": {"wall": Color(0.531, 0.502, 0.437), "leaf": Color(0.236, 0.223, 0.194), "frame": Color(0.383, 0.362, 0.315), "frame_w": 0.10, "glazed": true},
	"koban_box": {"wall": Color(0.531, 0.502, 0.437), "leaf": Color(0.236, 0.223, 0.194), "frame": Color(0.383, 0.362, 0.315), "frame_w": 0.07, "glazed": false},
	# The konbini's doors are glass in thin aluminium, as its storefront is: a dark glass leaf and a silver
	# frame, lighter than the wall rather than darker. Its front windows draw no casing (storefront).
	"konbini_road": {"wall": Color(0.531, 0.502, 0.437), "leaf": Color(0.205, 0.245, 0.262), "frame": Color(0.737, 0.745, 0.741), "frame_w": 0.06, "glazed": false},
	"shed_garage": {"wall": Color(0.203, 0.171, 0.143), "leaf": Color(0.474, 0.453, 0.434), "frame": Color(0.338, 0.312, 0.289), "frame_w": 0.06, "glazed": false},
	"shed_lockup": {"wall": Color(0.203, 0.171, 0.143), "leaf": Color(0.474, 0.453, 0.434), "frame": Color(0.338, 0.312, 0.289), "frame_w": 0.06, "glazed": false},
	"shed_tin": {"wall": Color(0.203, 0.171, 0.143), "leaf": Color(0.474, 0.453, 0.434), "frame": Color(0.338, 0.312, 0.289), "frame_w": 0.06, "glazed": false},
	"shop_corner": {"wall": Color(0.746, 0.715, 0.631), "leaf": Color(0.454, 0.435, 0.384), "frame": Color(0.6, 0.575, 0.508), "frame_w": 0.10, "glazed": true},
	"shrine_village": {"wall": Color(0.531, 0.502, 0.437), "leaf": Color(0.236, 0.223, 0.194), "frame": Color(0.383, 0.362, 0.315), "frame_w": 0.07, "glazed": false},
	"station_small": {"wall": Color(0.531, 0.502, 0.437), "leaf": Color(0.236, 0.223, 0.194), "frame": Color(0.383, 0.362, 0.315), "frame_w": 0.07, "glazed": false},
	"store_grocery": {"wall": Color(0.531, 0.502, 0.437), "leaf": Color(0.236, 0.223, 0.194), "frame": Color(0.383, 0.362, 0.315), "frame_w": 0.10, "glazed": true},
	"terrace_pair": {"wall": Color(0.746, 0.715, 0.631), "leaf": Color(0.454, 0.435, 0.384), "frame": Color(0.6, 0.575, 0.508), "frame_w": 0.07, "glazed": false},
	"unit_industrial": {"wall": Color(0.203, 0.171, 0.143), "leaf": Color(0.474, 0.453, 0.434), "frame": Color(0.338, 0.312, 0.289), "frame_w": 0.06, "glazed": false},
	"warehouse_brick": {"wall": Color(0.746, 0.715, 0.631), "leaf": Color(0.454, 0.435, 0.384), "frame": Color(0.6, 0.575, 0.508), "frame_w": 0.06, "glazed": false},
	"workshop_unit": {"wall": Color(0.203, 0.171, 0.143), "leaf": Color(0.474, 0.453, 0.434), "frame": Color(0.338, 0.312, 0.289), "frame_w": 0.10, "glazed": false},
	"default": {"wall": Color(0.531, 0.502, 0.437), "leaf": Color(0.236, 0.223, 0.194), "frame": Color(0.383, 0.362, 0.315), "frame_w": 0.08, "glazed": false},
}


static func style_for(slug: String) -> Dictionary:
	if TABLE.has(slug):
		return TABLE[slug] as Dictionary
	return TABLE[DEFAULT_KEY] as Dictionary


static func has_row(slug: String) -> bool:
	return TABLE.has(slug)


static func luminance(colour: Color) -> float:
	return 0.2126 * colour.r + 0.7152 * colour.g + 0.0722 * colour.b


# Whether the leaf's luminance differs from the wall's by at least LUMA_MIN. A planted style, a leaf
# set to the wall colour, fails this.
static func contrast_ok(style: Dictionary) -> bool:
	return absf(luminance(style["leaf"] as Color) - luminance(style["wall"] as Color)) >= LUMA_MIN


# One tile-local point to a world point. `a` runs along the wall, `b` through it, `h` is up.
static func _at(tx: int, ty: int, along_x: bool, a: float, b: float, h: float) -> Vector3:
	if along_x:
		return Vector3(float(tx) + a, h, float(ty) + b)
	return Vector3(float(tx) + b, h, float(ty) + a)


static func _box(tx: int, ty: int, along_x: bool, a0: float, a1: float, b0: float, b1: float, h0: float, h1: float, colour: Color) -> Dictionary:
	var lo: Vector3 = _at(tx, ty, along_x, minf(a0, a1), minf(b0, b1), h0)
	var hi: Vector3 = _at(tx, ty, along_x, maxf(a0, a1), maxf(b0, b1), h1)
	var low: Vector3 = Vector3(minf(lo.x, hi.x), minf(lo.y, hi.y), minf(lo.z, hi.z))
	var high: Vector3 = Vector3(maxf(lo.x, hi.x), maxf(lo.y, hi.y), maxf(lo.z, hi.z))
	return {"min": low, "max": high, "colour": colour}


# The boxes of one door tile. `open_side` is the tile's outward side (Vector2i, unit, perpendicular to
# the wall run). `open` picks an open leaf (swung along the inner jamb) or a closed one (across the
# aperture, proud of the face). Frame and lintel are the same either way.
static func door_boxes(tx: int, ty: int, along_x: bool, open_side: Vector2i, open: bool, style: Dictionary) -> Array:
	var out: Array = []
	var s: float = float(open_side.y) if along_x else float(open_side.x)
	var sign_b: float = 1.0 if s >= 0.0 else -1.0
	var face: float = 1.0 if sign_b > 0.0 else 0.0
	var fw: float = float(style["frame_w"])
	var frame: Color = style["frame"] as Color
	var leaf: Color = style["leaf"] as Color
	var left: float = 0.5 - DOOR_WIDTH * 0.5
	var right: float = 0.5 + DOOR_WIDTH * 0.5
	var proud: float = sign_b * FRAME_PROUD
	out.append(_box(tx, ty, along_x, left, left + fw, face, face + proud, 0.0, DOOR_TOP, frame))
	out.append(_box(tx, ty, along_x, right - fw, right, face, face + proud, 0.0, DOOR_TOP, frame))
	out.append(_box(tx, ty, along_x, left, right, face, face + proud, DOOR_TOP, LINTEL_TOP, frame))
	if open:
		var inner: float = right - fw
		out.append(_box(tx, ty, along_x, inner - OPEN_LEAF_WIDTH, inner, face, face - sign_b * (DOOR_WIDTH), 0.0, DOOR_TOP - 0.01, leaf))
	else:
		var b0: float = face + sign_b * 0.004
		out.append(_box(tx, ty, along_x, left + fw, right - fw, b0, face + sign_b * LEAF_PROUD, 0.0, DOOR_TOP - 0.01, leaf))
		if bool(style["glazed"]):
			out.append(_box(tx, ty, along_x, left + fw + 0.06, right - fw - 0.06, face + sign_b * LEAF_PROUD, face + sign_b * (LEAF_PROUD + 0.002), GLASS_LOW, GLASS_HIGH, GLASS))
	return out


# The casing of one window tile on one face (`side`, a unit Vector2i) that meets open ground: two
# jambs at the tile's edges, a sill 0.08 m proud at 1.00 m, and a lintel casing under the head band.
static func window_boxes(tx: int, ty: int, along_x: bool, side: Vector2i, style: Dictionary) -> Array:
	var out: Array = []
	var s: float = float(side.y) if along_x else float(side.x)
	var sign_b: float = 1.0 if s >= 0.0 else -1.0
	var face: float = 1.0 if sign_b > 0.0 else 0.0
	var fw: float = float(style["frame_w"])
	var frame: Color = style["frame"] as Color
	var proud: float = sign_b * FRAME_PROUD
	out.append(_box(tx, ty, along_x, 0.0, fw, face, face + proud, WINDOW_SILL, WINDOW_TOP, frame))
	out.append(_box(tx, ty, along_x, 1.0 - fw, 1.0, face, face + proud, WINDOW_SILL, WINDOW_TOP, frame))
	out.append(_box(tx, ty, along_x, 0.0, 1.0, face, face + sign_b * SILL_DEPTH, WINDOW_SILL - SILL_HEIGHT, WINDOW_SILL, frame))
	out.append(_box(tx, ty, along_x, 0.0, 1.0, face, face + proud, WINDOW_TOP, WINDOW_TOP + CASING_LINTEL, frame))
	return out
