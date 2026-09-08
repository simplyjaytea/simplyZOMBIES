extends Control
# The inventory sheet. One fixed layout, since the owner's 2026-09-08 call (docs/30, "The
# inventory sheet"): the body and its twelve slots on the left, a column of bag grids in a fixed
# order in the middle, a pane of words about one item on the right, and the belt and pockets as a
# quick strip along the bottom.
#
# What this replaced was a desktop: every carried container was its own draggable, pinnable
# window, remembered by label in `user://ui_prefs.json`. That bought pouches usable during play
# and cost a screen where two bags could land on top of each other -- the pockets spent a session
# hidden under a hiking pack, which is why the version before this one had a collision-avoiding
# default-position allocator at all. The strip is what buys the pouches back, and it cannot be
# lost behind anything.
#
# Rules unchanged from the first version of this screen: it reads `SimInventory.inventory_view`
# snapshots, proposes Commands, and the sim decides fit and depth. No numbers except a stack
# count and the strip's key names (docs/10 -- counting discrete objects is not uncertainty being
# collapsed).
#
# All drag state lives here, in one place, and now that is the only place it *could* live: the
# grids are drawn into this one Control rather than being Controls of their own, so a press and
# its release are the same node's business and there is nothing to forward.

const SimInventory = preload("res://sim/modules/inventory.gd")
const SimCondition = preload("res://sim/condition.gd")
const SimTreatment = preload("res://sim/modules/treatment.gd")
const UiText = preload("res://ui/text.gd")
const Palette = preload("res://presentation/palette.gd")
const Paperdoll = preload("res://ui/paperdoll.gd")
const Chrome = preload("res://ui/chrome.gd")
const UiPrefs = preload("res://ui/prefs.gd")
const BagGrid = preload("res://ui/bag_grid.gd")
const InspectPane = preload("res://ui/inspect_pane.gd")
const ItemMenu = preload("res://ui/item_menu.gd")
const QuickStrip = preload("res://ui/quick_strip.gd")

# PartState 0..3 as words. Same four grades the paperdoll tints, never a number.
const PART_STATE_WORDS: Array[String] = ["unhurt", "hurt", "badly hurt", "unusable"]

const PAD: float = 24.0
const GAP: float = 20.0
const STRIP_H: float = 92.0
const BODY_W: float = 660.0
const INSPECT_W: float = 380.0
# The body panel is sized from what is in it -- six slot rows, the prose under them, the hint --
# rather than stretched to the screen, which left a hand's width of nothing under the last line.
# The column and the inspect pane still take the full height, because they have something to put
# in it.
const BODY_H: float = 724.0

# Equipment slot geometry, in one place -- the boxes you can click and the boxes you can see must
# be the same set of rects.
const SLOT_W: float = 190.0
const SLOT_H: float = 58.0
const SLOT_TOP: float = 78.0
const SLOT_STEP: float = 74.0
const SLOT_INSET: float = 16.0
# The figure sits in the gap the two columns leave, and is sized from it rather than by eye: at
# 660 wide with 190-wide slots inset 16, that gap is 248 px. A doll wider than the gap draws its
# own stance word over the belt slot, which is how this number was found.
const DOLL_W: float = 240.0
const DOLL_H: float = 400.0
const DOLL_TOP: float = 62.0
# Twelve slots, six a side, in body order top to bottom: what covers your head down the left,
# what covers your trunk and legs down the right, weapons at the bottom of each.
const LEFT_SLOTS: Array[String] = ["head", "eyes", "face", "gloves", "belt", "primary"]
const RIGHT_SLOTS: Array[String] = ["vest", "torso", "legs", "feet", "back", "secondary"]

# The bag column, in the order it is drawn. Pockets first because they are always there; then what
# is worn, outermost-reachable first. Anything else -- a toolbox inside the pack -- appears only
# once the player has opened it, which is what the `open` verb is for.
const COLUMN_SLOTS: Array[String] = ["belt", "vest", "back"]


