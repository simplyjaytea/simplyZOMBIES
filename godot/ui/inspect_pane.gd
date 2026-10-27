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
const Locker = preload("res://ui/locker.gd")
const UiText = preload("res://ui/text.gd")
const Appearance = preload("res://presentation/appearance.gd")
const ItemPicture = preload("res://ui/item_picture.gd")

const PAD: float = 16.0
const TITLE_SIZE: int = 30
const BODY_SIZE: int = 25
const LINE: float = 28.0
const SMALL: int = 20
# The picture's well, top left under the header: wide enough for a long gun lying flat at three
# times the art -- the pane is the one close look on the sheet; everything else is the world's 2x. The name, the
# condition and the slot line sit beside it; the sentence below is wide again.
const PICTURE_W: float = 136.0
const PICTURE_H: float = 104.0
const PICTURE_GAP: float = 16.0
# The verb buttons along the foot of the pane.
const BUTTON_H: float = 36.0
const BUTTON_GAP: float = 8.0
# What a verb is called on a button, where the menu's bare word would be unclear out of context.
const VERB_WORDS: Dictionary = {"stash": "put it here", "take": "take it", "unequip": "take off", "name": "name it"}
# The caret in the name field: one art pixel wide, the accent, as tall as the type.
const CARET_W: float = 2.0


static func verb_word(verb: String) -> String:
	return String(VERB_WORDS.get(verb, verb))


# Where each verb's button sits in a pane drawn at `rect`: left to right along the foot, a new row
# above when a row runs out. The panel draws from this list and the click is tested against it, so
# the two cannot disagree about where a button is.
static func button_rects(rect: Rect2, verbs: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if verbs.is_empty():
		return out
	var left: float = rect.position.x + PAD
	var right: float = rect.end.x - PAD
	var rows: Array = [[]]
	var x: float = left
	for v in verbs:
		var w: float = Locker.label_width(verb_word(String(v)), Locker.LABEL_SIZE)
		if x > left and x + w > right:
			rows.append([])
			x = left
		(rows[rows.size() - 1] as Array).append({"verb": String(v), "x": x, "w": minf(w, right - left)})
		x += w + BUTTON_GAP
	var y: float = rect.end.y - PAD - BUTTON_H - float(rows.size() - 1) * (BUTTON_H + BUTTON_GAP)
	for row in rows:
		for b in row as Array:
			var d: Dictionary = b as Dictionary
			out.append({"verb": d["verb"], "rect": Rect2(Vector2(float(d["x"]), y), Vector2(float(d["w"]), BUTTON_H))})
		y += BUTTON_H + BUTTON_GAP
	return out


# `world` is what the picture is resolved against: the same picture the bag plate, the quick strip
# and the floor draw for that base, through `Appearance.item_look` -- the pack's icon, or its class's
# glyph where the pack has none. With no world the pane is words alone, as it was before the pictures.
# `verbs` are the buttons along its foot, from `button_rects`; the first is drawn as the obvious one.
# `field` is the name field while it is open on this item ({item, text, caret}, the panel's own
# typing state): it is drawn in the title's place, so the name you are typing sits where the name
# will be.
static func draw_pane(ci: CanvasItem, rect: Rect2, view: Dictionary, alpha: float, verbs: Array = [], world: Variant = null, field: Dictionary = {}) -> void:
	Locker.panel(ci, rect, alpha)
	var top: float = Locker.header(ci, rect, "inspect", alpha, "", Chrome.GLYPH_SMALL + Locker.PX * 3.0)
	Chrome.glyph(ci, "inspect", Vector2(rect.end.x - Chrome.GLYPH_SMALL - Locker.PX * 5.0, rect.position.y + Locker.PX * 2.0 + floorf((Locker.TAPE_H - Chrome.GLYPH_SMALL) / 2.0)), true, alpha * 0.7)
	var font: Font = Chrome.font()
	var x: float = rect.position.x + PAD
	var wide: float = rect.size.x - PAD * 2.0
	var y: float = top + PAD
	if view.is_empty():
		ci.draw_string(font, Vector2(x, y + Chrome.ascent(BODY_SIZE)), "nothing selected", HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, Locker._a(Locker.TEXT_DIM, alpha))
		ci.draw_string(font, Vector2(x, y + LINE + Chrome.ascent(BODY_SIZE)), UiText.fit(font, "click a thing to read it", BODY_SIZE, wide), HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, Locker._a(Locker.TEXT_FAINT, alpha))
		return

	# The picture in its well, and the width the lines beside it may use.
	var text_x: float = x
	var text_wide: float = wide
	if world != null:
		var base: String = ItemPicture.base_of(world, int(view.get("item", -1)))
		var look: Dictionary = Appearance.item_look(world, base)
		var well := Rect2(Vector2(x, y), Vector2(minf(PICTURE_W, wide * 0.4), PICTURE_H))
		Locker.well(ci, well, alpha)
		# Three times the art here, where everywhere else on the sheet is the world's two: the pane is
		# the close look, and a whole multiple keeps every pixel square.
		ItemPicture.draw(ci, well.grow(-Locker.PX * 3.0), look, alpha, 3)
		text_x = well.end.x + PICTURE_GAP
		text_wide = rect.end.x - PAD - text_x

	var ty: float = y + Chrome.ascent(TITLE_SIZE)
	if not field.is_empty() and int(field.get("item", -2)) == int(view.get("item", -1)):
		draw_field(ci, Rect2(Vector2(text_x - Locker.PX * 2.0, y - Locker.PX * 2.0), Vector2(text_wide + Locker.PX * 2.0, Chrome.line_height(TITLE_SIZE) + Locker.PX * 2.0)), String(field.get("text", "")), int(field.get("caret", 0)), alpha)
	else:
		ci.draw_string(font, Vector2(text_x, ty), UiText.fit(font, String(view.get("name", "")), TITLE_SIZE, text_wide), HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, Locker._a(Locker.TEXT, alpha))
	ty += LINE + 2.0

	# The condition word, and the only place on this screen where a colour carries meaning about
	# an object's state: sound reads calm, broken reads as the warning it is.
	var band: String = String(view.get("condition", ""))
	ci.draw_string(font, Vector2(text_x, ty), "condition ", HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, Locker._a(Locker.TEXT_DIM, alpha))
	var lead: float = font.get_string_size("condition ", HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE).x
	ci.draw_string(font, Vector2(text_x + lead, ty), UiText.fit(font, band, BODY_SIZE, text_wide - lead), HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, Locker._a(_band_colour(band), alpha))
	ty += LINE

	var slot: String = String(view.get("slot", ""))
	if not slot.is_empty():
		var where: String = ("worn on the " + slot) if bool(view.get("worn", false)) else ("goes on the " + slot)
		ci.draw_string(font, Vector2(text_x, ty), UiText.fit(font, where, BODY_SIZE, text_wide), HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, Locker._a(Locker.TEXT_DIM, alpha))
		ty += LINE
	y = maxf(y + PICTURE_H, ty - Chrome.ascent(BODY_SIZE)) + PAD
	Locker.groove(ci, Vector2(x, y - PAD / 2.0), wide, alpha)
	y += Chrome.ascent(BODY_SIZE)

	# Everything below stops above the buttons, so a long sentence never runs under them.
	var buttons: Array[Dictionary] = button_rects(rect, verbs)
	var floor_y: float = rect.end.y - PAD
	if not buttons.is_empty():
		floor_y = (buttons[0]["rect"] as Rect2).position.y - BUTTON_GAP

	# The sentence, wrapped by measurement rather than at a character count -- a description is
	# prose and a hard cut mid-word reads as a bug, which is `ui/text.gd`'s whole lesson.
	for line in _wrap(font, String(view.get("description", "")), BODY_SIZE, wide):
		if y > floor_y:
			break
		ci.draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, Locker._a(Locker.TEXT, alpha))
		y += LINE
	y += 10.0

	# What is on it, and what would go on it. `item.attach` and `item.detach` have worked and had
	# no surface since attachments landed; this is not that surface, but it is the first place the
	# screen says out loud that a weapon has slots and one of them is empty.
	var fitted: Array = view.get("attachments", []) as Array
	if not fitted.is_empty() and y < floor_y:
		ci.draw_string(font, Vector2(x, y), "fitted", HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL, Locker._a(Locker.TEXT_DIM, alpha))
		y += LINE - 4.0
		for row in fitted:
			if y > floor_y:
				break
			var d: Dictionary = row as Dictionary
			var name: String = String(d.get("name", ""))
			var text: String = "%s — %s" % [String(d.get("slot", "")), name if not name.is_empty() else "empty"]
			var col: Color = Locker.TEXT if not name.is_empty() else Locker.TEXT_DIM
			ci.draw_string(font, Vector2(x + 10.0, y), UiText.fit(font, text, BODY_SIZE, wide - 10.0), HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, Locker._a(col, alpha))
			y += LINE - 2.0
		y += 10.0
	var fits: Array = view.get("fits", []) as Array
	if not fits.is_empty() and y < floor_y:
		var where2: String = "fits a " + " or a ".join(PackedStringArray(fits))
		ci.draw_string(font, Vector2(x, y), UiText.fit(font, where2, BODY_SIZE, wide), HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, Locker._a(Locker.TEXT_DIM, alpha))

	for n in buttons.size():
		var b: Dictionary = buttons[n]
		Locker.button(ci, b["rect"] as Rect2, verb_word(String(b["verb"])), n == 0, alpha)


