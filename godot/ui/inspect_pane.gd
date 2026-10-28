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
const VERB_WORDS: Dictionary = {"stash": "put it here", "take": "take it", "unequip": "take off", "name": "name it", "handload": "hand-load"}
# The caret in the name field: one art pixel wide, the accent, as tall as the type.
const CARET_W: float = 2.0
# The most rows a state line may take beside the picture (`state_rows`).
const STATE_ROWS: int = 2
# From the well's edge to the first letter, and from the last to the far edge: the rim's art pixel
# and two of fill.
const FIELD_INSET: float = 6.0


# The one state line under the condition, as {label, word}: a blade's edge, a lamp's fuel, a barrel's
# words, or what a firearm is loaded with, and nothing for an item that is none of them. Every word
# comes out of `inspect_view` ready-made; the pane only chooses which one is not empty. No item is
# two of them, and the edge is asked first so a future one would still draw one line, not two.
static func state_line(view: Dictionary) -> Dictionary:
	var edge: String = String(view.get("edge", ""))
	if not edge.is_empty():
		return {"label": "edge", "word": edge}
	var fuel: String = String(view.get("fuel", ""))
	if not fuel.is_empty():
		return {"label": "fuel", "word": fuel}
	# A barrel's departures from the identity, "long, match": a part, so no blade or lamp is one too.
	var barrel: String = String(view.get("barrel", ""))
	if not barrel.is_empty():
		return {"label": "barrel", "word": barrel}
	# What a magazine-fed weapon holds: "empty", "slug", "mixed". No firearm is a blade or a lamp,
	# so this is still one line.
	var load: String = String(view.get("load", ""))
	if not load.is_empty():
		return {"label": "load", "word": load}
	return {}


# How a state line is laid out in `room` px at the body size, as rows of {label, word}; `draw_pane`
# draws them and STATE FIT measures them, so the two cannot disagree. One row while label and word
# fit together, which every edge, fuel and load word does. A phrase that does not (a barrel's
# "carbine, rough, chromed") breaks after a comma: the label and as many words as fit beside it,
# the rest on a second row from the label's left edge. Only when that still does not fit is the
# label dropped and the words wrapped on their own, never the type shrunk (docs/30, "The barrel's
# words wrap, 2026-10-28"). More than STATE_ROWS rows means the phrase does not fit; the pane draws
# the rest on its last row cut to an ellipsis, and the gate refuses the phrase first.
static func state_rows(font: Font, state: Dictionary, room: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state.is_empty():
		return out
	var label: String = String(state["label"]) + " "
	var word: String = String(state["word"])
	var lead: float = _width(font, label)
	if lead + _width(font, word) <= room:
		out.append({"label": label, "word": word})
		return out
	var parts: PackedStringArray = word.split(", ", false)
	var beside: int = _parts_that_fit(font, parts, 0, room - lead)
	if beside > 0:
		var rest: String = _parts_line(parts, beside, parts.size())
		if _width(font, rest) <= room:
			out.append({"label": label, "word": _parts_line(parts, 0, beside)})
			out.append({"label": "", "word": rest})
			return out
	# The label goes before the type does: the words alone, wrapped at their commas.
	var at: int = 0
	while at < parts.size():
		var take: int = maxi(1, _parts_that_fit(font, parts, at, room))
		out.append({"label": "", "word": _parts_line(parts, at, at + take)})
		at += take
	return out


# How many of `parts` from `from` fit on one line of `room`, with the comma a line ends on when
# more follow.
static func _parts_that_fit(font: Font, parts: PackedStringArray, from: int, room: float) -> int:
	var fit: int = 0
	for to in range(from + 1, parts.size() + 1):
		if _width(font, _parts_line(parts, from, to)) > room:
			break
		fit = to - from
	return fit


# `parts[from..to)` as one line of the phrase, ending on its comma when the phrase goes on.
static func _parts_line(parts: PackedStringArray, from: int, to: int) -> String:
	var line: String = ", ".join(parts.slice(from, to))
	return line + "," if to < parts.size() else line


static func _width(font: Font, text: String) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE).x


