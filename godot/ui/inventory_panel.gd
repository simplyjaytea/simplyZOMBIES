extends Control
# Port of src/ui/inventory.ts — first screen, Controls not canvas.
# Rules: reads InventoryView snapshot, proposes Commands, no numbers except counts.
# ponytail: drag is one file here; split to DragState resource when reusing outside inventory.

const SimInventory = preload("res://sim/modules/inventory.gd")
const SimCondition = preload("res://sim/condition.gd")
const UiText = preload("res://ui/text.gd")

# PartState 0..3 as words. Same four grades the paperdoll tints, never a number.
const PART_STATE_WORDS: Array[String] = ["unhurt", "hurt", "badly hurt", "unusable"]

# Equipment slot geometry, in one place. This array was copied into _gui_input, _try_drop
# and _draw, so the boxes you could click and the boxes you could see were three separate
# sets of literals that happened to agree.
#
# Three cells wide rather than two: "Kitchen Knife" did not fit in two, and a slot that
# cannot show what is in it is not doing its job. The right-hand column still lands inside
# the 548px body panel (440 + 102 = 542).
const SLOT_W: float = float(CELL) * 3.0
const SLOT_H: float = float(CELL)
const SLOT_PLACEMENTS: Array[Dictionary] = [
	{"slot": "head", "x": 24.0, "y": 43.0},
	{"slot": "back", "x": 24.0, "y": 104.0},
	{"slot": "vest", "x": 440.0, "y": 104.0},
	{"slot": "primary", "x": 24.0, "y": 220.0},
	{"slot": "secondary", "x": 440.0, "y": 220.0},
	{"slot": "belt", "x": 24.0, "y": 324.0},
	{"slot": "torso", "x": 440.0, "y": 324.0},
]


static func slot_rect(body_x: float, body_y: float, placement: Dictionary) -> Rect2:
	return Rect2(Vector2(body_x + float(placement["x"]), body_y + float(placement["y"])), Vector2(SLOT_W, SLOT_H))
const Palette = preload("res://presentation/palette.gd")
const Paperdoll = preload("res://ui/paperdoll.gd")

const CELL: int = 34
const PAD: int = 14
const TITLE_H: int = 18

var _world: Variant = null
var _actor: int = -1
var _view: Dictionary = {}
var _body_view: String = "equipment" # equipment | injuries
var _selected_part: String = "head"
var _drag_item: int = -1
var _drag_rotated: bool = false
var _drag_from_container: int = -1
var _paperdoll: Control = null

func _ready() -> void:
	custom_minimum_size = Vector2(860, 520)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_paperdoll = Paperdoll.new()
	_paperdoll.custom_minimum_size = Vector2(260, 260)
	add_child(_paperdoll)

func set_world(world: Variant, actor: int) -> void:
	_world = world
	_actor = actor
	_view = SimInventory.inventory_view(world, actor) if world != null else {}
	# refresh condition view into paperdoll — sim/condition.gd is the one builder, and the
	# one thing check_ban_health_bar.gd gates.
	if world != null:
		var cv: Dictionary = SimCondition.view(world, actor)
		if not cv.is_empty():
			_paperdoll.call("set_view", cv)
	queue_redraw()

