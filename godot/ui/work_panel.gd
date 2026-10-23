extends Control
# The Colony screen (J): the work grid, the roster it is drawn from, and the colonist picked on it.
# docs/32's coverage row: "Persistent identity, readable job groups, explicit priority controls
# and Focus choices; details open from the selected person." UI overhaul, slice 2.
#
# Three parts, top to bottom, in the Salvage Locker's steel like the sheet and the web:
#   - **the grid.** One row per colonist (the player is not a row, docs/07): their name, their
#     Focus as a stamp, and what they are doing now (`WorkRead.doing`). The job columns stand in
#     four groups -- care, home, build, field -- and a cell is a recessed well with the priority in
#     it. A left click counts it up (1, 2, 3, 4, never, 1), a right click counts it back down.
#   - **the drawer.** The picked colonist in full: their Focus as six chips you press, with what
#     that Focus puts first (read off the sim's own preset, so the sentence cannot drift from what
#     the colonist does); who they are, the whole clause wrapped rather than cut; what they know
#     and, when the learning is yours, what they could learn now, each a word you click; and a
#     button to their Skills.
#   - **the footer.** The six job names nothing does yet, named as such, so the grid does not
#     look like it is hiding work and the six are not mistaken for work anybody does.
#
# The grid is drawn only for the columns something does (`shown_columns`): a column it drew with
# nothing behind it would promise work nobody does. Its order is the groups', not the sim's
# COLUMNS order, and that is truthful because the job pick breaks a tie by the job's name
# (`SimJobs._pick`'s sort), never by column position.
#
# Focus is chosen here, and it is the same act as choosing who manages a survivor's skill web.
# docs/07: "Setting Focus to Manual gives full control of that one survivor's web and inventory",
# and every other Focus auto-allocates. So there is deliberately no second toggle: "manual" is
# the value that says the learning is in your hands. A number changed by hand is a Manual row
# (`SimJobs.set_priority` flips it), and the legend says so.
#
# One layout (`_layout`) serves the draw, the clicks and the gates, so what is drawn and what a
# click lands on cannot drift apart.

const SimJobs = preload("res://sim/modules/jobs.gd")
const SimSkills = preload("res://sim/modules/skills.gd")
const SimSurvivors = preload("res://sim/modules/survivors.gd")
const WorkRead = preload("res://sim/work_read.gd")
const UiText = preload("res://ui/text.gd")
const Chrome = preload("res://ui/chrome.gd")
const Locker = preload("res://ui/locker.gd")
const NavBar = preload("res://ui/nav_bar.gd")

# Asks main.gd to make `entity` the person the screens are about (the bar, the HUD, Skills).
signal picked(entity: int)
# Asks main.gd to bring a screen forward, the bar's own signal: the drawer's Skills button.
signal navigate(screen: String)

const PX: float = Locker.PX
# The job groups, left to right, and the columns in each. Display only (see the header). A column
# with a consumer that no group names still shows, in a last group of its own, so a job added to
# the sim can never be hidden by this table.
const GROUPS: Array[Dictionary] = [
	{"word": "care", "columns": ["Patient", "Doctor", "Rest"]},
	{"word": "home", "columns": ["Cook", "Water", "Clean"]},
	{"word": "build", "columns": ["Construct", "Repair", "Haul"]},
	{"word": "field", "columns": ["Scavenge", "Guard", "Bury"]},
]
const OTHER_GROUP: String = "other"

# Grid geometry. Each column is as wide as its own head plus COL_GAP (never under COL_MIN), groups
# stand GROUP_GAP apart, and the grid sits against the panel's right gutter, so the room the
# columns do not need goes to the names. GRID_X is the floor for that name area; below it the
# columns share what is left equally.
const COL_MIN: float = 48.0
const COL_GAP: float = 20.0
const GROUP_GAP: float = 12.0
const GRID_X: float = 220.0
# The top of the first row band. Above it: the tape (Locker.HEAD_H), the group words and their
# groove, the column heads.
const GRID_Y: float = 92.0
const GROUP_BASE: float = 56.0
const HEAD_BASE: float = 84.0
# A row is two lines -- the name and its Focus stamp, then what they are doing now -- and the same
# height for every row, so the click math is one divide.
const ROW_H: float = 64.0
const NAME_DY: float = 26.0
const NOW_DY: float = 52.0
const WELL: Vector2 = Vector2(40.0, 30.0)
const WELL_DY: float = 6.0
const GUTTER: float = 24.0
# The panel's widest, centred beyond it: on a wide window the names and the grid are not a room
# apart.
const MAX_W: float = 1440.0
const MARGIN: float = 16.0
# Text. VT323 is pixel-exact at 25 (ui/chrome.gd), so every line here is 25; the column heads
# take the ladder's 20 only where twelve heads at 25 do not fit the window (`head_size`).
const TEXT_SIZE: int = 25
const SMALL_SIZE: int = 20
const LINE: float = 26.0
# The most lines a drawer block may wrap to; past them a block is cut, marked. The drawer is as
# tall as the longest block among the rows needs (`_sync_layout`), so picking another colonist
# never moves the grid, and each block is laid out by the lines it uses, so no blank line sits
# between two blocks.
const FOCUS_LINES: int = 2
const WHO_LINES: int = 6
const LEARN_LINES: int = 3
const CHIP_H: float = 28.0
# The drawer is a dossier: a word down the left for each block, the block beside it.
const LABEL_W: float = 104.0
const FOOT_H: float = 36.0
# The strip under the rows that says how many more there are, only while some are scrolled away.
const MORE_H: float = 26.0

