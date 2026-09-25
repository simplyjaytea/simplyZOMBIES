extends Control
# The keys, on screen, because "playable end to end without a developer explaining it" is
# Milestone 2's exit criterion and the bindings previously lived only in README.md.
#
# Shown on a fresh run and dismissed with any of F1, Escape, or Enter -- then it stays dismissed
# across boots, because a legend you cannot turn off is a legend you resent. The memory is
# `ui/prefs.gd`'s `legend_dismissed`, written by those three presses and read by `_ensure_ui`;
# the header used to promise this and nothing stored it, so every launch opened on the keys.
# F1 always brings it back.
#
# The key column here is one half of a pair: `presentation/input_map.gd`'s `BINDINGS` is the
# other, and `godot:check:play`'s KEYS lane reads them against each other both ways. A row added
# here for a key nothing binds is red, and a binding with no row here is red too -- which is why
# F8, the dev spawn menu, is not listed: it is bound only in a debug build, and a player is never
# told about a key they do not have.
#
# The groupings are the ones a new player needs in the order they need them: move first,
# fight second, look third, and the meta keys last.

const Chrome = preload("res://ui/chrome.gd")

const PAD: float = 36.0
const TITLE_GAP: float = 14.0
const GROUP_GAP: float = 14.0
const COLUMN_GAP: float = 48.0
# The widest the panel grows, and how far it stays in from the window's edges when the window is
# narrower or shorter than that.
const MAX_WIDTH: float = 1600.0
const EDGE: float = 24.0
# The key cell's width. A key wider than this -- the stance ladder's "Ctrl+Z / Ctrl+C / Ctrl+S /
# Ctrl+V" since the ladder moved onto Ctrl (docs/30, "The alpha shell, 2026-09-16") -- takes a
# line of its own with its words under it, rather than pushing every description in the column
# out to make room for one row. Measured in the row's own font; this is the cap, not a guess at it.
const KEY_COLUMN: float = 150.0
const KEY_INDENT: float = 20.0
# The two sizes from the ladder (ui/chrome.gd's LADDER): 25, pixel-exact, when the whole legend
# fits the window at it, and 20 when it does not. The keys are the one panel that must be read
# whole; a legend that spills off a 720-line window is a legend that lies by omission.
const FONT_SIZE: int = 25
const FONT_SIZE_TIGHT: int = 20

