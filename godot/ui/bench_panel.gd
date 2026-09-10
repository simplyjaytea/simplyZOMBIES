extends Control
# The gunsmithing bench, drawn.
#
# Two columns: what is in the weapon on the left, and what in your pack would go in instead on the
# right, each candidate with what the swap would change. It is the surface `item.attach` and
# `item.detach` have never had -- docs/23 carried "an attachment-fitting screen" as an open piece
# from the day attachments landed.
#
# **This panel computes nothing.** Every word on it comes out of `SimGunsmith.bench_view`, exactly
# as `inspect_pane.gd` draws `inspect_view` and for the same reason: the read model has no
# magnitude in it, so there is no number here to print even by accident. A change reads as the word
# "better", "worse" or "different", and this file turns that into an arrow -- with the word beside
# it, because a glyph the chrome font is missing would otherwise be a silent blank.
#
# The only integers that cross the seam are handles -- `host`, `part`, `item` -- which go straight
# back out on a command and are never drawn.

const Chrome = preload("res://ui/chrome.gd")
const UiText = preload("res://ui/text.gd")
const SimGunsmith = preload("res://sim/modules/gunsmith.gd")

const PAD: float = 20.0
const TITLE_SIZE: int = 24
const BODY_SIZE: int = 18
const SMALL: int = 15
const LINE: float = 26.0
const ROW_H: float = 34.0
const COL_GAP: float = 24.0

var _world: Variant = null
var _actor: int = -1
var _view: Dictionary = {}
## Rows the pointer can hit, rebuilt every draw: {rect, kind: "strip"|"fit", part/item, slot}.
var _hits: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func set_world(world: Variant, actor: int) -> void:
	_world = world
	_actor = actor
	if world == null or actor < 0:
		_view = {}
		visible = false
		return
	var host: int = SimGunsmith.focus_of(world, actor)
	if host < 0:
		_view = {}
		visible = false
		return
	_view = SimGunsmith.bench_view(world, actor, host)
	visible = not _view.is_empty()
	queue_redraw()


