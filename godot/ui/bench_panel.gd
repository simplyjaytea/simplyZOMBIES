extends Control
# The assembly screen: a weapon opened up on the Salvage Locker's steel (UI overhaul, slice 3).
#
# The weapon's picture sits in the middle at a whole integer scale, and each of its real slots is a
# plate placed round it by what the slot is -- the sight above, the stock to the left, the muzzle
# device to the right, the magazine below, the underbarrel below and right, and the rest (barrel,
# action, the parts a bow or an axe or a vest carries) in a row beneath. Pick a plate and the column
# on the right lists what you carry that fits it, each with what the swap would change in words.
# It replaced a two-column list whose fixed 960x620 rect hung its bottom forty pixels off a
# 1280x720 window (the 2026-10-03 audit's "bench clipping at 720p").
#
# **This panel computes nothing.** Every word on it comes out of `SimGunsmith.bench_view`, exactly
# as `inspect_pane.gd` draws `inspect_view` and for the same reason: the read model has no
# magnitude in it, so there is no number here to print even by accident. A change reads as the word
# "better", "worse" or "different", and this file turns that into an arrow -- with the word beside
# it, because a glyph the chrome font is missing would otherwise be a silent blank.
#
# The only integers that cross the seam are handles -- `host`, `part`, `item` -- which go straight
# back out on a command and are never drawn.
#
# **Where it sits.** main.gd stretches this Control over the whole window and the frame is
# `frame_for(size)`: its natural size, centred, and never closer than `MARGIN` to an edge. The rest
# of the window is washed, and a click there is spent on the wash rather than swinging at the street
# behind it -- the bench is a screen, and its focus already refuses the street's keys.
#
# **Keys.** `input_map.gd` hands this panel the arrows (and WASD, which answer the same "move"
# action) and Enter while the bench has the focus, the way the shell takes its own keys; Escape
# stays the router's, which pushes `bench.close`. The arrows walk the plates by where they are
# drawn, Right off the last plate crosses to the candidates and Left comes back, and Enter does
# whatever the footer's lit button says: take the picked part off, fit the picked candidate, or
# make the picked part.
#
# **Making a part.** Under what you carry, an empty slot lists the parts that can be made for it
# (the view's `recipes`, docs/33 item 22's default): each says what it uses, or what it still
# needs, and only a row the sim says is `makeable` lights "make it". The arrows walk the candidates
# and the make rows as one column, and a click on a makeable row makes it at once, as a click on a
# candidate fits it.

const Chrome = preload("res://ui/chrome.gd")
const Kit = preload("res://ui/kit.gd")
const Locker = preload("res://ui/locker.gd")
const UiText = preload("res://ui/text.gd")
const ItemPicture = preload("res://ui/item_picture.gd")
const Appearance = preload("res://presentation/appearance.gd")
const SimGunsmith = preload("res://sim/modules/gunsmith.gd")

const PX: float = Locker.PX
# The frame's size when the window has room for it, and the gap it keeps from every edge when it
# does not: at 1280x720 it is the window less the margin, at 1920x1080 it is this, centred.
const NATURAL: Vector2 = Vector2(1376, 752)
const MARGIN: float = 16.0
const PAD: float = 24.0
const FOOT_H: float = 56.0
# One slot plate, and the gaps between plates. The row gap leaves room for a "needed" tape, which
# straddles a plate's top edge.
const PLATE: Vector2 = Vector2(240, 80)
const PLATE_GAP: Vector2 = Vector2(24, 28)
# The middle row is taller than a plate: it holds the weapon's picture.
const PICTURE_H: float = 112.0
# The largest whole scale the weapon's picture is drawn at; ItemPicture steps it down by whole
# numbers until it fits the well.
const PICTURE_SCALE: int = 8
# A part's picture square on a plate and on a candidate card.
const THUMB: float = 56.0
const OFFER_THUMB: float = 48.0
# Between the assembly and the candidates column.
const COL_GAP: float = 32.0
const NAME_SIZE: int = 25
const SMALL_SIZE: int = 20
const LINE: float = 24.0
const OFFER_GAP: float = 8.0
# A plate's first line of words starts this far down, clear of a "needed" tape's lower half.
const PLATE_TEXT_TOP: float = 16.0
# The amber corner's key: a small well wearing the corner, and its sentence beside it.
const LEGEND: float = 24.0
const LEGEND_SAYS: String = "something you carry fits"
# The make group's label, over the first row of parts the bench can make for the picked slot.
const MAKE_SAYS: String = "make one"
# Over a locked part's picture: the wash the window wears, lighter, so the part still shows.
const LOCKED_WASH: Color = Color(0.027, 0.031, 0.039, 0.6)
# Rust light enough to read at 4.5:1 on the cells' dark well, where the Locker's DANGER (made for
# rims and hazard stripes) measures about 4 to 1. Only words wear it.
const DANGER_INK: Color = Color("#e07a4f")

# Where a slot's plate sits round the picture, as (column, row) on a three-column grid whose row 1
# is the picture's. Anything not named here goes in the row beneath, in the order the weapon lists
# its slots. "optic" and "sight" share the top: a host carries one or the other.
const ANCHOR: Dictionary = {
	"optic": Vector2i(1, 0), "sight": Vector2i(1, 0),
	"furniture": Vector2i(0, 1), "muzzle": Vector2i(2, 1),
	"magazine": Vector2i(1, 2), "underbarrel": Vector2i(2, 2),
}

