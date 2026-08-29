extends Control
# 17-column Work grid (docs/07 order). Player is not a row. Stub columns store a number.

const SimJobs = preload("res://sim/modules/jobs.gd")
const SimSurvivors = preload("res://sim/modules/survivors.gd")
const UiText = preload("res://ui/text.gd")
const Chrome = preload("res://ui/chrome.gd")

# Grid geometry, shared by _draw and _gui_input. These were duplicated literals in both, so
# moving a header down silently moved every cell out from under the cursor that clicks it.
# ROW_H carries two lines now -- the name and, beneath it, `person_clause`'s dimmer second
# line -- so it grew from the one-line 36 to fit both without crowding.
const COL_W: float = 72.0
const ROW_H: float = 52.0
const GRID_X: float = 240.0
const GRID_Y: float = 88.0

var _world: Variant = null
var _rows: Array[Dictionary] = []


func set_world(world: Variant) -> void:
	_world = world
	_rows = SimJobs.work_view(world) if world != null else []
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if _world == null or not event is InputEventMouseButton:
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
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
	SimJobs.set_priority(_world, int(row.get("entity", -1)), col, nxt)
	set_world(_world)


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	Chrome.panel(self, Rect2(Vector2.ZERO, size), 0.95)
	Chrome.header(self, Rect2(Vector2.ZERO, size), "work — click a cell to change priority", 0.95)
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
		var row_y: float = oy + 28.0 + float(r) * ROW_H
		var who: String = UiText.fit(font, String(row.get("name", "?")), 20, ox - 32.0)
		draw_string(font, Vector2(16, row_y), who, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#c9c4b8"))
		# Who they are, past the name: backstory, roughly how old they read, what a look at
		# them shows -- one prose sentence, no digits, `identity`'s dead sockets read at last.
		# The row already says the name, so the clause's own leading "name, " is dropped here
		# rather than repeated.
		var clause: String = SimSurvivors.person_clause(_world, int(row.get("entity", -1)))
		var lead: String = String(row.get("name", "?")) + ", "
		if clause.begins_with(lead):
			clause = clause.substr(lead.length())
		if not clause.is_empty():
			var fitted: String = UiText.fit(font, clause, 14, ox - 32.0)
			draw_string(font, Vector2(16, row_y + 18.0), fitted, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Chrome.TEXT_DIM)
		var cols: Dictionary = row.get("cols", {}) as Dictionary
		for i in SimJobs.COLUMNS.size():
			var v: int = int(cols.get(SimJobs.COLUMNS[i], 0))
			var label: String = "–" if v <= 0 else str(v)
			# Urgent work reads brighter, so a row's shape is visible without reading digits.
			var tint: Color = Color("#4e4a45") if v <= 0 else Color("#c9c4b8").lerp(Color("#7b776e"), float(v - 1) / 3.0)
			draw_string(font, Vector2(ox + float(i) * col_w, row_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, tint)