var _world: Variant = null
var _actor: int = -1
var _view: Dictionary = {}
var _open: bool = false

var _drag_item: int = -1
var _drag_rotated: bool = false
var _drag_dims: Vector2i = Vector2i.ONE

# What the inspect pane is talking about, and the plate that wears the ring.
var _selected: int = -1
# Nested containers the player has opened, as an Array of item ids rather than a Dictionary keyed
# by one: an Array is what survives a save if this ever moves into one, and it is pruned against
# the view every refresh so a bag that was dropped does not leave a column behind.
var _opened: Array[int] = []

# The word menu: where it is, and what is in it. Rebuilt from `verbs_for` at every right-click and
# cleared on any other press.
var _menu_at: Vector2 = Vector2.ZERO
var _menu_item: int = -1
var _menu_verbs: Array[String] = []

# Clickable words under the condition readout, built by _draw and read by _press_at: {rect, verb}.
# Derived every draw and never stored, which is work_panel.gd's rule and the reason the word you
# can see and the word you can click cannot drift apart.
var _hit: Array[Dictionary] = []

# Where each column was drawn this frame: {at, column}. The hit test walks this rather than
# recomputing the layout, so a click and a plate cannot disagree about where a bag is.
var _placed: Array[Dictionary] = []
var _scroll: float = 0.0

var _paperdoll: Control = null
var _ghost: Control = null
# The bag column is drawn into its own clipped child rather than straight onto the sheet: a deep
# loadout is taller than the screen, and without a clip the last bag paints over the quick strip.
# Input stays with the sheet -- the child ignores the mouse -- so every rect in `_placed` is still
# in sheet coordinates and the hit test needs no second frame of reference.
var _column_layer: Control = null


class Columns:
	extends Control
	# Clips, and nothing else. The drawing lives on the sheet (`_draw_columns`) because that is
	# where the layout and the placement list live; this exists so `clip_contents` has a rect to
	# be true of.

	var panel: Control = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true

	func _draw() -> void:
		if panel != null:
			panel.call("_draw_columns_into", self)


class Ghost:
	extends Control
	# Inner classes do not see the outer script's constants, so the chrome is preloaded again here
	# rather than reached for implicitly.
	const GhostChrome = preload("res://ui/chrome.gd")
	const GHOST_CELL: int = 56

	var panel: Control = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if panel == null or int(panel.get("_drag_item")) == -1:
			return
		var dims: Vector2i = panel.get("_drag_dims") as Vector2i
		if bool(panel.get("_drag_rotated")):
			dims = Vector2i(dims.y, dims.x)
		var px: Vector2 = Vector2(float(dims.x * GHOST_CELL), float(dims.y * GHOST_CELL))
		var at: Vector2 = get_local_mouse_position() - px / 2.0
		GhostChrome.item_plate(self, Rect2(at, px), 0.85)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sync_size()
	_paperdoll = Paperdoll.new()
	_paperdoll.custom_minimum_size = Vector2(DOLL_W, DOLL_H)
	_paperdoll.size = Vector2(DOLL_W, DOLL_H)
	_paperdoll.visible = false
	add_child(_paperdoll)
	var columns := Columns.new()
	columns.panel = self
	_column_layer = columns
	add_child(_column_layer)
	var g := Ghost.new()
	g.panel = self
	_ghost = g
	add_child(_ghost)


func _process(_delta: float) -> void:
	if _drag_item != -1 and _ghost != null:
		_ghost.queue_redraw()


func _sync_size() -> void:
	var view: Vector2 = get_viewport_rect().size
	size = view
	if _ghost != null:
		_ghost.size = view


func is_open() -> bool:
	return _open


func set_open(open: bool) -> void:
	_open = open
	mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
	if not open:
		_cancel_drag()
		_close_menu()
	if _paperdoll != null:
		_paperdoll.visible = open
	_sync_size()
	queue_redraw()


