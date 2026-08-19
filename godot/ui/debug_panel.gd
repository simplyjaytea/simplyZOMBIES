extends Control
# The developer spawn menu, on F8. Dev tooling in the same family as the M raw sheet: it
# exists to set up test scenarios without hand-writing a driver script, and it is not part
# of the player-facing HUD contract (the HUD gate reads hud.gd's lines, and nothing here
# is prose the player is owed). Everything it does goes through the `debug.spawn` command,
# so a spawned zombie arrives inside the tick like any other change to the world.

const Chrome = preload("res://ui/chrome.gd")
const UiText = preload("res://ui/text.gd")
const SimRoster = preload("res://sim/modules/roster.gd")

const PANEL_W: float = 480.0
const ROW_H: float = 34.0
const ITEM_FONT: int = 18
const ZOMBIE_SPAWN_METRES: float = 6.0

var _world: Variant = null
var _item_ids: Array[String] = []
var _scroll: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_world(world: Variant) -> void:
	_world = world
	if _item_ids.is_empty() and world != null and world.content is Dictionary:
		var ids: Dictionary = {}
		for v in (world.content as Dictionary).values():
			var entries: Array = (v as Array) if v is Array else ([v] if v is Dictionary else [])
			for e in entries:
				if e is Dictionary:
					var id: String = String((e as Dictionary).get("id", ""))
					if id.begins_with("item."):
						ids[id] = true
		var sorted: Array = ids.keys()
		sorted.sort()
		for id in sorted:
			_item_ids.append(String(id))
	queue_redraw()


func _zombie_ids() -> Array[String]:
	return [SimRoster.TYPE_SHAMBLER, SimRoster.TYPE_SCREAMER, SimRoster.TYPE_BLOATER]


func _rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for z in _zombie_ids():
		out.append({"kind": "zombie", "id": z})
	for i in _item_ids.size():
		out.append({"kind": "item", "id": _item_ids[i]})
	return out


func _visible_rows() -> int:
	return maxi(1, int((size.y - Chrome.HEADER_H - 56.0) / ROW_H))


func _spawn(kind: String, id: String) -> void:
	if _world == null:
		return
	var pos: Variant = _world.components.get_component(int(_world.player), "position")
	if not (pos is Dictionary):
		return
	var x: float = float((pos as Dictionary)["x"])
	var y: float = float((pos as Dictionary)["y"])
	if kind == "zombie":
		# Ahead of the player, so the spawn is visible and not on top of them.
		var facing: Variant = _world.components.get_component(int(_world.player), "facing")
		var ang: float = float((facing as Dictionary).get("radians", 0.0)) if facing is Dictionary else 0.0
		x += cos(ang) * ZOMBIE_SPAWN_METRES
		y += sin(ang) * ZOMBIE_SPAWN_METRES
	else:
		x += 0.8
	_world.commands.push({"type": "debug.spawn", "kind": kind, "id": id, "x": x, "y": y})


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll = mini(_scroll + 3, maxi(0, _rows().size() - _visible_rows()))
			queue_redraw()
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll = maxi(0, _scroll - 3)
			queue_redraw()
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var idx: int = _scroll + int((mb.position.y - Chrome.HEADER_H - 48.0) / ROW_H)
			var rows: Array[Dictionary] = _rows()
			if idx >= 0 and idx < rows.size() and mb.position.y > Chrome.HEADER_H + 44.0:
				_spawn(String(rows[idx]["kind"]), String(rows[idx]["id"]))
			accept_event()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	Chrome.panel(self, rect, 0.96)
	Chrome.header(self, rect, "debug — spawn", 0.96)
	var font: Font = Chrome.font()
	draw_string(font, Vector2(14.0, Chrome.HEADER_H + 30.0), "click to spawn at your feet (items) or ahead of you (zombies) · wheel scrolls", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Chrome.TEXT_DIM)
	var rows: Array[Dictionary] = _rows()
	var y: float = Chrome.HEADER_H + 48.0
	var shown: int = 0
	for i in range(_scroll, rows.size()):
		if shown >= _visible_rows():
			break
		var r: Dictionary = rows[i]
		var is_z: bool = String(r["kind"]) == "zombie"
		var label: String = UiText.fit(font, String(r["id"]), ITEM_FONT, size.x - 28.0)
		draw_string(font, Vector2(14.0, y + 24.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, ITEM_FONT, Chrome.DANGER if is_z else Chrome.TEXT)
		y += ROW_H
		shown += 1