func rotate() -> void:
	if _drag_item != -1:
		_drag_rotated = not _drag_rotated
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if _world == null or _view.is_empty():
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_try_pick(mb.position)
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and _drag_item != -1:
			_try_drop(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _drag_item != -1:
			_drag_rotated = not _drag_rotated
			queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _drag_item == -1:
			_try_use(mb.position)
	elif event is InputEventMouseMotion and _drag_item != -1:
		queue_redraw()

func _try_pick(at: Vector2) -> void:
	# tabs
	var body_x: float = float(PAD)
	var body_y: float = float(PAD)
	var tab_w: float = 112.0
	# two tabs at top-right of body panel (548x390 in TS, scaled to our size)
	var tab_equip: Rect2 = Rect2(Vector2(body_x + 548.0 - PAD - tab_w * 2, body_y + 1), Vector2(tab_w, 26))
	var tab_inj: Rect2 = Rect2(Vector2(body_x + 548.0 - PAD - tab_w, body_y + 1), Vector2(tab_w, 26))
	if tab_equip.has_point(at):
		_body_view = "equipment"; queue_redraw(); return
	if tab_inj.has_point(at):
		_body_view = "injuries"; _drag_item = -1; queue_redraw(); return
	if _body_view == "injuries":
		# injury rows
		var list_x: float = body_x + 276.0; var list_y: float = body_y + 52.0
		for i in range(SimCondition.PART_ORDER.size()):
			var r: Rect2 = Rect2(Vector2(list_x, list_y + float(i) * 27.0), Vector2(248, 27))
			if r.has_point(at):
				_selected_part = SimCondition.PART_ORDER[i]
				queue_redraw(); return
		return
	# equipment slots (simplified 7 slots)
	var slots: Array = _view.get("slots", []) as Array
	for pl in SLOT_PLACEMENTS:
		var rect: Rect2 = slot_rect(body_x, body_y, pl)
		if rect.has_point(at):
			for entry in slots:
				var d: Dictionary = entry as Dictionary
				if String(d.get("slot", "")) == String(pl["slot"]):
					var it: Variant = d.get("item")
					if it is Dictionary:
						_drag_item = int((it as Dictionary).get("item", -1))
						_drag_from_container = -2 # equipment
						_drag_rotated = false
						_world.commands.push({"type": "item.unequip", "slot": String(pl["slot"])})
						queue_redraw()
					return
	# grid picks
	for cont in _view.get("containers", []) as Array:
		var c: Dictionary = cont as Dictionary
		var ox: float = float(c.get("_ox", 0)); var oy: float = float(c.get("_oy", 0))
		var gw: int = int(c.get("w", 0)); var gh: int = int(c.get("h", 0))
		var grid_rect: Rect2 = Rect2(Vector2(ox, oy), Vector2(float(gw * CELL), float(gh * CELL)))
		if not grid_rect.has_point(at): continue
		var local: Vector2 = at - Vector2(ox, oy)
		var cx: int = floori(local.x / float(CELL)); var cy: int = floori(local.y / float(CELL))
		for it in c.get("items", []) as Array:
			var d: Dictionary = it as Dictionary
			var rx: int = int(d.get("x", 0)); var ry: int = int(d.get("y", 0))
			var rw: int = int(d.get("w", 1)); var rh: int = int(d.get("h", 1))
			if cx >= rx and cx < rx + rw and cy >= ry and cy < ry + rh:
				_drag_item = int(d.get("item", -1))
				_drag_from_container = int(c.get("container", -1))
				_drag_rotated = bool(d.get("rotated", false))
				queue_redraw()
				return

func _try_use(at: Vector2) -> void:
	for cont in _view.get("containers", []) as Array:
		var c: Dictionary = cont as Dictionary
		var ox: float = float(c.get("_ox", 0)); var oy: float = float(c.get("_oy", 0))
		var gw: int = int(c.get("w", 0)); var gh: int = int(c.get("h", 0))
		var grid_rect: Rect2 = Rect2(Vector2(ox, oy), Vector2(float(gw * CELL), float(gh * CELL)))
		if not grid_rect.has_point(at):
			continue
		var local: Vector2 = at - Vector2(ox, oy)
		var cx: int = floori(local.x / float(CELL)); var cy: int = floori(local.y / float(CELL))
		for it in c.get("items", []) as Array:
			var d: Dictionary = it as Dictionary
			var rx: int = int(d.get("x", 0)); var ry: int = int(d.get("y", 0))
			var rw: int = int(d.get("w", 1)); var rh: int = int(d.get("h", 1))
			if cx >= rx and cx < rx + rw and cy >= ry and cy < ry + rh:
				_world.commands.push({"type": "item.use", "item": int(d.get("item", -1))})
				return


func _try_drop(at: Vector2) -> void:
	if _drag_item == -1 or _world == null: return
	var item: int = _drag_item
	_drag_item = -1
	# drop onto equipment slot?
	var body_x: float = float(PAD); var body_y: float = float(PAD)
	for pl in SLOT_PLACEMENTS:
		var rect: Rect2 = slot_rect(body_x, body_y, pl)
		if rect.has_point(at):
			_world.commands.push({"type": "item.equip", "item": item, "slot": String(pl["slot"])})
			queue_redraw(); return
	# drop onto grid cell
	for cont in _view.get("containers", []) as Array:
		var c: Dictionary = cont as Dictionary
		var ox: float = float(c.get("_ox", 0)); var oy: float = float(c.get("_oy", 0))
		var gw: int = int(c.get("w", 0)); var gh: int = int(c.get("h", 0))
		var grid_rect: Rect2 = Rect2(Vector2(ox, oy), Vector2(float(gw * CELL), float(gh * CELL)))
		if not grid_rect.has_point(at): continue
		var local: Vector2 = at - Vector2(ox, oy)
		var cx: int = floori(local.x / float(CELL)); var cy: int = floori(local.y / float(CELL))
		# propose move; sim decides (depth, fit, cycle)
		_world.commands.push({"type": "item.move", "item": item, "container": int(c.get("container", -1)), "x": cx, "y": cy, "rotated": _drag_rotated})
		queue_redraw()
		return
	# dropped outside: no op (keeps in original container until command lands)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.06, 0.07, 0.93))
	if _view.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(float(PAD), float(PAD) + 16), "no inventory", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#7b776e"))
		return
	# body panel header
	var body_x: float = float(PAD)
	var body_y: float = float(PAD)
	var body_w: float = 548.0
	var body_h: float = 390.0
	draw_rect(Rect2(Vector2(body_x, body_y), Vector2(body_w, body_h)), Color("#15181a"))
	draw_rect(Rect2(Vector2(body_x, body_y), Vector2(body_w, body_h)), Color("#2b3033"), false, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(body_x + float(PAD), body_y + 14), "survivor  %s" % _body_view, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#c9c4b8"))
	# tabs
	var tab_w: float = 112.0
	for i in range(2):
		var name: String = ["equipment", "injuries"][i]
		var tx: float = body_x + body_w - float(PAD) - tab_w * float(2 - i)
		var sel: bool = name == _body_view
		draw_rect(Rect2(Vector2(tx, body_y + 1), Vector2(tab_w, 26)), Color("#1e2225") if sel else Color("#15181a"))
		draw_rect(Rect2(Vector2(tx, body_y + 1), Vector2(tab_w, 26)), Color("#6f8a72") if sel else Color("#2b3033"), false, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(tx + 12, body_y + 18), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#c9c4b8") if sel else Color("#7b776e"))
	if _body_view == "equipment":
		_paperdoll.position = Vector2(body_x + body_w / 2.0 - 130, body_y + 42)
		_paperdoll.visible = true
		# equipment slot boxes — geometry from SLOT_PLACEMENTS, the same source the click and
		# drop handlers use, so what you can hit is what you can see.
		var by_slot: Dictionary = {}
		for entry in _view.get("slots", []) as Array:
			var d: Dictionary = entry as Dictionary
			by_slot[String(d.get("slot", ""))] = d.get("item")
		for pl in SLOT_PLACEMENTS:
			var box: Rect2 = slot_rect(body_x, body_y, pl)
			draw_rect(box, Color("#191d20"))
			draw_rect(box, Color("#2b3033"), false, 1.0)
			var it: Variant = by_slot.get(String(pl["slot"]))
			if it is Dictionary:
				draw_rect(Rect2(box.position + Vector2(2, 2), box.size - Vector2(4, 4)), Color("#3a4a3e"))
				var item_name: String = UiText.fit(ThemeDB.fallback_font, String((it as Dictionary).get("name", "")), 10, SLOT_W - 12.0)
				draw_string(ThemeDB.fallback_font, box.position + Vector2(6, 20), item_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#c9c4b8"))
			else:
				draw_string(ThemeDB.fallback_font, box.position + Vector2(6, 20), String(pl["slot"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#7b776e"))
	else:
		_paperdoll.position = Vector2(body_x + 12, body_y + 42)
		_paperdoll.visible = true
		var list_x: float = body_x + 276.0; var list_y: float = body_y + 52.0
		var list_w: float = 248.0
		# Each part's state as a word, from the same read model the paperdoll and HUD use.
		# Still no integrity value and no fraction -- docs/01 clause 4 and the ban gated by
		# check_ban_health_bar.gd. The list previously showed only part names, which told a
		# player nothing about which of them was actually hurt.
		var by_part: Dictionary = {}
		if _world != null:
			for entry in (SimCondition.view(_world, _actor).get("parts", []) as Array):
				var pd: Dictionary = entry as Dictionary
				by_part[String(pd.get("part", ""))] = pd
		var idx: int = 0
		for part in SimCondition.PART_ORDER:
			var sel: bool = part == _selected_part
			if sel:
				draw_rect(Rect2(Vector2(list_x, list_y + float(idx) * 27.0), Vector2(list_w, 25)), Color("#1e2225"))
			var row_y: float = list_y + float(idx) * 27.0 + 16
			draw_string(ThemeDB.fallback_font, Vector2(list_x + 6, row_y), SimCondition.label_of(part), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#c9c4b8"))
			var d: Dictionary = by_part.get(part, {}) as Dictionary
			var st: int = int(d.get("state", 0))
			var word: String = PART_STATE_WORDS[st] if st < PART_STATE_WORDS.size() else ""
			var tint: Color = Palette.CONDITION_TINTS[st] if st < Palette.CONDITION_TINTS.size() else Color("#7b776e")
			draw_string(ThemeDB.fallback_font, Vector2(list_x + 96, row_y), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, tint)
			# The same three words the paperdoll draws as marks on the figure, here as text
			# for the row the player is actually reading. `infected` is already a word
			# (diagnosis_of_part's actionable) rather than a boolean, so it says more than
			# "something is wrong" without ever naming a stage.
			var tags: Array[String] = []
			if bool(d.get("wounded", false)):
				tags.append("wound")
			var infected: String = String(d.get("infected", "none"))
			if infected != "none":
				tags.append(infected)
			if bool(d.get("armored", false)):
				tags.append("armoured")
			if not tags.is_empty():
				var tag_text: String = UiText.fit(ThemeDB.fallback_font, " · ".join(tags), 10, list_x + list_w - (list_x + 168.0) - 6.0)
				draw_string(ThemeDB.fallback_font, Vector2(list_x + 168.0, row_y), tag_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#8b929c"))
			idx += 1
	# grids to the right of body panel, wrapping
	var gx: float = body_x + body_w + 12.0
	var gy: float = body_y
	var col_w: float = 0
	# layout containers into columns so they don't run off-screen
	for cont in _view.get("containers", []) as Array:
		var c: Dictionary = cont as Dictionary
		var gw: int = int(c.get("w", 0)); var gh: int = int(c.get("h", 0))
		var pw: float = float(gw * CELL + PAD * 2)
		var ph: float = float(gh * CELL + TITLE_H + PAD + 8)
		if gy + ph > size.y - float(PAD) and gy > body_y:
			gx += col_w + 12.0; gy = body_y; col_w = 0
		col_w = maxf(col_w, pw)
		# store origin for hit testing in _try_pick
		(c as Dictionary)["_ox"] = gx + float(PAD)
		(c as Dictionary)["_oy"] = gy + float(TITLE_H) + 8.0
		draw_rect(Rect2(Vector2(gx, gy), Vector2(pw, ph)), Color("#15181a"))
		draw_rect(Rect2(Vector2(gx, gy), Vector2(pw, ph)), Color("#2b3033"), false, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(gx + float(PAD), gy + 14), String(c.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#c9c4b8"))
		var ox: float = gx + float(PAD); var oy: float = gy + float(TITLE_H) + 8.0
		for cy in range(gh):
			for cx in range(gw):
				draw_rect(Rect2(Vector2(ox + float(cx * CELL) + 1, oy + float(cy * CELL) + 1), Vector2(float(CELL) - 2, float(CELL) - 2)), Color("#1e2225"))
		for it in c.get("items", []) as Array:
			var d: Dictionary = it as Dictionary
			if int(d.get("item", -1)) == _drag_item: continue
			var ix: int = int(d.get("x", 0)); var iy: int = int(d.get("y", 0))
			var iw: int = int(d.get("w", 1)); var ih: int = int(d.get("h", 1))
			var rx: float = ox + float(ix * CELL) + 2; var ry: float = oy + float(iy * CELL) + 2
			draw_rect(Rect2(Vector2(rx, ry), Vector2(float(iw * CELL) - 4, float(ih * CELL) - 4)), Color("#3a4a3e"))
			draw_rect(Rect2(Vector2(rx, ry), Vector2(float(iw * CELL) - 4, float(ih * CELL) - 4)), Color("#6f8a72"), false, 1.0)
			var label: String = String(d.get("name", "")).substr(0, 6)
			if int(d.get("count", 1)) > 1:
				label += " x%d" % int(d.get("count", 1))
			draw_string(ThemeDB.fallback_font, Vector2(rx + 4, ry + 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#c9c4b8"))
		gy += ph + 12.0
	# drag ghost
	if _drag_item != -1:
		var mp: Vector2 = get_local_mouse_position()
		draw_rect(Rect2(mp + Vector2(-16, -12), Vector2(32, 24)), Color(0.27, 0.34, 0.25, 0.9))
		draw_rect(Rect2(mp + Vector2(-16, -12), Vector2(32, 24)), Color("#6f8a72"), false, 1.0)