# The five self-managing focuses and the one that is not, in the order the drawer's chips stand.
# Auto first because it is the handback (jobs.gd stamps it "auto"), Manual last.
const FOCUS_CYCLE: Array[String] = ["Auto", "Fighter", "Worker", "Medic", "Scout", "Manual"]

const NOW_LEAD: String = "now "
const LEGEND: String = "1 first · 4 last · – never · click counts up, right-click down · a changed number makes the row manual"

var _world: Variant = null
var _rows: Array[Dictionary] = []
var _row_scroll: int = 0
# The colonist the drawer is about, by entity: main.gd's selection when that is a row, else -1 and
# the drawer asks for a click. A click on a name picks them for the game, so the two never differ.
var _selected: int = -1
# The lines the drawer gives each block, the most any row needs (see FOCUS_LINES).
var _block_lines: Vector3i = Vector3i(1, 1, 1)
# The Focus chip under the mouse, whose sentence the drawer shows while it is pointed at; "" for none.
var _hover_focus: String = ""
# The size the column heads were drawn at, for the gate (25, or 20 where 25 does not fit).
var head_size: int = TEXT_SIZE
# What the last draw put on screen, for the gates: {entity: {"now": String}} per drawn row, and the
# drawer's wrapped "who" lines. Derived every draw, never read back by the panel.
var drawn: Dictionary = {}


# The columns this grid draws, in display order: every grouped column that has a consumer, then any
# consumer no group names. The six with no consumer (Firefight, Hunt, Farm, Craft, Modify, Butcher)
# are not drawn (alpha plan A15) and are named in the footer instead.
static func shown_columns() -> Array[String]:
	var shown: Array[String] = []
	for g in groups():
		for c in (g["columns"] as Array):
			shown.append(String(c))
	return shown


# The groups as drawn: GROUPS less any column without a consumer, and a last group for any consumer
# no group names.
static func groups() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var named: Dictionary = {}
	for g in GROUPS:
		var cols: Array[String] = []
		for c in (g["columns"] as Array):
			named[String(c)] = true
			if SimJobs.CONSUMERS.has(c):
				cols.append(String(c))
		if not cols.is_empty():
			out.append({"word": String(g["word"]), "columns": cols})
	var rest: Array[String] = []
	for c in SimJobs.COLUMNS:
		if SimJobs.CONSUMERS.has(c) and not named.has(c):
			rest.append(c)
	if not rest.is_empty():
		out.append({"word": OTHER_GROUP, "columns": rest})
	return out


# The job names the sim stores and nothing does, in the sim's order.
static func unworked_columns() -> Array[String]:
	var out: Array[String] = []
	for c in SimJobs.COLUMNS:
		if not SimJobs.CONSUMERS.has(c):
			out.append(c)
	return out


# What a Focus puts first, read off `SimJobs.preset`: the jobs in priority order, a tier at a time,
# with ties in the pick's own order (by name), and whether they learn on their own.
static func focus_sentence(focus: String) -> String:
	if focus == "Manual":
		return "manual: the row is yours, and so is what they learn"
	var row: Dictionary = SimJobs.preset(focus)
	var tiers: Dictionary = {}
	for c in SimJobs.CONSUMERS:
		var p: int = int(row.get(c, 0))
		if p > 0:
			if not tiers.has(p):
				tiers[p] = []
			(tiers[p] as Array).append(String(c).to_lower())
	var keys: Array = tiers.keys()
	keys.sort()
	var parts: PackedStringArray = []
	if keys.size() == 1:
		parts.append("puts every job alike")
	else:
		for i in keys.size():
			var names: Array = tiers[keys[i]] as Array
			names.sort()
			var said: String = _and_list(names)
			if i == 0:
				parts.append("puts " + said + " first")
			elif i == keys.size() - 1 and keys.size() > 2:
				parts.append(said + " last")
			else:
				parts.append("then " + said)
	return focus.to_lower() + " " + ", ".join(parts) + " · they choose what to learn"