var _world: Variant = null
var _actor: int = -1
var _view: Dictionary = {}
# The picked slot, which side of the screen the keys are on, and the picked candidate.
var _pick: String = ""
var _side: String = "slots"
var _offer: int = 0
# The first candidate drawn, when the column holds more than fits.
var _offer_top: int = 0
# What the last draw put on screen, for the gate's digit scan: {text, kind: "name"|"word"}.
var _said: Array = []
# The slots drawn locked (by hand, a fitted part only a bench can take off) and the slots drawn with
# the amber corner, on the last draw: what a gate holds against the read model.
var _locked: Array[String] = []
var _eared: Array[String] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func set_world(world: Variant, actor: int) -> void:
	_world = world
	_actor = actor
	if world == null or actor < 0:
		_close_view()
		return
	var host: int = SimGunsmith.focus_of(world, actor)
	if host < 0:
		_close_view()
		return
	var was: int = int(_view.get("host", -1))
	_view = SimGunsmith.bench_view(world, actor, host)
	if _view.is_empty():
		_close_view()
		return
	if was != host:
		_pick = ""
		_side = "slots"
		_offer = 0
		_offer_top = 0
	if _row(_pick).is_empty():
		var slots: Array = _view.get("slots", []) as Array
		_pick = String((slots[0] as Dictionary).get("slot", "")) if not slots.is_empty() else ""
	var n: int = _entries().size()
	_offer = clampi(_offer, 0, maxi(0, n - 1))
	if n == 0:
		_side = "slots"
	visible = true
	queue_redraw()


func _close_view() -> void:
	_view = {}
	_pick = ""
	_side = "slots"
	visible = false


# --- what a gate or a review scene may ask --------------------------------------------------------

func picked_slot() -> String:
	return _pick


func side() -> String:
	return _side


func pick_slot(slot: String) -> bool:
	if _row(slot).is_empty():
		return false
	if slot != _pick:
		_offer = 0
		_offer_top = 0
	_pick = slot
	_side = "slots"
	queue_redraw()
	return true


func locked() -> Array[String]:
	return _locked


func eared() -> Array[String]:
	return _eared


func said() -> Array:
	return _said


# The frame inside a window of `view`: the natural size, shrunk to keep MARGIN from every edge, on
# the even grid, centred.
static func frame_for(view: Vector2) -> Rect2:
	var w: float = floorf(minf(NATURAL.x, view.x - MARGIN * 2.0) / PX) * PX
	var h: float = floorf(minf(NATURAL.y, view.y - MARGIN * 2.0) / PX) * PX
	var at: Vector2 = ((view - Vector2(w, h)) / 2.0 / PX).floor() * PX
	return Rect2(at, Vector2(w, h))


func frame_rect() -> Rect2:
	return frame_for(size)


# --- the read model, by slot ----------------------------------------------------------------------

func _row(slot: String) -> Dictionary:
	if slot.is_empty():
		return {}
	for row_v in _view.get("slots", []) as Array:
		if String((row_v as Dictionary).get("slot", "")) == slot:
			return row_v as Dictionary
	return {}


# The candidates for the picked slot, in the read model's order.
func _offers() -> Array:
	var out: Array = []
	for offer_v in _view.get("offers", []) as Array:
		if String((offer_v as Dictionary).get("slot", "")) == _pick:
			out.append(offer_v)
	return out


# The parts the bench can make for the picked slot, in the read model's order (makeable first).
func _recipes() -> Array:
	var out: Array = []
	for recipe_v in _view.get("recipes", []) as Array:
		if String((recipe_v as Dictionary).get("slot", "")) == _pick:
			out.append(recipe_v)
	return out


# The right column as the keys walk it: what you carry that fits, then what you could make.
func _entries() -> Array:
	return _offers() + _recipes()


static func _is_make(entry: Dictionary) -> bool:
	return entry.has("recipe")


# The entry the keys are on in the right column, or {} for none.
func _focused() -> Dictionary:
	var shown: Array = _entries()
	return shown[_offer] as Dictionary if _offer >= 0 and _offer < shown.size() else {}


# Whether anything you carry fits `slot`.
func _fits(slot: String) -> bool:
	for offer_v in _view.get("offers", []) as Array:
		if String((offer_v as Dictionary).get("slot", "")) == slot:
			return true
	return false


func _at_bench() -> bool:
	return bool(_view.get("at_bench", int(_view.get("bench", -1)) >= 0))


# --- the layout: one answer, drawn and clicked ----------------------------------------------------
#
# Everything the pointer can hit and everything the draw places, from the view and the frame alone,
# so the word you see and the plate you click cannot drift apart (the rule `item_menu.gd`'s
# `verb_rects` set).

