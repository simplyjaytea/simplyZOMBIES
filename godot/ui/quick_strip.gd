extends RefCounted
# The belt and the pockets, along the bottom, with the six keys that reach them.
#
# The numerals on it are key names, not measurements: docs/01 clause 4 bans a UI that collapses
# uncertainty into a number, and "press 3" collapses nothing. The stack tally beside a name is
# allowed for docs/10's reason -- counting discrete objects is not uncertainty being collapsed --
# and is the only other digit here.
#
# What the strip is *for* is the pinning this overhaul deleted. A pouch on your front was
# reachable mid-fight because its window could be pinned to the screen; now the six things on your
# belt and in your pockets are on screen always, and a number key spends one.

const Chrome = preload("res://ui/chrome.gd")
const UiText = preload("res://ui/text.gd")

const SLOTS: int = 6
const SLOT_W: float = 210.0
const SLOT_H: float = 62.0
const GAP: float = 12.0
const KEY_SIZE: int = 15
const NAME_SIZE: int = 18


static func draw_strip(ci: CanvasItem, rect: Rect2, rows: Array, alpha: float) -> void:
	Chrome.panel(ci, rect, alpha)
	var font: Font = Chrome.font()
	var lead: String = "belt and pockets"
	ci.draw_string(font, rect.position + Vector2(20.0, rect.size.y / 2.0 + 5.0), lead, HORIZONTAL_ALIGNMENT_LEFT, -1, KEY_SIZE, Chrome.TEXT_DIM)
	var x: float = rect.position.x + 20.0 + font.get_string_size(lead, HORIZONTAL_ALIGNMENT_LEFT, -1, KEY_SIZE).x + 24.0
	var y: float = rect.position.y + (rect.size.y - SLOT_H) / 2.0
	for i in SLOTS:
		var box := Rect2(Vector2(x, y), Vector2(SLOT_W, SLOT_H))
		var bg: Color = Chrome.SLOT_EMPTY
		bg.a = alpha
		ci.draw_rect(box, bg)
		var edge: Color = Chrome.PANEL_EDGE
		edge.a = alpha
		ci.draw_rect(box, edge, false, 2.0)
		var key: Color = Chrome.ACCENT
		key.a = alpha
		ci.draw_string(font, box.position + Vector2(10.0, SLOT_H / 2.0 + 6.0), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, KEY_SIZE, key)
		if i < rows.size():
			var d: Dictionary = rows[i] as Dictionary
			var text: String = String(d.get("name", ""))
			var count: int = int(d.get("count", 1))
			var col: Color = Chrome.TEXT
			col.a = alpha
			var wide: float = SLOT_W - 44.0
			if count > 1:
				var tally: String = "x%d" % count
				var tw: float = font.get_string_size(tally, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x
				var tcol: Color = Chrome.ACCENT
				tcol.a = alpha
				ci.draw_string(font, box.position + Vector2(SLOT_W - tw - 10.0, SLOT_H / 2.0 + 6.0), tally, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE, tcol)
				wide -= tw + 8.0
			ci.draw_string(font, box.position + Vector2(32.0, SLOT_H / 2.0 + 6.0), UiText.fit(font, text, NAME_SIZE, wide), HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE, col)
		else:
			var dim: Color = Chrome.TEXT_DIM
			dim.a = alpha
			ci.draw_string(font, box.position + Vector2(32.0, SLOT_H / 2.0 + 6.0), "empty", HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE, dim)
		x += SLOT_W + GAP


# Where the strip sits: full width along the bottom, above the margin.
static func rect_for(view: Vector2, pad: float, height: float) -> Rect2:
	return Rect2(Vector2(pad, view.y - pad - height), Vector2(view.x - pad * 2.0, height))