# Settings changed; everything that reads an opacity redraws.
func refresh_style() -> void:
	queue_redraw()


func set_world(world: Variant, actor: int) -> void:
	_world = world
	_actor = actor
	_view = SimInventory.inventory_view(world, actor) if world != null else {}
	_sync_size()
	if world != null and _paperdoll != null:
		var cv: Dictionary = SimCondition.view(world, actor)
		if not cv.is_empty():
			_paperdoll.call("set_view", cv)
	_prune()
	queue_redraw()


func rotate() -> void:
	if _drag_item != -1:
		_drag_rotated = not _drag_rotated
		if _ghost != null:
			_ghost.queue_redraw()


# A number key on the quick strip. The mapping lives here rather than in main.gd so the row you
# can see and the row the key spends are the same list, read once.
func strip_use(index: int) -> void:
	if _world == null or _actor < 0:
		return
	var rows: Array = SimInventory.quick_strip_view(_world, _actor)
	if index < 0 or index >= rows.size():
		return
	_world.commands.push({"type": "item.use", "item": int((rows[index] as Dictionary)["item"])})


# The bag column's labels, top to bottom. The gate's handle on the layout -- and the reason the
# order is asserted rather than assumed, because "pockets, belt, vest, back" is a decision about
# what the player reaches for first and not an accident of `reachable_containers`.
func column_labels() -> Array[String]:
	var out: Array[String] = []
	for column in _columns():
		out.append(String((column as Dictionary).get("label", "")))
	return out


# --- layout -----------------------------------------------------------------------------

func _tall() -> float:
	return get_viewport_rect().size.y - PAD * 2.0 - STRIP_H - GAP


func _body_rect() -> Rect2:
	return Rect2(Vector2(PAD, PAD), Vector2(BODY_W, minf(BODY_H, _tall())))


func _inspect_rect() -> Rect2:
	var view: Vector2 = get_viewport_rect().size
	return Rect2(Vector2(view.x - PAD - INSPECT_W, PAD), Vector2(INSPECT_W, _tall()))


func _column_rect() -> Rect2:
	var body: Rect2 = _body_rect()
	var inspect: Rect2 = _inspect_rect()
	var x: float = body.position.x + body.size.x + GAP
	return Rect2(Vector2(x, PAD), Vector2(maxf(200.0, inspect.position.x - GAP - x), _tall()))


static func slot_rect(body: Rect2, side: int, index: int) -> Rect2:
	var x: float = body.position.x + SLOT_INSET if side == 0 else body.position.x + body.size.x - SLOT_INSET - SLOT_W
	return Rect2(Vector2(x, body.position.y + SLOT_TOP + SLOT_STEP * float(index)), Vector2(SLOT_W, SLOT_H))


# Every slot's name and rect for this frame, so the drawing and the hit test share one list.
func _slot_boxes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var body: Rect2 = _body_rect()
	for i in LEFT_SLOTS.size():
		out.append({"slot": LEFT_SLOTS[i], "rect": slot_rect(body, 0, i)})
	for i in RIGHT_SLOTS.size():
		out.append({"slot": RIGHT_SLOTS[i], "rect": slot_rect(body, 1, i)})
	return out


# The bag column, in its fixed order. Pockets, then the belt, vest and back containers in that
# order, then anything nested the player has opened -- and nothing else, so a toolbox in the pack
# is a bag you chose to look inside rather than a fourth grid that appeared on its own.
func _columns() -> Array:
	var out: Array = []
	if _view.is_empty():
		return out
	var by_id: Dictionary = {}
	for entry in _view.get("containers", []) as Array:
		by_id[int((entry as Dictionary)["container"])] = entry
	if by_id.has(_actor):
		out.append(by_id[_actor])
	var worn: Dictionary = {}
	for entry in _view.get("slots", []) as Array:
		var d: Dictionary = entry as Dictionary
		var it: Variant = d.get("item")
		if it is Dictionary:
			worn[String(d.get("slot", ""))] = int((it as Dictionary).get("item", -1))
	for slot in COLUMN_SLOTS:
		var id: Variant = worn.get(slot)
		if id != null and by_id.has(int(id)):
			out.append(by_id[int(id)])
	for id2 in _opened:
		if by_id.has(int(id2)) and not out.has(by_id[int(id2)]):
			out.append(by_id[int(id2)])
	return out