func layout() -> Dictionary:
	var frame: Rect2 = frame_rect()
	var top: float = frame.position.y + Locker.HEAD_H + PAD
	var bottom: float = frame.end.y - FOOT_H - PAD
	var left: float = frame.position.x + PAD
	var grid_w: float = PLATE.x * 3.0 + PLATE_GAP.x * 2.0
	var col_x: float = left + grid_w + COL_GAP
	var col_w: float = frame.end.x - PAD - col_x

	# Which rows the assembly uses: the picture's always, the top and the bottom only when a slot
	# anchors there, and as many rows beneath as the rest of the slots fill three to a row.
	var anchored: Dictionary = {}
	var rest: Array = []
	for row_v in _view.get("slots", []) as Array:
		var slot: String = String((row_v as Dictionary).get("slot", ""))
		if ANCHOR.has(slot) and not anchored.values().has(ANCHOR[slot]):
			anchored[slot] = ANCHOR[slot]
		else:
			rest.append(slot)
	var has_top: bool = false
	var has_low: bool = false
	for cell_v in anchored.values():
		has_top = has_top or (cell_v as Vector2i).y == 0
		has_low = has_low or (cell_v as Vector2i).y == 2
	var rest_rows: int = ceili(float(rest.size()) / 3.0)
	var heights: Array[float] = []
	var row_of: Array[int] = []
	if has_top:
		heights.append(PLATE.y)
		row_of.append(0)
	heights.append(PICTURE_H)
	row_of.append(1)
	if has_low:
		heights.append(PLATE.y)
		row_of.append(2)
	for i in rest_rows:
		heights.append(PLATE.y)
		row_of.append(3 + i)
	var total: float = 0.0
	for h in heights:
		total += h
	total += PLATE_GAP.y * float(maxi(0, heights.size() - 1))
	var y0: float = floorf((top + maxf(0.0, (bottom - top - total) / 2.0)) / PX) * PX
	var row_y: Dictionary = {}
	var y: float = y0
	for i in heights.size():
		row_y[row_of[i]] = Vector2(y, heights[i])
		y += heights[i] + PLATE_GAP.y

	var picture_row: Vector2 = row_y[1] as Vector2
	var picture: Rect2 = Rect2(Vector2(left + PLATE.x + PLATE_GAP.x, picture_row.x), Vector2(PLATE.x, PICTURE_H))
	var plates: Dictionary = {}
	for slot_v in anchored.keys():
		var cell: Vector2i = anchored[slot_v] as Vector2i
		var ry: Vector2 = row_y[cell.y] as Vector2
		var py: float = ry.x + floorf((ry.y - PLATE.y) / 2.0 / PX) * PX
		plates[String(slot_v)] = Rect2(Vector2(left + float(cell.x) * (PLATE.x + PLATE_GAP.x), py), PLATE)
	for i in rest.size():
		var ry2: Vector2 = row_y[3 + i / 3] as Vector2
		var in_row: int = mini(3, rest.size() - (i / 3) * 3)
		# A short last row is centred under the picture rather than hung off the left.
		var lead: float = (grid_w - (float(in_row) * PLATE.x + float(in_row - 1) * PLATE_GAP.x)) / 2.0
		var x: float = left + floorf(lead / PX) * PX + float(i % 3) * (PLATE.x + PLATE_GAP.x)
		plates[String(rest[i])] = Rect2(Vector2(x, ry2.x), PLATE)

	# The key to the amber corner, under the assembly on its left, when the plates leave room.
	var lowest: float = picture.end.y
	for r_v in plates.values():
		lowest = maxf(lowest, (r_v as Rect2).end.y)
	var legend_at: Vector2 = Vector2(left, floorf((bottom - LEGEND) / PX) * PX)
	if legend_at.y < lowest + PLATE_GAP.y:
		legend_at = Vector2(-1.0, -1.0)

	# The candidates column: the slot's tape, what is in it now, then what fits it.
	var tape_at: Vector2 = Vector2(col_x, top)
	var current: Rect2 = Rect2(Vector2(col_x, top + Locker.TAPE_H + 12.0), Vector2(col_w, THUMB + 16.0))
	var fits_label_y: float = current.end.y + 20.0
	var list_top: float = fits_label_y + LINE
	var offers: Array = []
	var shown: Array = _entries()
	var first_make: int = _offers().size()
	var more_above: bool = _offer_top > 0
	var oy: float = list_top
	var more_below: bool = false
	# The make group's label sits over its first row, when that row is drawn; -1 when it is not.
	var make_label_y: float = -1.0
	for i in range(_offer_top, shown.size()):
		var offer: Dictionary = shown[i] as Dictionary
		var h: float = _offer_height(offer)
		var label_h: float = LINE + OFFER_GAP if i == first_make else 0.0
		if oy + label_h + h > bottom - LINE and i > _offer_top:
			more_below = true
			break
		if label_h > 0.0:
			make_label_y = oy + OFFER_GAP
			oy += label_h + OFFER_GAP
		offers.append({"rect": Rect2(Vector2(col_x, oy), Vector2(col_w, h)), "index": i, "item": int(offer.get("item", -1)), "recipe": String(offer.get("recipe", "")), "slot": String(offer.get("slot", ""))})
		oy += h + OFFER_GAP

	# The footer: the two things Enter can do, as buttons, present only when the sim would take
	# them, then Esc. Laid out from the right edge in.
	var foot_y: float = frame.end.y - FOOT_H
	var buttons: Array = []
	var font_w: float = Chrome.font().get_string_size("close", HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x
	var esc_w: float = _keycap_width("Esc")
	var bx: float = frame.end.x - PAD - ceilf(font_w) - 8.0 - esc_w
	var esc_at: Vector2 = Vector2(bx, foot_y + floorf((FOOT_H - _keycap_height()) / 2.0 / PX) * PX + PX * 2.0)
	bx -= 32.0
	var bh: float = 40.0
	var by: float = foot_y + floorf((FOOT_H - bh) / 2.0 / PX) * PX + PX * 2.0
	for kind in ["fit", "make it", "take off"]:
		if not _can(kind):
			continue
		var bw: float = Locker.label_width(String(kind), NAME_SIZE) + PX * 6.0
		bx -= bw
		buttons.append({"rect": Rect2(Vector2(bx, by), Vector2(bw, bh)), "kind": kind})
		bx -= 12.0
	return {
		"frame": frame, "picture": picture, "plates": plates, "tape_at": tape_at, "current": current,
		"fits_label_y": fits_label_y, "offers": offers, "more_above": more_above, "more_below": more_below, "make_label_y": make_label_y,
		"legend_at": legend_at, "foot_y": foot_y, "buttons": buttons, "esc_at": esc_at, "enter_x": bx, "col_x": col_x, "col_w": col_w,
	}


func _offer_height(offer: Dictionary) -> float:
	if _is_make(offer):
		return OFFER_THUMB + 16.0
	var changes: int = (offer.get("changes", []) as Array).size()
	return maxf(OFFER_THUMB + 16.0, 12.0 + LINE + float(changes) * LINE + 10.0)


static func _keycap_height() -> float:
	return maxf(Chrome.KEYCAP_MIN, float(SMALL_SIZE) + 8.0)


static func _keycap_width(label: String) -> float:
	var text_w: float = ceilf(Chrome.font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE).x)
	# Chrome.keycap's own arithmetic, so a cap placed from its right edge lands where it is drawn.
	var pad: float = float(Kit.margins("keycap")[0]) + 4.0 if not Kit.margins("keycap").is_empty() else 9.0
	return maxf(_keycap_height(), text_w + pad * 2.0)


