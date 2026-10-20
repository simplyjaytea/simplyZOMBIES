extends Control
# The shared navigation frame: one bar across the top of the three screens that are about people
# rather than the street -- Survivor (Tab), Colony (J) and Skills (K) -- in the Salvage Locker's
# steel, so moving between them reads as turning a page in one binder rather than opening three
# different programs (docs/32, "Navigation and layout"; docs/23's UI overhaul group, first slice).
#
# What the bar says, left to right: the three tabs, the one in front lit, each with the key that
# reaches it; then **whose** screen this is -- the person's name and a stamp that says whether it
# is you or somebody you are only looking at; then, at the far end, how to put it away. The stamp
# is the brief's "clearly distinguish the controlled survivor from the person being viewed": a
# colonist selected on the street keeps their name on the Skills page, and the amber "viewing"
# stamp says that what you do on that page is done to them, not to you.
#
# Two ways in. The inventory sheet draws the bar into its own title strip (`draw_bar`, static), so
# the sheet's notice and hint line can sit in the room the bar leaves; and main.gd adds one
# instance of this Control over the Colony and Skills screens, which have no title strip of their
# own. Both report a click on a tab the same way -- `navigate(screen)` -- and main.gd's
# `_show_screen` is the one place a screen is opened or closed, by key or by click.
#
# Nothing here reads the sim beyond a name: the subject is handed in by main.gd (`_who()` for
# Skills, the player for Survivor), and a screen with no one person in it -- Colony -- names none.

const Chrome = preload("res://ui/chrome.gd")
const Kit = preload("res://ui/kit.gd")
const Locker = preload("res://ui/locker.gd")
const UiText = preload("res://ui/text.gd")
const UiPrefs = preload("res://ui/prefs.gd")

signal navigate(screen: String)

# The tabs, in the order they stand. `key` is the key that reaches the screen, as `input_map.gd`'s
# BINDINGS names it; `godot:check:play`'s NAV lane presses each one and reads which screen is up.
const TABS: Array[Dictionary] = [
	{"screen": "survivor", "word": "survivor", "key": "Tab"},
	{"screen": "colony", "word": "colony", "key": "J"},
	{"screen": "skills", "word": "skills", "key": "K"},
]
const CLOSE_WORD: String = "close"
const CLOSE_KEY: String = "Esc"
const YOU_WORD: String = "you"
const VIEWING_WORD: String = "viewing"
const COLONY_WORD: String = "everyone"

# The bar's own geometry: the same box the inventory's title strip has always had, so the sheet's
# columns below it do not move.
const MARGIN: float = 16.0
const BAR_H: float = 56.0
const BAR_H_COMPACT: float = 48.0
# A window narrower or shorter than this is the compact one (the inventory sheet's own rule).
const FULL_WIDTH: float = 1600.0
const FULL_HEIGHT: float = 900.0
# Text, from the ladder (`Chrome.LADDER`): the tab words a rung down on the compact window.
const WORD_SIZE: int = 30
const WORD_SIZE_COMPACT: int = 25
const NAME_TEXT: int = 25
const CAP_TEXT: int = 20

var screen: String = ""
var subject_name: String = ""
var subject_is_you: bool = true



static func compact_for(view: Vector2) -> bool:
	return view.x < FULL_WIDTH or view.y < FULL_HEIGHT


static func rect_for(view: Vector2) -> Rect2:
	return Rect2(Vector2(MARGIN, MARGIN), Vector2(view.x - MARGIN * 2.0, BAR_H_COMPACT if compact_for(view) else BAR_H))


