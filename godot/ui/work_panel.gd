extends Control
# 17-column Work grid (docs/07 order). Player is not a row. Stub columns store a number.
#
# The panel is also where a survivor's **Focus** is chosen, which is the same act as choosing who
# manages their skill web. docs/07: "Setting Focus to Manual gives full control of that one
# survivor's web and inventory", and every other Focus auto-allocates. So there is deliberately no
# second toggle beside the word -- the word *is* the toggle, and "manual" is the value that says
# the learning is in your hands.

const SimJobs = preload("res://sim/modules/jobs.gd")
const SimSkills = preload("res://sim/modules/skills.gd")
const SimSurvivors = preload("res://sim/modules/survivors.gd")
const UiText = preload("res://ui/text.gd")
const Chrome = preload("res://ui/chrome.gd")

# Grid geometry, shared by _draw and _gui_input. These were duplicated literals in both, so
# moving a header down silently moved every cell out from under the cursor that clicks it.
# ROW_H carries three lines now -- the name and focus word, `person_clause`'s dimmer second
# line, and the learning line beneath that -- and it is the same for every row on purpose: a
# variable row height would turn the click math from one divide into a running sum.
const COL_W: float = 72.0
const ROW_H: float = 70.0
const GRID_X: float = 240.0
const GRID_Y: float = 88.0
const CLAUSE_DY: float = 18.0
const LEARN_DY: float = 36.0
# What the name column gives up so the focus word has somewhere to sit.
const FOCUS_W: float = 88.0

# The five self-managing focuses and the one that is not, in the order a click walks them. Manual
# is last so it is one right-click away from Auto, and Auto is first because it is the handback --
# clicking round to it hands the survivor back to themselves (jobs.gd stamps it "auto" for exactly
# that reason).
const FOCUS_CYCLE: Array[String] = ["Auto", "Fighter", "Worker", "Medic", "Scout", "Manual"]

var _world: Variant = null
var _rows: Array[Dictionary] = []
# Click targets built by _draw and read by _gui_input: {rect, entity, node}, where an empty `node`
# is the focus word and anything else is a learnable node. Derived every draw, never stored.
var _hit: Array[Dictionary] = []


func set_world(world: Variant) -> void:
	_world = world
	_rows = SimJobs.work_view(world) if world != null else []
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if _world == null or not event is InputEventMouseButton:
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if not mb.pressed:
		return
	var right: bool = mb.button_index == MOUSE_BUTTON_RIGHT
	if mb.button_index != MOUSE_BUTTON_LEFT and not right:
		return
	# Words first: they sit inside the rows the grid math also covers, so whichever is more
	# specific has to win, and a word is more specific than a row.
	for h in _hit:
		if (h["rect"] as Rect2).has_point(mb.position):
			_act(h, right)
			return
	if right:
		return
	var c: int = floori((mb.position.x - GRID_X) / COL_W)
	var r: int = floori((mb.position.y - GRID_Y) / ROW_H)
	if r < 0 or r >= _rows.size() or c < 0 or c >= SimJobs.COLUMNS.size():
		return
	var col: String = SimJobs.COLUMNS[c]
	if not SimJobs.CONSUMERS.has(col):
		return
	var row: Dictionary = _rows[r]
	var cols: Dictionary = row.get("cols", {}) as Dictionary
	var cur: int = int(cols.get(col, 0))
	var nxt: int = 0 if cur >= 4 else cur + 1
	if nxt == 1 and cur == 0:
		nxt = 1
	# Through the queue, like every other player act. This was the one place in the UI that
	# reached into the sim and mutated it directly, which meant a grid edit was invisible to
	# `commands.recorded` and so R6's replay could never reproduce a run the player had steered.
	# The synchronous re-pull went with it: main.gd re-pulls the view every frame anyway, so the
	# row updates on the tick the command lands rather than a tick before it.
	_world.commands.push({
		"type": "job.priority", "entity": int(row.get("entity", -1)), "column": col, "value": nxt,
	})


func _act(hit: Dictionary, right: bool) -> void:
	var ent: int = int(hit.get("entity", -1))
	var node: String = String(hit.get("node", ""))
	if node != "":
		if right:
			return
		_world.commands.push({"type": "web.buy", "entity": ent, "node": node})
		return
	var cur: int = FOCUS_CYCLE.find(String(hit.get("focus", "Auto")))
	if cur < 0:
		cur = 0
	var step: int = -1 if right else 1
	var nxt: String = FOCUS_CYCLE[posmod(cur + step, FOCUS_CYCLE.size())]
	_world.commands.push({"type": "job.focus", "entity": ent, "focus": nxt})