# Whether the footer's button would do anything: the sim decided every answer already (the row's
# `removable`, the candidate's presence in `offers`, filtered by `may_work`, and a make row's
# `makeable`, which is `improvise`'s own check).
func _can(kind: String) -> bool:
	if kind == "take off":
		var row: Dictionary = _row(_pick)
		return bool(row.get("removable", false)) and int(row.get("part", -1)) >= 0
	var on: Dictionary = _focused() if _side == "offers" else {}
	if kind == "fit":
		return not on.is_empty() and not _is_make(on)
	if kind == "make it":
		return not on.is_empty() and _is_make(on) and bool(on.get("makeable", false))
	return false


# What Enter does now: the button lit in the footer.
func _enter_does() -> String:
	if _side == "offers" and _can("fit"):
		return "fit"
	if _side == "offers" and _can("make it"):
		return "make it"
	if _side == "slots" and _can("take off"):
		return "take off"
	return ""


# --- drawing --------------------------------------------------------------------------------------

func _say(at: Vector2, text: String, font_size: int, col: Color, kind: String = "word") -> void:
	_said.append({"text": text, "kind": kind})
	draw_string(Chrome.font(), at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


func _baseline(top: float, font_size: int) -> float:
	return floorf(top + Chrome.ascent(font_size))


func _draw() -> void:
	_said.clear()
	_locked.clear()
	_eared.clear()
	if _view.is_empty():
		return
	var lay: Dictionary = layout()
	var frame: Rect2 = lay["frame"] as Rect2
	draw_rect(Rect2(Vector2.ZERO, size), Locker.WASH)
	Locker.panel(self, frame, 1.0)
	var font: Font = Chrome.font()

	# The header: the weapon's name on tape, its condition word after it, and where the work is
	# being done at the far end.
	var name: String = String(_view.get("name", "weapon"))
	var place: String = "at the bench" if _at_bench() else "by hand"
	# The note sits in from the frame's corner bracket rather than against it.
	Locker.header(self, frame, name, 1.0, place, PX * 4.0)
	_said.append({"text": name.to_upper(), "kind": "name"})
	_said.append({"text": place, "kind": "word"})
	var tape_w: float = Locker.label_width(name.to_upper(), Locker.LABEL_SIZE)
	var band: String = String(_view.get("condition", ""))
	if not band.is_empty():
		var cx: float = frame.position.x + PX * 4.0 + tape_w + 16.0
		var cy: float = floorf(frame.position.y + PX * 2.0 + (Locker.TAPE_H - Chrome.line_height(NAME_SIZE)) / 2.0 + Chrome.ascent(NAME_SIZE))
		_say(Vector2(cx, cy), band, NAME_SIZE, _band_colour(band))

	_draw_assembly(lay)
	_draw_candidates(lay, font)
	_draw_footer(lay, font)


func _draw_assembly(lay: Dictionary) -> void:
	var picture: Rect2 = lay["picture"] as Rect2
	var plates: Dictionary = lay["plates"] as Dictionary
	# Leader lines first, so the plates and the picture sit over their ends.
	for slot_v in plates.keys():
		_draw_leader(String(slot_v), plates[slot_v] as Rect2, picture)
	Locker.well(self, picture, 1.0)
	var host: int = int(_view.get("host", -1))
	var base: String = ItemPicture.base_of(_world, host)
	if not base.is_empty():
		ItemPicture.draw(self, picture.grow(-PX * 4.0), Appearance.item_look(_world, base), 1.0, PICTURE_SCALE, false)
	for row_v in _view.get("slots", []) as Array:
		var row: Dictionary = row_v as Dictionary
		var slot: String = String(row.get("slot", ""))
		if plates.has(slot):
			_draw_plate(row, plates[slot] as Rect2)
	_draw_legend(lay)


# The key to the amber corner, drawn only while some plate wears one (the plates draw first).
func _draw_legend(lay: Dictionary) -> void:
	var at: Vector2 = lay["legend_at"] as Vector2
	if at.x < 0.0:
		return
	if _eared.is_empty():
		return
	var box: Rect2 = Rect2(at, Vector2(LEGEND, LEGEND))
	Locker.well(self, box, 1.0)
	_draw_ear(box)
	var base_y: float = floorf(at.y + (LEGEND - Chrome.line_height(SMALL_SIZE)) / 2.0 + Chrome.ascent(SMALL_SIZE))
	_say(Vector2(box.end.x + 12.0, base_y), LEGEND_SAYS, SMALL_SIZE, Locker.TEXT_DIM)


func _draw_ear(r: Rect2) -> void:
	var ear: float = PX * 5.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(r.end.x - PX, r.end.y - PX - ear), Vector2(r.end.x - PX, r.end.y - PX), Vector2(r.end.x - PX - ear, r.end.y - PX),
	]), Locker.ACCENT)


# A two-pixel line from an anchored plate to the picture's nearest edge: the sight down onto the
# top, the stock and the muzzle device in from the sides, the magazine up into the bottom, and the
# underbarrel up and across to the bottom's right end. A plate in the row beneath has none.
func _draw_leader(slot: String, plate: Rect2, picture: Rect2) -> void:
	if not ANCHOR.has(slot):
		return
	var col: Color = Locker.TEXT_FAINT
	var cell: Vector2i = ANCHOR[slot] as Vector2i
	var mid: Vector2 = (plate.get_center() / PX).floor() * PX
	match cell:
		Vector2i(1, 0):
			draw_rect(Rect2(Vector2(mid.x, plate.end.y), Vector2(PX, picture.position.y - plate.end.y)), col)
		Vector2i(0, 1):
			draw_rect(Rect2(Vector2(plate.end.x, mid.y), Vector2(picture.position.x - plate.end.x, PX)), col)
		Vector2i(2, 1):
			draw_rect(Rect2(Vector2(picture.end.x, mid.y), Vector2(plate.position.x - picture.end.x, PX)), col)
		Vector2i(1, 2):
			draw_rect(Rect2(Vector2(mid.x, picture.end.y), Vector2(PX, plate.position.y - picture.end.y)), col)
		Vector2i(2, 2):
			var x: float = plate.position.x + PX * 8.0
			var knee: float = picture.end.y - PX * 6.0
			draw_rect(Rect2(Vector2(x, knee), Vector2(PX, plate.position.y - knee)), col)
			draw_rect(Rect2(Vector2(picture.end.x, knee), Vector2(x - picture.end.x + PX, PX)), col)