# Does `row` (a work_view row) hold exactly what its Focus's preset puts? Auto always does (the
# pick re-lays the preset); an authored row or a hand-edited one may not, and then the drawer does
# not describe the row by a preset it no longer matches.
static func row_is_preset(row: Dictionary) -> bool:
	var focus: String = String(row.get("focus", "Auto"))
	if focus == "Manual":
		return true
	var preset: Dictionary = SimJobs.preset(focus)
	var cols: Dictionary = row.get("cols", {}) as Dictionary
	for c in SimJobs.CONSUMERS:
		if c == "Patient" and focus == "Auto":
			continue
		if int(cols.get(c, 0)) != int(preset.get(c, 0)):
			return false
	return true


# The drawer's Focus line: the pointed-at chip's sentence, else the row's own focus -- by its preset
# when the row is that preset, and plainly as a row of their own when it is not.
func focus_line() -> String:
	if not _hover_focus.is_empty():
		return focus_sentence(_hover_focus)
	var sel: int = _row_of(_selected)
	if sel < 0:
		return ""
	var row: Dictionary = _rows[sel]
	var focus: String = String(row.get("focus", "Auto"))
	if row_is_preset(row):
		return focus_sentence(focus)
	return "%s, with a row of their own · point at a focus to see what it puts first" % focus.to_lower()


static func _and_list(names: Array) -> String:
	if names.size() <= 1:
		return "" if names.is_empty() else String(names[0])
	var head: PackedStringArray = []
	for i in names.size() - 1:
		head.append(String(names[i]))
	return ", ".join(head) + " and " + String(names[names.size() - 1])


func _ready() -> void:
	get_viewport().size_changed.connect(_sync_layout)
	_sync_layout()


func set_world(world: Variant, who: int = -1) -> void:
	_world = world
	_rows = SimJobs.work_view(world) if world != null else []
	# The pick is the game's: whoever main has picked, or nobody when that is the player, so the bar
	# and the drawer always name the same person.
	_selected = who if _row_of(who) >= 0 else -1
	_sync_layout()
	_scroll_to(_selected)


func selected() -> int:
	return _selected


# Scroll the roster just far enough that `entity`'s row is drawn: a colonist picked in the street
# past the visible rows still gets their bracket.
func _scroll_to(entity: int) -> void:
	var i: int = _row_of(entity)
	if i < 0:
		return
	var vis: int = _visible_rows()
	if i < _row_scroll:
		_row_scroll = i
	elif i >= _row_scroll + vis:
		_row_scroll = i - vis + 1
	_row_scroll = clampi(_row_scroll, 0, maxi(0, _rows.size() - vis))


# Whether the roster is longer than the rows drawn, so the more strip stands under them.
func _overflows() -> bool:
	return _rows.size() > _visible_rows()


# "3 more below · wheel", "2 above · 3 below · wheel", "5 above · wheel", or "" when all are shown.
func more_line() -> String:
	if not _overflows():
		return ""
	var above: int = _row_scroll
	var below: int = maxi(0, _rows.size() - _row_scroll - _visible_rows())
	if above == 0:
		return "%d more below · wheel" % below
	if below == 0:
		return "%d above · wheel" % above
	return "%d above · %d below · wheel" % [above, below]


func _row_of(entity: int) -> int:
	for i in _rows.size():
		if int(_rows[i].get("entity", -1)) == entity:
			return i
	return -1


func _drawer_h() -> float:
	return PX * 4.0 + LINE + PX * 4.0 + CHIP_H + PX * 4.0 + LINE * float(_block_lines.x + _block_lines.y + _block_lines.z) + PX * 4.0


# The drawer's text width at the panel's current size.
func _inner() -> float:
	return size.x - GUTTER * 2.0 - LABEL_W


# The most lines each drawer block needs over every row, every Focus sentence a chip can show and
# the "row of their own" line: the drawer's height, so it holds still while you pick and point.
func _measure_blocks() -> void:
	var font: Font = Chrome.font()
	var inner: float = _inner()
	var f: int = 1
	var lines: Array[String] = ["%s, with a row of their own · point at a focus to see what it puts first" % "fighter"]
	for focus in FOCUS_CYCLE:
		lines.append(focus_sentence(focus))
	for t in lines:
		f = maxi(f, wrap_text(font, t, TEXT_SIZE, inner, FOCUS_LINES).size())
	var w: int = 1
	var l: int = 1
	for i in _rows.size():
		w = maxi(w, wrap_text(font, _clause_of(i), TEXT_SIZE, inner, WHO_LINES).size())
		var runs: Array[Dictionary] = _learning_runs(font, Vector2.ZERO, inner, int(_rows[i].get("entity", -1)), String(_rows[i].get("focus", "Auto")))
		var used: int = 1
		for r in runs:
			used = maxi(used, int(roundf(((r as Dictionary)["at"] as Vector2).y / LINE)) + 1)
		l = maxi(l, used)
	_block_lines = Vector3i(f, w, l)


