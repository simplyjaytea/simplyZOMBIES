extends RefCounted
# How the stockpile looks on the street: slice S2 of the stockpile plan. The zone is the sim's
# (`SimStockpile.tiles`, and `SimStockpile.preview` for what a drag would change); this file decides
# only how its tiles are painted, as pure functions over plain arguments, so `godot:check:memory`'s
# STOCKPILE lane judges the rules without a frame and main.gd's `_draw_stockpile` draws exactly what
# they answer.
#
# The rules, each one a lane:
#   * **Never on ground the player has not seen.** A tile with no bit in the explored set is absent,
#     whatever the zone says -- the default annex floor included, before anyone has looked at it.
#   * **The colony's own marking, not a sighting.** A zone tile the player has seen draws whether it
#     is in sight now or only remembered, like the remembered map itself; out of sight it is pulled
#     through `Palette.remembered`, the same filter the ground under it wears.
#   * **Under its roof.** An indoor tile the roof covers right now (RoofLook's rule, the list
#     `_draw_world` already built) shows the roof, not the wash, with the brush in hand or not: from
#     the street you see the building, and a wash laid over a roof reads as paint on the shingles.
#     Indoor ground is marked from indoors, where the roof is off. The drag's preview obeys the same
#     rule, so a rectangle dragged over a roofed building previews only the ground outside it.
#   * **One rim around the zone, no seams inside it.** A tile carries a rim only on the sides whose
#     neighbour is not in the zone, plus the notch at a concave corner, so two marked tiles side by
#     side read as one patch.
#   * **Quieter at rest.** Outside the brush the wash and the rim are drawn at a lower alpha, so the
#     player always knows where the stockpile is without the street turning blue.
#
# The look is the Salvage Locker's: a cool steel wash, and the rim a strip of masking tape with its
# shadow under it (`ui/locker.gd`'s TAPE and RIM_OUTER), one art pixel each. The tape reads on dark
# ground and the shadow on light ground, so the pair holds its contrast on every surface the district
# has (the STOCKPILE lane's CONTRAST half measures it).

const Palette = preload("res://presentation/palette.gd")

# Side bits, for `cells`' `edges` and `corners`.
const N: int = 1
const E: int = 2
const S: int = 4
const W: int = 8
# Concave corners: the diagonal is outside the zone while both sides beside it are in.
const NE: int = 1
const SE: int = 2
const SW: int = 4
const NW: int = 8
# The zone's tape, laid in strips: this many art pixels on, then this many off. Six and two make four
# strips to a 32-pixel tile side, so the pattern meets itself at every tile corner.
const DASH: int = 6
const GAP: int = 2


## The zone's shape, once per change of the zone: tile -> Vector2i(edges, corners). A caller that
## keeps it between frames (main.gd keys it on `SimStockpile.signature`) passes it to `cells`.
static func geometry(zone: Array[Vector2i]) -> Dictionary:
	var in_zone: Dictionary = {}
	for t in zone:
		in_zone[t] = true
	var out: Dictionary = {}
	for t in zone:
		out[t] = Vector2i(edges_of(in_zone, t), corners_of(in_zone, t))
	return out