# Where everything on a bar at `rect` goes, without drawing it: {tabs: [{rect, screen, word, key}],
# close: Rect2 (the keycap, the glyph and the word, clickable as one), cap_at, glyph_at, word_at,
# name: the name as it fits, name_at, stamp, stamp_rect (empty when there is no room), left/right:
# the free room after the stamp that a screen may write its own line into}. Pure: the draw and the
# click both come from here, so a click lands on what was drawn even before the first frame.
static func layout(rect: Rect2, active: String, who: String, is_you: bool, compact: bool) -> Dictionary:
	var font: Font = Chrome.font()
	var p: float = Locker.PX
	var tabs: Array[Dictionary] = tab_rects(rect, compact)
	var x: float = (tabs[tabs.size() - 1]["rect"] as Rect2).end.x + p * 8.0 if not tabs.is_empty() else rect.position.x + p * 6.0
	var mid: float = rect.position.y + rect.size.y / 2.0
	var base: float = floorf(mid - Chrome.line_height(NAME_TEXT) / 2.0 + Chrome.ascent(NAME_TEXT))

	# From the right: the close control -- its keycap, the kit's close glyph and the word.
	var right: float = rect.end.x - p * 6.0
	var cw: float = font.get_string_size(CLOSE_WORD, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_TEXT).x
	var cap: Vector2 = cap_extent(CLOSE_KEY)
	var glyph_x: float = right - cw - p * 2.0 - Chrome.GLYPH_SMALL
	var close_left: float = glyph_x - p * 3.0 - cap.x
	var close := Rect2(Vector2(close_left - p * 2.0, rect.position.y + p * 2.0), Vector2(right - close_left + p * 4.0, rect.size.y - p * 4.0))
	var out: Dictionary = {
		"tabs": tabs,
		"close": close,
		"cap_at": Vector2(close_left, roundf(mid - cap.y / 2.0)),
		"glyph_at": Vector2(glyph_x, roundf(mid - Chrome.GLYPH_SMALL / 2.0)),
		"word_at": Vector2(right - cw, base),
	}
	right = close.position.x - p * 6.0

	# Whose screen: the name, then the stamp. A screen about the colony names nobody; a survivor the
	# roster never named is only "you".
	var stamp: String = COLONY_WORD if active == "colony" else (YOU_WORD if is_you else VIEWING_WORD)
	var sw: float = Locker.label_width(stamp, Locker.SMALL_SIZE)
	var shown: String = UiText.fit(font, who, NAME_TEXT, maxf(0.0, right - x - sw - p * 4.0)) if not who.is_empty() and active != "colony" else ""
	out["name"] = shown
	out["name_at"] = Vector2(x, base)
	if not shown.is_empty():
		x += font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_TEXT).x + p * 4.0
	out["stamp"] = stamp
	out["stamp_rect"] = Rect2()
	if x + sw <= right:
		var sh: float = p * 10.0
		out["stamp_rect"] = Rect2(Vector2(x, roundf(mid - sh / 2.0)), Vector2(sw, sh))
		x += sw + p * 6.0
	out["left"] = x
	out["right"] = right
	return out