# The one place a word's extent is measured, so the rectangle that is drawn and the rectangle
# that is clicked cannot drift apart.
func _word_rect(font: Font, at: Vector2, word: String, font_size: int) -> Rect2:
	var w: float = font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	return Rect2(Vector2(at.x, at.y - float(font_size) * 0.8), Vector2(w, float(font_size) * 1.15))


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	_hit.clear()
	Chrome.panel(self, Rect2(Vector2.ZERO, size), 0.95)
	Chrome.header(self, Rect2(Vector2.ZERO, size), "work — click a cell to change priority · click their word to change focus — manual puts their learning in your hands", 0.95)
	# The priority scale, which the grid previously assumed you already knew. 1 is most
	# urgent; docs/07's row is an ordering the player sets, not a hidden stat, so the
	# numbers are the honest presentation here.
	draw_string(font, Vector2(16, 64), "1 first · 4 last · – never", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Chrome.TEXT_DIM)
	var ox: float = GRID_X
	var oy: float = GRID_Y
	var col_w: float = COL_W
	for i in SimJobs.COLUMNS.size():
		# Fit the real column name to its width rather than cutting every one to 3 letters,
		# which made Construct and Cook read identically.
		var name: String = UiText.fit(font, String(SimJobs.COLUMNS[i]), 18, col_w - 6.0)
		var consumer: bool = SimJobs.CONSUMERS.has(SimJobs.COLUMNS[i])
		draw_string(font, Vector2(ox + float(i) * col_w, oy - 4), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#c9c4b8") if consumer else Color("#4e4a45"))
	for r in _rows.size():
		var row: Dictionary = _rows[r]
		var ent: int = int(row.get("entity", -1))
		var row_y: float = oy + 28.0 + float(r) * ROW_H
		var who: String = UiText.fit(font, String(row.get("name", "?")), 20, ox - 32.0 - FOCUS_W)
		draw_string(font, Vector2(16, row_y), who, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#c9c4b8"))
		# Who manages this survivor, in one lowercase word at the end of their name. `work_view`
		# has delivered `focus` since the grid was written and nothing had ever drawn it; this is
		# the field being read at last, and the click target for changing it.
		var focus: String = String(row.get("focus", "Auto"))
		var word: String = focus.to_lower()
		var word_w: float = font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var word_at := Vector2(16.0 + (ox - 32.0) - word_w, row_y)
		# Amber is reserved for the one thing that matters (chrome.gd), and among these six words
		# exactly one means "you are doing this yourself".
		draw_string(font, word_at, word, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Chrome.ACCENT if focus == "Manual" else Chrome.TEXT_DIM)
		_hit.append({"rect": _word_rect(font, word_at, word, 18), "entity": ent, "node": "", "focus": focus})
		# Who they are, past the name: backstory, roughly how old they read, what a look at
		# them shows -- one prose sentence, no digits, `identity`'s dead sockets read at last.
		# The row already says the name, so the clause's own leading "name, " is dropped here
		# rather than repeated.
		var clause: String = SimSurvivors.person_clause(_world, ent)
		var lead: String = String(row.get("name", "?")) + ", "
		if clause.begins_with(lead):
			clause = clause.substr(lead.length())
		if not clause.is_empty():
			var fitted: String = UiText.fit(font, clause, 14, ox - 32.0)
			draw_string(font, Vector2(16, row_y + CLAUSE_DY), fitted, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Chrome.TEXT_DIM)
		_draw_learning(font, ent, row_y + LEARN_DY)
		var cols: Dictionary = row.get("cols", {}) as Dictionary
		for i in SimJobs.COLUMNS.size():
			var v: int = int(cols.get(SimJobs.COLUMNS[i], 0))
			var label: String = "–" if v <= 0 else str(v)
			# Urgent work reads brighter, so a row's shape is visible without reading digits.
			var tint: Color = Color("#4e4a45") if v <= 0 else Color("#c9c4b8").lerp(Color("#7b776e"), float(v - 1) / 3.0)
			draw_string(font, Vector2(ox + float(i) * col_w, row_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, tint)


# What this survivor has learned, and -- when the learning is the player's job -- what they could
# learn right now. Both come from `SimSkills.web_view`, which carries prose and nothing else: no
# cost, no points, no counts, so there is no way to draw a progress bar over somebody's web from
# what this function is given. A name that is affordable is simply present; one that is not is not.
func _draw_learning(font: Font, ent: int, y: float) -> void:
	if _world == null or ent < 0:
		return
	var view: Dictionary = SimSkills.web_view(_world, ent)
	var known: Array = view.get("known", []) as Array
	var learnable: Array = view.get("learnable", []) as Array
	var x: float = 16.0
	if not known.is_empty():
		var head: String = "knows " + " · ".join(PackedStringArray(known))
		draw_string(font, Vector2(x, y), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Chrome.TEXT_DIM)
		x += font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	if learnable.is_empty():
		return
	var lead: String = " — could learn: " if not known.is_empty() else "could learn: "
	draw_string(font, Vector2(x, y), lead, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Chrome.TEXT_DIM)
	x += font.get_string_size(lead, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	for i in learnable.size():
		var it: Dictionary = learnable[i] as Dictionary
		var label: String = String(it.get("name", ""))
		var at := Vector2(x, y)
		draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Chrome.ACCENT)
		_hit.append({"rect": _word_rect(font, at, label, 14), "entity": ent, "node": String(it.get("node", "")), "focus": ""})
		x += font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		if i < learnable.size() - 1:
			var sep: String = ", "
			draw_string(font, Vector2(x, y), sep, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Chrome.TEXT_DIM)
			x += font.get_string_size(sep, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
