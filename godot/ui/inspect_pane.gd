extends RefCounted
# What one item is, in words, down the right of the inventory sheet.
#
# Everything drawn here comes out of `SimInventory.inspect_view` and nothing is computed from the
# item itself: the pane cannot reach the sim, so it cannot draw a number the read model did not
# hand it, and the read model has none to hand. That is the condition view's arrangement applied
# to gear -- `godot:check:inventory`'s INSPECT lane serialises the view and refuses a digit
# anywhere in it, so a damage figure or a weight cannot arrive here later without turning a gate
# red first.
#
# What is deliberately absent: the footprint (the grid already draws it as a shape), the mass
# (docs/10's invisible pressure -- you learn you are overloaded because you are walking slower),
# and anything about how hard it hits. What a weapon does is the sentence.

const Chrome = preload("res://ui/chrome.gd")
const UiText = preload("res://ui/text.gd")

const PAD: float = 20.0
const TITLE_SIZE: int = 24
const BODY_SIZE: int = 18
const LINE: float = 26.0
const SMALL: int = 15


static func draw_pane(ci: CanvasItem, rect: Rect2, view: Dictionary, alpha: float) -> void:
	Chrome.panel(ci, rect, alpha)
	Chrome.header(ci, rect, "inspect", alpha)
	var font: Font = Chrome.font()
	var x: float = rect.position.x + PAD
	var wide: float = rect.size.x - PAD * 2.0
	var y: float = rect.position.y + Chrome.HEADER_H + PAD + float(TITLE_SIZE)
	if view.is_empty():
		ci.draw_string(font, Vector2(x, y), "nothing selected", HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, Chrome.TEXT_DIM)
		ci.draw_string(font, Vector2(x, y + LINE), UiText.fit(font, "click a thing to read it", BODY_SIZE, wide), HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, Chrome.TEXT_DIM)
		return

	ci.draw_string(font, Vector2(x, y), UiText.fit(font, String(view.get("name", "")), TITLE_SIZE, wide), HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, Chrome.TEXT)
	y += LINE + 8.0

	# The condition word, and the only place on this screen where a colour carries meaning about
	# an object's state: sound reads calm, broken reads as the warning it is.
	var band: String = String(view.get("condition", ""))
	ci.draw_string(font, Vector2(x, y), "condition ", HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, Chrome.TEXT_DIM)
	var lead: float = font.get_string_size("condition ", HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE).x
	ci.draw_string(font, Vector2(x + lead, y), band, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, _band_colour(band))
	y += LINE

	var slot: String = String(view.get("slot", ""))
	if not slot.is_empty():
		var where: String = ("worn on the " + slot) if bool(view.get("worn", false)) else ("goes on the " + slot)
		ci.draw_string(font, Vector2(x, y), UiText.fit(font, where, BODY_SIZE, wide), HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, Chrome.TEXT_DIM)
		y += LINE
	y += 10.0

	# The sentence, wrapped by measurement rather than at a character count -- a description is
	# prose and a hard cut mid-word reads as a bug, which is `ui/text.gd`'s whole lesson.
	for line in _wrap(font, String(view.get("description", "")), BODY_SIZE, wide):
		ci.draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, Chrome.TEXT)
		y += LINE
	y += 14.0

	# What is on it, and what would go on it. `item.attach` and `item.detach` have worked and had
	# no surface since attachments landed; this is not that surface, but it is the first place the
	# screen says out loud that a weapon has slots and one of them is empty.
	var fitted: Array = view.get("attachments", []) as Array
	if not fitted.is_empty():
		ci.draw_string(font, Vector2(x, y), "fitted", HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL, Chrome.TEXT_DIM)
		y += LINE - 4.0
		for row in fitted:
			var d: Dictionary = row as Dictionary
			var name: String = String(d.get("name", ""))
			var text: String = "%s — %s" % [String(d.get("slot", "")), name if not name.is_empty() else "empty"]
			var col: Color = Chrome.TEXT if not name.is_empty() else Chrome.TEXT_DIM
			ci.draw_string(font, Vector2(x + 10.0, y), UiText.fit(font, text, BODY_SIZE, wide - 10.0), HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, col)
			y += LINE - 2.0
		y += 10.0
	var fits: Array = view.get("fits", []) as Array
	if not fits.is_empty():
		var where2: String = "fits a " + " or a ".join(PackedStringArray(fits))
		ci.draw_string(font, Vector2(x, y), UiText.fit(font, where2, BODY_SIZE, wide), HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, Chrome.TEXT_DIM)


static func _band_colour(band: String) -> Color:
	match band:
		"sound":
			return Chrome.OK
		"broken", "barely holding":
			return Chrome.DANGER
		_:
			return Chrome.TEXT


# Greedy word wrap by measured width. Words only -- a description is a sentence somebody wrote.
static func _wrap(font: Font, text: String, font_size: int, wide: float) -> Array[String]:
	var out: Array[String] = []
	if text.strip_edges().is_empty():
		return out
	var line: String = ""
	for word in text.split(" ", false):
		var candidate: String = word if line.is_empty() else line + " " + word
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= wide:
			line = candidate
			continue
		if not line.is_empty():
			out.append(line)
		line = String(word)
	if not line.is_empty():
		out.append(line)
	return out
