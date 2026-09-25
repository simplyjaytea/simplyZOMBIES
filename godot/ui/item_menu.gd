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
const PAD_X: float = 22.0
const PAD_Y: float = 12.0
const FONT_SIZE: int = 25
const MIN_W: float = 150.0

# The one verb that is the obvious thing to do with the item under the cursor, drawn in the accent
# the way the treatment responses are. Everything else is plain text -- amber is chrome.gd's one
# colour for the thing that matters, and a menu where every row is amber has no accent at all.
# "attack", "pick up" and "walk here"/"walk over" joined this set with the right-click street menu
# (`ui/context_menu.gd`), whose rows carry the object too ("pick up the tin can") -- a *prefix*
# match (`_is_lead` below) rather than the loot menu's own exact words, so a full sentence still
# lights up on the word that made it the obvious thing to do. One accent list for every word menu
# in the game, not a second one the street menu would have needed to keep in step with this.
const LEAD: Dictionary = {"use": true, "equip": true, "attack": true, "pick up": true, "walk here": true, "walk over": true}


static func _is_lead(verb: String) -> bool:
	for key in LEAD.keys():
		if verb.begins_with(String(key)):
			return true
	return false


# The kit's small glyph beside a word, by the word's first words -- the same prefix match as
# `_is_lead`, so the street menu's full sentences ("open the crate", "look at Mara", "walk here")
# find their glyph on the verb that starts them. The UI Field Kit, live (docs/30): a glyph names
# the kind of thing a row does, never a state -- there is no glyph for a verb the sim refused,
# because a refused verb is not in the menu at all. A verb with none keeps its gutter blank.
const GLYPHS: Dictionary = {
	"use": "use",
	"drop": "drop",
	"inspect": "inspect",
	"look at": "inspect",
	"search": "search",
	"open": "search",
	"walk": "move",
	"move": "move",
}
# Between the glyph gutter and the word.
const GLYPH_GAP: float = 8.0


# The kit glyph a row wears, or "" for none.
static func glyph_of(verb: String) -> String:
	for key in GLYPHS.keys():
		if verb.begins_with(String(key)):
			return String(GLYPHS[key])
	return ""


# How far the words sit right of the pad: a small glyph and its gap when any row in this menu
# has a glyph, nothing when none does -- a menu of words with no glyph among them does not carry
# an empty column. Part of `size_of`, so `draw_menu` and `verb_rects` share it.
static func gutter_of(verbs: Array) -> float:
	for verb in verbs:
		if not glyph_of(String(verb)).is_empty():
			return Chrome.GLYPH_SMALL + GLYPH_GAP
	return 0.0


static func size_of(verbs: Array) -> Vector2:
	var font: Font = Chrome.font()
	var gutter: float = gutter_of(verbs)
	var wide: float = MIN_W
	for verb in verbs:
		wide = maxf(wide, font.get_string_size(String(verb), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + gutter + PAD_X * 2.0)
	return Vector2(wide, PAD_Y * 2.0 + ROW_H * float(verbs.size()))


static func draw_menu(ci: CanvasItem, at: Vector2, verbs: Array, alpha: float) -> void:
	if verbs.is_empty():
		return
	var rect := Rect2(at, size_of(verbs))
	Chrome.panel(ci, rect, minf(1.0, alpha + 0.05))
	var font: Font = Chrome.font()
	var gutter: float = gutter_of(verbs)
	for i in verbs.size():
		var verb: String = String(verbs[i])
		var col: Color = Chrome.ACCENT if _is_lead(verb) else Chrome.TEXT
		var mark: String = glyph_of(verb)
		if not mark.is_empty():
			Chrome.glyph(ci, mark, at + Vector2(PAD_X, PAD_Y + ROW_H * float(i) + floorf((ROW_H - Chrome.GLYPH_SMALL) / 2.0)), true, minf(1.0, alpha))
		ci.draw_string(font, at + Vector2(PAD_X + gutter, PAD_Y + ROW_H * float(i) + ROW_H * 0.7), verb, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, col)


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