# Who the colonist on row `i` is: the sim's clause less its leading name, which the drawer's
# heading already says.
func _clause_of(i: int) -> String:
	if _world == null or i < 0 or i >= _rows.size():
		return ""
	var clause: String = SimSurvivors.person_clause(_world, int(_rows[i].get("entity", -1)))
	var lead: String = String(_rows[i].get("name", "?")) + ", "
	if clause.begins_with(lead):
		clause = clause.substr(lead.length())
		clause = clause.substr(0, 1).to_upper() + clause.substr(1)
	return clause


func _sync_layout() -> void:
	var view: Vector2 = get_viewport_rect().size
	var top: float = NavBar.rect_for(view).end.y + MARGIN
	var w: float = floorf(minf(MAX_W, view.x - MARGIN * 2.0) / 2.0) * 2.0
	if size.x != w:
		size.x = w
	_measure_blocks()
	var room: float = view.y - top - MARGIN
	var fixed: float = GRID_Y + _drawer_h() + FOOT_H
	var fits: int = maxi(1, floori((room - fixed) / ROW_H))
	if _rows.size() > fits:
		fixed += MORE_H
		fits = maxi(1, floori((room - fixed) / ROW_H))
	var shown_rows: int = clampi(_rows.size(), 1, fits)
	size = Vector2(w, floorf(minf(room, fixed + ROW_H * float(shown_rows)) / 2.0) * 2.0)
	position = Vector2(floorf((view.x - w) / 4.0) * 2.0, top)
	queue_redraw()


# The room the "now" phrase has on a row: from after "now " to the grid, less a gap.
func now_room() -> float:
	var lw: float = Chrome.font().get_string_size(NOW_LEAD, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x
	return _column_edges()[0] - GUTTER - PX * 8.0 - lw


func _visible_rows() -> int:
	var room: float = size.y - GRID_Y - _drawer_h() - FOOT_H
	var fits: int = maxi(1, floori(room / ROW_H))
	if _rows.size() > fits:
		fits = maxi(1, floori((room - MORE_H) / ROW_H))
	return fits


# The left edge of every shown column, plus one more entry for the grid's right edge, in whole even
# pixels; group gaps sit between the last column of one group and the first of the next. Shared by
# the draw and the clicks.
func _column_edges() -> Array[float]:
	var font: Font = Chrome.font()
	var gs: Array[Dictionary] = groups()
	var room: float = size.x - GUTTER - GRID_X
	var gaps: float = GROUP_GAP * float(maxi(0, gs.size() - 1))
	head_size = TEXT_SIZE
	var widths: Array[float] = _widths(font, TEXT_SIZE)
	if _sum(widths) + gaps > room:
		head_size = SMALL_SIZE
		widths = _widths(font, SMALL_SIZE)
	if _sum(widths) + gaps > room and not widths.is_empty():
		var each: float = floorf((room - gaps) / float(widths.size()) / 2.0) * 2.0
		for i in widths.size():
			widths[i] = each
	var x: float = floorf((size.x - GUTTER - _sum(widths) - gaps) / 2.0) * 2.0
	var edges: Array[float] = []
	var i: int = 0
	for g in gs.size():
		if g > 0:
			x += GROUP_GAP
		for c in (gs[g]["columns"] as Array):
			edges.append(x)
			x += widths[i]
			i += 1
	edges.append(x)
	return edges


func _widths(font: Font, at: int) -> Array[float]:
	var out: Array[float] = []
	for c in shown_columns():
		var w: float = maxf(COL_MIN, font.get_string_size(c, HORIZONTAL_ALIGNMENT_LEFT, -1, at).x + COL_GAP)
		out.append(ceilf(w / 2.0) * 2.0)
	return out


func _sum(a: Array[float]) -> float:
	var t: float = 0.0
	for v in a:
		t += v
	return t


# Each column's right edge as drawn: the next column's left edge, less the group gap where a group
# ends there.
func _column_end(edges: Array[float], i: int) -> float:
	var end: float = edges[i + 1]
	if i + 1 < edges.size() - 1 and _group_starts().has(i + 1):
		end -= GROUP_GAP
	return end


func _group_starts() -> Dictionary:
	var out: Dictionary = {}
	var i: int = 0
	for g in groups():
		out[i] = true
		i += (g["columns"] as Array).size()
	return out


func _column_at(x: float, edges: Array[float]) -> int:
	for i in edges.size() - 1:
		if x >= edges[i] and x < _column_end(edges, i):
			return i
	return -1


# Wrap `text` into lines no wider than `width` at `at`, breaking at spaces. At most `max_lines`;
# past them the last line is fitted with the ellipsis, so a cut is marked, never silent.
static func wrap_text(font: Font, text: String, at: int, width: float, max_lines: int) -> Array[String]:
	var lines: Array[String] = []
	if text.is_empty():
		return lines
	var line: String = ""
	var words: PackedStringArray = text.split(" ", false)
	var i: int = 0
	while i < words.size():
		var next: String = words[i] if line.is_empty() else line + " " + words[i]
		if line.is_empty() or font.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, at).x <= width:
			line = next
			i += 1
			continue
		if lines.size() == max_lines - 1:
			break
		lines.append(line)
		line = ""
	if i < words.size():
		var rest: PackedStringArray = words.slice(i)
		line = line + " " + " ".join(rest)
	lines.append(UiText.fit(font, line, at, width))
	return lines