# The name field: a well with the typed text in it and the caret where the next letter goes. The
# title's ladder size while the name fits; a rung down when it does not; and if it still runs past
# the well, the text scrolls so the caret is always on show. Words only, and only what was typed.
static func draw_field(ci: CanvasItem, box: Rect2, text: String, caret: int, alpha: float) -> void:
	Locker.well(ci, box, alpha)
	var font: Font = Chrome.font()
	var inner: float = box.size.x - Locker.PX * 4.0
	var size: int = TITLE_SIZE
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > inner:
		size = BODY_SIZE
	caret = clampi(caret, 0, text.length())
	var start: int = visible_start(font, text, caret, size, inner)
	var shown: String = text.substr(start)
	while not shown.is_empty() and font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > inner:
		shown = shown.left(-1)
	var at := Vector2(box.position.x + Locker.PX * 2.0, box.position.y + (box.size.y - Chrome.line_height(size)) / 2.0 + Chrome.ascent(size))
	ci.draw_string(font, at, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Locker._a(Locker.TEXT, alpha))
	var cx: float = at.x + font.get_string_size(text.substr(start, caret - start), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ci.draw_rect(Rect2(Vector2(cx, at.y - Chrome.ascent(size)), Vector2(CARET_W, Chrome.ascent(size) + Locker.PX)), Locker._a(Locker.ACCENT, alpha))


# The first character the field shows: 0 while everything up to the caret fits, else as far along as
# it takes for the caret to be inside the well.
static func visible_start(font: Font, text: String, caret: int, size: int, inner: float) -> int:
	var start: int = 0
	while start < caret and font.get_string_size(text.substr(start, caret - start), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > inner - CARET_W:
		start += 1
	return start


static func _band_colour(band: String) -> Color:
	match band:
		"sound":
			return Locker.GOOD
		"broken", "barely holding":
			return Locker.DANGER
		_:
			return Locker.ACCENT


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
