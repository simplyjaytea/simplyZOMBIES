extends RefCounted
# The Salvage Locker: the inventory's own skin, since the owner asked on 2026-10-19 for the
# Tarkov-style grid to stay and for its look to be redone from scratch (docs/23, "The inventory,
# redone"). Gunmetal panels with a brushed grain, a riveted corner and a bevelled rim; recessed
# cells; items sat on plates tinted by what kind of thing they are; container names on a strip of
# masking tape. Everything here is drawn at the world's density -- one art pixel is `PX` screen
# pixels, the same 2x the district and the item pictures draw at -- so the sheet reads as a thing in
# the same world rather than a screen pasted over it. Every edge, rim and rivet below is a whole
# number of art pixels.
#
# Statics only, like `chrome.gd`, whose job this is for the inventory's surfaces: the sheet, its
# bag grids, the inspect pane, the list, the quick strip and the transfer window. The rest of the
# UI still wears the UI Field Kit through `chrome.gd`, and text still comes from `Chrome.font()`
# (docs/30, "The UI Field Kit, live": one typeface).
#
# The two textures here (the brushed steel and the cell) are generated once from code and cached
# rather than shipped as PNGs: they are a few lines of arithmetic, they are identical for every
# world, and nothing under godot/sim/ reads them -- the same reason `kit.gd` keeps its caches static.

const Kit = preload("res://ui/kit.gd")
const Chrome = preload("res://ui/chrome.gd")

# Screen pixels per art pixel: the kit's own scale, which is the world's.
const PX: float = float(Kit.SCALE)

# --- the palette ------------------------------------------------------------------------------
const STEEL: Color = Color("#1d2024")
const STEEL_GRAIN: Color = Color("#22262b")
const STEEL_GRAIN_DARK: Color = Color("#1a1d20")
const RIM_OUTER: Color = Color("#08090a")
const RIM_TOP: Color = Color("#3c4248")
const RIM_SIDE: Color = Color("#30353b")
const RIM_SHADOW: Color = Color("#111316")
const RIVET: Color = Color("#7a8087")
const RIVET_SHADE: Color = Color("#3d4146")
const GROOVE_DARK: Color = Color("#0d0e10")
const GROOVE_LIGHT: Color = Color("#2c3136")
const WELL: Color = Color("#121417")
const WELL_TOP: Color = Color("#08090a")
const WELL_LIP: Color = Color("#2b3036")
const TAPE: Color = Color("#cfc6a8")
const TAPE_SHADE: Color = Color("#ada385")
const TAPE_INK: Color = Color("#2a2418")
const TEXT: Color = Color("#e4dfcf")
const TEXT_DIM: Color = Color("#9a9a8e")
const TEXT_FAINT: Color = Color("#5f615e")
const SHADOW: Color = Color(0.0, 0.0, 0.0, 0.55)
const ACCENT: Color = Color("#e2a33a")
const DANGER: Color = Color("#c4532c")
const GOOD: Color = Color("#8fae5e")
const WASH: Color = Color(0.027, 0.031, 0.039, 0.9)

# What a plate is tinted by: the item's content class, the one fact about it every item has and the
# player already knows by looking. A colour per *kind*, never per quality -- quality is a word in
# the inspect pane and nowhere else (docs/01 clause 4).
const TINTS: Dictionary = {
	"consumable": Color("#2f4229"),
	"material": Color("#433a2c"),
	"armor": Color("#2c3b45"),
	"tool": Color("#4a3520"),
	"attachment": Color("#363a44"),
	"weapon.melee": Color("#4a2b25"),
	"weapon.ranged": Color("#3a3f47"),
	"container": Color("#3e4130"),
}
const TINT_DEFAULT: Color = Color("#383b3e")

# Sizes, in screen pixels: a whole number of art pixels each.
const TAPE_H: float = 12.0 * PX
const HEAD_H: float = 16.0 * PX
const RIVET_INSET: float = 3.0 * PX
const TITLE_SIZE: int = 50
const LABEL_SIZE: int = 25
const SMALL_SIZE: int = 20

static var _steel: Texture2D = null
static var _cell: Texture2D = null


static func tint_of(item_class: String) -> Color:
	return TINTS.get(item_class, TINT_DEFAULT) as Color


static func _a(c: Color, alpha: float) -> Color:
	var out: Color = c
	out.a = c.a * alpha
	return out


static func _shade(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0.0, 1.0), clampf(c.g * f, 0.0, 1.0), clampf(c.b * f, 0.0, 1.0), c.a)