const GROUPS: Array = [
	["Move", [
		["WASD", "walk"],
		["Shift", "sprint — fast, and loud, latches while held"],
		["Ctrl+Z / Ctrl+C / Ctrl+S / Ctrl+V", "crawl, crouch, stand, jog"],
	]],
	["Act", [
		["Mouse", "aim — you turn to the cursor while standing; moving, you face where you go"],
		["Click", "attack: fires if a gun or bow is in hand, swings if not"],
		["Right-click", "what you can do with what is under the cursor — walk there, pick up, open, attack, first aid"],
		["F", "swing, or struggle out of a grab"],
		["H", "pull someone out of a grab"],
		["G", "fire"],
		["R", "reload"],
		["E", "interact — pick up, open a cupboard or a car boot, a car door or a bike from the side, its hood from the nose, fill its tank from a can you carry, or put what you are holding on a gunsmithing bench"],
		["T", "first aid — bandage if you have one, bare hands if not; again to stop"],
		["C", "make camp where you stand — home moves here, and it takes a while and makes noise; shift+C to strike it"],
		["1 … 6", "use what is on your belt and in your pockets"],
		["Space", "shout — heard across the district"],
	]],
	["Look", [
		["Tab", "gear and injuries — drag between bags, right-click a thing for what you can do"],
		["J", "work priorities"],
		["K", "the skill web — what they know, what they could learn, and the shape of it, for whoever you have selected"],
		["O", "attention overlay: noise, scent, sight, light"],
		["M", "raw developer sheets"],
		["Wheel", "zoom"],
	]],
	["Run", [
		["- / =", "slower, faster"],
		["P", "pause"],
		["F5 / F9", "save and load"],
		["Esc", "menu — resume, save, load, settings, or back to the title"],
		["F1", "these keys"],
	]],
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var font: Font = Chrome.font()
	# The viewport rect, not `size`: a Control parented to a CanvasLayer keeps a zero-sized
	# rect, so centring against `size` puts the panel off the top-left of the screen.
	var view: Vector2 = get_viewport_rect().size
	var width: float = minf(MAX_WIDTH, view.x - EDGE * 2.0)
	# Two columns, filled in reading order -- move, act, look, run -- and broken where the halves
	# come out nearest even, so a long group can run on at the top of the second column.
	var font_size: int = FONT_SIZE
	var lines: Array = []
	var height: float = 0.0
	for candidate in [FONT_SIZE, FONT_SIZE_TIGHT]:
		font_size = int(candidate)
		lines = _layout(font, font_size, _column_width(width))
		height = _panel_height(lines, font_size)
		if height <= view.y - EDGE * 2.0:
			break
	var origin := Vector2(
		roundf((view.x - width) / 2.0),
		roundf(maxf(EDGE, (view.y - height) / 2.0)),
	)

	# Dim the district behind, so the legend reads as a layer over the game rather than as
	# part of it. Panel chrome comes from ui/chrome.gd, the one place the skin lives.
	var dim: Color = Chrome.FIELD
	dim.a = 0.72
	draw_rect(Rect2(Vector2.ZERO, view), dim)
	var panel := Rect2(origin, Vector2(width, height))
	Chrome.panel(self, panel, 0.97)
	Chrome.header(self, panel, "keys", 0.97, "journal")
	var hint: String = "F1 to close"
	var hint_w: float = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, Chrome.FONT_SIZE).x
	draw_string(font, Vector2(origin.x + width - PAD - hint_w, origin.y + Chrome.header_baseline()), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, Chrome.FONT_SIZE, Chrome.TEXT_DIM)

	var col_w: float = _column_width(width)
	var ascent: float = Chrome.ascent(font_size)
	var top: float = origin.y + Chrome.HEADER_H + TITLE_GAP
	for entry in lines:
		var e: Dictionary = entry as Dictionary
		var x: float = origin.x + PAD + float(e["col"]) * (col_w + COLUMN_GAP)
		var y: float = top + float(e["y"]) + ascent
		match String(e["kind"]):
			"group":
				draw_string(font, Vector2(x, y), String(e["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Chrome.TEXT_DIM)
			"key":
				draw_string(font, Vector2(x + KEY_INDENT, y), String(e["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Chrome.ACCENT)
			_:
				draw_string(font, Vector2(x + KEY_INDENT + _key_column(font_size), y), String(e["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Chrome.TEXT)


func _line_height(font_size: int) -> float:
	return roundf(float(font_size) * 1.1)


# The key cell at this size: KEY_COLUMN is the 25 px figure, and the cell shrinks with the text.
func _key_column(font_size: int) -> float:
	return roundf(KEY_COLUMN * float(font_size) / float(FONT_SIZE))


func _column_width(width: float) -> float:
	return floorf((width - PAD * 2.0 - COLUMN_GAP) / 2.0)


func _panel_height(lines: Array, font_size: int) -> float:
	var tallest: float = 0.0
	for entry in lines:
		tallest = maxf(tallest, float((entry as Dictionary)["y"]) + _line_height(font_size))
	return Chrome.HEADER_H + TITLE_GAP + tallest + PAD


# Every line the legend draws, as {kind: group|key|words, text, col, y}: the groups' names, each
# key, and each key's words wrapped to the column. Built as one list in reading order, then split
# into two columns at whichever key leaves the taller column shortest -- never inside a key's words.
func _layout(font: Font, font_size: int, col_w: float) -> Array:
	var line_h: float = _line_height(font_size)
	var key_col: float = _key_column(font_size)
	var words_w: float = col_w - KEY_INDENT - key_col
	# Blocks: a key with its wrapped words, and how many lines it takes. A group's heading rides in
	# the block of its first key, so a heading can never be the last line of a column.
	var blocks: Array = []
	for g in GROUPS.size():
		var group: Array = GROUPS[g] as Array
		var rows: Array = group[1] as Array
		for k in rows.size():
			var r: Array = rows[k] as Array
			var key: String = String(r[0])
			var entry_lines: Array = []
			var dy: int = 0
			if k == 0:
				entry_lines.append({"kind": "group", "text": String(group[0]), "dy": 0})
				dy = 1
			entry_lines.append({"kind": "key", "text": key, "dy": dy})
			if font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > key_col - 12.0:
				dy += 1
			for w in _wrap(font, String(r[1]), font_size, words_w):
				entry_lines.append({"kind": "words", "text": w, "dy": dy})
				dy += 1
			blocks.append({"lines": entry_lines, "gap": k == 0 and g > 0, "group": String(group[0])})
	var best: Array = []
	var best_h: float = INF
	for split in range(1, blocks.size()):
		var placed: Array = _place(blocks, split, line_h)
		var h: float = 0.0
		for entry in placed:
			h = maxf(h, float((entry as Dictionary)["y"]))
		if h < best_h:
			best_h = h
			best = placed
	return best


# The blocks laid out with column two starting at block `split`.
func _place(blocks: Array, split: int, line_h: float) -> Array:
	var out: Array = []
	var col: int = 0
	var y: float = 0.0
	for i in blocks.size():
		var b: Dictionary = blocks[i] as Dictionary
		if i == split:
			col = 1
			y = 0.0
			# A group the break cut in two says whose keys these still are.
			if String(((b["lines"] as Array)[0] as Dictionary)["kind"]) != "group":
				out.append({"kind": "group", "text": String(b["group"]), "col": col, "y": y})
				y += line_h
		elif bool(b["gap"]) and y > 0.0:
			y += GROUP_GAP
		for l in b["lines"] as Array:
			var ld: Dictionary = l as Dictionary
			out.append({"kind": ld["kind"], "text": ld["text"], "col": col, "y": y + float(ld["dy"]) * line_h})
		y += _block_height(b, line_h)
	return out


func _block_height(b: Dictionary, line_h: float) -> float:
	var deepest: int = 0
	for l in b["lines"] as Array:
		deepest = maxi(deepest, int((l as Dictionary)["dy"]))
	return float(deepest + 1) * line_h


# Greedy word wrap to `max_width`, measured in the font that draws it.
static func _wrap(font: Font, text: String, font_size: int, max_width: float) -> Array[String]:
	var out: Array[String] = []
	var current: String = ""
	for word in text.split(" "):
		var candidate: String = word if current.is_empty() else current + " " + word
		if not current.is_empty() and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
			out.append(current)
			current = word
		else:
			current = candidate
	if not current.is_empty():
		out.append(current)
	return out
