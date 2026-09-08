extends RefCounted
# The word menu on a right-click. Words, in the sim's own order, and only the ones the sim would
# accept -- `SimInventory.verbs_for` decides what is in it and this file decides nothing.
#
# There is no greyed-out row and no "you cannot do that because" beside one. That is
# `work_panel.gd`'s rule and `SimTreatment.response_view`'s contract: a thing you can do is simply
# there, and a thing you cannot is absent. A greyed row is a promise the screen has to keep
# explaining.

const Chrome = preload("res://ui/chrome.gd")

const ROW_H: float = 32.0
const PAD_X: float = 16.0
const PAD_Y: float = 8.0
const FONT_SIZE: int = 18
const MIN_W: float = 150.0

# The one verb that is the obvious thing to do with the item under the cursor, drawn in the accent
# the way the treatment responses are. Everything else is plain text -- amber is chrome.gd's one
# colour for the thing that matters, and a menu where every row is amber has no accent at all.
const LEAD: Dictionary = {"use": true, "equip": true}


static func size_of(verbs: Array) -> Vector2:
	var font: Font = Chrome.font()
	var wide: float = MIN_W
	for verb in verbs:
		wide = maxf(wide, font.get_string_size(String(verb), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + PAD_X * 2.0)
	return Vector2(wide, PAD_Y * 2.0 + ROW_H * float(verbs.size()))


static func draw_menu(ci: CanvasItem, at: Vector2, verbs: Array, alpha: float) -> void:
	if verbs.is_empty():
		return
	var rect := Rect2(at, size_of(verbs))
	Chrome.panel(ci, rect, minf(1.0, alpha + 0.05))
	var font: Font = Chrome.font()
	for i in verbs.size():
		var verb: String = String(verbs[i])
		var col: Color = Chrome.ACCENT if LEAD.has(verb) else Chrome.TEXT
		ci.draw_string(font, at + Vector2(PAD_X, PAD_Y + ROW_H * float(i) + ROW_H * 0.7), verb, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, col)


# The rectangle for each row, in the same arithmetic `draw_menu` uses, so the word you can see and
# the word you can click cannot drift apart. The rule `work_panel.gd` set and `inventory_panel.gd`
# has followed since the treatment words landed.
static func verb_rects(at: Vector2, verbs: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var wide: float = size_of(verbs).x
	for i in verbs.size():
		out.append({
			"rect": Rect2(at + Vector2(0.0, PAD_Y + ROW_H * float(i)), Vector2(wide, ROW_H)),
			"verb": String(verbs[i]),
		})
	return out