# Where everything goes, without drawing: {edges, rows: [{entity, band, name_at, now_at, focus,
# focus_at, cells: [{rect, column}]}], drawer: Rect2, name_at, chips: [{rect, focus}], skills:
# Rect2, focus_lines, who_lines, learn: [{at, text, node}] , foot_at}. Pure but for `head_size`.
func _layout() -> Dictionary:
	var font: Font = Chrome.font()
	var edges: Array[float] = _column_edges()
	var columns: Array[String] = shown_columns()
	var out: Dictionary = {"edges": edges, "rows": []}
	_row_scroll = clampi(_row_scroll, 0, maxi(0, _rows.size() - _visible_rows()))
	var name_room: float = edges[0] - GUTTER - PX * 8.0
	for vr in mini(_rows.size(), _visible_rows()):
		var row: Dictionary = _rows[vr + _row_scroll]
		var top: float = GRID_Y + float(vr) * ROW_H
		var focus: String = String(row.get("focus", "Auto")).to_lower()
		var fw: float = Locker.label_width(focus, TEXT_SIZE)
		var cells: Array[Dictionary] = []
		for i in columns.size():
			var mid: float = (edges[i] + _column_end(edges, i)) / 2.0
			cells.append({"rect": Rect2(Vector2(floorf((mid - WELL.x / 2.0) / 2.0) * 2.0, top + WELL_DY), WELL), "column": columns[i]})
		out["rows"].append({
			"entity": int(row.get("entity", -1)),
			"band": Rect2(Vector2(PX * 4.0, top), Vector2(size.x - PX * 8.0, ROW_H)),
			"name": UiText.fit(font, String(row.get("name", "?")), TEXT_SIZE, name_room - fw - PX * 4.0),
			"name_at": Vector2(GUTTER, top + NAME_DY),
			"focus": focus,
			"focus_rect": Rect2(Vector2(edges[0] - PX * 8.0 - fw, top + WELL_DY), Vector2(fw, CHIP_H)),
			"now_at": Vector2(GUTTER, top + NOW_DY),
			"cells": cells,
		})
	var dt: float = GRID_Y + float(_visible_rows()) * ROW_H
	out["more_at"] = Vector2(GUTTER, dt + NAME_DY - PX * 4.0)
	if _overflows():
		dt += MORE_H
	out["drawer"] = Rect2(Vector2(PX * 4.0, dt), Vector2(size.x - PX * 8.0, _drawer_h()))
	var inner: float = _inner()
	var body_x: float = GUTTER + LABEL_W
	var y: float = dt + PX * 4.0
	out["name_at"] = Vector2(GUTTER, y + NAME_DY - PX * 2.0)
	var sk_label: String = "their skills"
	var sk_w: float = Locker.label_width(sk_label, TEXT_SIZE) + PX * 4.0
	out["skills"] = Rect2(Vector2(size.x - GUTTER - sk_w, y), Vector2(sk_w, CHIP_H))
	out["skills_label"] = sk_label
	y += LINE + PX * 4.0
	out["focus_label_at"] = Vector2(GUTTER, floorf(y + (CHIP_H - Chrome.line_height(TEXT_SIZE)) / 2.0 + Chrome.ascent(TEXT_SIZE)))
	var cx: float = body_x
	var chips: Array[Dictionary] = []
	for f in FOCUS_CYCLE:
		var cw: float = Locker.label_width(f.to_lower(), TEXT_SIZE)
		chips.append({"rect": Rect2(Vector2(cx, y), Vector2(cw, CHIP_H)), "focus": f})
		cx += cw + PX * 3.0
	out["chips"] = chips
	y += CHIP_H + PX * 4.0
	var sel: int = _row_of(_selected)
	var focus_now: String = String(_rows[sel].get("focus", "Auto")) if sel >= 0 else "Auto"
	out["focus_now"] = focus_now
	var focus_lines: Array[String] = wrap_text(font, focus_line(), TEXT_SIZE, inner, FOCUS_LINES)
	out["focus_lines"] = focus_lines
	out["focus_at"] = Vector2(body_x, y + NAME_DY - PX * 2.0)
	y += LINE * float(maxi(1, focus_lines.size()))
	var clause: String = _clause_of(sel)
	var who_lines: Array[String] = wrap_text(font, clause, TEXT_SIZE, inner, WHO_LINES)
	out["who_text"] = clause
	out["who_lines"] = who_lines
	out["who_at"] = Vector2(body_x, y + NAME_DY - PX * 2.0)
	out["who_label_at"] = Vector2(GUTTER, y + NAME_DY - PX * 2.0)
	y += LINE * float(maxi(1, who_lines.size()))
	out["learn_label_at"] = Vector2(GUTTER, y + NAME_DY - PX * 2.0)
	out["learn"] = _learning_runs(font, Vector2(body_x, y + NAME_DY - PX * 2.0), inner, _selected, focus_now)
	out["foot_at"] = Vector2(GUTTER, size.y - FOOT_H + NAME_DY - PX * 2.0)
	return out