func _draw_plate(row: Dictionary, r: Rect2) -> void:
	var part: int = int(row.get("part", -1))
	var required: bool = bool(row.get("required", false))
	Locker.well(self, r, 1.0)
	var thumb: Rect2 = Rect2(Vector2(r.position.x + PX * 4.0, r.position.y + floorf((r.size.y - THUMB) / 2.0 / PX) * PX), Vector2(THUMB, THUMB))
	# By hand, a fitted part the hands cannot take off (`removable` is the sim's answer) is locked:
	# its picture washed, its words dimmed, a "bench" tape on its top edge, and no amber corner.
	var locked: bool = part >= 0 and not _at_bench() and not bool(row.get("removable", false))
	if locked:
		_locked.append(String(row.get("slot", "")))
	if part >= 0:
		var base: String = ItemPicture.base_of(_world, part)
		# A recessed well, not a class plate: a plate's bright corner would read as the amber "fits"
		# corner below, and on this screen only that corner means anything.
		Locker.well(self, thumb, 1.0)
		if not base.is_empty():
			ItemPicture.draw(self, thumb.grow(-PX), Appearance.item_look(_world, base), 1.0)
		if locked:
			draw_rect(thumb.grow(-PX), LOCKED_WASH)
	else:
		Locker.rim(self, thumb, Locker.WELL_LIP)
	var tx: float = thumb.end.x + 12.0
	var room: float = r.end.x - PX * 4.0 - tx
	var font: Font = Chrome.font()
	var noun: String = String(row.get("noun", ""))
	var cond: String = String(row.get("condition", ""))
	# The first line starts clear of a "needed" tape's lower half, which hangs over the top edge.
	var line1: float = _baseline(r.position.y + PLATE_TEXT_TOP, SMALL_SIZE)
	var cond_w: float = ceilf(font.get_string_size(cond, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE).x) if not cond.is_empty() else 0.0
	_say(Vector2(tx, line1), UiText.fit(font, noun, SMALL_SIZE, room - cond_w - 8.0), SMALL_SIZE, Locker.TEXT_DIM)
	if not cond.is_empty():
		_say(Vector2(r.end.x - PX * 4.0 - cond_w, line1), cond, SMALL_SIZE, _band_colour(cond))
	var line2: float = _baseline(r.position.y + PLATE_TEXT_TOP + 26.0, NAME_SIZE)
	if part >= 0:
		_say(Vector2(tx, line2), UiText.fit(font, String(row.get("name", "")), NAME_SIZE, room), NAME_SIZE, Locker.TEXT_DIM if locked else Locker.TEXT, "name")
	else:
		_say(Vector2(tx, line2), "empty", NAME_SIZE, DANGER_INK if required else Locker.TEXT_DIM)
	if required and part < 0:
		Locker.rim(self, r, Locker.DANGER)
	if not locked and _fits(String(row.get("slot", ""))):
		_eared.append(String(row.get("slot", "")))
		# An amber dog-ear in the bottom-right corner: something you carry fits this slot. The
		# sim's answer (an offer for the slot), not a guess here.
		_draw_ear(r)
	if String(row.get("slot", "")) == _pick:
		if _side == "slots":
			Locker.selected(self, r, 1.0)
		else:
			Locker.rim(self, r, Locker.ACCENT)
	if required:
		# Taped across the plate's top edge, at its right end: this slot is one the weapon will not
		# work without.
		var label: String = "needed"
		var tw: float = Locker.label_width(label.to_upper(), Locker.LABEL_SIZE)
		Locker.tape(self, Vector2(r.end.x - tw - PX * 6.0, r.position.y - floorf(Locker.TAPE_H / 2.0 / PX) * PX), label, 1.0)
		_said.append({"text": label.to_upper(), "kind": "word"})
	if locked:
		# The "needed" tape's style at the other end of the top edge: this part is the bench's job.
		var lock_label: String = "bench"
		Locker.tape(self, Vector2(r.position.x + PX * 6.0, r.position.y - floorf(Locker.TAPE_H / 2.0 / PX) * PX), lock_label, 1.0)
		_said.append({"text": lock_label.to_upper(), "kind": "word"})