# How wide the lines beside the picture may run in a pane of this rect: the name, the condition,
# the state line and the slot line. `draw_pane` lays them out with it, and the STATE lane holds
# every state word to it at the narrowest window, so a word that would be cut to an ellipsis turns
# the gate red instead of reaching the screen.
static func side_width(rect: Rect2) -> float:
	var wide: float = rect.size.x - PAD * 2.0
	return wide - minf(PICTURE_W, wide * 0.4) - PICTURE_GAP


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
# will be. It comes before `world`, which stays last: `godot:check:appearance` PICTURES reads the
# sheet's call for the world as its final argument.
static func draw_pane(ci: CanvasItem, rect: Rect2, view: Dictionary, alpha: float, verbs: Array = [], field: Dictionary = {}, world: Variant = null) -> void:
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
		text_wide = side_width(rect)

	var ty: float = y + Chrome.ascent(TITLE_SIZE)
	if not field.is_empty() and int(field.get("item", -2)) == int(view.get("item", -1)):
		draw_field(ci, field_rect(rect, world != null), String(field.get("text", "")), int(field.get("caret", 0)), alpha, String(field.get("plain", "")), int(field.get("start", -1)))
	else:
		# The title takes the field's rule: its own rung while the name fits, a rung down when it does
		# not, and only then the ellipsis. A name typed whole in the field stays whole once it is kept.
		var title: String = String(view.get("name", ""))
		var title_size: int = TITLE_SIZE if font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE).x <= text_wide else BODY_SIZE
		ci.draw_string(font, Vector2(text_x, ty), UiText.fit(font, title, title_size, text_wide), HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, Locker._a(Locker.TEXT, alpha))
	ty += LINE + 2.0

	# The condition word, and the only place on this screen where a colour carries meaning about
	# an object's state: sound reads calm, broken reads as the warning it is.
	var band: String = String(view.get("condition", ""))
	ci.draw_string(font, Vector2(text_x, ty), "condition ", HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, Locker._a(Locker.TEXT_DIM, alpha))
	var lead: float = font.get_string_size("condition ", HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE).x
	ci.draw_string(font, Vector2(text_x + lead, ty), UiText.fit(font, band, BODY_SIZE, text_wide - lead), HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, Locker._a(_band_colour(band), alpha))
	ty += LINE

	# The state line: how keen a blade is, or how much a lamp has left, in the condition's shape. A
	# phrase too long for one line (a barrel with more than one departure) takes a second, laid out by
	# `state_rows`.
	var state: Dictionary = state_line(view)
	if not state.is_empty():
		var ink: Color = Locker._a(_state_colour(String(state["word"]), String(state["label"])), alpha)
		var rows: Array[Dictionary] = state_rows(font, state, text_wide)
		for n in mini(rows.size(), STATE_ROWS):
			var label: String = String(rows[n]["label"])
			var word: String = String(rows[n]["word"])
			# Past the last row the pane has room for, the rest goes on that row and the cut is marked.
			if n == STATE_ROWS - 1 and rows.size() > STATE_ROWS:
				var rest: PackedStringArray = []
				for m in range(n, rows.size()):
					rest.append(String(rows[m]["word"]))
				word = " ".join(rest)
			var state_lead: float = 0.0
			if not label.is_empty():
				ci.draw_string(font, Vector2(text_x, ty), label, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, Locker._a(Locker.TEXT_DIM, alpha))
				state_lead = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE).x
			ci.draw_string(font, Vector2(text_x + state_lead, ty), UiText.fit(font, word, BODY_SIZE, text_wide - state_lead), HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE, ink)
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


# Where the name field stands in a pane drawn at `rect`: over the title's line, beside the picture
# when there is one, one art pixel proud of the text on the left and above. The pane draws it here
# and the panel tests a click against it, so the two cannot disagree about where the field is.
static func field_rect(rect: Rect2, with_picture: bool) -> Rect2:
	var x: float = rect.position.x + PAD
	var wide: float = rect.size.x - PAD * 2.0
	var y: float = Locker._snap(rect).position.y + Locker.HEAD_H + PAD
	var text_x: float = x
	if with_picture:
		text_x = x + minf(PICTURE_W, wide * 0.4) + PICTURE_GAP
	var text_wide: float = rect.end.x - PAD - text_x
	return Rect2(Vector2(text_x - Locker.PX * 2.0, y - Locker.PX * 2.0), Vector2(text_wide + Locker.PX * 2.0, Chrome.line_height(TITLE_SIZE) + Locker.PX * 2.0))