static func _snap(r: Rect2) -> Rect2:
	return Rect2((r.position / PX).round() * PX, (r.size / PX).round() * PX)


# --- generated textures -------------------------------------------------------------------------

# A tile of brushed gunmetal, 64 art pixels square, drawn at PX: horizontal streaks a shade either
# side of the base, from a fixed seed so every run and every panel wears the same grain.
static func steel_texture() -> Texture2D:
	if _steel != null:
		return _steel
	var n: int = 64
	var img := Image.create(n * int(PX), n * int(PX), false, Image.FORMAT_RGBA8)
	img.fill(STEEL)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7041
	for y in n:
		var runs: int = rng.randi_range(0, 2)
		for i in runs:
			var x0: int = rng.randi_range(0, n - 1)
			var length: int = rng.randi_range(5, 26)
			var col: Color = STEEL_GRAIN if rng.randf() < 0.6 else STEEL_GRAIN_DARK
			for x in length:
				var ax: int = (x0 + x) % n
				img.fill_rect(Rect2i(ax * int(PX), y * int(PX), int(PX), int(PX)), col)
	_steel = ImageTexture.create_from_image(img)
	return _steel


# One recessed cell, `cell` screen pixels square: a dark well, its top and left edges in shadow,
# its bottom and right catching the light, and a centre pip. Tiled across a grid in one draw.
static func cell_texture(cell: int) -> Texture2D:
	if _cell != null and int(_cell.get_width()) == cell:
		return _cell
	var p: int = int(PX)
	var img := Image.create(cell, cell, false, Image.FORMAT_RGBA8)
	img.fill(WELL)
	img.fill_rect(Rect2i(0, 0, cell, p), WELL_TOP)
	img.fill_rect(Rect2i(0, 0, p, cell), WELL_TOP)
	img.fill_rect(Rect2i(p, cell - p, cell - p, p), WELL_LIP)
	img.fill_rect(Rect2i(cell - p, p, p, cell - p), WELL_LIP)
	var mid: int = (cell / 2 / p) * p
	img.fill_rect(Rect2i(mid, mid, p, p), Color("#1a1d21"))
	_cell = ImageTexture.create_from_image(img)
	return _cell


# --- surfaces -------------------------------------------------------------------------------------

# A gunmetal panel: brushed fill, a one-pixel dark outline, a lit top and left edge inside it, a
# shadowed bottom and right, and a rivet at each corner. `alpha` is the player's opacity setting;
# the rim is drawn a little more opaque than the fill so a faded panel still shows its edge.
static func panel(ci: CanvasItem, rect: Rect2, alpha: float, rivets: bool = true) -> void:
	var r: Rect2 = _snap(rect)
	if r.size.x < PX * 6.0 or r.size.y < PX * 6.0:
		ci.draw_rect(r, _a(STEEL, alpha))
		return
	ci.draw_texture_rect(steel_texture(), r, true, Color(1.0, 1.0, 1.0, alpha))
	var edge: float = minf(1.0, alpha + 0.15)
	var p: float = PX
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, p)), _a(RIM_OUTER, edge))
	ci.draw_rect(Rect2(Vector2(r.position.x, r.end.y - p), Vector2(r.size.x, p)), _a(RIM_OUTER, edge))
	ci.draw_rect(Rect2(r.position, Vector2(p, r.size.y)), _a(RIM_OUTER, edge))
	ci.draw_rect(Rect2(Vector2(r.end.x - p, r.position.y), Vector2(p, r.size.y)), _a(RIM_OUTER, edge))
	ci.draw_rect(Rect2(r.position + Vector2(p, p), Vector2(r.size.x - p * 2.0, p)), _a(RIM_TOP, edge))
	ci.draw_rect(Rect2(r.position + Vector2(p, p * 2.0), Vector2(p, r.size.y - p * 3.0)), _a(RIM_SIDE, edge))
	ci.draw_rect(Rect2(Vector2(r.position.x + p, r.end.y - p * 2.0), Vector2(r.size.x - p * 2.0, p)), _a(RIM_SHADOW, edge))
	ci.draw_rect(Rect2(Vector2(r.end.x - p * 2.0, r.position.y + p * 2.0), Vector2(p, r.size.y - p * 4.0)), _a(RIM_SHADOW, edge))
	if rivets and r.size.x > RIVET_INSET * 4.0 and r.size.y > RIVET_INSET * 4.0:
		for c in [r.position + Vector2(RIVET_INSET, RIVET_INSET), Vector2(r.end.x - RIVET_INSET - p * 2.0, r.position.y + RIVET_INSET),
				Vector2(r.position.x + RIVET_INSET, r.end.y - RIVET_INSET - p * 2.0), r.end - Vector2(RIVET_INSET + p * 2.0, RIVET_INSET + p * 2.0)]:
			rivet(ci, c as Vector2, edge)