func _draw_candidates(lay: Dictionary, font: Font) -> void:
	var row: Dictionary = _row(_pick)
	if row.is_empty():
		return
	var col_x: float = float(lay["col_x"])
	var col_w: float = float(lay["col_w"])
	var noun: String = String(row.get("noun", ""))
	Locker.tape(self, lay["tape_at"] as Vector2, noun, 1.0)
	_said.append({"text": noun.to_upper(), "kind": "word"})

	# What is in the slot now.
	var cur: Rect2 = lay["current"] as Rect2
	Locker.well(self, cur, 1.0)
	var thumb: Rect2 = Rect2(cur.position + Vector2(PX * 4.0, PX * 4.0), Vector2(THUMB, THUMB))
	var part: int = int(row.get("part", -1))
	var tx: float = thumb.end.x + 12.0
	var room: float = cur.end.x - PX * 4.0 - tx
	_say(Vector2(tx, _baseline(cur.position.y + 10.0, SMALL_SIZE)), "in it now", SMALL_SIZE, Locker.TEXT_DIM)
	if part >= 0:
		Locker.well(self, thumb, 1.0)
		var base: String = ItemPicture.base_of(_world, part)
		if not base.is_empty():
			ItemPicture.draw(self, thumb.grow(-PX), Appearance.item_look(_world, base), 1.0)
		var cond: String = String(row.get("condition", ""))
		var cond_w: float = ceilf(font.get_string_size(cond, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE).x) if not cond.is_empty() else 0.0
		var line2: float = _baseline(cur.position.y + 36.0, NAME_SIZE)
		_say(Vector2(tx, line2), UiText.fit(font, String(row.get("name", "")), NAME_SIZE, room - cond_w - 12.0), NAME_SIZE, Locker.TEXT, "name")
		if not cond.is_empty():
			_say(Vector2(cur.end.x - PX * 4.0 - cond_w, line2), cond, SMALL_SIZE, _band_colour(cond))
	else:
		Locker.rim(self, thumb, Locker.WELL_LIP)
		_say(Vector2(tx, _baseline(cur.position.y + 36.0, NAME_SIZE)), "nothing", NAME_SIZE, Locker.TEXT_DIM)

	# What fits it, from what you carry, then what could be made for it.
	var shown: Array = _entries()
	var label_y: float = float(lay["fits_label_y"])
	if _offers().is_empty():
		_say(Vector2(col_x, _baseline(label_y, SMALL_SIZE)), "nothing you carry fits it", SMALL_SIZE, Locker.TEXT_DIM)
		if shown.is_empty():
			return
	else:
		_say(Vector2(col_x, _baseline(label_y, SMALL_SIZE)), "what you carry that fits", SMALL_SIZE, Locker.TEXT_DIM)
	if bool(lay["more_above"]):
		var above: String = "more above"
		var aw: float = font.get_string_size(above, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE).x
		_say(Vector2(col_x + col_w - aw, _baseline(label_y, SMALL_SIZE)), above, SMALL_SIZE, Locker.TEXT_DIM)
	var make_y: float = float(lay["make_label_y"])
	if make_y >= 0.0:
		_say(Vector2(col_x, _baseline(make_y, SMALL_SIZE)), MAKE_SAYS, SMALL_SIZE, Locker.TEXT_DIM)
	for card_v in lay["offers"] as Array:
		var card: Dictionary = card_v as Dictionary
		var entry: Dictionary = shown[int(card["index"])] as Dictionary
		var focused: bool = int(card["index"]) == _offer and _side == "offers"
		if _is_make(entry):
			_draw_make(entry, card["rect"] as Rect2, focused, font)
		else:
			_draw_offer(entry, card["rect"] as Rect2, focused, font)
	if bool(lay["more_below"]):
		var last: Array = lay["offers"] as Array
		var below_y: float = ((last[last.size() - 1] as Dictionary)["rect"] as Rect2).end.y + 6.0 if not last.is_empty() else label_y
		_say(Vector2(col_x, _baseline(below_y, SMALL_SIZE)), "more below", SMALL_SIZE, Locker.TEXT_DIM)


func _draw_offer(offer: Dictionary, r: Rect2, focused: bool, font: Font) -> void:
	Locker.well(self, r, 1.0)
	var thumb: Rect2 = Rect2(r.position + Vector2(PX * 4.0, PX * 4.0), Vector2(OFFER_THUMB, OFFER_THUMB))
	Locker.well(self, thumb, 1.0)
	var base: String = ItemPicture.base_of(_world, int(offer.get("item", -1)))
	if not base.is_empty():
		ItemPicture.draw(self, thumb.grow(-PX), Appearance.item_look(_world, base), 1.0)
	var tx: float = thumb.end.x + 12.0
	var cond: String = String(offer.get("condition", ""))
	var cond_w: float = ceilf(font.get_string_size(cond, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE).x) if not cond.is_empty() else 0.0
	var line1: float = _baseline(r.position.y + 10.0, NAME_SIZE)
	_say(Vector2(tx, line1), UiText.fit(font, String(offer.get("name", "")), NAME_SIZE, r.end.x - PX * 4.0 - tx - cond_w - 12.0), NAME_SIZE, Locker.TEXT, "name")
	if not cond.is_empty():
		_say(Vector2(r.end.x - PX * 4.0 - cond_w, line1), cond, SMALL_SIZE, _band_colour(cond))
	var cy: float = r.position.y + 10.0 + LINE + 4.0
	for change_v in offer.get("changes", []) as Array:
		var change: Dictionary = change_v as Dictionary
		var word: String = String(change.get("change", ""))
		var base_y: float = _baseline(cy, SMALL_SIZE)
		var asc: float = Chrome.ascent(SMALL_SIZE)
		var gy: float = floorf(base_y - asc + (asc - Chrome.GLYPH_SMALL) / 2.0)
		var gw: float = _draw_arrow(self, Vector2(tx, gy), word, 1.0)
		_say(Vector2(tx + gw + 6.0, base_y), "%s %s" % [String(change.get("word", "")), word], SMALL_SIZE, _change_colour(word))
		cy += LINE
	if focused:
		Locker.selected(self, r, 1.0)


# A part the bench could make: its picture, its name, and under it what it uses -- or, when it cannot
# be made here and now, what it still needs, in the sim's words. A row that cannot be made is
# dimmed and lights no button; it is listed so the player learns what to bring back.
func _draw_make(entry: Dictionary, r: Rect2, focused: bool, font: Font) -> void:
	var makeable: bool = bool(entry.get("makeable", false))
	Locker.well(self, r, 1.0)
	var thumb: Rect2 = Rect2(r.position + Vector2(PX * 4.0, PX * 4.0), Vector2(OFFER_THUMB, OFFER_THUMB))
	Locker.well(self, thumb, 1.0)
	var recipe: String = String(entry.get("recipe", ""))
	if not recipe.is_empty():
		ItemPicture.draw(self, thumb.grow(-PX), Appearance.item_look(_world, recipe), 1.0)
	if not makeable:
		draw_rect(thumb.grow(-PX), LOCKED_WASH)
	var tx: float = thumb.end.x + 12.0
	var room: float = r.end.x - PX * 4.0 - tx
	var line1: float = _baseline(r.position.y + 10.0, NAME_SIZE)
	_say(Vector2(tx, line1), UiText.fit(font, String(entry.get("name", "")), NAME_SIZE, room), NAME_SIZE, Locker.TEXT if makeable else Locker.TEXT_DIM, "name")
	var line2: float = _baseline(r.position.y + 10.0 + LINE + 4.0, SMALL_SIZE)
	if makeable:
		_say(Vector2(tx, line2), UiText.fit(font, "uses %s" % String(entry.get("spends", "")), SMALL_SIZE, room), SMALL_SIZE, Locker.TEXT_DIM)
	else:
		_say(Vector2(tx, line2), UiText.fit(font, String(entry.get("needs", "")), SMALL_SIZE, room), SMALL_SIZE, DANGER_INK)
	if focused:
		Locker.selected(self, r, 1.0)


