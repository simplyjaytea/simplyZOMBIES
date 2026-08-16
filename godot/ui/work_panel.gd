extends Control
# 17-column Work grid (docs/07 order). Player is not a row. Stub columns store a number.

const SimJobs = preload("res://sim/modules/jobs.gd")

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
	var col_w: float = 36.0
	var row_h: float = 18.0
	var ox: float = 120.0
	var oy: float = 28.0
	var c: int = floori((mb.position.x - ox) / col_w)
	var r: int = floori((mb.position.y - oy) / row_h)
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
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.06, 0.07, 0.94))
	draw_string(ThemeDB.fallback_font, Vector2(8, 16), "Work  Auto · Fighter · Worker · Medic · Scout · Manual", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#c9c4b8"))
	var ox: float = 120.0
	var oy: float = 28.0
	var col_w: float = 36.0
	for i in SimJobs.COLUMNS.size():
		var name: String = SimJobs.COLUMNS[i].substr(0, 3)
		draw_string(ThemeDB.fallback_font, Vector2(ox + float(i) * col_w, oy - 2), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#7b776e"))
	for r in _rows.size():
		var row: Dictionary = _rows[r]
		draw_string(ThemeDB.fallback_font, Vector2(8, oy + 14.0 + float(r) * 18.0), String(row.get("name", "?")).substr(0, 12), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#c9c4b8"))
		var cols: Dictionary = row.get("cols", {}) as Dictionary
		for i in SimJobs.COLUMNS.size():
			var v: int = int(cols.get(SimJobs.COLUMNS[i], 0))
			var label: String = "-" if v <= 0 else str(v)
			draw_string(ThemeDB.fallback_font, Vector2(ox + float(i) * col_w, oy + 14.0 + float(r) * 18.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#c9c4b8"))