# One rivet, its top-left at `at`: a two-pixel head, its lower-right pixel in shade, and a pixel of
# shadow off the corner.
static func rivet(ci: CanvasItem, at: Vector2, alpha: float) -> void:
	var p: float = PX
	ci.draw_rect(Rect2(at, Vector2(p * 2.0, p * 2.0)), _a(RIVET, alpha))
	ci.draw_rect(Rect2(at + Vector2(p, p), Vector2(p, p)), _a(RIVET_SHADE, alpha))
	ci.draw_rect(Rect2(at + Vector2(p * 2.0, p * 2.0), Vector2(p, p)), _a(RIM_OUTER, alpha))


# A strip of masking tape with `label` written on it in marker, its top-left at `at`. The tape is
# a pixel crooked -- it rises one art pixel from end to end -- and its ends are torn. Returns the
# rect it covers, so a caller can put something after it.
static func tape(ci: CanvasItem, at: Vector2, label: String, alpha: float) -> Rect2:
	var font: Font = Chrome.font()
	var text: String = label.to_upper()
	var tw: float = ceilf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x)
	var p: float = PX
	var w: float = ceilf((tw + p * 10.0) / p) * p
	var o: Vector2 = (at / p).round() * p
	var half: float = floorf(w / p / 2.0) * p
	# Two halves, the right one a pixel higher: the crook.
	ci.draw_rect(Rect2(o + Vector2(0.0, p), Vector2(half, TAPE_H - p)), _a(TAPE, alpha))
	ci.draw_rect(Rect2(o + Vector2(half, 0.0), Vector2(w - half, TAPE_H - p)), _a(TAPE, alpha))
	# Shade along the bottom edge and the torn ends: every other pixel bitten out.
	ci.draw_rect(Rect2(o + Vector2(0.0, TAPE_H - p), Vector2(half, p)), _a(TAPE_SHADE, alpha))
	ci.draw_rect(Rect2(o + Vector2(half, TAPE_H - p * 2.0), Vector2(w - half, p)), _a(TAPE_SHADE, alpha))
	var y: float = p
	while y < TAPE_H - p:
		ci.draw_rect(Rect2(o + Vector2(0.0, y + p), Vector2(p, p)), _a(TAPE_SHADE, alpha))
		ci.draw_rect(Rect2(o + Vector2(w - p, y), Vector2(p, p)), _a(TAPE_SHADE, alpha))
		y += p * 2.0
	var base: float = floorf(o.y + (TAPE_H - Chrome.line_height(LABEL_SIZE)) / 2.0 + Chrome.ascent(LABEL_SIZE))
	ci.draw_string(font, Vector2(o.x + p * 5.0, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, _a(TAPE_INK, alpha))
	return Rect2(o, Vector2(w, TAPE_H))


# A container's header inside a panel drawn at `rect`: its name on tape, an optional note at the
# far end in the dim ink (who it belongs to: "on you", "belt", "here"), and an engraved groove
# under both. The returned y is where the panel's contents begin.
static func header(ci: CanvasItem, rect: Rect2, label: String, alpha: float, note: String = "", note_inset: float = 0.0) -> float:
	var r: Rect2 = _snap(rect)
	var p: float = PX
	var strip: Rect2 = tape(ci, r.position + Vector2(p * 4.0, p * 2.0), label, alpha)
	if not note.is_empty():
		var font: Font = Chrome.font()
		var nw: float = font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE).x
		var base: float = floorf(r.position.y + p * 2.0 + (TAPE_H - Chrome.line_height(SMALL_SIZE)) / 2.0 + Chrome.ascent(SMALL_SIZE))
		var nx: float = r.end.x - nw - p * 6.0 - note_inset
		# A narrow panel with a long name keeps the name: the note is the lesser of the two, and a
		# note written over the tape's end reads as a misprint.
		if nx >= strip.end.x + p * 3.0:
			ci.draw_string(font, Vector2(nx, base), note, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE, _a(TEXT_DIM, alpha))
	groove(ci, Vector2(r.position.x + p * 2.0, r.position.y + HEAD_H - p * 2.0), r.size.x - p * 4.0, alpha)
	return r.position.y + HEAD_H