# A bag that is no longer reachable -- dropped, given away, eaten by a fire -- leaves no column
# behind. Pruned against the view rather than against an event, because the view is the one
# statement of what is carried and an event would be a second one to keep in step.
func _prune() -> void:
	var live: Dictionary = {}
	for entry in _view.get("containers", []) as Array:
		live[int((entry as Dictionary)["container"])] = true
	var kept: Array[int] = []
	for id in _opened:
		if live.has(int(id)):
			kept.append(int(id))
	_opened = kept
	if _selected != -1 and _world != null and not SimInventory.owns(_world, _actor, _selected):
		_selected = -1
	if _menu_item != -1 and _world != null and not SimInventory.owns(_world, _actor, _menu_item):
		_close_menu()


# --- input ------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not _open or _world == null or _view.is_empty():
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_scroll = minf(_scroll + 56.0, maxf(0.0, _column_height() - _column_rect().size.y))
			queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_scroll = maxf(0.0, _scroll - 56.0)
			queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_press_at(mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_release_at(mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_right_at(mb.position)
			accept_event()


func _press_at(p: Vector2) -> void:
	if _world == null or _view.is_empty():
		return
	# The menu first: it is drawn over everything, so it has to be tested before everything.
	if _menu_item != -1:
		for row in ItemMenu.verb_rects(_menu_at, _menu_verbs):
			if (row["rect"] as Rect2).has_point(p):
				_act(String(row["verb"]), _menu_item)
				_close_menu()
				return
		_close_menu()
		return
	# Then the clickable words, for work_panel.gd's reason: they sit inside the body panel the
	# slot maths also covers, so whichever target is more specific has to win.
	for h in _hit:
		if (h["rect"] as Rect2).has_point(p):
			# Through the queue like every other player act, and with no patient named: the intake
			# defaults it to the player (treatment.gd's `infection.respond` arm), which is the same
			# "one key, one obvious target" rule the T key already follows.
			_world.commands.push({"type": "infection.respond", "verb": String(h.get("verb", ""))})
			return
	# An equipment slot: lift the item out of it.
	for box in _slot_boxes():
		if not (box["rect"] as Rect2).has_point(p):
			continue
		var it: Variant = _slot_item(String(box["slot"]))
		if it is Dictionary:
			# The item, not just the slot: a slot name on its own does not say whose coat this is,
			# and inventory.intake used to act on everybody's.
			var id: int = int((it as Dictionary).get("item", -1))
			_selected = id
			_begin_drag(id, false, Vector2i(1, 1))
			_world.commands.push({"type": "item.unequip", "slot": String(box["slot"]), "item": id})
		return
	# A grid cell.
	var found: Variant = _item_under(p)
	if found is Dictionary:
		var d: Dictionary = found as Dictionary
		var dims := Vector2i(int(d.get("w", 1)), int(d.get("h", 1)))
		var rotated: bool = bool(d.get("rotated", false))
		if rotated:
			dims = Vector2i(dims.y, dims.x)
		_selected = int(d.get("item", -1))
		_begin_drag(int(d.get("item", -1)), rotated, dims)
		return
	_selected = -1
	queue_redraw()


func _release_at(p: Vector2) -> void:
	if _drag_item == -1 or _world == null:
		return
	var item: int = _drag_item
	var rotated: bool = _drag_rotated
	_cancel_drag()
	for box in _slot_boxes():
		if (box["rect"] as Rect2).has_point(p):
			_world.commands.push({"type": "item.equip", "item": item, "slot": String(box["slot"])})
			queue_redraw()
			return
	for placed in _placed:
		var at: Vector2 = placed["at"] as Vector2
		var column: Dictionary = placed["column"] as Dictionary
		var cell: Variant = BagGrid.cell_at(at, column, p)
		if cell == null:
			continue
		# Propose the move; the sim decides depth, fit and cycle.
		_world.commands.push({"type": "item.move", "item": item, "container": int(column.get("container", -1)), "x": (cell as Vector2i).x, "y": (cell as Vector2i).y, "rotated": rotated})
		queue_redraw()
		return
	# Dropped on nothing: no op. The item stays where it is until a command lands, which is what
	# makes a mis-drag cost nothing.
	queue_redraw()


func _right_at(p: Vector2) -> void:
	if _drag_item != -1:
		rotate()
		return
	var found: Variant = _item_under(p)
	if not (found is Dictionary):
		# A slot's contents can be reasoned about too -- that is where "unequip" lives.
		for box in _slot_boxes():
			if (box["rect"] as Rect2).has_point(p):
				var it: Variant = _slot_item(String(box["slot"]))
				if it is Dictionary:
					_open_menu(p, int((it as Dictionary).get("item", -1)))
				return
		_close_menu()
		return
	_open_menu(p, int((found as Dictionary).get("item", -1)))


func _open_menu(p: Vector2, item: int) -> void:
	if _world == null or item < 0:
		return
	var verbs: Array[String] = SimInventory.verbs_for(_world, _actor, item)
	if verbs.is_empty():
		_close_menu()
		return
	_selected = item
	_menu_item = item
	_menu_verbs = verbs
	# Nudged back onto the screen rather than clipped: a menu half off the right edge is a menu
	# with rows nobody can click.
	var view: Vector2 = get_viewport_rect().size
	var box: Vector2 = ItemMenu.size_of(verbs)
	_menu_at = Vector2(minf(p.x, view.x - box.x - 8.0), minf(p.y, view.y - box.y - 8.0))
	queue_redraw()


func _close_menu() -> void:
	_menu_item = -1
	_menu_verbs = []
	queue_redraw()


# What a menu word does. Every one of these is a command through the queue, except the two that
# are questions about the screen rather than about the world: `inspect` picks what the pane talks
# about, and `open` decides whether a nested bag gets a column.
func _act(verb: String, item: int) -> void:
	if _world == null:
		return
	match verb:
		"equip":
			_world.commands.push({"type": "item.equip", "item": item})
		"unequip":
			_world.commands.push({"type": "item.unequip", "slot": _slot_of(item), "item": item})
		"use":
			_world.commands.push({"type": "item.use", "item": item})
		"drop":
			_world.commands.push({"type": "item.drop", "item": item})
		"split":
			_world.commands.push({"type": "item.split", "item": item, "count": maxi(1, _count_of(item) / 2)})
		"open":
			if _opened.has(item):
				_opened.erase(item)
			else:
				_opened.append(item)
		"inspect":
			_selected = item
	queue_redraw()


func _slot_of(item: int) -> String:
	for entry in _view.get("slots", []) as Array:
		var d: Dictionary = entry as Dictionary
		var it: Variant = d.get("item")
		if it is Dictionary and int((it as Dictionary).get("item", -1)) == item:
			return String(d.get("slot", ""))
	return ""


func _count_of(item: int) -> int:
	for column in _columns():
		for entry in (column as Dictionary).get("items", []) as Array:
			if int((entry as Dictionary).get("item", -1)) == item:
				return int((entry as Dictionary).get("count", 1))
	return 1


func _slot_item(slot: String) -> Variant:
	for entry in _view.get("slots", []) as Array:
		var d: Dictionary = entry as Dictionary
		if String(d.get("slot", "")) == slot:
			return d.get("item")
	return null


# The item view under a point, across every drawn grid, or null.
func _item_under(p: Vector2) -> Variant:
	for placed in _placed:
		var at: Vector2 = placed["at"] as Vector2
		var column: Dictionary = placed["column"] as Dictionary
		var cell: Variant = BagGrid.cell_at(at, column, p)
		if cell == null:
			continue
		return BagGrid.item_at(column, cell as Vector2i)
	return null


func _begin_drag(item: int, rotated: bool, dims: Vector2i) -> void:
	_drag_item = item
	_drag_rotated = rotated
	_drag_dims = dims
	_close_menu()
	queue_redraw()


func _cancel_drag() -> void:
	_drag_item = -1
	_drag_rotated = false
	if _ghost != null:
		_ghost.queue_redraw()


func _column_height() -> float:
	var total: float = 0.0
	for column in _columns():
		var d: Dictionary = column as Dictionary
		total += BagGrid.size_of(int(d.get("w", 0)), int(d.get("h", 0))).y + GAP
	return maxf(0.0, total - GAP)


# --- drawing ----------------------------------------------------------------------------

func _draw() -> void:
	# Cleared before the early returns, not inside the body: a closed screen has no clickable
	# words and no placed grids, and rects left over from the last frame it was open would still
	# be hit-testable.
	_hit.clear()
	_placed.clear()
	if not _open:
		return
	var view: Vector2 = get_viewport_rect().size
	var dim: Color = Chrome.FIELD
	dim.a = 0.88
	draw_rect(Rect2(Vector2.ZERO, view), dim)
	var alpha: float = UiPrefs.opacity("inventory_opacity")
	var font: Font = Chrome.font()
	if _view.is_empty():
		draw_string(font, Vector2(PAD, PAD + 32.0), "no inventory", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Chrome.TEXT_DIM)
		return
	_draw_body(font, alpha)
	if _column_layer != null:
		var area: Rect2 = _column_rect()
		_column_layer.position = area.position
		_column_layer.size = area.size
		_column_layer.queue_redraw()
	InspectPane.draw_pane(self, _inspect_rect(), _inspect_view(), alpha)
	QuickStrip.draw_strip(self, QuickStrip.rect_for(view, PAD, STRIP_H), SimInventory.quick_strip_view(_world, _actor) if _world != null else [], alpha)
	ItemMenu.draw_menu(self, _menu_at, _menu_verbs, alpha)


func _inspect_view() -> Dictionary:
	if _world == null or _selected < 0:
		return {}
	return SimInventory.inspect_view(_world, _actor, _selected)


func _draw_body(font: Font, alpha: float) -> void:
	var body: Rect2 = _body_rect()
	Chrome.panel(self, body, alpha)
	Chrome.header(self, body, "survivor", alpha)
	# One screen (the owner's call, 2026-08-19): the doll carries injuries and armour, the slots
	# flank it, and anything wrong with the body reads as prose below the figure.
	_paperdoll.position = Vector2(body.position.x + body.size.x / 2.0 - DOLL_W / 2.0, body.position.y + DOLL_TOP)
	_paperdoll.visible = true
	for box in _slot_boxes():
		var rect: Rect2 = box["rect"] as Rect2
		var it: Variant = _slot_item(String(box["slot"]))
		draw_rect(rect, Chrome.SLOT_EMPTY)
		draw_rect(rect, Chrome.PANEL_EDGE, false, 2.0)
		draw_string(font, rect.position + Vector2(10.0, 18.0), String(box["slot"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Chrome.TEXT_DIM)
		if it is Dictionary:
			var name: String = UiText.fit(font, String((it as Dictionary).get("name", "")), 18, SLOT_W - 20.0)
			draw_string(font, rect.position + Vector2(10.0, 44.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Chrome.TEXT)
		else:
			draw_string(font, rect.position + Vector2(10.0, 44.0), "nothing", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(Chrome.TEXT_DIM, 0.7))
	# The condition readout: only the parts with something to say, as prose under the doll. Same
	# read model as the doll's tints and the HUD -- states and words, never a number (docs/01
	# clause 4; check_ban_health_bar.gd).
	var lines: Array = _condition_lines()
	# Below the last slot row rather than beside the figure: the two columns leave 248 px in the
	# middle and "left arm - badly hurt - bleeding" is twice that, so a line centred on the panel
	# ran under both columns of boxes.
	var ly: float = body.position.y + SLOT_TOP + SLOT_STEP * float(LEFT_SLOTS.size()) + 44.0
	var cx: float = body.position.x + body.size.x / 2.0
	if lines.is_empty():
		var none: String = "no injuries"
		draw_string(font, Vector2(cx - font.get_string_size(none, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x / 2.0, ly), none, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Chrome.TEXT_DIM)
	else:
		for line in lines:
			var d2: Dictionary = line as Dictionary
			var text: String = String(d2["text"])
			var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			draw_string(font, Vector2(cx - tw / 2.0, ly), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, d2["colour"] as Color)
			ly += 28.0
	_draw_responses(font, body, ly + 10.0)
	var hint: String = "drag between bags · right-click for what you can do · R turns it"
	draw_string(font, Vector2(body.position.x + SLOT_INSET, body.position.y + body.size.y - 22.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Chrome.TEXT_DIM)


# Called by the clipped child, and drawing into it: `at` is built in sheet coordinates so the
# placement list the hit test walks is the same arithmetic, then shifted by the child's own origin
# at the moment of drawing. One layout, two frames of reference, and the translation is one line.
func _draw_columns_into(ci: CanvasItem) -> void:
	var alpha: float = UiPrefs.opacity("inventory_opacity")
	var area: Rect2 = _column_rect()
	_placed.clear()
	var y: float = area.position.y - _scroll
	var origin_for_selected: Variant = null
	for column in _columns():
		var d: Dictionary = column as Dictionary
		var box: Vector2 = BagGrid.size_of(int(d.get("w", 0)), int(d.get("h", 0)))
		var at := Vector2(area.position.x, y)
		# Only what is on screen, so a deep loadout scrolls rather than painting under the strip.
		if at.y + box.y > area.position.y and at.y < area.position.y + area.size.y:
			var note: String = ""
			if int(d.get("container", -1)) == _actor:
				note = "on you"
			elif _opened.has(int(d.get("container", -1))):
				note = "opened"
			BagGrid.draw_bag(ci, at - area.position, d, alpha, _drag_item, note, _world)
			var sel: Variant = _selected_in(d)
			if sel is Dictionary:
				origin_for_selected = {"origin": BagGrid.origin_of(at - area.position), "item": sel}
		_placed.append({"at": at, "column": d})
		y += box.y + GAP
	# There is no scrollbar on this screen and there is not going to be one, so the one thing the
	# wheel does has to be said out loud when it matters.
	if _column_height() > area.size.y:
		var font: Font = Chrome.font()
		var note: String = "wheel to scroll"
		var nw: float = font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		ci.draw_string(font, Vector2(area.size.x - nw, area.size.y - 6.0), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Chrome.TEXT_DIM)
	# The selection ring last, so it is never painted over by the next bag's panel.
	if origin_for_selected is Dictionary:
		var o: Dictionary = origin_for_selected as Dictionary
		BagGrid.draw_item(ci, o["origin"] as Vector2, o["item"] as Dictionary, alpha, true, _world)


func _selected_in(column: Dictionary) -> Variant:
	if _selected < 0:
		return null
	for entry in column.get("items", []) as Array:
		if int((entry as Dictionary).get("item", -1)) == _selected:
			return entry
	return null


# What you could do about an infection, under the body it is in. One clickable word per offered
# response, in work_panel.gd's idiom exactly: the sim decides what is on offer
# (`SimTreatment.response_view`), a response you can afford is simply *there* in the accent colour,
# and one you cannot is absent rather than greyed with a reason beside it. Amber is chrome.gd's one
# colour for the thing that matters, and on this screen an answer to a fever is that thing.
#
# No numbers reach here and none could: the view carries a verb and a sentence, which is the same
# contract the condition readout above it has (docs/01 clause 4, check_ban_health_bar.gd).
func _draw_responses(font: Font, body: Rect2, y: float) -> void:
	if _world == null:
		return
	var rows: Array = SimTreatment.response_view(_world, _actor)
	if rows.is_empty():
		return
	var lead: String = "you could "
	var sep: String = " · "
	# Centred by measurement, the way the condition lines above are, rather than nudged by a
	# constant: a second response one day must not push the first off centre.
	var total: float = font.get_string_size(lead, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	for i in rows.size():
		total += font.get_string_size(String((rows[i] as Dictionary).get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		if i < rows.size() - 1:
			total += font.get_string_size(sep, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var at: float = body.position.x + body.size.x / 2.0 - total / 2.0
	draw_string(font, Vector2(at, y), lead, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Chrome.TEXT_DIM)
	at += font.get_string_size(lead, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	for i in rows.size():
		var row: Dictionary = rows[i] as Dictionary
		var word: String = String(row.get("text", ""))
		draw_string(font, Vector2(at, y), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Chrome.ACCENT)
		_hit.append({"rect": _word_rect(font, Vector2(at, y), word, 20), "verb": String(row.get("verb", ""))})
		at += font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		if i < rows.size() - 1:
			draw_string(font, Vector2(at, y), sep, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Chrome.TEXT_DIM)
			at += font.get_string_size(sep, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x


# The one place a word's extent is measured, so the rectangle that is drawn and the rectangle that
# is clicked cannot drift apart. Same shape as work_panel.gd's, which set the convention.
func _word_rect(font: Font, at: Vector2, word: String, font_size: int) -> Rect2:
	var w: float = font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	return Rect2(Vector2(at.x, at.y - float(font_size) * 0.8), Vector2(w, float(font_size) * 1.15))


# One prose line per part that has anything to report: "left arm — badly hurt · bleeding".
func _condition_lines() -> Array:
	var out: Array = []
	if _world == null:
		return out
	for entry in (SimCondition.view(_world, _actor).get("parts", []) as Array):
		var d: Dictionary = entry as Dictionary
		var st: int = int(d.get("state", 0))
		var tags: Array[String] = []
		# One tag for the wound, not three: an open wound is "bleeding", a dressed one is named by
		# its dressing, and a wound that is neither is just "wound".
		var dressing: String = String(d.get("bandage", "none"))
		if bool(d.get("bleeding", false)):
			tags.append("bleeding")
		elif dressing != "none":
			tags.append(dressing + " dressing")
		elif bool(d.get("wounded", false)):
			tags.append("wound")
		var infected: String = String(d.get("infected", "none"))
		if infected != "none":
			tags.append(infected)
		# What an old injury left behind: "left leg · limp" on a leg that has long since healed.
		var lasting: String = String(d.get("lasting", "none"))
		if lasting != "none":
			tags.append(lasting)
		if st == 0 and tags.is_empty():
			continue
		var word: String = PART_STATE_WORDS[st] if st < PART_STATE_WORDS.size() else ""
		var text: String = SimCondition.label_of(String(d.get("part", "")))
		if st > 0:
			text += " — " + word
		if not tags.is_empty():
			text += " · " + " · ".join(tags)
		var colour: Color = Palette.CONDITION_TINTS[st] if st < Palette.CONDITION_TINTS.size() else Chrome.TEXT
		out.append({"text": text, "colour": colour})
	return out