# What the picked colonist knows and, when the learning is the player's, what they could learn now,
# as runs of words laid along at most LEARN_LINES lines: [{at, text, node, col}]. A learnable name
# is one run with its node, so it is one click target; nothing here carries a cost or a count.
func _learning_runs(font: Font, origin: Vector2, width: float, ent: int, focus: String) -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	if _world == null or ent < 0:
		return runs
	var view: Dictionary = SimSkills.web_view(_world, ent)
	var pieces: Array[Dictionary] = []
	var known: Array = view.get("known", []) as Array
	pieces.append({"text": (" · ".join(PackedStringArray(known)) if not known.is_empty() else "nothing yet"), "node": "", "col": Locker.TEXT})
	var learnable: Array = view.get("learnable", []) as Array
	if focus != "Manual":
		pieces.append({"text": " — learns on their own; manual lets you choose", "node": "", "col": Locker.TEXT_DIM})
	elif learnable.is_empty():
		pieces.append({"text": " — nothing they could learn yet", "node": "", "col": Locker.TEXT_DIM})
	else:
		pieces.append({"text": " — could learn:", "node": "", "col": Locker.TEXT_DIM})
		for it in learnable:
			pieces.append({"text": " " + String((it as Dictionary).get("name", "")), "node": String((it as Dictionary).get("node", "")), "col": Locker.ACCENT})
	var at: Vector2 = origin
	var line: int = 0
	for p in pieces:
		# A plain piece breaks at its spaces; a learnable name moves whole to the next line.
		var words: PackedStringArray = [String(p["text"])] if String(p["node"]) != "" else String(p["text"]).split(" ", true)
		for wi in words.size():
			var word: String = words[wi] if String(p["node"]) != "" or wi == 0 else " " + words[wi]
			var ww: float = font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x
			if at.x + ww > origin.x + width and at.x > origin.x:
				line += 1
				if line >= LEARN_LINES:
					return runs
				at = Vector2(origin.x, origin.y + LINE * float(line))
				word = word.strip_edges(true, false)
				ww = font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x
			if word.is_empty():
				continue
			runs.append({"at": at, "text": word, "node": String(p["node"]), "col": p["col"]})
			at.x += ww
	return runs


func _gui_input(event: InputEvent) -> void:
	if _world == null:
		return
	if event is InputEventMouseMotion:
		var over: String = ""
		for chip in _layout()["chips"] as Array:
			if ((chip as Dictionary)["rect"] as Rect2).has_point((event as InputEventMouseMotion).position):
				over = String((chip as Dictionary)["focus"])
		if over != _hover_focus:
			_hover_focus = over
			queue_redraw()
		return
	if not event is InputEventMouseButton:
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if not mb.pressed:
		return
	if mb.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP]:
		var step: int = 1 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1
		_row_scroll = clampi(_row_scroll + step, 0, maxi(0, _rows.size() - _visible_rows()))
		queue_redraw()
		accept_event()
		return
	var right: bool = mb.button_index == MOUSE_BUTTON_RIGHT
	if mb.button_index != MOUSE_BUTTON_LEFT and not right:
		return
	accept_event()
	_click(mb.position, right)