func _draw_footer(lay: Dictionary, font: Font) -> void:
	var frame: Rect2 = lay["frame"] as Rect2
	var foot_y: float = float(lay["foot_y"])
	Locker.groove(self, Vector2(frame.position.x + PX * 2.0, foot_y), frame.size.x - PX * 4.0, 1.0)
	var mid: float = foot_y + PX * 2.0 + FOOT_H / 2.0
	# Why the weapon will not work, in the sim's own sentence, or what the screen is for.
	var buttons: Array = lay["buttons"] as Array
	var left_room: float = (float(lay["enter_x"]) if not buttons.is_empty() else (lay["esc_at"] as Vector2).x) - frame.position.x - PAD * 2.0
	var refusal: String = String(_view.get("refusal", ""))
	var base_y: float = floorf(mid - Chrome.line_height(NAME_SIZE) / 2.0 + Chrome.ascent(NAME_SIZE))
	if not refusal.is_empty():
		_say(Vector2(frame.position.x + PAD, base_y), UiText.fit(font, refusal, NAME_SIZE, left_room), NAME_SIZE, DANGER_INK)
	else:
		var hint: String = "pick a slot, then what fits it"
		_say(Vector2(frame.position.x + PAD, base_y), UiText.fit(font, hint, NAME_SIZE, left_room), NAME_SIZE, Locker.TEXT_DIM)
	var lit: String = _enter_does()
	for b_v in buttons:
		var b: Dictionary = b_v as Dictionary
		var kind: String = String(b["kind"])
		Locker.button(self, b["rect"] as Rect2, kind, kind == lit, 1.0)
		_said.append({"text": kind, "kind": "word"})
		if kind == lit:
			var r: Rect2 = b["rect"] as Rect2
			var kw: float = _keycap_width("Enter")
			Chrome.keycap(self, Vector2(r.position.x - kw - 8.0, r.position.y + floorf((r.size.y - _keycap_height()) / 2.0)), "Enter", SMALL_SIZE, 1.0)
			_said.append({"text": "Enter", "kind": "word"})
	var esc_at: Vector2 = lay["esc_at"] as Vector2
	var ew: float = Chrome.keycap(self, esc_at, "Esc", SMALL_SIZE, 1.0)
	_said.append({"text": "Esc", "kind": "word"})
	_say(Vector2(esc_at.x + ew + 8.0, base_y), "close", NAME_SIZE, Locker.TEXT_DIM)


# --- input ----------------------------------------------------------------------------------------

# The pointer the kit dresses the mouse in at `p` (ui/cursors.gd): the hand over a plate, a
# candidate or a button, the arrow anywhere else.
func cursor_at(p: Vector2) -> int:
	if _view.is_empty():
		return Input.CURSOR_ARROW
	return Input.CURSOR_POINTING_HAND if not _hit_at(layout(), p).is_empty() else Input.CURSOR_ARROW


func _hit_at(lay: Dictionary, p: Vector2) -> Dictionary:
	for b_v in lay["buttons"] as Array:
		if ((b_v as Dictionary)["rect"] as Rect2).has_point(p):
			return {"kind": String((b_v as Dictionary)["kind"])}
	var plates: Dictionary = lay["plates"] as Dictionary
	for slot_v in plates.keys():
		if (plates[slot_v] as Rect2).has_point(p):
			return {"kind": "plate", "slot": String(slot_v)}
	for card_v in lay["offers"] as Array:
		if ((card_v as Dictionary)["rect"] as Rect2).has_point(p):
			return {"kind": "offer", "index": int((card_v as Dictionary)["index"])}
	return {}


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_default_cursor_shape = cursor_at((event as InputEventMouseMotion).position) as Control.CursorShape
		return
	if _world == null or _view.is_empty():
		return
	if not (event is InputEventMouseButton) or not (event as InputEventMouseButton).pressed:
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	# Every press over the screen is the screen's, so none of them swings at the street behind it.
	accept_event()
	var lay: Dictionary = layout()
	if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN or mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		if (Rect2(Vector2(float(lay["col_x"]), (lay["current"] as Rect2).end.y), Vector2(float(lay["col_w"]), size.y))).has_point(mb.position):
			_scroll(1 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1, lay)
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var hit: Dictionary = _hit_at(lay, mb.position)
	match String(hit.get("kind", "")):
		"plate":
			pick_slot(String(hit["slot"]))
		"offer":
			_offer = int(hit["index"])
			_side = "offers"
			_press(_offer)
		"take off":
			_take_off()
		"fit":
			_fit(_offer)
		"make it":
			_make(_offer)
	queue_redraw()