# The bar into `rect` on `ci`, as `layout` places it. Returns that layout, so the caller tests a
# click against exactly what was drawn.
static func draw_bar(ci: CanvasItem, rect: Rect2, active: String, who: String, is_you: bool, alpha: float, compact: bool) -> Dictionary:
	var font: Font = Chrome.font()
	var laid: Dictionary = layout(rect, active, who, is_you, compact)
	Locker.panel(ci, rect, alpha, false)
	var word_size: int = WORD_SIZE_COMPACT if compact else WORD_SIZE
	for t in laid["tabs"] as Array:
		var d: Dictionary = t as Dictionary
		_draw_tab(ci, d["rect"] as Rect2, String(d["word"]), String(d["key"]), String(d["screen"]) == active, word_size, alpha)
	Chrome.keycap(ci, laid["cap_at"] as Vector2, CLOSE_KEY, CAP_TEXT, alpha)
	Chrome.glyph(ci, "close", laid["glyph_at"] as Vector2, true, alpha * 0.8)
	ci.draw_string(font, laid["word_at"] as Vector2, CLOSE_WORD, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_TEXT, Locker._a(Locker.TEXT_DIM, alpha))
	if not String(laid["name"]).is_empty():
		ci.draw_string(font, laid["name_at"] as Vector2, String(laid["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_TEXT, Locker._a(Locker.TEXT, alpha))
	var stamp_rect: Rect2 = laid["stamp_rect"] as Rect2
	if stamp_rect.has_area():
		# Amber when the person on this page is not you: what you do here lands on them.
		Locker.chip(ci, stamp_rect, String(laid["stamp"]), String(laid["stamp"]) == VIEWING_WORD, alpha)
	return laid


# Where each tab stands in a bar at `rect`: left to right from the bar's start, each as wide as its
# word and keycap need. Pure, so a gate can ask where the Colony tab is without drawing anything.
static func tab_rects(rect: Rect2, compact: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var font: Font = Chrome.font()
	var p: float = Locker.PX
	var word_size: int = WORD_SIZE_COMPACT if compact else WORD_SIZE
	var x: float = rect.position.x + p * 3.0
	for t in TABS:
		var word: String = String(t["word"]).to_upper()
		var ww: float = font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, word_size).x
		var w: float = ceilf((ww + cap_extent(String(t["key"])).x + p * 13.0) / p) * p
		var r := Rect2(Vector2(x, rect.position.y + p * 2.0), Vector2(w, rect.size.y - p * 4.0))
		out.append({"rect": r, "screen": String(t["screen"]), "word": String(t["word"]), "key": String(t["key"])})
		x += w + p * 2.0
	return out


# A tab: the lit one is an amber-rimmed plate that stands proud; the others are recessed wells with
# dim words. The key that reaches it sits after the word in either case.
static func _draw_tab(ci: CanvasItem, r: Rect2, word: String, key: String, on: bool, word_size: int, alpha: float) -> void:
	var font: Font = Chrome.font()
	var p: float = Locker.PX
	if on:
		ci.draw_rect(r, Locker._a(Locker._shade(Locker.ACCENT, 0.3), alpha))
		ci.draw_rect(Rect2(r.position + Vector2(p, p), Vector2(r.size.x - p * 2.0, p)), Locker._a(Locker._shade(Locker.ACCENT, 0.55), alpha))
		ci.draw_rect(r, Locker._a(Locker.ACCENT, minf(1.0, alpha + 0.1)), false, p)
	else:
		Locker.well(ci, r, alpha)
	var text: String = word.to_upper()
	var mid: float = r.position.y + r.size.y / 2.0
	var base: float = floorf(mid - Chrome.line_height(word_size) / 2.0 + Chrome.ascent(word_size))
	var x: float = r.position.x + p * 5.0
	ci.draw_string(font, Vector2(x, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, word_size, Locker._a(Locker.TEXT if on else Locker.TEXT_DIM, alpha))
	x += font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, word_size).x + p * 3.0
	var cap: Vector2 = cap_extent(key)
	Chrome.keycap(ci, Vector2(x, roundf(mid - cap.y / 2.0)), key, CAP_TEXT, alpha if on else alpha * 0.7)


# How big `Chrome.keycap` draws `label` at the bar's cap size: its own arithmetic, measured ahead
# so a tab can be sized before it is drawn (hud.gd's `_cap_extent` makes the same measurement).
static func cap_extent(label: String) -> Vector2:
	var text_w: float = ceilf(Chrome.font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, CAP_TEXT).x)
	var m: Array[int] = Kit.margins("keycap")
	var pad: float = float(m[0]) + 4.0 if not m.is_empty() else 9.0
	var h: float = maxf(Chrome.KEYCAP_MIN, float(CAP_TEXT) + 8.0)
	return Vector2(maxf(h, text_w + pad * 2.0), h)


# What a press at `p` on a bar laid out as `laid` asks for: a screen's name, "" for the close
# control, or null when it missed the bar's controls.
static func hit(laid: Dictionary, p: Vector2) -> Variant:
	for t in laid.get("tabs", []) as Array:
		if ((t as Dictionary)["rect"] as Rect2).has_point(p):
			return String((t as Dictionary)["screen"])
	var close: Variant = laid.get("close", null)
	if close is Rect2 and (close as Rect2).has_point(p):
		return ""
	return null


# --- the instance over Colony and Skills -----------------------------------------------------------


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	get_viewport().size_changed.connect(_sync)
	_sync()


func _sync() -> void:
	var r: Rect2 = rect_for(get_viewport_rect().size)
	position = r.position
	size = r.size
	queue_redraw()


# What main.gd hands over when a screen opens or its subject changes.
func show_for(active: String, who: String, is_you: bool) -> void:
	screen = active
	subject_name = who
	subject_is_you = is_you
	_sync()


func _draw() -> void:
	var compact: bool = compact_for(get_viewport_rect().size)
	draw_bar(self, Rect2(Vector2.ZERO, size), screen, subject_name, subject_is_you, maxf(0.85, UiPrefs.opacity("inventory_opacity")), compact)


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	var asked: Variant = hit(layout(Rect2(Vector2.ZERO, size), screen, subject_name, subject_is_you, compact_for(get_viewport_rect().size)), mb.position)
	if asked == null:
		return
	# The tab already in front puts the screen away, the same as pressing its key again.
	navigate.emit("" if String(asked) == screen else String(asked))


# The street put behind glass while Colony or Skills is up: the inventory sheet's own wash
# (`Locker.WASH`), so all three screens about people sit on the same dark field and the world under
# them reads as paused attention rather than something still to click. Draws only; never takes the
# pointer. main.gd adds it under the two screens and shows it with the bar.
class Wash:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Locker.WASH)