# What a click at `p` (panel space) does. Returns what it did, for the gates: "cell", "row",
# "focus", "skills", "learn" or "".
func _click(p: Vector2, right: bool) -> String:
	var laid: Dictionary = _layout()
	if not right:
		for chip in laid["chips"] as Array:
			if ((chip as Dictionary)["rect"] as Rect2).has_point(p) and _selected >= 0:
				_world.commands.push({"type": "job.focus", "entity": _selected, "focus": String((chip as Dictionary)["focus"])})
				return "focus"
		if (laid["skills"] as Rect2).has_point(p) and _selected >= 0:
			picked.emit(_selected)
			navigate.emit("skills")
			return "skills"
		for run in laid["learn"] as Array:
			var rd: Dictionary = run as Dictionary
			if String(rd["node"]) != "" and _run_rect(rd).has_point(p):
				_world.commands.push({"type": "web.buy", "entity": _selected, "node": String(rd["node"])})
				return "learn"
	var edges: Array[float] = laid["edges"] as Array[float]
	var vr: int = floori((p.y - GRID_Y) / ROW_H)
	if vr < 0 or vr >= mini(_rows.size(), _visible_rows()) or p.x < PX * 4.0 or p.x > size.x - PX * 4.0:
		return ""
	var row: Dictionary = _rows[vr + _row_scroll]
	var ent: int = int(row.get("entity", -1))
	var c: int = _column_at(p.x, edges)
	if c < 0:
		if right:
			return ""
		_selected = ent
		picked.emit(ent)
		queue_redraw()
		return "row"
	var col: String = shown_columns()[c]
	var cur: int = int((row.get("cols", {}) as Dictionary).get(col, 0))
	var nxt: int = (4 if cur <= 0 else cur - 1) if right else (0 if cur >= 4 else cur + 1)
	# Through the queue, like every other player act: a grid edit is in `commands.recorded`, so R6's
	# replay reproduces a run the player steered. main.gd re-pulls the view every frame.
	_world.commands.push({"type": "job.priority", "entity": ent, "column": col, "value": nxt})
	return "cell"