# The name field: a well with the typed text in it and the caret where the next letter goes. The
# title's ladder size while the name fits; a rung down when it does not; and if it still runs past
# the well, the text scrolls so the caret is always on show. Words only, and only what was typed --
# except an empty field, which shows `plain` dimmed behind the caret: the name the item goes back to
# if Enter keeps nothing.
static func draw_field(ci: CanvasItem, box: Rect2, text: String, caret: int, alpha: float, plain: String = "", start: int = -1) -> void:
	Locker.well(ci, box, alpha)
	# One art pixel of the accent round the well: the picture's well is the same well, and this is
	# what says the one on the right is live and taking keys. Snapped as the well is, so the rim
	# sits on the art grid at 1280 too.
	Locker.rim(ci, Locker._snap(box), Locker._a(Locker.ACCENT, alpha * 0.85))
	var font: Font = Chrome.font()
	var lay: Dictionary = field_layout(font, box, text, caret, start)
	var size: int = int(lay["size"])
	var at: Vector2 = lay["at"] as Vector2
	if text.is_empty() and not plain.is_empty():
		ci.draw_string(font, at + Vector2(CARET_W + Locker.PX, 0.0), UiText.fit(font, plain, size, box.size.x - FIELD_INSET * 2.0 - CARET_W - Locker.PX), HORIZONTAL_ALIGNMENT_LEFT, -1, size, Locker._a(Locker.TEXT_DIM, alpha))
	ci.draw_string(font, at, String(lay["shown"]), HORIZONTAL_ALIGNMENT_LEFT, -1, size, Locker._a(Locker.TEXT, alpha))
	ci.draw_rect(caret_rect(box, float(lay["caret_x"])), Locker._a(Locker.ACCENT, alpha))


# The caret at `x` in a field drawn in `box`: the well's height less two art pixels top and bottom,
# so it brackets the letters rather than hanging off the top of the face's padded ascent.
static func caret_rect(box: Rect2, x: float) -> Rect2:
	return Rect2(Vector2(x, box.position.y + Locker.PX * 2.0), Vector2(CARET_W, box.size.y - Locker.PX * 4.0))


# How the field lays out `text` in `box` with the caret at `caret`: the size it is drawn at, the
# first character shown, the part that fits, where the text's baseline starts and where the caret
# stands. The draw reads it and so does a click placing the caret. `start` is where the field was
# scrolled to last (-1 for none): kept while the caret stays on show, so a click or an arrow inside
# the visible letters moves the caret and not the text.
static func field_layout(font: Font, box: Rect2, text: String, caret: int, start: int = -1) -> Dictionary:
	var inner: float = box.size.x - FIELD_INSET * 2.0
	var size: int = TITLE_SIZE
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > inner - CARET_W:
		size = BODY_SIZE
	caret = clampi(caret, 0, text.length())
	start = visible_start(font, text, caret, size, inner, start)
	var shown: String = text.substr(start)
	while not shown.is_empty() and font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > inner:
		shown = shown.left(-1)
	var at := Vector2(box.position.x + FIELD_INSET, floorf(box.position.y + (box.size.y - Chrome.line_height(size)) / 2.0 + Chrome.ascent(size)))
	var cx: float = at.x + font.get_string_size(text.substr(start, caret - start), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	return {"size": size, "start": start, "shown": shown, "at": at, "caret_x": cx}


# Where a click at `x` puts the caret in a field laid out with the caret at `caret`: the gap between
# two letters nearest the click, among the letters on show.
static func caret_from_click(font: Font, box: Rect2, text: String, caret: int, x: float, scrolled: int = -1) -> int:
	var lay: Dictionary = field_layout(font, box, text, caret, scrolled)
	var size: int = int(lay["size"])
	var start: int = int(lay["start"])
	var left: float = (lay["at"] as Vector2).x
	var best: int = start
	var best_d: float = absf(x - left)
	for n in range(1, String(lay["shown"]).length() + 1):
		var gap_x: float = left + font.get_string_size(text.substr(start, n), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if absf(x - gap_x) < best_d:
			best_d = absf(x - gap_x)
			best = start + n
	return best


# The first character the field shows. With no earlier scroll, 0 while everything up to the caret
# fits, else as far along as it takes for the caret to be inside the well. With one (`from`), that
# start is kept while the caret is on show: back to the caret when it moved left of it, on as far
# as the caret needs when it moved right of the well, and back as far as the letters allow when
# deleting left room at the end.
static func visible_start(font: Font, text: String, caret: int, size: int, inner: float, from: int = -1) -> int:
	var room: float = inner - CARET_W
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= room:
		return 0
	var start: int = clampi(from, 0, caret)
	while start < caret and font.get_string_size(text.substr(start, caret - start), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > room:
		start += 1
	while start > 0 and font.get_string_size(text.substr(start - 1), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= room:
		start -= 1
	return start


static func _band_colour(band: String) -> Color:
	match band:
		"sound":
			return Locker.GOOD
		"broken", "barely holding":
			return Locker.DANGER_INK
		_:
			return Locker.ACCENT


# The state word's colour, on the condition's scale: at its best reads calm, spent reads as the
# warning it is, and everything between is the accent. A barrel's words are a description, not a
# condition, so they read as plain text rather than as the amber that means "fits" on the bench.
static func _state_colour(word: String, label: String = "") -> Color:
	if label == "barrel":
		return Locker.TEXT
	match word:
		"keen", "burning well":
			return Locker.GOOD
		"dull", "dark", "empty":
			return Locker.DANGER_INK
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