# An engraved line: a dark pixel row over a lit one.
static func groove(ci: CanvasItem, at: Vector2, wide: float, alpha: float) -> void:
	ci.draw_rect(Rect2(at, Vector2(wide, PX)), _a(GROOVE_DARK, alpha))
	ci.draw_rect(Rect2(at + Vector2(0.0, PX), Vector2(wide, PX)), _a(GROOVE_LIGHT, alpha))


# A grid of `w` by `h` recessed cells, `cell` screen pixels each, from `origin`. One tiled draw.
static func cells(ci: CanvasItem, origin: Vector2, w: int, h: int, cell: int, alpha: float) -> void:
	if w <= 0 or h <= 0:
		return
	ci.draw_texture_rect(cell_texture(cell), Rect2(origin, Vector2(float(w * cell), float(h * cell))), true, Color(1.0, 1.0, 1.0, alpha))


# A recessed well: one big cell, for an equipment slot, the inspect picture or a strip slot.
static func well(ci: CanvasItem, rect: Rect2, alpha: float) -> void:
	var r: Rect2 = _snap(rect)
	var p: float = PX
	ci.draw_rect(r, _a(WELL, alpha))
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, p)), _a(WELL_TOP, alpha))
	ci.draw_rect(Rect2(r.position, Vector2(p, r.size.y)), _a(WELL_TOP, alpha))
	ci.draw_rect(Rect2(Vector2(r.position.x + p, r.end.y - p), Vector2(r.size.x - p, p)), _a(WELL_LIP, alpha))
	ci.draw_rect(Rect2(Vector2(r.end.x - p, r.position.y + p), Vector2(p, r.size.y - p)), _a(WELL_LIP, alpha))


# An item's plate over the cells it covers, tinted by its class: the tint's own fill, a lighter
# outline, a lit top row, a shaded bottom row and a bright dog-ear in the top-right corner that
# carries the kind at a glance even under a picture that fills the plate.
static func plate(ci: CanvasItem, rect: Rect2, item_class: String, alpha: float) -> void:
	var r: Rect2 = _snap(rect)
	var p: float = PX
	var t: Color = tint_of(item_class)
	ci.draw_rect(r, _a(_shade(t, 0.85), alpha))
	ci.draw_rect(Rect2(r.position + Vector2(p, p), Vector2(r.size.x - p * 2.0, p)), _a(_shade(t, 1.15), alpha))
	ci.draw_rect(Rect2(Vector2(r.position.x + p, r.end.y - p * 2.0), Vector2(r.size.x - p * 2.0, p)), _a(_shade(t, 0.6), alpha))
	rim(ci, r, _a(_shade(t, 1.45), alpha))
	var ear: float = p * 5.0
	if r.size.x > ear * 2.0 and r.size.y > ear * 2.0:
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(r.end.x - ear - p, r.position.y + p), Vector2(r.end.x - p, r.position.y + p), Vector2(r.end.x - p, r.position.y + ear + p),
		]), _a(_shade(t, 1.9), alpha))


# Corner brackets around `rect` in `col`, four art pixels long: the selection mark, and the shape
# a legal drop is outlined in.
static func brackets(ci: CanvasItem, rect: Rect2, col: Color) -> void:
	var r: Rect2 = _snap(rect).grow(PX)
	var p: float = PX
	var arm: float = p * 4.0
	for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var cx: float = r.position.x if corner.x == 0 else r.end.x - p
		var cy: float = r.position.y if corner.y == 0 else r.end.y - p
		var hx: float = cx if corner.x == 0 else r.end.x - arm
		var vy: float = cy if corner.y == 0 else r.end.y - arm
		ci.draw_rect(Rect2(Vector2(hx, cy), Vector2(arm, p)), col)
		ci.draw_rect(Rect2(Vector2(cx, vy), Vector2(p, arm)), col)


# A selected plate: an amber hairline round it and the brackets outside that.
static func selected(ci: CanvasItem, rect: Rect2, alpha: float) -> void:
	var r: Rect2 = _snap(rect)
	rim(ci, r, _a(ACCENT, minf(1.0, alpha + 0.1)))
	brackets(ci, r, _a(ACCENT, minf(1.0, alpha + 0.1)))


# Where a held item would land and the sim would take it: the cells it would cover, washed and
# bracketed in a steady green.
static func accept(ci: CanvasItem, rect: Rect2) -> void:
	var r: Rect2 = _snap(rect)
	ci.draw_rect(r, _a(GOOD, 0.18))
	rim(ci, r, _a(GOOD, 0.85))