func _draw() -> void:
	_hits.clear()
	if _view.is_empty():
		return
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	Chrome.panel(self, rect, 1.0)
	Chrome.header(self, rect, "bench", 1.0)
	var font: Font = Chrome.font()
	var top: float = rect.position.y + Chrome.HEADER_H + PAD
	var col_w: float = (rect.size.x - PAD * 3.0) / 2.0
	var left_x: float = rect.position.x + PAD
	var right_x: float = left_x + col_w + COL_GAP

	# The weapon, and whether it works. The refusal is the sim's own sentence.
	draw_string(font, Vector2(left_x, top + float(TITLE_SIZE)), UiText.fit(font, String(_view.get("name", "")), TITLE_SIZE, rect.size.x - PAD * 2.0), HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, Chrome.TEXT)
	var band: String = String(_view.get("condition", ""))
	draw_string(font, Vector2(left_x, top + float(TITLE_SIZE) + LINE), band, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, _band_colour(band))
	var refusal: String = String(_view.get("refusal", ""))
	if not refusal.is_empty():
		draw_string(font, Vector2(left_x, top + float(TITLE_SIZE) + LINE * 2.0), UiText.fit(font, refusal, BODY_SIZE, rect.size.x - PAD * 2.0), HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, Chrome.DANGER)

	var y: float = top + float(TITLE_SIZE) + LINE * 3.0 + 6.0
	draw_string(font, Vector2(left_x, y), "in it", HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL, Chrome.TEXT_DIM)
	draw_string(font, Vector2(right_x, y), "in the pack", HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL, Chrome.TEXT_DIM)
	y += LINE - 6.0

	var ly: float = y
	for row_v in _view.get("slots", []) as Array:
		var row: Dictionary = row_v as Dictionary
		var r: Rect2 = Rect2(Vector2(left_x, ly), Vector2(col_w, ROW_H - 4.0))
		var part: int = int(row.get("part", -1))
		Chrome.cell(self, r, 1.0)
		var noun: String = String(row.get("noun", ""))
		var name: String = String(row.get("name", ""))
		var col: Color = Chrome.TEXT if part >= 0 else Chrome.TEXT_DIM
		if bool(row.get("required", false)) and part < 0:
			col = Chrome.DANGER
		draw_string(font, Vector2(r.position.x + 8.0, r.position.y + 22.0), UiText.fit(font, "%s — %s" % [noun, name], BODY_SIZE, col_w - 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, col)
		var cond: String = String(row.get("condition", ""))
		if not cond.is_empty():
			draw_string(font, Vector2(r.position.x + col_w - 96.0, r.position.y + 22.0), cond, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL, _band_colour(cond))
		if bool(row.get("removable", false)):
			_hits.append({"rect": r, "kind": "strip", "part": part})
		ly += ROW_H

	var ry: float = y
	for offer_v in _view.get("offers", []) as Array:
		var offer: Dictionary = offer_v as Dictionary
		var changes: Array = offer.get("changes", []) as Array
		var h: float = ROW_H - 4.0 + float(changes.size()) * (LINE - 6.0)
		var r2: Rect2 = Rect2(Vector2(right_x, ry), Vector2(col_w, h))
		Chrome.cell(self, r2, 1.0)
		draw_string(font, Vector2(r2.position.x + 8.0, r2.position.y + 22.0), UiText.fit(font, "%s → %s" % [String(offer.get("name", "")), String(offer.get("noun", ""))], BODY_SIZE, col_w - 16.0), HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, Chrome.TEXT)
		var cy: float = r2.position.y + 22.0 + LINE - 6.0
		for change_v in changes:
			var change: Dictionary = change_v as Dictionary
			var word: String = String(change.get("change", ""))
			draw_string(font, Vector2(r2.position.x + 18.0, cy), "%s %s %s" % [_arrow(word), String(change.get("word", "")), word], HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL, _change_colour(word))
			cy += LINE - 6.0
		_hits.append({"rect": r2, "kind": "fit", "item": int(offer.get("item", -1)), "slot": String(offer.get("slot", ""))})
		ry += h + 6.0

	draw_string(font, Vector2(left_x, rect.size.y - PAD), "click a part to take it off, or one in the pack to fit it · esc to close", HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL, Chrome.TEXT_FAINT)


func _gui_input(event: InputEvent) -> void:
	if _world == null or _view.is_empty():
		return
	if not (event is InputEventMouseButton) or not (event as InputEventMouseButton).pressed:
		return
	if (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	var at: Vector2 = (event as InputEventMouseButton).position
	for hit_v in _hits:
		var hit: Dictionary = hit_v as Dictionary
		if not (hit["rect"] as Rect2).has_point(at):
			continue
		# The panel never fits anything itself: it pushes the same commands a gate does, and the
		# sim decides whether they are allowed. Every refusal in this feature -- no bench, wrong
		# slot, a part already on something -- is answered there and nowhere else.
		if String(hit["kind"]) == "strip":
			_world.commands.push({"type": "item.detach", "item": int(hit["part"])})
		else:
			var slot: String = String(hit["slot"])
			var sitting: int = -1
			for row_v in _view.get("slots", []) as Array:
				if String((row_v as Dictionary).get("slot", "")) == slot:
					sitting = int((row_v as Dictionary).get("part", -1))
			if sitting >= 0:
				_world.commands.push({"type": "item.detach", "item": sitting})
			_world.commands.push({"type": "item.attach", "host": int(_view.get("host", -1)), "item": int(hit["item"]), "slot": slot})
		accept_event()
		return


static func _arrow(change: String) -> String:
	match change:
		"better":
			return "▲"
		"worse":
			return "▼"
		_:
			return "↔"


static func _change_colour(change: String) -> Color:
	match change:
		"better":
			return Chrome.OK
		"worse":
			return Chrome.DANGER
		_:
			return Chrome.TEXT_DIM


static func _band_colour(band: String) -> Color:
	match band:
		"sound":
			return Chrome.OK
		"broken", "barely holding":
			return Chrome.DANGER
		_:
			return Chrome.TEXT