# A key `input_map.gd` handed over while the bench has the focus. True when it meant something.
func key(ke: InputEventKey) -> bool:
	if _view.is_empty():
		return false
	var dir: Vector2i = Vector2i.ZERO
	match ke.keycode:
		KEY_UP, KEY_W:
			dir = Vector2i(0, -1)
		KEY_DOWN, KEY_S:
			dir = Vector2i(0, 1)
		KEY_LEFT, KEY_A:
			dir = Vector2i(-1, 0)
		KEY_RIGHT, KEY_D:
			dir = Vector2i(1, 0)
		KEY_ENTER, KEY_KP_ENTER:
			match _enter_does():
				"fit":
					_fit(_offer)
				"make it":
					_make(_offer)
				"take off":
					_take_off()
				_:
					# Nothing in the slot to take off: Enter crosses to what fits it or could be made
					# for it, if anything does.
					if _side == "slots" and not _entries().is_empty():
						_side = "offers"
					else:
						return false
			queue_redraw()
			return true
		_:
			return false
	var lay: Dictionary = layout()
	if _side == "offers":
		if dir.x < 0:
			_side = "slots"
		elif dir.y != 0:
			_offer = clampi(_offer + dir.y, 0, _entries().size() - 1)
			_keep_in_view(lay)
		queue_redraw()
		return true
	var next: String = _neighbour(lay["plates"] as Dictionary, _pick, dir)
	if not next.is_empty():
		pick_slot(next)
	elif dir.x > 0 and not _entries().is_empty():
		_side = "offers"
		_offer = clampi(_offer, 0, _entries().size() - 1)
	queue_redraw()
	return true


# The plate the arrow points at from `from`: the nearest whose centre lies that way, preferring one
# straight along the arrow over one off to the side.
static func _neighbour(plates: Dictionary, from: String, dir: Vector2i) -> String:
	if not plates.has(from):
		return ""
	var here: Vector2 = (plates[from] as Rect2).get_center()
	var best: String = ""
	var best_cost: float = INF
	for slot_v in plates.keys():
		var slot: String = String(slot_v)
		if slot == from:
			continue
		var d: Vector2 = (plates[slot] as Rect2).get_center() - here
		var along: float = d.x * float(dir.x) + d.y * float(dir.y)
		if along <= 1.0:
			continue
		var across: float = absf(d.y) if dir.x != 0 else absf(d.x)
		var cost: float = along + across * 2.0
		if cost < best_cost:
			best_cost = cost
			best = slot
	return best


func _scroll(step: int, lay: Dictionary) -> void:
	var n: int = _entries().size()
	if step > 0 and bool(lay["more_below"]):
		_offer_top = mini(_offer_top + 1, n - 1)
	elif step < 0:
		_offer_top = maxi(0, _offer_top - 1)
	_offer = clampi(_offer, _offer_top, maxi(_offer_top, n - 1))


func _keep_in_view(_lay: Dictionary) -> void:
	if _offer < _offer_top:
		_offer_top = _offer
		return
	# Step the window down until the focused card is drawn.
	for _i in _entries().size():
		var drawn: Array = (layout()["offers"] as Array).map(func(c: Variant) -> int: return int((c as Dictionary)["index"]))
		if drawn.has(_offer):
			return
		_offer_top += 1


# The panel never fits anything itself: it pushes the same commands a gate does, and the sim
# decides whether they are allowed. Every refusal in this feature -- no bench, wrong slot, a part
# already on something -- is answered there and nowhere else.
func _take_off() -> void:
	var row: Dictionary = _row(_pick)
	var part: int = int(row.get("part", -1))
	if part < 0 or not bool(row.get("removable", false)):
		return
	_world.commands.push({"type": "item.detach", "item": part})


# A click on an entry in the right column: a candidate is fitted, a makeable part is made, and a part
# that cannot be made is only picked, so its "needs" line has the keys.
func _press(index: int) -> void:
	var shown: Array = _entries()
	if index < 0 or index >= shown.size():
		return
	if _is_make(shown[index] as Dictionary):
		_make(index)
	else:
		_fit(index)


# Make the part on this row and fit it, through the same command a gate sends. The sim checks every
# refusal again before it spends anything; the row's `makeable` only decides whether to ask.
func _make(index: int) -> void:
	var shown: Array = _entries()
	if index < 0 or index >= shown.size():
		return
	var entry: Dictionary = shown[index] as Dictionary
	if not _is_make(entry) or not bool(entry.get("makeable", false)):
		return
	_world.commands.push({"type": "item.improvise", "host": int(_view.get("host", -1)), "slot": String(entry.get("slot", "")), "recipe": String(entry.get("recipe", ""))})


func _fit(index: int) -> void:
	var shown: Array = _entries()
	if index < 0 or index >= shown.size():
		return
	var offer: Dictionary = shown[index] as Dictionary
	if _is_make(offer):
		return
	var slot: String = String(offer.get("slot", ""))
	var sitting: int = int(_row(slot).get("part", -1))
	if sitting >= 0:
		_world.commands.push({"type": "item.detach", "item": sitting})
	_world.commands.push({"type": "item.attach", "host": int(_view.get("host", -1)), "item": int(offer.get("item", -1)), "slot": slot})


# The kit glyph(s) for a change word, drawn at `at` (top-left, whole pixels): one arrow for
# better or worse, and the left/right pair standing in for a two-headed arrow where neither face
# draws one (docs/23's record, "UI -- one typeface"; docs/30, "The UI Field Kit, live"). Returns
# the width it took, so the caller can put the word after it.
static func _draw_arrow(ci: CanvasItem, at: Vector2, change: String, alpha: float) -> float:
	var gap: float = 2.0
	match change:
		"better":
			Chrome.glyph(ci, "up", at, true, alpha)
			return Chrome.GLYPH_SMALL
		"worse":
			Chrome.glyph(ci, "down", at, true, alpha)
			return Chrome.GLYPH_SMALL
		_:
			Chrome.glyph(ci, "left", at, true, alpha)
			Chrome.glyph(ci, "right", at + Vector2(Chrome.GLYPH_SMALL + gap, 0.0), true, alpha)
			return Chrome.GLYPH_SMALL * 2.0 + gap


static func _change_colour(change: String) -> Color:
	match change:
		"better":
			return Locker.GOOD
		"worse":
			return DANGER_INK
		_:
			return Locker.TEXT_DIM


static func _band_colour(band: String) -> Color:
	match band:
		"sound":
			return Locker.GOOD
		"broken", "barely holding":
			return DANGER_INK
		_:
			return Locker.TEXT