# Where a held item would land and the sim would refuse it: hazard stripes in rust over the cells
# it would cover, and a rust rim. Stripes, not only a colour, so the refusal reads without one.
static func refuse(ci: CanvasItem, rect: Rect2) -> void:
	var r: Rect2 = _snap(rect)
	if not r.has_area():
		return
	ci.draw_rect(r, _a(DANGER, 0.22))
	var p: float = PX
	var step: float = p * 6.0
	var x: float = r.position.x - r.size.y
	while x < r.end.x:
		var a := Vector2(maxf(x, r.position.x), r.position.y + maxf(0.0, r.position.x - x))
		var b := Vector2(minf(x + r.size.y, r.end.x), r.position.y + minf(r.size.y, r.end.x - x))
		if b.x > a.x:
			ci.draw_line(a, b, _a(DANGER, 0.7), p * 2.0)
		x += step
	rim(ci, r, _a(DANGER, 0.95))


# A stamped button: a recessed well when idle, an amber-rimmed plate when it is the obvious thing to
# do. `label` is centred on it.
static func button(ci: CanvasItem, rect: Rect2, label: String, primary: bool, alpha: float) -> void:
	var r: Rect2 = _snap(rect)
	if primary:
		ci.draw_rect(r, _a(_shade(ACCENT, 0.32), alpha))
		ci.draw_rect(Rect2(r.position + Vector2(PX, PX), Vector2(r.size.x - PX * 2.0, PX)), _a(_shade(ACCENT, 0.55), alpha))
		rim(ci, r, _a(ACCENT, minf(1.0, alpha + 0.1)))
	else:
		well(ci, r, alpha)
		rim(ci, r, _a(RIM_SIDE, alpha))
	text_centred(ci, r, label, LABEL_SIZE, TEXT if primary else TEXT_DIM, alpha)


# A one-art-pixel rim drawn inside `r`. An outlined draw_rect centres its stroke on the edge, which
# puts half of a two-pixel rim on an odd screen pixel; this keeps every edge on the grid.
static func rim(ci: CanvasItem, r: Rect2, col: Color) -> void:
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, PX)), col)
	ci.draw_rect(Rect2(Vector2(r.position.x, r.end.y - PX), Vector2(r.size.x, PX)), col)
	ci.draw_rect(Rect2(r.position + Vector2(0.0, PX), Vector2(PX, r.size.y - PX * 2.0)), col)
	ci.draw_rect(Rect2(Vector2(r.end.x - PX, r.position.y + PX), Vector2(PX, r.size.y - PX * 2.0)), col)


# A filter chip: a small stamped tag, lit amber when it is the filter in force.
static func chip(ci: CanvasItem, rect: Rect2, label: String, on: bool, alpha: float) -> void:
	var r: Rect2 = _snap(rect)
	if on:
		ci.draw_rect(r, _a(_shade(ACCENT, 0.35), alpha))
		rim(ci, r, _a(ACCENT, minf(1.0, alpha + 0.1)))
	else:
		ci.draw_rect(r, _a(Color(0.0, 0.0, 0.0, 0.25), alpha))
		rim(ci, r, _a(TEXT_FAINT, alpha))
	text_centred(ci, r, label, SMALL_SIZE, TEXT if on else TEXT_DIM, alpha)


# The width a chip or button needs for `label` at `size`: the words and five art pixels a side.
static func label_width(label: String, size: int) -> float:
	var w: float = Chrome.font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + PX * 10.0
	return ceilf(w / PX) * PX


# Words centred in `rect` on the face's own metrics.
static func text_centred(ci: CanvasItem, rect: Rect2, label: String, size: int, col: Color, alpha: float) -> void:
	var font: Font = Chrome.font()
	var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var base: float = floorf(rect.position.y + (rect.size.y - Chrome.line_height(size)) / 2.0 + Chrome.ascent(size))
	ci.draw_string(font, Vector2(roundf(rect.position.x + (rect.size.x - w) / 2.0), base), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, _a(col, alpha))


# Words with a one-pixel drop shadow, for a name or a tally sat on top of a picture.
static func text_shadowed(ci: CanvasItem, at: Vector2, label: String, size: int, col: Color, alpha: float) -> void:
	var font: Font = Chrome.font()
	ci.draw_string(font, at + Vector2(PX / 2.0, PX / 2.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, _a(SHADOW, alpha))
	ci.draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, _a(col, alpha))