## The zone as painted: one entry per tile that draws, {tile, live, wash, tape, shadow, edges,
## corners}. `zone` is the sim's tile list, `seen` the current shadowcast (anything with
## `has_tile(tx, ty)`, or null), `explored` the remembered set (the same, or null: nothing draws),
## `roof` the tiles under a roof this frame, `view` the tiles on screen, `geom` the zone's
## `geometry` when the caller kept it (built here when it did not).
static func cells(zone: Array[Vector2i], seen: Variant, explored: Variant, roof: Array, marking: bool, view: Rect2i, geom: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if explored == null:
		return out
	if geom.is_empty():
		geom = geometry(zone)
	var roofed: Dictionary = roofed_set(roof)
	var wash: Color = Palette.STOCKPILE_WASH
	wash.a = Palette.STOCKPILE_WASH_MARKING if marking else Palette.STOCKPILE_WASH_REST
	var tape: Color = Palette.STOCKPILE_TAPE
	tape.a = Palette.STOCKPILE_RIM_MARKING if marking else Palette.STOCKPILE_RIM_REST
	var shadow: Color = Palette.STOCKPILE_SHADOW
	shadow.a = tape.a * Palette.STOCKPILE_SHADOW_SHARE
	var wash_dim: Color = Palette.remembered(wash)
	var tape_dim: Color = Palette.remembered(tape)
	var ex: Object = explored as Object
	var sn: Object = seen as Object
	for t in zone:
		if not view.has_point(t):
			continue
		if not bool(ex.call("has_tile", t.x, t.y)):
			continue
		if roofed.has(t):
			continue
		var live: bool = sn != null and bool(sn.call("has_tile", t.x, t.y))
		var shape: Vector2i = geom.get(t, Vector2i.ZERO) as Vector2i
		out.append({
			"tile": t, "live": live,
			"wash": wash if live else wash_dim,
			"tape": tape if live else tape_dim,
			"shadow": shadow,
			"edges": shape.x, "corners": shape.y, "dashed": true,
		})
	return out


## What each zone tile is to the player right now, one byte a tile in the zone's order: 1 explored,
## 2 in sight, 4 under a roof. Everything `cells` reads per tile besides the zone itself, so a caller
## that kept a batch can tell, cheaply, whether `cells` would answer differently.
static func states(zone: Array[Vector2i], seen: Variant, explored: Variant, roof: Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(zone.size())
	if explored == null:
		return out
	var roofed: Dictionary = roofed_set(roof)
	var ex: Object = explored as Object
	var sn: Object = seen as Object
	for i in zone.size():
		var t: Vector2i = zone[i]
		var b: int = 0
		if bool(ex.call("has_tile", t.x, t.y)):
			b |= 1
		if sn != null and bool(sn.call("has_tile", t.x, t.y)):
			b |= 2
		if roofed.has(t):
			b |= 4
		out[i] = b
	return out


## The drag's preview: the tiles `SimStockpile.preview` says the release would change, each with the
## add or clear colour and its own rim around the preview patch. Drawn only where the player has
## explored and no roof covers -- an `off` rectangle can take back default tiles nobody has looked
## at yet, and those still show nothing.
static func preview_cells(tiles: Array, on: bool, explored: Variant, roof: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if explored == null:
		return out
	var roofed: Dictionary = roofed_set(roof)
	var in_set: Dictionary = {}
	for t in tiles:
		in_set[t as Vector2i] = true
	var base: Color = Palette.STOCKPILE_ADD if on else Palette.STOCKPILE_CLEAR
	var fill: Color = base
	fill.a = Palette.STOCKPILE_PREVIEW_FILL
	var tape: Color = Palette.STOCKPILE_ADD if on else Palette.STOCKPILE_CLEAR_RIM
	var shadow: Color = Palette.STOCKPILE_SHADOW
	shadow.a = Palette.STOCKPILE_SHADOW_SHARE
	for v in tiles:
		var t: Vector2i = v as Vector2i
		if not bool((explored as Object).call("has_tile", t.x, t.y)) or roofed.has(t):
			continue
		out.append({"tile": t, "live": true, "wash": fill, "tape": tape, "shadow": shadow, "edges": edges_of(in_set, t), "corners": corners_of(in_set, t), "dashed": false})
	return out


static func roofed_set(roof: Array) -> Dictionary:
	var out: Dictionary = {}
	for r in roof:
		out[r as Vector2i] = true
	return out


static func edges_of(in_zone: Dictionary, t: Vector2i) -> int:
	var bits: int = 0
	if not in_zone.has(t + Vector2i(0, -1)): bits |= N
	if not in_zone.has(t + Vector2i(1, 0)): bits |= E
	if not in_zone.has(t + Vector2i(0, 1)): bits |= S
	if not in_zone.has(t + Vector2i(-1, 0)): bits |= W
	return bits


static func corners_of(in_zone: Dictionary, t: Vector2i) -> int:
	var bits: int = 0
	var n: bool = in_zone.has(t + Vector2i(0, -1))
	var e: bool = in_zone.has(t + Vector2i(1, 0))
	var s: bool = in_zone.has(t + Vector2i(0, 1))
	var w: bool = in_zone.has(t + Vector2i(-1, 0))
	if n and e and not in_zone.has(t + Vector2i(1, -1)): bits |= NE
	if s and e and not in_zone.has(t + Vector2i(1, 1)): bits |= SE
	if s and w and not in_zone.has(t + Vector2i(-1, 1)): bits |= SW
	if n and w and not in_zone.has(t + Vector2i(-1, -1)): bits |= NW
	return bits


## One art pixel at this zoom, in whole screen pixels: the district draws 32 art pixels to a tile.
static func art_px(zoom: float) -> float:
	return maxf(1.0, roundf(zoom / 32.0))


## What a list of cells paints, batched for the canvas: {"fills": [[Rect2, Color], ...], "lines":
## {Color: PackedVector2Array}}. A fill is a run of washed tiles along a row that share a colour --
## one rect, not one per tile; a line is a segment one art pixel thick (`draw_multiline` with width
## `px`), every segment of one colour in one array: the tape on each outer side and its shadow one art
## pixel inside it, then the concave corners' notches. The zone's tape is laid in strips (`DASH` art
## pixels on, `GAP` off, from each tile's own corner, so the run continues tile to tile and every tile
## corner is covered); the drag's preview is one unbroken strip, so a patch the release has not made
## yet never reads as one already laid. `origin` is tile (0, 0)'s top-left on screen, `size` a tile's
## side. Pure, so the STOCKPILE lane can ask what a list paints without a canvas.
static func batch(list: Array[Dictionary], origin: Vector2, size: float, px: float) -> Dictionary:
	var fills: Array = []
	var lines: Dictionary = {}
	var run_tile: Vector2i = Vector2i.ZERO
	var run_len: int = 0
	var run_col: Color = Color(0, 0, 0, 0)
	for cell in list:
		var t: Vector2i = cell["tile"] as Vector2i
		var at: Vector2 = origin + Vector2(t) * size
		var wash: Color = cell["wash"] as Color
		if run_len > 0 and t.y == run_tile.y and t.x == run_tile.x + run_len and wash == run_col:
			run_len += 1
		else:
			if run_len > 0:
				fills.append([Rect2(origin + Vector2(run_tile) * size, Vector2(size * run_len, size)), run_col])
			run_tile = t
			run_len = 1
			run_col = wash
		var edges: int = int(cell["edges"])
		var corners: int = int(cell["corners"])
		if edges == 0 and corners == 0:
			continue
		var tape: Color = cell["tape"] as Color
		var shadow: Color = cell["shadow"] as Color
		var dashed: bool = bool(cell.get("dashed", false))
		var h: float = px * 0.5
		if edges & N:
			_strip(lines, at + Vector2(0.0, h), Vector2(1.0, 0.0), size, px, dashed, tape, shadow, Vector2(0.0, px))
		if edges & S:
			_strip(lines, at + Vector2(0.0, size - h), Vector2(1.0, 0.0), size, px, dashed, tape, shadow, Vector2(0.0, -px))
		if edges & W:
			_strip(lines, at + Vector2(h, 0.0), Vector2(0.0, 1.0), size, px, dashed, tape, shadow, Vector2(px, 0.0))
		if edges & E:
			_strip(lines, at + Vector2(size - h, 0.0), Vector2(0.0, 1.0), size, px, dashed, tape, shadow, Vector2(-px, 0.0))
		if corners & NE:
			_segment(lines, tape, at + Vector2(size - px, h), at + Vector2(size, h))
		if corners & SE:
			_segment(lines, tape, at + Vector2(size - px, size - h), at + Vector2(size, size - h))
		if corners & SW:
			_segment(lines, tape, at + Vector2(0.0, size - h), at + Vector2(px, size - h))
		if corners & NW:
			_segment(lines, tape, at + Vector2(0.0, h), at + Vector2(px, h))
	if run_len > 0:
		fills.append([Rect2(origin + Vector2(run_tile) * size, Vector2(size * run_len, size)), run_col])
	return {"fills": fills, "lines": lines}


# A strip of tape along `dir` from `from` (the centre of its one-pixel band), `size` long, and its
# shadow the same shape offset by `inward`: whole when `dashed` is false, else DASH on and GAP off.
# Shadows go in first, so a tape segment of the same frame lands over a neighbour's shadow.
static func _strip(lines: Dictionary, from: Vector2, dir: Vector2, size: float, px: float, dashed: bool, tape: Color, shadow: Color, inward: Vector2) -> void:
	if not dashed:
		_segment(lines, shadow, from + inward, from + inward + dir * size)
		_segment(lines, tape, from, from + dir * size)
		return
	var step: float = float(DASH + GAP) * px
	var at: float = 0.0
	while at < size:
		var length: float = minf(float(DASH) * px, size - at)
		_segment(lines, shadow, from + inward + dir * at, from + inward + dir * (at + length))
		_segment(lines, tape, from + dir * at, from + dir * (at + length))
		at += step


static func _segment(lines: Dictionary, col: Color, a: Vector2, b: Vector2) -> void:
	if not lines.has(col):
		lines[col] = PackedVector2Array()
	var arr: PackedVector2Array = lines[col]
	arr.append(a)
	arr.append(b)
	lines[col] = arr


## The brush's own tile: a tape outline one art pixel wide, so the player sees where a click lands.
static func cursor(at: Vector2, size: float, px: float) -> Array:
	var col: Color = Palette.STOCKPILE_CURSOR
	return [
		[Rect2(at, Vector2(size, px)), col],
		[Rect2(at + Vector2(0.0, size - px), Vector2(size, px)), col],
		[Rect2(at, Vector2(px, size)), col],
		[Rect2(at + Vector2(size - px, 0.0), Vector2(px, size)), col],
	]


## WCAG's contrast ratio between two opaque colours.
static func contrast(a: Color, b: Color) -> float:
	var la: float = _luminance(a)
	var lb: float = _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## `top` laid over `ground` at its own alpha, as the canvas blends it.
static func over(top: Color, ground: Color) -> Color:
	return Color(lerpf(ground.r, top.r, top.a), lerpf(ground.g, top.g, top.a), lerpf(ground.b, top.b, top.a), 1.0)


static func _luminance(c: Color) -> float:
	var ch: Array[float] = []
	for v in [c.r, c.g, c.b]:
		var f: float = float(v)
		ch.append(f / 12.92 if f <= 0.03928 else pow((f + 0.055) / 1.055, 2.4))
	return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2]