func _run_rect(run: Dictionary) -> Rect2:
	var at: Vector2 = run["at"] as Vector2
	var w: float = Chrome.font().get_string_size(String(run["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x
	return Rect2(Vector2(at.x, at.y - Chrome.ascent(TEXT_SIZE)), Vector2(w, Chrome.line_height(TEXT_SIZE)))


func _draw() -> void:
	var font: Font = Chrome.font()
	var laid: Dictionary = _layout()
	var rect := Rect2(Vector2.ZERO, size)
	var a: float = 0.96
	Locker.panel(self, rect, a)
	Locker.header(self, rect, "work", a, LEGEND, Chrome.GLYPH_SMALL + PX * 3.0)
	# One art pixel further in than the web's first cut, clear of the corner rivet.
	Chrome.glyph(self, "work", Vector2(rect.end.x - Chrome.GLYPH_SMALL - PX * 6.0, PX * 3.0 + floorf((Locker.TAPE_H - Chrome.GLYPH_SMALL) / 2.0)), true, 0.7)
	var edges: Array[float] = laid["edges"] as Array[float]
	var columns: Array[String] = shown_columns()
	# The group words over their columns, each on a groove that spans the group.
	var i0: int = 0
	for g in groups():
		var cols: Array = g["columns"] as Array
		var x0: float = edges[i0]
		var x1: float = _column_end(edges, i0 + cols.size() - 1)
		draw_string(font, Vector2(x0, GROUP_BASE), String(g["word"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, Locker.TEXT_DIM)
		Locker.groove(self, Vector2(x0, GROUP_BASE + PX * 3.0), x1 - x0, a)
		i0 += cols.size()
	for i in columns.size():
		var cw: float = _column_end(edges, i) - edges[i]
		var head: String = UiText.fit(font, columns[i], head_size, cw - PX * 2.0)
		var hw: float = font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, head_size).x
		draw_string(font, Vector2(floorf((edges[i] + (cw - hw) / 2.0) / 2.0) * 2.0, HEAD_BASE), head, HORIZONTAL_ALIGNMENT_LEFT, -1, head_size, Locker.TEXT)
	drawn = {"rows": {}}
	var picked_band: Rect2 = Rect2()
	for rd in laid["rows"] as Array:
		var row: Dictionary = rd as Dictionary
		var ent: int = int(row["entity"])
		var band: Rect2 = row["band"] as Rect2
		var source: Dictionary = _rows[_row_of(ent)] if _row_of(ent) >= 0 else {}
		if ent == _selected:
			Locker.well(self, band, a)
			picked_band = band
		else:
			Locker.groove(self, Vector2(band.position.x + PX * 2.0, band.end.y - PX * 2.0), band.size.x - PX * 4.0, a)
		draw_string(font, row["name_at"] as Vector2, String(row["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, Locker.TEXT)
		# The stamp is never amber: amber on this screen is the picked person, the Focus in force on
		# the drawer's chips and a name you can learn, all one meaning (docs/32, selection and
		# available action). Manual says itself in the word.
		var focus: String = String(row["focus"])
		Locker.chip(self, row["focus_rect"] as Rect2, focus, false, a, TEXT_SIZE)
		var now: String = WorkRead.doing(_world, ent) if _world != null else ""
		var shown_now: String = UiText.fit(font, now, TEXT_SIZE, now_room())
		(drawn["rows"] as Dictionary)[ent] = {"now": shown_now}
		if not now.is_empty():
			var nat: Vector2 = row["now_at"] as Vector2
			draw_string(font, nat, NOW_LEAD, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, Locker.TEXT_DIM)
			var lw: float = font.get_string_size(NOW_LEAD, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x
			draw_string(font, nat + Vector2(lw, 0.0), shown_now, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, Locker.TEXT)
		var vals: Dictionary = source.get("cols", {}) as Dictionary
		for cell in row["cells"] as Array:
			var cr: Rect2 = (cell as Dictionary)["rect"] as Rect2
			var v: int = int(vals.get(String((cell as Dictionary)["column"]), 0))
			Locker.well(self, cr, a)
			# Urgent work reads brighter, so a row's shape shows without reading the digits.
			# "Never" is the dim ink, not the faint one: the faint ink on a well is under 3:1.
			var tint: Color = Locker.TEXT_DIM if v <= 0 else Locker.TEXT.lerp(Locker.TEXT_DIM, float(v - 1) / 3.0)
			Locker.text_centred(self, cr, "–" if v <= 0 else str(v), TEXT_SIZE, tint, a)
	# Under the last row drawn, while some are scrolled away: how many, and which way.
	drawn["more"] = more_line()
	if not String(drawn["more"]).is_empty():
		draw_string(font, laid["more_at"] as Vector2, String(drawn["more"]), HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, Locker.TEXT_DIM)
	_draw_drawer(font, laid, a)
	# The picked row's brackets go on last: the drawer's groove under the last row would otherwise
	# cut their bottom arms.
	if picked_band.size.x > 0.0:
		Locker.brackets(self, picked_band, Locker.ACCENT)
	var stubs: PackedStringArray = []
	for c in unworked_columns():
		stubs.append(c.to_lower())
	var foot: String = "not yet anyone's work: " + ", ".join(stubs)
	drawn["foot"] = foot
	Locker.groove(self, Vector2(PX * 4.0, size.y - FOOT_H), size.x - PX * 8.0, a)
	draw_string(font, laid["foot_at"] as Vector2, UiText.fit(font, foot, TEXT_SIZE, size.x - GUTTER * 2.0), HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, Locker.TEXT_DIM)


func _draw_drawer(font: Font, laid: Dictionary, a: float) -> void:
	var dr: Rect2 = laid["drawer"] as Rect2
	Locker.groove(self, dr.position, dr.size.x, a)
	drawn["who"] = laid["who_lines"]
	if _selected < 0:
		var ask: String = "nobody to manage yet" if _rows.is_empty() else "click a colonist's name to see them here"
		draw_string(font, laid["name_at"] as Vector2, ask, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, Locker.TEXT_DIM)
		return
	var sel: int = _row_of(_selected)
	var name: String = String(_rows[sel].get("name", "?")) if sel >= 0 else "?"
	draw_string(font, laid["name_at"] as Vector2, name, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, Locker.TEXT)
	Locker.button(self, laid["skills"] as Rect2, String(laid["skills_label"]), false, a)
	draw_string(font, laid["focus_label_at"] as Vector2, "focus", HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, Locker.TEXT_DIM)
	draw_string(font, laid["who_label_at"] as Vector2, "who", HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, Locker.TEXT_DIM)
	draw_string(font, laid["learn_label_at"] as Vector2, "knows", HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, Locker.TEXT_DIM)
	var now: String = String(laid["focus_now"])
	for chip in laid["chips"] as Array:
		var cd: Dictionary = chip as Dictionary
		var f: String = String(cd["focus"])
		Locker.chip(self, cd["rect"] as Rect2, f.to_lower(), f == now, a, TEXT_SIZE)
		if f == _hover_focus and f != now:
			Locker.rim(self, cd["rect"] as Rect2, Locker.TEXT_DIM)
	var at: Vector2 = laid["focus_at"] as Vector2
	for line in laid["focus_lines"] as Array:
		draw_string(font, at, String(line), HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, Locker.TEXT_DIM)
		at.y += LINE
	at = laid["who_at"] as Vector2
	for line in laid["who_lines"] as Array:
		draw_string(font, at, String(line), HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, Locker.TEXT)
		at.y += LINE
	for run in laid["learn"] as Array:
		var rd: Dictionary = run as Dictionary
		draw_string(font, rd["at"] as Vector2, String(rd["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, rd["col"] as Color)
